extends RefCounted
## `--arsenal-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --arsenal-only` lines up every weapon side on.


## Every weapon side on and from a three-quarter view, one row each, guns
## then power weapons then blades (arsenal.png): `-- <dir> --arsenal-only`.
## `ARSENAL_IDS` (comma separated) picks the rows.
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
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, -2.4, 0.0)
	fill.light_energy = 0.35
	stage.add_child(fill)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var ids := ["rifle_scrap", "rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher",
			"pistol_service", "pistol_machine", "pistol_hand_cannon",
			"power_rail_lance", "power_helion", "power_arc_mortar", "power_storm_cannon",
			"blade_scrap", "blade_arc", "knife_gutter", "axe_splitter", "hammer_breaker", "spear_lancer"]
	if OS.has_environment("ARSENAL_IDS"):
		ids = Array(OS.get_environment("ARSENAL_IDS").split(","))
	var cell := Vector2i(480, 240)
	var sheet := Image.create(2 * cell.x, ids.size() * cell.y, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var id: String = ids[row]
		var model: Node3D = null
		if id.ends_with(".glb"):
			# A raw model from the weapons folder, turned to point along -Z.
			model = Node3D.new()
			var raw: Node3D = Look._instance(Look.WEAPONS + id)
			model.add_child(raw)
			Look._fit(raw, Look.WEAPONS + id, Look.GUN_LENGTH, false)
			model.rotation.y = PI / 2.0
		else:
			var weapon: Weapon = MeleeWeapon.new() if ItemDB.has_tag(id, "melee") else Gun.new()
			Loadout._setup_weapon(weapon, id, ItemDB.item_stats(id))
			if weapon is Gun and ItemDB.has_tag(id, "sidearm"):
				(weapon as Gun).is_sidearm = true
			model = Look.weapon_model(weapon)
			weapon.free()
		if model == null:
			continue
		var pivot := Node3D.new()
		stage.add_child(pivot)
		pivot.add_child(model)
		if ItemDB.has_tag(id, "melee"):
			# Blades stand along +Y, edge ahead: lay them along -Z like a gun,
			# point ahead, flat to the side camera.
			pivot.rotation = Vector3(-PI / 2.0, 0, 0)
			pivot.rotate_object_local(Vector3.UP, PI / 2.0)
		await v._settle(2)
		var box: AABB = Look.model_bounds(pivot)
		var centre := box.get_center()
		var span := maxf(box.size.z, maxf(box.size.y * 2.0, 0.3))
		for c in 2:
			var side := Vector3(1, 0.08, 0) if c == 0 else Vector3(1, 0.45, -0.9)
			cam.global_position = centre + side.normalized() * span * 2.1
			cam.look_at(centre)
			await v._settle(2)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - h * 2 / 3, h / 2 - h / 3, h * 4 / 3, h * 2 / 3))
			cut.resize(cell.x, cell.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, cell), Vector2i(c * cell.x, row * cell.y))
		pivot.queue_free()
	sheet.save_png(out_dir.path_join("arsenal.png"))
	print("saved arsenal.png")
	stage.queue_free()
