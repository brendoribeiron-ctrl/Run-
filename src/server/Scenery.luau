--!strict
-- Cenário decorativo: espalha pelo mapa os modelos feitos no Blender (ids em Shared.Assets,
-- enviados por tools/upload_assets.cjs). Fundo de colinas, árvores e cogumelos gigantes atrás
-- dos muros, plantas em cima deles, canteiros nas bordas do gramado, postes no caminho e cerca
-- atrás dos terrenos. Tudo é só visual: nada colide. As quantidades ficam em Config.Scenery.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)

local W = Config.World
local G = W.groundY
local SCENERY = Config.Scenery

local Scenery = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- O nome de cada peça começa pelo tipo ("Leaf_tree_round"): o tipo decide cor e material.
local STYLE: { [string]: { color: Color3, material: Enum.Material } } = {
	Leaf = { color = rgb(64, 176, 52), material = Enum.Material.LeafyGrass },
	Pine = { color = rgb(30, 116, 66), material = Enum.Material.LeafyGrass },
	Moss = { color = rgb(70, 150, 50), material = Enum.Material.Grass },
	Grass = { color = rgb(92, 196, 54), material = Enum.Material.Grass },
	Blade = { color = rgb(84, 204, 60), material = Enum.Material.Grass },
	Trunk = { color = rgb(112, 72, 40), material = Enum.Material.Wood },
	Cut = { color = rgb(214, 176, 112), material = Enum.Material.Wood },
	Wood = { color = rgb(150, 102, 58), material = Enum.Material.WoodPlanks },
	Rock = { color = rgb(132, 136, 152), material = Enum.Material.Slate },
	Cap = { color = rgb(226, 48, 42), material = Enum.Material.SmoothPlastic },
	Stem = { color = rgb(242, 230, 204), material = Enum.Material.SmoothPlastic },
	Spot = { color = rgb(255, 255, 255), material = Enum.Material.SmoothPlastic },
	Petal = { color = rgb(255, 120, 190), material = Enum.Material.SmoothPlastic },
	Core = { color = rgb(255, 214, 40), material = Enum.Material.SmoothPlastic },
	Berry = { color = rgb(240, 40, 70), material = Enum.Material.SmoothPlastic },
	Metal = { color = rgb(40, 42, 58), material = Enum.Material.Metal },
	Glow = { color = rgb(255, 226, 130), material = Enum.Material.Neon },
}

-- Variações de cor sorteadas por instância.
local CAPS = { rgb(226, 48, 42), rgb(170, 80, 240), rgb(40, 200, 230), rgb(255, 150, 40) }
local PETALS = { rgb(255, 120, 190), rgb(255, 230, 90), rgb(255, 255, 255), rgb(170, 130, 255), rgb(255, 110, 70) }
local CRYSTALS = { rgb(90, 230, 255), rgb(190, 110, 255), rgb(255, 110, 200), rgb(120, 255, 170) }

local templates: { [string]: Model } = {}
-- colinas já colocadas: centro, raio e altura, para o resto do fundo ficar apoiado nelas
local hills: { { x: number, z: number, radius: number, height: number } } = {}
local folder: Folder
local rng = Random.new(SCENERY.seed)

local function kindOf(part: Instance): string
	return string.match(part.Name, "^(%a+)_") or ""
end

-- Carrega um modelo da Roblox e o deixa pronto para clonar: pintado, ancorado, sem colisão,
-- com o pivô no centro da base.
local function loadTemplate(name: string, asset: string): Model?
	local id = tonumber(string.match(asset, "%d+"))
	if not id then
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok then
		warn(`[Scenery] {name}: não carregou ({container})`)
		return nil
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		container:Destroy()
		return nil
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local style = STYLE[kindOf(part)]
			if style then
				part.Color = style.color
				part.Material = style.material
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = style ~= nil and style.material ~= Enum.Material.Neon
		end
	end
	local center, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(center.Position - Vector3.new(0, size.Y / 2, 0))
	model.Name = name
	model.Parent = nil
	container:Destroy()
	return model
