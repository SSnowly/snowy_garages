local Framework = require "bridge.framework"

local isEsx = Framework.isEsx

---@param row table
---@return number? model, table? props
local function parseVehicleRow(row)
    if isEsx then
        local props = row.vehicle and json.decode(row.vehicle) or nil
        local model = props and tonumber(props.model) or nil
        return model, props
    else
        local model = tonumber(row.hash)
        local props = row.mods and json.decode(row.mods) or nil
        if props then props.model = model end
        return model, props
    end
end

return {
    isEsx           = isEsx,
    parseVehicleRow = parseVehicleRow,

    -- SELECT cols for listing vehicles in a garage (%s = identifierColumn).
    vehicleDisplaySelect = isEsx
        and '`plate`, `vehicle`, `garageSpotID`, `%s`, `company`'
        or  '`plate`, `vehicle`, `mods`, `hash`, `garageSpotID`, `%s`, `company`',

    -- SELECT cols for single vehicle display without spotId (%s = identifierColumn).
    vehicleSingleSelect = isEsx
        and '`plate`, `vehicle`, `%s`, `company`'
        or  '`plate`, `vehicle`, `mods`, `hash`, `%s`, `company`',

    -- SELECT cols for the impound list (%s = identifierColumn).
    impoundListSelect = isEsx
        and '`plate`, `vehicle`, `garage`, `netid`, `impound_date`, `impound_fine`, `impound_until`, `impound_reason`, `%s`, `company`'
        or  '`plate`, `vehicle`, `mods`, `garage`, `netid`, `impound_date`, `impound_fine`, `impound_until`, `impound_reason`, `%s`, `company`',

    -- SELECT cols for gotovehicle (%s not used, but keep consistent).
    positionSelect = isEsx and '`netid`' or '`netid`, `position`',

    -- Injected into UPDATE SET clauses where QBCore tracks position but ESX doesn't.
    positionNull = isEsx and '' or ', `position` = NULL',
}
