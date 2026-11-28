extends RefCounted
## `--flinch-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --flinch-only` shoots the body flinching from hits
## (`Locomotion` hit clips, `Actor.hit_mark`), frame by frame.


## One contact sheet per view (`flinch_side.png`, `flinch_front.png`): a row
## per hit, left to right in time from just before it lands, a rifle held
## at the hip. Rows: the chest, the head, the stomach and each shoulder
## from the front, then the chest from behind and from the left.
## `only=chest_back,head` shoots just those rows, `weapon=blade_arc` holds
## another weapon, `armor=frame_bulwark` wears another frame, and `frames`
## saves every other tick as `flinch/<row>_<view>_NN.png` instead, to be
## strung into a clip (30 a second plays them at the game's speed).
static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var names: PackedStringArray = []
	var frames := args.has("frames")
	var weapon := "rifle_carbine"
	var armor := "frame_trooper"
	for arg in args:
		if arg.begins_with("only="):
			names = arg.substr(5).split(",")
		elif arg.begins_with("weapon="):
			weapon = arg.substr(7)
		elif arg.begins_with("armor="):
			armor = arg.substr(6)
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, [weapon, "blade_scrap", armor])
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	raid.zone_rules = false
	var p := raid.player
	p.weapons_locked = false
	for i in p.weapons.size():
		if p.weapons[i].item_id == weapon:
			p._draw_weapon(i)
	await v._settle(40)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(400, 1, 400)
	floor.add_child(shape)
	var slab := MeshInstance3D.new()
	slab.mesh = BoxMesh.new()
	(slab.mesh as BoxMesh).size = Vector3(400, 1, 400)
	floor.add_child(slab)
	raid.add_child(floor)
	floor.global_position = p.global_position + Vector3(0, 300, 0)
	p.global_position = floor.global_position + Vector3(0, 0.6, 0)
	p.velocity = Vector3.ZERO
	await v._settle(30)
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	# [row, where it lands (a share of the eyes' height, m to the right),
	# where it comes from (in the body's frame), headshot]
	var rows := [
		["chest", Vector2(0.72, 0.0), Vector3(0, 0, -1), false],
		["head", Vector2(1.0, 0.0), Vector3(0, 0, -1), true],
		["stomach", Vector2(0.5, 0.0), Vector3(0, 0, -1), false],
		["shoulder_left", Vector2(0.86, -0.18), Vector3(0, 0, -1), false],
		["shoulder_right", Vector2(0.86, 0.18), Vector3(0, 0, -1), false],
		["chest_back", Vector2(0.72, 0.0), Vector3(0, 0, 1), false],
		["chest_left", Vector2(0.72, 0.0), Vector3(-1, 0, 0), false],
	]
	if not names.is_empty():
		rows = rows.filter(func(row: Array) -> bool: return String(row[0]) in names)
	var shots := 20 if frames else 12
	var views := ["side", "front", "quarter"] if frames else ["side", "front"]
	if frames:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("flinch"))
	var cell := Vector2i(240, 300)
	var sheets := {}
	for view: String in ["side", "front"]:
		sheets[view] = Image.create(shots * cell.x, rows.size() * cell.y, false, Image.FORMAT_RGBA8)
	var start := p.global_transform
	var shooter := raid.spawn_bot("Shooter", p.global_position + Vector3(0, -100, 0), 300, false, "", -2,
			["rifle_carbine", "frame_trooper"])
	await v._settle(2)
	var brain := shooter.get_node_or_null("Brain")
	if brain:
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	for row in rows.size():
		p.global_transform = start
		p.velocity = Vector3.ZERO
		p.health.health = p.health.max_health
		p.protected_left = 0.0
		var spot: Vector2 = rows[row][1]
		var from: Vector3 = rows[row][2]
		shooter.global_position = p.global_position + p.global_basis * (from * 8.0) + Vector3(0, -100, 0)
		await v._settle(40)
		for i in shots:
			if i == 1:
				var info := DamageInfo.make(30.0, shooter, "bullet",
						p.global_position + p.global_basis * Vector3(spot.y, spot.x * p.eye_height, 0.0))
				# The shooter stands level only for the hit, out of the frame otherwise.
				shooter.global_position.y += 100.0
				info.headshot = rows[row][3]
				Combat.deal(p, info)
				shooter.global_position.y -= 100.0
			for k in 2:
				await v.get_tree().process_frame
			for view: String in views:
				var at := p.global_position + Vector3(0, 0.95, 0)
				var off := p.global_basis.x if view == "side" else -p.global_basis.z
				if view == "quarter":
					off = (p.global_basis.x - p.global_basis.z).normalized()
				cam.look_at_from_position(at + off * 7.5, at)
				await RenderingServer.frame_post_draw
				var frame := v.get_viewport().get_texture().get_image()
				var h := frame.get_height()
				var size := Vector2i(cell.x * h / 720, cell.y * h / 720)
				var cut := frame.get_region(Rect2i(frame.get_width() / 2 - size.x / 2, h / 2 - size.y / 2, size.x, size.y))
				cut.resize(cell.x, cell.y)
				cut.convert(Image.FORMAT_RGBA8)
				if frames:
					cut.save_png(out_dir.path_join("flinch/%s_%s_%02d.png" % [rows[row][0], view, i]))
					continue
				(sheets[view] as Image).blit_rect(cut, Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, row * cell.y))
	for view: String in ([] if frames else sheets.keys()):
		(sheets[view] as Image).save_png(out_dir.path_join("flinch_%s.png" % view))
		print("saved flinch_%s.png" % view)
	raid.queue_free()
