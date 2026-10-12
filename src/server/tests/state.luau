-- Estado do primeiro jogador, para conferir o que um teste manual (cliques) produziu.
--   node tools/bridge.cjs run server src/server/tests/state.luau

local Players = game:GetService("Players")

local player = Players:GetPlayers()[1]
if not player then
	return "sem jogador"
end
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
return `Power={player:GetAttribute("Power")} Money={player:GetAttribute("Money")} BagLevel={player:GetAttribute("BagLevel")} Plot={player:GetAttribute("PlotId")} Pos={root and root.Position}`
