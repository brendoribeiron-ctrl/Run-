--!strict
-- O golem da sala do chefe, no cliente (servidor em src/server/Boss.luau).
--
-- Cada cliente tem a sua cópia do golem (ReplicatedStorage.BossModels) e move as peças a cada
-- quadro com as rotações gravadas pelo Blender (src/shared/GolemAnims.luau): o servidor só diz
-- onde ele está (Boss.Root), qual animação toca e desde quando. Os efeitos de cada golpe saem
-- nos eventos da animação (src/client/BossFx.luau), no mesmo instante do dano no servidor.
--
-- Aqui também: a barra de vida do chefe, a cena do despertar, o soco no golem (pelo Bag) e o que
-- acontece quando um golpe acerta o jogador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local Config = require(ReplicatedStorage.Shared.Config)
require(ReplicatedStorage.Shared.GolemExperiment) -- EXPERIMENTO: põe o clip SlamV2 em GolemAnims (Config.Boss.slamV2)
local Bag = require(script.Parent.Bag)
local BossFx = require(script.Parent.BossFx)
local BossRoom = require(script.Parent.BossRoom)
local Fx = require(script.Parent.Fx)
local GolemPose = require(script.Parent.GolemPose)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local BOSS = Config.Boss
local S = BOSS.scale
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local WHITE = Color3.new(1, 1, 1)

-- cor das fissuras, da magia e da pedra de cada mundo
local PALETTE = BossFx.PALETTE
local GLOW = { PALETTE[1].glow, PALETTE[2].glow }
local MAGIC = { PALETTE[1].magic, PALETTE[2].magic }
local ROCK = { PALETTE[1].rock, PALETTE[2].rock }

local Boss = {}

local BONE_INDEX = GolemPose.index
type Pose = GolemPose.Pose
local mix, sample, solve = GolemPose.mix, GolemPose.sample, GolemPose.solve

---------------------------------------------------------------------------------------------------
-- Um golem na tela

type Rig = {
	world: number,
	server: Model,
	model: Model?,
	parts: { BasePart },
	rest: { CFrame },
	bone: { number },
	byBone: { [number]: BasePart },
	glow: { { part: BasePart, color: Color3, eye: boolean } },
	cf: CFrame?,
	clip: string,
	started: number,
	lastT: number,
	pose: Pose?,
	from: Pose?,
	fadeStart: number,
	solved: { CFrame }?,
	crumbled: boolean,
	lit: number,
	highlight: Highlight?,
	stepAt: number,
}

-- um por sala (pelo nome dela); só o da sala do jogador anima e aparece
local rigs: { [string]: Rig } = {}

local function myRig(): Rig?
	local key = player:GetAttribute("RoomKey")
	return if type(key) == "string" then rigs[key] else nil
end

local function serverTime(): number
	return workspace:GetServerTimeNow()
end

local function build(rig: Rig): boolean
	local folder = ReplicatedStorage:FindFirstChild("BossModels")
	local source = folder and folder:FindFirstChild("Golem" .. rig.world)
	if not source or not source:IsA("Model") then
		return false
	end
	if rig.model then
		rig.model:Destroy()
	end
	local model = source:Clone()
	model.Name = "Golem" .. rig.world
	rig.parts, rig.rest, rig.bone, rig.byBone, rig.glow = {}, {}, {}, {}, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local boneName = string.match(part.Name, "_(%w+)$")
			local index = boneName and BONE_INDEX[boneName]
			if index then
				table.insert(rig.parts, part)
				table.insert(rig.rest, part.CFrame)
				table.insert(rig.bone, index)
				rig.byBone[index] = rig.byBone[index] or part
				local kind = string.match(part.Name, "^(%a+)_")
				if kind == "Magma" or kind == "Ember" then
					table.insert(rig.glow, { part = part, color = part.Color, eye = kind == "Ember" and boneName == "Head" })
				end
			end
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	rig.highlight = highlight
	model.Parent = nil -- update() põe no mundo quando a câmera está perto da sala
	rig.model = model
	rig.crumbled = false
	rig.lit = -1
	return true
end

local function rootCFrame(rig: Rig): CFrame?
	local root = rig.server:FindFirstChild("Root")
	return if root and root:IsA("BasePart") then root.CFrame else nil
