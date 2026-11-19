extends RefCounted
## `--lounge-only`, a mode `visual_check.gd` finds by itself: the lounge in
## each style from its doorway and from a seat, its small form, and its
## doorway from the hub (hall) and from the corridor (spine).

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BasePlan := preload("res://core/base/base_plan.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var base := HomeBase.new()
	var gear := ["rifle_carbine", "frame_trooper", "bike_scrapper", "medkit"]
	var worn := {"primary": "rifle_carbine"}
	base.show_gear(gear, worn, BaseUpgrades.full())
	v.add_child(base)
	var camera := Camera3D.new()
	camera.fov = 70.0
	base.add_child(camera)
	camera.make_current()
	await v._settle(20)
	for style: String in BasePlan.styles("lounge"):
		var plan := BasePlan.clean(null)
		plan["styles"]["lounge"] = style
		for whole: bool in [true, false]:
			var owned := BaseUpgrades.full()
			if not whole:
				owned.erase("lounge")
			base.show_gear(gear, worn, owned, plan)
			# Out of the way, so the shots are of the room.
			base.player.global_position = base.to_global(base.spawn_point)
			await v._settle(10)
			var xf := base.room_transform("lounge")
			var deep := -8.0 if whole else -4.2
			camera.look_at_from_position(xf * Vector3(-1.2, 2.2, 0.8), xf * Vector3(0.6, 1.0, deep))
			await v._settle(4)
			await v._shot(out_dir.path_join("lounge_%s%s.png" % [style, "" if whole else "_small"]))
			if whole:
				# Sat down, looking out of the window.
				camera.look_at_from_position(xf * Vector3(1.5, 1.2, -3.0), xf * Vector3(-0.5, 1.7, -9.75))
				await v._settle(4)
				await v._shot(out_dir.path_join("lounge_%s_seat.png" % style))
	for shape: String in ["hall", "spine"]:
		var plan := BasePlan.clean(null)
		plan["shape"] = shape
		base.show_gear(gear, worn, BaseUpgrades.full(), plan)
		base.player.global_position = base.to_global(base.spawn_point)
		await v._settle(12)
		var xf := base.room_transform("lounge")
		if HomeBase.corridor_socket(shape):
			# The spine's corridor is narrow: from across it, square on.
			camera.look_at_from_position(xf * Vector3(0.0, 1.6, 1.3), xf * Vector3(0.0, 1.3, -5.0))
		else:
			camera.look_at_from_position(xf * Vector3(1.2, 1.7, 4.0), xf * Vector3(0.0, 1.4, -2.0))
		await v._settle(4)
		await v._shot(out_dir.path_join("lounge_door_%s.png" % shape))
	base.queue_free()
	await v._settle(2)
