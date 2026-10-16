--!strict
-- Os modelos do golem para os clientes copiarem: o golem de cada mundo, pintado e na escala do
-- jogo, e as peças 3D dos efeitos (tools/blender/boss_fx.py). Ficam em
-- ReplicatedStorage.BossModels (Golem1, Golem2, Fx). Usado pelo Boss e pelo laboratório de
-- efeitos (lab.project.json).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(script.Parent.Models)

local GolemModels = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local M = Enum.Material
-- arcano (mundo 1): pedra azul-noite e fissuras de magia azul; magma (mundo 2): basalto e brasa
GolemModels.STYLES = {
	{
		Rock = { color = rgb(36, 38, 54), material = M.Slate },
		Plate = { color = rgb(62, 66, 90), material = M.Slate },
		Trim = { color = rgb(255, 196, 72), material = M.Metal },
		Magma = { color = rgb(80, 190, 255), material = M.Neon },
		Ember = { color = rgb(220, 245, 255), material = M.Neon },
	},
	{
		Rock = { color = rgb(38, 28, 28), material = M.Basalt },
		Plate = { color = rgb(66, 48, 46), material = M.Basalt },
		Trim = { color = rgb(255, 168, 56), material = M.Metal },
		Magma = { color = rgb(255, 84, 20), material = M.Neon },
		Ember = { color = rgb(255, 216, 96), material = M.Neon },
	},
} :: { { [string]: Models.Style } }

function GolemModels.load()
	if ReplicatedStorage:FindFirstChild("BossModels") then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "BossModels"
	holder.Parent = ReplicatedStorage
	local S = Config.Boss.scale
	for _, world in Config.Worlds do
		task.spawn(function()
			local model = Models.load("golem", GolemModels.STYLES[world.id] or GolemModels.STYLES[1])
			if not model then
				warn("[GolemModels] o modelo do golem não carregou")
				return
			end
			if S ~= 1 then
				model:ScaleTo(model:GetScale() * S)
			end
			model:PivotTo(CFrame.identity)
			model.Name = "Golem" .. world.id
			model.Parent = holder
		end)
	end
	-- peças 3D dos efeitos: o cliente copia, escala e anima
	task.spawn(function()
		local model = Models.load("boss_fx", {})
		if not model then
			warn("[GolemModels] as peças dos efeitos não carregaram")
			return
		end
		model.Name = "Fx"
		model.Parent = holder
	end)
end

return GolemModels
