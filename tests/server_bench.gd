extends Node
## Measures the whole server under load (DESIGN.md section 14): starts a real
## server process with the plaza, every raid world and the arena, fills each
## with players (idle clients that wander), and prints
##   - the server's own health lines (tick time and players per session), and
##   - how long travel between worlds takes with all of it running, against
##     `TRAVEL_TARGET`: the whole trip (connect, sign in, deploy), and the
##     arrival alone, which is all a player waits for when the game connected
##     ahead while the gate opened (DESIGN.md "Travel that hides its wait").
##
##   godot --headless --path . res://tests/server_bench.tscn -- --plaza 6 --per-world 6 --arena 2 --seconds 60
##
## `--cluster` runs every world as a program of its own (`-- --server
## --cluster`, DESIGN.md section 14 "Scaling") instead of all in one, to
## compare the two: each program then has the tick budget to itself.
##
## `--strict` exits 1 when the tick average is over budget or a trip is over
## the target. `--bots <n>` sets the bots per world; the default is each
## world's own. Players are real `NetSession` clients in this process, so the
## server is the only thing whose time is reported as the server's.

const PORT := 25830
const SERVICE_PORT := 25890
## DESIGN.md section 14: travel between worlds within about 3 s.
const TRAVEL_TARGET := 3.0
const _stash := preload("res://core/account/stash_service.gd")
const HEALTH_EVERY := 5

