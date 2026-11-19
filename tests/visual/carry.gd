extends RefCounted
## `--carry-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --carry-only` shoots a rifle and a pistol carried on
## the move: jog, sprint, strafe, slide and shooting on the run, from the
## side, the front and the eyes.


## A gun carried on the move, one sheet per gun (`carry_rifle.png`,
## `carry_pistol.png`): a row per way of moving (jog, sprint, strafe, slide,
## shooting on the run), and columns from the side at two points in the
## stride, from the front, from three-quarters behind, and from the eyes.
## `VIEW_GUN` and `VIEW_SIDEARM` pick the guns. Full-size shots go under
## `carry/`.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	var kit := [OS.get_environment("VIEW_GUN") if OS.has_environment("VIEW_GUN") else "rifle_carbine",
			"blade_scrap", OS.get_environment("VIEW_SIDEARM") if OS.has_environment("VIEW_SIDEARM") else "pistol_service",
			"plate_light"]
	raid.start(Worlds.get_world("ashfront"), 42, kit)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
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
	controller.pitch = -0.1
	p.cmd.pitch = controller.pitch
	p.cmd.yaw = controller.yaw
	var skin: Node = p.get_node("Skin")
	var outside := Camera3D.new()
	outside.fov = 40.0
	raid.add_child(outside)
	var moves := [
		["jog", Vector3(0, 0, -p.walk_speed), false],
		["sprint", Vector3(0, 0, -p.sprint_speed), false],
		["strafe", Vector3(-p.walk_speed, 0, 0), false],
		["slide", Vector3(0, 0, -p.slide_speed), false],
		["shoot_run", Vector3(0, 0, -p.walk_speed), true],
		["crouch_walk", Vector3(0, 0, -p.crouch_speed), false],
		["crouch_aim", Vector3.ZERO, true],
	]
	var size := Vector2i(320, 360)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("carry"))
	for which: String in ["rifle", "pistol"]:
		for i in p.weapons.size():
			var g := p.weapons[i] as Gun
			if g != null and g.is_sidearm == (which == "pistol"):
				p.active_weapon_index = i
		var sheet := Image.create(5 * size.x, moves.size() * size.y, false, Image.FORMAT_RGBA8)
		for row in moves.size():
			var move: Array = moves[row]
			var sliding: bool = move[0] == "slide"
			var hold := func() -> void:
				p.velocity = p.global_basis * (move[1] as Vector3)
				p.slide_left = 0.5 if sliding else 0.0
				p.slide_low = 1.0 if sliding else 0.0
				var low: bool = (move[0] as String).begins_with("crouch")
				p.cmd.crouch = low
				p.crouched = low
				p.crouch = 1.0 if low else 0.0
				p.cmd.secondary = move[0] == "crouch_aim"
				p.cmd.primary = move[2]
			for col in 5:
				var first := col == 4
				controller.view_mode = PlayerController.ViewMode.FIRST if first else PlayerController.ViewMode.THIRD
				outside.current = not first
				controller.camera.current = first
				for k in (50 if col == 0 else 9):
					hold.call()
					await v.get_tree().process_frame
				var at := p.global_position
				var spots := [p.global_basis.x * 4.5, p.global_basis.x * 4.5, -p.global_basis.z * 4.5,
						p.global_basis * Vector3(2.2, 0.6, 3.2)]
				if not first:
					outside.global_position = at + (spots[col] as Vector3) + Vector3(0, 1.0, 0)
					outside.look_at(at + Vector3(0, 1.0, 0))
				hold.call()
				await RenderingServer.frame_post_draw
				var frame := v.get_viewport().get_texture().get_image()
				frame.save_png(out_dir.path_join("carry/%s_%s_%d.png" % [which, move[0], col]))
				var w := frame.get_width()
				var h := frame.get_height()
				var cut_h := h if first else h * 3 / 4
				var cut_w := cut_h * size.x / size.y
				var cut := frame.get_region(Rect2i((w - cut_w) / 2, (h - cut_h) / 2, cut_w, cut_h))
				cut.resize(size.x, size.y)
				cut.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, row * size.y))
			print("shot %s %s" % [which, move[0]])
		p.cmd.primary = false
		sheet.save_png(out_dir.path_join("carry_%s.png" % which))
		print("saved carry_%s.png" % which)
	raid.queue_free()
