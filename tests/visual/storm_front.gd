extends RefCounted
## `--storm-front-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --storm-front-only [ashfront|frostline]` shoots a storm
## front coming in (DESIGN.md "Weather: ash storms") from the ground in
## every world with weather, or only the one named: far off, close, at its
## edge, and from a rise. What to look for: no hard outline or top rim
## anywhere, billows breaking the skyline, soft where it meets the ground,
## and the haze thickening (never a plane) as the camera walks in.
## With `--cost` it also prints what drawing the front costs at each shot:
## the viewport's GPU time over 60 frames with it shown and hidden.


static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var worlds: Array[String] = ["ashfront", "frostline"]
	for name in worlds.duplicate():
		if args.has(name):
			worlds = [name]
	# The fog follows the storm at once, not over seconds.
	Look.weather_follow = 100.0
	for id in worlds:
		await _world(v, out_dir, id, args.has("--cost"))
	Look.weather_follow = 0.35


static func _world(v: Node, out_dir: String, id: String, cost: bool) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world(id), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position += Vector3(0, -400, 0)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	var ground := func(at: Vector3) -> Vector3:
		return Vector3(at.x, float(raid.map.call("ground_height", at.x, at.z)), at.z)
	# Out from where the player starts toward the middle of the map, clear of
	# the gate, so the storm has room.
	var forward := -Vector3(player.global_position.x, 0.0, player.global_position.z).normalized()
	if forward.length_squared() < 0.5:
		forward = Vector3.FORWARD
	var origin: Vector3 = ground.call(player.global_position + forward * 45.0)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	var weather := raid.weather
	weather.start()
	weather.velocity = -forward * 0.01
	weather.life = 100000.0
	weather.age = 1000.0
	weather.strength = 1.0
	var eye: Vector3 = origin + Vector3(0, 1.7, 0)
	# How far the storm's edge is from the camera in each shot.
	var gaps := {"far": 260.0, "near": 110.0, "edge": 30.0, "in": -25.0}
	for shot: String in gaps:
		var gap: float = gaps[shot]
		weather.centre = Vector3(origin.x, 0.0, origin.z) + forward * (weather.radius + gap)
		cam.look_at_from_position(eye, eye + forward * 50.0 + Vector3(0, 6.0, 0))
		await v._settle(30)
		await v._shot(out_dir.path_join("%s_front_%s.png" % [id, shot]))
		if cost:
			await _cost(v, raid, "%s %s" % [id, shot])
	weather.centre = Vector3(origin.x, 0.0, origin.z) + forward * (weather.radius + 200.0)
	cam.look_at_from_position(eye - forward * 10.0 + Vector3(0, 30.0, 0), weather.centre + Vector3(0, 20.0, 0))
	await v._settle(30)
	await v._shot(out_dir.path_join("%s_front_rise.png" % id))
	raid.queue_free()
	await v._settle(4)


## Prints the GPU time a frame takes with the front shown and hidden.
static func _cost(v: Node, raid: Raid, label: String) -> void:
	var view: Node = raid.find_child("WeatherView", true, false)
	var wall: Node3D = view.get_node("Wall")
	# Held still, so it does not show the front again between frames.
	view.set_process(false)
	var port := v.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(port, true)
	var times := {}
	for shown in [true, false]:
		var total := 0.0
		for i in 70:
			wall.visible = shown
			await v.get_tree().process_frame
			if i >= 10:
				total += RenderingServer.viewport_get_measured_render_time_gpu(port)
		times[shown] = total / 60.0
	wall.visible = true
	view.set_process(true)
	print("cost %s: front %.2f ms, without %.2f ms, the front %.2f ms" % [label, times[true], times[false], times[true] - times[false]])
