extends RefCounted
## The `collision` checks: nothing you can see standing in a world is a ghost
## you walk through (docs/systems/worlds-and-war.md "Collision"). Every world,
## the arena and the home base are built with `Look` on, then every mesh big
## enough to block a person and standing where one could walk is checked for
## a world collider (`Actor.LAYER_WORLD`) through its middle. A mesh that is
## meant to be walked through (a zone's glow, plants, a crowd behind glass,
## scenery far past the rim) says so with `SKIP_META` on itself or any
## parent. A new world is covered by this the day it is added: it is found
## through `Worlds`, like the game finds it.
##
## Also: loot crates and stations are solid, people bump into vehicles, and
## the boxes `SolidProp` puts under a model match the model.

## Set on a node (or a parent) that is drawn but deliberately has no
## collision; the value says why.
const SKIP_META := "walk_through"
## Shorter than this and smaller than `LITTER_AREA` across is litter you
## step over or through (a gas can, a backpack).
const LITTER_HEIGHT := 0.9
const LITTER_AREA := 1.0
## A trim this close to a solid (a pour down a wall, a rib on a tower) is
## part of that solid.
const SKIN := 0.35
## A face narrower than this is a stem's or a wire's and is not judged.
const THIN := 0.08
## Points tried on each mesh's faces.
const SAMPLES := 48


static func run(t: Node) -> void:
	print("Collision")
	var was_on: bool = Look.enabled
	Look.enabled = true
	var places := {}
	for world in Worlds.all():
		places[world.id] = world
	places["arena"] = Arena.ArenaVenue.new()
	for id: String in places:
		var map: Node3D = (places[id] as WorldDef).create_map()
		if map == null:
			continue
		await _check_place(t, id, map)
	await _check_place(t, "home base", HomeBase.new())
	Look.enabled = was_on
	await _check_audit(t)
	_check_bodies(t)
	_check_solid_props(t)


static func _check_place(t: Node, id: String, map: Node3D) -> void:
	var holder := Node3D.new()
	t.add_child(holder)
	holder.add_child(map)
	await t.frames(3)
	var ghosts := ghosts_in(map)
	var listed: PackedStringArray = []
	for g: Dictionary in ghosts.slice(0, 6):
		listed.append("%s (%.1f x %.1f x %.1f at %s)" % [g["path"], g["size"].x, g["size"].y, g["size"].z, g["at"].snapped(Vector3.ONE)])
	t.check(ghosts.is_empty(), "%s: everything solid you can see has collision%s" % [id,
			"" if ghosts.is_empty() else ": %d without, e.g. %s" % [ghosts.size(), ", ".join(listed)]])
	holder.queue_free()
	await t.frames(2)


