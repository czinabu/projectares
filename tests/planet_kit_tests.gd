extends RefCounted
## Checks for the planet kit (DESIGN.md "Planet kit"): every type is whole,
## its ground is the same height for the same point on any thread, the
## horizon ring stays a fixed size whatever its reach, and none of it adds
## anything a headless server would draw. Kept in its own file and called
## from the test runner.


static func run(t: Node) -> void:
	print("Planet kit: types, ground, horizon, headless")
	var ids := PlanetTypes.ids()
	t.check(ids.size() >= 6, "six planet types or more")
	for id in ids:
		var type := PlanetTypes.get_type(id)
		t.check(type != null and type.id == id and type.display_name != "", "%s is a whole type" % id)
		t.check(not type.calm.is_empty() and not type.storm.is_empty() and not type.terrain.is_empty()
				and not type.ground.is_empty() and not type.sky.is_empty(), "%s has sky, light, ground and storm" % id)
		for layer in Planet.LAYERS:
			var folder := String(type.surfaces.get(layer, "missing"))
			if folder == "missing":
				t.check(false, "%s names a surface for its %s layer" % [id, layer])
				continue
			if folder != "":
				for map in ["Color", "NormalGL"]:
					var path := Planet.surface_path(folder, map)
					t.check(ResourceLoader.exists(path) and load(path) is Texture2D,
							"%s's %s surface %s has its %s map" % [id, layer, folder, map])
		var kinds := ["boulder", "slab", "spire", "shard", "crystal", "stalk"]
		for entry: Dictionary in type.props:
			t.check(entry.get("kind", "") in kinds, "%s scatters only kinds the kit makes" % id)

	# A world takes a planet's rule defaults and can still set its own.
	var world := WorldDef.new()
	t.check(world.planet == "" and world.planet_type() == null and is_equal_approx(world.surface_grip(Vector3.ZERO), 1.0),
			"a world stands on no planet by default and keeps dry ground")
	world.take_planet("glacier")
	var ice := PlanetTypes.get_type("glacier")
	t.check(world.planet == "glacier" and world.planet_type() != null and world.planet_type().id == "glacier",
			"take_planet names the world's planet")
	t.check(is_equal_approx(world.cold, ice.rules["cold"]) and is_equal_approx(world.shot_carry, ice.rules["shot_carry"])
			and is_equal_approx(world.surface_grip(Vector3(40.0, 0.0, -12.0)), ice.rules["surface_grip"]),
			"and gives it the planet's cold, shot carry and grip")
	world.cold = 3.0
	t.check(is_equal_approx(world.cold, 3.0), "a world's own setting after it wins")
	world.take_planet("nowhere")
	t.check(world.planet == "glacier", "an unknown planet changes nothing")

	# Meridian stands on the Salt Flat but races at full grip.
	var meridian: WorldDef = load("res://worlds/meridian/world.gd").new()
	t.check(meridian.planet == "saltflat" and is_equal_approx(meridian.surface_grip(Vector3(30.0, 0.0, 40.0)), 1.0),
			"Meridian stands on the Salt Flat and keeps full grip for its race profiles")
	var meridian_map: Node3D = meridian.create_map()
	var handed: PlanetType = meridian_map.get("planet")
	t.check(handed != null and handed.id == "saltflat", "and hands its map the planet")
	meridian_map.free()

	# Frostline stands on the Glacier and keeps its own cold, carry and grip.
	var frost: WorldDef = load("res://worlds/frostline/world.gd").new()
	var frost_type := PlanetTypes.get_type("glacier")
	t.check(frost.planet == "glacier", "Frostline stands on the Glacier")
	t.check(not is_equal_approx(frost.cold, float(frost_type.rules["cold"]))
			and is_equal_approx(frost.shot_carry, 2.0),
			"and keeps its own cold and still-air carry over the planet's defaults")
	t.check(frost.surface_grip(Vector3(0.0, 40.0, 0.0)) != frost.planet_grip,
			"and its own snow and ice grip")
	var frost_map: Node3D = frost.create_map()
	var frost_handed: PlanetType = frost_map.get("planet")
	t.check(frost_handed != null and frost_handed.id == "glacier", "and hands its map the planet")
	frost_map.free()

	# The same ground for the same point, whichever copy asks and on any thread.
	var recipe: Dictionary = PlanetTypes.get_type("glacier").terrain
	var a := PlanetTerrain.new(recipe, 7)
	var b := PlanetTerrain.new(recipe, 7)
	var same := true
	for i in 50:
		var x := -300.0 + i * 12.3
		same = same and is_equal_approx(a.height_at(x, x * 0.7), b.height_at(x, x * 0.7))
	t.check(same, "a recipe and seed give one ground")
	var on_thread := [0.0]
	var thread := Thread.new()
	thread.start(func() -> void: on_thread[0] = PlanetTerrain.new(recipe, 7).height_at(41.0, -77.0))
	thread.wait_to_finish()
	t.check(is_equal_approx(on_thread[0], a.height_at(41.0, -77.0)), "and works it out off the main thread the same")
	var other := PlanetTerrain.new(recipe, 8)
	t.check(not is_equal_approx(other.height_at(41.0, -77.0), a.height_at(41.0, -77.0)), "a new seed is new ground")

	# The field is kept playable: its rim rises past it, its middle stays low.
	var ash := PlanetTerrain.new(PlanetTypes.get_type("ashland").terrain, 3)
	t.check(ash.height_at(0.0, 360.0) > ash.height_at(0.0, 0.0) + 15.0, "ground rises past the field's edge")
	var floor_type := PlanetTypes.get_type("saltflat")
	var salt := PlanetTerrain.new(floor_type.terrain, 3)
	var lowest := INF
	for i in 40:
		lowest = minf(lowest, salt.height_at(i * 9.0 - 180.0, 30.0))
	t.check(lowest >= float(floor_type.terrain["floor"]) - 0.01, "a floor fills low ground flat")

	# The horizon: one mesh of fixed size, never collision or a shadow.
	var type := PlanetTypes.get_type("dunes")
	var ring := Planet.horizon(type, PlanetTerrain.new(type.terrain, 1), 320.0)
	var verts: int = ring.mesh.surface_get_array_len(0)
	t.check(verts < 30000, "the horizon ring stays under 30,000 vertices (%d)" % verts)
	t.check(ring.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and ring.get_child_count() == 0,
			"and casts no shadow and has no collision")
	ring.free()

	# Headless: no sky, no props, no weather; only the plain sun.
	if not Look.enabled:
		var map := Node3D.new()
		t.add_child(map)
		Planet.atmosphere(map, type)
		PlanetProps.scatter(map, type, func(_x: float, _z: float) -> float: return 0.0, 100.0, 1)
		t.check(Planet.weather(map, "rain") == null, "no weather headless")
		var kinds_made: Array[String] = []
		for child in map.get_children():
			kinds_made.append(child.get_class())
		t.check(kinds_made == ["DirectionalLight3D"], "headless a planet adds only the sun (%s)" % [kinds_made])
		map.free()
