local Config     = require "configs.shared.main"
local GaragesApi = require "client.garages_api"

---@type table<string, table>
local activePoints = {}

---@type table<string, number[]>
local activeProps = {}

---@param garageIdentifier string
local function openPayStation(garageIdentifier)
    local input = lib.inputDialog(locale('pay_station_dialog_title'), {
        { type = 'input', label = locale('pay_station_plate'), required = true },
        {
            type = 'select', label = locale('pay_station_account'), required = true,
            options = {
                { value = 'cash', label = locale('pay_station_cash') },
                { value = 'bank', label = locale('pay_station_bank') },
            },
        },
    })
    if not input then return end

    -- Plate formatting/spacing doesn't matter here - the server normalizes it before matching.
    local result = lib.callback.await('snowy_garages:payParkingBill', false, garageIdentifier, input[1], input[2])
    if result == 'nothing_owed' then
        lib.notify({ title = locale('pay_station_nothing_owed'), type = 'info' })
        return
    elseif not result then
        lib.notify({ title = locale('pay_station_failed'), type = 'error' })
        return
    end

    lib.notify({ title = locale('pay_station_paid'):format(result), type = 'success' })
end

---@param garageIdentifier string
---@param station GarageSpawn
local function spawnProp(garageIdentifier, station)
    lib.requestModel(Config.payStationModel)
    local prop = CreateObject(Config.payStationModel, station.x, station.y, station.z, false, false, false)
    SetEntityHeading(prop, station.heading or 0.0)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)

    exports.ox_target:addLocalEntity(prop, {
        {
            name     = 'snowy_garages:payStation',
            icon     = 'fas fa-money-bill',
            label    = locale('pay_station_interact'),
            onSelect = function() openPayStation(garageIdentifier) end,
        },
    })

    activeProps[garageIdentifier][#activeProps[garageIdentifier] + 1] = prop
end

---@param garage Garage
local function registerPayStations(garage)
    if not garage.payStations or not next(garage.payStations) then return end

    activePoints[garage.identifier] = lib.points.new({
        coords   = garage.coords,
        distance = Config.loadDistance,
        onEnter  = function()
            activeProps[garage.identifier] = {}
            for _, station in pairs(garage.payStations) do
                spawnProp(garage.identifier, station)
            end
        end,
        onExit = function()
            for _, prop in ipairs(activeProps[garage.identifier] or {}) do
                DeleteEntity(prop)
            end
            activeProps[garage.identifier] = nil
        end,
    })
end

---@param identifier string
local function unregisterPayStations(identifier)
    local point = activePoints[identifier]
    if point then
        point:remove()
        activePoints[identifier] = nil
    end

    for _, prop in ipairs(activeProps[identifier] or {}) do
        DeleteEntity(prop)
    end
    activeProps[identifier] = nil
end

CreateThread(function()
    Wait(1000)
    for _, garage in ipairs(GaragesApi.getGarages()) do
        registerPayStations(garage)
    end
end)

RegisterNetEvent('snowy_garages:garageCreated', function(garage)
    registerPayStations(garage)
end)

RegisterNetEvent('snowy_garages:garageDeleted', function(identifier)
    unregisterPayStations(identifier)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= cache.resource then return end
    for _, point in pairs(activePoints) do point:remove() end
    for _, props in pairs(activeProps) do
        for _, prop in ipairs(props) do DeleteEntity(prop) end
    end
end)
