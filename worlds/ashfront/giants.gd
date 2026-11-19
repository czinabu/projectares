extends Node3D
## Ashfront's giants on the horizon (DESIGN.md "Scale you can see"): the
## Colossus, a war walker far taller than anything on the field, striding
## round past the rim, and a capital ship riding at anchor in the sky. View
## only and never in a server: the map adds one only where `Look` is on.
## Both are timed by the wall clock, so every player sees them in the same
## place, and a footfall is heard once its sound has had time to arrive.
## Once in a while the war's shared moment comes round on the same clock:
## a targeting line finds the Colossus, an orbital lance comes down on it
## out of the sky and it falls, lies burning a while, and is gone into the
## smoke before the next one walks out of it.

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

## The orbital lance: one strike every `LANCE_EVERY` seconds, `LANCE_AT`
## into the round; the targeting line shows `LANCE_CHARGE` before it, the
## column burns `LANCE_BURN`, the Colossus takes `FALL_TIME` to go down and
## lies until `WRECK_GONE` after the strike, fading into the smoke over its
## last `FADE_TIME`, and the next walks out of the smoke over as long.
const LANCE_EVERY := 1500.0
const LANCE_AT := 900.0
const LANCE_CHARGE := 10.0
const LANCE_BURN := 4.5
const FALL_TIME := 12.0
const WRECK_GONE := 560.0
const FADE_TIME := 40.0
## How high the lance starts (it comes down from orbit, past the far plane).
const LANCE_HEIGHT := 1600.0
const LANCE_WIDTH := 60.0

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
var _eye: Node3D
var _guide: MeshInstance3D
var _lance: MeshInstance3D
var _lance_glow: MeshInstance3D
var _impact: MeshInstance3D
var _fires: Array[Node3D] = []
## Every drawn part of the Colossus, faded together as it comes and goes.
var _colossus_parts: Array[GeometryInstance3D] = []
var _colossus_lights: Array[GeometryInstance3D] = []
var _shown_fade := -1.0
## Seconds since the last strike when last placed, to hear each blow once.
var _last_since := -INF


