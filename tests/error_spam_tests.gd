extends RefCounted
## No error spam: a running game must not log errors every frame. Thousands a
## second sank Ashfront to 9 fps on a fast PC (the GPU drew a frame in 3 ms),
## from three bugs that each fed on a slow frame or a freed node: the view's
## shake spring overshooting on a long frame until the camera was NaN (and
## every view reading it, the watch card first, failed each frame), a faded
## bullet mark breaking the sweep of every later mark, and a storm-lit
## folding blade that had lost its folded copy. Each is checked where it
## happens, and an Ashfront session is watched for any error at all.


## Counts every error and warning the engine or a script reports while it is
## added (`OS.add_logger`), and keeps the first few to say what they were.
class ErrorCount extends Logger:
	var count := 0
	var first: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1
		if first.size() < 3:
			var where := ""
			for trace in script_backtraces:
				if not trace.is_empty():
					where += " " + trace.format().strip_edges().replace("\n", " <")
			first.append("%s (%s:%d %s%s)" % [rationale if rationale != "" else code, file, line, function, where])

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func said() -> String:
		return "none" if count == 0 else "%d, first: %s" % [count, "; ".join(first)]


static func watch() -> ErrorCount:
	var errors := ErrorCount.new()
	OS.add_logger(errors)
	return errors


static func run(t: Node) -> void:
	print("Error spam")
	_check_shake_on_long_frames(t)
	await _check_marks_after_one_fades(t)
	_check_storm_lit_blade_folds(t)
	_check_peek_fade_after_body_freed(t)
	await _check_ashfront_session(t)


static func _check_shake_on_long_frames(t: Node) -> void:
	var controller := PlayerController.new()
	controller.kick_view(controller.bullet_flinch(40.0, 1.0))
	var finite := true
	for i in 20:
		# A hitch, then a machine at a few frames a second.
		controller._update_shake(0.5 if i == 0 else 0.15)
		finite = finite and controller.view_shake().is_finite() and controller.view_shake().length() < 0.2
	t.check(finite and controller.view_shake().is_zero_approx(),
			"a jolt on slow frames settles back instead of throwing the view off (shake %s)" % controller.view_shake())
	controller.free()


static func _check_marks_after_one_fades(t: Node) -> void:
	var wall := Node3D.new()
	t.add_child(wall)
	var errors := watch()
	Fx._marks.clear()
	for i in 3:
		Fx._leave_mark(wall, Vector3(i, 1.0, 0.0), Vector3.BACK)
	# One fades out and frees itself; the next shots must sweep it out.
	(Fx._marks[0] as Node).free()
	for i in Fx.MAX_MARKS + 2:
		Fx._leave_mark(wall, Vector3(0.0, 1.0 + i * 0.1, 0.0), Vector3.BACK)
	await t.frames(1)
	var all_live := Fx._marks.all(func(m: Variant) -> bool: return is_instance_valid(m))
	OS.remove_logger(errors)
	t.check(errors.count == 0 and all_live and Fx._marks.size() <= Fx.MAX_MARKS,
			"bullet marks keep sweeping out faded ones, with no errors (%s)" % errors.said())
	Fx._marks.clear()
	wall.free()


static func _check_storm_lit_blade_folds(t: Node) -> void:
	var was := Look.enabled
	Look.enabled = true
	var blade := MeleeWeapon.new()
	var errors := watch()
	var lit := true
	var folds := true
	for id: String in ["blade_arc", "spear_lancer"]:
		blade.item_id = id
		# Worn folded on the hip when the soldier is lit, and drawn later.
		for start: float in [1.0, 0.0, 0.5]:
			var model := Look.weapon_model(blade)
			_unlit(model)
			Look.set_extend(model, start)
			Look.mark_storm_readable(model, Color(1.0, 0.3, 0.7))
			for extend: float in [0.0, 0.5, 1.0, 0.0]:
				Look.set_extend(model, extend)
				var mats := _fold_mats(model)
				folds = folds and not mats.is_empty()
				for mat in mats:
					lit = lit and mat.get_shader_parameter("storm_pop") == 1.0
					folds = folds and is_equal_approx(float(mat.get_shader_parameter("extend")), extend)
			model.free()
	OS.remove_logger(errors)
	blade.free()
	Look.enabled = was
	t.check(errors.count == 0 and folds, "a storm-lit blade folds and draws like any other (errors: %s)" % errors.said())
	t.check(lit, "and keeps its faction rim folded, half drawn and drawn")


