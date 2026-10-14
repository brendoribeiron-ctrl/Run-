-- Aura em movimento (parada, andando com a câmera acompanhando de lado e de frente, correndo
-- no corredor), a árvore de skills e o botão de coleta, para captura.
--   node tools/bridge.cjs run server src/server/tests/view_flight.luau 90000
--   powershell -File tools\screenshot.ps1 -Out shots\flight\f.png -Count 30 -IntervalMs 1000 -DelayMs 1500
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local aura = "solar"

local function ui(command: string, arg: any): any
	return hook:Invoke("ui", player, { command = command, arg = arg })
end

hook:Invoke("reset", player)
task.wait(0.5)
hook:Invoke("set", player, { aura = aura, power = Config.AuraFx.fullPower, money = 2_000, stats = { speed = 3, critChance = 2, critDamage = 0 } })
character = player.Character :: Model
local at = Vector3.new(-150, Config.World.groundY + 4, 60)
character:PivotTo(CFrame.new(at))
task.wait(0.6)

-- 1: parada (2 s)
ui("camera", { follow = true, from = Vector3.new(0, 4.5, 17), to = Vector3.new(0, 1, 0), seconds = 2 })
task.wait(2)
local idle = ui("auraState")

-- 2: andando para +X, câmera de lado acompanhando (3 s); depois dá meia-volta (3 s)
ui("camera", { follow = true, from = Vector3.new(-3, 5, 22), to = Vector3.new(-3, 1.5, 0), seconds = 6 })
ui("walk", { direction = Vector3.new(1, 0, 0), seconds = 3 })
task.wait(2)
local walking = ui("auraState")
task.wait(1)
ui("walk", { direction = Vector3.new(-1, 0, 0), seconds = 3 })
task.wait(3)

-- 3: andando para +X com a câmera na frente, de três quartos (3 s)
ui("camera", { follow = true, from = Vector3.new(16, 6, 14), to = Vector3.new(-2, 1.5, 0), seconds = 3 })
ui("walk", { direction = Vector3.new(1, 0, 0), seconds = 3 })
task.wait(3.3)

-- 4: a árvore de skills (4 s)
ui("toggle", "Skills")
task.wait(2.5)
ui("skillsFocus", "critDamage")
task.wait(2.5)
ui("toggle", "Skills")
task.wait(0.8)

-- 5: o botão de coleta do terreno, de cima, dos dois lados compridos (2 s cada)
local plot = workspace[Config.Worlds[1].plots]["Plot" .. hook:Invoke("plot", player)]
local pad = plot.Collect
local spot = pad.Position
character:PivotTo(CFrame.new(spot + Vector3.new(0, 4, 12)))
task.wait(0.3)
for _, side in { -1, 1 } do
	ui("camera", { from = pad.CFrame:PointToWorldSpace(Vector3.new(side * 13, 9, 0)), to = spot, seconds = 2 })
	task.wait(2)
end

-- 6: corrida de verdade no corredor, com a câmera do jogo
assert(hook:Invoke("goZone", player, "resetCooldown") == true, "não foi à zona")
task.wait(1)
ui("charge", Config.Run.chargeTime + 0.3)
task.wait(Config.Run.chargeTime + 2.5)
local racing = ui("auraState")
task.wait(6)
hook:Invoke("reset", player)
return string.format("parada %.2f (rastro %s, vida %.2f) | andando %.2f (rastro %s, vida %.2f) | correndo %.2f (rastro %s, vida %.2f, livre %.2f)", idle.flight, tostring(idle.comet), idle.flameLife, walking.flight, tostring(walking.comet), walking.flameLife, racing.flight, tostring(racing.comet), racing.flameLife, racing.clear)
