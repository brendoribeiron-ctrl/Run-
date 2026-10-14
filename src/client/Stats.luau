--!strict
-- Árvore de skills (botão SKILLS do HUD): três ramos (velocidade, chance e dano de crítico),
-- cada um com um nó por nível. Os nós se ligam por linhas que acendem conforme o jogador
-- compra; uma barreira marca até onde dá para ir antes do mundo 2. Clicar num nó escolhe o
-- ramo (o cartão da esquerda mostra o efeito e o preço); clicar no próximo nó do ramo compra.
-- A compra é um pedido ao servidor, que só conhece o nível de cada ramo.
-- A árvore fica à direita e o cartão no alto à esquerda: com a câmera do painel, a cabeça do
-- boneco cobre o canto de baixo à esquerda da janela.
-- A árvore é maior que a janela dela: dá para segurar e arrastar (ou rolar a roda do mouse), e
-- os três botões em cima do cartão levam direto a cada ramo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local P = Config.Palette
local player = Players.LocalPlayer

local Stats = {}

local ICONS = { speed = "👟", critChance = "🎯", critDamage = "💥" }
local COLORS = { speed = Color3.fromRGB(60, 200, 255), critChance = Color3.fromRGB(255, 196, 46), critDamage = Color3.fromRGB(255, 90, 70) }

-- Desenho de um ramo, de baixo para cima: coluna (-1, 0, 1) e linha de cada nó, e quais nós
-- cada linha liga. Os losangos são só desenho: a compra segue a ordem dos números.
local LAYOUT = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { -1, 3 }, { 1, 3 }, { 0, 4 }, { 0, 5 }, { -1, 6 }, { 1, 6 }, { 0, 7 } }
local EDGES = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 3, 5 }, { 4, 6 }, { 5, 6 }, { 6, 7 }, { 7, 8 }, { 7, 9 }, { 8, 10 }, { 9, 10 } }
local KEYSTONE = { [6] = true, [10] = true } -- nós maiores, no fecho de cada losango
local TREE = Vector2.new(438, 440) -- tamanho do desenho da árvore, antes do zoom
local VIEW = Vector2.new(416, 440) -- janela por onde se vê a árvore
local ZOOM = 1.8 -- quanto o desenho é ampliado dentro da janela
local DRAG = 1.5 -- pixels do desenho por pixel de tela ao arrastar
local WHEEL = 70 -- pixels por passo da roda do mouse
local COLUMNS = { 75, 219, 363 } -- centro de cada ramo
local STEP = Vector2.new(44, 45) -- distância entre colunas e entre linhas de um ramo
local BASE_Y = 398 -- altura da primeira linha de nós
local TRUNK_Y = 424
local GATE_GAP = 22 -- folga a mais entre o último nó do mundo 1 e o seguinte, para a barreira caber
local GATE_ROW = LAYOUT[Config.statCap(Config.StatOrder[1], 0)][2] -- linha do último nó do mundo 1

local DIM_LINE = Color3.fromRGB(56, 78, 140)
local DIM_NODE = Color3.fromRGB(16, 24, 52)
local DIM_EDGE = Color3.fromRGB(74, 96, 150)
local GOLD = Color3.fromRGB(255, 228, 130)
local LAVA = Config.Worlds[2].color

type Node = { button: TextButton, icon: TextLabel, stroke: UIStroke, ring: Frame, ringStroke: UIStroke }
type Branch = { nodes: { Node }, edges: { { line: Frame, to: number } }, title: TextLabel, count: TextLabel }

local branches: { [string]: Branch } = {}
local gate: Frame
local detail: { icon: TextLabel, name: TextLabel, level: TextLabel, effect: TextLabel, next: TextLabel, fill: Frame, frame: Frame, border: UIStroke, button: TextButton, action: TextLabel, price: TextLabel }
local selected = Config.StatOrder[1]
local content: Frame
local pan = Vector2.zero -- posição do desenho dentro da janela (sempre negativa ou zero)
local tabs: { [string]: UIStroke } = {}

