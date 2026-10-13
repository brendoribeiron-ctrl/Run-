--!strict
-- Mundos, do lado do cliente: a conversa com o feiticeiro da casa de feitiçaria (que guarda a
-- passagem para os outros mundos), o portal de volta, o corte para preto na viagem e a troca de
-- clima (céu, névoa e cor) quando o jogador está no vulcão. Quem decide se a viagem acontece é
-- o servidor: daqui só sai o pedido, pelo remote World.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Fx = require(script.Parent.Fx)
local Ui = require(script.Parent.Ui)

local W = Config.Wizard
local player = Players.LocalPlayer

local Worlds = {}

local remote: RemoteEvent
local panel: Frame
local speech: TextLabel
local accept: TextButton
local decline: TextButton
local scale: UIScale
local open = false
local typing = 0 -- muda a cada fala: a digitação antiga para sozinha
local talkedAt: Vector3? = nil

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local CYAN = rgb(110, 225, 255)

-- O próximo mundo que o feiticeiro oferece (por enquanto, só o segundo).
local function nextWorld(): any
	return Config.Worlds[2]
end

local function rebirths(): number
	local value = player:GetAttribute("Rebirths")
	return if type(value) == "number" then value else 0
end

function Worlds.worthy(): boolean
	return rebirths() >= nextWorld().rebirths
end

local function say(text: string)
	typing += 1
	local mine = typing
	speech.Text = text
	speech.MaxVisibleGraphemes = 0
	task.spawn(function()
		local total = utf8.len(text) or #text
		local shown = 0
		while mine == typing and shown < total do
			shown = math.min(shown + 2, total)
			speech.MaxVisibleGraphemes = shown
			task.wait(0.03)
		end
		if mine == typing then
			speech.MaxVisibleGraphemes = -1
		end
	end)
end

local function close()
	if not open then
		return
	end
	open = false
	typing += 1
	local tween = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
	tween.Completed:Connect(function()
		if not open then
			panel.Visible = false
		end
	end)
	tween:Play()
end

-- Abre a conversa. Sem os rebirths, ele despreza o jogador; com eles, oferece a viagem.
function Worlds.talk()
	local world = nextWorld()
	local have, need = rebirths(), world.rebirths
	local character = player.Character
	talkedAt = if character then character:GetPivot().Position else nil
	open = true
	panel.Visible = true
	scale.Scale = 0
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if have >= need then
		say(`So... the walls of this meadow no longer hold you. You have earned your passage, mortal. The {world.name} burns beyond my gate: step through whenever you wish.`)
		accept.Visible = true
		accept.Text = `TRAVEL TO THE {world.name}`
		decline.Text = "NOT NOW"
	else
		say(`Hmph. You? You are not worthy of the worlds beyond. The {world.name} would turn you to ash before your first step. Return when you have been reborn {need} times. ({have}/{need} rebirths)`)
		accept.Visible = false
		decline.Text = "I WILL RETURN"
	end
end

local function button(parent: Instance, name: string, color: Color3, position: UDim2, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.Size = size
	b.Position = position
	b.AnchorPoint = Vector2.new(1, 1)
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Ui.white
	b.TextScaled = true
	b.Text = name
	Ui.corner(b, 10)
	Ui.border(b, 3)
	Ui.stroke(b, 2.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 7)
	pad.PaddingBottom = UDim.new(0, 7)
	pad.Parent = b
	Ui.juice(b)
	b.Parent = parent
	return b
end

local function buildUi()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Worlds"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Parent = player:WaitForChild("PlayerGui")

	-- duas escalas: a de fora acompanha o tamanho da tela, a de dentro faz a caixa abrir e fechar
	local holder = Ui.frame(gui, "Holder", UDim2.fromOffset(700, 190), UDim2.new(0.5, 0, 0.8, 0), nil, Vector2.new(0.5, 1))
	Ui.autoScale(holder)
	panel = Ui.frame(holder, "Dialogue", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), rgb(22, 18, 54), Vector2.new(0.5, 0.5))
	panel.Visible = false
	Ui.corner(panel, 16)
	Ui.border(panel, 4, CYAN)
	Ui.gradient(panel, rgb(44, 34, 110), rgb(18, 14, 46))
	scale = Instance.new("UIScale")
	scale.Parent = panel

	local plate = Ui.frame(panel, "Name", UDim2.fromOffset(250, 40), UDim2.fromOffset(22, -20), rgb(104, 52, 200))
	Ui.corner(plate, 10)
	Ui.border(plate, 3, CYAN)
	Ui.text(plate, { text = W.name, size = UDim2.new(1, -16, 1, -8), position = UDim2.fromOffset(8, 4), stroke = 2.5 })

	speech = Ui.text(panel, { name = "Speech", text = "", size = UDim2.new(1, -44, 0, 96), position = UDim2.fromOffset(22, 28), textSize = 21, stroke = 2, align = Enum.TextXAlignment.Left })
	speech.TextWrapped = true
	speech.TextYAlignment = Enum.TextYAlignment.Top

	decline = button(panel, "Decline", rgb(96, 96, 130), UDim2.new(1, -18, 1, -14), UDim2.fromOffset(170, 44))
	accept = button(panel, "Accept", rgb(255, 110, 30), UDim2.new(1, -200, 1, -14), UDim2.fromOffset(300, 44))
	decline.MouseButton1Click:Connect(close)
	accept.MouseButton1Click:Connect(function()
		close()
		remote:FireServer(nextWorld().id)
	end)
