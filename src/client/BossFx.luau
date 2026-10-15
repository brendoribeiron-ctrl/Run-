--!strict
-- Efeitos dos golpes do golem (src/client/Boss.luau chama no quadro de cada evento da animação).
--
-- Golpes físicos, na pegada do Demon of Hatred (Sekiro): explosão de fogo no impacto, onda no
-- chão, rachaduras acesas que ficam um tempo, entulho de pedra, poeira e brasas; rastro de fogo
-- no braço que varre. Golpes perigosos piscam um "!" vermelho na cabeça antes (o aviso do Sekiro).
-- Magia (Pulso Ancestral), na pegada das magias toon de referência: orbe carregando no peito com
-- anéis girando, pedras flutuando, círculo mágico sob a mão, quadro de impacto em preto e branco,
-- coroa de espinhos e a parede de magia que corre pelo chão (a mesma onda que dá dano no servidor).

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Textures = require(ReplicatedStorage.Shared.Textures)
local Fx = require(script.Parent.Fx)

local BOSS = Config.Boss
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local DANGER = Color3.fromRGB(255, 40, 30)

export type Ctx = {
	cf: CFrame, -- raiz do golem na tela (pés, de frente para LookVector)
	point: (bone: string, rest: Vector3) -> Vector3, -- ponto do modelo em repouso -> mundo agora
	part: (bone: string) -> BasePart?, -- uma peça do osso (para prender rastros)
	glow: Color3, -- cor das fissuras deste golem
	magic: Color3, -- cor da magia
	rock: Color3,
	scale: number,
	near: number, -- 1 perto do jogador, cai com a distância (tremor de câmera)
}

local BossFx = {}
local rng = Random.new()

local function ease(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
end

local function holder(at: Vector3): Part
	local p = Fx.part(Vector3.one, CFrame.new(at), WHITE)
	p.Transparency = 1
	return p
end

-- Imagem deitada no chão (ou virada para `normal`), que cresce de `from` a `to` studs e some.
local function decal(texture: string, at: CFrame, color: Color3, from: number, to: number, time: number, hold: number?, spin: number?, brightness: number?): (Part, ImageLabel)
	local p = Fx.part(Vector3.new(from, 0.05, from), at, color)
	p.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(256, 256)
	gui.LightInfluence = 0
	gui.Brightness = brightness or 2
	gui.Parent = p
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = texture
	image.ImageColor3 = color
	image.Parent = gui
	TweenService:Create(p, ease(time), { Size = Vector3.new(to, 0.05, to) }):Play()
	if spin then
		TweenService:Create(image, ease(time + (hold or 0), Enum.EasingStyle.Linear), { Rotation = spin }):Play()
	end
	local fade = TweenService:Create(image, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold or time * 0.5), { ImageTransparency = 1 })
	fade:Play()
	Debris:AddItem(p, (hold or time * 0.5) + 0.4)
	return p, image
end

local function ground(ctx: Ctx, at: Vector3): CFrame
	return CFrame.new(at.X, ctx.cf.Y + 0.15, at.Z)
end

-- Explosão de fogo: labaredas do flipbook subindo, com miolo claro.
local function fire(at: Vector3, color: Color3, count: number, size: number, rise: number, spread: number?)
	local p = holder(at)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Textures.flame
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.45, 0.8)
	e.Speed = NumberRange.new(rise * 0.4, rise)
	e.SpreadAngle = Vector2.new(spread or 40, spread or 40)
	e.Acceleration = Vector3.new(0, rise * 0.6, 0)
	e.Drag = 2
	e.Rotation = NumberRange.new(-20, 20)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(0.4, size), NumberSequenceKeypoint.new(1, size * 0.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.6)), ColorSequenceKeypoint.new(0.35, color), ColorSequenceKeypoint.new(1, color:Lerp(BLACK, 0.6)) })
	e.LightEmission = 0.55
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 1.2)
end

-- Poeira que corre pelo chão para os lados.
local function dust(at: Vector3, color: Color3, count: number, size: number, speed: number)
	local p = holder(at)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Textures.glow
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(85, 85)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Drag = 3
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 1.4)
end

