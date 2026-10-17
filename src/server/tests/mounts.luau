-- Montarias: modelos prontos, compra com dinheiro, escolher no menu, subir e descer (tecla M), e o cliente mostrando
-- a montaria embaixo do boneco (que sobe um pouco). Também confere o limite de zoom da câmera.
--   node tools/bridge.cjs run server src/server/tests/mounts.luau 90000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function state()
	return hook:Invoke("state", player)
end
local function client()
	return hook:Invoke("ui", player, { command = "mountState" })
end

local folder = ReplicatedStorage:WaitForChild("Mounts", 60)
check("modelos carregaram", folder ~= nil and #folder:GetChildren() == #Config.Mounts, folder and tostring(#folder:GetChildren()))
for _, info in Config.Mounts do
	local model = folder[info.id]
	local _, size = model:GetBoundingBox()
	local parts, segments, markers = 0, 0, 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			parts += 1
			segments = math.max(segments, part:GetAttribute("Segment") or 0)
			if string.match(part.Name, "^Pivot") then
				markers += 1
			end
			assert(part.Anchored and not part.CanCollide, part.Name .. " solto ou colidindo")
		end
	end
	check(info.id .. " no tamanho certo", math.abs(math.max(size.X, size.Z) - info.length) < 0.6 and size.Y < 3, tostring(size))
	check(info.id .. " sem o marcador", markers == 0 and parts >= 5, `{parts} peças`)
	if info.id == "carpet" then
		check("tapete tem 7 gomos", segments == 7, tostring(segments))
	end
end

check("zoom máximo limitado", player.CameraMaxZoomDistance == Config.Camera.maxZoom, tostring(player.CameraMaxZoomDistance))

-- compra e uso
local board, carpet = Config.Mounts[1], Config.Mounts[2]
hook:Invoke("set", player, { money = board.price - 1, mounts = {}, mount = "" })
check("sem dinheiro não compra", hook:Invoke("mount", player, board.id) == nil and state().mount == "", "comprou")
check("montaria inexistente recusa", hook:Invoke("mount", player, "dragon") == nil, "dragon")
hook:Invoke("set", player, { money = board.price })
check("compra e já sobe", hook:Invoke("mount", player, board.id) == "bought" and state().mount == board.id and state().money == 0, tostring(state().money))
check("atributos replicam", player:GetAttribute("Mount") == board.id and player:GetAttribute("Mounts") == board.id, tostring(player:GetAttribute("Mounts")))
task.wait(1.2)
local riding = client()
check("cliente mostra o skate", riding.id == board.id and riding.shown and riding.pieces >= 5, `{riding.id} {riding.shown}`)
check("o boneco sobe", math.abs(riding.hip - riding.baseHip - board.lift) < 0.05, `{riding.hip} / {riding.baseHip}`)
local feet = root.Position.Y - root.Size.Y / 2 - riding.baseHip
check("o skate fica embaixo dos pés", math.abs(riding.height - feet) < 0.6 and feet > Config.World.groundY + 1, `skate {riding.height}, pés {feet}`)

check("clicar de novo continua escolhida e montado", hook:Invoke("mount", player, board.id) == "selected" and state().mount == board.id and player:GetAttribute("Riding") == true, state().mount)
check("M desce", hook:Invoke("ride", player) == false and player:GetAttribute("Riding") == nil and state().mount == board.id, tostring(player:GetAttribute("Riding")))
task.wait(0.8)
local walking = client()
check("a pé volta à altura normal", walking.id == "" and math.abs(walking.hip - walking.baseHip) < 0.05, `{walking.hip}`)
check("M sobe de novo", hook:Invoke("ride", player) == true and player:GetAttribute("Riding") == true, "")
hook:Invoke("ride", player)
check("não cobra duas vezes", hook:Invoke("mount", player, board.id) == "selected" and state().money == 0, tostring(state().money))

hook:Invoke("set", player, { money = carpet.price })
check("compra o tapete, troca e sobe", hook:Invoke("mount", player, carpet.id) == "bought" and state().mount == carpet.id and state().mounts[board.id] == true and player:GetAttribute("Riding") == true, state().mount)
task.wait(1.2)
local flying = client()
check("cliente mostra o tapete", flying.id == carpet.id and flying.shown and flying.segments == 7, `{flying.id} {flying.segments}`)

-- some durante a corrida no corredor
player:SetAttribute("Racing", true)
task.wait(0.5)
check("some na corrida", client().shown == false, "ainda aparece")
player:SetAttribute("Racing", false)
task.wait(0.5)
check("volta depois da corrida", client().shown == true, "não voltou")

-- animado: andando, a pose do boneco muda de um quadro para o outro
local function walkSpread(): number
	hook:Invoke("ui", player, { command = "walk", arg = { direction = Vector3.new(0, 0, 1), seconds = 2.2 } })
	task.wait(1)
	local low, high = math.huge, -math.huge
	for _ = 1, 20 do
		local arm = client().arm
		low, high = math.min(low, arm), math.max(high, arm)
		task.wait(0.05)
	end
	task.wait(0.6)
	return high - low
end
local surfing = client()
local carpetSwing = walkSpread()
check("o tapete é animado andando", carpetSwing > 6, `braço variou {carpetSwing} graus`)
hook:Invoke("mount", player, board.id)
task.wait(0.8)
local boardSwing = walkSpread()
check("o skate é animado andando", boardSwing > 6, `braço variou {boardSwing} graus`)
check("trocar no menu montado troca embaixo do boneco", client().id == board.id, client().id)
check("o passeio mede a velocidade", client().moving >= 0 and surfing.id == carpet.id, tostring(client().moving))

hook:Invoke("ride", player)
hook:Invoke("set", player, { mount = "" })
check("sem montaria escolhida M não sobe", hook:Invoke("ride", player) == nil and player:GetAttribute("Riding") == nil, "")
task.wait(0.5)
return `{#passed} verificações OK: ` .. table.concat(passed, "; ")
