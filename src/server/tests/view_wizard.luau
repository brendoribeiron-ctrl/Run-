-- Três tomadas do feiticeiro (de frente, de lado, com a conversa aberta), 4 s cada.
--   node tools/bridge.cjs run server src/server/tests/view_wizard.luau 60000
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local sanctum = workspace:WaitForChild("Sanctum", 90)
sanctum:WaitForChild("Wizard", 30)
local spot = hook:Invoke("wizard", player)
local toCenter = (Vector3.new(Config.Sanctum.center.X, spot.Y, Config.Sanctum.center.Y) - spot).Unit
local side = toCenter:Cross(Vector3.yAxis)
hook:Invoke("set", player, { rebirths = 0, power = 0, aura = "" })
local stand = spot + toCenter * 7 + side * 3 + Vector3.new(0, 3, 0)
local function shot(from: Vector3, to: Vector3)
	character:PivotTo(CFrame.lookAt(stand, Vector3.new(spot.X, stand.Y, spot.Z)))
	hook:Invoke("ui", player, { command = "camera", arg = { from = from, to = to, seconds = 4 } })
	task.wait(4)
end
shot(spot + toCenter * 13 + Vector3.new(0, 7, 0), spot + Vector3.new(0, 6, 0))
shot(spot + toCenter * 7 - side * 11 + Vector3.new(0, 9, 0), spot + Vector3.new(0, 6, 0))
hook:Invoke("ui", player, { command = "wizardTalk" })
shot(spot + toCenter * 16 + side * 5 + Vector3.new(0, 6, 0), spot + toCenter * 3 + Vector3.new(0, 5, 0))
return "3 tomadas"
