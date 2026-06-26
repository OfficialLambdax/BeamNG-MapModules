-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.

--[[
	Repository and example modules: https://github.com/OfficialLambdax/BeamNG-MapModules

	Me notes
		hotreloads the mainLevel lua
			extensions.reload("levels_" .. core_levels.getLevelName(getMissionFilename()) .. "_mainLevel")

		alternate
			extensions.unload("mainLevel"); extensions.loadAtRoot("levels/" .. core_levels.getLevelName(getMissionFilename()) .. "/mainLevel", "")
	
	Todo
		- Find a way to mount virtual pathes to other virtual pathes >>>without copying files<<< (thats important, as we cannot ensure the deletion of these files duo to potential game crashes)
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
	_VERSION = '0.5' -- 26.06.2026 (DD.MM.YYYY)
}
local GE_MODULES = {} -- module | module path (path wo. .lua)
local VE_MODULES = {} -- module | module path (path wo. .lua)
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
local function indexGEModules()
	log('I', 'mainLevel.module_loader', 'Indexing GE modules for map "' .. LEVEL_NAME .. '"')
	for _, path in ipairs(FS:directoryList('levels/' .. LEVEL_NAME .. '/lua/') or {}) do
		if (fileExtension(path) or ''):lower() == 'lua' then
			local module = fileNameNoExt(path)
			GE_MODULES[module] = path:sub(1, #path - 4)
			log('I', 'mainLevel.indexGEModules', '-> Learned of "' .. module .. '" GE module')
		end
	end
end

local function indexVEModules()
	log('I', 'mainLevel.module_loader', 'Indexing VE modules for map "' .. LEVEL_NAME .. '"')
	for _, path in ipairs(FS:directoryList('levels/' .. LEVEL_NAME .. '/vlua/') or {}) do
		if (fileExtension(path) or ''):lower() == 'lua' then
			local module = fileNameNoExt(path)
			VE_MODULES[module] = path:sub(1, #path - 4)
			log('I', 'mainLevel.indexVEModules', '-> Learned of "' .. module .. '" VE module')
		end
	end
end

local function loadLevelModule(module, path)
	local ok, r = pcall(extensions.loadAtRoot, path, "")
	if not ok then
		log('E', 'mainLevel.loadLevelModule', r)
		return
	end
	log('I', 'mainLevel.loadLevelModule', '-> Loaded level module "' .. module .. '"')
end

local function reloadVehicleModule(module, path)
	local exec = 'extensions.unload("' .. module .. '"); extensions.loadAtRoot("' .. path .. '", ""); if ' .. module .. ' and ' .. module .. '.onReset then ' .. module .. '.onReset() end'
	for _, vehicle in ipairs(getAllVehicles()) do
		vehicle:queueLuaCommand(exec)
	end
end

local function unloadGEModules()
	log('I', 'mainLevel.unloadGEModules', 'Unloading all GE map modules')
	for module, _ in pairs(GE_MODULES) do
		local ok, r = pcall(extensions.unload, module)
		if not ok then
			log('E', 'mainLevel.unloadGEModules', r)
		else
			log('I', 'mainLevel.unloadGEModules', '-> Unloaded level module "' .. module .. '"')
		end
	end
end

local function unloadVEModules()
	log('I', 'mainLevel.unloadVEModules', 'Unloading all VE map modules')
	local exec = ''
	for module, _ in pairs(VE_MODULES) do
		exec = exec .. 'extensions.unload("' .. module .. '") '
	end
	for _, vehicle in ipairs(getAllVehicles()) do
		vehicle:queueLuaCommand(exec)
	end
end

-- -------------------------------------------------------------------
-- Load/Unload
local function vehicleInit(vehicle_id)
	if #VE_MODULES == 0 then return end
	local vehicle = getObjectByID(vehicle_id)

	vehicle:queueLuaCommand("mainLevel = {}; mainLevel.findLib = function(lib_path) local try_path = string.format('/levels/%s/lua/%s', '" .. LEVEL_NAME .. "', lib_path); if FS:fileExists(try_path .. '.lua') then return try_path end; print(try_path); return lib_path end")
	
	local exec = ''
	for module, path in pairs(VE_MODULES) do
		exec = exec .. 'extensions.loadAtRoot("' .. path .. '", "") '
	end
	vehicle:queueLuaCommand(exec)
	
	-- doing this because the game does it, but since our mods are loaded after full veh load and the reset event, we have todo it ourself.
	local exec = ''
	for module, path in pairs(VE_MODULES) do
		exec = exec .. 'if ' .. module .. ' and ' .. module .. '.onReset then ' .. module .. '.onReset() end '
	end
	vehicle:queueLuaCommand(exec)
end

local function vehicleHotreload()
	for _, vehicle in ipairs(getAllVehicles()) do
		vehicleInit(vehicle:getId())
	end
end

local function init()
	LEVEL_NAME = myLevelName()
	indexGEModules()
	indexVEModules()
	for module, path in pairs(GE_MODULES) do
		loadLevelModule(module, path)
	end
	vehicleHotreload()
end

local function unload()
	unloadGEModules()
	table.clear(GE_MODULES)
	unloadVEModules()
	table.clear(VE_MODULES)
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

M.reload = function()
	--[[ -- this would be enough, but with the method below we are reloading THIS file as well
	unload()
	init()
	]]
	extensions.unload("mainLevel"); extensions.loadAtRoot("levels/" .. core_levels.getLevelName(getMissionFilename()) .. "/mainLevel", "")
end

M.reloadGE = function(extension_name)
	local path = GE_MODULES[extension_name]
	if path then
		if not _G[extension_name] then return end
		extensions.unload(extension_name)
		loadLevelModule(extension_name, path)

	elseif extension_name == nil then
		unloadGEModules()
		for module, path in pairs(GE_MODULES) do
			loadLevelModule(module, path)
		end
	end
end

M.reloadVE = function(extension_name)
	local path = VE_MODULES[extension_name]
	if path then
		reloadVehicleModule(extension_name, path)

	elseif extension_name == nil then
		unloadVEModules()
		vehicleHotreload()
	end
end

-- -------------------------------------------------------------------
-- Game events
M.onExtensionLoaded = init -- ran by game on load and for manual reloads
M.onExtensionUnloaded = unload
M.onVehicleSpawned = vehicleInit

return M
