--!strict
-- Servidor autoritativo: terrenos, saco de pancada, corrida, pedestais e renda.

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
-- Stat: C->S nome do atributo a comprar
State.createRemotes({ "BagHit", "Charge", "RunResult", "Select", "Fx", "Stat" })
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

remotes.BagHit.OnServerEvent:Connect(function(player)
	local gain, newTier, crit = tryHit(player)
	if gain then
		remotes.BagHit:FireClient(player, gain, crit)
	end
	if newTier then
		local rarity = Config.Rarities[newTier]
		local root = State.root(player)
		remotes.Fx:FireClient(player, "reveal", `{string.upper(rarity.id)} POWER!`, rarity.color, root and root.Position)
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

	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(command: string, player: Player, value: any): any
		if command == "state" then
			return PlayerData.get(player)
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
		elseif command == "upgradeBag" then
			return upgradeBag(player)
		end
		return nil
	end
	hook.Parent = ServerStorage
end
