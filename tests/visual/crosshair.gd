extends RefCounted
## `--crosshair-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --crosshair-only` shoots the crosshair in each of its
## states, in third person (top row) and first person (bottom row): still,
## spraying, aimed, an enemy under it, out of range, empty, reloading, a hit,
## a head, plates breaking and a kill. Saves `crosshair.png` (the middle of each frame, enlarged)
## and the full frames under `crosshair/`.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "pistol_service", "frame_trooper"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	var p := raid.player
	p.protected_left = 0.0
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await v._settle(30)
	p.set_physics_process(false)
	p._draw_weapon(p.weapon_for_key(1))
	await v._settle(20)
	controller.yaw = v.open_heading(p, 60.0) if v.has_method("open_heading") else controller.yaw
	controller.pitch = -0.05
	var mark: Variant = hud.crosshair
	var gun := p.get_active_weapon() as Gun
	var states := ["still", "spray", "aimed", "enemy", "far", "empty", "reload", "hit", "head", "break", "kill"]
	var crop := Vector2i(200, 140)
	var scale := 2
	var cell := crop * scale
	var sheet := Image.create(states.size() * cell.x, 2 * cell.y, false, Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("crosshair"))
	for row in 2:
		controller.view_mode = PlayerController.ViewMode.THIRD if row == 0 else PlayerController.ViewMode.FIRST
		for col in states.size():
			var state: String = states[col]
			gun._bloom = 0.0
			gun._aiming = false
			gun._aim_in = 0.0
			gun._reload_left = 0.0
			gun.ammo_in_mag = gun.mag_size
			mark._probe_wait = 0.0
			mark.probe_interval = 0.08
			for k in 24:
				match state:
					"spray":
						gun._bloom = gun.max_bloom
						mark._kicked = mark.kick * 2.0
					"aimed":
						gun._aiming = true
						gun._aim_in = 1.0
					"enemy", "far":
						mark._probe_wait = 99.0
						mark.probe_distance = 20.0 if state == "enemy" else 400.0
						mark.probe_hostile = true
					"empty":
						gun.ammo_in_mag = 0
					"reload":
						gun._reload_left = gun.reload_time * 0.4
				# A software renderer's frames are long enough to miss a flash: a
				# hit mark is held a third of the way through (snapped in, not fading).
				var kinds := {"hit": "hit", "head": "head", "break": "armor_break", "kill": "kill"}
				if k == 22 and kinds.has(state):
					hud._hit_marker.flash(kinds[state])
					hud._hit_marker._left = hud._hit_marker._duration * 0.7
					hud._hit_marker.set_process(false)
				await v.get_tree().process_frame
			await RenderingServer.frame_post_draw
			hud._hit_marker.set_process(true)
			hud._hit_marker._left = 0.0
			var frame := v.get_viewport().get_texture().get_image()
			frame.save_png(out_dir.path_join("crosshair/%s_%s.png" % [["third", "first"][row], state]))
			var mid := Vector2i(frame.get_width(), frame.get_height()) / 2
			var cut := frame.get_region(Rect2i(mid - crop / 2, crop))
			cut.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, cell), Vector2i(col * cell.x, row * cell.y))
			print("crosshair %s %s: %s gap %.1f" % [["third", "first"][row], state, mark.state, mark.gap])
	sheet.save_png(out_dir.path_join("crosshair.png"))
	print("saved crosshair.png")
	raid.queue_free()
