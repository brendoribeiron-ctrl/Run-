--!strict
-- EXPERIMENTO (Config.Boss.chargeV2): efeitos do gancho da corrida com a animação nova
-- (tools/blender/golem_v2.py). src/client/BossFx.luau chama start/event quando o clip é
-- "ChargeV2" e passa as ferramentas dele (kit); as peças de terra vêm de BossFxEarth.
--
-- Sequência (segundos do clip; o dano do servidor sai no impacto, 0,60 s):
--   0,00  aviso "!" e o círculo do golpe no chão (raio exato do dano), enchendo até o impacto
--   0,17  "brake": os pés fincam e derrapam (poeira e pedra jogadas para a frente)
--   0,33  "coil": o braço armado puxa energia, rastro aceso no punho
--   0,60  impacto: o punho crava no chão (quadro de impacto, cratera) e uma fileira de espinhos
--         dispara para a frente atrás de uma rachadura, cada um maior que o anterior, com lascas
--         para os lados
--   0,73  "rip": o punho arranca o chão num gancho: lua de luz subindo, pedras jogadas para cima
--   +1,0 a +1,6  os espinhos racham e afundam; fumaça e brasas ao longo da fileira somem

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Textures = require(ReplicatedStorage.Shared.Textures)
local Earth = require(script.Parent.BossFxEarth)
local Fx = require(script.Parent.Fx)

local A = Config.Boss.attacks.Charge
local WHITE, BLACK, DUST = Earth.WHITE, Earth.BLACK, Earth.DUST
local floor = Earth.floor

local ChargeV2 = {}
local rng = Random.new()

-- Centro do golpe no chão (o mesmo ponto que o servidor usa para o dano).
local function target(ctx: any): Vector3
	return (ctx.cf * CFrame.new(0, 0, -A.ahead * ctx.scale)).Position
end

local function fist(ctx: any): Vector3
	return ctx.point("HandR", Vector3.new(10, 1, -1.5) * ctx.scale)
end

-- Fileira de espinhos que dispara do punho para a frente.
local function row(kit: any, ctx: any, origin: Vector3, detail: number)
	local s = ctx.scale
	local look = ctx.cf.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local side = Vector3.new(-forward.Z, 0, forward.X)
	local count = math.floor(9 * detail + 0.5)
	local step = 3.4 * s
	local speed = 95 * s / 1.5 -- studs por segundo da frente da erupção
	local length = step * (count + 0.5)
	Earth.crack(kit, ctx, origin, forward, length, speed * 1.15, 0.5 * s)
	for i = 1, count do
		local u = i / count
		local d = step * i
		local at = origin + forward * d + side * (if i % 2 == 0 then 1 else -1) * rng:NextNumber(0.4, 1.3) * s
		local delay = 0.02 + d / speed
		-- crescendo: os de trás pequenos, os da ponta enormes
		local height = (5 + 10 * u ^ 1.3) * s * rng:NextNumber(0.9, 1.1)
		local big = u > 0.7
		-- inclinados para a frente, como se a onda os empurrasse
		task.delay(delay, Earth.spike, kit, ctx, at, height, forward + side * rng:NextNumber(-0.2, 0.2), 0.8 + 0.5 * u, big, rng:NextNumber(22, 34) * (1 - 0.4 * u))
		-- lascas para os lados
		if detail >= 1 or i % 2 == 0 then
			for _, sign in { -1, 1 } do
				local out = (side * sign + forward * 0.4).Unit
				task.delay(delay + 0.03, Earth.spike, kit, ctx, at + side * sign * rng:NextNumber(2.2, 3.4) * s, height * rng:NextNumber(0.35, 0.5), out, 0.5 + 0.3 * u, false)
			end
		end
		-- fumaça baixa saindo para os lados
		if i % 2 == 1 then
			task.delay(delay + 0.05, Earth.puff, kit, ctx, at, side * (if i % 4 == 1 then 1 else -1), 3, 30)
		end
	end
	local mid = floor(kit, ctx, origin + forward * length / 2)
	Earth.smolder(kit, ctx, CFrame.lookAt(mid.Position, mid.Position + forward), 5 * s, length, 1.4)
	-- a ponta: um clarão quando o último espinho rompe
	task.delay(0.02 + step * count / speed + 0.08, function()
		local tip = floor(kit, ctx, origin + forward * step * count).Position
		kit.light(tip + Vector3.new(0, 6, 0), ctx.glow, 40, 5, 0.6)
		Fx.cubes(tip + Vector3.new(0, 2, 0), ctx.rock, 6, 30, Vector3.new(0, 30, 0) + forward * 20, 1.1 * s)
		Fx.shake(0.25 * ctx.near)
	end)
end

