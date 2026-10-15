--!strict
-- Saco de pancada no cliente: pede o soco, anima um combo de corpo inteiro (jab, cruzado,
-- gancho, uppercut) e mostra o impacto. Ganho e crítico vêm sempre do servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Aura = require(script.Parent.Aura)
local Auto = require(script.Parent.Auto)
local Fx = require(script.Parent.Fx)
local Pose = require(script.Parent.Pose)
local Super = require(script.Parent.Super)
local Windows = require(script.Parent.Windows)

local P = Config.Palette
local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 214, 40)
local deg = Pose.deg

local Bag = {}
-- Outro alvo para o mesmo soco (o golem da sala do chefe, src/client/Boss.luau): devolve o centro
-- dele quando o jogador está perto o bastante, e onTarget avisa o servidor de cada soco.
Bag.target = nil :: (() -> Vector3?)?
Bag.onTarget = nil :: (() -> ())?

local bagModel: Model? = nil
local bagCenter = Vector3.zero
local restPivot = CFrame.identity
local hint: BillboardGui? = nil

local holding = false
local pending = false
local angle = 0
local velocity = 0

local SPRING = 70
local DAMPING = 6

---------------------------------------------------------------------------------------------------
-- Combo. Cada golpe: recuo (wind) -> estalo (strike) -> volta para a guarda.

type PoseSet = { [string]: CFrame }

-- guarda de luta: pés afastados, joelhos dobrados, tronco de lado, punhos no rosto
local GUARD: PoseSet = {
	Root = CFrame.new(0, -0.22, 0) * deg(-4, -14, 0),
	Waist = deg(-8, -8, 0),
	Neck = deg(4, 18, 0),
	RightShoulder = deg(56, 0, -8),
	LeftShoulder = deg(62, 0, 8),
	RightElbow = deg(112, 0, 0),
	LeftElbow = deg(108, 0, 0),
	RightHip = deg(-18, 0, 6),
	LeftHip = deg(24, 0, -4),
	RightKnee = deg(-26, 0, 0),
	LeftKnee = deg(-30, 0, 0),
}

local COMBO: { { name: string, wind: PoseSet, strike: PoseSet, up: boolean? } } = {
	{ -- jab de direita: reto e rápido
		name = "jab",
		wind = { RightShoulder = deg(38, 0, -14), RightElbow = deg(128, 0, 0), Waist = deg(-6, -20, 0) },
		strike = {
			Root = CFrame.new(0, -0.25, -0.45) * deg(-8, 8, 0),
			RightShoulder = deg(96, 0, 8),
			RightElbow = deg(3, 0, 0),
			Waist = deg(-10, 34, 0),
			LeftHip = deg(36, 0, -4),
			LeftKnee = deg(-42, 0, 0),
		},
	},
	{ -- cruzado de esquerda: o tronco inteiro gira
		name = "cross",
		wind = { LeftShoulder = deg(34, 0, 14), LeftElbow = deg(130, 0, 0), Waist = deg(-6, 26, 0), Root = CFrame.new(0, -0.25, 0.1) * deg(-4, 6, 0) },
		strike = {
			Root = CFrame.new(0, -0.3, -0.7) * deg(-12, -22, 0),
			LeftShoulder = deg(100, 0, -8),
			LeftElbow = deg(3, 0, 0),
			RightShoulder = deg(30, 0, -20),
			Waist = deg(-14, -46, 0),
			Neck = deg(6, 40, 0),
			LeftHip = deg(42, 0, -4),
			LeftKnee = deg(-50, 0, 0),
			RightHip = deg(-34, 0, 6),
		},
	},
	{ -- gancho de direita: braço aberto varre para dentro
		name = "hook",
		wind = { RightShoulder = deg(24, 0, 86), RightElbow = deg(96, 0, 0), Waist = deg(-4, -36, 0), Root = CFrame.new(0, -0.3, 0) * deg(-4, -24, 0) },
		strike = {
			Root = CFrame.new(0, -0.3, -0.4) * deg(-8, 26, 0),
			RightShoulder = deg(88, 0, -30),
			RightElbow = deg(92, 0, 0),
			LeftShoulder = deg(40, 0, 18),
			Waist = deg(-8, 58, 0),
			Neck = deg(4, -34, 0),
			RightHip = deg(8, 0, 6),
			RightKnee = deg(-34, 0, 0),
		},
	},
	{ -- uppercut de esquerda: afunda e sobe com o braço
		name = "uppercut",
		up = true,
		wind = {
			Root = CFrame.new(0, -0.75, 0) * deg(-20, 16, 0),
			LeftShoulder = deg(-28, 0, -10),
			LeftElbow = deg(70, 0, 0),
			Waist = deg(-14, 22, 0),
			LeftHip = deg(48, 0, -4),
			LeftKnee = deg(-70, 0, 0),
			RightHip = deg(-10, 0, 6),
			RightKnee = deg(-58, 0, 0),
		},
		strike = {
			Root = CFrame.new(0, 0.35, -0.35) * deg(10, -26, 0),
			LeftShoulder = deg(156, 0, -6),
			LeftElbow = deg(64, 0, 0),
			RightShoulder = deg(20, 0, -24),
			Waist = deg(10, -40, 0),
			Neck = deg(18, 30, 0),
			LeftHip = deg(10, 0, -4),
			LeftKnee = deg(-8, 0, 0),
			RightHip = deg(-8, 0, 6),
			RightKnee = deg(-6, 0, 0),
		},
	},
}

