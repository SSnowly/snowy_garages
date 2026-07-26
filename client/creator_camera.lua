local Config = require "configs.shared.main"
local Camera = {}

local MOVE_SPEED       = 8.0
local FAST_MULTIPLIER  = 3.0
local LOOK_SENSITIVITY = 15.0
local RAYCAST_DISTANCE = 500.0
local DEFAULT_THICKNESS = 6.0
local THICKNESS_STEP   = 1.0
local MIN_THICKNESS    = 2.0
local HEADING_STEP     = 5.0

-- Preview models cycled in awaitParkingSpots, grouped by garage vehicleType.
-- Keybind Q/E (controls 73/51) switches between them while the placement session is open.
local MODELS = {
    car  = { `adder`,   `guardian`, `phantom`  }, -- sports / SUV / semi
    air  = { `buzzard2`, `swift2`,  `akula`    }, -- small heli / exec heli / stealth heli
    boat = { `dinghy`,  `toro`,     `marquis`  }, -- small / speedboat / sail
}

local LEFT_CLICK  = 24   -- INPUT_ATTACK   (LMB)
local RIGHT_CLICK = 25   -- INPUT_AIM      (RMB)
local ENTER       = 191  -- INPUT_FRONTEND_ACCEPT
local BACK        = 194  -- INPUT_FRONTEND_DELETE (Backspace)
local FINISH      = 47   -- INPUT_DETONATE (G)
local SCROLL_UP   = 181  -- INPUT_WEAPON_WHEEL_NEXT
local SCROLL_DN   = 180  -- INPUT_WEAPON_WHEEL_PREV
local CYCLE_NEXT  = 51   -- INPUT_CONTEXT  (E)

local DISABLED_CONTROLS = { 1, 2, 21, 22, 24, 25, 30, 31, 32, 33, 34, 35, 36, 51 }

---@param pitch   number
---@param heading number
---@return vector3
local function directionFromRot(pitch, heading)
    local pitchRad   = math.rad(pitch)
    local headingRad = math.rad(heading)
    local flat       = math.abs(math.cos(pitchRad))
    return vector3(-math.sin(headingRad) * flat, math.cos(headingRad) * flat, math.sin(pitchRad))
end

local function disableControls()
    for _, control in ipairs(DISABLED_CONTROLS) do
        DisableControlAction(0, control, true)
    end
    DisablePlayerFiring(cache.ped, true)
end

