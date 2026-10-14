--!strict
-- Todos os números ajustáveis do jogo. Mundo, servidor e cliente leem daqui.

local Config = {}

Config.GameName = "Wall Breaker Titans"
Config.DataVersion = 1
Config.DataStoreName = "Profile_v1"
Config.AutosaveSeconds = 60

-- Administradores: quem pode usar os comandos de chat de admin (/giveall, /give, /reset) no jogo
-- publicado.
-- O dono do jogo já é admin sem estar na lista (em jogo de grupo, o dono do grupo). No Studio,
-- todo mundo é admin. Para dar admin a alguém, ponha o UserId dele aqui (o número que aparece
-- no endereço do perfil: roblox.com/users/<UserId>/profile).
Config.Admins = {
	1033322591, -- br3ndo256
	10098933976, -- jogorui
}
-- Em jogo de grupo, quem tem este cargo (rank) ou maior também é admin. 255 = só o dono.
Config.AdminGroupRank = 255

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
	-- Números pequenos de propósito: o jogador sai do mundo 1 com cerca de 50K de Poder.
	-- Mundo 1 (níveis 1 a 15): de 1 a 20 de Poder por soco, preços de dezenas a dezenas de
	-- milhares. Do 16 em diante só se paga com a renda dos personagens de magma (mundo 2).
	levels = {
		{ power = 1, cost = 0 },
		{ power = 2, cost = 25 },
		{ power = 3, cost = 60 },
		{ power = 4, cost = 130 },
		{ power = 5, cost = 260 },
		{ power = 6, cost = 500 },
		{ power = 7, cost = 900 },
		{ power = 8, cost = 1_600 },
		{ power = 9, cost = 2_800 },
		{ power = 10, cost = 4_500 },
		{ power = 12, cost = 7_500 },
		{ power = 14, cost = 12_000 },
		{ power = 16, cost = 20_000 },
		{ power = 18, cost = 35_000 },
		{ power = 20, cost = 60_000 },
		-- mundo 2
		{ power = 25, cost = 90_000 },
		{ power = 30, cost = 140_000 },
		{ power = 36, cost = 220_000 },
		{ power = 44, cost = 340_000 },
		{ power = 54, cost = 520_000 },
		{ power = 66, cost = 800_000 },
		{ power = 80, cost = 1_200_000 },
		{ power = 100, cost = 1_800_000 },
		{ power = 120, cost = 2_700_000 },
		{ power = 150, cost = 4_000_000 },
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
	collectOffset = Vector3.new(18, 0, -22), -- botão único que recolhe o dinheiro de todos os pedestais
	pedestalDiameter = 7.2,
	freePedestals = 1, -- quantos já vêm liberados (os primeiros da lista)
	pedestalHeight = 1.4, -- altura do topo do pedestal acima da laje
	-- cost = preço para liberar (0 = já vem liberado). Liberam em ordem. Só o primeiro é de graça;
	-- até o 6º dá para pagar com a renda do mundo 1, do 7º em diante só com a dos personagens de
	-- magma, e o último fica para o fim do mundo 2.
	pedestals = {
		{ offset = Vector3.new(-13, 0, -4), cost = 0 },
		{ offset = Vector3.new(13, 0, -4), cost = 1_000 },
		{ offset = Vector3.new(-23, 0, -4), cost = 3_000 },
		{ offset = Vector3.new(23, 0, -4), cost = 8_000 },
		{ offset = Vector3.new(-13, 0, 10), cost = 20_000 },
		{ offset = Vector3.new(13, 0, 10), cost = 50_000 },
		{ offset = Vector3.new(-23, 0, 10), cost = 150_000 },
		{ offset = Vector3.new(23, 0, 10), cost = 500_000 },
		{ offset = Vector3.new(-18, 0, 24), cost = 1_500_000 },
		{ offset = Vector3.new(18, 0, 24), cost = 4_000_000 },
	},
}

-- Nível dos personagens: vale para todas as cópias do mesmo personagem e não se perde ao tirar
-- do pedestal. Sobe com dinheiro, no próprio pedestal. AJUSTE AQUI.
Config.Fighter = {
	maxLevel = 10,
	incomePerLevel = 0.25, -- cada nível soma este tanto da renda base (nível 10 = 3,25x), e no mínimo +1
	costSeconds = 60, -- o 1º upgrade custa a renda base x isto
	costGrowth = 1.4, -- cada upgrade seguinte custa este tanto do anterior
}

