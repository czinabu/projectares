extends RefCounted
## Checks for the Engine's inside (DESIGN.md "The Engine's inside", first
## step): the drum is hollow, the hatch is open, the Drum Hall and the Shaft
## have room for a squad to fight in, a garrison stands guard, and inside is
## out of the weather: no storm, no trail, a gentler cold. Kept in its own
## file and called from the test runner.

const MapScript := preload("res://worlds/frostline/map.gd")


static func run(t: Node) -> void:
	_shape(t)
	await _inside(t)


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
	t.check(guards.size() >= 6 and in_hall.size() == guards.size(),
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
	t.check(engine_caches.size() >= 4, "the hall and the Shaft hold caches of their own (%d)" % engine_caches.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var coils := 0
	for i in 60:
		coils += frost.roll_loot("engine", rng).count("engine_coil")
	t.check(coils > 10, "the Engine's caches pay Engine Coils (%d in 60)" % coils)
	var warm_inside := raid.warmth.filter(func(w: Node3D) -> bool: return MapScript.inside_engine(w.global_position))
	t.check(warm_inside.size() >= 2, "warm pockets inside, the hall's and the Shaft's foot")
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


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD)
	return space.intersect_ray(query)
