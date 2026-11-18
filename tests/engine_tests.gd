extends RefCounted
## Checks for the Engine's inside (DESIGN.md "The Engine's inside"): the drum
## is hollow, the hatch is open, the Drum Hall, the Shaft, the Coil Galleries
## and the Descent have room for a squad to fight in and a way through, a
## garrison stands guard, the cable lift is powered by one player and carries
## everyone, and inside is out of the weather: no storm, no trail, a cold that
## grows with depth and bites on the coolant. Kept in its own file and called
## from the test runner.

const MapScript := preload("res://worlds/frostline/map.gd")


static func run(t: Node) -> void:
	_shape(t)
	await _inside(t)
	await _deeper(t)
	await _lift(t)


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
		var hit := _ray(space, top, top + Vector3(0, -6.0, 0))
		var floor_y: float = (frame * (spot[0] as Vector3)).y
		t.check(not hit.is_empty() and absf(hit.position.y - floor_y) < 0.3, "%s has a floor to stand on" % spot[1])
	# Someone can walk from the hatch to the Shaft's foot.
	# The region is built off the main thread: wait until the map has it.
	var nav := raid.get_world_3d().navigation_map
	for i in 600:
		if NavigationServer3D.map_get_iteration_id(nav) > 0 \
				and NavigationServer3D.map_get_closest_point(nav, Vector3(0, 0, 250)) != Vector3.ZERO:
			break
		await t.frames(1)
	var from := NavigationServer3D.map_get_closest_point(nav, frame * Vector3(-MapScript.ENGINE_RADIUS - 5.0, f, MapScript.HATCH_Z))
	var goal := frame * Vector3(4.0, low, 20.0)
	var path := NavigationServer3D.map_get_path(nav, from, goal, true)
	t.check(path.size() > 1 and path[path.size() - 1].distance_to(goal) < 2.0,
			"a path runs from the hatch, through the hall and down the Shaft (%d points)" % path.size())
	# The garrison.
	var guards: Array = raid._guards
	var in_hall := guards.filter(func(g: Dictionary) -> bool:
		return MapScript.inside_engine((g.marker as Node3D).global_position))
	t.check(guards.size() >= 18 and in_hall.size() == guards.size(),
			"a garrison of Wardens stands guard inside (%d)" % guards.size())
	var first: Actor = guards[0].bot
	t.check(first != null and first.faction == "warden" and raid.is_guard(first) and raid._is_extra(first),
			"a guard is a Warden outside the armies")
	var army := raid.bots.filter(func(b: Actor) -> bool: return not raid._is_extra(b))
	t.check(army.size() == frost.bot_count, "and the valley keeps its own army besides (%d)" % army.size())
	first.health.apply_damage(DamageInfo.make(99999.0, null, "test"))
	await t.frames(2)
	raid._tick_guards(0.1)
	t.check(guards[0].bot == null and guards[0].back_in > 0.0, "a guard brought down comes back in time")
	raid._tick_guards(frost.guard_respawn_time + 1.0)
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
			[Vector3(-4.0, g - step * 2.0, 117.0), "the Descent's west landing"], [Vector3(8.0, bottom, 168.0), "the Descent's foot"]]:
		var top: Vector3 = frame * ((spot[0] as Vector3) + Vector3(0, 3.0, 0))
		var hit := _ray(space, top, top + Vector3(0, -6.0, 0))
		var floor_y: float = (frame * (spot[0] as Vector3)).y
		t.check(not hit.is_empty() and absf(hit.position.y - floor_y) < 0.3,
				"%s has a floor to stand on (%s)" % [spot[1], "none" if hit.is_empty() else "%.2f off" % (hit.position.y - floor_y)])
	var nav := raid.get_world_3d().navigation_map
	for i in 600:
		if NavigationServer3D.map_get_iteration_id(nav) > 0 \
				and NavigationServer3D.map_get_closest_point(nav, Vector3(0, 0, 250)) != Vector3.ZERO:
			break
		await t.frames(1)
	var low := MapScript.HALL_FLOOR - MapScript.SHAFT_DEPTH
	var from := NavigationServer3D.map_get_closest_point(nav, frame * Vector3(4.0, low, 20.0))
	var goal := frame * Vector3(8.0, bottom, 168.0)
	var path := NavigationServer3D.map_get_path(nav, from, goal, true)
	t.check(path.size() > 1 and path[path.size() - 1].distance_to(goal) < 2.0,
			"a path runs from the Shaft's foot through the galleries and down the Descent (%d points, ends %.1f m off)"
			% [path.size(), path[path.size() - 1].distance_to(goal) if path.size() > 0 else -1.0])
	var guards: Array = raid._guards
	var per_depth := [0, 0, 0]
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


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD)
	return space.intersect_ray(query)
