-- Sala do chefe: as duas salas montadas, quem limpa o corredor vai para a sala do mundo dele, o
-- piso segura, a saída leva de volta à zona e quem não limpa volta para a zona como sempre.
--   node tools/bridge.cjs run server src/server/tests/boss.luau 90000
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local passed = {}
local function check(name: string, ok: boolean, detail: string?)
	assert(ok, "FALHOU: " .. name .. " (" .. tostring(detail) .. ")")
	table.insert(passed, name)
end
local function where(): Vector3
	return (player.Character :: Model):GetPivot().Position
end

local rooms = {}
for _, world in Config.Worlds do
	rooms[world.id] = workspace:WaitForChild("BossRoom" .. world.id, 60)
end
check("cada mundo tem a sala dele", rooms[1] ~= nil and rooms[2] ~= nil, "pastas")
local model = rooms[1]:WaitForChild("boss_room", 60)
check("o modelo da sala carregou", model ~= nil and #model:GetChildren() > 10, tostring(model and #model:GetChildren()))
local _, size = model:GetBoundingBox()
local K = Config.BossRoom.scale
check("a sala tem o tamanho certo (2x o modelo)", K >= 2 and math.abs(size.X - (Config.BossRoom.radius + 4) * 2 * K) < 12 and size.Y > Config.BossRoom.wallHeight * K, tostring(size))
local doors = model:FindFirstChild("DoorL_boss_room") and model:FindFirstChild("DoorR_boss_room") and model:FindFirstChild("DoorLGold_boss_room")
check("as folhas da porta vêm separadas", doors ~= nil, "portas")
local solid = 0
for _, p in model:GetDescendants() do
	if p:IsA("BasePart") and p.CanCollide then
		solid += 1
	end
end
check("do modelo, só o piso e a cúpula colidem (para segurar a câmera)", solid == 2 and #rooms[1].Colliders:GetChildren() > 20, tostring(solid))
check("as duas salas têm cores diferentes", rooms[2]:WaitForChild("boss_room", 60) ~= nil and rooms[2].boss_room.Stone_boss_room.Color ~= model.Stone_boss_room.Color, "cores")

-- corrida que não limpa: volta para a zona
hook:Invoke("reset", player)
task.wait(0.5)
local world = Config.Worlds[1]
local walls = world.walls
hook:Invoke("set", player, { power = walls[3].power })
hook:Invoke("goZone", player, "resetCooldown")
task.wait(0.3)
hook:Invoke("runStart", player)
local result = hook:Invoke("runRelease", player, 1)
hook:Invoke("runFinish", player)
local zone = Config.zoneCenter(world)
check("quem não limpa volta para a zona", result.broken < #walls and (where() - (zone + Config.Run.teleportOffset)).Magnitude < 8 and player:GetAttribute("Room") == nil, tostring(where()))

-- corrida que limpa: vai para a sala
local owned = #hook:Invoke("state", player).inventory
hook:Invoke("set", player, { power = walls[#walls].power * 2 })
hook:Invoke("goZone", player, "resetCooldown")
task.wait(0.3)
hook:Invoke("runStart", player)
result = hook:Invoke("runRelease", player, 1)
hook:Invoke("runFinish", player)
local center = Config.BossRoom.center + world.offset
local entry = center + Vector3.new(0, 3, Config.BossRoom.entry * K)
check("quem limpa o corredor vai para a sala do chefe", result.broken == #walls and (where() - entry).Magnitude < 8 and player:GetAttribute("Room") == 1, tostring(where()))
check("limpar o corredor não sorteia na hora", result.characterId == "" and #hook:Invoke("state", player).inventory == owned and player:GetAttribute("BossReward") == true, tostring(result.characterId))
task.wait(1.5)
check("o piso da sala segura o boneco", math.abs(where().Y - entry.Y) < 3, tostring(where()))
-- a câmera para em peça que colide e é quase opaca: em volta da sala não pode haver fresta
local params = RaycastParams.new()
params.FilterDescendantsInstances = { player.Character :: Model }
params.FilterType = Enum.RaycastFilterType.Exclude
local function blocks(hit: RaycastResult?): boolean
	return hit ~= nil and hit.Instance.CanCollide and hit.Instance.Transparency < 0.25
end
-- como a câmera faz: atravessa o que não a segura e segue até o primeiro que segura
local function cameraRay(origin: Vector3, direction: Vector3): RaycastResult?
	local skip: { Instance } = { player.Character :: Model }
	for _ = 1, 20 do
		local p = RaycastParams.new()
		p.FilterDescendantsInstances = skip
		p.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(origin, direction, p)
		if not hit or blocks(hit) then
			return hit
		end
		table.insert(skip, hit.Instance)
	end
	return nil
end
local blockers = 0
for i = 0, 15 do
	local angle = i * 2 * math.pi / 16 + 0.1
	if blocks(cameraRay(center + Vector3.new(0, 20, 0), Vector3.new(math.sin(angle), 0.15, math.cos(angle)) * 400)) then
		blockers += 1
	end
end
check("em todas as direções a parede segura a câmera", blockers == 16, tostring(blockers))
-- ninguém entra na parede: a colisão começa logo atrás da face de dentro dela
local inner = Config.BossRoom.radius * K
local deepest = 0
for i = 0, 31 do
	local angle = i * 2 * math.pi / 32 + 0.05
	local hit = workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(math.sin(angle), 0, math.cos(angle)) * 400, params)
	if hit then
		deepest = math.max(deepest, (Vector3.new(hit.Position.X, center.Y, hit.Position.Z) - center).Magnitude)
	else
		deepest = math.huge
	end
end
-- cada vão é reto: no canto a face fica mais longe do centro (raio / cos de meio vão)
check("ninguém entra na parede", deepest <= (inner + 0.8) / math.cos(math.pi / 16), tostring(deepest))
local seat = workspace:Raycast(center + Vector3.new(0, 30 * K, -44 * K), Vector3.new(0, -40 * K, 0), params)
check("o trono é sólido", seat ~= nil and seat.Instance.Name == "Throne" and seat.Position.Y > center.Y + 5 * K, seat and seat.Instance.Name or "nada")
check("para cima a cúpula segura a câmera", blocks(cameraRay(center + Vector3.new(0, 20, 0), Vector3.new(0.3, 1, 0.2) * 400)), "cúpula")
check("embaixo o piso segura a câmera", blocks(workspace:Raycast(entry + Vector3.new(0, 4, 0), Vector3.new(0.2, -1, 0) * 50, params)), "piso")
check("a saída fica na porta, na altura do chão", rooms[1].Exit:FindFirstChild("LeaveRoom") ~= nil and rooms[1].Exit.Position.Y - center.Y < 6, tostring(rooms[1].Exit.Position.Y - center.Y))
-- ninguém sobe nos pilares, na parede ou na cúpula: um teto invisível na altura dos pilares
local roof = workspace:Raycast(center + Vector3.new(30, 10, 30), Vector3.new(0, 300, 0), params)
check("um teto invisível fecha a sala na altura dos pilares", roof ~= nil and roof.Instance.Name == "Lid" and roof.Position.Y - center.Y <= 46 * K + 1, roof and roof.Instance.Name or "nada")
-- o véu de fora cobre a abertura da porta de qualquer ângulo
local veil = rooms[1].Veil
check("o véu da porta é opaco e maior que a abertura", veil.Transparency == 0 and veil.Size.X > 16 * K + 8 and veil.Position.Z > center.Z + Config.BossRoom.radius * K, tostring(veil.Size))
check("o sorteio vem com a vitória contra o chefe", hook:Invoke("bossWin", player) == true and #hook:Invoke("state", player).inventory == owned + 1 and player:GetAttribute("BossReward") == nil, "sorteio")
check("só um sorteio por corredor limpo", hook:Invoke("bossWin", player) == false and #hook:Invoke("state", player).inventory == owned + 1, "sorteou de novo")
check("sair leva de volta à zona", hook:Invoke("leaveRoom", player) == true and (where() - (zone + Config.Run.teleportOffset)).Magnitude < 8 and player:GetAttribute("Room") == nil, tostring(where()))
check("fora da sala, sair não faz nada", hook:Invoke("leaveRoom", player) == false, "saiu de novo")

hook:Invoke("reset", player)
return #passed .. " verificações OK: " .. table.concat(passed, "; ")
