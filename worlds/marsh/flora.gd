extends RefCounted
## The Spore Marsh's scale and floor (DESIGN.md "The Spore Marsh (part
## three)"): view only, built by the map's `_dress` where `Look` is on, from
## its own random numbers so it never moves the layout.
##
## Far off in the haze, past the hills, stand the elders (fungus stalks two
## to three hundred metres tall, their gills glowing through the mist) and
## the root arches (roots the size of bridges that rise out of the ground
## and plunge back in). Up close the forest floors grow curled ferns,
## ribbed spires, ochre fronds and trumpet caps with glowing throats. The
## palette is the marsh's own: mauve flesh, jade glow, olive moss, black
## water, with ochre as the warm accent.

## How many of each far giant, and where they stand (metres from the middle).
const ELDERS := 7
const ARCHES := 5
const GIANT_NEAR := 430.0
const GIANT_FAR := 900.0
## The tallest stalk of an elder cluster, metres.
const ELDER_HEIGHT := Vector2(230.0, 420.0)
## Tube sides and steps along a root arch.
const ARCH_SIDES := 12
const ARCH_STEPS := 28


## The far giants into `art`. `height_of(x, z)` is the ground, near or far.
## Each elder is a cluster of two or three stalks leaning together. Drawn
## with `giant_haze.gdshader`, whose "veil" the map sets from the close air
## and the storm round the viewer (`set_veil`).
static func build_giants(map: Node3D, art: Node3D, height_of: Callable, seed: int, haze: Color) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var flesh := SurfaceTool.new()
	flesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gills := SurfaceTool.new()
	gills.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spot: Dictionary in giant_spots(seed):
		var at: Vector2 = spot.at
		var foot := Vector3(at.x, float(height_of.call(at.x, at.y)) - 3.0, at.y)
		if spot.kind == "elder":
			for k in rng.randi_range(2, 3):
				var h := rng.randf_range(ELDER_HEIGHT.x, ELDER_HEIGHT.y) * (1.0 if k == 0 else rng.randf_range(0.5, 0.8))
				var off := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * h * 0.18 * float(k)
				map.call("_fungus", flesh, gills, {"at": foot + off, "height": h,
						"radius": h * rng.randf_range(0.05, 0.065), "cap": h * rng.randf_range(0.3, 0.42)})
		else:
			_arch(flesh, foot, float(spot.heading), rng)
	var shader := load("res://assets/shaders/giant_haze.gdshader") as Shader
	var flesh_mat := ShaderMaterial.new()
	flesh_mat.shader = shader
	flesh_mat.set_shader_parameter("haze", haze)
	flesh_mat.set_shader_parameter("shade", haze.darkened(0.72))
	var gill_mat := flesh_mat.duplicate() as ShaderMaterial
	gill_mat.set_shader_parameter("gills", 1.0)
	flesh.generate_normals()
	gills.generate_normals()
	flesh.set_material(flesh_mat)
	gills.set_material(gill_mat)
	var mesh := flesh.commit()
	gills.commit(mesh)
	var node := MeshInstance3D.new()
	node.name = "Giants"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(node)
	return node


## Hides the giants by `amount` (0 clear, 1 gone into the haze).
static func set_veil(giants: MeshInstance3D, amount: float) -> void:
	if giants == null or giants.mesh == null:
		return
	for i in giants.mesh.get_surface_count():
		var mat := giants.mesh.surface_get_material(i) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("veil", amount)
	giants.visible = amount < 0.98


## Where the far giants stand: spread round the basin, never two close, from
## the seed alone. Each a dictionary with "kind", "at" and "heading".
static func giant_spots(seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Dictionary] = []
	var count := ELDERS + ARCHES
	for i in count:
		# Even-ish round the compass, nudged, so no side of the sky is bare.
		var bearing := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / count
		var reach := rng.randf_range(GIANT_NEAR, GIANT_FAR)
		var kind := "arch" if i % 2 == 1 and out.filter(func(s: Dictionary) -> bool: return s.kind == "arch").size() < ARCHES else "elder"
		out.append({"kind": kind, "at": Vector2.from_angle(bearing) * reach, "heading": bearing + PI * 0.5 + rng.randf_range(-0.6, 0.6)})
	return out