-- Brasas: faíscas que sobem e caem.
local function embers(at: Vector3, color: Color3, count: number, speed: number)
	local p = holder(at)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Textures.star
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.6, 1.4)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Drag = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(color:Lerp(WHITE, 0.4), color)
	e.LightEmission = 1
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 1.6)
end

local function light(at: Vector3, color: Color3, range: number, brightness: number, time: number)
	local p = holder(at)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	TweenService:Create(l, ease(time), { Brightness = 0 }):Play()
	Debris:AddItem(p, time + 0.1)
end

-- Imagem virada para a câmera que estoura (coroa de espinhos, clarão).
local function pop(texture: string, at: Vector3, color: Color3, from: number, to: number, time: number, spin: number?)
	local p = holder(at)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(from, from)
	board.LightInfluence = 0
	board.Brightness = 2.5
	board.Parent = p
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = texture
	image.ImageColor3 = color
	image.Rotation = rng:NextNumber(0, 360)
	image.Parent = board
	TweenService:Create(board, ease(time, Enum.EasingStyle.Quart), { Size = UDim2.fromScale(to, to) }):Play()
	TweenService:Create(image, ease(time), { ImageTransparency = 1, Rotation = image.Rotation + (spin or 0) }):Play()
	Debris:AddItem(p, time + 0.1)
end

-- Quadro de impacto: a tela estoura em preto e branco por dois quadros e volta.
local function impactFrame(tint: Color3)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "BossImpact"
	cc.Saturation = -1
	cc.Contrast = 2.5
	cc.Brightness = 0.35
	cc.Parent = Lighting
	task.delay(0.05, function()
		cc.Brightness = -0.3
		cc.TintColor = WHITE:Lerp(tint, 0.25)
	end)
	task.delay(0.11, function()
		cc.Saturation = 0.4
		cc.Contrast = 0.4
		cc.Brightness = 0.05
		cc.TintColor = WHITE:Lerp(tint, 0.35)
		TweenService:Create(cc, ease(0.35), { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE }):Play()
	end)
	Debris:AddItem(cc, 0.6)
end

-- Aviso de golpe perigoso: "!" vermelho que pisca sobre a cabeça.
local function danger(ctx: Ctx)
	local at = ctx.point("Head", Vector3.new(0, 33, -2) * ctx.scale)
	local p = holder(at)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(7, 7)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Parent = p
	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1
	glow.Size = UDim2.fromScale(1.6, 1.6)
	glow.Position = UDim2.fromScale(-0.3, -0.3)
	glow.Image = Textures.glow
	glow.ImageColor3 = DANGER
	glow.Parent = board
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Font = Enum.Font.FredokaOne
	mark.Text = "!"
	mark.TextScaled = true
	mark.TextColor3 = WHITE
	local stroke = Instance.new("UIStroke")
	stroke.Color = DANGER
	stroke.Thickness = 4
	stroke.Parent = mark
	mark.Parent = board
	local scale = Instance.new("UIScale")
	scale.Scale = 2.2
	scale.Parent = board
	TweenService:Create(scale, ease(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local out = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45)
	TweenService:Create(mark, out, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, out, { Transparency = 1 }):Play()
	TweenService:Create(glow, out, { ImageTransparency = 1 }):Play()
	Debris:AddItem(p, 0.8)
end

-- Rastro de fogo preso a uma peça (braço que varre), ligado por `time` segundos.
local function trail(part: BasePart?, color: Color3, width: number, time: number)
	if not part then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Texture = Textures.comet
	t.TextureMode = Enum.TextureMode.Stretch
	t.Lifetime = 0.3
	t.LightEmission = 0.8
	t.FaceCamera = true
	t.Color = ColorSequence.new(color:Lerp(WHITE, 0.5), color)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	t.Parent = part
	task.delay(time, function()
		t.Enabled = false
	end)
	Debris:AddItem(t, time + 0.4)
	Debris:AddItem(a0, time + 0.4)
	Debris:AddItem(a1, time + 0.4)
end

---------------------------------------------------------------------------------------------------
-- Golpes físicos

-- Impacto no chão: o pacote comum de pisão, esmagamento e gancho.
local function quake(ctx: Ctx, at: Vector3, power: number)
	local s = ctx.scale
	local g = ground(ctx, at)
	local hot = ctx.glow
	fire(g.Position + Vector3.new(0, 1, 0), hot, math.floor(14 * power), 7 * s * power, 26 * power)
	fire(g.Position + Vector3.new(0, 1, 0), hot, math.floor(10 * power), 5 * s * power, 50 * power, 70)
	decal(Textures.wave, g, hot:Lerp(WHITE, 0.3), 4, 34 * s * power, 0.45)
	decal(Textures.wave, g * CFrame.new(0, 0.05, 0), WHITE, 2, 22 * s * power, 0.3)
	decal(Textures.crack, g * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), hot, 10 * s * power, 24 * s * power, 0.12, 2.6, nil, 1.6)
	decal(Textures.glow, g * CFrame.new(0, 0.08, 0), BLACK, 8 * s * power, 26 * s * power, 0.2, 2.4, nil, 0.4)
	dust(g.Position + Vector3.new(0, 1.5, 0), Color3.fromRGB(70, 62, 60), math.floor(16 * power), 6 * s, 40 * power)
	embers(g.Position + Vector3.new(0, 2, 0), hot, math.floor(26 * power), 50 * power)
	Fx.cubes(g.Position + Vector3.new(0, 2, 0), ctx.rock, math.floor(10 * power), 30 * power, Vector3.new(0, 26, 0), 1.6 * s)
	Fx.cubes(g.Position + Vector3.new(0, 2, 0), hot, math.floor(6 * power), 34 * power, Vector3.new(0, 30, 0), 0.7 * s, Enum.Material.Neon)
	light(g.Position + Vector3.new(0, 6, 0), hot, 60, 6 * power, 0.7)
	Fx.shake(0.55 * power * ctx.near)
