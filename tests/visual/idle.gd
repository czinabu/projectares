extends RefCounted
## `--idle-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --idle-only` shoots the player standing still.


## Contact sheets of the player standing still, side on and from the front: one
## row each for empty hands, a gun held low, a gun raised to shoot, and coming
## to a stop from a jog. Frames are spread over a few seconds to show breathing.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.queue_free()
	var player := raid.player
	player.set_physics_process(false)
	await v._settle(10)
	var skin: Node = player.get_node("Skin")
	var gun := -1
	for i in player.weapons.size():
		if player.weapons[i] is Gun and not player.weapons[i].is_sidearm:
			gun = i
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var rows := ["empty", "gun_low", "gun_raised", "stop"]
	for view: String in ["side", "front"]:
		var sheet := Image.create(6 * 320, rows.size() * 360, false, Image.FORMAT_RGBA8)
		for row in rows.size():
			var kind: String = rows[row]
			player.active_weapon_index = -1 if kind == "empty" else gun
			for i in player.weapons.size():
				if player.weapons[i].visual:
					player.weapons[i].visual.visible = i == player.active_weapon_index
			player.cmd.primary = kind == "gun_raised"
			player.velocity = player.global_basis * Vector3(0, 0, -player.walk_speed) if kind == "stop" else Vector3.ZERO
			for k in 60:
				skin._process(1.0 / 60.0)
				await v.get_tree().process_frame
			player.velocity = Vector3.ZERO
			for i in 6:
				for k in (4 if kind == "stop" else 20):
					skin._process(1.0 / 60.0)
					await v.get_tree().process_frame
				var at := player.global_position
				var side := player.global_basis.x if view == "side" else player.global_basis.z
				cam.global_position = at + side * 5.5 + Vector3(0, 0.9, 0)
				cam.look_at(at + Vector3(0, 0.9, 0))
				await RenderingServer.frame_post_draw
				var frame := v.get_viewport().get_texture().get_image()
				var w := frame.get_width()
				var h := frame.get_height()
				var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
				cut.resize(320, 360)
				cut.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(i * 320, row * 360))
		sheet.save_png(out_dir.path_join("idle_%s.png" % view))
		print("saved idle_%s.png" % view)
	player.cmd.primary = false
	raid.queue_free()
