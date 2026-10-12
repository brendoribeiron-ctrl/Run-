--!strict
-- Carga e corrida no cliente: só encenação. O servidor diz quantas paredes quebram e o que saiu.
-- Sequência: carregar (câmera de frente, cubos, tremor) -> corte seco para a corrida (linhas de
-- velocidade, FOV aberto, paredes estourando) -> falha -> tela preta -> roleta.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local RunMath = require(ReplicatedStorage.Shared.RunMath)
local Aura = require(script.Parent.Aura)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Pose = require(script.Parent.Pose)
local Roll = require(script.Parent.Roll)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local P = Config.Palette
local RUN = Config.Run
local LINES = Config.SpeedLines
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local rng = Random.new()

local Run = {}

local state = "idle" -- idle | charging | waiting | running
local chargeStart = 0
local chargeRemote: RemoteEvent

local pill: TextButton
local chargeBar: Frame
local chargeFill: Frame
local chargeLabel: TextLabel
local chargeTier: TextLabel
local distanceBar: Frame
local marker: Frame
local multiplier: TextLabel
local linesGui: ScreenGui
-- dist = posição no caminho centro->borda (0-1); pace = ritmo próprio da linha
type Line = { frame: Frame, angle: number, dist: number, pace: number, thick: number, white: boolean }
local lines: { Line } = {}
local linesAlpha = 0 -- opacidade geral agora
local linesTarget = 0 -- 1 durante a corrida, 0 fora dela
local linesPower = 0 -- progresso da corrida (0-1)
local linesPulse = 0 -- reforço que decai depois de cada parede
local goButton: GuiObject?
local popup: TextLabel

local cubes: { Part } = {}
local ring: Part
local stripes: { Part } = {}
local tint: ColorCorrectionEffect
local hidden: { BasePart } = {}
local barScale: UIScale
local nextRing = 0
local streakDebt = 0
local lastTier = -1
local maxed = false
local core: Part
local crescents: { { a0: Attachment, a1: Attachment, beam: Beam } } = {}
local convergeDebt = 0
local rayDebt = 0
local smashStart = -10
local smashRight = false
local fovKick = 0
local lineColor = Color3.fromRGB(255, 250, 235)

local function character(): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return model, root, humanoid
	end
	return nil, nil, nil
end

local function inZone(root: BasePart): boolean
	return math.abs(root.Position.X - RUN.zoneCenter.X) <= RUN.zoneSize.X / 2
		and math.abs(root.Position.Z - RUN.zoneCenter.Z) <= RUN.zoneSize.Y / 2
end

local function tierColor(tier: number): Color3
	return if tier >= 1 then Config.Rarities[tier].color else Color3.fromRGB(150, 150, 160)
end

---------------------------------------------------------------------------------------------------
-- Interface da corrida