local function setPan(to: Vector2)
	local size = TREE * ZOOM
	pan = Vector2.new(math.clamp(to.X, VIEW.X - size.X, 0), math.clamp(to.Y, VIEW.Y - size.Y, 0))
	content.Position = UDim2.fromOffset(pan.X, pan.Y)
end

local function levelOf(name: string): number
	local value = player:GetAttribute("Stat_" .. name)
	return if type(value) == "number" then value else 0
end

local function effectText(name: string, level: number): string
	local stat = Config.Stats[name]
	if name == "speed" then
		return `{Config.Move.walk + level * stat.perLevel} walk speed`
	elseif name == "critChance" then
		return `{math.floor((Config.Crit.baseChance + level * stat.perLevel) * 1000 + 0.5) / 10}% crit chance`
	end
	return `x{Config.Crit.baseMultiplier + level * stat.perLevel} crit power`
end

-- Até que nível o ramo vai com os rebirths de agora (antes do mundo 2, só uma parte).
local function capOf(name: string): number
	local rebirths = player:GetAttribute("Rebirths")
	return Config.statCap(name, if type(rebirths) == "number" then rebirths else 0)
end

local function refresh()
	local money = player:GetAttribute("Money")
	local cash = if type(money) == "number" then money else 0
	local anyGated = false
	for name, branch in branches do
		local stat = Config.Stats[name]
		local level = levelOf(name)
		local cap = capOf(name)
		local color = COLORS[name]
		anyGated = anyGated or cap < stat.max
		branch.count.Text = `{level}/{stat.max}`
		branch.title.TextTransparency = if name == selected then 0 else 0.35
		tabs[name].Color = if name == selected then Color3.new(1, 1, 1) else P.outline
		for index, node in branch.nodes do
			local owned = index <= level
			local gated = index > cap
			local nextUp = index == level + 1 and not gated
			node.button.BackgroundColor3 = if owned then color elseif gated then Color3.fromRGB(26, 16, 18) else DIM_NODE
			node.stroke.Color = if owned then GOLD elseif nextUp then color elseif gated then LAVA:Lerp(Color3.new(0, 0, 0), 0.55) else DIM_EDGE
			node.stroke.Thickness = if owned or nextUp then 3 else 2
			node.icon.TextTransparency = if owned or nextUp then 0 elseif gated then 0.72 else 0.5
			node.ring.Visible = nextUp
			node.ringStroke.Color = if cash >= Config.statCost(name, level) then Color3.fromRGB(110, 255, 140) else color
		end
		for _, edge in branch.edges do
			local lit = level >= edge.to
			edge.line.BackgroundColor3 = if lit then color else DIM_LINE
			edge.line.ZIndex = if lit then 2 else 1
		end
	end
	gate.Visible = anyGated

	local stat = Config.Stats[selected]
	local level = levelOf(selected)
	local maxed = level >= stat.max
	local capped = not maxed and level >= capOf(selected)
	local cost = Config.statCost(selected, level)
	local color = COLORS[selected]
	detail.icon.Text = ICONS[selected]
	detail.icon.BackgroundColor3 = color
	detail.name.Text = stat.label
	detail.name.TextColor3 = color
	detail.level.Text = `NODE {level} / {stat.max}`
	detail.effect.Text = effectText(selected, level)
	detail.next.Text = if maxed then "" else "▼  " .. effectText(selected, level + 1)
	detail.fill.Size = UDim2.fromScale(level / stat.max, 1)
	detail.fill.BackgroundColor3 = color
	detail.border.Color = color
	detail.action.Text = if maxed then "COMPLETE" elseif capped then "LOCKED" else "UNLOCK"
	detail.price.Text = if maxed then "MAX" elseif capped then Config.Worlds[2].name else "$" .. Format.abbreviate(cost)
	detail.button.BackgroundColor3 = if maxed or capped then Color3.fromRGB(90, 96, 120) elseif cash >= cost then Color3.fromRGB(60, 210, 90) else Color3.fromRGB(190, 60, 60)
end

