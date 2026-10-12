-- Preparação para teste visual da corrida: Poder para quebrar 7 paredes e jogador na zona de carga.
--   node tools/bridge.cjs run server src/server/tests/goto_zone.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)

local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
hook:Invoke("runFinish", player)
hook:Invoke("set", player, { power = 16000 })
character:PivotTo(CFrame.new(Config.Run.zoneCenter + Vector3.new(0, 4, 4)) * CFrame.Angles(0, 0, 0))
return "na zona de carga com Poder 16000"
