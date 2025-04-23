-- Made by Neverless @ BeamMP. Problems, Questions or requests? Feel free to ask.
--[[
	Todo
		- Vehicle reset should quit transitions
		- Sound effects
	
	Credits
		- Zeit for the help with the flight rotation in the mfd discord
		- Olrosse for further help with the rotation code, code examples and ideas
]]

local M = {}

local ROOT_GROUP = "Portals"
local DEFAULT_PORTAL_SCALE = vec3(3, 3, 3)
local DEFAULT_PORTAL_Z_OFFSET = vec3(0, 0, 1)

local TRANSITION_PATH_SPEED = 30
local TRANSITION_PATH_SPEED_FINAL = TRANSITION_PATH_SPEED / 2

local RENDER_RANGE_PORTAL = 150

local COLOR_PORTAL_TELEPORTER = Point4F(0, 0.5, 1, 0.8)
local COLOR_PORTAL_PATHER = Point4F(0.4, 0, 0.6, 0.8)

local PATH_DYN_FIELD = "point"
local PATH_TRIGGER_DYN_FIELD = "start"
local PATH_WAYPOINT_CONTAINER_DYN_FIELD = "path"
local PORTAL_DISABLED_DYN_FIELD = "disabled"
local PORTAL_HIDDEN_DYN_FIELD = "p_hidden" -- "hidden" is taken by the game

local DEBUG_RENDER_PATH = false
local DEBUG_PORTAL_LINKS = false
local DEBUG_PORTAL_TYPES = false

local COLOR_PORTAL_TELEPORTER_DBG = ColorF(COLOR_PORTAL_TELEPORTER.x, COLOR_PORTAL_TELEPORTER.y, COLOR_PORTAL_TELEPORTER.z, COLOR_PORTAL_TELEPORTER.w)
local COLOR_PORTAL_PATHER_DBG = ColorF(COLOR_PORTAL_PATHER.x, COLOR_PORTAL_PATHER.y, COLOR_PORTAL_PATHER.z, COLOR_PORTAL_PATHER.w)

--[[
	Format
	[1..n] = table (portal_group)
		[1..n] = table (portal)
			[trigger] = BeamNGTrigger ref
			[trigger_name]
			[disabled] = bool
			[base_particle]
			[dir_particles] = table
				[1..n]
		[path] = table
			[1..n] = BeamNGWaypoint ref (where the index is the id)
			[start] = portal ref
]]
local PORTALS = {}

--[[
	Format
	["trigger name"] = table
		[portal_group] = portal group ref
		[portal] = portal ref
]]
local TRIGGERS = {}

--[[
	Format
	["vehicle_id"] = table
		[mode] = int
			1 = regular teleport
			2 = path transition
		[stage] = int (mode specific)
		[portal_group] = portal group ref
		[portal] = portal ref
		[data] = if needed for the transition
]]
local TRANSITIONS = {}

local RENDER_CHECK_TIMER = 0

-- -------------------------------------------------------------------
-- Common
local function alignToSurfaceZ(pos_vec, max)
	local pos_z = be:getSurfaceHeightBelow(vec3(pos_vec.x, pos_vec.y, pos_vec.z + 2))
	if pos_z < -1e10 then return end -- "the function returns -1e20 when the raycast fails"
	if max and math.abs(pos_vec.z - pos_z) > max then return end
	
	return vec3(pos_vec.x, pos_vec.y, pos_z)
end

local function evalTPPosition(pos_vec, vehicle, factor)
	local new_pos = alignToSurfaceZ(pos_vec, 7)
	if not new_pos then return pos_vec end -- tp pos is in the air
	
	local bounding_box = vehicle:getSpawnWorldOOBB()
	local half_extends = bounding_box:getHalfExtents()
	new_pos = new_pos + vec3(0, 0, half_extends.z / (factor or 4)) -- if this ports the vehicle into the ground when damaged, reduce it to / 3
	
	return new_pos
end

local function dist3d(p1, p2)
	return math.sqrt((p2.x - p1.x)^2 + (p2.y - p1.y)^2 + (p2.z - p1.z)^2)
end

