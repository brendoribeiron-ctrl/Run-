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
local Aura = require(script.Parent.Aura)
local Worlds = require(script.Parent.Worlds)
local Auto = require(script.Parent.Auto)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Mount = require(script.Parent.Mount)
local Others = require(script.Parent.Others)
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
local backpackSell: TextButton
local backpackFuse: TextButton
local sellArmed = 0 -- até quando o segundo clique confirma a venda

-- Preço de venda do personagem selecionado (nil sem seleção).
local function sellOffer(): (number?, number?)
	local selected = player:GetAttribute("Selected")
	local id = if type(selected) == "number" then list("Inventory")[selected] else nil
	if not id or not Config.CharacterById[id] then
		return nil, nil
	end
	local level = 1
	for _, pair in list("Levels") do
		local owner, value = string.match(pair, "^(.+):(%d+)$")
		if owner == id then
			level = tonumber(value) :: number
		end
	end
	return selected :: number, Config.sellPrice(id, level)
end

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
	local _, price = sellOffer()
	local armed = os.clock() < sellArmed
	backpackSell.Text = if not price then "SELL" elseif armed then "CONFIRM?" else `SELL ${Format.abbreviate(price)}`
	backpackSell.BackgroundColor3 = if not price then EMPTY elseif armed then P.red else Color3.fromRGB(40, 170, 70)
	-- fusão: quantas cópias do selecionado existem na mochila
	local chosen = if type(selected) == "number" then items[selected] else nil
	local info = chosen and Config.CharacterById[chosen]
	local copies = 0
	for _, id in items do
		if id == chosen then
			copies += 1
		end
	end
	local need = Config.Fusion.count
	local canFuse = info ~= nil and not info.shiny and copies >= need
	backpackFuse.Text = if not info then "FUSE" elseif info.shiny then "SHINY!" else `FUSE {math.min(copies, need)}/{need}`
	backpackFuse.BackgroundColor3 = if canFuse then Color3.fromRGB(230, 170, 30) else EMPTY
end

