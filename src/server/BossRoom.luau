--!strict
-- Sala do chefe: a rotunda para onde vai quem limpa o corredor inteiro (modelo em
-- tools/blender/boss_room.py). Cada jogador luta sozinho, na sua cópia da sala (com o seu golem):
-- as cópias de um mundo ficam em fila (Config.BossRoom.spacing), nascem quando faltam e são
-- reaproveitadas quando o dono sai. A primeira ("BossRoom<mundo>") é montada ao abrir o servidor;
-- as outras se chamam "BossRoom<mundo>_<n>". O jogador sabe qual é a dele pelo atributo RoomKey.
-- Todas com as cores do mundo: o mesmo modelo, pintado pelo nome das peças. Ficam longe e no alto
-- (Config.BossRoom.center), fora do alcance de quem está no mapa. O chefe (src/server/Boss.luau)
-- dorme no círculo mágico do centro; a entrada é encenada pelo cliente e a saída é pela porta.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boss = require(script.Parent.Boss)
local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(script.Parent.Models)
local State = require(script.Parent.State)

local ROOM = Config.BossRoom
local K = ROOM.scale -- tudo que vem do modelo é multiplicado por isto
local BossRoom = {}

-- Personagem a sortear para quem limpou o corredor e ainda não enfrentou o chefe.
local pending: { [Player]: boolean } = {}

-- Uma cópia da sala. ready = já montada; owner = quem está lutando nela.
type Slot = { key: string, world: any, index: number, center: Vector3, ready: boolean, owner: Player? }
local slots: { [number]: { Slot } } = {} -- por mundo
local owned: { [Player]: Slot } = {}
-- Modelo da sala de cada mundo já pintado (só é baixado uma vez; as cópias são clones dele).
local templates: { [number]: Model } = {}
-- Quem sorteia e entrega o personagem (Run.reward, ligado pelo init do servidor).
BossRoom.rewarder = nil :: ((Player) -> (string?, boolean))?

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local M = Enum.Material
-- arcano (gramado): pedra azul-aço, ouro e carmesim, como o salão do trono de referência
local ARCANE: { [string]: Models.Style } = {
	Stone = { color = rgb(58, 72, 128), material = M.Slate },
	Dark = { color = rgb(18, 22, 54), material = M.Slate },
	Path = { color = rgb(126, 140, 188), material = M.Marble },
	Tile = { color = rgb(28, 38, 92), material = M.Slate },
	Dome = { color = rgb(36, 46, 96), material = M.Slate },
	Gold = { color = rgb(255, 196, 72), material = M.Metal },
	Inlay = { color = rgb(255, 190, 60), material = M.Metal },
	Crimson = { color = rgb(190, 18, 40), material = M.Neon },
	Banner = { color = rgb(140, 14, 30), material = M.Fabric },
	Glass = { color = rgb(110, 150, 230), material = M.Neon },
	Flame = { color = rgb(255, 160, 50), material = M.Neon },
	Rune = { color = rgb(110, 190, 255), material = M.Neon },
	Wax = { color = rgb(236, 226, 204), material = M.SmoothPlastic },
	DoorL = { color = rgb(22, 28, 66), material = M.Wood },
	DoorR = { color = rgb(22, 28, 66), material = M.Wood },
	DoorLGold = { color = rgb(255, 196, 72), material = M.Metal },
	DoorRGold = { color = rgb(255, 196, 72), material = M.Metal },
}
-- magma (vulcão): basalto, bronze e brasa
local MAGMA: { [string]: Models.Style } = {
	Stone = { color = rgb(74, 56, 62), material = M.Basalt },
	Dark = { color = rgb(30, 20, 26), material = M.Basalt },
	Path = { color = rgb(112, 88, 92), material = M.Slate },
	Tile = { color = rgb(42, 26, 30), material = M.Slate },
	Dome = { color = rgb(48, 34, 40), material = M.Basalt },
	Gold = { color = rgb(255, 150, 50), material = M.Metal },
	Inlay = { color = rgb(255, 120, 30), material = M.Neon },
	Crimson = { color = rgb(255, 80, 20), material = M.Neon },
	Banner = { color = rgb(70, 12, 12), material = M.Fabric },
	Glass = { color = rgb(220, 100, 40), material = M.Neon },
	Flame = { color = rgb(255, 190, 80), material = M.Neon },
	Rune = { color = rgb(255, 90, 30), material = M.Neon },
	Wax = { color = rgb(60, 50, 50), material = M.SmoothPlastic },
	DoorL = { color = rgb(36, 24, 28), material = M.Basalt },
	DoorR = { color = rgb(36, 24, 28), material = M.Basalt },
	DoorLGold = { color = rgb(255, 150, 50), material = M.Metal },
	DoorRGold = { color = rgb(255, 150, 50), material = M.Metal },
}
local STYLES = { ARCANE, MAGMA }

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Shape = shape or Enum.PartType.Block
	p.Transparency = 1
	p.CanCollide = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Centro do piso da cópia `index` da sala de um mundo.
