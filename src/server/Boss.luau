--!strict
-- O golem da sala do chefe, no servidor (modelo e animações em tools/blender/golem.py).
--
-- O servidor não mexe nas peças: ele guarda onde o golem está (a peça Root), qual animação está
-- tocando e desde quando (atributos Clip e ClipStart, em tempo do servidor) e a vida. Cada
-- cliente move as peças do seu golem com src/shared/GolemAnims.luau, e como os dois lados contam
-- o tempo da mesma animação, o dano sai no mesmo quadro em que o golpe acerta na tela.
--
-- Luta: dorme ajoelhado; quem desafia acorda ele. Anda devagar até o alvo, corre se ele estiver
-- longe e solta um gancho no fim da corrida; de perto escolhe entre pisão, varredura,
-- esmagamento de punhos e o pulso de magia (a onda que só se esquiva pulando). Depois de cada
-- golpe fica parado, cansado: é a hora de bater. Com menos da metade da vida fica mais rápido.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(script.Parent.Models)
local PlayerData = require(script.Parent.PlayerData)
local State = require(script.Parent.State)

local BOSS = Config.Boss
local ROOM = Config.BossRoom
local K = ROOM.scale
local S = BOSS.scale

local Boss = {}
-- Ligados pelo BossRoom: vitória (sorteio) e derrota (perde o sorteio).
Boss.onVictory = nil :: ((Player) -> ())?
Boss.onDefeat = nil :: ((Player) -> ())?

type Golem = {
	world: any,
	center: Vector3,
	model: Model,
	root: Part,
	body: Part,
	prompt: ProximityPrompt?,
	state: string, -- sleep | wake | idle | walk | run | attack | dead
	clip: string,
	started: number,
	position: Vector3,
	yaw: number,
	hp: number,
	maxHp: number,
	rage: boolean,
	attack: string?,
	attackId: number,
	restUntil: number,
	lastAttack: string?,
	emptySince: number?,
	deadAt: number,
}

local golems: { [number]: Golem } = {}
local lastPunch: { [Player]: number } = {}
local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local M = Enum.Material
-- arcano (mundo 1): pedra azul-noite e fissuras de magia azul; magma (mundo 2): basalto e brasa
local STYLES: { { [string]: Models.Style } } = {
	{
		Rock = { color = rgb(36, 38, 54), material = M.Slate },
		Plate = { color = rgb(62, 66, 90), material = M.Slate },
		Trim = { color = rgb(255, 196, 72), material = M.Metal },
		Magma = { color = rgb(80, 190, 255), material = M.Neon },
		Ember = { color = rgb(220, 245, 255), material = M.Neon },
	},
	{
		Rock = { color = rgb(38, 28, 28), material = M.Basalt },
		Plate = { color = rgb(66, 48, 46), material = M.Basalt },
		Trim = { color = rgb(255, 168, 56), material = M.Metal },
		Magma = { color = rgb(255, 84, 20), material = M.Neon },
		Ember = { color = rgb(255, 216, 96), material = M.Neon },
	},
}
Boss.STYLES = STYLES

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Altura do piso: o estrado do círculo do centro é um degrau.
local function floorAt(g: Golem, at: Vector3): number
	return g.center.Y + (if flat(at - g.center).Magnitude < 15 * K then 1.1 * K else 0)
end

local function cframe(g: Golem): CFrame
	return CFrame.new(g.position) * CFrame.Angles(0, g.yaw, 0)
end

local function place(g: Golem)
	g.position = Vector3.new(g.position.X, floorAt(g, g.position), g.position.Z)
	local cf = cframe(g)
	g.root.CFrame = cf
	g.body.CFrame = cf * CFrame.new(0, 12 * S, 0)
end

local function play(g: Golem, clip: string)
	g.clip = clip
	g.started = now()
	g.model:SetAttribute("Clip", clip)
	g.model:SetAttribute("ClipStart", g.started)
end

local function length(clip: string): number
	return (Anims.clips :: any)[clip].length
