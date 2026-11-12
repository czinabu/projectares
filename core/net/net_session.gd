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
## drops you into the world with the kit the server took out of the stash, and
## the server settles each life into the stash when it ends. After a death the
## client stays connected and `deploy` drops it in again. A client never sends
## a kit.
##
## The server's raid never ends or restarts. A client that disconnects leaves
## its body behind for a while (`Raid.remove_player`), and the server settles
## that life when the body is killed or its sign-out runs out.
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
## Client: the raid view exists and your actor is in it. Fires again every
## time you drop back in after a death.
signal joined(raid: Raid)
## Client: one life ended. `result.outcome` is "died" (you are still connected
## and `deploy` drops you in again) or "left" (your sign-out finished).
signal run_finished(result: Dictionary)
## Client: could not connect, or the server refused.
signal failed(reason: String)
## Client: the connection dropped after joining.
signal disconnected
## Client: the server said which port each of its worlds runs on.
signal routes_changed(routes: Dictionary)
## Client: the phone's contacts, messages, invites and news changed (see
## `SocialService.snapshot`).
signal social_changed(social: Dictionary)
## Client: the server turned down a phone request (message, invite, contact).
signal social_error(reason: String)
## Client: something happened on the phone worth a pop-up ("Bo accepted").
signal social_notice(text: String)
## Client: you accepted an invite to the raid on this server.
signal world_invite_accepted(invite: Dictionary)
## Client: you accepted an invite to someone's home base. The owner's stash
## and loadout come from the server, so a base can be shown read-only.
signal base_visit_requested(owner_name: String, stash: Array, loadout: Dictionary)

const DEFAULT_PORT := 24565
const PROTOCOL := 15
const StashService := preload("res://core/account/stash_service.gd")
const Economy := preload("res://core/economy/economy.gd")
const Human := preload("res://core/visual/human.gd")
const SocialService := preload("res://core/social/social_service.gd")
const ArenaVenue := preload("res://core/arena/arena_venue.gd")
## Server physics ticks between arena board updates when nothing changed.
const BOARD_RESEND_TICKS := 60
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
		"Backpack full", "Someone is riding it", "Banked ", "Signing out", "Sign-out cancelled",
		"You cannot sign out", "Scanned"]