local function raycastAlongSideLine(from_vec, to_vec)
	local dir_vec = (to_vec - from_vec):normalized()
	local length = dist3d(from_vec, to_vec)
	
	local hit_dist = castRayStatic(from_vec, dir_vec, length)
	if hit_dist < length then
		return hit_dist
	end
end

local function vehicleMoveToPosition(vehicle, tar_pos, max_speed, strength_range)
	local v_pos = vehicle:getPosition()
	local v_vel = vehicle:getVelocity()
	local t_dir = (tar_pos - v_pos):normalized()
	
	local dist = dist3d(v_pos, tar_pos)
	local strength = math.min(max_speed, (dist / (strength_range or 40)) * max_speed)
	local t_vel = t_dir * strength -- intended velocity towards target
	
	local force = (t_vel - v_vel) * 0.8
	if dist > 0.3 and force:length() > 0.1 then
		if force:length() < 500 then -- force spikes can happen when the vehicle was just reset
			vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 1, force.x, force.y, force.z)
		end
	end
end

local function vehicleMoveToPosition2(dt, vehicle, tar_pos, max_speed, strength_range)
	local v_pos = vehicle:getPosition()
	local t_dir = (tar_pos - v_pos):normalized()
	
	local dist = dist3d(v_pos, tar_pos)
	max_speed = max_speed * dt
	local step_by = math.min(max_speed, (dist / strength_range) * max_speed)
	local next_pos = v_pos + (t_dir * step_by)
	
	local v_rot = quatFromDir(vehicle:getDirectionVector(), vehicle:getDirectionVectorUp())
	
	-- chance to spaz
	--local t_rot = v_rot:inversed():slerp(quatFromDir(t_dir, vec3(0, 0, 1)), 0.5) 
	
	-- direct pointing
	--local t_rot = v_rot:inversed() * quatFromDir(t_dir, vec3(0, 0, 1))
	
	-- hovering
	local t_rot = v_rot:inversed() * quatFromDir(vec3(t_dir.x, t_dir.y, 0), vec3(0, 0, 1))
	
	vehicle:setClusterPosRelRot(vehicle:getRefNodeId(), next_pos.x, next_pos.y, next_pos.z, t_rot.x, t_rot.y, t_rot.z, t_rot.w)
end

local function evalValidPortalLinks(portal_group, trigger_name)
	local portal_links = {}
	for _, portal in ipairs(portal_group) do
		if portal.trigger:getName() ~= trigger_name then
			table.insert(portal_links, portal)
		end
	end
	return portal_links
end

local function getLinkedPortal(portal_group, portal)
	local portal_name = portal.trigger:getName()
	for _, portal in ipairs(portal_group) do
		if portal.trigger:getName() ~= portal_name then
			return portal
		end
	end
end

local function vTableIsHoled(vtable)
	local index
	if vtable[1] ~= nil then index = 1 end
	if vtable[0] ~= nil then index = 0 end
	if index == nil then return true end
	local max = 0
	for _, _ in pairs(vtable) do
		max = max + 1
	end
	
	for i = index, max do
		if vtable[i] == nil then return true end
	end
	return false
end

local function getPortalPath(portal_group, portal, include_start) -- where portal is the portal to path from, towards the other
	if not portal_group.path then return end
	local portal_link = getLinkedPortal(portal_group, portal)
	local is_start = portal_group.path.start.trigger:getName() == portal.trigger:getName()
	local path = {}
	if is_start then
		if include_start then
			table.insert(path, portal.trigger:getPosition())
		end
		for _, point in ipairs(portal_group.path) do
			table.insert(path, point:getPosition())
		end
		table.insert(path, portal_link.trigger:getPosition())
	else
		if include_start then
			table.insert(path, portal.trigger:getPosition())
		end
		for i = #portal_group.path, 1, -1 do
			local point = portal_group.path[i]
			table.insert(path, point:getPosition())
		end
		table.insert(path, portal_link.trigger:getPosition())
	end
	return path
end

local function isAnyVehicleInsideRadius(pos_vec, radius, except_id)
	for _, vehicle in ipairs(getAllVehicles()) do
		if vehicle:getId() ~= except_id then
			if dist3d(vehicle:getPosition(), pos_vec) < radius then
				return true
			end
		end
	end
	return false
