--!strict
-- Sala de testes da equipe: um chão xadrez grande, longe do mapa, para testar habilidades,
-- golpes e efeitos com o jogo inteiro rodando. Só dev entra (/lab leva, /back devolve ao
-- terreno); se alguém de fora aparecer aqui, volta para o terreno dele.
--
-- O chão (DevArea.floor) também é o do laboratório de efeitos separado (lab.project.json).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local AREA = Config.DevArea
local TILE = 20
local LIGHT = Color3.fromRGB(132, 132, 140)
local DARK = Color3.fromRGB(98, 98, 108)
local LINE = Color3.fromRGB(70, 70, 82) -- linha a cada 100 studs, para medir o tamanho dos efeitos

local DevArea = {}

local function block(parent: Instance, size: Vector3, position: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Chão xadrez cinza médio (nem claro nem escuro) de `size` studs, com o topo em center.Y.
function DevArea.floor(parent: Instance, center: Vector3, size: number)
	-- base inteira por baixo (sem fresta entre as casas) e as casas claras por cima
	block(parent, Vector3.new(size, 4, size), center + Vector3.new(0, -2.05, 0), DARK).Name = "Base"
	local count = math.floor(size / TILE)
	for i = 0, count - 1 do
		for j = 0, count - 1 do
			if (i + j) % 2 == 0 then
				local x = -size / 2 + TILE * (i + 0.5)
				local z = -size / 2 + TILE * (j + 0.5)
				block(parent, Vector3.new(TILE, 0.1, TILE), center + Vector3.new(x, -0.05, z), LIGHT)
			end
		end
	end
	for k = -size / 2, size / 2, 100 do
		local width = if k == 0 then 1.2 else 0.6
		block(parent, Vector3.new(size, 0.02, width), center + Vector3.new(0, 0.01, k), LINE)
		block(parent, Vector3.new(width, 0.02, size), center + Vector3.new(k, 0.01, 0), LINE)
	end
end

-- Onde o dev aparece: na beira sul do centro, olhando para o meio.
function DevArea.arriveCFrame(): CFrame
	local at = AREA.center + Vector3.new(0, 4, 60)
	return CFrame.lookAt(at, AREA.center + Vector3.new(0, 4, 0))
end

function DevArea.contains(position: Vector3): boolean
	local d = position - AREA.center
	return math.abs(d.X) <= AREA.size / 2 + 50 and math.abs(d.Z) <= AREA.size / 2 + 50 and d.Y > -100 and d.Y < 600
end

-- Monta a sala e vigia quem entra. isAdmin e home vêm do servidor (quem é dev, onde fica o
-- terreno de cada um).
function DevArea.start(isAdmin: (Player) -> boolean, home: (Player) -> CFrame?)
	local folder = Instance.new("Folder")
	folder.Name = "DevArea"
	folder.Parent = workspace
	DevArea.floor(folder, AREA.center, AREA.size)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and DevArea.contains(root.Position) and not isAdmin(player) then
					local target = home(player)
					if target then
						root.AssemblyLinearVelocity = Vector3.zero
						character:PivotTo(target)
					end
				end
			end
		end
	end)
end

return DevArea
