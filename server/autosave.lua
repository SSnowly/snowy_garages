local Config  = require "configs.shared.main"
local Schema  = require "server.schema"

---@type table<number, { plate: string, done: boolean, props: table?, expectedSource: number? }>
local pending = {}
local nextRequestId = 0

RegisterNetEvent('snowy_garages:autosaveResult', function(requestId, plate, props)
    local request = pending[requestId]
    if not request or request.done or request.plate ~= plate then return end
    if request.expectedSource and source ~= request.expectedSource then return end

    request.done = true
    request.props = props
end)

---Broadcasts to every client since only whichever one actually has the vehicle streamed in
---can read its live properties - the rest silently ignore the request (see the handler in
---client/vehicle.lua). Waits up to Config.autosaveClientTimeoutMs for a reply before giving up.
---@param netId number
---@param plate string
---@return table?
local function requestVehicleProps(netId, plate)
    nextRequestId = nextRequestId + 1
    local requestId = nextRequestId

    local entity         = NetworkGetEntityFromNetworkId(netId)
    local expectedSource = (entity ~= 0 and DoesEntityExist(entity)) and NetworkGetEntityOwner(entity) or nil
    pending[requestId] = { plate = plate, done = false, props = nil, expectedSource = expectedSource }

    TriggerClientEvent('snowy_garages:autosaveRequest', -1, netId, requestId, plate)

    local timeout = GetGameTimer() + Config.autosaveClientTimeoutMs
    local request = pending[requestId]
    while not request.done and GetGameTimer() < timeout do
        Wait(100)
    end

    pending[requestId] = nil
    return request.props
end

local function runAutosave()
    local startedAt = GetGameTimer()

    local rows = MySQL.query.await(
        ('SELECT `plate`, `netid` FROM `%s` WHERE `garage` IS NULL AND `impound_date` IS NULL'):format(Config.ownedVehiclesTable)
    )

    local saved, skipped = 0, 0
    for _, row in ipairs(rows) do
        local props = row.netid and requestVehicleProps(row.netid, row.plate) or nil

        if props then
            local modsCol = Schema.isEsx and '`vehicle`' or '`mods`'
            MySQL.update.await(
                ('UPDATE `%s` SET %s = ? WHERE `plate` = ?'):format(Config.ownedVehiclesTable, modsCol),
                { json.encode(props), row.plate }
            )
            saved = saved + 1
        else
            skipped = skipped + 1
        end
    end

    local elapsedSeconds = (GetGameTimer() - startedAt) / 1000
    print(('[snowy_garages] Saved %d vehicles in %.2f seconds'):format(saved, elapsedSeconds))
    if skipped > 0 then
        print(('[snowy_garages] Skipped %d vehicles due to no client nearby'):format(skipped))
    end
end

CreateThread(function()
    while true do
        Wait(Config.autosaveIntervalMinutes * 60000)
        runAutosave()
    end
end)
