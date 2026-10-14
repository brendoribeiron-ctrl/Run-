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

-- no mundo 1 as skills param em 30% do máximo; os rebirths do mundo 2 liberam o resto
local cap = Config.statCap("speed", 0)
hook:Invoke("set", player, { money = 1e12, stats = { speed = cap - 1 } })
check("no mundo 1 a skill vai até 30% do máximo", cap == math.ceil(Config.Stats.speed.max * 0.3) and hook:Invoke("buyStat", player, "speed") == true and state().stats.speed == cap, tostring(state().stats.speed))
check("e para aí", hook:Invoke("buyStat", player, "speed") == false and state().stats.speed == cap, tostring(state().stats.speed))

-- com os rebirths, mas longe dele: recusa
hook:Invoke("set", player, { rebirths = world.rebirths })
check("com os rebirths do mundo 2 a skill volta a subir", hook:Invoke("buyStat", player, "speed") == true and state().stats.speed == cap + 1, tostring(state().stats.speed))
hook:Invoke("set", player, { money = 0, stats = {} })
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
check("depois da corrida volta para a zona do vulcão", player:GetAttribute("World") == 2 and (where() - (zone + Config.Run.teleportOffset)).Magnitude < 8, tostring(where()))
check("o personagem entra na mochila", state().inventory[1] == id, tostring(state().inventory[1]))
-- o 1º rebirth pede a última parede do gramado (50K) e abre o vulcão; os seguintes seguem a
-- lista (250K, 500K, 1M...). As primeiras paredes daqui ficam abaixo do fim do mundo 1, porque o
-- jogador chega do rebirth com o Poder zerado.
local lava = world.walls
check("um rebirth aos 50K abre o vulcão", world.rebirths == 1 and Config.rebirthCost(0) == 50_000 and Config.Walls[#Config.Walls].power == 50_000, tostring(Config.rebirthCost(0)))
check("os rebirths seguintes pedem 250K, 500K, 1M", Config.rebirthCost(1) == 250_000 and Config.rebirthCost(2) == 500_000 and Config.rebirthCost(3) == 1_000_000, tostring(Config.rebirthCost(1)))
check("depois da lista o custo segue 1, 2, 5", Config.rebirthCost(8) == 50_000_000 and Config.rebirthCost(9) == 100_000_000 and Config.rebirthCost(11) == 500_000_000 and Config.rebirthCost(12) == 1_000_000_000, tostring(Config.rebirthCost(11)))
check("o vulcão começa abaixo do fim do mundo 1 e vai além", lava[1].power < 50_000 and lava[#lava].power > 50_000, tostring(lava[1].power))
hook:Invoke("goZone", player, "resetCooldown")
task.wait(0.3)
hook:Invoke("set", player, { power = lava[1].power - 1 })
hook:Invoke("runStart", player)
result = hook:Invoke("runRelease", player, 1)
check("sem o Poder da 1ª parede do vulcão não quebra nada", result ~= nil and result.broken == 0, tostring(result and result.broken))
hook:Invoke("runFinish", player)

-- o terreno do vulcão é espelho do do gramado: mesmo saco, mesmos pedestais, mesma coleta
local plotId = hook:Invoke("plot", player)
local meadowPlot = workspace.Plots["Plot" .. plotId]
local lavaPlot = workspace:WaitForChild(world.plots, 10)["Plot" .. plotId]
local lavaOrigin = lavaPlot:GetAttribute("Origin") :: CFrame
check("o vulcão tem o terreno do jogador", lavaPlot ~= nil and (lavaOrigin.Position - ((meadowPlot:GetAttribute("Origin") :: CFrame).Position + world.offset)).Magnitude < 0.1, tostring(lavaOrigin.Position))
check("a placa do terreno do vulcão tem o nome dele", string.find(lavaPlot.NameSign.Board.Text.Text, player.DisplayName, 1, true) ~= nil, lavaPlot.NameSign.Board.Text.Text)
local lavaBag = lavaPlot.Gantry.Bag:GetAttribute("Center") :: Vector3
character = player.Character :: Model
character:PivotTo(CFrame.new(lavaBag + Vector3.new(6, -4, 0)))
task.wait(0.6)
check("o terraço segura o boneco", math.abs(where().Y - (Config.World.groundY + 3.4)) < 1.6, tostring(where().Y))
hook:Invoke("set", player, { power = 0, money = 1_000_000, bagLevel = 1 })
check("soca o saco do vulcão", (hook:Invoke("hit", player, "noCrit") or 0) > 0 and state().power > 0, tostring(state().power))
check("melhora o saco pelo vulcão", hook:Invoke("upgradeBag", player) == true and state().bagLevel == 2, tostring(state().bagLevel))
check("os dois sacos mostram o nível novo", lavaPlot.Gantry.Sign:FindFirstChildOfClass("SurfaceGui").Title.Text == "BAG Lv 2" and meadowPlot.Gantry.Sign:FindFirstChildOfClass("SurfaceGui").Title.Text == "BAG Lv 2", lavaPlot.Gantry.Sign:FindFirstChildOfClass("SurfaceGui").Title.Text)
hook:Invoke("set", player, { inventory = { id }, pedestals = {}, stored = {} })
player:SetAttribute("Selected", 1)
check("coloca o personagem no pedestal do vulcão", hook:Invoke("pedestal", player, 1) == "placed" and state().pedestals["1"].id == id, tostring(state().pedestals["1"]))
task.wait(0.3)
check("o personagem aparece nos dois terrenos", lavaPlot.Pedestal1:FindFirstChild("Character") ~= nil and meadowPlot.Pedestal1:FindFirstChild("Character") ~= nil, "falta numa das cópias")
check("o do vulcão está no terraço", (lavaPlot.Pedestal1.Character:GetPivot().Position - lavaOrigin.Position).Magnitude < 60, tostring(lavaPlot.Pedestal1.Character:GetPivot().Position))
hook:Invoke("tick", player)
hook:Invoke("tick", player)
task.wait(0.2)
local shown = lavaPlot.Collect.Gui.Amount.Text
check("a renda aparece nos dois botões de coleta", shown ~= "$0" and shown == meadowPlot.Collect.Gui.Amount.Text, shown)
local before = state().money
check("coleta pelo vulcão", hook:Invoke("collect", player) > 0 and state().money > before and lavaPlot.Collect.Gui.Amount.Text == "$0" and meadowPlot.Collect.Gui.Amount.Text == "$0", tostring(state().money))
check("sobe o nível pelo vulcão", hook:Invoke("fighterUp", player, 1) == true and state().levels[id] == 2, tostring(state().levels[id]))
check("recolhe pelo vulcão e some dos dois", hook:Invoke("pedestal", player, 1) == "picked" and lavaPlot.Pedestal1:FindFirstChild("Character") == nil and meadowPlot.Pedestal1:FindFirstChild("Character") == nil, "ficou numa das cópias")
-- cair do mapa no vulcão devolve para o terreno de lá
character:PivotTo(CFrame.new(lavaBag + Vector3.new(0, -80, 0)))
task.wait(2.5)
check("quem cai no vulcão volta para o terreno de lá", player:GetAttribute("World") == 2 and (where() - lavaOrigin.Position).Magnitude < 60, tostring(where()))

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
