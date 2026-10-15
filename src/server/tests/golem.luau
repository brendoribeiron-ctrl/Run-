-- O golem da sala do chefe: modelo e animações carregados, desafio acorda ele, cada golpe acerta
-- quem está no lugar dele e erra quem não está, o pulso se esquiva no alto, o soco do jogador
-- tira vida, metade da vida liga a raiva, a vitória sorteia o personagem e a derrota perde o
-- sorteio. O cliente monta o golem, move as peças e mostra a barra.
--   node tools/bridge.cjs run server src/server/tests/golem.luau 180000
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Anims = require(ReplicatedStorage.Shared.GolemAnims)
local hook = game:GetService("ServerStorage"):WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local BOSS = Config.Boss
local S = BOSS.scale
local passed = {}
local function check(name: string, ok: boolean, detail: string?)
	assert(ok, "FALHOU: " .. name .. " (" .. tostring(detail) .. ")")
	table.insert(passed, name)
end
local function boss(action: string, arg: any?): any
	return hook:Invoke("boss", player, { action = action, arg = arg, world = 1 })
end
local function ui(command: string, arg: any?): any
	return hook:Invoke("ui", player, { command = command, arg = arg })
end
local function humanoid(): Humanoid
	return (player.Character :: Model):WaitForChild("Humanoid") :: Humanoid
end

-- modelo e animações
local models = ReplicatedStorage:WaitForChild("BossModels", 30)
local golem = models and models:WaitForChild("Golem1", 60)
check("o modelo do golem carregou", golem ~= nil, "BossModels.Golem1")
local bones: { [string]: number } = {}
for _, part in (golem :: Model):GetDescendants() do
	if part:IsA("BasePart") then
		local bone = string.match(part.Name, "_(%w+)$")
		if bone then
			bones[bone] = (bones[bone] or 0) + 1
		end
	end
end
local missing = {}
for _, name in Anims.bones do
	if not bones[name] then
		table.insert(missing, name)
	end
