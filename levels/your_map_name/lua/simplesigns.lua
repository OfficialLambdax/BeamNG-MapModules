
local M = {}

local ROOT_GROUP = "SimpleSigns"
local OBJ_DYN_TEXT = "text"
local TEXT_COLOR = ColorF(0, 0, 0, 1)
local BACK_COLOR = ColorI(255, 255, 255, 127)
local TEXT_FADE_MIN = 10
local TEXT_FADE_MAX = 30

--[[
	Format
	[1..n] = table
		[pos] = vec3
		[text] = String
]]
local SIGNS = {}

local VARBUF = {}

-- --------------------------------------------------------------------------------
-- Common
local function dist3d(p1, p2)
	return math.sqrt((p2.x - p1.x)^2 + (p2.y - p1.y)^2 + (p2.z - p1.z)^2)
end

local function adaptColor(from, into)
	into.r = from.r
	into.g = from.g
	into.b = from.b
	into.a = from.a
end

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

-- --------------------------------------------------------------------------------
-- Load / Unload
local function init()
	local root_group = scenetree[ROOT_GROUP]
	if root_group == nil then
		log('E', 'SimpleSigns', 'No scentree group or prefab with the name "' .. ROOT_GROUP .. '"')
		return
	end
	
	local class_name = root_group:getClassName()
	if class_name ~= "SimGroup" then
		if class_name == "Prefab" then
			root_group = root_group:getChildGroup()
		else
			log('E', 'SimpleSigns', 'No scenetree group or prefab with name "' .. ROOT_GROUP .. '"')
			return
		end
	end
	
	local signs = findAllObjectsInSimgroupOfTypeRecursive(root_group, 'BeamNGWaypoint')
	for _, sign in ipairs(signs) do
		local text = sign:getDynDataFieldbyName(OBJ_DYN_TEXT, 0)
		if text == nil then
			log('E', 'SimpleSigns', 'Sign "' .. sign:getName() .. '" has no Dyn field "' .. OBJ_DYN_TEXT .. '"')
		else
			table.insert(SIGNS, {
				pos = sign:getPosition(),
				text = text
			})
		end
	end
end

local function unload()
	SIGNS = {}
end

-- --------------------------------------------------------------------------------
-- Game Events
VARBUF.onUpdate = {ColorF(0, 0, 0, 0), ColorI(0, 0, 0, 0)}
M.onUpdate = function()
	local cam_pos = core_camera:getPosition()
	if not cam_pos then return end
	
	local text_color, back_color = unpack(VARBUF.onUpdate)
	
	for _, sign in ipairs(SIGNS) do
		adaptColor(TEXT_COLOR, text_color)
		adaptColor(BACK_COLOR, back_color)
		
		local dist = dist3d(sign.pos, cam_pos)
		if dist < TEXT_FADE_MAX then
			local fade = 1
			if dist > TEXT_FADE_MIN then
				fade = 1 - math.min(1, ((dist - TEXT_FADE_MIN) / (TEXT_FADE_MAX / 2)) * 1)
			end
			text_color.a = text_color.a * fade
			back_color.a = back_color.a * fade
			
			debugDrawer:drawTextAdvanced(
				sign.pos,
				' ' .. sign.text,
				text_color, -- text color
				true, -- draw background
				false, -- unknown
				back_color
			)
		end
	end
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
