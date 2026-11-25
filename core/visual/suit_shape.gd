extends RefCounted
## The tactical suit's shape (Caleb's call: painted straight on the bare
## body it hugged every curve). The suit is drawn on the body's own torso
## and legs (`Human.SUITS`, `character.gdshader`), so this reshapes those
## two parts' meshes, at rest, into cloth hung over the body: each slice of
## the trunk and of each thigh is filled out to its convex hull (no cleavage
## or hollow of the back), cloth falls from the chest and the seat at a
## slant instead of following the curve back in (`drape_down`, `drape_up`),
## what still stands out at the front is eased back toward the cloth above
## and below it (`flatten`), and the whole layer sits `slack` out from the
## skin. Moves are smoothed over the mesh so no seam or step shows, and the
## normals are made again from the new shape so the light shows cloth, not
## the body under it.
##
## View only, like everything a body is drawn with: the bones, the skin
## binding, each vertex's rest place for the suit's pattern (CUSTOM0) and
## every other part stay as they are. The result is made once per build and
## shared. It is worked out offline (`tools/suit_shape`, about a second a
## body) and kept in `suit_<build>_<part>.res` beside the bodies; a body
## with no baked file is shaped as it loads. Bake again whenever the bodies
## or this script change, then re-measure with `tools/body_fit` so armor
## fits over the suit.
##
## Load with `const SuitShape := preload("res://core/visual/suit_shape.gd")`.

## The parts reshaped (`Human.SLOT_NODES`).
const PARTS: Array[String] = ["PartBody", "PartLegs"]
## Bones whose skin is the trunk, and the thighs'.
const TRUNK_BONES: Array[String] = ["Hips", "Abdomen", "Torso", "Chest"]
const THIGH_BONES: Array[String] = ["UpperLeg.L", "UpperLeg.R"]
## Height of a slice, metres.
const STEP := 0.02
## Directions round a slice.
const ANGLES := 48
## How far the cloth stands off the skin, metres.
const SLACK := 0.012
## How much the cloth comes in per metre as it falls (front, then sides and
## back), and as it rises to the collarbones: lower hangs looser.
const DRAPE_DOWN_FRONT := 0.45
const DRAPE_DOWN_BACK := 0.5
const DRAPE_UP := 0.55
## How far what stands out at the front is eased back toward the cloth a
## hand's width above and below it (0 none, 1 all the way), and the most it
## is pulled in, metres.
const FLATTEN := 0.8
const FLATTEN_BACK := 0.8
const FLATTEN_MOST := 0.06
const FLATTEN_SPAN := 6
## The most the cloth stands out from the skin anywhere, metres.
const MOST_OUT := 0.035
## Passes of smoothing over the mesh.
const SMOOTH := 12
## How far apart, in degrees, two faces' normals may be and still be merged
## when the levels of detail are made (Godot's import default).
const LOD_MERGE_ANGLE := 25.0

## Build -> {part name: ArrayMesh}, made once.
static var _made := {}
## Off draws the bare body's shape (to compare, in dev tools).
static var enabled := true


## Puts the suit's shape on a body just instanced from `Human.rig_path`.
static func apply(rig: Node, build: String) -> void:
	if not enabled:
		return
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	if not _made.has(build):
		_made[build] = _baked(skeleton, build)
		if (_made[build] as Dictionary).is_empty():
			_made[build] = make(skeleton)
	var meshes: Dictionary = _made[build]
	for part: String in meshes:
		var node := skeleton.find_child(part, false, false) as MeshInstance3D
		if node != null:
			node.mesh = meshes[part]


## Where a build's baked part is kept.
static func baked_path(build: String, part: String) -> String:
	return "res://assets/characters/humans/suit_%s_%s.res" % [build, part]


## The baked parts, given the body's own materials back; {} if any is missing.
static func _baked(skeleton: Skeleton3D, build: String) -> Dictionary:
	var out := {}
	for part: String in PARTS:
		var path := baked_path(build, part)
		var node := skeleton.find_child(part, false, false) as MeshInstance3D
		if node == null or not ResourceLoader.exists(path):
			return {}
		var mesh := load(path) as ArrayMesh
		if mesh == null or mesh.get_surface_count() != 1:
			return {}
		mesh.surface_set_material(0, node.mesh.surface_get_material(0))
		out[part] = mesh
	return out


