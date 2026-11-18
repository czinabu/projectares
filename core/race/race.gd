class_name Race
extends Raid
## A race world's time trials (DESIGN.md section 9). The `Raid` that runs a
## world whose map lays out a `RaceTrack`: nobody loses gear and weapons stay
## locked (`WorldDef.gear_at_risk` and `weapons_free` off), and the machines
## waiting in the pit bays are the class's stock machines, tuned by their
## race profile (`Vehicle.race`), never the rider's own.
##
## Getting on a bay machine starts a run: it is set at a free start slot
## behind the line and held (`Vehicle.held`) while the gantry's lights come
## on one by one, then goes. Each run passes the track's gates in order; the
## line ends a lap, `RaceTrack.laps` laps end the run. A lap that strayed off
## the track (`RaceTrack.is_off_track`) is timed but does not count. Getting
## off, or the machine going, retires the run.
##
## Only the authority judges a run. Clients get their own run's view from
## `NetSession` (`remote_run`) and ask for a restart or retirement through
## `send_request`. The ghost, the gantry, the splits on the arches and the
## board are drawn by `RaceView`, which only reads `view_run` and `board`.
##
## A world may lay out several tracks (Meridian has Coilrun and Skyhook),
## each with its own pit bays, grid, gantry, gates and board. A run is on
## the track whose road the machine was nearest when it was got on
## (`track_near`), so a racer picks a track by walking to its pit row.
##
## Map contract, beyond `WorldDef`'s: a `race_track()` method returning the
## first `RaceTrack` and, with more than one, `race_tracks()` returning them
## all; "spawn_vehicle" markers for the bays, as in any world (the world's
## `roll_loot` names the machine each bay holds).

## The lights over the line come on one every `LIGHT_STEP` seconds; when
## all `LIGHTS` are lit, they go out and the run goes.
const LIGHTS := 5
const LIGHT_STEP := 0.6
## Best laps kept on each track's board.
const BOARD_SIZE := 8
## A racing machine resting this far under the track has fallen off it
## (into the Spillway's channel) and is put back (`_back_on_track`).
const FALLEN_DEPTH := 3.0

## A racer's run changed: started, a gate, a lap, finished or retired.
signal run_changed(actor: Actor)
## A lap was finished. `counted` is false when it strayed off the track.
signal lap_finished(actor: Actor, lap_time: float, counted: bool)
signal board_changed

## The first track, and every track the map lays out (`circuits`; `tracks`
## is the `Raid`'s footprints).
var track: RaceTrack
var circuits: Array[RaceTrack] = []
## Actor -> Run, on the authority.
var runs := {}
## The best laps: [{"name", "machine", "time", "track"}], fastest first,
## at most `BOARD_SIZE` per track (`board_for`).
var board: Array[Dictionary] = []
## Online client: the local player's run, as the server last sent it, and
## the local time it arrived (`Time.get_ticks_msec`).
var remote_run := {}
var remote_at := 0
## Online client: sends a request (`request`'s action) to the server.
var send_request: Callable


class Run:
	extends RefCounted
	var actor: Actor
	var vehicle: Node3D
	var track: RaceTrack
	var machine := ""
	## "grid" (held for the lights), "racing", "done".
	var phase := "grid"
	var go_at := 0.0
	var lap := 1
	## The next gate to pass (0 is the line).
	var next_gate := 1
	var lap_start := 0.0
	var last_pos := Vector3.ZERO
	var hint := -1
	## Still counts: has not strayed off the track this lap.
	var clean := true
	## Race clock time at each gate this lap, and on the best lap.
	var splits: Array[float] = []
	var best_splits: Array[float] = []
	## The last gate passed this lap and its time against the best lap's.
	var last_gate := -1
	var last_delta := NAN
	var last_lap := -1.0
	var best_lap := -1.0
	var total := -1.0
	var slot := 0


# --- Setting up ---------------------------------------------------------------

func _setup(p_world: WorldDef, p_seed: int) -> void:
	super(p_world, p_seed)
	if map != null and map.has_method("race_tracks"):
		circuits.assign(map.call("race_tracks"))
	elif map != null and map.has_method("race_track"):
		circuits.assign([map.call("race_track")])
	if not circuits.is_empty():
		track = circuits[0]


## The track with id `id`, or the first.
func track_by_id(id: String) -> RaceTrack:
	for t in circuits:
		if t.id == id:
			return t
	return track


