minetest.log("info", "[monoidal_effects] Loading mod")

monoidal_effects = {}

local mod_path = minetest.get_modpath("monoidal_effects") .. "/"
local world_path = minetest.get_worldpath() .. "/"
local save_path = world_path .. "monoidal_effects.mt"
local backup_path = world_path .. "monoidal_effects_bak.mt"

local effectset = dofile(mod_path .. "effect_set.lua")

local hud_interval = tonumber(minetest.setting_get("effect_hud_interval")) or 1
local effect_interval = tonumber(minetest.setting_get("effect_interval")) or 0.5

local save_interval = tonumber(minetest.setting_get("effect_save_interval")) or 10
local backup_interval =
	tonumber(minetest.setting_get("effect_backup_interval")) or 6

-- The effect database
local effects

-- Try to load the data
local save_file = io.open(save_path, "rb")

if (save_file == nil) then
	minetest.log("info", "[monoidal_effects] Save not found, generating anew.")
	effects = effectset.new_set()
else
	minetest.log("info", "[monoidal_effects] Save found. Loading.")

	local contents = save_file:read("*a")
	save_file:close()

	effects = effectset.deserialize(contents)

	if (effects == nil) then
		error("[monoidal_effects] Save corrupted. Delete or replace with a backup.")
	end
end


-- Name-indexed table of monoid definitions
local monoids = {}

-- Name-indexed table of effect type definitions
local types = {}

-- Keeps track of temporary effects that affect single players. Is a table
-- mapping effect ids to a table containing:
--
--  time_started - The last time the effect was brought into activity
--  duration - How long after time_started to wait until canceling
--  players - Affected players
local active_effects = {}

-- Complements the above, mapping player names to a set of effect IDs that
-- are currently in the above table. Used to efficiently find a player's active
-- effects, so that they can be updated when the player leaves.
local player_effects = {}

-- Keeps track of HUDs the player needs updated. Is a map from player names
-- to another map from effect ids to a table containing:
--   text - HUD id of the display name text
--   icon - HUD id of the icon (may be nil)
--   offset - Y offset
local huds = {}

-- For each online player name, is a map from monoid names to the last
-- calculated value. Does not cache the total with the child values
local monoid_cache = {}


-- Calculates monoid value, caching it
local function calculate_monoid_value(p_name, m_name)
	local p_effects = effects:with_index("player", p_name)

	local m_effects = effects:with_index("monoid", m_name)

	local p_m_effects = effectset.set_intersect(p_effects, m_effects)

	
	local fold = monoids[m_name].fold

	local res = fold(p_m_effects)

	local p_cache = monoid_cache[p_name]

	if (p_cache == nil) then
		p_cache = {}
		monoid_cache[p_name] = p_cache
	end

	p_cache[m_name] = res

	return res
end


local function clear_cache(m_name, p_name)
	local p_cache = monoid_cache[p_name]
	if p_cache == nil then return end

	p_cache[m_name] = nil
end


-- Gets monoid value
local function get_monoid_value(m_name, p_name)
	local cached = monoid_cache[p_name] and monoid_cache[p_name][m_name]

	if (cached == nil) then
		return calculate_monoid_value(p_name, m_name)
	else
		return cached
	end
end


local function add_active_effect(uid, dur, players)

	active_effects[uid] = { time_started = os.time(),
				duration = dur,
				players = players
			      }

	for k, p_name in ipairs(players) do
		if player_effects[p_name] == nil then
			player_effects[p_name] = {}
		end
		player_effects[p_name][uid] = true
	end
end


-- Saves the current remaining duration of an effect
local function save_active_effect(uid)
	local effect = active_effects[uid]

	if effect == nil then
		minetest.log("error",
			     "[monoidal_effects] Tried to save an effect not active")
		return
	end

	local new_dur = os.difftime(effect.duration + effect.time_started, os.time())

	local effect_record = effects:get(uid)

	if effect_record == nil then
		minetest.log("error",
			     "[monoidal_effects] Tried to save nonexistent effect")
		return
	end

	effect_record.duration = new_dur
end
	


