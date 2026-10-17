-- O que os outros jogadores veem: a aura é montada para todos os jogadores, e as poses do
-- boneco (corrida, montaria...) saem do cliente em pacotes pequenos que o servidor repassa.
-- Com um jogador só dá para conferir o envio, o formato e o repasse; ver de fato o boneco do
-- outro pede um teste com dois clientes (Studio: Teste > Clientes e servidores > 2 jogadores).
--   node tools/bridge.cjs run server src/server/tests/sync.luau 60000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command, arg = arg })
end

local remote = ReplicatedStorage.Remotes:FindFirstChild("PoseSync")
check("canal das poses existe", remote ~= nil and remote:IsA("UnreliableRemoteEvent"), tostring(remote))

-- o servidor recebe os pacotes do cliente enquanto uma pose está ativa (aqui, a montaria)
local got, size = 0, 0
local connection = remote.OnServerEvent:Connect(function(_, data)
	got += 1
	size = if typeof(data) == "buffer" then buffer.len(data) else -1
end)
hook:Invoke("set", player, { mounts = { hoverboard = true }, mount = "" })
hook:Invoke("mount", player, "hoverboard")
hook:Invoke("ride", player)
task.wait(1.5)
local riding = got
check("cliente manda a pose enquanto ela está ativa", riding >= 12 and riding <= 40, riding .. " pacotes em 1,5 s")
local state = ui("poseSync")
check("pacote pequeno", size == state.bytes and size <= 128, size .. " bytes")
check("a pose sobrevive ao empacotamento", state.angleError < 0.5 and state.offsetError < 0.01, `{state.angleError} graus, {state.offsetError} studs`)
hook:Invoke("ride", player)
connection:Disconnect()

-- estados que os outros clientes usam para a aura
check("aura conta os jogadores montados", ui("auraState").players == #Players:GetPlayers(), tostring(ui("auraState").players))
local character = player.Character
character:PivotTo(CFrame.new(Config.Run.zoneCenter + Vector3.new(0, 4, 0)))
task.wait(0.3)
check("carga começa", hook:Invoke("runStart", player) == true, "fora da zona")
check("Charging replica na carga", player:GetAttribute("Charging") == true, tostring(player:GetAttribute("Charging")))
hook:Invoke("runRelease", player, 1)
check("corrida troca Charging por Racing", player:GetAttribute("Charging") == false and player:GetAttribute("Racing") == true, "atributos")
hook:Invoke("runFinish", player)
check("fim da corrida limpa os dois", player:GetAttribute("Charging") == false and player:GetAttribute("Racing") == false, "atributos")

return `{#passed} verificações OK: ` .. table.concat(passed, "; ") .. ` | {riding} pacotes de {size} bytes em 1,5 s`