## The track whose road runs nearest `pos`, height counted.
func track_near(pos: Vector3) -> RaceTrack:
	var best := track
	var best_d := INF
	for t in circuits:
		var i := t.locate(pos)
		if i < 0:
			continue
		var d := t.points[i].distance_to(pos)
		if d < best_d:
			best_d = d
			best = t
	return best


## Every machine here is a stock one: its race profile replaces its tuning.
func spawn_vehicle(id: String, at: Vector3, heading: float, unpacking := false) -> Node3D:
	var vehicle := super(id, at, heading, unpacking)
	vehicle.call("apply_race_profile")
	if mode != Mode.CLIENT:
		vehicle.connect("dismounted", _on_vehicle_dismounted.bind(vehicle))
	return vehicle


func add_player(p_kit: Array = [], p_mastery: Dictionary = {}, p_name := "Raider",
		p_owner := "", p_renown := 0, p_drop := "", _p_insured := "") -> Actor:
	# Nothing of your own rides here: the machines are the track's.
	var kit: Array[String] = []
	for id: String in (p_kit if not p_kit.is_empty() else world.starter_loadout()):
		if id == Loadout.BARE or not (ItemDB.has_tag(id, "vehicle") or ItemDB.has_tag(id, "heal")):
			kit.append(id)
	if kit.is_empty():
		kit.append(Loadout.BARE)
	return super(kit, p_mastery, p_name, p_owner, p_renown, p_drop)


# --- Running ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if world == null or track == null:
		return
	if mode == Mode.CLIENT:
		_hold_remote()
		return
	_keep_racers_safe()
	for actor: Actor in runs.keys():
		_tick_run(runs[actor], delta)


func _on_vehicle_mounted(actor: Actor, vehicle: Node3D) -> void:
	super(actor, vehicle)
	if mode == Mode.CLIENT or track == null or vehicle.get("rider") != actor or state_for(actor) == null:
		return
	start_run(actor, vehicle)


func _on_vehicle_dismounted(actor: Actor, vehicle: Node3D) -> void:
	var run: Run = runs.get(actor)
	if run != null and run.vehicle == vehicle:
		retire(actor)


## Puts `actor`, riding `vehicle`, on a free start slot, held for the lights.
func start_run(actor: Actor, vehicle: Node3D) -> void:
	var run := Run.new()
	run.actor = actor
	run.vehicle = vehicle
	run.machine = str(vehicle.get("item_id"))
	run.track = track_near(vehicle.global_position)
	var old: Run = runs.get(actor)
	if old != null and old.track == run.track and old.machine == run.machine:
		run.best_lap = old.best_lap
		run.best_splits = old.best_splits
	runs[actor] = run
	_to_grid(run)
	actor.notice.emit("Time trial · %s · %d laps" % [run.track.display_name, run.track.laps])


func _to_grid(run: Run) -> void:
	var rt := run.track
	var taken := {}
	for other: Run in runs.values():
		if other != run and other.phase == "grid" and other.track == rt:
			taken[other.slot] = true
	run.slot = 0
	while taken.has(run.slot) and run.slot < rt.start_slots.size() - 1:
		run.slot += 1
	var at: Transform3D = rt.start_slots[run.slot]
	var vehicle := run.vehicle
	vehicle.global_position = at.origin + Vector3(0, 0.4, 0)
	vehicle.set("heading", at.basis.get_euler().y)
	vehicle.rotation = Vector3(0, at.basis.get_euler().y, 0)
	vehicle.set("speed", 0.0)
	vehicle.set("velocity", Vector3.ZERO)
	vehicle.set("held", true)
	run.phase = "grid"
	run.go_at = clock + LIGHTS * LIGHT_STEP
	run.lap = 1
	run.next_gate = 1
	run.clean = true
	run.splits.clear()
	run.last_gate = -1
	run.last_delta = NAN
	run.last_lap = -1.0
	run.total = -1.0
	run.last_pos = vehicle.global_position
	run.hint = rt.locate(run.last_pos)
	run_changed.emit(run.actor)


