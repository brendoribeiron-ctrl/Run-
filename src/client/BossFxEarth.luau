--!strict
-- Peças de efeito de terra dos golpes novos do golem (BossFxSlamV2, BossFxChargeV2): aviso no
-- chão, espinho que rompe o chão, rachadura que corre, pedrinhas tremendo, anéis de luz, fumaça
-- baixa e brasas. Recebem o kit de src/client/BossFx.luau (decal, mesh, run, dust...), para os
-- golpes novos terem a mesma cara dos antigos.
--
-- Regras que custaram tentativa (ver a skill roblox-boss-attack-overhaul):
--   * decalques 0,25 acima do kit.ground: as runas de neon do estrado da sala ficam na mesma
--     altura e escondiam o aviso e as rachaduras;
--   * aviso vermelho (DANGER), feito de SurfaceGui com UICorner/UIStroke: a textura "circle" tem
--     traço fino e some no piso; ciano some no círculo mágico da sala, que é ciano;
--   * rocha dos espinhos mais clara que a do golem e com miolo de neon grosso: no piso escuro a
--     rocha original some;
--   * nada de cúpula/onda grande e clara: com o Bloom vira um borrão branco que esconde tudo.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Textures = require(ReplicatedStorage.Shared.Textures)
local Fx = require(script.Parent.Fx)

local Earth = {}
local rng = Random.new()

Earth.WHITE = Color3.new(1, 1, 1)
Earth.BLACK = Color3.new(0, 0, 0)
Earth.DUST = Color3.fromRGB(78, 70, 68)
Earth.DANGER = Color3.fromRGB(255, 40, 30)
local WHITE, DUST, DANGER = Earth.WHITE, Earth.DUST, Earth.DANGER

-- Chão para decalques: um pouco acima do kit.ground (runas do estrado).
function Earth.floor(kit: any, ctx: any, at: Vector3): CFrame
	return kit.ground(ctx, at) * CFrame.new(0, 0.25, 0)
end
local floor = Earth.floor

---------------------------------------------------------------------------------------------------
-- Aviso no chão: placa com SurfaceGui; `shape` desenha nela e devolve `update(u)` (u de 0 a 1 até o
-- impacto). A placa acompanha `place(ctx)` (o golem ainda vira na preparação) e some no impacto.

type Shape = (gui: SurfaceGui) -> ((u: number, t: number) -> ())

local function paint(kit: any, getCtx: () -> any, impactAt: number, size: Vector2, place: (ctx: any) -> CFrame, shape: Shape, crack: boolean)
	local ctx = getCtx()
	local plate = Fx.part(Vector3.new(size.X, 0.05, size.Y), place(ctx), DANGER)
	plate.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(512, 512 * size.Y / size.X)
	gui.LightInfluence = 0
	gui.Brightness = 2.2
	gui.Parent = plate
	local update = shape(gui)
	local cracks: Part?, crackImage: ImageLabel? = nil, nil
	if crack then
		cracks, crackImage = kit.decal(Textures.crack, place(ctx) * CFrame.new(0, 0.03, 0), ctx.glow, size.X * 0.8, size.X * 0.8, 0.01, impactAt + 0.05, nil, 1.2)
		;(crackImage :: ImageLabel).ImageTransparency = 1
	end
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if t >= impactAt or not plate.Parent then
			connection:Disconnect()
			-- some rápido: no impacto quem fala é o golpe
			for _, d in gui:GetDescendants() do
				if d:IsA("Frame") then
					TweenService:Create(d, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(0.12), { Transparency = 1 }):Play()
				end
			end
			Debris:AddItem(plate, 0.2)
			return
		end
		local c = getCtx()
		local cf = place(c)
		plate.CFrame = cf
		local u = t / impactAt
		update(u, t)
		if cracks and crackImage then
			cracks.CFrame = cf * CFrame.new(0, 0.03, 0)
			crackImage.ImageTransparency = 1 - 0.85 * math.clamp((u - 0.55) / 0.45, 0, 1) ^ 2
			crackImage.ImageColor3 = c.glow:Lerp(WHITE, 0.4 * u)
		end
	end)
end

local function frame(parent: Instance, round: boolean): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = DANGER
	f.BorderSizePixel = 0
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
	end
	f.Parent = parent
	return f
end

local function edge(f: Frame): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = DANGER
	stroke.Thickness = 7
	stroke.Transparency = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	return stroke
