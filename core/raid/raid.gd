class_name Raid
extends Node3D
## One run of a world: builds the map, spawns everyone, tracks the timer, and
## decides how the raid ends. It knows nothing about any specific world; it only
## uses the WorldDef contract. It also knows nothing about cameras or the HUD,
## so the same class can run on a headless server.

signal ended(result: Dictionary)
## A player's run is over (died or extracted). In a solo raid this fires
## together with `ended`. On a server the raid carries on for everyone else.
signal player_finished(actor: Actor, result: Dictionary)
signal actor_spawned(actor: Actor)
signal actor_removed(actor: Actor)
signal container_spawned(container: LootContainer)
signal vehicle_spawned(vehicle: Node3D)
signal vehicle_removed(vehicle: Node3D)

## Bots never start closer to the player than this, so a raid does not open with a fight.
const MIN_BOT_SPAWN_DISTANCE := 40.0
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MasteryTracker := preload("res://core/progression/mastery_tracker.gd")

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
var exits: Array[ExtractionZone] = []
var vehicles: Array[Node3D] = []
var time_left := 0.0
var kills := 0
var is_over := false
var rng := RandomNumberGenerator.new()
## The seed each bot was equipped with, so a client can rebuild the same bot.
var bot_seeds := {}
## The local player's mastery tracker.
var mastery: MasteryTracker
## When false, the raid reports results but leaves the stash alone, so a server
## never writes to a profile that is not the player's.
var apply_to_profile := true
## Server: every player starts at the same spawn point, as one squad.
var squad_spawn := false
var _squad_marker := -1
var _player_count := 0


## Call after the Raid is in the scene tree. A fixed seed makes it repeatable.
## `p_kit` is the gear the player deploys with; empty means the free scrap kit.
## `p_mastery` maps mastery track -> picked variant id (see MasteryBook.active_picks).
func start(p_world: WorldDef, p_seed: int = -1, p_kit: Array = [], p_mastery: Dictionary = {}) -> void:
	mode = Mode.SOLO
	_setup(p_world, p_seed)
	_spawn_caches()
	add_player(p_kit, p_mastery, "You")
	_spawn_bots()
	_spawn_map_vehicles()


## Starts the raid as the authority for an online game. Players are added with
## `add_player` as they connect.
func start_server(p_world: WorldDef, p_seed: int = -1) -> void:
	mode = Mode.SERVER
	apply_to_profile = false
	_setup(p_world, p_seed)
	_spawn_caches()
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
	time_left = world.raid_duration

	map = world.create_map()
	map.name = "Map"
	add_child(map)
	if mode != Mode.CLIENT and map.has_method("bake_navigation"):
		map.call("bake_navigation")

	for node in _map_nodes("exit"):
		var zone := node as ExtractionZone
		if zone:
			zone.hold_time = world.exit_hold_time
			if mode != Mode.CLIENT:
				zone.actor_extracted.connect(_on_actor_extracted)
			exits.append(zone)


func _spawn_caches() -> void:
	for marker in _map_nodes("spawn_cache"):
		var source: String = marker.get_meta("loot_source", "cache")
		spawn_container(world.roll_loot(source, rng), false, "cache", marker.global_position)


func _physics_process(delta: float) -> void:
	if is_over or world == null or mode == Mode.CLIENT:
		return
	time_left -= delta
	if time_left <= 0.0:
		for state in players.duplicate():
			if not state.finished and not state.actor.is_dead:
				state.actor.kill("storm")
		if mode == Mode.SERVER:
			is_over = true


## Exit zone progress for the player, 0..1.
func extract_progress() -> float:
	var best := 0.0
	if player == null:
		return best
	for zone in exits:
		best = maxf(best, zone.progress_for(player))
	return best


