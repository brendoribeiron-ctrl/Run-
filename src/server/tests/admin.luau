-- Comando /reset, painel PLAYERS, placa em cima da cabeça e os efeitos que os outros veem.
-- Com um jogador só, o repasse aos outros clientes não tem para quem ir: aqui confere o que o
-- servidor guarda e o que o cliente sabe desenhar.
--   node tools/bridge.cjs run server src/server/tests/admin.luau 60000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function state()
	return hook:Invoke("state", player)
end
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command, arg = arg })
end

-- crítico e super soco raros
check("crítico começa raro", Config.Crit.baseChance <= 0.05, tostring(Config.Crit.baseChance))
local maxChance = Config.Crit.baseChance + Config.Stats.critChance.max * Config.Stats.critChance.perLevel
check("crítico no máximo fica abaixo de 1 em 4", maxChance <= 0.25, tostring(maxChance))
check("super soco mais raro que o crítico", Config.Super.chance < Config.Crit.baseChance, tostring(Config.Super.chance))
hook:Invoke("set", player, { power = 0, stats = {}, bagLevel = 1, aura = "" })
local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
character:PivotTo(plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset))
task.wait(0.4)
local crits, hits = 0, 400
for _ = 1, hits do
	local before = state().power
	hook:Invoke("hit", player)
	if state().power - before > Config.Bag.levels[1].power then
		crits += 1
	end
end
check("frequência real de crítico bate com a chance", crits / hits < Config.Crit.baseChance * 2.5 + 0.01, `{crits} em {hits}`)

-- placa em cima da cabeça
local tag = character:WaitForChild("Head"):WaitForChild("StatsTag", 5)
check("placa em cima da cabeça", tag ~= nil, "sem placa")
hook:Invoke("set", player, { power = 12_300, money = 4_500 })
task.wait(0.2)
check("placa mostra Poder e dinheiro", string.find(tag.Text.Text, ">12.3K POWER<", 1, true) ~= nil and string.find(tag.Text.Text, ">$4.5K<", 1, true) ~= nil, tag.Text.Text)

-- painel PLAYERS
ui("toggle", "Players")
task.wait(1.2)
local rows = ui("rank")
check("painel PLAYERS lista o jogador", #rows == #Players:GetPlayers() and string.find(rows[1], "12.3K", 1, true) ~= nil and string.find(rows[1], "4.5K", 1, true) ~= nil, tostring(rows[1]))
ui("toggle", "Players")

-- efeitos dos outros: o cliente sabe desenhar cada um
local before = ui("others", "hit")
check("efeito de soco dos outros", before >= 1, tostring(before))
check("efeito de crítico dos outros", ui("others", "crit") == before + 1, "crit")
check("efeito de super soco dos outros", ui("others", "super") == before + 2, "super")
check("efeito de dash dos outros", ui("others", "dash") == before + 3, "dash")
check("efeito de pulo duplo dos outros", ui("others", "jump") == before + 4, "jump")
check("canal do dash existe", ReplicatedStorage.Remotes:FindFirstChild("Cast") ~= nil, "sem Cast")

-- /reset: tudo volta ao começo
hook:Invoke("giveAll", player)
hook:Invoke("pedestal", player, 1)
task.wait(0.2)
check("antes do reset tem coisa", state().power > 0 and next(state().pedestals) ~= nil and state().slots == #Config.Plot.pedestals, "giveall falhou")
check("reset roda", hook:Invoke("reset", player) == true, "recusou")
task.wait(0.3)
local s = state()
check("reset zera Poder, dinheiro e saco", s.power == 0 and s.money == 0 and s.bagLevel == 1, `{s.power} {s.money} {s.bagLevel}`)
check("reset limpa inventário, pedestais e índice", #s.inventory == 0 and next(s.pedestals) == nil and next(s.index) == nil and s.slots == Config.Plot.freePedestals, tostring(#s.inventory))
check("reset tira aura, montaria, skills e automáticos", s.aura == "" and s.mount == "" and next(s.mounts) == nil and next(s.stats) == nil and next(s.unlocks) == nil and next(s.levels) == nil, s.aura)
check("reset limpa o terreno", plot.Pedestal1:FindFirstChild("Character") == nil and player:GetAttribute("Power") == 0 and player:GetAttribute("Inventory") == "", "terreno")
check("no Studio todo mundo é admin", hook:Invoke("isAdmin", player) == true, "não é admin")
check("jogorui está na lista de admins", table.find(Config.Admins, 10098933976) ~= nil, "fora da lista")

-- /lab e /back: a sala de testes da equipe, longe do mapa
local area = Config.DevArea
check("comandos /lab e /back existem", game:GetService("TextChatService"):FindFirstChild("Lab") ~= nil and game:GetService("TextChatService"):FindFirstChild("Back") ~= nil, "sem comando")
check("sala de testes montada", workspace:FindFirstChild("DevArea") ~= nil and #workspace.DevArea:GetChildren() > 500, "sem chão")
local labMessage = hook:Invoke("devArea", player, true)
task.wait(0.5)
local at = (character:GetPivot().Position - area.center)
check("/lab leva para a sala de testes", math.abs(at.X) < area.size / 2 and math.abs(at.Z) < area.size / 2 and math.abs(at.Y) < 20, `{labMessage} {at}`)
task.wait(1.5) -- o vigia passa (no Studio todo mundo é dev: fica)
at = (character:GetPivot().Position - area.center)
check("dev fica na sala de testes", math.abs(at.X) < area.size / 2 and math.abs(at.Z) < area.size / 2, tostring(at))
local backMessage = hook:Invoke("devArea", player, false)
task.wait(0.5)
check("/back volta ao terreno", (character:GetPivot().Position - area.center).Magnitude > area.size, tostring(backMessage))

-- /give power|money <quantia> [jogador]
hook:Invoke("set", player, { power = 0, money = 0 })
hook:Invoke("giveCommand", player, "/give power 5M")
check("/give power soma Poder", state().power == 5_000_000, tostring(state().power))
hook:Invoke("giveCommand", player, "/give money 2.5k")
check("/give money soma dinheiro", state().money == 2_500 and state().power == 5_000_000, tostring(state().money))
hook:Invoke("giveCommand", player, `/give Money 1b "{string.sub(player.Name, 1, 3)}"`)
check("/give aceita o nome entre aspas e pelo começo", state().money == 1_000_002_500, tostring(state().money))
local usage = hook:Invoke("giveCommand", player, "/give gems 10")
check("/give recusa o que não é Poder nem dinheiro", string.find(usage, "Usage") ~= nil and state().money == 1_000_002_500, usage)
check("/give recusa quantia inválida", string.find(hook:Invoke("giveCommand", player, "/give power -5"), "Usage") ~= nil and string.find(hook:Invoke("giveCommand", player, "/give power abc"), "Usage") ~= nil and state().power == 5_000_000, tostring(state().power))
check("/give avisa quando o jogador não está no servidor", string.find(hook:Invoke("giveCommand", player, "/give power 10 zzzninguem"), "No player") ~= nil and state().power == 5_000_000, tostring(state().power))

return `{#passed} verificações OK: ` .. table.concat(passed, "; ") .. ` | {crits} críticos em {hits} socos`
