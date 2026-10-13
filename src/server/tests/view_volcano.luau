-- Passeio de câmera pelo feiticeiro e pelo vulcão, para captura (4 s por tomada).
--   node tools/bridge.cjs run server src/server/tests/view_volcano.luau 120000
--   powershell -File tools\screenshot.ps1 -Out shots\volcano\v.png -Count 9 -IntervalMs 4000 -DelayMs 3000
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
workspace:WaitForChild("Volcano", 90)
local sanctum = workspace:WaitForChild("Sanctum", 90)
sanctum:WaitForChild("Wizard", 30)

local SECONDS = 4
local G = Config.World.groundY
local function shot(stand: Vector3, from: Vector3, to: Vector3)
	character:PivotTo(CFrame.new(stand))
	hook:Invoke("ui", player, { command = "camera", arg = { from = from, to = to, seconds = SECONDS } })
	task.wait(SECONDS)
end

-- 1 e 2: o feiticeiro, de frente, e a conversa aberta
local spot = hook:Invoke("wizard", player)
local toCenter = (Vector3.new(Config.Sanctum.center.X, spot.Y, Config.Sanctum.center.Y) - spot).Unit
hook:Invoke("set", player, { rebirths = 0, power = 0, aura = "" })
shot(spot + toCenter * 7 + Vector3.new(4, 3, 0), spot + toCenter * 17 + Vector3.new(-3, 8, 0), spot + Vector3.new(0, 6.5, 0))
hook:Invoke("ui", player, { command = "wizardTalk" })
shot(spot + toCenter * 7 + Vector3.new(4, 3, 0), spot + toCenter * 15 + Vector3.new(6, 6, 0), spot + Vector3.new(0, 6, 0))

-- vai para o vulcão do jeito de verdade
hook:Invoke("set", player, { rebirths = Config.Worlds[2].rebirths })
character:PivotTo(CFrame.new(spot + toCenter * 6 + Vector3.new(0, 3, 0)))
task.wait(0.3)
hook:Invoke("travel", player, 2)
task.wait(3)

local O = Config.Worlds[2].offset
local island = O + Config.Volcano.islandCenter + Vector3.new(0, G, 0)
local zone = Config.zoneCenter(Config.Worlds[2])
-- 3: a ilha do alto; 4: o portão visto da praça; 5: o portal de volta; 6: a ilha de dentro
shot(island + Vector3.new(0, 4, 20), island + Vector3.new(-90, 120, 150), island + Vector3.new(0, 0, -30))
shot(island + Vector3.new(0, 4, -30), island + Vector3.new(8, 9, -10), island + Vector3.new(0, 30, -90))
shot(island + Vector3.new(0, 4, 35), island + Vector3.new(16, 8, 22), island + Vector3.new(0, 9, 62))
shot(island + Vector3.new(30, 4, 20), island + Vector3.new(50, 14, 40), island + Vector3.new(0, 8, -10))
-- 7: a zona de carga e a entrada da pista; 8: dentro da pista, com parede; 9: mais fundo
shot(zone + Vector3.new(0, 4, 4), zone + Vector3.new(6, 9, 26), zone + Vector3.new(0, 10, -60))
shot(zone + Vector3.new(0, 4, -75), zone + Vector3.new(4, 8, -55), zone + Vector3.new(0, 10, -160))
shot(zone + Vector3.new(0, 4, -560), zone + Vector3.new(-12, 22, -520), zone + Vector3.new(4, 4, -640))
hook:Invoke("travel", player, 1)
hook:Invoke("reset", player)
return "9 tomadas"
