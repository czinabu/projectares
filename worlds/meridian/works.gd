extends RefCounted
## Meridian's surroundings, decoration only: the dead launch works the
## circuits were built in, so no view from the road ends on bare salt.
## A belt of districts round both tracks (tank farm, hangar row, container
## port, cooling plant, launch field), each with one landmark to steer by
## and lower buildings toward the road; service roads out into it; fans'
## car parks and camps just outside the tracks; the infield festival; and
## catch fences, hoardings and tyre walls along both tracks.
##
## Nothing here collides or is read by the race, and the map builds it only
## where `Look` is on, with its own RNG so the layout never shifts. Shapes
## are merged into one mesh per material per block (`BIG_CHUNK` for
## buildings, `FINE_CHUNK` for the small things, which stop being drawn past
## `FINE_RANGE`), so blocks out of view are culled and the whole belt costs
## a few dozen draw calls; the people are one `Crowd`.

const CYAN := Color(0.3, 0.85, 1.0)
const AMBER := Color(1.0, 0.6, 0.2)
const MAGENTA := Color(1.0, 0.3, 0.7)
const RED := Color(1.0, 0.22, 0.12)
const WARM := Color(1.0, 0.85, 0.6)
## The middle of both circuits.
const CENTRE := Vector3(-40, 0, 100)
## The belt runs from `INNER` out, thinning from `FADE_FROM` to `OUTER`.
const INNER := 230.0
const FADE_FROM := 540.0
const OUTER := 860.0
const BIG_CHUNK := 600.0
const FINE_CHUNK := 300.0
const FINE_RANGE := 900.0
## The districts round the belt, clockwise from -x; each takes an equal
## slice, its edges wavering.
const DISTRICTS := ["tanks", "hangars", "port", "cooling", "launch", "hangars", "tanks", "port"]

var root: Node3D
var rng := RandomNumberGenerator.new()
var crowd: Crowd
var steel: Material
var dark: Material
var rust: Material
var concrete: Material
var white: Material
var asphalt: Material
## Paints for cars, containers and tents, each `[colour]` (see `_paint`).
var paints: Array = []
## Circles nothing new may stand in: [centre, radius], the stands, pits and
## skyline already there; a third number keeps trackside fences that far off.
var keep_out: Array = []
var _noise := FastNoiseLite.new()
## Track points by 40 m cell, for `track_dist`.
var _cells := {}
var _mats: Array[Material] = []
## "tier|material|cx|cz" -> SurfaceTool.
var _batches := {}
## The one lit material, coloured by its vertices.
var _lit: StandardMaterial3D
## The one painted material (cars, containers, tents, the crane), coloured
## by its vertices; a paint is passed as `[colour]`.
var _paint: StandardMaterial3D


func _init(p_parent: Node3D, p_seed: int, p_keep_out: Array) -> void:
	root = Node3D.new()
	root.name = "Works"
	p_parent.add_child(root)
	rng.seed = p_seed
	keep_out = p_keep_out
	_noise.seed = p_seed
	_noise.frequency = 0.004
	crowd = Crowd.new()
	crowd.name = "WorksCrowd"
	_lit = StandardMaterial3D.new()
	_lit.vertex_color_use_as_albedo = true
	_lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lit.vertex_color_is_srgb = true
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.vertex_color_is_srgb = true
	_paint.metallic = 0.4
	_paint.roughness = 0.6
	steel = Look.surface("metal", {"metal": 0.4, "tint": Color(0.22, 0.23, 0.27), "grime": 0.25, "scale": 0.3})
	dark = Look.surface("metal", {"metal": 0.3, "tint": Color(0.1, 0.1, 0.13), "grime": 0.15, "scale": 0.3})
	rust = Look.surface("metal", {"metal": 0.2, "tint": Color(0.42, 0.26, 0.18), "grime": 0.7, "scale": 0.3})
	concrete = Look.surface("concrete", {"tint": Color(0.62, 0.58, 0.54), "grime": 0.5})
	white = Look.surface("metal", {"metal": 0.2, "tint": Color(0.82, 0.82, 0.8), "grime": 0.3, "scale": 0.3})
	asphalt = Look.surface("concrete", {"tint": Color(0.16, 0.15, 0.16), "grime": 0.3})
	for tint: Color in [Color(0.42, 0.14, 0.1), Color(0.12, 0.24, 0.38), Color(0.6, 0.45, 0.16), Color(0.38, 0.4, 0.4),
			Color(0.1, 0.36, 0.42), Color(0.5, 0.18, 0.32)]:
		paints.append([tint])


func build(tracks: Array) -> void:
	for track: RaceTrack in tracks:
		for p in track.points:
			# A packed array is a copy once read out of the dictionary, so
			# each cell's is taken out, added to and put back.
			var c := _cell(p)
			var cell: PackedVector3Array = _cells.get(c, PackedVector3Array())
			cell.append(Vector3(p.x, 0, p.z))
			_cells[c] = cell
	_landmarks()
	_belt()
	_roads()
	_festival()
	_car_parks()
	for track: RaceTrack in tracks:
		_trackside(track)
	_finish()


# --- Placing -----------------------------------------------------------------------

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / 40.0), floori(p.z / 40.0))


