--!strict
-- Cliente do laboratório de efeitos: o golem no meio do chão, tocando Idle. O servidor manda
-- tocar um golpe (lab/server/tests/fx.luau) e os efeitos saem nos mesmos eventos da animação
-- que o golem do jogo usa (src/client/Boss.luau), com a câmera fixa num ângulo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local Config = require(ReplicatedStorage.Shared.Config)
local BossFx = require(script.BossFx)
local Fx = require(script.Fx)
local GolemPose = require(script.GolemPose)

local S = Config.Boss.scale
local BONE_INDEX = GolemPose.index
local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

-- o golem fica no centro, de frente para +Z, onde o jogador nasce
local ORIGIN = CFrame.Angles(0, math.pi, 0)

-- ângulos de câmera, no espaço do golem (frente = -Z), em unidades do modelo sem escala
local VIEWS: { [string]: { from: Vector3, to: Vector3 } } = {
	side = { from = Vector3.new(-62, 20, -34), to = Vector3.new(0, 11, -10) },
	front = { from = Vector3.new(0, 14, -62), to = Vector3.new(0, 10, 0) },
	wide = { from = Vector3.new(-70, 36, -70), to = Vector3.new(0, 6, -12) },
	top = { from = Vector3.new(0, 110, -24), to = Vector3.new(0, 0, -14) },
	close = { from = Vector3.new(-24, 10, -28), to = Vector3.new(0, 10, -6) },
}

type Rig = {
	world: number,
	model: Model,
	parts: { BasePart },
	rest: { CFrame },
	bone: { number },
	byBone: { [number]: BasePart },
	clip: string,
	started: number,
	lastT: number,
	pose: GolemPose.Pose?,
	from: GolemPose.Pose?,
	fadeStart: number,
	solved: { CFrame }?,
	crumbled: boolean,
}

local rig: Rig? = nil
local view: string = "free"

local function build(world: number): Rig?
	local folder = ReplicatedStorage:WaitForChild("BossModels", 30)
	local source = folder and folder:WaitForChild("Golem" .. world, 30)
	if not source or not source:IsA("Model") then
		warn("[Lab] o golem do mundo " .. world .. " não carregou")
		return nil
	end
	-- os efeitos 3D também precisam estar carregados
	if folder then
		folder:WaitForChild("Fx", 30)
	end
	local model = source:Clone()
	local r: Rig = {
		world = world,
		model = model,
		parts = {},
		rest = {},
		bone = {},
		byBone = {},
		clip = "Idle",
		started = os.clock(),
		lastT = -1,
		pose = nil,
		from = nil,
		fadeStart = 0,
		solved = nil,
		crumbled = false,
	}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local boneName = string.match(part.Name, "_(%w+)$")
			local index = boneName and BONE_INDEX[boneName]
			if index then
				table.insert(r.parts, part)
				table.insert(r.rest, part.CFrame)
				table.insert(r.bone, index)
				r.byBone[index] = r.byBone[index] or part
			end
		end
	end
	model.Parent = workspace
	return r
end

local function ctxOf(r: Rig): BossFx.Ctx
	local colors = BossFx.PALETTE[r.world] or BossFx.PALETTE[1]
	return {
		cf = ORIGIN,
		point = function(boneName: string, rest: Vector3): Vector3
			local i = BONE_INDEX[boneName]
			local solved = r.solved
			if not solved or not i then
				return (ORIGIN * CFrame.new(rest)).Position
			end
			return (ORIGIN * solved[i] * CFrame.new(rest)).Position
		end,
		part = function(boneName: string): BasePart?
			return r.byBone[BONE_INDEX[boneName] or 0]
		end,
		glow = colors.glow,
		magic = colors.magic,
		rock = colors.rock,
		scale = S,
		near = 1,
	}
end

local function setClip(r: Rig, clip: string, effects: boolean)
	r.from = r.pose
	r.fadeStart = os.clock()
	r.clip = clip
	r.started = os.clock()
	r.lastT = -1
	if effects then
		BossFx.start(clip, ctxOf(r), function()
			return ctxOf(r)
		end)
	end
end

local function crumble(r: Rig)
	r.crumbled = true
	BossFx.death(ctxOf(r))
	for _, part in r.parts do
		part.Anchored = false
		part.CanCollide = true
		local out = Vector3.new(part.Position.X, 0, part.Position.Z)
		part.AssemblyLinearVelocity = (if out.Magnitude > 0.1 then out.Unit else Vector3.xAxis) * math.random(6, 18) + Vector3.new(0, math.random(4, 16), 0)
		part.AssemblyAngularVelocity = Vector3.new(math.random(-4, 4), math.random(-4, 4), math.random(-4, 4))
	end
	-- golem inteiro de novo depois de um tempo
	task.delay(3.5, function()
		if rig == r then
			r.model:Destroy()
			local fresh = build(r.world)
			rig = fresh
		end
	end)
end

local function update(dt: number)
	local r = rig
	if not r or r.crumbled then
		return
	end
	local data = (Anims.clips :: any)[r.clip]
	local t = os.clock() - r.started
	if not data.loop and t > data.length + 0.4 and r.clip ~= "Death" then
		setClip(r, "Idle", false)
		data = (Anims.clips :: any).Idle
		t = 0
	end
	if r.clip == "Death" and t > data.events.crumble then
		crumble(r)
		return
	end

	local pose = GolemPose.sample(r.clip, t)
	local fade = math.clamp((os.clock() - r.fadeStart) / 0.2, 0, 1)
	if r.from and fade < 1 then
		pose = GolemPose.mix(r.from :: GolemPose.Pose, pose, fade * fade * (3 - 2 * fade))
	end
	r.pose = pose
	local solved = GolemPose.solve(pose)
	r.solved = solved
	local cframes = table.create(#r.parts)
	for i in r.parts do
		cframes[i] = ORIGIN * solved[r.bone[i]] * r.rest[i]
	end
	workspace:BulkMoveTo(r.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- eventos da animação que passaram neste quadro (como no jogo)
	local looped = data.loop and r.lastT >= 0 and (t % data.length) < (r.lastT % data.length)
	local previous = if data.loop then (if looped then -1 else r.lastT % data.length) else r.lastT
	local now = if data.loop then t % data.length else t
	for name, at in data.events do
		if previous < at and at <= now then
			BossFx.event(r.clip, name, ctxOf(r))
		end
	end
	r.lastT = t
end

local function updateCamera()
	local preset = VIEWS[view]
	if not preset then
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt((ORIGIN * CFrame.new(preset.from * S)).Position, (ORIGIN * CFrame.new(preset.to * S)).Position) * Fx.shakeCFrame()
end

RunService.RenderStepped:Connect(function(dt)
	update(dt)
	updateCamera()
end)

local remote = ReplicatedStorage:WaitForChild("Lab") :: RemoteEvent
remote.OnClientEvent:Connect(function(action: string, clip: string?, world: number?, newView: string?)
	if action == "toast" and clip then
		Fx.toast(clip)
		return
	end
	if action ~= "play" or not clip then
		return
	end
	view = newView or view
	local wanted = world or 1
	if not rig or rig.world ~= wanted or rig.crumbled then
		if rig then
			rig.model:Destroy()
		end
		rig = build(wanted)
	end
	if rig then
		setClip(rig, clip, true)
		remote:FireServer("played", clip) -- confirmação para os testes
	end
end)

rig = build(1)
player:SetAttribute("LabReady", rig ~= nil)
