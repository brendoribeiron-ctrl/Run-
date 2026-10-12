-- Preparação para teste visual do soco: jogador no saco, dinheiro para atributos e crítico alto.
--   node tools/bridge.cjs run server src/server/tests/setup_bag.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()

hook:Invoke("runFinish", player)
hook:Invoke("set", player, { power = 20000, money = 5000, stats = { critChance = 14 } })
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
local origin = plot:GetAttribute("Origin")
local bag = (origin * CFrame.new(Config.Plot.bagOffset)).Position
local spot = (origin * CFrame.new(Config.Plot.spawnOffset)).Position
character:PivotTo(CFrame.lookAt(spot, Vector3.new(bag.X, spot.Y, bag.Z)))
return "no saco, crítico em 36%, $5K"
