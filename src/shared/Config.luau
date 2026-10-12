--!strict
-- Todos os números ajustáveis do jogo. Mundo, servidor e cliente leem daqui.

local Config = {}

Config.GameName = "Wall Breaker Titans"
Config.DataVersion = 1
Config.DataStoreName = "Profile_v1"
Config.AutosaveSeconds = 60

Config.Rarities = {
	{ id = "Common", color = Color3.fromRGB(180, 180, 180) },
	{ id = "Uncommon", color = Color3.fromRGB(63, 196, 30) },
	{ id = "Rare", color = Color3.fromRGB(46, 123, 255) },
	{ id = "Epic", color = Color3.fromRGB(163, 53, 238) },
	{ id = "Legendary", color = Color3.fromRGB(255, 154, 30) },
	{ id = "Mythic", color = Color3.fromRGB(240, 20, 20) },
}

Config.Palette = {
	grassLight = Color3.fromRGB(140, 240, 42),
	grassDark = Color3.fromRGB(63, 196, 30),
	sand = Color3.fromRGB(232, 217, 168),
	yellowLine = Color3.fromRGB(255, 210, 30),
	wallOrange = Color3.fromRGB(217, 119, 43),
	wallBrown = Color3.fromRGB(122, 59, 22),
	navy = Color3.fromRGB(20, 26, 51),
	machineYellow = Color3.fromRGB(245, 179, 27),
	cyan = Color3.fromRGB(25, 227, 255),
	red = Color3.fromRGB(240, 20, 20),
	slab = Color3.fromRGB(142, 144, 181),
	outline = Color3.fromRGB(16, 18, 34),
	money = Color3.fromRGB(87, 255, 87),
	power = Color3.fromRGB(255, 196, 46),
	hitNumber = Color3.fromRGB(90, 190, 255),
}

-- Saco de pancada: poder por soco e custo para chegar ao nível.
Config.Bag = {
	hitCooldown = 0.2, -- o servidor recusa socos mais rápidos que isto
	hitRange = 13, -- distância máxima do jogador ao saco
	holdInterval = 0.25, -- cliente repete o soco enquanto o botão fica apertado
	levels = {
		{ power = 1, cost = 0 },
		{ power = 2, cost = 50 },
		{ power = 4, cost = 250 },
		{ power = 8, cost = 1_000 },
		{ power = 16, cost = 5_000 },
		{ power = 35, cost = 25_000 },
		{ power = 75, cost = 120_000 },
		{ power = 160, cost = 600_000 },
		{ power = 350, cost = 3_000_000 },
		{ power = 800, cost = 15_000_000 },
	},
}

-- Medidas do mundo, em studs. O chão do gramado fica em Y = groundY.
Config.World = {
	groundY = 0.25,
	lawnSize = Vector2.new(480, 300), -- X, Z
	tile = 20,
	plotCount = 6,
	plotSize = Vector2.new(60, 70), -- X, Z
	plotSpacing = 72,
	plotRowZ = 100, -- centro da fileira de terrenos; o portão do corredor fica em -Z
	perimeterHeight = 12,
}

-- Posições dentro do terreno, relativas ao centro dele (-Z aponta para o gramado).
Config.Plot = {
	bagOffset = Vector3.new(-18, 0, -24),
	spawnOffset = Vector3.new(-8, 3, -24),
	pedestals = {
		{ offset = Vector3.new(-13, 0, -2), locked = false },
		{ offset = Vector3.new(-23, 0, -2), locked = false },
		{ offset = Vector3.new(13, 0, -2), locked = false },
		{ offset = Vector3.new(23, 0, -2), locked = false },
		{ offset = Vector3.new(-13, 0, 18), locked = true },
		{ offset = Vector3.new(-23, 0, 18), locked = true },
		{ offset = Vector3.new(13, 0, 18), locked = true },
		{ offset = Vector3.new(23, 0, 18), locked = true },
	},
}

