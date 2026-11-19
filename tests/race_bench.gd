extends Node
## The time-trial bench (DESIGN.md section 9, "Balance"): a driver bot runs
## three laps of every race track on each machine of the track's class, on
## its race profile, and prints each lap. A machine whose best lap is more
## than `TOLERANCE` off its class's average is flagged, and the bench exits
## 1 so a change that breaks the class shows up. Tune the race profiles
## (`ItemDB.RACE_*`) until every machine is inside it.
##
##   godot --headless --fixed-fps 60 --path . res://tests/race_bench.tscn
##
## The driver aims at the racing line a little ahead and holds the boost,
## braking where the corner ahead is tighter than the machine can turn at
## its speed (its radius is speed over `turn_rate`), so it drives every
## machine to its own limits the same way.
##
## With `-- --drift` the driver also uses the handbrake: it throws the
## machine into a drift where the bend it is in is tighter than it can turn
## at its speed, and lets go on the throttle for the exit boost. Comparing
## the two runs shows what drifting is worth on each track.
##
## With `-- --tunes` each machine is also driven with every tuning kit
## (`RaceLeague.KITS`) fitted, and a kit that takes it more than
## `TOLERANCE` off the class's stock average is flagged.
##
## `-- --kit <id>` benches only that kit, and `-- --sweep` instead prints
## how far one stat at a time moves each machine's lap (`SWEEP`), the
## numbers a kit is balanced from.
##
## With `-- --ai` each machine is also driven by the AI racers' driver
## (`RaceDriver`) at a rookie's, a middling and the best skill, and the
## bench is flagged if any AI laps faster than the bench's own driver, which
## drives at the limit: an AI racer must never beat a perfect run by more
## than a lap's own noise (`AI_NOISE`).

const WORLDS: Array[String] = ["meridian"]
const CLASSES := {"street": ["bike_scrapper", "bike_raider"]}
const TOLERANCE := 0.03
## Seconds of driving allowed for a whole run before it is called stuck.
const RUN_LIMIT := 420.0

const RaceLeague := preload("res://core/race/race_league.gd")

var _failed := false
static var _tunes := false
static var _only_kit := ""
## The sweep's steps: one stat at a time, by these.
const SWEEP := {"max_speed": 1.01, "accel": 1.1, "turn_rate": 1.05, "full_turn_speed": 1.15, "brake_decel": 1.2,
		"coast_decel": 1.3}
static var _drift := false
static var _ai := false
const AI_SKILLS: Array[float] = [0.0, 0.5, 1.0]
## The share of a lap two runs at the limit can differ by.
const AI_NOISE := 0.005


func _ready() -> void:
	# Lap times on empty tracks: no AI races of their own.
	Race.ambient_races = false
	_drift = OS.get_cmdline_user_args().has("--drift")
	_ai = OS.get_cmdline_user_args().has("--ai")
	_tunes = OS.get_cmdline_user_args().has("--tunes")
	var args := OS.get_cmdline_user_args()
	if args.has("--kit") and args.find("--kit") + 1 < args.size():
		_only_kit = args[args.find("--kit") + 1]
		_tunes = true
	if args.has("--sweep"):
		await _sweep()
		get_tree().quit(0)
		return
	for world_id in WORLDS:
		var world := Worlds.get_world(world_id)
		for track_index in _track_count(world):
			for race_class: String in CLASSES:
				await _bench_class(world, track_index, race_class)
	print("Race bench: %s" % ("a machine is out of its class" if _failed else "every machine is in its class"))
	get_tree().quit(1 if _failed else 0)


## How many tracks `world`'s map lays out.
static func _track_count(world: WorldDef) -> int:
	var map: Node3D = world.create_map()
	var count := 1
	if map.has_method("race_tracks"):
		count = (map.call("race_tracks") as Array).size()
	map.free()
	return count


## How far each stat in `SWEEP` moves each machine's best lap, on every
## track (max_speed moves boost_speed with it).
func _sweep() -> void:
	var world := Worlds.get_world("meridian")
	for track_index in _track_count(world):
		for machine: String in CLASSES.street:
			var base := await drive(self, world, machine, track_index)
			var line := "%-10s %-14s %s " % [base.track, machine, Race.format_time(base.best)]
			for stat: String in SWEEP:
				var mult := {stat: SWEEP[stat]}
				if stat == "max_speed":
					mult["boost_speed"] = SWEEP[stat]
				var run := await drive(self, world, machine, track_index, null, "stock", mult)
				line += " %s×%.2f %+.2f%%" % [stat, SWEEP[stat], (float(run.best) - base.best) / base.best * 100.0] \
						if run.finished else " %s DNF" % stat
			print(line)


