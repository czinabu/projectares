extends RefCounted
## `--watch-read-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --watch-read-only` shoots the raised watch as it is read
## in a fight: in Frostline's snow (the brightest ground behind the card),
## a pistol in hand and the pack's list open, from the eyes and from behind,
## on both builds (`Human.BUILDS` "m" and "f") bare and under a heavy frame
## (its bracers are the nearest thing to the watch), and a close look at the
## worn watch on the wrist. Files: `read_<build>_<frame>_first.png`,
## `_third.png`, `_wrist.png`.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for build: String in ["m", "f"]:
		for frame: String in ["none", "frame_bulwark"]:
			var raid := Raid.new()
			v.add_child(raid)
			var kit: Array[String] = ["pistol_service", "rifle_scrap"]
			if frame != "none":
				kit.append(frame)
			raid.start(Worlds.get_world("frostline"), 42, kit)
			for bot in raid.bots:
				bot.get_node("Brain").set_physics_process(false)
				bot.global_position += Vector3(0, -200, 0)
			var p := raid.player
			Look.set_appearance(p, {"build": build, "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2",
					"feet": "Casual_2"})
			for id: String in ["medkit", "medkit", "scrap_metal", "scrap_metal", "frame_runner", "rifle_carbine"]:
				p.inventory.add_item(id)
			var controller := PlayerController.new()
			controller.setup(p)
			raid.add_child(controller)
			var hud := Hud.new()
			hud.setup(raid, controller)
			raid.add_child(hud)
			await v._settle(60)
			# Facing out over the snow, the sky behind the card.
			p.cmd.pitch = -0.1
			controller.wrist_raised = true
			controller.watch_focus = Hud.Wrist.SLOTS.find("pack")
			controller.watch_focus_moved = true
			controller.watch_open = "pack"
			controller.pack_pick = 0
			await v._settle(40)
			var tag := "%s_%s" % [build, "bare" if frame == "none" else "heavy"]
			await v._shot(out_dir.path_join("read_%s_first.png" % tag))
			controller.toggle_view()
			await v._settle(40)
			await v._shot(out_dir.path_join("read_%s_third.png" % tag))
			# A close look at the worn watch on the raised wrist, from the
			# eyes through a narrow lens of its own.
			controller.toggle_view()
			controller.watch_open = ""
			await v._settle(30)
			var worn: Node3D = hud.wrist._worn
			if worn != null and is_instance_valid(worn):
				var cam := Camera3D.new()
				cam.fov = 14.0
				raid.add_child(cam)
				cam.global_position = p.get_eye_position()
				cam.look_at(worn.global_position)
				cam.current = true
				await v._settle(6)
				await v._shot(out_dir.path_join("read_%s_wrist.png" % tag))
			raid.queue_free()
			await v._settle(5)
