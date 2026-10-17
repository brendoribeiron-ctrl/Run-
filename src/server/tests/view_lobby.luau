-- Passeio de câmera pelo gramado para capturas: casa de feitiçaria (de fora, de perto, por
-- dentro) e o terreno do jogador com os pedestais. Cada vista fica parada 5 segundos.
--   node tools/bridge.cjs run server src/server/tests/view_lobby.luau 60000
--   powershell -File tools\screenshot.ps1 -Out shots\lobby.png -Count 8 -IntervalMs 5000 -DelayMs 3500

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()

local G = Config.World.groundY
local c = Vector3.new(Config.Sanctum.center.X, G, Config.Sanctum.center.Y)
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
local home = (plot:GetAttribute("Origin") :: CFrame).Position

-- { câmera, alvo, onde o boneco fica }
local shots = {
	{ c + Vector3.new(40, 30, 150), c + Vector3.new(0, 55, 0), c + Vector3.new(14, 4, 60) }, -- de longe, do lado dos terrenos
	{ c + Vector3.new(-95, 16, 70), c + Vector3.new(0, 40, 0), c + Vector3.new(-50, 4, 40) }, -- de quina
	{ c + Vector3.new(6, 9, 62), c + Vector3.new(0, 16, 30), c + Vector3.new(4, 4, 50) }, -- porta, de perto
	{ c + Vector3.new(2, 9, 4), c + Vector3.new(-14, 6, -14), c + Vector3.new(8, 6, 10) }, -- balcão de poções
	{ home + Vector3.new(0, 26, -46), home + Vector3.new(0, 2, 8), home + Vector3.new(0, 4, -20) }, -- terreno, de cima
	{ home + Vector3.new(-2, 7, -14), home + Vector3.new(-18, 3, 6), home + Vector3.new(-6, 4, -8) }, -- pedestais, de perto
	{ c + Vector3.new(69, 5, 64), c + Vector3.new(60, 3, 60), c + Vector3.new(60, 6, 60) }, -- skate
	{ c + Vector3.new(69, 5, 64), c + Vector3.new(60, 3, 60), c + Vector3.new(60, 6, 60) }, -- tapete
}
for index, shot in shots do
	-- nas duas últimas vistas o boneco aparece montado (skate, depois tapete)
	local mount = if index == #shots - 1 then "hoverboard" elseif index == #shots then "carpet" else nil
	if mount then
		hook:Invoke("set", player, { mounts = { hoverboard = true, carpet = true }, mount = "" })
		hook:Invoke("mount", player, mount)
		player:SetAttribute("Riding", true)
	end
	character:PivotTo(CFrame.new(shot[3]))
	hook:Invoke("ui", player, { command = "camera", arg = { from = shot[1], to = shot[2], seconds = 5 } })
	task.wait(5)
end
return #shots .. " vistas"
