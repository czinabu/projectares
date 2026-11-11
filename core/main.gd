extends Node
## Entry point. Switches between the hub and a raid, solo or online.
##
## Run with `-- --server [--world <id>] [--port <n>] [--bots <n>] [--squad-spawn]
## [--accounts <folder>] [--no-rewind]` for a dedicated server: no hub, no window needed,
## just a raid that players join. Player stashes are saved in the accounts
## folder (`user://accounts` unless given).

const JOIN_TIMEOUT := 12.0
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")

var hub: Hub
var raid: Raid
var controller: PlayerController
var hud: Hud
var nameplates: CanvasLayer
var scoreboard: CanvasLayer
var net: NetSession
var _server_pid := -1
var _join_attempts := 0
var _join_address := ""
var _join_port := NetSession.DEFAULT_PORT


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_local_server()


# ------------------------------------------------------------------ solo ----

func start_raid(world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	if world == null or raid != null or net != null:
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
	net.lobby_error.connect(func(reason: String) -> void: hub.set_online_status(reason))
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
	hub.set_online_status("")
	hub.enter_lobby(account, Worlds.get_world(net.world_id))


func _on_online_account_changed(account: Dictionary) -> void:
	if raid == null:
		hub.update_account(account)


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
	hub.set_online_status(reason)


## The connection dropped in the middle of a raid. The server treats that as
## a death, so the gear is gone.
func _on_online_disconnected() -> void:
	_leave_raid()
	_stop_local_server()
	hub.leave_lobby()
	hub.refresh({})
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
