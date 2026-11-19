extends Node3D
## Ashfront's giants on the horizon (DESIGN.md "Scale you can see"): the
## Colossus, a war walker far taller than anything on the field, striding
## round past the rim, and a capital ship riding at anchor in the sky. View
## only and never in a server: the map adds one only where `Look` is on.
## Both are timed by the wall clock, so every player sees them in the same
## place, and a footfall is heard once its sound has had time to arrive.

## How far out the Colossus walks, and how high its hips ride (before `SCALE`).
const WALK_RADIUS := 750.0
const HIP_HEIGHT := 129.0
## Its pace (m/s) along its round and one stride's length in time.
const WALK_SPEED := 4.0
const STRIDE_TIME := 13.0
## The walker is built at this size and then scaled up as a whole.
const SCALE := 1.7
## Four legs, each a thigh arching up over the body and a long shin that
## tapers down to a broad foot.
const THIGH := 80.0
const SHIN := 194.0
## How far each thigh is raised out from hanging (radians) and how far the
## shin folds back from it, standing.
const THIGH_RAISE := 2.4
const KNEE_FOLD := 2.15
## Each leg's corner on the body and where it is in the stride: diagonal
## pairs move together, the pairs half a stride apart.
const LEGS := [
	[Vector3(30, 0, 48), 0.0], [Vector3(-30, 0, -48), 0.0],
	[Vector3(-30, 0, 48), 0.5], [Vector3(30, 0, -48), 0.5],
]
## The capital ship: where it rides, how high and how long it is.
const SHIP_ANGLE := 200.0
const SHIP_RADIUS := 900.0
const SHIP_HEIGHT := 400.0

## Dropship wings: one leaves the capital ship every `WING_EVERY` seconds,
## flies `WING_FLIGHT` seconds down over the fighting and away past the
## rim, more ships to a wing the hotter the war.
const WING_EVERY := 75.0
const WING_FLIGHT := 50.0
const WING_SIZE := Vector2i(2, 5)
const WING_LOW := 110.0

## Where the ground under the giants is (the skyline's floor).
var floor_y := 38.0
var soundscape: Node = null
## Makes a smoke plume (the map's own), for the vents on the walker's back.
var plume_maker := Callable()

var _colossus: Node3D
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _was_lifted: Array[bool] = []
var _body: Node3D
var _lamp: Node3D
var _blinkers: Array[GeometryInstance3D] = []
var _ship: Node3D
var _ship_home := Transform3D.IDENTITY
var _lights: Array[GeometryInstance3D] = []
var _wing: Array[Node3D] = []
var _wing_cycle := -1
var _wing_path: Array[Vector3] = []


