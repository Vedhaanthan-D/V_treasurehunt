-- Main client-side logic
local isHuntActive = false
local huntData = nil
local currentBlip = nil
local radiusBlip = nil
local treasureZone = nil
local inTreasureZone = false
local digSpot = nil
local spawnedBoat = nil
local treasureMarker = nil
local treasureLocation = nil
local nearTreasure = false
local hasUsedScanner = false
local hasUsedSpear = false
local hasUsedMap = false
local isDigging = false
local hasDugThisHunt = false -- Track if player has dug at least once (for stats)
local dugSpots = {} -- Track which spots have been dug (prevents re-digging same spot)
local currentDigSpotIndex = nil -- Track current dig spot being used
local currentZoneCenter = nil  -- Center of the currently active zone
local currentZoneRadius = nil  -- Radius of the currently active zone
local currentZoneIndex = 0     -- Which zone number is currently active (0 = none)
local currentZoneDugLocally = false -- True after the chest in the current zone has been opened
local lastDigDebugTime = 0 -- For debug timing
local activeDigSpotZones = {} -- Tracks registered third-eye zone names keyed by spotKey

-- Wait for player to be loaded
CreateThread(function()
    while not Bridge.IsPlayerLoaded() do
        Wait(1000)
    end
    
    -- Request hunt status from server
    TriggerServerEvent('v_treasurehunt:server:getHuntStatus')
end)

-- Start treasure hunt
RegisterNetEvent('v_treasurehunt:client:startHunt', function(data)
    if isHuntActive then return end
    
    huntData = data
    isHuntActive = true
    
    -- Spawn boat at starting location immediately (removed delays)
    SpawnTreasureBoat()
    
    -- Note: zone setup happens when player uses the treasure map
    Bridge.Notify.Info('Use the Treasure Map in your inventory to begin the hunt!')
end)

-- Setup treasure zone
function SetupTreasureZone()
    local rawCenter = currentZoneCenter or (huntData and huntData.zoneCenter)
    local zoneRadius = currentZoneRadius or (huntData and huntData.radius)
    if not rawCenter or not zoneRadius then return end
    -- Always ensure we have a proper vector3 (network events may deserialise as a table)
    local zoneCenter = vector3(rawCenter.x, rawCenter.y, rawCenter.z)
    
    -- Remove old zone first
    if treasureZone then
        if GetResourceState('ox_lib') == 'started' then
            pcall(function() treasureZone:remove() end)
        end
        treasureZone = nil
    end
    
    -- Create zone using ox_lib or fallback
    if GetResourceState('ox_lib') == 'started' and lib and lib.zones then
        treasureZone = lib.zones.sphere({
            coords = zoneCenter,
            radius = zoneRadius,
            debug = false, -- Never show visual zone in-game
            onEnter = function()
                inTreasureZone = true
                Bridge.Notify.Success(Locale.en['enter_treasure_zone'])
                TriggerEvent('v_treasurehunt:client:enteredZone')
            end,
            onExit = function()
                inTreasureZone = false
                Bridge.Notify.Info(Locale.en['leave_treasure_zone'])
                TriggerEvent('v_treasurehunt:client:exitedZone')
            end
        })
    else
        -- Fallback zone check
        local capturedCenter = zoneCenter
        local capturedRadius = zoneRadius
        CreateThread(function()
            local wasInZone = false
            while isHuntActive and currentZoneCenter == capturedCenter do
                Wait(1000)
                
                local playerCoords = GetEntityCoords(PlayerPedId())
                local distance = #(playerCoords - capturedCenter)
                local inZone = distance <= capturedRadius
                
                if inZone and not wasInZone then
                    inTreasureZone = true
                    wasInZone = true
                    Bridge.Notify.Success(Locale.en['enter_treasure_zone'])
                    TriggerEvent('v_treasurehunt:client:enteredZone')
                elseif not inZone and wasInZone then
                    inTreasureZone = false
                    wasInZone = false
                    Bridge.Notify.Info(Locale.en['leave_treasure_zone'])
                    TriggerEvent('v_treasurehunt:client:exitedZone')
                end
            end
        end)
    end
end

-- Find available boat spawn position
function FindAvailableBoatSpawn()
    local spawnPoints = Config.NPC.boatSpawnPoints or {Config.NPC.boatSpawn}
    local minDistance = 10.0 -- Increased minimum distance between boats
    local maxAttempts = 20 -- Maximum attempts to find a safe spot
    
    -- First, try configured spawn points
    for _, spawnPoint in ipairs(spawnPoints) do
        local coords = vector3(spawnPoint.x, spawnPoint.y, spawnPoint.z)
        
        if IsPositionSafeForBoat(coords, minDistance) then
            return spawnPoint
        end
    end
    
    -- If all configured spots are taken, try to find safe alternatives
    local baseSpawn = Config.NPC.boatSpawn
    local attempts = 0
    
    while attempts < maxAttempts do
        local randomOffset = math.random(8, 25) -- Increased minimum offset
        local randomAngle = math.random(0, 360)
        local rad = math.rad(randomAngle)
        
        local testCoords = vector3(
            baseSpawn.x + (randomOffset * math.cos(rad)),
            baseSpawn.y + (randomOffset * math.sin(rad)),
            baseSpawn.z
        )
        
        if IsPositionSafeForBoat(testCoords, minDistance) then
            return vector4(testCoords.x, testCoords.y, testCoords.z, baseSpawn.w)
        end
        
        attempts = attempts + 1
    end
    
    -- Last resort: use the base spawn with a large random offset
    local finalOffset = math.random(15, 30)
    local finalAngle = math.random(0, 360)
    local finalRad = math.rad(finalAngle)
    
    return vector4(
        baseSpawn.x + (finalOffset * math.cos(finalRad)),
        baseSpawn.y + (finalOffset * math.sin(finalRad)),
        baseSpawn.z,
        baseSpawn.w + math.random(-45, 45) -- Add some heading variation
    )
end

-- Check if a position is safe for boat spawning
function IsPositionSafeForBoat(coords, minDistance)
    -- Check for nearby vehicles using multiple methods for reliability
    local nearby = GetClosestVehicle(coords.x, coords.y, coords.z, minDistance, 0, 70)
    
    if nearby ~= 0 and DoesEntityExist(nearby) then
        return false
    end
    
    -- Additional check: Get all vehicles in a larger area
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distance = #(coords - vehicleCoords)
            
            if distance < minDistance then
                return false
            end
        end
    end
    
    -- Check for objects that might interfere
    local objects = GetGamePool('CObject')
    for _, object in ipairs(objects) do
        if DoesEntityExist(object) then
            local objectCoords = GetEntityCoords(object)
            local distance = #(coords - objectCoords)
            
            -- Check if it's a large object/prop that could interfere
            if distance < (minDistance * 0.5) then
                return false
            end
        end
    end
    
    return true
end