var is_server := false
var raid: Raid
var world_id := ""
## Server options, set before `host`: a bot count override (below zero keeps
## the world's own) and whether players spawn together.
var bot_count := -1
var squad_spawn := false
## Server, set before `host`: the raid gets a 3D world of its own, so several
## sessions (a plaza and a warzone) can run in one process without their maps
## colliding.
var isolated := false
## Where to find the other worlds on this server: world id -> port. A server
## hosting a safe zone fills this in before `host`, and clients receive it
## when they sign in, so a plaza gate knows where to send you.
var routes := {}
## Client: called with the server's world, returns the kit to deploy with.
## Server: owns every player's stash, loadout and mastery. Set its
## `save_dir` or `persist` before `host`.
var stash := StashService.new()
## Server: presence, contacts, messages, invites and news for the phone. Its
## files live in a `social` folder inside the stash's `save_dir`.
var social := SocialService.new()
## Client: the phone's view as the server last sent it. Empty until signed in.
var social_state := {}
## Client: the name to sign in with, and the secret that proves the account
## is yours (see `StashService.new_secret`).
var player_name := "Raider"
## Client: how this player's character looks, sent once signed in.
var look := {}
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
var _peer_look := {}  # peer id -> appearance (server). Cosmetic only.
var _joining_look := {}  # the look of the player being added right now (server)
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
var _board_sent := {}    # peer id -> [board text, tick sent] (server, arena)
var _board_dirty := false
var _sent_standing := {} # actor id -> public renown standing last sent (server)
var _sent_war := -1.0    # war intensity last sent (server)
var _sent_points := {}   # peer id -> strongpoint states last sent to them (server)
var _tick := 0
var _died_at := {}       # peer id -> msec when their last life ended in a death (server)
var _finished := false   # client: signed out, so the server closing the connection is expected
var _can_redeploy := false # client: dead and still connected
var _space: SubViewport  # the raid's own 3D world when `isolated` (server)


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
	if world_for(p_world_id) == null:
		return ERR_DOES_NOT_EXIST
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	is_server = true
	world_id = p_world_id
	social.persist = stash.persist
	social.save_dir = stash.save_dir.path_join("social")
	social.load_server_news(stash.save_dir.path_join("news.json"))
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
	var world := world_for(world_id)
	raid = world.new_raid()
	raid.name = "Raid"
	if isolated:
		if _space == null:
			_space = SubViewport.new()
			_space.name = "Space"
			_space.own_world_3d = true
			_space.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(_space)
		_space.add_child(raid)
	else:
		add_child(raid)
	raid.actor_spawned.connect(_on_server_actor_spawned)
	raid.actor_removed.connect(_on_server_actor_removed)
	raid.player_finished.connect(_on_server_player_finished)
	raid.player_banked.connect(_on_server_player_banked)
	raid.war_feed.connect(func(text: String) -> void:
		for peer in _joined_peers:
			_war_feed.rpc_id(peer, text))
	raid.sign_out_changed.connect(_on_server_sign_out_changed)
	raid.container_spawned.connect(_on_server_container_spawned)
	raid.vehicle_spawned.connect(_on_server_vehicle_spawned)
	raid.vehicle_removed.connect(_on_server_vehicle_removed)
	raid.squad_spawn = squad_spawn
	if lag_compensation:
		raid.rewind = _seen_positions
	if bot_count >= 0:
		world.bot_count = bot_count
	var arena := raid as Arena
	if arena != null:
		# The arena pays wagers from the accounts this server keeps.
		arena.bank = Arena.StashBank.new(stash)
		arena.board_changed.connect(func() -> void: _board_dirty = true)
		arena.told.connect(func(actor: Actor, text: String) -> void:
			var peer: int = _actor_peer.get(actor, 0)
			if peer in _api.get_peers():
				_notice.rpc_id(peer, text))
	raid.start_server(world)


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
	_sent_standing.clear()
	_sent_war = -1.0
	_sent_points.clear()
	_actor_account.clear()
	_board_sent.clear()


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
	_social_left(peer)
	_peer_account.erase(peer)
	_peer_look.erase(peer)
	_input_queue.erase(peer)
	_queued_seq.erase(peer)
	_died_at.erase(peer)
	# Their body stays in the world for a while. The run is settled into the
	# account when it is killed or its sign-out runs out.
	var actor: Actor = _peer_actor.get(peer)
	if actor != null and is_instance_valid(actor) and raid != null:
		raid.remove_player(actor)
	_peer_actor.erase(peer)


func _on_server_actor_spawned(actor: Actor) -> void:
	# A joining player's look is put on before anyone is told about them.
	if not _joining_look.is_empty() and raid.state_for(actor) != null:
		Look.set_appearance(actor, _joining_look)
		_joining_look = {}
	var id := _register(actor)
	actor.died.connect(func(_a: Actor, info: DamageInfo) -> void: _dead_kind[id] = info.kind)
	# A power weapon taken off a rack, swapped or spent is shown to all.
	actor.power_changed.connect(func(item_id: String, mag: int, reserve: int) -> void:
		for peer in _joined_peers:
			_power_changed.rpc_id(peer, id, item_id, mag, reserve))
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
	_sent_standing.erase(id)
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
		# Nothing to settle where no gear was at risk (the arena).
		if raid.world.gear_at_risk:
			stash.settle(account_id, result)
		# Everyone signed in to the account hears, including a player back in
		# the lobby whose old body just finished its sign-out.
		for other: int in _peer_account:
			if _peer_account[other] == account_id and other in _api.get_peers():
				_account.rpc_id(other, stash.snapshot(account_id))
	if _peer_actor.get(peer) == actor:
		# Free to drop in again, after a short wait if they died.
		_peer_actor.erase(peer)
		_input_queue.erase(peer)
		if result.get("outcome", "") == "died":
			_died_at[peer] = Time.get_ticks_msec()
	if online:
		_run_finished.rpc_id(peer, result)
		# A dead player is still in the world, about to drop back in.
		if result.get("outcome", "") != "died":
			_social_moved(peer, "lobby")


## Banked loot goes straight into the account's stash.
func _on_server_player_banked(actor: Actor, items: Array) -> void:
	var account_id: String = _actor_account.get(actor, "")
	if account_id == "":
		return
	stash.bank(account_id, items)
	var peer: int = _actor_peer.get(actor, 0)
	if peer != 0 and peer in _api.get_peers():
		_account.rpc_id(peer, stash.snapshot(account_id))


