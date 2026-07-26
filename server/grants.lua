---One-time key grants issued server-side after a validated impound release.
---Consumed by snowy_garages:giveImpoundKeys to prevent the event being fired
---arbitrarily by any player to acquire keys for vehicles they did not release.
---@type table<number, true>
local grants = {}

return {
    set = function(source)
        grants[source] = true
    end,
    consume = function(source)
        if not grants[source] then return false end
        grants[source] = nil
        return true
    end,
}
