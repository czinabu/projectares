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
## deaths then correct the local guess. Damage is never decided on a client
## (`Combat.authoritative` is false there).
##
## Every input a client sends is numbered and the server plays them in order,
## one per tick. Its answer says which input it had reached, so the client
## compares the server's position with its own prediction for that same
## input and blends away only the real difference. Your own movement stays
## smooth however slow the connection is. A vehicle you ride is predicted
## and corrected the same way, so it steers the moment you do.
##
## Shots are lag compensated. Each input also says which server tick the
## client's view of everyone else had reached, and the server keeps a short
## history of where every actor was. When a player attacks, the server tests
## the hit against where the targets were on that player's screen
## (`Combat.rewind`), so nobody has to lead their shots by their ping.
##
## Connecting puts a client in the lobby: it signs in with a name and a secret,
## and the server answers with that account's stash and loadout from its
## `StashService`. Loadout changes are requests the server checks. `deploy`
## enters the raid with the kit the server took out of the stash, and the
## server settles the result into the stash when the run ends. A client never
## sends a kit.
##
## Each session owns its own multiplayer API rooted at itself, so it works
## anywhere in the scene tree and several can live in one process.

## Client: the server accepted your name. `account` is your stash, loadout,
## mastery and record as the server holds them. You are now in the lobby.
signal signed_in(account: Dictionary)
## Client: the server sent a fresh copy of your account (after any change).
signal account_changed(account: Dictionary)
## Client: the server turned down a lobby request (equip, pick, deploy).
signal lobby_error(reason: String)
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
const PROTOCOL := 6
const StashService := preload("res://core/account/stash_service.gd")
## Server physics ticks between state updates (2 = 30 a second).
const TICKS_PER_SNAPSHOT := 2
## Actors per state packet, to keep each one under the network's packet size.
const ACTORS_PER_PACKET := 5
## Position errors beyond this are fixed at once instead of blended.
const SNAP_DISTANCE := 5.0
## Each input packet repeats this many recent ticks, so a lost packet does not
## lose a key press.
const INPUT_REDUNDANCY := 4
## The server holds at most this many unplayed inputs per player. More means
## the player's packets arrived in a burst, and the oldest are folded together.
const MAX_QUEUED_INPUTS := 6
## The furthest back the server rewinds a target for an attacker's ping
## (30 = half a second). A slower connection has to lead by the rest.
const MAX_REWIND_TICKS := 30
## How many ticks of your own predicted positions a client remembers.
const HISTORY_TICKS := 180
## The share of a position error that is corrected each tick.
const CORRECTION_RATE := 0.2
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
## Server: owns every player's stash, loadout and mastery. Set its
## `save_dir` or `persist` before `host`.
var stash := StashService.new()
## Client: the name to sign in with, and the secret that proves the account
## is yours (see `StashService.new_secret`).
var player_name := "Raider"
var secret := ""
## Client: your account as the server last sent it. Empty until signed in.
var account := {}
## Client: the server answered and said no, so trying again will not help.
var refused := false
## Client: the id of your own actor, and the kit you joined with.
var my_actor_id := -1
## Client, for testing how the game feels on a bad connection: seconds of delay
## added in each direction, and the share of input packets thrown away (0 to 1).
var simulated_lag := 0.0
var simulated_loss := 0.0
## Client: the largest gap seen between where the server put you and where
## this game had predicted you would be at that same moment.
var max_correction := 0.0
## Server: test hits against where the attacker saw their targets. Off only
## to compare with how it plays without (`--no-rewind`).
var lag_compensation := true