## How far `p` is from the nearest road of either track, on the ground.
func track_dist(p: Vector3) -> float:
	var c := _cell(p)
	var best := 1e9
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k := c + Vector2i(dx, dz)
			if _cells.has(k):
				for q: Vector3 in _cells[k]:
					best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best


## True where something `margin` across may stand at `p`: that far from
## the roads and clear of what already stands.
func clear(p: Vector3, margin: float) -> bool:
	if track_dist(p) < margin:
		return false
	for k: Array in keep_out:
		var c: Vector3 = k[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(k[1]) + margin * 0.4:
			return false
	return true


## `clear` over a square `half` each way round `p`: its middle and corners.
func clear_area(p: Vector3, half: float, margin: float) -> bool:
	if not clear(p, margin + half):
		return false
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		if not clear(p + Vector3(c.x * half, 0, c.y * half), margin):
			return false
	return true


func _district_at(p: Vector3) -> String:
	var off := p - CENTRE
	var a := atan2(off.z, off.x)
	var slice := (a + PI) / TAU * DISTRICTS.size() + _noise.get_noise_1d(off.length()) * 0.6
	return DISTRICTS[posmod(int(floor(slice)), DISTRICTS.size())]


## The middle of district `k`'s slice at radius `r`.
func _district_spot(k: int, r: float) -> Vector3:
	var a := -PI + TAU * (k + 0.5) / DISTRICTS.size()
	return CENTRE + Vector3(cos(a), 0, sin(a)) * r


# --- Shapes ------------------------------------------------------------------------

## A lit colour: every lit shape is drawn in one unshaded material that
## takes its colour from the shape's vertices (`_lit`), so all the lights
## in a block are one draw. `energy` is kept for reading; unshaded light is
## its colour alone.
func glow(color: Color, _energy := 1.0) -> Color:
	return color


func _add(mesh: PrimitiveMesh, xf: Transform3D, mat: Variant, fine: bool) -> void:
	var size := FINE_CHUNK if fine else BIG_CHUNK
	var source: Mesh = mesh
	if mat is Color or mat is Array:
		var arrays := mesh.get_mesh_arrays()
		var colors := PackedColorArray()
		colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		colors.fill(mat if mat is Color else mat[0])
		arrays[Mesh.ARRAY_COLOR] = colors
		var painted := ArrayMesh.new()
		painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		source = painted
		mat = _lit if mat is Color else _paint
	var m := _mats.find(mat)
	if m < 0:
		m = _mats.size()
		_mats.append(mat)
	var key := "%d|%d|%d|%d" % [1 if fine else 0, m, floori(xf.origin.x / size), floori(xf.origin.z / size)]
	var st: SurfaceTool = _batches.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	st.append_from(source, 0, xf)


func box(size: Vector3, xf: Transform3D, mat: Variant, fine := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(mesh, xf, mat, fine)


func cyl(r_top: float, r_bottom: float, h: float, xf: Transform3D, mat: Variant, sides := 16, fine := false) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = h
	mesh.radial_segments = sides
	mesh.rings = 1
	_add(mesh, xf, mat, fine)


func ball(r: float, xf: Transform3D, mat: Variant) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	_add(mesh, xf, mat, false)


func at(p: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)


func _finish() -> void:
	for key: String in _batches:
		var parts := key.split("|")
		var mat := _mats[int(parts[1])]
		var node := MeshInstance3D.new()
		node.mesh = (_batches[key] as SurfaceTool).commit()
		node.mesh.surface_set_material(0, mat)
		if mat == _lit:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if parts[0] == "1":
			node.visibility_range_end = FINE_RANGE
			node.visibility_range_end_margin = FINE_RANGE * 0.15
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
	_batches.clear()
	if crowd.count() > 0:
		root.add_child(crowd)
		crowd.build()


func _person(p: Vector3, yaw: float) -> void:
	var pick := rng.randf()
	var c: Color
	if pick < 0.14:
		c = CYAN.darkened(rng.randf_range(0.35, 0.65))
	elif pick < 0.26:
		c = AMBER.darkened(rng.randf_range(0.35, 0.65))
	elif pick < 0.3:
		c = MAGENTA.darkened(0.55)
	else:
		c = Color.from_hsv(rng.randf_range(0.5, 0.75), rng.randf_range(0.05, 0.3), rng.randf_range(0.06, 0.3))
	crowd.add(p, yaw, c, rng.randf(), rng.randf() < 0.08, rng.randf(), rng.randf_range(0.9, 1.1))


## `count` people milling round `p`, out to `radius`.
func _milling(p: Vector3, radius: float, count: int) -> void:
	for k in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		_person(p + Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU)


func _ad_color() -> Color:
	return [CYAN, MAGENTA, AMBER, CYAN, MAGENTA][rng.randi() % 5]


# --- Landmarks -----------------------------------------------------------------------

## One set piece per district, big enough to steer by from anywhere on the
## track, standing at the middle of its slice where there is room.
func _landmarks() -> void:
	for k in DISTRICTS.size():
		var spot := Vector3.INF
		for r: float in [420.0, 470.0, 380.0, 520.0, 560.0]:
			for nudge: float in [0.0, 0.12, -0.12, 0.24, -0.24]:
				var a := -PI + TAU * (k + 0.5 + nudge) / DISTRICTS.size()
				var p := CENTRE + Vector3(cos(a), 0, sin(a)) * r
				if clear_area(p, 80.0, 50.0):
					spot = p
					break
			if spot != Vector3.INF:
				break
		if spot == Vector3.INF:
			continue
		var off := spot - CENTRE
		var face := atan2(-off.x, -off.z)
		match String(DISTRICTS[k]):
			"tanks":
				_spheres(spot, face)
			"hangars":
				if k == 1:
					_assembly_hall(spot, face)
				else:
					_hangar_row(spot, face)
			"port":
				_portal_crane(spot, face)
			"cooling":
				_twin_coolers(spot)
			"launch":
				_rocket_pad(spot, face)
		keep_out.append([spot, 70.0])


## Fuel spheres on legs, ringed with light, a gantry walk between them.
func _spheres(p: Vector3, yaw: float) -> void:
	var xf := at(p, yaw)
	for k in 3:
		var q := Vector3((k - 1) * 34.0, 0, absf(k - 1) * 14.0)
		var r := 13.0 + (2.0 if k == 1 else 0.0)
		ball(r, xf * at(q + Vector3(0, r + 8, 0)), white)
		cyl(r + 0.1, r + 0.1, 0.8, xf * at(q + Vector3(0, r + 8, 0)), glow(CYAN if k != 1 else MAGENTA, 3.0), 24)
		for s in 6:
			var a := TAU * s / 6.0
			box(Vector3(1.0, r + 8, 1.0), xf * at(q + Vector3(cos(a) * r * 0.8, (r + 8) * 0.5, sin(a) * r * 0.8)), steel)
		box(Vector3(1.2, 1.2, 1.2), xf * at(q + Vector3(0, r * 2 + 8.6, 0)), glow(RED, 6.0))
	box(Vector3(70, 1.2, 2.5), xf * at(Vector3(0, 22, 6)), dark)
	box(Vector3(70, 0.2, 0.2), xf * at(Vector3(0, 22.7, 4.8)), glow(AMBER, 2.5))


## A vehicle assembly hall, the tallest thing on the flats: a slab with a
## lit slot of a door up its face and a screen on its side.
func _assembly_hall(p: Vector3, yaw: float) -> void:
	var xf := at(p, yaw)
	var w := 70.0
	var l := 90.0
	var h := 120.0
	box(Vector3(w, h, l), xf * at(Vector3(0, h * 0.5, 0)), white)
	box(Vector3(w * 0.5, h * 0.28, l * 0.8), xf * at(Vector3(w * 0.5 + w * 0.25, h * 0.14, 0)), steel)
	# The door: a tall dark slot, lit along its edges.
	box(Vector3(22, h * 0.85, 1.0), xf * at(Vector3(0, h * 0.425, -l * 0.5 - 0.4)), dark)
	for s: float in [-1.0, 1.0]:
		box(Vector3(0.6, h * 0.85, 0.6), xf * at(Vector3(s * 11.3, h * 0.425, -l * 0.5 - 1.0)), glow(CYAN, 3.0))
	box(Vector3(23, 0.6, 0.6), xf * at(Vector3(0, h * 0.85, -l * 0.5 - 1.0)), glow(CYAN, 3.0))
	# Floors of lit windows down the far bays.
	for f in range(6, int(h / 6.0)):
		if rng.randf() < 0.7:
			for s: float in [-1.0, 1.0]:
				box(Vector3(rng.randf_range(8, 18), 0.6, 0.2), xf * at(Vector3(s * 24, f * 6.0, -l * 0.5 - 0.15)), glow(WARM, 1.8))
	# A screen on the side and a crown of red lamps.
	box(Vector3(0.6, 34, 56), xf * at(Vector3(-w * 0.5 - 0.4, h * 0.62, 0)), glow(MAGENTA, 1.6))
	box(Vector3(0.8, 36, 58), xf * at(Vector3(-w * 0.5 - 0.1, h * 0.62, 0)), dark)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		box(Vector3(2, 2, 2), xf * at(Vector3(c.x * w * 0.48, h + 1, c.y * l * 0.48)), glow(RED, 6.0))
	box(Vector3(w + 0.4, 1.0, 0.4), xf * at(Vector3(0, h - 1.0, -l * 0.5 - 0.1)), glow(CYAN, 3.0))


## Three big hangars side by side, doors lit.
func _hangar_row(p: Vector3, yaw: float) -> void:
	var xf := at(p, yaw)
	for k in 3:
		_hangar(xf * Vector3((k - 1) * 58.0, 0, 0), yaw, 1.8, true)


## A portal crane straddling a stack yard, its boom out over the salt.
func _portal_crane(p: Vector3, yaw: float) -> void:
	var xf := at(p, yaw)
	_containers(xf * Vector3(-18, 0, 0), yaw, 5)
	_containers(xf * Vector3(30, 0, 0), yaw, 5)
	var h := 62.0
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		box(Vector3(2.4, h, 2.4), xf * at(Vector3(s.x * 46, h * 0.5, s.y * 14)), _crane_paint())
	box(Vector3(96, 4, 32), xf * at(Vector3(0, h, 0)), _crane_paint())
	box(Vector3(150, 3, 4), xf * at(Vector3(-20, h + 6, 0)), _crane_paint())
	box(Vector3(8, 18, 8), xf * at(Vector3(36, h + 11, 0)), dark)
	box(Vector3(6, 4, 5), xf * at(Vector3(-50, h + 2, 0)), dark)
	box(Vector3(0.4, 30, 0.4), xf * at(Vector3(-50, h - 15, 0)), dark)
	box(Vector3(150, 0.3, 0.3), xf * at(Vector3(-20, h + 7.7, -2.2)), glow(AMBER, 3.0))
	box(Vector3(1.6, 1.6, 1.6), xf * at(Vector3(-95, h + 7, 0)), glow(RED, 6.0))
	box(Vector3(1.6, 1.6, 1.6), xf * at(Vector3(36, h + 21, 0)), glow(RED, 6.0))


func _crane_paint() -> Array:
	return [Color(0.62, 0.4, 0.1)]


## Two great cooling towers with lit rims, steam-stained.
func _twin_coolers(p: Vector3) -> void:
	for k in 2:
		var q := p + Vector3((k - 0.5) * 110.0, 0, (k - 0.5) * 30.0)
		_cooler(q, 2.0 - k * 0.2)


## A launch pad with a rocket still standing on it in its service tower:
## the one thing on the flats that ever flew.
func _rocket_pad(p: Vector3, yaw: float) -> void:
	var xf := at(p, yaw)
	box(Vector3(60, 8, 60), xf * at(Vector3(0, 4, 0)), concrete)
	box(Vector3(18, 8.2, 18), xf * at(Vector3(0, 4.1, 0)), dark)
	box(Vector3(60.4, 0.4, 0.4), xf * at(Vector3(0, 8.1, -30.1)), glow(AMBER, 2.5))
	# The rocket: a white stack, a dark interstage band and a nose cone.
	var r := 6.0
	cyl(r, r, 70, xf * at(Vector3(0, 8 + 35, 0)), white, 24)
	cyl(r + 0.05, r + 0.05, 4, xf * at(Vector3(0, 8 + 52, 0)), dark, 24)
	cyl(r * 0.85, r, 26, xf * at(Vector3(0, 8 + 83, 0)), white, 24)
	cyl(0.3, r * 0.85, 16, xf * at(Vector3(0, 8 + 104, 0)), white, 24)
	for s in 4:
		var a := TAU * s / 4.0 + PI / 4.0
		box(Vector3(0.6, 14, 7), xf * Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * r, 15, -sin(a) * r)), dark)
	for b: float in [-1.0, 1.0]:
		cyl(2.6, 2.6, 46, xf * at(Vector3(b * (r + 2.8), 8 + 23, 0)), white, 16)
		cyl(0.2, 2.6, 7, xf * at(Vector3(b * (r + 2.8), 8 + 49.5, 0)), white, 16)
	cyl(r + 0.1, r + 0.1, 1.0, xf * at(Vector3(0, 8 + 30, 0)), glow(CYAN, 3.0), 24)
	# The service tower beside it, arms reaching across.
	var tx := Vector3(0, 0, r + 14)
	for c: Vector2 in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]:
		box(Vector3(1.2, 120, 1.2), xf * at(tx + Vector3(c.x, 68, c.y)), rust)
	var y := 14.0
	while y < 128.0:
		box(Vector3(9, 0.8, 9), xf * at(tx + Vector3(0, y, 0)), rust)
		y += 12.0
	for arm_y: float in [40.0, 70.0, 98.0]:
		box(Vector3(3, 2, 14), xf * at(tx + Vector3(0, arm_y, -8)), rust)
		box(Vector3(3.2, 0.3, 14), xf * at(tx + Vector3(0, arm_y + 1.2, -8)), glow(AMBER, 2.0))
	box(Vector3(1.6, 1.6, 1.6), xf * at(tx + Vector3(0, 129, 0)), glow(RED, 6.0))


