Config = {}

-- Framework Configuration
Config.Framework = 'esx' -- 'esx', 'qbcore', 'standalone', 'auto' (auto-detect)

-- Target System Configuration  
Config.TargetSystem = 'ox_target' -- 'ox_target', 'qb-target', 'auto' (auto-detect)

-- Inventory System Configuration
Config.InventorySystem = 'auto' -- 'ox_inventory', 'qb-inventory', 'auto' (auto-detect)

-- Starting NPC Configuration
Config.NPC = {
    model = 'a_m_m_beach_01', -- Fisherman/pirate style model
    coords = vector4(-2166.2664, 5197.4746, 16.8804, 102.4599),
    boatSpawn = vector4(-2165.5435, 5131.0513, -0.3343, 222.4791), -- Primary boat spawn
    
    -- Multiple boat spawn positions to prevent overlapping
    boatSpawnPoints = {
        vector4(-2165.5435, 5131.0513, -0.3343, 222.4791),  -- Primary spawn
        vector4(-2155.5435, 5131.0513, -0.3343, 222.4791),  -- 10m east
        vector4(-2175.5435, 5131.0513, -0.3343, 222.4791),  -- 10m west
        vector4(-2165.5435, 5143.0513, -0.3343, 222.4791),  -- 12m north
        vector4(-2165.5435, 5119.0513, -0.3343, 222.4791),  -- 12m south
        vector4(-2150.5435, 5140.0513, -0.3343, 200.0),     -- Northeast
        vector4(-2180.5435, 5140.0513, -0.3343, 245.0),     -- Northwest
        vector4(-2150.5435, 5122.0513, -0.3343, 200.0),     -- Southeast
        vector4(-2180.5435, 5122.0513, -0.3343, 245.0),     -- Southwest
        vector4(-2145.5435, 5131.0513, -0.3343, 180.0),     -- Far east
    },
    
    scenario = nil,  -- Animation is handled in code (reading map / smoking loop)
    frozen = true,
    invincible = true,
    blockEvents = true,
    label = 'Treasure Hunter',
    icon = 'fas fa-map-marked-alt'
}

-- Treasure Hunt Configuration
Config.TreasureHunt = {
    cost = 2500, -- Cost to start treasure hunt
    cooldown = 1800, -- 30 minutes in seconds
    maxActiveHunts = 50, -- Maximum concurrent hunts
    huntDuration = 3600, -- 1 hour maximum hunt time
    
    -- Blip settings (used for all zone circles)
    zone = {
        blipColor = 11, -- Light blue
        blipAlpha = 128
    },

    -- Sequential zones: Zone 1 revealed by treasure map, Zone 2 shown after completing Zone 1, Zones 3-9 revealed by compass only.
    -- Each zone has a circle area (center + radius) and multiple dig spots inside it.
    zones = {
        -- Zone 1 (revealed by treasure map) - Center calculated from 4 corners
        {
            center = vector3(-1954.15, 4831.96, 1.14),
            radius = 55.0,
            digSpots = {
                vector4(-1933.7983, 4814.9932, 16.5341, 8.1438),
                vector4(-1958.8970, 4821.9268, 13.7139, 173.8575),
                vector4(-1985.9067, 4830.6763, 6.7568, 294.5777),
                vector4(-1951.4867, 4836.3569, 11.3989, 275.9281),
                vector4(-1923.8290, 4836.3584, 9.0754, 281.8909)
            },
            label = 'Zone 1'
        },
        -- Zone 2 (automatically revealed after Zone 1 completion)
        {
            center = vector3(-1436.58, 5406.21, -0.28),
            radius = 50.0,
            digSpots = {
                vector4(-1442.6001, 5422.2568, 22.8858, 174.2118),
                vector4(-1437.2599, 5403.6860, 24.6688, 126.6912),
                vector4(-1421.2451, 5416.2852, 24.3507, 221.6092),
                vector4(-1462.3448, 5426.6621, 21.9564, 168.6419)
            },
            label = 'Zone 2'
        },
        -- Zone 3 (compass only)
        {
            center = vector3(-1635.26, 5444.13, 1.37),
            radius = 45.0,
            digSpots = {
                vector4(-1643.2462, 5437.5933, 9.0424, 310.1928),
                vector4(-1624.5327, 5460.8042, 18.8729, 349.1296),
                vector4(-1628.1766, 5441.1099, 12.6870, 146.6088)
            },
            label = 'Zone 3'
        },
        -- Zone 4 (compass only)
        {
            center = vector3(-1807.12, 5509.65, -1.11),
            radius = 42.0,
            digSpots = {
                vector4(-1797.6526, 5499.2896, 10.1690, 347.8054),
                vector4(-1822.8583, 5512.8359, 9.7148, 45.2608),
                vector4(-1824.0929, 5526.0767, 9.3111, 45.1620),
                vector4(-1804.2930, 5524.3325, 15.2491, 11.3982)
            },
            label = 'Zone 4'
        },
        -- Zone 5 (compass only)
        {
            center = vector3(-1889.19, 5453.27, -0.09),
            radius = 25.0,
            digSpots = {
                vector4(-1891.6224, 5457.8101, 5.9986, 296.5330),
                vector4(-1881.3799, 5450.4702, 2.9300, 94.6486)
            },
            label = 'Zone 5'
        },
        -- Zone 6 (compass only)
        {
            center = vector3(-2047.48, 5248.02, -2.13),
            radius = 65.0,
            digSpots = {
                vector4(-2068.9646, 5241.5723, 10.2331, 100.4520),
                vector4(-2050.2646, 5262.0747, 17.2801, 358.4791),
                vector4(-2030.2186, 5272.2769, 19.8829, 315.5217),
                vector4(-2038.7297, 5223.1357, 3.8434, 102.4289),
                vector4(-2071.1458, 5197.4717, 4.2191, 141.7551)
            },
            label = 'Zone 6'
        },
        -- Zone 7 (compass only)
        {
            center = vector3(-99.74, 7295.15, 0.50),
            radius = 70.0,
            digSpots = {
                vector4(-70.6041, 7300.9727, 4.2693, 148.1210),
                vector4(-112.3165, 7253.9995, 4.0823, 75.6502),
                vector4(-144.8366, 7296.7114, 4.7420, 106.1102),
                vector4(-64.1273, 7345.2061, 3.1117, 231.7986)
            },
            label = 'Zone 7'
        },
        -- Zone 8 (compass only)
        {
            center = vector3(214.52, 7412.52, -2.68),
            radius = 120.0,
            digSpots = {
                vector4(268.3613, 7488.1201, 2.8311, 124.4343),
                vector4(228.1622, 7465.1250, 1.9876, 251.2949),
                vector4(138.0247, 7374.1875, 4.2757, 190.6883),
                vector4(171.4938, 7327.9951, 2.1598, 11.2307),
                vector4(193.0650, 7363.7119, 0.9817, 31.0647)
            },
            label = 'Zone 8'
        },
        -- Zone 9 - Final (compass only)
        {
            center = vector3(18.62, 7631.80, -0.67),
            radius = 55.0,
            digSpots = {
                vector4(4.7391, 7630.2754, 5.2086, 185.9096),
                vector4(-10.0669, 7608.0254, 0.8776, 273.9645),
                vector4(21.5999, 7616.2051, 2.5409, 333.8684),
                vector4(42.3721, 7647.5371, 1.1040, 138.6012)
            },
            label = 'Zone 9 (Final)'
        },
    },
    
    -- Detection range for spear usage (meters)
    spearRadius = 25.0,
    
    -- Chest Scanner Settings
    scannerDetectionRange = 30.0, -- Detection range in meters
    scannerBeepDistance = 15.0, -- Distance when beeping starts
    scannerAnimationTime = 8000, -- 8 seconds
    
    -- Digging settings
    digTime = 8000, -- 8 seconds digging animation
    digKey = 'E',
    
    -- Distance validation (anti-cheat)
    maxDistance = 1200.0
}