end

-- Ponto do modelo em repouso (coordenadas do Roblox, com a escala) -> mundo, na pose atual.
local function pointOf(rig: Rig, boneName: string, rest: Vector3): Vector3
	local cf = rig.cf or CFrame.identity
	local solved = rig.solved
	local i = BONE_INDEX[boneName]
	if not solved or not i then
		return (cf * CFrame.new(rest)).Position
	end
	return (cf * solved[i] * CFrame.new(rest)).Position
end

local function ctxOf(rig: Rig): BossFx.Ctx
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local d = if root and root:IsA("BasePart") and rig.cf then (root.Position - rig.cf.Position).Magnitude else 0
	return {
		cf = rig.cf or CFrame.identity,
		point = function(boneName: string, rest: Vector3): Vector3
			return pointOf(rig, boneName, rest)
		end,
		part = function(boneName: string): BasePart?
			return rig.byBone[BONE_INDEX[boneName] or 0]
		end,
		glow = GLOW[rig.world] or GLOW[1],
		magic = MAGIC[rig.world] or MAGIC[1],
		rock = ROCK[rig.world] or ROCK[1],
		scale = S,
		near = math.clamp(1 - d / 160, 0.25, 1),
	}
end

-- Brilho das fissuras: apagado dormindo, aceso lutando, mais forte com raiva.
local function setGlow(rig: Rig, level: number)
	if rig.lit == level then
		return
	end
	rig.lit = level
	for _, g in rig.glow do
		local dim = if level == 0 then (if g.eye then 0.92 else 0.7) elseif level == 1 then 0 else -0.35
		local color = if dim >= 0 then g.color:Lerp(Color3.new(0, 0, 0), dim) else g.color:Lerp(WHITE, -dim)
		TweenService:Create(g.part, TweenInfo.new(0.4), { Color = color }):Play()
	end
end

local function crumble(rig: Rig)
	if rig.crumbled or not rig.model then
		return
	end
	rig.crumbled = true
	BossFx.death(ctxOf(rig))
	local center = if rig.cf then rig.cf.Position else Vector3.zero
	for _, part in rig.parts do
		part.Anchored = false
		part.CanCollide = true
		local out = part.Position - center
		out = Vector3.new(out.X, 0, out.Z)
		part.AssemblyLinearVelocity = (if out.Magnitude > 0.1 then out.Unit else Vector3.xAxis) * math.random(6, 18) + Vector3.new(0, math.random(4, 16), 0)
		part.AssemblyAngularVelocity = Vector3.new(math.random(-4, 4), math.random(-4, 4), math.random(-4, 4))
		TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2.6), { Transparency = 1 }):Play()
	end
	setGlow(rig, 0)
	Fx.shake(0.6)
end

