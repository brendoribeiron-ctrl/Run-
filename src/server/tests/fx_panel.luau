-- Captura visual do painel 3D: enche o índice e abre a janela INDEX no cliente.
--   node tools/bridge.cjs run server src/server/tests/fx_panel.luau
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
hook:Invoke("runFinish", player)
hook:Invoke("giveAll", player)
character:PivotTo(CFrame.new(-60, 4, 20))
task.wait(1.2)
hook:Invoke("ui", player, { command = "toggle", arg = "Index" })
task.wait(0.2)
task.wait(1)
return hook:Invoke("ui", player, { command = "panel" })
