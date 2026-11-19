extends RefCounted
## DEV MODE: the dev tools (`core/dev/dev_tools.gd`): what a performance
## capture writes and what a bug snapshot keeps, and that their keys stay
## out of a headless run. Delete this file with dev mode.

const DevToolsScript := preload("res://core/dev/dev_tools.gd")
const DevConsole := preload("res://core/dev/dev_console.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const DIR := "user://test_dev_tools"


static func run(t: Node) -> void:
	print("Dev tools: performance capture and bug snapshot")
	_check_summary(t)
	await _check_capture(t)
	_check_snapshot(t)
	await _check_console(t)
	await _check_console_app(t)


static func _check_summary(t: Node) -> void:
	var frames: Array[Dictionary] = []
	for i in 100:
		frames.append({"frame_ms": 60.0 if i == 99 else 10.0, "render_gpu_ms": float(i), "draws": 100 + i})
	var summary: Dictionary = DevToolsScript.summarize(frames)
	t.check(summary.frames == 100 and summary.hitches == 1 and is_equal_approx(summary.frame_ms.median, 10.0)
			and is_equal_approx(summary.frame_ms.worst, 60.0) and is_equal_approx(summary.render_gpu_ms.p95, 95.0),
			"a capture's summary gives the median, percentiles, worst and the hitches over 50 ms")
	t.check(summary.draws.most == 199 and is_equal_approx(summary.draws.average, 149.5)
			and absf(summary.fps - 100.0 / 1.05) < 0.01,
			"it averages the draw calls, keeps the most, and counts frames a second")
	t.check(DevToolsScript.summarize([]).frames == 0, "an empty capture still summarizes")


static func _check_capture(t: Node) -> void:
	var tools: Node = DevToolsScript.new()
	tools.save_dir = DIR
	t.check(not tools.enabled(), "the dev keys do nothing in a headless run")
	tools.force_enabled = true
	tools.context_source = func() -> Dictionary: return {"place": "test"}
	t.add_child(tools)
	var written := []
	tools.saved.connect(func(kind: String, path: String) -> void: written.append([kind, path]))
	tools.start_capture(0.2)
	t.check(tools.capturing(), "F9 starts a capture")
	for i in 60:
		if not tools.capturing():
			break
		await t.get_tree().process_frame
	t.check(not tools.capturing() and written.size() == 1 and written[0][0] == "perf",
			"the capture stops by itself once its time is up and writes its file")
	if written.size() == 1:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(written[0][1]))
		t.check(typeof(data) == TYPE_DICTIONARY and data.has("summary") and data.has("machine")
				and data.has("settings") and data.context.place == "test" and data.frames.size() > 0
				and data.frames[0].has("render_gpu_ms") and data.frames[0].has("draws"),
				"the file holds the summary, the machine, the settings, where it was taken and every frame")
	tools.queue_free()


static func _check_snapshot(t: Node) -> void:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	var path: String = DevToolsScript.write_snapshot(image, {"place": "Ashfront", "position": "1, 2, 3"}, DIR)
	var reader := ZIPReader.new()
	t.check(path != "" and reader.open(path) == OK, "a snapshot is one zip")
	if path == "":
		return
	var names := reader.get_files()
	var info: Variant = JSON.parse_string(reader.read_file("snapshot.json").get_string_from_utf8())
	var shot := Image.new()
	shot.load_png_from_buffer(reader.read_file("screenshot.png"))
	reader.close()
	t.check("screenshot.png" in names and shot.get_width() == 8 and typeof(info) == TYPE_DICTIONARY
			and info.context.position == "1, 2, 3" and info.has("machine") and info.has("settings"),
			"it keeps the screenshot, where the player was, the machine and the settings")


