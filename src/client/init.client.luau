--!strict
-- Cliente: HUD, entrada e efeitos. Nenhuma regra de jogo mora aqui.

local Aura = require(script.Aura)
local Auto = require(script.Auto)
local Bag = require(script.Bag)
local Events = require(script.Events)
local Hud = require(script.Hud)
local Menus = require(script.Menus)
local Move = require(script.Move)
local Pose = require(script.Pose)
local Run = require(script.Run)
local Stats = require(script.Stats)
local Super = require(script.Super)

-- a ordem define a prioridade das poses: movimento < soco < carga e lançamento
Hud.start()
Pose.start()
Aura.start()
Move.start()
Bag.start()
Super.start()
Run.start()
Events.start()
Stats.start()
Auto.start()
Menus.start()
