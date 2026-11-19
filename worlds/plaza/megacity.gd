extends Node3D
## The megacity round the Concourse (Caleb's ask: from the ground it should
## feel tall and grand, a city that goes on up and down for ever). View
## only: no collision, nothing read by the simulation, built by the map only
## where `Look` is on, from its own RNG so it never shifts the layout.
##
## The deck is one terrace part way up the city, not its roof. The towers
## round it stand on a canyon floor far below (`FLOOR_Y`) and rise in rings
## that fade into the haze: a near ring that looks down on you, a middle
## ring hundreds of metres over the deck, a far ring of giants a kilometre
## tall and a few landmark spires over all of it. Skyways link tower to
## tower, and streams of air traffic circle the Concourse at many heights.
##
## Everything is drawn in a handful of meshes: every tower box in one, lit
## with windows by `megacity.gdshader` from the world position (no window is
## geometry), the lights on top in another, and the traffic one MultiMesh
## flown by `sky_traffic.gdshader` alone, so none of it costs the CPU a
## thing per frame.

const MEGACITY_SHADER := preload("res://assets/shaders/megacity.gdshader")
const TRAFFIC_SHADER := preload("res://assets/shaders/sky_traffic.gdshader")

## The canyon floor, far under the deck.
const FLOOR_Y := -420.0
const CYAN := Color(0.25, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.85)
const AMBER := Color(1.0, 0.62, 0.25)
const RED := Color(1.0, 0.18, 0.12)
## The rings of towers: [from, to, count, lowest top, highest top, narrowest,
## widest], radii from the middle of the deck and tops in metres over it.
const RINGS := [
	[300.0, 520.0, 46, 70.0, 300.0, 24.0, 46.0],
	[520.0, 900.0, 64, 160.0, 560.0, 34.0, 70.0],
	[900.0, 1500.0, 72, 260.0, 850.0, 50.0, 110.0],
	[1500.0, 2400.0, 60, 380.0, 1150.0, 70.0, 150.0],
]
## Landmark spires: [bearing, radius, top, width]. Placed where they stand
## over the places people look: past the gates, over Market Row and off the
## civic square and the residences.
const LANDMARKS := [
	[18.0, 820.0, 1350.0, 90.0],
	[160.0, 1050.0, 1500.0, 110.0],
	[95.0, 640.0, 980.0, 70.0],
	[265.0, 900.0, 1200.0, 85.0],
	[320.0, 1500.0, 1700.0, 140.0],
]
## The low city in the canyon under the rail: block tops between these.
const UNDERCITY := [260.0, 700.0, 180, -330.0, -45.0]
## Air lanes: [radius, height, craft, speed]. Each is flown both ways, the
## two streams a few metres apart.
const LANES := [
	[290.0, 35.0, 46, 55.0],
	[340.0, -60.0, 50, 70.0],
	[420.0, 120.0, 60, 65.0],
	[520.0, 210.0, 60, 80.0],
	[610.0, 60.0, 70, 75.0],
	[760.0, 320.0, 70, 90.0],
	[900.0, 160.0, 80, 85.0],
	[1100.0, 450.0, 80, 100.0],
	[1350.0, 260.0, 90, 95.0],
	[1700.0, 600.0, 90, 110.0],
]

## How far the view must draw to see all of it.
const VIEW_FAR := 3200.0

var rng := RandomNumberGenerator.new()
## The deck's rail radius: nothing stands nearer.
var rim := 240.0
var _boxes: Array = []
var _lights := {}
## Towers already placed, [position (xz), half width], so none overlap.
var _placed: Array = []
## Tower tops, for skyways: [position, top].
var _tops: Array = []
var _material: ShaderMaterial


func _init(p_seed: int, p_rim: float) -> void:
	rng.seed = p_seed
	rim = p_rim
	name = "Megacity"


