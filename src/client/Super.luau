--!strict
-- Super soco: minigame de teclas no tempo certo. O servidor abre de vez em quando (chance por
-- soco, mais rara que o crítico). Um marcador cruza a barra; aperte a tecla mostrada quando ele estiver na zona verde.
-- Acertou todas: soco gigante (o servidor paga). Errou: o boneco é jogado para longe.
-- No toque, o quadro da tecla é o botão. Os números ficam em Config.Super.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Aura = require(script.Parent.Aura)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(script.Parent.Fx)
local Platform = require(script.Parent.Platform)
local Pose = require(script.Parent.Pose)
local Ui = require(script.Parent.Ui)

local P = Config.Palette
local SUPER = Config.Super
local player = Players.LocalPlayer
local deg = Pose.deg
local GOLD = Color3.fromRGB(255, 214, 40)
local GREEN = Color3.fromRGB(60, 210, 90)
local DARK = Color3.fromRGB(24, 28, 46)
local DIRT = Color3.fromRGB(122, 80, 40)
local rng = Random.new()

local Super = {}

-- Bag.luau liga aqui o balanço do saco no impacto.
Super.onImpact = nil :: (() -> ())?

type Step = { key: string, zone: number, time: number }

local remote: RemoteEvent
local token: number? = nil -- senha do minigame aberto
local steps: { Step } = {}
local index = 0
local stepStart = 0
local busyUntil = 0 -- soco ou queda em andamento: o saco não aceita socos comuns
local punchStart = -10
local failStart = -10

local panel: Frame
local panelScale: UIScale
local boxes: { TextButton } = {}
local bar: Frame
local zone: Frame
local marker: Frame

local tint: ColorCorrectionEffect

local function parts(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function bagCenter(): Vector3?
	local plot = Config.plotOf(player)
	local gantry = plot and plot:FindFirstChild("Gantry")
	local bag = gantry and gantry:FindFirstChild("Bag")
	local center = bag and bag:GetAttribute("Center")
	return if typeof(center) == "Vector3" then center else nil
end

function Super.isActive(): boolean
	return token ~= nil
end

-- Minigame aberto, soco em andamento ou boneco caído.
function Super.isBusy(): boolean
	return token ~= nil or os.clock() < busyUntil
end

---------------------------------------------------------------------------------------------------
-- Interface

local function showStep()
	local step = steps[index]
	for i, box in boxes do
		local current = i == index
		box.Visible = i <= #steps
		box.BackgroundColor3 = if i < index then GREEN elseif current then GOLD else DARK
		box.TextTransparency = if i > index then 0.6 else 0
		local scale = box:FindFirstChildOfClass("UIScale") :: UIScale
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = if current then 1.25 else 1 }):Play()
	end
	if step then
		zone.Position = UDim2.fromScale(step.zone, 0)
		zone.Size = UDim2.fromScale(SUPER.zoneWidth, 1)
	end
end

local function closePanel()
	TweenService:Create(panelScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.5 }):Play()
	task.delay(0.15, function()
		if token == nil then
			panel.Visible = false
		end
	end)
	Pose.weight("superWind", 0)
end

---------------------------------------------------------------------------------------------------
-- Desfecho