end

-- has beammp and is in a session. never true on server
local function isBeamMPSession()
	if MPCoreNetwork then return MPCoreNetwork.isMPSession() end
	return false
end

local function isOwn(game_vehicle_id)
	if not isBeamMPSession() then return true end
	return MPVehicleGE.isOwn(game_vehicle_id)
end

-- -------------------------------------------------------------------
-- Load / Unload
local function adjustPortal(portal)
	local trigger = portal.trigger
	local new_pos = alignToSurfaceZ(trigger:getPosition(), 7)
	if new_pos then
		new_pos = new_pos + DEFAULT_PORTAL_Z_OFFSET
	else
		new_pos = trigger:getPosition()
	end
	trigger:setPosition(new_pos)
	trigger:setScale(DEFAULT_PORTAL_SCALE)
	trigger:setField("TriggerMode", 0, "Overlaps")
	trigger:setField("TriggerTestType", 0, "Bounding box")
	trigger:setField("luaFunction", 0, "onBeamNGTrigger")
end

local function portalSetRender(portal, state)
	--if portal.outer then portal.outer:setHidden(not state) end
	if portal.inner then portal.inner:setHidden(not state) end
	if portal.inner3 then portal.inner3:setHidden(not state) end
	if portal.ring_particle then portal.ring_particle:setActive(state) end
	if portal.ring_particle2 then portal.ring_particle2:setActive(state) end
	if portal.burst_particle then portal.burst_particle:setActive(state) end
end

