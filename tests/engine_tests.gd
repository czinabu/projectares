extends RefCounted
## Checks for the Engine's inside (DESIGN.md "The Engine's inside"): the drum
## is hollow, the hatch is open, the Drum Hall, the Shaft, the Coil Galleries
## and the Descent have room for a squad to fight in and a way through, a
## garrison stands guard, the cable lift is powered by one player and carries
## everyone, and inside is out of the weather: no storm, no trail, a cold that
## grows with depth and bites on the coolant. Past the Descent the Heart
## is an arena with room to spare and a way up to its balcony, and its keeper
## fights in two phases (sockets, then purges that warn before they hurt),
## opens a share of its vault for each player who fought it, lights the deep
## beacon and comes back on its own timer. Kept in its own file and called
## from the test runner.

const MapScript := preload("res://worlds/frostline/map.gd")


static func run(t: Node) -> void:
	_shape(t)
	await _inside(t)
	await _deeper(t)
	await _lift(t)
	await _heart(t)


## The layout's numbers: room for a squad (DESIGN.md: no way narrower than
## 9 m, the hall an arena).
static func _shape(t: Node) -> void:
	print("Engine: room for a squad")
	var across := MapScript._hall_half(MapScript.HALL_FLOOR) * 2.0
	t.check(across >= 36.0 and MapScript.ENGINE_LENGTH >= 70.0,
			"the Drum Hall is an arena, %.0f by %.0f m" % [across, MapScript.ENGINE_LENGTH])
	t.check(MapScript.HATCH_WIDTH >= 9.0 and MapScript.SHAFT_RAMP >= 9.0,
			"the hatch and the Shaft's ramps are 9 m wide or more")
	var run := MapScript.SHAFT_TO_Z - MapScript.SHAFT_LANDING - MapScript.SHAFT_FROM_Z
	var steep := rad_to_deg(atan2(MapScript.SHAFT_DEPTH * 0.5, run))
	t.check(steep < 40.0, "the Shaft's ramps are walkable (%.0f degrees)" % steep)
	var frame := MapScript.engine_frame()
	var hall := frame * Vector3(0, MapScript.HALL_FLOOR + 2.0, -20.0)
	var shaft := frame * Vector3(4.0, MapScript.HALL_FLOOR - MapScript.SHAFT_DEPTH + 1.0, 20.0)
	var apron := frame * Vector3(-MapScript.ENGINE_RADIUS - 5.0, MapScript.HALL_FLOOR + 1.0, MapScript.HATCH_Z)
	var roof := frame * Vector3(0, MapScript.ENGINE_RADIUS + 2.0, 0)
	t.check(MapScript.inside_engine(hall) and MapScript.inside_engine(shaft)
			and not MapScript.inside_engine(apron) and not MapScript.inside_engine(roof),
			"the hall and the Shaft are inside; the hatch's apron and the drum's back are not")
	# The galleries and the Descent: every way 9 m wide or more (an alcove is
	# a pocket off a gallery, not a way).
	var narrow := 0
	for room: Array in MapScript.GALLERY_ROOMS:
		var span := float(room[1]) - float(room[0])
		var along := float(room[3]) - float(room[2])
		var pocket := absf(float(room[0])) >= 19.0 or absf(float(room[1])) >= 21.0
		# A short passage on along the drum is as wide as it is across.
		var passage := along <= 8.0 and span >= 9.0
		if minf(span, along) < 9.0 and not pocket and not passage:
			narrow += 1
	t.check(narrow == 0 and MapScript.DESCENT_LANE >= 9.0, "the galleries' halls and the Descent's ramps are 9 m wide or more")
	var ramp_run := MapScript.DESCENT_TO_Z - MapScript.DESCENT_FROM_Z - MapScript.DESCENT_LANDING - MapScript.DESCENT_FOOT
	var ramp_steep := rad_to_deg(atan2(MapScript.DESCENT_DROP / 3.0, ramp_run))
	t.check(ramp_steep < 30.0, "the Descent's ramps are walkable (%.0f degrees)" % ramp_steep)
	var g := MapScript.GALLERY_FLOOR
	var gallery := frame * Vector3(13.0, g + 1.0, 70.0)
	var well := frame * Vector3(0.0, MapScript.DESCENT_FLOOR + 1.0, 150.0)
	var rock := frame * Vector3(0.0, g + 1.0, 60.0)
	t.check(MapScript.inside_engine(gallery) and MapScript.inside_engine(well) and not MapScript.inside_engine(rock),
			"the galleries and the Descent are inside; the rock between the galleries is not")
	t.check(MapScript.engine_depth(hall) == 0 and MapScript.engine_depth(gallery) == 1 and MapScript.engine_depth(well) == 2,
			"depth reads 0 in the hall, 1 in the galleries, 2 down the Descent")
	var channel := frame * Vector3(-13.0, g + 0.5, 70.0)
	t.check(MapScript.on_coolant(channel) and not MapScript.on_coolant(frame * Vector3(-8.0, g + 0.5, 70.0)),
			"the coolant channel runs down the south gallery, a dry walk beside it")