-- Corrida. Distâncias das paredes em "M" de exibição; metersPerStud converte para studs.
Config.Run = {
	zoneCenter = Vector3.new(0, 0, -125), -- centro da zona de carga; a corrida segue em -Z
	zoneSize = Vector2.new(40, 30),
	hallwayWidth = 40,
	metersPerStud = 4,
	speed = 130, -- studs por segundo
	chargeTime = 1.4, -- segundos para 100%
	minCharge = 0.15, -- soltar antes disso cancela
	endPadding = 60, -- studs de corredor depois da última parede
	returnDelay = 1.4, -- segundos entre o fim da corrida e a volta ao terreno
}

-- tier = índice em Config.Rarities. A corrida para na primeira parede que o jogador não quebra.
Config.Walls = {
	{ tier = 1, distance = 200, power = 15, luck = 1 },
	{ tier = 1, distance = 400, power = 60, luck = 1.2 },
	{ tier = 2, distance = 800, power = 150, luck = 1.5 },
	{ tier = 2, distance = 1200, power = 1_000, luck = 1.8 },
	{ tier = 3, distance = 1400, power = 2_000, luck = 2.2 },
	{ tier = 3, distance = 1800, power = 6_000, luck = 2.6 },
	{ tier = 4, distance = 2200, power = 15_000, luck = 3.2 },
	{ tier = 4, distance = 2400, power = 30_000, luck = 3.8 },
	{ tier = 5, distance = 2800, power = 80_000, luck = 4.5 },
	{ tier = 5, distance = 3200, power = 250_000, luck = 5.5 },
	{ tier = 6, distance = 3600, power = 800_000, luck = 7 },
	{ tier = 6, distance = 4000, power = 3_000_000, luck = 10 },
}

-- Sorteio: pesos em relação ao tier da última parede quebrada.
Config.Roll = {
	sameWeight = 60,
	lowerWeight = 30,
	higherWeight = 10, -- multiplicado pela sorte da parede, até higherCap
	higherCap = 50,
}