local function spawnPortalScene(portal, portal_group)
	if portal.hidden then return end
	local portal_pos = portal.trigger:getPosition()
	local portal_center = portal_pos + vec3(0, 0, 1)
	local portal_rot = portal.trigger:getRotation()
	local portal_name = portal.trigger:getName()
	
	-- spawn portal
	local portal_link = getLinkedPortal(portal_group, portal)
	local path = getPortalPath(portal_group, portal) or {}
	local dir = ((path[1] or portal_link.trigger:getPosition()) - portal_center):normalized()
	local obj_rot = quatFromDir(dir, vec3(0, 0, 1))
	local obj_rot_base = quatFromDir(vec3(dir.x, dir.y, 0), vec3(0, 0, 1))
	local up_vec = vec3(0, 0, 1)
	if dir.z < 0 then up_vec.z = up_vec.z * -1 end -- dirty my ass fix
	local obj_rot_particle = quatFromDir(dir:cross(vec3(0, 0, 1)):cross(dir), up_vec)
	
	local outer_color = COLOR_PORTAL_TELEPORTER
	if portal_group.path then outer_color = COLOR_PORTAL_PATHER end
	
	local obj = createObject("TSStatic")
	obj.shapeName = "/art/shapes/interface/sideMarker/checkpoint_curve_base.cdae"
	obj.useInstanceRenderData = 1
	obj.instanceColor = outer_color
	obj:setPosRot(portal_center.x, portal_center.y, portal_center.z - 0.5, obj_rot_base.x, obj_rot_base.y, obj_rot_base.z, obj_rot_base.w)
	obj.scale = vec3(2, 2, 1)
	obj:registerObject("portal_outer_" .. portal_name)
	portal.outer = obj
	
	local obj = createObject("TSStatic")
	obj.shapeName = "/art/shapes/interface/ringMarker/checkpoint_ring_finish.cdae"
	obj.useInstanceRenderData = 1
	obj.instanceColor = Point4F(1, 0.4, 0, 0.2)
	local pos_offset = portal_center + (dir * -0.15)
	obj:setPosRot(pos_offset.x, pos_offset.y, pos_offset.z, obj_rot.x, obj_rot.y, obj_rot.z, obj_rot.w)
	obj.scale = vec3(2.1, 2.1, 2.1)
	obj:registerObject("portal_inner_" .. portal_name)
	portal.inner = obj
	
	local obj = createObject("TSStatic")
	obj.shapeName = "/art/shapes/interface/ringMarker/checkpoint_ring_finish.cdae"
	obj.useInstanceRenderData = 1
	obj.instanceColor = Point4F(1, 0.4, 0, 0.5)
	local pos_offset = portal_center
	obj:setPosRot(pos_offset.x, pos_offset.y, pos_offset.z, obj_rot.x, obj_rot.y, obj_rot.z, obj_rot.w)
	obj.scale = vec3(2, 2, 2)
	obj:registerObject("portal_inner2_" .. portal_name)
	portal.inner2 = obj

	local obj = createObject("TSStatic")
	obj.shapeName = "/art/shapes/interface/ringMarker/checkpoint_ring_finish.cdae"
	obj.useInstanceRenderData = 1
	obj.instanceColor = Point4F(1, 0.4, 0, 0.8)
	local pos_offset = portal_center + (dir * 0.15)
	obj:setPosRot(pos_offset.x, pos_offset.y, pos_offset.z, obj_rot.x, obj_rot.y, obj_rot.z, obj_rot.w)
	obj.scale = vec3(1.8, 1.9, 1.9)
	obj:registerObject("portal_inner3_" .. portal_name)
	portal.inner3 = obj
	
	if portal.disabled then
		portal.inner.instanceColor = Point4F(0.5, 0, 0, 0.2)
		portal.inner2.instanceColor = Point4F(0.5, 0, 0, 0.4)
		portal.inner3.instanceColor = Point4F(0.5, 0, 0, 0.6)
		
	elseif not portal.disabled then
		-- create particle ring
		local obj = createObject("ParticleEmitterNode")
		obj:setField("emitter", 0, "Portal_Ring")
		obj.useInstanceRenderData = 1
		obj.scale = vec3(1, 1, 1)
		obj:setField("dataBlock", 0, "lightExampleEmitterNodeData1")
		obj:setField("Velocity", 0, 0)
		local pos_offset = portal_center
		obj:setPosRot(pos_offset.x, pos_offset.y, pos_offset.z, obj_rot_particle.x, obj_rot_particle.y, obj_rot_particle.z, obj_rot_particle.w)
		obj:registerObject('portal_ring_' .. portal_name)
		portal.ring_particle = obj
		
		local obj = createObject("ParticleEmitterNode")
		obj:setField("emitter", 0, "Portal_Ring")
		obj.useInstanceRenderData = 1
		obj.scale = vec3(1, 1, 1)
		obj:setField("dataBlock", 0, "lightExampleEmitterNodeData1")
		obj:setField("Velocity", 0, 0)
		local pos_offset = portal_center + (dir * 0.05)
		obj:setPosRot(pos_offset.x, pos_offset.y, pos_offset.z, obj_rot_particle.x, obj_rot_particle.y, obj_rot_particle.z, obj_rot_particle.w)
		obj:registerObject('portal_ring2_' .. portal_name)
		portal.ring_particle2 = obj
		
		-- create particle burst
		if not raycastAlongSideLine(portal_center, portal_center + (dir * 5)) then
			local obj = createObject("ParticleEmitterNode")
			obj:setField("emitter", 0, "Portal_Burst")
			obj.useInstanceRenderData = 1
			obj.scale = vec3(1, 1, 1)
			obj:setField("dataBlock", 0, "lightExampleEmitterNodeData1")
			obj:setField("Velocity", 0, 0)
			obj:setPosRot(portal_center.x, portal_center.y, portal_center.z, obj_rot_particle.x, obj_rot_particle.y, obj_rot_particle.z, obj_rot_particle.w)
			obj:registerObject('portal_burst_' .. portal_name)
			portal.burst_particle = obj
		end
	end
	
	portalSetRender(portal, false)
end

local function despawnPortalScene(portal)
	-- dont delete the trigger
	if portal.outer then portal.outer:delete() end
	if portal.inner then portal.inner:delete() end
	if portal.inner2 then portal.inner2:delete() end
	if portal.inner3 then portal.inner3:delete() end
	if portal.ring_particle then portal.ring_particle:delete() end
	if portal.ring_particle2 then portal.ring_particle2:delete() end
	if portal.burst_particle then portal.burst_particle:delete() end
end

