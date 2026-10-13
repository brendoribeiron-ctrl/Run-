-- Uma corrida de verdade (encenada pelo cliente) na pista do vulcão, para captura e conferência.
--   node tools/bridge.cjs run server src/server/tests/fx_volcano.luau 60000
--   powershell -File tools\screenshot.ps1 -Out shots\volcano\run.png -Count 8 -IntervalMs 700 -DelayMs 5500
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
workspace:WaitForChild("Volcano", 90)
workspace:WaitForChild("Sanctum", 90):WaitForChild("Wizard", 30)

local world = Config.Worlds[2]
local spot = hook:Invoke("wizard", player)
hook:Invoke("reset", player)
task.wait(0.5)
hook:Invoke("set", player, { rebirths = world.rebirths, power = world.walls[5].power, aura = "solar", inventory = {} })
character = player.Character :: Model
character:PivotTo(CFrame.new(spot + Vector3.new(-7, 4, -7)))
task.wait(0.4)
assert(hook:Invoke("travel", player, 2) == true, "não viajou")
task.wait(2.5)
assert(hook:Invoke("goZone", player, "resetCooldown") == true, "não foi à zona")
task.wait(1)
hook:Invoke("ui", player, { command = "charge", arg = Config.Run.chargeTime + 0.3 })
-- carga + corrida até a 6ª parede (que não quebra) + volta
local studs = world.walls[6].distance / Config.Run.metersPerStud
task.wait(Config.Run.chargeTime + 0.3 + studs / Config.Run.speed + 0.6)
local at = character:GetPivot().Position
local zone = Config.zoneCenter(world)
local ran = zone.Z - at.Z
task.wait(Config.Run.returnDelay + 4)
local inventory = hook:Invoke("state", player).inventory
local home = (character:GetPivot().Position - (world.offset + Config.Volcano.arrive)).Magnitude
assert(math.abs(at.X - zone.X) < 12 and ran > studs - 40, `o boneco não correu pela pista do vulcão: {at}`)
assert(#inventory == 1 and string.sub(inventory[1], -#world.suffix) == world.suffix, "sem personagem de magma: " .. tostring(inventory[1]))
assert(home < 14, "não voltou para a ilha: " .. tostring(character:GetPivot().Position))
hook:Invoke("travel", player, 1)
hook:Invoke("reset", player)
return `correu {math.floor(ran)} studs no vulcão, ganhou {inventory[1]}, voltou para a ilha`
