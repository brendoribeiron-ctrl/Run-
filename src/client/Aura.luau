--!strict
-- Aura toon, em camadas. Cada aura de Config.Auras liga e pinta as camadas do jeito dela:
--   fogo    labaredas de desenho (flipbook) subindo dos pés e do corpo, em duas cores, com uma
--           sombra escura atrás; chama nas duas mãos
--   órbita  o que gira em volta em anéis inclinados: faixas largas de luz, cortes pretos de
--           borda colorida ou fitas finas e rápidas
--   chão    círculo mágico girando (dois, um contra o outro) e/ou vento em espiral abrindo
--   soltos  lascas voando para fora, estrelas piscando, riscos de luz subindo, pilares de luz
--           descendo do céu, raios, neve, bolhas
--
-- As texturas são próprias (src/shared/Textures.luau, desenhadas por
-- tools/blender/aura_textures.py): brancas, a cor entra aqui.
--
-- As órbitas são Trails: dois pontos giram num círculo e a trilha que deixam vira a faixa.
-- O chão é um SurfaceGui deitado numa peça invisível: imagens que giram e crescem.
-- A força (Aura.strength) cresce com o Poder: aura fraca tem pouco fogo, menos anéis, círculo
-- menor. A carga (boost) acelera e abre tudo; a corrida (sprint) liga os rastros nas mãos e pés.
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
local Textures = require(ReplicatedStorage.Shared.Textures)
local Fx = require(script.Parent.Fx)

local localPlayer = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local RED = Color3.fromRGB(255, 50, 30)
local BASE_COLOR = Color3.fromRGB(255, 120, 20) -- antes do segundo tier
local FX = Config.AuraFx
local MAX_RINGS = 4
local GROUND_SIZE = 26 -- lado da peça do chão, em studs: o maior desenho cabe dentro
local PILLARS = 3
-- inclinação de cada anel (graus em X e Z), altura do centro e sentido do giro
local RINGS = {
	{ tilt = Vector2.new(34, 18), height = -0.2, spin = 1 },
	{ tilt = Vector2.new(-40, -22), height = 0.4, spin = -1 },
	{ tilt = Vector2.new(16, -52), height = -0.8, spin = 1 },
	{ tilt = Vector2.new(-14, 50), height = 1.0, spin = -1 },
}

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

-- Estilos de órbita. radial = a faixa fica deitada no plano do anel (lâmina de corte); senão
-- fica em pé, virada para fora (fita em volta do corpo). arc = comprimento, em radianos.
type Orbit = { texture: string, width: number, arc: number, radius: number, speed: number, emission: number, face: boolean, radial: boolean, surge: number, shape: NumberSequence, fade: NumberSequence }
local ORBITS: { [string]: Orbit } = {
	ribbon = { texture = Textures.ribbon, width = 1.7, arc = 3.0, radius = 4.6, speed = 0.5, emission = 0.5, face = false, radial = false, surge = 0.15, shape = seq({ { 0, 0 }, { 0.25, 1 }, { 0.6, 0.8 }, { 1, 0 } }), fade = seq({ { 0, 0.3 }, { 0.65, 0.45 }, { 1, 1 } }) },
	slash = { texture = Textures.slash, width = 1.9, arc = 2.1, radius = 5.0, speed = 0.8, emission = 0, face = false, radial = true, surge = 0.55, shape = seq({ { 0, 0 }, { 0.3, 1 }, { 1, 0 } }), fade = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }) },
	thin = { texture = "", width = 0.42, arc = 2.3, radius = 3.3, speed = 1.45, emission = 0.6, face = true, radial = false, surge = 0.3, shape = seq({ { 0, 0.15 }, { 0.25, 1 }, { 1, 0 } }), fade = seq({ { 0, 0.05 }, { 0.7, 0.4 }, { 1, 1 } }) },
}

local Aura = {}