local function update(rig: Rig, dt: number)
	local server = rig.server
	if not rig.model then
		if not build(rig) then
			return
		end
	end
	local model = rig.model :: Model
	local target = rootCFrame(rig)
	if not target then
		return
	end
	local clip = server:GetAttribute("Clip") :: string? or "Sleep"
	local started = server:GetAttribute("ClipStart") :: number? or 0
	local defeated = server:GetAttribute("Defeated") == true

	-- longe da sala não vale animar; e o modelo sai do mundo (a cópia nasce na origem, que é o
	-- meio do mapa, e sem animar ninguém move ela de lá)
	if (camera.CFrame.Position - target.Position).Magnitude > 700 then
		rig.cf = target
		model.Parent = nil
		return
	end
	if not defeated and rig.crumbled then
		build(rig) -- voltou a dormir: golem inteiro de novo
	end
	if rig.crumbled then
		return
	end
	if rig.model and not rig.model.Parent then
		rig.model.Parent = workspace
	end

	-- raiz: segue a do servidor suavizando (ela chega 20 vezes por segundo)
	if not rig.cf or (rig.cf.Position - target.Position).Magnitude > 30 then
		rig.cf = target
	else
		rig.cf = (rig.cf :: CFrame):Lerp(target, 1 - math.exp(-dt * 14))
	end

	local data = (Anims.clips :: any)[clip]
	if not data then
		return
	end
	local t = serverTime() - started
	local fresh = clip ~= rig.clip or started ~= rig.started
	if fresh then
		-- troca de animação: cruza a partir da pose em que estava
		rig.from = rig.pose
		rig.fadeStart = os.clock()
		rig.clip = clip
		rig.started = started
		rig.lastT = if t > 0.3 then t else -1 -- chegou no meio (entrou na sala depois): sem efeitos atrasados
		if t < 0.3 then
			BossFx.start(clip, ctxOf(rig), function()
				return ctxOf(rig)
			end)
		end
	end
	if clip == "Death" and t > data.events.crumble then
		if rig.lastT < data.events.crumble and rig.lastT >= 0 then
			crumble(rig)
		else
			-- já tinha se desfeito antes deste cliente chegar
			rig.crumbled = true
			rig.model.Parent = nil
		end
		return
	end

	local pose = sample(clip, t)
	local fade = math.clamp((os.clock() - rig.fadeStart) / 0.2, 0, 1)
	if rig.from and fade < 1 then
		pose = mix(rig.from :: Pose, pose, fade * fade * (3 - 2 * fade))
	end
	rig.pose = pose
	local solved = solve(pose)
	rig.solved = solved

	local cf = rig.cf :: CFrame
	local cframes = table.create(#rig.parts)
	for i, part in rig.parts do
		cframes[i] = cf * solved[rig.bone[i]] * rig.rest[i]
	end
	workspace:BulkMoveTo(rig.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- eventos da animação que passaram neste quadro
	local looped = data.loop and rig.lastT >= 0 and (t % data.length) < (rig.lastT % data.length)
	local previous = if data.loop then (if looped then -1 else rig.lastT % data.length) else rig.lastT
	local now = if data.loop then t % data.length else t
	for name, at in data.events do
		if previous < at and at <= now then
			BossFx.event(clip, name, ctxOf(rig))
		end
	end
	-- passos da corrida e da caminhada
	if clip == "Run" or clip == "Walk" then
		local period = data.length / 2
		local before = math.floor(math.max(rig.lastT, 0) / period)
		if math.floor(t / period) > before and rig.lastT >= 0 then
			local side = if math.floor(t / period) % 2 == 0 then "FootR" else "FootL"
			BossFx.footstep(ctxOf(rig), pointOf(rig, side, Vector3.new(if side == "FootR" then 3.6 else -3.6, 0, -1) * S), clip == "Run")
		end
	end
	rig.lastT = t

	local state = server:GetAttribute("State")
	setGlow(rig, if clip == "Sleep" or (clip == "Wake" and t < data.events.eyes) then 0 elseif server:GetAttribute("Rage") == true then 2 else 1)
	if state == "dead" then
		setGlow(rig, 0)
	end
end

---------------------------------------------------------------------------------------------------
-- Barra de vida do chefe (no alto da tela, como em Sekiro)

local bar: Frame? = nil
local fill: Frame? = nil
local chip: Frame? = nil
local title: TextLabel? = nil
local shownHp = -1

local function makeBar()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BossBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = player:WaitForChild("PlayerGui")
	local holder = Ui.frame(gui, "Holder", UDim2.new(0.5, 0, 0, 62), UDim2.new(0.5, 0, 0, 74), nil, Vector2.new(0.5, 0))
	holder.Visible = false
	local name = Ui.text(holder, { name = "Name", text = "", size = UDim2.new(1, 0, 0, 26), textSize = 24, stroke = 3 })
	local back = Ui.frame(holder, "Back", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 32), Color3.fromRGB(20, 14, 18))
	Ui.corner(back, 4)
	Ui.border(back, 2, Color3.fromRGB(10, 6, 8))
	local c = Ui.frame(back, "Chip", UDim2.fromScale(1, 1), nil, Color3.fromRGB(255, 240, 210))
	Ui.corner(c, 4)
	local f = Ui.frame(back, "Fill", UDim2.fromScale(1, 1), nil, Color3.fromRGB(200, 30, 30))
	Ui.corner(f, 4)
	Ui.gradient(f, Color3.fromRGB(255, 90, 70), Color3.fromRGB(150, 10, 20))
	bar, fill, chip, title = holder, f, c, name
end

local function updateBar()
	local rig = myRig()
	local holder = bar
	if not holder or not fill or not chip or not title then
		return
	end
	local state = rig and rig.server:GetAttribute("State")
	local visible = rig ~= nil and state ~= nil and state ~= "sleep" and state ~= "wake" and not (state == "dead" and rig.crumbled)
	holder.Visible = visible
	if not visible or not rig then
		shownHp = -1
		return
	end
	local hp = rig.server:GetAttribute("Hp") :: number? or 0
	local maxHp = math.max(rig.server:GetAttribute("MaxHp") :: number? or 1, 1)
	title.Text = rig.server:GetAttribute("Name") :: string? or "BOSS"
	title.TextColor3 = if rig.server:GetAttribute("Rage") == true then Color3.fromRGB(255, 150, 120) else WHITE
	if hp ~= shownHp then
		if shownHp >= 0 and hp < shownHp and rig.highlight then
			-- golpe no golem: pisca branco
			local h = rig.highlight :: Highlight
			h.FillTransparency = 0.55
			TweenService:Create(h, TweenInfo.new(0.12), { FillTransparency = 1 }):Play()
		end
		shownHp = hp
		local size = UDim2.fromScale(hp / maxHp, 1)
		fill.Size = size
		TweenService:Create(chip, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), { Size = size }):Play()
	end
