class_name Raid
extends Node3D
## One running world. It never ends: it builds the map, spawns everyone, and
## keeps the place alive by bringing bots, cache loot and vehicles back over
## time. Players drop in, fight, bank what they carry at a depot, die and drop
## in again, and leave when they choose. It knows nothing about any specific
## world; it only uses the WorldDef contract. It also knows nothing about
## cameras or the HUD, so the same class can run on a headless server.
##
## A player's stay is a string of lives. Each `add_player` starts one, and
## `player_finished` ends it, as "died" (what they carried is in a bag on the
## ground) or "left" (it all goes home). Whoever owns the stash, the local
## profile or the server's accounts, then calls `add_player` again to drop
## them back in.

## A player's life is over: they died, or signed out and left. The world
## carries on for everyone else.
signal player_finished(actor: Actor, result: Dictionary)
## A player banked `items` at a depot. They are out of the backpack and belong
## in the stash.
signal player_banked(actor: Actor, items: Array)
## What a player has banked this life changed (`Actor.banked_count`,
## `banked_value`, `banked_scrip`): items or scrip went home through a depot.
signal banked_changed(actor: Actor)
## A player's sign-out started, with `seconds_left` to go, or stopped (below zero).
signal sign_out_changed(actor: Actor, seconds_left: float)
## A line for everyone in the world: a player kill, a new bounty, the Marked.
signal war_feed(text: String)
## A strongpoint changed hands.
signal strongpoint_taken(point: Strongpoint)
## A world event began or ended. `event` is `Raid.event` ({} when it ended).
signal event_changed(event: Dictionary)
signal actor_spawned(actor: Actor)
signal actor_removed(actor: Actor)
signal container_spawned(container: LootContainer)
signal vehicle_spawned(vehicle: Node3D)
## A salvage crate was placed in the world (`spawn_crate`).
signal crate_spawned(crate: SalvageCrate)
## A salvage field was buried or uncovered (`set_field_buried`).
signal field_changed(index: int, buried: bool)
signal vehicle_removed(vehicle: Node3D)
## A player threw a toy vehicle off their watch. It flies from `from`.
signal toy_thrown(actor: Actor, item_id: String, from: Vector3, toy_velocity: Vector3)
## A thrown toy came to rest. `unpacked` is false if there was no room and it
## went back on the watch.
signal toy_landed(actor: Actor, item_id: String, at: Vector3, unpacked: bool)
## What a player's watch holds, or when they can throw again, changed.
signal watch_changed(actor: Actor)
## The toy in a player's hand (`Actor.toy_in_hand`) changed, or they started
## a throw (`Actor.toy_throws`).
signal toy_hand_changed(actor: Actor)
## A player pinged a spot for their side (`ping`). On a client it is only
## ever heard for pings the server chose to tell this player about.
signal pinged(actor: Actor, at: Vector3)
## A squad portal opened (`open_portal`), on the authority.
signal portal_opened(portal: Portal)
## A player walked into an open portal their side may use, on the authority.
## Whoever owns the player sends them to `destination` (a world id or the
## arena's) with the drop `PORTAL_DROP`.
signal portal_entered(actor: Actor, destination: String)
## A squad portal was closed early or folded away, on the authority.
signal portal_closed(portal: Portal)
## A player's contract counters for this life changed (`Actor.tally`).
signal tally_changed(actor: Actor)
## Thin ice (`WorldDef.thin_ice`) cracking under a heavy vehicle at `at`:
## `stage` 1 and 2 are warnings, 3 is the ice giving way. On every machine
## (a client hears it from `NetSession`), for the view.
signal ice_cracked(at: Vector3, stage: int)
## The open holes in the ice changed (`ice_holes`).
signal ice_changed
## A bot of a linked faction (`WorldDef.linked_factions`) called the rest of
## its faction to a fight. On every machine near enough (a client hears it
## from `NetSession`, with no `source`), for the view.
signal grid_called(bot: Actor, source: Actor)
## The war's artillery (`shelling`): shells will land at `points`, each
## `lands_in` seconds from now, and are marked until then. Every client is
## sent it (`NetSession._shells`); `ShellView` shows it where `Look` is on.
signal shells_called(points: PackedVector3Array, lands_in: PackedFloat32Array)
## A shell landed at `at` (authority; clients time it from `shells_called`).
signal shell_landed(at: Vector3)
## An army set off for a strongpoint (`Raid.pushes`, DESIGN.md "Challenge
## and balance data": danger warns first). `loud` is a new push worth a
## horn and a war feed line; a quiet one only moves the watch map's arrow.
signal army_pushed(site: int, from: Vector3, title: String, loud: bool)
## A lift (the map's "lift_stop" and "lift_power" markers) was powered, with
## `seconds_left` to run, or ran down (0). Authority only; a client is told
## by `NetSession` and keeps `lifts` for the view.
signal lift_changed(id: String, seconds_left: float)
## A keeper (a boss whose "spawn_boss" marker has the meta "keeper", a
## dungeon's last fight) changed phase: 1 standing, 2 below its split, 0
## fallen. Authority only; a client is told by `NetSession` (`set_keeper`).
signal keeper_changed(kind: String, phase: int)
## A keeper's purge lane (the map's "purge" markers, by their place in
## `purges`) warns (1), vents (2) or goes quiet (0). Every machine emits it
## (a client from `NetSession`), for the view.
signal purge_changed(index: int, state: int)
## A death burst (`WorldDef.death_burst`, the Marsh's bloaters) left a cloud
## at `at`, `radius` metres round, hanging `seconds`. The authority alone
## hurts anyone in it (`_tick_clouds`); views show it from this.
signal cloud_burst(at: Vector3, radius: float, seconds: float, kind: String)

