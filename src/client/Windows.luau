--!strict
-- Janelas do jogo (mochila, loja, rebirth, índice, daily, playtime, atributos, automáticos) no
-- estilo "painel do sistema": um painel 3D flutuando na frente do boneco, com a câmera indo
-- para trás do ombro. O painel inclina de leve seguindo o cursor, tem borda e cantos brilhando,
-- e o braço direito do boneco aponta para onde o cursor está. Só uma janela aberta por vez.
-- Os números ficam em Config.Panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Aura = require(script.Parent.Aura)
local Pose = require(script.Parent.Pose)
local Ui = require(script.Parent.Ui)

local PANEL = Config.Panel
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local GLOW = Color3.fromRGB(150, 225, 255)
local DEEP = Color3.fromRGB(4, 9, 28)
local NAVY = Color3.fromRGB(12, 30, 78)

local Windows = {}

type Entry = { frame: Frame, open: boolean, refresh: (() -> ())? }

local entries: { [string]: Entry } = {}
local listeners: { () -> () } = {}

local stage: Part
local canvas: Frame
local flash: Frame
local light: PointLight
local shown = 0 -- 0 = fechado, 1 = aberto; anda até `target` a cada quadro
local target = 0
local holding = false -- a câmera está com o painel
local startCamera = CFrame.identity
local startFov = 70
local base = CFrame.identity -- onde o painel fica, sem a inclinação do cursor
local cameraGoal = CFrame.identity
local origin = Vector3.zero
local tilt = Vector2.zero
local lastMouse = Vector2.zero
local mouseMovedAt = 0
local muted: { [BasePart]: boolean } = {}

local function rootPart(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then root else nil
end

-- As peças do boneco ficam entre a câmera e o painel: enquanto ele está aberto elas não
-- seguram o clique (só neste cliente).
local function setCharacterQuery(restore: boolean)
	if restore then
		for part, was in muted do
			if part.Parent then
				part.CanQuery = was
			end
		end
		table.clear(muted)
		return
	end
	local character = player.Character
	if not character then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and muted[part] == nil then
			muted[part] = part.CanQuery
			part.CanQuery = false
		end
	end
end

local function ensureStage()
	if stage then
		return
	end
	stage = Instance.new("Part")
	stage.Name = "SystemPanel"
	stage.Anchored = true
	stage.CanCollide = false
	stage.CanTouch = false
	stage.CastShadow = false
	stage.Transparency = 1
	stage.Size = Vector3.new(PANEL.size.X, PANEL.size.Y, 0.05)
	light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 12
	light.Brightness = 0
	light.Parent = stage

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Menus"
	surface.ResetOnSpawn = false
	surface.Adornee = stage
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = PANEL.canvas
	surface.LightInfluence = 0
	surface.Brightness = PANEL.brightness
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surface.Parent = player:WaitForChild("PlayerGui")

	canvas = Ui.frame(surface, "Canvas", UDim2.fromScale(1, 1))
	-- clarão claro por cima de tudo: o painel nasce branco-azulado e o conteúdo aparece por baixo
	flash = Ui.frame(surface, "Flash", UDim2.fromScale(1, 1), nil, Color3.fromRGB(190, 235, 255))
	flash.BackgroundTransparency = 1
	flash.ZIndex = 50
	flash.Active = false

	-- braço direito apontando para o cursor; as juntas são recalculadas a cada quadro
	Pose.define("panelArm", { RightShoulder = CFrame.identity, RightElbow = Pose.deg(14, 0, 0) }, false, 10)
end

-- Moldura no estilo do painel: fundo azul-escuro em degradê, borda fina clara com halo,
-- cantoneiras brilhando, título numa caixa e um X no canto.
local function skin(frame: Frame, name: string, title: string, accent: Color3)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 55
	gradient.Color = ColorSequence.new(NAVY, DEEP)
	gradient.Parent = frame
	Ui.corner(frame, 6)
	Ui.border(frame, 2, GLOW)

	local halo = Ui.frame(frame, "Halo", UDim2.new(1, 14, 1, 14), UDim2.fromOffset(-7, -7))
	halo.ZIndex = 0
	Ui.corner(halo, 10)
	local haloStroke = Ui.border(halo, 6, GLOW)
	haloStroke.Transparency = 0.72
	TweenService:Create(haloStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.88 }):Play()

	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		for _, size in { Vector2.new(26, 5), Vector2.new(5, 26) } do
			local bracket = Ui.frame(frame, "Corner", UDim2.fromOffset(size.X, size.Y), UDim2.new(corner.X, if corner.X == 0 then -9 else 9, corner.Y, if corner.Y == 0 then -9 else 9), Color3.new(1, 1, 1), corner)
			bracket.ZIndex = 6
			Ui.corner(bracket, 2)
			Ui.border(bracket, 2, GLOW).Transparency = 0.35
		end
	end

	local header = Ui.text(frame, { name = "Title", text = title, color = Color3.fromRGB(215, 240, 255), size = UDim2.fromOffset(250, 30), position = UDim2.new(0.5, 0, 0, 8), anchor = Vector2.new(0.5, 0), textSize = 21, stroke = 0, z = 3 })
	header.Font = Enum.Font.GothamBlack
	header.BackgroundTransparency = 0
	header.BackgroundColor3 = DEEP
	Ui.border(header, 2, GLOW)
	local line = Ui.frame(header, "Accent", UDim2.new(1, 0, 0, 3), UDim2.new(0, 0, 1, -3), accent)
	line.ZIndex = 4

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 6)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = DEEP
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 22
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.ZIndex = 4
	Ui.border(close, 2, Color3.new(1, 1, 1))
	Ui.juice(close)
	close.Activated:Connect(function()
		Windows.set(name, false)
	end)
	close.Parent = frame