local function buildBackpack()
	local window = Windows.create("Backpack", "BACKPACK", Vector2.new(640, 440), P.cyan, refreshBackpack)
	backpackCount = Ui.text(window, { name = "Count", text = "0/0", color = MUTED, size = UDim2.fromOffset(120, 24), position = UDim2.fromOffset(22, 14), textSize = 20, stroke = 3, align = Enum.TextXAlignment.Left })
	backpackGrid = gridArea(window, 44, 72, Vector2.new(92, 110))
	-- barra de baixo: slots rápidos (escolha um personagem e clique no número para colocá-lo ali)
	-- e, à direita, os botões de fundir e vender o personagem escolhido
	local slotRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Slot") :: RemoteEvent
	local bar = Ui.frame(window, "Slots", UDim2.new(1, -36, 0, 48), UDim2.new(0, 18, 1, -60))
	Ui.text(bar, { name = "Label", text = "SLOT", color = MUTED, size = UDim2.fromOffset(52, 48), textSize = 17, stroke = 2, align = Enum.TextXAlignment.Left })
	for slot = 1, Config.Inventory.hotbarSlots do
		local button = Instance.new("TextButton")
		button.Name = "Slot" .. slot
		button.Position = UDim2.fromOffset(56 + (slot - 1) * 42, 5)
		button.Size = UDim2.fromOffset(38, 38)
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
	-- vender o personagem selecionado: o primeiro clique arma, o segundo (em 2,5 s) confirma
	local sellRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Sell") :: RemoteEvent
	backpackSell = Instance.new("TextButton")
	backpackSell.Name = "Sell"
	backpackSell.AnchorPoint = Vector2.new(1, 0)
	backpackSell.Position = UDim2.new(1, 0, 0, 5)
	backpackSell.Size = UDim2.fromOffset(112, 38)
	backpackSell.BackgroundColor3 = EMPTY
	backpackSell.Font = Enum.Font.FredokaOne
	backpackSell.TextSize = 17
	backpackSell.TextColor3 = Ui.white
	backpackSell.Text = "SELL"
	backpackSell.AutoButtonColor = false
	Ui.corner(backpackSell, 10)
	Ui.border(backpackSell, 3)
	Ui.juice(backpackSell)
	backpackSell.Activated:Connect(function()
		local index = sellOffer()
		if not index then
			Fx.toast("Pick a character first!", P.yellowLine)
			return
		end
		if os.clock() < sellArmed then
			sellArmed = 0
			sellRemote:FireServer(index)
		else
			sellArmed = os.clock() + 2.5
			task.delay(2.6, refreshBackpack)
		end
		refreshBackpack()
	end)
	backpackSell.Parent = bar
	-- fusão: três iguais viram um Shiny, com a renda multiplicada
	local fuseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fuse") :: RemoteEvent
	backpackFuse = Instance.new("TextButton")
	backpackFuse.Name = "Fuse"
	backpackFuse.AnchorPoint = Vector2.new(1, 0)
	backpackFuse.Position = UDim2.new(1, -118, 0, 5)
	backpackFuse.Size = UDim2.fromOffset(92, 38)
	backpackFuse.BackgroundColor3 = EMPTY
	backpackFuse.Font = Enum.Font.FredokaOne
	backpackFuse.TextSize = 17
	backpackFuse.TextColor3 = Ui.white
	backpackFuse.Text = "FUSE"
	backpackFuse.AutoButtonColor = false
	Ui.corner(backpackFuse, 10)
	Ui.border(backpackFuse, 3)
	Ui.juice(backpackFuse)
	backpackFuse.Activated:Connect(function()
		local selected = player:GetAttribute("Selected")
		if type(selected) == "number" and selected >= 1 then
			fuseRemote:FireServer(selected)
		else
			Fx.toast("Pick a character first!", P.yellowLine)
		end
	end)
	backpackFuse.Parent = bar
	player:GetAttributeChangedSignal("Levels"):Connect(refreshBackpack)
	player:GetAttributeChangedSignal("Selected"):Connect(function()
		sellArmed = 0 -- trocou de personagem: a confirmação não vale para o outro
	end)
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
	Ui.text(window, { name = "Help", text = "Reach the Power to unlock. Your aura boosts Power and grows stronger as you do.", color = MUTED, size = UDim2.new(1, -40, 0, 22), position = UDim2.fromOffset(20, 46), textSize = 16, stroke = 2 })
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
-- Jogadores: Poder e dinheiro de todo mundo no servidor, do mais forte para o mais fraco.

type RankRow = { frame: Frame, place: TextLabel, name: TextLabel, power: TextLabel, money: TextLabel }
local rankRows: { RankRow } = {}

local function refreshRank()
	if not Windows.isOpen("Players") then
		return
	end
	local list = Players:GetPlayers()
	local function number(other: Player, attribute: string): number
		local value = other:GetAttribute(attribute)
		return if type(value) == "number" then value else 0
	end
	table.sort(list, function(a, b)
		local pa, pb = number(a, "Power"), number(b, "Power")
		return if pa ~= pb then pa > pb else a.UserId < b.UserId
	end)
	for index, row in rankRows do
		local other = list[index]
		row.frame.Visible = other ~= nil
		if other then
			row.place.Text = "#" .. index
			row.name.Text = if other == player then other.DisplayName .. " (you)" else other.DisplayName
			row.name.TextColor3 = if other == player then P.yellowLine else Ui.white
			row.power.Text = Format.abbreviate(number(other, "Power")) .. " POWER"
			row.money.Text = "$" .. Format.abbreviate(number(other, "Money"))
		end
	end
end

