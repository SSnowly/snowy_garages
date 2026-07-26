local Bridge      = require "bridge._index"
local VehicleType = require "client.vehicle_type"

local M = {}

---@param vehicle number
---@return boolean
function M.isEmpty(vehicle)
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for seat = -1, maxSeats - 2 do
        if GetPedInVehicleSeat(vehicle, seat) ~= 0 then return false end
    end
    return true
end

RegisterNetEvent('snowy_garages:forceLeaveVehicle', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if cache.vehicle ~= vehicle then return end

    TaskLeaveVehicle(cache.ped, vehicle, 0)
end)

---Deleting a vehicle without owning its network control can silently no-op for other
---clients (the delete doesn't propagate) - request control first so it actually disappears
---everywhere, not just locally.
---@param vehicle number
function M.forceDelete(vehicle)
    if not DoesEntityExist(vehicle) then return end

    if not NetworkHasControlOfEntity(vehicle) then
        NetworkRequestControlOfEntity(vehicle)
        local timeout = GetGameTimer() + 1000
        while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do
            Wait(0)
        end
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteEntity(vehicle)
end

-- Server-side deletion of a networked vehicle doesn't reliably reach every client, so bulk
-- cleanup (e.g. /impoundall) asks whichever client actually has the entity streamed in to
-- delete it locally instead - broadcast to everyone, only the relevant client(s) will resolve it.
RegisterNetEvent('snowy_garages:forceDeleteVehicle', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    M.forceDelete(vehicle)
end)

-- Same broadcast-and-whoever-has-it-streamed-in trick as forceDeleteVehicle above - the
-- periodic autosave (server/autosave.lua) has no way to read live vehicle properties itself,
-- so it asks every client and only the one(s) with the vehicle actually streamed in reply.
RegisterNetEvent('snowy_garages:autosaveRequest', function(netId, requestId, plate)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local props = Bridge.getVehicleProperties(vehicle)
    props.deformation = Bridge.getVehicleDeformation(vehicle)

    TriggerServerEvent('snowy_garages:autosaveResult', requestId, plate, props)
end)

---@param vehicle number
local function ejectPassengers(vehicle)
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    TriggerServerEvent('snowy_garages:requestEjectOccupants', NetworkGetNetworkIdFromEntity(vehicle), maxSeats)

    local timeout = GetGameTimer() + 30000
    while GetGameTimer() < timeout and not M.isEmpty(vehicle) do
        Wait(100)
    end
end

---@param garageIdentifier string
---@param spotId number
function M.storeVehicle(garageIdentifier, spotId)
    local vehicle = cache.vehicle
    if not vehicle then return end

    local plate = GetVehicleNumberPlateText(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local props = Bridge.getVehicleProperties(vehicle)
    props.deformation = Bridge.getVehicleDeformation(vehicle)

    ejectPassengers(vehicle)
    if not M.isEmpty(vehicle) then
        lib.notify({ title = locale('vehicle_store_failed'), type = 'error' })
        return
    end

    local model = GetEntityModel(vehicle)
    local modelName = GetEntityArchetypeName(vehicle)
    local vehicleType = VehicleType.classify(model)
    local ok = lib.callback.await('snowy_garages:storeVehicle', false, garageIdentifier, spotId, plate, netId, props, vehicleType, model, modelName)
    if ok == 'wrong_vehicle_type' then
        lib.notify({ title = locale('vehicle_wrong_type'), type = 'error' })
        return
    elseif not ok then
        lib.notify({ title = locale('vehicle_store_failed'), type = 'error' })
        return
    end

    M.forceDelete(vehicle)
    lib.notify({ title = locale('vehicle_stored'), type = 'success' })
end

return M
