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
signal vehicle_removed(vehicle: Node3D)
## A player threw a toy vehicle off their watch. It flies from `from`.
signal toy_thrown(actor: Actor, item_id: String, from: Vector3, toy_velocity: Vector3)
## A thrown toy came to rest. `unpacked` is false if there was no room and it
## went back on the watch.
signal toy_landed(actor: Actor, item_id: String, at: Vector3, unpacked: bool)
## What a player's watch holds, or when they can throw again, changed.
signal watch_changed(actor: Actor)
## A player pinged a spot for their side (`ping`). On a client it is only
## ever heard for pings the server chose to tell this player about.
signal pinged(actor: Actor, at: Vector3)

## Bots never start closer to the player than this, so a raid does not open with a fight.
const MIN_BOT_SPAWN_DISTANCE := 40.0
## A vehicle this close to its parking spot counts as still parked there.
const PARKED_DISTANCE := 6.0
## A spawn point this close to open ground, above or below, is stood on it.
const SPAWN_SNAP := 2.5
## Seconds between rounds of orders to the bot factions.
const ORDERS_EVERY := 8.0
const DETAIL_EVERY := 0.25
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MasteryTracker := preload("res://core/progression/mastery_tracker.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const Economy := preload("res://core/economy/economy.gd")
const WarDirector := preload("res://core/war/war_director.gd")
const Strongpoint := preload("res://core/war/strongpoint.gd")
const PowerArmory := preload("res://core/war/power_armory.gd")

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
var vehicles: Array[Node3D] = []
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
## Seconds between one throw and the next, for a vehicle with no
## `watch_recharge` stat of its own (heavier vehicles take longer).
var toy_cooldown := 8.0
## How many vehicles a watch holds.
var watch_capacity := 2
## A squad ping from the watch: how far it reaches, how long its marker
## stands, and the wait before the next.
var ping_range := 300.0
var ping_time := 8.0
var ping_cooldown := 2.0
## The clear box a vehicle needs to unpack: width, height, length. A vehicle
## with a `footprint` stat needs that instead.
var unpack_room := Vector3(1.3, 1.2, 2.6)
## Toys in the air: { state, id, at, velocity, age, heading, node }.
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
## The sites worth holding, one per "strongpoint" marker on the map.
var strongpoints: Array[Strongpoint] = []
## Where power weapons turn up (racks at strongpoints, pods, caches). Runs on
## the authority only.
var armory := PowerArmory.new()
var _assault_in := 0.0
## War intensity from which a player may choose to land beside the fighting.
var hot_drop_from := 0.2
## The world event going on, or {}: { kind ("supply_pod" or "warlord"),
## title, at, ends (on `clock`) }. One at a time.
var event := {}
## Players who stand together: owner key -> [side key, side name]. See `set_team`.
var teams := {}
## The warlords alive in the world, so clients can build the same bot.
var warlords := {}
var _event_in := 0.0
var _event_bots: Array[Actor] = []
var _event_pod: LootContainer
## When false, the raid reports results but leaves the stash alone, so a server
## never writes to a profile that is not the player's.
var apply_to_profile := true
## Server: every player starts at the same spawn point, as one squad.
var squad_spawn := false
## Bots within this many metres of a player are simulated every tick, bots
## within `half_detail_range` every second tick, and the rest every
## `far_detail_step` ticks.
var full_detail_range := 70.0
var half_detail_range := 160.0
var far_detail_step := 4
var _squad_marker := -1
var _player_count := 0
var _bot_count := 0
## One per cache: { container, source, refill_in }.
var _caches: Array[Dictionary] = []
## Seconds until each dead bot is replaced.
var _bot_respawns: Array[float] = []
var _reinforce_in := 0.0
var _orders_in := 0.0
var _detail_in := 0.0
## Bot -> the strongpoint its faction last sent it to.
var _orders := {}
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
		p_owner := "", p_renown := 0) -> void:
	mode = Mode.SOLO
	_setup(p_world, p_seed)
	_spawn_caches()
	armory.setup(self)
	add_player(p_kit, p_mastery, "You", p_owner, p_renown)
	_spawn_bots()
	_spawn_map_vehicles()