end

-- Fogo que fica queimando no chão um tempo (esmagamento).
local function burning(ctx: Ctx, at: Vector3, seconds: number)
	local g = ground(ctx, at)
	local p = holder(g.Position + Vector3.new(0, 0.5, 0))
	p.Size = Vector3.new(14, 1, 14) * ctx.scale
	local e = Instance.new("ParticleEmitter")
	e.Texture = Textures.flame
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Rate = 26
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(4, 10)
	e.Acceleration = Vector3.new(0, 10, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(0.5, 4), NumberSequenceKeypoint.new(1, 1) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(ctx.glow:Lerp(WHITE, 0.4), ctx.glow)
	e.LightEmission = 0.5
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = p
	task.delay(seconds, function()
		e.Enabled = false
	end)
	Debris:AddItem(p, seconds + 1)
end

local function stompStart(ctx: Ctx)
	-- o pé que vai pisar esquenta
	local foot = ctx.point("FootR", Vector3.new(3.6, 1, -1.5) * ctx.scale)
	light(foot, ctx.glow, 22, 3, 0.8)
end

local function stomp(ctx: Ctx)
	local foot = ctx.point("FootR", Vector3.new(3.6, 0, -1.5) * ctx.scale)
	quake(ctx, foot, 1)
end

local function sweepStart(ctx: Ctx)
	task.delay(0.3, trail, ctx.part("HandR"), ctx.glow, 5 * ctx.scale, 0.55)
	task.delay(0.3, trail, ctx.part("ForearmR"), ctx.glow:Lerp(BLACK, 0.3), 4 * ctx.scale, 0.5)
end

local function sweep(ctx: Ctx)
	-- arco de fogo varrendo da direita para a esquerda, na frente do golem
	local s = ctx.scale
	local center = ctx.cf.Position
	for i = 0, 9 do
		local angle = math.rad(-80 + i * 18)
		local at = (ctx.cf * CFrame.Angles(0, angle, 0) * CFrame.new(0, 3 * s, -15 * s)).Position
		task.delay(i * 0.018, fire, at, ctx.glow, 5, 5 * s, 18, 60)
	end
	local hand = ctx.point("HandR", Vector3.new(10, 2, -1.5) * s)
	pop(Textures.slash, hand, ctx.glow:Lerp(WHITE, 0.3), 10 * s, 26 * s, 0.3, 40)
	embers(hand, ctx.glow, 30, 55)
	decal(Textures.wave, ground(ctx, center), ctx.glow, 10 * s, 46 * s, 0.4)
	light(hand, ctx.glow, 50, 5, 0.5)
	Fx.shake(0.35 * ctx.near)
end

local function slamStart(ctx: Ctx)
	danger(ctx)
	for _, side in { "HandR", "HandL" } do
		local fist = ctx.point(side, Vector3.new(if side == "HandR" then 10 else -10, 4, -1) * ctx.scale)
		light(fist, ctx.glow, 25, 2, 1)
	end
end

local function slam(ctx: Ctx)
	local s = ctx.scale
	local r = ctx.point("HandR", Vector3.new(10, 1, -1.5) * s)
	local l = ctx.point("HandL", Vector3.new(-10, 1, -1.5) * s)
	local mid = (r + l) / 2
	quake(ctx, mid, 1.45)
	Fx.burst(ground(ctx, mid).Position + Vector3.new(0, 3, 0), ctx.glow, 28 * s, 0.4)
	Fx.flash(ctx.glow, 0.35 * ctx.near, 0.35)
	burning(ctx, mid, 2.2)
	-- segunda onda atrasada, mais larga
	task.delay(0.12, decal, Textures.wave, ground(ctx, mid), ctx.glow:Lerp(WHITE, 0.5), 10, 62 * s, 0.6)
end

local function chargeStart(ctx: Ctx)
	danger(ctx)
	task.delay(0.3, trail, ctx.part("HandR"), ctx.glow, 5 * ctx.scale, 0.5)
	dust(ctx.cf.Position + Vector3.new(0, 1, 0), Color3.fromRGB(70, 62, 60), 14, 6 * ctx.scale, 30)
end

local function charge(ctx: Ctx)
	-- gancho: coluna de fogo subindo à frente
	local s = ctx.scale
	local at = (ctx.cf * CFrame.new(0, 0, -9 * s)).Position
	quake(ctx, at, 0.9)
	for i = 0, 4 do
		task.delay(i * 0.04, fire, at + Vector3.new(0, i * 5 * s, 0), ctx.glow, 8, 6 * s, 40, 18)
	end
	pop(Textures.spikes, at + Vector3.new(0, 12 * s, 0), ctx.glow:Lerp(WHITE, 0.5), 8 * s, 34 * s, 0.35, 30)
end

---------------------------------------------------------------------------------------------------
-- Pulso Ancestral (magia)

local function pulseCharge(ctx: Ctx, length: number, getCtx: () -> Ctx)
	danger(ctx)
	local s = ctx.scale
	local color = ctx.magic
	-- orbe no peito com dois anéis girando
	local orb = Fx.part(Vector3.one * 0.5, CFrame.new(), color:Lerp(WHITE, 0.5), Enum.Material.Neon, Enum.PartType.Ball)
	local rings = {}
	for i = 1, 2 do
		local ring = Fx.part(Vector3.new(0.3, 1, 1), CFrame.new(), color, Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.Transparency = 0.3
		rings[i] = ring
	end
	local glowLight = Instance.new("PointLight")
	glowLight.Color = color
	glowLight.Range = 30
	glowLight.Brightness = 0
	glowLight.Parent = orb
	-- pedras que flutuam em volta dos ombros
	local rocks = {}
	for i = 1, 10 do
		local cube = Fx.part(Vector3.one * rng:NextNumber(0.8, 1.8) * s, CFrame.new(), ctx.rock, Enum.Material.Slate)
		cube.CastShadow = false
		rocks[i] = { part = cube, angle = rng:NextNumber(0, 6.28), radius = rng:NextNumber(10, 16) * s, rise = rng:NextNumber(4, 12) * s, spin = rng:NextNumber(-3, 3) }
	end
	local began = os.clock()
	local circle: ImageLabel? = nil
	local circlePart: Part? = nil
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		local c = getCtx()
		local chest = c.point("Chest", Vector3.new(0, 18.8, -6.2) * s)
		local grow = math.clamp(t / 0.95, 0, 1)
		local size = (1 + 4 * grow) * s * (1 + 0.08 * math.sin(t * 30))
		orb.Size = Vector3.one * size
		orb.CFrame = CFrame.new(chest)
		glowLight.Brightness = 4 * grow
		for i, ring in rings do
			ring.Size = Vector3.new(0.25, size * 2.2, size * 2.2)
			ring.CFrame = CFrame.new(chest) * CFrame.Angles(t * (3 + i), t * (2 - i * 4), i * 1.2) * CFrame.Angles(0, 0, math.rad(90))
		end
		-- as pedras sobem a partir da carga (0,63 s)
		local lift = math.clamp((t - 0.6) / 0.4, 0, 1)
		for _, rock in rocks do
			local a = rock.angle + t * 0.6
			local base = c.cf.Position + Vector3.new(math.cos(a) * rock.radius, 0, math.sin(a) * rock.radius)
			rock.part.CFrame = CFrame.new(base + Vector3.new(0, 2 * s + rock.rise * lift + math.sin(t * 3 + rock.angle) * 0.6, 0)) * CFrame.Angles(t * rock.spin, t * rock.spin * 0.7, 0)
			rock.part.Transparency = if lift > 0 then 0 else 1
		end
		if t >= 0.63 and not circle then
			-- círculo mágico sob a mão que vai bater no chão
			local hand = c.point("HandL", Vector3.new(-10, 0, -1.5) * s)
			local p, image = decal(Textures.circle, ground(c, hand), color, 2, 30 * s, 0.35, 1.6, 300, 2.5)
			circle = image
			circlePart = p
			embers(hand, color, 20, 20)
		end
		if t >= 1.0 or t > length then
			connection:Disconnect()
			orb:Destroy()
			for _, ring in rings do
				ring:Destroy()
			end
			-- as pedras são arremessadas para fora
			for _, rock in rocks do
				local part = rock.part
				part.Anchored = false
				local out = Vector3.new(part.Position.X - c.cf.X, 0, part.Position.Z - c.cf.Z)
				part.AssemblyLinearVelocity = (if out.Magnitude > 0.1 then out.Unit else Vector3.xAxis) * 60 + Vector3.new(0, 25, 0)
				TweenService:Create(part, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { Transparency = 1 }):Play()
				Debris:AddItem(part, 1.2)
			end
			if circlePart then
				TweenService:Create(circlePart, ease(0.25), { Size = Vector3.new(44 * s, 0.05, 44 * s) }):Play()
			end
		end
	end)
end

local function pulse(ctx: Ctx)
	local s = ctx.scale
	local A = BOSS.attacks.Pulse
	local color = ctx.magic
	local origin = (ctx.cf * CFrame.new(A.side * s, 0, -A.ahead * s)).Position
	local g = ground(ctx, origin)
	impactFrame(color)
	Fx.flash(WHITE, 0.55 * ctx.near, 0.3)
	Fx.shake(0.7 * ctx.near)
	pop(Textures.spikes, g.Position + Vector3.new(0, 4 * s, 0), WHITE, 6 * s, 46 * s, 0.4, 25)
	task.delay(0.06, pop, Textures.spikes, g.Position + Vector3.new(0, 4 * s, 0), color, 6 * s, 64 * s, 0.5, -40)
	pop(Textures.glow, g.Position + Vector3.new(0, 3 * s, 0), color:Lerp(WHITE, 0.4), 10 * s, 50 * s, 0.35)
	decal(Textures.swirl, g * CFrame.new(0, 0.12, 0), color:Lerp(WHITE, 0.3), 6 * s, 40 * s, 0.6, 0.2, -260, 2.5)
	decal(Textures.spikes, g * CFrame.new(0, 0.14, 0), WHITE, 4 * s, 36 * s, 0.3, 0.1, 60, 3)
	light(g.Position + Vector3.new(0, 8, 0), color, 60, 10, 0.9)
	embers(g.Position + Vector3.new(0, 2, 0), color, 40, 60)

	-- a onda: borda dura no chão e uma parede baixa de magia, na velocidade da onda do servidor
	local reach = A.reach * s
	local speed = A.speed * s
	local seconds = reach / speed
	local wave = decal(Textures.wave, g * CFrame.new(0, 0.1, 0), color:Lerp(WHITE, 0.2), 1, reach * 2, seconds, seconds, nil, 2.5)
	TweenService:Create(wave, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(reach * 2, 0.05, reach * 2) }):Play()
	local count = 40
	local wall = {}
	for i = 1, count do
		local seg = Fx.part(Vector3.new(0.5, 3.2 * s, 1), CFrame.new(g.Position), color:Lerp(WHITE, 0.35), Enum.Material.Neon)
		seg.Transparency = 0.25
		wall[i] = seg
	end
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		local r = math.min(t * speed, reach)
		local fade = math.clamp((t - seconds * 0.75) / (seconds * 0.25), 0, 1)
		for i, seg in wall do
			local a = i / count * math.pi * 2
			local at = g.Position + Vector3.new(math.cos(a) * r, 1.6 * s, math.sin(a) * r)
			seg.Size = Vector3.new(0.5, 3.2 * s * (1 - fade * 0.6), math.max(r * 2 * math.pi / count * 1.05, 0.3))
			seg.CFrame = CFrame.lookAt(at, at + Vector3.new(-math.sin(a), 0, math.cos(a)))
			seg.Transparency = 0.25 + 0.75 * fade
		end
		if t >= seconds then
			connection:Disconnect()
			for _, seg in wall do
				seg:Destroy()
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------

