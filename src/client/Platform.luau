--!strict
-- Em que aparelho o jogador está: "phone", "tablet", "console" ou "desktop". O texto grande do
-- HUD (dinheiro, Poder, placa da cabeça, minigame do super soco, avisos) encolhe no toque, onde a
-- tela é pequena. Muda junto com a tela (girar o celular, redimensionar a janela).
--
-- Platform.force("phone") troca na hora (testes e o emulador do Studio).

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Platform = {}

export type Kind = "phone" | "tablet" | "console" | "desktop"

-- multiplicador do texto grande e da placa em cima da cabeça, por aparelho
local TEXT: { [Kind]: number } = { phone = 0.72, tablet = 0.86, console = 1, desktop = 1 }
local TAG: { [Kind]: number } = { phone = 0.6, tablet = 0.8, console = 1, desktop = 1 }
local PHONE_SIDE = 600 -- lado menor da tela (px) abaixo do qual o toque conta como celular

local forced: Kind? = nil
local current: Kind = "desktop"
local changed = Instance.new("BindableEvent")
Platform.changed = changed.Event

local function detect(): Kind
	if forced then
		return forced
	end
	if GuiService:IsTenFootInterface() then
		return "console"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local size = workspace.CurrentCamera.ViewportSize
		return if math.min(size.X, size.Y) < PHONE_SIDE then "phone" else "tablet"
	end
	return "desktop"
end

local function refresh()
	local kind = detect()
	if kind ~= current then
		current = kind
		changed:Fire(kind)
	end
end

function Platform.kind(): Kind
	return current
end

-- Toque (celular ou tablet): mostra o editor do HUD e esconde as dicas de tecla.
function Platform.isTouch(): boolean
	return current == "phone" or current == "tablet"
end

function Platform.textScale(): number
	return TEXT[current]
end

function Platform.tagScale(): number
	return TAG[current]
end

function Platform.force(kind: Kind?)
	forced = kind
	refresh()
end

-- Chama fn agora e de novo a cada troca de aparelho.
function Platform.watch(fn: (Kind) -> ())
	fn(current)
	Platform.changed:Connect(fn)
end

current = detect()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
UserInputService.LastInputTypeChanged:Connect(refresh)

return Platform