end

-- Círculo do raio exato do dano: borda nítida e miolo que cresce do centro e encosta na borda no
-- instante do impacto (diz onde e quando).
function Earth.warnCircle(kit: any, getCtx: () -> any, impactAt: number, radius: number, center: (ctx: any) -> Vector3)
	paint(kit, getCtx, impactAt, Vector2.new(radius * 2, radius * 2), function(c)
		return floor(kit, c, center(c))
	end, function(gui)
		local border = frame(gui, true)
		border.AnchorPoint = Vector2.new(0.5, 0.5)
		border.Position = UDim2.fromScale(0.5, 0.5)
		border.Size = UDim2.fromScale(1, 1)
		border.BackgroundTransparency = 1
		local stroke = edge(border)
		local fill = frame(gui, true)
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		return function(u, t)
			stroke.Transparency = 1 - math.min(t / 0.2, 1) * (0.85 + 0.15 * math.sin(t * 20) * u)
			local grow = u ^ 1.6
			fill.Size = UDim2.fromScale(grow, grow)
			fill.BackgroundTransparency = 0.78 - 0.2 * u
		end
	end, true)
end

-- Faixa reta à frente de `origin(ctx)` na direção `dir(ctx)`: borda nítida e miolo que corre da
-- base até a ponta no instante do impacto.
function Earth.warnLine(kit: any, getCtx: () -> any, impactAt: number, length: number, width: number, origin: (ctx: any) -> Vector3, dir: (ctx: any) -> Vector3)
	paint(kit, getCtx, impactAt, Vector2.new(width, length), function(c)
		local o = floor(kit, c, origin(c))
		local d = dir(c)
		local flat = Vector3.new(d.X, 0, d.Z).Unit
		return CFrame.lookAt(o.Position, o.Position + flat) * CFrame.new(0, 0, -length / 2)
	end, function(gui)
		local border = frame(gui, false)
		border.Size = UDim2.fromScale(1, 1)
		border.BackgroundTransparency = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = border
		local stroke = edge(border)
		local fill = frame(gui, false)
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0.5, 0)
		fillCorner.Parent = fill
		-- a placa olha para a frente: a ponta da faixa é o topo do SurfaceGui
		fill.AnchorPoint = Vector2.new(0.5, 1)
		fill.Position = UDim2.fromScale(0.5, 1)
		return function(u, t)
			stroke.Transparency = 1 - math.min(t / 0.2, 1) * (0.85 + 0.15 * math.sin(t * 20) * u)
			fill.Size = UDim2.fromScale(1, math.max(u ^ 1.4, 0.02))
			fill.BackgroundTransparency = 0.75 - 0.2 * u
		end
	end, true)
end

---------------------------------------------------------------------------------------------------
-- Antecipação

-- Pedrinhas que sobem tremendo do chão em volta de `center(ctx)`; em `until_` são arremessadas.
function Earth.levitate(kit: any, getCtx: () -> any, until_: number, radius: number, center: (ctx: any) -> Vector3, count: number?)
	local ctx = getCtx()
	local s = ctx.scale
	local rocks = {}
	for i = 1, count or 12 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = radius * math.sqrt(rng:NextNumber(0.05, 0.9))
		local cube = Fx.part(Vector3.one * rng:NextNumber(0.5, 1.3) * s, CFrame.new(), if i % 4 == 0 then ctx.glow else ctx.rock, if i % 4 == 0 then Enum.Material.Neon else Enum.Material.Slate)
		rocks[i] = { part = cube, offset = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rise = rng:NextNumber(1.5, 4.5) * s, spin = rng:NextUnitVector() * rng:NextNumber(1, 3), seed = rng:NextNumber(0, 10) }
	end
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		local c = getCtx()
		local at = floor(kit, c, center(c)).Position
		if t >= until_ then
			connection:Disconnect()
			for _, rock in rocks do
				local part = rock.part
				part.Anchored = false
				part.AssemblyLinearVelocity = Vector3.new(rock.offset.X * 1.2, rng:NextNumber(55, 85), rock.offset.Z * 1.2)
				part.AssemblyAngularVelocity = rock.spin * 6
				TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7), { Transparency = 1 }):Play()
				Debris:AddItem(part, 1.1)
			end
			return
		end
		local u = math.clamp(t / until_, 0, 1)
		local lift = u * u
		for _, rock in rocks do
			local jitter = Vector3.new(math.sin(t * 47 + rock.seed), math.sin(t * 61 + rock.seed * 2), math.cos(t * 53 + rock.seed)) * 0.18 * s * u
			rock.part.CFrame = CFrame.new(at + rock.offset + Vector3.new(0, 0.3 + rock.rise * lift, 0) + jitter) * CFrame.Angles(rock.spin.X * t, rock.spin.Y * t, rock.spin.Z * t)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Espinho

