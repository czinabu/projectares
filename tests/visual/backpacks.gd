extends RefCounted
## `--backpacks-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --backpacks-only` shoots each backpack being worn, with
## and without a jetpack, and the gear room's hooks.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for rig: String in ["", "jetpack_mk1"]:
		for id: String in ["pack_rucksack", "pack_hauler", "pack_mule"]:
			var kit: Array[String] = ["rifle_carbine", "blade_scrap", "frame_trooper", id]
			if rig != "":
				kit.append(rig)
			var raid := Raid.new()
			v.add_child(raid)
			raid.start(Worlds.get_world("ashfront"), 42, kit)
			v._armed(raid)
			for bot in raid.bots:
				bot.get_node("Brain").set_physics_process(false)
				bot.global_position += Vector3(0, -200, 0)
			var camera := Camera3D.new()
			camera.fov = 50.0
			raid.add_child(camera)
			camera.make_current()
			var p := raid.player
			await v._settle(30)
			p.set_physics_process(false)
			var at := p.global_position
			var back := p.global_transform.basis.z
			var side := p.global_transform.basis.x
			var views := {
				"back": at + back * 2.4 + side * 0.9 + Vector3(0, 1.5, 0),
				"side": at + side * 2.4 + back * 0.4 + Vector3(0, 1.2, 0),
			}
			for view: String in views:
				camera.look_at_from_position(views[view], at + Vector3(0, 0.95, 0))
				await v._settle(6)
				await v._shot(out_dir.path_join("pack_%s%s_%s.png" % [id, "_" + rig if rig != "" else "", view]))
			raid.queue_free()
			await v._settle(3)
	# At home: the packs on their hooks by the gear room's way in, the
	# hauler worn.
	for upgrades: Array in [[], BaseUpgrades.full()]:
		var base := HomeBase.new()
		base.show_gear(["pack_rucksack", "pack_hauler", "pack_mule", "rifle_carbine", "frame_trooper"],
				{"pack": "pack_hauler", "primary": "rifle_carbine", "frame": "frame_trooper"}, upgrades)
		v.add_child(base)
		await v._settle(30)
		var camera := Camera3D.new()
		camera.fov = 60.0
		base.add_child(camera)
		camera.make_current()
		var hook := base.spot_transform("pack_hooks", 0)
		camera.look_at_from_position(hook.origin + hook.basis.z * 5.0 + hook.basis.x * 1.5 + Vector3(0, 0.8, 0), hook.origin)
		await v._settle(10)
		await v._shot(out_dir.path_join("pack_hooks_%s.png" % ("full" if not upgrades.is_empty() else "starter")))
		base.queue_free()
		await v._settle(3)
