extends RefCounted
## The `start_screen` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("-- start screen")
	t.check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/start.tscn",
			"the game launches on the start screen")
	var screen := StartScreen.new()
	t.add_child(screen)
	await t.frames(2)
	t.check(screen.start_button != null and screen.start_button.text == "START", "it offers Start")
	t.check(screen.title_text == "VERGE", "it shows the game title")
	var count := [0]
	screen.start_pressed.connect(func() -> void: count[0] += 1)
	screen.start_button.pressed.emit()
	screen.start_button.pressed.emit()
	t.check(count[0] == 1, "pressing Start fires once, however often it is pressed")
	screen.queue_free()
	var by_key := StartScreen.new()
	t.add_child(by_key)
	await t.frames(1)
	var keyed := [0]
	by_key.start_pressed.connect(func() -> void: keyed[0] += 1)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	by_key._unhandled_input(space)
	t.check(keyed[0] == 1, "Space starts the game too")
	by_key.queue_free()
	await t.frames(1)
	# Behind it: the lane between worlds, running forever on a fixed set of gates.
	var backdrop := TitleBackdrop.new()
	t.add_child(backdrop)
	await t.frames(2)
	t.check(backdrop.camera != null and backdrop.camera.is_current(), "the start screen has its own camera")
	var gates := backdrop.get_children().filter(func(n: Node) -> bool: return n.has_node("Sign"))
	t.check(gates.size() == backdrop.gate_count, "the lane is a row of gate frames")
	var zs := func() -> Array: return gates.map(func(g: Node3D) -> float: return g.position.z)
	backdrop.advance(backdrop.gate_spacing * backdrop.gate_count * 3.3)
	var after: Array = zs.call()
	var lane := backdrop.gate_spacing * backdrop.gate_count
	t.check(after.all(func(z: float) -> bool: return z <= backdrop.gate_spacing * 0.5 and z > -lane),
			"gates that pass the camera go round to the far end, so the lane never runs out")
	var signs := gates.map(func(g: Node) -> String: return (g.get_node("Sign") as Label3D).text) \
			.filter(func(t: String) -> bool: return t != "")
	var names := Worlds.raid_worlds().map(func(w: WorldDef) -> String: return w.display_name.to_upper())
	t.check(not signs.is_empty() and signs.all(func(t: String) -> bool: return t in names),
			"some gates carry the names of the worlds you can deploy to")
	backdrop.jump_time = 0.1
	await backdrop.jump()
	await t.frames(1)
	t.check(backdrop.speed >= backdrop.jump_speed * 0.99 and backdrop.camera.fov > backdrop.fov + 20.0,
			"Start throws the lane into a jump")
	backdrop.queue_free()
	await t.frames(1)
