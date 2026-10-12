-- Preparação para teste visual do terreno: dinheiro, inventário cheio de exemplos e 3 pedestais ocupados.
--   node tools/bridge.cjs run server src/server/tests/setup_plot.luau

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()

hook:Invoke("runFinish", player)
for slot = 1, 4 do
	if hook:Invoke("state", player).pedestals[tostring(slot)] then
		hook:Invoke("pedestal", player, slot)
	end
end
hook:Invoke("set", player, { money = 1200, inventory = { "storm_monk", "golden_gladiator", "abyss_titan", "rookie_jabber", "frost_hook", "turbo_sparrer" } })
for slot = 1, 3 do
	player:SetAttribute("Selected", 1)
	hook:Invoke("pedestal", player, slot)
end
for _ = 1, 5 do
	hook:Invoke("tick", player)
end

local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
local origin = plot:GetAttribute("Origin")
character:PivotTo(CFrame.lookAt((origin * CFrame.new(0, 4, -26)).Position, (origin * CFrame.new(0, 4, 10)).Position))
return "terreno montado: 3 pedestais ocupados, 3 personagens no hotbar"
