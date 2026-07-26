local Config = require "configs.shared.main"
local Plates = require "configs.shared.plates"

---@return string
local function generateUniquePlate()
    for _ = 1, 20 do
        local plate = Plates.generate()
        local exists = MySQL.scalar.await(
            ('SELECT 1 FROM `%s` WHERE `plate` = ?'):format(Config.ownedVehiclesTable),
            { plate }
        )
        if not exists then return plate end
    end
    error('snowy_garages: exhausted plate generation attempts')
end

exports('generatePlate', generateUniquePlate)

return {
    generateUniquePlate = generateUniquePlate,
}