var _log_path := ""
var _server_pid := -1
var _clients: Array[NetSession] = []
var _secrets := {}
var _count := 0
var _routes := {}
var _cluster := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var in_plaza := int(_arg(args, "--plaza", "6"))
	var per_world := int(_arg(args, "--per-world", "6"))  # capped at a world's max_players, less one for the trips
	var in_arena := int(_arg(args, "--arena", "2"))
	var seconds := float(_arg(args, "--seconds", "45"))
	var trips := int(_arg(args, "--trips", "6"))
	var bots := _arg(args, "--bots", "-1")
	var strict := "--strict" in args
	_cluster = "--cluster" in args
	Profile.persist = false
	# Measured with the worlds' enemies unless `--no-enemies` (`Raid.enemies`),
	# here and in any server this starts.
	Raid.enemies = "--no-enemies" not in args
	OS.set_environment("ARES_ENEMIES", "1" if Raid.enemies else "0")
	if not await _start_server(bots):
		print("Server bench: the server did not start")
		_finish(1)
		return
	# Plaza: the first join also tells us where each world is.
	var plaza: Array[NetSession] = []
	for i in in_plaza:
		var s := await _enter(PORT)
		if s != null:
			plaza.append(s)
	if plaza.is_empty():
		print("Server bench: nobody could sign in at the plaza")
		_finish(1)
		return
	var worlds: Array[String] = []
	for world in Worlds.raid_worlds():
		worlds.append(world.id)
	# A cluster's worlds come onto the plaza's routes as each one starts.
	for i in 240:
		if worlds.all(func(id: String) -> bool: return plaza[0].routes.has(id)) \
				and plaza[0].routes.has(Arena.ArenaVenue.ID):
			break
		await get_tree().create_timer(0.25).timeout
	_routes = plaza[0].routes.duplicate()
	print("Server bench: plaza %d, routes %s%s" % [plaza.size(), _routes,
			", every world its own program" if _cluster else ""])
	var in_world := {}
	for id in worlds:
		in_world[id] = []
		# A world takes only `max_players`; more would never get in.
		for i in mini(per_world, Worlds.get_world(id).max_players - 1):
			var s := await _enter(int(_routes.get(id, 0)))
			if s != null:
				in_world[id].append(s)
	var arena_port := int(_routes.get(Arena.ArenaVenue.ID, 0))
	var arena: Array[NetSession] = []
	for i in in_arena:
		var s := await _enter(arena_port)
		if s != null:
			arena.append(s)
			s.raid.call("ask", "practice")
	print("Server bench: %d in the plaza, %s in the worlds, %d in the arena" % [plaza.size(),
			", ".join(worlds.map(func(id: String) -> String: return "%d in %s" % [in_world[id].size(), id])),
			arena.size()])
	# Everyone in a world or the arena walks about; the plaza stands around.
	var walking: Array[NetSession] = arena.duplicate()
	for id in worlds:
		walking.append_array(in_world[id])
	var travel: Array[float] = []
	var arrivals: Array[float] = []
	var began := Time.get_ticks_msec()
	var next_trip := 5.0
	var trip := 0
	while (Time.get_ticks_msec() - began) / 1000.0 < seconds:
		for s in walking:
			_wander(s)
		var elapsed := (Time.get_ticks_msec() - began) / 1000.0
		if trip < trips and elapsed >= next_trip and not worlds.is_empty():
			var id := worlds[trip % worlds.size()]
			var took := await _travel(int(_routes.get(id, 0)))
			travel.append(took)
			var arrival := await _travel(int(_routes.get(id, 0)), true)
			arrivals.append(arrival)
			print("  trip %d to %s: %.2f s whole, %.2f s to arrive when connected ahead" % [trip + 1, id, took, arrival])
			trip += 1
			next_trip = elapsed + 3.0
		await get_tree().create_timer(0.5).timeout
	# One more look at the server before it goes.
	await get_tree().create_timer(HEALTH_EVERY + 1.0).timeout
	var ticks := _report_health()
	var slowest := 0.0
	var total := 0.0
	for took in travel:
		slowest = maxf(slowest, took)
		total += took
	var fine := true
	if not ticks.is_empty():
		var budget := ServerHealth.budget_ms()
		var avg := 0.0
		var worst := 0.0
		for t: Vector2 in ticks:
			avg += t.x / ticks.size()
			worst = maxf(worst, t.y)
		print("Server tick%s: %.2f ms average, %.1f ms worst, %.0f%% of the %.1f ms budget" % [
				" (each program)" if _cluster else "", avg, worst, avg / budget * 100.0, budget])
		fine = avg <= budget
	if not travel.is_empty():
		print("Travel between worlds: %.2f s average, %.2f s slowest, target %.1f s" % [
				total / travel.size(), slowest, TRAVEL_TARGET])
		fine = fine and slowest <= TRAVEL_TARGET
	if not arrivals.is_empty():
		var arrive_total := 0.0
		var arrive_slowest := 0.0
		for took in arrivals:
			arrive_total += took
			arrive_slowest = maxf(arrive_slowest, took)
		print("Arrival when connected ahead: %.2f s average, %.2f s slowest" % [
				arrive_total / arrivals.size(), arrive_slowest])
	print("Server bench: %s" % ("within budget" if fine else "OVER BUDGET"))
	_finish(0 if fine or not strict else 1)


## Starts the server process (plaza, every world and the arena) and reads its
## output on a thread, since a pipe read waits.
func _start_server(bots: String) -> bool:
	var accounts := OS.get_user_data_dir().path_join("server_bench_accounts")
	_wipe(accounts)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server", "--port", str(PORT), "--accounts", accounts,
			"--health-log", str(HEALTH_EVERY), "--no-zone-rules"])
	if bots != "-1":
		args.append_array(["--bots", bots])
	if _cluster:
		args.append_array(["--cluster", "--account-port", str(SERVICE_PORT)])
	# Its output goes to a file this reads back, so no pipe can fill and stall it.
	_log_path = OS.get_user_data_dir().path_join("server_bench.log")
	var shell := "exec \"%s\" %s > \"%s\" 2>&1" % [OS.get_executable_path(),
			" ".join(Array(args).map(func(a: String) -> String: return "'%s'" % a)), _log_path]
	_server_pid = OS.create_process("/bin/sh", PackedStringArray(["-c", shell]))
	if _server_pid <= 0:
		return false
	# The server is up once it says it runs the plaza (the last session).
	for i in 240:
		await get_tree().create_timer(0.25).timeout
		if _heard("running plaza"):
			return true
	return false


func _heard(text: String) -> bool:
	return text in FileAccess.get_file_as_string(_log_path)


