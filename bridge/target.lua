-- Target Bridge System (Client-side only)
if not IsDuplicityVersion() then
    Bridge.Target = {}
    Bridge.TargetName = nil
    
    -- Auto-detect target system
    local function DetectTarget()
        if Config.TargetSystem == 'auto' then
            if GetResourceState('ox_target') == 'started' then
                return 'ox_target'
            elseif GetResourceState('qb-target') == 'started' then
                return 'qb-target'
            else
                return 'none'
            end
        else
            return Config.TargetSystem
        end
    end
    
    -- Initialize target system
    local function InitTarget()
        Bridge.TargetName = DetectTarget()
        
        if Config.Debug then
            print(('[V_treasurehunt] Target system loaded: %s'):format(Bridge.TargetName))
        end
    end
    
    -- Add target to entity
    Bridge.AddTargetEntity = function(entity, options)
        if Bridge.TargetName == 'ox_target' then
            exports.ox_target:addLocalEntity(entity, options)
            
        elseif Bridge.TargetName == 'qb-target' then
            -- Convert ox_target format to qb-target format
            local qbOptions = {}
            for i, option in ipairs(options) do
                qbOptions[#qbOptions + 1] = {
                    type = 'client',
                    event = option.onSelect and 'v_treasurehunt:client:targetCallback' or nil,
                    action = option.onSelect,
                    icon = option.icon,
                    label = option.label,
                    canInteract = option.canInteract
                }
            end
            
            exports['qb-target']:AddTargetEntity(entity, {
                options = qbOptions,
                distance = options.distance or 2.5
            })
        end
    end
    
    -- Remove target from entity
    Bridge.RemoveTargetEntity = function(entity, label)
        if Bridge.TargetName == 'ox_target' then
            exports.ox_target:removeLocalEntity(entity, label)
            
        elseif Bridge.TargetName == 'qb-target' then
            exports['qb-target']:RemoveTargetEntity(entity, label)
        end
    end
    
    -- Add target model
    Bridge.AddTargetModel = function(models, options)
        if Bridge.TargetName == 'ox_target' then
            exports.ox_target:addModel(models, options)
            
        elseif Bridge.TargetName == 'qb-target' then
            -- Convert ox_target format to qb-target format
            local qbOptions = {}
            for i, option in ipairs(options) do
                qbOptions[#qbOptions + 1] = {
                    type = 'client',
                    event = option.onSelect and 'v_treasurehunt:client:targetCallback' or nil,
                    action = option.onSelect,
                    icon = option.icon,
                    label = option.label,
                    canInteract = option.canInteract
                }
            end
            
            exports['qb-target']:AddTargetModel(models, {
                options = qbOptions,
                distance = options.distance or 2.5
            })
        end
    end
    
    -- Remove target model
    Bridge.RemoveTargetModel = function(models, label)
        if Bridge.TargetName == 'ox_target' then
            exports.ox_target:removeModel(models, label)
            
        elseif Bridge.TargetName == 'qb-target' then
            exports['qb-target']:RemoveTargetModel(models, label)
        end
    end
    
    -- Add target to coordinates
    Bridge.AddTargetCoords = function(coords, options)
        if Bridge.TargetName == 'ox_target' then
            return exports.ox_target:addBoxZone({
                coords = coords,
                size = options.size or vec3(2, 2, 2),
                rotation = options.rotation or 0,
                options = options
            })
            
        elseif Bridge.TargetName == 'qb-target' then
            -- Convert ox_target format to qb-target format
            local qbOptions = {}
            for i, option in ipairs(options) do
                qbOptions[#qbOptions + 1] = {
                    type = 'client',
                    event = option.onSelect and 'v_treasurehunt:client:targetCallback' or nil,
                    action = option.onSelect,
                    icon = option.icon,
                    label = option.label,
                    canInteract = option.canInteract
                }
            end
            
            return exports['qb-target']:AddBoxZone('treasurehunt_' .. math.random(1000, 9999), coords, 
                options.size and options.size.x or 2.0, 
                options.size and options.size.y or 2.0, {
                name = 'treasurehunt_' .. math.random(1000, 9999),
                heading = options.rotation or 0,
                debugPoly = false,
                minZ = coords.z - 1.0,
                maxZ = coords.z + 1.0,
            }, {
                options = qbOptions,
                distance = options.distance or 2.5
            })
        end
        return nil
    end
    
    -- Remove target zone
    Bridge.RemoveZone = function(id)
        if Bridge.TargetName == 'ox_target' then
            exports.ox_target:removeZone(id)
            
        elseif Bridge.TargetName == 'qb-target' then
            exports['qb-target']:RemoveZone(id)
        end
    end
    
    -- Disable target
    Bridge.DisableTarget = function()
        if Bridge.TargetName == 'ox_target' then
            exports.ox_target:disableTargeting(true)
            
        elseif Bridge.TargetName == 'qb-target' then
            exports['qb-target']:AllowTargeting(false)
        end
    end
    
    -- Enable target
    Bridge.EnableTarget = function()
        if Bridge.TargetName == 'ox_target' then
            exports.ox_target:disableTargeting(false)
            
        elseif Bridge.TargetName == 'qb-target' then
            exports['qb-target']:AllowTargeting(true)
        end
    end
    
    -- Add target interaction handler for qb-target compatibility
    RegisterNetEvent('v_treasurehunt:client:targetCallback', function(data)
        if data.action then
            data.action(data)
        end
    end)
    
    -- Initialize target system
    CreateThread(function()
        while not Bridge.FrameworkName do
            Wait(100)
        end
        InitTarget()
    end)

else -- Server side
    Bridge.Target = {}
    Bridge.TargetName = 'server' -- Placeholder for server side
end