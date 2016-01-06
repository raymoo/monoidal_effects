
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
-- Has a table uid_table that maps uids to records
--
-- Has a field "tables" that holds all the index tables.
--
-- Currently, it has index tables:
--
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
-- It also has two methods:
--
--   get(uid) - takes an effect id and returns the effect record if it exists
--   effects() - iterator over the effect ids and effect records
--
-- Setmap
--
-- A set map is a map from indices to sets of records. They are used to represent
-- many-to-many and one-to-many relations.


-- Version of db format
local db_version


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


local function setmap_delete(setmap, indices, uid)

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


-- Returns a new set that's the intersection of the two
local function set_intersect(set1,set2)

	local res_set = {}

	for k, rec in pairs(set1) do
		if set2[k] then
			res_set[k] = rec
		end
	end

	return res_set
end


-- Returns a new map, using the function to resolve conflicts
local function map_intersect_with(f, set1, set2)

	local res_map = {}

	for k, v in pairs(set1) do
		local v2 = set2[k]

		if v2 ~= nil then
			res_map[k] = f(v, v2)
		end
	end

	return res_map
end


-- Returns a new setmap. Will be faster if you put the smaller one first.
local function setmap_intersect(smap1, smap2)
	return map_intersect_with(set_intersect, smap1, smap2)
end


local function set_union(set1, set2)

	local res_set = {}

	for k, v in pairs(set1) do
		res_set[k] = v
	end

	for k, v in pairs(set2) do
		res_set[k] = v
	end

	return res_set
end


local function map_union_with(f, map1, map2)

	local res_map = {}

	for k, v in pairs(map1) do
		res_map[k] = v
	end

	for k, v in pairs(map2) do
		local existing = res_map[k]

		if (existing) then
			res_map[k] = f(existing, v)
		else
			res_map[k] = v
		end
	end

	return res_map
end


-- Returns a new setmap. *I think* faster if the first is smaller.
local function setmap_union(smap1, smap2)
	return map_union_with(set_union, smap1, smap2)
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


local function is_perm(record)
	return record.duration == "perm"
end


local function shallow_copy(x)
	local res = {}

	for k, v in pairs(x) do
		res[k] = v
	end

	return res
end


-- Prepares for serialization.
local function prep_record(record, cur_time)

	-- Save the amount of time left
	if (not is_perm(record)) then
		record.duration = record.duration - (cur_time - record.time_started)
	end

	record.time_started = nil
end


-- Sets the time_started nicely.
local function unprep_record(record, cur_time)
	record.time_started = cur_time
end


local function effect_set_get(eset, uid)
	return eset.uid_table[uid]
end


local function effect_set_effects(eset)
	return pairs(eset.uid_table)
end


local function add_methods(eset)
	eset.get = effect_set_get
	eset.effects = effect_set_effects
	eset.insert = insert_record
	eset.delete = delete_record
	eset.size = function(self)
		return #(self.uid_table)
	end
end


local function make_db()

	local db = {}

	db.version = db_version

	db.next_id = 0

	db.tables = {}

	db.uid_table = {}
	db.tables.player_table = {}
	db.tables.tag_table = {}
	db.tables.monoid_table = {}
	db.tables.name_table = {}
	db.tables.perm_table = {}

	add_methods(db)
end


-- Mutates the DB to have the new record
local function insert_record_with_uid(uid, db, record)
	db.uid_table[uid] = record
	setmap_insert(db.tables.player_table, record.players, record)
	setmap_insert(db.tables.tag_table, record.tags, record)
	setmap_insert(db.tables.monoid_table, record.monoids, record)
	setmap_insert(db.tables.name_table, {record.effect_type}, record)

	local perm = is_perm(record)
	
	setmap_insert(db.tables.name_table, {perm}, record)
end


local function insert_record(db, record)
	local uid = db.next_id
	db.next_id = uid + 1

	insert_record_with_uid(uid, db, record)
end


-- Mutates the DB to remove the record. Returns the deleted record, or nil if
-- it was not found.
local function delete_record(db, uid)
	local record = db.uid_table[uid]

	if (record == nil) then return end

	local players = record.players
	local tags = record.tags
	local monoids = record.monoids
	local effect_type = record.effect_type
	local perm = is_perm(record)

	db.uid_table[uid] = nil

	setmap_delete(db.tables.player_table, players, uid)
	setmap_delete(db.tables.tag_table, tags, uid)
	setmap_delete(db.tables.monoid_table, monoids, uid)
	setmap_delete(db.tables.name_table, {effect_type}, uid)
	setmap_delete(db.tables.perm_table, {perm}, uid)
end


local function serialize_effect_set(eset)
	local serialize_this = shallow_copy(eset.uid_table)

	for k, v in pairs(uid_table) do
		prep_record(v)
	end

	serialize_this.get = nil
	serialize_this.effects = nil
	serialize_this.tables = nil

	return minetest.serialize(serialize_this)
end


local function deserialize_effect_set(str)
	local deserialized = minetest.deserialize(str)

	for k, v in pairs(deserialized) do
		unprep_record(v)
		insert_record_with_uid(k, deserialized, v)
	end
	
	add_methods(deserialized)

	return deserialized
end


-- Mini namespace for effect sets
local effectset = {}

effectset.new_set = make_db

effectset.intersect = function(es1, es2)
	local es = {}

	es.uid_table = set_intersect(es1.uid_table, es2.uid_table)
	es.tables = map_intersect(setmap_intersect, es1.tables, es2.tables)

	add_methods(es)
	return es
end

effectset.union = function(es1, es2)
	local es = {}

	es.uid_table = set_union(es1.uid_table, es2.uid_table)
	es.tables = map_intersect(setmap_union, es1.tables, es2.tables)

	add_methods(es)
	return es
end


return effectset
