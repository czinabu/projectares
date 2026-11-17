extends RefCounted
## Starting a server of your own never leaves you on the travel screen: it
## moves to free ports when an old server still holds its own, a server that
## stops before it lets you in is noticed at once and started again, and a
## server left behind by a game that is gone stops itself (its heartbeat).
## Starts servers (each a `NetSession` per world), so it runs in the online
## tier. `-- --groups HostRecoveryTests` runs just these.

const PORT := 25161


static func run(t: Node) -> void:
	print("Host recovery: a server of your own always lets you in or sends you home")
	var Main: Script = load("res://core/main.gd")

	# Ports another server still holds are passed over.
	var held := PacketPeerUDP.new()
	held.bind(PORT)
	var offsets: Array[int] = [0, 1]
	t.check(not Main.port_free(PORT), "a port something listens on is not free")
	t.check(Main.free_host_port(PORT, offsets) == PORT + Main.HOST_PORT_STEP,
			"a server of your own moves past ports an old server still holds")
	held.close()
	t.check(Main.free_host_port(PORT, offsets) == PORT, "and keeps its own ports when they are free")

	# A server left running by a game that is gone notices and stops.
	var beat := "user://test_heartbeat"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(beat))
	t.check(Main.heartbeat_stale(beat), "no heartbeat at all: the game is gone")
	var file := FileAccess.open(beat, FileAccess.WRITE)
	file.store_string("x")
	file.close()
	var now := Time.get_unix_time_from_system()
	t.check(not Main.heartbeat_stale(beat, now), "a fresh heartbeat keeps the server running")
	t.check(Main.heartbeat_stale(beat, now + Main.HEARTBEAT_STALE + 5.0), "a stale heartbeat stops it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(beat))

	Profile.reset()
	Profile.home_server = ""
	Profile.player_name = "Rook"
	Profile.welcome_granted = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.host_port = PORT
	main.host_args = PackedStringArray(["--accounts", t.NET_ACCOUNTS, "--bots", "0"])
	t.add_child(main)
	await t.frames(20)

	# The server dies while starting: noticed on the next try, started again.
	main.base.leave_requested.emit()
	t.check(main._server_pid > 0 and main.net != null, "the door starts a server of your own")
	var first_pid: int = main._server_pid
	OS.kill(first_pid)
	var started := Time.get_ticks_msec()
	await t._wait_until(func() -> bool: return main._server_pid != first_pid or main.base != null, 1800)
	t.check(main._server_pid > 0 and main._server_pid != first_pid and main.net != null,
			"a server that stops before it lets you in is started again")
	t.check("again" in main.hub.online_status(), "and the travel line says so (%s)" % main.hub.online_status())

	# Out of restarts: home with the reason, quickly, not after every attempt.
	OS.kill(main._server_pid)
	await t._wait_until(func() -> bool: return main.base != null and main.net == null, 1800)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	t.check(main.base != null and main.net == null and main.raid == null,
			"when it stops again you are taken home instead of left waiting")
	t.check(took < Main.JOIN_TIMEOUT * 2.0, "and soon (%.1f s)" % took)
	t.check("stopped" in main.hub.online_status(), "with what went wrong (%s)" % main.hub.online_status())

	# And the next trip out works.
	main.base.leave_requested.emit()
	await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 3600)
	t.check(main.raid != null and main.raid.world.safe_zone, "the next trip out reaches the plaza")
	main._stop_local_server()
	main.queue_free()
	await t.frames(30)
	Profile.reset()
	Profile.home_server = ""