-- Uma lâmina: dois pontos que giram juntos e a trilha entre eles.
type Blade = { top: Attachment, bottom: Attachment, trail: Trail, ring: number, phase: number }
type Ground = { part: Part, gui: SurfaceGui, pool: ImageLabel, outer: ImageLabel, inner: ImageLabel, winds: { ImageLabel } }
type Pillar = { beam: Beam, low: Attachment, high: Attachment, phase: number, period: number, at: Vector3 }
type State = {
	player: Player,
	rig: Part?, -- peça ancorada no centro do boneco: os pontos das órbitas giram dentro dela
	blades: { Blade },
	orbit: string?, -- estilo já aplicado nas lâminas
	ground: Ground?,
	groundY: number,
	pillars: { Pillar },
	rays: RaycastParams?,
	front: ParticleEmitter?, -- labaredas da frente (cor da aura)
	back: ParticleEmitter?, -- labaredas de trás (segunda cor)
	shade: ParticleEmitter?, -- sombra escura atrás de tudo
	licks: ParticleEmitter?, -- labaredas pequenas saindo do corpo
	shards: ParticleEmitter?,
	stars: ParticleEmitter?,
	streaks: ParticleEmitter?, -- riscos finos de luz subindo
	hands: { ParticleEmitter }, -- chama em cada mão
	extra: ParticleEmitter?,
	extraKind: string?,
	light: PointLight?,
	outline: Highlight?,
	trails: { Trail },
	forcedTrails: boolean,
	root: BasePart?,
	boost: number,
	sprint: number,
	angle: number,
	wind: number,
	nextArc: number,
	hidden: boolean,
}

local states: { [Player]: State } = {}
local rng = Random.new()

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { player = player, blades = {}, pillars = {}, trails = {}, hands = {}, groundY = 0, forcedTrails = false, boost = 0, sprint = 0, angle = 0, wind = 0, nextArc = 0, hidden = false } :: State
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

-- Efeito extra de partículas: neve caindo ou gotas subindo.
local function setupExtra(e: ParticleEmitter, kind: string)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Transparency = seq({ { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } })
	if kind == "snow" then
		e.Texture = Textures.star
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(0.4, 1.4)
		e.Acceleration = Vector3.new(0, -3.5, 0)
		e.Size = seq({ { 0, 0 }, { 0.2, 0.5 }, { 1, 0 } })
	else
		e.Texture = Textures.glow
		e.Lifetime = NumberRange.new(0.9, 1.6)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.Acceleration = Vector3.new(0, 7, 0)
		e.Size = seq({ { 0, 0.15 }, { 0.7, 0.75 }, { 1, 0 } })
	end
end

local EXTRA_RATE: { [string]: number } = { snow = 22, bubbles = 18 }

local function apply(state: State)
	local player = state.player
	local boost, sprint, hidden = state.boost, state.sprint, state.hidden
	local info = infoOf(player)
	local color = colorOf(player)
	local accent: Color3 = if info and info.accent then info.accent else color:Lerp(WHITE, 0.55)
	local second: Color3 = if info and info.second then info.second else color:Lerp(RED, 0.5)
	local dark = color:Lerp(second, 0.5):Lerp(BLACK, 0.66)
	local k = strengthOf(player)
	local on = k > 0 and not hidden
	local many = 0.25 + 0.75 * k -- quantidade de partículas e brilho
	local big = 0.5 + 0.5 * k -- tamanho
	local heat: number = if info then info.flames else 0
	local rings = ringsOf(player, k)

	-- órbitas: o estilo troca textura e forma; a cor e o ritmo mudam a cada chamada
	local kind: string? = if info then info.orbit else nil
	local style = if kind then ORBITS[kind] else nil
	if style and state.orbit ~= kind then
		state.orbit = kind
		for _, blade in state.blades do
			local trail = blade.trail
			trail.Texture = style.texture
			trail.FaceCamera = style.face
			trail.LightEmission = style.emission
			trail.WidthScale = style.shape
		end
	end
	for _, blade in state.blades do
		local trail = blade.trail
		trail.Enabled = on and style ~= nil and blade.ring <= rings
		if style and info then
			local line: Color3 = info.orbitColor or color
			trail.Color = if kind == "slash" then ColorSequence.new(color) else ColorSequence.new({ ColorSequenceKeypoint.new(0, if info.orbitColor then line else accent), ColorSequenceKeypoint.new(0.3, line), ColorSequenceKeypoint.new(1, line) })
			trail.Lifetime = style.arc / (FX.spin * info.spin * style.speed * (1 + boost * FX.boostSpin))
			-- aura fraca: faixas mais apagadas (o corte preto continua opaco, só menor)
			local veil = if kind == "slash" then 0 else 0.45 * (1 - k)
			trail.Transparency = if veil > 0 then seq({ { 0, 0.3 + veil }, { 0.65, 0.45 + veil * 0.5 }, { 1, 1 } }) else style.fade
			trail.Brightness = if kind == "slash" then 1 else 1.2 + 0.6 * k + boost * 2
		end
	end

	-- fogo toon
	local rate = FX.flameRate * heat * many * (1 + boost * 1.6)
	local size = (2.6 + 1.2 * math.min(heat, 1.2)) * big * (1 + boost * 0.45)
	local rise = NumberRange.new(3 + boost * 4, 6 + boost * 7)
	local front, back, shade, licks = state.front, state.back, state.shade, state.licks
	if front then
		front.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, accent), ColorSequenceKeypoint.new(0.45, color), ColorSequenceKeypoint.new(1, color) })
		front.Rate = rate
		front.Size = seq({ { 0, size * 0.85 }, { 1, size * 1.1 } })
		front.Speed = rise
		front.Enabled = on
	end
	if back then
		back.Color = ColorSequence.new(second:Lerp(accent, 0.25), second)
		back.Rate = rate * 0.7
		back.Size = seq({ { 0, size * 1.1 }, { 1, size * 1.4 } })
		back.Speed = rise
		back.Enabled = on
	end
	if shade then
		shade.Color = ColorSequence.new(dark)
		shade.Rate = rate * 0.55
		shade.Size = seq({ { 0, size * 1.35 }, { 1, size * 1.75 } })
		shade.Speed = rise
		shade.Enabled = on and k > 0.3
	end
	if licks then
		licks.Color = ColorSequence.new(accent, color)
		licks.Rate = rate * 0.6
		licks.Size = seq({ { 0, size * 0.45 }, { 1, size * 0.6 } })
		licks.Enabled = on
	end
	for _, hand in state.hands do
		hand.Color = ColorSequence.new(accent, color)
		hand.Rate = (9 + boost * 16) * many
		hand.Size = seq({ { 0, 1.1 * big }, { 1, 1.5 * big } })
		hand.Enabled = on and k > 0.3
	end

	local shards, stars, streaks, extra, light, outline = state.shards, state.stars, state.streaks, state.extra, state.light, state.outline
	if shards then
		shards.Color = ColorSequence.new(accent, color)
		shards.Rate = (9 + boost * 40) * many
		shards.Speed = NumberRange.new(7 + boost * 8, 13 + boost * 14)
		shards.Enabled = on and info ~= nil and info.shards == true
	end
	if stars then
		stars.Color = ColorSequence.new(accent)
		stars.Rate = (6 + boost * 18) * many
		stars.Enabled = on
	end
	if streaks then
		streaks.Color = ColorSequence.new(accent, color)
		streaks.Rate = (7 + boost * 40) * many
		streaks.Enabled = on
	end
	if extra then
		local which: string = if info then info.extra else "none"
		local extraRate = EXTRA_RATE[which]
		if extraRate and which ~= state.extraKind then
			setupExtra(extra, which)
		end
		state.extraKind = which
		extra.Color = ColorSequence.new(WHITE, accent)
		extra.Rate = (extraRate or 0) * many * (1 + boost)
		extra.Enabled = on and extraRate ~= nil and k > 0.35
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
		outline.FillTransparency = 1 - (0.16 + boost * 0.3) * k -- o corpo fica levemente tingido de luz
		outline.OutlineTransparency = 0.6 - 0.6 * k
		outline.Enabled = on
	end

	-- chão e pilares: aqui só cor e o que está ligado; o movimento fica em animate
	local ground = state.ground
	if ground then
		local what: string = if info then info.ground else "none"
		local circle = what == "circle" or what == "both"
		local swirl = what == "swirl" or what == "both"
		ground.gui.Enabled = on and (circle or swirl)
		ground.pool.ImageColor3 = color
		ground.outer.ImageColor3 = color:Lerp(accent, 0.25)
		ground.outer.Visible = circle
		ground.inner.ImageColor3 = accent
		ground.inner.Visible = circle
		for _, wind in ground.winds do
			wind.ImageColor3 = accent
			wind.Visible = swirl
		end
	end
	local pillared = on and info ~= nil and info.extra == "pillars" and k > 0.35
	for _, pillar in state.pillars do
		pillar.beam.Enabled = pillared
		pillar.beam.Color = ColorSequence.new(accent, color)
	end

	for _, t in state.trails do
		t.Color = ColorSequence.new(WHITE, color)
		t.Enabled = not hidden and (sprint > 0.5 or state.forcedTrails)
	end
