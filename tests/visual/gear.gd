extends RefCounted
## `--gear-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --gear-only` shoots everything worn over an armor frame
## at once (`tools/armor_fit/gear_check.tscn` checks it in numbers): a
## flight rig and its straps, a backpack, a gun and a blade put away, a
## sidearm on the hip and a helmet clipped to the belt, from behind, the
## back three-quarter, the side and the front, one row a combination, into
## `gear.png`. `GEAR_FRAMES`, `GEAR_RIGS` (ids, "none" for none) and
## `GEAR_KIT` (item ids) pick them; `GEAR_BUILD=f` wears them on a body of
## that build.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var frames := _list("GEAR_FRAMES", ["none", "frame_trooper", "frame_bulwark"])
	var rigs := _list("GEAR_RIGS", ["jetpack_mk1", "wings_glide", "none"])
	var kit := _list("GEAR_KIT", ["rifle_carbine", "blade_scrap", "pistol_service", "pack_mule", "helm_warden"])
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, [Loadout.BARE])
	await v._settle(10)
	var player := raid.player
	var want := OS.get_environment("GEAR_BUILD")
	for bot in raid.bots:
		var skin_b: Node = bot.get_node_or_null("Skin")
		if want != "" and player == raid.player and str(player.get_node("Skin")._appearance.get("build", "")) != want \
				and skin_b != null and str(skin_b._appearance.get("build", "")) == want and skin_b._def.get("frame", "") == "" \
				and skin_b._def.has("people"):
			bot.get_node("Brain").set_physics_process(false)
			bot.global_transform = player.global_transform
			player.global_position += Vector3(0, -200, 0)
			player = bot
			continue
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	await v._settle(60)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 1.4
	cam.add_child(lamp)
	lamp.position = Vector3(0.8, 0.6, 0)
	var combos := []
	for frame: String in frames:
		for rig: String in rigs:
			combos.append([frame, rig])
	var size := 360
	var sheet := Image.create(4 * size, combos.size() * size, false, Image.FORMAT_RGBA8)
	for row in combos.size():
		var wear := kit.duplicate()
		for id: String in combos[row]:
			if id != "none":
				wear.append(id)
		Loadout.refit(player, wear)
		Loadout.arrive_unarmed(player)
		player.helmet_stow = 1.0 if player.visor.enabled else 0.0
		for k in 40:
			await v.get_tree().process_frame
		var f := -player.global_basis.z
		var r := player.global_basis.x
		var views := [-f, (-f - r).normalized(), -r, f]
		for i in views.size():
			var mid := player.global_position + Vector3(0, 1.05, 0)
			cam.global_position = mid + (views[i] as Vector3) * 3.6 + Vector3(0, 0.35, 0)
			cam.look_at(mid)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h * 3 / 8, h / 8, h * 3 / 4, h * 3 / 4))
			cut.resize(size, size)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, size, size), Vector2i(i * size, row * size))
	sheet.save_png(out_dir.path_join("gear.png"))
	print("saved gear.png")
	raid.queue_free()


static func _list(env: String, fallback: Array) -> Array:
	var got := OS.get_environment(env)
	return Array(got.split(",")) if got != "" else fallback
