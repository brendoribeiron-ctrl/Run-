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
	boundsHeight = 400, -- altura das paredes invisíveis que fecham o gramado e o corredor
	outlandSize = 4096, -- lado do chão de grama que continua para fora dos muros (até o horizonte)
	fallY = -40, -- quem cair abaixo disto volta para o próprio terreno
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
	wallHeight = 50, -- altura dos muros laterais e do fim do corredor (o teto fica em cima)
	-- botão CORRER do HUD: teleporta para a zona de carga
	teleportCooldown = 3, -- segundos entre dois teleportes do mesmo jogador
	teleportOffset = Vector3.new(0, 4, 4), -- ponto de chegada, a partir de zoneCenter (de frente para o corredor)
}

-- Linhas de velocidade da corrida (2D, atrás do HUD): radiais, nascem perto do centro e
-- aceleram para as bordas. AJUSTE AQUI.
Config.SpeedLines = {
	count = 64, -- quantas linhas na tela
	length = 0.5, -- comprimento na borda, em fração da meia-diagonal da tela
	lengthAtBirth = 0.3, -- fração do comprimento (e da espessura) quando a linha nasce
	thickness = NumberRange.new(3, 11), -- espessura na borda, em pixels
	flowSpeed = 0.85, -- velocidade de fluxo: frações do caminho centro->borda por segundo
	acceleration = 1.5, -- quanto a linha acelera ao se afastar do centro (0 = constante)
	maxOpacity = 0.9, -- opacidade da linha mais forte (0-1)
	innerRadius = 0.2, -- raio do centro limpo, em fração da meia-diagonal
	center = Vector2.new(0.5, 0.44), -- ponto de fuga na tela (fração): o fim do corredor
	birthFade = 0.08, -- trecho do caminho em que a linha recém-nascida aparece aos poucos
	fadeIn = 0.25, -- segundos para aparecer no início da corrida
	fadeOut = 0.35, -- segundos para sumir no fim
	minIntensity = 0.65, -- intensidade na largada; chega a 1 na última parede
	wallPulse = 0.5, -- reforço de intensidade ao estourar uma parede
	pulseTime = 0.35, -- segundos que esse reforço dura
	whiteChance = 0.35, -- parte das linhas que fica branca em vez da cor do tier
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

-- Super soco: cada soco no saco tem uma chance pequena (menor que a do crítico) de abrir um
-- minigame de apertar a tecla mostrada quando o marcador passa pela zona verde. Acertou tudo: soco gigante. Errou: o
-- boneco é jogado para longe. AJUSTE AQUI.
Config.Super = {
	chance = 0.025, -- chance de um soco virar super soco (o crítico começa em 8%)
	keys = { "Z", "X", "C", "V" }, -- teclas sorteadas (no toque, o próprio quadro da tecla é o botão)
	steps = 3, -- teclas por minigame
	stepTime = 2.0, -- segundos que o marcador leva para cruzar a barra na 1ª tecla
	speedUp = 0.9, -- cada tecla seguinte leva este tanto do tempo da anterior
	zoneWidth = 0.26, -- largura da zona verde, em fração da barra
	tolerance = 0.04, -- folga invisível antes e depois da zona verde (ajuda quem joga com atraso)
	stepPause = 0.35, -- respiro, em segundos, entre uma tecla certa e o marcador da próxima
	zoneRange = NumberRange.new(0.4, 0.66), -- onde a zona verde pode começar
	multiplier = 80, -- ganho do super soco = poder do saco x isto
	ejectSpeed = 60, -- erro: velocidade horizontal com que o boneco é jogado (studs/s)
	ejectUp = 45, -- erro: velocidade para cima
	stunTime = 1.2, -- erro: segundos caído antes de levantar
	windTime = 0.55, -- acerto: segundos juntando energia antes do soco
	holdTime = 0.5, -- acerto: segundos com o braço esticado depois do impacto
	cameraLinger = 0.45, -- acerto: segundos que a câmera de cinema ainda fica depois do golpe
	latency = 0.3, -- servidor: folga de rede ao conferir se deu tempo de acertar
	grace = 3, -- servidor: segundos além do fim da barra antes de desistir do cliente
}

-- Decoração do corredor (src/server/Hall.luau), estilo salão gótico azul e dourado. Um trecho
-- se repete a cada `spacing` studs. AJUSTE AQUI.
Config.Hall = {
	spacing = 40, -- comprimento de cada trecho (um par de pilares e um arco por trecho)
	firstOffset = 12, -- distância do portão até o primeiro arco
	pillarOffset = 17.5, -- distância dos pilares ao centro do corredor
	pillarHeight = 26,
	archRise = 20, -- quanto o arco sobe acima do topo dos pilares
	archSteps = 8, -- trechos retos em cada metade do arco
	bannerOffset = 9, -- distância dos estandartes ao centro
	bannerLength = 11,
	bannerWidth = 3.4,
	windowWidth = 4.6,
	windowHeight = 12,
	windowSill = 12, -- altura do peitoril das janelas
	inlayWidth = 0.55, -- largura das linhas douradas do piso
	lanternRange = 44,
	lanternBrightness = 2.6,
	windowRange = 30, -- luz azul que cada janela joga para dentro
	windowBrightness = 1.6,
}

-- Cenário decorativo (src/server/Scenery.luau): quantos de cada coisa. A mesma semente dá
-- sempre o mesmo mapa. AJUSTE AQUI.
Config.Scenery = {
	seed = 7,
	hills = 34, -- colinas grandes atrás dos muros
	farHills = 40, -- colinas enormes ao longe, fechando o horizonte
	hallwayStep = 24, -- distância entre as árvores que acompanham o corredor dos dois lados
	giantTrees = 70, -- árvores e pinheiros gigantes no fundo
	giantMushrooms = 22, -- cogumelos gigantes no fundo
	giantCrystals = 10, -- cristais gigantes no fundo
	groves = 46, -- canteiros (árvore + pedras, arbustos, flores) nas bordas do gramado
	tufts = 150, -- tufos de grama soltos pelo gramado
	flowers = 60, -- canteirinhos de flores soltos pelo gramado
}

-- Painel 3D das janelas (estilo "painel do sistema"): flutua na frente do boneco, com a câmera
-- atrás do ombro. Posições em studs, relativas ao boneco (X = direita, Y = cima, -Z = frente).
-- AJUSTE AQUI.
Config.Panel = {
	size = Vector2.new(6.6, 5.1), -- largura e altura do painel no mundo
	canvas = Vector2.new(800, 620), -- resolução do painel, em pixels (mesma proporção de size)
	margin = 70, -- pixels livres em volta da janela, para o halo e as cantoneiras
	brightness = 1.5, -- brilho da interface (com o Bloom, é o que faz a borda brilhar)
	lightBrightness = 0.7, -- luz azulada que o painel joga no boneco
	offset = Vector3.new(3.4, 2.7, -2.6), -- centro do painel
	facing = Vector3.new(0.4, 2.6, 3.4), -- ponto para onde o painel fica virado
	cameraOffset = Vector3.new(-0.9, 2.9, 2.8), -- câmera: atrás e acima do ombro esquerdo
	lookAt = Vector3.new(3.0, 2.4, -2.6), -- ponto que a câmera olha
	fieldOfView = 58,
	openTime = 0.38, -- segundos para abrir (e para fechar)
	openTwist = 55, -- graus que o painel nasce virado de lado
	maxTilt = 7, -- inclinação máxima seguindo o cursor, em graus
	tiltSpeed = 9, -- quão rápido a inclinação segue o cursor
	leash = 7, -- o painel fecha se o boneco se afastar mais que isto de onde abriu
	armIdle = 3, -- segundos com o cursor parado até o braço descer
	armDrop = 0.5, -- o braço aponta este tanto abaixo do cursor, para a mão não cobrir o clique
}

-- Automáticos: cada um é liberado por Game Pass (passId, 0 = ainda sem passe criado) ou
-- comprado uma vez com dinheiro do jogo. Depois de liberado, liga e desliga no botão do HUD.
Config.Auto = {
	punch = { label = "AUTO CLICK", info = "Punches the bag for you while you stand next to it.", price = 25_000, passId = 0 },
	super = { label = "AUTO SUPER", info = "Lands every Super Punch for you. No minigame, no miss.", price = 250_000, passId = 0 },
}
Config.AutoOrder = { "punch", "super" }

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
	-- parafuso do dash no chão (voo deitado girando no próprio eixo). AJUSTE AQUI.
	dashRollTurns = 1, -- voltas completas
	dashRollTime = 0.3, -- segundos do giro; a pose deitada dura até ele acabar
	-- "flat" = gira deitado como hélice (eixo vertical); "barrel" = parafuso em torno do próprio corpo
	dashRollStyle = "barrel",
	doubleJumpPower = 60,
	-- Animação de caminhada própria (ex.: "rbxassetid://123456"). Vazio = braços levemente
	-- para trás por código, somados à caminhada padrão.
	walkAnimationId = "",
}

