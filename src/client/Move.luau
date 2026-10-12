--!strict
-- Movimento no lobby: corrida (Shift, ou automática depois de 1 s andando) com ciclo próprio e
-- braços para trás, dash (Q), pulo duplo com cambalhota, inclinação nas curvas, poeira, pisão
-- ao pousar, riscos de vento e campo de visão abrindo. A velocidade base vem do atributo SPEED.
-- Só visual e velocidade local; nenhuma regra de jogo depende disto.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Aura = require(script.Parent.Aura)
local Fx = require(script.Parent.Fx)
local Pose = require(script.Parent.Pose)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local MOVE = Config.Move

local Move = {}

local AUTO_SPRINT_AFTER = 1 -- segundos andando sem parar
local DUST = Color3.fromRGB(240, 235, 215)
local DIRT = Color3.fromRGB(122, 80, 40)
local WHITE = Color3.new(1, 1, 1)

local sprintAlpha = 0
local movingFor = 0
local lastYaw = 0
local bank = 0
local stride = 0
local steps = 0
local runPhase = 0
local windDebt = 0
local rng = Random.new()

local dashUntil = 0
local dashReady = 0
local dashDirection = Vector3.zAxis
local ghostAt = 0
local flipStart = -10
local lastJumpRequest = 0
local FLIP_TIME = 0.6
-- Janela do pulo duplo, contada a partir do primeiro toque. O pulo simples dura ~0,55 s no ar;
-- até JUMP_SEQUENCE o segundo toque ainda vira pulo duplo, mesmo já tendo pousado.
local JUMP_SEQUENCE = 1.1
local firstJumpAt = -10
local usedDouble = false
local dashStart = -10
local dashInAir = false
local dashPoseUntil = 0
local skidUntil = 0
local swayStart = -10
local wasSprinting = false

local function parts(): (Humanoid?, BasePart?, Model?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root, character
	end
	return nil, nil, nil
end

-- Velocidade de caminhada com o atributo SPEED comprado no painel.
function Move.walkSpeed(): number
	local level = player:GetAttribute("Stat_speed")
	return MOVE.walk + (if type(level) == "number" then level else 0) * Config.Stats.speed.perLevel
end

local function stomp(position: Vector3, size: number, cubes: number)
	Fx.burst(position, WHITE, size, 0.3)
	Fx.ring(position + Vector3.new(0, 0.2, 0), Aura.color(), size * 1.6, 0.35)
	Fx.cubes(position + Vector3.new(0, 0.5, 0), DIRT, cubes, 16, Vector3.new(0, 12, 0), 0.8)
end

-- Dash: arrancada curta na direção do movimento (ou para onde o personagem olha). Vale no ar.
local function dash()
	local humanoid, root, character = parts()
	local now = os.clock()
	if not humanoid or not root or not character or root.Anchored or humanoid.PlatformStand or now < dashReady then
		return
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	if direction.Magnitude < 0.1 then
		return
	end
	dashDirection = direction.Unit
	dashStart = now
	dashUntil = now + MOVE.dashTime
	dashReady = now + MOVE.dashCooldown
	dashInAir = humanoid.FloorMaterial == Enum.Material.Air
	-- a pose deitada dura até o giro acabar, mesmo que o empurrão termine antes (chão e ar)
	dashPoseUntil = now + math.max(MOVE.dashTime, MOVE.dashRollTime)
	ghostAt = 0
	-- vira o corpo para a direção do dash na hora
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dashDirection)

	local color = Aura.color()
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	Fx.shock(root.Position, -dashDirection, color:Lerp(WHITE, 0.4), 14, 0.3)
	task.delay(0.05, Fx.shock, root.Position + dashDirection * 5, -dashDirection, WHITE, 9, 0.25)
	-- nuvem de arrancada: bolas brancas atrás, abrindo
	for i = 1, 5 do
		local side = Vector3.new(rng:NextNumber(-1.6, 1.6), rng:NextNumber(-1.4, 1.4), rng:NextNumber(-1.6, 1.6))
		Fx.burst(root.Position - dashDirection * (1 + i * 0.5) + side, WHITE, 3 + i * 0.5, 0.3)
	end
	if not dashInAir then
		Fx.ring(feet, color, 16, 0.3)
		Fx.cubes(feet + Vector3.new(0, 0.5, 0), DIRT, 6, 14, -dashDirection * 26 + Vector3.new(0, 10, 0), 0.8)
	end
	Fx.shake(0.25)
	Aura.forceTrails(true)