## The window material, shared with the map's own towers (`material_for`).
static func material_for(near := false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = MEGACITY_SHADER
	if near:
		# Up close the haze barely touches them, and the floors are a size
		# that reads against a person.
		mat.set_shader_parameter("haze_max", 0.5)
		mat.set_shader_parameter("lit_share", 0.4)
		mat.set_shader_parameter("band_every", 12.0)
	return mat


func build() -> void:
	_material = material_for()
	for ring: Array in RINGS:
		_ring(ring)
	for spec: Array in LANDMARKS:
		_landmark(spec)
	_undercity()
	_skyways()
	_canyon_floor()
	_flush()
	_traffic()


func _ring(ring: Array) -> void:
	var from: float = ring[0]
	var to: float = ring[1]
	var count: int = ring[2]
	var tries := count * 6
	var made := 0
	while made < count and tries > 0:
		tries -= 1
		var bearing := rng.randf() * 360.0
		var r := rng.randf_range(from, to)
		var w := rng.randf_range(ring[5], ring[6])
		var at := _at(r, bearing)
		if not _free(at, w * 0.75):
			continue
		var top := rng.randf_range(ring[3], ring[4])
		# Taller further out on average, but with a few short ones between,
		# so the skyline steps rather than ramps.
		if rng.randf() < 0.25:
			top *= 0.55
		_tower(at, w, rng.randf_range(0.7, 1.0) * w, top, rng.randf() * TAU)
		made += 1


func _free(at: Vector3, half: float) -> bool:
	for other: Array in _placed:
		var o: Vector3 = other[0]
		if Vector2(at.x - o.x, at.z - o.z).length() < (half + float(other[1])) * 1.15:
			return false
	_placed.append([at, half])
	return true


## One tower from the canyon floor to `top` over the deck: a shape picked
## at random from a few (stepped setbacks, a sheer slab with a crown, twin
## blades joined high up, a needle), lit by the window shader, with a crown
## of light and a red beacon.
func _tower(at: Vector3, w: float, d: float, top: float, yaw: float) -> void:
	var turn := Basis(Vector3.UP, yaw)
	var kind := rng.randi_range(0, 3)
	var bottom := FLOOR_Y
	var accent: Color = [CYAN, MAGENTA, AMBER, Color(0.6, 0.7, 1.0)][rng.randi_range(0, 3)]
	match kind:
		0:
			# Stepped setbacks, three to five of them.
			var tiers := rng.randi_range(3, 5)
			var y := bottom
			var tw := w
			var td := d
			var span := top - bottom
			for t in tiers:
				var share := 0.5 if t == 0 else (1.0 - 0.5) / float(tiers - 1)
				var tall := span * share
				_box(Vector3(tw, tall, td), at + Vector3(0, y + tall * 0.5, 0), turn)
				_band(at, Vector3(tw, 0, td), y + tall, turn, accent)
				y += tall
				tw *= rng.randf_range(0.66, 0.84)
				td *= rng.randf_range(0.66, 0.84)
			_crown(at, Vector3(tw, 0, td), top, turn, accent, rng.randf() < 0.5)
		1:
			# A sheer slab with a lit crown and a mast.
			_box(Vector3(w, top - bottom, d * 0.55), at + Vector3(0, (top + bottom) * 0.5, 0), turn)
			_band(at, Vector3(w, 0, d * 0.55), top, turn, accent)
			_crown(at, Vector3(w * 0.3, 0, d * 0.3), top, turn, accent, true)
		2:
			# Twin blades, joined by a bridge block high up.
			var gap := w * 0.35
			for side: float in [-1.0, 1.0]:
				var tall := top - bottom - (0.0 if side < 0 else top * 0.18)
				var c := at + turn * Vector3(side * (gap + w * 0.3) * 0.5, 0, 0)
				_box(Vector3(w * 0.3, tall, d), c + Vector3(0, bottom + tall * 0.5, 0), turn)
				_band(c, Vector3(w * 0.3, 0, d), bottom + tall, turn, accent)
			var link_y := top * rng.randf_range(0.45, 0.7)
			_box(Vector3(gap + w * 0.6, 14.0, d * 0.7), at + Vector3(0, link_y, 0), turn)
			_light(Vector3(gap + w * 0.62, 1.2, d * 0.72), at + Vector3(0, link_y - 7.0, 0), turn, accent)
			_crown(at + turn * Vector3(-(gap + w * 0.3) * 0.5, 0, 0), Vector3(w * 0.3, 0, d), top, turn, accent, false)
		_:
			# A needle: a broad foot, a slim shaft and a long spire.
			var foot := (top - bottom) * 0.45
			_box(Vector3(w, foot, d), at + Vector3(0, bottom + foot * 0.5, 0), turn)
			_band(at, Vector3(w, 0, d), bottom + foot, turn, accent)
			var shaft := top - bottom - foot
			_box(Vector3(w * 0.5, shaft, d * 0.5), at + Vector3(0, bottom + foot + shaft * 0.5, 0), turn)
			_crown(at, Vector3(w * 0.5, 0, d * 0.5), top, turn, accent, true)
	_tops.append([at, top])


## A landmark: a colossal stepped spire over everything, with lit fins up
## its corners and a long mast.
func _landmark(spec: Array) -> void:
	var at := _at(spec[1], spec[0])
	var top: float = spec[2]
	var w: float = spec[3]
	_placed.append([at, w * 0.8])
	var turn := Basis(Vector3.UP, deg_to_rad(spec[0]) + PI / 4.0)
	var y := FLOOR_Y
	var tw := w
	var levels := [0.38, 0.24, 0.16, 0.12, 0.10]
	var span := top - y
	for share: float in levels:
		var tall := span * share
		_box(Vector3(tw, tall, tw), at + Vector3(0, y + tall * 0.5, 0), turn)
		# Fins up each corner, lit along their edge.
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var corner := turn * Vector3(cx * tw * 0.5, 0, cz * tw * 0.5)
				_light(Vector3(1.4, tall, 1.4), at + corner + Vector3(0, y + tall * 0.5, 0), turn, CYAN)
		_band(at, Vector3(tw, 0, tw), y + tall, turn, CYAN)
		y += tall
		tw *= 0.74
	var mast := top * 0.12
	_box(Vector3(tw * 0.25, mast, tw * 0.25), at + Vector3(0, top + mast * 0.5, 0), turn)
	_light(Vector3(tw * 0.3, 3.0, tw * 0.3), at + Vector3(0, top + mast, 0), turn, Color(0.8, 1.0, 1.0))
	_light(Vector3(4, 4, 4), at + Vector3(0, top + mast + 6.0, 0), turn, RED)
	_tops.append([at, top])


## The low city down in the canyon, round under the rail: what you see when
## you look over it.
func _undercity() -> void:
	var made := 0
	var tries: int = UNDERCITY[2] * 5
	while made < UNDERCITY[2] and tries > 0:
		tries -= 1
		var bearing := rng.randf() * 360.0
		var r := rng.randf_range(UNDERCITY[0], UNDERCITY[1])
		var w := rng.randf_range(16.0, 40.0)
		var at := _at(r, bearing)
		if not _free(at, w * 0.6):
			continue
		var top := rng.randf_range(UNDERCITY[3], UNDERCITY[4])
		var turn := Basis(Vector3.UP, rng.randf() * TAU)
		_box(Vector3(w, top - FLOOR_Y, w * rng.randf_range(0.6, 1.0)), at + Vector3(0, (top + FLOOR_Y) * 0.5, 0), turn)
		if rng.randf() < 0.5:
			_light(Vector3(w * 0.5, 1.5, w * 0.5), at + Vector3(0, top + 0.75, 0), turn,
					[CYAN, MAGENTA, AMBER][rng.randi_range(0, 2)])
		made += 1
	# The deck's own underside: the terrace sits on a great tapering pier
	# going down into the dark, ringed with lit bands.
	var y := -2.0
	var r := rim + 2.0
	for k in 6:
		var tall := 55.0
		for i in 24:
			var bearing := 360.0 * (i + 0.5) / 24.0
			var turn := Basis(Vector3.UP, -deg_to_rad(bearing))
			var seg := TAU * r / 24.0 + 2.0
			_box(Vector3(seg, tall, 6.0), _at(r - 3.0, bearing) + Vector3(0, y - tall * 0.5, 0), turn)
			if k % 2 == 0:
				_light(Vector3(seg, 0.8, 0.4), _at(r + 0.2, bearing) + Vector3(0, y - 4.0, 0), turn, CYAN)
		y -= tall
		r *= 0.86


## Skyways: long bridges between towers that stand near each other, at a
## height both reach, with lit edges.
func _skyways() -> void:
	var made := 0
	for i in _tops.size():
		if made >= 60:
			break
		var a: Array = _tops[i]
		for j in range(i + 1, _tops.size()):
			var b: Array = _tops[j]
			var pa: Vector3 = a[0]
			var pb: Vector3 = b[0]
			var span := Vector2(pb.x - pa.x, pb.z - pa.z).length()
			if span < 60.0 or span > 260.0 or rng.randf() > 0.35:
				continue
			var low := minf(a[1], b[1])
			var height := rng.randf_range(-200.0, low * 0.8)
			var mid := (pa + pb) * 0.5 + Vector3(0, height, 0)
			var yaw := atan2(pb.x - pa.x, pb.z - pa.z)
			var turn := Basis(Vector3.UP, yaw)
			_box(Vector3(8.0, 5.0, span), mid, turn)
			for side: float in [-1.0, 1.0]:
				_light(Vector3(0.6, 0.6, span), mid + turn * Vector3(side * 4.2, -2.2, 0), turn, AMBER)
			made += 1
			break


## The canyon floor: lit streets far below, lost in the warm haze.
func _canyon_floor() -> void:
	_box(Vector3(6000, 2, 6000), Vector3(0, FLOOR_Y - 1.0, 0), Basis.IDENTITY)


func _box(size: Vector3, at: Vector3, turn: Basis) -> void:
	_boxes.append([size, Transform3D(turn, at)])


func _light(size: Vector3, at: Vector3, turn: Basis, color: Color) -> void:
	if not _lights.has(color):
		_lights[color] = []
	(_lights[color] as Array).append([size, Transform3D(turn, at)])


## A lit band round a box's top edge at height `y`.
func _band(at: Vector3, size: Vector3, y: float, turn: Basis, color: Color) -> void:
	_light(Vector3(size.x + 0.8, 1.6, size.z + 0.8), at + Vector3(0, y - 0.8, 0), turn, color)


## The top of a tower: a lit cap, sometimes a mast, always a red beacon.
func _crown(at: Vector3, size: Vector3, top: float, turn: Basis, color: Color, mast: bool) -> void:
	_light(Vector3(size.x * 0.7, 2.0, size.z * 0.7), at + Vector3(0, top + 1.0, 0), turn, color)
	var tip := top + 2.0
	if mast:
		var tall := rng.randf_range(20.0, 70.0)
		_box(Vector3(2.5, tall, 2.5), at + Vector3(0, top + tall * 0.5, 0), turn)
		tip = top + tall
	_light(Vector3(3.0, 3.0, 3.0), at + Vector3(0, tip + 1.5, 0), turn, RED)


func _flush() -> void:
	_mesh(_boxes, _material)
	for color: Color in _lights:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color * 2.4
		mat.disable_fog = true
		_mesh(_lights[color], mat)
	_boxes.clear()
	_lights.clear()


func _mesh(parts: Array, material: Material) -> void:
	if parts.is_empty():
		return
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	for part: Array in parts:
		box.size = part[0]
		tool.append_from(box, 0, part[1])
	var mesh := tool.commit()
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(node)


## Streams of air traffic round the Concourse, each lane flown both ways.
func _traffic() -> void:
	var total := 0
	for lane: Array in LANES:
		total += int(lane[2]) * 2
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	var craft := BoxMesh.new()
	craft.size = Vector3(1, 1, 1)
	multi.mesh = craft
	multi.instance_count = total
	var tails := [RED, AMBER, CYAN, Color(1.0, 0.95, 0.9)]
	var k := 0
	for lane: Array in LANES:
		var color: Color = tails[rng.randi_range(0, tails.size() - 1)]
		for way: float in [-1.0, 1.0]:
			for i in int(lane[2]):
				var size := Vector3(rng.randf_range(2.0, 3.5), rng.randf_range(0.8, 1.4), rng.randf_range(5.0, 9.0))
				multi.set_instance_transform(k, Transform3D(Basis.from_scale(size), Vector3.ZERO))
				multi.set_instance_color(k, color)
				var radius: float = lane[0] + way * 7.0
				var height: float = lane[1] + way * 3.0 + rng.randf_range(-2.0, 2.0)
				var speed: float = lane[3] * rng.randf_range(0.9, 1.1) * way
				# Bunched in loose convoys rather than evenly spaced.
				var phase := rng.randf() * TAU
				multi.set_instance_custom_data(k, Color(radius, height, speed, phase))
				k += 1
	var node := MultiMeshInstance3D.new()
	node.name = "Traffic"
	node.multimesh = multi
	var mat := ShaderMaterial.new()
	mat.shader = TRAFFIC_SHADER
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves every craft, so the bounds are the whole sky.
	node.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1500, 4000))
	add_child(node)


## A point `radius` metres out on compass `bearing` (degrees, 0 north, clockwise).
static func _at(radius: float, bearing: float) -> Vector3:
	var a := deg_to_rad(bearing)
	return Vector3(sin(a) * radius, 0, -cos(a) * radius)