## A root arch: a thick tube rising out of the ground on a lopsided curve
## and plunging back in, knotted along its length.
static func _arch(st: SurfaceTool, foot: Vector3, heading: float, rng: RandomNumberGenerator) -> void:
	var span := rng.randf_range(120.0, 260.0)
	var rise := span * rng.randf_range(0.35, 0.6)
	var thick := span * rng.randf_range(0.035, 0.055)
	var lean := rng.randf_range(-0.25, 0.25)
	var along := Vector3(cos(heading), 0, sin(heading))
	var side := Vector3(-along.z, 0, along.x)
	var start := foot - along * span * 0.5
	var tone := Color(0.0, 0.5, 0.5, 1.0)
	var rings: Array[PackedVector3Array] = []
	for k in ARCH_STEPS + 1:
		var t := float(k) / ARCH_STEPS
		var centre := _arch_point(start, along, side, span, rise, thick, lean, t)
		var ahead_t := minf(t + 0.02, 1.0)
		var back_t := maxf(t - 0.02, 0.0)
		var tangent := (_arch_point(start, along, side, span, rise, thick, lean, ahead_t)
				- _arch_point(start, along, side, span, rise, thick, lean, back_t)).normalized()
		var normal := tangent.cross(side).normalized()
		var binormal := tangent.cross(normal).normalized()
		# Thickest where it meets the ground, knotted in places.
		var r := thick * (1.0 + 0.7 * pow(1.0 - sin(PI * t), 3.0)) * (1.0 + 0.18 * sin(t * 31.0 + heading * 5.0))
		var ring := PackedVector3Array()
		for s in ARCH_SIDES:
			var a := TAU * s / ARCH_SIDES
			ring.append(centre + (normal * cos(a) + binormal * sin(a)) * r)
		rings.append(ring)
	for k in rings.size() - 1:
		var a_ring := rings[k]
		var b_ring := rings[k + 1]
		for s in ARCH_SIDES:
			var s2 := (s + 1) % ARCH_SIDES
			var v0 := float(k) / ARCH_STEPS
			var v1 := float(k + 1) / ARCH_STEPS
			var quad := [[a_ring[s], v0], [b_ring[s], v1], [b_ring[s2], v1], [a_ring[s], v0], [b_ring[s2], v1], [a_ring[s2], v0]]
			for corner: Array in quad:
				st.set_color(tone)
				st.set_uv(Vector2(float(s) / ARCH_SIDES, 0.15 + 0.6 * corner[1]))
				st.add_vertex(corner[0])


## A point along an arch: steeper going in than coming out, and a little
## sideways.
static func _arch_point(start: Vector3, along: Vector3, side: Vector3, span: float, rise: float, thick: float,
		lean: float, t: float) -> Vector3:
	var bend := pow(sin(PI * t), 0.8) * (1.0 + lean * (t - 0.5))
	return start + along * span * t + Vector3(0, rise * bend - thick * 0.6, 0) + side * sin(PI * t) * span * 0.08 * lean * 4.0


# --- The forest floor -------------------------------------------------------------

## How many of each plant, over the forests' floors and their edges.
const FERNS := 1800
const SPIRES := 260
const FRONDS := 1400
const TRUMPETS := 440
## The palette: the marsh's own, ochre the warm accent to its jade glow.
const FERN_DARK := Color(0.07, 0.09, 0.05)
const FERN_TIP := Color(0.2, 0.32, 0.18)
const SPIRE_FLESH := Color(0.2, 0.16, 0.19)
const SPIRE_RIM := Color(0.42, 0.37, 0.36)
const FROND_STEM := Color(0.2, 0.18, 0.08)
const FROND_TIP := Color(0.78, 0.52, 0.16)
const TRUMPET_SHELL := Color(0.22, 0.16, 0.21)
const TRUMPET_LIP := Color(0.45, 0.36, 0.4)
const TRUMPET_THROAT := Color(0.35, 1.0, 0.72)