-- Spawn treasure boat
function SpawnTreasureBoat()
    -- Clean up any existing boat first
    if spawnedBoat and DoesEntityExist(spawnedBoat) then
        DeleteEntity(spawnedBoat)
        spawnedBoat = nil
        Wait(100) -- Small delay to ensure cleanup
    end
    
    -- Spawn boat at designated location from config
    local boatModel = GetHashKey('dinghy')
    RequestModel(boatModel)
    
    local timeout = 0
    while not HasModelLoaded(boatModel) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if HasModelLoaded(boatModel) then
        -- Find available spawn position with retries
        local spawnCoords = nil
        local maxRetries = 5
        local retryCount = 0
        
        while not spawnCoords and retryCount < maxRetries do
            spawnCoords = FindAvailableBoatSpawn()
            
            if spawnCoords then
                -- Double-check the position is still safe
                local testCoords = vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z)
                if not IsPositionSafeForBoat(testCoords, 8.0) then
                    spawnCoords = nil -- Force another attempt
                end
            end
            
            retryCount = retryCount + 1
            
            -- Reduced retry wait time for faster spawning
            if not spawnCoords and retryCount < maxRetries then
                Wait(50) -- Reduced from 200ms to 50ms
            end
        end
        
        if not spawnCoords then
            Bridge.Notify.Warning('Unable to find safe boat spawn location. Please try again in a moment.')
            return
        end
        
        -- Get water height at this position
        local waterHeight = GetWaterHeight(spawnCoords.x, spawnCoords.y)
        local zCoord = waterHeight and waterHeight + 0.1 or spawnCoords.z
        
        -- Create the boat
        spawnedBoat = CreateVehicle(boatModel, spawnCoords.x, spawnCoords.y, zCoord, spawnCoords.w, true, false)
        
        if DoesEntityExist(spawnedBoat) then
            -- Wait a moment for vehicle to fully spawn
            Wait(100)
            
            -- Configure boat properties safely
            local success1 = pcall(SetVehicleOnGroundProperly, spawnedBoat)
            SetEntityAsMissionEntity(spawnedBoat, true, true)
            
            local success2 = pcall(SetVehicleEngineOn, spawnedBoat, false, false, false)
            
            -- Set vehicle unlocked
            local success3 = pcall(SetVehicleDoorsLocked, spawnedBoat, 1) -- 1 = Unlocked
            
            -- Set random minor damage to make it look more authentic (optional)
            if math.random(100) < 30 then -- 30% chance
                pcall(SetVehicleBodyHealth, spawnedBoat, math.random(800, 950))
            end
            
            -- Create blip for boat
            local boatBlip = AddBlipForEntity(spawnedBoat)
            SetBlipSprite(boatBlip, 427) -- Boat icon
            SetBlipDisplay(boatBlip, 4)
            SetBlipScale(boatBlip, 0.8)
            SetBlipColour(boatBlip, 3) -- Blue
            SetBlipAsShortRange(boatBlip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Treasure Hunt Boat')
            EndTextCommandSetBlipName(boatBlip)
            
            Bridge.Notify.Success('A boat has been prepared at the dock!')
        else
            Bridge.Notify.Warning('Failed to spawn boat. Please try starting the hunt again.')
        end
    else
        Bridge.Notify.Warning('Failed to load boat model')
    end
    
    SetModelAsNoLongerNeeded(boatModel)
end

-- 3D Text Drawing Function (improved)
function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    
    if onScreen then
        local camCoords = GetGameplayCamCoord()
        local distance = #(camCoords - vector3(x, y, z))
        
        -- Enhanced visibility settings
        local scale = math.max(0.35, (1 / distance) * 2)
        local fov = (1 / GetGameplayCamFov()) * 100
        local scaleMultiplier = math.min(1.0, scale * fov * 0.7)
        
        SetTextScale(scaleMultiplier, scaleMultiplier)
        SetTextFont(0) -- Changed to font 0 for better visibility
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 255) -- Pure white text
        SetTextDropshadow(2, 2, 0, 0, 0) -- Black shadow for contrast
        SetTextOutline() -- Text outline for better readability
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
        
        -- Add a semi-transparent background for better visibility
        local textWidth = GetTextScaleWidth(text, scaleMultiplier)
        local textHeight = GetTextScaleHeight(scaleMultiplier, 0)
        DrawRect(_x, _y + (textHeight / 2), textWidth + 0.02, textHeight + 0.01, 0, 0, 0, 120)
    end
end

-- Simple screen text for debugging and fallback display
function DrawScreenText(text, x, y)
    SetTextFont(4)
    SetTextScale(0.55, 0.55) -- Slightly larger for better visibility
    
    -- Color based on text content for better UX
    if text:find('DIG HERE') or text:find('Dig Here') then
        SetTextColour(0, 255, 0, 255) -- Bright green for dig prompts
    elseif text:find('found') then
        SetTextColour(255, 255, 0, 255) -- Yellow for success messages
    else
        SetTextColour(255, 255, 255, 255) -- White for regular text
    end
    
    SetTextDropshadow(2, 2, 0, 0, 0) -- Black shadow
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- Register ox_target / qb-target zones for all undig spots in a zone
function RegisterDigSpotTargets(zone)
    if not zone or not zone.digSpots then return end
    for i, digSpotCoords in ipairs(zone.digSpots) do
        local digSpotPos = vector3(digSpotCoords.x, digSpotCoords.y, digSpotCoords.z)
        local spotKey = string.format('%.0f_%.0f_%.0f', digSpotPos.x, digSpotPos.y, digSpotPos.z)
        if not dugSpots[spotKey] and not activeDigSpotZones[spotKey] then
            local zoneName = 'digspot_' .. spotKey
            -- Capture loop vars for closure
            local capturedI = i
            local capturedPos = digSpotPos
            local capturedKey = spotKey
            local function doDigAction()
                local currentWeapon = GetSelectedPedWeapon(PlayerPedId())
                local metalDetectorHash = GetHashKey('WEAPON_METALDETECTOR')
                if currentWeapon == metalDetectorHash then
                    Bridge.Notify.Warning('Put away the metal detector to dig!')
                    return
                end
                isDigging = true
                currentDigSpotIndex = capturedI
                dugSpots[capturedKey] = true
                RemoveDigSpotTarget(capturedKey)
                if Config.Debug then
                    print(string.format('[DigSpot] Third-eye dig triggered at spot %d: %.2f,%.2f,%.2f', capturedI, capturedPos.x, capturedPos.y, capturedPos.z))
                end
                TriggerServerEvent('v_treasurehunt:server:startDigging', capturedPos)
            end
            if GetResourceState('ox_target') == 'started' then
                exports.ox_target:addSphereZone({
                    name = zoneName,
                    coords = capturedPos,
                    radius = 1.2,
                    options = {
                        {
                            name = 'dig_' .. capturedKey,
                            label = 'Dig Here',
                            icon = 'fas fa-hammer',
                            canInteract = function()
                                return isHuntActive and hasUsedMap and not isDigging and not dugSpots[capturedKey]
                            end,
                            onSelect = doDigAction
                        }
                    }
                })
                activeDigSpotZones[spotKey] = zoneName
            elseif GetResourceState('qb-target') == 'started' then
                exports['qb-target']:AddCircleZone(zoneName, capturedPos, 1.2, {
                    name = zoneName,
                    useZ = true,
                }, {
                    options = {
                        {
                            type = 'client',
                            icon = 'fas fa-hammer',
                            label = 'Dig Here',
                            canInteract = function()
                                return isHuntActive and hasUsedMap and not isDigging and not dugSpots[capturedKey]
                            end,
                            action = doDigAction
                        }
                    },
                    distance = 1.5
                })
                activeDigSpotZones[spotKey] = zoneName
            end
        end
    end
