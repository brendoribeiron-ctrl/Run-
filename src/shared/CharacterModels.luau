--!strict
-- Lutadores de brinquedo montados com peças, a partir das cores e do chapéu em Config.Characters.
-- O mesmo modelo serve para o pedestal (servidor), a carta e o hotbar (ViewportFrame no cliente).

local Config = require(script.Parent.Config)

local CharacterModels = {}

local SKIN = Color3.fromRGB(255, 205, 150)
local DARK = Color3.fromRGB(20, 20, 28)

local function piece(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function addHat(model: Model, hat: string, color: Color3, glow: Enum.Material)
	local top = 4.8 -- topo da cabeça
	if hat == "band" then
		piece(model, "Band", Vector3.new(1.62, 0.3, 1.52), CFrame.new(0, 4.45, 0), color)
		piece(model, "Knot", Vector3.new(0.3, 0.6, 0.5), CFrame.new(0.5, 4.35, 0.95) * CFrame.Angles(0.4, 0, 0), color)
	elseif hat == "cap" then
		piece(model, "Cap", Vector3.new(1.6, 0.5, 1.5), CFrame.new(0, top + 0.1, 0), color)
		piece(model, "Brim", Vector3.new(1.4, 0.15, 0.8), CFrame.new(0, top - 0.1, -1), color)
	elseif hat == "hood" then
		piece(model, "Hood", Vector3.new(1.8, 1.5, 1.5), CFrame.new(0, 4.3, 0.2), color)
		piece(model, "HoodTop", Vector3.new(1.8, 0.4, 1.9), CFrame.new(0, top + 0.1, 0), color)
	elseif hat == "spikes" then
		for i = -1, 1 do
			piece(model, "Spike", Vector3.new(0.45, 1, 0.45), CFrame.new(i * 0.5, top + 0.3, 0.1 * math.abs(i)) * CFrame.Angles(-0.25, 0, -i * 0.35), color, glow)
		end
	elseif hat == "horns" then
		for _, side in { -1, 1 } do
			piece(model, "Horn", Vector3.new(0.4, 1.2, 0.4), CFrame.new(side * 0.75, top + 0.35, 0) * CFrame.Angles(0, 0, -side * 0.5), color, glow)
		end
	elseif hat == "crown" then
		piece(model, "Crown", Vector3.new(1.4, 0.35, 1.3), CFrame.new(0, top + 0.15, 0), color, glow)
		for i = -1, 1 do
			piece(model, "Point", Vector3.new(0.3, 0.5, 0.3), CFrame.new(i * 0.5, top + 0.55, 0), color, glow)
		end
	elseif hat == "halo" then
		piece(model, "Halo", Vector3.new(0.15, 1.9, 1.9), CFrame.new(0, top + 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	end
end

-- Devolve o modelo com os pés na origem e a frente virada para -Z.
function CharacterModels.build(id: string, scale: number?): Model
	local info = Config.CharacterById[id]
	assert(info, "personagem desconhecido: " .. tostring(id))

	local model = Instance.new("Model")
	model.Name = info.name
	local glow = if info.rarity >= 4 then Enum.Material.Neon else Enum.Material.SmoothPlastic

	for _, side in { -1, 1 } do
		piece(model, "Leg", Vector3.new(0.9, 1.6, 0.95), CFrame.new(side * 0.52, 0.8, 0), info.pants)
		piece(model, "Shoe", Vector3.new(0.95, 0.4, 1.3), CFrame.new(side * 0.52, 0.2, -0.15), DARK)
		-- braços em guarda de boxe
		piece(model, "Arm", Vector3.new(0.7, 1.5, 0.7), CFrame.new(side * 1.38, 2.65, -0.35) * CFrame.Angles(math.rad(55), 0, 0), info.body)
		piece(model, "Glove", Vector3.new(1.15, 1.15, 1.15), CFrame.new(side * 1.3, 3.05, -1.15), info.glove, glow, Enum.PartType.Ball)
	end
	piece(model, "Torso", Vector3.new(2, 1.8, 1.1), CFrame.new(0, 2.5, 0), info.body)
	piece(model, "Belt", Vector3.new(2.06, 0.32, 1.16), CFrame.new(0, 1.75, 0), info.glove)
	piece(model, "Head", Vector3.new(1.5, 1.4, 1.4), CFrame.new(0, 4.1, 0), SKIN)
	for _, side in { -1, 1 } do
		piece(model, "Eye", Vector3.new(0.24, 0.4, 0.06), CFrame.new(side * 0.34, 4.18, -0.71), DARK)
	end
	piece(model, "Mouth", Vector3.new(0.5, 0.1, 0.06), CFrame.new(0, 3.72, -0.71), DARK)
	addHat(model, info.hat, info.glove, glow)

	-- os dois tiers mais altos ganham orbes flutuando
	if info.rarity >= 5 then
		for i = 1, 3 do
			local angle = i * math.pi * 2 / 3
			piece(model, "Orb", Vector3.new(0.5, 0.5, 0.5), CFrame.new(math.cos(angle) * 2.1, 2.2 + i * 0.7, math.sin(angle) * 2.1), Config.Rarities[info.rarity].color, Enum.Material.Neon, Enum.PartType.Ball)
		end
	end

	model.WorldPivot = CFrame.identity
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

-- Monta o modelo dentro de um ViewportFrame com câmera de frente, levemente de lado.
function CharacterModels.render(viewport: ViewportFrame, id: string)
	viewport:ClearAllChildren()
	local model = CharacterModels.build(id)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(-4, 4.2, -11.5), Vector3.new(0, 2.7, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.LightDirection = Vector3.new(0.4, -1, 0.8)
	viewport.Ambient = Color3.fromRGB(170, 170, 180)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
end

return CharacterModels