## Bots never start closer to the player than this, so a raid does not open with a fight.
const MIN_BOT_SPAWN_DISTANCE := 40.0
## A vehicle this close to its parking spot counts as still parked there.
const PARKED_DISTANCE := 6.0
## A spawn point this close to open ground, above or below, is stood on it.
const SPAWN_SNAP := 2.5
## How many times a bot the world turns away is rolled again before the last
## roll is kept anyway.
const BOT_REROLLS := 8
## How many of the most wanted a world tells the plaza about (`wanted`).
const WANTED_SHOWN := 5
## The War Room's big moments (`moments`, `note_moment`): how many a world
## keeps to tell the plaza, newest first, and how long one stays news.
const MOMENTS_KEPT := 4
const MOMENT_LIFETIME := 600.0
## The War Room's hunted list: at most this many, and a grudge only counts
## once it is this share of the way to sending hunters (`hunted`).
const HUNTED_SHOWN := 4
const HUNTED_SHARE := 0.5
## Seconds between rounds of orders to the bot factions.
const ORDERS_EVERY := 8.0
## An army's push is announced (horn, war feed) at most this often, and
## shown on the watch map for `PUSH_SHOWN` seconds. Fewer bots than
## `PUSH_MIN` going for a site is not a push.
const PUSH_EVERY := 30.0
const PUSH_SHOWN := 60.0
const PUSH_MIN := 3
const DETAIL_EVERY := 0.25
## The drop id (`add_player`'s `p_drop`) for arriving through a squad portal:
## at the world's gate outpost (a map marker in the group "outpost", the
## same one for a whole side, so a squad lands together), else a quiet drop.
const PORTAL_DROP := "portal"
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MasteryTracker := preload("res://core/progression/mastery_tracker.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const Economy := preload("res://core/economy/economy.gd")
const SafetyNets := preload("res://core/economy/safety_nets.gd")
const StashRules := preload("res://core/account/stash_rules.gd")
const WarDirector := preload("res://core/war/war_director.gd")
const Strongpoint := preload("res://core/war/strongpoint.gd")
const PowerArmory := preload("res://core/war/power_armory.gd")
const Human := preload("res://core/visual/human.gd")

## How this raid runs.
##   SOLO   - one local player, everything simulated here.
##   SERVER - the authority for an online raid. Players join and leave.
##   CLIENT - a view of a server's raid. Nothing here decides an outcome.
enum Mode { SOLO, SERVER, CLIENT }

var mode := Mode.SOLO
var world: WorldDef
var map: Node3D
## The local player: the only one in a solo raid, your own actor on a client,
## and null on a server.
var player: Actor
## Everyone playing, by actor. See `PlayerState`.
var players: Array[PlayerState] = []
var bots: Array[Actor] = []
var depots: Array[Depot] = []
## The scrip piles lying in the world (`WorldDef.death_drops_scrip`), on
## every machine: a client's come from `NetSession`.
var piles: Array[LootContainer] = []
## What a scrip pile's bonus item is usually picked from (`pile_bonus`).
const PILE_SMALL_TAGS := ["consumable", "material", "augment", "attachment", "upgrade_data"]
var vehicles: Array[Node3D] = []
## Salvage crates in the world (`SalvageCrate`), wherever they are.
var crates: Array[SalvageCrate] = []
## Authority: the map's "spawn_crate" markers, each {marker, crate, empty_for},
## and how long each crate set down away from a marker has lain there.
var _crate_spots: Array = []
var _crate_idle := {}
## Salvage fields a storm buries and uncovers (the map's "salvage_field"
## markers, `WorldDef.weather_buries`), the same list in the same order on
## every machine. Whether one is buried is its "buried" meta.
var fields: Array[Node3D] = []
# Toy vehicles. A vehicle a player owns rides on their watch as a toy
# (`PlayerState.stowed`); thrown, it flies in an arc and unpacks where it lands.
## How hard a toy is thrown, in m/s, and how much the throw is tipped upwards.
var toy_speed := 12.0
var toy_lift := 0.3
var toy_gravity := 20.0
## A toy that has not come to rest after this long goes back on the watch.
var toy_max_flight := 5.0
## How much speed a toy keeps when it bounces off a wall.
var toy_bounce := 0.35
## Seconds from the throw to the toy leaving the hand: the arm draws back and
## comes through first (`ActionPose.toy_release` shows the same wait).
var toy_windup := 0.3
## Seconds between one throw and the next, for a vehicle with no
## `watch_recharge` stat of its own (heavier vehicles take longer).
var toy_cooldown := 12.0
## How many vehicles a watch holds.
var watch_capacity := 2
## A squad ping from the watch: how far it reaches, how long its marker
## stands, and the wait before the next.
var ping_range := 300.0
var ping_time := 8.0
var ping_cooldown := 2.0
## How close to their last drop a player must stand for the next one to go
## in the same bag (`drop_item`), in metres.
var drop_bag_reach := 2.5
## Squad portals open here (`open_portal`), and how long a player waits
## between opening two.
var portals: Array[Portal] = []
var portal_cooldown := 5.0
## Owner key -> squad key (`set_squad`).
var squads := {}
## The clear box a vehicle needs to unpack: width, height, length. A vehicle
## with a `footprint` stat needs that instead.
var unpack_room := Vector3(1.3, 1.2, 2.6)
## Toys in the air: { state, id, at, velocity, age, heading, node }. A
## throw still winding up is here too, with `windup` above zero and no node
## yet (the authority's only).
var toys: Array[Dictionary] = []
## Seconds this world has been running.
var clock := 0.0
## The local player's kills across every life of this stay.
var kills := 0
var rng := RandomNumberGenerator.new()
## The seed each bot was equipped with, so a client can rebuild the same bot.
var bot_seeds := {}
## The local player's mastery tracker.
var mastery: MasteryTracker
## Every player's renown in this world. It outlives their lives here.
var renown := RenownLedger.new()
var _marked_owner := ""
## How hot the war is here, and where. On a client the values come from the
## server. The map hears them through its "war_intensity" and "war_centre"
## metas, which is all `Look` needs to shift the sky.
var war := WarDirector.new()
## Where lives end, one line a finished life (`LifeLog`, DESIGN.md
## "Challenge and balance data"). Authority only.
var life_log := LifeLog.new()
## The sites worth holding, one per "strongpoint" marker on the map.
var strongpoints: Array[Strongpoint] = []
## A strongpoint at least this deep in a storm is cover for a push: an
## army's commander weighs it up (`WarCommander.storm_weight`).
const STORM_COVER := 0.5
## Where power weapons turn up (racks at strongpoints, pods, caches). Runs on
## the authority only.
var armory := PowerArmory.new()
## The war's artillery (DESIGN.md "Shelling"), where `WorldDef.shelling` is
## on. Authority only.
var shelling := Shelling.new()
## Smoke that hides people from bots as it hides them from eyes (`Smoke`):
## authority only, aged every tick, added where a cloud rises (a shell).
var smoke := Smoke.new()
## Each army's grudge against each player for this life
## ({player actor: {faction: points}}, `WorldDef.grudge_factions`).
## Authority only; the player hears only who is hunting them
## (`Actor.hunted_by`).
var grudges := {}
var _grudge_in := 0.0
## Seconds between an army's hunters being sent after the player it holds
## a grudge against, how many go each time, and from how far.
const GRUDGE_EVERY := 12.0
const GRUDGE_HUNTERS := 2
const GRUDGE_REACH := 120.0
## The weather (DESIGN.md "Weather: ash storms"): at most one storm crossing
## the map, on `WorldDef.weather_kind`. Only the authority runs it; a client's
## copy comes from `NetSession` and is only carried on between updates.
var weather := Weather.new()
var _assault_in := 0.0
## War intensity from which a player may choose to land beside the fighting.
var hot_drop_from := 0.2
## The world event going on, or {}: { kind ("supply_pod", "warlord",
## "convoy" or "airship"),
## title, at, ends (on `clock`) }. One at a time.
var event := {}
## Players who stand together: owner key -> [side key, side name]. See `set_team`.
var teams := {}
## The warlords alive in the world, so clients can build the same bot.
var warlords := {}
## The big moments of this world for the plaza's War Room, newest first:
## [{"kind", "text", "at" (unix seconds)}]. Authority only (`note_moment`).
var moments: Array[Dictionary] = []
var _event_in := 0.0
var _event_bots: Array[Actor] = []
## Rival raiders in the world (`WorldDef.raider_count`, authority only), one
## entry each: {"bot": Actor, "leaves_at": clock time it heads out,
## "sign_out_left": seconds, below 0 when not signing out, "cache": the
## LootContainer it is going for or null, "visited": caches it has emptied}.
var raiders: Array[Dictionary] = []
## How close (metres) a raider must be to a cache to loot it.
var raider_loot_reach := 2.5
## A raider only goes for caches it can walk to: no higher than this over
## the ground (rooftops are for players, for now).
var raider_climb := 2.0
var _raider_in := 0.0
var _event_pod: LootContainer
## The convoy on the road (`WorldDef.convoy_vehicles`), authority only:
## {"vehicles": [the hauler first], "drivers": [one each], "route": points,
## "next": [the point each heads for], "stopped": the hauler has stopped}.
var convoy := {}
## How close (flat metres) a convoy vehicle comes to a route point before
## heading for the next, and how near it lets the one ahead get.
const CONVOY_REACH := 10.0
const CONVOY_GAP := 16.0
## The airship aloft (`WorldDef.airship_vehicle`), authority only:
## {"ship", "route": points, "next": the point it heads for, "way": +1 or
## -1 along the route, "passes": crossings left, "down": all its weak spots
## broken and falling, "falling": seconds since, "over": crashed or gone}.
var airship := {}
## How close (flat metres) the airship comes to a route point before
## heading for the next, and the longest it falls before it counts as down.
const AIRSHIP_REACH := 14.0
const AIRSHIP_FALL_MAX := 30.0
## Risk zones (DESIGN.md section 2): the map's gate outposts (Marker3D, metas
## "name" and "radius") and its core bosses, { marker, bot, back_in }.
var outposts: Array[Node3D] = []
## Warm beacons (DESIGN.md "Frostline"): where a world with
## `WorldDef.sign_out_at_beacons` lets players sign out (Marker3D, metas
## "name" and "radius").
var beacons: Array[Node3D] = []
## Whether gate outposts shelter anyone and hazards burn. Only the test suite
## turns it off, for the checks written before risk zones that need a player
## ready to fight where they spawn and unhurt by the ground.
static var zone_rules := true
## Whether worlds have enemies: armies, bosses, guards and their broods,
## rival raiders and the events that bring bots (a warlord, a convoy, an
## airship). Off, a world keeps its caches, vehicles, weather and supply
## pods, and every enemy system stays in place to switch back on. `Main`
## sets it from the project setting `ares/stability/enemies` (off during
## the stability pass), the command line (`--enemies`, `--no-enemies`,
## `--bots N`) or the environment (`ARES_ENEMIES`); see `enemies_wanted`. Code that
## builds its own `Raid` (the tests, the benches) keeps them on.
static var enemies := true
## The enemy budget (Caleb: enemies must never overwhelm the frame rate or
## the player). `enemy_cap` is the most enemies one world holds at once,
## everything counted (army, bosses, guards, raiders, an event's); 0 is no
## cap. `near_full_cap` is how many of the bots near a player think and
## move every tick (`_tick_detail`); the rest near them step every second
## tick; 0 is no cap. `Main` sets both from `ares/stability/enemy_cap` and
## `ares/stability/enemies_full_detail` (or `--enemy-cap`, `ARES_ENEMY_CAP`);
## code that builds its own `Raid` keeps them off.
static var enemy_cap := 0
static var near_full_cap := 0
var _bosses: Array[Dictionary] = []
## Guards at the map's "spawn_guard" markers (a dungeon's garrison), each
## { marker, bot, back_in, brood (what it has spilled), brood_in }, outside
## the armies like the bosses.
var _guards: Array[Dictionary] = []
## Encounter pockets (`WorldDef.pocket_wake`) by key (a marker's "pocket"
## meta, or the marker itself): { guards (indices into `_guards`), awake,
## idle (seconds nobody has been near while awake) }.
var _pockets := {}
var _pocket_in := 0.0
## Guards of pockets just woken, waiting their turn to stand: one a tick
## (`_tick_pocket_guards`), since a body's first frame dressed is dear on
## the machines that draw it (three at once were a 50 ms hitch). Their room
## is kept for them (`_pocket_room`).
var _pocket_queue: Array[Dictionary] = []
## How often pockets are woken and put to sleep (seconds).
const POCKET_EVERY := 0.5
## Past its wake range by this much, for `POCKET_SLEEP_AFTER` seconds with
## none of its guards fighting, a pocket sleeps.
const POCKET_SLEEP_MARGIN := 40.0
const POCKET_SLEEP_AFTER := 15.0
## A fallen guard of an awake pocket comes back only with no player this
## near its marker (out of sight).
const POCKET_REFILL_CLEAR := 60.0
## Short of room, an awake pocket sleeps for a waking one only when every
## player is at least this much further from it (metres).
const POCKET_YIELD := 30.0
## The map's lifts by id: { stops (its two "lift_stop" markers), power (its
## "lift_power" marker or null), left (seconds it runs on for), charge (how
## long someone has stood at its switch), wait and arrived (by rider's
## instance id: seconds waited in a stop, the stop just arrived at) }.
var lifts := {}
## Keepers by kind: their phase (1 standing, 2 below their split, 0 fallen),
## kept on every machine (a client's from `NetSession`) and handed to the map
## as the meta "keepers" for the view. While a keeper stands, the markers
## that wait on it ("beacon", "warmth" with its kind as meta "keeper") are
## dark.
var keepers := {}
## The map's "purge" markers, in tree order (the same on every machine), and
## its "boss_socket" and "vault" markers.
var purges: Array[Node3D] = []
var _sockets: Array[Node3D] = []
var _vaults: Array[Node3D] = []
## The map's "boss_snag" markers: what a charging keeper can ram.
var _snags: Array[Node3D] = []
## The map's "boss_pool" markers: where a keeper that dives comes up.
var _pools: Array[Node3D] = []
## How long a purge lane vents after its warning.
const PURGE_VENT := 0.8
## Bosses' toughness is counted this often (`_scale_boss`).
const BOSS_PARTY_EVERY := 1.0
var _boss_party_left := 0.0
## Linked factions: a hurt bot calls the rest at most this often, and when
## each may call again.
const LINK_EVERY := 1.5
var _link_next := {}
var _hazard_in := 0.0
## The lava's clock (`WorldDef.molten_level`): it burns this often.
const MOLTEN_EVERY := 0.25
var _molten_in := 0.0
## Death bursts' clouds (`WorldDef.death_burst`), authority only: each
## { at, radius, damage, left, kind, faction }, hurting once a second.
var clouds: Array[Dictionary] = []
var _cloud_in := 1.0
## Bots that leave hurting ground where they walk (their "trail" meta, a
## cloud as `burst_cloud` takes it, and "every", the seconds between two):
## bot -> { at (where it last left one), wait }. Authority only.
var _trails := {}
var _trail_in := 0.0
const TRAIL_STEP := 0.5
## The map's warmth (heaters, vents; Marker3D in group "warmth") and the
## clock for the cold's once-a-second hurt.
var warmth: Array[Node3D] = []
## The map's rooms (Marker3D in group "indoors", see `WorldDef`'s "The
## cold"): out of the open cold, heated or not. Every machine has them, so a
## client's view can tell where its player stands (`indoors_at`).
var rooms: Array[Node3D] = []
var _cold_in := 1.0
## Footprints and wheel tracks in a world with `WorldDef.tracks`: laid down
## by the authority, copied to clients near them (`NetSession._send_tracks`).
var tracks := Tracks.new()
## Metres walked between two footprints, and driven between two wheel marks.
const FOOT_STEP := 0.8
const TREAD_STEP := 1.4
## How often the authority looks for new marks, and how far off the ground a
## body may be and still print it (a roof or a hut floor leaves none).
const TRACK_EVERY := 0.1
const TRACK_GROUND := 0.5
var _track_in := 0.0
var _expire_in := 1.0
## Where each body or vehicle last left a mark, and which foot it was.
var _last_mark := {}
## Holes broken through thin ice (`WorldDef.thin_ice`), each [where (on the
## ground), when it opened (`clock`)]. The authority keeps them and clients
## are sent them. Anyone standing in one is in the water: their body heat
## is gone. Anything driven into one sinks.
var ice_holes: Array = []
const ICE_HOLE_RADIUS := 3.5
## Shares of `WorldDef.ice_break_strain` at which the ice cracks out loud
## before it gives way, and how fast strain eases once off the thin ice.
const ICE_WARNINGS := [0.4, 0.7]
const ICE_EASE := 2.0
## How hard each heavy vehicle has been on the thin ice (authority only).
var _ice_strain := {}
## When false, the raid reports results but leaves the stash alone, so a server
## never writes to a profile that is not the player's.
var apply_to_profile := true
## Server: every player starts at the same spawn point, as one squad.
var squad_spawn := false
## Bots within this many metres of a player are simulated every tick, bots
## within `half_detail_range` every second tick, and the rest every
## `far_detail_step` ticks. Past 100 m a bot is out of sight in most of
## Ashfront, and its few-tick steps cost the least feel (Caleb's call, to
## keep a big battle's tick inside its budget).
var full_detail_range := 70.0
var half_detail_range := 100.0
var far_detail_step := 6
var _squad_marker := -1
var _player_count := 0
var _bot_count := 0
## One per cache: { container, source, refill_in }.
var _caches: Array[Dictionary] = []
## Seconds until each dead bot is replaced.
var _bot_respawns: Array[float] = []
var _reinforce_in := 0.0
var _orders_in := 0.0
## Each army's commander (`_tick_orders`).
var commander := WarCommander.new()
var _detail_in := 0.0
## Bot -> the strongpoint its faction last sent it to.
var _orders := {}
## Bot -> where it was last posted, for orders that send it short of the
## site (a siege ring) or to a line post.
var _posted := {}
## Battles by ground (the enemy AI pass, step 4): the "line_post" markers,
## bot -> the post it holds, and "faction:site index" -> when that army
## began ringing that site (`_tick_orders`).
var line_posts: Array[Node3D] = []
var _line_of := {}
var _sieges := {}
## The armies' pushes, newest last, as {"site", "from", "title", "at"}
## (`at` is `clock`): what the watch map draws as an arrow. The server
## decides them in `_tick_orders`; a client is told (`note_push`).
var pushes: Array[Dictionary] = []
## Each faction's last push target and when it was last announced.
var _push_target := {}
var _push_loud_at := {}
## Bot -> `clock` until which something else (an assault) has the say over it.
var _busy_until := {}
## One per vehicle marker: { marker, source, vehicle, empty_for }.
var _parking: Array[Dictionary] = []
## Vehicle -> seconds since anyone rode it.
var _idle := {}
## Lag compensation for this raid, set by the `NetSession` running it: called
## with an attacker, returns {Actor: Vector3} of where they saw everyone.
## Per raid, because one server process can run several (a world and the arena).
var rewind := Callable()
## DEV MODE: cheats for this raid's players, from `DevMode.raid_cheats()`
## ("god", "heat", "ammo", "cooldowns" -> true). Only a solo raid applies
## them (`_apply_dev_cheats`); a server or client raid ignores them.
var dev_cheats := {}


## The raid a node belongs to, or null. Rules and scans use this so two raids
## in one process (a plaza and a warzone on one server) never mix.
static func of(node: Node) -> Raid:
	while node != null:
		if node is Raid:
			return node
		node = node.get_parent()
	return null


## True when both nodes are in the same raid (or neither is in one).
static func together(a: Node, b: Node) -> bool:
	return of(a) == of(b)


## Call after the Raid is in the scene tree. A fixed seed makes it repeatable.
## `p_kit` is the gear the player deploys with; empty means the free scrap kit.
## `p_mastery` maps mastery track -> picked variant id (see MasteryBook.active_picks).
## `p_owner` and `p_renown` are the player's renown key and lifetime renown (see `add_player`).
func start(p_world: WorldDef, p_seed: int = -1, p_kit: Array = [], p_mastery: Dictionary = {},
		p_owner := "", p_renown := 0, p_drop := "", p_insured := "") -> void:
	mode = Mode.SOLO
	_setup(p_world, p_seed)
	_spawn_caches()
	armory.setup(self)
	add_player(p_kit, p_mastery, "You", p_owner, p_renown, p_drop, p_insured)
	_spawn_bots()
	_spawn_bosses()
	_spawn_guards()
	_spawn_map_vehicles()
	_bury_at_start()
	_spawn_crates()


## Starts the raid as the authority for an online game. Players are added with
## `add_player` as they connect.
func start_server(p_world: WorldDef, p_seed: int = -1) -> void:
	mode = Mode.SERVER
	apply_to_profile = false
	_setup(p_world, p_seed)
	_spawn_caches()
	armory.setup(self)
	_spawn_bots()
	_spawn_bosses()
	_spawn_guards()
	_spawn_map_vehicles()
	_bury_at_start()
	_spawn_crates()


## Starts the raid as a view of a server's raid: the map only. Actors are added
## by the network session as the server reports them.
func start_client(p_world: WorldDef) -> void:
	mode = Mode.CLIENT
	apply_to_profile = false
	_setup(p_world, 0)


func _setup(p_world: WorldDef, p_seed: int) -> void:
	world = p_world
	Worlds.current = world
	# The world's music, or the music fading out for the war (view only).
	Sfx.music(world.music)
	if p_seed >= 0:
		rng.seed = p_seed
	else:
		rng.randomize()

	# A safe zone is never at war.
	war.scale = 0.0 if world.safe_zone else world.war_scale
	map = world.create_map()
	map.name = "Map"
	map.set_meta("war_intensity", 0.0)
	map.set_meta("war_centre", Vector3.ZERO)
	add_child(map)
	if mode != Mode.CLIENT and map.has_method("bake_navigation"):
		map.call("bake_navigation")

	fields = _map_nodes("salvage_field")
	for field in fields:
		field.set_meta("buried", false)
		field.set_meta("ground_y", field.position.y)
	for node in _map_nodes("depot"):
		var depot := node as Depot
		if depot:
			depot.hold_time = world.depot_hold_time
			depot.can_bank = _can_bank
			if mode != Mode.CLIENT:
				depot.actor_banked.connect(_on_actor_banked)
			depots.append(depot)
	for marker in _map_nodes("strongpoint"):
		var point := Strongpoint.new()
		point.index = strongpoints.size()
		point.name = "Strongpoint%d" % point.index
		point.title = marker.get_meta("name", "Strongpoint %d" % (point.index + 1))
		point.radius = float(marker.get_meta("radius", point.radius))
		point.hot_at = float(marker.get_meta("hot_at", 0.0))
		marker.add_child(point)
		var faction: String = marker.get_meta("holder", "")
		if faction != "":
			point.hold("faction:" + faction, marker.get_meta("holder_name", faction.capitalize()), false)
		strongpoints.append(point)
	_find_lifts()
	outposts = _map_nodes("outpost")
	line_posts = _map_nodes("line_post")
	beacons = _map_nodes("beacon")
	warmth = _map_nodes("warmth")
	rooms = _map_nodes("indoors")
	_find_keepers()
	tracks.clear()
	tracks.lifetime = world.track_lifetime
	if world.tracks and Look.enabled:
		var view := TrackView.new()
		view.raid = self
		add_child(view)
	shelling.reset(int(rng.seed) + 4231)
	if world.shelling > 0.0 and not world.safe_zone and Look.enabled:
		var shells := ShellView.new()
		shells.raid = self
		add_child(shells)
	ice_holes.clear()
	_ice_strain.clear()
	if world.thin_ice and Look.enabled:
		var ice := IceView.new()
		ice.raid = self
		add_child(ice)
	weather = Weather.new()
	weather.setup(world, int(rng.seed) + 7919)
	if world.weather_kind != "" and not world.safe_zone and Look.enabled:
		var sky := WeatherView.new()
		sky.raid = self
		add_child(sky)
	_link_next.clear()
	if not world.linked_factions.is_empty() and Look.enabled and not grid_called.is_connected(_show_grid_call):
		grid_called.connect(_show_grid_call)
	if Look.enabled and not army_pushed.is_connected(_show_push):
		army_pushed.connect(_show_push)
	clouds.clear()
	if Look.enabled and not cloud_burst.is_connected(_show_cloud):
		cloud_burst.connect(_show_cloud)
	_assault_in = world.assault_interval
	_event_in = world.event_interval
	_raider_in = world.raider_gap


func _spawn_caches() -> void:
	for marker in _map_nodes("spawn_cache"):
		var source: String = marker.get_meta("loot_source", "cache")
		var cache := spawn_container(world.roll_loot(source, rng), false, "cache", marker.global_position)
		var entry := {"container": cache, "source": source, "refill_in": -1.0, "looted": {},
				"hive": str(marker.get_meta("hive", ""))}
		_caches.append(entry)
		cache.looted_by.connect(_on_cache_looted.bind(entry))


func _physics_process(delta: float) -> void:
	if world == null:
		return
	clock += delta
	_tick_sign_outs(delta)
	_tick_toys(delta)
	_tick_portals(delta)
	if mode != Mode.CLIENT:
		_tick_war(delta)
		weather.tick(delta)
	else:
		weather.advance(delta)
	map.set_meta("war_intensity", war.intensity)
	map.set_meta("war_centre", war.centre)
	if world.tracks:
		_tick_tracks(delta)
	if not lifts.is_empty():
		_tick_lifts(delta)
	if mode == Mode.CLIENT:
		return
	# DEV MODE
	if mode == Mode.SOLO and not dev_cheats.is_empty():
		_apply_dev_cheats()
	if world.safe_zone:
		_keep_everyone_safe()
		return
	_tick_outposts()
	_tick_piles()
	_tick_hazards(delta)
	if world.molten_level > -INF:
		_tick_molten(delta)
	if not _trails.is_empty():
		_tick_trails(delta)
	if not clouds.is_empty():
		_tick_clouds(delta)
	if world.shelling > 0.0 and zone_rules:
		shelling.tick(self, delta)
	smoke.tick(delta)
	_tick_cold(delta)
	if not world.grudge_factions.is_empty() and zone_rules:
		_tick_grudges(delta)
	if world.thin_ice:
		_tick_ice(delta)
	_tick_bosses(delta)
	_tick_guards(delta)
	_tick_strongpoints(delta)
	_tick_events(delta)
	_tick_caches(delta)
	armory.tick(delta)
	_tick_bots(delta)
	_tick_raiders(delta)
	_tick_detail(delta)
	_tick_vehicles(delta)
	if world.weather_buries and not fields.is_empty():
		_tick_fields()
	if not _crate_spots.is_empty() or not crates.is_empty():
		_tick_crates(delta)


## DEV MODE: changes the cheats mid-run. Turning god mode off takes effect
## at once even with no cheats left to run.
func set_dev_cheats(cheats: Dictionary) -> void:
	dev_cheats = cheats.duplicate() if mode == Mode.SOLO else {}
	for state in players:
		if is_instance_valid(state.actor):
			state.actor.dev_invulnerable = dev_cheats.get("god", false)


## DEV MODE: keeps each player's cheats running. Solo only (see `dev_cheats`).
func _apply_dev_cheats() -> void:
	for state in players:
		var actor := state.actor
		if not is_instance_valid(actor) or actor.is_dead:
			continue
		actor.dev_invulnerable = dev_cheats.get("god", false)
		if actor.dev_invulnerable:
			actor.health.health = actor.health.max_health
			actor.health.armor = actor.health.max_armor
		if dev_cheats.get("heat", false):
			actor.flight.heat = 0.0
			actor.flight.overheated = false
		if dev_cheats.get("ammo", false):
			for weapon in actor.weapons:
				var gun := weapon as Gun
				if gun != null:
					gun.ammo_in_mag = gun.mag_size
		if dev_cheats.get("cooldowns", false):
			actor.ability.cooldown_left = 0.0


## Safe zones have no deaths. Anyone who gets hurt anyway (a fall off the
## map) is put back at a spawn point, whole.
func _keep_everyone_safe() -> void:
	for state in players:
		var actor := state.actor
		if not is_instance_valid(actor) or actor.is_dead:
			continue
		if actor.global_position.y < -15.0:
			var spawns := _map_nodes("spawn_player")
			actor.velocity = Vector3.ZERO
			actor.global_position = spawns[rng.randi() % spawns.size()].global_position if not spawns.is_empty() \
					else Vector3(0, 2, 0)
		actor.health.health = actor.health.max_health


## An emptied cache fills up again after a while.
## Feeds the war director: hostile players close to each other heat the
## world up, and a hotter world pays more renown.
func _tick_war(delta: float) -> void:
	var living: Array[Actor] = active_players()
	var clashes: Array[Vector3] = []
	var probe := DamageInfo.new()
	for i in living.size():
		for j in range(i + 1, living.size()):
			var a := living[i]
			var b := living[j]
			if a.global_position.distance_to(b.global_position) <= war.clash_distance \
					and world.can_damage(a, b, probe):
				clashes.append((a.global_position + b.global_position) * 0.5)
	war.tick(delta, clashes)
	renown.pay_scale = war.renown_bonus()


## The side an actor fights for, as [key, name to show, is a player side].
## Bots are a side per faction. Players are each their own side unless the
## world makes them allies.
func side_of(actor: Actor) -> Array:
	var state := state_for(actor)
	if state == null:
		return ["faction:" + actor.faction, "the %ss" % actor.display_name, false]
	if world.players_allied:
		return ["players", "the raiders", true]
	if teams.has(state.owner):
		return [teams[state.owner][0], teams[state.owner][1], true]
	return [state.owner, actor.display_name, true]


## The side key of the player with this owner key.
func _player_side(key: String) -> String:
	if world.players_allied:
		return "players"
	return teams[key][0] if teams.has(key) else key


## Puts the player with this owner key on a team (a clan): everyone given the
## same `team` is one side for strongpoints and drops, named `title`. An
## empty `team` puts them back on their own. Whoever owns the accounts calls
## this before `add_player`; the `Raid` never asks who is in which clan.
func set_team(owner: String, team: String, title := "") -> void:
	if owner == "":
		return
	if team == "":
		teams.erase(owner)
	else:
		teams[owner] = ["team:" + team, title if title != "" else team]


## Whether `actor`'s side holds `point`. On a client this is the server's word
## about the local player.
func holds(actor: Actor, point: Strongpoint) -> bool:
	if mode == Mode.CLIENT:
		return point.viewer_holds
	return actor != null and is_instance_valid(actor) and point.holder != "" \
			and point.holder == side_of(actor)[0]


## The strongpoint an actor is standing in, or null.
func strongpoint_at(actor: Actor) -> Strongpoint:
	for point in strongpoints:
		if point.covers(actor.global_position):
			return point
	return null


## Runs the strongpoints: who is inside each, who takes it, what that pays.
func _tick_strongpoints(delta: float) -> void:
	if strongpoints.is_empty():
		return
	var living: Array[Actor] = []
	for bot in bots:
		if is_instance_valid(bot) and not bot.is_dead:
			living.append(bot)
	living.append_array(active_players().filter(func(a: Actor) -> bool:
		return is_instance_valid(a) and not a.is_dead))
	for point in strongpoints:
		var present := {}
		var inside: Array[Actor] = []
		for actor in living:
			if not point.covers(actor.global_position):
				continue
			inside.append(actor)
			var side := side_of(actor)
			if not present.has(side[0]):
				present[side[0]] = {"count": 0, "name": side[1], "player": side[2]}
			present[side[0]].count += 1
		var was_contested := point.contested
		var loser := point.holder_name
		var lost_by_player := point.holder_is_player
		_count_holding(point, inside, delta)
		if point.tick(delta, present):
			_on_strongpoint_taken(point, inside, loser, lost_by_player)
		elif point.contested != was_contested:
			point.refresh_look()
		# Players fighting over a site are part of the war.
		if point.contested and present.values().any(func(who: Dictionary) -> bool: return who.player):
			war.report_clash(point.global_position, delta)
	_tick_assaults(delta)


## Players standing in a site their side holds are holding the line: whole
## seconds of it count toward "hold_seconds" (Ashfront's hold contracts).
func _count_holding(point: Strongpoint, inside: Array[Actor], delta: float) -> void:
	if point.holder == "":
		return
	for actor in inside:
		var state := state_for(actor)
		if state == null or side_of(actor)[0] != point.holder:
			continue
		state.held_for += delta
		var whole := int(state.held_for)
		if whole > 0:
			state.held_for -= whole
			_count(state, "hold_seconds", whole)


func _on_strongpoint_taken(point: Strongpoint, inside: Array[Actor], loser: String, lost_by_player: bool) -> void:
	# Bots trading a site among themselves is not news.
	if point.holder_is_player or lost_by_player:
		var line := "%s took %s" % [point.holder_name, point.title]
		if loser != "":
			line += " from %s" % loser
		war_feed.emit(line.left(1).to_upper() + line.substr(1))
		war.report_capture(point.global_position)
	if point.holder != "":
		note_moment("front", "%s took %s" % [point.holder_name.left(1).to_upper() + point.holder_name.substr(1),
				point.title])
	if point.holder_is_player:
		for actor in inside:
			var state := state_for(actor)
			if state == null:
				continue
			var paid := renown.award(state.owner, renown.strongpoint_taken)
			_pay_scrip(state, Economy.STRONGPOINT_SCRIP)
			_count(state, "strongpoints")
			actor.notice.emit("Took %s   +%d renown" % [point.title, paid])
		_publish_standing()
	strongpoint_taken.emit(point)


## Every so often the bots push on a site that players hold: the nearest few
## are sent to retake it.
func _tick_assaults(delta: float) -> void:
	if world.assault_size <= 0:
		return
	_assault_in -= delta
	if _assault_in > 0.0:
		return
	_assault_in = world.assault_interval
	var targets := strongpoints.filter(func(p: Strongpoint) -> bool: return p.holder_is_player)
	if targets.is_empty():
		return
	var point: Strongpoint = targets[rng.randi() % targets.size()]
	var nearest: Array[Actor] = []
	for bot in bots:
		if is_instance_valid(bot) and not bot.is_dead and bot.has_node("Brain") and not is_raider(bot):
			nearest.append(bot)
	nearest.sort_custom(func(a: Actor, b: Actor) -> bool:
		return a.global_position.distance_squared_to(point.global_position) \
				< b.global_position.distance_squared_to(point.global_position))
	for bot in nearest.slice(0, world.assault_size):
		(bot.get_node("Brain") as BotBrain).post_to(point.global_position, point.radius)
		# Theirs until the next assault: the army's own orders leave them be.
		_orders.erase(bot)
		_busy_until[bot] = clock + world.assault_interval
	war_feed.emit("%s is under attack" % point.title)


## Gives a new bot a site to stand on: one its faction holds, if it spawned
## close to it. Everyone else patrols where they spawned, as before.
func _post_bot(bot: Actor) -> void:
	var brain := bot.get_node_or_null("Brain") as BotBrain
	if brain == null:
		return
	for point in strongpoints:
		if point.holder == "faction:" + bot.faction \
				and bot.global_position.distance_to(point.global_position) <= point.radius * 3.0:
			brain.post_to(point.global_position, point.radius)
			return


## Where a player who holds a strongpoint drops in: at one of theirs that
## nobody is fighting over. Returns null when they hold none.
func _forward_drop(side: String) -> Strongpoint:
	var mine := strongpoints.filter(func(p: Strongpoint) -> bool:
		return p.holder == side and not p.contested and p.taker == "")
	return mine[rng.randi() % mine.size()] if not mine.is_empty() else null


## Where the player with this owner key may ask to land, as { id, title,
## note }. The id goes back into `add_player`. A client asks with no key: it
## knows which sites are its own from the server.
func drop_choices(owner := "") -> Array[Dictionary]:
	var side := _player_side(owner) if owner != "" else ""
	var out: Array[Dictionary] = [{"id": "safe", "title": "Quiet drop", "note": "away from the fighting"}]
	if war.intensity >= hot_drop_from:
		out.append({"id": "hot", "title": "Into the fight", "note": "beside the heaviest fighting"})
	for point in strongpoints:
		var mine := point.viewer_holds if mode == Mode.CLIENT else (side != "" and point.holder == side)
		if mine and not point.contested and point.taker == "":
			out.append({"id": "point:%d" % point.index, "title": point.title, "note": "a strongpoint you hold"})
	return out


## The spawn marker nearest a place.
func _nearest_spawn(spawns: Array[Node3D], to: Vector3) -> int:
	var best := 0
	for i in spawns.size():
		if spawns[i].global_position.distance_squared_to(to) < spawns[best].global_position.distance_squared_to(to):
			best = i
	return best


## World events: one at a time, more often the hotter the war.
func _tick_events(delta: float) -> void:
	if world.event_interval <= 0.0:
		return
	if not event.is_empty():
		if event.kind == "convoy":
			_drive_convoy()
		elif event.kind == "airship":
			_drive_airship(delta)
		if clock >= float(event.ends) or _event_over():
			end_event(clock >= float(event.ends))
		return
	_event_in -= delta * (1.0 + war.intensity)
	if _event_in <= 0.0:
		var bring := enemy_room() >= 1 + maxi(world.warlord_escort, 2)
		var kinds := ["warlord", "supply_pod"] if bring else ["supply_pod"]
		if bring and _convoy_routes().size() > 0:
			kinds.append("convoy")
		if bring and _airship_routes().size() > 0:
			kinds.append("airship")
		start_event(kinds[rng.randi() % kinds.size()])


## Starts a world event now. Returns false when one is running or the map
## has nowhere to put it.
func start_event(kind: String) -> bool:
	var spawns := _map_nodes("spawn_bot")
	if not event.is_empty() or spawns.is_empty():
		return false
	if kind in ["warlord", "convoy", "airship"] and enemy_room() < 1 + maxi(world.warlord_escort, 2):
		return false
	if kind == "convoy" and _convoy_routes().is_empty():
		return false
	if kind == "airship" and _airship_routes().is_empty():
		return false
	_event_in = world.event_interval
	var at: Vector3
	if kind == "convoy":
		at = _start_convoy()
		event = {"kind": kind, "title": "Convoy"}
		war_feed.emit("A convoy has set out %s" % _whereabouts(at))
	elif kind == "airship":
		at = _start_airship()
		event = {"kind": kind, "title": ItemDB.item_name(world.airship_vehicle)}
		war_feed.emit("%s is coming in %s" % [event.title, _whereabouts(at)])
	elif kind == "warlord":
		var marker := spawns[_farthest_from_players(spawns)]
		at = marker.global_position
		for i in 1 + maxi(world.warlord_escort, 0):
			var bot := _add_bot(marker, i == 0)
			_event_bots.append(bot)
		# They march on a site the players hold, if there is one.
		var targets := strongpoints.filter(func(p: Strongpoint) -> bool: return p.holder_is_player)
		if not targets.is_empty():
			var point: Strongpoint = targets[rng.randi() % targets.size()]
			for bot in _event_bots:
				(bot.get_node("Brain") as BotBrain).post_to(point.global_position, point.radius)
		event = {"kind": kind, "title": "Warlord"}
		war_feed.emit("A warlord has arrived %s" % _whereabouts(at))
	else:
		at = spawns[rng.randi() % spawns.size()].global_position
		# Always a good haul, and a better one in a hot war.
		var items := world.roll_war_loot("cache", rng, maxf(war.intensity, 0.5))
		items.append_array(world.roll_war_loot("cache", rng, 1.0))
		var relic := world.roll_artifact(rng, world.pod_artifact_chance)
		if relic != "":
			items.append(relic)
		items.append_array(world.roll_crafting_loot(rng, world.pod_blueprint_chance, world.pod_upgrade_data))
		_event_pod = spawn_container(items, false, "Supply pod", at)
		armory.on_supply_pod(at)
		event = {"kind": "supply_pod", "title": "Supply pod"}
		war_feed.emit("A supply pod came down %s" % _whereabouts(at))
	event["at"] = at
	event["ends"] = clock + world.event_lifetime
	event_changed.emit(event)
	return true


## Ends the running event and clears away what is left of it.
func end_event(timed_out := false) -> void:
	if event.is_empty():
		return
	if event.kind == "convoy":
		_end_convoy(timed_out)
	elif event.kind == "airship":
		_end_airship()
	elif timed_out:
		war_feed.emit("The warlord has moved on" if event.kind == "warlord" else "The supply pod is gone")
	for bot in _event_bots:
		if is_instance_valid(bot) and not bot.is_dead:
			_remove_actor(bot)
	_event_bots.clear()
	if is_instance_valid(_event_pod):
		_event_pod.queue_free()
	_event_pod = null
	event = {}
	event_changed.emit(event)


## Whether the event has been dealt with: the pod emptied, or the warlord dead.
func _event_over() -> bool:
	if event.kind == "convoy":
		return convoy.is_empty() or bool(convoy.stopped) or _convoy_through()
	if event.kind == "airship":
		return airship.is_empty() or bool(airship.over)
	if event.kind == "warlord":
		# The event's own warlord, not a core boss standing guard elsewhere.
		return not _event_bots.any(func(bot: Actor) -> bool:
			return is_instance_valid(bot) and warlords.has(bot))
	return not is_instance_valid(_event_pod) or _event_pod.items.is_empty()


# --- Convoys (DESIGN.md "The Dune Sea (part three)") ------------------------

func _convoy_routes() -> Array:
	if world.convoy_vehicles.is_empty() or map == null or not map.has_method("convoy_routes"):
		return []
	return map.call("convoy_routes")


## Authority: puts the convoy on the road at the start of one of the map's
## routes (either way along it), the hauler in front with its cargo full,
## each vehicle driven by a bot with riders aboard. Returns where it starts.
func _start_convoy() -> Vector3:
	var routes := _convoy_routes()
	var route: Array = (routes[rng.randi() % routes.size()] as Array).duplicate()
	if rng.randf() < 0.5:
		route.reverse()
	var start: Vector3 = route[0]
	var ahead: Vector3 = route[1] - start
	ahead.y = 0.0
	ahead = ahead.normalized()
	var heading := atan2(-ahead.x, -ahead.z)
	convoy = {"vehicles": [], "drivers": [], "route": route, "next": [], "stopped": false}
	for i in world.convoy_vehicles.size():
		var at := _stand(start - ahead * CONVOY_GAP * i)
		var vehicle := spawn_vehicle(world.convoy_vehicles[i], at + Vector3(0, 0.4, 0), heading)
		vehicle.set_meta("convoy", true)
		var driver := _add_bot(vehicle, false, world.convoy_faction)
		_event_bots.append(driver)
		# The road drives it, not its brain (`_drive_convoy`).
		driver.get_node("Brain").process_mode = Node.PROCESS_MODE_DISABLED
		vehicle.call("mount", driver)
		for seat in mini(world.convoy_riders, (vehicle.get("seats") as Array).size()):
			var rider := _add_bot(vehicle, false, world.convoy_faction)
			_event_bots.append(rider)
			vehicle.call("mount", rider, true, seat)
		if i == 0:
			var cargo: Array = vehicle.get("cargo")
			for slot in cargo.size():
				var crate := spawn_crate(world.roll_loot("crate", rng), at)
				cargo[slot] = crate
				crate.place(vehicle, slot)
		convoy.vehicles.append(vehicle)
		convoy.drivers.append(driver)
		convoy.next.append(1)
	return start


## Authority: each driver steers for its next route point at the world's
## pace, slowing for the one ahead. Once the hauler's driver is gone the
## hauler's cargo spills and the escort gets off to fight.
func _drive_convoy() -> void:
	if convoy.is_empty() or bool(convoy.stopped):
		return
	var route: Array = convoy.route
	var hauler: Node3D = convoy.vehicles[0]
	if not _convoy_driving(0):
		convoy.stopped = true
		if is_instance_valid(hauler):
			spill_cargo(hauler)
			war_feed.emit("The convoy has been stopped %s" % _whereabouts(hauler.global_position))
		for vehicle: Variant in convoy.vehicles:
			if is_instance_valid(vehicle):
				_unseat_bots(vehicle)
		return
	for i in convoy.vehicles.size():
		if not _convoy_driving(i):
			continue
		var vehicle: Node3D = convoy.vehicles[i]
		var driver: Actor = convoy.drivers[i]
		var next := int(convoy.next[i])
		var flat := Vector2(vehicle.global_position.x, vehicle.global_position.z)
		while next < route.size() and flat.distance_to(Vector2(route[next].x, route[next].z)) < CONVOY_REACH:
			next += 1
		convoy.next[i] = next
		var cmd := driver.cmd
		if next >= route.size():
			cmd.move = Vector2.ZERO
			continue
		var to: Vector3 = route[next] - vehicle.global_position
		var want := atan2(-to.x, -to.z)
		var off := wrapf(want - float(vehicle.get("heading")), -PI, PI)
		var throttle := world.convoy_throttle
		if i > 0 and is_instance_valid(convoy.vehicles[i - 1]):
			var gap: float = vehicle.global_position.distance_to((convoy.vehicles[i - 1] as Node3D).global_position)
			if gap < CONVOY_GAP * 0.6:
				throttle = 0.0
		elif i == 0 and convoy.vehicles.size() > 1 and _convoy_driving(1):
			# The hauler waits for its escort if it falls far behind.
			if vehicle.global_position.distance_to((convoy.vehicles[1] as Node3D).global_position) > CONVOY_GAP * 4.0:
				throttle *= 0.3
		# Slow into a sharp turn.
		throttle *= clampf(1.2 - absf(off), 0.35, 1.0)
		cmd.move = Vector2(clampf(-off * 2.0, -1.0, 1.0), throttle)
		cmd.sprint = false
		cmd.jump = false


func _convoy_driving(index: int) -> bool:
	if index >= convoy.vehicles.size():
		return false
	var vehicle: Variant = convoy.vehicles[index]
	var driver: Variant = convoy.drivers[index]
	return is_instance_valid(vehicle) and is_instance_valid(driver) and not (driver as Actor).is_dead \
			and vehicle.get("rider") == driver


## Whether the hauler has reached the end of its route.
func _convoy_through() -> bool:
	return _convoy_driving(0) and int(convoy.next[0]) >= (convoy.route as Array).size()


## Every bot aboard `vehicle` gets off and fights on foot, its brain back.
func _unseat_bots(vehicle: Node3D) -> void:
	var aboard: Array = (vehicle.get("passengers") as Array).duplicate()
	aboard.append(vehicle.get("rider"))
	for actor: Variant in aboard:
		if actor == null or not is_instance_valid(actor) or state_for(actor) != null:
			continue
		vehicle.call("get_off", actor)
		(actor as Actor).get_node("Brain").process_mode = Node.PROCESS_MODE_INHERIT


## Authority: the convoy is over. Stopped, its vehicles and bots stay where
## they are, ordinary now (the fight goes on, and anyone may drive off in
## them); through or timed out, it drives off the map, crates and all,
## save a vehicle a player has taken.
func _end_convoy(timed_out: bool) -> void:
	if convoy.is_empty():
		return
	if bool(convoy.stopped):
		_event_bots.clear()
	else:
		war_feed.emit("The convoy got through" if not timed_out else "The convoy has gone")
		for vehicle: Variant in convoy.vehicles:
			if not is_instance_valid(vehicle) or _has_player_aboard(vehicle):
				continue
			for crate: Variant in (vehicle.get("cargo") as Array):
				if crate != null and is_instance_valid(crate):
					(crate as SalvageCrate).queue_free()
			remove_vehicle(vehicle)
	for vehicle: Variant in convoy.vehicles:
		if is_instance_valid(vehicle):
			(vehicle as Node3D).remove_meta("convoy")
	convoy = {}


func _has_player_aboard(vehicle: Node3D) -> bool:
	var aboard: Array = (vehicle.get("passengers") as Array).duplicate()
	aboard.append(vehicle.get("rider"))
	return aboard.any(func(actor: Variant) -> bool:
		return actor != null and is_instance_valid(actor) and state_for(actor) != null)


# --- Airships (DESIGN.md "Basalt Rift", the Sky Leviathan) ------------------

func _airship_routes() -> Array:
	if world.airship_vehicle == "" or map == null or not map.has_method("airship_routes"):
		return []
	return map.call("airship_routes")


## Authority: the airship comes in at one end of one of the map's routes
## (either way along it), a bot of the world's on each of its weak spots.
## Returns where it starts.
func _start_airship() -> Vector3:
	var routes := _airship_routes()
	var route: Array = (routes[rng.randi() % routes.size()] as Array).duplicate()
	if rng.randf() < 0.5:
		route.reverse()
	var start: Vector3 = route[0]
	var ahead: Vector3 = route[1] - start
	var ship := spawn_vehicle(world.airship_vehicle, start, atan2(-ahead.x, -ahead.z))
	ship.set("course", route[1])
	var seats: Array = ship.get("seats")
	for i in seats.size():
		var part := str((seats[i] as Dictionary).get("part", ""))
		if part == "":
			continue
		var bot := _add_bot(ship, false, world.airship_faction, part)
		_event_bots.append(bot)
		# Only a gunner fights; the rest is the ship's own iron.
		if not (seats[i] as Dictionary).has("gun"):
			bot.get_node("Brain").process_mode = Node.PROCESS_MODE_DISABLED
		ship.call("mount", bot, true, i)
		bot.died.connect(_on_airship_part_died)
	airship = {"ship": ship, "route": route, "next": 1, "way": 1, "passes": maxi(world.airship_passes, 1),
			"down": false, "falling": 0.0, "over": false}
	return start


## Authority: steers the airship along its route, back and forth until its
## passes are spent, then off the end. With every weak spot broken it goes
## down (`Vehicle._float` with no course) and crashes on whatever is under
## it, or on the lava.
func _drive_airship(delta: float) -> void:
	if airship.is_empty() or bool(airship.over):
		return
	var ship: Variant = airship.ship
	if not is_instance_valid(ship):
		airship.over = true
		return
	if not bool(airship.down):
		if not _event_bots.any(func(bot: Variant) -> bool:
				return is_instance_valid(bot) and not (bot as Actor).is_dead):
			airship.down = true
			ship.set("course", Vector3.INF)
			war_feed.emit("%s is going down %s" % [ship.get("display_name"), _whereabouts(ship.global_position)])
			return
		var route: Array = airship.route
		var next := int(airship.next)
		var to: Vector3 = route[next]
		if Vector2(ship.global_position.x, ship.global_position.z).distance_to(Vector2(to.x, to.z)) < AIRSHIP_REACH:
			next += int(airship.way)
			if next < 0 or next >= route.size():
				airship.passes = int(airship.passes) - 1
				if int(airship.passes) <= 0:
					# Off the end of its last pass: it has drifted off.
					airship.over = true
					return
				airship.way = -int(airship.way)
				next = clampi(next + 2 * int(airship.way), 0, route.size() - 1)
			airship.next = next
			ship.set("course", route[next])
		return
	airship.falling = float(airship.falling) + delta
	var at: Vector3 = ship.global_position
	if ship.is_on_floor() or at.y <= world.molten_level or float(airship.falling) >= AIRSHIP_FALL_MAX:
		_crash_airship(ship)


## A weak spot broken: its salvage falls under the ship.
func _on_airship_part_died(actor: Actor, _info: DamageInfo) -> void:
	var items := world.roll_loot("airship_part", rng)
	if not items.is_empty():
		spawn_container(items, false, "%s salvage" % actor.display_name, drop_spot(actor))


## The airship comes down: its hold lands where it crashed (on top of the
## lava, never in it), the best haul of any event.
func _crash_airship(ship: Node3D) -> void:
	var at := drop_spot_at(ship.global_position + Vector3(0, 2.0, 0))
	var items := world.roll_loot("airship_hold", rng)
	items.append_array(world.roll_war_loot("cache", rng, maxf(war.intensity, 0.5)))
	items.append_array(world.roll_war_loot("cache", rng, 1.0))
	var relic := world.roll_artifact(rng, world.pod_artifact_chance)
	if relic != "":
		items.append(relic)
	items.append_array(world.roll_crafting_loot(rng, world.pod_blueprint_chance, world.pod_upgrade_data))
	var hold := spawn_container(items, false, "%s's hold" % ship.get("display_name"), at)
	get_tree().create_timer(world.bag_lifetime, false, true).timeout.connect(hold.queue_free)
	war_feed.emit("%s has crashed %s" % [ship.get("display_name"), _whereabouts(at)])
	note_moment("event", "%s came down %s" % [ship.get("display_name"), _whereabouts(at)])
	airship.over = true
	airship.crashed = true
	remove_vehicle(ship)


## Authority: the airship event is over. Still aloft, it drifts off with
## whoever is left on it.
func _end_airship() -> void:
	if airship.is_empty():
		return
	var ship: Variant = airship.ship
	if is_instance_valid(ship) and ship in vehicles:
		war_feed.emit("%s has drifted off" % ship.get("display_name"))
		remove_vehicle(ship)
	airship = {}


## Words for where something is: by a strongpoint, or a compass direction.
func _whereabouts(at: Vector3) -> String:
	var nearest: Strongpoint = null
	for point in strongpoints:
		if nearest == null or point.global_position.distance_to(at) < nearest.global_position.distance_to(at):
			nearest = point
	if nearest != null and nearest.global_position.distance_to(at) <= nearest.radius * 4.0:
		return "near %s" % nearest.title
	var flat := Vector2(at.x, at.z)
	if flat.length() < 25.0:
		return "in the middle of the map"
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return "to the %s" % names[posmod(roundi(flat.angle() / (PI / 4.0)), 8)]


func _tick_caches(delta: float) -> void:
	for cache in _caches:
		var container: LootContainer = cache.container
		if not is_instance_valid(container) or not container.items.is_empty():
			cache.refill_in = -1.0
			continue
		if cache.refill_in < 0.0:
			cache.refill_in = world.cache_refill_time
		cache.refill_in -= delta
		if cache.refill_in <= 0.0:
			cache.refill_in = -1.0
			# A cache that refills in the middle of a war holds better things.
			container.set_items(world.roll_war_loot(cache.source, rng, war.intensity))
			cache.looted.clear()
			container.changed.emit()
			armory.on_cache_refilled(container.global_position)


## Every dead bot is replaced, so the world never runs out of enemies.
func _tick_bots(delta: float) -> void:
	# Enemies off (`enemies`): nobody comes back and nobody new comes in.
	if not enemies:
		_bot_respawns.clear()
		return
	for i in range(_bot_respawns.size() - 1, -1, -1):
		_bot_respawns[i] -= delta
		if _bot_respawns[i] > 0.0:
			continue
		_bot_respawns.remove_at(i)
		var spawns := _reinforcement_spawns()
		if not spawns.is_empty() and enemy_room() > 0:
			# Out of the players' sight, or anywhere if nobody is here to see.
			_add_bot(spawns[_farthest_from_players(spawns) if not active_players().is_empty()
					else rng.randi() % spawns.size()])
	# A hotter war draws in more bots, one at a time.
	_reinforce_in -= delta
	if _reinforce_in <= 0.0:
		_reinforce_in = world.reinforcement_time
		if _standing_bots() + _bot_respawns.size() < bot_target():
			_bot_respawns.append(0.0)
	_tick_orders(delta)


## How many bots the world wants alive right now: its own count, and more
## the hotter the war is.
func bot_target() -> int:
	# A world with no army of its own (a server run with `--bots 0`) has
	# nobody to send, however hot the war gets.
	if army_size() <= 0:
		return 0
	var want := army_size() + roundi(maxi(world.war_reinforcements, 0) * war.intensity)
	return want if enemy_budget() <= 0 else mini(want, army_size())


## The world's own army: `WorldDef.bot_count`, or none with enemies off.
## Under an `enemy_cap` the army leaves room for the map's bosses and
## guards, but always keeps at least half the cap.
func army_size() -> int:
	if not enemies:
		return 0
	var cap := enemy_budget()
	if cap <= 0:
		return world.bot_count
	# Pockets take room only while awake, so they hold none back.
	var fixed := _map_nodes("spawn_boss").size() + (0 if pockets_on() else _map_nodes("spawn_guard").size())
	return mini(world.bot_count, maxi(cap - fixed, ceili(cap * 0.5)))


## Whether the world's guards are encounter pockets (`WorldDef.pocket_wake`).
func pockets_on() -> bool:
	return enemies and world.pocket_wake > 0.0


## Whether the world fields enemies at all: an army, or pockets (a world of
## pockets may have no army). A run without bots (`--bots 0`) has neither.
func _fields_enemies() -> bool:
	return army_size() > 0 or pockets_on()


## This world's enemy budget: its own (`WorldDef.enemy_cap`) where it sets
## one, else `enemy_cap`; none (0) while `enemy_cap` is off, as in the tests
## and benches that build their own `Raid`.
func enemy_budget() -> int:
	if enemy_cap <= 0:
		return 0
	return world.enemy_cap if world.enemy_cap > 0 else enemy_cap


## How many more enemies the budget (`enemy_budget`) lets in now.
func enemy_room() -> int:
	if not enemies:
		return 0
	var cap := enemy_budget()
	return 1 << 30 if cap <= 0 else cap - bots.size()


## The enemy cap a program runs with: `--enemy-cap <n>`, then the
## environment's `ARES_ENEMY_CAP`, then the project setting
## `ares/stability/enemy_cap` (0 is no cap).
static func enemy_cap_wanted(args: PackedStringArray) -> int:
	var at := args.find("--enemy-cap")
	if at >= 0 and at + 1 < args.size():
		return maxi(args[at + 1].to_int(), 0)
	var env := OS.get_environment("ARES_ENEMY_CAP")
	if env != "":
		return maxi(env.to_int(), 0)
	return maxi(int(ProjectSettings.get_setting("ares/stability/enemy_cap", 0)), 0)


## Whether enemies are wanted, from (first match wins) the command line's
## `--enemies` / `--no-enemies`, the environment's `ARES_ENEMIES` ("1" or
## "0", which servers started from this program inherit), a `--bots` count
## over 0 (asking for bots is asking for enemies), then the project setting
## `ares/stability/enemies`.
static func enemies_wanted(args: PackedStringArray) -> bool:
	if "--no-enemies" in args:
		return false
	if "--enemies" in args:
		return true
	var env := OS.get_environment("ARES_ENEMIES")
	if env != "":
		return env != "0"
	var bots := args.find("--bots")
	if bots >= 0 and bots + 1 < args.size() and args[bots + 1].to_int() > 0:
		return true
	return bool(ProjectSettings.get_setting("ares/stability/enemies", true))


## Bots that no player is near are simulated less often, in longer steps
## (`Actor.thin`), so a big war costs the server little where nobody watches.
## The fight a player is in always runs every tick.
func _tick_detail(delta: float) -> void:
	_detail_in -= delta
	if _detail_in > 0.0:
		return
	_detail_in = DETAIL_EVERY
	var watchers: Array[Vector3] = []
	for state in players:
		if is_instance_valid(state.actor) and not state.actor.is_dead:
			watchers.append(state.actor.global_position)
	# Under `near_full_cap`, only the nearest that many of the bots in full
	# range run every tick; the rest step every second tick.
	var full_ok := {}
	if near_full_cap > 0:
		var near: Array = []
		for bot in bots:
			var d := INF
			for at in watchers:
				d = minf(d, at.distance_squared_to(bot.global_position))
			if d <= full_detail_range * full_detail_range:
				near.append([d, bot])
		if near.size() > near_full_cap:
			near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for k in mini(near.size(), near_full_cap):
			full_ok[near[k][1]] = true
	for i in bots.size():
		var bot := bots[i]
		var nearest := INF
		for at in watchers:
			nearest = minf(nearest, at.distance_squared_to(bot.global_position))
		if nearest <= full_detail_range * full_detail_range and (near_full_cap <= 0 or full_ok.has(bot)):
			bot.thin(1)
		elif nearest <= half_detail_range * half_detail_range:
			bot.thin(2, i)
		else:
			bot.thin(far_detail_step, i)


## The bots alive that belong to the world itself, not to an event.
func _standing_bots() -> int:
	var count := 0
	for bot in bots:
		if not _is_extra(bot):
			count += 1
	return count


## Where the next bot may arrive. On a map whose bot spawns name factions it
## joins the faction with the fewest alive, and never appears inside a site
## its faction has lost.
func _reinforcement_spawns() -> Array[Node3D]:
	var spawns := _map_nodes("spawn_bot")
	var alive := {}
	for marker in spawns:
		if marker.has_meta("faction"):
			alive[marker.get_meta("faction")] = 0
	if alive.is_empty():
		return spawns
	for bot in bots:
		if alive.has(bot.faction) and not _is_extra(bot):
			alive[bot.faction] += 1
	var weakest := ""
	for faction: String in alive:
		if weakest == "" or alive[faction] < alive[weakest]:
			weakest = faction
	var open := spawns.filter(func(marker: Node3D) -> bool:
		if marker.get_meta("faction", "") != weakest:
			return false
		for point in strongpoints:
			if point.covers(marker.global_position) and point.holder != "faction:" + weakest:
				return false
		return true)
	return open if not open.is_empty() else spawns


## The bot factions' war over the strongpoints (`WorldDef.bots_contest_sites`).
## Every few seconds each army's commander (`WarCommander`, `commander`)
## gives its orders: a garrison for every site it holds, nearest bots first,
## and fireteams for the rest, spread over the objectives worth most (a site
## of its own under attack, open ground, the other army's, a storm-covered
## push), never all one way, and away from fights it is losing.
func _tick_orders(delta: float) -> void:
	if not world.bots_contest_sites or strongpoints.is_empty():
		return
	_orders_in -= delta
	if _orders_in > 0.0:
		return
	_orders_in = ORDERS_EVERY
	var armies := {}
	var strength := {}
	for bot in bots:
		if is_instance_valid(bot) and not bot.is_dead and bot.has_node("Brain") and not _is_extra(bot):
			for point in strongpoints:
				if bot.global_position.distance_squared_to(point.global_position) <= pow(point.radius * 2.5, 2):
					if not strength.has(point):
						strength[point] = {}
					strength[point][bot.faction] = int(strength[point].get(bot.faction, 0)) + 1
			# A soldier falling back to its post is left to it.
			var brain := bot.get_node("Brain") as BotBrain
			if float(_busy_until.get(bot, 0.0)) > clock or brain._falling_back or brain.is_broken():
				continue
			if not armies.has(bot.faction):
				armies[bot.faction] = []
			armies[bot.faction].append(bot)
	# Untyped: a freed bot cannot be assigned to an `Actor` to be checked.
	for book: Dictionary in [_orders, _posted, _line_of]:
		for bot: Variant in book.keys():
			if not is_instance_valid(bot) or (bot as Actor).is_dead:
				book.erase(bot)
	# A share of each army stands on its line posts first.
	var on_line := {}
	for faction: String in armies:
		_man_lines(faction, armies[faction], on_line)
		armies[faction] = (armies[faction] as Array).filter(func(bot: Actor) -> bool:
			return not on_line.has(bot))
	var storm: Array = []
	if world.weather_pushes:
		storm = strongpoints.filter(func(p: Strongpoint) -> bool:
			return weather.strength_at(p.global_position) >= STORM_COVER)
	var teams := {}
	var first := 1
	var sieges := {}
	var grounds := {}
	for bot: Actor in on_line:
		grounds[bot] = "line"
	for faction: String in armies:
		var orders := commander.plan(faction, armies[faction], strongpoints, strength, storm,
				world.garrison_size, teams, first, war.intensity, world.elite_kinds)
		first += 100
		var pushing := {}
		var sizes := {}
		var centres := {}
		for bot: Actor in orders:
			var id := int(teams.get(bot, 0))
			sizes[id] = int(sizes.get(id, 0)) + 1
			centres[id] = (centres.get(id, Vector3.ZERO) as Vector3) + bot.global_position
		var rank := {}
		for bot: Actor in orders:
			var id := int(teams.get(bot, 0))
			var point: Strongpoint = orders[bot]
			var ring := -1.0
			if id != 0 and _besieging(faction, point, strength.get(point, {})):
				var key := "%s:%d" % [faction, point.index]
				if not sieges.has(key):
					sieges[key] = float(_sieges.get(key, clock))
				if clock - float(sieges[key]) < world.siege_time:
					ring = float(rank.get(id, 0))
					rank[id] = ring + 1.0
			if ring >= 0.0:
				var from: Vector3 = centres[id] / float(sizes[id])
				_order(bot, point, _siege_spot(point, from, int(ring), int(sizes[id])), 6.0)
				grounds[bot] = "siege"
			else:
				_order(bot, point)
				grounds[bot] = world.ground_at(bot.global_position)
			(bot.get_node("Brain") as BotBrain).set_team(id, int(sizes[id]) if id != 0 else 0)
			if teams.has(bot):
				if not pushing.has(orders[bot]):
					pushing[orders[bot]] = []
				pushing[orders[bot]].append(bot)
		# The army's main push is the objective most of its teams go for.
		var main: Strongpoint = null
		for point: Strongpoint in pushing:
			if main == null or pushing[point].size() > pushing[main].size():
				main = point
		if main != null:
			_note_army_target(faction, main, pushing[main])
	_sieges = sieges
	if not world.ground_styles.is_empty():
		for bot: Actor in grounds:
			(bot.get_node("Brain") as BotBrain).set_ground(grounds[bot],
					world.ground_styles.get(grounds[bot], {}))


## Puts `line_share` of an army on its own "line_post" markers (meta
## "faction"), a standing skirmish line: a soldier keeps its post from one
## round to the next, and an empty post takes the nearest one free. The
## ones posted go in `on_line`.
func _man_lines(faction: String, army: Array, on_line: Dictionary) -> void:
	if world.line_share <= 0.0 or line_posts.is_empty():
		return
	var posts := line_posts.filter(func(post: Node3D) -> bool:
		return str(post.get_meta("faction", "")) == faction)
	var count := mini(posts.size(), roundi(army.size() * world.line_share))
	var free: Array = army.filter(func(bot: Actor) -> bool:
		return str(bot.get_meta("kind", "")) not in world.elite_kinds)
	var manned := {}
	for bot: Actor in free:
		if manned.size() < count and _line_of.has(bot) and not manned.has(_line_of[bot]):
			manned[_line_of[bot]] = bot
	for bot: Variant in _line_of.keys():
		if str(_line_of[bot].get_meta("faction", "")) != faction:
			continue
		if not manned.has(_line_of[bot]) or manned[_line_of[bot]] != bot:
			_line_of.erase(bot)
	for post: Node3D in posts:
		if manned.size() >= count:
			break
		if manned.has(post):
			continue
		var best: Actor = null
		for bot: Actor in free:
			if _line_of.has(bot):
				continue
			if best == null or bot.global_position.distance_squared_to(post.global_position) \
					< best.global_position.distance_squared_to(post.global_position):
				best = bot
		if best == null:
			break
		manned[post] = best
		_line_of[best] = post
	for post: Node3D in manned:
		var bot: Actor = manned[post]
		on_line[bot] = true
		_orders.erase(bot)
		if (_posted.get(bot, Vector3.INF) as Vector3).distance_to(post.global_position) > 1.0:
			_posted[bot] = post.global_position
			(bot.get_node("Brain") as BotBrain).post_to(post.global_position, 4.0)


## Whether `faction`'s team sent at `point` should ring it first: a site
## the other side holds, with enough of them near it.
func _besieging(faction: String, point: Strongpoint, near: Dictionary) -> bool:
	if world.siege_time <= 0.0 or point.holder == "" or point.holder == "faction:" + faction:
		return false
	var theirs := 0
	for side: String in near:
		if side != faction:
			theirs += int(near[side])
	return theirs >= world.siege_holders


## Where the `index`th of a team of `size` stands in the ring round
## `point`, on the side the team comes from, spread along an arc.
func _siege_spot(point: Strongpoint, from: Vector3, index: int, size: int) -> Vector3:
	var out := from - point.global_position
	out.y = 0.0
	if out.length_squared() < 1.0:
		out = Vector3.FORWARD
	var angle := atan2(out.x, out.z) + (index - (size - 1) * 0.5) * 0.18
	var spot := point.global_position + Vector3(sin(angle), 0.0, cos(angle)) * (point.radius + world.siege_reach)
	if map != null and map.has_method("ground_height"):
		spot.y = float(map.call("ground_height", spot.x, spot.z))
	return spot


## A faction's army has a new site to go for: a push, told before it lands
## (a horn at the site, a war feed line, an arrow on the watch map). The
## first orders of a raid set the targets quietly.
func _note_army_target(faction: String, target: Strongpoint, army: Array) -> void:
	var first := not _push_target.has(faction)
	if _push_target.get(faction) == target or army.size() < PUSH_MIN:
		return
	_push_target[faction] = target
	if first:
		return
	var from := Vector3.ZERO
	for bot: Actor in army:
		from += bot.global_position
	from /= army.size()
	var loud := clock - float(_push_loud_at.get(faction, -INF)) >= PUSH_EVERY
	if loud:
		_push_loud_at[faction] = clock
	var title := world.faction_title(faction)
	note_push(target.index, from, title, loud)
	if loud:
		var line := "%s is pushing on %s" % [title, target.title]
		war_feed.emit(line.left(1).to_upper() + line.substr(1))


## Records an army's push on site `site` (its `Strongpoint.index`) for the
## views, and lets them know. The server calls it from its orders; a
## client from what `NetSession` was told.
func note_push(site: int, from: Vector3, title: String, loud: bool) -> void:
	pushes = pushes.filter(func(p: Dictionary) -> bool:
		return p.title != title and clock - float(p.at) < PUSH_SHOWN)
	pushes.append({"site": site, "from": from, "title": title, "at": clock})
	army_pushed.emit(site, from, title, loud)


## The pushes still worth showing.
func live_pushes() -> Array[Dictionary]:
	return pushes.filter(func(p: Dictionary) -> bool: return clock - float(p.at) < PUSH_SHOWN)


## A loud push is heard: a war horn at the site, carried far, and a ring
## of light where it stands. View only.
func _show_push(site: int, _from: Vector3, _title: String, loud: bool) -> void:
	if not loud or site < 0 or site >= strongpoints.size():
		return
	var at := strongpoints[site].global_position + Vector3(0, 0.2, 0)
	Fx.ring(self, at, strongpoints[site].radius, Color(1.0, 0.45, 0.2), 1.6, false)
	Sfx.play("war_horn", at, 6.0, 420.0, 40.0)


## The site a faction goes for next, by the commander's worth of each site
## from the middle of the ground it holds (or of its bots, if it holds none).
func _army_target(faction: String, held: Array, army: Array) -> Strongpoint:
	var from := Vector3.ZERO
	var anchors: Array = held if not held.is_empty() else army
	if anchors.is_empty():
		return null
	for node: Node3D in anchors:
		from += node.global_position
	from /= anchors.size()
	var best: Strongpoint = null
	var best_score := 0.0
	for point in strongpoints:
		if point.holder == "faction:" + faction:
			continue
		var storm := world.weather_pushes and weather.strength_at(point.global_position) >= STORM_COVER
		var score := commander.worth(faction, point, from, {}, storm)
		if score > best_score:
			best_score = score
			best = point
	return best


## Sends `bot` at `point`: into it, or with `at` set short of it (a siege
## ring), to hold `radius` round there. A bot already sent there is left
## alone, so its patrol goes on.
func _order(bot: Actor, point: Strongpoint, at := Vector3.INF, radius := 0.0) -> void:
	var spot := point.global_position if at == Vector3.INF else at
	if _orders.get(bot) == point and (_posted.get(bot, Vector3.INF) as Vector3).distance_to(spot) < 4.0:
		return
	_orders[bot] = point
	_posted[bot] = spot
	(bot.get_node("Brain") as BotBrain).post_to(spot, point.radius if at == Vector3.INF else radius)


## Vehicles nobody rides are cleared away, and empty parking spots get a new one.
func _tick_vehicles(delta: float) -> void:
	for vehicle in vehicles.duplicate():
		if vehicle.call("is_occupied"):
			_idle[vehicle] = 0.0
			continue
		_idle[vehicle] = _idle.get(vehicle, 0.0) + delta
		if _idle[vehicle] >= world.vehicle_respawn_time and not _is_parked(vehicle):
			remove_vehicle(vehicle)
	for spot in _parking:
		if _is_parked(spot.vehicle):
			spot.empty_for = 0.0
			continue
		spot.empty_for += delta
		if spot.empty_for >= float((spot.marker as Node3D).get_meta("respawn", world.vehicle_respawn_time)):
			spot.empty_for = 0.0
			spot.vehicle = _park_vehicle(spot.marker, spot.source)


func _is_parked(vehicle: Variant) -> bool:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle not in vehicles:
		return false
	for spot in _parking:
		var marker: Node3D = spot.marker
		if spot.vehicle == vehicle:
			return vehicle.global_position.distance_to(marker.global_position) < PARKED_DISTANCE
	return false


## Depot progress for the local player, 0..1.
func bank_progress() -> float:
	var best := 0.0
	if player == null or not is_instance_valid(player):
		return best
	for depot in depots:
		best = maxf(best, depot.progress_for(player))
	return best


func _can_bank(actor: Actor) -> bool:
	var state := state_for(actor)
	return state != null and not state.finished


## Drops a player in and returns their actor: the start of one life. In a
## solo raid the newest one is `player`, so calling this again after a death
## drops the player back in. `p_kit` empty means the world's free scrap kit;
## `[Loadout.BARE]` means nothing at all.
## `p_owner` says whose life this is (an account id), so renown carries over
## from their earlier lives here; without it every life is a stranger's.
## `p_renown` is their lifetime renown, which sets the rank others see.
## `p_insured` is their insured item (`SafetyNets`), recalled home instead
## of dropping in the bag if it is on the body at the death. Only an item
## in this kit counts: the owner of the stash decides, never a client.
func add_player(p_kit: Array = [], p_mastery: Dictionary = {}, p_name := "Raider",
		p_owner := "", p_renown := 0, p_drop := "", p_insured := "") -> Actor:
	var state := PlayerState.new()
	state.started = clock
	state.kit.assign((p_kit if not p_kit.is_empty() else world.starter_loadout()).filter(
			func(id: Variant) -> bool: return id != Loadout.BARE))
	if p_insured != "" and p_insured in state.kit and world.gear_at_risk:
		state.insured = p_insured
	state.picks = p_mastery
	var spawns := _map_nodes("spawn_player")
	var marker := 0
	# Anyone arriving in a world that is already running lands away from the
	# fighting, and cannot be hurt for a moment.
	var arriving := mode == Mode.SERVER or _player_count > 0
	if mode == Mode.SOLO and player != null:
		_remove_actor(player)
	if arriving and not spawns.is_empty():
		marker = _safest_spawn(spawns, state)
	else:
		marker = rng.randi() % maxi(spawns.size(), 1)
	if squad_spawn:
		if _squad_marker < 0:
			_squad_marker = marker
		marker = _squad_marker
	var at: Vector3 = spawns[marker].global_position if not spawns.is_empty() else Vector3.ZERO
	# Where they asked to land (see `drop_choices`). With no choice, or one
	# that is no longer on offer, a strongpoint they hold is a forward drop
	# point and otherwise they land away from the fighting.
	var forward: Strongpoint = null
	if p_drop == PORTAL_DROP and not outposts.is_empty():
		# One outpost per squad, so a squad through the same portal lands together.
		var squad: String = squads.get(p_owner, _player_side(p_owner)) if p_owner != "" else ""
		at = outposts[absi(hash(squad)) % outposts.size()].global_position
	elif arriving and p_owner != "":
		var side := _player_side(p_owner)
		var offered := drop_choices(p_owner).map(func(c: Dictionary) -> String: return c.id)
		if p_drop == "hot" and "hot" in offered and not spawns.is_empty() and not squad_spawn:
			at = spawns[_nearest_spawn(spawns, war.centre)].global_position
		elif p_drop.begins_with("point:") and p_drop in offered:
			forward = strongpoints[int(p_drop.trim_prefix("point:"))]
		elif p_drop != "safe":
			forward = _forward_drop(side)
	if forward != null:
		var angle := rng.randf_range(0.0, TAU)
		at = forward.global_position + Vector3(cos(angle), 0.0, sin(angle)) * forward.radius * 0.4
	# Back in a safe zone through one of its doorways: in front of that door.
	var doorway := _arrival_doorway(p_drop)
	if doorway != null:
		at = arrival_point(doorway)
	var actor := Actor.new()
	actor.name = "Player" if _player_count == 0 else "Player%d" % _player_count
	_player_count += 1
	actor.is_player = mode == Mode.SOLO
	actor.display_name = p_name
	add_child(actor)
	# Spread out players who arrive at the same spawn point.
	if mode == Mode.SERVER and doorway == null:
		at += Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
	actor.global_position = _stand(at)
	Loadout.equip(actor, state.kit)
	Loadout.arrive_unarmed(actor)
	actor.weapons_locked = world.safe_zone or not world.weapons_free
	state.actor = actor
	state.owner = p_owner if p_owner != "" else "#%d" % actor.get_instance_id()
	if mode != Mode.CLIENT:
		renown.enter(state.owner, p_name, p_renown)
	state.mastery = MasteryTracker.new()
	state.mastery.name = "Mastery" if _player_count == 1 else "Mastery%d" % _player_count
	add_child(state.mastery)
	state.mastery.setup(actor, p_mastery)
	players.append(state)
	if mode == Mode.SOLO:
		player = actor
		mastery = state.mastery
	if arriving:
		actor.protected_left = world.spawn_protection
	actor.died.connect(_on_actor_died)
	actor.artifact.used.connect(func(_effect: String) -> void: _count(state, "artifacts"))
	actor.health.damaged.connect(func(info: DamageInfo) -> void:
		if info.source is Actor and info.source != actor and is_instance_valid(info.source):
			state.last_hit_by = info.source.get_instance_id()
			state.last_hit_at = clock
		_mark_combat(state))
	actor.hit_confirmed.connect(func(_target: Actor, _info: DamageInfo, _lethal: bool) -> void:
		_mark_combat(state))
	world.on_spawn(actor)
	_publish_standing()
	actor_spawned.emit(actor)
	# Their own vehicle, if they brought one, rides on their watch as a toy
	# (never one the launch holds back, `LaunchScope`).
	for id in state.kit:
		if ItemDB.has_tag(id, "vehicle") and not LaunchScope.holds_item(id):
			state.deployed_vehicles.append(id)
			state.stowed.append(id)
	watch_changed.emit(actor)
	return actor


## The doorway someone comes back through, for a `p_drop` of
## "from:<destination>": in a safe zone, the "portal" marker leading where
## they have been ("world:ashfront", "arena", "home"). Null otherwise, and
## they arrive the usual way.
func _arrival_doorway(drop: String) -> Node3D:
	if not world.safe_zone or not drop.begins_with("from:"):
		return null
	var destination := drop.trim_prefix("from:")
	for node in _map_nodes("portal"):
		if str(node.get_meta("destination", "")) == destination:
			return node
	return null


## Where someone coming out of a doorway stands: just clear of it, toward
## the middle of the map, so they see the door they came through and are not
## offered the trip again. The same spot every time.
static func arrival_point(doorway: Node3D) -> Vector3:
	var at := doorway.global_position
	var inward := Vector3(-at.x, 0.0, -at.z)
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.BACK
	return at + inward * (float(doorway.get_meta("radius", 2.0)) + 2.0)


## The spawn point farthest from everyone already in the raid, so nobody
## joins into the middle of a fight.
func _safest_spawn(spawns: Array[Node3D], arriving: PlayerState = null) -> int:
	var others: Array[Actor] = []
	others.append_array(bots)
	others.append_array(active_players())
	# Someone fresh (little gear brought) lands well away from anyone who
	# came in strong (DESIGN.md "Challenge and balance data"): a strong
	# player counts as `strong_player_wariness` times as near.
	var fresh := arriving != null and world.fresh_gear_value > 0 and is_fresh(arriving)
	var best := 0
	var best_distance := -1.0
	for i in spawns.size():
		var nearest := INF
		for other in others:
			if not other.is_dead:
				var distance := spawns[i].global_position.distance_to(other.global_position)
				var them := state_for(other)
				if fresh and them != null and them != arriving and is_strong(them):
					distance /= world.strong_player_wariness
				nearest = minf(nearest, distance)
		if nearest > best_distance:
			best_distance = nearest
			best = i
	return best


## Whether a life came in with little gear (`WorldDef.fresh_gear_value`),
## or strong (`strong_gear_value`), by what it brought from the stash.
func is_fresh(state: PlayerState) -> bool:
	return ItemDB.total_value(state.kit) < world.fresh_gear_value


func is_strong(state: PlayerState) -> bool:
	return world.strong_gear_value > 0 and ItemDB.total_value(state.kit) >= world.strong_gear_value


## For a dropped connection. Nobody escapes a fight by quitting: the body
## stays where it stood, helpless, for the sign-out time (longer if they were
## in a fight). If it survives, everything on it goes home.
func remove_player(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null:
		return
	if world.safe_zone:
		# Nothing was at stake: they and the vehicle they showed off just go.
		for vehicle in state.parked:
			if is_instance_valid(vehicle):
				vehicle.call("dismount_all")
				vehicles.erase(vehicle)
				vehicle_removed.emit(vehicle)
				vehicle.queue_free()
		_remove_actor(actor)
		return
	if not state.finished and not actor.is_dead:
		begin_sign_out(actor, true)
		return
	players.erase(state)


## Whether `actor` is a body left standing by a dropped connection that its
## player can still come back to (`reclaim_player`).
func is_unguarded(actor: Actor) -> bool:
	var state := state_for(actor)
	return state != null and state.sign_out_forced and not state.finished \
			and is_instance_valid(actor) and not actor.is_dead


## A player whose connection dropped is back before their body's sign-out ran
## out: they take over the body where it stands. The forced countdown ends.
## A sign-out they had started themselves carries on with the time it has
## left, unless the body was in a fight meanwhile (as a hit would have
## cancelled it). Returns false if the body is gone, dead or already home.
func reclaim_player(actor: Actor) -> bool:
	if mode == Mode.CLIENT or not is_unguarded(actor):
		return false
	var state := state_for(actor)
	var had: Array = state.dropped_sign_out
	state.dropped_sign_out = []
	state.sign_out_forced = false
	var fighting := clock - state.last_combat < world.combat_time
	if had.size() == 3 and not fighting:
		state.sign_out_total = maxf(float(had[0]), state.sign_out_left)
		state.sign_out_fixed = bool(had[1])
		state.sign_out_door = str(had[2])
		actor.notice.emit("Back in your body. Still signing out")
	else:
		state.sign_out_left = -1.0
		state.sign_out_fixed = false
		state.sign_out_door = ""
		state.at_beacon = null
		actor.notice.emit("Back in your body")
	actor.set_sign_out_beacon(false)
	sign_out_changed.emit(actor, state.sign_out_left)
	return true


## How long a hop or a step off a ledge can be before a sign-out counts as
## airborne. Below this, the ground rate keeps running.
const SIGN_OUT_AIR_GRACE := 0.35
## How far the airborne sign-out's sound carries. Bots on patrol hear it
## through `Combat.noise` and come to look; the column itself is the thing
## players see.
const SIGN_OUT_BEACON_HEAR := 120.0


## True while `actor` is in the air for a sign-out: on foot above the ground,
## or riding a vehicle that has left it. A bike on the road is the ground rate.
func _sign_out_in_air(actor: Actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var ride := actor.vehicle
	if ride != null:
		return float(ride.get("airborne_time")) > SIGN_OUT_AIR_GRACE
	return actor.airborne_time > SIGN_OUT_AIR_GRACE


## The sign-out length for where `actor` is now: ground, or the air time.
func _sign_out_span(actor: Actor) -> float:
	if _sign_out_in_air(actor):
		return world.sign_out_air_time
	return world.sign_out_time


## Starts a player's sign-out. On the ground it takes `WorldDef.sign_out_time`
## (15 s); in the air, `sign_out_air_time` (25 s), with a beacon. Taking or
## dealing damage cancels it, so it cannot be started in a fight. A gate
## outpost keeps its short sign-out. `forced` is for a player who is gone: it
## cannot be cancelled, the body stands for the ground time (or the combat
## log), and it does not grow for being in the air. Returns false if it did
## not start.
func begin_sign_out(actor: Actor, forced := false) -> bool:
	var state := state_for(actor)
	if state == null or state.finished or actor.is_dead or mode == Mode.CLIENT:
		return false
	var fighting := clock - state.last_combat < world.combat_time
	if forced:
		var wait := world.combat_log_time if fighting else world.sign_out_time
		if state.sign_out_left >= 0.0:
			wait = minf(wait, state.sign_out_left)
			# Kept for `reclaim_player`: a player back in time carries on
			# with the sign-out they had started.
			if not state.sign_out_forced:
				state.dropped_sign_out = [state.sign_out_total, state.sign_out_fixed, state.sign_out_door]
		var yaw := actor.cmd.yaw
		actor.cmd.apply_array(ActorCommand.new().to_array())
		actor.cmd.yaw = yaw
		state.sign_out_forced = true
		state.sign_out_fixed = true
		state.sign_out_left = wait
		# A body left behind counts down where it stands, beacon or not.
		state.at_beacon = null
		actor.set_sign_out_beacon(false)
	elif state.sign_out_left >= 0.0:
		return true
	elif fighting:
		actor.notice.emit("You cannot sign out in a fight")
		return false
	elif _beacons_only():
		var beacon := beacon_at(actor.global_position)
		if beacon == null:
			actor.notice.emit("Sign out at a warm beacon")
			return false
		# A beacon powers up while you hold it; the count runs only inside.
		state.at_beacon = beacon
		state.sign_out_fixed = true
		state.sign_out_door = ""
		state.sign_out_left = world.beacon_sign_out_time
		actor.notice.emit("Powering up %s. Stay close for %d seconds"
				% [beacon.get_meta("name", "the beacon"), ceili(world.beacon_sign_out_time)])
	elif state.sheltered:
		# A gate outpost is the way out: a quick sign-out, and it stays that
		# long even if they are off the floor inside the bubble.
		state.sign_out_fixed = true
		state.sign_out_door = ""
		state.sign_out_left = world.outpost_sign_out_time
		actor.notice.emit("Signing out at the gate")
	else:
		state.sign_out_fixed = false
		state.sign_out_door = ""
		var span := _sign_out_span(actor)
		state.sign_out_left = span
		if _sign_out_in_air(actor):
			actor.notice.emit("Signing out in the air. The beacon stays up for %d seconds" % ceili(span))
		else:
			actor.notice.emit("Signing out. Stay out of trouble for %d seconds" % ceili(span))
	state.sign_out_total = state.sign_out_left
	sign_out_changed.emit(actor, state.sign_out_left)
	return true


func cancel_sign_out(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null or state.sign_out_left < 0.0 or state.sign_out_forced or mode == Mode.CLIENT:
		return
	state.sign_out_left = -1.0
	state.sign_out_fixed = false
	state.sign_out_door = ""
	state.at_beacon = null
	state.count_rate = 1.0
	actor.set_sign_out_beacon(false)
	actor.notice.emit("Sign-out cancelled")
	sign_out_changed.emit(actor, -1.0)


## Whether `actor` may abandon this life here (`abandon`): out in a world
## where gear is at stake, alive, and still playing their body (not one a
## dropped connection left standing).
func can_abandon(actor: Actor) -> bool:
	var state := state_for(actor)
	return state != null and not state.finished and not state.sign_out_forced \
			and is_instance_valid(actor) and not actor.is_dead \
			and world != null and not world.safe_zone and world.gear_at_risk


## The player gives this life up where they stand: a quick way out that is
## never a way to leave with the loot. It is a death in every way (DESIGN.md
## "Abandon"): what they carry falls in their bag (or as the world's death
## rule says), the insured item is recalled and salvage paid, and if they
## were hurt within the fight time their last attacker gets the kill, so it
## never takes a kill or a bounty away from anyone. Authority only; the
## result says "abandoned" so the game goes straight home. Returns false
## where it cannot happen (`can_abandon`).
func abandon(actor: Actor) -> bool:
	if mode == Mode.CLIENT or not can_abandon(actor):
		return false
	var state := state_for(actor)
	var killer: Actor = null
	if clock - state.last_hit_at < world.combat_time:
		var by := instance_from_id(state.last_hit_by) if state.last_hit_by != 0 else null
		if by is Actor and is_instance_valid(by) and by != actor:
			killer = by
	# Quietly: the life is over, not a sign-out called off.
	state.sign_out_left = -1.0
	state.at_beacon = null
	actor.set_sign_out_beacon(false)
	state.abandoned = true
	actor.kill("abandon", killer)
	return true


## How far along an actor's sign-out is, 0..1, or below zero when there is none.
func sign_out_progress(actor: Actor) -> float:
	var state := state_for(actor)
	if state == null or state.sign_out_left < 0.0 or state.sign_out_total <= 0.0:
		return -1.0
	return clampf(1.0 - state.sign_out_left / state.sign_out_total, 0.0, 1.0)


func _tick_sign_outs(delta: float) -> void:
	for state in players.duplicate():
		if state.finished or state.sign_out_left < 0.0:
			continue
		var actor: Actor = state.actor
		# The authority retargets when they leave or touch the ground. A
		# client only counts down what it was last told.
		if mode != Mode.CLIENT and is_instance_valid(actor) and not state.sign_out_fixed:
			_retarget_sign_out(state)
		if mode != Mode.CLIENT and is_instance_valid(actor):
			_update_sign_out_beacon(state, delta)
		# A Phase Cloak never hides a sign-out: the countdown waits for it,
		# and the beacon (if they are in the air) stays up.
		if is_instance_valid(actor) and actor.is_cloaked():
			continue
		if state.at_beacon != null and mode != Mode.CLIENT and is_instance_valid(actor):
			var rate := _beacon_rate(state)
			if not is_equal_approx(rate, state.count_rate):
				state.count_rate = rate
				# The owner's countdown follows the beacon's pace.
				sign_out_changed.emit(actor, state.sign_out_left)
		elif mode != Mode.CLIENT:
			state.count_rate = 1.0
		state.sign_out_left = maxf(0.0, state.sign_out_left - delta * state.count_rate)
		# A client only shows the countdown. The server decides when it ends.
		if state.sign_out_left <= 0.0 and mode != Mode.CLIENT:
			_leave(state)


## Switches the countdown between the ground rate and the air rate. Time
## already spent is progress, so landing shortens the seconds left and
## lifting off lengthens them, without starting over.
func _retarget_sign_out(state: PlayerState) -> void:
	var span := _sign_out_span(state.actor)
	if state.sign_out_total <= 0.0 or is_equal_approx(span, state.sign_out_total):
		return
	var progress := clampf(1.0 - state.sign_out_left / state.sign_out_total, 0.0, 1.0)
	state.sign_out_total = span
	state.sign_out_left = (1.0 - progress) * span
	sign_out_changed.emit(state.actor, state.sign_out_left)


## The beacon column for an airborne sign-out, and a sound bots can hear.
## A gate sign-out and a body left by a disconnect do not raise one.
func _update_sign_out_beacon(state: PlayerState, delta: float) -> void:
	var actor := state.actor
	var show := state.sign_out_left >= 0.0 and not state.finished and not state.sign_out_fixed \
			and _sign_out_in_air(actor)
	if show and not actor.sign_out_beacon:
		state.beacon_hum = 0.0
		var progress := 0.0
		if state.sign_out_total > 0.0:
			progress = 1.0 - state.sign_out_left / state.sign_out_total
		# Starting in the air already said so. Lifting off mid-count gets a line.
		if progress > 0.02:
			actor.notice.emit("Beacon up. The sign-out is longer in the air")
	if actor.sign_out_beacon != show:
		actor.set_sign_out_beacon(show)
	if not show:
		return
	state.beacon_hum -= delta
	if state.beacon_hum > 0.0:
		return
	state.beacon_hum = 2.0
	Combat.noise(actor, actor.global_position, SIGN_OUT_BEACON_HEAR)


## Whether this world signs out only at warm beacons. Like gate outposts, a
## zone rule: the test suite's older checks turn it off.
func _beacons_only() -> bool:
	return world.sign_out_at_beacons and zone_rules and not beacons.is_empty()


## The warm beacon an actor stands at, or null.
func beacon_at(at: Vector3) -> Node3D:
	for marker in beacons:
		if waits_on_keeper(marker):
			continue
		var flat := Vector2(at.x - marker.global_position.x, at.z - marker.global_position.z)
		if flat.length() <= float(marker.get_meta("radius", 6.0)) and absf(at.y - marker.global_position.y) < 4.0:
			return marker
	return null


## How fast a beacon sign-out counts down: nothing while its player is away
## from the beacon (it waits, held), and faster for each other player
## powering the same one, so company helps but one can do it alone.
func _beacon_rate(state: PlayerState) -> float:
	var actor := state.actor
	if beacon_at(actor.global_position) != state.at_beacon:
		if not state.beacon_left:
			state.beacon_left = true
			actor.notice.emit("Back to the beacon: it only powers up while you hold it")
		return 0.0
	state.beacon_left = false
	var others := 0
	for other in players:
		if other != state and not other.finished and other.at_beacon == state.at_beacon \
				and other.sign_out_left >= 0.0 and is_instance_valid(other.actor) \
				and beacon_at(other.actor.global_position) == state.at_beacon:
			others += 1
	return minf(1.0 + world.beacon_join_bonus * others, world.beacon_join_cap)


func _mark_combat(state: PlayerState) -> void:
	state.last_combat = clock
	if state.sign_out_left >= 0.0 and not state.finished:
		cancel_sign_out(state.actor)


func state_for(actor: Actor) -> PlayerState:
	for state in players:
		if state.actor == actor:
			return state
	return null


## Players still in the raid.
## What this world looks like from outside, for a doorway or a travel screen:
## how many are fighting, how hot the war is, the biggest bounty and the
## event running, and the most wanted (`wanted`): their names and bounties,
## which the plaza's board shows, but never where anyone is.
func status() -> Dictionary:
	var bounty := 0
	var fighting := active_players()
	for actor in fighting:
		if is_instance_valid(actor):
			bounty = maxi(bounty, actor.bounty)
	return {"players": fighting.size(), "war": snappedf(war.intensity, 0.05), "level": war.level_name(),
			"bounty": bounty, "event": str(event.get("title", "")),
			"storm": world.weather_name if weather.active() else "", "wanted": wanted(),
			"front": front(), "moments": live_moments(), "hunted": hunted()}


## The War Room's front line: each landmark of this world, where it stands
## (a landmark, never a person) and who holds it, as {name, x, z, holder
## (an army's faction, "players" or ""), contested}. A player's own side key
## never leaves the server.
func front() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for point in strongpoints:
		if not is_instance_valid(point):
			continue
		var holder := ""
		if point.holder_is_player:
			holder = "players"
		elif point.holder.begins_with("faction:"):
			holder = point.holder.trim_prefix("faction:")
		var at := point.global_position if point.is_inside_tree() else Vector3.ZERO
		out.append({"name": point.title.left(24), "x": roundi(at.x), "z": roundi(at.z), "holder": holder,
				"contested": point.contested})
	return out


## Tells the plaza's War Room of a big moment here (a warlord or a boss
## brought down, a landmark changing hands). Authority only; the newest
## `MOMENTS_KEPT` are kept.
func note_moment(kind: String, text: String) -> void:
	if mode == Mode.CLIENT or text == "":
		return
	moments.push_front({"kind": kind.left(16), "text": text.left(80), "at": int(Time.get_unix_time_from_system())})
	if moments.size() > MOMENTS_KEPT:
		moments.resize(MOMENTS_KEPT)


## The moments still news (`MOMENT_LIFETIME`), newest first.
func live_moments() -> Array[Dictionary]:
	var now := int(Time.get_unix_time_from_system())
	var out: Array[Dictionary] = []
	for moment in moments:
		if now - int(moment.at) <= MOMENT_LIFETIME:
			out.append(moment)
	return out


## Who the armies are hunting here, for the War Room: players an army holds
## a grudge against (`grudges`, `WorldDef.grudge_factions`, where a world
## keeps them), biggest first, as {name, clan, by (the army's faction)}.
## Who and by whom, never where. Empty where no army keeps grudges.
func hunted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world.safe_zone or not world.gear_at_risk:
		return out
	var bar := world.grudge_hunt
	var held := grudges
	var rows: Array = []
	for key: Variant in held:
		if not is_instance_valid(key) or not key is Actor or (key as Actor).is_dead:
			continue
		var actor := key as Actor
		var by := ""
		var top := 0.0
		var grudge: Variant = held[key]
		if typeof(grudge) != TYPE_DICTIONARY:
			continue
		for faction: Variant in grudge:
			if float(grudge[faction]) > top:
				top = float(grudge[faction])
				by = str(faction)
		if by == "" or top < bar * HUNTED_SHARE:
			continue
		rows.append([top, {"name": actor.display_name.left(24), "clan": actor.clan_tag.left(6), "by": by.left(16)}])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for row: Array in rows.slice(0, HUNTED_SHOWN):
		out.append(row[1])
	return out


## The most wanted here, for the plaza's board: up to `WANTED_SHOWN` players
## with a bounty or the Marked, biggest bounty first, each {name, clan,
## bounty, marked}. Who, never where (see `status`).
func wanted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world.safe_zone or not world.gear_at_risk:
		return out
	for actor in active_players():
		if not is_instance_valid(actor) or actor.is_dead or (actor.bounty <= 0 and not actor.marked):
			continue
		out.append({"name": actor.display_name.left(24), "clan": actor.clan_tag.left(6), "bounty": actor.bounty,
				"marked": actor.marked})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.bounty > b.bounty if a.bounty != b.bounty else (a.marked and not b.marked))
	return out.slice(0, WANTED_SHOWN)


func active_players() -> Array[Actor]:
	var out: Array[Actor] = []
	for state in players:
		if not state.finished:
			out.append(state.actor)
	return out


func _spawn_bots() -> void:
	var spawns := _map_nodes("spawn_bot")
	if player != null:
		var far := spawns.filter(func(m: Node3D) -> bool:
			return m.global_position.distance_to(player.global_position) > MIN_BOT_SPAWN_DISTANCE)
		if not far.is_empty():
			spawns = far
	if spawns.is_empty():
		return
	for i in army_size():
		_add_bot(spawns[i % spawns.size()])


## Risk zones: a boss stands guard at each of the map's "spawn_boss" markers.
func _spawn_bosses() -> void:
	# A world run without bots (`--bots 0`) has no bosses either.
	if not _fields_enemies():
		return
	for marker in _map_nodes("spawn_boss"):
		if enemy_room() <= 0:
			break
		var boss := {"marker": marker, "bot": null, "back_in": 0.0, "helpers": {}, "adds": [], "shares": [],
				"socket_in": 0.0, "socket_next": 0, "purge_in": 0.0, "purge_next": 0, "venting": []}
		boss.bot = _add_boss(marker, boss)
		_bosses.append(boss)


func _add_boss(marker: Node3D, boss: Dictionary) -> Actor:
	var bot := _add_bot(marker, true)
	var brain := bot.get_node_or_null("Brain") as BotBrain
	if brain != null:
		brain.post_to(marker.global_position, float(marker.get_meta("radius", 12.0)))
	if marker.get_meta("keeper", false):
		bot.health.damaged.connect(_on_keeper_hurt.bind(boss))
	return bot


## A dungeon's garrison: a guard stands at each of the map's "spawn_guard"
## markers, kept to the ground round it, and comes back
## `WorldDef.guard_respawn_time` after it dies. Guards are ordinary bots of
## their marker's faction, outside the armies (`_is_extra`).
func _spawn_guards() -> void:
	if not _fields_enemies():
		return
	if pockets_on():
		# Every pocket starts asleep; those near a player wake at once.
		for marker in _map_nodes("spawn_guard"):
			var key: Variant = marker.get_meta("pocket", marker.get_instance_id())
			if not _pockets.has(key):
				_pockets[key] = {"guards": [], "awake": false, "idle": 0.0}
			(_pockets[key].guards as Array).append(_guards.size())
			_guards.append({"marker": marker, "bot": null, "back_in": 0.0, "brood": [],
					"brood_in": float(marker.get_meta("brood_every", 0.0)) * 0.5, "pocket": _pockets[key]})
		# At the start everyone near stands at once: the world is loading.
		_tick_pockets()
		_stand_queued(_pocket_queue.size())
		_seal_hives()
		return
	for marker in _map_nodes("spawn_guard"):
		if enemy_room() <= 0:
			break
		_guards.append({"marker": marker, "bot": _add_guard(marker), "back_in": 0.0, "brood": [],
				"brood_in": float(marker.get_meta("brood_every", 0.0)) * 0.5})
	_seal_hives()


func _add_guard(marker: Node3D) -> Actor:
	var bot := _add_bot(marker)
	var brain := bot.get_node_or_null("Brain") as BotBrain
	if brain != null:
		brain.post_to(marker.global_position, float(marker.get_meta("radius", 10.0)))
	return bot


func _tick_guards(delta: float) -> void:
	if not _pockets.is_empty():
		_tick_pocket_guards(delta)
		return
	var changed := false
	for guard in _guards:
		var bot: Variant = guard.bot
		if bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			_tick_brood(guard, delta)
			continue
		if guard.back_in <= 0.0:
			guard.back_in = world.guard_respawn_time
			guard.bot = null
			changed = true
			continue
		# With enemies off (`enemies`) or the budget full, its clock waits.
		if enemy_room() <= 0:
			continue
		guard.back_in -= delta
		if guard.back_in <= 0.0:
			guard.bot = _add_guard(guard.marker)
			changed = true
	if changed:
		_seal_hives()


## The guards of a world of pockets (`WorldDef.pocket_wake`): a fallen one
## counts down `guard_respawn_time` whether its pocket is awake or not, and
## once it is due stands again when its pocket wakes, or, while it is
## awake, as soon as no player is within `POCKET_REFILL_CLEAR` of its post.
func _tick_pocket_guards(delta: float) -> void:
	var changed := _stand_queued(1)
	for guard in _guards:
		var bot: Variant = guard.bot
		if bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			_tick_brood(guard, delta)
			continue
		if bot != null:
			guard.bot = null
			guard.back_in = world.guard_respawn_time
			changed = true
			continue
		if guard.back_in > 0.0:
			guard.back_in -= delta
			continue
		var pocket: Dictionary = guard.pocket
		if pocket.awake and not guard.get("queued", false) and _pocket_room() > 0 \
				and _nearest_player(guard.marker.global_position) > POCKET_REFILL_CLEAR:
			guard.bot = _add_guard(guard.marker)
			changed = true
	_pocket_in -= delta
	if _pocket_in <= 0.0:
		_pocket_in = POCKET_EVERY
		changed = _tick_pockets() or changed
	if changed:
		_seal_hives()


## Wakes the pockets players have come near, nearest first while the
## budget has room, and puts to sleep those nobody has been near for
## `POCKET_SLEEP_AFTER` seconds. Says whether any guard came or went.
func _tick_pockets() -> bool:
	var changed := false
	var waking: Array = []
	var spare: Array = []
	for key: Variant in _pockets:
		var pocket: Dictionary = _pockets[key]
		# How far inside its wake range the nearest player is (under 0 is
		# inside), by each marker's own range.
		var reach := INF
		for i: int in pocket.guards:
			var marker := _guards[i].marker as Node3D
			reach = minf(reach, _nearest_player(marker.global_position)
					- float(marker.get_meta("wake", world.pocket_wake)))
		if not pocket.awake:
			pocket.idle = 0.0
			if reach <= 0.0:
				waking.append([reach, pocket])
			continue
		if _pocket_fighting(pocket):
			pocket.idle = 0.0
			continue
		# Its room can go to a pocket a player is nearer to.
		spare.append([reach, pocket])
		if reach <= POCKET_SLEEP_MARGIN:
			pocket.idle = 0.0
			continue
		pocket.idle += POCKET_EVERY
		if pocket.idle >= POCKET_SLEEP_AFTER:
			_sleep_pocket(pocket)
			changed = true
	waking.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	spare.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in waking:
		var pocket: Dictionary = entry[1]
		# A pocket wakes whole or waits for room (one bigger than the whole
		# budget takes what there is).
		var due := 0
		for i: int in pocket.guards:
			if _guards[i].bot == null and _guards[i].back_in <= 0.0:
				due += 1
		# Short of room, awake pockets that nobody is fighting and every
		# player is further from (by `POCKET_YIELD` metres) sleep for it,
		# farthest first: the room goes where someone is.
		var fits := enemy_budget() - _bosses.size()
		while _pocket_room() < mini(due, fits) and not spare.is_empty() \
				and float(spare.back()[0]) > float(entry[0]) + POCKET_YIELD:
			var far: Array = spare.pop_back()
			if far[1].awake:
				_sleep_pocket(far[1])
				changed = true
		var room := _pocket_room()
		if room <= 0 or (due > room and due <= fits):
			continue
		pocket.awake = true
		for i: int in pocket.guards:
			var guard: Dictionary = _guards[i]
			if guard.bot == null and guard.back_in <= 0.0 and not guard.get("queued", false) \
					and _pocket_room() > 0:
				guard.queued = true
				_pocket_queue.append(guard)
	return changed


## Stands up to `count` of the woken pockets' guards waiting their turn
## (a pocket that fell asleep again drops its own). Says whether any stood.
func _stand_queued(count: int) -> bool:
	var stood := 0
	while stood < count and not _pocket_queue.is_empty():
		var guard: Dictionary = _pocket_queue.pop_front()
		guard.queued = false
		if not guard.pocket.awake or guard.bot != null or guard.back_in > 0.0 or enemy_room() <= 0:
			continue
		guard.bot = _add_guard(guard.marker)
		stood += 1
	return stood > 0


## Room under `enemy_budget` for pockets, less what the queued guards keep.
func _pocket_room() -> int:
	return enemy_room() - _pocket_queue.size()


func _pocket_fighting(pocket: Dictionary) -> bool:
	for i: int in pocket.guards:
		var bot: Variant = _guards[i].bot
		if bot == null or not is_instance_valid(bot):
			continue
		var brain := (bot as Node).get_node_or_null("Brain") as BotBrain
		if brain != null and brain.target != null:
			return true
	return false


## A pocket goes to sleep: its standing guards and their brood leave
## quietly (no body, no loot), and stand again whole when it wakes.
func _sleep_pocket(pocket: Dictionary) -> void:
	pocket.awake = false
	pocket.idle = 0.0
	for i: int in pocket.guards:
		var guard: Dictionary = _guards[i]
		for one: Variant in guard.brood:
			if one != null and is_instance_valid(one):
				_remove_actor(one)
		(guard.brood as Array).clear()
		var bot: Variant = guard.bot
		if bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			_remove_actor(bot)
			guard.bot = null


## How far the nearest living player is from `at` (INF with nobody here).
func _nearest_player(at: Vector3) -> float:
	var best := INF
	for state in players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead:
			continue
		best = minf(best, actor.global_position.distance_to(at))
	return best


## A guard whose marker names a "brood" (a faction, its kin) spills one of
## it every "brood_every" seconds while a player is within "brood_range"
## of its post, no more than "brood_max" alive at once, each posted to the
## guard's ground and told where the nearest player is. The brood are
## outside the armies (`_is_extra`) and never replaced. A fallen guard
## spills nothing.
func _tick_brood(guard: Dictionary, delta: float) -> void:
	var marker := guard.marker as Node3D
	var kind := str(marker.get_meta("brood", ""))
	if kind == "":
		return
	var brood: Array = guard.brood
	for k in range(brood.size() - 1, -1, -1):
		var one: Variant = brood[k]
		if one == null or not is_instance_valid(one) or (one as Actor).is_dead:
			brood.remove_at(k)
	var near := _players_at(marker.global_position, float(marker.get_meta("brood_range", 20.0)))
	if near.is_empty():
		guard.brood_in = float(marker.get_meta("brood_every", 8.0)) * 0.5
		return
	guard.brood_in -= delta
	if guard.brood_in > 0.0 or brood.size() >= int(marker.get_meta("brood_max", 4)) or enemy_room() <= 0:
		return
	guard.brood_in = float(marker.get_meta("brood_every", 8.0))
	var bot := _add_bot(marker, false, kind)
	brood.append(bot)
	var brain := bot.get_node_or_null("Brain") as BotBrain
	if brain != null:
		brain.post_to(marker.global_position, float(marker.get_meta("radius", 10.0)))
	var target := near[0]
	for actor in near:
		if actor.global_position.distance_to(marker.global_position) < target.global_position.distance_to(marker.global_position):
			target = actor
	bot.heard.emit(target.global_position, target)


## A hive (a cache whose marker names a "hive") is sealed while the guard
## whose marker names the same hive stands, and opens once it falls
## (`LootContainer.sealed`). Authority only, so only it refuses the loot.
func _seal_hives() -> void:
	var standing := {}
	for guard in _guards:
		var key := str((guard.marker as Node3D).get_meta("hive", ""))
		var bot: Variant = guard.bot
		if key != "" and bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			standing[key] = str((bot as Actor).display_name)
		elif key != "" and not _pockets.is_empty() and bot == null and guard.back_in <= 0.0:
			# Asleep in its pocket, not fallen.
			standing[key] = str((guard.marker as Node3D).get_meta("name", "keeper"))
	for cache in _caches:
		var container: Variant = cache.container
		if str(cache.get("hive", "")) == "" or container == null or not is_instance_valid(container):
			continue
		var by := str(standing.get(cache.hive, ""))
		(container as LootContainer).sealed = ("The %s guards it" % by) if by != "" else ""


func _find_lifts() -> void:
	lifts.clear()
	for marker in _map_nodes("lift_stop"):
		var id := str(marker.get_meta("lift", ""))
		if not lifts.has(id):
			lifts[id] = {"stops": [], "power": null, "left": 0.0, "charge": 0.0, "wait": {}, "arrived": {}}
		(lifts[id].stops as Array).append(marker)
	for marker in _map_nodes("lift_power"):
		var id := str(marker.get_meta("lift", ""))
		if lifts.has(id):
			lifts[id].power = marker
	for id: String in lifts.keys():
		if (lifts[id].stops as Array).size() != 2:
			lifts.erase(id)


## Seconds a lift runs on for (0 while it is dead).
func lift_left(id: String) -> float:
	return float(lifts[id].left) if lifts.has(id) else 0.0


## A client's copy of a lift's power, from `NetSession`.
func set_lift(id: String, seconds_left: float) -> void:
	if lifts.has(id):
		lifts[id].left = maxf(seconds_left, 0.0)


## Lifts run down; the authority powers them from their switches and
## carries riders. Every machine hands the map what runs ("lift_power":
## id to seconds left) for the view.
func _tick_lifts(delta: float) -> void:
	var powers := {}
	for id: String in lifts:
		var lift: Dictionary = lifts[id]
		var was: float = lift.left
		lift.left = maxf(was - delta, 0.0)
		if mode != Mode.CLIENT:
			if was > 0.0 and lift.left <= 0.0:
				lift_changed.emit(id, 0.0)
			_power_lift(id, lift, delta)
			_ride_lift(lift, delta)
		powers[id] = lift.left
	map.set_meta("lift_power", powers)


## The living players, not riding anything, within `radius` of `at` (and
## 2.5 m up or down).
func _players_at(at: Vector3, radius: float) -> Array[Actor]:
	var found: Array[Actor] = []
	for state in players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead or actor.vehicle != null:
			continue
		var off := actor.global_position - at
		if absf(off.y) < 2.5 and Vector2(off.x, off.z).length_squared() <= radius * radius:
			found.append(actor)
	return found


## A dead lift is powered by anyone who stands at its switch for
## `WorldDef.lift_power_time`, and then runs `lift_powered_for` for everyone.
func _power_lift(id: String, lift: Dictionary, delta: float) -> void:
	var switch: Variant = lift.power
	if switch == null or not is_instance_valid(switch) or lift.left > 0.0:
		lift.charge = 0.0
		return
	var marker := switch as Node3D
	var here := _players_at(marker.global_position, float(marker.get_meta("radius", 2.5)))
	if here.is_empty():
		lift.charge = 0.0
		return
	lift.charge += delta
	if lift.charge < world.lift_power_time:
		return
	lift.charge = 0.0
	lift.left = world.lift_powered_for
	lift_changed.emit(id, lift.left)
	var title := str(marker.get_meta("name", "The lift"))
	for actor in here:
		actor.notice.emit("%s is running" % title)
	war_feed.emit("%s is running for %d minutes" % [title, roundi(world.lift_powered_for / 60.0)])


## While a lift runs, a player who stands `WorldDef.lift_wait` in one stop
## is carried to the same spot in the other, and rides again only once they
## have stepped out.
func _ride_lift(lift: Dictionary, delta: float) -> void:
	var stops: Array = lift.stops
	var wait: Dictionary = lift.wait
	var arrived: Dictionary = lift.arrived
	var seen := {}
	for k in 2:
		var stop := stops[k] as Node3D
		for actor in _players_at(stop.global_position, float(stop.get_meta("radius", 2.5))):
			var key := actor.get_instance_id()
			seen[key] = true
			if int(arrived.get(key, -1)) == k or lift.left <= 0.0:
				wait.erase(key)
				continue
			wait[key] = float(wait.get(key, 0.0)) + delta
			if float(wait[key]) < world.lift_wait:
				continue
			wait.erase(key)
			var to := stops[1 - k] as Node3D
			var off := actor.global_position - stop.global_position
			actor.global_position = to.global_position + Vector3(off.x, 0.1, off.z)
			actor.velocity = Vector3.ZERO
			arrived[key] = 1 - k
			seen[key] = true
			actor.notice.emit("The lift carries you %s" % ("down" if to.global_position.y < stop.global_position.y else "up"))
	for key: int in wait.keys():
		if not seen.has(key):
			wait.erase(key)
	for key: int in arrived.keys():
		if not seen.has(key):
			arrived.erase(key)


## Whether a bot is one of the map's guards, or a brood one spilled.
func is_guard(bot: Actor) -> bool:
	return _guards.any(func(guard: Dictionary) -> bool: return guard.bot == bot or (guard.brood as Array).has(bot))


## A dead boss comes back after `WorldDef.boss_respawn_time`.
func _tick_bosses(delta: float) -> void:
	for boss in _bosses:
		var bot: Variant = boss.bot
		if bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			continue
		if boss.back_in <= 0.0:
			boss.back_in = float((boss.marker as Node3D).get_meta("respawn", world.boss_respawn_time))
			if (boss.marker as Node3D).get_meta("keeper", false):
				_keeper_fell(boss)
			boss.bot = null
			continue
		if enemy_room() <= 0:
			continue
		boss.back_in -= delta
		if boss.back_in <= 0.0:
			boss.bot = _add_boss(boss.marker, boss)
			if (boss.marker as Node3D).get_meta("keeper", false):
				_keeper_back(boss)
			war_feed.emit(world.boss_back_news(boss.bot, _whereabouts(boss.marker.global_position)))
	for boss in _bosses:
		if (boss.marker as Node3D).get_meta("keeper", false):
			_tick_keeper(boss, delta)
	if world.boss_party_scale > 0.0:
		_boss_party_left -= delta
		if _boss_party_left <= 0.0:
			_boss_party_left = BOSS_PARTY_EVERY
			for boss in _bosses:
				if boss.bot != null and is_instance_valid(boss.bot):
					_scale_boss(boss.bot)


## A boss grows tougher with company (`WorldDef.boss_party_scale`): one
## player fights it as it is, each other player near it adds a share.
## Counted every `BOSS_PARTY_EVERY`, so a group arriving mid-fight shows.
func _scale_boss(bot: Actor) -> void:
	var near := 0
	for state in players:
		var other := state.actor
		if other == null or not is_instance_valid(other) or other.is_dead or state.finished:
			continue
		if other.global_position.distance_to(bot.global_position) <= world.boss_party_range:
			near += 1
	bot.toughness = 1.0 + world.boss_party_scale * maxi(near - 1, 0)


# --- Keepers ---------------------------------------------------------------------

## A keeper is a dungeon's last fight (DESIGN.md "The Engine's inside"): a
## boss whose "spawn_boss" marker has the meta "keeper", with the fight its
## map lays out round it ("boss_socket", "purge" and "vault" markers naming
## its kind). Every keeper starts standing; a client is told otherwise when
## it joins.
func _find_keepers() -> void:
	keepers.clear()
	for marker in _map_nodes("spawn_boss"):
		if marker.get_meta("keeper", false):
			keepers[str(marker.get_meta("boss", ""))] = 1
	purges = _map_nodes("purge")
	_sockets = _map_nodes("boss_socket")
	_vaults = _map_nodes("vault")
	_snags = _map_nodes("boss_snag")
	_pools = _map_nodes("boss_pool")
	map.set_meta("keepers", keepers.duplicate())
	if Look.enabled and map.has_method("show_purge"):
		var show := Callable(map, "show_purge")
		if not purge_changed.is_connected(show):
			purge_changed.connect(show)


## Whether a marker that waits on a keeper (one with its kind as meta
## "keeper": a deep beacon, its warmth) is still dark, its keeper standing.
func waits_on_keeper(marker: Node) -> bool:
	if not marker.has_meta("keeper"):
		return false
	return int(keepers.get(str(marker.get_meta("keeper")), 0)) != 0


## A client's copy of a keeper's phase, from `NetSession`.
func set_keeper(kind: String, phase: int) -> void:
	if not keepers.has(kind):
		return
	keepers[kind] = clampi(phase, 0, 2)
	map.set_meta("keepers", keepers.duplicate())


func _set_keeper_phase(kind: String, phase: int) -> void:
	if int(keepers.get(kind, -1)) == phase:
		return
	keepers[kind] = phase
	map.set_meta("keepers", keepers.duplicate())
	keeper_changed.emit(kind, phase)


## Everyone who hurts a keeper has helped, and gets a share of its vault.
func _on_keeper_hurt(info: DamageInfo, boss: Dictionary) -> void:
	if info.amount <= 0.0 or not info.source is Actor:
		return
	var state := state_for(info.source as Actor)
	if state != null:
		(boss.helpers as Dictionary)[state.owner] = state.actor.display_name


## The living players in a keeper's arena (its marker's meta "arena").
func _arena_players(marker: Node3D) -> Array[Actor]:
	var reach := float(marker.get_meta("arena", 30.0))
	var found: Array[Actor] = []
	for state in players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead:
			continue
		if actor.global_position.distance_to(marker.global_position) <= reach:
			found.append(actor)
	return found


## A keeper's fight, run by the authority while someone is in its arena. In
## its first phase it calls its faction out of its wall sockets, one every
## `WorldDef.keeper_socket_every`, up to `keeper_socket_max` at once and one
## more for each other player there (a squad splits between it and them).
## Below `keeper_split` of its health it turns to its purges: every
## `keeper_purge_every` the next `keeper_purges_at_once` lanes warn for
## `keeper_purge_warn` and then vent (`_tick_venting`).
func _tick_keeper(boss: Dictionary, delta: float) -> void:
	var marker := boss.marker as Node3D
	var kind := str(marker.get_meta("boss", ""))
	_tick_venting(boss, delta)
	var bot: Variant = boss.bot
	if bot == null or not is_instance_valid(bot) or (bot as Actor).is_dead:
		return
	var keeper := bot as Actor
	var near := _arena_players(marker)
	_check_snags(keeper, kind, near)
	var phase := 2 if keeper.health.health < keeper.health.max_health * world.keeper_split else 1
	if phase != int(keepers.get(kind, 1)):
		_set_keeper_phase(kind, phase)
		world.on_keeper_phase(keeper, phase)
		var news := world.keeper_news(keeper, phase)
		for actor in near:
			if news != "":
				actor.notice.emit(news)
	_tick_dive(boss, keeper, kind, near, phase, delta)
	if near.is_empty():
		boss.socket_in = world.keeper_socket_first
		boss.purge_in = world.keeper_purge_first
		return
	if phase == 1:
		boss.socket_in -= delta
		if boss.socket_in <= 0.0:
			boss.socket_in = world.keeper_socket_every
			_call_from_socket(boss, kind, near)
	else:
		boss.purge_in -= delta
		if boss.purge_in <= 0.0:
			boss.purge_in = world.keeper_purge_every
			_start_purges(boss, kind)


## A keeper in a dash-strike (`MeleeWeapon.is_dashing`) that has run into
## one of its snags, facing it, is stuck there: staggered for the snag's
## "stun" (the stagger cancels the strike and reaches clients with its
## state), and everyone in its arena is told.
func _check_snags(keeper: Actor, kind: String, near: Array[Actor]) -> void:
	var blade := keeper.get_active_weapon() as MeleeWeapon
	if blade == null or not blade.is_dashing() or keeper.stagger_left > 0.0:
		return
	var facing := keeper.get_aim_dir()
	facing.y = 0.0
	facing = facing.normalized()
	for snag in _snags:
		if str(snag.get_meta("keeper", "")) != kind:
			continue
		var to := snag.global_position - keeper.global_position
		to.y = 0.0
		var reach := float(snag.get_meta("radius", 1.0)) + Actor.BODY_RADIUS + 0.6
		if to.length() > reach or facing.dot(to.normalized()) < 0.5:
			continue
		keeper.stagger(float(snag.get_meta("stun", 3.0)))
		var news := world.keeper_snag_news(keeper)
		if news != "":
			for actor in near:
				actor.notice.emit(news)
		return


## A keeper with pools of its own dives (see `WorldDef.keeper_dive_up`):
## "up" fighting, "under" (submerged, held down by its brain) and "rising"
## at the pool nearest one of the players in its arena, still unhurtable
## until it is up. With nobody in its arena it stays up. Its state lives in
## the boss's "dive" and starts over with each new body.
func _tick_dive(boss: Dictionary, keeper: Actor, kind: String, near: Array[Actor], phase: int, delta: float) -> void:
	var pools := _pools.filter(func(pool: Node3D) -> bool: return str(pool.get_meta("keeper", "")) == kind)
	if pools.is_empty():
		return
	var brain := keeper.get_node_or_null("Brain") as BotBrain
	var dive: Dictionary = boss.get("dive", {})
	if dive.get("body", 0) != keeper.get_instance_id():
		dive = {"body": keeper.get_instance_id(), "state": "up", "left": world.keeper_dive_up}
		boss.dive = dive
	if near.is_empty():
		dive.state = "up"
		dive.left = world.keeper_dive_up
		keeper.submerged = false
		if brain != null:
			brain.held_under = false
			brain.held_still = false
		return
	dive.left = float(dive.left) - delta
	if float(dive.left) > 0.0:
		return
	match str(dive.state):
		"up":
			dive.state = "under"
			dive.left = world.keeper_dive_under
			keeper.submerged = true
			if brain != null:
				brain.held_under = true
		"under":
			# Up at the pool nearest one of them, never where it went down.
			var prey := near[rng.randi() % near.size()]
			var best: Node3D = null
			for pool: Node3D in pools:
				if pool.global_position.distance_to(keeper.global_position) < 2.0:
					continue
				if best == null or pool.global_position.distance_to(prey.global_position) \
						< best.global_position.distance_to(prey.global_position):
					best = pool
			if best != null:
				keeper.global_position = best.global_position
				keeper.velocity = Vector3.ZERO
			dive.state = "rising"
			dive.left = world.keeper_dive_rise
			dive.prey = prey
			if brain != null:
				brain.held_under = false
				brain.held_still = true
		"rising":
			dive.state = "up"
			dive.left = world.keeper_dive_up_hurt if phase == 2 else world.keeper_dive_up
			keeper.submerged = false
			if brain != null:
				brain.held_still = false
			var prey: Variant = dive.get("prey")
			if prey != null and is_instance_valid(prey):
				keeper.heard.emit((prey as Actor).global_position, prey)


## A keeper calls one of its faction out of its next wall socket, posted to
## its arena and told where the nearest player is. The grid's ring shows it.
func _call_from_socket(boss: Dictionary, kind: String, near: Array[Actor]) -> void:
	var adds: Array = boss.adds
	for k in range(adds.size() - 1, -1, -1):
		var add: Variant = adds[k]
		if add == null or not is_instance_valid(add) or (add as Actor).is_dead:
			adds.remove_at(k)
	if adds.size() >= world.keeper_socket_max + near.size() - 1 or enemy_room() <= 0:
		return
	var sockets := _sockets.filter(func(socket: Node3D) -> bool: return str(socket.get_meta("keeper", "")) == kind)
	if sockets.is_empty():
		return
	var socket := sockets[int(boss.socket_next) % sockets.size()] as Node3D
	boss.socket_next = int(boss.socket_next) + 1
	var bot := _add_bot(socket)
	adds.append(bot)
	var marker := boss.marker as Node3D
	var brain := bot.get_node_or_null("Brain") as BotBrain
	if brain != null:
		brain.post_to(marker.global_position, float(marker.get_meta("arena", 30.0)) * 0.8)
	var target := near[0]
	for actor in near:
		if actor.global_position.distance_to(socket.global_position) < target.global_position.distance_to(socket.global_position):
			target = actor
	bot.heard.emit(target.global_position, target)
	grid_called.emit(bot, target)


## The next of a keeper's purge lanes warn.
func _start_purges(boss: Dictionary, kind: String) -> void:
	var lanes: Array[int] = []
	for i in purges.size():
		if str(purges[i].get_meta("keeper", "")) == kind:
			lanes.append(i)
	if lanes.is_empty():
		return
	for k in mini(world.keeper_purges_at_once, lanes.size()):
		var index := lanes[int(boss.purge_next) % lanes.size()]
		boss.purge_next = int(boss.purge_next) + 1
		(boss.venting as Array).append({"index": index, "left": world.keeper_purge_warn, "vented": false})
		purge_changed.emit(index, 1)


## Warned lanes vent once their warning is up, then go quiet. Lanes that
## vent together hurt anyone once, however many of them they stand in.
func _tick_venting(boss: Dictionary, delta: float) -> void:
	var venting: Array = boss.venting
	if venting.is_empty():
		return
	var hit := {}
	for k in range(venting.size() - 1, -1, -1):
		var vent: Dictionary = venting[k]
		vent.left = float(vent.left) - delta
		if float(vent.left) > 0.0:
			continue
		var index := int(vent.index)
		if not vent.vented:
			vent.vented = true
			vent.left = PURGE_VENT
			_vent(purges[index], boss, hit)
			purge_changed.emit(index, 2)
		else:
			venting.remove_at(k)
			purge_changed.emit(index, 0)


## A purge lane vents: everyone standing in it (on its floor, not over it)
## takes its "damage" through `Combat.deal`, from the keeper, so the world's
## rules decide who (the keeper's own faction is spared in Frostline).
func _vent(lane: Node3D, boss: Dictionary, hit: Dictionary) -> void:
	var from := lane.global_position
	var to: Vector3 = lane.get_meta("toward", from)
	var keeper: Variant = boss.bot
	var source: Actor = keeper as Actor if keeper != null and is_instance_valid(keeper) else null
	var targets: Array = []
	for state in players:
		if not state.finished:
			targets.append(state.actor)
	targets.append_array(bots)
	for target: Variant in targets:
		if target == null or not is_instance_valid(target) or (target as Actor).is_dead or hit.has(target):
			continue
		var actor := target as Actor
		if not in_lane(actor.global_position, from, to, float(lane.get_meta("width", 4.0))):
			continue
		hit[actor] = true
		var info := DamageInfo.new()
		info.amount = float(lane.get_meta("damage", 20.0))
		info.kind = "purge"
		info.position = actor.global_position
		info.armor_pierce = 0.5
		info.source = source
		Combat.deal(actor, info)


## Whether a point stands in a lane `width` across from `from` to `to`, on
## its floor (within 2.5 m up or down).
static func in_lane(at: Vector3, from: Vector3, to: Vector3, width: float) -> bool:
	if absf(at.y - from.y) > 2.5:
		return false
	var run := Vector2(to.x - from.x, to.z - from.z)
	var off := Vector2(at.x - from.x, at.z - from.z)
	var length := run.length()
	if length < 0.01:
		return false
	var along := off.dot(run / length)
	if along < -0.5 or along > length + 0.5:
		return false
	return absf(off.cross(run / length)) <= width * 0.5 + 0.4


## A keeper fell: its deep markers light, and its vault opens a share for
## everyone who hurt it and everyone in its arena, each kept for them alone
## (`LootContainer.reserved`) until the keeper comes back.
func _keeper_fell(boss: Dictionary) -> void:
	var marker := boss.marker as Node3D
	var kind := str(marker.get_meta("boss", ""))
	_set_keeper_phase(kind, 0)
	_open_vault(boss, kind)
	boss.helpers = {}
	boss.socket_next = 0
	boss.purge_next = 0
	var news := world.keeper_news(boss.bot as Actor if boss.bot != null and is_instance_valid(boss.bot) else null, 0)
	if news != "":
		war_feed.emit(news)


func _keeper_back(boss: Dictionary) -> void:
	for share: Variant in boss.shares:
		if share != null and is_instance_valid(share):
			(share as Node).queue_free()
	boss.shares = []
	boss.helpers = {}
	_set_keeper_phase(str((boss.marker as Node3D).get_meta("boss", "")), 1)


## How far apart the vault's shares stand.
const VAULT_SPACING := 1.6


func _open_vault(boss: Dictionary, kind: String) -> void:
	var vault: Node3D = null
	for marker in _vaults:
		if str(marker.get_meta("keeper", "")) == kind:
			vault = marker
			break
	if vault == null:
		return
	var helpers: Dictionary = (boss.helpers as Dictionary).duplicate()
	for actor in _arena_players(boss.marker as Node3D):
		var state := state_for(actor)
		if state != null and not helpers.has(state.owner):
			helpers[state.owner] = actor.display_name
	var across := vault.global_transform.basis.x.normalized()
	var owners := helpers.keys()
	var shares: Array = boss.shares
	for i in owners.size():
		var owner: String = owners[i]
		var title: String = helpers[owner]
		var at := vault.global_position + across * (float(i) - (owners.size() - 1) * 0.5) * VAULT_SPACING
		var share := spawn_container(world.roll_vault(kind, rng), false, "%s's share" % title, at)
		share.reserved = owner
		share.reserved_name = title
		shares.append(share)
		for state in players:
			if state.owner == owner and not state.finished and is_instance_valid(state.actor):
				state.actor.notice.emit("The vault is open: your share waits for you there")


## The view of a grid call (view only, added where `Look` is on): a ring of
## the faction's light runs out from the bot's feet with a rising chirp, so
## whoever hurt it knows the rest are coming.
func _show_grid_call(bot: Actor, _source: Actor) -> void:
	if bot == null or not is_instance_valid(bot) or not bot.is_inside_tree():
		return
	var at := bot.global_position + Vector3(0, 0.15, 0)
	Fx.ring(self, at, GRID_CALL_RING, GRID_CALL_COLOR, 1.1, false)
	Fx.ring(self, at + Vector3(0, bot.body_height() * 0.6, 0), GRID_CALL_RING * 0.35, GRID_CALL_COLOR, 0.7, false)
	Sfx.play("grid_call", at, 2.0, 90.0)


const GRID_CALL_RING := 9.0
const GRID_CALL_COLOR := Color(0.1, 0.85, 0.8)


## A bot of a linked faction (`WorldDef.linked_factions`) was hurt and
## lived: every other one of its faction within range hears where the hit
## came from, at most once every `LINK_EVERY` for each bot hurt. A blow
## that kills calls nobody, so a clean kill stays quiet.
func _on_linked_hurt(info: DamageInfo, bot: Actor) -> void:
	var source := info.source as Actor
	if source == null or not is_instance_valid(bot) or bot.is_dead or bot.health.health <= 0.0:
		return
	if info.amount <= 0.0 or source.faction == bot.faction:
		return
	if clock < float(_link_next.get(bot, -1.0)):
		return
	_link_next[bot] = clock + LINK_EVERY
	var reach := float(world.linked_factions.get(bot.faction, 0.0))
	for other in bots:
		if other == bot or not is_instance_valid(other) or other.is_dead or other.faction != bot.faction:
			continue
		if other.global_position.distance_to(bot.global_position) <= reach:
			other.heard.emit(source.global_position, source)
	grid_called.emit(bot, source)


## Bots outside the world's own army: an event's, the core bosses and the
## rival raiders. They are never ordered about by the war, and the army
## never replaces them.
func _is_extra(bot: Actor) -> bool:
	if _event_bots.has(bot) or is_raider(bot) or is_guard(bot):
		return true
	for boss in _bosses:
		if boss.bot == bot or (boss.adds as Array).has(bot):
			return true
	return false


## Whether a bot is one of the world's rival raiders.
func is_raider(bot: Actor) -> bool:
	for entry in raiders:
		if entry.bot == bot:
			return true
	return false


## Rival raiders (`WorldDef.raider_count`): bots that play the way a player
## does. They arrive one at a time, go from cache to cache, fight whoever
## they meet (the armies, players and each other), and once their stay is
## up or their pack is full they sign out, standing still for the world's
## sign-out time; a fight starts it over. Authority only.
func _tick_raiders(delta: float) -> void:
	if world.raider_count <= 0 or world.safe_zone or not enemies:
		return
	_raider_in -= delta
	if _raider_in <= 0.0:
		_raider_in = world.raider_gap
		if raiders.size() < world.raider_count and enemy_room() > 0:
			spawn_raider()
	for entry in raiders.duplicate():
		var bot: Actor = entry.bot
		if not is_instance_valid(bot) or bot.is_dead:
			continue
		var brain := bot.get_node_or_null("Brain") as BotBrain
		if brain == null:
			continue
		var fighting := brain.state != BotBrain.State.PATROL
		if float(entry.sign_out_left) >= 0.0:
			if fighting:
				entry.sign_out_left = world.sign_out_time
				continue
			entry.sign_out_left = float(entry.sign_out_left) - delta
			if float(entry.sign_out_left) <= 0.0:
				_raider_leaves(entry)
			continue
		if clock >= float(entry.leaves_at) or bot.inventory.is_full():
			entry.sign_out_left = world.sign_out_time
			entry.cache = null
			brain.clear_errand()
			brain.holding = true
			continue
		if fighting:
			continue
		var cache: Variant = entry.cache
		if cache != null and (not is_instance_valid(cache) or (cache as LootContainer).items.is_empty()):
			cache = null
		if cache == null:
			cache = _raider_cache(entry)
			entry.cache = cache
			if cache == null:
				if brain.has_errand:
					brain.clear_errand()
			else:
				brain.go_to((cache as LootContainer).global_position)
		elif bot.global_position.distance_to((cache as LootContainer).global_position) <= raider_loot_reach:
			(cache as LootContainer).interact(bot)
			entry.visited.append(cache)
			entry.cache = null
			brain.clear_errand()


## Drops a rival raider in at a player spawn, away from the players, with a
## kit from `WorldDef.raider_kit` and a name nobody here is using. Returns
## null when there is nowhere to put one or no name left.
func spawn_raider() -> Actor:
	if mode == Mode.CLIENT:
		return null
	var spawns := _map_nodes("spawn_player")
	if spawns.is_empty():
		spawns = _map_nodes("spawn_bot")
	var callsign := _raider_name()
	if spawns.is_empty() or callsign == "":
		return null
	var marker := spawns[_farthest_from_players(spawns) if not active_players().is_empty()
			else rng.randi() % spawns.size()]
	var at := _stand(marker.global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)))
	# A side of its own: the armies, the players and the other raiders are
	# all fair game, as they are for a player.
	var bot := spawn_bot("Raider%d" % _bot_count, at, rng.randi(), false, "raider:" + callsign, -2,
			world.raider_kit(rng))
	bot.display_name = callsign
	Look.set_appearance(bot, Human.for_name(callsign))
	_bot_count += 1
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = rng.randi()
	brain.skill_range = world.raider_skill
	brain.flies = bot.flight.enabled
	brain.uses_kit = true
	bot.add_child(brain)
	bot.died.connect(_on_actor_died)
	world.on_spawn(bot)
	raiders.append({"bot": bot, "sign_out_left": -1.0, "cache": null, "visited": [],
			"leaves_at": clock + rng.randf_range(world.raider_stay.x, world.raider_stay.y)})
	war_feed.emit("%s dropped in %s" % [callsign, _whereabouts(at)])
	actor_spawned.emit(bot)
	return bot


func _raider_name() -> String:
	var taken := {}
	for actor in bots:
		if is_instance_valid(actor):
			taken[actor.display_name] = true
	for state in players:
		if is_instance_valid(state.actor):
			taken[state.actor.display_name] = true
	var free := world.raider_names().filter(func(n: String) -> bool: return not taken.has(n))
	return free[rng.randi() % free.size()] if not free.is_empty() else ""


## The cache a raider goes for next: one of the nearest it has not emptied
## that holds something, stands low enough to walk to, and no other raider
## is already heading for.
func _raider_cache(entry: Dictionary) -> LootContainer:
	var bot: Actor = entry.bot
	var claimed := raiders.map(func(other: Dictionary) -> Variant: return other.cache)
	var options: Array[LootContainer] = []
	for cache in _caches:
		var container := cache.container as LootContainer
		if not is_instance_valid(container) or container.items.is_empty() or container.is_rack() \
				or entry.visited.has(container) or claimed.has(container):
			continue
		var at := container.global_position
		var ground := float(map.call("ground_height", at.x, at.z)) if map.has_method("ground_height") else 0.0
		if at.y - ground > raider_climb:
			continue
		options.append(container)
	if options.is_empty():
		return null
	options.sort_custom(func(a: LootContainer, b: LootContainer) -> bool:
		return a.global_position.distance_squared_to(bot.global_position) \
				< b.global_position.distance_squared_to(bot.global_position))
	return options[rng.randi() % mini(3, options.size())]


## A raider's sign-out ends: it leaves with everything it carried, as a
## player would, and another takes its place in time.
func _raider_leaves(entry: Dictionary) -> void:
	var bot: Actor = entry.bot
	raiders.erase(entry)
	war_feed.emit("%s signed out with %s" % [bot.display_name, "nothing" if bot.inventory.items.is_empty()
			else "%d items" % bot.inventory.items.size()])
	_raider_in = maxf(_raider_in, world.raider_gap)
	_remove_actor(bot)


## The gate outpost a point is inside, or null.
func outpost_at(at: Vector3) -> Node3D:
	for marker in outposts:
		var flat := Vector2(at.x - marker.global_position.x, at.z - marker.global_position.z)
		if flat.length() <= float(marker.get_meta("radius", 10.0)) and absf(at.y - marker.global_position.y) < 12.0:
			return marker
	return null


## Gate outposts are safe bubbles: weapons locked and nobody can hurt you.
## Someone in a fight or carrying a bounty is turned away at the gate (put
## back outside it), so nobody ducks in to escape a fight. Walking out gives
## a moment of protection that ends as soon as you fire. Authority only:
## clients learn the lock from the state (`ActorCommand.STATE_SHELTERED`).
func _tick_outposts() -> void:
	if outposts.is_empty() or not zone_rules:
		return
	for state in players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead:
			continue
		var gate := outpost_at(actor.global_position)
		if gate != null and not state.sheltered:
			var fighting := clock - state.last_combat < world.combat_time
			if fighting or actor.bounty > 0:
				_turn_away(state, gate, "in a fight" if fighting else "carrying a bounty")
				continue
			state.sheltered = true
			state.leaving_gate = false
			actor.weapons_locked = true
			actor.notice.emit("%s: safe, weapons locked" % gate.get_meta("name", "Outpost"))
		elif gate == null and state.sheltered:
			state.sheltered = false
			state.leaving_gate = true
			actor.weapons_locked = false
			actor.protected_left = world.spawn_protection
		if state.sheltered:
			actor.protected_left = maxf(actor.protected_left, 0.5)
		elif state.leaving_gate:
			# Firing gives the protection up, hit or miss.
			if actor.protected_left <= 0.0 or actor.cmd.primary or actor.cmd.primary_pressed \
					or actor.cmd.ability_pressed or actor.cmd.artifact_pressed:
				actor.protected_left = 0.0
				state.leaving_gate = false


## Puts someone who may not shelter back outside the gate's edge.
func _turn_away(state: PlayerState, gate: Node3D, why: String) -> void:
	var actor := state.actor
	var centre := gate.global_position
	var out := Vector2(actor.global_position.x - centre.x, actor.global_position.z - centre.z)
	if out.length() < 0.1:
		out = Vector2(0, 1)
	var edge := out.normalized() * (float(gate.get_meta("radius", 10.0)) + 1.0)
	var vehicle := actor.vehicle
	if vehicle != null:
		vehicle.global_position = _stand(Vector3(centre.x + edge.x, vehicle.global_position.y, centre.z + edge.y))
	else:
		actor.global_position = _stand(Vector3(centre.x + edge.x, actor.global_position.y, centre.z + edge.y))
		actor.velocity = Vector3.ZERO
	if clock - state.refused_at > 3.0:
		actor.notice.emit("The gate stays shut while you are %s" % why)
	state.refused_at = clock


## Leaves a death burst's cloud (`WorldDef.death_burst`) at `at`. Authority
## only; everyone is told through `cloud_burst`.
func burst_cloud(at: Vector3, burst: Dictionary, faction: String) -> void:
	var cloud := {"at": at, "radius": float(burst.get("radius", 4.0)), "damage": float(burst.get("damage", 5.0)),
			"left": float(burst.get("seconds", 8.0)), "kind": str(burst.get("kind", "spores")), "faction": faction}
	clouds.append(cloud)
	cloud_burst.emit(at, cloud.radius, cloud.left, cloud.kind)


## A trail-leaving bot (the Rift's Magma Crawlers) leaves a cloud at its
## feet every "every" seconds while it walks on, never two on one spot, so
## the ground it has crossed hurts the other side for a while. Checked
## every `TRAIL_STEP` seconds over only the bots that leave one.
func _tick_trails(delta: float) -> void:
	_trail_in -= delta
	if _trail_in > 0.0:
		return
	_trail_in = TRAIL_STEP
	for body: Variant in _trails.keys():
		if not is_instance_valid(body) or (body as Actor).is_dead:
			_trails.erase(body)
			continue
		var bot := body as Actor
		var left: Dictionary = _trails[bot]
		left.wait = float(left.wait) - TRAIL_STEP
		var trail: Dictionary = bot.get_meta("trail")
		var feet := bot.global_position
		if left.wait > 0.0 or not bot.is_on_floor() or feet.distance_to(left.at) < float(trail.get("radius", 2.0)):
			continue
		left.at = feet
		left.wait = float(trail.get("every", 1.5))
		burst_cloud(feet + Vector3(0, 0.3, 0), trail, bot.faction)


## Death bursts' clouds hang a while and hurt, once a second, everyone of
## another faction inside them (players and bots alike) through
## `Combat.deal`, past armor. Authority only.
func _tick_clouds(delta: float) -> void:
	for cloud in clouds:
		cloud.left = float(cloud.left) - delta
	clouds = clouds.filter(func(c: Dictionary) -> bool: return float(c.left) > 0.0)
	_cloud_in -= delta
	if _cloud_in > 0.0:
		return
	_cloud_in = 1.0
	var hurt: Array = []
	for state in players:
		if not state.finished and is_instance_valid(state.actor):
			hurt.append(state.actor)
	hurt.append_array(bots)
	for cloud in clouds:
		var at: Vector3 = cloud.at
		var reach: float = cloud.radius
		for body: Variant in hurt:
			if not is_instance_valid(body):
				continue
			var actor := body as Actor
			if actor == null or actor.is_dead or (cloud.faction != "" and actor.faction == cloud.faction):
				continue
			var centre := actor.global_position + Vector3(0, actor.body_height() * 0.5, 0)
			if centre.distance_to(at) > reach:
				continue
			var info := DamageInfo.new()
			info.amount = float(cloud.damage)
			info.kind = str(cloud.kind)
			info.position = centre
			info.armor_pierce = 1.0
			Combat.deal(actor, info)


## A death burst's cloud, view only: a slow swell of spores that thins and
## goes as it runs out. Burning ground ("fire") is a low haze of embers.
func _show_cloud(at: Vector3, radius: float, seconds: float, kind: String) -> void:
	var color: Color = CLOUD_COLORS.get(kind, CLOUD_COLOR)
	# Burning ground (a trail) is low and quiet: it is left every step.
	var trail := kind == "fire"
	# Soft puffs hung through the cloud's ball, low ones more than high, so it
	# lies on the ground with a ragged edge (`spore_cloud.gdshader`).
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/spore_cloud.gdshader") as Shader
	mat.set_shader_parameter("tint", Color(color, CLOUD_ALPHA * (0.5 if trail else 1.0)))
	mat.set_shader_parameter("alpha", 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = mat
	var puffs := MultiMesh.new()
	puffs.transform_format = MultiMesh.TRANSFORM_3D
	puffs.use_custom_data = true
	puffs.mesh = quad
	puffs.instance_count = CLOUD_PUFFS
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(at.round()))
	for i in CLOUD_PUFFS:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.7), rng.randf_range(-1.0, 1.0))
		var spot := dir.limit_length(1.0) * radius * 0.7
		if trail:
			spot.y = absf(spot.y) * 0.25
		var size := radius * rng.randf_range(0.45, 0.75) * (0.6 if trail else 1.0)
		puffs.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), spot))
		puffs.set_instance_custom_data(i, Color(rng.randf(), radius * 0.12, 0.0, 0.0))
	var cloud := MultiMeshInstance3D.new()
	cloud.name = "Cloud"
	cloud.multimesh = puffs
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud.custom_aabb = AABB(Vector3.ONE * -radius * 1.6, Vector3.ONE * radius * 3.2)
	add_child(cloud)
	cloud.global_position = at
	cloud.scale = Vector3.ONE * 0.4
	var swell := cloud.create_tween()
	swell.tween_property(cloud, "scale", Vector3.ONE, 0.8).set_ease(Tween.EASE_OUT)
	swell.parallel().tween_property(mat, "shader_parameter/alpha", 1.0, 0.8)
	swell.tween_interval(maxf(seconds - 2.8, 0.1))
	swell.tween_property(mat, "shader_parameter/alpha", 0.0, 2.0)
	swell.tween_callback(cloud.queue_free)
	if trail:
		return
	Fx.ring(self, at, radius, color, 0.9, false)
	Sfx.play("spore_burst", at, 0.0, 50.0)


