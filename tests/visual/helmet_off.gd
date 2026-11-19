extends RefCounted
## `--helmet-off-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --helmet-off-only` shoots a helmet taken off and
## clipped to the hip, at points through the take off, from the front
## left, over the shoulder and from the eyes.


## The helmet coming off onto the hip (`Actor.helmet_stow`): a column per
## point through the take off (on the head, the hand on it, on its way
## down, clipped on, the hand gone), a row each from the front left, over
## the shoulder and from the eyes. `VIEW_HELMET` picks the helmet. Saves
## `helmet_off.png`, and each shot full size under `helmet_off/`.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	var helmet := OS.get_environment("VIEW_HELMET") if OS.has_environment("VIEW_HELMET") else "helm_warden"
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "pistol_service", "frame_trooper", helmet])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await v._settle(30)
	p.set_physics_process(false)
	controller.set_physics_process(false)
	# Turned about, so the left side (the clip's) faces open ground.
	controller.yaw += PI
	controller.pitch = -0.15
	p.cmd.pitch = controller.pitch
	p.cmd.yaw = controller.yaw
	p.rotation.y = controller.yaw
	var pose := ActionPose.of(p)
	var outside := Camera3D.new()
	outside.fov = 40.0
	raid.add_child(outside)
	# Empty hands, as the take off leaves them (it puts a weapon away first).
	p.active_weapon_index = -1
	var stows := [0.0, 0.25, 0.5, 0.65, 1.0]
	# `HELMET_STOWS=0,0.2,0.4` picks the points through the take off.
	if OS.has_environment("HELMET_STOWS"):
		stows = Array(OS.get_environment("HELMET_STOWS").split(",")).map(func(v: String) -> float: return float(v))
	var size := Vector2i(320, 240)
	var sheet := Image.create(stows.size() * size.x, 3 * size.y, false, Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("helmet_off"))
	# `HELMET_CAMS=0,2` shoots only those rows (0 front left, 1 third, 2 first).
	var cams := [0, 1, 2]
	if OS.has_environment("HELMET_CAMS"):
		cams = Array(OS.get_environment("HELMET_CAMS").split(",")).map(func(c: String) -> int: return int(c))
	for cam: int in cams:
		for col in stows.size():
			var stow: float = stows[col]
			controller.view_mode = PlayerController.ViewMode.FIRST if cam == 2 else PlayerController.ViewMode.THIRD
			outside.current = cam == 0
			controller.camera.current = cam != 0
			p.cmd.helmet_off = stow > 0.0
			for k in 16:
				p.helmet_stow = stow
				p.visor.stowed = stow >= Actor.HELMET_LIFTED
				pose.helmet = stow
				if cam == 0:
					var at := p.global_position
					outside.global_position = at + p.global_basis * Vector3(-1.9, 1.5, -2.0)
					outside.look_at(at + Vector3(0, 1.1, 0))
				await v.get_tree().process_frame
			if OS.has_environment("HELMET_DEBUG"):
				var skin: Node = p.get_node("Skin")
				var sk: Skeleton3D = skin.find_child("Skeleton3D", true, false)
				var to_actor := p.global_transform.affine_inverse()
				var bone := func(n: String) -> Vector3: return to_actor * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n)).origin)
				var gl: Variant = skin.helmet_grip(-1.0)
				var gr: Variant = skin.helmet_grip(1.0)
				print("STOW %.2f gripL %s handL %s gripR %s handR %s head %s hips %s" % [stow,
						to_actor * gl if gl != null else "-", bone.call("Wrist.L"), to_actor * gr if gr != null else "-",
						bone.call("Wrist.R"), bone.call("Head"), bone.call("Hips")])
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			frame.save_png(out_dir.path_join("helmet_off/%d_%s.png" % [roundi(stow * 100), ["front", "third", "first"][cam]]))
			var w := frame.get_width()
			var h := frame.get_height()
			var cut_w := h * size.x / size.y
			var cut := frame.get_region(Rect2i((w - cut_w) / 2, 0, cut_w, h))
			cut.resize(size.x, size.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, cam * size.y))
	sheet.save_png(out_dir.path_join("helmet_off.png"))
	print("saved helmet_off.png")
	raid.queue_free()
