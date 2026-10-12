--!strict
-- Aura estilo reiatsu, em camadas (de trás para a frente):
--   chamas escuras largas (contorno) -> chamas coloridas altas -> núcleo branco -> faíscas,
--   mais contorno luminoso no corpo, névoa rasteira, casca de energia, pedras flutuando,
--   arcos elétricos e luz.
-- A cor segue o tier do Poder; a carga (boost) e a corrida (sprint) fazem tudo crescer.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local RunMath = require(ReplicatedStorage.Shared.RunMath)
local Fx = require(script.Parent.Fx)

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BASE_COLOR = Color3.fromRGB(255, 120, 20) -- antes do segundo tier
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local ROCKS = 8

local Aura = {}

local dark: ParticleEmitter? = nil
local flames: ParticleEmitter? = nil
local core: ParticleEmitter? = nil
local sparks: ParticleEmitter? = nil
local light: PointLight? = nil
local outline: Highlight? = nil
local trails: { Trail } = {}
local forcedTrails = false
local mist: ParticleEmitter? = nil
local shell: Part? = nil
local rocks: { Part } = {}
local rootPart: BasePart? = nil
local boost = 0
local sprint = 0
local nextArc = 0
local rng = Random.new()

function Aura.tier(): number
	local power = player:GetAttribute("Power")
	return if type(power) == "number" then RunMath.powerTier(power) else 0
end

function Aura.color(): Color3
	local tier = Aura.tier()
	-- Common é cinza: a aura só troca de cor a partir do segundo tier
	return if tier >= 2 then Config.Rarities[tier].color else BASE_COLOR
end

local function sizes(peak: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, peak * 0.55),
		NumberSequenceKeypoint.new(0.25, peak),
		NumberSequenceKeypoint.new(1, peak * 0.15),
	})
end

local function apply()
	local color = Aura.color()
	local grow = boost + Aura.tier() * 0.07 + sprint * 0.2
	local shadow = color:Lerp(Color3.new(0, 0, 0), 0.82)
	-- correndo, as partículas ficam para trás: vida curta para não virar um muro de fogo
	local life = 1 - sprint * 0.6
	if dark then
		dark.Lifetime = NumberRange.new(0.7 * life, 1.15 * life)
		dark.Color = ColorSequence.new(shadow)
		dark.Rate = 34 + boost * 70
		dark.Size = sizes(5.2 + grow * 4)
		dark.Speed = NumberRange.new(7 + boost * 9, 11 + boost * 14)
	end
	if flames then
		flames.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.75)),
			ColorSequenceKeypoint.new(0.35, color),
			ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.35)),
		})
		flames.Lifetime = NumberRange.new(0.6 * life, 1.1 * life)
		flames.Rate = 55 + boost * 130 + sprint * 40
		flames.Size = sizes(4 + grow * 3.4)
		flames.Speed = NumberRange.new(9 + boost * 12, 15 + boost * 20)
	end
	if core then
		core.Color = ColorSequence.new(WHITE, color:Lerp(WHITE, 0.5))
		core.Rate = 30 + boost * 80
		core.Size = sizes(2.2 + grow * 1.6)
	end
	if sparks then
		sparks.Color = ColorSequence.new(color:Lerp(WHITE, 0.7))
		sparks.Rate = 26 + boost * 90 + sprint * 20
		sparks.Speed = NumberRange.new(6 + boost * 14, 14 + boost * 24)
	end
	if light then
		light.Color = color
		light.Brightness = 2.5 + boost * 5
		light.Range = 14 + boost * 16
	end
	if outline then
		outline.OutlineColor = color:Lerp(WHITE, 0.35)
		outline.FillColor = color
		outline.FillTransparency = 0.82 - boost * 0.3
	end
	for _, t in trails do
		t.Color = ColorSequence.new(WHITE, color)
		t.Enabled = sprint > 0.5 or forcedTrails
	end
	if mist then
		mist.Color = ColorSequence.new(color:Lerp(WHITE, 0.35), color:Lerp(Color3.new(0, 0, 0), 0.4))
		mist.Rate = 7 + boost * 30
	end
	if shell then
		shell.Color = color:Lerp(WHITE, 0.2)
	end
	for i, rock in rocks do
		if i % 2 == 0 then
			rock.Color = color:Lerp(WHITE, 0.3)
		end
	end
end

-- 0 = parado, 1 = carga cheia
function Aura.setBoost(value: number)
	boost = math.clamp(value, 0, 1)
	apply()
end

