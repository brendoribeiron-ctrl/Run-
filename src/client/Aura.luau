--!strict
-- Aura estilo "spin": arcos de luz em meia-lua girando em volta do boneco em anéis inclinados,
-- um anel fino de luz por fora, estrelinhas piscando, poeira brilhante e um brilho suave no
-- corpo. Por baixo disso, a energia que o boneco exala: labaredas coloridas subindo do chão
-- com uma sombra escura atrás, chama nas duas mãos, riscos de luz subindo e uma poça de luz no
-- chão. Cada aura de Config.Auras tem o próprio desenho (quantos anéis, velocidade, cor de
-- destaque e um efeito extra: neve, bolhas, raios, clarões, vazio).
--
-- Os arcos são Trails: dois pontos giram num círculo e a trilha que deixam vira a meia-lua.
-- A força (Aura.strength) cresce com o Poder: aura fraca tem poucos arcos, finos e apagados.
-- A carga (boost) acelera e abre os anéis; a corrida (sprint) liga os rastros nas mãos e pés.
--
-- Cada cliente monta a aura de TODOS os jogadores (efeito criado no cliente não replica). A do
-- jogador local é comandada pelo resto do cliente (setBoost, setSprint...). A dos outros sai do
-- que o servidor replica: atributos Power e Aura, "Charging" (segurando a carga), "Racing"
-- (correndo no corredor) e a velocidade do boneco.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local RunMath = require(ReplicatedStorage.Shared.RunMath)
local Fx = require(script.Parent.Fx)

local localPlayer = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BASE_COLOR = Color3.fromRGB(255, 120, 20) -- antes do segundo tier
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local FX = Config.AuraFx
local MAX_RINGS = 4
-- inclinação de cada anel (graus em X e Z), altura do centro e sentido do giro
local RINGS = {
	{ tilt = Vector2.new(22, 12), height = -0.3, spin = 1 },
	{ tilt = Vector2.new(-30, -16), height = 0.5, spin = -1 },
	{ tilt = Vector2.new(14, -40), height = -1.0, spin = 1 },
	{ tilt = Vector2.new(-12, 36), height = 1.2, spin = -1 },
}

local Aura = {}

-- Uma lâmina: dois pontos que giram juntos e a trilha entre eles.
type Blade = { top: Attachment, bottom: Attachment, trail: Trail, ring: number, phase: number }
type State = {
	player: Player,
	rig: Part?, -- peça ancorada no centro do boneco: os pontos dos arcos giram dentro dela
	blades: { Blade },
	halo: Blade?,
	stars: ParticleEmitter?,
	motes: ParticleEmitter?,
	flames: ParticleEmitter?, -- labaredas coloridas subindo
	shade: ParticleEmitter?, -- sombra escura atrás das labaredas
	streaks: ParticleEmitter?, -- riscos finos de luz subindo
	pool: ParticleEmitter?, -- poça de luz deitada no chão
	hands: { ParticleEmitter }, -- chama em cada mão
	extra: ParticleEmitter?,
	extraKind: string?,
	light: PointLight?,
	outline: Highlight?,
	trails: { Trail },
	forcedTrails: boolean,
	root: BasePart?,
	base: Part?,
	boost: number,
	sprint: number,
	angle: number,
	nextArc: number,
	hidden: boolean,
}

local states: { [Player]: State } = {}
local rng = Random.new()

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { player = player, blades = {}, trails = {}, hands = {}, forcedTrails = false, boost = 0, sprint = 0, angle = 0, nextArc = 0, hidden = false } :: State
		states[player] = state
	end
	return state
end
local me = stateOf(localPlayer)

local function infoOf(player: Player): any
	return Config.AuraById[player:GetAttribute("Aura") :: any]
end

local function tierOf(player: Player): number
	local power = player:GetAttribute("Power")
	return if type(power) == "number" then RunMath.powerTier(power) else 0
end

