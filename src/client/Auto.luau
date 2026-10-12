--!strict
-- Automáticos do HUD (Config.Auto): AUTO CLICK soca o saco sozinho e AUTO SUPER acerta o super
-- soco sem minigame. Trancado, o botão abre a janela de compra (Game Pass ou dinheiro do jogo);
-- liberado, liga e desliga. O que está liberado vem do servidor, nos atributos Auto_<nome>.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local P = Config.Palette
local player = Players.LocalPlayer
local ON = Color3.fromRGB(60, 210, 90)
local OFF = Color3.fromRGB(24, 28, 46)
local LOCKED = Color3.fromRGB(90, 96, 120)
local MUTED = Color3.fromRGB(200, 215, 255)

local Auto = {}

local remote: RemoteEvent
local on: { [string]: boolean } = {}
local offered = Config.AutoOrder[1] -- qual automático a janela de compra está mostrando

local title: TextLabel
local info: TextLabel
local price: TextLabel
local passLabel: TextLabel

local function unlocked(name: string): boolean
	return player:GetAttribute("Auto_" .. name) == true
end

function Auto.isOn(name: string): boolean
	return on[name] == true and unlocked(name)
end

local function refresh()
	for _, name in Config.AutoOrder do
		local holder = Hud.gui():FindFirstChild("Auto" .. name, true)
		local label = holder and holder:FindFirstChild("Label")
		if holder and holder:IsA("Frame") and label and label:IsA("TextLabel") then
			local text = Config.Auto[name].label
			if not unlocked(name) then
				holder.BackgroundColor3 = LOCKED
				label.Text = "🔒 " .. text
			elseif on[name] then
				holder.BackgroundColor3 = ON
				label.Text = text .. ": ON"
			else
				holder.BackgroundColor3 = OFF
				label.Text = text .. ": OFF"
			end
		end
	end
	local item = Config.Auto[offered]
	title.Text = item.label
	info.Text = item.info
	price.Text = "$" .. Format.abbreviate(item.price)
	passLabel.Text = if item.passId > 0 then "GAME PASS" else "GAME PASS: SOON"
end

-- Liberado: liga ou desliga. Trancado: abre a janela de compra.
function Auto.toggle(name: string)
	if not Config.Auto[name] then
		return
	end
	if not unlocked(name) then
		offered = name
		refresh()
		Windows.set("Auto", true)
		return
	end
	on[name] = not on[name]
	remote:FireServer("toggle", name, on[name])
	refresh()
end

local function buyButton(window: Frame, name: string, y: number, color: Color3, action: () -> ()): TextLabel
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, y)
	button.Size = UDim2.fromOffset(300, 54)
	button.BackgroundColor3 = color
	button.Text = ""
	button.AutoButtonColor = false
	Ui.corner(button, 14)
	Ui.border(button, 4)
	Ui.juice(button)
	button.Activated:Connect(action)
	button.Parent = window
	return Ui.text(button, { name = "Label", text = "", size = UDim2.fromScale(1, 1), textSize = 24, stroke = 3 })
end

function Auto.start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Auto") :: RemoteEvent

	local window = Windows.create("Auto", "UNLOCK", Vector2.new(460, 330), ON, refresh)
	title = Ui.text(window, { name = "Name", text = "", color = P.yellowLine, size = UDim2.new(1, -40, 0, 36), position = UDim2.fromOffset(20, 44), textSize = 32, stroke = 4 })
	info = Ui.text(window, { name = "Info", text = "", color = MUTED, size = UDim2.new(1, -60, 0, 48), position = UDim2.fromOffset(30, 86), textSize = 19, stroke = 2 })
	info.TextWrapped = true
	price = buyButton(window, "Money", 150, ON, function()
		remote:FireServer("buy", offered)
	end)
	passLabel = buyButton(window, "Pass", 220, Color3.fromRGB(40, 130, 240), function()
		local passId = Config.Auto[offered].passId
		if passId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, passId)
		else
			Fx.toast("GAME PASS: COMING SOON!", P.yellowLine)
		end
	end)
	Ui.text(window, { name = "Hint", text = "Buy once, keep forever.", color = MUTED, size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 1, -34), textSize = 16, stroke = 2 })

	for _, name in Config.AutoOrder do
		Hud.onClick("Auto" .. name, function()
			Auto.toggle(name)
		end)
		player:GetAttributeChangedSignal("Auto_" .. name):Connect(function()
			-- acabou de liberar: fecha a janela e já deixa ligado
			if unlocked(name) and not on[name] then
				if Windows.isOpen("Auto") and offered == name then
					Windows.set("Auto", false)
				end
				Auto.toggle(name)
				Fx.toast(Config.Auto[name].label .. " UNLOCKED!", ON)
			elseif not unlocked(name) then
				on[name] = false
			end
			refresh()
		end)
	end
	refresh()
end

return Auto