func _tick_run(run: Run, _delta: float) -> void:
	var rt := run.track
	var vehicle := run.vehicle
	if not is_instance_valid(vehicle) or not is_instance_valid(run.actor) or run.actor.is_dead:
		retire(run.actor)
		return
	var pos: Vector3 = vehicle.global_position
	if run.phase == "grid":
		if clock >= run.go_at:
			run.phase = "racing"
			run.lap_start = run.go_at
			vehicle.set("held", false)
			run_changed.emit(run.actor)
		run.last_pos = pos
		return
	var from := run.last_pos
	run.last_pos = pos
	run.hint = rt.locate(pos, run.hint)
	if run.phase != "racing":
		return
	if run.clean and rt.is_off_track(pos, run.hint):
		run.clean = false
		run.actor.notice.emit("Off the track: this lap will not count")
		run_changed.emit(run.actor)
	var t := rt.cross(run.next_gate, from, pos)
	if t < 0.0:
		return
	# The moment it went through, between the last tick and this one.
	var at := clock - get_physics_process_delta_time() * (1.0 - t)
	if run.next_gate != 0:
		run.splits.append(at - run.lap_start)
		run.last_gate = run.next_gate
		var i := run.splits.size() - 1
		run.last_delta = run.splits[i] - run.best_splits[i] if i < run.best_splits.size() else NAN
		run.next_gate = (run.next_gate + 1) % rt.gates.size()
		run_changed.emit(run.actor)
		return
	_finish_lap(run, at)


func _finish_lap(run: Run, at: float) -> void:
	var lap_time := at - run.lap_start
	run.splits.append(lap_time)
	run.last_lap = lap_time
	run.last_gate = 0
	var i := run.splits.size() - 1
	run.last_delta = run.splits[i] - run.best_splits[i] if i < run.best_splits.size() else NAN
	var counted := run.clean
	if counted and (run.best_lap < 0.0 or lap_time < run.best_lap):
		run.best_lap = lap_time
		run.best_splits = run.splits.duplicate()
		var state := state_for(run.actor)
		add_record(run.actor.display_name, run.machine, lap_time, state.owner if state != null else "", run.track.id)
	lap_finished.emit(run.actor, lap_time, counted)
	run.splits.clear()
	run.clean = true
	run.lap_start = at
	run.next_gate = 1
	if run.lap >= run.track.laps:
		run.phase = "done"
		run.total = at - run.go_at
		run.actor.notice.emit("Finished in %s" % format_time(run.total))
	else:
		run.lap += 1
	run_changed.emit(run.actor)


## Ends `actor`'s run: they keep their machine until they get off it, and
## nothing more is timed.
func retire(actor: Actor) -> void:
	var run: Run = runs.get(actor)
	if run == null:
		return
	runs.erase(actor)
	if is_instance_valid(run.vehicle):
		run.vehicle.set("held", false)
	if is_instance_valid(actor):
		run_changed.emit(actor)


## A racer asks for something: "restart" (back to the grid on the same
## machine) or "retire" (stop the run and get off). Returns {"ok"} or
## {"ok": false, "error"}. Online only the server's own copy decides.
func request(actor: Actor, action: String) -> Dictionary:
	if mode == Mode.CLIENT:
		if send_request.is_valid():
			send_request.call(action)
		return {"ok": true}
	var run: Run = runs.get(actor)
	match action:
		"restart":
			if run == null:
				var vehicle: Node3D = actor.vehicle
				if vehicle == null or vehicle.get("rider") != actor:
					return {"ok": false, "error": "Get on a machine in the pit bays first"}
				start_run(actor, vehicle)
				return {"ok": true}
			_to_grid(run)
			return {"ok": true}
		"retire":
			if run == null:
				return {"ok": false, "error": "No run to stop"}
			var vehicle := run.vehicle
			retire(actor)
			if is_instance_valid(vehicle) and vehicle.get("rider") == actor:
				vehicle.call("dismount")
			return {"ok": true}
	return {"ok": false, "error": "Unknown request"}


## Asks for something as the local player: solo at once, online through
## the server.
func ask(action: String) -> void:
	if player == null or not is_instance_valid(player):
		return
	var result := request(player, action)
	if not result.get("ok", false):
		player.notice.emit(str(result.get("error", "")))