end

-- Some com a aura inteira enquanto um painel está aberto: com a câmera atrás do ombro, as
-- órbitas passariam na frente da tela.
function Aura.setHidden(on: boolean)
	if me.hidden == on then
		return
	end
	me.hidden = on
	if on then
		for _, particles in { me.front, me.back, me.shade, me.licks, me.shards, me.stars, me.streaks, me.extra } do
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
	if state.ground then
		state.ground.part:Destroy()
		state.ground = nil
	end
	table.clear(state.blades)
	table.clear(state.pillars)
	state.orbit = nil
end

local function blade(rig: Part, ring: number, phase: number): Blade
	local top = Instance.new("Attachment")
	top.Parent = rig
	local bottom = Instance.new("Attachment")
	bottom.Parent = rig
	local trail = Instance.new("Trail")
	trail.Name = "AuraOrbit"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.LightInfluence = 0
	trail.MinLength = 0.08
	trail.Enabled = false
	trail.Parent = rig
	return { top = top, bottom = bottom, trail = trail, ring = ring, phase = phase }
end

local function emitter(parent: Instance, name: string, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.LightInfluence = 0
	e.LockedToPart = false
	e.Enabled = false
	e.Parent = parent
	return e
end

-- Labareda toon: o flipbook faz a chama nascer, ondular e se desfazer; a partícula só sobe.
local function flame(parent: Instance, name: string, depth: number): ParticleEmitter
	local e = emitter(parent, name, Textures.flame)
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.EmissionDirection = Enum.NormalId.Top
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LightEmission = 0.3 -- baixo: a cor fica cheia, de desenho, em vez de estourar em branco
	e.Brightness = 1.5
	e.ZOffset = depth
	e.Lifetime = NumberRange.new(0.6, 0.95)
	e.SpreadAngle = Vector2.new(14, 14)
	e.Rotation = NumberRange.new(-16, 16)
	e.RotSpeed = NumberRange.new(-14, 14)
	e.Transparency = seq({ { 0, 0 }, { 0.85, 0 }, { 1, 1 } })
	return e
end

local function image(parent: Instance, name: string, texture: string, z: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.Image = texture
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.4, 0.4)
	label.ZIndex = z
	label.Parent = parent
	return label
end

local function buildGround(): Ground
	local part = Fx.part(Vector3.new(GROUND_SIZE, 0.1, GROUND_SIZE), CFrame.identity, BASE_COLOR)
	part.Name = "AuraGround"
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Circle"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(640, 640)
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Enabled = false
	gui.Parent = part
	local ground: Ground = {
		part = part,
		gui = gui,
		pool = image(gui, "Pool", Textures.glow, 1),
		outer = image(gui, "Outer", Textures.circle, 3),
		inner = image(gui, "Inner", Textures.circle, 4),
		winds = { image(gui, "WindA", Textures.swirl, 2), image(gui, "WindB", Textures.swirl, 2) },
	}
	return ground
end

local function attach(state: State, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or state.player.Character ~= character then
		return
	end
	state.root = root
	state.groundY = root.Position.Y - 3
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	rays.FilterDescendantsInstances = { character, Fx.folder }
	rays.RespectCanCollide = true
	state.rays = rays

	-- volume invisível em volta do corpo: estrelas, lascas e o efeito extra nascem dentro dele
	local base = Instance.new("Part")
	base.Name = "AuraBase"
	base.Size = Vector3.new(6, 6, 6)
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

	-- estrelas de quatro pontas que piscam (crescem girando e somem)
	local s = emitter(base, "Stars", Textures.star)
	s.Shape = Enum.ParticleEmitterShape.Sphere
	s.LightEmission = 0.6
	s.Brightness = 2.2
	s.Lifetime = NumberRange.new(0.45, 0.9)
	s.Speed = NumberRange.new(0.2, 1.2)
	s.SpreadAngle = Vector2.new(180, 180)
	s.Rotation = NumberRange.new(-20, 20)
	s.RotSpeed = NumberRange.new(-60, 60)
	s.Size = seq({ { 0, 0 }, { 0.4, 1.3 }, { 1, 0 } })
	s.Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } })
	state.stars = s

	-- lascas: cada partícula sorteia um dos quatro cacos e voa de ponta para fora
	local c = emitter(base, "Shards", Textures.shards)
	c.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	c.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	c.FlipbookFramerate = NumberRange.new(1)
	c.FlipbookStartRandom = true
	c.Shape = Enum.ParticleEmitterShape.Sphere
	c.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	c.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	c.Orientation = Enum.ParticleOrientation.VelocityParallel
	c.LightEmission = 0.3
	c.Brightness = 1.6
	c.Lifetime = NumberRange.new(0.4, 0.75)
	c.SpreadAngle = Vector2.new(25, 25)
	c.Drag = 2.6
	c.Size = seq({ { 0, 0.3 }, { 0.2, 1.05 }, { 1, 0 } })
	c.Transparency = seq({ { 0, 0 }, { 0.85, 0 }, { 1, 1 } })
	state.shards = c

	local x = emitter(base, "Extra", Textures.star)
	x.Shape = Enum.ParticleEmitterShape.Sphere
	x.LightEmission = 0.8
	x.Brightness = 2.5
	state.extra = x
	state.extraKind = nil

	-- base nos pés: as labaredas nascem numa caixa baixa e sobem
	local feet = Instance.new("Part")
	feet.Name = "AuraFeet"
	feet.Size = Vector3.new(3.8, 0.4, 3.2)
	feet.Transparency = 1
	feet.CanCollide = false
	feet.CanQuery = false
	feet.CanTouch = false
	feet.Massless = true
	feet.CFrame = root.CFrame * CFrame.new(0, -1.9, 0)
	local feetWeld = Instance.new("WeldConstraint")
	feetWeld.Part0 = root
	feetWeld.Part1 = feet
	feetWeld.Parent = feet
	feet.Parent = character
	local shade = flame(feet, "Shade", -1.6)
	shade.LightEmission = 0
	shade.Brightness = 1
	state.shade = shade
	state.back = flame(feet, "Back", -0.8)
	state.front = flame(feet, "Front", -0.3)
	-- labaredas pequenas saindo do tronco: o fogo abraça o corpo em vez de ficar só no chão
	local licks = flame(root, "AuraLicks", 0.6)
	licks.Lifetime = NumberRange.new(0.45, 0.75)
	licks.Speed = NumberRange.new(2.5, 5)
	licks.SpreadAngle = Vector2.new(35, 35)
	state.licks = licks
	-- riscos de luz subindo rápido
	local streaks = emitter(feet, "Streaks", Textures.streak)
	streaks.EmissionDirection = Enum.NormalId.Top
	streaks.LightEmission = 0.8
	streaks.Brightness = 2.5
	streaks.Lifetime = NumberRange.new(0.35, 0.7)
	streaks.Speed = NumberRange.new(14, 24)
	streaks.SpreadAngle = Vector2.new(6, 6)
	streaks.Rotation = NumberRange.new(90, 90) -- a textura é deitada: em pé, vira risco vertical
	streaks.Size = seq({ { 0, 0.4 }, { 0.3, 1.5 }, { 1, 0.6 } })
	streaks.Transparency = seq({ { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } })
	state.streaks = streaks
	-- chama nas mãos
	table.clear(state.hands)
	task.spawn(function()
		for _, name in { "RightHand", "LeftHand" } do
			local hand = character:WaitForChild(name, 5)
			if hand and hand:IsA("BasePart") then
				local e = flame(hand, "AuraHand", 0.4)
				e.Lifetime = NumberRange.new(0.3, 0.5)
				e.Speed = NumberRange.new(1.5, 3)
				e.SpreadAngle = Vector2.new(20, 20)
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
		t.Transparency = seq({ { 0, transparency }, { 0.6, transparency + (1 - transparency) * 0.5 }, { 1, 1 } })
		t.WidthScale = seq({ { 0, 1 }, { 1, 0 } })
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

	-- peça ancorada que acompanha o boneco sem girar com ele: as órbitas e os pilares vivem nela
	dropLoose(state)
	local rig = Fx.part(Vector3.one, CFrame.new(root.Position), BASE_COLOR)
	rig.Name = "AuraRig"
	rig.Transparency = 1
	state.rig = rig
	for ring = 1, MAX_RINGS do
		for half = 0, 1 do
			table.insert(state.blades, blade(rig, ring, half * math.pi + ring * 0.9))
		end
	end
	for index = 1, PILLARS do
		local low = Instance.new("Attachment")
		low.Parent = rig
		local high = Instance.new("Attachment")
		high.Parent = rig
		local beam = Instance.new("Beam")
		beam.Name = "AuraPillar"
		beam.Attachment0 = low
		beam.Attachment1 = high
		beam.Texture = Textures.streak
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureSpeed = 0
		beam.FaceCamera = true
		beam.LightEmission = 0.9
		beam.LightInfluence = 0
		beam.Brightness = 2
		beam.Segments = 1
		beam.Transparency = seq({ { 0, 0.05 }, { 0.5, 0.35 }, { 1, 1 } })
		beam.Width0 = 0
		beam.Width1 = 0
		beam.Enabled = false
		beam.Parent = rig
		table.insert(state.pillars, { beam = beam, low = low, high = high, phase = index / PILLARS, period = 1.1 + index * 0.23, at = Vector3.zero })
	end
	state.ground = buildGround()
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

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
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
	local origin = root.Position
	rig.CFrame = CFrame.new(origin)
	local size = (0.72 + 0.28 * k) * (1 + boost * 0.35)
	local breath = math.sin(now * 2.2)

	-- órbitas: o giro acelera na carga e pulsa (arranca e alivia) conforme o estilo
	local style = if info then ORBITS[info.orbit] else nil
	if style and info then
		local speed = FX.spin * info.spin * style.speed * (1 + boost * FX.boostSpin)
		state.angle += speed * dt
		local width = style.width * (0.5 + 0.5 * k) * (1 + boost * 0.4)
		for _, blade in state.blades do
			if blade.trail.Enabled then
				local ring = RINGS[blade.ring]
				local turn = state.angle * ring.spin + blade.phase
				local theta = turn + style.surge * math.sin(turn * 1.5 + blade.ring)
				local radius = (style.radius + blade.ring * 0.3 + breath * 0.15) * size
				local frame = CFrame.new(0, ring.height * size, 0) * CFrame.Angles(math.rad(ring.tilt.X), 0, math.rad(ring.tilt.Y))
				local out = Vector3.new(math.cos(theta), 0, math.sin(theta))
				local point = frame * (out * radius)
				local span = if style.radial then frame:VectorToWorldSpace(out) * (width / 2) else frame.UpVector * (width / 2)
				blade.top.Position = point + span
				blade.bottom.Position = point - span
			end
		end
	end

	-- chão: a peça fica colada no piso embaixo do boneco, mesmo no pulo
	local ground = state.ground
	local hit = workspace:Raycast(origin, Vector3.new(0, -40, 0), state.rays)
	state.groundY = if hit then hit.Position.Y else origin.Y - 3
	if ground and ground.gui.Enabled then
		ground.part.CFrame = CFrame.new(origin.X, state.groundY + 0.12, origin.Z)
		local diameter = FX.circleSize * (0.55 + 0.45 * k) * (1 + boost * 0.45) * (1 + breath * 0.025)
		local scale = diameter / GROUND_SIZE
		local turn = now * FX.circleSpin * (1 + boost * 3)
		ground.pool.Size = UDim2.fromScale(scale * 1.35, scale * 1.35)
		ground.pool.ImageTransparency = 0.5 - 0.12 * breath - boost * 0.2
		ground.outer.Size = UDim2.fromScale(scale, scale)
		ground.outer.Rotation = turn
		ground.outer.ImageTransparency = 0.08 + 0.08 * breath
		ground.inner.Size = UDim2.fromScale(scale * 0.5, scale * 0.5)
		ground.inner.Rotation = -turn * 1.7
		-- vento: duas ondas defasadas; cada uma abre desacelerando e some antes de recomeçar
		state.wind = (state.wind + dt / FX.windPeriod * (1 + boost * 1.5)) % 1
		for index, wind in ground.winds do
			local p = (state.wind + (index - 1) / #ground.winds) % 1
			local open = 1 - (1 - p) ^ 3
			local reach = scale * 1.7 * (0.3 + 0.7 * open)
			wind.Size = UDim2.fromScale(reach, reach)
			wind.Rotation = index * 97 + now * 30 + open * 50
			wind.ImageTransparency = 1 - 0.92 * smoothstep(0, 0.12, p) * (1 - smoothstep(0.5, 1, p))
		end
	end

	-- pilares de luz: cada um nasce num ponto sorteado em volta, engorda e afina sem estalo
	for _, pillar in state.pillars do
		if pillar.beam.Enabled then
			pillar.phase += dt / pillar.period * (1 + boost)
			if pillar.phase >= 1 then
				pillar.phase %= 1
				local angle = rng:NextNumber(0, math.pi * 2)
				local reach = rng:NextNumber(2.5, 9) * size
				pillar.at = Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
			end
			local swell = math.sin(pillar.phase * math.pi) ^ 0.6 * (0.5 + 0.5 * k) * (1 + boost)
			local foot = Vector3.new(pillar.at.X, state.groundY - origin.Y, pillar.at.Z)
			pillar.low.Position = foot
			pillar.high.Position = foot + Vector3.new(0, 60, 0)
			pillar.beam.Width0 = swell * 1.5
			pillar.beam.Width1 = swell * 0.4
		end
	end

	-- raios: só na aura que tem (sempre) e em qualquer aura durante a carga
	local stormy = info ~= nil and info.lightning == true
	if (stormy or boost > 0.3) and now >= state.nextArc then
		state.nextArc = now + (if stormy then 0.22 else 0.4) * rng:NextNumber(0.6, 1.4) / math.max(k * (1 + boost * 2), 0.15)
		arc(origin, colorOf(state.player):Lerp(WHITE, 0.7), 3 + boost * 4)
		if boost > 0.5 then
			arc(origin, WHITE, 4 + boost * 4)
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
	local pillars = 0
	for _, pillar in me.pillars do
		if pillar.beam.Enabled then
			pillars += 1
		end
	end
	local ground = me.ground
	return {
		strength = Aura.strength(),
		emitting = me.stars ~= nil and me.stars.Enabled,
		rate = if me.stars then me.stars.Rate else 0,
		lit = me.light ~= nil and me.light.Enabled,
		flames = me.front ~= nil and me.front.Enabled,
		flameRate = if me.front then me.front.Rate else 0,
		hands = #me.hands,
		players = built,
		arcs = arcs,
		orbit = if arcs > 0 then me.orbit else "none",
		circle = ground ~= nil and ground.gui.Enabled and ground.outer.Visible,
		swirl = ground ~= nil and ground.gui.Enabled and ground.winds[1].Visible,
		shards = me.shards ~= nil and me.shards.Enabled,
		pillars = pillars,
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
