-- Captura visual da corrida: Poder para 7 paredes, teleporte à zona e carga cheia pelo cliente.
--   node tools/bridge.cjs run server src/server/tests/fx_run.luau
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
hook:Invoke("runFinish", player)
hook:Invoke("set", player, { power = 16000 })
assert(hook:Invoke("goZone", player, "resetCooldown"), "teleporte recusado")
task.wait(0.8)
local busy = hook:Invoke("ui", player, { command = "charge", arg = 1.5 })
return "carga iniciada no cliente: " .. tostring(busy)
