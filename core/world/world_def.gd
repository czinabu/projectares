class_name WorldDef
extends RefCounted
## The world contract. Every world is a folder under res://worlds/ with a
## `world.gd` that extends this class.
##
## Core code only ever talks to a world through this class, and never names a
## specific world. To add a world: copy a world folder, change the fields in
## `_init`, and override the hooks you need.
##
## Map contract: `create_map()` returns a Node3D that, once in the tree, has
##   - Marker3D nodes in group "spawn_player"
##   - Marker3D nodes in group "spawn_bot" (optional meta "faction": the
##     Raid sets it as the bot's faction before `equip_bot`, and sends new
##     bots where their faction is shortest of them)
##   - Marker3D nodes in group "spawn_cache" (optional meta "loot_source")
##   - Depot nodes in group "depot": where players bank what they carry
##   - optionally Marker3D nodes in group "spawn_vehicle" (optional meta
##     "loot_source", default "vehicle", and "respawn", seconds before an
##     emptied spot gets a new vehicle, default `vehicle_respawn_time`). The
##     Raid parks the first vehicle-tagged item from `roll_loot` there,
##     facing the marker's yaw.
##   - optionally Marker3D nodes in group "spawn_crate": a salvage crate
##     stands on each (`SalvageCrate`), filled from `roll_loot("crate")`
##     (or the marker's "loot_source"), and a new one after
##     `crate_respawn_time` once it has gone.
##   - optionally Marker3D nodes in group "salvage_field": a field of
##     salvage a storm can bury (`weather_buries`), meta "radius" (the
##     ground it covers, flat distance), "sink" (how far down its scenery
##     goes when buried, default 4 m) and "title" ("a wreck field"). Its
##     scenery (hulks) are its children, so they sink with it; the
##     "spawn_crate" markers inside its radius stand empty while it is
##     buried.
##   - optionally a `convoy_routes()` method: an Array of routes, each an
##     Array of Vector3 points on the ground a convoy drives through in
##     order (`WorldDef.convoy_vehicles`).
##   - optionally a `bake_navigation()` method for bot pathfinding
##   - optionally a `ground_height(x, z)` method, on a map with open ground
##     that is not level (see `core/world/terrain.gd`). The Raid stands
##     players and bots on it when they spawn. Flight rig ceilings are
##     measured from it too (`FlightRig.ceiling`); a map without one has its
##     ground level at its own origin, so keep the floor there.
##   - optionally Marker3D nodes in group "strongpoint": sites to capture and
##     hold. Metas: "name" (String), "radius" (float, metres), and optionally
##     "holder" (a bot faction that holds it from the start) with
##     "holder_name" (what to call them). Put a depot near each one.
##
## Safe zones (`safe_zone = true`) are social spaces, not raids: nobody can be
## hurt, weapons and abilities are locked, nothing respawns, and players show
## up wearing their loadout without taking it out of the stash. Their map
## needs only "spawn_player" markers, and may add:
##   - Marker3D nodes in group "portal" with meta "destination" ("world:<id>",
##     "home", or anything the game's flow understands), "label" (what the
##     prompt says) and optionally "radius" (metres, default 3). A player
##     standing in one is offered the trip; see `core/social/plaza_view.gd`.
##     A portal that opens a screen (a shop) may have a child Node3D named
##     "Screen": a terminal's face, centred on it and facing its +Z, 1.6 by
##     0.9 metres. The screen is shown there (`WorldScreen`). A destination
##     "talk:<id>" is a person to talk to, answered by the view itself. A
##     portal at a counter may name its "keeper" (a talker id), who greets
##     whoever uses it. A portal may have a hidden child Node3D named "Lit"
##     (an arch's light), shown while a player stands in it. Nothing marks a
##     portal on the floor: you walk up to a person, a counter or an arch.
##   - Marker3D nodes in group "talker" with meta "id", "yaw", "name" and
##     "role": where the people you talk to stand
##     (`core/social/plaza_locals.gd`), and optionally "lines" (what they
##     say, in turn), "reads" ("worlds": the dispatcher reads `world_status`
##     out), "color" (their speech card's), "dress" (`Human.random`'s pool,
##     what they wear for their work) and "shop" (a keeper's shop id: they
##     talk about its real stock and the player's account,
##     `PlazaLocals.stock_lines`).
##   - optionally a `locals_layout()` method: where the place's locals spend
##     their day, as plain data (see `worlds/plaza/map.gd`). Without it the
##     place has no crowd. A "street" ({from, to, lane}) has shoppers walk
##     its lanes and cross only at doors instead of a "promenade" ring.
##     "stops" (street carts) get a cook each and customers who queue in
##     turn, eat at the tables and walk on.
##   - a Label3D in group "wanted_board": the most-wanted board, written by
##     `PlazaView` from `world_status`.
##
## Risk zones (DESIGN.md section 2, "Risk zones"): a world may split its map
## into tiers by overriding `zone_at` (0 the outer ring, 1 the middle, 2 the
## core) and `hazard_at`, and its map may add:
##   - Marker3D nodes in group "outpost": gate outposts, small safe bubbles
##     inside a PvP world. Metas: "name" and "radius" (metres). The Raid
##     shelters a player inside one (weapons locked, cannot be hurt) unless
##     they arrive in a fight or carrying a bounty, and gives them
##     `spawn_protection` again as they walk out. Put a depot and the player
##     spawns inside them.
##   - Marker3D nodes in group "spawn_boss": a boss (a bot made a warlord)
##     stands guard there, and comes back `boss_respawn_time` after it dies.
##     Optional metas: "faction" (as on "spawn_bot"), "radius" (the ground it
##     guards) and "boss" (a kind of boss of the world's own, set on the bot
##     as meta "boss" before `equip_bot` and `make_warlord`, and sent to
##     clients so they build the same one), "respawn" (seconds before it
##     comes back, in place of `boss_respawn_time`), and "keeper" (true: a
##     dungeon's last fight, see below; it carries no loot of its own) with
##     "arena" (metres round the marker its fight runs in).
##   - A keeper's fight, markers naming its kind (the "boss" meta) in meta
##     "keeper": "boss_socket" markers in its walls that it calls its
##     "faction" out of while it is above `keeper_split` of its health;
##     "purge" lanes (meta "toward", the lane's far end; "width", "damage")
##     that warn and then vent across the floor once it is below; a "vault"
##     where a share for each player who fought it (`roll_vault`) is laid
##     out along the marker's x when it falls; "boss_snag" markers (meta
##     "radius", "stun"), solid things a keeper that charges can ram: one
##     that drives into a snag in a dash-strike is staggered "stun" seconds
##     (`keeper_snag_news`); "boss_pool" markers, where a keeper that dives
##     comes up (see `keeper_dive_up`); and a "beacon" or "warmth" with the
##     meta stays dark while it stands.
##   - Marker3D nodes in group "spawn_guard": a dungeon's garrison. A bot of
##     the marker's "faction" stands guard over "radius" metres (10 by
##     default) round it, outside the armies, and another comes back
##     `guard_respawn_time` after it dies.
##   - Marker3D nodes in group "lift_stop": a lift's two stops (meta "lift",
##     the lift's id; "radius" metres). Once it is powered, a player who
##     stands `lift_wait` in one stop's ring is carried to the other.
##   - Marker3D nodes in group "lift_power": the switch that powers a lift
##     (meta "lift", "radius"). A player who stands `lift_power_time` in its
##     ring powers it for `lift_powered_for`, for every player in the world.
## The cold (DESIGN.md section 2, "Frostline"): a world with `cold` over 0
## drains its players' body heat (`Actor.body_heat`) by `cold_at` a second
## out in the open, and its map may add warmth:
##   - Marker3D nodes in group "warmth": a heater, a vent, a fire. Metas
##     "radius" (metres) and "warmth" (body heat a second given back to
##     anyone within it, and within 3 m up or down).
## A running vehicle's engine warms its riders and anyone close to it
## (`engine_warmth`). Body heat gone, the cold hurts by `cold_damage` a
## second through `Combat.deal`.
##
## Warm beacons (DESIGN.md "Frostline"): a world with `sign_out_at_beacons`
## lets players sign out only at a beacon, and its map adds:
##   - Marker3D nodes in group "beacon". Metas "name" and "radius" (metres).
##     A sign-out started inside one powers it up for `beacon_sign_out_time`;
##     the countdown only runs while the player stays inside, and runs
##     faster for each other player powering the same beacon
##     (`beacon_join_bonus`, up to `beacon_join_cap` times as fast). It is
##     still `Raid.begin_sign_out`, so a fight cancels it as anywhere.
##
## The Raid marks each spawned bot with the tier it arrived in (meta "zone")
## before `equip_bot`, so a world can make bots tougher further in.
##
## Looks: a world may give a bot a model with `bot.set_meta("look", "<skin>")`
## in `equip_bot`. The skins are listed in `core/visual/look.gd`.

