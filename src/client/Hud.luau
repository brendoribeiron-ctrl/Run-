--!strict
-- HUD completo. Usa os objetos montados no plugin de UI quando existem (pelos nomes combinados:
-- Money, Power, ShopButton, SkillsButton, RebirthButton, IndexButton, DailyButton, PlaytimeButton,
-- VipButton, BoostLuckButton); o que faltar é criado aqui com o mesmo nome e estilo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CharacterModels = require(ReplicatedStorage.Shared.CharacterModels)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(script.Parent.Fx)
local Ui = require(script.Parent.Ui)

local P = Config.Palette
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Hud = {}

local gui: ScreenGui

local function ensureGui(): ScreenGui
	local existing = playerGui:FindFirstChild("HUD")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "HUD"
	created.ResetOnSpawn = false
	created.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	created.DisplayOrder = 10
	created.Parent = playerGui
	return created
end

function Hud.gui(): ScreenGui
	return gui
end

-- Liga um botão do HUD (pelo nome combinado, ex.: "SkillsButton") a uma ação.
local handlers: { [string]: () -> () } = {}
function Hud.onClick(name: string, handler: () -> ())
	handlers[name] = handler
end

---------------------------------------------------------------------------------------------------
-- Contadores: dígitos cheios enquanto o valor anda, curto em repouso

type Counter = {
	label: TextLabel,
	scale: UIScale,
	prefix: string,
	shown: number,
	from: number,
	target: number,
	started: number,
	rolling: boolean,
}

local ROLL_TIME = 0.45
local counters: { Counter } = {}

local function findLabel(object: Instance): TextLabel?
	if object:IsA("TextLabel") then
		return object
	end
	local named = object:FindFirstChild("Label", true)
	if named and named:IsA("TextLabel") then
		return named
	end
	return object:FindFirstChildWhichIsA("TextLabel", true)
end

local function makeCounter(object: Instance, prefix: string): Counter?
	local textLabel = findLabel(object)
	if not textLabel then
		return nil
	end
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = textLabel
	local counter: Counter = { label = textLabel, scale = scale, prefix = prefix, shown = 0, from = 0, target = 0, started = 0, rolling = false }
	table.insert(counters, counter)
	return counter
end

local function setCounter(counter: Counter, value: number, instant: boolean)
	if instant then
		counter.shown, counter.target, counter.rolling = value, value, false
		counter.label.Text = counter.prefix .. Format.abbreviate(value)
		return
	end
	if value == counter.target then
		return
	end
	counter.from = counter.shown
	counter.target = value
	counter.started = os.clock()
	counter.rolling = true
	counter.scale.Scale = 1.18
	TweenService:Create(counter.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function stepCounters()
	local now = os.clock()
	for _, counter in counters do
		if counter.rolling then
			local alpha = math.clamp((now - counter.started) / ROLL_TIME, 0, 1)
			counter.shown = counter.from + (counter.target - counter.from) * alpha
			if alpha >= 1 then
				counter.rolling = false
				counter.shown = counter.target
				counter.label.Text = counter.prefix .. Format.abbreviate(counter.target)
			else
				counter.label.Text = counter.prefix .. Format.commas(counter.shown)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Blocos criados em código

-- Botão quadrado com ícone e rótulo embaixo.
local function squareButton(parent: Instance, name: string, glyph: string, text: string, top: Color3, bottom: Color3, order: number): Frame
	local holder = Ui.frame(parent, name, UDim2.fromOffset(86, 104))
	holder.LayoutOrder = order
	local box = Ui.frame(holder, "Box", UDim2.fromOffset(78, 78), UDim2.fromOffset(4, 0), Ui.white)
	Ui.corner(box, 16)
	Ui.gradient(box, top, bottom)
	Ui.border(box, 4)
	local shine = Ui.frame(box, "Shine", UDim2.new(1, -14, 0.36, 0), UDim2.fromOffset(7, 6), Ui.white)
	shine.BackgroundTransparency = 0.7
	Ui.corner(shine, 10)
	Ui.text(box, { name = "Icon", text = glyph, size = UDim2.fromScale(0.72, 0.72), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), stroke = 3, z = 2 })
	Ui.text(holder, { name = "Label", text = text, size = UDim2.new(1, 8, 0, 24), position = UDim2.new(0.5, 0, 1, -26), anchor = Vector2.new(0.5, 0), textSize = 22, stroke = 3, z = 3 })
	local button = Ui.hit(holder, "Hit")
	Ui.juice(button, holder)
	button.Activated:Connect(function()
		local handler = handlers[name]
		if handler then
			handler()
		else
			Fx.toast(text .. ": COMING SOON!", P.yellowLine)
		end
	end)
	return holder
