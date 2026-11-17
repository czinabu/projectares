extends Node
## Measures what a big battle costs the player's game: frame rate, where the
## frame time goes, and what is drawn. Runs the real game (`Main`, with the
## camera, HUD and nameplates) on Ashfront with a full army, puts the player
## where the fighting is thickest, and samples every frame.
##
##   godot --path . res://tests/frame_bench.tscn -- --mode solo --bots 120
##   godot --path . res://tests/frame_bench.tscn -- --mode online --bots 120
##
## Online it starts a dedicated server process, joins it as a client, waits
## for the war to warm up and drops in beside the fighting, then reports the
## client's frame rate and what the server sends it. Needs a display (or xvfb) to see rendering costs; it still
## runs headless, where only the game's own processing is measured.
## `--view third` measures third person; `--seconds` and `--warmup` set how
## long it measures and how long the armies march first.

const PORT := 25790
const MainScene := "res://scenes/main.tscn"

var _main: Node
var _server_pid := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := _arg(args, "--mode", "solo")
	var bots := int(_arg(args, "--bots", "120"))
	var seconds := float(_arg(args, "--seconds", "20"))
	var warmup := float(_arg(args, "--warmup", "20"))
	var third := _arg(args, "--view", "first") == "third"
	Profile.persist = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var world := Worlds.get_world("ashfront")
	world.bot_count = bots
	# A steady army for a fair measurement: no war reinforcements on top.
	world.war_reinforcements = 0
	_main = load(MainScene).instantiate()
	add_child(_main)
	await _frames(5)
	var ok := false
	if mode == "online":
		ok = await _start_online(bots, warmup)
	else:
		ok = await _start_solo(warmup)
	if not ok:
		print("Frame bench: could not start (%s)" % mode)
		_finish(1)
		return
	if third and not _main.controller.is_third_person():
		_main.controller.toggle_view()
	if "--probe" in args:
		await _probe()
	else:
		await _measure(mode, seconds)
	# `--shot <file.png>` saves the last frame, to check the look by eye.
	var shot := _arg(args, "--shot", "")
	if shot != "" and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
	_finish(0)


func _start_solo(warmup: float) -> bool:
	_main.start_raid("ashfront")
	await _frames(5)
	var raid: Raid = _main.raid
	if raid == null or raid.player == null:
		return false
	_toughen(raid.player)
	print("Frame bench: solo, %d bots, marching for %.0f s" % [raid.bots.size(), warmup])
	await _seconds(warmup)
	# Drop the player beside the thickest fighting, facing it.
	var hot := _hot_spot(raid.bots)
	var out := Vector3(hot.x, 0, hot.z).normalized() if Vector3(hot.x, 0, hot.z).length() > 1.0 else Vector3.FORWARD
	var at := hot + out * 18.0
	if raid.map.has_method("ground_height"):
		at.y = raid.map.call("ground_height", at.x, at.z) + 0.2
	raid.player.global_position = at
	raid.player.velocity = Vector3.ZERO
	_face(hot)
	await _seconds(2.0)
	return true


func _start_online(bots: int, warmup: float) -> bool:
	# A fresh account store: one left by an earlier run holds that run's secret.
	var accounts := OS.get_user_data_dir().path_join("frame_bench_accounts")
	if DirAccess.dir_exists_absolute(accounts):
		for file in DirAccess.get_files_at(accounts):
			DirAccess.remove_absolute(accounts.path_join(file))
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server", "--world", "ashfront", "--no-plaza", "--no-arena", "--port", str(PORT),
			"--bots", str(bots), "--accounts", accounts])
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	if _server_pid <= 0:
		return false
	# Joining while the server is still building its world times out; the
	# game's own retry (as when hosting) keeps knocking until it answers.
	await _seconds(3.0)
	_main._begin_join("127.0.0.1", PORT, 20)
	var waited := 0.0
	while (_main.net == null or _main.net.account.is_empty()) and waited < 60.0:
		await _seconds(0.25)
		waited += 0.25
	var net: NetSession = _main.net
	if net == null or net.account.is_empty():
		return false
	# Bots fighting bots warm the war up enough to offer a drop beside the
	# fighting; wait in the lobby for that, then take it.
	print("Frame bench: online, %d bots on the server, the armies march for %.0f s" % [bots, warmup])
	await _seconds(warmup)
	net.deploy("hot")
	waited = 0.0
	while (_main.raid == null or _main.raid.player == null) and waited < 20.0:
		await _seconds(0.25)
		waited += 0.25
	if _main.raid == null or _main.raid.player == null:
		return false
	await _seconds(3.0)
	_take_stats(net)
	return true


## A body that does not fall over while it is being measured. Solo only:
## online the server decides.
func _toughen(actor: Actor) -> void:
	actor.health.max_health = 1.0e9
	actor.health.health = 1.0e9


## The bot with the most other bots within 50 m.
func _hot_spot(actors: Array) -> Vector3:
	var best := Vector3.ZERO
	var most := -1
	for a: Actor in actors:
		if not is_instance_valid(a) or a.is_dead:
			continue
		var near := 0
		for b: Actor in actors:
			if is_instance_valid(b) and not b.is_dead and a.global_position.distance_squared_to(b.global_position) < 2500.0:
				near += 1
		if near > most:
			most = near
			best = a.global_position
	return best


func _face(point: Vector3) -> void:
	var controller: PlayerController = _main.controller
	var player: Actor = _main.raid.player
	var dir := point - player.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		return
	controller.yaw = atan2(-dir.x, -dir.z)
	controller.pitch = 0.0


