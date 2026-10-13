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
-- começa sem aura; a primeira chega sozinha ao alcançar o Poder dela e nasce fraca
local first = Config.Auras[1]
hook:Invoke("set", player, { power = 0, aura = "" })
task.wait(0.3)
check("começa sem aura", player:GetAttribute("Aura") == "" and ui("auraState").strength == 0 and ui("auraState").emitting == false, tostring(ui("auraState").strength))
hook:Invoke("hit", player, "noCrit")
check("abaixo do Poder continua sem aura", state().aura == "", state().aura)
hook:Invoke("set", player, { power = first.power - 1 })
hook:Invoke("hit", player, "noCrit")
task.wait(0.3)
check("a primeira aura chega sozinha", state().aura == first.id and player:GetAttribute("Aura") == first.id, state().aura)
local weak = ui("auraState")
check("a aura nasce fraca", weak.emitting and weak.strength > 0 and weak.strength < 0.3, tostring(weak.strength))
hook:Invoke("set", player, { power = Config.AuraFx.fullPower })
task.wait(0.3)
local strong = ui("auraState")
check("a aura cresce com o Poder", strong.strength > 0.99 and strong.rate > weak.rate * 2, `{weak.rate} -> {strong.rate}`)
check("a primeira aura tem um anel de arcos", weak.arcs == 2 and strong.arcs == 2 and not strong.halo, `{weak.arcs} / {strong.arcs}`)
-- cada aura tem o próprio desenho: mais anéis, anel de fora e o efeito extra dela
local seen = {}
for _, info in Config.Auras do
	hook:Invoke("set", player, { aura = info.id })
	task.wait(0.25)
	local look = ui("auraState")
	assert(look.arcs == info.rings * 2, `{info.id}: {look.arcs} arcos, esperava {info.rings * 2}`)
	assert(look.halo == info.halo, `{info.id}: anel de fora {tostring(look.halo)}`)
	local extra = if info.extra == "lightning" or info.extra == "none" then "none" else info.extra
	assert(look.extra == extra, `{info.id}: extra {tostring(look.extra)}, esperava {extra}`)
	seen[info.extra] = true
end
check("cada aura tem o desenho dela", seen.snow and seen.bubbles and seen.lightning and seen.rays and seen.void, "extras")
hook:Invoke("set", player, { aura = "void", power = Config.AuraFx.startPower })
task.wait(0.25)
check("aura forte com pouco Poder mostra menos arcos", ui("auraState").arcs < Config.AuraById.void.rings * 2 and ui("auraState").arcs >= 2, tostring(ui("auraState").arcs))
hook:Invoke("set", player, { aura = first.id, power = Config.AuraFx.fullPower })
check("clicar na equipada tira a aura", hook:Invoke("auraEquip", player, first.id) == true and state().aura == "", state().aura)
hook:Invoke("set", player, { power = 0, aura = "ember" })
check("sem Poder não equipa", hook:Invoke("auraEquip", player, "spark") == false and state().aura == "ember", state().aura)
check("aura inexistente recusa", hook:Invoke("auraEquip", player, "banana") == false, "aceitou")
hook:Invoke("set", player, { power = Config.AuraById.spark.power })
check("com Poder equipa", hook:Invoke("auraEquip", player, "spark") == true and player:GetAttribute("Aura") == "spark", tostring(player:GetAttribute("Aura")))
check("aura multiplica o soco", hook:Invoke("hit", player, "noCrit") == math.floor(base * Config.AuraById.spark.multiplier), `base {base}`)
check("aura multiplica o crítico", hook:Invoke("hit", player, "crit") == math.floor(math.floor(base * Config.Crit.baseMultiplier) * Config.AuraById.spark.multiplier), "crítico")
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
check("super soco paga com a aura", gain == math.floor(base * Config.Super.multiplier * Config.AuraById.spark.multiplier), tostring(gain))

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

hook:Invoke("set", player, { power = 0, money = 0, bagLevel = 1, inventory = {}, index = {}, aura = "" })
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