## Adds a player and returns their actor. In a solo raid the first one becomes
## `player`. `p_kit` empty means the world's free scrap kit.
func add_player(p_kit: Array = [], p_mastery: Dictionary = {}, p_name := "Raider") -> Actor:
	var state := PlayerState.new()
	state.kit.assign(p_kit if not p_kit.is_empty() else world.starter_loadout())
	state.picks = p_mastery
	var spawns := _map_nodes("spawn_player")
	var marker := rng.randi() % maxi(spawns.size(), 1)
	if mode == Mode.SERVER and not spawns.is_empty():
		marker = _safest_spawn(spawns)
	if squad_spawn:
		if _squad_marker < 0:
			_squad_marker = marker
		marker = _squad_marker
	var at: Vector3 = spawns[marker].global_position if not spawns.is_empty() else Vector3.ZERO
	var actor := Actor.new()
	actor.name = "Player" if _player_count == 0 else "Player%d" % _player_count
	_player_count += 1
	actor.is_player = mode == Mode.SOLO
	actor.display_name = p_name
	add_child(actor)
	# Spread out players who arrive at the same spawn point.
	if mode == Mode.SERVER:
		at += Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
	actor.global_position = at
	Loadout.equip(actor, state.kit)
	state.actor = actor
	state.mastery = MasteryTracker.new()
	state.mastery.name = "Mastery" if players.is_empty() else "Mastery%d" % _player_count
	add_child(state.mastery)
	state.mastery.setup(actor, p_mastery)
	players.append(state)
	if mode == Mode.SOLO and player == null:
		player = actor
		mastery = state.mastery
	actor.died.connect(_on_actor_died)
	world.on_spawn(actor)
	actor_spawned.emit(actor)
	# Their own vehicle, if they brought one, is parked beside them.
	for id in state.kit:
		if ItemDB.has_tag(id, "vehicle"):
			state.deployed_vehicles.append(id)
			var side := Basis(Vector3.UP, actor.cmd.yaw) * Vector3(2.5, 0.3, -1.0)
			spawn_vehicle(id, actor.global_position + side, actor.cmd.yaw)
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