end

-- Pulo duplo: um pulo extra com mortal. A janela é larga de propósito: vale a qualquer momento
-- no ar e também se o segundo toque chegar atrasado, logo depois de pousar do primeiro pulo.
local function doubleJump()
	local humanoid, root = parts()
	if not humanoid or not root or root.Anchored or humanoid.PlatformStand then
		return
	end
	local now = os.clock()
	local late = humanoid.FloorMaterial ~= Enum.Material.Air
	if late then
		-- toque no chão: é o primeiro pulo de uma sequência nova, a menos que venha logo depois
		-- de outro pulo que ainda não gastou o duplo (segundo toque atrasado)
		local sinceFirst = now - firstJumpAt
		if usedDouble or sinceFirst < 0.3 or sinceFirst > JUMP_SEQUENCE then
			firstJumpAt = now
			usedDouble = false
			return
		end
	elseif usedDouble and now - firstJumpAt < 2 then
		return
	end
	usedDouble = true
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, MOVE.doubleJumpPower, velocity.Z)
	if late then
		-- no chão o pulo normal do Humanoid sai neste mesmo instante e sobrescreve o impulso:
		-- reaplica logo depois
		task.delay(0.06, function()
			if root.Parent and not root.Anchored then
				local current = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(current.X, MOVE.doubleJumpPower, current.Z)
			end
		end)
	end
	flipStart = os.clock()

	local color = Aura.color()
	local below = root.Position - Vector3.new(0, 2.6, 0)
	Fx.ring(below, color:Lerp(WHITE, 0.4), 15, 0.35)
	Fx.burst(below, WHITE, 6, 0.25)
	for i = 1, 8 do
		local angle = i * math.pi / 4
		Fx.streak(below + Vector3.new(math.cos(angle) * 1.5, 0, math.sin(angle) * 1.5), Vector3.new(math.cos(angle) * 5, -7, math.sin(angle) * 5), color:Lerp(WHITE, 0.5), 2.5, 0.3)
	end
	Fx.shake(0.15)
end

-- Troca a caminhada padrão pelo asset de Config.Move.walkAnimationId. No Animate atual a
-- caminhada mistura "walk" e "run" pela velocidade, então os dois recebem o mesmo asset
-- (a corrida de verdade é a camada "sprint", que cobre os dois).
local CUSTOM_WALK = MOVE.walkAnimationId ~= ""
local function applyWalkAnimation(character: Model)
	local animate = character:WaitForChild("Animate", 10)
	if not animate then
		return
	end
	for holderName, animationName in { walk = "WalkAnim", run = "RunAnim" } do
		local holder = animate:WaitForChild(holderName, 5)
		local animation = holder and holder:FindFirstChild(animationName)
		if animation and animation:IsA("Animation") then
			animation.AnimationId = MOVE.walkAnimationId
		end
	end
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if CUSTOM_WALK then
		task.spawn(applyWalkAnimation, character)
	end
	usedDouble = false
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and not root.Anchored then
				stomp(root.Position - Vector3.new(0, 2.9, 0), 9, 7)
				Fx.shake(0.22)
			end
		end
	end)
end

-- Botão de dash para toque, acima do botão de pulo.
local function touchButton()
	if not UserInputService.TouchEnabled then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MoveButtons"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	local button = Instance.new("TextButton")
	button.Name = "DashButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -110, 1, -120)
	button.Size = UDim2.fromOffset(64, 64)
	button.BackgroundColor3 = Color3.fromRGB(30, 34, 54)
	button.BackgroundTransparency = 0.25
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 18
	button.TextColor3 = WHITE
	button.Text = "DASH"
	Ui.corner(button, 32)
	Ui.border(button, 3)
	Ui.stroke(button, 2)
	button.Activated:Connect(dash)
	button.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

