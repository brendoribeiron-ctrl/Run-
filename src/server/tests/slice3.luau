-- Crítico e atributos (velocidade, chance e dano de crítico).
--   node tools/bridge.cjs run server src/server/tests/slice3.luau 30000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
assert(hook, "TestHook ausente")

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")
task.wait(1)

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function state()
	return hook:Invoke("state", player)
end

hook:Invoke("runFinish", player)
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
local origin = plot:GetAttribute("Origin")
character:PivotTo(origin * CFrame.new(Config.Plot.spawnOffset))
task.wait(0.3)
hook:Invoke("set", player, { power = 0, money = 0, bagLevel = 1, stats = {} })

local base = Config.Bag.levels[1].power
check("soco normal não multiplica", hook:Invoke("hit", player, "noCrit") == base, "sem crítico")
check("crítico multiplica pelo valor base", hook:Invoke("hit", player, "crit") == base * Config.Crit.baseMultiplier, "x" .. Config.Crit.baseMultiplier)

-- atributos: custo cresce, cobra, sobe o nível e replica
local cost0 = Config.statCost("speed", 0)
check("sem dinheiro não compra", hook:Invoke("buyStat", player, "speed") == false, "dinheiro 0")
hook:Invoke("set", player, { money = cost0 })
check("compra velocidade", hook:Invoke("buyStat", player, "speed") == true and state().stats.speed == 1 and state().money == 0, tostring(state().stats.speed))
check("atributo replica", player:GetAttribute("Stat_speed") == 1, tostring(player:GetAttribute("Stat_speed")))
check("custo sobe com o nível", Config.statCost("speed", 1) > cost0, tostring(Config.statCost("speed", 1)))
check("atributo inexistente recusa", hook:Invoke("buyStat", player, "banana") == false, "banana")

hook:Invoke("set", player, { money = 1e9, stats = { critDamage = 2 } })
local expected = math.floor(base * (Config.Crit.baseMultiplier + 2 * Config.Stats.critDamage.perLevel))
check("dano de crítico soma por nível", hook:Invoke("hit", player, "crit") == expected, tostring(expected))

hook:Invoke("set", player, { stats = { speed = Config.Stats.speed.max } })
check("nível máximo recusa", hook:Invoke("buyStat", player, "speed") == false, "no máximo")

-- chance: com 20 níveis (48%) saem bem mais críticos que os 8% base
hook:Invoke("set", player, { stats = { critChance = 20 } })
local crits = 0
for _ = 1, 300 do
	if hook:Invoke("hit", player) > base then
		crits += 1
	end
end
check("chance de crítico sobe com o atributo", crits > 90 and crits < 200, crits .. "/300")

hook:Invoke("set", player, { power = 0, money = 0, stats = {} })
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
