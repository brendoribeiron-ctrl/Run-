-- Passeio de câmera pelo corredor para capturas: fachada, teto, entrada e fim. Cada vista fica
-- parada 4 segundos; o boneco vai junto para o mapa carregar em volta (streaming).
--   node tools/bridge.cjs run server src/server/tests/view.luau 60000
--   powershell -File tools\screenshot.ps1 -Out shots\view.png -Count 5 -IntervalMs 5000 -DelayMs 3500

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()

local run = Config.Run
local lawnEdge = -Config.World.lawnSize.Y / 2
local endZ = run.zoneCenter.Z - Config.Walls[#Config.Walls].distance / run.metersPerStud - run.endPadding

local shots = {
	{ Vector3.new(0, 22, lawnEdge + 95), Vector3.new(0, 36, lawnEdge) }, -- fachada de frente
	{ Vector3.new(60, 14, lawnEdge + 50), Vector3.new(0, 32, lawnEdge - 3) }, -- fachada de lado
	{ Vector3.new(30, 150, lawnEdge + 70), Vector3.new(0, 50, lawnEdge - 120) }, -- teto, de cima
	{ Vector3.new(0, 9, lawnEdge + 8), Vector3.new(0, 16, lawnEdge - 60) }, -- entrada, por dentro
	{ Vector3.new(-6, 14, endZ + 52), Vector3.new(8, 12, endZ) }, -- fim do corredor, depois da última parede
}
local character = player.Character or player.CharacterAdded:Wait()
for _, shot in shots do
	character:PivotTo(CFrame.new(shot[2].X, Config.World.groundY + 4, math.max(shot[2].Z, endZ + 20) + 12))
	hook:Invoke("ui", player, { command = "camera", arg = { from = shot[1], to = shot[2], seconds = 5 } })
	task.wait(5)
end
return #shots .. " vistas"
