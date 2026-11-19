extends RefCounted
## `--weather-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --weather-only` shoots an ash storm (DESIGN.md
## "Weather: ash storms"): clear air, the wall coming in, and the thick of
## it in first and third person.


## An ash storm by eye: the same spot in clear air and in the thick of the
## storm (first and third person), and the wall seen coming from a rise.
## Bots stand at 15, 30, 45 and 70 m: in the storm the first is clear, the
## next a shape, then faint, and the last gone (Caleb's pick).
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	var gate: Node3D = raid.outposts[0]
	var forward := -Vector3(gate.global_position.x, 0.0, gate.global_position.z).normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var ground := func(at: Vector3) -> Vector3:
		return Vector3(at.x, float(raid.map.call("ground_height", at.x, at.z)), at.z)
	var origin: Vector3 = ground.call(gate.global_position + forward * 70.0)
	var line: Array[Actor] = [player]
	for bot in raid.bots:
		if line.size() < 5 and not bot.is_dead:
			line.append(bot)
		else:
			bot.global_position += Vector3(0, -400, 0)
	var distances: Array[float] = [3.0, 15.0, 30.0, 45.0, 70.0]
	var lateral: Array[float] = [0.6, -3.0, 2.0, -2.5, 3.0]
	for i in line.size():
		line[i].global_position = ground.call(origin + forward * distances[i] + side * lateral[i])
		line[i].rotation.y = atan2(forward.x, forward.z) + (PI if i > 0 else 0.0)
	player.rotation.y = atan2(-forward.x, -forward.z)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	raid.war.cooling = 0.0
	raid.war.intensity = 0.35
	var mood: Node = raid.map.get_node("WarMood")
	mood.follow = 100.0
	var eye: Vector3 = ground.call(origin + forward * 4.5) + Vector3(0, 1.65, 0)
	var focus: Vector3 = ground.call(origin + forward * 35.0) + Vector3(0, 1.3, 0)
	cam.look_at_from_position(eye, focus)
	await v._settle(40)
	await v._shot(out_dir.path_join("weather_1_clear.png"))
	# The storm far off, coming in: seen from a rise.
	var weather := raid.weather
	weather.start()
	weather.velocity = -forward * 0.01
	weather.life = 100000.0
	weather.age = 1000.0
	weather.strength = 1.0
	weather.centre = origin + forward * 260.0 + side * 40.0
	weather.centre.y = 0.0
	cam.look_at_from_position(origin - forward * 6.0 + Vector3(0, 22.0, 0), weather.centre + Vector3(0, 10, 0))
	await v._settle(30)
	await v._shot(out_dir.path_join("weather_2_coming.png"))
	# The thick of it.
	weather.centre = Vector3(origin.x, 0.0, origin.z) + forward * 20.0
	Look.weather_follow = 100.0
	cam.look_at_from_position(eye, focus)
	await v._settle(10)
	for air: GPUParticles3D in raid.find_children("*", "GPUParticles3D", true, false):
		if air.get_parent().name == "Air":
			air.preprocess = 6.0
			air.restart()
	await v._settle(30)
	await v._shot(out_dir.path_join("weather_3_storm_first.png"))
	cam.look_at_from_position(player.global_position - forward * 3.4 + side * 0.9 + Vector3(0, 2.0, 0), focus)
	await v._settle(10)
	await v._shot(out_dir.path_join("weather_4_storm_third.png"))
	Look.weather_follow = 0.35
	raid.queue_free()
	await v._settle(4)
