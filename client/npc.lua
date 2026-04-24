-- NPC management for treasure hunt starting point
local startingNPC = nil
local npcBlip = nil
local isSpawning = false
local hasInitialSpawnCompleted = false

-- Wait for player to be loaded
CreateThread(function()
    -- Simple wait for player to spawn
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(100)
    end
    
    -- Check if Config is loaded
    if not Config or not Config.NPC then
        print('[V_treasurehunt] ERROR: Config or Config.NPC not loaded!')
        return
    end
    
    if Config.Debug then
        print('[V_treasurehunt] NPC initialization starting...')
        print('- Config loaded:', Config ~= nil)
        print('- NPC config loaded:', Config.NPC ~= nil)
        print('- NPC model:', Config.NPC and Config.NPC.model or 'unknown')
        print('- NPC coords:', Config.NPC and Config.NPC.coords or 'unknown')
    end
    
    -- Wait for main script exports to be ready
    local maxWait = 0
    while maxWait < 30000 do -- 30 second timeout
        local success = pcall(function()
            return exports['V_treasurehunt']:IsHuntActive()
        end)
        
        if success then
            if Config.Debug then
                print('[V_treasurehunt] NPC: Main script exports are ready!')
            end
            break
        end
        
        Wait(500)
        maxWait = maxWait + 500
    end
    
    if maxWait >= 30000 then
        print('[V_treasurehunt] Warning: NPC script timeout waiting for main script exports')
    end
    
    -- Additional wait to ensure everything is ready
    Wait(1000)
    
    -- Spawn NPC immediately after player loads (priority)
    SpawnStartingNPC()
    hasInitialSpawnCompleted = true
    
    if Config.Debug then
        print('[V_treasurehunt] NPC initialization complete')
    end
end)