-- Começo de cada animação (avisos, rastros).
function BossFx.start(clip: string, ctx: Ctx, getCtx: () -> Ctx)
	if clip == "Stomp" then
		stompStart(ctx)
	elseif clip == "Sweep" then
		sweepStart(ctx)
	elseif clip == "Slam" then
		slamStart(ctx)
	elseif clip == "Charge" then
		chargeStart(ctx)
	elseif clip == "Pulse" then
		pulseCharge(ctx, 1.0, getCtx)
	end
end

-- Eventos marcados na animação (tools/blender/golem.py).
function BossFx.event(clip: string, name: string, ctx: Ctx)
	if name == "impact" then
		if clip == "Stomp" then
			stomp(ctx)
		elseif clip == "Sweep" then
			sweep(ctx)
		elseif clip == "Slam" then
			slam(ctx)
		elseif clip == "Charge" then
			charge(ctx)
		end
	elseif name == "pulse" then
		pulse(ctx)
	elseif name == "roar" then
		local head = ctx.point("Head", Vector3.new(0, 25, -6) * ctx.scale)
		Fx.shake(1.1 * ctx.near)
		pop(Textures.spikes, head, ctx.glow:Lerp(WHITE, 0.5), 10, 70, 0.6, 20)
		decal(Textures.wave, ground(ctx, ctx.cf.Position), ctx.glow, 10, 120 * ctx.scale, 0.7)
		dust(ctx.cf.Position + Vector3.new(0, 2, 0), Color3.fromRGB(70, 62, 60), 30, 8, 50)
		embers(head, ctx.glow, 40, 40)
	elseif name == "eyes" then
		local head = ctx.point("Head", Vector3.new(0, 25.5, -6) * ctx.scale)
		light(head, ctx.glow, 20, 4, 1.2)
		pop(Textures.star, head, ctx.glow:Lerp(WHITE, 0.5), 2, 9, 0.35, 45)
	end
end

-- Passos pesados na corrida: poeira e um tremor leve.
function BossFx.footstep(ctx: Ctx, at: Vector3, heavy: boolean)
	dust(at + Vector3.new(0, 1, 0), Color3.fromRGB(70, 62, 60), if heavy then 8 else 4, 4 * ctx.scale, 16)
	Fx.shake((if heavy then 0.2 else 0.08) * ctx.near)
end

-- Soco do jogador acertando o golem.
function BossFx.struck(at: Vector3, normal: Vector3, crit: boolean, color: Color3)
	Fx.star(at, normal, WHITE, if crit then 16 else 8, if crit then 4 else 3, 0.22)
	Fx.burst(at, if crit then Color3.fromRGB(255, 214, 40) else WHITE, if crit then 9 else 4, 0.2)
	Fx.cubes(at, color, if crit then 8 else 4, 18, normal * 20, 0.6)
	embers(at, color, if crit then 16 else 6, 30)
end

return BossFx
