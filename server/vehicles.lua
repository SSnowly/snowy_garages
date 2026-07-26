local Config  = require "configs.shared.main"
local Bridge  = require "bridge._index"
local Garages = require "server.garages"
local Grants  = require "server.grants"
local Schema  = require "server.schema"

local identifierColumn = Bridge.identifierColumn

---@param source number
---@return boolean
local function isPlayerLoaded(source)
    return source > 0 and GetPlayerName(source) ~= nil
end

---@param plate string
---@return table?
local function getVehicleRow(plate)
    return MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
end

---@param garageIdentifier string
---@return table<number, boolean>
local function getOccupiedSpots(garageIdentifier)
    local rows = MySQL.query.await(
        ('SELECT `garageSpotID` FROM `%s` WHERE `garage` = ?'):format(Config.ownedVehiclesTable),
        { garageIdentifier }
    )
    local occupied = {}
    for _, row in ipairs(rows) do
        if row.garageSpotID then occupied[row.garageSpotID] = true end
    end
    return occupied
end

---@param row table
---@param identifier string
---@param job string?
---@param gang string?
---@return boolean
local function canAccessVehicle(row, identifier, job, gang)
    if row[identifierColumn] == identifier then return true end

    if row.company and job then
        local companyJob = row.company:match('^([^:]+)')
        if companyJob == job then return true end
    end

    if row.company and gang then
        local companyGang = row.company:match('^([^:]+)')
        if companyGang == gang then return true end
    end

    return false
end

---@param garage Garage
---@param job string?
---@param gang string?
---@return boolean
local function canAccessGarage(garage, job, gang)
    return not garage.company or garage.company == job or garage.company == gang
end

local parseVehicleRow = Schema.parseVehicleRow

---@param row table
---@return table
local function toDisplayEntry(row)
    local model, props = parseVehicleRow(row)
    return { plate = row.plate, model = model, props = props or {} }
end

