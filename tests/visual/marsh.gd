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
	for kind: String in ["stalker", "shellback", "bloater"]:
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
	for i in 3:
		var beast := line[i]
		var at := beast.global_position
		cam.look_at_from_position(at + Vector3(2.2, 1.4, -2.4), at + Vector3(0, 0.8, 0))
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
	raid.queue_free()