local function buildUi()
	local hud = Hud.gui()

	local existingBar = hud:FindFirstChild("ChargeBar", true)
	if existingBar and existingBar:IsA("Frame") and existingBar:FindFirstChild("Fill") and existingBar:FindFirstChild("Label") then
		chargeBar = existingBar
		chargeFill = existingBar:FindFirstChild("Fill") :: Frame
		chargeLabel = existingBar:FindFirstChild("Label") :: TextLabel
		chargeTier = (existingBar:FindFirstChild("Tier") or chargeLabel) :: TextLabel
	else
		chargeBar = Ui.frame(hud, "ChargeBar", UDim2.fromOffset(520, 46), UDim2.new(0.5, 0, 0, 70), Color3.fromRGB(10, 10, 16), Vector2.new(0.5, 0))
		Ui.corner(chargeBar, 14)
		Ui.border(chargeBar, 4)
		Ui.autoScale(chargeBar)
		chargeFill = Ui.frame(chargeBar, "Fill", UDim2.new(0, 0, 1, -8), UDim2.fromOffset(4, 4), Ui.white)
		Ui.corner(chargeFill, 10)
		chargeLabel = Ui.text(chargeBar, { name = "Label", text = "CHARGING... 0%", size = UDim2.new(0.6, 0, 1, -10), position = UDim2.fromOffset(16, 5), textSize = 26, stroke = 3, align = Enum.TextXAlignment.Left, z = 3 })
		chargeTier = Ui.text(chargeBar, { name = "Tier", text = "", size = UDim2.new(0.4, -16, 1, -10), position = UDim2.new(0.6, 0, 0, 5), textSize = 26, stroke = 3, align = Enum.TextXAlignment.Right, z = 3 })
	end
	chargeBar.Visible = false
	barScale = Instance.new("UIScale")
	barScale.Parent = chargeTier

	-- barra de distância: um segmento por raridade, cabeça do jogador como marcador
	distanceBar = Ui.frame(hud, "DistanceBar", UDim2.fromOffset(560, 22), UDim2.new(0.5, 0, 0, 78), Color3.fromRGB(10, 10, 16), Vector2.new(0.5, 0))
	Ui.border(distanceBar, 4)
	Ui.corner(distanceBar, 6)
	Ui.autoScale(distanceBar)
	local count = #Config.Rarities
	for index, rarity in Config.Rarities do
		Ui.frame(distanceBar, "Segment" .. index, UDim2.new(1 / count, 0, 1, 0), UDim2.fromScale((index - 1) / count, 0), rarity.color)
	end
	marker = Ui.frame(distanceBar, "Marker", UDim2.fromOffset(40, 40), UDim2.fromScale(0, 0.5), Color3.fromRGB(30, 34, 54), Vector2.new(0.5, 0.5))
	marker.ZIndex = 4
	Ui.corner(marker, 20)
	Ui.border(marker, 3, Ui.white)
	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 1)
	head.ZIndex = 5
	Ui.corner(head, 20)
	head.Parent = marker
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			head.Image = image
		end
	end)
	multiplier = Ui.text(marker, { name = "Multiplier", text = "x1", size = UDim2.fromOffset(80, 24), position = UDim2.new(0.5, 0, 1, 2), anchor = Vector2.new(0.5, 0), textSize = 22, stroke = 3, z = 5 })
	distanceBar.Visible = false

	-- pílula vermelha "HOLD TO CHARGE [E]": também é o botão para toque
	pill = Instance.new("TextButton")
	pill.Name = "ChargePill"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -170)
	pill.Size = UDim2.fromOffset(300, 46)
	pill.BackgroundColor3 = P.red
	pill.Font = Enum.Font.FredokaOne
	pill.TextSize = 24
	pill.TextColor3 = Ui.white
	pill.Text = "HOLD TO CHARGE [E]"
	pill.AutoButtonColor = false
	pill.Visible = false
	Ui.corner(pill, 23)
	Ui.border(pill, 4)
	Ui.stroke(pill, 3)
	Ui.autoScale(pill)
	pill.Parent = hud

	-- linhas de velocidade: ficam atrás do HUD
	linesGui = Instance.new("ScreenGui")
	linesGui.Name = "SpeedLines"
	linesGui.ResetOnSpawn = false
	linesGui.IgnoreGuiInset = true
	linesGui.DisplayOrder = 1
	linesGui.Enabled = false
	linesGui.Parent = player:WaitForChild("PlayerGui")
	for i = 1, LINES.count do
		-- âncora no meio: a rotação de um Frame é sempre em torno do centro dele
		local frame = Ui.frame(linesGui, "Line", UDim2.fromOffset(100, 4), nil, Ui.white, Vector2.new(0.5, 0.5))
		-- ponta de dentro some, ponta de fora cheia
		local taper = Instance.new("UIGradient")
		taper.Transparency = NumberSequence.new(1, 0)
		taper.Parent = frame
		lines[i] = { frame = frame, angle = 0, dist = 0, pace = 1, thick = 1, white = false }
	end
	-- fica no HUD e não junto das linhas: precisa aparecer depois que elas somem ("TOO WEAK!")
	popup = Ui.text(hud, { name = "Popup", text = "", size = UDim2.new(0.5, 0, 0, 90), position = UDim2.fromScale(0.5, 0.3), anchor = Vector2.new(0.5, 0.5), stroke = 6 })
	popup.Visible = false
	local popScale = Instance.new("UIScale")
	popScale.Parent = popup
end