end

---------------------------------------------------------------------------------------------------
-- Cena do despertar: câmera baixa no rosto, ele levanta, ruge, nome do chefe

local function intro(key: string)
	local rig = rigs[key]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not rig or not root or not root:IsA("BasePart") then
		return
	end
	local total = (Anims.clips :: any).Wake.length
	root.Anchored = true
	local hud = Hud.gui()
	hud.Enabled = false
	BossRoom.letterbox(true, 0.4)
	camera.CameraType = Enum.CameraType.Scriptable
	local began = os.clock()
	local titled = false
	while true do
		local t = os.clock() - began
		if t >= total or not rig.cf then
			break
		end
		local cf = rig.cf :: CFrame
		local head = pointOf(rig, "Head", Vector3.new(0, 25, -4) * S)
		local eye: Vector3
		local look: Vector3
		if t < 1.9 then
			-- baixo, de frente, longe dos punhos apoiados no chão, olhando o rosto que se levanta
			local u = t / 1.9
			eye = (cf * CFrame.new(-14 * S + 5 * u, 9 * S - 2 * u, -40 * S + 6 * u)).Position
			look = head
			camera.FieldOfView = 50 - 6 * u
		elseif t < 3.4 then
			-- de lado, mais aberto, enquanto ele fica de pé
			local u = (t - 1.9) / 1.5
			local angle = math.rad(-60 + 30 * u)
			eye = (cf * CFrame.Angles(0, angle, 0) * CFrame.new(0, 10 * S, -46 * S)).Position
			look = cf.Position + Vector3.new(0, 15 * S, 0)
			camera.FieldOfView = 55
		else
			-- rugido: de baixo, perto, o nome entra
			local u = math.clamp((t - 3.4) / (total - 3.4), 0, 1)
			eye = (cf * CFrame.new(5 * S, 3 * S, -(30 + 10 * u) * S)).Position
			look = head + Vector3.new(0, 2, 0)
			camera.FieldOfView = 62 + 8 * u
			if not titled and t > 3.6 then
				titled = true
				Fx.title(rig.server:GetAttribute("Name") :: string? or "BOSS", GLOW[rig.world] or GLOW[1], 1.4)
				Fx.flash(GLOW[rig.world] or GLOW[1], 0.35, 0.4)
			end
		end
		camera.CFrame = CFrame.lookAt(eye, look) * Fx.shakeCFrame()
		RunService.RenderStepped:Wait()
	end
	BossRoom.letterbox(false, 0.4)
	hud.Enabled = true
	root.Anchored = false
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end

---------------------------------------------------------------------------------------------------
-- Golpe do golem no jogador e o soco do jogador no golem

