--!strict
-- Carrega um modelo feito com tools/blender/kit.py (id em Shared.Assets) e devolve ele pronto
-- para pôr no lugar: pintado pelo nome de cada peça ("Rock_volcano_base"), sem colisão, na
-- escala certa e com o pivô na origem do modelo.
--
-- O kit exporta três cubinhos: Pivot (origem), MarkX (+X) e MarkY (frente), a 20 studs da
-- origem. Daqui saem a escala e a direção, sem depender de como a Roblox importou o arquivo.
-- Depois de carregado: +X do pivô = direita do modelo, -Z do pivô = frente, +Y = cima.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)

local MARK = 20

export type Style = { color: Color3, material: Enum.Material, transparency: number? }

local Models = {}

function Models.load(name: string, styles: { [string]: Style }): Model?
	local id = tonumber(string.match(Assets[name] or "", "%d+"))
	if not id then
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok then
		warn(`[Models] {name} não carregou ({container})`)
		return nil
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		container:Destroy()
		return nil
	end

	local marks: { [string]: Vector3 } = {}
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local kind = string.match(part.Name, "^(%a+)_") or ""
		if kind == "Pivot" or kind == "MarkX" or kind == "MarkY" then
			marks[kind] = part.Position
			part:Destroy()
			continue
		end
		local style = styles[kind]
		if style then
			part.Color = style.color
			part.Material = style.material
			part.Transparency = style.transparency or 0
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = style ~= nil and style.material ~= Enum.Material.Neon
	end

	local origin, markX, markY = marks.Pivot, marks.MarkX, marks.MarkY
	if not origin or not markX or not markY then
		warn(`[Models] {name} veio sem os marcadores`)
		container:Destroy()
		return nil
	end
	local right = (markX - origin).Unit
	local front = (markY - origin).Unit
	model.WorldPivot = CFrame.fromMatrix(origin, right, right:Cross(front), -front)
	model:ScaleTo(MARK / (markX - origin).Magnitude)
	model.Name = name
	model.Parent = nil
	container:Destroy()
	return model
end

return Models