const CLOUD_COLOR := Color(0.62, 0.85, 0.3)
## A cloud's colour by its kind; spores are `CLOUD_COLOR`.
const CLOUD_COLORS := {"fire": Color(1.0, 0.42, 0.1)}
const CLOUD_ALPHA := 0.36
const CLOUD_PUFFS := 22


## Hazard ground (a molten core) drains whoever stands in it, once a second.
func _tick_hazards(delta: float) -> void:
	if not zone_rules:
		return
	_hazard_in -= delta
	if _hazard_in > 0.0:
		return
	_hazard_in = 1.0
	for state in players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead:
			continue
		var burn := world.hazard_at(actor.global_position)
		if burn <= 0.0:
			continue
		var info := DamageInfo.new()
		info.amount = burn
		info.kind = "hazard"
		info.position = actor.global_position
		info.armor_pierce = 1.0
		Combat.deal(actor, info)


## A world's lava sea (`WorldDef.molten_level`): whoever's feet are under
## it burns, player or bot, four times a second through `Combat.deal`,
## whatever the zone rules. A scan of the players and bots at that pace,
## not every tick.
func _tick_molten(delta: float) -> void:
	_molten_in -= delta
	if _molten_in > 0.0:
		return
	_molten_in = MOLTEN_EVERY
	var burning: Array[Actor] = []
	for state in players:
		if not state.finished and is_instance_valid(state.actor):
			burning.append(state.actor)
	for bot: Variant in bots:
		if is_instance_valid(bot):
			burning.append(bot)
	for actor in burning:
		if actor.is_dead or actor.global_position.y >= world.molten_level:
			continue
		var info := DamageInfo.new()
		info.amount = world.molten_damage
		info.kind = "lava"
		info.position = actor.global_position
		info.armor_pierce = 1.0
		Combat.deal(actor, info)


