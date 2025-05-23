-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.

--[[
	hotreloads the mainLevel lua
		extensions.reload("levels_" .. core_levels.getLevelName(getMissionFilename()) .. "_mainLevel")
	
	alternate
		extensions.unload("mainLevel"); extensions.loadAtRoot("levels/" .. core_levels.getLevelName(getMissionFilename()) .. "/mainLevel", "")
]]

local M = {
	_VERSION = '0.3' -- 23.05.2025 (DD.MM.YYYY)
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
	
	local exec = ''
	for _, module in ipairs(VE_MODULES) do
		exec = exec .. 'extensions.loadAtRoot("' .. module .. '", "") '
	end
	getObjectByID(vehicle_id):queueLuaCommand(exec)
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
	
	-- for hotreloads
	for _, vehicle in ipairs(getAllVehicles()) do
		vehicleInit(vehicle:getId())
	end
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
-- Game events
M.onExtensionLoaded = init -- ran by game on load and for manual reloads
M.onExtensionUnloaded = unload
M.onVehicleSpawned = vehicleInit

return M