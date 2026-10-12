-- Corredor decorado: os trechos existem do portão ao fim, nada da decoração colide, e a pista
-- continua livre para a corrida (nenhuma peça que colide entre o chão e a altura do boneco).
--   node tools/bridge.cjs run server src/server/tests/hall.luau 60000

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local hallway = workspace:WaitForChild("Hallway", 10)
local decor = hallway and hallway:FindFirstChild("Decor")
assert(decor, "sem Hallway.Decor")

local run = Config.Run
local lawnEdge = -Config.World.lawnSize.Y / 2
local endZ = run.zoneCenter.Z - Config.Walls[#Config.Walls].distance / run.metersPerStud - run.endPadding
local firstWall = run.zoneCenter.Z - Config.Walls[1].distance / run.metersPerStud
local expected = math.floor((firstWall + Config.Hall.archLead - Config.Hall.spacing - endZ + 4) / Config.Hall.spacing)
local segments = {}
for _, child in decor:GetChildren() do
	if child.Name == "Segment" then
		table.insert(segments, child)
	end
end
assert(#segments >= expected - 1 and #segments >= 15, `{#segments} trechos, esperava perto de {expected}`)

local parts, colliding, lights, kinds = 0, 0, 0, {}
for _, instance in decor:GetDescendants() do
	if instance:IsA("BasePart") then
		parts += 1
		kinds[instance.Name] = (kinds[instance.Name] or 0) + 1
		if instance.CanCollide or not instance.Anchored then
			colliding += 1
		end
	elseif instance:IsA("PointLight") then
		lights += 1
	end
end
assert(colliding == 0, colliding .. " peças da decoração colidem")
assert(lights == #segments * 4, `{lights} luzes para {#segments} trechos`)
for _, kind in { "Stone", "Gold", "Trim", "Cloth", "Glass", "Glow", "Dark", "Gem" } do
	assert((kinds[kind] or 0) > 0, "nenhuma peça do tipo " .. kind)
end

-- nada da decoração atravessa uma parede quebrável nem a entrada (portão até a primeira parede)
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = segments
local inside = 0
for index, wall in Config.Walls do
	local z = run.zoneCenter.Z - wall.distance / run.metersPerStud
	-- a parede ocupa a largura do corredor; a caixa vai do chão até acima da placa dela
	local found = workspace:GetPartBoundsInBox(CFrame.new(0, Config.World.groundY + 12, z), Vector3.new(run.hallwayWidth - 1, 23, 5), overlap)
	inside += #found
	assert(#found == 0, `parede {index}: {#found} peças da decoração dentro dela (ex.: {found[1] and found[1].Name})`)
end
local entrance = workspace:GetPartBoundsInBox(CFrame.new(0, Config.World.groundY + 25, (lawnEdge + firstWall) / 2), Vector3.new(run.hallwayWidth + 8, 49, lawnEdge - firstWall), overlap)
assert(#entrance == 0, #entrance .. " peças da decoração na entrada")

-- pista livre: da largada ao fim, na altura do boneco, só as paredes quebráveis podem aparecer
local params = RaycastParams.new()
params.RespectCanCollide = true
local blocked = {}
for _, x in { -14, -7, 0, 7, 14 } do
	local hit = workspace:Raycast(Vector3.new(x, Config.World.groundY + 3, lawnEdge - 4), Vector3.new(0, 0, -(lawnEdge - 4 - endZ) + 10), params)
	if hit then
		local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
		local name = if model then model.Name else hit.Instance.Name
		if not string.find(name, "^Wall") and name ~= "Bricks" then
			blocked[name] = true
		end
	end
end
local names = {}
for name in blocked do
	table.insert(names, name)
end
assert(#names == 0, "a pista bate em: " .. table.concat(names, ", "))

-- muros laterais na altura nova
local side = workspace:Raycast(Vector3.new(0, Config.World.groundY + run.wallHeight - 2, lawnEdge - 100), Vector3.new(60, 0, 0), params)
assert(side ~= nil, "muro lateral não chega à altura do teto")

return `{#segments} trechos, {parts} peças, {lights} luzes, nada colide, nada atravessa as {#Config.Walls} paredes nem a entrada, pista livre`
