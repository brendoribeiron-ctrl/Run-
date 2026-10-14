--!strict
-- Efeitos dos OUTROS jogadores. Tudo o que o cliente desenha (impacto do soco, crítico, super
-- soco, dash, pulo duplo) só existe na tela de quem fez; aqui chegam os avisos do servidor
-- (remote Fx: "hitOther", "superOther", "castOther") e o efeito é refeito no boneco ou no saco
-- do outro jogador. São versões mais leves: sem clarão na tela, sem tremer a câmera e sem
-- letreiro, para o jogo dos outros não atrapalhar o seu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Aura = require(script.Parent.Aura)
local Fx = require(script.Parent.Fx)

local P = Config.Palette
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 40)
local DIRT = Color3.fromRGB(122, 84, 52)
local RANGE = 260 -- studs: mais longe que isto, o efeito nem é montado

local Others = {}
local shown = 0 -- quantos efeitos já foram mostrados (para os testes)

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function bagOf(player: Player): Vector3?
	local plot = Config.plotOf(player)
	local gantry = plot and plot:FindFirstChild("Gantry")
	local bag = gantry and gantry:FindFirstChild("Bag")
	local center = bag and bag:GetAttribute("Center")
	return if typeof(center) == "Vector3" then center else nil
end

local function near(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < RANGE
end

-- Número subindo em cima do saco do outro jogador (menor que o seu).
local function floatNumber(at: Vector3, text: string, color: Color3, big: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = at + Vector3.new(math.random(-15, 15) / 10, 2.5, math.random(-15, 15) / 10)
	local board = Instance.new("BillboardGui")
	board.Size = if big then UDim2.fromScale(8, 3.2) else UDim2.fromScale(3.6, 1.6)
	board.MaxDistance = 140
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Rotation = math.random(-12, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if big then 5 else 3
	stroke.Color = P.outline
	stroke.Parent = label
	label.Parent = board
	anchor.Parent = workspace.CurrentCamera
	local hold = if big then 0.7 else 0.35
	TweenService:Create(board, TweenInfo.new(hold + 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, if big then 5 else 3.5, 0) }):Play()
	local fade = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(hold + 0.35, anchor.Destroy, anchor)
end

-- Direção do soco: do boneco para o saco.
local function aim(player: Player, center: Vector3): (Vector3, Vector3)
	local root = rootOf(player)
	local flat = if root then Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z) else Vector3.xAxis
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
	local floor = Vector3.new(center.X, if root then root.Position.Y - 2.8 else center.Y - 7, center.Z)
	return dir, floor
end

local function hit(player: Player, gain: number, crit: boolean)
	local center = bagOf(player)
	if not center or not near(center) then
		return
	end
	shown += 1
	local dir, floor = aim(player, center)
	local color = Aura.colorOf(player)
	local bright = color:Lerp(WHITE, 0.45)
	local front, back = center - dir * 1.8, center + dir * 1.8
	floatNumber(center, if crit then `CRIT! +{Format.abbreviate(gain)}` else `+{Format.abbreviate(gain)}`, if crit then GOLD else P.hitNumber, crit)
	Fx.star(front, -dir, WHITE, 6, 3, 0.2)
	Fx.shock(back, dir, bright, 9, 0.28)
	Fx.burst(back, color, 5, 0.25)
	Fx.cubes(back, color, 3, 12, dir * 30, 0.6, Enum.Material.Neon)
	if crit then
		Fx.star(front, -dir, GOLD, 22, 2, 0.4)
		Fx.shock(back, dir, GOLD, 18, 0.32)
		Fx.burst(center, GOLD, 17, 0.35)
		Fx.ring(floor, GOLD, 38, 0.5)
		Fx.cubes(back, GOLD, 10, 26, dir * 44 + Vector3.new(0, 14, 0), 1, Enum.Material.Neon)
		for i = 1, 8 do
			local around = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, i * math.pi / 4) * Vector3.yAxis
			Fx.streak(center + around * 1.5, around * 13 + dir * 4, GOLD:Lerp(WHITE, 0.5), 5, 0.38)
		end
	end
