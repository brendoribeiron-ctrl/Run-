--!strict
-- Quem é admin (comandos de chat, laboratório de efeitos): todo mundo no Studio; no jogo
-- publicado, o dono, quem está em Config.Admins e, em jogo de grupo, quem tem o cargo de
-- Config.AdminGroupRank para cima. Usado pelo jogo e pelo laboratório (lab.project.json).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Admin = {}

local cache: { [number]: boolean } = {}

function Admin.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local cached = cache[player.UserId]
	if cached ~= nil then
		return cached
	end
	local admin = table.find(Config.Admins, player.UserId) ~= nil
	if not admin then
		if game.CreatorType == Enum.CreatorType.User then
			admin = player.UserId == game.CreatorId
		else
			-- consulta à Roblox: pode falhar; nesse caso não é admin agora e tenta de novo depois
			local ok, rank = pcall(function()
				return player:GetRankInGroup(game.CreatorId)
			end)
			if not ok then
				return false
			end
			admin = rank >= Config.AdminGroupRank
		end
	end
	cache[player.UserId] = admin
	return admin
end

return Admin
