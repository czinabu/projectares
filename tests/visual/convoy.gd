extends RefCounted
## `--convoy-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --convoy-only` shows a Dune Sea convoy (DESIGN.md "The
## Dune Sea (part three)"): the hauler and its escort on the road, close up
## on an escort rover's roof gunner, and the hauler stopped with its crates
## spilled.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("dunes"), 42)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	player.global_position += Vector3(0, -300, 0)
	var above := func(at: Vector3, lift: float) -> Vector3:
		return Vector3(at.x, float(raid.map.call("ground_height", at.x, at.z)) + lift, at.z)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 1500.0
	raid.add_child(cam)
	cam.current = true
	await v._settle(20)
	raid.start_event("convoy")
	var convoy: Dictionary = raid.convoy
	var hauler: Node3D = convoy.vehicles[0]
	var escort: Node3D = convoy.vehicles[1]
	await v._settle(360)
	var forward := -hauler.global_transform.basis.z
	var side := forward.cross(Vector3.UP).normalized()
	var mid := (hauler.global_position + escort.global_position) * 0.5
	cam.look_at_from_position(above.call(mid + side * 11.0 + forward * 12.0, 4.0), mid + Vector3(0, 1.0, 0))
	await v._settle(2)
	await v._shot(out_dir.path_join("convoy_1_road.png"))
	# Close on the escort rover's roof gunner.
	for bot in raid.bots:
		bot.get_node("Brain").process_mode = Node.PROCESS_MODE_DISABLED
	for vehicle: Node3D in convoy.vehicles:
		vehicle.set_physics_process(false)
	var at := escort.global_position
	var back := escort.global_transform.basis.z
	cam.look_at_from_position(at + back * 6.0 - side * 4.0 + Vector3(0, 3.2, 0), at + Vector3(0, 1.8, 0))
	await v._settle(6)
	await v._shot(out_dir.path_join("convoy_2_gunner.png"))
	# The hauler stopped: its driver dropped, its crates on the sand.
	for vehicle: Node3D in convoy.vehicles:
		vehicle.set_physics_process(true)
	Combat.deal(convoy.drivers[0], DamageInfo.make(9999.0, null, "bullet"))
	await v._settle(40)
	at = hauler.global_position
	cam.look_at_from_position(above.call(at + side * 12.0 + forward * 6.0, 7.0), at)
	await v._settle(4)
	await v._shot(out_dir.path_join("convoy_3_stopped.png"))
	raid.queue_free()
	await v._settle(4)