var id := ""
var display_name := "Unnamed world"
var description := ""
## How many bots the world keeps alive. A dead one is replaced after
## `bot_respawn_time` seconds, away from the players.
var bot_count := 8
## How many players a server lets into one copy of the world at once.
var max_players := 8
## A social space with no combat and nothing at stake. See "Safe zones" above.
var safe_zone := false
var bot_respawn_time := 45.0
## Seconds an emptied cache takes to fill again.
var cache_refill_time := 240.0
## Seconds before a vehicle that left its parking spot is replaced there, and
## before a vehicle nobody rides is cleared away.
var vehicle_respawn_time := 300.0
## Salvage crates (`SalvageCrate`, the "spawn_crate" markers): seconds before
## a marker whose crate has gone gets a new one, and before a crate left
## lying anywhere else, nobody holding it, is cleared away.
var crate_respawn_time := 240.0
var crate_lifetime := 600.0
## Salvage fields (the map's "salvage_field" markers; DESIGN.md "The Dune
## Sea (part two)"): with `weather_buries` a storm buries every field its
## heart crosses (its crates lying there are gone, its markers stand empty)
## and for each one uncovers a buried field away from the storm, every
## crate spot in it filled at once. `fields_buried_at_start` of them begin
## buried.
var weather_buries := false
var fields_buried_at_start := 0
## Whether players may throw the toy vehicles on their watch here (see
## `Raid.throw_toy`). Off, a brought vehicle stays on the watch.
var vehicle_toys := true
## Seconds a dead actor's bag lies around before it is cleared away.
var bag_lifetime := 300.0
## Seconds to stand in a depot to bank what you carry.
var depot_hold_time := 4.0
## The planet this world stands on (DESIGN.md "Planet kit"): a
## `PlanetTypes` id, or "" for a world that builds its own look. Set it with
## `take_planet` at the top of `_init`, which also gives the world the
## planet's rule defaults (`PlanetType.rules`: `cold`, `shot_carry` and
## `planet_grip`); anything the world sets after that is its own.
var planet := ""
## The ground's grip where the world's own `surface_grip` does not say.
var planet_grip := 1.0
## Body heat (of 100) a player loses each second out in the open; 0 for a
## world with no cold. See "The cold" above and `cold_at`.
var cold := 0.0
## Damage a second once body heat is gone, through `Combat.deal`.
var cold_damage := 4.0
## Body heat a second a running vehicle gives back to its riders and anyone
## within `engine_warmth_radius` metres of it.
var engine_warmth := 6.0
var engine_warmth_radius := 4.0
## Seconds a sign-out takes on the ground. Taking or dealing damage cancels it.
var sign_out_time := 15.0
## Warm beacons: whether a sign-out must start at a "beacon" marker (see the
## map contract above), how long one takes to power up, and how much each
## other player at the same beacon speeds it. Off by default.
var sign_out_at_beacons := false
var beacon_sign_out_time := 20.0
var beacon_join_bonus := 0.5
var beacon_join_cap := 2.0
## Tracks (DESIGN.md "Frostline"): with `tracks` on, people on foot leave
## footprints and ground vehicles wheel tracks in the open ground (the map's
## `ground_height`, never a roof or a floor), kept by the authority for
## `track_lifetime` seconds and sent to each player only near them
## (`Tracks`, `Raid.tracks`). Off by default.
var tracks := false
var track_lifetime := 240.0
## How far a gunshot carries, as a share of the usual: bots hear it that much
## further off (`Combat.noise`) and so do people (`Gun.SHOT_REACH`).
var shot_carry := 1.0
## Fouling (DESIGN.md "Spore Marsh", Caleb's call): how fast sustained fire
## fouls a gun here, as a rate on its `Gun.foul_per_shot`. A fouled gun
## spreads wider and a long burst jams it until a reload. 0, the default,
## leaves guns alone.
var gun_fouling := 0.0
## Weather (DESIGN.md "Weather: ash storms"): with a `weather_kind` ("ash",
## "snow", "rain"; "" for none) storms cross the map one at a time (`Weather`,
## `Raid.weather`), named `weather_name` on the watch and the plaza's signs.
## Each is a cell `weather_radius` across its middle, moving at
## `weather_speed` along `weather_path`, building and dying away over
## `weather_ramp` seconds, with a quiet spell of `weather_gap` seconds
## between (the first after `weather_first`). In the thick of it sight
## and scan reach drop to `weather_sight` of usual, shots carry
## `weather_carry` as far (and so do footsteps, to a bot listening),
## flight rigs are pushed by gusts up to
## `weather_gust` m/s² (times the rig's `gust_mult`), body heat drains
## `weather_cold` times as fast, and with `weather_wipes_tracks` the
## storm wipes the tracks it passes over. Guns foul `weather_fouling`
## times as fast in its thick (`gun_fouling`: a rain that washes what
## fouls them out of the air). With `weather_pushes` the armies go for a
## strongpoint a storm covers. Off by default.
var weather_kind := ""
var weather_name := "Storm"
var weather_radius := 150.0
var weather_speed := 2.5
var weather_ramp := 40.0
var weather_gap := Vector2(360.0, 720.0)
var weather_first := Vector2(120.0, 360.0)
var weather_sight := 0.5
var weather_carry := 0.6
var weather_gust := 6.0
var weather_cold := 1.0
var weather_fouling := 1.0
var weather_wipes_tracks := false
var weather_pushes := false
## How far from the map's middle storms cross (metres), for the default
## `weather_path`.
var weather_field := 280.0
## The war's artillery (DESIGN.md "Shelling", `core/war/shelling.gd`): how
## often salvos come down near the fighting, as a rate on `Shelling.every`
## (sooner the hotter the war). Each spot is marked before its shell lands,
## and the shells hurt. 0 keeps the world unshelled.
var shelling := 0.0
## A sea of lava (DESIGN.md "Basalt Rift"): anything whose feet go under
## `molten_level` (a height in metres) burns for `molten_damage` four times
## a second through `Combat.deal`, players and bots alike, whatever the
## zone rules (`Raid._tick_molten`). A death over it leaves its bag or pile
## floating on it, where a flyer can still reach it (`Raid.drop_spot`).
## -INF: no lava.
var molten_level := -INF
var molten_damage := 50.0
## Thin ice (DESIGN.md "Frostline"): with `thin_ice` on, the ground where
## `thin_ice_at` says so bears a ground vehicle up to `ice_holds` tonnes
## (its "weight" stat). A heavier one strains it by its weight over that a
## second, cracking audibly on the way, and at `ice_break_strain` it breaks
## through: the vehicle sinks, its riders go into the water, and the hole
## stays open for `ice_refreeze` seconds (`Raid._tick_ice`). Off by default.
## With `ice_keeps_vehicle` the sunk vehicle is not lost: the watch of
## whoever threw it (else its driver) pulls it back out as a toy.
var thin_ice := false
var ice_keeps_vehicle := false
var ice_holds := 1.0
var ice_break_strain := 10.0
var ice_refreeze := 150.0
## Seconds a sign-out takes while airborne. Progress already earned is kept
## when you land or lift off, so the seconds left are whatever the rate you
## are on still needs (DESIGN.md section 7). The exact air time is this.
var sign_out_air_time := 25.0
## Seconds the body of a player who quit in a fight stays in the world.
var combat_log_time := 30.0
## Seconds after a hit, given or taken, that a player counts as in a fight.
var combat_time := 6.0
## Seconds a player who just dropped in cannot be hurt. Ends when they attack.
var spawn_protection := 4.0
## Death stakes. False is full loot: a dead player drops everything. True is
## a gentler world: the gear they had equipped goes back to their stash and
## only the backpack drops.
var keep_gear_on_death := false
## Scrip piles (DESIGN.md "Scrip piles", Caleb's call for Ashfront): a dead
## player or bot drops no gear. What they lost is gone, and a glowing pile
## of scrip worth what a trader pays for it (`Economy.sell_price`) lies
## where they fell, with their carried scrip, for whoever runs over it
## first, beside one bonus item from their pack. Gear then only comes from
## caches, pods and racks. The rest of these tune it.
var death_drops_scrip := false
## A bot's pile is this share of what its pack would sell for, so the war's
## dead do not flood the world with scrip...
var bot_pile_share := 0.5
## ...growing by up to this share again as the war heats up
## (`war.intensity`), so the big fights pay best. Players' piles never grow.
var pile_war_bonus := 0.5
## The bonus item: one pick from the pack, usually something small
## (medkits, materials, attachments), and with this chance something the
## dead found this life instead, if they found any gear.
var pile_found_chance := 0.15
## How close a body must come to grab a pile, and how far away a visor
## shows one (`VisorHud.compass_marks`, the "pile" mark).
var pile_reach := 1.4
var pile_seen_range := 80.0