func _ready() -> void:
	name = "Giants"
	var hull := Look.trim("distant")
	_build_colossus(hull)
	_build_ship(hull)
	for i in WING_SIZE.y:
		_wing.append(_build_dropship(hull))
	# Every part is far off and drawn as far as the sky goes: small parts
	# would otherwise be cut off close by (`Look._limit_draw_distance`).
	for part in find_children("*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).visibility_range_end = 2000.0
	_place(clock())


func _process(_delta: float) -> void:
	_place(clock())


## The time the giants keep: the wall clock, so every machine agrees.
static func clock() -> float:
	return fmod(Time.get_unix_time_from_system(), 100000.0)


## Where the Colossus stands at time `t` and which way it faces: on its
## round past the rim, walking along it.
static func walker_at(t: float) -> Transform3D:
	var angle := t * WALK_SPEED / WALK_RADIUS
	var at := Vector3(cos(angle) * WALK_RADIUS, 0.0, sin(angle) * WALK_RADIUS)
	var ahead := Vector3(-sin(angle), 0.0, cos(angle))
	return Transform3D(Basis.looking_at(-ahead), at)


## A leg's place in its stride at time `t`, from 0 to 1.
static func stride(t: float, offset: float) -> float:
	return fposmod(t / STRIDE_TIME + offset, 1.0)


## How high a leg is lifted at stride phase `phase`: it swings forward in
## the air for half the stride and stands on the ground for the other half.
static func lift(phase: float) -> float:
	return maxf(0.0, sin(phase * TAU))


func _place(t: float) -> void:
	var walk := walker_at(t)
	walk.origin.y = floor_y + 2.5 * sin(t / STRIDE_TIME * TAU * 2.0)
	_colossus.transform = walk.scaled_local(Vector3.ONE * SCALE)
	# The hull rolls a little onto each planted pair and nods with the step.
	var step := t / STRIDE_TIME * TAU
	_body.basis = Basis(Vector3.BACK, 0.03 * sin(step)) * Basis(Vector3.RIGHT, 0.02 * sin(step * 2.0))
	# The searchlight sweeps the ground ahead of it.
	_lamp.basis = Basis(Vector3.UP, 0.45 * sin(t * 0.23)) * Basis(Vector3.RIGHT, -0.85 + 0.12 * sin(t * 0.37))
	for i in _hips.size():
		var phase := stride(t, LEGS[i][1])
		var up := lift(phase)
		var side := signf((LEGS[i][0] as Vector3).x)
		# Swing forward while lifted, push back while planted.
		var sweep := 0.2 * cos(phase * TAU) * -signf((LEGS[i][0] as Vector3).z)
		_hips[i].basis = Basis(Vector3.UP, sweep) * Basis(Vector3.BACK, side * (THIGH_RAISE + 0.1 * up))
		_knees[i].basis = Basis(Vector3.BACK, -side * (KNEE_FOLD - 0.3 * up))
		var lifted := up > 0.02
		# One of each pair is heard landing: a footfall every half stride.
		if i % 2 == 0 and _was_lifted[i] and not lifted and soundscape != null:
			soundscape.call("boom", _feet[i].global_position)
		_was_lifted[i] = lifted
	for i in _blinkers.size():
		_blinkers[i].visible = int(t * 1.4 + i * 0.5) % 2 == 0
	if _ship != null:
		_ship.transform = _ship_home * Transform3D(Basis(Vector3.UP, 0.04 * sin(t * 0.05)), Vector3(0, 4.0 * sin(t * 0.21), 0))
	_fly_wing(t)
	# Ash hides their lights with the rest of the skyline.
	var seen := 1.0 - Look.weather_cover
	for light in _lights:
		light.transparency = 1.0 - seen


## How many ships fly in a wing at war intensity `heat` (0 to 1).
static func wing_size(heat: float) -> int:
	return WING_SIZE.x + int(round(clampf(heat, 0.0, 1.0) * (WING_SIZE.y - WING_SIZE.x)))


## A point along a dropship's flight from `from` down past `over` and away
## to `to`, at `p` from 0 to 1: one smooth curve through `over` halfway.
static func flight_point(from: Vector3, over: Vector3, to: Vector3, p: float) -> Vector3:
	var bend := over * 2.0 - (from + to) * 0.5
	var q := 1.0 - p
	return from * q * q + bend * 2.0 * q * p + to * p * p


## Where the wing's lead ship is now, or INF while no wing is in the sky
## (what the flak shoots at, `skyfire.gd`).
func wing_lead() -> Vector3:
	for ship in _wing:
		if ship.visible:
			return ship.global_position
	return Vector3.INF


func _fly_wing(t: float) -> void:
	var cycle := int(floor(t / WING_EVERY))
	var p := (t - cycle * WING_EVERY) / WING_FLIGHT
	if cycle != _wing_cycle:
		# Each wing heads for where the fighting is as it sets out.
		_wing_cycle = cycle
		var map := get_parent()
		var centre: Vector3 = map.get_meta("war_centre", Vector3.ZERO) if map != null else Vector3.ZERO
		var from := _ship.global_position + Vector3(0, -30, 0)
		var over := Vector3(centre.x, floor_y + WING_LOW, centre.z)
		var away := Vector3(over.x - from.x, 0, over.z - from.z).normalized()
		_wing_path = [from, over, over + away * 700.0 + Vector3(0, 260, 0)]
	var heat := float(get_parent().get_meta("war_intensity", 0.0)) if get_parent() != null else 0.0
	var count := wing_size(heat)
	for i in _wing.size():
		var ship := _wing[i]
		ship.visible = p < 1.0 and i < count
		if not ship.visible:
			continue
		# A loose echelon: each ship a little behind and beside the last.
		var lag := clampf(p - i * 0.012, 0.0, 1.0)
		var here := flight_point(_wing_path[0], _wing_path[1], _wing_path[2], lag)
		var ahead := flight_point(_wing_path[0], _wing_path[1], _wing_path[2], minf(lag + 0.01, 1.0))
		var heading := ahead - here
		if heading.length() < 0.01:
			continue
		var basis := Basis.looking_at(heading.normalized())
		ship.global_transform = Transform3D(basis, here + basis * Vector3((i % 2 * 2 - 1) * i * 16.0, -i * 3.0, 0))


func _build_dropship(hull: Material) -> Node3D:
	var ship := Node3D.new()
	ship.name = "Dropship"
	ship.visible = false
	add_child(ship)
	# Nose to -Z: a blunt hull, swept wings and two engine pods behind.
	_box(Vector3(8, 5, 26), Transform3D.IDENTITY, hull, ship)
	_box(Vector3(28, 1.2, 9), Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 0.5, 3)), hull, ship)
	_box(Vector3(5, 3, 8), Transform3D.IDENTITY.translated(Vector3(0, 3.5, 6)), hull, ship)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(3.5, 3.5, 9), Transform3D.IDENTITY.translated(Vector3(side * 12, 0, 5)), hull, ship)
		_light("flash", 10.0, Vector3(side * 12, 0, 11), ship)
	_light("halo", 3.0, Vector3(0, -2.5, -12), ship)
	return ship


