local Config      = require "configs.shared.main"
local Vehicle     = require "client.vehicle"
local Bridge      = require "bridge._index"
local VehicleType = require "client.vehicle_type"

---@type table<string, Garage>
local activeGarages = {}

---@type table<string, table<number, { entity: number, plate: string }>>
local displays = {}

---@type { garageIdentifier: string, spotId: number }?
local nearestSpot = nil

---@type number?
local processingVehicle = nil

local storeKeybind = lib.addKeybind({
    name        = 'snowy_garages_store',
    description = locale('garage_store'),
    defaultKey  = 'E',
    onPressed   = function()
        if not nearestSpot then return end
        Vehicle.storeVehicle(nearestSpot.garageIdentifier, nearestSpot.spotId)
    end,
})
storeKeybind:disable(true)

---@param garageIdentifier string
---@param spotId number
local function removeDisplay(garageIdentifier, spotId)
    local garageDisplays = displays[garageIdentifier]
    local display = garageDisplays and garageDisplays[spotId]
    if not display then return end

    garageDisplays[spotId] = nil

    if not display.entity then return end
    -- the take-out broadcast reaches the taking player's own client too; never delete
    -- the vehicle they're currently sitting in, or one they're still entering, just
    -- because the server confirmed the same take-out they triggered.
    if display.entity == cache.vehicle then return end
    if display.entity == processingVehicle then return end
    DeleteEntity(display.entity)
end

---@param garageIdentifier string
---@param spotId number
---@param entry { plate: string, model: number, props: table, canAccess: boolean }
local function spawnDisplay(garageIdentifier, spotId, entry)
    local garage = activeGarages[garageIdentifier]
    local spawn = garage and garage.spawns[spotId]
    if not spawn then return end

    lib.requestModel(entry.model)
    local vehicle = CreateVehicle(entry.model, spawn.x, spawn.y, spawn.z, spawn.heading, false, false)
    local spawnTimeout = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < spawnTimeout do Wait(0) end
    if not DoesEntityExist(vehicle) then return end
    SetEntityAsMissionEntity(vehicle, true, true)
    Bridge.setVehicleProperties(vehicle, entry.props)
    SetVehicleNumberPlateText(vehicle, entry.plate)
    local lockState = entry.canAccess and 1 or 2
    SetVehicleDoorsLocked(vehicle, lockState)
    Entity(vehicle).state:set('doorslockstate', lockState, false)
    SetVehicleEngineOn(vehicle, false, true, true)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, false)
    SetEntityProofs(vehicle, true, true, true, true, true, true, true, true, true)
    Bridge.setVehicleDeformation(vehicle, entry.props.deformation)

    displays[garageIdentifier] = displays[garageIdentifier] or {}
    displays[garageIdentifier][spotId] = { entity = vehicle, plate = entry.plate, fuel = entry.props and entry.props.fuelLevel or 100.0 }
end

---@param vehicle number
---@return string?, number?
local function findDisplayEntity(vehicle)
    for garageIdentifier, garageDisplays in pairs(displays) do
        for spotId, display in pairs(garageDisplays) do
            if display.entity == vehicle then
                return garageIdentifier, spotId
            end
        end
    end
end

---@param garageIdentifier string
local function clearNearestSpotIfStale(garageIdentifier)
    if nearestSpot and nearestSpot.garageIdentifier == garageIdentifier then
        nearestSpot = nil
        storeKeybind:disable(true)
        lib.hideTextUI()
    end
end

---@param garage Garage
local function loadGarageVehicles(garage)
    activeGarages[garage.identifier] = garage
    displays[garage.identifier] = displays[garage.identifier] or {}

    for _, entry in ipairs(lib.callback.await('snowy_garages:getGarageVehicles', false, garage.identifier)) do
        spawnDisplay(garage.identifier, entry.spotId, entry)
    end
end

---@param identifier string
local function unloadGarageVehicles(identifier)
    for spotId in pairs(displays[identifier] or {}) do
        removeDisplay(identifier, spotId)
    end
    displays[identifier] = nil
    activeGarages[identifier] = nil

    clearNearestSpotIfStale(identifier)
end

RegisterNetEvent('snowy_garages:spotOccupied', function(garageIdentifier, spotId)
    if not activeGarages[garageIdentifier] then return end

    displays[garageIdentifier] = displays[garageIdentifier] or {}
    if not displays[garageIdentifier][spotId] then
        displays[garageIdentifier][spotId] = { entity = false, plate = '' }
    end

    if nearestSpot and nearestSpot.garageIdentifier == garageIdentifier and nearestSpot.spotId == spotId then
        nearestSpot = nil
        storeKeybind:disable(true)
        lib.hideTextUI()
    end
end)

RegisterNetEvent('snowy_garages:spotDisplaySpawn', function(garageIdentifier, spotId)
    if not activeGarages[garageIdentifier] then return end

    local entry = lib.callback.await('snowy_garages:getGarageVehicle', false, garageIdentifier, spotId)
    if not entry then return end

    spawnDisplay(garageIdentifier, spotId, entry)
end)