-- Spawn the starting NPC
function SpawnStartingNPC()
    if Config.Debug then
        print('[V_treasurehunt] SpawnStartingNPC called')
    end
    
    -- Prevent multiple simultaneous spawns
    if isSpawning then
        if Config.Debug then
            print('[V_treasurehunt] NPC spawn already in progress, skipping...')
        end
        return
    end
    
    -- Check if NPC already exists and is valid
    if startingNPC and DoesEntityExist(startingNPC) then
        if Config.Debug then
            print('[V_treasurehunt] NPC already exists, skipping spawn...')
        end
        return
    end
    
    isSpawning = true
    
    if Config.Debug then
        print('[V_treasurehunt] Starting NPC spawn process...')
        print('- Model:', Config.NPC.model)
        print('- Coords:', Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
    end
    
    local npcModel = GetHashKey(Config.NPC.model)
    
    -- Request model with retries (streaming can be slow after server restart)
    local modelLoaded = false
    local maxRetries = 5
    
    for retry = 1, maxRetries do
        RequestModel(npcModel)
        local attempts = 0
        while not HasModelLoaded(npcModel) and attempts < 200 do
            Wait(100) -- 100ms per tick = up to 20 seconds per attempt
            attempts = attempts + 1
        end
        
        if HasModelLoaded(npcModel) then
            modelLoaded = true
            if Config.Debug then
                print(string.format('[V_treasurehunt] NPC model loaded on attempt %d/%d', retry, maxRetries))
            end
            break
        end
        
        print(string.format('[V_treasurehunt] Model load attempt %d/%d failed for %s, retrying in 3s...', retry, maxRetries, Config.NPC.model))
        Wait(3000)
    end
    
    if not modelLoaded then
        print('[V_treasurehunt] ERROR: Failed to load NPC model after ' .. maxRetries .. ' attempts: ' .. Config.NPC.model)
        isSpawning = false
        return
    end
    
    if Config.Debug then
        print('[V_treasurehunt] NPC model loaded, creating ped...')
    end
    
    -- Spawn NPC
    startingNPC = CreatePed(4, npcModel, Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z - 1.0, Config.NPC.coords.w, false, true)
    
    if not DoesEntityExist(startingNPC) then
        print('[V_treasurehunt] ERROR: Failed to create NPC entity!')
        isSpawning = false
        return
    end
    
    if Config.Debug then
        print('[V_treasurehunt] NPC entity created, configuring...')
    end
    
    -- Configure NPC
    SetEntityAsMissionEntity(startingNPC, true, true)
    SetPedCanRagdoll(startingNPC, false)
    SetEntityInvincible(startingNPC, Config.NPC.invincible)
    FreezeEntityPosition(startingNPC, Config.NPC.frozen)
    SetBlockingOfNonTemporaryEvents(startingNPC, Config.NPC.blockEvents)
    
    -- NPC stands still
    TaskStandStill(startingNPC, -1)
    
    -- Add blip
    CreateNPCBlip()
    
    -- Add target interaction
    AddNPCTarget()
    
    isSpawning = false
    
    if Config.Debug then
        print('[V_treasurehunt] Starting NPC spawned successfully! Entity ID:', startingNPC)
    end
end

-- Idle animation loop for NPC: alternates between reading a map and smoking
-- Helper: load a model and return the hash, or nil on failure
local function LoadPropModel(modelHash)
    RequestModel(modelHash)
    local t = 0
    while not HasModelLoaded(modelHash) and t < 50 do
        Wait(100)
        t = t + 1
    end
    return HasModelLoaded(modelHash) and modelHash or nil
end

-- Helper: safely delete a prop entity
local function DeleteProp(propObj)
    if propObj and DoesEntityExist(propObj) then
        DetachEntity(propObj, true, true)
        SetEntityAsMissionEntity(propObj, true, true)
        DeleteEntity(propObj)
        DeleteObject(propObj)
    end
end

function StartNPCAnimation(npc)
    -- unused: NPC stands still
end

-- Create blip for NPC
function CreateNPCBlip()
    if Config.Debug then
        print('[V_treasurehunt] Creating NPC blip...')
    end
    
    if npcBlip and DoesBlipExist(npcBlip) then
        RemoveBlip(npcBlip)
    end
    
    if not DoesEntityExist(startingNPC) then
        print('[V_treasurehunt] ERROR: Cannot create blip, NPC entity does not exist!')
        return
    end
    
    npcBlip = AddBlipForEntity(startingNPC)
    SetBlipSprite(npcBlip, 280) -- Treasure map icon
    SetBlipDisplay(npcBlip, 4)
    SetBlipScale(npcBlip, 1.0)
    SetBlipColour(npcBlip, 5) -- Yellow
    SetBlipAsShortRange(npcBlip, false) -- Show on minimap and full map
    
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Treasure Hunter')
    EndTextCommandSetBlipName(npcBlip)
    
    if Config.Debug then
        print('[V_treasurehunt] NPC blip created successfully! Blip ID:', npcBlip)
    end
end

-- Add target interaction to NPC
function AddNPCTarget()
    if not DoesEntityExist(startingNPC) then
        print('[V_treasurehunt] ERROR: Cannot add target, NPC entity does not exist!')
        return
    end
    
    if Config.Debug then
        print('[V_treasurehunt] Adding target interaction to NPC...')
        print('- NPC Entity ID:', startingNPC)
    end
    
    -- Check for ox_target first (most common)
    if GetResourceState('ox_target') == 'started' then
        if Config.Debug then
            print('[V_treasurehunt] Using ox_target for NPC interaction')
        end
        
        exports.ox_target:addLocalEntity(startingNPC, {
            {
                name = 'treasurehunt_start',
                label = 'Start Treasure Hunt',
                icon = 'fas fa-map-marked-alt',
                distance = 1.5,
                canInteract = function(entity, distance, data)
                    -- Safe export call with error handling
                    local success, isActive = pcall(function()
                        return exports['V_treasurehunt']:IsHuntActive()
                    end)
                    return success and not isActive
                end,
                onSelect = function(data)
                    InteractWithNPC('start')
                end
            },
            {
                name = 'treasurehunt_end',
                label = 'End Treasure Hunt',
                icon = 'fas fa-times-circle',
                distance = 1.5,
                canInteract = function(entity, distance, data)
                    -- Safe export call with error handling
                    local success, isActive = pcall(function()
                        return exports['V_treasurehunt']:IsHuntActive()
                    end)
                    return success and isActive
                end,
                onSelect = function(data)
                    InteractWithNPC('end')
                end
            }
        })
        
        if Config.Debug then
            print('[V_treasurehunt] ox_target options added successfully!')
        end
        
    -- Check for qb-target
    elseif GetResourceState('qb-target') == 'started' then
        if Config.Debug then
            print('[V_treasurehunt] Using qb-target for NPC interaction')
        end
        
        exports['qb-target']:AddTargetEntity(startingNPC, {
            options = {
                {
                    type = 'client',
                    icon = 'fas fa-map-marked-alt',
                    label = 'Start Treasure Hunt',
                    action = function()
                        InteractWithNPC('start')
                    end,
                    canInteract = function()
                        local success, isActive = pcall(function()
                            return exports['V_treasurehunt']:IsHuntActive()
                        end)
                        return success and not isActive
                    end
                },
                {
                    type = 'client',
                    icon = 'fas fa-times-circle',
                    label = 'End Treasure Hunt',
                    action = function()
                        InteractWithNPC('end')
                    end,
                    canInteract = function()
                        local success, isActive = pcall(function()
                            return exports['V_treasurehunt']:IsHuntActive()
                        end)
                        return success and isActive
                    end
                }
            },
            distance = 1.5
        })
        
        if Config.Debug then
            print('[V_treasurehunt] qb-target options added successfully!')
        end
        
    -- Fallback to 3D text if no target system found
    else
        print('[V_treasurehunt] WARNING: No target system found (ox_target or qb-target), using fallback 3D text')
        
        CreateThread(function()
            while DoesEntityExist(startingNPC) do
                Wait(0)
                local playerCoords = GetEntityCoords(PlayerPedId())
                local npcCoords = GetEntityCoords(startingNPC)
                local distance = #(playerCoords - npcCoords)
                
                if distance <= 3.0 then
                    -- Safe export call with error handling
                    local isActive = false
                    local success, result = pcall(function()
                        return exports['V_treasurehunt']:IsHuntActive()
                    end)
                    
                    if success then
                        isActive = result
                    else
                        DrawText3D(npcCoords.x, npcCoords.y, npcCoords.z + 1.0, '~y~[E]~w~ Treasure Hunter (Loading...)')
                        goto continue
                    end
                    
                    if isActive then
                        DrawText3D(npcCoords.x, npcCoords.y, npcCoords.z + 1.0, '~r~[E]~w~ End Hunt')
                    else
                        DrawText3D(npcCoords.x, npcCoords.y, npcCoords.z + 1.0, '~g~[E]~w~ Start Hunt')
                    end
                    
                    if IsControlJustPressed(0, 38) then -- E key
                        if isActive then
                            InteractWithNPC('end')
                        else
                            InteractWithNPC('start')
                        end
                    end
                    
                    ::continue::
                end
            end
        end)
    end
end

-- Handle NPC interaction
function InteractWithNPC(action)
    action = action or 'start'
    
    if action == 'start' then
        -- Check if already in hunt (with error handling)
        local isHuntActive = false
        local success, result = pcall(function()
            return exports['V_treasurehunt']:IsHuntActive()
        end)
        
        if success then
            isHuntActive = result
        else
            Bridge.Notify.Error('Treasure Hunt system is still loading, please wait...')
            return
        end
        
        if isHuntActive then
            Bridge.Notify.Warning(Locale.en['npc_active_hunt'])
            return
        end
        
        -- Show confirmation dialog
        ShowStartDialog()
    elseif action == 'end' then
        -- Check if hunt is active (with error handling)
        local isHuntActive = false
        local success, result = pcall(function()
            return exports['V_treasurehunt']:IsHuntActive()
        end)
        
        if success then
            isHuntActive = result
        else
            Bridge.Notify.Error('Treasure Hunt system is still loading, please wait...')
            return
        end
        
        if not isHuntActive then
            Bridge.Notify.Warning('You dont have an active treasure hunt.')
            return
        end
        
        -- Show end confirmation dialog
        ShowEndDialog()
    end
end

-- Show start dialog
function ShowStartDialog()
    if GetResourceState('ox_lib') == 'started' and lib and lib.alertDialog then
        -- Use ox_lib dialog
        local alert = lib.alertDialog({
            header = 'Treasure Hunt',
            content = Locale.en['npc_cost_info']:format(Config.TreasureHunt.cost),
            centered = true,
            cancel = true,
            labels = {
                confirm = Locale.en['yes'],
                cancel = Locale.en['no']
            }
        })
        
        if alert == 'confirm' then
            StartTreasureHunt()
        end
        
    elseif Bridge.FrameworkName == 'qbcore' and GetResourceState('qb-input') == 'started' then
        -- Use QBCore input
        local dialog = exports['qb-input']:ShowInput({
            header = 'Treasure Hunt',
            submitText = Locale.en['yes'],
            inputs = {
                {
                    type = 'text',
                    isRequired = false,
                    name = 'confirm',
                    text = Locale.en['npc_cost_info']:format(Config.TreasureHunt.cost) .. ' Type "yes" to confirm.'
                }
            }
        })
        
        if dialog and dialog.confirm and string.lower(dialog.confirm) == 'yes' then
            StartTreasureHunt()
        end
        
    else
        -- Fallback simple confirmation
        Bridge.Notify.Info(Locale.en['npc_cost_info']:format(Config.TreasureHunt.cost))
        Bridge.Notify.Info('Press Y to confirm, N to cancel')
        
        CreateThread(function()
            local timeout = GetGameTimer() + 10000 -- 10 second timeout
            while GetGameTimer() < timeout do
                Wait(0)
                
                if IsControlJustPressed(0, 246) then -- Y key
                    StartTreasureHunt()
                    break
                elseif IsControlJustPressed(0, 249) then -- N key
                    Bridge.Notify.Info('Treasure hunt cancelled')
                    break
                end
            end
        end)
    end
end

-- Start the treasure hunt
function StartTreasureHunt()
    -- Play NPC speech animation
    if DoesEntityExist(startingNPC) then
        local playerPed = PlayerPedId()
        TaskTurnPedToFaceEntity(playerPed, startingNPC, 3000)
        TaskTurnPedToFaceEntity(startingNPC, playerPed, 3000)
        
        Wait(1000)
        
        -- NPC speaks
        RequestAnimDict('mp_common')
        while not HasAnimDictLoaded('mp_common') do
            Wait(10)
        end
        
        TaskPlayAnim(startingNPC, 'mp_common', 'givetake1_a', 8.0, 8.0, 3000, 0, 0, false, false, false)
        
        -- Show speech bubble or notification
        Bridge.Notify.Info(Locale.en['npc_greeting'], 3000)
        Wait(2000)
    end
    
    -- Send request to server
    TriggerServerEvent('v_treasurehunt:server:startHunt')
    
    -- Update statistics
    TriggerServerEvent('v_treasurehunt:server:updateStats', 'huntStarted')
end

-- Show end dialog
function ShowEndDialog()
    if GetResourceState('ox_lib') == 'started' and lib and lib.alertDialog then
        -- Use ox_lib dialog
        local alert = lib.alertDialog({
            header = 'End Treasure Hunt',
            content = 'Are you sure you want to end your current treasure hunt? You will not get a refund.',
            centered = true,
            cancel = true,
            labels = {
                confirm = 'Yes, End Hunt',
                cancel = 'No, Continue'
            }
        })
        
        if alert == 'confirm' then
            EndTreasureHunt()
        end
    else
        -- Fallback simple confirmation
        Bridge.Notify.Info('Press Y to end hunt, N to cancel')
        
        CreateThread(function()
            local timeout = GetGameTimer() + 10000 -- 10 second timeout
            while GetGameTimer() < timeout do
                Wait(0)
                
                if IsControlJustPressed(0, 246) then -- Y key
                    EndTreasureHunt()
                    break
                elseif IsControlJustPressed(0, 249) then -- N key
                    Bridge.Notify.Info('Hunt continues')
                    break
                end
            end
        end)
    end
end

-- End the treasure hunt
function EndTreasureHunt()
    TriggerServerEvent('v_treasurehunt:server:cancelHunt')
    Bridge.Notify.Success('Treasure hunt ended. Return when youre ready for another adventure!')
end

-- Make NPC look at nearby players
CreateThread(function()
    while true do
        Wait(2000)
        
        if DoesEntityExist(startingNPC) then
            local npcCoords = GetEntityCoords(startingNPC)
            local players = GetActivePlayers()
            local closestPlayer = nil
            local closestDistance = 10.0
            
            for _, playerId in ipairs(players) do
                if playerId ~= PlayerId() then
                    local playerPed = GetPlayerPed(playerId)
                    if DoesEntityExist(playerPed) then
                        local playerCoords = GetEntityCoords(playerPed)
                        local distance = #(npcCoords - playerCoords)
                        
                        if distance < closestDistance then
                            closestDistance = distance
                            closestPlayer = playerPed
                        end
                    end
                end
            end
            
            -- Also check current player
            local currentPlayerPed = PlayerPedId()
            local currentPlayerCoords = GetEntityCoords(currentPlayerPed)
            local currentDistance = #(npcCoords - currentPlayerCoords)
            
            if currentDistance < closestDistance then
                closestPlayer = currentPlayerPed
            end
            
            -- Make NPC look at closest player
            if closestPlayer then
                TaskLookAtEntity(startingNPC, closestPlayer, 4000, 2048, 3)
            end
        end
    end
end)

-- Ensure NPC doesn't despawn
CreateThread(function()
    -- Wait for initial spawn to complete
    while not hasInitialSpawnCompleted do
        Wait(1000)
    end
    
    Wait(30000) -- Additional 30 second delay after initial spawn
    
    while true do
        Wait(120000) -- Check every 2 minutes
        
        -- Only check if initial spawn has completed and NPC doesn't exist
        if hasInitialSpawnCompleted and startingNPC and not DoesEntityExist(startingNPC) and not isSpawning then
            if Config.Debug then
                print('[V_treasurehunt] Starting NPC despawned, respawning...')
            end
            SpawnStartingNPC()
        end
    end
end)

-- Handle resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Remove target interactions
        if startingNPC and DoesEntityExist(startingNPC) then
            if GetResourceState('ox_target') == 'started' then
                pcall(function()
                    exports.ox_target:removeLocalEntity(startingNPC, 'treasurehunt_start')
                    exports.ox_target:removeLocalEntity(startingNPC, 'treasurehunt_end')
                end)
            elseif GetResourceState('qb-target') == 'started' then
                pcall(function()
                    exports['qb-target']:RemoveTargetEntity(startingNPC)
                end)
            end
        end
        
        -- Clean up NPC and blip
        if startingNPC and DoesEntityExist(startingNPC) then
            DeleteEntity(startingNPC)
        end
        
        if npcBlip and DoesBlipExist(npcBlip) then
            RemoveBlip(npcBlip)
        end
        
        -- Reset flags
        hasInitialSpawnCompleted = false
        isSpawning = false
    end
end)