-- Renda no nível dado. Cada nível vale pelo menos +1: com rendas pequenas, +25% de 1 ou 2
-- sumiria no arredondamento e subir de nível não mudaria nada.
function Config.fighterIncome(id: string, level: number): number
	local base = Config.CharacterById[id].income
	return math.max(math.floor(base * (1 + Config.Fighter.incomePerLevel * (level - 1))), base + level - 1)
end

-- Quanto vale vender um personagem da mochila.
function Config.sellPrice(id: string, level: number): number
	return Config.fighterIncome(id, level) * Config.Inventory.sellSeconds
end

-- Custo para sair de `level` e ir ao próximo.
function Config.fighterCost(id: string, level: number): number
	return math.floor(Config.CharacterById[id].income * Config.Fighter.costSeconds * Config.Fighter.costGrowth ^ (level - 1))
end

-- Casa de feitiçaria no centro do gramado (src/server/Sanctum.luau; modelo em
-- tools/blender/sanctum.py). As medidas da colisão são as do modelo, em studs, antes da escala.
Config.Sanctum = {
	center = Vector2.new(0, -22), -- X, Z no gramado
	scale = 1,
	modelWidth = 84.4, -- largura do modelo (de degrau a degrau), para acertar a escala ao carregar
	clear = 52, -- meia largura da área em volta onde o cenário não coloca nada
	half = 30, -- meia largura do salão
	thick = 3, -- espessura das paredes
	floor = 2, -- altura do piso
	wall = 30, -- altura das paredes
	doorWidth = 14,
	doorHeight = 21, -- vão livre para a colisão (o arco sobe até 23)
	plinth = 34, -- meia largura do embasamento
	porch = 38, -- até onde vai a plataforma de cada porta
	porchWidth = 26,
	stairs = 4, -- comprimento dos degraus depois da plataforma
	towerRadius = 9.4,
	lightRange = 46,
	lightBrightness = 1.6,
	-- balcão de poções dentro do salão (modelo em tools/blender/potion_shop.py): abre o SHOP
	shopOffset = Vector2.new(-14, -14), -- X, Z a partir do centro da casa, em studs do modelo
	shopWidth = 11.7, -- largura do balcão, para acertar a escala ao carregar
	shopRange = 12, -- distância para o aviso de abrir a loja aparecer
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
	{ tier = 1, distance = 200, power = 40, luck = 1 },
	{ tier = 1, distance = 400, power = 80, luck = 1.2 },
	{ tier = 2, distance = 800, power = 150, luck = 1.5 },
	{ tier = 2, distance = 1200, power = 300, luck = 1.8 },
	{ tier = 3, distance = 1400, power = 550, luck = 2.2 },
	{ tier = 3, distance = 1800, power = 1_000, luck = 2.6 },
	{ tier = 4, distance = 2200, power = 2_000, luck = 3.2 },
	{ tier = 4, distance = 2400, power = 4_000, luck = 3.8 },
	{ tier = 5, distance = 2800, power = 7_500, luck = 4.5 },
	{ tier = 5, distance = 3200, power = 14_000, luck = 5.5 },
	{ tier = 6, distance = 3600, power = 27_000, luck = 7 },
	{ tier = 6, distance = 4000, power = 50_000, luck = 10 },
}

-- Paredes do mundo 2 (vulcão): mesmas distâncias. O jogador chega aqui logo depois do rebirth,
-- com o Poder zerado, então as primeiras ficam abaixo do fim do mundo 1 (dá para voltar a
-- quebrar parede cedo); da quarta em diante é Poder que o mundo 1 nunca pediu. A última pede
-- 500K: dez vezes o fim do mundo 1, e é o que o 2º rebirth cobra.
Config.VolcanoWalls = {
	{ tier = 1, distance = 200, power = 20_000, luck = 1 },
	{ tier = 1, distance = 400, power = 30_000, luck = 1.2 },
	{ tier = 2, distance = 800, power = 45_000, luck = 1.5 },
	{ tier = 2, distance = 1200, power = 65_000, luck = 1.8 },
	{ tier = 3, distance = 1400, power = 90_000, luck = 2.2 },
	{ tier = 3, distance = 1800, power = 125_000, luck = 2.6 },
	{ tier = 4, distance = 2200, power = 170_000, luck = 3.2 },
	{ tier = 4, distance = 2400, power = 225_000, luck = 3.8 },
	{ tier = 5, distance = 2800, power = 290_000, luck = 4.5 },
	{ tier = 5, distance = 3200, power = 360_000, luck = 5.5 },
	{ tier = 6, distance = 3600, power = 430_000, luck = 7 },
	{ tier = 6, distance = 4000, power = 500_000, luck = 10 },
}

