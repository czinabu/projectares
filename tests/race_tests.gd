extends RefCounted
## Checks for the race world (DESIGN.md section 9): Meridian's Coilrun
## track, the time trial's grid, lights, gates, laps and off-track rule, the
## board, the stock race profiles, and that racing never risks or grants
## gear. Run from the main test runner. Nothing here starts a server.

const RaceLeague := preload("res://core/race/race_league.gd")
const StashRules := preload("res://core/account/stash_rules.gd")
const StashService := preload("res://core/account/stash_service.gd")


## A league kept in memory, for a race to read and record into.
class MemoryBank:
	extends Race.LeagueBank
	var states := {}
	var recorded: Array = []

	func state(key: String) -> Dictionary:
		return RaceLeague.clean(states.get(key, {}))

	func record(key: String, result: Dictionary) -> void:
		recorded.append([key, result])
		states[key] = RaceLeague.apply(state(key), result, 100).state

	## "key|track|machine" -> RaceGhost.
	var kept := {}

	func tune(key: String, machine: String, kit: String) -> void:
		var s := state(key)
		if RaceLeague.set_kit(s, machine, kit):
			states[key] = s

	func keep_ghost(key: String, track_id: String, machine: String, ghost: RaceGhost) -> void:
		var s := state(key)
		if RaceLeague.note_best(s, track_id, machine, ghost.lap_time):
			states[key] = s
			kept["%s|%s|%s" % [key, track_id, machine]] = ghost

	func ghost_of(keys: Array, track_id: String, machine: String) -> Dictionary:
		for key: Variant in keys:
			var ghost: RaceGhost = kept.get("%s|%s|%s" % [key, track_id, machine])
			if ghost != null:
				return {"ok": true, "name": str(key), "machine": machine, "lap": ghost.lap_time,
						"ghost": ghost.to_packed()}
		return {"ok": false}


static func run(t: Node) -> void:
	print("Race world: Meridian time trials, live races and the league")
	# Quiet tracks, unless a check asks for the AI's own races.
	Race.ambient_races = false
	_test_world(t)
	_test_track(t)
	_test_formatting(t)
	_test_league_rules(t)
	_test_league_on_account(t)
	_test_bests(t)
	_test_ghosts_on_account(t)
	await _test_time_trial(t)
	await _test_skyhook(t)
	await _test_live_race(t)
	await _test_desks_and_pits(t)
	_test_tuning_rules(t)
	await _test_tuning(t)
	_test_crowd(t)
	_test_works(t)
	_test_ghost_data(t)
	await _test_off_the_machine(t)
	await _test_ambient_races(t)
	Race.ambient_races = true


## Machines on the track that no AI racer rides: the bays and people's.
static func _machines(race: Race) -> int:
	return race.vehicles.filter(func(v: Variant) -> bool:
		return is_instance_valid(v) and not race.is_ai_racer((v as Node3D).get("rider"))).size()


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
		off_from := -1, off_to := -1, on: RaceTrack = null) -> int:
	var track := on if on != null else race.track
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
	var bank := MemoryBank.new()
	race.league_bank = bank
	await t.frames(5)
	var me := race.player
	t.check(me != null and me.weapons_locked, "a racer has weapons locked")
	var is_vehicle := func(id: String) -> bool: return ItemDB.has_tag(id, "vehicle")
	t.check(not me.inventory.items.any(is_vehicle) and not me.gear_items.any(is_vehicle),
			"a racer brings no vehicle of their own")
	t.check(race.stowed_for(me).is_empty(), "nor one on the watch")
	t.check(Portal.choices_for(race, me) == ([Portal.HOME] as Array[String]), "the portal home is on offer")
	var bays: Array = race.vehicles.filter(func(v: Node3D) -> bool:
		return v.get("rider") == null and race.track_near(v.global_position) == race.track)
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
	t.check(bank.kept.is_empty(), "nor is it kept as a ghost")
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
	# The authority recorded the lap as it was driven and kept it as a ghost.
	var key := "%s|%s|bike_scrapper" % [race.state_for(me).owner, track.id]
	var kept: RaceGhost = bank.kept.get(key)
	t.check(kept != null and kept.samples() >= 10 and is_equal_approx(kept.lap_time, float(laps[1][0]))
			and is_equal_approx(RaceLeague.best_lap(bank.state(race.state_for(me).owner), track.id, "bike_scrapper"),
			float(laps[1][0])), "a clean lap is kept as the racer's best ghost, its time as their best")
	if kept != null:
		t.check(kept.sample(0.0).origin.distance_to(line.at) < 30.0, "the ghost starts at the line")
	var mine := race.ghost_shown("mine", track.id, "bike_scrapper")
	t.check(not mine.is_empty() and is_equal_approx(float(mine.lap), float(laps[1][0])),
			"and comes straight back as the ghost to chase")
	race.want_ghost("leader", track.id, "bike_scrapper")
	var leader := race.ghost_shown("leader", track.id, "bike_scrapper")
	t.check(not leader.is_empty() and leader.ghost.samples() == kept.samples() if kept != null else false,
			"the board leader's ghost is the leader's kept lap")
	race.want_ghost("friend", track.id, "bike_scrapper")
	t.check(race.ghost_shown("friend", track.id, "bike_scrapper").is_empty(), "solo, no friend's ghost turns up")
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