-- Required Items
Config.RequiredItems = {
    startCost = 'money', -- Item required to start (money/bank/cash)
    
    -- Regular items given to player
    items = {
        { name = 'treasure_map', count = 1 },
        { name = 'compass', count = 1 },
        { name = 'garden_shovel', count = 1 }
    },
    
    -- Weapons given to player (for ox_inventory these are in weapons.lua)
    weapons = {
        { name = 'WEAPON_METALDETECTOR', ammo = 0 }
    }
}

-- Sharks Configuration
Config.Sharks = {
    enabled = false, -- DISABLED: No shark spawning
    maxSharks = 3, -- Maximum sharks at once
    spawnChance = 0.15, -- 15% chance per minute in water
    spawnDistance = 50.0, -- Spawn distance from player
    despawnDistance = 150.0, -- Despawn distance from player
    
    -- Shark models based on water depth
    models = {
        shallow = 'a_c_sharktiger', -- Less water area
        deep = 'a_c_sharkhammer' -- More water area
    },
    
    -- Shark behavior
    attackDistance = 15.0,
    health = 200,
    damage = 25
}

-- Reward System (Weighted System)
Config.Rewards = {
    maxRewards = 3, -- Maximum items per reward
    minRewards = 1, -- Minimum items per reward
    
    items = {
        { name = 'gold_bar', weight = 40, min = 1, max = 2 },
        { name = 'diamond', weight = 10, min = 1, max = 1 },
        { name = 'ancient_coin', weight = 50, min = 2, max = 4 },
        { name = 'emerald', weight = 5, min = 1, max = 1 },
        { name = 'rare_chain', weight = 3, min = 1, max = 1 }
    }
}

-- Random Events Configuration
Config.RandomEvents = {
    enabled = true,
    
    events = {
        fakeChest = {
            enabled = true,
            chance = 0.1, -- 10% chance
            explosion = true,
            damage = 50
        },
        
        storm = {
            enabled = true,
            chance = 0.05, -- 5% chance
            duration = 120000 -- 2 minutes
        },
        
        pirateAttack = {
            enabled = true,
            chance = 0.03, -- 3% chance
            npcs = 2,
            weapons = { 'WEAPON_PISTOL', 'WEAPON_KNIFE' }
        }
    }
}

-- Performance Settings
Config.Performance = {
    updateInterval = 1000, -- 1 second updates
    cleanupInterval = 30000, -- 30 seconds cleanup
    maxRenderDistance = 100.0,
    lowSpec = false -- Enable for lower-end servers
}

-- Notification Settings
Config.Notifications = {
    position = 'top-right',
    duration = 5000
}

-- Debug Mode
Config.Debug = false