static func _inside(t: Node) -> void:
	print("Engine: inside")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 4242)
	_wake_engine(raid)
	await t.frames(2)
	var frame := MapScript.engine_frame()
	var f := MapScript.HALL_FLOOR
	var space := raid.get_world_3d().direct_space_state
	# The hatch is open and the hall is hollow.
	var outside := frame * Vector3(-MapScript.ENGINE_RADIUS - 4.0, f + 2.0, MapScript.HATCH_Z)
	var through := frame * Vector3(-6.0, f + 2.0, MapScript.HATCH_Z)
	t.check(_ray(space, outside, through).is_empty(), "the hatch opens into the hall")
	var beside := frame * Vector3(-6.0, f + 2.0, MapScript.HATCH_Z + 20.0)
	t.check(not _ray(space, frame * Vector3(-MapScript.ENGINE_RADIUS - 4.0, f + 2.0, MapScript.HATCH_Z + 20.0),
			beside).is_empty(), "everywhere else the hull is solid")
	t.check(_ray(space, frame * Vector3(0, f + 4.0, -35.0), frame * Vector3(0, f + 4.0, 4.0)).is_empty(),
			"the hall is hollow from its west end to the Shaft")
	# Floors stand where a squad walks: the hall, the catwalks, the landing and the Shaft's foot.
	var walk := MapScript.HALL_FLOOR + MapScript.CATWALK_UP
	var catwalk_x := MapScript._hall_half(walk + 2.0) - 0.4 - MapScript.CATWALK_WIDTH * 0.5
	var low := f - MapScript.SHAFT_DEPTH
	var landing := MapScript.SHAFT_TO_Z - MapScript.SHAFT_LANDING * 0.5
	for spot: Array in [[Vector3(0, f, -20.0), "the hall"], [Vector3(catwalk_x, walk, -5.0), "a catwalk"],
			[Vector3(0, f - MapScript.SHAFT_DEPTH * 0.5, landing), "the Shaft's landing"],
			[Vector3(4.0, low, 20.0), "the Shaft's foot"]]:
		var top: Vector3 = frame * ((spot[0] as Vector3) + Vector3(0, 3.0, 0))
		var hit := _floor_ray(space, top)
		var floor_y: float = (frame * (spot[0] as Vector3)).y
		t.check(not hit.is_empty() and absf(hit.position.y - floor_y) < 0.3, "%s has a floor to stand on" % spot[1])
	# Someone can walk from the hatch to the Shaft's foot.
	# The region is built off the main thread: wait until the map has it.
	var nav := raid.get_world_3d().navigation_map
	var goal := frame * Vector3(4.0, low, 20.0)
	await _wait_for_nav(t, nav, goal, raid)
	var from := NavigationServer3D.map_get_closest_point(nav, frame * Vector3(-MapScript.ENGINE_RADIUS - 5.0, f, MapScript.HATCH_Z))
	var path := NavigationServer3D.map_get_path(nav, from, goal, true)
	t.check(path.size() > 1 and path[path.size() - 1].distance_to(goal) < 2.0,
			"a path runs from the hatch, through the hall and down the Shaft (%d points)" % path.size())
	# The garrison.
	var guards: Array = _engine_guards(raid)
	var in_hall := guards.filter(func(g: Dictionary) -> bool:
		return MapScript.inside_engine((g.marker as Node3D).global_position))
	t.check(guards.size() >= 18 and in_hall.size() == guards.size(),
			"a garrison of Wardens stands guard inside (%d)" % guards.size())
	var first: Actor = guards[0].bot
	t.check(first != null and first.faction == "warden" and raid.is_guard(first) and raid._is_extra(first),
			"a guard is a Warden outside the armies")
	var army := raid.bots.filter(func(b: Actor) -> bool: return not raid._is_extra(b))
	t.check(army.is_empty() and frost.bot_count == 0, "and no army walks the valley: its enemies are pockets too (%d)" % army.size())
	first.health.apply_damage(DamageInfo.make(99999.0, null, "test"))
	await t.frames(2)
	raid._tick_guards(0.1)
	t.check(guards[0].bot == null and guards[0].back_in > 0.0, "a guard brought down comes back in time")
	raid._tick_guards(frost.guard_respawn_time + 1.0)
	raid._tick_guards(0.1)
	t.check(guards[0].bot != null and is_instance_valid(guards[0].bot) and not (guards[0].bot as Actor).is_dead,
			"and stands at its post again")
	var engine_caches := raid._caches.filter(func(c: Dictionary) -> bool: return c.source == "engine")
	t.check(engine_caches.size() >= 10, "every level holds caches of its own (%d)" % engine_caches.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var coils := 0
	for i in 60:
		coils += frost.roll_loot("engine", rng).count("engine_coil")
	t.check(coils > 10, "the Engine's caches pay Engine Coils (%d in 60)" % coils)
	var warm_inside := raid.warmth.filter(func(w: Node3D) -> bool: return MapScript.inside_engine(w.global_position))
	t.check(warm_inside.size() >= 4, "warm pockets inside, one or more a level (%d)" % warm_inside.size())
	# Out of the weather.
	var hall := frame * Vector3(0, f + 1.0, -20.0)
	var deep := frame * Vector3(4.0, low + 1.0, 20.0)
	t.check(frost.sheltered_at(hall) and frost.sheltered_at(deep) and not frost.sheltered_at(outside),
			"inside is sheltered, the apron outside is not")
	raid.weather.start()
	raid.weather.centre = Vector3(hall.x, 0.0, hall.z)
	raid.weather.strength = 1.0
	t.check(raid.weather.strength_at(hall) == 0.0 and raid.weather.strength_at(outside) > 0.5,
			"a whiteout at the hatch never reaches into the hall")
	var glacier := Vector3(MapScript.centre(-200.0), MapScript.floor_at(-200.0), -200.0)
	t.check(frost.cold_at(hall) < frost.cold_at(glacier) and frost.cold_at(deep) > frost.cold_at(hall),
			"the hall is gentler than the glacier head, and it is colder down the Shaft")
	var me := raid.add_player([], {}, "Delver", "delver")
	await t.frames(2)
	raid.tracks.clear()
	var before := raid.tracks.count()
	for i in 30:
		raid._track_mark(me, hall + Vector3(0, 0, i * 0.8), Tracks.Kind.LEFT if i % 2 == 0 else Tracks.Kind.RIGHT, 0.5)
	t.check(raid.tracks.count() == before, "no trail is laid on the hall's floor")
	raid.queue_free()
	await t.frames(2)


## The Coil Galleries and the Descent: open from the Shaft, floored, walkable
## to the Descent's foot, colder the deeper, bitter on the coolant.
static func _deeper(t: Node) -> void:
	print("Engine: the galleries and the Descent")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 4243)
	_wake_engine(raid)
	await t.frames(2)
	var frame := MapScript.engine_frame()
	var g := MapScript.GALLERY_FLOOR
	var step := MapScript.DESCENT_DROP / 3.0
	var bottom := MapScript.DESCENT_FLOOR
	var space := raid.get_world_3d().direct_space_state
	t.check(_ray(space, frame * Vector3(0, g + 2.0, 24.0), frame * Vector3(0, g + 2.0, 44.0)).is_empty(),
			"the Shaft's foot opens east into the galleries")
	t.check(not _ray(space, frame * Vector3(0, g + 2.0, 46.0), frame * Vector3(0, g + 2.0, 71.0)).is_empty(),
			"between the cross halls is rock")
	t.check(_ray(space, frame * Vector3(0, g + 2.0, 104.0), frame * Vector3(0, g + 2.0, 118.0)).is_empty(),
			"the last cross hall opens on the Descent")
	for spot: Array in [[Vector3(0, g, 72.0), "a cross hall"], [Vector3(13.0, g, 70.0), "the north gallery"],
			[Vector3(-8.0, g, 72.0), "the south gallery's dry walk"], [Vector3(21.5, g, 56.0), "a coil alcove"],
			[Vector3(0, g, 116.0), "the Descent's top"], [Vector3(-3.0, g - step, 160.0), "the Descent's east landing"],
			[Vector3(-4.0, g - step * 2.0, 117.0), "the Descent's west landing"], [Vector3(8.0, bottom, 168.0), "the Descent's foot"],
			[Vector3(18.0, g + MapScript.WALKWAY_UP, 76.0), "the north gallery's walkway"]]:
		var top: Vector3 = frame * ((spot[0] as Vector3) + Vector3(0, 3.0, 0))
		var hit := _floor_ray(space, top)
		var floor_y: float = (frame * (spot[0] as Vector3)).y
		t.check(not hit.is_empty() and absf(hit.position.y - floor_y) < 0.3,
				"%s has a floor to stand on (%s)" % [spot[1], "none" if hit.is_empty() else "%.2f off" % (hit.position.y - floor_y)])
	var nav := raid.get_world_3d().navigation_map
	var low := MapScript.HALL_FLOOR - MapScript.SHAFT_DEPTH
	var goal := frame * Vector3(8.0, bottom, 168.0)
	await _wait_for_nav(t, nav, goal, raid)
	var from := NavigationServer3D.map_get_closest_point(nav, frame * Vector3(4.0, low, 20.0))
	var path := NavigationServer3D.map_get_path(nav, from, goal, true)
	t.check(path.size() > 1 and path[path.size() - 1].distance_to(goal) < 2.0,
			"a path runs from the Shaft's foot through the galleries and down the Descent (%d points, ends %.1f m off)"
			% [path.size(), path[path.size() - 1].distance_to(goal) if path.size() > 0 else -1.0])
	var deck := frame * Vector3(18.0, g + MapScript.WALKWAY_UP, 76.0)
	var up_path := NavigationServer3D.map_get_path(nav, NavigationServer3D.map_get_closest_point(nav, frame * Vector3(12.0, g, 60.0)), deck, true)
	t.check(up_path.size() > 1 and up_path[up_path.size() - 1].distance_to(deck) < 1.5,
			"the walkway can be walked up to from the gallery floor")
	var guards: Array = _engine_guards(raid)
	var switch_at := frame * Vector3(MapScript.LIFT_SWITCH.x, bottom, MapScript.LIFT_SWITCH.y)
	var keepers := guards.filter(func(guard: Dictionary) -> bool:
		return (guard.marker as Node3D).global_position.distance_to(switch_at) < 6.0)
	t.check(keepers.size() >= 2, "Wardens keep the lift's switch (%d)" % keepers.size())
	var high := 0
	var deck_y := (frame * Vector3(0, g + 3.0, 0)).y
	for guard: Dictionary in guards:
		var at := (guard.marker as Node3D).global_position
		if at.y > deck_y and MapScript.engine_depth(at) == 1:
			high += 1
	t.check(high >= 1, "and one up on the walkway")
	var per_depth := [0, 0, 0, 0]
	for guard: Dictionary in guards:
		per_depth[MapScript.engine_depth((guard.marker as Node3D).global_position)] += 1
	t.check(per_depth[1] >= 8 and per_depth[2] >= 4, "Wardens hold the galleries and the Descent (%s)" % str(per_depth))
	var foot_y := (frame * Vector3(0, bottom, 160.0)).y
	t.check(frost.void_y < foot_y - 5.0, "the world goes on down past the Descent's foot (void at %.0f)" % frost.void_y)
	await t.frames(30)
	var standing := guards.filter(func(guard: Dictionary) -> bool:
		return guard.bot != null and is_instance_valid(guard.bot) and not (guard.bot as Actor).is_dead)
	t.check(standing.size() == guards.size(), "every guard stands at its post, the deepest too (%d of %d)" % [standing.size(), guards.size()])
	var hall := frame * Vector3(0, MapScript.HALL_FLOOR + 1.0, -20.0)
	var gallery := frame * Vector3(13.0, g + 1.0, 70.0)
	var well := frame * Vector3(8.0, bottom + 1.0, 168.0)
	var channel := frame * Vector3(-13.0, g + 0.5, 70.0)
	var glacier := Vector3(MapScript.centre(-200.0), MapScript.floor_at(-200.0), -200.0)
	t.check(frost.cold_at(hall) < frost.cold_at(gallery) and frost.cold_at(gallery) < frost.cold_at(well),
			"colder the deeper: the hall, the galleries, the Descent")
	t.check(frost.cold_at(channel) > frost.cold_at(glacier) and frost.cold_at(channel) > frost.cold_at(well),
			"wading the coolant is colder than anywhere else")
	t.check(frost.sheltered_at(gallery) and frost.sheltered_at(well), "the galleries and the Descent are sheltered")
	raid.queue_free()
	await t.frames(2)