## Starts the raid as the authority for an online game. Players are added with
## `add_player` as they connect.
func start_server(p_world: WorldDef, p_seed: int = -1) -> void:
	mode = Mode.SERVER
	apply_to_profile = false
	_setup(p_world, p_seed)
	_spawn_caches()
	armory.setup(self)
	_spawn_bots()
	_spawn_map_vehicles()


## Starts the raid as a view of a server's raid: the map only. Actors are added
## by the network session as the server reports them.
func start_client(p_world: WorldDef) -> void:
	mode = Mode.CLIENT
	apply_to_profile = false
	_setup(p_world, 0)


func _setup(p_world: WorldDef, p_seed: int) -> void:
	world = p_world
	Worlds.current = world
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
		marker.add_child(point)
		var faction: String = marker.get_meta("holder", "")
		if faction != "":
			point.hold("faction:" + faction, marker.get_meta("holder_name", faction.capitalize()), false)
		strongpoints.append(point)
	_assault_in = world.assault_interval
	_event_in = world.event_interval


func _spawn_caches() -> void:
	for marker in _map_nodes("spawn_cache"):
		var source: String = marker.get_meta("loot_source", "cache")
		var cache := spawn_container(world.roll_loot(source, rng), false, "cache", marker.global_position)
		_caches.append({"container": cache, "source": source, "refill_in": -1.0})


func _physics_process(delta: float) -> void:
	if world == null:
		return
	clock += delta
	_tick_sign_outs(delta)
	_tick_toys(delta)
	if mode != Mode.CLIENT:
		_tick_war(delta)
	map.set_meta("war_intensity", war.intensity)
	map.set_meta("war_centre", war.centre)
	if mode == Mode.CLIENT:
		return
	# DEV MODE
	if mode == Mode.SOLO and not dev_cheats.is_empty():
		_apply_dev_cheats()
	if world.safe_zone:
		_keep_everyone_safe()
		return
	_tick_strongpoints(delta)
	_tick_events(delta)
	_tick_caches(delta)
	armory.tick(delta)
	_tick_bots(delta)
	_tick_detail(delta)
	_tick_vehicles(delta)


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
		if point.tick(delta, present):
			_on_strongpoint_taken(point, inside, loser, lost_by_player)
		elif point.contested != was_contested:
			point.refresh_look()
		# Players fighting over a site are part of the war.
		if point.contested and present.values().any(func(who: Dictionary) -> bool: return who.player):
			war.report_clash(point.global_position, delta)
	_tick_assaults(delta)


func _on_strongpoint_taken(point: Strongpoint, inside: Array[Actor], loser: String, lost_by_player: bool) -> void:
	# Bots trading a site among themselves is not news.
	if point.holder_is_player or lost_by_player:
		var line := "%s took %s" % [point.holder_name, point.title]
		if loser != "":
			line += " from %s" % loser
		war_feed.emit(line.left(1).to_upper() + line.substr(1))
		war.report_capture(point.global_position)
	if point.holder_is_player:
		for actor in inside:
			var state := state_for(actor)
			if state == null:
				continue
			var paid := renown.award(state.owner, renown.strongpoint_taken)
			_pay_scrip(state, Economy.STRONGPOINT_SCRIP)
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
		if is_instance_valid(bot) and not bot.is_dead and bot.has_node("Brain"):
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
		if clock >= float(event.ends) or _event_over():
			end_event(clock >= float(event.ends))
		return
	_event_in -= delta * (1.0 + war.intensity)
	if _event_in <= 0.0:
		start_event("warlord" if rng.randf() < 0.5 else "supply_pod")