## Where what someone drops when they die comes to rest: on whatever is
## under them (the ground, or below them if they died in the air), and on top of the lava, never in
## it, in a world with a lava sea, so a flyer can still reach it.
func drop_spot(actor: Actor) -> Vector3:
	return drop_spot_at(actor.global_position)


## The same for something falling from `at`.
func drop_spot_at(at: Vector3) -> Vector3:
	if is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.2, 0), at - Vector3(0, 400.0, 0),
				Actor.LAYER_WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			at = hit["position"]
	if at.y < world.molten_level:
		at.y = world.molten_level
	return at


## The cold (`WorldDef.cold`): out in the open a player's body heat drains
## by `cold_at` a second, and warmth (a heater or vent, `warmth_at`) fills
## it again. Once it is gone the cold hurts, once a second, through
## `Combat.deal`, but only out in the open: in a room (`indoors_at`) it
## drains by `WorldDef.indoor_chill` of that, nothing where the room is
## heated, and a storm leaks in by the room's "leak". Authority only: the owner's game is sent the number and
## everyone else whether they shiver (`Actor.shivering`).
## The share of the cold an actor's worn frame keeps out (its "insulation"
## stat, 0 for none).
static func insulation_of(actor: Actor) -> float:
	if actor.frame_id == "":
		return 0.0
	return clampf(float(ItemDB.item_stats(actor.frame_id).get("insulation", 0.0)), 0.0, 1.0)