## The cable lift: dead until someone holds its switch, then it runs for
## everyone and carries whoever waits in a stop to the other one.
static func _lift(t: Node) -> void:
	print("Engine: the cable lift")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 4244)
	await t.frames(2)
	t.check(raid.lifts.has(MapScript.LIFT_ID) and raid.lift_left(MapScript.LIFT_ID) == 0.0,
			"the Engine's lift is found, and starts dead")
	var lift: Dictionary = raid.lifts[MapScript.LIFT_ID]
	var stops: Array = lift.stops
	var high := stops[0] as Node3D if (stops[0] as Node3D).global_position.y > (stops[1] as Node3D).global_position.y else stops[1] as Node3D
	var deep := stops[1] as Node3D if high == stops[0] else stops[0] as Node3D
	t.check(high.global_position.y - deep.global_position.y > 60.0, "it runs from the hall to the Descent's foot")
	var me := raid.add_player([], {}, "Delver", "delver")
	await t.frames(2)
	var sent := []
	raid.lift_changed.connect(func(id: String, left: float) -> void: sent.append([id, left]))
	# Waiting in a dead lift goes nowhere.
	me.global_position = high.global_position
	raid._tick_lifts(frost.lift_wait + 0.5)
	t.check(me.global_position.distance_to(high.global_position) < 0.5, "a dead lift carries nobody")
	# One player alone powers it.
	me.global_position = (lift.power as Node3D).global_position
	raid._tick_lifts(frost.lift_power_time * 0.5)
	t.check(raid.lift_left(MapScript.LIFT_ID) == 0.0, "the switch takes a while to throw")
	raid._tick_lifts(frost.lift_power_time * 0.6)
	t.check(raid.lift_left(MapScript.LIFT_ID) > frost.lift_powered_for - 1.0 and sent.size() == 1 and sent[0][1] > 0.0,
			"one player at the switch powers the lift for everyone, and clients hear of it")
	# It carries you up, and not straight back down.
	me.global_position = deep.global_position + Vector3(0.5, 0, 0)
	raid._tick_lifts(frost.lift_wait * 0.5)
	t.check(me.global_position.y < high.global_position.y - 30.0, "the lift waits a moment before it goes")
	raid._tick_lifts(frost.lift_wait * 0.6)
	t.check(me.global_position.distance_to(high.global_position + Vector3(0.5, 0.1, 0)) < 0.3,
			"and carries a rider to the other stop")
	raid._tick_lifts(frost.lift_wait + 0.5)
	t.check(me.global_position.distance_to(high.global_position) < 1.0, "nobody bounces straight back")
	# It runs down in time.
	raid._tick_lifts(frost.lift_powered_for)
	t.check(raid.lift_left(MapScript.LIFT_ID) == 0.0 and sent.size() == 2 and sent[1][1] == 0.0,
			"the lift runs down after its time, and clients hear of that too")
	t.check(not (raid.map.get_meta("lift_power", {}) as Dictionary).is_empty(), "the map is told what runs")
	# A client's copy follows the server.
	raid.set_lift(MapScript.LIFT_ID, 30.0)
	t.check(raid.lift_left(MapScript.LIFT_ID) == 30.0, "a client copies the lift's power from the server")
	raid.queue_free()
	await t.frames(2)