# --- The belt ------------------------------------------------------------------------

## The works on a jittered grid all round, square to the district's radial
## road, lower toward the track and taller out toward the dunes, with
## gaps where the noise opens them.
func _belt() -> void:
	var step := 56.0
	var x := CENTRE.x - OUTER
	while x <= CENTRE.x + OUTER:
		var z := CENTRE.z - OUTER
		while z <= CENTRE.z + OUTER:
			var p := Vector3(x + rng.randf_range(-12, 12), 0, z + rng.randf_range(-12, 12))
			var off := p - CENTRE
			var r := Vector2(off.x, off.z).length()
			var dense := (1.0 - smoothstep(FADE_FROM, OUTER, r)) * smoothstep(-0.45, 0.05, _noise.get_noise_2d(p.x, p.z))
			var roll := rng.randf()
			if r > INNER and roll < dense and clear_area(p, 30.0, 40.0):
				var yaw := snappedf(atan2(off.x, off.z), PI / 4.0)
				var tall := lerpf(0.55, 1.35, smoothstep(INNER, FADE_FROM + 60.0, r))
				_district(_district_at(p), p, yaw, tall)
			z += step
		x += step


func _district(theme: String, p: Vector3, yaw: float, tall: float) -> void:
	var pick := rng.randf()
	match theme:
		"tanks":
			if pick < 0.7:
				_tanks(p, yaw, tall)
			else:
				_lattice(p, yaw, tall)
		"hangars":
			if pick < 0.55:
				_hangar(p, yaw, tall, false)
			elif pick < 0.85:
				_block(p, yaw, tall)
			else:
				_radiators(p, yaw)
		"port":
			if pick < 0.75:
				_containers(p, yaw, 4)
			else:
				_block(p, yaw, tall)
		"cooling":
			if pick < 0.3:
				_cooler(p, tall)
			elif pick < 0.75:
				_radiators(p, yaw)
			else:
				_tanks(p, yaw, tall)
		_:
			if pick < 0.5:
				_block(p, yaw, tall * 1.4)
			elif pick < 0.8:
				_lattice(p, yaw, tall)
			else:
				_radiators(p, yaw)