end

local function super(player: Player, gain: number)
	local center = bagOf(player)
	if not center or not near(center) then
		return
	end
	shown += 1
	local dir, floor = aim(player, center)
	local front, back = center - dir * 1.8, center + dir * 1.8
	floatNumber(center, `SUPER! +{Format.abbreviate(gain)}`, GOLD, true)
	Fx.star(front, -dir, GOLD, 40, 3, 0.55)
	Fx.burst(center, WHITE, 30, 0.35)
	task.delay(0.1, Fx.burst, center, GOLD, 46, 0.5)
	for i = 0, 3 do
		task.delay(i * 0.07, Fx.shock, back + dir * (i * 5), dir, if i % 2 == 0 then GOLD else WHITE, 22 + i * 14, 0.4 + i * 0.06)
	end
	for i = 0, 2 do
		task.delay(i * 0.11, Fx.ring, floor + Vector3.new(0, 0.2, 0), if i % 2 == 0 then GOLD else WHITE, 46 + i * 34, 0.55)
	end
	Fx.cubes(back, GOLD, 20, 40, dir * 70 + Vector3.new(0, 22, 0), 1.3, Enum.Material.Neon)
	Fx.cubes(floor + Vector3.new(0, 1, 0), DIRT, 12, 30, Vector3.new(0, 34, 0), 1.6)
	local character = player.Character
	if character then
		for i = 0, 2 do
			task.delay(i * 0.05, Fx.ghost, character, GOLD, 0.45)
		end
	end
end

-- Dash e pulo duplo: saem do cliente do outro jogador e o servidor repassa.
local function cast(player: Player, kind: string)
	local root = rootOf(player)
	if not root or not near(root.Position) then
		return
	end
	shown += 1
	local color = Aura.colorOf(player)
	if kind == "dash" then
		local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		local dir = if velocity.Magnitude > 2 then velocity.Unit else (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
		local feet = root.Position - Vector3.new(0, 2.8, 0)
		Fx.shock(root.Position, -dir, color:Lerp(WHITE, 0.4), 14, 0.3)
		for i = 1, 4 do
			Fx.burst(root.Position - dir * (1 + i * 0.5), WHITE, 3 + i * 0.5, 0.3)
		end
		Fx.ring(feet, color, 16, 0.3)
		local character = player.Character
		if character then
			for i = 0, 3 do
				task.delay(i * 0.05, Fx.ghost, character, color:Lerp(WHITE, 0.3), 0.3)
			end
		end
	elseif kind == "jump" then
		local below = root.Position - Vector3.new(0, 2.6, 0)
		Fx.ring(below, color:Lerp(WHITE, 0.4), 15, 0.35)
		Fx.burst(below, WHITE, 6, 0.25)
		for i = 1, 8 do
			local angle = i * math.pi / 4
			Fx.streak(below + Vector3.new(math.cos(angle) * 1.5, 0, math.sin(angle) * 1.5), Vector3.new(math.cos(angle) * 5, -7, math.sin(angle) * 5), color:Lerp(WHITE, 0.5), 2.5, 0.3)
		end
	end
end

-- Para os testes: mostra um efeito como se o jogador local fosse "outro".
function Others.preview(kind: string): number
	local me = Players.LocalPlayer
	if kind == "hit" then
		hit(me, 12, false)
	elseif kind == "crit" then
		hit(me, 36, true)
	elseif kind == "super" then
		super(me, 480)
	else
		cast(me, kind)
	end
	return shown
end

function Others.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: string, who: any, a: any, b: any)
		if typeof(who) ~= "Instance" or not who:IsA("Player") or who == Players.LocalPlayer then
			return
		end
		if kind == "hitOther" then
			hit(who, a, b == true)
		elseif kind == "superOther" then
			super(who, a)
		elseif kind == "castOther" then
			cast(who, a)
		end
	end)
end

return Others
