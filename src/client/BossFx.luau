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
local Anims = require(ReplicatedStorage.Shared.GolemAnims)
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

-- Cores de cada mundo: fissuras, magia e pedra (as mesmas do GolemModels.STYLES do servidor).
BossFx.PALETTE = {
	{ glow = Color3.fromRGB(80, 190, 255), magic = Color3.fromRGB(150, 110, 255), rock = Color3.fromRGB(36, 38, 54) },
	{ glow = Color3.fromRGB(255, 84, 20), magic = Color3.fromRGB(255, 120, 60), rock = Color3.fromRGB(38, 28, 28) },
}

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
-- Peças 3D (tools/blender/boss_fx.py): o servidor carrega em ReplicatedStorage.BossModels.Fx.
-- Cada peça tem 10 studs de referência; a escala s é relativa a isso (x = lado, y = cima, z = frente).

type Piece = { part: BasePart, offset: CFrame }
type Mesh = { part: BasePart, place: (cf: CFrame, s: Vector3) -> () }

local pieces: { [string]: Piece } = {}

local function piece(kind: string): Piece?
	if pieces[kind] then
		return pieces[kind]
	end
	local models = ReplicatedStorage:FindFirstChild("BossModels")
	local fx = models and models:FindFirstChild("Fx")
	if not fx or not fx:IsA("Model") then
		return nil
	end
	local pivot = fx:GetPivot()
	for _, part in fx:GetDescendants() do
		local name = if part:IsA("BasePart") then string.match(part.Name, "^(%a+)_") else nil
		if name and part:IsA("BasePart") then
			pieces[name] = { part = part, offset = pivot:ToObjectSpace(part.CFrame) }
		end
	end
	return pieces[kind]
end

-- Escala de um eixo da peça (a importação pode ter girado os eixos dela em relação ao modelo).
local function along(axis: Vector3, s: Vector3): number
	return math.max(math.abs(axis.X) * s.X + math.abs(axis.Y) * s.Y + math.abs(axis.Z) * s.Z, 0.002)
end

local function mesh(kind: string, color: Color3, material: Enum.Material?, transparency: number?): Mesh?
	local p = piece(kind)
	if not p then
		return nil
	end
	local part = p.part:Clone()
	part.Color = color
	part.Material = material or Enum.Material.Neon
	part.Transparency = transparency or 0
	part.CastShadow = false
	local offset, base = p.offset, p.part.Size
	local function place(cf: CFrame, s: Vector3)
		part.Size = Vector3.new(base.X * along(offset.XVector, s), base.Y * along(offset.YVector, s), base.Z * along(offset.ZVector, s))
		part.CFrame = cf * CFrame.new(offset.Position * s) * offset.Rotation
	end
	place(CFrame.new(0, -1e4, 0), Vector3.one * 0.01)
	part.Parent = Fx.folder
	return { part = part, place = place }
end

-- Chama f(t) a cada quadro, t de 0 a 1 ao longo de `time`; depois `done`.
local function run(time: number, f: (t: number) -> (), done: (() -> ())?)
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - began) / time, 1)
		f(t)
		if t >= 1 then
			connection:Disconnect()
			if done then
				done()
			end
		end
	end)
end

local function outQuint(t: number): number
	return 1 - (1 - t) ^ 5
end

local function outBack(t: number): number
	local u = t - 1
	return 1 + 2.7 * u * u * u + 1.7 * u * u
end

local function drop(...: Mesh?)
	for _, m in { ... } do
		if m then
			m.part:Destroy()
		end
	end
end

