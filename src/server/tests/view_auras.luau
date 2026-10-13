-- Mostra cada aura por 4 segundos, com o Poder cheio, para captura (a última fica carregando).
--   node tools/bridge.cjs run server src/server/tests/view_auras.luau 90000
--   powershell -File tools\screenshot.ps1 -Out shots\aura.png -Count 8 -IntervalMs 4000 -DelayMs 2500
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local at = Vector3.new(70, Config.World.groundY + 4, 30)
character:PivotTo(CFrame.new(at))
task.wait(0.5)
local spot = character:GetPivot().Position
for index, info in Config.Auras do
	hook:Invoke("set", player, { aura = info.id, power = if index == 1 then Config.AuraFx.startPower else Config.AuraFx.fullPower })
	hook:Invoke("ui", player, { command = "camera", arg = { from = spot + Vector3.new(0, 3, 15), to = spot + Vector3.new(0, 0.5, 0), seconds = 4 } })
	task.wait(4)
end
-- a mesma primeira aura, fraca, de perto, para comparar
return #Config.Auras .. " auras"
