class_name NetSession
extends Node
## One end of an online raid: the server that runs it, or a client that plays in it.
##
## The server is the authority. It runs a `Raid` in SERVER mode, feeds each
## connected player's `ActorCommand` into their actor, and sends everyone the
## state of every actor many times a second.
##
## A client runs a `Raid` in CLIENT mode. Every actor in it simulates locally
## from commands: your own from your input, so it responds at once, and
## everyone else's from the commands the server relays, so their swings, shots
## and flight play out between updates. The server's positions, health and
## deaths then overwrite the local guess. Damage is never decided on a client
## (`Combat.authoritative` is false there).
##
## Each session owns its own multiplayer API rooted at itself, so it works
## anywhere in the scene tree and several can live in one process.

## Client: the raid view exists and your actor is in it.
signal joined(raid: Raid)
## Client: your run ended (died or extracted). The result is like a solo raid's.
signal run_finished(result: Dictionary)
## Client: could not connect, or the server refused.
signal failed(reason: String)
## Client: the connection dropped after joining.
signal disconnected
## Server: a fresh raid replaced a finished one.
signal raid_restarted(raid: Raid)

const DEFAULT_PORT := 24565
const PROTOCOL := 1
const MAX_KIT_ITEMS := 16
## Server physics ticks between state updates (2 = 30 a second).
const TICKS_PER_SNAPSHOT := 2
## Actors per state packet, to keep each one under the network's packet size.
const ACTORS_PER_PACKET := 5
## Position errors beyond this are fixed at once instead of blended.
const SNAP_DISTANCE := 5.0
## Your own actor is left alone inside this error, because the server's view
## of you is always slightly in the past.
const OWN_TOLERANCE := 1.5
## Notices the server passes on to a player. Others are produced locally.
const FORWARDED_NOTICES := ["Parry!", "Wrong side", "Guard broken", "Staggered", "Killed ", "Looted ",
		"Backpack full", "Someone is riding it"]

var is_server := false
var raid: Raid
var world_id := ""
## Server options, set before `host`: a bot count override (below zero keeps
## the world's own) and whether players spawn together.
var bot_count := -1
var squad_spawn := false
## Client: called with the server's world, returns the kit to deploy with.
var kit_provider := Callable()
var player_name := "Raider"
var mastery_picks := {}
## Client: the id of your own actor, and the kit you joined with.
var my_actor_id := -1
var my_kit: Array[String] = []

var _api: SceneMultiplayer
var _actors := {}        # id -> Actor
var _ids := {}           # Actor -> id
var _next_id := 1
var _peer_actor := {}    # peer id -> Actor (server)
var _actor_peer := {}    # Actor -> peer id (server)
var _joined_peers: Array[int] = []
var _pending_input := {} # peer id -> command array (server)
var _one_shots := {}     # actor id -> accumulated one-shot flags (server)
var _switches := {}      # actor id -> last weapon switch since the snapshot
var _dead_kind := {}     # actor id -> damage kind that killed them
var _latest := {}        # actor id -> newest state entry (client)
var _containers := {}    # container id -> LootContainer
var _container_ids := {} # LootContainer -> id
var _vehicles := {}      # vehicle id -> vehicle node
var _vehicle_ids := {}   # vehicle node -> id
var _vehicle_targets := {} # vehicle id -> newest state entry (client)
var _sent_kills := {}    # actor id -> kill count last sent (server)
var _tick := 0
var _had_players := false
var _restart_in := -1.0
var _finished := false


func _enter_tree() -> void:
	_api = SceneMultiplayer.new()
	_api.root_path = get_path()
	get_tree().set_multiplayer(_api, get_path())
	process_physics_priority = -20
	var late := LateTick.new()
	late.name = "LateTick"
	late.session = self
	add_child(late)


func _exit_tree() -> void:
	close()
	if not is_server:
		Combat.authoritative = true


# ---------------------------------------------------------------- server ----