## Starts a world event now. Returns false when one is running or the map
## has nowhere to put it.
func start_event(kind: String) -> bool:
	var spawns := _map_nodes("spawn_bot")
	if not event.is_empty() or spawns.is_empty():
		return false
	_event_in = world.event_interval
	var at: Vector3
	if kind == "warlord":
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
	if timed_out:
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
	if event.kind == "warlord":
		return warlords.is_empty()
	return not is_instance_valid(_event_pod) or _event_pod.items.is_empty()


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
			container.changed.emit()
			armory.on_cache_refilled(container.global_position)


## Every dead bot is replaced, so the world never runs out of enemies.
func _tick_bots(delta: float) -> void:
	for i in range(_bot_respawns.size() - 1, -1, -1):
		_bot_respawns[i] -= delta
		if _bot_respawns[i] > 0.0:
			continue
		_bot_respawns.remove_at(i)
		var spawns := _reinforcement_spawns()
		if not spawns.is_empty():
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
	if world.bot_count <= 0:
		return 0
	return world.bot_count + roundi(maxi(world.war_reinforcements, 0) * war.intensity)


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
	for i in bots.size():
		var bot := bots[i]
		var nearest := INF
		for at in watchers:
			nearest = minf(nearest, at.distance_squared_to(bot.global_position))
		if nearest <= full_detail_range * full_detail_range:
			bot.thin(1)
		elif nearest <= half_detail_range * half_detail_range:
			bot.thin(2, i)
		else:
			bot.thin(far_detail_step, i)


## The bots alive that belong to the world itself, not to an event.
func _standing_bots() -> int:
	var count := 0
	for bot in bots:
		if not _event_bots.has(bot):
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
		if alive.has(bot.faction) and not _event_bots.has(bot):
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
## Every few seconds each faction is given its orders: a garrison for every
## site it holds, nearest bots first, and everyone else against the site
## nearest to its own that it does not hold. Massed, so the armies meet.
func _tick_orders(delta: float) -> void:
	if not world.bots_contest_sites or strongpoints.is_empty():
		return
	_orders_in -= delta
	if _orders_in > 0.0:
		return
	_orders_in = ORDERS_EVERY
	var armies := {}
	for bot in bots:
		if is_instance_valid(bot) and not bot.is_dead and bot.has_node("Brain") and not _event_bots.has(bot) \
				and float(_busy_until.get(bot, 0.0)) <= clock:
			if not armies.has(bot.faction):
				armies[bot.faction] = []
			armies[bot.faction].append(bot)
	for bot: Actor in _orders.keys():
		if not is_instance_valid(bot) or bot.is_dead:
			_orders.erase(bot)
	for faction: String in armies:
		var spare: Array = armies[faction]
		var held := strongpoints.filter(func(p: Strongpoint) -> bool: return p.holder == "faction:" + faction)
		for point: Strongpoint in held:
			spare.sort_custom(func(a: Actor, b: Actor) -> bool:
				return a.global_position.distance_squared_to(point.global_position) \
						< b.global_position.distance_squared_to(point.global_position))
			for i in mini(world.garrison_size, spare.size()):
				_order(spare.pop_front(), point)
		var target := _army_target(faction, held, spare)
		if target != null:
			for bot: Actor in spare:
				_order(bot, target)


## The site a faction goes for next: of those it does not hold, the one
## nearest to the ground it already has (or to its bots, if it has none).
func _army_target(faction: String, held: Array, army: Array) -> Strongpoint:
	var from := Vector3.ZERO
	var anchors: Array = held if not held.is_empty() else army
	if anchors.is_empty():
		return null
	for node: Node3D in anchors:
		from += node.global_position
	from /= anchors.size()
	var best: Strongpoint = null
	for point in strongpoints:
		if point.holder == "faction:" + faction:
			continue
		if best == null or point.global_position.distance_squared_to(from) \
				< best.global_position.distance_squared_to(from):
			best = point
	return best


func _order(bot: Actor, point: Strongpoint) -> void:
	if _orders.get(bot) == point:
		return
	_orders[bot] = point
	(bot.get_node("Brain") as BotBrain).post_to(point.global_position, point.radius)


