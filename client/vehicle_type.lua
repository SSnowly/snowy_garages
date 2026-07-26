local BOAT_CLASS = 14
local AIR_CLASSES = { [15] = true, [16] = true } -- helicopters, planes

---@param model number
---@return 'car'|'air'|'boat'
local function classify(model)
    local class = GetVehicleClassFromName(model)
    if class == BOAT_CLASS then return 'boat' end
    if AIR_CLASSES[class] then return 'air' end
    return 'car'
end

return {
    classify = classify,
}