local function buildRank()
	local window = Windows.create("Players", "PLAYERS", Vector2.new(640, 460), Color3.fromRGB(230, 150, 30), refreshRank)
	for index = 1, Config.World.plotCount do
		local frame = Ui.frame(window, "Row" .. index, UDim2.new(1, -40, 0, 52), UDim2.fromOffset(20, 50 + (index - 1) * 60), CARD)
		Ui.corner(frame, 12)
		Ui.border(frame, 3)
		local function cell(name: string, x: number, width: number, color: Color3, align: Enum.TextXAlignment): TextLabel
			return Ui.text(frame, { name = name, text = "", color = color, size = UDim2.new(0, width, 1, -12), position = UDim2.fromOffset(x, 6), textSize = 24, stroke = 3, align = align })
		end
		rankRows[index] = {
			frame = frame,
			place = cell("Place", 12, 50, MUTED, Enum.TextXAlignment.Left),
			name = cell("Name", 66, 230, Ui.white, Enum.TextXAlignment.Left),
			power = cell("Power", 300, 160, P.power, Enum.TextXAlignment.Right),
			money = cell("Money", 468, 120, P.money, Enum.TextXAlignment.Right),
		}
	end
	task.spawn(function()
		while true do
			refreshRank()
			task.wait(0.5)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Montarias: compra uma vez com dinheiro, depois equipa e desequipa. Só visual.

local mountCards: { [string]: { frame: Frame, status: TextLabel, border: UIStroke } } = {}

local function refreshMounts()
	if not Windows.isOpen("Mounts") then
		return
	end
	local owned: { [string]: boolean } = {}
	for _, id in list("Mounts") do
		owned[id] = true
	end
	local equipped = player:GetAttribute("Mount")
	for _, info in Config.Mounts do
		local entry = mountCards[info.id]
		local on = equipped == info.id
		entry.status.Text = if on then "RIDING" elseif owned[info.id] then "RIDE" else `BUY ${Format.abbreviate(info.price)}`
		entry.status.TextColor3 = if on then P.money elseif owned[info.id] then Ui.white else P.yellowLine
		entry.border.Color = if on then Ui.white else P.outline
		entry.border.Thickness = if on then 5 else 3
	end
end

-- Põe uma cópia do modelo da montaria girando devagar dentro do cartão.
local function mountPreview(viewport: ViewportFrame, id: string)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Mounts", 120)
		local template = folder and folder:FindFirstChild(id)
		if not template or not template:IsA("Model") then
			return
		end
		local model = template:Clone()
		model:PivotTo(CFrame.new())
		model.Parent = viewport
		local camera = Instance.new("Camera")
		local _, size = model:GetBoundingBox()
		local reach = math.max(size.X, size.Z)
		camera.FieldOfView = 40
		camera.CFrame = CFrame.lookAt(Vector3.new(reach * 0.75, reach * 0.55, reach * 0.95), Vector3.new(0, -0.2, 0))
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		viewport.LightDirection = Vector3.new(-1, -2, -1)
		viewport.Ambient = Color3.fromRGB(190, 190, 200)
		RunService.Heartbeat:Connect(function()
			if Windows.isOpen("Mounts") then
				model:PivotTo(CFrame.Angles(0, os.clock() * 0.9, 0))
			end
		end)
	end)
end

local function buildMounts()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Mount") :: RemoteEvent
	local window = Windows.create("Mounts", "MOUNTS", Vector2.new(640, 460), Color3.fromRGB(30, 160, 240), refreshMounts)
	Ui.text(window, { name = "Help", text = "Buy once, ride anywhere. Same speed, more style. Click again to hop off.", color = MUTED, size = UDim2.new(1, -40, 0, 22), position = UDim2.fromOffset(20, 46), textSize = 16, stroke = 2 })
	local grid = gridArea(window, 72, 18, Vector2.new(280, 300))
	for order, info in Config.Mounts do
		local frame, border = card(grid, info.id, order)
		mountPreview(viewportIn(frame, 170), info.id)
		fitted(frame, "Name", info.name, 180, 30, 24, info.color)
		fitted(frame, "Info", info.info, 214, 22, 16, MUTED)
		local status = fitted(frame, "Status", "", 250, 34, 24)
		local button = Ui.hit(frame, "Hit")
		Ui.juice(button, frame)
		button.Activated:Connect(function()
			remote:FireServer(info.id)
		end)
		mountCards[info.id] = { frame = frame, status = status, border = border }
	end
	player:GetAttributeChangedSignal("Mounts"):Connect(refreshMounts)
	player:GetAttributeChangedSignal("Mount"):Connect(refreshMounts)
end

---------------------------------------------------------------------------------------------------
-- Índice: todos os personagens do Config; os que ainda não saíram ficam em silhueta.

