
-- Defines the relational data structure used for storing status effects.
--
--
-- Effects
--
-- A single effect record has these components:
--
--   A unique ID (uid)
--
--   A boolean, whether it is dynamic (dynamic)
--
--   The effect type name (effect_type)
--
--   A set of names of players it applies to (players)
--
--   A set of tags it has (tags)
--
--   A set of monoids it belongs to (monoids)
--
--   A table from monoid names to monoidal values (values), if it is dynamic
--
--   A duration (duration), either the string "perm" or a number of seconds
--
--   The time it started (time_started)
--
--
-- Effect Set
--
-- An effect set represents a many-to-many relation by holding for each index a
-- map from indices to a set of records it indexes. Since the unique ID should be
-- unique, a set of records can instead be represented by a map from IDs to
-- records. The ID table can instead be a simple map to records, since each
-- effect can only have one ID.
--
-- Currently, it has index tables:
--
-- id_table (one-to-one)
-- player_table (many-to-many)
-- tag_table (many-to-many)
-- monoid_table (many-to-many)
-- name_table (one-to-many)
-- perm_table (one-to-many)
--
--
-- To serialize, it suffices to just serialize the ID-indexed table, since all
-- records have an ID.
--
-- It also keeps track of the next unique ID in next_id
--
--
-- Setmap
--
-- A set map is a map from indices to sets of records. They are used to represent
-- many-to-many and one-to-many relations.


-- Returns a set of results
local function setmap_get(setmap, index)
	return setmap[index]
end


local function setmap_insert(setmap, indices, record)
	local uid = record.uid

	for k, index in pairs(indices) do
		local set = setmap[index]
		
		if (not set) then
			set = {}
			setmap[index] = set
		end

		setmap[index][uid] = record
	end
end


local function setmap_delete(setmap, indices, record)
	local uid = record.uid

	for k, index in pairs(indices) do
		local set = setmap[index]

		if set ~= nil then
			set[uid] = nil

			-- If the set is empty we should clean it up to prevent
			-- leaks
			if next(set) == nil then
				setmap[index] = nil
			end
		end
	end
end


monoidal_effects.static = 1
monoidal_effects.dynamic = 2


local function record(id, dyn, effect_type, players, tags, monoids, dur, values)

	return { uid = id,
		 dynamic = dyn,
		 effect_type = effect_type,
		 players = players,
		 tags = tags,
		 monoids = monoids
		 values = values,
		 duration = dur,
		 time_started = os.time()
	}
end


-- Prepares for serialization.
local function prep_record(record, cur_time)

	-- Save the amount of time left
	if (record.duration ~= "perm") then
		record.duration = record.duration - (cur_time - record.time_started)
	end

	record.time_started = nil
end


-- Sets the time_started nicely.
local function unprep_record(record, cur_time)
	record.time_started = cur_time
end


local function make_db()

	local db = {}

	db.next_id = 0

	db.uid_table = {}
	db.player_table = {}
	db.tag_table = {}
	db.monoid_table = {}
	db.name_table = {}
	db.perm_table = {}
end


-- Mutates the table to have the new record
local function insert_record(db, record)
	local uid = record.uid
	
	db.uid_table[uid] = record
	setmap_insert(db.player_table, record.players, record)
	setmap_insert(db.tag_table, record.tags, record)
	setmap_insert(db.monoid_table, record.monoids, record)
	setmap_insert(db.name_table, {record.effect_type}, record)

	local perm

	if (record.duration == "perm") then
		perm = true
	else
		perm = false
	end
	
	setmap_insert(db.name_table, {perm}, record)
end