-- Onda de choque em 3D: cúpula achatada que abre, miolo branco, anel deitado correndo na frente
-- e (opcional) as faixas de vento girando por cima.
local function shockwave(ctx: Ctx, at: Vector3, radius: number, color: Color3, time: number, swirl: boolean?)
	local g = ground(ctx, at)
	local k = radius / 10
	-- com Bloom, neon claro e pouco transparente vira uma bolha branca: cor cheia e bem transparente
	local dome = mesh("Dome", color, Enum.Material.Neon, 0.62)
	local core = mesh("Dome", color:Lerp(WHITE, 0.5), Enum.Material.Neon, 0.45)
	local ring = mesh("Ring", color:Lerp(WHITE, 0.15), Enum.Material.Neon, 0)
	local spiral = if swirl then mesh("Swirl", WHITE, Enum.Material.Neon, 0.1) else nil
	local spin = rng:NextNumber(0, math.pi * 2)
	run(time, function(t)
		local e = outQuint(t)
		if dome then
			dome.place(g, Vector3.new(k, k * 0.5, k) * (0.12 + 0.88 * e))
			dome.part.Transparency = 0.62 + 0.38 * t ^ 1.2
		end
		if core then
			local c = math.min(t * 3, 1)
			core.place(g, Vector3.new(k, k * 0.75, k) * (0.06 + 0.28 * outQuint(c)))
			core.part.Transparency = 0.45 + 0.55 * c
		end
		if ring then
			local r = k * 1.3 * (0.1 + 0.9 * e)
			ring.place(g, Vector3.new(r, k * 0.9 * (1 - 0.7 * t), r))
			ring.part.Transparency = t * t
		end
		if spiral then
			spiral.place(g * CFrame.Angles(0, spin - e * 2.4, 0), Vector3.new(k, k * 0.55, k) * (0.2 + 0.8 * e))
			spiral.part.Transparency = 0.1 + 0.9 * t
		end
	end, function()
		drop(dome, core, ring, spiral)
	end)
end

-- Espinho que brota do chão inclinado para `out`, fica `hold` segundos e afunda.
local function spike(ctx: Ctx, at: Vector3, height: number, out: Vector3, hold: number, kind: string?, color: Color3?, material: Enum.Material?)
	local m = mesh(kind or (if rng:NextNumber() < 0.55 then "SpikeA" else "SpikeB"), color or ctx.rock, material or Enum.Material.Slate)
	if not m then
		return
	end
	local flat = Vector3.new(out.X, 0, out.Z)
	local yaw = if flat.Magnitude > 0.01 then math.atan2(-flat.X, -flat.Z) else rng:NextNumber(0, 6.28)
	local cf = ground(ctx, at) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-math.rad(rng:NextNumber(14, 34)), 0, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local s = height / 10
	local size = Vector3.new(s * rng:NextNumber(0.8, 1.2), s, s * rng:NextNumber(0.8, 1.2))
	-- rocha escura some na luz da sala: um miolo aceso, mais fino e um pouco mais alto, aparece
	-- na ponta e nas frestas
	local hot = if m.part.Material ~= Enum.Material.Neon then mesh("SpikeB", ctx.glow, Enum.Material.Neon, 0) else nil
	local hotSize = Vector3.new(s * 0.45, s * 1.06, s * 0.45)
	local function at(cframe: CFrame)
		m.place(cframe, size)
		if hot then
			hot.place(cframe, hotSize)
		end
	end
	run(0.11, function(t)
		at(cf * CFrame.new(0, -height * (1 - outBack(t)), 0))
	end, function()
		task.delay(hold, function()
			run(0.4, function(t)
				at(cf * CFrame.new(0, -height * 0.9 * t * t, 0))
				m.part.Transparency = math.max(t * 1.6 - 0.6, 0)
				if hot then
					hot.part.Transparency = math.min(t * 2, 1)
				end
			end, function()
				drop(m, hot)
			end)
		end)
	end)
end

