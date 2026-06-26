# BeamNG-MapModules

## Usecase

The use case for this module loader can be explained given a problem.

This problem affects all map authors that add lua extensions to their maps. The regular way of archiving this is by adding lua extensions at their desired path's. Like
- `/lua/ge/extensions/*.lua` or
- `/lua/vehicle/extensions/auto/*lua`

But by doing this the map author unwillingly runs into a multitude of problems.

1) The lua extensions will be present and loaded whenever a player loads the mod. NO MATTER if the map is loaded or not. So a player having the map mod loaded but that is then joining another map, will now have the extensions present thought only to be used in just one level. This can cause errors and performance issues.

2) Another map (might be from the same author) may bring along the same lua extensions.. maybe on the same pathes. This opens up two more problems.

4) First. The games virtual file system can only have one file at a certain path. If two or more maps, or even any other mod offer the same lua extensions at the same path's then only one of them will succeed (that depends on the load order).

5) Second. Duo to this very fact: The lua extensions might be of different versions. A newer map might now be handled by older extension versions, which may simply not work with the newer map and vise versa.

However this problem can be circumvented. At map load the game looks if the level has a .lua file placed at `/levels/your_level_name/mainLevel.lua` and loads it. And on map unload automatically unloads it again. As such we can use this one lua file as the main entry and exit point to load custom lua extensions that are only to be present and loaded while the map is loaded.

This module loader is what archives that. It prevents file conflicts and makes it possible for the user of it to also "on the fly" add, remove and reload extensions without having to fully reload the lua (CTRL+L), the map or the game as a whole.


### Installation
1. Grab the file @ `/levels/your_map_name/mainLevel.lua` from this repository
2. Open your maps level folder. Navigate to `/levels/your_map_name`
3. And plaxe the `mainLevel.lua` right into it.

### Usage
General Environment (GE) lua moduls go into `/levels/your_level_name/lua`

Vehicle lua modules (VE) go into `/levels/your_level_name/vlua`

### Relatively Important Notes
Since the folder structure is different to regular GE and VE extensions you will have to load libaries, that you yourself added to your map, differently.
- A simple `local MyLib = require("libs/MyLib")` will not find it.
- You need to `local MyLib = require(mainLevel.findLib("libs/MyLib"))`
- This also works when you want to remove a lib from the package cache for a reload by `package.loaded[mainLevel.findLib("libs/MyLib")] = nil`
- `.findLib()` hasnt been well implemented in the VE extension space yet. The function there can only find libaries in the ge `lua` folder.

GE extensions are loaded at level start. As such they will receive all regular GE extension events.

VE extensions are loaded after the module loader has received the `onVehicleSpawned` event. Which happens AFTER the vehicle VM has already been initialized. As such you can only trust on the `onReset` event to load your extension. (This behaviour can currently not be changed)

GE and VE extensions are all accessible by their filename. So eg a GE extension stored at `levels/your_level_name/lua/myExtension.lua` will be available as `myExtension`

### How to reload all or an individual extension
- To reload all extensions you can do `mainLevel.reload()` you want to fire this when you add or remove entire GE or VE extensions. Will also reload THIS file, which is necessary if you edit the module loader

- To reload all GE extensions you can `mainLevel.reloadGE()`

- To reload an individual GE extension you can `mainLevel.reloadGE("extensionName")`

- To reload all VE extensions you can `mainLevel.reloadVE()`

- To reload an individual VE extension you can `mainLevel.reloadVE("extensionName")`

- If you need to reload a GE and VE extension together. Then chain the commands up and ensure you reload the VE side first to prevent load order bugs `mainLevel.reloadVE("extensionName"); mainLevel.reloadGE("extensionName")`

### Reloadability Template for GE extensions
In order to make your extensions reloadable on the fly and headache free you generally want to follow this setup.
```lua
local M = {}
local INITIALIZED = false

local function init()
	if INITIALIZED then return end
	INITIALIZED = true

	-- init your extension
	-- spawn objects you might need etc etc
end

local function unload()
	INITIALIZED = false

	-- unload your extension
	-- cleanup objects you might have handled etc etc
end

M.onUpdate = function()
	-- as with a regular GE extension, this event might fire before the level has been fully loaded. So if you are expection that objects might exist already because you are assuming that init() has been called yet, then you are going to error out. SAME time, this event might still be fired AFTER the objects have already been deleted by the game when the player triggered a level change/exit. Checking for the INITIALIZED flag here will save you from headaches.
	if not INITIALIZED then return end

	-- do whatever you need todo every frame
end

M.onExtensionLoaded = function()
	if worldReadyState == 2 then init() end -- if the extension was loaded "on the fly" then init
end

M.onWorldReadyState = function(state)
	if state == 2 then init() end -- otherwise init as usual after the world is ready
end

M.onExtensionUnloaded = unload -- will either be fired if triggered on the fly by the module loader OR at the very end of the level unloading
M.onClientEndMission = unload -- triggered as soon as the player clicks to change to another map OR on exit.

-- OPTIONAL. If your extension makes use of objects the player OR you have created via the world editor. With this event you can reload your own extension as soon as the user has exited the world editor
--M.onEditorDeactivated = function()
--	unload()
--	init()
--end

return M
```

### Examples
You can find examples in the `/levels/your_map_name/lua` and `vlua` folder