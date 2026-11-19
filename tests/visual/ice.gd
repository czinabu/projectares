extends RefCounted
## `--ice-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --ice-only` shows Frostline's lake: the dark thin ice
## in its middle from above, and a hole broken through it beside fresh
## cracks, close up.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	const FrostMap := preload("res://worlds/frostline/map.gd")
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("frostline"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	raid.player.set_physics_process(false)
	raid.player.visible = false
	var x := FrostMap.centre(FrostMap.LAKE_Z)
	var mid := Vector3(x, float(raid.map.call("ground_height", x, FrostMap.LAKE_Z)), FrostMap.LAKE_Z)
	var camera := Camera3D.new()
	camera.far = 900.0
	raid.add_child(camera)
	camera.make_current()
	camera.global_position = mid + Vector3(-30.0, 38.0, 70.0)
	camera.look_at(mid)
	await v._settle(30)
	await v._shot(out_dir.path_join("ice_lake.png"))
	var hole := mid + Vector3(4.0, 0.0, 6.0)
	raid.ice_holes.append([hole, raid.clock])
	raid.ice_changed.emit()
	raid.ice_cracked.emit(hole + Vector3(7.0, 0.0, 3.0), 2)
	camera.global_position = hole + Vector3(-5.0, 6.0, 12.0)
	camera.look_at(hole + Vector3(2.0, 0.0, 1.0))
	await v._settle(20)
	await v._shot(out_dir.path_join("ice_hole.png"))
	raid.queue_free()
