-- Faz o personagem andar sozinho 120 studs pelo gramado, para ver a corrida sem teclado.
--   node tools/bridge.cjs run server src/server/tests/walk.luau

local Players = game:GetService("Players")

local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")

character:PivotTo(CFrame.new(-60, 4, 20))
task.wait(0.3)
humanoid:MoveTo(root.Position + Vector3.new(120, 0, 0))
return "andando de " .. tostring(root.Position)
