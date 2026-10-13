-- Progressão: rebirth, poções, recompensa diária, tempo de jogo, missões do dia, fusão Shiny.
--   node tools/bridge.cjs run server src/server/tests/progress.luau 90000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function state()
	return hook:Invoke("state", player)
end
local function go(action, arg)
	return hook:Invoke("progress", player, { action = action, arg = arg })
end
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command or "state", arg = arg })
end
local function open(window)
	ui("toggle", window)
	task.wait(1.3)
	local snapshot = ui()
	ui("toggle", window)
	task.wait(0.2)
	return snapshot
end

hook:Invoke("reset", player)
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
character:PivotTo(plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset))
task.wait(0.5)
local base = Config.Bag.levels[1].power

-- rebirth
local cost = go("rebirthCost", 0)
check("1º rebirth pede o Poder da última parede", cost == Config.Walls[#Config.Walls].power, tostring(cost))
check("o seguinte pede mais", go("rebirthCost", 1) > cost, tostring(go("rebirthCost", 1)))
hook:Invoke("set", player, { power = cost - 1, money = 5_000, bagLevel = 4 })
check("sem Poder não faz rebirth", go("rebirth") == false and state().rebirths == 0, tostring(state().rebirths))
check("janela mostra o que falta", string.find(open("Rebirth").rebirth, "Need", 1, true) ~= nil, "texto")
hook:Invoke("set", player, { power = cost, inventory = { "frost_hook" }, stats = { speed = 2 } })
check("rebirth com o Poder exigido", go("rebirth") == true and state().rebirths == 1, tostring(state().rebirths))
local s = state()
check("rebirth zera Poder, dinheiro e saco", s.power == 0 and s.money == 0 and s.bagLevel == 1 and s.aura == "", `{s.power} {s.money} {s.bagLevel}`)
check("rebirth mantém personagens e skills", #s.inventory == 1 and s.stats.speed == 2, tostring(#s.inventory))
check("atributo replica", player:GetAttribute("Rebirths") == 1, tostring(player:GetAttribute("Rebirths")))
check("rebirth multiplica o soco", hook:Invoke("hit", player, "noCrit") == math.floor(base * (1 + Config.Rebirth.powerPerRebirth)), "ganho")
local boosts = go("boosts")
check("rebirth multiplica a renda", math.abs(boosts.money - (1 + Config.Rebirth.moneyPerRebirth)) < 1e-6, tostring(boosts.money))
hook:Invoke("set", player, { rebirths = Config.Rebirth.max, power = 1e18 })
check("rebirth tem teto", go("rebirth") == false, "passou do máximo")
hook:Invoke("set", player, { rebirths = 0, power = 0, money = 0 })

-- poções
local potion = Config.PotionById.power
hook:Invoke("set", player, { money = potion.price - 1, boosts = {} })
check("sem dinheiro não compra poção", go("potion", "power") == false, "comprou")
check("poção inexistente recusa", go("potion", "banana") == false, "banana")
hook:Invoke("set", player, { money = potion.price * 2 })
check("compra a poção", go("potion", "power") == true and state().money == potion.price, tostring(state().money))
check("poção dobra o soco", hook:Invoke("hit", player, "noCrit") == base * potion.multiplier, "ganho")
local first = state().boosts.power
go("potion", "power")
check("comprar de novo soma tempo", math.abs(state().boosts.power - first - potion.seconds) < 2, tostring(state().boosts.power - first))
check("janela mostra a poção ativa", string.find(open("Shop").potion, "ACTIVE", 1, true) ~= nil, "texto")
hook:Invoke("set", player, { money = 1e9, boosts = { power = workspace:GetServerTimeNow() + Config.Potions.maxSeconds } })
check("poção cheia recusa", go("potion", "power") == false and state().money == 1e9, "cobrou")
hook:Invoke("set", player, { boosts = { power = workspace:GetServerTimeNow() - 5 }, money = 0 })
check("poção vencida não vale", hook:Invoke("hit", player, "noCrit") == base, "ainda dobra")
hook:Invoke("set", player, { boosts = { money = workspace:GetServerTimeNow() + 60, luck = workspace:GetServerTimeNow() + 60 } })
boosts = go("boosts")
check("poções de dinheiro e sorte valem", boosts.money == 2 and boosts.luck == 2, `{boosts.money} {boosts.luck}`)
hook:Invoke("set", player, { boosts = {} })

-- recompensa diária
local today = math.floor(workspace:GetServerTimeNow() / 86400)
hook:Invoke("set", player, { daily = { streak = 0, last = 0 }, money = 0 })
check("janela oferece o dia 1", open("Daily").daily == "CLAIM DAY 1", "texto")
check("resgata o dia 1", go("daily") == Config.Daily.rewards[1] and state().money == Config.Daily.rewards[1] and state().daily.streak == 1, tostring(state().money))
check("só uma vez por dia", go("daily") == nil, "resgatou de novo")
hook:Invoke("set", player, { daily = { streak = 1, last = today - 1 } })
check("no dia seguinte vem o dia 2", go("daily") == Config.Daily.rewards[2] and state().daily.streak == 2, tostring(state().daily.streak))
hook:Invoke("set", player, { daily = { streak = 5, last = today - 3 } })
check("faltou um dia, recomeça", go("daily") == Config.Daily.rewards[1] and state().daily.streak == 1, tostring(state().daily.streak))
hook:Invoke("set", player, { daily = { streak = Config.Daily.days, last = today - 1 } })
check("depois do último volta ao primeiro", go("daily") == Config.Daily.rewards[1], tostring(state().daily.streak))

-- tempo de jogo
hook:Invoke("set", player, { money = 0 })
go("played", 60)
check("antes da hora não resgata", go("playtime", 1) == nil, "resgatou")
go("played", Config.Playtime.minutes[1] * 60 + 5)
task.wait(1.2)
check("cartão fica pronto", string.find(ui().playtime, "CLAIM", 1, true) ~= nil, tostring(ui().playtime))
check("resgata a de 5 minutos", go("playtime", 1) == Config.Playtime.rewards[1] and state().money == Config.Playtime.rewards[1], tostring(state().money))
check("não resgata duas vezes", go("playtime", 1) == nil, "de novo")
check("a seguinte ainda não", go("playtime", 2) == nil and go("playtime", 99) == nil, "resgatou")

-- missões do dia
hook:Invoke("set", player, { money = 0, quests = { day = today, progress = {}, claimed = {} } })
local quest = Config.QuestById.punch
hook:Invoke("hit", player, "noCrit")
check("soco conta na missão", state().quests.progress.punch == 1, tostring(state().quests.progress.punch))
check("missão incompleta não paga", go("quest", "punch") == nil, "pagou")
go("count", { id = "punch", amount = quest.goal })
check("progresso para no objetivo", state().quests.progress.punch == quest.goal, tostring(state().quests.progress.punch))
check("janela mostra a missão pronta", string.find(open("Daily").quest, "CLAIM", 1, true) ~= nil, "texto")
check("missão completa paga", go("quest", "punch") == quest.reward and state().money == quest.reward, tostring(state().money))
check("não paga duas vezes", go("quest", "punch") == nil and go("quest", "banana") == nil, "pagou")
hook:Invoke("set", player, { quests = { day = today - 1, progress = { punch = quest.goal }, claimed = {} } })
check("missão de ontem não vale", go("quest", "punch") == nil, "pagou a de ontem")
hook:Invoke("hit", player, "noCrit")
check("dia novo zera as missões", state().quests.day == today and state().quests.progress.punch == 1, tostring(state().quests.progress.punch))

-- fusão
hook:Invoke("set", player, { inventory = { "brick_bruiser", "frost_hook", "brick_bruiser" } })
check("com duas cópias não funde", go("fuse", 1) == nil and #state().inventory == 3, tostring(#state().inventory))
hook:Invoke("set", player, { inventory = { "brick_bruiser", "frost_hook", "brick_bruiser", "brick_bruiser", "brick_bruiser" } })
check("três iguais viram um Shiny", go("fuse", 3) == "brick_bruiser_shiny", "fusão")
local inventory = state().inventory
check("as três saem e o Shiny entra", #inventory == 3 and table.concat(inventory, ",") == "brick_bruiser,frost_hook,brick_bruiser_shiny", table.concat(inventory, ","))
local shiny = Config.CharacterById.brick_bruiser_shiny
check("Shiny rende mais", shiny.income == Config.CharacterById.brick_bruiser.income * Config.Fusion.incomeMultiplier and shiny.shiny == true, tostring(shiny.income))
check("Shiny não funde de novo", go("fuse", 3) == nil, "fundiu")
check("Shiny vai para o pedestal", hook:Invoke("pedestal", player, 1) == "placed" and plot.Pedestal1:FindFirstChild("Character") ~= nil, "pedestal")
hook:Invoke("tick", player)
check("Shiny rende no pedestal", state().stored["1"] == shiny.income, tostring(state().stored["1"]))

check("bônus de amigos começa em zero", player:GetAttribute("FriendBoost") == 0, tostring(player:GetAttribute("FriendBoost")))

hook:Invoke("reset", player)
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
