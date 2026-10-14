--!strict
-- Progressão além do saco e das paredes: rebirth, poções (bônus com tempo), recompensa diária,
-- recompensas por tempo de jogo, missões do dia, fusão de personagens e bônus de amigos.
-- Também é daqui que saem os multiplicadores de Poder, dinheiro e sorte que o resto do
-- servidor aplica. Os números ficam em Config (Rebirth, Potions, Daily, Playtime, Quests,
-- Fusion, Friends).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local State = require(script.Parent.State)

local Progress = {}

local joinedAt: { [Player]: number } = {}
local friendBoost: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function toast(player: Player, text: string)
	State.remotes.Fx:FireClient(player, "toast", text)
end

---------------------------------------------------------------------------------------------------
-- Multiplicadores

local function potion(profile: PlayerData.Profile, kind: string): number
	local expires = profile.boosts[kind]
	local info = Config.PotionById[kind]
	return if info and expires and expires > now() then info.multiplier else 1
end

-- Ganho de Poder: rebirths, poção e amigos no servidor (a aura entra à parte, em init).
function Progress.powerBoost(player: Player, profile: PlayerData.Profile): number
	return (1 + profile.rebirths * Config.Rebirth.powerPerRebirth) * potion(profile, "power") * (1 + (friendBoost[player] or 0))
end

-- Renda dos pedestais.
function Progress.moneyBoost(_player: Player, profile: PlayerData.Profile): number
	return (1 + profile.rebirths * Config.Rebirth.moneyPerRebirth) * potion(profile, "money")
end

-- Sorte do sorteio de personagem no fim da corrida.
function Progress.luckBoost(_player: Player, profile: PlayerData.Profile): number
	return potion(profile, "luck")
end

---------------------------------------------------------------------------------------------------
-- Rebirth

-- Poder exigido para o próximo rebirth: a última parede do mundo em que o jogador está na
-- progressão (ver Config.rebirthCost).
function Progress.rebirthCost(rebirths: number): number
	return Config.rebirthCost(rebirths)
end

-- Zera Poder, dinheiro (o do bolso e o guardado nos pedestais) e o saco, em troca de mais um
-- rebirth. Personagens, pedestais, níveis, montarias e skills ficam.
function Progress.rebirth(player: Player): boolean
	local profile = PlayerData.get(player)
	if not profile then
		return false
	end
	if profile.rebirths >= Config.Rebirth.max then
		toast(player, "Max rebirths reached!")
		return false
	end
	local cost = Progress.rebirthCost(profile.rebirths)
	if profile.power < cost then
		toast(player, `Need {Format.abbreviate(cost)} Power to rebirth!`)
		return false
	end
	PlayerData.update(player, function(p)
		p.rebirths += 1
		p.power = 0
		p.money = 0
		p.bagLevel = 1
		p.aura = ""
		for key in p.stored do
			p.stored[key] = 0
		end
	end)
	State.remotes.Fx:FireClient(player, "reveal", `REBIRTH {profile.rebirths}!`, Color3.fromRGB(255, 90, 180), nil)
	return true
end

---------------------------------------------------------------------------------------------------
-- Poções

-- Compra uma poção: liga o bônus ou soma tempo ao que já está correndo (até o teto).
function Progress.buyPotion(player: Player, id: any): boolean
	local profile = PlayerData.get(player)
	local info = if type(id) == "string" then Config.PotionById[id] else nil
	if not profile or not info then
		return false
	end
	local t = now()
	local left = math.max((profile.boosts[info.id] or 0) - t, 0)
	if left + info.seconds > Config.Potions.maxSeconds then
		toast(player, "That potion is already full!")
		return false
	end
	if profile.money < info.price then
		toast(player, `Need ${Format.abbreviate(info.price)}!`)
		return false
	end
	PlayerData.update(player, function(p)
		p.money -= info.price
		p.boosts[info.id] = t + left + info.seconds
	end)
	toast(player, `{info.name}: {math.floor((left + info.seconds) / 60)} min!`)
	return true
end

---------------------------------------------------------------------------------------------------
-- Recompensa diária (sequência de 7 dias) e por tempo de jogo

local function today(): number
	return math.floor(now() / 86400)
end

local function scaled(profile: PlayerData.Profile, amount: number): number
	return math.floor(amount * (1 + profile.rebirths * Config.Rebirth.rewardPerRebirth))
end

-- Uma vez por dia. Faltou um dia, a sequência recomeça; depois do 7º, volta ao 1º.
function Progress.claimDaily(player: Player): number?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local day = today()
	if profile.daily.last >= day then
		toast(player, "Come back tomorrow!")
		return nil
	end
	local streak = if profile.daily.last == day - 1 then profile.daily.streak % #Config.Daily.rewards + 1 else 1
	local amount = scaled(profile, Config.Daily.rewards[streak])
	PlayerData.update(player, function(p)
		p.daily.streak = streak
		p.daily.last = day
		p.money += amount
	end)
	toast(player, `DAY {streak}: +${Format.abbreviate(amount)}`)
	return amount
end

-- Segundos jogados nesta sessão.
function Progress.played(player: Player): number
	return now() - (joinedAt[player] or now())
end

