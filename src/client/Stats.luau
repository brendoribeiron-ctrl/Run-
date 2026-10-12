--!strict
-- Painel de atributos (botão SKILLS do HUD): velocidade, chance e dano de crítico.
-- Mostra nível, efeito atual e preço; a compra é um pedido ao servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local P = Config.Palette
local player = Players.LocalPlayer

local Stats = {}

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

local function build(remote: RemoteEvent)
	local window = Windows.create("Skills", "ATTRIBUTES", Vector2.new(520, 400), P.cyan, refresh)

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

end

function Stats.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Stat") :: RemoteEvent
	build(remote)

	Hud.onClick("SkillsButton", function()
		Windows.toggle("Skills")
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.K then
			Windows.toggle("Skills")
		end
	end)

	local function onChange()
		if Windows.isOpen("Skills") then
			refresh()
		end
	end
	player:GetAttributeChangedSignal("Money"):Connect(onChange)
	for name in Config.Stats do
		player:GetAttributeChangedSignal("Stat_" .. name):Connect(onChange)
	end
end

return Stats
