local Config  = require "configs.shared.main"
local Bridge  = require "bridge._index"
local Vehicle = require "client.vehicle"

RegisterNetEvent('snowy_garages:startImpound', function()
    local coords  = GetEntityCoords(cache.ped)
    local nearby  = lib.getNearbyVehicles(coords, Config.interactDistance, false)
    local vehicle, ghostVehicle = nil, nil
    for _, entry in ipairs(nearby) do
        if NetworkGetEntityIsNetworked(entry.vehicle) then
            vehicle = entry.vehicle
            break
        elseif not ghostVehicle then
            ghostVehicle = entry.vehicle
        end
    end

    if vehicle then
        if not Vehicle.isEmpty(vehicle) then
            lib.notify({ title = locale('impound_occupied'), type = 'error' })
            return
        end

        local plate    = GetVehicleNumberPlateText(vehicle)
        local netId    = NetworkGetNetworkIdFromEntity(vehicle)
        local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))

        local input = lib.inputDialog(locale('impound_input_title'), {
            { type = 'number', label = locale('impound_input_fine'),     default = Config.impoundFee, min = 0 },
            { type = 'number', label = locale('impound_input_duration'), default = 0,                min = 0 },
            { type = 'input',  label = locale('impound_input_reason'),   max = 128 },
        })
        if not input then return end

        local fine     = tonumber(input[1]) or Config.impoundFee
        local lockMins = tonumber(input[2]) or 0
        local reason   = type(input[3]) == 'string' and input[3] ~= '' and input[3] or nil

        local completed = lib.progressBar({
            duration  = Config.impoundDuration * 1000,
            label     = locale('impound_progress'),
            canCancel = true,
            disable   = { move = true, car = true, combat = true },
            anim      = { dict = Config.impoundAnimDict, clip = Config.impoundAnim },
        })
        if not completed then return end

        local result = lib.callback.await('snowy_garages:impoundVehicle', false, netId, plate, maxSeats, fine, lockMins, reason)
        if result == 'occupied' then
            lib.notify({ title = locale('impound_occupied'), type = 'error' })
            return
        elseif not result then
            lib.notify({ title = locale('impound_failed'), type = 'error' })
            return
        end

        Vehicle.forceDelete(vehicle)
        lib.notify({ title = locale('impound_success'), type = 'success' })
    else
        local plate = ghostVehicle and GetVehicleNumberPlateText(ghostVehicle):match('^%s*(.-)%s*$') or nil

        local input
        if plate then
            input = lib.inputDialog(locale('impound_input_title'), {
                { type = 'number', label = locale('impound_input_fine'),     default = Config.impoundFee, min = 0 },
                { type = 'number', label = locale('impound_input_duration'), default = 0,                min = 0 },
                { type = 'input',  label = locale('impound_input_reason'),   max = 128 },
            })
            if not input then return end
        else
            input = lib.inputDialog(locale('impound_input_title'), {
                { type = 'input',  label = locale('impound_input_plate'),    max = 8, required = true },
                { type = 'number', label = locale('impound_input_fine'),     default = Config.impoundFee, min = 0 },
                { type = 'number', label = locale('impound_input_duration'), default = 0,                min = 0 },
                { type = 'input',  label = locale('impound_input_reason'),   max = 128 },
            })
            if not input then return end
            plate = type(input[1]) == 'string' and input[1]:upper():gsub('%s', '') or nil
            if not plate or plate == '' then return end
        end

        local fine, lockMins, reason
        if ghostVehicle then
            fine     = tonumber(input[1]) or Config.impoundFee
            lockMins = tonumber(input[2]) or 0
            reason   = type(input[3]) == 'string' and input[3] ~= '' and input[3] or nil
        else
            fine     = tonumber(input[2]) or Config.impoundFee
            lockMins = tonumber(input[3]) or 0
            reason   = type(input[4]) == 'string' and input[4] ~= '' and input[4] or nil
        end

        local completed = lib.progressBar({
            duration  = Config.impoundDuration * 1000,
            label     = locale('impound_progress'),
            canCancel = true,
            disable   = { move = true, car = true, combat = true },
            anim      = { dict = Config.impoundAnimDict, clip = Config.impoundAnim },
        })
        if not completed then return end

        local result = lib.callback.await('snowy_garages:impoundParkedVehicle', false, plate, fine, lockMins, reason)
        if not result then
            lib.notify({ title = locale('impound_failed'), type = 'error' })
            return
        end

        lib.notify({ title = locale('impound_success'), type = 'success' })
    end
