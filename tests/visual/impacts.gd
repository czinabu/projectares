extends RefCounted
## `--impacts-only`, a mode `visual_check.gd` finds by itself.


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
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 2.5, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.52)
	box.material = mat
	wall.mesh = box
	stage.add_child(wall)
	wall.position = Vector3(0, 1.25, -0.15)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	cam.position = Vector3(0.6, 1.4, 3.0)
	cam.look_at(Vector3(0, 1.2, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		Fx.impact(stage, Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(0.6, 2.0), 0.0), Vector3.BACK, false)
		await v._settle(1)
	Fx.impact(stage, Vector3(-0.8, 1.0, 1.2), Vector3.ZERO, true)
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	var kinds := ["hit", "armor", "armor_break", "head", "guarded", "kill"]
	for i in kinds.size():
		var marker := Hud.HitMarker.new()
		layer.add_child(marker)
		marker.position = Vector2(60 + i * 90, 40)
		marker.size = Vector2(40, 40)
		marker.flash(kinds[i])
		marker.set_process(false)
	await v._settle(2)
	await RenderingServer.frame_post_draw
	v.get_viewport().get_texture().get_image().save_png(out_dir.path_join("impacts.png"))
	print("saved impacts.png")
	stage.queue_free()
