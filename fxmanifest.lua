fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'snowy'
description 'snowy_garages'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/debug.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/_index.lua',
}

client_scripts {
    'client/_index.lua',
}

ui_page 'web/impound/index.html'

files {
    'bridge/_index.lua',
    'bridge/vehicle.lua',

    'client/garages.lua',
    'client/garages_api.lua',
    'client/vehicle.lua',
    'client/vehicle_type.lua',
    'client/creator_camera.lua',
    'client/creator.lua',
    'client/ipl.lua',
    'client/parking.lua',
    'client/spots.lua',
    'client/impound.lua',

    'configs/shared/main.lua',

    'locales/*.json',

    'web/impound/index.html',
    'web/impound/style.css',
    'web/impound/script.js',
}

ox_libs {
    'locale',
    'math',
    'table',
}

server_export 'generatePlate'
