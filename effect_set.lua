
-- Defines the relational data structure used for storing status effects.
--
--
-- Effects
--
-- A single effect record has these components:
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
-- Has a table uid_table that maps uids to records
--
-- Has a field "tables" that holds all the index tables.
--
-- Currently, it has index tables:
--
--   player (many-to-many)
--   tag (many-to-many)
--   monoid (many-to-many)
--   name (one-to-many)
--   perm (one-to-many)
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
local db_version = 0

local table_names = { "player", "tag", "monoid", "name", "perm" }


-- Returns a set of results
local function setmap_get(setmap, index)
	return setmap[index]
end


local function setmap_insert(setmap, indices, uid)

	for k, index in pairs(indices) do
		local set = setmap[index]
		
		if (not set) then
			set = {}
			setmap[index] = set
		end

		set[uid] = true
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
		res_set[k] = set2[k]
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


local function record(dyn, effect_type, players, tags, monoids, dur, values)

	return { dynamic = dyn,
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


-- Returns a set of UIDs that match the given index
local function effect_set_index_set(db, table_name, index)

	return db.tables[table_name][index]
end


local function fill_tables(db)

	db.tables = {}

	for i, table_name in ipairs(table_names) do
		db.tables[table_name] = {}
	end
	
	for k, v in pairs(db.uid_table) do
		insert_record_with_uid(k, db, v)
	end
end


local function add_methods(eset)
	eset.get = effect_set_get
	eset.effects = effect_set_effects
	eset.insert = insert_record
	eset.delete = delete_record
	eset.size = function(self)
		return #(self.uid_table)
	end
	eset.with_index = effect_set_index_set
end


local function make_db()

	local db = {}

	db.version = db_version

	db.next_id = 0

	db.tables = {}

	db.uid_table = {}
	db.tables.player = {}
	db.tables.tag = {}
	db.tables.monoid = {}
	db.tables.name = {}
	db.tables.perm = {}

	add_methods(db)
end


-- Mutates the DB to have the new record
local function insert_record_with_uid(uid, db, record)
	db.uid_table[uid] = record
	setmap_insert(db.tables.player, record.players, uid)
	setmap_insert(db.tables.tag, record.tags, uid)
	setmap_insert(db.tables.monoid, record.monoids, uid)
	setmap_insert(db.tables.name, {record.effect_type}, uid)

	local perm = is_perm(record)
	
	setmap_insert(db.tables.perm, {perm}, uid)
end


local function insert_record(db, record)
	local uid = db.next_id
	db.next_id = uid + 1

	insert_record_with_uid(uid, db, record)

	return uid
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

	setmap_delete(db.tables.player, players, uid)
	setmap_delete(db.tables.tag, tags, uid)
	setmap_delete(db.tables.monoid, monoids, uid)
	setmap_delete(db.tables.name, {effect_type}, uid)
	setmap_delete(db.tables.perm, {perm}, uid)
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
