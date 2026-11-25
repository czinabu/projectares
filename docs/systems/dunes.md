# Dune Sea

Rules for `worlds/dunes/` and its haul. These are part of the rules in
`CLAUDE.md` that must not be broken: read this file before changing
anything it covers, and keep it up to date in the same PR.

- The Dune Sea (DESIGN.md "The Dune Sea (part one, built: the haul)"):
  its map is the dunes planet's ground (`PlanetTerrain`, the type's recipe
  with `field` set to `FIELD`, no terrace steps on the playable sand,
  `terrace_field` 0, and slip faces a wheel climbs, `dune_slip`
  `DUNE_SLIP`: under 1% of it steeper than a vehicle's 40 degrees) laid
  flat round the landing, the yards
  (`SITES`) and the wreck fields (`WRECKS`), each flat at the dunes' own
  height there, about 1.8 km across. Its navigation is baked coarser than
  a small map's (`cell_size` 1 m), which keeps the bake to a few seconds
  at that size; bots walk open sand. Anything that stands on the playable
  sand is a solid (the hulks are `_box`es); the planet's props stand only
  past the field. Its enemies are the roster (`ROSTER` in
  `worlds/dunes/world.gd`), built by `equip_bot`: the raiders, with the
  Salvage Runner (a knife, held as the item it is, row "item"). A Dune
  Burrower (`BURROWER`) is built for the map's "spawn_guard" markers of
  faction "burrower", one in every other wreck field; it lies low, feels
  9 m round, and grows bolder in a sandstorm ("storm_bold",
  `BotBrain.storm_boost`). It stays wild (faction "burrower"), and
  `can_damage` keeps it and the raiders from fighting each other. You keep what you wear
  on death (`keep_gear_on_death`). The far ring past the walls
  (`Planet.horizon`) is built from that same ground (`far_land`), so it
  meets the sand at the map's edge, and drawn smoothed (`HORIZON_SMOOTH`);
  a ring from another recipe stood tens of metres over the edge and its
  dunes folded into sheets jutting into the sky. Check it with
  `tests/dunes_tests.gd`, `tests/dunes_ground_tests.gd` (the ring meets the
  sand, the sand is drivable, a rover crosses it at speed with its wheels
  down) and by eye with `visual_check.tscn -- <dir> --dunes-only`.
- Salvage crates are generic (`core/interact/salvage_crate.gd`): any map
  may put "spawn_crate" markers down, filled from `roll_loot("crate")`.
  Only the authority moves one (`Raid.lift_crate`, `set_down_crate`,
  `drop_crate`, `spill_cargo`); a crate's `place` emits `moved` and
  `NetSession` sends clients where it is (`_crate`, `_crate_moved`: on the
  ground, which actor carries it, which vehicle and slot), never what is
  in it. A client sets `Actor.crate` from that, so the carrier's slow walk
  is predicted. Where a crate is shown follows its holder every physics
  frame (`SalvageCrate.follow`), the same everywhere.
- Carrying (`Actor.crate`): no weapon comes out (as `weapons_locked`),
  the walk is `crate_speed` of `walk_speed` with no sprint, and the jump
  is held off in the air so no rig lifts off. Interact with a crate in
  hand goes to `Raid.set_down_crate`, never to what is looked at.
- Banking: a depot banks `SalvageCrate.hauled_by(actor)` (the crate in
  hand and the cargo of the vehicle they drive) with the pack
  (`Raid._bank_crates` in `_on_actor_banked`). Nothing else takes a
  crate home: death, a sign-out, a body removed and a vehicle cleared or
  packed all drop or refuse it first (`_drop_hauled`, `spill_cargo`, the
  "Unload its cargo first" refusal in `pack_vehicle`).
- Crates in a world that never ends: `Raid._tick_crates` refills an
  emptied marker after `WorldDef.crate_respawn_time` and clears a crate
  left lying away from the markers after `crate_lifetime`. It scans the
  crates only (a few dozen), never the actors.
- Checks: `tests/dunes_haul_tests.gd`.
- Sandstorms (DESIGN.md "The Dune Sea (part two, built: sandstorms)"):
  the shared weather with `weather_kind` "sand" (`Look.WEATHER_KITS`
  "sand": an ochre wall, grit driven flat), each storm aimed through a
  wreck field (`weather_path` in `worlds/dunes/world.gd`). Burying is
  generic (`WorldDef.weather_buries`): the map's "salvage_field" markers
  (one per wreck field, its hulks its children, meta "radius", "sink",
  "title") are `Raid.fields`, the same list on every machine. Only the
  authority decides (`Raid._tick_fields`: a storm at strength 0.8 or more
  buries every open field within its heart, `radius * core_share`, and
  uncovers one buried field out of its reach for each, one it has passed
  if it can, told on the war feed); `Raid.set_field_buried` sinks or
  raises the field's scenery everywhere, and on the authority clears the
  crates lying in a buried field (never one held or in cargo) and fills
  every spot of an uncovered one at once. A buried field's spots never
  refill (`_tick_crates`). `NetSession._fields` sends the buried flags
  (`Raid.pack_fields`) on joining and on every change. The navigation is
  baked with every field open; a buried field's hulks only leave holes
  bots walk round. `fields_buried_at_start` begin buried, by the raid's
  seed. Check it with `tests/dunes_storm_tests.gd` and by eye with
  `--sandstorm-only`.
- Convoys (DESIGN.md "The Dune Sea (part three, built: convoys and roof
  guns)"): the world event "convoy" (`Raid.start_event`, chosen at random
  with the warlord and the supply pod where a world has
  `WorldDef.convoy_vehicles` and its map `convoy_routes`). Generic in
  `Raid` (`_start_convoy`, `_drive_convoy`, `_end_convoy`, `convoy`):
  the hauler first with its cargo full of crates, each vehicle driven by a
  bot of `convoy_faction` whose brain is off while the road drives it
  (`_drive_convoy` sets its `cmd.move` toward the next route point, at
  `convoy_throttle`, slowing into turns and for the one ahead), and
  `convoy_riders` bots more aboard (the rover's first seat is its roof
  gun). Its driver gone, the hauler spills its cargo (`spill_cargo`;
  `_drop_hauled` does it too as the driver dies), every convoy bot gets
  off with its brain back, the event ends and they and the vehicles stay
  as ordinary ones. Through or timed out, it is cleared away with its
  crates, save a vehicle with a player aboard. Online it needs nothing of
  its own: the vehicles, riders, seats and crates go by the usual ways.
  The Dune Sea's roads (`CONVOY_ROUTES` in its map) run yard to yard and
  pass the wreck fields 60 m off. Check it with
  `tests/dunes_convoy_tests.gd` and by eye with `--convoy-only`.