var _api: SceneMultiplayer
var _actors := {}        # id -> Actor
var _ids := {}           # Actor -> id
var _next_id := 1
var _peer_actor := {}    # peer id -> Actor (server)
var _actor_peer := {}    # Actor -> peer id (server)
var _joined_peers: Array[int] = []
var _peer_account := {}  # peer id -> account id (server)
var _actor_account := {} # Actor -> account id, until the run is settled (server)
var _input_queue := {}   # peer id -> [[seq, command array], ...] not yet played (server)
var _queued_seq := {}    # peer id -> newest input number received (server)
var _applied_seq := {}   # actor id -> input number the actor last simulated (server)
var _seen_tick := {}     # Actor -> server tick the player was looking at (server)
var _past := {}          # server tick -> {Actor: position} after that tick (server)
var _seq := 0            # number of the input sent this tick (client)
var _history := {}       # input number -> own predicted position after it (client)
var _recent_inputs: Array = [] # the last few [seq, command array, view tick] sent (client)
var _newest_tick := 0    # server tick of the newest state received (client)
var _fresh_state := false # a newer state arrived since the last tick (client)
var _view_tick := 0      # server tick the actors on screen show (client)
var _corrections := {}   # actor id -> position error still to blend away (client)
var _delayed_out: Array = [] # [due msec, inputs] held back by simulated_lag
var _delayed_in: Array = []  # [due msec, Callable] updates held back by simulated_lag
var _one_shots := {}     # actor id -> accumulated one-shot flags (server)
var _switches := {}      # actor id -> last weapon switch since the snapshot
var _dead_kind := {}     # actor id -> damage kind that killed them
var _latest := {}        # actor id -> newest state entry (client)
var _containers := {}    # container id -> LootContainer
var _container_ids := {} # LootContainer -> id
var _vehicles := {}      # vehicle id -> vehicle node
var _vehicle_ids := {}   # vehicle node -> id
var _vehicle_targets := {} # vehicle id -> newest state entry (client)
var _ride_history := {}  # input number -> [position, heading, speed] of the ride after it (client)
var _ride_fix := Vector3.ZERO # position error of your ride still to blend away (client)
var _ride_turn := 0.0    # heading error of your ride still to blend away (client)
var _ride_entry: Array = [] # the server's last answer about your ride, once compared (client)
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
	if is_server:
		# A server that stops mid-raid hands everyone's gear back.
		stash.cancel_all_deploys()
	close()
	if not is_server:
		Combat.authoritative = true
	elif Combat.rewind == _seen_positions:
		Combat.rewind = Callable()


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
	if lag_compensation:
		Combat.rewind = _seen_positions
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
	_input_queue.clear()
	_queued_seq.clear()
	_applied_seq.clear()
	_seen_tick.clear()
	_past.clear()
	_newest_tick = 0
	_fresh_state = false
	_view_tick = 0
	_seq = 0
	_history.clear()
	_recent_inputs.clear()
	_corrections.clear()
	_delayed_out.clear()
	_delayed_in.clear()
	_one_shots.clear()
	_switches.clear()
	_dead_kind.clear()
	_latest.clear()
	_containers.clear()
	_container_ids.clear()
	_vehicles.clear()
	_vehicle_ids.clear()
	_vehicle_targets.clear()
	_ride_history.clear()
	_ride_fix = Vector3.ZERO
	_ride_turn = 0.0
	_ride_entry = []
	_sent_kills.clear()
	_actor_account.clear()


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
	_peer_account.erase(peer)
	_input_queue.erase(peer)
	_queued_seq.erase(peer)
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
	_seen_tick.erase(actor)
	for tick: int in _past:
		_past[tick].erase(actor)
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
	var online := peer != 0 and peer in _api.get_peers()
	# The stash only ever changes from the server's own result.
	var account_id: String = _actor_account.get(actor, "")
	if account_id != "":
		_actor_account.erase(actor)
		stash.settle(account_id, result)
		if online:
			_account.rpc_id(peer, stash.snapshot(account_id))
	if online:
		_run_finished.rpc_id(peer, result)


func _send_account(peer: int) -> void:
	_account.rpc_id(peer, stash.snapshot(_peer_account[peer]))


## Lobby: a connected player says who they are.
@rpc("any_peer", "call_remote", "reliable")
func _sign_in(p_name: String, p_secret: String) -> void:
	if not is_server:
		return
	var peer := _api.get_remote_sender_id()
	if _peer_account.has(peer):
		return
	var result := stash.sign_in(p_name, p_secret)
	if not result.ok:
		_refused.rpc_id(peer, result.error)
		return
	# The newest sign-in wins. An older connection for the same account (a
	# crashed game, or one that is still closing) is dropped, and if it was in
	# the raid that run ends as a death before the new lobby sees the stash.
	for other: int in _peer_account.keys():
		if _peer_account[other] == result.account_id:
			_on_peer_disconnected(other)
			if other in _api.get_peers():
				_api.multiplayer_peer.disconnect_peer(other)
	_peer_account[peer] = result.account_id
	_send_account(peer)


## Lobby: put a stash item in a loadout slot, or "" to empty the slot.
@rpc("any_peer", "call_remote", "reliable")
func _request_equip(slot: String, item_id: String) -> void:
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var account_id: String = _peer_account[peer]
	var result: Dictionary = stash.unequip(account_id, slot) if item_id == "" else stash.equip(account_id, slot, item_id)
	if not result.ok:
		_lobby_error.rpc_id(peer, result.error)
	_send_account(peer)


