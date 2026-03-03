-- Zone management for treasure hunt areas
local TreasureZones = {}
local activeZones = {}
local zoneEffects = {}

-- Initialize zone system
local function InitZones()
    if Config.Debug then
        print('[V_treasurehunt] Zone system initialized')
    end
end

-- Create treasure zone
function TreasureZones.CreateTreasureZone(center, radius, callbacks)
    local zone = nil
    
    if GetResourceState('ox_lib') == 'started' and lib and lib.zones then
        -- Use ox_lib zones
        zone = lib.zones.sphere({
            coords = center,
            radius = radius,
            debug = false, -- Never show visual zone
            onEnter = callbacks.onEnter or function() end,
            onExit = callbacks.onExit or function() end,
            inside = callbacks.inside or function() end
        })
    else
        -- Fallback manual zone checking
        zone = {
            center = center,
            radius = radius,
            callbacks = callbacks,
            active = true,
            inside = false
        }
        
        -- Start manual checking thread
        CreateThread(function()
            while zone.active do
                Wait(1000)
                
                local playerCoords = GetEntityCoords(PlayerPedId())
                local distance = #(playerCoords - zone.center)
                local isInside = distance <= zone.radius
                
                if isInside and not zone.inside then
                    zone.inside = true
                    if zone.callbacks.onEnter then 
                        zone.callbacks.onEnter() 
                    end
                elseif not isInside and zone.inside then
                    zone.inside = false
                    if zone.callbacks.onExit then 
                        zone.callbacks.onExit() 
                    end
                end
                
                if zone.inside and zone.callbacks.inside then
                    zone.callbacks.inside()
                end
            end
        end)
    end
    
    return zone
end

-- Remove treasure zone
function TreasureZones.RemoveZone(zone)
    if not zone then return end
    
    if GetResourceState('ox_lib') == 'started' then
        if zone.remove then
            zone:remove()
        end
    elseif GetResourceState('PolyZone') == 'started' then
        if zone.destroy then
            zone:destroy()
        end
    else
        -- Fallback
        if zone.active then
            zone.active = false
        end
    end
end

-- Create visual effects for zones
function TreasureZones.CreateZoneEffects(center, radius)
    local effects = {
        particles = {},
        sounds = {},
        active = true
    }
    
    -- Water ripple effects around the treasure area
    CreateThread(function()
        while effects.active do
            Wait(2000)
            
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - center)
            
            if distance <= radius + 100.0 then -- Close enough to see effects
                -- Create random water ripples
                for i = 1, 3 do
                    local angle = math.random() * 2 * math.pi
                    local dist = math.random() * radius * 0.8
                    local effectCoords = center + vector3(
                        math.cos(angle) * dist,
                        math.sin(angle) * dist,
                        0
                    )
                    
                    -- Check if coordinates are over water
                    local groundZ = GetWaterHeight(effectCoords.x, effectCoords.y)
                    if groundZ and groundZ > -999.0 then
                        effectCoords = vector3(effectCoords.x, effectCoords.y, groundZ)
                        
                        -- Spawn water splash effect
                        RequestNamedPtfxAsset('core')
                        while not HasNamedPtfxAssetLoaded('core') do
                            Wait(10)
                        end
                        
                        UseParticleComponentInThisFrame("core")
                        StartParticleFxLoopedAtCoord("water_splash_ped_out", effectCoords.x, effectCoords.y, effectCoords.z, 0.0, 0.0, 0.0, 0.5, false, false, false, false)
                    end
                end
            end
        end
    end)
    
    return effects
end

-- Remove zone effects
function TreasureZones.RemoveZoneEffects(effects)
    if effects then
        effects.active = false
        
        -- Clean up any particles
        for _, particle in ipairs(effects.particles or {}) do
            if DoesParticleFxLoopedExist(particle) then
                StopParticleFxLooped(particle, false)
            end
        end
        
        -- Clean up any sounds
        for _, sound in ipairs(effects.sounds or {}) do
            if sound.id then
                StopSound(sound.id)
                ReleaseSoundId(sound.id)
            end
        end
    end
end