## Prints the server's health lines; returns each one's (average, worst) tick ms.
func _report_health() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var lines := FileAccess.get_file_as_string(_log_path).split("\n")
	var re := RegEx.create_from_string("tick ([0-9.]+) ms of [0-9.]+ \\(worst ([0-9.]+)\\)")
	for line in lines:
		if line.begins_with("Health:"):
			print("  " + line)
			var m := re.search(line)
			if m != null:
				out.append(Vector2(float(m.get_string(1)), float(m.get_string(2))))
	# The first lines are the quiet start-up; they would flatter the average.
	if out.size() > 2:
		out = out.slice(2)
	return out


func _new_client() -> NetSession:
	_count += 1
	var shown := "Bench%d" % _count
	var view := SubViewport.new()
	view.own_world_3d = true
	add_child(view)
	var session := NetSession.new()
	session.name = "Net"
	session.player_name = shown
	session.secret = _stash.new_secret()
	view.add_child(session)
	return session


## Connects and signs in, or null. `session` stays in `_clients`.
func _sign_in(port: int) -> NetSession:
	for attempt in 20:
		var session := _new_client()
		var state := {"failed": false}
		session.failed.connect(func(_reason: String) -> void: state.failed = true)
		session.join("127.0.0.1", port)
		var waited := 0.0
		while not state.failed and session.account.is_empty() and waited < 8.0:
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
		if not session.account.is_empty():
			_clients.append(session)
			return session
		session.get_parent().queue_free()
		await get_tree().create_timer(0.5).timeout
	return null


## Signs in and deploys into the world at `port`; null if it never lands.
func _enter(port: int) -> NetSession:
	var session := await _sign_in(port)
	if session == null:
		return null
	session.deploy()
	var waited := 0.0
	while (session.raid == null or session.raid.player == null) and waited < 20.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if session.raid != null and session.raid.player != null:
		return session
	_drop(session)
	return null


## One trip as the game makes it: connect to the world, sign in, deploy, and
## stand in it. Seconds, or the wait given up on. With `ahead` the clock
## starts once the game is signed in, as when it connected while the gate
## opened: only the deploy is waited for.
func _travel(port: int, ahead := false) -> float:
	var began := Time.get_ticks_msec()
	var session := _new_client()
	session.ahead = ahead
	session.join("127.0.0.1", port)
	var waited := 0.0
	while session.account.is_empty() and waited < 20.0:
		await get_tree().create_timer(0.02).timeout
		waited += 0.02
	if ahead:
		began = Time.get_ticks_msec()
	session.deploy()
	while (session.raid == null or session.raid.player == null) and waited < 20.0:
		await get_tree().create_timer(0.02).timeout
		waited += 0.02
	var took := (Time.get_ticks_msec() - began) / 1000.0
	_drop(session)
	return took


func _drop(session: NetSession) -> void:
	_clients.erase(session)
	if is_instance_valid(session):
		session.get_parent().queue_free()


var _wander_at := {}

## Players do something: walk a heading for a few seconds, then another.
func _wander(session: NetSession) -> void:
	if not is_instance_valid(session) or session.raid == null or session.raid.player == null:
		return
	var key := session.get_instance_id()
	var now := Time.get_ticks_msec()
	if now >= int(_wander_at.get(key, 0)):
		_wander_at[key] = now + randi_range(2000, 5000)
		var angle := randf() * TAU
		session.raid.player.cmd.move = Vector2(sin(angle), -cos(angle))
		session.raid.player.cmd.yaw = angle


func _wipe(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for sub in DirAccess.get_directories_at(dir):
			_wipe(dir.path_join(sub))
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _finish(code: int) -> void:
	for s in _clients:
		if is_instance_valid(s):
			s.close()
	if _server_pid > 0:
		OS.kill(_server_pid)
	if _cluster and OS.get_name() == "Linux":
		# A cluster's worlds stop by themselves a little later; do not wait.
		OS.execute("pkill", PackedStringArray(["-f", "--", "--account-url ws://127.0.0.1:%d" % SERVICE_PORT]))
	get_tree().quit(code)


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback
