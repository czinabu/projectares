extends RefCounted
## People's heads: more hairstyles and facial hair than the pack's meshes
## (`Human.STYLES`, `Human.FACIAL`), and face shapes (`Human.FACES`).
##
## A style names its meshes as "Hair_Long" (worn as made) or "Hair_Long:bob"
## (a cut of it, `_cut`). A cut only takes away, folds or moves what is
## there: whole strands and buns are dropped or moved as one piece, so a
## cut never opens a hole in a strand. A face shape moves the head's skin
## and everything on it (brows, hair, beard) by one smooth field set
## around the eyes, so a beard follows the jaw it sits on; the eyes move
## whole and the neck's edge stays where it is, so the head still meets
## the body.
##
## View only, like everything a body is drawn with: the bones and skin
## binding stay as they are. Each cut and shape is made once per build and
## shared.
##
## Load with `const HeadShape := preload("res://core/visual/head_shape.gd")`.

## The pack's hair is all made on the first build's head: the middle of
## that head, where a cut lifts hair from.
const HAIR_CENTRE := Vector3(0.0, 1.7, -0.01)
## The parts of a face a shape moves, in metres and scales: "jaw" (width
## below the cheeks), "cheeks" (width under the eyes), "length" (of the
## face below the eyes), "chin" (forward), "chin_down", "brow" (forward).
const FACE_PARTS: Array[String] = ["jaw", "cheeks", "length", "chin", "chin_down", "brow"]
## How far from the neck's edge the skin starts to move, metres.
const SEAM_FREE := 0.035
## How far apart, in degrees, two faces' normals may be and still be merged
## when the levels of detail are made (Godot's import default).
const LOD_MERGE_ANGLE := 25.0

## "build/part/cut/face" -> ArrayMesh, made once.
static var _made := {}
## Build -> {"eyes": Vector3, "seam": PackedVector3Array}, head space.
static var _frames := {}


## Puts a look's hair and face on a body just instanced from
## `Human.rig_path`: a copy of each hair mesh `specs` names, cut and shaped,
## and the head shaped by `face` ({} keeps it). Returns the names of the
## hair nodes made; the pack's own hair nodes are left for the caller to
## take away.
static func dress(skeleton: Skeleton3D, build: String, specs: Array, face_id: String, face: Dictionary) -> Array[String]:
	var made: Array[String] = []
	var head := skeleton.find_child("PartHead", false, false) as MeshInstance3D
	var frame := _frame(build, head)
	if frame.is_empty():
		face = {}
	for spec: String in specs:
		var bits := spec.split(":")
		var base := skeleton.find_child(bits[0], false, false) as MeshInstance3D
		if base == null or base.mesh == null:
			continue
		var cut := bits[1] if bits.size() > 1 else ""
		var node := base.duplicate() as MeshInstance3D
		node.name = "Worn_" + spec.replace(":", "_")
		node.mesh = _mesh(build, base, cut, face_id, face, frame)
		skeleton.add_child(node)
		made.append(String(node.name))
	if head != null and not face.is_empty():
		head.mesh = _mesh(build, head, "", face_id, face, frame)
	return made


## A part's mesh with a cut and a face shape, made once.
static func _mesh(build: String, node: MeshInstance3D, cut: String, face_id: String, face: Dictionary,
		frame: Dictionary) -> Mesh:
	if cut == "" and face.is_empty():
		return node.mesh
	var key := "%s/%s/%s/%s" % [build, node.mesh.resource_name if node.mesh.resource_name != "" else String(node.name),
			cut, face_id]
	if _made.has(key):
		return _made[key]
	var source := node.mesh
	var bind: Variant = _head_bind(node.skin)
	# Through an ImporterMesh to make its levels of detail again, as the
	# pack's import did: without them a far head draws all its triangles.
	# A few milliseconds, once per cut and face.
	var made := ImporterMesh.new()
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		if cut != "":
			arrays = _cut(arrays, cut)
		if not face.is_empty() and bind != null:
			var eye := String(source.surface_get_material(s).resource_name if source.surface_get_material(s) else "") \
					.contains("Eye")
			arrays[Mesh.ARRAY_VERTEX] = _shape(arrays[Mesh.ARRAY_VERTEX], bind, face, frame, eye)
		made.add_surface(source.surface_get_primitive_type(s), arrays, [], {}, source.surface_get_material(s),
				source.surface_get_name(s), source.surface_get_format(s) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	made.generate_lods(LOD_MERGE_ANGLE, 0.0, [])
	var mesh := made.get_mesh()
	_made[key] = mesh
	return mesh


## Where a mesh's points are in the head bone's own space: its skin's bind
## for the head (the hair is bound from the first build's head, so this
## puts every mesh on the same footing). Null when it has none.
static func _head_bind(skin: Skin) -> Variant:
	if skin == null:
		return null
	for i in skin.get_bind_count():
		if skin.get_bind_name(i) == "Head":
			return skin.get_bind_pose(i)
	return null


## A build's head in head space: the middle of the eyes and the points of
## the neck's edge (the skin's open edge, which the body meets).
static func _frame(build: String, head: MeshInstance3D) -> Dictionary:
	if _frames.has(build):
		return _frames[build]
	var out := {}
	var bind: Variant = _head_bind(head.skin) if head != null and head.mesh != null else null
	if bind != null:
		var eyes := Vector3.ZERO
		var seam := PackedVector3Array()
		for s in head.mesh.get_surface_count():
			var material := head.mesh.surface_get_material(s)
			var named := String(material.resource_name) if material else ""
			var arrays := head.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if named.contains("Eye"):
				for v in verts:
					eyes += bind * v
				eyes /= maxf(verts.size(), 1.0)
				eyes.x = 0.0
			elif not named.contains("Hair"):
				for v in _open_edge(verts, arrays[Mesh.ARRAY_INDEX]):
					seam.append(bind * v)
		if eyes != Vector3.ZERO and not seam.is_empty():
			out = {"eyes": eyes, "seam": seam}
	_frames[build] = out
	return out


## The points on a surface's open edge: welded edges only one triangle uses.
static func _open_edge(verts: PackedVector3Array, index: PackedInt32Array) -> PackedVector3Array:
	var weld := {}
	var ids := PackedInt32Array()
	ids.resize(verts.size())
	for v in verts.size():
		var key := Vector3i((verts[v] * 5000.0).round())
		if not weld.has(key):
			weld[key] = v
		ids[v] = weld[key]
	var edges := {}
	for t in range(0, index.size() - 2, 3):
		for e in 3:
			var a := ids[index[t + e]]
			var b := ids[index[t + (e + 1) % 3]]
			var key := Vector2i(mini(a, b), maxi(a, b))
			edges[key] = edges.get(key, 0) + 1
	var seen := {}
	var out := PackedVector3Array()
	for key: Vector2i in edges:
		if edges[key] != 1:
			continue
		for v in [key.x, key.y]:
			if not seen.has(v):
				seen[v] = true
				out.append(verts[v])
	return out


## 0 at `from`, 1 at `to`, eased; either way round.
static func _ramp(from: float, to: float, t: float) -> float:
	return smoothstep(0.0, 1.0, clampf((t - from) / (to - from), 0.0, 1.0))


## Moves points by a face shape. Eyes move whole, each by the field at its
## own middle.
static func _shape(verts: PackedVector3Array, bind: Transform3D, face: Dictionary, frame: Dictionary,
		eyes: bool) -> PackedVector3Array:
	var out := verts.duplicate()
	var back := bind.affine_inverse()
	if eyes:
		var sides := [Vector3.ZERO, Vector3.ZERO]
		var counts := [0, 0]
		for v in verts:
			var side := 0 if v.x < 0.0 else 1
			sides[side] += bind * v
			counts[side] += 1
		var moves := []
		for side in 2:
			moves.append(_field(sides[side] / maxf(counts[side], 1.0), face, frame) if counts[side] > 0 else Vector3.ZERO)
		for v in out.size():
			out[v] = back * (bind * out[v] + moves[0 if out[v].x < 0.0 else 1])
		return out
	for v in out.size():
		var p := bind * out[v]
		out[v] = back * (p + _field(p, face, frame))
	return out


## How far a point in head space moves for a face shape.
static func _field(p: Vector3, face: Dictionary, frame: Dictionary) -> Vector3:
	var q: Vector3 = p - frame["eyes"]
	var ax := absf(q.x)
	# The face, not the back of the head.
	var front := _ramp(-0.13, -0.05, q.z)
	var move := Vector3.ZERO
	# The jaw: wider or narrower from the cheeks down.
	var jaw := _ramp(-0.03, -0.085, q.y) * front
	move.x += q.x * (float(face.get("jaw", 1.0)) - 1.0) * jaw
	# The cheekbones, under the eyes and out to the side.
	var cheek := exp(-pow((q.y + 0.03) / 0.028, 2.0)) * _ramp(0.015, 0.05, ax) * front
	move.x += q.x * (float(face.get("cheeks", 1.0)) - 1.0) * cheek
	# The length of the face below the eyes.
	move.y += minf(q.y, 0.0) * (float(face.get("length", 1.0)) - 1.0) * front
	# The chin, forward and down.
	var chin_at := Vector2(q.y + 0.105, q.z + 0.005)
	var chin := exp(-chin_at.length_squared() / (0.035 * 0.035)) * _ramp(0.05, 0.0, ax)
	move.z += float(face.get("chin", 0.0)) * chin
	move.y -= float(face.get("chin_down", 0.0)) * chin
	# The brow ridge, above the eyes.
	var brow := exp(-pow((q.y - 0.02) / 0.014, 2.0)) * _ramp(-0.06, -0.01, q.z) * _ramp(0.075, 0.05, ax)
	move.z += float(face.get("brow", 0.0)) * brow
	# The neck's edge stays where the body meets it.
	var near := INF
	for s: Vector3 in frame["seam"]:
		near = minf(near, s.distance_squared_to(p))
	return move * _ramp(0.0, SEAM_FREE, sqrt(near))


## A hair mesh cut into another style (arrays of one surface, in the
## pack's own space: the first build's head).
static func _cut(arrays: Array, cut: String) -> Array:
	arrays = arrays.duplicate()
	var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var keep := func(_a: Vector3, _b: Vector3, _c: Vector3) -> bool: return true
	match cut:
		"mohawk":
			# A strip down the middle of the buzz cut, raised to a crest:
			# what lay beyond the strip is folded in under its edge, so the
			# edge runs straight and the crest has sides.
			var half := 0.026
			keep = func(a: Vector3, b: Vector3, c: Vector3) -> bool:
				return minf(minf(absf(a.x), absf(b.x)), absf(c.x)) < half and minf(minf(a.y, b.y), c.y) > 1.655
			for v in verts.size():
				var p := verts[v]
				var out := Vector3(0.0, p.y - HAIR_CENTRE.y, p.z - HAIR_CENTRE.z).normalized()
				if absf(p.x) >= half:
					verts[v] = Vector3(signf(p.x) * half, p.y, p.z) - out * 0.012
				else:
					var crest := 1.0 - absf(p.x) / half
					verts[v] = p + out * 0.012 * sqrt(crest) * _ramp(1.65, 1.7, p.y)
		"bob":
			# The long hair folded up to the jaw.
			for v in verts.size():
				var p := verts[v]
				if p.y < 1.64:
					verts[v].y = 1.64 + (p.y - 1.64) * 0.35
		"swept":
			# The long hair with the strands at the front left out: worn
			# back off the face.
			index = _drop_pieces(verts, index, func(middle: Vector3, _count: int) -> bool: return middle.z > 0.04)
		"knot":
			# The buns' cap with one bun on top; the fringe and the locks
			# at the sides left out.
			var pieces := _pieces(verts, index)
			for piece: Dictionary in pieces:
				var middle: Vector3 = piece["middle"]
				if middle.x > 0.05:
					var turn := Basis(Vector3.BACK, PI * 0.5)
					for v: int in piece["verts"]:
						verts[v] = Vector3(0.0, 1.775, -0.085) + turn * (verts[v] - middle)
			index = _drop_pieces(verts, index, func(middle: Vector3, _count: int) -> bool:
				return middle.x < -0.05 or middle.z > 0.0)
		"fringe":
			# Only the buns' fringe, worn over a buzz cut.
			index = _drop_pieces(verts, index, func(middle: Vector3, count: int) -> bool:
				return middle.z < 0.05 or count > 300)
		"short":
			# The beard trimmed: the point at the chin taken up.
			for v in verts.size():
				if verts[v].y < 1.59:
					verts[v].y = 1.59 + (verts[v].y - 1.59) * 0.3
		"goatee":
			keep = func(a: Vector3, b: Vector3, c: Vector3) -> bool:
				var m := (a + b + c) / 3.0
				return absf(m.x) < 0.03 and m.y < 1.66
		"moustache":
			keep = func(a: Vector3, b: Vector3, c: Vector3) -> bool:
				var m := (a + b + c) / 3.0
				return absf(m.x) < 0.035 and m.y > 1.628 and m.y < 1.66
		"chinstrap":
			# A line of beard along the jaw: the sides and under the chin,
			# its point taken up.
			for v in verts.size():
				if verts[v].y < 1.59:
					verts[v].y = 1.59 + (verts[v].y - 1.59) * 0.25
			keep = func(a: Vector3, b: Vector3, c: Vector3) -> bool:
				var m := (a + b + c) / 3.0
				return m.y < 1.597 or absf(m.x) > 0.05
	var kept := PackedInt32Array()
	for t in range(0, index.size() - 2, 3):
		if keep.call(verts[index[t]], verts[index[t + 1]], verts[index[t + 2]]):
			kept.append_array([index[t], index[t + 1], index[t + 2]])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = kept
	return arrays


## The separate pieces of a mesh (strands, buns): [{"verts", "middle"}].
static func _pieces(verts: PackedVector3Array, index: PackedInt32Array) -> Array:
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for v in verts.size():
		parent[v] = v
	var weld := {}
	for v in verts.size():
		var key := Vector3i((verts[v] * 5000.0).round())
		if weld.has(key):
			_join(parent, v, weld[key])
		else:
			weld[key] = v
	for t in range(0, index.size() - 2, 3):
		_join(parent, index[t], index[t + 1])
		_join(parent, index[t + 1], index[t + 2])
	var groups := {}
	for v in verts.size():
		var root := _root(parent, v)
		if not groups.has(root):
			groups[root] = {"verts": PackedInt32Array(), "middle": Vector3.ZERO}
		var group: Dictionary = groups[root]
		var members: PackedInt32Array = group["verts"]
		members.append(v)
		group["verts"] = members
		group["middle"] += verts[v]
	for group: Dictionary in groups.values():
		group["middle"] /= float((group["verts"] as PackedInt32Array).size())
	return groups.values()


static func _root(parent: PackedInt32Array, v: int) -> int:
	while parent[v] != v:
		parent[v] = parent[parent[v]]
		v = parent[v]
	return v


static func _join(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _root(parent, a)
	var rb := _root(parent, b)
	if ra != rb:
		parent[ra] = rb


## The triangles left once the pieces `drop` picks (by their middle and
## their count of points) are taken out.
static func _drop_pieces(verts: PackedVector3Array, index: PackedInt32Array, drop: Callable) -> PackedInt32Array:
	var gone := {}
	for piece: Dictionary in _pieces(verts, index):
		var members: PackedInt32Array = piece["verts"]
		if drop.call(piece["middle"], members.size()):
			for v in members:
				gone[v] = true
	var kept := PackedInt32Array()
	for t in range(0, index.size() - 2, 3):
		if not gone.has(index[t]):
			kept.append_array([index[t], index[t + 1], index[t + 2]])
	return kept
