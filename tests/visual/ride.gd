extends RefCounted
## `--ride-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --ride-only` shoots the rider seated on a bike
## (`RIDE_VEHICLE=<item id>` seats them on another vehicle).


## The rider on a bike: rows of hands-free with weapons slung, a gun drawn, a
## blade drawn, and leaning into a right turn; each from the side, the front
## quarter, behind and above-behind. Then the riding view in first person.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.queue_free()
	raid.bots.clear()
	var player := raid.player
	await v._settle(10)
	# A flat deck well above the map, so nothing stands in the shots.
	var at := player.global_position + Vector3(0, 40, 0)
	var deck := StaticBody3D.new()
	var deck_shape := CollisionShape3D.new()
	deck_shape.shape = BoxShape3D.new()
	deck_shape.shape.size = Vector3(40, 1, 40)
	deck.add_child(deck_shape)
	var deck_mesh := MeshInstance3D.new()
	deck_mesh.mesh = BoxMesh.new()
	deck_mesh.mesh.size = Vector3(40, 1, 40)
	deck.add_child(deck_mesh)
	raid.add_child(deck)
	deck.global_position = at - Vector3(0, 0.5, 0)
	var ride_id := OS.get_environment("RIDE_VEHICLE")
	if ride_id == "" or not ItemDB.has_tag(ride_id, "vehicle"):
		ride_id = "bike_raider"
	var bike: Node3D = raid.spawn_vehicle(ride_id, at + Vector3(0, 0.3, 0), 0.6)
	# Bigger vehicles are framed from further out and higher up.
	var seat_y: float = bike.seat_point.y
	var frame_out := maxf(1.0, seat_y / 0.98)
	if bike.model != "bike":
		frame_out = maxf(frame_out, bike.body_size.z / 2.6)
	await v._settle(20)
	bike.mount(player)
	player.set_physics_process(false)
	for seat_index in bike.seats.size():
		# A passenger on every seat, to see the seating two up (or four up).
		# A plain soldier, not a heavy in a walker frame.
		var pillion: Actor = null
		for tries in 20:
			pillion = raid.spawn_bot("Pillion%d_%d" % [seat_index, tries], at + Vector3(-2.0 - seat_index, 0.3, 0.0),
					7 + tries + seat_index * 31, false, "tide", 0)
			if pillion.display_name == "Tide Raider":
				break
			raid.bots.erase(pillion)
			pillion.free()
		if pillion.has_node("Brain"):
			pillion.get_node("Brain").set_physics_process(false)
		await v._settle(5)
		bike.mount(pillion, true, seat_index)
		pillion.set_physics_process(false)
	player.rotation.y = 0.6
	var skin: Node = player.get_node("Skin")
	var gun := -1
	var blade := -1
	for i in player.weapons.size():
		if player.weapons[i] is MeleeWeapon:
			blade = i
		elif player.weapons[i] is Gun and gun < 0:
			gun = i
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	# [weapon, lean]
	var rows := [[-1, 0.0], [gun, 0.0], [blade, 0.0], [-1, 0.3]]
	var sheet := Image.create(4 * 320, rows.size() * 360, false, Image.FORMAT_RGBA8)
	for row in rows.size():
		player.active_weapon_index = rows[row][0]
		player._refresh_weapon_visuals()
		bike.set_physics_process(rows[row][1] == 0.0)
		bike.lean = rows[row][1]
		bike.get_node("Model").rotation = Vector3(0.0, 0.0, -bike.lean)
		await v._settle(60)
		var b: Basis = bike.global_basis
		var sides: Array[Vector3] = [b.x, (b.x - b.z).normalized(), b.z, (b.z * 0.8 + Vector3.UP * 0.7).normalized()]
		for c in sides.size():
			var look_at := bike.global_position + Vector3(0, seat_y - 0.13, 0)
			cam.global_position = look_at + (sides[c] + Vector3.UP * 0.15).normalized() * 6.5 * frame_out
			cam.look_at(look_at)
			await v._settle(1)
			await RenderingServer.frame_post_draw
			var frame := v.get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
			cut.resize(320, 360)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(c * 320, row * 360))
	sheet.save_png(out_dir.path_join("ride.png"))
	print("saved ride.png")
	# Close in on the hands and feet, hands free, from the left and above-front.
	player.active_weapon_index = -1
	player._refresh_weapon_visuals()
	bike.set_physics_process(true)
	await v._settle(40)
	var close := [[(-bike.global_basis.x * 2.4 + Vector3(0, 0.2, 0)) * frame_out, "ride_close_side.png"],
		[(-bike.global_basis.z * 1.6 + bike.global_basis.x * 0.9 + Vector3(0, 1.0, 0)) * frame_out, "ride_close_front.png"]]
	for shot in close:
		var focus: Vector3 = bike.global_position + bike.global_basis * (bike.seat_point + Vector3(0, 0.02, -0.38))
		cam.global_position = focus + shot[0]
		cam.look_at(focus)
		await v._settle(2)
		await v._shot(out_dir.path_join(shot[1]))
	cam.queue_free()
	bike.set_physics_process(true)
	player.set_physics_process(true)
	player.active_weapon_index = -1
	var controller := PlayerController.new()
	controller.setup(player)
	raid.add_child(controller)
	# Looking straight down the vehicle, as a driver does.
	controller.yaw = bike.heading
	controller.pitch = -0.05
	controller.ride_view = PlayerController.ViewMode.THIRD
	await v._settle(40)
	await v._shot(out_dir.path_join("ride_third.png"))
	controller.ride_view = PlayerController.ViewMode.FIRST
	await v._settle(40)
	await v._shot(out_dir.path_join("ride_first.png"))
	# And glancing down at the controls, which shows whether the eyes are
	# where the seated body's are, not down in its collar.
	controller.pitch = -0.6
	await v._settle(40)
	await v._shot(out_dir.path_join("ride_first_down.png"))
	raid.queue_free()
