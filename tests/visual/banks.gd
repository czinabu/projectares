extends RefCounted
## `--banks-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --banks-only`: the depots (uplink stations) and the gate
## outposts' safe zones, in every world that has them: a gate from the field
## and from inside the yard, a depot up close and from across a site.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	for id: String in ["ashfront", "frostline", "marsh"]:
		var raid := Raid.new()
		v.add_child(raid)
		raid.start(Worlds.get_world(id), 42)
		v._armed(raid)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -300, 0)
		raid.player.visible = false
		var camera := Camera3D.new()
		camera.fov = 70.0
		camera.far = 1500.0
		raid.add_child(camera)
		camera.make_current()
		var shots := []
		if not raid.outposts.is_empty():
			var gate: Node3D = raid.outposts[0]
			var at := gate.global_position
			var dir := Vector3(at.x, 0, at.z).normalized()
			# From the field, walking up to the gate; and from inside, looking out.
			var field := at - dir * 30.0
			field.y = float(raid.map.call("ground_height", field.x, field.z)) + 2.0
			shots.append(["gate_outside", field, at + Vector3(0, 3.0, 0)])
			shots.append(["gate_inside", at + dir * 4.0 + Vector3(0, 1.8, 0), at - dir * 20.0 + Vector3(0, 3.0, 0)])
			shots.append(["gate_depot", at - dir * 4.0 + dir.cross(Vector3.UP) * 3.0 + Vector3(0, 1.8, 0),
					at + dir * 9.5 + Vector3(0, -0.5, 0)])
		# A depot out in the world: up close, from the pad's front, then from far.
		var depot := raid.depots[raid.depots.size() - 1] as Depot
		var back := depot.global_basis.z
		var floor_at := depot.global_position - Vector3(0, depot.size.y * 0.5, 0)
		shots.append(["depot_close", floor_at - back * 5.5 + depot.global_basis.x * 2.0 + Vector3(0, 1.7, 0),
				floor_at + back * 2.5 + Vector3(0, 1.0, 0)])
		shots.append(["depot_far", floor_at - back * 40.0 + depot.global_basis.x * 15.0 + Vector3(0, 4.0, 0),
				floor_at + Vector3(0, 4.0, 0)])
		for shot: Array in shots:
			camera.look_at_from_position(shot[1], shot[2])
			await v._settle(40)
			await v._shot(out_dir.path_join("%s_%s.png" % [id, shot[0]]))
		raid.queue_free()
		await v._settle(5)