-- 0 = andando, 1 = correndo
function Aura.setSprint(value: number)
	local clamped = math.clamp(value, 0, 1)
	if math.abs(clamped - sprint) > 0.05 or (clamped == 0) ~= (sprint == 0) then
		sprint = clamped
		apply()
	end
end

-- Liga os rastros mesmo sem corrida (dash, largada no corredor).
function Aura.forceTrails(on: boolean)
	if forcedTrails ~= on then
		forcedTrails = on
		apply()
	end
end

local function emitter(parent: Instance, name: string, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.LightInfluence = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = false
	e.Parent = parent
	return e
end

-- Arco elétrico: linha quebrada de 3 segmentos que pisca por um instante perto do corpo.
local function arc(origin: Vector3, color: Color3, reach: number)
	local angle = rng:NextNumber(0, math.pi * 2)
	local point = origin + Vector3.new(math.cos(angle) * reach * 0.5, rng:NextNumber(-1.5, 2.5), math.sin(angle) * reach * 0.5)
	for _ = 1, 3 do
		local step = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 1.2), rng:NextNumber(-1, 1)) * reach * 0.45
		local nextPoint = point + step
		local segment = Fx.part(Vector3.new(0.07, 0.07, step.Magnitude), CFrame.lookAt((point + nextPoint) / 2, nextPoint), color, Enum.Material.Neon)
		Debris:AddItem(segment, rng:NextNumber(0.05, 0.11))
		point = nextPoint
	end
end

local function attach(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	rootPart = root

	-- base invisível nos pés: os emissores nascem num volume, não num ponto
	local base = Instance.new("Part")
	base.Name = "AuraBase"
	base.Size = Vector3.new(3.4, 0.4, 2.6)
	base.Transparency = 1
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.Massless = true
	base.CFrame = root.CFrame * CFrame.new(0, -2.6, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = base
	weld.Parent = base
	base.Parent = character

	local d = emitter(base, "Dark", FIRE)
	d.LightEmission = 0
	d.ZOffset = -1.5
	d.Lifetime = NumberRange.new(0.7, 1.15)
	d.SpreadAngle = Vector2.new(16, 16)
	d.Rotation = NumberRange.new(-30, 30)
	d.RotSpeed = NumberRange.new(-50, 50)
	d.Squash = NumberSequence.new(0.35)
	d.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dark = d

	local f = emitter(base, "Flames", FIRE)
	f.LightEmission = 0.75
	f.Brightness = 4
	f.ZOffset = -0.5
	f.Lifetime = NumberRange.new(0.6, 1.1)
	f.SpreadAngle = Vector2.new(10, 10)
	f.Rotation = NumberRange.new(-20, 20)
	f.RotSpeed = NumberRange.new(-40, 40)
	f.Squash = NumberSequence.new(0.6) -- estica na vertical: labaredas altas
	f.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.3), NumberSequenceKeypoint.new(1, 1) })
	flames = f

	local c = emitter(base, "Core", FIRE)
	c.LightEmission = 1
	c.Brightness = 6
	c.Lifetime = NumberRange.new(0.3, 0.55)
	c.Speed = NumberRange.new(8, 13)
	c.SpreadAngle = Vector2.new(6, 6)
	c.Squash = NumberSequence.new(0.5)
	c.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	core = c

	local s = emitter(base, "Sparks", SPARK)
	s.LightEmission = 1
	s.Brightness = 5
	s.Lifetime = NumberRange.new(0.7, 1.4)
	s.SpreadAngle = Vector2.new(40, 40)
	s.Drag = 1.5
	s.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks = s

	local l = Instance.new("PointLight")
	l.Name = "AuraLight"
	l.Shadows = false
	l.Parent = root
	light = l

	local h = Instance.new("Highlight")
	h.Name = "AuraOutline"
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.OutlineTransparency = 0
	h.Parent = character
	outline = h

	-- rastros da corrida: fitas finas e brilhantes nas mãos e nos pés, uma faixa suave nas costas
	table.clear(trails)
	local function ribbon(part: Instance?, half: number, lifetime: number, transparency: number)
		if not part or not part:IsA("BasePart") then
			return
		end
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(0, half, 0)
		a.Parent = part
		local b = Instance.new("Attachment")
		b.Position = Vector3.new(0, -half, 0)
		b.Parent = part
		local t = Instance.new("Trail")
		t.Name = "SpeedTrail"
		t.Attachment0 = a
		t.Attachment1 = b
		t.Lifetime = lifetime
		t.MinLength = 0.05
		t.LightEmission = 1
		t.LightInfluence = 0
		t.Brightness = 3
		t.FaceCamera = true
		t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, transparency), NumberSequenceKeypoint.new(0.6, transparency + (1 - transparency) * 0.5), NumberSequenceKeypoint.new(1, 1) })
		t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		t.Enabled = false
		t.Parent = part
		table.insert(trails, t)
	end
	task.spawn(function()
		for _, name in { "RightHand", "LeftHand", "RightFoot", "LeftFoot" } do
			ribbon(character:WaitForChild(name, 5), 0.3, 0.45, 0.05)
		end
		ribbon(character:WaitForChild("UpperTorso", 5), 0.8, 0.3, 0.6)
		apply()
	end)

	-- névoa rasteira: fumaça larga e baixa em volta dos pés, tingida pela cor da aura
	local mistBase = Instance.new("Part")
	mistBase.Name = "AuraMist"
	mistBase.Size = Vector3.new(9, 0.3, 9)
	mistBase.Transparency = 1
	mistBase.CanCollide = false
	mistBase.CanQuery = false
	mistBase.CanTouch = false
	mistBase.Massless = true
	mistBase.CFrame = root.CFrame * CFrame.new(0, -2.8, 0)
	local mistWeld = Instance.new("WeldConstraint")
	mistWeld.Part0 = root
	mistWeld.Part1 = mistBase
	mistWeld.Parent = mistBase
	mistBase.Parent = character
	local m = emitter(mistBase, "Mist", SMOKE)
	m.LightEmission = 0.35
	m.Lifetime = NumberRange.new(1.1, 1.9)
	m.Speed = NumberRange.new(0.2, 1.2)
	m.Rotation = NumberRange.new(0, 360)
	m.RotSpeed = NumberRange.new(-25, 25)
	m.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) })
	m.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.72), NumberSequenceKeypoint.new(1, 1) })
	mist = m

	-- casca de energia em volta do corpo e pedras flutuando
	if shell then
		shell:Destroy()
	end
	for _, rock in rocks do
		rock:Destroy()
	end
	table.clear(rocks)
	local bubble = Fx.part(Vector3.one * 9, CFrame.identity, BASE_COLOR, Enum.Material.ForceField, Enum.PartType.Ball)
	bubble.Transparency = 1
	shell = bubble
	for i = 1, ROCKS do
		local size = if i % 2 == 0 then 0.28 else 0.45 + (i % 3) * 0.3
		local rock = Fx.part(Vector3.new(size, size * 1.3, size), CFrame.identity, Color3.fromRGB(40, 40, 52), if i % 2 == 0 then Enum.Material.Neon else Enum.Material.Slate)
		rock.Transparency = 1
		rocks[i] = rock
	end
	apply()