-- Força da aura, de 0 a 1: zero sem aura equipada; com aura, nasce fraca e cresce com o Poder.
local function strengthOf(player: Player): number
	if not infoOf(player) then
		return 0
	end
	local power = player:GetAttribute("Power")
	local value = if type(power) == "number" then math.max(power, 1) else 1
	local progress = math.clamp(math.log(value / FX.startPower) / math.log(FX.fullPower / FX.startPower), 0, 1)
	return FX.minStrength + (1 - FX.minStrength) * progress
end

local function colorOf(player: Player): Color3
	-- aura equipada no painel AURAS: cor própria (a primeira acompanha o tier do Poder)
	local equipped = infoOf(player)
	if equipped and not equipped.followTier then
		return equipped.color
	end
	local tier = tierOf(player)
	-- Common é cinza: a aura só troca de cor a partir do segundo tier
	return if tier >= 2 then Config.Rarities[tier].color else BASE_COLOR
end

function Aura.tier(): number
	return tierOf(localPlayer)
end

function Aura.strength(): number
	return strengthOf(localPlayer)
end

function Aura.color(): Color3
	return colorOf(localPlayer)
end

-- Cor da aura de qualquer jogador (efeitos dos outros, em Others.luau).
function Aura.colorOf(player: Player): Color3
	return colorOf(player)
end

-- Quantos anéis a aura mostra agora: os do desenho dela, liberados aos poucos com a força.
local function ringsOf(player: Player, k: number): number
	local info = infoOf(player)
	if not info or k <= 0 then
		return 0
	end
	return math.clamp(math.floor(1 + (info.rings - 1) * math.clamp((k - FX.minStrength) / (1 - FX.minStrength) * 1.25, 0, 1) + 0.5), 1, MAX_RINGS)
end

-- Efeito extra de cada aura: um emissor a mais, configurado pelo tipo.
local function setupExtra(e: ParticleEmitter, kind: string)
	e.Texture = SPARK
	e.LightEmission = 1
	e.Brightness = 3
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.zero
	e.Drag = 0
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	if kind == "snow" then
		-- flocos caindo devagar em volta
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(0.4, 1.4)
		e.Acceleration = Vector3.new(0, -3.5, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.42), NumberSequenceKeypoint.new(1, 0) })
	elseif kind == "bubbles" then
		-- gotas subindo
		e.Lifetime = NumberRange.new(0.9, 1.6)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.Acceleration = Vector3.new(0, 7, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.6), NumberSequenceKeypoint.new(1, 0) })
	elseif kind == "rays" then
		-- clarões grandes de estrela
		e.Lifetime = NumberRange.new(0.28, 0.45)
		e.Speed = NumberRange.new(0, 0.5)
		e.Brightness = 6
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.35, 3.6), NumberSequenceKeypoint.new(1, 0) })
	elseif kind == "void" then
		-- fumaça escura sendo puxada para dentro
		e.Texture = SMOKE
		e.LightEmission = 0
		e.Brightness = 1
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(3, 6)
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(1, 0.4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1) })
		return
	else
		-- "lightning" e "none" não usam o emissor (os raios são peças soltas)
		e.Lifetime = NumberRange.new(0.5, 0.8)
		e.Speed = NumberRange.new(0, 1)
		e.Size = NumberSequence.new(0.2)
	end
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
end

local EXTRA_RATE: { [string]: number } = { snow = 22, bubbles = 18, rays = 2.6, void = 14 }

