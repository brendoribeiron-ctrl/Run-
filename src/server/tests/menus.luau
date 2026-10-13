-- Janelas (mochila, índice, loja, rebirth, daily, playtime) e braços da caminhada.
-- O estado das janelas e das poses vem do cliente, pelo comando "ui" do TestHook.
--   node tools/bridge.cjs run server src/server/tests/menus.luau 40000

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

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
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command or "state", arg = arg })
end
local function toggle(name)
	ui("toggle", name)
	task.wait(0.1)
	return ui().open
end

hook:Invoke("runFinish", player)
if ui().open ~= "" then
	toggle(ui().open)
end

-- vazio: nada no índice nem na mochila
hook:Invoke("set", player, { inventory = {}, index = {} })
task.wait(0.2)
check("atributo Index vazio", player:GetAttribute("Index") == "", tostring(player:GetAttribute("Index")))
check("mochila abre", toggle("Backpack") == "Backpack", ui().open)
check("mochila vazia sem células", ui().backpackCells == 0 and ui().backpackCount == "0/24", ui().backpackCount)

-- cheio: 18 personagens entram na mochila aberta e no índice
hook:Invoke("giveAll", player)
task.wait(0.3)
check("atributo Index com 18", #string.split(player:GetAttribute("Index"), ",") == 18, tostring(player:GetAttribute("Index")))
check("mochila aberta atualiza", ui().backpackCells == 18 and ui().backpackCount == "18/24", ui().backpackCount)
check("mochila fecha", toggle("Backpack") == "", ui().open)

toggle("Backpack")
check("abrir o índice fecha a mochila", toggle("Index") == "Index", ui().open)
local state = ui()
check("índice mostra os 18", state.indexCards == 18 and state.indexFound == 18, `{state.indexFound}/{state.indexCards} {state.indexCount}`)
hook:Invoke("set", player, { index = { rookie_jabber = true } })
task.wait(0.3)
check("índice aberto atualiza", ui().indexFound == 1, ui().indexCount)
toggle("Index")

for _, name in { "Shop", "Rebirth", "Daily", "Playtime" } do
	check(name .. " abre", toggle(name) == name, ui().open)
	check(name .. " fecha", toggle(name) == "", ui().open)
end

-- caminhada: no primeiro segundo andando os ombros vão para trás; depois a corrida assume
check("mochila tem o botão de vender", string.find(ui().backpackSell, "SELL", 1, true) ~= nil, tostring(ui().backpackSell))
character:PivotTo(CFrame.new(-60, 4, 38)) -- faixa livre entre a casa do centro e os terrenos
task.wait(1.2)
local idle = ui("arms", 0.4)
local from = root.Position
-- anda por mais tempo que as medições levam: com o jogo pesado, as chamadas ao cliente
-- demoram e a medição da corrida caía depois de o boneco já ter parado
ui("walk", { direction = Vector3.xAxis, seconds = 6 })
task.wait(0.3)
local walking = ui("arms", 0.45)
task.wait(1.5)
local sprinting = ui("arms", 0.4)
local walked = (root.Position - from).Magnitude
ui("walk", { direction = Vector3.xAxis, seconds = 0 })
task.wait(0.5)
local detail = string.format(
	"andou %.0f studs | parado %.1f | andando %.1f (peso %.2f, mov %.1f, chão %s, vel %.0f) | correndo %.1f (peso %.2f, sprint %.2f, vel %.0f)",
	walked, idle.pitch, walking.pitch, walking.walkArms, walking.moving, walking.floor, walking.speed, sprinting.pitch, sprinting.walkArms, sprinting.sprint, sprinting.speed
)
check("o personagem andou", walked > 40, detail)
check("camada walkArms liga ao andar", walking.walkArms > 0.6, detail)
check("ombros para trás ao andar", walking.pitch < idle.pitch - 12, detail)
check("corrida desliga walkArms", sprinting.walkArms < 0.1 and sprinting.sprint > 0.9, detail)
check("corrida leva os braços mais para trás", sprinting.pitch < walking.pitch - 20, detail)

hook:Invoke("set", player, { power = 0, money = 0, inventory = {}, index = {} })
return `{#passed} verificações OK: ` .. table.concat(passed, "; ") .. " | " .. detail