## Works the suit's shape out from a bare body: {part name: ArrayMesh}.
static func make(skeleton: Skeleton3D) -> Dictionary:
	# Every vertex of the parts, welded by place so a seam moves as one.
	var parts := []
	var weld := {}
	var points: Array[Vector3] = []
	var kinds: Array[int] = []  # 0 left alone, 1 trunk, 2 left thigh, 3 right thigh
	var owners: Array = []  # welded -> [[part, vertex], ...]
	for part: String in PARTS:
		var node := skeleton.find_child(part, false, false) as MeshInstance3D
		if node == null or node.mesh == null or node.mesh.get_surface_count() != 1 or node.skin == null:
			continue
		var arrays := node.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		var map := PackedInt32Array()
		map.resize(verts.size())
		for v in verts.size():
			var key := Vector3i((verts[v] * 2000.0).round())
			var at: int = weld.get(key, -1)
			if at < 0:
				at = points.size()
				weld[key] = at
				points.append(verts[v])
				kinds.append(_kind(node.skin, bones, weights, v, per))
				owners.append([])
			map[v] = at
			owners[at].append([parts.size(), v])
		parts.append({"name": part, "node": node, "arrays": arrays, "map": map})
	if parts.is_empty():
		return {}
	var crotch := skeleton.get_bone_global_rest(skeleton.find_bone("LowerLeg.L")).origin.y
	crotch = lerpf(crotch, skeleton.get_bone_global_rest(skeleton.find_bone("UpperLeg.L")).origin.y, 0.8)
	var neck := skeleton.get_bone_global_rest(skeleton.find_bone("Neck")).origin.y
	var moved: Array[Vector3] = []
	moved.resize(points.size())
	for i in points.size():
		moved[i] = Vector3.ZERO
	_shape_zone(points, kinds, 1, moved, Vector2.ZERO, crotch - 0.12, neck - 0.04)
	for side in [2, 3]:
		var hip := skeleton.get_bone_global_rest(skeleton.find_bone(THIGH_BONES[side - 2])).origin
		# The seat on this side counts with the thigh, so the cloth falls
		# from it down the back of the leg instead of tucking under it.
		# Down to a hand above the knee: the knee pads hang below.
		var knee := skeleton.get_bone_global_rest(skeleton.find_bone("LowerLeg.L")).origin.y
		_shape_zone(points, kinds, side, moved, Vector2(hip.x, hip.z), knee + 0.1, INF, hip.y)
	# Smooth the moves over the mesh, so slices and zones meet without a step.
	var links := _links(parts, points.size())
	for pass_i in SMOOTH:
		var next: Array[Vector3] = moved.duplicate()
		for i in points.size():
			var around: PackedInt32Array = links[i]
			if around.is_empty():
				continue
			var sum := Vector3.ZERO
			for j in around:
				sum += moved[j]
			next[i] = moved[i].lerp(sum / float(around.size()), 0.6)
		moved = next
	var out := {}
	for info: Dictionary in parts:
		out[info["name"]] = _rebuild(info, points, moved, kinds)
	return out


## 1 trunk, 2 or 3 a thigh, 0 anything else, by the bone that moves a vertex most.
static func _kind(skin: Skin, bones: PackedInt32Array, weights: PackedFloat32Array, v: int, per: int) -> int:
	var best := -1
	var most := 0.0
	for k in per:
		if weights[v * per + k] > most:
			most = weights[v * per + k]
			best = bones[v * per + k]
	if best < 0 or best >= skin.get_bind_count():
		return 0
	var bone := String(skin.get_bind_name(best))
	if bone in TRUNK_BONES:
		return 1
	if bone == THIGH_BONES[0]:
		return 2
	if bone == THIGH_BONES[1]:
		return 3
	return 0