## Every mesh in `map` that looks solid, stands where someone could walk and
## has nothing to bump into where it is: `{path, size, at}` each, `at` a
## point on it with nothing solid there.
##
## Points spread over the mesh's own faces are tested, not its bounding
## box, so a merged mesh (a map's boxes drawn as one) and a turned one are
## judged by where they really are. A point counts where a person walking
## would touch it: from a hand above the floor under it to head height. The
## mesh is a ghost when fewer than half those points have a world collider
## within `SKIN`.
static func ghosts_in(map: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var space := map.get_world_3d().direct_space_state
	var reach := _reach(map)
	var faces_of := {}
	var probe := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = SKIN
	probe.shape = ball
	probe.collision_mask = Actor.LAYER_WORLD
	for node in map.find_children("*", "GeometryInstance3D", true, false):
		if not (node as Node3D).is_visible_in_tree() or _skipped(node, map):
			continue
		# A MultiMesh keeps its instances in the renderer, which a headless
		# run has none of: a scatter that should block builds its own
		# collision (a map's business) and is not judged here.
		if not node is MeshInstance3D:
			continue
		var mesh := (node as MeshInstance3D).mesh
		var pieces: Array[Transform3D] = [(node as Node3D).global_transform]
		if mesh == null or pieces.is_empty():
			continue
		if not faces_of.has(mesh):
			faces_of[mesh] = _sample_faces(mesh)
		var samples: Array = faces_of[mesh]
		for xform in pieces:
			var box := xform * mesh.get_aabb()
			if not _blocks_size(box):
				continue
			var c := box.get_center()
			if absf(c.x) > reach.x or absf(c.z) > reach.y:
				continue
			var touched := 0
			var held := 0
			var misses: Array[Vector3] = []
			for sample: Array in samples:
				var at: Vector3 = xform * (sample[0] as Vector3)
				var floor_y := _floor_under(space, at)
				if is_nan(floor_y) or at.y < floor_y + 0.2 or at.y > floor_y + 2.0:
					continue
				touched += 1
				probe.transform = Transform3D(Basis(), at)
				if _solid_hit(space.intersect_shape(probe, 8)):
					held += 1
				elif misses.size() < 12:
					misses.append(at)
			if touched >= 3 and held * 2 < touched:
				out.append({"path": str(map.get_path_to(node)), "size": box.size, "at": misses[0], "misses": misses,
						"share": "%d/%d" % [touched - held, touched]})
	return out


## Up to `SAMPLES` points on `mesh`'s faces, each a little out from its face
## (a trimesh is met from its front)
## (`[point]` each), spread evenly over its triangles.
static func _sample_faces(mesh: Mesh) -> Array:
	var faces := mesh.get_faces()
	var triangles := faces.size() / 3
	var out := []
	if triangles == 0:
		return out
	var stride := maxf(1.0, float(triangles) / SAMPLES)
	var t := 0.0
	while int(t) < triangles:
		var i := int(t) * 3
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var normal := (b - a).cross(c - a)
		t += stride
		# A face narrower than `THIN` belongs to a stem, a wire or a trim
		# strip: nothing anyone expects to bump into.
		var longest := maxf((b - a).length(), maxf((c - b).length(), (a - c).length()))
		if longest <= 0.0 or normal.length() / longest < THIN:
			continue
		var mid := (a + b + c) / 3.0
		# Godot winds front faces clockwise, so this normal points in.
		if normal.length() > 0.000001:
			mid -= normal.normalized() * 0.03
		out.append([mid])
	return out


## The height of what stands under `at`, or NAN with nothing within 3 m. A
## point on a solid's top finds that top, so only its sides are judged.
static func _floor_under(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at, at - Vector3(0, 3.0, 0))
	q.collision_mask = Actor.LAYER_WORLD
	var hit := space.intersect_ray(q)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


## How far from the middle anyone can go, along x and z: inside the walls
## a map stands round its edge (the "map_edge" group), or anywhere.
static func _reach(map: Node) -> Vector2:
	var out := Vector2(INF, INF)
	for wall: Node in map.get_tree().get_nodes_in_group("map_edge"):
		if not map.is_ancestor_of(wall):
			continue
		var at := (wall as Node3D).global_position
		if absf(at.x) > absf(at.z):
			out.x = minf(out.x, absf(at.x))
		else:
			out.y = minf(out.y, absf(at.z))
	return out


static func _skipped(node: Node, map: Node) -> bool:
	# A shape and its mesh built as one body (a map's `_box`) are the same
	# thing; a tilted one would fool the columns below.
	var body := node.get_parent() as CollisionObject3D
	if body != null and body.collision_layer & Actor.LAYER_WORLD != 0 and not body.get_shape_owners().is_empty():
		return true
	var at := node
	while at != null and at != map.get_parent():
		if at.has_meta(SKIP_META) or at.has_meta(SolidProp.META) or at is Actor:
			return true
		at = at.get_parent()
	return false


static func _blocks_size(box: AABB) -> bool:
	if minf(box.size.x, box.size.z) < 0.25 or box.size.y < 0.5:
		return false
	return box.size.y >= LITTER_HEIGHT or box.size.x * box.size.z >= LITTER_AREA


## Any hit but the ground itself (a heightmap, or a body marked as ground).
static func _solid_hit(hits: Array[Dictionary]) -> bool:
	for hit in hits:
		var body := hit["collider"] as CollisionObject3D
		if body == null:
			continue
		var shape := body.shape_owner_get_shape(body.shape_find_owner(hit["shape"]), 0)
		if shape is HeightMapShape3D or shape is WorldBoundaryShape3D:
			continue
		return true
	return false


## The check itself: a bare crate-sized box on open ground is a ghost, the
## same box with a collider round it is not, and one marked `SKIP_META` is
## let off.
static func _check_audit(t: Node) -> void:
	var map := Node3D.new()
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(floor_shape)
	map.add_child(ground)
	var crates: Array[MeshInstance3D] = []
	for k in 3:
		var crate := MeshInstance3D.new()
		crate.mesh = BoxMesh.new()
		(crate.mesh as BoxMesh).size = Vector3(1.5, 1.5, 1.5)
		crate.position = Vector3(k * 10.0, 0.75, 0)
		map.add_child(crate)
		crates.append(crate)
	SolidProp.box(map, Vector3(1.5, 1.5, 1.5), Transform3D(Basis(), Vector3(10.0, 0.75, 0)))
	crates[2].set_meta(SKIP_META, "a test")
	var holder := Node3D.new()
	t.add_child(holder)
	holder.add_child(map)
	await t.frames(3)
	var paths := ghosts_in(map).map(func(g: Dictionary) -> String: return g["path"])
	t.check(paths == [str(map.get_path_to(crates[0]))],
			"the collision check flags a box with nothing solid there, and only that one (%s)" % [paths])
	holder.queue_free()
	await t.frames(2)


static func _check_bodies(t: Node) -> void:
	var crate := LootContainer.new()
	crate._ready()
	t.check(crate.collision_layer & Actor.LAYER_WORLD != 0 and crate.collision_layer & Actor.LAYER_INTERACT != 0,
			"a loot crate is solid as well as usable")
	crate.free()
	var bag := LootContainer.new()
	bag.is_bag = true
	bag._ready()
	t.check(bag.collision_layer & Actor.LAYER_WORLD == 0, "a dropped bag is not: you never get caught on a body's kit")
	bag.free()
	var actor := Actor.new()
	actor._ready()
	t.check(actor.collision_mask & preload("res://core/vehicle/vehicle.gd").LAYER_VEHICLES != 0,
			"people bump into vehicles instead of walking through them")
	actor.free()


static func _check_solid_props(t: Node) -> void:
	var was_on: bool = Look.enabled
	Look.enabled = true
	var worst := ""
	var off := 0.0
	for file: String in SolidProp.SHAPES:
		var holder := Look.prop(file, 2.0)
		var bounds := Look.model_bounds(holder.get_child(0)) if holder.get_child_count() > 0 else AABB()
		var box := SolidProp.box_size(file, 2.0)
		var miss := (bounds.size - box).abs()
		var worst_axis := maxf(miss.x, maxf(miss.y, miss.z)) / 2.0
		if worst_axis > off:
			off = worst_axis
			worst = "%s: model %s, box %s" % [file, bounds.size.snapped(Vector3.ONE * 0.01), box.snapped(Vector3.ONE * 0.01)]
		holder.free()
	Look.enabled = was_on
	t.check(off <= 0.12, "every solid prop's box fits its model (worst %s)" % worst)