---@return number cam, vector3 coords, number pitch, number yaw
local function enterCameraMode()
    local coords = GetGameplayCamCoord()
    local rot    = GetGameplayCamRot(2)
    local fov    = GetGameplayCamFov()

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, coords.x, coords.y, coords.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
    SetCamFov(cam, fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
    FreezeEntityPosition(cache.ped, true)

    return cam, coords, rot.x, rot.z
end

---@param cam number
local function exitCameraMode(cam)
    RenderScriptCams(false, true, 500, true, true)
    SetCamActive(cam, false)
    DestroyCam(cam, true)
    FreezeEntityPosition(cache.ped, false)
end

---@param state { coords: vector3, pitch: number, yaw: number }
local function updateLook(state)
    local dx    = GetDisabledControlNormal(0, 1)
    local dy    = GetDisabledControlNormal(0, 2)
    state.yaw   = (state.yaw - dx * LOOK_SENSITIVITY) % 360.0
    state.pitch = math.max(-89.0, math.min(89.0, state.pitch - dy * LOOK_SENSITIVITY))
end

---@param state { coords: vector3, pitch: number, yaw: number }
local function updateMove(state)
    local forward = directionFromRot(state.pitch, state.yaw)
    local right   = directionFromRot(0.0, state.yaw - 90.0)
    local move    = vector3(0.0, 0.0, 0.0)

    if IsDisabledControlPressed(0, 32) then move = move + forward end
    if IsDisabledControlPressed(0, 33) then move = move - forward end
    if IsDisabledControlPressed(0, 34) then move = move - right   end
    if IsDisabledControlPressed(0, 35) then move = move + right   end
    if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end
    if IsDisabledControlPressed(0, 36) then move = move - vector3(0.0, 0.0, 1.0) end

    if move.x ~= 0.0 or move.y ~= 0.0 or move.z ~= 0.0 then
        local speed = MOVE_SPEED * GetFrameTime()
        if IsDisabledControlPressed(0, 21) then speed = speed * FAST_MULTIPLIER end
        state.coords = state.coords + (move / #move) * speed
    end
end

---@param state { coords: vector3, pitch: number, yaw: number }
---@return vector3
local function raycastFromCamera(state)
    local dir    = directionFromRot(state.pitch, state.yaw)
    local dest   = state.coords + dir * RAYCAST_DISTANCE
    local handle = StartShapeTestRay(state.coords.x, state.coords.y, state.coords.z, dest.x, dest.y, dest.z, -1, cache.ped, 0)
    local _, hit, endCoords = GetShapeTestResult(handle)
    return hit == 1 and endCoords or dest
end

---@param cam     number
---@param state   { coords: vector3, pitch: number, yaw: number }
---@param hint    string
---@return vector3
local function tick(cam, state, hint)
    disableControls()
    updateLook(state)
    updateMove(state)
    SetCamCoord(cam, state.coords.x, state.coords.y, state.coords.z)
    SetCamRot(cam, state.pitch, 0.0, state.yaw, 2)

    local hit = raycastFromCamera(state)
    local m   = Config.markers.cameraHit
    DrawMarker(28, hit.x, hit.y, hit.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, m.r, m.g, m.b, m.a, false, true, 2, true, nil, nil, false)

    lib.showTextUI(hint, { position = 'top-center', icon = 'crosshairs' })
    return hit
end

---Resolves a raycast terrain hit to the actual spawn position for the given vehicle type.
---Boats float to the nearest water surface; air gets a 2m clearance above terrain.
---@param hit         vector3
---@param vehicleType 'car'|'air'|'boat'|nil
---@return vector3
local function resolveSpawnPoint(hit, vehicleType)
    if vehicleType == 'boat' then
        local found, waterZ = GetWaterHeight(hit.x, hit.y, hit.z + 100.0)
        return vector3(hit.x, hit.y, found and waterZ or hit.z)
    elseif vehicleType == 'air' then
        return vector3(hit.x, hit.y, hit.z + 2.0)
    end
    return hit
end

---@param model   number
---@param x y z   number
---@param heading number
---@return number entity
local function spawnGhost(model, x, y, z, heading)
    lib.requestModel(model)
    local ent = CreateVehicle(model, x, y, z, heading, false, false)
    SetEntityAlpha(ent, 200, false)
    SetEntityCollision(ent, false, false)
    SetEntityInvincible(ent, true)
    FreezeEntityPosition(ent, true)
    return ent
end

---@param spot        GarageSpawn
---@param model       number
---@return number entity
local function spawnPlacedGhost(spot, model)
    return spawnGhost(model, spot.x, spot.y, spot.z, spot.heading)
end

---@param vehicleType 'car'|'air'|'boat'|nil
---@return number[]
local function modelListForType(vehicleType)
    return MODELS[vehicleType] or MODELS.car
end

---Free-fly camera + raycast placement of parking spots.
---Cycles through 3 preview vehicles (Q = prev, E = next) tuned to the garage vehicleType.
---Boats snap to water height; air spots are placed 2 m above terrain.
---@param promptLabel  string
---@param vehicleType  'car'|'air'|'boat'|nil
---@return GarageSpawn[]? -- nil if cancelled or nothing placed
function Camera.awaitParkingSpots(promptLabel, vehicleType)
    local cam, coords, pitch, yaw = enterCameraMode()
    local state = { coords = coords, pitch = pitch, yaw = yaw }

    local modelList = modelListForType(vehicleType)
    local modelIdx  = 1
    local zOffset   = Config.spawnZOffset[vehicleType or 'car'] or 1.0

    local ghost       = spawnGhost(modelList[modelIdx], coords.x, coords.y, coords.z, 0.0)
    local heading     = 0.0
    local spots       = {}
    local placedGhosts = {}
    local finished    = false

    while true do
        local rawHit = tick(cam, state,
            locale('creator_camera_hint_spot'):format(promptLabel, #spots, modelIdx, #modelList))
        local hit = resolveSpawnPoint(rawHit, vehicleType)

        SetEntityCoords(ghost, hit.x, hit.y, hit.z, false, false, false, false)
        SetEntityHeading(ghost, heading)

        if IsDisabledControlJustPressed(0, LEFT_CLICK) then
            local spot = { x = hit.x, y = hit.y, z = hit.z + zOffset, heading = heading }
            spots[#spots + 1]        = spot
            placedGhosts[#placedGhosts + 1] = spawnPlacedGhost(spot, modelList[modelIdx])

        elseif IsDisabledControlJustPressed(0, RIGHT_CLICK) then
            if #spots > 0 then
                spots[#spots] = nil
                DeleteEntity(placedGhosts[#placedGhosts])
                placedGhosts[#placedGhosts] = nil
            end

        elseif IsControlJustReleased(0, BACK) then
            break

        elseif IsControlJustReleased(0, ENTER) then
            finished = true
            break

        elseif IsControlPressed(0, SCROLL_UP) then
            heading = (heading + HEADING_STEP) % 360.0

        elseif IsControlPressed(0, SCROLL_DN) then
            heading = (heading - HEADING_STEP) % 360.0

        elseif IsDisabledControlJustPressed(0, CYCLE_NEXT) then
            modelIdx = modelIdx % #modelList + 1
            DeleteEntity(ghost)
            ghost = spawnGhost(modelList[modelIdx], hit.x, hit.y, hit.z, heading)
        end

        Wait(0)
    end

    lib.hideTextUI()
    exitCameraMode(cam)
    DeleteEntity(ghost)
    for _, car in ipairs(placedGhosts) do DeleteEntity(car) end

    if not finished or #spots == 0 then
        lib.notify({ title = locale('creator_placement_cancelled'), type = 'info' })
        return nil
    end

    return spots
end

---Free-fly camera + raycast placement of a single point.
---@param promptLabel string
---@return GarageSpawn? -- nil if cancelled
function Camera.awaitPoint(promptLabel)
    local cam, coords, pitch, yaw = enterCameraMode()
    local state  = { coords = coords, pitch = pitch, yaw = yaw }
    local result = nil

    while true do
        local hit = tick(cam, state, locale('creator_camera_hint_point'):format(promptLabel))

        if IsDisabledControlJustPressed(0, LEFT_CLICK) then
            result = { x = hit.x, y = hit.y, z = hit.z, heading = state.yaw }
            break
        elseif IsControlJustReleased(0, BACK) then
            break
        end

        Wait(0)
    end

    lib.hideTextUI()
    exitCameraMode(cam)

    if not result then
        lib.notify({ title = locale('creator_placement_cancelled'), type = 'info' })
    end
    return result
end

---Free-fly camera + raycast placement of a ground polygon (garage interaction zone).
---All points are locked to the Z of the first placed point so the preview exactly matches
---what ox_lib will create (it derives minZ/maxZ from the points, so varying terrain heights
---would produce a mismatched zone). Scroll adjusts how tall the zone is.
---@param promptLabel string
---@return { points: GarageSpawn[], thickness: number }? -- nil if cancelled
function Camera.awaitZone(promptLabel)
    local cam, coords, pitch, yaw = enterCameraMode()
    local state     = { coords = coords, pitch = pitch, yaw = yaw }
    local points    = {}
    local thickness = DEFAULT_THICKNESS
    local finished  = false

    while true do
        local hit = tick(cam, state,
            locale('creator_camera_hint_zone'):format(promptLabel, #points, thickness))

        local mc    = Config.markers
        local baseZ = #points > 0 and points[1].z or hit.z
        local topZ  = baseZ + thickness

        for i, point in ipairs(points) do
            local next = points[i + 1]

            -- vertical corner pillar
            DrawLine(point.x, point.y, baseZ, point.x, point.y, topZ,
                mc.zoneCeiling.r, mc.zoneCeiling.g, mc.zoneCeiling.b, mc.zoneCeiling.a)
            DrawMarker(28, point.x, point.y, topZ, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3,
                mc.zoneCeiling.r, mc.zoneCeiling.g, mc.zoneCeiling.b, mc.zoneCeiling.a,
                false, true, 2, true, nil, nil, false)

            if next then
                -- filled wall panel
                DrawPoly(point.x, point.y, baseZ, next.x,  next.y,  baseZ, next.x,  next.y,  topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 60)
                DrawPoly(next.x,  next.y,  baseZ, point.x, point.y, baseZ, next.x,  next.y,  topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 60)
                DrawPoly(point.x, point.y, baseZ, next.x,  next.y,  topZ,  point.x, point.y, topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 60)
                DrawPoly(next.x,  next.y,  topZ,  point.x, point.y, baseZ, point.x, point.y, topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 60)
                -- outline edges
                DrawLine(point.x, point.y, baseZ, next.x, next.y, baseZ, mc.zone.r, mc.zone.g, mc.zone.b, mc.zone.a)
                DrawLine(point.x, point.y, topZ,  next.x, next.y, topZ,  mc.zoneCeiling.r, mc.zoneCeiling.g, mc.zoneCeiling.b, mc.zoneCeiling.a)
            end
        end

        if #points >= 3 then
            local first, last = points[1], points[#points]
            DrawPoly(last.x,  last.y,  baseZ, first.x, first.y, baseZ, first.x, first.y, topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 40)
            DrawPoly(first.x, first.y, baseZ, last.x,  last.y,  baseZ, first.x, first.y, topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 40)
            DrawPoly(last.x,  last.y,  baseZ, first.x, first.y, topZ,  last.x,  last.y,  topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 40)
            DrawPoly(first.x, first.y, topZ,  last.x,  last.y,  baseZ, last.x,  last.y,  topZ,  mc.zone.r, mc.zone.g, mc.zone.b, 40)
            DrawLine(last.x, last.y, baseZ, first.x, first.y, baseZ, mc.zone.r, mc.zone.g, mc.zone.b, 120)
            DrawLine(last.x, last.y, topZ,  first.x, first.y, topZ,  mc.zoneCeiling.r, mc.zoneCeiling.g, mc.zoneCeiling.b, 120)
        end

        if IsDisabledControlJustPressed(0, LEFT_CLICK) then
            -- all points share the first point's Z so the polygon is flat and the zone matches the preview
            local z = #points == 0 and hit.z or points[1].z
            points[#points + 1] = { x = hit.x, y = hit.y, z = z }

        elseif IsDisabledControlJustPressed(0, RIGHT_CLICK) then
            if #points > 0 then points[#points] = nil end

        elseif IsControlJustReleased(0, BACK) then
            break

        elseif IsControlJustReleased(0, FINISH) and #points >= 3 then
            finished = true
            break

        elseif IsControlPressed(0, SCROLL_UP) then
            thickness = thickness + THICKNESS_STEP

        elseif IsControlPressed(0, SCROLL_DN) then
            thickness = math.max(MIN_THICKNESS, thickness - THICKNESS_STEP)
        end

        Wait(0)
    end

    lib.hideTextUI()
    exitCameraMode(cam)

    if not finished then
        lib.notify({ title = locale('creator_placement_cancelled'), type = 'info' })
        return nil
    end

    return { points = points, thickness = thickness }
end

---@param model number
---@param x number
---@param y number
---@param z number
---@param heading number
---@return number entity
local function spawnGhostProp(model, x, y, z, heading)
    lib.requestModel(model)
    local ent = CreateObject(model, x, y, z, false, false, false)
    SetEntityAlpha(ent, 200, false)
    SetEntityCollision(ent, false, false)
    SetEntityInvincible(ent, true)
    FreezeEntityPosition(ent, true)
    SetEntityHeading(ent, heading)
    return ent
end

---Free-fly camera + raycast placement of pay station props.
---Works identically to awaitParkingSpots: LMB places, RMB undoes last, scroll rotates,
---Enter confirms the session, Backspace cancels.
---@param promptLabel string
---@return GarageSpawn[]? -- nil if cancelled or nothing placed
function Camera.awaitPayStations(promptLabel)
    local cam, coords, pitch, yaw = enterCameraMode()
    local state = { coords = coords, pitch = pitch, yaw = yaw }

    local model        = Config.payStationModel
    local heading      = 0.0
    local stations     = {}
    local placedGhosts = {}
    local finished     = false

    local ghost = spawnGhostProp(model, coords.x, coords.y, coords.z, heading)

    while true do
        local hit = tick(cam, state,
            locale('creator_camera_hint_paystation'):format(promptLabel, #stations))

        SetEntityCoords(ghost, hit.x, hit.y, hit.z, false, false, false, false)
        SetEntityHeading(ghost, heading)

        if IsDisabledControlJustPressed(0, LEFT_CLICK) then
            local s = { x = hit.x, y = hit.y, z = hit.z, heading = heading }
            stations[#stations + 1]        = s
            placedGhosts[#placedGhosts + 1] = spawnGhostProp(model, s.x, s.y, s.z, s.heading)

        elseif IsDisabledControlJustPressed(0, RIGHT_CLICK) then
            if #stations > 0 then
                stations[#stations] = nil
                DeleteEntity(placedGhosts[#placedGhosts])
                placedGhosts[#placedGhosts] = nil
            end

        elseif IsControlJustReleased(0, BACK) then
            break

        elseif IsControlJustReleased(0, ENTER) then
            finished = true
            break

        elseif IsControlPressed(0, SCROLL_UP) then
            heading = (heading + HEADING_STEP) % 360.0

        elseif IsControlPressed(0, SCROLL_DN) then
            heading = (heading - HEADING_STEP) % 360.0
        end

        Wait(0)
    end

    lib.hideTextUI()
    exitCameraMode(cam)
    DeleteEntity(ghost)
    for _, prop in ipairs(placedGhosts) do DeleteEntity(prop) end

    if not finished or #stations == 0 then
        lib.notify({ title = locale('creator_placement_cancelled'), type = 'info' })
        return nil
    end

    return stations
end

return Camera