local PUNCH_TIME = 0.24
local punchStart = -10
local comboStep = 0
local lastStep = COMBO[1]
local fromPose: PoseSet = GUARD

local function blend(a: PoseSet, b: PoseSet, t: number): PoseSet
	local out: PoseSet = {}
	for joint, guard in GUARD do
		out[joint] = (a[joint] or guard):Lerp(b[joint] or guard, t)
	end
	return out
end

local function punchPose(u: number): PoseSet
	local step = lastStep
	if u < 0.22 then
		return blend(fromPose, step.wind, (u / 0.22) ^ 0.7)
	elseif u < 0.42 then
		return blend(step.wind, step.strike, ((u - 0.22) / 0.2) ^ 0.45) -- estalo
	elseif u < 0.62 then
		return blend(step.strike, step.strike, 0)
	end
	return blend(step.strike, GUARD, ((u - 0.62) / 0.38) ^ 1.4)
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function startPunch(center: Vector3?)
	local now = os.clock()
	local facing = center or bagCenter
	-- encadeia a partir de onde o corpo está; combo zera depois de 1,2 s parado
	fromPose = if now - punchStart < PUNCH_TIME then punchPose((now - punchStart) / PUNCH_TIME) else GUARD
	if now - punchStart > 1.2 then
		comboStep = 0
	end
	comboStep = comboStep % #COMBO + 1
	lastStep = COMBO[comboStep]
	punchStart = now

	-- parado, vira de frente para o saco
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootPart()
	if root and humanoid and humanoid.MoveDirection.Magnitude < 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(facing.X, root.Position.Y, facing.Z))
	end
end

local function stepPunch()
	local elapsed = os.clock() - punchStart
	if elapsed < PUNCH_TIME then
		Pose.define("punch", punchPose(elapsed / PUNCH_TIME))
		Pose.weight("punch", 1, true)
	else
		Pose.weight("punch", 0, true)
	end
	Pose.weight("guard", if elapsed < 1.1 then 1 else 0)
end

---------------------------------------------------------------------------------------------------
-- Impacto

local function inRange(): boolean
	local root = rootPart()
	if not root or not bagModel then
		return false
	end
	local flat = Vector3.new(root.Position.X - bagCenter.X, 0, root.Position.Z - bagCenter.Z)
	return flat.Magnitude <= Config.Bag.hitRange
end

