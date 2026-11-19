extends RefCounted
## `--hands-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --hands-only` shoots the hands close up on every gun
## and melee weapon, held low and aimed: each is held by its own grip.


## The four power weapons side on (power_weapons.png), then one in use in a
## raid: a Rail Lance beam, a plasma burst and an arc burst (power_fire.png).
## The weapon hand close up on each weapon, from the side and from ahead,
## at the hip and aiming (a blade: at rest, both shots the same), one row a
## weapon. Every model is held by its own grip (`Look._measure_hold`,
## `Look._fit_hands`), so the hands sit differently on each.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var ids := ["rifle_scrap", "rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher",
			"pistol_service", "pistol_machine", "pistol_hand_cannon", "power_rail_lance", "power_storm_cannon",
			"blade_scrap", "blade_arc", "knife_gutter", "axe_splitter", "hammer_breaker", "spear_lancer"]
	if OS.has_environment("HANDS_IDS"):
		ids = Array(OS.get_environment("HANDS_IDS").split(","))
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["blade_scrap", "plate_light"])
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	await v._settle(30)
	var p := raid.player
	p.set_physics_process(false)
	p.cmd.pitch = 0.0
	var cam := Camera3D.new()
	cam.fov = 30.0
	raid.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("hands"))
	var cell := Vector2i(360, 300)
	var sheet := Image.create(4 * cell.x, ids.size() * cell.y, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var id: String = ids[row]
		if ItemDB.has_tag(id, "power"):
			Loadout.equip(p, ["blade_scrap", "plate_light"])
			Loadout.set_power(p, id)
		else:
			Loadout.equip(p, [id, "plate_light"])
		var weapon: Weapon = null
		for i in p.weapons.size():
			if p.weapons[i].item_id == id:
				weapon = p.weapons[i]
				p.active_weapon_index = i
		await v._settle(70)
		var gun := weapon as Gun
		for col in 4:
			var aiming := col >= 2 and gun != null
			p.cmd.secondary = aiming
			if gun != null:
				gun._aiming = aiming
			await v._settle(40 if col % 2 == 0 else 3)
			var hand: Vector3 = (p.hand.get_meta("shown") as Transform3D).origin if p.hand.has_meta("shown") else p.hand.global_position
			var right := p.global_basis.x.normalized()
			var ahead := -p.global_basis.z.normalized()
			var side := right * 0.75 + Vector3.UP * 0.12 if col % 2 == 0 else ahead * 0.65 + right * 0.4 + Vector3.UP * 0.1
			var focus := hand + ahead * (0.12 if gun != null and not gun.is_sidearm else 0.04)
			cam.global_position = focus + side * (1.6 if weapon is MeleeWeapon and Look.is_two_handed(weapon) else 1.0)
			cam.look_at(focus)
			await v._settle(2)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			frame.save_png(out_dir.path_join("hands/%s_%d.png" % [id, col]))
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - cell.x * h / 720, h / 2 - cell.y * h / 720, 2 * cell.x * h / 720, 2 * cell.y * h / 720))
			cut.resize(cell.x, cell.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, cell), Vector2i(col * cell.x, row * cell.y))
		p.cmd.secondary = false
		if gun != null:
			gun._aiming = false
	sheet.save_png(out_dir.path_join("hands.png"))
	print("saved hands.png")
	raid.queue_free()
