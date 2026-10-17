--!strict
-- Monta o elenco de anime (Shared.AnimeCast) como avatares R6 do catálogo e guarda em
-- ReplicatedStorage.CharacterMeshes, com os pés na origem e a frente em -Z. CharacterModels.build
-- copia de lá; enquanto um personagem não chegou, ele monta o boneco de peças antigo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeCast = require(ReplicatedStorage.Shared.AnimeCast)
local Config = require(ReplicatedStorage.Shared.Config)

local CharacterMeshes = {}

local BODY = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }

local function description(avatar: AnimeCast.Avatar): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	desc.HairAccessory = if avatar.hair then tostring(avatar.hair) else ""
	desc.FaceAccessory = if avatar.face then tostring(avatar.face) else ""
	desc.BackAccessory = if avatar.back then tostring(avatar.back) else ""
	desc.WaistAccessory = if avatar.waist then tostring(avatar.waist) else ""
	desc.ShouldersAccessory = if avatar.shoulder then tostring(avatar.shoulder) else ""
	desc.Shirt = avatar.shirt or 0
	desc.Pants = avatar.pants or 0
	for _, prop in BODY do
		(desc :: any)[prop] = avatar.skin
	end
	return desc
end

-- O modelo sai fora do Workspace, sem física: as soldas dos acessórios não encaixam sozinhas.
local function placeAccessories(model: Model)
	for _, accessory in model:GetChildren() do
		local handle = if accessory:IsA("Accessory") then accessory:FindFirstChild("Handle") else nil
		if not handle or not handle:IsA("BasePart") then
			continue
		end
		for _, own in handle:GetChildren() do
			if not own:IsA("Attachment") then
				continue
			end
			for _, part in model:GetChildren() do
				local target = if part:IsA("BasePart") then part:FindFirstChild(own.Name) else nil
				if target and target:IsA("Attachment") then
					handle.CFrame = target.WorldCFrame * own.CFrame:Inverse()
					break
				end
			end
		end
	end
end

local function build(key: string, avatar: AnimeCast.Avatar): Model?
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description(avatar), Enum.HumanoidRigType.R6)
	end)
	if not ok or not result then
		warn(`[CharacterMeshes] {key} não montou ({result})`)
		return nil
	end
	local model = result :: Model
	placeAccessories(model)
	local head = model:FindFirstChild("Head")
	local face = if head then head:FindFirstChild("face") else nil
	if face and avatar.face then
		face:Destroy() -- o rosto de anime cobre o rosto padrão
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.EvaluateStateMachine = false
	end
	-- pivô na sola dos pés (o do avatar fica no meio do tronco), frente em -Z
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		model.PrimaryPart = root
		local bottom = math.huge
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				bottom = math.min(bottom, part.Position.Y - part.Size.Y / 2)
			end
		end
		root.PivotOffset = CFrame.new(0, bottom - root.Position.Y, 0)
	end
	model:PivotTo(CFrame.identity)
	return model
end

-- Monta todos em paralelo e chama onReady quando o último terminar (ou falhar).
function CharacterMeshes.load(onReady: (() -> ())?)
	if ReplicatedStorage:FindFirstChild("CharacterMeshes") then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "CharacterMeshes"
	holder.Parent = ReplicatedStorage

	local pending = 0
	local function done()
		pending -= 1
		if pending == 0 and onReady then
			onReady()
		end
	end
	for _, info in Config.Characters do
		local key = info.model
		local avatar = if key then AnimeCast[key] else nil
		if not avatar then
			continue
		end
		pending += 1
		task.spawn(function()
			local model = build(key, avatar)
			if model then
				model.Name = key
				model.Parent = holder
			end
			done()
		end)
	end
end

return CharacterMeshes