-- Mundos. O 1 é o gramado. Os seguintes ficam longe, em `offset`, com a mesma planta: a zona de
-- carga, a pista e os terrenos ficam onde ficam os do mundo 1, somados ao offset. Cada jogador
-- tem o mesmo terreno em todos os mundos: os pedestais, o saco e a coleta de um são espelho dos
-- do outro (o que se coloca num aparece no outro), para ninguém precisar trocar de mundo.
--   rebirths = quantos rebirths o feiticeiro da casa de feitiçaria exige para deixar passar
--   suffix   = os personagens sorteados nesse mundo são a versão com este sufixo (ver o fim
--              deste arquivo); incomeMultiplier = quanto a renda deles vale a mais
--   hallway  = nome da pasta da pista no Workspace (o cliente procura as paredes nela)
--   plots    = nome da pasta dos terrenos desse mundo no Workspace
Config.Worlds = {
	{ id = 1, name = "MEADOW", rebirths = 0, offset = Vector3.zero, walls = Config.Walls, hallway = "Hallway", plots = "Plots", suffix = "", incomeMultiplier = 1, color = Color3.fromRGB(63, 196, 30) },
	{ id = 2, name = "VOLCANO", rebirths = 1, offset = Vector3.new(9000, 0, 0), walls = Config.VolcanoWalls, hallway = "VolcanoHallway", plots = "VolcanoPlots", suffix = "_magma", incomeMultiplier = 10, prefix = "Magma ", color = Color3.fromRGB(255, 110, 30) },
}

-- Mundo em que o jogador está agora (atributo "World", posto pelo servidor).
function Config.worldOf(player: Player): any
	local id = player:GetAttribute("World")
	return Config.Worlds[if type(id) == "number" then id else 1] or Config.Worlds[1]
end

function Config.zoneCenter(world: any): Vector3
	return Config.Run.zoneCenter + world.offset
end

-- O terreno do jogador no mundo em que ele está (nil enquanto não carregou).
function Config.plotOf(player: Player): Model?
	local folder = workspace:FindFirstChild(Config.worldOf(player).plots)
	local plot = folder and folder:FindFirstChild("Plot" .. tostring(player:GetAttribute("PlotId")))
	return if plot and plot:IsA("Model") then plot else nil
end

-- Vulcão (src/server/Volcano.luau; modelos em tools/blender/volcano.py). Posições relativas
-- ao offset do mundo, nos mesmos eixos do mundo 1 (a pista segue em -Z).
Config.Volcano = {
	islandCenter = Vector3.new(0, 0, -60), -- centro da ilha de chegada
	islandRadius = 85,
	arrive = Vector3.new(0, 4, -42), -- onde o jogador aparece, olhando para o portão
	gateZ = -150, -- o portão e o começo da pista
	segment = 50, -- comprimento de cada trecho da pista (igual ao passo das paredes)
	cliff = 24.5, -- distância do centro da pista ao pé dos paredões
	portal = Vector3.new(0, 0, 2), -- portal de volta, do outro lado da ilha
	terraceSize = Vector2.new(480, 120), -- o terraço dos terrenos (X, Z), centrado na fileira deles
	neck = 46, -- meia largura da passagem entre a ilha e o terraço (o portal fica no meio dela)
	portalRange = 16,
	lavaY = -7, -- nível do mar de lava
	seaSize = 4096,
	mount = Vector3.new(0, -12, 520), -- o vulcão do fundo, atrás da ilha
	mountScale = 1.5,
	spires = 46, -- agulhas de rocha espalhadas pelo mar de lava
	seed = 21,
}

-- O feiticeiro da casa de feitiçaria (src/server/Wizard.luau; modelo em tools/blender/wizard.py):
-- guarda a passagem para os outros mundos.
Config.Wizard = {
	name = "ARCHMAGE ORIN",
	offset = Vector2.new(14, 14), -- X, Z a partir do centro da casa
	height = 10.5, -- altura do modelo no jogo, em studs
	hover = 0.9, -- quanto ele flutua acima do piso
	range = 13, -- distância para o aviso de conversar aparecer
	travelRange = 40, -- o servidor só aceita a viagem com o jogador até esta distância dele
}