local function loadFromRootGroup()
	local root_group = scenetree[ROOT_GROUP]
	if root_group == nil then
		log("E", "Portals", 'No Scenetree group or prefab with the name "' .. ROOT_GROUP .. '"')
		return false
	end
	
	local class_name = root_group:getClassName()
	if class_name ~= "SimGroup" then
		if class_name == "Prefab" then
			root_group = root_group:getChildGroup()
		else
			log("E", "Portals", 'No Scenetree group or prefab with the name "' .. ROOT_GROUP .. '"')
			return
		end
	end
	
	-- learn of all portal groups
	for i = 0, root_group:getCount() do
		local sim_group = scenetree.findObjectById(root_group:idAt(i))
		
		if sim_group:getClassName() == "SimGroup" and sim_group:getName() ~= "RootGroup" then
			local portal_group = {}
			local path
			
			-- learn of the portal points
			for id = 0, sim_group:getCount() do
				local obj = scenetree.findObjectById(sim_group:idAt(id))
				local class_name = obj:getClassName()
				if class_name == "BeamNGTrigger" then
					table.insert(portal_group, {
						trigger = obj,
						trigger_name = obj:getName(),
						sfx = nil,
						particle = nil,
						disabled = obj:getDynDataFieldbyName(PORTAL_DISABLED_DYN_FIELD, 0) ~= nil,
						hidden = obj:getDynDataFieldbyName(PORTAL_HIDDEN_DYN_FIELD, 0) ~= nil
					})
				elseif class_name == "SimGroup" and obj:getName():find(PATH_WAYPOINT_CONTAINER_DYN_FIELD) then
					path = obj -- dealt with later
				end
			end
			
			if #portal_group ~= 2 then
				log('E', "Portals", 'No, to many or not enough triggers in group "' .. sim_group:getName() .. '" to generate a portal')
				
			else
				if not path then
					table.insert(PORTALS, portal_group)
					
				else -- learn of optional path
					portal_group.path = {}
					local has_error = false
					for id = 0, path:getCount() do
						local obj = scenetree.findObjectById(path:idAt(id))
						if obj:getClassName() == "BeamNGWaypoint" then
							local path_id = tonumber(obj:getDynDataFieldbyName(PATH_DYN_FIELD, 0))
							if path_id == nil then
								log('E', "Portals", 'Waypoint "' .. obj:getName() .. '" has no dynfield of "' .. PATH_DYN_FIELD .. '"')
								has_error = true
								break
								
							else
								if portal_group.path[path_id] ~= nil then
									log('E', "Portals", 'Waypoint "' .. obj:getName() .. '" path index is already taken!')
									has_error = true
									break
									
								else
									portal_group.path[path_id] = obj
								end
							end
						end
					end
					
					if not has_error then
						-- check for holes in path
						if vTableIsHoled(portal_group.path) or portal_group.path[0] ~= nil or #portal_group.path == 0 then
							dump(vTableIsHoled(portal_group.path))
							log('E', "Portals", 'Path is empty or has holes. Make sure a path starts at 1 and has no missing indexies')
							
						else
							-- check for origin portal
							for _, portal in ipairs(portal_group) do
								if portal.trigger:getDynDataFieldbyName(PATH_TRIGGER_DYN_FIELD, 0) then
									if portal_group.path.start then
										log('E', "Portals", 'Starting portal for the path is already taken. Ensure only one has the "' .. PATH_TRIGGER_DYN_FIELD .. '" field')
										has_error = true
									else
										portal_group.path.start = portal
									end
								end
							end
							
							if not portal_group.path.start then
								log('E', "Portals", 'There is no portal that has the "' .. PATH_TRIGGER_DYN_FIELD .. '" field')
								has_error = true
							end
							
							if not has_error then
								table.insert(PORTALS, portal_group)
							end
						end
					end
				end
			end
		end
	end
	
	-- link portals to the trigger names and adjust the triggers
	for _, portal_group in ipairs(PORTALS) do
		for _, portal in ipairs(portal_group) do
			-- link groups to trigger names
			TRIGGERS[portal.trigger:getName()] = {portal_group = portal_group, portal = portal}
			
			-- adjust triggers
			adjustPortal(portal)
			
			-- spawn portal
			spawnPortalScene(portal, portal_group)
		end
	end