-- Utility function for 3D text (if not already defined)
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

-- Export NPC functions
exports('GetStartingNPC', function()
    return startingNPC
end)

exports('RespawnNPC', function()
    if DoesEntityExist(startingNPC) then
        DeleteEntity(startingNPC)
    end
    SpawnStartingNPC()
end)

-- Debug commands for NPC troubleshooting
RegisterCommand('treasurehunt_npc_debug', function()
    print('=== NPC DEBUG INFO ===')
    print('- Config loaded:', Config ~= nil)
    print('- Config.NPC loaded:', Config and Config.NPC ~= nil)
    print('- NPC model:', Config and Config.NPC and Config.NPC.model or 'unknown')
    print('- NPC coords:', Config and Config.NPC and Config.NPC.coords or 'unknown')
    print('- Starting NPC exists:', startingNPC ~= nil and DoesEntityExist(startingNPC))
    print('- Starting NPC ID:', startingNPC or 'none')
    print('- NPC blip exists:', npcBlip ~= nil and DoesBlipExist(npcBlip))
    print('- Is spawning:', isSpawning)
    print('- Initial spawn completed:', hasInitialSpawnCompleted)
    
    if startingNPC and DoesEntityExist(startingNPC) then
        local coords = GetEntityCoords(startingNPC)
        print('- NPC coordinates:', coords.x, coords.y, coords.z)
        local playerCoords = GetEntityCoords(PlayerPedId())
        local distance = #(playerCoords - coords)
        print('- Distance to player:', distance)
    end
    print('=====================')
end, false)

RegisterCommand('treasurehunt_npc_respawn', function()
    print('[V_treasurehunt] Force respawning NPC...')
    
    -- Clean up existing NPC
    if startingNPC and DoesEntityExist(startingNPC) then
        DeleteEntity(startingNPC)
        print('- Deleted existing NPC')
    end
    
    if npcBlip and DoesBlipExist(npcBlip) then
        RemoveBlip(npcBlip)
        print('- Removed existing blip')
    end
    
    -- Reset flags
    startingNPC = nil
    npcBlip = nil
    isSpawning = false
    
    -- Respawn
    SpawnStartingNPC()
    print('- Attempted to respawn NPC')
end, false)