func _hangar(p: Vector3, yaw: float, tall: float, lit: bool) -> void:
	var w := rng.randf_range(30, 46)
	var l := rng.randf_range(40, 56)
	var h := rng.randf_range(14, 22) * tall
	var xf := at(p, yaw)
	var shell := white if rng.randf() < 0.55 else steel
	box(Vector3(w, h, l), xf * at(Vector3(0, h * 0.5, 0)), shell)
	for k in 4:
		var t := float(k + 1) / 4.0
		box(Vector3(w * (1.0 - t * 0.55), 1.6, l), xf * at(Vector3(0, h + k * 1.4 + 0.8, 0)), shell)
	box(Vector3(w * 0.7, h * 0.75, 0.6), xf * at(Vector3(0, h * 0.375, -l * 0.5 - 0.2)), dark)
	if lit or rng.randf() < 0.6:
		box(Vector3(w * 0.66, h * 0.7, 0.2), xf * at(Vector3(0, h * 0.36, -l * 0.5 - 0.55)), glow(WARM, 0.9))
	box(Vector3(w * 0.7, 0.5, 0.3), xf * at(Vector3(0, h * 0.75 + 0.3, -l * 0.5 - 0.6)), glow(AMBER if rng.randf() < 0.6 else CYAN, 3.0))
	box(Vector3(w + 0.4, 0.35, 0.3), xf * at(Vector3(0, h * 0.95, -l * 0.5 - 0.1)), glow(CYAN, 2.0))
	for s: float in [-1.0, 1.0]:
		box(Vector3(1.2, 0.8, 1.2), xf * at(Vector3(s * w * 0.5, h + 0.5, l * 0.5)), glow(RED, 5.0))


