--!strict
-- Pedestais do terreno: colocar e recolher personagens, renda por segundo e coleta no pad verde.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterModels = require(ReplicatedStorage.Shared.CharacterModels)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local State = require(script.Parent.State)

local P = Config.Palette
local Pedestals = {}

local function pedestalOf(plot: Model, slot: number): Model?
	local found = plot:FindFirstChild("Pedestal" .. slot)
	return if found and found:IsA("Model") then found else nil
end

local function setCashLabel(pedestal: Model, amount: number)
	local cash = pedestal:FindFirstChild("CashPad")
	local gui = cash and cash:FindFirstChild("Gui")
	local text = gui and gui:FindFirstChild("Amount")
	if text and text:IsA("TextLabel") then
		text.Text = "$" .. Format.abbreviate(amount)
	end
end

local function line(parent: Instance, text: string, color: Color3, height: number, order: number)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, height)
	t.LayoutOrder = order
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = P.outline
	stroke.Parent = t
	t.Parent = parent
end

-- Mostra (ou limpa, com entry = nil) o que está no pedestal.
local function render(plot: Model, slot: number, entry: { id: string, level: number }?, stored: number)
	local pedestal = pedestalOf(plot, slot)
	if not pedestal then
		return
	end
	local old = pedestal:FindFirstChild("Character")
	if old then
		old:Destroy()
	end
	local pad = pedestal.PrimaryPart :: BasePart
	local prompt = pad:FindFirstChild("Prompt")
	local cash = pedestal:FindFirstChild("CashPad")
	local gui = cash and cash:FindFirstChild("Gui")
	if cash and cash:IsA("BasePart") then
		cash.Transparency = if entry then 0 else 1
	end
	if gui and gui:IsA("SurfaceGui") then
		gui.Enabled = entry ~= nil
	end
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ActionText = if entry then "Pick Up" else "Place"
	end
	if not entry then
		return
	end

	local info = Config.CharacterById[entry.id]
	local model = CharacterModels.build(entry.id, 1.5)
	model.Name = "Character"
	model:PivotTo(CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)))

	local head = model:FindFirstChild("Head") :: BasePart
	local board = Instance.new("BillboardGui")
	board.Name = "Info"
	board.Size = UDim2.fromScale(9, 3.6)
	board.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	board.MaxDistance = 90
	board.Adornee = head
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = board
	line(board, info.name, Color3.fromRGB(255, 255, 255), 0.36, 1)
	line(board, string.upper(Config.Rarities[info.rarity].id), Config.Rarities[info.rarity].color, 0.28, 2)
	line(board, `Lv {entry.level}  ${Format.abbreviate(info.income * entry.level)}/s`, P.money, 0.34, 3)
	board.Parent = model

	model.Parent = pedestal
	setCashLabel(pedestal, stored)
end

local function collect(player: Player, slot: number)
	local profile = PlayerData.get(player)
	local plot = State.plot(player)
	local key = tostring(slot)
	if not profile or not plot then
		return
	end
	local amount = profile.stored[key] or 0
	if amount <= 0 or not profile.pedestals[key] then
		return
	end
	PlayerData.update(player, function(p)
		p.money += amount
		p.stored[key] = 0
	end)
	local pedestal = pedestalOf(plot, slot)
	if pedestal then
		setCashLabel(pedestal, 0)
		local cash = pedestal:FindFirstChild("CashPad") :: BasePart
		State.remotes.Fx:FireClient(player, "collected", amount, cash.Position)
	end
end

-- Coloca o personagem selecionado no pedestal, ou recolhe o que já está lá.
function Pedestals.interact(player: Player, slot: number): string?
	local profile = PlayerData.get(player)
	local plot = State.plot(player)
	local info = Config.Plot.pedestals[slot]
	if not profile or not plot or not info or info.locked then
		return nil
	end
	local key = tostring(slot)
	local entry = profile.pedestals[key]

	if entry then
		if #profile.inventory >= Config.Inventory.maxItems then
			State.remotes.Fx:FireClient(player, "toast", "Backpack is full!")
			return nil
		end
		collect(player, slot)
		PlayerData.update(player, function(p)
			p.pedestals[key] = nil
			p.stored[key] = nil
			table.insert(p.inventory, entry.id)
		end)
		player:SetAttribute("Selected", #profile.inventory)
		render(plot, slot, nil, 0)
		return "picked"
	end

	local selected = player:GetAttribute("Selected")
	if type(selected) ~= "number" or not profile.inventory[selected] then
		selected = #profile.inventory -- nada escolhido: usa o mais recente
	end
	local id = profile.inventory[selected]
	if not id then
		State.remotes.Fx:FireClient(player, "toast", "Run the hallway to get a character!")
		return nil
	end
	PlayerData.update(player, function(p)
		table.remove(p.inventory, selected)
		p.pedestals[key] = { id = id, level = 1 }
		p.stored[key] = 0
	end)
	player:SetAttribute("Selected", math.min(selected, #profile.inventory))
	render(plot, slot, profile.pedestals[key], 0)
	local pedestal = pedestalOf(plot, slot)
	if pedestal then
		State.remotes.Fx:FireAllClients("placed", pedestal)
	end
	return "placed"
end

-- Liga os pedestais do terreno ao dono que acabou de entrar.
function Pedestals.attach(player: Player, plot: Model)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for slot, info in Config.Plot.pedestals do
		local pedestal = pedestalOf(plot, slot)
		local prompt = pedestal and pedestal.PrimaryPart and pedestal.PrimaryPart:FindFirstChild("Prompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = not info.locked
		end
		local key = tostring(slot)
		render(plot, slot, profile.pedestals[key], profile.stored[key] or 0)
	end
end

function Pedestals.detach(plot: Model)
	for slot in Config.Plot.pedestals do
		local pedestal = pedestalOf(plot, slot)
		local prompt = pedestal and pedestal.PrimaryPart and pedestal.PrimaryPart:FindFirstChild("Prompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
		render(plot, slot, nil, 0)
	end
end

-- Um segundo de renda para todos os jogadores.
function Pedestals.tick()
	for id, player in State.owners do
		local profile = PlayerData.get(player)
		local plot = State.plots[id]
		if profile and next(profile.pedestals) then
			PlayerData.update(player, function(p)
				for key, entry in p.pedestals do
					p.stored[key] = (p.stored[key] or 0) + Config.CharacterById[entry.id].income * entry.level
				end
			end)
			for key in profile.pedestals do
				local pedestal = pedestalOf(plot, tonumber(key) :: number)
				if pedestal then
					setCashLabel(pedestal, profile.stored[key])
				end
			end
		end
	end
end

function Pedestals.connect()
	for id, plot in State.plots do
		for slot, info in Config.Plot.pedestals do
			local pedestal = pedestalOf(plot, slot)
			if not pedestal or info.locked then
				continue
			end
			local pad = pedestal.PrimaryPart :: BasePart
			local prompt = pad:FindFirstChild("Prompt") :: ProximityPrompt
			prompt.Triggered:Connect(function(player)
				if State.owners[id] == player then
					Pedestals.interact(player, slot)
				end
			end)
			local cash = pedestal:FindFirstChild("CashPad") :: BasePart
			cash.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if player and State.owners[id] == player then
					collect(player, slot)
				end
			end)
		end
	end

	State.remotes.Select.OnServerEvent:Connect(function(player, index)
		local profile = PlayerData.get(player)
		if not profile or type(index) ~= "number" or index % 1 ~= 0 then
			return
		end
		if index == 0 or profile.inventory[index] then
			player:SetAttribute("Selected", index)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			Pedestals.tick()
		end
	end)
end

return Pedestals