end

-- Cria a janela fechada e devolve a moldura para o conteúdo. refresh roda toda vez que ela abre.
function Windows.create(name: string, title: string, size: Vector2, accent: Color3, refresh: (() -> ())?): Frame
	ensureStage()
	local frame = Ui.frame(canvas, name, UDim2.fromOffset(size.X, size.Y), UDim2.fromScale(0.5, 0.5), nil, Vector2.new(0.5, 0.5))
	frame.BackgroundTransparency = 0
	frame.Visible = false
	skin(frame, name, title, accent)
	-- cada janela enche o painel, seja qual for o tamanho em que foi desenhada
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Scale = math.min((PANEL.canvas.X - PANEL.margin) / size.X, (PANEL.canvas.Y - PANEL.margin) / size.Y)
	fit.Parent = frame
	entries[name] = { frame = frame, open = false, refresh = refresh }
	return frame
end

function Windows.isOpen(name: string): boolean
	local entry = entries[name]
	return entry ~= nil and entry.open
end

-- Nome da janela aberta, ou nil.
function Windows.current(): string?
	for name, entry in entries do
		if entry.open then
			return name
		end
	end
	return nil
end

-- Posiciona painel e câmera a partir de onde o boneco está agora.
local function place(root: BasePart)
	local frame = CFrame.new(root.Position) * (root.CFrame - root.Position)
	local position = frame:PointToWorldSpace(PANEL.offset)
	local eye = frame:PointToWorldSpace(PANEL.cameraOffset)
	base = CFrame.lookAt(position, frame:PointToWorldSpace(PANEL.facing))
	cameraGoal = CFrame.lookAt(eye, frame:PointToWorldSpace(PANEL.lookAt))
	origin = root.Position
end

function Windows.set(name: string, open: boolean)
	local entry = entries[name]
	if not entry or entry.open == open then
		return
	end
	if not open then
		entry.open = false
		target = 0
		return
	end
	local root = rootPart()
	-- outra encenação está com a câmera (carga, corrida, super soco): não abre por cima
	if not root or (not holding and camera.CameraType ~= Enum.CameraType.Custom) then
		return
	end
	for other, otherEntry in entries do
		if otherEntry.open then
			otherEntry.open = false
		end
		otherEntry.frame.Visible = other == name
	end
	for _, listener in listeners do
		listener()
	end
	entry.open = true
	if entry.refresh then
		entry.refresh()
	end
	if not holding then
		holding = true
		startCamera = camera.CFrame
		startFov = camera.FieldOfView
		place(root)
		tilt = Vector2.zero
		stage.Parent = workspace
		camera.CameraType = Enum.CameraType.Scriptable
		setCharacterQuery(false)
		Aura.setHidden(true)
	end
	target = 1
	-- trocar de janela com o painel já aberto também pisca
	flash.BackgroundTransparency = 0.1
end

function Windows.toggle(name: string)
	Windows.set(name, not Windows.isOpen(name))
end

function Windows.closeAll()
	for name in entries do
		Windows.set(name, false)
	end
end

-- Avisa quando alguma janela abre.
function Windows.onOpen(listener: () -> ())
	table.insert(listeners, listener)
end

local function release()
	holding = false
	stage.Parent = nil
	light.Brightness = 0
	for _, entry in entries do
		entry.frame.Visible = false
	end
	Pose.weight("panelArm", 0)
	setCharacterQuery(true)
	Aura.setHidden(false)
	if camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = startFov
	end
end

-- Rotação que leva o braço pendurado (apontando para baixo) até a direção pedida.
local function aimArm(direction: Vector3): CFrame
	local down = -Vector3.yAxis
	local axis = down:Cross(direction)
	if axis.Magnitude < 1e-4 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(down:Dot(direction), -1, 1)))
end