## The forest floor's plants into `art`, each kind one MultiMesh.
static func build_floor(map: Node3D, art: Node3D, seed: int) -> Array[MultiMeshInstance3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[MultiMeshInstance3D] = []
	out.append(_plant(art, "Ferns", _fern_mesh(), _scatter(map, rng, FERNS, 4, 0.25, Vector2(0.7, 1.5)), false))
	out.append(_plant(art, "Spires", _spire_mesh(), _scatter(map, rng, SPIRES, 2, 1.2, Vector2(0.6, 2.0)), true))
	out.append(_plant(art, "Fronds", _frond_mesh(), _scatter(map, rng, FRONDS, 3, 0.3, Vector2(0.6, 1.4)), false))
	out.append(_plant(art, "Trumpets", _trumpet_mesh(), _scatter(map, rng, TRUMPETS, 3, 0.8, Vector2(1.0, 2.8)), false))
	return out


static func _plant(art: Node3D, title: String, mesh: Mesh, spots: Array[Transform3D], shadow: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(node)
	return node


## Spots over the forests' floors and just past their edges, in clumps of
## up to `clump`, on dry ground and clear of the trunks by `clear`.
static func _scatter(map: Node3D, rng: RandomNumberGenerator, count: int, clump: int, clear: float,
		size: Vector2) -> Array[Transform3D]:
	var consts: Dictionary = map.get_script().get_script_constant_map()
	var forests: Array = consts["FORESTS"]
	var water := float(consts["WATER_Y"])
	var spots: Array[Transform3D] = []
	var tries := 0
	while spots.size() < count and tries < count * 8:
		tries += 1
		var forest: Dictionary = forests[rng.randi() % forests.size()]
		var centre: Vector2 = forest["at"]
		# Thickest under the caps, thinning out past the edge.
		var at := centre + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (float(forest["radius"]) + 10.0)
		for k in rng.randi_range(1, clump):
			var p := at + Vector2(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.4, 1.4)) * float(k)
			var ground := float(map.call("ground_height", p.x, p.y))
			if ground < water + 0.05 or not bool(map.call("_clear_of_stalks", p, clear)) \
					or bool(map.call("in_cut", p.x, p.y)):
				continue
			var s := rng.randf_range(size.x, size.y)
			var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.18))
			var basis := tilt * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
			spots.append(Transform3D(basis, Vector3(p.x, ground - 0.05, p.y)))
	return spots


## A tube along `points`, `radii` thick at each, coloured `colours`, into `st`.
static func _tube(st: SurfaceTool, points: PackedVector3Array, radii: PackedFloat32Array, colours: Array[Color], sides: int) -> void:
	var rings: Array[PackedVector3Array] = []
	for i in points.size():
		var ahead := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var t := ahead.normalized()
		var ref := Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
		var n := t.cross(ref).normalized()
		var b := t.cross(n).normalized()
		var ring := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			ring.append(points[i] + (n * cos(a) + b * sin(a)) * radii[i])
		rings.append(ring)
	for i in rings.size() - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			for corner: Array in [[i, s], [i + 1, s], [i + 1, s2], [i, s], [i + 1, s2], [i, s2]]:
				st.set_color(colours[corner[0]])
				st.add_vertex(rings[corner[0]][corner[1]])


static func _finish(st: SurfaceTool, emission := Color.BLACK, energy := 0.0) -> ArrayMesh:
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	st.set_material(mat)
	return st.commit()


