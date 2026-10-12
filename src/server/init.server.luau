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
local Pedestals = require(script.Pedestals)
local PlayerData = require(script.PlayerData)
local Run = require(script.Run)
local State = require(script.State)
local World = require(script.World)

-- BagHit: C->S pedido de soco, S->C poder ganho (e tier novo, se subiu)
-- Charge: C->S "start" | "release" | "cancel"      RunResult: S->C resultado da corrida (ou nil)
-- Select: C->S índice do inventário                Fx: S->C efeitos ("reveal", "collected", "placed", "toast")
-- Stat: C->S nome do atributo a comprar          GoZone: C->S pedido de teleporte à zona de carga
-- Super: S->C "start", senha, teclas | "result", acertou, ganho | "auto", ganho      C->S senha, acertou
-- Auto: C->S "buy", nome | "toggle", nome, ligado
-- Aura: C->S id da aura a equipar          Slot: C->S posição na mochila, slot rápido de destino
State.createRemotes({ "BagHit", "Charge", "RunResult", "Select", "Fx", "Stat", "GoZone", "Super", "Auto", "Aura", "Slot" })
local remotes = State.remotes

World.setupLighting()
World.buildLobby()
World.buildHallway()

local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"
plotsFolder.Parent = workspace
for i = 1, Config.World.plotCount do
	local plot = World.buildPlot(i)
	plot.Parent = plotsFolder
	State.plots[i] = plot
end

local lastHit: { [Player]: number } = {}
local lastTeleport: { [Player]: number } = {}

type SuperStep = { key: string, zone: number, time: number }
-- token = senha do minigame aberto (nil = fechado); earliest/latest = janela em que um acerto é possível
type SuperState = { token: number?, startedAt: number, earliest: number, latest: number }
local supers: { [Player]: SuperState } = {}
-- automáticos ligados nesta sessão (o que está liberado fica no perfil)
local autoOn: { [Player]: { [string]: boolean } } = {}

local function setNameSign(plot: Model, text: string, color: Color3)
	local sign = plot:FindFirstChild("NameSign")
	local board = sign and sign:FindFirstChild("Board")
	local textLabel = board and board:FindFirstChild("Text")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = text
		textLabel.TextColor3 = color
	end
end

local function refreshBag(plot: Model, bagLevel: number)
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

local function placeCharacter(player: Player, character: Model)
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
		p.aura = aura.id
	end)
	return true
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
		Pedestals.detach(State.plots[id])
	end
	lastHit[player] = nil
	lastTeleport[player] = nil
	supers[player] = nil
	autoOn[player] = nil
	PlayerData.release(player)
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
	gain = math.floor(gain * powerMultiplier(profile))
	local tierBefore = RunMath.powerTier(profile.power)
	PlayerData.update(player, function(p)
		p.power += gain
	end)
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
	local gain = math.floor(Config.Bag.levels[profile.bagLevel].power * SUPER.multiplier * powerMultiplier(profile))
	local tierBefore = RunMath.powerTier(profile.power)
	PlayerData.update(player, function(p)
		p.power += gain
	end)
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
	end
	if newTier then
		task.delay(1.2, revealTier, player, newTier) -- depois do letreiro do super soco
	end
end)

for id, plot in State.plots do
	local gantry = plot:FindFirstChild("Gantry") :: Instance
	local upgrade = gantry:FindFirstChild("Upgrade") :: Instance
	local prompt = upgrade:FindFirstChild("Prompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(player)
		if State.owners[id] == player then
			upgradeBag(player)
		end
	end)
end

remotes.Stat.OnServerEvent:Connect(buyStat)
remotes.Aura.OnServerEvent:Connect(equipAura)
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
	character:PivotTo(CFrame.new(Config.Run.zoneCenter + Config.Run.teleportOffset))
	return true
end
remotes.GoZone.OnServerEvent:Connect(goZone)

Run.connect()
Pedestals.connect()
PlayerData.start()
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Dá um de cada personagem (inventário e índice), dinheiro e Poder no máximo.
-- Só para teste: nunca é ligado fora do Studio.
local GIVEALL_POWER = 10_000_000 -- quebra a última parede (3M) até com carga mínima
local GIVEALL_MONEY = 1_000_000_000_000

local function giveAll(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	PlayerData.update(player, function(p)
		p.power = math.max(p.power, GIVEALL_POWER)
		p.money = math.max(p.money, GIVEALL_MONEY)
		table.clear(p.inventory)
		for _, info in Config.Characters do
			if #p.inventory < Config.Inventory.maxItems then
				table.insert(p.inventory, info.id)
			end
			p.index[info.id] = true
		end
	end)
	player:SetAttribute("Selected", 1)
	return #profile.inventory
end

-- Gancho de teste: só existe no Studio. Os testes em src/server/tests chamam por aqui.
if RunService:IsStudio() then
	-- comando de chat /giveall
	local command = Instance.new("TextChatCommand")
	command.Name = "GiveAll"
	command.PrimaryAlias = "/giveall"
	command.Triggered:Connect(function(source)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			local count = giveAll(player)
			remotes.Fx:FireClient(player, "toast", `GIVEALL: {count} characters, max money and power!`)
		end
	end)
	command.Parent = game:GetService("TextChatService")

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
		elseif command == "pedestal" then
			return Pedestals.interact(player, value)
		elseif command == "tick" then
			Pedestals.tick()
			return true
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