func _measure(mode: String, seconds: float) -> void:
	var raid: Raid = _main.raid
	var vp := get_viewport().get_viewport_rid()
	var frame_ms: Array[float] = []
	var process_ms := 0.0
	var physics_ms := 0.0
	var nav_ms := 0.0
	var render_cpu := 0.0
	var render_gpu := 0.0
	var draws := 0.0
	var objects := 0.0
	var primitives := 0.0
	var near_sum := 0.0
	var samples := 0
	var net: NetSession = _main.net
	_take_stats(net)
	var cpu_began := _cpu_seconds(-1)
	var server_began := _cpu_seconds(_server_pid)
	var prof_began: Dictionary = (Engine.get_meta("prof") as Dictionary).duplicate() if Engine.has_meta("prof") else {}
	var began := Time.get_ticks_usec()
	var last := began
	while Time.get_ticks_usec() - began < seconds * 1000000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		nav_ms += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) \
				+ RenderingServer.get_frame_setup_time_cpu()
		render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		if raid.player != null and is_instance_valid(raid.player):
			near_sum += _count_near(raid, raid.player.global_position, 70.0)
		samples += 1
	var wall := (Time.get_ticks_usec() - began) / 1000000.0
	var n := maxi(samples, 1)
	if Engine.has_meta("prof"):
		var prof: Dictionary = Engine.get_meta("prof")
		var keys := prof.keys()
		keys.sort_custom(func(a, b) -> bool: return prof[a] > prof[b])
		for key in keys:
			var spent: float = (prof[key] - prof_began.get(key, 0)) / 1000.0
			print("  prof %-40s %7.2f ms a second, %6.2f ms a frame" % [key, spent / wall, spent / n])
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var p99: float = sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)] if not sorted.is_empty() else 0.0
	var p50: float = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	print("Frame bench result (%s, %s, %d actors in the world, %.0f within 70 m)" % [mode,
			"third person" if _main.controller.is_third_person() else "first person",
			_count_near(raid, Vector3.ZERO, INF), near_sum / n])
	print("  frames: %d in %.1f s -> %.1f fps average, median %.2f ms, 1%% worst %.2f ms" % [samples, wall,
			samples / wall, p50, p99])
	# Godot reports the slowest frame and tick of each second for these.
	print("  slowest each second: process %.2f ms, physics tick %.2f ms (navigation %.2f ms)"
			% [process_ms / n, physics_ms / n, nav_ms / n])
	print("  rendering: cpu %.2f ms, gpu %.2f ms, %.0f draw calls, %.0f objects, %.0fk primitives" % [render_cpu / n,
			render_gpu / n, draws / n, objects / n, primitives / n / 1000.0])
	var cpu := _cpu_seconds(-1) - cpu_began
	print("  this process: %.0f%% of one core" % (cpu / wall * 100.0))
	if _server_pid > 0:
		print("  server process: %.0f%% of one core" % ((_cpu_seconds(_server_pid) - server_began) / wall * 100.0))
	if net != null and is_instance_valid(net):
		var stats := _take_stats(net)
		print("  network: %.1f KB/s down, %.1f KB/s up" % [stats.x / 1024.0 / wall, stats.y / 1024.0 / wall])


## Draw counts with parts of the scene switched off in turn, to see what
## the frame is spent on.
func _probe() -> void:
	var raid: Raid = _main.raid
	var skins: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("actors"):
		if node != raid.player and Raid.together(node, raid):
			skins.append(node)
	var sun: DirectionalLight3D = null
	for node in raid.find_children("*", "DirectionalLight3D", true, false):
		sun = node
	await _probe_line("everything")
	for skin in skins:
		skin.visible = false
	await _probe_line("bot bodies hidden")
	for skin in skins:
		skin.visible = true
	if sun:
		sun.shadow_enabled = false
		await _probe_line("no sun shadows")
		sun.shadow_enabled = true
	raid.map.visible = false
	await _probe_line("map hidden")
	for skin in skins:
		skin.visible = false
	await _probe_line("map and bots hidden")
	raid.map.visible = true
	for skin in skins:
		skin.visible = true


func _probe_line(what: String) -> void:
	await _frames(3)
	var draws := 0.0
	var objects := 0.0
	var prims := 0.0
	for i in 5:
		await get_tree().process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("  %-22s %5.0f draw calls, %5.0f objects, %5.0fk primitives" % [what, draws / 5, objects / 5, prims / 5000.0])


func _count_near(raid: Raid, at: Vector3, reach: float) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("actors"):
		var actor := node as Actor
		if actor and Raid.together(actor, raid) and not actor.is_dead \
				and (reach == INF or actor.global_position.distance_to(at) <= reach):
			count += 1
	return count


## Bytes received and sent by the client since the last call.
func _take_stats(net: NetSession) -> Vector2:
	if net == null or not is_instance_valid(net) or net._api == null:
		return Vector2.ZERO
	var peer := net._api.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.host == null:
		return Vector2.ZERO
	return Vector2(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA),
			peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))


func _finish(code: int) -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
	get_tree().quit(code)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


## Processor time a process has used so far (this one with -1), in seconds,
## or -1 where the system does not say (anything but Linux).
func _cpu_seconds(pid: int) -> float:
	var stat := FileAccess.open("/proc/%s/stat" % ("self" if pid < 0 else str(pid)), FileAccess.READ)
	if stat == null:
		return -1.0
	var fields := stat.get_buffer(1024).get_string_from_ascii().get_slice(") ", 1).split(" ")
	if fields.size() < 13:
		return -1.0
	return (float(fields[11]) + float(fields[12])) / 100.0
