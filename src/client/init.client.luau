--!strict
-- Cliente: HUD, entrada e efeitos. Nenhuma regra de jogo mora aqui.

local Aura = require(script.Aura)
local Bag = require(script.Bag)
local Events = require(script.Events)
local Hud = require(script.Hud)
local Move = require(script.Move)
local Pose = require(script.Pose)
local Run = require(script.Run)
local Stats = require(script.Stats)

-- a ordem define a prioridade das poses: movimento < soco < carga e lançamento
Hud.start()
Pose.start()
Aura.start()
Move.start()
Bag.start()
Run.start()
Events.start()
Stats.start()
