--!strict
-- Poses procedurais por cima das animações padrão (R15). Cada camada tem um peso suavizado;
-- no Stepped (depois do Animator) a pose animada é misturada com a da camada.
-- "override" troca a junta pela pose; "additive" soma a rotação (inclinação ao correr).

local Players = game:GetService("Players")
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

function Pose.start()
	player.CharacterAdded:Connect(collect)
	if player.Character then
		collect(player.Character)
	end
	RunService.Stepped:Connect(function(_, dt)
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
						else
							motor.Transform = motor.Transform:Lerp(pose, layer.weight)
						end
					end
				end
			end
		end
	end)
end

return Pose