local function buildWorld()
	for i = 1, 10 do
		local cube = Fx.part(Vector3.one * (0.9 + (i % 3) * 0.35), CFrame.identity, Color3.fromRGB(150, 20, 25), Enum.Material.SmoothPlastic)
		cube.Transparency = 1
		cubes[i] = cube
	end
	ring = Fx.part(Vector3.new(0.2, 9, 9), CFrame.identity, P.yellowLine, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 1
	for i = 1, 2 do
		local stripe = Fx.part(Vector3.new(1.1, 0.1, 70), CFrame.identity, P.yellowLine, Enum.Material.Neon)
		stripe.Transparency = 1
		stripes[i] = stripe
	end
	core = Fx.part(Vector3.one, CFrame.identity, Ui.white, Enum.Material.Neon, Enum.PartType.Ball)
	core.Transparency = 1
	-- crescentes da carga: Beams curvos entre dois Attachments reposicionados a cada quadro
	local holder = Fx.part(Vector3.one, CFrame.identity, Ui.white)
	holder.Transparency = 1
	for i = 1, 3 do
		local a0 = Instance.new("Attachment")
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Segments = 24
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = 4
		beam.Width1 = 0.02
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) })
		beam.Enabled = false
		beam.Parent = holder
		crescents[i] = { a0 = a0, a1 = a1, beam = beam }
	end
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "ChargeTint"
	tint.Parent = game:GetService("Lighting")
end

-- Linhas de velocidade: todas apontam para o ponto de fuga, nascem perto dele e aceleram
-- para as bordas. Os números ficam em Config.SpeedLines.
local function spawnLine(line: Line, dist: number)
	line.angle = rng:NextNumber(0, math.pi * 2)
	line.dist = dist
	line.pace = rng:NextNumber(0.7, 1.3)
	line.thick = rng:NextNumber(LINES.thickness.Min, LINES.thickness.Max)
	line.white = rng:NextNumber() < LINES.whiteChance
end

-- Liga (com as linhas já espalhadas pelo caminho) ou desliga; o fade acontece em stepLines.
local function setLines(on: boolean)
	linesTarget = if on then 1 else 0
	if on then
		linesPower, linesPulse = 0, 0
		for _, line in lines do
			spawnLine(line, rng:NextNumber())
		end
	end
end

-- Roda a cada quadro, em qualquer estado, enquanto houver linha visível.
local function stepLines(dt: number)
	if linesAlpha < linesTarget then
		linesAlpha = math.min(linesTarget, linesAlpha + dt / LINES.fadeIn)
	elseif linesAlpha > linesTarget then
		linesAlpha = math.max(linesTarget, linesAlpha - dt / LINES.fadeOut)
	end
	if linesAlpha <= 0 then
		linesGui.Enabled = false
		return
	end
	linesGui.Enabled = true
	linesPulse = math.max(0, linesPulse - dt / LINES.pulseTime)
	local strength = LINES.minIntensity + (1 - LINES.minIntensity) * math.clamp(linesPower + linesPulse * LINES.wallPulse, 0, 1)

	local viewport = camera.ViewportSize
	local center = viewport * LINES.center
	local reach = viewport.Magnitude / 2
	local inner = reach * LINES.innerRadius
	for _, line in lines do
		line.dist += LINES.flowSpeed * line.pace * (1 + LINES.acceleration * line.dist) * strength * dt
		if line.dist > 1 then
			spawnLine(line, 0)
		end
		local grown = LINES.lengthAtBirth + (1 - LINES.lengthAtBirth) * line.dist
		local length = reach * LINES.length * grown * strength
		local radius = inner + (reach - inner) * line.dist + length / 2
		local frame = line.frame
		frame.Position = UDim2.fromOffset(center.X + math.cos(line.angle) * radius, center.Y + math.sin(line.angle) * radius)
		frame.Size = UDim2.fromOffset(length, line.thick * grown * strength)
		frame.Rotation = math.deg(line.angle)
		frame.BackgroundColor3 = if line.white then Ui.white else lineColor
		local born = math.clamp(line.dist / LINES.birthFade, 0, 1)
		-- a intensidade mexe em velocidade, comprimento e espessura; a opacidade só segue o fade
		frame.BackgroundTransparency = 1 - LINES.maxOpacity * linesAlpha * born
	end
end

local function setNeon(color: Color3)
	local hallway = workspace:FindFirstChild("Hallway")
	local neon = hallway and hallway:FindFirstChild("Neon")
	if neon then
		for _, strip in neon:GetChildren() do
			if strip:IsA("BasePart") then
				TweenService:Create(strip, TweenInfo.new(0.2), { Color = color }):Play()
			end
		end
	end
