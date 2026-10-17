-- Animação de parado ("descansando") do boneco R15, gerada por código e salva como
-- KeyframeSequence no AnimSaves do boneco de trabalho (Workspace.AnimRigs.RestRig): o Eclipse
-- Animator abre dali para ajustar à mão. Rodado no modo de edição (MCP execute_luau ou a ponte).
--
-- Laço de 4 s: duas respirações (inspira em 1 s e 3 s), o peso passa de uma perna para a outra
-- (direita em 0 s, esquerda em 2 s), a cabeça olha em volta devagar, os braços soltos acompanham.
-- Pés parados no chão: o quadril compensa a inclinação e o deslocamento da bacia.
--
-- Eixos das juntas (todas iguais neste rig): tronco/cabeça +X inclina para trás, +Z para a
-- esquerda, +Y gira para a esquerda; braço/perna +X vai para a frente, +Z para a direita.
--
-- Atributo Preview da pasta AnimRigs = segundos: em vez de gravar, põe o boneco (ancorado) na
-- pose daquele instante, para foto; -1 volta à pose de descanso; sem atributo, grava.
--   node tools/bridge.cjs run edit tools/anim/rest_idle.luau

local PREVIEW: number? = workspace:WaitForChild("AnimRigs"):GetAttribute("Preview")

local LENGTH = 4
local TIMES = { 0, 1, 2, 3, 4 }

-- [junta] = { parte animada, { {x, y, z} graus por tempo }, { posição por tempo }? }
local KEYS: { [string]: any } = {
	-- bacia: peso na perna direita (quadril sai para a direita) e depois na esquerda; desce ao
	-- soltar o ar
	LowerTorso = {
		rot = { { 0, 5, 4 }, { 0, 0, 0 }, { 0, -5, -4 }, { 0, 0, 0 }, { 0, 5, 4 } },
		pos = { { 0.14, -0.04, 0 }, { 0, 0, 0 }, { -0.14, -0.04, 0 }, { 0, 0, 0 }, { 0.14, -0.04, 0 } },
	},
	-- peito: cansado, curvado para a frente; solta o ar caindo mais, inspira subindo; equilibra
	-- a bacia para a cabeça ficar sobre os pés
	UpperTorso = { rot = { { -9, -3, -5 }, { -2, 0, 0 }, { -9, 3, 5 }, { -2, 0, 0 }, { -9, -3, -5 } } },
	-- cabeça: pende um pouco, olha para os lados devagar
	Head = { rot = { { -6, 14, -4 }, { 2, 4, 0 }, { -6, -16, 4 }, { 2, -5, 0 }, { -6, 14, -4 } } },
	-- braços pendurados, um pouco à frente; os ombros sobem ao inspirar (abrem) e os braços
	-- balançam atrasados em relação ao peso
	RightUpperArm = { rot = { { 8, 0, 5 }, { 4, 0, 9 }, { 5, 0, 3 }, { 4, 0, 9 }, { 8, 0, 5 } } },
	LeftUpperArm = { rot = { { 5, 0, -3 }, { 4, 0, -9 }, { 8, 0, -5 }, { 4, 0, -9 }, { 5, 0, -3 } } },
	RightLowerArm = { rot = { { 18, 0, 0 }, { 14, 0, 0 }, { 16, 0, 0 }, { 14, 0, 0 }, { 18, 0, 0 } } },
	LeftLowerArm = { rot = { { 16, 0, 0 }, { 14, 0, 0 }, { 18, 0, 0 }, { 14, 0, 0 }, { 16, 0, 0 } } },
	RightHand = { rot = { { 8, 0, 0 }, { 5, 0, 0 }, { 8, 0, 0 }, { 5, 0, 0 }, { 8, 0, 0 } } },
	LeftHand = { rot = { { 8, 0, 0 }, { 5, 0, 0 }, { 8, 0, 0 }, { 5, 0, 0 }, { 8, 0, 0 } } },
	-- pernas: o ponto de partida; quadril e joelho são recalculados para os pés ficarem presos
	-- (solveLegs). Y é o giro que acompanha a bacia.
	RightUpperLeg = { rot = { { 0, -5, 0 }, { 0, 0, 0 }, { 0, 5, 0 }, { 0, 0, 0 }, { 0, -5, 0 } } },
	LeftUpperLeg = { rot = { { 0, -5, 0 }, { 0, 0, 0 }, { 0, 5, 0 }, { 0, 0, 0 }, { 0, -5, 0 } } },
	RightLowerLeg = { rot = { { -4, 0, 0 }, { -2, 0, 0 }, { -4, 0, 0 }, { -2, 0, 0 }, { -4, 0, 0 } } },
	LeftLowerLeg = { rot = { { -4, 0, 0 }, { -2, 0, 0 }, { -4, 0, 0 }, { -2, 0, 0 }, { -4, 0, 0 } } },
	RightFoot = { rot = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } } },
	LeftFoot = { rot = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } } },
}

