minetest.register_privilege("monoid_master", "Lets you apply effects to players")

minetest.register_chatcommand("apply_effect",
	{ params = "<name> <effect> <duration>",
	  description = "Applies effect to player",
	  privs = { monoid_master = true },
	  func = function(p_name, param)
		  local target, eff, dur =
			  param:match("^([^ ]+) +([^ ]+) +(.+)$")
		  if not target then
			  return false, "Target name required"
		  end

		  if not eff then
			  return false, "Effect name required"
		  end

		  if not dur then
			  return false, "Duration required"
		  end

		  local duration = tonumber(dur)

		  if not duration then
			  return false, "Duration must be a number"
		  end

		  if duration <= 0 then
			  return false, "Duration must be positive"
		  end

		  monoidal_effects.apply_effect(eff, math.ceil(duration), target)
		  return true
	  end,
})
