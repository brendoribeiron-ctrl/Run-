--!strict
-- Pedestais do terreno: liberar com dinheiro, colocar e recolher personagens, subir o nível
-- deles, renda por segundo e coleta de tudo num botão só.
--
-- Cada jogador tem o mesmo terreno em todos os mundos. Os dados são um só (o perfil); tudo o
-- que é mostrado (personagem no pedestal, preço, valor da coleta) é desenhado em todas as
-- cópias, e o jogador mexe na do mundo em que está.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterModels = require(ReplicatedStorage.Shared.CharacterModels)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local Progress = require(script.Parent.Progress)
local State = require(script.Parent.State)

local P = Config.Palette
local Pedestals = {}

-- Fração de dinheiro que sobrou do último segundo de cada pedestal. Com rendas pequenas, um
-- bônus de 15% sumiria no arredondamento; a sobra entra no segundo seguinte.
local leftover: { [Player]: { [string]: number } } = {}

local function pedestalOf(plot: Model, slot: number): Model?
	local found = plot:FindFirstChild("Pedestal" .. slot)
	return if found and found:IsA("Model") then found else nil
end

-- Soma do que todos os pedestais do jogador guardam.
local function total(profile: PlayerData.Profile): number
	local sum = 0
	for _, amount in profile.stored do
		sum += amount
	end
	return sum
end

-- Valor mostrado no botão de coleta do terreno (em todas as cópias dele).
local function setCashLabel(plot: Model, amount: number)
	for _, copy in State.copies(plot) do
		local pad = copy:FindFirstChild("Collect")
		local gui = pad and pad:FindFirstChild("Gui")
		local text = gui and gui:FindFirstChild("Amount")
		if text and text:IsA("TextLabel") then
			text.Text = "$" .. Format.abbreviate(amount)
		end
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

local function levelOf(profile: PlayerData.Profile, id: string): number
	return profile.levels[id] or 1
end

-- Mostra o estado do pedestal para o dono do terreno: trancado (com o preço no próximo a
-- liberar), vazio ou com o personagem. Sem perfil (terreno sem dono), fica vazio e desligado.
local function renderOne(plot: Model, slot: number, profile: PlayerData.Profile?)
	local pedestal = pedestalOf(plot, slot)
	if not pedestal then
		return
	end
	local old = pedestal:FindFirstChild("Character")
	if old then
		old:Destroy()
	end
	local pad = pedestal.PrimaryPart :: BasePart
	local prompt = pad:FindFirstChild("Prompt") :: ProximityPrompt
	local upgrade = pad:FindFirstChild("Upgrade") :: ProximityPrompt
	local lock = pad:FindFirstChild("Lock") :: BillboardGui
	local rim = pedestal:FindFirstChild("Rim") :: BasePart

	local key = tostring(slot)
	local entry = profile and profile.pedestals[key]
	local locked = profile ~= nil and slot > profile.slots
	local nextToUnlock = profile ~= nil and slot == profile.slots + 1
	local cost = Config.Plot.pedestals[slot].cost

	local accent = plot:GetAttribute("Accent")
	rim.Color = if locked then P.red elseif typeof(accent) == "Color3" then accent else P.cyan
	lock.Enabled = locked
	local price = lock:FindFirstChild("Price")
	if price and price:IsA("TextLabel") then
		price.Text = if nextToUnlock then "$" .. Format.abbreviate(cost) else ""
	end
	prompt.Enabled = profile ~= nil and (not locked or nextToUnlock)
	prompt.ActionText = if locked then `Unlock ${Format.abbreviate(cost)}` elseif entry then "Pick Up" else "Place"
	upgrade.Enabled = false
	if not profile or not entry then
		return
	end

	local info = Config.CharacterById[entry.id]
	local level = levelOf(profile, entry.id)
	local maxed = level >= Config.Fighter.maxLevel
	upgrade.Enabled = not maxed
	upgrade.ActionText = if maxed then "MAX" else `Level Up ${Format.abbreviate(Config.fighterCost(entry.id, level))}`

	local model = CharacterModels.build(entry.id, 1.5)
	model.Name = "Character"
	model:PivotTo(CFrame.new(pad.Position + Vector3.new(0, pad.Size.X / 2, 0))) -- cilindro em pé: X é a altura

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
	line(board, `Lv {level}{if maxed then " MAX" else ""}  ${Format.abbreviate(Config.fighterIncome(entry.id, level))}/s`, P.money, 0.34, 3)
	board.Parent = model

	model.Parent = pedestal