-- Modelos de Shared.Assets que não são cenário espalhado (cada um tem o próprio módulo).
Config.StructureAssets = { sanctum = true, potion_shop = true, wizard = true, volcano_terrace = true, volcano_base = true, volcano_track = true, volcano_mount = true, volcano_spire = true }

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
	sellSeconds = 20, -- preço de venda de um personagem = renda dele (no nível atual) x este valor;
	-- também é o que o jogador recebe quando ganha um personagem com a mochila cheia
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- hat: none | band | cap | hood | spikes | horns | crown | halo
Config.Characters = {
	{ id = "rookie_jabber", name = "Rookie Jabber", rarity = 1, income = 1, body = rgb(235, 235, 235), pants = rgb(60, 90, 200), glove = rgb(220, 40, 40), hat = "none" },
	{ id = "rope_skipper", name = "Rope Skipper", rarity = 1, income = 1, body = rgb(255, 214, 70), pants = rgb(60, 60, 70), glove = rgb(240, 240, 240), hat = "band" },
	{ id = "bucket_boxer", name = "Bucket Boxer", rarity = 1, income = 2, body = rgb(130, 200, 255), pants = rgb(40, 60, 110), glove = rgb(255, 150, 40), hat = "cap" },
	{ id = "brick_bruiser", name = "Brick Bruiser", rarity = 2, income = 2, body = rgb(200, 80, 50), pants = rgb(70, 40, 30), glove = rgb(110, 60, 40), hat = "none" },
	{ id = "turbo_sparrer", name = "Turbo Sparrer", rarity = 2, income = 3, body = rgb(70, 220, 110), pants = rgb(20, 20, 30), glove = rgb(255, 235, 60), hat = "band" },
	{ id = "dojo_cadet", name = "Dojo Cadet", rarity = 2, income = 4, body = rgb(250, 250, 250), pants = rgb(250, 250, 250), glove = rgb(40, 150, 70), hat = "band" },
	{ id = "frost_hook", name = "Frost Hook", rarity = 3, income = 6, body = rgb(120, 200, 255), pants = rgb(235, 245, 255), glove = rgb(180, 240, 255), hat = "spikes" },
	{ id = "volt_kicker", name = "Volt Kicker", rarity = 3, income = 8, body = rgb(40, 60, 160), pants = rgb(20, 20, 40), glove = rgb(255, 240, 60), hat = "spikes" },
	{ id = "stone_guard", name = "Stone Guard", rarity = 3, income = 10, body = rgb(130, 130, 145), pants = rgb(80, 80, 95), glove = rgb(90, 160, 255), hat = "cap" },
	{ id = "shadow_sensei", name = "Shadow Sensei", rarity = 4, income = 13, body = rgb(40, 30, 60), pants = rgb(25, 20, 40), glove = rgb(190, 80, 255), hat = "hood" },
	{ id = "blaze_champion", name = "Blaze Champion", rarity = 4, income = 16, body = rgb(255, 110, 30), pants = rgb(120, 20, 20), glove = rgb(255, 220, 60), hat = "spikes" },
	{ id = "storm_monk", name = "Storm Monk", rarity = 4, income = 20, body = rgb(150, 90, 230), pants = rgb(245, 240, 255), glove = rgb(120, 240, 255), hat = "halo" },
	{ id = "golden_gladiator", name = "Golden Gladiator", rarity = 5, income = 28, body = rgb(255, 200, 40), pants = rgb(140, 30, 30), glove = rgb(255, 235, 140), hat = "crown" },
	{ id = "titan_wrestler", name = "Titan Wrestler", rarity = 5, income = 36, body = rgb(30, 160, 150), pants = rgb(255, 170, 40), glove = rgb(255, 120, 30), hat = "horns" },
	{ id = "comet_striker", name = "Comet Striker", rarity = 5, income = 46, body = rgb(255, 150, 60), pants = rgb(30, 30, 70), glove = rgb(120, 220, 255), hat = "halo" },
	{ id = "void_emperor", name = "Void Emperor", rarity = 6, income = 60, body = rgb(30, 10, 50), pants = rgb(15, 5, 25), glove = rgb(255, 40, 90), hat = "crown" },
	{ id = "solar_colossus", name = "Solar Colossus", rarity = 6, income = 80, body = rgb(255, 235, 120), pants = rgb(255, 120, 20), glove = rgb(255, 60, 30), hat = "horns" },
	{ id = "abyss_titan", name = "Abyss Titan", rarity = 6, income = 110, body = rgb(20, 40, 90), pants = rgb(10, 15, 40), glove = rgb(60, 255, 220), hat = "horns" },
}

