extends RefCounted
## `--clip-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --clip-only` shoots the upper body close up with a gun
## held each way (aimed, up at the hip, carried still, strafing, sprinting),
## from the gun side, from above and from the front, to see where the gun
## and the body meet. `CLIP_IDS` picks the guns (rifle_carbine,power_helion).


## One sheet per gun (`clip_<id>.png`): a row per hold, columns from the gun
## side, from above, from the front and from the off side.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var ids := ["rifle_carbine", "power_helion"]
	if OS.has_environment("CLIP_IDS"):
		ids = Array(OS.get_environment("CLIP_IDS").split(","))
	var moves := [
		["aim", Vector3.ZERO, false, true],
		["hip", Vector3.ZERO, true, false],
		["still", Vector3.ZERO, false, false],
		["strafe", Vector3(-1, 0, 0), false, false],
		["jog", Vector3(0, 0, -1), false, false],
	]
	var size := Vector2i(300, 300)
	# `CLIP_AIM_ONLY`: only the aim, closer in on the shoulder.
	var close := OS.has_environment("CLIP_AIM_ONLY")
	if close:
		moves = [moves[0]]
	for id: String in ids:
		var raid := Raid.new()
		v.add_child(raid)
		var power := ItemDB.has_tag(id, "power")
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine" if power else id, "blade_scrap", "plate_light"])
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -500, 0)
		var p := raid.player
		if power:
			Loadout.set_power(p, id)
		for i in p.weapons.size():
			if p.weapons[i].item_id == id:
				p.active_weapon_index = i
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		await v._settle(40)
		p.set_physics_process(false)
		controller.set_physics_process(false)
		controller.view_mode = PlayerController.ViewMode.THIRD
		controller.pitch = -0.1
		p.cmd.pitch = controller.pitch
		p.cmd.yaw = controller.yaw
		var gun: Gun = null
		for w in p.weapons:
			if w is Gun and w.item_id == id:
				gun = w
		var cam := Camera3D.new()
		cam.fov = 35.0
		raid.add_child(cam)
		cam.current = true
		var sheet := Image.create(4 * size.x, moves.size() * size.y, false, Image.FORMAT_RGBA8)
		for row in moves.size():
			var move: Array = moves[row]
			var hold := func() -> void:
				for i in p.weapons.size():
					if p.weapons[i] == gun:
						p.active_weapon_index = i
				p.velocity = p.global_basis * ((move[1] as Vector3) * p.walk_speed)
				p.cmd.primary = move[2]
				p.cmd.secondary = move[3]
				gun._aiming = move[3]
			for k in 70:
				hold.call()
				await v.get_tree().process_frame
			var chest := p.global_position + Vector3(0, 1.4, 0)
			var spots := [p.global_basis * Vector3(1.4, 0.1, -0.3), p.global_basis * Vector3(0.05, 1.5, -0.25),
					p.global_basis * Vector3(0.2, 0.1, -1.4), p.global_basis * Vector3(-1.4, 0.1, -0.3)]
			if close:
				# Gun side, from above and behind the shoulder, from ahead
				# of the shoulder, and from behind.
				chest = p.global_position + Vector3(0, 1.45, 0) + p.global_basis.x * 0.1
				spots = [p.global_basis * Vector3(0.7, 0.05, -0.1), p.global_basis * Vector3(0.25, 0.6, 0.45),
						p.global_basis * Vector3(0.45, 0.1, -0.6), p.global_basis * Vector3(0.1, 0.25, 0.8)]
			if OS.has_environment("CLIP_WIDE"):
				# `CLIP_WIDE`: the whole body, to see where a gun hangs.
				chest = p.global_position + Vector3(0, 1.0, 0)
				for i in spots.size():
					spots[i] = (spots[i] as Vector3) * 2.2
			for col in 4:
				cam.global_position = chest + (spots[col] as Vector3)
				cam.look_at(chest, p.global_basis.z if col == 1 else Vector3.UP)
				for k in 2:
					hold.call()
					await v.get_tree().process_frame
				await RenderingServer.frame_post_draw
				var frame := v.get_viewport().get_texture().get_image()
				var w := frame.get_width()
				var h := frame.get_height()
				var cut := frame.get_region(Rect2i((w - h) / 2, 0, h, h))
				cut.resize(size.x, size.y)
				cut.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, row * size.y))
		p.cmd.primary = false
		sheet.save_png(out_dir.path_join("clip_%s.png" % id))
		print("saved clip_%s.png" % id)
		controller.queue_free()
		raid.queue_free()
		await v._settle(3)