## Vehicles nobody rides are cleared away, and empty parking spots get a new one.
func _tick_vehicles(delta: float) -> void:
	for vehicle in vehicles.duplicate():
		if vehicle.get("rider") != null:
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
		if spot.empty_for >= world.vehicle_respawn_time:
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
## drops the player back in. `p_kit` empty means the world's free scrap kit.
## `p_owner` says whose life this is (an account id), so renown carries over
## from their earlier lives here; without it every life is a stranger's.
## `p_renown` is their lifetime renown, which sets the rank others see.
func add_player(p_kit: Array = [], p_mastery: Dictionary = {}, p_name := "Raider",
		p_owner := "", p_renown := 0, p_drop := "") -> Actor:
	var state := PlayerState.new()
	state.kit.assign(p_kit if not p_kit.is_empty() else world.starter_loadout())
	state.picks = p_mastery
	var spawns := _map_nodes("spawn_player")
	var marker := 0
	# Anyone arriving in a world that is already running lands away from the
	# fighting, and cannot be hurt for a moment.
	var arriving := mode == Mode.SERVER or _player_count > 0
	if mode == Mode.SOLO and player != null:
		_remove_actor(player)
	if arriving and not spawns.is_empty():
		marker = _safest_spawn(spawns)
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
	if arriving and p_owner != "":
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
	var actor := Actor.new()
	actor.name = "Player" if _player_count == 0 else "Player%d" % _player_count
	_player_count += 1
	actor.is_player = mode == Mode.SOLO
	actor.display_name = p_name
	add_child(actor)
	# Spread out players who arrive at the same spawn point.
	if mode == Mode.SERVER:
		at += Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
	actor.global_position = _stand(at)
	Loadout.equip(actor, state.kit)
	actor.weapons_locked = world.safe_zone
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
	actor.health.damaged.connect(func(_info: DamageInfo) -> void: _mark_combat(state))
	actor.hit_confirmed.connect(func(_target: Actor, _info: DamageInfo, _lethal: bool) -> void:
		_mark_combat(state))
	world.on_spawn(actor)
	_publish_standing()
	actor_spawned.emit(actor)
	# Their own vehicle, if they brought one, rides on their watch as a toy.
	for id in state.kit:
		if ItemDB.has_tag(id, "vehicle"):
			state.deployed_vehicles.append(id)
			state.stowed.append(id)
	watch_changed.emit(actor)
	return actor


## The spawn point farthest from everyone already in the raid, so nobody
## joins into the middle of a fight.
func _safest_spawn(spawns: Array[Node3D]) -> int:
	var others: Array[Actor] = []
	others.append_array(bots)
	others.append_array(active_players())
	var best := 0
	var best_distance := -1.0
	for i in spawns.size():
		var nearest := INF
		for other in others:
			if not other.is_dead:
				nearest = minf(nearest, spawns[i].global_position.distance_to(other.global_position))
		if nearest > best_distance:
			best_distance = nearest
			best = i
	return best


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
				if vehicle.get("rider") != null:
					vehicle.call("dismount")
				vehicles.erase(vehicle)
				vehicle_removed.emit(vehicle)
				vehicle.queue_free()
		_remove_actor(actor)
		return
	if not state.finished and not actor.is_dead:
		begin_sign_out(actor, true)
		return
	players.erase(state)


