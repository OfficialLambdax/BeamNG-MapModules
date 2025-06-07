-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.
local M = {}
M.version = "0.2"
M.version_release = "23.05.2025"

local FLARES = {"vehicleBrakeLightFlare", "vehicleHeadLightFlare", "vehicleReverseLightFlare"}

-- ---------------------------------------------------------------------------------------------------
-- The most likely function you use
--[[
	Scenetree tree
		/scenetree_group_name/
		/scenetree_group_name/groupname/
			put into this folder how ever many triggers or lights you want.
			Should the light contain a capital DD or NN then this light will only turn on
			at either day or night. Otherwise always.
]]
M.autoDetect = function(scenetree_group_name)
	M.wipe()
	if scenetree_group_name == nil then
		log("E", "TriggerLights", "scenetree_group_name is nil")
		return nil
	end
	local scenetree_group = scenetree[scenetree_group_name]
	if scenetree_group == nil then
		log("E", "TriggerLights", 'No Scenetree group with the name "' .. scenetree_group_name .. '"')
		return false
	end
	
	for i = 0, scenetree_group:getCount(), 1 do
		local scenetree_folder = scenetree.findObjectById(scenetree_group:idAt(i))
		if scenetree_folder:getName() == "RootGroup" then
			-- wtf is this
			
		elseif scenetree_folder:getClassName() ~= "SimGroup" then
			log("E", "TriggerLights", 'Ignoring "' .. scenetree_folder:getName() .. '". Not a folder.')
			
		else
			-- eval group restrictions
			local can_day = true
			local can_night = true
			local is_photograph = false
			if scenetree_folder:getName():find("DD") then
				can_night = false
			elseif scenetree_folder:getName():find("NN") then
				can_day = false
			end
			
			if scenetree_folder:getName():find("PP") then
				is_photograph = true
			end
			
			-- sort triggers and lights
			local group = {triggers = {}, lights = {}}
			for _, obj_name in pairs(scenetree_folder:getObjects()) do
				M.addObject(scenetree.findObject(obj_name), group, is_photograph)
			end
			
			-- register triggers
			for obj_name, _ in pairs(group.triggers) do
				if M.AUTOLIGHTS:newGroupOrAdd(scenetree_folder:getName(), obj_name, can_day, can_night) then
					log("I", "TriggerLights", 'Detected Group "' .. scenetree_folder:getName() .. '"')
				end
			end
			
			-- register lights
			for obj_name, obj_eval in pairs(group.lights) do
				local lights = M.AUTOLIGHTS:exists(scenetree_folder:getName())
				if lights == nil then
					log("E", "TriggerLights", 'Cannot add "' .. obj_name .. '" to group "' .. scenetree_folder:getName() .. '". Group is unknown. Trigger doesnt exists')
					
				else
					lights:addLight(obj_eval.reference, obj_eval.can_day, obj_eval.can_night)
				end
			end
		end
	end
	
	-- check groups
	for group_name, lights in pairs(M.AUTOLIGHTS:getAll()) do
		if lights:lightAmount() == 0 then
			log("E", "TriggerLights", 'Group "' .. group_name .. '" has no known lights')
			M.AUTOLIGHTS:remove(group_name)
			
		else
			log("I", "TriggerLights", 'Watching group "' .. group_name .. '" with ' .. lights:lightAmount() .. ' lights')
		end
	end
	
	return true
end

