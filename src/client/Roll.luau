--!strict
-- Roleta de cartas e carta do resultado. É só animação: o personagem já veio sorteado do servidor.
-- Tempos: roleta 2,0 s desacelerando, segura 0,6 s; carta: raios, modelo aos 0,5 s, segura 2,5 s,
-- encolhe para o hotbar em 0,3 s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CharacterModels = require(ReplicatedStorage.Shared.CharacterModels)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(script.Parent.Fx)
local Ui = require(script.Parent.Ui)

local P = Config.Palette
local player = Players.LocalPlayer

local Roll = {}

local CARD_W, CARD_H, GAP = 150, 190, 12
local STEP = CARD_W + GAP
local VISIBLE = 5
local CARDS = 34
local RESULT_INDEX = 30
local DARK = Color3.fromRGB(22, 24, 40)

local playing = false
local gui: ScreenGui

local function ease(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
end

function Roll.isPlaying(): boolean
	return playing
end

local function ensureGui(): ScreenGui
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "Roll"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function spinReel(root: Frame, rarityColor: Color3)
	local title = Ui.text(root, { name = "Title", text = "ROLLING...", size = UDim2.fromOffset(500, 56), position = UDim2.new(0.5, 0, 0.5, -CARD_H / 2 - 70), anchor = Vector2.new(0.5, 0.5), stroke = 5 })

	local reel = Ui.frame(root, "Reel", UDim2.fromOffset(VISIBLE * STEP, CARD_H + 20), UDim2.fromScale(0.5, 0.5), nil, Vector2.new(0.5, 0.5))
	reel.ClipsDescendants = true
	local strip = Ui.frame(reel, "Strip", UDim2.fromOffset(CARDS * STEP, CARD_H), UDim2.fromOffset(0, 10))
	for i = 1, CARDS do
		local card = Ui.frame(strip, "Card" .. i, UDim2.fromOffset(CARD_W, CARD_H), UDim2.fromOffset((i - 1) * STEP + GAP / 2, 0), DARK)
		Ui.corner(card, 14)
		Ui.border(card, 3, Color3.fromRGB(60, 66, 100))
		Ui.text(card, { name = "Mark", text = "?", color = Color3.fromRGB(90, 98, 140), size = UDim2.fromScale(0.6, 0.6), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), stroke = 0 })
	end

	-- moldura do slot central e risco vermelho que pisca a cada carta que passa
	local outline = Ui.frame(root, "Center", UDim2.fromOffset(CARD_W + 10, CARD_H + 10), UDim2.fromScale(0.5, 0.5), nil, Vector2.new(0.5, 0.5))
	Ui.corner(outline, 16)
	local outlineStroke = Ui.border(outline, 5, Ui.white)
	local tick = Ui.frame(root, "Tick", UDim2.fromOffset(4, CARD_H + 44), UDim2.fromScale(0.5, 0.5), P.red, Vector2.new(0.5, 0.5))
	tick.BackgroundTransparency = 1

	local middle = (VISIBLE + 1) / 2
	local target = (middle - RESULT_INDEX) * STEP
	local tween = TweenService:Create(strip, ease(2, Enum.EasingStyle.Quint), { Position = UDim2.fromOffset(target, 10) })
	local lastCard = 0
	local watcher = RunService.RenderStepped:Connect(function()
		local passed = math.floor(-strip.Position.X.Offset / STEP)
		if passed ~= lastCard then
			lastCard = passed
			tick.BackgroundTransparency = 0
			TweenService:Create(tick, ease(0.12), { BackgroundTransparency = 1 }):Play()
		end
	end)
	tween:Play()
	tween.Completed:Wait()
	watcher:Disconnect()

	title.Text = "YOU GOT"
	outlineStroke.Color = rarityColor
	outlineStroke.Thickness = 7
	Fx.shake(0.3)
	task.wait(0.6)
	title:Destroy()
	reel:Destroy()
	outline:Destroy()
	tick:Destroy()
end