-- Suspend an active effect, for when the player logs off.
local function hibernate_active_effect(uid)

	local effect = active_effects[uid]

	if (effect == nil) then
		error("Not an active effect")
	end

	local new_dur = effect.duration - (os.difftime(os.time(), effect.time_started))

	local effect_record = effects:get(uid)

	if (effect_record == nil) then
		error("Hibernating nonexistent effect")
	end

	effect_record.duration = new_dur

	local affected = effect.players

	for p_name in pairs(affected) do
		local p_effs = player_effects[p_name]
		if p_effs ~= nil then
			p_effs[uid] = nil
		end
	end

	active_effects[uid] = nil
end


-- Returns two hud defs. icon is optional
local function mk_hud(uid, disp_name, dur, offset, icon)
	local text_def, icon_def

	local color = 0xFFFFFF

	text_def = { hud_elem_type = "text",
		     position = { x = 1, y = 0.3 },
		     name = "effect_" .. uid,
		     text = disp_name .. " (" .. dur .. "s)",
		     scale = { x = 170, y = 20 },
		     alignment = { x = -1, y = 0 },
		     direction = 1,
		     number = color,
		     offset = { x = -5, y = offset * 20 },
	}

	if icon ~= nil then
		icon_def = { hud_elem_type = "image",
			     scale = { x = 1, y = 1 },
			     position = { x = 1, y = 0.3 },
			     name = "effect_icon_" .. uid,
			     text = icon,
			     alignment = { x = -1, y = 0 },
			     direction = 0,
			     offset = { x = -186, y = offset * 20 },
		}
	end

	return text_def, icon_def
end
		     

local function add_hud(player, uid, disp_name, dur, icon)
	local p_name = player:get_player_name()

	if (huds[p_name] == nil) then
		huds[p_name] = {}
	end

	local p_huds = huds[p_name]

	local min_hudpos
	local max_hudpos = -1
	local free_hudpos

	for uid, hudinfo in pairs(p_huds) do
		local hudpos = hudinfo.offset
		if (hudpos > max_hudpos) then
			max_hudpos = hudpos
		end
		if (min_hudpos == nil) then
			min_hudpos = hudpos
		elseif (hudpos < min_hudpos) then
			min_hudpos = hudpos
		end
	end

	if (min_hudpos == nil) then
		free_hudpos = 0
	elseif(min_hudpos >= 0) then
		free_hudpos = min_hudpos - 1
	else
		free_hudpos = max_hudpos + 1
	end

	if (free_hudpos > 20) then return end

	local text_def, icon_def = mk_hud(uid, disp_name, dur, free_hudpos, icon)

	local text_id = player:hud_add(text_def)
	local icon_id
	if (icon_def ~= nil) then icon_id = player:hud_add(icon_def) end

	p_huds[uid] = { text = text_id,
			icon = icon_id,
			offset = free_hudpos,
	}

end


local function update_hud(now, player)
	local p_name = player:get_player_name()
	local p_huds = huds[p_name]

	if (p_huds ~= nil) then
		for uid, hudinfo in pairs(p_huds) do
			local active_info = active_effects[uid]
			local effect = effects:get(uid)

			if (effect ~= nil) then
				local effect_type = effect.effect_type
				local type_def = types[effect_type]
				local text = hudinfo.text
				local desc = type_def.disp_name
				local time_left
				if (active_info == nil) then
					time_left = "perm"
				else
					local time_started = active_info.time_started
					local dur = active_info.duration
					time_left = os.difftime(time_started + dur, now)
				end

				local new_text = desc .. " ("..tostring(time_left).." s)"

				player:hud_change(hudinfo.text, "text", new_text)
			end
		end
	end
end


monoidal_effects.register_monoid = function(name, def)
	local identity = def.identity

	if (identity == nil) then
		error("No identity defined")
	end
	
	local fold = def.fold
	local combine = def.combine

	if (combine == nil) then
		if (fold == nil) then
			error("Neither combine nor fold is defined")
		else
			def.combine = function(v1, v2)
				return fold({v1, v2})
			end
		end
	elseif (fold == nil) then
		def.fold = function(elems)
			
			local result = identity
			
			for k, v in pairs(elems) do
				result = combine(result, v)
			end

			return result
		end
	end

	def.apply = def.apply or function() return end
	def.on_change = def.on_change or function() return end

	monoids[name] = def
end


monoidal_effects.register_type = function(name, def)
	types[name] = def
end


