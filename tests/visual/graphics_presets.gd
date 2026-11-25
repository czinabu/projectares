extends RefCounted
## `-- <output_dir> --graphics-presets-only [world ...]`, a mode
## `visual_check.gd` finds by itself: the same view through the player's own
## camera at every Graphics quality pick (`GameSettings.GRAPHICS`, all but
## Custom), in Ashfront and Frostline by default. Each shot is
## <world>_<n>_<pick>.png, and presets.txt beside them lists each shot's
## average graphics card time, draw calls and primitives, to compare what a
## pick saves. (On a software renderer, which draws on the processor, the
## times are far slower than any graphics card but rank the picks the same.)

const GameSettings := preload("res://core/settings/game_settings.gd")
## Frames each pick is timed over, after it settles.
const TIMED := 6


static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	GameSettings.persist = false
	var worlds: Array[String] = []
	for i in range(args.find("--graphics-presets-only") + 1, args.size()):
		if not args[i].begins_with("-") and Worlds.get_world(args[i]) != null:
			worlds.append(args[i])
	if worlds.is_empty():
		worlds = ["ashfront", "frostline"]
	var vp := v.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var report := PackedStringArray()
	report.append("graphics card: %s (%s)" % [RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method()])
	for world_id: String in worlds:
		var raid := Raid.new()
		v.add_child(raid)
		raid.start(Worlds.get_world(world_id), 42)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
		var controller := PlayerController.new()
		controller.setup(raid.player)
		raid.add_child(controller)
		for i in 40:
			await v.get_tree().process_frame
		var spawn := raid.player.global_position
		var to_mid := Vector3(-spawn.x, 0.0, -spawn.z)
		if to_mid.length() < 20.0:
			to_mid = Vector3(0, 0, -20)
		raid.player.set_physics_process(false)
		controller.yaw = atan2(-to_mid.x, -to_mid.z)
		controller.pitch = -0.04
		for pick: int in GameSettings.GRAPHICS_CUSTOM:
			GameSettings.set_value("graphics", pick)
			for i in 30:
				await v.get_tree().process_frame
			var gpu := 0.0
			var draws := 0
			var prims := 0
			for i in TIMED:
				await RenderingServer.frame_post_draw
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			var name := "%s_%d_%s" % [world_id, pick, String(GameSettings.GRAPHICS[pick][0]).get_slice(" ", 0).to_lower()]
			report.append("%s gpu=%.1f ms draws=%d primitives=%d" % [name, gpu / TIMED, draws / TIMED, prims / TIMED])
			print(report[-1])
			await RenderingServer.frame_post_draw
			v.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
		raid.queue_free()
		for i in 5:
			await v.get_tree().process_frame
	GameSettings.reset()
	var file := FileAccess.open(out_dir.path_join("presets.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(report) + "\n")
