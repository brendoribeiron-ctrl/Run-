-- Botão CORRER: teleporte para a zona de carga, intervalo e recusa durante carga e corrida.
--   node tools/bridge.cjs run server src/server/tests/tp.luau 30000

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

local target = Config.Run.zoneCenter + Config.Run.teleportOffset
local function distance(): number
	return (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
end
local function toPlot()
	local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
	character:PivotTo(plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset))
	task.wait(0.4)
end

hook:Invoke("runFinish", player)
hook:Invoke("set", player, { power = 100 })
toPlot()
check("começa longe da zona", distance() > 50, tostring(root.Position))

check("teleporta do terreno", hook:Invoke("goZone", player, "resetCooldown") == true, "recusado")
task.wait(0.4)
check("chega ao ponto de largada", distance() < 6, tostring(root.Position))
local facing = root.CFrame.LookVector
check("de frente para o corredor", facing.Z < -0.9, tostring(facing))

toPlot()
check("intervalo recusa o segundo pedido", hook:Invoke("goZone", player) == false, "aceitou")
task.wait(0.3)
check("recusado não move", distance() > 50, tostring(root.Position))

-- carga e corrida: o teleporte chega à zona, a carga começa e daí em diante é recusado
check("teleporta de novo sem intervalo", hook:Invoke("goZone", player, "resetCooldown") == true, "recusado")
task.wait(0.4)
check("carga começa na zona", hook:Invoke("runStart", player) == true, tostring(root.Position))
check("recusa durante a carga", hook:Invoke("goZone", player, "resetCooldown") == false, "aceitou")
check("corrida começa", hook:Invoke("runRelease", player, 1) ~= nil, "sem resultado")
check("recusa durante a corrida", hook:Invoke("goZone", player, "resetCooldown") == false, "aceitou")
hook:Invoke("runFinish", player)
task.wait(0.4)
check("depois da corrida volta a aceitar", hook:Invoke("goZone", player, "resetCooldown") == true, "recusado")

hook:Invoke("runFinish", player)
hook:Invoke("set", player, { power = 0, money = 0, inventory = {}, index = {} })
toPlot()
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
