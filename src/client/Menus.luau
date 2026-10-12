--!strict
-- Janelas abertas pelos botões do HUD: mochila (tecla G ou botão acima do hotbar), SHOP,
-- REBIRTH, INDEX, DAILY e PLAYTIME. Mochila e índice mostram dados reais (atributos Inventory
-- e Index); loja, rebirth, daily e playtime são só o layout, sem regra no servidor ainda.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CharacterModels = require(ReplicatedStorage.Shared.CharacterModels)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Auto = require(script.Parent.Auto)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Move = require(script.Parent.Move)
local Pose = require(script.Parent.Pose)
local Run = require(script.Parent.Run)
local Super = require(script.Parent.Super)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local P = Config.Palette
local player = Players.LocalPlayer

local Menus = {}

local CARD = Color3.fromRGB(32, 40, 74)
local MUTED = Color3.fromRGB(200, 215, 255)
local EMPTY = Color3.fromRGB(24, 28, 46)

local function list(attribute: string): { string }
	local raw = player:GetAttribute(attribute)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	return string.split(raw, ",")
end

local function soon(what: string)
	Fx.toast(what .. ": COMING SOON!", P.yellowLine)
end

-- Área rolável com grade, ocupando a janela abaixo de `top` e acima de `bottom`.
local function gridArea(window: Frame, top: number, bottom: number, cell: Vector2): ScrollingFrame
	local area = Instance.new("ScrollingFrame")
	area.Name = "Grid"
	area.BackgroundTransparency = 1
	area.BorderSizePixel = 0
	area.Position = UDim2.fromOffset(18, top)
	area.Size = UDim2.new(1, -36, 1, -(top + bottom))
	area.CanvasSize = UDim2.new()
	area.AutomaticCanvasSize = Enum.AutomaticSize.Y
	area.ScrollingDirection = Enum.ScrollingDirection.Y
	area.ScrollBarThickness = 8
	area.ScrollBarImageColor3 = P.cyan
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = area
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = area
	area.Parent = window
	return area
end

local function card(parent: Instance, name: string, order: number, color: Color3?): (Frame, UIStroke)
	local frame = Ui.frame(parent, name, UDim2.new(), nil, color or CARD)
	frame.LayoutOrder = order
	Ui.corner(frame, 12)
	return frame, Ui.border(frame, 3)
end

local function fitted(parent: Instance, name: string, text: string, y: number, height: number, max: number, color: Color3?): TextLabel
	local t = Ui.text(parent, { name = name, text = text, color = color, size = UDim2.new(1, -6, 0, height), position = UDim2.fromOffset(3, y), stroke = 2, z = 3 })
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.Parent = t
	return t
end

local function viewportIn(parent: Instance, height: number): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Model"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, 0, 0, height)
	viewport.Parent = parent
	return viewport
end

-- Botão largo no rodapé da janela.
local function footerButton(window: Frame, text: string, color: Color3, action: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -16)
	button.Size = UDim2.fromOffset(240, 54)
	button.BackgroundColor3 = color
	button.Text = ""
	button.AutoButtonColor = false
	Ui.corner(button, 14)
	Ui.border(button, 4)
	Ui.juice(button)
	Ui.text(button, { name = "Label", text = text, size = UDim2.fromScale(1, 1), textSize = 26, stroke = 3 })
	button.Activated:Connect(action)
	button.Parent = window
	return button
end

---------------------------------------------------------------------------------------------------
-- Mochila: o inventário inteiro (o hotbar mostra só os primeiros). Clicar escolhe o personagem.

local backpackCells: { { border: UIStroke, scale: UIScale } } = {}
local backpackShown: string? = nil
local backpackGrid: ScrollingFrame
local backpackCount: TextLabel
local backpackEmpty: TextLabel

