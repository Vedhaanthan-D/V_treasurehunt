-- Simplified Metal Detector System for Treasure Hunt
-- Only handles metal detector beeping - dig spot detection is in main.lua

local scannerActive = false
local lastBeepTime = 0
local lastNotifyTime = 0
local metalDetectorHash = GetHashKey('WEAPON_METALDETECTOR')

-- Initialize metal detector system  
CreateThread(function()
    Wait(3000) -- Wait for main script to load
    
    local debugTimer = 0
    
    while true do
        Wait(50) -- Faster check for better responsiveness
        
        local playerPed = PlayerPedId()
        local currentWeapon = GetSelectedPedWeapon(playerPed)
        
        -- Check if player has metal detector equipped
        if currentWeapon == metalDetectorHash then
            -- Check if player is actively using detector (right click or left click held)
            local isRightClicking = IsControlPressed(0, 25) -- Right mouse button (aim)
            local isLeftClicking = IsControlPressed(0, 24) -- Left mouse button (attack)
            local isUsingDetector = isRightClicking or isLeftClicking
            
            local currentTime = GetGameTimer()
            
            -- Debug output every 3 seconds when metal detector is equipped
            if Config.Debug and currentTime - debugTimer > 3000 then
                print(string.format('[MetalDetector] Equipped - Using: %s (R:%s L:%s)', 
                    tostring(isUsingDetector), tostring(isRightClicking), tostring(isLeftClicking)))
                debugTimer = currentTime
            end
            
            -- Get hunt status from main script
            local success1, isHuntActive = pcall(function() return exports['V_treasurehunt']:IsHuntActive() end)
            local success2, hasUsedMap = pcall(function() return exports['V_treasurehunt']:HasUsedMap() end)
            local success3, isCurrentlyDigging = pcall(function() return exports['V_treasurehunt']:IsCurrentlyDigging() end)
            local success4, isZoneDugLocally = pcall(function() return exports['V_treasurehunt']:IsCurrentZoneDugLocally() end)
            
            -- Use proper success checks and default to false if failed
            isHuntActive = success1 and isHuntActive or false
            hasUsedMap = success2 and hasUsedMap or false
            isCurrentlyDigging = success3 and isCurrentlyDigging or false
            isZoneDugLocally = success4 and isZoneDugLocally or false
            
            -- Only work if conditions are met AND detector is being actively used
            if isHuntActive and hasUsedMap and not isCurrentlyDigging and not isZoneDugLocally and isUsingDetector then
                if not scannerActive then
                    scannerActive = true
                    Bridge.Notify.Success('Metal Detector activated! Hold Right Click or Left Click and walk around.')
                    if Config.Debug then
                        print('[MetalDetector] Activated successfully!')
                    end
                end
                
                -- Get current zone and check distances to dig spots
                local playerCoords = GetEntityCoords(playerPed)
                local success5, currentZoneIndex = pcall(function() return exports['V_treasurehunt']:GetCurrentZoneIndex() end)
                currentZoneIndex = success5 and currentZoneIndex or 0
                local closestDistance = 999999.0
                
                if currentZoneIndex > 0 and Config.TreasureHunt.zones[currentZoneIndex] then
                    local zone = Config.TreasureHunt.zones[currentZoneIndex]
                    
                    -- Get info about dug spots from main script
                    local success6, dugSpotsTable = pcall(function() return exports['V_treasurehunt']:GetDugSpots() end)
                    local dugSpots = success6 and dugSpotsTable or {}
                    
                    -- Check distance to all dig spots in current zone (excluding already dug ones)
                    if zone.digSpots then
                        for _, digSpotCoords in ipairs(zone.digSpots) do
                            local digSpotPos = vector3(digSpotCoords.x, digSpotCoords.y, digSpotCoords.z)
                            
                            -- Check if this spot was already dug
                            local spotKey = string.format('%.0f_%.0f_%.0f', digSpotPos.x, digSpotPos.y, digSpotPos.z)
                            local isAlreadyDug = dugSpots[spotKey] == true
                            
                            -- Only beep for spots that haven't been dug yet
                            if not isAlreadyDug then
                                local distance = #(playerCoords - digSpotPos)
                                
                                if distance < closestDistance then
                                    closestDistance = distance
                                end
                            end
                        end
                    end
                end
                
                -- Play beep sounds based on distance
                if closestDistance <= Config.TreasureHunt.scannerDetectionRange then
                    if closestDistance <= Config.TreasureHunt.scannerBeepDistance then
                        -- Always try to beep when in range
                        PlayBeepSound(closestDistance / Config.TreasureHunt.scannerBeepDistance)
                        
                        -- Distance notifications (less frequent to avoid spam)
                        if closestDistance <= 3.0 and (not lastNotifyTime or currentTime - lastNotifyTime >= 5000) then
                            Bridge.Notify.Success('Dig spot very close! Look for the [E] prompt!')
                            lastNotifyTime = currentTime
                        elseif closestDistance <= 8.0 and (not lastNotifyTime or currentTime - lastNotifyTime >= 8000) then
                            Bridge.Notify.Info('Dig spot nearby - keep looking!')
                            lastNotifyTime = currentTime
                        end
                    end
                end
            else
                if scannerActive then
                    scannerActive = false
                    lastBeepTime = 0
                end
            end
        else
            -- Metal detector not equipped
            if scannerActive then
                scannerActive = false
                lastBeepTime = 0
            end
        end
    end
end)

-- Play beep sound based on distance
function PlayBeepSound(distanceRatio)
    local currentTime = GetGameTimer()
    -- Beep interval: closer = faster beeps (200ms min when very close, 1000ms max when far)
    local beepInterval = math.max(200, math.floor(distanceRatio * 1000))
    
    if currentTime - lastBeepTime >= beepInterval then
        -- Play loud beep sound - using multiple sounds for emphasis
        PlaySoundFrontend(-1, "BEEP_RED", "HUD_MINI_GAME_SOUNDSET", true)
        
        -- Add extra beep layer for louder effect
        PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", false)
        
        lastBeepTime = currentTime
        
        if Config.Debug and (currentTime % 2000) < 100 then
            print(string.format('[MetalDetector] BEEP - Distance ratio: %.2f, Interval: %dms', distanceRatio, beepInterval))
        end
    end
end

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        scannerActive = false
        lastBeepTime = 0
    end
end)