RegisterNetEvent('snowy_garages:spotVacated', function(garageIdentifier, spotId)
    removeDisplay(garageIdentifier, spotId)
end)

-- Immediately disable the store keybind when the player leaves any vehicle,
-- without waiting for the next proximity poll cycle.
lib.onCache('vehicle', function(vehicle)
    if vehicle then return end
    nearestSpot = nil
    storeKeybind:disable(true)
    lib.hideTextUI()
end)

---@type number?
local lastVehicle = nil

CreateThread(function()
    while true do
        Wait(250)

        local vehicle = cache.vehicle

        -- Catch the player trying to enter a display vehicle (door-handle state) rather
        -- than waiting until they're fully seated - this lets the server callback fire
        -- earlier so the vehicle is ready to drive the moment the ped sits down.
        local target = GetVehiclePedIsTryingToEnter(cache.ped)
        if target and target ~= 0 and target ~= processingVehicle then
            local garageIdentifier, spotId = findDisplayEntity(target)
            if garageIdentifier then
                processingVehicle = target
                local result = lib.callback.await('snowy_garages:takeOutVehicle', false, garageIdentifier, spotId)
                if result == 'unpaid' then
                    lib.notify({ title = locale('vehicle_unpaid'), type = 'error' })
                    ClearPedTasks(cache.ped)
                elseif result == 'impounded' then
                    lib.notify({ title = locale('vehicle_impounded'), type = 'error' })
                    ClearPedTasks(cache.ped)
                elseif result == 'no_access' or not result then
                    lib.notify({ title = locale('vehicle_no_access'), type = 'error' })
                    ClearPedTasks(cache.ped)
                else
                    local display = displays[garageIdentifier][spotId]
                    displays[garageIdentifier][spotId] = nil
                    SetVehicleDoorsLocked(target, 1)
                    FreezeEntityPosition(target, false)
                    SetEntityInvincible(target, false)
                    SetVehicleCanBeVisiblyDamaged(target, true)
                    SetEntityProofs(target, false, false, false, false, false, false, false, false, false)

                    NetworkRegisterEntityAsNetworked(target)
                    local timeout = GetGameTimer() + 1000
                    while not NetworkGetEntityIsNetworked(target) and GetGameTimer() < timeout do Wait(0) end

                    local netId = NetworkGetNetworkIdFromEntity(target)
                    SetNetworkIdCanMigrate(netId, true)
                    SetEntityAsMissionEntity(target, true, true)

                    local plate = GetVehicleNumberPlateText(target)
                    TriggerServerEvent('snowy_garages:vehicleSpawned', plate, netId, display and display.fuel or 100.0)
                end
                processingVehicle = nil
            end
        end

        lastVehicle = vehicle
    end
end)

CreateThread(function()
    while true do
        local drewAny = false
        local playerCoords = GetEntityCoords(cache.ped)
        local canInteract = cache.vehicle ~= nil and GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped
        -- Spots are only ever worth showing while driving a vehicle whose type actually fits
        -- the garage - a pedestrian preview (or a mismatched vehicle) has nothing to store here.
        local vehicleType = canInteract and VehicleType.classify(GetEntityModel(cache.vehicle)) or nil

        local closestGarage, closestSpot, closestDist = nil, nil, Config.spotInteractDistance

        if vehicleType then
            for garageIdentifier, garage in pairs(activeGarages) do
                if not garage.vehicleType or garage.vehicleType == vehicleType then
                    local occupied = displays[garageIdentifier] or {}
                    for spotId, spot in pairs(garage.spawns) do
                        if not occupied[spotId] then
                            local coords = vector3(spot.x, spot.y, spot.z)
                            local dist = #(playerCoords - coords)

                            if dist < 30.0 then
                                local m = Config.markers.freeSpot
                                DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, m.r, m.g, m.b, m.a, false, false, 2, false, nil, nil, false)
                                drewAny = true
                            end

                            if dist < closestDist then
                                closestGarage, closestSpot, closestDist = garageIdentifier, spotId, dist
                            end
                        end
                    end
                end
            end
        end

        if closestGarage then
            if not nearestSpot then
                storeKeybind:disable(false)
                lib.showTextUI(locale('garage_store'), { position = 'right-center', icon = 'square-parking' })
            end
            nearestSpot = { garageIdentifier = closestGarage, spotId = closestSpot }
        elseif nearestSpot then
            nearestSpot = nil
            storeKeybind:disable(true)
            lib.hideTextUI()
        end

        Wait(drewAny and 0 or 500)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= cache.resource then return end
    for identifier in pairs(activeGarages) do
        unloadGarageVehicles(identifier)
    end
end)

return {
    load   = loadGarageVehicles,
    unload = unloadGarageVehicles,
}
