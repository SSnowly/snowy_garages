local Config  = require "configs.shared.main"
local Bridge  = require "bridge._index"
local Garages = require "server.garages"

---@param source number
---@return boolean
local function isPlayerLoaded(source)
    return source > 0 and GetPlayerName(source) ~= nil
end

---Players type plates by hand at the pay station, so spacing/casing shouldn't matter -
---strip everything but letters/digits and uppercase, then compare against the DB's stored
---plate the same way (plates are otherwise stored padded, e.g. " ABC 123").
---@param plate string
---@return string
local function normalizePlate(plate)
    return plate:gsub('%s+', ''):upper()
end

lib.callback.register('snowy_garages:payParkingBill', function(source, garageIdentifier, plate, accountType)
    if not isPlayerLoaded(source) then return false end
    if accountType ~= 'cash' and accountType ~= 'bank' then return false end
    if type(plate) ~= 'string' or plate == '' then return false end

    local garage = Garages.getByIdentifier(garageIdentifier)
    if not garage or not garage.fee or garage.fee <= 0 then return false end

    local normalized = normalizePlate(plate)
    local row = MySQL.single.await(
        ('SELECT `plate`, `garage`, `parking_date` FROM `%s` WHERE REPLACE(`plate`, \' \', \'\') = ?'):format(Config.ownedVehiclesTable),
        { normalized }
    )
    -- Paying for anyone's vehicle is allowed, but only while it's actually parked at this
    -- specific garage - not just "somewhere", and not anyone else's spot.
    if not row or row.garage ~= garageIdentifier or not row.parking_date then return 'nothing_owed' end

    local elapsed = os.time() - tonumber(row.parking_date)
    if elapsed <= Config.parkingGracePeriod then return 'nothing_owed' end

    local amount = math.ceil(elapsed / 3600) * garage.fee
    if not Bridge.removeMoney(source, accountType, amount) then return false end

    MySQL.update.await(
        ('UPDATE `%s` SET `parking_date` = ? WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
        { os.time(), row.plate }
    )

    return amount
end)