## The Heart: the chamber, its keeper's two phases, the vault's shares, the
## deep beacon and the keeper's return.
static func _heart(t: Node) -> void:
	print("Engine: the Heart")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 4245)
	await t.frames(2)
	var frame := MapScript.engine_frame()
	var bottom := MapScript.DESCENT_FLOOR
	var c := MapScript.HEART_Z
	var kind := MapScript.HEART_KEEPER
	var space := raid.get_world_3d().direct_space_state
	t.check(MapScript.HEART_RADIUS * 2.0 >= 64.0 and MapScript.HEART_UP >= 30.0,
			"the Heart is a round chamber %.0f m across and %.0f m high" % [MapScript.HEART_RADIUS * 2.0, MapScript.HEART_UP])
	t.check(MapScript.HEART_DOOR >= 9.0, "its door is 9 m wide or more")
	var blocked := []
	for x: float in [-MapScript.HEART_DOOR * 0.5 + 0.6, 0.0, MapScript.HEART_DOOR * 0.5 - 0.6]:
		for y: float in [1.0, MapScript.HEART_DOOR_UP - 1.0]:
			var hit := _ray(space, frame * Vector3(x, bottom + y, 173.5), frame * Vector3(x, bottom + y, c - 26.0))
			if not hit.is_empty():
				blocked.append(MapScript.engine_local(hit.position).snappedf(0.1))
	t.check(blocked.is_empty(), "the Descent's door opens on the Heart, clear its whole width %s" % str(blocked))
	t.check(not _ray(space, frame * Vector3(0, bottom + 2.0, c), frame * Vector3(0, bottom + 2.0, c + MapScript.HEART_RADIUS + 3.0)).is_empty()
			and not _ray(space, frame * Vector3(0, bottom + 20.0, c), frame * Vector3(MapScript.HEART_RADIUS + 3.0, bottom + 20.0, c)).is_empty()
			and not _ray(space, frame * Vector3(0, bottom + 20.0, c - 20.0), frame * Vector3(0, bottom + 20.0, c - MapScript.HEART_RADIUS - 3.0)).is_empty(),
			"and its wall closes round it, over the door too")
	var ledge := MapScript.HEART_RADIUS - MapScript.HEART_LEDGE * 0.5
	var up := MapScript.HEART_BALCONY
	for spot: Array in [[Vector3(0, bottom, c - 8.0), "the Heart's floor"], [Vector3(0, bottom, 180.0), "the way on to it"],
			[Vector3(0, bottom, c + 30.0), "the vault's floor"], [Vector3(0, bottom + up, c + ledge), "the balcony"],
			[Vector3(-ledge * 0.7071, bottom + up, c - ledge * 0.7071), "the balcony over the door's side"],
			[Vector3(30.0, bottom + up, c + 11.0), "a ramp's landing"]]:
		var top: Vector3 = frame * ((spot[0] as Vector3) + Vector3(0, 3.0, 0))
		var hit := _floor_ray(space, top)
		var floor_y: float = (frame * (spot[0] as Vector3)).y
		t.check(not hit.is_empty() and absf(hit.position.y - floor_y) < 0.3,
				"%s has a floor to stand on (%s)" % [spot[1], "none" if hit.is_empty() else "%.2f off" % (hit.position.y - floor_y)])
	var middle := frame * Vector3(0, bottom + 1.0, c - 6.0)
	var well := frame * Vector3(8.0, bottom + 1.0, 168.0)
	t.check(MapScript.in_heart(middle) and MapScript.inside_engine(middle) and MapScript.engine_depth(middle) == 3,
			"the Heart is inside the Engine, its deepest part")
	t.check(frost.sheltered_at(middle) and frost.cold_at(middle) > frost.cold_at(well), "sheltered, and colder than the Descent")
	var nav := raid.get_world_3d().navigation_map
	var goal := frame * Vector3(0, bottom, c - 6.0)
	await _wait_for_nav(t, nav, goal, raid)
	var foot := NavigationServer3D.map_get_closest_point(nav, frame * Vector3(8.0, bottom, 168.0))
	var path := NavigationServer3D.map_get_path(nav, foot, goal, true)
	t.check(path.size() > 1 and path[path.size() - 1].distance_to(goal) < 2.0,
			"a path runs from the Descent's foot into the Heart (%d points)" % path.size())
	var balcony := frame * Vector3(0, bottom + up, c + ledge)
	var climb := NavigationServer3D.map_get_path(nav, NavigationServer3D.map_get_closest_point(nav, goal), balcony, true)
	t.check(climb.size() > 1 and climb[climb.size() - 1].distance_to(balcony) < 1.5,
			"and up a ramp to the balcony")
	# The keeper.
	var found := raid._bosses.filter(func(entry: Dictionary) -> bool:
		return (entry.marker as Node3D).get_meta("boss", "") == kind)
	t.check(found.size() == 1, "the Heart has its keeper")
	if found.is_empty():
		raid.queue_free()
		return
	var boss: Dictionary = found[0]
	var keeper := boss.bot as Actor
	t.check(keeper != null and keeper.display_name == "Heart Warden" and keeper.rear_damage_mult > 1.5
			and keeper.body_height() > 3.5, "the Heart Warden stands there, tall, its back its weak spot")
	t.check(keeper != null and keeper.get_meta("look", "") == "core_colossus",
			"and it looks like a machine of its own, its core bared, not the Sentinel grown taller")
	t.check(keeper.inventory.items.is_empty(), "it carries nothing: its vault pays")
	t.check(int(raid.keepers.get(kind, -1)) == 1 and (raid.map.get_meta("keepers", {}) as Dictionary).get(kind) == 1,
			"it starts standing, and the map is told")
	var beacon: Node3D = null
	for marker in raid.beacons:
		if marker.get_meta("keeper", "") == kind:
			beacon = marker
	t.check(beacon != null and raid.beacon_at(beacon.global_position) == null, "the deep beacon is dark while it stands")
	var me := raid.add_player([], {}, "Delver", "delver")
	var mate := raid.add_player([], {}, "Second", "second")
	var late := raid.add_player([], {}, "Late", "late")
	await t.frames(2)
	for actor: Actor in [me, mate, late]:
		actor.protected_left = 0.0
	me.global_position = beacon.global_position + Vector3(0, 0.1, 0)
	t.check(raid.warmth_at(me) == 0.0, "and gives no warmth")
	me.global_position = frame * Vector3(0, bottom + 0.2, c - 20.0)
	mate.global_position = frame * Vector3(0, bottom + 0.2, 160.0)
	late.global_position = frame * Vector3(0, bottom + 0.2, 150.0)
	# Phase one: Wardens out of the sockets, a few at a time.
	raid._tick_keeper(boss, frost.keeper_socket_first + 0.1)
	var adds: Array = boss.adds
	t.check(adds.size() == 1, "with someone in the Heart, it calls a Warden out of a wall socket")
	if adds.size() == 1:
		var add := adds[0] as Actor
		var by_socket := raid._sockets.any(func(socket: Node3D) -> bool:
			return socket.global_position.distance_to(add.global_position) < 3.0)
		t.check(add.faction == "warden" and by_socket and raid._is_extra(add), "a Warden, at a socket, outside the armies")
	for i in 12:
		raid._tick_keeper(boss, frost.keeper_socket_every + 0.1)
	t.check(adds.size() == frost.keeper_socket_max, "no more than %d out at once for one player" % frost.keeper_socket_max)
	# Phase two: the purges.
	var phases := []
	var lanes := []
	raid.keeper_changed.connect(func(k: String, phase: int) -> void: phases.append([k, phase]))
	raid.purge_changed.connect(func(index: int, state: int) -> void: lanes.append([index, state]))
	keeper.health.health = keeper.health.max_health * 0.4
	raid._tick_keeper(boss, 0.05)
	t.check(phases.size() == 1 and phases[0] == [kind, 2], "below half, the core thaws: its second phase")
	raid._tick_keeper(boss, frost.keeper_purge_first + 0.05)
	var warned := lanes.filter(func(e: Array) -> bool: return e[1] == 1)
	t.check(warned.size() == frost.keeper_purges_at_once, "the pylons' lanes warn first (%d)" % warned.size())
	if not warned.is_empty():
		var lane := raid.purges[int(warned[0][0])]
		var to: Vector3 = lane.get_meta("toward")
		me.global_position = lane.global_position.lerp(to, 0.3) + Vector3(0, 0.1, 0)
		mate.global_position = frame * Vector3(0, bottom + 0.2, c - 28.0)
		var mine := me.health.health
		var theirs := mate.health.health
		raid._tick_keeper(boss, frost.keeper_purge_warn * 0.5)
		t.check(me.health.health == mine, "nothing hurts while a lane only warns")
		raid._tick_keeper(boss, frost.keeper_purge_warn * 0.6)
		t.check(me.health.health < mine and mate.health.health == theirs,
				"then it vents: whoever stands in it is hurt, nobody outside it")
		t.check(lanes.any(func(e: Array) -> bool: return e[1] == 2), "and everyone sees it vent")
		raid._tick_keeper(boss, Raid.PURGE_VENT + 0.1)
		t.check(lanes.filter(func(e: Array) -> bool: return e[1] == 0).size() == warned.size(), "then each lane goes quiet")
	t.check(Raid.in_lane(Vector3(0, 0, 5), Vector3.ZERO, Vector3(0, 0, 10), 4.0)
			and not Raid.in_lane(Vector3(4, 0, 5), Vector3.ZERO, Vector3(0, 0, 10), 4.0)
			and not Raid.in_lane(Vector3(0, 6, 5), Vector3.ZERO, Vector3(0, 0, 10), 4.0),
			"a lane is its floor, its width across, never over it")
	# The fall: one who hurt it from outside, one in the Heart, one neither.
	mate.global_position = frame * Vector3(0, bottom + 0.2, 160.0)
	me.global_position = frame * Vector3(0, bottom + 0.2, c - 20.0)
	var info := DamageInfo.new()
	info.amount = 5.0
	info.source = mate
	raid._on_keeper_hurt(info, boss)
	keeper.kill("test", me)
	raid._tick_bosses(0.1)
	t.check(int(raid.keepers.get(kind, -1)) == 0 and phases[phases.size() - 1] == [kind, 0], "it falls, and clients hear of it")
	var shares: Array = boss.shares
	var labels := shares.map(func(share: LootContainer) -> String: return share.label)
	t.check(shares.size() == 2 and labels.has("Delver's share") and labels.has("Second's share"),
			"the vault opens a share for each who fought it, none for anyone else (%s)" % str(labels))
	me.global_position = beacon.global_position + Vector3(0, 0.1, 0)
	t.check(raid.beacon_at(beacon.global_position) == beacon and raid.warmth_at(me) > 0.0, "the deep beacon lights, and warms")
	var theirs_share: LootContainer = null
	for share: LootContainer in shares:
		if share.label == "Second's share":
			theirs_share = share
	if theirs_share != null:
		var held := theirs_share.items.size()
		theirs_share.interact(me)
		t.check(held > 0 and theirs_share.items.size() == held, "nobody takes another's share")
		var before := mate.inventory.items.size()
		theirs_share.interact(mate)
		t.check(mate.inventory.items.size() == before + held, "its owner takes it all")
	# What a share pays.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var relics := 0
	var blueprints := 0
	var data := true
	var tiers := false
	for i in 1000:
		var roll := frost.roll_vault(kind, rng)
		if not roll.has("upgrade_data"):
			data = false
		for id: String in roll:
			if ItemDB.has_tag(id, "artifact"):
				relics += 1
			if ItemDB.has_tag(id, "blueprint"):
				blueprints += 1
			if id.contains("mk2") or id.contains("mk3"):
				tiers = true
	t.check(data and blueprints > 150 and not tiers, "a share holds upgrade data, often a blueprint, never a crafted Mk")
	var ashfront := Worlds.get_world("ashfront")
	t.check(relics > 0 and relics / 1000.0 < ashfront.warlord_artifact_chance,
			"rarely an artifact (%.1f%%), rarer than an Ashfront warlord's" % (relics / 10.0))
	# It comes back on its own timer, the vault closed and the beacon dark.
	t.check(float(boss.back_in) == MapScript.HEART_RESPAWN and MapScript.HEART_RESPAWN > frost.boss_respawn_time,
			"it comes back on its own, longer timer")
	raid._tick_bosses(MapScript.HEART_RESPAWN + 0.1)
	var back: Variant = boss.bot
	t.check(back != null and is_instance_valid(back) and not (back as Actor).is_dead and int(raid.keepers[kind]) == 1,
			"and wakes again")
	t.check((boss.shares as Array).is_empty() and raid.beacon_at(beacon.global_position) == null,
			"its vault closes and the deep beacon goes dark")
	raid.set_keeper(kind, 0)
	t.check((raid.map.get_meta("keepers", {}) as Dictionary).get(kind) == 0, "a client copies the keeper's phase")
	raid.queue_free()
	await t.frames(2)


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD)
	return space.intersect_ray(query)