## Keeping fresh players from strong ones (DESIGN.md "Challenge and balance
## data"): a player who brought less than `fresh_gear_value` of gear (by
## item value) lands at the arrival point furthest from anyone who brought
## `strong_gear_value` or more, each of whom counts as
## `strong_player_wariness` times as near (`Raid._safest_spawn`). 0 is off.
var fresh_gear_value := 0
var strong_gear_value := 0
var strong_player_wariness := 3.0
## True when every player here is on one side (a co-op world). Strongpoints
## then belong to the players together, not to whoever took them.
var players_allied := false
## Seconds between bot pushes on a strongpoint that players hold, and how
## many bots go. 0 bots turns the pushes off.
var assault_interval := 120.0
var assault_size := 3
## Bots the world adds on top of `bot_count` as the war heats up: this many
## more at full war intensity, and a share of them below it. They arrive one
## every `reinforcement_time` seconds and are not replaced once it cools.
var war_reinforcements := 0
var reinforcement_time := 5.0
## True where the bot factions fight each other over the strongpoints: each
## keeps `garrison_size` bots on every site it holds and sends the rest
## against the nearest site it does not.
var bots_contest_sites := false
var garrison_size := 4
## How strongly fighting raises this world's war intensity (see
## `core/war/war_director.gd`). 0 keeps the world quiet whatever happens.
var war_scale := 1.0
## Power weapons (items tagged "power", see `core/war/power_armory.gd`):
## racks at strongpoints, beside supply pods and now and then beside a
## refilled cache, more often the hotter the war. A multiplier on how often
## they turn up; 0 keeps them out of this world.
var power_weapon_rate := 1.0
## World events: every so often the war throws something worth fighting over
## into the world, a supply pod or a warlord with an escort. This is the
## seconds between them while the world is quiet; an all-out war halves it.
## 0 turns events off.
var event_interval := 420.0
## Seconds an event stays before it is cleared away.
var event_lifetime := 300.0
## How many bots march with a warlord.
var warlord_escort := 2
## Convoys (DESIGN.md "The Dune Sea (part three)"): a world event of armed
## vehicles driving one of the map's `convoy_routes`. `convoy_vehicles`
## are item ids, the first the hauler (its cargo full of crates from
## `roll_loot("crate")`), the rest its escort; each is driven by a bot of
## the world's roster with `convoy_riders` more aboard on its seats, at
## `convoy_throttle` of its top speed, all of `convoy_faction`. Drop the
## hauler's driver and its cargo spills on the sand; the escort gets off to
## fight. Empty: no convoys.
var convoy_vehicles: Array[String] = []
var convoy_faction := ""
var convoy_riders := 1
var convoy_throttle := 0.55
## Airships (DESIGN.md "Basalt Rift", the Sky Leviathan): a world event of
## an armoured airship (`airship_vehicle`, an item tagged "airship") that
## drifts back and forth along one of the map's `airship_routes` (points
## with their height) `airship_passes` times, then drifts off. Each of its
## seats with a "part" holds a weak spot: a bot of `airship_faction` whose
## `boss` meta is that part, built by `equip_bot`. A weak spot broken drops
## `roll_loot("airship_part")` under the ship; all of them broken, it goes
## down and its hold (`roll_loot("airship_hold")` and a supply pod's war
## loot) lands where it crashes. Empty: no airships.
var airship_vehicle := ""
var airship_faction := ""
var airship_passes := 3
## Artifacts (items tagged "artifact", DESIGN.md section 6). Until the PvE
## dungeons and arena tournaments that should hand them out exist, world
## events do: the chance that a warlord carries one, and that a supply pod
## holds one. 0 keeps them out of this world.
var warlord_artifact_chance := 0.25
var pod_artifact_chance := 0.05
## An earned cosmetic a warlord may carry, and the chance it does: an armor
## paint (DESIGN.md "Armor paints", an item tagged "paint") or a thruster
## trail (`RigTrail`, tagged "trail") that no shop sells.
## "" or 0 keeps it out of this world.
var warlord_paint := ""
var warlord_paint_chance := 0.0
## Blueprints and upgrade data (DESIGN.md section 10) come from the fights
## worth having: the chance that a warlord carries a blueprint and that a
## supply pod holds one, and how much upgrade data each always has. 0 keeps
## them out of this world, which is the default: only a PvP world hands
## them out.
var warlord_blueprint_chance := 0.0
var pod_blueprint_chance := 0.0
var warlord_upgrade_data := 0
var pod_upgrade_data := 0
## Risk zones: seconds before a core boss comes back after it dies, and the
## sign-out time while sheltered in a gate outpost (it is the way out there).
var boss_respawn_time := 360.0
## How far down the world goes: anyone below this height has fallen out of
## it and dies (`Actor`). A map with levels under its ground (Frostline's
## Engine) lowers it.
var void_y := -30.0
## No world sets `void_y` higher than this.
const VOID_Y_MAX := -30.0
## Seconds before a guard at a "spawn_guard" marker comes back after it dies.
var guard_respawn_time := 240.0
## A lift (see "lift_stop" and "lift_power" above): how long a player stands
## at its switch to power it, how long it then runs for everyone, and how
## long a rider waits in a stop before it carries them.
var lift_power_time := 4.0
var lift_powered_for := 600.0
var lift_wait := 2.5
var outpost_sign_out_time := 3.0
## A boss made for one player is a wall for none and a pushover for four,
## so where this is over 0 it gets tougher with company: each player past
## the first within `boss_party_range` of it adds this share to its
## `Actor.toughness` (hits are divided by it). Authority only.
var boss_party_scale := 0.0
var boss_party_range := 45.0
## A keeper's fight (see "spawn_boss" above): seconds between Wardens called
## from its sockets and how many may be out at once (one more for each
## other player in its arena), the share of its health below which it turns
## to its purges, seconds between volleys, how many lanes a volley vents and
## how long each warns first, and the first wait of each once someone comes
## in.
var keeper_socket_every := 14.0
var keeper_socket_max := 3
var keeper_socket_first := 4.0
var keeper_split := 0.5
var keeper_purge_every := 5.5
var keeper_purges_at_once := 2
var keeper_purge_warn := 1.6
var keeper_purge_first := 2.0
## A keeper with "boss_pool" markers dives: up and fighting for
## `keeper_dive_up` seconds (`keeper_dive_up_hurt` once below
## `keeper_split`), then under, where nothing hurts it (`Actor.submerged`),
## for `keeper_dive_under`, then it rises at the pool nearest one of the
## players in its arena, unhurtable for `keeper_dive_rise` more while it
## comes up (its brain holds it down and lets it up, so clients see it
## through its crouch).
var keeper_dive_up := 6.0
var keeper_dive_up_hurt := 4.0
var keeper_dive_under := 2.5
var keeper_dive_rise := 1.4
## Linked factions (DESIGN.md "Frostline", the defence grid): faction to
## range in metres. A bot of one that is hurt and lives calls every other
## bot of its faction within range to where the hit came from, the way a
## gunshot is heard (`Actor.heard`), so a drawn-out fight brings the rest.
## A kill in one blow calls nobody.
var linked_factions := {}
## Grudges (DESIGN.md "The enemy AI pass", step 5): the bot factions that
## remember a player for one life. Hurting one of its bots raises that
## army's grudge (`grudge_per_damage` a point of damage, `grudge_per_kill`
## a kill), it fades by `grudge_fade` a second, and death clears it. Over
## `grudge_hunt` the army sends a few of its bots after that player, to
## where they roughly are, every `Raid.GRUDGE_EVERY` (still through the
## brain's hunter and leash limits), and the player's visor says so.
## Empty keeps no grudges.
var grudge_factions: Array[String] = []
var grudge_per_damage := 1.0
var grudge_per_kill := 60.0
var grudge_fade := 3.0
var grudge_hunt := 300.0
var grudge_cap := 700.0
## Battles by ground (DESIGN.md "The enemy AI pass", step 4): how an army
## fights where it stands. `ground_at` names a place's kind of ground and
## `ground_styles` says how a soldier there fights, {kind: {key: value}}:
## "range" scales the distance it keeps, "hunters" is added to how many may
## leave their ground to hunt one person, "leash" (metres) is how far past
## its ground it may chase, and "notice" scales how long it takes to spot
## someone. The `Raid` sets them on each soldier with its orders
## (`BotBrain.set_ground`), so they are authority only; empty changes
## nothing. Kinds the `Raid` names itself: "line" for a soldier on a
## "line_post" marker and "siege" for a team ringing a held site.
var ground_styles := {}
## The share of an army's soldiers the `Raid` keeps on its "line_post"
## markers (meta "faction"), a standing skirmish line, before the
## commander sends the rest out. 0 leaves the posts empty.
var line_share := 0.0
## Sieges: a team sent at a site the other side holds with at least
## `siege_holders` near it first rings it from `siege_reach` metres past
## its edge for `siege_time` seconds, trading fire, before it goes in.
## 0 seconds goes straight in.
var siege_time := 0.0
var siege_reach := 22.0
var siege_holders := 2
## The bot kinds (meta "kind") that are an army's elite. A strongpoint
## marker with the meta "hot_at" (war intensity, 0 to 1) is fought over
## only once the war is that hot, and then only by elites, who go there
## first (`WarCommander.plan`).
var elite_kinds: Array[String] = []
## Contracts of its own (DESIGN.md section 10, "World-tagged contracts"):
## a world with a `contract_tag` ("expedition") puts `contract_jobs` on the
## board beside the jobs that count anywhere, and they count only in a world
## with the same tag (the result's "contract_tag"). Jobs as in
## `Contracts.JOBS`; give them ids no other world uses.
var contract_tag := ""