func _on_server_sign_out_changed(actor: Actor, seconds_left: float) -> void:
	var peer: int = _actor_peer.get(actor, 0)
	if peer != 0 and peer in _api.get_peers():
		_sign_out.rpc_id(peer, seconds_left)


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
	if not routes.is_empty():
		_routes.rpc_id(peer, routes)
	_send_account(peer)
	_social_joined(peer)


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


## Lobby: how the player's character looks. Looks are cosmetic, so this is
## the one thing a client gets to choose; it is still checked, and a look can
## only name parts and colours that exist.
@rpc("any_peer", "call_remote", "reliable")
func _request_look(p_look: Dictionary) -> void:
	var peer := _api.get_remote_sender_id()
	if not is_server or not _peer_account.has(peer):
		return
	# Only clothing the account owns: the stash decides, not the client.
	var owned := Economy.unlocked_outfits(stash.snapshot(_peer_account[peer]).get("stash", []))
	var cleaned := Look.clean_appearance(p_look, owned)
	_peer_look[peer] = cleaned
	# Already in this world (changed in front of the phone's mirror): everyone
	# here sees it now, the player included, so their game shows what passed.
	var actor: Actor = _peer_actor.get(peer)
	if actor == null or not is_instance_valid(actor) or not _ids.has(actor) \
			or actor.get_meta("appearance", {}) == cleaned:
		return
	Look.set_appearance(actor, cleaned)
	for other in _joined_peers:
		if other in _api.get_peers():
			_look_changed.rpc_id(other, _ids[actor], cleaned)


## Client: someone in this world changed how they look. The server checked it.
@rpc("authority", "call_remote", "reliable")
func _look_changed(id: int, p_look: Dictionary) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor):
		return
	var cleaned := Human.sanitize(p_look)
	if actor.get_meta("appearance", {}) != cleaned:
		Look.set_appearance(actor, cleaned)


## Server: the look a signed-in player chose, or {} if they sent none.
func look_for_peer(peer: int) -> Dictionary:
	return _peer_look.get(peer, {})


## Client: tells the server how this player looks. It is used from the next
## deploy, and if the player is already in a world everyone there sees it now.
func send_look(p_look: Dictionary) -> void:
	look = p_look
	if not is_server and not account.is_empty():
		_request_look.rpc_id(1, look)


func _send_spawn(peer: int, actor: Actor) -> void:
	var state := raid.state_for(actor)
	var data := {}
	if state != null:
		data = {"kit": state.kit, "picks": state.picks}
		var power := Loadout.power_index(actor)
		if power >= 0:
			var gun := actor.weapons[power] as Gun
			data["power"] = [gun.item_id, gun.ammo_in_mag, gun.reserve_ammo]
		if actor.has_meta("appearance"):
			data["look"] = actor.get_meta("appearance")
	else:
		data = {"seed": raid.bot_seeds.get(actor, 0), "warlord": raid.warlords.has(actor),
				"faction": actor.faction}
	_spawn.rpc_id(peer, _ids[actor], "player" if state != null else "bot", actor.display_name,
			String(actor.name), actor.global_position, actor.cmd.yaw, data)