end)

---ox_lib's lib.requestModel throws if IsModelInCdimage() rejects the hash, which misfires for
---some legitimately valid, already-streamed vehicle models (seen with certain PD models) - this
---does the actual streaming wait ourselves without that extra check.
---@param model number
---@return boolean
local function ensureModelLoaded(model)
    local ok, err = pcall(lib.requestModel, model)
    if not ok then
        debugPrint('[snowy_garages] ensureModelLoaded failed for model', model, '-', err)
        lib.notify({ title = locale('impound_model_failed'):format(tostring(err)), type = 'error' })
        return false
    end
    return true
end

---@param coords vector3
---@return boolean
local function isSpawnPointClear(coords)
    if #lib.getNearbyVehicles(coords, 3.0) > 0 then return false end
    if #lib.getNearbyPlayers(coords, 3.0, true) > 0 then return false end
    return true
end

---Resolves which configured lot a vehicle model belongs to, falling back to the lot with no
---explicit `classes` list (the catch-all) when nothing else claims that class.
---@param model number
---@return table lot
local function findLotForModel(model)
    local class = GetVehicleClassFromName(model)
    local fallback
    for _, lot in ipairs(Config.impoundLots) do
        if lot.classes then
            for _, c in ipairs(lot.classes) do
                if c == class then return lot end
            end
        elseif not fallback then
            fallback = lot
        end
    end
    return fallback or Config.impoundLots[1]
end

---@type table?
local currentLot = nil

---@type number?
local previewVehicleEntity = nil
---@type number?
local previewCam = nil

---Tears down whatever's currently being previewed, if anything - called on switching to a
---different vehicle's preview and on closing the panel entirely.
local function stopPreview()
    if previewCam then
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(previewCam, true)
        previewCam = nil
    end
    if previewVehicleEntity then
        DeleteEntity(previewVehicleEntity)
        previewVehicleEntity = nil
    end
end

---Spawns a non-networked, script-owned vehicle (never touches the server or other clients -
---same trick already used for the garage spot displays in client/spots.lua) at the lot's
---fixed preview spot and points a fixed camera at it - previously this computed a spawn/camera
---position relative to wherever the player was standing, which was unreliable (clipped into
---walls, NPCs, etc); every lot now has a known-clear preview spot in config instead.
---@param lot table
---@param plate string
---@return boolean
local function previewVehicle(lot, plate)
    local props = lib.callback.await('snowy_garages:getImpoundedVehiclePreview', false, plate)
    if not props then
        lib.notify({ title = locale('impound_preview_failed'), type = 'error' })
        return false
    end

    -- Only swap the vehicle here, not the camera - destroying/recreating the cam on every
    -- switch made it visibly swing back to the gameplay cam and then back out to the new
    -- preview each time. The cam itself is reused across previews within the same lot/panel.
    if previewVehicleEntity then
        DeleteEntity(previewVehicleEntity)
        previewVehicleEntity = nil
    end

    local spawn = lot.previewSpawn
    if not isSpawnPointClear(vector3(spawn.x, spawn.y, spawn.z)) then
        lib.notify({ title = locale('impound_spawn_blocked'), type = 'error' })
        return false
    end

    if not ensureModelLoaded(props.model) then
        lib.notify({ title = locale('impound_preview_failed'), type = 'error' })
        return false
    end
    local vehicle = CreateVehicle(props.model, spawn.x, spawn.y, spawn.z, spawn.w, false, false)
    local spawnTimeout = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < spawnTimeout do Wait(0) end
    if not DoesEntityExist(vehicle) then return false end
    SetEntityAsMissionEntity(vehicle, true, true)
    Bridge.setVehicleProperties(vehicle, props)
    Bridge.setVehicleDeformation(vehicle, props.deformation)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetEntityCollision(vehicle, false, false)
    previewVehicleEntity = vehicle

    if not previewCam then
        local camCoords = lot.previewCamCoords
        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamCoord(cam, camCoords.x, camCoords.y, camCoords.z)
        SetCamActive(cam, true)
        RenderScriptCams(true, true, 500, true, true)
        previewCam = cam
    end
    PointCamAtEntity(previewCam, vehicle, 0.0, 0.0, 0.0, true)

    return true
end

