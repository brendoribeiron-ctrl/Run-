-- HUD por aparelho e editor do HUD: no celular o dinheiro/Poder e a placa da cabeça encolhem e a
-- engrenagem aparece; mexer num bloco muda posição, tamanho e opacidade; salvar grava no perfil;
-- a validação descarta blocos desconhecidos e limita os números.
--   node tools/bridge.cjs run server src/server/tests/hud.luau 60000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local HudLayout = require(ReplicatedStorage.Shared.HudLayout)
local hook = ServerStorage:WaitForChild("TestHook", 5)
assert(hook, "TestHook ausente")

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")
task.wait(1)

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end
local function ui(command, arg)
	return hook:Invoke("ui", player, { command = command, arg = arg })
end

-- validação (servidor e cliente usam a mesma)
local clean = HudLayout.decode('{"Hotbar":{"x":5,"y":-3,"s":9,"o":0},"Evil":{"x":1},"Stats":{"x":0,"y":0,"s":1,"o":1}}')
check("bloco desconhecido some", clean.Evil == nil, "")
check("números presos nos limites", clean.Hotbar and clean.Hotbar.x == 1 and clean.Hotbar.y == -1 and clean.Hotbar.s == HudLayout.SIZE.max and clean.Hotbar.o == HudLayout.OPACITY.min, HudLayout.encode(clean))
check("bloco no padrão não ocupa espaço", clean.Stats == nil, "")
check("texto quebrado vira padrão", next(HudLayout.decode("{nope")) == nil, "")

-- plataforma: PC x celular
ui("hudPlatform", "desktop")
task.wait(0.3)
local desk = ui("hudState")
ui("hudPlatform", "phone")
task.wait(0.3)
local phone = ui("hudState")
check("detecta o celular", phone.platform == "phone", tostring(phone.platform))
check("engrenagem só no toque", phone.gear == true and desk.gear == false, `{desk.gear} {phone.gear}`)
check("dinheiro e Poder menores no celular", phone.statsScale and desk.statsScale and phone.statsScale < desk.statsScale * 0.8, `{desk.statsScale} -> {phone.statsScale}`)
check("placa da cabeça menor no celular", phone.tagSize and desk.tagSize and phone.tagSize < desk.tagSize, `{desk.tagSize} -> {phone.tagSize}`)

-- opacidade DE VERDADE: a transparência que aparece na tela (fundo da hotbar, texto e contorno do
-- dinheiro) segue 1 - (1 - original) * opacidade em qualquer sequência de ajustes e volta ao
-- original. Regressão: o HUD ia a 0 % e não voltava (float32 x precisão dupla no editor).
local TOL = 2e-3
local function near(a, b)
	return a ~= nil and b ~= nil and math.abs(a - b) <= TOL
end
local function fade(base, o)
	return 1 - (1 - base) * o
end
local clear = ui("hudState")
check("lê as transparências reais do HUD", clear.slotBg and clear.moneyText and clear.moneyStroke, `{clear.slotBg} {clear.moneyText} {clear.moneyStroke}`)
local steps = {}
for i = 1, 25 do
	table.insert(steps, 1 - i * 0.032) -- 0.968 ... 0.2, como a barra deslizando
end
for i = 24, 1, -1 do
	table.insert(steps, 1 - i * 0.032) -- e voltando
end
table.insert(steps, 1)
local lowest
for index, o in steps do
	ui("hudSet", { id = "Hotbar", entry = { x = 0, y = 0, s = 1, o = o } })
	ui("hudSet", { id = "Stats", entry = { x = 0, y = 0, s = 1, o = o } })
	task.wait(0.06) -- os sinais adiados chegam aqui; era onde o editor se perdia
	local now = ui("hudState")
	assert(near(now.slotBg, fade(clear.slotBg, o)), `FALHOU: fundo da hotbar no passo {index} (o={o}): esperado {fade(clear.slotBg, o)}, veio {now.slotBg}`)
	assert(near(now.moneyText, fade(clear.moneyText, o)), `FALHOU: texto do dinheiro no passo {index} (o={o}): esperado {fade(clear.moneyText, o)}, veio {now.moneyText}`)
	assert(near(now.moneyStroke, fade(clear.moneyStroke, o)), `FALHOU: contorno do dinheiro no passo {index} (o={o}): esperado {fade(clear.moneyStroke, o)}, veio {now.moneyStroke}`)
	if index == 25 then
		lowest = now
	end
