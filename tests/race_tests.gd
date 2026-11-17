extends RefCounted
## Checks for the race world (DESIGN.md section 9): Meridian's Coilrun
## track, the time trial's grid, lights, gates, laps and off-track rule, the
## board, the stock race profiles, and that racing never risks or grants
## gear. Run from the main test runner. Nothing here starts a server.


static func run(t: Node) -> void:
	print("Race world: Meridian time trials")
	_test_world(t)
	_test_track(t)
	_test_formatting(t)
	await _test_time_trial(t)
	_test_ghost_data(t)


static func _test_world(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	t.check(world != null, "the race world is registered")
	if world == null:
		return
	t.check(not world.gear_at_risk and not world.weapons_free and not world.safe_zone,
			"the race world risks no gear and keeps weapons locked")
	t.check(world.bot_count == 0 and world.war_scale == 0.0 and world.power_weapon_rate == 0.0,
			"no bots, no war and no heavy weapons on the track")
	var raid := world.new_raid()
	t.check(raid is Race, "the race world is run by a Race")
	raid.free()
	var a := Node.new()
	var b := Node.new()
	t.check(not world.can_damage(a, b, null) and Worlds.get_world("ashfront").can_damage(a, b, null),
			"nobody can hurt anybody on the track, the warzone is unchanged")
	a.free()
	b.free()
	for id: String in ["bike_scrapper", "bike_raider"]:
		var race: Dictionary = ItemDB.item_stats(id).get("race", {})
		t.check(not race.is_empty() and race.has("max_speed"), "%s has a race profile" % id)


static func _test_track(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	var map: Node3D = world.create_map()
	t.add_child(map)
	var track: RaceTrack = map.call("race_track")
	t.check(track != null and track.laps == 3, "Coilrun is a three lap track")
	t.check(track.length() > 1400.0 and track.length() < 1900.0,
			"Coilrun runs about 1.6 km a lap (%.0f m)" % track.length())
	t.check(track.gates.size() == 5, "the line and four checkpoints")
	t.check(track.start_slots.size() >= 4, "at least four start slots")
	# Start slots sit behind the line, facing along the track.
	var line: Dictionary = track.gates[0]
	var behind := true
	for slot: Transform3D in track.start_slots:
		behind = behind and (slot.origin - line.at).dot(line.forward) < 0.0 \
				and (-slot.basis.z).dot(line.forward) > 0.9
	t.check(behind, "every start slot is behind the line, facing down the track")
	# Gates are crossed one way only, and only within the track's width.
	var g: Dictionary = track.gates[1]
	var f: Vector3 = g.forward
	var s: Vector3 = f.cross(Vector3.UP).normalized()
	t.check(track.cross(1, g.at - f * 2.0, g.at + f * 2.0) > 0.0, "driving through a gate passes it")
	t.check(track.cross(1, g.at + f * 2.0, g.at - f * 2.0) < 0.0, "driving back through it does not")
	t.check(track.cross(1, g.at - f * 2.0 + s * 40.0, g.at + f * 2.0 + s * 40.0) < 0.0,
			"going past its end does not")
	# Off the track is well off it: the kerb and a bit of run-off still count.
	var i := track.locate(g.at)
	t.check(not track.is_off_track(g.at + s * (track.width * 0.5 + 2.0), i)
			and track.is_off_track(g.at + s * (track.width * 0.5 + RaceTrack.OFF_TRACK + 5.0), i),
			"cutting far off the track is off it, running wide onto the kerb is not")
	t.check(map.find_children("*", "", true, false).any(
			func(n: Node) -> bool: return n.is_in_group("spawn_vehicle")), "the pits have bays")
	map.queue_free()


static func _test_formatting(t: Node) -> void:
	t.check(Race.format_time(68.214) == "1:08.21" and Race.format_time(-1.0) == "--:--.--",
			"lap times read as minutes, seconds and hundredths")
	t.check(Race.format_delta(-0.42).ends_with("0.42") and Race.format_delta(-0.42).begins_with("−")
			and Race.format_delta(1.1) == "+1.10" and Race.format_delta(NAN) == "",
			"splits read as ahead or behind")
	var view := {"phase": "grid", "go_in": Race.LIGHTS * Race.LIGHT_STEP - 0.01, "made": Time.get_ticks_msec()}
	t.check(Race.lights_lit(view) == 1, "the first light is on as the grid starts")
	view.go_in = 0.1
	t.check(Race.lights_lit(view) == Race.LIGHTS, "all the lights are on just before the go")
	view.go_in = 0.0
	t.check(Race.lights_lit(view) == 0, "and out at the go")


## Moves the machine along the track's points from `from` by `count` points,
## a few a tick, shifted `aside` meters to the side between `off_from` and
## `off_to`.
static func _drive(t: Node, race: Race, vehicle: Node3D, from: int, count: int, aside := 0.0,
		off_from := -1, off_to := -1) -> int:
	var track := race.track
	var n := track.points.size()
	var i := from
	for k in count:
		i = (from + k) % n
		var at := track.points[i]
		if k >= off_from and k < off_to:
			at += track.side(i) * aside
		vehicle.global_position = at + Vector3(0, 0.6, 0)
		vehicle.set("velocity", Vector3.ZERO)
		vehicle.set("speed", 0.0)
		if k % 4 == 3:
			await t.frames(1)
	await t.frames(2)
	return (from + count) % n


static func _test_time_trial(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	var race: Race = world.new_raid()
	t.add_child(race)
	race.start(world, 5, ["rifle_ar", "bike_raider", "medkit"] as Array[String])
	await t.frames(5)
	var me := race.player
	t.check(me != null and me.weapons_locked, "a racer has weapons locked")
	var is_vehicle := func(id: String) -> bool: return ItemDB.has_tag(id, "vehicle")
	t.check(not me.inventory.items.any(is_vehicle) and not me.gear_items.any(is_vehicle),
			"a racer brings no vehicle of their own")
	t.check(race.stowed_for(me).is_empty(), "nor one on the watch")
	t.check(Portal.choices_for(race, me) == ([Portal.HOME] as Array[String]), "the portal home is on offer")
	var bays: Array = race.vehicles.filter(func(v: Node3D) -> bool: return v.get("rider") == null)
	var scrappers := bays.filter(func(v: Node3D) -> bool: return v.get("item_id") == "bike_scrapper")
	var raiders := bays.filter(func(v: Node3D) -> bool: return v.get("item_id") == "bike_raider")
	t.check(scrappers.size() == 4 and raiders.size() == 4, "the pit bays hold four of each Street machine")
	if scrappers.is_empty():
		race.queue_free()
		return
	var bike: Node3D = scrappers[0]
	t.check(is_equal_approx(float(bike.get("max_speed")), float(ItemDB.RACE_SCRAPPER.max_speed)),
			"a bay machine runs on its race profile")
	me.global_position = bike.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	bike.call("mount", me)
	await t.frames(2)
	var view := race.view_run()
	t.check(view.get("phase") == "grid" and bool(bike.get("held")), "getting on starts a run, held on the grid")
	var line: Dictionary = race.track.gates[0]
	t.check(bike.global_position.distance_to(line.at) < 30.0, "the machine is moved to a start slot")
	me.cmd.move = Vector2(0, 1)
	await t.frames(30)
	t.check(race.view_run().get("phase") == "grid" and bike.global_position.distance_to(line.at) < 30.0
			and float(bike.get("speed")) < 0.5, "the throttle does nothing while the lights are on")
	await t.frames(int(Race.LIGHTS * Race.LIGHT_STEP * Engine.physics_ticks_per_second) + 5)
	t.check(race.view_run().get("phase") == "racing" and not bool(bike.get("held")), "at the go it races")
	me.cmd.move = Vector2.ZERO
	# Skipping the checkpoints counts for nothing.
	var track := race.track
	var start_i := track.locate(bike.global_position)
	var line_i := track.locate(line.at)
	var back := (line_i - 6 + track.points.size()) % track.points.size()
	await _drive(t, race, bike, back, 12)
	t.check(int(race.view_run().get("lap", 0)) == 1 and race.view_run().get("last_lap") == -1.0,
			"crossing the line without the checkpoints is no lap")
	# A lap that leaves the track is timed, but does not count.
	var laps := []
	race.lap_finished.connect(func(_a: Actor, time: float, counted: bool) -> void: laps.append([time, counted]))
	var from := track.locate(bike.global_position)
	var to_line := (line_i - from + track.points.size()) % track.points.size()
	var full := track.points.size()
	await _drive(t, race, bike, from, to_line + full + 3, 40.0, 200, 230)
	t.check(laps.size() == 1 and not laps[0][1], "a lap that cut off the track is not counted")
	t.check(race.board.is_empty(), "and goes nowhere near the board")
	t.check(int(race.view_run().get("lap", 0)) == 2, "it still moves the run on a lap")
	# A clean lap counts and goes on the board, and its splits set the pace.
	from = track.locate(bike.global_position)
	to_line = (line_i - from + track.points.size()) % track.points.size()
	await _drive(t, race, bike, from, to_line + 3)
	t.check(laps.size() == 2 and laps[1][1], "a clean lap counts")
	t.check(race.board.size() == 1 and race.board[0].machine == "bike_scrapper"
			and is_equal_approx(float(race.board[0].time), float(laps[1][0])), "and goes on the board")
	view = race.view_run()
	t.check(is_equal_approx(float(view.best_lap), float(laps[1][0])), "it is the run's best lap")
	await _drive(t, race, bike, track.locate(bike.global_position), 200)
	view = race.view_run()
	t.check(int(view.last_gate) == 1 and not is_nan(float(view.last_delta)),
			"the next lap's first checkpoint is split against the best")
	# Down in the Spillway's channel, it is put back at the last checkpoint.
	bike.global_position = Vector3(68.0, -5.0, 250.0)
	bike.set("velocity", Vector3.ZERO)
	await t.frames(40)
	var gate_at: Vector3 = track.gates[1].at
	t.check(bike.global_position.y > -1.0 and bike.global_position.distance_to(gate_at) < 8.0
			and race.view_run().phase == "racing", "a machine down in the channel is put back at the last checkpoint")
	# A wheeled machine is told to keep to the Spillway's ramp side.
	var spill := track.locate(Vector3(68.0, 0.0, 236.0))
	t.check(track.line_offset(spill, false) < -1.0 and track.line_offset(spill, true) == 0.0,
			"wheels keep to the ramp at the Spillway, a hover may take either side")
	# Restart puts it back on the grid, keeping the best.
	race.ask("restart")
	await t.frames(2)
	view = race.view_run()
	t.check(view.phase == "grid" and int(view.lap) == 1 and is_equal_approx(float(view.best_lap), float(laps[1][0])),
			"a restart goes back to the grid and keeps the best lap")
	# Getting off ends the run.
	bike.call("dismount")
	await t.frames(2)
	t.check(race.view_run().is_empty() and not bool(bike.get("held")), "getting off ends the run")
	# Nothing is at stake: a sign-out brings nothing home and loses nothing.
	var results := []
	race.player_finished.connect(func(_a: Actor, result: Dictionary) -> void: results.append(result))
	bike.call("mount", me)
	await t.frames(2)
	race.begin_sign_out(me, true)
	await t.frames(int((world.sign_out_time + 1.0) * Engine.physics_ticks_per_second))
	t.check(results.size() == 1 and results[0].outcome == "left", "a racer can sign out")
	if not results.is_empty():
		t.check(results[0].brought_home.is_empty() and results[0].lost.is_empty() and results[0].kept_gear.is_empty(),
				"riding a track machine out brings nothing home and loses nothing")
	t.check(start_i >= 0, "the grid is on the track")
	race.queue_free()
	await t.frames(2)


static func _test_ghost_data(t: Node) -> void:
	var ghost := RaceGhost.new()
	for k in 30:
		ghost.record(k * 0.1, Vector3(k, 0, 0), 0.5)
	var data := ghost.to_data()
	var back := RaceGhost.from_data(data)
	t.check(back != null and back.samples() == 30, "a ghost keeps its samples")
	if back == null:
		return
	var mid := back.sample(1.05)
	t.check(absf(mid.origin.x - 10.5) < 0.01, "and plays back between them")
	t.check(RaceGhost.from_data({"t": [1], "p": "junk"}) == null, "a broken ghost file is refused")
