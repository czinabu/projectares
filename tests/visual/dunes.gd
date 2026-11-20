extends RefCounted
## `--dunes-only`, a mode `visual_check.gd` finds by itself:
## `-- <output_dir> --dunes-only` shoots the Dune Sea from the landing, over
## a salvage yard, a wreck field and the deep sea, the roster's kinds side by
## side, and the haul: someone carrying a salvage crate to a loaded rover.


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
	var landing: Vector3 = ground.call(0.0, map.LANDING_Z)
	cam.look_at_from_position(landing + Vector3(0, 2.0, 8.0), ground.call(0.0, 0.0) + Vector3(0, 4.0, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("dunes_landing.png"))
	var site: Vector2 = map.SITES[1]["at"]
	cam.look_at_from_position(ground.call(site.x + 40.0, site.y + 50.0) + Vector3(0, 30.0, 0),
			ground.call(site.x, site.y))
	await v._settle(4)
	await v._shot(out_dir.path_join("dunes_site.png"))
	cam.look_at_from_position(ground.call(map.BOSS_AT.x, map.BOSS_AT.y + 70.0) + Vector3(0, 40.0, 0),
			ground.call(map.BOSS_AT.x, map.BOSS_AT.y))
	await v._settle(4)
	await v._shot(out_dir.path_join("dunes_core.png"))
	# The roster side by side, facing the camera.
	var origin: Vector3 = ground.call(0.0, map.LANDING_Z - 20.0)
	var kinds: Array = raid.world.ROSTER.keys()
	var line: Array[Actor] = []
	for i in 40:
		if line.size() == kinds.size():
			break
		var bot := raid.spawn_bot("Kind%d" % i, origin, 1000 + i, false, "dunes", 0)
		if line.any(func(b: Actor) -> bool: return b.get_meta("kind", "") == bot.get_meta("kind", "")):
			raid._remove_actor(bot)
			continue
		line.append(bot)
	for i in line.size():
		line[i].global_position = ground.call((i - (line.size() - 1) * 0.5) * 3.0, origin.z)
		line[i].set_physics_process(false)
		line[i].rotation.y = PI
	cam.look_at_from_position(origin + Vector3(0, 1.8, 8.0), origin + Vector3(0, 1.1, 0))
	await v._settle(6)
	await v._shot(out_dir.path_join("dunes_roster.png"))
	for bot in line:
		raid._remove_actor(bot)
	# A wreck field from above.
	var wreck: Vector2 = map.WRECKS[2]["at"]
	cam.look_at_from_position(ground.call(wreck.x + 45.0, wreck.y + 45.0) + Vector3(0, 28.0, 0),
			ground.call(wreck.x, wreck.y))
	await v._settle(4)
	await v._shot(out_dir.path_join("dunes_wrecks.png"))
	# The haul: a rover with three crates aboard, and someone carrying the
	# fourth to it.
	wreck = map.WRECKS[5]["at"]
	var spot: Vector3 = ground.call(wreck.x + 30.0, wreck.y + 6.0)
	var rover := raid.spawn_vehicle("rover_warden", spot + Vector3(0, 0.4, 0), 0.6)
	await v._settle(20)
	var near: Array[SalvageCrate] = []
	for crate in raid.crates:
		if crate.global_position.distance_to(Vector3(wreck.x, crate.global_position.y, wreck.y)) < 40.0:
			near.append(crate)
	var cargo: Array = rover.get("cargo")
	for i in mini(3, near.size()):
		cargo[i] = near[i]
		near[i].place(rover, i)
	player.visible = true
	player.set_physics_process(true)
	var walk: Vector3 = ground.call(spot.x + 3.5, spot.z + 4.0)
	player.global_position = walk
	player.cmd.yaw = atan2(-(spot.x - walk.x), -(spot.z - walk.z))
	if near.size() > 3:
		raid.lift_crate(player, near[3])
	await v._settle(20)
	player.set_physics_process(false)
	cam.look_at_from_position(walk + Vector3(4.5, 2.4, 3.5), spot + Vector3(0, 0.8, 0))
	await v._settle(6)
	await v._shot(out_dir.path_join("dunes_haul.png"))
	cam.look_at_from_position(spot + Vector3(-1.5, 2.6, 6.5), spot + Vector3(0, 0.9, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("dunes_haul_rover.png"))
