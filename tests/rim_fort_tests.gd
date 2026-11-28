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
		if piece.file != FORT.CREST:
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
	# Nothing reaches in past the edge walls, where a flier could meet it.
	var clear := true
	for child in fort.get_children():
		var box := (child as MeshInstance3D).global_transform * (child as MeshInstance3D).mesh.get_aabb()
		# A side is long one way and thin the other; the thin way is "out".
		var across_x := box.size.x < box.size.z
		var inner := minf(absf(box.position.x), absf(box.end.x)) if across_x else minf(absf(box.position.z), absf(box.end.z))
		clear = clear and inner > walls
	t.check(clear, "and none of it reaches in over the rim's slope")
	var draws := 0
	for child in fort.get_children():
		var mesh := (child as MeshInstance3D).mesh
		draws += mesh.get_surface_count() if mesh != null else 0
	t.check(fort.get_child_count() == 4 and draws <= 16, "it costs a few draws: one mesh a side, a surface a material")
	fort.queue_free()
	raid.queue_free()
