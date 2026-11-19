extends RefCounted
## `--vehicles-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --vehicles-only` shoots every vehicle parked, alone
## from three sides and in a row from far off, to compare their looks.


## Every vehicle parked in a row on a deck over Ashfront, dressed as in a
## raid: each one alone from the front quarter, the side and the back
## quarter (`vehicles.png`), and the row from 45 m (`vehicles_far.png`), to
## see that each reads as itself from far off.
static func shoot(vc: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	vc.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	vc._armed(raid)
	for bot in raid.bots:
		bot.queue_free()
	raid.bots.clear()
	raid.player.global_position += Vector3(0, -300, 0)
	raid.player.set_physics_process(false)
	await vc._settle(10)
	var at := raid.player.global_position + Vector3(0, 340, 0)
	var deck := StaticBody3D.new()
	var deck_shape := CollisionShape3D.new()
	deck_shape.shape = BoxShape3D.new()
	deck_shape.shape.size = Vector3(120, 1, 120)
	deck.add_child(deck_shape)
	var deck_mesh := MeshInstance3D.new()
	deck_mesh.mesh = BoxMesh.new()
	deck_mesh.mesh.size = Vector3(120, 1, 120)
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color(0.32, 0.3, 0.29)
	deck_mesh.mesh.material = deck_mat
	deck.add_child(deck_mesh)
	raid.add_child(deck)
	deck.global_position = at - Vector3(0, 0.5, 0)
	var ids := ["bike_scrapper", "bike_raider", "rover_warden", "mech_bulwark", "jet_kestrel"]
	var spaced := [-11.0, -6.5, -1.5, 4.0, 10.5]
	var parked: Array[Node3D] = []
	for i in ids.size():
		var v: Node3D = raid.spawn_vehicle(ids[i], at + Vector3(spaced[i], 0.4, 0), 0.0)
		parked.append(v)
	await vc._settle(60)
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var size := Vector2i(400, 300)
	var sheet := Image.create(3 * size.x, ids.size() * size.y, false, Image.FORMAT_RGBA8)
	for row in parked.size():
		var v: Node3D = parked[row]
		var reach: float = maxf(maxf(v.body_size.z, v.body_size.y * 1.3), 2.4) * 1.45
		var focus: Vector3 = v.global_position + Vector3(0, v.seat_point.y * 0.7, 0)
		# Hide the others, so each stands alone.
		for other in parked:
			other.visible = other == v
		var sides: Array[Vector3] = [Vector3(-0.8, 0.3, -1.0), Vector3(-1.0, 0.18, 0.0), Vector3(0.75, 0.45, 1.0)]
		for c in sides.size():
			cam.global_position = focus + sides[c].normalized() * reach
			cam.look_at(focus)
			await vc._settle(2)
			await RenderingServer.frame_post_draw
			var frame := vc.get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut_w := h * size.x / size.y
			var cut := frame.get_region(Rect2i((w - cut_w) / 2, 0, cut_w, h))
			cut.resize(size.x, size.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(c * size.x, row * size.y))
	sheet.save_png(out_dir.path_join("vehicles.png"))
	print("saved vehicles.png")
	for other in parked:
		other.visible = true
	cam.fov = 30.0
	var middle := at + Vector3(0, 1.2, 0)
	cam.global_position = middle + Vector3(-18, 9, -40)
	cam.look_at(middle)
	await vc._settle(4)
	await vc._shot(out_dir.path_join("vehicles_far.png"))
	cam.global_position = middle + Vector3(0, 2.5, -14)
	cam.fov = 60.0
	cam.look_at(middle)
	await vc._settle(4)
	await vc._shot(out_dir.path_join("vehicles_row.png"))
	raid.queue_free()