## The floor under `top`, through any loot crate standing there: a crate is
## solid (docs/systems/worlds-and-war.md "Collision") but is not the floor.
static func _floor_ray(space: PhysicsDirectSpaceState3D, top: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -6.0, 0), Actor.LAYER_WORLD)
	for i in 4:
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not hit.collider is LootContainer:
			return hit
		query.exclude = query.exclude + [(hit.collider as CollisionObject3D).get_rid()]
	return {}


## The Engine's region is built off the main thread and joins the map some
## frames later: wait until the map has ground where `spot` is, not just any
## region (an earlier world's, or the valley's outside), before asking for a
## path to it. Only once the map holds this raid's regions alone: the last
## check's raid, freed a frame or two ago, can leave its own Engine's region
## at the very same spot for a sync, and a wait that took that for this one
## asked for its path just as it left the map, finding nothing.
static func _wait_for_nav(t: Node, nav: RID, spot: Vector3, raid: Node) -> void:
	# The bake runs on its own thread in real time, which frames run at
	# `--fixed-fps` (as fast as the machine goes) do not measure: a busy
	# machine can take longer than 600 such frames. Wait by the clock.
	var until := Time.get_ticks_msec() + 30000
	# The map answers from its last sync, so the sync must come after the
	# old regions left: count from the first frame they are gone.
	var clean_from := -1
	while Time.get_ticks_msec() < until:
		if clean_from < 0 and _only_regions_of(nav, raid):
			clean_from = NavigationServer3D.map_get_iteration_id(nav)
		if clean_from >= 0 and NavigationServer3D.map_get_iteration_id(nav) > clean_from \
				and NavigationServer3D.map_get_closest_point(nav, spot).distance_to(spot) < 2.0:
			break
		await t.frames(1)
	# And one more sync, so the regions round it are joined too.
	await t.frames(2)


## Whether every region in the map belongs to `raid` (none left from a raid
## freed before it).
static func _only_regions_of(nav: RID, raid: Node) -> bool:
	for region in NavigationServer3D.map_get_regions(nav):
		var owner = instance_from_id(NavigationServer3D.region_get_owner_id(region))
		if owner == null or not is_instance_valid(owner) or not raid.is_ancestor_of(owner):
			return false
	return true


## The Engine's garrison: its guards by their pockets ("engine ...").
static func _engine_guards(raid: Raid) -> Array:
	return raid._guards.filter(func(g: Dictionary) -> bool:
		return str((g.marker as Node3D).get_meta("pocket", "")).begins_with("engine"))


## Nobody is inside to wake the garrison's pockets: wake them all, as a
## player walking through would.
static func _wake_engine(raid: Raid) -> void:
	for key: Variant in raid._pockets:
		if not str(key).begins_with("engine"):
			continue
		var pocket: Dictionary = raid._pockets[key]
		pocket.awake = true
		for i: int in pocket.guards:
			if raid._guards[i].bot == null:
				raid._guards[i].bot = raid._add_guard(raid._guards[i].marker)
