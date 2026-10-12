-- Super soco: medidor, minigame aberto pelo servidor, pagamento, recusas e a queda no erro.
-- O minigame em si roda no cliente (comandos superAuto / superEarly do gancho de teste).
--   node tools/bridge.cjs run server src/server/tests/super.luau 60000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SUPER = Config.Super
local hook = ServerStorage:WaitForChild("TestHook", 5)
assert(hook, "TestHook ausente")

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
task.wait(1)

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function power()
	return hook:Invoke("state", player).power
end
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command, arg = arg })
end
local function toSpawn()
	local plot = workspace.Plots["Plot" .. hook:Invoke("plot", player)]
	character:PivotTo(plot:GetAttribute("Origin") * CFrame.new(Config.Plot.spawnOffset))
	task.wait(0.5)
end

hook:Invoke("runFinish", player)
hook:Invoke("set", player, { power = 0, money = 0, bagLevel = 1, stats = {} })
toSpawn()
local reward = math.floor(Config.Bag.levels[1].power * SUPER.multiplier)

-- só o servidor: senha errada, acerto cedo demais, erro declarado
local token = hook:Invoke("superOpen", player)
check("super soco abre o minigame", type(token) == "number" and hook:Invoke("superActive", player) == true, tostring(token))
task.wait(0.3)
check("cliente recebeu o minigame", ui("superState").active == true, "inativo")
check("senha errada não vale", hook:Invoke("superFinish", player, { token = token + 1, success = true }) == nil, "aceitou")
check("acerto antes do tempo possível não paga", hook:Invoke("superFinish", player, { token = token, success = true }) == 0 and power() == 0, tostring(power()))
check("senha usada não vale de novo", hook:Invoke("superFinish", player, { token = token, success = true }) == nil, "aceitou")
task.wait(SUPER.steps * (SUPER.stepTime + SUPER.stepPause) + 0.5) -- o cliente estoura o tempo do minigame que ficou aberto nele
task.wait(SUPER.stunTime + 0.6)
toSpawn()

-- ponta a ponta, acertando: o cliente joga sozinho no meio da zona verde
hook:Invoke("superOpen", player)
task.wait(0.2)
check("jogador automático começou", ui("superAuto") == true, "inativo")
task.wait(SUPER.steps * (SUPER.stepTime + SUPER.stepPause) + 1)
task.wait(SUPER.windTime + SUPER.holdTime)
check("acertar as teclas paga o super soco", power() == reward, `{power()} de {reward}`)
check("cliente fechou o minigame", ui("superState").active == false, "ativo")

-- ponta a ponta, errando: tecla certa cedo demais joga o boneco longe e não paga
task.wait(1)
toSpawn()
local from = root.Position
hook:Invoke("superOpen", player)
task.wait(0.2)
ui("superEarly")
task.wait(0.9)
local thrown = (root.Position - from).Magnitude
check("errar não paga", power() == reward, tostring(power()))
check("errar joga o boneco para longe", thrown > 12, string.format("%.1f studs", thrown))
check("servidor fechou depois do erro", hook:Invoke("superActive", player) == false, "ativo")
task.wait(SUPER.stunTime + 0.8)
local humanoid = character:FindFirstChildOfClass("Humanoid")
check("o boneco levanta depois", humanoid ~= nil and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Physics, tostring(humanoid and humanoid:GetState()))

hook:Invoke("set", player, { power = 0, money = 0 })
toSpawn()
return `{#passed} verificações OK: ` .. table.concat(passed, "; ") .. string.format(" | arremesso %.1f studs", thrown)
