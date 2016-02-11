-- Standard effect monoids, to provide canonicity.

local function mult(x, y) return x * y end

local function mult_fold(elems)
	local tot = 1
	
	for k,v in pairs(elems) do
		tot = tot * v
	end

	return tot
end

local function v_mult(v1, v2)
	local res = {}

	for k, v in pairs(v1) do
		res[k] = v * v2[k]
	end

	return res
end

local function v_mult_fold(identity)

	return function(elems)
		local tot = identity

		for k, v in pairs(elems) do
			tot = v_mult(tot, v)
		end

		return tot
	end
end


-- Speed monoid. Effect values are speed multipliers. Must be nonnegative
-- numbers.
monoidal_effects.register_monoid("speed",
				 { combine = function(x, y) return x * y end,
				   fold = function(elems)
					   local res = 1
					   for k, v in pairs(elems) do
						   res = res * v
					   end

					   return res
				   end,
				   identity = 1,
				   apply = function(mult, player)
					   local ov = player:get_physics_override()
					   ov.speed = mult
					   player:set_physics_override(ov)
				   end,
})


-- Jump monoid. Effect values are jump multipliers. Must be nonnegative
-- numbers.
monoidal_effects.register_monoid("jump",
				 { combine = function(x, y) return x * y end,
				   fold = function(elems)
					   local res = 1
					   for k, v in pairs(elems) do
						   res = res * v
					   end

					   return res
				   end,
				   identity = 1,
				   apply = function(mult, player)
					   local ov = player:get_physics_override()
					   ov.jump = mult
					   player:set_physics_override(ov)
				   end,
})


-- Gravity monoid. Effect values are gravity multipliers.
monoidal_effects.register_monoid("gravity",
				 { combine = function(x, y) return x * y end,
				   fold = function(elems)
					   local res = 1
					   for k, v in pairs(elems) do
						   res = res * v
					   end

					   return res
				   end,
				   identity = 1,
				   apply = function(mult, player)
					   local ov = player:get_physics_override()
					   ov.gravity = mult
					   player:set_physics_override(ov)
				   end,
})


-- Max HP modifier monoid. It combines by addition. Values should be integers.
-- A player's max hp will never be sent below 1, even if the combined modifier
-- is -20 or below.
monoidal_effects.register_monoid("hp_max",
				 { combine = function(x, y) return x + y end,
				   fold = function(elems)
					   local res = 0
					   for k, v in pairs(elems) do
						   res = res + v
					   end

					   return res
				   end,
				   identity = 0,
				   apply = function(offset, player)
					   local real_offset = math.max(offset,1)
					   player:set_properties(
						   { hp_max = real_offset + 20 }
					   )
				   end,
})


-- Fly ability monoid. The values are booleans, which are combined by or. A true
-- value indicates having the ability to fly.
monoidal_effects.register_monoid("fly",
				 { combine = function(p, q) return p or q end,
				   fold = function(elems)
					   for k, v in pairs(elems) do
						   if v then return true end
					   end

					   return false
				   end,
				   identity = false,
				   apply = function(can_fly, player)
					   local p_name = player:get_player_name()
					   local privs = minetest.get_player_privs(p_name)
					   
					   if can_fly then
						   privs.fly = true
					   else
						   privs.fly = nil
					   end

					   minetest.set_player_privs(p_name, privs)

				   end,
})


-- Noclip ability monoid. Works the same as fly monoid.
monoidal_effects.register_monoid("noclip",
				 { combine = function(p, q) return p or q end,
				   fold = function(elems)
					   for k, v in pairs(elems) do
						   if v then return true end
					   end

					   return false
				   end,
				   identity = false,
				   apply = function(can_noclip, player)
					   local p_name = player:get_player_name()
					   local privs = minetest.get_player_privs(p_name)
					   
					   if can_noclip then
						   privs.noclip = true
					   else
						   privs.noclip = nil
					   end

					   minetest.set_player_privs(p_name, privs)

				   end,
})

local def_col_scale = { x=0.3, y=1, z=0.3 }

-- Collisionbox scaling factor. Values are a vector of x, y, z multipliers.
monoidal_effects.register_monoid("collisionbox", {
	combine = v_mult,
	fold = v_mult_fold({x=1, y=1, z=1}),
	identity = {x=1, y=1, z=1},
	apply = function(multiplier, player)
		local v = vector.multiply(def_col_scale, multiplier)

		player:set_properties({
			collisionbox = { -v.x, -v.y, -v.z, v.z, v.y, v.z }
		})
	end,
})

monoidal_effects.register_monoid("visual_size", {
	combine = v_mult,
	fold = v_mult_fold({x=1, y=1}),
	identity = {x=1, y=1},
	apply = function(multiplier, player)
		player:set_properties({
			visual_size = multiplier
		})
	end,
})