local function refreshBackpack()
	if not Windows.isOpen("Backpack") then
		return
	end
	local raw = player:GetAttribute("Inventory")
	local items = list("Inventory")
	if raw ~= backpackShown then
		backpackShown = if type(raw) == "string" then raw else ""
		for _, child in backpackGrid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(backpackCells)
		for index, id in items do
			local info = Config.CharacterById[id]
			if not info then
				continue
			end
			local frame, border = card(backpackGrid, "Item" .. index, index, Config.Rarities[info.rarity].color)
			CharacterModels.render(viewportIn(frame, 76), id)
			fitted(frame, "Name", info.name, 76, 30, 14)
			if index <= Config.Inventory.hotbarSlots then
				-- os primeiros são os slots rápidos (teclas 1 a 8)
				Ui.text(frame, { name = "Slot", text = tostring(index), color = P.yellowLine, size = UDim2.fromOffset(22, 22), position = UDim2.fromOffset(4, 2), textSize = 18, stroke = 3, z = 4 })
			end
			local scale = Instance.new("UIScale")
			scale.Parent = frame
			local button = Ui.hit(frame, "Hit")
			button.Activated:Connect(function()
				Hud.select(index)
			end)
			backpackCells[index] = { border = border, scale = scale }
		end
		backpackCount.Text = `{#items}/{Config.Inventory.maxItems}`
		backpackEmpty.Visible = #items == 0
	end
	local selected = player:GetAttribute("Selected")
	for index, cell in backpackCells do
		local active = selected == index
		cell.border.Color = if active then Ui.white else P.outline
		cell.border.Thickness = if active then 5 else 3
		cell.scale.Scale = if active then 1.06 else 1
	end
end

local function buildBackpack()
	local window = Windows.create("Backpack", "BACKPACK", Vector2.new(640, 440), P.cyan, refreshBackpack)
	backpackCount = Ui.text(window, { name = "Count", text = "0/0", color = MUTED, size = UDim2.fromOffset(120, 24), position = UDim2.fromOffset(22, 14), textSize = 20, stroke = 3, align = Enum.TextXAlignment.Left })
	backpackGrid = gridArea(window, 44, 72, Vector2.new(92, 110))
	-- barra de slots rápidos: escolha um personagem e clique no número para colocá-lo ali
	local slotRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Slot") :: RemoteEvent
	local bar = Ui.frame(window, "Slots", UDim2.new(1, -36, 0, 48), UDim2.new(0, 18, 1, -60))
	Ui.text(bar, { name = "Label", text = "PUT SELECTED IN SLOT", color = MUTED, size = UDim2.fromOffset(210, 48), textSize = 17, stroke = 2, align = Enum.TextXAlignment.Left })
	for slot = 1, Config.Inventory.hotbarSlots do
		local button = Instance.new("TextButton")
		button.Name = "Slot" .. slot
		button.Position = UDim2.fromOffset(214 + (slot - 1) * 48, 3)
		button.Size = UDim2.fromOffset(42, 42)
		button.BackgroundColor3 = EMPTY
		button.Font = Enum.Font.FredokaOne
		button.TextSize = 24
		button.TextColor3 = P.yellowLine
		button.Text = tostring(slot)
		button.AutoButtonColor = false
		Ui.corner(button, 10)
		Ui.border(button, 3)
		Ui.juice(button)
		button.Activated:Connect(function()
			local selected = player:GetAttribute("Selected")
			if type(selected) == "number" and selected >= 1 then
				slotRemote:FireServer(selected, slot)
			else
				Fx.toast("Pick a character first!", P.yellowLine)
			end
		end)
		button.Parent = bar
	end
	backpackEmpty = Ui.text(window, { name = "Empty", text = "No characters yet. Run the hallway to get one!", color = MUTED, size = UDim2.new(1, -60, 0, 30), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), textSize = 22, stroke = 3 })
	player:GetAttributeChangedSignal("Inventory"):Connect(refreshBackpack)
	player:GetAttributeChangedSignal("Selected"):Connect(refreshBackpack)
