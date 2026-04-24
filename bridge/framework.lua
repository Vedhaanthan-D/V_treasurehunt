-- Bridge system for framework compatibility
if IsDuplicityVersion() then -- Server side
    Bridge = {}
    Bridge.Framework = nil
    Bridge.FrameworkName = nil
    
    -- Auto-detect framework
    local function DetectFramework()
        if Config.Framework == 'auto' then
            if GetResourceState('es_extended') == 'started' then
                return 'esx'
            elseif GetResourceState('qb-core') == 'started' or GetResourceState('qbx_core') == 'started' then
                return 'qbcore'
            else
                return 'standalone'
            end
        else
            return Config.Framework
        end
    end
    
    -- Initialize framework
    local function InitFramework()
        Bridge.FrameworkName = DetectFramework()
        
        if Bridge.FrameworkName == 'esx' then
            Bridge.Framework = exports['es_extended']:getSharedObject()
        elseif Bridge.FrameworkName == 'qbcore' then
            Bridge.Framework = exports['qb-core']:GetCoreObject() or exports['qbx_core']:GetCoreObject()
        elseif Bridge.FrameworkName == 'standalone' then
            Bridge.Framework = nil
        end
        
        if Config.Debug then
            print(('[V_treasurehunt] Framework loaded: %s'):format(Bridge.FrameworkName))
            print(('[V_treasurehunt] Framework object: %s'):format(tostring(Bridge.Framework)))
        end
    end
    
    -- Get player data
    Bridge.GetPlayer = function(source)
        if Bridge.FrameworkName == 'esx' then
            return Bridge.Framework.GetPlayerFromId(source)
        elseif Bridge.FrameworkName == 'qbcore' then
            return Bridge.Framework.Functions.GetPlayer(source)
        elseif Bridge.FrameworkName == 'standalone' then
            return {
                source = source,
                identifier = GetPlayerIdentifiers(source)[1] or 'unknown'
            }
        end
        return nil
    end
    
    -- Get player identifier
    Bridge.GetIdentifier = function(source)
        if Bridge.FrameworkName == 'esx' then
            local player = Bridge.GetPlayer(source)
            return player and player.identifier or nil
        elseif Bridge.FrameworkName == 'qbcore' then
            local player = Bridge.GetPlayer(source)
            return player and player.PlayerData.citizenid or nil
        elseif Bridge.FrameworkName == 'standalone' then
            return GetPlayerIdentifiers(source)[1] or 'unknown'
        end
        return nil
    end
    
    -- Get player money
    Bridge.GetMoney = function(source, account)
        local player = Bridge.GetPlayer(source)
        if not player then return 0 end
        
        account = account or 'money'
        
        if Bridge.FrameworkName == 'esx' then
            if account == 'money' or account == 'cash' then
                return player.getMoney() or 0
            elseif account == 'bank' then
                return player.getAccount('bank').money or 0
            end
            return player.getMoney() or 0
        elseif Bridge.FrameworkName == 'qbcore' then
            if account == 'money' then account = 'cash' end
            return player.PlayerData.money[account] or 0
        elseif Bridge.FrameworkName == 'standalone' then
            return 99999 -- Unlimited money for standalone
        end
        return 0
    end
    
    -- Remove player money
    Bridge.RemoveMoney = function(source, amount, account, reason)
        local player = Bridge.GetPlayer(source)
        if not player then return false end
        
        account = account or 'money'
        reason = reason or 'Treasure Hunt'
        
        if Bridge.FrameworkName == 'esx' then
            if account == 'money' then account = 'money' end
            if account == 'bank' then account = 'bank' end
            player.removeMoney(amount)
            return true
        elseif Bridge.FrameworkName == 'qbcore' then
            if account == 'money' then account = 'cash' end
            return player.Functions.RemoveMoney(account, amount, reason)
        elseif Bridge.FrameworkName == 'standalone' then
            return true -- Always success for standalone
        end
        return false
    end
    
    -- Add player money
    Bridge.AddMoney = function(source, amount, account, reason)
        local player = Bridge.GetPlayer(source)
        if not player then return false end
        
        account = account or 'money'
        reason = reason or 'Treasure Hunt Refund'
        
        if Bridge.FrameworkName == 'esx' then
            if account == 'money' or account == 'cash' then
                player.addMoney(amount)
            elseif account == 'bank' then
                player.addAccountMoney('bank', amount)
            end
            return true
        elseif Bridge.FrameworkName == 'qbcore' then
            if account == 'money' then account = 'cash' end
            return player.Functions.AddMoney(account, amount, reason)
        elseif Bridge.FrameworkName == 'standalone' then
            return true -- Always success for standalone
        end
        return false
    end
    
    -- Initialize on resource start
    InitFramework()
    
else -- Client side
    Bridge = {}
    Bridge.Framework = nil
    Bridge.FrameworkName = nil
    Bridge.PlayerLoaded = false
    Bridge.PlayerData = {}
    
    -- Auto-detect framework
    local function DetectFramework()
        if Config.Framework == 'auto' then
            if GetResourceState('es_extended') == 'started' then
                return 'esx'
            elseif GetResourceState('qb-core') == 'started' or GetResourceState('qbx_core') == 'started' then
                return 'qbcore'
            else
                return 'standalone'
            end
        else
            return Config.Framework
        end
    end
    
    -- Initialize framework
    local function InitFramework()
        Bridge.FrameworkName = DetectFramework()
        
        if Bridge.FrameworkName == 'esx' then
            Bridge.Framework = exports['es_extended']:getSharedObject()
            
            -- ESX events
            RegisterNetEvent('esx:playerLoaded', function(xPlayer)
                Bridge.PlayerLoaded = true
                Bridge.PlayerData = xPlayer
            end)
            
            RegisterNetEvent('esx:setJob', function(job)
                Bridge.PlayerData.job = job
            end)
            
        elseif Bridge.FrameworkName == 'qbcore' then
            Bridge.Framework = exports['qb-core']:GetCoreObject() or exports['qbx_core']:GetCoreObject()
            
            -- QBCore events
            RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
                Bridge.PlayerLoaded = true
                Bridge.PlayerData = Bridge.Framework.Functions.GetPlayerData()
            end)
            
            RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
                Bridge.PlayerData = val
            end)
            
        elseif Bridge.FrameworkName == 'standalone' then
            Bridge.Framework = nil
            Bridge.PlayerLoaded = true
            Bridge.PlayerData = { source = GetPlayerServerId(PlayerId()) }
        end
        
        if Config.Debug then
            print(('[V_treasurehunt] Client Framework loaded: %s'):format(Bridge.FrameworkName))
        end
    end
    
    -- Wait for framework to be ready
    CreateThread(function()
        while not Bridge.FrameworkName do
            Wait(100)
        end
        InitFramework()
        
        -- Wait for player to be loaded
        while not Bridge.PlayerLoaded do
            Wait(500)
        end
    end)
    
    -- Get player data
    Bridge.GetPlayerData = function()
        return Bridge.PlayerData
    end
    
    -- Check if player is loaded
    Bridge.IsPlayerLoaded = function()
        return Bridge.PlayerLoaded
    end
end