## A live race: asking to race forms one on the grid, AI racers fill every
## empty slot at the start, everyone goes under one set of lights, the AI
## drive clean laps on their own, places are kept, and once the winner is
## home and the rest are out of time the results go up, people's laps only
## on the board, and the AI leave with their machines.
static func _test_live_race(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	var race: Race = world.new_raid()
	t.add_child(race)
	race.start(world, 9, [Loadout.BARE] as Array[String])
	await t.frames(5)
	var me := race.player
	var track := race.track
	t.check(track.start_slots.size() >= Race.GRID_SIZE, "the grid has a slot for every racer")
	var bike: Node3D = null
	for v: Node3D in race.vehicles:
		if v.get("item_id") == "bike_raider" and v.get("rider") == null and race.track_near(v.global_position) == track:
			bike = v
			break
	if bike == null:
		t.check(false, "a Raider waits in the pit bays")
		race.queue_free()
		return
	t.check(not race.join_race(me).get("ok", false), "you race on a machine")
	var bank := MemoryBank.new()
	race.league_bank = bank
	var heard: Array = []
	race.radio.connect(func(a: Actor, from: String, text: String) -> void: heard.append([a, from, text]))
	me.global_position = bike.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	bike.call("mount", me)
	await t.frames(2)
	t.check(race.view_run().get("phase") == "grid" and str(race.view_run().get("heat")) == "",
			"getting on a machine is a time trial until you ask to race")
	var bays_before := race.vehicles.size()
	race.ask("race")
	await t.frames(2)
	var view := race.view_run()
	t.check(view.get("phase") == "waiting" and view.get("heat") == "forming" and bool(bike.get("held")),
			"asking to race puts you on the grid of the next race, held")
	var forming: Race.Heat = race.heats.get(track.id)
	t.check(forming != null and forming.runs.size() == Race.GRID_SIZE and forming.runs.all(func(r: Race.Run) -> bool:
			return r.phase == "waiting" and bool(r.vehicle.get("held"))),
			"the AI line up on the grid at once, held with you (Caleb's \"nothing happened\")")
	t.check(forming != null and forming.starts_at - race.clock <= Race.ALL_IN_FORM + 0.1,
			"with everyone here on the grid, the lights come on in %d s, not %d" % [int(Race.ALL_IN_FORM), int(Race.FORM_TIME)])
	t.check(Race.run_line(view).begins_with("Next race in"), "the watch says when it starts")
	t.check(RaceView.heat_text(race.heat_view(track.id)).begins_with("NEXT RACE"),
			"and so does the pit board")
	# Let it go now rather than in half a minute.
	(race.heats[track.id] as Race.Heat).starts_at = race.clock
	await t.frames(3)
	var heat: Race.Heat = race.heats.get(track.id)
	t.check(heat != null and heat.phase == "racing" and heat.runs.size() == Race.GRID_SIZE,
			"at the start AI racers fill the grid (%d racers)" % (heat.runs.size() if heat != null else 0))
	if heat == null:
		race.queue_free()
		return
	var ai := heat.runs.filter(func(r: Race.Run) -> bool: return r.ai)
	var ai_machines: Array = ai.map(func(r: Race.Run) -> Node3D: return r.vehicle)
	t.check(ai.size() == Race.GRID_SIZE - 1 and race.vehicles.size() == bays_before + ai.size(),
			"each AI racer rides a machine of its own, not one from the bays")
	var slots := {}
	var names := {}
	for run: Race.Run in heat.runs:
		slots[run.slot] = true
		names[run.actor.display_name] = true
	t.check(slots.size() == Race.GRID_SIZE and names.size() == Race.GRID_SIZE,
			"every racer has a slot and a name of their own")
	var stock := true
	for r: Race.Run in ai:
		var profile: Dictionary = ItemDB.RACE_SCRAPPER if r.machine == "bike_scrapper" else ItemDB.RACE_RAIDER
		stock = stock and is_equal_approx(float(r.vehicle.get("max_speed")), float(profile.max_speed)) \
				and r.actor.vehicle == r.vehicle and r.go_at == heat.runs[0].go_at
	t.check(stock, "the AI ride stock machines on their race profile, under the same lights")
	var rookies := RaceLeague.rivals_in(0)
	var on_grid: Array[String] = []
	var top_run: Race.Run = null
	for r: Race.Run in ai:
		if r.rival != "":
			on_grid.append(r.rival)
		if r.rival == RaceLeague.top_rival(0):
			top_run = r
	var all_there := on_grid.size() == rookies.size()
	for id in rookies:
		all_there = all_there and id in on_grid and names.has(RaceLeague.rival_name(id))
	t.check(heat.league == 0 and all_there, "a rookie's grid holds the Rookie league's named rivals, by name")
	t.check(top_run != null and is_equal_approx((race.drivers[top_run.actor] as RaceDriver).skill,
			RaceLeague.rival_skill(top_run.rival)), "each rival drives at their own skill")
	var rival_names: Array = RaceLeague.RIVALS.values().map(func(r: Dictionary) -> String: return r.name)
	t.check(heard.size() == 1 and heard[0][0] == me and str(heard[0][2]) != "" and heard[0][1] in rival_names,
			"at the lights a rival says something on your race radio")
	await t.frames(int(Race.LIGHTS * Race.LIGHT_STEP * Engine.physics_ticks_per_second) + 5)
	t.check(race.view_run().get("phase") == "racing" and int(race.view_run().get("place", 0)) > 0,
			"at the go everyone races, and you have a place")
	# One lap, so the test is short; you sit still on the line.
	var laps := track.laps
	track.laps = 1
	await t.frames(5 * Engine.physics_ticks_per_second)
	var moving := ai.filter(func(r: Race.Run) -> bool: return absf(float(r.vehicle.get("speed"))) > 8.0)
	t.check(moving.size() == ai.size(), "the AI racers drive off on their own (%d of %d)" % [moving.size(), ai.size()])
	var places := {}
	for run: Race.Run in heat.runs:
		places[run.place] = true
	t.check(places.size() == Race.GRID_SIZE and not places.has(0), "every racer has a place of their own")
	t.check(int(race.view_run().get("place", 0)) == Race.GRID_SIZE, "standing still, you are last")
	var ai_laps := []
	race.lap_finished.connect(func(a: Actor, time: float, counted: bool) -> void:
		if race.is_ai_racer(a):
			ai_laps.append([time, counted]))
	var limit := 150 * Engine.physics_ticks_per_second
	for k in limit:
		if heat.phase != "racing":
			break
		await t.frames(1)
	track.laps = laps
	t.check(heat.phase == "done", "once the winner is home and the rest are out of time, the race is over")
	var clean := ai_laps.filter(func(l: Array) -> bool: return l[1])
	t.check(ai_laps.size() >= 4 and clean.size() >= ai_laps.size() - 1,
			"the AI drive the racing line, clean laps (%d of %d clean)" % [clean.size(), ai_laps.size()])
	t.check(heat.results.size() == Race.GRID_SIZE and int(heat.results[0].place) == 1
			and bool(heat.results[0].ai) and float(heat.results[0].time) > 0.0,
			"the results go up, the winner first")
	var last: Dictionary = heat.results[heat.results.size() - 1]
	t.check(last.name == me.display_name and float(last.time) < 0.0, "a racer who never finished is last, not finished")
	t.check(race.view_run().get("phase") == "done" and int(race.view_run().get("finish_place", 0)) == Race.GRID_SIZE,
			"your run ends with your place")
	t.check(race.board.all(func(e: Dictionary) -> bool: return e.name == me.display_name),
			"AI laps never go on the board")
	t.check(bank.recorded.size() == 1, "your finish goes to the league")
	if bank.recorded.size() == 1:
		var result: Dictionary = bank.recorded[0][1]
		t.check(int(result.place) == Race.GRID_SIZE and int(result.field) == Race.GRID_SIZE
				and not bool(result.finished) and (result.ahead as Array).size() == rookies.size(),
				"as last, not finished, behind every rival")
	t.check(heard.size() >= 2 and heard[heard.size() - 1][0] == me, "and a rival has a word at the finish")
	t.check(RaceView.heat_text(race.heat_view(track.id)).begins_with("RESULTS"), "the board shows the results")
	await t.frames(int((Race.RESULTS_TIME + 0.5) * Engine.physics_ticks_per_second))
	t.check(not race.heats.has(track.id) and race.drivers.is_empty()
			and race.bots.filter(func(b: Actor) -> bool: return is_instance_valid(b)).is_empty(),
			"then the AI racers leave")
	await t.frames(2)
	t.check(ai_machines.all(func(v: Variant) -> bool: return not is_instance_valid(v)), "with their machines")
	t.check(str(race.view_run().get("heat", "x")) == "", "and your run is a time trial again")
	race.queue_free()
	await t.frames(2)


## Race control's desks and the way off the track (Caleb's ask): a desk
## puts you on the next race's grid on a fresh machine, a watch desk follows
## the racers, a race on refuses a sign-up, and a finished racer is set down
## on pit row (driving in, or after `PIT_TIME`) with the machine gone.
static func _test_desks_and_pits(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	var race: Race = world.new_raid()
	t.add_child(race)
	race.start(world, 11, [Loadout.BARE] as Array[String])
	await t.frames(5)
	var me := race.player
	var track := race.track
	var desks := {}
	for node: Node in race.map.find_children("*", "", true, false):
		if node.is_in_group("race_desk"):
			desks["%s|%s" % [node.get_meta("track"), node.get_meta("machine")]] = node
	var all_there := true
	for rt in race.circuits:
		for machine in ["bike_scrapper", "bike_raider", ""]:
			all_there = all_there and desks.has("%s|%s" % [rt.id, machine])
	t.check(all_there, "race control has a desk for each track's machines and one to watch from (%d)" % desks.size())
	var raider_desk: Node3D = desks.get("%s|bike_raider" % track.id)
	var scrapper_desk: Node3D = desks.get("%s|bike_scrapper" % track.id)
	if raider_desk == null or scrapper_desk == null:
		race.queue_free()
		return
	t.check(not race.request(me, "signup:%s:bike_raider" % track.id).get("ok", false), "a desk is used standing at it")
	me.global_position = raider_desk.global_position + Vector3(1.0, 0.2, 0.0)
	await t.frames(2)
	t.check(not race.request(me, "signup:%s:jet_hawk" % track.id).get("ok", false), "only the track's own machines")
	var bays := _machines(race)
	t.check(race.request(me, "signup:%s:bike_raider" % track.id).get("ok", false), "standing at a desk, you sign up")
	await t.frames(2)
	var view := race.view_run()
	var bike: Node3D = me.vehicle
	t.check(bike != null and bike.get("item_id") == "bike_raider" and _machines(race) == bays + 1,
			"on a fresh machine of the desk's kind")
	t.check(view.get("phase") == "waiting" and view.get("heat") == "forming" and bool(bike.get("held")),
			"straight onto the grid of the next race")
	# Another desk swaps the machine; the one the desk made goes.
	me.vehicle.call("dismount")
	await t.frames(1)
	me.global_position = scrapper_desk.global_position + Vector3(1.0, 0.2, 0.0)
	await t.frames(2)
	t.check(race.request(me, "signup:%s:bike_scrapper" % track.id).get("ok", false), "you can change machine at the next desk")
	await t.frames(2)
	t.check(not is_instance_valid(bike) and me.vehicle != null and me.vehicle.get("item_id") == "bike_scrapper"
			and _machines(race) == bays + 1 and race.view_run().get("heat") == "forming",
			"the old desk machine goes and you keep your place in the race")
	# Desks say how the next race stands.
	var forming := race.heat_view(track.id)
	t.check(RaceView.desk_text("COILRUN", forming).contains("1/%d riders" % Race.GRID_SIZE)
			and RaceView.desk_prompt("bike_raider", forming).begins_with(RaceView.key() + "  Join"), "a desk shows the next race and who is on it")
	t.check(RaceView.desk_prompt("bike_raider", {}).begins_with(RaceView.key() + "  Start")
			and RaceView.desk_prompt("", forming).contains("Watch"), "and what it does")
	var rv := RaceView.new()
	rv.setup(race)
	race.add_child(rv)
	(race.heats[track.id] as Race.Heat).starts_at = race.clock
	await t.frames(3)
	var watched := rv.watch_list(track.id)
	t.check(watched.size() == Race.GRID_SIZE - 1 and watched.all(func(v: Node3D) -> bool:
			return v.get("rider") != me), "the watch desk follows everyone else on the track")
	var racing := race.heat_view(track.id)
	t.check(RaceView.desk_prompt("bike_raider", racing).begins_with("A race is on"), "while a race is on, the desk says so")
	var stand := Actor.new()
	stand.display_name = "Late"
	race.add_child(stand)
	stand.global_position = raider_desk.global_position + Vector3(0.5, 0.2, 0.0)
	var late := race.sign_up(stand, track.id, "bike_raider")
	t.check(not late.get("ok", false) and str(late.get("error", "")).contains("Watch"),
			"a sign-up during a race is turned away, pointed at the watch desk")
	stand.queue_free()
	rv.watch(track.id)
	t.check(rv.watching == track.id, "watching a track")
	rv.watch("")
	t.check(rv.watching == "", "and back")
	rv.queue_free()
	# Finished: driving into the pits sets you down there and the machine goes.
	var run: Race.Run = race.runs.get(me)
	var machine := me.vehicle
	var laps := track.laps
	track.laps = 1
	run.lap = 1
	run.phase = "racing"
	race.call("_finish_lap", run, race.clock)
	track.laps = laps
	t.check(race.view_run().get("phase") == "done" and Race.run_line(race.view_run()).ends_with("head to the pits"),
			"at the finish you are told to head to the pits")
	await t.frames(int(Engine.physics_ticks_per_second))
	t.check(me.vehicle == machine, "you can ride on after the line")
	var pit := track.pit_spot()
	machine.global_position = pit + Vector3(2.0, 0.6, 0.0)
	machine.set("velocity", Vector3.ZERO)
	machine.set("speed", 0.0)
	await t.frames(4)
	t.check(me.vehicle == null and race.view_run().is_empty(), "driving into the pits ends it: you are set down")
	t.check(Vector2(me.global_position.x - pit.x, me.global_position.z - pit.z).length() < 4.0,
			"standing on pit row")
	await t.frames(2)
	t.check(not is_instance_valid(machine), "and the machine goes")
	# Out on the track, you are set down anyway once the time is up.
	me.global_position = scrapper_desk.global_position + Vector3(1.0, 0.2, 0.0)
	await t.frames(2)
	t.check(race.request(me, "signup:%s:bike_scrapper" % track.id).get("ok", false)
			and race.view_run().get("heat") == "forming", "once that race is over, a desk forms the next one")
	var desk_bike: Node3D = me.vehicle
	desk_bike.call("dismount")
	await t.frames(3)
	t.check(not is_instance_valid(desk_bike) and race.view_run().is_empty(), "getting off a desk's machine, it goes")
	var bay: Node3D = null
	for v: Node3D in race.vehicles:
		if v.get("rider") == null and race.track_near(v.global_position) == track:
			bay = v
			break
	if bay != null:
		me.global_position = bay.global_position + Vector3(2.0, 0.2, 0.0)
		await t.frames(2)
		bay.call("mount", me)
		await t.frames(2)
		run = race.runs.get(me)
		if run != null:
			bay.global_position = track.points[track.points.size() / 2] + Vector3(0, 0.6, 0)
			run.phase = "done"
			run.done_at = race.clock - Race.PIT_TIME + 0.5
			await t.frames(int(0.25 * Engine.physics_ticks_per_second))
			t.check(me.vehicle == bay, "a finished time trial rides on for a while")
			await t.frames(int(0.5 * Engine.physics_ticks_per_second))
			t.check(me.vehicle == null and Vector2(me.global_position.x - pit.x, me.global_position.z - pit.z).length() < 4.0,
					"then, out on the track, you are set down on pit row anyway")
		else:
			t.check(false, "getting on a bay machine starts a time trial")
	race.queue_free()
	await t.frames(2)


## Tuning kits (`RaceLeague.KITS`): each league opens more, a kit is a
## multiplier on the race profile, and a saved choice is made safe.
static func _test_tuning_rules(t: Node) -> void:
	var rookie := RaceLeague.fresh()
	t.check(RaceLeague.kits_for(rookie) == (["stock"] as Array[String]), "a rookie has only the stock setup")
	t.check(not RaceLeague.set_kit(rookie, "bike_raider", "short") and RaceLeague.kit_of(rookie, "bike_raider") == "stock",
			"and cannot fit a kit their league has not opened")
	var club := RaceLeague.fresh()
	club.league = 1
	t.check(RaceLeague.kits_for(club) == (["stock", "short", "tall"] as Array[String]), "the Club league opens the gearing kits")
	t.check(RaceLeague.set_kit(club, "bike_raider", "tall") and RaceLeague.kit_of(club, "bike_raider") == "tall"
			and RaceLeague.kit_of(club, "bike_scrapper") == "stock", "a kit is fitted per machine")
	t.check(RaceLeague.next_kit(club, "bike_raider") == "stock" and RaceLeague.next_kit(club, "bike_scrapper") == "short",
			"the bench turns round the opened kits")
	t.check(not RaceLeague.set_kit(club, "bike_raider", "grip"), "a higher league's kit stays shut")
	var kept := RaceLeague.clean({"league": 1, "tunes": {"bike_raider": "tall", "bike_scrapper": "nitro", "x": "stock"}})
	t.check(kept.tunes == {"bike_raider": "tall"}, "a saved setup keeps only real kits (%s)" % str(kept.tunes))
	var demoted := RaceLeague.clean({"league": 0, "tunes": {"bike_raider": "grip"}})
	t.check(RaceLeague.kit_of(demoted, "bike_raider") == "stock", "a kit the league has not opened runs as stock")
	var tall := RaceLeague.tuned(ItemDB.RACE_RAIDER, "tall")
	t.check(is_equal_approx(float(tall.max_speed), ItemDB.RACE_RAIDER.max_speed * 1.003)
			and is_equal_approx(float(tall.accel), ItemDB.RACE_RAIDER.accel * 0.85)
			and is_equal_approx(float(tall.turn_rate), ItemDB.RACE_RAIDER.turn_rate), "a kit trades one stat for another")
	var sidegrades := true
	for kit: String in RaceLeague.KITS:
		var mult: Dictionary = RaceLeague.KITS[kit].mult
		if kit == "stock":
			continue
		sidegrades = sidegrades and mult.values().any(func(m: float) -> bool: return m > 1.0) \
				and mult.values().any(func(m: float) -> bool: return m < 1.0)
	t.check(sidegrades, "every kit gives something up for what it gains")
	t.check(RaceView.bench_text("bike_raider", club).contains("▶ Tall gearing")
			and RaceView.bench_text("bike_raider", club).contains("Grip tyres · Pro"),
			"a pit bench shows the fitted kit and where the rest open")
	t.check(RaceView.bench_prompt("bike_raider", rookie).contains("Club")
			and RaceView.bench_prompt("bike_scrapper", club).begins_with(RaceView.key() + "  Fit Short gearing"), "and what pressing the interact key fits")
	# On the account, only the server's own call fits one.
	var service := StashService.new()
	service.persist = false
	var account: String = service.sign_in("Tuner", StashService.new_secret()).account_id
	t.check(not service.tune_race(account, "bike_raider", "tall").ok, "an account fits no kit before its league opens it")
	service.load_account(account).racing.league = 1
	t.check(service.tune_race(account, "bike_raider", "tall").ok
			and RaceLeague.kit_of(RaceLeague.clean(service.snapshot(account).racing), "bike_raider") == "tall",
			"then keeps the kit fitted, in its snapshot")


## The pit bench in a race: a kit fitted there goes on the racer's machine
## for their runs (and a machine on the grid at once), and off it again
## when the run ends, so the bays stay stock.
static func _test_tuning(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	var race: Race = world.new_raid()
	t.add_child(race)
	race.start(world, 13, [Loadout.BARE] as Array[String])
	var bank := MemoryBank.new()
	race.league_bank = bank
	await t.frames(5)
	var me := race.player
	var key: String = race.state_for(me).owner
	var bench: Node3D = null
	for node: Node in race.map.find_children("*", "", true, false):
		if node.is_in_group("race_tune") and node.get_meta("machine") == "bike_raider" \
				and node.get_meta("track") == race.track.id:
			bench = node
	t.check(bench != null, "the pits have a tuning bench for each machine")
	if bench == null:
		race.queue_free()
		return
	t.check(not race.request(me, "tune:bike_raider").get("ok", false), "a bench is used standing at it")
	me.global_position = bench.global_position + Vector3(0.5, 0.2, 0.0)
	await t.frames(2)
	var refused := race.request(me, "tune:bike_raider")
	t.check(not refused.get("ok", false) and str(refused.get("error", "")).contains("Club"), "a rookie is told when kits open")
	var club := RaceLeague.fresh()
	club.league = 2
	bank.states[key] = club
	t.check(race.request(me, "tune:bike_raider").get("kit", "") == "short"
			and race.request(me, "tune:bike_raider").get("kit", "") == "tall", "each use fits the next kit")
	t.check(RaceLeague.kit_of(bank.state(key), "bike_raider") == "tall", "kept with the racer's league")
	var bay: Node3D = null
	for v: Node3D in race.vehicles:
		if v.get("item_id") == "bike_raider" and v.get("rider") == null and race.track_near(v.global_position) == race.track:
			bay = v
			break
	if bay == null:
		t.check(false, "a Raider waits in the bays")
		race.queue_free()
		return
	me.global_position = bay.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	bay.call("mount", me)
	await t.frames(2)
	t.check(race.view_run().get("kit") == "tall" and is_equal_approx(float(bay.get("max_speed")),
			ItemDB.RACE_RAIDER.max_speed * 1.003) and is_equal_approx(float(bay.get("accel")), ItemDB.RACE_RAIDER.accel * 0.85),
			"getting on, the machine runs with the racer's kit")
	bay.call("dismount")
	await t.frames(2)
	t.check(is_equal_approx(float(bay.get("max_speed")), ItemDB.RACE_RAIDER.max_speed)
			and is_equal_approx(float(bay.get("accel")), ItemDB.RACE_RAIDER.accel), "getting off, it is stock again")
	t.check(race.kit_for("", "bike_raider") == "stock", "AI racers and the nameless run stock")
	race.queue_free()
	await t.frames(2)


## The league's rules (`RaceLeague`): points by place, no relegation, the
## top rival's gate, one league at a time, the day's pay cap, the radio's
## lines and a saved state made safe.
static func _test_league_rules(t: Node) -> void:
	t.check(RaceLeague.points_for(1, 8) == 21 and RaceLeague.points_for(8, 8) == -7
			and RaceLeague.points_for(3, 8, false) == -7 and RaceLeague.points_for(4, 8) > 0,
			"beating racers gains more than losing to them costs; not finishing counts last")
	var leagues_rise := true
	for i in range(1, RaceLeague.LEAGUES.size()):
		leagues_rise = leagues_rise and RaceLeague.floor_of(i) > RaceLeague.floor_of(i - 1) \
				and RaceLeague.ai_skill(i) > RaceLeague.ai_skill(i - 1)
	t.check(leagues_rise and RaceLeague.ai_skill(RaceLeague.LEAGUES.size() - 1) <= 1.0,
			"each league is harder to reach and its AI better")
	var cast := true
	for i in RaceLeague.LEAGUES.size():
		var rivals := RaceLeague.rivals_in(i)
		cast = cast and rivals.size() == 3 and RaceLeague.top_rival(i) == rivals[2]
		for id in rivals:
			var skill := RaceLeague.rival_skill(id)
			cast = cast and skill <= 1.0 and skill > RaceLeague.ai_skill(i) \
					and RaceLeague.rival_skill(RaceLeague.top_rival(i)) >= skill
	t.check(cast, "every league has three named rivals, the top one the best of them")
	var lines := true
	for id: String in RaceLeague.RIVALS:
		for event: String in RaceLeague.EVENTS:
			lines = lines and RaceLeague.line(id, event, "Ash", RaceLeague.fresh(), 0) != ""
	t.check(lines, "every rival has something to say at every moment")
	var s := RaceLeague.fresh()
	var lose := {"track": "coilrun", "place": 8, "field": 8, "finished": true, "ahead": ["pip", "haro", "moss"],
			"behind": []}
	var applied := RaceLeague.apply(s, lose, 10)
	t.check(int(applied.state.rating) == 0 and int(applied.points) == -7 and int(applied.scrip) == RaceLeague.FINISH_SCRIP,
			"a rookie's rating never drops below the league's floor")
	t.check(s.races == 0 and int(applied.state.races) == 1, "the state passed in is left alone")
	var win := {"track": "coilrun", "place": 1, "field": 8, "finished": true, "ahead": [], "behind": ["pip", "haro"]}
	s = RaceLeague.fresh()
	for k in 4:
		s = RaceLeague.apply(s, win, 10).state
	t.check(int(s.league) == 0 and int(s.rating) == RaceLeague.next_from(0) and RaceLeague.at_gate(s),
			"without beating the top rival the rating waits at the next league")
	t.check(RaceLeague.standing_line(s).contains(RaceLeague.rival_name("moss")), "and says who to beat")
	var paid := 0
	var day := RaceLeague.fresh()
	for k in 10:
		var a := RaceLeague.apply(day, win, 10)
		paid += int(a.scrip)
		day = a.state
	t.check(paid == RaceLeague.DAILY_CAP, "race pay stops at the day's cap (%d)" % paid)
	t.check(int(RaceLeague.apply(day, win, 11).scrip) == RaceLeague.PLACE_SCRIP[0], "and starts again the next day")
	var beat_top := {"track": "coilrun", "place": 1, "field": 8, "finished": true, "ahead": [], "behind": ["moss"]}
	applied = RaceLeague.apply(s, beat_top, 10)
	t.check(bool(applied.promoted) and int(applied.state.league) == 1 and not bool(applied.state.top_beaten),
			"beating the top rival at the gate moves you up a league")
	var flying := RaceLeague.fresh()
	flying.rating = 10000
	flying.top_beaten = true
	applied = RaceLeague.apply(flying, win, 10)
	t.check(int(applied.state.league) == 1 and int(applied.state.rating) <= RaceLeague.next_from(1),
			"one league at a time")
	s = RaceLeague.fresh()
	for k in RaceLeague.HUMBLED_AFTER:
		s = RaceLeague.apply(s, win, 10).state
	t.check(RaceLeague.record_against(s, "pip") == [RaceLeague.HUMBLED_AFTER, 0] and RaceLeague.humbled(s, "pip")
			and RaceLeague.line("pip", "lights", "Ash", s, 0) in RaceLeague.LINES.joker.humbled,
			"a rival you keep beating changes their tune")
	t.check(s.recent.size() == RaceLeague.HUMBLED_AFTER and int(s.recent[0].place) == 1, "recent races are kept")
	for k in 10:
		s = RaceLeague.apply(s, win, 10).state
	t.check(s.recent.size() == RaceLeague.RECENT, "only the last few")
	var junk := RaceLeague.clean({"league": 99, "rating": -5, "rivals": {"nobody": [1, 2], "pip": "x"},
			"recent": "no"})
	t.check(int(junk.league) == RaceLeague.LEAGUES.size() - 1 and int(junk.rating) == RaceLeague.floor_of(junk.league)
			and junk.rivals.is_empty() and junk.recent.is_empty(), "a saved state is made safe")
	t.check(RaceLeague.clean_result({"place": 9, "field": 8}).is_empty()
			and RaceLeague.clean_result({"place": 1, "field": 8, "ahead": ["nobody", "pip"]}).ahead == ["pip"],
			"so is a result")
	t.check(RaceLeague.line("pip", "lights", "Ash", RaceLeague.fresh(), 0).find("{you}") < 0,
			"the radio uses your name")


## The league lives on the account: recorded there by the server, carried
## in its snapshot and saved with it, and its scrip paid into it.
static func _test_league_on_account(t: Node) -> void:
	var service := StashService.new()
	service.persist = false
	var id: String = service.sign_in("League Tester", StashService.new_secret()).account_id
	var scrip := int(service.snapshot(id).scrip)
	var answer := service.record_race(id, {"track": "coilrun", "place": 1, "field": 8, "finished": true,
			"ahead": [], "behind": ["pip"]})
	var snap := service.snapshot(id)
	t.check(bool(answer.ok) and int(answer.points) == 21 and int(snap.scrip) == scrip + RaceLeague.PLACE_SCRIP[0],
			"the server records a race on the account and pays its scrip")
	t.check(int(snap.racing.rating) == 21 and int(snap.racing.wins) == 1 and RaceLeague.record_against(snap.racing,
			"pip") == [1, 0], "the snapshot carries the league")
	t.check("racing" in StashRules.CARRIED, "and your own server hands it home")
	var account := service.load_account(id)
	var copy := StashService.Account.new()
	copy.load_dict(account.to_dict())
	t.check(int(copy.racing.rating) == 21, "it is saved with the account")
	t.check(not bool(service.record_race("nobody", {}).get("ok", true)), "nobody else's account is touched")
	var bank := Race.StashLeagueBank.new(service)
	t.check(int(bank.state(id).rating) == 21, "a race reads the league from the accounts")


## Best laps in the league state: kept per track and machine, only ever
## faster, read for a track on any machine, and cleaned.
static func _test_bests(t: Node) -> void:
	var state := RaceLeague.fresh()
	t.check(RaceLeague.note_best(state, "coilrun", "bike_raider", 70.0)
			and RaceLeague.note_best(state, "coilrun", "bike_scrapper", 68.0)
			and not RaceLeague.note_best(state, "coilrun", "bike_raider", 71.0)
			and RaceLeague.note_best(state, "coilrun", "bike_raider", 69.5), "only a faster lap is a new best")
	t.check(is_equal_approx(RaceLeague.best_lap(state, "coilrun", "bike_raider"), 69.5)
			and is_equal_approx(RaceLeague.best_lap(state, "coilrun"), 68.0)
			and RaceLeague.best_machine(state, "coilrun") == "bike_scrapper"
			and RaceLeague.best_lap(state, "skyhook") < 0.0, "a best is read per machine, or the track's on any")
	var raw := state.duplicate(true)
	raw.bests["junk"] = 5.0
	raw.bests["coilrun|x"] = -2.0
	var cleaned := RaceLeague.clean(raw)
	t.check(cleaned.bests.size() == 2 and is_equal_approx(float(cleaned.bests["coilrun|bike_raider"]), 69.5),
			"a saved best list is cleaned")
	t.check(not RaceLeague.note_best(state, "coilrun", "", 50.0) and not RaceLeague.note_best(state, "coilrun",
			"bike_raider", 0.0), "nonsense laps are refused")


## Ghosts on the server's accounts: kept beside the account when faster,
## found among a list of accounts (a friend's, the board leader's), and
## friends' best laps for the pit boards.
static func _test_ghosts_on_account(t: Node) -> void:
	var service := StashService.new()
	service.persist = false
	var a: String = service.sign_in("Ghost One", StashService.new_secret()).account_id
	var b: String = service.sign_in("Ghost Two", StashService.new_secret()).account_id
	var lap := RaceGhost.new()
	for k in 400:
		lap.record(k * 0.1, Vector3(k, 1, -k), 0.01 * k)
	var packed := lap.to_packed()
	t.check(packed.length() < 12000, "a 40 s ghost packs to a few KB (%d)" % packed.length())
	var kept := service.keep_ghost(a, "coilrun", "bike_raider", 40.0, packed)
	t.check(bool(kept.ok) and bool(kept.kept), "the server keeps a racer's best lap ghost")
	t.check(not bool(service.keep_ghost(a, "coilrun", "bike_raider", 41.0, packed).get("kept", true)),
			"but not a slower one")
	t.check(not bool(service.keep_ghost(a, "coilrun", "bike_raider", 30.0, "junk").ok), "nor junk")
	service.keep_ghost(b, "coilrun", "bike_raider", 38.5, packed)
	t.check(is_equal_approx(RaceLeague.best_lap(service.snapshot(a).racing, "coilrun", "bike_raider"), 40.0),
			"the best time is in the account's snapshot")
	t.check(not JSON.stringify(service.load_account(a).to_dict()).contains(packed.substr(4, 40)),
			"the ghost itself is kept apart from the account's own save")
	var found := service.race_ghost([a, b], "coilrun", "bike_raider")
	var ghost := RaceGhost.from_packed(found.get("ghost"), "bike_raider", 38.5)
	t.check(bool(found.ok) and found.name == "Ghost Two" and is_equal_approx(float(found.lap), 38.5) and ghost != null
			and ghost.samples() == 400, "the fastest ghost among friends is found")
	t.check(not bool(service.race_ghost([a], "skyhook", "").ok), "no ghost where nobody has raced")
	t.check(bool(service.race_ghost([a], "coilrun", "").ok), "with no machine named, their best there on any")
	var rows := service.race_bests([a, b])
	t.check(rows.size() == 2 and rows[0].name == "Ghost Two" and rows[0].track == "coilrun", "friends' bests, fastest first")
	var bank := Race.StashLeagueBank.new(service)
	t.check(is_equal_approx(bank.best(a, "coilrun", "bike_raider"), 40.0), "a race reads a racer's best from the accounts")


## Skyhook, the second track: its own bays, a run on it judged on its own
## gates, the road over the road told apart by height, and its own board.
static func _test_skyhook(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	var race: Race = world.new_raid()
	t.add_child(race)
	race.start(world, 6, [Loadout.BARE] as Array[String])
	await t.frames(5)
	t.check(race.circuits.size() == 2 and race.circuits[1].id == "skyhook" and race.track.id == "coilrun",
			"Meridian lays out Coilrun and Skyhook")
	var sky: RaceTrack = race.track_by_id("skyhook")
	t.check(sky != null and sky.gates.size() == 4 and sky.laps == 3, "Skyhook has the line and three checkpoints")
	t.check(sky.length() > 1200.0 and sky.length() < 2000.0, "Skyhook runs %.0f m a lap" % sky.length())
	var top := 0.0
	for p in sky.points:
		top = maxf(top, p.y)
	t.check(top > 15.0, "Skyhook climbs onto its deck (%.0f m up)" % top)
	# Where the road runs over itself, height tells the levels apart.
	var flyover := sky.points[sky.locate(Vector3(-190, 20, -125), -1)]
	var under := sky.points[sky.locate(Vector3(-190, 0.5, -125), -1)]
	t.check(flyover.y > 15.0 and under.y < 1.0, "the flyover and the straight under it are told apart")
	var g2: Dictionary = sky.gates[2]
	var f: Vector3 = g2.forward
	var below: Vector3 = g2.at - Vector3(0, g2.at.y, 0)
	t.check(sky.cross(2, g2.at - f * 2.0, g2.at + f * 2.0) > 0.0 and sky.cross(2, below - f * 2.0, below + f * 2.0) < 0.0,
			"a gate up on the deck is not passed by driving under it")
	var bays: Array = race.vehicles.filter(func(v: Node3D) -> bool:
		return v.get("rider") == null and race.track_near(v.global_position) == sky)
	t.check(bays.filter(func(v: Node3D) -> bool: return v.get("item_id") == "bike_scrapper").size() == 4
			and bays.filter(func(v: Node3D) -> bool: return v.get("item_id") == "bike_raider").size() == 4,
			"Skyhook's pits hold four of each Street machine")
	if bays.is_empty():
		race.queue_free()
		return
	var me := race.player
	var bike: Node3D = bays[0]
	me.global_position = bike.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	bike.call("mount", me)
	await t.frames(2)
	var view := race.view_run()
	t.check(view.get("track") == "skyhook" and view.get("gates") == 4, "a machine from Skyhook's bays races Skyhook")
	t.check(bike.global_position.distance_to(sky.gates[0].at) < 30.0, "on Skyhook's own grid")
	await t.frames(int(Race.LIGHTS * Race.LIGHT_STEP * Engine.physics_ticks_per_second) + 5)
	var laps := []
	race.lap_finished.connect(func(_a: Actor, time: float, counted: bool) -> void: laps.append([time, counted]))
	var line_i: int = sky.gates[0].index
	var from := sky.locate(bike.global_position)
	var to_line := (line_i - from + sky.points.size()) % sky.points.size()
	await _drive(t, race, bike, from, to_line + sky.points.size() + 3, 0.0, -1, -1, sky)
	t.check(laps.size() == 1 and laps[0][1], "a clean lap of Skyhook counts")
	t.check(race.board_for("skyhook").size() == 1 and race.board_for("coilrun").is_empty(),
			"and goes on Skyhook's board, not Coilrun's")
	t.check(race.public_board().all(func(r: Dictionary) -> bool: return r.has("track")),
			"the board sent to clients says which track each time is on")
	race.queue_free()
	await t.frames(2)


## The crowd is a view: a figure mesh with a light stick marked for the
## shader, and people added in blocks.
static func _test_crowd(t: Node) -> void:
	var mesh := Crowd.person_mesh()
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	t.check(mesh.get_surface_count() == 1 and uvs.size() > 0 and uvs.size() < 300,
			"a spectator is one small mesh (%d vertices)" % uvs.size())
	t.check(Array(uvs).any(func(uv: Vector2) -> bool: return uv.x > 1.0), "with a light stick the shader can fold away")
	var crowd := Crowd.new()
	for k in Crowd.CHUNK + 10:
		crowd.add(Vector3(k, 0, 0), 0.0, Color.GRAY, 0.5, k % 9 == 0, 0.3)
	crowd.build()
	t.check(crowd.get_child_count() == 2, "a big crowd is drawn in blocks")
	crowd.free()


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
	var unpacked := RaceGhost.from_packed(back.to_packed(), "bike_raider", 3.0)
	t.check(unpacked != null and unpacked.samples() == 30 and absf(unpacked.sample(1.05).origin.x - 10.5) < 0.02
			and absf(unpacked.sample(1.05).basis.get_euler().y - 0.5) < 0.01, "a packed ghost plays back the same")
	t.check(RaceGhost.from_packed("40:") == null and RaceGhost.from_packed("41:AAAA") == null and RaceGhost.from_packed("x") == null
			and RaceGhost.from_packed(12) == null, "packed junk is refused")


## Meridian's works (`works.gd`) fill the salt round the circuits as
## decoration only: nothing collides, it is drawn in a bounded number of
## merged blocks, and nothing stands on either road.
static func _test_works(t: Node) -> void:
	var map: Node3D = Worlds.get_world("meridian").create_map()
	var works_script: GDScript = load("res://worlds/meridian/works.gd")
	var tracks: Array = map.call("race_tracks")
	var holder := Node3D.new()
	var consts := (map.get_script() as Script).get_script_constant_map()
	var works: RefCounted = works_script.new(holder, int(consts["LAYOUT_SEED"]) + 4, consts["WORKS_KEEP_OUT"].duplicate(true))
	works.call("build", tracks)
	var root := holder.get_child(0)
	t.check(root.find_children("*", "CollisionObject3D", true, false).is_empty(), "the works never collide")
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	t.check(meshes.size() > 20 and meshes.size() < 200, "the works are merged into blocks (%d meshes)" % meshes.size())
	var on_road := 0
	for node: Node in meshes:
		var verts: PackedVector3Array = (node as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in range(0, verts.size(), 5):
			var v := verts[k]
			if v.y < 3.0 and float(works.call("track_dist", v)) < 13.0 * 0.5 + 1.0:
				on_road += 1
	t.check(on_road == 0, "nothing from the works stands on the road (%d points)" % on_road)
	holder.free()
	map.free()


## Getting off out on the track (Caleb: "I wasn't put back in the starting
## area"): set down on pit row and the machine goes; getting off in the
## pits leaves you and a bay machine where you are; stopping a run from the
## watch out on the track does the same as getting off.
static func _test_off_the_machine(t: Node) -> void:
	var world := Worlds.get_world("meridian")
	var race: Race = world.new_raid()
	t.add_child(race)
	race.start(world, 17, [Loadout.BARE] as Array[String])
	await t.frames(5)
	var me := race.player
	var track := race.track
	var pit := track.pit_spot()
	var bays: Array = race.vehicles.filter(func(v: Node3D) -> bool:
		return v.get("rider") == null and race.track_near(v.global_position) == track)
	if bays.size() < 3:
		t.check(false, "the pit bays hold machines to ride")
		race.queue_free()
		return
	var near_pit := func() -> bool:
		return Vector2(me.global_position.x - pit.x, me.global_position.z - pit.z).length() < 4.0
	# A time trial out on the track, then off the machine.
	var bike: Node3D = bays[0]
	me.global_position = bike.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	bike.call("mount", me)
	await t.frames(2)
	t.check(race.view_run().get("phase") == "grid", "a bay machine starts a time trial")
	var far_spot: Vector3 = track.points[track.points.size() / 2]
	t.check(Vector2(far_spot.x - pit.x, far_spot.z - pit.z).length() > Race.PIT_WALK, "half way round is far from the pits")
	bike.global_position = far_spot + Vector3(0, 0.6, 0)
	await t.frames(2)
	bike.call("dismount")
	await t.frames(3)
	t.check(me.vehicle == null and race.view_run().is_empty() and near_pit.call(),
			"getting off out on the track puts you back on pit row")
	t.check(not is_instance_valid(bike), "and the machine goes, the bay fills again")
	# In the pits, getting off leaves things be.
	var other: Node3D = bays[1]
	me.global_position = other.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	other.call("mount", me)
	await t.frames(2)
	other.call("dismount")
	await t.frames(3)
	var apart := me.global_position.distance_to(other.global_position) if is_instance_valid(other) else INF
	t.check(apart < 4.0, "getting off on the grid by the pits, you and the bay machine stay (%.1f m)" % apart)
	# Stopping the run from the watch, out on the track.
	var third: Node3D = bays[2]
	me.global_position = third.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	third.call("mount", me)
	await t.frames(2)
	third.global_position = far_spot + Vector3(0, 0.6, 0)
	await t.frames(2)
	race.ask("retire")
	await t.frames(3)
	t.check(me.vehicle == null and race.view_run().is_empty() and near_pit.call() and not is_instance_valid(third),
			"stopping a run out on the track sets you down on pit row too")
	race.queue_free()
	await t.frames(2)


## Ambient races (Caleb: "the racing world seems dead"): with someone here,
## each track nobody rides gets an AI-only race; asking to race calls its
## field back to the grid to race you; with nobody here they stop.
static func _test_ambient_races(t: Node) -> void:
	Race.ambient_races = true
	var world := Worlds.get_world("meridian")
	var race: Race = world.new_raid()
	t.add_child(race)
	race.start(world, 19, [Loadout.BARE] as Array[String])
	await t.frames(5)
	var me := race.player
	await t.frames(int((Race.AMBIENT_FIRST + 0.5) * Engine.physics_ticks_per_second))
	var track := race.track
	var first: Race.Heat = race.heats.get(track.id)
	t.check(first != null and first.ambient and first.phase == "racing" and first.runs.size() == Race.AMBIENT_FIELD
			and first.people() == 0, "soon after you arrive, the track by you has an AI race of %d on it" % Race.AMBIENT_FIELD)
	t.check(race.heats.size() == Race.AMBIENT_TRACKS, "one at a time, so the server pays little")
	var view := race.heat_view(track.id)
	t.check(bool(view.get("ambient", false)) and RaceView.heat_text(view).begins_with("AI RACE ON")
			and RaceView.desk_prompt("bike_raider", view).begins_with(RaceView.key() + "  Race the AI"),
			"the boards and desks say so, and a desk offers to race them")
	await t.frames(6 * Engine.physics_ticks_per_second)
	var heat: Race.Heat = race.heats.get(track.id)
	var moving := heat.runs.filter(func(r: Race.Run) -> bool:
		return is_instance_valid(r.vehicle) and absf(float(r.vehicle.get("speed"))) > 8.0)
	t.check(moving.size() == Race.AMBIENT_FIELD, "the AI race round on their own (%d moving)" % moving.size())
	var bike: Node3D = null
	for v: Node3D in race.vehicles:
		if v.get("item_id") == "bike_raider" and v.get("rider") == null and race.track_near(v.global_position) == track:
			bike = v
			break
	if bike == null:
		t.check(false, "a Raider waits in the pit bays")
		race.queue_free()
		Race.ambient_races = false
		return
	me.global_position = bike.global_position + Vector3(2.0, 0.2, 0.0)
	await t.frames(2)
	bike.call("mount", me)
	await t.frames(2)
	t.check(race.heats.get(track.id) == heat and heat.ambient, "a time trial shares the track with the AI's race")
	race.ask("race")
	await t.frames(2)
	heat = race.heats.get(track.id)
	t.check(heat != null and not heat.ambient and heat.phase == "forming" and heat.people() == 1
			and heat.runs.size() == Race.GRID_SIZE and race.view_run().get("phase") == "waiting",
			"asking to race calls the AI back to the grid, filled to %d with you on it" % Race.GRID_SIZE)
	t.check(heat != null and heat.runs.all(func(r: Race.Run) -> bool:
			return (r.phase == "waiting" and bool(r.vehicle.get("held"))
					and r.vehicle.global_position.distance_to(track.start_slots[r.slot].origin) < 2.0)),
			"every machine waits at its slot, held for the lights")
	var other: RaceTrack = race.circuits[1]
	await t.frames(3)
	var moved: Race.Heat = race.heats.get(other.id)
	t.check(moved != null and moved.ambient and moved.phase == "racing", "and the AI's own race goes on at the other track")
	# Nobody here: the AI's races stop, so an empty server pays nothing.
	bike.call("dismount")
	await t.frames(2)
	me.is_dead = true
	await t.frames(3)
	t.check(not race.heats.has(other.id) and race.drivers.is_empty(), "with nobody here the AI's races stop")
	me.is_dead = false
	race.queue_free()
	await t.frames(2)
	Race.ambient_races = false
