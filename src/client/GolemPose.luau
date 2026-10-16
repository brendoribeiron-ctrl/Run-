--!strict
-- Pose do golem: amostra as animações gravadas pelo Blender (src/shared/GolemAnims.luau) e calcula
-- o deslocamento de cada osso (cinemática direta). Usado pelo golem da sala (Boss.luau) e pelo
-- laboratório de efeitos (lab/).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local Config = require(ReplicatedStorage.Shared.Config)

local S = Config.Boss.scale

local GolemPose = {}

-- Pose: amostra a animação e calcula o deslocamento de cada osso (cinemática direta)

local BONES: { string } = Anims.bones
local PARENTS: { number } = Anims.parents
local HEADS: { Vector3 } = {}
for i = 1, #BONES do
	HEADS[i] = Vector3.new(Anims.heads[i * 3 - 2], Anims.heads[i * 3 - 1], Anims.heads[i * 3]) * S
end
local BONE_INDEX: { [string]: number } = {}
for i, name in BONES do
	BONE_INDEX[name] = i
end

export type Pose = { loc: Vector3, rot: { CFrame } }

local function quat(x: number, y: number, z: number): CFrame
	local w = math.sqrt(math.max(0, 1 - x * x - y * y - z * z))
	return CFrame.new(0, 0, 0, x, y, z, w)
end

local function frame(row: { number }): Pose
	local rot = table.create(#BONES)
	for i = 1, #BONES do
		local k = 3 + (i - 1) * 3
		rot[i] = quat(row[k + 1], row[k + 2], row[k + 3])
	end
	return { loc = Vector3.new(row[1], row[2], row[3]) * S, rot = rot }
end

-- frames decodificados uma vez por animação
local decoded: { [string]: { Pose } } = {}
local function frames(clip: string): { Pose }
	local list = decoded[clip]
	if not list then
		list = {}
		for i, row in (Anims.clips :: any)[clip].frames do
			list[i] = frame(row)
		end
		decoded[clip] = list
	end
	return list
end

local function mix(a: Pose, b: Pose, t: number): Pose
	local rot = table.create(#BONES)
	for i = 1, #BONES do
		rot[i] = a.rot[i]:Lerp(b.rot[i], t)
	end
	return { loc = a.loc:Lerp(b.loc, t), rot = rot }
end

local function sample(clip: string, t: number): Pose
	local data = (Anims.clips :: any)[clip]
	local times: { number } = data.times
	local list = frames(clip)
	if data.loop then
		t = t % data.length
	else
		t = math.clamp(t, 0, data.length)
	end
	local i = math.clamp(math.floor(t * Anims.fps) + 1, 1, #times - 1)
	while i < #times - 1 and times[i + 1] < t do
		i += 1
	end
	local span = times[i + 1] - times[i]
	local u = if span > 0 then math.clamp((t - times[i]) / span, 0, 1) else 0
	return mix(list[i], list[i + 1], u)
end

local function solve(pose: Pose): { CFrame }
	local out = table.create(#BONES)
	for i = 1, #BONES do
		local h = HEADS[i]
		local here = CFrame.new(h) * pose.rot[i] * CFrame.new(-h)
		local parent = PARENTS[i]
		out[i] = (if parent > 0 then out[parent] else CFrame.new(pose.loc)) * here
	end
	return out
end

GolemPose.index = BONE_INDEX
GolemPose.mix = mix
GolemPose.sample = sample
GolemPose.solve = solve

return GolemPose