## Every machine of `race_class` round track `track_index`, against the
## class average.
func _bench_class(world: WorldDef, track_index: int, race_class: String) -> void:
	var bests := {}
	var where := world.id
	for machine: String in CLASSES[race_class]:
		var result := await drive(self, world, machine, track_index)
		bests[machine] = result.best
		where = str(result.get("track", where))
		print("%-10s %-14s laps %s  best %s%s" % [where, machine,
				", ".join(result.laps.map(func(l: Array) -> String:
					return Race.format_time(l[0]) + ("" if l[1] else " (off)"))),
				Race.format_time(result.best), "" if result.finished else "  DID NOT FINISH"])
		if _drift:
			print("  drifting %.1f s of the run" % (int(result.get("drift_ticks", 0)) / float(Engine.physics_ticks_per_second)))
		if not result.finished:
			_failed = true
		if _ai:
			for skill in AI_SKILLS:
				var driven := await drive(self, world, machine, track_index, RaceDriver.make(skill, 7))
				var faster: bool = driven.best > 0.0 and result.best > 0.0 and driven.best < float(result.best) * (1.0 - AI_NOISE)
				print("  AI skill %.1f    laps %s  best %s%s" % [skill,
						", ".join(driven.laps.map(func(l: Array) -> String:
							return Race.format_time(l[0]) + ("" if l[1] else " (off)"))),
						Race.format_time(driven.best),
						"  FASTER THAN THE LIMIT" if faster else ("" if driven.finished else "  DID NOT FINISH")])
				_failed = _failed or faster or not driven.finished
	var times: Array = bests.values().filter(func(b: float) -> bool: return b > 0.0)
	if times.is_empty():
		return
	var average: float = times.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / times.size()
	print("%-10s %s class average %s" % [where, race_class, Race.format_time(average)])
	for machine: String in bests:
		var off: float = (float(bests[machine]) - average) / average
		var flag := absf(off) > TOLERANCE
		_failed = _failed or flag
		print("  %-14s %+.2f%%%s" % [machine, off * 100.0, "   OUT OF CLASS" if flag else ""])
	if not _tunes:
		return
	for machine: String in CLASSES[race_class]:
		for kit: String in RaceLeague.KIT_ORDER:
			if kit == "stock" or (_only_kit != "" and kit != _only_kit):
				continue
			var tuned := await drive(self, world, machine, track_index, null, kit)
			var off: float = (float(tuned.best) - average) / average if tuned.best > 0.0 else 1.0
			var flag: bool = absf(off) > TOLERANCE or not tuned.finished
			_failed = _failed or flag
			print("  %-14s %-14s best %s  %+.2f%%%s" % [machine, kit, Race.format_time(tuned.best), off * 100.0,
					"   OUT OF CLASS" if flag else ""])


## Drives `machine` round `world`'s track `track_index` for a full run, from
## a bay of that track. Returns {"laps": [[time, counted]], "best": seconds
## or -1, "finished": bool, "track": its id}.
static func drive(host: Node, world: WorldDef, machine: String, track_index := 0,
		driver: RaceDriver = null, kit := "stock", mult := {}) -> Dictionary:
	var race: Race = world.new_raid()
	host.add_child(race)
	race.start(world, 1, [Loadout.BARE] as Array[String])
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var me := race.player
	var track := race.circuits[track_index]
	var bike: Node3D = null
	for v: Node3D in race.vehicles:
		if v.get("item_id") == machine and v.get("rider") == null and race.track_near(v.global_position) == track:
			bike = v
			break
	var out := {"laps": [], "best": -1.0, "finished": false, "track": track.id}
	if bike == null:
		race.queue_free()
		return out
	me.global_position = bike.global_position + Vector3(2.0, 0.2, 0.0)
	await host.get_tree().physics_frame
	bike.call("mount", me)
	if kit != "stock":
		var profile := RaceLeague.tuned(bike.get("race"), kit)
		for stat: String in profile:
			bike.set(stat, profile[stat])
	for stat: String in mult:
		bike.set(stat, float(bike.get(stat)) * float(mult[stat]))
	race.lap_finished.connect(func(_a: Actor, time: float, counted: bool) -> void:
		out.laps.append([time, counted]))
	var ticks := int(RUN_LIMIT * Engine.physics_ticks_per_second)
	var hint := -1
	var stuck := 0
	for k in ticks:
		var view := race.run_view(me)
		if view.is_empty() or view.phase == "done":
			break
		hint = track.locate(bike.global_position, hint)
		var drive := steer_for(bike, track, hint)
		if driver != null:
			driver.drive(me, bike, track, view.phase == "racing", [], 1.0 / Engine.physics_ticks_per_second)
		else:
			me.cmd.move = Vector2(drive.x, drive.y)
			me.cmd.sprint = true
			me.cmd.jump = _drift and drift_for(bike, track, hint)
		if bool(bike.get("drifting")):
			out["drift_ticks"] = int(out.get("drift_ticks", 0)) + 1
		if view.phase == "racing" and absf(float(bike.get("speed"))) < 1.0:
			stuck += 1
			if stuck > 5 * Engine.physics_ticks_per_second:
				print("  %s is stuck at %s" % [machine, bike.global_position.snapped(Vector3.ONE * 0.1)])
				break
		else:
			stuck = 0
		if OS.has_environment("RACE_BENCH_TRACE") and k % 120 == 0:
			print("  t %.0f %s gate %s speed %.1f at %s hint %d drive %s" % [k / 60.0, view.phase, view.next_gate,
					float(bike.get("speed")), bike.global_position.snapped(Vector3.ONE * 0.1), hint, drive])
		await host.get_tree().physics_frame
	var view := race.run_view(me)
	out.finished = not view.is_empty() and view.phase == "done"
	out.best = float(view.get("best_lap", -1.0)) if not view.is_empty() else -1.0
	race.queue_free()
	await host.get_tree().physics_frame
	return out


## The driver: the AI racers' own at full skill (`RaceDriver.steer`), so
## the bench's lap is the fastest clean lap an AI can drive.
static func steer_for(bike: Node3D, track: RaceTrack, hint: int) -> Vector2:
	return RaceDriver.steer(bike, track, hint, RaceDriver.PACE_BEST, 0.0, _drift)


## The drifting driver's handbrake (`RaceDriver.drift_for`).
static func drift_for(bike: Node3D, track: RaceTrack, hint: int) -> bool:
	return RaceDriver.drift_for(bike, track, hint)
