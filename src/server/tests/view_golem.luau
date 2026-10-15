-- Passeio de câmera pela luta com o golem, para captura: dormindo, o despertar (cena do
-- cliente), cada golpe visto de lado, a corrida e a morte.
--   node tools/bridge.cjs run server src/server/tests/view_golem.luau 200000
--   (junto) powershell -File tools\screenshot.ps1 -Out shots\golem\g.png -Count 120 -IntervalMs 250
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local S = Config.Boss.scale
local function boss(action: string, arg: any?): any
	return hook:Invoke("boss", player, { action = action, arg = arg, world = 1 })
end
local function ui(command: string, arg: any?): any
	return hook:Invoke("ui", player, { command = command, arg = arg })
end
local began = os.clock()
local log = {}
local function mark(name: string)
	table.insert(log, string.format("%.1f %s", os.clock() - began, name))
end

hook:Invoke("reset", player)
task.wait(0.5)
local world = Config.Worlds[1]
hook:Invoke("set", player, { power = world.walls[#world.walls].power * 2 })
hook:Invoke("goZone", player, "resetCooldown")
task.wait(0.3)
hook:Invoke("runStart", player)
hook:Invoke("runRelease", player, 1)
hook:Invoke("runFinish", player)
task.wait(Config.BossRoom.introTime + 1.5)
local humanoid = (player.Character :: Model):WaitForChild("Humanoid") :: Humanoid
humanoid.MaxHealth = 1e6
humanoid.Health = 1e6

local center = Config.BossRoom.center + world.offset
local function put(offset: Vector3)
	local state = boss("state")
	local at = (state.cframe * CFrame.new(offset)).Position
	local character = player.Character :: Model
	character:PivotTo(CFrame.lookAt(Vector3.new(at.X, center.Y + 3, at.Z), Vector3.new(state.position.X, center.Y + 3, state.position.Z)))
end
-- câmera de lado, relativa ao golem
local function shot(offset: Vector3, look: Vector3, seconds: number)
	local state = boss("state")
	local cf = state.cframe
	ui("camera", { from = (cf * CFrame.new(offset * S)).Position, to = (cf * CFrame.new(look * S)).Position, seconds = seconds })
end

-- 1. dormindo
mark("dormindo")
put(Vector3.new(0, 0, -40))
shot(Vector3.new(-26, 8, -34), Vector3.new(0, 10, 0), 2.5)
task.wait(2.5)

-- 2. desafio: a cena do despertar é do cliente
mark("despertar")
boss("challenge")
task.wait(Anims.clips.Wake.length + 0.8)

-- 3. golpes, de lado
local function attack(name: string, offset: Vector3, look: Vector3)
	boss("place", { position = center, yaw = math.pi, rest = 30 })
	put(Vector3.new(0, 0, -44))
	task.wait(0.4)
	shot(offset, look, Anims.clips[name].length + 0.8)
	mark(name)
	boss("attack", name)
	task.wait(Anims.clips[name].length + 0.8)
	boss("rest", 30)
end
attack("Stomp", Vector3.new(-44, 12, -30), Vector3.new(0, 8, -6))
attack("Sweep", Vector3.new(-40, 18, -44), Vector3.new(0, 8, -8))
attack("Slam", Vector3.new(-46, 12, -26), Vector3.new(0, 8, -8))
attack("Charge", Vector3.new(-48, 14, -30), Vector3.new(0, 10, -10))
attack("Pulse", Vector3.new(-50, 24, -10), Vector3.new(0, 4, -24))

-- 4. andando e correndo atrás do jogador
mark("anda")
boss("place", { position = center, yaw = math.pi, rest = 0 })
put(Vector3.new(0, 0, -30))
shot(Vector3.new(-40, 12, -20), Vector3.new(0, 10, 0), 2.5)
task.wait(2.5)
mark("corre")
boss("place", { position = center + Vector3.new(0, 0, -60), yaw = 0, rest = 0 })
put(Vector3.new(0, 0, -80))
ui("camera", { from = center + Vector3.new(-50, 18, -20), to = center + Vector3.new(0, 10, 0), seconds = 3 })
task.wait(3)

-- 5. raiva e morte
mark("morte")
boss("place", { position = center, yaw = math.pi, rest = 30 })
put(Vector3.new(0, 0, -(Config.Boss.radius + 5)))
shot(Vector3.new(-34, 10, -30), Vector3.new(0, 8, 0), 6.5)
task.wait(0.3)
boss("hp", 0)
task.wait(6.5)

humanoid.MaxHealth = 100
boss("reset")
hook:Invoke("leaveRoom", player)
hook:Invoke("reset", player)
return table.concat(log, " | ")