func _tick_cold(delta: float) -> void:
	if world.cold <= 0.0 or not zone_rules:
		return
	_cold_in -= delta
	var hurt := _cold_in <= 0.0
	if hurt:
		_cold_in = 1.0
	for state in players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead:
			continue
		var at := actor.global_position
		var room := indoors_at(at)
		var warm := warmth_at(actor)
		actor.warming = warm > 0.0
		var cold := world.cold_at(at) * (1.0 - insulation_of(actor))
		var storm := weather.cold_at(at)
		var change: float
		if room == null:
			change = warm if actor.warming else -cold * storm
		else:
			# Indoors: an unheated room still lets `indoor_chill` of the cold
			# through, a heated one (or a fire inside) none, and a storm's
			# extra bite leaks in through the doorways and broken walls by
			# the room's "leak", slowing the warming even by a heater.
			var leak := float(room.get_meta("leak", 0.0)) * maxf(storm - 1.0, 0.0)
			change = warm - cold * ((0.0 if actor.warming else world.indoor_chill) + leak)
		actor.body_heat = clampf(actor.body_heat + change * delta, 0.0, actor.max_body_heat)
		actor.shivering = actor.body_heat < actor.max_body_heat * Actor.CHILL_SHARE
		# The cold hurts only out in the open: indoors it chills, never harms.
		if hurt and actor.body_heat <= 0.0 and room == null:
			var info := DamageInfo.new()
			info.amount = world.cold_damage
			info.kind = "cold"
			info.position = actor.global_position
			info.armor_pierce = 1.0
			Combat.deal(actor, info)