Config.Inventory = {
	hotbarSlots = 8,
	maxItems = 24,
	sellSeconds = 20, -- inventário cheio: o personagem vira dinheiro (renda x este valor)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- hat: none | band | cap | hood | spikes | horns | crown | halo
Config.Characters = {
	{ id = "rookie_jabber", name = "Rookie Jabber", rarity = 1, income = 1, body = rgb(235, 235, 235), pants = rgb(60, 90, 200), glove = rgb(220, 40, 40), hat = "none" },
	{ id = "rope_skipper", name = "Rope Skipper", rarity = 1, income = 2, body = rgb(255, 214, 70), pants = rgb(60, 60, 70), glove = rgb(240, 240, 240), hat = "band" },
	{ id = "bucket_boxer", name = "Bucket Boxer", rarity = 1, income = 4, body = rgb(130, 200, 255), pants = rgb(40, 60, 110), glove = rgb(255, 150, 40), hat = "cap" },
	{ id = "brick_bruiser", name = "Brick Bruiser", rarity = 2, income = 10, body = rgb(200, 80, 50), pants = rgb(70, 40, 30), glove = rgb(110, 60, 40), hat = "none" },
	{ id = "turbo_sparrer", name = "Turbo Sparrer", rarity = 2, income = 18, body = rgb(70, 220, 110), pants = rgb(20, 20, 30), glove = rgb(255, 235, 60), hat = "band" },
	{ id = "dojo_cadet", name = "Dojo Cadet", rarity = 2, income = 30, body = rgb(250, 250, 250), pants = rgb(250, 250, 250), glove = rgb(40, 150, 70), hat = "band" },
	{ id = "frost_hook", name = "Frost Hook", rarity = 3, income = 80, body = rgb(120, 200, 255), pants = rgb(235, 245, 255), glove = rgb(180, 240, 255), hat = "spikes" },
	{ id = "volt_kicker", name = "Volt Kicker", rarity = 3, income = 140, body = rgb(40, 60, 160), pants = rgb(20, 20, 40), glove = rgb(255, 240, 60), hat = "spikes" },
	{ id = "stone_guard", name = "Stone Guard", rarity = 3, income = 240, body = rgb(130, 130, 145), pants = rgb(80, 80, 95), glove = rgb(90, 160, 255), hat = "cap" },
	{ id = "shadow_sensei", name = "Shadow Sensei", rarity = 4, income = 700, body = rgb(40, 30, 60), pants = rgb(25, 20, 40), glove = rgb(190, 80, 255), hat = "hood" },
	{ id = "blaze_champion", name = "Blaze Champion", rarity = 4, income = 1_200, body = rgb(255, 110, 30), pants = rgb(120, 20, 20), glove = rgb(255, 220, 60), hat = "spikes" },
	{ id = "storm_monk", name = "Storm Monk", rarity = 4, income = 2_000, body = rgb(150, 90, 230), pants = rgb(245, 240, 255), glove = rgb(120, 240, 255), hat = "halo" },
	{ id = "golden_gladiator", name = "Golden Gladiator", rarity = 5, income = 6_000, body = rgb(255, 200, 40), pants = rgb(140, 30, 30), glove = rgb(255, 235, 140), hat = "crown" },
	{ id = "titan_wrestler", name = "Titan Wrestler", rarity = 5, income = 10_000, body = rgb(30, 160, 150), pants = rgb(255, 170, 40), glove = rgb(255, 120, 30), hat = "horns" },
	{ id = "comet_striker", name = "Comet Striker", rarity = 5, income = 18_000, body = rgb(255, 150, 60), pants = rgb(30, 30, 70), glove = rgb(120, 220, 255), hat = "halo" },
	{ id = "void_emperor", name = "Void Emperor", rarity = 6, income = 60_000, body = rgb(30, 10, 50), pants = rgb(15, 5, 25), glove = rgb(255, 40, 90), hat = "crown" },
	{ id = "solar_colossus", name = "Solar Colossus", rarity = 6, income = 120_000, body = rgb(255, 235, 120), pants = rgb(255, 120, 20), glove = rgb(255, 60, 30), hat = "horns" },
	{ id = "abyss_titan", name = "Abyss Titan", rarity = 6, income = 250_000, body = rgb(20, 40, 90), pants = rgb(10, 15, 40), glove = rgb(60, 255, 220), hat = "horns" },
}

-- Golpe crítico no saco: chance e multiplicador base; os atributos somam por nível.
Config.Crit = {
	baseChance = 0.08,
	baseMultiplier = 3,
}

-- Atributos compráveis com dinheiro. custo(nível atual) = baseCost * growth ^ nível.
Config.Stats = {
	speed = { label = "SPEED", unit = "walk speed", max = 20, baseCost = 100, growth = 1.55, perLevel = 1.5 },
	critChance = { label = "CRIT CHANCE", unit = "% chance", max = 20, baseCost = 250, growth = 1.6, perLevel = 0.02 },
	critDamage = { label = "CRIT DAMAGE", unit = "x power", max = 20, baseCost = 400, growth = 1.6, perLevel = 0.5 },
}
Config.StatOrder = { "speed", "critChance", "critDamage" }

function Config.statCost(name: string, level: number): number
	local stat = Config.Stats[name]
	return math.floor(stat.baseCost * stat.growth ^ level)
end

-- Movimento no lobby (só cliente): corrida, dash e pulo duplo.
Config.Move = {
	walk = 16,
	sprintBonus = 12,
	dashSpeed = 90,
	dashTime = 0.2,
	dashCooldown = 1.1,
	doubleJumpPower = 60,
}

Config.CharacterById = {}
for _, info in Config.Characters do
	Config.CharacterById[info.id] = info
end

return Config
