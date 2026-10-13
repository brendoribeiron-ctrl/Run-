-- Casa de feitiçaria do centro: o modelo carregou, as quatro portas estão livres, as paredes e
-- as torres seguram o jogador, dá para subir os degraus e o cenário não invade a área.
--   node tools/bridge.cjs run server src/server/tests/sanctum.luau 60000

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local S = Config.Sanctum
local G = Config.World.groundY
local k = S.scale

local house
for _ = 1, 100 do
	house = workspace:FindFirstChild("Sanctum")
	if house then
		break
	end
	task.wait(0.2)
end
assert(house, "a casa não foi montada (o modelo não carregou?)")
local model = house:FindFirstChild("Model")
assert(model, "sem o modelo")

local kinds, meshes = {}, 0
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") then
		meshes += 1
		kinds[string.match(part.Name, "^(%a+)_") or part.Name] = true
		assert(not part.CanCollide, part.Name .. " do modelo colide (a colisão é das peças simples)")
	end
end
for _, kind in { "Stone", "Dark", "Roof", "Gold", "Glass", "Glow", "Wood", "Floor" } do
	assert(kinds[kind], "falta a peça " .. kind)
end
local _, size = model:GetBoundingBox()
assert(math.abs(size.X - S.modelWidth * k) < 1.5 and math.abs(size.Z - S.modelWidth * k) < 1.5, `largura {size.X} x {size.Z}`)
assert(size.Y > 120 * k, "altura " .. size.Y)

local origin = CFrame.new(S.center.X, G, S.center.Y)
local params = RaycastParams.new()
params.RespectCanCollide = true
local function world(x: number, y: number, z: number): Vector3
	return (origin * CFrame.new(x * k, y * k, z * k)).Position
end

-- portas: da frente de cada uma até o outro lado da casa, na altura do peito, só o pedestal do
-- centro fica no caminho; um pouco para o lado da porta, a parede segura
local doors, walls = 0, 0
for i = 0, 3 do
	local turn = CFrame.Angles(0, i * math.pi / 2, 0)
	local outside = turn * Vector3.new(4, S.floor + 4, S.porch + 10)
	local inside = turn * Vector3.new(4, S.floor + 4, 8)
	local from, to = world(outside.X, outside.Y, outside.Z), world(inside.X, inside.Y, inside.Z)
	if not workspace:Raycast(from, to - from, params) then
		doors += 1
	end
	for _, s in { -1, 1 } do
		local a = turn * Vector3.new(s * 18, S.floor + 4, S.porch + 10)
		local b = turn * Vector3.new(s * 18, S.floor + 4, 8)
		local hit = workspace:Raycast(world(a.X, a.Y, a.Z), world(b.X, b.Y, b.Z) - world(a.X, a.Y, a.Z), params)
		if hit and hit.Instance.Name == "Wall" then
			walls += 1
		end
	end
end
assert(doors == 4, doors .. " de 4 portas livres")
assert(walls == 8, walls .. " de 8 trechos de parede seguram")

-- piso: chão do gramado fora, rampa nos degraus, plataforma e salão na altura do piso
local function floorAt(x: number, z: number): number
	local hit = workspace:Raycast(world(x, 12, z), Vector3.new(0, -30 * k, 0), params)
	return if hit then (hit.Position.Y - G) / k else -99
end
for i = 0, 3 do
	local turn = CFrame.Angles(0, i * math.pi / 2, 0)
	local low, mid, porch, hall = turn * Vector3.new(0, 0, S.porch + S.stairs - 0.5), turn * Vector3.new(0, 0, S.porch + S.stairs / 2), turn * Vector3.new(0, 0, S.porch - 2), turn * Vector3.new(0, 0, 20)
	local a, b, c, d = floorAt(low.X, low.Z), floorAt(mid.X, mid.Z), floorAt(porch.X, porch.Z), floorAt(hall.X, hall.Z)
	assert(a < 0.7 and a > -0.1, `porta {i}: pé da rampa em {a}`)
	assert(b > a + 0.4 and b < S.floor - 0.3, `porta {i}: meio da rampa em {b}`)
	assert(math.abs(c - S.floor) < 0.35 and math.abs(d - S.floor) < 0.35, `porta {i}: plataforma {c}, salão {d}`)
end

-- teto: a câmera não sai por cima
assert(workspace:Raycast(world(10, S.floor + 3, 10), Vector3.new(0, 60 * k, 0), params) ~= nil, "sem teto")

-- cenário fora da área da casa
local scenery = workspace:FindFirstChild("Scenery")
local inside = 0
if scenery then
	for _, item in scenery:GetChildren() do
		local p = item:GetPivot().Position
		if math.abs(p.X - S.center.X) < S.clear * k and math.abs(p.Z - S.center.Y) < S.clear * k and p.Y < G + 5 then
			inside += 1
		end
	end
end
assert(inside == 0, inside .. " peças do cenário dentro da área da casa")

-- balcão de poções dentro do salão, com o aviso que abre a loja
local shop = house:FindFirstChild("PotionShop")
assert(shop and shop:IsA("Model"), "sem o balcão de poções")
local shopAt = shop:GetPivot().Position
assert(math.abs(shopAt.X - S.center.X) < S.half * k and math.abs(shopAt.Z - S.center.Y) < S.half * k and math.abs(shopAt.Y - (G + S.floor * k)) < 0.6, "balcão fora do salão: " .. tostring(shopAt))
local _, shopSize = shop:GetBoundingBox()
assert(shopSize.Y > 8 * k and shopSize.Y < 13 * k, "altura do balcão " .. shopSize.Y)
assert(house.Colliders.ShopBody:FindFirstChild("PotionShop"), "sem o aviso da loja")

local lights = 0
for _, item in house:GetDescendants() do
	if item:IsA("PointLight") then
		lights += 1
	end
end
return `{meshes} peças do modelo, {#house.Colliders:GetChildren()} de colisão, {lights} luzes, 4 portas livres, paredes seguram, rampas e piso OK`