## Thin ice (`WorldDef.thin_ice`). A ground vehicle heavier than the ice
## bears strains it while it stands or drives on it, cracking out loud at
## `ICE_WARNINGS`, and breaks through at `ice_break_strain`. Anything driven
## into an open hole sinks too, and anyone standing in one is in the water.
## Holes freeze over again after `ice_refreeze`. Authority only.
func _tick_ice(delta: float) -> void:
	var before := ice_holes.size()
	ice_holes = ice_holes.filter(func(hole: Array) -> bool: return clock - float(hole[1]) < world.ice_refreeze)
	if ice_holes.size() != before:
		ice_changed.emit()
	for key: Variant in _ice_strain.keys():
		if not is_instance_valid(key) or key not in vehicles:
			_ice_strain.erase(key)
	for vehicle in vehicles.duplicate():
		if not is_instance_valid(vehicle) or vehicle.hovers or not vehicle.is_on_floor():
			continue
		var at: Vector3 = vehicle.global_position
		if ice_hole_at(at) >= 0:
			_go_through_ice(vehicle, false)
			continue
		var strain: float = _ice_strain.get(vehicle, 0.0)
		var heavy: float = vehicle.weight / maxf(world.ice_holds, 0.01)
		if heavy > 1.0 and world.thin_ice_at(at):
			var was := strain
			strain += heavy * delta
			for k in ICE_WARNINGS.size():
				var mark: float = ICE_WARNINGS[k] * world.ice_break_strain
				if was < mark and strain >= mark:
					ice_cracked.emit(_on_ground(at), k + 1)
			if strain >= world.ice_break_strain:
				_go_through_ice(vehicle, true)
				continue
		else:
			strain = maxf(0.0, strain - ICE_EASE * delta)
		if strain > 0.0:
			_ice_strain[vehicle] = strain
		else:
			_ice_strain.erase(vehicle)
	for state in players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead or actor.vehicle != null:
			continue
		if ice_hole_at(actor.global_position) >= 0:
			actor.body_heat = 0.0
			actor.warming = false
			actor.shivering = true


## The open hole in the ice at a point (flat distance, near the ground), as
## an index into `ice_holes`, or -1.
func ice_hole_at(at: Vector3) -> int:
	for k in ice_holes.size():
		var hole: Vector3 = ice_holes[k][0]
		var off := at - hole
		if Vector2(off.x, off.z).length() <= ICE_HOLE_RADIUS and absf(off.y) < 1.5:
			return k
	return -1


## A vehicle breaks through the ice (`opens` a new hole where it stands) or
## drives into an open one: it sinks, and whoever rode it is in the water.
func _go_through_ice(vehicle: Node3D, opens: bool) -> void:
	var at := _on_ground(vehicle.global_position)
	var riders: Array[Actor] = []
	for actor in [vehicle.get("rider")] + vehicle.get("passengers"):
		if actor != null and is_instance_valid(actor):
			riders.append(actor)
	if opens:
		ice_holes.append([at, clock])
		ice_changed.emit()
	ice_cracked.emit(at, ICE_WARNINGS.size() + 1)
	_ice_strain.erase(vehicle)
	# Where the world is gentle about it, the watch pulls the vehicle back
	# out as a toy: onto the watch of whoever threw it, else its driver's.
	var keeper: PlayerState = null
	if world.ice_keeps_vehicle:
		for state in players:
			if vehicle in state.parked and not state.finished:
				keeper = state
		if keeper == null and not riders.is_empty():
			keeper = state_for(riders[0])
		if keeper != null and keeper.finished:
			keeper = null
	var id: String = vehicle.get("item_id")
	if keeper != null:
		keeper.parked.erase(vehicle)
	remove_vehicle(vehicle)
	if keeper != null:
		keeper.stowed.append(id)
		if is_instance_valid(keeper.actor):
			keeper.actor.notice.emit("%s went through the ice. Your watch pulled it back out" % ItemDB.item_name(id))
			watch_changed.emit(keeper.actor)
	for k in riders.size():
		var actor := riders[k]
		actor.global_position = _stand(at + Vector3(0.8 if k == 0 else -0.8, 0.0, 0.0))
		actor.velocity = Vector3.ZERO
		actor.notice.emit("Through the ice! Get out of the water")


## A point dropped onto the map's open ground, if it has any.
func _on_ground(at: Vector3) -> Vector3:
	if map != null and map.has_method("ground_height"):
		return Vector3(at.x, float(map.call("ground_height", at.x, at.z)), at.z)
	return at


## Open holes packed for the wire: x, y, z and age for each.
func pack_ice_holes() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for hole: Array in ice_holes:
		var at: Vector3 = hole[0]
		out.append_array([at.x, at.y, at.z, clock - float(hole[1])])
	return out


## Takes the open holes the authority sent (see `pack_ice_holes`).
func unpack_ice_holes(data: PackedFloat32Array) -> void:
	ice_holes.clear()
	for k in range(0, data.size() - 3, 4):
		ice_holes.append([Vector3(data[k], data[k + 1], data[k + 2]), clock - maxf(data[k + 3], 0.0)])
	ice_changed.emit()


## Lays footprints and wheel tracks down behind everyone on open ground, and
## lets old ones go. Only the authority lays them; a client is sent them.
func _tick_tracks(delta: float) -> void:
	_expire_in -= delta
	if _expire_in <= 0.0:
		_expire_in = 1.0
		tracks.expire(clock)
		# A storm that wipes tracks takes them as its thick middle passes
		# over, on every machine (a client moves its own copy of the cell).
		if world.weather_wipes_tracks and weather.strength >= 0.5:
			tracks.wipe(weather.centre, weather.radius * weather.core_share)
	if mode == Mode.CLIENT:
		return
	_track_in -= delta
	if _track_in > 0.0:
		return
	_track_in = TRACK_EVERY
	for key: Variant in _last_mark.keys():
		if not is_instance_valid(key):
			_last_mark.erase(key)
	for state in players:
		_track_foot(state.actor)
	for bot in bots:
		_track_foot(bot)
	for vehicle in vehicles:
		if is_instance_valid(vehicle) and not vehicle.hovers and not vehicle.flies and vehicle.is_on_floor():
			_track_mark(vehicle, vehicle.global_position, Tracks.Kind.TREAD, TREAD_STEP)


func _track_foot(actor: Actor) -> void:
	if not is_instance_valid(actor) or actor.is_dead or actor.vehicle != null or not actor.is_on_floor():
		return
	var last: Array = _last_mark.get(actor, [])
	var kind := Tracks.Kind.LEFT if last.is_empty() or last[1] == Tracks.Kind.RIGHT else Tracks.Kind.RIGHT
	_track_mark(actor, actor.global_position, kind, FOOT_STEP)


## A mark for `body` at `at` if it has gone `step` metres since its last one
## and stands on the open ground.
func _track_mark(body: Node3D, at: Vector3, kind: int, step: float) -> void:
	var last: Array = _last_mark.get(body, [])
	if not last.is_empty():
		var gone: Vector3 = at - last[0]
		gone.y = 0.0
		if gone.length_squared() < step * step:
			return
	if not map.has_method("ground_height"):
		return
	# Nothing is laid where the world is sheltered (inside, underground).
	if world.sheltered_at(at):
		_last_mark[body] = [at, kind]
		return
	var ground := float(map.call("ground_height", at.x, at.z))
	var low := at.y - ground
	if kind == Tracks.Kind.TREAD:
		low = 0.0 if at.y >= ground - TRACK_GROUND and at.y - ground < 3.0 else 99.0
	if absf(low) > TRACK_GROUND:
		_last_mark[body] = [at, kind]
		return
	var heading: Vector3 = (at - last[0]) if not last.is_empty() else -body.global_basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	var yaw := atan2(-heading.x, -heading.z)
	var spot := Vector3(at.x, ground, at.z)
	if kind != Tracks.Kind.TREAD:
		# Feet fall either side of the line walked.
		var side := heading.cross(Vector3.UP) * (0.13 if kind == Tracks.Kind.RIGHT else -0.13)
		spot += side
		spot.y = float(map.call("ground_height", spot.x, spot.z))
	tracks.add(spot, yaw, kind, clock)
	_last_mark[body] = [at, kind]


## Body heat a second that warmth gives back to someone where they stand: the
## warmest heater or vent in reach, or a running engine they ride or stand
## beside. 0 out in the open.
func warmth_at(actor: Actor) -> float:
	var at := actor.global_position
	var best := 0.0
	var room := indoors_at(at)
	if room != null:
		best = float(room.get_meta("heat", 0.0))
	for source in warmth:
		if waits_on_keeper(source):
			continue
		var off := at - source.global_position
		var radius := float(source.get_meta("radius", 4.0))
		if absf(off.y) < 3.0 and Vector2(off.x, off.z).length_squared() <= radius * radius:
			best = maxf(best, float(source.get_meta("warmth", 6.0)))
	if world.engine_warmth > best:
		if actor.vehicle != null:
			return world.engine_warmth
		var reach := world.engine_warmth_radius * world.engine_warmth_radius
		for vehicle in vehicles:
			if is_instance_valid(vehicle) and vehicle.call("is_occupied") \
					and vehicle.global_position.distance_squared_to(at) <= reach:
				return world.engine_warmth
	return best


## The room (a map's "indoors" marker) a point stands in, or null out in the
## open. A room is a box of the marker's meta "size" (metres, across, up,
## deep) standing on the marker and turned with it. Works on clients.
func indoors_at(at: Vector3) -> Node3D:
	for room: Variant in rooms:
		if not is_instance_valid(room):
			continue
		var size: Vector3 = room.get_meta("size", Vector3.ZERO)
		var local: Vector3 = room.global_transform.affine_inverse() * at
		if absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5 and local.y >= -0.5 and local.y <= size.y:
			return room
	return null


## The risk zone someone is in as the watch says it: the tier's name, or the
## outpost sheltering them. Works on clients (from the lock the server sent).
func zone_label(actor: Actor) -> String:
	if world == null or world.safe_zone or actor == null:
		return ""
	if actor.weapons_locked:
		var gate := outpost_at(actor.global_position)
		if gate != null:
			return "%s · safe" % gate.get_meta("name", "Outpost")
	var tier := world.zone_at(actor.global_position)
	var label := world.zone_name(tier)
	if label != "" and world.hazard_at(actor.global_position) > 0.0:
		label += " · burning"
	elif label != "" and world.updraft_at(actor.global_position) > 0.0:
		label += " · updraft"
	elif label != "" and _beacons_only() and beacon_at(actor.global_position) != null:
		label = "%s · beacon" % beacon_at(actor.global_position).get_meta("name", "Beacon")
	elif label != "" and world.cold > 0.0 and actor.warming:
		label += " · warm"
	elif label != "" and world.cold > 0.0 and indoors_at(actor.global_position) != null:
		label += " · shelter"
	if label != "" and weather.strength_at(actor.global_position) >= 0.3:
		label += " · " + world.weather_name.to_lower()
	return label


## A new bot with a brain, at a spawn marker.
## `p_boss` makes it that boss kind (an airship's weak spot) wherever it is.
func _add_bot(marker: Node3D, warlord := false, p_faction := "", p_boss := "") -> Actor:
	var at := marker.global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	var first_seed := rng.randi()
	var boss: String = p_boss if p_boss != "" else (marker.get_meta("boss", "") if warlord else "")
	var faction: String = p_faction if p_faction != "" else str(marker.get_meta("faction", ""))
	var bot := spawn_bot("Bot%d" % _bot_count, _stand(at), first_seed, warlord, faction, -2, [], boss)
	# The world may turn a rare kind away (`WorldDef.bot_allowed`): roll again,
	# from seeds made from the first, so the raid's own dice are not moved.
	for tries in BOT_REROLLS:
		if world.bot_allowed(bot, self):
			break
		bots.erase(bot)
		bot_seeds.erase(bot)
		warlords.erase(bot)
		bot.free()
		bot = spawn_bot("Bot%d" % _bot_count, _stand(at), hash([first_seed, tries]), warlord,
				faction, -2, [], boss)
	if warlord and marker.get_meta("keeper", false):
		# A keeper carries nothing: its vault pays everyone who fought it.
		bot.inventory.items.clear()
		bot.mark_carry()
	elif warlord:
		# What a warlord carries is worth the fight.
		for id in world.roll_war_loot("bot", rng, 1.0) + world.roll_war_loot("cache", rng, 1.0):
			bot.inventory.add_item(id)
		# A boss may carry an artifact, the long chase (DESIGN.md section 6).
		var relic := world.roll_artifact(rng, world.warlord_artifact_chance)
		if relic != "":
			bot.inventory.add_item(relic)
		# And sometimes an earned armor paint, the trophy of the fight.
		if world.warlord_paint != "" and rng.randf() < world.warlord_paint_chance:
			bot.inventory.add_item(world.warlord_paint)
		# And what crafting runs on (DESIGN.md section 10).
		for id in world.roll_crafting_loot(rng, world.warlord_blueprint_chance, world.warlord_upgrade_data):
			bot.inventory.add_item(id)
	_bot_count += 1
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = rng.randi()
	brain.skill_range = world.bot_skill_range(bot, warlord)
	bot.add_child(brain)
	bot.died.connect(_on_actor_died)
	if world.linked_factions.has(bot.faction):
		bot.health.damaged.connect(_on_linked_hurt.bind(bot))
	if world.grudge_factions.has(bot.faction) and mode != Mode.CLIENT:
		bot.health.damaged.connect(_on_army_hurt.bind(bot))
	world.on_spawn(bot)
	_post_bot(bot)
	actor_spawned.emit(bot)
	return bot


## Where someone spawning at `at` puts their feet. On a map with open ground
## (one that has `ground_height`) a spot nudged away from its marker is moved
## onto the ground, so nobody starts inside a slope. A spot well above the
## ground, a roof say, is left alone.
func _stand(at: Vector3) -> Vector3:
	if map == null or not map.has_method("ground_height"):
		return at
	var ground: float = map.call("ground_height", at.x, at.z)
	if absf(at.y - ground) > SPAWN_SNAP:
		return at
	return Vector3(at.x, ground + 0.15, at.z)


## The marker farthest from every player still in the world.
func _farthest_from_players(markers: Array[Node3D]) -> int:
	var best := 0
	var best_distance := -1.0
	for i in markers.size():
		var nearest := INF
		for other in active_players():
			if not other.is_dead:
				nearest = minf(nearest, markers[i].global_position.distance_to(other.global_position))
		if nearest > best_distance:
			best_distance = nearest
			best = i
	return best


## Creates a bot equipped from `equip_seed`, with no brain. A client calls this
## with the server's seed (and the faction, zone and boss kind it was sent)
## to get the same bot. A rival raider is given its
## `kit` instead (item ids, put on like a player's) and is not passed
## through `WorldDef.equip_bot`.
func spawn_bot(bot_name: String, at: Vector3, equip_seed: int, warlord := false, faction := "",
		zone := -2, kit: Array = [], boss := "") -> Actor:
	var bot := Actor.new()
	bot.name = bot_name
	if faction != "":
		bot.faction = faction
	# A core boss of the world's own kind ("spawn_boss" meta "boss").
	if boss != "":
		bot.set_meta("boss", boss)
	# The risk zone it arrived in, for `equip_bot`. A client is told it, since
	# the bot may have walked elsewhere by the time the client hears of it.
	bot.set_meta("zone", zone if zone >= -1 else world.zone_at(at))
	add_child(bot)
	bot.global_position = at
	var equip_rng := RandomNumberGenerator.new()
	equip_rng.seed = equip_seed
	if kit.is_empty():
		world.equip_bot(bot, equip_rng)
	else:
		bot.set_meta("raider_kit", kit.duplicate())
		Loadout.equip(bot, kit)
	if warlord:
		world.make_warlord(bot)
		warlords[bot] = true
	bot_seeds[bot] = equip_seed
	bots.append(bot)
	if bot.has_meta("trail"):
		_trails[bot] = {"at": Vector3.INF, "wait": 0.0}
	return bot


## Fills the map's vehicle markers with abandoned vehicles anyone can take.
func _spawn_map_vehicles() -> void:
	for marker in _map_nodes("spawn_vehicle"):
		var source: String = marker.get_meta("loot_source", "vehicle")
		_parking.append({"marker": marker, "source": source, "vehicle": _park_vehicle(marker, source),
				"empty_for": 0.0})


func _park_vehicle(marker: Node3D, source: String) -> Node3D:
	for id in world.roll_loot(source, rng):
		if ItemDB.has_tag(id, "vehicle"):
			return spawn_vehicle(id, marker.global_position + Vector3(0, 0.3, 0), marker.rotation.y)
	return null


## `unpacking` is for a thrown toy: the vehicle grows from toy size.
func spawn_vehicle(id: String, at: Vector3, heading: float, unpacking := false) -> Node3D:
	var vehicle := VehicleScript.new()
	vehicle.name = "Vehicle%d" % vehicles.size()
	vehicle.setup(id)
	vehicle.rotation.y = heading
	add_child(vehicle)
	vehicle.global_position = at
	if unpacking:
		vehicle.unpack()
	vehicles.append(vehicle)
	vehicle.mounted.connect(_on_vehicle_mounted.bind(vehicle))
	vehicle_spawned.emit(vehicle)
	return vehicle


## Each vehicle a player gets on counts once a life toward contracts.
func _on_vehicle_mounted(actor: Actor, vehicle: Node3D) -> void:
	var state := state_for(actor)
	if state == null or vehicle.get_instance_id() in state.ridden:
		return
	state.ridden.append(vehicle.get_instance_id())
	_count(state, "rides")


## The toy vehicles on a player's watch, as item ids.
func stowed_for(actor: Actor) -> Array[String]:
	var state := state_for(actor)
	return state.stowed if state != null else ([] as Array[String])


## Seconds until a player can throw a toy again, or 0.
func toy_wait(actor: Actor) -> float:
	var state := state_for(actor)
	return maxf(0.0, state.toy_ready_at - clock) if state != null else 0.0


## Throws the toy `item_id` off a player's watch, from their hand along their
## aim. It unpacks into the vehicle where it lands (see `_tick_toys`).
## Returns "" if it left the hand, or why it did not (also sent as a notice).
func throw_toy(actor: Actor, item_id: String) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	var why := ""
	if item_id not in state.stowed:
		why = "That is not on your watch"
	elif not world.vehicle_toys:
		why = "Vehicles stay on the watch here"
	elif actor.vehicle != null:
		why = "Get off first"
	elif state.sign_out_left >= 0.0:
		why = "Not while signing out"
	elif toy_wait(actor) > 0.0:
		why = "Watch recharging: %d s" % ceili(toy_wait(actor))
	if why != "":
		actor.notice.emit(why)
		return why
	state.stowed.erase(item_id)
	state.toy_ready_at = clock + toy_recharge(item_id)
	# The arm draws back and comes through; the toy flies at the release.
	actor.toy_in_hand = item_id
	actor.toy_throws += 1
	toys.append({"state": state, "id": item_id, "windup": maxf(toy_windup, 0.0), "node": null})
	toy_hand_changed.emit(actor)
	watch_changed.emit(actor)
	if toy_windup <= 0.0:
		_tick_toys(0.0)
	return ""


## Takes the toy `item_id` off a player's watch into their hand to throw, or
## puts it back with "". Only the look: the toy stays on the watch until it
## is thrown. Returns "" if it is in hand (or put back), or why not.
func hold_toy(actor: Actor, item_id: String) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	if _throwing(state):
		return "Throwing"
	var why := ""
	if item_id != "" and item_id not in state.stowed:
		why = "That is not on your watch"
	elif item_id != "" and actor.vehicle != null:
		why = "Get off first"
	if why != "":
		item_id = ""
	if actor.toy_in_hand != item_id:
		actor.toy_in_hand = item_id
		toy_hand_changed.emit(actor)
	return why


## True while a player's throw is winding up.
func _throwing(state: PlayerState) -> bool:
	for toy in toys:
		if toy.state == state and toy.get("windup", 0.0) > 0.0:
			return true
	return false


## The thrown toy leaves the hand: it flies from in front of the thrower's
## eyes along their aim as it is now.
func _release_toy(toy: Dictionary) -> void:
	var state: PlayerState = toy.state
	var actor := state.actor
	toy.erase("windup")
	if state.finished or not is_instance_valid(actor) or actor.is_dead or actor.vehicle != null:
		# Knocked out of the throw: the toy jumps back onto the watch.
		toys.erase(toy)
		if is_instance_valid(actor):
			actor.toy_in_hand = ""
			toy_hand_changed.emit(actor)
		if not state.finished and is_instance_valid(actor) and not actor.is_dead:
			state.stowed.append(toy.id)
			state.toy_ready_at = clock
			watch_changed.emit(actor)
		return
	var aim := actor.get_aim_dir()
	var from := actor.get_eye_position() + aim * 0.6 - Vector3(0.0, 0.25, 0.0)
	var toy_velocity := (aim + Vector3.UP * toy_lift).normalized() * toy_speed \
			+ Vector3(actor.velocity.x, 0.0, actor.velocity.z)
	toys.erase(toy)
	fly_toy(toy.id, from, toy_velocity, actor.cmd.yaw, state)
	actor.toy_in_hand = ""
	toy_hand_changed.emit(actor)
	toy_thrown.emit(actor, toy.id, from, toy_velocity)


## Seconds until a player's watch can materialize a weapon again, or 0.
func summon_wait(actor: Actor) -> float:
	var state := state_for(actor)
	return maxf(0.0, state.summon_ready_at - clock) if state != null else 0.0


## That wait as a share from 0 (just summoned) to 1 (ready).
func summon_charge(actor: Actor) -> float:
	var state := state_for(actor)
	if state == null or state.summon_wait_total <= 0.0:
		return 1.0
	return clampf(1.0 - summon_wait(actor) / state.summon_wait_total, 0.0, 1.0)


## The watch's summon: materializes weapon `item_id` out of a player's pack
## into their hand, and the weapon it replaces goes into the pack in its
## place, with the rounds it had. Only what is carried can be summoned,
## never the stash, so everything summonable is still what a death drops.
## It takes `Loadout.summon_time` to materialize (heavier is slower; the
## weapon cannot be used until then) and the watch then waits
## `Loadout.summon_cooldown`. Returns "" if it was summoned, or why not
## (also sent as a notice).
func summon(actor: Actor, item_id: String) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	# A helmet, armor frame, flight rig or ability chip from the pack is put
	# on (`swap_worn`).
	if Loadout.wearable_from_pack(item_id) and not Loadout.summonable(item_id):
		return swap_worn(actor, item_id)
	var why := ""
	if not actor.inventory.has_item(item_id):
		why = "That is not in your pack"
	elif not Loadout.summonable(item_id):
		why = "The watch cannot summon that"
	elif actor.stagger_left > 0.0:
		why = "Not while staggered"
	elif state.sign_out_left >= 0.0:
		why = "Not while signing out"
	elif summon_wait(actor) > 0.0:
		why = "Watch recharging: %d s" % ceili(summon_wait(actor))
	if why != "":
		actor.notice.emit(why)
		return why
	var rounds: Array = actor.stowed_rounds.get(item_id, [-1, -1])
	actor.stowed_rounds.erase(item_id)
	actor.inventory.remove_item(item_id)
	var given := Loadout.swap_weapon(actor, item_id, int(rounds[0]), int(rounds[1]))
	var old: String = given.id
	if old != "":
		# One out, one in: the pack is no fuller than it was.
		actor.inventory.add_item(old)
		if int(given.mag) >= 0:
			actor.stowed_rounds[old] = [given.mag, given.reserve]
		var at := state.kit.find(old)
		if at >= 0:
			state.kit[at] = item_id
	if old == "" or item_id not in state.kit:
		state.kit.append(item_id)
	state.summon_wait_total = Loadout.summon_cooldown(item_id)
	state.summon_ready_at = clock + state.summon_wait_total
	if dev_cheats.get("cooldowns", false):  # DEV MODE
		state.summon_ready_at = clock
	watch_changed.emit(actor)
	return ""


## The watch's store, the summon in reverse: the weapon in a player's hand
## dematerializes back into their pack, with the rounds it had, leaving its
## slot empty. It takes `Loadout.store_time`, during which it cannot be used,
## and the hands are empty after. Storing does not rest the watch. Returns ""
## if it is being stored, or why not (also sent as a notice).
func store(actor: Actor, item_id: String) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	var held := actor.get_active_weapon()
	var why := ""
	if held == null or held.item_id != item_id:
		why = "Hold the weapon to store it"
	elif not Loadout.summonable(item_id):
		why = "The watch cannot store that"
	elif actor.storing_weapon() != null or actor.materialize_left > 0.0:
		why = "The watch is busy"
	elif actor.stagger_left > 0.0:
		why = "Not while staggered"
	elif state.sign_out_left >= 0.0:
		why = "Not while signing out"
	elif actor.inventory.is_full():
		why = "Your pack is full"
	if why != "":
		actor.notice.emit(why)
		return why
	var given := Loadout.store_weapon(actor, item_id)
	if given.id == "":
		return "not now"
	actor.inventory.add_item(item_id)
	if int(given.mag) >= 0:
		actor.stowed_rounds[item_id] = [given.mag, given.reserve]
	state.kit.erase(item_id)
	watch_changed.emit(actor)
	return ""


## The pack list's drop (Caleb's call: a way to be rid of what you do not
## want): `item_id` leaves the player's pack and lies at their feet in a
## bag anyone may loot, like a dead player's, cleared after
## `WorldDef.bag_lifetime`. Drops made close together go in the same bag
## (`drop_bag_reach`). A gun put away with rounds keeps them in the bag
## (`LootContainer.ammo`), so dropping and taking it back never refills it.
## Refused in a safe zone and where nothing is at stake
## (`WorldDef.gear_at_risk`), where it would only pass gear between players.
## Returns "" if it was dropped, or why not (also sent as a notice).
## Authority only; online it arrives through `NetSession.drop`.
func drop_item(actor: Actor, item_id: String) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	var why := ""
	if world.safe_zone or not world.gear_at_risk:
		why = "Nothing can be dropped here"
	elif item_id == "" or item_id not in actor.inventory.items:
		why = "That is not in your pack"
	if why != "":
		actor.notice.emit(why)
		return why
	actor.inventory.remove_item(item_id)
	var rounds: Array = []
	if actor.stowed_rounds.has(item_id) and item_id not in actor.inventory.items:
		rounds = actor.stowed_rounds[item_id]
		actor.stowed_rounds.erase(item_id)
	var at := _drop_ground(actor.global_position)
	var bag := state.drop_bag
	if bag != null and (not is_instance_valid(bag) or bag.is_queued_for_deletion() \
			or bag.global_position.distance_to(at) > drop_bag_reach):
		bag = null
	if bag == null:
		bag = LootContainer.new()
		if not rounds.is_empty():
			bag.ammo[item_id] = [rounds]
		bag = spawn_container([item_id], true, "%s's drop" % actor.display_name, at, -1, 0, bag)
		state.drop_bag = bag
		get_tree().create_timer(world.bag_lifetime, false, true).timeout.connect(bag.queue_free)
	else:
		if not rounds.is_empty():
			if not bag.ammo.has(item_id):
				bag.ammo[item_id] = []
			bag.ammo[item_id].append(rounds)
		var held := bag.items.duplicate()
		held.append(item_id)
		bag.set_items(held)
		bag.changed.emit()
	actor.notice.emit("Dropped %s" % ItemDB.item_name(item_id))
	watch_changed.emit(actor)
	return ""


