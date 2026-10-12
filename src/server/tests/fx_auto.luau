-- Captura visual: abre a janela de compra dos automáticos (trancados) no cliente.
--   node tools/bridge.cjs run server src/server/tests/fx_auto.luau
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
hook:Invoke("set", player, { unlocks = {} })
task.wait(0.3)
return hook:Invoke("ui", player, { command = "autoToggle", arg = "super" })