end

local function init()
	loadJsonMaterialsFile("art/shapes/portals/particles/portalParticleData.json")
	loadJsonMaterialsFile("art/shapes/portals/particles/portalEmitterData.json")
	loadFromRootGroup()
end

local function unload()
	for vehicle_id, transition in pairs(TRANSITIONS) do
		local vehicle = getObjectByID(vehicle_id)
		if vehicle then
			vehicle:queueLuaCommand("obj:setGhostEnabled(false)")
			vehicle:setMeshAlpha(1, "", false)
		end
		if transition.spotlight then transition.spotlight:delete() end
	end
	
	for _, portal_group in ipairs(PORTALS) do
		for _, portal in ipairs(portal_group) do
			despawnPortalScene(portal)
		end
	end
	PORTALS = {}
	TRIGGERS = {}
	TRANSITIONS = {}
end

-- -------------------------------------------------------------------
-- Render
local function evalRenderPipe()
	local reload = false
	local cam_pos = core_camera:getPosition() or vec3(0, 0, 0)
	for _, portal_group in ipairs(PORTALS) do
		for _, portal in ipairs(portal_group) do
			if not scenetree.findObject(portal.trigger_name) then
				-- if object was deleted
				reload = true
			else
				portalSetRender(portal, dist3d(portal.trigger:getPosition(), cam_pos) < RENDER_RANGE_PORTAL)
			end
		end
		
		-- todo
		--for _, point in ipairs(portal_group.path) do
			
		--end
	end
	
	if reload then
		unload()
		init()
	end
end

-- -------------------------------------------------------------------
-- Transition
local function engageTransition(portal_group, portal, vehicle_id)
	local path = getPortalPath(portal_group, portal)
	if not path then -- if tp
		TRANSITIONS[vehicle_id] = {
			mode = 1,
			stage = 1,
			portal_group = portal_group,
			portal = portal,
			data = {}
		}
	else -- if path
		TRANSITIONS[vehicle_id] = {
			mode = 2,
			stage = 1,
			portal_group = portal_group,
			portal = portal,
			data = {
				path = path,
			}
		}
	end
end

local function teleportTransition(transition, vehicle)
	local data = transition.data
	local is_own = isOwn(vehicle:getId())
	if transition.stage == 1 then
		vehicle:queueLuaCommand("obj:setGhostEnabled(true)")
		vehicle:setMeshAlpha(0.5, "", false)
		
		data.timer = hptimer()
		transition.stage = 2
		
	elseif transition.stage == 2 then
		if data.timer:stop() < 500 then
			if is_own then
				vehicleMoveToPosition(vehicle, transition.portal.trigger:getPosition() + vec3(0, 0, 1), 100)
			end
			return
		end
		transition.stage = 3
		
	elseif transition.stage == 3 then
		if is_own then
			local portal_link = getLinkedPortal(transition.portal_group, transition.portal)
			local pos_vec = evalTPPosition(portal_link.trigger:getPosition(), vehicle)
			--vehicle:setPositionNoPhysicsReset(pos_vec)
			vehicle:setClusterPosRelRot(vehicle:getRefNodeId(), pos_vec.x, pos_vec.y, pos_vec.z + 0.2, 0, 0, 0, 0)
			local vel = -vehicle:getVelocity()
			vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 1, vel.x, vel.y, vel.z)
		end
		data.timer:stopAndReset()
		transition.stage = 4
		
	elseif transition.stage == 4 then
		if data.timer:stop() < 5000 then
			return
		end
		if isAnyVehicleInsideRadius(vehicle:getPosition(), 5, vehicle:getId()) then return end
		vehicle:queueLuaCommand("obj:setGhostEnabled(false)")
		vehicle:setMeshAlpha(1, "", false)
		return true
	end
end