-- árvore das poses do R15 (pai -> filhos)
local TREE: { [string]: { string } } = {
	HumanoidRootPart = { "LowerTorso" },
	LowerTorso = { "UpperTorso", "LeftUpperLeg", "RightUpperLeg" },
	UpperTorso = { "Head", "LeftUpperArm", "RightUpperArm" },
	LeftUpperArm = { "LeftLowerArm" },
	LeftLowerArm = { "LeftHand" },
	RightUpperArm = { "RightLowerArm" },
	RightLowerArm = { "RightHand" },
	LeftUpperLeg = { "LeftLowerLeg" },
	LeftLowerLeg = { "LeftFoot" },
	RightUpperLeg = { "RightLowerLeg" },
	RightLowerLeg = { "RightFoot" },
}

local rig = workspace:WaitForChild("AnimRigs"):WaitForChild("RestRig") :: Model

local joints: { [string]: AnimationConstraint } = {}
for _, d in rig:GetDescendants() do
	if d:IsA("AnimationConstraint") and d.Attachment1 then
		joints[d.Attachment1.Parent.Name] = d
	end
end

-- pernas calculadas (pés presos no chão), por tempo: [índice][parte] = transformação
local solved: { { [string]: CFrame } } = {}

local function transform(part: string, index: number): CFrame
	local fixed = solved[index] and solved[index][part]
	if fixed then
		return fixed
	end
	local key = KEYS[part]
	if not key then
		return CFrame.identity
	end
	local r = key.rot[index]
	local p = if key.pos then key.pos[index] else { 0, 0, 0 }
	return CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
end

-- peça filha a partir da peça pai, com a transformação da junta (espaço do HumanoidRootPart)
local function child(parentCf: CFrame, name: string, t: CFrame): CFrame
	local joint = joints[name]
	return parentCf * joint.Attachment0.CFrame * t * joint.Attachment1.CFrame:Inverse()
end

-- Pés presos: para cada tempo, acha quadril (frente/lado) e joelho que levam o pé de volta ao
-- lugar de descanso e gira o tornozelo para o pé ficar com o mesmo ângulo de descanso.
local function solveLegs()
	local pelvisRest = child(CFrame.identity, "LowerTorso", CFrame.identity)
	for index in TIMES do
		solved[index] = {}
		local pelvis = child(CFrame.identity, "LowerTorso", transform("LowerTorso", index))
		for _, side in { "Left", "Right" } do
			local upperName, lowerName, footName = side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"
			local upperRest = child(pelvisRest, upperName, CFrame.identity)
			local lowerRest = child(upperRest, lowerName, CFrame.identity)
			local footRest = child(lowerRest, footName, CFrame.identity)
			local key = KEYS[upperName].rot[index]
			local yaw = math.rad(key[2])
			local params = { math.rad(key[1]), math.rad(key[3]), math.rad(KEYS[lowerName].rot[index][1]) }
			local function legs(p: { number }): (CFrame, CFrame, CFrame)
				local upper = child(pelvis, upperName, CFrame.Angles(p[1], yaw, p[2]))
				local lower = child(upper, lowerName, CFrame.Angles(p[3], 0, 0))
				return upper, lower, child(lower, footName, CFrame.identity)
			end
			local function err(p: { number }): number
				local _, _, foot = legs(p)
				return (foot.Position - footRest.Position).Magnitude
			end
			-- descida por coordenadas: passos que encolhem
			local step = math.rad(4)
			for _ = 1, 400 do
				local improved = false
				for k = 1, 3 do
					for _, dir in { 1, -1 } do
						local trial = table.clone(params)
						trial[k] += dir * step
						if k == 3 and trial[3] > 0 then
							continue -- joelho só dobra para trás
						end
						if err(trial) < err(params) then
							params = trial
							improved = true
						end
					end
				end
				if not improved then
					step *= 0.5
					if step < math.rad(0.01) then
						break
					end
				end
			end
			local _, lower = legs(params)
			local joint = joints[footName]
			solved[index][upperName] = CFrame.Angles(params[1], yaw, params[2])
			solved[index][lowerName] = CFrame.Angles(params[3], 0, 0)
			solved[index][footName] = (lower * joint.Attachment0.CFrame):Inverse() * footRest * joint.Attachment1.CFrame
		end
	end