function Progress.claimPlaytime(player: Player, index: any): number?
	local profile = PlayerData.get(player)
	local reward = if type(index) == "number" then Config.Playtime.rewards[index] else nil
	local minutes = if type(index) == "number" then Config.Playtime.minutes[index] else nil
	if not profile or not reward or not minutes then
		return nil
	end
	local claimed = player:GetAttribute("PlaytimeClaimed")
	local list = if type(claimed) == "string" and claimed ~= "" then string.split(claimed, ",") else {}
	if table.find(list, tostring(index)) then
		return nil
	end
	if Progress.played(player) < minutes * 60 then
		toast(player, "Not ready yet!")
		return nil
	end
	local amount = scaled(profile, reward)
	table.insert(list, tostring(index))
	player:SetAttribute("PlaytimeClaimed", table.concat(list, ","))
	PlayerData.update(player, function(p)
		p.money += amount
	end)
	toast(player, `PLAYTIME: +${Format.abbreviate(amount)}`)
	return amount
end

---------------------------------------------------------------------------------------------------
-- Missões do dia

local function rollQuests(profile: PlayerData.Profile)
	if profile.quests.day ~= today() then
		profile.quests.day = today()
		table.clear(profile.quests.progress)
		table.clear(profile.quests.claimed)
	end
end

-- Soma progresso numa missão (socos, paredes quebradas, super socos, dinheiro recolhido).
function Progress.count(player: Player, id: string, amount: number)
	local profile = PlayerData.get(player)
	local quest = Config.QuestById[id]
	if not profile or not quest or amount <= 0 then
		return
	end
	if profile.quests.day == today() and (profile.quests.progress[id] or 0) >= quest.goal then
		return -- já completa: não precisa replicar de novo a cada soco
	end
	PlayerData.update(player, function(p)
		rollQuests(p)
		p.quests.progress[id] = math.min((p.quests.progress[id] or 0) + amount, quest.goal)
	end)
end

function Progress.claimQuest(player: Player, id: any): number?
	local profile = PlayerData.get(player)
	local quest = if type(id) == "string" then Config.QuestById[id] else nil
	if not profile or not quest then
		return nil
	end
	if profile.quests.day ~= today() or (profile.quests.progress[quest.id] or 0) < quest.goal or profile.quests.claimed[quest.id] then
		return nil
	end
	local amount = scaled(profile, quest.reward)
	PlayerData.update(player, function(p)
		p.quests.claimed[quest.id] = true
		p.money += amount
	end)
	toast(player, `QUEST DONE: +${Format.abbreviate(amount)}`)
	return amount
end

---------------------------------------------------------------------------------------------------
-- Fusão: três iguais viram um Shiny (mesma raridade, renda multiplicada)

function Progress.fuse(player: Player, index: any): string?
	local profile = PlayerData.get(player)
	if not profile or type(index) ~= "number" or index % 1 ~= 0 then
		return nil
	end
	local id = profile.inventory[index]
	local info = id and Config.CharacterById[id]
	if not id or not info or info.shiny then
		return nil
	end
	local need = Config.Fusion.count
	local owned = 0
	for _, other in profile.inventory do
		if other == id then
			owned += 1
		end
	end
	if owned < need then
		toast(player, `Need {need} {info.name} to fuse!`)
		return nil
	end
	local shiny = id .. Config.Fusion.suffix
	PlayerData.update(player, function(p)
		-- o escolhido vira o Shiny no mesmo lugar; os outros saem do fim da mochila
		p.inventory[index] = shiny
		local removed = 1
		for i = #p.inventory, 1, -1 do
			if removed >= need then
				break
			end
			if p.inventory[i] == id then
				table.remove(p.inventory, i)
				removed += 1
			end
		end
	end)
	local at = table.find(profile.inventory, shiny) or 0
	player:SetAttribute("Selected", at)
	State.remotes.Fx:FireClient(player, "reveal", string.upper(Config.CharacterById[shiny].name) .. "!", Color3.fromRGB(255, 215, 70), nil)
	return shiny
end

---------------------------------------------------------------------------------------------------
-- Amigos no servidor: cada um soma um pouco de Poder, até o teto

local function refreshFriends()
	local list = Players:GetPlayers()
	for _, player in list do
		task.spawn(function()
			local count = 0
			for _, other in list do
				if other ~= player then
					local ok, friends = pcall(function()
						return player:IsFriendsWith(other.UserId)
					end)
					if ok and friends then
						count += 1
					end
				end
			end
			if player.Parent then
				local boost = math.min(count * Config.Friends.perFriend, Config.Friends.max)
				friendBoost[player] = boost
				player:SetAttribute("FriendBoost", boost)
			end
		end)
	end
end

function Progress.join(player: Player)
	joinedAt[player] = now()
	player:SetAttribute("JoinedAt", joinedAt[player])
	player:SetAttribute("PlaytimeClaimed", "")
	player:SetAttribute("FriendBoost", 0)
	PlayerData.update(player, rollQuests)
	refreshFriends()
end

function Progress.leave(player: Player)
	joinedAt[player] = nil
	friendBoost[player] = nil
	task.defer(refreshFriends)
end

-- Só para os testes: finge que o jogador entrou há \`seconds\` segundos.
function Progress.setPlayed(player: Player, seconds: number)
	joinedAt[player] = now() - seconds
	player:SetAttribute("JoinedAt", joinedAt[player])
end

return Progress
