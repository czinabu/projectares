extends RefCounted
## `--air-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --air-only` shoots the body's flying poses on one sheet.


## One contact sheet, side on and from the back three-quarter, of each way a
## person flies: a jetpack hovering still and drifting, a boost, wings
## gliding, boots skimming and a plain fall. All in one raid, so it is quick
## to run while tuning the air poses in `ActorSkin`: any `name=value` after
## the mode sets that tuning var on the skin first (`glide_look=0.6`, a
## vector as `hang_legs=[Vector3(0,-1,0),...]`, anything `str_to_var` reads).
static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var tune := {}
	for arg in args:
		if arg.contains("=") and not arg.begins_with("--"):
			var value := arg.substr(arg.find("=") + 1)
			tune[arg.get_slice("=", 0)] = value if arg.begins_with("only=") else str_to_var(value)
	# [name, rig, hovering, boosting, gliding, speed, climb]
	var poses := [
		["hover", "jetpack_mk2", true, false, false, 0.0, 0.0],
		["hover_drift", "jetpack_mk2", true, false, false, 10.0, 0.0],
		["boost", "jetpack_mk2", true, true, false, 22.0, 0.0],
		["glide", "wings_glide", false, false, true, 16.0, -1.8],
		["boots", "boots_thruster", false, false, false, 15.0, 0.0],
		["fall", "jetpack_mk2", false, false, false, 4.0, -12.0],
	]
	# `only=hover,glide` shoots just those.
	if tune.has("only"):
		var names := String(tune["only"]).split(",")
		poses = poses.filter(func(pose: Array) -> bool: return String(pose[0]) in names)
		tune.erase("only")
	var cell := Vector2i(360, 360)
	var views := ["side", "quarter"]
	var sheet := Image.create(poses.size() * cell.x, views.size() * cell.y, false, Image.FORMAT_RGBA8)
	var rig := ""
	var raid: Raid = null
	var cam: Camera3D = null
	for column in poses.size():
		var pose: Array = poses[column]
		if pose[1] != rig:
			if raid:
				raid.queue_free()
				await v._settle(3)
			rig = pose[1]
			raid = Raid.new()
			v.add_child(raid)
			raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", rig, "frame_trooper"])
			v._armed(raid)
			for bot in raid.bots:
				bot.get_node("Brain").set_physics_process(false)
				bot.global_position += Vector3(0, -200, 0)
			cam = Camera3D.new()
			cam.fov = 45.0
			raid.add_child(cam)
			cam.make_current()
			await v._settle(20)
			var skin: Node = raid.player.get_node("Skin")
			for key: String in tune:
				skin.set(key, tune[key])
			raid.player.set_physics_process(false)
			raid.player.global_position += Vector3(0, 6, 0)
		var p := raid.player
		p.airborne_time = 1.0
		p.flight.is_hovering = pose[2]
		p.flight.is_boosting = pose[3]
		p.flight.is_thrusting = pose[2]
		p.flight.is_gliding = pose[4]
		p.flight.is_skimming = rig == "boots_thruster"
		var heading := -p.global_basis.z
		for row in views.size():
			for i in 70:
				p.velocity = heading * float(pose[5]) + Vector3(0, float(pose[6]), 0)
				await v.get_tree().process_frame
			var at := p.global_position + Vector3(0, 1.0, 0)
			var off := p.global_basis.x * 4.2 if views[row] == "side" else (p.global_basis.x + p.global_basis.z).normalized() * 4.2
			cam.look_at_from_position(at + off + Vector3(0, 0.6, 0), at)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var size := Vector2i(cell.x * h / 600, cell.y * h / 600)
			var cut := frame.get_region(Rect2i(frame.get_width() / 2 - size.x / 2, h / 2 - size.y / 2, size.x, size.y))
			cut.resize(cell.x, cell.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, cell), Vector2i(column * cell.x, row * cell.y))
	sheet.save_png(out_dir.path_join("air.png"))
	print("saved air.png")
	raid.queue_free()
