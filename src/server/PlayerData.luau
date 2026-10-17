--!strict
-- Perfil do jogador: carrega, guarda em memória, espelha em atributos e salva com versão.
-- No Studio nada é lido nem gravado no DataStore.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local HudLayout = require(ReplicatedStorage.Shared.HudLayout)

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
	unlocks: { [string]: boolean }, -- automáticos de Config.Auto já liberados
	aura: string, -- id da aura equipada (Config.Auras); "" = nenhuma
	slots: number, -- quantos pedestais do terreno estão liberados
	levels: { [string]: number }, -- nível de cada personagem (vale para todas as cópias)
	mounts: { [string]: boolean }, -- montarias de Config.Mounts já compradas
	mount: string, -- id da montaria equipada ("" = a pé)
	rebirths: number,
	boosts: { [string]: number }, -- poções: id -> hora (do servidor) em que acaba
	daily: { streak: number, last: number }, -- recompensa diária: dia da sequência e o dia do último resgate
	quests: { day: number, progress: { [string]: number }, claimed: { [string]: boolean } },
	hud: string, -- layout do HUD escolhido no editor (JSON de Shared.HudLayout); "" = padrão
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
		unlocks = {},
		aura = "",
		slots = Config.Plot.freePedestals,
		levels = {},
		mounts = {},
		mount = "",
		rebirths = 0,
		boosts = {},
		daily = { streak = 0, last = 0 },
		quests = { day = 0, progress = {}, claimed = {} },
		hud = "",
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
	if type(raw.slots) == "number" then
		profile.slots = math.clamp(math.floor(raw.slots), Config.Plot.freePedestals, #Config.Plot.pedestals)
	end
	if type(raw.levels) == "table" then
		for id, level in raw.levels do
			if Config.CharacterById[id] and type(level) == "number" then
				profile.levels[id] = math.clamp(math.floor(level), 1, Config.Fighter.maxLevel)
			end
		end
	end
	if type(raw.rebirths) == "number" then
		profile.rebirths = math.clamp(math.floor(raw.rebirths), 0, Config.Rebirth.max)
	end
	if type(raw.boosts) == "table" then
		for id in Config.PotionById do
			if type(raw.boosts[id]) == "number" then
				profile.boosts[id] = raw.boosts[id]
			end
		end
	end
	if type(raw.daily) == "table" and type(raw.daily.streak) == "number" and type(raw.daily.last) == "number" then
		profile.daily = { streak = math.clamp(math.floor(raw.daily.streak), 0, Config.Daily.days), last = math.floor(raw.daily.last) }
	end
	if type(raw.quests) == "table" and type(raw.quests.day) == "number" then
		profile.quests.day = math.floor(raw.quests.day)
		for id, quest in Config.QuestById do
			local progress = type(raw.quests.progress) == "table" and raw.quests.progress[id]
			if type(progress) == "number" then
				profile.quests.progress[id] = math.clamp(math.floor(progress), 0, quest.goal)
			end
			if type(raw.quests.claimed) == "table" and raw.quests.claimed[id] == true then
				profile.quests.claimed[id] = true
			end
		end
	end
	if type(raw.mounts) == "table" then
		for _, info in Config.Mounts do
			if raw.mounts[info.id] == true then
				profile.mounts[info.id] = true
			end
		end
	end
	if type(raw.mount) == "string" and profile.mounts[raw.mount] then
		profile.mount = raw.mount
	end
	if type(raw.pedestals) == "table" then
		for key, entry in raw.pedestals do
			local slot = tonumber(key)
			if slot and Config.Plot.pedestals[slot] and type(entry) == "table" and Config.CharacterById[entry.id] then
				profile.pedestals[tostring(slot)] = { id = entry.id, level = 1 }
				-- save antigo com personagem num pedestal que hoje é pago: o pedestal continua dele
				profile.slots = math.max(profile.slots, slot)
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
	-- só vale a aura que o Poder já alcança (saves antigos começavam com a primeira equipada)
	if type(raw.aura) == "string" and Config.AuraById[raw.aura] and profile.power >= Config.AuraById[raw.aura].power then
		profile.aura = raw.aura
	end
	profile.hud = HudLayout.encode(HudLayout.decode(raw.hud))
	if type(raw.unlocks) == "table" then
		for name in Config.Auto do
			if raw.unlocks[name] == true then
				profile.unlocks[name] = true
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
	-- índice: ids já obtidos, na ordem do Config (a janela INDEX lê daqui)
	local found = {}
	for _, info in Config.Characters do
		if profile.index[info.id] then
			table.insert(found, info.id)
		end
	end
	player:SetAttribute("Index", table.concat(found, ","))
	for name in Config.Stats do
		player:SetAttribute("Stat_" .. name, profile.stats[name] or 0)
	end
	for name in Config.Auto do
		player:SetAttribute("Auto_" .. name, profile.unlocks[name] == true)
	end
	player:SetAttribute("Aura", profile.aura)
	player:SetAttribute("Pedestals", profile.slots)
	player:SetAttribute("Rebirths", profile.rebirths)
	-- poções: "id:fim,id:fim" (hora do servidor em que cada uma acaba)
	local boosts = {}
	for _, info in Config.Potions.list do
		if profile.boosts[info.id] then
			table.insert(boosts, info.id .. ":" .. math.floor(profile.boosts[info.id]))
		end
	end
	player:SetAttribute("Boosts", table.concat(boosts, ","))
	player:SetAttribute("Daily", profile.daily.streak .. ":" .. profile.daily.last)
	-- missões: "dia|id:progresso:resgatada,..."
	local quests = {}
	for _, quest in Config.Quests do
		table.insert(quests, `{quest.id}:{profile.quests.progress[quest.id] or 0}:{if profile.quests.claimed[quest.id] then 1 else 0}`)
	end
	player:SetAttribute("Quests", profile.quests.day .. "|" .. table.concat(quests, ","))
	local owned = {}
	for _, info in Config.Mounts do
		if profile.mounts[info.id] then
			table.insert(owned, info.id)
		end
	end
	player:SetAttribute("Mounts", table.concat(owned, ","))
	player:SetAttribute("Mount", profile.mount)
	-- níveis acima de 1, como "id:nível,id:nível" (a janela INDEX lê daqui)
	local levels = {}
	for _, info in Config.Characters do
		local level = profile.levels[info.id]
		if level and level > 1 then
			table.insert(levels, info.id .. ":" .. level)
		end
	end
	player:SetAttribute("Levels", table.concat(levels, ","))
	player:SetAttribute("HudLayout", profile.hud)
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

-- Volta o perfil ao de um jogador novo (comando de admin /reset).
function PlayerData.reset(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.profile = defaults()
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
