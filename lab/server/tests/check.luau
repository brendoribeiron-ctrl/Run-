-- Confere o laboratório: chão, golem carregado, comandos de chat e o jogador como admin.
--   BRIDGE_PORT=34875 node tools/bridge.cjs run server lab/server/tests/check.luau 30000
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local out = {}
local function check(name: string, ok: boolean)
	table.insert(out, (if ok then "ok " else "FALHOU ") .. name)
end

local models = ReplicatedStorage:WaitForChild("BossModels", 20)
check("chão xadrez", workspace:FindFirstChild("Floor") ~= nil and #workspace.Floor:GetChildren() > 1000)
check("sem Baseplate", workspace:FindFirstChild("Baseplate") == nil)
check("golem do mundo 1", models ~= nil and models:WaitForChild("Golem1", 20) ~= nil)
check("golem do mundo 2", models ~= nil and models:WaitForChild("Golem2", 20) ~= nil)
check("peças dos efeitos", models ~= nil and models:WaitForChild("Fx", 20) ~= nil)
check("comando /fx", TextChatService:FindFirstChild("Fx") ~= nil)
local player = Players:GetPlayers()[1]
check("jogador entrou", player ~= nil)
check("jogador no laboratório", player ~= nil and player.Character ~= nil)

-- comandos de chat, pelo gancho (o mesmo código que o chat chama)
local hook = game:GetService("ServerStorage"):WaitForChild("LabHook", 5)
if hook and player then
	player:SetAttribute("LabPlayed", nil)
	check("/fx slam não reclama", hook:Invoke(player, "/fx slam 1 side") == nil)
	local waited = 0
	while player:GetAttribute("LabPlayed") == nil and waited < 3 do
		waited += task.wait(0.1)
	end
	check("/fx slam: o cliente tocou o golpe", player:GetAttribute("LabPlayed") == "Slam")
	local usage = hook:Invoke(player, "/fx banana")
	check("/fx com golpe errado mostra o uso", type(usage) == "string" and string.find(usage, "Usage", 1, true) ~= nil)
	task.wait(3) -- deixa o golpe terminar
else
	check("gancho dos comandos", false)
end
return table.concat(out, " | ")
