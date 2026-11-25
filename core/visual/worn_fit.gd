extends RefCounted
## Where worn gear can go without sinking into the body or what is already
## worn over it: the outside of everything on a body at rest, in the actor's
## frame (feet at 0, front -Z, metres), as `ActorSkin` puts the gear on.
## The body's skin comes from its measurements (`body_fit.gd`) and the
## armor from its meshes, worked out once per build and frame in the body's
## measured metres and read scaled and moved to where this body stands;
## each piece of gear placed so far is added as the boxes round its meshes
## (`boxes`), which is cheap and never smaller than the gear.
##
## It keeps three height maps of that outside on a `CELL` grid: how far back
## it reaches over each spot of the back (x, y), and how far out to the
## right and to the left over each spot of the sides (y, z). A piece of gear
## is pushed straight back, or out to one side, until every point of it is
## `clear` beyond the outside (`back_gap`, `side_gap`), then added to it,
## so the next piece goes over it. A strap is laid over the top of a
## shoulder by casting in from outside until it meets the outside
## (`cast_in`), and a cuff round a leg opened until it clears (`widen`).
## View only.
##
## Load with `const WornFit := preload("res://core/visual/worn_fit.gd")`.

const BodyFit := preload("res://core/visual/body_fit.gd")
const ArmorModel := preload("res://core/visual/armor_model.gd")

const CELL := 0.01
## How far apart points are taken over a face.
const STEP := 0.012
## How far apart points are taken over a box round a piece of gear.
const BOX_STEP := 0.03
## How far apart the points `cloud` keeps are, at least.
const THIN := 0.008
## How many cells round each point of gear a gap reads the outside over:
## enough to cover the space between box points however the box is turned
## (a gun slung across the back), so no ridge slips between them. Points
## as close as `cloud`'s need only 1.
const SPREAD := 2
const NEAR: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## Back: Vector2i(x, y) -> furthest +Z; front the same -Z. Right: Vector2i(y, z) -> furthest
## +X. Left: Vector2i(y, z) -> furthest -X. `solid`: every cell something
## is in, for casting. `all`: every point added. Gear only; the body and
## armor's are in `base`.
var back := {}
var front := {}
var right := {}
var left := {}
var solid := {}
var all := PackedVector3Array()

## The body and its armor: maps in the body's measured metres, and how
## they are read here (actor = measured * `scale` + `shift`).
var base := {}
var scale := 1.0
var shift := Vector3.ZERO

## Each build's skin at rest, measured metres: {"back", "right", "left",
## "solid" (as above), "legs" (points round both legs)}; and each build's
## with a frame's armor on it, by "build|frame" ("legs" then has the armor's
## points too).
static var _bodies := {}
static var _bases := {}


## A body of `build`, `body_scale` its size against its measurements and
## `body_shift` where it stands against them, wearing frame `frame` (a key,
## "" for none): `armor` gives its points (actor frame) the first time
## that build and frame are met.
func _init(build: String, frame: String, body_scale: float, body_shift: Vector3, armor: Callable) -> void:
	scale = body_scale
	shift = body_shift
	var b := BodyFit.build_of(build)
	if not _bodies.has(b):
		_bodies[b] = _measure(b)
	var key := b + "|" + frame
	if frame == "":
		base = _bodies[b]
		return
	if not _bases.has(key):
		var maps: Dictionary = (_bodies[b] as Dictionary).duplicate(true)
		var raw := PackedVector3Array()
		for p: Vector3 in armor.call():
			raw.append((p - shift) / scale)
		_fill(maps["back"], maps["front"], maps["right"], maps["left"], maps["solid"], raw)
		# A packed array is a value: append to a copy and put it back.
		var legs: PackedVector3Array = maps["legs"]
		legs.append_array(raw)
		maps["legs"] = legs
		_bases[key] = maps
	base = _bases[key]


