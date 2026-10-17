--!strict
-- Montarias: mostra, embaixo de cada jogador, a montaria que ele escolheu (atributo "Mount")
-- quando ele está montado (atributo "Riding", ligado e desligado na tecla M ou no botão RIDE).
-- É só visual: o modelo acompanha o boneco, flutua, costura de um lado para o outro, inclina
-- nas curvas e, no tapete, os gomos ondulam. No pulo, o skate dá um kickflip e o tapete empina.
-- No jogador local, o boneco sobe um pouco (HipHeight) e ganha uma pose animada a cada quadro:
-- no skate, surfando de lado, bombeando os joelhos e equilibrando com os braços; no tapete,
-- sentado de pernas cruzadas parado e de pé, surfando a onda, em movimento.
-- Some durante a carga e a corrida no corredor.
-- Os modelos vêm prontos do servidor em ReplicatedStorage.Mounts (src/server/Mounts.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Pose = require(script.Parent.Pose)
local Run = require(script.Parent.Run)
local Ui = require(script.Parent.Ui)

local localPlayer = Players.LocalPlayer
local MOUNT = Config.Mount
local deg = Pose.deg

local Mount = {}

type Piece = { part: BasePart, offset: CFrame, segment: number?, z: number }
type Ride = {
	id: string,
	info: any,
	model: Model,
	pieces: { Piece },
	segments: number,
	shown: boolean,
	y: number,
	moving: number, -- 0 parado, 1 andando, suavizado
	turn: number, -- inclinação de curva, -1 a 1, suavizada
	yaw: number?, -- direção do boneco no quadro anterior
	air: number, -- segundos no ar (0 no chão)
	last: number,
}

local rides: { [Player]: Ride } = {}
-- HipHeight original do boneco local (antes de subir na montaria)
local baseHip: number? = nil
local hipHumanoid: Humanoid? = nil
local lifted = 0

local function clear(player: Player)
	local ride = rides[player]
	if ride then
		ride.model:Destroy()
		rides[player] = nil
	end
end

local function equip(player: Player)
	clear(player)
	-- "Mount" é a escolhida no menu; "Riding" diz se está em cima dela (tecla M)
	local id = player:GetAttribute("Mount")
	local info = if type(id) == "string" and player:GetAttribute("Riding") == true then Config.MountById[id] else nil
	local folder = ReplicatedStorage:FindFirstChild("Mounts")
	local template = info and folder and folder:FindFirstChild(info.id)
	if not info or not template or not template:IsA("Model") then
		return
	end
	local model = template:Clone()
	local pivot = model:GetPivot()
	local pieces: { Piece } = {}
	local segments = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local segment = part:GetAttribute("Segment")
			if type(segment) == "number" then
				segments = math.max(segments, segment)
			end
			table.insert(pieces, { part = part, offset = pivot:ToObjectSpace(part.CFrame), segment = if type(segment) == "number" then segment else nil, z = 0 })
		end
	end
	-- centro de cada gomo ao longo do comprimento (média das peças dele)
	local sum: { [number]: number }, count: { [number]: number } = {}, {}
	for _, piece in pieces do
		if piece.segment then
			sum[piece.segment] = (sum[piece.segment] or 0) + piece.offset.Position.Z
			count[piece.segment] = (count[piece.segment] or 0) + 1
		end
	end
	for _, piece in pieces do
		if piece.segment then
			piece.z = sum[piece.segment] / count[piece.segment]
		end
	end
	model.Name = "Mount_" .. player.Name
	rides[player] = { id = info.id, info = info, model = model, pieces = pieces, segments = segments, shown = false, y = 0, moving = 0, turn = 0, yaw = nil, air = 0, last = os.clock() }
end

---------------------------------------------------------------------------------------------------
-- Poses animadas (só o boneco local). Recebem o tempo e o estado do passeio.

-- Vai e vem da costura: o mesmo valor inclina a montaria e o corpo.
local function carveOf(ride: Ride, now: number): number
	return math.sin(now * MOUNT.carveSpeed) * math.min(ride.moving, 1) + math.sin(now * 1.3) * 0.18
end

local function mix(a: { [string]: CFrame }, b: { [string]: CFrame }, alpha: number): { [string]: CFrame }
	local out = {}
	for joint, pose in a do
		out[joint] = pose:Lerp(b[joint] or pose, alpha)
	end
	return out
end

-- Skate: de lado, costurando; joelhos bombeando, braços abertos acompanhando a curva. No ar,
-- encolhe as pernas e abre os braços enquanto o shape gira.
local function boardPose(ride: Ride, now: number): { [string]: CFrame }
	local m = math.min(ride.moving, 1.3)
	local carve = carveOf(ride, now)
	local lean = carve * MOUNT.carve + ride.turn * MOUNT.turnLean
	local pump = math.sin(now * MOUNT.carveSpeed * 2) * m
	local wobble = math.sin(now * 3.1)
	local tuck = math.clamp(ride.air / 0.15, 0, 1) * (1 - math.clamp((ride.air - 0.45) / 0.25, 0, 1))
	local crouch = 16 + 16 * m + 7 * pump + 34 * tuck
	return {
		Root = CFrame.new(0, -0.16 - 0.14 * m - 0.05 * pump - 0.3 * tuck, 0) * deg(-5 * m, 0, lean) * deg(0, -68, 0),
		Waist = deg(4 + 7 * m + 10 * tuck, 28 + 8 * carve, -lean * 0.5),
		Neck = deg(-4 * m, 36 - 6 * carve, lean * 0.3),
		RightHip = deg(crouch, 0, 15 + 4 * carve),
		LeftHip = deg(crouch * 0.85, 0, -15 + 4 * carve),
		RightKnee = deg(-crouch * 1.9, 0, 0),
		LeftKnee = deg(-crouch * 1.7, 0, 0),
		RightAnkle = deg(crouch * 0.9, 0, 0),
		LeftAnkle = deg(crouch * 0.8, 0, 0),
		RightShoulder = deg(-14 * carve + 20 * tuck, 0, 62 + 22 * carve + 6 * wobble + 30 * tuck),
		LeftShoulder = deg(14 * carve + 20 * tuck, 0, -(60 - 22 * carve) - 6 * math.sin(now * 3.1 + 1.3) - 30 * tuck),
		RightElbow = deg(16 + 14 * math.abs(carve) + 8 * wobble, 0, 0),
		LeftElbow = deg(16 + 14 * math.abs(carve) - 8 * wobble, 0, 0),
	}
end

-- Tapete: parado, sentado de pernas cruzadas, respirando e balançando de leve; andando, fica de
-- pé e surfa a onda do tapete, com o corpo subindo e descendo junto do gomo em que pisa.
local function carpetPose(ride: Ride, now: number): { [string]: CFrame }
	local m = math.clamp(ride.moving, 0, 1)
	local carve = carveOf(ride, now)
	local lean = carve * MOUNT.carve * 0.8 + ride.turn * MOUNT.turnLean
	local amp = MOUNT.waveIdle + (MOUNT.wave - MOUNT.waveIdle) * m
	local wave = math.sin(now * MOUNT.waveSpeed) * amp -- altura do gomo do meio, onde o boneco está
	local breath = math.sin(now * 1.8)
	local sit = {
		Root = CFrame.new(0, -1.5 + wave, 0) * deg(-4 + 1.5 * breath, 8 * math.sin(now * 0.7), 3 * math.sin(now * 1.1)),
		Waist = deg(-4 + 2 * breath, 0, 0),
		Neck = deg(4, 14 * math.sin(now * 0.7 + 0.6), 0),
		RightHip = deg(84, 0, 32),
		LeftHip = deg(84, 0, -32),
		RightKnee = deg(-118, 0, 0),
		LeftKnee = deg(-118, 0, 0),
		RightAnkle = deg(0, 0, 0),
		LeftAnkle = deg(0, 0, 0),
		RightShoulder = deg(52 + 2 * breath, 0, -26),
		LeftShoulder = deg(52 + 2 * breath, 0, 26),
		RightElbow = deg(96, 0, 0),
		LeftElbow = deg(96, 0, 0),
	}
	local bend = 22 + 9 * math.sin(now * MOUNT.waveSpeed + 0.8) + 20 * math.clamp(ride.air / 0.2, 0, 1)
	local surf = {
		Root = CFrame.new(0, -0.24 + wave - 0.004 * bend, 0) * deg(-9, 0, lean) * deg(0, -44, 0),
		Waist = deg(8, 20 + 8 * carve, -lean * 0.5),
		Neck = deg(-6, 22 - 6 * carve, 0),
		RightHip = deg(bend, 0, 17),
		LeftHip = deg(bend * 0.8, 0, -17),
		RightKnee = deg(-bend * 1.9, 0, 0),
		LeftKnee = deg(-bend * 1.6, 0, 0),
		RightAnkle = deg(bend * 0.9, 0, 0),
		LeftAnkle = deg(bend * 0.8, 0, 0),
		RightShoulder = deg(-10 * carve, 0, 70 + 20 * carve + 7 * math.sin(now * 2.7)),
		LeftShoulder = deg(24 + 10 * carve, 0, -44 + 20 * carve - 7 * math.sin(now * 2.7 + 1)),
		RightElbow = deg(18 + 10 * math.sin(now * 2.7), 0, 0),
		LeftElbow = deg(30 - 10 * math.sin(now * 2.7), 0, 0),
	}
	local alpha = m * m * (3 - 2 * m) -- levanta e senta suave
	return mix(sit, surf, alpha)
end

local POSES: { [string]: (Ride, number) -> { [string]: CFrame } } = {
	hoverboard = boardPose,
	carpet = carpetPose,
}

-- Boneco local: sobe na montaria (HipHeight) e liga a pose dela; desce e desliga ao sair.
local function setLocal(humanoid: Humanoid?, ride: Ride?, now: number)
	if humanoid ~= hipHumanoid then
		hipHumanoid, baseHip, lifted = humanoid, if humanoid then humanoid.HipHeight else nil, 0
	end
	local lift = if ride then ride.info.lift else 0
	if humanoid and baseHip and lift ~= lifted then
		lifted = lift
		humanoid.HipHeight = baseHip + lift
	end
	for _, other in Config.Mounts do
		local on = ride ~= nil and other.id == ride.id
		if on and ride and POSES[other.id] then
			Pose.define("mount_" .. other.id, POSES[other.id](ride, now))
		end
		Pose.weight("mount_" .. other.id, if on then 1 else 0)
	end
end

local function update(player: Player, ride: Ride, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local busy = player:GetAttribute("Racing") == true or (player == localPlayer and Run.isBusy())
	local visible = humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart") and not busy
	local dt = math.clamp(now - ride.last, 0, 0.1)
	ride.last = now
	if not visible or not humanoid or not root or not root:IsA("BasePart") then
		if player == localPlayer then
			setLocal(humanoid, nil, now)
		end
		if ride.shown then
			ride.shown = false
			ride.model.Parent = nil
		end
		return
	end
	if not ride.shown then
		ride.shown = true
		ride.yaw = nil
		ride.model.Parent = workspace
	end

	-- estado do passeio: velocidade, curva e tempo no ar, suavizados
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local yaw = math.atan2(-flat.X, -flat.Z)
	local rate = 0
	if ride.yaw and dt > 0 then
		rate = ((yaw - ride.yaw + math.pi) % (2 * math.pi) - math.pi) / dt
	end
	ride.yaw = yaw
	local blend = 1 - math.exp(-8 * dt)
	ride.moving += (math.clamp(speed / 16, 0, 1.6) - ride.moving) * blend
	ride.turn += (math.clamp(-rate / 5, -1, 1) - ride.turn) * blend
	ride.air = if humanoid.FloorMaterial == Enum.Material.Air then ride.air + dt else 0

	if player == localPlayer then
		setLocal(humanoid, ride, now)
	end

	-- pés do boneco: nos outros jogadores o HipHeight lido aqui é o original (a mudança é local)
	local hip = if player == localPlayer and baseHip then baseHip else humanoid.HipHeight
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + hip, 0)
	local bob = math.sin(now * MOUNT.bobSpeed) * MOUNT.bob
	local carve = carveOf(ride, now)
	local roll = math.rad(carve * MOUNT.carve + ride.turn * MOUNT.turnLean)
	local pitch = math.rad(-MOUNT.pitch) * ride.moving
	local flip = 0
	if ride.air > 0 then
		if ride.info.flip then
			-- kickflip: uma volta em torno do comprimento, com o bico levantado
			local t = math.clamp(ride.air / MOUNT.flipTime, 0, 1)
			flip = (t * t * (3 - 2 * t)) * math.pi * 2
			pitch += math.rad(MOUNT.airPitch) * math.sin(t * math.pi)
		else
			pitch += math.rad(MOUNT.airPitch) * math.clamp(ride.air / 0.2, 0, 1)
		end
	end
	local base = CFrame.lookAt(feet + Vector3.new(0, bob, 0), feet + Vector3.new(0, bob, 0) + flat)
		* CFrame.Angles(0, math.rad(-carve * MOUNT.carveYaw), 0)
		* CFrame.Angles(pitch, 0, roll + flip)
	ride.y = base.Position.Y

	local amp = (MOUNT.waveIdle + (MOUNT.wave - MOUNT.waveIdle) * math.min(ride.moving, 1)) * (if ride.air > 0 then 1.8 else 1)
	local parts, frames = table.create(#ride.pieces), table.create(#ride.pieces)
	for i, piece in ride.pieces do
		local cframe = base
		if piece.segment then
			-- onda que corre pelo comprimento; cada gomo sobe, desce e inclina com ela
			local phase = now * MOUNT.waveSpeed + piece.z * MOUNT.waveStep
			cframe = base * CFrame.new(0, math.sin(phase) * amp, piece.z) * CFrame.Angles(math.cos(phase) * amp * MOUNT.waveTilt, 0, 0) * CFrame.new(0, 0, -piece.z) * piece.offset
		else
			cframe = base * piece.offset
		end
		parts[i], frames[i] = piece.part, cframe
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function watch(player: Player)
	for _, name in { "Mount", "Riding" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			equip(player)
		end)
	end
	equip(player)
end

-- Sobe ou desce da montaria escolhida (o servidor decide e marca "Riding").
local function ride()
	local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Mount")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer("ride")
	end
end
Mount.ride = ride

-- No celular: botão RIDE acima do DASH, só com uma montaria escolhida.
local function touchButton()
	if not UserInputService.TouchEnabled then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RideButton"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	local button = Instance.new("TextButton")
	button.Name = "RideButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -110, 1, -194)
	button.Size = UDim2.fromOffset(64, 64)
	button.BackgroundColor3 = Color3.fromRGB(30, 34, 54)
	button.BackgroundTransparency = 0.25
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 18
	button.TextColor3 = Color3.new(1, 1, 1)
	Ui.corner(button, 32)
	Ui.border(button, 3)
	Ui.stroke(button, 2)
	button.Activated:Connect(ride)
	button.Parent = gui
	local function refresh()
		local id = localPlayer:GetAttribute("Mount")
		button.Visible = type(id) == "string" and id ~= ""
		button.Text = if localPlayer:GetAttribute("Riding") == true then "OFF" else "RIDE"
	end
	localPlayer:GetAttributeChangedSignal("Mount"):Connect(refresh)
	localPlayer:GetAttributeChangedSignal("Riding"):Connect(refresh)
	refresh()
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Estado da montaria do jogador local; usado pelos testes.
function Mount.debug(): { [string]: any }
	local ride = rides[localPlayer]
	local shoulder = Pose.transform("RightShoulder")
	local _, _, arm = (shoulder or CFrame.identity):ToEulerAnglesXYZ()
	return {
		arm = math.deg(arm), -- abertura do braço direito agora, em graus
		id = if ride then ride.id else "",
		shown = ride ~= nil and ride.shown,
		pieces = if ride then #ride.pieces else 0,
		segments = if ride then ride.segments else 0,
		lift = lifted,
		hip = if hipHumanoid then hipHumanoid.HipHeight else 0,
		baseHip = baseHip or 0,
		height = if ride and ride.shown then ride.y else 0,
		moving = if ride then ride.moving else 0,
		air = if ride then ride.air else 0,
	}
end

function Mount.start()
	-- as juntas de cada camada são recalculadas a cada quadro em setLocal
	for _, info in Config.Mounts do
		Pose.define("mount_" .. info.id, {}, false, 10)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			ride()
		end
	end)
	touchButton()

	task.spawn(function()
		-- os modelos chegam quando o servidor termina de carregar
		local folder = ReplicatedStorage:WaitForChild("Mounts", 120)
		if not folder then
			return
		end
		Players.PlayerAdded:Connect(watch)
		Players.PlayerRemoving:Connect(clear)
		for _, player in Players:GetPlayers() do
			watch(player)
		end
		RunService:BindToRenderStep("Mounts", Enum.RenderPriority.Camera.Value - 1, function()
			local now = os.clock()
			for player, ride in rides do
				update(player, ride, now)
			end
			if not rides[localPlayer] then
				local character = localPlayer.Character
				setLocal(character and character:FindFirstChildOfClass("Humanoid"), nil, now)
			end
		end)
	end)
end

return Mount
