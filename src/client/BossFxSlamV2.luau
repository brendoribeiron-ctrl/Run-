--!strict
-- EXPERIMENTO (Config.Boss.slamV2): efeitos do Esmagamento de Punhos com a animação nova
-- (tools/blender/golem_v2.py). src/client/BossFx.luau chama start/event quando o clip é "SlamV2" e
-- passa as ferramentas dele (kit); as peças de terra vêm de BossFxEarth.
--
-- Sequência (segundos do clip; o dano do servidor sai no impacto, 1,10 s):
--   0,00  aviso "!" e o círculo do golpe no chão (raio exato do dano), enchendo até o impacto
--   0,53  "rise": os punhos acendem e puxam energia
--   0,73  "hang": o chão da área treme, pedrinhas sobem e as rachaduras do círculo esquentam
--   1,10  impacto: quadro de impacto, clarão curto, cratera, onda curta no chão, anéis de luz
--   +0,03 a +0,45  erupção: rachaduras correm para fora e os espinhos rompem o chão atrás delas
--   +0,12 fumaça baixa rolando para fora; brasas saindo das rachaduras
--   +0,67 os punhos saem do chão soltando entulho
--   +1,3 a +2,2  os espinhos racham e afundam, a fumaça e as rachaduras somem

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Textures = require(ReplicatedStorage.Shared.Textures)
local Earth = require(script.Parent.BossFxEarth)
local Fx = require(script.Parent.Fx)

local A = Config.Boss.attacks.Slam
local WHITE, BLACK, DUST = Earth.WHITE, Earth.BLACK, Earth.DUST
local floor = Earth.floor

local SlamV2 = {}
local rng = Random.new()

-- Centro do golpe no chão (o mesmo ponto que o servidor usa para o dano).
local function target(ctx: any): Vector3
	return (ctx.cf * CFrame.new(0, 0, -A.ahead * ctx.scale)).Position
end

-- A erupção: rachaduras acesas correm do centro para fora pelos "raios" e os espinhos saem atrás
-- delas. Os de dentro são os maiores; os de fora, menores e mais inclinados.
local function eruption(kit: any, ctx: any, center: Vector3, detail: number)
	local s = ctx.scale
	local radius = A.radius * s
	local speed = 70 * s / 1.5 -- studs por segundo da rachadura (devagar o bastante para o olho seguir)
	local lanes = math.floor(11 * detail + 0.5)
	local phase = rng:NextNumber(0, math.pi * 2)
	-- miolo: os espinhos maiores, colados no impacto
	for i = 1, 5 do
		local a = phase + i / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		task.delay(0.03 + i * 0.012, Earth.spike, kit, ctx, center + dir * rng:NextNumber(4, 6.5) * s, rng:NextNumber(14, 18) * s, dir, rng:NextNumber(1.1, 1.4), true)
	end
	for lane = 1, lanes do
		local a = phase + (lane + 0.5 + rng:NextNumber(-0.25, 0.25)) / lanes * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local side = Vector3.new(-dir.Z, 0, dir.X)
		-- passa um pouco da área de dano (o círculo vermelho); os de fora são pequenos
		local reach = radius * rng:NextNumber(1.3, 1.55)
		Earth.crack(kit, ctx, center, dir, reach, speed, 0.4 * s)
		local d = rng:NextNumber(7, 8.5) * s
		while d < reach do
			local u = d / reach
			local height = (13 - 7.5 * u) * s * rng:NextNumber(0.8, 1.2)
			local at = center + dir * d + side * rng:NextNumber(-1.4, 1.4) * s
			task.delay(0.03 + d / speed, Earth.spike, kit, ctx, at, height, dir + side * rng:NextNumber(-0.25, 0.25), rng:NextNumber(0.8, 1.15) - u * 0.25, false)
			d += rng:NextNumber(2.8, 3.8) * s
		end
	end
end

