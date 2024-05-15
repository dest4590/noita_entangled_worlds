dofile_once("mods/quant.ew/NoitaPatcher/load.lua")
local np = require("noitapatcher")

dofile_once( "data/scripts/lib/utilities.lua" )

np.InstallShootProjectileFiredCallbacks()
np.EnableGameSimulatePausing(false)
np.InstallDamageDetailsPatch()
np.SilenceLogs("Warning - streaming didn\'t find any chunks it could stream away...\n")

local player_fns = dofile_once("mods/quant.ew/files/src/player_fns.lua")
local net = dofile_once("mods/quant.ew/files/src/net.lua")
local util = dofile_once("mods/quant.ew/files/src/util.lua")
local ctx = dofile_once("mods/quant.ew/files/src/ctx.lua")
local pretty = dofile_once("mods/quant.ew/files/lib/pretty_print.lua")
local perk_fns = dofile_once("mods/quant.ew/files/src/perk_fns.lua")
local enemy_sync = dofile_once("mods/quant.ew/files/src/enemy_sync.lua")
local world_sync = dofile_once("mods/quant.ew/files/src/world_sync.lua")
local item_sync = dofile_once("mods/quant.ew/files/src/item_sync.lua")

ModLuaFileAppend("data/scripts/gun/gun.lua", "mods/quant.ew/files/append/gun.lua")
ModLuaFileAppend("data/scripts/gun/gun_actions.lua", "mods/quant.ew/files/append/action_fix.lua")

local my_player = nil

function OnProjectileFired(shooter_id, projectile_id, initial_rng, position_x, position_y, target_x, target_y, send_message,
    unknown1, multicast_index, unknown3)
    if not EntityHasTag(shooter_id, "player_unit") and not EntityHasTag(shooter_id, "ew_client") then
        return -- Not fired by player, we don't care about it (for now?)
    end
    EntityAddTag(projectile_id, "ew_shot_by_player")
    local projectileComponent = EntityGetFirstComponentIncludingDisabled(projectile_id, "ProjectileComponent")
    local entity_that_shot    = ComponentGetValue2(projectileComponent, "mEntityThatShot")

    local shooter_player_data = player_fns.get_player_data_by_local_entity_id(shooter_id)
    local rng = 0
    -- Was shot locally
    if shooter_id == my_player.entity then
        -- If it was an initial shot by host
        if (entity_that_shot == 0 and multicast_index ~= -1 and unknown3 == 0) then
            rng = initial_rng
            table.insert(shooter_player_data.projectile_rng_init, rng)
        else
            rng = shooter_player_data.projectile_seed_chain[entity_that_shot] + 25
        end
    else
        if (entity_that_shot == 0 and multicast_index ~= -1 and unknown3 == 0) then
            if #shooter_player_data.projectile_rng_init > 0 then
                rng = table.remove(shooter_player_data.projectile_rng_init, 1)
            else
                -- Shouldn't happen
                GamePrint("No values in projectile_rng_init")
                rng = 0
            end
        else
            rng = shooter_player_data.projectile_seed_chain[entity_that_shot] + 25
        end
    end
    shooter_player_data.projectile_seed_chain[projectile_id] = rng
    -- GamePrint("on fired "..projectile_id.." "..entity_that_shot.." "..shooter_id.." "..rng)
    np.SetProjectileSpreadRNG(rng)
end

function OnProjectileFiredPost(shooter_id, projectile_id, rng, position_x, position_y, target_x, target_y, send_message,
    unknown1, multicast_index, unknown3)
end

function OnPausedChanged(paused, is_wand_pickup)
	local players = EntityGetWithTag("player_unit") or {}

	if (players[1]) then
		np.RegisterPlayerEntityId(players[1])
		local inventory_gui = EntityGetFirstComponentIncludingDisabled(players[1], "InventoryGuiComponent")
		local controls_component = EntityGetFirstComponentIncludingDisabled(players[1], "ControlsComponent")
		if (paused) then
			--EntitySetComponentIsEnabled(players[1], inventory_gui, false)
			np.EnableInventoryGuiUpdate(false)
			np.EnablePlayerItemPickUpper(false)
			ComponentSetValue2(controls_component, "enabled", false)
		else
			--EntitySetComponentIsEnabled(players[1], inventory_gui, true)
			np.EnableInventoryGuiUpdate(true)
			np.EnablePlayerItemPickUpper(true)
			ComponentSetValue2(controls_component, "enabled", true)
		end
	end
end

-- all functions below are optional and can be left out

--[[

function OnModPreInit()
	print("Mod - OnModPreInit()") -- First this is called for all mods
end

function OnModInit()
	print("Mod - OnModInit()") -- After that this is called for all mods
end

function OnModPostInit()
	print("Mod - OnModPostInit()") -- Then this is called for all mods
end
]]--

function OnWorldInitialized() -- This is called once the game world is initialized. Doesn't ensure any world chunks actually exist. Use OnPlayerSpawned to ensure the chunks around player have been loaded or created.
	--GamePrint( "OnWorldInitialized() " .. tostring(GameGetFrameNum()) )
end



