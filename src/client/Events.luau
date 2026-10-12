--!strict
-- Efeitos pedidos pelo servidor pelo remote Fx: revelação, coleta de dinheiro, personagem colocado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Fx = require(script.Parent.Fx)
local Ui = require(script.Parent.Ui)

local Events = {}

-- Personagem estala no pedestal (0,2 s) com duas nuvens brancas aos lados.
local function placed(pedestal: Instance)
	local model = pedestal:WaitForChild("Character", 2)
	if not model or not model:IsA("Model") then
		return
	end
	local full = model:GetScale()
	local pivot = model:GetPivot()
	for _, side in { -1, 1 } do
		Fx.burst(pivot.Position + Vector3.new(side * 3.5, 2.5, 0), Ui.white, 7, 0.4)
	end
	Fx.shake(0.25)
	local began = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - began) / 0.25, 0, 1)
		if not model.Parent then
			connection:Disconnect()
			return
		end
		-- passa do tamanho e volta (Back Out)
		local overshoot = 1 + 2.2 * (alpha - 1) ^ 3 + 1.2 * (alpha - 1) ^ 2
		model:ScaleTo(full * math.max(0.15, overshoot))
		if alpha >= 1 then
			model:ScaleTo(full)
			connection:Disconnect()
		end
	end)
end

function Events.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
		if kind == "reveal" then
			Fx.reveal(a, b, c)
		elseif kind == "toast" then
			Fx.toast(a)
		elseif kind == "collected" then
			Fx.cubes(b + Vector3.new(0, 1, 0), Config.Palette.yellowLine, 12, 22, Vector3.new(0, 18, 0), 0.8, Enum.Material.Neon)
			Fx.toast("+$" .. Format.abbreviate(a), Config.Palette.money)
		elseif kind == "placed" then
			placed(a)
		end
	end)
end

return Events
