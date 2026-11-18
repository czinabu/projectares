class_name PlanetProps
extends RefCounted
## What lies on a planet's ground (DESIGN.md "Planet kit"): boulders, slabs,
## spires and buttes, ice shards, glowing crystals and fungal stalks, made
## in code from noise rather than loaded, so every planet type has its own
## without new art files.
##
## Cheap by construction: each kind is made in a few variants once per run
## (`_meshes`, shared by every copy of a map and every world on the type),
## each with generated levels of detail, and placed with one
## `MultiMeshInstance3D` per variant, which fades out by distance by size
## (`visibility_range_end`). Rock is drawn with the planet's ground material,
## so it wears the same strata, colour and cap as the slopes round it.
## View only, like the rest of the dressing: never collision, and placed with
## its own random numbers so it cannot shift a map's layout. A prop big
## enough to matter for cover is a map's business, built as a solid.

const VARIANTS := 4

static var _meshes := {}


## Scatters `type.props` over the square map `half` metres from its middle
## to each edge, standing them on `height_of(x, z)`. `clear(x, z)` may
## refuse a spot (a road, a base). Big kinds marked "out" also stand beyond
## the edge, on the horizon's near ground, so the map does not end in a line.
static func scatter(parent: Node3D, type: PlanetType, height_of: Callable, half: float, seed_value: int,
		clear := Callable()) -> void:
	if not Look.enabled:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = "Props"
	parent.add_child(root)
	for entry: Dictionary in type.props:
		var kind: String = entry["kind"]
		var size: Vector2 = entry.get("size", Vector2(1.0, 2.0))
		var out := float(entry.get("out", 0.0))
		var reach := half * (2.2 if out > 0.0 else 1.0)
		var area := (reach * 2.0) * (reach * 2.0) / 10000.0
		var count := int(float(entry.get("per_ha", 1.0)) * area)
		var places: Array = []
		for v in VARIANTS:
			places.append([])
		var tries := count * 3
		while count > 0 and tries > 0:
			tries -= 1
			var x := rng.randf_range(-reach, reach)
			var z := rng.randf_range(-reach, reach)
			if out > 0.0 and maxf(absf(x), absf(z)) < half * out:
				continue
			if clear.is_valid() and not clear.call(x, z):
				continue
			var h: float = height_of.call(x, z)
			var slope := Vector2(float(height_of.call(x + 2.0, z)) - float(height_of.call(x - 2.0, z)),
					float(height_of.call(x, z + 2.0)) - float(height_of.call(x, z - 2.0))).length() / 4.0
			if slope > float(entry.get("max_slope", 0.6)):
				continue
			if entry.has("low") and h > float(entry["low"]):
				continue
			if entry.has("high") and h < float(entry["high"]):
				continue
			count -= 1
			var s := lerpf(size.x, size.y, pow(rng.randf(), 2.2))
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(),
					rng.randf_range(0.0, 0.12)) * basis
			# Sunk a little, so nothing sits on the ground like a dropped toy.
			var at := Vector3(x, h - s * 0.12, z)
			places[rng.randi() % VARIANTS].append(Transform3D(basis.scaled(Vector3.ONE * s), at))
		for v in VARIANTS:
			if places[v].is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh(kind, v, type)
			mm.instance_count = places[v].size()
			for i in places[v].size():
				mm.set_instance_transform(i, places[v][i])
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d" % [kind, v]
			node.multimesh = mm
			if kind in ["boulder", "slab", "spire"]:
				node.material_override = Planet.ground_material(type)
			# Small things fade out first; landmarks stay.
			var fade := {"boulder": 220.0, "slab": 320.0, "crystal": 160.0, "shard": 400.0}
			if fade.has(kind):
				node.visibility_range_end = fade[kind]
				node.visibility_range_end_margin = 30.0
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if kind in ["crystal"]:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(node)


## One variant of a kind, made once and kept.
static func mesh(kind: String, variant: int, type: PlanetType) -> Mesh:
	var key := "%s:%s:%d" % [type.id, kind, variant]
	if _meshes.has(key):
		return _meshes[key]
	var noise := FastNoiseLite.new()
	noise.seed = hash(key)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	var made: Mesh
	match kind:
		"boulder": made = _rock(noise, Vector3(1.0, 0.68, 0.85), 3, 0.32)
		"slab": made = _rock(noise, Vector3(1.0, 0.32, 0.7), 4, 0.18)
		"spire": made = _spire(noise, type.id == "basalt")
		"shard": made = _crystals(noise, _ice_material(), 5, 0.22)
		"crystal": made = _crystals(noise, _glow_material(Color(0.35, 1.0, 0.85)), 7, 0.12)
		"stalk": made = _stalk(noise)
		_: made = _rock(noise, Vector3.ONE, 2, 0.3)
	_meshes[key] = made
	return made


