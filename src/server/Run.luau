--!strict
-- Carga e corrida. O servidor mede a carga pelo próprio relógio, calcula quantas paredes
-- quebram, sorteia o personagem e só manda o resultado: o cliente apenas encena.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RunMath = require(ReplicatedStorage.Shared.RunMath)
local PlayerData = require(script.Parent.PlayerData)
local State = require(script.Parent.State)

local Run = {}

type Session = {
	chargeStart: number,
	running: boolean,
	reward: string?,
}

export type Result = {
	charge: number,
	broken: number,
	runTime: number,
	characterId: string,
	isNew: boolean,
}

local sessions: { [Player]: Session } = {}
local rng = Random.new()

local function inZone(player: Player): boolean
	local root = State.root(player)
	if not root then
		return false
	end
	local run = Config.Run
	local margin = 4
	return math.abs(root.Position.X - run.zoneCenter.X) <= run.zoneSize.X / 2 + margin
		and math.abs(root.Position.Z - run.zoneCenter.Z) <= run.zoneSize.Y / 2 + margin
end

function Run.isBusy(player: Player): boolean
	return sessions[player] ~= nil
end

-- Raridade a partir do tier da última parede quebrada; depois um personagem daquela raridade.
function Run.rollCharacter(broken: number): string
	local tier, luck = 1, 1
	local weights: { number } = table.create(#Config.Rarities, 0)
	if broken == 0 then
		weights[1] = 1
	else
		local wall = Config.Walls[broken]
		tier, luck = wall.tier, wall.luck
		local roll = Config.Roll
		local lower = if tier > 1 then tier - 1 else tier
		local higher = if tier < #Config.Rarities then tier + 1 else tier
		weights[tier] += roll.sameWeight
		weights[lower] += roll.lowerWeight
		weights[higher] += math.min(roll.higherWeight * luck, roll.higherCap)
	end

	local total = 0
	for _, weight in weights do
		total += weight
	end
	local pick = rng:NextNumber() * total
	local rarity = tier
	for index, weight in weights do
		pick -= weight
		if pick <= 0 and weight > 0 then
			rarity = index
			break
		end
	end

	local pool = {}
	for _, info in Config.Characters do
		if info.rarity == rarity then
			table.insert(pool, info.id)
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

function Run.start(player: Player): boolean
	if sessions[player] or not PlayerData.get(player) or not inZone(player) then
		return false
	end
	sessions[player] = { chargeStart = os.clock(), running = false }
	return true
end

function Run.cancel(player: Player)
	local session = sessions[player]
	if session and not session.running then
		sessions[player] = nil
	end
end

-- Entrega o personagem sorteado. Inventário cheio vira dinheiro.
local function grant(player: Player, characterId: string)
	local info = Config.CharacterById[characterId]
	PlayerData.update(player, function(profile)
		profile.index[characterId] = true
		if #profile.inventory < Config.Inventory.maxItems then
			table.insert(profile.inventory, characterId)
			player:SetAttribute("Selected", #profile.inventory)
		else
			profile.money += info.income * Config.Inventory.sellSeconds
		end
	end)
end

-- Fim da corrida: entrega a recompensa e devolve o jogador ao terreno.
function Run.finish(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	if session.reward then
		grant(player, session.reward)
	end
	local plot = State.plot(player)
	local character = player.Character
	if plot and character and character.Parent then
		character:PivotTo(State.spawnCFrame(plot))
	end
end

-- chargeOverride só é usado pelos testes.
function Run.release(player: Player, chargeOverride: number?): Result?
	local session = sessions[player]
	local profile = PlayerData.get(player)
	if not session or session.running or not profile then
		return nil
	end
	local run = Config.Run
	local charge = chargeOverride or math.clamp((os.clock() - session.chargeStart) / run.chargeTime, 0, 1)
	if charge < run.minCharge or not inZone(player) then
		sessions[player] = nil
		return nil
	end

	local broken = RunMath.wallsBroken(RunMath.effectivePower(profile.power, charge))
	local runTime = RunMath.stopStuds(broken) / run.speed
	local characterId = Run.rollCharacter(broken)
	local result: Result = {
		charge = charge,
		broken = broken,
		runTime = runTime,
		characterId = characterId,
		isNew = profile.index[characterId] ~= true,
	}

	session.running = true
	session.reward = characterId
	task.delay(runTime + run.returnDelay, function()
		if sessions[player] == session then
			Run.finish(player)
		end
	end)
	return result
end

function Run.connect()
	State.remotes.Charge.OnServerEvent:Connect(function(player, action)
		if action == "start" then
			if not Run.start(player) then
				State.remotes.RunResult:FireClient(player, nil)
			end
		elseif action == "release" then
			State.remotes.RunResult:FireClient(player, Run.release(player))
		elseif action == "cancel" then
			Run.cancel(player)
		end
	end)
end

return Run
