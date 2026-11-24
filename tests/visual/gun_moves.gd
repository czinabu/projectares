extends RefCounted
## `--gun-moves-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --gun-moves-only` films a long gun through a string of
## holds (at ease, a jog, aiming, shooting from the hip, a sprint, a
## summoned power weapon aimed), from three-quarters ahead and from the
## eyes, as numbered frames under `gun_moves/<view>/` to make a GIF of.
## `MOVES_GUN` picks the gun (rifle_carbine).


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var id: String = OS.get_environment("MOVES_GUN") if OS.has_environment("MOVES_GUN") else "rifle_carbine"
	for view: String in ["third", "first"]:
		var raid := Raid.new()
		v.add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, [id, "blade_scrap", "plate_light"])
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -500, 0)
		var p := raid.player
		var gun: Gun = null
		for i in p.weapons.size():
			if p.weapons[i] is Gun and p.weapons[i].item_id == id:
				gun = p.weapons[i]
				p.active_weapon_index = i
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		await v._settle(40)
		p.set_physics_process(false)
		controller.set_physics_process(false)
		controller.view_mode = PlayerController.ViewMode.FIRST if view == "first" else PlayerController.ViewMode.THIRD
		controller.pitch = -0.08
		p.cmd.pitch = controller.pitch
		p.cmd.yaw = controller.yaw
		var cam := Camera3D.new()
		cam.fov = 40.0
		raid.add_child(cam)
		cam.current = view == "third"
		controller.camera.current = view == "first"
		var dir := out_dir.path_join("gun_moves/%s" % view)
		DirAccess.make_dir_recursive_absolute(dir)
		# [what, velocity as a share of walk speed, sprint, shooting, aiming, seconds]
		var steps := [
			["at ease", Vector3.ZERO, false, false, false, 1.2],
			["jog", Vector3(0, 0, -1), false, false, false, 1.2],
			["aim", Vector3.ZERO, false, false, true, 1.2],
			["hip fire", Vector3.ZERO, false, true, false, 1.0],
			["run and shoot", Vector3(0, 0, -1), false, true, false, 1.0],
			["sprint", Vector3(0, 0, -1.6), true, false, false, 1.2],
			["at ease", Vector3.ZERO, false, false, false, 0.8],
		]
		var frame := 0
		var tick := 0
		for step: Array in steps:
			var t := 0.0
			while t < float(step[5]):
				# Kept in hand: the start sits in a safe zone, which would holster it.
				for i in p.weapons.size():
					if p.weapons[i] == gun:
						p.active_weapon_index = i
				p.velocity = p.global_basis * ((step[1] as Vector3) * p.walk_speed)
				p.cmd.sprint = step[2]
				p.cmd.primary = step[3]
				p.cmd.secondary = step[4]
				gun._aiming = step[4]
				# The camera keeps pace from three-quarters ahead and to the gun side.
				var at := p.global_position + Vector3(0, 1.3, 0)
				cam.global_position = at + p.global_basis * Vector3(1.1, 0.2, -1.5)
				cam.look_at(at)
				await v.get_tree().process_frame
				var dt := v.get_process_delta_time()
				t += dt
				# Moved by hand while physics is off, so the stride runs.
				p.global_position += p.velocity * dt
				tick += 1
				if tick % 2 == 0:
					await RenderingServer.frame_post_draw
					var img := v.get_viewport().get_texture().get_image()
					img.resize(img.get_width() / 2, img.get_height() / 2)
					img.save_png(dir.path_join("%04d.png" % frame))
					frame += 1
		p.cmd.primary = false
		print("saved gun_moves/%s (%d frames)" % [view, frame])
		controller.queue_free()
		raid.queue_free()
		await v._settle(3)