end

---------------------------------------------------------------------------------------------------
-- Auras: liberam com Poder; a equipada multiplica um pouco todo ganho de Poder.

local auraCards: { [string]: { frame: Frame, status: TextLabel, border: UIStroke } } = {}

local function refreshAuras()
	if not Windows.isOpen("Auras") then
		return
	end
	local raw = player:GetAttribute("Power")
	local power = if type(raw) == "number" then raw else 0
	local equipped = player:GetAttribute("Aura")
	for _, info in Config.Auras do
		local entry = auraCards[info.id]
		local unlocked = power >= info.power
		local on = equipped == info.id
		entry.status.Text = if on then "EQUIPPED" elseif unlocked then "EQUIP" else `🔒 {Format.abbreviate(info.power)} POWER`
		entry.status.TextColor3 = if on then P.money elseif unlocked then Ui.white else MUTED
		entry.border.Color = if on then Ui.white else P.outline
		entry.border.Thickness = if on then 5 else 3
		entry.frame.BackgroundColor3 = if unlocked then CARD else EMPTY
	end
end

local function buildAuras()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Aura") :: RemoteEvent
	local window = Windows.create("Auras", "AURAS", Vector2.new(640, 460), Color3.fromRGB(170, 110, 255), refreshAuras)
	Ui.text(window, { name = "Help", text = "Reach the Power to unlock. The equipped aura boosts all Power you gain.", color = MUTED, size = UDim2.new(1, -40, 0, 22), position = UDim2.fromOffset(20, 46), textSize = 16, stroke = 2 })
	local grid = gridArea(window, 72, 18, Vector2.new(138, 168))
	for order, info in Config.Auras do
		local frame, border = card(grid, info.id, order)
		local orb = Ui.frame(frame, "Orb", UDim2.fromOffset(62, 62), UDim2.new(0.5, 0, 0, 12), info.color, Vector2.new(0.5, 0))
		Ui.corner(orb, 31)
		Ui.border(orb, 4, Ui.white)
		local glow = Ui.frame(orb, "Glow", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5), Ui.white, Vector2.new(0.5, 0.5))
		glow.BackgroundTransparency = 0.45
		Ui.corner(glow, 16)
		fitted(frame, "Name", info.name, 80, 24, 20, info.color)
		fitted(frame, "Bonus", `x{info.multiplier} POWER`, 106, 22, 17, P.power)
		local status = fitted(frame, "Status", "", 134, 24, 16)
		local button = Ui.hit(frame, "Hit")
		Ui.juice(button, frame)
		button.Activated:Connect(function()
			remote:FireServer(info.id)
		end)
		auraCards[info.id] = { frame = frame, status = status, border = border }
	end
	player:GetAttributeChangedSignal("Power"):Connect(refreshAuras)
	player:GetAttributeChangedSignal("Aura"):Connect(refreshAuras)
end

---------------------------------------------------------------------------------------------------
-- Índice: todos os personagens do Config; os que ainda não saíram ficam em silhueta.

type IndexCard = { frame: Frame, viewport: ViewportFrame, name: TextLabel, income: TextLabel, found: boolean? }

local indexCards: { [string]: IndexCard } = {}
local indexCount: TextLabel
local indexFound = 0

local function refreshIndex()
	if not Windows.isOpen("Index") then
		return
	end
	local found: { [string]: boolean } = {}
	for _, id in list("Index") do
		found[id] = true
	end
	indexFound = 0
	for _, info in Config.Characters do
		local entry = indexCards[info.id]
		local has = found[info.id] == true
		if has then
			indexFound += 1
		end
		if entry.found ~= has then
			entry.found = has
			entry.frame.BackgroundColor3 = if has then Config.Rarities[info.rarity].color else EMPTY
			entry.viewport.ImageColor3 = if has then Ui.white else Color3.new(0, 0, 0)
			entry.name.Text = if has then info.name else "???"
			entry.income.Text = if has then `${Format.abbreviate(info.income)}/s` else "?"
		end
	end
	indexCount.Text = `{indexFound}/{#Config.Characters} FOUND`