## Starts a server running `p_world_id`. Returns OK or an error.
func host(p_world_id: String, port := DEFAULT_PORT, max_players := 8) -> Error:
	if Worlds.get_world(p_world_id) == null:
		return ERR_DOES_NOT_EXIST
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	is_server = true
	world_id = p_world_id
	Combat.authoritative = true
	_api.multiplayer_peer = peer
	_api.peer_connected.connect(_on_peer_connected)
	_api.peer_disconnected.connect(_on_peer_disconnected)
	_start_server_raid()
	return OK


func close() -> void:
	if _api and _api.multiplayer_peer and not _api.multiplayer_peer is OfflineMultiplayerPeer:
		_api.multiplayer_peer.close()
		_api.multiplayer_peer = OfflineMultiplayerPeer.new()


func _start_server_raid() -> void:
	_clear_tables()
	raid = Raid.new()
	raid.name = "Raid"
	add_child(raid)
	raid.actor_spawned.connect(_on_server_actor_spawned)
	raid.actor_removed.connect(_on_server_actor_removed)
	raid.player_finished.connect(_on_server_player_finished)
	raid.container_spawned.connect(_on_server_container_spawned)
	raid.vehicle_spawned.connect(_on_server_vehicle_spawned)
	raid.vehicle_removed.connect(_on_server_vehicle_removed)
	raid.squad_spawn = squad_spawn
	var world := Worlds.get_world(world_id)
	if bot_count >= 0:
		world.bot_count = bot_count
	raid.start_server(world)
	_had_players = false
	_restart_in = -1.0
	raid_restarted.emit(raid)


func _clear_tables() -> void:
	_actors.clear()
	_ids.clear()
	_peer_actor.clear()
	_actor_peer.clear()
	_joined_peers.clear()
	_pending_input.clear()
	_one_shots.clear()
	_switches.clear()
	_dead_kind.clear()
	_latest.clear()
	_containers.clear()
	_container_ids.clear()
	_vehicles.clear()
	_vehicle_ids.clear()
	_vehicle_targets.clear()
	_sent_kills.clear()


func _register(actor: Actor) -> int:
	var id := _next_id
	_next_id += 1
	_actors[id] = actor
	_ids[actor] = id
	return id


func _on_peer_connected(peer: int) -> void:
	_hello.rpc_id(peer, PROTOCOL, world_id)


func _on_peer_disconnected(peer: int) -> void:
	_joined_peers.erase(peer)
	_pending_input.erase(peer)
	var actor: Actor = _peer_actor.get(peer)
	if actor != null and is_instance_valid(actor) and raid != null:
		raid.remove_player(actor)
	_peer_actor.erase(peer)


func _on_server_actor_spawned(actor: Actor) -> void:
	var id := _register(actor)
	actor.died.connect(func(_a: Actor, info: DamageInfo) -> void: _dead_kind[id] = info.kind)
	for peer in _joined_peers:
		_send_spawn(peer, actor)


func _on_server_actor_removed(actor: Actor) -> void:
	if not _ids.has(actor):
		return
	var id: int = _ids[actor]
	for peer in _joined_peers:
		_despawn.rpc_id(peer, id)
	_ids.erase(actor)
	_actors.erase(id)
	_one_shots.erase(id)
	_switches.erase(id)
	_dead_kind.erase(id)
	_sent_kills.erase(id)
	var peer: int = _actor_peer.get(actor, 0)
	_actor_peer.erase(actor)
	if peer != 0 and _peer_actor.get(peer) == actor:
		_peer_actor.erase(peer)


func _on_server_container_spawned(container: LootContainer) -> void:
	var id := _next_id
	_next_id += 1
	_containers[id] = container
	_container_ids[container] = id
	container.changed.connect(func() -> void:
		for peer in _joined_peers:
			_container_items.rpc_id(peer, id, container.items))
	container.tree_exited.connect(func() -> void:
		if not _containers.has(id):
			return
		_containers.erase(id)
		_container_ids.erase(container)
		for peer in _joined_peers:
			_container_gone.rpc_id(peer, id))
	for peer in _joined_peers:
		_send_container(peer, id)


