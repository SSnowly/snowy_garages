local Config  = require "configs.shared.main"
local Bridge  = require "bridge._index"
local Plates  = require "server.plates"
local Garages = require "server.garages"
local Grants  = require "server.grants"
local Schema  = require "server.schema"

local parseVehicleRow = Schema.parseVehicleRow

---@param source number
---@return boolean
local function isPlayerLoaded(source)
    return source > 0 and GetPlayerName(source) ~= nil
end

---@param job string?
---@return boolean
local function isImpoundJob(job)
    if not job then return false end
    for _, allowed in ipairs(Config.impoundJobs) do
        if allowed == job then return true end
    end
    return false
end

---@param seconds number
---@return string
local function formatLockDuration(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.ceil((seconds % 3600) / 60)
    if h > 0 and m > 0 then
        return locale('impound_time_format_hm'):format(h, m)
    elseif h > 0 then
        return locale('impound_time_format_h'):format(h)
    else
        return locale('impound_time_format_m'):format(math.max(1, m))
    end
end

---@param plate string
---@return table?
local function getVehicleRow(plate)
    return MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
end

---@param vehicle number
---@param maxSeats number
---@return boolean
local function isVehicleEmpty(vehicle, maxSeats)
    for seat = -1, maxSeats - 2 do
        if GetPedInVehicleSeat(vehicle, seat) ~= 0 then return false end
    end
    return true
end

---Seat count natives are unreliable server-side; check a fixed wide range instead.
---GetPedInVehicleSeat returns 0 for seats a vehicle does not have.
---@param vehicle number
---@return boolean
local function isVehicleOccupiedByAnyone(vehicle)
    for seat = -1, 16 do
        if GetPedInVehicleSeat(vehicle, seat) ~= 0 then return true end
    end
    return false
end

---@param plate string
---@return string
local function normalizePlate(plate)
    return plate:match('^%s*(.-)%s*$')
end

---The DB netid can go stale; scan live vehicles by plate as the authoritative check.
---@param plate string
---@return number? vehicle
local function findVehicleByPlate(plate)
    local normalized = normalizePlate(plate)
    for _, vehicle in ipairs(GetAllVehicles()) do
        if normalizePlate(GetVehicleNumberPlateText(vehicle)) == normalized then
            return vehicle
        end
    end
    return nil
end

---@param plate string
local function deleteVehicleByPlate(plate)
    local vehicle = findVehicleByPlate(plate)
    if not vehicle then return end
    TriggerClientEvent('snowy_garages:forceDeleteVehicle', -1, NetworkGetNetworkIdFromEntity(vehicle))
end

---@param row table
---@return boolean
local function isVehicleGone(row)
    if row.garage then return false end
    return findVehicleByPlate(row.plate) == nil
end

---@param source number
---@return boolean
local function hasAdminPermission(source)
    local group = Bridge.getPlayerGroup(source)
    return group ~= nil and Config.creatorGroups[group] == true
end

---@param row table
---@param job string?
---@param gang string?
---@return boolean
local function isCompanyMatch(row, job, gang)
    if not row.company then return false end
    local company = row.company:match('^([^:]+)')
    return (job ~= nil and company == job) or (gang ~= nil and company == gang)
end

lib.callback.register('snowy_garages:impoundVehicle', function(source, netId, plate, maxSeats, fine, lockMins, reason)
    if not isPlayerLoaded(source) then return false end
    if not isImpoundJob(Bridge.getPlayerJob(source)) then return false end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if GetVehicleNumberPlateText(vehicle):match('^%s*(.-)%s*$') ~= plate:match('^%s*(.-)%s*$') then return false end
    if not isVehicleEmpty(vehicle, maxSeats) then return 'occupied' end

    local row = getVehicleRow(plate)
    if not row or row.impound_date then return false end

    local sanitizedFine   = type(fine)    == 'number' and math.max(0, math.floor(fine))            or nil
    local sanitizedReason = type(reason)  == 'string' and reason:sub(1, 128)                        or nil
    local impoundUntil    = type(lockMins) == 'number' and lockMins > 0
                            and os.time() + math.floor(lockMins) * 60 or nil

    local affected = MySQL.update.await(
        ('UPDATE `%s` SET `garage` = NULL, `garageSpotID` = NULL, `netid` = NULL%s, `impound_date` = ?, `impound_fine` = ?, `impound_until` = ?, `impound_reason` = ?, `state` = 2 WHERE `plate` = ?'):format(Config.ownedVehiclesTable, Schema.positionNull),
        { os.time(), sanitizedFine, impoundUntil, sanitizedReason, plate }
    )
    if affected == 0 then return false end

    if row.garage and row.garageSpotID then
        TriggerClientEvent('snowy_garages:spotVacated', -1, row.garage, row.garageSpotID)
    end

    return true
end)

lib.callback.register('snowy_garages:impoundParkedVehicle', function(source, plate, fine, lockMins, reason)
    if not isPlayerLoaded(source) then return false end
    if not isImpoundJob(Bridge.getPlayerJob(source)) then return false end

    plate = type(plate) == 'string' and normalizePlate(plate:upper()) or nil
    if not plate or plate == '' then return false end

    local row = getVehicleRow(plate)
    if not row or row.impound_date then return false end
    if not row.garage then return false end

    local sanitizedFine   = type(fine)     == 'number' and math.max(0, math.floor(fine))           or nil
    local sanitizedReason = type(reason)   == 'string' and reason:sub(1, 128)                       or nil
    local impoundUntil    = type(lockMins) == 'number' and lockMins > 0
                            and os.time() + math.floor(lockMins) * 60 or nil

    local affected = MySQL.update.await(
        ('UPDATE `%s` SET `garage` = NULL, `garageSpotID` = NULL, `netid` = NULL%s, `impound_date` = ?, `impound_fine` = ?, `impound_until` = ?, `impound_reason` = ?, `state` = 2 WHERE `plate` = ?'):format(Config.ownedVehiclesTable, Schema.positionNull),
        { os.time(), sanitizedFine, impoundUntil, sanitizedReason, plate }
    )
    if affected == 0 then return false end

    TriggerClientEvent('snowy_garages:spotVacated', -1, row.garage, row.garageSpotID)
    return true
end)

lib.callback.register('snowy_garages:getImpoundedVehicles', function(source)
    if not isPlayerLoaded(source) then return {} end
    local identifier = Bridge.getPlayerIdentifier(source)
    if not identifier then return {} end
    local job  = Bridge.getPlayerJob(source)
    local gang = Bridge.getPlayerGang(source)

    local identifierColumn = Bridge.identifierColumn
    local rows = MySQL.query.await(
        ('SELECT ' .. Schema.impoundListSelect .. ' FROM `%s` WHERE (`%s` = ? OR `company` IS NOT NULL) AND (`impound_date` IS NOT NULL OR `garage` IS NULL)'):format(identifierColumn, Config.ownedVehiclesTable, identifierColumn),
        { identifier }
    )

    local now = os.time()
    local vehicles = {}
    for _, row in ipairs(rows) do
        local isOwner   = row[identifierColumn] == identifier
        local isCompany = not isOwner and isCompanyMatch(row, job, gang)
        if isOwner or isCompany then
            local impounded = row.impound_date ~= nil
            if impounded or isVehicleGone(row) then
                local model, _ = parseVehicleRow(row)

                local fine        = row.impound_fine ~= nil and tonumber(row.impound_fine) or Config.impoundFee
                local lockedUntil = row.impound_until and tonumber(row.impound_until) or nil
                local isLocked    = lockedUntil ~= nil and lockedUntil > now

                vehicles[#vehicles + 1] = {
                    plate     = row.plate,
                    model     = model,
                    impounded = impounded,
                    isCompany = isCompany,
                    locked    = isLocked,
                    lockLabel = isLocked and locale('impound_locked_until'):format(formatLockDuration(lockedUntil - now)) or nil,
                    reason    = row.impound_reason,
                    feeLabel  = locale('impound_amount'):format(fine),
                    fine      = fine,
                }
            end
        end
    end
    return vehicles
end)

lib.callback.register('snowy_garages:getImpoundedVehiclePreview', function(source, plate)
    if not isPlayerLoaded(source) then return false end
    local identifier = Bridge.getPlayerIdentifier(source)
    if not identifier then return false end
    local job  = Bridge.getPlayerJob(source)
    local gang = Bridge.getPlayerGang(source)

    local row = getVehicleRow(plate)
    if not row then return false end
    if row[Bridge.identifierColumn] ~= identifier and not isCompanyMatch(row, job, gang) then return false end

    local _, props = parseVehicleRow(row)
    return props
end)

lib.callback.register('snowy_garages:releaseImpoundedVehicle', function(source, plate, accountType)
    if not isPlayerLoaded(source) then return false end
    if accountType ~= 'cash' and accountType ~= 'bank' then return false end

    local identifier = Bridge.getPlayerIdentifier(source)
    if not identifier then return false end
    local job  = Bridge.getPlayerJob(source)
    local gang = Bridge.getPlayerGang(source)

    local row = getVehicleRow(plate)
    if not row then return false end
    if row[Bridge.identifierColumn] ~= identifier and not isCompanyMatch(row, job, gang) then return false end
    if not row.impound_date and not isVehicleGone(row) then return false end

    local lockedUntil = row.impound_until and tonumber(row.impound_until) or nil
    if lockedUntil and lockedUntil > os.time() then return 'locked' end

    local fine = row.impound_fine ~= nil and tonumber(row.impound_fine) or Config.impoundFee
    if fine > 0 and not Bridge.removeMoney(source, accountType, fine) then return false end

    MySQL.update.await(
        ('UPDATE `%s` SET `impound_date` = NULL, `impound_fine` = NULL, `impound_until` = NULL, `impound_reason` = NULL, `garage` = NULL, `garageSpotID` = NULL, `netid` = NULL%s, `state` = 0 WHERE `plate` = ?'):format(Config.ownedVehiclesTable, Schema.positionNull),
        { plate }
    )

    deleteVehicleByPlate(plate)

    Grants.set(source)
    local _, props = parseVehicleRow(row)
    return props
end)

lib.addCommand('impoundall', { help = locale('impound_cmd_help_all') }, function(source)
    if not isPlayerLoaded(source) then return end
    if not hasAdminPermission(source) then return end

    local rows = MySQL.query.await(
        ('SELECT `plate` FROM `%s` WHERE `garage` IS NULL AND `impound_date` IS NULL'):format(Config.ownedVehiclesTable)
    )

    local count = 0
    for _, row in ipairs(rows) do
        local vehicle = findVehicleByPlate(row.plate)
        if not vehicle or not isVehicleOccupiedByAnyone(vehicle) then
            MySQL.update.await(
                ('UPDATE `%s` SET `garage` = NULL, `garageSpotID` = NULL, `netid` = NULL%s, `impound_date` = ?, `state` = 2 WHERE `plate` = ?'):format(Config.ownedVehiclesTable, Schema.positionNull),
                { os.time(), row.plate }
            )
            if vehicle then TriggerClientEvent('snowy_garages:forceDeleteVehicle', -1, NetworkGetNetworkIdFromEntity(vehicle)) end
            count = count + 1
        end
    end

    TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_all_result'):format(count), type = 'inform' })
end)

lib.addCommand('impound', { help = locale('impound_cmd_help') }, function(source)
    if not isPlayerLoaded(source) then return end
    if not isImpoundJob(Bridge.getPlayerJob(source)) then return end
    TriggerClientEvent('snowy_garages:startImpound', source)
end)

lib.addCommand('admincar', {
    help       = locale('admincar_cmd_help'),
    restricted = 'group.admin',
}, function(source)
    if not isPlayerLoaded(source) then return end
    TriggerClientEvent('snowy_garages:requestAdminCar', source)
end)

lib.addCommand('setjobvehicle', {
    help       = locale('setjobvehicle_cmd_help'),
    restricted = 'group.admin',
    params     = {
        { name = 'job', type = 'string', help = 'Job name' },
    },
}, function(source, args)
    if not isPlayerLoaded(source) then return end
    TriggerClientEvent('snowy_garages:requestSetJobVehicle', source, args.job)
end)

---@param plate  string
---@param garage string?
---@param spotId number?
local function clearVehicleStorage(plate, garage, spotId)
    MySQL.update.await(
        ('UPDATE `%s` SET `garage` = NULL, `garageSpotID` = NULL, `impound_date` = NULL, `state` = 0 WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    if garage and spotId then
        TriggerClientEvent('snowy_garages:spotVacated', -1, garage, spotId)
    end
end

lib.addCommand('dupevehicle', {
    help       = locale('dupevehicle_cmd_help'),
    restricted = 'group.admin',
    params     = {
        { name = 'plate',   type = 'string',  help = 'Plate of the vehicle to duplicate' },
        { name = 'garage',  type = 'string',  help = 'Garage identifier to store the duplicate in (optional)', optional = true },
        { name = 'spot',    type = 'number',  help = 'Parking spot number (optional, defaults to next free)', optional = true },
    },
}, function(source, args)
    if not isPlayerLoaded(source) then return end

    local plate = args.plate:upper():gsub('%s', '')
    local row   = MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    if not row then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_plate'):format(plate), type = 'error' })
        return
    end

    local model, props = parseVehicleRow(row)
    if not model then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_model'), type = 'error' })
        return
    end

    local newPlate = Plates.generateUniquePlate()
    -- ESX stores props in vehicle column; QBCore uses mods column.
    local mods = Schema.isEsx and row.vehicle or row.mods
    if mods then
        local modsData = json.decode(mods)
        if modsData then
            modsData.plate = newPlate
            mods = json.encode(modsData)
        end
    end

    local identifierColumn = Bridge.identifierColumn

    if args.garage then
        local garage = Garages.getByIdentifier(args.garage)
        if not garage then
            TriggerClientEvent('ox_lib:notify', source, { title = ('Unknown garage: %s'):format(args.garage), type = 'error' })
            return
        end

        local spotId = args.spot
        if spotId then
            if not garage.spawns[spotId] then
                TriggerClientEvent('ox_lib:notify', source, { title = ('Spot %d does not exist in garage %s'):format(spotId, args.garage), type = 'error' })
                return
            end
            local occupant = MySQL.single.await(
                ('SELECT `plate` FROM `%s` WHERE `garage` = ? AND `garageSpotID` = ?'):format(Config.ownedVehiclesTable),
                { args.garage, spotId }
            )
            if occupant then
                TriggerClientEvent('ox_lib:notify', source, { title = ('Spot %d in %s is already occupied by %s'):format(spotId, args.garage, occupant.plate), type = 'error' })
                return
            end
        else
            local occupiedRows = MySQL.query.await(
                ('SELECT `garageSpotID` FROM `%s` WHERE `garage` = ?'):format(Config.ownedVehiclesTable),
                { args.garage }
            )
            local occupied = {}
            for _, r in ipairs(occupiedRows) do
                if r.garageSpotID then occupied[r.garageSpotID] = true end
            end
            for id in pairs(garage.spawns) do
                if not occupied[id] then
                    spotId = id
                    break
                end
            end
            if not spotId then
                TriggerClientEvent('ox_lib:notify', source, { title = ('Garage %s has no free spots'):format(args.garage), type = 'error' })
                return
            end
        end

        if Schema.isEsx then
            MySQL.insert.await(
                ('INSERT INTO `%s` (`plate`, `%s`, `vehicle`, `company`, `garage`, `garageSpotID`, `state`) VALUES (?, ?, ?, ?, ?, ?, 1)'):format(Config.ownedVehiclesTable, identifierColumn),
                { newPlate, row[identifierColumn], mods, row.company, args.garage, spotId }
            )
        else
            MySQL.insert.await(
                ('INSERT INTO `%s` (`plate`, `%s`, `vehicle`, `hash`, `mods`, `company`, `garage`, `garageSpotID`, `state`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)'):format(Config.ownedVehiclesTable, identifierColumn),
                { newPlate, row[identifierColumn], row.vehicle, row.hash, mods, row.company, args.garage, spotId }
            )
        end

        TriggerClientEvent('snowy_garages:spotOccupied', -1, args.garage, spotId)
        TriggerClientEvent('snowy_garages:spotDisplaySpawn', -1, args.garage, spotId)
        TriggerClientEvent('ox_lib:notify', source, { title = ('Duplicated %s → %s into %s spot %d'):format(plate, newPlate, args.garage, spotId), type = 'success' })
        return
    end

    if Schema.isEsx then
        MySQL.insert.await(
            ('INSERT INTO `%s` (`plate`, `%s`, `vehicle`, `company`, `state`) VALUES (?, ?, ?, ?, 0)'):format(Config.ownedVehiclesTable, identifierColumn),
            { newPlate, row[identifierColumn], mods, row.company }
        )
    else
        MySQL.insert.await(
            ('INSERT INTO `%s` (`plate`, `%s`, `vehicle`, `hash`, `mods`, `company`, `state`) VALUES (?, ?, ?, ?, ?, ?, 0)'):format(Config.ownedVehiclesTable, identifierColumn),
            { newPlate, row[identifierColumn], row.vehicle, row.hash, mods, row.company }
        )
    end

    props       = props or {}
    props.model = model
    props.plate = newPlate

    TriggerClientEvent('snowy_garages:adminSpawnVehicle', source, props, newPlate)
end)

lib.addCommand('getvehicle', {
    help       = locale('getvehicle_cmd_help'),
    restricted = 'group.admin',
    params     = {
        { name = 'plate', type = 'string', help = 'Plate of the vehicle to fetch' },
    },
}, function(source, args)
    if not isPlayerLoaded(source) then return end

    local plate = args.plate:upper():gsub('%s', '')
    local row   = MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    if not row then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_plate'):format(plate), type = 'error' })
        return
    end

    clearVehicleStorage(plate, row.garage, row.garageSpotID)

    if row.netid then
        TriggerClientEvent('snowy_garages:teleportVehicleToMe', source, tonumber(row.netid))
        return
    end

    local model, props = parseVehicleRow(row)
    if not model then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_model'), type = 'error' })
        return
    end

    props       = props or {}
    props.model = model
    props.plate = plate

    TriggerClientEvent('snowy_garages:adminSpawnVehicle', source, props, plate)
end)

lib.addCommand('gotovehicle', {
    help       = locale('gotovehicle_cmd_help'),
    restricted = 'group.admin',
    params     = {
        { name = 'plate', type = 'string', help = 'Plate of the vehicle' },
    },
}, function(source, args)
    if not isPlayerLoaded(source) then return end

    local plate = args.plate:upper():gsub('%s', '')
    local row   = MySQL.single.await(
        ('SELECT ' .. Schema.positionSelect .. ' FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    if not row then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_plate'):format(plate), type = 'error' })
        return
    end

    local netId = row.netid and tonumber(row.netid)
    local pos   = row.position and json.decode(row.position)
    if not netId and not pos then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_position'), type = 'error' })
        return
    end

    TriggerClientEvent('snowy_garages:gotoVehicle', source, netId, pos)
end)

lib.addCommand('delveh', {
    help       = locale('delveh_cmd_help'),
    restricted = 'group.admin',
    params     = {
        { name = 'plate', type = 'string', help = 'Plate of the vehicle to delete' },
    },
}, function(source, args)
    if not isPlayerLoaded(source) then return end

    local plate = args.plate:upper():gsub('%s', '')
    local row   = MySQL.single.await(
        ('SELECT `netid` FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    if not row then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_plate'):format(plate), type = 'error' })
        return
    end

    if row.netid then
        TriggerClientEvent('snowy_garages:forceDeleteVehicle', -1, row.netid)
    end

    MySQL.query.await(
        ('DELETE FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )

    TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_db_deleted'):format(plate), type = 'success' })
end)

lib.addCommand('respawnveh', {
    help       = locale('respawnveh_cmd_help'),
    restricted = 'group.admin',
    params     = {
        { name = 'plate', type = 'string', help = 'Plate of the vehicle to respawn' },
    },
}, function(source, args)
    if not isPlayerLoaded(source) then return end

    local plate = args.plate:upper():gsub('%s', '')
    local row   = MySQL.single.await(
        ('SELECT * FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    if not row then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_plate'):format(plate), type = 'error' })
        return
    end

    local model, props = parseVehicleRow(row)
    if not model then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_no_model'), type = 'error' })
        return
    end

    local existing = findVehicleByPlate(plate)
    if existing then DeleteEntity(existing) end

    clearVehicleStorage(plate, row.garage, row.garageSpotID)

    props       = props or {}
    props.model = model
    props.plate = plate

    TriggerClientEvent('snowy_garages:adminSpawnVehicle', source, props, plate)
end)

RegisterNetEvent('snowy_garages:adminCarData', function(plate, props)
    local source = source
    if not isPlayerLoaded(source) then return end
    if not hasAdminPermission(source) then return end
    if type(plate) ~= 'string' or #plate > 8 then return end
    if type(props) ~= 'table' or not props.model then return end

    local identifier = Bridge.getPlayerIdentifier(source)
    if not identifier then return end

    local vehicle = findVehicleByPlate(plate)
    if not vehicle then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_not_found_server'), type = 'error' })
        return
    end

    local modelHash        = tonumber(props.model)
    local identifierColumn = Bridge.identifierColumn

    local row = MySQL.single.await(
        ('SELECT `plate` FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    local propsJson = json.encode(props)

    if row then
        if Schema.isEsx then
            MySQL.update.await(
                ('UPDATE `%s` SET `%s` = ?, `company` = NULL, `vehicle` = ? WHERE `plate` = ?'):format(Config.ownedVehiclesTable, identifierColumn),
                { identifier, propsJson, plate }
            )
        else
            MySQL.update.await(
                ('UPDATE `%s` SET `%s` = ?, `company` = NULL, `hash` = ?, `mods` = ? WHERE `plate` = ?'):format(Config.ownedVehiclesTable, identifierColumn),
                { identifier, modelHash, propsJson, plate }
            )
        end
    else
        props.plate = plate
        propsJson   = json.encode(props)
        if Schema.isEsx then
            MySQL.insert.await(
                ('INSERT INTO `%s` (`plate`, `%s`, `vehicle`, `state`) VALUES (?, ?, ?, 0)'):format(Config.ownedVehiclesTable, identifierColumn),
                { plate, identifier, propsJson }
            )
        else
            MySQL.insert.await(
                ('INSERT INTO `%s` (`plate`, `%s`, `hash`, `mods`, `state`) VALUES (?, ?, ?, ?, 0)'):format(Config.ownedVehiclesTable, identifierColumn),
                { plate, identifier, modelHash, propsJson }
            )
        end
    end

    TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_now_own'):format(plate), type = 'success' })
end)

RegisterNetEvent('snowy_garages:setJobVehicleData', function(plate, job, modelHash, props)
    local source = source
    if not isPlayerLoaded(source) then return end
    if not hasAdminPermission(source) then return end
    if type(plate) ~= 'string' or #plate > 8 then return end
    if type(job) ~= 'string' or job == '' then return end

    local row = MySQL.single.await(
        ('SELECT `plate` FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { plate }
    )
    if not row then
        TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_not_owned'), type = 'error' })
        return
    end

    local hash     = tonumber(modelHash)
    local modsJson = (type(props) == 'table') and json.encode(props) or nil
    if Schema.isEsx then
        MySQL.update.await(
            ('UPDATE `%s` SET `owner` = NULL, `company` = ?, `vehicle` = COALESCE(?, `vehicle`) WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
            { job, modsJson, plate }
        )
        MySQL.update.await(
            ('UPDATE `%s` SET `owner` = NULL WHERE (`company` = ? OR `company` LIKE ?) AND `plate` != ?'):format(Config.ownedVehiclesTable),
            { job, job .. ':%', plate }
        )
    else
        MySQL.update.await(
            ('UPDATE `%s` SET `citizenid` = NULL, `license` = NULL, `company` = ?, `hash` = ?, `mods` = COALESCE(?, `mods`) WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
            { job, hash, modsJson, plate }
        )
        MySQL.update.await(
            ('UPDATE `%s` SET `citizenid` = NULL, `license` = NULL WHERE (`company` = ? OR `company` LIKE ?) AND `plate` != ?'):format(Config.ownedVehiclesTable),
            { job, job .. ':%', plate }
        )
    end
    TriggerClientEvent('ox_lib:notify', source, { title = locale('impound_company_set'):format(plate, job), type = 'success' })
end)
