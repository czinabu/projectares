extends RefCounted
## `--sidearms-only`, a mode `visual_check.gd` finds by itself.


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
	var ids := ["pistol_service", "pistol_machine", "pistol_hand_cannon"]
	var sheet := Image.create(2 * 480, ids.size() * 320, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var gun := Gun.new()
		gun.item_id = ids[row]
		gun.is_sidearm = true
		var model: Node3D = Look.weapon_model(gun)
		gun.free()
		if model == null:
			continue
		stage.add_child(model)
		var box: AABB = Look.model_bounds(model)
		var centre := box.get_center()
		for c in 2:
			var side := Vector3(1, 0.15, 0) if c == 0 else Vector3(1, 0.4, -0.9)
			cam.global_position = centre + side.normalized() * 1.1
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
	sheet.save_png(out_dir.path_join("sidearms.png"))
	print("saved sidearms.png")
	stage.queue_free()
