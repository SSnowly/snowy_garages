local Config = require "configs.shared.main"
local Plates = require "configs.shared.plates"

if not Config.npcPlatePattern then return end

AddEventHandler('entityCreated', function(entity)
    if GetEntityType(entity) ~= 2 then return end
    -- Pop type 7 = POPTYPE_MISSION: script-spawned vehicles (players, other resources).
    -- Anything below 7 is ambient/NPC traffic spawned by the world engine.
    if GetEntityPopulationType(entity) == 7 then return end
    SetVehicleNumberPlateText(entity, Plates.generate(Config.npcPlatePattern))
end)