function OnPlayerSpawned( player_entity ) -- This runs when player entity has been created
	GamePrint( "OnPlayerSpawned() - Player entity id: " .. tostring(player_entity) )

    my_player = player_fns.make_playerdata_for(player_entity, ctx.my_id)
    GamePrint("My peer_id: "..ctx.my_id)
    ctx.players[ctx.my_id] = my_player
    ctx.player_data_by_local_entity[player_entity] = my_player
    ctx.ready = true

    np.SetPauseState(4)
    np.SetPauseState(0)

    local hp = util.get_ent_health(player_entity)
    util.set_ent_health(player_entity, {hp*3, hp*3})

    EntityAddTag(player_entity, "polymorphable_NOT") -- TODO

    if ctx.is_host then
        EntityAddTag(player_entity, "ew_host")
    else
        EntityAddComponent2(player_entity, "LuaComponent", {script_damage_about_to_be_received = "mods/quant.ew/files/cbs/immortal.lua"})
    end

    EntityAddComponent2(player_entity, "LuaComponent", {script_wand_fired = "mods/quant.ew/files/cbs/count_times_wand_fired.lua"})

    if ctx.debug then
        dofile_once("data/scripts/perks/perk.lua")
        local x, y = EntityGetFirstHitboxCenter(player_entity)
        perk_spawn(x, y, "LASER_AIM", true)
        perk_spawn(x-50, y, "GLASS_CANNON", true)
        perk_spawn(x-25, y, "EDIT_WANDS_EVERYWHERE", true)
    end
end

local function on_world_pre_update_inner()
    if my_player == nil then return end

    GlobalsSetValue("ew_player_rng", tostring(GameGetFrameNum()))

    net.update()

    if ctx.is_host and not EntityGetIsAlive(my_player.entity) then
        if not ctx.run_ended then
            GamePrint("Notifying of run end")
            net.proxy_notify_game_over()
            ctx.run_ended = true
        end
    end
    if not ctx.is_host then
        local hp, _ = util.get_ent_health(my_player.entity)
        if hp == 0 then
           EntityInflictDamage(my_player.entity, 10000000, "DAMAGE_CURSE", "Out of shared health", "NONE", 0, 0, GameGetWorldStateEntity())
           if not ctx.run_ended then
               GamePrint("Notifying of run end")
               net.proxy_notify_game_over()
               ctx.run_ended = true
           end
        end
    end

    -- Item sync
    if ctx.is_host then
        item_sync.host_upload_items(my_player)
    else
        item_sync.client_tick(my_player)
    end

    -- Player sync
    if GameGetFrameNum() % 1 == 0 then
        local input_data = player_fns.serialize_inputs(my_player)
        local pos_data =  player_fns.serialize_position(my_player)
        local current_slot = player_fns.get_current_slot(my_player)
        if input_data ~= nil and pos_data ~= nil then
            net.send_player_update(input_data, pos_data, current_slot)
        end
    end

    -- Enemy sync
    if GameGetFrameNum() % 2 == 1 then
        if ctx.is_host then
            net.send_enemy_data(enemy_sync.host_upload_entities())
        else
            enemy_sync.client_cleanup()
        end
    end

    -- World sync
    if ctx.is_host then
        world_sync.host_upload()
    end

    -- Health and air sync
    if ctx.is_host and GameGetFrameNum() % 4 == 3 then
        local player_info = {}
        local hp, max_hp = util.get_ent_health(my_player.entity)
        for id, player_data in pairs(ctx.players) do
            local entity = player_data.entity
            local air, max_air = util.get_ent_air(entity)
            player_info[id] = {hp, max_hp, air, max_air}
        end
        net.send_host_player_info(player_info)
    end

    -- Inventory and perk sync
    if GameGetFrameNum() % 120 == 0 then
        local inventory_state = player_fns.serialize_items(my_player)
        if inventory_state ~= nil then
            net.send_player_inventory(inventory_state)
        end
        local perk_data = perk_fns.get_my_perks()
        if perk_data ~= nil then
            net.send_player_perks(perk_data)
        end
    end
end

function OnWorldPreUpdate() -- This is called every time the game is about to start updating the world
    util.tpcall(on_world_pre_update_inner)
end

local function on_world_post_update_inner()
    local times_wand_fired = tonumber(GlobalsGetValue("ew_wand_fired", "0"))
    GlobalsSetValue("ew_wand_fired", "0")
    if times_wand_fired > 0 then
        local special_seed = tonumber(GlobalsGetValue("ew_player_rng", "0"))
        local fire_data = player_fns.make_fire_data(special_seed, my_player)
        if fire_data ~= nil then
            net.send_fire(fire_data)
        end
    end
end

function OnWorldPostUpdate() -- This is called every time the game has finished updating the world
	util.tpcall(on_world_post_update_inner)
end



function register_localizations(translation_file, clear_count)

    clear_count = clear_count or 0

    local loc_content = ModTextFileGetContent("data/translations/common.csv") -- Gets the original translations of the game

    local append_content = ModTextFileGetContent(translation_file) -- Gets my own translations file

    -- Split the append_content into lines
    local lines = {}
    for line in append_content:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    -- Remove the first clear_count lines
    for i = 1, clear_count do
        table.remove(lines, 1)
    end

    -- Reconstruct append_content after removing clear_count lines
    local new_append_content = table.concat(lines, "\n")

    -- if loc_content does not end with a new line, add one
    if not loc_content:match("\n$") then
        loc_content = loc_content .. "\n"
    end

    -- Concatenate loc_content and new_append_content without extra newline character
    local new_content = loc_content .. new_append_content .. "\n"

    -- Set the new content to the file
    ModTextFileSetContent("data/translations/common.csv", new_content)
end

function OnModPreInit()
	register_localizations("mods/quant.ew/translations.csv", 1)
    ctx.init()
    net.init()
end

function OnModPostInit()
	
end

print("entangled_worlds init ok")