local function floatNumber(gain: number, crit: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = bagCenter + Vector3.new(math.random(-15, 15) / 10, 2.5, math.random(-15, 15) / 10)

	local board = Instance.new("BillboardGui")
	board.Size = if crit then UDim2.fromScale(11, 4.4) else UDim2.fromScale(5, 2.2)
	board.AlwaysOnTop = true
	board.Parent = anchor

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = if crit then GOLD else P.hitNumber
	text.Text = if crit then `CRIT! +{gain}` else `+{gain}`
	text.Rotation = math.random(-12, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if crit then 6 else 4
	stroke.Color = if crit then Color3.fromRGB(120, 20, 0) else P.outline
	stroke.Parent = text
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = text
	text.Parent = board

	anchor.Parent = workspace.CurrentCamera

	local hold = if crit then 0.7 else 0.35
	TweenService:Create(scale, TweenInfo.new(if crit then 0.22 else 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(board, TweenInfo.new(hold + 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, if crit then 5 else 3.5, 0) }):Play()
	local fade = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold)
	TweenService:Create(text, fade, { TextTransparency = 1 }):Play()
	local last = TweenService:Create(stroke, fade, { Transparency = 1 })
	last.Completed:Connect(function()
		anchor:Destroy()
	end)
	last:Play()
end

-- Impacto confirmado pelo servidor: estrela na frente, onda de ar e energia saindo por trás.
local function onHit(gain: number, crit: boolean?)
	local root = rootPart()
	local side = if root and root.Position.X < bagCenter.X then 1 else -1
	local isCrit = crit == true
	velocity += side * (if isCrit then 11 else 5)
	floatNumber(gain, isCrit)
	if hint then
		hint.Enabled = false
	end

	local color = Aura.color()
	local flat = if root then Vector3.new(bagCenter.X - root.Position.X, 0, bagCenter.Z - root.Position.Z) else Vector3.xAxis
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
	local front = bagCenter - dir * 1.8
	local back = bagCenter + dir * 1.8
	local floor = Vector3.new(bagCenter.X, if root then root.Position.Y - 2.8 else bagCenter.Y - 7, bagCenter.Z)
	local bright = color:Lerp(WHITE, 0.45)
	local upward = lastStep.up == true

	Fx.star(front, -dir, WHITE, 6, 3, 0.2)
	Fx.burst(front, WHITE, 3, 0.14)
	Fx.shock(back, dir, bright, 9, 0.28)
	Fx.burst(back, color, 5, 0.25)
	for _ = 1, 6 do
		local spread = Vector3.new(math.random(-10, 10), math.random(-8, 10), math.random(-10, 10)) / 10 * 3
		local travel = if upward then Vector3.new(0, 12, 0) + dir * 4 + spread else dir * 12 + spread
		Fx.streak(back + spread * 0.4, travel, bright, 3.5, 0.3)
	end
	Fx.cubes(back, color, 4, 12, (if upward then Vector3.new(0, 30, 0) else Vector3.zero) + dir * 30, 0.6, Enum.Material.Neon)
	Fx.shake(0.14)
	if upward then
		Fx.ring(floor, bright, 18, 0.35)
	end

	if isCrit then
		-- crítico: X dourado, duas ondas de ar, explosão, chuva de cubos, clarão e coice de câmera
		Fx.flash(GOLD, 0.4, 0.2)
		Fx.shake(0.75)
		Fx.star(front, -dir, GOLD, 22, 2, 0.4)
		Fx.star(front, -dir, WHITE, 12, 4, 0.28)
		Fx.shock(back, dir, GOLD, 18, 0.32)
		task.delay(0.07, Fx.shock, back + dir * 2, dir, WHITE, 28, 0.4)
		Fx.burst(bagCenter, GOLD, 17, 0.35)
		Fx.ring(floor, GOLD, 38, 0.5)
		Fx.cubes(back, GOLD, 16, 26, dir * 44 + Vector3.new(0, 14, 0), 1, Enum.Material.Neon)
		for i = 1, 12 do
			local around = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, i * math.pi / 6) * Vector3.new(0, 1, 0)
			Fx.streak(bagCenter + around * 1.5, around * 13 + dir * 4, GOLD:Lerp(WHITE, 0.5), 5, 0.38)
		end
		local camera = workspace.CurrentCamera
		if camera.CameraType == Enum.CameraType.Custom then
			camera.FieldOfView = 60
			TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = 70 }):Play()
		end
	end
