-- Fatia 1: terreno, saco e Poder. Roda no servidor do Play pela ponte:
--   node tools/bridge.cjs run server src/server/tests/slice1.luau 30000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
assert(hook, "TestHook ausente")

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
task.wait(1)

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end

local plotId = hook:Invoke("plot", player)
check("terreno atribuído", type(plotId) == "number" and player:GetAttribute("PlotId") == plotId, tostring(plotId))

local plot = workspace.Plots["Plot" .. plotId]
local origin = plot:GetAttribute("Origin")
local bagCenter = plot.Gantry.Bag:GetAttribute("Center")
local sign = plot.NameSign.Board.Text.Text
check("placa com o nome", string.find(sign, player.DisplayName, 1, true) ~= nil, sign)

hook:Invoke("set", player, { power = 0, money = 0, bagLevel = 1 })
check("nasce ao alcance do saco", (root.Position - bagCenter).Magnitude < Config.Bag.hitRange + 6, tostring(root.Position))

local gain = hook:Invoke("hit", player, "noCrit")
check("soco dá o poder do nível 1", gain == Config.Bag.levels[1].power, tostring(gain))
check("atributo Power replica", player:GetAttribute("Power") == gain, tostring(player:GetAttribute("Power")))

local second = hook:Invoke("hit", player, "keepCooldown")
check("intervalo entre socos é respeitado", second == nil, tostring(second))

hook:Invoke("set", player, { bagLevel = 3 })
check("nível do saco muda o ganho", hook:Invoke("hit", player, "noCrit") == Config.Bag.levels[3].power, "nível 3")

local home = character:GetPivot()
character:PivotTo(origin * CFrame.new(0, 4, 30))
task.wait(0.2)
check("longe do saco não conta", hook:Invoke("hit", player, "noCrit") == nil, "a 30 studs")
character:PivotTo(home)

hook:Invoke("set", player, { power = 0, bagLevel = 1 })
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