func contract_jobs() -> Dictionary:
	return {}


## Rival raiders: bots that play the way a player does (DESIGN.md section 2,
## "Rival raiders"). Each drops in at a player spawn with a real kit
## (`raider_kit`), loots caches, fights everyone, and after a while signs
## out with what it carries. Killed, it drops its whole kit in a bag. This
## many are kept in the world; 0 keeps them out. One arrives every
## `raider_gap` seconds until the count is met, and one that dies or signs
## out is replaced the same way.
var raider_count := 0
var raider_gap := 45.0
## Seconds a raider stays before it heads out: a random time in this range.
var raider_stay := Vector2(240.0, 540.0)
## A raider's gun aim (`BotBrain.skill`): the range each one rolls from. They
## drop in at the rim, but they aim like players who have been here before,
## not like the outer ring's rookies.
var raider_skill := Vector2(0.5, 0.8)


## Seconds between dying and being allowed to drop in again.
var redeploy_delay := 3.0
## False for a venue where nobody loses gear (the arena). The server then
## hands out the loadout without taking it out of the stash, and never settles
## a result into the stash (see `StashService.deploy`).
var gear_at_risk := true
## Off where nobody fights at all (a race world): weapons stay locked for
## everyone, on every machine, and nothing can be hurt.
var weapons_free := true
## Whether the watch's portal opens home from here (a sign-out with a door).
## The arena has none: you leave it from its panel.
var portal_home := true