## The trunk all round and the legs down to the ankle, as maps.
static func _measure(build: String) -> Dictionary:
	var maps := {"back": {}, "front": {}, "right": {}, "left": {}, "solid": {}, "legs": PackedVector3Array()}
	var points := PackedVector3Array()
	var y := BodyFit.trunk_low()
	var high := BodyFit.trunk_top(build)
	while y <= high:
		for i in 64:
			points.append(BodyFit.trunk_point(build, y, TAU * i / 64.0))
		y += 0.01
	var legs := PackedVector3Array()
	for out: float in [-1.0, 1.0]:
		for part: String in ["UpperLeg", "LowerLeg"]:
			var limb := ArmorModel.Limb.new(build, part, out)
			var length := BodyFit.limb_length(build, part)
			var along := 0.0
			while along <= length:
				for i in 32:
					legs.append(limb.frame * BodyFit.limb_point(build, part, along, TAU * i / 32.0, out))
				along += 0.015
	points.append_array(legs)
	_fill(maps["back"], maps["front"], maps["right"], maps["left"], maps["solid"], points)
	maps["legs"] = legs
	return maps


static func _fill(b: Dictionary, f: Dictionary, r: Dictionary, l: Dictionary, s: Dictionary, points: PackedVector3Array) -> void:
	for p in points:
		var bk := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		b[bk] = maxf(b.get(bk, -INF), p.z)
		f[bk] = minf(f.get(bk, INF), p.z)
		var sk := Vector2i(floori(p.y / CELL), floori(p.z / CELL))
		r[sk] = maxf(r.get(sk, -INF), p.x)
		l[sk] = minf(l.get(sk, INF), p.x)
		s[Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))] = true


func add_points(points: PackedVector3Array) -> void:
	all.append_array(points)
	_fill(back, front, right, left, solid, points)


## Points over the faces of every shown mesh under `root`, `xf` taking
## `root`'s frame to the actor's. Meshes named in `skip` (or under a node
## so named) are left out, and hidden ones, unless `shown` (`root` itself
## counts as shown: a weapon in hand still has its place).
static func sample(root: Node3D, xf: Transform3D, skip: Array = [], shown := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	_sample(root, xf, skip, out, shown)
	return out


## `sample`'s points of `root` in its own frame, thinned to one a few
## millimetres apart, worked out once for each shape (a weapon model is the
## same wherever it hangs). `root` should not be scaled itself.
static func cloud(root: Node3D, skip: Array = []) -> PackedVector3Array:
	var key := _shape_key(root, Transform3D.IDENTITY, skip, true)
	if _clouds.has(key):
		return _clouds[key]
	var seen := {}
	var out := PackedVector3Array()
	for p in sample(root, Transform3D.IDENTITY, skip, true):
		var cell := Vector3i(floori(p.x / THIN), floori(p.y / THIN), floori(p.z / THIN))
		if not seen.has(cell):
			seen[cell] = true
			out.append(p)
	_clouds[key] = out
	return out


static var _clouds := {}


## What `sample` would read under `node`: each shown mesh and where it is.
static func _shape_key(node: Node, xf: Transform3D, skip: Array, shown := false) -> String:
	if str(node.name) in skip or (not shown and node is Node3D and not (node as Node3D).visible):
		return ""
	var key := ""
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		# By its size and make, not the mesh itself: a model merged as it
		# is hung is a new mesh on every body (the same shape all the same),
		# and a freed mesh's id goes to the next one made.
		key = "%s%s%s" % [mi.mesh.get_class(), mi.mesh.get_aabb(), xf]
		var arrays := mi.mesh as ArrayMesh
		if arrays != null:
			for k in arrays.get_surface_count():
				key += "," + str(arrays.surface_get_array_len(k))
		key += ";"
	for child in node.get_children():
		var n3 := child as Node3D
		key += _shape_key(child, xf * n3.transform if n3 else xf, skip)
	return key


static func _sample(node: Node, xf: Transform3D, skip: Array, out: PackedVector3Array, shown := false) -> void:
	if str(node.name) in skip or (not shown and node is Node3D and not (node as Node3D).visible):
		return
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var index := PackedInt32Array(arr[Mesh.ARRAY_INDEX]) if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var indexed := not index.is_empty()
			var count := index.size() if indexed else verts.size()
			var at := PackedVector3Array()
			at.resize(verts.size())
			for i in verts.size():
				at[i] = xf * verts[i]
			# Every corner once, then points across the faces too big to
			# leave between their corners.
			out.append_array(at)
			for t in range(0, count, 3):
				var a := at[index[t] if indexed else t]
				var b := at[index[t + 1] if indexed else t + 1]
				var c := at[index[t + 2] if indexed else t + 2]
				var n := ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / STEP)
				if n < 2:
					continue
				for i in n + 1:
					for j in n + 1 - i:
						out.append(a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n))
	for child in node.get_children():
		var n3 := child as Node3D
		_sample(child, xf * n3.transform if n3 else xf, skip, out)


