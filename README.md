#Monoidal Effects

Motivation
==========
A mod may want to apply status effects to a player, but often this requires
changing some global state, such as player physics overrides or damage
callbacks. If multiple mods try to independently alter global state, it can
leave it in an inconsistent state, causing jarring bugs. This mod provides a
framework for managing player-specific global state that allows multiple mods
to affect the same state.

playereffects
-------------
Wuzzy's playereffects currently solves the problem of inconsistent states, but
it does not allow multiple effects on the same state to be active at the
same time. If a new effect would affect state that a currently active effect
affects, the old effect is cancelled before the new one is applied. This means
the two effects cannot be merged into a combined effect. This excludes some
use-cases:
- Numerically combine physics overrides - For example, two speed effects, one
  giving 3x speed and the other 0.5x speed, could combine to give 1.5x speed.
- Preserving longer effects - If effect A has 10 seconds left, and a new effect
  lasting 3 seconds is applied, players and mod authors might want effect A to
  continue working after the shorter effect has run out.
- Choosing an effect by priority - Maybe your mod has "fly" and "anti-fly"
  effects with varying power, and you want the player to be able to fly
  only if the strongest activefly effect is stronger than the strongest active
  anti-fly effect.
- Working nicely with permanent status changes - You might want the above flying
  effect to work correctly with the fly perm, maybe interpreting it as the
  highest possible priority.

Monoidal Effects seeks to make these behaviors possible.


Concepts
========

Monoids
-------
Monoids are collections of things (think "type") that can be combined nicely.
"Nice" means you can combine two elements of the collection to get a new
value in the collection, and this combining operation is associative (like in
algebra) and has an identity. An identity element (call it "e") can be
combined with any element to get the other element. For addition,
(0 + x = x + 0 = x), and for multiplication, (1 * x = x = x * 1).

This abstract concept is relevant to status effects because we would like to
be able to combine status effects nicely. The parts of a monoid map well to
combinable status effects: The combining operation is how you make a new
effect from others, and the identity represents the "neutral" state, when
no effects are active. If no effects are active and you add a new effect, then
obviously you will just want that new effect to take effect.

Monoids in Monoidal Effects
---------------------------
When you want to have a certain kind of player state handled by the framework,
you need to register a monoid. This is done by calling
```monoidal_effects.register_monoid("name", monoid_def)```
where "name" is your monoid's name, and monoid_def is a table that should
contain these fields:
  - ```combine(elem1, elem2)``` - The combining operation for the monoid
  - ```fold({elems})``` - A function that should be equivalent to using combine
  to combine all the values in the table together, from left to right. That
  means using it on an empty table should give the identity.
  - ```identity``` - The identity.
  - ```apply(value, player)``` - This is a special function that "interprets" a
  monoidal value, and carries out its intended effect. For example, in a
  speed multiplier monoid, value would be a number, and you would set the
  player's speed physics override to it.
This is everything you need to start accepting effects that affect the state
handled by this monoid. For example, a speed monoid might be registered with
```
monoidal_effects.register_monoid("speed",
  { combine = function(x,y) return x * y end,
    fold = function(xs)
      local total = 1
      for k, x in pairs(xs)
        total = total * x
      end
      return total
    end,
    identity = 1,
    apply = function(mult, player)
      local ov = player:get_physics_override()
      ov.speed = mult
      player:set_physics_override(ov)
    end,
})
```

Effect Types
------------
Once you have a way of combining and applying and executing your effects to
players, you will want to actually have effects. An effect type is a
description of an effect that can later be applied to a player, and is
registered by calling
```monoidal_effects.register_type("name", type_def)```
where type_def is a table that should have these fields:
  - ```disp_name``` - The name displayed to users
  - ```tags``` - A set of string tags. These are used so they can be searched
  later. It should be in the form ```{tag1 = true, tag2 = true ...}```.
  - ```monoids``` - A set of names of the monoids this effect type affects.
  An effect that makes you fly slowly might have {fly = true, speed = true},
  if "fly" and "speed" were the names of the fly and speed multiplier monoids.
  - ```hidden``` - Should the player see if they are affected?
  - ```cancel_on_death``` - A boolean for whether the effect should go away on
  death.
  - ```values``` - A table mapping monoid names to associated values. Continuing
  the earlier example, you might have {fly = true, speed = 0.5}, if the fly
  monoid takes booleans for whether fly is activated, and the speed monoid takes
  multipliers.
  - ```icon``` - An optional texture string for displaying to the player.
As an example, here is an effect type using the example speed monoid, that
gives a player half speed:
```
monoidal_effects.register_type("half_speed",
  { disp_name = "Slow",
    tags = { example_effect = true },
    monoids = { speed = true },
    hidden = false,
    cancel_on_death = false, -- Not even the dead
    values = { speed = 0.5 },
    icon = "half_speed.png",
})
```
In reality, you will want to prefix your monoid and effect type names with your
mod name, like you do with item definitions. This is to prevent collisions.

To apply an effect, you can just do (for example)
```monoidal_effects.apply_effect("half_speed", 999999999, "Griefman")```.
The duration is in seconds.

To see some ways you can query or affect already-applied effects, take a look
at API.txt.

Standard Monoids
================
These monoids "come with" monoidal_effects, and are not prefixed by any mod
name:
  - "speed", "jump", "gravity" - These are monoids for the physics overrides,
  and are combined using multiplication. The gravity monoid may have negative
  multipliers.
  - "hp_max" - A monoid for max health modifiers. Valid effect values are
  integers, which are combined with addition. The final result is added to
  20 to get the real max health of a player.
  - "fly" - A monoid for the fly permission. Valid effect values are booleans,
  which say whether flying should be allowed. These are combined with or. That
  means that if there is any single effect providing fly, the player can fly.
  The identity is false, since the player shouldn't be able to fly normally.
  - "noclip" - The same as above, but for noclip.