## Lobby: pick a mastery variant, or "" for stock.
@rpc("any_peer", "call_remote", "reliable")
func _request_pick(track: String, variant_id: String) -> void:
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = stash.pick_mastery(_peer_account[peer], track, variant_id)
	if not result.ok:
		_lobby_error.rpc_id(peer, result.error)
	_send_account(peer)


## Lobby: buy one item from a hub shop. The server sets the price.
@rpc("any_peer", "call_remote", "reliable")
func _request_buy(shop_id: String, item_id: String) -> void:
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = stash.buy(_peer_account[peer], shop_id, item_id)
	if not result.ok:
		_lobby_error.rpc_id(peer, result.error)
	_send_account(peer)


## Lobby: sell stash items for credits. An empty `item_id` sells all loot.
@rpc("any_peer", "call_remote", "reliable")
func _request_sell(item_id: String, count: int) -> void:
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	var result: Dictionary = stash.sell(_peer_account[peer], item_id, count)
	if not result.ok:
		_lobby_error.rpc_id(peer, result.error)
	_send_account(peer)


func _send_spawn(peer: int, actor: Actor) -> void:
	var state := raid.state_for(actor)
	var data := {}
	if state != null:
		data = {"kit": state.kit, "picks": state.picks}
	else:
		data = {"seed": raid.bot_seeds.get(actor, 0)}
	_spawn.rpc_id(peer, _ids[actor], "player" if state != null else "bot", actor.display_name,
			String(actor.name), actor.global_position, actor.cmd.yaw, data)


## Lobby: deploy into the running raid with the account's loadout. The kit
## and picks come from the server's stash, never from the client.
@rpc("any_peer", "call_remote", "reliable")
func _request_join() -> void:
	if not is_server or raid == null:
		return
	var peer := _api.get_remote_sender_id()
	if _peer_actor.has(peer) or not _peer_account.has(peer):
		return
	if raid.is_over or _restart_in >= 0.0:
		_lobby_error.rpc_id(peer, "That raid is ending. Try again in a moment.")
		return
	var account_id: String = _peer_account[peer]
	var deployed: Dictionary = stash.deploy(account_id, raid.world)
	if not deployed.ok:
		_lobby_error.rpc_id(peer, deployed.error)
		return
	var actor := raid.add_player(deployed.kit, deployed.picks, stash.snapshot(account_id).name)
	_actor_account[actor] = account_id
	_send_account(peer)
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
func _send_input(inputs: Array) -> void:
	if not is_server or inputs.size() > INPUT_REDUNDANCY:
		return
	var peer := _api.get_remote_sender_id()
	if not _peer_actor.has(peer):
		return
	# Each packet repeats recent ticks. Queue only the ones not seen before,
	# in order, so every tick the player simulated is played here exactly once.
	var queue: Array = _input_queue.get_or_add(peer, [])
	for input: Variant in inputs:
		if typeof(input) != TYPE_ARRAY or input.size() != 3 or typeof(input[0]) != TYPE_INT \
				or typeof(input[1]) != TYPE_ARRAY or input[1].size() != ActorCommand.ARRAY_SIZE \
				or typeof(input[2]) != TYPE_INT:
			return
		if input[0] > int(_queued_seq.get(peer, 0)):
			_queued_seq[peer] = input[0]
			queue.append(input)
	# A burst after a stall: fold the oldest inputs together to catch up,
	# keeping every press.
	while queue.size() > MAX_QUEUED_INPUTS:
		var dropped: Array = queue.pop_front()[1]
		var next: Array = queue[0][1]
		next[ActorCommand.FLAGS_INDEX] = int(next[ActorCommand.FLAGS_INDEX]) \
				| (int(dropped[ActorCommand.FLAGS_INDEX]) & ActorCommand.ONE_SHOT_MASK)
		if int(next[ActorCommand.SWITCH_INDEX]) < 0:
			next[ActorCommand.SWITCH_INDEX] = dropped[ActorCommand.SWITCH_INDEX]


