require "server.db"

---@class IplPreset
---@field id         number
---@field identifier string
---@field label      string
---@field entry      GarageEntry
---@field spawns     GarageSpawn[]

---@type table<string, IplPreset>
local presets = {}

---@param row table
---@return IplPreset
local function hydrate(row)
    return {
        id         = row.id,
        identifier = row.identifier,
        label      = row.label,
        entry      = json.decode(row.entry),
        spawns     = json.decode(row.spawns),
    }
end

local function loadPresets()
    local rows = MySQL.query.await('SELECT * FROM `snowy_garages_ipl_presets`')
    local next = {}
    for _, row in ipairs(rows) do
        next[row.identifier] = hydrate(row)
    end
    presets = next
end

loadPresets()

---@return IplPreset[]
local function getAll()
    local list = {}
    for _, preset in pairs(presets) do
        list[#list + 1] = preset
    end
    return list
end

---@param identifier string
---@return IplPreset?
local function getByIdentifier(identifier)
    return presets[identifier]
end

---@param identifier string
---@param label string
---@param entry GarageEntry
---@param spawns GarageSpawn[]
---@return boolean
local function upsert(identifier, label, entry, spawns)
    MySQL.query.await([[
        INSERT INTO `snowy_garages_ipl_presets` (`identifier`, `label`, `entry`, `spawns`, `created_at`)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `entry` = VALUES(`entry`), `spawns` = VALUES(`spawns`)
    ]], { identifier, label, json.encode(entry), json.encode(spawns), os.time() })
    loadPresets()
    return true
end

---@param identifier string
---@return boolean
local function remove(identifier)
    MySQL.query.await('DELETE FROM `snowy_garages_ipl_presets` WHERE `identifier` = ?', { identifier })
    loadPresets()
    return true
end

lib.callback.register('snowy_garages:getIplPresets', function(source)
    return getAll()
end)

return {
    getAll         = getAll,
    getByIdentifier = getByIdentifier,
    upsert         = upsert,
    remove         = remove,
}