## A clump of fiddleheads: stems that rise and curl into a tight spiral.
static func _fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for f in 5:
		var a := TAU * f / 5.0 + rng.randf() * 0.6
		var out := Vector3(cos(a), 0, sin(a))
		var tall := rng.randf_range(0.6, 1.1)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var cols: Array[Color] = []
		var steps := 22
		for i in steps + 1:
			var t := float(i) / steps
			var p: Vector3
			if t < 0.5:
				var u := t / 0.5
				p = out * (0.06 + u * 0.12) + Vector3(0, u * tall, 0)
			else:
				# The curl: up, over outward and round in, tighter each turn.
				var u := (t - 0.5) / 0.5
				var turn := u * TAU * 1.3
				var r := 0.13 * (1.0 - u * 0.75)
				var centre := out * (0.18 + 0.13) + Vector3(0, tall, 0)
				p = centre + (-out * cos(turn) + Vector3.UP * sin(turn)) * r
			pts.append(p)
			radii.append(lerpf(0.022, 0.008, t))
			cols.append(FERN_DARK.lerp(FERN_TIP, smoothstep(0.55, 1.0, t)))
		_tube(st, pts, radii, cols, 5)
	return _finish(st, FERN_TIP, 0.15)


## A ribbed spire: a tapering stem ringed with flared plates, pale at
## their rims.
static func _spire_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tall := 2.2
	var plates := 13
	var sides := 10
	for p in plates:
		var t := float(p) / plates
		var y0 := t * tall
		var y1 := y0 + tall / plates * 0.85
		var r_in := lerpf(0.16, 0.03, t)
		var r_out := lerpf(0.34, 0.07, t) * (1.0 + 0.15 * sin(p * 1.7))
		# Each plate a short flared band: in at its foot, out at its lip.
		var rings: Array[PackedVector3Array] = []
		var tones: Array[Color] = [SPIRE_FLESH.darkened(0.3), SPIRE_FLESH, SPIRE_RIM]
		for k in 3:
			var ring := PackedVector3Array()
			var y := lerpf(y0, y1, [0.0, 0.55, 1.0][k])
			var r := lerpf(r_in, r_out, [0.0, 0.6, 1.0][k])
			for s in sides:
				var a := TAU * s / sides
				ring.append(Vector3(cos(a) * r, y, sin(a) * r))
			rings.append(ring)
		for k in 2:
			for s in sides:
				var s2 := (s + 1) % sides
				for corner: Array in [[k, s], [k + 1, s], [k + 1, s2], [k, s], [k + 1, s2], [k, s2]]:
					st.set_color(tones[corner[0]])
					st.add_vertex(rings[corner[0]][corner[1]])
		# The plate's top, back in to the stem above.
		for s in sides:
			var s2 := (s + 1) % sides
			var inner := Vector3(cos(TAU * s / sides), 0, sin(TAU * s / sides)) * lerpf(0.16, 0.03, t + 1.0 / plates)
			var inner2 := Vector3(cos(TAU * s2 / sides), 0, sin(TAU * s2 / sides)) * lerpf(0.16, 0.03, t + 1.0 / plates)
			inner.y = y1 + 0.02
			inner2.y = y1 + 0.02
			for corner: Array in [[rings[2][s], SPIRE_RIM], [inner, SPIRE_FLESH.darkened(0.2)], [inner2, SPIRE_FLESH.darkened(0.2)],
					[rings[2][s], SPIRE_RIM], [inner2, SPIRE_FLESH.darkened(0.2)], [rings[2][s2], SPIRE_RIM]]:
				st.set_color(corner[1])
				st.add_vertex(corner[0])
	return _finish(st)


## Ochre fronds: thin stems that fork twice into flat, lit tips.
static func _frond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for f in 4:
		var a := TAU * f / 4.0 + rng.randf() * 0.8
		var dir := Vector3(cos(a) * 0.35, 1.0, sin(a) * 0.35).normalized()
		_fork(st, Vector3(cos(a), 0, sin(a)) * 0.05, dir, rng.randf_range(0.35, 0.55), 0.016, 2, rng)
	return _finish(st, FROND_TIP, 0.35)


