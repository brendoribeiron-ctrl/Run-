-- Super soco por sorteio, auras (liberar por Poder, multiplicar o ganho) e slots rápidos da mochila.
--   node tools/bridge.cjs run server src/server/tests/extras.luau 60000

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
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command, arg = arg })
end

hook:Invoke("runFinish", player)
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
character:PivotTo(plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset))
hook:Invoke("autoSet", player, { name = "super", on = false })
hook:Invoke("set", player, { power = 0, money = 0, bagLevel = 10, stats = {}, aura = "ember", unlocks = {} })
task.wait(0.5)

-- super soco: mais raro que o crítico e pagando mais que ele
local base = Config.Bag.levels[10].power
check("super soco é mais raro que o crítico", Config.Super.chance < Config.Crit.baseChance, `{Config.Super.chance} x {Config.Crit.baseChance}`)
check("super soco paga mais que o crítico", Config.Super.multiplier > Config.Crit.baseMultiplier, tostring(Config.Super.multiplier))

-- auras
check("aura inicial replica", player:GetAttribute("Aura") == "ember", tostring(player:GetAttribute("Aura")))
check("sem Poder não equipa", hook:Invoke("auraEquip", player, "spark") == false and state().aura == "ember", state().aura)
check("aura inexistente recusa", hook:Invoke("auraEquip", player, "banana") == false, "aceitou")
hook:Invoke("set", player, { power = Config.AuraById.spark.power })
check("com Poder equipa", hook:Invoke("auraEquip", player, "spark") == true and player:GetAttribute("Aura") == "spark", tostring(player:GetAttribute("Aura")))
check("aura multiplica o soco", hook:Invoke("hit", player, "noCrit") == math.floor(base * 1.05), `base {base}`)
check("aura multiplica o crítico", hook:Invoke("hit", player, "crit") == math.floor(math.floor(base * Config.Crit.baseMultiplier) * 1.05), "crítico")
check("aura mais forte continua trancada", hook:Invoke("auraEquip", player, "void") == false, "equipou")
local bonus = Config.Auras[#Config.Auras].multiplier
check("bônus das auras é pequeno", bonus <= 1.5, tostring(bonus))

-- super soco com aura: paga poder do saco x multiplicador x aura
local before = state().power
local token = hook:Invoke("superOpen", player)
check("super soco abre o minigame", type(token) == "number", tostring(token))
-- o cliente joga o minigame sozinho (o servidor só aceita o acerto no tempo certo)
task.wait(0.3)
ui("superAuto")
task.wait(Config.Super.steps * (Config.Super.stepTime + Config.Super.stepPause) + Config.Super.windTime + Config.Super.holdTime + 1)
local gain = state().power - before
check("super soco paga com a aura", gain == math.floor(base * Config.Super.multiplier * 1.05), tostring(gain))

-- slots rápidos: o 10º personagem vai para o slot 2 e troca de lugar com quem estava lá
local ids = {}
for i = 1, 10 do
	ids[i] = Config.Characters[i].id
end
hook:Invoke("set", player, { inventory = table.clone(ids) })
check("move para o slot rápido", hook:Invoke("slotMove", player, { from = 10, slot = 2 }) == true, "recusou")
local inventory = state().inventory
check("troca de lugar com o slot", inventory[2] == ids[10] and inventory[10] == ids[2] and #inventory == 10, table.concat(inventory, ","))
check("o movido fica selecionado", player:GetAttribute("Selected") == 2, tostring(player:GetAttribute("Selected")))
check("hotbar recebe pelo atributo", string.split(player:GetAttribute("Inventory"), ",")[2] == ids[10], tostring(player:GetAttribute("Inventory")))
check("slot fora da hotbar recusa", hook:Invoke("slotMove", player, { from = 1, slot = Config.Inventory.hotbarSlots + 1 }) == false, "aceitou")
check("posição inexistente recusa", hook:Invoke("slotMove", player, { from = 99, slot = 1 }) == false, "aceitou")
hook:Invoke("set", player, { inventory = { ids[1], ids[2], ids[3] } })
check("com poucos personagens vai para o último ocupado", hook:Invoke("slotMove", player, { from = 1, slot = 8 }) == true and state().inventory[3] == ids[1], table.concat(state().inventory, ","))

-- painel de auras abre no cliente
ui("toggle", "Auras")
task.wait(0.2)
check("painel AURAS abre", ui("state").open == "Auras", ui("state").open)
ui("toggle", "Auras")

hook:Invoke("set", player, { power = 0, money = 0, bagLevel = 1, inventory = {}, index = {}, aura = "ember" })
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