end

local function paint(model: Model, kind: string, color: Color3)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and kindOf(part) == kind then
			part.Color = color
		end
	end
end

-- Põe uma cópia com a base em (x, y, z), girada e na escala pedida.
local function place(name: string, x: number, y: number, z: number, scale: number, yaw: number?): Model?
	local template = templates[name]
	if not template then
		return nil
	end
	local model = template:Clone()
	model:ScaleTo(scale)
	model:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw or rng:NextNumber(0, math.pi * 2), 0))
	if name == "mushroom_big" or name == "mushroom_cluster" then
		paint(model, "Cap", CAPS[rng:NextInteger(1, #CAPS)])
	elseif name == "flowers" then
		paint(model, "Petal", PETALS[rng:NextInteger(1, #PETALS)])
	elseif name == "crystal" then
		local color = CRYSTALS[rng:NextInteger(1, #CRYSTALS)]
		paint(model, "Glow", color)
		local glow = model:FindFirstChild("Glow_crystal")
		if glow then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 6 * scale
			light.Brightness = 1.2
			light.Parent = glow
		end
	elseif name == "lamp" then
		local glow = model:FindFirstChild("Glow_lamp")
		if glow then
			local light = Instance.new("PointLight")
			light.Color = rgb(255, 226, 150)
			light.Range = 26
			light.Brightness = 1.4
			light.Parent = glow
		end
	elseif name == "tree_round" then
		-- cada árvore num verde um pouco diferente
		paint(model, "Leaf", rgb(64, 176, 52):Lerp(rgb(150, 210, 60), rng:NextNumber(0, 0.5)))
	end
	model.Parent = folder
	return model
end

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- Altura do chão de fora num ponto: o chão de grama ou a colina mais alta que passa por ali.
local function groundAt(x: number, z: number): number
	local ground = G - 0.6
	for _, hill in hills do
		local distance = math.sqrt((x - hill.x) ^ 2 + (z - hill.z) ^ 2) / hill.radius
		if distance < 1 then
			ground = math.max(ground, G - 3 + hill.height * math.sqrt(1 - distance * distance) * 0.92)
		end
	end
	return ground
end

local function addHill(x: number, z: number, scale: number)
	if place("hill", x, G - 3, z, scale) then
		-- medidas do modelo: 6 de raio e 3,2 de altura por unidade de escala
		table.insert(hills, { x = x, z = z, radius = 6 * scale, height = 3.2 * scale })
	end
end

---------------------------------------------------------------------------------------------------
-- Áreas

local halfX, halfZ = W.lawnSize.X / 2, W.lawnSize.Y / 2
local gate = Config.Run.hallwayWidth / 2 + 8 -- meia largura livre na frente do portão do corredor

-- Dentro do gramado, onde o jogo acontece e nada pode ficar no caminho.
local function busy(x: number, z: number): boolean
	local plots = z > W.plotRowZ - W.plotSize.Y / 2 - 20 and math.abs(x) < halfX - 22 and z < W.plotRowZ + W.plotSize.Y / 2 + 2
	local run = math.abs(x) < gate + 14 and z < Config.Run.zoneCenter.Z + Config.Run.zoneSize.Y / 2 + 16
	return plots or run
end

-- Fundo: colinas grandes em três lados e meio, com árvores, pinheiros e cogumelos gigantes em cima.
local function backdrop()
	local function ring(count: number, near: number, far: number, each: (x: number, z: number) -> ())
		for _ = 1, count do
			local side = rng:NextInteger(1, 4)
			local out = rng:NextNumber(near, far)
			local x, z
			if side == 1 then
				x, z = rng:NextNumber(-halfX - far, halfX + far), halfZ + out
			elseif side == 2 then
				x, z = rng:NextNumber(-halfX - far, halfX + far), -halfZ - out
			elseif side == 3 then
				x, z = halfX + out, rng:NextNumber(-halfZ - far, halfZ + far)
			else
				x, z = -halfX - out, rng:NextNumber(-halfZ - far, halfZ + far)
			end
			-- o corredor sai pelo lado -Z: nada em cima dele
			if not (z < -halfZ and math.abs(x) < gate + 30) then
				each(x, z)
			end
		end
	end
	ring(SCENERY.hills, 30, 120, function(x, z)
		addHill(x, z, rng:NextNumber(5.5, 10))
	end)
	-- colinas enormes ao longe: o horizonte vira morro em vez de céu
	ring(SCENERY.farHills, 170, 420, function(x, z)
		addHill(x, z, rng:NextNumber(12, 22))
	end)
	ring(SCENERY.giantTrees, 14, 110, function(x, z)
		place(pick({ "tree_round", "tree_round", "tree_pine" }), x, groundAt(x, z) - 1.5, z, rng:NextNumber(5, 9))
	end)
	ring(SCENERY.giantMushrooms, 12, 90, function(x, z)
		place("mushroom_big", x, groundAt(x, z) - 1.5, z, rng:NextNumber(5, 10))
	end)
	ring(SCENERY.giantCrystals, 16, 70, function(x, z)
		place("crystal", x, groundAt(x, z) - 1, z, rng:NextNumber(5, 9))
	end)
end

-- Em cima dos muros: arbustos, flores e tufos ao longo de toda a volta.
-- Ao longo do corredor, dos dois lados: árvores e cogumelos altos por cima dos muros dele.
local function hallwaySides()
	local endZ = Config.Run.zoneCenter.Z - Config.Walls[#Config.Walls].distance / Config.Run.metersPerStud - Config.Run.endPadding
	local z = -halfZ - 30
	while z > endZ - 60 do
		for _, side in { -1, 1 } do
			if rng:NextNumber() < 0.35 then
				addHill(side * (gate + rng:NextNumber(70, 140)), z, rng:NextNumber(7, 12))
			end
			local x = side * (gate + rng:NextNumber(14, 44))
			local name = pick({ "tree_round", "tree_pine", "tree_pine", "mushroom_big" })
			place(name, x, groundAt(x, z) - 1.5, z + rng:NextNumber(-8, 8), rng:NextNumber(6, 10))
		end
		z -= SCENERY.hallwayStep
	end
end

local function wallTops()
	local top = G + W.perimeterHeight + 1.2
	local function run(length: number, at: (offset: number) -> (number, number), skip: number?)
		local offset = -length / 2 + 4
		while offset < length / 2 - 4 do
			if not skip or math.abs(offset) > skip then
				local x, z = at(offset)
				local roll = rng:NextNumber()
				if roll < 0.4 then
					place("bush", x, top, z, rng:NextNumber(1.6, 2.6))
				elseif roll < 0.65 then
					place("flowers", x, top, z, rng:NextNumber(1.8, 2.6))
				elseif roll < 0.8 then
					place("mushroom_cluster", x, top, z, rng:NextNumber(1.6, 2.4))
				else
					place("grass_tuft", x, top, z, rng:NextNumber(2.2, 3.4))
				end
			end
			offset += rng:NextNumber(7, 13)
		end
	end
	run(W.lawnSize.X, function(offset)
		return offset, halfZ + 3 + rng:NextNumber(-2, 2)
	end)
	run(W.lawnSize.X, function(offset)
		return offset, -halfZ - 3 + rng:NextNumber(-2, 2)
	end, gate)
	run(W.lawnSize.Y, function(offset)
		return halfX + 3 + rng:NextNumber(-2, 2), offset
	end)
	run(W.lawnSize.Y, function(offset)
		return -halfX - 3 + rng:NextNumber(-2, 2), offset
	end)
end

-- Bordas do gramado: canteiros com uma árvore, pedras, arbustos, cogumelos e flores em volta.
local function borders()
	local placed = 0
	local tries = 0
	while placed < SCENERY.groves and tries < SCENERY.groves * 20 do
		tries += 1
		local inset = rng:NextNumber(9, 26)
		local x, z
		if rng:NextNumber() < 0.5 then
			x, z = (if rng:NextNumber() < 0.5 then -1 else 1) * (halfX - inset), rng:NextNumber(-halfZ + 8, halfZ - 8)
		else
			x, z = rng:NextNumber(-halfX + 8, halfX - 8), (if rng:NextNumber() < 0.5 then -1 else 1) * (halfZ - inset)
		end
		if busy(x, z) then
			continue
		end
		placed += 1
		place(pick({ "tree_round", "tree_round", "tree_pine", "mushroom_big" }), x, G, z, rng:NextNumber(2.2, 3.6))
		for _ = 1, rng:NextInteger(3, 6) do
			local angle = rng:NextNumber(0, math.pi * 2)
			local reach = rng:NextNumber(4, 11)
			local px, pz = x + math.cos(angle) * reach, z + math.sin(angle) * reach
			if math.abs(px) < halfX - 3 and math.abs(pz) < halfZ - 3 and not busy(px, pz) then
				local name = pick({ "rock_a", "rock_b", "bush", "bush", "mushroom_cluster", "flowers", "flowers", "stump", "crystal" })
				place(name, px, G, pz, if name == "crystal" then rng:NextNumber(0.9, 1.5) else rng:NextNumber(1.3, 2.4))
			end
		end
	end
end

-- Gramado inteiro: tufos e flores soltos, fora das áreas de jogo.
local function meadow()
	local function sprinkle(name: string, count: number, low: number, high: number)
		for _ = 1, count do
			local x, z = rng:NextNumber(-halfX + 6, halfX - 6), rng:NextNumber(-halfZ + 6, halfZ - 6)
			if not busy(x, z) then
				place(name, x, G, z, rng:NextNumber(low, high))
			end
		end
	end
	sprinkle("grass_tuft", SCENERY.tufts, 1.6, 2.8)
	sprinkle("flowers", SCENERY.flowers, 1.4, 2.2)
end

-- Postes ao longo do caminho de areia e cerca atrás dos terrenos; cristais guardando o portão.
local function structures()
	local pathZ = W.plotRowZ - W.plotSize.Y / 2 - 9
	local first = -(W.plotCount / 2) * W.plotSpacing
	for i = 0, W.plotCount do
		place("lamp", first + i * W.plotSpacing, G, pathZ - 9, 2.4, math.rad(-90))
	end
	local fenceZ = W.plotRowZ + W.plotSize.Y / 2 + 5
	local segment = 4 * 2.2
	local x = -halfX + 14
	while x < halfX - 14 do
		place("fence", x, G, fenceZ, 2.2, 0)
		x += segment
	end
	for _, side in { -1, 1 } do
		place("crystal", side * (gate + 4), G, -halfZ + 7, 3.2)
		place("rock_b", side * (gate + 11), G, -halfZ + 9, 2.6)
		place("mushroom_big", side * (gate + 20), G, -halfZ + 12, 2.8)
	end
end

-- Carrega os modelos (uma chamada à Roblox por modelo) e monta o cenário. Devolve quantas
-- cópias foram colocadas. Sem ids em Shared.Assets, não faz nada.
function Scenery.build(): number
	folder = Instance.new("Folder")
	folder.Name = "Scenery"
	local loaded = 0
	for name, asset in Assets do
		local template = loadTemplate(name, asset)
		if template then
			templates[name] = template
			loaded += 1
		end
	end
	if loaded == 0 then
		return 0
	end
	backdrop()
	hallwaySides()
	wallTops()
	borders()
	meadow()
	structures()
	folder.Parent = workspace
	folder:SetAttribute("Models", loaded)
	return #folder:GetChildren()
end

return Scenery
