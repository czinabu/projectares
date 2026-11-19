extends RefCounted
## `--tracks-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --tracks-only` shows Frostline's snow with a trail of
## footprints and a bike's wheel tracks across it, fresh to old, and a
## warm beacon.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("frostline"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	raid.player.set_physics_process(false)
	raid.player.visible = false
	var x0 := 40.0
	var z0 := 200.0
	var ground := func(x: float, z: float) -> Vector3:
		return Vector3(x, float(raid.map.call("ground_height", x, z)), z)
	# A walker crossing at an angle, the oldest prints furthest off.
	for k in 30:
		var at: Vector3 = ground.call(x0 - 8.0 + k * 0.55, z0 + 6.0 - k * 0.6)
		var heading := Vector3(0.55, 0, -0.6).normalized()
		var side := heading.cross(Vector3.UP) * (0.13 if k % 2 else -0.13)
		var spot: Vector3 = ground.call(at.x + side.x, at.z + side.z)
		raid.tracks.add(spot, atan2(-heading.x, -heading.z), Tracks.Kind.RIGHT if k % 2 else Tracks.Kind.LEFT,
				raid.clock - (30 - k) * 6.0)
	# A bike's wheel tracks across the other way.
	for k in 14:
		var at: Vector3 = ground.call(x0 + 6.0 - k * 1.4, z0 - 4.0 + k * 0.2)
		raid.tracks.add(at, atan2(1.4, -0.2), Tracks.Kind.TREAD, raid.clock - k * 4.0)
	var camera := Camera3D.new()
	camera.far = 900.0
	raid.add_child(camera)
	camera.make_current()
	var look: Vector3 = ground.call(x0, z0)
	camera.global_position = look + Vector3(-1.5, 2.2, 5.0)
	camera.look_at(look)
	await v._settle(30)
	await v._shot(out_dir.path_join("tracks_close.png"))
	camera.global_position = look + Vector3(-9.0, 12.0, 20.0)
	camera.look_at(look)
	await v._settle(10)
	await v._shot(out_dir.path_join("tracks_far.png"))
	var beacon: Node3D = raid.beacons[0]
	camera.global_position = beacon.global_position + Vector3(-12.0, 5.0, 12.0)
	camera.look_at(beacon.global_position + Vector3(0, 2.5, 0))
	await v._settle(20)
	await v._shot(out_dir.path_join("beacon.png"))
	raid.queue_free()
