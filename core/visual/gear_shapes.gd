extends RefCounted
## The shapes and finishes worn gear is built from (`helmet_model.gd`,
## `armor_model.gd`): chamfered boxes, shells cut from (super)ellipsoids,
## the materials, and a merge that bakes a finished piece into one mesh
## with a surface per material, so a dressed body costs a few draw calls.
## View only, like everything `Look` builds. Front is -Z.
##
## Load with `const GearShapes := preload("res://core/visual/gear_shapes.gd")`.

## Materials shared by every piece built with the same finish, so many
## bodies in the same gear draw from the same few materials.
static var _mats := {}


## A box `size` with its edges cut at `r` (a chamfer, flat shaded).
static func rbox(size: Vector3, r: float) -> ArrayMesh:
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var u_axis := (axis + 1) % 3
			var v_axis := (axis + 2) % 3
			var us := [-h[u_axis], -h[u_axis] + r, h[u_axis] - r, h[u_axis]]
			var vs := [-h[v_axis], -h[v_axis] + r, h[v_axis] - r, h[v_axis]]
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
					# Pulled onto the cut's plane where two or three faces meet.
					var k := 0
					for c in 3:
						if absf(d[c]) > 0.0001:
							k += 1
					if k > 1:
						d /= float(k)
					row.append(inner + d)
				grid.append(row)
			var out := Vector3.ZERO
			out[axis] = sgn
			for j in 3:
				for i in 3:
					var a: Vector3 = grid[j][i]
					var b: Vector3 = grid[j][i + 1]
					var c2: Vector3 = grid[j + 1][i + 1]
					var d2: Vector3 = grid[j + 1][i]
					var tri := [a, b, c2, a, c2, d2]
					if (b - a).cross(c2 - a).dot(out) > 0.0:
						tri = [a, c2, b, a, d2, c2]
					for p: Vector3 in tri:
						st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()


## A shell cut from the ellipsoid of radii `r`, from polar angle `top(az)`
## to `bot(az)` (0 straight up, PI straight down) across azimuths `from`
## to `to` (0 at -Z, PI/2 at +X), `thick` outward. `push(polar, az)` scales
## the radius there (a brow, a crest, a prow); `power` over 2 squares the
## ellipsoid off (a superellipsoid), and `flat` shades it in facets.
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
	for i in az_steps:
		quad.call([inner[i][pol_steps], inner[i + 1][pol_steps], outer[i + 1][pol_steps], outer[i][pol_steps]])
		if float(top.call(0.0)) > 0.001:
			quad.call([outer[i][0], outer[i + 1][0], inner[i + 1][0], inner[i][0]])
	if not full:
		for j in pol_steps:
			quad.call([outer[0][j], outer[0][j + 1], inner[0][j + 1], inner[0][j]])
			quad.call([inner[az_steps][j], inner[az_steps][j + 1], outer[az_steps][j + 1], outer[az_steps][j]])
	if flat:
		st.index()
	st.generate_normals()
	return st.commit()


