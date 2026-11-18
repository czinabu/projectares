extends Node3D
## Ashfront's giants on the horizon (DESIGN.md "Scale you can see"): the
## Colossus, a war walker far taller than anything on the field, striding
## round past the rim, and a capital ship riding at anchor in the sky. View
## only and never in a server: the map adds one only where `Look` is on.
## Both are timed by the wall clock, so every player sees them in the same
## place, and a footfall is heard once its sound has had time to arrive.

## How far out the Colossus walks, and how high its hips ride (before `SCALE`).
const WALK_RADIUS := 640.0
const HIP_HEIGHT := 129.0
## Its pace (m/s) along its round and one stride's length in time.
const WALK_SPEED := 4.0
const STRIDE_TIME := 13.0
## The walker is built at this size and then scaled up as a whole.
const SCALE := 1.7
## Four legs, each a long thigh up and out and a shin down to the ground.
const THIGH := 72.0
const SHIN := 170.0
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

## Where the ground under the giants is (the skyline's floor).
var floor_y := 38.0
var soundscape: Node = null

var _colossus: Node3D
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _was_lifted: Array[bool] = []
var _ship: Node3D
var _ship_home := Transform3D.IDENTITY
var _lights: Array[GeometryInstance3D] = []


func _ready() -> void:
	name = "Giants"
	var hull := Look.trim("distant")
	_build_colossus(hull)
	_build_ship(hull)
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
	for i in _hips.size():
		var phase := stride(t, LEGS[i][1])
		var up := lift(phase)
		var side := signf((LEGS[i][0] as Vector3).x)
		# Swing forward while lifted, push back while planted.
		var sweep := 0.22 * cos(phase * TAU) * -signf((LEGS[i][0] as Vector3).z)
		_hips[i].basis = Basis(Vector3.UP, sweep) * Basis(Vector3.BACK, side * (2.05 + 0.1 * up))
		_knees[i].basis = Basis(Vector3.BACK, -side * (1.75 - 0.3 * up))
		var lifted := up > 0.02
		# One of each pair is heard landing: a footfall every half stride.
		if i % 2 == 0 and _was_lifted[i] and not lifted and soundscape != null:
			soundscape.call("boom", _feet[i].global_position)
		_was_lifted[i] = lifted
	if _ship != null:
		_ship.transform = _ship_home * Transform3D(Basis(Vector3.UP, 0.04 * sin(t * 0.05)), Vector3(0, 4.0 * sin(t * 0.21), 0))
	# Ash hides their lights with the rest of the skyline.
	var seen := 1.0 - Look.weather_cover
	for light in _lights:
		light.transparency = 1.0 - seen


func _build_colossus(hull: Material) -> void:
	_colossus = Node3D.new()
	_colossus.name = "Colossus"
	add_child(_colossus)
	var body := Node3D.new()
	body.position = Vector3(0, HIP_HEIGHT, 0)
	_colossus.add_child(body)
	# A long armoured hull, a raised deck with a gun on it and a low head.
	_box(Vector3(78, 30, 140), Transform3D(Basis(Vector3.RIGHT, -0.05), Vector3(0, 14, 0)), hull, body)
	_box(Vector3(48, 20, 62), Transform3D(Basis.IDENTITY, Vector3(0, 38, 22)), hull, body)
	_box(Vector3(30, 16, 34), Transform3D(Basis.IDENTITY, Vector3(0, 8, 84)), hull, body)
	_box(Vector3(5, 5, 80), Transform3D(Basis.IDENTITY, Vector3(0, 44, 80)), hull, body)
	_box(Vector3(2.5, 46, 2.5), Transform3D(Basis.IDENTITY, Vector3(12, 70, 10)), hull, body)
	_light("halo", 30.0, Vector3(0, 8, 102), body)
	for i in 6:
		_light("flash", 7.0, Vector3(-40 + (i % 2) * 80, 30, -46 + (i / 2) * 46), body)
	_light("halo", 6.0, Vector3(12, 94, 10), body)
	for leg: Array in LEGS:
		var hip := Node3D.new()
		hip.position = body.position + (leg[0] as Vector3)
		_colossus.add_child(hip)
		_box(Vector3(9, THIGH, 11), Transform3D(Basis.IDENTITY, Vector3(0, -THIGH * 0.5, 0)), hull, hip)
		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		_box(Vector3(13, 15, 13), Transform3D.IDENTITY, hull, knee)
		_box(Vector3(6.5, SHIN, 8), Transform3D(Basis.IDENTITY, Vector3(0, -SHIN * 0.5, 0)), hull, knee)
		var foot := Node3D.new()
		foot.position = Vector3(0, -SHIN, 0)
		knee.add_child(foot)
		_box(Vector3(20, 6, 26), Transform3D.IDENTITY, hull, foot)
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