end

local function wallModel(index: number): Model?
	local hallway = workspace:FindFirstChild("Hallway")
	local walls = hallway and hallway:FindFirstChild("Walls")
	local wall = walls and walls:FindFirstChild("Wall" .. index)
	return if wall and wall:IsA("Model") then wall else nil
end

local function showPopup(text: string, color: Color3)
	popup.Text = text
	popup.TextColor3 = color
	popup.Visible = true
	popup.Rotation = rng:NextNumber(-8, 8)
	local scale = popup:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.3
	TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.4, function()
		if popup.Text == text then
			popup.Visible = false
		end
	end)
end

-- Estoura a parede: some com os tijolos de verdade (só neste cliente) e joga cópias na câmera.
local function breakWall(index: number)
	local wall = wallModel(index)
	local info = Config.Walls[index]
	local color = tierColor(info.tier)
	if wall then
		local bricks = wall:FindFirstChild("Bricks")
		local thrown = 0
		for _, brick in (if bricks then bricks:GetChildren() else {}) do
			if brick:IsA("BasePart") then
				if thrown < 18 and rng:NextNumber() < 0.6 then
					thrown += 1
					local copy = brick:Clone()
					copy.Anchored = false
					copy.CanCollide = false
					copy.CanQuery = false
					copy.Parent = Fx.folder
					copy.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-45, 45), rng:NextNumber(5, 55), rng:NextNumber(40, 150))
					copy.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
					game:GetService("Debris"):AddItem(copy, 1.1)
				end
				brick.Transparency = 1
				table.insert(hidden, brick)
			end
		end
		local sign = wall:FindFirstChild("Sign")
		if sign and sign:IsA("BasePart") then
			Fx.burst(Vector3.new(0, 6, sign.Position.Z), color:Lerp(Ui.white, 0.5), 46, 0.28)
		end
	end
	Fx.flash(color, 0.45, 0.16)
	Fx.shake(0.55)
	smashStart = os.clock()
	smashRight = not smashRight
	fovKick = 14
	linesPulse = 1
	linesPower = index / #Config.Walls
	showPopup(Format.abbreviate(info.power) .. "!", color)
	lineColor = color:Lerp(Ui.white, 0.35)
	setNeon(color)
	multiplier.Text = "x" .. tostring(info.luck)
end

local function restoreWalls()
	for _, brick in hidden do
		brick.Transparency = 0
	end
	table.clear(hidden)
	setNeon(Ui.white)
	lineColor = Color3.fromRGB(255, 250, 235)
end

---------------------------------------------------------------------------------------------------
-- Carga

local function hideChargeVisuals()
	for _, cube in cubes do
		cube.Transparency = 1
	end
	ring.Transparency = 1
	tint.TintColor = Ui.white
	tint.Brightness = 0
	chargeBar.Visible = false
	Aura.setBoost(0)
	core.Transparency = 1
	for _, crescent in crescents do
		crescent.beam.Enabled = false
	end
	Pose.weight("charge", 0)
	Pose.define("chargeShake", { Root = CFrame.identity })
end

local function endCharge(restoreCamera: boolean)
	hideChargeVisuals()
	local _, root = character()
	if root then
		root.Anchored = false
	end
	if restoreCamera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end
end

local function beginCharge()
	local _, root = character()
	if state ~= "idle" or not root or not inZone(root) or Roll.isPlaying() or Windows.current() then
		return -- com um painel aberto a câmera é dele
	end
	state = "charging"
	chargeStart = os.clock()
	chargeRemote:FireServer("start")
	pill.Visible = false
	chargeBar.Visible = true
	-- parado, de frente para o corredor (-Z)
	root.Anchored = true
	root.CFrame = CFrame.new(root.Position)
	camera.CameraType = Enum.CameraType.Scriptable
	Pose.weight("charge", 1)
	nextRing, streakDebt, lastTier, maxed = 0, 0, -1, false
end

