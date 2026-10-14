-- Corrida de verdade até limpar o corredor, a passagem pelo portal e a cinemática da sala, para
-- captura; depois um passeio de câmera pela sala do vulcão.
--   node tools/bridge.cjs run server src/server/tests/view_boss.luau 120000
--   powershell -File tools\screenshot.ps1 -Out shots\boss\b.png -Count 40 -IntervalMs 500 -DelayMs 2000
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
workspace:WaitForChild("BossRoom1", 60):WaitForChild("boss_room", 60)

local function ui(command: string, arg: any): any
	return hook:Invoke("ui", player, { command = command, arg = arg })
end

hook:Invoke("reset", player)
task.wait(0.5)
local walls = Config.Walls
hook:Invoke("set", player, { power = walls[#walls].power * 2, aura = "solar" })
assert(hook:Invoke("goZone", player, "resetCooldown") == true, "não foi à zona")
task.wait(1)
ui("charge", Config.Run.chargeTime + 0.3)
-- carga + corrida inteira + portal + espera + cinemática
local studs = walls[#walls].distance / Config.Run.metersPerStud
task.wait(Config.Run.chargeTime + 0.3 + studs / Config.Run.speed + Config.BossRoom.portalTime + 1.5)
local during = ui("bossState")
task.wait(Config.BossRoom.introTime + 1)
local after = ui("bossState")
hook:Invoke("bossWin", player) -- o sorteio que vem depois do chefe
task.wait(5)
local inside = player:GetAttribute("Room")

-- passeio: a sala do mundo 1 vista de alguns pontos (2 s cada)
local center = Config.BossRoom.center
local character = player.Character :: Model
for _, shot in {
	{ Vector3.new(0, 8, 40), Vector3.new(0, 10, -40) },
	{ Vector3.new(-30, 4, -10), Vector3.new(10, 20, -50) },
	{ Vector3.new(20, 3, 30), Vector3.new(-10, 50, -10) },
} do
	ui("camera", { from = center + shot[1] * Config.BossRoom.scale, to = center + shot[2] * Config.BossRoom.scale, seconds = 2 })
	task.wait(2)
end
hook:Invoke("leaveRoom", player)
hook:Invoke("reset", player)
return `durante: {during.phase} | depois: {after.phase}, portas {after.doors}, sala {inside}`
