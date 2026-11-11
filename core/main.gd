extends Node
## Entry point. Switches between the hub and a raid, solo or online.
##
## Run with `-- --server [--world <id>] [--port <n>] [--bots <n>] [--squad-spawn]
## [--accounts <folder>] [--no-rewind] [--arena-port <n>] [--no-arena]` for a
## dedicated server: no hub, no window needed, just a raid that players join.
## Player stashes are saved in the accounts folder (`user://accounts` unless
## given). The same process also runs the arena on `--arena-port` (the raid
## port plus `ARENA_PORT_OFFSET` unless given), sharing the same accounts.

const JOIN_TIMEOUT := 12.0
const StashRules := preload("res://core/account/stash_rules.gd")
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")
const ArenaHudScript := preload("res://core/arena/arena_hud.gd")
## The arena listens this many ports above the raid server.
const ARENA_PORT_OFFSET := 10

var hub: Hub
var raid: Raid
var controller: PlayerController
var hud: Hud
var nameplates: CanvasLayer
var scoreboard: CanvasLayer
var net: NetSession
## The home base while the player is walking around it, else null.
var base: HomeBase
var base_hud: CanvasLayer
var _server_pid := -1
var _join_attempts := 0
var _join_address := ""
var _join_port := NetSession.DEFAULT_PORT
## Online: the raid lobby's port, while visiting that server's arena.
var _lobby_port := -1
## Server: the arena session beside the raid.
var arena_net: NetSession


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		_run_dedicated_server(args)
		return
	hub = Hub.new()
	add_child(hub)
	hub.deploy_requested.connect(start_raid)
	hub.host_requested.connect(host_and_join)
	hub.join_requested.connect(join_online)
	hub.online_equip_requested.connect(func(slot: String, item_id: String) -> void:
		if net:
			net.equip(slot, item_id))
	hub.online_pick_requested.connect(func(track: String, variant_id: String) -> void:
		if net:
			net.pick_mastery(track, variant_id))
	hub.online_deploy_requested.connect(func() -> void:
		if net and raid == null:
			hub.set_online_status("Deploying...")
			net.deploy())
	hub.online_leave_requested.connect(leave_server)
	hub.base_requested.connect(enter_base)
	hub.arena_requested.connect(open_arena)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_local_server()


# ------------------------------------------------------------- home base ----

## Leaves the hub screen for the home base, which shows the stash the hub
## was showing: the local profile's, or the server's while in a lobby.
func enter_base() -> void:
	_open_base(hub.stash_items(), hub.current_loadout(), "")


## Opens someone else's base to look around. Nothing in it can be equipped.
## `stash` and `loadout` are that player's, as their server reports them.
func visit_base(owner_name: String, stash: Array, loadout: Dictionary) -> void:
	_open_base(stash, loadout, owner_name if owner_name != "" else "Raider")


func _open_base(stash: Array, loadout: Dictionary, owner_name: String) -> void:
	if base != null or raid != null:
		return
	hub.visible = false
	base = HomeBase.new()
	base.name = "HomeBase"
	base.owner_name = owner_name
	base.read_only = owner_name != ""
	base.show_gear(stash, loadout)
	add_child(base)
	base.equip_requested.connect(_on_base_equip)
	base.leave_requested.connect(leave_base)
	controller = PlayerController.new()
	controller.setup(base.player)
	base.add_child(controller)
	base_hud = BaseHudScript.new()
	base_hud.name = "BaseHud"
	base_hud.setup(base)
	base.add_child(base_hud)


func leave_base() -> void:
	if base == null:
		return
	base.queue_free()
	base = null
	base_hud = null
	controller = null
	hub.refresh_gear()
	hub.visible = true


## Gear used in the base changes the loadout the same way the hub's pickers
## do: straight into the profile solo, as a request to the server online.
func _on_base_equip(slot: String, item_id: String) -> void:
	if hub.in_lobby():
		if net:
			net.equip(slot, item_id)
		return
	if item_id == "":
		Profile.unequip(slot)
	else:
		Profile.equip(slot, item_id)
	_refresh_base()


## Shows the base whatever the hub would show now.
func _refresh_base() -> void:
	if base and not base.read_only:
		base.show_gear(hub.stash_items(), hub.current_loadout())


# ----------------------------------------------------------------- arena ----

