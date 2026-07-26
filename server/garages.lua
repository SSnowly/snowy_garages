require "server.db"

---@class GarageSpawn
---@field x       number
---@field y       number
---@field z       number
---@field heading number

---@class GarageEntry
---@field onFoot  GarageSpawn
---@field vehicle GarageSpawn

---@class GarageZone
---@field points GarageSpawn[]
---@field thickness number

---@class Garage
---@field id         number
---@field identifier string
---@field label      string
---@field type       'parking'|'garage'|'ipl'
---@field company    string?
---@field fee        number?
---@field entry      GarageEntry?
---@field payStations GarageSpawn[]?
---@field showBlip   boolean
---@field coords     vector3
---@field coordsHeading number
---@field vehicleCoords vector3?
---@field vehicleCoordsHeading number?
---@field spawns     GarageSpawn[]
---@field vehicleType 'car'|'air'|'boat'?
---@field zone       GarageZone?

---@type table<string, Garage>
local garages = {}

---A JSON object with numeric-looking keys (e.g. spawns with gaps in their original slot
---numbers) decodes with string keys ("1", "5", ...) - normalize back to numbers so
---`spawns[garageSpotID]` lookups keep working regardless of how the encoder serialized it.
---@param decoded table
---@return table
local function withNumericKeys(decoded)
    local normalized = {}
    for key, value in pairs(decoded) do
        normalized[tonumber(key) or key] = value
    end
    return normalized
end

---@param row table
---@return Garage
local function hydrate(row)
    local coords = json.decode(row.coords)
    local vehicleCoords = row.vehicle_coords and json.decode(row.vehicle_coords) or nil
    return {
        id         = row.id,
        identifier = row.identifier,
        label      = row.label,
        type       = row.type,
        company    = row.company,
        fee        = row.fee,
        entry      = row.entry and json.decode(row.entry) or nil,
        payStations = row.pay_stations and withNumericKeys(json.decode(row.pay_stations)) or nil,
        showBlip   = row.show_blip, -- oxmysql casts TINYINT(1) to a real boolean
        coords     = vector3(coords.x, coords.y, coords.z),
        coordsHeading = coords.heading or 0.0,
        vehicleCoords = vehicleCoords and vector3(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z) or nil,
        vehicleCoordsHeading = vehicleCoords and (vehicleCoords.heading or 0.0) or nil,
        spawns     = withNumericKeys(json.decode(row.spawns)),
        vehicleType = row.vehicle_type,
        zone       = row.zone and json.decode(row.zone) or nil,
    }
end

local function loadGarages()
    local rows = MySQL.query.await('SELECT * FROM `snowy_garages`')
    local next = {}
    for _, row in ipairs(rows) do
        next[row.identifier] = hydrate(row)
    end
    garages = next
end

loadGarages()

---@return Garage[]
local function getAll()
    local list = {}
    for _, garage in pairs(garages) do
        list[#list + 1] = garage
    end
    return list
end

---@param identifier string
---@return Garage?
local function getByIdentifier(identifier)
    return garages[identifier]
end

---@param identifier string
---@param label string
---@param garageType 'parking'|'garage'|'ipl'
---@param coords GarageSpawn
---@param spawns GarageSpawn[]
---@param company string?
---@param fee number?
---@param entry GarageEntry?
---@param payStations GarageSpawn[]?
---@param showBlip boolean?
---@param vehicleCoords GarageSpawn?
---@param vehicleType 'car'|'air'|'boat'?
---@param zone GarageZone?
local function upsert(identifier, label, garageType, coords, spawns, company, fee, entry, payStations, showBlip, vehicleCoords, vehicleType, zone)
    MySQL.query.await([[
        INSERT INTO `snowy_garages` (`identifier`, `label`, `type`, `company`, `fee`, `entry`, `pay_stations`, `show_blip`, `coords`, `vehicle_coords`, `spawns`, `vehicle_type`, `zone`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `type` = VALUES(`type`), `company` = VALUES(`company`),
            `fee` = VALUES(`fee`), `entry` = VALUES(`entry`), `pay_stations` = VALUES(`pay_stations`),
            `show_blip` = VALUES(`show_blip`), `coords` = VALUES(`coords`), `vehicle_coords` = VALUES(`vehicle_coords`),
            `spawns` = VALUES(`spawns`), `vehicle_type` = VALUES(`vehicle_type`), `zone` = VALUES(`zone`)
    ]], {
        identifier, label, garageType, company, fee,
        entry and json.encode(entry) or nil,
        payStations and json.encode(payStations) or nil,
        showBlip and 1 or 0,
        json.encode({ x = coords.x, y = coords.y, z = coords.z, heading = coords.heading or 0.0 }),
        vehicleCoords and json.encode({ x = vehicleCoords.x, y = vehicleCoords.y, z = vehicleCoords.z, heading = vehicleCoords.heading or 0.0 }) or nil,
        json.encode(spawns),
        vehicleType,
        zone and json.encode(zone) or nil,
        os.time(),
    })
    loadGarages()
end

---@param identifier string
local function remove(identifier)
    MySQL.query.await('DELETE FROM `snowy_garages` WHERE `identifier` = ?', { identifier })
    loadGarages()
end

lib.callback.register('snowy_garages:getGarages', function(source)
    return getAll()
end)

return {
    getAll         = getAll,
    getByIdentifier = getByIdentifier,
    upsert         = upsert,
    remove         = remove,
}
