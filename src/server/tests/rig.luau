-- Tipo de rig do avatar do primeiro jogador e as juntas que ele tem.
--   node tools/bridge.cjs run server src/server/tests/rig.luau

local Players = game:GetService("Players")

local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local names = {}
for _, descendant in character:GetDescendants() do
	if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
		table.insert(names, descendant.ClassName .. " " .. descendant.Name)
	end
end
table.sort(names)
return humanoid.RigType.Name .. ": " .. table.concat(names, ", ")