func _tanks(p: Vector3, yaw: float, tall: float) -> void:
	var xf := at(p, yaw)
	var n := rng.randi_range(2, 4)
	for k in n:
		var r := rng.randf_range(6, 10)
		var h := rng.randf_range(10, 24) * tall
		var q := Vector3((k - (n - 1) * 0.5) * 22.0, 0, rng.randf_range(-8, 8))
		var mat := white if rng.randf() < 0.6 else rust
		cyl(r, r, h, xf * at(q + Vector3(0, h * 0.5, 0)), mat, 20)
		cyl(r * 0.3, r, 2.5, xf * at(q + Vector3(0, h + 1.25, 0)), mat, 20)
		cyl(r + 0.05, r + 0.05, 0.6, xf * at(q + Vector3(0, h * 0.7, 0)), glow(_ad_color(), 2.2), 20)
	box(Vector3(n * 22.0, 1.4, 1.4), xf * at(Vector3(0, 5, 12)), dark)
	for k in n + 1:
		box(Vector3(0.6, 5, 0.6), xf * at(Vector3((k - n * 0.5) * 22.0, 2.5, 12)), dark)


func _containers(p: Vector3, yaw: float, rows: int) -> void:
	var xf := at(p, yaw)
	for row in rows:
		for col in 3:
			var tiers := rng.randi_range(0, 4)
			for t in tiers:
				box(Vector3(12.2, 2.6, 2.5), xf * at(Vector3(col * 13.0 - 13.0, 1.3 + t * 2.6, row * 3.0 - rows * 1.5)),
						paints[rng.randi() % paints.size()])
	if rows < 5 and rng.randf() < 0.5:
		# A straddle carrier over the stacks.
		for s: float in [-1.0, 1.0]:
			box(Vector3(1.2, 16, 1.2), xf * at(Vector3(s * 22, 8, -8)), rust)
			box(Vector3(1.2, 16, 1.2), xf * at(Vector3(s * 22, 8, 8)), rust)
		box(Vector3(46, 1.6, 18), xf * at(Vector3(0, 16.5, 0)), rust)
		box(Vector3(1, 1, 1), xf * at(Vector3(23, 17.8, 0)), glow(RED, 5.0))


func _cooler(p: Vector3, tall: float) -> void:
	var h := rng.randf_range(38, 58) * tall
	var r := h * 0.42
	cyl(r * 0.7, r, h * 0.55, at(p + Vector3(0, h * 0.275, 0)), concrete, 24)
	cyl(r * 0.78, r * 0.7, h * 0.45, at(p + Vector3(0, h * 0.775, 0)), concrete, 24)
	cyl(r * 0.79, r * 0.79, 0.8, at(p + Vector3(0, h - 2.0, 0)), glow(CYAN, 2.5), 24)
	cyl(r * 0.71, r * 0.71, 0.6, at(p + Vector3(0, h * 0.55, 0)), glow(AMBER, 2.0), 24)


