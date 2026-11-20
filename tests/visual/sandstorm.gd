extends RefCounted
## `--sandstorm-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --sandstorm-only` shows a Dune Sea sandstorm (DESIGN.md
## "The Dune Sea (part two)"): one coming over a wreck field, the thick of
## it at the landing, and a wreck field it buried beside one it left open.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("dunes"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	var ground := func(x: float, z: float) -> Vector3:
		return Vector3(x, raid.map.call("ground_height", x, z), z)
	var map: Node3D = raid.map
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	await v._settle(40)
	# A storm coming over an open wreck field.
	var open := 0
	while raid.is_field_buried(open):
		open += 1
	var wreck: Vector2 = map.WRECKS[open]["at"]
	var weather := raid.weather
	weather.start()
	weather.velocity = Vector3(0, 0, 0.2)
	weather.life = 100000.0
	weather.age = 1000.0
	weather.strength = 1.0
	weather.centre = Vector3(wreck.x, 0.0, wreck.y - 250.0)
	cam.look_at_from_position(ground.call(wreck.x + 20.0, wreck.y + 50.0) + Vector3(0, 6.0, 0),
			ground.call(wreck.x, wreck.y - 120.0) + Vector3(0, 30.0, 0))
	await v._settle(30)
	await v._shot(out_dir.path_join("sandstorm_1_coming.png"))
	# The thick of it, at the landing, far from any wreck field.
	var at: Vector3 = ground.call(0.0, map.LANDING_Z - 30.0)
	weather.centre = Vector3(at.x, 0.0, at.z - 20.0)
	Look.weather_follow = 100.0
	cam.look_at_from_position(at + Vector3(0, 1.65, 0), ground.call(0.0, map.LANDING_Z - 80.0) + Vector3(0, 1.5, 0))
	await v._settle(10)
	for air: GPUParticles3D in raid.find_children("*", "GPUParticles3D", true, false):
		if air.get_parent().name == "Air":
			air.preprocess = 6.0
			air.restart()
	await v._settle(30)
	await v._shot(out_dir.path_join("sandstorm_2_thick.png"))
	Look.weather_follow = 0.35
	weather.kind = ""
	weather.strength = 0.0
	await v._settle(20)
	# A buried field from above: the sand where its hulks were.
	var buried := 0
	while not raid.is_field_buried(buried):
		buried += 1
	wreck = map.WRECKS[buried]["at"]
	cam.look_at_from_position(ground.call(wreck.x + 45.0, wreck.y + 45.0) + Vector3(0, 28.0, 0),
			ground.call(wreck.x, wreck.y))
	await v._settle(6)
	await v._shot(out_dir.path_join("sandstorm_3_buried.png"))
	raid.set_field_buried(buried, false)
	await v._settle(6)
	await v._shot(out_dir.path_join("sandstorm_4_uncovered.png"))
	raid.queue_free()
	await v._settle(4)
