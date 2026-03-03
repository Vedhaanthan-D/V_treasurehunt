-- Inventory Bridge System
if IsDuplicityVersion() then -- Server side
    Bridge.Inventory = {}
    Bridge.InventoryName = nil
    
    -- Auto-detect inventory system
    local function DetectInventory()
        if Config.InventorySystem == 'auto' then
            if GetResourceState('ox_inventory') == 'started' then
                if Config.Debug then print('[V_treasurehunt] Auto-detected: ox_inventory') end
                return 'ox_inventory'
            elseif GetResourceState('qb-inventory') == 'started' then
                if Config.Debug then print('[V_treasurehunt] Auto-detected: qb-inventory') end
                return 'qb-inventory'
            elseif Bridge.FrameworkName == 'esx' then
                if Config.Debug then print('[V_treasurehunt] Auto-detected: esx_default') end
                return 'esx_default'
            elseif Bridge.FrameworkName == 'qbcore' then
                if Config.Debug then print('[V_treasurehunt] Auto-detected: qb_default') end
                return 'qb_default'
            else
                if Config.Debug then print('[V_treasurehunt] Auto-detected: standalone') end
                return 'standalone'
            end
        else
            if Config.Debug then print('[V_treasurehunt] Manual config: ' .. Config.InventorySystem) end
            return Config.InventorySystem
        end
    end
    
    -- Initialize inventory
    local function InitInventory()
        Bridge.InventoryName = DetectInventory()
        
        if Config.Debug then
            print(('[V_treasurehunt] Inventory system loaded: %s'):format(Bridge.InventoryName))
        end
    end
    
    -- Add item to player inventory
    Bridge.AddItem = function(source, item, count, metadata)
        local player = Bridge.GetPlayer(source)
        if not player then 
            if Config.Debug then
                print(('[V_treasurehunt] AddItem failed: Player not found for source %d'):format(source))
            end
            return false 
        end
        
        count = count or 1
        metadata = metadata or {}
        
        if Config.Debug then
            print(('[V_treasurehunt] AddItem called: item=%s, count=%d, inventory=%s'):format(item, count, Bridge.InventoryName))
        end
        
        if Bridge.InventoryName == 'ox_inventory' then
            -- ox_inventory handles both items and weapons with AddItem
            local success = exports.ox_inventory:AddItem(source, item, count, metadata)
            if Config.Debug then
                print(('[V_treasurehunt] ox_inventory AddItem result: %s'):format(tostring(success)))
            end
            return success ~= nil and success ~= false
            
        elseif Bridge.InventoryName == 'qb-inventory' then
            return exports['qb-inventory']:AddItem(source, item, count, false, metadata)
            
        elseif Bridge.InventoryName == 'esx_default' then
            local success = player.addInventoryItem(item, count)
            if Config.Debug then
                print(('[V_treasurehunt] ESX AddItem result for %s (x%d): %s'):format(item, count, tostring(success)))
            end
            return success ~= nil
            
        elseif Bridge.InventoryName == 'qb_default' then
            return player.Functions.AddItem(item, count, false, metadata)
            
        elseif Bridge.InventoryName == 'standalone' then
            return true -- Always success for standalone
        end
        
        return false
    end
    
    -- Remove item from player inventory
    Bridge.RemoveItem = function(source, item, count, metadata)
        local player = Bridge.GetPlayer(source)
        if not player then return false end
        
        count = count or 1
        
        if Bridge.InventoryName == 'ox_inventory' then
            return exports.ox_inventory:RemoveItem(source, item, count, metadata)
            
        elseif Bridge.InventoryName == 'qb-inventory' then
            return exports['qb-inventory']:RemoveItem(source, item, count, false, metadata)
            
        elseif Bridge.InventoryName == 'esx_default' then
            player.removeInventoryItem(item, count)
            return true
            
        elseif Bridge.InventoryName == 'qb_default' then
            return player.Functions.RemoveItem(item, count, false)
            
        elseif Bridge.InventoryName == 'standalone' then
            return true -- Always success for standalone
        end
        
        return false
    end
    
    -- Get item count from player inventory
    Bridge.GetItemCount = function(source, item)
        local player = Bridge.GetPlayer(source)
        if not player then return 0 end
        
        if Bridge.InventoryName == 'ox_inventory' then
            return exports.ox_inventory:GetItemCount(source, item)
            
        elseif Bridge.InventoryName == 'qb-inventory' then
            local items = exports['qb-inventory']:GetItemsByName(source, item)
            local count = 0
            for _, itemData in pairs(items) do
                count = count + itemData.amount
            end
            return count
            
        elseif Bridge.InventoryName == 'esx_default' then
            local item = player.getInventoryItem(item)
            return item and item.count or 0
            
        elseif Bridge.InventoryName == 'qb_default' then
            local item = player.Functions.GetItemByName(item)
            return item and item.amount or 0
            
        elseif Bridge.InventoryName == 'standalone' then
            return 999 -- Unlimited items for standalone
        end
        
        return 0
    end
    
    -- Check if player can carry item
    Bridge.CanCarryItem = function(source, item, count)
        count = count or 1
        
        if Bridge.InventoryName == 'ox_inventory' then
            -- ox_inventory: weapons always fit, items need space check
            if string.find(item, 'WEAPON_') then
                return true -- Weapons don't consume regular inventory space
            end
            local canCarry = exports.ox_inventory:CanCarryItem(source, item, count)
            if Config.Debug then
                print(('[V_treasurehunt] ox_inventory CanCarryItem %s x%d: %s'):format(item, count, tostring(canCarry)))
            end
            return canCarry
            
        elseif Bridge.InventoryName == 'qb-inventory' then
            return exports['qb-inventory']:CanAddItem(source, item, count)
            
        elseif Bridge.InventoryName == 'esx_default' then
            local player = Bridge.GetPlayer(source)
            if player then
                -- Use ESX's built-in canCarryItem function which checks weight properly
                local canCarry = player.canCarryItem(item, count)
                if Config.Debug then
                    print(('[V_treasurehunt] ESX CanCarryItem check for %s x%d: %s'):format(item, count, tostring(canCarry)))
                end
                return canCarry
            end
            return false
            
        elseif Bridge.InventoryName == 'qb_default' then
            local player = Bridge.GetPlayer(source)
            return player and true or false -- QBCore handles this internally
            
        elseif Bridge.InventoryName == 'standalone' then
            return true -- Always success for standalone
        end
        
        return false
    end
    
    -- Initialize on resource start
    InitInventory()
    
    -- Register usable items
    local function RegisterUsableItems()
        if Config.Debug then
            print('[V_treasurehunt] Registering usable items for inventory: ' .. tostring(Bridge.InventoryName))
            print('[V_treasurehunt] Framework: ' .. tostring(Bridge.FrameworkName))
        end
        
        if Bridge.InventoryName == 'ox_inventory' then
            if Config.Debug then
                print('[V_treasurehunt] Registering items via ox_inventory hook')
            end
            exports.ox_inventory:registerHook('usingItem', function(payload)
                local itemName = payload.item and payload.item.name or payload.itemName
                local source = payload.source
                
                if Config.Debug then
                    print('[V_treasurehunt] ox_inventory item used: ' .. tostring(itemName) .. ' by player ' .. tostring(source))
                end
                
                if not itemName then return end
                
                if itemName == 'treasure_map' then
                    TriggerClientEvent('v_treasurehunt:client:mapItemUsed', source)
                    return false -- Don't consume item
                elseif itemName == 'chest_scanner' then
                    TriggerClientEvent('v_treasurehunt:client:useScanner', source)
                    return false -- Don't consume item
                elseif itemName == 'spear' then
                    TriggerClientEvent('v_treasurehunt:client:useSpear', source)
                    return false -- Don't consume item
                elseif itemName == 'shovel' then
                    TriggerClientEvent('v_treasurehunt:client:useShovel', source)
                    return false -- Don't consume item
                end
            end)
            
        elseif Bridge.InventoryName == 'esx_default' and Bridge.Framework then
            if Config.Debug then
                print('[V_treasurehunt] Registering items via ESX RegisterUsableItem')
            end
            Bridge.Framework.RegisterUsableItem('treasure_map', function(source)
                if Config.Debug then
                    print('[V_treasurehunt] treasure_map used by player ' .. source)
                end
                TriggerClientEvent('v_treasurehunt:client:mapItemUsed', source)
            end)
            
            Bridge.Framework.RegisterUsableItem('chest_scanner', function(source)
                TriggerClientEvent('v_treasurehunt:client:useScanner', source)
            end)
            
            Bridge.Framework.RegisterUsableItem('spear', function(source)
                TriggerClientEvent('v_treasurehunt:client:useSpear', source)
            end)
            
            Bridge.Framework.RegisterUsableItem('shovel', function(source)
                TriggerClientEvent('v_treasurehunt:client:useShovel', source)
            end)
            
        elseif Bridge.InventoryName == 'qb_default' and Bridge.Framework then
            if Config.Debug then
                print('[V_treasurehunt] Registering items via QBCore CreateUseableItem')
            end
            Bridge.Framework.Functions.CreateUseableItem('treasure_map', function(source, item)
                if Config.Debug then
                    print('[V_treasurehunt] treasure_map used by player ' .. source)
                end
                TriggerClientEvent('v_treasurehunt:client:mapItemUsed', source)
            end)
            
            Bridge.Framework.Functions.CreateUseableItem('chest_scanner', function(source, item)
                TriggerClientEvent('v_treasurehunt:client:useScanner', source)
            end)
            
            Bridge.Framework.Functions.CreateUseableItem('spear', function(source, item)
                TriggerClientEvent('v_treasurehunt:client:useSpear', source)
            end)
            
            Bridge.Framework.Functions.CreateUseableItem('shovel', function(source, item)
                TriggerClientEvent('v_treasurehunt:client:useShovel', source)
            end)
        else
            if Config.Debug then
                print('[V_treasurehunt] WARNING: No matching inventory system found!')
                print('[V_treasurehunt] Bridge.InventoryName: ' .. tostring(Bridge.InventoryName))
                print('[V_treasurehunt] Bridge.Framework: ' .. tostring(Bridge.Framework))
            end
        end
        
        if Config.Debug then
            print('[V_treasurehunt] Usable items registration complete')
        end
    end
    
    -- Wait a bit before registering items to ensure framework is loaded
    SetTimeout(1000, RegisterUsableItems)

else -- Client side
    Bridge.Inventory = {}
    Bridge.InventoryName = nil
    
    -- Auto-detect inventory system
    local function DetectInventory()
        if Config.InventorySystem == 'auto' then
            if GetResourceState('ox_inventory') == 'started' then
                return 'ox_inventory'
            elseif GetResourceState('qb-inventory') == 'started' then
                return 'qb-inventory'
            elseif Bridge.FrameworkName == 'esx' then
                return 'esx_default'
            elseif Bridge.FrameworkName == 'qbcore' then
                return 'qb_default'
            else
                return 'standalone'
            end
        else
            return Config.InventorySystem
        end
    end
    
    -- Initialize inventory
    CreateThread(function()
        while not Bridge.FrameworkName do
            Wait(100)
        end
        
        Bridge.InventoryName = DetectInventory()
        
        if Config.Debug then
            print(('[V_treasurehunt] Client Inventory system loaded: %s'):format(Bridge.InventoryName))
        end
    end)
end