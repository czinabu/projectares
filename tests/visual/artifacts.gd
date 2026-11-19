extends RefCounted
## `--artifacts-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --artifacts-only` shows the artifacts at work: the
## watch's artifact icon, Phase Cloak in first and third person, the
## Time Rewind trail and the Static Bloom ring.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for relic: String in ["artifact_cloak", "artifact_rewind", "artifact_bloom"]:
		var raid := Raid.new()
		v.add_child(raid)
		var kit: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", relic]
		raid.start(Worlds.get_world("ashfront"), 42, kit)
		v._armed(raid)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, 0, 400)
		var p := raid.player
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		var hud := Hud.new()
		hud.setup(raid, controller)
		raid.add_child(hud)
		await v._settle(60)
		var tag := relic.trim_prefix("artifact_")
		if relic == "artifact_cloak":
			controller.wrist_raised = true
			controller.watch_focus = Hud.Wrist.SLOTS.find("artifact")
			controller.watch_focus_moved = true
			await v._settle(30)
			await v._shot(out_dir.path_join("artifact_watch.png"))
			controller.wrist_raised = false
			await v._settle(20)
			await v._shot(out_dir.path_join("cloak_first_off.png"))
			# Long enough to outlast a slow software render.
			p.artifact.duration = 600.0
			p.artifact.activate()
			await v._settle(30)
			await v._shot(out_dir.path_join("cloak_first_on.png"))
			controller.toggle_view()
			await v._settle(30)
			await v._shot(out_dir.path_join("cloak_third_on.png"))
			p.artifact.on_attack()
			await v._settle(30)
			await v._shot(out_dir.path_join("cloak_third_off.png"))
		elif relic == "artifact_rewind":
			controller.toggle_view()
			await v._settle(30)
			var start := p.global_position
			for i in 40:
				p.global_position = start + Vector3(0.15 * i, 0, 0.1 * i)
				await v.get_tree().physics_frame
			p.artifact.activate()
			await v._settle(6)
			await v._shot(out_dir.path_join("rewind_trail.png"))
		else:
			controller.toggle_view()
			await v._settle(30)
			p.artifact.activate()
			await v._settle(2)
			await v._shot(out_dir.path_join("bloom_ring.png"))
		raid.queue_free()
		await v._settle(3)