end
check("toda peça tem osso e todo osso tem peça", #missing == 0, table.concat(missing, ","))
local _, size = (golem :: Model):GetBoundingBox()
check("o golem tem o tamanho certo (~32 studs)", size.Y > 26 * S and size.Y < 40 * S, tostring(size))
local clips = 0
for name, clip in Anims.clips do
	clips += 1
	assert(#clip.frames == #clip.times and #clip.frames[1] == 3 + #Anims.bones * 3, "quadros de " .. name)
end
check("as animações estão todas lá", clips >= 11 and Anims.clips.Stomp.events.impact ~= nil and Anims.clips.Pulse.events.pulse ~= nil, tostring(clips))

-- o golem dorme na sala
local room = workspace:WaitForChild("BossRoom1", 60)
local server = room:WaitForChild("Boss", 30) :: Model
check("o golem dorme no círculo", server:GetAttribute("State") == "sleep" and server:GetAttribute("Clip") == "Sleep", tostring(server:GetAttribute("State")))

-- vai para a sala com uma corrida que limpa o corredor
hook:Invoke("reset", player)
task.wait(0.5)
local world = Config.Worlds[1]
local walls = world.walls
hook:Invoke("set", player, { power = walls[#walls].power * 2 })
hook:Invoke("goZone", player, "resetCooldown")
task.wait(0.3)
hook:Invoke("runStart", player)
hook:Invoke("runRelease", player, 1)
hook:Invoke("runFinish", player)
task.wait(Config.BossRoom.introTime + 1.5)
check("está na sala com direito ao sorteio", player:GetAttribute("Room") == 1 and player:GetAttribute("BossReward") == true, tostring(player:GetAttribute("Room")))
local seen = ui("golem")
check("o cliente montou o golem", seen.built == true and seen.parts >= 50 and seen.clip == "Sleep", `{seen.built} {seen.parts} {seen.clip}`)

local center = Config.BossRoom.center + world.offset
local floorY = center.Y
local function put(offset: Vector3)
	-- jogador num ponto em volta do golem (offset no espaço dele: x direita, z para trás)
	local state = boss("state")
	local at = (state.cframe * CFrame.new(offset)).Position
	local character = player.Character :: Model
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.new(Vector3.new(at.X, floorY + 3, at.Z)))
end
local function heal()
	local h = humanoid()
	h.Health = h.MaxHealth
end

-- desafio: acorda e a barra aparece
check("sem o direito, desafiar não acorda", (function()
	boss("pending", false)
	local ok = boss("challenge")
	boss("pending", true)
	return ok == false
end)(), "acordou")
check("desafiar acorda o golem", boss("challenge") == true and server:GetAttribute("State") == "wake" and server:GetAttribute("Clip") == "Wake", tostring(server:GetAttribute("State")))
task.wait(Anims.clips.Wake.length + 0.6)
local state = boss("state")
check("depois de levantar, ele luta", state.state ~= "sleep" and state.state ~= "wake", state.state)
seen = ui("golem")
check("a barra do chefe aparece", seen.bar == true, tostring(seen.bar))

-- golpes: para o golem no centro, de frente para a porta, e força cada um
local function strike(name: string, offset: Vector3, jump: boolean?): number
	boss("place", { position = center, yaw = math.pi, rest = 30 })
	task.wait(0.2)
	heal()
	put(offset)
	local before = humanoid().Health
	-- a menor vida durante o golpe (a regeneração do Roblox devolve um pouco depois)
	local lowest = before
	local watching = humanoid().HealthChanged:Connect(function(health)
		lowest = math.min(lowest, health)
	end)
	boss("attack", name)
	local data = Anims.clips[name]
	local at = data.events.impact or data.events.pulse
	if jump then
		-- no alto enquanto a onda passa
		local character = player.Character :: Model
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
		task.wait(at - 0.05)
		root.Anchored = true
		character:PivotTo(character:GetPivot() + Vector3.new(0, 9, 0))
		task.wait(1.6)
		root.Anchored = false
	else
		task.wait(at + 1.7)
	end
	boss("rest", 30)
	watching:Disconnect()
	return before - lowest
end
local A = BOSS.attacks
check("pisão acerta quem está perto do pé", strike("Stomp", Vector3.new(A.Stomp.side + 3, 0, -(A.Stomp.ahead + 5))) >= A.Stomp.damage - 1, "pisão")
check("pisão erra quem está longe", strike("Stomp", Vector3.new(0, 0, -(A.Stomp.ahead + A.Stomp.radius) * S - 10)) == 0, "pisão longe")
check("varredura acerta do lado", strike("Sweep", Vector3.new(14, 0, -2)) >= A.Sweep.damage - 1, "varredura")
check("varredura erra quem está atrás", strike("Sweep", Vector3.new(0, 0, 16)) == 0, "varredura atrás")
check("esmagamento acerta na frente", strike("Slam", Vector3.new(0, 0, -A.Slam.ahead - 2)) >= A.Slam.damage - 1, "esmagamento")
check("o gancho da corrida acerta à frente", strike("Charge", Vector3.new(0, 0, -(A.Charge.ahead + A.Charge.lunge + 2))) >= A.Charge.damage - 1, "gancho")
check("o pulso acerta quem está no chão", strike("Pulse", Vector3.new(A.Pulse.side, 0, -(A.Pulse.ahead + 30))) >= A.Pulse.damage - 1, "pulso")
check("pular o pulso esquiva", strike("Pulse", Vector3.new(A.Pulse.side, 0, -(A.Pulse.ahead + 30)), true) == 0, "pulso no alto")
heal()

-- soco do jogador
boss("place", { position = center, yaw = math.pi, rest = 30 })
task.wait(0.3)
put(Vector3.new(0, 0, -(BOSS.radius * S + 4)))
task.wait(0.3)
local hp = boss("state").hp
local d1 = boss("punch", false)
task.wait(BOSS.hitCooldown + 0.05)
local d2 = boss("punch", true)
check("soco tira 1, crítico tira 2", d1 == 1 and d2 == 2 and boss("state").hp == hp - 3, `{d1} {d2} {boss("state").hp}`)
task.wait(BOSS.hitCooldown + 0.05)
check("o cliente pode socar daqui", ui("golem").target == true, "alvo")
put(Vector3.new(0, 0, -(BOSS.hitRange * S + 6)))
task.wait(BOSS.hitCooldown + 0.05)
check("de longe o soco não conta", boss("punch", false) == 0, "longe")
put(Vector3.new(0, 0, -(BOSS.radius * S + 4)))
boss("hp", math.floor(boss("state").maxHp / 2) + 1)
task.wait(BOSS.hitCooldown + 0.05)
boss("punch", true)
check("metade da vida liga a raiva", boss("state").rage == true and server:GetAttribute("Rage") == true, "raiva")

-- vitória: ele cai, se desfaz e o sorteio vem
local owned = #hook:Invoke("state", player).inventory
boss("hp", 1)
task.wait(BOSS.hitCooldown + 0.05)
boss("punch", false)
check("vida zero: ele morre", boss("state").state == "dead" and server:GetAttribute("Clip") == "Death", boss("state").state)
task.wait(Anims.clips.Death.events.crumble + 2.2)
check("vitória sorteia o personagem", #hook:Invoke("state", player).inventory == owned + 1 and player:GetAttribute("BossReward") == nil, "sorteio")
check("o golem se desfez na tela", ui("golem").crumbled == true, "pedaços")

-- derrota: quem morre para o golem perde o sorteio
boss("reset")
task.wait(0.5)
check("ele volta a dormir inteiro", server:GetAttribute("State") == "sleep" and ui("golem").crumbled == false, "dormindo")
boss("pending", true)
boss("challenge")
task.wait(Anims.clips.Wake.length + 0.4)
boss("place", { position = center, yaw = math.pi, rest = 30 })
put(Vector3.new(0, 0, -A.Slam.ahead - 2))
humanoid().Health = 5
boss("attack", "Slam")
task.wait(Anims.clips.Slam.events.impact + 0.4)
check("morrer para o golem perde o sorteio", player:GetAttribute("BossReward") == nil and humanoid().Health <= 0, tostring(humanoid().Health))
player.CharacterAdded:Wait()
task.wait(1)
check("depois de morrer não está mais na sala", player:GetAttribute("Room") == nil, tostring(player:GetAttribute("Room")))
task.wait(BOSS.resetDelay + 1)
check("sem ninguém, o golem volta a dormir", server:GetAttribute("State") == "sleep", tostring(server:GetAttribute("State")))

hook:Invoke("reset", player)
return `{#passed} ok: ` .. table.concat(passed, " | ")
