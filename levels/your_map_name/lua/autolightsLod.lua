-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.
local M = {
	_VERSION = "0.3" -- 31.07.2026 (DD.MM.YYYY)
}
local ROOT_GROUP = 'autolights'

--[[
	Format
	[1..n] = table
		[light] = obj
		[pos] = vec3
		[id] = int
		[type] = int
			0 = PointLight
			1 = SpotLight
]]
local LIGHTS = {}
local STATE = false
local PERMA_LIGHT = false
local INITIALIZED = false

--[[
	Spotlights have half the distance usually .. and PointLights sometimes as well (unknown as of why and when)
	Settings name: GraphicClusteredQuality
]]
local DISTANCES = {
	Ultra = 7500,
	High = 5000,
	Normal = 3700,
	Low = 3000,
	Lowest = 3000
}

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
-- Job
local function lightRunnerJob(job)
	local cam_pos = vec3()
	while INITIALIZED do
		job.yield()
		local max_distance = (DISTANCES[settings.getValue("GraphicClusteredQuality")] or DISTANCES.Normal) / 2
		local tod = scenetree.tod
		if tod then
			local do_light = PERMA_LIGHT or isNight(tod)
			if do_light ~= STATE then -- if day/night has changed
				STATE = do_light
				for _, light in ipairs(LIGHTS) do
					if scenetree.findObjectById(light.id) then -- check if instance is still valid
						light.light.isEnabled = STATE
					end
				end

				for _, vehicle in ipairs(getAllVehicles()) do
					setTodInVehicle(vehicle, STATE)
				end

			elseif do_light then
				cam_pos:set(core_camera.getPositionXYZ())
				for index, light in ipairs(LIGHTS) do
					if (index % 50) == 0 then
						job.yield()
						cam_pos:set(core_camera.getPositionXYZ())
					end

					if scenetree.findObjectById(light.id) then
						--local dist = max_distance
						--if light.type == 1 then dist = dist / 2 end
						--local do_on = cam_pos:dist(light.pos) < dist
						local do_on = cam_pos:distance(light.pos) < max_distance

						if light.light.isEnabled ~= do_on then
							light.light.isEnabled = do_on
						end
					end
				end
			end
		end
	end
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
			pos = light:getPosition(),
			id = light:getId(),
			type = light:getClassName() == "PointLight" and 0 or 1
		})
		
		light.isEnabled = false
	end

	core_jobsystem.create(lightRunnerJob, 0)
	INITIALIZED = true
end

local function unload()
	LIGHTS = {}
	STATE = false
	INITIALIZED = false
end

-- --------------------------------------------------------------------------------
-- Game Events
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
