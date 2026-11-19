extends RefCounted
## `--power-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --power-only` shoots the power weapons and their effects.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var stage := Node3D.new()
	v.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.16)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	stage.add_child(sun)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var ids := ["power_rail_lance", "power_helion", "power_arc_mortar", "power_storm_cannon"]
	var sheet := Image.create(2 * 480, ids.size() * 320, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var gun := Gun.new()
		Loadout._setup_weapon(gun, ids[row], ItemDB.item_stats(ids[row]))
		var model: Node3D = Look.weapon_model(gun)
		gun.free()
		if model == null:
			continue
		stage.add_child(model)
		var box: AABB = Look.model_bounds(model)
		var centre := box.get_center()
		for c in 2:
			var side := Vector3(1, 0.15, 0) if c == 0 else Vector3(1, 0.4, -0.9)
			cam.global_position = centre + side.normalized() * 2.9
			cam.look_at(centre)
			await v._settle(2)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 240 * h / 720, h / 2 - 160 * h / 720, 480 * h / 720, 320 * h / 720))
			cut.resize(480, 320)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 480, 320), Vector2i(c * 480, row * 320))
		model.queue_free()
	sheet.save_png(out_dir.path_join("power_weapons.png"))
	print("saved power_weapons.png")
	stage.queue_free()

	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.queue_free()
	var player := raid.player
	await v._settle(30)
	player.velocity = Vector3.ZERO
	var rack := raid.spawn_container(["power_rail_lance"], false, LootContainer.RACK_LABEL,
			player.global_position + Vector3(2.0, 0, -2.0))
	rack.interact(player)
	await v._settle(10)
	var lance := player.get_active_weapon() as Gun
	var shot_cam := Camera3D.new()
	raid.add_child(shot_cam)
	shot_cam.current = true
	shot_cam.fov = 60.0
	shot_cam.global_position = player.global_position + Vector3(3.2, 2.4, 3.5)
	shot_cam.look_at(player.global_position + Vector3(0, 1.2, -8))
	player.cmd.aim_dir = Vector3(0, 0.02, -1).normalized()
	player.cmd.yaw = 0.0
	player.cmd.primary = true
	for i in 70:
		await v.get_tree().physics_frame
		if lance.ammo_in_mag < lance.mag_size:
			break
	player.cmd.primary = false
	var ahead := player.global_position + Vector3(0, 0, -14)
	Fx.burst(raid, player.global_position + Vector3(-4, 1.5, -7), 3.0, Color(1.0, 0.45, 0.15))
	Fx.burst(raid, player.global_position + Vector3(5, 1.5, -6), 3.0, Color(0.7, 0.45, 1.0))
	rack.set_items(["power_storm_cannon"])
	await v._settle(4)
	await RenderingServer.frame_post_draw
	v.get_viewport().get_texture().get_image().save_png(out_dir.path_join("power_fire.png"))
	print("saved power_fire.png")
	raid.queue_free()
