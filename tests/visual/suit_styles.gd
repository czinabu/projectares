extends RefCounted
## `--suit-styles-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --suit-styles-only` shoots every suit style (the
## Mirror's "Suit top" and "Suit legs") on both bodies, from the front and
## the back, one style a column, into `suit_styles_<build>.png`, then one
## style under each armor frame and from the eyes into `suit_styles_worn.png`.
## SUIT_TOP=<colour index> and SUIT_BOTTOM=<colour index> dye every look.

const Human := preload("res://core/visual/human.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const CELL := Vector2i(240, 420)


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("plaza"), 42, [Loadout.BARE])
	for bot in raid.bots:
		bot.queue_free()
	raid.bots.clear()
	raid.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	player.active_weapon_index = -1
	player.global_position += Vector3(0, 40, 0)
	await v._settle(10)
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	# A plain grey backdrop and an even light, so the cloth reads.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.43, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cam.environment = env
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	raid.add_child(sun)
	sun.rotation_degrees = Vector3(-35, 30, 0)
	var fill := OmniLight3D.new()
	fill.light_energy = 0.7
	fill.omni_range = 12.0
	fill.shadow_enabled = false
	cam.add_child(fill)
	fill.position = Vector3(0.6, 0.8, 0)
	var top := int(OS.get_environment("SUIT_TOP")) if OS.get_environment("SUIT_TOP") != "" else 0
	var bottom := int(OS.get_environment("SUIT_BOTTOM")) if OS.get_environment("SUIT_BOTTOM") != "" else 0
	# Front and back whole, then the chest and the back close up.
	var views := [[Vector3(0.35, 0, -1), 3.3, 0.92], [Vector3(-0.5, 0, 0.85), 3.3, 0.92],
			[Vector3(0.3, 0.1, -1), 1.3, 1.2], [Vector3(-0.3, 0.1, 1), 1.3, 1.2]]
	for build: String in Human.BUILDS:
		var outfits: Array = Human.OUTFITS[build].keys()
		var sheet := Image.create(outfits.size() * CELL.x, views.size() * CELL.y, false, Image.FORMAT_RGBA8)
		for col in outfits.size():
			var outfit: String = outfits[col]
			Look.set_appearance(player, {"build": build, "head": outfit, "body": outfit, "legs": outfit,
					"feet": outfit, "skin": 2, "top": top, "bottom": bottom})
			await _pose(v, player)
			for row in views.size():
				await _frame(v, cam, player, views[row][0], views[row][1], views[row][2], 40.0)
				_blit(v, sheet, col, row)
		sheet.save_png(out_dir.path_join("suit_styles_%s.png" % build))
		print("saved suit_styles_%s.png" % build)
	# Worn: one style under each frame, then from the eyes, the same model.
	var worn_look := {"build": "m", "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2", "feet": "Casual_2",
			"skin": 2}
	var frames := ["", "plate_light", "frame_runner", "frame_trooper", "frame_bulwark"]
	var sheet := Image.create((frames.size() + 1) * CELL.x, 2 * CELL.y, false, Image.FORMAT_RGBA8)
	for row in 2:
		var look := worn_look.duplicate()
		if row == 1:
			for key in ["head", "body", "legs", "feet"]:
				look[key] = "Casual"
			look["build"] = "f"
		Look.set_appearance(player, look)
		for col in frames.size():
			Loadout.wear_frame(player, frames[col])
			await _pose(v, player)
			await _frame(v, cam, player, Vector3(0.45, 0, -1), 3.3, 0.92, 40.0)
			_blit(v, sheet, col, row)
		# From the eyes, looking down at the arms and legs.
		Loadout.wear_frame(player, "")
		await _pose(v, player)
		var head := player.global_position + Vector3(0, 1.62, 0)
		cam.fov = 75.0
		# What your own camera leaves out in first person: the head.
		cam.cull_mask &= ~(1 << (MirrorScript.HEAD_LAYER - 1))
		cam.global_position = head
		cam.look_at(head + player.global_basis * Vector3(0.15, -1.0, -0.6))
		await RenderingServer.frame_post_draw
		_blit(v, sheet, frames.size(), row)
		cam.cull_mask |= 1 << (MirrorScript.HEAD_LAYER - 1)
	sheet.save_png(out_dir.path_join("suit_styles_worn.png"))
	print("saved suit_styles_worn.png")


static func _pose(v: Node, player: Node) -> void:
	await v._settle(4)
	var skin: Node = player.get_node("Skin")
	for k in 20:
		skin._process(1.0 / 60.0)
		await v.get_tree().process_frame


static func _frame(v: Node, cam: Camera3D, player: Node3D, dir: Vector3, dist: float, h: float, fov: float) -> void:
	var at := player.global_position + Vector3(0, h, 0)
	cam.fov = fov
	cam.global_position = at + player.global_basis * dir.normalized() * dist
	cam.look_at(at)
	await RenderingServer.frame_post_draw


static func _blit(v: Node, sheet: Image, col: int, row: int) -> void:
	var frame := v.get_viewport().get_texture().get_image()
	var w := frame.get_width()
	var h := frame.get_height()
	var cw := CELL.x * h / CELL.y
	var cut := frame.get_region(Rect2i(w / 2 - cw / 2, 0, cw, h))
	cut.resize(CELL.x, CELL.y)
	cut.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
