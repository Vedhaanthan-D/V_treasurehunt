-- Server-side reward system with weighted loot
local RewardUtils = {}

-- Generate weighted random rewards
function RewardUtils.GenerateRewards()
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
                    if selected.name == item.name then
                        found = true
                        break
                    end
                end
                
                if not found then
                    local count = math.random(item.min, item.max)
                    table.insert(selectedItems, {
                        name = item.name,
                        count = count,
                        weight = item.weight
                    })
                    table.insert(rewards, {
                        item = item.name,
                        count = count
                    })
                end
                break
            end
        end
    end
    
    return rewards, selectedItems
end

-- Give rewards to player
function RewardUtils.GiveRewards(source)
    local player = Bridge.GetPlayer(source)
    if not player then
        return false
    end
    
    local rewards, selectedItems = RewardUtils.GenerateRewards()
    local givenItems = {}
    local success = true
    
    -- Check if player can carry all items first
    for _, reward in ipairs(rewards) do
        if not Bridge.CanCarryItem(source, reward.item, reward.count) then
            Bridge.Notify.Player(source, ('Not enough space for %s'):format(reward.item), 'error')
            return false
        end
    end
    
    -- Give all rewards
    for _, reward in ipairs(rewards) do
        local itemGiven = Bridge.AddItem(source, reward.item, reward.count, {
            description = 'Found during treasure hunt',
            quality = 100
        })
        
        if itemGiven then
            table.insert(givenItems, reward)
            local itemLabel = reward.item:gsub('_', ' '):gsub("(%a)([%w_]*)", function(a, b) return a:upper()..b end)
            Bridge.Notify.Player(source, ('Received %s x%s'):format(itemLabel, reward.count), 'success')
        else
            success = false
            Bridge.Notify.Player(source, ('Failed to receive %s'):format(reward.item), 'error')
        end
    end
    
    -- Trigger analytics event (if you have an analytics system)
    TriggerEvent('v_treasurehunt:server:rewardsAnalytics', source, givenItems)
    
    return success, givenItems
end

-- Calculate reward value (for balancing)
function RewardUtils.CalculateRewardValue(items)
    local totalValue = 0
    local itemValues = {
        gold_bar = 1500,
        diamond = 5000,
        ancient_coin = 450,
        emerald = 3500,
        rare_chain = 8000
    }
    
    for _, item in ipairs(items) do
        local value = itemValues[item.item] or 100
        totalValue = totalValue + (value * item.count)
    end
    
    return totalValue
end

-- Anti-exploit: Validate reward legitimacy
function RewardUtils.ValidateReward(source, rewards)
    -- Check if rewards are within expected parameters
    if #rewards > Config.Rewards.maxRewards then
        return false
    end
    
    -- Check individual item counts
    for _, reward in ipairs(rewards) do
        local found = false
        for _, configItem in ipairs(Config.Rewards.items) do
            if configItem.name == reward.item then
                if reward.count > configItem.max or reward.count < configItem.min then
                    return false
                end
                found = true
                break
            end
        end
        
        if not found then
            return false
        end
    end
    
    return true
end

-- Event handler for giving rewards
RegisterNetEvent('v_treasurehunt:server:giveRewards', function(playerId)
    local source = playerId or source
    
    -- Generate and validate rewards
    local success, rewards = RewardUtils.GiveRewards(source)
    
    if success and rewards then
        if RewardUtils.ValidateReward(source, rewards) then
            -- Calculate total value for analytics
            local totalValue = RewardUtils.CalculateRewardValue(rewards)
            
            -- Trigger success event
            TriggerClientEvent('v_treasurehunt:client:rewardsReceived', source, rewards, totalValue)
        else
            Bridge.Notify.Player(source, Locale.en['error_general'], 'error')
        end
    else
        Bridge.Notify.Player(source, Locale.en['chest_empty'], 'warning')
    end
end)

-- Command to test rewards (admin only)
RegisterCommand('treasuretest', function(source, args)
    if source == 0 then -- Console only
        local testRewards, selectedItems = RewardUtils.GenerateRewards()
        print('[V_treasurehunt] Test rewards generated:')
        for _, reward in ipairs(testRewards) do
            print(('  - %s x%s'):format(reward.item, reward.count))
        end
        local value = RewardUtils.CalculateRewardValue(testRewards)
        print(('Total estimated value: $%s'):format(value))
    end
end, false)

-- Export reward functions
exports('GenerateRewards', RewardUtils.GenerateRewards)
exports('GiveRewards', RewardUtils.GiveRewards)
exports('CalculateRewardValue', RewardUtils.CalculateRewardValue)

-- Analytics event handler (customize based on your analytics system)
RegisterNetEvent('v_treasurehunt:server:rewardsAnalytics', function(source, rewards)
    -- You can integrate with your analytics system here
end)

-- Return the module for require()
return RewardUtils