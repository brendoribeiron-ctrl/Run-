--!strict
-- Casa de feitiçaria no centro do gramado: salão quadrado com uma porta em cada parede, quatro
-- torres de canto e a torre central com o chapéu. O modelo vem do Blender
-- (tools/blender/sanctum.py, id em Shared.Assets); aqui ele é pintado, posto no lugar e ganha a
-- colisão e as luzes. As medidas ficam em Config.Sanctum.
--
-- A colisão é feita de peças simples escondidas dentro das paredes do modelo (um pouco menores
-- que elas). Elas são opacas de propósito: a câmera do Roblox só desvia de peça opaca, e sem
-- isso ela ficaria do lado de fora enquanto o jogador anda dentro do salão.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)

local S = Config.Sanctum
local G = Config.World.groundY

local Sanctum = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- O nome de cada peça do modelo começa pelo tipo ("Roof_sanctum").
local STYLE: { [string]: { color: Color3, material: Enum.Material } } = {
	Stone = { color = rgb(206, 198, 238), material = Enum.Material.Marble },
	Dark = { color = rgb(52, 46, 112), material = Enum.Material.Slate },
	Roof = { color = rgb(126, 66, 216), material = Enum.Material.Slate },
	Gold = { color = rgb(255, 196, 60), material = Enum.Material.Metal },
	Glass = { color = rgb(120, 220, 255), material = Enum.Material.Neon },
	Glow = { color = rgb(120, 255, 230), material = Enum.Material.Neon },
	Wood = { color = rgb(92, 58, 36), material = Enum.Material.Wood },
	Floor = { color = rgb(44, 40, 98), material = Enum.Material.Marble },
}

local INSET = 0.2 -- quanto a colisão fica para dentro da parede do modelo

-- Peças do balcão de poções ("Iron_potion_shop"...).
local SHOP_STYLE: { [string]: { color: Color3, material: Enum.Material } } = {
	Stone = { color = rgb(150, 150, 172), material = Enum.Material.Slate },
	Wood = { color = rgb(124, 80, 44), material = Enum.Material.WoodPlanks },
	Flame = { color = rgb(255, 140, 30), material = Enum.Material.Neon },
	Iron = { color = rgb(38, 38, 48), material = Enum.Material.Metal },
	Gold = { color = rgb(255, 196, 60), material = Enum.Material.Metal },
	Liquid = { color = rgb(90, 255, 120), material = Enum.Material.Neon },
	PotionA = { color = rgb(255, 80, 90), material = Enum.Material.Neon },
	PotionB = { color = rgb(80, 170, 255), material = Enum.Material.Neon },
	PotionC = { color = rgb(200, 100, 255), material = Enum.Material.Neon },
	Glass = { color = rgb(210, 235, 255), material = Enum.Material.Glass },
	Cork = { color = rgb(170, 120, 70), material = Enum.Material.Wood },
	BookA = { color = rgb(150, 30, 45), material = Enum.Material.Fabric },
	BookB = { color = rgb(40, 80, 170), material = Enum.Material.Fabric },
	Page = { color = rgb(250, 244, 220), material = Enum.Material.SmoothPlastic },
	Crystal = { color = rgb(120, 255, 230), material = Enum.Material.Neon },
}