-- Linha entre dois pontos: uma barra fina girada.
local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3): Frame
	local delta = b - a
	local f = Ui.frame(parent, "Line", UDim2.fromOffset(delta.Magnitude, thickness), UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2), color, Vector2.new(0.5, 0.5))
	f.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	Ui.corner(f, thickness)
	return f
end

local function nodeAt(column: number, index: number): Vector2
	local spot = LAYOUT[index]
	return Vector2.new(column + spot[1] * STEP.X, BASE_Y - spot[2] * STEP.Y - (if spot[2] > GATE_ROW then GATE_GAP else 0))
end

local function buildBranch(tree: Frame, remote: RemoteEvent, name: string, column: number)
	local stat = Config.Stats[name]
	local color = COLORS[name]
	local branch: Branch = { nodes = {}, edges = {}, title = nil :: any, count = nil :: any }

	branch.title = Ui.text(tree, { name = name .. "Title", text = stat.label, color = color, size = UDim2.fromOffset(140, 18), position = UDim2.fromOffset(column, 4), anchor = Vector2.new(0.5, 0), textSize = 15, stroke = 2, z = 4 })
	branch.title.Font = Enum.Font.GothamBlack
	branch.count = Ui.text(tree, { name = name .. "Count", text = "0/0", color = Color3.fromRGB(190, 205, 240), size = UDim2.fromOffset(80, 14), position = UDim2.fromOffset(column, 22), anchor = Vector2.new(0.5, 0), textSize = 13, stroke = 2, z = 4 })

	-- do tronco até o primeiro nó
	line(tree, Vector2.new(column, TRUNK_Y), nodeAt(column, 1), 3, GOLD:Lerp(DIM_LINE, 0.4))
	for _, pair in EDGES do
		local l = line(tree, nodeAt(column, pair[1]), nodeAt(column, pair[2]), 4, DIM_LINE)
		table.insert(branch.edges, { line = l, to = pair[2] })
	end

	for index in LAYOUT do
		local at = nodeAt(column, index)
		local size = if KEYSTONE[index] then 42 else 34
		-- anel que pulsa em volta do próximo nó
		local ring = Ui.frame(tree, "Ring", UDim2.fromOffset(size + 12, size + 12), UDim2.fromOffset(at.X, at.Y), nil, Vector2.new(0.5, 0.5))
		ring.ZIndex = 3
		ring.Visible = false
		Ui.corner(ring, size)
		local ringStroke = Ui.border(ring, 3, color)
		TweenService:Create(ringStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85 }):Play()

		local button = Instance.new("TextButton")
		button.Name = name .. index
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromOffset(at.X, at.Y)
		button.Size = UDim2.fromOffset(size, size)
		button.BackgroundColor3 = DIM_NODE
		button.Text = ""
		button.AutoButtonColor = false
		button.ZIndex = 5
		Ui.corner(button, size)
		local stroke = Ui.border(button, 2, DIM_EDGE)
		Ui.juice(button)
		local icon = Ui.text(button, { name = "Icon", text = ICONS[name], size = UDim2.fromScale(1, 1), textSize = if KEYSTONE[index] then 22 else 17, stroke = 0, z = 6 })
		button.Activated:Connect(function()
			selected = name
			if index == levelOf(name) + 1 then
				remote:FireServer(name)
			end
			refresh()
		end)
		button.Parent = tree
		table.insert(branch.nodes, { button = button, icon = icon, stroke = stroke, ring = ring, ringStroke = ringStroke })
	end
	branches[name] = branch
end

-- Escolhe o ramo e leva a janela até a base dele.
function Stats.focus(name: string)
	local index = table.find(Config.StatOrder, name)
	if not index then
		return
	end
	selected = name
	setPan(Vector2.new(VIEW.X / 2 - COLUMNS[index] * ZOOM, -math.huge))
	refresh()
end