-- Rocha que rompe o chão inclinada para `out`: uma rachadura acesa 0,06 s antes, sai com
-- passa-do-ponto, solta lascas da ponta, segura `hold`, racha e afunda soltando pedaços.
-- `lean` = graus de inclinação (padrão: 8-20 grande, 18-38 pequeno).
function Earth.spike(kit: any, ctx: any, at: Vector3, height: number, out: Vector3, hold: number, big: boolean, lean: number?)
	local s = ctx.scale
	local g = floor(kit, ctx, at)
	kit.decal(Textures.crack, g * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), ctx.glow, height * 0.3, height * 0.75, 0.08, 0.5, nil, 1.8)
	task.delay(0.06, function()
		local m = kit.mesh(if rng:NextNumber() < 0.5 then "SpikeA" else "SpikeB", ctx.rock:Lerp(WHITE, 0.28), Enum.Material.Slate)
		if not m then
			return
		end
		local hot = kit.mesh("SpikeB", ctx.glow, Enum.Material.Neon, 0)
		local flat = Vector3.new(out.X, 0, out.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		end
		flat = flat.Unit
		local yaw = math.atan2(-flat.X, -flat.Z)
		local tilt = math.rad(lean or (if big then rng:NextNumber(8, 20) else rng:NextNumber(18, 38)))
		local cf = g * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-tilt, 0, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local k = height / 10
		local size = Vector3.new(k * rng:NextNumber(0.75, 1.25), k, k * rng:NextNumber(0.75, 1.25))
		local hotSize = Vector3.new(k * 0.55, k * 1.07, k * 0.55)
		local function place(cframe: CFrame, scale: Vector3, heat: number)
			m.place(cframe, scale)
			if hot then
				hot.place(cframe, Vector3.new(hotSize.X * scale.X / size.X, hotSize.Y * scale.Y / size.Y, hotSize.Z * scale.Z / size.Z))
				hot.part.Transparency = heat
			end
		end
		place(cf * CFrame.new(0, -height, 0), size, 0)
		local base = g.Position + Vector3.new(0, 0.6, 0)
		kit.dust(base, DUST, if big then 6 else 3, (if big then 3.2 else 2) * s, if big then 26 else 16)
		Fx.cubes(base, ctx.rock, if big then 5 else 2, if big then 26 else 16, Vector3.new(0, 18, 0) + flat * 8, (if big then 0.9 else 0.6) * s)
		kit.run(if big then 0.16 else 0.12, function(t)
			local e = kit.outBack(t)
			-- mais fino enquanto sobe (velocidade), engorda no fim
			local squeeze = 0.8 + 0.2 * math.min(t * 1.4, 1)
			place(cf * CFrame.new(0, -height * (1 - e), 0), Vector3.new(size.X * squeeze, size.Y, size.Z * squeeze), 0)
		end, function()
			Fx.cubes((cf * CFrame.new(0, height * 0.85, 0)).Position, ctx.rock, if big then 3 else 1, 14, Vector3.new(0, 10, 0), 0.5 * s)
			task.delay(hold, function()
				local cracked = false
				kit.run(0.45, function(t)
					local sink = height * (0.04 + 0.9 * t * t)
					place(cf * CFrame.new(0, -sink, 0) * CFrame.Angles(0, 0, math.rad(3 * t)), Vector3.new(size.X * (1 - 0.25 * t), size.Y, size.Z * (1 - 0.25 * t)), math.min(0.35 + t * 1.5, 1))
					m.part.Transparency = math.max(t * 1.8 - 0.8, 0)
					if t > 0.12 and not cracked then
						cracked = true
						Fx.cubes((cf * CFrame.new(0, height * 0.45, 0)).Position, ctx.rock, if big then 4 else 2, 12, Vector3.new(0, 4, 0), 0.7 * s)
						kit.dust(base, DUST, 2, 2.4 * s, 8)
					end
				end, function()
					kit.drop(m, hot)
				end)
			end)
		end)
	end)
end

-- Rachadura acesa que corre de `from` na direção `dir` até `reach`, a `speed` studs/s, e apaga.
function Earth.crack(kit: any, ctx: any, from: Vector3, dir: Vector3, reach: number, speed: number, width: number)
	local g = floor(kit, ctx, from)
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local look = CFrame.lookAt(g.Position, g.Position + flat)
	local bar = Fx.part(Vector3.new(0.1, 0.08, 0.1), look, ctx.glow:Lerp(WHITE, 0.3), Enum.Material.Neon)
	kit.run(reach / speed, function(t)
		local length = math.max(reach * t, 0.1)
		bar.Size = Vector3.new(width * (1 - 0.5 * t), 0.08, length)
		bar.CFrame = look * CFrame.new(0, 0.05, -length / 2)
	end, function()
		kit.run(0.6, function(t)
			bar.Transparency = t
		end, function()
			bar:Destroy()
		end)
	end)
end

---------------------------------------------------------------------------------------------------
-- Impacto e depois

-- Anéis de luz deitados subindo de `at`, um dentro do outro.
function Earth.halos(kit: any, ctx: any, at: Vector3, size: number?)
	local s = ctx.scale * (size or 1)
	local g = floor(kit, ctx, at)
	for i = 0, 2 do
		task.delay(i * 0.06, function()
			local ring = kit.mesh("Ring", ctx.glow:Lerp(WHITE, 0.15 * i), Enum.Material.Neon, 0.35)
			if not ring then
				return
			end
			local from, to = (0.7 - i * 0.12) * s, (1.9 - i * 0.35) * s
			kit.run(0.5, function(t)
				local e = kit.outQuint(t)
				local r = from + (to - from) * e
				ring.place(g * CFrame.new(0, (2 + 14 * e) * s * (1 - i * 0.2), 0), Vector3.new(r, 0.1 * (1 - 0.7 * t), r))
				ring.part.Transparency = 0.35 + 0.65 * t ^ 1.3
			end, function()
				kit.drop(ring)
			end)
		end)
	end
end

-- Uma baforada de fumaça baixa que rola de `at` na direção `dir`.
function Earth.puff(kit: any, ctx: any, at: Vector3, dir: Vector3, count: number, speed: number)
	local s = ctx.scale
	local p = kit.holder(at + Vector3.new(0, 1.2, 0))
	local flat = Vector3.new(dir.X, 0, dir.Z)
	p.CFrame = CFrame.lookAt(p.Position, p.Position + (if flat.Magnitude > 0.01 then flat.Unit else Vector3.xAxis))
	local e = Instance.new("ParticleEmitter")
	e.Texture = Textures.glow
	e.EmissionDirection = Enum.NormalId.Front
	e.Rate = 0
	e.Lifetime = NumberRange.new(1.2, 2.0)
	e.Speed = NumberRange.new(speed * 0.6, speed)
	e.SpreadAngle = Vector2.new(18, 6)
	e.Drag = 2.6
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3 * s), NumberSequenceKeypoint.new(0.4, 6 * s), NumberSequenceKeypoint.new(1, 8 * s) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(DUST:Lerp(ctx.glow, 0.12), DUST)
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 2.2)
end

-- Fumaça baixa rolando para fora de uma cratera, em volta.
function Earth.smoke(kit: any, ctx: any, at: Vector3, radius: number)
	local count = 10
	for i = 1, count do
		local a = (i + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		Earth.puff(kit, ctx, at + dir * radius * 0.25, dir, 4, 44)
	end
end

-- Brasas subindo de uma área (placa `width` x `length` deitada em `cf`) por um tempo.
function Earth.smolder(kit: any, ctx: any, cf: CFrame, width: number, length: number, seconds: number)
	local p = kit.holder(cf.Position + Vector3.new(0, 0.4, 0))
	p.CFrame = cf + Vector3.new(0, 0.4, 0)
	p.Size = Vector3.new(width, 0.2, length)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Textures.star
	e.Rate = 34
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(4, 12)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, 6, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(ctx.glow:Lerp(WHITE, 0.5), ctx.glow)
	e.LightEmission = 1
	e.Parent = p
	task.delay(seconds, function()
		e.Enabled = false
	end)
	Debris:AddItem(p, seconds + 1.3)
end

return Earth
