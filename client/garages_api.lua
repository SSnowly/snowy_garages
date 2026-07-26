local RETRY_TIMEOUT  = 5000
local RETRY_INTERVAL = 250

---`server/garages.lua` registers this callback only after its initial DB load finishes -
---on a slow boot a client resource can start (and this gets called from a startup
---CreateThread) before the server side is ready. lib.callback.await with no timeout would
---then hang forever waiting for a response that's never sent, so retry with a bounded
---timeout until the server is up, then fall back to an unbounded wait just in case.
---@return Garage[]
local function getGarages()
    local deadline = GetGameTimer() + RETRY_TIMEOUT
    while GetGameTimer() < deadline do
        Wait(100)
        local result = lib.callback.await('snowy_garages:getGarages', RETRY_INTERVAL)
        if result then return result end
    end

    return lib.callback.await('snowy_garages:getGarages', false)
end

return {
    getGarages = getGarages,
}