## How far back the outside reaches over the cell column `ix`, `iy`, or
## -INF where nothing is.
func _back_at(ix: int, iy: int) -> float:
	var z: float = back.get(Vector2i(ix, iy), -INF)
	var mid := Vector2((ix + 0.5) * CELL - shift.x, (iy + 0.5) * CELL - shift.y) / scale
	var bz: float = base["back"].get(Vector2i(floori(mid.x / CELL), floori(mid.y / CELL)), -INF)
	return maxf(z, bz * scale + shift.z if bz > -INF else -INF)


## How far forward (-Z, as a +Z value negated) the outside reaches over the
## cell column `ix`, `iy`, or -INF where nothing is.
func _front_at(ix: int, iy: int) -> float:
	var z: float = front.get(Vector2i(ix, iy), INF)
	var mid := Vector2((ix + 0.5) * CELL - shift.x, (iy + 0.5) * CELL - shift.y) / scale
	var bz: float = base["front"].get(Vector2i(floori(mid.x / CELL), floori(mid.y / CELL)), INF)
	return maxf(-z, -(bz * scale + shift.z) if bz < INF else -INF)


## Where the outside is furthest back (`dir_z` 1) or forward (-1) across
## `x0` to `x1` at height `y`, plus `gap` that way; `z` when nothing is there.
func surface_z(x0: float, x1: float, y: float, dir_z: float, gap: float, z: float) -> float:
	var best := -INF
	# Two cells up and down: the straps take a point every two centimetres.
	for ix in range(floori(x0 / CELL), floori(x1 / CELL) + 1):
		for dy in range(-2, 3):
			best = maxf(best, _back_at(ix, floori(y / CELL) + dy) if dir_z > 0.0 else _front_at(ix, floori(y / CELL) + dy))
	return (best + gap) * dir_z if best > -INF else z


## How far out along `side` the outside reaches over the cell row `iy`,
## `iz` (x times `side`), or -INF where nothing is.
func _side_at(iy: int, iz: int, side: float) -> float:
	var x: float = (right if side > 0.0 else left).get(Vector2i(iy, iz), -INF * side)
	var mid := Vector2((iy + 0.5) * CELL - shift.y, (iz + 0.5) * CELL - shift.z) / scale
	var bx: float = base["right" if side > 0.0 else "left"].get(Vector2i(floori(mid.x / CELL), floori(mid.y / CELL)), -INF * side)
	return maxf(x * side, (bx * scale + shift.x) * side if is_finite(bx) else -INF)


## How far `points` must move back (+Z) for every one of them to be
## `clear` behind the outside, or how far they may come in when they are
## further out (negative): snug against it. 0 when nothing is in front of
## them.
func back_gap(points: PackedVector3Array, clear: float, spread := SPREAD) -> float:
	# Only the point furthest in over each cell matters.
	var seen := {}
	for p in points:
		var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		if not seen.has(key) or seen[key] > p.z:
			seen[key] = p.z
	# Each cell's own reach read once, then against the cells round it.
	var reach := {}
	var need := -INF
	for key: Vector2i in seen:
		for dx in range(-spread, spread + 1):
			for dy in range(-spread, spread + 1):
				var at := Vector2i(key.x + dx, key.y + dy)
				if not reach.has(at):
					reach[at] = _back_at(at.x, at.y)
				var z: float = reach[at]
				if z > -INF:
					need = maxf(need, z + clear - (seen[key] as float))
	return need if need > -INF else 0.0


## The same out to one side: `side` 1 pushes along +X, -1 along -X.
func side_gap(points: PackedVector3Array, side: float, clear: float, spread := SPREAD) -> float:
	var seen := {}
	for p in points:
		var key := Vector2i(floori(p.y / CELL), floori(p.z / CELL))
		if not seen.has(key) or seen[key] > p.x * side:
			seen[key] = p.x * side
	var reach := {}
	var need := -INF
	for key: Vector2i in seen:
		for dy in range(-spread, spread + 1):
			for dz in range(-spread, spread + 1):
				var at := Vector2i(key.x + dy, key.y + dz)
				if not reach.has(at):
					reach[at] = _side_at(at.x, at.y, side)
				var x: float = reach[at]
				if x > -INF:
					need = maxf(need, x + clear - (seen[key] as float))
	return need if need > -INF else 0.0