## Shapes one zone: slices round an upright axis through `axis` (x, z),
## each filled to its hull, draped and flattened; the move for each vertex
## goes in `moved`.
static func _shape_zone(points: Array[Vector3], kinds: Array[int], kind: int, moved: Array[Vector3], axis: Vector2,
		low: float, high: float, seat := -INF) -> void:
	var members: Array[int] = []
	var bottom := INF
	var top := -INF
	for i in points.size():
		var p := points[i]
		var with_seat := kinds[i] == 1 and p.y < seat and p.x * axis.x > 0.0 and absf(p.x) > absf(axis.x) * 0.3
		if (kinds[i] == kind or with_seat) and p.y >= low and p.y <= high:
			members.append(i)
			bottom = minf(bottom, points[i].y)
			top = maxf(top, points[i].y)
	if members.size() < 8:
		return
	var count := int(ceil((top - bottom) / STEP)) + 1
	var slices := []
	for s in count:
		slices.append(PackedVector2Array())
	for i in members:
		var p := points[i]
		var s := clampi(int((p.y - bottom) / STEP), 0, count - 1)
		# A packed array in a list is a copy: take it out, add, put it back.
		var row: PackedVector2Array = slices[s]
		row.append(Vector2(p.x - axis.x, p.z - axis.y))
		slices[s] = row
	# Each slice's hull, as a radius at each angle (0 where the slice is empty).
	var hull := []
	for s in count:
		hull.append(_hull_radii(slices[s]))
	# Cloth falls from what stands out above, and rises to what stands out below.
	var cloth := []
	for s in count:
		cloth.append((hull[s] as PackedFloat32Array).duplicate())
	for a in ANGLES:
		var front := cos(TAU * a / ANGLES) > 0.3
		var fall := (DRAPE_DOWN_FRONT if front else DRAPE_DOWN_BACK) * STEP
		for s in range(count - 2, -1, -1):
			if hull[s][a] > 0.0 and cloth[s + 1][a] > 0.0:
				var row: PackedFloat32Array = cloth[s]
				row[a] = maxf(row[a], cloth[s + 1][a] - fall)
				cloth[s] = row
		for s in range(1, count):
			if hull[s][a] > 0.0 and cloth[s - 1][a] > 0.0:
				var row: PackedFloat32Array = cloth[s]
				row[a] = maxf(row[a], cloth[s - 1][a] - DRAPE_UP * STEP)
				cloth[s] = row
	# What stands out at the front is eased back toward the cloth round it.
	var eased := []
	for s in count:
		var row := (cloth[s] as PackedFloat32Array).duplicate()
		for a in ANGLES:
			var c := cos(TAU * a / ANGLES)
			var front := maxf(c, 0.0) * FLATTEN + maxf(-c, 0.0) * FLATTEN_BACK
			if front <= 0.0 or row[a] <= 0.0:
				continue
			# The cloth a hand's width above and below, the higher of the
			# two: what stands out past both is eased back toward it.
			var mean := 0.0
			for k in [-FLATTEN_SPAN, FLATTEN_SPAN]:
				var t := clampi(s + k, 0, count - 1)
				mean = maxf(mean, cloth[t][a])
			if mean <= 0.0:
				continue
			if row[a] > mean:
				row[a] -= minf((row[a] - mean) * front, FLATTEN_MOST)
		eased.append(row)
	for i in members:
		var p := points[i]
		var flat := Vector2(p.x - axis.x, p.z - axis.y)
		var r := flat.length()
		if r < 0.001:
			continue
		# Angle 0 is the front (+Z for the pack's bodies), round toward +X.
		var ang := fposmod(atan2(flat.x, flat.y), TAU) / TAU * ANGLES
		var fy := clampf((p.y - bottom) / STEP - 0.5, 0.0, count - 1.0)
		var want := _sample(eased, fy, ang, count)
		if want <= 0.0:
			continue
		var target := want + SLACK
		var move := Vector3(flat.x, 0.0, flat.y) / r * clampf(target - r, -FLATTEN_MOST, MOST_OUT)
		# A vertex shaped by two zones (the seat) keeps the larger move out.
		if moved[i] == Vector3.ZERO or move.length() > moved[i].length():
			moved[i] = move