## A boulder: an icosphere pushed out by noise, squashed, cut by a few
## planes into faces as rock breaks, and stood on its flat base.
static func _rock(noise: FastNoiseLite, squash: Vector3, cuts: int, bump: float) -> Mesh:
	var sphere := _icosphere(3)
	var planes: Array[Plane] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	for i in cuts:
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
		planes.append(Plane(n, rng.randf_range(0.28, 0.42)))
	var verts := PackedVector3Array()
	for p: Vector3 in sphere[0]:
		var q := p * (0.5 + bump * noise.get_noise_3dv(p * 1.6) + bump * 0.35 * noise.get_noise_3dv(p * 4.5 + Vector3(7, 7, 7)))
		q *= squash
		for plane in planes:
			var over := plane.distance_to(q)
			if over > 0.0:
				q -= plane.normal * over
		q.y = maxf(q.y, -squash.y * 0.3)
		verts.append(q)
	var low := INF
	for v in verts:
		low = minf(low, v.y)
	for i in verts.size():
		verts[i].y -= low
	return _commit(verts, sphere[1], null, true)


## A spire or butte: rings stacked up a column, each wobbled by noise and
## stepped where layers of rock wore back unevenly; six-sided columns for
## basalt.
static func _spire(noise: FastNoiseLite, columnar: bool) -> Mesh:
	var sides := 6 if columnar else 18
	var rings := 22
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var lean := Vector2(noise.get_noise_1d(3.3), noise.get_noise_1d(9.1)) * 0.25
	for ri in rings + 1:
		var t := float(ri) / rings
		var r := lerpf(0.5, 0.2, t) * (1.0 + 0.6 * (1.0 - smoothstep(0.0, 0.18, t)))
		# Harder layers stand out, softer ones wear in.
		r *= 1.0 + 0.12 * sin(t * 19.0 + noise.get_noise_1d(t * 3.0) * 4.0)
		for si in sides:
			var a := TAU * si / sides
			var wob := 1.0 + (0.0 if columnar else 0.22 * noise.get_noise_2d(cos(a) * 1.4 + t * 2.0, sin(a) * 1.4))
			verts.append(Vector3(cos(a) * r * wob + lean.x * t, t, sin(a) * r * wob + lean.y * t))
	for ri in rings:
		for si in sides:
			var a := ri * sides + si
			var b := ri * sides + (si + 1) % sides
			indices.append_array([a, b, a + sides, b, b + sides, a + sides])
	# A cap.
	var top := verts.size()
	verts.append(Vector3(lean.x, 1.0 + 0.02, lean.y))
	for si in sides:
		indices.append_array([rings * sides + si, top, rings * sides + (si + 1) % sides])
	var tall := 1.0 + noise.get_noise_1d(5.0) * 0.6
	for i in verts.size():
		verts[i].y *= tall * 1.6
	return _commit(verts, indices, null, not columnar)


## A cluster of six-sided crystals with pointed tips, leaning out of one
## root.
static func _crystals(noise: FastNoiseLite, mat: Material, count: int, thick: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for c in count:
		var length := rng.randf_range(0.45, 1.0)
		var r := thick * rng.randf_range(0.6, 1.2) * (1.3 if c == 0 else 1.0)
		var axis := (Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)) if c > 0 else Vector3.UP).normalized()
		var basis := Basis(Quaternion(Vector3.UP, axis))
		var base := verts.size()
		for ring in 2:
			for si in 6:
				var a := TAU * si / 6.0
				verts.append(basis * Vector3(cos(a) * r, ring * length * 0.78, sin(a) * r))
		verts.append(basis * Vector3(0, length, 0))
		for si in 6:
			var a := base + si
			var b := base + (si + 1) % 6
			indices.append_array([a, b, a + 6, b, b + 6, a + 6])
			indices.append_array([a + 6, b + 6, base + 12])
	return _commit(verts, indices, mat, false)