end

local function buildLeft(root: ScreenGui)
	local block = Ui.frame(root, "LeftButtons", UDim2.fromOffset(190, 220), UDim2.new(0, 14, 0.5, -40), nil, Vector2.new(0, 0.5))
	Ui.autoScale(block)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(86, 104)
	grid.CellPadding = UDim2.fromOffset(10, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = block

	local function ensure(name: string, glyph: string, text: string, top: Color3, bottom: Color3, order: number): Instance
		return root:FindFirstChild(name, true) or squareButton(block, name, glyph, text, top, bottom, order)
	end
	local shop = ensure("ShopButton", "🛒", "SHOP", Color3.fromRGB(255, 120, 110), Color3.fromRGB(215, 30, 40), 1)
	ensure("SkillsButton", "⭐", "SKILLS", Color3.fromRGB(120, 200, 255), Color3.fromRGB(30, 110, 235), 2)
	ensure("RebirthButton", "🔄", "REBIRTH", Color3.fromRGB(255, 160, 220), Color3.fromRGB(225, 50, 150), 3)
	ensure("IndexButton", "📖", "INDEX", Color3.fromRGB(130, 220, 255), Color3.fromRGB(40, 130, 240), 4)

	local box = shop:FindFirstChild("Box")
	if box then
		local ribbon = Ui.text(box, { name = "Sale", text = "SALE!", size = UDim2.fromOffset(52, 20), position = UDim2.fromOffset(-8, -6), textSize = 15, stroke = 2, z = 4 })
		ribbon.BackgroundTransparency = 0
		ribbon.BackgroundColor3 = P.red
		ribbon.Rotation = -14
		Ui.corner(ribbon, 6)
		Ui.border(ribbon, 2)
	end
end

local function statRow(parent: Instance, name: string, glyph: string, color: Color3, height: number, order: number): Frame
	local row = Ui.frame(parent, name, UDim2.fromOffset(330, height))
	row.LayoutOrder = order
	Ui.text(row, { name = "Icon", text = glyph, size = UDim2.fromOffset(height, height), stroke = 3 })
	Ui.text(row, { name = "Label", text = "0", color = color, size = UDim2.new(1, -(height + 6), 1, 0), position = UDim2.fromOffset(height + 6, 0), textSize = height - 4, stroke = 4, align = Enum.TextXAlignment.Left })
	return row
end

local function buildStats(root: ScreenGui): (Instance, Instance)
	local block = Ui.frame(root, "Stats", UDim2.fromOffset(330, 190), UDim2.new(0, 14, 1, -12), nil, Vector2.new(0, 1))
	Ui.autoScale(block)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Padding = UDim.new(0, 4)
	list.Parent = block

	if not root:FindFirstChild("BoostLuckButton", true) then
		local boost = Ui.frame(block, "BoostLuckButton", UDim2.fromOffset(300, 32))
		boost.LayoutOrder = 1
		Ui.text(boost, { name = "Label", text = "🍀 BOOST SERVER LUCK!", color = Color3.fromRGB(120, 255, 90), size = UDim2.fromScale(1, 1), textSize = 25, stroke = 4, align = Enum.TextXAlignment.Left })
		local button = Ui.hit(boost, "Hit")
		Ui.juice(button, boost)
		button.Activated:Connect(function()
			Fx.toast("SERVER LUCK: COMING SOON!", P.yellowLine)
		end)
	end

	local power = root:FindFirstChild("Power", true) or statRow(block, "Power", "👊", P.power, 42, 2)
	local money = root:FindFirstChild("Money", true) or statRow(block, "Money", "💰", P.money, 54, 3)

	local friend = Ui.frame(block, "FriendBoost", UDim2.fromOffset(300, 24))
	friend.LayoutOrder = 4
	Ui.text(friend, { name = "Label", text = "FRIEND BOOST +0%", size = UDim2.fromOffset(190, 24), textSize = 19, stroke = 3, align = Enum.TextXAlignment.Left })
	local bar = Ui.frame(friend, "Bar", UDim2.fromOffset(70, 10), UDim2.fromOffset(196, 8), Color3.fromRGB(30, 34, 54))
	Ui.corner(bar, 5)
	Ui.border(bar, 2)
	return power, money
end

local function buildTopRight(root: ScreenGui)
	local block = Ui.frame(root, "TopRight", UDim2.fromOffset(200, 250), UDim2.new(1, -14, 0, 8), nil, Vector2.new(1, 0))
	Ui.autoScale(block)

	local function iconButton(name: string, glyph: string, text: string, status: string, top: Color3, bottom: Color3, x: number, y: number, badge: boolean)
		if root:FindFirstChild(name, true) then
			return
		end
		local holder = squareButton(block, name, glyph, text, top, bottom, 0)
		holder.Position = UDim2.fromOffset(x, y)
		holder.Size = UDim2.fromOffset(86, 122)
		Ui.text(holder, { name = "Status", text = status, color = P.yellowLine, size = UDim2.new(1, 8, 0, 20), position = UDim2.new(0.5, 0, 1, -20), anchor = Vector2.new(0.5, 0), textSize = 18, stroke = 3, z = 3 })
		local caption = holder:FindFirstChild("Label") :: TextLabel
		caption.Position = UDim2.new(0.5, 0, 0, 76)
		if badge then
			Ui.badge(holder:FindFirstChild("Box") :: Instance)
		end
	end
	iconButton("DailyButton", "✅", "DAILY", "READY!", Color3.fromRGB(150, 255, 150), Color3.fromRGB(40, 190, 70), 10, 0, true)
	iconButton("PlaytimeButton", "🎁", "PLAYTIME", "4:59", Color3.fromRGB(255, 210, 120), Color3.fromRGB(240, 130, 30), 106, 0, true)
	iconButton("VipButton", "👑", "VIP", "R$ 399", Color3.fromRGB(255, 240, 130), Color3.fromRGB(245, 170, 20), 106, 128, false)
end

---------------------------------------------------------------------------------------------------
-- Hotbar: os 8 primeiros personagens do inventário

type Slot = { frame: Frame, viewport: ViewportFrame, name: TextLabel, border: UIStroke, scale: UIScale, id: string? }

local slots: { Slot } = {}
local hintLabel: TextLabel
local selectRemote: RemoteEvent

local function inventory(): { string }
	local raw = player:GetAttribute("Inventory")
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	return string.split(raw, ",")
end

local function refreshHotbar()
	local items = inventory()
	local selected = player:GetAttribute("Selected")
	for index, slot in slots do
		local id = items[index]
		if id ~= slot.id then
			slot.id = id
			local info = id and Config.CharacterById[id]
			if info then
				slot.frame.BackgroundColor3 = Config.Rarities[info.rarity].color
				slot.frame.BackgroundTransparency = 0.05
				slot.name.Text = info.name
				CharacterModels.render(slot.viewport, id :: string)
			else
				slot.frame.BackgroundColor3 = Color3.fromRGB(24, 28, 46)
				slot.frame.BackgroundTransparency = 0.25
				slot.name.Text = ""
				slot.viewport:ClearAllChildren()
			end
		end
		local active = selected == index and id ~= nil
		slot.border.Color = if active then Ui.white else P.outline
		slot.border.Thickness = if active then 4 else 3
		TweenService:Create(slot.scale, TweenInfo.new(0.12), { Scale = if active then 1.12 else 1 }):Play()
	end

	local chosen = if type(selected) == "number" then items[selected] else nil
	local info = chosen and Config.CharacterById[chosen]
	hintLabel.Text = if info then `Walk to an empty pedestal to place {info.name}` else ""
end

local function select(index: number)
	local current = player:GetAttribute("Selected")
	selectRemote:FireServer(if current == index then 0 else index)
end

local function buildHotbar(root: ScreenGui)
	local count = Config.Inventory.hotbarSlots
	local size, gap = 64, 6
	local block = Ui.frame(root, "Hotbar", UDim2.fromOffset(count * (size + gap), 132), UDim2.new(0.5, 0, 1, -10), nil, Vector2.new(0.5, 1))
	Ui.autoScale(block)
	hintLabel = Ui.text(block, { name = "Hint", text = "", color = P.yellowLine, size = UDim2.new(1, 300, 0, 24), position = UDim2.new(0.5, 0, 0, 0), anchor = Vector2.new(0.5, 0), textSize = 20, stroke = 3 })
	Ui.text(block, { name = "Backpack", text = "(G) Open Backpack", size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 40), textSize = 16, stroke = 2 })

	for index = 1, count do
		local frame = Ui.frame(block, "Slot" .. index, UDim2.fromOffset(size, size), UDim2.fromOffset((index - 1) * (size + gap) + gap / 2, 64), Color3.fromRGB(24, 28, 46))
		frame.BackgroundTransparency = 0.25
		Ui.corner(frame, 10)
		local border = Ui.border(frame, 3)
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Model"
		viewport.BackgroundTransparency = 1
		viewport.Size = UDim2.fromScale(1, 0.82)
		viewport.Parent = frame
		Ui.text(frame, { name = "Number", text = tostring(index), size = UDim2.fromOffset(16, 16), position = UDim2.fromOffset(4, 2), textSize = 14, stroke = 2, z = 3 })
		local name = Ui.text(frame, { name = "Name", text = "", size = UDim2.new(1, -4, 0, 20), position = UDim2.new(0, 2, 1, -21), stroke = 2, z = 3 })
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 12
		limit.Parent = name
		local button = Ui.hit(frame, "Hit")
		button.Activated:Connect(function()
			select(index)
		end)
		slots[index] = { frame = frame, viewport = viewport, name = name, border = border, scale = scale, id = nil }
	end

	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight }
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(keys, input.KeyCode)
		if index and index <= count then
			select(index)
		end
	end)

	player:GetAttributeChangedSignal("Inventory"):Connect(refreshHotbar)
	player:GetAttributeChangedSignal("Selected"):Connect(refreshHotbar)
	refreshHotbar()
end

---------------------------------------------------------------------------------------------------

function Hud.start()
	gui = ensureGui()
	selectRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Select") :: RemoteEvent

	-- a lista de jogadores e a mochila padrão ocupariam o espaço do HUD
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	buildLeft(gui)
	local power, money = buildStats(gui)
	buildTopRight(gui)
	buildHotbar(gui)

	local function bind(object: Instance, prefix: string, attribute: string)
		local counter = makeCounter(object, prefix)
		if not counter then
			warn(`[Hud] {attribute}: nenhum TextLabel encontrado`)
			return
		end
		local first = true
		local function refresh()
			local value = player:GetAttribute(attribute)
			if type(value) == "number" then
				setCounter(counter, value, first)
				first = false
			end
		end
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
		refresh()
	end
	bind(power, "", "Power")
	bind(money, "$", "Money")

	RunService.RenderStepped:Connect(stepCounters)
end

return Hud
