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
	hook:Invoke("set", player, { power = power, money = money or 0, bagLevel = 1, inventory = {}, pedestals = {}, stored = {}, index = {} })
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
check("volta para o terreno", (root.Position - home.Position).Magnitude < 25, tostring(root.Position))
check("índice marca o personagem", state().index[weak.characterId] == true, weak.characterId)

-- Poder 100: quebra as paredes de 15 e 60, para na de 150
reset(100)
toZone()
hook:Invoke("runStart", player)
local mid = hook:Invoke("runRelease", player, 1)
check("poder 100 quebra 2 paredes", mid.broken == 2, tostring(mid.broken))
local expected = (Config.Walls[3].distance / Config.Run.metersPerStud) / Config.Run.speed
check("tempo da corrida vem da distância", math.abs(mid.runTime - expected) < 0.01, tostring(mid.runTime))
hook:Invoke("runFinish", player)

-- carga parcial aproveita menos Poder; carga mínima cancela
reset(20)
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

-- sorteio: parede Epic só dá Rare, Epic ou Legendary
local seen = {}
for _ = 1, 400 do
	local rarity = Config.CharacterById[hook:Invoke("roll", player, 8)].rarity
	seen[rarity] = (seen[rarity] or 0) + 1
end
check("sorteio respeita o tier da parede", seen[3] and seen[4] and seen[5] and not seen[1] and not seen[2] and not seen[6], "raridades fora da faixa")
check("a raridade da parede é a mais comum", seen[4] > seen[3] and seen[4] > seen[5], `R{seen[3]} E{seen[4]} L{seen[5]}`)

-- pedestais e renda
reset(0)
hook:Invoke("set", player, { inventory = { "brick_bruiser" } })
player:SetAttribute("Selected", 1)
check("pedestal trancado recusa", hook:Invoke("pedestal", player, 5) == nil, "pedestal 5")
check("coloca no pedestal", hook:Invoke("pedestal", player, 1) == "placed", "pedestal 1")
check("sai do inventário", #state().inventory == 0 and state().pedestals["1"].id == "brick_bruiser", "inventário")
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
check("modelo aparece no pedestal", plot.Pedestal1:FindFirstChild("Character") ~= nil, "sem modelo")
local before = state().stored["1"] or 0
hook:Invoke("tick", player)
hook:Invoke("tick", player)
local income = Config.CharacterById.brick_bruiser.income
check("renda acumula por segundo", state().stored["1"] - before == income * 2, tostring(state().stored["1"]))
check("recolhe do pedestal", hook:Invoke("pedestal", player, 1) == "picked", "pedestal 1")
check("recolher paga o guardado", state().money >= income * 2 and #state().inventory == 1, tostring(state().money))
check("modelo some do pedestal", plot.Pedestal1:FindFirstChild("Character") == nil, "modelo ficou")

-- upgrade do saco
local cost = Config.Bag.levels[2].cost
hook:Invoke("set", player, { money = cost - 1 })
check("upgrade sem dinheiro recusa", hook:Invoke("upgradeBag", player) == false, "faltando 1")
hook:Invoke("set", player, { money = cost })
check("upgrade cobra e sobe o nível", hook:Invoke("upgradeBag", player) == true and state().bagLevel == 2 and state().money == 0, tostring(state().bagLevel))

reset(0)
character:PivotTo(home)
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
