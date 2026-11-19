extends RefCounted
## `--hub-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --arena-only` shoots just the arena.
## `-- <output_dir> --hub-only` walks round the Concourse from fixed spots
## and prints what a frame of it costs to draw.


## The Concourse from the spots people stand: arriving, at the gates, down
## Market Row, in the civic square and the residences, from a rim lookout,
## and from high above. Prints the draw calls
## and objects of each view, the frame cost that grows with the map.
static func shoot(vc: Node, out_dir: String, _args: PackedStringArray) -> void:
	var plaza := Worlds.social_world()
	var raid := Raid.new()
	vc.add_child(raid)
	raid.start(plaza, 5)
	var map: Node3D = raid.map
	var camera := Camera3D.new()
	camera.far = maxf(1500.0, float(map.get_meta("view_far", 1500.0)))
	camera.fov = 75.0
	vc.add_child(camera)
	camera.make_current()
	var arrival: Vector3 = map.get("ARRIVAL") if map.get("ARRIVAL") != null else Vector3.ZERO
	var views := [
		["arrival", arrival + Vector3(0, 1.7, 6), Vector3(0, 12, -10)],
		["plaza", Vector3(9, 1.7, 22), Vector3(-2, 2.5, -8)],
		["gates", Vector3(0, 2.2, -150), Vector3(0, 6, -190)],
		["market", Vector3(0, 1.8, 64), Vector3(0, 3, 140)],
		["civic", Vector3(108, 2.0, 4), Vector3(160, 4, 0)],
		["residences", Vector3(-108, 2.0, -4), Vector3(-160, 4, 0)],
		["lookout", Vector3(161, 1.7, -161), Vector3(0, 8, 0)],
		["skyline", Vector3(0, 1.7, 40), Vector3(-40, 60, -200)],
		["look_up", Vector3(60, 1.7, -60), Vector3(300, 380, -500)],
		["rail", Vector3(-200, 1.7, 120), Vector3(-420, -120, 260)],
		["monorail", Vector3(150, 1.7, 150), Vector3(260, 60, 250)],
		["tower_foot", Vector3(37, 1.7, -93), Vector3(46, 9, -111)],
		["overview", Vector3(260, 220, 260), Vector3(0, 0, 0)],
	]
	for v: Array in views:
		camera.look_at_from_position(v[1], v[2])
		await vc._settle(20)
		await vc._shot(out_dir.path_join("hub_%s.png" % v[0]))
		print("  %s: %d draw calls, %d objects" % [v[0],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	camera.queue_free()
	raid.queue_free()
	await vc._settle(2)
