-- Mundos: o feiticeiro barra quem não tem os rebirths, deixa passar quem tem; no vulcão a corrida
-- usa as paredes de lá e sorteia personagens de magma; o portal traz de volta.
--   node tools/bridge.cjs run server src/server/tests/worlds.luau 120000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
assert(hook, "TestHook ausente")

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")
task.wait(1)

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function state()
	return hook:Invoke("state", player)
end
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command, arg = arg })
end
local function where(): Vector3
	return (player.Character :: Model):GetPivot().Position
end

local volcano = workspace:WaitForChild("Volcano", 90)
local hallway = workspace:WaitForChild("VolcanoHallway", 10)
local sanctum = workspace:WaitForChild("Sanctum", 90)
assert(volcano and hallway and sanctum, "o vulcão ou a casa não apareceram")
local wizard = sanctum:WaitForChild("Wizard", 30)
check("o feiticeiro está na casa", wizard ~= nil and sanctum:FindFirstChild("WizardBody") ~= nil, "sem Wizard")

local world = Config.Worlds[2]
local track = volcano:FindFirstChild("Track")
check("os modelos do vulcão carregaram", volcano:FindFirstChild("volcano_base") ~= nil and track ~= nil and volcano:FindFirstChild("volcano_mount") ~= nil and volcano:FindFirstChild("volcano_spire") ~= nil, "falta modelo")
local segments = 0
for _, child in track:GetChildren() do
	if child:IsA("Model") then
		segments += 1
	end
