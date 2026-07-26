local M  = {}
local fw = require "bridge.framework"

---@param source number
---@return string?
function M.getPlayerIdentifier(source)
    if fw.name == 'qbox' or fw.name == 'qbcore' then
        local player = exports.qbx_core:GetPlayer(source)
        return player and player.PlayerData.citizenid or nil
    elseif fw.name == 'esx' then
        local xPlayer = exports.es_extended:GetPlayerFromId(source)
        return xPlayer and xPlayer.identifier or nil
    end
    return nil
end

---@param source number
---@return string?
function M.getPlayerJob(source)
    if fw.name == 'qbox' or fw.name == 'qbcore' then
        local player = exports.qbx_core:GetPlayer(source)
        return player and player.PlayerData.job.name or nil
    elseif fw.name == 'esx' then
        local xPlayer = exports.es_extended:GetPlayerFromId(source)
        return xPlayer and xPlayer.job.name or nil
    end
    return nil
end

---@param source number
---@return string?
function M.getPlayerGang(source)
    if fw.name == 'qbox' or fw.name == 'qbcore' then
        local player = exports.qbx_core:GetPlayer(source)
        return player and player.PlayerData.gang.name or nil
    end
    return nil
end

---ACE-group check is framework-agnostic.
---@param source number
---@return string?
function M.getPlayerGroup(source)
    local src = tostring(source)
    if IsPlayerAceAllowed(src, 'superadmin') then return 'superadmin' end
    if IsPlayerAceAllowed(src, 'admin')      then return 'admin'      end
    if IsPlayerAceAllowed(src, 'mod')        then return 'mod'        end
    return nil
end

return M
