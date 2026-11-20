extends RefCounted
## `--rain-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --rain-only` shows a Spore Marsh rain storm (DESIGN.md
## "The Spore Marsh (part two, built)"): the shore dry, the storm coming
## over the water, and the thick of it in first and third person.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("marsh"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -400, 0)
		bot.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	var ground := func(at: Vector3) -> Vector3:
		return Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z)
	var origin: Vector3 = ground.call(Vector3(0, 0, 150))
	var forward := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	player.global_position = ground.call(origin + forward * 3.0 + side * 0.6)
	player.rotation.y = 0.0
	var line: Array[Actor] = []
	var next_seed := 20
	for kind: String in ["stalker", "shellback", "stalker"]:
		next_seed += 1
		line.append(raid.spawn_bot("Beast%d" % next_seed, origin, next_seed, false, kind, 1))
	var distances: Array[float] = [14.0, 28.0, 45.0]
	for i in line.size():
		line[i].global_position = ground.call(origin + forward * distances[i] + side * (2.5 if i % 2 == 0 else -2.5))
		line[i].set_physics_process(false)
		line[i].cmd.yaw = PI
		line[i].rotation.y = PI
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	var eye: Vector3 = ground.call(origin) + Vector3(0, 1.65, 0)
	var focus: Vector3 = ground.call(origin + forward * 30.0) + Vector3(0, 1.3, 0)
	cam.look_at_from_position(eye, focus)
	await v._settle(40)
	await v._shot(out_dir.path_join("rain_1_dry.png"))
	# The storm coming over the water.
	var weather := raid.weather
	weather.start()
	weather.velocity = Vector3(0, 0, 0.2)
	weather.life = 100000.0
	weather.age = 1000.0
	weather.strength = 1.0
	weather.centre = Vector3(origin.x, 0.0, origin.z) + forward * 260.0
	cam.look_at_from_position(eye + Vector3(0, 4.0, 0), weather.centre + Vector3(0, 30, 0))
	await v._settle(30)
	await v._shot(out_dir.path_join("rain_2_coming.png"))
	# The thick of it, first person.
	weather.centre = Vector3(origin.x, 0.0, origin.z) + forward * 20.0
	Look.weather_follow = 100.0
	player.visible = false
	cam.look_at_from_position(player.global_position + Vector3(0, 1.65, 0), focus)
	await v._settle(10)
	for air: GPUParticles3D in raid.find_children("*", "GPUParticles3D", true, false):
		if air.get_parent().name == "Air":
			air.preprocess = 6.0
			air.restart()
	await v._settle(30)
	await v._shot(out_dir.path_join("rain_3_first.png"))
	# Third person, over the shoulder.
	player.visible = true
	cam.look_at_from_position(player.global_position - forward * 3.4 + side * 0.9 + Vector3(0, 2.0, 0), focus)
	await v._settle(10)
	await v._shot(out_dir.path_join("rain_4_third.png"))
	Look.weather_follow = 0.35
	raid.queue_free()
	await v._settle(4)