end
local zone = Config.zoneCenter(world)
local endZ = zone.Z - world.walls[#world.walls].distance / Config.Run.metersPerStud - Config.Run.endPadding
check("a pista cobre todas as paredes", segments * Config.Volcano.segment >= world.offset.Z + Config.Volcano.gateZ - endZ, `{segments} trechos`)
local walls = hallway:FindFirstChild("Walls")
check("o vulcão tem as paredes dele", walls ~= nil and #walls:GetChildren() == #world.walls, "paredes")
for _, part in volcano:GetDescendants() do
	if part:IsA("BasePart") and part.Parent.Name ~= "Colliders" and part.Name ~= "LavaSea" then
		assert(part.Anchored and not part.CanCollide, "peça de enfeite colide: " .. part:GetFullName())
	end
end
table.insert(passed, "só as peças de colisão colidem")

-- sem rebirths: o feiticeiro despreza e o servidor recusa
hook:Invoke("reset", player)
task.wait(0.5)
local spot = hook:Invoke("wizard", player)
check("o servidor sabe onde o feiticeiro está", typeof(spot) == "Vector3", tostring(spot))
local _, wizardSize = wizard:GetBoundingBox()
local wizardAt = (wizard:GetAttribute("Home") :: CFrame).Position
check("o modelo do feiticeiro está no lugar e no tamanho", Vector2.new(wizardAt.X - spot.X, wizardAt.Z - spot.Z).Magnitude < 1 and math.abs(wizardSize.Y - Config.Wizard.height) < 1.5 and wizardSize.X < 9, `{wizardAt} x {spot}, tamanho {wizardSize}`)
local facing = (wizard:GetAttribute("Home") :: CFrame).LookVector
local center = Vector3.new(Config.Sanctum.center.X, spot.Y, Config.Sanctum.center.Y)
check("o feiticeiro olha para o centro do salão", facing:Dot((center - spot).Unit) > 0.95, tostring(facing))
character = player.Character :: Model
character:PivotTo(CFrame.new(spot + Vector3.new(-7, 4, -7)))
task.wait(0.4)
local talk = ui("wizardTalk")
check("sem rebirths ele diz que o jogador não é digno", talk.open and not talk.travel and not talk.worthy and string.find(talk.text, "not worthy") ~= nil, talk.text)
check("sem rebirths o servidor recusa a viagem", hook:Invoke("travel", player, 2) == false and player:GetAttribute("World") == 1, tostring(player:GetAttribute("World")))

-- com os rebirths, mas longe dele: recusa
hook:Invoke("set", player, { rebirths = world.rebirths })
task.wait(0.3)
character:PivotTo(CFrame.new(spot + Vector3.new(0, 4, 120)))
task.wait(0.3)
check("longe do feiticeiro o servidor recusa", hook:Invoke("travel", player, 2) == false, "viajou de longe")

-- perto e digno: a conversa oferece a viagem e o botão leva ao vulcão
character:PivotTo(CFrame.new(spot + Vector3.new(-7, 4, -7)))
task.wait(0.4)
talk = ui("wizardTalk")
check("com os rebirths ele oferece a viagem", talk.open and talk.travel and talk.worthy, talk.text)
ui("wizardAccept")
task.wait(2.5)
local arrive = world.offset + Config.Volcano.arrive
check("o botão leva ao vulcão", player:GetAttribute("World") == 2 and (where() - arrive).Magnitude < 12, tostring(where()))
check("o cliente sabe que está no vulcão", ui("worldState").world == 2 and not ui("worldState").open, tostring(ui("worldState").world))
task.wait(1)
check("o chão da ilha segura o boneco", math.abs(where().Y - (Config.World.groundY + 3)) < 1.5, tostring(where().Y))

-- o botão CORRER leva à zona de carga do vulcão, e a corrida usa as paredes de lá
check("CORRER leva à zona do vulcão", hook:Invoke("goZone", player, "resetCooldown") == true, "recusou")
task.wait(0.4)
check("chegou na zona do vulcão", (where() - (zone + Config.Run.teleportOffset)).Magnitude < 6, tostring(where()))
hook:Invoke("set", player, { power = world.walls[3].power, inventory = {} })
check("carrega no vulcão", hook:Invoke("runStart", player) == true, "recusou")
local result = hook:Invoke("runRelease", player, 1)
check("quebra as paredes do vulcão pelo Poder", result ~= nil and result.broken == 3, tostring(result and result.broken))
local id = result.characterId
local info = Config.CharacterById[id]
check("sorteia um personagem de magma", string.sub(id, -#world.suffix) == world.suffix and info ~= nil and info.world == 2, id)
local plain = Config.CharacterById[string.sub(id, 1, #id - #world.suffix)]
check("o de magma rende mais", info.income == plain.income * world.incomeMultiplier and string.sub(info.name, 1, 6) == "Magma ", `{info.name} {info.income}`)
hook:Invoke("runFinish", player)
task.wait(0.4)
check("depois da corrida volta para a ilha", player:GetAttribute("World") == 2 and (where() - arrive).Magnitude < 12, tostring(where()))
check("o personagem entra na mochila", state().inventory[1] == id, tostring(state().inventory[1]))
-- com o Poder do fim do mundo 1 não quebra nada aqui
hook:Invoke("goZone", player, "resetCooldown")
task.wait(0.3)
hook:Invoke("set", player, { power = Config.Walls[#Config.Walls].power })
hook:Invoke("runStart", player)
result = hook:Invoke("runRelease", player, 1)
check("o Poder do mundo 1 não quebra parede do vulcão", result ~= nil and result.broken == 0, tostring(result and result.broken))
hook:Invoke("runFinish", player)

-- volta pelo portal (o cliente pede o mundo 1) e cai no próprio terreno
check("volta para o mundo 1", hook:Invoke("travel", player, 1) == true and player:GetAttribute("World") == 1, tostring(player:GetAttribute("World")))
task.wait(1.5)
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
check("cai no próprio terreno", (where() - (plot:GetAttribute("Origin") :: CFrame).Position).Magnitude < 60, tostring(where()))
check("o cliente voltou ao clima do gramado", ui("worldState").world == 1, tostring(ui("worldState").world))
-- fusão de magma: três iguais viram o Shiny de magma
hook:Invoke("set", player, { inventory = { id, id, id } })
local fused = hook:Invoke("progress", player, { action = "fuse", arg = 1 })
check("três de magma fundem num Shiny de magma", fused == id .. Config.Fusion.suffix and Config.CharacterById[fused].income == info.income * Config.Fusion.incomeMultiplier, tostring(fused))

hook:Invoke("reset", player)
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
