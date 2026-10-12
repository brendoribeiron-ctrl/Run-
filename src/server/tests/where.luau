-- Onde o boneco está, o que há embaixo dele e a distância até o ponto de nascer do terreno.
--   node tools/bridge.cjs run server src/server/tests/where.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
local spawn = (plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset)).Position
local params = RaycastParams.new()
params.FilterDescendantsInstances = { character }
local below = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), params)
local lines = {}
for i = 1, 4 do
	table.insert(lines, string.format("t%d pos=(%.1f, %.1f, %.1f) vel=%.1f", i, root.Position.X, root.Position.Y, root.Position.Z, root.AssemblyLinearVelocity.Magnitude))
	task.wait(0.5)
end
return string.format("nascer=(%.1f, %.1f, %.1f) dist=%.1f embaixo=%s | ", spawn.X, spawn.Y, spawn.Z, (root.Position - spawn).Magnitude, if below then below.Instance:GetFullName() else "nada") .. table.concat(lines, " ; ")