local function centerOf(world: any, index: number): Vector3
	return ROOM.center + world.offset + Vector3.new(index * ROOM.spacing, 0, 0)
end

-- Onde o jogador aparece: perto da porta, olhando para o círculo do centro.
local function entryCFrame(center: Vector3): CFrame
	local at = center + Vector3.new(0, 3, ROOM.entry * K)
	return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
end

-- Colisão simples: piso, parede em volta, pilares, estrado do centro e degraus do trono. O
-- modelo não colide (Models.load).
local function colliders(folder: Instance, center: Vector3)
	local box = Instance.new("Folder")
	box.Name = "Colliders"
	box.Parent = folder
	local R = ROOM.radius * K
	part(box, "Floor", Vector3.new(4, (R + 6) * 2, (R + 6) * 2), CFrame.new(center - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder) -- 1 stud abaixo do piso do modelo, que é quem segura a câmera
	local bays = 16
	for i = 0, bays - 1 do
		local angle = i * 2 * math.pi / bays
		-- a câmera do Roblox só para em peça que colide e é quase opaca: a parede de colisão é
		-- opaca e ocupa a espessura inteira da parede do modelo, começando um pouco atrás da face
		-- de dentro (para não brigar com ela na tela). Assim ninguém entra na parede.
		local thick = 4 * K - 0.6
		local width = 2 * (R + 4 * K) * math.tan(math.pi / bays) + 1
		local bay = CFrame.new(center) * CFrame.Angles(0, angle, 0)
		local function wall(w: number, h: number, x: number, y: number, see: boolean)
			local p = part(box, "Wall", Vector3.new(w, h, thick), bay * CFrame.new(x, y, R + 0.3 + thick / 2))
			if see then
				p.Transparency = 0
				p.Color = Color3.fromRGB(20, 24, 50)
			end
		end
		local height = ROOM.wallHeight * K
		if i > 0 then
			wall(width, height, 0, height / 2, true)
		else
			-- vão da porta: parede dos dois lados e em cima da abertura; na abertura, uma parede
			-- invisível (a câmera passa e para no véu de fora, as folhas da porta continuam à vista)
			local door, top = 16 * K, 28 * K
			local side = (width - door) / 2
			for _, s in { -1, 1 } do
				wall(side, height, s * (door + side) / 2, height / 2, true)
			end
			wall(door, height - top, 0, top + (height - top) / 2, true)
			wall(door, top, 0, top / 2, false)
		end
		-- pilares: entre um vão e o próximo
		local p = CFrame.new(center) * CFrame.Angles(0, angle + math.pi / bays, 0) * CFrame.new(0, 23 * K, ROOM.pillarRing * K)
		part(box, "Pillar", Vector3.new(46, 5, 5) * K, p * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	end
	-- teto invisível na altura do topo dos pilares: ninguém sobe neles, na parede ou na cúpula
	-- (pulo duplo, montaria). A câmera atravessa e para na cúpula, que é opaca.
	part(box, "Lid", Vector3.new((R + 6) * 2, 4, (R + 6) * 2), CFrame.new(center + Vector3.new(0, 46 * K + 2, 0)))
	part(box, "Dais", Vector3.new(1.1, 30, 30) * K, CFrame.new(center + Vector3.new(0, 0.55, 0) * K) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	-- degraus do trono (o trono fica em -Z, do outro lado da porta)
	for _, step in { { 34, 20, 1 }, { 28, 15, 2 }, { 22, 11, 3 } } do
		part(box, "Step", Vector3.new(step[1], step[3], step[2]) * K, CFrame.new(center + Vector3.new(0, step[3] / 2, -(36 + step[2] / 2)) * K))
	end
	-- trono (assento e encosto), os dois braseiros do estrado e as quatro pedras de runa
	-- (medidas de tools/blender/boss_room.py; o Y do Blender vira -Z aqui)
	local function solid(name: string, size: Vector3, at: Vector3)
		part(box, name, size * K, CFrame.new(center + at * K))
	end
	solid("Throne", Vector3.new(7.4, 2.8, 5.2), Vector3.new(0, 4.4, -44))
	solid("ThroneBack", Vector3.new(7.4, 15.5, 1.8), Vector3.new(0, 10.75, -46.6))
	for _, s in { -1, 1 } do
		solid("ThroneArm", Vector3.new(1.2, 2.4, 4.8), Vector3.new(s * 3.4, 6.2, -44))
		solid("Brazier", Vector3.new(4.2, 9, 4.2), Vector3.new(s * 15, 5.5, -40))
	end
	for j = 0, 3 do
		local a = math.pi / 4 + j * math.pi / 2
		solid("RuneStone", Vector3.new(1.8, 4.8, 1.8), Vector3.new(17.5 * math.cos(a), 2.4, -17.5 * math.sin(a)))
	end
end

local function lights(folder: Instance, center: Vector3, world: any)
	local style = STYLES[world.id] or ARCANE
	local glow = Instance.new("Folder")
	glow.Name = "Lights"
	glow.Parent = folder
	local function light(at: Vector3, color: Color3, range: number, brightness: number)
		local holder = Instance.new("Part")
		holder.Name = "Light"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(at)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = holder
		holder.Parent = glow
	end
	-- uma lanterna em cada pilar e a luz fria do círculo mágico
	for i = 0, 15 do
		local angle = i * 2 * math.pi / 16 + math.pi / 16
		local at = (CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 30 * K, (ROOM.pillarRing - 3.2) * K)).Position
		light(at, style.Flame.color, 50, 2.6)
	end
	light(center + Vector3.new(0, 8, 0), style.Rune.color, 60, 3)
	light(center + Vector3.new(0, 40 * K, 0), style.Glass.color, 60, 1.6)
	light(center + Vector3.new(0, 12 * K, -44 * K), style.Flame.color, 50, 2.6)
	-- luz de enchimento: a sala é fechada e o sol não entra (o alcance máximo de uma luz é 60)
	for ring = 1, 2 do
		local count = ring * 4
		for i = 0, count - 1 do
			local angle = i * 2 * math.pi / count + math.pi / count
			local reach = ring * 34 * K / 2
			light(center + Vector3.new(math.sin(angle) * reach, 22 * K, math.cos(angle) * reach), style.Glass.color, 60, 1.4)
		end
	end
end

-- Monta uma cópia da sala.
local function build(slot: Slot)
	local world, center = slot.world, slot.center
	local folder = Instance.new("Folder")
	folder.Name = slot.key
	folder:SetAttribute("World", world.id)
	folder:SetAttribute("Slot", slot.index)
	folder:SetAttribute("Center", center)
	colliders(folder, center)
	lights(folder, center, world)
	if not templates[world.id] then
		templates[world.id] = Models.load("boss_room", STYLES[world.id] or ARCANE)
	end
	local template = templates[world.id]
	local model = if template then template:Clone() else nil
	if model then
		model:ScaleTo(model:GetScale() * K)
		model:PivotTo(CFrame.new(center))
		-- piso e cúpula seguram a câmera (ninguém alcança a cúpula, então a colisão dela não atrapalha)
		for _, name in { "Path_boss_room", "Dome_boss_room" } do
			local piece = model:FindFirstChild(name)
			if piece and piece:IsA("BasePart") then
				piece.CanCollide = true
				piece.CanQuery = true
			end
		end
		model.Parent = folder
	else
		warn("[BossRoom] o modelo da sala não carregou")
	end

	-- do lado de fora da porta, colado na face de fora da parede, um véu de magia opaco e bem
	-- maior que a abertura: com a porta aberta (na cena de entrada) não se vê céu de nenhum ângulo
	local veil = part(folder, "Veil", Vector3.new(32 * K, 44 * K, 2), CFrame.new(center + Vector3.new(0, 18 * K, ROOM.radius * K + 4 * K + 1)))
	veil.CanCollide = true -- segura a câmera no vão da porta
	veil.Transparency = 0
	veil.Material = Enum.Material.Neon
	veil.Color = (STYLES[world.id] or ARCANE).Rune.color:Lerp(Color3.new(0, 0, 0), 0.55)

	-- saída: a porta, por dentro, na altura de quem está no chão
	local door = part(folder, "Exit", Vector3.new(14 * K, 8, 2), CFrame.new(center + Vector3.new(0, 4, ROOM.radius * K - 1)))
	door.CanCollide = false
	door.CanQuery = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LeaveRoom"
	prompt.ObjectText = ROOM.names[world.id] or "Throne Room"
	prompt.ActionText = "Leave"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = ROOM.exitRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	prompt.Triggered:Connect(function(player)
		BossRoom.leave(player)
	end)

	-- o chefe dorme no círculo do centro: desafiar acorda ele (Boss.challenge); só quem limpou
	-- o corredor e ainda não lutou pode desafiar
	local circle = part(folder, "Challenge", Vector3.new(4, 4, 4), CFrame.new(center + Vector3.new(0, 3 * K, 0)))
	circle.CanCollide = false
	circle.CanQuery = false
	local challenge = Instance.new("ProximityPrompt")
	challenge.Name = "Challenge"
	challenge.ObjectText = Config.Boss.names[world.id] or Config.Boss.names[1]
	challenge.ActionText = "Challenge"
	challenge.HoldDuration = 0.6
	challenge.MaxActivationDistance = ROOM.challengeRange
	challenge.RequiresLineOfSight = false
	challenge.Parent = circle
	challenge.Triggered:Connect(function(player)
		Boss.challenge(player, BossRoom.hasPending(player))
	end)

	folder.Parent = workspace
	Boss.build(world, folder, center, challenge, slot.key)
	slot.ready = true
end

-- Cria (e começa a montar) a próxima cópia da sala de um mundo.
local function newSlot(world: any): Slot
	local list = slots[world.id]
	local index = #list
	local slot: Slot = {
		key = "BossRoom" .. world.id .. (if index > 0 then "_" .. index else ""),
		world = world,
		index = index,
		center = centerOf(world, index),
		ready = false,
		owner = nil,
	}
	table.insert(list, slot)
	task.spawn(build, slot)
	return slot
end

-- A sala do jogador neste mundo: a que ele já tem, uma livre ou uma nova. Espera ela ficar pronta.
local function acquire(player: Player, world: any): Slot?
	local slot = owned[player]
	if slot and slot.world ~= world then
		BossRoom.release(player)
		slot = nil
	end
	if not slot then
		for _, free in slots[world.id] do
			if free.owner == nil then
				slot = free
				break
			end
		end
		slot = slot or newSlot(world)
		local mine = slot :: Slot
		mine.owner = player
		owned[player] = mine
	end
	local deadline = os.clock() + 10
	while not (slot :: Slot).ready and os.clock() < deadline do
		task.wait(0.05)
	end
	return if (slot :: Slot).ready then slot else nil
end

-- Devolve a sala do jogador (saiu, morreu, viajou): o golem volta a dormir para o próximo dono.
function BossRoom.release(player: Player)
	local slot = owned[player]
	owned[player] = nil
	player:SetAttribute("RoomKey", nil)
	if slot and slot.owner == player then
		slot.owner = nil
		Boss.reset(slot.key)
	end
end

function BossRoom.build()
	Boss.onVictory = function(player)
		BossRoom.victory(player)
	end
	Boss.onDefeat = function(player)
		BossRoom.setPending(player, false)
	end
	Boss.loadModels()
	Boss.start()
	for _, world in Config.Worlds do
		slots[world.id] = {}
		newSlot(world)
	end
end

-- Leva o jogador para a sala dele no mundo em que ele está.
function BossRoom.enter(player: Player)
	local character = player.Character
	local world = State.world(player)
	if not character then
		return
	end
	local slot = acquire(player, world)
	if not slot or player.Character ~= character then
		return
	end
	local target = entryCFrame(slot.center)
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 3)
	end)
	if player.Character ~= character or owned[player] ~= slot then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	player:SetAttribute("RoomKey", slot.key)
	player:SetAttribute("Room", world.id)
	character:PivotTo(target)