## Headless, a shader parameter never set reads back null rather than its
## default, which `Look.mark_storm_readable` takes as "no storm uniforms";
## set the default (unlit) as a renderer would read it.
static func _unlit(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_surface_override_material(i) as ShaderMaterial
			if mat and mat.get_shader_parameter("storm_pop") == null:
				mat.set_shader_parameter("storm_pop", 0.0)
				if mat.has_meta("tech_fold") and not mat.has_meta("tech_full"):
					Look._folded_copy(mat).set_shader_parameter("storm_pop", 0.0)


static func _fold_mats(model: Node3D) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_surface_override_material(i) as ShaderMaterial
			if mat and mat.get_shader_parameter("fold_slide") != null and mat.get_shader_parameter("fold_slide") > 0.0:
				out.append(mat)
	return out


## The third-person peek fade keeps the bodies it has faded. One freed
## since (a dead bot cleared away, a world left) used to be assigned to a
## typed `Actor` loop variable, an error that stopped the game in the
## editor's debugger: the "freeze" while aiming or joining a world.
static func _check_peek_fade_after_body_freed(t: Node) -> void:
	var fade := PlayerController.PeekFade.new()
	var errors := watch()
	for active: bool in [true, false]:
		var gone := Actor.new()
		var kept := Actor.new()
		fade._unseen[gone] = 1.0
		fade._alpha[gone] = 0.4
		fade._alpha[kept] = 0.5
		gone.free()
		# Inactive needs no viewer; active with nothing to check this tick.
		fade._check_left = 1.0
		fade.update(null, null, active, 0.016)
		t.check(not fade._unseen.has(gone) and not fade._alpha.has(gone),
				"the peek fade lets go of a freed body (%s)" % ("third person" if active else "first person"))
		kept.free()
		fade.update(null, null, active, 0.016)
	OS.remove_logger(errors)
	t.check(errors.count == 0, "and logs no error over it (errors: %s)" % errors.said())


## The real game on Ashfront for a few seconds, in both views, watch up and
## down, being shot, with a hitch on the way: not one error may be logged.
static func _check_ashfront_session(t: Node) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(10)
	main.start_raid("ashfront")
	await t.frames(10)
	var p: Actor = main.raid.player if main.raid != null else null
	t.check(p != null and main.controller != null, "an Ashfront session starts")
	if p == null or main.controller == null:
		main.queue_free()
		await t.frames(5)
		return
	var controller: PlayerController = main.controller
	var errors := watch()
	for view in 2:
		for i in 90:
			controller.wrist_raised = i % 40 > 20
			if i % 15 == 0:
				# Being shot jolts the view (view only, so no real damage).
				controller._on_damaged(DamageInfo.make(30.0, null, "bullet"))
				# A slow patch right after (a hitch, then a few frames a
				# second): the long frames the view must ride out.
				controller._process(0.5)
				for slow in 5:
					controller._process(0.15)
			await t.frames(1)
		controller.toggle_view()
		await t.frames(3)
	# A bot that had orders and was freed since: the next orders sweep it out.
	var raid: Raid = main.raid
	var gone := Actor.new()
	raid._orders[gone] = "freed"
	gone.free()
	raid._orders_in = 0.0
	raid._tick_orders(0.016)
	t.check(not raid._orders.has(gone), "the armies' orders let go of a freed bot")
	OS.remove_logger(errors)
	t.check(errors.count == 0 and main.controller.camera.global_transform.is_finite(),
			"an Ashfront session in both views logs no errors and keeps its view (errors: %s)" % errors.said())
	main.queue_free()
	await t.frames(5)
