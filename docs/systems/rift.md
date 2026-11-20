# The Basalt Rift

Rules for `worlds/rift/` (DESIGN.md "Basalt Rift", "The Basalt Rift (part
one, built: the world and updrafts)"). Check it with `tests/rift_tests.gd`
and by eye with `visual_check.tscn -- <dir> --rift-only`.

## The map

- A small, tall world over lava (`worlds/rift/map.gd`): the rift's floor
  (`FLOOR_Y`) lies under the lava (`LAVA_Y`), and the cliffs climb past
  `FIELD`. The floor and cliffs are a `Terrain` outside the navigation
  region: solid, so a body falls onto them, but never walked by a bot.
  Walls stand `EDGE` past the field, at the cliffs' foot, so nobody lands
  on a cliff top (a rig's ceiling counts from the ground under it, and
  there that is the cliff).
- Everything you stand on is basalt in the navigation region: the Gate
  Shelf (`SHELF_TOP`, `SHELF_AT`, `SHELF_SIZE`; the outpost, the player
  spawns and two depots), the three mesas of the strongpoints (`SITES`,
  each with lower columns round it, cover, a depot, a cache and three
  soldiers), the Crown (`CROWN`, the warlord and three caches) and the
  perches (`PERCHES`, placed on the layout's own RNG clear of everything
  else, some with a cache, some with a soldier). Columns are six-sided
  (`_column`), collision cut to the same shape; a bridge ends inside a
  mesa's flat side (cos 30° of its radius).
- Iron bridges (`BRIDGES`, group "rift_bridge", one body with a deck and
  two rails) join the Shelf and the three mesas, so every strongpoint is
  walkable from the landing. Nothing joins the Crown: only an updraft
  gets you there.
- The decoration (`_dress`, view only): the lava sheet (`Look.trim("lava")`,
  `lava.gdshader`) and a few lights under the smoke, each vent's glow,
  heat haze and embers (the haze column is air: meta "walk_through"), and
  the planet's land and props past the cliffs, on `_art_rng`.

## The lava

- `WorldDef.molten_level` is the lava's top. `Raid._tick_molten` scans the
  players and bots four times a second and burns anyone whose feet are
  under it for `molten_damage` (the world's `LAVA_DAMAGE`, 50, armor no
  help) through `Combat.deal`, kind "lava", whatever the zone rules.
- What someone drops dying comes to rest where `Raid.drop_spot` says: on
  whatever is under them, and on top of the lava, never in it. So a scrip
  pile from a fight in the air floats on the crust, and a jetpack
  hovering over it can still grab it.

## Updrafts

- The map's `VENTS` (each a spot in the lava and a top), read by the
  static `updraft_at` that the world's `WorldDef.updraft_at` returns: up
  to `VENT_RISE` m/s, full in the middle `VENT_CORE` share of
  `VENT_RADIUS`, easing to nothing at its edge and over the last
  `VENT_EASE` metres to its top. Plain data, so the server and every
  client agree and a client predicts it.
- `Actor._ride_updraft` asks it every tick in the air (not on the floor,
  not in a vehicle). The rise is added to the body's vertical speed for
  the move only and taken off after it, so it carries the body on top of
  whatever the rig does: a hover rises with the air, a glide climbs
  instead of sinking, a fall is only slowed. A landing counts the speed
  against the ground. It pays no heed to the rig's ceiling.
- `FlightRig.in_updraft` is set while riding one: gliding spends no
  stamina there.
- The watch's zone label says "updraft" while you are in one.
- Keep a vent clear of the bridges and the mesas, and keep at least one
  rising past the Crown beside it (the tests check both the Crown's
  height over every rig's ceiling and that ride).

## Rules

- Ashfront's death rule (`death_drops_scrip`): the fallen drop scrip, not
  gear. The starter kit carries the Mk1 jetpack.
- The roster (`ROSTER` in `worlds/rift/world.gd`) does not fly; its
  marksmen see far (90 m), since the rift is all long sight lines.