-- Coluna de luz subindo do saco: nasce larga e afina até sumir.
local function pillar(position: Vector3, color: Color3, width: number, time: number)
	local beam = Fx.part(Vector3.new(160, width, width), CFrame.new(position + Vector3.new(0, 70, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	beam.Transparency = 0.15
	TweenService:Create(beam, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(160, 0.4, 0.4), Transparency = 1 }):Play()
	task.delay(time, beam.Destroy, beam)
end

-- O golpe: clarão, coluna de luz, ondas em sequência, chão rachando em anéis e entulho.
local function impact(root: BasePart, center: Vector3, dir: Vector3)
	local cinema = workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable
	local front, back = center - dir * 1.8, center + dir * 1.8
	local floor = Vector3.new(center.X, root.Position.Y - 2.8, center.Z)
	local bright = GOLD:Lerp(Ui.white, 0.5)
	Aura.setBoost(0)
	TweenService:Create(tint, TweenInfo.new(0.5), { Saturation = 0, Contrast = 0, Brightness = 0 }):Play()

	Fx.flash(Ui.white, 1, 0.14)
	task.delay(0.12, Fx.flash, GOLD, 0.3, 0.3)
	Fx.shake(if cinema then 2.2 else 1.1)
	local camera = workspace.CurrentCamera
	if camera.CameraType == Enum.CameraType.Custom then
		camera.FieldOfView = 98
		TweenService:Create(camera, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { FieldOfView = 70 }):Play()
	end

	-- no saco: estrela, núcleo branco, coluna de luz
	Fx.star(front, -dir, GOLD, 40, 3, 0.55)
	Fx.star(front, -dir, Ui.white, 22, 6, 0.4)
	Fx.burst(center, Ui.white, 30, 0.35)
	task.delay(0.1, Fx.burst, center, GOLD, 46, 0.5)
	pillar(floor, Ui.white, 16, 0.7)
	task.delay(0.08, pillar, floor, GOLD, 26, 0.9)

	-- ondas de ar saindo por trás do saco, cada uma maior e mais longe
	for i = 0, 4 do
		task.delay(i * 0.07, Fx.shock, back + dir * (i * 5), dir, if i % 2 == 0 then GOLD else Ui.white, 22 + i * 14, 0.4 + i * 0.06)
	end
	-- anéis no chão, em sequência
	for i = 0, 3 do
		task.delay(i * 0.11, Fx.ring, floor + Vector3.new(0, 0.2, 0), if i % 2 == 0 then GOLD else Ui.white, 46 + i * 34, 0.55)
	end
	-- entulho: neon para a frente, terra para todo lado
	Fx.cubes(back, GOLD, 30, 40, dir * 70 + Vector3.new(0, 22, 0), 1.3, Enum.Material.Neon)
	Fx.cubes(floor + Vector3.new(0, 1, 0), DIRT, 22, 30, Vector3.new(0, 34, 0), 1.6)
	-- raios em leque e riscos rente ao chão
	for i = 1, 22 do
		local around = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, i * math.pi / 11) * Vector3.yAxis
		Fx.streak(center + around * 1.5, around * 22 + dir * 10, bright, 8, 0.5)
		local flat = Vector3.new(math.cos(i * math.pi / 11), 0, math.sin(i * math.pi / 11))
		Fx.streak(floor + flat * 3 + Vector3.new(0, 0.4, 0), flat * 30, Ui.white, 6, 0.4)
	end
	-- o boneco deixa rastros dourados no avanço
	local character = root.Parent
	if character and character:IsA("Model") then
		for i = 0, 2 do
			task.delay(i * 0.05, Fx.ghost, character, GOLD, 0.45)
		end
	end
	-- réplicas: dois tremores menores
	task.delay(0.3, Fx.shake, 0.9)
	task.delay(0.55, Fx.shake, 0.5)
	Fx.title("SUPER PUNCH!", GOLD, 0.8)
	if Super.onImpact then
		Super.onImpact()
	end
end

-- Câmera de cinema do super soco. Juntando energia: close baixo que gira em volta do boneco e
-- chega perto. No golpe: corte seco para um plano aberto de lado, recuando. Depois devolve
-- a câmera ao jogador.
local function cinematic(root: BasePart, center: Vector3, dir: Vector3)
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local side = dir:Cross(Vector3.yAxis)
	local began = os.clock()
	local total = SUPER.windTime + SUPER.holdTime + SUPER.cameraLinger
	local cut = false
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - began
		if t >= total or not root.Parent then
			connection:Disconnect()
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			return
		end
		if t < SUPER.windTime then
			local p = t / SUPER.windTime
			local chest = root.Position + Vector3.new(0, 0.8, 0)
			local angle = math.rad(30 + 45 * p)
			local eye = chest + (dir * math.cos(angle) + side * math.sin(angle)) * (10 - 4 * p) + Vector3.new(0, -1 + 1.5 * p, 0)
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, chest), 1 - math.exp(-14 * dt)) * Fx.shakeCFrame()
			camera.FieldOfView = 62 - 20 * p
		else
			local p = math.clamp((t - SUPER.windTime) / 0.3, 0, 1)
			local middle = (root.Position + center) / 2 + Vector3.new(0, 1.5, 0)
			local goal = CFrame.lookAt(middle + side * (15 + 9 * p) - dir * 5 + Vector3.new(0, 3.5 + 2 * p, 0), middle + dir * 4)
			if not cut then
				cut = true
				camera.CFrame = goal
			end
			camera.CFrame = camera.CFrame:Lerp(goal, 1 - math.exp(-10 * dt)) * Fx.shakeCFrame()
			camera.FieldOfView = 100 - 28 * p
		end
	end)