end
solveLegs()

-- transformação de um instante qualquer (entre dois tempos, suavizado como o Cubic InOut)
local function transformAt(part: string, t: number): CFrame
	t = t % LENGTH
	local i = math.clamp(math.floor(t) + 1, 1, #TIMES - 1)
	local u = (t - TIMES[i]) / (TIMES[i + 1] - TIMES[i])
	u = if u < 0.5 then 4 * u * u * u else 1 - (-2 * u + 2) ^ 3 / 2
	return transform(part, i):Lerp(transform(part, i + 1), u)
end

if PREVIEW then
	-- cinemática direta à mão (no modo de edição as juntas não movem as peças)
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local function place(name: string, parentCf: CFrame)
		for _, child in TREE[name] or {} do
			local joint = joints[child]
			local part = joint.Attachment1.Parent :: BasePart
			local t = if PREVIEW >= 0 then transformAt(child, PREVIEW) else CFrame.identity
			local cf = parentCf * joint.Attachment0.CFrame * t * joint.Attachment1.CFrame:Inverse()
			part.Anchored = true
			part.CFrame = cf
			place(child, cf)
		end
	end
	place("HumanoidRootPart", root.CFrame)
	local feet = {}
	for _, side in { "LeftFoot", "RightFoot" } do
		local foot = rig:FindFirstChild(side) :: BasePart
		local rel = root.CFrame:ToObjectSpace(foot.CFrame).Position
		table.insert(feet, string.format("%s(%.2f, %.2f, %.2f)", side, rel.X, rel.Y, rel.Z))
	end
	return "pose em " .. tostring(PREVIEW) .. "s: " .. table.concat(feet, " ")
end

-- grava o KeyframeSequence
local saves = rig:FindFirstChild("AnimSaves") or Instance.new("Folder")
saves.Name = "AnimSaves"
saves.Parent = rig
local old = saves:FindFirstChild("RestIdle")
if old then
	old:Destroy()
end
local sequence = Instance.new("KeyframeSequence")
sequence.Name = "RestIdle"
sequence.Loop = true
sequence.Priority = Enum.AnimationPriority.Idle
for index, time in TIMES do
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = time
	local function add(name: string, parent: Instance)
		local pose = Instance.new("Pose")
		pose.Name = name
		pose.CFrame = transform(name, index)
		pose.EasingStyle = Enum.PoseEasingStyle.Cubic
		pose.EasingDirection = Enum.PoseEasingDirection.InOut
		pose.Weight = if KEYS[name] then 1 else 0
		pose.Parent = parent
		for _, child in TREE[name] or {} do
			add(child, pose)
		end
	end
	add("HumanoidRootPart", keyframe)
	keyframe.Parent = sequence
end
sequence.Parent = saves
return "RestIdle gravado: " .. #sequence:GetKeyframes() .. " keyframes, " .. LENGTH .. " s em laço"
