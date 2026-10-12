--!strict
-- Contas da corrida usadas pelo servidor (decisão) e pelo cliente (prévia na barra de carga).

local Config = require(script.Parent.Config)

local RunMath = {}

-- Carga baixa aproveita só parte do Poder; 100% usa tudo.
function RunMath.effectivePower(power: number, charge: number): number
	return math.floor(power * (0.4 + 0.6 * math.clamp(charge, 0, 1)))
end

function RunMath.wallsBroken(effective: number): number
	local count = 0
	for _, wall in Config.Walls do
		if effective < wall.power then
			break
		end
		count += 1
	end
	return count
end

-- Distância em studs até onde a corrida termina.
function RunMath.stopStuds(broken: number): number
	local walls = Config.Walls
	local run = Config.Run
	if broken < #walls then
		return walls[broken + 1].distance / run.metersPerStud
	end
	return walls[#walls].distance / run.metersPerStud + run.endPadding * 0.6
end

function RunMath.wallStuds(index: number): number
	return Config.Walls[index].distance / Config.Run.metersPerStud
end

-- Tier (índice de raridade) do Poder atual: o da parede mais forte que ele quebra com carga cheia.
function RunMath.powerTier(power: number): number
	local broken = RunMath.wallsBroken(power)
	return if broken == 0 then 0 else Config.Walls[broken].tier
end

return RunMath