## True where a heavy weapon from the armory wall may be carried into the
## chamber (DESIGN.md section 6): a PvP world, the only place they are found.
## Safe zones, the arena and a world with no power weapons leave it on the wall.
func carries_power_weapons() -> bool:
	return power_weapon_rate > 0.0 and not safe_zone and gear_at_risk


## Stands the world on planet type `id` and takes its rule defaults. Call
## it first in `_init`, before the world's own settings. An unknown id
## leaves the world as it was.
func take_planet(id: String) -> void:
	var type := PlanetTypes.get_type(id)
	if type == null:
		return
	planet = id
	cold = float(type.rules.get("cold", cold))
	shot_carry = float(type.rules.get("shot_carry", shot_carry))
	planet_grip = float(type.rules.get("surface_grip", planet_grip))


## The planet type this world stands on, or null.
func planet_type() -> PlanetType:
	return PlanetTypes.get_type(planet) if planet != "" else null


func create_map() -> Node3D:
	return null


## Works out, ahead of a visit, whatever every copy of this world's map
## shares (its ground), so the first arrival does not wait for it: a game
## calls this while it connects ahead of a trip (DESIGN.md section 14,
## "Travel that hides its wait"). It may run on a worker thread, so it must
## touch nothing in the scene tree. Nothing by default.
func prepare_map() -> void:
	pass