## The ground under `at` (within 40 m), or `at` itself over nothing, so a
## drop made in the air lands instead of hanging there.
func _drop_ground(at: Vector3) -> Vector3:
	if not is_inside_tree():
		return at
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 40.0, Actor.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else at


## The watch's squad ping: marks the spot a player is looking at for their
## side for `ping_time` seconds. Returns "" if it went out, or why not.
func ping(actor: Actor) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	if clock < state.ping_ready_at:
		return "Ping recharging"
	var from := actor.get_eye_position()
	var to := from + actor.get_aim_dir() * ping_range
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		actor.notice.emit("Nothing there to ping")
		return "Nothing there to ping"
	state.ping_ready_at = clock + ping_cooldown
	pinged.emit(actor, hit.position)
	return ""


## Puts the player with this owner key in a squad (a clan, online): who may
## walk through a squad portal they open. "" puts them back on their own.
## Unlike a team (`set_team`) it changes no side, so it holds in safe zones.
## Whoever owns the accounts calls this; the `Raid` never asks about clans.
func set_squad(owner: String, squad: String) -> void:
	if owner == "":
		return
	if squad == "":
		squads.erase(owner)
	else:
		squads[owner] = "squad:" + squad


## The key a squad portal checks: the player's squad if they have one, else
## their side (`side_of`), so allies in a world are a squad too.
func squad_of(actor: Actor) -> String:
	var state := state_for(actor)
	if state != null and squads.has(state.owner):
		return squads[state.owner]
	return side_of(actor)[0]


## Whether `actor` may open a squad portal to `destination` where they are
## (`Portal.choices_for`): in a safe zone to a world, the arena or home, so a
## portal there is a way out to a fight; in a world where gear is at stake
## home, another world, the arena or the plaza, where opening it is a
## sign-out (`open_portal`).
func may_open_portal(actor: Actor, destination := "") -> bool:
	if world == null or actor == null or not is_instance_valid(actor) or actor.is_dead:
		return false
	return destination in Portal.choices_for(self, actor)


## The watch's squad portal: opens a portal to `destination` (a
## `Portal.choices_for` id) in front of `actor`, for their side to walk
## through for `Portal.open_time`. Their last one folds away. Authority
## only. Returns "" if it opened, or why not.
##
## Out in a world where gear is at stake every portal is a sign-out (Caleb's
## call), wherever it leads: it starts the opener's sign-out
## (`begin_sign_out`, so a fight or a bounty still refuses it, and it takes
## the sign-out's own time: the gate's in an outpost, else the ground's or
## the air's) and the ring unfolds over that countdown (`_tick_portals`
## keeps it in step, and folds it away if the sign-out is cancelled). Each
## squadmate who steps in starts their own, through the same door. Everyone
## leaves the usual way, with outcome "left" (everything carried goes home)
## and the result's "door" saying where the portal led, when their own
## countdown ends; whoever keeps the stash then sends them on from home
## (`Main`). The ring never sends anyone anywhere.
func open_portal(actor: Actor, destination: String) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished:
		return "not now"
	if not may_open_portal(actor, destination):
		if Portal.choices_for(self, actor).is_empty():
			return "No portal opens here"
		if destination == world.id:
			return "You are already here"
		return "No portal goes there"
	if clock < state.portal_ready_at:
		return "Portal recharging"
	var signing := not world.safe_zone
	if signing:
		if state.sign_out_left >= 0.0:
			return "You are already signing out"
		if not begin_sign_out(actor):
			return "You cannot sign out now"
		state.sign_out_door = destination
	state.portal_ready_at = clock + portal_cooldown
	for old in portals.duplicate():
		if old.opener == state.owner:
			close_portal(old)
	var portal := Portal.new()
	portal.name = "Portal%d" % actor.get_instance_id()
	portal.destination = destination
	portal.side = squad_of(actor)
	portal.opener = state.owner
	portal.opener_name = actor.display_name
	if signing:
		# It opens as the sign-out ends.
		portal.set_unfold(state.sign_out_total)
		portal.signs_out = true
	add_child(portal)
	portal.global_transform = Portal.spot(get_world_3d().direct_space_state, actor.get_eye_position(),
			actor.get_aim_dir(), actor.global_position.y, portal.distance, portal.wall_gap)
	portals.append(portal)
	portal_opened.emit(portal)
	return ""


## Shows a portal the server opened, on a client. `p_usable` is whether
## the local player's side may walk through it.
## `p_unfold` is how long it takes to unfold (a sign-out's countdown for a
## portal out of a world), below zero for the usual.
func show_portal(destination: String, at: Transform3D, p_usable: bool, p_age := 0.0, p_name := "",
		p_unfold := -1.0) -> Portal:
	var portal := Portal.new()
	portal.destination = destination
	portal.usable = p_usable
	portal.age = p_age
	portal.opener_name = p_name
	if p_unfold > 0.0:
		portal.set_unfold(p_unfold)
		portal.signs_out = not world.safe_zone
	add_child(portal)
	portal.global_transform = at
	portals.append(portal)
	return portal


func close_portal(portal: Portal) -> void:
	portals.erase(portal)
	if mode != Mode.CLIENT:
		portal_closed.emit(portal)
	if is_instance_valid(portal):
		portal.queue_free()


## Ages the open portals and folds away the ones whose time is up. On the
## authority, anyone of the opener's side who walks into one is sent
## through (`portal_entered`), once. A portal out of a world follows
## its opener's sign-out: it unfolds as the countdown runs (longer in the
## air) and folds away if the sign-out is cancelled.
func _tick_portals(delta: float) -> void:
	for portal in portals.duplicate():
		if not is_instance_valid(portal):
			portals.erase(portal)
			continue
		portal.tick(delta)
		if mode != Mode.CLIENT and portal.signs_out and not _keep_sign_out_portal(portal):
			close_portal(portal)
			continue
		if not portal.is_open():
			close_portal(portal)
			continue
		if mode == Mode.CLIENT:
			continue
		for state in players:
			var actor := state.actor
			if state.finished or not is_instance_valid(actor) or actor.is_dead or actor in portal.sent:
				continue
			if portal.side != "" and squad_of(actor) != portal.side:
				continue
			if not portal.contains(actor.global_position):
				continue
			if portal.signs_out:
				# Stepping into a portal out of a world starts your own
				# sign-out, through the same door.
				if state.sign_out_left < 0.0 and begin_sign_out(actor):
					state.sign_out_door = portal.destination
					portal.sent.append(actor)
				continue
			portal.sent.append(actor)
			portal_entered.emit(actor, portal.destination)


## Keeps a portal out of a world in step with its opener's sign-out. False once the
## sign-out was cancelled (a fight, or they called it off) or they went down
## before it ended: then the ring folds away. Once they are through it stays
## open its time for the squad.
func _keep_sign_out_portal(portal: Portal) -> bool:
	for state in players:
		if state.owner != portal.opener:
			continue
		if state.finished:
			# Through, or down: down takes the ring with them.
			return not is_instance_valid(state.actor) or not state.actor.is_dead
		if state.sign_out_left < 0.0:
			return false
		if state.sign_out_total > 0.0:
			portal.set_unfold(state.sign_out_total)
			portal.age = clampf(state.sign_out_total - state.sign_out_left, 0.0, portal.unfold_time)
		return true
	return true


## Seconds the watch waits after the vehicle `item_id` is thrown.
func toy_recharge(item_id: String) -> float:
	return float(ItemDB.item_stats(item_id).get("watch_recharge", toy_cooldown))


## Puts a toy in the air. With no `state` it is only for show (a client
## drawing a throw the server told it about) and lands without unpacking.
func fly_toy(item_id: String, from: Vector3, toy_velocity: Vector3, heading := 0.0,
		state: PlayerState = null) -> void:
	var node := VehicleScript.toy_model(item_id)
	add_child(node)
	node.global_position = from
	node.basis = VehicleScript.toy_flight_basis(heading, 0.0).scaled(node.scale)
	toys.append({"state": state, "id": item_id, "at": from, "velocity": toy_velocity, "age": 0.0,
			"heading": heading, "node": node})


## Flies every thrown toy along its arc. It bounces off walls, and where it
## comes down on ground a vehicle could stand on, it unpacks.
func _tick_toys(delta: float) -> void:
	if toys.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for toy in toys.duplicate():
		if toy.has("windup"):
			toy.windup -= delta
			if toy.windup <= 0.0:
				_release_toy(toy)
			continue
		toy.age += delta
		var toy_velocity: Vector3 = toy.velocity
		toy_velocity.y -= toy_gravity * delta
		var at: Vector3 = toy.at
		var next := at + toy_velocity * delta
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, next, Actor.LAYER_WORLD))
		var landed := false
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			next = hit.position + normal * 0.05
			if normal.y > 0.7:
				landed = true
			else:
				toy_velocity = toy_velocity.bounce(normal) * toy_bounce
		toy.at = next
		toy.velocity = toy_velocity
		var node: Node3D = toy.node
		node.global_position = next
		# One flip, then level and facing the way it unpacks.
		node.basis = VehicleScript.toy_flight_basis(toy.heading, toy.age).scaled(Vector3.ONE * VehicleScript.TOY_SCALE)
		if landed or toy.age >= toy_max_flight or next.y < world.void_y:
			toys.erase(toy)
			node.queue_free()
			if toy.state != null:
				_land_toy(toy, landed)


func _land_toy(toy: Dictionary, on_ground: bool) -> void:
	var state: PlayerState = toy.state
	# The thrower may be gone by now. The toy lands all the same.
	var actor: Actor = state.actor if is_instance_valid(state.actor) else null
	var id: String = toy.id
	var at: Vector3 = toy.at
	if on_ground and has_room_to_unpack(at, toy.heading, ItemDB.item_stats(id).get("footprint", unpack_room)):
		var vehicle := spawn_vehicle(id, at + Vector3(0.0, 0.25, 0.0), toy.heading, true)
		state.parked.append(vehicle)
		toy_landed.emit(actor, id, at, true)
		return
	# No room: the toy snaps back to the wrist, and can be thrown again at once.
	if not state.finished and actor != null and not actor.is_dead:
		state.stowed.append(id)
		state.toy_ready_at = clock
		actor.notice.emit("No room there. %s is back on your watch" % ItemDB.item_name(id))
		watch_changed.emit(actor)
	toy_landed.emit(actor, id, at, false)


## True if a vehicle facing `heading` fits on the ground at `at` without
## touching the map, a person or another vehicle.
func has_room_to_unpack(at: Vector3, heading: float, room := Vector3.ZERO) -> bool:
	return room_to_unpack(get_world_3d().direct_space_state, at, heading, room if room != Vector3.ZERO else unpack_room)


## The same test in any space (the home base has one too, and no raid).
static func room_to_unpack(space: PhysicsDirectSpaceState3D, at: Vector3, heading: float, room: Vector3) -> bool:
	var box := BoxShape3D.new()
	box.size = room
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	# Lifted clear of the ground it stands on, so a slope does not count.
	query.transform = Transform3D(Basis(Vector3.UP, heading), at + Vector3(0.0, room.y * 0.5 + 0.45, 0.0))
	query.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ACTORS | VehicleScript.LAYER_VEHICLES
	return space.intersect_shape(query, 1).is_empty()


## Packs the vehicle a player is looking at (within reach, nobody on it) back
## into a toy on their watch. Any vehicle will do: one found in the field
## goes home with them like anything else they carry.
## Returns "" if it was packed, or why not (also sent as a notice).
func pack_vehicle(actor: Actor) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	var seat := actor.find_interactable() if actor.vehicle == null else null
	var vehicle: Node3D = seat.get("vehicle") if seat != null and seat.get("vehicle") is Node3D else null
	var why := ""
	if vehicle == null or vehicle not in vehicles:
		why = "Look at a vehicle to pack it"
	elif vehicle.call("is_occupied") or float(vehicle.get("unpack_left")) > 0.0:
		why = "Someone is riding it"
	elif state.stowed.size() >= watch_capacity:
		why = "Your watch is full"
	elif _has_cargo(vehicle):
		why = "Unload its cargo first"
	if why != "":
		actor.notice.emit(why)
		return why
	var id: String = vehicle.get("item_id")
	state.parked.erase(vehicle)
	remove_vehicle(vehicle)
	state.stowed.append(id)
	actor.notice.emit("Packed %s onto your watch" % ItemDB.item_name(id))
	watch_changed.emit(actor)
	return ""


## Puts on helmet, armor frame, flight rig or ability chip `item_id` out of
## a player's pack (the watch's pack list or summon carousel, through
## `summon`), and the one worn goes into the pack in its place (a frame with
## the armor it had left). Authority only; returns why not, or "" when done.
## What is worn is gear and drops on death, and what is in the pack drops as
## loot. Each goes on at once and then the watch rests, like after a weapon:
## briefly for a helmet or chip, longer for a rig or frame, so spare plates
## are no instant refill. A rig takes over the old one's heat and a chip
## starts on its cooldown (`Loadout.wear_rig`, `wear_ability`), and a rig is
## only changed on the ground.
func swap_worn(actor: Actor, item_id: String) -> String:
	var state := state_for(actor)
	if mode == Mode.CLIENT or state == null or state.finished or actor.is_dead:
		return "not now"
	var helmet := ItemDB.has_tag(item_id, "helmet")
	var rig := ItemDB.has_tag(item_id, "flight_rig")
	var chip := ItemDB.has_tag(item_id, "ability")
	var why := ""
	if not Loadout.wearable_from_pack(item_id) or Loadout.summonable(item_id) \
			or not actor.inventory.has_item(item_id):
		why = "That is not in your pack"
	elif rig and (actor.airborne_time > 0.15 or actor.vehicle != null):
		why = "Land first"
	elif state.sign_out_left >= 0.0:
		why = "Not while signing out"
	elif summon_wait(actor) > 0.0:
		why = "Watch recharging: %d s" % ceili(summon_wait(actor))
	if why != "":
		actor.notice.emit(why)
		return why
	actor.inventory.remove_item(item_id)
	var worn := ""
	if helmet:
		worn = actor.visor.item_id if actor.visor.enabled else ""
		Loadout.wear_helmet(actor, item_id)
	elif rig:
		worn = actor.flight.item_id if actor.flight.enabled else ""
		Loadout.wear_rig(actor, item_id)
	elif chip:
		worn = actor.ability.item_id if actor.ability.enabled else ""
		Loadout.wear_ability(actor, item_id)
	else:
		worn = actor.frame_id
		var left := Loadout.wear_frame(actor, item_id, float(actor.stowed_armor.get(item_id, -1.0)))
		actor.stowed_armor.erase(item_id)
		if worn != "":
			actor.stowed_armor[worn] = left
	# Either goes on at once, and then the watch rests like after any summon:
	# a helmet's rest is short (`Loadout.SUMMON_TIMES` "helmet"), a frame's
	# long, so neither can be swapped back and forth in a fight.
	state.summon_wait_total = Loadout.summon_cooldown(item_id)
	state.summon_ready_at = clock + state.summon_wait_total
	if dev_cheats.get("cooldowns", false):  # DEV MODE
		state.summon_ready_at = clock
	if worn != "":
		# One out, one in: the pack is no fuller than it was.
		actor.inventory.add_item(worn)
	var at := state.kit.find(worn) if worn != "" else -1
	if at >= 0:
		state.kit[at] = item_id
	else:
		state.kit.append(item_id)
	actor.notice.emit("Put on %s" % ItemDB.item_name(item_id))
	watch_changed.emit(actor)
	return ""


## Takes a vehicle out of the world, putting its rider on their feet.
func remove_vehicle(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle):
		return
	spill_cargo(vehicle)
	vehicle.call("dismount_all")
	vehicles.erase(vehicle)
	_idle.erase(vehicle)
	vehicle_removed.emit(vehicle)
	vehicle.queue_free()


# --- Salvage crates (DESIGN.md "The Dune Sea") ------------------------------

## Places a salvage crate holding `items` standing at `at`. Everywhere: a
## client builds the ones the server tells it of (`NetSession`).
func spawn_crate(items: Array, at: Vector3) -> SalvageCrate:
	var crate := SalvageCrate.new()
	crate.items.assign(items)
	add_child(crate)
	crate.global_position = at
	crates.append(crate)
	crate.tree_exiting.connect(func() -> void:
		crates.erase(crate)
		_crate_idle.erase(crate))
	crate_spawned.emit(crate)
	return crate


## Authority: a crate on every "spawn_crate" marker, filled from the
## world's "crate" loot (`WorldDef.roll_loot`, or the marker's
## "loot_source").
func _spawn_crates() -> void:
	for marker in _map_nodes("spawn_crate"):
		var field := _field_index_at(marker.global_position)
		var crate: SalvageCrate = null if field >= 0 and is_field_buried(field) else _crate_at(marker)
		_crate_spots.append({"marker": marker, "crate": crate, "empty_for": 0.0, "field": field})


func _crate_at(marker: Node3D) -> SalvageCrate:
	var items := world.roll_loot(str(marker.get_meta("loot_source", "crate")), rng)
	return spawn_crate(items, marker.global_position + Vector3(0, SalvageCrate.SIZE.y * 0.5, 0))


## Authority: a marker whose crate has gone (banked, or carried off) gets a
## new one after `WorldDef.crate_respawn_time`; a crate left lying away from
## any marker, nobody holding it, is cleared after `WorldDef.crate_lifetime`,
## as a bag is, so a world that never ends does not fill up with them.
func _tick_crates(delta: float) -> void:
	if mode == Mode.CLIENT:
		return
	for spot: Dictionary in _crate_spots:
		var crate: Variant = spot.crate
		var marker: Node3D = spot.marker
		if int(spot.field) >= 0 and is_field_buried(int(spot.field)):
			spot.empty_for = 0.0
			continue
		if crate != null and is_instance_valid(crate) and (crate as SalvageCrate).holder == null \
				and (crate as SalvageCrate).global_position.distance_to(marker.global_position) < 3.0:
			spot.empty_for = 0.0
			continue
		spot.empty_for = float(spot.empty_for) + delta
		if spot.empty_for >= world.crate_respawn_time:
			spot.empty_for = 0.0
			spot.crate = _crate_at(marker)
	for crate in crates.duplicate():
		if crate.holder != null or _is_crate_home(crate):
			_crate_idle.erase(crate)
			continue
		_crate_idle[crate] = float(_crate_idle.get(crate, 0.0)) + delta
		if _crate_idle[crate] >= world.crate_lifetime:
			crate.queue_free()


func _is_crate_home(crate: SalvageCrate) -> bool:
	for spot: Dictionary in _crate_spots:
		if spot.crate == crate:
			return true
	return false


## Authority: `actor` lifts `crate` into both hands, off the ground or out
## of a vehicle's cargo. Returns "" if they did, or why not (a notice too).
func lift_crate(actor: Actor, crate: SalvageCrate) -> String:
	var why := ""
	if mode == Mode.CLIENT or actor == null or actor.is_dead or not is_instance_valid(crate):
		why = "not now"
	elif actor.vehicle != null:
		why = "Get off to lift it"
	elif actor.crate != null:
		why = "Your hands are full"
	elif crate.holder is Actor:
		why = "Someone is carrying it"
	if why != "":
		if why != "not now":
			actor.notice.emit(why)
		return why
	_take_from_cargo(crate)
	actor.crate = crate
	crate.place(actor)
	actor.notice.emit("Lifted a salvage crate: load it into a vehicle, or bring it to a depot")
	return ""


## Authority: `actor` puts down the crate in their hands: into the cargo of
## the vehicle `target` belongs to when it has room, else on the ground in
## front of them. Returns "" if it went into a vehicle, or where it went.
func set_down_crate(actor: Actor, target: Interactable = null) -> String:
	if mode == Mode.CLIENT or actor == null or actor.crate == null:
		return "not now"
	var crate := actor.crate
	var vehicle: Node3D = target.get("vehicle") if target != null and target.get("vehicle") is Node3D else null
	if vehicle != null and vehicle in vehicles:
		var free := (vehicle.get("cargo") as Array).find(null)
		if free >= 0:
			actor.crate = null
			(vehicle.get("cargo") as Array)[free] = crate
			crate.place(vehicle, free)
			actor.notice.emit("Loaded a salvage crate (%d of %d)" % [_cargo_count(vehicle),
					(vehicle.get("cargo") as Array).size()])
			return ""
		actor.notice.emit("No room in its cargo" if not (vehicle.get("cargo") as Array).is_empty()
				else "It has no room for cargo")
		return "full"
	var ahead := Basis(Vector3.UP, actor.cmd.yaw) * Vector3(0, 0, -1.0)
	drop_crate(crate, actor.global_position + ahead)
	return "down"


## Authority: puts `crate` down on the ground at `at` (its holder lets go).
func drop_crate(crate: SalvageCrate, at: Vector3) -> void:
	if not is_instance_valid(crate):
		return
	if crate.holder is Actor and (crate.holder as Actor).crate == crate:
		(crate.holder as Actor).crate = null
	_take_from_cargo(crate)
	crate.global_transform = Transform3D(Basis.IDENTITY, _ground_below(at) + Vector3(0, SalvageCrate.SIZE.y * 0.5, 0))
	crate.place(null)


## Authority: every crate in `vehicle`'s cargo falls off round it.
func spill_cargo(vehicle: Node3D) -> void:
	if mode == Mode.CLIENT or not is_instance_valid(vehicle):
		return
	var cargo: Array = vehicle.get("cargo") if vehicle.get("cargo") is Array else []
	var i := 0
	for crate: Variant in cargo.duplicate():
		if crate != null and is_instance_valid(crate):
			var side := Basis(Vector3.UP, vehicle.rotation.y) * Vector3(1.8 if i % 2 == 0 else -1.8, 0, float(i / 2) * 1.2 - 0.6)
			drop_crate(crate, vehicle.global_position + side)
			i += 1


func _has_cargo(vehicle: Node3D) -> bool:
	return _cargo_count(vehicle) > 0


func _cargo_count(vehicle: Node3D) -> int:
	var count := 0
	for crate: Variant in vehicle.get("cargo") if vehicle.get("cargo") is Array else []:
		if crate != null and is_instance_valid(crate):
			count += 1
	return count


func _take_from_cargo(crate: SalvageCrate) -> void:
	var vehicle := crate.holder
	if vehicle != null and is_instance_valid(vehicle) and not vehicle is Actor:
		var cargo: Array = vehicle.get("cargo")
		var at := cargo.find(crate)
		if at >= 0:
			cargo[at] = null


## The ground's height under `at` (a ray down from a little above it), or
## `at` itself with nothing under it.
func _ground_below(at: Vector3) -> Vector3:
	if not is_inside_tree():
		return at
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0, 2.0, 0), at + Vector3(0, -6.0, 0), Actor.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return at if hit.is_empty() else hit["position"]