end

-- O mesmo pedestal em todas as cópias do terreno.
local function render(plot: Model, slot: number, profile: PlayerData.Profile?)
	for _, copy in State.copies(plot) do
		renderOne(copy, slot, profile)
	end
end

-- Recolhe de uma vez o dinheiro guardado em todos os pedestais. Devolve quanto pagou.
function Pedestals.collect(player: Player): number
	local profile = PlayerData.get(player)
	local plot = State.plot(player)
	if not profile or not plot then
		return 0
	end
	local amount = total(profile)
	if amount <= 0 then
		return 0
	end
	PlayerData.update(player, function(p)
		p.money += amount
		for key in p.stored do
			p.stored[key] = 0
		end
	end)
	setCashLabel(plot, 0)
	Progress.count(player, "collect", amount)
	local pad = plot:FindFirstChild("Collect")
	if pad and pad:IsA("BasePart") then
		State.remotes.Fx:FireClient(player, "collected", amount, pad.Position)
	end
	return amount
end

-- Libera o próximo pedestal trancado, cobrando o preço dele.
local function unlock(player: Player, profile: PlayerData.Profile, plot: Model, slot: number): string?
	if slot ~= profile.slots + 1 then
		State.remotes.Fx:FireClient(player, "toast", "Unlock the previous pedestal first!")
		return nil
	end
	local cost = Config.Plot.pedestals[slot].cost
	if profile.money < cost then
		State.remotes.Fx:FireClient(player, "toast", `Need ${Format.abbreviate(cost)}!`)
		return nil
	end
	PlayerData.update(player, function(p)
		p.money -= cost
		p.slots = slot
	end)
	render(plot, slot, profile)
	if Config.Plot.pedestals[slot + 1] then
		render(plot, slot + 1, profile) -- o seguinte passa a mostrar o preço
	end
	local pad = (pedestalOf(plot, slot) :: Model).PrimaryPart :: BasePart
	State.remotes.Fx:FireClient(player, "reveal", `PEDESTAL {slot} UNLOCKED!`, P.cyan, pad.Position + Vector3.new(0, 3, 0))
	return "unlocked"
end

