--!strict
-- Perfil do jogador: carrega, guarda em memória, espelha em atributos e salva com versão.
-- No Studio nada é lido nem gravado no DataStore.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

export type Profile = {
	version: number,
	power: number,
	money: number,
	bagLevel: number,
	inventory: { string }, -- ids de personagem carregados (hotbar + mochila)
	pedestals: { [string]: { id: string, level: number } }, -- chave = índice do pedestal
	stored: { [string]: number }, -- dinheiro acumulado em cada pedestal
	index: { [string]: boolean }, -- personagens já obtidos
	stats: { [string]: number }, -- nível de cada atributo de Config.Stats
}

type Session = {
	profile: Profile,
	loaded: boolean, -- false = a leitura falhou; nunca salvar por cima
	dirty: boolean,
}

local PlayerData = {}

local USE_STORE = not RunService:IsStudio()
local sessions: { [Player]: Session } = {}

local function defaults(): Profile
	return {
		version = Config.DataVersion,
		power = 0,
		money = 0,
		bagLevel = 1,
		inventory = {},
		pedestals = {},
		stored = {},
		index = {},
		stats = {},
	}
end

local function sanitize(raw: any): Profile
	local profile = defaults()
	if type(raw) ~= "table" then
		return profile
	end
	if type(raw.power) == "number" and raw.power >= 0 then
		profile.power = math.floor(raw.power)
	end
	if type(raw.money) == "number" and raw.money >= 0 then
		profile.money = math.floor(raw.money)
	end
	if type(raw.bagLevel) == "number" then
		profile.bagLevel = math.clamp(math.floor(raw.bagLevel), 1, #Config.Bag.levels)
	end
	-- só entram personagens que ainda existem no Config
	if type(raw.inventory) == "table" then
		for _, id in raw.inventory do
			if Config.CharacterById[id] and #profile.inventory < Config.Inventory.maxItems then
				table.insert(profile.inventory, id)
			end
		end
	end
	if type(raw.pedestals) == "table" then
		for key, entry in raw.pedestals do
			local slot = tonumber(key)
			local info = slot and Config.Plot.pedestals[slot]
			if info and not info.locked and type(entry) == "table" and Config.CharacterById[entry.id] then
				profile.pedestals[tostring(slot)] = { id = entry.id, level = if type(entry.level) == "number" then math.max(1, math.floor(entry.level)) else 1 }
			end
		end
	end
	if type(raw.stored) == "table" then
		for key, amount in raw.stored do
			if profile.pedestals[tostring(key)] and type(amount) == "number" and amount >= 0 then
				profile.stored[tostring(key)] = math.floor(amount)
			end
		end
	end
	if type(raw.stats) == "table" then
		for name, stat in Config.Stats do
			local level = raw.stats[name]
			if type(level) == "number" then
				profile.stats[name] = math.clamp(math.floor(level), 0, stat.max)
			end
		end
	end
	if type(raw.index) == "table" then
		for id, seen in raw.index do
			if Config.CharacterById[id] and seen == true then
				profile.index[id] = true
			end
		end
	end
	return profile
end

local function getStore(): DataStore
	return DataStoreService:GetDataStore(Config.DataStoreName)
end

local function mirror(player: Player, profile: Profile)
	player:SetAttribute("Power", profile.power)
	player:SetAttribute("Money", profile.money)
	player:SetAttribute("BagLevel", profile.bagLevel)
	player:SetAttribute("Inventory", table.concat(profile.inventory, ","))
	for name in Config.Stats do
		player:SetAttribute("Stat_" .. name, profile.stats[name] or 0)
	end
end

function PlayerData.load(player: Player): boolean
	local session: Session = { profile = defaults(), loaded = true, dirty = false }
	if USE_STORE then
		local ok, result
		for attempt = 1, 3 do
			ok, result = pcall(function()
				return getStore():GetAsync("p_" .. player.UserId)
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
		if ok then
			session.profile = sanitize(result)
		else
			warn(`[PlayerData] falha ao carregar {player.Name}: {result}`)
			session.loaded = false
		end
	end
	if player.Parent ~= Players then
		return false
	end
	sessions[player] = session
	mirror(player, session.profile)
	return session.loaded
end

function PlayerData.get(player: Player): Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

-- Aplica uma mudança no perfil e replica os atributos.
function PlayerData.update(player: Player, change: (Profile) -> ())
	local session = sessions[player]
	if not session then
		return
	end
	change(session.profile)
	session.dirty = true
	mirror(player, session.profile)
end

function PlayerData.save(player: Player)
	local session = sessions[player]
	if not session or not session.loaded or not session.dirty or not USE_STORE then
		return
	end
	local snapshot = table.clone(session.profile)
	local ok, err = pcall(function()
		getStore():UpdateAsync("p_" .. player.UserId, function()
			return snapshot
		end)
	end)
	if ok then
		session.dirty = false
	else
		warn(`[PlayerData] falha ao salvar {player.Name}: {err}`)
	end
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	sessions[player] = nil
end

function PlayerData.start()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for player in sessions do
				task.spawn(PlayerData.save, player)
			end
		end
	end)
	game:BindToClose(function()
		for player in sessions do
			task.spawn(PlayerData.save, player)
		end
		if USE_STORE then
			task.wait(2)
		end
	end)
end

return PlayerData