## Opens the arena: the server's, while in its lobby, or a solo one against
## bot gladiators. The plaza's arena gate calls this too.
func open_arena() -> void:
	if raid != null or base != null:
		return
	if net != null:
		if not hub.in_lobby():
			return
		# Leave the lobby for the arena session on the same server.
		_lobby_port = _join_port
		net.queue_free()
		net = null
		hub.set_online_status("Entering the arena...")
		_begin_join(_join_address, _lobby_port + ARENA_PORT_OFFSET, 3)
		return
	hub.visible = false
	var arena := Arena.new()
	arena.name = "Raid"
	raid = arena
	add_child(arena)
	# Your own loadout, but nothing leaves the stash: no gear is at risk here.
	var kit := StashRules.checkout(Profile.stash.duplicate(), Profile.loadout.duplicate(), Arena.ArenaVenue.new())
	arena.start_solo(kit, Profile.mastery.active_picks())
	_attach_player_view()


func leave_arena() -> void:
	if not raid is Arena:
		return
	var back_online := net != null and _lobby_port > 0
	_leave_raid()
	hub.visible = true
	hub.refresh_gear()
	if back_online:
		_join_port = _lobby_port
		_lobby_port = -1
		hub.set_online_status("Back to the lobby...")
		_begin_join(_join_address, _join_port, 3)


# ------------------------------------------------------------------ solo ----