-- Libera o pedestal trancado, coloca o personagem selecionado, ou recolhe o que já está lá.
function Pedestals.interact(player: Player, slot: number): string?
	local profile = PlayerData.get(player)
	local plot = State.plot(player)
	if not profile or not plot or not Config.Plot.pedestals[slot] then
		return nil
	end
	if slot > profile.slots then
		return unlock(player, profile, plot, slot)
	end
	local key = tostring(slot)
	local entry = profile.pedestals[key]

	if entry then
		if #profile.inventory >= Config.Inventory.maxItems then
			State.remotes.Fx:FireClient(player, "toast", "Backpack is full!")
			return nil
		end
		PlayerData.update(player, function(p)
			p.money += p.stored[key] or 0 -- o que este pedestal guardava vai junto
			p.pedestals[key] = nil
			p.stored[key] = nil
			table.insert(p.inventory, entry.id)
		end)
		player:SetAttribute("Selected", #profile.inventory)
		render(plot, slot, profile)
		setCashLabel(plot, total(profile))
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
	render(plot, slot, profile)
	local pedestal = pedestalOf(plot, slot)
	if pedestal then
		State.remotes.Fx:FireAllClients("placed", pedestal)
	end
	return "placed"
end

-- Sobe um nível do personagem que está no pedestal. O nível é do personagem (todas as cópias
-- dele sobem junto) e continua valendo depois de recolher.
function Pedestals.upgrade(player: Player, slot: number): boolean
	local profile = PlayerData.get(player)
	local plot = State.plot(player)
	local entry = profile and profile.pedestals[tostring(slot)]
	if not profile or not plot or not entry then
		return false
	end
	local level = levelOf(profile, entry.id)
	if level >= Config.Fighter.maxLevel then
		return false
	end
	local cost = Config.fighterCost(entry.id, level)
	if profile.money < cost then
		State.remotes.Fx:FireClient(player, "toast", `Need ${Format.abbreviate(cost)}!`)
		return false
	end
	PlayerData.update(player, function(p)
		p.money -= cost
		p.levels[entry.id] = level + 1
	end)
	-- todas as cópias dele nos outros pedestais mostram o nível novo
	for key, other in profile.pedestals do
		if other.id == entry.id then
			render(plot, tonumber(key) :: number, profile)
		end
	end
	local pad = (pedestalOf(plot, slot) :: Model).PrimaryPart :: BasePart
	State.remotes.Fx:FireClient(player, "reveal", `{string.upper(Config.CharacterById[entry.id].name)} Lv {level + 1}!`, P.money, pad.Position + Vector3.new(0, 6, 0))
	return true
end

-- Liga os pedestais do terreno ao dono que acabou de entrar.
function Pedestals.attach(player: Player, plot: Model)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for slot in Config.Plot.pedestals do
		render(plot, slot, profile)
	end
	setCashLabel(plot, total(profile))
end

-- Só esta cópia: quem chama passa por todas (ver detach em init.server.luau).
function Pedestals.detach(plot: Model)
	for slot in Config.Plot.pedestals do
		renderOne(plot, slot, nil)
	end
	setCashLabel(plot, 0)
end

-- Um segundo de renda para todos os jogadores.
function Pedestals.tick()
	for id, player in State.owners do
		local profile = PlayerData.get(player)
		local plot = State.plots[id]
		if profile and next(profile.pedestals) then
			local boost = Progress.moneyBoost(player, profile) -- rebirths e poção de dinheiro
			local rest = leftover[player] or {}
			leftover[player] = rest
			PlayerData.update(player, function(p)
				for key, entry in p.pedestals do
					local exact = Config.fighterIncome(entry.id, levelOf(p, entry.id)) * boost + (rest[key] or 0)
					local whole = math.floor(exact)
					rest[key] = exact - whole
					p.stored[key] = (p.stored[key] or 0) + whole
				end
			end)
			setCashLabel(plot, total(profile))
		end
	end
end

local function connectPlot(id: number, plot: Model)
	do
		for slot in Config.Plot.pedestals do
			local pedestal = pedestalOf(plot, slot)
			if not pedestal then
				continue
			end
			local pad = pedestal.PrimaryPart :: BasePart
			local prompt = pad:FindFirstChild("Prompt") :: ProximityPrompt
			prompt.Triggered:Connect(function(player)
				if State.owners[id] == player then
					Pedestals.interact(player, slot)
				end
			end)
			local upgrade = pad:FindFirstChild("Upgrade") :: ProximityPrompt
			upgrade.Triggered:Connect(function(player)
				if State.owners[id] == player then
					Pedestals.upgrade(player, slot)
				end
			end)
		end
		local pad = plot:FindFirstChild("Collect") :: BasePart
		pad.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player and State.owners[id] == player then
				Pedestals.collect(player)
			end
		end)
	end
end

function Pedestals.connect()
	for _, plots in State.worldPlots do
		for id, plot in plots do
			connectPlot(id, plot)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		leftover[player] = nil
	end)

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