## A fungal giant: a stem bent along a curve, a cap that spreads like an
## umbrella, and gills under it that glow.
static func _stalk(noise: FastNoiseLite) -> Mesh:
	var sides := 12
	var rings := 16
	var lean := Vector2(noise.get_noise_1d(1.7), noise.get_noise_1d(4.2)) * 0.35
	var stem := PackedVector3Array()
	var stem_i := PackedInt32Array()
	var centre := func(t: float) -> Vector3:
		return Vector3(lean.x * t * t, t, lean.y * t * t)
	for ri in rings + 1:
		var t := float(ri) / rings
		var r := lerpf(0.07, 0.035, t) * (1.0 + 0.9 * (1.0 - smoothstep(0.0, 0.12, t)))
		var c: Vector3 = centre.call(t)
		for si in sides:
			var a := TAU * si / sides
			var ridge := 1.0 + 0.08 * sin(a * 5.0 + t * 3.0)
			stem.append(c + Vector3(cos(a), 0, sin(a)) * r * ridge)
	for ri in rings:
		for si in sides:
			var a := ri * sides + si
			var b := ri * sides + (si + 1) % sides
			stem_i.append_array([a, b, a + sides, b, b + sides, a + sides])
	# The cap: a dome over the top, its rim curling down.
	var top: Vector3 = centre.call(1.0)
	var cap_r := 0.32 + noise.get_noise_1d(8.0) * 0.08
	var cap_rings := 8
	var cap_sides := 24
	var cap_base := stem.size()
	for ri in cap_rings + 1:
		var t := float(ri) / cap_rings
		var r := cap_r * sin(t * PI * 0.5)
		var y := 0.09 * cos(t * PI * 0.5) - 0.05 * t * t
		for si in cap_sides:
			var a := TAU * si / cap_sides
			var wob := 1.0 + 0.06 * noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0)
			stem.append(top + Vector3(cos(a) * r * wob, y, sin(a) * r * wob))
	for ri in cap_rings:
		for si in cap_sides:
			var a := cap_base + ri * cap_sides + si
			var b := cap_base + ri * cap_sides + (si + 1) % cap_sides
			stem_i.append_array([a, a + cap_sides, b, b, a + cap_sides, b + cap_sides])
	var mesh := _commit(stem, stem_i, _fungus_material(), true) as ArrayMesh
	# The gills: a glowing disc under the cap's rim.
	var gills := PackedVector3Array()
	var gills_i := PackedInt32Array()
	gills.append(top + Vector3(0, 0.0, 0))
	for si in cap_sides:
		var a := TAU * si / cap_sides
		gills.append(top + Vector3(cos(a) * cap_r * 0.97, -0.045, sin(a) * cap_r * 0.97))
	for si in cap_sides:
		gills_i.append_array([0, 1 + si, 1 + (si + 1) % cap_sides])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in gills:
		st.add_vertex(v)
	for i in gills_i:
		st.add_index(i)
	st.generate_normals()
	st.set_material(_glow_material(Color(0.4, 1.0, 0.75)))
	return st.commit(mesh)


static func _commit(verts: PackedVector3Array, indices: PackedInt32Array, mat: Material, smooth: bool) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0 if smooth else -1)
	if smooth:
		for v in verts:
			st.add_vertex(v)
		for i in indices:
			st.add_index(i)
	else:
		for i in indices:
			st.add_vertex(verts[i])
	st.generate_normals()
	if mat != null:
		st.set_material(mat)
	var arrays := st.commit_to_arrays()
	# Levels of detail, so far copies draw a fraction of the triangles.
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat)
	importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


## Vertices and triangles of a unit icosphere, `level` times subdivided.
static func _icosphere(level: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = []
	for v: Vector3 in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
			[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
			[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in level:
		var mids := {}
		var next := []
		for f: Array in faces:
			var m := []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var k := Vector2i(mini(a, b), maxi(a, b))
				if not mids.has(k):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mids[k] = verts.size() - 1
				m.append(mids[k])
			next.append_array([[f[0], m[0], m[2]], [f[1], m[1], m[0]], [f[2], m[2], m[1]], [m[0], m[1], m[2]]])
		faces = next
	var packed := PackedVector3Array(verts)
	var indices := PackedInt32Array()
	for f: Array in faces:
		# Wound for Godot's front faces (clockwise seen from outside).
		indices.append_array([f[0], f[2], f[1]])
	return [packed, indices]


static func _ice_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.82, 0.95)
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.18, 0.4, 0.6)
	m.emission_energy_multiplier = 0.4
	m.rim_enabled = true
	m.rim = 0.6
	return m


static func _glow_material(color: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	m.roughness = 0.3
	return m


## Stem and cap: dark violet-brown, the cap's top paler with lit pores.
static func _fungus_material() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.28)
	m.roughness = 0.6
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.8
	m.emission_enabled = true
	m.emission = Color(0.1, 0.5, 0.4)
	m.emission_energy_multiplier = 0.25
	m.emission_texture = _pores()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(14, 14, 14)
	return m


static var _pore_tex: NoiseTexture2D

static func _pores() -> Texture2D:
	if _pore_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.06
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		_pore_tex = NoiseTexture2D.new()
		_pore_tex.width = 256
		_pore_tex.height = 256
		_pore_tex.seamless = true
		_pore_tex.invert = true
		_pore_tex.noise = n
		var ramp := Gradient.new()
		ramp.set_color(0, Color.BLACK)
		ramp.set_color(1, Color.WHITE)
		ramp.set_offset(0, 0.75)
		_pore_tex.color_ramp = ramp
	return _pore_tex
