-- Cenário: os modelos carregam, o mapa é montado, nada colide e nada fica nas áreas de jogo.
--   node tools/bridge.cjs run server src/server/tests/scenery.luau 90000

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)

local folder = workspace:WaitForChild("Scenery", 60)
assert(folder, "o cenário não apareceu em 60 s")

local expected = 0
for _ in Assets do
	expected += 1
end
assert(folder:GetAttribute("Models") == expected, `carregaram {folder:GetAttribute("Models")} de {expected} modelos`)

local W = Config.World
local counts, parts, colliding, inPlay = {}, 0, 0, 0
for _, model in folder:GetChildren() do
	counts[model.Name] = (counts[model.Name] or 0) + 1
	local position = model:GetPivot().Position
	-- zona de carga e frente do portão; e o miolo de cada terreno
	local zone = math.abs(position.X) < Config.Run.hallwayWidth / 2 and position.Z < Config.Run.zoneCenter.Z + Config.Run.zoneSize.Y / 2 and position.Z > -W.lawnSize.Y / 2
	local plots = math.abs(position.Z - W.plotRowZ) < W.plotSize.Y / 2 - 2 and math.abs(position.X) < W.lawnSize.X / 2 - 24
	if zone or plots then
		inPlay += 1
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			parts += 1
			if part.CanCollide or not part.Anchored then
				colliding += 1
			end
		end
	end
end
assert(#folder:GetChildren() > 300, "poucas peças no cenário: " .. #folder:GetChildren())
assert(colliding == 0, colliding .. " peças colidem ou estão soltas")
assert(inPlay == 0, inPlay .. " modelos dentro da zona de carga ou dos terrenos")
for name in Assets do
	assert((counts[name] or 0) > 0, "modelo nunca usado: " .. name)
end

local summary = {}
for name, count in counts do
	table.insert(summary, name .. "=" .. count)
end
table.sort(summary)
return `{#folder:GetChildren()} modelos, {parts} peças, nenhuma colide, nada nas áreas de jogo | ` .. table.concat(summary, " ")
