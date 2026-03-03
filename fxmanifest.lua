fx_version 'cerulean'
game 'gta5'

name 'V_treasurehunt'
author 'V Development'
version '1.0.0'
description 'Optimized Treasure Hunt Script with Bridge System'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/en.lua'
}

client_scripts {
    'bridge/framework.lua',
    'bridge/inventory.lua',
    'bridge/target.lua',
    'bridge/notify.lua',
    'client/main.lua',          -- Main script with exports and digging logic
    'client/digging.lua',       -- Metal detector beeping only
    'client/zones.lua',         -- Zone management
    'client/sharks.lua',        -- Shark spawning
    'client/npc.lua'            -- NPC management (loads last, depends on main exports)
}

server_scripts {
    'bridge/framework.lua',
    'bridge/inventory.lua',
    'bridge/notify.lua',
    'server/main.lua',
    'server/rewards.lua',
    'server/session.lua'
}

dependencies {
    'ox_lib'
}

escrow_ignore {
    'config.lua',
    'locales/*.lua',
    'bridge/*.lua'
}