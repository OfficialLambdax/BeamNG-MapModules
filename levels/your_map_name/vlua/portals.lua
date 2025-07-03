--[[
	This is a rewrite of stefan750's airStabilizer Script by Neverless.
	Goal was to follow the garbage collection suggestions https://documentation.beamng.com/modding/programming/performance/#avoid-garbage-collection
]]


local M = {}

local ENABLED = false

local min, max = math.min, math.max

local PITCH_PID = newPIDParallel(2, 0, 2)
local ROLL_PID = newPIDParallel(2, 0, 2)

local VARBUF = {}

M.setState = function(state)
	ENABLED = state
end

M.onExtensionLoaded = function()
	enablePhysicsStepHook()
end

M.onReset = function()
	PITCH_PID:reset()
	ROLL_PID:reset()
	
	obj:queueGameEngineLua('portals.onVehicleReset(' .. obj:getId() .. ')')
end

VARBUF.onPhysicsStep = {
	vec3(), -- veh_dir
	vec3(), -- veh_udir
	quat(), -- veh_rot
	vec3(), -- veh_pos
	vec3(), -- cog
	vec3(), -- ang_vel_local
	vec3(), -- ang_vel
	vec3(), -- veh_vel
	vec3(), -- tmp_vec1
	vec3(), -- veh_vel_dir
	vec3(), -- tmp_vec2
	vec3(), -- ray_start
	vec3(), -- impulse
	vec3() -- torque
}
M.onPhysicsStep = function(dt)
	if not ENABLED then return end
	
	for _, wheel in pairs(wheels.wheels) do
		if not wheel.isBroken and wheel.downForceRaw > 0 then return end
	end
	
	local veh_dir, veh_udir, veh_rot, veh_pos, cog, ang_vel_local, ang_vel, veh_vel, tmp_vec1, veh_vel_dir, tmp_vec2, ray_start, impulse, torque = unpack(VARBUF.onPhysicsStep)
	
	veh_dir:set(obj:getDirectionVectorXYZ())
	veh_udir:set(obj:getDirectionVectorUpXYZ())
	
	tmp_vec1:set(-veh_dir.x, -veh_dir.y, -veh_dir.z)
	veh_rot:setFromDir(tmp_vec1, veh_udir)
	
	local veh_cpos = obj:getCenterPosition() -- has no XYZ
	veh_pos:set(obj:getPositionXYZ())
	cog:set(veh_cpos)
	cog:setSub(veh_pos)
	
	ang_vel_local:set(obj:getPitchAngularVelocity(), obj:getRollAngularVelocity(), obj:getYawAngularVelocity())
	ang_vel:set(ang_vel_local)
	ang_vel:setRotate(veh_rot)
	
	tmp_vec1:set(cog)
	tmp_vec1:setCross(tmp_vec1, ang_vel)
	veh_vel:set(obj:getVelocityXYZ())
	veh_vel:setAdd(tmp_vec1)
	
	local roll, pitch, yar = obj:getRollPitchYaw()
	
	-- Fall damping
	local speed = veh_vel:length()
	veh_vel_dir:set(veh_vel)
	veh_vel_dir:normalize()
	local fall_damp_force, ray_len, height = 0, 0, 0
	
	for _, wheel in pairs(wheels.wheels) do
		if not wheel.isBroken then
			-- veh_pos - cog + node_pos
			local node_pos = obj:getNodePosition(wheel.node1) -- has no XYZ
			node_pos:setAddXYZ(0, 0, -wheel.radius + 0.05)
			ray_start:set(veh_cpos)
			ray_start:setSub(cog)
			ray_start:setAdd(node_pos)
			
			ray_len = speed * 0.05
			height = obj:castRayStatic(ray_start, veh_vel_dir, ray_len)
			
			fall_damp_force = max(fall_damp_force, (ray_len - height) / guardZero(ray_len))
			
			--obj.debugDrawProxy:drawLine(ray_start, ray_start + veh_vel_dir*ray_len, color(0, 0, 255, 255))
			--obj.debugDrawProxy:drawSphere(0.2, ray_start, color(0, 0, 255, 255))
		end
	end
	
	-- Calculate final impulse
	impulse:set(0, 0, max(fall_damp_force * 70 * -veh_vel.z, 0))
	
	-- Stabilize pitch and roll
	local pitch_torque = PITCH_PID:get(pitch, 0, dt)
	local roll_torque = ROLL_PID:get(-roll, 0, dt)
	
	-- Calculate final torque
	torque:set(
		pitch_torque,
		roll_torque,
		-ang_vel_local.z * 5
	)
	torque:setRotate(veh_rot)
	torque:set(-torque.x, -torque.y, -torque.z)
	
	tmp_vec1:set(cog)
	tmp_vec1:setCross(tmp_vec1, torque)
	tmp_vec2:set(impulse)
	tmp_vec2:setAdd(tmp_vec1)
	obj:applyClusterLinearAngularAccel(v.data.refNodes and v.data.refNodes[0].ref or 0, tmp_vec2, torque)
end


return M
