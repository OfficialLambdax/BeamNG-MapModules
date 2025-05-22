-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.

--[[
	hotreloads the mainLevel lua
		extensions.reload("levels_" .. core_levels.getLevelName(getMissionFilename()) .. "_mainLevel")
	
	alternate
		extensions.unload("mainLevel"); extensions.loadAtRoot("levels/" .. core_levels.getLevelName(getMissionFilename()) .. "/mainLevel", "")
]]

local M = {
	_VERSION = '0.2' -- 22.05.2025 (DD.MM.YYYY)
}
local MODULES = {}


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
	if ext ~= "lua" then return end
	
	return file_name:sub(1, #file_name - #ext - 1)
end

-- -------------------------------------------------------------------
-- Module loader
local function loadLevelModule(path)
	local module = fileNameNoExt(path)
	if not module then return end -- not a lua file
	
	local ok, r = pcall(extensions.loadAtRoot, path:sub(1, #path - 4), "")
	if not ok then
		log('E', 'mainLevel.module_loader', r)
		return
	end
	log('I', 'mainLevel.module_loader', 'Loaded level module "' .. module .. '"')
	
	local ext = _G[module]
	if ext then MODULES[module] = module end
end

-- -------------------------------------------------------------------
-- Load/Unload
local function init()
	local level_name = myLevelName()
	log('I', 'mainLevel.module_loader', 'Loading modules for map "' .. level_name .. '"')
	for _, path in ipairs(FS:directoryList('levels/' .. level_name .. '/lua/') or {}) do
		loadLevelModule(path)
	end
end

local function unload()
	log('I', 'mainLevel.module_loader', 'Unloading all map modules')
	for module, _ in pairs(MODULES) do
		local ok, r = pcall(extensions.unload, module)
		if not ok then
			log('E', 'mainLevel.module_loader', r)
		else
			log('I', 'mainLevel.module_loader', 'Unloaded level module "' .. module .. '"')
		end
	end
	MODULES = {}
end

M.reload = function()
	unload()
	init()
end

-- -------------------------------------------------------------------
-- Game events
M.onExtensionLoaded = function() -- ran by game on load and for manual reloads
	init()
end

M.onExtensionUnloaded = function()
	unload()
end

return M