static func _fork(st: SurfaceTool, from: Vector3, dir: Vector3, length: float, width: float, depth: int, rng: RandomNumberGenerator) -> void:
	var to := from + dir * length
	var pts := PackedVector3Array([from, from.lerp(to, 0.5) + Vector3(0, 0.02, 0), to])
	var tip := float(2 - depth) / 2.0
	var cols: Array[Color] = [FROND_STEM.lerp(FROND_TIP, tip * 0.6), FROND_STEM.lerp(FROND_TIP, tip * 0.8), FROND_STEM.lerp(FROND_TIP, tip)]
	_tube(st, pts, PackedFloat32Array([width, width * 0.85, width * 0.7]), cols, 4)
	if depth == 0:
		# A soft leaf that droops and curls under at its end, never a point.
		var side := dir.cross(Vector3.UP).normalized()
		var flat := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3.FORWARD
		var leaf := length * 0.9
		var rows: Array[Vector3] = []
		var halves: Array[float] = []
		for i in 5:
			var t := float(i) / 4.0
			rows.append(to + dir * leaf * t * 0.6 + flat * leaf * t * 0.5 - Vector3.UP * leaf * t * t * 0.7)
			halves.append(width * (1.0 + 4.0 * sin(t * PI) * (1.0 - 0.3 * t)))
		for i in 4:
			var a := rows[i]
			var b := rows[i + 1]
			var ca := FROND_STEM.lerp(FROND_TIP, 0.85 + 0.15 * i / 3.0)
			for v: Vector3 in [a - side * halves[i], a + side * halves[i], b + side * halves[i + 1], a - side * halves[i], b + side * halves[i + 1], b - side * halves[i + 1]]:
				st.set_color(ca)
				st.add_vertex(v)
		return
	for k in 2:
		var spread := (1.0 if k == 0 else -1.0) * rng.randf_range(0.35, 0.6)
		var axis := dir.cross(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))).normalized()
		if axis.length() < 0.1:
			axis = Vector3.RIGHT
		_fork(st, to, dir.rotated(axis, spread), length * 0.72, width * 0.7, depth - 1, rng)


## A trumpet cap: a horn of flesh flaring to a curled lip, its throat glowing.
static func _trumpet_mesh() -> ArrayMesh:
	var mesh: ArrayMesh
	var shell := SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	var throat := SurfaceTool.new()
	throat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 16
	var steps := 9
	var outer: Array[PackedVector3Array] = []
	var inner: Array[PackedVector3Array] = []
	for i in steps + 1:
		var t := float(i) / steps
		var r := 0.07 + 0.5 * pow(t, 2.6)
		var y := t * 1.2 + (0.05 * pow(t, 6.0))
		var ring := PackedVector3Array()
		var ring_in := PackedVector3Array()
		for s in sides:
			var a := TAU * s / sides
			var wave := 1.0 + 0.09 * sin(a * 5.0) * t * t
			ring.append(Vector3(cos(a) * r * wave, y - 0.04 * sin(a * 5.0) * t * t, sin(a) * r * wave))
			ring_in.append(Vector3(cos(a) * r * wave * 0.9, y - 0.03 - 0.04 * sin(a * 5.0) * t * t, sin(a) * r * wave * 0.9))
		outer.append(ring)
		inner.append(ring_in)
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		for s in sides:
			var s2 := (s + 1) % sides
			for corner: Array in [[i, s, t0], [i + 1, s, t1], [i + 1, s2, t1], [i, s, t0], [i + 1, s2, t1], [i, s2, t0]]:
				shell.set_color(TRUMPET_SHELL.lerp(TRUMPET_LIP, pow(corner[2], 3.0)))
				shell.add_vertex(outer[corner[0]][corner[1]])
				throat.set_color(TRUMPET_THROAT.darkened(0.6 * (1.0 - corner[2])))
				throat.add_vertex(inner[corner[0]][corner[1]])
	mesh = _finish(shell)
	throat.generate_normals()
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.emission_enabled = true
	glow.emission = TRUMPET_THROAT
	glow.emission_energy_multiplier = 0.7
	throat.set_material(glow)
	throat.commit(mesh)
	return mesh
