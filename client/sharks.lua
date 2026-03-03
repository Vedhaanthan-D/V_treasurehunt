-- Shark system for treasure hunt adventure
local SharkSystem = {}
local activeeSharks = {}
local sharkSpawnTimer = 0
local inWaterZone = false
local sharkRelationshipGroup = nil

-- Initialize shark system
function SharkSystem.Init()
    -- Create relationship group for sharks
    sharkRelationshipGroup = GetHashKey('SHARK_HUNT')
    AddRelationshipGroup('SHARK_HUNT')
    
    -- Set sharks to attack players
    SetRelationshipBetweenGroups(5, sharkRelationshipGroup, GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), sharkRelationshipGroup)
    
    if Config.Debug then
        print('[V_treasurehunt] Shark system initialized')
    end
end

-- Enable shark spawning
function SharkSystem.Enable()
    if not Config.Sharks.enabled then return end
    
    inWaterZone = true
    sharkSpawnTimer = GetGameTimer()
    
    CreateThread(function()
        while inWaterZone do
            Wait(60000) -- Check every minute
            
            if #activeeSharks < Config.Sharks.maxSharks then
                -- Random chance to spawn shark
                if math.random() < Config.Sharks.spawnChance then
                    SharkSystem.SpawnShark()
                end
            end
            
            -- Clean up distant sharks
            SharkSystem.CleanupDistantSharks()
        end
    end)
    
    -- Shark behavior update thread
    CreateThread(function()
        while inWaterZone do
            Wait(1000)
            SharkSystem.UpdateSharkBehavior()
        end
    end)
    
    if Config.Debug then
        print('[V_treasurehunt] Shark spawning enabled')
    end
end

-- Disable shark spawning
function SharkSystem.Disable()
    inWaterZone = false
    SharkSystem.DespawnAllSharks()
    
    if Config.Debug then
        print('[V_treasurehunt] Shark spawning disabled')
    end
end

-- Spawn a shark near the player
function SharkSystem.SpawnShark()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    -- Check if player is in water
    local isInWater = IsEntityInWater(playerPed) or IsPedSwimming(playerPed)
    if not isInWater then return end
    
    -- Determine shark model based on water depth
    local waterHeight = GetWaterHeight(playerCoords.x, playerCoords.y)
    local depth = waterHeight and (waterHeight - playerCoords.z) or 0
    
    local sharkModel = depth > 10.0 and Config.Sharks.models.deep or Config.Sharks.models.shallow
    local modelHash = GetHashKey(sharkModel)
    
    -- Request model
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(modelHash) then
        if Config.Debug then
            print('[V_treasurehunt] Failed to load shark model: ' .. sharkModel)
        end
        return
    end
    
    -- Find spawn position around player
    local angle = math.random() * 2 * math.pi
    local distance = Config.Sharks.spawnDistance
    local spawnCoords = vector3(
        playerCoords.x + math.cos(angle) * distance,
        playerCoords.y + math.sin(angle) * distance,
        waterHeight and (waterHeight - 2.0) or (playerCoords.z - 2.0)
    )
    
    -- Create shark
    local shark = CreatePed(28, modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, math.random(0, 360), false, true)
    
    if DoesEntityExist(shark) then
        -- Configure shark
        SetEntityAsMissionEntity(shark, true, true)
        SetPedRelationshipGroupHash(shark, sharkRelationshipGroup)
        SetEntityHealth(shark, Config.Sharks.health)
        SetPedMaxHealth(shark, Config.Sharks.health)
        SetPedCanRagdoll(shark, false)
        SetEntityInvincible(shark, false)
        
        -- Make shark aggressive
        SetPedCombatAttributes(shark, 46, true) -- Always fight
        SetPedCombatAttributes(shark, 5, true) -- Can use vehicles
        SetPedFleeAttributes(shark, 0, false) -- Don't flee
        
        -- Add to active sharks list
        table.insert(activeeSharks, {
            entity = shark,
            spawnTime = GetGameTimer(),
            lastPlayerDistance = 999.0,
            isAttacking = false
        })
        
        -- Set shark behavior
        SharkSystem.SetSharkBehavior(shark)
        
        -- Notify player - DISABLED
        -- Bridge.Notify.Warning(Locale.en['shark_warning'])
        
        if Config.Debug then
            print(('[V_treasurehunt] Shark spawned: %s at %s'):format(sharkModel, spawnCoords))
        end
    end
    
    SetModelAsNoLongerNeeded(modelHash)