end

local function buildIndex()
	local window = Windows.create("Index", "INDEX", Vector2.new(640, 460), Color3.fromRGB(40, 130, 240), refreshIndex)
	indexCount = Ui.text(window, { name = "Count", text = "", color = MUTED, size = UDim2.fromOffset(260, 24), position = UDim2.fromOffset(22, 14), textSize = 20, stroke = 3, align = Enum.TextXAlignment.Left })
	local grid = gridArea(window, 44, 18, Vector2.new(104, 146))
	for order, info in Config.Characters do
		local frame = card(grid, info.id, order, EMPTY)
		local viewport = viewportIn(frame, 76)
		CharacterModels.render(viewport, info.id)
		local name = fitted(frame, "Name", "???", 76, 26, 14)
		fitted(frame, "Rarity", string.upper(Config.Rarities[info.rarity].id), 102, 18, 13, Config.Rarities[info.rarity].color)
		local income = fitted(frame, "Income", "?", 120, 22, 16, P.money)
		indexCards[info.id] = { frame = frame, viewport = viewport, name = name, income = income, found = nil }
	end
	player:GetAttributeChangedSignal("Index"):Connect(refreshIndex)
end

---------------------------------------------------------------------------------------------------
-- Loja, rebirth, daily e playtime: só layout por enquanto.

local function buildShop()
	local window = Windows.create("Shop", "SHOP", Vector2.new(560, 400), P.red)
	local grid = gridArea(window, 44, 18, Vector2.new(240, 150))
	for order, item in Config.Shop do
		local frame = card(grid, item.id, order)
		Ui.text(frame, { name = "Icon", text = item.icon, size = UDim2.fromOffset(70, 70), position = UDim2.fromOffset(12, 12), stroke = 3 })
		Ui.text(frame, { name = "Name", text = item.name, color = P.yellowLine, size = UDim2.new(1, -96, 0, 60), position = UDim2.fromOffset(90, 16), textSize = 24, stroke = 3, align = Enum.TextXAlignment.Left })
		local price = Ui.frame(frame, "Price", UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 1, -56), Color3.fromRGB(90, 96, 120))
		Ui.corner(price, 12)
		Ui.border(price, 3)
		Ui.text(price, { name = "Label", text = "SOON", size = UDim2.fromScale(1, 1), textSize = 22, stroke = 3 })
		local button = Ui.hit(frame, "Hit")
		Ui.juice(button, frame)
		button.Activated:Connect(function()
			soon(item.name)
		end)
	end
end

local function buildRebirth()
	local window = Windows.create("Rebirth", "REBIRTH", Vector2.new(460, 340), Color3.fromRGB(225, 50, 150))
	Ui.text(window, { name = "Icon", text = "🔄", size = UDim2.fromOffset(90, 90), position = UDim2.new(0.5, 0, 0, 44), anchor = Vector2.new(0.5, 0), stroke = 3 })
	Ui.text(window, { name = "Count", text = "REBIRTHS: 0", color = P.yellowLine, size = UDim2.new(1, -40, 0, 34), position = UDim2.fromOffset(20, 142), textSize = 30, stroke = 4 })
	Ui.text(window, { name = "Info", text = "Reset your Power and Money for a permanent boost.", color = MUTED, size = UDim2.new(1, -40, 0, 48), position = UDim2.fromOffset(20, 182), textSize = 19, stroke = 2 }).TextWrapped = true
	footerButton(window, "REBIRTH", Color3.fromRGB(90, 96, 120), function()
		soon("REBIRTH")
	end)
end

