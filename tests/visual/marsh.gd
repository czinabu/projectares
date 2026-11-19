extends RefCounted
## `--marsh-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --marsh-only` shoots the Spore Marsh's wildlife side
## by side front and back, close up, a bloater's spore cloud, and a
## fungus forest (DESIGN.md "The Spore Marsh").


## Ashfront's armies by kind, for judging the heavy units by eye
## (DESIGN.md "Heavy units").
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
	player.visible = false
	var ground := func(at: Vector3) -> Vector3:
		return Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z)
	var origin: Vector3 = ground.call(Vector3(0, 0, 150))
	player.global_position = origin
	var forward := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	var line: Array[Actor] = []
	var next_seed := 10
	for kind: String in ["stalker", "shellback", "bloater", "lurker", "keeper", "broodling"]:
		next_seed += 1
		line.append(raid.spawn_bot("Beast%d" % next_seed, origin, next_seed, false, kind, 1))
	next_seed += 1
	line.append(raid.spawn_bot("Matriarch", origin, next_seed, true, "stalker", 2, [], "matriarch"))
	for i in line.size():
		var at: Vector3 = ground.call(origin + forward * 8.0 + side * ((i - (line.size() - 1) * 0.5) * 3.2))
		line[i].global_position = at
		line[i].set_physics_process(false)
		# Facing the camera at the shore.
		line[i].cmd.yaw = PI
		line[i].rotation.y = PI
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 800.0
	raid.add_child(cam)
	cam.current = true
	await v._settle(40)
	var mid: Vector3 = ground.call(origin + forward * 8.0)
	cam.look_at_from_position(ground.call(origin) + Vector3(0, 1.8, 0), mid + Vector3(0, 1.2, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("marsh_beasts_front.png"))
	cam.look_at_from_position(ground.call(mid + forward * 8.0) + Vector3(0, 1.8, 0), mid + Vector3(0, 1.2, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("marsh_beasts_back.png"))
	for i in line.size() - 1:
		var beast := line[i]
		var at := beast.global_position
		var reach := maxf(beast.body_height() / 1.4, 0.8)
		cam.look_at_from_position(at + Vector3(2.2, 1.4, -2.4) * reach, at + Vector3(0, 0.8, 0) * reach)
		await v._settle(4)
		await v._shot(out_dir.path_join("marsh_%s_close.png" % beast.faction))
	# A bloater bursts.
	raid.burst_cloud(line[2].global_position + Vector3(0, 0.6, 0), {"radius": 4.5, "damage": 0.0, "seconds": 8.0,
			"kind": "spores"}, "bloater")
	cam.look_at_from_position(mid + Vector3(0, 2.5, 9.0), line[2].global_position + Vector3(0, 1.0, 0))
	await v._settle(50)
	await v._shot(out_dir.path_join("marsh_cloud.png"))
	# A fungus forest from its edge, and the basin from over the shore.
	var forest: Vector2 = raid.map.FORESTS[2]["at"]
	var edge: Vector3 = ground.call(Vector3(forest.x, 0, forest.y + 55.0))
	cam.look_at_from_position(edge + Vector3(0, 2.0, 0), Vector3(forest.x, edge.y + 6.0, forest.y))
	await v._settle(4)
	await v._shot(out_dir.path_join("marsh_forest.png"))
	cam.look_at_from_position(origin + Vector3(0, 30.0, 30.0), Vector3(0, 0, -40))
	await v._settle(4)
	await v._shot(out_dir.path_join("marsh_basin.png"))
	# A brood keeper at its hive with its broodlings, under the caps where
	# the air shuts in.
	var hive: Vector3 = raid.map._hives[2]
	var to_heart := (Vector3(forest.x, hive.y, forest.y) - hive).normalized()
	var keeper := raid.spawn_bot("Keeper", hive, 31, false, "keeper", 1)
	keeper.global_position = ground.call(hive + to_heart * 4.0)
	keeper.set_physics_process(false)
	keeper.cmd.yaw = atan2(to_heart.x, to_heart.z)
	keeper.rotation.y = keeper.cmd.yaw
	for i in 3:
		var pup := raid.spawn_bot("Brood%d" % i, hive, 40 + i, false, "broodling", 1)
		pup.global_position = ground.call(hive + to_heart * 6.5 + Vector3(to_heart.z, 0, -to_heart.x) * (i - 1) * 1.8)
		pup.set_physics_process(false)
		pup.cmd.yaw = keeper.cmd.yaw
		pup.rotation.y = keeper.cmd.yaw
	var mood := raid.map.get_node_or_null("WarMood")
	var eye: Vector3 = ground.call(hive + to_heart * 14.0) + Vector3(0, 1.8, 0)
	cam.look_at_from_position(eye, keeper.global_position + Vector3(0, 1.4, 0))
	await v._settle(4)
	if mood != null:
		mood.close_shown = 1.0
	await v._settle(4)
	await v._shot(out_dir.path_join("marsh_hive.png"))
	# The same forest's air looked through, deep under the caps.
	cam.look_at_from_position(Vector3(forest.x, 0, forest.y) + Vector3(0, ground.call(Vector3(forest.x, 0, forest.y)).y + 2.0, 0),
			Vector3(forest.x + 40.0, 2.0, forest.y + 10.0))
	await v._settle(4)
	await v._shot(out_dir.path_join("marsh_forest_inside.png"))
	if mood != null:
		mood.close_shown = 0.0
	# A lurker in its pool: lying low, then up out of the water.
	var lurker := raid.spawn_bot("Lurker", origin, 51, false, "lurker", 1)
	var pool := Vector3.INF
	for marker in raid.map.get_tree().get_nodes_in_group("spawn_guard"):
		if str(marker.get_meta("faction", "")) == "lurker":
			pool = marker.global_position
			break
	if pool.is_finite():
		lurker.global_position = pool
		lurker.set_physics_process(false)
		var look := pool + Vector3(0, 0.3, 0)
		cam.look_at_from_position(Vector3(pool.x + 5.0, 1.6, pool.z + 4.0), look)
		lurker.cmd.yaw = atan2(6.0, 5.0)
		lurker.rotation.y = lurker.cmd.yaw
		lurker.crouch = 1.0
		await v._settle(30)
		await v._shot(out_dir.path_join("marsh_lurker_hidden.png"))
		# Up out of the pool as it lunges (the shot lifts it to the shallows).
		lurker.crouch = 0.0
		lurker.global_position.y = maxf(pool.y, -0.4)
		await v._settle(30)
		await v._shot(out_dir.path_join("marsh_lurker_up.png"))
	raid.queue_free()