local function pathTransition(transition, vehicle, dt)
	local data = transition.data
	local is_own = isOwn(vehicle:getId())
	if transition.stage == 1 then
		vehicle:queueLuaCommand("obj:setGhostEnabled(true)")
		
		local obj = createObject("SpotLight")
		obj.useInstanceRenderData = 1
		obj.color = COLOR_PORTAL_PATHER
		obj.isEnabled = true
		obj:setField("flareType", 0, "SunFlareExample")
		obj.range = 20
		obj.innerAngle = 40
		obj.outerAngle = 45
		obj.brightness = 1
		obj.castShadows = false
		local pos = vehicle:getPosition()
		local rot = quatFromDir(vec3(0, 0, -1), vec3(0, 0, -1))
		obj:setPosRot(pos.x, pos.y, pos.z + 10, rot.x, rot.y, rot.z, rot.w)
		obj:registerObject("transition_light_" .. vehicle:getId())
		transition.spotlight = obj
		
		-- this is alot smoother but there is a chance that the vehicle clashes with the ground on last node because of the release spazz
		--data.path[#data.path] = evalTPPosition(data.path[#data.path], vehicle, 3)
		data.timer = hptimer()
		transition.stage = 2
		
	elseif transition.stage == 2 then
		if data.timer:stop() < 500 then
			if is_own then
				vehicleMoveToPosition(vehicle, transition.portal.trigger:getPosition() + vec3(0, 0, 1), 100)
			end
			return
		end
		if is_own then
			local vel = -vehicle:getVelocity()
			vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 1, vel.x, vel.y, vel.z)
		end
		data.to_pos = data.path[1]
		data.to_id = 1
		transition.stage = 3
		
	elseif transition.stage == 3 then
		transition.spotlight:setPosition(vehicle:getPosition() + vec3(0, 0, 10))
		local dist = dist3d(vehicle:getPosition(), data.to_pos)
		if data.to_id < #data.path then
			if dist > 1 then
				--if is_own then
					vehicleMoveToPosition2(dt, vehicle, data.to_pos, TRANSITION_PATH_SPEED, 3)
				--end
				return
			else
				data.to_id = data.to_id + 1
				data.to_pos = data.path[data.to_id]
				return
			end
			
		else -- final node
			if dist > 12 then
				--if is_own then
					vehicleMoveToPosition2(dt, vehicle, data.to_pos, TRANSITION_PATH_SPEED, 20)
				--end
			elseif dist > 1 then -- we must switch to scaleadd before arrival because setClusterPosRelRot most often releases alot of spazz leading to vehicle destruction once the effect is stopped
				--if is_own then
					vehicleMoveToPosition(vehicle, data.to_pos, TRANSITION_PATH_SPEED_FINAL, 5)
				--end
			else
				transition.stage = 4
			end
		end
	
	elseif transition.stage == 4 then
		--if is_own then
			local pos_vec = evalTPPosition(data.to_pos, vehicle)
			local v_pos = vehicle:getPosition()
			local t_dir = (pos_vec - v_pos):normalized()
			local v_rot = quatFromDir(vehicle:getDirectionVector(), vehicle:getDirectionVectorUp())
			local t_rot = v_rot:inversed() * quatFromDir(vec3(t_dir.x, t_dir.y, 0), vec3(0, 0, 1))
			vehicle:setClusterPosRelRot(vehicle:getRefNodeId(), pos_vec.x, pos_vec.y, pos_vec.z + 0.2, t_rot.x, t_rot.y, t_rot.z, t_rot.w)
			local vel = -vehicle:getVelocity()
			vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 1, vel.x, vel.y, vel.z)
		--end
		transition.spotlight:delete()
		vehicle:setMeshAlpha(0.5, "", false)
		data.timer:stopAndReset()
		transition.stage = 6
	
	elseif transition.stage == 6 then
		if data.timer:stop() < 5000 then
			return
		end
		if isAnyVehicleInsideRadius(vehicle:getPosition(), 5, vehicle:getId()) then return end
		vehicle:queueLuaCommand("obj:setGhostEnabled(false)")
		vehicle:setMeshAlpha(1, "", false)
		return true
	end
end

-- -------------------------------------------------------------------
-- Custom events
M.toggleDbgPaths = function()
	DEBUG_RENDER_PATH = not DEBUG_RENDER_PATH
end

M.toggleDbgLinks = function()
	DEBUG_PORTAL_LINKS = not DEBUG_PORTAL_LINKS
end

M.toggleDbgTypes = function()
	DEBUG_PORTAL_TYPES = not DEBUG_PORTAL_TYPES