local function apply(state: State)
	local player = state.player
	local boost, sprint, hidden = state.boost, state.sprint, state.hidden
	local info = infoOf(player)
	local color = colorOf(player)
	local accent = if info and info.accent then info.accent else color:Lerp(WHITE, 0.6)
	local k = strengthOf(player)
	local on = k > 0 and not hidden
	local many = 0.25 + 0.75 * k -- quantidade de partículas e brilho
	local rings = ringsOf(player, k)

	-- arcos: pontas brancas, corpo na cor da aura; mais largos e mais opacos com a força
	local fade = 0.55 - 0.45 * k
	for _, blade in state.blades do
		local trail = blade.trail
		trail.Enabled = on and blade.ring <= rings
		trail.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, accent), ColorSequenceKeypoint.new(0.25, color), ColorSequenceKeypoint.new(1, color) })
		trail.Lifetime = FX.arcLength / (FX.spin * (1 + boost * FX.boostSpin))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, fade), NumberSequenceKeypoint.new(0.7, fade + (1 - fade) * 0.4), NumberSequenceKeypoint.new(1, 1) })
		trail.Brightness = 1.1 + 0.9 * k + boost * 2.5
	end
	local halo = state.halo
	if halo then
		halo.trail.Enabled = on and info ~= nil and info.halo == true and k > 0.45
		halo.trail.Color = ColorSequence.new(accent, color)
		halo.trail.Brightness = 1.4 + boost * 3
	end

	-- energia exalando: labaredas, sombra, riscos, poça no chão e mãos acesas
	local big = 0.45 + 0.55 * k
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.86)
	local flames, shade, streaks, pool = state.flames, state.shade, state.streaks, state.pool
	if flames then
		flames.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, accent), ColorSequenceKeypoint.new(0.3, color), ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.4)) })
		flames.Rate = (FX.flameRate + boost * 90) * many
		flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6 * big), NumberSequenceKeypoint.new(0.3, (3.2 + boost * 3) * big), NumberSequenceKeypoint.new(1, 0.4 * big) })
		flames.Speed = NumberRange.new(6 + boost * 10, 11 + boost * 16)
		flames.Enabled = on
	end
	if shade then
		shade.Color = ColorSequence.new(dark)
		shade.Rate = (FX.flameRate * 0.5 + boost * 40) * many
		shade.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2 * big), NumberSequenceKeypoint.new(0.3, (4.4 + boost * 3.5) * big), NumberSequenceKeypoint.new(1, 0.6 * big) })
		shade.Enabled = on and k > 0.3
	end
	if streaks then
		streaks.Color = ColorSequence.new(accent, color)
		streaks.Rate = (10 + boost * 50) * many
		streaks.Enabled = on
	end
	if pool then
		pool.Color = ColorSequence.new(color)
		pool.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, (9 + boost * 6) * big), NumberSequenceKeypoint.new(1, (13 + boost * 8) * big) })
		pool.Rate = 5
		pool.Enabled = on
	end
	for _, hand in state.hands do
		hand.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.3, accent), ColorSequenceKeypoint.new(1, color) })
		hand.Rate = (26 + boost * 50) * many
		hand.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * big), NumberSequenceKeypoint.new(0.3, 1.25 * big), NumberSequenceKeypoint.new(1, 0.1) })
		hand.Enabled = on and k > 0.3
	end

	local stars, motes, extra, light, outline = state.stars, state.motes, state.extra, state.light, state.outline
	if stars then
		stars.Color = ColorSequence.new(accent, color)
		stars.Rate = (9 + boost * 26) * many
		stars.Enabled = on
	end
	if motes then
		motes.Color = ColorSequence.new(color)
		motes.Rate = (26 + boost * 70 + sprint * 20) * many
		motes.Speed = NumberRange.new(2 + boost * 6, 5 + boost * 12)
		motes.Enabled = on
	end
	if extra then
		local kind = if info then info.extra else "none"
		if kind ~= state.extraKind then
			state.extraKind = kind
			setupExtra(extra, kind)
		end
		extra.Color = if kind == "void" then ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.75)) else ColorSequence.new(WHITE, accent)
		extra.Rate = (EXTRA_RATE[kind] or 0) * many * (1 + boost)
		extra.Enabled = on and EXTRA_RATE[kind] ~= nil and k > 0.35
	end
	if light then
		light.Color = color
		light.Brightness = (2 + boost * 5) * many
		light.Range = 12 + 10 * k + boost * 14
		light.Enabled = on
	end
	if outline then
		outline.OutlineColor = accent
		outline.FillColor = color
		outline.FillTransparency = 1 - (0.3 + boost * 0.3) * k -- o corpo inteiro fica tingido de luz
		outline.OutlineTransparency = 0.6 - 0.6 * k
		outline.Enabled = on
	end
	for _, t in state.trails do
		t.Color = ColorSequence.new(WHITE, color)
		t.Enabled = not hidden and (sprint > 0.5 or state.forcedTrails)
	end