## The node that runs this world: a plain `Raid` for every world. A venue with
## its own rules (the arena) returns its own `Raid` subclass. Called on servers,
## clients and solo alike, so the same class runs everywhere.
func new_raid() -> Raid:
	return Raid.new()


## Register items that only this world adds, with ItemDB.register. Called once
## when the registry finds the world. Ids are global, so prefix them with the
## world id to avoid clashes. Items stay usable in every world once stashed.
func register_items() -> void:
	pass


## Item ids every raider gets for free when they deploy with nothing.
func starter_loadout() -> Array[String]:
	return []


## Items for a loot source: "cache", "rooftop", "bot", or anything a map defines.
func roll_loot(_source: String, _rng: RandomNumberGenerator) -> Array[String]:
	return []


## Loot for a source while war intensity is `intensity` (0 to 1). A hotter
## war pays better: the roll is repeated and the rarest haul wins. A world
## with tables of its own for wartime can override this.
func roll_war_loot(source: String, rng: RandomNumberGenerator, intensity: float) -> Array[String]:
	var best := roll_loot(source, rng)
	for i in roundi(clampf(intensity, 0.0, 1.0) * 2.0):
		var again := roll_loot(source, rng)
		if _haul_rarity(again) > _haul_rarity(best):
			best = again
	return best