func _server_early_tick() -> void:
	if raid == null:
		return
	for peer: int in _peer_actor:
		var actor: Actor = _peer_actor[peer]
		if not is_instance_valid(actor) or actor.is_dead:
			continue
		# With nothing new to play, held keys carry on and presses do not repeat.
		actor.cmd.clear_one_shots()
		var queue: Array = _input_queue.get(peer, [])
		if not queue.is_empty():
			var input: Array = queue.pop_front()
			actor.cmd.apply_array(input[1])
			_applied_seq[_ids[actor]] = input[0]
			# Never later than now: a client cannot see the future.
			_seen_tick[actor] = mini(input[2], _tick)
		elif _seen_tick.has(actor):
			# A held trigger keeps firing at what the player is watching move on.
			_seen_tick[actor] = mini(int(_seen_tick[actor]) + 1, _tick)


## `Combat.rewind` on a server: where everyone else was on `attacker`'s screen
## when their current input was made.
func _seen_positions(attacker: Actor) -> Dictionary:
	if not _seen_tick.has(attacker):
		return {}
	var tick := maxi(int(_seen_tick[attacker]), _tick - MAX_REWIND_TICKS)
	if tick >= _tick:
		return {}
	return _past.get(tick, {})


func _server_late_tick(delta: float) -> void:
	if raid == null:
		return
	for id: int in _actors:
		var actor: Actor = _actors[id]
		_one_shots[id] = int(_one_shots.get(id, 0)) | (actor.cmd.flags() & ActorCommand.ONE_SHOT_MASK)
		if actor.cmd.switch_weapon >= 0:
			_switches[id] = actor.cmd.switch_weapon
	_tick += 1
	if lag_compensation:
		var now := {}
		for actor: Actor in _ids:
			if not actor.is_dead:
				now[actor] = actor.global_position
		_past[_tick] = now
		_past.erase(_tick - MAX_REWIND_TICKS - 1)
	if _tick % TICKS_PER_SNAPSHOT == 0 and not _joined_peers.is_empty():
		var entries: Array = []
		for id: int in _actors:
			var actor: Actor = _actors[id]
			var cmd := actor.cmd.to_array()
			cmd[ActorCommand.FLAGS_INDEX] = (int(cmd[ActorCommand.FLAGS_INDEX]) & ActorCommand.HELD_MASK) \
					| int(_one_shots.get(id, 0))
			cmd[ActorCommand.SWITCH_INDEX] = _switches.get(id, -1)
			entries.append([id, actor.global_position, actor.velocity, cmd, actor.health.health,
					actor.health.armor, actor.stagger_left, _dead_kind.get(id, ""), _applied_seq.get(id, 0)])
		_one_shots.clear()
		_switches.clear()
		for start in range(0, entries.size(), ACTORS_PER_PACKET):
			var chunk := entries.slice(start, start + ACTORS_PER_PACKET)
			for peer in _joined_peers:
				_state.rpc_id(peer, _tick, raid.time_left, chunk)
		if not _vehicles.is_empty():
			var rides: Array = []
			for id: int in _vehicles:
				var vehicle: Node3D = _vehicles[id]
				var rider: Actor = vehicle.get("rider")
				var rider_id: int = _ids.get(rider, -1) if rider != null else -1
				rides.append([id, vehicle.global_position, vehicle.get("heading"), vehicle.get("speed"),
						rider_id, _applied_seq.get(rider_id, 0)])
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
	# Players in the old raid are sent home. Players waiting in the lobby stay.
	for peer in _joined_peers:
		if peer in _api.get_peers():
			_peer_account.erase(peer)
			_api.multiplayer_peer.disconnect_peer(peer)
	_joined_peers.clear()
	# Everyone should be settled by now. Anyone who is not gets their gear back.
	for account_id: String in _actor_account.values():
		stash.cancel_deploy(account_id)
	raid.queue_free()
	remove_child(raid)
	_start_server_raid()


# ---------------------------------------------------------------- client ----

## Connects to a server and signs in. `signed_in` or `failed` follows; then
## `deploy` enters the raid.
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
		failed.emit("The server closed the connection." if account.is_empty() else "Lost the connection to the server.")
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
	_sign_in.rpc_id(1, player_name, secret)


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	refused = true
	failed.emit(reason)
	close()


@rpc("authority", "call_remote", "reliable")
func _account(snapshot: Dictionary) -> void:
	var first := account.is_empty()
	account = snapshot
	if first:
		signed_in.emit(account)
	account_changed.emit(account)


@rpc("authority", "call_remote", "reliable")
func _lobby_error(reason: String) -> void:
	lobby_error.emit(reason)


