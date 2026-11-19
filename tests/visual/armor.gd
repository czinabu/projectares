extends RefCounted
## `--armor-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --armor-only` shoots each armor frame worn on the whole
## body (front, three-quarter, side, back), lightest first, so the weights
## and each frame's look can be compared at a glance.


## Every armor frame worn on its own (no helmet, rig or weapon), from four
## sides, one frame a row, into `armor.png`; `ARMOR_FRAMES=<ids>` picks them.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, [Loadout.BARE])
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
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 1.4
	cam.add_child(lamp)
	lamp.position = Vector3(0.8, 0.6, 0)
	var frames := ["", "plate_light", "frame_runner", "frame_trooper", "frame_thermal", "frame_bulwark"]
	var pick := OS.get_environment("ARMOR_FRAMES")
	if pick != "":
		frames = Array(pick.split(","))
	var size := 360
	var sheet := Image.create(4 * size, frames.size() * size, false, Image.FORMAT_RGBA8)
	for row in frames.size():
		Loadout.wear_frame(player, frames[row])
		for k in 10:
			skin._process(1.0 / 60.0)
			await v.get_tree().process_frame
		var f := -player.global_basis.z
		var r := player.global_basis.x
		var views := [f, (f + r).normalized(), r, -f]
		for i in views.size():
			var mid := player.global_position + Vector3(0, 1.12, 0)
			cam.global_position = mid + (views[i] as Vector3) * 3.5 + Vector3(0, 0.3, 0)
			cam.look_at(mid)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h * 3 / 8, h / 8, h * 3 / 4, h * 3 / 4))
			cut.resize(size, size)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, size, size), Vector2i(i * size, row * size))
	sheet.save_png(out_dir.path_join("armor.png"))
	print("saved armor.png")
	raid.queue_free()