## Drop into the running world with the account's loadout: from the lobby,
## or again after a death. The kit and picks come from the server's stash,
## never from the client.
@rpc("any_peer", "call_remote", "reliable")
func _request_join(drop := "") -> void:
	if not is_server or raid == null:
		return
	var peer := _api.get_remote_sender_id()
	if _peer_actor.has(peer) or not _peer_account.has(peer):
		return
	if Time.get_ticks_msec() - int(_died_at.get(peer, -1000000)) < raid.world.redeploy_delay * 1000.0:
		_lobby_error.rpc_id(peer, "Not yet. You can drop in again in a moment.")
		return
	var account_id: String = _peer_account[peer]
	# In a safe zone the loadout is worn, not risked: it never leaves the
	# stash, and there is no run to settle afterwards.
	var safe := raid.world.safe_zone
	var deployed: Dictionary = stash.showcase(account_id, raid.world) if safe else stash.deploy(account_id, raid.world)
	if not deployed.ok:
		_lobby_error.rpc_id(peer, deployed.error)
		return
	# A peer that is dropping back in already knows the world. It must hear
	# which actor is its own before it hears that the actor exists.
	var returning := peer in _joined_peers
	_joined_peers.erase(peer)
	_joining_look = look_for_peer(peer)
	var who: Dictionary = stash.snapshot(account_id)
	# Renown is kept under the account, never under a name the client chose.
	var actor := raid.add_player(deployed.kit, deployed.picks, who.name, account_id, int(who.get("renown", 0)),
			drop.left(16))
	_joining_look = {}
	if not safe:
		_actor_account[actor] = account_id
	if raid is Arena:
		raid.set_key(actor, account_id)
	_send_account(peer)
	_peer_actor[peer] = actor
	_actor_peer[actor] = peer
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
	# What a helmet reveals goes only to the players allowed to know it.
	actor.visor.revealed.connect(func(found: Array) -> void:
		if peer in _api.get_peers():
			_visor_ghosts.rpc_id(peer, found))
	actor.visor.felt_scan.connect(func(origin: Vector3) -> void:
		if peer in _api.get_peers():
			_visor_felt.rpc_id(peer, origin))
	actor.visor.tagged.connect(_on_server_tagged.bind(actor))
	_joined_peers.append(peer)
	_social_moved(peer, "hub" if safe else "raid")
	_welcome.rpc_id(peer, _ids[actor])
	if returning:
		_send_spawn(peer, actor)
		return
	for other: Actor in _ids:
		if not other.is_dead:
			_send_spawn(peer, other)
	for id: int in _containers:
		_send_container(peer, id)
	for id: int in _vehicles:
		_send_vehicle(peer, id)
	for id: int in _sent_kills:
		_kills.rpc_id(peer, id, _sent_kills[id])
	for id: int in _sent_standing:
		_standing.rpc_id(peer, id, _sent_standing[id])
	_war.rpc_id(peer, raid.war.intensity, raid.war.centre)
	_sent_points.erase(peer)


## Arena: a player in it asks for something (challenge, accept, bet...).
## The server's own `Arena.request` decides, for the sender's own actor.
@rpc("any_peer", "call_remote", "reliable")
func _arena_request(action: String, args: Dictionary) -> void:
	var peer := _api.get_remote_sender_id()
	var arena := raid as Arena
	if not is_server or arena == null or not _peer_actor.has(peer) or action.length() > 32 or args.size() > 4:
		return
	var result := arena.request(_peer_actor[peer], action, args)
	if not result.ok and peer in _api.get_peers():
		_notice.rpc_id(peer, result.error)
	_board_dirty = true


## Sends each player in the arena their own view of the board, when it
## changed and now and then anyway.
func _send_boards() -> void:
	var arena := raid as Arena
	if arena == null:
		return
	var due := _board_dirty or _tick % 15 == 0
	_board_dirty = false
	if not due:
		return
	for peer: int in _peer_actor:
		if peer not in _joined_peers:
			continue
		var b := arena.board_for(_peer_actor[peer])
		var text := JSON.stringify(b)
		var sent: Array = _board_sent.get(peer, ["", -BOARD_RESEND_TICKS])
		if text == sent[0] and _tick - int(sent[1]) < BOARD_RESEND_TICKS:
			continue
		_board_sent[peer] = [text, _tick]
		_arena_board.rpc_id(peer, b)


func _on_server_hit_confirmed(target: Actor, info: DamageInfo, lethal: bool, peer: int) -> void:
	if peer in _api.get_peers() and _ids.has(target):
		_hit_feedback.rpc_id(peer, _ids[target], info.amount, info.kind, lethal, info.blocked, info.parried)


## In the world: start signing out, or call it off.
@rpc("any_peer", "call_remote", "reliable")
func _request_sign_out(start: bool) -> void:
	if not is_server or raid == null:
		return
	var actor: Actor = _peer_actor.get(_api.get_remote_sender_id())
	if actor == null or not is_instance_valid(actor):
		return
	if start:
		raid.begin_sign_out(actor)
	else:
		raid.cancel_sign_out(actor)


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


