extends RefCounted
## `--whiteout-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --whiteout-only` shows a Frostline whiteout: the
## valley clear, the blizzard coming down it, the thick of it in first and
## third person (the body leaning into the wind, seen from the side) and
## spindrift streaming off a rim.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	const MapScript := preload("res://worlds/frostline/map.gd")
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("frostline"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	var ground := func(at: Vector3) -> Vector3:
		return Vector3(at.x, float(raid.map.call("ground_height", at.x, at.z)), at.z)
	# On the floor below the Narrows, looking up the valley (toward -z).
	var z0 := 120.0
	var origin: Vector3 = ground.call(Vector3(MapScript.centre(z0), 0.0, z0))
	var forward := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	var line: Array[Actor] = [player]
	for bot in raid.bots:
		if line.size() < 5 and not bot.is_dead and bot.get_meta("boss", "") == "":
			line.append(bot)
		else:
			bot.global_position += Vector3(0, -400, 0)
	var distances: Array[float] = [3.0, 15.0, 30.0, 45.0, 70.0]
	var lateral: Array[float] = [0.6, -3.0, 2.0, -2.5, 3.0]
	for i in line.size():
		line[i].global_position = ground.call(origin + forward * distances[i] + side * lateral[i])
		line[i].rotation.y = PI if i == 0 else 0.0
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	var eye: Vector3 = ground.call(origin + forward * 4.5) + Vector3(0, 1.65, 0)
	var focus: Vector3 = ground.call(origin + forward * 35.0) + Vector3(0, 1.3, 0)
	cam.look_at_from_position(eye, focus)
	await v._settle(40)
	await v._shot(out_dir.path_join("whiteout_1_clear.png"))
	# The blizzard coming down the valley, seen from the shelf.
	var weather := raid.weather
	weather.start()
	weather.velocity = Vector3(0, 0, 0.2)
	weather.life = 100000.0
	weather.age = 1000.0
	weather.strength = 1.0
	weather.centre = Vector3(MapScript.centre(-120.0), 0.0, -120.0)
	var perch: Vector3 = origin + Vector3(0, 7.0, 0)
	cam.look_at_from_position(perch, weather.centre + Vector3(0, 30, 0))
	await v._settle(30)
	await v._shot(out_dir.path_join("whiteout_2_coming.png"))
	# The thick of it, first person.
	weather.centre = Vector3(origin.x, 0.0, origin.z) + forward * 20.0
	Look.weather_follow = 100.0
	cam.look_at_from_position(eye, focus)
	await v._settle(10)
	for air: GPUParticles3D in raid.find_children("*", "GPUParticles3D", true, false):
		if air.get_parent().name == "Air":
			air.preprocess = 6.0
			air.restart()
	await v._settle(30)
	await v._shot(out_dir.path_join("whiteout_3_first.png"))
	# Third person, over the shoulder.
	cam.look_at_from_position(player.global_position - forward * 3.4 + side * 0.9 + Vector3(0, 2.0, 0), focus)
	await v._settle(10)
	await v._shot(out_dir.path_join("whiteout_4_third.png"))
	# The body leaning into the wind, in profile: the wind blows down the
	# valley (+z), the player faces up it into the wind, the camera beside.
	player.rotation.y = 0.0
	player.cmd.yaw = 0.0
	var at := player.global_position
	cam.look_at_from_position(at + Vector3(-3.5, 1.1, 0.0), at + Vector3(0, 1.0, 0))
	await v._settle(80)
	await v._shot(out_dir.path_join("whiteout_5_lean.png"))
	# Spindrift streaming off the east rim.
	# The camera in the storm's soft edge on the east side of the floor, the
	# rim close by and deeper in.
	weather.centre = Vector3(MapScript.centre(z0 - 75.0), 0.0, z0 - 75.0)
	var rim := MapScript.rim_point(z0 - 5.0, 1.0)
	var rim_at: Vector3 = ground.call(Vector3(rim.x, 0.0, rim.y))
	var below: Vector3 = ground.call(Vector3(MapScript.centre(z0 + 15.0) + MapScript.half_width(z0 + 15.0) * 0.5, 0.0, z0 + 15.0))
	cam.look_at_from_position(below + Vector3(0, 1.8, 0), rim_at + Vector3(0, 6, 0))
	await v._settle(80)
	await v._shot(out_dir.path_join("whiteout_6_spindrift.png"))
	Look.weather_follow = 0.35
	raid.queue_free()
	await v._settle(4)
