--!strict
-- Laboratório de efeitos (lab.project.json): um place separado do jogo, só no Studio, com o chão
-- da sala de testes (DevArea) e o golem no meio, para eu testar VFX rápido pela ponte. A equipe
-- testa no próprio jogo, na sala de testes (/lab). Os efeitos são os mesmos módulos do jogo
-- (src/client/BossFx.luau, Fx.luau, GolemPose.luau), sem cópia.
--
-- Comandos pela ponte (porta 34875, marcada em ReplicatedStorage.BridgePort):
--   BRIDGE_PORT=34875 node tools/bridge.cjs run server lab/server/tests/fx.luau 30000 Slam 1 side

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admin = require(script.Admin)
local DevArea = require(script.DevArea)
local GolemModels = require(script.GolemModels)

-- A mesma luz do jogo (World.setupLighting por cima dos efeitos montados no place do jogo), para
-- o efeito sair igual nos dois lugares. Feito aqui e não no arquivo do place: uma sincronização
-- do Rojo com o projeto errado não estraga.
Lighting.Brightness = 1.8
Lighting.ExposureCompensation = -0.35
Lighting.ClockTime = 14
Lighting.GeographicLatitude = 35
Lighting.Ambient = Color3.fromRGB(95, 95, 110)
Lighting.OutdoorAmbient = Color3.fromRGB(125, 125, 140)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.3
Lighting.GlobalShadows = true
for _, effect in Lighting:GetChildren() do
	if effect:IsA("PostEffect") or effect:IsA("Atmosphere") then
		effect:Destroy()
	end
end
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 1
bloom.Size = 56
bloom.Threshold = 2
bloom.Parent = Lighting
local color = Instance.new("ColorCorrectionEffect")
color.Contrast = 0.5
color.Brightness = -0.1
color.Parent = Lighting
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.3
atmosphere.Haze = 0
atmosphere.Glare = 0
atmosphere.Color = Color3.fromRGB(199, 199, 199)
atmosphere.Decay = Color3.fromRGB(106, 112, 125)
atmosphere.Parent = Lighting

-- o place vazio do Studio vem com Baseplate e SpawnLocation
for _, name in { "Baseplate", "SpawnLocation" } do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local floor = Instance.new("Folder")
floor.Name = "Floor"
floor.Parent = workspace
DevArea.floor(floor, Vector3.zero, 1200)

local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(8, 0.2, 8)
spawn.Position = Vector3.new(0, 0.1, 90)
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Duration = 0
spawn.Parent = workspace

-- comandos do servidor para o cliente (a cena roda no cliente, como no jogo)
local remote = Instance.new("RemoteEvent")
remote.Name = "Lab"
remote.Parent = ReplicatedStorage

GolemModels.load()

local CLIPS = { stomp = "Stomp", sweep = "Sweep", slam = "Slam", charge = "Charge", pulse = "Pulse", wake = "Wake", death = "Death" }
local VIEWS = { side = true, front = true, wide = true, top = true, close = true, free = true }

-- Comandos de chat (só admin; quem não é não recebe nada). Cada um devolve o aviso para quem
-- digitou (nil = sem aviso):
--   /fx slam [1|2] [side|front|wide|top|close|free]   toca um golpe do golem
local COMMANDS: { [string]: (player: Player, words: { string }) -> string? } = {}

COMMANDS.fx = function(player, words)
	local clip = CLIPS[words[1] or ""]
	if not clip then
		return "Usage: /fx stomp|sweep|slam|charge|pulse|wake|death [1|2] [side|front|wide|top|close|free]"
	end
	local world = if words[2] == "2" then 2 else 1
	local view = if VIEWS[words[3] or ""] then words[3] else "free"
	remote:FireClient(player, "play", clip, world, view)
	return nil
end

local function run(player: Player, text: string)
	local words = string.split(string.lower(text), " ")
	local name = string.sub(table.remove(words, 1) or "", 2)
	local action = COMMANDS[name]
	local message = if action then action(player, words) else nil
	if message then
		remote:FireClient(player, "toast", message)
	end
	return message
end

for name, alias in { Fx = "/fx" } do
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = alias
	command.Triggered:Connect(function(source, text)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player and Admin.isAdmin(player) then
			run(player, text)
		end
	end)
	command.Parent = game:GetService("TextChatService")
end

-- o cliente avisa que tocou o golpe (os testes conferem pelo atributo)
remote.OnServerEvent:Connect(function(player, action, clip)
	if action == "played" and type(clip) == "string" and #clip < 20 then
		player:SetAttribute("LabPlayed", clip)
	end
end)

-- Gancho dos testes (lab/server/tests): roda um comando de chat como se o jogador tivesse digitado.
local hook = Instance.new("BindableFunction")
hook.Name = "LabHook"
hook.OnInvoke = function(player: Player, text: string)
	return run(player, text)
end
hook.Parent = game:GetService("ServerStorage")

Players.PlayerAdded:Connect(function(player)
	if not Admin.isAdmin(player) then
		player:Kick("This place is for the dev team.")
		return
	end
	player.CharacterAdded:Connect(function(character)
		-- o boneco olha para o golem, no centro
		task.defer(function()
			character:PivotTo(CFrame.lookAt(Vector3.new(0, 4, 90), Vector3.new(0, 4, 0)))
		end)
	end)
end)