func _server_late_tick(_delta: float) -> void:
	if raid == null:
		return
	for id: int in _actors:
		var actor: Actor = _actors[id]
		_one_shots[id] = int(_one_shots.get(id, 0)) | (actor.cmd.flags() & ActorCommand.ONE_SHOT_MASK)
		if actor.cmd.switch_weapon != -1:
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
				_state.rpc_id(peer, _tick, chunk)
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
	_send_boards()
	for state in raid.players:
		var id: int = _ids.get(state.actor, -1)
		if id >= 0 and int(_sent_kills.get(id, 0)) != state.kills:
			_sent_kills[id] = state.kills
			for peer in _joined_peers:
				_kills.rpc_id(peer, id, state.kills)
		var actor := state.actor
		if not is_instance_valid(actor):
			continue
		var standing := [actor.renown, actor.rank, actor.streak, actor.bounty, actor.exposed, actor.marked,
				actor.scrip]
		if id >= 0 and _sent_standing.get(id, []) != standing:
			_sent_standing[id] = standing
			for peer in _joined_peers:
				_standing.rpc_id(peer, id, standing)
	# The meter moves slowly, so a few times a second is plenty.
	if _tick % 20 == 0 and not is_equal_approx(_sent_war, raid.war.intensity):
		_sent_war = raid.war.intensity
		for peer in _joined_peers:
			_war.rpc_id(peer, raid.war.intensity, raid.war.centre)
	# Strongpoints: each player hears who holds what, and which are theirs.
	if _tick % 10 == 0 and not raid.strongpoints.is_empty():
		for peer in _joined_peers:
			var viewer: Actor = _peer_actor.get(peer)
			var states := []
			for point in raid.strongpoints:
				states.append([point.holder_name, point.holder_is_player, point.taker_name,
						floori(point.progress * 100.0), point.contested,
						viewer != null and is_instance_valid(viewer) and raid.holds(viewer, point)])
			if _sent_points.get(peer, []) != states:
				_sent_points[peer] = states
				_strongpoints.rpc_id(peer, states)


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
	var world := world_for(p_world_id)
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
		if not look.is_empty():
			_request_look.rpc_id(1, look)
		signed_in.emit(account)
	account_changed.emit(account)


@rpc("authority", "call_remote", "reliable")
func _routes(p_routes: Dictionary) -> void:
	routes.clear()
	for id: Variant in p_routes:
		if typeof(id) == TYPE_STRING and typeof(p_routes[id]) == TYPE_INT:
			routes[id] = p_routes[id]
	routes_changed.emit(routes)


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


## Drop into the server's world: from the lobby, or again after a death.
## `joined` follows, or `lobby_error`. `drop` is where to land, an id from
## `Raid.drop_choices`; the server decides whether it is still on offer.
func deploy(drop := "") -> void:
	if _is_connected() and not account.is_empty() and (my_actor_id < 0 or _can_redeploy):
		_request_join.rpc_id(1, drop)


## In the world: ask the server to start your sign-out, or to call it off.
func sign_out(start := true) -> void:
	if _is_connected() and my_actor_id >= 0 and not _can_redeploy:
		_request_sign_out.rpc_id(1, start)


@rpc("authority", "call_remote", "reliable")
func _welcome(actor_id: int) -> void:
	if raid != null:
		# Dropping back in: the world is already here. Only your actor is new.
		_can_redeploy = false
		var corpse: Actor = raid.player
		if corpse != null and is_instance_valid(corpse):
			var state := raid.state_for(corpse)
			if state != null:
				raid.players.erase(state)
			_actors.erase(_ids.get(corpse, -1))
			_ids.erase(corpse)
			corpse.queue_free()
		raid.player = null
		_history.clear()
		_corrections.erase(my_actor_id)
		_latest.erase(my_actor_id)
		my_actor_id = actor_id
		return
	_clear_tables()
	my_actor_id = actor_id
	Combat.authoritative = false
	var world := world_for(world_id)
	raid = world.new_raid()
	raid.name = "Raid"
	add_child(raid)
	raid.start_client(world)
	if raid is Arena:
		raid.send_request = arena_request


## Client: someone's power weapon slot changed (taken off a rack, swapped,
## or spent). The server decided it; this only makes the copy here match.
@rpc("authority", "call_remote", "reliable")
func _power_changed(id: int, item_id: String, mag: int, reserve: int) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor) or (item_id != "" and not ItemDB.has_tag(item_id, "power")):
		return
	Loadout.set_power(actor, item_id, mag, reserve)


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
		if data.has("look"):
			Look.set_appearance(actor, data["look"])
		raid.add_child(actor)
		actor.global_position = at
		Loadout.equip(actor, data.get("kit", []))
		var power: Variant = data.get("power")
		if power is Array and power.size() == 3 and ItemDB.has_tag(str(power[0]), "power"):
			Loadout.set_power(actor, power[0], int(power[1]), int(power[2]))
		actor.weapons_locked = raid.world.safe_zone
		Raid.MasteryTracker.apply_variants(actor, data.get("picks", {}))
		raid.world.on_spawn(actor)
		# Listed as a player, so the HUD and scoreboard can tell them from bots.
		var state := Raid.PlayerState.new()
		state.actor = actor
		state.kit.assign(data.get("kit", []))
		state.picks = data.get("picks", {})
		raid.players.append(state)
	else:
		actor = raid.spawn_bot(node_name, at, data.get("seed", 0), data.get("warlord", false),
				data.get("faction", ""))
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
func _state(tick: int, entries: Array) -> void:
	_after_lag(_receive_state.bind(tick, entries))


