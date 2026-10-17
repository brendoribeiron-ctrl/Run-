--!strict
-- Peças de interface reaproveitadas: texto com contorno, botões que reagem, escala por tela.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local P = Config.Palette
local Ui = {}

Ui.white = Color3.fromRGB(255, 255, 255)

function Ui.stroke(target: Instance, thickness: number, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color or P.outline
	stroke.Parent = target
	return stroke
end

function Ui.border(target: Instance, thickness: number, color: Color3?): UIStroke
	local stroke = Ui.stroke(target, thickness, color)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return stroke
end

function Ui.corner(target: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = target
end

type TextProps = {
	name: string?,
	text: string,
	color: Color3?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?, -- sem textSize o texto escala para caber
	stroke: number?,
	align: Enum.TextXAlignment?,
	z: number?,
}

function Ui.text(parent: Instance, props: TextProps): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = props.name or "Label"
	t.BackgroundTransparency = 1
	t.Size = props.size
	t.Position = props.position or UDim2.new()
	t.AnchorPoint = props.anchor or Vector2.zero
	t.Font = Enum.Font.FredokaOne
	t.Text = props.text
	t.TextColor3 = props.color or Ui.white
	t.TextXAlignment = props.align or Enum.TextXAlignment.Center
	t.ZIndex = props.z or 1
	if props.textSize then
		t.TextSize = props.textSize
	else
		t.TextScaled = true
	end
	if props.stroke ~= 0 then
		Ui.stroke(t, props.stroke or 3)
	end
	t.Parent = parent
	return t
end

function Ui.frame(parent: Instance, name: string, size: UDim2, position: UDim2?, color: Color3?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position or UDim2.new()
	f.AnchorPoint = anchor or Vector2.zero
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	f.Parent = parent
	return f
end

function Ui.gradient(target: Instance, top: Color3, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Parent = target
end

-- Escala ao passar o mouse e ao apertar.
function Ui.juice(button: GuiButton, target: GuiObject?)
	local scale = Instance.new("UIScale")
	scale.Parent = target or button
	local function to(value: number, time: number, style: Enum.EasingStyle)
		TweenService:Create(scale, TweenInfo.new(time, style, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		to(1.07, 0.12, Enum.EasingStyle.Quad)
	end)
	button.MouseLeave:Connect(function()
		to(1, 0.12, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Down:Connect(function()
		to(0.9, 0.06, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Up:Connect(function()
		to(1.07, 0.2, Enum.EasingStyle.Back)
	end)
end

-- Botão transparente cobrindo um bloco visual.
function Ui.hit(parent: GuiObject, name: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 20
	button.Parent = parent
	return button
end

-- Mantém um bloco do HUD proporcional à altura da tela.
function Ui.autoScale(target: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = target
	local camera = workspace.CurrentCamera
	-- atributos do alvo: PlatformScale (texto menor no celular, client/Platform.luau) e
	-- UserScale (tamanho escolhido no editor do HUD)
	local function factor(name: string): number
		local value = target:GetAttribute(name)
		return if type(value) == "number" then value else 1
	end
	local function update()
		scale.Scale = math.clamp(camera.ViewportSize.Y / 900, 0.6, 1.2) * factor("PlatformScale") * factor("UserScale")
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	target:GetAttributeChangedSignal("PlatformScale"):Connect(update)
	target:GetAttributeChangedSignal("UserScale"):Connect(update)
	update()
end

-- Selo vermelho "!" pulsando no canto.
function Ui.badge(parent: Instance): TextLabel
	local badge = Ui.text(parent, { name = "Badge", text = "!", size = UDim2.fromOffset(26, 26), position = UDim2.new(1, -8, 0, -8), anchor = Vector2.new(0.5, 0.5), stroke = 0, z = 5 })
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = P.red
	Ui.corner(badge, 13)
	Ui.border(badge, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = badge
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.25 }):Play()
	return badge
end

return Ui
