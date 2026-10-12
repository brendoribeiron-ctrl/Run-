-- Captura visual do dash no chão: anda para +Z (de lado para a câmera padrão) e dispara o dash depois de `0,6 s`.
--   node tools/bridge.cjs run server src/server/tests/fx_dash.luau
local Players = game:GetService("Players")
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]
local character = player.Character or player.CharacterAdded:Wait()
hook:Invoke("runFinish", player)
character:PivotTo(CFrame.new(-60, 4, 20))
task.wait(1)
hook:Invoke("ui", player, { command = "walk", arg = { direction = Vector3.zAxis, seconds = 1.6 } })
task.wait(0.6)
local from = character.HumanoidRootPart.Position
hook:Invoke("ui", player, { command = "dash" })
task.wait(0.9)
return string.format("dash disparado; andou %.1f studs em 0,9 s", (character.HumanoidRootPart.Position - from).Magnitude)
