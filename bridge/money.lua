local M  = {}
local fw = require "bridge.framework"

---ESX uses 'money'/'bank' account names; QB uses 'cash'/'bank'.
---@param accountType 'cash'|'bank'
---@return string
local function toEsxAccount(accountType)
    return accountType == 'cash' and 'money' or accountType
end

---@param source number
---@param accountType 'cash'|'bank'
---@return number
function M.getMoney(source, accountType)
    if fw.name == 'qbox' or fw.name == 'qbcore' then
        local player = exports.qbx_core:GetPlayer(source)
        if not player then return 0 end
        return player.PlayerData.money[accountType] or 0
    elseif fw.name == 'esx' then
        local xPlayer = exports.es_extended:GetPlayerFromId(source)
        if not xPlayer then return 0 end
        local account = xPlayer.getAccount(toEsxAccount(accountType))
        return account and account.money or 0
    end
    return 0
end

---@param source number
---@param accountType 'cash'|'bank'
---@param amount number
---@return boolean
function M.removeMoney(source, accountType, amount)
    if fw.name == 'qbox' or fw.name == 'qbcore' then
        local player = exports.qbx_core:GetPlayer(source)
        if not player then return false end
        if (player.PlayerData.money[accountType] or 0) < amount then return false end
        return player.Functions.RemoveMoney(accountType, amount, 'snowy_garages')
    elseif fw.name == 'esx' then
        local xPlayer = exports.es_extended:GetPlayerFromId(source)
        if not xPlayer then return false end
        local account = xPlayer.getAccount(toEsxAccount(accountType))
        if not account or account.money < amount then return false end
        xPlayer.removeAccountMoney(toEsxAccount(accountType), amount)
        return true
    end
    return false
end

return M
