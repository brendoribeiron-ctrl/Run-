-- Abre o painel MOUNTS por alguns segundos, para captura.
--   node tools/bridge.cjs run server src/server/tests/view_mounts.luau 30000
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
hook:Invoke("set", player, { money = 30_000, mounts = { hoverboard = true }, mount = "" })
hook:Invoke("ui", player, { command = "toggle", arg = "Mounts" })
task.wait(6)
hook:Invoke("ui", player, { command = "toggle", arg = "Mounts" })
return "ok"
