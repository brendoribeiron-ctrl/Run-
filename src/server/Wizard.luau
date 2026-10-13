--!strict
-- O feiticeiro da casa de feitiçaria: fica num canto do salão e guarda a passagem para os outros
-- mundos. O modelo vem do Blender (tools/blender/wizard.py). Aqui ele é posto no lugar e ganha
-- colisão, luz, a placa com o nome e o aviso de conversar; a conversa e o balanço de flutuar
-- ficam no cliente (src/client/Worlds.luau), e quem decide se o jogador viaja é o servidor
-- (travel, em init.server.luau). As medidas ficam em Config.Wizard.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(script.Parent.Models)

local W = Config.Wizard
local S = Config.Sanctum
local MODEL_HEIGHT = 10.5 -- altura do modelo como sai do Blender, em studs

local Wizard = {}

local spot: Vector3? = nil

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STYLE: { [string]: Models.Style } = {
	Robe = { color = rgb(104, 52, 200), material = Enum.Material.Fabric },
	Cloak = { color = rgb(40, 28, 96), material = Enum.Material.Fabric },
	Hat = { color = rgb(84, 40, 170), material = Enum.Material.Fabric },
	Gold = { color = rgb(255, 196, 60), material = Enum.Material.Metal },
	Glow = { color = rgb(120, 255, 230), material = Enum.Material.Neon },
	Crystal = { color = rgb(110, 225, 255), material = Enum.Material.Neon },
	Orb = { color = rgb(255, 120, 30), material = Enum.Material.Neon },
	Skin = { color = rgb(238, 190, 150), material = Enum.Material.SmoothPlastic },
	Beard = { color = rgb(240, 240, 248), material = Enum.Material.SmoothPlastic },
	Wood = { color = rgb(92, 58, 36), material = Enum.Material.Wood },
	Book = { color = rgb(150, 30, 45), material = Enum.Material.Fabric },
	Page = { color = rgb(250, 244, 220), material = Enum.Material.SmoothPlastic },
}

-- Onde o feiticeiro está (o servidor confere a distância antes de deixar viajar).
function Wizard.position(): Vector3?
	return spot
end

local function text(parent: Instance, name: string, value: string, color: Color3, size: UDim2, position: UDim2)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = value
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Config.Palette.outline
	stroke.Parent = label
	label.Parent = parent
end

-- Chamado depois de Sanctum.build: precisa da pasta da casa no Workspace.
function Wizard.build(): boolean
	local sanctum = workspace:FindFirstChild("Sanctum")
	local model = if sanctum then Models.load("wizard", STYLE) else nil
	if not sanctum or not model then
		return false
	end
	local k = S.scale
	local size = k * W.height / MODEL_HEIGHT
	local origin = CFrame.new(S.center.X, Config.World.groundY, S.center.Y)
	local floor = (origin * CFrame.new(W.offset.X * k, S.floor * k, W.offset.Y * k)).Position
	local toCenter = Vector3.new(origin.Position.X - floor.X, 0, origin.Position.Z - floor.Z).Unit

	model:ScaleTo(model:GetScale() * size)
	model:PivotTo(CFrame.lookAt(floor + Vector3.new(0, W.hover * k, 0), floor + Vector3.new(0, W.hover * k, 0) + toCenter))
	model.Name = "Wizard"
	model:SetAttribute("Home", model:GetPivot()) -- o cliente balança o modelo em volta daqui
	model.Parent = sanctum

	-- corpo invisível: colisão, aviso de conversar, luz e a placa com o nome
	local body = Instance.new("Part")
	body.Name = "WizardBody"
	body.Anchored = true
	body.Transparency = 1
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(W.height * k, 4.6 * size, 4.6 * size)
	body.CFrame = CFrame.new(floor + Vector3.new(0, W.height * k / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	body.Parent = sanctum

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Wizard"
	prompt.ObjectText = W.name
	prompt.ActionText = "Talk"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = W.range * k
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	local glow = Instance.new("PointLight")
	glow.Color = STYLE.Crystal.color
	glow.Range = 24 * k
	glow.Brightness = 1.6
	glow.Shadows = false
	glow.Parent = body

	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromScale(8, 1.9)
	tag.StudsOffsetWorldSpace = Vector3.new(0, W.height * k / 2 + W.hover * k + 2.4, 0)
	tag.MaxDistance = 90
	text(tag, "Name", W.name, STYLE.Crystal.color, UDim2.fromScale(1, 0.58), UDim2.fromScale(0, 0))
	text(tag, "Title", "KEEPER OF WORLDS", rgb(255, 196, 60), UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6))
	tag.Parent = body

	spot = floor
	return true
end

return Wizard