monoidal_effects.apply_effect = function(effect_type, dur, player_name, values)

	local type_def = types[effect_type]

	if (type_def == nil) then
		error("Tried to apply nonexistent effect type")
	end

	local dyn = type_def.dynamic

	local players = {player_name}

	local tags = type_def.tags

	local t_monoids = type_def.monoids

	local record =
		effectset.record(dyn, effect_type, players, tags, monoids, dur, values)

	local p_cache = monoid_cache[player_name]

	if (p_cache == nil) then
		p_cache = {}
		monoid_cache[player_name] = p_cache
	end

	local eff_values

	if (dyn) then
		eff_values = values
	else
		eff_values = type_def.values
	end

	local player = minetest.get_player_by_name(player_name)

	if (player ~= nil) then
	
		for monoid in pairs(t_monoids) do
			local existing = get_monoid_value(monoid, player_name)

			local new_val

			local mon_def = monoids[monoid]

			if (existing == nil) then
				new_val = eff_values[monoid]
			else
				new_val = mon_def.combine(existing, eff_values[monoid])
			end

			p_cache[monoid] = new_val

			local apply = mon_def.apply

			local on_change = mon_def.on_change

			if (apply ~= nil) then
				apply(new_val, player)
			end

			if (on_change ~= nil) then
				on_change(existing, new_val, player)
			end
		end
	end

	local uid = effects:insert(record)

	if not type_def.hidden then
		add_hud(player, uid, type_def.disp_name, dur, type_def.icon)
	end

	if (dur ~= "perm") then
		add_active_effect(uid, dur, {player_name})
	end

	return uid
end


monoidal_effects.cancel_effect = function(uid)

	local all_players = minetest.get_connected_players()

	local player_set = {}

	local effect = effects:get(uid)
	local players = effect.players
	local monoids = effect.monoids

	for i, player in ipairs(all_players) do
		local p_name = player:get_player_name()
		if players[p_name] then
			player_set[p_name] = player
		end
	end

	local old_vals = {}

	if (effect == nil) then return end

	for p_name in pairs(player_set) do
		old_vals[p_name] = {}
		local p_vals = old_vals[p_name]
		for monoid in pairs(monoids) do
			p_vals[monoid] = get_monoid_value(monoid, player)
		end
	end

	effects:delete(uid)

	for p_name, player in pairs(player_set) do
		local p_vals = old_vals[p_name]
		for monoid in pairs(monoids) do
			clear_cache(monoid, p_name)
			local val = get_monoid_value(p_name, monoid)
			local mon_def = monoids[monoid]

			if (mon_def == nil) then
				minetest.log("error",
					     "[monoidal_effects] Effect with bad monoid")
			else
				mon_def.apply(val, player)
				mon_def.on_change(p_vals[monoid], val, player)

				local p_huds = huds[p_name]
				if p_huds ~= nil then
					local hudinfo = p_huds[uid]
					if hudinfo ~= nil then
						player:remove_hud(hudinfo.text)
						if hudinfo.icon ~= nil then
							player:remove_hud(hudinfo.icon)
						end
					end
					p_huds[uid] = nil
				end
			end
		end
	end

	local active_data = active_effects[uid]
	active_effects[uid] = nil

	if active_data ~= nil then
		for i, player in ipairs(active_data.players) do
			player_effects[player][uid] = nil
		end
	end
end


local function cancel_index(index_name)

	return function(index, p_name)
	
		local indexed_effects = effects:with_index(index_name, index)

		local affected_effects

		if p_name ~= nil then
			local p_effects = effects:with_index("player", p_name)
			affected_effects = effectset.set_intersect(indexed_effects, p_effects)
		else
			affected_effects = indexed_effects
		end

		for uid in pairs(affected_effects) do
			monoidal_effects.cancel_effect(uid)
		end
	end
end

monoidal_effects.cancel_monoid = cancel_index("monoid")

monoidal_effects.cancel_effect_type = cancel_index("name")

monoidal_effects.cancel_tag = cancel_index("tag")

monoidal_effects.get_remaining_time = function(uid)
	local active = active_effects[uid]

	if (active ~= nil) then
		return os.difftime(active.time_started + active.duration, os.time())
	end

	local effect = effects:get(uid)

	if effect == nil then return nil end

	return effect.duration
end

