--!strict
-- Estado do servidor compartilhado entre os módulos: terrenos, donos e remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local State = {
	plots = {} :: { Model },
	owners = {} :: { [number]: Player },
	plotOf = {} :: { [Player]: number },
	remotes = {} :: { [string]: RemoteEvent },
}

function State.createRemotes(names: { string })
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in names do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		State.remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
end

function State.plot(player: Player): Model?
	local id = State.plotOf[player]
	return if id then State.plots[id] else nil
end

function State.root(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Ponto de nascimento do terreno, de frente para o saco.
function State.spawnCFrame(plot: Model): CFrame
	local origin = plot:GetAttribute("Origin") :: CFrame
	local position = (origin * CFrame.new(Config.Plot.spawnOffset)).Position
	local bag = (origin * CFrame.new(Config.Plot.bagOffset)).Position
	return CFrame.lookAt(position, Vector3.new(bag.X, position.Y, bag.Z))
end

return State
