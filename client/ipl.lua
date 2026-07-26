local Config = require "configs.shared.main"
local Spots  = require "client.spots"

local M = {}

---@type Garage?
local activeGarage = nil

---@type boolean
local nearExit = false

local exitKeybind = lib.addKeybind({
    name        = 'snowy_garages_exit_ipl',
    description = locale('garage_exit_ipl'),
    defaultKey  = 'E',
    onPressed   = function()
        if not activeGarage then return end
        M.exit(activeGarage)
    end,
})
exitKeybind:disable(true)

local function clearExitPrompt()
    if not nearExit then return end
    nearExit = false
    exitKeybind:disable(true)
    lib.hideTextUI()
end

-- Which exit point is relevant has to be re-checked every tick, not decided once at entry -
-- getting out of the car and walking to the onFoot point (or vice versa) must still work,
-- not just whichever way you happened to arrive.
CreateThread(function()
    while true do
        if not activeGarage then
            Wait(500)
        else
            local point = cache.vehicle and activeGarage.entry.vehicle or activeGarage.entry.onFoot
            local playerCoords = GetEntityCoords(cache.ped)
            local coords = vector3(point.x, point.y, point.z)
            local dist = #(playerCoords - coords)

            if dist < 15.0 then
                local me = Config.markers.entryPoint
                DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, me.r, me.g, me.b, me.a, false, false, 2, false, nil, nil, false)
            end

            if dist < Config.iplInteractDistance then
                if not nearExit then
                    nearExit = true
                    exitKeybind:disable(false)
                    lib.showTextUI(locale('garage_exit_ipl'), { position = 'right-center', icon = 'right-from-bracket' })
                end
            elseif nearExit then
                nearExit = false
                exitKeybind:disable(true)
                lib.hideTextUI()
            end

            Wait(0)
        end
    end
end)

---@param entity number
---@param point GarageSpawn
local function teleportTo(entity, point)
    SetEntityCoords(entity, point.x, point.y, point.z, false, false, false, false)
    SetEntityHeading(entity, point.heading)
end

---@param garage Garage
function M.enter(garage)
    local vehicle  = cache.vehicle
    local isDriver = vehicle and GetPedInVehicleSeat(vehicle, -1) == cache.ped
    local netId     = (vehicle and isDriver) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    local maxSeats  = netId and GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) or nil

    local entry = lib.callback.await('snowy_garages:enterIpl', false, garage.identifier, netId, maxSeats)
    if not entry then
        lib.notify({ title = locale('garage_enter_failed'), type = 'error' })
        return
    end

    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(0) end

    if netId then
        teleportTo(vehicle, entry.vehicle)
    else
        teleportTo(cache.ped, entry.onFoot)
    end

    Wait(200)
    DoScreenFadeIn(350)

    activeGarage = garage

    Spots.load(garage)
end

---@param garage Garage
function M.exit(garage)
    local vehicle  = cache.vehicle
    local netId    = vehicle and NetworkGetNetworkIdFromEntity(vehicle) or nil
    local maxSeats = vehicle and GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) or nil

    local destination = lib.callback.await('snowy_garages:exitIpl', false, garage.identifier, netId, maxSeats)
    if not destination then
        lib.notify({ title = locale('garage_exit_failed'), type = 'error' })
        return
    end

    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(0) end

    if vehicle then
        teleportTo(vehicle, destination)
    else
        teleportTo(cache.ped, destination)
    end

    Wait(200)
    DoScreenFadeIn(350)

    activeGarage = nil
    clearExitPrompt()

    Spots.unload(garage.identifier)
end

-- Passengers are teleported implicitly by staying seated in the vehicle (their bucket is
-- switched server-side to match), but they never call M.enter/M.exit themselves - without
-- this, only the driver ever gets the exit prompt/marker or sees the garage's parked spots.
RegisterNetEvent('snowy_garages:iplEnteredAsPassenger', function(garage)
    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(0) end

    Wait(200)
    DoScreenFadeIn(350)

    activeGarage = garage

    Spots.load(garage)
end)

RegisterNetEvent('snowy_garages:iplExitedAsPassenger', function(identifier)
    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(0) end

    Wait(200)
    DoScreenFadeIn(350)

    activeGarage = nil
    clearExitPrompt()

    Spots.unload(identifier)
end)

return M
