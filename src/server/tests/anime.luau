-- Personagens de anime: os 18 avatares do catálogo (Shared.AnimeCast) chegam em
-- ReplicatedStorage.CharacterMeshes com roupa e cabelo, cada personagem (e as variantes de magma
-- e Shiny) monta pelo avatar, com a cabeça para o letreiro, e o pedestal mostra o modelo novo.
--   node tools/bridge.cjs run server src/server/tests/anime.luau 120000

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterModels = require(ReplicatedStorage.Shared.CharacterModels)
local Config = require(ReplicatedStorage.Shared.Config)
local hook = ServerStorage:WaitForChild("TestHook", 5)
assert(hook, "TestHook ausente")

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")

local passed = {}
local function check(name, condition, detail)
	assert(condition, `FALHOU: {name} ({detail})`)
	table.insert(passed, name)
end

local holder = ReplicatedStorage:WaitForChild("CharacterMeshes", 10)
check("pasta dos modelos existe", holder ~= nil, "")
local deadline = os.clock() + 40
while #holder:GetChildren() < #Config.Characters and os.clock() < deadline do
	task.wait(0.5)
end
check("os 18 modelos carregaram", #holder:GetChildren() == #Config.Characters, `{#holder:GetChildren()}/{#Config.Characters}`)

local heights = {}
for _, info in Config.Characters do
	check(`{info.id} tem modelo`, info.model ~= nil and holder:FindFirstChild(info.model) ~= nil, tostring(info.model))
	for _, id in { info.id, info.id .. "_magma", info.id .. Config.Fusion.suffix } do
		local model = CharacterModels.build(id)
		check(`{id} usa o modelo de anime`, model:GetAttribute("Anime") == true, id)
		check(`{id} tem a cabeça`, model:FindFirstChild("Head") ~= nil, id)
		check(`{id} tem camisa e calça`, model:FindFirstChildOfClass("Shirt") ~= nil and model:FindFirstChildOfClass("Pants") ~= nil, id)
		check(`{id} tem cabelo`, model:FindFirstChildOfClass("Accessory") ~= nil, id)
		local head, torso = model:FindFirstChild("Head") :: BasePart, model:FindFirstChild("Torso") :: BasePart
		local sole = math.huge
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				sole = math.min(sole, part.Position.Y - part.Size.Y / 2)
			end
		end
		check(`{id} está de pé na origem`, head.Position.Y > torso.Position.Y and math.abs(sole) < 0.05, `{id} sola={sole}`)
		local _, size = model:GetBoundingBox()
		if id == info.id then
			table.insert(heights, `{info.model}={math.floor(size.Y * 10) / 10}`)
		end
		check(`{id} tem altura de boneco`, size.Y > 3.5 and size.Y < 8, tostring(size))
		model:Destroy()
	end
end
-- magma escurece o corpo
local plain = CharacterModels.build("frost_hook")
local magma = CharacterModels.build("frost_hook_magma")
local function skin(model: Model): Color3?
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Torso" then
			return part.Color
		end
	end
	return nil
end
local a, b = skin(plain), skin(magma)
check("magma escurece a pele", a and b and (b.R + b.G + b.B) < (a.R + a.G + a.B), `{a} -> {b}`)
plain:Destroy()
magma:Destroy()

-- pedestal: coloca um personagem e confere que o modelo do pedestal é o de anime
hook:Invoke("set", player, { money = 1200, inventory = { "shadow_sensei", "frost_hook" } })
task.wait(1)
local found
for _, d in workspace:GetDescendants() do
	if d.Name == "Character" and d:IsA("Model") and d:GetAttribute("Anime") ~= nil then
		found = d
		break
	end
end
if found then
	check("pedestal usa o modelo de anime", found:GetAttribute("Anime") == true, found:GetFullName())
end

print("alturas: " .. table.concat(heights, " "))
return `{#passed} checagens ok`
