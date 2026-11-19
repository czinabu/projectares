extends RefCounted
## `--watch-only`, a mode `visual_check.gd` finds by itself.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for helmet: String in ["", "helm_seeker"]:
		var raid := Raid.new()
		v.add_child(raid)
		var world := Worlds.get_world("ashfront")
		var kit: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light"]
		if helmet != "":
			kit.append(helmet)
		raid.start(world, 42, kit)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
		raid.state_for(raid.player).stowed.append("bike_raider")
		var p := raid.player
		# Loot in the pack for the carousel: two weapons, an artifact, scrap.
		for id: String in ["rifle_carbine", "knife_gutter", "artifact_cloak", "scrap_metal"]:
			p.inventory.add_item(id)
		p.health.health = p.health.max_health * 0.6
		p.stamina = p.max_stamina * 0.4
		p.flight.heat = p.flight.max_heat * 0.55
		p.flight.cool_per_sec = 0.0
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		var hud := Hud.new()
		hud.setup(raid, controller)
		raid.add_child(hud)
		await v._settle(60)
		controller.wrist_raised = true
		await v._settle(30)
		var tag := "helmet" if helmet != "" else "bare"
		await v._shot(out_dir.path_join("watch_first_%s.png" % tag))
		if helmet == "":
			for i in Hud.Wrist.SLOTS.size():
				controller.watch_focus = i
				controller.watch_focus_moved = true
				await v._settle(4)
				await v._shot(out_dir.path_join("watch_look_%s.png" % Hud.Wrist.SLOTS[i]))
			# The Status icons and the pack opened with a click: the tabletop map
			# with a waypoint set, Standing's first page, and the pack's list.
			for opened: String in ["map", "standing", "pack"]:
				controller.watch_focus = Hud.Wrist.SLOTS.find(opened)
				controller.watch_open = opened
				if opened == "map":
					controller.map_pick = 1
					await v._settle(4)
					controller.click_watch()
				await v._settle(10)
				await v._shot(out_dir.path_join("watch_open_%s.png" % opened))
				controller.watch_open = ""
			# The weapon carousel on a weapon in the pack.
			controller.watch_focus = Hud.Wrist.SLOTS.find("weapon")
			controller.watch_open = "weapon"
			controller.weapon_pick = 3
			await v._settle(20)
			await v._shot(out_dir.path_join("watch_carousel_pack_weapon.png"))
			controller.watch_open = ""
			controller.watch_focus_moved = false
		controller.toggle_view()
		await v._settle(40)
		await v._shot(out_dir.path_join("watch_third_%s.png" % tag))
		if helmet == "":
			# Third person on the carousel, then the summon: the carbine
			# digitizing into the hand, part way and done, in both views.
			controller.watch_focus = Hud.Wrist.SLOTS.find("weapon")
			controller.watch_focus_moved = true
			controller.watch_open = "weapon"
			controller.weapon_pick = 3
			await v._settle(20)
			await v._shot(out_dir.path_join("watch_carousel_third.png"))
			controller.watch_open = ""
			controller.wrist_raised = false
			await v._settle(30)
			raid.summon(p, "rifle_carbine")
			# Held half way through materializing for the picture.
			p.materialize_time = 30.0
			p.materialize_left = 15.0
			await v._settle(10)
			await v._shot(out_dir.path_join("summon_third_half.png"))
			p.materialize_left = 0.0
			await v._settle(30)
			await v._shot(out_dir.path_join("summon_third_done.png"))
			# Stored back: the same light, the other way.
			raid.store(p, "rifle_carbine")
			p.dematerialize_time = 30.0
			p.dematerialize_left = 15.0
			await v._settle(10)
			await v._shot(out_dir.path_join("store_third_half.png"))
			p.dematerialize_left = 0.0
			await v._settle(10)
			controller.toggle_view()
			raid.state_for(p).summon_ready_at = -INF
			await v._settle(40)
			raid.summon(p, "rifle_scrap")
			p.materialize_time = 30.0
			p.materialize_left = 15.0
			await v._settle(10)
			await v._shot(out_dir.path_join("summon_first_half.png"))
			p.materialize_left = 0.0
			await v._settle(10)
			raid.store(p, "rifle_scrap")
			p.dematerialize_time = 30.0
			p.dematerialize_left = 15.0
			await v._settle(10)
			await v._shot(out_dir.path_join("store_first_half.png"))
			p.dematerialize_left = 0.0
			p.cmd.pitch = -0.25
			await v._settle(10)
			raid.ping(p)
			await v._settle(20)
			await v._shot(out_dir.path_join("ping_first.png"))
		raid.queue_free()
		await v._settle(3)
	await v._base_watch_shots(out_dir)
