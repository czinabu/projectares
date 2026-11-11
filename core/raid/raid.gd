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
signal actor_spawned(actor: Actor)
signal actor_removed(actor: Actor)
signal container_spawned(container: LootContainer)
signal vehicle_spawned(vehicle: Node3D)
signal vehicle_removed(vehicle: Node3D)

## Bots never start closer to the player than this, so a raid does not open with a fight.
const MIN_BOT_SPAWN_DISTANCE := 40.0
## A vehicle this close to its parking spot counts as still parked there.
const PARKED_DISTANCE := 6.0
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MasteryTracker := preload("res://core/progression/mastery_tracker.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")

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
## When false, the raid reports results but leaves the stash alone, so a server
## never writes to a profile that is not the player's.
var apply_to_profile := true
## Server: every player starts at the same spawn point, as one squad.
var squad_spawn := false
var _squad_marker := -1
var _player_count := 0
var _bot_count := 0
## One per cache: { container, source, refill_in }.
var _caches: Array[Dictionary] = []
## Seconds until each dead bot is replaced.
var _bot_respawns: Array[float] = []
## One per vehicle marker: { marker, source, vehicle, empty_for }.
var _parking: Array[Dictionary] = []
## Vehicle -> seconds since anyone rode it.
var _idle := {}


## Call after the Raid is in the scene tree. A fixed seed makes it repeatable.
## `p_kit` is the gear the player deploys with; empty means the free scrap kit.
## `p_mastery` maps mastery track -> picked variant id (see MasteryBook.active_picks).
## `p_owner` and `p_renown` are the player's renown key and lifetime renown (see `add_player`).
func start(p_world: WorldDef, p_seed: int = -1, p_kit: Array = [], p_mastery: Dictionary = {},
		p_owner := "", p_renown := 0) -> void:
	mode = Mode.SOLO
	_setup(p_world, p_seed)
	_spawn_caches()
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

	map = world.create_map()
	map.name = "Map"
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
	if mode == Mode.CLIENT:
		return
	_tick_caches(delta)
	_tick_bots(delta)
	_tick_vehicles(delta)


## An emptied cache fills up again after a while.
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
			container.set_items(world.roll_loot(cache.source, rng))
			container.changed.emit()


## Every dead bot is replaced, so the world never runs out of enemies.
func _tick_bots(delta: float) -> void:
	for i in range(_bot_respawns.size() - 1, -1, -1):
		_bot_respawns[i] -= delta
		if _bot_respawns[i] > 0.0:
			continue
		_bot_respawns.remove_at(i)
		var spawns := _map_nodes("spawn_bot")
		if not spawns.is_empty():
			_add_bot(spawns[_farthest_from_players(spawns)])


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
		p_owner := "", p_renown := 0) -> Actor:
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


## For a dropped connection. Nobody escapes a fight by quitting: the body
## stays where it stood, helpless, for the sign-out time (longer if they were
## in a fight). If it survives, everything on it goes home.
func remove_player(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null:
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
func _add_bot(marker: Node3D) -> Actor:
	var at := marker.global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	var bot := spawn_bot("Bot%d" % _bot_count, at, rng.randi())
	_bot_count += 1
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = rng.randi()
	bot.add_child(brain)
	bot.died.connect(_on_actor_died)
	world.on_spawn(bot)
	actor_spawned.emit(bot)
	return bot


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
		_parking.append({"marker": marker, "source": source, "vehicle": _park_vehicle(marker, source),
				"empty_for": 0.0})


func _park_vehicle(marker: Node3D, source: String) -> Node3D:
	for id in world.roll_loot(source, rng):
		if ItemDB.has_tag(id, "vehicle"):
			return spawn_vehicle(id, marker.global_position + Vector3(0, 0.3, 0), marker.rotation.y)
	return null


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
	if not drops.is_empty():
		var bag := spawn_container(drops, true, "%s's bag" % actor.display_name, actor.global_position)
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
		if mode != Mode.CLIENT:
			_bot_respawns.append(world.bot_respawn_time)
	get_tree().create_timer(4.0).timeout.connect(_remove_actor.bind(actor))


## Pays out renown for a death and tells the world about it. Returns what
## the killer gained.
func _settle_renown(victim: PlayerState, killer: PlayerState, actor: Actor, by: String) -> int:
	var gained := 0
	if victim == null:
		if killer != null:
			gained = renown.bot_killed(killer.owner)
			_publish_standing()
		return gained
	var paid := renown.player_died(victim.owner, killer.owner if killer != null else "",
			_wears_scrap(actor))
	victim.renown_lost = paid.lost
	gained = paid.gain
	if killer == null:
		war_feed.emit("%s was killed by %s" % [actor.display_name, by] if by != ""
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
	actor_removed.emit(actor)
	actor.queue_free()


func _on_actor_banked(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null or state.finished or actor.is_dead:
		return
	var items := Depot.bankable(actor)
	if items.is_empty():
		return
	for id in items:
		actor.inventory.remove_item(id)
	state.banked.append_array(items)
	actor.notice.emit("Banked %s (worth %d)" % [ItemDB.summarize(items), ItemDB.total_value(items)])
	if apply_to_profile:
		Profile.add_to_stash(items)
	player_banked.emit(actor, items)


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
	elif world.keep_gear_on_death:
		lost.assign(actor.inventory.items)
		kept.assign(actor.gear_items.filter(func(id: String) -> bool:
			return not ItemDB.has_tag(id, "starter")))
		brought_home.assign(kept)
	else:
		lost.assign(actor.get_drop_items())
	# A vehicle you brought is lost unless you rode it (or another) back out.
	var left_behind := state.deployed_vehicles.duplicate()
	left_behind.erase(state.rode_home)
	lost.append_array(left_behind)
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
	var kit: Array[String] = []
	var mastery: MasteryTracker
	## Mastery variants the player deployed with (track -> variant id).
	var picks := {}
	var kills := 0
	## Vehicle items the player deployed with. Lost unless they leave riding one.
	var deployed_vehicles: Array[String] = []
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