end

-- Set initial shark behavior
function SharkSystem.SetSharkBehavior(shark)
    if not DoesEntityExist(shark) then return end
    
    local playerPed = PlayerPedId()
    
    -- Make shark swim towards player area
    TaskWanderInWater(shark, 8.0)
    
    -- Set up AI behavior
    SetPedPathCanUseClimbovers(shark, false)
    SetPedPathCanUseLadders(shark, false)
    SetPedPathAvoidFire(shark, false)
    
    -- Combat settings
    SetPedCombatRange(shark, 2) -- Close range combat
    SetPedAlertness(shark, 3) -- High alertness
    SetPedSeeingRange(shark, 50.0)
    SetPedHearingRange(shark, 30.0)
end

-- Update shark behavior
function SharkSystem.UpdateSharkBehavior()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    for i = #activeeSharks, 1, -1 do
        local sharkData = activeeSharks[i]
        local shark = sharkData.entity
        
        if DoesEntityExist(shark) and not IsEntityDead(shark) then
            local sharkCoords = GetEntityCoords(shark)
            local distance = #(playerCoords - sharkCoords)
            
            sharkData.lastPlayerDistance = distance
            
            -- Check attack range
            if distance <= Config.Sharks.attackDistance and not sharkData.isAttacking then
                SharkSystem.StartSharkAttack(shark, sharkData)
            elseif distance > Config.Sharks.attackDistance * 2 and sharkData.isAttacking then
                SharkSystem.StopSharkAttack(shark, sharkData)
            end
            
            -- Make shark follow player if close enough
            if distance <= 30.0 and distance > Config.Sharks.attackDistance then
                if not IsPedInCombat(shark, playerPed) then
                    TaskGoToEntity(shark, playerPed, -1, 15.0, 2.0, 1073741824, 0)
                end
            end
            
            -- Check if shark is too far from player
            if distance > Config.Sharks.despawnDistance then
                SharkSystem.DespawnShark(i)
            end
            
        else
            -- Remove dead/invalid sharks
            table.remove(activeeSharks, i)
        end
    end
end

-- Start shark attack
function SharkSystem.StartSharkAttack(shark, sharkData)
    if not DoesEntityExist(shark) then return end
    
    sharkData.isAttacking = true
    local playerPed = PlayerPedId()
    
    -- Make shark aggressive towards player
    TaskCombatPed(shark, playerPed, 0, 16)
    SetPedCombatMovement(shark, 2) -- Aggressive movement
    
    -- Attack notification - DISABLED
    -- Bridge.Notify.Error(Locale.en['shark_attack'])
    
    -- Play attack sound
    PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
    
    -- Damage player periodically while shark is close
    CreateThread(function()
        while sharkData.isAttacking and DoesEntityExist(shark) and not IsEntityDead(shark) do
            Wait(3000) -- Every 3 seconds
            
            local playerCoords = GetEntityCoords(playerPed)
            local sharkCoords = GetEntityCoords(shark)
            local distance = #(playerCoords - sharkCoords)
            
            if distance <= Config.Sharks.attackDistance then
                -- Apply damage
                local playerHealth = GetEntityHealth(playerPed)
                local newHealth = playerHealth - Config.Sharks.damage
                
                if newHealth > 0 then
                    SetEntityHealth(playerPed, newHealth)
                    
                    -- Screen effect
                    SetFlash(0, 0, 200, 500, 200)
                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.3)
                else
                    -- Player died - stop attack
                    sharkData.isAttacking = false
                end
            else
                break
            end
        end
    end)
    
    if Config.Debug then
        print('[V_treasurehunt] Shark attack started')
    end
end

-- Stop shark attack
function SharkSystem.StopSharkAttack(shark, sharkData)
    if not DoesEntityExist(shark) then return end
    
    sharkData.isAttacking = false
    
    -- Return to wandering behavior
    ClearPedTasks(shark)
    TaskWanderInWater(shark, 8.0)
    
    if Config.Debug then
        print('[V_treasurehunt] Shark attack stopped')
    end
