-- Toca um golpe do golem no laboratório, com a câmera fixa num ângulo.
--   BRIDGE_PORT=34875 node tools/bridge.cjs run server lab/server/tests/fx.luau 60000 <golpe> [mundo] [vista]
--   golpe: Stomp, Sweep, Slam, Charge, Pulse, Wake, Death, All (todos os golpes em sequência)
--   mundo: 1 (arcano) ou 2 (magma)
--   vista: side, front, wide, top, close, free (câmera do jogador)
-- Junto, para capturar: powershell -File tools\screenshot.ps1 -Window VfxLab -Out shots\lab\x.png -Count 40 -IntervalMs 100
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Anims = require(ReplicatedStorage.Shared.GolemAnims)

local args = HttpService:JSONDecode(script.Parent:GetAttribute("Args") or "[]")
local clip = args[1] or "Slam"
local world = tonumber(args[2]) or 1
local view = args[3] or "side"

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local remote = ReplicatedStorage:WaitForChild("Lab")

local list = if clip == "All" then { "Stomp", "Sweep", "Slam", "Charge", "Pulse" } else { clip }
local began = os.clock()
local log = {}
for _, name in list do
	local data = Anims.clips[name]
	if not data then
		return "golpe desconhecido: " .. name
	end
	table.insert(log, string.format("%.2f %s", os.clock() - began, name))
	remote:FireClient(player, "play", name, world, view)
	-- a morte ainda desmorona e o golem volta inteiro depois
	task.wait(data.length + (if name == "Death" then 4.5 else 1.2))
end
return table.concat(log, " | ")
