-- EXPERIMENTOS (src/shared/GolemExperiment.luau): um golpe novo do golem, duas vezes seguidas (de
-- lado e de cima), para captura. Confere que o servidor toca o clip novo e mede o dano no jogador.
--   node tools/bridge.cjs run server src/server/tests/view_boss_v2.luau 120000 Slam
--   node tools/bridge.cjs run server src/server/tests/view_boss_v2.luau 120000 Charge
--   (junto) powershell -File tools\screenshot.ps1 -Out shots\v2\s.png -Count 70 -IntervalMs 40 -DelayMs 13000
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local Experiment = require(ReplicatedStorage.Shared.GolemExperiment)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local S = Config.Boss.scale
local args = HttpService:JSONDecode(script.Parent:GetAttribute("Args") or "[]")
local attack: string = args[1] or "Slam"
local function boss(action: string, arg: any?): any
	return hook:Invoke("boss", player, { action = action, arg = arg, world = 1 })
end
local function ui(command: string, arg: any?): any
	return hook:Invoke("ui", player, { command = command, arg = arg })
end
local began = os.clock()
local log = {}
local function mark(name: string)
	table.insert(log, string.format("%.2f %s", os.clock() - began, name))
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
-- sem regeneração, para medir o dano do golpe
local regen = (player.Character :: Model):FindFirstChild("Health")
if regen then
	regen:Destroy()
end

local center = (workspace:FindFirstChild(player:GetAttribute("RoomKey")) :: Folder):GetAttribute("Center") :: Vector3
local function put(offset: Vector3)
	local state = boss("state")
	local at = (state.cframe * CFrame.new(offset)).Position
	local character = player.Character :: Model
	character:PivotTo(CFrame.lookAt(Vector3.new(at.X, center.Y + 3, at.Z), Vector3.new(state.position.X, center.Y + 3, state.position.Z)))
end
local function shot(offset: Vector3, look: Vector3, seconds: number)
	local cf = boss("state").cframe
	ui("camera", { from = (cf * CFrame.new(offset * S)).Position, to = (cf * CFrame.new(look * S)).Position, seconds = seconds })
end

boss("challenge")
task.wait(Anims.clips.Wake.length + 0.8)

local clipName = Experiment.clipFor(attack)
local clip = Anims.clips[clipName]
local A = Config.Boss.attacks[attack]
-- onde o jogador fica: dentro da área do golpe (o gancho ainda avança `lunge` antes de acertar)
local reach = (A.ahead + (A.lunge or 0) + 2) * S
local function go(offset: Vector3, look: Vector3, label: string)
	boss("place", { position = center, yaw = math.pi, rest = 30 })
	put(Vector3.new(0, 0, -reach))
	task.wait(0.5)
	shot(offset, look, clip.length + 2.4)
	local before = humanoid.Health
	mark(label .. " começa")
	boss("attack", attack)
	task.wait(0.05)
	mark("clip " .. tostring(boss("state").clip))
	task.wait(clip.events.impact + 0.1)
	mark(string.format("dano %d", before - humanoid.Health))
	task.wait(clip.length - clip.events.impact - 0.05)
	boss("rest", 30) -- sem isto a IA emenda outro golpe e atrapalha a captura
	task.wait(2.3)
end
-- de lado, baixo, para ver o corpo e os espinhos
go(Vector3.new(-40, 9, -30), Vector3.new(0, 9, -10), "lado")
-- de cima e de frente, para ver a erupção correndo
go(Vector3.new(-22, 34, -52), Vector3.new(0, 2, -12), "cima")

humanoid.MaxHealth = 100
boss("reset")
hook:Invoke("leaveRoom", player)
hook:Invoke("reset", player)
return attack .. ": " .. table.concat(log, " | ")