end

local function stepSwing(dt: number)
	local model = bagModel
	if not model or (math.abs(angle) < 0.001 and math.abs(velocity) < 0.001) then
		return
	end
	local step = math.min(dt, 1 / 30)
	velocity += (-SPRING * angle - DAMPING * velocity) * step
	angle = math.clamp(angle + velocity * step, -1.1, 1.1)
	model:PivotTo(restPivot * CFrame.Angles(0, 0, angle))
end

local function isPunchInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function Bag.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local bagHit = remotes:WaitForChild("BagHit") :: RemoteEvent

	-- o saco é o do terreno do mundo em que o jogador está: ao viajar, troca para o de lá
	local binding = 0
	local function bind()
		binding += 1
		local mine = binding
		bagModel = nil
		while player:GetAttribute("PlotId") == nil do
			player:GetAttributeChangedSignal("PlotId"):Wait()
		end
		local folder = workspace:WaitForChild(Config.worldOf(player).plots, 60)
		local plot = folder and folder:WaitForChild("Plot" .. tostring(player:GetAttribute("PlotId")), 60)
		local gantry = plot and plot:WaitForChild("Gantry", 60)
		local model = gantry and gantry:WaitForChild("Bag", 60)
		local body = model and model:WaitForChild("Body", 60)
		if mine ~= binding or not model or not model:IsA("Model") or not body or not model:WaitForChild("Chain", 60) then
			return
		end
		bagCenter = model:GetAttribute("Center") :: Vector3
		restPivot = model:GetPivot()
		local found = body:WaitForChild("Hint", 5)
		if mine ~= binding then
			return
		end
		hint = if found and found:IsA("BillboardGui") then found else nil
		bagModel = model
	end
	task.spawn(bind)
	player:GetAttributeChangedSignal("World"):Connect(function()
		task.spawn(bind)
	end)

	bagHit.OnClientEvent:Connect(onHit)
	-- o super soco balança o saco bem mais que um soco comum
	Super.onImpact = function()
		local root = rootPart()
		velocity += (if root and root.Position.X < bagCenter.X then 1 else -1) * 26
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and isPunchInput(input) then
			holding = true
			-- um clique rápido ainda conta como um soco, mas só perto do saco (ou do golem)
			pending = inRange() or (Bag.target ~= nil and (Bag.target :: () -> Vector3?)() ~= nil)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPunchInput(input) then
			holding = false
		end
	end)

	-- segurar o botão repete o soco; o servidor ainda aplica o próprio intervalo
	task.spawn(function()
		while true do
			local near = inRange()
			local other = if not near and Bag.target then Bag.target() else nil
			-- o soco automático é só para o saco; no golem, só segurando o botão
			if (holding or pending or (Auto.isOn("punch") and near)) and (near or other) and not Super.isBusy() and not Windows.current() then
				pending = false
				if other then
					startPunch(other)
					if Bag.onTarget then
						Bag.onTarget()
					end
				else
					startPunch()
					bagHit:FireServer()
				end
				task.wait(Config.Bag.holdInterval)
			else
				task.wait()
			end
		end
	end)

	-- a guarda fica por baixo; o golpe do combo é redefinido a cada quadro por cima dela
	Pose.define("guard", GUARD, false, 14)
	Pose.define("punch", GUARD, false, 40)

	RunService.RenderStepped:Connect(stepSwing)
	RunService.RenderStepped:Connect(stepPunch)
end

return Bag