-- Anel de espinhos em volta de um ponto (os de perto brotam primeiro).
local function eruption(ctx: Ctx, center: Vector3, count: number, radius: number, height: number, hold: number, delay: number?)
	local phase = rng:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local a = phase + (i + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = radius * rng:NextNumber(0.75, 1.1)
		task.delay((delay or 0) + r / radius * 0.05, spike, ctx, center + dir * r, height * rng:NextNumber(0.75, 1.15), dir, hold + rng:NextNumber(0, 0.3))
	end
end

-- Lua crescente varrendo: gira em volta do Y local de `cf` de `from` a `to` (radianos), com miolo
-- branco e um fantasma atrasado.
local function crescent(cf: CFrame, radius: number, color: Color3, time: number, from: number, to: number)
	local k = radius / 10
	local ghost = mesh("Slash", color:Lerp(BLACK, 0.15), Enum.Material.Neon, 0.5)
	local outer = mesh("Slash", color, Enum.Material.Neon, 0)
	local inner = mesh("Slash", WHITE, Enum.Material.Neon, 0)
	local lag = (to - from) * 0.18
	run(time, function(t)
		local e = outQuint(t)
		local a = from + (to - from) * e
		local fade = math.clamp((t - 0.3) / 0.7, 0, 1)
		if outer then
			outer.place(cf * CFrame.Angles(0, a, 0), Vector3.new(k, k * 1.3, k) * (0.85 + 0.2 * e))
			outer.part.Transparency = fade
		end
		if inner then
			inner.place(cf * CFrame.Angles(0, a + lag * 0.3, 0), Vector3.new(k * 0.94, k * 0.7, k * 0.94) * (0.85 + 0.2 * e))
			inner.part.Transparency = math.min(fade * 1.6, 1)
		end
		if ghost then
			ghost.place(cf * CFrame.Angles(0, a - lag, 0), Vector3.new(k, k, k) * (0.9 + 0.25 * e))
			ghost.part.Transparency = 0.5 + 0.5 * fade
		end
	end, function()
		drop(ghost, outer, inner)
	end)
end

-- Energia puxada para um ponto antes do golpe: riscos que convergem e uma bola de luz que cresce.
local function gather(point: () -> Vector3?, color: Color3, time: number, radius: number)
	local began = os.clock()
	local nextAt = 0
	local orb = Fx.part(Vector3.one * 0.1, CFrame.new(), color:Lerp(WHITE, 0.5), Enum.Material.Neon, Enum.PartType.Ball)
	orb.Transparency = 0.2
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		local at = point()
		if t >= time or not at then
			connection:Disconnect()
			orb:Destroy()
			return
		end
		local grow = t / time
		orb.CFrame = CFrame.new(at)
		orb.Size = Vector3.one * radius * 0.28 * grow * (1 + 0.15 * math.sin(t * 40))
		if t >= nextAt then
			nextAt = t + 0.03
			local dir = rng:NextUnitVector()
			Fx.streak(at + dir * radius, -dir * radius * 0.85, color:Lerp(WHITE, rng:NextNumber(0.2, 0.7)), radius * 0.3, 0.2)
		end
	end)
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

-- Ponto de um osso que acompanha a pose a cada quadro (para a energia que se junta na mão).
local function follow(getCtx: () -> Ctx, bone: string, rest: Vector3): () -> Vector3?
	return function()
		local c = getCtx()
		return c.point(bone, rest * c.scale)
	end
end

local function stompStart(ctx: Ctx, getCtx: () -> Ctx)
	-- o pé que vai pisar esquenta e puxa energia
	local foot = ctx.point("FootR", Vector3.new(3.6, 1, -1.5) * ctx.scale)
	light(foot, ctx.glow, 22, 3, 0.8)
	task.delay(0.15, gather, follow(getCtx, "FootR", Vector3.new(3.6, 1.5, -1.5)), ctx.glow, 0.55, 9 * ctx.scale)
end

local function stomp(ctx: Ctx)
	local s = ctx.scale
	local foot = ctx.point("FootR", Vector3.new(3.6, 0, -1.5) * s)
	quake(ctx, foot, 1)
	shockwave(ctx, foot, 15 * s, ctx.glow, 0.45)
	eruption(ctx, foot, 7, 7 * s, 5.5 * s, 0.7)
end

local function sweepStart(ctx: Ctx, getCtx: () -> Ctx)
	task.delay(0.08, gather, follow(getCtx, "HandR", Vector3.new(10, 2, -1.5)), ctx.glow, 0.45, 8 * ctx.scale)
	task.delay(0.3, trail, ctx.part("HandR"), ctx.glow, 5 * ctx.scale, 0.55)
	task.delay(0.3, trail, ctx.part("ForearmR"), ctx.glow:Lerp(BLACK, 0.3), 4 * ctx.scale, 0.5)
end

local function sweep(ctx: Ctx)
	-- lua de fogo varrendo da direita para a esquerda, na frente do golem
	local s = ctx.scale
	local center = ctx.cf.Position
	crescent(ctx.cf * CFrame.new(0, 6 * s, 0) * CFrame.Angles(0, 0, math.rad(-8)), 19 * s, ctx.glow, 0.4, -1.3, 0.7)
	for i = 0, 9 do
		local angle = math.rad(-80 + i * 18)
		local at = (ctx.cf * CFrame.Angles(0, angle, 0) * CFrame.new(0, 3 * s, -15 * s)).Position
		task.delay(i * 0.018, fire, at, ctx.glow, 4, 4 * s, 18, 60)
	end
	local hand = ctx.point("HandR", Vector3.new(10, 2, -1.5) * s)
	embers(hand, ctx.glow, 30, 55)
	decal(Textures.wave, ground(ctx, center), ctx.glow, 10 * s, 46 * s, 0.4)
	light(hand, ctx.glow, 50, 5, 0.5)
	Fx.shake(0.35 * ctx.near)