## Keeps a record on a track's board (the first track's when `track_id` is
## empty): the best lap per racer and machine.
func add_record(racer: String, machine: String, time: float, key := "", track_id := "") -> void:
	var who := key if key != "" else racer
	var on := track_id if track_id != "" else (track.id if track != null else "")
	for entry in board:
		if entry.track == on and entry.get("key", entry.name) == who and entry.machine == machine:
			if time >= float(entry.time):
				return
			board.erase(entry)
			break
	board.append({"name": racer, "machine": machine, "time": time, "key": who, "track": on})
	board.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	var kept: Array[Dictionary] = []
	var counts := {}
	for entry in board:
		counts[entry.track] = int(counts.get(entry.track, 0)) + 1
		if counts[entry.track] <= BOARD_SIZE:
			kept.append(entry)
	board = kept
	board_changed.emit()


## One track's best laps, fastest first.
func board_for(track_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in board:
		if entry.track == track_id:
			rows.append(entry)
	return rows


## The board as sent to clients: no keys.
func public_board() -> Array:
	return board.map(func(e: Dictionary) -> Dictionary:
		return {"name": e.name, "machine": e.machine, "time": e.time, "track": e.track})


## Nobody here can be hurt or fall out of the world, and weapons stay
## locked. Riders off a machine walk back to the pits.
func _keep_racers_safe() -> void:
	for state in players:
		var actor := state.actor
		if not is_instance_valid(actor) or actor.is_dead:
			continue
		actor.weapons_locked = true
		actor.health.health = actor.health.max_health
		if actor.global_position.y < -20.0 and actor.vehicle == null:
			var spawns := _map_nodes("spawn_player")
			actor.velocity = Vector3.ZERO
			actor.global_position = spawns[0].global_position if not spawns.is_empty() else Vector3(0, 2, 0)
	for actor: Actor in runs.keys():
		var run: Run = runs[actor]
		if not is_instance_valid(run.vehicle):
			continue
		var pos: Vector3 = run.vehicle.global_position
		if pos.y < -20.0:
			# Fell off the world: back to the grid.
			_to_grid(run)
		elif run.phase == "racing" and run.hint >= 0 and pos.y < run.track.points[run.hint].y - FALLEN_DEPTH \
				and run.vehicle.get("airborne_time") == 0.0:
			# Down in a channel or a pit with no way out: back on the track at
			# the last gate passed, stopped. The clock keeps running.
			_back_on_track(run)


## Puts a run's machine back on the track just past the last gate it
## passed, facing down the track and stopped.
func _back_on_track(run: Run) -> void:
	var rt := run.track
	var g: Dictionary = rt.gates[(run.next_gate - 1 + rt.gates.size()) % rt.gates.size()]
	var at: Vector3 = g.at + g.forward * 3.0 + Vector3(0, 0.5, 0)
	var vehicle := run.vehicle
	var yaw := rt.heading(int(g.index))
	vehicle.global_position = at
	vehicle.set("heading", yaw)
	vehicle.rotation = Vector3(0, yaw, 0)
	vehicle.set("speed", 0.0)
	vehicle.set("slip", 0.0)
	vehicle.set("velocity", Vector3.ZERO)
	run.last_pos = at
	run.hint = int(g.index)
	run.actor.notice.emit("Back on the track at the last checkpoint")
	run_changed.emit(run.actor)


## Online client: the run the server sent holds the local rider's machine
## for the lights, the same as the server does.
func _hold_remote() -> void:
	if player == null or not is_instance_valid(player) or player.vehicle == null:
		return
	var held := str(remote_run.get("phase", "")) == "grid" and run_go_in(remote_run) > 0.0
	player.vehicle.set("held", held)


# --- Views --------------------------------------------------------------------

## A run as plain data, for the watch, the visor and `RaceView`, and to send
## to the racer online. Empty when there is none. Times are from the moment
## it was made: `run_lap_time` and `run_go_in` move them on.
func run_view(actor: Actor) -> Dictionary:
	var run: Run = runs.get(actor)
	if run == null:
		return {}
	return {
		"phase": run.phase,
		"machine": run.machine,
		"track": run.track.id,
		"lap": run.lap,
		"laps": run.track.laps,
		"gates": run.track.gates.size(),
		"next_gate": run.next_gate,
		"clean": run.clean,
		"go_in": maxf(run.go_at - clock, 0.0),
		"lap_elapsed": maxf(clock - run.lap_start, 0.0) if run.phase == "racing" else 0.0,
		"last_gate": run.last_gate,
		"last_delta": run.last_delta,
		"last_lap": run.last_lap,
		"best_lap": run.best_lap,
		"total": run.total,
		"made": Time.get_ticks_msec(),
	}


## The local player's run, here or online.
func view_run() -> Dictionary:
	if mode == Mode.CLIENT:
		return remote_run
	return run_view(player) if player != null and is_instance_valid(player) else {}


## Seconds until the lights go out, from a run view.
static func run_go_in(view: Dictionary) -> float:
	if view.is_empty():
		return 0.0
	var since := (Time.get_ticks_msec() - int(view.get("made", 0))) / 1000.0
	return maxf(float(view.get("go_in", 0.0)) - since, 0.0)


## The time on the lap being run, from a run view.
static func run_lap_time(view: Dictionary) -> float:
	if view.is_empty() or str(view.get("phase", "")) != "racing":
		return 0.0
	var since := (Time.get_ticks_msec() - int(view.get("made", 0))) / 1000.0
	return float(view.get("lap_elapsed", 0.0)) + since


## How many of the lights are lit, from a run view (0 once they are out).
static func lights_lit(view: Dictionary) -> int:
	if str(view.get("phase", "")) != "grid":
		return 0
	var left := run_go_in(view)
	if left <= 0.0:
		return 0
	return clampi(LIGHTS - ceili(left / LIGHT_STEP) + 1, 1, LIGHTS)


## The run in one short line, for the watch and the visor: the lights, the
## lap and its time with the last split, or the finish.
static func run_line(view: Dictionary) -> String:
	if view.is_empty():
		return ""
	match str(view.get("phase", "")):
		"grid":
			return "On the grid · lights %d/%d" % [lights_lit(view), LIGHTS]
		"racing":
			var line := "Lap %d/%d · %s" % [int(view.get("lap", 1)), int(view.get("laps", 1)),
					format_time(run_lap_time(view))]
			var delta := format_delta(float(view.get("last_delta", NAN)))
			if delta != "":
				line += " · " + delta
			if not bool(view.get("clean", true)):
				line += " · off track"
			return line
		"done":
			return "Finished %s · best %s" % [format_time(float(view.get("total", -1.0))),
					format_time(float(view.get("best_lap", -1.0)))]
	return ""


## How far round the run is, from 0 at the line to 1 at the finish.
static func run_progress(view: Dictionary) -> float:
	if view.is_empty():
		return -1.0
	if str(view.get("phase", "")) == "done":
		return 1.0
	var gates := maxi(int(view.get("gates", 1)), 1)
	var passed := (int(view.get("next_gate", 1)) - 1 + gates) % gates
	return clampf((int(view.get("lap", 1)) - 1 + float(passed) / gates) / maxf(float(view.get("laps", 1)), 1.0), 0.0, 1.0)


## A lap time as 1:08.21.
static func format_time(seconds: float) -> String:
	if seconds < 0.0 or is_nan(seconds):
		return "--:--.--"
	var whole := int(seconds)
	return "%d:%02d.%02d" % [whole / 60, whole % 60, int((seconds - whole) * 100.0)]


## A split against the best as -0.42 or +1.10.
static func format_delta(delta: float) -> String:
	if is_nan(delta):
		return ""
	return ("−" if delta < 0.0 else "+") + "%.2f" % absf(delta)


## Online client: the run the server sent for the local player.
func set_remote_run(view: Dictionary) -> void:
	var was := remote_run
	remote_run = view.duplicate()
	if not remote_run.is_empty():
		remote_run["made"] = Time.get_ticks_msec()
	if player != null and is_instance_valid(player):
		run_changed.emit(player)
		var laps_before := int(was.get("lap", 0)) + (1 if str(was.get("phase", "")) == "done" else 0)
		var laps_now := int(view.get("lap", 0)) + (1 if str(view.get("phase", "")) == "done" else 0)
		if not was.is_empty() and laps_now > laps_before and float(view.get("last_lap", -1.0)) > 0.0:
			lap_finished.emit(player, float(view.last_lap), float(view.last_lap) == float(view.get("best_lap", -2.0)))


## Online client: the board the server sent.
func set_remote_board(rows: Array) -> void:
	board.clear()
	for row: Variant in rows:
		if row is Dictionary and row.has("time"):
			board.append({"name": str(row.get("name", "?")), "machine": str(row.get("machine", "")),
					"time": float(row.time), "key": str(row.get("name", "?")),
					"track": str(row.get("track", track.id if track != null else ""))})
	board_changed.emit()