end

-- Remove a single dig spot's third-eye zone
function RemoveDigSpotTarget(spotKey)
    local zoneName = activeDigSpotZones[spotKey]
    if not zoneName then return end
    if GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeZone(zoneName) end)
    elseif GetResourceState('qb-target') == 'started' then
        pcall(function() exports['qb-target']:RemoveZone(zoneName) end)
    end
    activeDigSpotZones[spotKey] = nil
end

-- Remove all registered dig spot third-eye zones (zone change / hunt end)
function RemoveAllDigSpotTargets()
    for spotKey, _ in pairs(activeDigSpotZones) do
        RemoveDigSpotTarget(spotKey)
    end
    activeDigSpotZones = {}
end

-- Check all dig spots for proximity (updated to use actual dig spot coordinates)
function StartDigSpotDetection()
    if Config.Debug then
        print('[DigSpot] *** StartDigSpotDetection function called - dig spot detection should now work! ***')
    end
    
    CreateThread(function()
        -- Wait for Bridge system to be ready
        local maxWait = 0
        while not Bridge or not Bridge.FrameworkName do
            Wait(100)
            maxWait = maxWait + 100
            if maxWait > 10000 then -- 10 second timeout
                print('[DigSpot] Warning: Bridge system not ready after 10s, continuing anyway...')
                break
            end
        end
        
        if Config.Debug then
            print('[DigSpot] Bridge system ready, framework:', Bridge and Bridge.FrameworkName or 'unknown')
        end
        
        local useThirdEye = GetResourceState('ox_target') == 'started' or GetResourceState('qb-target') == 'started'
        local lastRegisteredZoneIndex = -1
        
        -- Main detection loop
        while isHuntActive do
            if useThirdEye then
                -- Third-eye mode: register zones when zone becomes active or changes
                Wait(200)
                if isHuntActive and hasUsedMap and currentZoneIndex > 0 and currentZoneIndex ~= lastRegisteredZoneIndex then
                    if Config.TreasureHunt.zones[currentZoneIndex] then
                        RemoveAllDigSpotTargets() -- clear previous zone's zones
                        RegisterDigSpotTargets(Config.TreasureHunt.zones[currentZoneIndex])
                        lastRegisteredZoneIndex = currentZoneIndex
                        if Config.Debug then
                            print(string.format('[DigSpot] Registered third-eye zones for zone %d', currentZoneIndex))
                        end
                    end
                end
            else
                -- Fallback: per-frame [E] key detection with 3D text
                Wait(0)
                
                -- Debug: Log detailed status every 3 seconds
                local currentTime = GetGameTimer()
                if not lastDigDebugTime or currentTime - lastDigDebugTime > 3000 then
                    if Config.Debug then
                        print(string.format('[DigSpot Debug] Active:%s, Map:%s, Digging:%s, Chest:%s, ZoneDug:%s, ZoneIdx:%d', 
                            tostring(isHuntActive), tostring(hasUsedMap), tostring(isDigging), 
                            tostring(digSpot ~= nil), tostring(currentZoneDugLocally), currentZoneIndex))
                        if currentZoneIndex > 0 and Config.TreasureHunt.zones[currentZoneIndex] then
                            local zone = Config.TreasureHunt.zones[currentZoneIndex]
                            local playerCoords = GetEntityCoords(PlayerPedId())
                            print(string.format('[DigSpot] Player at: %.2f, %.2f, %.2f', playerCoords.x, playerCoords.y, playerCoords.z))
                            if zone.digSpots then
                                print(string.format('[DigSpot] Zone %d has %d dig spots', currentZoneIndex, #zone.digSpots))
                                for i, spot in ipairs(zone.digSpots) do
                                    local dist = #(playerCoords - vector3(spot.x, spot.y, spot.z))
                                    print(string.format('[DigSpot] Spot %d at %.2f,%.2f,%.2f - Distance: %.2f', i, spot.x, spot.y, spot.z, dist))
                                end
                            end
                        end
                    end
                    lastDigDebugTime = currentTime
                end
                
                if isHuntActive and hasUsedMap and not isDigging and currentZoneIndex > 0 and not currentZoneDugLocally then
                    local playerCoords = GetEntityCoords(PlayerPedId())
                    
                    if Config.TreasureHunt.zones[currentZoneIndex] then
                        local zone = Config.TreasureHunt.zones[currentZoneIndex]
                        
                        if zone.digSpots then
                            local foundDigSpot = false
                            for i, digSpotCoords in ipairs(zone.digSpots) do
                                local digSpotPos = vector3(digSpotCoords.x, digSpotCoords.y, digSpotCoords.z)
                                local distance = #(playerCoords - digSpotPos)
                                local spotKey = string.format('%.0f_%.0f_%.0f', digSpotPos.x, digSpotPos.y, digSpotPos.z)
                                local alreadyDug = dugSpots[spotKey]
                                
                                if distance <= 2.5 and not alreadyDug then
                                    nearTreasure = true
                                    foundDigSpot = true
                                    DrawText3D(digSpotPos.x, digSpotPos.y, digSpotPos.z + 2.0, '~g~[E] ~w~Dig Here')
                                    
                                    if IsControlJustPressed(0, 38) then
                                        local currentWeapon = GetSelectedPedWeapon(PlayerPedId())
                                        local metalDetectorHash = GetHashKey('WEAPON_METALDETECTOR')
                                        if currentWeapon == metalDetectorHash then
                                            Bridge.Notify.Warning('Put away the metal detector to dig!')
                                        else
                                            isDigging = true
                                            currentDigSpotIndex = i
                                            dugSpots[spotKey] = true
                                            if Config.Debug then
                                                print(string.format('[DigSpot] Starting dig at spot %d in zone %d at coords %.2f,%.2f,%.2f', i, currentZoneIndex, digSpotPos.x, digSpotPos.y, digSpotPos.z))
                                            end
                                            TriggerServerEvent('v_treasurehunt:server:startDigging', digSpotPos)
                                        end
                                        break
                                    end
                                end
                            end
                            
                            if not foundDigSpot and nearTreasure then
                                nearTreasure = false
                            end
                        end
                    end
                else
                    Wait(100)
                    if nearTreasure then
                        nearTreasure = false
                    end
                end
            end
        end
        
        -- Hunt ended — clean up any remaining third-eye zones
        RemoveAllDigSpotTargets()
    end)
end

-- Use treasure map from inventory
RegisterNetEvent('v_treasurehunt:client:mapItemUsed', function()
    if not isHuntActive then
        Bridge.Notify.Error(Locale.en['map_no_active_hunt'])
        return
    end
    
    -- Prevent double usage
    if hasUsedMap then
        Bridge.Notify.Warning('You have already used the treasure map!')
        return
    end
    
    if radiusBlip and DoesBlipExist(radiusBlip) then
        Bridge.Notify.Warning('The search area is already revealed!')
        return
    end
    
    local playerPed = PlayerPedId()
    
    -- Request animation dict
    RequestAnimDict('amb@world_human_tourist_map@male@base')
    while not HasAnimDictLoaded('amb@world_human_tourist_map@male@base') do
        Wait(10)
    end
    
    -- Request map prop
    local mapModel = GetHashKey('prop_tourist_map_01')
    RequestModel(mapModel)
    while not HasModelLoaded(mapModel) do
        Wait(10)
    end
    
    -- Create and attach map prop
    local mapObj = CreateObject(mapModel, 0, 0, 0, true, true, true)
    AttachEntityToEntity(mapObj, playerPed, GetPedBoneIndex(playerPed, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    
    local success = lib.progressBar({
        duration = 2500,
        label = 'Reading treasure map...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        },
        anim = {
            dict = 'amb@world_human_tourist_map@male@base',
            clip = 'base'
        }
    })
    
    -- Delete map prop
    if DoesEntityExist(mapObj) then
        DeleteEntity(mapObj)
    end
    
    if not success then
        Bridge.Notify.Warning('You stopped reading the map')
        return
    end
    
    TriggerServerEvent('v_treasurehunt:server:useMap')
end)

-- Show treasure map on minimap (Zone 1)
RegisterNetEvent('v_treasurehunt:client:showMap', function(data)
    -- Remove existing blips
    if currentBlip and DoesBlipExist(currentBlip) then
        RemoveBlip(currentBlip)
    end
    if radiusBlip and DoesBlipExist(radiusBlip) then
        RemoveBlip(radiusBlip)
    end
    
    -- Store zone data (force vector3 so distance math works after network serialisation)
    currentZoneCenter = vector3(data.center.x, data.center.y, data.center.z)
    currentZoneRadius = data.radius
    currentZoneIndex = data.zoneIndex or 1
    currentZoneDugLocally = false  -- New zone, not yet dug
    
    -- Create radius blip for zone 1
    radiusBlip = AddBlipForRadius(data.center.x, data.center.y, data.center.z, data.radius)
    SetBlipColour(radiusBlip, Config.TreasureHunt.zone.blipColor)
    SetBlipAlpha(radiusBlip, Config.TreasureHunt.zone.blipAlpha)
    SetBlipAsShortRange(radiusBlip, false)
    
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(data.zoneLabel or 'Zone 1 - Treasure Zone')
    EndTextCommandSetBlipName(radiusBlip)
    
    hasUsedMap = true
    
    -- Setup the treasure zone detection
    if huntData then
        huntData.zoneCenter = data.center
        huntData.radius = data.radius
    end
    SetupTreasureZone()
    
    -- Start dig spot detection now that zone is active
    StartDigSpotDetection()
    
    Bridge.Notify.Success('Zone 1 revealed! Head to the marked area and use your metal detector to find the dig spot.')
end)

-- Reset dig state for more spots in current zone
RegisterNetEvent('v_treasurehunt:client:resetForMoreSpots', function()
    if Config.Debug then
        print('[V_treasurehunt] Resetting client state for more dig spots in same zone')
    end
    
    -- Reset digging state so player can find more spots
    digSpot = nil
    isDigging = false
    currentDigSpotIndex = nil
    currentZoneDugLocally = false  -- Allow more dig spots in this zone
    nearTreasure = false
    
    -- Clean up any text UI
    if Bridge and Bridge.Framework and Bridge.FrameworkName == 'esx' then
        pcall(function() Bridge.Framework.HideUI() end)
    elseif Bridge and Bridge.Framework and Bridge.FrameworkName == 'qbcore' then
        pcall(function() exports['qb-core']:HideText() end)
    end
end)

-- Mark zone as fully complete
RegisterNetEvent('v_treasurehunt:client:markZoneComplete', function()
    if Config.Debug then
        print('[V_treasurehunt] Marking current zone as fully complete')
    end
    
    currentZoneDugLocally = true  -- All spots in this zone are now complete
    digSpot = nil
    isDigging = false
    currentDigSpotIndex = nil
    nearTreasure = false
end)

-- Show next zone (compass reveal)
RegisterNetEvent('v_treasurehunt:client:showNextZone', function(data)
    print('[DEBUG] Received showNextZone event with data:', json.encode(data))
    
    -- Remove existing zone blip with confirmation
    if radiusBlip and DoesBlipExist(radiusBlip) then
        RemoveBlip(radiusBlip)
        radiusBlip = nil
        print('[DEBUG] Removed old radius blip')
    end
    
    -- Remove old treasure zone with proper cleanup
    if treasureZone then
        if GetResourceState('ox_lib') == 'started' then
            pcall(function() 
                treasureZone:remove() 
                print('[DEBUG] Removed old treasure zone')
            end)
        end
        treasureZone = nil
    end
    inTreasureZone = false
    
    -- Clear any existing dig spots and reset digging state immediately
    RemoveAllDigSpotTargets() -- remove old zone's third-eye targets
    dugSpots = {}
    digSpot = nil
    isDigging = false
    currentDigSpotIndex = nil
    nearTreasure = false
    
    -- Update zone data (force vector3 so distance math works after network serialisation)
    currentZoneCenter = vector3(data.center.x, data.center.y, data.center.z)
    currentZoneRadius = data.radius
    currentZoneIndex = data.zoneIndex or currentZoneIndex + 1
    currentZoneDugLocally = false  -- New zone, not yet dug
    
    Wait(100) -- Small delay to ensure proper cleanup before creating new elements
    
    -- Create new radius blip
    radiusBlip = AddBlipForRadius(data.center.x, data.center.y, data.center.z, data.radius)
    SetBlipColour(radiusBlip, Config.TreasureHunt.zone.blipColor)
    SetBlipAlpha(radiusBlip, Config.TreasureHunt.zone.blipAlpha)
    SetBlipAsShortRange(radiusBlip, false)
    
    local zoneLabel = data.zoneLabel or ('Zone ' .. currentZoneIndex)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(zoneLabel)
    EndTextCommandSetBlipName(radiusBlip)
    
    -- Update huntData zone center for zone checks
    if huntData then
        huntData.zoneCenter = data.center
        huntData.radius = data.radius
    end
    
    -- Re-setup the treasure zone
    SetupTreasureZone()
    
    -- Reset digging state for new zone
    dugSpots = {}
    digSpot = nil
    isDigging = false
    currentDigSpotIndex = nil
    nearTreasure = false
    currentZoneDugLocally = false  -- Ensure prompt reappears in new zone
    
    local msg
    if data.isFinal then
        msg = ('Final zone revealed! Head to %s - this is the last treasure location!'):format(zoneLabel)
    else
        msg = ('Zone %d revealed! Head to the marked area and dig for treasure.'):format(currentZoneIndex)
    end
    Bridge.Notify.Success(msg)
end)

-- Use spear
RegisterNetEvent('v_treasurehunt:client:useSpear', function()
    if not isHuntActive then
        Bridge.Notify.Error(Locale.en['spear_no_hunt'])
        return
    end
    
    if not inTreasureZone then
        Bridge.Notify.Warning(Locale.en['error_too_far'])
        return
    end
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    -- Play spear animation
    RequestAnimDict('weapons@first_person@aim_rng@generic@pistol@')
    while not HasAnimDictLoaded('weapons@first_person@aim_rng@generic@pistol@') do
        Wait(10)
    end
    
    TaskPlayAnim(playerPed, 'weapons@first_person@aim_rng@generic@pistol@', 'idle_2_aim_8', 8.0, 8.0, 2000, 51, 0, false, false, false)
    
    -- Send spear usage to server
    TriggerServerEvent('v_treasurehunt:server:useSpear', playerCoords)
end)

-- Use compass (reveals next zone from inventory)
RegisterNetEvent('v_treasurehunt:client:compassItemUsed', function()
    if not isHuntActive then
        Bridge.Notify.Error('You need an active treasure hunt to use the compass!')
        return
    end
    
    if not hasUsedMap then
        Bridge.Notify.Warning('Use the treasure map first!')
        return
    end
    
    local playerPed = PlayerPedId()
    
    -- Load compass prop with multiple fallbacks
    local compassModels = {
        GetHashKey('prop_cs_compass_01'),
        GetHashKey('prop_tourist_map_01'),
        GetHashKey('prop_paper_bag_small')
    }
    
    local compassModel = nil
    local compassObj = nil
    
    -- Try each model until one loads
    for _, model in ipairs(compassModels) do
        RequestModel(model)
        local timeout = 0
        while not HasModelLoaded(model) and timeout < 20 do
            Wait(50)
            timeout = timeout + 1
        end
        
        if HasModelLoaded(model) then
            compassModel = model
            break
        end
    end
    
    -- Load compass animation (navigation/compass checking animation)
    local animDict = 'amb@world_human_tourist_map@male@base'
    local animName = 'base'
    
    RequestAnimDict(animDict)
    local animTimeout = 0
    while not HasAnimDictLoaded(animDict) and animTimeout < 30 do
        Wait(50)
        animTimeout = animTimeout + 1
    end
    
    -- Fallback to clipboard animation if map animation fails
    if not HasAnimDictLoaded(animDict) then
        animDict = 'amb@world_human_clipboard@male@base'
        animName = 'base'
        RequestAnimDict(animDict)
        local fallbackTimeout = 0
        while not HasAnimDictLoaded(animDict) and fallbackTimeout < 20 do
            Wait(50)
            fallbackTimeout = fallbackTimeout + 1
        end
    end
    
    -- Create and attach compass prop
    if compassModel and HasModelLoaded(compassModel) then
        compassObj = CreateObject(compassModel, 0.0, 0.0, 0.0, true, true, true)
        if DoesEntityExist(compassObj) then
            -- Attach to right hand bone with proper positioning for compass
            AttachEntityToEntity(
                compassObj, playerPed,
                GetPedBoneIndex(playerPed, 28422), -- right hand bone
                0.08, 0.05, 0.0, -- position offset for compass
                0.0, 0.0, 180.0, -- rotation for proper compass orientation
                true, true, false, true, 1, true
            )
        end
    end
    
    print('[DEBUG] Starting compass animation with dict:', animDict, 'clip:', animName)
    
    local success = lib.progressBar({
        duration = 3000, -- Increased duration for better compass consultation feel
        label = 'Consulting the ancient compass...',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = animDict, clip = animName }
    })
    
    -- Clean up prop and animation
    ClearPedTasks(playerPed)
    if compassObj and DoesEntityExist(compassObj) then
        DeleteEntity(compassObj)
        print('[DEBUG] Cleaned up compass prop')
    end
    
    -- Clean up model
    if compassModel then
        SetModelAsNoLongerNeeded(compassModel)
    end
    
    if not success then
        Bridge.Notify.Warning('Stopped using compass.')
        return
    end
    
    print('[DEBUG] Compass consultation complete, triggeting server event...')
    TriggerServerEvent('v_treasurehunt:server:useCompass')
end)

-- Use shovel (from inventory - digging only happens via E at dig spots)
RegisterNetEvent('v_treasurehunt:client:useShovel', function()
    Bridge.Notify.Info('Go to a dig spot inside the zone and press [E] to dig.')
end)

-- Start digging process
RegisterNetEvent('v_treasurehunt:client:startDigging', function()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    isDigging = true
    hasDugThisHunt = true
    
    -- Pre-load the dig animation dict
    RequestAnimDict('amb@world_human_gardener_plant@male@base')
    while not HasAnimDictLoaded('amb@world_human_gardener_plant@male@base') do
        Wait(10)
    end

    -- Play kneeling dig animation looped indefinitely — stays crouched the whole time
    TaskPlayAnim(playerPed, 'amb@world_human_gardener_plant@male@base', 'base', 8.0, -8.0, -1, 1, 0, false, false, false)
    Wait(400) -- let blend fully settle before attaching prop

    -- Attach trowel prop to right hand (SKEL_R_Hand bone 28422)
    local digToolObj = nil
    local digToolModel = GetHashKey('prop_cs_trowel')
    RequestModel(digToolModel)
    local timeout = 0
    while not HasModelLoaded(digToolModel) and timeout < 50 do
        Wait(50)
        timeout = timeout + 1
    end
    
    if HasModelLoaded(digToolModel) then
        digToolObj = CreateObject(digToolModel, 0, 0, 0, true, true, true)
        -- Trowel properly gripped in palm with blade facing ground
        AttachEntityToEntity(digToolObj, playerPed, GetPedBoneIndex(playerPed, 57005), 0.08, 0.03, -0.02, -20.0, -90.0, 180.0, true, true, false, true, 1, true)
    end
    
    -- No anim field here — TaskPlayAnim above keeps the crouch looping uninterrupted
    local success = lib.progressBar({
        duration = Config.TreasureHunt.digTime,
        label = 'Digging for treasure...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })
    
    -- Stop animation and clean up
    ClearPedTasks(playerPed)
    
    if digToolObj and DoesEntityExist(digToolObj) then
        DeleteEntity(digToolObj)
    end
    
    if success then
        TriggerServerEvent('v_treasurehunt:server:completeDigging', playerCoords)
        -- Keep isDigging true until server responds with chest spawn or error
    else
        Bridge.Notify.Warning(Locale.en['digging_cancelled'])
        isDigging = false
        -- Clear the coordinate-based key when cancelled
        if currentDigSpotIndex and currentZoneIndex > 0 and Config.TreasureHunt.zones[currentZoneIndex] then
            local zone = Config.TreasureHunt.zones[currentZoneIndex]
            if zone.digSpots and zone.digSpots[currentDigSpotIndex] then
                local spot = zone.digSpots[currentDigSpotIndex]
                local spotKey = string.format('%.0f_%.0f_%.0f', spot.x, spot.y, spot.z)
                dugSpots[spotKey] = nil -- Allow re-digging this spot after cancellation
            end
        end
    end
end)

-- Reset digging state (called when server validation fails)
RegisterNetEvent('v_treasurehunt:client:resetDiggingState', function()
    if Config.Debug then
        print('[V_treasurehunt] Resetting digging state')
    end
    
    isDigging = false
    
    -- Clear the dug spot flag for this attempt (allow retry)
    if currentDigSpotIndex and currentZoneIndex > 0 and Config.TreasureHunt.zones[currentZoneIndex] then
        local zone = Config.TreasureHunt.zones[currentZoneIndex]
        if zone.digSpots and zone.digSpots[currentDigSpotIndex] then
            local spot = zone.digSpots[currentDigSpotIndex]
            local spotKey = string.format('%.0f_%.0f_%.0f', spot.x, spot.y, spot.z)
            dugSpots[spotKey] = nil -- Allow re-digging this spot
        end
    end
    
    currentDigSpotIndex = nil
    
    -- Also cleanup any stale chest
    if digSpot and DoesEntityExist(digSpot) then
        if Config.Debug then
            print('[V_treasurehunt] Cleaning up stale chest during state reset')
        end
        SetEntityAsMissionEntity(digSpot, true, true)
        DeleteEntity(digSpot)
        DeleteObject(digSpot)
    end
    digSpot = nil
end)

-- Spawn treasure chest
RegisterNetEvent('v_treasurehunt:client:spawnChest', function(chestCoords)
    -- Reset digging state first
    isDigging = false
    
    -- Force cleanup any existing chest before spawning new one
    if digSpot and DoesEntityExist(digSpot) then
        print('[V_treasurehunt] Cleaning up old chest before spawning new one')
        SetEntityAsMissionEntity(digSpot, true, true)
        DeleteEntity(digSpot)
        DeleteObject(digSpot)
        digSpot = nil
        Wait(200)
    end
    
    local chestModel = GetHashKey('xm_prop_x17_chest_closed')
    RequestModel(chestModel)
    
    local timeout = 0
    while not HasModelLoaded(chestModel) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(chestModel) then
        Bridge.Notify.Error('Failed to spawn treasure chest')
        return
    end
    
    -- Spawn chest exactly at the dig spot coordinates
    if Config.Debug then
        print(string.format('[V_treasurehunt] Spawning chest at: %.2f, %.2f, %.2f', chestCoords.x, chestCoords.y, chestCoords.z))
    end
    
    digSpot = CreateObject(chestModel, chestCoords.x, chestCoords.y, chestCoords.z, true, true, true)
    
    if not DoesEntityExist(digSpot) then
        Bridge.Notify.Error('Failed to create chest entity')
        return
    end
    
    PlaceObjectOnGroundProperly(digSpot)
    FreezeEntityPosition(digSpot, true)
    SetEntityHeading(digSpot, math.random(0, 360))
    
    if Config.Debug then
        print('[V_treasurehunt] Chest spawned successfully, entity ID:', digSpot)
    end
    
        -- Attach third-eye / E key interaction to chest
    AddChestTarget(digSpot)
end)

-- Add third-eye / fallback interaction target to spawned chest
function AddChestTarget(chest)
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(chest, {
            {
                name = 'treasurehunt_chest',
                label = 'Open Treasure Chest',
                icon = 'fas fa-box-open',
                distance = 3.0,
                onSelect = function()
                    OpenTreasureChest(chest)
                end
            }
        })
    elseif GetResourceState('qb-target') == 'started' then
        exports['qb-target']:AddTargetEntity(chest, {
            options = {
                {
                    type = 'client',
                    icon = 'fas fa-box-open',
                    label = 'Open Treasure Chest',
                    action = function()
                        OpenTreasureChest(chest)
                    end
                }
            },
            distance = 3.0
        })
    else
        -- Fallback: 3D text with [E] key when no third-eye resource is available
        CreateThread(function()
            while DoesEntityExist(chest) do
                Wait(0)
                local playerCoords = GetEntityCoords(PlayerPedId())
                local chestPos = GetEntityCoords(chest)
                local dist = #(playerCoords - chestPos)
                if dist <= 3.0 then
                    DrawText3D(chestPos.x, chestPos.y, chestPos.z + 0.5, '~g~[E]~w~ Open Treasure Chest')
                    if IsControlJustPressed(0, 38) then
                        OpenTreasureChest(chest)
                        break
                    end
                end
            end
        end)
    end
end

-- Open treasure chest
function OpenTreasureChest(chest)
    -- Check if chest still exists
    if not DoesEntityExist(chest) then
        Bridge.Notify.Warning('Chest no longer exists!')
        digSpot = nil
        isDigging = false
        currentDigSpotIndex = nil
        return
    end

    -- Remove third-eye target before opening
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeLocalEntity(chest, {'treasurehunt_chest'})
    elseif GetResourceState('qb-target') == 'started' then
        exports['qb-target']:RemoveTargetEntity(chest)
    end

    local playerPed = PlayerPedId()

    -- Face the chest
    TaskTurnPedToFaceEntity(playerPed, chest, 1000)
    Wait(1000)

    -- Start bin-rummage scenario (bum digging through bin — crouched search pose)
    TaskStartScenarioInPlace(playerPed, 'PROP_HUMAN_BUM_BIN', 0, true)

    -- Progress bar (no anim field — scenario keeps playing underneath)
    local success = lib.progressBar({
        duration = 7000,
        label = 'Opening treasure chest...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })

    -- Stop scenario
    ClearPedTasksImmediately(playerPed)

    if not success then
        Bridge.Notify.Warning('You stopped opening the chest')
        return
    end

    -- Save chest position before deleting
    local chestPos = GetEntityCoords(chest)

    -- Remove closed chest
    if DoesEntityExist(chest) then
        SetEntityAsMissionEntity(chest, true, true)
        DeleteEntity(chest)
        DeleteObject(chest)
    end
    digSpot = nil

    -- Spawn open chest at same position
    local openModel = GetHashKey('xm_prop_x17_chest_open')
    RequestModel(openModel)
    local t = 0
    while not HasModelLoaded(openModel) and t < 100 do
        Wait(50)
        t = t + 1
    end

    local openChest = nil
    if HasModelLoaded(openModel) then
        openChest = CreateObject(openModel, chestPos.x, chestPos.y, chestPos.z, true, true, true)
        if DoesEntityExist(openChest) then
            PlaceObjectOnGroundProperly(openChest)
            FreezeEntityPosition(openChest, true)
        end
        SetModelAsNoLongerNeeded(openModel)
    end

    -- Get fresh player coords after animation
    local playerCoords = GetEntityCoords(playerPed)

    -- Trigger server event
    TriggerServerEvent('v_treasurehunt:server:openChest', playerCoords)

    -- Reset dig state
    isDigging = false
    currentDigSpotIndex = nil
    -- currentZoneDugLocally will be set by server event if zone is complete

    -- Delete open chest after 5 seconds
    if openChest then
        CreateThread(function()
            Wait(5000)
            if DoesEntityExist(openChest) then
                SetEntityAsMissionEntity(openChest, true, true)
                DeleteEntity(openChest)
                DeleteObject(openChest)
            end
        end)
    end

    Wait(500)
end

-- Clean up hunt
RegisterNetEvent('v_treasurehunt:client:cleanupHunt', function()
    isHuntActive = false
    huntData = nil
    inTreasureZone = false
    currentZoneCenter = nil
    currentZoneRadius = nil
    currentZoneIndex = 0
    currentZoneDugLocally = false
    
    -- Remove blips
    if currentBlip and DoesBlipExist(currentBlip) then
        RemoveBlip(currentBlip)
        currentBlip = nil
    end
    if radiusBlip and DoesBlipExist(radiusBlip) then
        RemoveBlip(radiusBlip)
        radiusBlip = nil
    end
    
    -- Remove zone
    if treasureZone then
        if GetResourceState('ox_lib') == 'started' then
            treasureZone:remove()
        end
        treasureZone = nil
    end
    
    -- Remove chest
    if digSpot and DoesEntityExist(digSpot) then
        SetEntityAsMissionEntity(digSpot, true, true)
        DeleteEntity(digSpot)
        DeleteObject(digSpot)
    end
    digSpot = nil
    
    -- Remove boat with enhanced cleanup
    if spawnedBoat and DoesEntityExist(spawnedBoat) then
        -- Remove any blips attached to this boat
        local blipHandle = GetBlipFromEntity(spawnedBoat)
        if DoesBlipExist(blipHandle) then
            RemoveBlip(blipHandle)
        end
        
        -- Ensure vehicle is properly removed
        SetEntityAsMissionEntity(spawnedBoat, true, true)
        DeleteEntity(spawnedBoat)
        spawnedBoat = nil
        
        -- Small delay to ensure cleanup is processed
        Wait(100)
    end
    
    -- Remove treasure marker
    if treasureMarker and DoesBlipExist(treasureMarker) then
        RemoveBlip(treasureMarker)
        treasureMarker = nil
    end
    
    -- Reset flags
    nearTreasure = false
    hasUsedScanner = false
    hasUsedSpear = false
    hasUsedMap = false
    isDigging = false
    treasureLocation = nil
    RemoveAllDigSpotTargets() -- clean up any lingering third-eye zones
    dugSpots = {}
    activeDigSpotZones = {}
    currentDigSpotIndex = nil
    hasDugThisHunt = false -- Reset dig flag
end)

-- Handle scanner activation
RegisterNetEvent('v_treasurehunt:internal:scannerUsed', function()
    hasUsedScanner = true
end)

-- Handle spear usage confirmation
RegisterNetEvent('v_treasurehunt:internal:spearUsed', function()
    hasUsedSpear = true
end)

-- Handle hunt status response
RegisterNetEvent('v_treasurehunt:client:huntStatus', function(status)
    if status.active then
        isHuntActive = true
        huntData = {
            zoneCenter = (status.currentZoneData and status.currentZoneData.center) or Config.TreasureHunt.zones[1].center,
            radius = (status.currentZoneData and status.currentZoneData.radius) or Config.TreasureHunt.zones[1].radius,
        }
        
        -- Restore zone state if map was used
        if status.mapUsed and status.currentZone and status.currentZone > 0 then
            hasUsedMap = true
            currentZoneIndex = status.currentZone
            
            if status.currentZoneData then
                currentZoneCenter = status.currentZoneData.center
                currentZoneRadius = status.currentZoneData.radius
                huntData.zoneCenter = status.currentZoneData.center
                huntData.radius = status.currentZoneData.radius
            end
            
            -- Restore the map blip on minimap
            if not radiusBlip or not DoesBlipExist(radiusBlip) then
                if currentZoneCenter then
                    radiusBlip = AddBlipForRadius(currentZoneCenter.x, currentZoneCenter.y, currentZoneCenter.z, currentZoneRadius)
                    SetBlipColour(radiusBlip, Config.TreasureHunt.zone.blipColor)
                    SetBlipAlpha(radiusBlip, Config.TreasureHunt.zone.blipAlpha)
                    SetBlipAsShortRange(radiusBlip, false)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName(('Zone %d/%d'):format(currentZoneIndex, status.totalZones or 9))
                    EndTextCommandSetBlipName(radiusBlip)
                end
            end
            
            SetupTreasureZone()
        end
        
        -- Start dig spot detection thread
        StartDigSpotDetection()
    end
end)

-- Handle rewards received
RegisterNetEvent('v_treasurehunt:client:rewardsReceived', function(rewards, totalValue)
    TriggerServerEvent('v_treasurehunt:server:updateStats', 'huntCompleted')
    TriggerServerEvent('v_treasurehunt:server:updateStats', 'rewardValue', totalValue)
end)

-- Utility function for 3D text
function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(1)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0+0.0125, 0.017+ factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

-- Handle resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Clean up everything
        TriggerEvent('v_treasurehunt:client:cleanupHunt')
    end
end)

-- Periodic cleanup to remove abandoned boats
CreateThread(function()
    local cleanupInterval = 300000 -- 5 minutes
    while true do
        Wait(cleanupInterval)
        
        -- Check if we have an active hunt but boat got lost somehow
        if isHuntActive and (not spawnedBoat or not DoesEntityExist(spawnedBoat)) then
            print('Treasure Hunt: Boat was lost, attempting to respawn...')
            SpawnTreasureBoat()
        end
        
        -- Clean up any stray dinghies that might be treasure hunt boats
        local allVehicles = GetGamePool('CVehicle')
        local cleanupCount = 0
        
        for _, vehicle in ipairs(allVehicles) do
            if DoesEntityExist(vehicle) then
                local model = GetEntityModel(vehicle)
                if model == GetHashKey('dinghy') then
                    -- Check if it's near our spawn points and has no driver
                    local vehCoords = GetEntityCoords(vehicle)
                    local driver = GetPedInVehicleSeat(vehicle, -1)
                    
                    if driver == 0 or not DoesEntityExist(driver) then -- No driver
                        -- Check if it's near any of our spawn points
                        for _, spawnPoint in ipairs(Config.NPC.boatSpawnPoints) do
                            local spawnCoords = vector3(spawnPoint.x, spawnPoint.y, spawnPoint.z)
                            local distance = #(vehCoords - spawnCoords)
                            
                            if distance < 50.0 then -- Within 50 units of a spawn point
                                -- Check if it's been sitting there for too long without a player nearby
                                local nearbyPlayer = false
                                for _, player in ipairs(GetActivePlayers()) do
                                    local playerCoords = GetEntityCoords(GetPlayerPed(player))
                                    if #(playerCoords - vehCoords) < 20.0 then
                                        nearbyPlayer = true
                                        break
                                    end
                                end
                                
                                if not nearbyPlayer and vehicle ~= spawnedBoat then
                                    DeleteEntity(vehicle)
                                    cleanupCount = cleanupCount + 1
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
        
        if cleanupCount > 0 then
            print(string.format('Treasure Hunt: Cleaned up %d abandoned boats', cleanupCount))
        end
    end
end)

-- Export functions
exports('IsHuntActive', function()
    return isHuntActive
end)

exports('GetHuntData', function()
    return huntData
end)

exports('IsInTreasureZone', function()
    return inTreasureZone
end)

exports('IsDigging', function()
    return isDigging
end)

exports('HasUsedMap', function()
    return hasUsedMap
end)

exports('HasDigged', function()
    return hasDugThisHunt
end)

exports('GetDugSpots', function()
    return dugSpots
end)

exports('IsCurrentlyDigging', function()
    return isDigging
end)

exports('GetCurrentZoneCenter', function()
    return currentZoneCenter
end)

exports('GetCurrentZoneIndex', function()
    return currentZoneIndex
end)

exports('IsCurrentZoneDugLocally', function()
    return currentZoneDugLocally
end)

-- Item usage exports for ox_inventory
exports('treasure_map', function(event, item, inventory, slot, data)
    if not isHuntActive then
        Bridge.Notify.Error(Locale.en['map_no_active_hunt'])
        return false
    end
    
    if hasUsedMap then
        Bridge.Notify.Warning('You have already used the treasure map!')
        return false
    end
    
    -- Trigger the map usage event
    TriggerEvent('v_treasurehunt:client:mapItemUsed')
    return true
end)

exports('compass', function(event, item, inventory, slot, data)
    if not isHuntActive then
        Bridge.Notify.Error('You need an active treasure hunt to use the compass!')
        return false
    end
    
    if not hasUsedMap then
        Bridge.Notify.Warning('Use the treasure map first!')
        return false
    end
    
    -- Trigger the compass usage event
    TriggerEvent('v_treasurehunt:client:compassItemUsed')
    return true
end)

exports('garden_shovel', function(event, item, inventory, slot, data)
    -- Garden shovel is passive - just checked for possession when digging
    -- No active use needed
    Bridge.Notify.Info('The garden shovel will be used automatically when you find a dig spot!')
    return false -- Don't consume the item
end)

-- Debug: Confirm exports are registered
if Config.Debug then
    CreateThread(function()
        Wait(1000) -- Wait a moment for exports to be registered
        print('[V_treasurehunt] Main script exports registered successfully!')
        print('[V_treasurehunt] Item usage exports: treasure_map, compass, garden_shovel')
    end)
end

-- Debug command to check dig spot status
RegisterCommand('treasurehunt_debug', function()
    print('=== DEBUG INFO (Treasure Hunt) ===')
    print('- Hunt Active:', isHuntActive)
    print('- Has Used Map:', hasUsedMap)
    print('- Is Digging:', isDigging)
    print('- Dig Spot Entity Exists:', digSpot ~= nil and DoesEntityExist(digSpot))
    print('- In Treasure Zone:', inTreasureZone)
    print('- Near Treasure:', nearTreasure)
    print('- Current Zone Index:', currentZoneIndex)
    print('- Current Zone Center:', currentZoneCenter and tostring(currentZoneCenter) or 'none')
    print('- Current Zone Radius:', currentZoneRadius or 'none')
    
    if isHuntActive and Config and Config.TreasureHunt and Config.TreasureHunt.zones then
        local playerCoords = GetEntityCoords(PlayerPedId())
        print('\n=== ZONE STATUS ===')
        print('Total zones:', #Config.TreasureHunt.zones)
        print('Active zone:', currentZoneIndex .. '/' .. #Config.TreasureHunt.zones)
        
        if currentZoneCenter then
            local dist = #(playerCoords - currentZoneCenter)
            print(string.format('Distance to current zone center: %.2fm', dist))
            print('Within dig range (5m):', dist <= 5.0)
            print('Within zone radius:', currentZoneRadius and dist <= currentZoneRadius or 'N/A')
        end
    else
        print('- Hunt not active or config not loaded')
    end
    
    print('\n=== CONDITIONS CHECK ===')
    print('- hasUsedMap allows detection:', hasUsedMap)
    print('- isDigging prevents detection:', isDigging)
    print('- digSpot exists prevents detection:', digSpot ~= nil)
    print('- currentZoneCenter set:', currentZoneCenter ~= nil)
    print('- Detection should be running:', hasUsedMap and not isDigging and not digSpot and currentZoneCenter ~= nil)
end)

-- Reset command if flags get stuck
RegisterCommand('treasurehunt_reset', function()
    print('Resetting treasure hunt flags...')
    
    -- Clean up any chest entity
    if digSpot and DoesEntityExist(digSpot) then
        print('Deleting stale chest entity...')
        SetEntityAsMissionEntity(digSpot, true, true)
        DeleteEntity(digSpot)
        DeleteObject(digSpot)
    end
    
    isDigging = false
    digSpot = nil
    nearTreasure = false
    currentDigSpotIndex = nil
    
    print('Flags reset:')
    print('- isDigging:', isDigging)
    print('- digSpot:', digSpot)
    print('- nearTreasure:', nearTreasure)
    print('- currentDigSpotIndex:', currentDigSpotIndex)
    
    Bridge.Notify.Success('Treasure hunt state reset! Try finding dig spots again.')
end)

-- Test command to verify exports work
RegisterCommand('treasurehunt_test_exports', function()
    print('=== TESTING EXPORTS ===')
    
    local tests = {
        {'IsHuntActive', function() return exports['V_treasurehunt']:IsHuntActive() end},
        {'HasUsedMap', function() return exports['V_treasurehunt']:HasUsedMap() end},
        {'GetCurrentZoneIndex', function() return exports['V_treasurehunt']:GetCurrentZoneIndex() end},
        {'IsCurrentlyDigging', function() return exports['V_treasurehunt']:IsCurrentlyDigging() end}
    }
    
    for _, test in ipairs(tests) do
        local success, result = pcall(test[2])
        if success then
            print(string.format('✅ %s: %s', test[1], tostring(result)))
        else
            print(string.format('❌ %s: ERROR - %s', test[1], tostring(result)))
        end
    end
    
    print('=====================')
end, false)

-- Command to force cleanup any stuck states
RegisterCommand('treasurehunt_force_cleanup', function()
    print('[V_treasurehunt] Force cleanup initiated...')
    
    -- Reset all flags
    isDigging = false
    nearTreasure = false
    currentDigSpotIndex = nil
    dugSpots = {}
    
    -- Clean up chest
    if digSpot and DoesEntityExist(digSpot) then
        SetEntityAsMissionEntity(digSpot, true, true)
        DeleteEntity(digSpot)
        DeleteObject(digSpot)
        digSpot = nil
        print('- Cleaned up chest entity')
    end
    
    print('- Reset dig flags')
    print('- Cleared dug spots history')
    
    Bridge.Notify.Success('Treasure hunt client state cleaned up!')
end, false)