local function impact(kit: any, ctx: any)
	local s = ctx.scale
	local center = target(ctx)
	local g = floor(kit, ctx, center)
	local r = ctx.point("HandR", Vector3.new(10, 1, -1.5) * s)
	local l = ctx.point("HandL", Vector3.new(-10, 1, -1.5) * s)
	local fists = (r + l) / 2
	local fistsGround = floor(kit, ctx, fists)
	local detail = if ctx.near > 0.45 then 1 else 0.6 -- longe da câmera: menos espinhos

	-- quadro 0: quadro de impacto, clarão curto e tremor forte
	kit.impactFrame(ctx.glow)
	Fx.flash(WHITE, 0.25 * ctx.near, 0.15)
	Fx.shake(0.95 * ctx.near)
	kit.light(fistsGround.Position + Vector3.new(0, 8, 0), ctx.glow, 60, 7, 0.9)
	Fx.burst(fistsGround.Position + Vector3.new(0, 2, 0), ctx.glow, 9 * s, 0.18)

	-- cratera sob os punhos: miolo escuro e rachaduras acesas que ficam
	kit.decal(Textures.glow, fistsGround * CFrame.new(0, 0.08, 0), BLACK, 6 * s, 15 * s, 0.15, 2.4, nil, 0.4)
	kit.decal(Textures.crack, g * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), ctx.glow, A.radius * s * 0.8, A.radius * s * 2.1, 0.18, 2.2, nil, 1.8)

	-- borda de onda no chão, curta e tingida: só leva o olho para fora
	local _, wave = kit.decal(Textures.wave, g * CFrame.new(0, 0.12, 0), ctx.glow, 6, A.radius * s * 1.9, 0.35, 0.02, nil, 1)
	wave.ImageTransparency = 0.6
	Earth.halos(kit, ctx, fists)

	-- entulho: pedra pesada e lascas acesas
	Fx.cubes(fistsGround.Position + Vector3.new(0, 2, 0), ctx.rock, math.floor(14 * detail), 34, Vector3.new(0, 32, 0), 1.5 * s)
	Fx.cubes(fistsGround.Position + Vector3.new(0, 2, 0), ctx.glow, math.floor(8 * detail), 40, Vector3.new(0, 38, 0), 0.6 * s, Enum.Material.Neon)
	kit.fire(fistsGround.Position + Vector3.new(0, 1, 0), ctx.glow, math.floor(12 * detail), 5 * s, 34, 60)
	kit.embers(fistsGround.Position + Vector3.new(0, 2, 0), ctx.glow, math.floor(30 * detail), 55)

	eruption(kit, ctx, center, detail)
	task.delay(0.12, Earth.smoke, kit, ctx, center, A.radius * s)
	Earth.smolder(kit, ctx, g, A.radius * s * 1.6, A.radius * s * 1.6, 1.6)

	-- os punhos saem do chão (quadro 53 do clip)
	task.delay(20 / 30, function()
		for _, fist in { r, l } do
			local base = floor(kit, ctx, fist).Position + Vector3.new(0, 1, 0)
			Fx.cubes(base, ctx.rock, 4, 18, Vector3.new(0, 16, 0), 0.9 * s)
			kit.dust(base, DUST, 4, 3 * s, 14)
		end
	end)
end

-- Começo do clip: aviso e o círculo da área.
function SlamV2.start(kit: any, ctx: any, getCtx: () -> any, impactAt: number)
	kit.danger(ctx)
	Earth.warnCircle(kit, getCtx, impactAt, A.radius * ctx.scale, target)
end

-- Eventos do clip (impact, rise, hang). now = segundo do evento no clip.
function SlamV2.event(kit: any, name: string, ctx: any, getCtx: () -> any, impactAt: number, now: number)
	local s = ctx.scale
	if name == "rise" then
		for _, side in { "HandR", "HandL" } do
			local x = if side == "HandR" then 10 else -10
			kit.light(ctx.point(side, Vector3.new(x, 4, -1) * s), ctx.glow, 28, 3, impactAt - now)
			kit.gather(kit.follow(getCtx, side, Vector3.new(x, 3, -1.5)), ctx.glow, impactAt - now - 0.05, 10 * s)
		end
	elseif name == "hang" then
		Earth.levitate(kit, getCtx, impactAt - now, A.radius * s, target)
		kit.dust(floor(kit, ctx, target(ctx)).Position + Vector3.new(0, 0.6, 0), DUST, 6, 3 * s, 6)
		Fx.shake(0.12 * ctx.near)
	elseif name == "impact" then
		impact(kit, ctx)
	end
end

return SlamV2
