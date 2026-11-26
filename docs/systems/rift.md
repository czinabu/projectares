# The Basalt Rift

Rules for `worlds/rift/` (DESIGN.md "Basalt Rift", "The Basalt Rift (part
one, built: the world and updrafts)", "(part two, built: the Sky
Leviathan)", "(part three, built: the rig rewards)"). Check it with
`tests/rift_tests.gd`, `tests/rift_leviathan_tests.gd` and
`tests/rift_rewards_tests.gd`, and by eye with `visual_check.tscn --
<dir> --rift-only`, `--leviathan-only` and `--trails-only`.

## The map

- A small, tall world over lava (`worlds/rift/map.gd`): the rift's floor
  (`FLOOR_Y`) lies under the lava (`LAVA_Y`), and the cliffs climb past
  `FIELD`. The floor and cliffs are a `Terrain` outside the navigation
  region: solid, so a body falls onto them, but never walked by a bot.
  A bot whose goal lies past an edge or on another mesa walks to its
  path's walkable end and stops there (`BotBrain._onto_nav`,
  `ARRIVE_STOP`), and every Rift bot carries the meta "edge_guard"
  (`equip_bot`), so a step, a side-step out of a jam included, that would
  leave the navmesh slides along its edge instead (`_keep_on_ground`).
  Bots stay on their mesa (`tests/rift_bots_tests.gd`; before, most walked
  off and burned within a minute; a rare one still slips off a lip rock).
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

## The Sky Leviathan

- A world event of the core's airship kind (`worlds-and-war.md`, "World
  events"; `vehicles.md`, the "airship" tag). The world names its ship
  (`LEVIATHAN`, item `rift_leviathan`, registered in `register_items`,
  tagged "airship", never "vehicle", so nobody owns one), its faction
  ("leviathan") and its passes (3); the map gives its routes
  (`AIRSHIP_ROUTES`, `airship_routes`): each comes in high over a cliff,
  crosses the rift and climbs out over the other.
- Its weak spots are `LEVIATHAN_SEATS` (where on the ship, which piece the
  model builds there) and `LEVIATHAN_PARTS` (each kind's body, health,
  armor, and metas): four engine pods hung under the keel, two spine
  plates on its back, two turrets on its tower. `equip_bot` builds one by
  its `boss` meta (`_make_leviathan_part`): no randomness, a hidden body
  (skin "ship_part"), a wider one (`Actor.set_body_radius`), nothing
  carried. Only the turrets fight, with the seat's gun
  (`rift_leviathan_gun`); a spine plate is soft only to a hit from steeply
  above (`rear_damage_mult`, `rear_arc_deg` 0).
- Heights: over the rift a pod's middle is within a Mk1 jetpack's reach
  held at its ceiling, and the plates and turrets are over it, for whoever
  rides an updraft or dives off the Crown (the test checks the routes).
  Keep the routes so, and keep perches out of them (`_in_airship_lane`:
  none within `AIRSHIP_LANE` of a route stands within `AIRSHIP_HEADROOM`
  of its keel).
- A broken weak spot drops `roll_loot("airship_part")` under it; the crash
  drops the hold, `roll_loot("airship_hold")` with a supply pod's war loot.

## The rig rewards

- The rift's blueprints are the flight rigs' only: the world overrides
  `roll_crafting_loot` to pick from `RIG_BLUEPRINTS`, so the warlord
  (`warlord_blueprint_chance`, `warlord_upgrade_data`) and anything else
  that asks never hands out a gun or vehicle blueprint here.
- The Crown's three caches carry `loot_source` "crown" (`CROWN_TABLE`, with
  upgrade data and the rig blueprints); the plain cache table holds no
  upgrade data. A Crown cache counts as "cache:crown", not toward the
  "cache:cache" contract.
- The Leviathan pays rig rewards in its own tables: `LEVIATHAN_PART_TABLE`
  holds upgrade data, and `roll_loot("airship_hold")` adds
  `LEVIATHAN_HOLD_DATA`, a rig blueprint at `LEVIATHAN_HOLD_BLUEPRINT` and
  the earned Leviathan trail at `LEVIATHAN_TRAIL_CHANCE`. The world leaves
  `pod_upgrade_data` and `pod_blueprint_chance` at 0, so supply pods stay
  as they were.
- The warlord's earned cosmetic is a thruster trail, Magma
  (`warlord_paint`, which takes any earned cosmetic item).

## Rules

- Thruster boots count their ceiling from the floor last stood on
  (`rig_ceiling_from_floor`, Caleb's call), so a kick still lifts off a
  mesa or a perch; every other rig counts from the lava's floor, so only
  an updraft gets a jetpack onto the Crown. `Actor._measure_altitude`
  keeps the floor (`_floor_y`) and asks the world once per rig worn.

- Ashfront's death rule (`death_drops_scrip`): the fallen drop scrip, not
  gear. The starter kit carries the Mk1 jetpack.
- The roster (`ROSTER` in `worlds/rift/world.gd`) is the Crown's cult
  (Caleb's call, DESIGN.md "Own rosters"): zealots, sharpshooters, Slag
  Brutes and Magma Crawlers. None of it flies; its sharpshooters see far
  (90 m), since the rift is all long sight lines. Every kind keeps to its
  mesa (`edge_guard`).
- A Magma Crawler leaves burning ground: its row's "trail" meta (a cloud
  as `Raid.burst_cloud` takes it, kind "fire", and "every") makes the
  Raid leave a cloud at its feet as it moves on (`Raid._tick_trails`,
  authority only, never two on one spot), which hurts the other side
  through `Combat.deal` like any cloud and is shown as a low ember haze.
- Cinder Hounds are built by `equip_bot` for the map's "spawn_guard"
  markers of faction "hound" (`HOUND`), three to a den on each outer
  stack (`HOUND_PACK`), and fight for the cult (faction "rift"). They come
  back like any guard (`guard_respawn_time`).
- No army roams: each mesa is an encounter pocket by the site's name
  (`pocket_wake` 110 m, a budget of 12), three of the cult on the Anvil
  and two on each outer stack, which shares its pocket with the den (five
  in one fight). The perches keep "spawn_bot" markers for events only.
- The Lord of the Crown is always one of the cult's people: `bot_allowed`
  turns away a crawler rolled as a warlord. The roster's numbers follow
  Ashfront's for the same roles (`BOT_SKILL`, `ZONE_TOUGH`, DESIGN.md
  "Enemy balance"); a row may keep its own ring curve ("tough") or a shell
  as thick in every ring ("flat_armor").