M.addObject = function(obj_eval, group, is_photograph)
	local object = {reference = obj_eval, can_day = true, can_night = true}
	if obj_eval:getName():find("DD") then
		object.can_night = false
	elseif obj_eval:getName():find("NN") then
		object.can_day = false
	end
	
	if obj_eval:getClassName() == "BeamNGTrigger" then
		group.triggers[obj_eval:getName()] = object
		obj_eval:setField("TriggerMode", 0, "Overlaps")
		obj_eval:setField("TriggerTestType", 0, "Bounding box")
		obj_eval:setField("luaFunction", 0, "onBeamNGTrigger")
		
	elseif obj_eval:getClassName() == "SpotLight" or obj_eval:getClassName() == "PointLight" then
		if is_photograph then
			obj_eval:setField("flareType", 0, FLARES[math.random(1, #FLARES)])
			obj_eval:setField("animationType", 0, "BlinkLightAnim")
			obj_eval:setField("animationPeriod", 0, math.random(200, 2000) / 1000)
		end
		
		group.lights[obj_eval:getName()] = object
	end
end

M.wipe = function()
	M.AUTOLIGHTS:wipe()
end

M.setAll = function(state)
	M.AUTOLIGHTS:setState(state)
end

-- ---------------------------------------------------------------------------------------------------
-- Basics
--[[ #var cannot be trusted on zero indexed tablearrays.. eg.
	local table_1 = {}
	print(#table_1) -- will show 0
	local table_2 = {}
	table_2[0] = "some value"
	print(#table_1) -- will also show 0.. fock
]] -- so we have to use this func.
M.tableSize = function(table)
	if type(table) ~= "table" then return 0 end
	local len = 0
	for _, _ in pairs(table) do
		len = len + 1
	end
	return len
end

M.split = function(string, delim)
	local t = {}
	for str in string.gmatch(string, "([^" .. delim .. "]+)") do
		table.insert(t, str)
	end
	return t
end

-- ---------------------------------------------------------------------------------------------------
-- Time of Day
M.timeOfDay = function()
    local tod = scenetree.tod
    if not tod then
		log("E", "TriggerLights", "scenetree.tod is unavailable on this map")
		return {state = 2}
	end
	
	local time_of_day = {}
	time_of_day.is_night = tod.time > 0.21 and tod.time < 0.77
	time_of_day.is_day = not time_of_day.is_night
	if time_of_day.is_night then time_of_day.state = 1 else time_of_day.state = 2 end
	time_of_day.tod = tod.time
	
	return time_of_day
end

-- ---------------------------------------------------------------------------------------------------
-- AutoLightsClass
--[[
	Format
		[int] = table
			["triggername"] = LightGroupClass
]]
M.AUTOLIGHTS = {int = {}}

function M.AUTOLIGHTS:newGroup(group_name, trigger_name, can_day, can_night)
	if not M.AUTOLIGHTS:exists(group_name) then
		self.int[trigger_name] = M.newLightGroup(group_name, can_day, can_night)
		return true
	end
	return false
end

function M.AUTOLIGHTS:newGroupOrAdd(group_name, trigger_name, can_day, can_night)
	local lights = M.AUTOLIGHTS:exists(group_name)
	if lights then
		self.int[trigger_name] = lights
		return false
	else
		self:newGroup(group_name, trigger_name, can_day, can_night)
		return true
	end
end

function M.AUTOLIGHTS:remove(group_name)
	for trigger_name, lights in pairs(self.int) do
		if lights:name() == group_name then
			self.int[trigger_name] = nil
		end
	end
end

function M.AUTOLIGHTS:wipe()
	self.int = {}
end

function M.AUTOLIGHTS:exists(group_name)
	for _, lights in pairs(self.int) do
		if lights:name() == group_name then
			return lights
		end
	end
	return nil
end

function M.AUTOLIGHTS:getAll()
	local groups = {}
	for _, lights in pairs(self.int) do
		if groups[lights:name()] == nil then groups[lights:name()] = lights end
	end
	return groups
end

function M.AUTOLIGHTS:exec(trigger_eventobj)
	if self.int[trigger_eventobj.triggerName] then
		self.int[trigger_eventobj.triggerName]:setContains(trigger_eventobj)
	end
end

function M.AUTOLIGHTS:setState(state)
	for _, lights in pairs(self:getAll()) do
		lights:setStateForce(state)
	end
end
-- ---------------------------------------------------------------------------------------------------
-- LightGroupClass
--[[
	Format
		[int] = table
			[group_name] = string
			[contains] = table
				["game_vehicle_id"] = true
								if this vehicle is in any of the attached triggers of this light group.
								if tableSize() > 0 then lights on, else lights off
			[state] = bool (lights are on or off)
			[lights] = table
				["light_name"] = LightClass
			[time_restrictions] = table
				[1] = bool (night)
				[2] = bool (day)
]]
M.newLightGroup = function(group_name, can_day, can_night)
	local lights = {int = {group_name = group_name, contains = {}, state = false, lights = {}, time_restrictions = {can_night, can_day}}}
	
	function lights:addLight(reference, can_day, can_night)
		self.int.lights[reference:getName()] = M.newLight(reference, can_day, can_night)
	end
	
	function lights:remLight(reference)
		self.int.lights[reference:getName()] = nil
	end
	
	function lights:lightAmount()
		return M.tableSize(self.int.lights)
	end
	
	function lights:setState(state, time_of_day)
		if time_of_day == nil then time_of_day = M.timeOfDay() end
		if self.int.state == state then return end
		
		-- always allow disable, only allow enable if not restricted
		if state == false or (state and self.int.time_restrictions[time_of_day.state]) then
			for _, light in pairs(self.int.lights) do
				light:setState(state, time_of_day)
			end
			self.int.state = state
		end
	end
	
	function lights:setStateForce(state)
		for _, light in pairs(self.int.lights) do
			light:setStateForce(state)
		end
		self.int.state = state
	end
	
	function lights:setContains(trigger_eventobj)
		if trigger_eventobj.event == "enter" then
			self.int.contains[trigger_eventobj.subjectID] = true
		elseif trigger_eventobj.event == "exit" then
			self.int.contains[trigger_eventobj.subjectID] = nil
		end
		
		-- enable/disable light
		self:setState(self:containsAmount() > 0, M.timeOfDay())
	end
	
	function lights:contains()
		return self.int.contains
	end
	
	function lights:containsAmount()
		return M.tableSize(self:contains())
	end
	
	function lights:name()
		return self.int.group_name
	end
	
	return lights
end

-- ---------------------------------------------------------------------------------------------------
-- LightClass
--[[
	Format
		[int] = table
			[ref] = Obj (reference to the scenetree light object)
			[state] = bool (light is on or off)
			[time_restrictions] = table
				[1] = bool (night)
				[2] = bool (day)
			[id] = number
]]
M.newLight = function(reference, can_day, can_night)
	local light = {int = {ref = reference, state = false, time_restrictions = {can_night, can_day}}}
	reference:setLightEnabled(false) -- init as false
	
	function light:setState(state, time_of_day)
		if self.int.state == state then return end
		
		-- always allow disable, only allow enable if not restricted
		if state == false or (state and self.int.time_restrictions[time_of_day.state]) then
			self.int.ref:setLightEnabled(state)
			self.int.state = state
		end
	end
	
	function light:setStateForce(state)
		if self.int.state == state then return end
		self.int.ref:setLightEnabled(state)
		self.int.state = state
	end
	
	return light
end

-- ---------------------------------------------------------------------------------------------------
-- Events
local function onExtensionLoaded()
	if worldReadyState == 2 then
		M.autoDetect("triggerlights")
	end
end

local function onWorldReadyState(state)
	if state == 2 then
		M.autoDetect("triggerlights")
	end
end

local function onBeamNGTrigger(trigger_eventobj)
	M.AUTOLIGHTS:exec(trigger_eventobj)
end

local function onEditorDeactivated()
	M.autoDetect("triggerlights")
end

M.onBeamNGTrigger = onBeamNGTrigger
M.onInit = function() setExtensionUnloadMode(M, "manual") end
M.onWorldReadyState = onWorldReadyState
M.onExtensionLoaded = onExtensionLoaded
M.onEditorDeactivated = onEditorDeactivated
return M