-- Enhanced zone with underwater detection
function TreasureZones.CreateUnderwaterZone(center, radius, callbacks)
    local zone = TreasureZones.CreateTreasureZone(center, radius, callbacks)
    
    -- Add underwater detection
    CreateThread(function()
        while zone do
            Wait(500)
            
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local distance = #(playerCoords - center)
            
            if distance <= radius then
                local isUnderwater = IsPedSwimmingUnderWater(playerPed)
                
                -- Trigger underwater events
                TriggerEvent('v_treasurehunt:client:underwaterStatus', isUnderwater)
                
                -- Check water depth for shark spawning
                local waterHeight = GetWaterHeight(playerCoords.x, playerCoords.y)
                if waterHeight and waterHeight > -999.0 then
                    local depth = waterHeight - playerCoords.z
                    if depth > 0 then
                        TriggerEvent('v_treasurehunt:client:waterDepth', depth)
                    end
                end
            end
        end
    end)
    
    return zone
end

-- Zone status checker
function TreasureZones.IsPlayerInZone(center, radius)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = #(playerCoords - center)
    return distance <= radius
end

-- Get closest zone
function TreasureZones.GetClosestZone()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closest = nil
    local closestDistance = math.huge
    
    for _, zone in pairs(activeZones) do
        if zone.center then
            local distance = #(playerCoords - zone.center)
            if distance < closestDistance then
                closestDistance = distance
                closest = zone
            end
        end
    end
    
    return closest, closestDistance
end

-- Zone boundary warning
function TreasureZones.CreateBoundaryWarning(center, radius)
    local warningZone = TreasureZones.CreateTreasureZone(center, radius + 50.0, {
        onExit = function()
            Bridge.Notify.Warning('You are leaving the treasure hunt area!')
            
            -- Give player 10 seconds to return
            CreateThread(function()
                Wait(10000)
                
                local currentCoords = GetEntityCoords(PlayerPedId())
                local currentDistance = #(currentCoords - center)
                
                if currentDistance > radius + 100.0 then
                    Bridge.Notify.Error('You left the treasure hunt area. Hunt cancelled.')
                    TriggerServerEvent('v_treasurehunt:server:cancelHunt')
                end
            end)
        end
    })
    
    return warningZone
end

-- Weather effects in zones
function TreasureZones.CreateWeatherEffects(center, radius)
    local effects = {
        active = true,
        originalWeather = GetNextWeatherTypeHashName()
    }
    
    CreateThread(function()
        while effects.active do
            Wait(5000)
            
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - center)
            
            if distance <= radius then
                -- Random weather changes in treasure zone
                if math.random() < 0.1 then -- 10% chance every 5 seconds
                    local weatherTypes = {
                        'CLOUDS', 'FOGGY', 'OVERCAST', 'RAIN', 'THUNDER'
                    }
                    local newWeather = weatherTypes[math.random(1, #weatherTypes)]
                    
                    SetWeatherTypeOvertimePersist(newWeather, 30.0)
                    Bridge.Notify.Info('The weather is changing...')
                    
                    -- Restore weather after some time
                    SetTimeout(120000, function() -- 2 minutes
                        if effects.active then
                            SetWeatherTypeOvertimePersist(effects.originalWeather, 30.0)
                        end
                    end)
                end
            end
        end
    end)
    
    return effects
end

-- Event handlers
RegisterNetEvent('v_treasurehunt:client:enteredZone', function()
    -- Start zone-specific effects
    if Config.Sharks.enabled then
        TriggerEvent('v_treasurehunt:client:enableSharks')
    end
    
    -- Start random events
    if Config.RandomEvents.enabled then
        TriggerEvent('v_treasurehunt:client:startRandomEvents')
    end
end)

RegisterNetEvent('v_treasurehunt:client:exitedZone', function()
    -- Stop zone-specific effects
    TriggerEvent('v_treasurehunt:client:disableSharks')
    TriggerEvent('v_treasurehunt:client:stopRandomEvents')
end)

-- Initialize when client starts
CreateThread(function()
    Wait(4000) -- Wait for NPC to spawn first
    InitZones()
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Clean up all zones
        for _, zone in pairs(activeZones) do
            TreasureZones.RemoveZone(zone)
        end
        
        -- Clean up all effects
        for _, effects in pairs(zoneEffects) do
            TreasureZones.RemoveZoneEffects(effects)
        end
    end
end)

-- Export zone functions
exports('CreateTreasureZone', TreasureZones.CreateTreasureZone)
exports('RemoveZone', TreasureZones.RemoveZone)
exports('IsPlayerInZone', TreasureZones.IsPlayerInZone)
exports('GetClosestZone', TreasureZones.GetClosestZone)