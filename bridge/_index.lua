if IsDuplicityVersion() then
    local fw       = require "bridge.framework"
    local identity = require "bridge.identity"
    local money    = require "bridge.money"
    local keys     = require "bridge.keys"

    return {
        framework           = fw.name,
        identifierColumn    = fw.identifierColumn,
        getPlayerIdentifier = identity.getPlayerIdentifier,
        getPlayerJob        = identity.getPlayerJob,
        getPlayerGang       = identity.getPlayerGang,
        getPlayerGroup      = identity.getPlayerGroup,
        getMoney            = money.getMoney,
        removeMoney         = money.removeMoney,
        giveVehicleKeys     = keys.giveVehicleKeys,
    }
else
    local vehicle = require "bridge.vehicle"

    return {
        setVehicleProperties  = vehicle.setVehicleProperties,
        getVehicleProperties  = vehicle.getVehicleProperties,
        getVehicleDeformation = vehicle.getVehicleDeformation,
        setVehicleDeformation = vehicle.setVehicleDeformation,
    }
end
