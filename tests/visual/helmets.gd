extends RefCounted
## `--helmets-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --helmets-only` shoots each helmet and armor frame worn.


## Every helmet worn, and a bare head, from the front, the side and behind,
## one row each, in one sheet. The same model first person leaves out.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	var player := raid.player
	player.set_physics_process(false)
	player.cmd.yaw = player.rotation.y
	player.cmd.pitch = 0.0
	player.cmd.aim_dir = -player.global_basis.z
	await v._settle(10)
	var skin: Node = player.get_node("Skin")
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	# A lamp beside the camera, so the face is not lost against the sky.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 6.0
	lamp.light_energy = 1.5
	cam.add_child(lamp)
	lamp.position = Vector3(0.6, 0.4, 0)
	# Each row: a helmet and an armor frame worn together.
	var helmets := ["", "visor_scav", "helm_spotter", "helm_seeker", "helm_warden", "helm_ember"]
	var frames := ["", "plate_light", "frame_runner", "frame_trooper", "frame_bulwark", "frame_trooper"]
	var sheet := Image.create(3 * 320, helmets.size() * 320, false, Image.FORMAT_RGBA8)
	for row in helmets.size():
		Loadout.wear_helmet(player, helmets[row])
		Loadout.wear_frame(player, frames[row])
		for k in 10:
			skin._process(1.0 / 60.0)
			await v.get_tree().process_frame
		var views := [-player.global_basis.z, player.global_basis.x, player.global_basis.z]
		for i in views.size():
			var head := player.global_position + Vector3(0, 1.45, 0)
			cam.global_position = head + (views[i] as Vector3) * 3.0 + Vector3(0, 0.15, 0)
			cam.look_at(head)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h / 4, h / 4, h / 2, h / 2))
			cut.resize(320, 320)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 320, 320), Vector2i(i * 320, row * 320))
	sheet.save_png(out_dir.path_join("helmets.png"))
	print("saved helmets.png")
	# Close up, the head alone: front, three quarters, side and back, each
	# helmet and its Mk2 in a row (helmet_closeups.png).
	Loadout.wear_frame(player, "")
	lamp.light_color = Color(0.95, 0.97, 1.0)
	lamp.light_energy = 2.5
	var fill := OmniLight3D.new()
	fill.omni_range = 6.0
	fill.light_energy = 1.2
	fill.light_color = Color(0.8, 0.88, 1.0)
	cam.add_child(fill)
	fill.position = Vector3(-0.8, 0.6, 0.2)
	var close := ["visor_scav", "helm_spotter", "helm_spotter_mk2", "helm_seeker", "helm_seeker_mk2",
			"helm_warden", "helm_warden_mk2", "helm_ember", "helm_ember_mk2"]
	var cells := 4
	var px := 300
	var closeups := Image.create(cells * px, close.size() * px, false, Image.FORMAT_RGBA8)
	var back_z: Vector3 = player.global_basis.z
	var right: Vector3 = player.global_basis.x
	var angles := [-back_z, (-back_z + right).normalized(), right, (back_z - right * 0.4).normalized()]
	for row in close.size():
		Loadout.wear_helmet(player, close[row])
		for k in 10:
			skin._process(1.0 / 60.0)
			await v.get_tree().process_frame
		var worn: Node3D = skin.get("_helmet")
		for i in cells:
			var head: Vector3 = worn.get_child(0).get_child(0).global_position if worn.get_child(0).get_child_count() > 0 \
					else player.global_position + Vector3(0, 1.66, 0)
			head.y -= 0.03
			cam.global_position = head + (angles[i] as Vector3) * 1.15 + Vector3(0, 0.1, 0)
			cam.look_at(head)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h * 3 / 8, h / 8, h * 3 / 4, h * 3 / 4))
			cut.resize(px, px)
			cut.convert(Image.FORMAT_RGBA8)
			closeups.blit_rect(cut, Rect2i(0, 0, px, px), Vector2i(i * px, row * px))
	closeups.save_png(out_dir.path_join("helmet_closeups.png"))
	print("saved helmet_closeups.png")
	raid.queue_free()