-- Balcão de poções: caldeirão, estante e bancada num canto do salão. Chegar perto mostra o
-- aviso que abre o painel SHOP (o cliente ouve o ProximityPrompt "PotionShop").
local function buildShop(folder: Instance, colliders: Instance, origin: CFrame, k: number)
	local id = tonumber(string.match(Assets.potion_shop or "", "%d+"))
	if not id then
		return
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok then
		warn(`[Sanctum] o balcão de poções não carregou ({container})`)
		return
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		container:Destroy()
		return
	end
	local pivot: Vector3? = nil
	local front: Vector3? = nil
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local kind = string.match(part.Name, "^(%a+)_") or ""
		if kind == "Pivot" or kind == "Front" then
			if kind == "Pivot" then
				pivot = part.Position
			else
				front = part.Position
			end
			part:Destroy()
			continue
		end
		local style = SHOP_STYLE[kind]
		if style then
			part.Color = style.color
			part.Material = style.material
		end
		if kind == "Glass" then
			part.Transparency = 0.35
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	local center, size = model:GetBoundingBox()
	local at = pivot or (center.Position - Vector3.new(0, size.Y / 2, 0))
	local facing = if front then front - at else center.LookVector
	facing = Vector3.new(facing.X, 0, facing.Z)
	model.WorldPivot = CFrame.lookAt(at, at + (if facing.Magnitude > 0.01 then facing.Unit else Vector3.zAxis)) -- -Z do pivô = frente
	model:ScaleTo(k * S.shopWidth / math.max(size.X, size.Z))
	model.Name = "PotionShop"

	-- no canto do salão, de frente para o centro
	local spot = origin * CFrame.new(S.shopOffset.X * k, S.floor * k, S.shopOffset.Y * k)
	local toCenter = Vector3.new(origin.Position.X - spot.Position.X, 0, origin.Position.Z - spot.Position.Z)
	model:PivotTo(CFrame.lookAt(spot.Position, spot.Position + toCenter))
	model.Parent = folder
	container:Destroy()

	-- colisão simples no caldeirão e na estante, e o aviso de abrir a loja
	local body = Instance.new("Part")
	body.Name = "ShopBody"
	body.Anchored = true
	body.Transparency = 1
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(6, 5.6, 5.6) * k
	body.CFrame = CFrame.new(spot.Position + Vector3.new(0, 3 * k, 0)) * CFrame.Angles(0, 0, math.rad(90))
	body.Parent = colliders
	local shelf = Instance.new("Part")
	shelf.Name = "ShopShelf"
	shelf.Anchored = true
	shelf.Transparency = 1
	shelf.Size = Vector3.new(8.6, 9.6, 1.6) * k
	shelf.CFrame = model:GetPivot() * CFrame.new(0, 4.8 * k, 4.2 * k)
	shelf.Parent = colliders

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PotionShop"
	prompt.ObjectText = "Potion Shop"
	prompt.ActionText = "Open"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = S.shopRange * k
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	local glow = Instance.new("PointLight")
	glow.Color = SHOP_STYLE.Liquid.color
	glow.Range = 22 * k
	glow.Brightness = 1.8
	glow.Shadows = false
	glow.Parent = body
end

local function loadModel(): Model?
	local id = tonumber(string.match(Assets.sanctum or "", "%d+"))
	if not id then
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok then
		warn(`[Sanctum] o modelo não carregou ({container})`)
		return nil
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		container:Destroy()
		return nil
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local style = STYLE[string.match(part.Name, "^(%a+)_") or ""]
			if style then
				part.Color = style.color
				part.Material = style.material
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = style ~= nil and style.material ~= Enum.Material.Neon
		end
	end
	local center, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(center.Position - Vector3.new(0, size.Y / 2, 0))
	model:ScaleTo(S.scale * S.modelWidth / math.max(size.X, size.Z))
	model.Name = "Model"
	model.Parent = nil
	container:Destroy()
	return model
end

