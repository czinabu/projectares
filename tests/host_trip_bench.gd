extends Node
## Times the trip out of your base's door to a server of your own, the way
## the game takes it (`Main.head_out`): starting the server process, every
## join attempt, signing in, and arriving in the plaza. Prints a timeline,
## so a slow trip shows which step the time went to.
##
##   godot --headless --path . res://tests/host_trip_bench.tscn
##
## It plays as the saved profile on this computer and never writes to it
## (`Profile.persist` is off). The server keeps its accounts apart, in
## `--accounts` (default `user://trip_bench_accounts`), so no real account
## changes. `--port` moves it off the usual ports; `--runs` repeats the trip.

const MainScene := "res://scenes/main.tscn"

var _t0 := 0
var _main: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(_arg(args, "--port", "25890"))
	var runs := int(_arg(args, "--runs", "1"))
	var accounts := _arg(args, "--accounts", "user://trip_bench_accounts")
	Profile.persist = false
	_main = load(MainScene).instantiate()
	_main.host_port = port
	_main.host_args = PackedStringArray(["--accounts", accounts])
	add_child(_main)
	await _frames(10)
	var failed := 0
	for run in runs:
		if not await _trip(run + 1):
			failed += 1
		if _main.raid != null:
			_main._leave_raid()
		_main._plaza_port = -1
		_main.leave_server()
		await _frames(30)
	_main._stop_local_server()
	print("Trip bench: %d of %d trips reached the plaza" % [runs - failed, runs])
	get_tree().quit(1 if failed > 0 else 0)


func _trip(run: int) -> bool:
	if _main.base == null:
		_main.go_home()
		await _frames(10)
	print("Trip %d, as %s:" % [run, Profile.player_name])
	_t0 = Time.get_ticks_msec()
	var status := ""
	var net_id := 0
	var pid := 0
	var connected := false
	var signed := false
	_main.base.leave_requested.emit()
	while Time.get_ticks_msec() - _t0 < 150000:
		if _main._server_pid != pid:
			pid = _main._server_pid
			_note("server process %d" % pid)
		var net: NetSession = _main.net
		if net != null and net.get_instance_id() != net_id:
			net_id = net.get_instance_id()
			connected = false
			signed = false
			_note("join attempt to port %d (%d left)" % [_main._join_port, _main._join_attempts])
		if net != null and not connected and net._api.multiplayer_peer != null \
				and net._api.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			_note("connected, signing in")
		if net != null and not signed and not net.account.is_empty():
			signed = true
			_note("signed in")
		if _main.hub.online_status() != status:
			status = _main.hub.online_status()
			_note("travel line: %s" % status)
		if _main.raid != null and _main.raid.player != null:
			_note("in %s" % _main.raid.world.display_name)
			return true
		if _main.base != null and _main.net == null and Time.get_ticks_msec() - _t0 > 1000:
			_note("sent home")
			return false
		await get_tree().process_frame
	_note("gave up waiting")
	return false


func _note(text: String) -> void:
	print("  %6.2f s  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, text])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback
