--!strict
-- Entrada na sala do chefe, do lado do cliente. Quem limpa o corredor inteiro:
--   1. portal: um círculo mágico se abre no fim do corredor, o boneco é puxado para dentro e a
--      câmera vai junto até a tela estourar em branco e apagar;
--   2. espera: o servidor leva o boneco para a sala (src/server/BossRoom.luau);
--   3. cinemática, com faixas pretas em cima e embaixo: a câmera desce da cúpula girando sobre o
--      círculo onde o chefe dorme (com o nome da sala), corta para um plano baixo na porta, que
--      bate atrás do jogador, e termina atrás dele, avançando para o centro.
-- Tudo aqui é local: as portas só giram neste cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Textures = require(ReplicatedStorage.Shared.Textures)
local Aura = require(script.Parent.Aura)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Pose = require(script.Parent.Pose)
local Roll = require(script.Parent.Roll)

local ROOM = Config.BossRoom
local K = ROOM.scale -- medidas do modelo -> studs do jogo
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- cor de cada sala (runas do círculo, portal, luz do anel)
local GLOW = { Color3.fromRGB(110, 190, 255), Color3.fromRGB(255, 110, 40) }

-- clima dentro de cada sala: a sala é fechada, então o ambiente sobe para ela não ficar preta
local MOOD = {
	{ Ambient = Color3.fromRGB(96, 104, 150), OutdoorAmbient = Color3.fromRGB(110, 118, 170), ExposureCompensation = 0 },
	{ Ambient = Color3.fromRGB(130, 90, 80), OutdoorAmbient = Color3.fromRGB(140, 100, 90), ExposureCompensation = 0 },
}

local BossRoom = {}
local saved: { [string]: any }? = nil

-- Liga o clima da sala quando o servidor marca o jogador dentro dela e devolve o de antes na saída.
local function applyMood()
	local Lighting = game:GetService("Lighting")
	local id = player:GetAttribute("Room")
	local mood = if type(id) == "number" then MOOD[id] else nil
	if mood then
		if not saved then
			saved = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, ExposureCompensation = Lighting.ExposureCompensation }
		end
		TweenService:Create(Lighting, TweenInfo.new(0.4), mood):Play()
	elseif saved then
		TweenService:Create(Lighting, TweenInfo.new(0.4), saved):Play()
		saved = nil
	end
end
player:GetAttributeChangedSignal("Room"):Connect(applyMood)

local phase = "idle"
local doorsOpen = 0
local bars: { Frame } = {}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function letterbox(on: boolean, time: number)
	if #bars == 0 then
		local gui = Instance.new("ScreenGui")
		gui.Name = "Cinema"
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 40
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		for _, top in { true, false } do
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = Color3.new(0, 0, 0)
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0, if top then 0 else 1)
			bar.Position = UDim2.fromScale(0, if top then 0 else 1)
			bar.Size = UDim2.fromScale(1, 0)
			bar.Parent = gui
			table.insert(bars, bar)
		end
	end
	for _, bar in bars do
		TweenService:Create(bar, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, if on then 0.11 else 0) }):Play()
	end
end

-- Roda `step(t)` a cada quadro por `seconds`, com t de 0 a 1.
local function play(seconds: number, step: (number) -> ())
	local began = os.clock()
	while true do
		local t = math.min((os.clock() - began) / seconds, 1)
		step(t)
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

-- A sala do jogador (o servidor dá uma para cada um, atributo RoomKey) e o centro do piso dela.
local function myRoom(): (Folder?, Vector3?)
	local key = player:GetAttribute("RoomKey")
	local found = if type(key) == "string" then workspace:FindFirstChild(key) else nil
	local center = found and found:GetAttribute("Center")
	if found and found:IsA("Folder") and typeof(center) == "Vector3" then
		return found, center
	end
	return nil, nil
end

---------------------------------------------------------------------------------------------------
-- Portas: cada folha (e o dourado dela) gira pela dobradiça, para dentro da sala.

type Leaf = { parts: { BasePart }, base: { CFrame }, hinge: Vector3, sign: number }