end

-- Quem limpou o corredor ganha o direito a um sorteio, feito depois da luta com o chefe.
function BossRoom.setPending(player: Player, on: boolean)
	pending[player] = if on then true else nil
	player:SetAttribute("BossReward", on or nil)
end

function BossRoom.hasPending(player: Player): boolean
	return pending[player] == true
end

-- Vitória contra o chefe (Boss.luau chama quando ele se desfaz): sorteia e entrega o personagem, e o cliente mostra o sorteio.
function BossRoom.victory(player: Player): boolean
	if not pending[player] or player:GetAttribute("Room") == nil or not BossRoom.rewarder then
		return false
	end
	BossRoom.setPending(player, false)
	local id, isNew = (BossRoom.rewarder :: any)(player)
	if id then
		State.remotes.BossReward:FireClient(player, id, isNew)
	end
	return id ~= nil
end

-- Sai da sala de volta para a zona de carga do mundo.
function BossRoom.leave(player: Player): boolean
	local character = player.Character
	if not character or player:GetAttribute("Room") == nil then
		return false
	end
	player:SetAttribute("Room", nil)
	local target = State.zoneCFrame(player)
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 3)
	end)
	character:PivotTo(target)
	return true
end

-- Quem sai da sala por outro caminho (botão CORRER, viagem, morte) deixa de estar nela e a
-- sala fica livre.
function BossRoom.connect()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Room", nil)
		end)
		player:GetAttributeChangedSignal("Room"):Connect(function()
			if player:GetAttribute("Room") == nil and owned[player] then
				BossRoom.release(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		BossRoom.release(player)
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return BossRoom
