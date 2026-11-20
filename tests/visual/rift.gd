extends RefCounted
## `--rift-only`, a mode `visual_check.gd` finds by itself:
## `-- <output_dir> --rift-only` shoots the Basalt Rift from the Gate Shelf,
## over the Anvil, at the Gate Draft, from the top of a Crown draft onto
## the Crown, and the roster's kinds side by side.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("rift"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	var map: Node3D = raid.map
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	await v._settle(40)
	var shelf := Vector3(map.SHELF_AT.x, map.SHELF_TOP, map.SHELF_AT.y)
	var anvil: Dictionary = map.SITES[1]
	var anvil_top := Vector3(anvil["at"].x, anvil["top"], anvil["at"].y)
	var crown := Vector3(map.CROWN["at"].x, map.CROWN["top"], map.CROWN["at"].y)
	# From the Gate Shelf, north over the rift: the bridges, the mesas, the
	# Crown at the back.
	cam.look_at_from_position(shelf + Vector3(0, 9.0, 16.0), anvil_top + Vector3(0, -14.0, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("rift_shelf.png"))
	# Over the Anvil, its bridges running off to the Stacks and the Shelf.
	cam.look_at_from_position(anvil_top + Vector3(45.0, 40.0, 60.0), anvil_top)
	await v._settle(4)
	await v._shot(out_dir.path_join("rift_anvil.png"))
	# The Gate Draft rising out of the lava beside the Shelf.
	var first: Dictionary = map.VENTS[0]
	var draft := Vector3(first["at"].x, 14.0, first["at"].y)
	cam.look_at_from_position(draft + Vector3(28.0, 8.0, 34.0), draft + Vector3(0.0, 12.0, 0.0))
	await v._settle(4)
	await v._shot(out_dir.path_join("rift_updraft.png"))
	# The Crown from the top of its draft.
	var vent: Dictionary = map.VENTS[5]
	cam.look_at_from_position(Vector3(vent["at"].x, float(vent["top"]) - 4.0, vent["at"].y), crown)
	await v._settle(4)
	await v._shot(out_dir.path_join("rift_crown.png"))
	var ground := func(x: float, z: float) -> Vector3:
		return Vector3(x, map.SHELF_TOP, z)
	# The roster side by side, facing the camera.
	var origin: Vector3 = ground.call(0.0, map.SHELF_AT.y - 6.0)
	var kinds: Array = raid.world.ROSTER.keys()
	var line: Array[Actor] = []
	for i in 40:
		if line.size() == kinds.size():
			break
		var bot := raid.spawn_bot("Kind%d" % i, origin, 1000 + i, false, "rift", 0)
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
	await v._shot(out_dir.path_join("rift_roster.png"))