-- Monta a casa. Devolve false se o modelo não carregou (aí nada é criado, nem a colisão).
function Sanctum.build(): boolean
	local model = loadModel()
	if not model then
		return false
	end
	local k = S.scale
	local origin = CFrame.new(S.center.X, G, S.center.Y)
	local folder = Instance.new("Folder")
	folder.Name = "Sanctum"

	-- a base do modelo fica um pouco enterrada (os cristais de fora nascem abaixo do chão)
	model:PivotTo(origin * CFrame.new(0, -0.6 * k, 0))
	model.Parent = folder

	local colliders = Instance.new("Folder")
	colliders.Name = "Colliders"
	colliders.Parent = folder

	-- medidas em studs do modelo, relativas ao centro no chão; a escala entra aqui
	local function solid(name: string, size: Vector3, at: CFrame, kind: string, shape: Enum.PartType?): Part
		local style = STYLE[kind]
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size * k
		p.CFrame = origin * (at.Rotation + at.Position * k)
		p.Color = style.color
		p.Material = style.material
		p.Shape = shape or Enum.PartType.Block
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CastShadow = false
		p.Parent = colliders
		return p
	end
	local function post(name: string, radius: number, bottom: number, top: number, x: number, z: number, kind: string)
		-- o eixo do cilindro do Roblox é X: deitado de pé com 90° em Z
		solid(name, Vector3.new(top - bottom, radius * 2, radius * 2), CFrame.new(x, (top + bottom) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), kind, Enum.PartType.Cylinder)
	end

	local top = S.floor + S.wall
	local door = S.doorWidth
	local side = S.half - door / 2 -- comprimento de cada trecho de parede ao lado da porta

	solid("Floor", Vector3.new(S.plinth * 2 - INSET * 2, S.floor - INSET, S.plinth * 2 - INSET * 2), CFrame.new(0, (S.floor - INSET) / 2, 0), "Dark")
	solid("Ceiling", Vector3.new(S.half * 2 - 1, 1 - INSET * 2, S.half * 2 - 1), CFrame.new(0, top - 0.5, 0), "Dark")
	for i = 0, 3 do
		local turn = CFrame.Angles(0, i * math.pi / 2, 0)
		for _, s in { -1, 1 } do
			solid("Wall", Vector3.new(side - INSET, S.wall, S.thick - INSET * 2), turn * CFrame.new(s * (door / 2 + side / 2 + INSET / 2), S.floor + S.wall / 2, S.half - S.thick / 2), "Stone")
			post("PorchColumn", 1.1, S.floor, 25, (turn * CFrame.new(s * 10.5, 0, S.porch - 2)).X, (turn * CFrame.new(s * 10.5, 0, S.porch - 2)).Z, "Stone")
		end
		-- acima do arco da porta (o arco do modelo sobe até 23 acima do piso)
		local lintel = S.floor + 23.3
		solid("Lintel", Vector3.new(door + 1, top - lintel - INSET, S.thick - INSET * 2), turn * CFrame.new(0, (top + lintel - INSET) / 2, S.half - S.thick / 2), "Stone")
		-- plataforma da porta e rampa (invisível) por cima dos degraus
		solid("Porch", Vector3.new(S.porchWidth - INSET * 2, S.floor - INSET, S.porch - S.plinth), turn * CFrame.new(0, (S.floor - INSET) / 2, (S.porch + S.plinth) / 2 - INSET), "Dark")
		local ramp = Instance.new("WedgePart")
		ramp.Name = "Ramp"
		ramp.Anchored = true
		ramp.Transparency = 1
		ramp.Size = Vector3.new(S.porchWidth - 2, S.floor - INSET, S.stairs + 0.6) * k
		-- a parte alta da cunha (+Z dela) encosta na plataforma; a baixa aponta para fora
		local at = turn * CFrame.new(0, (S.floor - INSET) / 2, S.porch + S.stairs / 2 + 0.1) * CFrame.Angles(0, math.pi, 0)
		ramp.CFrame = origin * (at.Rotation + at.Position * k)
		ramp.Parent = colliders
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			post("Tower", S.towerRadius - 1.9, 0, top + 14, sx * S.half, sz * S.half, "Stone")
			post("Column", 1.5, S.floor, top - 1, sx * 17.5, sz * 17.5, "Stone")
		end
	end
	post("Dais", 5.2, S.floor, S.floor + 2.1, 0, 0, "Stone")

	-- luzes: cristal do centro, lustre, uma em cada porta e o cristal do alto
	local function light(name: string, at: Vector3, color: Color3, range: number, brightness: number)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = origin * CFrame.new(at * k)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = math.min(range * k, 60)
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = p
		p.Parent = folder
	end
	light("CrystalLight", Vector3.new(0, S.floor + 10, 0), STYLE.Glow.color, S.lightRange, S.lightBrightness * 1.4)
	light("ChandelierLight", Vector3.new(0, 25, 0), rgb(255, 226, 170), S.lightRange, S.lightBrightness)
	light("TopLight", Vector3.new(0, 139, 0), STYLE.Glow.color, 60, 2)
	for i = 0, 3 do
		local at = CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 16, S.porch)
		light("DoorLight", at.Position, rgb(255, 226, 170), 30, S.lightBrightness)
		local corner = CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(20, 14, 20)
		light("CornerLight", corner.Position, rgb(190, 170, 255), 32, S.lightBrightness * 0.8)
	end

	buildShop(folder, colliders, origin, k)

	folder.Parent = workspace
	return true
end

return Sanctum
