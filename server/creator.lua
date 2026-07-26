local Config  = require "configs.shared.main"
local Bridge  = require "bridge._index"
local Garages = require "server.garages"
local Presets = require "server.ipl_presets"

---@param source number
---@return boolean
local function isPlayerLoaded(source)
    return source > 0 and GetPlayerName(source) ~= nil
end

---FXServer ACE groups aren't reliably set up on this server, so permission is checked
---against the player's ESX group instead (owner/developer-type admins, per Config.creatorGroups).
---@param source number
---@return boolean
local function hasCreatorPermission(source)
    local group = Bridge.getPlayerGroup(source)
    return group ~= nil and Config.creatorGroups[group] == true
end

---@param identifier string
---@return boolean
local function isValidIdentifier(identifier)
    return type(identifier) == 'string' and identifier:match('^[%w_%-]+$') ~= nil
end

---@param point table
---@return boolean
local function isValidPoint(point)
    return type(point) == 'table'
        and type(point.x) == 'number' and type(point.y) == 'number'
        and type(point.z) == 'number' and type(point.heading) == 'number'
end

---Garages can have gap-keyed spawns (a spot deleted mid-edit, or inherited from the legacy
---migration) - `#`/`ipairs` silently stop at the first hole, so this must walk every key.
---@param spawns table
---@return boolean
local function areValidSpawns(spawns)
    if type(spawns) ~= 'table' or not next(spawns) then return false end
    for key, spawn in pairs(spawns) do
        if type(key) ~= 'number' or key ~= math.floor(key) or key < 1 then return false end
        if not isValidPoint(spawn) then return false end
    end
    return true
end

---@param points table
---@return boolean
local function areValidPoints(points)
    if type(points) ~= 'table' then return false end
    for _, point in ipairs(points) do
        if not isValidPoint(point) then return false end
    end
    return true
end

---@param zone table
---@return boolean
local function isValidZone(zone)
    if type(zone) ~= 'table' then return false end
    if type(zone.thickness) ~= 'number' or zone.thickness <= 0 then return false end
    if type(zone.points) ~= 'table' or #zone.points < 3 then return false end
    for _, point in ipairs(zone.points) do
        if type(point) ~= 'table' or type(point.x) ~= 'number' or type(point.y) ~= 'number' or type(point.z) ~= 'number' then
            return false
        end
    end
    return true
end

---@param draft table
---@return boolean
local function isValidDraft(draft)
    if type(draft) ~= 'table' then return false end
    if not isValidIdentifier(draft.identifier) then return false end
    if type(draft.label) ~= 'string' or draft.label == '' then return false end
    if draft.type ~= 'parking' and draft.type ~= 'garage' and draft.type ~= 'ipl' then return false end
    if draft.company ~= nil and type(draft.company) ~= 'string' then return false end
    if draft.fee ~= nil and type(draft.fee) ~= 'number' then return false end
    if draft.showBlip ~= nil and type(draft.showBlip) ~= 'boolean' then return false end
    if not areValidSpawns(draft.spawns) then return false end
    if draft.coords ~= nil and not isValidPoint(draft.coords) then return false end
    if draft.payStations ~= nil and not areValidPoints(draft.payStations) then return false end
    if draft.fee and draft.fee > 0 and (not draft.payStations or #draft.payStations == 0) then return false end
    if draft.vehicleType ~= nil and draft.vehicleType ~= 'car' and draft.vehicleType ~= 'air' and draft.vehicleType ~= 'boat' then return false end
    if not isValidZone(draft.zone) then return false end

    if draft.type == 'ipl' then
        if not draft.coords then return false end
        if not isValidPoint(draft.vehicleCoords) then return false end
        if type(draft.entry) ~= 'table' then return false end
        if not isValidPoint(draft.entry.onFoot) then return false end
        if not isValidPoint(draft.entry.vehicle) then return false end
    elseif draft.entry ~= nil or draft.vehicleCoords ~= nil then
        return false
    end

    return true
end

---@param preset table
---@return boolean
local function isValidPreset(preset)
    if type(preset) ~= 'table' then
        debugPrint('snowy_garages: preset rejected - not a table')
        return false
    end
    if not isValidIdentifier(preset.identifier) then
        debugPrint('snowy_garages: preset rejected - bad identifier', json.encode(preset.identifier))
        return false
    end
    if type(preset.label) ~= 'string' or preset.label == '' then
        debugPrint('snowy_garages: preset rejected - bad label', json.encode(preset.label))
        return false
    end
    if type(preset.entry) ~= 'table' then
        debugPrint('snowy_garages: preset rejected - entry not a table')
        return false
    end
    if not isValidPoint(preset.entry.onFoot) then
        debugPrint('snowy_garages: preset rejected - bad entry.onFoot', json.encode(preset.entry.onFoot))
        return false
    end
    if not isValidPoint(preset.entry.vehicle) then
        debugPrint('snowy_garages: preset rejected - bad entry.vehicle', json.encode(preset.entry.vehicle))
        return false
    end
    if not areValidSpawns(preset.spawns) then
        debugPrint('snowy_garages: preset rejected - bad spawns', json.encode(preset.spawns))
        return false
    end
    return true
end

lib.callback.register('snowy_garages:createGarage', function(source, draft)
    if not isPlayerLoaded(source) then return false end
    if not hasCreatorPermission(source) then return false end
    if not isValidDraft(draft) then return false end
    if Garages.getByIdentifier(draft.identifier) then return 'taken' end

    local point = draft.coords or draft.spawns[next(draft.spawns)]
    Garages.upsert(
        draft.identifier, draft.label, draft.type,
        point, draft.spawns,
        draft.company, draft.fee, draft.entry, draft.payStations, draft.showBlip,
        draft.vehicleCoords, draft.vehicleType, draft.zone
    )

    TriggerClientEvent('snowy_garages:garageCreated', -1, Garages.getByIdentifier(draft.identifier))
    return true
end)

---@param identifier string
---@return table<number, boolean>
local function getOccupiedSpotKeys(identifier)
    local rows = MySQL.query.await(
        ('SELECT `garageSpotID` FROM `%s` WHERE `garage` = ? AND `garageSpotID` IS NOT NULL'):format(Config.ownedVehiclesTable),
        { identifier }
    )
    local occupied = {}
    for _, row in ipairs(rows) do
        occupied[row.garageSpotID] = true
    end
    return occupied
end

lib.callback.register('snowy_garages:updateGarage', function(source, identifier, draft)
    if not isPlayerLoaded(source) then return false end
    if not hasCreatorPermission(source) then return false end

    local existing = Garages.getByIdentifier(identifier)
    if not existing then return 'notfound' end

    -- The identifier is the DB key and everything else (player_vehicles.garage, rentals,
    -- IPL routing) references it - it's never editable via the draft, only trusted from here.
    draft.identifier = identifier
    if not isValidDraft(draft) then return false end

    -- A spot dropped from the edited layout must not currently hold a vehicle, or that
    -- vehicle's garageSpotID would point at a slot that no longer exists.
    local occupied = getOccupiedSpotKeys(identifier)
    for key in pairs(existing.spawns or {}) do
        if draft.spawns[key] == nil and occupied[key] then
            return 'spot_occupied'
        end
    end

    local point = draft.coords or draft.spawns[next(draft.spawns)]
    Garages.upsert(
        identifier, draft.label, draft.type,
        point, draft.spawns,
        draft.company, draft.fee, draft.entry, draft.payStations, draft.showBlip,
        draft.vehicleCoords, draft.vehicleType, draft.zone
    )

    -- Reuse the create/delete propagation path so every client's proximity-streamed blip,
    -- marker, and pay-station prop for this garage gets torn down and rebuilt from scratch.
    TriggerClientEvent('snowy_garages:garageDeleted', -1, identifier)
    TriggerClientEvent('snowy_garages:garageCreated', -1, Garages.getByIdentifier(identifier))
    return true
end)

lib.callback.register('snowy_garages:deleteGarage', function(source, identifier)
    if not isPlayerLoaded(source) then return false end
    if not hasCreatorPermission(source) then return false end
    if not Garages.getByIdentifier(identifier) then return false end

    MySQL.update.await(
        ('UPDATE `%s` SET `garage` = NULL, `garageSpotID` = NULL, `impound_date` = ?, `impound_fine` = 0, `impound_until` = NULL, `impound_reason` = NULL, `state` = 2 WHERE `garage` = ?'):format(Config.ownedVehiclesTable),
        { os.time(), identifier }
    )

    Garages.remove(identifier)
    TriggerClientEvent('snowy_garages:garageDeleted', -1, identifier)
    return true
end)

lib.callback.register('snowy_garages:createIplPreset', function(source, preset)
    if not isPlayerLoaded(source) then
        debugPrint('snowy_garages: createIplPreset rejected - player not loaded', source)
        return false
    end
    if not hasCreatorPermission(source) then
        debugPrint('snowy_garages: createIplPreset rejected - missing group', Bridge.getPlayerGroup(source))
        return false
    end
    if not isValidPreset(preset) then return false end
    if Presets.getByIdentifier(preset.identifier) then return 'taken' end

    local ok, saved = pcall(Presets.upsert, preset.identifier, preset.label, preset.entry, preset.spawns)
    if not ok then
        debugPrint('snowy_garages: createIplPreset upsert threw', saved)
        return false
    end
    if not saved then
        debugPrint('snowy_garages: createIplPreset upsert did not persist to disk')
        return false
    end

    return true
end)

lib.callback.register('snowy_garages:deleteIplPreset', function(source, identifier)
    if not isPlayerLoaded(source) then return false end
    if not hasCreatorPermission(source) then return false end
    if not Presets.getByIdentifier(identifier) then return false end

    Presets.remove(identifier)
    return true
end)

lib.addCommand('garagecreator', { help = locale('creator_cmd_help_create') }, function(source)
    if not hasCreatorPermission(source) then return end
    TriggerClientEvent('snowy_garages:openCreatorMenu', source)
end)
