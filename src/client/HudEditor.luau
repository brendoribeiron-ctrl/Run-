--!strict
-- Editor do HUD (toque): o botão ⚙️ abre um modo em que o jogador arrasta cada bloco do HUD e o
-- botão de pular do Roblox, e muda o tamanho e a opacidade do bloco escolhido. DONE salva no
-- perfil (remote HudLayout); ao entrar, o layout volta pelo atributo "HudLayout". Os blocos e os
-- limites ficam em Shared.HudLayout.
--
-- Posição: deslocamento da posição padrão em fração da tela (vale em qualquer tamanho de tela).
-- Tamanho: atributo UserScale (Ui.autoScale multiplica); no botão de pular, o próprio Size.
-- Opacidade: cada transparência do bloco vira 1 - (1 - original) * opacidade. Quando outro código
-- muda uma transparência (ex.: a hotbar ao trocar de personagem), o novo valor vira o original.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local HudLayout = require(ReplicatedStorage.Shared.HudLayout)
local Hud = require(script.Parent.Hud)
local Platform = require(script.Parent.Platform)
local Ui = require(script.Parent.Ui)

local P = Config.Palette
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local HudEditor = {}

local layout: HudLayout.Layout = {}
local labels: { [string]: string } = {}
for _, block in HudLayout.BLOCKS do
	labels[block.id] = block.label
end

---------------------------------------------------------------------------------------------------
-- Escritas próprias: com sinais adiados, o aviso de mudança chega depois; o valor que nós mesmos
-- escrevemos fica guardado para não ser confundido com uma mudança de outro código.
--
-- O que fica guardado é o valor que o Roblox LEU de volta, não o que pedimos: transparência é
-- float32 (pedir 0.325 devolve 0.32499998...), e comparar com o número pedido nunca bate. Quando
-- não batia, a nossa própria escrita era tratada como mudança de outro código: o valor já
-- esmaecido virava o "original", era esmaecido de novo, e a opacidade só crescia até sumir.

-- tabelas normais (não fracas): o Roblox pode soltar chaves de Instance numa tabela fraca mesmo
-- com o objeto vivo. Cada objeto sai de todas quando é destruído (forget).
local written: { [Instance]: { [string]: any } } = {}
local forget: (Instance) -> ()
local watched: { [Instance]: boolean } = {}

local function remember(object: Instance)
	if not watched[object] then
		watched[object] = true
		object.Destroying:Connect(function()
			forget(object)
		end)
	end
end

local function write(object: Instance, prop: string, value: any)
	local mine = written[object]
	if not mine then
		mine = {}
		written[object] = mine
		remember(object)
	end
	(object :: any)[prop] = value
	mine[prop] = (object :: any)[prop] -- o que o Roblox guardou
end

-- Números de float32 vindos de contas em precisão dupla: igual dentro de uma folga minúscula.
local TOLERANCE = 1e-4

local function sameValue(a: any, b: any): boolean
	if type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) <= TOLERANCE
	end
	return a == b
end

local function isMine(object: Instance, prop: string): boolean
	local mine = written[object]
	return mine ~= nil and mine[prop] ~= nil and sameValue(mine[prop], (object :: any)[prop])
end

---------------------------------------------------------------------------------------------------
-- Opacidade

