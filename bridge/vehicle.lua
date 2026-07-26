local M = {}

---@param vehicle number
---@param props table
function M.setVehicleProperties(vehicle, props)
    lib.setVehicleProperties(vehicle, props)
end

---@param vehicle number
---@return table
function M.getVehicleProperties(vehicle)
    return lib.getVehicleProperties(vehicle)
end

---@param vehicle number
---@return table?
function M.getVehicleDeformation(vehicle)
    local state = GetResourceState('VehicleDeformation')
    if state ~= 'started' then
        debugPrint('[deformation] get skipped, VehicleDeformation state =', state)
        return nil
    end

    local ok, deformation = pcall(function()
        return exports['VehicleDeformation']:GetVehicleDeformation(vehicle)
    end)
    if not ok then
        debugPrint('[deformation] get export threw:', deformation)
        return nil
    end
    if type(deformation) ~= 'table' or not next(deformation) then
        debugPrint('[deformation] get returned empty/invalid:', type(deformation))
        return nil
    end

    local count = 0
    for _ in pairs(deformation) do count = count + 1 end
    debugPrint('[deformation] captured', count, 'entries')

    return deformation
end

---@param vehicle number
---@param deformation table?
function M.setVehicleDeformation(vehicle, deformation)
    local state = GetResourceState('VehicleDeformation')
    if not deformation then
        debugPrint('[deformation] set skipped, no stored deformation data')
        return
    end
    if state ~= 'started' then
        debugPrint('[deformation] set skipped, VehicleDeformation state =', state)
        return
    end

    local ok, err = pcall(function()
        exports['VehicleDeformation']:SetVehicleDeformation(vehicle, deformation)
    end)
    if not ok then
        debugPrint('[deformation] set export threw:', err)
    else
        debugPrint('[deformation] applied to vehicle', vehicle)
    end
end

return M