type IndexCard = { frame: Frame, viewport: ViewportFrame, name: TextLabel, income: TextLabel, found: boolean?, level: number? }

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
	-- níveis acima de 1 chegam como "id:nível,id:nível"
	local levels: { [string]: number } = {}
	for _, pair in list("Levels") do
		local id, level = string.match(pair, "^(.+):(%d+)$")
		if id then
			levels[id] = tonumber(level) :: number
		end
	end
	indexFound = 0
	for _, info in Config.Characters do
		local entry = indexCards[info.id]
		local has = found[info.id] == true
		local level = levels[info.id] or 1
		if has then
			indexFound += 1
		end
		if entry.found ~= has or entry.level ~= level then
			entry.found = has
			entry.level = level
			entry.frame.BackgroundColor3 = if has then Config.Rarities[info.rarity].color else EMPTY
			entry.viewport.ImageColor3 = if has then Ui.white else Color3.new(0, 0, 0)
			entry.name.Text = if has then info.name else "???"
			entry.income.Text = if has then `Lv {level}  ${Format.abbreviate(Config.fighterIncome(info.id, level))}/s` else "?"
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
	player:GetAttributeChangedSignal("Levels"):Connect(refreshIndex)
end

---------------------------------------------------------------------------------------------------
-- Loja de poções, rebirth, recompensa diária com missões e recompensas por tempo de jogo.
-- As regras ficam no servidor (src/server/Progress.luau); aqui é só a janela.

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function clock(seconds: number): string
	local whole = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- Botão pequeno com texto, usado dentro das janelas.
local function smallButton(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, action: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = EMPTY
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 20
	button.TextColor3 = Ui.white
	button.Text = text
	button.AutoButtonColor = false
	Ui.corner(button, 10)
	Ui.border(button, 3)
	Ui.juice(button)
	button.Activated:Connect(action)
	button.Parent = parent
	return button
end

local GREEN = Color3.fromRGB(40, 170, 70)

-- Poções ------------------------------------------------------------------------------------------

local potionCards: { [string]: { status: TextLabel, price: TextLabel, border: UIStroke } } = {}

local function boostEnds(): { [string]: number }
	local ends = {}
	for _, pair in list("Boosts") do
		local id, at = string.match(pair, "^(.+):(%d+)$")
		if id then
			ends[id] = tonumber(at) :: number
		end
	end
	return ends
end

local function refreshShop()
	if not Windows.isOpen("Shop") then
		return
	end
	local ends = boostEnds()
	for _, info in Config.Potions.list do
		local entry = potionCards[info.id]
		local left = (ends[info.id] or 0) - serverNow()
		entry.status.Text = if left > 0 then "ACTIVE " .. clock(left) else `{info.seconds // 60} MIN`
		entry.status.TextColor3 = if left > 0 then P.money else MUTED
		entry.border.Color = if left > 0 then Ui.white else P.outline
		entry.price.Text = "$" .. Format.abbreviate(info.price)
	end
end

local function buildShop()
	local remote = remotes:WaitForChild("Potion") :: RemoteEvent
	local window = Windows.create("Shop", "POTION SHOP", Vector2.new(640, 400), P.red, refreshShop)
	Ui.text(window, { name = "Help", text = "Potions boost you for a while. Buying again adds more time.", color = MUTED, size = UDim2.new(1, -40, 0, 22), position = UDim2.fromOffset(20, 46), textSize = 16, stroke = 2 })
	local grid = gridArea(window, 76, 18, Vector2.new(188, 280))
	for order, info in Config.Potions.list do
		local frame, border = card(grid, info.id, order)
		Ui.text(frame, { name = "Icon", text = info.icon, size = UDim2.fromOffset(80, 80), position = UDim2.new(0.5, 0, 0, 12), anchor = Vector2.new(0.5, 0), stroke = 3 })
		fitted(frame, "Name", info.name, 98, 28, 22, info.color)
		fitted(frame, "Info", info.info, 128, 26, 22, Ui.white)
		local status = fitted(frame, "Status", "", 160, 26, 20, MUTED)
		local box = Ui.frame(frame, "Price", UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 1, -56), GREEN)
		Ui.corner(box, 12)
		Ui.border(box, 3)
		local price = Ui.text(box, { name = "Label", text = "", size = UDim2.fromScale(1, 1), textSize = 22, stroke = 3 })
		local button = Ui.hit(frame, "Hit")
		Ui.juice(button, frame)
		button.Activated:Connect(function()
			remote:FireServer(info.id)
		end)
		potionCards[info.id] = { status = status, price = price, border = border }
	end
	player:GetAttributeChangedSignal("Boosts"):Connect(refreshShop)