Move.dash = dash -- o gancho de teste dispara o dash sem tecla

function Move.start()
	-- inclinação: soma na junta Root (corpo inteiro)
	Pose.define("lean", { Root = CFrame.identity }, true, 30)
	Pose.weight("lean", 1, true)
	-- correndo: ciclo de pernas próprio, braços para trás (a fase anda com a distância)
	Pose.define("sprint", Pose.runCycle(0, 1, 16, true), false, 9)
	-- andando: braços levemente para trás, somados ao balanço da caminhada padrão
	Pose.define("walkArms", {
		RightShoulder = Pose.deg(-24, 0, 9),
		LeftShoulder = Pose.deg(-24, 0, -9),
		RightElbow = Pose.deg(-6, 0, 0),
		LeftElbow = Pose.deg(-6, 0, 0),
		Waist = Pose.deg(-4, 0, 0),
	}, true, 7)
	-- balanço ao arrancar a corrida: soma no corpo inteiro, por cima do ciclo
	Pose.define("sway", { Root = CFrame.identity }, true, 60)
	Pose.weight("sway", 1, true)
	-- dash no chão: voo deitado (Superman), um braço à frente, o outro colado ao corpo, pernas
	-- juntas e esticadas. O parafuso entra na camada "flip", por cima desta.
	Pose.define("dash", {
		Root = CFrame.new(0, -0.3, 0) * Pose.deg(-90, 0, 0),
		Waist = Pose.deg(6, 0, 0),
		Neck = Pose.deg(70, 0, 0),
		RightShoulder = Pose.deg(178, 0, 4),
		RightElbow = Pose.deg(0, 0, 0),
		LeftShoulder = Pose.deg(-8, 0, -10),
		LeftElbow = Pose.deg(6, 0, 0),
		RightHip = Pose.deg(-6, 0, 3),
		RightKnee = Pose.deg(-4, 0, 0),
		LeftHip = Pose.deg(-6, 0, -3),
		LeftKnee = Pose.deg(-4, 0, 0),
		RightAnkle = Pose.deg(-30, 0, 0),
		LeftAnkle = Pose.deg(-30, 0, 0),
	}, false, 45)
	-- fim do dash no chão: freada, corpo para trás, perna da frente esticada, braços abertos
	Pose.define("skid", {
		Root = CFrame.new(0, -0.45, 0) * Pose.deg(14, 0, 0),
		Waist = Pose.deg(-18, 0, 0),
		Neck = Pose.deg(6, 0, 0),
		RightShoulder = Pose.deg(10, 0, 62),
		LeftShoulder = Pose.deg(10, 0, -62),
		RightElbow = Pose.deg(30, 0, 0),
		LeftElbow = Pose.deg(30, 0, 0),
		RightHip = Pose.deg(58, 0, 0),
		RightKnee = Pose.deg(-14, 0, 0),
		LeftHip = Pose.deg(-8, 0, 0),
		LeftKnee = Pose.deg(-84, 0, 0),
	}, false, 16)
	-- mortal do pulo duplo: corpo encolhido, joelhos no peito, braços abraçando as pernas
	Pose.define("tuck", {
		Waist = Pose.deg(-38, 0, 0),
		Neck = Pose.deg(-24, 0, 0),
		RightHip = Pose.deg(118, 0, 6),
		LeftHip = Pose.deg(118, 0, -6),
		RightKnee = Pose.deg(-128, 0, 0),
		LeftKnee = Pose.deg(-128, 0, 0),
		RightShoulder = Pose.deg(74, 0, -22),
		LeftShoulder = Pose.deg(74, 0, 22),
		RightElbow = Pose.deg(84, 0, 0),
		LeftElbow = Pose.deg(84, 0, 0),
	}, false, 20)
	-- giro do mortal (para a frente) e do dash no ar (parafuso): somam na junta Root
	Pose.define("flip", { Root = CFrame.identity }, true, 60)
	Pose.weight("flip", 1, true)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX) then
			dash()
		end
	end)
	-- JumpRequest repete a cada quadro enquanto o botão fica apertado: um toque novo é uma pausa
	-- curta entre pedidos (antes eram 0,25 s, o que barrava o toque duplo rápido)
	UserInputService.JumpRequest:Connect(function()
		local now = os.clock()
		local fresh = now - lastJumpRequest > 0.07
		lastJumpRequest = now
		if fresh then
			doubleJump()
		end
	end)
	touchButton()

	RunService.RenderStepped:Connect(function(dt)
		local humanoid, root, character = parts()
		if not humanoid or not root or not character or root.Anchored or humanoid.PlatformStand then
			sprintAlpha = 0
			movingFor = 0
			dashUntil = 0
			dashPoseUntil = 0
			wasSprinting = false
			Pose.weight("sprint", 0)
			Pose.weight("dash", 0)
			Pose.weight("skid", 0)
			Pose.weight("tuck", 0)
			Pose.weight("walkArms", 0)
			Pose.define("lean", { Root = CFrame.identity })
			Pose.define("sway", { Root = CFrame.identity })
			Pose.define("flip", { Root = CFrame.identity })
			Aura.setSprint(0)
			return
		end

		local now = os.clock()
		local walk = Move.walkSpeed()
		local sprintSpeed = walk + MOVE.sprintBonus
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local dashing = now < dashUntil
		movingFor = if moving then movingFor + dt else 0

		-- dash: empurra na horizontal, deixa fantasmas e riscos paralelos ao caminho
		if dashing then
			root.AssemblyLinearVelocity = Vector3.new(dashDirection.X * MOVE.dashSpeed, math.max(velocity.Y, 0), dashDirection.Z * MOVE.dashSpeed)
			if now >= ghostAt then
				ghostAt = now + 0.04
				Fx.ghost(character, Aura.color():Lerp(WHITE, 0.3), 0.3)
			end
			for _ = 1, 3 do
				local offset = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-2.2, 2.6), rng:NextNumber(-3, 3))
				Fx.streak(root.Position + offset, -dashDirection * 14, WHITE, 5, 0.2)
			end
		elseif dashUntil > 0 then
			dashUntil = 0
			Aura.forceTrails(false)
			-- no chão termina freando: poeira para a frente e pose de derrapagem
			if grounded then
				skidUntil = math.max(now, dashPoseUntil) + 0.26
				local feet = root.Position - Vector3.new(0, 2.8, 0)
				Fx.cubes(feet + Vector3.new(0, 0.4, 0), DUST, 8, 9, dashDirection * 22 + Vector3.new(0, 7, 0), 0.6)
				Fx.ring(feet, WHITE, 11, 0.3)
			end
		end
		-- o parafuso (no chão e no ar) entra na camada "flip"; a freada espera a pose deitada acabar
		local flying = now < dashPoseUntil
		Pose.weight("dash", if flying then 1 else 0)
		Pose.weight("skid", if now < skidUntil and grounded and not dashing and not flying then 1 else 0)

		local wantSprint = moving and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or movingFor > AUTO_SPRINT_AFTER)
		sprintAlpha += ((if wantSprint then 1 else 0) - sprintAlpha) * (1 - math.exp(-6 * dt))
		humanoid.WalkSpeed = walk + (sprintSpeed - walk) * sprintAlpha
		Pose.weight("sprint", if sprintAlpha > 0.5 and grounded and not dashing then 1 else 0)
		Aura.setSprint(sprintAlpha)
		local fast = math.max(sprintAlpha, if dashing then 1.4 else 0)
		if camera.CameraType == Enum.CameraType.Custom and (fast > 0.02 or camera.FieldOfView > 70.5) and camera.FieldOfView >= 69 then
			camera.FieldOfView += (70 + 12 * fast - camera.FieldOfView) * (1 - math.exp(-10 * dt))
		end

		-- inclina para a frente com a velocidade e deita nas curvas
		local _, yaw = root.CFrame:ToOrientation()
		local turn = math.atan2(math.sin(yaw - lastYaw), math.cos(yaw - lastYaw)) / math.max(dt, 1 / 240)
		lastYaw = yaw
		local frac = math.clamp(speed / sprintSpeed, 0, 1)
		bank += (math.clamp(-turn * 0.05, -0.3, 0.3) * frac - bank) * (1 - math.exp(-8 * dt))
		-- a corrida já inclina o corpo no próprio ciclo; aqui fica a inclinação da caminhada e a curva
		Pose.define("lean", { Root = CFrame.Angles(-math.rad(7) * frac * (1 - sprintAlpha), 0, bank) })
		runPhase += speed * dt * 0.42
		Pose.define("sprint", Pose.runCycle(runPhase, 0.85 + 0.15 * frac, 18, true))
		-- com asset próprio de caminhada os braços já vêm na animação
		Pose.weight("walkArms", if not CUSTOM_WALK and moving and grounded and sprintAlpha < 0.5 and not dashing then 1 else 0)

		-- balanço ao arrancar a corrida: mergulho para a frente e um vai-e-vem que morre em ~0,7 s
		local sprinting = sprintAlpha > 0.5
		if sprinting and not wasSprinting then
			swayStart = now
		end
		wasSprinting = sprinting
		local since = now - swayStart
		if since < 0.9 then
			local decay = math.exp(-5 * since)
			Pose.define("sway", { Root = CFrame.Angles(-0.2 * decay * math.cos(since * 9), 0, 0.13 * decay * math.sin(since * 13)) })
		else
			Pose.define("sway", { Root = CFrame.identity })
		end

		-- mortal do pulo duplo: uma volta completa encolhido
		local flip = (now - flipStart) / FLIP_TIME
		local spin = CFrame.identity
		if flip < 1 then
			local eased = flip * flip * (3 - 2 * flip)
			spin = CFrame.Angles(-math.pi * 2 * eased, 0, 0)
		end
		Pose.weight("tuck", if flip > 0.06 and flip < 0.78 then 1 else 0)
		-- giro do dash (chão e ar). O corpo está deitado: na junta Root, Z aponta para cima do
		-- mundo (giro "flat", de hélice) e Y é o comprimento do corpo (giro "barrel", de parafuso).
		if flying then
			local turn = math.pi * 2 * MOVE.dashRollTurns * math.clamp((now - dashStart) / MOVE.dashRollTime, 0, 1)
			spin *= if MOVE.dashRollStyle == "barrel" then CFrame.Angles(0, turn, 0) else CFrame.Angles(0, 0, turn)
		end
		Pose.define("flip", { Root = spin })

		-- passos: poeira sempre; correndo, um pisão a cada três passos
		if grounded and speed > 6 then
			stride += speed * dt
			local length = 4.5 + 3 * sprintAlpha
			if stride >= length then
				stride -= length
				steps += 1
				local feet = root.Position - Vector3.new(0, 2.9, 0)
				Fx.cubes(feet + Vector3.new(rng:NextNumber(-0.6, 0.6), 0.3, rng:NextNumber(-0.6, 0.6)), DUST, 2, 5, -velocity * 0.15 + Vector3.new(0, 5, 0), 0.45)
				if sprintAlpha > 0.7 and steps % 3 == 0 then
					stomp(feet, 6, 4)
				end
			end
		end

		-- riscos de vento passando pelo corpo em alta velocidade
		if speed > walk + 4 then
			windDebt += dt * (10 + (speed - walk) * 0.9)
			local back = -Vector3.new(velocity.X, 0, velocity.Z).Unit
			while windDebt >= 1 do
				windDebt -= 1
				local offset = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-2, 3.5), rng:NextNumber(-4, 4))
				Fx.streak(root.Position + offset - back * 6, back * (9 + speed * 0.15), Aura.color():Lerp(WHITE, 0.7), 2.5 + speed * 0.05, 0.22)
			end
		end
	end)
end

return Move
