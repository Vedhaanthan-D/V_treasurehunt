-- Main server-side logic
local ActiveHunts = {} -- Store active treasure hunts
local PlayerCooldowns = {} -- Store player cooldowns

-- Utility function to calculate distance
local function GetDistance(coords1, coords2)
    return #(coords1 - coords2)
end

-- Utility function to get a random dig spot from the zone's dig spots
local function GetZoneDigSpot(zoneIndex)
    local zone = Config.TreasureHunt.zones[zoneIndex]
    if not zone or not zone.digSpots or #zone.digSpots == 0 then return nil end
    
    -- Select a random dig spot from the available ones
    local randomIndex = math.random(1, #zone.digSpots)
    local digSpot = zone.digSpots[randomIndex]
    return vector3(digSpot.x, digSpot.y, digSpot.z)
end

-- Helper: remove all hunt items and weapons from a player
local function RemoveHuntItems(source)
    for _, item in ipairs(Config.RequiredItems.items) do
        Bridge.RemoveItem(source, item.name, item.count)
    end
    if Config.RequiredItems.weapons then
        for _, weapon in ipairs(Config.RequiredItems.weapons) do
            Bridge.RemoveItem(source, weapon.name, 1)
        end
    end
end

-- Clean up expired hunts
local function CleanupExpiredHunts()
    local currentTime = os.time()
    for source, hunt in pairs(ActiveHunts) do
        if currentTime - hunt.startedAt > Config.TreasureHunt.huntDuration then
            RemoveHuntItems(source)
            ActiveHunts[source] = nil
            Bridge.Notify.Player(source, Locale.en['hunt_expired'], 'warning')
            
            TriggerClientEvent('v_treasurehunt:client:cleanupHunt', source)
        end
    end
end

-- Start treasure hunt
RegisterNetEvent('v_treasurehunt:server:startHunt', function()
    local source = source
    local identifier = Bridge.GetIdentifier(source)
    
    if not identifier then
        Bridge.Notify.Player(source, Locale.en['error_general'], 'error')
        return
    end
    
    -- Check if server is at capacity
    local activeCount = 0
    for _ in pairs(ActiveHunts) do
        activeCount = activeCount + 1
    end
    
    if activeCount >= Config.TreasureHunt.maxActiveHunts then
        Bridge.Notify.Player(source, Locale.en['error_server_full'], 'error')
        return
    end
    
    -- Check cooldown
    local currentTime = os.time()
    if PlayerCooldowns[identifier] and currentTime - PlayerCooldowns[identifier] < Config.TreasureHunt.cooldown then
        local remainingTime = Config.TreasureHunt.cooldown - (currentTime - PlayerCooldowns[identifier])
        local minutes = math.ceil(remainingTime / 60)
        Bridge.Notify.Player(source, Locale.en['npc_cooldown']:format(minutes), 'warning')
        return
    end
    
    -- Check if player already has active hunt
    if ActiveHunts[source] then
        Bridge.Notify.Player(source, Locale.en['npc_active_hunt'], 'warning')
        return
    end
    
    -- Check player money
    local playerMoney = Bridge.GetMoney(source, Config.RequiredItems.startCost)
    if playerMoney < Config.TreasureHunt.cost then
        Bridge.Notify.Player(source, Locale.en['npc_insufficient_funds'], 'error')
        return
    end
    
    -- Check inventory space for items (weapons don't need space check in ox_inventory)
    if Config.Debug then
        local player = Bridge.GetPlayer(source)
        if player and Bridge.FrameworkName == 'esx' then
            local weight = player.getWeight()
            local maxWeight = player.maxWeight or 'unknown'
            print(('[V_treasurehunt] Player %d weight: %s / %s'):format(source, weight, maxWeight))
        end
    end
    
    for _, item in ipairs(Config.RequiredItems.items) do
        local canCarry = Bridge.CanCarryItem(source, item.name, item.count)
        if Config.Debug then
            print(('[V_treasurehunt] Checking space for %s x%d: %s'):format(item.name, item.count, tostring(canCarry)))
        end
        
        if not canCarry then
            Bridge.Notify.Player(source, 'Not enough inventory space! Please free up space and try again.', 'error')
            if Config.Debug then
                print(('[V_treasurehunt] Player %d cannot carry %s'):format(source, item.name))
            end
            return
        end
    end
    
    -- Take money
    local success = Bridge.RemoveMoney(source, Config.TreasureHunt.cost, Config.RequiredItems.startCost, 'Treasure Hunt Start')
    if not success then
        Bridge.Notify.Player(source, Locale.en['error_general'], 'error')
        return
    end
    
    -- Give items to player
    for _, item in ipairs(Config.RequiredItems.items) do
        if Config.Debug then
            print(('[V_treasurehunt] Attempting to add item: %s x%d to player %d'):format(item.name, item.count, source))
        end
        
        local itemAdded = Bridge.AddItem(source, item.name, item.count)
        
        if Config.Debug then
            print(('[V_treasurehunt] Add item result for %s: %s'):format(item.name, tostring(itemAdded)))
        end
        
        if not itemAdded then
            Bridge.Notify.Player(source, 'Failed to receive ' .. item.name .. '. Please try again or contact an admin.', 'error')
            
            -- Refund the money if item addition fails
            Bridge.AddMoney(source, Config.TreasureHunt.cost, Config.RequiredItems.startCost, 'Treasure Hunt Refund')
            
            -- Remove any items that were successfully added
            for i = 1, _ - 1 do
                local prevItem = Config.RequiredItems.items[i]
                Bridge.RemoveItem(source, prevItem.name, prevItem.count)
            end
            
            return
        end
    end
    
    -- Give weapons to player
    if Config.RequiredItems.weapons then
        for _, weapon in ipairs(Config.RequiredItems.weapons) do
            if Config.Debug then
                print(('[V_treasurehunt] Attempting to add weapon: %s to player %d'):format(weapon.name, source))
            end
            
            local weaponAdded = Bridge.AddItem(source, weapon.name, 1)
            
            if Config.Debug then
                print(('[V_treasurehunt] Add weapon result for %s: %s'):format(weapon.name, tostring(weaponAdded)))
            end
            
            if not weaponAdded then
                Bridge.Notify.Player(source, 'Failed to receive ' .. weapon.name .. '. Please try again or contact an admin.', 'error')
                
                -- Refund and cleanup
                Bridge.AddMoney(source, Config.TreasureHunt.cost, Config.RequiredItems.startCost, 'Treasure Hunt Refund')
                
                for _, item in ipairs(Config.RequiredItems.items) do
                    Bridge.RemoveItem(source, item.name, item.count)
                end
                
                return
            end
        end
    end
    
    -- Create hunt session
    ActiveHunts[source] = {
        identifier = identifier,
        currentZone = 0,  -- 0 = map not used yet; 1-N = active zone index
        zoneDug = false,  -- whether current zone's chest was opened
        digLocation = nil,
        startedAt = currentTime,
        stage = 1,
        mapUsed = false,
        dugSpotsInZone = {}  -- Track which dig spots have been completed in current zone
    }
    
    -- Set cooldown
    PlayerCooldowns[identifier] = currentTime
    
    -- Notify player
    Bridge.Notify.Player(source, Locale.en['npc_hunt_started'], 'success')
    
    -- Trigger client to setup hunt (no zone data yet - player must use the treasure map)
    TriggerClientEvent('v_treasurehunt:client:startHunt', source, {})
    
end)

-- Use treasure map
RegisterNetEvent('v_treasurehunt:server:useMap', function()
    local source = source
    local hunt = ActiveHunts[source]
    
    if not hunt then
        Bridge.Notify.Player(source, Locale.en['map_no_active_hunt'], 'error')
        return
    end
    
    -- Check if map was already used
    if hunt.mapUsed then
        Bridge.Notify.Player(source, 'You have already used the treasure map for this hunt!', 'warning')
        return
    end
    
    -- Check if player has the map
    if Bridge.GetItemCount(source, 'treasure_map') < 1 then
        Bridge.Notify.Player(source, Locale.en['error_no_items'], 'error')
        return
    end
    
    -- Remove the treasure map from inventory
    local mapRemoved = Bridge.RemoveItem(source, 'treasure_map', 1)
    if not mapRemoved then
        Bridge.Notify.Player(source, 'Failed to use map', 'error')
        return
    end
    
    -- Mark map as used and activate zone 1
    hunt.mapUsed = true
    hunt.currentZone = 1
    hunt.zoneDug = false
    hunt.dugSpotsInZone = {}  -- Reset dug spots for new zone
    hunt.digLocation = GetZoneDigSpot(1) -- Select random dig spot for Zone 1
    
    local zone = Config.TreasureHunt.zones[1]
    -- Send zone 1 data to client
    TriggerClientEvent('v_treasurehunt:client:showMap', source, {
        center = zone.center,
        radius = zone.radius,
        zoneLabel = zone.label,
        zoneIndex = 1
    })
    
    Bridge.Notify.Player(source, Locale.en['map_used'], 'info')
end)

-- Use compass (reveals next zone without removing compass)
RegisterNetEvent('v_treasurehunt:server:useCompass', function()
    local source = source
    local hunt = ActiveHunts[source]
    
    print('[DEBUG] Compass event received from player', source)
    
    if not hunt then
        print('[DEBUG] No active hunt for player', source)
        Bridge.Notify.Player(source, Locale.en['map_no_active_hunt'], 'error')
        return
    end
    
    print('[DEBUG] Hunt state - mapUsed:', hunt.mapUsed, 'zoneDug:', hunt.zoneDug, 'currentZone:', hunt.currentZone)
    
    if not hunt.mapUsed then
        Bridge.Notify.Player(source, 'Use the treasure map first!', 'warning')
        return
    end
    
    -- All zones require completion before using compass
    if hunt.currentZone < 1 then
        Bridge.Notify.Player(source, 'Complete Zone 1 first!', 'warning')
        return
    end
    
    -- Check if all dig spots in current zone have been completed
    local currentZone = Config.TreasureHunt.zones[hunt.currentZone]
    local totalDigSpots = currentZone and currentZone.digSpots and #currentZone.digSpots or 0
    local dugCount = 0
    for _ in pairs(hunt.dugSpotsInZone) do
        dugCount = dugCount + 1
    end
    
    if dugCount < totalDigSpots then
        Bridge.Notify.Player(source, string.format('You need to dig ALL spots in this zone first! (%d/%d dug)', dugCount, totalDigSpots), 'warning')
        return
    end
    
    local nextZone = hunt.currentZone + 1
    if nextZone > #Config.TreasureHunt.zones then
        Bridge.Notify.Player(source, 'The hunt is already complete!', 'info')
        return
    end
    
    -- Check player has compass
    if Bridge.GetItemCount(source, 'compass') < 1 then
        Bridge.Notify.Player(source, Locale.en['error_no_items'], 'error')
        return
    end
    
    -- Advance to next zone (compass is NOT removed)
    hunt.currentZone = nextZone
    hunt.zoneDug = false
    hunt.dugSpotsInZone = {}  -- Reset dug spots for new zone
    hunt.digLocation = GetZoneDigSpot(nextZone) -- Select random dig spot
    hunt.stage = 1
    hunt.dugThisRound = false
    
    local zone = Config.TreasureHunt.zones[nextZone]
    print('[DEBUG] Sending showNextZone event for zone', nextZone, 'center:', zone.center.x, zone.center.y, zone.center.z)
    
    TriggerClientEvent('v_treasurehunt:client:showNextZone', source, {
        center = zone.center,
        radius = zone.radius,
        zoneLabel = zone.label,
        zoneIndex = nextZone,
        isFinal = (nextZone >= #Config.TreasureHunt.zones)
    })
    
    print('[DEBUG] Compass event completed successfully')
    Bridge.Notify.Player(source, ('Zone %d/%d revealed! Head to the marked area and dig.'):format(nextZone, #Config.TreasureHunt.zones), 'success')
end)

-- Use spear
RegisterNetEvent('v_treasurehunt:server:useSpear', function(playerCoords)
    local source = source
    local hunt = ActiveHunts[source]
    
    if not hunt then
        Bridge.Notify.Player(source, Locale.en['spear_no_hunt'], 'error')
        return
    end
    
    -- Check if player has the spear
    if Bridge.GetItemCount(source, 'spear') < 1 then
        Bridge.Notify.Player(source, Locale.en['error_no_items'], 'error')
        return
    end
    
    -- Validate player position (anti-cheat)
    local currentZoneData = Config.TreasureHunt.zones[hunt.currentZone or 1]
    local zoneCenter = currentZoneData and vector3(currentZoneData.center.x, currentZoneData.center.y, currentZoneData.center.z) or vector3(0,0,0)
    if GetDistance(vector3(playerCoords.x, playerCoords.y, playerCoords.z), zoneCenter) > Config.TreasureHunt.maxDistance then
        Bridge.Notify.Player(source, Locale.en['error_too_far'], 'error')
        return
    end
    
    -- Calculate distance to treasure
    local distance = GetDistance(vector3(playerCoords.x, playerCoords.y, playerCoords.z), hunt.digLocation)
    
    local message = Locale.en['spear_cold']
    if distance <= Config.TreasureHunt.spearRadius then
        message = Locale.en['spear_hot']
        hunt.stage = 2 -- Player found the spot, advance to digging stage
        -- Notify client that spear was successfully used
        TriggerClientEvent('v_treasurehunt:client:spearSuccess', source)
    elseif distance <= Config.TreasureHunt.spearRadius * 2 then
        message = Locale.en['spear_warm']
    end
    
    Bridge.Notify.Player(source, message, 'info')
    
end)

-- Start digging
RegisterNetEvent('v_treasurehunt:server:startDigging', function(playerCoords)
    local source = source
    local hunt = ActiveHunts[source]
    
    if not hunt then
        Bridge.Notify.Player(source, Locale.en['error_invalid_session'], 'error')
        return
    end
    
    -- Check if already dug
    if hunt.dugThisRound then
        Bridge.Notify.Player(source, 'You are already digging!', 'warning')
        return
    end
    
    -- Check if player has the garden shovel
    if Bridge.GetItemCount(source, 'garden_shovel') < 1 then
        Bridge.Notify.Player(source, Locale.en['error_no_items'], 'error')
        return
    end
    
    -- Check hunt has an active zone (map must have been used)
    if hunt.currentZone < 1 or not Config.TreasureHunt.zones[hunt.currentZone] then
        Bridge.Notify.Player(source, 'Use the treasure map first to find a dig zone!', 'error')
        return
    end
    
    -- Check zone hasn't already been dug this round
    if hunt.zoneDug then
        Bridge.Notify.Player(source, 'You already opened the chest here! Use your compass to find the next zone.', 'warning')
        return
    end
    
    -- Check player is within the current zone's radius
    local zone = Config.TreasureHunt.zones[hunt.currentZone]
    local zoneCenter = vector3(zone.center.x, zone.center.y, zone.center.z)
    local distToZoneCenter = GetDistance(vector3(playerCoords.x, playerCoords.y, playerCoords.z), zoneCenter)
    
    if distToZoneCenter > zone.radius then
        Bridge.Notify.Player(source, ('You need to be inside %s to dig!'):format(zone.label), 'error')
        return
    end
    
    -- Validate player is at an actual dig spot
    local digSpotFound = false
    local actualDigSpot = nil
    local digSpotIndex = nil
    
    if zone.digSpots then
        for i, digSpot in ipairs(zone.digSpots) do
            local digSpotPos = vector3(digSpot.x, digSpot.y, digSpot.z)
            local distToDigSpot = GetDistance(vector3(playerCoords.x, playerCoords.y, playerCoords.z), digSpotPos)
            
            if distToDigSpot <= 5.0 then -- Within 5m of dig spot
                -- Check if this specific dig spot was already dug
                local spotKey = string.format('%.0f_%.0f_%.0f', digSpotPos.x, digSpotPos.y, digSpotPos.z)
                if hunt.dugSpotsInZone[spotKey] then
                    Bridge.Notify.Player(source, 'This dig spot has already been used!', 'warning')
                    return
                end
                
                digSpotFound = true
                actualDigSpot = digSpotPos
                digSpotIndex = i
                break
            end
        end
    end
    
    if not digSpotFound then
        Bridge.Notify.Player(source, 'You need to be at a dig spot! Use your metal detector to find one.', 'error')
        return
    end
    
    -- Set the dig location to the ACTUAL dig spot, not zone center
    hunt.digLocation = actualDigSpot
    hunt.currentDigSpotIndex = digSpotIndex
    
    -- Allow digging
    hunt.stage = 3
    hunt.dugThisRound = true
    TriggerClientEvent('v_treasurehunt:client:startDigging', source)
end)

-- Complete digging
RegisterNetEvent('v_treasurehunt:server:completeDigging', function(playerCoords)
    local source = source
    local hunt = ActiveHunts[source]
    
    if not hunt or hunt.stage < 3 then
        Bridge.Notify.Player(source, Locale.en['error_invalid_session'], 'error')
        return
    end
    
    -- Final validation (use smaller distance since we have exact dig spot)
    local distance = GetDistance(vector3(playerCoords.x, playerCoords.y, playerCoords.z), hunt.digLocation)
    if distance > 5.0 then -- Reduced from 10.0 to 5.0 for precision
        Bridge.Notify.Player(source, 'You moved too far from the dig spot!', 'error')
        -- Reset state so player can try again at correct location
        hunt.stage = 2
        hunt.dugThisRound = false
        TriggerClientEvent('v_treasurehunt:client:resetDiggingState', source)
        return
    end
    
    -- Spawn treasure chest for client at exact dig location
    hunt.stage = 4
    -- DON'T reset dugThisRound here - let it stay true until chest is opened
    TriggerClientEvent('v_treasurehunt:client:spawnChest', source, hunt.digLocation)
    Bridge.Notify.Player(source, Locale.en['treasure_found'], 'success')
end)

-- Open treasure chest
RegisterNetEvent('v_treasurehunt:server:openChest', function(playerCoords)
    local source = source
    local hunt = ActiveHunts[source]
    
    if not hunt or hunt.stage < 4 then
        Bridge.Notify.Player(source, Locale.en['error_invalid_session'], 'error')
        return
    end
    
    -- Final position check
    local distance = GetDistance(vector3(playerCoords.x, playerCoords.y, playerCoords.z), hunt.digLocation)
    if distance > Config.TreasureHunt.spearRadius then
        Bridge.Notify.Player(source, Locale.en['error_too_far'], 'error')
        return
    end
    
    -- Generate rewards
    local rewards = {}
    local totalWeight = 0
    
    -- Calculate total weight
    for _, item in ipairs(Config.Rewards.items) do
        totalWeight = totalWeight + item.weight
    end
    
    -- Determine number of rewards to give
    local numRewards = math.random(Config.Rewards.minRewards, Config.Rewards.maxRewards)
    local selectedItems = {}
    
    for i = 1, numRewards do
        local randomWeight = math.random(1, totalWeight)
        local currentWeight = 0
        
        -- Find the selected item based on weight
        for _, item in ipairs(Config.Rewards.items) do
            currentWeight = currentWeight + item.weight
            if randomWeight <= currentWeight then
                -- Check if this item was already selected (avoid duplicates)
                local found = false
                for _, selected in ipairs(selectedItems) do
                    if selected == item.name then
                        found = true
                        break
                    end
                end
                
                if not found then
                    local count = math.random(item.min, item.max)
                    table.insert(selectedItems, item.name)
                    table.insert(rewards, {
                        item = item.name,
                        count = count
                    })
                end
                break
            end
        end
    end
    
    -- Give all rewards to player
    local successCount = 0
    for _, reward in ipairs(rewards) do
        -- Check if player can carry item
        if Bridge.CanCarryItem(source, reward.item, reward.count) then
            local itemGiven = Bridge.AddItem(source, reward.item, reward.count, {
                description = 'Found during treasure hunt',
                quality = 100
            })
            
            if itemGiven then
                successCount = successCount + 1
                local itemLabel = reward.item:gsub('_', ' '):gsub("(%a)([%w_]*)", function(a, b) return a:upper()..b end)
                Bridge.Notify.Player(source, ('You received %s x%s!'):format(itemLabel, reward.count), 'success')
            else
                Bridge.Notify.Player(source, ('Failed to receive %s'):format(reward.item), 'error')
            end
        else
            Bridge.Notify.Player(source, ('Not enough space for %s'):format(reward.item), 'error')
        end
    end
    
    -- Mark this specific dig spot as completed
    local spotKey = string.format('%.0f_%.0f_%.0f', hunt.digLocation.x, hunt.digLocation.y, hunt.digLocation.z)
    hunt.dugSpotsInZone[spotKey] = true
    hunt.dugThisRound = false
    
    -- Check if all dig spots in current zone have been completed
    local currentZone = Config.TreasureHunt.zones[hunt.currentZone]
    local totalDigSpots = currentZone and currentZone.digSpots and #currentZone.digSpots or 0
    local dugCount = 0
    for _ in pairs(hunt.dugSpotsInZone) do
        dugCount = dugCount + 1
    end
    
    local allSpotsCompleted = (dugCount >= totalDigSpots)
    
    if not allSpotsCompleted then
        -- More dig spots remain in this zone
        Bridge.Notify.Player(source, string.format('Dig spot complete! Find the remaining spots in this zone (%d/%d complete)', dugCount, totalDigSpots), 'success')
        Bridge.Notify.Player(source, 'Use your metal detector to find more dig spots in this zone!', 'info')
        hunt.stage = 1  -- Reset stage to allow more digging
        
        -- Tell client to reset state for more spots (don't mark zone complete yet)
        TriggerClientEvent('v_treasurehunt:client:resetForMoreSpots', source)
        return
    end
    
    -- All spots in zone completed - mark zone as fully dug
    hunt.zoneDug = true
    
    -- Tell client that this zone is now fully complete
    TriggerClientEvent('v_treasurehunt:client:markZoneComplete', source)
    
    if hunt.currentZone >= #Config.TreasureHunt.zones then
        -- This was the final zone - end the hunt
        RemoveHuntItems(source)
        ActiveHunts[source] = nil
        Bridge.Notify.Player(source, 'Congratulations! You have completed the entire treasure hunt!', 'success')
        TriggerClientEvent('v_treasurehunt:client:cleanupHunt', source)
    else
        -- All zones (including Zone 1) require compass usage for next zone
        hunt.stage = 2
        Bridge.Notify.Player(source, string.format('Zone %d/%d fully complete! All %d dig spots found.', hunt.currentZone, #Config.TreasureHunt.zones, totalDigSpots), 'success')
        Bridge.Notify.Player(source, 'Use your compass to reveal the next zone.', 'info')
    end
end)

-- Cancel hunt
RegisterNetEvent('v_treasurehunt:server:cancelHunt', function()
    local source = source
    local hunt = ActiveHunts[source]
    
    if not hunt then
        return
    end
    
    -- Remove all hunt items and weapons (including metal detector)
    RemoveHuntItems(source)
    
    ActiveHunts[source] = nil
    Bridge.Notify.Player(source, Locale.en['hunt_cancelled'], 'info')
    
    TriggerClientEvent('v_treasurehunt:client:cleanupHunt', source)
end)

-- Check hunt status (for client)
RegisterNetEvent('v_treasurehunt:server:getHuntStatus', function()
    local source = source
    local hunt = ActiveHunts[source]
    
    if hunt then
        local timeRemaining = Config.TreasureHunt.huntDuration - (os.time() - hunt.startedAt)
        local currentZoneData = nil
        if hunt.currentZone > 0 and Config.TreasureHunt.zones[hunt.currentZone] then
            local z = Config.TreasureHunt.zones[hunt.currentZone]
            currentZoneData = { center = z.center, radius = z.radius, label = z.label }
        end
        TriggerClientEvent('v_treasurehunt:client:huntStatus', source, {
            active = true,
            stage = hunt.stage,
            mapUsed = hunt.mapUsed,
            timeRemaining = timeRemaining,
            currentZone = hunt.currentZone,
            zoneDug = hunt.zoneDug,
            currentZoneData = currentZoneData,
            totalZones = #Config.TreasureHunt.zones
        })
    else
        TriggerClientEvent('v_treasurehunt:client:huntStatus', source, { active = false })
    end
end)

-- Handle player disconnect
AddEventHandler('playerDropped', function(reason)
    local source = source
    if ActiveHunts[source] then
        ActiveHunts[source] = nil
    end
end)

-- Periodic cleanup
CreateThread(function()
    while true do
        Wait(Config.Performance.cleanupInterval)
        CleanupExpiredHunts()
    end
end)

-- Export functions for other scripts
exports('GetActiveHunts', function()
    return ActiveHunts
end)

exports('GetPlayerHunt', function(source)
    return ActiveHunts[source]
end)

exports('CancelPlayerHunt', function(source)
    if ActiveHunts[source] then
        TriggerEvent('v_treasurehunt:server:cancelHunt', source)
        return true
    end
    return false
end)