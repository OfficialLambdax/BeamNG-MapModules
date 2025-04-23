-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.

-- hotreloads the mainLevel lua
-- extensions.reload("levels_" .. core_levels.getLevelName(getMissionFilename()) .. "_mainLevel")

local M = {}

-- add module names that are found in the /levels/yourlevel/lua/* path
local MY_MODULES = {"triggerlights", "portals"}

local INITIALIZED = false
local MODULES = {}

-- -------------------------------------------------------------------
-- Module loader
local function loadLevelModule(level_name, module)
	local path = 'levels/' .. level_name .. '/lua/' .. module
	if not FS:fileExists(path .. '.lua') then
		log('E', 'Module could not be found "' .. module .. '"')
		return
	end
	if MODULES[module] then return end
	
	extensions.loadAtRoot(path, "")
	log('I', 'Loaded level module "' .. module .. '"')
	
	local ext = _G[module]
	if ext then
		MODULES[module] = module
		if ext.onWorldReadyState then ext.onWorldReadyState(2) end
	end
end

-- -------------------------------------------------------------------
-- Load/Unload
local function init()
	local level_name = core_levels.getLevelName(getMissionFilename())
	if level_name == nil then return end
	INITIALIZED = true -- doing it here in case of loading error with any of the extensions
	
	for _, module in ipairs(MY_MODULES) do
		loadLevelModule(level_name, module)
	end
end

local function unload()
	for module, _ in pairs(MODULES) do
		extensions.unload(module)
		log('I', 'Unloaded level module "' .. module .. '"')
	end
	MODULES = {}
	INITIALIZED = false
end

-- -------------------------------------------------------------------
-- Game events
M.onUpdate = function() -- there is no event that is fired when mainLevel is loaded. onClientPreStartMission should be, but isnt
	if not INITIALIZED then init() end
end

M.onExtensionLoaded = function() -- ran by game on load and for manual reloads
	init()
end

M.onExtensionUnloaded = function()
	unload()
end

M.onWorldReadyState = function(state)
	if state == 2 then
		init()
	end
end

return M