end

local function event(clip: string, name: string): number
	return (Anims.clips :: any)[clip].events[name]
end

local function remote(): RemoteEvent
	return State.remotes.Boss :: RemoteEvent
end

-- Quem está na sala deste golem, vivo.
local function fighters(g: Golem): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Room") == g.world.id then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
				table.insert(list, player)
			end
		end
	end
	return list
end

local function toRoom(g: Golem, ...: any)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Room") == g.world.id then
			remote():FireClient(player, ...)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Dano no jogador

local function hurt(g: Golem, player: Player, amount: number, from: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local damage = math.floor(amount * (if g.rage then BOSS.rageDamage else 1) + 0.5)
	humanoid:TakeDamage(damage)
	local away = flat(root.Position - from)
	local dir = if away.Magnitude > 0.1 then away.Unit else -cframe(g).LookVector
	remote():FireClient(player, "hit", damage, dir)
	if humanoid.Health <= 0 then
		-- derrotado pelo golem: perde o sorteio desta corrida
		if Boss.onDefeat then
			(Boss.onDefeat :: any)(player)
		end
		remote():FireClient(player, "defeat")
	end
end

-- Jogadores dentro de um círculo no chão (quem pulou alto o bastante escapa).
local function inCircle(g: Golem, at: Vector3, radius: number, height: number): { Player }
	local list = {}
	for _, player in fighters(g) do
		local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
		local d = flat(root.Position - at).Magnitude
		if d <= radius and root.Position.Y - floorAt(g, root.Position) < height then
			table.insert(list, player)
		end
	end
	return list
end

local function strike(g: Golem, name: string)
	local A = (BOSS.attacks :: any)[name]
	local cf = cframe(g)
	local function ahead(forward: number, side: number?): Vector3
		return (cf * CFrame.new((side or 0) * S, 0, -forward * S)).Position
	end
	if name == "Stomp" then
		local at = ahead(A.ahead, A.side)
		for _, player in inCircle(g, at, A.radius * S, 7) do
			hurt(g, player, A.damage, at)
		end
	elseif name == "Slam" or name == "Charge" then
		local at = ahead(A.ahead)
		for _, player in inCircle(g, at, A.radius * S, 9) do
			hurt(g, player, A.damage, at)
		end
	elseif name == "Sweep" then
		local look = flat(cf.LookVector).Unit
		for _, player in inCircle(g, g.position, A.radius * S, 9) do
			local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
			local to = flat(root.Position - g.position)
			local angle = if to.Magnitude < 0.1 then 0 else math.deg(math.acos(math.clamp(to.Unit:Dot(look), -1, 1)))
			if angle <= A.arc / 2 then
				hurt(g, player, A.damage, g.position)
			end
		end
	elseif name == "Pulse" then
		-- onda de magia que corre pelo chão a partir da mão apoiada: quem está no chão quando a
		-- borda passa leva o dano; pular na hora certa esquiva
		local origin = ahead(A.ahead, A.side)
		local hit: { [Player]: boolean } = {}
		local radius = 0
		local id = g.attackId
		while radius < A.reach * S and g.attackId == id and g.state ~= "dead" do
			local dt = RunService.Heartbeat:Wait()
			local before = radius
			radius += A.speed * S * dt
			for _, player in fighters(g) do
				if not hit[player] then
					local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
					local d = flat(root.Position - origin).Magnitude
					if d <= radius and d >= before - 4 and root.Position.Y - floorAt(g, root.Position) < A.height then
						hit[player] = true
						hurt(g, player, A.damage, origin)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Estados

local function reset(g: Golem)
	g.state = "sleep"
	g.attack = nil
	g.attackId += 1
	g.rage = false
	g.maxHp = BOSS.hp[g.world.id] or BOSS.hp[1]
	g.hp = g.maxHp
	g.emptySince = nil
	-- ajoelhado no círculo, de frente para a porta (+Z)
	g.position = g.center
	g.yaw = math.pi
	place(g)
	play(g, "Sleep")
	g.body.CanCollide = true
	g.model:SetAttribute("Hp", g.hp)
	g.model:SetAttribute("MaxHp", g.maxHp)
	g.model:SetAttribute("Rage", false)
	g.model:SetAttribute("Defeated", false)
	g.model:SetAttribute("State", g.state)
	if g.prompt then
		g.prompt.Enabled = true
	end
end

local function setState(g: Golem, state: string)
	g.state = state
	g.model:SetAttribute("State", state)
end

local function startAttack(g: Golem, name: string)
	setState(g, "attack")
	g.attack = name
	g.lastAttack = name
	g.attackId += 1
	local id = g.attackId
	play(g, name)
	local events = (Anims.clips :: any)[name].events
	local at = events.impact or events.pulse
	task.delay(at, function()
		if g.attackId == id and g.state == "attack" then
			strike(g, name)
		end
	end)
end

local function chooseAttack(g: Golem): string
	local pool = {}
	local total = 0
	for _, name in { "Stomp", "Sweep", "Slam", "Pulse" } do
		local weight = (BOSS.attacks :: any)[name].weight
		if name == g.lastAttack then
			weight *= 0.25 -- raramente repete o mesmo golpe
		end
		if name == "Pulse" and g.rage then
			weight *= 1.6
		end
		table.insert(pool, { name, weight })
		total += weight
	end
	local pick = rng:NextNumber() * total
	for _, entry in pool do
		pick -= entry[2]
		if pick <= 0 then
			return entry[1]
		end
	end
	return "Stomp"
end

-- Vira o golem para o alvo, no máximo `speed` radianos por segundo. Devolve o ângulo que falta.
local function turn(g: Golem, target: Vector3, speed: number, dt: number): number
	local to = flat(target - g.position)
	if to.Magnitude < 0.1 then
		return 0
	end
	local want = math.atan2(-to.X, -to.Z)
	local diff = (want - g.yaw + math.pi) % (2 * math.pi) - math.pi
	g.yaw += math.clamp(diff, -speed * dt, speed * dt)
	return math.abs(diff)
end

local function move(g: Golem, distance: number)
	local look = cframe(g).LookVector
	local goal = g.position + flat(look) * distance
	-- não sai da sala
	local limit = ROOM.radius * K - 16
	local offset = flat(goal - g.center)
	if offset.Magnitude > limit then
		goal = g.center + offset.Unit * limit + Vector3.new(0, goal.Y - g.center.Y, 0)
	end
	g.position = goal
end

local function die(g: Golem)
	setState(g, "dead")
	g.attackId += 1
	g.attack = nil
	g.deadAt = now()
	play(g, "Death")
	g.body.CanCollide = false
	g.model:SetAttribute("Defeated", true)
	toRoom(g, "victory")
	-- o sorteio vem depois de ele se desfazer
	task.delay(event("Death", "crumble") + 1.4, function()
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Room") == g.world.id and Boss.onVictory then
				(Boss.onVictory :: any)(player)
			end
		end
	end)
end

local function step(g: Golem, dt: number)
	local t = now()
	if g.state == "sleep" or g.state == "wake" then
		return
	end
	if g.state == "dead" then
		-- volta a dormir um tempo depois, para quem chegar em seguida ter a luta dele
		if t - g.deadAt > 15 then
			reset(g)
		end
		return
	end

	local list = fighters(g)
	if #list == 0 then
		g.emptySince = g.emptySince or t
		if t - (g.emptySince :: number) > BOSS.resetDelay then
			reset(g)
		elseif g.state ~= "attack" and g.clip ~= "Idle" then
			setState(g, "idle")
			play(g, "Idle")
		end
		return
	end
	g.emptySince = nil

	-- alvo: o mais perto
	local target: Vector3 = g.position
	local best = math.huge
	for _, player in list do
		local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
		local d = flat(root.Position - g.position).Magnitude
		if d < best then
			best = d
			target = root.Position
		end
	end
	local dist = best

	if g.state == "attack" then
		local name = g.attack :: string
		local elapsed = t - g.started
		local events = (Anims.clips :: any)[name].events
		local hitAt = events.impact or events.pulse
		-- acompanha o alvo durante a preparação e trava antes do golpe (dá para esquivar)
		if elapsed < hitAt * 0.6 then
			turn(g, target, BOSS.turnSpeed * 0.7, dt)
		end
		-- a corrida ainda leva o corpo para a frente até o gancho
		if name == "Charge" and elapsed < hitAt then
			local speed = BOSS.attacks.Charge.lunge * S * 2 / hitAt * (1 - elapsed / hitAt)
			move(g, speed * dt)
		end
		place(g)
		if elapsed >= length(name) then
			g.attack = nil
			setState(g, "idle")
			play(g, "Idle")
			local rest = if g.rage then BOSS.rageRest else BOSS.rest
			g.restUntil = t + rng:NextNumber(rest[1], rest[2])
		end
		return
	end

	if t < g.restUntil then
		-- cansado: respira e só vira devagar
		turn(g, target, BOSS.turnSpeed * 0.35, dt)
		place(g)
		return
	end

	local off = turn(g, target, BOSS.turnSpeed * (if g.state == "run" then 0.8 else 1), dt)
	if g.state == "run" and dist <= BOSS.chargeRange * S then
		startAttack(g, "Charge")
	elseif dist > BOSS.runRange * S or (g.state == "run" and dist > BOSS.chargeRange * S) then
		if g.state ~= "run" then
			setState(g, "run")
			play(g, "Run")
		end
		if off < math.rad(70) then
			move(g, BOSS.runSpeed * S * dt * (if g.rage then 1.15 else 1))
		end
	elseif dist > BOSS.closeRange * S then
		if g.state ~= "walk" then
			setState(g, "walk")
			play(g, "Walk")
		end
		if off < math.rad(60) then
			move(g, BOSS.walkSpeed * S * dt * (if g.rage then 1.2 else 1))
		end
	elseif off < math.rad(35) then
		startAttack(g, chooseAttack(g))
	elseif g.clip ~= "Idle" then
		setState(g, "idle")
		play(g, "Idle")
	end
	place(g)
end

---------------------------------------------------------------------------------------------------

-- Monta o golem de uma sala (chamado pelo BossRoom depois de montar a sala).
function Boss.build(world: any, folder: Folder, center: Vector3, prompt: ProximityPrompt?)
	local model = Instance.new("Model")
	model.Name = "Boss"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- o cliente sempre sabe onde ele está
	model:SetAttribute("World", world.id)
	model:SetAttribute("Name", BOSS.names[world.id] or BOSS.names[1])
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.one
	root.Parent = model
	-- corpo: segura os jogadores (transparente, então a câmera passa)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = true
	body.CanQuery = false
	body.CanTouch = false
	body.Transparency = 1
	body.Size = Vector3.new(BOSS.radius * 2, 24, BOSS.radius * 2) * S
	body.Parent = model
	model.PrimaryPart = root

	local g: Golem = {
		world = world,
		center = center,
		model = model,
		root = root,
		body = body,
		prompt = prompt,
		state = "sleep",
		clip = "Sleep",
		started = 0,
		position = center,
		yaw = math.pi,
		hp = 1,
		maxHp = 1,
		rage = false,
		attack = nil,
		attackId = 0,
		restUntil = 0,
		lastAttack = nil,
		emptySince = nil,
		deadAt = 0,
	}
	golems[world.id] = g
	reset(g)
	model.Parent = folder
end

-- O visual de cada mundo fica em ReplicatedStorage.BossModels, para os clientes copiarem.
function Boss.loadModels()
	local holder = Instance.new("Folder")
	holder.Name = "BossModels"
	holder.Parent = ReplicatedStorage
	for _, world in Config.Worlds do
		task.spawn(function()
			local model = Models.load("golem", STYLES[world.id] or STYLES[1])
			if not model then
				warn("[Boss] o modelo do golem não carregou")
				return
			end
			if S ~= 1 then
				model:ScaleTo(model:GetScale() * S)
			end
			model:PivotTo(CFrame.identity)
			model.Name = "Golem" .. world.id
			model.Parent = holder
		end)
	end
end

-- Desafio no círculo: acorda o golem. A luta começa quando ele termina de levantar.
function Boss.challenge(player: Player, allowed: boolean): boolean
	local g = golems[player:GetAttribute("Room") :: number]
	if not g or g.state ~= "sleep" or not allowed then
		return false
	end
	local count = math.max(#fighters(g), 1)
	g.maxHp = (BOSS.hp[g.world.id] or BOSS.hp[1]) * count
	g.hp = g.maxHp
	g.model:SetAttribute("Hp", g.hp)
	g.model:SetAttribute("MaxHp", g.maxHp)
	setState(g, "wake")
	play(g, "Wake")
	if g.prompt then
		g.prompt.Enabled = false
	end
	toRoom(g, "intro", g.world.id)
	local started = g.started
	task.delay(length("Wake"), function()
		if g.state == "wake" and g.started == started then
			setState(g, "idle")
			play(g, "Idle")
			g.restUntil = now() + 0.4
		end
	end)
	return true
end

-- Soco do jogador no golem. Devolve o dano (0 se não contou).
function Boss.punch(player: Player, forceCrit: boolean?): number
	local g = golems[player:GetAttribute("Room") :: number]
	if not g or g.state == "sleep" or g.state == "wake" or g.state == "dead" then
		return 0
	end
	local t = os.clock()
	if lastPunch[player] and t - lastPunch[player] < BOSS.hitCooldown then
		return 0
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or flat(root.Position - g.position).Magnitude > BOSS.hitRange * S then
		return 0
	end
	lastPunch[player] = t
	local profile = PlayerData.get(player)
	local chance = Config.Crit.baseChance + (if profile then (profile.stats.critChance or 0) * Config.Stats.critChance.perLevel else 0)
	local crit = if forceCrit ~= nil then forceCrit else rng:NextNumber() < chance
	local damage = if crit then 2 else 1
	g.hp = math.max(g.hp - damage, 0)
	g.model:SetAttribute("Hp", g.hp)
	remote():FireClient(player, "hurt", damage, crit)
	if not g.rage and g.hp <= g.maxHp / 2 then
		g.rage = true
		g.model:SetAttribute("Rage", true)
	end
	if g.hp <= 0 then
		die(g)
	end
	return damage
end

function Boss.start()
	RunService.Heartbeat:Connect(function(dt)
		for _, g in golems do
			step(g, dt)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPunch[player] = nil
	end)
end

-- Para os testes (src/server/tests/golem.luau).
function Boss.debug(worldId: number): { [string]: any }?
	local g = golems[worldId]
	if not g then
		return nil
	end
	return { state = g.state, clip = g.clip, hp = g.hp, maxHp = g.maxHp, rage = g.rage, position = g.position, cframe = cframe(g), attack = g.attack }
end

function Boss.test(worldId: number, action: string, arg: any): any
	local g = golems[worldId]
	if not g then
		return nil
	end
	if action == "attack" then
		startAttack(g, arg)
		return true
	elseif action == "place" then
		g.position = arg.position
		g.yaw = arg.yaw or g.yaw
		g.restUntil = now() + (arg.rest or 0)
		place(g)
		return true
	elseif action == "hp" then
		g.hp = arg
		g.model:SetAttribute("Hp", g.hp)
		if g.hp <= 0 then
			die(g)
		end
		return true
	elseif action == "reset" then
		reset(g)
		return true
	elseif action == "rest" then
		g.restUntil = now() + arg
		if g.state ~= "attack" then
			setState(g, "idle")
			play(g, "Idle")
		end
		return true
	end
	return nil
end

return Boss
