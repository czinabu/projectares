extends Node
## Entry point. Switches between the hub and a raid, solo or online.
##
## Run with `-- --server [--world <id>] [--port <n>] [--bots <n>] [--squad-spawn]`
## for a dedicated server: no hub, no window needed, just a raid that players join.

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
var _online_kit: Array[String] = []


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_local_server()


# ------------------------------------------------------------------ solo ----

func start_raid(world_id: String) -> void:
	var world := Worlds.get_world(world_id)
	if world == null or raid != null:
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
	_online_kit.clear()
	net = NetSession.new()
	net.name = "Net"
	net.player_name = Profile.player_name
	net.mastery_picks = Profile.mastery.active_picks()
	net.kit_provider = func(world: WorldDef) -> Array:
		_online_kit = Profile.checkout_loadout(world)
		return _online_kit
	add_child(net)
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
		if net == session and raid == null:
			_on_online_failed("The server did not answer."))


func _on_online_joined(p_raid: Raid) -> void:
	raid = p_raid
	hub.visible = false
	hub.set_online_status("")
	_attach_player_view()


func _on_online_failed(reason: String) -> void:
	_return_online_kit()
	if net:
		net.queue_free()
		net = null
	if _join_attempts > 0:
		# A server we just started needs a moment before it listens.
		await get_tree().create_timer(1.0).timeout
		if net == null and raid == null:
			_try_join()
		return
	_stop_local_server()
	hub.set_online_status(reason)


func _on_online_disconnected() -> void:
	# The run never finished, so the gear you brought comes back.
	_return_online_kit()
	_leave_raid()
	_stop_local_server()
	hub.refresh({})
	hub.set_online_status("Lost the connection to the server. Your gear was returned.")
	hub.visible = true


func _on_online_finished(result: Dictionary) -> void:
	_online_kit.clear()
	Raid.apply_result(result)
	await get_tree().create_timer(1.5).timeout
	_leave_raid()
	_stop_local_server()
	hub.refresh(result)
	hub.visible = true


func _return_online_kit() -> void:
	if not _online_kit.is_empty():
		Profile.add_to_stash(_online_kit)
		_online_kit.clear()


func _stop_local_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback
