--!strict
-- Efeitos locais: clarão, tremor de câmera, estouros, cubos de entulho, título grande, tela preta.
-- Tudo roda só neste cliente; o servidor apenas avisa o que aconteceu.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Platform = require(script.Parent.Platform)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Fx = {}

local gui = Instance.new("ScreenGui")
gui.Name = "Fx"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui

local flashFrame = Ui.frame(gui, "Flash", UDim2.fromScale(1, 1), nil, Ui.white)
flashFrame.BackgroundTransparency = 1
flashFrame.ZIndex = 10
local blackFrame = Ui.frame(gui, "Black", UDim2.fromScale(1, 1), nil, Color3.new(0, 0, 0))
blackFrame.BackgroundTransparency = 1
blackFrame.ZIndex = 20

local folder = Instance.new("Folder")
folder.Name = "LocalFx"
folder.Parent = workspace
Fx.folder = folder

local trauma = 0
local rng = Random.new()

local function ease(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
end

function Fx.part(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Shape = shape or Enum.PartType.Block
	p.Parent = folder
	return p
end

function Fx.flash(color: Color3?, strength: number?, time: number?)
	flashFrame.BackgroundColor3 = color or Ui.white
	flashFrame.BackgroundTransparency = 1 - (strength or 1)
	TweenService:Create(flashFrame, ease(time or 0.4), { BackgroundTransparency = 1 }):Play()
end

function Fx.black(alpha: number, time: number)
	TweenService:Create(blackFrame, ease(time, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 - alpha }):Play()
end

function Fx.shake(amount: number)
	trauma = math.min(trauma + amount, 1.5)
end

-- Deslocamento do tremor neste quadro, para câmeras roteirizadas.
function Fx.shakeCFrame(): CFrame
	if trauma <= 0 then
		return CFrame.identity
	end
	local a = trauma * trauma
	return CFrame.new(rng:NextNumber(-1, 1) * a, rng:NextNumber(-1, 1) * a, 0) * CFrame.Angles(0, 0, rng:NextNumber(-1, 1) * a * 0.03)
end

-- Esfera que cresce e some.
function Fx.burst(position: Vector3, color: Color3, size: number, time: number?)
	local ball = Fx.part(Vector3.one * size * 0.2, CFrame.new(position), color, Enum.Material.Neon, Enum.PartType.Ball)
	ball.Transparency = 0.15
	local tween = TweenService:Create(ball, ease(time or 0.3), { Size = Vector3.one * size, Transparency = 1 })
	tween.Completed:Connect(function()
		ball:Destroy()
	end)
	tween:Play()
end

-- Onda de choque: disco fino no chão que abre e some.
function Fx.ring(position: Vector3, color: Color3, size: number, time: number?)
	local disc = Fx.part(Vector3.new(0.15, size * 0.15, size * 0.15), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.Transparency = 0.35
	local tween = TweenService:Create(disc, ease(time or 0.4), { Size = Vector3.new(0.15, size, size), Transparency = 1 })
	tween.Completed:Connect(function()
		disc:Destroy()
	end)
	tween:Play()
end

-- Onda de impacto de frente: disco fino virado para uma direção (parede de ar do soco).
function Fx.shock(position: Vector3, normal: Vector3, color: Color3, size: number, time: number?)
	local facing = CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.rad(90), 0)
	local disc = Fx.part(Vector3.new(0.12, size * 0.2, size * 0.2), facing, color, Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.Transparency = 0.3
	local tween = TweenService:Create(disc, ease(time or 0.3), { Size = Vector3.new(0.12, size, size), Transparency = 1, CFrame = facing + normal * (size * 0.12) })
	tween.Completed:Connect(function()
		disc:Destroy()
	end)
	tween:Play()
end

-- Estrela de impacto: barras cruzadas que abrem rápido e somem. count = 2 faz um X.
function Fx.star(position: Vector3, normal: Vector3, color: Color3, length: number, count: number?, time: number?)
	local base = CFrame.lookAt(position, position + normal)
	local total = count or 3
	for i = 1, total do
		local spin = base * CFrame.Angles(0, 0, math.pi * i / total + rng:NextNumber(-0.2, 0.2))
		local bar = Fx.part(Vector3.new(length * 0.25, 0.28, 0.12), spin, color, Enum.Material.Neon)
		local tween = TweenService:Create(bar, ease(time or 0.22), { Size = Vector3.new(length, 0.04, 0.05), Transparency = 1 })
		tween.Completed:Connect(function()
			bar:Destroy()
		end)
		tween:Play()
	end
end

-- Fantasma: cópia de neon das peças do personagem que some (rastro de dash).
function Fx.ghost(character: Model, color: Color3, time: number?)
	for _, piece in character:GetChildren() do
		if piece:IsA("BasePart") and piece.Transparency < 1 and piece.Name ~= "HumanoidRootPart" and piece.Name ~= "AuraBase" and piece.Name ~= "AuraFeet" then
			local copy = Fx.part(piece.Size, piece.CFrame, color, Enum.Material.Neon)
			copy.Transparency = 0.45
			local tween = TweenService:Create(copy, ease(time or 0.35), { Transparency = 1 })
			tween.Completed:Connect(function()
				copy:Destroy()
			end)
			tween:Play()
		end
	end
end

-- Risco de energia: barra fina de neon que anda numa direção e some.
function Fx.streak(position: Vector3, travel: Vector3, color: Color3, length: number, time: number?)
	local goal = position + travel
	local bar = Fx.part(Vector3.new(0.18, 0.18, length), CFrame.lookAt(position, goal), color, Enum.Material.Neon)
	bar.Transparency = 0.1
	local tween = TweenService:Create(bar, ease(time or 0.35), { CFrame = CFrame.lookAt(goal, goal + travel), Transparency = 1, Size = Vector3.new(0.05, 0.05, length * 1.6) })
	tween.Completed:Connect(function()
		bar:Destroy()
	end)
	tween:Play()
end

-- Cubos soltos voando; direction puxa o jato para um lado.
function Fx.cubes(position: Vector3, color: Color3, count: number, speed: number, direction: Vector3?, cubeSize: number?, material: Enum.Material?)
	for _ = 1, count do
		local size = (cubeSize or 1) * rng:NextNumber(0.6, 1.3)
		local cube = Fx.part(Vector3.one * size, CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), color, material or Enum.Material.SmoothPlastic)
		cube.Anchored = false
		local spread = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.3, 1.2), rng:NextNumber(-1, 1))
		cube.AssemblyLinearVelocity = spread * speed + (direction or Vector3.zero)
		cube.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		TweenService:Create(cube, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55), { Transparency = 1, Size = Vector3.one * 0.1 }):Play()
		Debris:AddItem(cube, 1)
	end
