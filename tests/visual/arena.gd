extends RefCounted
## `--arena-only`, a mode `visual_check.gd` finds by itself.


## The arena from the stands, during an exhibition bout, with its overlay.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var arena := Arena.new()
	v.add_child(arena)
	arena.call_time = 1.0
	arena.countdown_time = 0.5
	arena.exhibition_delay = 0.2
	arena.start_solo(["rifle_carbine", "blade_scrap", "plate_light"])
	var controller := PlayerController.new()
	controller.setup(arena.player)
	arena.add_child(controller)
	var hud := Hud.new()
	hud.setup(arena, controller)
	arena.add_child(hud)
	var overlay: CanvasLayer = preload("res://core/arena/arena_hud.gd").new()
	overlay.setup(arena)
	arena.add_child(overlay)
	# Look down into the pit from where you stand.
	var to_center := -arena.player.global_position
	controller.yaw = atan2(-to_center.x, -to_center.z)
	controller.pitch = 0.1
	await v._settle(60)
	await v._shot(out_dir.path_join("arena_calling.png"))
	# A bookmaker's booth in the stands, from its spot and then in use.
	var booth: Node3D = v.get_tree().get_nodes_in_group("arena_booth")[0]
	var stood := arena.player.global_position
	arena.player.global_position = booth.global_position + Vector3(0, 0.1, 0)
	var to_booth: Vector3 = (booth.get_node("Screen") as Node3D).global_position - booth.global_position
	controller.yaw = atan2(-to_booth.x, -to_booth.z)
	controller.pitch = 0.0
	await v._settle(30)
	await v._shot(out_dir.path_join("arena_booth.png"))
	overlay.open_booth(booth)
	hud.visible = false
	arena.player.hand.visible = false
	await v._settle(40)
	await v._shot(out_dir.path_join("arena_booth_screen.png"))
	overlay.close_booth()
	hud.visible = true
	arena.player.hand.visible = true
	arena.player.global_position = stood
	controller.yaw = atan2(-to_center.x, -to_center.z)
	controller.pitch = -0.35
	await v._settle(200)
	await v._shot(out_dir.path_join("arena_fight.png"))
	controller.view_mode = PlayerController.ViewMode.THIRD
	await v._settle(30)
	await v._shot(out_dir.path_join("arena_third_person.png"))
	# The floor's layout: from high over the stands, from the rim, from the
	# middle of the floor, and from a fighter's tunnel.
	var camera := Camera3D.new()
	camera.fov = 70.0
	arena.add_child(camera)
	camera.make_current()
	hud.visible = false
	overlay.visible = false
	for view: Array in [["arena_overview", Vector3(0, 48, 34), Vector3(0, 0, 0)],
			["arena_rim", Vector3(-22, 9, 22), Vector3(4, 2, -4)],
			["arena_floor", Vector3(0, 1.7, 17), Vector3(0, 3, 0)],
			["arena_tunnel", Vector3(-Arena.ArenaVenue.GATE_DISTANCE - 2.0, 1.7, 0), Vector3(0, 2, 0)],
			["arena_stands", Vector3(10, 6.5, 23), Vector3(-6, 2, -4)],
			["arena_board", Vector3(4, 1.7, 9), Vector3(0, 18, 0)]]:
		camera.look_at_from_position(view[1], view[2])
		await v._settle(10)
		await v._shot(out_dir.path_join("%s.png" % view[0]))
		print("%s: %d draw calls, %d objects" % [view[0],
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	camera.queue_free()