local function showCard(root: Frame, dim: Frame, characterId: string, isNew: boolean)
	local info = Config.CharacterById[characterId]
	local rarity = Config.Rarities[info.rarity]

	TweenService:Create(dim, ease(0.3), { BackgroundTransparency = 1 }):Play()
	local card = Ui.frame(root, "Result", UDim2.fromOffset(330, 450), UDim2.fromScale(0.5, 0.5), DARK, Vector2.new(0.5, 0.5))
	Ui.corner(card, 22)
	Ui.border(card, 9, rarity.color)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = card

	-- raios girando atrás do personagem
	local burstClip = Ui.frame(card, "BurstClip", UDim2.new(1, -20, 0, 270), UDim2.fromOffset(10, 56))
	burstClip.ClipsDescendants = true
	local burst = Ui.frame(burstClip, "Burst", UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.55), nil, Vector2.new(0.5, 0.5))
	-- a rotação de GUI gira pelo centro: cada barra atravessa o meio e vale por dois raios
	for i = 1, 8 do
		local ray = Ui.frame(burst, "Ray", UDim2.fromOffset(640, 18), UDim2.fromScale(0.5, 0.5), P.cyan, Vector2.new(0.5, 0.5))
		ray.Rotation = i * (180 / 8)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = ray
	end
	local burstScale = Instance.new("UIScale")
	burstScale.Scale = 0
	burstScale.Parent = burst
	local spin = RunService.RenderStepped:Connect(function(dt)
		burst.Rotation += dt * 40
	end)

	Ui.text(card, { name = "Top", text = "YOU GOT", size = UDim2.new(1, 0, 0, 40), position = UDim2.fromOffset(0, 12), textSize = 34, stroke = 4, z = 4 })
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Model"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, -30, 0, 260)
	viewport.Position = UDim2.fromOffset(15, 60)
	viewport.ZIndex = 3
	viewport.Parent = card
	local modelScale = Instance.new("UIScale")
	modelScale.Scale = 0
	modelScale.Parent = viewport

	Ui.text(card, { name = "Name", text = info.name, size = UDim2.new(1, -20, 0, 40), position = UDim2.fromOffset(10, 322), stroke = 4, z = 4 })
	local strip = Ui.text(card, { name = "Rarity", text = string.upper(rarity.id), size = UDim2.new(1, -60, 0, 30), position = UDim2.fromOffset(30, 366), textSize = 24, stroke = 3, z = 4 })
	strip.BackgroundTransparency = 0
	strip.BackgroundColor3 = rarity.color
	Ui.corner(strip, 8)
	Ui.text(card, { name = "Income", text = `${Format.abbreviate(info.income)}/s`, color = P.money, size = UDim2.new(1, 0, 0, 38), position = UDim2.fromOffset(0, 402), textSize = 34, stroke = 4, z = 4 })

	if isNew then
		local tag = Ui.text(card, { name = "NewTag", text = "NEW!", color = Color3.fromRGB(60, 40, 0), size = UDim2.fromOffset(104, 40), position = UDim2.new(1, -50, 0, 6), anchor = Vector2.new(0.5, 0.5), textSize = 28, stroke = 0, z = 6 })
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = P.yellowLine
		tag.Rotation = 14
		Ui.corner(tag, 8)
		Ui.border(tag, 4)
	end

	Fx.flash(rarity.color, 0.5, 0.3)
	TweenService:Create(scale, ease(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(burstScale, ease(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.wait(0.5)
	CharacterModels.render(viewport, characterId)
	TweenService:Create(modelScale, ease(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	if info.rarity >= 4 then
		Fx.shake(0.4)
		Fx.title(string.upper(rarity.id) .. "!", rarity.color, 1)
	end
	task.wait(2.5)

	-- encolhe em direção ao hotbar
	TweenService:Create(card, ease(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 1.05) }):Play()
	TweenService:Create(scale, ease(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.1 }):Play()
	task.wait(0.3)
	spin:Disconnect()
end

function Roll.play(characterId: string, isNew: boolean)
	if playing or not Config.CharacterById[characterId] then
		return
	end
	playing = true
	local screen = ensureGui()
	local dim = Ui.frame(screen, "Dim", UDim2.fromScale(1, 1), nil, Color3.new(0, 0, 0))
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, ease(0.2), { BackgroundTransparency = 0.5 }):Play()
	local root = Ui.frame(screen, "Root", UDim2.fromScale(1, 1))

	local rarityColor = Config.Rarities[Config.CharacterById[characterId].rarity].color
	local ok, err = pcall(function()
		spinReel(root, rarityColor)
		showCard(root, dim, characterId, isNew)
	end)
	if not ok then
		warn("[Roll] " .. tostring(err))
	end
	root:Destroy()
	dim:Destroy()
	playing = false
end

return Roll
