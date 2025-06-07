-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.

--[[
	hotreloads the mainLevel lua
		extensions.reload("levels_" .. core_levels.getLevelName(getMissionFilename()) .. "_mainLevel")
	
	alternate
		extensions.unload("mainLevel"); extensions.loadAtRoot("levels/" .. core_levels.getLevelName(getMissionFilename()) .. "/mainLevel", "")
	
	Todo
		- Find a way to mount virtual pathes to other virtual pathes >>>without copying files<<<
			So everything from
			/levels/map_name/lua	--to->	/lua/ge/extensions
			/levels/map_name/vlua	--to->	/lua/vehicle/extensions
			
			eg.
			/levels/map_name/lua/module.lua			-> /lua/ge/extensions/module.lua
			/levels/map_name/lua/libs/anylib.lua	-> /lua/ge/extensions/libs/anylib.lua
			/levels/map_name/lua/core/input/actions/hotkeys.json -> /lua/ge/extensions/core/input/actions/hotkeys.json
			
			This would allow map modules to operate exactly like ge/ve modules. And the pathes to require() would be the same, allowing a module to work as either a map module, a ge module or vehicle module without any change in its file.
]]

local M = {
	_VERSION = '0.4' -- 01.06.2025 (DD.MM.YYYY)
}
local GE_MODULES = {}
local VE_MODULES = {}
local LEVEL_NAME = ''

-- -------------------------------------------------------------------
-- Common
local function myLevelName()
	local source = debug.getinfo(1).source
	if source == nil then return end
	
	local strip = source:sub(8)
	local _, pos = strip:find('/')
	return strip:sub(1, pos - 1)
end

local function fileName(path)
	local str = path:sub(1):gsub("\\", "/")
	local _, pos = str:find(".*/")
	if pos == nil then return path end
	return str:sub(pos + 1, -1)
end

local function fileExtension(path)
	return path:match("[^.]+$")
end

local function fileNameNoExt(path)
	local file_name = fileName(path)
	local ext = (fileExtension(file_name) or ''):lower()
	
	return file_name:sub(1, #file_name - #ext - 1) -- what if #ext == 0
end

-- -------------------------------------------------------------------
-- Module loader
local function loadLevelModule(path)
	local module = fileNameNoExt(path)
	
	local ok, r = pcall(extensions.loadAtRoot, path:sub(1, #path - 4), "")
	if not ok then
		log('E', 'mainLevel.module_loader', r)
		return
	end
	log('I', 'mainLevel.module_loader', '-> Loaded level module "' .. module .. '"')
	
	if _G[module] then table.insert(GE_MODULES, module) end
end

-- -------------------------------------------------------------------
-- Load/Unload
local function vehicleInit(vehicle_id)
	if #VE_MODULES == 0 then return end
	local vehicle = getObjectByID(vehicle_id)
	
	local exec = ''
	for _, module in ipairs(VE_MODULES) do
		exec = exec .. 'extensions.loadAtRoot("' .. module .. '", "") '
	end
	vehicle:queueLuaCommand(exec)
	
	-- doing this because the game does it, but since our mods are loaded after full veh load and the reset event, we have todo it ourself.
	local exec = ''
	for _, module in ipairs(VE_MODULES) do
		module = fileName(module)
		exec = exec .. 'if ' .. module .. ' and ' .. module .. '.onReset then ' .. module .. '.onReset() end '
	end
	vehicle:queueLuaCommand(exec)
end

local function hotreload()
	for _, vehicle in ipairs(getAllVehicles()) do
		vehicleInit(vehicle:getId())
	end
end

local function init()
	LEVEL_NAME = myLevelName()
	log('I', 'mainLevel.module_loader', 'Loading GE modules for map "' .. LEVEL_NAME .. '"')
	for _, path in ipairs(FS:directoryList('levels/' .. LEVEL_NAME .. '/lua/') or {}) do
		if (fileExtension(path) or ''):lower() == 'lua' then
			loadLevelModule(path)
		end
	end
	
	log('I', 'mainLevel.module_loader', 'Indexing VE modules for map "' .. LEVEL_NAME .. '"')
	for _, path in ipairs(FS:directoryList('levels/' .. LEVEL_NAME .. '/vlua/') or {}) do
		if (fileExtension(path) or ''):lower() == 'lua' then
			table.insert(VE_MODULES, path:sub(1, #path - 4))
			log('I', 'mainLevel.module_loader', '-> Learned of "' .. fileName(path) .. '"')
		end
	end
	
	hotreload()
end

local function unload()
	log('I', 'mainLevel.module_loader', 'Unloading all GE map modules')
	for _, module in ipairs(GE_MODULES) do
		local ok, r = pcall(extensions.unload, module)
		if not ok then
			log('E', 'mainLevel.module_loader', r)
		else
			log('I', 'mainLevel.module_loader', '-> Unloaded level module "' .. module .. '"')
		end
	end
	GE_MODULES = {}
	
	log('I', 'mainLevel.module_loader', 'Unloading all VE map modules')
	local exec = ''
	for _, module in ipairs(VE_MODULES) do
		exec = exec .. 'extensions.unload("' .. fileName(module) .. '") '
	end
	for _, vehicle in ipairs(getAllVehicles()) do
		vehicle:queueLuaCommand(exec)
	end
	VE_MODULES = {}
end

-- -------------------------------------------------------------------
-- Module API
--[[
	If your lib is bundled with this map and located at eg.
		/levels/map_name/lua/libs/myLib.lua
	then you CANT just require it like this
		local MyLib = require("libs/myLib")
	Because it isnt at that location in the virtual file system like it would be for a ge or ve module. (See Todo on the top of this file)
	
	So you do
		local MyLib = require(mainLevel.findLib("libs/myLib"))
		
	I dont like this fact but currently there is no solution to this.
]]
M.findLib = function(lib_path) -- ge only
	local try_path = string.format('/levels/%s/lua/%s', LEVEL_NAME, lib_path)
	if FS:fileExists(try_path .. '.lua') then return try_path end
	return lib_path
end

M.luaPath = function()
	return '/levels/' .. LEVEL_NAME .. '/lua'
end

M.vluaPath = function()
	return '/levels/' .. LEVEL_NAME .. '/vlua'
end


M.levelName = function() return LEVEL_NAME end

-- -------------------------------------------------------------------
-- Game events
M.onExtensionLoaded = init -- ran by game on load and for manual reloads
M.onExtensionUnloaded = unload
M.onVehicleSpawned = vehicleInit

return M