end

-- Some com a aura inteira enquanto um painel está aberto: com a câmera atrás do ombro, os
-- arcos passariam na frente da tela.
function Aura.setHidden(on: boolean)
	if me.hidden == on then
		return
	end
	me.hidden = on
	if on then
		for _, particles in { me.stars, me.motes, me.extra, me.flames, me.shade, me.streaks, me.pool } do
			if particles then
				particles:Clear()
			end
		end
		for _, hand in me.hands do
			hand:Clear()
		end
	end
	apply(me)
end

-- 0 = parado, 1 = carga cheia
function Aura.setBoost(value: number)
	me.boost = math.clamp(value, 0, 1)
	apply(me)
end

local function setSprint(state: State, value: number)
	local clamped = math.clamp(value, 0, 1)
	if math.abs(clamped - state.sprint) > 0.05 or (clamped == 0) ~= (state.sprint == 0) then
		state.sprint = clamped
		apply(state)
	end
end

-- 0 = andando, 1 = correndo
function Aura.setSprint(value: number)
	setSprint(me, value)
end

-- Liga os rastros mesmo sem corrida (dash, largada no corredor).
function Aura.forceTrails(on: boolean)
	if me.forcedTrails ~= on then
		me.forcedTrails = on
		apply(me)
	end
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

local function dropLoose(state: State)
	if state.rig then
		state.rig:Destroy()
		state.rig = nil
	end
	table.clear(state.blades)
	state.halo = nil
end

local function blade(rig: Part, ring: number, phase: number, taper: boolean): Blade
	local top = Instance.new("Attachment")
	top.Parent = rig
	local bottom = Instance.new("Attachment")
	bottom.Parent = rig
	local trail = Instance.new("Trail")
	trail.Name = "AuraArc"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.FaceCamera = true
	trail.LightEmission = 0.55 -- menos que 1: a cor da aura não vira branco
	trail.LightInfluence = 0
	trail.MinLength = 0.02
	trail.Enabled = false
	-- meia-lua: nasce fina, engrossa e afina de novo na cauda
	trail.WidthScale = if taper
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.25, 1), NumberSequenceKeypoint.new(1, 0) })
		else NumberSequence.new(1)
	trail.Parent = rig
	return { top = top, bottom = bottom, trail = trail, ring = ring, phase = phase }
end

