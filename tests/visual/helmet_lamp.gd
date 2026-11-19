extends RefCounted
## `--helmet-lamp-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --helmet-lamp-only` shoots the helmet lamp lit, with the
## sun turned down so the beam shows: from the front left, over the
## shoulder, from the eyes, and with the helmet on the hip (dark).


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "pistol_service", "frame_trooper", "helm_warden"])
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
	controller.pitch = -0.25
	p.cmd.pitch = controller.pitch
	p.cmd.yaw = controller.yaw
	p.rotation.y = controller.yaw
	p.cmd.aim_dir = Vector3.ZERO
	p.active_weapon_index = -1
	var pose := ActionPose.of(p)
	var outside := Camera3D.new()
	outside.fov = 50.0
	raid.add_child(outside)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("helmet_lamp"))
	# [name, lamp on, helmet on the hip, from outside]
	var shots := [["front_on", true, false, true], ["front_off", false, false, true],
			["first_on", true, false, false], ["first_off", false, false, false], ["hip", true, true, true]]
	for shot: Array in shots:
		var name: String = shot[0]
		p.cmd.lamp = shot[1]
		var stow := 1.0 if shot[2] else 0.0
		controller.view_mode = PlayerController.ViewMode.THIRD if shot[3] else PlayerController.ViewMode.FIRST
		outside.current = shot[3]
		controller.camera.current = not shot[3]
		for k in 20:
			# Night, near enough: the sun and the sky's light down, every
			# frame in case the world's sky sets them again.
			for node in v.get_tree().root.find_children("*", "DirectionalLight3D", true, false):
				(node as DirectionalLight3D).visible = false
			for node in v.get_tree().root.find_children("*", "WorldEnvironment", true, false):
				var env := (node as WorldEnvironment).environment
				if env != null:
					env.ambient_light_energy = 0.02
					env.background_energy_multiplier = 0.05
					env.fog_enabled = false
					env.volumetric_fog_enabled = false
			p.helmet_stow = stow
			p.visor.stowed = stow >= Actor.HELMET_LIFTED
			pose.helmet = stow
			var at := p.global_position
			outside.global_position = at + p.global_basis * Vector3(0.9, 1.9, 2.2)
			outside.look_at(at + p.global_basis * Vector3(0.0, 0.6, -3.0))
			await v.get_tree().process_frame
		await RenderingServer.frame_post_draw
		v.get_viewport().get_texture().get_image().save_png(out_dir.path_join("helmet_lamp/%s.png" % name))
		print("saved helmet_lamp/%s.png lit=%s" % [name, p.lamp_lit()])
	raid.queue_free()
