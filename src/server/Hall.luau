--!strict
-- Decoração do corredor da corrida, no estilo salão gótico: pedra azul, frisos dourados, pilares
-- com arcos ogivais, estandartes vermelhos pendurados, janelas acesas, lanternas e um desenho
-- dourado no piso. Um trecho é montado uma vez e copiado ao longo do corredor. É só visual:
-- nada aqui colide (piso, muros e paredes quebráveis continuam em World.luau).
-- As medidas ficam em Config.Hall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HALL = Config.Hall
local G = Config.World.groundY

local Hall = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STYLE: { [string]: { color: Color3, material: Enum.Material } } = {
	Stone = { color = rgb(96, 112, 235), material = Enum.Material.Marble },
	Dark = { color = rgb(40, 44, 120), material = Enum.Material.Slate },
	Gold = { color = rgb(240, 180, 70), material = Enum.Material.Metal },
	Trim = { color = rgb(255, 180, 70), material = Enum.Material.Neon },
	Cloth = { color = rgb(190, 25, 45), material = Enum.Material.Fabric },
	Glass = { color = rgb(110, 160, 255), material = Enum.Material.Neon },
	Glow = { color = rgb(255, 200, 120), material = Enum.Material.Neon },
	Gem = { color = rgb(255, 50, 80), material = Enum.Material.Neon },
}

local function piece(parent: Instance, kind: string, size: Vector3, cframe: CFrame, shape: Enum.PartType?): Part
	local style = STYLE[kind]
	local p = Instance.new("Part")
	p.Name = kind
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = style.color
	p.Material = style.material
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false -- o salão é fechado: com sombra, o sol não entra e fica tudo preto
	p.Parent = parent
	return p
end

-- Cilindro em pé (o eixo do cilindro do Roblox é X).
local function column(parent: Instance, kind: string, diameter: number, height: number, base: Vector3)
	piece(parent, kind, Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
end

-- Pilar: base escura, anel dourado, fuste azul com dois anéis, capitel abrindo.
local function pillar(parent: Instance, x: number)
	local at = Vector3.new(x, G, 0)
	piece(parent, "Dark", Vector3.new(5.2, 1.2, 5.2), CFrame.new(at + Vector3.new(0, 0.6, 0)))
	piece(parent, "Gold", Vector3.new(4.3, 0.7, 4.3), CFrame.new(at + Vector3.new(0, 1.55, 0)))
	column(parent, "Stone", 3.1, HALL.pillarHeight - 4.9, at + Vector3.new(0, 1.9, 0))
	column(parent, "Gold", 3.5, 0.45, at + Vector3.new(0, HALL.pillarHeight * 0.3, 0))
	column(parent, "Gold", 3.5, 0.45, at + Vector3.new(0, HALL.pillarHeight * 0.58, 0))
	piece(parent, "Stone", Vector3.new(4.4, 1.2, 4.4), CFrame.new(at + Vector3.new(0, HALL.pillarHeight - 2.4, 0)))
	piece(parent, "Gold", Vector3.new(5.3, 0.6, 5.3), CFrame.new(at + Vector3.new(0, HALL.pillarHeight - 1.5, 0)))
	piece(parent, "Dark", Vector3.new(5.8, 1.2, 5.8), CFrame.new(at + Vector3.new(0, HALL.pillarHeight - 0.6, 0)))
end

-- Lanterna no lado de dentro do pilar: braço, gaiola dourada e miolo aceso.
local function lantern(parent: Instance, x: number)
	local inward = -math.sign(x)
	local y = G + HALL.pillarHeight * 0.52
	piece(parent, "Gold", Vector3.new(2.6, 0.3, 0.3), CFrame.new(x + inward * 2.6, y + 2.2, 0))
	local lamp = Vector3.new(x + inward * 3.7, y + 0.9, 0)
	piece(parent, "Gold", Vector3.new(1.5, 0.25, 1.5), CFrame.new(lamp + Vector3.new(0, 1.0, 0)))
	piece(parent, "Gold", Vector3.new(1.5, 0.25, 1.5), CFrame.new(lamp - Vector3.new(0, 1.0, 0)))
	local core = piece(parent, "Glow", Vector3.new(1.1, 1.8, 1.1), CFrame.new(lamp))
	local light = Instance.new("PointLight")
	light.Color = STYLE.Glow.color
	light.Range = HALL.lanternRange
	light.Brightness = HALL.lanternBrightness
	light.Parent = core
end

-- Arco ogival entre os dois pilares: dois arcos de círculo que se encontram no alto, feitos
-- de trechos retos. Devolve a altura do arco (acima do topo dos pilares) num X dado.
local function arch(parent: Instance): (x: number) -> number
	local half = HALL.pillarOffset
	local rise = HALL.archRise
	local offset = (rise * rise - half * half) / (2 * half) -- centro de cada arco, do outro lado do eixo
	local radius = half + offset
	local top = G + HALL.pillarHeight
	local function height(x: number): number
		local dx = math.abs(x) + offset
		return math.sqrt(math.max(radius * radius - dx * dx, 0))
	end
	local steps = HALL.archSteps
	for _, side in { -1, 1 } do
		for i = 0, steps - 1 do
			local x0, x1 = half * (1 - i / steps), half * (1 - (i + 1) / steps)
			local a = Vector3.new(side * x0, top + height(x0), 0)
			local b = Vector3.new(side * x1, top + height(x1), 0)
			local length = (b - a).Magnitude
			local turn = CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, math.atan2(b.Y - a.Y, b.X - a.X))
			piece(parent, "Stone", Vector3.new(length + 0.5, 1.9, 2.8), turn)
			-- friso dourado aceso por baixo da nervura
			piece(parent, "Trim", Vector3.new(length + 0.3, 0.35, 0.8), turn * CFrame.new(0, side * 1.1, 0))
		end
	end
	local apex = Vector3.new(0, top + rise, 0)
	piece(parent, "Gold", Vector3.new(2.6, 2.6, 3.2), CFrame.new(apex) * CFrame.Angles(0, 0, math.rad(45)))
	piece(parent, "Gem", Vector3.new(1.1, 1.1, 3.5), CFrame.new(apex) * CFrame.Angles(0, 0, math.rad(45)))
	return height
