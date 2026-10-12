-- Captura visual: Poder 300K (4 auras liberadas), mochila cheia, e abre o painel pedido no cliente.
--   node tools/bridge.cjs run server src/server/tests/fx_auras.luau
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
hook:Invoke("runFinish", player)
hook:Invoke("giveAll", player)
hook:Invoke("set", player, { power = 300000, aura = "frost" })
character:PivotTo(CFrame.new(-60, 4, 20))
task.wait(1.2)
local open = hook:Invoke("ui", player, { command = "state" }).open
hook:Invoke("ui", player, { command = "toggle", arg = if open == "Auras" then "Backpack" else "Auras" })
return "aberto"