func start_raid(world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	if world == null or raid != null or net != null or base != null:
		return
	hub.visible = false
	raid = Raid.new()
	raid.name = "Raid"
	add_child(raid)
	raid.start(world, -1, Profile.checkout_loadout(world), Profile.mastery.active_picks())
	_attach_player_view()
	raid.ended.connect(_on_raid_ended)


func _attach_player_view() -> void:
	controller = PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	hud = Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	nameplates = NameplatesScript.new()
	nameplates.name = "Nameplates"
	nameplates.setup(raid)
	raid.add_child(nameplates)
	scoreboard = ScoreboardScript.new()
	scoreboard.name = "Scoreboard"
	scoreboard.setup(raid)
	raid.add_child(scoreboard)
	if raid is Arena:
		var arena_hud := ArenaHudScript.new()
		arena_hud.name = "ArenaHud"
		arena_hud.setup(raid)
		arena_hud.leave_requested.connect(leave_arena)
		raid.add_child(arena_hud)


func _on_raid_ended(result: Dictionary) -> void:
	# Leave a beat so the player sees what happened before the hub appears.
	await get_tree().create_timer(1.5).timeout
	_leave_raid()
	hub.refresh(result)
	hub.visible = true


func _leave_raid() -> void:
	if net:
		net.queue_free()
		net = null
		raid = null
	elif raid:
		raid.queue_free()
		raid = null


# ---------------------------------------------------------------- online ----

func _run_dedicated_server(args: PackedStringArray) -> void:
	var world_id := _arg(args, "--world", "")
	if Worlds.get_world(world_id) == null:
		world_id = Worlds.all()[0].id
	var port := int(_arg(args, "--port", str(NetSession.DEFAULT_PORT)))
	net = NetSession.new()
	net.name = "Net"
	net.bot_count = int(_arg(args, "--bots", "-1"))
	net.squad_spawn = "--squad-spawn" in args
	net.lag_compensation = "--no-rewind" not in args
	var accounts := _arg(args, "--accounts", "")
	if accounts != "":
		net.stash.save_dir = accounts
	add_child(net)
	var err := net.host(world_id, port)
	if err != OK:
		push_error("Server: could not listen on port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	print("Server: running %s on port %d" % [world_id, port])
	if "--no-arena" in args:
		return
	# The arena shares the accounts, so wagers and the stash are one wallet.
	var arena_port := int(_arg(args, "--arena-port", str(port + ARENA_PORT_OFFSET)))
	arena_net = NetSession.new()
	arena_net.name = "ArenaNet"
	arena_net.stash = net.stash
	arena_net.lag_compensation = net.lag_compensation
	add_child(arena_net)
	err = arena_net.host(Arena.ArenaVenue.ID, arena_port)
	if err != OK:
		push_warning("Server: no arena, could not listen on port %d (%s)" % [arena_port, error_string(err)])
		arena_net.queue_free()
		arena_net = null
		return
	print("Server: arena on port %d" % arena_port)


## Starts a server on this machine as a second process, then joins it.
func host_and_join(world_id: String) -> void:
	if raid != null or net != null:
		return
	_stop_local_server()
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server", "--world", world_id])
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	if _server_pid <= 0:
		hub.set_online_status("Could not start a server on this computer.")
		return
	hub.set_online_status("Starting a server...")
	_begin_join("127.0.0.1", NetSession.DEFAULT_PORT, 8)


## `address` is "host" or "host:port".
func join_online(address: String) -> void:
	if raid != null or net != null:
		return
	var host := address.strip_edges()
	var port := NetSession.DEFAULT_PORT
	if ":" in host:
		port = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	if host == "":
		hub.set_online_status("Type the server's address first.")
		return
	hub.set_online_status("Connecting to %s..." % host)
	_begin_join(host, port, 1)


func _begin_join(host: String, port: int, attempts: int) -> void:
	_join_address = host
	_join_port = port
	_join_attempts = attempts
	_try_join()


func _try_join() -> void:
	_join_attempts -= 1
	net = NetSession.new()
	net.name = "Net"
	net.player_name = Profile.player_name
	net.secret = Profile.get_online_secret()
	# `-- --lag 120 --loss 10` fakes a bad connection: milliseconds of delay
	# each way, and the percent of input packets lost.
	var args := OS.get_cmdline_user_args()
	net.simulated_lag = float(_arg(args, "--lag", "0")) / 1000.0
	net.simulated_loss = float(_arg(args, "--loss", "0")) / 100.0
	add_child(net)
	net.signed_in.connect(_on_online_signed_in)
	net.account_changed.connect(_on_online_account_changed)
	net.lobby_error.connect(func(reason: String) -> void:
		hub.set_online_status(reason)
		if base_hud:
			base_hud.show_notice(reason))
	net.joined.connect(_on_online_joined)
	net.failed.connect(_on_online_failed)
	net.disconnected.connect(_on_online_disconnected)
	net.run_finished.connect(_on_online_finished)
	var err := net.join(_join_address, _join_port)
	if err != OK:
		_on_online_failed("Could not open a connection (%s)." % error_string(err))
		return
	# A server that never answers should not leave the hub waiting forever.
	var session := net
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(func() -> void:
		if net == session and net.account.is_empty():
			_on_online_failed("The server did not answer."))


## Signed in: the hub becomes that server's lobby.
func _on_online_signed_in(account: Dictionary) -> void:
	_join_attempts = 0
	if _lobby_port > 0:
		# Signed in to the arena: walk straight into the stands.
		hub.update_account(account)
		net.deploy()
		return
	hub.set_online_status("")
	hub.enter_lobby(account, Worlds.get_world(net.world_id))


func _on_online_account_changed(account: Dictionary) -> void:
	if raid == null:
		hub.update_account(account)
		_refresh_base()


func _on_online_joined(p_raid: Raid) -> void:
	raid = p_raid
	hub.visible = false
	hub.set_online_status("")
	_attach_player_view()


## Could not connect or sign in, or the connection dropped in the lobby.
func _on_online_failed(reason: String) -> void:
	if net:
		if net.refused:
			_join_attempts = 0
		net.queue_free()
		net = null
	if _join_attempts > 0:
		# A server we just started needs a moment before it listens.
		await get_tree().create_timer(1.0).timeout
		if net == null and raid == null:
			_try_join()
		return
	_stop_local_server()
	hub.leave_lobby()
	if _lobby_port > 0:
		reason = "Could not enter the arena: %s" % reason
		_join_port = _lobby_port
		_lobby_port = -1
	hub.set_online_status(reason)
	# A base open on the server's stash falls back to the local one.
	_refresh_base()
	if base_hud:
		base_hud.show_notice(reason)


## The connection dropped in the middle of a raid. The server treats that as
## a death, so the gear is gone.
func _on_online_disconnected() -> void:
	var in_arena := raid is Arena
	_leave_raid()
	_stop_local_server()
	hub.leave_lobby()
	hub.refresh({})
	if in_arena:
		_lobby_port = -1
		hub.set_online_status("Lost the connection to the arena. Your gear is safe.")
	else:
		hub.set_online_status("Lost the connection to the server during the raid. What you carried is lost.")
	hub.visible = true


## The server has already settled the run into your account there. Nothing
## is written to the local profile.
func _on_online_finished(result: Dictionary) -> void:
	var account := net.account
	await get_tree().create_timer(1.5).timeout
	_leave_raid()
	hub.update_account(account)
	hub.refresh(result)
	hub.visible = true
	# Back to the lobby for the next raid.
	hub.set_online_status("Returning to the lobby...")
	_begin_join(_join_address, _join_port, 3)


## Disconnects from the lobby and shows the solo hub again.
func leave_server() -> void:
	if raid != null:
		return
	_join_attempts = 0
	_lobby_port = -1
	if net:
		net.queue_free()
		net = null
	_stop_local_server()
	hub.leave_lobby()
	hub.set_online_status("")


func _stop_local_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback
