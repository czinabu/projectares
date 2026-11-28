extends RefCounted
## `--lane-walls-only`, a mode `visual_check.gd` finds by itself: the starter
## bunker's corridor and test lane, from the hub and from the counter, to see
## that walls close them all round (no void, no range hall showing past them).

const BasePlan := preload("res://core/base/base_plan.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var base := HomeBase.new()
	var gear := ["rifle_carbine"]
	base.show_gear(gear, {"primary": "rifle_carbine"}, [])
	v.add_child(base)
	var camera := Camera3D.new()
	camera.fov = 75.0
	base.add_child(camera)
	camera.make_current()
	await v._settle(20)
	for shape: String in ["hall", "spine"]:
		var plan := BasePlan.clean(null)
		plan["shape"] = shape
		base.show_gear(gear, {"primary": "rifle_carbine"}, [], plan)
		base.player.global_position = base.to_global(base.spawn_point)
		await v._settle(12)
		var hub_back := base.room_size.z * 0.5
		var lane := base.range_from()
		# Down the corridor from the hub's back wall.
		camera.look_at_from_position(Vector3(0, 1.7, -hub_back + 1.5), Vector3(0, 1.5, -lane - 6.0))
		await v._settle(4)
		await v._shot(out_dir.path_join("lane_walls_%s_corridor.png" % shape))
		# Half way down, looking at each wall.
		var half := -(hub_back + lane) * 0.5 - 2.0
		camera.look_at_from_position(Vector3(0.4, 1.8, half + 1.5), Vector3(-2.0, 1.6, half - 1.5))
		await v._settle(4)
		await v._shot(out_dir.path_join("lane_walls_%s_left.png" % shape))
		camera.look_at_from_position(Vector3(-0.4, 1.8, half + 1.5), Vector3(2.0, 1.6, half - 1.5))
		await v._settle(4)
		await v._shot(out_dir.path_join("lane_walls_%s_right.png" % shape))
		# At the lane's counter, looking back up and to the side.
		camera.look_at_from_position(Vector3(0.9, 2.6, -lane - 1.0), Vector3(-1.2, 2.4, -lane + 3.0))
		await v._settle(4)
		await v._shot(out_dir.path_join("lane_walls_%s_back.png" % shape))
	base.queue_free()
	await v._settle(2)
