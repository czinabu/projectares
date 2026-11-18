extends RefCounted
## Checks for Frostline's whiteouts (DESIGN.md "Frostline", step 5): the
## shared weather as blizzards that run the length of the valley, with
## spindrift off its edges and gusts that come and go. Kept in its own file
## and called from the test runner.


static func run(t: Node) -> void:
	_settings(t)
	_paths(t)
	_ridges(t)
	await _storm(t)


static func _settings(t: Node) -> void:
	print("Whiteout: the world's settings")
	var frost := Worlds.get_world("frostline")
	t.check(frost.weather_kind == "snow" and frost.weather_name == "Whiteout",
			"Frostline's storms are whiteouts")
	t.check(frost.weather_sight < 1.0 and frost.weather_cold > 1.0 and frost.weather_gust > 0.0
			and frost.weather_wipes_tracks,
			"a whiteout cuts sight, bites colder, gusts and fills in the trails")
	t.check(frost.shot_carry * frost.weather_carry <= 1.0,
			"the wind swallows the still air's far-carrying shots (%.2f)" % [frost.shot_carry * frost.weather_carry])
	t.check(bool(Look.weather_kit("snow").get("drift", false)), "snow storms tear spindrift off edges")


static func _paths(t: Node) -> void:
	print("Whiteout: down the valley")
	var frost := Worlds.get_world("frostline")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var along := true
	var down := 0
	const RUNS := 400
	for i in RUNS:
		var path := frost.weather_path(rng)
		var from: Vector3 = path[0]
		var to: Vector3 = path[1]
		# Both ends past the valley's, one at each end, and it keeps to the
		# middle of the valley as it crosses.
		var span := absf(to.z - from.z)
		if signf(from.z) == signf(to.z) or span < 600.0 + frost.weather_radius * 2.0 - 1.0 \
				or absf(from.x) > 40.0 or absf(to.x) > 40.0:
			along = false
		if from.z < to.z:
			down += 1
	t.check(along, "every whiteout runs the length of the valley, end to end")
	var share := float(down) / RUNS
	t.check(share > 0.6 and share < 0.9, "most come down off the glacier, some up from the sea (%.2f)" % share)


static func _ridges(t: Node) -> void:
	print("Whiteout: spindrift edges")
	const MapScript := preload("res://worlds/frostline/map.gd")
	var frost := Worlds.get_world("frostline")
	var map: Node3D = frost.create_map()
	t.add_child(map)
	var ridges: PackedVector3Array = map.call("weather_ridges")
	var high := true
	for point in ridges:
		if point.y < MapScript.floor_at(point.z) + MapScript.SHELF * 0.6:
			high = false
	t.check(ridges.size() > 100 and high,
			"the map offers its rim crests and shelf lips as edges for spindrift (%d)" % ridges.size())
	map.queue_free()


static func _storm(t: Node) -> void:
	print("Whiteout: in the thick of one")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 93)
	var weather := raid.weather
	t.check(not weather.active() and weather.next_in > 0.0, "the valley starts clear, a whiteout on its way")
	weather.start()
	t.check(weather.kind == "snow" and absf(weather.velocity.x) < absf(weather.velocity.z),
			"a whiteout starts at one end and blows along the valley")
	var at := Vector3(5.0, 0.0, 40.0)
	weather.centre = at
	weather.age = frost.weather_ramp * 2.0
	weather.strength = 1.0
	t.check(is_equal_approx(weather.cold_at(at), frost.weather_cold)
			and is_equal_approx(weather.sight_at(at), frost.weather_sight),
			"in its heart the cold bites twice as hard and sight halves")
	var outside := at + Vector3(0, 0, frost.weather_radius + 20.0)
	t.check(is_equal_approx(weather.cold_at(outside), 1.0) and WeatherView.gust_now(weather, outside, 3.0) == 0.0,
			"out of it, nothing changes and nothing gusts")
	var low := 1.0
	var most := 0.0
	var clock := 0.0
	while clock < 20.0:
		var g := WeatherView.gust_now(weather, at, clock)
		low = minf(low, g)
		most = maxf(most, g)
		clock += 0.1
	t.check(most - low > 0.3 and most <= 1.0 and low >= 0.0,
			"the wind comes in gusts and lulls, never one even rate (%.2f to %.2f)" % [low, most])
	raid.queue_free()
	await t.frames(2)