end

local function slamStart(ctx: Ctx, getCtx: () -> Ctx)
	danger(ctx)
	for _, side in { "HandR", "HandL" } do
		local x = if side == "HandR" then 10 else -10
		local fist = ctx.point(side, Vector3.new(x, 4, -1) * ctx.scale)
		light(fist, ctx.glow, 25, 2, 1)
		task.delay(0.3, gather, follow(getCtx, side, Vector3.new(x, 3, -1.5)), ctx.glow, 0.7, 10 * ctx.scale)
	end
end

local function slam(ctx: Ctx)
	local s = ctx.scale
	local r = ctx.point("HandR", Vector3.new(10, 1, -1.5) * s)
	local l = ctx.point("HandL", Vector3.new(-10, 1, -1.5) * s)
	local mid = (r + l) / 2
	quake(ctx, mid, 1.45)
	shockwave(ctx, mid, 28 * s, ctx.glow, 0.6, true)
	eruption(ctx, mid, 9, 11 * s, 9 * s, 1.3)
	eruption(ctx, mid, 14, 20 * s, 6 * s, 1.0, 0.08)
	Fx.burst(ground(ctx, mid).Position + Vector3.new(0, 3, 0), ctx.glow, 28 * s, 0.4)
	Fx.flash(ctx.glow, 0.35 * ctx.near, 0.35)
	burning(ctx, mid, 2.2)
	-- segunda onda atrasada, mais larga
	task.delay(0.12, decal, Textures.wave, ground(ctx, mid), ctx.glow:Lerp(WHITE, 0.5), 10, 62 * s, 0.6)
end

local function chargeStart(ctx: Ctx, getCtx: () -> Ctx)
	danger(ctx)
	gather(follow(getCtx, "HandR", Vector3.new(10, 2, -1.5)), ctx.glow, 0.5, 8 * ctx.scale)
	task.delay(0.3, trail, ctx.part("HandR"), ctx.glow, 5 * ctx.scale, 0.5)
	dust(ctx.cf.Position + Vector3.new(0, 1, 0), Color3.fromRGB(70, 62, 60), 14, 6 * ctx.scale, 30)
end

