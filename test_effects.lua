-- Static half speed
monoidal_effects.register_type("monoidal_effects:half_speed",
			       { disp_name = "Half Speed",
				 tags = {test = true},
				 monoids = {speed = true},
				 cancel_on_death = true,
				 values = {speed = 0.5},
})

-- 3x speed plus heavy gravity
monoidal_effects.register_type("monoidal_effects:three_speed",
			       { disp_name = "3x Speed",
				 tags = {test = true},
				 monoids = {speed = true, gravity = true},
				 cancel_on_death = true,
				 values = {speed = 3, gravity = 10},
})

minetest.register_on_joinplayer(function(player)

		monoidal_effects.apply_effect("monoidal_effects:half_speed",
					      4,
					      player:get_player_name()
		)

		monoidal_effects.apply_effect("monoidal_effects:three_speed",
					      8,
					      player:get_player_name()
		)
end)
