--!strict
-- Mundo 2, o vulcão: ilha de chegada, pista, mar de lava, vulcões e agulhas de rocha no fundo.
-- Os modelos vêm do Blender (tools/blender/volcano.py); aqui eles são pintados e postos no
-- lugar, e ganham colisão, luzes, a zona de carga, as paredes quebráveis e o portal de volta.
--
-- Fica longe do mundo 1 (Config.Worlds[2].offset) e usa a mesma planta: a zona de carga e as
-- paredes ficam onde ficam as do gramado, somadas ao offset. Por isso a corrida é o mesmo código.
-- As medidas ficam em Config.Volcano.
--
-- A colisão é de peças simples e invisíveis: o chão onde se pisa é um disco e uma faixa, e os
-- modelos ficam um fio abaixo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(script.Parent.Models)
local World = require(script.Parent.World)

local V = Config.Volcano
local RUN = Config.Run
local G = Config.World.groundY
local WORLD = Config.Worlds[2]
local O = WORLD.offset

local Volcano = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local LAVA = rgb(255, 96, 20)
local EMBER = rgb(255, 170, 40)

-- O nome de cada peça dos modelos começa pelo tipo ("Rock_volcano_base").
local STYLE: { [string]: Models.Style } = {
	Rock = { color = rgb(62, 48, 54), material = Enum.Material.Slate },
	RockDark = { color = rgb(38, 30, 36), material = Enum.Material.Slate },
	Basalt = { color = rgb(80, 66, 72), material = Enum.Material.Basalt },
	BasaltDark = { color = rgb(52, 42, 48), material = Enum.Material.Basalt },
	Obsidian = { color = rgb(26, 16, 40), material = Enum.Material.SmoothPlastic },
	Lava = { color = LAVA, material = Enum.Material.Neon },
	Ember = { color = EMBER, material = Enum.Material.Neon },
	Flame = { color = rgb(255, 205, 90), material = Enum.Material.Neon },
	Crystal = { color = rgb(255, 70, 30), material = Enum.Material.Neon },
	Iron = { color = rgb(30, 28, 34), material = Enum.Material.Metal },
	Gold = { color = rgb(255, 196, 60), material = Enum.Material.Metal },
	Portal = { color = rgb(90, 220, 255), material = Enum.Material.Neon },
	Board = { color = rgb(22, 16, 24), material = Enum.Material.Slate },
}

type Props = { name: string, size: Vector3, cframe: CFrame, color: Color3?, material: Enum.Material?, shape: Enum.PartType?, visible: boolean?, collide: boolean? }

local function part(parent: Instance, props: Props): Part
	local p = Instance.new("Part")
	p.Name = props.name
	p.Anchored = true
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color or rgb(255, 255, 255)
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Shape = props.shape or Enum.PartType.Block
	p.Transparency = if props.visible == false then 1 else 0
	p.CanCollide = props.collide ~= false
	p.CanQuery = props.collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Cilindro em pé (o eixo do cilindro do Roblox é X).
local function post(parent: Instance, name: string, radius: number, bottom: number, top: number, at: Vector3)
	part(parent, { name = name, size = Vector3.new(top - bottom, radius * 2, radius * 2), cframe = CFrame.new(at.X, (top + bottom) / 2, at.Z) * CFrame.Angles(0, 0, math.rad(90)), shape = Enum.PartType.Cylinder, visible = false })
end

local function light(parent: Instance, at: Vector3, color: Color3, range: number, brightness: number)
	local p = part(parent, { name = "Light", size = Vector3.one, cframe = CFrame.new(at), visible = false, collide = false })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = math.min(range, 60)
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

local function label(parent: Instance, name: string, text: string, color: Color3, size: UDim2, position: UDim2)
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
	stroke.Color = Config.Palette.outline
	stroke.Parent = t
	t.Parent = parent
end

-- Um ponto da ilha, dado nos eixos do modelo do Blender (X = direita, Y = para a pista).
local function onIsland(x: number, y: number, height: number?): Vector3
	return O + V.islandCenter + Vector3.new(x, G + (height or 0), -y)
