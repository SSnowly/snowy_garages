local Config     = require "configs.shared.main"
local GaragesApi = require "client.garages_api"
local Ipl        = require "client.ipl"
local Spots      = require "client.spots"

---@type table<string, Garage>
local garages = {}

---@type table<string, Garage>
local activeIplGarages = {}

---@type Garage?
local nearestIplGarage = nil

---@type table<string, table>
local activePoints = {}

---@type table<string, table>
local activeZones = {}

---@type table<string, number>
local blips = {}

local enterKeybind = lib.addKeybind({
    name        = 'snowy_garages_enter_ipl',
    description = locale('garage_enter_ipl'),
    defaultKey  = 'E',
    onPressed   = function()
        if not nearestIplGarage then return end
        Ipl.enter(nearestIplGarage)
    end,
})
enterKeybind:disable(true)

---@param garage Garage
local function createBlip(garage)
    if not garage.showBlip then return end

    local blip = AddBlipForCoord(garage.coords.x, garage.coords.y, garage.coords.z)
    SetBlipSprite(blip, 357)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(locale('garage_blip_label'))
    EndTextCommandSetBlipName(blip)
    blips[garage.identifier] = blip
end

---@param garage Garage
local function enterGarage(garage)
    if garage.type == 'ipl' then
        activeIplGarages[garage.identifier] = garage
    else
        Spots.load(garage)
    end
end

---@param garage Garage
local function exitGarage(garage)
    if activeIplGarages[garage.identifier] then
        activeIplGarages[garage.identifier] = nil

        if nearestIplGarage and nearestIplGarage.identifier == garage.identifier then
            nearestIplGarage = nil
            enterKeybind:disable(true)
            lib.hideTextUI()
        end
    else
        Spots.unload(garage.identifier)
    end
end

---@param garage Garage
local function registerGarage(garage)
    garages[garage.identifier] = garage
    createBlip(garage)

    if garage.zone then
        -- Zoned garages spawn their vehicle displays only once the player actually crosses
        -- into the polygon, not just when they're within the old loose loadDistance radius.
        local points = {}
        for i, point in ipairs(garage.zone.points) do
            points[i] = vector3(point.x, point.y, point.z)
        end

        activeZones[garage.identifier] = lib.zones.poly({
            points    = points,
            thickness = garage.zone.thickness,
            debug     = Config.debug,
            onEnter   = function() enterGarage(garage) end,
            onExit    = function() exitGarage(garage) end,
        })
    else
        -- Legacy garage (created/migrated before the zone feature) - keeps working exactly
        -- as before until an admin edits it and places a zone.
        activePoints[garage.identifier] = lib.points.new({
            coords   = garage.coords,
            distance = Config.loadDistance,
            onEnter  = function() enterGarage(garage) end,
            onExit   = function() exitGarage(garage) end,
        })
    end
end

---@param identifier string
local function unregisterGarage(identifier)
    exitGarage({ identifier = identifier })

    local zone = activeZones[identifier]
    if zone then
        zone:remove()
        activeZones[identifier] = nil
    end

    local point = activePoints[identifier]
    if point then
        point:remove()
        activePoints[identifier] = nil
    end

    local blip = blips[identifier]
    if blip then
        RemoveBlip(blip)
        blips[identifier] = nil
    end

    garages[identifier] = nil
end

CreateThread(function()
    while true do
        local drewAny = false
        local playerCoords = GetEntityCoords(cache.ped)
        local closestGarage, closestDist = nil, Config.iplInteractDistance

        for _, garage in pairs(activeIplGarages) do
            local coords = garage.coords
            local dist = #(playerCoords - coords)

            if dist < 30.0 then
                local m = Config.markers.iplEntrance
                DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, m.r, m.g, m.b, m.a, false, false, 2, false, nil, nil, false)
                drewAny = true
            end

            if dist < closestDist then
                closestGarage, closestDist = garage, dist
            end
        end

        if closestGarage then
            if not nearestIplGarage then
                enterKeybind:disable(false)
                lib.showTextUI(locale('garage_enter_ipl'), { position = 'right-center', icon = 'warehouse' })
            end
            nearestIplGarage = closestGarage
        elseif nearestIplGarage then
            nearestIplGarage = nil
            enterKeybind:disable(true)
            lib.hideTextUI()
        end

        Wait(drewAny and 0 or 500)
    end
end)

---@param garage Garage
local function tryRegisterGarage(garage)
    -- A single malformed garage (e.g. bad migrated zone data) throwing here would otherwise
    -- kill this whole loop/thread and silently skip every garage after it in iteration order.
    local ok, err = pcall(registerGarage, garage)
    if not ok then
        debugPrint(('snowy_garages: failed to register garage "%s": %s'):format(garage.identifier, err))
    end
end

CreateThread(function()
    Wait(1000)
    for _, garage in ipairs(GaragesApi.getGarages()) do
        tryRegisterGarage(garage)
    end
end)

RegisterNetEvent('snowy_garages:garageCreated', function(garage)
    tryRegisterGarage(garage)
end)

RegisterNetEvent('snowy_garages:garageDeleted', function(identifier)
    unregisterGarage(identifier)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= cache.resource then return end
    for _, point in pairs(activePoints) do point:remove() end
    for _, zone in pairs(activeZones) do zone:remove() end
end)