## Runs `update` now, or after the simulated lag.
func _after_lag(update: Callable) -> void:
	if simulated_lag > 0.0:
		_delayed_in.append([Time.get_ticks_msec() + simulated_lag * 1000.0, update])
	else:
		update.call()


func _receive_state(tick: int, entries: Array) -> void:
	if raid == null:
		return
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


## Every strongpoint, in map order: [holder name, holder is a player,
## taker name, progress percent, contested, yours].
@rpc("authority", "call_remote", "reliable")
func _strongpoints(states: Array) -> void:
	if raid == null:
		return
	for i in mini(states.size(), raid.strongpoints.size()):
		var state: Array = states[i]
		if state.size() < 6:
			continue
		var point := raid.strongpoints[i]
		point.holder_name = str(state[0])
		point.holder = "held" if point.holder_name != "" else ""
		point.holder_is_player = bool(state[1])
		point.taker_name = str(state[2])
		point.taker = "taking" if point.taker_name != "" else ""
		point.progress = clampf(float(state[3]) / 100.0, 0.0, 1.0)
		point.contested = bool(state[4])
		point.viewer_holds = bool(state[5])
		point.refresh_look()


## How hot the war is and where, for the sky and the HUD.
@rpc("authority", "call_remote", "unreliable_ordered")
func _war(intensity: float, centre: Vector3) -> void:
	if raid != null:
		raid.war.intensity = clampf(intensity, 0.0, 1.0)
		raid.war.centre = centre


## A player's public standing: [renown, rank, streak, bounty, exposed, marked,
## scrip carried].
@rpc("authority", "call_remote", "reliable")
func _standing(id: int, standing: Array) -> void:
	var actor: Actor = _actors.get(id)
	if actor == null or not is_instance_valid(actor) or standing.size() < 6:
		return
	actor.renown = int(standing[0])
	actor.rank = int(standing[1])
	actor.streak = int(standing[2])
	actor.bounty = int(standing[3])
	actor.exposed = bool(standing[4])
	actor.marked = bool(standing[5])
	if standing.size() > 6:
		actor.scrip = int(standing[6])


## A player tagged someone: they and their side are told, nobody else.
func _on_server_tagged(target: Actor, tagger: Actor) -> void:
	if not _ids.has(target) or not _ids.has(tagger):
		return
	for peer in _joined_peers:
		var viewer: Actor = _peer_actor.get(peer)
		if viewer == null or not is_instance_valid(viewer):
			continue
		if viewer == tagger or Visor.allied(tagger, viewer):
			_visor_tag.rpc_id(peer, _ids[tagger], _ids[target], float(tagger.visor.tags.get(target, 0.0)))


## The answer to your scan: where everyone it caught was standing.
@rpc("authority", "call_remote", "reliable")
func _visor_ghosts(found: Array) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me):
		me.visor.show_ghosts(found)


## Someone's scan caught you, from `origin`.
@rpc("authority", "call_remote", "reliable")
func _visor_felt(origin: Vector3) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null and is_instance_valid(me):
		me.visor.felt_scan.emit(origin)


## Someone on your side tagged a target.
@rpc("authority", "call_remote", "reliable")
func _visor_tag(tagger_id: int, target_id: int, seconds: float) -> void:
	var tagger: Actor = _actors.get(tagger_id)
	var target: Actor = _actors.get(target_id)
	if tagger != null and is_instance_valid(tagger) and target != null and is_instance_valid(target):
		tagger.visor.add_tag(target, clampf(seconds, 0.0, 30.0))


@rpc("authority", "call_remote", "reliable")
func _war_feed(text: String) -> void:
	if raid != null:
		raid.war_feed.emit(text)


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	var me: Actor = _actors.get(my_actor_id)
	if me != null:
		me.notice.emit(text)
		if text.begins_with("Looted "):
			Sfx.play("loot")