func _send_container(peer: int, id: int) -> void:
	var container: LootContainer = _containers[id]
	_container.rpc_id(peer, id, container.items, container.is_bag, container.label, container.global_position)


func _on_server_vehicle_spawned(vehicle: Node3D) -> void:
	var id := _next_id
	_next_id += 1
	_vehicles[id] = vehicle
	_vehicle_ids[vehicle] = id
	for peer in _joined_peers:
		_send_vehicle(peer, id)


func _on_server_vehicle_removed(vehicle: Node3D) -> void:
	if not _vehicle_ids.has(vehicle):
		return
	var id: int = _vehicle_ids[vehicle]
	_vehicle_ids.erase(vehicle)
	_vehicles.erase(id)
	for peer in _joined_peers:
		_vehicle_gone.rpc_id(peer, id)


func _send_vehicle(peer: int, id: int) -> void:
	var vehicle: Node3D = _vehicles[id]
	_vehicle.rpc_id(peer, id, vehicle.get("item_id"), vehicle.global_position, vehicle.get("heading"))


func _on_server_player_finished(actor: Actor, result: Dictionary) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer != 0 and peer in _api.get_peers():
		_run_finished.rpc_id(peer, result)


func _send_spawn(peer: int, actor: Actor) -> void:
	var state := raid.state_for(actor)
	var data := {}
	if state != null:
		data = {"kit": state.kit, "picks": state.picks}
	else:
		data = {"seed": raid.bot_seeds.get(actor, 0)}
	_spawn.rpc_id(peer, _ids[actor], "player" if state != null else "bot", actor.display_name,
			String(actor.name), actor.global_position, actor.cmd.yaw, data)


@rpc("any_peer", "call_remote", "reliable")
func _request_join(p_name: String, kit: Array, picks: Dictionary) -> void:
	if not is_server or raid == null:
		return
	var peer := _api.get_remote_sender_id()
	if _peer_actor.has(peer):
		return
	var clean: Array[String] = []
	for id: Variant in kit:
		if typeof(id) == TYPE_STRING and ItemDB.has_item(id) and clean.size() < MAX_KIT_ITEMS:
			clean.append(id)
	var clean_picks := {}
	for track: Variant in picks:
		if typeof(track) == TYPE_STRING and typeof(picks[track]) == TYPE_STRING:
			clean_picks[track] = picks[track]
	var shown := p_name.strip_edges().left(20)
	var actor := raid.add_player(clean, clean_picks, shown if shown != "" else "Raider")
	_peer_actor[peer] = actor
	_actor_peer[actor] = peer
	_had_players = true
	actor.hit_confirmed.connect(_on_server_hit_confirmed.bind(peer))
	actor.health.damaged.connect(func(info: DamageInfo) -> void:
		if peer in _api.get_peers():
			_hurt.rpc_id(peer, info.amount, info.kind))
	actor.notice.connect(func(text: String) -> void:
		if peer not in _api.get_peers():
			return
		for prefix: String in FORWARDED_NOTICES:
			if text.begins_with(prefix):
				_notice.rpc_id(peer, text)
				return)
	actor.inventory.changed.connect(func() -> void:
		if peer in _api.get_peers():
			_inventory.rpc_id(peer, actor.inventory.items))
	_joined_peers.append(peer)
	_welcome.rpc_id(peer, _ids[actor], raid.time_left)
	for other: Actor in _ids:
		if not other.is_dead:
			_send_spawn(peer, other)
	for id: int in _containers:
		_send_container(peer, id)
	for id: int in _vehicles:
		_send_vehicle(peer, id)
	for id: int in _sent_kills:
		_kills.rpc_id(peer, id, _sent_kills[id])