end

function Aura.start()
	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end
	player:GetAttributeChangedSignal("Power"):Connect(apply)

	RunService.RenderStepped:Connect(function()
		local bubble, root = shell, rootPart
		if not bubble or not root or not root.Parent then
			return
		end
		local now = os.clock()
		local tier = Aura.tier()
		local pulse = 0.5 + 0.5 * math.sin(now * (3 + boost * 9))

		-- casca: quase invisível parado, forte na carga; respira com o pulso
		local size = 8.5 + boost * 5 + pulse * (0.3 + boost * 0.9)
		bubble.Size = Vector3.one * size
		bubble.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, now * 0.6, 0)
		bubble.Transparency = math.clamp(0.9 - tier * 0.03 - boost * 0.35 - pulse * 0.05, 0.5, 1)

		-- pedras: mais delas a cada tier; sobem e orbitam devagar, aceleram na carga
		local visible = math.min(ROCKS, 2 + tier + math.floor(boost * 3))
		for i, rock in rocks do
			if i <= visible then
				local angle = now * (0.5 + boost * 2.2) * (if i % 2 == 0 then 1 else -0.7) + i * 1.05
				local radius = 3.4 + (i % 3) * 0.9 + boost * 1.5
				local height = -1.6 + (i % 4) * 1.15 + math.sin(now * 1.4 + i * 2) * 0.5 + boost * 1.2
				rock.CFrame = CFrame.new(root.Position + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)) * CFrame.Angles(now * 0.9 + i, now * 0.6, i)
				rock.Transparency = 0
			else
				rock.Transparency = 1
			end
		end

		-- arcos elétricos: raros parado, constantes na carga
		if now >= nextArc then
			nextArc = now + (0.32 - boost * 0.26) * rng:NextNumber(0.6, 1.4)
			arc(root.Position, Aura.color():Lerp(WHITE, 0.7), 3 + boost * 4)
			if boost > 0.5 then
				arc(root.Position, WHITE, 4 + boost * 4)
			end
		end
	end)
end

return Aura
