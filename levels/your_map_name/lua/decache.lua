-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.

local M = {}

local MAP_VERSION = 1
local MAP_NAME = "your_map_name"


-- -------------------------------------------------------------------------------
-- Game Events
M.onExtensionLoaded = function()
    if worldReadyState ~= 0 then return end

    local settings_name = string.format("decache_%s_v", MAP_NAME, MAP_VERSION)
    if settings.getValue(settings_name) == MAP_VERSION then return end

    FS:remove(string.format("/temp/levels/%s", MAP_NAME))
    settings.setValue(settings_name, MAP_VERSION)

    log('I', 'Map Decache', string.format("Removing cache of map %s duo to update", MAP_NAME))
end

return M