func _on_server_hit_confirmed(target: Actor, info: DamageInfo, lethal: bool, peer: int) -> void:
	if peer in _api.get_peers() and _ids.has(target):
		_hit_feedback.rpc_id(peer, _ids[target], info.amount, info.kind, lethal, info.blocked, info.parried)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_input(data: Array) -> void:
	if not is_server or data.size() != ActorCommand.ARRAY_SIZE:
		return
	var peer := _api.get_remote_sender_id()
	if not _peer_actor.has(peer):
		return
	# Several inputs can arrive between ticks: keep every press.
	if _pending_input.has(peer):
		var earlier: Array = _pending_input[peer]
		data[ActorCommand.FLAGS_INDEX] = int(data[ActorCommand.FLAGS_INDEX]) \
				| (int(earlier[ActorCommand.FLAGS_INDEX]) & ActorCommand.ONE_SHOT_MASK)
		if int(data[ActorCommand.SWITCH_INDEX]) < 0:
			data[ActorCommand.SWITCH_INDEX] = earlier[ActorCommand.SWITCH_INDEX]
	_pending_input[peer] = data


func _server_early_tick() -> void:
	if raid == null:
		return
	for peer: int in _peer_actor:
		var actor: Actor = _peer_actor[peer]
		if not is_instance_valid(actor) or actor.is_dead:
			continue
		actor.cmd.clear_one_shots()
		if _pending_input.has(peer):
			actor.cmd.apply_array(_pending_input[peer])
			_pending_input.erase(peer)


func _server_late_tick(delta: float) -> void:
	if raid == null:
		return
	for id: int in _actors:
		var actor: Actor = _actors[id]
		_one_shots[id] = int(_one_shots.get(id, 0)) | (actor.cmd.flags() & ActorCommand.ONE_SHOT_MASK)
		if actor.cmd.switch_weapon >= 0:
			_switches[id] = actor.cmd.switch_weapon
	_tick += 1
	if _tick % TICKS_PER_SNAPSHOT == 0 and not _joined_peers.is_empty():
		var entries: Array = []
		for id: int in _actors:
			var actor: Actor = _actors[id]
			var cmd := actor.cmd.to_array()
			cmd[ActorCommand.FLAGS_INDEX] = (int(cmd[ActorCommand.FLAGS_INDEX]) & ActorCommand.HELD_MASK) \
					| int(_one_shots.get(id, 0))
			cmd[ActorCommand.SWITCH_INDEX] = _switches.get(id, -1)
			entries.append([id, actor.global_position, actor.velocity, cmd, actor.health.health,
					actor.health.armor, actor.stagger_left, _dead_kind.get(id, "")])
		_one_shots.clear()
		_switches.clear()
		for start in range(0, entries.size(), ACTORS_PER_PACKET):
			var chunk := entries.slice(start, start + ACTORS_PER_PACKET)
			for peer in _joined_peers:
				_state.rpc_id(peer, raid.time_left, chunk)
		if not _vehicles.is_empty():
			var rides: Array = []
			for id: int in _vehicles:
				var vehicle: Node3D = _vehicles[id]
				var rider: Actor = vehicle.get("rider")
				rides.append([id, vehicle.global_position, vehicle.get("heading"), vehicle.get("speed"),
						_ids.get(rider, -1) if rider != null else -1])
			for peer in _joined_peers:
				_vehicle_state.rpc_id(peer, rides)
	for state in raid.players:
		var id: int = _ids.get(state.actor, -1)
		if id >= 0 and int(_sent_kills.get(id, 0)) != state.kills:
			_sent_kills[id] = state.kills
			for peer in _joined_peers:
				_kills.rpc_id(peer, id, state.kills)
	# A raid that ran out of time, or that everyone has left, makes way for a new one.
	if _restart_in < 0.0 and (raid.is_over or (_had_players and raid.players.is_empty())):
		_restart_in = 5.0 if raid.is_over else 1.0
	if _restart_in >= 0.0:
		_restart_in -= delta
		if _restart_in < 0.0:
			_restart_raid()


