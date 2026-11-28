extends RefCounted
## `-- <output_dir> --gates-only`, a mode `visual_check.gd` finds by itself.
## The Concourse's deploy gates: the terrace from where you walk up to it,
## each open gate close, a sealed one and a gate's write-up console, with a
## made-up war in each world so the gates have numbers to show. Add
## `--playtest` to see the launch's terrace (two worlds, two sealed gates).
## Prints the draw calls of each view. `--low` shoots at the Low graphics
## pick and also times the terrace view (graphics card time, averaged), to
## hold the gates against main on a laptop's settings.

const PlazaView := preload("res://core/social/plaza_view.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")


static func shoot(vc: Node, out_dir: String, args: PackedStringArray) -> void:
	var low := "--low" in args
	if low:
		GameSettings.persist = false
		GameSettings.set_value("graphics", GameSettings.GRAPHICS_LOW)
	var plaza := Worlds.social_world()
	var raid := Raid.new()
	vc.add_child(raid)
	raid.start(plaza, 5)
	var status := {}
	var levels := ["Skirmish", "Quiet", "All-out war", "Battle", "Quiet", "Skirmish"]
	var i := 0
	var routes := {}
	for world in Worlds.raid_worlds():
		status[world.id] = {"players": [14, 3, 27, 6, 0, 9][i % 6], "war": [0.4, 0.05, 0.95, 0.7, 0.0, 0.3][i % 6],
				"level": levels[i % 6], "bounty": 0, "event": "", "storm": ""}
		routes[world.id] = 7000 + i
		i += 1
	var view: CanvasLayer = PlazaView.new()
	view.setup(raid, routes, status)
	vc.add_child(view)
	var camera := Camera3D.new()
	camera.far = 1500.0
	camera.fov = 75.0
	vc.add_child(camera)
	camera.make_current()
	var line := -185.0
	var arches := maxi(4, Worlds.raid_worlds().size())
	var first := -float(arches - 1) * 0.5 * 22.0
	var views := [
		["wide", Vector3(0, 2.4, line + 44.0), Vector3(0, 7.5, line)],
		["open_first", Vector3(first + 3.0, 1.8, line + 13.0), Vector3(first, 5.5, line)],
		["open_second", Vector3(first + 22.0 - 3.0, 1.8, line + 13.0), Vector3(first + 22.0, 5.5, line)],
		["sealed", Vector3(-first - 2.0, 1.8, line + 13.0), Vector3(-first, 5.5, line)],
		["console", Vector3(first + 6.4, 1.7, line + 8.0), Vector3(first + 6.4, 1.2, line + 4.0)],
	]
	for v: Array in views:
		camera.look_at_from_position(v[1], v[2])
		await vc._settle(30)
		if low and v[0] == "wide":
			var vp := vc.get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vp, true)
			await vc._settle(5)
			var gpu := 0.0
			for f in 20:
				await RenderingServer.frame_post_draw
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			print("  wide at Low: graphics card %.2f ms a frame" % (gpu / 20.0))
		await vc._shot(out_dir.path_join("gates_%s.png" % v[0]))
		print("  %s: %d draw calls, %d objects" % [v[0],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	# A pulse halfway up the first gate's panels, its doorway lit, as when
	# someone has just stepped in.
	var bays: Array = raid.map.gate_bays()
	if not bays.is_empty():
		var bay: Dictionary = bays[0]
		for part: GeometryInstance3D in bay["meters"] + bay["fins"]:
			part.set_instance_shader_parameter("pulse", 0.45)
		if bay["glimpse"] != null:
			(bay["glimpse"] as GeometryInstance3D).set_instance_shader_parameter("lit", 1.0)
		view.set_process(false)
		camera.look_at_from_position(Vector3(first + 2.0, 2.0, line + 24.0), Vector3(first, 6.0, line))
		await vc._settle(10)
		await vc._shot(out_dir.path_join("gates_pulse.png"))
	# Standing in the first gate, its countdown half run, looking up at it.
	if not bays.is_empty() and bays[0]["portal"] != null:
		var gate: Node3D = bays[0]["portal"]
		view._light_arch(gate)
		view.step_walk_in(gate, view.gate_walk_in_time * 0.5)
		view._show_walk_in(gate)
		camera.look_at_from_position(gate.global_position + Vector3(0.6, 2.6, 4.0),
				gate.global_position + Vector3(0, 3.0, -6.0))
		await vc._settle(10)
		await vc._shot(out_dir.path_join("gates_inside.png"))
	view.queue_free()
	if low:
		GameSettings.reset()
	camera.queue_free()
	raid.queue_free()
	await vc._settle(2)