local FADE_PROPS: { [string]: { string } } = {
	Frame = { "BackgroundTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency" },
	TextBox = { "BackgroundTransparency", "TextTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	ViewportFrame = { "BackgroundTransparency", "ImageTransparency" },
	UIStroke = { "Transparency" },
}

local fadeBase: { [Instance]: { [string]: number } } = {}
local fadeRoot: { [Instance]: GuiObject } = {}
local fadeLevel: { [GuiObject]: number } = {}

local function fadeOne(object: Instance, prop: string)
	local root = fadeRoot[object]
	local base = fadeBase[object] and fadeBase[object][prop]
	if not root or base == nil then
		return
	end
	write(object, prop, 1 - (1 - base) * (fadeLevel[root] or 1))
end

local function track(object: Instance, root: GuiObject)
	local props = FADE_PROPS[object.ClassName]
	if not props or fadeRoot[object] then
		return
	end
	fadeRoot[object] = root
	remember(object)
	local bases = {}
	fadeBase[object] = bases
	for _, prop in props do
		bases[prop] = (object :: any)[prop]
		object:GetPropertyChangedSignal(prop):Connect(function()
			if not isMine(object, prop) then
				bases[prop] = (object :: any)[prop]
				fadeOne(object, prop)
			end
		end)
		fadeOne(object, prop)
	end
end

local function setOpacity(root: GuiObject, opacity: number)
	local first = fadeLevel[root] == nil
	if first and opacity >= 1 then
		return -- nunca mexido: nada a fazer
	end
	fadeLevel[root] = opacity
	if first then
		track(root, root)
		for _, object in root:GetDescendants() do
			track(object, root)
		end
		root.DescendantAdded:Connect(function(object)
			track(object, root)
		end)
	end
	for object, owner in fadeRoot do
		if owner == root then
			for prop in fadeBase[object] do
				fadeOne(object, prop)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Blocos

type Base = { position: UDim2, size: UDim2 }
local bases: { [GuiObject]: Base } = {}

function forget(object: Instance)
	watched[object] = nil
	written[object] = nil
	fadeBase[object] = nil
	fadeRoot[object] = nil
	fadeLevel[object :: any] = nil
	bases[object :: any] = nil
end

local apply: (string) -> ()

local function target(id: string): GuiObject?
	if id == "Jump" then
		local touch = playerGui:FindFirstChild("TouchGui")
		local frame = touch and touch:FindFirstChild("TouchControlFrame")
		local jump = frame and frame:FindFirstChild("JumpButton")
		return if jump and jump:IsA("GuiObject") then jump else nil
	end
	local gui = Hud.gui()
	local found = gui and gui:FindFirstChild(id)
	return if found and found:IsA("GuiObject") then found else nil
end

local function baseOf(id: string, object: GuiObject): Base
	local base = bases[object]
	if base then
		return base
	end
	local fresh: Base = { position = object.Position, size = object.Size }
	bases[object] = fresh
	remember(object)
	-- o Roblox recoloca o botão de pular quando a tela muda: o novo lugar vira o padrão
	for _, prop in { "Position", "Size" } do
		object:GetPropertyChangedSignal(prop):Connect(function()
			if not isMine(object, prop) then
				if prop == "Position" then
					fresh.position = object.Position
				else
					fresh.size = object.Size
				end
				apply(id)
			end
		end)
	end
	return fresh
end

function apply(id: string)
	local object = target(id)
	if not object then
		return
	end
	-- layout salvo é só do celular: no PC (sem editor) o HUD fica sempre no padrão
	local entry = (Platform.isTouch() and layout[id]) or HudLayout.default()
	local base = baseOf(id, object)
	write(object, "Position", base.position + UDim2.fromScale(entry.x, entry.y))
	if id == "Jump" then
		local s = base.size
		write(object, "Size", UDim2.new(s.X.Scale * entry.s, s.X.Offset * entry.s, s.Y.Scale * entry.s, s.Y.Offset * entry.s))
	else
		object:SetAttribute("UserScale", entry.s)
	end
	setOpacity(object, entry.o)
end

local function applyAll()
	for _, block in HudLayout.BLOCKS do
		apply(block.id)
	end
end

local function entryOf(id: string): HudLayout.Entry
	local entry = layout[id]
	if not entry then
		entry = HudLayout.default()
		layout[id] = entry
	end
	return entry
end

---------------------------------------------------------------------------------------------------
-- Interface do editor

local gui: ScreenGui
local gear: TextButton
local overlay: Frame
local panel: Frame
local selectedLabel: TextLabel
local handles: { [string]: Frame } = {}
local selected: string? = nil
local editing = false
local sliders: { () -> () } = {}

local function screenRect(object: GuiObject): (Vector2, Vector2)
	local position = object.AbsolutePosition
	local holder = object:FindFirstAncestorOfClass("ScreenGui")
	if holder and holder.IgnoreGuiInset then
		position -= GuiService:GetGuiInset() -- o editor não ignora a faixa do topo
	end
	return position, object.AbsoluteSize
end

local function select(id: string?)
	selected = id
	for name, handle in handles do
		local stroke = handle:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if name == id then P.yellowLine else Ui.white
			stroke.Thickness = if name == id then 4 else 2
		end
	end
	selectedLabel.Text = if id then labels[id] else "TAP A BLOCK"
	for _, refresh in sliders do
		refresh()
	end
end

-- Barra de arrastar: get devolve o valor atual (min..max), set grava.
local function slider(parent: Instance, y: number, title: string, min: number, max: number, get: () -> number?, set: (number) -> ())
	Ui.text(parent, { name = title, text = title, size = UDim2.fromOffset(110, 30), position = UDim2.fromOffset(16, y), textSize = 18, stroke = 2, align = Enum.TextXAlignment.Left })
	local value = Ui.text(parent, { name = title .. "Value", text = "", size = UDim2.fromOffset(60, 30), position = UDim2.new(1, -76, 0, y), textSize = 18, stroke = 2 })
	local track = Ui.frame(parent, title .. "Track", UDim2.new(1, -220, 0, 12), UDim2.fromOffset(130, y + 9), Color3.fromRGB(30, 34, 54))
	Ui.corner(track, 6)
	Ui.border(track, 2)
	local fill = Ui.frame(track, "Fill", UDim2.fromScale(0, 1), nil, P.cyan)
	Ui.corner(fill, 6)
	local knob = Ui.frame(track, "Knob", UDim2.fromOffset(28, 28), UDim2.fromScale(0, 0.5), Ui.white, Vector2.new(0.5, 0.5))
	Ui.corner(knob, 14)
	Ui.border(knob, 3)
	local hit = Ui.hit(track, "Hit")
	hit.Size = UDim2.new(1, 30, 0, 44)
	hit.Position = UDim2.new(0, -15, 0.5, -22)

	local function refresh()
		local current = get()
		local alpha = if current then (current - min) / (max - min) else 0
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		value.Text = if current then `{math.floor(current * 100 + 0.5)}%` else "-"
		knob.Visible = current ~= nil
	end
	table.insert(sliders, refresh)

	local active: InputObject? = nil
	local function move(x: number)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		set(min + (max - min) * alpha)
		refresh()
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			active = input
			move(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if active and (input == active or input.UserInputType == Enum.UserInputType.MouseMovement) then
			move(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == active or input.UserInputType == Enum.UserInputType.MouseButton1 then
			active = nil
		end
	end)
	refresh()
end

local function button(parent: Instance, name: string, text: string, color: Color3, x: number, width: number, y: number, onClick: () -> ())
	local holder = Ui.frame(parent, name, UDim2.fromOffset(width, 40), UDim2.fromOffset(x, y), color)
	Ui.corner(holder, 10)
	Ui.border(holder, 3)
	Ui.text(holder, { name = "Label", text = text, size = UDim2.fromScale(1, 1), textSize = 18, stroke = 2 })
	local hit = Ui.hit(holder, "Hit")
	Ui.juice(hit, holder)
	hit.Activated:Connect(onClick)
end

local dragging: { id: string, input: InputObject, start: Vector3, x: number, y: number }? = nil

local function makeHandle(id: string): Frame
	local handle = Ui.frame(overlay, "Handle_" .. id, UDim2.fromOffset(10, 10), nil, Ui.white)
	handle.BackgroundTransparency = 0.82
	handle.ZIndex = 5
	Ui.corner(handle, 8)
	Ui.border(handle, 2, Ui.white)
	local name = Ui.text(handle, { name = "Name", text = labels[id], size = UDim2.new(1, 0, 0, 22), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), textSize = 16, stroke = 2, z = 6 })
	name.ZIndex = 6
	local hit = Ui.hit(handle, "Hit")
	hit.ZIndex = 7
	hit.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		select(id)
		local entry = entryOf(id)
		dragging = { id = id, input = input, start = input.Position, x = entry.x, y = entry.y }
	end)
	return handle
