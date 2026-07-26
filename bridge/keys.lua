local M = {}

---@param source number
---@param vehicle number
function M.giveVehicleKeys(source, vehicle)
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        exports.qbx_vehiclekeys:GiveKeys(source, vehicle)
    elseif GetResourceState('qb-vehiclekeys') == 'started' then
        local plate = GetVehicleNumberPlateText(vehicle)
        TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate)
    else
        print('^3[snowy_garages] WARNING: no keys resource found (qbx_vehiclekeys / qb-vehiclekeys) - player will not receive vehicle keys^7')
    end
end

return M
