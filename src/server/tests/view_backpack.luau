-- Abre a mochila cheia por alguns segundos, com um personagem que dá para fundir selecionado,
-- para captura.
--   node tools/bridge.cjs run server src/server/tests/view_backpack.luau 30000
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
hook:Invoke("giveAll", player)
local state = hook:Invoke("state", player)
local inventory = table.clone(state.inventory)
table.insert(inventory, "brick_bruiser")
table.insert(inventory, "brick_bruiser")
hook:Invoke("set", player, { inventory = inventory })
player:SetAttribute("Selected", 4)
hook:Invoke("ui", player, { command = "toggle", arg = "Backpack" })
task.wait(6)
hook:Invoke("ui", player, { command = "toggle", arg = "Backpack" })
return "ok"