end

-- -------------------------------------------------------------------
-- Game events
local function drawPath(portal_group, include_dbg)
	if not portal_group.path then return end
	local path = getPortalPath(portal_group, portal_group.path.start, false)
	local start_pos = portal_group.path.start.trigger:getPosition() + DEFAULT_PORTAL_Z_OFFSET
	if include_dbg then
		debugDrawer:drawSphere(start_pos, 0.2, ColorF(0,1,0,1))
		debugDrawer:drawText(start_pos + vec3(0, 0, 2), "Path start", ColorF(0,1,0,1))
	end
	local last_pos = start_pos
	for index, pos in ipairs(path) do
		debugDrawer:drawLine(last_pos, pos, COLOR_PORTAL_PATHER_DBG)
		if include_dbg then
			debugDrawer:drawSphere(pos, 0.1, ColorF(1,1,1,1))
			debugDrawer:drawText(pos + vec3(0, 0, 2), index, ColorF(0,1,0,1))
		end
		last_pos = pos
	end
end

M.onPreRender = function()
	if DEBUG_RENDER_PATH then
		for _, portal_group in ipairs(PORTALS) do
			drawPath(portal_group, true)
		end
	end
	
	if DEBUG_PORTAL_LINKS then
		for _, portal_group in ipairs(PORTALS) do
			local p1 = portal_group[1].trigger:getPosition() + DEFAULT_PORTAL_Z_OFFSET
			local p2 = portal_group[2].trigger:getPosition() + DEFAULT_PORTAL_Z_OFFSET
			
			--debugDrawer:drawSphere(p1, 0.1, ColorF(1,1,1,1))
			--debugDrawer:drawSphere(p2, 0.1, ColorF(1,1,1,1))
			if portal_group.path then
				drawPath(portal_group, false)
			else
				debugDrawer:drawLine(p1, p2, COLOR_PORTAL_TELEPORTER_DBG)
			end
			
		end
	end
	
	if DEBUG_PORTAL_TYPES then
		for _, portal_group in ipairs(PORTALS) do
			for _, portal in ipairs(portal_group) do
				local pos = portal.trigger:getPosition() + DEFAULT_PORTAL_Z_OFFSET
				
				local type = "TP Portal"
				local color = COLOR_PORTAL_TELEPORTER
				if portal_group.path then
					type = "Path Portal"
					color = COLOR_PORTAL_PATHER
				end
				debugDrawer:drawText(pos, type, color)
				
				if portal.disabled then
					debugDrawer:drawText(pos + vec3(0, 0, 0.3), "D", ColorF(1,0,0,1))
				end
				if portal.hidden then
					debugDrawer:drawText(pos + vec3(0, 0, 0.6), "H", ColorF(1,1,1,1))
				end
			end
		end
	end
end

M.onUpdate = function(dt)
	RENDER_CHECK_TIMER = RENDER_CHECK_TIMER + dt
	if RENDER_CHECK_TIMER > 0.5 then
		RENDER_CHECK_TIMER = 0
		evalRenderPipe()
	end
	
	for vehicle_id, transition in pairs(TRANSITIONS) do
		local vehicle = getObjectByID(vehicle_id)
		if not vehicle then
			if transition.spotlight then transition.spotlight:delete() end
			TRANSITIONS[vehicle_id] = nil
			
		else
			if transition.mode == 1 then
				if teleportTransition(transition, vehicle) then
					TRANSITIONS[vehicle_id] = nil
				end
				
			elseif transition.mode == 2 then
				if pathTransition(transition, vehicle, dt) then
					TRANSITIONS[vehicle_id] = nil
				end
			end
		end
	end
end

M.onExtensionLoaded = function()
	init()
end

M.onExtensionUnloaded = function()
	unload()
end

M.onClientEndMission = function()
	unload()
end

M.onBeamNGTrigger = function(data)
	local known = TRIGGERS[data.triggerName]
	if known and data.event == "enter" then
		if not TRANSITIONS[data.subjectID] and not known.portal.disabled then
			engageTransition(known.portal_group, known.portal, data.subjectID)
		end
	end
end


return M
