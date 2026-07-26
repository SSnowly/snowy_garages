---@param point vector4
---@param front number
---@param left  number
---@param up    number
---@return vector3
local function offsetFromPoint(point, front, left, up)
    local rad     = math.rad(point.w)
    local forward = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local sideways = vector3(math.cos(rad), math.sin(rad), 0.0)
    return vector3(point.x, point.y, point.z) + forward * front - sideways * left + vector3(0.0, 0.0, up)
end

local CAR_SPAWN   = vector4(485.44,    -1307.5,   28.26, 214.9)
local BOAT_SPAWN  = vector4(-789.49,  -1428.88,  -0.66,  133.2)
local PLANE_SPAWN = vector4(-1008.26, -2981.2,    12.94,  54.16)
local HELI_SPAWN  = vector4(-1178.28, -2845.51,   12.95, 152.06)

return {
    debug   = false,
    logging = false,

    -- Set to false to suppress vehicle-stored / vehicle-retrieved log entries.
    saveLogs = true,

    -- Name of the framework-owned vehicle ownership table.
    -- Column used for the owner identifier is detected automatically from the active framework
    -- (citizenid for QBox/QBCore, identifier for ESX).
    ownedVehiclesTable = 'player_vehicles',

    -- Plate generation pattern (must be exactly 8 characters).
    -- A = random uppercase letter, 1 = random digit, any other character = literal.
    -- e.g. 'AAAA1111' -> 'XKQM4821', 'EEAA1111' -> 'EEXK4821'
    platePattern = 'AAAA1111',

    -- Plate pattern applied to ambient NPC vehicles on spawn so they never collide with
    -- player plates. Set to false to disable NPC plate rewriting entirely.
    -- Default starts with 4 digits so it can never match the default 'AAAA1111' player pattern.
    npcPlatePattern = '1111AAAA',

    autosaveIntervalMinutes = 5,
    autosaveClientTimeoutMs = 2000,

    loadDistance        = 120.0,
    interactDistance    = 4.0,
    iplInteractDistance = 2.0,
    spotInteractDistance = 2.0,

    -- ACE group names whose members may use the garage creator and admin commands.
    creatorGroups = { ['superadmin'] = true, ['admin'] = true },

    parkingGracePeriod = 3600,
    payStationModel    = `prop_parkingpay`,

    -- Jobs whose members can use /impound.
    impoundJobs = { 'police', 'sheriff' },

    -- Default fine pre-filled in the /impound dialog. Officers can override per impound.
    impoundFee    = 500,
    impoundRadius = 3.0,

    -- Progress bar duration (seconds) and animation played while an officer impounds a vehicle.
    impoundDuration = 10,
    impoundAnimDict = 'amb@world_human_clipboard@male@idle_a',
    impoundAnim     = 'idle_a',

    -- Marker RGBA colours used by client-side overlays.
    markers = {
        spawn       = { r = 0,   g = 160, b = 255, a = 150 }, -- spawn-spot indicator (blue)
        entrance    = { r = 0,   g = 255, b = 0,   a = 150 }, -- IPL entrance door (green)
        vehicleExit = { r = 180, g = 0,   b = 255, a = 150 }, -- IPL vehicle exit point (purple)
        entryPoint  = { r = 255, g = 160, b = 0,   a = 150 }, -- IPL on-foot / vehicle arrival (orange)
        payStation  = { r = 255, g = 0,   b = 200, a = 150 }, -- pay station (pink)
        iplEntrance = { r = 0,   g = 160, b = 255, a = 150 }, -- live IPL entrance proximity (blue)
        freeSpot    = { r = 0,   g = 200, b = 255, a = 120 }, -- unoccupied parking spot (light-blue)
        zone        = { r = 114, g = 49,  b = 212, a = 200 }, -- creator zone boundary line (purple)
        zoneCeiling = { r = 114, g = 49,  b = 212, a = 230 }, -- zone ceiling / corner lines
        cameraHit   = { r = 255, g = 0,   b = 60,  a = 220 }, -- creator camera raycast crosshair
    },

    -- Z-offsets applied when placing a spot ghost in the creator.
    -- Boats rely on GetWaterHeight and need no extra lift; air spots already include 2m.
    spawnZOffset = {
        car  = 1.0,
        boat = 0.0,
        air  = 2.0,
    },

    -- Vehicle class ids routed to each impound lot.
    impoundLots = {
        {
            id         = 'car',
            label      = 'Capital Blvd',
            classes    = nil,
            location   = vector3(495.73, -1340.29, 29.31),
            spawnPoint = CAR_SPAWN,
            blipCoords = vector3(485.16, -1322.74, 49.07),
            previewSpawn     = CAR_SPAWN,
            previewCamCoords = offsetFromPoint(CAR_SPAWN, 5.0, 3.0, 2.0),
            npc = {
                model    = `a_m_m_rurmeth_01`,
                coords   = vector4(495.75, -1340.83, 28.31, 358.03),
                animDict = 'mini@hookers_spvanilla',
                anim     = 'idle_reject_loop_a',
            },
        },
        {
            id         = 'boat',
            label      = 'Goma St',
            classes    = { 14 },
            location   = vector3(-772.02, -1431.83, 2.6),
            spawnPoint = BOAT_SPAWN,
            blipCoords = vector3(-773.02, -1431.09, 0.87),
            previewSpawn     = BOAT_SPAWN,
            previewCamCoords = offsetFromPoint(BOAT_SPAWN, 5.0, 3.0, 2.0),
            npc = {
                model    = `a_m_m_rurmeth_01`,
                coords   = vector4(-772.02, -1431.83, 0.6, 52.12),
                animDict = 'anim@heists@humane_labs@finale@strip_club',
                anim     = 'ped_b_celebrate_loop',
            },
        },
        {
            id         = 'plane',
            label      = 'International Airport',
            classes    = { 16 },
            location   = vector3(-943.05, -2964.19, 14.95),
            spawnPoint = PLANE_SPAWN,
            blipCoords = vector3(-943.05, -2964.19, 12.95),
            previewSpawn     = PLANE_SPAWN,
            previewCamCoords = offsetFromPoint(PLANE_SPAWN, 8.0, 5.0, 3.0),
            npc = {
                model    = `a_m_m_rurmeth_01`,
                coords   = vector4(-943.05, -2964.19, 12.95, 63.59),
                animDict = 'anim@heists@humane_labs@finale@strip_club',
                anim     = 'ped_b_celebrate_loop',
            },
        },
        {
            id         = 'heli',
            label      = 'International Airport',
            classes    = { 15 },
            location   = vector3(-1161.54, -2855.52, 14.95),
            spawnPoint = HELI_SPAWN,
            blipCoords = vector3(-1161.54, -2855.52, 12.95),
            previewSpawn     = HELI_SPAWN,
            previewCamCoords = offsetFromPoint(HELI_SPAWN, 8.0, 5.0, 3.0),
            npc = {
                model    = `a_m_m_rurmeth_01`,
                coords   = vector4(-1161.54, -2855.52, 12.95, 240.14),
                animDict = 'anim@heists@humane_labs@finale@strip_club',
                anim     = 'ped_b_celebrate_loop',
            },
        },
    },
}
