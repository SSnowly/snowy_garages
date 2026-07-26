local Config = require "configs.shared.main"

---@param ... any
function debugPrint(...)
    if not Config.debug then return end
    local tag = IsDuplicityVersion() and '^5[server]^7' or '^6[client]^7'
    print(tag, ...)
end