## A curved band round an upright elliptical cylinder of radii `rx` and
## `rz`, from angle `from` to `to` (0 at -Z) and height `low` to `high`,
## `thick` thick and thinning to a bevel at its edges. `bulge` swells its
## middle, `flare` widens its top (negative narrows it).
static func band(rx: float, rz: float, from: float, to: float, low: float, high: float, thick: float,
		bulge := 0.0, flare := 0.0) -> ArrayMesh:
	var cols := maxi(4, ceili((to - from) / 0.12))
	var rows := 5
	var bevel := minf(0.022, 0.3 * minf(high - low, (to - from) * rx))
	var outer := []
	var inner := []
	var normals := []
	for j in rows + 1:
		var v := float(j) / rows
		var row_o := []
		var row_i := []
		var row_n := []
		for i in cols + 1:
			var u := float(i) / cols
			var a := lerpf(from, to, u)
			var grow := 1.0 + flare * (v - 0.5) + bulge * sin(PI * v) * sin(PI * u) / maxf(rx, 0.01)
			var at := Vector3(rx * grow * sin(a), lerpf(low, high, v), -rz * grow * cos(a))
			var n := Vector3(sin(a) / rx, 0.0, -cos(a) / rz).normalized()
			var edge := minf(minf(u, 1.0 - u) * (to - from) * rx, minf(v, 1.0 - v) * (high - low))
			var t := thick * lerpf(0.3, 1.0, smoothstep(0.0, bevel, edge))
			row_i.append(at)
			row_o.append(at + n * t)
			row_n.append(n)
		outer.append(row_o)
		inner.append(row_i)
		normals.append(row_n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(q: Array, n: Array, sgn: float) -> void:
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal((n[k] as Vector3) * sgn)
			st.add_vertex(q[k])
	for j in rows:
		for i in cols:
			var n := [normals[j][i], normals[j][i + 1], normals[j + 1][i + 1], normals[j + 1][i]]
			quad.call([outer[j][i], outer[j][i + 1], outer[j + 1][i + 1], outer[j + 1][i]], n, 1.0)
			quad.call([inner[j][i], inner[j][i + 1], inner[j + 1][i + 1], inner[j + 1][i]], n, -1.0)
	for i in cols:
		for j: int in [0, rows]:
			var d: Vector3 = Vector3.DOWN if j == 0 else Vector3.UP
			quad.call([inner[j][i], inner[j][i + 1], outer[j][i + 1], outer[j][i]], [d, d, d, d], 1.0)
	for j in rows:
		for i: int in [0, cols]:
			var side: Vector3 = (inner[j][mini(i + 1, cols)] - inner[j][maxi(i - 1, 0)]).normalized() \
					* (1.0 if i == cols else -1.0)
			quad.call([inner[j][i], inner[j + 1][i], outer[j + 1][i], outer[j][i]], [side, side, side, side], 1.0)
	return st.commit()


## A plate laid over any surface: `point(u, v)` (u and v from 0 to 1) is
## where its inner face lies, with u running round to the right as seen
## from outside and v running up, so the plate stands out toward
## dv x du. `thick` thick, thinning to a bevel `bevel` metres in from its
## edges, `cols` by `rows` faces. Fitted armor is laid this way over the
## body's own shape (`body_fit.gd`).
static func sheet(point: Callable, thick: float, cols := 16, rows := 8, bevel := 0.018) -> ArrayMesh:
	var inner := []
	for j in rows + 1:
		var row := []
		for i in cols + 1:
			row.append(point.call(float(i) / cols, float(j) / rows))
		inner.append(row)
	# Rough lengths across and up, for the bevel.
	var lu := 0.0
	var lv := 0.0
	for i in cols:
		lu += (inner[rows / 2][i + 1] - inner[rows / 2][i]).length()
	for j in rows:
		lv += (inner[j + 1][cols / 2] - inner[j][cols / 2]).length()
	var outer := []
	var normals := []
	for j in rows + 1:
		var row_o := []
		var row_n := []
		for i in cols + 1:
			var du: Vector3 = inner[j][mini(i + 1, cols)] - inner[j][maxi(i - 1, 0)]
			var dv: Vector3 = inner[mini(j + 1, rows)][i] - inner[maxi(j - 1, 0)][i]
			var n := dv.cross(du)
			n = n.normalized() if n.length() > 0.0000001 else Vector3.FORWARD
			var u := float(i) / cols
			var v := float(j) / rows
			var edge := minf(minf(u, 1.0 - u) * lu, minf(v, 1.0 - v) * lv)
			var t := thick * lerpf(0.35, 1.0, smoothstep(0.0, bevel, edge))
			row_o.append(inner[j][i] + n * t)
			row_n.append(n)
		outer.append(row_o)
		normals.append(row_n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(q: Array, n: Array, sgn: float) -> void:
		var order: Array = [0, 1, 2, 0, 2, 3] if sgn > 0.0 else [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_normal((n[k] as Vector3) * sgn)
			st.add_vertex(q[k])
	for j in rows:
		for i in cols:
			var n := [normals[j][i], normals[j][i + 1], normals[j + 1][i + 1], normals[j + 1][i]]
			quad.call([outer[j][i], outer[j][i + 1], outer[j + 1][i + 1], outer[j + 1][i]], n, 1.0)
			quad.call([inner[j][i], inner[j][i + 1], inner[j + 1][i + 1], inner[j + 1][i]], n, -1.0)
	# The rims: square to the face along each edge.
	for i in cols:
		for j: int in [0, rows]:
			var d: Vector3 = (inner[j][i + 1] - inner[j][i]).cross(normals[j][i]).normalized() * (1.0 if j == 0 else -1.0)
			quad.call([inner[j][i], inner[j][i + 1], outer[j][i + 1], outer[j][i]], [d, d, d, d], 1.0)
	for j in rows:
		for i: int in [0, cols]:
			var d: Vector3 = (inner[j + 1][i] - inner[j][i]).cross(normals[j][i]).normalized() * (-1.0 if i == 0 else 1.0)
			quad.call([inner[j][i], inner[j + 1][i], outer[j + 1][i], outer[j][i]], [d, d, d, d], 1.0)
	return st.commit()


## The polar angle at height `y` (a share of the radius, 1 the top).
static func pol(y: float) -> float:
	return acos(clampf(y, -1.0, 1.0))


static func const_of(v: float) -> Callable:
	return func(_a: float) -> float: return v


## ---------------------------------------------------------------- materials

## A matte or metal finish, shared by everything asking for the same one.
static func mat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "m%s/%.2f/%.2f" % [color.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## A lit part: an accent, a seam, a gauge.
static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "g%s/%.2f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.3)
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## Smoked visor glass, tinted a touch toward the display's colour, glossy
## so the sky and the room show in it.
static func glass(color: Color) -> StandardMaterial3D:
	return mat(Color(0.02, 0.025, 0.03).lerp(color, 0.07), 0.05, 0.85)


## A faint highlight across glass.
static func glint() -> StandardMaterial3D:
	if _mats.has("glint"):
		return _mats["glint"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.88, 1.0, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.8, 0.88, 1.0)
	m.emission_energy_multiplier = 0.18
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats["glint"] = m
	return m


## ---------------------------------------------------------------- building

## Adds `mesh` in `material` to `root` under the name `part`. Names say what
## a piece is (tests look for them); `merge` keeps them in the "parts" meta.
static func add(root: Node3D, part: String, mesh: Mesh, material: Material, at := Vector3.ZERO,
		basis := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part
	mi.set_meta("part", part)
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = Transform3D(basis, at)
	root.add_child(mi)
	return mi


static func box(root: Node3D, part: String, size: Vector3, material: Material, at: Vector3, r := 0.004,
		basis := Basis.IDENTITY) -> MeshInstance3D:
	return add(root, part, rbox(size, r), material, at, basis)


static func cyl(root: Node3D, part: String, radius: float, height: float, material: Material, at: Vector3,
		basis := Basis.IDENTITY, sides := 12) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return add(root, part, m, material, at, basis)


## Leaves every part a node of its own instead of merging (a tool that
## names the parts, `tools/armor_fit`). Never set in the game.
static var keep_parts := false


## Bakes every mesh under `root` into one mesh with a surface per material,
## named "Gear", and lists the parts it was made of in the "parts" meta.
## Glass casts no shadow, so it goes in a mesh of its own ("Glass").
static func merge(root: Node3D) -> Node3D:
	if keep_parts:
		return root
	var groups := {}
	var order: Array[Material] = []
	var names := PackedStringArray()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var part: String = mi.get_meta("part", str(mi.name))
		if not part in names:
			names.append(part)
		var xform := root.global_transform.affine_inverse() * mi.global_transform if root.is_inside_tree() \
				else _to_root(root, mi)
		var material: Material = mi.material_override
		if not groups.has(material):
			groups[material] = []
			order.append(material)
		(groups[material] as Array).append([mi.mesh, xform])
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	var solid := ArrayMesh.new()
	var clear := ArrayMesh.new()
	for material in order:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for item: Array in groups[material]:
			var mesh: Mesh = item[0]
			for s in mesh.get_surface_count():
				# Every piece goes in unindexed: appended after an indexed
				# one, an unindexed piece would lose its triangles.
				var one := SurfaceTool.new()
				one.create_from(mesh, s)
				one.deindex()
				st.append_from(one.commit(), 0, item[1])
		st.index()
		st.set_material(material)
		var glassy := material is StandardMaterial3D and (material as StandardMaterial3D).metallic > 0.8 \
				and (material as StandardMaterial3D).roughness < 0.1 \
				or material is StandardMaterial3D and (material as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		st.commit(clear if glassy else solid)
	for pair: Array in [["Gear", solid], ["Glass", clear]]:
		var mesh: ArrayMesh = pair[1]
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = pair[0]
		mi.mesh = mesh
		if pair[0] == "Glass":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.set_meta("parts", names)
	return root


## Where `node` sits in `root`'s space, out of the tree.
static func _to_root(root: Node3D, node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


## True if a merged piece was built with a part named `part`.
static func has_part(root: Node, part: String) -> bool:
	return root.has_meta("parts") and part in (root.get_meta("parts") as PackedStringArray)


## Built pieces by key: their meshes and parts, so the same piece on many
## bodies shares one mesh (`cached`).
static var _built := {}


## The piece `make` builds (a merged root), built once per `key` and after
## that copied, sharing its meshes and materials.
static func cached(key: String, make: Callable) -> Node3D:
	if not _built.has(key):
		var made: Node3D = make.call()
		var meshes := []
		for child in made.get_children():
			if child is MeshInstance3D:
				meshes.append([child.name, (child as MeshInstance3D).mesh, (child as MeshInstance3D).cast_shadow])
		_built[key] = {"name": made.name, "scale": made.scale, "meshes": meshes, "parts": made.get_meta("parts", PackedStringArray())}
		made.free()
	var entry: Dictionary = _built[key]
	var root := Node3D.new()
	root.name = entry["name"]
	root.scale = entry["scale"]
	for m: Array in entry["meshes"]:
		var mi := MeshInstance3D.new()
		mi.name = m[0]
		mi.mesh = m[1]
		mi.cast_shadow = m[2]
		root.add_child(mi)
	root.set_meta("parts", entry["parts"])
	return root