func _restart_raid() -> void:
	for peer in _api.get_peers():
		_api.multiplayer_peer.disconnect_peer(peer)
	_joined_peers.clear()
	raid.queue_free()
	remove_child(raid)
	_start_server_raid()


# ---------------------------------------------------------------- client ----

## Connects to a server. `joined`, `failed` and `run_finished` report what happens.
func join(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	is_server = false
	_api.multiplayer_peer = peer
	_api.connection_failed.connect(func() -> void: failed.emit("Could not reach the server."))
	_api.server_disconnected.connect(_on_server_disconnected)
	return OK


func _on_server_disconnected() -> void:
	if _finished:
		return
	if my_actor_id < 0:
		failed.emit("The server closed the connection.")
	else:
		disconnected.emit()


@rpc("authority", "call_remote", "reliable")
func _hello(protocol: int, p_world_id: String) -> void:
	if protocol != PROTOCOL:
		failed.emit("The server runs a different version of the game.")
		close()
		return
	var world := Worlds.get_world(p_world_id)
	if world == null:
		failed.emit("The server runs a world this game does not have: %s." % p_world_id)
		close()
		return
	world_id = p_world_id
	my_kit.clear()
	if kit_provider.is_valid():
		my_kit.assign(kit_provider.call(world))
	_request_join.rpc_id(1, player_name, my_kit, mastery_picks)


@rpc("authority", "call_remote", "reliable")
func _welcome(actor_id: int, time_left: float) -> void:
	_clear_tables()
	my_actor_id = actor_id
	Combat.authoritative = false
	raid = Raid.new()
	raid.name = "Raid"
	add_child(raid)
	raid.start_client(Worlds.get_world(world_id))
	raid.time_left = time_left


@rpc("authority", "call_remote", "reliable")
func _spawn(id: int, kind: String, shown_name: String, node_name: String, at: Vector3, yaw: float,
		data: Dictionary) -> void:
	if raid == null or _actors.has(id):
		return
	var actor: Actor
	if kind == "player":
		actor = Actor.new()
		actor.name = node_name
		actor.display_name = shown_name
		actor.is_player = id == my_actor_id
		raid.add_child(actor)
		actor.global_position = at
		Loadout.equip(actor, data.get("kit", []))
		Raid.MasteryTracker.apply_variants(actor, data.get("picks", {}))
		raid.world.on_spawn(actor)
		# Listed as a player, so the HUD and scoreboard can tell them from bots.
		var state := Raid.PlayerState.new()
		state.actor = actor
		state.kit.assign(data.get("kit", []))
		state.picks = data.get("picks", {})
		raid.players.append(state)
	else:
		actor = raid.spawn_bot(node_name, at, data.get("seed", 0))
		raid.world.on_spawn(actor)
	actor.cmd.yaw = yaw
	_actors[id] = actor
	_ids[actor] = id
	if id == my_actor_id:
		raid.player = actor
		joined.emit(raid)


@rpc("authority", "call_remote", "reliable")
func _despawn(id: int) -> void:
	var actor: Actor = _actors.get(id)
	_actors.erase(id)
	_latest.erase(id)
	if actor == null or not is_instance_valid(actor):
		return
	_ids.erase(actor)
	if raid != null:
		raid.bots.erase(actor)
		var state := raid.state_for(actor)
		if state != null and id != my_actor_id:
			raid.players.erase(state)
	if id != my_actor_id:
		actor.queue_free()


@rpc("authority", "call_remote", "reliable")
func _kills(id: int, count: int) -> void:
	var actor: Actor = _actors.get(id)
	if raid == null or actor == null or not is_instance_valid(actor):
		return
	var state := raid.state_for(actor)
	if state != null:
		state.kills = count
	if id == my_actor_id:
		raid.kills = count


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(time_left: float, entries: Array) -> void:
	if raid == null:
		return
	raid.time_left = time_left
	for entry: Array in entries:
		var id: int = entry[0]
		# Presses from an update we have not applied yet must not be lost.
		if _latest.has(id):
			var cmd: Array = entry[3]
			var earlier: Array = _latest[id][3]
			cmd[ActorCommand.FLAGS_INDEX] = int(cmd[ActorCommand.FLAGS_INDEX]) \
					| (int(earlier[ActorCommand.FLAGS_INDEX]) & ActorCommand.ONE_SHOT_MASK)
			if int(cmd[ActorCommand.SWITCH_INDEX]) < 0:
				cmd[ActorCommand.SWITCH_INDEX] = earlier[ActorCommand.SWITCH_INDEX]
		_latest[id] = entry


@rpc("authority", "call_remote", "reliable")
func _container(id: int, items: Array, is_bag: bool, label: String, at: Vector3) -> void:
	if raid == null or _containers.has(id):
		return
	_containers[id] = raid.spawn_container(items, is_bag, label, at)


@rpc("authority", "call_remote", "reliable")
func _container_items(id: int, items: Array) -> void:
	var container: LootContainer = _containers.get(id)
	if container != null and is_instance_valid(container):
		container.set_items(items)


@rpc("authority", "call_remote", "reliable")
func _container_gone(id: int) -> void:
	var container: LootContainer = _containers.get(id)
	_containers.erase(id)
	if container != null and is_instance_valid(container):
		container.queue_free()


@rpc("authority", "call_remote", "reliable")
func _inventory(items: Array) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me):
		me.inventory.items.assign(items)
		me.inventory.changed.emit()


