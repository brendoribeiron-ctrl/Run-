-- Passeio de câmera pelo terraço dos terrenos do vulcão, para captura (4 s por tomada).
--   node tools/bridge.cjs run server src/server/tests/view_terrace.luau 90000
--   powershell -File tools\screenshot.ps1 -Out shots\volcano\t.png -Count 4 -IntervalMs 4000 -DelayMs 8500
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
workspace:WaitForChild("Volcano", 90):WaitForChild("volcano_terrace", 60)
workspace:WaitForChild("Sanctum", 90):WaitForChild("Wizard", 30)

local world = Config.Worlds[2]
local spot = hook:Invoke("wizard", player)
hook:Invoke("reset", player)
task.wait(0.5)
-- três personagens de magma nos pedestais, para o terreno não aparecer vazio
local ids = { "rookie_jabber_magma", "frost_hook_magma", "void_emperor_magma" }
hook:Invoke("set", player, { rebirths = world.rebirths, power = 0, aura = "", inventory = ids })
for slot = 1, 3 do
	player:SetAttribute("Selected", 1)
	hook:Invoke("pedestal", player, slot)
end
character = player.Character :: Model
character:PivotTo(CFrame.new(spot + Vector3.new(-7, 4, -7)))
task.wait(0.4)
assert(hook:Invoke("travel", player, 2) == true, "não viajou")
task.wait(3)

local G = Config.World.groundY
local plot = workspace[world.plots]["Plot" .. hook:Invoke("plot", player)]
local origin = (plot:GetAttribute("Origin") :: CFrame).Position
local terrace = world.offset + Vector3.new(0, G, Config.World.plotRowZ)
local function shot(stand: Vector3, from: Vector3, to: Vector3)
	character:PivotTo(CFrame.new(stand))
	hook:Invoke("ui", player, { command = "camera", arg = { from = from, to = to, seconds = 4 } })
	task.wait(4)
end
-- 1: o terraço inteiro, do alto; 2: o terreno do jogador; 3: de dentro dele; 4: a passagem e o portal
shot(terrace + Vector3.new(0, 4, -40), terrace + Vector3.new(-60, 110, -190), terrace + Vector3.new(0, 0, 10))
shot(origin + Vector3.new(0, 4, -30), origin + Vector3.new(26, 26, -62), origin + Vector3.new(0, 4, 4))
shot(origin + Vector3.new(-8, 4, -24), origin + Vector3.new(6, 9, -34), origin + Vector3.new(-14, 5, 2))
shot(terrace + Vector3.new(0, 4, -50), terrace + Vector3.new(24, 16, -34), terrace + Vector3.new(0, 8, -100))
hook:Invoke("travel", player, 1)
hook:Invoke("reset", player)
return "4 tomadas"
