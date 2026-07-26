local Config     = require "configs.shared.main"
local GaragesApi = require "client.garages_api"
local Camera     = require "client.creator_camera"

---@class GarageDraft
---@field identifier string
---@field label      string
---@field type       'parking'|'garage'|'ipl'
---@field company    string?
---@field fee        number?
---@field coords     GarageSpawn?
---@field vehicleCoords GarageSpawn?
---@field entry      GarageEntry?
---@field payStations GarageSpawn[]
---@field showBlip   boolean
---@field spawns     GarageSpawn[]
---@field vehicleType 'car'|'air'|'boat'?
---@field zone       { points: GarageSpawn[], thickness: number }?

---@type GarageDraft?
local draft = nil

---Identifier of the garage currently being edited, or nil when `draft` is a brand new garage.
---@type string?
local editingIdentifier = nil

---Set while the admin is standing inside a preset interior placing spots/entry data,
---so they can be popped back to the exact spot (and heading) they were at outside.
---@type GarageSpawn?
local interiorReturnPoint = nil

---@param coords vector3
---@param text string
local function drawText3D(coords, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        if not draft then
            Wait(500)
        else
            local playerCoords = GetEntityCoords(cache.ped)
            for i, spawn in pairs(draft.spawns) do
                local coords = vector3(spawn.x, spawn.y, spawn.z)
                if #(playerCoords - coords) < 30.0 then
                    local m = Config.markers.spawn
                    DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, m.r, m.g, m.b, m.a, false, false, 2, false, nil, nil, false)
                    drawText3D(coords + vector3(0.0, 0.0, 0.5), tostring(i))
                end
            end

            if draft.coords then
                local coords = vector3(draft.coords.x, draft.coords.y, draft.coords.z)
                if #(playerCoords - coords) < 30.0 then
                    local m = Config.markers.entrance
                    DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, m.r, m.g, m.b, m.a, false, false, 2, false, nil, nil, false)
                    drawText3D(coords + vector3(0.0, 0.0, 0.5), locale('creator_label_entrance'))
                end
            end

            if draft.vehicleCoords then
                local coords = vector3(draft.vehicleCoords.x, draft.vehicleCoords.y, draft.vehicleCoords.z)
                if #(playerCoords - coords) < 30.0 then
                    local m = Config.markers.vehicleExit
                    DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, m.r, m.g, m.b, m.a, false, false, 2, false, nil, nil, false)
                    drawText3D(coords + vector3(0.0, 0.0, 0.5), locale('creator_label_vehicle_exit'))
                end
            end

            if draft.entry then
                for kind, point in pairs(draft.entry) do
                    local coords = vector3(point.x, point.y, point.z)
                    if #(playerCoords - coords) < 30.0 then
                        local me = Config.markers.entryPoint
                        DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, me.r, me.g, me.b, me.a, false, false, 2, false, nil, nil, false)
                        drawText3D(coords + vector3(0.0, 0.0, 0.5), kind == 'onFoot' and locale('creator_label_entry_foot') or locale('creator_label_entry_vehicle'))
                    end
                end
            end

            for _, station in ipairs(draft.payStations) do
                local coords = vector3(station.x, station.y, station.z)
                if #(playerCoords - coords) < 30.0 then
                    local mp = Config.markers.payStation
                    DrawMarker(21, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, mp.r, mp.g, mp.b, mp.a, false, false, 2, false, nil, nil, false)
                    drawText3D(coords + vector3(0.0, 0.0, 0.5), locale('creator_label_paystation'))
                end
            end

            if draft.zone then
                local zpoints = draft.zone.points
                if #zpoints > 0 then
                    local baseZ = zpoints[1].z
                    local topZ  = baseZ + draft.zone.thickness
                    local mz    = Config.markers.zone
                    local mc    = Config.markers.zoneCeiling
                    for i, point in ipairs(zpoints) do
                        local next = zpoints[i + 1] or zpoints[1]
                        DrawPoly(point.x, point.y, baseZ, next.x,  next.y,  baseZ, next.x,  next.y,  topZ, mz.r, mz.g, mz.b, 60)
                        DrawPoly(next.x,  next.y,  baseZ, point.x, point.y, baseZ, next.x,  next.y,  topZ, mz.r, mz.g, mz.b, 60)
                        DrawPoly(point.x, point.y, baseZ, next.x,  next.y,  topZ,  point.x, point.y, topZ, mz.r, mz.g, mz.b, 60)
                        DrawPoly(next.x,  next.y,  topZ,  point.x, point.y, baseZ, point.x, point.y, topZ, mz.r, mz.g, mz.b, 60)
                        DrawLine(point.x, point.y, baseZ, next.x,  next.y,  baseZ, mz.r, mz.g, mz.b, mz.a)
                        DrawLine(point.x, point.y, topZ,  next.x,  next.y,  topZ,  mc.r, mc.g, mc.b, mc.a)
                        DrawLine(point.x, point.y, baseZ, point.x, point.y, topZ,  mc.r, mc.g, mc.b, mc.a)
                    end
                end
            end

            Wait(0)
        end
    end