## Arena: ask the server for something (see `Arena.request`). A refusal
## comes back as a notice.
func arena_request(action: String, args := {}) -> void:
	if _is_connected() and my_actor_id >= 0:
		_arena_request.rpc_id(1, action, args)


@rpc("authority", "call_remote", "reliable")
func _arena_board(p_board: Dictionary) -> void:
	_after_lag(_receive_board.bind(p_board))


func _receive_board(p_board: Dictionary) -> void:
	var arena := raid as Arena
	if arena == null:
		return
	var was: String = arena.board.get("phase", "")
	arena.board = p_board
	# A fighter's guns are refilled on the server as the bout starts; do the
	# same to your own copy so the two agree.
	var me: Actor = _actors.get(my_actor_id)
	var bout: Dictionary = p_board.get("bout", {})
	if me != null and p_board.get("phase", "") == "countdown" and was != "countdown" \
			and String(me.name) in bout.get("nodes", []):
		Arena.refresh_fighter(me)


## Your sign-out started, with this many seconds to go, or stopped (below zero).
@rpc("authority", "call_remote", "reliable")
func _sign_out(seconds_left: float) -> void:
	var me: Actor = _actors.get(my_actor_id)
	var state := raid.state_for(me) if raid != null and me != null else null
	if state != null:
		state.sign_out_left = seconds_left
		state.sign_out_total = maxf(seconds_left, 0.0)


@rpc("authority", "call_remote", "reliable")
func _run_finished(result: Dictionary) -> void:
	if result.get("outcome", "") == "died":
		_can_redeploy = true
	else:
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


# ---------------------------------------------------------------- social ----
# The phone: who is online, messages, invites and news. The server keeps it all
# in `social` (`core/social/social_service.gd`) and sends each player a fresh
# snapshot whenever something they can see changes. A client only sends
# requests; the server always knows who sent them from the peer's sign-in.

## Server: a peer finished signing in.
func _social_joined(peer: int) -> void:
	var account_id: String = _peer_account[peer]
	social.player_online(account_id, stash.snapshot(account_id).get("name", account_id), "lobby")
	_broadcast_social()


## Server: a signed-in peer is going away.
func _social_left(peer: int) -> void:
	var account_id: String = _peer_account.get(peer, "")
	if account_id == "":
		return
	# Another connection for the same account may still be signed in.
	for other: int in _peer_account:
		if other != peer and _peer_account[other] == account_id:
			return
	social.player_offline(account_id)
	_broadcast_social(peer)


## Server: a player moved somewhere else ("lobby", "raid", or a place another
## feature adds, see `SocialService.PLACE_NAMES`).
func _social_moved(peer: int, where: String) -> void:
	_set_presence(peer, where)


func _set_presence(peer: int, where: String) -> void:
	if not _peer_account.has(peer):
		return
	social.set_where(_peer_account[peer], where)
	_broadcast_social()


## Server: sends every signed-in player their phone snapshot. `skip` is a peer
## that is on its way out.
func _broadcast_social(skip := 0) -> void:
	var peers := _api.get_peers()
	for peer: int in _peer_account:
		if peer != skip and peer in peers:
			_send_social(peer)


func _send_social(peer: int) -> void:
	if _peer_account.has(peer) and peer in _api.get_peers():
		_social.rpc_id(peer, social.snapshot(_peer_account[peer]))


## Server: the peer signed in as `account_id`, or -1.
func _peer_for_account(account_id: String) -> int:
	for peer: int in _peer_account:
		if _peer_account[peer] == account_id and peer in _api.get_peers():
			return peer
	return -1


## The sender's account id, or "" when the sender has not signed in.
func _social_sender() -> String:
	if not is_server:
		return ""
	return _peer_account.get(_api.get_remote_sender_id(), "")


func _social_result(peer: int, result: Dictionary, others: Array[String] = []) -> void:
	if not result.ok:
		_social_error.rpc_id(peer, result.error)
	_send_social(peer)
	for other in others:
		var other_peer := _peer_for_account(other)
		if other_peer > 0 and other_peer != peer:
			_send_social(other_peer)


@rpc("any_peer", "call_remote", "reliable")
func _request_message(to: String, text: String) -> void:
	var from := _social_sender()
	if from == "":
		return
	var peer := _api.get_remote_sender_id()
	var result := social.send_message(from, to.left(64), text.left(SocialService.MAX_MESSAGE * 2))
	var others: Array[String] = []
	if result.ok:
		others.append(to)
	_social_result(peer, result, others)
	if result.ok:
		var to_peer := _peer_for_account(to)
		if to_peer > 0:
			_social_notice.rpc_id(to_peer, "%s: %s" % [result.message.from_name, result.message.text])