---@param lot table
---@param plate string
---@param accountType 'cash'|'bank'
---@return boolean
local function releaseVehicle(lot, plate, accountType)
    -- previewSpawn and spawnPoint are the same coords, so the preview ghost car sitting
    -- there would otherwise block its own release - tear it down before checking clearance.
    stopPreview()

    local spawn = lot.spawnPoint
    if not isSpawnPointClear(vector3(spawn.x, spawn.y, spawn.z)) then
        lib.notify({ title = locale('impound_spawn_blocked'), type = 'error' })
        return false
    end

    local props = lib.callback.await('snowy_garages:releaseImpoundedVehicle', false, plate, accountType)
    if props == 'locked' then
        lib.notify({ title = locale('impound_release_locked'), type = 'error' })
        return false
    elseif not props then
        lib.notify({ title = locale('impound_pay_failed'), type = 'error' })
        return false
    end

    if not ensureModelLoaded(props.model) then
        lib.notify({ title = locale('impound_pay_failed'), type = 'error' })
        return false
    end
    local vehicle = CreateVehicle(props.model, spawn.x, spawn.y, spawn.z, spawn.w, true, false)
    local spawnTimeout = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < spawnTimeout do Wait(0) end
    if not DoesEntityExist(vehicle) then return false end
    SetEntityAsMissionEntity(vehicle, true, true)
    Bridge.setVehicleProperties(vehicle, props)
    SetVehicleNumberPlateText(vehicle, plate)
    Bridge.setVehicleDeformation(vehicle, props.deformation)
    SetPedIntoVehicle(cache.ped, vehicle, -1)
    TriggerServerEvent('snowy_garages:giveImpoundKeys', NetworkGetNetworkIdFromEntity(vehicle), props.fuelLevel or 100.0)

    lib.notify({ title = locale('impound_paid'), type = 'success' })
    return true
end

---@param lot table
local function openImpoundMenu(lot)
    local vehicles = lib.callback.await('snowy_garages:getImpoundedVehicles', false)

    local personal, company = {}, {}
    for _, entry in ipairs(vehicles) do
        if findLotForModel(entry.model) == lot then
            local row = {
                plate     = entry.plate,
                impounded = entry.impounded,
                status    = entry.impounded and locale('impound_status_impounded') or locale('impound_status_lost'),
                locked    = entry.locked,
                lockLabel = entry.lockLabel,
                reason    = entry.reason,
                feeLabel  = entry.feeLabel,
                fine      = entry.fine,
            }
            if entry.isCompany then
                company[#company + 1] = row
            else
                personal[#personal + 1] = row
            end
        end
    end

    if #personal == 0 and #company == 0 then
        lib.notify({ title = locale('impound_nothing'), type = 'info' })
        return
    end

    currentLot = lot
    SendNUIMessage({
        action        = 'openImpound',
        title         = locale('impound_menu_title'):format(lot.label),
        personalLabel = locale('impound_section_personal'),
        companyLabel  = locale('impound_section_company'),
        releaseLabel  = locale('impound_release_action'),
        cashLabel     = locale('impound_cash'),
        bankLabel     = locale('impound_bank'),
        personal      = personal,
        company       = company,
    })
    SetNuiFocus(true, true)
end

---Guards against clicking a second vehicle before the first one's preview (an async chain of
---a server callback + model streaming) finishes - two overlapping previewVehicle calls both
---read previewVehicleEntity before either had set it, so the first one's ghost car never gets
---deleted and its spawn point stays occupied forever.
local previewBusy = false

RegisterNUICallback('impoundPreview', function(data, cb)
    if not currentLot or previewBusy then cb(false) return end
    previewBusy = true
    local ok, result = pcall(previewVehicle, currentLot, data.plate)
    previewBusy = false
    if not ok then
        lib.notify({ title = locale('impound_preview_failed'), type = 'error' })
        cb(false)
        return
    end
    cb(result)
end)

RegisterNUICallback('impoundRelease', function(data, cb)
    if not currentLot then cb(false) return end
    local ok = releaseVehicle(currentLot, data.plate, data.accountType)
    cb(ok)
end)

RegisterNUICallback('impoundClose', function(_, cb)
    stopPreview()
    SetNuiFocus(false, false)
    currentLot = nil
    cb('ok')
end)

local spawnedNpcs = {}

for _, lot in ipairs(Config.impoundLots) do
    exports.ox_target:addSphereZone({
        coords  = lot.location,
        radius  = lot.radius or Config.impoundRadius,
        options = {
            {
                name     = ('snowy_garages:releaseImpound_%s'):format(lot.id),
                icon     = 'fas fa-car-burst',
                label    = locale('impound_release_menu'),
                onSelect = function() openImpoundMenu(lot) end,
            },
        },
    })

    local blipCoords = lot.blipCoords
    local blip = AddBlipForCoord(blipCoords.x, blipCoords.y, blipCoords.z)
    SetBlipSprite(blip, 225)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.9)
    SetBlipColour(blip, 17)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(locale('impound_blip_label'):format(lot.label))
    EndTextCommandSetBlipName(blip)

    local npc = lot.npc
    lib.requestModel(npc.model)
    local ped = CreatePed(4, npc.model, npc.coords.x, npc.coords.y, npc.coords.z, npc.coords.w, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    lib.requestAnimDict(npc.animDict)
    TaskPlayAnim(ped, npc.animDict, npc.anim, 8.0, -8.0, -1, 1, 0, false, false, false)

    spawnedNpcs[#spawnedNpcs + 1] = ped
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= cache.resource then return end
    stopPreview()
    for _, ped in ipairs(spawnedNpcs) do
        DeleteEntity(ped)
    end
end)

RegisterNetEvent('snowy_garages:requestAdminCar', function()
    local vehicle = GetVehiclePedIsIn(cache.ped, false)
    if vehicle == 0 then
        lib.notify({ title = locale('impound_no_vehicle'), type = 'error' })
        return
    end
    local plate = GetVehicleNumberPlateText(vehicle):match('^%s*(.-)%s*$')
    local props = Bridge.getVehicleProperties(vehicle)
    TriggerServerEvent('snowy_garages:adminCarData', plate, props)
end)

RegisterNetEvent('snowy_garages:requestSetJobVehicle', function(job)
    local vehicle = GetVehiclePedIsIn(cache.ped, false)
    if vehicle == 0 then
        lib.notify({ title = locale('impound_no_vehicle'), type = 'error' })
        return
    end
    local plate = GetVehicleNumberPlateText(vehicle):match('^%s*(.-)%s*$')
    local modelHash = GetEntityModel(vehicle)
    local props = Bridge.getVehicleProperties(vehicle)
    TriggerServerEvent('snowy_garages:setJobVehicleData', plate, job, modelHash, props)
end)

RegisterNetEvent('snowy_garages:adminSpawnVehicle', function(props, plate)
    if not ensureModelLoaded(props.model) then
        lib.notify({ title = locale('impound_model_failed'):format(plate), type = 'error' })
        return
    end

    local spawnPos = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 5.0, 0.0)
    local heading  = GetEntityHeading(cache.ped)
    local vehicle  = CreateVehicle(props.model, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, false)
    local timeout  = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(vehicle) then
        lib.notify({ title = locale('impound_spawn_failed'):format(plate), type = 'error' })
        return
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    Bridge.setVehicleProperties(vehicle, props)
    SetVehicleNumberPlateText(vehicle, plate)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent('snowy_garages:giveImpoundKeys', netId, props.fuelLevel or 100.0)
    TriggerServerEvent('snowy_garages:vehicleSpawned', plate, netId, props.fuelLevel or 100.0)
    lib.notify({ title = locale('impound_spawned'):format(plate), type = 'success' })
end)

RegisterNetEvent('snowy_garages:teleportVehicleToMe', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        lib.notify({ title = locale('impound_not_in_world'), type = 'error' })
        return
    end
    local spawnPos = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 5.0, 0.0)
    SetEntityCoords(vehicle, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, false)
    SetEntityHeading(vehicle, GetEntityHeading(cache.ped))
    lib.notify({ title = locale('impound_teleported_to_you'), type = 'success' })
end)

RegisterNetEvent('snowy_garages:gotoVehicle', function(netId, pos)
    local coords
    if netId then
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            coords = GetEntityCoords(vehicle)
        end
    end
    if not coords and pos then
        coords = vector3(pos.x, pos.y, pos.z)
    end
    if not coords then
        lib.notify({ title = locale('impound_no_position'), type = 'error' })
        return
    end
    SetEntityCoords(cache.ped, coords.x, coords.y, coords.z + 1.0, false, false, false, false)
    lib.notify({ title = locale('impound_goto_done'), type = 'success' })
end)
