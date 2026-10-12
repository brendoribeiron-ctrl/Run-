--!strict
-- Formatação de números do HUD: curto em repouso (15K), dígitos cheios enquanto muda (14,989).

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Format.abbreviate(value: number): string
	local n = math.floor(value)
	if n < 1000 then
		return tostring(n)
	end
	local index = 1
	local scaled = n
	while scaled >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end
	-- uma casa decimal, truncada, sem ".0"
	local truncated = math.floor(scaled * 10) / 10
	local text = string.format("%.1f", truncated)
	text = string.gsub(text, "%.0$", "")
	return text .. SUFFIXES[index]
end

function Format.commas(value: number): string
	local text = tostring(math.floor(value))
	local out = text
	while true do
		local replaced, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return out
end

return Format