end)

---@param destination GarageSpawn
local function teleportTo(destination)
    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(0) end

    SetEntityCoords(cache.ped, destination.x, destination.y, destination.z, false, false, false, false)
    SetEntityHeading(cache.ped, destination.heading)

    Wait(200)
    DoScreenFadeIn(350)
end

local function returnFromInterior()
    if not interiorReturnPoint then return end
    local point = interiorReturnPoint
    interiorReturnPoint = nil
    teleportTo(point)
end

---Legacy garages can have gap-keyed spawns (spot 3 deleted years ago, etc) - `#`/`ipairs`
---silently stop at the first hole, so counting and key-picking must walk every key instead.
---@param spawns table<number, GarageSpawn>
---@return number
local function spawnCount(spawns)
    local count = 0
    for _ in pairs(spawns) do count = count + 1 end
    return count
end

---@param spawns table<number, GarageSpawn>
---@return number
local function nextSpawnKey(spawns)
    local maxKey = 0
    for key in pairs(spawns) do
        if key > maxKey then maxKey = key end
    end
    return maxKey + 1
end

local function startCreator()
    local input = lib.inputDialog(locale('creator_dialog_title'), {
        { type = 'input',  label = locale('creator_field_identifier'), required = true },
        { type = 'input',  label = locale('creator_field_label'),      required = true },
        {
            type = 'select', label = locale('creator_field_type'), required = true,
            options = {
                { value = 'parking', label = locale('creator_type_parking') },
                { value = 'garage',  label = locale('creator_type_garage') },
                { value = 'ipl',     label = locale('creator_type_ipl') },
            },
        },
        { type = 'input',   label = locale('creator_field_company') },
        { type = 'number',  label = locale('creator_field_fee') },
        { type = 'checkbox', label = locale('creator_field_show_blip') },
        {
            type = 'select', label = locale('creator_field_vehicle_type'), required = true, default = 'any',
            options = {
                { value = 'any', label = locale('creator_vehicletype_any') },
                { value = 'car', label = locale('creator_vehicletype_car') },
                { value = 'air', label = locale('creator_vehicletype_air') },
                { value = 'boat', label = locale('creator_vehicletype_boat') },
            },
        },
    })
    if not input then return end

    editingIdentifier = nil
    draft = {
        identifier = input[1],
        label      = input[2],
        type       = input[3],
        company    = input[4] ~= '' and input[4] or nil,
        fee        = tonumber(input[5]),
        showBlip   = input[6] or false,
        vehicleType = input[7] ~= 'any' and input[7] or nil,
        spawns     = {},
        payStations = {},
    }

    lib.notify({ title = locale('creator_started'), description = locale('creator_started_desc'), type = 'info' })
end

