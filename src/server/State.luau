--!strict
-- Estado do servidor compartilhado entre os módulos: terrenos, donos e remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local State = {
	plots = {} :: { Model }, -- os terrenos do mundo 1
	worldPlots = {} :: { [number]: { Model } }, -- por mundo: worldPlots[mundo][id]; o [1] é `plots`
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

-- O terreno do jogador no mundo em que ele está.
function State.plot(player: Player): Model?
	local id = State.plotOf[player]
	if not id then
		return nil
	end
	local here = State.worldPlots[Config.worldOf(player).id]
	return (here and here[id]) or State.plots[id]
end

-- O mesmo terreno em todos os mundos (as cópias mostram sempre a mesma coisa).
function State.copies(plot: Model): { Model }
	local id = plot:GetAttribute("PlotId")
	local list = {}
	for _, plots in State.worldPlots do
		if plots[id] then
			table.insert(list, plots[id])
		end
	end
	if #list == 0 then
		table.insert(list, plot)
	end
	return list
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

-- Mundo em que o jogador está (atributo "World").
function State.world(player: Player): any
	return Config.worldOf(player)
end

-- Onde o jogador aparece no mundo 2: no meio da ilha, olhando para o portão da pista.
function State.arriveCFrame(world: any): CFrame
	local at = world.offset + Config.Volcano.arrive + Vector3.new(0, Config.World.groundY, 0)
	return CFrame.lookAt(at, at + Vector3.new(0, 0, -1))
end

-- Para onde o jogador volta quando cai do mapa: o terreno dele no mundo em que está.
function State.homeCFrame(player: Player): CFrame?
	local plot = State.plot(player)
	return if plot then State.spawnCFrame(plot) else nil
end

-- Ponto de largada da zona de carga do mundo em que o jogador está, de frente para a pista.
function State.zoneCFrame(player: Player): CFrame
	return CFrame.new(Config.zoneCenter(Config.worldOf(player)) + Config.Run.teleportOffset)
end

return State