## Points over the boxes round each shown mesh under `root` (as `sample`):
## a stand-in for gear that is never smaller than it, cheap to take.
static func boxes(root: Node3D, xf: Transform3D, skip: Array = [], shown := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	_boxes(root, xf, skip, out, shown)
	return out


static func _boxes(node: Node, xf: Transform3D, skip: Array, out: PackedVector3Array, shown := false) -> void:
	if str(node.name) in skip or (not shown and node is Node3D and not (node as Node3D).visible):
		return
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		box_points(mi.mesh.get_aabb(), xf, out)
	for child in node.get_children():
		var n3 := child as Node3D
		_boxes(child, xf * n3.transform if n3 else xf, skip, out)


## Points over the six faces of `box`, `xf` taking it to the actor's frame.
static func box_points(box: AABB, xf: Transform3D, out: PackedVector3Array) -> void:
	# Spaced in the actor's frame: a model is often scaled where it hangs.
	var n := Vector3i.ZERO
	for axis in 3:
		n[axis] = maxi(1, ceili((xf.basis[axis] * box.size[axis]).length() / BOX_STEP))
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for face: float in [0.0, 1.0]:
			for i in n[u] + 1:
				for j in n[v] + 1:
					var f := Vector3.ZERO
					f[axis] = face
					f[u] = float(i) / n[u]
					f[v] = float(j) / n[v]
					out.append(xf * (box.position + box.size * f))


## Whether anything is in the cell `p` falls in or its neighbours.
func _solid(p: Vector3) -> bool:
	var c := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
	var m := (p - shift) / scale
	var b := Vector3i(floori(m.x / CELL), floori(m.y / CELL), floori(m.z / CELL))
	var body_solid: Dictionary = base["solid"]
	for k: Vector3i in NEAR:
		if solid.has(c + k) or body_solid.has(b + k):
			return true
	return false


## How much a ring round an upright axis through `centre`, from `low` to
## `high`, with radius `rx` across and `rz` front to back inside, must be
## widened to stand `clear` off everything inside it there: a scale across
## and one front to back (each at least 1), the least that clears, so a leg
## deeper than it is wide widens it front to back. Only what is within
## `reach` of the axis counts (not the other leg).
func widen(centre: Vector3, low: float, high: float, rx: float, rz: float, clear: float, reach := 0.13) -> Vector2:
	var near := PackedVector2Array()
	for p in all:
		if p.y >= low and p.y <= high and Vector2(p.x - centre.x, p.z - centre.z).length() <= reach:
			near.append(Vector2(p.x - centre.x, p.z - centre.z))
	for q: Vector3 in base["legs"]:
		var p := q * scale + shift
		if p.y >= low and p.y <= high and Vector2(p.x - centre.x, p.z - centre.z).length() <= reach:
			near.append(Vector2(p.x - centre.x, p.z - centre.z))
	var s := Vector2.ONE
	for pass_i in 8:
		var moved := false
		for d in near:
			# Out from the axis by `clear`, against the ring as widened so far.
			var o := d + d.normalized() * clear if d.length() > 0.0001 else d
			var a := o.x / (rx * s.x)
			var b := o.y / (rz * s.y)
			if a * a + b * b <= 1.0:
				continue
			moved = true
			# Widen the way that point leans: across, or front to back.
			if absf(a) >= absf(b):
				s.x = maxf(s.x, absf(o.x) / (rx * sqrt(maxf(1.0 - minf(b * b, 0.5), 0.0001))))
			else:
				s.y = maxf(s.y, absf(o.y) / (rz * sqrt(maxf(1.0 - minf(a * a, 0.5), 0.0001))))
		if not moved:
			break
	return s


## Where a ray toward `to` from `dist` beyond it, coming in along `-dir`,
## first meets the outside, stood `gap` off it; `to` + `dir` * `gap` when
## it meets nothing.
func cast_in(to: Vector3, dir: Vector3, dist: float, gap: float) -> Vector3:
	var d := dist
	while d > 0.0:
		if _solid(to + dir * d):
			return to + dir * (d + gap)
		d -= CELL
	return to + dir * gap