---Adding more spots later reuses this exact same function/menu button - it's just another
---placement session, there's no separate "edit" mode to switch into.
local function addPoints()
    if not draft then
        lib.notify({ title = locale('creator_no_active'), type = 'error' })
        return
    end

    local spots = Camera.awaitParkingSpots(locale('creator_placement_point'), draft.vehicleType)
    if not spots then return end

    for _, spot in ipairs(spots) do
        local key = nextSpawnKey(draft.spawns)
        draft.spawns[key] = spot
    end

    lib.notify({
        title       = locale('creator_point_added'),
        description = locale('creator_points_added_desc'):format(#spots, spawnCount(draft.spawns)),
        type        = 'success',
    })
end

local function setCoords()
    if not draft then
        lib.notify({ title = locale('creator_no_active'), type = 'error' })
        return
    end

    local point = Camera.awaitPoint(locale('creator_placement_coords'))
    if not point then return end

    draft.coords = point
    lib.notify({ title = locale('creator_coords_set'), type = 'success' })
end

local function setVehicleCoords()
    if not draft then
        lib.notify({ title = locale('creator_no_active'), type = 'error' })
        return
    end

    if draft.type ~= 'ipl' then
        lib.notify({ title = locale('creator_entry_wrong_type'), type = 'error' })
        return
    end

    local point = Camera.awaitPoint(locale('creator_placement_vehicle_coords'))
    if not point then return end

    draft.vehicleCoords = point
    lib.notify({ title = locale('creator_vehicle_coords_set'), type = 'success' })
end

local function addPayStations()
    if not draft then
        lib.notify({ title = locale('creator_no_active'), type = 'error' })
        return
    end

    local placed = Camera.awaitPayStations(locale('creator_placement_paystation'))
    if not placed then return end

    for _, station in ipairs(placed) do
        draft.payStations[#draft.payStations + 1] = station
    end

    lib.notify({
        title       = locale('creator_paystation_added'),
        description = locale('creator_paystations_added_desc'):format(#placed, #draft.payStations),
        type        = 'success',
    })
end

local function setZone()
    if not draft then
        lib.notify({ title = locale('creator_no_active'), type = 'error' })
        return
    end

    local zone = Camera.awaitZone(locale('creator_placement_zone'))
    if not zone then return end

    draft.zone = zone
    lib.notify({ title = locale('creator_zone_set'), type = 'success' })
end

local function saveGarage()
    if not draft then
        lib.notify({ title = locale('creator_no_active'), type = 'error' })
        return
    end

    if spawnCount(draft.spawns) == 0 then
        lib.notify({ title = locale('creator_no_points'), type = 'error' })
        return
    end

    if not draft.zone then
        lib.notify({ title = locale('creator_zone_missing'), type = 'error' })
        return
    end

    if draft.type == 'ipl' then
        if not draft.coords then
            lib.notify({ title = locale('creator_coords_missing'), type = 'error' })
            return
        end
        if not draft.vehicleCoords then
            lib.notify({ title = locale('creator_vehicle_coords_missing'), type = 'error' })
            return
        end
        if not (draft.entry and draft.entry.onFoot and draft.entry.vehicle) then
            lib.notify({ title = locale('creator_entry_missing'), type = 'error' })
            return
        end
    end

    if draft.fee and draft.fee > 0 and #draft.payStations == 0 then
        lib.notify({ title = locale('creator_paystation_missing'), type = 'error' })
        return
    end

    if editingIdentifier then
        local result = lib.callback.await('snowy_garages:updateGarage', false, editingIdentifier, draft)
        if result == 'notfound' then
            lib.notify({ title = locale('creator_update_not_found'), type = 'error' })
            return
        elseif result == 'spot_occupied' then
            lib.notify({ title = locale('creator_update_spot_occupied'), type = 'error' })
            return
        elseif not result then
            lib.notify({ title = locale('creator_update_failed'), type = 'error' })
            return
        end

        draft = nil
        editingIdentifier = nil
        returnFromInterior()
        lib.notify({ title = locale('creator_updated'), type = 'success' })
        return
    end

    local result = lib.callback.await('snowy_garages:createGarage', false, draft)
    if result == 'taken' then
        lib.notify({ title = locale('creator_identifier_taken'), type = 'error' })
        return
    elseif not result then
        lib.notify({ title = locale('creator_save_failed'), type = 'error' })
        return
    end

    draft = nil
    returnFromInterior()
    lib.notify({ title = locale('creator_saved'), type = 'success' })
end

local function cancelCreator()
    if not draft then return end
    draft = nil
    editingIdentifier = nil
    returnFromInterior()
    lib.notify({ title = locale('creator_cancelled'), type = 'info' })
end

local openCreatorMenu
local openPresetterMenu
local openPresetDraftMenu
local editGarageMenu
local managePointsMenu
local managePayStationsMenu
local managePresetSpotsMenu

---Converts a persisted `Garage` back into an editable `GarageDraft`. Spawns keep their
---original numeric keys (see `spawnCount`/`nextSpawnKey`) so slots already referenced by a
---stored vehicle's `garageSpotID` don't shift underneath it; pay stations aren't referenced
---by index anywhere, so they're safely flattened into a dense array.
---@param garage Garage
---@return GarageDraft
local function garageToDraft(garage)
    local spawns = {}
    for key, spawn in pairs(garage.spawns) do
        spawns[key] = { x = spawn.x, y = spawn.y, z = spawn.z, heading = spawn.heading }
    end

    local payStations = {}
    if garage.payStations then
        for _, station in pairs(garage.payStations) do
            payStations[#payStations + 1] = { x = station.x, y = station.y, z = station.z, heading = station.heading }
        end
    end

    return {
        identifier    = garage.identifier,
        label         = garage.label,
        type          = garage.type,
        company       = garage.company,
        fee           = garage.fee,
        showBlip      = garage.showBlip,
        spawns        = spawns,
        payStations   = payStations,
        coords        = { x = garage.coords.x, y = garage.coords.y, z = garage.coords.z, heading = garage.coordsHeading },
        vehicleCoords = garage.vehicleCoords
            and { x = garage.vehicleCoords.x, y = garage.vehicleCoords.y, z = garage.vehicleCoords.z + 1.0, heading = garage.vehicleCoordsHeading }
            or nil,
        entry = garage.entry,
        vehicleType = garage.vehicleType,
        zone = garage.zone,
    }
end

---@param garage Garage
local function startEditor(garage)
    draft = garageToDraft(garage)
    editingIdentifier = garage.identifier
    lib.notify({ title = locale('creator_editing_loaded'), type = 'info' })
end

local function editDraftDetails()
    if not draft then return end

    local input = lib.inputDialog(locale('creator_edit_dialog_title'), {
        { type = 'input',  label = locale('creator_field_label'), required = true, default = draft.label },
        {
            type = 'select', label = locale('creator_field_type'), required = true, default = draft.type,
            options = {
                { value = 'parking', label = locale('creator_type_parking') },
                { value = 'garage',  label = locale('creator_type_garage') },
                { value = 'ipl',     label = locale('creator_type_ipl') },
            },
        },
        { type = 'input',   label = locale('creator_field_company'), default = draft.company },
        { type = 'number',  label = locale('creator_field_fee'), default = draft.fee },
        { type = 'checkbox', label = locale('creator_field_show_blip'), default = draft.showBlip },
        {
            type = 'select', label = locale('creator_field_vehicle_type'), required = true, default = draft.vehicleType or 'any',
            options = {
                { value = 'any', label = locale('creator_vehicletype_any') },
                { value = 'car', label = locale('creator_vehicletype_car') },
                { value = 'air', label = locale('creator_vehicletype_air') },
                { value = 'boat', label = locale('creator_vehicletype_boat') },
            },
        },
    })
    if not input then return end

    draft.label    = input[1]
    draft.type     = input[2]
    draft.company  = input[3] ~= '' and input[3] or nil
    draft.fee      = tonumber(input[4])
    draft.showBlip = input[5] or false
    draft.vehicleType = input[6] ~= 'any' and input[6] or nil

    if draft.type ~= 'ipl' then
        draft.entry = nil
        draft.vehicleCoords = nil
    end

    lib.notify({ title = locale('creator_details_updated'), type = 'success' })
end

function managePointsMenu()
    if not draft then return end

    local keys = {}
    for key in pairs(draft.spawns) do keys[#keys + 1] = key end
    table.sort(keys)

    local options = {}
    for _, key in ipairs(keys) do
        local spawn = draft.spawns[key]
        options[#options + 1] = {
            title       = locale('creator_point_label'):format(key),
            description = ('%.1f, %.1f, %.1f'):format(spawn.x, spawn.y, spawn.z),
            icon        = 'trash',
            onSelect    = function()
                draft.spawns[key] = nil
                lib.notify({ title = locale('creator_point_deleted'), type = 'info' })
                managePointsMenu()
            end,
        }
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openCreatorMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_manage_points',
        title   = locale('creator_manage_points_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_manage_points')
end

function managePayStationsMenu()
    if not draft then return end

    local options = {}
    for i, station in ipairs(draft.payStations) do
        options[#options + 1] = {
            title       = locale('creator_paystation_label'):format(i),
            description = ('%.1f, %.1f, %.1f'):format(station.x, station.y, station.z),
            icon        = 'trash',
            onSelect    = function()
                table.remove(draft.payStations, i)
                lib.notify({ title = locale('creator_paystation_deleted'), type = 'info' })
                managePayStationsMenu()
            end,
        }
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openCreatorMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_manage_paystations',
        title   = locale('creator_manage_paystations_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_manage_paystations')
end

function editGarageMenu()
    local garages = GaragesApi.getGarages()

    local options = {}
    for _, garage in ipairs(garages) do
        options[#options + 1] = {
            title       = garage.label,
            description = garage.identifier,
            icon        = 'pen',
            onSelect    = function()
                startEditor(garage)
                openCreatorMenu()
            end,
        }
    end

    if #options == 0 then
        lib.notify({ title = locale('creator_no_garages'), type = 'info' })
        return
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openCreatorMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_edit_pick',
        title   = locale('creator_edit_menu_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_edit_pick')
end

local function deleteGarageMenu()
    local garages = GaragesApi.getGarages()

    local options = {}
    for _, garage in ipairs(garages) do
        options[#options + 1] = {
            title       = garage.label,
            description = garage.identifier,
            icon        = 'trash',
            onSelect    = function()
                local confirmed = lib.alertDialog({
                    header   = locale('creator_delete_confirm_title'),
                    content  = locale('creator_delete_confirm_body'):format(garage.label),
                    centered = true,
                    cancel   = true,
                })
                if confirmed ~= 'confirm' then return end

                local ok = lib.callback.await('snowy_garages:deleteGarage', false, garage.identifier)
                lib.notify({
                    title = ok and locale('creator_deleted') or locale('creator_delete_failed'),
                    type  = ok and 'success' or 'error',
                })
            end,
        }
    end

    if #options == 0 then
        lib.notify({ title = locale('creator_no_garages'), type = 'info' })
        return
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openCreatorMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_delete',
        title   = locale('creator_delete_menu_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_delete')
end

---Interior presets remember a shared interior's onFoot/vehicle arrival points (and its
---parking spots) so admins don't have to rediscover and re-place the same interior for
---every garage that reuses it - picking one here just copies its data onto the current draft.
local function selectIplPreset()
    if not draft or draft.type ~= 'ipl' then return end

    local presets = lib.callback.await('snowy_garages:getIplPresets', false)

    local options = {}
    for _, preset in ipairs(presets) do
        options[#options + 1] = {
            title       = preset.label,
            description = preset.identifier,
            icon        = 'warehouse',
            onSelect    = function()
                local playerCoords = GetEntityCoords(cache.ped)
                interiorReturnPoint = { x = playerCoords.x, y = playerCoords.y, z = playerCoords.z, heading = GetEntityHeading(cache.ped) }
                draft.entry = { onFoot = preset.entry.onFoot, vehicle = preset.entry.vehicle }

                if spawnCount(draft.spawns) == 0 and preset.spawns and #preset.spawns > 0 then
                    draft.spawns = preset.spawns
                end

                teleportTo(preset.entry.onFoot)
                openCreatorMenu()
            end,
        }
    end

    if #options == 0 then
        lib.notify({ title = locale('creator_no_presets'), type = 'error' })
        return
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openCreatorMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_presets_pick',
        title   = locale('creator_preset_pick_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_presets_pick')
end

---@type { identifier: string, label: string, onFoot: GarageSpawn?, vehicle: GarageSpawn?, spawns: GarageSpawn[] }?
local presetDraft = nil

local function startPresetDraft()
    local input = lib.inputDialog(locale('creator_preset_dialog_title'), {
        { type = 'input', label = locale('creator_preset_field_identifier'), required = true },
        { type = 'input', label = locale('creator_preset_field_label'),      required = true },
    })
    if not input then return end

    presetDraft = {
        identifier = input[1],
        label      = input[2],
        spawns     = {},
    }
end

local function setPresetOnFoot()
    if not presetDraft then
        lib.notify({ title = locale('creator_preset_no_active'), type = 'error' })
        return
    end

    local point = Camera.awaitPoint(locale('creator_placement_preset_foot'))
    if not point then return end

    presetDraft.onFoot = point
    lib.notify({ title = locale('creator_entry_set'), type = 'success' })
end

local function setPresetVehicle()
    if not presetDraft then
        lib.notify({ title = locale('creator_preset_no_active'), type = 'error' })
        return
    end

    local point = Camera.awaitPoint(locale('creator_placement_preset_vehicle'))
    if not point then return end

    presetDraft.vehicle = point
    lib.notify({ title = locale('creator_entry_set'), type = 'success' })
end

local function addPresetSpot()
    if not presetDraft then
        lib.notify({ title = locale('creator_preset_no_active'), type = 'error' })
        return
    end

    local spots = Camera.awaitParkingSpots(locale('creator_placement_point'), nil)
    if not spots then return end

    for _, spot in ipairs(spots) do
        presetDraft.spawns[#presetDraft.spawns + 1] = spot
    end

    lib.notify({
        title       = locale('creator_point_added'),
        description = locale('creator_points_added_desc'):format(#spots, #presetDraft.spawns),
        type        = 'success',
    })
end

function managePresetSpotsMenu()
    if not presetDraft then return end

    local options = {}
    for i, spawn in ipairs(presetDraft.spawns) do
        options[#options + 1] = {
            title       = locale('creator_point_label'):format(i),
            description = ('%.1f, %.1f, %.1f'):format(spawn.x, spawn.y, spawn.z),
            icon        = 'trash',
            onSelect    = function()
                table.remove(presetDraft.spawns, i)
                lib.notify({ title = locale('creator_point_deleted'), type = 'info' })
                managePresetSpotsMenu()
            end,
        }
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openPresetDraftMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_preset_manage_points',
        title   = locale('creator_manage_points_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_preset_manage_points')
end

local function savePresetDraft()
    if not presetDraft then
        lib.notify({ title = locale('creator_preset_no_active'), type = 'error' })
        return
    end

    if not (presetDraft.onFoot and presetDraft.vehicle) then
        lib.notify({ title = locale('creator_entry_missing'), type = 'error' })
        return
    end

    if #presetDraft.spawns == 0 then
        lib.notify({ title = locale('creator_no_points'), type = 'error' })
        return
    end

    local result = lib.callback.await('snowy_garages:createIplPreset', false, {
        identifier = presetDraft.identifier,
        label      = presetDraft.label,
        entry      = { onFoot = presetDraft.onFoot, vehicle = presetDraft.vehicle },
        spawns     = presetDraft.spawns,
    })

    if result == 'taken' then
        lib.notify({ title = locale('creator_preset_identifier_taken'), type = 'error' })
        return
    elseif not result then
        lib.notify({ title = locale('creator_preset_save_failed'), type = 'error' })
        return
    end

    presetDraft = nil
    lib.notify({ title = locale('creator_preset_saved'), type = 'success' })
end

local function cancelPresetDraft()
    presetDraft = nil
end

function openPresetDraftMenu()
    local options = {}

    if not presetDraft then
        options[#options + 1] = {
            title       = locale('creator_presetter_create'),
            description = locale('creator_presetter_create_desc'),
            icon        = 'plus',
            onSelect    = function()
                startPresetDraft()
                openPresetDraftMenu()
            end,
        }
    else
        options[#options + 1] = {
            title       = presetDraft.label,
            description = locale('creator_preset_draft_desc'):format(
                presetDraft.onFoot and locale('creator_yes') or locale('creator_no'),
                presetDraft.vehicle and locale('creator_yes') or locale('creator_no'),
                #presetDraft.spawns
            ),
            icon        = 'circle-info',
            disabled    = true,
        }

        options[#options + 1] = {
            title    = locale('creator_preset_set_foot'),
            icon     = 'person-walking',
            onSelect = function()
                setPresetOnFoot()
                openPresetDraftMenu()
            end,
        }

        options[#options + 1] = {
            title    = locale('creator_preset_set_vehicle'),
            icon     = 'car',
            onSelect = function()
                setPresetVehicle()
                openPresetDraftMenu()
            end,
        }

        options[#options + 1] = {
            title    = locale('creator_preset_add_point'),
            icon     = 'map-marker-alt',
            onSelect = function()
                addPresetSpot()
                openPresetDraftMenu()
            end,
        }

        if #presetDraft.spawns > 0 then
            options[#options + 1] = {
                title    = locale('creator_menu_manage_points'),
                icon     = 'list',
                onSelect = managePresetSpotsMenu,
            }
        end

        options[#options + 1] = {
            title    = locale('creator_preset_save'),
            icon     = 'floppy-disk',
            onSelect = function()
                savePresetDraft()
                openPresetDraftMenu()
            end,
        }

        options[#options + 1] = {
            title    = locale('creator_preset_cancel'),
            icon     = 'xmark',
            onSelect = function()
                cancelPresetDraft()
                openPresetDraftMenu()
            end,
        }
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openPresetterMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_preset_draft',
        title   = locale('creator_preset_menu_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_preset_draft')
end

local function deleteIplPresetMenu()
    local presets = lib.callback.await('snowy_garages:getIplPresets', false)

    local options = {}
    for _, preset in ipairs(presets) do
        options[#options + 1] = {
            title       = preset.label,
            description = preset.identifier,
            icon        = 'trash',
            onSelect    = function()
                local confirmed = lib.alertDialog({
                    header   = locale('creator_preset_delete_confirm_title'),
                    content  = locale('creator_preset_delete_confirm_body'):format(preset.label),
                    centered = true,
                    cancel   = true,
                })
                if confirmed ~= 'confirm' then return end

                local ok = lib.callback.await('snowy_garages:deleteIplPreset', false, preset.identifier)
                lib.notify({
                    title = ok and locale('creator_preset_deleted') or locale('creator_preset_delete_failed'),
                    type  = ok and 'success' or 'error',
                })
            end,
        }
    end

    if #options == 0 then
        lib.notify({ title = locale('creator_preset_no_presets'), type = 'info' })
        return
    end

    options[#options + 1] = {
        title    = locale('creator_menu_back'),
        icon     = 'arrow-left',
        onSelect = openPresetterMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_presets_delete',
        title   = locale('creator_presetter_delete_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_presets_delete')
end

function openPresetterMenu()
    lib.registerContext({
        id      = 'snowy_garages_creator_presetter',
        title   = locale('creator_presetter_title'),
        options = {
            {
                title       = locale('creator_presetter_create'),
                description = locale('creator_presetter_create_desc'),
                icon        = 'plus',
                onSelect    = function()
                    startPresetDraft()
                    openPresetDraftMenu()
                end,
            },
            {
                title    = locale('creator_presetter_delete'),
                icon     = 'trash',
                onSelect = deleteIplPresetMenu,
            },
            {
                title    = locale('creator_menu_back'),
                icon     = 'arrow-left',
                onSelect = openCreatorMenu,
            },
        },
    })
    lib.showContext('snowy_garages_creator_presetter')
end

function openCreatorMenu()
    local options = {}

    if not draft then
        options[#options + 1] = {
            title       = locale('creator_menu_start'),
            description = locale('creator_menu_start_desc'),
            icon        = 'plus',
            onSelect    = function()
                startCreator()
                openCreatorMenu()
            end,
        }

        options[#options + 1] = {
            title       = locale('creator_menu_edit'),
            description = locale('creator_menu_edit_desc'),
            icon        = 'pen',
            onSelect    = editGarageMenu,
        }
    else
        options[#options + 1] = {
            title       = draft.label,
            description = editingIdentifier
                and locale('creator_menu_draft_desc_editing'):format(editingIdentifier, draft.type, spawnCount(draft.spawns), #draft.payStations)
                or locale('creator_menu_draft_desc'):format(draft.type, spawnCount(draft.spawns), #draft.payStations),
            icon        = 'circle-info',
            disabled    = true,
        }

        options[#options + 1] = {
            title    = locale('creator_menu_edit_details'),
            icon     = 'pen-to-square',
            onSelect = function()
                editDraftDetails()
                openCreatorMenu()
            end,
        }

        options[#options + 1] = {
            title    = locale('creator_menu_add_point'),
            icon     = 'map-marker-alt',
            onSelect = function()
                addPoints()
                openCreatorMenu()
            end,
        }

        if spawnCount(draft.spawns) > 0 then
            options[#options + 1] = {
                title    = locale('creator_menu_manage_points'),
                icon     = 'list',
                onSelect = managePointsMenu,
            }
        end

        options[#options + 1] = {
            title    = locale('creator_menu_set_coords'),
            icon     = 'door-open',
            onSelect = function()
                setCoords()
                openCreatorMenu()
            end,
        }

        if draft.type == 'ipl' then
            options[#options + 1] = {
                title    = locale('creator_menu_set_vehicle_coords'),
                icon     = 'car',
                onSelect = function()
                    setVehicleCoords()
                    openCreatorMenu()
                end,
            }

            options[#options + 1] = {
                title       = locale('creator_menu_select_preset'),
                description = draft.entry and locale('creator_menu_preset_selected') or nil,
                icon        = 'warehouse',
                onSelect    = selectIplPreset,
            }

            if interiorReturnPoint then
                options[#options + 1] = {
                    title    = locale('creator_menu_return_interior'),
                    icon     = 'arrow-right-from-bracket',
                    onSelect = function()
                        returnFromInterior()
                        openCreatorMenu()
                    end,
                }
            end
        end

        options[#options + 1] = {
            title    = locale('creator_menu_add_paystation'),
            icon     = 'cash-register',
            onSelect = function()
                addPayStations()
                openCreatorMenu()
            end,
        }

        if #draft.payStations > 0 then
            options[#options + 1] = {
                title    = locale('creator_menu_manage_paystations'),
                icon     = 'list',
                onSelect = managePayStationsMenu,
            }
        end

        options[#options + 1] = {
            title       = locale('creator_menu_set_zone'),
            description = draft.zone and locale('creator_zone_set') or locale('creator_zone_missing'),
            icon        = 'draw-polygon',
            onSelect    = function()
                setZone()
                openCreatorMenu()
            end,
        }

        options[#options + 1] = {
            title    = locale('creator_menu_save'),
            icon     = 'floppy-disk',
            onSelect = function()
                saveGarage()
                openCreatorMenu()
            end,
        }

        options[#options + 1] = {
            title    = locale('creator_menu_cancel'),
            icon     = 'xmark',
            onSelect = function()
                cancelCreator()
                openCreatorMenu()
            end,
        }
    end

    options[#options + 1] = {
        title    = locale('creator_menu_manage_presets'),
        icon     = 'warehouse',
        onSelect = openPresetterMenu,
    }

    options[#options + 1] = {
        title    = locale('creator_menu_delete'),
        icon     = 'trash',
        onSelect = deleteGarageMenu,
    }

    lib.registerContext({
        id      = 'snowy_garages_creator_menu',
        title   = locale('creator_menu_title'),
        options = options,
    })
    lib.showContext('snowy_garages_creator_menu')
end

RegisterNetEvent('snowy_garages:openCreatorMenu', openCreatorMenu)
