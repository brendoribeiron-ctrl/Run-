--!strict
-- Montarias (skate flutuante, tapete voador): carrega os modelos do Blender
-- (tools/blender/mounts.py, ids em Shared.Assets), pinta, acerta escala e orientação e deixa
-- prontos em ReplicatedStorage.Mounts. Quem mostra a montaria embaixo de cada boneco é o
-- cliente (src/client/Mount.luau): é só visual, a velocidade do jogador não muda.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)

local Mounts = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- O nome de cada peça começa pelo tipo ("Deck_hoverboard", "Cloth_carpet_3").
local STYLE: { [string]: { color: Color3, material: Enum.Material } } = {
	Deck = { color = rgb(40, 44, 70), material = Enum.Material.SmoothPlastic },
	Grip = { color = rgb(18, 18, 26), material = Enum.Material.Slate },
	Metal = { color = rgb(190, 196, 214), material = Enum.Material.Metal },
	Wheel = { color = rgb(28, 28, 36), material = Enum.Material.SmoothPlastic },
	Glow = { color = rgb(60, 230, 255), material = Enum.Material.Neon },
	Jet = { color = rgb(255, 150, 40), material = Enum.Material.Neon },
	Cloth = { color = rgb(150, 30, 60), material = Enum.Material.Fabric },
	Gold = { color = rgb(255, 196, 60), material = Enum.Material.Metal },
	Trim = { color = rgb(60, 60, 170), material = Enum.Material.Fabric },
	Gem = { color = rgb(80, 255, 220), material = Enum.Material.Neon },
}

local function prepare(info: any): Model?
	local id = tonumber(string.match(Assets[info.id] or "", "%d+"))
	if not id then
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok then
		warn(`[Mounts] {info.id}: não carregou ({container})`)
		return nil
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		container:Destroy()
		return nil
	end

	local pivot: Vector3? = nil
	local jets, jetCount = Vector3.zero, 0
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local kind = string.match(part.Name, "^(%a+)_") or ""
		if kind == "Pivot" then
			pivot = part.Position -- onde o boneco pisa
			part:Destroy()
			continue
		end
		if kind == "Jet" then
			jets += part.Position
			jetCount += 1
		end
		local style = STYLE[kind]
		if style then
			part.Color = style.color
			part.Material = style.material
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = style ~= nil and style.material ~= Enum.Material.Neon
		-- gomo do tapete: o número no fim do nome
		local segment = tonumber(string.match(part.Name, "_(%d+)$"))
		if segment then
			part:SetAttribute("Segment", segment)
		end
	end

	local center, size = model:GetBoundingBox()
	local at = pivot or center.Position
	-- o comprimento é o maior lado; a frente fica do lado oposto aos propulsores (peças Jet)
	local long = if size.X > size.Z then center.XVector else center.ZVector
	if jetCount > 0 and (jets / jetCount - at):Dot(long) > 0 then
		long = -long
	end
	model.WorldPivot = CFrame.lookAt(at, at + long) -- -Z do pivô = frente
	model:ScaleTo(info.length / math.max(size.X, size.Z))
	model.Name = info.id
	model.Parent = nil
	container:Destroy()
	return model
end

-- Devolve quantas montarias ficaram prontas.
function Mounts.build(): number
	local folder = Instance.new("Folder")
	folder.Name = "Mounts"
	local count = 0
	for _, info in Config.Mounts do
		local model = prepare(info)
		if model then
			model.Parent = folder
			count += 1
		end
	end
	folder:SetAttribute("Ready", true)
	folder.Parent = ReplicatedStorage
	return count
end

return Mounts