end

-- O super soco em si. cinema = veio do minigame: câmera de cinema e imagem escurecendo.
-- No AUTO SUPER (cinema = false) o soco acontece sem tirar a câmera do jogador.
local function punch(cinema: boolean)
	busyUntil = os.clock() + SUPER.windTime + SUPER.holdTime
	punchStart = os.clock()

	local _, root = parts()
	local center = bagCenter()
	if not root or not center then
		return
	end
	local flat = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)

	if cinema then
		cinematic(root, center, dir)
	end
	-- juntando energia: a imagem escurece e aproxima, a aura sobe, riscos convergem no punho
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	Aura.setBoost(1)
	if cinema then
		TweenService:Create(tint, TweenInfo.new(SUPER.windTime * 0.6), { Saturation = -0.55, Contrast = 0.3, Brightness = -0.12 }):Play()
	end
	Fx.ring(feet + Vector3.new(0, 0.2, 0), GOLD, 24, 0.45)
	task.delay(SUPER.windTime * 0.5, Fx.ring, feet + Vector3.new(0, 0.2, 0), Ui.white, 34, 0.4)
	Fx.cubes(feet + Vector3.new(0, 0.5, 0), DIRT, 10, 12, Vector3.new(0, 18, 0), 0.9)
	task.spawn(function()
		local began = os.clock()
		while os.clock() - began < SUPER.windTime do
			local dt = RunService.RenderStepped:Wait()
			local p = (os.clock() - began) / SUPER.windTime
			local fist = root.Position + root.CFrame.RightVector * 1.3 - dir * 1.1 + Vector3.new(0, 0.4, 0)
			for _ = 1, 3 do
				local from = fist + rng:NextUnitVector() * rng:NextNumber(7, 13)
				Fx.streak(from, (fist - from) * 0.9, GOLD:Lerp(Ui.white, 0.4), 3 + p * 4, 0.16)
			end
			Fx.burst(fist, GOLD:Lerp(Ui.white, p), 1 + p * 2.5, 0.08)
			Fx.shake(dt * 5 * p)
		end
		if root.Parent then
			impact(root, center, dir)
		else
			Aura.setBoost(0)
			tint.Saturation, tint.Contrast, tint.Brightness = 0, 0, 0
		end
	end)
end

local function succeed()
	local sent = token
	token = nil
	remote:FireServer(sent, true)
	closePanel()
	punch(true)
end

local function fail(reason: string)
	local sent = token
	token = nil
	remote:FireServer(sent, false)
	closePanel()
	busyUntil = os.clock() + SUPER.stunTime
	failStart = os.clock()
	Fx.toast(reason, P.red)
	Fx.flash(P.red, 0.35, 0.25)
	Fx.shake(0.9)

	local humanoid, root = parts()
	if not humanoid or not root then
		return
	end
	-- o saco devolve o golpe: o boneco voa para trás, girando, e fica caído um instante
	local center = bagCenter()
	local flat = if center then Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z) else -root.CFrame.LookVector
	local away = if flat.Magnitude > 0.1 then flat.Unit else -root.CFrame.LookVector
	Fx.burst(root.Position, Ui.white, 12, 0.3)
	Fx.star(root.Position - away * 1.5, away, P.red, 14, 3, 0.3)
	Fx.cubes(root.Position, P.red, 10, 20, away * 20 + Vector3.new(0, 14, 0), 0.8)
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = away * SUPER.ejectSpeed + Vector3.new(0, SUPER.ejectUp, 0)
	root.AssemblyAngularVelocity = Vector3.new(away.Z, 0, -away.X) * -7
	task.delay(SUPER.stunTime, function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

-- Uma tecla (ou o toque no quadro dela). Fora do minigame não faz nada.
function Super.press(key: string)
	local step = steps[index]
	if token == nil or not step then
		return
	end
	local t = (os.clock() - stepStart) / step.time
	if t < 0 then
		return -- respiro entre duas teclas: um aperto a mais não conta como erro
	end
	if key ~= step.key then
		fail("WRONG KEY!")
	elseif t < step.zone - SUPER.tolerance then
		fail("TOO EARLY!")
	elseif t > step.zone + SUPER.zoneWidth + SUPER.tolerance then
		fail("TOO LATE!")
	else
		Fx.shake(0.2)
		index += 1
		if index > #steps then
			succeed()
		else
			stepStart = os.clock() + SUPER.stepPause
			showStep()
		end
	end
end

local function begin(newToken: number, newSteps: { Step })
	local humanoid, root = parts()
	token = newToken
	steps = newSteps
	index = 1
	stepStart = os.clock()
	panel.Visible = true
	panelScale.Scale = 0.5
	TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	for i, box in boxes do
		box.Text = if newSteps[i] then newSteps[i].key else ""
	end
	showStep()
	Pose.weight("superWind", 1)
	Fx.flash(GOLD, 0.25, 0.2)
	local center = bagCenter()
	if humanoid and root and center and humanoid.MoveDirection.Magnitude < 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(center.X, root.Position.Y, center.Z))
	end
