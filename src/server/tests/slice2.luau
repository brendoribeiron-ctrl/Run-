-- Fatias 2 a 5: carga, corrida, sorteio, inventário, pedestais, renda e upgrade do saco.
--   node tools/bridge.cjs run server src/server/tests/slice2.luau 60000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
assert(hook, "TestHook ausente")

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
task.wait(1)

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end

local function reset(power, money)
	hook:Invoke("runFinish", player)
	hook:Invoke("set", player, { power = power, money = money or 0, bagLevel = 1, inventory = {}, pedestals = {}, stored = {}, index = {}, slots = Config.Plot.freePedestals, levels = {} })
	hook:Invoke("refreshPlot", player)
end
local function toZone()
	character:PivotTo(CFrame.new(Config.Run.zoneCenter + Vector3.new(0, 4, 0)))
	task.wait(0.2)
end
local function state()
	return hook:Invoke("state", player)
end

local home = character:GetPivot()

-- carga só dentro da zona
reset(0)
check("fora da zona não carrega", hook:Invoke("runStart", player) == false, "no terreno")
toZone()
check("na zona carrega", hook:Invoke("runStart", player) == true, "zona")
check("não carrega duas vezes", hook:Invoke("runStart", player) == false, "sessão aberta")

-- sem Poder: nenhuma parede, personagem Common
local weak = hook:Invoke("runRelease", player, 1)
check("sem poder não quebra parede", weak and weak.broken == 0, weak and tostring(weak.broken))
check("sem parede sai Common", Config.CharacterById[weak.characterId].rarity == 1, weak.characterId)
check("primeiro personagem é novo", weak.isNew == true, tostring(weak.isNew))
check("soco bloqueado durante a corrida", hook:Invoke("hit", player) == nil, "em corrida")
hook:Invoke("runFinish", player)
task.wait(0.3)
check("recompensa entra no inventário", #state().inventory == 1 and state().inventory[1] == weak.characterId, tostring(#state().inventory))
check("volta para a zona de carga", (root.Position - (Config.Run.zoneCenter + Config.Run.teleportOffset)).Magnitude < 8, tostring(root.Position))
check("índice marca o personagem", state().index[weak.characterId] == true, weak.characterId)

-- Poder logo abaixo da 3ª parede: quebra as duas primeiras e para nela
reset(Config.Walls[3].power - 1)
toZone()
hook:Invoke("runStart", player)
local mid = hook:Invoke("runRelease", player, 1)
check("poder abaixo da 3ª parede quebra 2", mid.broken == 2, tostring(mid.broken))
local expected = (Config.Walls[3].distance / Config.Run.metersPerStud) / Config.Run.speed
check("tempo da corrida vem da distância", math.abs(mid.runTime - expected) < 0.01, tostring(mid.runTime))
hook:Invoke("runFinish", player)

-- carga parcial aproveita menos Poder; carga mínima cancela
reset(Config.Walls[1].power)
toZone()
hook:Invoke("runStart", player)
local partial = hook:Invoke("runRelease", player, 0.2)
check("carga de 20% enfraquece", partial.broken == 0, tostring(partial.broken))
hook:Invoke("runFinish", player)
toZone()
hook:Invoke("runStart", player)
check("carga abaixo do mínimo cancela", hook:Invoke("runRelease", player, 0.05) == nil, "5%")
check("cancelar libera nova carga", hook:Invoke("runStart", player) == true, "depois do cancelamento")
hook:Invoke("runFinish", player)

-- sorteio: chegar na parede Epic não garante Epic; ele continua raro e Mítico mais ainda
local function rolls(wall: number, count: number): { [number]: number }
	local seen = {}
	for _ = 1, count do
		local rarity = Config.CharacterById[hook:Invoke("roll", player, wall)].rarity
		seen[rarity] = (seen[rarity] or 0) + 1
	end
	return seen
end
local epic = rolls(8, 1000)
check("parede Epic: Epic é minoria", (epic[4] or 0) > 40 and (epic[4] or 0) < 200, `E{epic[4]}`)
check("parede Epic: comuns ainda saem", (epic[1] or 0) > 100 and (epic[2] or 0) > 200, `C{epic[1]} U{epic[2]}`)
local last = rolls(#Config.Walls, 1000)
check("última parede: Mítico raro", (last[6] or 0) < 40, `M{last[6]}`)
check("mais longe = mais chance de raro", (last[4] or 0) + (last[5] or 0) > (epic[4] or 0) + (epic[5] or 0), "")
check("sem parede só comum", rolls(0, 50)[1] == 50, "")

-- pedestais e renda
reset(0)
hook:Invoke("set", player, { inventory = { "brick_bruiser" } })
player:SetAttribute("Selected", 1)
local free = Config.Plot.freePedestals
local unlockCost = Config.Plot.pedestals[free + 1].cost
check("terreno tem 10 pedestais", #Config.Plot.pedestals == 10 and workspace.Plots["Plot" .. hook:Invoke("plot", player)]:FindFirstChild("Pedestal10") ~= nil, tostring(#Config.Plot.pedestals))
check("pedestal trancado recusa", hook:Invoke("pedestal", player, free + 1) == nil and #state().inventory == 1, "sem dinheiro")
check("não pula a ordem", hook:Invoke("pedestal", player, free + 2) == nil, "pedestal seguinte")
hook:Invoke("set", player, { money = unlockCost })
check("libera o pedestal pagando", hook:Invoke("pedestal", player, free + 1) == "unlocked" and state().slots == free + 1 and state().money == 0, tostring(state().slots))
check("liberar não gasta o personagem", #state().inventory == 1, tostring(#state().inventory))
check("coloca no pedestal", hook:Invoke("pedestal", player, 1) == "placed", "pedestal 1")
check("sai do inventário", #state().inventory == 0 and state().pedestals["1"].id == "brick_bruiser", "inventário")
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
check("modelo aparece no pedestal", plot.Pedestal1:FindFirstChild("Character") ~= nil, "sem modelo")
local before = state().stored["1"] or 0
hook:Invoke("tick", player)
hook:Invoke("tick", player)
local income = Config.CharacterById.brick_bruiser.income
check("renda acumula por segundo", state().stored["1"] - before == income * 2, tostring(state().stored["1"]))
-- coleta única: um botão soma e recolhe o que todos os pedestais guardam
hook:Invoke("set", player, { inventory = { "rookie_jabber" }, money = 0 })
player:SetAttribute("Selected", 1)
check("coloca um segundo personagem", hook:Invoke("pedestal", player, 2) == "placed", "pedestal 2")
hook:Invoke("tick", player)
local both = state().stored["1"] + state().stored["2"]
check("terreno tem um botão de coleta só", plot:FindFirstChild("Collect") ~= nil and plot.Pedestal1:FindFirstChild("CashPad") == nil, "pads antigos")
check("o botão mostra a soma", string.find(plot.Collect.Gui.Amount.Text, tostring(both), 1, true) ~= nil, plot.Collect.Gui.Amount.Text)
check("coleta tudo de uma vez", hook:Invoke("collect", player) == both and state().money == both and state().stored["1"] == 0 and state().stored["2"] == 0, tostring(state().money))
check("sem nada guardado não paga", hook:Invoke("collect", player) == 0, "pagou de novo")
check("recolhe o segundo", hook:Invoke("pedestal", player, 2) == "picked", "pedestal 2")
hook:Invoke("set", player, { inventory = {} })

-- nível do personagem: sobe com dinheiro, aumenta a renda e não se perde ao recolher
local upCost = Config.fighterCost("brick_bruiser", 1)
hook:Invoke("set", player, { money = upCost - 1 })
check("subir de nível sem dinheiro recusa", hook:Invoke("fighterUp", player, 1) == false, "faltando 1")
hook:Invoke("set", player, { money = upCost })
check("subir de nível cobra", hook:Invoke("fighterUp", player, 1) == true and state().levels.brick_bruiser == 2 and state().money == 0, tostring(state().money))
check("pedestal vazio não sobe nível", hook:Invoke("fighterUp", player, 2) == false, "pedestal 2")
local stored = state().stored["1"]
hook:Invoke("tick", player)
check("nível aumenta a renda", state().stored["1"] - stored == Config.fighterIncome("brick_bruiser", 2) and Config.fighterIncome("brick_bruiser", 2) > income, tostring(state().stored["1"] - stored))
check("o próximo nível custa mais", Config.fighterCost("brick_bruiser", 2) > upCost, "custo")
hook:Invoke("set", player, { levels = { brick_bruiser = Config.Fighter.maxLevel }, money = 1e15 })
check("nível máximo recusa", hook:Invoke("fighterUp", player, 1) == false, "máximo")
hook:Invoke("set", player, { levels = { brick_bruiser = 2 }, money = 0 })
local kept = state().stored["1"]
check("recolhe do pedestal", hook:Invoke("pedestal", player, 1) == "picked", "pedestal 1")
check("o nível fica com o personagem", state().levels.brick_bruiser == 2, "nível perdido")
check("recolher paga o guardado", kept > 0 and state().money == kept and #state().inventory == 1, tostring(state().money))
check("modelo some do pedestal", plot.Pedestal1:FindFirstChild("Character") == nil, "modelo ficou")

-- venda: o personagem sai da mochila e vira dinheiro; o preço acompanha o nível dele
hook:Invoke("set", player, { inventory = { "rookie_jabber", "brick_bruiser", "frost_hook" }, money = 0, levels = { brick_bruiser = 2 } })
player:SetAttribute("Selected", 2)
check("posição inexistente não vende", hook:Invoke("sell", player, 9) == nil and hook:Invoke("sell", player, 0) == nil and hook:Invoke("sell", player, "x") == nil, "vendeu")
local sellPrice = Config.sellPrice("brick_bruiser", 2)
check("vende pelo preço do nível", hook:Invoke("sell", player, 2) == sellPrice and state().money == sellPrice and sellPrice > Config.sellPrice("brick_bruiser", 1), tostring(state().money))
check("vender libera espaço na mochila", #state().inventory == 2 and state().inventory[1] == "rookie_jabber" and state().inventory[2] == "frost_hook", table.concat(state().inventory, ","))
check("a seleção fica no mesmo lugar", player:GetAttribute("Selected") == 2, tostring(player:GetAttribute("Selected")))
check("o nível não se perde na venda", state().levels.brick_bruiser == 2, "nível")
hook:Invoke("sell", player, 2)
hook:Invoke("sell", player, 1)
check("vender tudo esvazia a mochila", #state().inventory == 0 and player:GetAttribute("Selected") == 0 and hook:Invoke("sell", player, 1) == nil, tostring(#state().inventory))

-- upgrade do saco
local cost = Config.Bag.levels[2].cost
hook:Invoke("set", player, { money = cost - 1 })
check("upgrade sem dinheiro recusa", hook:Invoke("upgradeBag", player) == false, "faltando 1")
hook:Invoke("set", player, { money = cost })
check("upgrade cobra e sobe o nível", hook:Invoke("upgradeBag", player) == true and state().bagLevel == 2 and state().money == 0, tostring(state().bagLevel))

reset(0)
character:PivotTo(home)
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
