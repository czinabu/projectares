extends RefCounted
## `--gait-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --gait-only` shoots the legs: run, sprint, strafe, slide.


## Contact sheets of the player's legs, side on and from the front, holding
## still while the skin is fed a velocity: one row of frames per way of moving.
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
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var moves := [
		["jog", Vector3(0, 0, -player.walk_speed), 0.0],
		["sprint", Vector3(0, 0, -player.sprint_speed), 0.0],
		["strafe", Vector3(-player.walk_speed, 0, 0), 0.0],
		["diagonal", Vector3(-4.2, 0, -4.2), 0.0],
		["backpedal", Vector3(0, 0, player.walk_speed), 0.0],
		["slide", Vector3(0, 0, -player.slide_speed), 1.0],
		["crouch", Vector3.ZERO, -1.0],
		["crouch_walk", Vector3(0, 0, -player.crouch_speed), -1.0],
	]
	for view: String in ["side", "front"]:
		var sheet := Image.create(6 * 320, moves.size() * 360, false, Image.FORMAT_RGBA8)
		for row in moves.size():
			var move: Array = moves[row]
			player.slide_left = 0.5 if move[2] > 0.0 else 0.0
			player.slide_low = maxf(move[2], 0.0)
			# A negative weight is the crouch.
			player.crouch = 1.0 if move[2] < 0.0 else 0.0
			player.crouched = move[2] < 0.0
			player.velocity = player.global_basis * move[1]
			for i in 6:
				for k in 5:
					skin._process(1.0 / 60.0)
					await v.get_tree().process_frame
				var at := player.global_position
				var side := player.global_basis.x if view == "side" else -player.global_basis.z
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
		sheet.save_png(out_dir.path_join("gait_%s.png" % view))
		print("saved gait_%s.png" % view)
	raid.queue_free()
