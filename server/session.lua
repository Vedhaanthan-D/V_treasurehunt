-- Session management for treasure hunts
local SessionManager = {}
SessionManager.sessions = {}
SessionManager.playerData = {}

-- Save session data (for persistence across reconnects if needed)
function SessionManager.SaveSession(source, sessionData)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return false end
    
    SessionManager.sessions[identifier] = {
        source = source,
        data = sessionData,
        lastUpdate = os.time(),
        savedAt = os.time()
    }
    
    return true
end

-- Load session data
function SessionManager.LoadSession(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return nil end
    
    local session = SessionManager.sessions[identifier]
    if session then
        -- Update source in case player reconnected
        session.source = source
        session.lastUpdate = os.time()
        
        return session.data
    end
    
    return nil
end

-- Remove session
function SessionManager.RemoveSession(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return false end
    
    if SessionManager.sessions[identifier] then
        SessionManager.sessions[identifier] = nil
        return true
    end
    
    return false
end

-- Get all active sessions
function SessionManager.GetActiveSessions()
    local active = {}
    local currentTime = os.time()
    
    for identifier, session in pairs(SessionManager.sessions) do
        -- Check if session is still valid (not too old)
        if currentTime - session.lastUpdate < Config.TreasureHunt.huntDuration then
            active[identifier] = session
        end
    end
    
    return active
end

-- Clean up old sessions
function SessionManager.CleanupOldSessions()
    local currentTime = os.time()
    local cleaned = 0
    
    for identifier, session in pairs(SessionManager.sessions) do
        -- Remove sessions older than hunt duration + 1 hour grace period
        if currentTime - session.lastUpdate > (Config.TreasureHunt.huntDuration + 3600) then
            SessionManager.sessions[identifier] = nil
            cleaned = cleaned + 1
        end
    end
    
    return cleaned
end

-- Store player statistics
function SessionManager.StorePlayerStats(source, statType, value)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return false end
    
    if not SessionManager.playerData[identifier] then
        SessionManager.playerData[identifier] = {
            huntsStarted = 0,
            huntsCompleted = 0,
            totalRewardValue = 0,
            lastHunt = 0,
            bestReward = 0,
            sharksKilled = 0,
            timesAttacked = 0,
            randomEvents = 0
        }
    end
    
    local stats = SessionManager.playerData[identifier]
    
    if statType == 'huntStarted' then
        stats.huntsStarted = stats.huntsStarted + 1
        stats.lastHunt = os.time()
    elseif statType == 'huntCompleted' then
        stats.huntsCompleted = stats.huntsCompleted + 1
    elseif statType == 'rewardValue' then
        stats.totalRewardValue = stats.totalRewardValue + value
        if value > stats.bestReward then
            stats.bestReward = value
        end
    elseif statType == 'sharkKilled' then
        stats.sharksKilled = stats.sharksKilled + 1
    elseif statType == 'attacked' then
        stats.timesAttacked = stats.timesAttacked + 1
    elseif statType == 'randomEvent' then
        stats.randomEvents = stats.randomEvents + 1
    end
    
    return true
end

-- Get player statistics
function SessionManager.GetPlayerStats(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return nil end
    
    return SessionManager.playerData[identifier]
end

-- Backup session data (could be used with database)
function SessionManager.BackupSessions()
    local backup = {
        sessions = SessionManager.sessions,
        playerData = SessionManager.playerData,
        timestamp = os.time()
    }
    
    -- In a full implementation, you could save this to a file or database
    -- For now, it's just kept in memory
    
    return backup
end

-- Restore session data (from database/file)
function SessionManager.RestoreSessions(backupData)
    if not backupData then return false end
    
    SessionManager.sessions = backupData.sessions or {}
    SessionManager.playerData = backupData.playerData or {}
    
    return true
end

-- Handle player connecting (restore session if exists)
RegisterNetEvent('v_treasurehunt:server:playerConnected', function()
    local source = source
    local sessionData = SessionManager.LoadSession(source)
    
    if sessionData then
        -- Player had an active session, restore it
        TriggerClientEvent('v_treasurehunt:client:restoreSession', source, sessionData)
        Bridge.Notify.Player(source, Locale.en['session_saved'], 'info')
    end
end)

-- Handle player disconnecting (save session if exists)
RegisterNetEvent('v_treasurehunt:server:playerDisconnected', function()
    local source = source
    
    -- Check if player had an active hunt
    if exports['V_treasurehunt']:GetPlayerHunt(source) then
        local huntData = exports['V_treasurehunt']:GetPlayerHunt(source)
        SessionManager.SaveSession(source, huntData)
    end
end)

-- Event handlers for statistics
RegisterNetEvent('v_treasurehunt:server:updateStats', function(statType, value)
    local source = source
    SessionManager.StorePlayerStats(source, statType, value)
end)

-- Command to get player stats (for testing/admin)
RegisterCommand('huntStats', function(source, args)
    if source == 0 then return end -- Console only command
    
    local stats = SessionManager.GetPlayerStats(source)
    if stats then
        local message = ('Treasure Hunt Stats:\nHunts Started: %s\nHunts Completed: %s\nTotal Reward Value: $%s\nBest Single Reward: $%s\nSharks Killed: %s'):format(
            stats.huntsStarted,
            stats.huntsCompleted,
            stats.totalRewardValue,
            stats.bestReward,
            stats.sharksKilled
        )
        Bridge.Notify.Player(source, message, 'info', 10000)
    else
        Bridge.Notify.Player(source, 'No treasure hunt statistics found.', 'info')
    end
end, false)

-- Periodic cleanup and backup
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        SessionManager.CleanupOldSessions()
        SessionManager.BackupSessions()
    end
end)

-- Handle resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Save all active sessions before stopping
        SessionManager.BackupSessions()
    end
end)

-- Export session functions
exports('SaveSession', SessionManager.SaveSession)
exports('LoadSession', SessionManager.LoadSession)
exports('RemoveSession', SessionManager.RemoveSession)
exports('GetActiveSessions', SessionManager.GetActiveSessions)
exports('GetPlayerStats', SessionManager.GetPlayerStats)
exports('StorePlayerStats', SessionManager.StorePlayerStats)