## Authority: what `actor` hauls goes in with a bank: the crate in their
## hands and their vehicle's cargo. Returns the items, the crates gone.
func _bank_crates(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for crate: SalvageCrate in SalvageCrate.hauled_by(actor):
		out.append_array(crate.items)
		if actor.crate == crate:
			actor.crate = null
		_take_from_cargo(crate)
		crates.erase(crate)
		crate.queue_free()
	return out


## Authority: the crate in `actor`'s hands falls where they are, and the
## cargo of the vehicle they drive with it (a death, or a sign-out: a crate
## is only ever banked at a depot).
func _drop_hauled(actor: Actor) -> void:
	if mode == Mode.CLIENT or actor == null:
		return
	if actor.crate != null and is_instance_valid(actor.crate):
		drop_crate(actor.crate, actor.global_position)
	actor.crate = null
	var vehicle := actor.vehicle
	if vehicle != null and is_instance_valid(vehicle) and vehicle.get("rider") == actor:
		spill_cargo(vehicle)


func spawn_container(items: Array, is_bag: bool, label: String, at: Vector3,
		pile_scrip := -1, pile_bounty := 0, made: LootContainer = null) -> LootContainer:
	var container := made if made != null else LootContainer.new()
	container.setup(items, is_bag, label)
	if pile_scrip >= 0:
		container.make_pile(pile_scrip, pile_bounty)
		piles.append(container)
		container.tree_exiting.connect(func() -> void: piles.erase(container))
	add_child(container)
	container.global_position = at
	container_spawned.emit(container)
	return container


func _on_actor_died(actor: Actor, info: DamageInfo) -> void:
	world.on_death(actor, info)
	# A crate is never in a bag: what they hauled falls where they died.
	_drop_hauled(actor)
	_tell_team(actor)
	if grudges.has(actor):
		# A grudge lasts one life.
		grudges.erase(actor)
		actor.hunted_by = ""
	elif info != null and world.grudge_factions.has(actor.faction):
		_add_grudge(info.source as Actor, actor.faction, world.grudge_per_kill)
	if mode != Mode.CLIENT and state_for(actor) == null:
		var burst := world.death_burst(actor)
		if not burst.is_empty():
			burst_cloud(actor.global_position + Vector3(0, 0.6, 0), burst, actor.faction)
	var drops := actor.get_drop_items()
	if state_for(actor) != null and world.keep_gear_on_death:
		# A gentler world: a player's equipped gear goes home, not in the bag.
		drops.assign(actor.inventory.items)
	_recall_insured(state_for(actor), drops)
	var dead := state_for(actor)
	var carried := dead.scrip if dead != null and mode != Mode.CLIENT else 0
	var pile_bounty := 0
	if world.death_drops_scrip:
		# No bag: a scrip pile (`_drop_pile`), the bounty in it. A client
		# hears of it from the server.
		if mode != Mode.CLIENT:
			pile_bounty = _drop_pile(actor, info, drops)
	else:
		# Power weapons never go in a bag: they are left on a rack, shots and all.
		armory.on_death(actor, drops)
	if not world.death_drops_scrip and (not drops.is_empty() or carried > 0):
		var bag := spawn_container(drops, true, "%s's bag" % actor.display_name if carried <= 0
				else "%s's bag, %d scrip" % [actor.display_name, carried], drop_spot(actor))
		if carried > 0:
			# What they carried lies with the bag for whoever gets there first.
			bag.scrip = carried
			bag.scrip_taken.connect(_on_scrip_taken)
			dead.scrip_lost = carried
			dead.scrip = 0
			actor.scrip = 0
		# Bags do not pile up forever in a world that never ends. Connected
		# to the bag itself, so a bag emptied and gone (or a raid closed)
		# before then drops the call with it.
		if mode != Mode.CLIENT:
			get_tree().create_timer(world.bag_lifetime, false, true).timeout.connect(bag.queue_free)
	var killer := state_for(info.source as Actor) if info.source is Actor else null
	var state := state_for(actor)
	if killer != null and killer.actor == actor:
		killer = null
	var by: String = (info.source as Actor).display_name if info.source is Actor else ""
	var gained := 0
	if mode != Mode.CLIENT:
		# Read before the ledger closes the victim's life.
		var bounty := renown.bounty_of(state.owner) if state != null else 0
		if state != null:
			state.end_note["bounty"] = bounty
		gained = _settle_renown(state, killer, actor, by)
		if killer != null:
			var pay := Economy.KILL_BOUNTY
			_count(killer, "kills")
			if state == null and actor.faction != "":
				_count(killer, "kills:" + actor.faction)
			if _bosses.any(func(boss: Dictionary) -> bool: return boss.bot == actor):
				_count(killer, "bosses")
				# And by its kind, so a contract can name one boss of several.
				if str(actor.get_meta("boss", "")) != "":
					_count(killer, "boss:" + str(actor.get_meta("boss")))
			if warlords.has(actor):
				pay += Economy.WARLORD_SCRIP
				_count(killer, "warlords")
			elif state != null and not _wears_scrap(actor):
				pay = Economy.PLAYER_KILL_SCRIP
			# A bounty on the victim is the killer's, carried like any scrip:
			# it only counts once they bank it or sign out alive.
			if pile_bounty > 0:
				killer.actor.notice.emit("Bounty dropped: %d scrip in the pile, grab it" % pile_bounty)
			elif bounty > 0 and killer.owner != state.owner and not world.death_drops_scrip:
				pay += Economy.bounty_scrip(bounty)
				killer.actor.notice.emit("Bounty claimed: +%d scrip, yours once you get it home" % Economy.bounty_scrip(bounty))
			_pay_scrip(killer, pay)
		# A warlord or a boss brought down is news in the plaza's War Room.
		if warlords.has(actor) or _bosses.any(func(boss: Dictionary) -> bool: return boss.bot == actor):
			note_moment("boss", "%s brought down %s" % [killer.actor.display_name, actor.display_name]
					if killer != null else "%s is down" % actor.display_name)
		# Only kills that players are part of count as the war.
		if state != null or killer != null:
			war.report_kill(actor.global_position, state != null)
	if killer != null:
		killer.kills += 1
		if killer.actor == player:
			kills += 1
		killer.actor.notice.emit("Killed %s" % actor.display_name if gained <= 0
				else "Killed %s   +%d renown" % [actor.display_name, gained])
	if state != null:
		if mode != Mode.CLIENT:
			# Read now, while the bots that were after them still are.
			state.end_note["killer"] = LifeLog.killer_kind(self, actor, info)
			state.end_note["hunters"] = LifeLog.hunters_of(actor)
		_finish_player(state, "died", info.kind, by)
		_publish_standing()
		# The local player's body stays for the camera until they drop in again.
		if mode == Mode.SOLO and actor == player:
			return
	else:
		var extra := _is_extra(actor)
		if mode != Mode.CLIENT and is_raider(actor):
			# A raider is somebody: everyone hears who got them. Another
			# drops in after the usual gap.
			war_feed.emit("%s killed %s" % [_feed_name(info.source as Actor), actor.display_name]
					if info.source is Actor and info.source != actor else "%s died" % actor.display_name)
			for entry in raiders.duplicate():
				if entry.bot == actor:
					raiders.erase(entry)
			_raider_in = maxf(_raider_in, world.raider_gap)
		bots.erase(actor)
		warlords.erase(actor)
		# A world event's bots are extra: nobody takes their place. Neither
		# are reinforcements replaced once the war has cooled.
		if mode != Mode.CLIENT and not extra:
			if _standing_bots() + _bot_respawns.size() < bot_target():
				_bot_respawns.append(world.bot_respawn_time)
			# Bots killing bots keep the war simmering.
			if state_for(info.source as Actor) == null and info.source is Actor:
				war.report_battle(actor.global_position)
	get_tree().create_timer(4.0).timeout.connect(_remove_actor.bind(actor))


## Pays out renown for a death and tells the world about it. Returns what
## the killer gained.
func _settle_renown(victim: PlayerState, killer: PlayerState, actor: Actor, by: String) -> int:
	var gained := 0
	if victim == null:
		if killer != null:
			gained = renown.bot_killed(killer.owner)
			if warlords.has(actor):
				gained += renown.award(killer.owner, renown.warlord_kill)
				war_feed.emit("%s killed the warlord" % _feed_name(killer.actor))
			_publish_standing()
		elif warlords.has(actor):
			war_feed.emit("The warlord is dead")
		return gained
	var paid := renown.player_died(victim.owner, killer.owner if killer != null else "",
			_wears_scrap(actor))
	victim.renown_lost = paid.lost
	gained = paid.gain
	if killer == null:
		war_feed.emit("%s fell to %s" % [actor.display_name, by] if by != ""
				else "%s died" % actor.display_name)
		return gained
	var line := "%s killed %s" % [_feed_name(killer.actor), _feed_name(actor)]
	if paid.marked:
		line += ", the Marked"
	if paid.bounty > 0:
		line += ", and claimed a bounty of %d" % paid.bounty
	war_feed.emit(line)
	var streak: int = renown.get_standing(killer.owner).player_streak
	if streak == renown.exposed_streak:
		war_feed.emit("%s is exposed: everyone can see where they are" % killer.actor.display_name)
	elif streak == renown.bounty_streak:
		war_feed.emit("%s has a bounty of %d" % [killer.actor.display_name,
				renown.bounty_of(killer.owner)])
	return gained


## A player's name with their rank, for the feed.
func _feed_name(actor: Actor) -> String:
	var state := state_for(actor)
	var standing := renown.get_standing(state.owner) if state != null else null
	if standing == null:
		return actor.display_name
	return "%s [%s]" % [actor.display_name, RenownLedger.rank_name(RenownLedger.rank_for(standing.lifetime))]


static func _wears_scrap(actor: Actor) -> bool:
	for id in actor.gear_items:
		if not ItemDB.has_tag(id, "starter"):
			return false
	return true


## Copies each player's public standing onto their actor, where nameplates,
## the HUD and `NetSession` read it, and announces a new Marked.
func _publish_standing() -> void:
	if mode == Mode.CLIENT:
		return
	var top := renown.marked()
	for state in players:
		var standing := renown.get_standing(state.owner)
		if standing == null or not is_instance_valid(state.actor):
			continue
		var actor := state.actor
		actor.renown = standing.renown
		actor.rank = RenownLedger.rank_for(standing.lifetime)
		actor.streak = standing.streak
		actor.bounty = renown.bounty_of(state.owner)
		actor.exposed = renown.is_exposed(state.owner)
		actor.marked = state.owner == top
		if actor.marked and top != _marked_owner:
			war_feed.emit("%s is now the Marked" % actor.display_name)
	_marked_owner = top


func _remove_actor(actor: Actor) -> void:
	if not is_instance_valid(actor):
		return
	_drop_hauled(actor)
	var state := state_for(actor)
	if state != null:
		players.erase(state)
		if is_instance_valid(state.mastery):
			state.mastery.queue_free()
	bots.erase(actor)
	bot_seeds.erase(actor)
	warlords.erase(actor)
	for entry in raiders.duplicate():
		if entry.bot == actor:
			raiders.erase(entry)
	_orders.erase(actor)
	_busy_until.erase(actor)
	actor_removed.emit(actor)
	actor.queue_free()


func _on_actor_banked(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null or state.finished or actor.is_dead:
		return
	var items := Depot.bankable(actor)
	var hauled := _bank_crates(actor)
	if items.is_empty() and state.scrip <= 0 and hauled.is_empty():
		return
	if state.scrip > 0:
		# Banked scrip is safe: it is paid out when this life ends, however it ends.
		actor.notice.emit("Banked %d scrip" % state.scrip)
		state.scrip_banked += state.scrip
		state.scrip = 0
		actor.scrip = 0
		actor.banked_scrip = state.scrip_banked
	if items.is_empty() and hauled.is_empty():
		banked_changed.emit(actor)
		return
	var heavy := ""
	var heavy_at := Loadout.power_index(actor)
	if heavy_at >= 0:
		heavy = (actor.weapons[heavy_at] as Gun).item_id
	for id in items:
		if id == heavy:
			# The chambered heavy goes home. It is not in the backpack.
			Loadout.set_power(actor, "")
			heavy = ""
		else:
			actor.inventory.remove_item(id)
	# A crate's contents go in with the pack's.
	items.append_array(hauled)
	state.banked.append_array(items)
	_count(state, "banks")
	actor.banked_count = state.banked.size()
	actor.banked_value = ItemDB.total_value(state.banked)
	banked_changed.emit(actor)
	actor.notice.emit("Banked %s (worth %d)" % [ItemDB.summarize(items), ItemDB.total_value(items)])
	if apply_to_profile:
		Profile.add_to_stash(items)
	player_banked.emit(actor, items)


## Someone took items out of a world cache: a contract's "cache:<source>",
## counted once for each player each time the cache is filled.
func _on_cache_looted(actor: Actor, entry: Dictionary) -> void:
	var state := state_for(actor)
	if state == null or entry.looted.has(state.owner):
		return
	entry.looted[state.owner] = true
	_count(state, "cache:" + str(entry.source))


## Adds to a living player's contract counters for this life (see
## `Contracts.JOBS` for the stats). Only the authority counts, and only where
## gear is at stake, so the arena and the safe zone count nothing. They reach
## the account in the result's `tally`, and only a sign-out counts them.
func _count(state: PlayerState, stat: String, amount := 1) -> void:
	if mode == Mode.CLIENT or world.safe_zone or not world.gear_at_risk or amount <= 0 \
			or state == null or not is_instance_valid(state.actor) or state.finished:
		return
	state.tally[stat] = int(state.tally.get(stat, 0)) + amount
	state.actor.tally = state.tally.duplicate()
	tally_changed.emit(state.actor)


## Scrip a living player earned. It is carried, so it is at stake.
func _pay_scrip(state: PlayerState, amount: int) -> void:
	if mode == Mode.CLIENT or world.safe_zone or not world.gear_at_risk or amount <= 0 \
			or not is_instance_valid(state.actor) or state.finished:
		return
	state.scrip += amount
	state.actor.scrip = state.scrip


## Someone picked the scrip out of a dead player's bag.
func _on_scrip_taken(actor: Actor, amount: int) -> void:
	var state := state_for(actor)
	if state == null:
		return
	_pay_scrip(state, amount)
	actor.notice.emit("Took %d scrip" % amount)


## A sign-out finished: the player leaves alive and everything they carry
## goes home, with the vehicle they are riding, whoever it belonged to.
func _leave(state: PlayerState) -> void:
	var actor := state.actor
	if state.finished or actor.is_dead:
		return
	world.on_leave(actor)
	# A crate goes home only through a depot: what they haul stays behind.
	_drop_hauled(actor)
	var ridden := actor.vehicle
	if ridden != null:
		state.rode_home = ridden.get("item_id")
	_finish_player(state, "left", "", "")
	renown.leave(state.owner)
	_publish_standing()
	if mode == Mode.SERVER:
		# They are gone from the world, and so is the vehicle they rode out on.
		if ridden != null:
			remove_vehicle(ridden)
		_remove_actor(actor)


## A death where `WorldDef.death_drops_scrip` (Caleb's call, DESIGN.md
## "Scrip piles"): everything in `drops` is gone but one bonus item from the
## pack (`pile_bonus`) and any artifact they carried, which drop as
## themselves, and a scrip pile lies where they fell, worth what a
## trader pays for the rest (a bot's by `bot_pile_share`, growing with the
## war), plus the scrip they carried and, if a player took a wanted player
## down, the bounty. Returns the bounty put in it. Authority only.
func _drop_pile(actor: Actor, info: DamageInfo, drops: Array[String]) -> int:
	var dead := state_for(actor)
	var bonus := pile_bonus(actor, dead, drops, rng)
	# An artifact, attuned or in the pack, drops as itself and is not sold
	# into the pile (Caleb's call), so artifacts keep changing hands.
	var items: Array[String] = []
	if bonus != "":
		items.append(bonus)
	var worth := 0
	var sold := drops.duplicate()
	sold.erase(bonus)
	for id in sold:
		if ItemDB.has_tag(id, "artifact"):
			items.append(id)
		else:
			worth += Economy.sell_price(id)
	if dead == null:
		worth = int(round(worth * world.bot_pile_share * (1.0 + world.pile_war_bonus * war.intensity)))
	var carried := 0
	if dead != null and dead.scrip > 0:
		carried = dead.scrip
		dead.scrip_lost = carried
		dead.scrip = 0
		actor.scrip = 0
	var bounty := 0
	var killer := state_for(info.source as Actor) if info.source is Actor else null
	if dead != null and killer != null and killer.owner != dead.owner:
		bounty = Economy.bounty_scrip(renown.bounty_of(dead.owner))
	var total := worth + carried + bounty
	if total <= 0 and items.is_empty():
		return 0
	var pile := spawn_container(items, true, "%s's scrip" % actor.display_name, drop_spot(actor),
			total, bounty)
	pile.scrip_taken.connect(_on_scrip_taken)
	if bounty > 0:
		war_feed.emit("%s's bounty of %d lies where they fell" % [_feed_name(actor), bounty])
	get_tree().create_timer(world.bag_lifetime, false, true).timeout.connect(pile.queue_free)
	return bounty


## The one bonus item a scrip pile keeps from `drops` (DESIGN.md "Scrip
## piles"), or "": from the pack only, never what was worn or held. Usually
## something small (a consumable, a material, an attachment); with
## `WorldDef.pile_found_chance` instead a piece of gear they found this life
## (in the pack but not brought from the stash: everything a bot carries
## counts as found). Never the free scrap kit, a heavy weapon or an artifact.
func pile_bonus(actor: Actor, dead: PlayerState, drops: Array[String], dice: RandomNumberGenerator) -> String:
	var small: Array[String] = []
	var found: Array[String] = []
	var brought: Array[String] = []
	if dead != null:
		brought.assign(dead.kit)
	for id in actor.inventory.items:
		if id not in drops or ItemDB.has_tag(id, "starter") or ItemDB.has_tag(id, "power") \
				or ItemDB.has_tag(id, "artifact"):
			continue
		if PILE_SMALL_TAGS.any(func(tag: String) -> bool: return ItemDB.has_tag(id, tag)):
			small.append(id)
		elif id in brought:
			brought.erase(id)
		else:
			found.append(id)
	if not found.is_empty() and dice.randf() < world.pile_found_chance:
		return found[dice.randi() % found.size()]
	if not small.is_empty():
		return small[dice.randi() % small.size()]
	return ""


## Grabs piles for any living player standing on one. Authority only.
func _tick_piles() -> void:
	if piles.is_empty():
		return
	var reach := world.pile_reach
	for pile: Variant in piles.duplicate():
		if not is_instance_valid(pile):
			continue
		var at := (pile as Node3D).global_position
		for state in players:
			var actor := state.actor
			if state.finished or not is_instance_valid(actor) or actor.is_dead:
				continue
			var flat := Vector2(actor.global_position.x - at.x, actor.global_position.z - at.z)
			if flat.length() <= reach and absf(actor.global_position.y - at.y) < 2.0:
				(pile as LootContainer).grab(actor)
				break


## A player died: their insured item, if it is on the body, is recalled home
## instead of dropping in `drops` (the bag). Authority only; a client never
## knows what is insured. One copy, once a life.
func _recall_insured(state: PlayerState, drops: Array[String]) -> void:
	if state == null or mode == Mode.CLIENT or state.insured == "" or state.recalled != "":
		return
	if state.insured not in drops:
		return
	drops.erase(state.insured)
	state.recalled = state.insured
	if is_instance_valid(state.actor):
		state.actor.notice.emit("%s recalled home by your insurance" % ItemDB.item_name(state.recalled))


func _finish_player(state: PlayerState, outcome: String, cause: String, killed_by: String) -> void:
	if state.finished:
		return
	state.finished = true
	state.sign_out_left = -1.0
	var actor := state.actor
	if is_instance_valid(actor):
		actor.set_sign_out_beacon(false)
	# A toy still in the hand mid-throw is on the watch, as far as what is
	# carried goes.
	for toy in toys.duplicate():
		if toy.state == state and toy.has("windup"):
			toys.erase(toy)
			state.stowed.append(toy.id)
	if is_instance_valid(actor) and actor.toy_in_hand != "":
		actor.toy_in_hand = ""
		toy_hand_changed.emit(actor)
	var left := outcome == "left"
	var loot: Array[String] = []
	var kept: Array[String] = []
	var brought_home: Array[String] = []
	var lost: Array[String] = []
	if left:
		loot.assign(actor.inventory.items)
		kept.assign(actor.gear_items.filter(func(id: String) -> bool:
			return not ItemDB.has_tag(id, "starter")))
		brought_home.assign(actor.get_drop_items())
		if state.rode_home != "":
			kept.append(state.rode_home)
			brought_home.append(state.rode_home)
		# The toys on their watch are carried, so they go home too.
		kept.append_array(state.stowed)
		brought_home.append_array(state.stowed)
	elif world.keep_gear_on_death:
		lost.assign(actor.inventory.items)
		kept.assign(actor.gear_items.filter(func(id: String) -> bool:
			return not ItemDB.has_tag(id, "starter")))
		brought_home.assign(kept)
	else:
		lost.assign(actor.get_drop_items())
	if not left and state.recalled != "":
		# The insured item went home instead of into the bag.
		lost.erase(state.recalled)
		brought_home.append(state.recalled)
	# What was lost with the body: dropped in the bag, or a toy on the watch.
	var with_body := lost.duplicate()
	# A vehicle you brought is lost unless you left with it on your watch or
	# rode it (or another) back out. Dying loses the watch's toys as well.
	var left_behind := state.deployed_vehicles.duplicate()
	left_behind.erase(state.rode_home)
	var found := state.stowed.duplicate()
	for id in state.deployed_vehicles:
		found.erase(id)
	if left:
		for id in state.stowed:
			left_behind.erase(id)
	else:
		lost.append_array(found)
	lost.append_array(left_behind)
	# Salvage (`SafetyNets`): crafted gear this life brought from the stash
	# and lost with the body. Not what was dropped or thrown before the death
	# (someone else may have it), nor anything picked up in the world.
	var salvaged: Array[String] = []
	if not left:
		with_body.append_array(state.stowed)
		var from_stash := state.kit.filter(func(id: String) -> bool: return not StashRules.is_free(id))
		for id: String in with_body:
			if id in from_stash:
				from_stash.erase(id)
				if SafetyNets.salvages(id):
					salvaged.append(id)
	# A heavy weapon in the chamber comes home on a sign-out (and counts as
	# lost on a death). One that was banked is already in `state.banked` and
	# off the body. Death still leaves the gun on a rack beside the bag.
	if not world.gear_at_risk:
		# Nothing left the stash, so nothing comes home or is lost (a race
		# machine ridden out is the track's, not yours).
		loot.clear()
		kept.clear()
		brought_home.clear()
		lost.clear()
		salvaged.clear()
	var result := {
		"outcome": outcome,
		"cause": cause,
		"killed_by": killed_by,
		"world_id": world.id,
		# Which of a world's own contracts count (`WorldDef.contract_tag`).
		"contract_tag": world.contract_tag,
		"loot": loot,
		"kept_gear": kept,
		"brought_home": brought_home,
		"loot_value": ItemDB.total_value(loot),
		"lost": lost,
		# The safety nets: the insured item recalled home (it is in
		# `brought_home` too), and the crafted gear lost with the body with
		# the parts it pays back.
		"recalled": state.recalled if world.gear_at_risk else "",
		"salvaged": salvaged,
		"salvage": SafetyNets.salvage_all(salvaged),
		"banked": state.banked.duplicate(),
		"banked_value": ItemDB.total_value(state.banked),
		"kills": state.kills,
		# Scrip: carried home (nothing if they died), banked on the way, and
		# dropped with the body.
		"scrip": state.scrip if left else 0,
		"scrip_banked": state.scrip_banked,
		"scrip_lost": state.scrip_lost,
		"mastery_xp": state.mastery.report(),
		# Contract counters (`_count`). Only a sign-out counts them.
		"tally": state.tally.duplicate(),
		# Given up on the watch (`abandon`): a death, but the game goes
		# straight home instead of offering a new life.
		"abandoned": state.abandoned and outcome == "died",
	}
	if left and state.sign_out_door != "":
		# Through a portal out of the world: everything carried goes home as
		# with any sign-out, and the door says where the trip goes on to
		# (home: your base, not the plaza; else a world, the arena or the
		# plaza, from there).
		result["door"] = state.sign_out_door
	var standing := renown.get_standing(state.owner)
	if standing != null:
		# What this life added to lifetime renown, what dying took from the
		# session, and where the session stands now.
		result["renown"] = standing.earned
		result["renown_lost"] = state.renown_lost
		result["renown_now"] = standing.renown
	if apply_to_profile:
		apply_result(result)
	_log_life(state, result)
	player_finished.emit(actor, result)


## One line in the life log for a finished life (`LifeLog`): where and how
## it ended and what it carried. Authority only, never in a safe zone.
func _log_life(state: PlayerState, result: Dictionary) -> void:
	if mode == Mode.CLIENT or world.safe_zone:
		return
	var actor := state.actor
	var at := actor.global_position if is_instance_valid(actor) else Vector3.ZERO
	var in_storm := weather.strength_at(at) if weather.kind != "" else 0.0
	var died: bool = result.outcome == "died"
	life_log.record({
		"time": int(Time.get_unix_time_from_system()),
		"world": world.id,
		"owner": state.owner,
		"outcome": result.outcome,
		"cause": result.cause,
		"killer": str(state.end_note.get("killer", "")) if died else "",
		"hunters": int(state.end_note.get("hunters", 0)) if died else 0,
		"zone": world.zone_at(at),
		"x": snappedf(at.x, 0.1),
		"z": snappedf(at.z, 0.1),
		"alive": snappedf(clock - state.started, 0.1),
		"kills": state.kills,
		"gear_value": ItemDB.total_value(state.kit),
		"carried_value": ItemDB.total_value(actor.get_drop_items()) if died and is_instance_valid(actor)
				else int(result.get("loot_value", 0)),
		"banked_value": int(result.get("banked_value", 0)),
		"scrip": int(result.get("scrip", 0)) + int(result.get("scrip_banked", 0)),
		"war": snappedf(war.intensity, 0.01),
		"storm": snappedf(in_storm, 0.01),
		"bounty": int(state.end_note.get("bounty", renown.bounty_of(state.owner))),
	})


## Writes a finished life into the local profile: what came home, the
## salvage and an insurance claim, and the record.
static func apply_result(result: Dictionary) -> void:
	var home: Array = result.get("brought_home", [])
	if not home.is_empty():
		Profile.add_to_stash(home)
	var salvage: Array = result.get("salvage", [])
	if not salvage.is_empty():
		Profile.add_to_stash(salvage)
	Profile.claim_insurance(str(result.get("recalled", "")))
	Profile.record_raid(result)


# --- Salvage fields (DESIGN.md "The Dune Sea (part two)") -------------------

func is_field_buried(index: int) -> bool:
	return index >= 0 and index < fields.size() and bool(fields[index].get_meta("buried", false))


## The salvage field whose ground covers `at` (flat distance), or -1.
func _field_index_at(at: Vector3) -> int:
	for i in fields.size():
		if _flat_distance(fields[i].global_position, at) <= float(fields[i].get_meta("radius", 30.0)):
			return i
	return -1


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Buries field `index` or uncovers it, everywhere: its scenery sinks or
## rises with it. On the authority a buried field loses the crates lying in
## it (never one someone holds or a vehicle carries), and an uncovered one
## gets a crate on every spot at once.
func set_field_buried(index: int, buried: bool) -> void:
	if index < 0 or index >= fields.size() or is_field_buried(index) == buried:
		return
	var field := fields[index]
	field.set_meta("buried", buried)
	field.position.y = float(field.get_meta("ground_y", field.position.y)) \
			- (float(field.get_meta("sink", 4.0)) if buried else 0.0)
	if mode != Mode.CLIENT:
		if buried:
			var reach := float(field.get_meta("radius", 30.0))
			for crate in crates.duplicate():
				if crate.holder == null and _flat_distance(crate.global_position, field.global_position) <= reach:
					crate.queue_free()
			for spot: Dictionary in _crate_spots:
				if int(spot.field) == index:
					spot.crate = null
					spot.empty_for = 0.0
		else:
			for spot: Dictionary in _crate_spots:
				if int(spot.field) == index:
					var old: Variant = spot.crate
					if old == null or not is_instance_valid(old):
						spot.crate = _crate_at(spot.marker)
					spot.empty_for = 0.0
	field_changed.emit(index, buried)


## Authority: `WorldDef.fields_buried_at_start` fields begin buried, picked
## by the raid's seed.
func _bury_at_start() -> void:
	if not world.weather_buries or fields.size() < 2:
		return
	var order: Array = range(fields.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = order[i]
		order[i] = order[j]
		order[j] = swap
	for i in mini(world.fields_buried_at_start, fields.size() - 1):
		set_field_buried(int(order[i]), true)


## Authority: a storm at full strength buries every open field its heart
## covers, and for each uncovers a buried one out of its reach (one it has
## already passed if there is one), told on the war feed.
func _tick_fields() -> void:
	if mode == Mode.CLIENT or not weather.active() or weather.strength < 0.8:
		return
	var heart := weather.radius * weather.core_share
	for i in fields.size():
		if is_field_buried(i) or _flat_distance(fields[i].global_position, weather.centre) > heart:
			continue
		set_field_buried(i, true)
		var title := str(fields[i].get_meta("title", "a salvage field"))
		war_feed.emit("The %s buried %s %s" % [world.weather_name.to_lower(), title,
				_whereabouts(fields[i].global_position)])
		var uncover := _field_to_uncover(i)
		if uncover >= 0:
			set_field_buried(uncover, false)
			war_feed.emit("The %s uncovered %s %s" % [world.weather_name.to_lower(),
					str(fields[uncover].get_meta("title", "a salvage field")), _whereabouts(fields[uncover].global_position)])


func _field_to_uncover(just_buried: int) -> int:
	var behind: Array[int] = []
	var clear: Array[int] = []
	for i in fields.size():
		if i == just_buried or not is_field_buried(i):
			continue
		var off := fields[i].global_position - weather.centre
		off.y = 0.0
		if off.length() <= weather.radius:
			continue
		clear.append(i)
		if off.dot(weather.velocity) < 0.0:
			behind.append(i)
	var pool := behind if not behind.is_empty() else clear
	return -1 if pool.is_empty() else pool[rng.randi_range(0, pool.size() - 1)]


## Which salvage fields are buried, one flag each in `fields` order (sent to
## a client).
func pack_fields() -> Array:
	var out := []
	for i in fields.size():
		out.append(is_field_buried(i))
	return out


func _map_nodes(group: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(group):
		if node is Node3D and map.is_ancestor_of(node):
			out.append(node)
	return out


func _exit_tree() -> void:
	if Worlds.current == world:
		Worlds.current = null


## One life of a player: who they are, what they brought, and how they are doing.
class PlayerState:
	extends RefCounted

	var actor: Actor
	## Whose life this is. Renown is kept under this key across lives.
	var owner := ""
	var renown_lost := 0
	## Scrip carried (lost with the body), banked this life, and dropped on death.
	var scrip := 0
	var scrip_banked := 0
	var scrip_lost := 0
	var kit: Array[String] = []
	var mastery: MasteryTracker
	## Mastery variants the player deployed with (track -> variant id).
	var picks := {}
	var kills := 0
	## Contract counters for this life: stat -> count (`Raid._count`).
	var tally := {}
	## The vehicles ridden this life, so each counts once.
	var ridden: Array[int] = []
	## Their insured item, if this kit carries it (`SafetyNets`), and the
	## item recalled home at their death.
	var insured := ""
	var recalled := ""
	## The bag their last drop went in (`Raid.drop_item`), so drops made in
	## one spot share one bag.
	var drop_bag: LootContainer
	## Vehicle items the player deployed with. Lost unless they leave riding one.
	var deployed_vehicles: Array[String] = []
	## The toy vehicles on their watch: ones they brought and have not thrown,
	## and ones they packed up in the field.
	var stowed: Array[String] = []
	## `Raid.clock` when they can throw a toy again.
	var toy_ready_at := -INF
	## `Raid.clock` when their watch can materialize a weapon again, and how
	## long that wait was (for the watch's ring).
	var summon_ready_at := -INF
	var summon_wait_total := 0.0
	## `Raid.clock` when they can ping again.
	var ping_ready_at := -INF
	var portal_ready_at := -INF
	## The vehicles they unpacked from toys.
	var parked: Array[Node3D] = []
	## The vehicle they were riding when they left.
	var rode_home := ""
	## What they banked at depots this life. Already in the stash.
	var banked: Array[String] = []
	## Seconds left of a sign-out, or below zero when there is none.
	var sign_out_left := -1.0
	var sign_out_total := 0.0
	## The player is gone and the body is waiting out the sign-out.
	var sign_out_forced := false
	## The length does not follow the air: a gate sign-out, or a body left
	## behind by a disconnect.
	var sign_out_fixed := false
	## The sign-out the player had going when their connection dropped, as
	## [total, fixed, door], or empty: what `Raid.reclaim_player` restores.
	var dropped_sign_out: Array = []
	## Where the portal this sign-out was started through leads
	## (`open_portal`, a `Portal.from_world` id), or "" for a plain sign-out.
	## The result says it as "door": home, or where the trip goes on to from
	## home once the gear is in.
	var sign_out_door := ""
	## The warm beacon this sign-out is powering, or null (DESIGN.md
	## "Frostline"), and whether they have stepped away from it.
	var at_beacon: Node3D = null
	var beacon_left := false
	## How fast the sign-out counts down now: 1, 0 while away from the
	## beacon, more with company there. A client is told it.
	var count_rate := 1.0
	## Seconds until the airborne beacon makes another noise.
	var beacon_hum := 0.0
	## `Raid.clock` when they last gave or took a hit.
	var last_combat := -INF
	## Who last hurt them (an instance id, 0 for none) and when, by
	## `Raid.clock`: an abandon in a fight is that attacker's kill.
	var last_hit_by := 0
	var last_hit_at := -INF
	## The life ended by abandoning it (`Raid.abandon`), not by a kill.
	var abandoned := false
	## Inside a gate outpost, under its shelter (`Raid._tick_outposts`).
	var sheltered := false
	## Walked out of an outpost and still protected: firing ends it.
	var leaving_gate := false
	## `Raid.clock` when an outpost last turned them away, so it says so once.
	var refused_at := -INF
	var finished := false
	## `Raid.clock` when this life began, and what ended it (the killer's
	## kind and how many bots were after them), for the life log.
	var started := 0.0
	var end_note := {}
	## Seconds held in a strongpoint of their side not yet counted.
	var held_for := 0.0


## A bot of a fireteam fell: the rest of its team hear of it
## (`BotBrain.ally_down`, which breaks a team that has lost too many).
## Authority only; one scan of the bots a death.
func _tell_team(dead: Actor) -> void:
	if mode == Mode.CLIENT or not dead.has_node("Brain"):
		return
	var team := (dead.get_node("Brain") as BotBrain).team
	if team == 0:
		return
	for other: Variant in bots:
		if not is_instance_valid(other) or other == dead:
			continue
		var bot := other as Actor
		if bot.is_dead or bot.faction != dead.faction or not bot.has_node("Brain"):
			continue
		var brain := bot.get_node("Brain") as BotBrain
		if brain.team == team:
			brain.ally_down()


## A bot of an army that keeps grudges was hurt: the player who did it rises
## in that army's grudge (`WorldDef.grudge_factions`).
func _on_army_hurt(info: DamageInfo, bot: Actor) -> void:
	if info == null or info.amount <= 0.0 or not is_instance_valid(bot):
		return
	# No more than the bot had in it: an overkill counts as one body.
	var hurt := minf(info.amount, bot.health.max_health)
	_add_grudge(info.source as Actor, bot.faction, hurt * world.grudge_per_damage)


func _add_grudge(source: Actor, faction: String, points: float) -> void:
	if source == null or not is_instance_valid(source) or source.is_dead or state_for(source) == null:
		return
	var held: Dictionary = grudges.get(source, {})
	held[faction] = minf(float(held.get(faction, 0.0)) + points, world.grudge_cap)
	grudges[source] = held


## Grudges fade, and an army whose grudge runs high sends a few of its bots
## after that player: to where they roughly are (a heard place, never live
## tracking), through `BotBrain.hunt_grudge`, so the brain's hunter and leash
## limits still hold. Authority only.
func _tick_grudges(delta: float) -> void:
	_grudge_in -= delta
	var send := _grudge_in <= 0.0
	if send:
		_grudge_in = GRUDGE_EVERY
	# Untyped: a freed player cannot be assigned to an `Actor` to be checked.
	for key: Variant in grudges.keys():
		if not is_instance_valid(key):
			grudges.erase(key)
			continue
		var player := key as Actor
		var held: Dictionary = grudges[player]
		var top := ""
		for faction: String in held.keys():
			var points := float(held[faction]) - world.grudge_fade * delta
			if points <= 0.0:
				held.erase(faction)
				continue
			held[faction] = points
			if points >= world.grudge_hunt and (top == "" or points > float(held[top])):
				top = faction
		player.hunted_by = top
		if held.is_empty():
			grudges.erase(player)
		elif send and top != "" and not player.is_dead:
			_send_grudge_hunters(player, top)


func _send_grudge_hunters(player: Actor, faction: String) -> void:
	var near: Array = []
	for bot in bots:
		if not is_instance_valid(bot) or bot.is_dead or bot.faction != faction or _is_extra(bot):
			continue
		var d := bot.global_position.distance_to(player.global_position)
		if d <= GRUDGE_REACH and bot.has_node("Brain"):
			near.append([d, bot])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(GRUDGE_HUNTERS, near.size()):
		(near[i][1].get_node("Brain") as BotBrain).hunt_grudge(player.global_position, player)
