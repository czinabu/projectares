extends RefCounted
## The `depot_station` checks: a depot is a station you walk up to (a pad,
## a solid uplink terminal at its back, a mast), not a see-through box, and
## the pad's middle stays open to stand and bank on. The test runner finds
## this file by itself and calls `run(t)`.


static func run(t: Node) -> void:
	print("Depot stations")
	var depot := Depot.new()
	t.add_child(depot)
	var terminal := depot.get_node_or_null("Terminal") as StaticBody3D
	t.check(depot.get_node_or_null("Pad") is MeshInstance3D, "a depot has a pad to stand on")
	t.check(terminal != null and terminal.collision_layer == Actor.LAYER_WORLD,
			"its uplink terminal is solid, like any other prop")
	var see_through := false
	for child in depot.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		var mat := mesh.surface_get_material(0) as BaseMaterial3D if mesh != null else null
		see_through = see_through or (mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	t.check(not see_through, "the greybox has no see-through box left")
	if terminal != null:
		var reach := absf(terminal.position.z) - Depot.TERMINAL_SIZE.z * 0.5
		t.check(reach > 2.5 and absf(terminal.position.z) + Depot.TERMINAL_SIZE.z * 0.5 <= depot.size.z * 0.5,
				"the terminal stands at the pad's back edge, leaving the middle open")
	depot.free()

	# Turned by its map: the terminal goes on the side the map asks for.
	var raid: Raid = await t._new_raid(44, false)
	var turned := 0
	for d: Depot in raid.depots:
		if not is_zero_approx(d.rotation.y):
			turned += 1
	t.check(turned > 0, "maps turn their depots so the terminal backs onto something")
	# Banking from the middle of a turned pad still works (the terminal is clear of it).
	var p := raid.player
	p.inventory.add_item("reactor_core")
	var target := raid.depots[0]
	for d: Depot in raid.depots:
		if not is_zero_approx(d.rotation.y):
			target = d
			break
	p.global_position = target.global_position - Vector3(0, 1.8, 0)
	await t.frames(30)
	t.check(target.progress_for(p) > 0.0, "standing in the middle of a turned pad starts the upload")
	await t._end_raid(raid)
