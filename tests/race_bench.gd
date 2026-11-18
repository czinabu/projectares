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

const WORLDS: Array[String] = ["meridian"]
const CLASSES := {"street": ["bike_scrapper", "bike_raider"]}
const TOLERANCE := 0.03
## Seconds of driving allowed for a whole run before it is called stuck.
const RUN_LIMIT := 420.0

var _failed := false


func _ready() -> void:
	for world_id in WORLDS:
		var world := Worlds.get_world(world_id)
		for race_class: String in CLASSES:
			var bests := {}
			for machine: String in CLASSES[race_class]:
				var result := await drive(self, world, machine)
				bests[machine] = result.best
				print("%-10s %-14s laps %s  best %s%s" % [world_id, machine,
						", ".join(result.laps.map(func(l: Array) -> String:
							return Race.format_time(l[0]) + ("" if l[1] else " (off)"))),
						Race.format_time(result.best), "" if result.finished else "  DID NOT FINISH"])
				if not result.finished:
					_failed = true
			var times: Array = bests.values().filter(func(b: float) -> bool: return b > 0.0)
			if times.is_empty():
				continue
			var average: float = times.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / times.size()
			print("%-10s %s class average %s" % [world_id, race_class, Race.format_time(average)])
			for machine: String in bests:
				var off: float = (float(bests[machine]) - average) / average
				var flag := absf(off) > TOLERANCE
				_failed = _failed or flag
				print("  %-14s %+.2f%%%s" % [machine, off * 100.0, "   OUT OF CLASS" if flag else ""])
	print("Race bench: %s" % ("a machine is out of its class" if _failed else "every machine is in its class"))
	get_tree().quit(1 if _failed else 0)


## Drives `machine` round `world`'s track for a full run. Returns
## {"laps": [[time, counted]], "best": seconds or -1, "finished": bool}.
static func drive(host: Node, world: WorldDef, machine: String) -> Dictionary:
	var race: Race = world.new_raid()
	host.add_child(race)
	race.start(world, 1, [Loadout.BARE] as Array[String])
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var me := race.player
	var bike: Node3D = null
	for v: Node3D in race.vehicles:
		if v.get("item_id") == machine and v.get("rider") == null:
			bike = v
			break
	var out := {"laps": [], "best": -1.0, "finished": false}
	if bike == null:
		race.queue_free()
		return out
	me.global_position = bike.global_position + Vector3(2.0, 0.2, 0.0)
	await host.get_tree().physics_frame
	bike.call("mount", me)
	race.lap_finished.connect(func(_a: Actor, time: float, counted: bool) -> void:
		out.laps.append([time, counted]))
	var track := race.track
	var ticks := int(RUN_LIMIT * Engine.physics_ticks_per_second)
	var hint := -1
	var stuck := 0
	for k in ticks:
		var view := race.run_view(me)
		if view.is_empty() or view.phase == "done":
			break
		hint = track.locate(bike.global_position, hint)
		var drive := steer_for(bike, track, hint)
		me.cmd.move = Vector2(drive.x, drive.y)
		me.cmd.sprint = true
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


## The driver: x is the steer (+1 right), y the throttle (-1 brakes).
static func steer_for(bike: Node3D, track: RaceTrack, hint: int) -> Vector2:
	var n := track.points.size()
	var speed := absf(float(bike.get("speed")))
	var rate := float(bike.get("turn_rate"))
	var brake := float(bike.get("brake_decel"))
	var at: Vector3 = bike.global_position
	# Aim a little ahead on the line, further at speed.
	var ahead := 3 + int(speed * 0.35 / RaceTrack.STEP)
	var ti := (hint + ahead) % n
	var target := track.points[ti] + track.side(ti) * track.line_offset(ti, bool(bike.get("hovers")))
	var heading := float(bike.get("heading")) + float(bike.get("slip"))
	var facing := Basis(Vector3.UP, heading) * Vector3.FORWARD
	var want := Vector3(target.x - at.x, 0.0, target.z - at.z).normalized()
	var angle := facing.signed_angle_to(want, Vector3.UP)
	var steer := clampf(-angle * 3.0, -1.0, 1.0)
	# Brake for a corner ahead tighter than this speed allows.
	var throttle := 1.0
	var reach := int((speed * speed / (2.0 * maxf(brake, 1.0)) + 20.0) / RaceTrack.STEP)
	for j in range(2, reach, 2):
		var i := (hint + j) % n
		var radius := _radius(track, i)
		var allowed := radius * rate * 0.9
		var dist := j * RaceTrack.STEP
		if speed * speed - allowed * allowed > 2.0 * brake * dist:
			throttle = -1.0
			break
	return Vector2(steer, throttle)


## The track's turning radius about point `i`, from the bend over 10 m.
static func _radius(track: RaceTrack, i: int) -> float:
	var n := track.points.size()
	var a := track.forward((i - 3 + n) % n)
	var b := track.forward((i + 3) % n)
	var bend := absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
	return 6.0 * RaceTrack.STEP / maxf(bend, 0.001)
