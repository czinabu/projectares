extends RefCounted
## `--attachments-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --attachments-only` shoots the gunsmith bench with each
## primary kitted out, and the view down a scope and a reflex sight.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	await _aim_shots(v, out_dir)
	if "--aim-only" in OS.get_cmdline_user_args():
		return
	var kits := {
		"rifle_scrap": ["optic_reflex", "muzzle_compensator", "grip_vertical", "mag_extended"],
		"rifle_carbine": ["optic_scope", "muzzle_suppressor", "grip_angled", "mag_drum"],
		"smg_stinger": ["optic_reflex", "muzzle_booster", "grip_vertical", "mag_quick"],
		"dmr_longshot": ["optic_longscope", "muzzle_suppressor", "grip_angled", "mag_extended"],
		"shotgun_breacher": ["optic_reflex", "muzzle_compensator", "grip_vertical", "mag_drum"],
	}
	var every: Array = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "attachment"):
			every.append(id)
	for primary: String in kits:
		var loadout := {"primary": primary}
		for id: String in kits[primary]:
			loadout[Loadout.attachment_slot(id)] = id
		var base := HomeBase.new()
		var stash: Array = every.duplicate()
		stash.append(primary)
		base.show_gear(stash, loadout, BaseUpgrades.full())
		v.add_child(base)
		var camera := Camera3D.new()
		camera.fov = 50.0
		base.add_child(camera)
		camera.make_current()
		base.player.global_position = Vector3(0, 0.1, 6)
		await v._settle(20)
		# Views in the bench's own frame (+Z is where you stand to use it).
		var bench := base.bench_transform()
		if primary == "rifle_scrap":
			camera.look_at_from_position(bench * Vector3(-0.6, 1.9, 3.2), bench * Vector3(0, 1.4, 0))
			await v._settle(4)
			await v._shot(out_dir.path_join("bench_overview.png"))
		camera.look_at_from_position(bench * Vector3(-0.25, 1.45, 1.0), bench * Vector3(0, 1.2, 0.0))
		await v._settle(4)
		await v._shot(out_dir.path_join("bench_%s.png" % primary))
		base.queue_free()
		await v._settle(2)


## Aiming down each optic in first person, in a raid, and with iron sights.
static func _aim_shots(v: Node, out_dir: String) -> void:
	for kit: Array in [["rifle_carbine", "optic_scope", "muzzle_suppressor"], ["smg_stinger", "optic_reflex"],
			["dmr_longshot", "optic_longscope"], ["rifle_carbine"]]:
		var raid := Raid.new()
		v.add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, kit)
		v._armed(raid)
		for bot in raid.bots:
			bot.queue_free()
		var controller := PlayerController.new()
		controller.setup(raid.player)
		raid.add_child(controller)
		controller.set_physics_process(false)
		raid.player.cmd.yaw = controller.yaw
		await v._settle(20)
		var name: String = kit[1] if kit.size() > 1 else "iron_sights"
		for aiming: bool in [false, true]:
			raid.player.cmd.secondary = aiming
			await v._settle(40)
			await v._shot(out_dir.path_join("aim_%s_%s.png" % [name, "on" if aiming else "off"]))
		raid.queue_free()
		await v._settle(2)
