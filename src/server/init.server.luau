--!strict
-- Servidor autoritativo: terrenos, saco de pancada, corrida, pedestais e renda.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local RunMath = require(ReplicatedStorage.Shared.RunMath)
local Hall = require(script.Hall)
local Pedestals = require(script.Pedestals)
local Progress = require(script.Progress)
local PlayerData = require(script.PlayerData)
local Run = require(script.Run)
local Mounts = require(script.Mounts)
local Sanctum = require(script.Sanctum)
local Scenery = require(script.Scenery)
local State = require(script.State)
local Boss = require(script.Boss)
local BossRoom = require(script.BossRoom)
local Volcano = require(script.Volcano)
local Wizard = require(script.Wizard)
local World = require(script.World)

-- BagHit: C->S pedido de soco, S->C poder ganho (e tier novo, se subiu)
-- Charge: C->S "start" | "release" | "cancel"      RunResult: S->C resultado da corrida (ou nil)
-- Select: C->S índice do inventário                Fx: S->C efeitos ("reveal", "collected", "placed", "toast")
-- World: C->S id do mundo para onde viajar (feiticeiro da casa, portal de volta)
-- Stat: C->S nome do atributo a comprar          GoZone: C->S pedido de teleporte à zona de carga
-- Super: S->C "start", senha, teclas | "result", acertou, ganho | "auto", ganho      C->S senha, acertou
-- Auto: C->S "buy", nome | "toggle", nome, ligado
-- Aura: C->S id da aura a equipar          Slot: C->S posição na mochila, slot rápido de destino
State.createRemotes({ "BagHit", "Charge", "RunResult", "Select", "Fx", "Stat", "GoZone", "Super", "Auto", "Aura", "Slot", "Mount", "Cast", "Sell", "Rebirth", "Potion", "Daily", "Playtime", "Quest", "Fuse", "World", "BossReward", "Boss", "BossHit" })
local remotes = State.remotes

World.setupLighting()
World.buildLobby()
Hall.build(World.buildHallway())
World.buildBounds()
-- os modelos vêm da Roblox (uma chamada por modelo): monta em paralelo, sem segurar o servidor
task.spawn(function()
	if Sanctum.build() then
		Wizard.build()
	end
end)
task.spawn(Volcano.build)
BossRoom.rewarder = Run.reward
BossRoom.build()
BossRoom.connect()
task.spawn(Mounts.build)
task.spawn(Scenery.build)

local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"
plotsFolder.Parent = workspace
for i = 1, Config.World.plotCount do
	local plot = World.buildPlot(i)
	plot.Parent = plotsFolder
	State.plots[i] = plot
end
State.worldPlots[1] = State.plots
State.worldPlots[2] = Volcano.buildPlots() -- o mesmo terreno de cada jogador, no vulcão

local lastHit: { [Player]: number } = {}
local leftover: { [Player]: number } = {} -- fração de Poder que sobrou do último soco
local lastTeleport: { [Player]: number } = {}

type SuperStep = { key: string, zone: number, time: number }
-- token = senha do minigame aberto (nil = fechado); earliest/latest = janela em que um acerto é possível
type SuperState = { token: number?, startedAt: number, earliest: number, latest: number }
local supers: { [Player]: SuperState } = {}
-- automáticos ligados nesta sessão (o que está liberado fica no perfil)
local autoOn: { [Player]: { [string]: boolean } } = {}

-- As três funções abaixo valem para o terreno em todos os mundos: as cópias mostram o mesmo.
local function setNameSign(plot: Model, text: string, color: Color3)
	for _, copy in State.copies(plot) do
		local sign = copy:FindFirstChild("NameSign")
		local board = sign and sign:FindFirstChild("Board")
		local textLabel = board and board:FindFirstChild("Text")
		if textLabel and textLabel:IsA("TextLabel") then
			textLabel.Text = text
			textLabel.TextColor3 = color
		end
	end
end

local function detachPlot(plot: Model)
	for _, copy in State.copies(plot) do
		Pedestals.detach(copy)
	end
end

local function refreshBagOne(plot: Model, bagLevel: number)
	local gantry = plot:FindFirstChild("Gantry")
	local sign = gantry and gantry:FindFirstChild("Sign")
	if not gantry or not sign then
		return
	end
	local levels = Config.Bag.levels
	for _, gui in sign:GetChildren() do
		local title = gui:FindFirstChild("Title")
		local rate = gui:FindFirstChild("Rate")
		if title and title:IsA("TextLabel") then
			title.Text = `BAG Lv {bagLevel}`
		end
		if rate and rate:IsA("TextLabel") then
			rate.Text = `+{levels[bagLevel].power} POWER`
		end
	end
	local upgrade = gantry:FindFirstChild("Upgrade")
	local price = upgrade and upgrade:FindFirstChild("Price")
	local priceText = price and price:FindFirstChild("Text")
	local prompt = upgrade and upgrade:FindFirstChild("Prompt")
	local nextLevel = levels[bagLevel + 1]
	if priceText and priceText:IsA("TextLabel") then
		priceText.Text = if nextLevel then `UPGRADE ${Format.abbreviate(nextLevel.cost)}` else "MAX LEVEL"
	end
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = nextLevel ~= nil
	end
end

local function refreshBag(plot: Model, bagLevel: number)
	for _, copy in State.copies(plot) do
		refreshBagOne(copy, bagLevel)
	end
end