func _block(p: Vector3, yaw: float, tall: float) -> void:
	var xf := at(p, yaw)
	var w := rng.randf_range(18, 34)
	var l := rng.randf_range(18, 30)
	var h := rng.randf_range(16, 44) * tall
	box(Vector3(w, h, l), xf * at(Vector3(0, h * 0.5, 0)), steel if rng.randf() < 0.6 else concrete)
	var floors := int(h / 4.0)
	var lights := WARM if rng.randf() < 0.7 else CYAN
	for f in range(1, floors):
		if rng.randf() < 0.6:
			var span := w * rng.randf_range(0.3, 0.9)
			box(Vector3(span, 0.6, 0.2), xf * at(Vector3(rng.randf_range(-1, 1) * (w - span) * 0.5, f * 4.0, -l * 0.5 - 0.1)),
					glow(lights, 1.8))
		if rng.randf() < 0.4:
			box(Vector3(0.2, 0.6, l * rng.randf_range(0.3, 0.8)), xf * at(Vector3(w * 0.5 + 0.1, f * 4.0, 0)), glow(lights, 1.8))
	box(Vector3(w * 0.4, 6, l * 0.4), xf * at(Vector3(w * 0.15, h + 3, 0)), dark)
	box(Vector3(0.4, 14, 0.4), xf * at(Vector3(-w * 0.3, h + 7, 0)), dark)
	box(Vector3(1, 1, 1), xf * at(Vector3(-w * 0.3, h + 14.5, 0)), glow(RED, 5.0))
	if rng.randf() < 0.55:
		# A screen hung on the face toward the track, in the circuit's colours.
		box(Vector3(w * 0.8, h * 0.3, 0.3), xf * at(Vector3(0, h * 0.65, -l * 0.5 - 0.3)), glow(_ad_color(), 1.4))
		box(Vector3(w * 0.84, h * 0.3 + 0.8, 0.3), xf * at(Vector3(0, h * 0.65, -l * 0.5 - 0.15)), dark)


func _radiators(p: Vector3, yaw: float) -> void:
	var xf := at(p, yaw)
	for row in 5:
		for col in 6:
			box(Vector3(6, 0.25, 3.5), xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(col * 7.0 - 17.5, 2.2, row * 6.0 - 12.0)), dark)
			box(Vector3(0.4, 2.0, 0.4), xf * at(Vector3(col * 7.0 - 17.5, 1.0, row * 6.0 - 12.0)), steel)
	box(Vector3(44, 0.15, 0.15), xf * at(Vector3(0, 0.3, -16)), glow(CYAN, 2.0))


func _lattice(p: Vector3, yaw: float, tall: float) -> void:
	var xf := at(p, yaw)
	var h := rng.randf_range(40, 80) * tall
	for s: Vector2 in [Vector2(-3, -3), Vector2(3, -3), Vector2(-3, 3), Vector2(3, 3)]:
		box(Vector3(0.8, h, 0.8), xf * at(Vector3(s.x, h * 0.5, s.y)), rust)
	var y := 6.0
	while y < h:
		box(Vector3(7, 0.5, 0.5), xf * at(Vector3(0, y, -3)), rust)
		box(Vector3(7, 0.5, 0.5), xf * at(Vector3(0, y, 3)), rust)
		box(Vector3(0.5, 0.5, 7), xf * at(Vector3(-3, y, 0)), rust)
		box(Vector3(0.5, 0.5, 7), xf * at(Vector3(3, y, 0)), rust)
		y += 8.0
	box(Vector3(26, 1.4, 1.6), xf * at(Vector3(8, h - 4, 0)), rust)
	box(Vector3(1.4, 1.4, 1.4), xf * at(Vector3(0, h + 0.8, 0)), glow(RED, 6.0))
	box(Vector3(7.2, 0.4, 7.2), xf * at(Vector3(0, h * 0.5, 0)), glow(CYAN, 2.5))


# --- Roads ----------------------------------------------------------------------------

## Service roads running out from the circuits into the works, lit at the
## edges, lamp posts along them.
func _roads() -> void:
	for k in 7:
		var a := TAU * k / 7.0 + 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var yaw := atan2(dir.x, dir.z)
		var d := 200.0
		while d < OUTER:
			var p := CENTRE + dir * d
			if clear(p, 22.0):
				box(Vector3(10, 0.06, 20.5), at(p + Vector3(0, 0.03, 0), yaw), asphalt, true)
				for s: float in [-1.0, 1.0]:
					box(Vector3(0.25, 0.08, 20.5), at(p + Vector3(0, 0.05, 0), yaw) * at(Vector3(s * 4.6, 0, 0)),
							glow(AMBER, 1.6), true)
				if int(d) % 60 == 0:
					var post := at(p, yaw) * at(Vector3(6.5, 0, 0))
					box(Vector3(0.4, 9, 0.4), post * at(Vector3(0, 4.5, 0)), dark, true)
					box(Vector3(2.4, 0.3, 0.6), post * at(Vector3(-1, 9, 0)), glow(WARM, 4.0), true)
			d += 20.0


# --- The festival -----------------------------------------------------------------------