end

local function step()
	local now = os.clock()
	local current = steps[index]
	if token ~= nil and current then
		local t = (now - stepStart) / current.time
		marker.Position = UDim2.fromScale(math.clamp(t, 0, 1), 0.5)
		if t > 1 then
			fail("TOO LATE!")
		end
	end

	-- soco: enrola o corpo juntando energia, estala para a frente, segura e volta
	local since = now - punchStart
	local coiling = since < SUPER.windTime
	local striking = not coiling and since < SUPER.windTime + SUPER.holdTime
	Pose.weight("superCoil", if coiling then 1 else 0, not coiling)
	Pose.weight("superHit", if striking then 1 else 0, striking)
	Pose.weight("superFail", if now - failStart < SUPER.stunTime then 1 else 0)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Super"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")


	panel = Ui.frame(gui, "Panel", UDim2.fromOffset(440, 190), UDim2.fromScale(0.5, 0.22), P.navy, Vector2.new(0.5, 0.5))
	panel.Visible = false
	Ui.corner(panel, 20)
	Ui.border(panel, 5, GOLD)
	Ui.autoScale(panel)
	local pop = Ui.frame(panel, "Pop", UDim2.fromScale(1, 1))
	panelScale = Instance.new("UIScale")
	panelScale.Parent = pop
	local title = Ui.text(pop, { name = "Title", text = "SUPER PUNCH!", color = GOLD, size = UDim2.new(1, 0, 0, 36), position = UDim2.fromOffset(0, 8), textSize = 30, stroke = 4 })
	local help = Ui.text(pop, { name = "Help", text = "Press the key in the green zone", color = Color3.fromRGB(200, 215, 255), size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 42), textSize = 16, stroke = 2 })
	-- no celular o texto encolhe; os quadros das teclas não (no toque eles são os botões)
	Platform.watch(function()
		title.TextSize = math.floor(30 * Platform.textScale())
		help.TextSize = math.floor(16 * Platform.textScale())
		help.Text = if Platform.isTouch() then "Tap the key in the green zone" else "Press the key in the green zone"
	end)

	for i = 1, SUPER.steps do
		local box = Instance.new("TextButton")
		box.Name = "Key" .. i
		box.AnchorPoint = Vector2.new(0.5, 0)
		box.Position = UDim2.new(0.5, (i - (SUPER.steps + 1) / 2) * 84, 0, 70)
		box.Size = UDim2.fromOffset(62, 62)
		box.BackgroundColor3 = DARK
		box.AutoButtonColor = false
		box.Font = Enum.Font.FredokaOne
		box.TextSize = 38
		box.TextColor3 = Ui.white
		box.Text = ""
		Ui.corner(box, 12)
		Ui.border(box, 4)
		Ui.stroke(box, 3)
		local scale = Instance.new("UIScale")
		scale.Parent = box
		-- toque: o quadro vale como a tecla escrita nele
		box.MouseButton1Down:Connect(function()
			if box.Text ~= "" then
				Super.press(box.Text)
			end
		end)
		box.Parent = pop
		boxes[i] = box
	end

	bar = Ui.frame(pop, "Bar", UDim2.new(1, -48, 0, 24), UDim2.new(0, 24, 1, -40), Color3.fromRGB(10, 10, 16))
	Ui.corner(bar, 8)
	Ui.border(bar, 3)
	zone = Ui.frame(bar, "Zone", UDim2.fromScale(SUPER.zoneWidth, 1), nil, GREEN)
	Ui.corner(zone, 6)
	marker = Ui.frame(bar, "Marker", UDim2.new(0, 8, 1, 14), UDim2.fromScale(0, 0.5), Ui.white, Vector2.new(0.5, 0.5))
	marker.ZIndex = 3
	Ui.corner(marker, 4)
	Ui.border(marker, 2)
