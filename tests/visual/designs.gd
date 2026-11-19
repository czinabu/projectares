extends RefCounted
## `--designs-only`, a mode `visual_check.gd` finds by itself.
## Before the home-base pass: that pass is most of the runtime.
## `--designs-only`: every hub shape and every room style.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BasePlan := preload("res://core/base/base_plan.gd")


## Every hub shape (`BasePlan.SHAPES`) from over the door and from above, and
## every room in every style (`BasePlan.STYLES`), whole and in its small form.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var base := HomeBase.new()
	var gear := ["rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher", "rifle_scrap", "blade_arc",
			"hammer_breaker", "knife_gutter", "axe_splitter", "spear_lancer", "pistol_machine", "pistol_hand_cannon",
			"frame_runner", "frame_trooper", "frame_bulwark", "helm_warden", "helm_seeker", "helm_ember", "helm_spotter",
			"jetpack_mk2", "boots_thruster", "wings_glide", "chip_blink", "chip_barrier", "chip_pulse", "bike_scrapper",
			"bike_raider", "medkit", "medkit", "scrap_metal", "alloy_ingot", "reactor_core", "lattice_shard"]
	var worn := {"primary": "dmr_longshot", "frame": "frame_bulwark", "helmet": "helm_warden", "vehicle": "bike_raider"}
	base.show_gear(gear, worn, BaseUpgrades.full())
	v.add_child(base)
	var camera := Camera3D.new()
	camera.fov = 75.0
	base.add_child(camera)
	camera.make_current()
	await v._settle(20)
	if "--plan-only" in OS.get_cmdline_user_args():
		await v._plan_table_shots(base, out_dir)
		base.queue_free()
		return
	if "--finishes-only" in OS.get_cmdline_user_args():
		await _finish_shots(v, base, camera, gear, worn, out_dir)
		base.queue_free()
		return
	for shape: String in BasePlan.SHAPES:
		var plan := BasePlan.clean(null)
		plan["shape"] = shape
		base.show_gear(gear, worn, BaseUpgrades.full(), plan)
		base.player.global_position = base.to_global(base.spawn_point)
		await v._settle(12)
		var half := base.room_size * 0.5
		camera.look_at_from_position(Vector3(0, base.room_size.y - 1.0, half.z - 0.8), Vector3(0, 1.0, -half.z * 0.6))
		await v._settle(4)
		await v._shot(out_dir.path_join("shape_%s.png" % shape))
		camera.look_at_from_position(Vector3(0.01, 42.0, -4.0), Vector3(0, 0, -4.0))
		await v._settle(4)
		await v._shot(out_dir.path_join("shape_%s_top.png" % shape))
	for room: String in BasePlan.STYLES:
		for style: String in BasePlan.STYLES[room]:
			var plan := BasePlan.clean(null)
			plan["styles"][room] = style
			for whole: bool in [true, false]:
				var owned := BaseUpgrades.full()
				if not whole:
					owned.erase(str(BasePlan.ROOMS[room]["opens"]))
				if not whole and str(BasePlan.ROOMS[room]["opens"]) == "":
					continue
				base.show_gear(gear, worn, owned, plan)
				await v._settle(10)
				var xf := base.room_transform(room)
				camera.look_at_from_position(xf * Vector3(0.0, 3.0, 3.4), xf * Vector3(0.0, 1.0, -6.5 if whole else -4.0))
				await v._settle(4)
				await v._shot(out_dir.path_join("style_%s_%s%s.png" % [room, style, "" if whole else "_small"]))
	base.queue_free()
	await v._settle(2)


## Every finish (`BasePlan.FINISHES`) on the hub, from over the door, and on
## the armory and the garage from their doorways.
static func _finish_shots(v: Node, base: HomeBase, camera: Camera3D, gear: Array, worn: Dictionary, out_dir: String) -> void:
	for finish: String in BasePlan.FINISHES:
		var plan := BasePlan.clean(null)
		for area: String in BasePlan.areas():
			plan["finishes"][area] = finish
		base.show_gear(gear, worn, BaseUpgrades.full(), plan)
		base.player.global_position = base.to_global(base.spawn_point)
		await v._settle(12)
		var half := base.room_size * 0.5
		camera.look_at_from_position(Vector3(0, base.room_size.y - 1.0, half.z - 0.8), Vector3(0, 1.0, -half.z * 0.6))
		await v._settle(4)
		await v._shot(out_dir.path_join("finish_%s_hub.png" % finish))
		for room: String in ["armory", "garage"]:
			var xf := base.room_transform(room)
			camera.look_at_from_position(xf * Vector3(0.0, 3.0, 3.4), xf * Vector3(0.0, 1.0, -6.5))
			await v._settle(4)
			await v._shot(out_dir.path_join("finish_%s_%s.png" % [finish, room]))