## The infield's festival: a stage and its crowd, a big wheel, a screen and
## a street of food stalls, all inside Coilrun where the stands look on.
func _festival() -> void:
	var spot := Vector3(-95, 0, 185)
	var tries := 0
	while not clear(spot, 55.0) and tries < 80:
		tries += 1
		spot = Vector3(rng.randf_range(-170, 40), 0, rng.randf_range(80, 280))
	if tries >= 80:
		return
	# The stage, facing back toward the grandstand side.
	var stage := at(spot + Vector3(0, 0, 24), PI)
	box(Vector3(30, 2.4, 14), stage * at(Vector3(0, 1.2, 0)), dark)
	for s: float in [-1.0, 1.0]:
		box(Vector3(1.2, 16, 1.2), stage * at(Vector3(s * 15, 8, 6)), steel)
		box(Vector3(6, 10, 4), stage * at(Vector3(s * 19, 5, 2)), dark)
		box(Vector3(6.2, 0.3, 4.2), stage * at(Vector3(s * 19, 10.1, 2)), glow(MAGENTA, 3.0))
	box(Vector3(32, 1.2, 1.2), stage * at(Vector3(0, 16, 6)), steel)
	box(Vector3(26, 11, 0.3), stage * at(Vector3(0, 9, 6.5)), glow(CYAN, 1.5))
	for k in 8:
		box(Vector3(1.2, 0.8, 0.8), stage * at(Vector3(-13 + k * 3.7, 15.2, 5.2)), glow([CYAN, MAGENTA, AMBER][k % 3], 5.0))
	box(Vector3(30.4, 0.3, 0.2), stage * at(Vector3(0, 2.3, -7.1)), glow(CYAN, 3.0))
	# The crowd in front of it.
	for k in 700:
		var q := stage * Vector3(rng.randf_range(-20, 20), 0, -10.0 - pow(rng.randf(), 0.8) * 30.0)
		_person(q, stage.basis.get_euler().y + PI + rng.randf_range(-0.3, 0.3))
	# The big wheel off to one side.
	_wheel(spot + Vector3(-52, 0, -10), 0.5)
	# A street of stalls behind, both sides, lit awnings and queues.
	for k in 9:
		for s: float in [-1.0, 1.0]:
			var q := spot + Vector3(-34 + k * 10.0, 0, -42 + s * 7.0)
			if track_dist(q) < 16.0:
				continue
			var yaw := 0.0 if s < 0 else PI
			box(Vector3(8, 4, 5), at(q + Vector3(0, 2, 0), yaw), steel)
			box(Vector3(8.6, 0.3, 3.4), at(q, yaw) * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 4.4, -3.4)),
					glow([AMBER, CYAN, MAGENTA][(k + int(s)) % 3], 2.0))
			box(Vector3(6, 1.0, 0.2), at(q, yaw) * at(Vector3(0, 5.4, -2.6)), glow([CYAN, MAGENTA, AMBER][k % 3], 2.5))
	for k in 260:
		_person(spot + Vector3(rng.randf_range(-36, 56), 0, -42 + rng.randf_range(-3.5, 3.5)), rng.randf() * TAU)
	# String lights over the street.
	for k in 9:
		box(Vector3(0.1, 0.1, 15), at(spot + Vector3(-34 + k * 10.0, 7.0, -42)), glow(WARM, 3.0), true)
	for s: float in [-1.0, 1.0]:
		for k in 10:
			box(Vector3(0.3, 7.0, 0.3), at(spot + Vector3(-39 + k * 10.0, 3.5, -42 + s * 7.5)), dark, true)
	_milling(spot + Vector3(0, 0, -10), 45.0, 240)
	keep_out.append([spot, 60.0])


func _wheel(p: Vector3, yaw: float) -> void:
	var r := 28.0
	var hub := at(p, yaw) * at(Vector3(0, r + 5, 0))
	for s: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			box(Vector3(1.4, r + 8, 1.4), at(p, yaw) * Transform3D(Basis(Vector3.BACK, side * 0.3),
					Vector3(side * (r + 5) * 0.15, (r + 5) * 0.5, s * 3.5)), dark)
	box(Vector3(1.6, 1.6, 8), hub, dark)
	var ring := TorusMesh.new()
	ring.inner_radius = r - 0.6
	ring.outer_radius = r
	ring.rings = 48
	ring.ring_segments = 6
	_add(ring, hub * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), glow(MAGENTA, 3.0), false)
	for k in 18:
		var a := TAU * k / 18.0
		box(Vector3(0.4, r, 0.4), hub * Transform3D(Basis(Vector3.BACK, a), Vector3(-sin(a), cos(a), 0) * r * 0.5), steel)
		box(Vector3(2.6, 2.4, 2.6), hub * at(Vector3(-sin(a) * r, cos(a) * r - 1.7, 0)), glow(CYAN if k % 2 else AMBER, 1.8))


# --- Car parks and camps ------------------------------------------------------------------

