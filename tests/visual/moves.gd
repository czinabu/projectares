extends RefCounted
## `--moves-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --moves-only` shoots one-shot moves frame by frame.


## Contact sheets, side on and from the front, of moves played for real with
## a blade out: a slide out of a sprint, light cuts from each side, a heavy,
## a kick, standing on guard, a sprint started and stopped, and a jump from a
## stand and from a sprint. Each row is one move, left to right in
## time, so a snap between poses or a leg that flares shows as a jump
## between neighbours. `only=slide,kick` shoots just those rows. `frames`
## instead saves every other tick of each move, from three sides, as
## `moves/<move>_<view>_NN.png`, to be strung into a clip (30 a second plays
## them at the game's speed).
static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var names: PackedStringArray = []
	var frames := args.has("frames")
	for arg in args:
		if arg.begins_with("only="):
			names = arg.substr(5).split(",")
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "frame_trooper"])
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	raid.zone_rules = false
	var p := raid.player
	p.weapons_locked = false
	var blade: MeleeWeapon = null
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			blade = p.weapons[i]
			p._draw_weapon(i)
	await v._settle(40)
	# A flat floor high above the map, nothing to run into.
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
	# [name, frames between shots]
	var rows := [["slide", 6], ["light_right", 3], ["light_left", 3], ["overhead", 3], ["heavy", 5], ["kick", 4], ["guard", 8],
			["start", 4], ["stop", 4], ["jump", 5], ["run_jump", 5]]
	if not names.is_empty():
		rows = rows.filter(func(row: Array) -> bool: return String(row[0]) in names)
	var shots := 42 if frames else 14
	var views := ["side", "front", "quarter"] if frames else ["side", "front"]
	if frames:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("moves"))
	var cell := Vector2i(240, 300)
	var sheets := {}
	for view: String in ["side", "front"]:
		sheets[view] = Image.create(shots * cell.x, rows.size() * cell.y, false, Image.FORMAT_RGBA8)
	var start := p.global_transform
	for row in rows.size():
		var move: String = rows[row][0]
		p.global_transform = start
		p.velocity = Vector3.ZERO
		p.cmd.move = Vector2.ZERO
		p.cmd.sprint = false
		blade.light_stamina = 0.0
		blade.heavy_stamina = 0.0
		p.stamina = p.max_stamina
		await v._settle(40)
		if move in ["slide", "stop", "run_jump"]:
			# A sprint, then the move out of it.
			p.cmd.move = Vector2(0, 1)
			p.cmd.sprint = true
			await v._settle(70)
		elif move in ["start", "jump"]:
			pass
		elif move == "kick":
			p.cmd.kick_pressed = true
		elif move != "guard":
			blade.combo_step = {"light_right": 0, "light_left": 1, "overhead": 2, "heavy": 0}[move]
			blade._combo_timer = 1.0 if blade.combo_step > 0 else 0.0
			if move == "heavy":
				p.cmd.tertiary_pressed = true
			else:
				p.cmd.primary_pressed = true
		for i in shots:
			# The slide starts two shots in, after a glimpse of the sprint.
			if i == (5 if frames else 2):
				match move:
					"slide":
						p.cmd.slide = true
					"start":
						p.cmd.move = Vector2(0, 1)
						p.cmd.sprint = true
					"stop":
						p.cmd.move = Vector2.ZERO
						p.cmd.sprint = false
					"jump", "run_jump":
						p.cmd.jump_pressed = true
						p.cmd.jump = true
			for k in (2 if frames else int(rows[row][1])):
				await v.get_tree().process_frame
				p.cmd.primary_pressed = false
				p.cmd.tertiary_pressed = false
				p.cmd.kick_pressed = false
				p.cmd.jump_pressed = false
				p.cmd.jump = false
				if move == "slide" and p.slide_left > 0.0:
					p.cmd.slide = false
					p.cmd.sprint = false
			for view: String in views:
				var at := p.global_position + Vector3(0, 0.9, 0)
				var off := p.global_basis.x if view == "side" else -p.global_basis.z
				if view == "quarter":
					off = (p.global_basis.x - p.global_basis.z).normalized()
				cam.look_at_from_position(at + off * 5.0, at)
				await RenderingServer.frame_post_draw
				var frame := v.get_viewport().get_texture().get_image()
				var h := frame.get_height()
				var size := Vector2i(cell.x * h / 720, cell.y * h / 720)
				var cut := frame.get_region(Rect2i(frame.get_width() / 2 - size.x / 2, h / 2 - size.y / 2, size.x, size.y))
				cut.resize(cell.x, cell.y)
				cut.convert(Image.FORMAT_RGBA8)
				if frames:
					cut.save_png(out_dir.path_join("moves/%s_%s_%02d.png" % [move, view, i]))
					continue
				(sheets[view] as Image).blit_rect(cut, Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, row * cell.y))
	for view: String in ([] if frames else sheets.keys()):
		(sheets[view] as Image).save_png(out_dir.path_join("moves_%s.png" % view))
		print("saved moves_%s.png" % view)
	raid.queue_free()