local function releaseCharge()
	if state ~= "charging" then
		return
	end
	local charge = (os.clock() - chargeStart) / RUN.chargeTime
	if charge < RUN.minCharge then
		state = "idle"
		chargeRemote:FireServer("cancel")
		endCharge(true)
		return
	end
	state = "waiting"
	chargeRemote:FireServer("release")
	-- sem resposta do servidor: desiste em vez de travar o jogador
	local started = chargeStart
	task.delay(3, function()
		if state == "waiting" and chargeStart == started then
			state = "idle"
			endCharge(true)
		end
	end)
end

local function stepCharge(now: number, dt: number)
	local _, root = character()
	if not root then
		state = "idle"
		endCharge(true)
		return
	end
	local pct = math.clamp((now - chargeStart) / RUN.chargeTime, 0, 1)
	local power = player:GetAttribute("Power")
	local broken = RunMath.wallsBroken(RunMath.effectivePower(if type(power) == "number" then power else 0, pct))
	local tier = if broken > 0 then Config.Walls[broken].tier else 0
	local color = tierColor(tier)

	chargeFill.Size = UDim2.new(pct, -8 * pct, 1, -8)
	chargeFill.BackgroundColor3 = color
	chargeLabel.Text = `CHARGING... {math.floor(pct * 100)}%`
	chargeTier.Text = if tier > 0 then string.upper(Config.Rarities[tier].id) else "WEAK"
	chargeTier.TextColor3 = color

	local position = root.Position
	local feet = position - Vector3.new(0, 2.9, 0)
	-- câmera gira para a frente do jogador: o lobby e os terrenos ficam ao fundo
	local goal = CFrame.lookAt(position + Vector3.new(7, 3.5, -15), position + Vector3.new(0, 1.2, 0))
	camera.CFrame = camera.CFrame:Lerp(goal, 1 - math.exp(-9 * dt)) * Fx.shakeCFrame()
	Fx.shake(pct * dt * 5)

	local visible = math.ceil(pct * #cubes)
	for i, cube in cubes do
		if i <= visible then
			local angle = now * (2.2 + (i % 3) * 0.6) + i * 0.63
			local radius = 3.2 + (i % 4) * 0.9
			local height = 0.6 + pct * (1.5 + (i % 5) * 1.1) + math.sin(now * 3 + i) * 0.4
			cube.CFrame = CFrame.new(feet + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)) * CFrame.Angles(now * 2 + i, now * 3, 0)
			cube.Transparency = 0
		else
			cube.Transparency = 1
		end
	end

	-- a partir de ~70% a imagem esquenta
	local warm = math.clamp((pct - 0.6) / 0.4, 0, 1)
	tint.TintColor = Ui.white:Lerp(Color3.fromRGB(255, 205, 150), warm)
	tint.Brightness = warm * 0.04
	ring.CFrame = CFrame.new(feet + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = if pct >= 1 then 0.1 + math.abs(math.sin(now * 10)) * 0.3 else 1
	Aura.setBoost(pct)

	-- corpo: agachado em pose de força, tremendo cada vez mais
	local jitter = pct * 0.05
	Pose.define("chargeShake", { Root = CFrame.new(rng:NextNumber(-1, 1) * jitter, 0, rng:NextNumber(-1, 1) * jitter) * CFrame.Angles(rng:NextNumber(-1, 1) * jitter, 0, rng:NextNumber(-1, 1) * jitter) })
	camera.FieldOfView = 70 - 14 * pct -- aproxima enquanto carrega

	-- ondas de choque no chão, cada vez mais rápidas, e riscos de energia subindo
	if now >= nextRing then
		nextRing = now + 0.34 - 0.2 * pct
		Fx.ring(feet + Vector3.new(0, 0.2, 0), color:Lerp(Ui.white, 0.3), 14 + pct * 22, 0.4)
	end
	streakDebt += dt * (6 + pct * 40)
	while streakDebt >= 1 do
		streakDebt -= 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(2, 6.5)
		Fx.streak(feet + Vector3.new(math.cos(angle) * radius, 0.3, math.sin(angle) * radius), Vector3.new(0, 9 + pct * 9, 0), color:Lerp(Ui.white, 0.5), 2 + pct * 2.5, 0.4)
	end

	-- energia convergindo para o peito: riscos entrando de todos os lados
	local chest = position + Vector3.new(0, 0.5, 0)
	local bright = color:Lerp(Ui.white, 0.55)
	convergeDebt += dt * (10 + pct * 55)
	while convergeDebt >= 1 do
		convergeDebt -= 1
		local from = chest + rng:NextUnitVector() * rng:NextNumber(8, 15)
		Fx.streak(from, (chest - from) * 0.9, bright, 3 + pct * 2, 0.2)
	end
	-- acima de 55%, raios de luz estourando para fora
	if pct > 0.55 then
		rayDebt += dt * (pct - 0.55) * 60
		while rayDebt >= 1 do
			rayDebt -= 1
			Fx.streak(chest, rng:NextUnitVector() * rng:NextNumber(10, 20), Ui.white, 7, 0.16)
		end
	end
	-- núcleo brilhante no peito, crescendo e pulsando
	local corePulse = 0.5 + 0.5 * math.sin(now * (14 + pct * 20))
	core.Size = Vector3.one * (0.4 + pct * 1.3 + corePulse * (0.15 + pct * 0.3))
	core.CFrame = CFrame.new(chest)
	core.Color = bright
	core.Transparency = 0.35
	-- crescentes: três arcos de luz girando em planos inclinados em volta do corpo
	local radius = 3 + pct * 1.8
	for i, crescent in crescents do
		local basis = CFrame.new(chest) * CFrame.Angles(math.rad(-30 + i * 35), i * 2.1, math.rad(20 * i))
		local a0 = now * (5 + pct * 9) * (if i % 2 == 0 then 1 else -1) + i * 2
		local a1 = a0 + 2.3
		local function place(attachment: Attachment, angle: number)
			local point = basis * Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local tangent = basis:VectorToWorldSpace(Vector3.new(-math.sin(angle), 0, math.cos(angle)))
			attachment.WorldCFrame = CFrame.fromMatrix(point, tangent, basis.UpVector)
		end
		place(crescent.a0, a0)
		place(crescent.a1, a1)
		crescent.beam.CurveSize0 = radius * 0.85
		crescent.beam.CurveSize1 = radius * 0.85
		crescent.beam.Width0 = 0.25 + pct * 1.1
		crescent.beam.Color = ColorSequence.new(Ui.white, bright)
		crescent.beam.Enabled = pct > 0.08
	end

	-- troca de tier previsto e carga cheia: estalo na barra, clarão, pedras
	if tier ~= lastTier then
		if lastTier >= 0 and tier > lastTier then
			Fx.flash(color, 0.22, 0.2)
			Fx.shake(0.3)
			Fx.cubes(feet + Vector3.new(0, 1, 0), color, 6, 20, Vector3.new(0, 16, 0), 0.9, Enum.Material.Neon)
			barScale.Scale = 1.15
			TweenService:Create(barScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		lastTier = tier
	end
	if pct >= 1 and not maxed then
		maxed = true
		showPopup("MAX!", P.yellowLine)
		Fx.flash(Ui.white, 0.5, 0.25)
		Fx.shake(0.7)
		Fx.burst(position, Ui.white, 26, 0.35)
		Fx.ring(feet + Vector3.new(0, 0.2, 0), P.yellowLine, 60, 0.5)
		Fx.cubes(feet + Vector3.new(0, 1, 0), Color3.fromRGB(122, 80, 40), 12, 26, Vector3.new(0, 22, 0), 1.3)
	end
end

---------------------------------------------------------------------------------------------------
-- Corrida

local function playRun(result: any)
	local _, root, humanoid = character()
	if not root or not humanoid then
		state = "idle"
		endCharge(true)
		return
	end
	state = "running"
	hideChargeVisuals()
	Aura.setBoost(0.6)
	Pose.weight("launch", 1, true)
	Aura.forceTrails(true)
	Fx.ring(root.Position - Vector3.new(0, 2.7, 0), Ui.white, 70, 0.5)
	Fx.cubes(root.Position - Vector3.new(0, 2, 0), Color3.fromRGB(122, 80, 40), 14, 30, Vector3.new(0, 20, 40), 1.4)

	local walls = Config.Walls
	local broken: number = result.broken
	local runTime: number = result.runTime
	local startZ = RUN.zoneCenter.Z
	local start = root.Position
	local totalStuds = walls[#walls].distance / RUN.metersPerStud
	local stopZ = startZ - RunMath.stopStuds(broken)
	if broken < #walls then
		stopZ += 5 -- para na frente da parede, não dentro dela
	end

	-- corte seco: clarão de um quadro, câmera atrás, campo de visão aberto
	Fx.flash(Ui.white, 1, 0.18)
	Fx.shake(0.8)
	camera.CameraType = Enum.CameraType.Scriptable
	fovKick = 0
	setLines(true)
	distanceBar.Visible = true
	multiplier.Text = "x1"
	for _, stripe in stripes do
		stripe.Transparency = 0.15
	end

	local began = os.clock()
	local nextWall = 1
	while true do
		RunService.RenderStepped:Wait()
		local t = os.clock() - began
		local blend = math.clamp(t / 0.25, 0, 1)
		local z = math.max(startZ - RUN.speed * t, stopZ)
		-- costura a pista de um lado para o outro, deitando o corpo na curva
		local weave = math.sin(t * 2.6) * 3.2 * blend
		local roll = -math.cos(t * 2.6) * 0.2 * blend
		local position = Vector3.new(start.X * (1 - blend) + weave, start.Y, start.Z + (z - start.Z) * blend)
		root.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(-12), 0, roll)

		-- ciclo de corrida rápido; ao estourar uma parede, um braço soca para a frente por 0,3 s
		Pose.define("launch", Pose.runCycle(t * 27, 1.2, 14, true))
		local smash = math.max(0, 1 - (os.clock() - smashStart) / 0.3)
		Pose.weight("smashR", if smashRight then smash else 0, true)
		Pose.weight("smashL", if smashRight then 0 else smash, true)

		-- a câmera segue o centro da pista (não a costura) e leva um coice de FOV a cada parede
		fovKick = math.max(0, fovKick - 40 * (1 / 60))
		camera.FieldOfView = 70 + 38 * math.clamp(t / 0.15, 0, 1) + fovKick
		local center = Vector3.new(position.X - weave * 0.6, position.Y, position.Z)
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 6.5, 17), center + Vector3.new(0, 3, -40)) * CFrame.Angles(0, 0, roll * 0.25) * Fx.shakeCFrame()

		for i, stripe in stripes do
			stripe.CFrame = CFrame.new(position.X + (if i == 1 then -1.7 else 1.7), Config.World.groundY + 0.2, position.Z + 33)
		end
		marker.Position = UDim2.fromScale(math.clamp((startZ - z) / totalStuds, 0, 1), 0.5)

		while nextWall <= broken and RUN.speed * t >= RunMath.wallStuds(nextWall) do
			breakWall(nextWall)
			nextWall += 1
		end
		if t >= runTime then
			break
		end
	end

	-- fim: bate na parede que não quebra (ou chega ao fim do corredor)
	setLines(false)
	for _, stripe in stripes do
		stripe.Transparency = 1
	end
	Aura.setBoost(0)
	Pose.weight("launch", 0)
	Aura.forceTrails(false)
	Pose.weight("smashR", 0, true)
	Pose.weight("smashL", 0, true)
	local impact = root.Position + Vector3.new(0, 2, -4)
	local failed = broken < #walls
	if failed then
		local color = tierColor(walls[broken + 1].tier)
		Fx.burst(impact, Ui.white, 34, 0.45)
		Fx.cubes(impact, color, 22, 38, Vector3.new(0, 10, 45), 2.2)
		Fx.flash(Ui.white, 0.6, 0.25)
		Fx.shake(1.2)
		showPopup("TOO WEAK!", P.red)
	else
		Fx.title("HALLWAY CLEARED!", P.yellowLine, 1)
	end
	root.Anchored = false
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-6, 6), 26, 30)
	root.AssemblyAngularVelocity = Vector3.new(6, 0, rng:NextNumber(-3, 3))

	local shakeUntil = os.clock() + 0.9
	while os.clock() < shakeUntil do
		RunService.RenderStepped:Wait()
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, root.Position) * Fx.shakeCFrame()
	end

	-- tela preta enquanto o servidor devolve o jogador ao terreno
	Fx.black(1, 0.15)
	task.wait(0.15 + 0.55)
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	-- de volta ao terreno: câmera atrás do jogador, olhando para onde ele olha
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if facing.Magnitude > 0.1 then
		camera.CFrame = CFrame.lookAt(root.Position - facing.Unit * 14 + Vector3.new(0, 7, 0), root.Position + Vector3.new(0, 1, 0))
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	distanceBar.Visible = false
	popup.Visible = false
	restoreWalls()
	Fx.black(0, 0.2)

	state = "idle"
	Roll.play(result.characterId, result.isNew)
