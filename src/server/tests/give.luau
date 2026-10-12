-- Enche mochila e índice e devolve o estado das janelas no cliente (para testes manuais com captura).
--   node tools/bridge.cjs run server src/server/tests/give.luau
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
hook:Invoke("giveAll", player)
return hook:Invoke("ui", player, { command = "state" })