local function emitter(parent: Instance, name: string, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.LightInfluence = 0
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = false
	e.Enabled = false
	e.Parent = parent
	return e
end

local function attach(state: State, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or state.player.Character ~= character then
		return
	end
	state.root = root

	-- volume invisível em volta do corpo: as partículas nascem dentro dele
	local base = Instance.new("Part")
	base.Name = "AuraBase"
	base.Size = Vector3.new(7, 6.5, 7)
	base.Transparency = 1
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.Massless = true
	base.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = base
	weld.Parent = base
	base.Parent = character
	state.base = base

	-- estrelinhas que piscam (crescem girando e somem)
	local s = emitter(base, "Stars", SPARK)
	s.LightEmission = 0.7
	s.Brightness = 2.5
	s.Lifetime = NumberRange.new(0.45, 0.9)
	s.Speed = NumberRange.new(0.2, 1.2)
	s.SpreadAngle = Vector2.new(180, 180)
	s.Rotation = NumberRange.new(0, 360)
	s.RotSpeed = NumberRange.new(-140, 140)
	s.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 1.15), NumberSequenceKeypoint.new(1, 0) })
	s.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) })
	state.stars = s

	-- poeira brilhante saindo para fora
	local m = emitter(base, "Motes", SPARK)
	m.LightEmission = 0.6
	m.Brightness = 2
	m.Lifetime = NumberRange.new(0.5, 1.1)
	m.SpreadAngle = Vector2.new(180, 180)
	m.Drag = 2.5
	m.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	state.motes = m

	local x = emitter(base, "Extra", SPARK)
	state.extra = x
	state.extraKind = nil

	-- base nos pés: as labaredas nascem numa caixa baixa e sobem
	local feet = Instance.new("Part")
	feet.Name = "AuraFeet"
	feet.Size = Vector3.new(3.6, 0.4, 3)
	feet.Transparency = 1
	feet.CanCollide = false
	feet.CanQuery = false
	feet.CanTouch = false
	feet.Massless = true
	feet.CFrame = root.CFrame * CFrame.new(0, -2.7, 0)
	local feetWeld = Instance.new("WeldConstraint")
	feetWeld.Part0 = root
	feetWeld.Part1 = feet
	feetWeld.Parent = feet
	feet.Parent = character
	local function rising(name: string, texture: string): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = texture
		e.LightInfluence = 0
		e.EmissionDirection = Enum.NormalId.Top
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.LockedToPart = false
		e.Enabled = false
		e.Parent = feet
		return e
	end
	local shade = rising("Shade", FIRE)
	shade.LightEmission = 0
	shade.ZOffset = -1.6
	shade.Lifetime = NumberRange.new(0.6, 1)
	shade.Speed = NumberRange.new(6, 10)
	shade.SpreadAngle = Vector2.new(18, 18)
	shade.Rotation = NumberRange.new(-30, 30)
	shade.RotSpeed = NumberRange.new(-50, 50)
	shade.Squash = NumberSequence.new(0.4)
	shade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 1) })
	state.shade = shade
	local flames = rising("Flames", FIRE)
	flames.LightEmission = 0.8
	flames.Brightness = 3
	flames.ZOffset = -0.6
	flames.Lifetime = NumberRange.new(0.5, 0.95)
	flames.SpreadAngle = Vector2.new(12, 12)
	flames.Rotation = NumberRange.new(-20, 20)
	flames.RotSpeed = NumberRange.new(-40, 40)
	flames.Squash = NumberSequence.new(0.65) -- estica na vertical: labaredas altas
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 1) })
	state.flames = flames
	-- riscos de luz: faíscas muito esticadas subindo rápido
	local streaks = rising("Streaks", SPARK)
	streaks.LightEmission = 0.9
	streaks.Brightness = 3
	streaks.Lifetime = NumberRange.new(0.35, 0.7)
	streaks.Speed = NumberRange.new(14, 24)
	streaks.SpreadAngle = Vector2.new(6, 6)
	streaks.Squash = NumberSequence.new(2.6)
	streaks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	state.streaks = streaks
	-- poça de luz: partículas grandes e moles deitadas no chão, quase paradas
	local pool = rising("Pool", SMOKE)
	pool.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pool.LightEmission = 0.9
	pool.Brightness = 2
	pool.ZOffset = -2
	pool.Lifetime = NumberRange.new(0.9, 1.3)
	pool.Speed = NumberRange.new(0.01, 0.01)
	pool.Rotation = NumberRange.new(0, 360)
	pool.RotSpeed = NumberRange.new(-20, 20)
	pool.LockedToPart = true
	pool.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) })
	state.pool = pool
	-- chama nas mãos
	table.clear(state.hands)
	task.spawn(function()
		for _, name in { "RightHand", "LeftHand" } do
			local hand = character:WaitForChild(name, 5)
			if hand and hand:IsA("BasePart") then
				local e = Instance.new("ParticleEmitter")
				e.Name = "AuraHand"
				e.Texture = FIRE
				e.LightInfluence = 0
				e.LightEmission = 0.9
				e.Brightness = 4
				e.Lifetime = NumberRange.new(0.25, 0.5)
				e.Speed = NumberRange.new(2, 4.5)
				e.SpreadAngle = Vector2.new(25, 25)
				e.EmissionDirection = Enum.NormalId.Top
				e.Rotation = NumberRange.new(-30, 30)
				e.Squash = NumberSequence.new(0.4)
				e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
				e.Enabled = false
				e.Parent = hand
				table.insert(state.hands, e)
			end
		end
		apply(state)
	end)

	local l = Instance.new("PointLight")
	l.Name = "AuraLight"
	l.Shadows = false
	l.Enabled = false
	l.Parent = root
	state.light = l

	local h = Instance.new("Highlight")
	h.Name = "AuraOutline"
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Enabled = false
	h.Parent = character
	state.outline = h

	-- rastros da corrida: fitas finas e brilhantes nas mãos e nos pés, uma faixa suave nas costas
	table.clear(state.trails)
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
		table.insert(state.trails, t)
	end
	task.spawn(function()
		for _, name in { "RightHand", "LeftHand", "RightFoot", "LeftFoot" } do
			ribbon(character:WaitForChild(name, 5), 0.3, 0.45, 0.05)
		end
		ribbon(character:WaitForChild("UpperTorso", 5), 0.8, 0.3, 0.6)
		apply(state)
	end)

	-- peça ancorada que acompanha o boneco sem girar com ele: os arcos giram dentro dela
	dropLoose(state)
	local rig = Fx.part(Vector3.one, CFrame.new(root.Position), BASE_COLOR)
	rig.Name = "AuraRig"
	rig.Transparency = 1
	state.rig = rig
	for ring = 1, MAX_RINGS do
		for half = 0, 1 do
			table.insert(state.blades, blade(rig, ring, half * math.pi + ring * 0.9, true))
		end
	end
	local halo = blade(rig, 0, 0, false)
	halo.trail.Lifetime = 2 * math.pi / FX.haloSpin * 0.96 -- quase uma volta inteira: fecha o anel
	halo.trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.8, 0.4), NumberSequenceKeypoint.new(1, 1) })
	state.halo = halo
	apply(state)