## The radius of a slice's convex hull at each angle, from the axis.
static func _hull_radii(points: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(ANGLES)
	if points.size() < 3:
		for p in points:
			var a := int(fposmod(atan2(p.x, p.y), TAU) / TAU * ANGLES) % ANGLES
			out[a] = maxf(out[a], p.length())
		return out
	var hull := Geometry2D.convex_hull(points)
	for a in ANGLES:
		var ang := TAU * a / ANGLES
		var dir := Vector2(sin(ang), cos(ang))
		var best := 0.0
		for k in hull.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(Vector2.ZERO, dir * 2.0, hull[k], hull[k + 1])
			if hit != null:
				best = maxf(best, (hit as Vector2).length())
		out[a] = best
	return out


## A radius between slices and angles.
static func _sample(rows: Array, fy: float, ang: float, count: int) -> float:
	var s0 := int(floor(fy))
	var s1 := mini(s0 + 1, count - 1)
	var ts: float = fy - s0
	var a0 := int(floor(ang)) % ANGLES
	var a1 := (a0 + 1) % ANGLES
	var ta: float = ang - floor(ang)
	var v00: float = rows[s0][a0]
	var v01: float = rows[s0][a1]
	var v10: float = rows[s1][a0]
	var v11: float = rows[s1][a1]
	if minf(minf(v00, v01), minf(v10, v11)) <= 0.0:
		return maxf(maxf(v00, v01), maxf(v10, v11)) if ts < 0.5 else maxf(v10, v11)
	return lerpf(lerpf(v00, v01, ta), lerpf(v10, v11, ta), ts)


## Each welded vertex's neighbours across every part's triangles.
static func _links(parts: Array, count: int) -> Array:
	var sets := []
	for i in count:
		sets.append({})
	for info: Dictionary in parts:
		var map: PackedInt32Array = info["map"]
		var index: PackedInt32Array = info["arrays"][Mesh.ARRAY_INDEX]
		for t in range(0, index.size() - 2, 3):
			var a := map[index[t]]
			var b := map[index[t + 1]]
			var c := map[index[t + 2]]
			sets[a][b] = true
			sets[a][c] = true
			sets[b][a] = true
			sets[b][c] = true
			sets[c][a] = true
			sets[c][b] = true
	var out := []
	for i in count:
		out.append(PackedInt32Array(sets[i].keys()))
	return out


## The part's mesh with its vertices moved and its normals made again where
## they moved.
static func _rebuild(info: Dictionary, points: Array[Vector3], moved: Array[Vector3], kinds: Array[int]) -> ArrayMesh:
	var node: MeshInstance3D = info["node"]
	var arrays: Array = info["arrays"].duplicate()
	var map: PackedInt32Array = info["map"]
	var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for v in verts.size():
		verts[v] = points[map[v]] + moved[map[v]]
	# Face normals summed per welded place, so a seam shades as one.
	var sums := {}
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0, index.size() - 2, 3):
		var a := verts[index[t]]
		var b := verts[index[t + 1]]
		var c := verts[index[t + 2]]
		var face := (b - a).cross(c - a)
		for k in 3:
			var at := map[index[t + k]]
			sums[at] = sums.get(at, Vector3.ZERO) + face
	var normals: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	for v in normals.size():
		var shift := moved[map[v]].length()
		var made: Vector3 = sums.get(map[v], Vector3.ZERO)
		if shift > 0.0005 and made.length() > 0.0:
			made = made.normalized()
			# The pack winds its triangles the other way round: keep the
			# made normal on the side the old one faced.
			if made.dot(normals[v]) < 0.0:
				made = -made
			# The cloth's own normal, all of it in the zones: the body's
			# curves under the cloth must not show in the light.
			var share := 1.0 if kinds[map[v]] != 0 else clampf(shift / 0.006, 0.0, 1.0)
			normals[v] = normals[v].lerp(made, share).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var source := node.mesh
	# Through an ImporterMesh to make its levels of detail again, as the
	# body's import did (`meshes/generate_lods`): without them a far body
	# draws all of its triangles, the costliest part of a crowd on a
	# laptop's graphics.
	var made := ImporterMesh.new()
	made.add_surface(source.surface_get_primitive_type(0), arrays, [], {}, source.surface_get_material(0),
			source.surface_get_name(0), source.surface_get_format(0) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	made.generate_lods(LOD_MERGE_ANGLE, 0.0, [])
	return made.get_mesh()