local function leaves(room: Folder, center: Vector3): { Leaf }
	local model = room:FindFirstChild("boss_room")
	if not model then
		return {}
	end
	local list = {}
	for _, side in { "DoorL", "DoorR" } do
		local leaf = model:FindFirstChild(side .. "_boss_room")
		local gold = model:FindFirstChild(side .. "Gold_boss_room")
		if leaf and leaf:IsA("BasePart") then
			-- largura da folha em X do mundo: a dobradiça é a ponta longe do eixo da sala
			local r = leaf.CFrame
			local half = (math.abs(r.RightVector.X) * leaf.Size.X + math.abs(r.UpVector.X) * leaf.Size.Y + math.abs(r.LookVector.X) * leaf.Size.Z) / 2
			local outward = if leaf.Position.X >= center.X then 1 else -1
			local hinge = Vector3.new(leaf.Position.X + outward * half, leaf.Position.Y, leaf.Position.Z)
			-- gira para o lado que leva a folha para dentro (-Z, longe da porta)
			local probe = CFrame.new(hinge) * CFrame.Angles(0, math.rad(60), 0) * CFrame.new(hinge):Inverse() * leaf.Position
			local parts: { BasePart } = { leaf }
			if gold and gold:IsA("BasePart") then
				table.insert(parts, gold)
			end
			local base = {}
			for _, p in parts do
				table.insert(base, p.CFrame)
			end
			table.insert(list, { parts = parts, base = base, hinge = hinge, sign = if probe.Z < leaf.Position.Z then 1 else -1 })
		end
	end
	return list
end

local function setDoors(list: { Leaf }, open: number)
	doorsOpen = open
	for _, leaf in list do
		local turn = CFrame.new(leaf.hinge) * CFrame.Angles(0, leaf.sign * math.rad(84) * open, 0) * CFrame.new(leaf.hinge):Inverse()
		for i, p in leaf.parts do
			p.CFrame = turn * leaf.base[i]
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 1. Portal no fim do corredor

-- Três poses do pulo no portal: agacha juntando força, salta esticando os braços para ele e
-- mergulha de cabeça, braços à frente e pernas juntas (o giro do corpo vem do CFrame da raiz).
local deg = Pose.deg
local CROUCH = {
	Root = CFrame.new(0, -0.8, 0) * deg(-8, 0, 0), Waist = deg(-20, 0, 0), Neck = deg(24, 0, 0),
	RightShoulder = deg(-50, 0, 28), LeftShoulder = deg(-50, 0, -28), RightElbow = deg(70, 0, 0), LeftElbow = deg(70, 0, 0),
	RightHip = deg(55, 0, 8), LeftHip = deg(55, 0, -8), RightKnee = deg(-90, 0, 0), LeftKnee = deg(-90, 0, 0),
}
local REACH = {
	Root = CFrame.new(0, 0.3, 0), Waist = deg(14, 0, 0), Neck = deg(12, 0, 0),
	RightShoulder = deg(165, 0, 14), LeftShoulder = deg(165, 0, -14), RightElbow = deg(6, 0, 0), LeftElbow = deg(6, 0, 0),
	RightHip = deg(-22, 0, 4), LeftHip = deg(-8, 0, -4), RightKnee = deg(-30, 0, 0), LeftKnee = deg(-60, 0, 0),
}
local DIVE = {
	Root = CFrame.identity, Waist = deg(8, 0, 0), Neck = deg(28, 0, 0),
	RightShoulder = deg(178, 0, 5), LeftShoulder = deg(178, 0, -5), RightElbow = deg(0, 0, 0), LeftElbow = deg(0, 0, 0),
	RightHip = deg(-10, 0, 2), LeftHip = deg(-10, 0, -2), RightKnee = deg(-8, 0, 0), LeftKnee = deg(-8, 0, 0),
}

local function blend(a: { [string]: CFrame }, b: { [string]: CFrame }, x: number): { [string]: CFrame }
	local out = {}
	for joint, cf in a do
		out[joint] = cf:Lerp(b[joint], x)
	end
	return out
end

