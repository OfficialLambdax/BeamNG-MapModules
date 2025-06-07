-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.

local M = {
	_VERSION = "0.1" -- 01.06.2025 (DD.MM.YYYY)
}
local ROOT_GROUP = 'autolights'

--[[
	Format
	[1..n] = table
		[light] = obj
		[id] = int (only used when world editor is open)
]]
local LIGHTS = {}
local STATE = false

-- --------------------------------------------------------------------------------
-- Common
local function tableVToK(table) -- alters
	for k, v in ipairs(table) do
		table[v] = true
		table[k] = nil
	end
	return table
end

local function vTableMerge(from, into) -- alters into
	for _, v in ipairs(from) do
		table.insert(into, v)
	end
	return into
end

local function findAllObjectsInSimgroupOfTypeRecursive(sim_group, ...)
	local classes = tableVToK({...})
	local objects = {}
	for i = 0, sim_group:getCount() do
		local obj = scenetree.findObjectById(sim_group:idAt(i))
		local class_name = obj:getClassName()
		if class_name == "Prefab" then
			obj = obj:getChildGroup()
		end
		if class_name == "SimGroup" then
			if obj:getName() ~= "RootGroup" then
				vTableMerge(findAllObjectsInSimgroupOfTypeRecursive(obj, ...), objects)
			end
		end
		if classes[class_name] then
			table.insert(objects, obj)
		end
	end
	return objects
end

local function isNight(tod)
	return tod.time > 0.21 and tod.time < 0.77
end

local function isDay(tod)
	return not isNight(tod)
end

-- --------------------------------------------------------------------------------
-- Veh client support
local function setTodInVehicle(vehicle, state)
	vehicle:queueLuaCommand('if autolights and autolights.setState then autolights.setState(' .. tostring(state) .. ') end')
end

-- --------------------------------------------------------------------------------
-- Load / Unload
local function init()
	local root_group = scenetree[ROOT_GROUP]
	if root_group == nil then
		log('E', 'AutoLights', 'No scentree group or prefab with the name "' .. ROOT_GROUP .. '"')
		return
	end
	
	local class_name = root_group:getClassName()
	if class_name ~= "SimGroup" then
		if class_name == "Prefab" then
			root_group = root_group:getChildGroup()
		else
			log('E', 'AutoLights', 'No scenetree group or prefab with name "' .. ROOT_GROUP .. '"')
			return
		end
	end
	
	local lights = findAllObjectsInSimgroupOfTypeRecursive(root_group, 'PointLight', 'SpotLight')
	for _, light in ipairs(lights) do
		table.insert(LIGHTS, {
			light = light,
			id = light:getId()
		})
		
		light.isEnabled = false
	end
end

local function unload()
	LIGHTS = {}
	STATE = false
end

-- --------------------------------------------------------------------------------
-- Game Events
M.onUpdate = function(dt_real)
	local tod = scenetree.tod
	if not tod then return end
	
	if (tod.time > 0.21 and tod.time < 0.77) == STATE then return end
	STATE = not STATE -- true = night
	
	local we_open = editor.isEditorActive()
	for _, light in ipairs(LIGHTS) do
		if not we_open or (we_open and scenetree.findObjectById(light.id)) then
			light.light.isEnabled = STATE
		end
	end
	
	for _, vehicle in ipairs(getAllVehicles()) do
		setTodInVehicle(vehicle, STATE)
	end
end

M.onVehicleSpawned = function(vehicle_id)
	setTodInVehicle(getObjectByID(vehicle_id), STATE)
end

M.onExtensionLoaded = function()
	if worldReadyState == 2 then init() end
end

M.onWorldReadyState = function(state)
	if state == 2 then init() end
end

M.onExtensionUnloaded = unload

M.onEditorDeactivated = function()
	unload()
	init()
end

return M
