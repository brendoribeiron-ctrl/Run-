--!strict
-- Painel de atributos (botão SKILLS do HUD): velocidade, chance e dano de crítico.
-- Mostra nível, efeito atual e preço; a compra é um pedido ao servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local P = Config.Palette
local player = Players.LocalPlayer

local Stats = {}

local window: Frame
local scale: UIScale
local open = false
local rows: { [string]: { level: TextLabel, effect: TextLabel, price: TextLabel, button: TextButton, fill: Frame } } = {}

local ICONS = { speed = "👟", critChance = "🎯", critDamage = "💥" }
local COLORS = { speed = Color3.fromRGB(60, 200, 255), critChance = Color3.fromRGB(255, 196, 46), critDamage = Color3.fromRGB(255, 90, 70) }

local function levelOf(name: string): number
	local value = player:GetAttribute("Stat_" .. name)
	return if type(value) == "number" then value else 0
end

local function effectText(name: string, level: number): string
	local stat = Config.Stats[name]
	if name == "speed" then
		return `{Config.Move.walk + level * stat.perLevel} walk speed`
	elseif name == "critChance" then
		return `{math.floor((Config.Crit.baseChance + level * stat.perLevel) * 100 + 0.5)}% crit chance`
	end
	return `x{Config.Crit.baseMultiplier + level * stat.perLevel} crit power`
end

local function refresh()
	local money = player:GetAttribute("Money")
	local cash = if type(money) == "number" then money else 0
	for name, row in rows do
		local stat = Config.Stats[name]
		local level = levelOf(name)
		local maxed = level >= stat.max
		local cost = Config.statCost(name, level)
		row.level.Text = `Lv {level}/{stat.max}`
		row.effect.Text = effectText(name, level)
		row.fill.Size = UDim2.fromScale(level / stat.max, 1)
		row.price.Text = if maxed then "MAX" else "$" .. Format.abbreviate(cost)
		row.button.BackgroundColor3 = if maxed then Color3.fromRGB(90, 96, 120) elseif cash >= cost then Color3.fromRGB(60, 210, 90) else Color3.fromRGB(190, 60, 60)
	end
end

local function setOpen(value: boolean)
	open = value
	if value then
		window.Visible = true
		refresh()
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		local tween = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.6 })
		tween.Completed:Connect(function()
			if not open then
				window.Visible = false
			end
		end)
		tween:Play()
	end
end

local function build(remote: RemoteEvent)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Windows"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	window = Ui.frame(gui, "Skills", UDim2.fromOffset(520, 400), UDim2.fromScale(0.5, 0.5), P.navy, Vector2.new(0.5, 0.5))
	window.Visible = false
	Ui.corner(window, 22)
	Ui.border(window, 6, P.cyan)
	scale = Instance.new("UIScale")
	scale.Parent = window

	local title = Ui.text(window, { name = "Title", text = "ATTRIBUTES", color = P.yellowLine, size = UDim2.fromOffset(300, 52), position = UDim2.new(0.5, 0, 0, -22), anchor = Vector2.new(0.5, 0), stroke = 5, z = 3 })
	title.BackgroundTransparency = 0
	title.BackgroundColor3 = P.red
	title.Rotation = -2
	Ui.corner(title, 12)
	Ui.border(title, 4)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -8, 0, 8)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = P.red
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 28
	close.TextColor3 = Ui.white
	close.Text = "X"
	close.ZIndex = 4
	Ui.corner(close, 12)
	Ui.border(close, 4)
	Ui.juice(close)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	close.Parent = window

	for index, name in Config.StatOrder do
		local stat = Config.Stats[name]
		local row = Ui.frame(window, name, UDim2.new(1, -36, 0, 96), UDim2.fromOffset(18, 44 + (index - 1) * 110), Color3.fromRGB(32, 40, 74))
		Ui.corner(row, 14)
		Ui.border(row, 3)

		local icon = Ui.text(row, { name = "Icon", text = ICONS[name], size = UDim2.fromOffset(64, 64), position = UDim2.fromOffset(12, 16), stroke = 3 })
		icon.BackgroundTransparency = 0
		icon.BackgroundColor3 = COLORS[name]
		Ui.corner(icon, 14)
		Ui.border(icon, 3)

		Ui.text(row, { name = "Name", text = stat.label, color = COLORS[name], size = UDim2.fromOffset(220, 30), position = UDim2.fromOffset(88, 8), textSize = 26, stroke = 3, align = Enum.TextXAlignment.Left })
		local level = Ui.text(row, { name = "Level", text = "Lv 0", size = UDim2.fromOffset(110, 24), position = UDim2.fromOffset(250, 12), textSize = 19, stroke = 3, align = Enum.TextXAlignment.Left })
		local effect = Ui.text(row, { name = "Effect", text = "", color = Color3.fromRGB(200, 215, 255), size = UDim2.fromOffset(250, 22), position = UDim2.fromOffset(88, 40), textSize = 18, stroke = 2, align = Enum.TextXAlignment.Left })
		local bar = Ui.frame(row, "Bar", UDim2.fromOffset(250, 12), UDim2.fromOffset(88, 70), Color3.fromRGB(12, 14, 26))
		Ui.corner(bar, 6)
		Ui.border(bar, 2)
		local fill = Ui.frame(bar, "Fill", UDim2.fromScale(0, 1), nil, COLORS[name])
		Ui.corner(fill, 6)

		local button = Instance.new("TextButton")
		button.Name = "Buy"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -12, 0.5, 0)
		button.Size = UDim2.fromOffset(120, 64)
		button.BackgroundColor3 = Color3.fromRGB(60, 210, 90)
		button.Text = ""
		button.AutoButtonColor = false
		Ui.corner(button, 14)
		Ui.border(button, 4)
		Ui.juice(button)
		Ui.text(button, { name = "Action", text = "UPGRADE", size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 8), textSize = 18, stroke = 3 })
		local price = Ui.text(button, { name = "Price", text = "$0", color = P.yellowLine, size = UDim2.new(1, 0, 0, 26), position = UDim2.fromOffset(0, 30), textSize = 22, stroke = 3 })
		button.Activated:Connect(function()
			remote:FireServer(name)
		end)
		button.Parent = row

		rows[name] = { level = level, effect = effect, price = price, button = button, fill = fill }
	end

	-- escala a janela inteira em telas pequenas
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	local wrapper = Ui.frame(gui, "Fit", UDim2.fromScale(1, 1))
	window.Parent = wrapper
	local camera = workspace.CurrentCamera
	local function resize()
		local view = camera.ViewportSize
		fit.Scale = math.min(1.1, view.Y / 520, view.X / 600)
	end
	fit.Parent = wrapper
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	resize()
	wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapper.Position = UDim2.fromScale(0.5, 0.5)
end

function Stats.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Stat") :: RemoteEvent
	build(remote)

	Hud.onClick("SkillsButton", function()
		setOpen(not open)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.K then
			setOpen(not open)
		end
	end)

	local function onChange()
		if open then
			refresh()
		end
	end
	player:GetAttributeChangedSignal("Money"):Connect(onChange)
	for name in Config.Stats do
		player:GetAttributeChangedSignal("Stat_" .. name):Connect(onChange)
	end
end

return Stats
