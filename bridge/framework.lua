local M = {}

if GetResourceState('qbx_core') == 'started' then
    M.name             = 'qbox'
    M.identifierColumn = 'citizenid'
    M.isEsx            = false
elseif GetResourceState('qb-core') == 'started' then
    M.name             = 'qbcore'
    M.identifierColumn = 'citizenid'
    M.isEsx            = false
elseif GetResourceState('es_extended') == 'started' then
    M.name             = 'esx'
    -- ESX owned_vehicles uses `owner`, not `identifier` (that's the users table column).
    M.identifierColumn = 'owner'
    M.isEsx            = true
else
    print('^1[snowy_garages] WARNING: no supported framework detected (qbx_core / qb-core / es_extended)^7')
    M.name             = 'unknown'
    M.identifierColumn = 'citizenid'
    M.isEsx            = false
end

return M