end

local function buildSea(folder: Instance)
	local quarter = V.seaSize / 2
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		part(folder, {
			name = "LavaSea",
			size = Vector3.new(quarter, 6, quarter),
			cframe = CFrame.new(O.X + corner.X * quarter / 2, G + V.lavaY - 3, O.Z - 500 + corner.Y * quarter / 2),
			color = rgb(255, 120, 40),
			material = Enum.Material.CrackedLava,
		})
	end
end

local function buildIsland(folder: Instance, colliders: Instance)
	local model = Models.load("volcano_base", STYLE)
	if model then
		model:PivotTo(CFrame.new(onIsland(0, 0)))
		model.Parent = folder
	end
	local center = onIsland(0, 0)
	local R = V.islandRadius

	-- chão: disco invisível com o topo na altura do gramado do mundo 1
	part(colliders, { name = "IslandFloor", size = Vector3.new(4, R * 2, R * 2), cframe = CFrame.new(center.X, G - 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), shape = Enum.PartType.Cylinder, visible = false })

	-- muralha: trechos retos em volta, abertos só na frente do portão
	local pieces = 28
	local radius = R - 4.5
	local width = 2 * math.pi * radius / pieces + 1.5
	for i = 0, pieces - 1 do
		local turn = CFrame.Angles(0, (i + 0.5) * 2 * math.pi / pieces, 0)
		local at = (CFrame.new(center) * turn * CFrame.new(0, 0, -radius)).Position
		if at.Z < center.Z and math.abs(at.X - center.X) < 26 then
			continue
		end
		part(colliders, { name = "Rim", size = Vector3.new(width, 120, 4), cframe = CFrame.new(center) * turn * CFrame.new(0, 60, -radius), visible = false })
	end
	-- torres do portão, obeliscos, pedestal do cristal e o portal
	for _, side in { -1, 1 } do
		post(colliders, "GateTower", 12.5, G - 2, G + 60, onIsland(side * 31, 90))
		post(colliders, "Brazier", 2.4, G, G + 5, onIsland(side * 19.5, 77.5))
		post(colliders, "Brazier", 1.8, G, G + 8, onIsland(side * 14.5, -60))
	end
	for n = 0, 5 do
		local a = n * math.pi / 3 + math.pi / 6
		post(colliders, "Obelisk", 2.3, G, G + 18, onIsland(math.cos(a) * 24.5, math.sin(a) * 24.5))
	end
	post(colliders, "Pedestal", 5, G, G + 5, center)
	part(colliders, { name = "PortalBase", size = Vector3.new(24, 2.6, 7), cframe = CFrame.new(onIsland(0, -62, 1.3)), visible = false })
	part(colliders, { name = "PortalRing", size = Vector3.new(19, 19, 2.4), cframe = CFrame.new(onIsland(0, -62, 11)), visible = false })

	-- portal de volta: o cliente ouve o ProximityPrompt "WorldPortal"
	local portal = part(folder, { name = "Portal", size = Vector3.new(4, 4, 4), cframe = CFrame.new(onIsland(0, -57, 5)), visible = false, collide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WorldPortal"
	prompt.ObjectText = "Portal"
	prompt.ActionText = "Return to the " .. string.sub(Config.Worlds[1].name, 1, 1) .. string.lower(string.sub(Config.Worlds[1].name, 2))
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = V.portalRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = portal
	portal:SetAttribute("World", 1)

	-- placa do portão (o modelo traz a tábua; o texto é daqui), virada para a ilha
	local board = part(folder, { name = "GateSign", size = Vector3.new(35, 10.2, 0.2), cframe = CFrame.new(onIsland(0, 87.7, 39.5)), visible = false, collide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z, o lado da ilha
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	label(gui, "Line1", WORLD.name .. " RUN", EMBER, UDim2.fromScale(0.94, 0.52), UDim2.fromScale(0.03, 0.03))
	label(gui, "Line2", `MAGMA CHARACTERS: x{WORLD.incomeMultiplier} INCOME`, rgb(255, 255, 255), UDim2.fromScale(0.94, 0.36), UDim2.fromScale(0.03, 0.58))
	gui.Parent = board

	light(folder, onIsland(0, 0, 15), rgb(255, 90, 40), 60, 2.6)
	light(folder, onIsland(0, -56, 10), STYLE.Portal.color, 40, 2)
	for _, side in { -1, 1 } do
		light(folder, onIsland(side * 19.5, 77.5, 6), EMBER, 36, 2)
		light(folder, onIsland(side * 40, 0, 12), LAVA, 60, 1.2)
	end
end

-- Zona de carga na saída da ilha: lajes escuras, borda acesa e o nome pintado no chão.
local function buildZone(hallway: Instance, zone: Vector3)
	local zx, zz = RUN.zoneSize.X, RUN.zoneSize.Y
	local plate = part(hallway, { name = "ChargeZone", size = Vector3.new(zx, 0.1, zz), cframe = CFrame.new(zone.X, G + 0.08, zone.Z), color = rgb(46, 30, 34), material = Enum.Material.Basalt, collide = false })
	plate:SetAttribute("Kind", "ChargeZone")
	for ix = 0, zx // 10 - 1 do
		for iz = 0, zz // 10 - 1 do
			if (ix + iz) % 2 == 0 then
				part(hallway, { name = "ZoneTile", size = Vector3.new(10, 0.1, 10), cframe = CFrame.new(zone.X - zx / 2 + ix * 10 + 5, G + 0.1, zone.Z - zz / 2 + iz * 10 + 5), color = rgb(120, 34, 22), material = Enum.Material.Basalt, collide = false })
			end
		end
	end
	for _, edge in { { 0, -zz / 2, zx + 1, 1 }, { 0, zz / 2, zx + 1, 1 }, { -zx / 2, 0, 1, zz }, { zx / 2, 0, 1, zz } } do
		part(hallway, { name = "ZoneBorder", size = Vector3.new(edge[3], 0.2, edge[4]), cframe = CFrame.new(zone.X + edge[1], G + 0.15, zone.Z + edge[2]), color = EMBER, material = Enum.Material.Neon, collide = false })
	end
	local text = part(hallway, { name = "ZoneText", size = Vector3.new(30, 0.05, 8), cframe = CFrame.new(zone.X, G + 0.2, zone.Z) * CFrame.Angles(0, math.rad(180), 0), visible = false, collide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	label(gui, "Text", "CHARGE ZONE", rgb(255, 235, 200), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	gui.Parent = text
end

local function buildTrack(folder: Instance, colliders: Instance, hallway: Instance, zone: Vector3)
	local gateZ = O.Z + V.gateZ
	local lastWall = WORLD.walls[#WORLD.walls].distance / RUN.metersPerStud
	local endZ = zone.Z - lastWall - RUN.endPadding
	local count = math.ceil((gateZ - endZ) / V.segment)
	local farZ = gateZ - count * V.segment

	local template = Models.load("volcano_track", STYLE)
	if template then
		local track = Instance.new("Folder")
		track.Name = "Track"
		track.Parent = folder
		for i = 0, count - 1 do
			local z = gateZ - i * V.segment
			local piece = template:Clone()
			piece.Name = "Segment" .. (i + 1)
			piece:PivotTo(CFrame.new(O.X, G, z))
			piece.Parent = track
			-- um braseiro de cada lado no começo do trecho
			for _, side in { -1, 1 } do
				light(track, Vector3.new(O.X + side * 14, G + 24, z), EMBER, 44, 2.4)
			end
		end
		template:Destroy()
	end

	-- chão da pista, paredões e o fim: invisíveis, do tamanho do que o modelo mostra
	local startZ = gateZ + 12 -- entra um pouco na ilha, para não sobrar fresta no portão
	local length = startZ - farZ
	local midZ = (startZ + farZ) / 2
	local half = RUN.hallwayWidth / 2
	part(colliders, { name = "TrackFloor", size = Vector3.new(half * 2 + 3.6, 4, length), cframe = CFrame.new(O.X, G - 2, midZ), visible = false })
	for _, side in { -1, 1 } do
		part(colliders, { name = "TrackSide", size = Vector3.new(4, 160, gateZ - farZ), cframe = CFrame.new(O.X + side * (half + 3.6), G + 78, (gateZ + farZ) / 2), visible = false })
	end
	part(colliders, { name = "TrackEnd", size = Vector3.new(half * 2 + 12, 160, 4), cframe = CFrame.new(O.X, G + 78, farZ - 2), visible = false })

	-- faixas de luz nas bordas: o cliente pinta com a cor da parede que estourou
	local neon = Instance.new("Folder")
	neon.Name = "Neon"
	neon.Parent = hallway
	for _, side in { -1, 1 } do
		part(neon, { name = "Strip", size = Vector3.new(0.8, 0.2, gateZ - farZ), cframe = CFrame.new(O.X + side * (half - 0.9), G + 0.12, (gateZ + farZ) / 2), color = EMBER, material = Enum.Material.Neon, collide = false })
	end

	-- as paredes quebráveis, de rocha e lava
	World.buildWalls(hallway, WORLD.walls, zone, { Enum.Material.Basalt, Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.CrackedLava, Enum.Material.Metal, Enum.Material.Neon })
	return farZ
end

-- Vulcões e agulhas de rocha no mar de lava. A mesma semente dá sempre o mesmo fundo.
local function buildBackdrop(folder: Instance, farZ: number)
	local rng = Random.new(V.seed)
	local sea = G + V.lavaY
	local mount = Models.load("volcano_mount", STYLE)
	if mount then
		local natural = mount:GetScale()
		-- um atrás da ilha e um, maior ainda de perto, no fim da pista: corre-se na direção dele
		for _, spot in { { at = O + V.mount, scale = V.mountScale }, { at = Vector3.new(O.X, G + V.mount.Y, farZ - 330), scale = V.mountScale * 0.8 } } do
			local copy = mount:Clone()
			copy:ScaleTo(natural * spot.scale)
			copy:PivotTo(CFrame.new(spot.at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			copy.Parent = folder
			light(folder, spot.at + Vector3.new(0, 300 * spot.scale, 0), LAVA, 60, 4)
		end
		mount:Destroy()
	end

	local spire = Models.load("volcano_spire", STYLE)
	if spire then
		local natural = spire:GetScale()
		local island = O + V.islandCenter
		local placed = 0
		while placed < V.spires do
			local x = O.X + rng:NextNumber(-520, 520)
			local z = rng:NextNumber(farZ - 120, O.Z + 260)
			local nearIsland = Vector2.new(x - island.X, z - island.Z).Magnitude < V.islandRadius + 55
			local nearTrack = math.abs(x - O.X) < 78 and z < O.Z + V.gateZ + 40
			if nearIsland or nearTrack then
				continue
			end
			local copy = spire:Clone()
			copy:ScaleTo(natural * rng:NextNumber(1, 3.2))
			copy:PivotTo(CFrame.new(x, sea, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			copy.Parent = folder
			placed += 1
		end
		spire:Destroy()
	end
end

function Volcano.build()
	local zone = Config.zoneCenter(WORLD)
	local folder = Instance.new("Folder")
	folder.Name = "Volcano"
	local colliders = Instance.new("Folder")
	colliders.Name = "Colliders"
	colliders.Parent = folder
	local hallway = Instance.new("Folder")
	hallway.Name = WORLD.hallway

	buildSea(folder)
	buildIsland(folder, colliders)
	buildZone(hallway, zone)
	local farZ = buildTrack(folder, colliders, hallway, zone)
	buildBackdrop(folder, farZ)

	folder.Parent = workspace
	hallway.Parent = workspace
end

return Volcano