## Takes a player out of the raid without a result, for a dropped connection.
## Their gear falls where they stood.
func remove_player(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null:
		return
	if not state.finished and not actor.is_dead:
		actor.kill("disconnect")
		return
	players.erase(state)


func state_for(actor: Actor) -> PlayerState:
	for state in players:
		if state.actor == actor:
			return state
	return null


## Players still in the raid.
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
		var marker: Node3D = spawns[i % spawns.size()]
		var at := marker.global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		var bot := spawn_bot("Bot%d" % i, at, rng.randi())
		var brain := BotBrain.new()
		brain.name = "Brain"
		brain.seed_value = rng.randi()
		bot.add_child(brain)
		bot.died.connect(_on_actor_died)
		world.on_spawn(bot)
		actor_spawned.emit(bot)


## Creates a bot equipped from `equip_seed`, with no brain. A client calls this
## with the server's seed to get the same bot.
func spawn_bot(bot_name: String, at: Vector3, equip_seed: int) -> Actor:
	var bot := Actor.new()
	bot.name = bot_name
	add_child(bot)
	bot.global_position = at
	var equip_rng := RandomNumberGenerator.new()
	equip_rng.seed = equip_seed
	world.equip_bot(bot, equip_rng)
	bot_seeds[bot] = equip_seed
	bots.append(bot)
	return bot


## Fills the map's vehicle markers with abandoned vehicles anyone can take.
func _spawn_map_vehicles() -> void:
	for marker in _map_nodes("spawn_vehicle"):
		var source: String = marker.get_meta("loot_source", "vehicle")
		for id in world.roll_loot(source, rng):
			if ItemDB.has_tag(id, "vehicle"):
				spawn_vehicle(id, marker.global_position + Vector3(0, 0.3, 0), marker.rotation.y)
				break


func spawn_vehicle(id: String, at: Vector3, heading: float) -> Node3D:
	var vehicle := VehicleScript.new()
	vehicle.name = "Vehicle%d" % vehicles.size()
	vehicle.setup(id)
	vehicle.rotation.y = heading
	add_child(vehicle)
	vehicle.global_position = at
	vehicles.append(vehicle)
	vehicle_spawned.emit(vehicle)
	return vehicle


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
	if not drops.is_empty():
		spawn_container(drops, true, "%s's bag" % actor.display_name, actor.global_position)
	var killer := state_for(info.source as Actor) if info.source is Actor else null
	if killer != null and killer.actor != actor:
		killer.kills += 1
		if killer.actor == player:
			kills += 1
		killer.actor.notice.emit("Killed %s" % actor.display_name)
	var state := state_for(actor)
	if state != null:
		_finish_player(state, "died", info.kind)
		if mode == Mode.SOLO:
			return
	else:
		bots.erase(actor)
	get_tree().create_timer(4.0).timeout.connect(_remove_actor.bind(actor))


func _remove_actor(actor: Actor) -> void:
	if not is_instance_valid(actor):
		return
	var state := state_for(actor)
	if state != null:
		players.erase(state)
	bots.erase(actor)
	bot_seeds.erase(actor)
	actor_removed.emit(actor)
	actor.queue_free()


func _on_actor_extracted(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null or state.finished or is_over:
		return
	world.on_extract(actor)
	# Everything carried comes home: surviving gear and the backpack, and the
	# vehicle they rode out on, whoever it belonged to.
	var ridden := actor.vehicle
	if ridden != null:
		state.extracted_vehicle = ridden.get("item_id")
	_finish_player(state, "extracted", "")
	if mode == Mode.SERVER:
		# They are gone from the raid, and so is the vehicle they rode out on.
		if ridden != null:
			ridden.call("dismount")
			vehicles.erase(ridden)
			vehicle_removed.emit(ridden)
			ridden.queue_free()
		_remove_actor(actor)


func _finish_player(state: PlayerState, outcome: String, cause: String) -> void:
	if state.finished:
		return
	state.finished = true
	var actor := state.actor
	var extracted := outcome == "extracted"
	var loot: Array[String] = []
	var kept: Array[String] = []
	var brought_home: Array[String] = []
	var lost: Array[String] = []
	if extracted:
		loot.assign(actor.inventory.items)
		kept.assign(actor.gear_items.filter(func(id: String) -> bool:
			return not ItemDB.has_tag(id, "starter")))
		brought_home.assign(actor.get_drop_items())
		if state.extracted_vehicle != "":
			kept.append(state.extracted_vehicle)
			brought_home.append(state.extracted_vehicle)
	else:
		lost.assign(actor.get_drop_items())
	# A vehicle you brought is lost unless you rode it (or another) back out.
	var left_behind := state.deployed_vehicles.duplicate()
	left_behind.erase(state.extracted_vehicle)
	lost.append_array(left_behind)
	var result := {
		"outcome": outcome,
		"cause": cause,
		"world_id": world.id,
		"loot": loot,
		"kept_gear": kept,
		"brought_home": brought_home,
		"loot_value": ItemDB.total_value(loot),
		"lost": lost,
		"kills": state.kills,
		"mastery_xp": state.mastery.report(extracted),
		"time_in_raid": world.raid_duration - time_left,
	}
	if apply_to_profile:
		apply_result(result)
	player_finished.emit(actor, result)
	if mode == Mode.SOLO and actor == player:
		is_over = true
		ended.emit(result)


## Writes a finished run into the local profile: what came home, and the record.
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


## One player's run: who they are, what they brought, and how they are doing.
class PlayerState:
	extends RefCounted

	var actor: Actor
	var kit: Array[String] = []
	var mastery: MasteryTracker
	## Mastery variants the player deployed with (track -> variant id).
	var picks := {}
	var kills := 0
	## Vehicle items the player deployed with. Lost unless they extract riding one.
	var deployed_vehicles: Array[String] = []
	var extracted_vehicle := ""
	var finished := false