local function buildDaily()
	local days = Config.Daily.days
	local window = Windows.create("Daily", "DAILY REWARDS", Vector2.new(660, 320), Color3.fromRGB(40, 190, 70))
	local row = Ui.frame(window, "Days", UDim2.new(1, -36, 0, 150), UDim2.fromOffset(18, 48))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(78, 140)
	layout.CellPadding = UDim2.fromOffset(10, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row
	for day = 1, days do
		local frame = card(row, "Day" .. day, day)
		Ui.text(frame, { name = "Day", text = "DAY " .. day, color = P.yellowLine, size = UDim2.new(1, 0, 0, 26), position = UDim2.fromOffset(0, 6), textSize = 19, stroke = 3 })
		Ui.text(frame, { name = "Icon", text = if day == days then "👑" else "🎁", size = UDim2.fromOffset(54, 54), position = UDim2.new(0.5, 0, 0, 36), anchor = Vector2.new(0.5, 0), stroke = 3 })
		Ui.text(frame, { name = "Reward", text = "?", color = MUTED, size = UDim2.new(1, 0, 0, 26), position = UDim2.new(0, 0, 1, -32), textSize = 20, stroke = 3 })
	end
	footerButton(window, "CLAIM", Color3.fromRGB(90, 96, 120), function()
		soon("DAILY REWARDS")
	end)
end

local playtimeCards: { { minutes: number, status: TextLabel } } = {}
local joinedAt = os.clock()

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function refreshPlaytime()
	local played = math.floor(os.clock() - joinedAt)
	local nextIn: number? = nil
	for _, entry in playtimeCards do
		local left = entry.minutes * 60 - played
		entry.status.Text = if left > 0 then clock(left) else "READY!"
		entry.status.TextColor3 = if left > 0 then MUTED else P.money
		if left > 0 and not nextIn then
			nextIn = left
		end
	end
	-- o mesmo contador aparece embaixo do botão PLAYTIME do HUD
	local holder = Hud.gui():FindFirstChild("PlaytimeButton", true)
	local status = holder and holder:FindFirstChild("Status")
	if status and status:IsA("TextLabel") then
		status.Text = if nextIn then clock(nextIn) else "READY!"
	end
end

local function buildPlaytime()
	local window = Windows.create("Playtime", "PLAYTIME REWARDS", Vector2.new(560, 400), Color3.fromRGB(240, 130, 30), refreshPlaytime)
	local grid = gridArea(window, 44, 18, Vector2.new(156, 150))
	for order, minutes in Config.Playtime.minutes do
		local frame = card(grid, "Reward" .. order, order)
		Ui.text(frame, { name = "Time", text = minutes .. " MIN", color = P.yellowLine, size = UDim2.new(1, 0, 0, 26), position = UDim2.fromOffset(0, 8), textSize = 21, stroke = 3 })
		Ui.text(frame, { name = "Icon", text = "🎁", size = UDim2.fromOffset(64, 64), position = UDim2.new(0.5, 0, 0, 38), anchor = Vector2.new(0.5, 0), stroke = 3 })
		local status = Ui.text(frame, { name = "Status", text = "", color = MUTED, size = UDim2.new(1, 0, 0, 28), position = UDim2.new(0, 0, 1, -36), textSize = 22, stroke = 3 })
		local button = Ui.hit(frame, "Hit")
		Ui.juice(button, frame)
		button.Activated:Connect(function()
			soon("PLAYTIME REWARDS")
		end)
		table.insert(playtimeCards, { minutes = minutes, status = status })
	end
	task.spawn(function()
		while true do
			refreshPlaytime()
			task.wait(1)
		end
	end)
end

---------------------------------------------------------------------------------------------------

-- Gancho dos testes do servidor (só no Studio): estado das janelas e da pose de caminhada.
local function testHook()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TestUi", 10)
	if not remote or not remote:IsA("RemoteFunction") then
		return
	end
	remote.OnClientInvoke = function(command: string, arg: any): any
		if command == "toggle" then
			Windows.toggle(arg)
		elseif command == "panel" then
			return Windows.debug()
		elseif command == "autoToggle" then
			Auto.toggle(arg)
			return Auto.isOn(arg)
		elseif command == "autoState" then
			return { punch = Auto.isOn("punch"), super = Auto.isOn("super") }
		elseif command == "superAuto" then
			-- joga o minigame sozinho: aperta a tecla pedida no meio da zona verde
			task.spawn(function()
				while Super.isActive() do
					local now = Super.debug()
					if now.key and now.zone and now.time and now.elapsed >= (now.zone + Config.Super.zoneWidth / 2) * now.time then
						Super.press(now.key)
					end
					RunService.Heartbeat:Wait()
				end
			end)
			return Super.isActive()
		elseif command == "superEarly" then
			-- aperta a tecla certa cedo demais
			local now = Super.debug()
			if now.key then
				Super.press(now.key)
			end
			return now.active
		elseif command == "superState" then
			return Super.debug()
		elseif command == "dash" then
			Move.dash()
			return true
		elseif command == "charge" then
			-- segura a carga por `arg` segundos e solta
			Run.beginCharge()
			task.delay(arg, Run.releaseCharge)
			return Run.isBusy()
		elseif command == "walk" then
			-- anda na direção arg.direction por arg.seconds, como se a tecla estivesse apertada:
			-- roda logo depois do controle padrão, que manda "parado" a cada quadro
			local finish = os.clock() + arg.seconds
			RunService:UnbindFromRenderStep("TestWalk")
			RunService:BindToRenderStep("TestWalk", Enum.RenderPriority.Input.Value + 1, function()
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if os.clock() >= finish or not humanoid then
					RunService:UnbindFromRenderStep("TestWalk")
				else
					humanoid:Move(arg.direction, false)
				end
			end)
			return true
		elseif command == "arms" then
			-- média, por `arg` segundos, da inclinação dos ombros para trás (graus) e do peso da camada
			local pitch, weight, samples = 0, 0, 0
			local finish = os.clock() + arg
			while os.clock() < finish do
				RunService.Heartbeat:Wait()
				local right, left = Pose.transform("RightShoulder"), Pose.transform("LeftShoulder")
				if right and left then
					pitch += (math.deg((right:ToEulerAnglesXYZ())) + math.deg((left:ToEulerAnglesXYZ()))) / 2
					weight += Pose.current("walkArms")
					samples += 1
				end
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			return {
				samples = samples,
				pitch = if samples > 0 then pitch / samples else 0,
				walkArms = if samples > 0 then weight / samples else 0,
				sprint = Pose.current("sprint"),
				speed = if humanoid then humanoid.WalkSpeed else 0,
				moving = if humanoid then humanoid.MoveDirection.Magnitude else 0,
				floor = if humanoid then humanoid.FloorMaterial.Name else "",
			}
		end
		local visible = 0
		for _, entry in indexCards do
			if entry.found then
				visible += 1
			end
		end
		return {
			open = Windows.current() or "",
			backpackCells = #backpackCells,
			backpackCount = backpackCount.Text,
			indexCards = #Config.Characters,
			indexFound = visible,
			indexCount = indexCount.Text,
		}
	end
end

function Menus.start()
	buildBackpack()
	buildAuras()
	buildIndex()
	buildShop()
	buildRebirth()
	buildDaily()
	buildPlaytime()

	local buttons = { BackpackButton = "Backpack", ShopButton = "Shop", RebirthButton = "Rebirth", IndexButton = "Index", DailyButton = "Daily", PlaytimeButton = "Playtime", AuraButton = "Auras" }
	for button, window in buttons do
		Hud.onClick(button, function()
			Windows.toggle(window)
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.G then
			Windows.toggle("Backpack")
		end
	end)

	if RunService:IsStudio() then
		task.spawn(testHook)
	end
end

return Menus