@rpc("authority", "call_remote", "reliable")
func _vehicle(id: int, item_id: String, at: Vector3, heading: float) -> void:
	if raid == null or _vehicles.has(id) or not ItemDB.has_item(item_id):
		return
	var vehicle := raid.spawn_vehicle(item_id, at, heading)
	# The server drives it. Here it only follows the reported position.
	vehicle.set_physics_process(false)
	_vehicles[id] = vehicle


@rpc("authority", "call_remote", "reliable")
func _vehicle_gone(id: int) -> void:
	var vehicle: Node3D = _vehicles.get(id)
	_vehicles.erase(id)
	_vehicle_targets.erase(id)
	if vehicle == null or not is_instance_valid(vehicle):
		return
	vehicle.call("dismount")
	if raid != null:
		raid.vehicles.erase(vehicle)
	vehicle.queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func _vehicle_state(entries: Array) -> void:
	for entry: Array in entries:
		_vehicle_targets[entry[0]] = entry


## Moves each vehicle toward where the server says it is, and keeps its rider
## the same as the server's.
func _client_move_vehicles() -> void:
	for id: int in _vehicles:
		var vehicle: Node3D = _vehicles[id]
		if not is_instance_valid(vehicle) or not _vehicle_targets.has(id):
			continue
		var entry: Array = _vehicle_targets[id]
		var at: Vector3 = entry[1]
		if vehicle.global_position.distance_to(at) > SNAP_DISTANCE:
			vehicle.global_position = at
		else:
			vehicle.global_position = vehicle.global_position.lerp(at, 0.35)
		var heading := lerp_angle(vehicle.get("heading"), entry[2], 0.35)
		vehicle.set("heading", heading)
		vehicle.rotation = Vector3(0.0, heading, 0.0)
		vehicle.set("speed", entry[3])
		var rider: Actor = _actors.get(entry[4]) if int(entry[4]) >= 0 else null
		if rider != null and not is_instance_valid(rider):
			rider = null
		var current: Actor = vehicle.get("rider")
		if current != rider:
			if current != null:
				vehicle.call("dismount")
			if rider != null:
				if rider.vehicle != null:
					rider.vehicle.call("dismount")
				vehicle.call("mount", rider)
		vehicle.call("_place_rider")


