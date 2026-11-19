extends RefCounted
## `--zones-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --zones-only` shows Ashfront's risk zones: a gate
## outpost from the field, and the burning core from its edge.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var camera := Camera3D.new()
	camera.far = 900.0
	raid.add_child(camera)
	camera.make_current()
	var gate: Node3D = raid.outposts[0]
	var inward := -Vector3(gate.global_position.x, 0, gate.global_position.z).normalized()
	camera.global_position = gate.global_position + inward * 32.0 + Vector3(0, 9, 0)
	camera.look_at(gate.global_position + Vector3(0, 2, 0))
	await v._settle(30)
	await v._shot(out_dir.path_join("zone_outpost.png"))
	var ground: float = raid.map.call("ground_height", 0.0, 72.0)
	camera.global_position = Vector3(0, ground + 14.0, 78.0)
	camera.look_at(Vector3(0, ground, 0))
	await v._settle(30)
	await v._shot(out_dir.path_join("zone_core.png"))
	raid.queue_free()