lib.callback.register('snowy_garages:getGarageVehicles', function(source, garageIdentifier)
    if not isPlayerLoaded(source) then return {} end
    local garage = Garages.getByIdentifier(garageIdentifier)
    if not garage then return {} end

    local job  = Bridge.getPlayerJob(source)
    local gang = Bridge.getPlayerGang(source)
    local identifier = Bridge.getPlayerIdentifier(source)

    local rows = MySQL.query.await(
        ('SELECT ' .. Schema.vehicleDisplaySelect .. ' FROM `%s` WHERE `garage` = ? AND `impound_date` IS NULL AND `garageSpotID` IS NOT NULL'):format(identifierColumn, Config.ownedVehiclesTable),
        { garageIdentifier }
    )

    local vehicles = {}
    for _, row in ipairs(rows) do
        local entry = toDisplayEntry(row)
        entry.spotId    = row.garageSpotID
        entry.canAccess = identifier ~= nil and canAccessVehicle(row, identifier, job, gang)
        vehicles[#vehicles + 1] = entry
    end
    return vehicles
end)

lib.callback.register('snowy_garages:getGarageVehicle', function(source, garageIdentifier, spotId)
    if not isPlayerLoaded(source) then return false end
    local garage = Garages.getByIdentifier(garageIdentifier)
    if not garage then return false end

    local job  = Bridge.getPlayerJob(source)
    local gang = Bridge.getPlayerGang(source)
    local row = MySQL.single.await(
        ('SELECT ' .. Schema.vehicleSingleSelect .. ' FROM `%s` WHERE `garage` = ? AND `garageSpotID` = ? AND `impound_date` IS NULL'):format(identifierColumn, Config.ownedVehiclesTable),
        { garageIdentifier, spotId }
    )
    if not row then return false end

    local identifier = Bridge.getPlayerIdentifier(source)
    local entry      = toDisplayEntry(row)
    entry.canAccess  = identifier ~= nil and canAccessVehicle(row, identifier, job, gang)
    return entry
end)

lib.callback.register('snowy_garages:takeOutVehicle', function(source, garageIdentifier, spotId)
    if not isPlayerLoaded(source) then return false end
    local garage = Garages.getByIdentifier(garageIdentifier)
    if not garage then return false end

    local job  = Bridge.getPlayerJob(source)
    local gang = Bridge.getPlayerGang(source)
    if not canAccessGarage(garage, job, gang) then return false end

    local row = MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `garage` = ? AND `garageSpotID` = ?'):format(Config.ownedVehiclesTable),
        { garageIdentifier, spotId }
    )
    if not row then return false end
    if row.impound_date then return 'impounded' end

    local identifier = Bridge.getPlayerIdentifier(source)
    if not identifier then return false end
    if not canAccessVehicle(row, identifier, job, gang) then return 'no_access' end

    if garage.fee and garage.fee > 0 and garage.payStations and #garage.payStations > 0 and row.parking_date then
        local elapsed = os.time() - tonumber(row.parking_date)
        if elapsed > Config.parkingGracePeriod then return 'unpaid' end
    end

    local affected = MySQL.update.await(
        ('UPDATE `%s` SET `garage` = NULL, `garageSpotID` = NULL, `state` = 0 WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { row.plate }
    )
    if affected == 0 then return false end

    TriggerClientEvent('snowy_garages:spotVacated', -1, garageIdentifier, spotId)
    return true
end)

---@param ped number
---@return number?
local function getPlayerFromPed(ped)
    for _, playerId in ipairs(GetPlayers()) do
        if GetPlayerPed(playerId) == ped then
            return tonumber(playerId)
        end
    end
end

RegisterNetEvent('snowy_garages:requestEjectOccupants', function(netId, maxSeats)
    local source = source
    if not isPlayerLoaded(source) then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        debugPrint('[eject] vehicle not found for netId', netId)
        return
    end

    local driverPed = GetPedInVehicleSeat(vehicle, -1)
    local driver    = driverPed ~= 0 and getPlayerFromPed(driverPed) or nil
    if driver ~= source then
        debugPrint('[eject] driver check failed, driver =', driver, 'source =', source)
        return
    end

    for seat = -1, maxSeats - 2 do
        local ped    = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 then
            local target = getPlayerFromPed(ped)
            if target then
                debugPrint('[eject] telling', target, 'to leave seat', seat)
                TriggerClientEvent('snowy_garages:forceLeaveVehicle', target, netId)
            end
        end
    end
end)

---@param netId number
---@return number
local function awaitVehicleEntity(netId)
    local vehicle  = 0
    local attempts = 0
    repeat
        Wait(100)
        vehicle  = NetworkGetEntityFromNetworkId(netId)
        attempts = attempts + 1
    until (vehicle ~= 0 and DoesEntityExist(vehicle)) or attempts >= 50
    return vehicle
end

RegisterNetEvent('snowy_garages:vehicleSpawned', function(plate, netId, fuel)
    local source = source
    if not isPlayerLoaded(source) then return end

    local group   = Bridge.getPlayerGroup(source)
    local isAdmin = group ~= nil and Config.creatorGroups[group] == true
    if not isAdmin then
        local row = getVehicleRow(plate)
        if not row then return end
        local identifier = Bridge.getPlayerIdentifier(source)
        if not identifier then return end
        local job  = Bridge.getPlayerJob(source)
        local gang = Bridge.getPlayerGang(source)
        if not canAccessVehicle(row, identifier, job, gang) then return end
    end

    MySQL.update(
        ('UPDATE `%s` SET `netid` = ? WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { netId, plate }
    )

    CreateThread(function()
        local vehicle = awaitVehicleEntity(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then return end
        SetEntityOrphanMode(vehicle, 2)
        if NetworkGetEntityOwner(vehicle) ~= source then return end
        Bridge.giveVehicleKeys(source, vehicle)
        Entity(vehicle).state.fuel = type(fuel) == 'number' and fuel or 100.0
    end)
end)

RegisterNetEvent('snowy_garages:giveImpoundKeys', function(netId, fuel)
    local source = source
    if not isPlayerLoaded(source) then return end

    local group   = Bridge.getPlayerGroup(source)
    local isAdmin = group ~= nil and Config.creatorGroups[group] == true
    if not isAdmin and not Grants.consume(source) then return end

    CreateThread(function()
        local vehicle = awaitVehicleEntity(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then return end
        SetEntityOrphanMode(vehicle, 2)
        if NetworkGetEntityOwner(vehicle) ~= source then return end
        Bridge.giveVehicleKeys(source, vehicle)
        Entity(vehicle).state.fuel = type(fuel) == 'number' and fuel or 100.0
    end)
end)

lib.callback.register('snowy_garages:storeVehicle', function(source, garageIdentifier, spotId, plate, netId, mods, vehicleType, modelHash, modelName)
    if not isPlayerLoaded(source) then return false end
    local garage = Garages.getByIdentifier(garageIdentifier)
    if not garage then return false end
    if garage.vehicleType and garage.vehicleType ~= vehicleType then return 'wrong_vehicle_type' end

    local spot = garage.spawns[spotId]
    if not spot then return false end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if NetworkGetEntityOwner(vehicle) ~= source then return false end
    if GetVehicleNumberPlateText(vehicle):match('^%s*(.-)%s*$') ~= plate:match('^%s*(.-)%s*$') then return false end

    local vehicleCoords = GetEntityCoords(vehicle)
    if #(vector3(spot.x, spot.y, spot.z) - vehicleCoords) > 5.0 then return false end

    local row = getVehicleRow(plate)
    if not row or row.garage ~= nil then return false end

    local identifier = Bridge.getPlayerIdentifier(source)
    if not identifier then return false end

    local job  = Bridge.getPlayerJob(source)
    local gang = Bridge.getPlayerGang(source)
    if not canAccessGarage(garage, job, gang) then return false end
    if not canAccessVehicle(row, identifier, job, gang) then return false end

    local occupied = getOccupiedSpots(garageIdentifier)
    if occupied[spotId] then return false end

    local resolvedModel, _ = parseVehicleRow(row)
    mods.model = type(modelHash) == 'number' and modelHash or resolvedModel
    mods.plate = plate

    local storeQuery, storeParams
    if Schema.isEsx then
        -- ESX: vehicle column carries the full props JSON; no separate hash/mods/position.
        storeQuery  = ('UPDATE `%s` SET `garage` = ?, `garageSpotID` = ?, `vehicle` = ?, `netid` = NULL, `parking_date` = ?, `state` = 1 WHERE `plate` = ?'):format(Config.ownedVehiclesTable)
        storeParams = { garageIdentifier, spotId, json.encode(mods), os.time(), plate }
    else
        local vehicleColumn = (type(modelName) == 'string' and modelName ~= '') and modelName or row.vehicle
        storeQuery  = ('UPDATE `%s` SET `garage` = ?, `garageSpotID` = ?, `vehicle` = ?, `hash` = ?, `mods` = ?, `netid` = NULL, `position` = NULL, `parking_date` = ?, `state` = 1 WHERE `plate` = ?'):format(Config.ownedVehiclesTable)
        storeParams = { garageIdentifier, spotId, vehicleColumn, type(modelHash) == 'number' and modelHash or nil, json.encode(mods), os.time(), plate }
    end
    local affected = MySQL.update.await(storeQuery, storeParams)
    if affected == 0 then return false end

    if Config.saveLogs then
        debugPrint(('[store] %s → garage=%s spot=%d plate=%s'):format(identifier, garageIdentifier, spotId, plate))
    end

    TriggerClientEvent('snowy_garages:spotOccupied', -1, garageIdentifier, spotId)
    TriggerClientEvent('snowy_garages:spotDisplaySpawn', -1, garageIdentifier, spotId)
    return true
end)