-- Super soco: cada soco no saco tem uma chance pequena (menor que a do crítico) de abrir um
-- minigame de apertar a tecla mostrada quando o marcador passa pela zona verde. Acertou tudo: soco gigante. Errou: o
-- boneco é jogado para longe. AJUSTE AQUI.
Config.Super = {
	chance = 0.015, -- chance de um soco virar super soco (o crítico começa em 4%)
	keys = { "Z", "X", "C", "V" }, -- teclas sorteadas (no toque, o próprio quadro da tecla é o botão)
	steps = 3, -- teclas por minigame
	stepTime = 2.0, -- segundos que o marcador leva para cruzar a barra na 1ª tecla
	speedUp = 0.9, -- cada tecla seguinte leva este tanto do tempo da anterior
	zoneWidth = 0.26, -- largura da zona verde, em fração da barra
	tolerance = 0.04, -- folga invisível antes e depois da zona verde (ajuda quem joga com atraso)
	stepPause = 0.35, -- respiro, em segundos, entre uma tecla certa e o marcador da próxima
	zoneRange = NumberRange.new(0.4, 0.66), -- onde a zona verde pode começar
	multiplier = 20, -- ganho do super soco = poder do saco x isto
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
	spacing = 50, -- comprimento de cada trecho; igual ao passo das paredes quebráveis, para nunca coincidirem
	archLead = 12.5, -- cada arco fica este tanto antes de onde pode haver uma parede quebrável
	contentOffset = 31, -- do arco até o centro do desenho do piso e das janelas do trecho
	inlayReach = 12, -- meia largura do desenho do piso
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
	-- fachada do portão
	pierWidth = 8, -- largura dos dois pilares grandes da fachada
	pierHeight = 64,
	signBase = 52, -- altura da base do letreiro (fica acima do arco da entrada)
	signHeight = 10,
	facadeLightRange = 40,
	facadeLightBrightness = 2.2,
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
	punch = { label = "AUTO CLICK", info = "Punches the bag for you while you stand next to it.", price = 3_000, passId = 0 },
	super = { label = "AUTO SUPER", info = "Lands every Super Punch for you. No minigame, no miss.", price = 25_000, passId = 0 },
}
Config.AutoOrder = { "punch", "super" }

-- Golpe crítico no saco: chance e multiplicador base; os atributos somam por nível.
Config.Crit = {
	baseChance = 0.04,
	baseMultiplier = 3,
}

-- Atributos compráveis com dinheiro. custo(nível atual) = baseCost * growth ^ nível.
-- No mundo 1 cada skill só vai até StatWorldCap do máximo; o resto libera com os rebirths que
-- abrem o mundo 2.
-- Cada nível é um nó da árvore de skills (src/client/Stats.luau, que desenha 10 nós por ramo).
Config.Stats = {
	speed = { label = "SPEED", unit = "walk speed", max = 10, baseCost = 150, growth = 2.2, perLevel = 3 },
	critChance = { label = "CRIT CHANCE", unit = "% chance", max = 10, baseCost = 400, growth = 2.2, perLevel = 0.016 },
	critDamage = { label = "CRIT DAMAGE", unit = "x power", max = 10, baseCost = 600, growth = 2.2, perLevel = 1 },
}
Config.StatWorldCap = 0.3 -- parte do máximo de cada skill que dá para comprar antes do mundo 2
Config.StatOrder = { "speed", "critChance", "critDamage" }

-- Até que nível a skill pode ir com estes rebirths.
function Config.statCap(name: string, rebirths: number): number
	local stat = Config.Stats[name]
	if rebirths >= Config.Worlds[2].rebirths then
		return stat.max
	end
	return math.ceil(stat.max * Config.StatWorldCap)
end

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