local function step(dt: number)
	if not holding then
		return
	end
	local root = rootPart()
	if not root or (root.Position - origin).Magnitude > PANEL.leash then
		-- o boneco saiu de perto (andou, foi teleportado, morreu): fecha
		for _, entry in entries do
			entry.open = false
		end
		target = 0
		if not root then
			shown = 0
		end
	end

	if target > shown then
		shown = math.min(1, shown + dt / PANEL.openTime)
	elseif target < shown then
		shown = math.max(0, shown - dt / PANEL.openTime)
	end
	if shown <= 0 and target == 0 then
		release()
		return
	end
	local eased = 1 - (1 - shown) ^ 3

	-- câmera: sai de onde estava e vai para trás do ombro (e volta ao fechar)
	camera.CFrame = startCamera:Lerp(cameraGoal, eased)
	camera.FieldOfView = startFov + (PANEL.fieldOfView - startFov) * eased

	-- cursor no plano do painel: -1 a 1 em cada eixo; fora disso o cursor não está em cima dele
	local mouse = UserInputService:GetMouseLocation()
	if (mouse - lastMouse).Magnitude > 1 then
		lastMouse = mouse
		mouseMovedAt = os.clock()
	end
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local normal = base.LookVector
	local facing = ray.Direction:Dot(normal)
	local over = false
	local hit = base.Position
	local goal = Vector2.zero
	if math.abs(facing) > 1e-4 then
		hit = ray.Origin + ray.Direction * ((base.Position - ray.Origin):Dot(normal) / facing)
		local point = base:PointToObjectSpace(hit)
		local nx, ny = point.X / (PANEL.size.X / 2), point.Y / (PANEL.size.Y / 2)
		over = math.abs(nx) <= 1.05 and math.abs(ny) <= 1.05
		if over then
			goal = Vector2.new(math.clamp(nx, -1, 1), math.clamp(ny, -1, 1))
		end
	end
	tilt = tilt:Lerp(goal, 1 - math.exp(-PANEL.tiltSpeed * dt))

	-- abre de uma lâmina fina, ainda virada de lado, até o tamanho cheio
	local grow = 0.04 + 0.96 * eased
	stage.Size = Vector3.new(PANEL.size.X * grow, PANEL.size.Y * (0.25 + 0.75 * eased), 0.05)
	stage.CFrame = base
		* CFrame.Angles(math.rad(tilt.Y * PANEL.maxTilt), math.rad(-tilt.X * PANEL.maxTilt), 0)
		* CFrame.Angles(0, math.rad(PANEL.openTwist) * (1 - eased), math.rad(-8) * (1 - eased))
	light.Brightness = PANEL.lightBrightness * eased
	-- o clarão some sozinho depois de aberto e volta ao fechar
	local flashGoal = if target == 1 and shown >= 1 then 1 else 0.1
	flash.BackgroundTransparency += (flashGoal - flash.BackgroundTransparency) * (1 - math.exp(-9 * dt))

	-- braço direito: sobe e aponta para onde o cursor está no painel; parado um tempo, desce
	local character = player.Character
	local torso = character and character:FindFirstChild("UpperTorso")
	local pointing = over and shown >= 0.9 and target == 1 and os.clock() - mouseMovedAt < PANEL.armIdle
	if pointing and torso and torso:IsA("BasePart") then
		local shoulder = torso.CFrame:PointToWorldSpace(Vector3.new(torso.Size.X / 2 + 0.25, torso.Size.Y * 0.3, 0))
		local aim = hit - base.UpVector * PANEL.armDrop
		local direction = torso.CFrame:VectorToObjectSpace((aim - shoulder).Unit)
		Pose.define("panelArm", { RightShoulder = aimArm(direction), RightElbow = Pose.deg(14, 0, 0) })
		Pose.weight("panelArm", 1)
	else
		Pose.weight("panelArm", 0)
	end
end

-- Para os testes: onde o painel e a câmera estão agora.
function Windows.debug(): { [string]: any }
	local surface = player:FindFirstChildOfClass("PlayerGui") and (player:FindFirstChildOfClass("PlayerGui") :: PlayerGui):FindFirstChild("Menus")
	local onScreen, visible = camera:WorldToViewportPoint(stage.Position)
	return {
		holding = holding,
		shown = shown,
		parent = if stage.Parent then stage.Parent.Name else "nil",
		size = tostring(stage.Size),
		position = tostring(stage.Position),
		look = tostring(stage.CFrame.LookVector),
		camera = tostring(camera.CFrame.Position),
		cameraLook = tostring(camera.CFrame.LookVector),
		screen = tostring(onScreen),
		inView = visible,
		gui = if surface then surface.ClassName else "sem gui",
		adornee = if surface and surface:IsA("SurfaceGui") and surface.Adornee then surface.Adornee.Name else "sem adornee",
		viewport = tostring(camera.ViewportSize),
	}
end

-- depois da câmera padrão, para a nossa valer no quadro
RunService:BindToRenderStep("SystemPanel", Enum.RenderPriority.Camera.Value + 1, step)

return Windows
