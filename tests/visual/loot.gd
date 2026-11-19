extends RefCounted
## `--loot-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --loot-only`: looking at a bag and a cache through the
## visor with the pickup feed running, in first and third person.


## Loot at a glance (DESIGN.md section 3): a full bag looked at, with the
## pickup feed running from a cache just looted, through a Warden and a
## scrap visor, first person and third person.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for helmet: String in ["helm_warden", "visor_scav"]:
		var raid := Raid.new()
		v.add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "jetpack_mk1", "plate_light",
				helmet])
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -300, 0)
		var p := raid.player
		var at := Vector2.from_angle(TAU * 0.5 / 12.0) * 248.0
		p.global_position = raid._stand(Vector3(at.x, raid.map.call("ground_height", at.x, at.y), at.y))
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		var hud := Hud.new()
		hud.setup(raid, controller)
		raid.add_child(hud)
		await v._settle(30)
		var turn := Basis(Vector3.UP, controller.yaw)
		var cache := LootContainer.new()
		cache.setup(["scrap_metal", "blade_arc", "medkit"], false, "Cache")
		raid.add_child(cache)
		cache.global_position = p.global_position + turn * Vector3(-1.2, 0, -1.4)
		var bag := LootContainer.new()
		bag.setup(["rifle_scrap", "blade_arc", "helm_warden", "frame_trooper", "scrap_metal", "scrap_metal",
				"scrap_metal", "medkit", "medkit", "rifle_carbine", "power_cell", "wings_glide", "chip_blink",
				"reactor_core"].filter(func(id: String) -> bool: return ItemDB.has_item(id)), true, "Rook's bag")
		bag.scrip = 140
		raid.add_child(bag)
		bag.global_position = p.global_position + turn * Vector3(0.5, 0, -1.8)
		await v._settle(5)
		var to_bag := bag.global_position + Vector3(0, 0.3, 0) - p.get_eye_position()
		controller.yaw = atan2(-to_bag.x, -to_bag.z)
		controller.pitch = asin(to_bag.normalized().y)
		await v._settle(40)
		cache.interact(p)
		await v._settle(4)
		await v._shot(out_dir.path_join("loot_%s_first.png" % helmet))
		controller.view_mode = PlayerController.ViewMode.THIRD
		await v._settle(40)
		# Over the shoulder the aim leaves the eyes at another angle: walk the
		# pitch down until the bag is what F would loot again.
		for i in 24:
			if p.find_interactable() == bag:
				break
			controller.pitch -= 0.03
			await v._settle(3)
		await v._settle(20)
		cache.set_items(["scrap_metal", "chip_blink"])
		cache.interact(p)
		await v._settle(4)
		await v._shot(out_dir.path_join("loot_%s_third.png" % helmet))
		raid.queue_free()
		await v._settle(3)
