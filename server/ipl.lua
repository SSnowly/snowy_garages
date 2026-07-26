local Garages = require "server.garages"

---@type table<number, { garage: string }>
local activeInstances = {}

---Each garage identifier gets its own stable bucket, shared by everyone inside it - so a
---garage is one instance for whoever uses it, not a separate copy per player.
---@type table<string, number>
local garageBuckets = {}
local nextBucket = 10000

---@param identifier string
---@return number
local function getGarageBucket(identifier)
    local bucket = garageBuckets[identifier]
    if not bucket then
        bucket = nextBucket
        nextBucket = nextBucket + 1
        garageBuckets[identifier] = bucket
    end
    return bucket
end

---@param source number
---@return boolean
local function isPlayerLoaded(source)
    return source > 0 and GetPlayerName(source) ~= nil
end

---@param vehicle number
---@param excludeSource number
---@param maxSeats number total seat count (driver included) - vehicle model data isn't
---loaded on a headless server, so this is measured client-side and passed in.
---@return number[]
local function getPassengerSources(vehicle, excludeSource, maxSeats)
    local passengers = {}
    for seat = 0, maxSeats - 2 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped) then
            local passengerSource = NetworkGetEntityOwner(ped)
            if passengerSource ~= 0 and passengerSource ~= excludeSource then
                passengers[#passengers + 1] = passengerSource
            end
        end
    end
    return passengers
end

lib.callback.register('snowy_garages:enterIpl', function(source, identifier, netId, maxSeats)
    if not isPlayerLoaded(source) then return false end

    local garage = Garages.getByIdentifier(identifier)
    if not garage or garage.type ~= 'ipl' or not garage.entry then return false end

    local playerCoords = GetEntityCoords(GetPlayerPed(source))
    if #(playerCoords - garage.coords) > 10.0 then return false end

    local vehicle = nil
    if netId then
        vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
        if NetworkGetEntityOwner(vehicle) ~= source then return false end
        if type(maxSeats) ~= 'number' then return false end
    end

    local bucket = getGarageBucket(identifier)
    SetPlayerRoutingBucket(source, bucket)
    activeInstances[source] = { garage = identifier }

    if vehicle then
        SetEntityRoutingBucket(vehicle, bucket)

        for _, passengerSource in ipairs(getPassengerSources(vehicle, source, maxSeats)) do
            SetPlayerRoutingBucket(passengerSource, bucket)
            activeInstances[passengerSource] = { garage = identifier }
            TriggerClientEvent('snowy_garages:iplEnteredAsPassenger', passengerSource, garage)
        end
    end

    return garage.entry
end)

lib.callback.register('snowy_garages:exitIpl', function(source, identifier, netId, maxSeats)
    if not isPlayerLoaded(source) then return false end

    local instance = activeInstances[source]
    if not instance or instance.garage ~= identifier then return false end

    local garage = Garages.getByIdentifier(identifier)
    if not garage then return false end

    local vehicle = nil
    if netId then
        vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
        if type(maxSeats) ~= 'number' then return false end
    end

    SetPlayerRoutingBucket(source, 0)
    activeInstances[source] = nil

    if vehicle then
        SetEntityRoutingBucket(vehicle, 0)

        for _, passengerSource in ipairs(getPassengerSources(vehicle, source, maxSeats)) do
            SetPlayerRoutingBucket(passengerSource, 0)
            activeInstances[passengerSource] = nil
            TriggerClientEvent('snowy_garages:iplExitedAsPassenger', passengerSource, identifier)
        end
    end

    local exitPoint, exitHeading
    if vehicle and garage.vehicleCoords then
        exitPoint, exitHeading = garage.vehicleCoords, garage.vehicleCoordsHeading
    else
        exitPoint, exitHeading = garage.coords, garage.coordsHeading
    end

    return { x = exitPoint.x, y = exitPoint.y, z = exitPoint.z, heading = exitHeading or 0.0 }
end)

AddEventHandler('playerDropped', function()
    local source = source
    activeInstances[source] = nil
end)
