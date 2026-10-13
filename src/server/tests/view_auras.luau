-- Mostra cada aura por 5 segundos, com o Poder cheio, para captura; a última repete carregando.
--   node tools/bridge.cjs run server src/server/tests/view_auras.luau 90000
--   powershell -File tools\screenshot.ps1 -Out shots\aura.png -Count 16 -IntervalMs 2500 -DelayMs 1500
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
local seconds = 5
hook:Invoke("ui", player, { command = "camera", arg = { from = spot + Vector3.new(0, 4.5, 17), to = spot + Vector3.new(0, 1, 0), seconds = seconds * (#Config.Auras + 1) } })
for _, info in Config.Auras do
	hook:Invoke("set", player, { aura = info.id, power = Config.AuraFx.fullPower })
	task.wait(seconds)
end
hook:Invoke("ui", player, { command = "charge", arg = seconds - 1 })
task.wait(seconds)
return #Config.Auras .. " auras"