func _build_colossus(hull: Material) -> void:
	_colossus = Node3D.new()
	_colossus.name = "Colossus"
	add_child(_colossus)
	_body = Node3D.new()
	_body.position = Vector3(0, HIP_HEIGHT, 0)
	_colossus.add_child(_body)
	# A hunched hull: low and long, the shoulders humped over the back
	# legs, the front dipping to a head thrust forward on a short neck.
	_box(Vector3(72, 30, 112), Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 6, 4)), hull, _body)
	_box(Vector3(58, 30, 56), Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 30, -26)), hull, _body)
	_box(Vector3(40, 18, 40), Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 30, 22)), hull, _body)
	_box(Vector3(22, 16, 34), Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, -4, 64)), hull, _body)
	var head := Node3D.new()
	head.position = Vector3(0, -14, 86)
	head.basis = Basis(Vector3.RIGHT, 0.25)
	_body.add_child(head)
	_box(Vector3(30, 18, 30), Transform3D.IDENTITY, hull, head)
	_box(Vector3(34, 6, 22), Transform3D.IDENTITY.translated(Vector3(0, 10, -2)), hull, head)
	_box(Vector3(10, 10, 16), Transform3D.IDENTITY.translated(Vector3(0, -12, 6)), hull, head)
	# One long eye slit across its face, and a glow round it to carry far.
	var slit := _box(Vector3(22, 2.2, 1.0), Transform3D.IDENTITY.translated(Vector3(0, 3, 15.2)), Look.trim("beacon"), head)
	_lights.append(slit)
	_light("halo", 26.0, Vector3(0, 3, 17), head)
	# A gun along the spine and a mast, and vents on the hump trailing smoke.
	_box(Vector3(5, 5, 90), Transform3D(Basis(Vector3.RIGHT, 0.05), Vector3(0, 46, 30)), hull, _body)
	_box(Vector3(14, 10, 22), Transform3D.IDENTITY.translated(Vector3(0, 46, -6)), hull, _body)
	_box(Vector3(2.5, 50, 2.5), Transform3D.IDENTITY.translated(Vector3(14, 66, -30)), hull, _body)
	_light("halo", 6.0, Vector3(14, 92, -30), _body)
	for vent: Vector3 in [Vector3(-16, 46, -40), Vector3(16, 46, -44)]:
		_box(Vector3(8, 14, 8), Transform3D.IDENTITY.translated(vent), hull, _body)
		if plume_maker.is_valid():
			var plume: Node3D = plume_maker.call(Vector3.ZERO, 3.0)
			plume.position = vent + Vector3(0, 8, 0)
			_body.add_child(plume)
	# Running lights down its flanks.
	for i in 6:
		_light("flash", 6.0, Vector3(-37 + (i % 2) * 74, 16, -40 + (i / 2) * 36), _body)
	# The searchlight under its chin: a long pale cone over the ground.
	_lamp = Node3D.new()
	_lamp.position = Vector3(0, -12, 8)
	head.add_child(_lamp)
	var cone := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 1.5
	shape.bottom_radius = 26.0
	shape.height = 200.0
	shape.cap_top = false
	shape.cap_bottom = false
	shape.radial_segments = 16
	shape.material = Look.trim("beam")
	cone.mesh = shape
	cone.position = Vector3(0, -100.0, 0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp.add_child(cone)
	_lights.append(cone)
	for leg: Array in LEGS:
		var hip := Node3D.new()
		hip.position = _body.position + (leg[0] as Vector3)
		_colossus.add_child(hip)
		_box(Vector3(20, 16, 20), Transform3D.IDENTITY, hull, hip)
		_taper(9.0, 6.0, THIGH, Vector3(0, -THIGH * 0.5, 0), hull, hip)
		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		_box(Vector3(16, 18, 16), Transform3D(Basis(Vector3.BACK, 0.4), Vector3.ZERO), hull, knee)
		_light("halo", 5.0, Vector3(0, 10, 0), knee)
		_blinkers.append(_lights[_lights.size() - 1])
		_taper(6.0, 2.6, SHIN, Vector3(0, -SHIN * 0.5, 0), hull, knee)
		var foot := Node3D.new()
		foot.position = Vector3(0, -SHIN, 0)
		knee.add_child(foot)
		_box(Vector3(10, 8, 10), Transform3D.IDENTITY.translated(Vector3(0, 3, 0)), hull, foot)
		# A broad foot with three toes, so a step reads as a step.
		for toe in 3:
			var turn := (toe - 1) * 0.5
			_box(Vector3(5, 4, 22), Transform3D(Basis(Vector3.UP, turn), Vector3(sin(turn) * 9.0, 0, cos(turn) * 9.0)), hull, foot)
		_hips.append(hip)
		_knees.append(knee)
		_feet.append(foot)
		_was_lifted.append(false)


func _build_ship(hull: Material) -> void:
	_ship = Node3D.new()
	_ship.name = "CapitalShip"
	add_child(_ship)
	var angle := deg_to_rad(SHIP_ANGLE)
	# Broadside to the field, nose a little down, as if holding station.
	_ship_home = Transform3D(Basis(Vector3.UP, -angle) * Basis(Vector3.RIGHT, -0.04),
			Vector3(cos(angle) * SHIP_RADIUS, SHIP_HEIGHT, sin(angle) * SHIP_RADIUS))
	_box(Vector3(150, 46, 600), Transform3D.IDENTITY, hull, _ship)
	_box(Vector3(104, 34, 230), Transform3D.IDENTITY.translated(Vector3(0, 36, -110)), hull, _ship)
	_box(Vector3(38, 58, 56), Transform3D.IDENTITY.translated(Vector3(28, 76, -160)), hull, _ship)
	_box(Vector3(230, 12, 110), Transform3D.IDENTITY.translated(Vector3(0, -8, 150)), hull, _ship)
	_box(Vector3(60, 22, 140), Transform3D.IDENTITY.translated(Vector3(0, -30, -60)), hull, _ship)
	for i in 5:
		_light("flash", 46.0, Vector3(-60 + i * 30, -4, 306), _ship)
		_light("halo", 10.0, Vector3(-72 + i * 36, -24, -220 + i * 90), _ship)


func _box(size: Vector3, xform: Transform3D, material: Material, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	node.mesh = mesh
	node.transform = xform
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## A tapered limb along Y: thick at the top, thin at the bottom.
func _taper(top: float, bottom: float, length: float, at: Vector3, material: Material, parent: Node3D) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = length
	mesh.radial_segments = 8
	mesh.material = material
	node.mesh = mesh
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


func _light(kind: String, size: float, at: Vector3, parent: Node3D) -> void:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = Look.trim(kind)
	node.mesh = quad
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	_lights.append(node)