static func _check_console(t: Node) -> void:
	var was := DevMode.enabled
	var persisted := DevMode.persist
	DevMode.persist = false
	DevMode.enabled = false
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start(Worlds.get_world("ashfront"), 41)
	await t.frames(2)
	var me := raid.player
	t.check(DevConsole.run("war 1", raid, me, false)[0].contains("Dev mode is off"),
			"the console does nothing with dev mode off")
	DevMode.enabled = true
	t.check(DevConsole.run("help", raid, me, false).size() == DevConsole.COMMANDS.size(), "help lists every command")
	t.check(DevConsole.run("war 1", raid, me, true)[0].begins_with("Solo only"), "online the server decides, so it refuses")
	t.check(DevConsole.run("war 0.8", raid, me, false)[0].contains("0.80") and is_equal_approx(raid.war.intensity, 0.8),
			"war sets the war's heat")
	var ground: float = raid.map.call("ground_height", 40.0, -30.0)
	DevConsole.run("tp 40 -30", raid, me, false)
	t.check(me.global_position.distance_to(Vector3(40, ground + 0.15, -30)) < 0.01,
			"tp puts the feet on the ground at a spot")
	var before := raid.bots.size()
	DevConsole.run("bots 4", raid, me, false)
	var near := raid.bots.filter(func(b: Actor) -> bool: return b.global_position.distance_to(me.global_position) < 30.0)
	t.check(raid.bots.size() == before + 4 and near.size() >= 4, "bots spawns them around you")
	DevConsole.run("clear 30", raid, me, false)
	t.check(raid.bots.size() <= before and not raid.bots.any(
			func(b: Actor) -> bool: return b.global_position.distance_to(me.global_position) < 30.0),
			"clear removes the bots near you")
	DevConsole.run("storm here", raid, me, false)
	t.check(raid.weather.active() and raid.weather.strength_at(me.global_position) > 0.5, "storm here puts a storm on you")
	DevConsole.run("storm stop", raid, me, false)
	t.check(not raid.weather.active(), "storm stop ends it")
	t.check(DevConsole.run("event supply_pod", raid, me, false)[0].begins_with("Supply pod") and raid.event.kind == "supply_pod",
			"event starts a world event")
	DevConsole.run("event end", raid, me, false)
	t.check(raid.event.is_empty(), "event end ends it")
	DevConsole.run("skip event", raid, me, false)
	t.check(raid._event_in <= 0.0, "skip runs a timer out")
	me.health.health = 10.0
	DevConsole.run("heal", raid, me, false)
	t.check(me.health.health == me.health.max_health, "heal fills health")
	DevConsole.run("give medkit 2", raid, me, false)
	t.check(me.inventory.items.count("medkit") >= 2, "give puts items in the pack")
	var vehicles := raid.vehicles.size()
	DevConsole.run("vehicle bike_scrapper", raid, me, false)
	t.check(raid.vehicles.size() == vehicles + 1, "vehicle puts one in front of you")
	t.check(DevConsole.run("nonsense", raid, me, false)[0].begins_with("Unknown"), "an unknown command says so")
	raid.queue_free()
	await t.frames(1)
	DevMode.enabled = was
	DevMode.persist = persisted


static func _check_console_app(t: Node) -> void:
	var was := DevMode.enabled
	DevMode.persist = false
	DevMode.enabled = true
	var phone: Node = PhoneScript.new()
	t.add_child(phone)
	await t.frames(1)
	var ran: Array[String] = []
	phone.console_command.connect(func(line: String) -> void:
		ran.append(line)
		phone.add_console_lines(["done"]))
	phone.toggle()
	phone.open_app("console")
	await t.frames(1)
	t.check(phone._icons["console"].visible and phone.find_child("ConsoleEdit", true, false) != null,
			"the phone has a Console app with a line to type in while dev mode is on")
	phone.run_console("war 1")
	t.check(ran == ["war 1"] and phone.console_lines.slice(-2) == ["> war 1", "done"]
			and phone.console_history == ["war 1"], "a command goes to Main and its answer is printed")
	DevMode.enabled = false
	phone.refresh()
	t.check(not phone._icons["console"].visible, "with dev mode off the app is hidden")
	phone.toggle()
	phone.queue_free()
	DevMode.enabled = was