end

-- Rebirth -----------------------------------------------------------------------------------------

local rebirthLabels: { count: TextLabel, now: TextLabel, need: TextLabel, button: TextButton }

local function rebirthCost(rebirths: number): number
	return math.floor(Config.Walls[#Config.Walls].power * Config.Rebirth.costGrowth ^ rebirths)
end

local function refreshRebirth()
	if not Windows.isOpen("Rebirth") then
		return
	end
	local count = numberAttribute("Rebirths")
	local maxed = count >= Config.Rebirth.max
	local cost = rebirthCost(count)
	local ready = not maxed and numberAttribute("Power") >= cost
	local function times(rebirths: number): string
		return `x{1 + rebirths * Config.Rebirth.powerPerRebirth} Power, x{1 + rebirths * Config.Rebirth.moneyPerRebirth} Money`
	end
	rebirthLabels.count.Text = "REBIRTHS: " .. count
	rebirthLabels.now.Text = if maxed then times(count) else `{times(count)}  >  {times(count + 1)}`
	rebirthLabels.need.Text = if maxed then "MAX REBIRTHS!" elseif ready then "READY!" else `Need {Format.abbreviate(cost)} Power`
	rebirthLabels.need.TextColor3 = if ready then P.money else MUTED
	rebirthLabels.button.BackgroundColor3 = if ready then Color3.fromRGB(225, 50, 150) else Color3.fromRGB(90, 96, 120)
end

local function buildRebirth()
	local remote = remotes:WaitForChild("Rebirth") :: RemoteEvent
	local window = Windows.create("Rebirth", "REBIRTH", Vector2.new(520, 400), Color3.fromRGB(225, 50, 150), refreshRebirth)
	Ui.text(window, { name = "Icon", text = "🔄", size = UDim2.fromOffset(80, 80), position = UDim2.new(0.5, 0, 0, 40), anchor = Vector2.new(0.5, 0), stroke = 3 })
	local count = Ui.text(window, { name = "Count", text = "REBIRTHS: 0", color = P.yellowLine, size = UDim2.new(1, -40, 0, 34), position = UDim2.fromOffset(20, 126), textSize = 30, stroke = 4 })
	local now = Ui.text(window, { name = "Bonus", text = "", color = Ui.white, size = UDim2.new(1, -40, 0, 26), position = UDim2.fromOffset(20, 166), textSize = 19, stroke = 3 })
	local info = Ui.text(window, { name = "Info", text = "Resets Power, Money and Bag. Keeps characters, pedestals, skills and mounts.", color = MUTED, size = UDim2.new(1, -60, 0, 44), position = UDim2.fromOffset(30, 198), textSize = 17, stroke = 2 })
	info.TextWrapped = true
	local need = Ui.text(window, { name = "Need", text = "", color = MUTED, size = UDim2.new(1, -40, 0, 28), position = UDim2.fromOffset(20, 250), textSize = 22, stroke = 3 })
	local button = footerButton(window, "REBIRTH", Color3.fromRGB(90, 96, 120), function()
		remote:FireServer()
	end)
	rebirthLabels = { count = count, now = now, need = need, button = button }
	player:GetAttributeChangedSignal("Rebirths"):Connect(refreshRebirth)
	player:GetAttributeChangedSignal("Power"):Connect(refreshRebirth)
end

-- Recompensa diária e missões do dia -------------------------------------------------------------

type DayCard = { frame: Frame, border: UIStroke, reward: TextLabel }
type QuestRow = { id: string, progress: TextLabel, fill: Frame, button: TextButton }
local dayCards: { DayCard } = {}
local questRows: { QuestRow } = {}
local dailyButton: TextButton

-- Dia da sequência que o próximo resgate entrega, e se já dá para resgatar hoje.
local function dailyState(): (number, boolean)
	local raw = player:GetAttribute("Daily")
	local streak, last = 0, 0
	if type(raw) == "string" then
		local a, b = string.match(raw, "^(%d+):(%d+)$")
		streak, last = tonumber(a) or 0, tonumber(b) or 0
	end
	local day = math.floor(serverNow() / 86400)
	if last >= day then
		return streak, false -- já resgatou hoje: mostra o dia em que está
	end
	return if last == day - 1 then streak % Config.Daily.days + 1 else 1, true
end

local function questState(): { [string]: { progress: number, claimed: boolean } }
	local out = {}
	local raw = player:GetAttribute("Quests")
	local day, rest = string.match(if type(raw) == "string" then raw else "", "^(%d+)|(.*)$")
	local fresh = tonumber(day) == math.floor(serverNow() / 86400)
	for _, entry in string.split(rest or "", ",") do
		local id, progress, claimed = string.match(entry, "^(.+):(%d+):(%d)$")
		if id then
			out[id] = { progress = if fresh then tonumber(progress) :: number else 0, claimed = fresh and claimed == "1" }
		end
	end
	return out
end

local function refreshDaily()
	local day, canClaim = dailyState()
	-- o aviso embaixo do botão DAILY do HUD vale mesmo com a janela fechada
	local holder = Hud.gui():FindFirstChild("DailyButton", true)
	local status = holder and holder:FindFirstChild("Status")
	local quests = questState()
	local pending = canClaim
	for _, quest in Config.Quests do
		local state = quests[quest.id]
		if state and state.progress >= quest.goal and not state.claimed then
			pending = true
		end
	end
	if status and status:IsA("TextLabel") then
		status.Text = if pending then "READY!" else ""
	end
	if not Windows.isOpen("Daily") then
		return
	end
	local bonus = 1 + numberAttribute("Rebirths") * Config.Rebirth.rewardPerRebirth
	for index, entry in dayCards do
		local done = index < day or (index == day and not canClaim)
		entry.reward.Text = if done then "CLAIMED" else "$" .. Format.abbreviate(math.floor(Config.Daily.rewards[index] * bonus))
		entry.reward.TextColor3 = if done then MUTED else P.money
		entry.frame.BackgroundColor3 = if done then EMPTY else CARD
		entry.border.Color = if index == day and canClaim then Ui.white else P.outline
		entry.border.Thickness = if index == day and canClaim then 5 else 3
	end
	dailyButton.Text = if canClaim then `CLAIM DAY {day}` else "COME BACK TOMORROW"
	dailyButton.BackgroundColor3 = if canClaim then GREEN else EMPTY
	for _, row in questRows do
		local quest = Config.QuestById[row.id]
		local state = quests[row.id] or { progress = 0, claimed = false }
		local complete = state.progress >= quest.goal
		row.progress.Text = `{Format.abbreviate(state.progress)}/{Format.abbreviate(quest.goal)}`
		row.fill.Size = UDim2.fromScale(math.clamp(state.progress / quest.goal, 0, 1), 1)
		row.button.Text = if state.claimed then "DONE" elseif complete then "CLAIM" else "$" .. Format.abbreviate(math.floor(quest.reward * bonus))
		row.button.BackgroundColor3 = if complete and not state.claimed then GREEN else EMPTY
	end
end

local function buildDaily()
	local days = Config.Daily.days
	local dailyRemote = remotes:WaitForChild("Daily") :: RemoteEvent
	local questRemote = remotes:WaitForChild("Quest") :: RemoteEvent
	local window = Windows.create("Daily", "DAILY", Vector2.new(660, 540), GREEN, refreshDaily)
	local row = Ui.frame(window, "Days", UDim2.new(1, -36, 0, 124), UDim2.fromOffset(18, 44))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(78, 118)
	layout.CellPadding = UDim2.fromOffset(10, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row
	for day = 1, days do
		local frame, border = card(row, "Day" .. day, day)
		Ui.text(frame, { name = "Day", text = "DAY " .. day, color = P.yellowLine, size = UDim2.new(1, 0, 0, 24), position = UDim2.fromOffset(0, 4), textSize = 18, stroke = 3 })
		Ui.text(frame, { name = "Icon", text = if day == days then "👑" else "🎁", size = UDim2.fromOffset(46, 46), position = UDim2.new(0.5, 0, 0, 30), anchor = Vector2.new(0.5, 0), stroke = 3 })
		local reward = Ui.text(frame, { name = "Reward", text = "", color = P.money, size = UDim2.new(1, -4, 0, 24), position = UDim2.new(0, 2, 1, -30), textSize = 17, stroke = 3 })
		dayCards[day] = { frame = frame, border = border, reward = reward }
	end
	dailyButton = smallButton(window, "Claim", "CLAIM", UDim2.fromOffset(300, 40), UDim2.new(0.5, -150, 0, 176), function()
		dailyRemote:FireServer()
	end)

	Ui.text(window, { name = "QuestsTitle", text = "TODAY'S QUESTS", color = P.yellowLine, size = UDim2.new(1, -40, 0, 26), position = UDim2.fromOffset(20, 228), textSize = 22, stroke = 3 })
	for index, quest in Config.Quests do
		local frame = Ui.frame(window, "Quest" .. index, UDim2.new(1, -40, 0, 58), UDim2.fromOffset(20, 260 + (index - 1) * 66), CARD)
		Ui.corner(frame, 12)
		Ui.border(frame, 3)
		Ui.text(frame, { name = "Text", text = quest.text, size = UDim2.new(1, -300, 0, 28), position = UDim2.fromOffset(14, 4), textSize = 20, stroke = 3, align = Enum.TextXAlignment.Left })
		local bar = Ui.frame(frame, "Bar", UDim2.new(1, -300, 0, 12), UDim2.fromOffset(14, 38), EMPTY)
		Ui.corner(bar, 6)
		local fill = Ui.frame(bar, "Fill", UDim2.fromScale(0, 1), nil, P.money)
		Ui.corner(fill, 6)
		local progress = Ui.text(frame, { name = "Progress", text = "", color = MUTED, size = UDim2.fromOffset(120, 28), position = UDim2.new(1, -278, 0, 15), textSize = 19, stroke = 3 })
		local button = smallButton(frame, "Claim", "", UDim2.fromOffset(140, 40), UDim2.new(1, -150, 0, 9), function()
			questRemote:FireServer(quest.id)
		end)
		questRows[index] = { id = quest.id, progress = progress, fill = fill, button = button }
	end
	player:GetAttributeChangedSignal("Daily"):Connect(refreshDaily)
	player:GetAttributeChangedSignal("Quests"):Connect(refreshDaily)
	task.spawn(function()
		while true do
			refreshDaily()
			task.wait(2)
		end
	end)
end

-- Recompensas por tempo de jogo --------------------------------------------------------------------

local playtimeCards: { { minutes: number, status: TextLabel, frame: Frame } } = {}

local function refreshPlaytime()
	local joined = player:GetAttribute("JoinedAt")
	local played = if type(joined) == "number" then serverNow() - joined else 0
	local claimed = list("PlaytimeClaimed")
	local label: string? = nil
	local bonus = 1 + numberAttribute("Rebirths") * Config.Rebirth.rewardPerRebirth
	for index, entry in playtimeCards do
		local left = entry.minutes * 60 - played
		local done = table.find(claimed, tostring(index)) ~= nil
		entry.status.Text = if done then "CLAIMED" elseif left > 0 then clock(left) else "CLAIM $" .. Format.abbreviate(math.floor(Config.Playtime.rewards[index] * bonus))
		entry.status.TextColor3 = if done then MUTED elseif left > 0 then MUTED else P.money
		entry.frame.BackgroundColor3 = if done then EMPTY else CARD
		if not done and not label then
			label = if left > 0 then clock(left) else "READY!"
		end
	end
	-- o mesmo contador aparece embaixo do botão PLAYTIME do HUD
	local holder = Hud.gui():FindFirstChild("PlaytimeButton", true)
	local status = holder and holder:FindFirstChild("Status")
	if status and status:IsA("TextLabel") then
		status.Text = label or ""
	end
end

local function buildPlaytime()
	local remote = remotes:WaitForChild("Playtime") :: RemoteEvent
	local window = Windows.create("Playtime", "PLAYTIME REWARDS", Vector2.new(560, 400), Color3.fromRGB(240, 130, 30), refreshPlaytime)
	local grid = gridArea(window, 44, 18, Vector2.new(156, 150))
	for order, minutes in Config.Playtime.minutes do
		local frame = card(grid, "Reward" .. order, order)
		Ui.text(frame, { name = "Time", text = minutes .. " MIN", color = P.yellowLine, size = UDim2.new(1, 0, 0, 26), position = UDim2.fromOffset(0, 8), textSize = 21, stroke = 3 })
		Ui.text(frame, { name = "Icon", text = "🎁", size = UDim2.fromOffset(64, 64), position = UDim2.new(0.5, 0, 0, 38), anchor = Vector2.new(0.5, 0), stroke = 3 })
		local status = Ui.text(frame, { name = "Status", text = "", color = MUTED, size = UDim2.new(1, -4, 0, 28), position = UDim2.new(0, 2, 1, -36), textSize = 20, stroke = 3 })
		local button = Ui.hit(frame, "Hit")
		Ui.juice(button, frame)
		button.Activated:Connect(function()
			remote:FireServer(order)
		end)
		table.insert(playtimeCards, { minutes = minutes, status = status, frame = frame })
	end
	task.spawn(function()
		while true do
			refreshPlaytime()
			if Windows.isOpen("Shop") then
				refreshShop()
			end
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
		if command == "wizardTalk" then
			Worlds.talk()
			return Worlds.debug()
		elseif command == "wizardAccept" then
			Worlds.accept()
			return true
		elseif command == "worldState" then
			return Worlds.debug()
		elseif command == "toggle" then
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
		elseif command == "others" then
			return Others.preview(arg)
		elseif command == "rank" then
			local rows = {}
			for _, row in rankRows do
				if row.frame.Visible then
					table.insert(rows, row.name.Text .. " | " .. row.power.Text .. " | " .. row.money.Text)
				end
			end
			return rows
		elseif command == "poseSync" then
			return Pose.syncDebug()
		elseif command == "auraState" then
			return Aura.debug()
		elseif command == "mountState" then
			return Mount.debug()
		elseif command == "dash" then
			Move.dash()
			return true
		elseif command == "camera" then
			-- prende a câmera em arg.from olhando para arg.to por arg.seconds (para capturas do mapa)
			local camera = workspace.CurrentCamera
			local finish = os.clock() + arg.seconds
			RunService:UnbindFromRenderStep("TestCamera")
			RunService:BindToRenderStep("TestCamera", Enum.RenderPriority.Camera.Value + 1, function()
				if os.clock() >= finish then
					RunService:UnbindFromRenderStep("TestCamera")
					camera.CameraType = Enum.CameraType.Custom
				else
					camera.CameraType = Enum.CameraType.Scriptable
					camera.CFrame = CFrame.lookAt(arg.from, arg.to)
				end
			end)
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
			backpackSell = backpackSell.Text,
			backpackFuse = backpackFuse.Text,
			rebirth = if Windows.isOpen("Rebirth") then rebirthLabels.need.Text else "",
			daily = if Windows.isOpen("Daily") then dailyButton.Text else "",
			quest = if Windows.isOpen("Daily") then questRows[1].button.Text .. " " .. questRows[1].progress.Text else "",
			potion = if Windows.isOpen("Shop") then potionCards.power.status.Text else "",
			playtime = if playtimeCards[1] then playtimeCards[1].status.Text else "",
			indexCards = #Config.Characters,
			indexFound = visible,
			indexCount = indexCount.Text,
		}
	end
end

function Menus.start()
	buildBackpack()
	buildAuras()
	buildMounts()
	buildRank()
	buildIndex()
	buildShop()
	buildRebirth()
	buildDaily()
	buildPlaytime()

	local buttons = { BackpackButton = "Backpack", ShopButton = "Shop", RebirthButton = "Rebirth", IndexButton = "Index", DailyButton = "Daily", PlaytimeButton = "Playtime", AuraButton = "Auras", MountButton = "Mounts", RankButton = "Players" }
	for button, window in buttons do
		Hud.onClick(button, function()
			Windows.toggle(window)
		end)
	end
	-- balcão de poções da casa de feitiçaria
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
		if prompt.Name == "PotionShop" and not Windows.isOpen("Shop") then
			Windows.toggle("Shop")
		end
	end)
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