func _haul_rarity(ids: Array[String]) -> int:
	var total := 0
	for id in ids:
		total += ItemDB.item_rarity(id)
	return total


## An artifact with chance `chance`, picked evenly from every item tagged
## "artifact", or "" for none.
func roll_artifact(rng: RandomNumberGenerator, chance: float) -> String:
	if chance <= 0.0 or rng.randf() >= chance:
		return ""
	var ids: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "artifact"):
			ids.append(id)
	if ids.is_empty():
		return ""
	ids.sort()
	return ids[rng.randi() % ids.size()]


## PvP rules live here. Called for every hit before damage is applied.
## What a world event adds for crafting: a blueprint with chance `chance`,
## picked evenly from every item tagged "blueprint", and `data` upgrade data.
## Expedition blueprints (tag "expedition") are left out: they turn up only
## where a world lists them in its own loot tables.
func roll_crafting_loot(rng: RandomNumberGenerator, chance: float, data: int) -> Array[String]:
	var out: Array[String] = []
	if chance > 0.0 and rng.randf() < chance:
		var ids: Array[String] = []
		for id: String in ItemDB.all_ids():
			if ItemDB.has_tag(id, "blueprint") and not ItemDB.has_tag(id, "expedition"):
				ids.append(id)
		if not ids.is_empty():
			ids.sort()
			out.append(ids[rng.randi() % ids.size()])
	for i in maxi(data, 0):
		out.append("upgrade_data")
	return out


## How sharp a bot's gun aim is (`BotBrain.skill`, 0 a rookie, 1 a veteran):
## the range each bot rolls from. Called on the authority only, before the
## brain starts; a world with risk zones can read the bot's meta "zone".
func bot_skill_range(_bot: Actor, warlord: bool) -> Vector2:
	return Vector2(0.7, 0.9) if warlord else Vector2(0.25, 0.75)


## The risk zone at a point: 0 the outer ring, 1 the middle, 2 the core, or
## -1 for a world without zones.
## The colour a bot faction wears on the plaza's War Room (its landmarks,
## its side of the front line). Plain worlds get one from the faction's name.
func faction_color(faction: String) -> Color:
	if faction == "":
		return Color(0.6, 0.65, 0.7)
	return Color.from_hsv(float(hash(faction) % 360) / 360.0, 0.6, 0.95)


## Big moments a world keeps on the wall clock rather than in its `Raid`
## (a set piece every screen times the same way), for the War Room: each
## {kind, text, at (unix seconds)}. None by default.
func clock_moments(_unix: int) -> Array[Dictionary]:
	return []


## The race circuits the War Room shows from outside (`Race`'s tracks, built
## from the map's data without the map). None for a world without races.
func feed_tracks() -> Array[RaceTrack]:
	return []


## What a bot faction is called in news ("the Legion"), for the war feed's
## lines about armies. Plain worlds use the faction's own name.
func faction_title(faction: String) -> String:
	return "the " + faction.capitalize()


func zone_at(_pos: Vector3) -> int:
	return -1


## The kind of ground at a point, for `ground_styles` ("" for none).
func ground_at(_pos: Vector3) -> String:
	return ""


## What a zone tier is called on the watch.
func zone_name(tier: int) -> String:
	return ["Outer ring", "Middle zone", "Core"][tier] if tier >= 0 and tier <= 2 else ""


## How fast the air rises at a point, in m/s (DESIGN.md "Basalt Rift",
## updrafts), or 0. Anyone in the air there is carried up by it on top of
## whatever they are doing (`Actor._ride_updraft`), a rig's ceiling or not,
## and wings spend no glide stamina in it. Worked out from the world's own
## data only, so a client predicts it the same.
func updraft_at(_pos: Vector3) -> float:
	return 0.0


## Whether the flight rig `rig_id` counts its ceiling from the floor its
## wearer last stood on (a mesa's top, say) rather than from the world's
## ground (`Actor._measure_altitude`). False everywhere by default, so
## roof-hopping never stacks a ceiling. Data only, so a client agrees.
func rig_ceiling_from_floor(_rig_id: String) -> bool:
	return false


## Damage a second that the ground at a point does to a player standing in it
## (heat, fumes), or 0. The Raid deals it through `Combat.deal`.
func hazard_at(_pos: Vector3) -> float:
	return 0.0