monoidal_effects.get_player_effects = function(p_name)

	return effects:with_index("player", p_name)
end

monoidal_effects.get_monoid_value = get_monoid_value


local function apply_effects(player)
	local p_name = player:get_player_name()

	if (p_name == nil) then return end

	local p_effects = monoidal_effects.get_player_effects(p_name)

	local monoids = {}

	for uid in pairs(p_effects) do

		local effect = effects:get(uid)


		if (effect ~= nil) then
			for monoid in pairs(effect.monoids) do
				monoids[monoid] = true
			end
		end
	end

	for monoid in pairs(monoids) do
		local mon_def = monoids[monoid]

		if (mon_def ~= nil) then
			local val = get_monoid_value(monoid, p_name)
			mon_def.apply(val, player)
		end
	end
end


-- Pulls all of a player's active effects out of hibernation
local function defrost_actives(p_name)
	local p_effects = effects:with_index("player", p_name)
	local perm_effects = effects:with_index("perm", false)

	local to_defrost = effectset.set_intersect(p_effects, perm_effects)

	for uid in pairs(to_defrost) do
		local effect = effects:get(uid)

		if effect ~= nil then
			add_active_effect(uid, effect.duration, {p_name})
		end
	end
end


local function frost_actives(p_name)
	local p_active = player_effects[p_name]

	if p_active == nil then return end

	for uid in pairs(p_active) do
		hibernate_active_effect(uid)
	end
end


minetest.register_on_joinplayer(function(player)
		local p_name = player:get_player_name()
		
		defrost_actives(p_name)
		apply_effects(player)

		local p_effects = effects:with_index("player", p_name)

		for uid in pairs(p_effects) do
			local effect = effects:get(uid)

			if effect ~=nil then
				local type_def = types[effect.effect_type]

				if type_def ~= nil then
					add_hud(player,
						uid,
						type_def.disp_name,
						effect.duration,
						type_def.icon)
				end
			end
		end
end)


minetest.register_on_leaveplayer(function(player)
		local p_name = player:get_player_name()
		frost_actives(p_name)
		huds[p_name] = nil
end)

minetest.register_on_respawnplayer(function(player)
		apply_effects(player)
end)

minetest.register_on_dieplayer(function(player)
		for uid in pairs(effects:with_index("player", player:get_player_name())) do
			local effect = effects:get(uid)

			local type_def = types[effect.effect_type]

			local cancel_on_death = (type_def and type_def.cancel_on_death)

			if (cancel_on_death) then
				monoidal_effects.cancel_effect(uid)
			end
		end
end)

-- Save, HUD update, effect update timers
local last_save = 0
local last_hud = 0
local last_effect = 0


-- How many more saves until should backup. Unit is number of saves.
local backup_timer = 0

local function save_effects(path)
	for uid in pairs(active_effects) do
		save_active_effect(uid)
	end

	local str = effectset.serialize(effects)

	local file = io.open(path, "wb")
	file:write(str)
	file:close()
end

local function on_save_timer()
	save_effects(save_path)
	if (backup_timer <= 0) then
		save_effects(backup_path)
		backup_timer = backup_interval
	else
		backup_timer = backup_timer - 1
	end
end

local function on_hud_timer()

	local now = os.time()

	for i, player in ipairs(minetest.get_connected_players()) do
	
	update_hud(now, player)
	end
end

local function update_effects()
	local now = os.time()

	for uid, active_info in pairs(active_effects) do
		local started = active_info.time_started
		local dur = active_info.duration
		local time_left = os.difftime(started + dur, now)

		if time_left <= 0 then
			monoidal_effects.cancel_effect(uid)
		end
	end
end

minetest.register_globalstep(function(dtime)

		local now = os.time()

		if os.difftime(now, last_save) >= save_interval then
			on_save_timer()
			last_save = now
		end

		if os.difftime(now, last_hud) >= hud_interval then
			on_hud_timer()
			last_hud = now
		end

		if os.difftime(now, last_effect) >= effect_interval then
			update_effects()
			last_effect = now
		end
end)

minetest.register_on_shutdown(function()
		save_effects(save_path)
		save_effects(backup_path)
end)


local debug = minetest.setting_getbool("debug_effects")

if debug then dofile(mod_path.."test_effects.lua") end
