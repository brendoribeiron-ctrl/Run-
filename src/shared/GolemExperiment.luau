--!strict
-- EXPERIMENTOS de golpes do golem: cada golpe pode ter uma versão nova, com animação própria
-- (tools/blender/golem_v2.py -> src/shared/GolemAnimsV2.luau) e efeitos próprios
-- (src/client/BossFx<Clip>.luau), ligada por uma chave em Config.Boss. Este módulo põe os clips
-- ligados dentro de GolemAnims e diz qual clip cada golpe toca; com a chave desligada nada muda.
-- Servidor (Boss.luau) e cliente (Boss.luau) exigem este módulo.
-- Método e armadilhas: skill roblox-boss-attack-overhaul.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local Config = require(ReplicatedStorage.Shared.Config)

local GolemExperiment = {}

-- golpe -> chave em Config.Boss e clip novo
GolemExperiment.LIST = {
	Slam = { flag = "slamV2", clip = "SlamV2" },
	Charge = { flag = "chargeV2", clip = "ChargeV2" },
}

local playing: { [string]: string } = {}
local v2: any = nil
for attack, entry in GolemExperiment.LIST do
	if (Config.Boss :: any)[entry.flag] == true then
		v2 = v2 or require(ReplicatedStorage.Shared.GolemAnimsV2)
		;(Anims.clips :: any)[entry.clip] = v2.clips[entry.clip]
		playing[attack] = entry.clip
	end
end

-- Clip que o golpe `attack` toca (o próprio nome, fora os golpes com experimento ligado).
function GolemExperiment.clipFor(attack: string): string
	return playing[attack] or attack
end

return GolemExperiment