## Starts a player's sign-out. It takes `WorldDef.sign_out_time` seconds and
## taking or dealing damage cancels it, so it cannot be started in a fight.
## `forced` is for a player who is gone: it cannot be cancelled, and the body
## stands still until it ends. Returns false if it did not start.
func begin_sign_out(actor: Actor, forced := false) -> bool:
	var state := state_for(actor)
	if state == null or state.finished or actor.is_dead or mode == Mode.CLIENT:
		return false
	var fighting := clock - state.last_combat < world.combat_time
	if forced:
		var wait := world.combat_log_time if fighting else world.sign_out_time
		if state.sign_out_left >= 0.0:
			wait = minf(wait, state.sign_out_left)
		var yaw := actor.cmd.yaw
		actor.cmd.apply_array(ActorCommand.new().to_array())
		actor.cmd.yaw = yaw
		state.sign_out_forced = true
		state.sign_out_left = wait
	elif state.sign_out_left >= 0.0:
		return true
	elif fighting:
		actor.notice.emit("You cannot sign out in a fight")
		return false
	else:
		state.sign_out_left = world.sign_out_time
		actor.notice.emit("Signing out. Stay out of trouble for %d seconds" % ceili(world.sign_out_time))
	state.sign_out_total = state.sign_out_left
	sign_out_changed.emit(actor, state.sign_out_left)
	return true