end

function Super.start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Super") :: RemoteEvent
	build()

	-- armando o soco: afundado, braço direito puxado lá atrás
	Pose.define("superWind", {
		Root = CFrame.new(0, -0.6, 0.25) * deg(-10, -34, 0),
		Waist = deg(-10, -30, 0),
		Neck = deg(6, 46, 0),
		RightShoulder = deg(-40, 0, 30),
		RightElbow = deg(120, 0, 0),
		LeftShoulder = deg(70, 0, 10),
		LeftElbow = deg(70, 0, 0),
		RightHip = deg(-30, 0, 8),
		RightKnee = deg(-50, 0, 0),
		LeftHip = deg(40, 0, -6),
		LeftKnee = deg(-56, 0, 0),
	}, false, 8)
	-- juntando energia: mais fundo e mais torcido que a pose de armar, punho lá atrás
	Pose.define("superCoil", {
		Root = CFrame.new(0, -0.95, 0.5) * deg(-16, -52, 0),
		Waist = deg(-14, -44, 0),
		Neck = deg(10, 70, 0),
		RightShoulder = deg(-62, 0, 36),
		RightElbow = deg(132, 0, 0),
		LeftShoulder = deg(88, 0, 4),
		LeftElbow = deg(24, 0, 0),
		RightHip = deg(-40, 0, 10),
		RightKnee = deg(-72, 0, 0),
		LeftHip = deg(52, 0, -8),
		LeftKnee = deg(-78, 0, 0),
	}, false, 10)
	-- o soco: corpo inteiro lançado para a frente, braço direito esticado
	Pose.define("superHit", {
		Root = CFrame.new(0, -0.35, -1.1) * deg(-22, 40, 0),
		Waist = deg(-16, 50, 0),
		Neck = deg(10, -50, 0),
		RightShoulder = deg(104, 0, 12),
		RightElbow = deg(0, 0, 0),
		LeftShoulder = deg(-30, 0, -30),
		LeftElbow = deg(60, 0, 0),
		RightHip = deg(-44, 0, 6),
		RightKnee = deg(-10, 0, 0),
		LeftHip = deg(54, 0, -6),
		LeftKnee = deg(-70, 0, 0),
	}, false, 50)
	-- errou: braços e pernas abertos, cabeça para trás, enquanto voa
	Pose.define("superFail", {
		Waist = deg(20, 0, 0),
		Neck = deg(-30, 0, 0),
		RightShoulder = deg(140, 0, 60),
		LeftShoulder = deg(140, 0, -60),
		RightElbow = deg(30, 0, 0),
		LeftElbow = deg(30, 0, 0),
		RightHip = deg(50, 0, 30),
		LeftHip = deg(20, 0, -30),
		RightKnee = deg(-60, 0, 0),
		LeftKnee = deg(-30, 0, 0),
	}, false, 30)

	remote.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "start" then
			begin(a, b)
		elseif kind == "auto" then
			-- AUTO SUPER: o servidor já pagou; aqui é só o soco
			punch(false)
			task.delay(SUPER.windTime + 0.25, Fx.toast, `+{Format.abbreviate(a)} POWER`, GOLD)
		elseif kind == "result" and a == true then
			-- o número aparece no golpe, não enquanto o boneco ainda junta energia
			task.delay(math.max(0, punchStart + SUPER.windTime + 0.25 - os.clock()), Fx.toast, `+{Format.abbreviate(b)} POWER`, GOLD)
		end
	end)

	local keys: { [Enum.KeyCode]: string } = {}
	for _, name in SUPER.keys do
		keys[(Enum.KeyCode :: any)[name]] = name
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = keys[input.KeyCode]
		if key and not processed then
			Super.press(key)
		end
	end)

	player.CharacterAdded:Connect(function()
		if token ~= nil then
			fail("TOO LATE!")
		end
	end)
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "SuperTint"
	tint.Parent = Lighting
	RunService.RenderStepped:Connect(step)
end

-- Para os testes: o que o minigame está pedindo agora.
function Super.debug(): { active: boolean, index: number, key: string?, zone: number?, time: number?, elapsed: number }
	local current = steps[index]
	return {
		active = token ~= nil,
		index = index,
		key = if current then current.key else nil,
		zone = if current then current.zone else nil,
		time = if current then current.time else nil,
		elapsed = os.clock() - stepStart,
	}
end

return Super
