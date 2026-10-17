--!strict
-- Elenco de anime do mundo 1 (Black Clover), no estilo dos jogos de "anime farm": avatar R6 com
-- cabelo, rosto, camisa, calça e acessórios do catálogo de avatar (peças que fãs fizeram para
-- cada personagem). O servidor monta cada um com Players:CreateHumanoidModelFromDescription
-- (server/CharacterMeshes.luau); Config.Characters aponta para cá pelo campo `model`.
--
-- Os números são ids do catálogo; escolhidos olhando as miniaturas de cada busca.

export type Avatar = {
	hair: number?,
	face: number?,
	shirt: number?,
	pants: number?,
	back: number?,
	waist: number?,
	shoulder: number?,
	skin: Color3?,
}

local SKIN = Color3.fromRGB(255, 204, 153)

local AnimeCast: { [string]: Avatar } = {
	magna = { hair = 95652500312305, face = 128270963708695, shirt = 5200794937, pants = 5200792459 },
	luck = { hair = 104057305440042, face = 10856597304, shirt = 5178215804, pants = 5177837566 },
	secre = { hair = 17518181963, face = 111347357706458, shirt = 5931401541, pants = 5931402278, back = 13920946859 },
	vanessa = { hair = 115758346260998, face = 123225583844411, shirt = 14588477877, pants = 14588482831 },
	zora = { hair = 103251717149065, face = 17860428616, shirt = 5178188482, pants = 5178175887 },
	mimosa = { hair = 77086271263341, face = 15707361611, shirt = 6720205055, pants = 6882501468 },
	noelle = { hair = 83697255385665, face = 107647104003186, shirt = 113852724463634, pants = 70472356074163 },
	yuno = { hair = 115191447987971, shirt = 112186922553994, pants = 16630875219 },
	nacht = { hair = 119339090583896, face = 108544844252815, shirt = 76021560609660, pants = 104885194578847, shoulder = 106767817726809 },
	asta = { hair = 88314631212939, face = 79900333811148, shirt = 8393000562, pants = 8392998329, back = 136895277917044 },
	mereoleona = { hair = 77086271263341, face = 16993883206, shirt = 71313135774651, pants = 78828418252388, back = 76597115174534 },
	fuegoleon = { hair = 77086271263341, face = 91634324982595, shirt = 11348563364, pants = 11348560331 },
	yami = { hair = 84704482838816, face = 106148235297079, shirt = 104920247456953, pants = 102075001000325, waist = 124805420492794 },
	zenon = { hair = 108978449742313, face = 113149274909201, shirt = 13467242352, pants = 13467243361 },
	dante = { hair = 138954706217394, face = 76827343611998, shirt = 11348540536, pants = 11348538062 },
	julius = { hair = 139701427990767, face = 112798380400643, shirt = 5908302963, pants = 5908320312 },
	lucius = { hair = 138954706217394, face = 97328823088409, shirt = 132278262893641, pants = 79307714438167 },
	demon = { hair = 95616810998593, shirt = 117363953833524, pants = 105096145226899, shoulder = 112472227381651 },
}

for _, avatar in AnimeCast do
	avatar.skin = avatar.skin or SKIN
end

return AnimeCast