end

-- Despawn specific shark
function SharkSystem.DespawnShark(index)
    local sharkData = activeeSharks[index]
    if sharkData and DoesEntityExist(sharkData.entity) then
        DeleteEntity(sharkData.entity)
        
        if Config.Debug then
            print('[V_treasurehunt] Shark despawned (distance)')
        end
    end
    
    table.remove(activeeSharks, index)
end

-- Despawn all sharks
function SharkSystem.DespawnAllSharks()
    for _, sharkData in ipairs(activeeSharks) do
        if DoesEntityExist(sharkData.entity) then
            DeleteEntity(sharkData.entity)
        end
    end
    
    activeeSharks = {}
    -- Removed notification: Bridge.Notify.Info(Locale.en['sharks_cleared'])
    
    if Config.Debug then
        print('[V_treasurehunt] All sharks despawned')
    end
end

-- Clean up sharks that are too far
function SharkSystem.CleanupDistantSharks()
    local playerCoords = GetEntityCoords(PlayerPedId())
    
    for i = #activeeSharks, 1, -1 do
        local sharkData = activeeSharks[i]
        local shark = sharkData.entity
        
        if DoesEntityExist(shark) then
            local sharkCoords = GetEntityCoords(shark)
            local distance = #(playerCoords - sharkCoords)
            
            if distance > Config.Sharks.despawnDistance then
                SharkSystem.DespawnShark(i)
            end
        else
            table.remove(activeeSharks, i)
        end
    end
end

-- Kill shark (when player fights back)
function SharkSystem.KillShark(shark)
    if DoesEntityExist(shark) then
        SetEntityHealth(shark, 0)
        
        -- Find and remove from active list
        for i = #activeeSharks, 1, -1 do
            if activeeSharks[i].entity == shark then
                table.remove(activeeSharks, i)
                break
            end
        end
        
        -- Reward player for killing shark
        TriggerServerEvent('v_treasurehunt:server:updateStats', 'sharkKilled')
        Bridge.Notify.Success('You killed the shark!')
        
        if Config.Debug then
            print('[V_treasurehunt] Player killed a shark')
        end
    end
end

-- Get active shark count
function SharkSystem.GetActiveSharkCount()
    -- Clean up invalid entries first
    for i = #activeeSharks, 1, -1 do
        if not DoesEntityExist(activeeSharks[i].entity) then
            table.remove(activeeSharks, i)
        end
    end
    
    return #activeeSharks
end

-- Event handlers
RegisterNetEvent('v_treasurehunt:client:enableSharks', function()
    SharkSystem.Enable()
end)

RegisterNetEvent('v_treasurehunt:client:disableSharks', function()
    SharkSystem.Disable()
end)

RegisterNetEvent('v_treasurehunt:client:underwaterStatus', function(isUnderwater)
    -- Increase shark spawn chance when underwater
    if isUnderwater and inWaterZone then
        if math.random() < 0.3 and #activeeSharks < Config.Sharks.maxSharks then -- 30% chance
            SharkSystem.SpawnShark()
        end
    end
end)

RegisterNetEvent('v_treasurehunt:client:waterDepth', function(depth)
    -- Spawn different sharks based on depth
    -- This is handled in SpawnShark() function
end)

-- Handle shark killed by player
AddEventHandler('entityDamaged', function(victim, culprit, weapon, baseDamage)
    if culprit == PlayerPedId() then
        -- Check if victim is one of our sharks
        for i = #activeeSharks, 1, -1 do
            if activeeSharks[i].entity == victim then
                if IsEntityDead(victim) then
                    SharkSystem.KillShark(victim)
                end
                break
            end
        end
    end
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SharkSystem.DespawnAllSharks()
    end
end)

-- Initialize when resource starts
CreateThread(function()
    Wait(6000) -- Wait for NPC, zones, and digging
    SharkSystem.Init()
end)

-- Export shark functions
exports('GetActiveSharkCount', SharkSystem.GetActiveSharkCount)
exports('SpawnShark', SharkSystem.SpawnShark)
exports('DespawnAllSharks', SharkSystem.DespawnAllSharks)
exports('IsSharkSystemActive', function() return inWaterZone end)