local function onHit(damage: number, dir: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	Fx.flash(Color3.fromRGB(255, 40, 30), 0.45, 0.35)
	Fx.shake(0.9)
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		-- arremessado para longe do golpe
		root.AssemblyLinearVelocity = dir * BOSS.knockback + Vector3.new(0, 32, 0)
		humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		task.delay(0.7, function()
			if humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
	Fx.toast(`-{damage}`, Color3.fromRGB(255, 80, 70))
end

local function fightable(rig: Rig): boolean
	local state = rig.server:GetAttribute("State")
	return state == "idle" or state == "walk" or state == "run" or state == "attack"
end

-- Centro do golem para o soco, se o jogador estiver perto o bastante dele.
local function punchTarget(): Vector3?
	local rig = myRig()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not rig or not rig.cf or not fightable(rig) or not root or not root:IsA("BasePart") then
		return nil
	end
	local center = (rig.cf :: CFrame).Position
	local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	if flat.Magnitude > BOSS.hitRange * S - 1.5 then
		return nil
	end
	return center + Vector3.new(0, 10 * S, 0)
end

function Boss.start()
	makeBar()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local bossRemote = remotes:WaitForChild("Boss") :: RemoteEvent
	local bossHit = remotes:WaitForChild("BossHit") :: RemoteEvent

	local function watch(folder: Instance)
		if not folder:IsA("Folder") or not string.match(folder.Name, "^BossRoom%d+_?%d*$") then
			return
		end
		task.spawn(function()
			local server = folder:WaitForChild("Boss", 60)
			local world = folder:GetAttribute("World")
			if server and server:IsA("Model") and type(world) == "number" then
				rigs[folder.Name] = {
					world = world,
					server = server,
					model = nil,
					parts = {},
					rest = {},
					bone = {},
					byBone = {},
					glow = {},
					cf = nil,
					clip = "",
					started = -1,
					lastT = -1,
					pose = nil,
					from = nil,
					fadeStart = 0,
					solved = nil,
					crumbled = false,
					lit = -1,
					highlight = nil,
					stepAt = 0,
				}
			end
		end)
	end
	for _, child in workspace:GetChildren() do
		watch(child)
	end
	workspace.ChildAdded:Connect(watch)

	RunService.RenderStepped:Connect(function(dt)
		local mine = myRig()
		for _, rig in rigs do
			if rig == mine then
				update(rig, dt)
			elseif rig.model and rig.model.Parent then
				rig.model.Parent = nil
			end
		end
		updateBar()
	end)

	bossRemote.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "intro" then
			task.spawn(intro, a)
		elseif kind == "hit" then
			onHit(a, b)
		elseif kind == "hurt" then
			local rig = myRig()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if rig and rig.cf and root and root:IsA("BasePart") then
				local center = (rig.cf :: CFrame).Position + Vector3.new(0, 10 * S, 0)
				local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
				BossFx.struck(center + dir * BOSS.radius * S + Vector3.new(0, -2, 0), dir, b == true, GLOW[rig.world] or GLOW[1])
				Fx.shake(if b then 0.35 else 0.1)
			end
		elseif kind == "victory" then
			task.delay(2.6, Fx.title, "VICTORY", Color3.fromRGB(255, 214, 40), 1.6)
		elseif kind == "defeat" then
			Fx.title("DEFEATED", Color3.fromRGB(255, 60, 50), 2)
		end
	end)

	-- o soco do jogador também serve para o golem (Bag cuida da animação e do botão)
	Bag.target = punchTarget
	Bag.onTarget = function()
		bossHit:FireServer()
	end
end

function Boss.debug(): { [string]: any }
	local rig = myRig() or rigs.BossRoom1
	if not rig then
		return { built = false }
	end
	return {
		built = rig.model ~= nil and rig.model.Parent ~= nil,
		parts = #rig.parts,
		clip = rig.clip,
		crumbled = rig.crumbled,
		position = rig.cf and rig.cf.Position,
		bar = bar ~= nil and bar.Visible,
		target = punchTarget() ~= nil,
		head = rig.solved and pointOf(rig, "Head", Vector3.new(0, 25.4, -2.8) * S),
		handR = rig.solved and pointOf(rig, "HandR", Vector3.new(10, 2, -1.5) * S),
		footR = rig.solved and pointOf(rig, "FootR", Vector3.new(3.6, 0, -1.5) * S),
	}
end

return Boss
