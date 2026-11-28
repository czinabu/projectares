extends RefCounted
## Checks for Ashfront's kit-clad landmarks (`worlds/ashfront/kit_dress.gd`,
## docs/systems/marsh-and-ashfront.md): built only where `Look` is on, a few
## draws each, panels hugging their box, tank wrecks drawn as a tank, walls
## faced, the hill's mast a lattice, the giants plated and the skyline one
## mesh with a broken roofline.

const KIT_DRESS := preload("res://worlds/ashfront/kit_dress.gd")


static func run(t: Node) -> void:
	print("Kit dress: Ashfront's landmarks clad in kit pieces")
	# A face clad on its own: every panel stays within `SKIN` of the face.
	var kit := KitMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var none := func(_i: int, _b: float, _t: float) -> bool: return false
	KIT_DRESS.clad_face(kit, Vector3.ZERO, Vector3.FORWARD, Vector3.UP, 12.0, 9.0, 3, none, rng)
	var mesh := kit.build({})
	var box := mesh.get_aabb()
	t.check(mesh.get_surface_count() >= 1 and box.size.x > 11.5 and box.size.y > 8.5,
			"a clad face is covered across and up")
	t.check(-box.position.z <= KIT_DRESS.SKIN + 0.01 and box.end.z <= 0.6,
			"and no panel stands out past the skin")
	# The map with Look on.
	var was_on: bool = Look.enabled
	Look.enabled = true
	var map: Node3D = Worlds.get_world("ashfront").create_map()
	t.add_child(map)
	await t.frames(2)
	var forge := map.find_child("ForgeClad", true, false) as MeshInstance3D
	t.check(forge != null and forge.mesh.get_surface_count() <= 6, "the Forge is clad, in a few draws")
	var wrecks := map.find_child("WreckClad", true, false) as MeshInstance3D
	t.check(wrecks != null and wrecks.mesh.get_surface_count() <= 8, "the wrecks' hulls are plated, all in one node")
	var tanks := 0
	var hidden := true
	for wreck: Dictionary in map.get("_wrecks"):
		if int(wreck.get("kind", -1)) != 0:
			continue
		tanks += 1
		for part: Array in wreck["boxes"]:
			hidden = hidden and not (part[3] as MeshInstance3D).visible
	t.check(tanks > 0 and hidden, "a tank wreck is drawn as a tank model, its boxes left as collision only")
	var walls := map.find_child("WallClad", true, false) as MeshInstance3D
	t.check(walls != null and walls.mesh.get_surface_count() <= 8, "the walls are faced in kit panels, all in one node")
	var mast: StaticBody3D = map.get("_mast")
	t.check(mast != null and not (mast.get_child(1) as MeshInstance3D).visible, "the hill's mast is drawn as a lattice, not a block")
	var clutter: Array = map.get("_clutter")
	var piles := map.find_child("ClutterClad", true, false) as MeshInstance3D
	t.check(clutter.size() >= 10 and piles != null and piles.mesh.get_surface_count() <= 7,
			"supply piles of kit crates and barrels stand about the camps and strongpoints, in one node")
	# The giants and the skyline: each moving part one hull mesh, the ship
	# with its lit ports, the skyline's blocks one mesh.
	var giants := map.get_node_or_null("Giants") as Node3D
	var body_hull := (giants.get("_body") as Node3D).get_node_or_null("Hull") as MeshInstance3D if giants != null else null
	var ship_hull := (giants.get("_ship") as Node3D).get_node_or_null("Hull") as MeshInstance3D if giants != null else null
	t.check(body_hull != null and ship_hull != null and ship_hull.mesh.get_surface_count() == 2
			and ship_hull.mesh.get_aabb().size.z > 600.0,
			"the Colossus and the capital ship are each one plated hull, the ship's ports lit")
	var colossus_draws := 0
	if giants != null:
		for part in (giants.get("_colossus") as Node3D).find_children("*", "MeshInstance3D", true, false):
			if not (part as MeshInstance3D).mesh is QuadMesh:
				colossus_draws += 1
	t.check(colossus_draws > 0 and colossus_draws <= 18, "the Colossus's hull is a mesh a moving part, not a node a box")
	var skyline := map.find_child("Skyline", true, false) as MeshInstance3D
	t.check(skyline != null and skyline.mesh.get_surface_count() <= 2, "the skyline's blocks and roofs are one mesh")
	map.queue_free()
	Look.enabled = was_on
	# Without Look, none of it.
	var bare: Node3D = Worlds.get_world("ashfront").create_map()
	t.add_child(bare)
	await t.frames(2)
	t.check(bare.find_child("ForgeClad", true, false) == null and bare.find_child("WreckClad", true, false) == null,
			"and none of it is built where Look is off")
	bare.queue_free()