local function impact(kit: any, ctx: any)
	local s = ctx.scale
	local hit = floor(kit, ctx, fist(ctx))
	local detail = if ctx.near > 0.45 then 1 else 0.6

	kit.impactFrame(ctx.glow)
	Fx.flash(WHITE, 0.2 * ctx.near, 0.12)
	Fx.shake(0.85 * ctx.near)
	kit.light(hit.Position + Vector3.new(0, 6, 0), ctx.glow, 50, 6, 0.7)
	Fx.burst(hit.Position + Vector3.new(0, 1.5, 0), ctx.glow, 7 * s, 0.16)
	-- cratera do punho e rachadura acesa embaixo
	kit.decal(Textures.glow, hit * CFrame.new(0, 0.08, 0), BLACK, 4 * s, 11 * s, 0.12, 1.8, nil, 0.4)
	kit.decal(Textures.crack, hit * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), ctx.glow, 6 * s, 18 * s, 0.15, 1.6, nil, 1.8)
	local _, wave = kit.decal(Textures.wave, hit * CFrame.new(0, 0.12, 0), ctx.glow, 4, A.radius * s * 1.6, 0.3, 0.02, nil, 1)
	wave.ImageTransparency = 0.6
	Fx.cubes(hit.Position + Vector3.new(0, 2, 0), ctx.rock, math.floor(10 * detail), 30, Vector3.new(0, 26, 0), 1.3 * s)
	kit.embers(hit.Position + Vector3.new(0, 2, 0), ctx.glow, math.floor(20 * detail), 45)
	row(kit, ctx, hit.Position, detail)
end

-- O punho arranca o chão num gancho.
local function rip(kit: any, ctx: any)
	local s = ctx.scale
	local at = fist(ctx)
	local base = floor(kit, ctx, at)
	kit.crescent(ctx.cf * CFrame.new(5 * s, 10 * s, -6 * s) * CFrame.Angles(0, 0, math.pi / 2), 12 * s, ctx.glow, 0.32, 1.1, -1.3)
	Fx.cubes(base.Position + Vector3.new(0, 2, 0), ctx.rock, 8, 20, Vector3.new(0, 55, 0) + ctx.cf.LookVector * 10, 1.2 * s)
	Fx.cubes(base.Position + Vector3.new(0, 2, 0), ctx.glow, 5, 22, Vector3.new(0, 60, 0), 0.5 * s, Enum.Material.Neon)
	for i = 0, 3 do
		task.delay(i * 0.035, kit.fire, base.Position + Vector3.new(0, i * 4 * s, 0), ctx.glow, 6, 5 * s, 40, 18)
	end
	Earth.halos(kit, ctx, base.Position, 0.7)
	kit.dust(base.Position + Vector3.new(0, 1, 0), DUST, 6, 3 * s, 18)
	Fx.shake(0.3 * ctx.near)
end

-- Começo do clip: aviso e a área do golpe.
function ChargeV2.start(kit: any, ctx: any, getCtx: () -> any, impactAt: number)
	kit.danger(ctx)
	Earth.warnCircle(kit, getCtx, impactAt, A.radius * ctx.scale, target)
end

-- Eventos do clip (brake, coil, impact, rip). now = segundo do evento no clip.
function ChargeV2.event(kit: any, name: string, ctx: any, getCtx: () -> any, impactAt: number, now: number)
	local s = ctx.scale
	if name == "brake" then
		-- os pés fincam: poeira e pedra jogadas para a frente, riscos no chão
		local forward = ctx.cf.LookVector
		for _, foot in { "FootR", "FootL" } do
			local x = if foot == "FootR" then 3.6 else -3.6
			local at = floor(kit, ctx, ctx.point(foot, Vector3.new(x, 0, -1.5) * s)).Position
			kit.dust(at + Vector3.new(0, 1, 0), DUST, 6, 3 * s, 22)
			Fx.cubes(at + Vector3.new(0, 1, 0), ctx.rock, 4, 14, forward * 30 + Vector3.new(0, 12, 0), 0.8 * s)
			Earth.puff(kit, ctx, at, forward, 2, 26)
			kit.decal(Textures.crack, CFrame.lookAt(at, at + forward) * CFrame.new(0, 0.3, 0), ctx.glow, 2 * s, 7 * s, 0.12, 1.2, nil, 1.4)
		end
		Fx.shake(0.25 * ctx.near)
	elseif name == "coil" then
		local hand = getCtx().part("HandR")
		kit.light(fist(ctx), ctx.glow, 26, 3, impactAt - now)
		kit.gather(kit.follow(getCtx, "HandR", Vector3.new(10, 2, -1.5)), ctx.glow, impactAt - now - 0.03, 8 * s)
		kit.trail(hand, ctx.glow, 5 * s, impactAt - now + 0.35)
		kit.trail(getCtx().part("ForearmR"), ctx.glow:Lerp(BLACK, 0.3), 4 * s, impactAt - now + 0.3)
	elseif name == "impact" then
		impact(kit, ctx)
	elseif name == "rip" then
		rip(kit, ctx)
	end
end

return ChargeV2
