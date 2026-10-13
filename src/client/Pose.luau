--!strict
-- Poses procedurais por cima das animações padrão (R15). Cada camada tem um peso suavizado;
-- no Stepped (depois do Animator) a pose animada é misturada com a da camada.
-- "override" troca a junta pela pose; "additive" soma a rotação (inclinação ao correr).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Pose = {}

type Layer = {
	joints: { [string]: CFrame },
	additive: boolean,
	weight: number,
	target: number,
	speed: number,
	order: number,
}

local layers: { [string]: Layer } = {}
local ordered: { Layer } = {}
-- juntas do avatar: Motor6D nos rigs antigos, AnimationConstraint nos novos; os dois têm Transform
local motors: { [string]: any } = {}

local function rad(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end
Pose.deg = rad

local function collect(character: Model)
	table.clear(motors)
	local function add(instance: Instance)
		if instance:IsA("Motor6D") or instance:IsA("AnimationConstraint") then
			motors[instance.Name] = instance
		end
	end
	for _, descendant in character:GetDescendants() do
		add(descendant)
	end
	character.DescendantAdded:Connect(add)
end

-- Cria ou troca as juntas de uma camada. speed = quão rápido o peso chega ao alvo (1/s).
function Pose.define(name: string, joints: { [string]: CFrame }, additive: boolean?, speed: number?)
	local layer = layers[name]
	if layer then
		layer.joints = joints
		return
	end
	layer = { joints = joints, additive = additive == true, weight = 0, target = 0, speed = speed or 12, order = #ordered + 1 }
	layers[name] = layer
	table.insert(ordered, layer)
end

function Pose.weight(name: string, target: number, instant: boolean?)
	local layer = layers[name]
	if layer then
		layer.target = target
		if instant then
			layer.weight = target
		end
	end
end

-- Pose atual de uma junta (já com as camadas) e peso de uma camada; usados pelos testes.
function Pose.transform(joint: string): CFrame?
	local motor = motors[joint]
	return if motor and motor.Parent then motor.Transform else nil
end

function Pose.current(name: string): number
	local layer = layers[name]
	return if layer then layer.weight else 0
end

-- Ciclo de corrida exagerado para uma fase (radianos): pernas largas, joelho dobrando na
-- recuperação, braços dobrados bombeando ao contrário das pernas, tronco torcendo e quicando.
-- amp = amplitude (1 = corrida forte), lean = inclinação do corpo em graus.
-- armsBack = braços esticados para trás (corrida ninja) em vez de bombear.
function Pose.runCycle(phase: number, amp: number, lean: number, armsBack: boolean?): { [string]: CFrame }
	local s, c = math.sin(phase), math.cos(phase)
	local stride = 58 * amp
	local pump = 62 * amp
	if armsBack then
		return {
			Root = CFrame.new(0, 0.28 * amp * math.abs(c) - 0.12, 0) * rad(-lean, 0, 5 * amp * s),
			Waist = rad(-lean * 0.6, 10 * amp * s, 0),
			Neck = rad(lean * 1.3, -6 * amp * s, 0),
			RightHip = rad(stride * s + 8, 0, 0),
			LeftHip = rad(-stride * s + 8, 0, 0),
			RightKnee = rad(-(18 + 80 * amp * math.max(0, c)), 0, 0),
			LeftKnee = rad(-(18 + 80 * amp * math.max(0, -c)), 0, 0),
			RightAnkle = rad(18 * s, 0, 0),
			LeftAnkle = rad(-18 * s, 0, 0),
			-- braços para trás, abertos, tremulando um pouco com o passo
			RightShoulder = rad(-68 + 7 * s, 0, 16 + 4 * c),
			LeftShoulder = rad(-68 - 7 * s, 0, -16 - 4 * c),
			RightElbow = rad(10, 0, 0),
			LeftElbow = rad(10, 0, 0),
		}
	end
	return {
		Root = CFrame.new(0, 0.28 * amp * math.abs(c) - 0.12, 0) * rad(-lean, 0, 5 * amp * s),
		Waist = rad(-lean * 0.5, 16 * amp * s, 0),
		Neck = rad(lean * 1.1, -10 * amp * s, 0),
		RightHip = rad(stride * s + 8, 0, 0),
		LeftHip = rad(-stride * s + 8, 0, 0),
		RightKnee = rad(-(18 + 80 * amp * math.max(0, c)), 0, 0),
		LeftKnee = rad(-(18 + 80 * amp * math.max(0, -c)), 0, 0),
		RightAnkle = rad(18 * s, 0, 0),
		LeftAnkle = rad(-18 * s, 0, 0),
		RightShoulder = rad(-pump * s - 8, 0, 10),
		LeftShoulder = rad(pump * s - 8, 0, -10),
		RightElbow = rad(88 + 18 * s, 0, 0),
		LeftElbow = rad(88 - 18 * s, 0, 0),
	}
end

---------------------------------------------------------------------------------------------------
-- Espelho das poses para os outros jogadores.
--
-- Motor6D.Transform mexido no cliente não replica: sem isto, cada um só vê as próprias poses
-- (corrida, dash, soco, montaria...) e os outros aparecem com a animação padrão. Enquanto
-- alguma camada está ativa, o cliente manda a pose final das juntas ao servidor algumas vezes
-- por segundo (pacote pequeno, canal não confiável); o servidor repassa aos outros, que a
-- aplicam no boneco do dono, interpolando. É genérico: qualquer camada nova já aparece.

local JOINTS = { "Root", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist", "RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle" }
local PACKET = #JOINTS * 6 + 6 -- 3 ângulos por junta + a posição da junta Root, tudo em int16
local SEND_INTERVAL = 1 / 15
local LINGER = 0.25 -- segundos mandando depois que a última camada desliga (para a volta ser suave)
local STALE = 0.35 -- sem pacote por este tempo, o boneco volta à animação padrão
local ANGLE = 32767 / math.pi
local OFFSET = 1000 -- milésimos de stud

Pose.PACKET = PACKET

type Mirror = { from: { CFrame }, to: { CFrame }, at: number, span: number, weight: number, character: Model?, motors: { [string]: any } }
local mirrors: { [Player]: Mirror } = {}

local function pack(): buffer
	local data = buffer.create(PACKET)
	for i, name in JOINTS do
		local motor = motors[name]
		local transform: CFrame = if motor and motor.Parent then motor.Transform else CFrame.identity
		local x, y, z = transform:ToEulerAnglesXYZ()
		local at = (i - 1) * 6
		buffer.writei16(data, at, math.round(x * ANGLE))
		buffer.writei16(data, at + 2, math.round(y * ANGLE))
		buffer.writei16(data, at + 4, math.round(z * ANGLE))
		if i == 1 then
			local p = transform.Position
			local tail = #JOINTS * 6
			buffer.writei16(data, tail, math.clamp(math.round(p.X * OFFSET), -32767, 32767))
			buffer.writei16(data, tail + 2, math.clamp(math.round(p.Y * OFFSET), -32767, 32767))
			buffer.writei16(data, tail + 4, math.clamp(math.round(p.Z * OFFSET), -32767, 32767))
		end
	end
	return data
end

local function unpack(data: buffer): { CFrame }
	local out = table.create(#JOINTS)
	local tail = #JOINTS * 6
	for i in JOINTS do
		local at = (i - 1) * 6
		local rotation = CFrame.Angles(buffer.readi16(data, at) / ANGLE, buffer.readi16(data, at + 2) / ANGLE, buffer.readi16(data, at + 4) / ANGLE)
		if i == 1 then
			rotation += Vector3.new(buffer.readi16(data, tail), buffer.readi16(data, tail + 2), buffer.readi16(data, tail + 4)) / OFFSET
		end
		out[i] = rotation
	end
	return out
end

local function receive(sender: Player, data: any)
	if typeof(sender) ~= "Instance" or sender == player or typeof(data) ~= "buffer" or buffer.len(data) ~= PACKET then
		return
	end
	local now = os.clock()
	local pose = unpack(data)
	local mirror = mirrors[sender]
	if not mirror or now - mirror.at > STALE then
		mirrors[sender] = { from = pose, to = pose, at = now, span = SEND_INTERVAL, weight = if mirror then mirror.weight else 0, character = if mirror then mirror.character else nil, motors = if mirror then mirror.motors else {} }
		return
	end
	-- parte de onde a interpolação estava e vai até a pose nova
	local alpha = math.clamp((now - mirror.at) / mirror.span, 0, 1)
	local from = table.create(#JOINTS)
	for i in JOINTS do
		from[i] = mirror.from[i]:Lerp(mirror.to[i], alpha)
	end
	mirror.from, mirror.to = from, pose
	mirror.span = math.clamp(now - mirror.at, SEND_INTERVAL * 0.5, SEND_INTERVAL * 3)
	mirror.at = now
end

local function applyMirrors(now: number, dt: number)
	for sender, mirror in mirrors do
		local character = sender.Character
		if sender.Parent == nil or not character then
			mirrors[sender] = nil
			continue
		end
		local fresh = now - mirror.at < STALE
		mirror.weight = math.clamp(mirror.weight + (if fresh then dt else -dt) * 8, 0, 1)
		if mirror.weight <= 0 then
			if not fresh then
				mirrors[sender] = nil
			end
			continue
		end
		if mirror.character ~= character then
			mirror.character = character
			table.clear(mirror.motors)
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
					mirror.motors[descendant.Name] = descendant
				end
			end
		end
		local alpha = math.clamp((now - mirror.at) / mirror.span, 0, 1)
		for i, name in JOINTS do
			local motor = mirror.motors[name]
			if motor and motor.Parent then
				local pose = mirror.from[i]:Lerp(mirror.to[i], alpha)
				if i > 1 then
					pose += motor.Transform.Position -- só a junta Root manda posição
				end
				motor.Transform = motor.Transform:Lerp(pose, mirror.weight)
			end
		end
	end
end

-- Para os testes: empacota a pose atual, desempacota e mede o maior erro (graus e studs); e
-- quantos pacotes já saíram e quantos jogadores estão sendo espelhados.
local sent = 0
function Pose.syncDebug(): { [string]: any }
	local back = unpack(pack())
	local worst, shift = 0, 0
	for i, name in JOINTS do
		local motor = motors[name]
		if motor and motor.Parent then
			local transform: CFrame = motor.Transform
			local _, angle = (transform.Rotation:Inverse() * back[i].Rotation):ToAxisAngle()
			worst = math.max(worst, math.deg(math.abs(angle)))
			if i == 1 then
				shift = (transform.Position - back[i].Position).Magnitude
			end
		end
	end
	local count = 0
	for _ in mirrors do
		count += 1
	end
	return { sent = sent, mirrored = count, angleError = worst, offsetError = shift, bytes = PACKET }
end

-- Para os testes: trata o pacote do próprio jogador como se viesse de `sender`.
function Pose.syncLoopback(sender: Player)
	local data = pack()
	local now = os.clock()
	local pose = unpack(data)
	mirrors[sender] = { from = pose, to = pose, at = now, span = SEND_INTERVAL, weight = 0, character = nil, motors = {} }
end

function Pose.start()
	player.CharacterAdded:Connect(collect)
	if player.Character then
		collect(player.Character)
	end

	local remote: UnreliableRemoteEvent? = nil
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PoseSync", 30)
		if found and found:IsA("UnreliableRemoteEvent") then
			remote = found
			found.OnClientEvent:Connect(receive)
		end
	end)
	local lastSend, lastActive = 0, -math.huge

	RunService.Stepped:Connect(function(_, dt)
		local active = false
		for _, layer in ordered do
			if layer.weight ~= layer.target then
				layer.weight += (layer.target - layer.weight) * (1 - math.exp(-layer.speed * dt))
				if math.abs(layer.weight - layer.target) < 0.005 then
					layer.weight = layer.target
				end
			end
			if layer.weight > 0 then
				for joint, pose in layer.joints do
					local motor = motors[joint]
					if motor and motor.Parent then
						if layer.additive then
							motor.Transform *= CFrame.identity:Lerp(pose, layer.weight)
							active = active or pose ~= CFrame.identity
						else
							motor.Transform = motor.Transform:Lerp(pose, layer.weight)
							active = true
						end
					end
				end
			end
		end

		-- manda a pose final aos outros enquanto alguma camada mexe no boneco
		local now = os.clock()
		if active then
			lastActive = now
		end
		if remote and now - lastActive < LINGER and now - lastSend >= SEND_INTERVAL then
			lastSend = now
			sent += 1
			remote:FireServer(pack())
		end
		applyMirrors(now, dt)
	end)
end

return Pose