end

---------------------------------------------------------------------------------------------------

function Run.isBusy(): boolean
	return state ~= "idle"
end

-- O gancho de teste carrega e solta sem tecla.
Run.beginCharge = beginCharge
Run.releaseCharge = releaseCharge

function Run.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	chargeRemote = remotes:WaitForChild("Charge") :: RemoteEvent
	local resultRemote = remotes:WaitForChild("RunResult") :: RemoteEvent

	buildUi()
	buildWorld()

	-- carga: agachado, braços abertos e flexionados, cabeça baixa
	Pose.define("charge", {
		Root = CFrame.new(0, -0.55, 0) * Pose.deg(-14, 0, 0),
		Waist = Pose.deg(-12, 0, 0),
		Neck = Pose.deg(-10, 0, 0),
		RightShoulder = Pose.deg(-18, 0, 42),
		LeftShoulder = Pose.deg(-18, 0, -42),
		RightElbow = Pose.deg(95, 0, 0),
		LeftElbow = Pose.deg(95, 0, 0),
		RightHip = Pose.deg(38, 0, 8),
		LeftHip = Pose.deg(38, 0, -8),
		RightKnee = Pose.deg(-62, 0, 0),
		LeftKnee = Pose.deg(-62, 0, 0),
	}, false, 10)
	Pose.define("chargeShake", { Root = CFrame.identity }, true, 60)
	Pose.weight("chargeShake", 1, true)
	-- lançamento: ciclo de corrida atualizado a cada quadro em playRun; soco ao estourar parede
	Pose.define("launch", Pose.runCycle(0, 1.2, 14, true), false, 20)
	Pose.define("smashR", { RightShoulder = Pose.deg(100, 0, 0), RightElbow = Pose.deg(2, 0, 0), Waist = Pose.deg(-14, 36, 0) })
	Pose.define("smashL", { LeftShoulder = Pose.deg(100, 0, 0), LeftElbow = Pose.deg(2, 0, 0), Waist = Pose.deg(-14, -36, 0) })

	resultRemote.OnClientEvent:Connect(function(result)
		if result == nil then
			-- o servidor recusou a carga ou a soltura
			if state == "charging" or state == "waiting" then
				state = "idle"
				endCharge(true)
			end
			return
		end
		if state == "waiting" or state == "charging" then
			task.spawn(playRun, result)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.E then
			beginCharge()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			releaseCharge()
		end
	end)
	-- a pílula some durante a carga, então a soltura do mouse/dedo é ouvida fora dela
	local pointerCharge = false
	pill.MouseButton1Down:Connect(function()
		pointerCharge = true
		beginCharge()
	end)
	UserInputService.InputEnded:Connect(function(input)
		local pointer = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
		if pointer and pointerCharge then
			pointerCharge = false
			releaseCharge()
		end
	end)

	-- botão CORRER do HUD: só pede; o servidor valida e decide o destino
	local goRemote = remotes:WaitForChild("GoZone") :: RemoteEvent
	local found = Hud.gui():FindFirstChild("GoZoneButton", true)
	goButton = if found and found:IsA("GuiObject") then found else nil
	Hud.onClick("GoZoneButton", function()
		if state == "idle" and not Roll.isPlaying() then
			goRemote:FireServer()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		stepLines(dt)
		local free = false -- parado fora da zona, sem carga, corrida ou roleta: pode teleportar
		if state == "charging" or state == "waiting" then
			stepCharge(os.clock(), dt)
		elseif state == "idle" then
			local _, root = character()
			local ready = root ~= nil and not Roll.isPlaying()
			pill.Visible = ready and inZone(root :: BasePart)
			free = ready and not inZone(root :: BasePart)
		end
		if goButton then
			goButton.Visible = free
		end
	end)

	player.CharacterAdded:Connect(function()
		if state == "charging" or state == "waiting" then
			state = "idle"
			endCharge(true)
		end
	end)
end

return Run