local function build(remote: RemoteEvent)
	local window = Windows.create("Skills", "SKILL TREE", Vector2.new(660, 500), P.cyan, refresh)

	local view = Ui.frame(window, "Tree", UDim2.fromOffset(VIEW.X, VIEW.Y), UDim2.fromOffset(230, 46), Color3.fromRGB(8, 13, 34))
	view.ClipsDescendants = true
	view.Active = true
	Ui.border(view, 2, Color3.fromRGB(50, 80, 150))
	local tree = Ui.frame(view, "Content", UDim2.fromOffset(TREE.X, TREE.Y))
	local zoom = Instance.new("UIScale")
	zoom.Scale = ZOOM
	zoom.Parent = tree
	content = tree

	-- segurar e arrastar move o desenho; a roda do mouse sobe e desce
	local dragging = false
	local last = Vector2.zero
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	view.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			last = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	view.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			setPan(pan + Vector2.new(0, input.Position.Z * WHEEL))
		elseif dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local now = Vector2.new(input.Position.X, input.Position.Y)
			setPan(pan + (now - last) * DRAG)
			last = now
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			dragging = false
		end
	end)
	-- malha de fundo, bem apagada
	for x = 44, TREE.X - 1, 44 do
		Ui.frame(tree, "Grid", UDim2.new(0, 1, 1, 0), UDim2.fromOffset(x, 0), Color3.fromRGB(120, 160, 255)).BackgroundTransparency = 0.9
	end
	for y = 44, TREE.Y - 1, 44 do
		Ui.frame(tree, "Grid", UDim2.new(1, 0, 0, 1), UDim2.fromOffset(0, y), Color3.fromRGB(120, 160, 255)).BackgroundTransparency = 0.9
	end

	-- tronco: liga os três ramos por baixo, com o núcleo no meio
	line(tree, Vector2.new(COLUMNS[1], TRUNK_Y), Vector2.new(COLUMNS[#COLUMNS], TRUNK_Y), 3, GOLD:Lerp(DIM_LINE, 0.4))
	local core = Ui.frame(tree, "Core", UDim2.fromOffset(16, 16), UDim2.fromOffset(COLUMNS[2], TRUNK_Y), GOLD, Vector2.new(0.5, 0.5))
	core.Rotation = 45
	core.ZIndex = 4
	Ui.border(core, 2, Color3.fromRGB(120, 80, 10))

	for index, name in Config.StatOrder do
		buildBranch(tree, remote, name, COLUMNS[index])
	end

	-- barreira do mundo 2: tracejado entre o último nó liberado no mundo 1 e o seguinte
	local gateY = BASE_Y - GATE_ROW * STEP.Y - (STEP.Y + GATE_GAP) / 2
	gate = Ui.frame(tree, "Gate", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, gateY), nil, Vector2.new(0, 0.5))
	gate.ZIndex = 3
	for x = 10, TREE.X - 20, 18 do
		local dash = Ui.frame(gate, "Dash", UDim2.fromOffset(10, 3), UDim2.new(0, x, 0.5, 0), LAVA, Vector2.new(0, 0.5))
		dash.ZIndex = 3
	end
	for _, x in { (COLUMNS[1] + COLUMNS[2]) / 2, (COLUMNS[2] + COLUMNS[3]) / 2 } do
		local tag = Ui.text(gate, { name = "Tag", text = "🔒 " .. Config.Worlds[2].name, color = Color3.fromRGB(255, 220, 190), size = UDim2.fromOffset(96, 20), position = UDim2.new(0, x, 0.5, 0), anchor = Vector2.new(0.5, 0.5), textSize = 12, stroke = 0, z = 4 })
		tag.Font = Enum.Font.GothamBlack
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = Color3.fromRGB(70, 24, 12)
		Ui.corner(tag, 10)
		Ui.border(tag, 2, LAVA)
	end

	-- um botão por ramo: escolhe e leva a janela até ele
	for index, statName in Config.StatOrder do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab" .. statName
		tab.Position = UDim2.fromOffset(14 + (index - 1) * 71, 46)
		tab.Size = UDim2.fromOffset(64, 44)
		tab.BackgroundColor3 = COLORS[statName]
		tab.Font = Enum.Font.FredokaOne
		tab.Text = ICONS[statName]
		tab.TextSize = 28
		tab.AutoButtonColor = false
		Ui.corner(tab, 12)
		tabs[statName] = Ui.border(tab, 3)
		Ui.juice(tab)
		tab.Activated:Connect(function()
			Stats.focus(statName)
		end)
		tab.Parent = window
	end

	-- cartão do ramo escolhido
	local bar = Ui.frame(window, "Detail", UDim2.fromOffset(206, 232), UDim2.fromOffset(14, 98), Color3.fromRGB(22, 30, 62))
	Ui.corner(bar, 12)
	local border = Ui.border(bar, 3, P.cyan)
	local icon = Ui.text(bar, { name = "Icon", text = "", size = UDim2.fromOffset(52, 52), position = UDim2.fromOffset(10, 10), textSize = 32, stroke = 3 })
	icon.BackgroundTransparency = 0
	Ui.corner(icon, 12)
	Ui.border(icon, 3)
	local name = Ui.text(bar, { name = "Name", text = "", size = UDim2.new(1, -74, 0, 28), position = UDim2.fromOffset(70, 10), stroke = 3, align = Enum.TextXAlignment.Left })
	local level = Ui.text(bar, { name = "Level", text = "", color = Color3.fromRGB(190, 205, 240), size = UDim2.new(1, -74, 0, 18), position = UDim2.fromOffset(70, 42), textSize = 15, stroke = 2, align = Enum.TextXAlignment.Left })
	level.Font = Enum.Font.GothamBlack
	local track = Ui.frame(bar, "Bar", UDim2.new(1, -28, 0, 12), UDim2.fromOffset(14, 74), Color3.fromRGB(10, 12, 24))
	Ui.corner(track, 5)
	Ui.border(track, 2)
	local fill = Ui.frame(track, "Fill", UDim2.fromScale(0, 1), nil, P.cyan)
	Ui.corner(fill, 5)
	local effect = Ui.text(bar, { name = "Effect", text = "", size = UDim2.new(1, -12, 0, 24), position = UDim2.fromOffset(6, 96), textSize = 20, stroke = 2 })
	local nextEffect = Ui.text(bar, { name = "Next", text = "", color = Color3.fromRGB(110, 255, 140), size = UDim2.new(1, -12, 0, 24), position = UDim2.fromOffset(6, 122), textSize = 20, stroke = 2 })

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -10)
	button.Size = UDim2.fromOffset(182, 64)
	button.BackgroundColor3 = Color3.fromRGB(60, 210, 90)
	button.Text = ""
	button.AutoButtonColor = false
	Ui.corner(button, 14)
	Ui.border(button, 4)
	Ui.juice(button)
	local action = Ui.text(button, { name = "Action", text = "UNLOCK", size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 6), textSize = 20, stroke = 3 })
	local price = Ui.text(button, { name = "Price", text = "$0", color = P.yellowLine, size = UDim2.new(1, 0, 0, 28), position = UDim2.fromOffset(0, 30), textSize = 25, stroke = 3 })
	button.Activated:Connect(function()
		remote:FireServer(selected)
	end)
	button.Parent = bar

	-- dica embaixo do cartão (a cabeça do boneco pode cobrir: nada aqui é necessário)
	local hint = Ui.text(window, { name = "Hint", text = "Hold and drag to move the tree. Click the glowing node to unlock it.", color = Color3.fromRGB(150, 170, 215), size = UDim2.fromOffset(206, 50), position = UDim2.fromOffset(14, 336), textSize = 14, stroke = 0 })
	hint.TextWrapped = true

	detail = { icon = icon, name = name, level = level, effect = effect, next = nextEffect, fill = fill, frame = bar, border = border, button = button, action = action, price = price }
	Stats.focus(selected)
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
	player:GetAttributeChangedSignal("Rebirths"):Connect(onChange)
	for name in Config.Stats do
		player:GetAttributeChangedSignal("Stat_" .. name):Connect(onChange)
	end
end

return Stats