-- Placa em cima da cabeça de cada boneco com o Poder e o dinheiro do jogador: todo mundo vê.
local function headTag(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "StatsTag"
	board.Size = UDim2.fromScale(7, 1.1)
	board.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	board.MaxDistance = 90
	board.Adornee = head
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.RichText = true
	text.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Config.Palette.outline
	stroke.Parent = text
	text.Parent = board
	local function refresh()
		local power, money = player:GetAttribute("Power"), player:GetAttribute("Money")
		text.Text = `<font color="#ffc42e">{Format.abbreviate(if type(power) == "number" then power else 0)} POWER</font>   <font color="#57ff57">${Format.abbreviate(if type(money) == "number" then money else 0)}</font>`
	end
	local connections = { player:GetAttributeChangedSignal("Power"):Connect(refresh), player:GetAttributeChangedSignal("Money"):Connect(refresh) }
	board.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	refresh()
	board.Parent = head
end

local function placeCharacter(player: Player, character: Model)
	player:SetAttribute("World", 1) -- todo boneco novo nasce no terreno, no mundo 1
	task.spawn(headTag, player, character)
	local plot = State.plot(player)
	if not plot then
		return
	end
	-- O RespawnLocation já coloca o personagem no terreno; isto só corrige se ele nascer fora.
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	task.wait(0.3)
	local target = State.spawnCFrame(plot)
	if character.Parent and (root.Position - target.Position).Magnitude > 20 then
		character:PivotTo(target)
	end
end

-- Multiplicador de ganho de Poder da aura equipada. Só vale enquanto o Poder ainda alcança
-- o requisito dela.
local function powerMultiplier(profile: PlayerData.Profile): number
	local aura = Config.AuraById[profile.aura]
	return if aura and profile.power >= aura.power then aura.multiplier else 1
end

-- A primeira aura chega sozinha: quem ainda não tem nenhuma e alcança o Poder dela já sai
-- com ela equipada.
local function grantFirstAura(player: Player)
	local profile = PlayerData.get(player)
	local first = Config.Auras[1]
	if profile and profile.aura == "" and profile.power >= first.power then
		PlayerData.update(player, function(p)
			p.aura = first.id
		end)
		State.remotes.Fx:FireClient(player, "toast", `AURA UNLOCKED: {first.name}!`)
	end
end

-- Equipa a aura; clicar na que já está equipada tira.
local function equipAura(player: Player, id: any): boolean
	local profile = PlayerData.get(player)
	local aura = if type(id) == "string" then Config.AuraById[id] else nil
	if not profile or not aura then
		return false
	end
	if profile.power < aura.power then
		State.remotes.Fx:FireClient(player, "toast", `Need {Format.abbreviate(aura.power)} Power!`)
		return false
	end
	PlayerData.update(player, function(p)
		p.aura = if p.aura == aura.id then "" else aura.id
	end)
	return true
end

-- Montarias: o primeiro clique compra (uma vez, com dinheiro), os seguintes equipam; clicar na
-- que já está equipada desce dela. Devolve "bought", "on" ou "off".
local function useMount(player: Player, id: any): string?
	local profile = PlayerData.get(player)
	local info = if type(id) == "string" then Config.MountById[id] else nil
	if not profile or not info then
		return nil
	end
	if profile.mount == info.id then
		PlayerData.update(player, function(p)
			p.mount = ""
		end)
		return "off"
	end
	local bought = false
	if not profile.mounts[info.id] then
		if profile.money < info.price then
			State.remotes.Fx:FireClient(player, "toast", `Need ${Format.abbreviate(info.price)}!`)
			return nil
		end
		bought = true
	end
	PlayerData.update(player, function(p)
		if bought then
			p.money -= info.price
			p.mounts[info.id] = true
		end
		p.mount = info.id
	end)
	return if bought then "bought" else "on"
end

-- Mochila: leva o personagem da posição `from` para o slot rápido `slot`, trocando de lugar
-- com quem estava lá. O personagem movido fica selecionado.
local function moveToSlot(player: Player, from: any, slot: any): boolean
	local profile = PlayerData.get(player)
	if not profile or type(from) ~= "number" or type(slot) ~= "number" or from % 1 ~= 0 or slot % 1 ~= 0 then
		return false
	end
	local count = #profile.inventory
	if from < 1 or from > count or slot < 1 or slot > Config.Inventory.hotbarSlots then
		return false
	end
	local target = math.min(slot, count) -- com menos personagens que slots, vai para o último ocupado
	if target ~= from then
		PlayerData.update(player, function(p)
			p.inventory[from], p.inventory[target] = p.inventory[target], p.inventory[from]
		end)
	end
	player:SetAttribute("Selected", target)
	return true
end

-- Vende o personagem da posição `index` da mochila: sai do inventário e vira dinheiro (renda
-- dele no nível atual x Config.Inventory.sellSeconds). Devolve quanto pagou. O índice e o
-- nível do personagem não se perdem.
local function sellCharacter(player: Player, index: any): number?
	local profile = PlayerData.get(player)
	if not profile or type(index) ~= "number" or index % 1 ~= 0 then
		return nil
	end
	local id = profile.inventory[index]
	if not id then
		return nil
	end
	local price = Config.sellPrice(id, profile.levels[id] or 1)
	PlayerData.update(player, function(p)
		table.remove(p.inventory, index)
		p.money += price
	end)
	-- a seleção continua no mesmo lugar da mochila (ou no último, se vendeu o último)
	player:SetAttribute("Selected", math.min(index, #profile.inventory))
	State.remotes.Fx:FireClient(player, "toast", `SOLD {Config.CharacterById[id].name}: +${Format.abbreviate(price)}`)
	return price
end

-- Automáticos (Config.Auto): liberar por dinheiro ou Game Pass, ligar e desligar.
local function grantAuto(player: Player, name: string)
	PlayerData.update(player, function(p)
		p.unlocks[name] = true
	end)
end

local function buyAuto(player: Player, name: any): boolean
	local profile = PlayerData.get(player)
	local info = if type(name) == "string" then Config.Auto[name] else nil
	if not profile or not info or profile.unlocks[name] then
		return false
	end
	if profile.money < info.price then
		State.remotes.Fx:FireClient(player, "toast", `Need ${Format.abbreviate(info.price)}!`)
		return false
	end
	PlayerData.update(player, function(p)
		p.money -= info.price
		p.unlocks[name] = true
	end)
	return true
end

-- Só liga o que está liberado; desligar sempre pode.
local function setAuto(player: Player, name: any, on: any): boolean
	local profile = PlayerData.get(player)
	if not profile or type(name) ~= "string" or not Config.Auto[name] or (on == true and not profile.unlocks[name]) then
		return false
	end
	local state = autoOn[player] or {}
	autoOn[player] = state
	state[name] = on == true
	return true
end

local function isAuto(player: Player, name: string): boolean
	local state = autoOn[player]
	local profile = PlayerData.get(player)
	return state ~= nil and state[name] == true and profile ~= nil and profile.unlocks[name] == true
end

-- Quem já tem o Game Pass entra com o automático liberado.
local function checkPasses(player: Player)
	for name, info in Config.Auto do
		if info.passId > 0 then
			task.spawn(function()
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, info.passId)
				if ok and owns and player.Parent == Players then
					grantAuto(player, name)
				end
			end)
		end
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	for name, info in Config.Auto do
		if info.passId > 0 and info.passId == passId then
			grantAuto(player, name)
		end
	end
end)

local function claimPlot(player: Player): number?
	for i = 1, #State.plots do
		if not State.owners[i] then
			State.owners[i] = player
			State.plotOf[player] = i
			player:SetAttribute("PlotId", i)
			local spawn = State.plots[i]:FindFirstChild("Spawn")
			if spawn and spawn:IsA("SpawnLocation") then
				player.RespawnLocation = spawn
			end
			setNameSign(State.plots[i], `{player.DisplayName}'s Plot`, Config.Palette.yellowLine)
			return i
		end
	end
	return nil
end

local function onPlayerAdded(player: Player)
	local id = claimPlot(player)
	if not id then
		player:Kick("Server is full, please try another one.")
		return
	end

	local loaded = PlayerData.load(player)
	if not loaded and player.Parent == Players then
		player:Kick("Could not load your data. Please rejoin.")
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	player:SetAttribute("Selected", #profile.inventory)
	player.CameraMaxZoomDistance = Config.Camera.maxZoom
	Progress.join(player)
	checkPasses(player)
	refreshBag(State.plots[id], profile.bagLevel)
	Pedestals.attach(player, State.plots[id])

	player.CharacterAdded:Connect(function(character)
		placeCharacter(player, character)
	end)
	if player.Character then
		placeCharacter(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	Run.finish(player) -- corrida em andamento: a recompensa já sorteada não se perde
	local id = State.plotOf[player]
	if id then
		State.owners[id] = nil
		State.plotOf[player] = nil
		setNameSign(State.plots[id], "Empty Plot", Color3.fromRGB(200, 200, 210))
		refreshBag(State.plots[id], 1)
		detachPlot(State.plots[id])
	end
	Progress.leave(player)
	lastHit[player] = nil
	leftover[player] = nil
	lastTeleport[player] = nil
	supers[player] = nil
	autoOn[player] = nil
	PlayerData.release(player)
end

-- Efeitos que os outros jogadores veem (src/client/Others.luau): o servidor avisa todos menos
-- quem fez, que já desenhou o próprio efeito.
local function toOthers(player: Player, kind: string, a: any, b: any?)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remotes.Fx:FireClient(other, kind, player, a, b)
		end
	end
end

-- Um soco. Valida dono do terreno, vida, distância e ritmo; o ganho é calculado aqui.
-- Devolve o ganho, o tier novo (quando o Poder passa a quebrar um tier de parede) e se foi crítico.
-- forceCrit só é usado pelos testes.
local critRng = Random.new()
local function tryHit(player: Player, forceCrit: boolean?): (number?, number?, boolean?)
	local profile = PlayerData.get(player)
	local plot = State.plot(player)
	if not profile or not plot or Run.isBusy(player) then
		return nil, nil
	end

	local now = os.clock()
	local previous = lastHit[player]
	if previous and now - previous < Config.Bag.hitCooldown then
		return nil, nil
	end

	local root = State.root(player)
	local gantry = plot:FindFirstChild("Gantry")
	local bag = gantry and gantry:FindFirstChild("Bag")
	local center = bag and bag:GetAttribute("Center")
	if not root or typeof(center) ~= "Vector3" then
		return nil, nil
	end
	local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	if flat.Magnitude > Config.Bag.hitRange then
		return nil, nil
	end

	lastHit[player] = now
	local gain = Config.Bag.levels[profile.bagLevel].power
	-- crítico: sorteado aqui, com os atributos do perfil
	local chance = Config.Crit.baseChance + (profile.stats.critChance or 0) * Config.Stats.critChance.perLevel
	local crit = if forceCrit ~= nil then forceCrit else critRng:NextNumber() < chance
	if crit then
		gain = math.floor(gain * (Config.Crit.baseMultiplier + (profile.stats.critDamage or 0) * Config.Stats.critDamage.perLevel))
	end
	-- Com ganhos pequenos, um bônus de 6% sumiria no arredondamento. O que sobra de cada soco
	-- fica guardado e entra no próximo: na média o jogador recebe o bônus inteiro. (Os testes,
	-- que forçam o crítico, não usam a sobra: lá cada soco é arredondado sozinho.)
	local exact = gain * powerMultiplier(profile) * Progress.powerBoost(player, profile)
	if forceCrit == nil then
		exact += leftover[player] or 0
		gain = math.floor(exact)
		leftover[player] = exact - gain
	else
		gain = math.floor(exact)
	end
	local tierBefore = RunMath.powerTier(profile.power)
	PlayerData.update(player, function(p)
		p.power += gain
	end)
	grantFirstAura(player)
	Progress.count(player, "punch", 1)
	local tierAfter = RunMath.powerTier(profile.power)
	return gain, if tierAfter > tierBefore then tierAfter else nil, crit
end

-- Compra um nível de atributo com dinheiro.
local function buyStat(player: Player, name: any): boolean
	local profile = PlayerData.get(player)
	local stat = if type(name) == "string" then Config.Stats[name] else nil
	if not profile or not stat then
		return false
	end
	local level = profile.stats[name] or 0
	if level >= stat.max then
		return false
	end
	if level >= Config.statCap(name, profile.rebirths) then
		remotes.Fx:FireClient(player, "toast", `Unlock the {Config.Worlds[2].name} to train further!`)
		return false
	end
	local cost = Config.statCost(name, level)
	if profile.money < cost then
		remotes.Fx:FireClient(player, "toast", `Need ${Format.abbreviate(cost)}!`)
		return false
	end
	PlayerData.update(player, function(p)
		p.money -= cost
		p.stats[name] = level + 1
	end)
	return true
end

local function upgradeBag(player: Player): boolean
	local profile = PlayerData.get(player)
	local plot = State.plot(player)
	if not profile or not plot then
		return false
	end
	local nextLevel = Config.Bag.levels[profile.bagLevel + 1]
	if not nextLevel then
		return false
	end
	if profile.money < nextLevel.cost then
		remotes.Fx:FireClient(player, "toast", `Need ${Format.abbreviate(nextLevel.cost)}!`)
		return false
	end
	PlayerData.update(player, function(p)
		p.money -= nextLevel.cost
		p.bagLevel += 1
	end)
	refreshBag(plot, profile.bagLevel)
	local gantry = plot:FindFirstChild("Gantry") :: Instance
	local bag = gantry:FindFirstChild("Bag") :: Instance
	remotes.Fx:FireClient(player, "reveal", `BAG Lv {profile.bagLevel}!`, Config.Palette.cyan, bag:GetAttribute("Center"))
	return true
end

-- Super soco. O acerto das teclas acontece no cliente; o servidor decide quando o minigame
-- abre (por sorteio, a cada soco válido), sorteia as teclas, e só paga se a resposta
-- trouxer a senha certa dentro do tempo em que acertar era possível.
local SUPER = Config.Super
local superRng = Random.new()

local function superActive(player: Player): boolean
	local state = supers[player]
	if not state or not state.token then
		return false
	end
	if os.clock() - state.startedAt > state.latest then
		-- o cliente nunca respondeu: fecha e zera
		state.token = nil
		return false
	end
	return true
end

local function revealTier(player: Player, tier: number)
	local rarity = Config.Rarities[tier]
	local root = State.root(player)
	remotes.Fx:FireClient(player, "reveal", `{string.upper(rarity.id)} POWER!`, rarity.color, root and root.Position)
end

-- Paga um super soco. Devolve o ganho e o tier novo, se subiu.
local function superPay(player: Player, profile: PlayerData.Profile): (number, number?)
	local gain = math.floor(Config.Bag.levels[profile.bagLevel].power * SUPER.multiplier * powerMultiplier(profile) * Progress.powerBoost(player, profile))
	local tierBefore = RunMath.powerTier(profile.power)
	PlayerData.update(player, function(p)
		p.power += gain
	end)
	grantFirstAura(player)
	Progress.count(player, "super", 1)
	local tierAfter = RunMath.powerTier(profile.power)
	return gain, if tierAfter > tierBefore then tierAfter else nil
end

-- Abre um super soco e devolve a senha do minigame. Com o AUTO SUPER ligado não há minigame:
-- o servidor paga na hora e o cliente só encena o soco (devolve nil).
local function superOpen(player: Player): number?
	local state = supers[player]
	if not state then
		state = { token = nil, startedAt = 0, earliest = 0, latest = 0 }
		supers[player] = state
	end
	local profile = PlayerData.get(player)
	if state.token or not profile then
		return nil
	end
	if isAuto(player, "super") then
		local gain, newTier = superPay(player, profile)
		remotes.Super:FireClient(player, "auto", gain)
		task.delay(SUPER.windTime, toOthers, player, "superOther", gain) -- na hora do golpe
		if newTier then
			task.delay(1.2, revealTier, player, newTier)
		end
		return nil
	end
	local steps: { SuperStep } = {}
	local earliest, total, time = 0, 0, SUPER.stepTime
	for i = 1, SUPER.steps do
		local zone = superRng:NextNumber(SUPER.zoneRange.Min, SUPER.zoneRange.Max)
		steps[i] = { key = SUPER.keys[superRng:NextInteger(1, #SUPER.keys)], zone = zone, time = time }
		earliest += zone * time
		total += time + SUPER.stepPause
		time *= SUPER.speedUp
	end
	local token = superRng:NextInteger(1, 2 ^ 30)
	state.token = token
	state.startedAt = os.clock()
	state.earliest = earliest - SUPER.latency
	state.latest = total + SUPER.grace
	remotes.Super:FireClient(player, "start", token, steps)
	return token
end

-- Fecha o minigame. Devolve o ganho (0 = errou), o tier novo se subiu, ou nil se o pedido não vale.
local function superFinish(player: Player, token: any, success: any): (number?, number?)
	local state = supers[player]
	local profile = PlayerData.get(player)
	if not state or not profile or not superActive(player) or state.token ~= token then
		return nil, nil
	end
	local elapsed = os.clock() - state.startedAt
	state.token = nil
	if success ~= true or elapsed < state.earliest then
		return 0, nil
	end
	return superPay(player, profile)
end

remotes.BagHit.OnServerEvent:Connect(function(player)
	if superActive(player) then
		return -- com o minigame aberto o saco não conta socos
	end
	local gain, newTier, crit = tryHit(player)
	if gain then
		remotes.BagHit:FireClient(player, gain, crit)
		toOthers(player, "hitOther", gain, crit == true)
		-- como o crítico, mas mais raro: o soco vira super soco
		if superRng:NextNumber() < SUPER.chance then
			superOpen(player)
		end
	end
	if newTier then
		revealTier(player, newTier)
	end
end)

remotes.Super.OnServerEvent:Connect(function(player, token, success)
	local gain, newTier = superFinish(player, token, success)
	if gain then
		remotes.Super:FireClient(player, "result", gain > 0, gain)
		if gain > 0 then
			task.delay(SUPER.windTime, toOthers, player, "superOther", gain)
		end
	end
	if newTier then
		task.delay(1.2, revealTier, player, newTier) -- depois do letreiro do super soco
	end
end)

for _, plots in State.worldPlots do
	for id, plot in plots do
		local gantry = plot:FindFirstChild("Gantry") :: Instance
		local upgrade = gantry:FindFirstChild("Upgrade") :: Instance
		local prompt = upgrade:FindFirstChild("Prompt") :: ProximityPrompt
		prompt.Triggered:Connect(function(player)
			if State.owners[id] == player then
				upgradeBag(player)
			end
		end)
	end
end

remotes.Stat.OnServerEvent:Connect(buyStat)
remotes.Aura.OnServerEvent:Connect(equipAura)
remotes.Mount.OnServerEvent:Connect(useMount)
remotes.Sell.OnServerEvent:Connect(sellCharacter)

-- Progressão (src/server/Progress.luau)
local function rebirth(player: Player): boolean
	if not Progress.rebirth(player) then
		return false
	end
	local id = State.plotOf[player]
	if id then
		refreshBag(State.plots[id], 1)
		Pedestals.attach(player, State.plots[id]) -- o dinheiro guardado zerou
	end
	return true
end
remotes.Rebirth.OnServerEvent:Connect(rebirth)
-- as poções só são vendidas no balcão da casa de feitiçaria: longe dele o pedido não vale
remotes.Potion.OnServerEvent:Connect(function(player, id)
	local sanctum = workspace:FindFirstChild("Sanctum")
	local counter = sanctum and sanctum:FindFirstChild("ShopBody", true)
	local character = player.Character
	if counter and counter:IsA("BasePart") and character and (character:GetPivot().Position - counter.Position).Magnitude <= Config.Sanctum.shopRange * 3 then
		Progress.buyPotion(player, id)
	end
end)
remotes.Daily.OnServerEvent:Connect(Progress.claimDaily)
remotes.Playtime.OnServerEvent:Connect(Progress.claimPlaytime)
remotes.Quest.OnServerEvent:Connect(Progress.claimQuest)
remotes.Fuse.OnServerEvent:Connect(Progress.fuse)

-- Dash e pulo duplo nascem no cliente: ele avisa e o servidor repassa aos outros (só visual).
local CASTS = { dash = true, jump = true }
local lastCast: { [Player]: number } = {}
remotes.Cast.OnServerEvent:Connect(function(player, kind)
	local now = os.clock()
	if type(kind) ~= "string" or not CASTS[kind] or now - (lastCast[player] or 0) < 0.25 then
		return
	end
	lastCast[player] = now
	toOthers(player, "castOther", kind)
end)
Players.PlayerRemoving:Connect(function(player)
	lastCast[player] = nil
end)

-- Espelho das poses (src/client/Pose.luau): cada cliente manda a pose final do próprio boneco e
-- o servidor só repassa aos outros. É cosmético e vai por canal não confiável; aqui confere o
-- formato e segura o ritmo de quem mandar demais.
local POSE_BYTES = 96
local POSE_RATE = 24 -- pacotes por segundo, no máximo
local poseSync = Instance.new("UnreliableRemoteEvent")
poseSync.Name = "PoseSync"
poseSync.Parent = ReplicatedStorage:WaitForChild("Remotes")
local poseBudget: { [Player]: { at: number, count: number } } = {}
poseSync.OnServerEvent:Connect(function(player, data)
	if typeof(data) ~= "buffer" or buffer.len(data) ~= POSE_BYTES then
		return
	end
	local now = os.clock()
	local budget = poseBudget[player]
	if not budget or now - budget.at >= 1 then
		budget = { at = now, count = 0 }
		poseBudget[player] = budget
	end
	budget.count += 1
	if budget.count > POSE_RATE then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			poseSync:FireClient(other, player, data)
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	poseBudget[player] = nil
end)
remotes.Slot.OnServerEvent:Connect(moveToSlot)
remotes.Auto.OnServerEvent:Connect(function(player, action, name, on)
	if action == "buy" then
		buyAuto(player, name)
	elseif action == "toggle" then
		setAuto(player, name, on)
	end
end)

-- Botão CORRER: leva o jogador à zona de carga. O cliente só pede; o destino é fixo e
-- decidido aqui. Recusa no meio de uma carga ou corrida e respeita um intervalo por jogador.
local function goZone(player: Player): boolean
	local character = player.Character
	if not PlayerData.get(player) or not character or not State.root(player) or Run.isBusy(player) then
		return false
	end
	local now = os.clock()
	local previous = lastTeleport[player]
	if previous and now - previous < Config.Run.teleportCooldown then
		remotes.Fx:FireClient(player, "toast", `Wait {math.ceil(Config.Run.teleportCooldown - (now - previous))}s`)
		return false
	end
	lastTeleport[player] = now
	player:SetAttribute("Room", nil)
	character:PivotTo(CFrame.new(Config.zoneCenter(State.world(player)) + Config.Run.teleportOffset))
	return true
end
remotes.GoZone.OnServerEvent:Connect(goZone)

-- Viagem entre mundos. Para os mundos seguintes o jogador precisa ter os rebirths que o
-- feiticeiro pede e estar perto dele; para voltar ao mundo 1, basta estar fora de uma corrida.
-- O destino é sempre decidido aqui.
local function travel(player: Player, id: any): boolean
	local world = if type(id) == "number" then Config.Worlds[id] else nil
	local profile = PlayerData.get(player)
	local character = player.Character
	local root = State.root(player)
	if not world or not profile or not character or not root or Run.isBusy(player) or State.world(player).id == world.id then
		return false
	end
	if world.id ~= 1 then
		if profile.rebirths < world.rebirths then
			remotes.Fx:FireClient(player, "toast", `You need {world.rebirths} rebirths to enter the {world.name}!`)
			return false
		end
		local wizard = Wizard.position()
		if not wizard or (root.Position - wizard).Magnitude > Config.Wizard.travelRange then
			return false
		end
	end
	player:SetAttribute("World", world.id)
	player:SetAttribute("Room", nil)
	-- nos outros mundos chega-se pela praça da ilha; no gramado, pelo próprio terreno
	local target = if world.id == 1 then State.homeCFrame(player) else State.arriveCFrame(world)
	if not target then
		return false
	end
	-- o mapa é carregado por proximidade: pede o destino antes, senão o boneco chega sem chão
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5)
	end)
	if character.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(target)
	end
	return true
end
remotes.World.OnServerEvent:Connect(travel)
remotes.BossHit.OnServerEvent:Connect(function(player)
	Boss.punch(player)
end)

-- Rede de segurança: quem cair para fora do mapa volta para o próprio terreno.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local root = State.root(player)
			local home = State.homeCFrame(player)
			local character = player.Character
			if root and home and character and root.Position.Y < Config.World.fallY then
				root.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(home)
			end
		end
	end
end)

Run.connect()
Pedestals.connect()
PlayerData.start()
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Dá um de cada personagem (inventário e índice), todas as auras (pelo Poder), skills no
-- máximo, dinheiro e Poder.
-- Comando de admin (/giveall); também usado pelos testes.
-- quebra a última parede do último mundo até com carga mínima
local lastWalls = Config.Worlds[#Config.Worlds].walls
local GIVEALL_POWER = lastWalls[#lastWalls].power * 4
for _, aura in Config.Auras do
	GIVEALL_POWER = math.max(GIVEALL_POWER, aura.power) -- e libera todas as auras
end
local GIVEALL_MONEY = 1_000_000_000_000

local function giveAll(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	PlayerData.update(player, function(p)
		p.power = math.max(p.power, GIVEALL_POWER)
		p.money = math.max(p.money, GIVEALL_MONEY)
		-- skills (atributos do painel SKILLS) no nível máximo
		for name, stat in Config.Stats do
			p.stats[name] = stat.max
		end
		p.slots = #Config.Plot.pedestals
		for _, info in Config.Mounts do
			p.mounts[info.id] = true
		end
		table.clear(p.inventory)
		for _, info in Config.Characters do
			if #p.inventory < Config.Inventory.maxItems then
				table.insert(p.inventory, info.id)
			end
			p.index[info.id] = true
		end
	end)
	player:SetAttribute("Selected", 1)
	local id = State.plotOf[player]
	if id then
		Pedestals.attach(player, State.plots[id]) -- os pedestais liberados aparecem na hora
	end
	return #profile.inventory
end

-- Quem é admin: todo mundo no Studio; no jogo publicado, o dono, quem está em Config.Admins
-- e, em jogo de grupo, quem tem o cargo de Config.AdminGroupRank para cima.
local adminCache: { [number]: boolean } = {}
local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local cached = adminCache[player.UserId]
	if cached ~= nil then
		return cached
	end
	local admin = table.find(Config.Admins, player.UserId) ~= nil
	if not admin then
		if game.CreatorType == Enum.CreatorType.User then
			admin = player.UserId == game.CreatorId
		else
			-- consulta à Roblox: pode falhar; nesse caso não é admin agora e tenta de novo depois
			local ok, rank = pcall(function()
				return player:GetRankInGroup(game.CreatorId)
			end)
			if not ok then
				return false
			end
			admin = rank >= Config.AdminGroupRank
		end
	end
	adminCache[player.UserId] = admin
	return admin
end

-- Zera o jogador: perfil de jogador novo, terreno limpo e boneco de volta ao começo.
local function resetPlayer(player: Player): boolean
	if not PlayerData.get(player) then
		return false
	end
	Run.finish(player)
	PlayerData.reset(player)
	supers[player] = nil
	autoOn[player] = nil
	lastHit[player] = nil
	player:SetAttribute("Selected", 0)
	local id = State.plotOf[player]
	if id then
		refreshBag(State.plots[id], 1)
		Pedestals.attach(player, State.plots[id])
		local character = player.Character
		if character and character.Parent then
			player:SetAttribute("World", 1)
			character:PivotTo(State.spawnCFrame(State.plots[id]))
		end
	end
	return true
end

-- Jogador no servidor cujo nome (ou apelido) começa com `wanted`, sem diferenciar maiúsculas.
local function findPlayer(wanted: string): Player?
	local prefix = string.lower(wanted)
	for _, other in Players:GetPlayers() do
		if string.sub(string.lower(other.Name), 1, #prefix) == prefix or string.sub(string.lower(other.DisplayName), 1, #prefix) == prefix then
			return other
		end
	end
	return nil
end

-- Quantia escrita no chat: "5000", "2.5k", "10M", "3b", "1T".
local GIVE_SUFFIX: { [string]: number } = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
local GIVE_MAX = 1e15
local function parseAmount(text: string?): number?
	local digits, suffix = string.match(string.lower(text or ""), "^([%d%.]+)([kmbt]?)$")
	local value = tonumber(digits)
	if not value then
		return nil
	end
	local amount = math.floor(value * (GIVE_SUFFIX[suffix] or 1))
	return if amount >= 1 and amount <= GIVE_MAX then amount else nil
end

-- /give: soma Poder ou dinheiro ao jogador. Devolve a mensagem, ou nil se o pedido não vale.
local function give(target: Player, kind: string, amount: number): string?
	local field = if kind == "power" then "power" elseif kind == "money" then "money" else nil
	if not field or not PlayerData.get(target) then
		return nil
	end
	PlayerData.update(target, function(p)
		(p :: any)[field] = math.min((p :: any)[field] + amount, GIVE_MAX)
	end)
	if field == "power" then
		grantFirstAura(target)
		return `GIVE ({target.Name}): +{Format.abbreviate(amount)} Power!`
	end
	return `GIVE ({target.Name}): +${Format.abbreviate(amount)}!`
end

-- Comandos de chat de admin. Quem não é admin não recebe nada (nem aviso de que o comando
-- existe). Sem nome, o comando vale para quem digitou; com um nome (ou o começo dele), vale
-- para aquele jogador:  /giveall   /giveall fulano   /reset   /reset fulano
--   /give power 5M   /give money 250k fulano   /give power 1b "fulano"
local function adminCommand(name: string, alias: string, action: (admin: Player, target: Player) -> string)
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = alias
	command.Triggered:Connect(function(source, text)
		local admin = Players:GetPlayerByUserId(source.UserId)
		if not admin or not isAdmin(admin) then
			return
		end
		local target = admin
		local wanted = string.lower(string.match(text, "^%S+%s+(%S+)") or "")
		if wanted ~= "" then
			local found = findPlayer(wanted)
			if not found then
				remotes.Fx:FireClient(admin, "toast", `No player called "{wanted}" here.`)
				return
			end
			target = found
		end
		local message = action(admin, target)
		remotes.Fx:FireClient(admin, "toast", message)
		if target ~= admin then
			remotes.Fx:FireClient(target, "toast", message)
		end
	end)
	command.Parent = game:GetService("TextChatService")
end
adminCommand("GiveAll", "/giveall", function(_, target)
	local count = giveAll(target)
	return `GIVEALL ({target.Name}): {count} characters, all auras, max skills, money and power!`
end)
-- /give tem argumentos próprios (o quê, quanto e, se quiser, para quem), então não usa adminCommand.
-- Devolve a mensagem para o admin e o jogador que recebeu (nil se nada foi dado).
local function giveCommand(admin: Player, text: string): (string, Player?)
	local kind, amountText, rest = string.match(text, "^%S+%s+(%a+)%s+(%S+)%s*(.*)$")
	local amount = parseAmount(amountText)
	kind = string.lower(kind or "")
	if (kind ~= "power" and kind ~= "money") or not amount then
		return "Usage: /give power|money <amount> [player]   e.g. /give power 5M", nil
	end
	local wanted = string.gsub(string.gsub(rest or "", '["\']', ""), "^%s*(.-)%s*$", "%1")
	local target: Player? = admin
	if wanted ~= "" then
		target = findPlayer(wanted)
		if not target then
			return `No player called "{wanted}" here.`, nil
		end
	end
	local message = give(target :: Player, kind, amount)
	return message or `GIVE ({(target :: Player).Name}): no data loaded.`, if message then target else nil
end
do
	local command = Instance.new("TextChatCommand")
	command.Name = "Give"
	command.PrimaryAlias = "/give"
	command.Triggered:Connect(function(source, text)
		local admin = Players:GetPlayerByUserId(source.UserId)
		if not admin or not isAdmin(admin) then
			return
		end
		local message, target = giveCommand(admin, text)
		remotes.Fx:FireClient(admin, "toast", message)
		if target and target ~= admin then
			remotes.Fx:FireClient(target, "toast", message)
		end
	end)
	command.Parent = game:GetService("TextChatService")
end
adminCommand("Reset", "/reset", function(_, target)
	return if resetPlayer(target) then `RESET ({target.Name}): everything back to zero.` else `RESET ({target.Name}): no data loaded.`
end)

-- Gancho de teste: só existe no Studio. Os testes em src/server/tests chamam por aqui.
if RunService:IsStudio() then
	-- TestUi: S->C, os testes perguntam ao cliente o estado das janelas e das poses
	local testUi = Instance.new("RemoteFunction")
	testUi.Name = "TestUi"
	testUi.Parent = ReplicatedStorage:WaitForChild("Remotes")

	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(command: string, player: Player, value: any): any
		if command == "state" then
			return PlayerData.get(player)
		elseif command == "ui" then
			return testUi:InvokeClient(player, value.command, value.arg)
		elseif command == "plot" then
			return State.plotOf[player]
		elseif command == "hit" then
			if value ~= "keepCooldown" then
				lastHit[player] = nil -- o teste não espera o intervalo entre socos
			end
			return (tryHit(player, if value == "crit" then true elseif value == "noCrit" then false else nil))
		elseif command == "buyStat" then
			return buyStat(player, value)
		elseif command == "set" then
			PlayerData.update(player, function(p)
				for key, v in value do
					(p :: any)[key] = v
				end
			end)
			return true
		elseif command == "runStart" then
			return Run.start(player)
		elseif command == "runRelease" then
			return Run.release(player, value)
		elseif command == "runFinish" then
			Run.finish(player)
			return true
		elseif command == "roll" then
			return Run.rollCharacter(value)
		elseif command == "travel" then
			return travel(player, value)
		elseif command == "leaveRoom" then
			return BossRoom.leave(player)
		elseif command == "bossWin" then
			return BossRoom.victory(player)
		elseif command == "boss" then
			-- value = { action, arg }: estado e controle do golem da sala em que o jogador está
			local room = player:GetAttribute("Room") or value.world or 1
			if value.action == "state" then
				return Boss.debug(room)
			elseif value.action == "challenge" then
				return Boss.challenge(player, BossRoom.hasPending(player))
			elseif value.action == "punch" then
				return Boss.punch(player, value.arg)
			elseif value.action == "pending" then
				BossRoom.setPending(player, value.arg)
				return true
			end
			return Boss.test(room, value.action, value.arg)
		elseif command == "wizard" then
			return Wizard.position()
		elseif command == "pedestal" then
			return Pedestals.interact(player, value)
		elseif command == "mount" then
			return useMount(player, value)
		elseif command == "collect" then
			return Pedestals.collect(player)
		elseif command == "fighterUp" then
			return Pedestals.upgrade(player, value)
		elseif command == "refreshPlot" then
			Pedestals.attach(player, State.plots[State.plotOf[player]])
			return true
		elseif command == "tick" then
			Pedestals.tick()
			return true
		elseif command == "progress" then
			-- value = { action, arg }: chama direto as funções de Progress
			local action, arg = value.action, value.arg
			if action == "rebirth" then
				return rebirth(player)
			elseif action == "rebirthCost" then
				return Progress.rebirthCost(arg)
			elseif action == "potion" then
				return Progress.buyPotion(player, arg)
			elseif action == "daily" then
				return Progress.claimDaily(player)
			elseif action == "playtime" then
				return Progress.claimPlaytime(player, arg)
			elseif action == "played" then
				Progress.setPlayed(player, arg)
				return true
			elseif action == "quest" then
				return Progress.claimQuest(player, arg)
			elseif action == "count" then
				Progress.count(player, arg.id, arg.amount)
				return true
			elseif action == "fuse" then
				return Progress.fuse(player, arg)
			elseif action == "boosts" then
				local profile = PlayerData.get(player) :: PlayerData.Profile
				return { power = Progress.powerBoost(player, profile), money = Progress.moneyBoost(player, profile), luck = Progress.luckBoost(player, profile) }
			end
			return nil
		elseif command == "sell" then
			return sellCharacter(player, value)
		elseif command == "reset" then
			return resetPlayer(player)
		elseif command == "giveCommand" then
			return (giveCommand(player, value))
		elseif command == "isAdmin" then
			return isAdmin(player)
		elseif command == "giveAll" then
			return giveAll(player)
		elseif command == "auraEquip" then
			return equipAura(player, value)
		elseif command == "slotMove" then
			return moveToSlot(player, value.from, value.slot)
		elseif command == "autoBuy" then
			return buyAuto(player, value)
		elseif command == "autoSet" then
			return setAuto(player, value.name, value.on)
		elseif command == "superOpen" then
			return superOpen(player)
		elseif command == "superActive" then
			return superActive(player)
		elseif command == "superFinish" then
			return (superFinish(player, value.token, value.success))
		elseif command == "goZone" then
			if value == "resetCooldown" then
				lastTeleport[player] = nil -- o teste não espera o intervalo
			end
			return goZone(player)
		elseif command == "upgradeBag" then
			return upgradeBag(player)
		end
		return nil
	end
	hook.Parent = ServerStorage
end
