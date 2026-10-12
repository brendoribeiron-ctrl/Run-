-- Mede por 4 s a altura máxima e o maior deslocamento horizontal do jogador
-- (para conferir pulo duplo e dash feitos pelo teclado durante a medição).
--   node tools/bridge.cjs run server src/server/tests/apex.luau 20000

local Players = game:GetService("Players")

local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")

local start = root.Position
local maxRise, maxSlide, maxSpeed = 0, 0, 0
local finish = os.clock() + 4
while os.clock() < finish do
	local offset = root.Position - start
	maxRise = math.max(maxRise, offset.Y)
	maxSlide = math.max(maxSlide, Vector3.new(offset.X, 0, offset.Z).Magnitude)
	local velocity = root.AssemblyLinearVelocity
	maxSpeed = math.max(maxSpeed, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
	task.wait()
end
return string.format("subiu %.1f studs, deslizou %.1f studs, velocidade horizontal máxima %.0f", maxRise, maxSlide, maxSpeed)