end
table.insert(passed, "50 ajustes de opacidade seguem a fórmula (fundo, texto, contorno)")
check("no mínimo de opacidade o HUD continua visível", lowest and lowest.slotBg < 0.9 and lowest.moneyText < 0.9, `{lowest and lowest.slotBg} {lowest and lowest.moneyText}`)
local restored = ui("hudState")
check("opacidade 100% devolve as transparências originais", near(restored.slotBg, clear.slotBg) and near(restored.moneyText, clear.moneyText) and near(restored.moneyStroke, clear.moneyStroke), `{restored.slotBg}/{clear.slotBg} {restored.moneyText}/{clear.moneyText}`)

-- outro código muda uma transparência com o bloco esmaecido (a hotbar ao trocar de personagem):
-- o valor novo vira o original e o esmaecimento é reaplicado por cima dele
ui("hudSet", { id = "Hotbar", entry = { x = 0, y = 0, s = 1, o = 0.5 } })
task.wait(0.1)
ui("hudTouch", 0.6)
task.wait(0.1)
local touched = ui("hudState")
check("valor novo de outro código é esmaecido a partir dele", near(touched.slotBg, fade(0.6, 0.5)), `esperado {fade(0.6, 0.5)}, veio {touched.slotBg}`)
ui("hudSet", { id = "Hotbar", entry = { x = 0, y = 0, s = 1, o = 1 } })
task.wait(0.1)
check("e volta a ele em 100%", near(ui("hudState").slotBg, 0.6), tostring(ui("hudState").slotBg))
ui("hudTouch", clear.slotBg)
ui("hudSet", { id = "Hotbar", entry = HudLayout.default() })
ui("hudSet", { id = "Stats", entry = HudLayout.default() })
task.wait(0.1)
check("hotbar de volta ao padrão", near(ui("hudState").slotBg, clear.slotBg), tostring(ui("hudState").slotBg))

-- editor: mexe na hotbar
local before = phone.Hotbar
local after = ui("hudSet", { id = "Hotbar", entry = { x = 0.1, y = -0.05, s = 1.3, o = 0.5 } })
check("hotbar andou", math.abs(after.Hotbar.x - (before.x + 0.1)) < 1e-3 and math.abs(after.Hotbar.y - (before.y - 0.05)) < 1e-3, `{before.x},{before.y} -> {after.Hotbar.x},{after.Hotbar.y}`)
check("hotbar cresceu", after.Hotbar.userScale == 1.3, tostring(after.Hotbar.userScale))
check("hotbar ficou translúcida", after.Hotbar.opacity == 0.5, tostring(after.Hotbar.opacity))
local opened = ui("hudOpen", true)
check("editor abre e esconde a engrenagem", opened.editing == true and opened.gear == false, `{opened.editing} {opened.gear}`)
local closed = ui("hudOpen", false) -- fechar salva
check("editor fecha", closed.editing == false and closed.gear == true, "")
task.wait(1)
local saved = HudLayout.decode(hook:Invoke("state", player).hud)
check("layout salvo no perfil", saved.Hotbar and saved.Hotbar.s == 1.3 and saved.Hotbar.o == 0.5, tostring(hook:Invoke("state", player).hud))
check("atributo atualizado", player:GetAttribute("HudLayout") == hook:Invoke("state", player).hud, "")

-- mesma conta no PC: layout do celular não vale lá
ui("hudPlatform", "desktop")
local pc = ui("hudState")
check("PC ignora layout do celular", math.abs(pc.Hotbar.x - before.x) < 1e-3 and pc.Hotbar.userScale == 1 and pc.Hotbar.opacity == 1, `{pc.Hotbar.x} {pc.Hotbar.userScale} {pc.Hotbar.opacity}`)
ui("hudPlatform", "phone")
local back = ui("hudState")
check("celular volta ao layout salvo", back.Hotbar.userScale == 1.3, tostring(back.Hotbar.userScale))

-- volta ao padrão
local reset = ui("hudSet", { id = "Hotbar", entry = HudLayout.default() })
check("reset volta a hotbar", math.abs(reset.Hotbar.x - before.x) < 1e-3 and reset.Hotbar.userScale == 1 and reset.Hotbar.opacity == 1, `{reset.Hotbar.x} {reset.Hotbar.userScale} {reset.Hotbar.opacity}`)
ui("hudSave")
ui("hudPlatform", nil)
task.wait(1)
check("perfil limpo", hook:Invoke("state", player).hud == "", tostring(hook:Invoke("state", player).hud))

return `{#passed} checagens ok`