end

-- Título grande no centro da tela: entra estalando, segura, some.
function Fx.title(text: string, color: Color3, hold: number?)
	local label = Ui.text(gui, { name = "Title", text = text, color = color, size = UDim2.new(0.8, 0, 0, 110 * Platform.textScale()), position = UDim2.fromScale(0.5, 0.3), anchor = Vector2.new(0.5, 0.5), stroke = 6, z = 12 })
	label.Rotation = -4
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = label
	TweenService:Create(scale, ease(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(hold or 1.4, function()
		local out = TweenService:Create(scale, ease(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		out.Completed:Connect(function()
			label:Destroy()
		end)
		out:Play()
	end)
end

-- Texto curto que sobe e some (números, avisos).
function Fx.toast(text: string, color: Color3?)
	local label = Ui.text(gui, { name = "Toast", text = text, color = color or Ui.white, size = UDim2.new(0.6, 0, 0, 44 * Platform.textScale()), position = UDim2.fromScale(0.5, 0.72), anchor = Vector2.new(0.5, 0.5), stroke = 4, z = 12 })
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	TweenService:Create(scale, ease(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.1), { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.66) }):Play()
	Debris:AddItem(label, 1.6)
end

-- Revelação de marco: clarão, pilar de luz, título, empurrão de câmera e bolha no fim.
function Fx.reveal(text: string, color: Color3, position: Vector3?)
	Fx.title(text, color, 1.6)
	Fx.shake(0.6)
	task.delay(0.1, Fx.flash, Ui.white, 0.9, 0.5)

	local camera = workspace.CurrentCamera
	local fov = camera.FieldOfView
	TweenService:Create(camera, ease(0.25), { FieldOfView = fov - 12 }):Play()
	task.delay(0.5, function()
		TweenService:Create(camera, ease(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { FieldOfView = 70 }):Play()
	end)

	if not position then
		return
	end
	local base = Vector3.new(position.X, Config.World.groundY, position.Z)
	local pillar = Fx.part(Vector3.new(400, 1, 1), CFrame.new(base + Vector3.new(0, 200, 0)) * CFrame.Angles(0, 0, math.rad(90)), color:Lerp(Ui.white, 0.6), Enum.Material.Neon, Enum.PartType.Cylinder)
	pillar.Transparency = 0.1
	TweenService:Create(pillar, ease(0.2), { Size = Vector3.new(400, 9, 9) }):Play()
	task.delay(0.7, function()
		local out = TweenService:Create(pillar, ease(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(400, 0.2, 0.2), Transparency = 1 })
		out.Completed:Connect(function()
			pillar:Destroy()
		end)
		out:Play()
	end)
	Fx.cubes(base + Vector3.new(0, 1, 0), color, 14, 30, nil, 1.2, Enum.Material.Neon)
	task.delay(1.3, Fx.burst, base + Vector3.new(0, 3, 0), color, 22, 0.5)
end

RunService.RenderStepped:Connect(function(dt)
	trauma = math.max(0, trauma - dt * 1.8)
	-- com a câmera padrão o tremor entra pelo deslocamento do Humanoid
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and workspace.CurrentCamera.CameraType == Enum.CameraType.Custom then
		local a = trauma * trauma
		humanoid.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * a * 0.6
	end
end)

return Fx