func _ready() -> void:
	name = "Giants"
	set_meta("walk_through", "scenery past the rim")
	var hull := Look.trim("distant")
	_build_colossus(hull)
	_build_ship(hull)
	for i in WING_SIZE.y:
		_wing.append(_build_dropship(hull))
	# Every part is far off and drawn as far as the sky goes: small parts
	# would otherwise be cut off close by (`Look._limit_draw_distance`).
	for part in find_children("*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).visibility_range_end = 2000.0
	for part in _colossus.find_children("*", "GeometryInstance3D", true, false):
		if part in _lights:
			_colossus_lights.append(part as GeometryInstance3D)
		else:
			_colossus_parts.append(part as GeometryInstance3D)
	_build_lance()
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


## Seconds since this round's lance struck at time `t`: negative while it
## is still to come, from `-LANCE_AT` (the round starting) up to
## `LANCE_EVERY - LANCE_AT`.
static func since_lance(t: float) -> float:
	return fposmod(t, LANCE_EVERY) - LANCE_AT


## How far down the Colossus is, `since` seconds after the strike (0
## standing, 1 lying): it holds a moment, then buckles faster and faster.
static func downed(since: float) -> float:
	if since <= 0.0:
		return 0.0
	var p := clampf((since - 1.0) / (FALL_TIME - 1.0), 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p) if p < 1.0 else 1.0


## How much of the Colossus shows at `since`: all of it, except while the
## wreck fades into the smoke and while the next one walks out of it.
static func shown(since: float) -> float:
	if since >= 0.0:
		return clampf((WRECK_GONE - since) / FADE_TIME, 0.0, 1.0)
	return clampf((since + LANCE_AT) / FADE_TIME, 0.0, 1.0)


## Where the Colossus is at time `t`: walking its round, or, once struck,
## where the lance caught it.
static func colossus_at(t: float) -> Transform3D:
	var since := since_lance(t)
	if since >= 0.0 and since < WRECK_GONE:
		return walker_at(t - since)
	return walker_at(t)


## A leg's place in its stride at time `t`, from 0 to 1.
static func stride(t: float, offset: float) -> float:
	return fposmod(t / STRIDE_TIME + offset, 1.0)


## How high a leg is lifted at stride phase `phase`: it swings forward in
## the air for half the stride and stands on the ground for the other half.
static func lift(phase: float) -> float:
	return maxf(0.0, sin(phase * TAU))


func _place(t: float) -> void:
	var since := since_lance(t)
	var down := downed(since)
	# Struck, it stops where it stands: its stride freezes at the blow.
	var pace := t - since if since >= 0.0 and since < WRECK_GONE else t
	var walk := colossus_at(t)
	walk.origin.y = floor_y + 2.5 * sin(pace / STRIDE_TIME * TAU * 2.0) * (1.0 - down)
	_colossus.transform = walk.scaled_local(Vector3.ONE * SCALE)
	# The hull rolls a little onto each planted pair and nods with the step;
	# going down it sinks onto its belly, rolling over and dropping its head.
	var step := pace / STRIDE_TIME * TAU
	var shake := 0.04 * sin(since * 9.0) * (1.0 - down) if since > 0.0 and since < FALL_TIME else 0.0
	_body.basis = Basis(Vector3.BACK, 0.03 * sin(step) + 0.32 * down + shake) * Basis(Vector3.RIGHT, 0.02 * sin(step * 2.0) + 0.2 * down)
	_body.position.y = lerpf(HIP_HEIGHT, 26.0, down)
	# The searchlight sweeps the ground ahead of it, and dies with it.
	_lamp.basis = Basis(Vector3.UP, 0.45 * sin(t * 0.23)) * Basis(Vector3.RIGHT, -0.85 + 0.12 * sin(t * 0.37))
	_lamp.visible = since < 0.0 or since >= WRECK_GONE
	_eye.visible = _lamp.visible
	for i in _hips.size():
		var phase := stride(pace, LEGS[i][1])
		var up := lift(phase) * (1.0 - down)
		var side := signf((LEGS[i][0] as Vector3).x)
		# Swing forward while lifted, push back while planted; going down
		# the legs splay out from under it and the shins fold flat.
		var sweep := 0.2 * cos(phase * TAU) * -signf((LEGS[i][0] as Vector3).z) * (1.0 - down)
		_hips[i].position.y = _body.position.y
		_hips[i].basis = Basis(Vector3.UP, sweep) * Basis(Vector3.BACK, side * (lerpf(THIGH_RAISE, 2.0, down) + 0.1 * up))
		_knees[i].basis = Basis(Vector3.BACK, -side * (lerpf(KNEE_FOLD, 0.55, down) - 0.3 * up))
		var lifted := up > 0.02
		# One of each pair is heard landing: a footfall every half stride.
		if i % 2 == 0 and _was_lifted[i] and not lifted and soundscape != null:
			soundscape.call("boom", _feet[i].global_position)
		_was_lifted[i] = lifted
	_strike(since)
	for i in _blinkers.size():
		_blinkers[i].visible = int(t * 1.4 + i * 0.5) % 2 == 0
	if _ship != null:
		_ship.transform = _ship_home * Transform3D(Basis(Vector3.UP, 0.04 * sin(t * 0.05)), Vector3(0, 4.0 * sin(t * 0.21), 0))
	_fly_wing(t)
	# Ash hides their lights with the rest of the skyline.
	var seen := 1.0 - Look.weather_cover
	for light in _lights:
		light.transparency = 1.0 - seen
	for light in _colossus_lights:
		light.transparency = 1.0 - seen * maxf(_shown_fade, 0.0)


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
	_eye = Node3D.new()
	head.add_child(_eye)
	var slit := _box(Vector3(22, 2.2, 1.0), Transform3D.IDENTITY.translated(Vector3(0, 3, 15.2)), Look.trim("beacon"), _eye)
	_lights.append(slit)
	_light("halo", 26.0, Vector3(0, 3, 17), _eye)
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
	# Fires that take hold where the lance struck, once it is down.
	for at: Vector3 in [Vector3(0, 40, -10), Vector3(-24, 26, 30), Vector3(20, 20, -44)]:
		var fire := Node3D.new()
		fire.position = at
		fire.visible = false
		_body.add_child(fire)
		_light("flash", 40.0, Vector3.ZERO, fire)
		if plume_maker.is_valid():
			var smoke: Node3D = plume_maker.call(Vector3.ZERO, 5.0)
			smoke.position = Vector3(0, 6, 0)
			fire.add_child(smoke)
		_fires.append(fire)
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


func _build_lance() -> void:
	# The targeting line: a thin red thread down out of the sky.
	_guide = _column(1.2, Look.trim("beacon"))
	_lance = _column(LANCE_WIDTH * 0.5, Look.trim("lance"))
	# A wider, fainter sheath round it, so it reads as light, not a rod.
	_lance_glow = _column(LANCE_WIDTH * 1.4, Look.trim("lance"))
	_impact = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.material = Look.trim("flash")
	_impact.mesh = quad
	_impact.visible = false
	_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_impact.visibility_range_end = 3000.0
	add_child(_impact)


func _column(radius: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = LANCE_HEIGHT
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.radial_segments = 16
	mesh.material = material
	node.mesh = mesh
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 3000.0
	add_child(node)
	return node


## The war's shared moment, `since` seconds after (or before) the strike:
## the line finds its mark, the lance comes down, the Colossus burns.
func _strike(since: float) -> void:
	var seen := 1.0 - Look.weather_cover
	var mark := _body.global_position + Vector3(0, 20, 0)
	var column := Transform3D(Basis.IDENTITY, mark + Vector3(0, LANCE_HEIGHT * 0.5, 0))
	# Locking on: the line flickers, then holds steady just before the blow.
	_guide.visible = since >= -LANCE_CHARGE and since < 0.4
	if _guide.visible:
		_guide.global_transform = column
		var steady := since > -2.5 or int(since * 7.0) % 2 == 0
		_guide.transparency = 1.0 - (0.9 if steady else 0.25) * seen
	# The lance: full width at once, then thinning out as it burns.
	_lance.visible = since >= 0.0 and since < LANCE_BURN
	if _lance.visible:
		var p := since / LANCE_BURN
		var width := 1.0 - p * p
		_lance.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(width, 1.0, width)), column.origin)
		_lance.transparency = 1.0 - (1.0 - p) * seen
	_lance_glow.visible = _lance.visible
	if _lance_glow.visible:
		var p := since / LANCE_BURN
		_lance_glow.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * lerpf(1.0, 1.6, p) * Vector3(1, 0, 1) + Vector3.UP), column.origin)
		_lance_glow.transparency = 1.0 - 0.22 * (1.0 - p) * seen
	_impact.visible = since >= 0.0 and since < 3.0
	if _impact.visible:
		_impact.global_position = mark
		_impact.scale = Vector3.ONE * lerpf(500.0, 900.0, since / 3.0)
		_impact.transparency = 1.0 - (1.0 - since / 3.0) * seen
	for fire in _fires:
		fire.visible = since >= 0.5 and since < WRECK_GONE
	# The blow and the crash of it landing, each heard once.
	if soundscape != null and is_finite(_last_since):
		if _last_since < 0.0 and since >= 0.0:
			for i in 3:
				soundscape.call("boom", mark + Vector3(i * 30.0, 0, 0))
		if _last_since < FALL_TIME and since >= FALL_TIME:
			soundscape.call("boom", _body.global_position)
			soundscape.call("boom", _feet[0].global_position)
	_last_since = since
	# Coming and going, it fades with the smoke rather than popping.
	var fade := shown(since)
	if not is_equal_approx(fade, _shown_fade):
		_shown_fade = fade
		_colossus.visible = fade > 0.0
		for part in _colossus_parts:
			part.transparency = 1.0 - fade
