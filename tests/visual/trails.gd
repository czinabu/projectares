extends RefCounted
## `--trails-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --trails-only` shoots the thruster trails (`RigTrail`):
## trails.png, every trail (rows, the factory one first) burning on a
## jetpack and on thruster boots (columns) over the Basalt Rift;
## trail_stand.png, a base rig stand in a trail with its swatch; and
## trail_flight/NNN.png, frames of a Magma jetpack climbing, for a GIF.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	await _sheet(v, out_dir)
	await _flight(v, out_dir)
	await _stand(v, out_dir)


static func _sheet(v: Node, out_dir: String) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("rift"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	var player := raid.player
	player.set_physics_process(false)
	player.cmd.yaw = player.rotation.y
	player.cmd.pitch = 0.0
	player.cmd.aim_dir = -player.global_basis.z
	await v._settle(10)
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var trails: Array[String] = [""]
	trails.append_array(RigTrail.ids())
	var rigs := ["jetpack_mk1", "boots_thruster"]
	var size := 300
	var sheet := Image.create(rigs.size() * size, trails.size() * size, false, Image.FORMAT_RGBA8)
	var base_look := {"build": "m", "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2", "feet": "Casual_2"}
	for row in trails.size():
		var look := base_look.duplicate()
		if trails[row] != "":
			look["trail"] = trails[row]
		for col in rigs.size():
			Loadout.wear_rig(player, rigs[col], false)
			Look.set_appearance(player, look)
			await v.get_tree().process_frame
			var skin: Node = player.get_node("Skin")
			for k in 10:
				skin._process(1.0 / 60.0)
				await v.get_tree().process_frame
			# Burning, as just after an air jump.
			skin.set("_burst_left", 100.0)
			skin._process(1.0 / 60.0)
			var f := -player.global_basis.z
			var r := player.global_basis.x
			# From behind and a little low: the nozzles and the flames under them.
			var mid := player.global_position + Vector3(0, 1.05 if col == 0 else 0.45, 0)
			cam.global_position = mid + (-f * 0.9 + r * 0.55).normalized() * 3.6 + Vector3(0, -0.25, 0)
			cam.look_at(mid + Vector3(0, -0.2, 0))
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h * 3 / 8, h / 8, h * 3 / 4, h * 3 / 4))
			cut.resize(size, size)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, size, size), Vector2i(col * size, row * size))
	sheet.save_png(out_dir.path_join("trails.png"))
	print("saved trails.png")
	raid.queue_free()
	await v._settle(2)


## A Magma jetpack lifting off a mesa and climbing, the camera beside it.
static func _flight(v: Node, out_dir: String) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("rift"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	var player := raid.player
	Loadout.wear_rig(player, "jetpack_mk1", false)
	Look.set_appearance(player, {"build": "m", "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2",
			"feet": "Casual_2", "trail": "magma"})
	player.cmd.yaw = player.rotation.y
	player.cmd.aim_dir = -player.global_basis.z
	await v._settle(20)
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 55.0
	var dir := out_dir.path_join("trail_flight")
	DirAccess.make_dir_recursive_absolute(dir)
	var side := player.global_basis.x
	for i in 48:
		# A hop to lift off, then the thrust held, drifting forward.
		player.cmd.jump_pressed = i == 2
		player.cmd.jump = i >= 2 and i < 40
		player.cmd.move = Vector2(0, -0.6) if i >= 8 else Vector2.ZERO
		await v.get_tree().physics_frame
		await v.get_tree().physics_frame
		var mid := player.global_position + Vector3(0, 1.0, 0)
		cam.global_position = mid + side * 2.2 + Vector3(0, 0.2, 0) + player.global_basis.z * 0.8
		cam.look_at(mid + Vector3(0, -0.2, 0))
		await RenderingServer.frame_post_draw
		var frame := v.get_viewport().get_texture().get_image()
		frame.resize(frame.get_width() / 3, frame.get_height() / 3)
		frame.save_png(dir.path_join("%03d.png" % i))
	print("saved trail_flight frames")
	raid.queue_free()
	await v._settle(2)


## The base's rig stand in the Leviathan trail, its swatch beside it.
static func _stand(v: Node, out_dir: String) -> void:
	var base := HomeBase.new()
	base.trail = "leviathan"
	base.show_gear(["jetpack_mk1", "trail_leviathan", "trail_ember"], {"rig": "jetpack_mk1"})
	v.add_child(base)
	await v._settle(20)
	var stand: Node3D = null
	for display in base.displays:
		if display.kind == "rig_stand":
			stand = display
	if stand == null:
		print("no rig stand to shoot")
		base.queue_free()
		return
	var cam := Camera3D.new()
	base.add_child(cam)
	cam.current = true
	cam.fov = 50.0
	var front := stand.global_basis.z
	var right := stand.global_basis.x
	var mid := stand.global_position + Vector3(0, 1.05, 0)
	cam.global_position = mid + front * 2.3 + right * 0.9 + Vector3(0, 0.2, 0)
	cam.look_at(mid + right * 0.2)
	if base.player:
		base.player.visible = false
	await v._settle(6)
	await v._shot(out_dir.path_join("trail_stand.png"))
	base.queue_free()
	await v._settle(2)