func cancel_sign_out(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null or state.sign_out_left < 0.0 or state.sign_out_forced or mode == Mode.CLIENT:
		return
	state.sign_out_left = -1.0
	actor.notice.emit("Sign-out cancelled")
	sign_out_changed.emit(actor, -1.0)


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
		# A Phase Cloak never hides a sign-out: the countdown waits for it.
		if state.actor != null and is_instance_valid(state.actor) and state.actor.is_cloaked():
			continue
		state.sign_out_left = maxf(0.0, state.sign_out_left - delta)
		# A client only shows the countdown. The server decides when it ends.
		if state.sign_out_left <= 0.0 and mode != Mode.CLIENT:
			_leave(state)


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
## event running. Nothing here says who or where anyone is.
func status() -> Dictionary:
	var bounty := 0
	var fighting := active_players()
	for actor in fighting:
		if is_instance_valid(actor):
			bounty = maxi(bounty, actor.bounty)
	return {"players": fighting.size(), "war": snappedf(war.intensity, 0.05), "level": war.level_name(),
			"bounty": bounty, "event": str(event.get("title", ""))}


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
	for i in world.bot_count:
		_add_bot(spawns[i % spawns.size()])


## A new bot with a brain, at a spawn marker.
func _add_bot(marker: Node3D, warlord := false) -> Actor:
	var at := marker.global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	var bot := spawn_bot("Bot%d" % _bot_count, _stand(at), rng.randi(), warlord, marker.get_meta("faction", ""))
	if warlord:
		# What a warlord carries is worth the fight.
		for id in world.roll_war_loot("bot", rng, 1.0) + world.roll_war_loot("cache", rng, 1.0):
			bot.inventory.add_item(id)
		# A boss may carry an artifact, the long chase (DESIGN.md section 6).
		var relic := world.roll_artifact(rng, world.warlord_artifact_chance)
		if relic != "":
			bot.inventory.add_item(relic)
		# And what crafting runs on (DESIGN.md section 10).
		for id in world.roll_crafting_loot(rng, world.warlord_blueprint_chance, world.warlord_upgrade_data):
			bot.inventory.add_item(id)
	_bot_count += 1
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = rng.randi()
	bot.add_child(brain)
	bot.died.connect(_on_actor_died)
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
## with the server's seed to get the same bot.
func spawn_bot(bot_name: String, at: Vector3, equip_seed: int, warlord := false, faction := "") -> Actor:
	var bot := Actor.new()
	bot.name = bot_name
	if faction != "":
		bot.faction = faction
	add_child(bot)
	bot.global_position = at
	var equip_rng := RandomNumberGenerator.new()
	equip_rng.seed = equip_seed
	world.equip_bot(bot, equip_rng)
	if warlord:
		world.make_warlord(bot)
		warlords[bot] = true
	bot_seeds[bot] = equip_seed
	bots.append(bot)
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
	vehicle_spawned.emit(vehicle)
	return vehicle


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
	elif ItemDB.has_tag(item_id, "aircraft") and not world.open_skies:
		why = "No open sky for a jet here"
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
	var aim := actor.get_aim_dir()
	var from := actor.get_eye_position() + aim * 0.6 - Vector3(0.0, 0.25, 0.0)
	var toy_velocity := (aim + Vector3.UP * toy_lift).normalized() * toy_speed \
			+ Vector3(actor.velocity.x, 0.0, actor.velocity.z)
	fly_toy(item_id, from, toy_velocity, actor.cmd.yaw, state)
	toy_thrown.emit(actor, item_id, from, toy_velocity)
	watch_changed.emit(actor)
	return ""


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
	var why := ""
	if not actor.inventory.has_item(item_id):
		why = "That is not in your pack"
	elif not Loadout.summonable(item_id):
		why = "The watch cannot summon that"
	elif actor.weapons_locked:
		why = "Weapons are locked here"
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
	toys.append({"state": state, "id": item_id, "at": from, "velocity": toy_velocity, "age": 0.0,
			"heading": heading, "node": node})


## Flies every thrown toy along its arc. It bounces off walls, and where it
## comes down on ground a vehicle could stand on, it unpacks.
func _tick_toys(delta: float) -> void:
	if toys.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for toy in toys.duplicate():
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
		node.rotation += Vector3(7.0, 3.0, 0.0) * delta
		if landed or toy.age >= toy_max_flight or next.y < -30.0:
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
	if room == Vector3.ZERO:
		room = unpack_room
	var box := BoxShape3D.new()
	box.size = room
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	# Lifted clear of the ground it stands on, so a slope does not count.
	query.transform = Transform3D(Basis(Vector3.UP, heading), at + Vector3(0.0, room.y * 0.5 + 0.45, 0.0))
	query.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ACTORS | VehicleScript.LAYER_VEHICLES
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


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
	elif vehicle.get("rider") != null or float(vehicle.get("unpack_left")) > 0.0:
		why = "Someone is riding it"
	elif state.stowed.size() >= watch_capacity:
		why = "Your watch is full"
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


## Takes a vehicle out of the world, putting its rider on their feet.
func remove_vehicle(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle):
		return
	if vehicle.get("rider") != null:
		vehicle.call("dismount")
	vehicles.erase(vehicle)
	_idle.erase(vehicle)
	vehicle_removed.emit(vehicle)
	vehicle.queue_free()


func spawn_container(items: Array, is_bag: bool, label: String, at: Vector3) -> LootContainer:
	var container := LootContainer.new()
	container.setup(items, is_bag, label)
	add_child(container)
	container.global_position = at
	container_spawned.emit(container)
	return container


func _on_actor_died(actor: Actor, info: DamageInfo) -> void:
	world.on_death(actor, info)
	var drops := actor.get_drop_items()
	if state_for(actor) != null and world.keep_gear_on_death:
		# A gentler world: a player's equipped gear goes home, not in the bag.
		drops.assign(actor.inventory.items)
	# Power weapons never go in a bag: they are left on a rack, shots and all.
	armory.on_death(actor, drops)
	var dead := state_for(actor)
	var carried := dead.scrip if dead != null and mode != Mode.CLIENT else 0
	if not drops.is_empty() or carried > 0:
		var bag := spawn_container(drops, true, "%s's bag" % actor.display_name if carried <= 0
				else "%s's bag, %d scrip" % [actor.display_name, carried], actor.global_position)
		if carried > 0:
			# What they carried lies with the bag for whoever gets there first.
			bag.scrip = carried
			bag.scrip_taken.connect(_on_scrip_taken)
			dead.scrip_lost = carried
			dead.scrip = 0
			actor.scrip = 0
		# Bags do not pile up forever in a world that never ends.
		if mode != Mode.CLIENT:
			get_tree().create_timer(world.bag_lifetime, false, true).timeout.connect(func() -> void:
				if is_instance_valid(bag):
					bag.queue_free())
	var killer := state_for(info.source as Actor) if info.source is Actor else null
	var state := state_for(actor)
	if killer != null and killer.actor == actor:
		killer = null
	var by: String = (info.source as Actor).display_name if info.source is Actor else ""
	var gained := 0
	if mode != Mode.CLIENT:
		gained = _settle_renown(state, killer, actor, by)
		if killer != null:
			var pay := Economy.KILL_BOUNTY
			if warlords.has(actor):
				pay += Economy.WARLORD_SCRIP
			elif state != null and not _wears_scrap(actor):
				pay = Economy.PLAYER_KILL_SCRIP
			_pay_scrip(killer, pay)
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
		_finish_player(state, "died", info.kind, by)
		_publish_standing()
		# The local player's body stays for the camera until they drop in again.
		if mode == Mode.SOLO and actor == player:
			return
	else:
		bots.erase(actor)
		warlords.erase(actor)
		# A world event's bots are extra: nobody takes their place. Neither
		# are reinforcements replaced once the war has cooled.
		if mode != Mode.CLIENT and not _event_bots.has(actor):
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
	var state := state_for(actor)
	if state != null:
		players.erase(state)
		if is_instance_valid(state.mastery):
			state.mastery.queue_free()
	bots.erase(actor)
	bot_seeds.erase(actor)
	warlords.erase(actor)
	_orders.erase(actor)
	_busy_until.erase(actor)
	actor_removed.emit(actor)
	actor.queue_free()


func _on_actor_banked(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null or state.finished or actor.is_dead:
		return
	var items := Depot.bankable(actor)
	if items.is_empty() and state.scrip <= 0:
		return
	if state.scrip > 0:
		# Banked scrip is safe: it is paid out when this life ends, however it ends.
		actor.notice.emit("Banked %d scrip" % state.scrip)
		state.scrip_banked += state.scrip
		state.scrip = 0
		actor.scrip = 0
	if items.is_empty():
		return
	for id in items:
		actor.inventory.remove_item(id)
	state.banked.append_array(items)
	actor.notice.emit("Banked %s (worth %d)" % [ItemDB.summarize(items), ItemDB.total_value(items)])
	if apply_to_profile:
		Profile.add_to_stash(items)
	player_banked.emit(actor, items)


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


func _finish_player(state: PlayerState, outcome: String, cause: String, killed_by: String) -> void:
	if state.finished:
		return
	state.finished = true
	state.sign_out_left = -1.0
	var actor := state.actor
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
	# Power weapons are raid-only: they never come home and are never counted
	# as lost. The gun left on a rack for one is what was risked.
	for list: Array[String] in [kept, brought_home, lost]:
		list.assign(list.filter(func(id: String) -> bool: return not ItemDB.has_tag(id, "power")))
	var result := {
		"outcome": outcome,
		"cause": cause,
		"killed_by": killed_by,
		"world_id": world.id,
		"loot": loot,
		"kept_gear": kept,
		"brought_home": brought_home,
		"loot_value": ItemDB.total_value(loot),
		"lost": lost,
		"banked": state.banked.duplicate(),
		"banked_value": ItemDB.total_value(state.banked),
		"kills": state.kills,
		# Scrip: carried home (nothing if they died), banked on the way, and
		# dropped with the body.
		"scrip": state.scrip if left else 0,
		"scrip_banked": state.scrip_banked,
		"scrip_lost": state.scrip_lost,
		"mastery_xp": state.mastery.report(),
	}
	var standing := renown.get_standing(state.owner)
	if standing != null:
		# What this life added to lifetime renown, what dying took from the
		# session, and where the session stands now.
		result["renown"] = standing.earned
		result["renown_lost"] = state.renown_lost
		result["renown_now"] = standing.renown
	if apply_to_profile:
		apply_result(result)
	player_finished.emit(actor, result)


## Writes a finished life into the local profile: what came home, and the record.
static func apply_result(result: Dictionary) -> void:
	var home: Array = result.get("brought_home", [])
	if not home.is_empty():
		Profile.add_to_stash(home)
	Profile.record_raid(result)


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
	## `Raid.clock` when they last gave or took a hit.
	var last_combat := -INF
	var finished := false