end

-- Outros jogadores: a carga e a corrida saem do que o servidor replica.
local function follow(state: State, root: BasePart, dt: number)
	local player = state.player
	local charging = player:GetAttribute("Charging") == true
	local boost = if charging then math.min(state.boost + dt / Config.Run.chargeTime, 1) else math.max(state.boost - dt * 4, 0)
	local racing = player:GetAttribute("Racing") == true
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local level = player:GetAttribute("Stat_speed")
	local walk = Config.Move.walk + (if type(level) == "number" then level * Config.Stats.speed.perLevel else 0)
	local sprint = if racing then 1 else math.clamp((speed - walk - 2) / math.max(Config.Move.sprintBonus - 4, 1), 0, 1)
	if state.forcedTrails ~= racing then
		state.forcedTrails = racing
		state.sprint = -1 -- força o apply logo abaixo
	end
	if math.abs(boost - state.boost) > 0.02 or (boost == 0) ~= (state.boost == 0) then
		state.boost = boost
		state.sprint = sprint
		apply(state)
	else
		setSprint(state, sprint)
	end
end

local function animate(state: State, now: number, dt: number)
	local rig, root = state.rig, state.root
	if not rig or not root or not root.Parent then
		return
	end
	local k = strengthOf(state.player)
	if state.hidden or k <= 0 then
		return
	end
	local info = infoOf(state.player)
	local boost = state.boost
	rig.CFrame = CFrame.new(root.Position)

	-- o giro acelera na carga; cada aura tem o próprio ritmo
	local speed = FX.spin * (if info then info.spin else 1) * (1 + boost * FX.boostSpin)
	state.angle += speed * dt
	local pulse = 0.5 + 0.5 * math.sin(now * 2.2)
	local size = (0.72 + 0.28 * k) * (1 + boost * 0.35)
	local width = FX.arcWidth * (0.45 + 0.55 * k) * (1 + boost * 0.5)
	for _, blade in state.blades do
		if blade.trail.Enabled then
			local ring = RINGS[blade.ring]
			local theta = state.angle * ring.spin + blade.phase
			local radius = (FX.radius + blade.ring * 0.35 + pulse * 0.15) * size
			local frame = CFrame.new(0, ring.height * size, 0) * CFrame.Angles(math.rad(ring.tilt.X), 0, math.rad(ring.tilt.Y))
			local point = frame * Vector3.new(math.cos(theta) * radius, 0, math.sin(theta) * radius)
			local up = frame.UpVector * (width / 2)
			blade.top.Position = point + up
			blade.bottom.Position = point - up
		end
	end
	local halo = state.halo
	if halo and halo.trail.Enabled then
		local theta = now * FX.haloSpin
		local radius = (FX.radius + 2.1) * size
		local frame = CFrame.Angles(math.rad(8), 0, math.rad(-6))
		local point = frame * Vector3.new(math.cos(theta) * radius, -0.2, math.sin(theta) * radius)
		halo.top.Position = point + Vector3.new(0, 0.09, 0)
		halo.bottom.Position = point - Vector3.new(0, 0.09, 0)
	end

	-- raios: só na aura de tempestade (sempre) e em qualquer aura durante a carga
	local stormy = info ~= nil and info.extra == "lightning"
	if (stormy or boost > 0.3) and now >= state.nextArc then
		state.nextArc = now + (if stormy then 0.22 else 0.4) * rng:NextNumber(0.6, 1.4) / math.max(k * (1 + boost * 2), 0.15)
		arc(root.Position, colorOf(state.player):Lerp(WHITE, 0.7), 3 + boost * 4)
		if boost > 0.5 then
			arc(root.Position, WHITE, 4 + boost * 4)
		end
	end
