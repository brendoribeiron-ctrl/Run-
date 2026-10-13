--!strict
-- Geometria do lobby e dos terrenos, gerada a partir do Config. Nada é montado à mão no Studio.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local P = Config.Palette
local W = Config.World
local G = W.groundY

local World = {}

type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	collide: boolean?,
}

local function part(parent: Instance, props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.name or "Part"
	p.Anchored = true
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Shape = props.shape or Enum.PartType.Block
	p.Transparency = props.transparency or 0
	p.CanCollide = props.collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = props.material ~= Enum.Material.Neon
	p.Parent = parent
	return p
end

local function label(parent: Instance, name: string, text: string, color: Color3, size: UDim2, position: UDim2): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = position
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = P.outline
	stroke.Parent = t
	t.Parent = parent
	return t
end

-- Cilindro em pé: o eixo do cilindro do Roblox é X, então gira 90 graus.
local function uprightCylinder(parent: Instance, name: string, diameter: number, height: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	return part(parent, {
		name = name,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		material = material,
		shape = Enum.PartType.Cylinder,
	})
end

function World.setupLighting()
	Lighting.Brightness = 1.8
	Lighting.ExposureCompensation = -0.35
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 35
	Lighting.Ambient = Color3.fromRGB(95, 95, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(125, 125, 140)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3

	-- efeitos que já existem no place (montados à mão no Studio) valem: não cria um segundo por cima
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.3
		bloom.Size = 18
		bloom.Threshold = 1.8
		bloom.Parent = Lighting
	end

	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local color = Instance.new("ColorCorrectionEffect")
		color.Saturation = 0.25
		color.Contrast = 0.08
		color.Parent = Lighting
	end

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 0.6
		atmosphere.Color = Color3.fromRGB(199, 220, 255)
		atmosphere.Parent = Lighting
	end
end

function World.buildLobby(): Folder
	-- sobras do place vazio do Studio: a Baseplate (cinza, sem textura do jogo) passava por cima
	-- do chão de fora em volta do gramado, e o spawn padrão ficava no meio do mapa
	for _, name in { "Baseplate", "SpawnLocation" } do
		local leftover = workspace:FindFirstChild(name)
		if leftover and leftover:IsA("BasePart") then
			leftover:Destroy()
		end
	end

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"

	local sx, sz = W.lawnSize.X, W.lawnSize.Y
	part(lobby, {
		name = "Lawn",
		size = Vector3.new(sx, 0.25, sz),
		cframe = CFrame.new(0, G - 0.125, 0),
		color = P.grassLight,
		material = Enum.Material.Grass,
	})

	-- Xadrez: só os quadrados escuros são peças, o claro é a base.
	local tiles = Instance.new("Folder")
	tiles.Name = "Checker"
	tiles.Parent = lobby
	local cols, rows = sx // W.tile, sz // W.tile
	for ix = 0, cols - 1 do
		for iz = 0, rows - 1 do
			if (ix + iz) % 2 == 0 then
				part(tiles, {
					name = "Tile",
					size = Vector3.new(W.tile, 0.05, W.tile),
					cframe = CFrame.new(-sx / 2 + (ix + 0.5) * W.tile, G + 0.025, -sz / 2 + (iz + 0.5) * W.tile),
					color = P.grassDark,
					material = Enum.Material.Grass,
					collide = false,
				})
			end
		end
	end

	-- Caminho de areia na frente dos terrenos, com linhas amarelas nas bordas.
	local pathZ = W.plotRowZ - W.plotSize.Y / 2 - 9
	part(lobby, {
		name = "Path",
		size = Vector3.new(sx - 20, 0.1, 12),
		cframe = CFrame.new(0, G + 0.08, pathZ),
		color = P.sand,
		material = Enum.Material.Sand,
		collide = false,
	})
	for _, side in { -1, 1 } do
		part(lobby, {
			name = "PathLine",
			size = Vector3.new(sx - 20, 0.1, 0.8),
			cframe = CFrame.new(0, G + 0.1, pathZ + side * 5.6),
			color = P.yellowLine,
			collide = false,
		})
	end

	-- Muro de contenção em xadrez laranja/marrom com grama em cima.
	local perimeter = Instance.new("Folder")
	perimeter.Name = "Perimeter"
	perimeter.Parent = lobby
	local h = W.perimeterHeight
	local half = h / 2
	-- gap: meia largura de uma abertura no centro do muro (portão do corredor)
	local function wallRun(length: number, origin: Vector3, alongX: boolean, gap: number?)
		local count = length // W.tile
		for i = 0, count - 1 do
			local offset = -length / 2 + (i + 0.5) * W.tile
			if gap and math.abs(offset) < gap then
				continue
			end
			for layer = 0, 1 do
				local color = if (i + layer) % 2 == 0 then P.wallOrange else P.wallBrown
				local size = if alongX then Vector3.new(W.tile, half, 6) else Vector3.new(6, half, W.tile)
				local pos = origin + (if alongX then Vector3.new(offset, 0, 0) else Vector3.new(0, 0, offset))
				part(perimeter, {
					name = "Wall",
					size = size,
					cframe = CFrame.new(pos.X, G + half / 2 + layer * half, pos.Z),
					color = color,
					material = Enum.Material.Brick,
				})
			end
		end
		if gap then
			local capLength = length / 2 - gap + 3
			for _, side in { -1, 1 } do
				part(perimeter, {
					name = "GrassCap",
					size = Vector3.new(capLength, 1.2, 8),
					cframe = CFrame.new(origin.X + side * (gap + capLength / 2), G + h + 0.6, origin.Z),
					color = P.grassDark,
					material = Enum.Material.LeafyGrass,
				})
			end
			return
		end
		local capSize = if alongX then Vector3.new(length + 6, 1.2, 8) else Vector3.new(8, 1.2, length + 6)
		part(perimeter, {
			name = "GrassCap",
			size = capSize,
			cframe = CFrame.new(origin.X, G + h + 0.6, origin.Z),
			color = P.grassDark,
			material = Enum.Material.LeafyGrass,
		})
	end
	wallRun(sx, Vector3.new(0, 0, sz / 2 + 3), true)
	wallRun(sx, Vector3.new(0, 0, -sz / 2 - 3), true, Config.Run.hallwayWidth / 2)
	wallRun(sz, Vector3.new(sx / 2 + 3, 0, 0), false)
	wallRun(sz, Vector3.new(-sx / 2 - 3, 0, 0), false)

	lobby.Parent = workspace
	return lobby
end

-- Fecha o mapa: chão de grama que continua para fora dos muros (nada de vazio à vista) e
-- paredes invisíveis altas em cima dos muros do gramado e do corredor (ninguém sobe neles
-- nem sai do mapa).
function World.buildBounds(): Folder
	local run = Config.Run
	local bounds = Instance.new("Folder")
	bounds.Name = "Bounds"

	-- chão de fora: quatro placas grandes, um pouco abaixo do gramado
	local quarter = W.outlandSize / 2
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		part(bounds, {
			name = "Outland",
			size = Vector3.new(quarter, 4, quarter),
			cframe = CFrame.new(corner.X * quarter / 2, G - 2.6, corner.Y * quarter / 2),
			color = Color3.fromRGB(58, 172, 40),
			material = Enum.Material.Grass,
		})
	end

	local height = W.boundsHeight
	local function barrier(size: Vector3, position: Vector3)
		local wall = part(bounds, { name = "Barrier", size = size, cframe = CFrame.new(position), color = Color3.new(1, 1, 1), transparency = 1 })
		wall.CastShadow = false
	end

	-- gramado: em cima dos quatro muros, do topo deles para cima (mais largo que o muro, para
	-- não sobrar beirada onde ficar em pé)
	local sx, sz = W.lawnSize.X, W.lawnSize.Y
	local tall = height - W.perimeterHeight
	local y = G + W.perimeterHeight + tall / 2
	local gap = run.hallwayWidth / 2 -- abertura do portão do corredor
	barrier(Vector3.new(sx + 20, tall, 10), Vector3.new(0, y, sz / 2 + 3))
	barrier(Vector3.new(10, tall, sz + 20), Vector3.new(sx / 2 + 3, y, 0))
	barrier(Vector3.new(10, tall, sz + 20), Vector3.new(-sx / 2 - 3, y, 0))
	local sideLength = sx / 2 + 10 - gap
	for _, side in { -1, 1 } do
		barrier(Vector3.new(sideLength, tall, 10), Vector3.new(side * (gap + sideLength / 2), y, -sz / 2 - 3))
	end

	-- corredor: em cima dos muros laterais e do muro do fim
	local lawnEdge = -sz / 2
	local endZ = run.zoneCenter.Z - Config.Walls[#Config.Walls].distance / run.metersPerStud - run.endPadding
	local length = lawnEdge - endZ
	for _, side in { -1, 1 } do
		barrier(Vector3.new(8, height - run.wallHeight, length), Vector3.new(side * (gap + 4), G + run.wallHeight + (height - run.wallHeight) / 2, (lawnEdge + endZ) / 2))
	end
	barrier(Vector3.new(run.hallwayWidth + 16, height - run.wallHeight, 8), Vector3.new(0, G + run.wallHeight + (height - run.wallHeight) / 2, endZ - 3))

	bounds.Parent = workspace
	return bounds
end

-- Zona de carga, portão e o corredor com as paredes pré-fraturadas.
function World.buildHallway(): Folder
	local run = Config.Run
	local hallway = Instance.new("Folder")
	hallway.Name = "Hallway"

	local width = run.hallwayWidth
	local startZ = run.zoneCenter.Z
	local lawnEdge = -W.lawnSize.Y / 2
	local lastWall = Config.Walls[#Config.Walls].distance / run.metersPerStud
	local endZ = startZ - lastWall - run.endPadding
	local length = lawnEdge - endZ
	local midZ = (lawnEdge + endZ) / 2
	local lightBlue = Color3.fromRGB(105, 180, 255)
	local blue = Color3.fromRGB(46, 123, 255)
	local white = Color3.fromRGB(255, 255, 255)

	-- zona de carga: xadrez azul, borda de neon branco e nome pintado no chão
	local zone = part(hallway, {
		name = "ChargeZone",
		size = Vector3.new(run.zoneSize.X, 0.1, run.zoneSize.Y),
		cframe = CFrame.new(run.zoneCenter.X, G + 0.08, run.zoneCenter.Z),
		color = lightBlue,
		collide = false,
	})
	local zx, zz = run.zoneSize.X, run.zoneSize.Y
	for ix = 0, zx // 10 - 1 do
		for iz = 0, zz // 10 - 1 do
			if (ix + iz) % 2 == 0 then
				part(hallway, {
					name = "ZoneTile",
					size = Vector3.new(10, 0.1, 10),
					cframe = CFrame.new(run.zoneCenter.X - zx / 2 + ix * 10 + 5, G + 0.1, run.zoneCenter.Z - zz / 2 + iz * 10 + 5),
					color = blue,
					collide = false,
				})
			end
		end
	end
	for _, edge in { { 0, -zz / 2, zx + 1, 1 }, { 0, zz / 2, zx + 1, 1 }, { -zx / 2, 0, 1, zz }, { zx / 2, 0, 1, zz } } do
		part(hallway, {
			name = "ZoneBorder",
			size = Vector3.new(edge[3], 0.2, edge[4]),
			cframe = CFrame.new(run.zoneCenter.X + edge[1], G + 0.15, run.zoneCenter.Z + edge[2]),
			color = white,
			material = Enum.Material.Neon,
			collide = false,
		})
	end
	local floorText = part(hallway, {
		name = "ZoneText",
		size = Vector3.new(30, 0.05, 8),
		cframe = CFrame.new(run.zoneCenter.X, G + 0.2, run.zoneCenter.Z) * CFrame.Angles(0, math.rad(180), 0),
		color = blue,
		transparency = 1,
		collide = false,
	})
	local floorGui = Instance.new("SurfaceGui")
	floorGui.Face = Enum.NormalId.Top
	floorGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	floorGui.PixelsPerStud = 25
	floorGui.LightInfluence = 0
	label(floorGui, "Text", "CHARGE ZONE", white, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	floorGui.Parent = floorText
	zone:SetAttribute("Kind", "ChargeZone")

	-- portão: os dois pilares grandes da fachada e o letreiro de duas linhas acima do arco da
	-- entrada, virado para os terrenos. A decoração da fachada fica em Hall.luau.
	local gateZ = lawnEdge - 3
	local hall = Config.Hall
	for _, side in { -1, 1 } do
		local pier = part(hallway, {
			name = "GatePillar",
			size = Vector3.new(hall.pierWidth, hall.pierHeight, 7),
			cframe = CFrame.new(side * (width / 2 + hall.pierWidth / 2), G + hall.pierHeight / 2, gateZ),
			color = Color3.fromRGB(58, 68, 170),
			material = Enum.Material.Slate,
		})
		pier.CastShadow = false
	end
	local board = part(hallway, { name = "Billboard", size = Vector3.new(width, hall.signHeight, 1.5), cframe = CFrame.new(0, G + hall.signBase + hall.signHeight / 2, gateZ + 1.75), color = P.navy, collide = false })
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Back -- +Z, lado dos terrenos
	boardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	boardGui.PixelsPerStud = 30
	boardGui.LightInfluence = 0
	local top = label(boardGui, "Line1", "BREAK WALLS FOR RARER CHARACTERS!", P.yellowLine, UDim2.fromScale(0.96, 0.44), UDim2.fromScale(0.02, 0.04))
	top.BackgroundTransparency = 0
	top.BackgroundColor3 = P.red
	label(boardGui, "Line2", "CHARGE UP, THEN RUN THE HALLWAY!", P.cyan, UDim2.fromScale(0.96, 0.44), UDim2.fromScale(0.02, 0.52))
	boardGui.Parent = board

	-- piso em xadrez, muros laterais e faixas de neon nas bordas
	part(hallway, { name = "Floor", size = Vector3.new(width, 0.25, length), cframe = CFrame.new(0, G - 0.125, midZ), color = Color3.fromRGB(52, 62, 160), material = Enum.Material.Slate })
	local tiles = Instance.new("Folder")
	tiles.Name = "Checker"
	tiles.Parent = hallway
	for iz = 0, length // W.tile - 1 do
		for ix = 0, width // W.tile - 1 do
			if (ix + iz) % 2 == 0 then
				part(tiles, {
					name = "Tile",
					size = Vector3.new(W.tile, 0.05, W.tile),
					cframe = CFrame.new(-width / 2 + (ix + 0.5) * W.tile, G + 0.025, lawnEdge - (iz + 0.5) * W.tile),
					color = Color3.fromRGB(74, 88, 205),
					material = Enum.Material.Slate,
					collide = false,
				})
			end
		end
	end
	-- muros laterais, da fachada até o muro do fim, em trechos iguais (sem sobra no final)
	local wallStart = lawnEdge - 6
	local wallCount = math.ceil((wallStart - endZ) / 40)
	local segment = (wallStart - endZ) / wallCount
	for i = 0, wallCount - 1 do
		local z = wallStart - (i + 0.5) * segment
		for _, side in { -1, 1 } do
			part(hallway, {
				name = "SideWall",
				size = Vector3.new(6, run.wallHeight, segment),
				cframe = CFrame.new(side * (width / 2 + 3), G + run.wallHeight / 2, z),
				color = if i % 2 == 0 then Color3.fromRGB(58, 68, 170) else Color3.fromRGB(70, 82, 196),
				material = Enum.Material.Slate,
			})
		end
	end
	part(hallway, { name = "EndWall", size = Vector3.new(width + 12, run.wallHeight, 6), cframe = CFrame.new(0, G + run.wallHeight / 2, endZ - 3), color = Color3.fromRGB(40, 46, 122), material = Enum.Material.Slate })

	local neon = Instance.new("Folder")
	neon.Name = "Neon"
	neon.Parent = hallway
	for _, side in { -1, 1 } do
		part(neon, {
			name = "Strip",
			size = Vector3.new(1, 0.2, length),
			cframe = CFrame.new(side * (width / 2 - 0.6), G + 0.15, midZ),
			color = white,
			material = Enum.Material.Neon,
			collide = false,
		})
	end

	-- paredes: grade de tijolos ancorados + placa com os requisitos
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = hallway
	local materials = { Enum.Material.WoodPlanks, Enum.Material.SmoothPlastic, Enum.Material.Ice, Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Neon }
	local columns, rows = 8, 4
	local brickW, brickH = width / columns, 4
	for index, info in Config.Walls do
		local wall = Instance.new("Model")
		wall.Name = "Wall" .. index
		wall:SetAttribute("Index", index)
		local z = startZ - info.distance / run.metersPerStud
		local color = Config.Rarities[info.tier].color
		local bricks = Instance.new("Folder")
		bricks.Name = "Bricks"
		bricks.Parent = wall
		for cx = 0, columns - 1 do
			for cy = 0, rows - 1 do
				local shade = if (cx + cy) % 2 == 0 then color else color:Lerp(Color3.new(0, 0, 0), 0.25)
				local brick = part(bricks, {
					name = "Brick",
					size = Vector3.new(brickW, brickH, 2),
					cframe = CFrame.new(-width / 2 + (cx + 0.5) * brickW, G + (cy + 0.5) * brickH, z),
					color = shade,
					material = materials[info.tier],
				})
				brick.CastShadow = false
			end
		end
		local sign = part(wall, { name = "Sign", size = Vector3.new(26, 8, 0.6), cframe = CFrame.new(0, G + rows * brickH + 6, z), color = P.navy, collide = false })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		label(gui, "Tier", string.upper(Config.Rarities[info.tier].id) .. " WALL", color, UDim2.fromScale(0.94, 0.36), UDim2.fromScale(0.03, 0.03))
		label(gui, "Require", `Require {Format.abbreviate(info.power)} Power`, white, UDim2.fromScale(0.94, 0.3), UDim2.fromScale(0.03, 0.38))
		label(gui, "Luck", `x{info.luck} Luck - {info.distance} M`, P.money, UDim2.fromScale(0.94, 0.26), UDim2.fromScale(0.03, 0.7))
		gui.Parent = sign
		wall.Parent = walls
	end

	hallway.Parent = workspace
	return hallway
end

function World.plotCFrame(index: number): CFrame
	local x = (index - (W.plotCount + 1) / 2) * W.plotSpacing
	return CFrame.new(x, G, W.plotRowZ)
end

local function buildGantry(plot: Model, origin: CFrame)
	local gantry = Instance.new("Model")
	gantry.Name = "Gantry"

	local bagPos = (origin * CFrame.new(Config.Plot.bagOffset)).Position

	-- Dois pilares ao longo de Z para o pórtico ficar de frente para o tapete.
	for _, dz in { -5, 5 } do
		local base = bagPos + Vector3.new(0, 0, dz)
		part(gantry, { name = "Pillar", size = Vector3.new(2, 14, 2), cframe = CFrame.new(base + Vector3.new(0, 7, 0)), color = P.navy })
		for _, y in { 3, 10 } do
			part(gantry, { name = "Band", size = Vector3.new(2.3, 0.9, 2.3), cframe = CFrame.new(base + Vector3.new(0, y, 0)), color = P.machineYellow })
		end
	end
	part(gantry, { name = "Beam", size = Vector3.new(2.4, 2, 14), cframe = CFrame.new(bagPos + Vector3.new(0, 15, 0)), color = P.navy })

	local sign = part(gantry, { name = "Sign", size = Vector3.new(0.6, 5, 11), cframe = CFrame.new(bagPos + Vector3.new(0, 19, 0)), color = P.navy })
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Gui" .. face.Name
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		label(gui, "Title", "BAG Lv 1", P.machineYellow, UDim2.fromScale(0.94, 0.5), UDim2.fromScale(0.03, 0.04))
		label(gui, "Rate", "+1 POWER", P.cyan, UDim2.fromScale(0.94, 0.4), UDim2.fromScale(0.03, 0.55))
		gui.Parent = sign
	end

	uprightCylinder(gantry, "Base", 9, 0.5, bagPos + Vector3.new(0, 0.25, 0), Color3.fromRGB(12, 12, 16))
	local disc = uprightCylinder(gantry, "Disc", 7, 0.2, bagPos + Vector3.new(0, 0.6, 0), P.cyan, Enum.Material.Neon)
	disc.CanCollide = false

	-- O saco é um Model com pivô no ponto onde pendura: o cliente balança com PivotTo.
	local bag = Instance.new("Model")
	bag.Name = "Bag"
	part(bag, { name = "Chain", size = Vector3.new(0.3, 2.5, 0.3), cframe = CFrame.new(bagPos + Vector3.new(0, 12.75, 0)), color = Color3.fromRGB(60, 60, 70), collide = false })
	local body = uprightCylinder(bag, "Body", 3.4, 6, bagPos + Vector3.new(0, 8.5, 0), P.red)
	body.CanCollide = false
	for _, y in { 7, 10 } do
		local band = uprightCylinder(bag, "Stripe", 3.5, 0.7, bagPos + Vector3.new(0, y, 0), Color3.fromRGB(255, 255, 255))
		band.CanCollide = false
	end
	bag.WorldPivot = CFrame.new(bagPos + Vector3.new(0, 14, 0))
	bag:SetAttribute("Center", bagPos + Vector3.new(0, 8.5, 0))
	bag.Parent = gantry

	-- bloco verde em degraus ao lado do pórtico: upgrade do saco
	local upgradePos = bagPos + Vector3.new(4, 0, 9)
	part(gantry, { name = "UpgradeStep", size = Vector3.new(5, 1, 5), cframe = CFrame.new(upgradePos + Vector3.new(0, 0.9, 0)), color = P.grassDark })
	local upgrade = part(gantry, { name = "Upgrade", size = Vector3.new(3.4, 2.4, 3.4), cframe = CFrame.new(upgradePos + Vector3.new(0, 2.6, 0)), color = Color3.fromRGB(60, 230, 90) })
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "Prompt"
	upgradePrompt.ObjectText = "Punching Bag"
	upgradePrompt.ActionText = "Upgrade Bag"
	upgradePrompt.KeyboardKeyCode = Enum.KeyCode.F
	upgradePrompt.MaxActivationDistance = 9
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt.Parent = upgrade
	local price = Instance.new("BillboardGui")
	price.Name = "Price"
	price.Size = UDim2.fromScale(7, 1.5)
	price.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	price.MaxDistance = 70
	label(price, "Text", "UPGRADE $50", P.money, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	price.Parent = upgrade

	local hint = Instance.new("BillboardGui")
	hint.Name = "Hint"
	hint.Size = UDim2.fromScale(9, 1.6)
	hint.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	hint.AlwaysOnTop = true
	hint.MaxDistance = 60
	hint.Adornee = body
	label(hint, "Text", "CLICK TO PUNCH!", Color3.fromRGB(255, 255, 255), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	hint.Parent = body

	gantry.Parent = plot
end

local function buildPedestal(plot: Model, origin: CFrame, index: number, offset: Vector3, cost: number)
	local pedestal = Instance.new("Model")
	pedestal.Name = "Pedestal" .. index
	pedestal:SetAttribute("PedestalIndex", index)
	local slab = 1.0 -- topo da laje
	local height = Config.Plot.pedestalHeight
	local diameter = Config.Plot.pedestalDiameter
	local base = (origin * CFrame.new(offset.X, slab, offset.Z)).Position
	-- redondo e elevado: anel de neon na laje, corpo escuro, friso e tampo onde o personagem fica
	local rim = uprightCylinder(pedestal, "Rim", diameter + 1.2, 0.2, base + Vector3.new(0, 0.1, 0), P.cyan, Enum.Material.Neon)
	rim.CanCollide = false
	uprightCylinder(pedestal, "Body", diameter, height - 0.3, base + Vector3.new(0, (height - 0.3) / 2, 0), P.navy)
	local band = uprightCylinder(pedestal, "Band", diameter + 0.3, 0.25, base + Vector3.new(0, height - 0.55, 0), P.machineYellow)
	band.CanCollide = false
	local pad = uprightCylinder(pedestal, "Pad", diameter - 0.6, 0.3, base + Vector3.new(0, height - 0.15, 0), P.slab)
	pedestal.PrimaryPart = pad

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ObjectText = "Pedestal " .. index
	prompt.ActionText = "Place"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = pad

	-- segundo prompt, em outra tecla: sobe o nível do personagem que está no pedestal
	local upgrade = Instance.new("ProximityPrompt")
	upgrade.Name = "Upgrade"
	upgrade.ObjectText = "Level Up"
	upgrade.ActionText = "Level Up"
	upgrade.KeyboardKeyCode = Enum.KeyCode.F
	upgrade.GamepadKeyCode = Enum.KeyCode.ButtonY
	upgrade.UIOffset = Vector2.new(0, 78)
	upgrade.HoldDuration = 0
	upgrade.MaxActivationDistance = 10
	upgrade.RequiresLineOfSight = false
	upgrade.Enabled = false
	upgrade.Parent = pad

	-- preço flutuando em cima do pedestal trancado
	local lock = Instance.new("BillboardGui")
	lock.Name = "Lock"
	lock.Size = UDim2.fromScale(7, 2.6)
	lock.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	lock.MaxDistance = 70
	lock.Enabled = false
	label(lock, "Title", "LOCKED", P.red, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0))
	label(lock, "Price", if cost > 0 then "$" .. Format.abbreviate(cost) else "", P.money, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5))
	lock.Parent = pad

	pedestal.Parent = plot
end

function World.buildPlot(index: number): Model
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	local origin = World.plotCFrame(index)
	plot:SetAttribute("PlotId", index)
	plot:SetAttribute("Origin", origin)

	local px, pz = W.plotSize.X, W.plotSize.Y
	local floor = part(plot, { name = "Floor", size = Vector3.new(px, 0.4, pz), cframe = origin * CFrame.new(0, 0.2, 0), color = P.sand })
	plot.PrimaryPart = floor
	part(plot, { name = "Carpet", size = Vector3.new(12, 0.1, pz), cframe = origin * CFrame.new(0, 0.45, 0), color = P.red, collide = false })

	for _, side in { -1, 1 } do
		local slabCenter = origin * CFrame.new(side * 18, 0.7, 8)
		part(plot, { name = "Slab", size = Vector3.new(20, 0.6, 40), cframe = slabCenter, color = P.slab })
		-- contorno de neon ciano em volta da laje
		for _, edge in { { 0, -20, 20.6, 0.5 }, { 0, 20, 20.6, 0.5 }, { -10, 0, 0.5, 40.6 }, { 10, 0, 0.5, 40.6 } } do
			part(plot, {
				name = "Neon",
				size = Vector3.new(edge[3], 0.2, edge[4]),
				cframe = slabCenter * CFrame.new(edge[1], 0.35, edge[2]),
				color = P.cyan,
				material = Enum.Material.Neon,
				collide = false,
			})
		end
	end

	for i, info in Config.Plot.pedestals do
		buildPedestal(plot, origin, i, info.offset, info.cost)
	end

	buildGantry(plot, origin)

	-- um só botão de coleta por terreno: mostra a soma do que todos os pedestais guardam;
	-- pisar nele recolhe tudo
	local collect = part(plot, {
		name = "Collect",
		size = Vector3.new(12, 0.5, 6),
		cframe = origin * CFrame.new(Config.Plot.collectOffset.X, 0.65, Config.Plot.collectOffset.Z) * CFrame.Angles(0, math.rad(180), 0),
		color = Color3.fromRGB(40, 200, 80),
		collide = false,
	})
	part(plot, {
		name = "CollectRim",
		size = Vector3.new(13, 0.3, 7),
		cframe = collect.CFrame * CFrame.new(0, -0.15, 0),
		color = Color3.fromRGB(150, 255, 170),
		material = Enum.Material.Neon,
		collide = false,
	})
	local collectGui = Instance.new("SurfaceGui")
	collectGui.Name = "Gui"
	collectGui.Face = Enum.NormalId.Top
	collectGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	collectGui.PixelsPerStud = 40
	collectGui.LightInfluence = 0
	label(collectGui, "Title", "COLLECT", Color3.fromRGB(255, 255, 255), UDim2.fromScale(0.9, 0.42), UDim2.fromScale(0.05, 0.06))
	label(collectGui, "Amount", "$0", P.yellowLine, UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.46))
	collectGui.Parent = collect

	-- Ponto de nascimento no tapete, virado para o saco.
	local spawnPos = (origin * CFrame.new(Config.Plot.spawnOffset.X, 0.5, Config.Plot.spawnOffset.Z)).Position
	local bagPos = (origin * CFrame.new(Config.Plot.bagOffset)).Position
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.lookAt(spawnPos, Vector3.new(bagPos.X, spawnPos.Y, bagPos.Z))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = plot

	local anchor = part(plot, { name = "NameSign", size = Vector3.new(1, 1, 1), cframe = origin * CFrame.new(0, 14, -pz / 2), color = P.navy, transparency = 1, collide = false })
	local board = Instance.new("BillboardGui")
	board.Name = "Board"
	board.Size = UDim2.fromScale(22, 3.5)
	board.MaxDistance = 400
	label(board, "Text", "Empty Plot", Color3.fromRGB(200, 200, 210), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	board.Parent = anchor

	return plot
end

return World