-- Vitrine da loja. Só layout por enquanto: nenhum produto está ligado.
Config.Shop = {
	{ id = "double_power", name = "2x POWER", icon = "👊" },
	{ id = "double_money", name = "2x MONEY", icon = "💰" },
	{ id = "lucky_roll", name = "LUCKY ROLL", icon = "🍀" },
	{ id = "auto_punch", name = "AUTO PUNCH", icon = "🤖" },
}

-- Só layout por enquanto: nenhuma recompensa é entregue.
Config.Daily = { days = 7 }
Config.Playtime = { minutes = { 5, 10, 15, 30, 45, 60 } }

-- Auras: cada uma libera ao atingir `power` de Poder e, equipada, multiplica todo ganho de
-- Poder (soco, crítico e super soco). Bônus pequeno de propósito. followTier = a cor acompanha
-- o tier do Poder em vez de usar `color`.
Config.Auras = {
	{ id = "ember", name = "EMBER", power = 0, multiplier = 1, color = rgb(255, 120, 20), followTier = true },
	{ id = "spark", name = "SPARK", power = 1_000, multiplier = 1.05, color = rgb(255, 230, 80), followTier = false },
	{ id = "frost", name = "FROST", power = 25_000, multiplier = 1.1, color = rgb(120, 220, 255), followTier = false },
	{ id = "venom", name = "VENOM", power = 250_000, multiplier = 1.15, color = rgb(120, 255, 90), followTier = false },
	{ id = "storm", name = "STORM", power = 2_000_000, multiplier = 1.2, color = rgb(170, 110, 255), followTier = false },
	{ id = "solar", name = "SOLAR", power = 20_000_000, multiplier = 1.3, color = rgb(255, 150, 40), followTier = false },
	{ id = "void", name = "VOID", power = 200_000_000, multiplier = 1.4, color = rgb(255, 60, 160), followTier = false },
}
Config.AuraById = {}
for _, info in Config.Auras do
	Config.AuraById[info.id] = info
end

Config.CharacterById = {}
for _, info in Config.Characters do
	Config.CharacterById[info.id] = info
end

return Config
