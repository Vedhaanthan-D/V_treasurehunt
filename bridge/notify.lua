-- Notification Bridge System
if IsDuplicityVersion() then -- Server side
    Bridge.Notify = {}
    
    -- Send notification to specific player
    Bridge.Notify.Player = function(source, message, type, duration)
        TriggerClientEvent('v_treasurehunt:client:notify', source, message, type, duration)
    end
    
    -- Send notification to all players
    Bridge.Notify.All = function(message, type, duration)
        TriggerClientEvent('v_treasurehunt:client:notify', -1, message, type, duration)
    end
    
else -- Client side
    Bridge.Notify = {}
    
    -- Send notification
    Bridge.Notify.Send = function(message, type, duration)
        type = type or 'info'
        duration = duration or Config.Notifications.duration
        
        -- Try ox_lib first (most universal)
        if GetResourceState('ox_lib') == 'started' and lib then
            lib.notify({
                title = 'Treasure Hunt',
                description = message,
                type = type,
                duration = duration,
                position = Config.Notifications.position or 'top-right'
            })
            
        -- ESX notifications
        elseif Bridge.FrameworkName == 'esx' and GetResourceState('esx_notify') == 'started' then
            exports['esx_notify']:Notify(type, duration, message)
            
        elseif Bridge.FrameworkName == 'esx' and Bridge.Framework then
            Bridge.Framework.ShowNotification(message)
            
        -- QBCore notifications
        elseif Bridge.FrameworkName == 'qbcore' and GetResourceState('qb-notify') == 'started' then
            exports['qb-notify']:Alert('Treasure Hunt', message, duration, type)
            
        elseif Bridge.FrameworkName == 'qbcore' and Bridge.Framework then
            Bridge.Framework.Functions.Notify(message, type, duration)
            
        -- Fallback to chat message
        else
            local color = {r = 255, g = 255, b = 255}
            if type == 'error' then
                color = {r = 255, g = 0, b = 0}
            elseif type == 'success' then
                color = {r = 0, g = 255, b = 0}
            elseif type == 'warning' then
                color = {r = 255, g = 165, b = 0}
            end
            
            TriggerEvent('chat:addMessage', {
                color = color,
                multiline = true,
                args = {'[Treasure Hunt]', message}
            })
        end
    end
    
    -- Notification type shortcuts
    Bridge.Notify.Success = function(message, duration)
        Bridge.Notify.Send(message, 'success', duration)
    end
    
    Bridge.Notify.Error = function(message, duration)
        Bridge.Notify.Send(message, 'error', duration)
    end
    
    Bridge.Notify.Warning = function(message, duration)
        Bridge.Notify.Send(message, 'warning', duration)
    end
    
    Bridge.Notify.Info = function(message, duration)
        Bridge.Notify.Send(message, 'info', duration)
    end
    
    -- Register notification event
    RegisterNetEvent('v_treasurehunt:client:notify', function(message, type, duration)
        Bridge.Notify.Send(message, type, duration)
    end)
    
    -- Progress bar function
    Bridge.ProgressBar = function(data)
        if GetResourceState('ox_lib') == 'started' and lib then
            -- Use ox_lib progress bar
            return lib.progressBar({
                duration = data.duration,
                label = data.label,
                useWhileDead = false,
                canCancel = data.canCancel or true,
                disable = data.disable or {
                    car = true,
                    move = true,
                    combat = true
                },
                anim = data.anim or {
                    dict = 'random@domestic',
                    clip = 'pickup_low',
                    flag = 1
                },
                prop = data.prop or nil
            })
            
        elseif Bridge.FrameworkName == 'qbcore' and GetResourceState('progressbar') == 'started' then
            -- Use QBCore progress bar
            local finished = false
            local success = false
            
            exports['progressbar']:Progress({
                name = data.name or 'treasurehunt_progress',
                duration = data.duration,
                label = data.label,
                useWhileDead = false,
                canCancel = data.canCancel or true,
                controlDisables = data.disable or {
                    disableMovement = true,
                    disableCarMovement = true,
                    disableMouse = false,
                    disableCombat = true
                },
                animation = data.anim or {
                    animDict = 'random@domestic',
                    anim = 'pickup_low',
                    flags = 1
                },
                prop = data.prop or nil
            }, function(cancelled)
                finished = true
                success = not cancelled
            end)
            
            -- Wait for progress to finish
            while not finished do
                Wait(10)
            end
            
            return success
            
        elseif Bridge.FrameworkName == 'esx' and GetResourceState('esx_progressbar') == 'started' then
            -- Use ESX progress bar
            local finished = false
            local success = false
            
            exports['esx_progressbar']:Progressbar(data.label, data.duration, {
                FreezePlayer = true,
                onFinish = function()
                    finished = true
                    success = true
                end,
                onCancel = function()
                    finished = true
                    success = false
                end
            })
            
            -- Wait for progress to finish
            while not finished do
                Wait(10)
            end
            
            return success
            
        else
            -- Fallback: simple wait with animation
            if data.anim then
                local ped = PlayerPedId()
                if data.anim.dict and data.anim.clip then
                    RequestAnimDict(data.anim.dict)
                    while not HasAnimDictLoaded(data.anim.dict) do
                        Wait(10)
                    end
                    TaskPlayAnim(ped, data.anim.dict, data.anim.clip, 8.0, 8.0, -1, data.anim.flag or 1, 0, false, false, false)
                end
            end
            
            local startTime = GetGameTimer()
            while GetGameTimer() - startTime < data.duration do
                if data.canCancel and IsControlJustPressed(0, 200) then -- ESC key
                    if data.anim then
                        StopAnimTask(PlayerPedId(), data.anim.dict, data.anim.clip, 1.0)
                    end
                    return false
                end
                Wait(10)
            end
            
            if data.anim then
                StopAnimTask(PlayerPedId(), data.anim.dict, data.anim.clip, 1.0)
            end
            
            return true
        end
    end
end