local function charge(ctx: Ctx)
	-- gancho: lua de pé subindo à frente, coluna de fogo e uma fileira de espinhos que corre adiante
	local s = ctx.scale
	local at = (ctx.cf * CFrame.new(0, 0, -9 * s)).Position
	quake(ctx, at, 0.9)
	crescent(ctx.cf * CFrame.new(0, 9 * s, -5 * s) * CFrame.Angles(0, 0, math.pi / 2), 13 * s, ctx.glow, 0.38, 1.0, -1.2)
	for i = 0, 4 do
		task.delay(i * 0.04, fire, at + Vector3.new(0, i * 5 * s, 0), ctx.glow, 8, 6 * s, 40, 18)
	end
	for i = 1, 6 do
		local spot = at + ctx.cf.LookVector * (4 + i * 4.2) * s + ctx.cf.RightVector * rng:NextNumber(-1.5, 1.5) * s
		task.delay(i * 0.045, spike, ctx, spot, (3.5 + i * 0.9) * s, ctx.cf.LookVector, 0.9)
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

	shockwave(ctx, origin, 20 * s, color, 0.5, true)
	-- coluna de luz que sobe do ponto do golpe e afina
	local pillar = mesh("Pillar", color:Lerp(WHITE, 0.5), Enum.Material.Neon, 0.05)
	if pillar then
		run(0.7, function(t)
			local width = 2.6 * s * (1 - t) ^ 1.5
			pillar.place(g, Vector3.new(width, 6 * s * outQuint(math.min(t * 3, 1)), width))
			pillar.part.Transparency = 0.05 + 0.6 * t
		end, function()
			pillar.part:Destroy()
		end)
	end

	-- a onda: borda dura no chão e uma parede de magia, na velocidade da onda do servidor;
	-- atrás dela brotam cristais
	local reach = A.reach * s
	local speed = A.speed * s
	local seconds = reach / speed
	local wave = decal(Textures.wave, g * CFrame.new(0, 0.1, 0), color:Lerp(WHITE, 0.2), 1, reach * 2, seconds, seconds, nil, 2.5)
	TweenService:Create(wave, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(reach * 2, 0.05, reach * 2) }):Play()
	local wall = mesh("Band", color:Lerp(WHITE, 0.35), Enum.Material.Neon, 0.2)
	local rim = mesh("Band", WHITE, Enum.Material.Neon, 0.1)
	local height = A.height * s
	local nextShards = 0.05
	run(seconds, function(t)
		local r = math.max(t * reach, 0.5)
		local fade = math.clamp((t - 0.75) / 0.25, 0, 1)
		if wall then
			wall.place(g, Vector3.new(r / 10, height / 3 * (1 - fade * 0.6) * (0.9 + 0.1 * math.sin(t * 60)), r / 10))
			wall.part.Transparency = 0.2 + 0.8 * fade
		end
		if rim then
			rim.place(g, Vector3.new(r / 10 * 0.995, height / 3 * 0.45, r / 10 * 0.995))
			rim.part.Transparency = 0.1 + 0.9 * fade
		end
		if t >= nextShards and t < 0.85 then
			nextShards = t + 0.07
			local phase = rng:NextNumber(0, math.pi * 2)
			for i = 1, 8 do
				local a = phase + i / 8 * math.pi * 2
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				spike(ctx, g.Position + dir * (r - 2 * s), rng:NextNumber(3, 6) * s, dir, 0.3, "Shard", color:Lerp(WHITE, rng:NextNumber(0.1, 0.5)), Enum.Material.Neon)
			end
		end
	end, function()
		drop(wall, rim)
	end)
end

---------------------------------------------------------------------------------------------------
-- Morte: luz escapando pelas rachaduras, cada vez mais, até o corpo estourar

local CRACKS = {
	{ "Chest", Vector3.new(0, 18.8, -6.2) },
	{ "Head", Vector3.new(0, 25, -6) },
	{ "HandR", Vector3.new(10, 4, -1) },
	{ "Chest", Vector3.new(5, 16, -5) },
	{ "HandL", Vector3.new(-10, 4, -1) },
	{ "Chest", Vector3.new(-5, 20, -5) },
	{ "Chest", Vector3.new(3, 22, 5) },
	{ "Chest", Vector3.new(-4, 15, 5) },
}