end

-- Estandarte pendurado no arco, de frente para quem corre: pano vermelho com ponta, bordas e
-- losango dourados.
local function banner(parent: Instance, x: number, topY: number)
	local long, wide = HALL.bannerLength, HALL.bannerWidth
	local at = Vector3.new(x, topY, 0)
	piece(parent, "Gold", Vector3.new(wide + 1, 0.45, 0.45), CFrame.new(at), Enum.PartType.Cylinder)
	piece(parent, "Cloth", Vector3.new(wide, long, 0.15), CFrame.new(at - Vector3.new(0, long / 2, 0)))
	-- ponta: um quadrado em losango, metade escondida atrás do pano
	local diagonal = wide / math.sqrt(2)
	piece(parent, "Cloth", Vector3.new(diagonal, diagonal, 0.15), CFrame.new(at - Vector3.new(0, long, 0)) * CFrame.Angles(0, 0, math.rad(45)))
	for _, side in { -1, 1 } do
		piece(parent, "Gold", Vector3.new(0.28, long, 0.22), CFrame.new(at + Vector3.new(side * (wide / 2 - 0.14), -long / 2, 0)))
	end
	local emblem = CFrame.new(at - Vector3.new(0, long * 0.45, 0)) * CFrame.Angles(0, 0, math.rad(45))
	piece(parent, "Gold", Vector3.new(1.5, 1.5, 0.24), emblem)
	piece(parent, "Gem", Vector3.new(0.6, 0.6, 0.3), emblem)
end

-- Janela ogival na parede lateral: vidro azul aceso, moldura e travessas douradas.
local function window(parent: Instance, x: number, z: number)
	local inward = -math.sign(x)
	local wide, tall = HALL.windowWidth, HALL.windowHeight
	local sill = G + HALL.windowSill
	local face = CFrame.new(x + inward * 0.2, sill, z) * CFrame.Angles(0, math.rad(90), 0) -- o plano da janela acompanha a parede
	piece(parent, "Glass", Vector3.new(wide, tall, 0.2), face * CFrame.new(0, tall / 2, 0))
	local diagonal = wide / math.sqrt(2)
	piece(parent, "Glass", Vector3.new(diagonal, diagonal, 0.2), face * CFrame.new(0, tall, 0) * CFrame.Angles(0, 0, math.rad(45)))
	for _, side in { -1, 1 } do
		piece(parent, "Gold", Vector3.new(0.45, tall, 0.5), face * CFrame.new(side * wide / 2, tall / 2, 0))
		piece(parent, "Gold", Vector3.new(diagonal + 0.4, 0.45, 0.5), face * CFrame.new(side * wide / 4, tall + wide / 4, 0) * CFrame.Angles(0, 0, math.rad(-side * 45)))
	end
	piece(parent, "Gold", Vector3.new(0.3, tall + wide / 2, 0.4), face * CFrame.new(0, (tall + wide / 2) / 2, 0))
	for _, fraction in { 0.33, 0.66 } do
		piece(parent, "Gold", Vector3.new(wide, 0.3, 0.4), face * CFrame.new(0, tall * fraction, 0))
	end
	piece(parent, "Dark", Vector3.new(wide + 1.6, 1, 1.2), face * CFrame.new(0, -0.5, 0))
	-- a janela joga uma luz azul fria para dentro
	local glow = Instance.new("PointLight")
	glow.Color = STYLE.Glass.color
	glow.Range = HALL.windowRange
	glow.Brightness = HALL.windowBrightness
	glow.Parent = piece(parent, "Glass", Vector3.new(0.4, 0.4, 0.4), face * CFrame.new(0, tall * 0.6, -1.5))
