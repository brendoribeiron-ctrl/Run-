-- Captura visual do super soco: abre o minigame e o cliente joga sozinho (value "fail" erra de propósito).
--   node tools/bridge.cjs run server src/server/tests/fx_super.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
hook:Invoke("runFinish", player)
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
character:PivotTo(plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset))
task.wait(0.8)
hook:Invoke("superOpen", player)
task.wait(0.2)
hook:Invoke("ui", player, { command = "superAuto" })
return "minigame aberto, cliente jogando sozinho"