end

local function placeHandles()
	for _, block in HudLayout.BLOCKS do
		local object = target(block.id)
		local handle = handles[block.id]
		if object and object.Visible then
			if not handle then
				handle = makeHandle(block.id)
				handles[block.id] = handle
			end
			local position, size = screenRect(object)
			handle.Position = UDim2.fromOffset(position.X, position.Y)
			handle.Size = UDim2.fromOffset(math.max(size.X, 40), math.max(size.Y, 40))
			handle.Visible = true
		elseif handle then
			handle.Visible = false
		end
	end
end

local function save()
	local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("HudLayout")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(HudLayout.encode(layout))
	end
end

function HudEditor.open(on: boolean)
	editing = on
	overlay.Visible = on
	panel.Visible = on
	gear.Visible = not on and Platform.isTouch()
	dragging = nil
	if on then
		select(nil)
		placeHandles()
	else
		layout = HudLayout.sanitize(layout)
		save()
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HudEditor"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- engrenagem: só no toque, embaixo dos botões do Roblox no canto de cima
	gear = Instance.new("TextButton")
	gear.Name = "Gear"
	gear.Size = UDim2.fromOffset(46, 46)
	gear.Position = UDim2.fromOffset(12, 8)
	gear.BackgroundColor3 = P.navy
	gear.BackgroundTransparency = 0.15
	gear.AutoButtonColor = false
	gear.Text = "⚙️"
	gear.TextScaled = true
	gear.Font = Enum.Font.FredokaOne
	gear.Parent = gui
	Ui.corner(gear, 12)
	Ui.border(gear, 3)
	gear.Activated:Connect(function()
		HudEditor.open(true)
	end)

	-- fundo escuro que segura os toques (os botões do HUD não disparam durante a edição)
	overlay = Ui.frame(gui, "Overlay", UDim2.fromScale(1, 1), nil, Color3.new(0, 0, 0))
	overlay.BackgroundTransparency = 0.55
	overlay.Active = true
	overlay.Visible = false
	local blocker = Ui.hit(overlay, "Blocker")
	blocker.ZIndex = 1
	blocker.Activated:Connect(function()
		select(nil)
	end)

	panel = Ui.frame(gui, "Panel", UDim2.fromOffset(470, 236), UDim2.new(0.5, 0, 0.5, 0), P.navy, Vector2.new(0.5, 0.5))
	panel.Visible = false
	panel.ZIndex = 20
	Ui.corner(panel, 16)
	Ui.border(panel, 4, P.yellowLine)
	Ui.autoScale(panel)
	Ui.text(panel, { name = "Title", text = "EDIT HUD", color = P.yellowLine, size = UDim2.new(1, 0, 0, 32), position = UDim2.fromOffset(0, 8), textSize = 26, stroke = 3 })
	Ui.text(panel, { name = "Help", text = "Drag a block to move it", color = Color3.fromRGB(200, 215, 255), size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 40), textSize = 15, stroke = 2 })
	selectedLabel = Ui.text(panel, { name = "Selected", text = "TAP A BLOCK", size = UDim2.new(1, 0, 0, 24), position = UDim2.fromOffset(0, 62), textSize = 20, stroke = 2 })
	slider(panel, 92, "SIZE", HudLayout.SIZE.min, HudLayout.SIZE.max, function()
		return if selected then entryOf(selected).s else nil
	end, function(value)
		if selected then
			entryOf(selected).s = value
			apply(selected)
		end
	end)
	slider(panel, 130, "OPACITY", HudLayout.OPACITY.min, HudLayout.OPACITY.max, function()
		return if selected then entryOf(selected).o else nil
	end, function(value)
		if selected then
			entryOf(selected).o = value
			apply(selected)
		end
	end)
	button(panel, "Reset", "RESET", Color3.fromRGB(70, 80, 120), 16, 130, 180, function()
		if selected then
			layout[selected] = nil
			apply(selected)
			select(selected)
		end
	end)
	button(panel, "ResetAll", "RESET ALL", Color3.fromRGB(200, 60, 70), 158, 150, 180, function()
		layout = {}
		applyAll()
		select(selected)
	end)
	button(panel, "Done", "DONE", Color3.fromRGB(40, 190, 70), 320, 134, 180, function()
		HudEditor.open(false)
	end)

	RunService.RenderStepped:Connect(function()
		if editing then
			placeHandles()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local drag = dragging
		if not drag or not (input == drag.input or input.UserInputType == Enum.UserInputType.MouseMovement) then
			return
		end
		local view = workspace.CurrentCamera.ViewportSize
		local delta = input.Position - drag.start
		local entry = entryOf(drag.id)
		entry.x = math.clamp(drag.x + delta.X / view.X, -1, 1)
		entry.y = math.clamp(drag.y + delta.Y / view.Y, -1, 1)
		apply(drag.id)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input == dragging.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
		end
	end)