## Lobby: ask the server to put a stash item in a slot ("" empties it).
func equip(slot: String, item_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_equip.rpc_id(1, slot, item_id)


## Lobby: ask the server to pick a mastery variant ("" for stock).
func pick_mastery(track: String, variant_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_pick.rpc_id(1, track, variant_id)


## Lobby: ask the server to buy one item from a hub shop.
func buy(shop_id: String, item_id: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_buy.rpc_id(1, shop_id, item_id)


## Lobby: ask the server to sell stash items ("" sells all loot).
func sell(item_id: String, count: int = 1) -> void:
	if _is_connected() and not account.is_empty():
		_request_sell.rpc_id(1, item_id, count)


## Lobby: deploy into the server's raid. `joined` follows, or `lobby_error`.
func deploy() -> void:
	if _is_connected() and not account.is_empty() and my_actor_id < 0:
		_request_join.rpc_id(1)


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
func _state(tick: int, time_left: float, entries: Array) -> void:
	_after_lag(_receive_state.bind(tick, time_left, entries))


## Runs `update` now, or after the simulated lag.
func _after_lag(update: Callable) -> void:
	if simulated_lag > 0.0:
		_delayed_in.append([Time.get_ticks_msec() + simulated_lag * 1000.0, update])
	else:
		update.call()


func _receive_state(tick: int, time_left: float, entries: Array) -> void:
	if raid == null:
		return
	raid.time_left = time_left
	if tick > _newest_tick:
		_newest_tick = tick
		_fresh_state = true
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
	_after_lag(func() -> void:
		for entry: Array in entries:
			_vehicle_targets[entry[0]] = entry)


## Moves each vehicle toward where the server says it is, and keeps its rider
## the same as the server's. The one you ride drives itself from your input
## here, and is only corrected (`_correct_ride`).
func _client_move_vehicles() -> void:
	for id: int in _vehicles:
		var vehicle: Node3D = _vehicles[id]
		if not is_instance_valid(vehicle):
			continue
		var me: Actor = _actors.get(my_actor_id)
		var mine: bool = me != null and vehicle.get("rider") == me
		vehicle.set_physics_process(mine)
		if mine:
			_blend_ride(vehicle)
		if not _vehicle_targets.has(id):
			continue
		var entry: Array = _vehicle_targets[id]
		if mine and int(entry[4]) == my_actor_id:
			# Each answer is compared once. The ride drives itself in between.
			if not is_same(entry, _ride_entry):
				_ride_entry = entry
				_correct_ride(vehicle, entry)
			continue
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
			_ride_history.clear()
			_ride_fix = Vector3.ZERO
			_ride_turn = 0.0
		vehicle.call("_place_rider")


## Compares the server's position for your ride with where this game predicted
## it after the same input, like `_apply_state` does for your own actor.
func _correct_ride(vehicle: Node3D, entry: Array) -> void:
	var seq: int = entry[5]
	if not _ride_history.has(seq):
		# Just got on: nothing predicted to compare with yet.
		if vehicle.global_position.distance_to(entry[1]) > SNAP_DISTANCE:
			_snap_ride(vehicle, entry)
		return
	var then: Array = _ride_history[seq]
	var miss: Vector3 = entry[1] - then[0]
	max_correction = maxf(max_correction, miss.length())
	if miss.length() > SNAP_DISTANCE:
		_snap_ride(vehicle, entry)
		return
	_ride_fix = miss
	_ride_turn = angle_difference(then[1], entry[2])
	# Speed carries straight into the future, so it is fixed at once, and in
	# the remembered rides too so the next answer only sees what is still wrong.
	var speed_miss := float(entry[3]) - float(then[2])
	vehicle.set("speed", float(vehicle.get("speed")) + speed_miss)
	for later: int in _ride_history:
		_ride_history[later][2] += speed_miss


func _snap_ride(vehicle: Node3D, entry: Array) -> void:
	vehicle.global_position = entry[1]
	vehicle.set("heading", entry[2])
	vehicle.rotation = Vector3(0.0, entry[2], 0.0)
	vehicle.set("speed", entry[3])
	_ride_history.clear()
	_ride_fix = Vector3.ZERO
	_ride_turn = 0.0


func _blend_ride(vehicle: Node3D) -> void:
	if _ride_fix == Vector3.ZERO and _ride_turn == 0.0:
		return
	var step := _ride_fix * CORRECTION_RATE if _ride_fix.length() > 0.02 else _ride_fix
	var turn := _ride_turn * CORRECTION_RATE if absf(_ride_turn) > 0.002 else _ride_turn
	vehicle.global_position += step
	vehicle.set("heading", float(vehicle.get("heading")) + turn)
	vehicle.rotation = Vector3(0.0, vehicle.get("heading"), 0.0)
	for seq: int in _ride_history:
		_ride_history[seq][0] += step
		_ride_history[seq][1] += turn
	_ride_fix -= step
	_ride_turn -= turn


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
	while not _delayed_in.is_empty() and _delayed_in[0][0] <= Time.get_ticks_msec():
		_delayed_in.pop_front()[1].call()
	if raid == null:
		return
	# Everyone else is shown as the newest state left them, moved on by local
	# simulation, so the screen shows the server's tick from that state plus
	# the ticks since. Attacks made now are judged against that tick.
	_view_tick = _newest_tick + 1 if _fresh_state else _view_tick + 1
	_fresh_state = false
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
	_blend_corrections()
	_client_move_vehicles()


## Moves each actor a share of the way toward where the server says it
## should be, every tick, so fixes glide in.
func _blend_corrections() -> void:
	for id: int in _corrections.keys():
		var actor: Actor = _actors.get(id)
		if actor == null or not is_instance_valid(actor) or actor.is_dead or actor.vehicle != null:
			_corrections.erase(id)
			continue
		var left: Vector3 = _corrections[id]
		var step := left * CORRECTION_RATE if left.length() > 0.02 else left
		actor.global_position += step
		if id == my_actor_id:
			# Remembered positions move too, so the next comparison only sees
			# what is still wrong.
			for seq: int in _history:
				_history[seq] += step
		if step == left:
			_corrections.erase(id)
		else:
			_corrections[id] = left - step


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
	var id: int = entry[0]
	if actor.vehicle != null:
		# A rider goes where their vehicle goes.
		if not mine:
			actor.cmd.apply_array(entry[3])
			actor.cmd.interact_pressed = false
		return
	if mine:
		# The server's position is from the past: it belongs to an input sent a
		# moment ago. Compare it with where this game predicted you would be
		# after that same input, not with where you are now. Running in a
		# straight line then needs no correction however slow the connection.
		var seq: int = entry[8]
		if not _history.has(seq):
			if actor.global_position.distance_to(at) > SNAP_DISTANCE:
				actor.global_position = at
				actor.velocity = entry[2]
			return
		var miss: Vector3 = at - _history[seq]
		max_correction = maxf(max_correction, miss.length())
		if miss.length() > SNAP_DISTANCE:
			actor.global_position += miss
			actor.velocity = entry[2]
			_history.clear()
			_corrections.erase(id)
		elif miss.length() > 0.01:
			_corrections[id] = miss
		else:
			_corrections.erase(id)
		return
	actor.cmd.apply_array(entry[3])
	# Looting is decided by the server, never replayed here.
	actor.cmd.interact_pressed = false
	var gap := at - actor.global_position
	if gap.length() > SNAP_DISTANCE:
		actor.global_position = at
		_corrections.erase(id)
	else:
		_corrections[id] = gap
	actor.velocity = entry[2]


func _client_late_tick() -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me == null or not is_instance_valid(me) or me.is_dead or not _is_connected():
		return
	# Number this tick's input and remember where it left you, to compare with
	# the server's answer later.
	_seq += 1
	if me.vehicle != null:
		# A rider goes where their vehicle goes; the ride is what is compared.
		_history.clear()
		_ride_history[_seq] = [me.vehicle.global_position, float(me.vehicle.get("heading")),
				float(me.vehicle.get("speed"))]
		_ride_history.erase(_seq - HISTORY_TICKS)
	else:
		_ride_history.clear()
		_history[_seq] = me.global_position
		_history.erase(_seq - HISTORY_TICKS)
	_recent_inputs.append([_seq, me.cmd.to_array(), _view_tick])
	if _recent_inputs.size() > INPUT_REDUNDANCY:
		_recent_inputs.pop_front()
	var now := Time.get_ticks_msec()
	if simulated_loss <= 0.0 or randf() >= simulated_loss:
		_delayed_out.append([now + simulated_lag * 1000.0, _recent_inputs.duplicate()])
	while not _delayed_out.is_empty() and _delayed_out[0][0] <= now:
		_send_input.rpc_id(1, _delayed_out.pop_front()[1])


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
