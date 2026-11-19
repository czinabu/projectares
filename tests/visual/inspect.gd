extends RefCounted
## `--inspect-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --inspect-only` shoots the inspect key at work: the
## rifle, the sidearm, the blade and a toy vehicle looked over, at points
## through the turn, in first person, third person and from the front.


## The inspect key: each thing in hand brought in and turned, at points
## through the look over (`ActionPose.INSPECT_TURNS`), seen from the eyes,
## over the shoulder and from the right. Saves `inspect.png`, and each shot
## full size under `inspect/`.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "pistol_service"])
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	raid.state_for(raid.player).stowed.append("bike_scrapper")
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await v._settle(30)
	p.set_physics_process(false)
	controller.set_physics_process(false)
	controller.pitch = -0.05
	p.cmd.pitch = controller.pitch
	p.cmd.yaw = controller.yaw
	var pose := ActionPose.of(p)
	var slot := {}
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			slot["blade"] = i
		elif p.weapons[i] is Gun and p.weapons[i].is_sidearm:
			slot["pistol"] = i
		elif p.weapons[i] is Gun:
			slot["rifle"] = i
	var outside := Camera3D.new()
	outside.fov = 40.0
	raid.add_child(outside)
	var rows := ["rifle", "pistol", "blade", "toy"]
	# `INSPECT_ROWS=rifle,toy` shoots only those.
	if OS.has_environment("INSPECT_ROWS"):
		rows = Array(OS.get_environment("INSPECT_ROWS").split(","))
	# [seconds into the look over, camera]: 0 first person, 1 third, 2 from
	# the right (the left of the spawn is walled in).
	var cols := [[0.0, 0], [0.9, 0], [2.3, 0], [2.85, 0], [0.9, 1], [2.3, 1], [0.9, 2], [2.3, 2]]
	var size := Vector2i(320, 240)
	var sheet := Image.create(cols.size() * size.x, rows.size() * size.y, false, Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("inspect"))
	for row in rows.size():
		var kind: String = rows[row]
		p.active_weapon_index = slot.get(kind, -1)
		controller.held_toy = "bike_scrapper" if kind == "toy" else ""
		p.toy_in_hand = controller.held_toy
		p.cmd.inspect = false
		for k in 40:
			await v.get_tree().process_frame
		for col in cols.size():
			var at_time: float = cols[col][0]
			var cam: int = cols[col][1]
			controller.view_mode = PlayerController.ViewMode.FIRST if cam == 0 else PlayerController.ViewMode.THIRD
			outside.current = cam == 2
			controller.camera.current = cam != 2
			p.cmd.inspect = at_time > 0.0
			for k in 40:
				pose.inspect_clock = at_time
				await v.get_tree().process_frame
			if cam == 2:
				var at := p.global_position
				outside.global_position = at + p.global_basis * Vector3(2.6, 1.6, -0.6)
				outside.look_at(at + Vector3(0, 1.35, 0))
			pose.inspect_clock = at_time
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			frame.save_png(out_dir.path_join("inspect/%s_%d_%s.png" % [kind, int(at_time * 100), ["first", "third", "right"][cam]]))
			var w := frame.get_width()
			var h := frame.get_height()
			var cut_w := h * size.x / size.y
			var cut := frame.get_region(Rect2i((w - cut_w) / 2, 0, cut_w, h))
			cut.resize(size.x, size.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, row * size.y))
		print("shot %s" % kind)
	sheet.save_png(out_dir.path_join("inspect.png"))
	print("saved inspect.png")
	raid.queue_free()