end

---------------------------------------------------------------------------------------------------
-- Clima de cada mundo: só neste cliente, trocado quando o atributo World muda.

type Mood = { ambient: Color3, outdoor: Color3, brightness: number, haze: number, density: number, air: Color3, decay: Color3, glare: number, tint: Color3, saturation: number, contrast: number }
local moods: { [number]: Mood } = {}

local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function correction(): ColorCorrectionEffect?
	return Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
end

local function applyMood(id: number, time: number)
	local air, color = atmosphere(), correction()
	if not moods[1] then
		-- o clima do mundo 1 é o que o servidor montou: guarda para poder voltar
		moods[1] = {
			ambient = Lighting.Ambient,
			outdoor = Lighting.OutdoorAmbient,
			brightness = Lighting.Brightness,
			haze = if air then air.Haze else 0,
			density = if air then air.Density else 0,
			air = if air then air.Color else Ui.white,
			decay = if air then air.Decay else Ui.white,
			glare = if air then air.Glare else 0,
			tint = if color then color.TintColor else Ui.white,
			saturation = if color then color.Saturation else 0,
			contrast = if color then color.Contrast else 0,
		}
		moods[2] = { ambient = rgb(130, 70, 58), outdoor = rgb(150, 84, 66), brightness = 1.3, haze = 1.7, density = 0.3, air = rgb(255, 150, 96), decay = rgb(120, 40, 26), glare = 0.35, tint = rgb(255, 226, 206), saturation = 0.3, contrast = 0.14 }
	end
	local mood = moods[id] or moods[1]
	local info = TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, info, { Ambient = mood.ambient, OutdoorAmbient = mood.outdoor, Brightness = mood.brightness }):Play()
	if air then
		TweenService:Create(air, info, { Haze = mood.haze, Density = mood.density, Color = mood.air, Decay = mood.decay, Glare = mood.glare }):Play()
	end
	if color then
		TweenService:Create(color, info, { TintColor = mood.tint, Saturation = mood.saturation, Contrast = mood.contrast }):Play()
	end
end

local shown = 1
local function onWorld()
	local world = Config.worldOf(player)
	if world.id == shown then
		return
	end
	shown = world.id
	close()
	-- corte para preto cobrindo o salto e a chegada do mapa novo
	Fx.black(1, 0.12)
	task.delay(0.15, applyMood, world.id, 0.3)
	task.delay(0.9, function()
		Fx.black(0, 0.7)
		if shown == world.id then
			Fx.title(world.name, world.color, 1.8)
		end
	end)
end

-- Estado da conversa; usado pelos testes.
function Worlds.debug(): { [string]: any }
	return { open = open, text = speech.Text, travel = open and accept.Visible, world = shown, worthy = Worlds.worthy() }
end

-- Aperta o botão de viajar (teste).
function Worlds.accept()
	if open and accept.Visible then
		close()
		remote:FireServer(nextWorld().id)
	end
end

function Worlds.start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("World") :: RemoteEvent
	buildUi()

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "Wizard" then
			if open then
				close()
			else
				Worlds.talk()
			end
		elseif prompt.Name == "WorldPortal" then
			local target = prompt.Parent and prompt.Parent:GetAttribute("World")
			remote:FireServer(if type(target) == "number" then target else 1)
		end
	end)
	player:GetAttributeChangedSignal("World"):Connect(onWorld)

	-- o feiticeiro flutua: sobe e desce devagar e vira um pouco de um lado para o outro
	RunService.RenderStepped:Connect(function()
		local sanctum = workspace:FindFirstChild("Sanctum")
		local wizard = sanctum and sanctum:FindFirstChild("Wizard")
		if wizard and wizard:IsA("Model") then
			local home = wizard:GetAttribute("Home")
			if typeof(home) == "CFrame" then
				local t = os.clock()
				wizard:PivotTo(home * CFrame.new(0, math.sin(t * 1.5) * 0.35, 0) * CFrame.Angles(0, math.sin(t * 0.6) * 0.1, math.sin(t * 0.9) * 0.025))
			end
		end
		-- a conversa fecha quando o jogador se afasta
		if open and talkedAt then
			local character = player.Character
			if not character or (character:GetPivot().Position - talkedAt).Magnitude > 9 then
				close()
			end
		end
	end)
end

return Worlds