-- Rebirth: ao alcançar o Poder exigido, o jogador zera Poder, dinheiro e saco e ganha um
-- multiplicador permanente. Personagens, pedestais, níveis, skills e montarias ficam.
-- O 1º pede a última parede do mundo 1 e abre o vulcão; os seguintes seguem a lista de costs e,
-- acabada a lista, continuam no mesmo passo (100M, 200M, 500M, 1B...).
Config.Rebirth = {
	max = 25,
	powerPerRebirth = 0.5, -- cada rebirth soma este tanto ao ganho de Poder (2 rebirths = 2x)
	moneyPerRebirth = 0.25, -- e este tanto à renda dos pedestais
	rewardPerRebirth = 0.5, -- e às recompensas (diária, tempo de jogo, missões)
	costs = { 50_000, 250_000, 500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000 },
}

-- Poder exigido para o próximo rebirth de quem já fez `rebirths`.
function Config.rebirthCost(rebirths: number): number
	local costs = Config.Rebirth.costs
	local cost = costs[math.min(rebirths + 1, #costs)]
	-- depois da lista: x2, x2, x2,5 e repete (1, 2, 5, 10, 20, 50...)
	for step = 1, rebirths + 1 - #costs do
		cost *= if step % 3 == 0 then 2.5 else 2
	end
	return cost
end

-- Poções da loja (painel SHOP e balcão da casa de feitiçaria): bônus com tempo, comprado com
-- dinheiro do jogo. Comprar de novo soma tempo, até maxSeconds.
Config.Potions = {
	maxSeconds = 30 * 60,
	list = {
		{ id = "power", name = "POWER POTION", icon = "👊", info = "x2 Power", multiplier = 2, seconds = 300, price = 1_500, color = rgb(255, 196, 46) },
		{ id = "money", name = "MONEY POTION", icon = "💰", info = "x2 Money", multiplier = 2, seconds = 300, price = 1_500, color = rgb(87, 255, 87) },
		{ id = "luck", name = "LUCK POTION", icon = "🍀", info = "x2 Luck", multiplier = 2, seconds = 300, price = 2_500, color = rgb(120, 220, 255) },
	},
}
Config.PotionById = {}
for _, info in Config.Potions.list do
	Config.PotionById[info.id] = info
end

-- Recompensa diária: uma por dia, em sequência. Faltou um dia, recomeça do primeiro.
-- Painel SHOP do HUD: só o que se compra com Robux. passId 0 = passe ainda não criado. Os
-- automáticos usam o passId de Config.Auto. As poções ficam só no balcão da casa de feitiçaria.
Config.Shop = {
	{ id = "vip", name = "VIP", icon = "👑", info = "VIP perks", color = rgb(255, 200, 60), passId = 0 },
	{ id = "punch", name = "AUTO CLICK", icon = "👊", info = "Punches for you", color = rgb(90, 200, 255), auto = "punch" },
	{ id = "super", name = "AUTO SUPER", icon = "⚡", info = "Never miss a Super", color = rgb(255, 120, 220), auto = "super" },
}

Config.Daily = { days = 7, rewards = { 50, 100, 200, 400, 800, 1_500, 4_000 } }
-- Recompensas por tempo jogado na sessão (minutos e o dinheiro de cada uma).
Config.Playtime = { minutes = { 5, 10, 15, 30, 45, 60 }, rewards = { 30, 80, 150, 400, 800, 1_500 } }

-- Missões do dia: zeram à meia-noite (UTC). id também é o contador que o servidor soma.
Config.Quests = {
	{ id = "punch", text = "Land 400 punches", goal = 400, reward = 200 },
	{ id = "walls", text = "Break 15 walls", goal = 15, reward = 350 },
	{ id = "super", text = "Land 3 Super Punches", goal = 3, reward = 400 },
	{ id = "collect", text = "Collect $500 from pedestals", goal = 500, reward = 300 },
}
Config.QuestById = {}
for _, quest in Config.Quests do
	Config.QuestById[quest.id] = quest
end

-- Fusão: `count` personagens iguais viram um Shiny, com a renda multiplicada.
Config.Fusion = { count = 3, incomeMultiplier = 3, suffix = "_shiny" }

-- Amigos no mesmo servidor: cada um soma este tanto ao ganho de Poder, até o teto.
Config.Friends = { perFriend = 0.1, max = 0.5 }

-- Auras: o jogador começa sem nenhuma. A primeira chega sozinha ao atingir o Poder dela; as
-- outras liberam no painel AURAS. Equipada, multiplica todo ganho de Poder (soco, crítico e
-- super soco). Bônus pequeno de propósito. followTier = a cor acompanha o tier do Poder em vez
-- de usar `color`.
--
-- Desenho de cada uma (src/client/Aura.luau, texturas em src/shared/Textures.luau):
--   accent = cor clara (miolo das labaredas, bordas);  second = cor das labaredas de trás
--   flames = quanto fogo toon sobe do corpo (0 = quase nada, 1,4 = fogueira)
--   orbit  = o que gira em volta: "ribbon" (faixas largas de luz), "slash" (cortes pretos de
--            borda colorida), "thin" (fitas finas e rápidas);  rings = quantos anéis com o
--            Poder cheio;  spin = ritmo;  orbitColor = cor das fitas, se não for a da aura
--   ground = o que aparece no chão: "circle" (círculo mágico girando), "swirl" (vento em
--            espiral abrindo), "both", "none"
--   shards = lascas voando para fora
--   extra  = "none", "snow" (flocos caindo), "bubbles" (gotas subindo), "pillars" (pilares
--            de luz descendo do céu);  lightning = raios em volta do corpo
Config.Auras = {
	{ id = "ember", name = "EMBER", power = 300, multiplier = 1.03, color = rgb(255, 120, 20), followTier = true, flames = 0.75, orbit = "thin", rings = 1, spin = 0.85, ground = "none", shards = false, extra = "none" },
	{ id = "spark", name = "SPARK", power = 800, multiplier = 1.06, color = rgb(255, 196, 30), accent = rgb(255, 240, 160), second = rgb(255, 120, 20), followTier = false, flames = 0.3, orbit = "ribbon", rings = 3, spin = 1, ground = "circle", shards = false, extra = "none" },
	{ id = "frost", name = "FROST", power = 2_000, multiplier = 1.1, color = rgb(60, 140, 255), accent = rgb(215, 238, 255), second = rgb(140, 205, 255), followTier = false, flames = 1.25, orbit = "thin", rings = 2, spin = 0.7, ground = "circle", shards = true, extra = "snow" },
	{ id = "venom", name = "VENOM", power = 5_000, multiplier = 1.15, color = rgb(90, 235, 60), accent = rgb(215, 255, 150), second = rgb(150, 60, 220), followTier = false, flames = 0.95, orbit = "thin", rings = 3, spin = 1.25, ground = "swirl", shards = false, extra = "bubbles" },
	{ id = "storm", name = "STORM", power = 10_000, multiplier = 1.2, color = rgb(190, 150, 255), accent = rgb(255, 238, 252), second = rgb(255, 160, 225), followTier = false, flames = 0.3, orbit = "thin", rings = 2, spin = 1.4, ground = "swirl", shards = false, extra = "pillars", lightning = true },
	{ id = "solar", name = "SOLAR", power = 22_000, multiplier = 1.3, color = rgb(255, 160, 20), accent = rgb(255, 232, 110), second = rgb(255, 70, 170), followTier = false, flames = 1.4, orbit = "thin", orbitColor = rgb(255, 40, 30), rings = 3, spin = 1.15, ground = "circle", shards = true, extra = "none" },
	{ id = "void", name = "VOID", power = 40_000, multiplier = 1.4, color = rgb(245, 40, 170), accent = rgb(255, 160, 235), second = rgb(120, 40, 215), followTier = false, flames = 1.2, orbit = "slash", rings = 3, spin = 1, ground = "both", shards = true, extra = "none" },
}

-- Força do efeito da aura no boneco: nasce fraca e cresce com o Poder, até ficar inteira.
-- A escala é logarítmica: cada vez que o Poder multiplica, a aura dá o mesmo passo.
Config.AuraFx = {
	startPower = 300, -- Poder em que a aura tem a força mínima
	fullPower = 50_000, -- Poder em que ela chega à força total (a última parede do mundo 1)
	minStrength = 0.22, -- força com startPower (0 = nada, 1 = inteira)
	spin = 3.2, -- giro do que orbita, em radianos por segundo (x o spin da aura e o do estilo)
	boostSpin = 1.4, -- quanto a carga acelera o giro
	flameRate = 13, -- labaredas da frente por segundo, com a aura inteira e flames = 1
	circleSize = 11, -- diâmetro do círculo do chão com a aura inteira, em studs
	circleSpin = 16, -- giro do círculo, em graus por segundo
	windPeriod = 1.3, -- segundos que cada onda de vento leva para abrir e sumir
	-- voo: a aura escorre para o lado contrário ao movimento (parado = para cima)
	flightSpeed = 45, -- studs/s em que ela deita de vez para trás
	flightLift = 0.12, -- quanto ela ainda sobe mesmo deitada
	flightFollow = 9, -- quão rápido a direção acompanha a mudança de movimento (maior = mais seco)
	flightTailFollow = 3.5, -- o mesmo para a ponta do rastro: menor, e ela chicoteia nas curvas
	flightTail = 15, -- comprimento do rastro, em studs, com a aura inteira e deitada
	flightGap = 1.3, -- distância entre duas labaredas do rastro: menor = mais cheio (e mais partículas)
	flightScroll = 2.2, -- quantas vezes por segundo a textura do rastro corre da frente até a ponta
}

Config.AuraById = {}
for _, info in Config.Auras do
	Config.AuraById[info.id] = info
end

-- Montarias (painel MOUNTS): só visual, a velocidade do jogador não muda. Compra uma vez com
-- dinheiro e depois equipa quando quiser. length = comprimento no jogo, em studs;
-- lift = quanto o boneco sobe do chão em cima dela.
Config.Mounts = {
	{ id = "hoverboard", name = "HOVERBOARD", info = "Anti-gravity board", price = 2_500, length = 6.8, lift = 1.9, flip = true, color = rgb(60, 230, 255) },
	{ id = "carpet", name = "MAGIC CARPET", info = "Flying carpet", price = 20_000, length = 7.6, lift = 1.7, flip = false, color = rgb(255, 120, 150) },
}
Config.MountById = {}
for _, info in Config.Mounts do
	Config.MountById[info.id] = info
end

-- Movimento da montaria embaixo do boneco (src/client/Mount.luau). AJUSTE AQUI.
Config.Mount = {
	bob = 0.14, -- sobe e desce flutuando, em studs
	bobSpeed = 2.4,
	pitch = 5, -- graus que o bico abaixa na velocidade de caminhada
	roll = 2.5, -- balanço lateral, em graus
	wave = 0.2, -- altura da onda do tapete andando, em studs
	waveIdle = 0.07, -- e parado
	waveSpeed = 5,
	waveStep = 0.85, -- radianos de onda por stud de comprimento
	waveTilt = 0.8, -- quanto cada gomo inclina acompanhando a onda
	carve = 11, -- costura: graus que montaria e boneco inclinam de um lado para o outro andando
	carveSpeed = 2.6, -- ritmo da costura
	carveYaw = 7, -- graus que o bico vira acompanhando a costura
	turnLean = 14, -- graus de inclinação a mais nas curvas
	flipTime = 0.5, -- segundos do kickflip do skate no pulo
	airPitch = 16, -- graus que o bico levanta no ar
}

-- Câmera: até onde o jogador consegue afastar o zoom, em studs.
Config.Camera = {
	maxZoom = 32,
}

Config.CharacterById = {}
for _, info in Config.Characters do
	Config.CharacterById[info.id] = info
end
-- Versão de cada mundo seguinte (sorteada nas pistas dele): mesmo personagem, feito de rocha e
-- lava, com a renda multiplicada. Não entra no INDEX.
local LAVA, ASH = rgb(255, 110, 20), rgb(48, 30, 34)
local everyone = table.clone(Config.Characters)
for _, world in Config.Worlds do
	if world.suffix ~= "" then
		for _, info in Config.Characters do
			local variant = table.clone(info)
			variant.id = info.id .. world.suffix
			variant.name = world.prefix .. info.name
			variant.income = info.income * world.incomeMultiplier
			variant.body = info.body:Lerp(ASH, 0.7)
			variant.pants = info.pants:Lerp(ASH, 0.5):Lerp(LAVA, 0.25)
			variant.glove = LAVA
			variant.world = world.id
			Config.CharacterById[variant.id] = variant
			table.insert(everyone, variant)
		end
	end
end
-- Versão Shiny de cada personagem (só por fusão): não entra no sorteio nem no INDEX.
local GOLD = rgb(255, 205, 60)
for _, info in everyone do
	local shiny = table.clone(info)
	shiny.id = info.id .. Config.Fusion.suffix
	shiny.name = "Shiny " .. info.name
	shiny.income = info.income * Config.Fusion.incomeMultiplier
	shiny.body = info.body:Lerp(GOLD, 0.6)
	shiny.pants = info.pants:Lerp(GOLD, 0.35)
	shiny.glove = GOLD
	shiny.shiny = true
	Config.CharacterById[shiny.id] = shiny
end

return Config