@rpc("any_peer", "call_remote", "reliable")
func _request_invite(to: String, kind: String) -> void:
	var from := _social_sender()
	if from == "":
		return
	var peer := _api.get_remote_sender_id()
	var result := social.invite(from, to.left(64), kind.left(16), world_id)
	var others: Array[String] = []
	if result.ok:
		others.append(to)
	_social_result(peer, result, others)
	if result.ok:
		_social_notice.rpc_id(peer, "Invite sent to %s." % social.name_of(to))
		var to_peer := _peer_for_account(to)
		if to_peer > 0:
			_social_notice.rpc_id(to_peer, _invite_text(result.invite))


func _invite_text(invite: Dictionary) -> String:
	if invite.kind == "base":
		return "%s invites you to their home base." % invite.from_name
	var world := Worlds.get_world(invite.get("world_id", ""))
	return "%s invites you to %s." % [invite.from_name, world.display_name if world else "their raid"]


@rpc("any_peer", "call_remote", "reliable")
func _request_answer_invite(invite_id: int, accept: bool) -> void:
	var account_id := _social_sender()
	if account_id == "":
		return
	var peer := _api.get_remote_sender_id()
	var result := social.answer_invite(account_id, invite_id, accept)
	_social_result(peer, result)
	if not result.ok:
		return
	var invite: Dictionary = result.invite
	var from_peer := _peer_for_account(invite.from)
	if from_peer > 0:
		_social_notice.rpc_id(from_peer, "%s %s your invite." % [
				social.name_of(account_id), "accepted" if accept else "declined"])
	if not accept:
		return
	if invite.kind == "base":
		# A base is a view of the owner's gear, so send just that.
		var owner := stash.snapshot(invite.from)
		_base_visit.rpc_id(peer, invite.from_name, owner.get("stash", []), owner.get("loadout", {}))
	else:
		_world_invite_accepted.rpc_id(peer, invite)


## `action` is "add", "remove", "block" or "unblock".
@rpc("any_peer", "call_remote", "reliable")
func _request_contact(action: String, other: String) -> void:
	var account_id := _social_sender()
	if account_id == "":
		return
	var peer := _api.get_remote_sender_id()
	other = other.left(64)
	var result: Dictionary
	match action:
		"add": result = social.add_contact(account_id, other)
		"remove": result = social.remove_contact(account_id, other)
		"block": result = social.block(account_id, other)
		"unblock": result = social.unblock(account_id, other)
		_: return
	_social_result(peer, result)


@rpc("authority", "call_remote", "reliable")
func _social(snapshot: Dictionary) -> void:
	social_state = snapshot
	social_changed.emit(snapshot)


@rpc("authority", "call_remote", "reliable")
func _social_error(reason: String) -> void:
	social_error.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _social_notice(text: String) -> void:
	social_notice.emit(text)


@rpc("authority", "call_remote", "reliable")
func _world_invite_accepted(invite: Dictionary) -> void:
	world_invite_accepted.emit(invite)


@rpc("authority", "call_remote", "reliable")
func _base_visit(owner_name: String, owner_stash: Array, owner_loadout: Dictionary) -> void:
	base_visit_requested.emit(owner_name, owner_stash, owner_loadout)


## Phone: message a player on this server, or a saved contact.
func send_message(to: String, text: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_message.rpc_id(1, to, text)


## Phone: invite a player online here to this server's raid ("world") or to
## your home base ("base").
func send_invite(to: String, kind: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_invite.rpc_id(1, to, kind)


func answer_invite(invite_id: int, accept: bool) -> void:
	if _is_connected() and not account.is_empty():
		_request_answer_invite.rpc_id(1, invite_id, accept)


## Phone: "add", "remove", "block" or "unblock" a contact.
func change_contact(action: String, other: String) -> void:
	if _is_connected() and not account.is_empty():
		_request_contact.rpc_id(1, action, other)


## Containers and vehicles this session knows about. For tests and tools.
func containers() -> Array:
	return _containers.values()


func vehicles() -> Array:
	return _vehicles.values()


## The world or venue with this id: a world from the registry, or the arena.
static func world_for(id: String) -> WorldDef:
	if id == ArenaVenue.ID:
		return ArenaVenue.new()
	return Worlds.get_world(id)


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
