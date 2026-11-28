extends RefCounted
## Checks for the fortress line on Ashfront's rim (DESIGN.md "The battle
## around you", `worlds/ashfront/rim_fort.gd`): it stands past the walls on
## every side, on the ground, low in front of the battle shelves, and costs
## a few draws.

const MAP := preload("res://worlds/ashfront/map.gd")
const FORT := preload("res://worlds/ashfront/rim_fort.gd")


static func run(t: Node) -> void:
	print("Rim fort: the fortress line on Ashfront's rim")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var fort: Node3D = raid.map.call("make_rim_fort")
	raid.map.add_child(fort)
	fort.call("build")
	var pieces: Array[Dictionary] = fort.get("pieces")
	var walls := float(raid.map.terrain.extent()) * 0.5 - 6.0
	var outside := not pieces.is_empty()
	var grounded := true
	var sides := {}
	for piece in pieces:
		var at: Vector3 = piece.at
		outside = outside and maxf(absf(at.x), absf(at.z)) > walls + 1.0
		var ground := float(raid.map.call("scenery_height", at.x, at.z))
		if not piece.stacked:
			grounded = grounded and at.y < ground and at.y > ground - 12.0
		sides[piece.side] = int(sides.get(piece.side, 0)) + 1
	t.check(outside and sides.size() == 4, "the line runs along all four sides, past the walls")
	t.check(grounded, "every piece stands sunk into the ground under it")
	# In front of a shelf only stubs and broken lengths stand, no towers.
	var shelf: Dictionary = MAP.SHELVES[0]
	var out: Vector2 = shelf["out"]
	var lateral: Vector2 = shelf["lateral"]
	var low := true
	for piece in pieces:
		var at: Vector3 = piece.at
		var l := Vector2(at.x, at.z).dot(Vector2(-out.y, out.x))
		if Vector2(at.x, at.z).dot(out) > 300.0 and l > lateral.x and l < lateral.y:
			low = low and not FORT.TOWERS.has(piece.file) and not FORT.WALLS.has(piece.file)
	t.check(low, "in front of a shelf the wall is broken down low")
	# No piece of the wall reaches in past the edge walls, where a flier
	# could meet it.
	var clear := true
	for piece in pieces:
		var box: AABB = piece.box
		# Clear of the square inside the walls on one axis or the other.
		var out_x := minf(absf(box.position.x), absf(box.end.x)) if box.position.x * box.end.x > 0.0 else 0.0
		var out_z := minf(absf(box.position.z), absf(box.end.z)) if box.position.z * box.end.z > 0.0 else 0.0
		var inner := maxf(out_x, out_z)
		clear = clear and inner > walls
	t.check(clear, "and no piece of the wall reaches in over the rim's slope")
	# Each side has its breaches, each with smoke going up.
	var breaches: Array[Vector3] = fort.get("breaches")
	var smoke := fort.find_children("*", "GPUParticles3D", false, false).size()
	t.check(breaches.size() >= 4 and smoke == breaches.size(), "the wall is blown open in places, smoke rising from each breach")
	var draws := 0
	var meshes := fort.find_children("*", "MeshInstance3D", false, false)
	for child in meshes:
		draws += (child as MeshInstance3D).mesh.get_surface_count()
	t.check(meshes.size() == 4 and draws <= 4 * FORT.KEYS.size(), "it costs a few draws: one mesh a side, a surface a material")
	fort.queue_free()
	raid.queue_free()