## Whether a point is sheltered: inside a building or underground, where no
## storm reaches (`Weather.strength_at` is 0 there) and no trail is laid
## (`Raid._track_mark`). A world's own `cold_at` decides the cold there.
func sheltered_at(_pos: Vector3) -> bool:
	return false


## How far anyone sees through the air at a point, in metres, or INF for
## clear air: a bot sees no further than the worse of where it stands and
## where its target does (`BotBrain._find_target`), as the view's close air
## shuts a player's eyes in there (a planet's `close` mood; the Spore
## Marsh's forests). Authority only, so it may read the map's layout.
func sight_at(_pos: Vector3) -> float:
	return INF


## Body heat a second a player at a point loses out in the open: `cold` by
## default. A world may make some places colder (higher, more exposed).
func cold_at(_pos: Vector3) -> float:
	return cold


## How much grip the ground at a point gives a wheel or a foot of a ground
## vehicle: 1 on dry ground, less on snow and ice, where wheels break loose
## and slide (`Vehicle._surface_grip`; a hover's cushion ignores it). Run on
## every machine that simulates a ride, so keep it free of randomness.
## By default the planet's grip (`take_planet`), the same everywhere.
func surface_grip(_pos: Vector3) -> float:
	return planet_grip


## Whether the ground at a point is thin ice (see `thin_ice`).
func thin_ice_at(_pos: Vector3) -> bool:
	return false


func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	return attacker != target and weapons_free


## Set up a bot's faction, gear and stats.
func equip_bot(_bot: Actor, _rng: RandomNumberGenerator) -> void:
	pass


## Whether a bot just equipped may join the world as it is (authority only).
## Refused, the `Raid` frees it and spawns another from a new seed, so a
## client only ever hears of the seed that was kept. A world caps its rare
## kinds here (Ashfront: one walker at each landmark).
func bot_allowed(_bot: Actor, _raid: Node) -> bool:
	return true


## A rival raider's kit: item ids exactly as a player's loadout, put on
## with `Loadout.equip`, so what it drops is real gear. Called on the
## authority only; the kit itself is sent to clients. The default is the
## world's starter kit.
func raider_kit(_rng: RandomNumberGenerator) -> Array[String]:
	return starter_loadout()


## Names rival raiders go by. A raider takes one nobody in the world is
## using, so a name in the war feed means one person.
func raider_names() -> Array[String]:
	return ["Vex", "Kestrel", "Juno", "Ashby", "Rook", "Sable", "Mercer", "Wren", "Talon", "Nyx",
			"Brandt", "Cinder", "Halloway", "Ixa", "Locke", "Moss", "Petra", "Quill", "Strand", "Voss"]


## Turns a freshly equipped bot into a warlord, the boss of a world event.
## Runs on clients too, so keep it free of randomness.
func make_warlord(bot: Actor) -> void:
	bot.display_name = "Warlord"
	bot.health.max_health *= 3.0
	bot.health.health = bot.health.max_health


## The war feed's line when a core boss stands guard again, `where` from
## the Raid ("near Echo Post").
func boss_back_news(_bot: Actor, where: String) -> String:
	return "A warlord has taken %s again" % where


## One player's share of a fallen keeper's vault (`kind`, its "boss" meta).
func roll_vault(_kind: String, rng: RandomNumberGenerator) -> Array[String]:
	return roll_war_loot("cache", rng, 1.0)


## What the world hears of a keeper: everyone in its arena when it turns to
## its second phase (`phase` 2), the war feed when it falls (0, `bot` may be
## gone). "" says nothing.
func keeper_news(_bot: Actor, phase: int) -> String:
	return "A keeper has fallen" if phase == 0 else ""


## A standing keeper's phase changed (1 or 2), on the authority: a world
## may change how it fights.
func on_keeper_phase(_bot: Actor, _phase: int) -> void:
	pass


## What everyone in a keeper's arena hears when it rams one of its snags
## and is stuck there. "" says nothing.
func keeper_snag_news(_bot: Actor) -> String:
	return ""


func on_spawn(_actor: Actor) -> void:
	pass


func on_death(_actor: Actor, _info: DamageInfo) -> void:
	pass


## Death bursts (DESIGN.md "Spore Marsh"): what a bot leaves where it falls,
## as {"radius": metres, "damage": a second, "seconds": how long it hangs,
## "kind": what it is ("spores")}, or {} for nothing. The cloud hurts
## everyone of another faction inside it through `Combat.deal`
## (`Raid._tick_clouds`, authority only) and is shown to everyone near.
## Runs on the authority only.
func death_burst(_bot: Actor) -> Dictionary:
	return {}


## Where the next storm comes in and where it leaves, as [from, to] on the
## ground plane. By default it comes in from beyond the rim on a random
## side, crosses near the middle (within 40% of `weather_field`) and leaves
## on the far side. A world whose map is not round (a valley) overrides it.
func weather_path(rng: RandomNumberGenerator) -> Array:
	var angle := rng.randf() * TAU
	var wind := Vector3(cos(angle), 0.0, sin(angle))
	var through := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * weather_field * 0.4
	var reach := weather_field + weather_radius
	return [through - wind * reach, through + wind * reach]

## A player left the world alive, taking what they carried home.
func on_leave(_actor: Actor) -> void:
	pass