@rpc("authority", "call_remote", "reliable")
func _hit_feedback(target_id: int, amount: float, kind: String, lethal: bool, blocked: bool,
		parried: bool) -> void:
	var me: Actor = _actors.get(my_actor_id)
	var target: Actor = _actors.get(target_id)
	if me == null or target == null or not is_instance_valid(target):
		return
	var info := DamageInfo.make(amount, me, kind, target.global_position)
	info.blocked = blocked
	info.parried = parried
	me.hit_confirmed.emit(target, info, lethal)


@rpc("authority", "call_remote", "reliable")
func _hurt(amount: float, kind: String) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and not me.is_dead:
		me.health.damaged.emit(DamageInfo.make(amount, null, kind))


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null:
		me.notice.emit(text)
		if text.begins_with("Looted "):
			Sfx.play("loot")


@rpc("authority", "call_remote", "reliable")
func _run_finished(result: Dictionary) -> void:
	_finished = true
	run_finished.emit(result)


func _client_early_tick() -> void:
	if raid == null:
		return
	for id: int in _actors:
		var actor: Actor = _actors[id]
		if not is_instance_valid(actor):
			continue
		var mine := id == my_actor_id
		if not mine:
			actor.cmd.clear_one_shots()
		if not _latest.has(id):
			continue
		var entry: Array = _latest[id]
		_latest.erase(id)
		_apply_state(actor, entry, mine)
	_client_move_vehicles()


func _apply_state(actor: Actor, entry: Array, mine: bool) -> void:
	var at: Vector3 = entry[1]
	var dead_kind: String = entry[7]
	if dead_kind != "":
		if not actor.is_dead:
			actor.global_position = at
			actor.kill(dead_kind)
		return
	if actor.is_dead:
		return
	actor.health.health = entry[4]
	actor.health.armor = entry[5]
	var stagger: float = entry[6]
	if absf(actor.stagger_left - stagger) > 0.15:
		actor.stagger_left = stagger
	var error := actor.global_position.distance_to(at)
	if actor.vehicle != null:
		# A rider goes where their vehicle goes.
		if not mine:
			actor.cmd.apply_array(entry[3])
			actor.cmd.interact_pressed = false
		return
	if mine:
		if error > SNAP_DISTANCE:
			actor.global_position = at
			actor.velocity = entry[2]
		elif error > OWN_TOLERANCE:
			actor.global_position = actor.global_position.lerp(at, 0.15)
		return
	actor.cmd.apply_array(entry[3])
	# Looting is decided by the server, never replayed here.
	actor.cmd.interact_pressed = false
	if error > SNAP_DISTANCE:
		actor.global_position = at
	else:
		actor.global_position = actor.global_position.lerp(at, 0.35)
	actor.velocity = entry[2]


func _client_late_tick() -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me) and not me.is_dead and _is_connected():
		_send_input.rpc_id(1, me.cmd.to_array())


func _is_connected() -> bool:
	return _api.multiplayer_peer != null \
			and _api.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Containers and vehicles this session knows about. For tests and tools.
func containers() -> Array:
	return _containers.values()


func vehicles() -> Array:
	return _vehicles.values()


## The actor for a network id, or null. For tests and tools.
func actor_for(id: int) -> Actor:
	var actor: Actor = _actors.get(id)
	return actor if actor != null and is_instance_valid(actor) else null


func _physics_process(_delta: float) -> void:
	if is_server:
		_server_early_tick()
	else:
		_client_early_tick()


## Runs after every actor has simulated its tick.
class LateTick:
	extends Node

	var session: NetSession

	func _ready() -> void:
		process_physics_priority = 100

	func _physics_process(delta: float) -> void:
		if session.is_server:
			session._server_late_tick(delta)
		else:
			session._client_late_tick()