end

-- Desenho dourado no piso de um trecho: moldura, losango grande, losango pequeno e medalhão.
local function inlay(parent: Instance, z: number, length: number)
	local y = G + 0.09
	local reach = math.min(HALL.pillarOffset - 3, length / 2 - 2)
	local line = HALL.inlayWidth
	local function strip(center: Vector3, long: number, yaw: number, wide: number?)
		piece(parent, "Trim", Vector3.new(long, 0.1, wide or line), CFrame.new(center) * CFrame.Angles(0, yaw, 0))
	end
	for _, side in { -1, 1 } do
		strip(Vector3.new(0, y, z + side * reach), reach * 2 + line, 0)
		strip(Vector3.new(side * reach, y, z), reach * 2 + line, math.rad(90))
	end
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		strip(Vector3.new(0, y, z) + dir * reach / math.sqrt(2), reach * math.sqrt(2), -angle + math.rad(90))
		strip(Vector3.new(0, y, z) + dir * reach * 0.3, reach * 0.6, -angle + math.rad(90), line * 0.7)
		piece(parent, "Gold", Vector3.new(2.4, 0.12, 2.4), CFrame.new(Vector3.new(0, y, z) + dir * reach * math.sqrt(2)) * CFrame.Angles(0, math.rad(45), 0))
	end
	piece(parent, "Gold", Vector3.new(0.14, 4.6, 4.6), CFrame.new(0, y, z) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	piece(parent, "Gem", Vector3.new(0.18, 2, 2), CFrame.new(0, y, z) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
end

-- Teto escuro com uma nervura dourada no meio e cornijas no alto das paredes.
local function ceiling(parent: Instance, z: number, length: number, width: number)
	local y = G + Config.Run.wallHeight
	piece(parent, "Dark", Vector3.new(width + 12, 1, length), CFrame.new(0, y + 0.5, z))
	piece(parent, "Trim", Vector3.new(0.7, 0.4, length), CFrame.new(0, y - 0.2, z))
	for _, side in { -1, 1 } do
		piece(parent, "Gold", Vector3.new(1.2, 1.2, length), CFrame.new(side * (width / 2 - 0.2), y - 0.8, z))
		piece(parent, "Trim", Vector3.new(0.4, 0.3, length), CFrame.new(side * (width / 2 - 1), y - 1.6, z))
	end
end

-- Monta um trecho (pilares e arco em z = 0, o resto até z = -length) e o copia pelo corredor.
function Hall.build(parent: Instance): number
	local run = Config.Run
	local lawnEdge = -Config.World.lawnSize.Y / 2
	local endZ = run.zoneCenter.Z - Config.Walls[#Config.Walls].distance / run.metersPerStud - run.endPadding
	local length = HALL.spacing

	local segment = Instance.new("Model")
	segment.Name = "Segment"
	for _, side in { -1, 1 } do
		pillar(segment, side * HALL.pillarOffset)
		lantern(segment, side * HALL.pillarOffset)
		window(segment, side * run.hallwayWidth / 2, -length / 2)
	end
	local archHeight = arch(segment)
	for _, side in { -1, 1 } do
		local x = side * HALL.bannerOffset
		banner(segment, x, G + HALL.pillarHeight + archHeight(x) - 1.2)
	end
	inlay(segment, -length / 2, length)
	ceiling(segment, -length / 2, length, run.hallwayWidth)
	segment.WorldPivot = CFrame.new(0, G, 0)

	-- muros, tampa e fundo do corredor também deixam o sol passar
	for _, child in parent:GetChildren() do
		if child:IsA("BasePart") and (child.Name == "SideWall" or child.Name == "SideCap" or child.Name == "EndWall") then
			child.CastShadow = false
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	local count = 0
	local z = lawnEdge - HALL.firstOffset
	while z - length > endZ - 4 do
		local copy = segment:Clone()
		copy:PivotTo(CFrame.new(0, G, z))
		copy.Parent = folder
		count += 1
		z -= length
	end
	segment:Destroy()
	folder.Parent = parent
	return count
end

return Hall
