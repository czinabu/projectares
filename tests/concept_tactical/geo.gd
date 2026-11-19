extends RefCounted
## Concept geometry: chamfered boxes, shells cut from ellipsoids, and the
## materials the tactical kit is made of. Front is -Z.


## A box `size` with its edges cut at `r` (a chamfer, flat shaded).
static func rbox(size: Vector3, r: float) -> ArrayMesh:
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var cuts := func(e: float) -> Array: return [-e, -e + r, e - r, e]
	# Each face: a 3x3 grid of points remapped onto the rounded box.
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var u_axis := (axis + 1) % 3
			var v_axis := (axis + 2) % 3
			var us: Array = cuts.call(h[u_axis])
			var vs: Array = cuts.call(h[v_axis])
			var grid := []
			for j in 4:
				var row := []
				for i in 4:
					var p := Vector3.ZERO
					p[axis] = h[axis] * sgn
					p[u_axis] = us[i]
					p[v_axis] = vs[j]
					var inner := Vector3(clampf(p.x, -h.x + r, h.x - r), clampf(p.y, -h.y + r, h.y - r),
							clampf(p.z, -h.z + r, h.z - r))
					var d := p - inner
					# A chamfer: corners pulled onto the plane through the cut.
					var n := d.abs()
					var k := 0
					for c in 3:
						if n[c] > 0.0001:
							k += 1
					if k > 1:
						d = d / float(k) * 1.0
					row.append(inner + d)
				grid.append(row)
			for j in 3:
				for i in 3:
					var a: Vector3 = grid[j][i]
					var b: Vector3 = grid[j][i + 1]
					var c: Vector3 = grid[j + 1][i + 1]
					var d2: Vector3 = grid[j + 1][i]
					var out := Vector3.ZERO
					out[axis] = sgn
					var tri := [a, b, c, a, c, d2]
					var nrm := (b - a).cross(c - a)
					if nrm.dot(out) > 0.0:
						tri = [a, c, b, a, d2, c]
					for p: Vector3 in tri:
						st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()


## A shell cut from the ellipsoid of radii `r`: from polar angle `top(az)`
## to `bot(az)` (0 straight up, PI straight down) across azimuths `from` to
## `to` (0 at -Z, PI/2 at +X), `thick` outward. `push(polar, az)` scales the
## radius there (a brow, a crest, a flat face). `flat` shades it in facets.
static func cap(r: Vector3, top: Callable, bot: Callable, from: float, to: float, thick: float,
		az_steps := 24, pol_steps := 10, flat := false, push := Callable(), power := 2.0) -> ArrayMesh:
	var full := absf(to - from - TAU) < 0.001
	var outer := []
	var inner := []
	for i in az_steps + 1:
		var a := lerpf(from, to, float(i) / az_steps)
		var p0: float = top.call(a)
		var p1: float = bot.call(a)
		var col_o := []
		var col_i := []
		for j in pol_steps + 1:
			var p := lerpf(p0, p1, float(j) / pol_steps)
			var dir := Vector3(sin(p) * sin(a), cos(p), -sin(p) * cos(a))
			var k := 1.0 if not push.is_valid() else float(push.call(p, a))
			if power != 2.0:
				# A superellipsoid: squarer the higher `power` is.
				k /= pow(pow(absf(dir.x), power) + pow(absf(dir.y), power) + pow(absf(dir.z), power), 1.0 / power)
			var at := dir * r * k
			var n := (dir / (r * r)).normalized()
			col_i.append(at)
			col_o.append(at + n * thick)
		outer.append(col_o)
		inner.append(col_i)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1 if flat else 0)
	var quad := func(q: Array) -> void:
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[k])
	for i in az_steps:
		for j in pol_steps:
			quad.call([outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]])
			quad.call([inner[i][j], inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j]])
	# The rims along the top and bottom cuts.
	for i in az_steps:
		quad.call([inner[i][pol_steps], inner[i + 1][pol_steps], outer[i + 1][pol_steps], outer[i][pol_steps]])
		if top.call(0.0) > 0.001:
			quad.call([outer[i][0], outer[i + 1][0], inner[i + 1][0], inner[i][0]])
	if not full:
		for j in pol_steps:
			quad.call([outer[0][j], outer[0][j + 1], inner[0][j + 1], inner[0][j]])
			quad.call([inner[az_steps][j], inner[az_steps][j + 1], outer[az_steps][j + 1], outer[az_steps][j]])
	if flat:
		st.index()
	st.generate_normals()
	return st.commit()


static func const_of(v: float) -> Callable:
	return func(_a: float) -> float: return v


## A material.
static func mat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := mat(color.darkened(0.3), 0.3, 0.0)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func glass(color: Color) -> StandardMaterial3D:
	var m := mat(Color(0.02, 0.025, 0.03).lerp(color, 0.06), 0.05, 0.85)
	return m


static func add(root: Node3D, mesh: Mesh, material: Material, at := Vector3.ZERO, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = Transform3D(basis, at)
	root.add_child(mi)
	return mi


static func box(root: Node3D, size: Vector3, material: Material, at: Vector3, r := 0.004,
		basis := Basis.IDENTITY) -> MeshInstance3D:
	return add(root, rbox(size, r), material, at, basis)


static func cyl(root: Node3D, radius: float, height: float, material: Material, at: Vector3,
		basis := Basis.IDENTITY, sides := 12) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return add(root, m, material, at, basis)