local function portal(root: BasePart, color: Color3)
	phase = "portal"
	local start = root.CFrame
	local center = root.Position + Vector3.new(0, 3, -15)
	local face = CFrame.new(center) -- frente em -Z: a câmera, atrás do boneco, vê a face de trás

	local ring = Fx.part(Vector3.new(0.4, 1, 1), face * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	local void = Fx.part(Vector3.new(0.3, 1, 1), face * CFrame.new(0, 0, 0.2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(12, 6, 30), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local board = Fx.part(Vector3.new(26, 26, 0.1), face * CFrame.new(0, 0, -0.3), color)
	board.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(512, 512)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = board
	local circle = Instance.new("ImageLabel")
	circle.BackgroundTransparency = 1
	circle.Image = Textures.circle
	circle.ImageColor3 = color
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromScale(0, 0)
	circle.Parent = gui
	local swirl = circle:Clone()
	swirl.Image = Textures.swirl
	swirl.ImageColor3 = color:Lerp(Color3.new(1, 1, 1), 0.4)
	swirl.Parent = gui
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 40
	light.Brightness = 0
	light.Parent = ring

	Fx.burst(center, color, 22, 0.5)
	Fx.shake(0.5)
	local eye = camera.CFrame.Position
	local seconds = ROOM.portalTime
	local flashed, jumped = false, false
	Pose.define("portal", CROUCH, false, 30)
	Pose.weight("portal", 1)
	play(seconds, function(t)
		local open = 1 - (1 - math.min(t / 0.4, 1)) ^ 3
		ring.Size = Vector3.new(0.4, 18 * open, 18 * open)
		void.Size = Vector3.new(0.3, 16 * open, 16 * open)
		circle.Size = UDim2.fromScale(open, open)
		circle.Rotation = t * 140
		swirl.Size = UDim2.fromScale(0.7 * open, 0.7 * open)
		swirl.Rotation = -t * 320
		light.Brightness = 4 * open
		-- agacha (até 0,28), salta para o portal (0,28 a 0,55) e mergulha girando (0,5 em diante)
		local leap = smooth((t - 0.28) / 0.25)
		local plunge = smooth((t - 0.5) / 0.4)
		Pose.define("portal", blend(blend(CROUCH, REACH, leap), DIVE, plunge))
		if leap > 0 and not jumped then
			jumped = true
			Fx.ring(start.Position - Vector3.new(0, 2.7, 0), color, 16, 0.4)
			Aura.setBoost(0.35)
			Aura.forceTrails(true)
		end
		local pull = smooth((t - 0.3) / 0.7)
		local hop = math.sin(math.pi * math.clamp((t - 0.28) / 0.5, 0, 1)) * 3.5
		local at = start.Position:Lerp(center, pull) + Vector3.new(0, hop, 0)
		local pitch = math.rad(-35 * leap - 50 * plunge)
		local spin = math.pi * 2 * plunge
		root.CFrame = CFrame.new(at) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, spin, 0)
		-- a câmera vai atrás e mergulha no portal
		local dive = smooth((t - 0.45) / 0.55)
		camera.FieldOfView = 80 - 25 * dive
		camera.CFrame = CFrame.lookAt(eye:Lerp(center + Vector3.new(0, 0.5, 5), dive), center) * Fx.shakeCFrame()
		if t > 0.86 and not flashed then
			flashed = true
			Fx.flash(Color3.new(1, 1, 1), 1, 0.25)
			Fx.black(1, 0.2)
		end
	end)
	Pose.weight("portal", 0, true)
	Aura.setBoost(0)
	Aura.forceTrails(false)
	task.delay(0.6, function()
		for _, p in { ring, void, board } do
			p:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- 3. Cinemática dentro da sala

local function intro(root: BasePart, world: any, room: Folder, center: Vector3)
	phase = "intro"
	local entry = root.Position
	local color = GLOW[world.id] or GLOW[1]
	local list = leaves(room, center)
	setDoors(list, 1)
	root.Anchored = true

	letterbox(true, 0.5)
	local hud = Hud.gui()
	hud.Enabled = false
	Fx.black(0, 0.7)
	camera.CameraType = Enum.CameraType.Scriptable
	local total = ROOM.introTime
	local cut1, cut2 = total * 0.37, total * 0.66

	-- plano 1: desce da cúpula girando sobre o círculo
	task.delay(0.5, function()
		Fx.title(ROOM.names[world.id] or "THRONE ROOM", color, 1.6)
	end)
	play(cut1, function(t)
		local e = smooth(t)
		local angle = math.rad(-20 + 55 * e)
		local radius = (6 + 24 * e) * K
		local height = (52 - 22 * e) * K
		local eye = center + Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)
		camera.FieldOfView = 62
		camera.CFrame = CFrame.lookAt(eye, center + Vector3.new(0, 1.5 * K, 0))
	end)

	-- plano 2: baixo, de lado, na porta; ela bate atrás do jogador
	local slammed = false
	play(cut2 - cut1, function(t)
		local e = smooth(t)
		local eye = entry + Vector3.new(9 - 5 * e, 2 + e, -18)
		camera.FieldOfView = 55
		camera.CFrame = CFrame.lookAt(eye, entry + Vector3.new(0, 6, (ROOM.radius - ROOM.entry) * K)) * Fx.shakeCFrame()
		local close = math.clamp((t - 0.3) / 0.25, 0, 1)
		setDoors(list, 1 - close * close)
		if close >= 1 and not slammed then
			slammed = true
			Fx.shake(0.7)
			Fx.flash(color, 0.25, 0.3)
			Fx.cubes(Vector3.new(entry.X, center.Y + 1, center.Z + ROOM.radius * K - 2), Color3.fromRGB(150, 150, 170), 16, 14, Vector3.new(0, 6, -10), 0.8)
		end
	end)

	-- plano 3: atrás do jogador, avançando para o centro; o círculo pulsa
	Fx.ring(center + Vector3.new(0, 1.3 * K, 0), color, 30 * K, 0.9)
	play(total - cut2, function(t)
		local e = smooth(t)
		local behind = entry + Vector3.new(0, 6.5 - 1.5 * e, 13 - 5 * e)
		camera.FieldOfView = 58 + 12 * e
		camera.CFrame = CFrame.lookAt(behind, center + Vector3.new(0, 3, 0))
	end)

	letterbox(false, 0.4)
	hud.Enabled = true
	root.Anchored = false
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end

---------------------------------------------------------------------------------------------------

-- Do fim do corredor até estar dentro da sala. Volta quando a câmera já é do jogador de novo.
function BossRoom.enter(root: BasePart, humanoid: Humanoid, world: any)
	local color = GLOW[world.id] or GLOW[1]
	portal(root, color)

	-- 2. tela preta enquanto o servidor leva o boneco
	phase = "waiting"
	root.Anchored = false
	humanoid.PlatformStand = false
	root.AssemblyLinearVelocity = Vector3.zero
	-- (uma sala nova pode levar um instante para ser montada no servidor)
	local deadline = os.clock() + 10
	local room, center = nil, nil
	local arrived = false
	while os.clock() < deadline do
		room, center = myRoom()
		if center and (root.Position - (center + Vector3.new(0, 3, ROOM.entry * K))).Magnitude <= 25 then
			arrived = true
			break
		end
		task.wait(0.05)
	end
	if arrived and room and center then
		-- espera as portas chegarem (o mapa é carregado aos poucos)
		local model = room:WaitForChild("boss_room", 2)
		if model then
			model:WaitForChild("DoorR_boss_room", 2)
		end
		intro(root, world, room, center)
	else
		Fx.black(0, 0.3)
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end
	phase = "idle"
end

-- O servidor manda o personagem sorteado na vitória contra o chefe.
task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BossReward") :: RemoteEvent
	remote.OnClientEvent:Connect(function(characterId: string, isNew: boolean)
		Roll.play(characterId, isNew)
	end)
end)

-- Faixas pretas de cinema (a cena do despertar do golem também usa).
BossRoom.letterbox = letterbox

function BossRoom.debug(): { [string]: any }
	return { phase = phase, doors = doorsOpen, room = player:GetAttribute("Room") }
end

return BossRoom