end

---------------------------------------------------------------------------------------------------

function HudEditor.start()
	build()
	Platform.watch(function()
		gear.Visible = Platform.isTouch() and not editing
		if not editing then
			applyAll()
		end
	end)

	local function load()
		if editing then
			return
		end
		layout = HudLayout.decode(player:GetAttribute("HudLayout"))
		applyAll()
	end
	player:GetAttributeChangedSignal("HudLayout"):Connect(load)
	load()

	-- o botão de pular só existe no toque e aparece depois (e volta a ser criado às vezes)
	local function watchTouch(touch: Instance)
		if touch.Name ~= "TouchGui" then
			return
		end
		touch.DescendantAdded:Connect(function(object)
			if object.Name == "JumpButton" then
				task.defer(apply, "Jump")
			end
		end)
		task.defer(apply, "Jump")
	end
	playerGui.ChildAdded:Connect(watchTouch)
	local touch = playerGui:FindFirstChild("TouchGui")
	if touch then
		watchTouch(touch)
	end
end

-- Para os testes: estado de cada bloco.
function HudEditor.debug(): { [string]: any }
	local out: { [string]: any } = { platform = Platform.kind(), gear = gear.Visible, editing = editing, layout = HudLayout.encode(layout) }
	for _, block in HudLayout.BLOCKS do
		local object = target(block.id)
		if object then
			local position = object.Position
			out[block.id] = {
				x = position.X.Scale,
				y = position.Y.Scale,
				userScale = object:GetAttribute("UserScale"),
				opacity = fadeLevel[object] or 1,
				background = object.BackgroundTransparency,
			}
		end
	end
	return out
end

-- Para os testes: muda um bloco como se fosse arrastado/deslizado.
function HudEditor.set(id: string, entry: HudLayout.Entry)
	layout[id] = entry
	apply(id)
end

function HudEditor.save()
	layout = HudLayout.sanitize(layout)
	save()
end

return HudEditor