## Fans' machines parked in rows and camps of tents just outside the
## circuits, people walking between them.
func _car_parks() -> void:
	var tries := 0
	var lots := 0
	while lots < 16 and tries < 500:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(150, INNER + 70.0)
		var p := CENTRE + Vector3(cos(a), 0, sin(a)) * r
		var yaw := rng.randf() * PI
		var xf := at(p, yaw)
		# The whole lot, every 8 m, stays well off the road.
		var ok := clear(p, 50.0)
		var gx := -28.0
		while ok and gx <= 28.0:
			var gz := -22.0
			while ok and gz <= 22.0:
				ok = clear(xf * Vector3(gx, 0, gz), 24.0)
				gz += 8.0
			gx += 8.0
		if not ok:
			continue
		lots += 1
		keep_out.append([p, 36.0])
		box(Vector3(56, 0.05, 44), xf * at(Vector3(0, 0.02, 0)), asphalt, true)
		if rng.randf() < 0.6:
			_lot(xf)
		else:
			_camp(xf)


func _lot(xf: Transform3D) -> void:
	for row in 5:
		for col in 12:
			if rng.randf() < 0.18:
				continue
			var q := Vector3(col * 4.4 - 24.2, 0, row * 8.0 - 16.0)
			var hover := rng.randf() < 0.4
			var lift := 0.6 if hover else 0.0
			box(Vector3(2.0, 0.9, 4.2), xf * at(q + Vector3(0, 0.6 + lift, 0)), paints[rng.randi() % paints.size()], true)
			box(Vector3(1.7, 0.6, 2.0), xf * at(q + Vector3(0, 1.35 + lift, -0.2)), dark, true)
			if hover:
				box(Vector3(1.6, 0.08, 3.6), xf * at(q + Vector3(0, 0.15, 0)), glow(CYAN, 2.5), true)
		box(Vector3(54, 0.04, 0.2), xf * at(Vector3(0, 0.06, row * 8.0 - 12.0)), glow(WARM, 0.8), true)
	_milling(xf.origin, 22.0, 30)


func _camp(xf: Transform3D) -> void:
	for t in 18:
		var q := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-18, 18))
		cyl(0.05, rng.randf_range(1.6, 2.4), rng.randf_range(1.6, 2.2), xf * at(q + Vector3(0, 1.0, 0), rng.randf() * TAU),
				paints[rng.randi() % paints.size()], 4, true)
	for f in 3:
		var q := Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-12, 12))
		cyl(0.9, 1.1, 0.5, xf * at(q + Vector3(0, 0.25, 0)), glow(AMBER, 4.0), 8, true)
		for k in 8:
			var a := TAU * k / 8.0
			_person(xf * (q + Vector3(cos(a), 0, sin(a)) * 2.6), -a + PI * 0.5)
	box(Vector3(0.3, 6, 0.3), xf * at(Vector3(0, 3, 0)), dark, true)
	for s in 4:
		var a := TAU * s / 4.0
		box(Vector3(0.08, 0.08, 18), xf * Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.3),
				Vector3(sin(a), 0, cos(a)) * 8.0 + Vector3(0, 3.0, 0)), glow(AMBER, 3.0), true)
	_milling(xf.origin, 20.0, 20)


# --- Trackside ------------------------------------------------------------------------------

## Catch fences, hoardings and tyre walls along a track's ground-level
## road, so it never runs through bare salt. They keep clear of the stands
## and of any other road.
func _trackside(track: RaceTrack) -> void:
	var pts := track.points
	var n := pts.size()
	var spacing := 4
	var i := 0
	while i < n:
		var p := pts[i]
		if p.y > 2.0:
			i += spacing
			continue
		var side := track.side(i)
		var yaw := track.heading(i)
		var turn := track.forward(i).cross(track.forward((i + 6) % n)).y
		for s: float in [-1.0, 1.0]:
			var q := p + side * s * (track.width * 0.5 + 7.0)
			q.y = 0
			if track_dist(q) < track.width * 0.5 + 5.0 or not _beside_free(q):
				continue
			var xf := at(q, yaw)
			box(Vector3(0.2, 4.0, 0.2), xf * at(Vector3(0, 2.0, 0)), dark, true)
			box(Vector3(0.06, 0.06, RaceTrack.STEP * spacing), xf * at(Vector3(0, 4.0, 0)), glow(CYAN, 1.2), true)
			box(Vector3(0.04, 0.04, RaceTrack.STEP * spacing), xf * at(Vector3(0, 2.2, 0)), dark, true)
			var slot := i / spacing
			if slot % 2 == 0:
				var c: Color = [CYAN, AMBER, MAGENTA, Color(0.9, 0.9, 0.95)][(slot / 2 + (1 if s > 0 else 0)) % 4]
				# A hoarding in front of the fence, its lit face to the road.
				box(Vector3(0.3, 1.4, 6.6), xf * at(Vector3(-s * 0.6, 0.9, 0)), dark, true)
				box(Vector3(0.05, 1.0, 6.0), xf * at(Vector3(-s * 0.78, 0.9, 0)), glow(c, 1.8), true)
			if signf(turn) == s and absf(turn) > 0.01:
				for t in 3:
					cyl(0.45, 0.45, 0.9, xf * at(Vector3(-s * 1.4, 0.45, t * 1.0 - 1.0)), dark, 10, true)
		i += spacing


## True where nothing the map already built stands at `q`.
func _beside_free(q: Vector3) -> bool:
	for k: Array in keep_out:
		var c: Vector3 = k[0]
		if k.size() > 2 and Vector2(q.x - c.x, q.z - c.z).length() < float(k[2]):
			return false
	return true
