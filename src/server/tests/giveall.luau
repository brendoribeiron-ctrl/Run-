-- Dá um de cada personagem, todas as auras, skills no máximo, dinheiro e Poder ao primeiro jogador
-- (o mesmo que digitar /giveall no chat, no Studio).
--   node tools/bridge.cjs run server src/server/tests/giveall.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1]

local count = hook:Invoke("giveAll", player)
local state = hook:Invoke("state", player)
assert(count == #Config.Characters, `esperava {#Config.Characters}, vieram {count}`)
for _, info in Config.Characters do
	assert(table.find(state.inventory, info.id), "faltou " .. info.id)
	assert(state.index[info.id] == true, "índice sem " .. info.id)
end
local lastWalls = Config.Worlds[#Config.Worlds].walls
assert(state.power >= lastWalls[#lastWalls].power * 4, "poder não foi ao máximo: " .. tostring(state.power))
for _, aura in Config.Auras do
	assert(state.power >= aura.power, "aura trancada: " .. aura.id)
	assert(hook:Invoke("auraEquip", player, aura.id) == true, "não equipou " .. aura.id)
end
hook:Invoke("auraEquip", player, Config.Auras[1].id)
for name, stat in Config.Stats do
	assert(state.stats[name] == stat.max and player:GetAttribute("Stat_" .. name) == stat.max, "skill abaixo do máximo: " .. name)
end
assert(state.money >= 1_000_000_000_000, "dinheiro não foi ao máximo: " .. tostring(state.money))
return `{count} personagens no inventário, índice completo, {#Config.Auras} auras liberadas, skills no máximo, Poder {state.power}, dinheiro {state.money}`