local function deathStart(getCtx: () -> Ctx)
	local crumbleAt = (Anims.clips :: any).Death.events.crumble :: number
	local beams: { Mesh } = {}
	local count = 12
	for i = 1, count do
		task.delay(crumbleAt * (0.2 + 0.78 * math.sqrt(i / count)), function()
			local c = getCtx()
			local s = c.scale
			local spot = CRACKS[(i - 1) % #CRACKS + 1]
			local at = c.point(spot[1], spot[2] * s)
			local center = c.cf.Position + Vector3.new(0, 15 * s, 0)
			local dir = ((at - center).Unit + rng:NextUnitVector() * 0.6).Unit
			local beam = mesh("Pillar", c.glow:Lerp(WHITE, 0.6), Enum.Material.Neon, 0)
			if not beam then
				return
			end
			table.insert(beams, beam)
			local cf = CFrame.lookAt(at, at + dir) * CFrame.Angles(-math.pi / 2, 0, 0)
			local length = rng:NextNumber(1.0, 1.7) * s
			run(0.25, function(t)
				local w = 0.45 * s * outBack(t)
				beam.place(cf, Vector3.new(w, length * outQuint(t), w))
			end)
			pop(Textures.star, at, c.glow:Lerp(WHITE, 0.6), 2 * s, 9 * s, 0.3, 60)
			embers(at, c.glow, 10, 30)
			light(at, c.glow, 30, 3, 0.6)
			Fx.shake((0.15 + 0.25 * i / count) * c.near)
		end)
	end
	task.delay(crumbleAt + 0.02, function()
		for _, beam in beams do
			beam.part:Destroy()
		end
	end)
end

-- O estouro, no quadro em que as peças se soltam (src/client/Boss.luau chama).
function BossFx.death(ctx: Ctx)
	local s = ctx.scale
	local chest = ctx.point("Chest", Vector3.new(0, 18.8, -6.2) * s)
	local color = ctx.glow
	impactFrame(color)
	Fx.flash(WHITE, 0.35 * ctx.near, 0.3)
	Fx.shake(1.2 * ctx.near)
	shockwave(ctx, ctx.cf.Position, 45 * s, color, 0.9, true)
	Fx.burst(chest, color, 22 * s, 0.35)
	pop(Textures.spikes, chest, WHITE, 10 * s, 80 * s, 0.6, 30)
	light(chest, color, 90, 12, 1.5)
	embers(chest, color, 80, 70)
	dust(ctx.cf.Position + Vector3.new(0, 2, 0), Color3.fromRGB(70, 62, 60), 40, 9 * s, 55)
	decal(Textures.wave, ground(ctx, ctx.cf.Position), color:Lerp(WHITE, 0.4), 10, 140 * s, 0.8)
	-- a alma do golem sobe numa coluna de luz
	local soul = mesh("Pillar", color:Lerp(WHITE, 0.55), Enum.Material.Neon, 0.1)
	if soul then
		local base = ground(ctx, ctx.cf.Position)
		run(1.8, function(t)
			local width = 4 * s * (1 - t) ^ 1.2 * (1 + 0.08 * math.sin(t * 50))
			soul.place(base, Vector3.new(width, 10 * s * outQuint(math.min(t * 2, 1)), width))
			soul.part.Transparency = 0.1 + 0.9 * t ^ 2
		end, function()
			soul.part:Destroy()
		end)
	end
end

---------------------------------------------------------------------------------------------------

-- EXPERIMENTOS (src/shared/GolemExperiment.luau): o golpe novo do clip X fica em BossFx<X> e usa
-- as ferramentas daqui (kit) e as peças de terra de BossFxEarth.
local V2 = {
	SlamV2 = require(script.Parent.BossFxSlamV2),
	ChargeV2 = require(script.Parent.BossFxChargeV2),
}
local kit = {
	decal = decal, ground = ground, fire = fire, dust = dust, embers = embers, light = light, pop = pop,
	impactFrame = impactFrame, danger = danger, gather = gather, follow = follow, holder = holder,
	mesh = mesh, run = run, drop = drop, outQuint = outQuint, outBack = outBack, shockwave = shockwave,
	crescent = crescent, trail = trail, quake = quake,
}
local v2GetCtx: { [string]: () -> Ctx } = {}

-- Começo de cada animação (avisos, rastros).
function BossFx.start(clip: string, ctx: Ctx, getCtx: () -> Ctx)
	local v2 = V2[clip]
	if v2 then -- EXPERIMENTO
		v2GetCtx[clip] = getCtx
		v2.start(kit, ctx, getCtx, (Anims.clips :: any)[clip].events.impact)
	elseif clip == "Stomp" then
		stompStart(ctx, getCtx)
	elseif clip == "Sweep" then
		sweepStart(ctx, getCtx)
	elseif clip == "Slam" then
		slamStart(ctx, getCtx)
	elseif clip == "Charge" then
		chargeStart(ctx, getCtx)
	elseif clip == "Pulse" then
		pulseCharge(ctx, 1.0, getCtx)
	elseif clip == "Death" then
		deathStart(getCtx)
	end
end

-- Eventos marcados na animação (tools/blender/golem.py).
function BossFx.event(clip: string, name: string, ctx: Ctx)
	local v2 = V2[clip]
	if v2 then -- EXPERIMENTO
		local events = (Anims.clips :: any)[clip].events
		v2.event(kit, name, ctx, v2GetCtx[clip] or function()
			return ctx
		end, events.impact, events[name] or 0)
		return
	end
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
		shockwave(ctx, ctx.cf.Position, 40 * ctx.scale, ctx.glow, 0.8, true)
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
	Fx.shock(at, normal, if crit then Color3.fromRGB(255, 214, 40) else WHITE, if crit then 12 else 7, 0.22)
	Fx.cubes(at, color, if crit then 8 else 4, 18, normal * 20, 0.6)
	embers(at, color, if crit then 16 else 6, 30)
end

return BossFx
