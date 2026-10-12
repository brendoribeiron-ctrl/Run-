-- Automáticos: compra com dinheiro, ligar só o que está liberado, AUTO SUPER pagando sem
-- minigame e AUTO CLICK socando sozinho (este último ponta a ponta, pelo cliente).
--   node tools/bridge.cjs run server src/server/tests/auto.luau 60000

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
hook:Invoke("set", player, { power = 0, money = 0, bagLevel = 1, stats = {}, unlocks = {} })
hook:Invoke("autoSet", player, { name = "punch", on = false })
hook:Invoke("autoSet", player, { name = "super", on = false })
task.wait(0.5)

local punch, super = Config.Auto.punch, Config.Auto.super
check("trancado não replica como liberado", player:GetAttribute("Auto_punch") == false, tostring(player:GetAttribute("Auto_punch")))
check("sem dinheiro não compra", hook:Invoke("autoBuy", player, "punch") == false, "comprou")
check("trancado não liga", hook:Invoke("autoSet", player, { name = "super", on = true }) == false, "ligou")
check("nome inexistente recusa", hook:Invoke("autoBuy", player, "banana") == false, "comprou")

hook:Invoke("set", player, { money = punch.price + super.price })
check("compra AUTO CLICK com dinheiro", hook:Invoke("autoBuy", player, "punch") == true and state().money == super.price, tostring(state().money))
check("liberado replica", player:GetAttribute("Auto_punch") == true, tostring(player:GetAttribute("Auto_punch")))
check("não cobra duas vezes", hook:Invoke("autoBuy", player, "punch") == false and state().money == super.price, tostring(state().money))
check("compra AUTO SUPER", hook:Invoke("autoBuy", player, "super") == true and state().money == 0, tostring(state().money))

-- AUTO SUPER ligado: o medidor cheio paga direto, sem abrir minigame
local reward = math.floor(Config.Bag.levels[1].power * Config.Super.multiplier)
task.wait(0.5) -- o cliente liga sozinho ao liberar; aqui o teste manda no estado
hook:Invoke("autoSet", player, { name = "punch", on = false })
if ui("autoState").punch then
	ui("autoToggle", "punch")
end
check("liberado liga", hook:Invoke("autoSet", player, { name = "super", on = true }) == true, "recusou")
task.wait(0.5) -- socos do AUTO CLICK que ainda estavam a caminho
local before = state().power
local token = hook:Invoke("superOpen", player)
check("AUTO SUPER paga sem minigame", token == nil and hook:Invoke("superActive", player) == false and state().power == before + reward, `{state().power} de {before + reward}`)
task.wait(Config.Super.windTime + Config.Super.holdTime + 0.3)

-- desligado: volta a abrir o minigame
hook:Invoke("autoSet", player, { name = "super", on = false })
if ui("autoState").super then
	ui("autoToggle", "super")
end
token = hook:Invoke("superOpen", player)
check("desligado abre o minigame", type(token) == "number", tostring(token))
hook:Invoke("superFinish", player, { token = token, success = false })
task.wait(Config.Super.stepTime + Config.Super.stunTime + 1.5) -- o cliente estoura o tempo e cai
character:PivotTo(plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset))
task.wait(0.6)

-- AUTO CLICK ponta a ponta: ligado no cliente, o Poder sobe sem ninguém clicar
before = state().power
check("cliente liga o AUTO CLICK", ui("autoToggle", "punch") == true, "desligado")
task.wait(2)
local gained = state().power - before
check("AUTO CLICK soca sozinho", gained >= 4, `+{gained} em 2 s`)
ui("autoToggle", "punch")
task.wait(0.5)
before = state().power
task.wait(1)
check("desligado para de socar", state().power == before, `+{state().power - before}`)

hook:Invoke("set", player, { power = 0, money = 0, unlocks = {} })
return `{#passed} verificações OK: ` .. table.concat(passed, "; ") .. ` | AUTO CLICK +{gained} em 2 s`
