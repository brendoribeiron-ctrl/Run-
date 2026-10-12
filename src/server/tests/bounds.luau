-- Limites do mapa: chão fora dos muros, paredes invisíveis fechando gramado e corredor, e a
-- rede de segurança que devolve quem cai.
--   node tools/bridge.cjs run server src/server/tests/bounds.luau 60000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local W = Config.World
local G = W.groundY

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
task.wait(1)

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end

check("pasta Bounds existe", workspace:FindFirstChild("Bounds") ~= nil, "sem Bounds")

-- um raio de dentro para fora, em várias alturas, tem que bater em algo que colide
local params = RaycastParams.new()
params.FilterDescendantsInstances = { character }
params.RespectCanCollide = true
local function blocked(from: Vector3, direction: Vector3): boolean
	return workspace:Raycast(from, direction, params) ~= nil
end
local halfX, halfZ = W.lawnSize.X / 2, W.lawnSize.Y / 2
local open, samples = 0, 0
for _, height in { 3, 11, 14, 20, 40, 120, 300 } do
	for _, along in { -0.9, -0.5, 0, 0.5, 0.9 } do
		for _, probe in {
			{ Vector3.new(along * halfX, G + height, halfZ - 20), Vector3.new(0, 0, 60) },
			{ Vector3.new(halfX - 20, G + height, along * halfZ), Vector3.new(60, 0, 0) },
			{ Vector3.new(-halfX + 20, G + height, along * halfZ), Vector3.new(-60, 0, 0) },
		} do
			samples += 1
			if not blocked(probe[1], probe[2]) then
				open += 1
			end
		end
	end
	-- lado do portão: fechado fora da abertura do corredor
	for _, x in { -200, -120, -60, 60, 120, 200 } do
		samples += 1
		if not blocked(Vector3.new(x, G + height, -halfZ + 20), Vector3.new(0, 0, -60)) then
			open += 1
		end
	end
end
check("gramado fechado em todas as alturas", open == 0, `{open} de {samples} raios passaram`)
check("portão do corredor continua aberto", not blocked(Vector3.new(0, G + 4, -halfZ + 20), Vector3.new(0, 0, -40)), "bloqueado") -- raio curto: a primeira parede quebrável fica logo depois

-- corredor: laterais e fim fechados, do chão ao alto
local endZ = Config.Run.zoneCenter.Z - Config.Walls[#Config.Walls].distance / Config.Run.metersPerStud - Config.Run.endPadding
local hallOpen = 0
for _, height in { 5, 18, 26, 60, 250 } do
	for _, z in { -200, -500, -900, endZ + 30 } do
		for _, side in { -1, 1 } do
			if not blocked(Vector3.new(0, G + height, z), Vector3.new(side * 60, 0, 0)) then
				hallOpen += 1
			end
		end
	end
	if not blocked(Vector3.new(0, G + height, endZ + 30), Vector3.new(0, 0, -80)) then
		hallOpen += 1
	end
end
check("corredor fechado nas laterais e no fim", hallOpen == 0, `{hallOpen} raios passaram`)

-- fora dos muros há chão (nada de vazio) até bem longe
local holes = 0
for _, point in { Vector2.new(400, 0), Vector2.new(-400, 0), Vector2.new(0, 400), Vector2.new(600, -900), Vector2.new(-700, -1400), Vector2.new(1500, 1500), Vector2.new(-1800, 300) } do
	if not workspace:Raycast(Vector3.new(point.X, 350, point.Y), Vector3.new(0, -450, 0), params) then
		holes += 1
	end
end
check("há chão fora dos muros", holes == 0, holes .. " pontos sem chão")

-- rede de segurança: jogado no vazio, volta para o terreno
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
local home = (plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset)).Position
character:PivotTo(CFrame.new(3000, W.fallY - 30, 3000))
task.wait(3)
check("quem cai volta para o terreno", (root.Position - home).Magnitude < 30, tostring(root.Position))

return `{#passed} verificações OK: ` .. table.concat(passed, "; ") .. ` | {samples} raios no gramado`