end

local function watch(player: Player)
	local state = stateOf(player)
	player.CharacterAdded:Connect(function(character)
		attach(state, character)
	end)
	if player.Character then
		task.spawn(attach, state, player.Character)
	end
	local function refresh()
		apply(state)
	end
	player:GetAttributeChangedSignal("Power"):Connect(refresh)
	player:GetAttributeChangedSignal("Aura"):Connect(refresh)
end

-- Estado do efeito do jogador local e quantos jogadores têm aura montada; usado pelos testes.
function Aura.debug(): { [string]: any }
	local built = 0
	for _, state in states do
		if state.stars then
			built += 1
		end
	end
	local arcs = 0
	for _, blade in me.blades do
		if blade.trail.Enabled then
			arcs += 1
		end
	end
	return {
		strength = Aura.strength(),
		emitting = me.stars ~= nil and me.stars.Enabled,
		rate = if me.stars then me.stars.Rate else 0,
		lit = me.light ~= nil and me.light.Enabled,
		flames = me.flames ~= nil and me.flames.Enabled,
		flameRate = if me.flames then me.flames.Rate else 0,
		hands = #me.hands,
		pool = me.pool ~= nil and me.pool.Enabled,
		players = built,
		arcs = arcs,
		halo = me.halo ~= nil and me.halo.trail.Enabled,
		extra = if me.extra and me.extra.Enabled then me.extraKind else "none",
	}
end

function Aura.start()
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			dropLoose(state)
			states[player] = nil
		end
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	local last = os.clock()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		for _, state in states do
			local root = state.root
			if state ~= me and root and root.Parent then
				follow(state, root, dt)
			end
			animate(state, now, dt)
		end
	end)
end

return Aura
