local M = {}

local IS_NIGHT = false
local TICK_TIMER = 0

local function evalLightState(force)
	local c_state = electrics.values.lights_state
	local is_seated = playerInfo.anyPlayerSeated
	local is_remote = v.mpVehicleType == 'R'
	
	-- if this is our vehicle and we arent forced to switch lights then let the player maintain full control
	if not is_remote and not force then return end
	
	-- only enable high beams on our vehicles if we are spectating it
	local state = 1
	if IS_NIGHT and is_seated then
		state = 2
	end
	
	electrics.setLightsState(state)
end

M.setState = function(state)
	IS_NIGHT = state
	evalLightState(true)
end

M.updateGFX = function(dt)
	TICK_TIMER = TICK_TIMER + dt
	if TICK_TIMER < 0.5 then return end
	TICK_TIMER = 0
	
	evalLightState()
end

return M
