--!strict
-- Layout do HUD escolhido pelo jogador (editor no celular: client/HudEditor.luau): para cada
-- bloco, deslocamento da posição padrão (fração da tela), tamanho e opacidade. Fica no perfil
-- como texto JSON (PlayerData.hud) e chega ao cliente pelo atributo "HudLayout".

local HttpService = game:GetService("HttpService")

local HudLayout = {}

export type Entry = { x: number, y: number, s: number, o: number }
export type Layout = { [string]: Entry }

-- blocos editáveis: nome do objeto no HUD (ou "Jump", o botão de pular do Roblox) e o rótulo
HudLayout.BLOCKS = {
	{ id = "LeftButtons", label = "MENU" },
	{ id = "TopRight", label = "SHORTCUTS" },
	{ id = "Stats", label = "MONEY & POWER" },
	{ id = "Hotbar", label = "HOTBAR" },
	{ id = "Jump", label = "JUMP" },
}
HudLayout.SIZE = { min = 0.5, max = 1.6 }
HudLayout.OPACITY = { min = 0.2, max = 1 }
HudLayout.MAX_LENGTH = 1200

local known: { [string]: boolean } = {}
for _, block in HudLayout.BLOCKS do
	known[block.id] = true
end

local function number(value: any, low: number, high: number, default: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.floor(math.clamp(value, low, high) * 1000 + 0.5) / 1000
end

function HudLayout.default(): Entry
	return { x = 0, y = 0, s = 1, o = 1 }
end

-- Só blocos conhecidos e números dentro dos limites; o resto é descartado.
function HudLayout.sanitize(raw: any): Layout
	local layout: Layout = {}
	if type(raw) ~= "table" then
		return layout
	end
	for id, entry in raw do
		if known[id] and type(entry) == "table" then
			local clean = {
				x = number(entry.x, -1, 1, 0),
				y = number(entry.y, -1, 1, 0),
				s = number(entry.s, HudLayout.SIZE.min, HudLayout.SIZE.max, 1),
				o = number(entry.o, HudLayout.OPACITY.min, HudLayout.OPACITY.max, 1),
			}
			if clean.x ~= 0 or clean.y ~= 0 or clean.s ~= 1 or clean.o ~= 1 then
				layout[id] = clean
			end
		end
	end
	return layout
end

function HudLayout.decode(text: any): Layout
	if type(text) ~= "string" or text == "" or #text > HudLayout.MAX_LENGTH then
		return {}
	end
	local ok, raw = pcall(HttpService.JSONDecode, HttpService, text)
	return if ok then HudLayout.sanitize(raw) else {}
end

function HudLayout.encode(layout: Layout): string
	local clean = HudLayout.sanitize(layout)
	return if next(clean) then HttpService:JSONEncode(clean) else ""
end

return HudLayout
