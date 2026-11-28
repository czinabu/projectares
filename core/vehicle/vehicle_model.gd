extends RefCounted
## The bodies of vehicles, built in code like the rest of the greybox gear,
## in the sci-fi style the rigs, helmets and armor wear: bevelled shells cut
## into panels over a dark frame (the gaps between them are the panel
## lines), lit seams and glowing thrusters. Plain materials only, so a
## server and the watch's toys can build them; `Look` weathers them.
##
## Every vehicle is one silhouette you can tell from far off. A bike or a
## hoverbike can wear one of several bodies (`BODIES`), picked by the item's
## "body" stat (`Vehicle.body`), so a new bike is data, not code:
##   bike       scrambler  a rat dirt bike: a bare tube frame, knobbly tyres,
##                         a finned power drum, a number board with a caged
##                         lamp, a long flat bench, a high pipe, a jerrycan.
##                         The Scrapper.
##              street     a low street bike with a beaked fairing and a
##                         kicked-up tail blade, patched with scrap plates.
##              fighter    a naked streetfighter whose glowing finned power
##                         block is the engine, with stacked insect lamps and
##                         a fat rear tyre on a one-sided swing arm.
##              junker     a café racer welded from salvage: a drum tank, a
##                         bullet nose, stacked cells, twin low pipes.
##   hoverbike  ducted     one hull over two big open ducted fans whose rotors
##                         spin ("Rotor*"), a tall rudder over the rear one.
##                         The Raider.
##              pontoon    a long dart of a hull between two thruster
##                         pontoons, each with a fin.
##              manta      a wide flat lifting wing with the seats on a raised
##                         spine and fins at its tips.
##              lancer     a needle nose over a slung lift pod, two engine
##                         nacelles canted out behind.
##   rover      a wide, low wedge on four wheels in armored pods, open-topped
##              for four (two up front, two raised behind) under a roll cage
##              with a light bar on it.
##   mech       a cockpit pod on two bird-like legs (knees forward, heels
##              back), cannons on its shoulders and its power unit glowing on
##              its back.
##   jet        a needle-nosed fighter with a clear bubble canopy, swept
##              delta wings, twin canted fins and two glowing engines.
##   airship    a world event's armoured airship: a long iron hull with a
##              ram, a gondola under it, a bridge tower on its back and
##              four tail fins. Its weak spots are built at its seats (each
##              seat's "piece": "pod", an engine pod on an outrigger;
##              "plate", an armoured spine plate over a glowing core;
##              "turret", a twin-barrelled turret), as "Part<n>", with a
##              wrecked one, "Broken<n>", hidden beside it.
##
## Only the look changes with the model: the collision shapes, the seat,
## grips and pegs (`Vehicle.seat_point`, `grip_points`, `peg_points`, the
## pillion's) are the vehicle's own, and each model is built round them.
## The vehicle faces -Z; y = 0 is the ground it stands on (a hover's cushion
## lifts the whole model by `hover_height`).
##
## Lights: thrusters, engines, hub rings and seams are material overrides,
## which `Look` leaves as they are. A lamp (a surface material that glows)
## is where `Look` hangs a headlight beam, so each model has one or two.
## Named children the vehicle uses: "Thruster*" (a hover's lift discs, which
## burn brighter with speed), "Rotor*" (a fan's rotor, which spins with
## speed) and "LegL"/"LegR" (a walker's legs, swung at
## the hip, `Vehicle.LEG_HIP` up).

const Self := preload("res://core/vehicle/vehicle_model.gd")

## Thrusters, engines and hub rings: the same energy as the rigs' jets.
const ENERGY := Color(0.4, 0.85, 1.0)
const TRIM := Color(0.1, 0.1, 0.11)
const STEEL := Color(0.46, 0.47, 0.5)
const TAIL := Color(1.0, 0.16, 0.08)

## How grimy `Look` paints each model (0 clean, 1 filthy): the Scrapper is
## made from scrap; the rest are kept up.
const WEAR := {"bike": 0.75}

## The bodies a bike or a hoverbike can wear (`Vehicle.body`); the first is
## the one it gets when its item names none, or one this list lacks.
const BODIES := {
	"bike": ["scrambler", "street", "fighter", "junker"],
	"hoverbike": ["ducted", "pontoon", "manta", "lancer"],
}
const WEAR_DEFAULT := 0.35

## The width of a panel line, and how deep the frame under the panels sits.
var gap := 0.018
var groove := 0.012

var v  # the Vehicle (untyped: its script has no class_name)
var paint: StandardMaterial3D
var trim: StandardMaterial3D
var steel: StandardMaterial3D
## Lit seams, in the item's rarity color (the same rule as a blade's
## energy edge): an override, so `Look` leaves it alone.
var seam: StandardMaterial3D
## Thrusters and engines: an override too.
var energy: StandardMaterial3D
var tail: StandardMaterial3D
## A headlight: a surface material that glows, so `Look` hangs a beam on it.
var lamp: StandardMaterial3D
var glass: StandardMaterial3D


## The body for `vehicle` (a `Vehicle`), by its `model`.
static func build(vehicle) -> Node3D:
	var maker := Self.new()
	maker._setup(vehicle)
	var root: Node3D
	match vehicle.model:
		"rover":
			root = maker._rover()
		"mech":
			root = maker._mech()
		"jet":
			root = maker._jet()
		"airship":
			root = maker._airship()
		"bike", "hoverbike":
			root = maker.call("_" + body_of(vehicle.model, vehicle.body))
			root.set_meta("body", body_of(vehicle.model, vehicle.body))
		_:
			root = maker.call("_" + body_of("bike", ""))
			root.set_meta("body", body_of("bike", ""))
	root.name = "Model"
	root.set_meta("wear", WEAR.get(vehicle.model, WEAR_DEFAULT))
	return root


## The body `model` wears for the item's `body`: that one if `model` has
## it, else its first.
static func body_of(model: String, body: String) -> String:
	var bodies: Array = BODIES.get(model, [])
	if bodies.is_empty():
		return ""
	return body if body in bodies else str(bodies[0])


func _setup(vehicle) -> void:
	v = vehicle
	paint = _mat(v.body_color, 0.55, 0.45)
	trim = _mat(TRIM, 0.7, 0.3)
	steel = _mat(STEEL, 0.4, 0.8)
	var rarity := ItemDB.item_rarity(v.item_id) if v.item_id != "" else ItemDB.Rarity.UNCOMMON
	var accent: Color = ItemDB.RARITY_COLORS[rarity]
	seam = _glow(accent, 2.2)
	energy = _glow(ENERGY, 2.5)
	tail = _glow(TAIL, 2.0)
	lamp = _mat(Color(1.0, 0.92, 0.7), 0.3, 0.0)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.88, 0.6)
	lamp.emission_energy_multiplier = 2.0
	glass = StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.78, 0.9, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.metallic = 0.4
	glass.roughness = 0.05


# --- Street (the first Scrapper) -------------------------------------------------

## A low street bike with a beaked fairing and a kicked-up tail blade.
func _street() -> Node3D:
	var root := Node3D.new()
	var dim := _glow(ENERGY, 1.4)  # a scrap build's rings run dim
	# The fork, the front wheel and its beak, and the bars turn together
	# about the steering head, raked along the fork.
	var head := Vector3(0, 1.02, -0.55)
	var fork := _pivot(root, "Steer", head, head - Vector3(0, 0.36, -0.75), 1.0, true)
	var front := _wheel_set(fork, Vector3(0, 0.36, -0.75) - head, 0.36, 0.17, dim, 0.0)
	front.name = "WheelFront"
	_wheel_set(root, Vector3(0, 0.36, 0.75), 0.36, 0.17, dim, 0.0)
	# Fenders: a beak over the front wheel, a hugger over the rear.
	_into(fork, _extrude(_arc(Vector2(-0.75, 0.36), 0.41, 0.455, 0.28 * PI, 0.72 * PI), 0.2, "x", paint))
	_add(root, _extrude(_arc(Vector2(0.75, 0.36), 0.41, 0.45, 0.45 * PI, 0.82 * PI), 0.19, "x", trim))
	# The shell, one side profile from the beak to the tail blade, cut into
	# panels: fairing, tank, seat flanks and tail.
	var shell := PackedVector2Array([Vector2(-0.97, 0.92), Vector2(-0.7, 1.02), Vector2(-0.48, 1.12),
			Vector2(-0.3, 1.06), Vector2(-0.05, 1.02), Vector2(0.1, 0.93), Vector2(0.55, 0.93),
			Vector2(0.8, 1.0), Vector2(1.1, 1.15), Vector2(1.02, 1.05), Vector2(0.62, 0.84),
			Vector2(0.3, 0.7), Vector2(0.12, 0.5), Vector2(-0.3, 0.5), Vector2(-0.42, 0.78),
			Vector2(-0.7, 0.85), Vector2(-0.97, 0.88)])
	_paneled(root, shell, 0.32, 0.0, paint, [-0.47, -0.02, 0.58], 0.012)
	# The seat, dark and padded, sunk into the shell.
	_add(root, _extrude(RoundedPath.of([Vector2(0.03, 0.92), Vector2(0.07, 0.99), Vector2(0.5, 0.99),
			Vector2(0.62, 0.95), Vector2(0.62, 0.92)], 0.02), 0.28, "x", trim))
	# The power cell glows through a port in each flank, and a lit seam runs
	# from it to the fairing.
	for side: float in [-1.0, 1.0]:
		root.add_child(_cyl(0.11, 0.11, 0.008, Vector3(side * 0.162, 0.66, -0.1), trim, Vector3(0, 0, PI / 2.0), 20))
		var port := MeshInstance3D.new()
		var port_ring := TorusMesh.new()
		port_ring.inner_radius = 0.06
		port_ring.outer_radius = 0.075
		port.mesh = port_ring
		port.material_override = dim
		port.rotation.z = PI / 2.0
		port.position = Vector3(side * 0.166, 0.66, -0.1)
		root.add_child(port)
		root.add_child(_cyl(0.03, 0.03, 0.012, Vector3(side * 0.166, 0.66, -0.1), steel, Vector3(0, 0, PI / 2.0), 12))
		root.add_child(_strut(Vector3(side * 0.163, 0.82, -0.66), Vector3(side * 0.163, 0.8, -0.24), Vector2(0.006, 0.022), seam))
		# Fork legs down to the front hub, and the swing arm back to the rear.
		_into(fork, _strut(Vector3(side * 0.1, 1.02, -0.55), Vector3(side * 0.1, 0.36, -0.75), Vector2(0.05, 0.05), steel))
		root.add_child(_strut(Vector3(side * 0.12, 0.56, 0.12), Vector3(side * 0.12, 0.36, 0.75), Vector2(0.05, 0.08), trim))
		# Foot pegs on stubs out of the frame.
		root.add_child(_box(Vector3(0.15, 0.035, 0.06), Vector3(side * 0.21, 0.42, 0.04), steel))
		root.add_child(_strut(Vector3(side * 0.12, 0.5, 0.1), Vector3(side * 0.16, 0.43, 0.04), Vector2(0.03, 0.03), trim))
		# Grips on the clip-on bar.
		_into(fork, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.24, 1.2, -0.3), trim))
	_into(fork, _strut(Vector3(-0.27, 1.2, -0.3), Vector3(0.27, 1.2, -0.3), Vector2(0.032, 0.032), steel))
	_into(fork, _strut(Vector3(0, 1.1, -0.45), Vector3(0, 1.19, -0.32), Vector2(0.06, 0.05), trim))
	# A short raked screen over the fairing.
	var screen := _strut(Vector3(0, 1.1, -0.53), Vector3(0, 1.25, -0.4), Vector2(0.26, 0.012), glass)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)
	# Scrap: mismatched patch plates riveted on, and a pipe off the cell.
	_patch(root, Vector3(-0.168, 0.94, -0.26), Vector2(0.22, 0.1), -0.12, -1.0)
	_patch(root, Vector3(0.168, 0.98, 0.84), Vector2(0.2, 0.08), 0.35, 1.0)
	_patch(root, Vector3(0.168, 0.6, -0.12), Vector2(0.12, 0.1), 0.08, 1.0)
	root.add_child(_cyl(0.035, 0.04, 0.5, Vector3(0.15, 0.6, 0.48), steel, Vector3(PI / 2.0 + 0.2, 0, 0)))
	root.add_child(_cyl(0.042, 0.042, 0.02, Vector3(0.15, 0.55, 0.73), dim, Vector3(PI / 2.0 + 0.2, 0, 0)))
	# The beak's headlight and the tail blade's lamp.
	root.add_child(_box(Vector3(0.15, 0.03, 0.03), Vector3(0, 0.905, -0.955), lamp))
	root.add_child(_strut(Vector3(-0.07, 1.05, 1.04), Vector3(0.07, 1.05, 1.04), Vector2(0.025, 0.02), tail))
	return root


## A scrap plate riveted on a flank (`side`: -1 left, 1 right), turned a
## little off square.
func _patch(root: Node3D, at: Vector3, size: Vector2, turn: float, side: float) -> void:
	var plate := _box(Vector3(0.008, size.y, size.x), at + Vector3(side * 0.004, 0, 0), steel)
	plate.rotation.x = turn
	root.add_child(plate)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var off := Basis(Vector3.RIGHT, turn) * Vector3(0, corner.y * size.y * 0.35, corner.x * size.x * 0.4)
		root.add_child(_cyl(0.008, 0.008, 0.008, at + off + Vector3(side * 0.01, 0, 0), trim, Vector3(0, 0, PI / 2.0), 6))


# --- Pontoon (the first Raider) ---------------------------------------------------

## A long dart of a hull between two thruster pontoons, each with a fin.
## No cylinder on a hover body may lie on its side (a hover has no wheels,
## and a test looks for them): rings round the pontoons are turned about X.
func _pontoon() -> Node3D:
	var root := Node3D.new()
	var b: float = v.hover_height
	for side: float in [-1.0, 1.0]:
		var x := side * 0.42
		# A pontoon: a long rounded pod, banded, with a lift thruster under
		# each end and a fin off its tail.
		root.add_child(_capsule(0.11, 1.9, Vector3(x, b + 0.13, -0.02), paint, Vector3(PI / 2.0, 0, 0)))
		for z: float in [-0.5, 0.42]:
			root.add_child(_cyl(0.114, 0.114, 0.03, Vector3(x, b + 0.13, z), trim, Vector3(PI / 2.0, 0, 0), 16))
		root.add_child(_strut(Vector3(x + side * 0.105, b + 0.15, -0.75), Vector3(x + side * 0.105, b + 0.15, 0.7), Vector2(0.008, 0.02), seam))
		for z: float in [-0.62, 0.62]:
			root.add_child(_cyl(0.15, 0.15, 0.06, Vector3(x, b + 0.06, z), trim, Vector3.ZERO, 20))
			var disc := _cyl(0.12, 0.12, 0.02, Vector3(x, b + 0.015, z), energy, Vector3.ZERO, 20)
			disc.name = "Thruster%d" % root.get_child_count()
			root.add_child(disc)
		# The fin is a rudder: it swings with the steering about its root.
		var rudder := _pivot(root, "Fin%d" % (0 if side < 0.0 else 1), Vector3(x, b + 0.2, 0.6),
				Basis(Vector3.FORWARD, side * 0.25) * Vector3.UP, -0.5)
		var fin := _extrude(RoundedPath.of([Vector2(0.55, b + 0.2), Vector2(0.86, b + 0.56),
				Vector2(1.0, b + 0.56), Vector2(0.94, b + 0.18)], 0.02), 0.03, "x", paint)
		fin.position = Vector3(x, 0, 0)
		fin.rotation.z = -side * 0.25
		_into(rudder, fin)
		# Foot pads on the pontoons: the rider's, and the pillion's on a step.
		root.add_child(_box(Vector3(0.12, 0.03, 0.14), Vector3(side * 0.37, b + 0.255, -0.04), trim))
		root.add_child(_box(Vector3(0.1, 0.09, 0.1), Vector3(side * 0.37, b + 0.28, 0.5), trim))
		# Grab rails for the pillion, on posts off the hull.
		root.add_child(_strut(Vector3(side * 0.23, b + 0.66, 0.5), Vector3(side * 0.23, b + 0.66, 0.86), Vector2(0.035, 0.035), steel))
		root.add_child(_strut(Vector3(side * 0.23, b + 0.66, 0.86), Vector3(side * 0.2, b + 0.56, 0.98), Vector2(0.035, 0.035), steel))
		# A lit seam down the hull's flank.
		root.add_child(_strut(Vector3(side * 0.203, b + 0.36, -1.15), Vector3(side * 0.203, b + 0.32, 0.4), Vector2(0.006, 0.022), seam))
	# The arms that carry the pontoons: two swept plates under the hull.
	for z: Vector2 in [Vector2(-0.82, -0.5), Vector2(0.12, 0.42)]:
		var arm := _extrude(PackedVector2Array([Vector2(-0.42, z.x + 0.08), Vector2(0.42, z.x + 0.08),
				Vector2(0.42, z.y + 0.08), Vector2(-0.42, z.y + 0.08)]), 0.05, "y", trim)
		arm.position.y = b + 0.2
		root.add_child(arm)
	# The hull: a long dart, panelled, with the two seats stepped into it.
	var hull := PackedVector2Array([Vector2(-1.48, b + 0.3), Vector2(-1.1, b + 0.46), Vector2(-0.66, b + 0.6),
			Vector2(-0.28, b + 0.62), Vector2(-0.08, b + 0.5), Vector2(0.48, b + 0.5), Vector2(0.56, b + 0.58),
			Vector2(1.0, b + 0.6), Vector2(1.26, b + 0.5), Vector2(1.3, b + 0.34), Vector2(1.0, b + 0.2),
			Vector2(-0.9, b + 0.18), Vector2(-1.3, b + 0.22)])
	_paneled(root, hull, 0.4, 0.0, paint, [-0.76, -0.12, 0.52], 0.014)
	_add(root, _extrude(RoundedPath.of([Vector2(-0.07, b + 0.5), Vector2(-0.04, b + 0.58), Vector2(0.42, b + 0.58),
			Vector2(0.48, b + 0.5)], 0.02), 0.32, "x", trim))  # rider's seat
	_add(root, _extrude(RoundedPath.of([Vector2(0.57, b + 0.58), Vector2(0.6, b + 0.66), Vector2(0.94, b + 0.66),
			Vector2(1.0, b + 0.6)], 0.02), 0.3, "x", trim))  # pillion seat
	# The tail's thruster, and the nose's lamp under a dark visor line.
	var exhaust := _box(Vector3(0.24, 0.1, 0.02), Vector3(0, b + 0.4, 1.29), energy)
	exhaust.name = "Exhaust"
	exhaust.rotation.x = -0.25
	root.add_child(exhaust)
	root.add_child(_box(Vector3(0.14, 0.03, 0.03), Vector3(0, b + 0.33, -1.38), lamp))
	root.add_child(_strut(Vector3(-0.2, b + 0.48, -1.05), Vector3(0.2, b + 0.48, -1.05), Vector2(0.02, 0.012), trim))
	# Bars and screen.
	var screen := _strut(Vector3(0, b + 0.6, -0.66), Vector3(0, b + 0.86, -0.52), Vector2(0.34, 0.012), glass)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)
	# The bars turn on their stem.
	var stem := Vector3(0, b + 0.6, -0.5)
	var bars := _pivot(root, "Steer", stem, Vector3(0, 1.3, -0.43) - stem, 1.0, true)
	_into(bars, _strut(stem, Vector3(0, 1.3, -0.43), Vector2(0.06, 0.05), trim))
	_into(bars, _strut(Vector3(-0.34, 1.3, -0.42), Vector3(0.34, 1.3, -0.42), Vector2(0.032, 0.032), steel))
	for side: float in [-1.0, 1.0]:
		_into(bars, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.3, 1.3, -0.42), trim))  # grip
	return root


func _ring(at: Vector3, inner: float, outer: float, mat: Material, rot := Vector3.ZERO, rings := 24) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = 8
	node.mesh = t
	node.position = at
	node.rotation = rot
	_paint(node, mat)
	return node


## Knobbly tread on a wheel from `_wheel_set`: its tyre is turned down and
## `count` lugs stand round it out to `radius`, on the part that spins.
func _lugs(wheel: Node3D, radius: float, width: float, count: int) -> void:
	var tyre := (wheel.get_child(0) as MeshInstance3D).mesh as CylinderMesh
	tyre.top_radius = radius - 0.03
	tyre.bottom_radius = radius - 0.03
	var spin := wheel.get_node("Spin")
	for i in count:
		var a := TAU * i / count
		var lug := _box(Vector3(width + 0.02, 0.05, 0.07), Vector3(0, cos(a), sin(a)) * (radius - 0.03), trim)
		lug.rotation.x = -a
		spin.add_child(lug)


# --- Scrapper A: the Scrambler --------------------------------------------------
## A rat dirt bike: bare tube trellis, knobbly tyres, a tall beak of a
## mudguard, a number board with a caged round lamp, a flat bench, a high
## pipe, a jerrycan strapped on.
func _scrambler() -> Node3D:
	var root := Node3D.new()
	var dim := _glow(ENERGY, 1.4)
	var head := Vector3(0, 1.04, -0.52)
	var fork := _pivot(root, "Steer", head, head - Vector3(0, 0.38, -0.76), 1.0, true)
	var front := _wheel_set(fork, Vector3(0, 0.38, -0.76) - head, 0.38, 0.16, dim, 0.0)
	front.name = "WheelFront"
	_lugs(front, 0.38, 0.16, 16)
	var rear := _wheel_set(root, Vector3(0, 0.38, 0.75), 0.38, 0.2, dim, 0.0)
	_lugs(rear, 0.38, 0.2, 16)
	# The frame: a bare steel trellis from the head to the swing-arm pivot
	# and back up under the seat.
	var pivot := Vector3(0, 0.5, 0.12)
	for side: float in [-1.0, 1.0]:
		var s := Vector3(side * 0.1, 0, 0)
		for pair: Array in [[head + Vector3(0, 0.02, 0.05), Vector3(0, 0.95, 0.05)], [head + Vector3(0, -0.12, 0.03), pivot + Vector3(0, 0.05, 0)],
				[Vector3(0, 0.95, 0.05), pivot + Vector3(0, 0.05, 0)], [Vector3(0, 0.95, 0.05), Vector3(0, 0.95, 0.86)],
				[pivot + Vector3(0, 0.05, 0), Vector3(0, 0.95, 0.62)], [head + Vector3(0, -0.12, 0.03), Vector3(0, 0.45, -0.2)],
				[Vector3(0, 0.45, -0.2), pivot]]:
			root.add_child(_strut(pair[0] + s, pair[1] + s, Vector2(0.035, 0.035), steel))
		# A box-section swing arm.
		root.add_child(_strut(pivot + s * 1.2, Vector3(side * 0.13, 0.38, 0.75), Vector2(0.04, 0.07), trim))
		# Fork legs with gaiters.
		_into(fork, _strut(Vector3(side * 0.1, 1.06, -0.52), Vector3(side * 0.1, 0.38, -0.76), Vector2(0.045, 0.045), steel))
		_into(fork, _strut(Vector3(side * 0.1, 0.72, -0.64), Vector3(side * 0.1, 0.5, -0.72), Vector2(0.07, 0.07), trim))
		# Pegs.
		root.add_child(_box(Vector3(0.16, 0.035, 0.07), Vector3(side * 0.21, 0.43, 0.04), steel))
		# Shock.
		root.add_child(_strut(Vector3(side * 0.12, 0.9, 0.5), Vector3(side * 0.13, 0.48, 0.66), Vector2(0.05, 0.05), dim))
	# The power cell: a finned drum across the frame, glowing between fins.
	root.add_child(_cyl(0.15, 0.15, 0.3, Vector3(0, 0.6, -0.1), trim, Vector3(0, 0, PI / 2.0), 16))
	for i in 5:
		root.add_child(_cyl(0.17, 0.17, 0.018, Vector3(-0.12 + i * 0.06, 0.6, -0.1), steel, Vector3(0, 0, PI / 2.0), 16))
	root.add_child(_cyl(0.12, 0.12, 0.32, Vector3(0, 0.6, -0.1), dim, Vector3(0, 0, PI / 2.0), 12))
	# A small dented tank and the long flat bench.
	_paneled(root, RoundedPath.of([Vector2(-0.42, 0.96), Vector2(-0.3, 1.12), Vector2(0.0, 1.12), Vector2(0.08, 1.0),
			Vector2(0.02, 0.88), Vector2(-0.36, 0.86)], 0.04), 0.3, 0.0, paint, [-0.18], 0.012)
	_add(root, _extrude(RoundedPath.of([Vector2(0.0, 0.95), Vector2(0.05, 1.03), Vector2(0.84, 1.03), Vector2(0.9, 0.98),
			Vector2(0.86, 0.95)], 0.02), 0.26, "x", trim))
	# Side number plates under the bench.
	for side: float in [-1.0, 1.0]:
		var plate := _extrude(PackedVector2Array([Vector2(0.3, 0.92), Vector2(0.75, 0.94), Vector2(0.6, 0.66), Vector2(0.34, 0.7)]), 0.012, "x", paint)
		plate.position.x = side * 0.15
		root.add_child(plate)
	# A tall beak of a mudguard on the fork, and a short tail guard behind.
	_into(fork, _extrude(PackedVector2Array([Vector2(-1.18, 0.88), Vector2(-0.9, 0.86), Vector2(-0.62, 0.84),
			Vector2(-0.48, 0.86), Vector2(-0.62, 0.9), Vector2(-0.95, 0.93)]), 0.2, "x", paint))
	_add(root, _extrude(PackedVector2Array([Vector2(0.84, 0.97), Vector2(1.08, 1.1), Vector2(1.1, 1.06),
			Vector2(0.86, 0.92)]), 0.18, "x", paint))
	root.add_child(_box(Vector3(0.1, 0.035, 0.035), Vector3(0, 1.05, 1.06), tail))
	# The number board on the fork with a round lamp in a wire cage.
	_into(fork, _strut(Vector3(0, 1.08, -0.6), Vector3(0, 0.82, -0.68), Vector2(0.3, 0.014), paint))
	_into(fork, _cyl(0.075, 0.075, 0.05, Vector3(0, 0.96, -0.66), lamp, Vector3(PI / 2.0 - 0.3, 0, 0), 16))
	for k in 3:
		_into(fork, _strut(Vector3(-0.08 + k * 0.08, 1.04, -0.69), Vector3(-0.08 + k * 0.08, 0.88, -0.74), Vector2(0.01, 0.01), steel))
	# Wide bars on a tall clamp, with a cross brace.
	_into(fork, _strut(Vector3(0, 1.08, -0.5), Vector3(0, 1.18, -0.34), Vector2(0.05, 0.05), trim))
	_into(fork, _strut(Vector3(-0.3, 1.2, -0.3), Vector3(0.3, 1.2, -0.3), Vector2(0.03, 0.03), steel))
	_into(fork, _strut(Vector3(-0.14, 1.25, -0.31), Vector3(0.14, 1.25, -0.31), Vector2(0.025, 0.025), steel))
	for side: float in [-1.0, 1.0]:
		_into(fork, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.24, 1.2, -0.3), trim))
	# The high pipe on the right, up past the bench, with a glowing can.
	root.add_child(_strut(Vector3(0.12, 0.55, -0.2), Vector3(0.2, 0.62, 0.2), Vector2(0.06, 0.06), steel))
	root.add_child(_strut(Vector3(0.2, 0.62, 0.2), Vector3(0.21, 0.86, 0.5), Vector2(0.06, 0.06), steel))
	root.add_child(_cyl(0.065, 0.065, 0.42, Vector3(0.22, 0.92, 0.72), trim, Vector3(PI / 2.0 - 0.25, 0, 0), 12))
	root.add_child(_cyl(0.045, 0.045, 0.02, Vector3(0.22, 0.97, 0.93), dim, Vector3(PI / 2.0 - 0.25, 0, 0), 12))
	# A jerrycan strapped on the left of the tail.
	root.add_child(_box(Vector3(0.1, 0.24, 0.3), Vector3(-0.22, 0.8, 0.58), _mat(Color(0.32, 0.36, 0.22), 0.8, 0.2)))
	root.add_child(_box(Vector3(0.115, 0.03, 0.31), Vector3(-0.22, 0.86, 0.58), trim))
	_patch(root, Vector3(-0.152, 1.04, -0.2), Vector2(0.16, 0.08), 0.2, -1.0)
	return root


# --- Scrapper B: the Streetfighter ---------------------------------------------
## Naked and mean: the power cell is the engine, a big finned block between
## the wheels glowing through its fins; sharp shrouds flare off a muscular
## tank, an insect face of two stacked lamps, a stub tail, a fat rear tyre on
## a one-sided swing arm.
func _fighter() -> Node3D:
	var root := Node3D.new()
	var dim := _glow(ENERGY, 1.8)
	var head := Vector3(0, 1.0, -0.5)
	var fork := _pivot(root, "Steer", head, head - Vector3(0, 0.35, -0.76), 1.0, true)
	var front := _wheel_set(fork, Vector3(0, 0.35, -0.76) - head, 0.35, 0.16, dim, 0.0)
	front.name = "WheelFront"
	_wheel_set(root, Vector3(0, 0.36, 0.75), 0.36, 0.27, dim, 0.0)
	# Upside-down fork: fat tubes on top, thin legs to the hub.
	for side: float in [-1.0, 1.0]:
		_into(fork, _strut(Vector3(side * 0.11, 1.06, -0.49), Vector3(side * 0.11, 0.7, -0.62), Vector2(0.075, 0.075), paint))
		_into(fork, _strut(Vector3(side * 0.11, 0.72, -0.62), Vector3(side * 0.11, 0.35, -0.76), Vector2(0.045, 0.045), steel))
		root.add_child(_box(Vector3(0.14, 0.035, 0.06), Vector3(side * 0.21, 0.44, 0.04), steel))
		root.add_child(_strut(Vector3(side * 0.1, 0.52, 0.04), Vector3(side * 0.16, 0.45, 0.04), Vector2(0.04, 0.04), trim))
	# The power block: dark, finned, glowing through the gaps.
	root.add_child(_box(Vector3(0.3, 0.36, 0.5), Vector3(0, 0.56, -0.08), dim))
	for i in 7:
		root.add_child(_box(Vector3(0.34, 0.025, 0.54), Vector3(0, 0.4 + i * 0.052, -0.08), trim))
	root.add_child(_box(Vector3(0.36, 0.06, 0.3), Vector3(0, 0.36, 0.0), steel))
	# A beam frame from the head over the block to the swing-arm pivot.
	for side: float in [-1.0, 1.0]:
		root.add_child(_strut(Vector3(side * 0.12, 1.0, -0.46), Vector3(side * 0.15, 0.8, 0.2), Vector2(0.04, 0.1), steel))
		root.add_child(_strut(Vector3(side * 0.15, 0.8, 0.2), Vector3(side * 0.13, 0.52, 0.2), Vector2(0.04, 0.1), steel))
	# One-sided swing arm on the left; a short, chunky pipe on the right.
	root.add_child(_strut(Vector3(-0.16, 0.52, 0.2), Vector3(-0.17, 0.36, 0.75), Vector2(0.06, 0.12), trim))
	root.add_child(_cyl(0.1, 0.1, 0.06, Vector3(-0.19, 0.36, 0.75), steel, Vector3(0, 0, PI / 2.0), 16))
	root.add_child(_box(Vector3(0.12, 0.12, 0.3), Vector3(0.14, 0.33, 0.32), trim))
	root.add_child(_box(Vector3(0.1, 0.08, 0.02), Vector3(0.14, 0.33, 0.48), dim))
	# The tank, and its shrouds flaring forward and down past the block.
	_paneled(root, RoundedPath.of([Vector2(-0.4, 1.0), Vector2(-0.22, 1.14), Vector2(0.06, 1.1), Vector2(0.12, 0.96),
			Vector2(-0.05, 0.86), Vector2(-0.4, 0.9)], 0.03), 0.36, 0.0, paint, [-0.1], 0.012)
	for side: float in [-1.0, 1.0]:
		var shroud := _extrude(PackedVector2Array([Vector2(-0.5, 1.0), Vector2(-0.18, 0.98), Vector2(0.02, 0.8),
				Vector2(-0.06, 0.66), Vector2(-0.38, 0.78)]), 0.02, "x", paint)
		shroud.position.x = side * 0.19
		shroud.rotation.y = side * 0.12
		root.add_child(shroud)
		root.add_child(_strut(Vector3(side * 0.2, 0.96, -0.44), Vector3(side * 0.205, 0.74, -0.08), Vector2(0.006, 0.022), seam))
	# The seat, stepped, and a short high stub of a tail with a thin lamp.
	_add(root, _extrude(RoundedPath.of([Vector2(0.06, 0.96), Vector2(0.1, 1.0), Vector2(0.5, 1.0), Vector2(0.56, 0.96)], 0.02), 0.28, "x", trim))
	_paneled(root, PackedVector2Array([Vector2(0.5, 0.94), Vector2(0.56, 1.04), Vector2(0.82, 1.14), Vector2(0.84, 1.1),
			Vector2(0.7, 0.92), Vector2(0.3, 0.86)]), 0.24, 0.0, paint, [], 0.01)
	root.add_child(_strut(Vector3(-0.08, 1.11, 0.835), Vector3(0.08, 1.11, 0.835), Vector2(0.02, 0.025), tail))
	# The insect face: two stacked lamps under a tiny smoked screen.
	_into(fork, _box(Vector3(0.22, 0.24, 0.1), Vector3(0, 1.02, -0.6), trim))
	_into(fork, _box(Vector3(0.12, 0.05, 0.03), Vector3(0, 1.08, -0.655), lamp))
	_into(fork, _box(Vector3(0.12, 0.05, 0.03), Vector3(0, 0.98, -0.655), _glow(Color(1.0, 0.9, 0.7), 2.0)))
	var screen := _strut(Vector3(0, 1.14, -0.62), Vector3(0, 1.24, -0.54), Vector2(0.2, 0.012), glass)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_into(fork, screen)
	_into(fork, _extrude(_arc(Vector2(-0.76, 0.35), 0.39, 0.42, 0.3 * PI, 0.7 * PI), 0.18, "x", trim))
	# Flat bars on risers.
	_into(fork, _strut(Vector3(0, 1.06, -0.48), Vector3(0, 1.17, -0.32), Vector2(0.05, 0.05), trim))
	_into(fork, _strut(Vector3(-0.28, 1.2, -0.3), Vector3(0.28, 1.2, -0.3), Vector2(0.03, 0.03), steel))
	for side: float in [-1.0, 1.0]:
		_into(fork, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.24, 1.2, -0.3), trim))
	return root


# --- Scrapper C: the Junker ----------------------------------------------------
## A café racer welded out of salvage: a long drum for a tank, a hump
## seat, a bullet nose cut from a pipe end with a round lamp and a bolted
## armour plate, a stack of three glowing cells under it, twin low pipes,
## laced wheels.
func _junker() -> Node3D:
	var root := Node3D.new()
	var dim := _glow(ENERGY, 1.5)
	var head := Vector3(0, 1.0, -0.52)
	var fork := _pivot(root, "Steer", head, head - Vector3(0, 0.36, -0.78), 1.0, true)
	var front := _wheel_set(fork, Vector3(0, 0.36, -0.78) - head, 0.36, 0.13, dim, 0.0)
	front.name = "WheelFront"
	var rear := _wheel_set(root, Vector3(0, 0.36, 0.75), 0.36, 0.17, dim, 0.0)
	for wheel: Node3D in [front, rear]:
		var spin := wheel.get_node("Spin")
		for i in 8:
			var spoke := _box(Vector3(0.012, 0.5, 0.012), Vector3.ZERO, steel)
			spoke.rotation.x = i * PI / 8.0 + 0.1
			spin.add_child(spoke)
	for side: float in [-1.0, 1.0]:
		_into(fork, _strut(Vector3(side * 0.09, 1.02, -0.51), Vector3(side * 0.09, 0.36, -0.78), Vector2(0.045, 0.045), steel))
		# A twin-loop frame under the drum.
		root.add_child(_strut(Vector3(side * 0.09, 0.96, -0.48), Vector3(side * 0.11, 0.38, -0.3), Vector2(0.035, 0.035), trim))
		root.add_child(_strut(Vector3(side * 0.11, 0.38, -0.3), Vector3(side * 0.11, 0.4, 0.15), Vector2(0.035, 0.035), trim))
		root.add_child(_strut(Vector3(side * 0.11, 0.4, 0.15), Vector3(side * 0.11, 0.92, 0.2), Vector2(0.035, 0.035), trim))
		root.add_child(_strut(Vector3(side * 0.11, 0.92, 0.2), Vector3(side * 0.1, 0.92, 0.85), Vector2(0.035, 0.035), trim))
		root.add_child(_strut(Vector3(side * 0.12, 0.45, 0.12), Vector3(side * 0.12, 0.36, 0.75), Vector2(0.04, 0.06), steel))
		root.add_child(_strut(Vector3(side * 0.11, 0.92, 0.55), Vector3(side * 0.13, 0.42, 0.68), Vector2(0.04, 0.04), steel))
		root.add_child(_box(Vector3(0.14, 0.035, 0.06), Vector3(side * 0.21, 0.44, 0.06), steel))
		# Twin low megaphone pipes.
		root.add_child(_strut(Vector3(side * 0.12, 0.5, -0.3), Vector3(side * 0.18, 0.34, 0.2), Vector2(0.05, 0.05), steel))
		root.add_child(_cyl(0.05, 0.075, 0.5, Vector3(side * 0.19, 0.38, 0.48), steel, Vector3(PI / 2.0 - 0.15, 0, 0), 12))
		root.add_child(_cyl(0.06, 0.06, 0.01, Vector3(side * 0.19, 0.42, 0.73), dim, Vector3(PI / 2.0 - 0.15, 0, 0), 12))
	# Three cells stacked in the frame, their ends glowing.
	for i in 3:
		var y := 0.5 + i * 0.13
		root.add_child(_cyl(0.06, 0.06, 0.2, Vector3(0, y, -0.12 + i * 0.03), steel, Vector3(0, 0, PI / 2.0), 12))
		root.add_child(_cyl(0.045, 0.045, 0.22, Vector3(0, y, -0.12 + i * 0.03), dim, Vector3(0, 0, PI / 2.0), 12))
	# The tank: a long drum with welded bands and a cap.
	root.add_child(_capsule(0.15, 0.78, Vector3(0, 0.98, -0.2), paint, Vector3(PI / 2.0 - 0.1, 0, 0)))
	for z: float in [-0.42, -0.2, 0.02]:
		root.add_child(_cyl(0.155, 0.155, 0.02, Vector3(0, 0.98 - z * 0.1, z), trim, Vector3(PI / 2.0 - 0.1, 0, 0), 16))
	root.add_child(_cyl(0.04, 0.04, 0.04, Vector3(0, 1.14, -0.32), steel))
	# The seat and its hump.
	_add(root, _extrude(RoundedPath.of([Vector2(0.14, 0.92), Vector2(0.16, 0.99), Vector2(0.48, 0.99), Vector2(0.52, 0.94)], 0.02), 0.26, "x", trim))
	_paneled(root, RoundedPath.of([Vector2(0.48, 0.92), Vector2(0.52, 1.02), Vector2(0.64, 1.1), Vector2(0.82, 1.08),
			Vector2(0.9, 0.98), Vector2(0.86, 0.9)], 0.03), 0.26, 0.0, paint, [], 0.01)
	root.add_child(_cyl(0.035, 0.035, 0.02, Vector3(0, 1.0, 0.91), tail, Vector3(PI / 2.0, 0, 0), 12))
	# The bullet nose: a pipe end round a lamp, an armour plate bolted on top.
	_into(fork, _cyl(0.15, 0.13, 0.26, Vector3(0, 1.0, -0.6), paint, Vector3(PI / 2.0 + 0.15, 0, 0), 16))
	_into(fork, _cyl(0.11, 0.11, 0.02, Vector3(0, 1.02, -0.735), lamp, Vector3(PI / 2.0 + 0.15, 0, 0), 16))
	var plate := _box(Vector3(0.24, 0.012, 0.26), Vector3(0, 1.15, -0.62), steel)
	plate.rotation.x = 0.2
	_into(fork, plate)
	for c: float in [-0.09, 0.09]:
		_into(fork, _cyl(0.012, 0.012, 0.012, Vector3(c, 1.16, -0.68), trim, Vector3.ZERO, 6))
	_into(fork, _extrude(_arc(Vector2(-0.78, 0.36), 0.4, 0.43, 0.35 * PI, 0.75 * PI), 0.15, "x", steel))
	# Low clip-ons.
	for side: float in [-1.0, 1.0]:
		_into(fork, _strut(Vector3(side * 0.1, 1.1, -0.48), Vector3(side * 0.26, 1.18, -0.32), Vector2(0.03, 0.03), steel))
		_into(fork, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.24, 1.18, -0.32), trim))
	_patch(root, Vector3(0.155, 0.86, 0.6), Vector2(0.16, 0.08), 0.3, 1.0)
	return root


# --- Raider A: the Ducted ------------------------------------------------------
## One hull over two big ducted fans, front and back, whose rotors spin;
## short canards at the nose, one tall rudder, footboards on outriggers.
func _ducted() -> Node3D:
	var root := Node3D.new()
	var b: float = v.hover_height
	for z: float in [-0.78, 0.82]:
		var rr := 0.42 if z < 0 else 0.46
		var shell := _cyl(rr, rr, 0.2, Vector3(0, b + 0.12, z), paint, Vector3.ZERO, 28)
		(shell.mesh as CylinderMesh).cap_top = false
		(shell.mesh as CylinderMesh).cap_bottom = false
		root.add_child(shell)
		root.add_child(_ring(Vector3(0, b + 0.215, z), rr - 0.045, rr + 0.005, paint, Vector3.ZERO, 28))
		var inner := _cyl(rr - 0.04, rr - 0.04, 0.2, Vector3(0, b + 0.12, z), trim, Vector3.ZERO, 28)
		(inner.mesh as CylinderMesh).cap_top = false
		(inner.mesh as CylinderMesh).cap_bottom = false
		root.add_child(inner)
		for k in 2:
			var strut := _box(Vector3(0.03, 0.03, rr * 2.0 - 0.1), Vector3(0, b + 0.2, z), trim)
			strut.rotation.y = PI / 4.0 + k * PI / 2.0
			root.add_child(strut)
		root.add_child(_ring(Vector3(0, b + 0.225, z), rr - 0.06, rr - 0.02, seam))
		var disc := _cyl(rr - 0.1, rr - 0.1, 0.02, Vector3(0, b + 0.03, z), energy, Vector3.ZERO, 24)
		disc.name = "Thruster%d" % root.get_child_count()
		root.add_child(disc)
		# The rotor spins with the speed (`Vehicle._turn_parts`) and is
		# merged among itself, a draw per material.
		var rotor := Node3D.new()
		rotor.name = "Rotor%d" % root.get_child_count()
		rotor.position = Vector3(0, b + 0.13, z)
		rotor.set_meta("merge", true)
		root.add_child(rotor)
		for i in 5:
			var turn := Basis(Vector3.UP, i * TAU / 5.0)
			var blade := _box(Vector3(0.08, 0.012, rr - 0.12), turn * Vector3(0, 0, (rr - 0.12) * 0.5 + 0.04), steel)
			blade.basis = turn * Basis(Vector3.BACK, 0.35)
			rotor.add_child(blade)
		rotor.add_child(_cyl(0.07, 0.07, 0.06, Vector3.ZERO, trim))
	# The hull, long and narrow over the fans.
	var hull := PackedVector2Array([Vector2(-1.3, b + 0.3), Vector2(-1.0, b + 0.5), Vector2(-0.6, b + 0.62),
			Vector2(-0.28, b + 0.64), Vector2(-0.08, b + 0.5), Vector2(0.48, b + 0.5), Vector2(0.56, b + 0.58),
			Vector2(1.0, b + 0.6), Vector2(1.3, b + 0.48), Vector2(1.32, b + 0.3), Vector2(1.0, b + 0.22),
			Vector2(-1.0, b + 0.22)])
	_paneled(root, hull, 0.34, 0.0, paint, [-0.7, -0.1, 0.5], 0.014)
	_add(root, _extrude(RoundedPath.of([Vector2(-0.07, b + 0.5), Vector2(-0.04, b + 0.58), Vector2(0.42, b + 0.58),
			Vector2(0.48, b + 0.5)], 0.02), 0.32, "x", trim))
	_add(root, _extrude(RoundedPath.of([Vector2(0.57, b + 0.58), Vector2(0.6, b + 0.66), Vector2(0.94, b + 0.66),
			Vector2(1.0, b + 0.6)], 0.02), 0.3, "x", trim))
	for side: float in [-1.0, 1.0]:
		# Outrigger footboards from the hull, and the pillion's steps.
		root.add_child(_strut(Vector3(side * 0.16, b + 0.28, -0.04), Vector3(side * 0.42, b + 0.27, -0.04), Vector2(0.05, 0.06), trim))
		root.add_child(_box(Vector3(0.16, 0.03, 0.2), Vector3(side * 0.37, b + 0.28, -0.04), paint))
		root.add_child(_box(Vector3(0.12, 0.08, 0.12), Vector3(side * 0.36, b + 0.32, 0.5), trim))
		root.add_child(_strut(Vector3(side * 0.16, b + 0.3, 0.5), Vector3(side * 0.36, b + 0.32, 0.5), Vector2(0.04, 0.05), trim))
		# Canards at the nose.
		var canard := _extrude(PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.3, -0.86), Vector2(0.3, -0.74), Vector2(0.0, -0.7)]), 0.03, "y", paint)
		canard.position = Vector3(0, b + 0.42, 0)
		canard.scale.x = side
		root.add_child(canard)
		root.add_child(_strut(Vector3(side * 0.172, b + 0.36, -1.1), Vector3(side * 0.172, b + 0.33, 0.4), Vector2(0.006, 0.022), seam))
	# One tall rudder over the rear fan.
	var rudder := _pivot(root, "Fin0", Vector3(0, b + 0.6, 1.0), Vector3.UP, -0.5)
	_into(rudder, _extrude(RoundedPath.of([Vector2(0.95, b + 0.58), Vector2(1.18, b + 1.02), Vector2(1.32, b + 1.02), Vector2(1.3, b + 0.5)], 0.02), 0.03, "x", paint))
	var exhaust := _box(Vector3(0.22, 0.08, 0.02), Vector3(0, b + 0.38, 1.33), energy)
	exhaust.name = "Exhaust"
	root.add_child(exhaust)
	root.add_child(_box(Vector3(0.14, 0.03, 0.03), Vector3(0, b + 0.33, -1.3), lamp))
	var screen := _strut(Vector3(0, b + 0.62, -0.66), Vector3(0, b + 0.86, -0.52), Vector2(0.3, 0.012), glass)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)
	var stem := Vector3(0, b + 0.6, -0.5)
	var bars := _pivot(root, "Steer", stem, Vector3(0, 1.3, -0.43) - stem, 1.0, true)
	_into(bars, _strut(stem, Vector3(0, 1.3, -0.43), Vector2(0.06, 0.05), trim))
	_into(bars, _strut(Vector3(-0.34, 1.3, -0.42), Vector3(0.34, 1.3, -0.42), Vector2(0.032, 0.032), steel))
	for side: float in [-1.0, 1.0]:
		_into(bars, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.3, 1.3, -0.42), trim))
	return root


# --- Raider B: the Manta -------------------------------------------------------
## A wide, flat lifting body, a manta seen from above, with the seats on a
## raised spine, four lift thrusters under the wing, wingtip fins that turn
## as rudders and two exhaust slots in the trailing edge.
func _manta() -> Node3D:
	var root := Node3D.new()
	var b: float = v.hover_height
	var wing := PackedVector2Array([Vector2(0.0, -1.42), Vector2(0.22, -1.12), Vector2(0.5, -0.5), Vector2(0.86, 0.3),
			Vector2(0.9, 0.62), Vector2(0.6, 0.86), Vector2(0.3, 1.0), Vector2(0.18, 1.3), Vector2(-0.18, 1.3), Vector2(-0.3, 1.0),
			Vector2(-0.6, 0.86), Vector2(-0.9, 0.62), Vector2(-0.86, 0.3), Vector2(-0.5, -0.5), Vector2(-0.22, -1.12)])
	var deck := _extrude(wing, 0.06, "y", paint)
	deck.position.y = b + 0.18
	root.add_child(deck)
	var under := _extrude(Geometry2D.offset_polygon(wing, -0.06)[0], 0.12, "y", trim)
	under.position.y = b + 0.14
	root.add_child(under)
	# A lit seam round the leading edge.
	for side: float in [-1.0, 1.0]:
		root.add_child(_strut(Vector3(side * 0.03, b + 0.2, -1.4), Vector3(side * 0.23, b + 0.2, -1.1), Vector2(0.02, 0.02), seam))
		root.add_child(_strut(Vector3(side * 0.23, b + 0.2, -1.1), Vector3(side * 0.85, b + 0.2, 0.28), Vector2(0.02, 0.02), seam))
		for z: float in [-0.15, 0.55]:
			root.add_child(_cyl(0.16, 0.16, 0.06, Vector3(side * 0.5, b + 0.08, z), trim, Vector3.ZERO, 20))
			var disc := _cyl(0.13, 0.13, 0.02, Vector3(side * 0.5, b + 0.04, z), energy, Vector3.ZERO, 20)
			disc.name = "Thruster%d" % root.get_child_count()
			root.add_child(disc)
		# Wingtip fins, swinging as rudders.
		var fin := _pivot(root, "Fin%d" % (0 if side < 0.0 else 1), Vector3(side * 0.86, b + 0.22, 0.6), Vector3.UP, -0.5)
		var blade := _extrude(RoundedPath.of([Vector2(0.3, b + 0.22), Vector2(0.62, b + 0.58), Vector2(0.76, b + 0.58), Vector2(0.8, b + 0.22)], 0.02), 0.03, "x", paint)
		blade.position.x = side * 0.88
		_into(fin, blade)
		root.add_child(_box(Vector3(0.14, 0.04, 0.22), Vector3(side * 0.37, b + 0.25, -0.04), trim))
		root.add_child(_box(Vector3(0.12, 0.1, 0.12), Vector3(side * 0.36, b + 0.29, 0.5), trim))
		var slot := _box(Vector3(0.14, 0.05, 0.02), Vector3(side * 0.24, b + 0.2, 1.23), energy)
		slot.name = "Exhaust%d" % root.get_child_count()
		root.add_child(slot)
	# The spine: nose cowl, the rider's seat, the raised pillion.
	var spine := PackedVector2Array([Vector2(-1.25, b + 0.24), Vector2(-0.9, b + 0.42), Vector2(-0.5, b + 0.58),
			Vector2(-0.24, b + 0.6), Vector2(-0.08, b + 0.5), Vector2(0.48, b + 0.5), Vector2(0.56, b + 0.6),
			Vector2(1.0, b + 0.64), Vector2(1.15, b + 0.5), Vector2(1.1, b + 0.24)])
	_paneled(root, spine, 0.3, 0.0, paint, [-0.62, -0.1, 0.52], 0.014)
	_add(root, _extrude(RoundedPath.of([Vector2(-0.07, b + 0.5), Vector2(-0.04, b + 0.58), Vector2(0.42, b + 0.58),
			Vector2(0.48, b + 0.5)], 0.02), 0.3, "x", trim))
	_add(root, _extrude(RoundedPath.of([Vector2(0.57, b + 0.6), Vector2(0.6, b + 0.68), Vector2(0.94, b + 0.68),
			Vector2(1.0, b + 0.62)], 0.02), 0.28, "x", trim))
	root.add_child(_box(Vector3(0.3, 0.025, 0.03), Vector3(0, b + 0.24, -1.28), lamp))
	var screen := _strut(Vector3(0, b + 0.58, -0.62), Vector3(0, b + 0.82, -0.5), Vector2(0.3, 0.012), glass)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)
	var stem := Vector3(0, b + 0.58, -0.5)
	var bars := _pivot(root, "Steer", stem, Vector3(0, 1.3, -0.43) - stem, 1.0, true)
	_into(bars, _strut(stem, Vector3(0, 1.3, -0.43), Vector2(0.06, 0.05), trim))
	_into(bars, _strut(Vector3(-0.34, 1.3, -0.42), Vector3(0.34, 1.3, -0.42), Vector2(0.032, 0.032), steel))
	for side: float in [-1.0, 1.0]:
		_into(bars, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.3, 1.3, -0.42), trim))
	return root


# --- Raider C: the Lancer ------------------------------------------------------
## A long needle of a hull with a lift pod slung under the nose and two big
## engine nacelles canted out behind the pillion, a blade keel under it.
func _lancer() -> Node3D:
	var root := Node3D.new()
	var b: float = v.hover_height
	var hull := PackedVector2Array([Vector2(-1.6, b + 0.36), Vector2(-1.2, b + 0.48), Vector2(-0.6, b + 0.6),
			Vector2(-0.26, b + 0.62), Vector2(-0.08, b + 0.5), Vector2(0.48, b + 0.5), Vector2(0.56, b + 0.6),
			Vector2(0.95, b + 0.62), Vector2(1.2, b + 0.5), Vector2(1.22, b + 0.3), Vector2(0.9, b + 0.22),
			Vector2(-0.8, b + 0.24), Vector2(-1.4, b + 0.3)])
	_paneled(root, hull, 0.3, 0.0, paint, [-0.9, -0.1, 0.52], 0.014)
	_add(root, _extrude(RoundedPath.of([Vector2(-0.07, b + 0.5), Vector2(-0.04, b + 0.58), Vector2(0.42, b + 0.58),
			Vector2(0.48, b + 0.5)], 0.02), 0.3, "x", trim))
	_add(root, _extrude(RoundedPath.of([Vector2(0.57, b + 0.6), Vector2(0.6, b + 0.68), Vector2(0.92, b + 0.68),
			Vector2(0.97, b + 0.62)], 0.02), 0.28, "x", trim))
	# The nose pod: a ducted lift ring slung under the hull on a pylon.
	root.add_child(_strut(Vector3(0, b + 0.3, -1.0), Vector3(0, b + 0.16, -0.95), Vector2(0.08, 0.2), trim))
	root.add_child(_cyl(0.26, 0.26, 0.14, Vector3(0, b + 0.1, -0.95), paint, Vector3.ZERO, 24))
	root.add_child(_cyl(0.22, 0.22, 0.16, Vector3(0, b + 0.1, -0.95), trim, Vector3.ZERO, 24))
	var disc := _cyl(0.19, 0.19, 0.02, Vector3(0, b + 0.02, -0.95), energy, Vector3.ZERO, 20)
	disc.name = "Thruster%d" % root.get_child_count()
	root.add_child(disc)
	for side: float in [-1.0, 1.0]:
		# The nacelles: big engine pods canted out on swept pylons, an
		# intake ring in front, a glowing nozzle behind, a lift disc under.
		var at := Vector3(side * 0.52, b + 0.26, 0.6)
		root.add_child(_strut(Vector3(side * 0.12, b + 0.34, 0.45), at + Vector3(-side * 0.08, 0.04, -0.1), Vector2(0.05, 0.18), trim))
		# Built in the nacelle's own frame, then set into the model's, so
		# its pieces merge with the rest.
		var pod := Transform3D(Basis.from_euler(Vector3(0, -side * 0.06, side * 0.25)), at)
		_set_in(root, pod, _capsule(0.16, 1.1, Vector3.ZERO, paint, Vector3(PI / 2.0, 0, 0)))
		_set_in(root, pod, _cyl(0.17, 0.17, 0.05, Vector3(0, 0, -0.38), trim, Vector3(PI / 2.0, 0, 0), 16))
		_set_in(root, pod, _cyl(0.12, 0.15, 0.16, Vector3(0, 0, 0.56), trim, Vector3(PI / 2.0, 0, 0), 16))
		var noz := _cyl(0.11, 0.11, 0.02, Vector3(0, 0, 0.645), energy, Vector3(PI / 2.0, 0, 0), 16)
		noz.name = "Exhaust%d" % root.get_child_count()
		_set_in(root, pod, noz)
		var lift := _cyl(0.11, 0.11, 0.02, Vector3(0, -0.16, 0.0), energy, Vector3.ZERO, 16)
		lift.name = "Thruster%d" % root.get_child_count()
		_set_in(root, pod, lift)
		_set_in(root, pod, _strut(Vector3(side * 0.15, 0.03, -0.4), Vector3(side * 0.15, 0.03, 0.4), Vector2(0.008, 0.02), seam))
		# Footboards and the pillion's steps.
		root.add_child(_strut(Vector3(side * 0.14, b + 0.28, -0.04), Vector3(side * 0.42, b + 0.27, -0.04), Vector2(0.05, 0.06), trim))
		root.add_child(_box(Vector3(0.16, 0.03, 0.2), Vector3(side * 0.37, b + 0.28, -0.04), paint))
		root.add_child(_strut(Vector3(side * 0.152, b + 0.38, -1.4), Vector3(side * 0.152, b + 0.34, 0.4), Vector2(0.006, 0.022), seam))
		# Rudders on the nacelles.
		var fin := _pivot(root, "Fin%d" % (0 if side < 0.0 else 1), at + Vector3(side * 0.05, 0.12, 0.3), Basis(Vector3.FORWARD, side * 0.25) * Vector3.UP, -0.5)
		var blade := _extrude(RoundedPath.of([Vector2(0.4, b + 0.36), Vector2(0.68, b + 0.7), Vector2(0.82, b + 0.7), Vector2(0.86, b + 0.36)], 0.02), 0.03, "x", paint)
		blade.position.x = at.x - side * 0.03
		_into(fin, blade)
	# A blade keel under the hull.
	_add(root, _extrude(PackedVector2Array([Vector2(-0.6, b + 0.24), Vector2(0.4, b + 0.24), Vector2(0.2, b + 0.1), Vector2(-0.4, b + 0.14)]), 0.04, "x", trim))
	root.add_child(_box(Vector3(0.12, 0.03, 0.03), Vector3(0, b + 0.38, -1.6), lamp))
	var screen := _strut(Vector3(0, b + 0.6, -0.66), Vector3(0, b + 0.86, -0.52), Vector2(0.3, 0.012), glass)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)
	var stem := Vector3(0, b + 0.6, -0.5)
	var bars := _pivot(root, "Steer", stem, Vector3(0, 1.3, -0.43) - stem, 1.0, true)
	_into(bars, _strut(stem, Vector3(0, 1.3, -0.43), Vector2(0.06, 0.05), trim))
	_into(bars, _strut(Vector3(-0.34, 1.3, -0.42), Vector3(0.34, 1.3, -0.42), Vector2(0.032, 0.032), steel))
	for side: float in [-1.0, 1.0]:
		_into(bars, _box(Vector3(0.12, 0.045, 0.045), Vector3(side * 0.3, 1.3, -0.42), trim))
	return root


# --- Rover -----------------------------------------------------------------------

## The driver must see out: nothing but glass stands between the driver's
## eyes and the road ahead (a test looks), so everything ahead of the dash
## stays low.
func _rover() -> Node3D:
	var root := Node3D.new()
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.35, 1.35]:
			_wheel_set(root, Vector3(x, 0.52, z), 0.52, 0.4, energy, x * 0.21, z < 0.0)
			# An armored pod over the wheel: an angular arch.
			var pod := PackedVector2Array([Vector2(z - 0.8, 0.84), Vector2(z - 0.62, 1.12), Vector2(z - 0.32, 1.2),
					Vector2(z + 0.32, 1.2), Vector2(z + 0.62, 1.12), Vector2(z + 0.8, 0.84), Vector2(z + 0.68, 0.84),
					Vector2(z + 0.52, 1.07), Vector2(z + 0.27, 1.12), Vector2(z - 0.27, 1.12), Vector2(z - 0.52, 1.07),
					Vector2(z - 0.68, 0.84)])
			_add(root, _extrude(pod, 0.58, "x", paint), Vector3(x * 1.0, 0, 0))
			root.add_child(_strut(Vector3(x * 1.292, 1.12, z - 0.3), Vector3(x * 1.292, 1.12, z + 0.3), Vector2(0.006, 0.02), seam))
		# The tub's flanks, low enough to show the crew, with a lit seam.
		var flank := PackedVector2Array([Vector2(-0.8, 0.68), Vector2(-0.8, 1.22), Vector2(-0.6, 1.28),
				Vector2(0.7, 1.2), Vector2(0.8, 1.1), Vector2(0.8, 0.68)])
		_paneled(root, flank, 0.14, x * 0.86, paint, [-0.05], 0.01)
		root.add_child(_strut(Vector3(x * 0.932, 1.02, -0.7), Vector3(x * 0.932, 1.02, 0.7), Vector2(0.006, 0.03), seam))
		root.add_child(_box(Vector3(0.22, 0.05, 1.0), Vector3(x * 0.98, 0.64, 0.0), steel))  # side step
		# A headlight in each corner of the nose, and tail lamps.
		root.add_child(_box(Vector3(0.24, 0.06, 0.04), Vector3(x * 0.6, 1.0, -2.2), lamp))
		root.add_child(_box(Vector3(0.22, 0.05, 0.03), Vector3(x * 0.68, 1.04, 2.2), tail))
		# The windscreen's pillars, raked back from the dash.
		root.add_child(_strut(Vector3(x * 0.8, 1.3, -0.7), Vector3(x * 0.78, 1.98, -0.5), Vector2(0.06, 0.06), steel))
		root.add_child(_strut(Vector3(x * 0.78, 1.98, -0.5), Vector3(x * 0.62, 2.07, 0.78), Vector2(0.05, 0.05), steel))
	root.add_child(_box(Vector3(1.5, 0.28, 3.8), Vector3(0, 0.62, 0), trim))      # chassis
	root.add_child(_box(Vector3(1.6, 0.06, 1.9), Vector3(0, 0.82, 0.05), trim))   # cab floor
	# The hood: a wedge sloping down to the nose, panelled, with a lit
	# strip across the nose between the lamps.
	var hood := PackedVector2Array([Vector2(-2.22, 0.62), Vector2(-2.22, 0.98), Vector2(-2.0, 1.12),
			Vector2(-0.8, 1.27), Vector2(-0.62, 1.29), Vector2(-0.62, 0.62)])
	_paneled(root, hood, 1.6, 0.0, paint, [-1.5], 0.016)
	# A raised spine down the hood's middle, kept under the driver's eye line.
	_add(root, _extrude(PackedVector2Array([Vector2(-2.05, 1.1), Vector2(-2.0, 1.17), Vector2(-0.82, 1.33),
			Vector2(-0.82, 1.24)]), 0.5, "x", paint))
	for x: float in [-0.26, 0.26]:
		root.add_child(_strut(Vector3(x, 1.18, -1.9), Vector3(x, 1.32, -0.9), Vector2(0.012, 0.012), seam))
	root.add_child(_strut(Vector3(-0.42, 0.9, -2.23), Vector3(0.42, 0.9, -2.23), Vector2(0.03, 0.02), seam))
	root.add_child(_strut(Vector3(-0.95, 0.62, -2.3), Vector3(0.95, 0.62, -2.3), Vector2(0.14, 0.12), steel))  # ram
	# The dash under the windscreen, with the driver's screens lit.
	root.add_child(_box(Vector3(1.62, 0.2, 0.3), Vector3(0, 1.2, -0.6), trim))
	var screen := _glow(ENERGY, 1.2)
	root.add_child(_strut(Vector3(-0.55, 1.31, -0.58), Vector3(-0.25, 1.31, -0.58), Vector2(0.12, 0.02), screen))
	root.add_child(_strut(Vector3(0.25, 1.31, -0.58), Vector3(0.45, 1.31, -0.58), Vector2(0.1, 0.02), screen))
	root.add_child(_strut(Vector3(-0.8, 1.98, -0.5), Vector3(0.8, 1.98, -0.5), Vector2(0.06, 0.06), steel))
	# The front passenger's grab rail over the dash, on two posts.
	root.add_child(_strut(Vector3(0.18, 1.32, -0.32), Vector3(0.62, 1.32, -0.32), Vector2(0.04, 0.04), steel))
	for x: float in [0.18, 0.62]:
		root.add_child(_strut(Vector3(x, 1.3, -0.48), Vector3(x, 1.32, -0.32), Vector2(0.035, 0.035), steel))
	var glass_pane := _strut(Vector3(0, 1.32, -0.7), Vector3(0, 1.96, -0.52), Vector2(1.54, 0.02), glass)
	glass_pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass_pane)
	# One roll hoop behind the seats, chamfered at its shoulders, with a
	# light bar along its top.
	var hoop := [Vector3(-0.84, 1.15, 0.78), Vector3(-0.84, 1.78, 0.78), Vector3(-0.6, 2.08, 0.78),
			Vector3(0.6, 2.08, 0.78), Vector3(0.84, 1.78, 0.78), Vector3(0.84, 1.15, 0.78)]
	for i in hoop.size() - 1:
		root.add_child(_strut(hoop[i], hoop[i + 1], Vector2(0.09, 0.09), steel))
	root.add_child(_box(Vector3(1.0, 0.06, 0.08), Vector3(0, 2.15, 0.78), trim))
	root.add_child(_strut(Vector3(-0.42, 2.15, 0.733), Vector3(0.42, 2.15, 0.733), Vector2(0.04, 0.012), seam))
	# Low bucket seats, so the crew's shoulders and heads show over them.
	for x: float in [-0.4, 0.4]:
		_add(root, _extrude(RoundedPath.of([Vector2(0.02, 0.85), Vector2(0.02, 0.95), Vector2(0.48, 0.95),
				Vector2(0.58, 1.38), Vector2(0.66, 1.38), Vector2(0.58, 0.85)], 0.03), 0.46, "x", trim), Vector3(x, 0, 0))
		for side: float in [-1.0, 1.0]:
			root.add_child(_box(Vector3(0.05, 0.12, 0.4), Vector3(x + side * 0.24, 0.98, 0.28), trim))  # bolster
	# The wheel faces the driver, its rim through the grips (`grip_points`).
	# It turns on its column, the hands with it, a spoke across to show it.
	var tilt := Basis(Vector3.RIGHT, PI / 2.0 - 0.45)
	var hub := Vector3(-0.4, 1.27, -0.25)
	var turner := _pivot(root, "SteerWheel", hub, tilt * Vector3.UP, 2.2, true)
	var wheel := MeshInstance3D.new()
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.16
	wheel_mesh.outer_radius = 0.2
	wheel_mesh.material = trim
	wheel.mesh = wheel_mesh
	wheel.basis = tilt
	turner.add_child(wheel)
	var spoke := _box(Vector3(0.34, 0.03, 0.05), Vector3.ZERO, steel)
	spoke.basis = tilt
	turner.add_child(spoke)
	root.add_child(_strut(Vector3(-0.4, 1.12, -0.6), Vector3(-0.4, 1.27, -0.25), Vector2(0.05, 0.05), steel))  # column
	for x: float in [-0.52, -0.28]:
		root.add_child(_box(Vector3(0.1, 0.04, 0.16), Vector3(x, 0.86, -0.5), steel))  # pedal
	# The back: two raised seats for the passengers behind, between the rear
	# pods, a bar across the roll hoop for them to hold, a second, lower
	# hoop behind them, and a low cargo bay with a power cell at the tail.
	root.add_child(_box(Vector3(1.4, 0.06, 1.2), Vector3(0, 0.86, 1.4), trim))  # rear floor
	root.add_child(_strut(Vector3(-0.84, 1.42, 0.84), Vector3(0.84, 1.42, 0.84), Vector2(0.05, 0.05), steel))  # grab bar
	for x: float in [-0.4, 0.4]:
		_add(root, _extrude(RoundedPath.of([Vector2(1.17, 0.85), Vector2(1.17, 1.05), Vector2(1.63, 1.05),
				Vector2(1.73, 1.5), Vector2(1.81, 1.5), Vector2(1.73, 0.85)], 0.03), 0.46, "x", trim), Vector3(x, 0, 0))
		for side: float in [-1.0, 1.0]:
			root.add_child(_box(Vector3(0.05, 0.12, 0.4), Vector3(x + side * 0.24, 1.08, 1.43), trim))  # bolster
	var rear_hoop := [Vector3(-0.8, 1.15, 1.88), Vector3(-0.8, 1.62, 1.88), Vector3(-0.6, 1.82, 1.88),
			Vector3(0.6, 1.82, 1.88), Vector3(0.8, 1.62, 1.88), Vector3(0.8, 1.15, 1.88)]
	for i in rear_hoop.size() - 1:
		root.add_child(_strut(rear_hoop[i], rear_hoop[i + 1], Vector2(0.08, 0.08), steel))
	for x: float in [-0.62, 0.62]:
		root.add_child(_strut(Vector3(x, 2.06, 0.78), Vector3(x, 1.82, 1.88), Vector2(0.06, 0.06), steel))  # cage rail
	var bay := PackedVector2Array([Vector2(1.9, 0.62), Vector2(1.9, 1.12), Vector2(2.1, 1.12),
			Vector2(2.22, 1.0), Vector2(2.22, 0.62)])
	_paneled(root, bay, 1.6, 0.0, paint, [], 0.016)
	root.add_child(_cyl(0.1, 0.1, 0.6, Vector3(0, 1.2, 2.04), trim, Vector3(0, 0, PI / 2.0), 16))
	for x: float in [-0.22, 0.22]:
		root.add_child(_cyl(0.105, 0.105, 0.03, Vector3(x, 1.2, 2.04), energy, Vector3(0, 0, PI / 2.0), 16))
	root.add_child(_strut(Vector3(-0.95, 0.72, 2.25), Vector3(0.95, 0.72, 2.25), Vector2(0.18, 0.16), trim))  # bumper
	root.add_child(_strut(Vector3(0.78, 1.16, 2.0), Vector3(0.84, 2.3, 2.12), Vector2(0.02, 0.02), steel))  # antenna
	return root


# --- Mech ------------------------------------------------------------------------

func _mech() -> Node3D:
	var root := Node3D.new()
	var hip: float = v.LEG_HIP
	for x: float in [-0.62, 0.62]:
		var leg := Node3D.new()
		leg.name = "LegL" if x < 0.0 else "LegR"
		leg.position = Vector3(x, hip, 0.1)
		_bird_leg(leg, signf(x))
		root.add_child(leg)
	root.add_child(_box(Vector3(1.1, 0.36, 0.8), Vector3(0, 1.82, 0.1), trim))  # hip block
	root.add_child(_cyl(0.16, 0.16, 1.5, Vector3(0, hip, 0.1), steel, Vector3(0, 0, PI / 2.0), 16))  # hip axle
	# The pod, one side profile: a sloped cowl in front of the pilot, a
	# footwell, the floor under the seat and the power unit behind it.
	var pod := PackedVector2Array([Vector2(-0.96, 1.98), Vector2(-1.04, 2.26), Vector2(-0.92, 2.6),
			Vector2(-0.72, 2.76), Vector2(-0.66, 2.74), Vector2(-0.64, 2.04), Vector2(-0.22, 2.04),
			Vector2(-0.18, 2.26), Vector2(0.42, 2.26), Vector2(0.5, 2.96), Vector2(0.94, 2.96),
			Vector2(1.06, 2.72), Vector2(1.0, 2.0), Vector2(0.4, 1.96)])
	_paneled(root, pod, 1.44, 0.0, paint, [-0.6, 0.46], 0.018)
	# Low armored sides, so the pilot sits exposed from the chest up.
	for side: float in [-1.0, 1.0]:
		var wall := PackedVector2Array([Vector2(-0.72, 2.04), Vector2(-0.72, 2.6), Vector2(-0.4, 2.56),
				Vector2(0.44, 2.5), Vector2(0.44, 2.04)])
		_paneled(root, wall, 0.12, side * 0.66, paint, [-0.1], 0.01)
		root.add_child(_strut(Vector3(side * 0.722, 2.42, -0.6), Vector3(side * 0.722, 2.4, 0.38), Vector2(0.006, 0.026), seam))
		# A cannon on each shoulder: a mount, a shrouded barrel and a lit muzzle.
		root.add_child(_box(Vector3(0.24, 0.3, 0.6), Vector3(side * 0.84, 2.45, 0.0), trim))
		_add(root, _extrude(RoundedPath.of([Vector2(-0.75, 2.36), Vector2(-0.75, 2.56), Vector2(0.25, 2.6),
				Vector2(0.3, 2.34)], 0.03), 0.26, "x", paint), Vector3(side * 1.0, 0, 0))
		root.add_child(_cyl(0.06, 0.06, 0.62, Vector3(side * 1.0, 2.46, -1.04), steel, Vector3(PI / 2.0, 0, 0), 12))
		root.add_child(_cyl(0.075, 0.075, 0.03, Vector3(side * 1.0, 2.46, -1.36), seam, Vector3(PI / 2.0, 0, 0), 12))
		# Control sticks out of the footwell, up to the grips.
		root.add_child(_strut(Vector3(side * 0.25, 2.06, -0.44), Vector3(side * 0.25, 2.48, -0.38), Vector2(0.05, 0.05), steel))
		root.add_child(_box(Vector3(0.06, 0.1, 0.06), Vector3(side * 0.25, 2.5, -0.38), trim))
		root.add_child(_box(Vector3(0.18, 0.04, 0.25), Vector3(side * 0.16, 2.06, -0.5), steel))  # pedal
		# Jump-jets under the power unit: a bell pointing down, lit inside.
		root.add_child(_cyl(0.13, 0.17, 0.2, Vector3(side * 0.42, 1.92, 0.78), steel, Vector3.ZERO, 16))
		root.add_child(_cyl(0.13, 0.13, 0.01, Vector3(side * 0.42, 1.82, 0.78), energy, Vector3.ZERO, 16))
	# The seat against the power unit.
	_add(root, _extrude(RoundedPath.of([Vector2(-0.08, 2.24), Vector2(-0.06, 2.32), Vector2(0.3, 2.32),
			Vector2(0.4, 2.92), Vector2(0.46, 2.92), Vector2(0.42, 2.24)], 0.03), 0.5, "x", trim))
	# The power unit's vent on its back (its weak spot, by design), behind
	# dark slats, and an antenna.
	var vent := _box(Vector3(0.7, 0.42, 0.02), Vector3(0, 2.5, 1.04), _glow(ENERGY, 1.3))
	vent.rotation.x = 0.08
	root.add_child(vent)
	for i in 4:
		var slat := _box(Vector3(0.84, 0.03, 0.04), Vector3(0, 2.32 + i * 0.12, 1.06), trim)
		slat.rotation.x = 0.08
		root.add_child(slat)
	root.add_child(_strut(Vector3(0.36, 2.96, 0.8), Vector3(0.4, 3.5, 0.86), Vector2(0.02, 0.02), steel))
	# Its eye: a lit band across the cowl, and a lamp under it.
	root.add_child(_strut(Vector3(-0.4, 2.48, -0.995), Vector3(0.4, 2.48, -0.995), Vector2(0.03, 0.02), seam))
	root.add_child(_box(Vector3(0.3, 0.06, 0.04), Vector3(0, 2.18, -1.0), lamp))
	return root


## A walker's leg, under its hip node: the thigh down and forward to the
## knee, the shin back to a raised heel, and a foot with toes forward and a
## spur back, flat on the ground `Vehicle.LEG_HIP` below the hip.
func _bird_leg(leg: Node3D, side: float) -> void:
	var knee := Vector3(0, -0.7, -0.38)
	var heel := Vector3(0, -1.36, 0.14)
	var ball := Vector3(0, -1.6, -0.1)
	leg.add_child(_strut(Vector3.ZERO, knee, Vector2(0.32, 0.36), paint))
	leg.add_child(_strut(Vector3(0, -0.06, -0.2), knee + Vector3(0, 0.04, -0.12), Vector2(0.26, 0.06), paint))  # thigh plate
	leg.add_child(_strut(Vector3(side * 0.17, -0.1, -0.12), Vector3(side * 0.17, -0.56, -0.36), Vector2(0.008, 0.024), seam))
	leg.add_child(_cyl(0.15, 0.15, 0.38, knee, steel, Vector3(0, 0, PI / 2.0), 16))
	leg.add_child(_strut(knee, heel, Vector2(0.24, 0.26), trim))
	leg.add_child(_strut(knee + Vector3(0, 0.0, 0.12), heel + Vector3(0, 0.12, 0.08), Vector2(0.05, 0.05), steel))  # piston
	leg.add_child(_cyl(0.1, 0.1, 0.3, heel, steel, Vector3(0, 0, PI / 2.0), 16))
	leg.add_child(_strut(heel, ball, Vector2(0.18, 0.18), paint))
	leg.add_child(_box(Vector3(0.44, 0.1, 0.36), Vector3(0, -1.7, -0.1), trim))  # sole
	for toe: float in [-0.12, 0.12]:
		var plate := _box(Vector3(0.14, 0.08, 0.36), Vector3(toe, -1.71, -0.4), trim)
		plate.rotation.y = -toe * 1.2
		leg.add_child(plate)
	leg.add_child(_box(Vector3(0.12, 0.08, 0.24), Vector3(0, -1.71, 0.16), trim))  # spur


# --- Jet -------------------------------------------------------------------------

func _jet() -> Node3D:
	var root := Node3D.new()
	# The fuselage: a needle nose, the cockpit tub cut into it and a spine
	# back to the engines.
	var body := PackedVector2Array([Vector2(-3.7, 0.98), Vector2(-3.2, 1.12), Vector2(-2.4, 1.28),
			Vector2(-1.95, 1.34), Vector2(-1.92, 0.86), Vector2(-0.14, 0.86), Vector2(-0.1, 1.4),
			Vector2(0.6, 1.56), Vector2(2.4, 1.5), Vector2(3.3, 1.32), Vector2(3.35, 0.78),
			Vector2(2.2, 0.6), Vector2(-1.4, 0.6), Vector2(-2.8, 0.74), Vector2(-3.7, 0.93)])
	_paneled(root, body, 1.0, 0.0, paint, [-2.6, 0.3, 1.8], 0.02)
	# The cockpit's walls, a dash with lit screens, the seat and the sticks.
	for side: float in [-1.0, 1.0]:
		_add(root, _extrude(PackedVector2Array([Vector2(-1.95, 0.86), Vector2(-1.95, 1.4), Vector2(-1.7, 1.52),
				Vector2(-0.1, 1.52), Vector2(-0.1, 0.86)]), 0.1, "x", paint), Vector3(side * 0.44, 0, 0))
		root.add_child(_strut(Vector3(side * 0.22, 0.92, -1.02), Vector3(side * 0.22, 1.45, -1.05), Vector2(0.04, 0.04), steel))
		root.add_child(_box(Vector3(0.05, 0.1, 0.05), Vector3(side * 0.22, 1.47, -1.05), trim))
		root.add_child(_box(Vector3(0.18, 0.04, 0.25), Vector3(side * 0.15, 0.88, -1.6), steel))  # pedal
		# A lit seam along each flank.
		root.add_child(_strut(Vector3(side * 0.503, 1.06, -3.0), Vector3(side * 0.503, 1.1, 2.6), Vector2(0.006, 0.026), seam))
	root.add_child(_box(Vector3(0.78, 0.26, 0.16), Vector3(0, 1.26, -1.85), trim))  # dash
	var screen := _glow(ENERGY, 1.2)
	var panel := _box(Vector3(0.5, 0.14, 0.01), Vector3(0, 1.3, -1.76), screen)
	panel.rotation.x = -0.4
	root.add_child(panel)
	_add(root, _extrude(RoundedPath.of([Vector2(-0.8, 1.06), Vector2(-0.8, 1.3), Vector2(-0.3, 1.3),
			Vector2(-0.18, 1.98), Vector2(-0.1, 1.98), Vector2(-0.18, 1.06)], 0.03), 0.5, "x", trim))  # seat
	# A teardrop canopy over the pilot, swept back from the windscreen,
	# clear so the pilot shows.
	var dome := _extrude(RoundedPath.of([Vector2(-2.0, 1.52), Vector2(-1.35, 2.18), Vector2(-0.85, 2.32),
			Vector2(-0.35, 2.22), Vector2(0.35, 1.53)], 0.18), 0.84, "x", glass)
	dome.name = "Canopy"
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dome)
	for side: float in [-1.0, 1.0]:
		root.add_child(_strut(Vector3(side * 0.44, 1.53, -2.0), Vector3(side * 0.44, 1.53, 0.04), Vector2(0.05, 0.03), trim))  # canopy rail
	# Delta wings, a lit tip on each, and canards by the nose.
	for side: float in [-1.0, 1.0]:
		var wing := _extrude(PackedVector2Array([Vector2(side * 0.48, -0.6), Vector2(side * 2.5, 1.55),
				Vector2(side * 2.55, 2.3), Vector2(side * 0.48, 2.25)]), 0.08, "y", paint)
		wing.position.y = 0.94
		root.add_child(wing)
		root.add_child(_strut(Vector3(side * 1.1, 0.985, 0.2), Vector3(side * 2.3, 0.985, 1.55), Vector2(0.02, 0.006), trim))
		root.add_child(_strut(Vector3(side * 2.53, 0.94, 1.6), Vector3(side * 2.56, 0.94, 2.28), Vector2(0.04, 0.1), seam))
		var canard := _extrude(PackedVector2Array([Vector2(side * 0.45, -2.75), Vector2(side * 1.0, -2.35),
				Vector2(side * 1.0, -2.15), Vector2(side * 0.45, -2.2)]), 0.05, "y", paint)
		canard.position.y = 1.0
		root.add_child(canard)
		# Twin fins, canted out.
		var fin := _extrude(RoundedPath.of([Vector2(1.95, 1.5), Vector2(2.85, 2.45), Vector2(3.3, 2.45),
				Vector2(3.32, 1.42)], 0.04), 0.06, "x", paint)
		fin.position = Vector3(side * 0.38, 0, 0)
		fin.rotation.z = -side * 0.3
		root.add_child(fin)
		# The engines: a nacelle each, a bell and a glowing nozzle.
		root.add_child(_cyl(0.24, 0.24, 1.8, Vector3(side * 0.32, 0.98, 2.5), trim, Vector3(PI / 2.0, 0, 0), 20))
		root.add_child(_cyl(0.2, 0.27, 0.22, Vector3(side * 0.32, 0.98, 3.48), steel, Vector3(PI / 2.0, 0, 0), 20))
		var nozzle := _cyl(0.19, 0.19, 0.02, Vector3(side * 0.32, 0.98, 3.58), energy, Vector3(PI / 2.0, 0, 0), 20)
		nozzle.name = "Engine" + ("L" if side < 0.0 else "R")
		root.add_child(nozzle)
		# Intakes beside the cockpit.
		root.add_child(_box(Vector3(0.14, 0.3, 0.9), Vector3(side * 0.56, 0.85, 0.1), trim))
		# Main gear.
		root.add_child(_strut(Vector3(side * 0.9, 0.94, 1.0), Vector3(side * 0.9, 0.18, 1.0), Vector2(0.08, 0.08), steel))
		var tyre := _cyl(0.18, 0.18, 0.14, Vector3(side * 0.9, 0.18, 1.0), trim, Vector3(0, 0, PI / 2.0), 20)
		root.add_child(tyre)
	root.add_child(_strut(Vector3(0, 0.75, -2.4), Vector3(0, 0.15, -2.4), Vector2(0.08, 0.08), steel))  # nose gear
	root.add_child(_cyl(0.15, 0.15, 0.12, Vector3(0, 0.15, -2.4), trim, Vector3(0, 0, PI / 2.0), 20))
	root.add_child(_box(Vector3(0.2, 0.06, 0.06), Vector3(0, 0.86, -3.5), lamp))
	return root


# --- Airship ---------------------------------------------------------------------

func _airship() -> Node3D:
	var root := Node3D.new()
	var length: float = v.body_size.z
	var radius := 4.0
	var mid := 4.5
	var along := Vector3(PI / 2.0, 0, 0)
	# The hull, banded with iron, a ram on its nose.
	root.add_child(_capsule(radius, length - 2.0, Vector3(0, mid, 0), paint, along))
	for z: float in [-0.3, -0.1, 0.12, 0.32]:
		root.add_child(_cyl(radius + 0.15, radius + 0.15, 0.6, Vector3(0, mid, z * length), trim, along, 24))
	root.add_child(_cyl(0.2, 2.2, 4.0, Vector3(0, mid - 0.6, -length * 0.5 - 0.6), steel, Vector3(-PI / 2.0, 0, 0)))
	# A lit seam down each flank.
	for side: float in [-1.0, 1.0]:
		root.add_child(_strut(Vector3(side * (radius + 0.02), mid, -length * 0.36),
				Vector3(side * (radius + 0.02), mid, length * 0.36), Vector2(0.06, 0.2), seam))
	# The gondola under it, its windows lit, a searchlight at its front.
	root.add_child(_box(Vector3(3.0, 1.6, 14.0), Vector3(0, 0.7, 1.0), trim))
	root.add_child(_box(Vector3(3.05, 0.3, 11.0), Vector3(0, 0.9, 1.0), _glow(Color(1.0, 0.7, 0.35), 1.6)))
	root.add_child(_box(Vector3(0.8, 0.5, 0.3), Vector3(0, 0.6, -6.1), lamp))
	# The bridge tower on its back, up to the turrets' seats (the highest).
	var roof := mid
	for seat: Dictionary in v.seats:
		roof = maxf(roof, (seat.offset as Vector3).y)
	var foot := mid + radius - 0.5
	root.add_child(_box(Vector3(4.5, roof - foot, 8.0), Vector3(0, (roof + foot) * 0.5, 0), paint))
	root.add_child(_box(Vector3(4.6, 0.4, 7.0), Vector3(0, roof - 1.2, 0), _glow(Color(1.0, 0.7, 0.35), 1.4)))
	# Four tail fins.
	var tail_z: float = length * 0.5 - 3.0
	root.add_child(_box(Vector3(0.5, 5.5, 5.0), Vector3(0, mid + radius + 1.5, tail_z), paint))
	root.add_child(_box(Vector3(0.5, 4.0, 5.0), Vector3(0, mid - radius - 0.6, tail_z), paint))
	root.add_child(_box(Vector3(radius * 2.0 + 6.0, 0.5, 4.5), Vector3(0, mid, tail_z), paint))
	# The weak spots, at their seats, each with a hot glow that reads from
	# far off as a place to shoot.
	var weak := _glow(Color(1.0, 0.42, 0.1), 2.6)
	for i in v.seats.size():
		var seat: Dictionary = v.seats[i]
		var kind := str(seat.get("piece", ""))
		if kind == "":
			continue
		var at: Vector3 = seat.offset
		var whole := Node3D.new()
		whole.name = "Part%d" % i
		whole.position = at
		var broken := Node3D.new()
		broken.name = "Broken%d" % i
		broken.position = at
		broken.visible = false
		whole.rotation.y = float(seat.get("turn", 0.0))
		broken.rotation.y = whole.rotation.y
		match kind:
			"pod":
				_airship_pod(whole, broken, weak)
				# The outrigger out to it from the hull, which stays.
				var side := signf(at.x)
				root.add_child(_strut(Vector3(side * (radius - 0.5), mid - 1.0, at.z),
						at + Vector3(-side * 1.0, 1.4, 0), Vector2(0.6, 0.9), trim))
			"plate":
				_airship_plate(whole, broken, weak)
			"turret":
				_airship_turret(whole, broken, weak)
		root.add_child(whole)
		root.add_child(broken)
	return root


## An engine pod: a long nacelle, a glowing ring at its back. Broken, a
## torn stub.
func _airship_pod(whole: Node3D, broken: Node3D, weak: Material) -> void:
	var along := Vector3(PI / 2.0, 0, 0)
	whole.add_child(_capsule(1.3, 5.6, Vector3(0, 1.4, 0), steel, along))
	whole.add_child(_cyl(1.34, 1.34, 0.35, Vector3(0, 1.4, 0.9), weak, along, 20))
	whole.add_child(_cyl(1.4, 1.4, 0.5, Vector3(0, 1.4, -1.2), trim, along, 20))
	whole.add_child(_cyl(1.1, 1.1, 0.15, Vector3(0, 1.4, 2.85), energy, along, 20))
	whole.add_child(_cyl(1.5, 1.5, 0.3, Vector3(0, 1.4, 2.6), trim, along, 20))
	broken.add_child(_cyl(1.0, 1.2, 1.6, Vector3(0, 1.4, -1.0), trim, along, 10))
	broken.add_child(_cyl(0.6, 0.6, 0.1, Vector3(0, 1.4, -0.15), tail, along, 10))


## A spine plate: an armoured ridge with lit seams over a glowing core.
## Broken, the core shows through torn armour.
func _airship_plate(whole: Node3D, broken: Node3D, weak: Material) -> void:
	whole.add_child(_box(Vector3(3.2, 1.2, 6.5), Vector3(0, 0.6, 0), steel))
	whole.add_child(_box(Vector3(2.0, 0.6, 5.6), Vector3(0, 1.4, 0), paint))
	# The core glows through the slats on top.
	for z: float in [-2.0, -0.7, 0.6, 1.9]:
		whole.add_child(_box(Vector3(1.6, 0.1, 0.35), Vector3(0, 1.72, z), weak))
	for side: float in [-1.0, 1.0]:
		whole.add_child(_box(Vector3(0.08, 0.12, 6.0), Vector3(side * 1.62, 0.9, 0), seam))
	broken.add_child(_box(Vector3(3.2, 0.4, 6.5), Vector3(0, 0.2, 0), trim))
	broken.add_child(_cyl(0.9, 1.1, 0.8, Vector3(0, 0.6, 0), tail))


## A turret: a ring, a dome and twin barrels. Broken, the empty ring.
func _airship_turret(whole: Node3D, broken: Node3D, weak: Material) -> void:
	whole.add_child(_cyl(1.4, 1.5, 0.7, Vector3(0, 0.35, 0), trim, Vector3.ZERO, 20))
	whole.add_child(_capsule(1.05, 2.1, Vector3(0, 1.2, 0), steel))
	whole.add_child(_box(Vector3(0.9, 0.18, 0.1), Vector3(0, 1.35, -1.02), weak))
	for side: float in [-1.0, 1.0]:
		whole.add_child(_strut(Vector3(side * 0.35, 1.35, -0.8), Vector3(side * 0.35, 1.35, -3.2),
				Vector2(0.22, 0.22), trim))
	whole.add_child(_box(Vector3(1.2, 0.12, 0.1), Vector3(0, 1.6, -1.0), seam))
	broken.add_child(_cyl(1.4, 1.5, 0.5, Vector3(0, 0.25, 0), trim, Vector3.ZERO, 12))


## Puts `part` (built in a frame of its own) into `root`, through `frame`.
static func _set_in(root: Node3D, frame: Transform3D, part: Node3D) -> void:
	part.transform = frame * part.transform
	root.add_child(part)


# --- Shared parts ----------------------------------------------------------------

## A wheel at `at` (axle along X): a dark tyre, a recessed rim face crossed
## by dark spokes (so its turning shows), a lit ring on each face and a
## steel hub. `out` pushes the outer ring out to the tyre's outside face when
## the wheel stands off-centre (0 lights both). It is a node of its own,
## "Wheel...", that the vehicle spins with its speed (`Vehicle._turn_parts`)
## and, with `steers`, turns with its steering; `Look` merges its pieces
## into a draw per material ("merge"). Returns it.
func _wheel_set(root: Node3D, at: Vector3, radius: float, width: float, ring_mat: Material, out: float,
		steers := false) -> Node3D:
	var wheel := Node3D.new()
	wheel.name = "Wheel%d" % root.get_child_count()
	wheel.position = at
	wheel.set_meta("radius", radius)
	wheel.set_meta("steers", steers)
	wheel.set_meta("merge", true)
	root.add_child(wheel)
	var side := Vector3(0, 0, PI / 2.0)
	# Everything round stays put (a draw for the dark tyre and rim face, one
	# for the lit rings); only the steel spokes and hub spin ("Spin", one
	# draw), which is all that shows the turning, and keeps the wheel's
	# bounds round, never a turned box's corners below the ground.
	wheel.add_child(_cyl(radius, radius, width, Vector3.ZERO, trim, side, 28))
	wheel.add_child(_cyl(radius * 0.7, radius * 0.7, width + 0.02, Vector3.ZERO, trim, side, 24))
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.set_meta("merge", true)
	wheel.add_child(spin)
	for i in 3:
		var spoke := _box(Vector3(width + 0.035, radius * 1.3, radius * 0.1), Vector3.ZERO, steel)
		spoke.rotation.x = i * PI / 3.0
		spin.add_child(spoke)
	spin.add_child(_cyl(radius * 0.3, radius * 0.3, width + 0.06, Vector3.ZERO, steel, side, 16))
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 0.62
	ring.outer_radius = radius * 0.7
	ring.rings = 24
	var faces: Array = [-1.0, 1.0] if out == 0.0 else [signf(out)]
	for face: float in faces:
		var node := MeshInstance3D.new()
		node.mesh = ring
		node.material_override = ring_mat
		node.rotation.z = PI / 2.0
		node.position = Vector3(face * (width * 0.5 + 0.012), 0, 0)
		wheel.add_child(node)
	return wheel


## A pivot for parts that turn with the steering (a bike's fork and bars, a
## hoverbike's bars, a rover's wheel, a tail fin): a node at `at` turning
## about `axis` (in the model's frame), by `share` of the steering. With
## `grips` the rider's hands are on it (`Vehicle.posed_grips`). Pieces go in
## with `_into`, which keeps them where they were built.
func _pivot(root: Node3D, node_name: String, at: Vector3, axis: Vector3, share: float, grips := false) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = at
	pivot.set_meta("axis", axis.normalized())
	pivot.set_meta("share", share)
	pivot.set_meta("grips", grips)
	pivot.set_meta("merge", true)
	root.add_child(pivot)
	return pivot


## Puts `part` (built in the model's frame) under `pivot`, where it was.
static func _into(pivot: Node3D, part: Node3D) -> Node3D:
	part.position -= pivot.position
	pivot.add_child(part)
	return part


## `outline` (a side profile, in z and y) as a shell `width` wide centred
## on `x`, cut across at each z in `cuts` into panels with a panel line
## between them; a dark frame shows through the lines. `bevel` chamfers
## each panel's edges.
func _paneled(root: Node3D, outline: PackedVector2Array, width: float, x: float, mat: Material,
		cuts: Array, bevel := 0.0) -> void:
	var at := Vector3(x, 0, 0)
	var pieces: Array[PackedVector2Array] = []
	if cuts.is_empty():
		pieces.append(outline)
	else:
		var edges: Array[float] = [-100.0]
		for c: float in cuts:
			edges.append(c)
		edges.append(100.0)
		for i in edges.size() - 1:
			var lo := edges[i] + (gap * 0.5 if i > 0 else 0.0)
			var hi := edges[i + 1] - (gap * 0.5 if i < edges.size() - 2 else 0.0)
			var band := PackedVector2Array([Vector2(lo, -100), Vector2(hi, -100), Vector2(hi, 100), Vector2(lo, 100)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(outline, band):
				pieces.append(piece)
		var core := Geometry2D.offset_polygon(outline, -groove)
		if not core.is_empty():
			_add(root, _extrude(core[0], width - groove * 2.0, "x", trim), at)
	for piece in pieces:
		if bevel <= 0.0:
			_add(root, _extrude(piece, width, "x", mat), at)
			continue
		_add(root, _extrude(piece, width - bevel * 2.0, "x", mat), at)
		var inset := Geometry2D.offset_polygon(piece, -bevel)
		if not inset.is_empty():
			_add(root, _extrude(inset[0], width, "x", mat), at)


## A plate cut to `outline` and `thickness` deep, centred on its middle
## plane. `axis` is the way it is extruded: "x" takes the outline as (z, y),
## a side profile; "y" as (x, z), a deck or a wing; "z" as (x, y).
func _extrude(outline: PackedVector2Array, thickness: float, axis: String, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := thickness * 0.5
	var tris := Geometry2D.triangulate_polygon(outline)
	# Every face is wound both ways, so the plate shows from either side
	# whatever way the axes turn it; the extra copies sit inside, unseen.
	var ccw := not Geometry2D.is_polygon_clockwise(outline)
	for face: float in [1.0, -1.0]:
		st.set_normal(_lift(Vector2.ZERO, face, axis))
		for i in range(0, tris.size(), 3):
			for k: int in [0, 1, 2, 0, 2, 1]:
				st.add_vertex(_lift(outline[tris[i + k]], half * face, axis))
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var edge := (b - a).normalized()
		var out := Vector2(edge.y, -edge.x) if ccw else Vector2(-edge.y, edge.x)
		st.set_normal(_lift(out, 0.0, axis))
		var a0 := _lift(a, -half, axis)
		var a1 := _lift(a, half, axis)
		var b0 := _lift(b, -half, axis)
		var b1 := _lift(b, half, axis)
		for p: Vector3 in [a0, b1, b0, a0, a1, b1, a0, b0, b1, a0, b1, a1]:
			st.add_vertex(p)
	var part := MeshInstance3D.new()
	part.mesh = st.commit()
	_paint(part, mat)
	return part


## A point of an outline on `axis`'s plane, `w` along the axis.
static func _lift(p: Vector2, w: float, axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3(w, p.y, p.x)
		"y":
			return Vector3(p.x, w, p.y)
	return Vector3(p.x, p.y, w)


## An annulus sector in an outline's plane round `centre`, from angle `a0`
## to `a1` (0 along the first axis, PI/2 along the second).
static func _arc(centre: Vector2, inner: float, outer: float, a0: float, a1: float, steps := 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		out.append(centre + Vector2(cos(a), sin(a)) * outer)
	for i in steps + 1:
		var a := lerpf(a1, a0, float(i) / steps)
		out.append(centre + Vector2(cos(a), sin(a)) * inner)
	return out


## A box `size.x` by `size.y` across, run from `a` to `b`.
func _strut(a: Vector3, b: Vector3, size: Vector2, mat: Material) -> MeshInstance3D:
	var along := b - a
	var part := _box(Vector3(size.x, size.y, along.length()), (a + b) * 0.5, mat)
	var up := Vector3.UP if absf(along.normalized().y) < 0.95 else Vector3.BACK
	part.basis = Basis.looking_at(along, up)
	return part


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	_paint(part, mat)
	return part


## A cylinder standing on Y, turned by `rot` (Euler).
func _cyl(top: float, bottom: float, height: float, at: Vector3, mat: Material, rot := Vector3.ZERO, sides := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = rot
	_paint(part, mat)
	return part


## A capsule standing on Y (`height` end to end), turned by `rot` (Euler).
func _capsule(radius: float, height: float, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 16
	mesh.rings = 4
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = rot
	_paint(part, mat)
	return part


## Lit materials (seams, thrusters) and glass go on as overrides, which
## `Look` leaves alone (it weathers only what is on the mesh, which would
## turn glass opaque); the rest go on the mesh, for `Look` to weather.
func _paint(part: MeshInstance3D, mat: Material) -> void:
	if mat == seam or mat == energy or mat == tail or mat == glass or (mat is StandardMaterial3D
			and mat.emission_enabled and mat != lamp):
		part.material_override = mat
	elif part.mesh is PrimitiveMesh:
		(part.mesh as PrimitiveMesh).material = mat
	elif part.mesh is ArrayMesh:
		(part.mesh as ArrayMesh).surface_set_material(0, mat)


static func _add(root: Node3D, part: Node3D, at := Vector3.ZERO) -> void:
	part.position += at
	root.add_child(part)


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _glow(color: Color, strength: float) -> StandardMaterial3D:
	var mat := _mat(color.lightened(0.2), 0.4, 0.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = strength
	return mat


## Outlines with their corners rounded off a little, so a seat or a fin
## reads as made, not cut from a box.
class RoundedPath:
	static func of(points: Array, radius: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		var n := points.size()
		for i in n:
			var p: Vector2 = points[i]
			var prev: Vector2 = points[(i + n - 1) % n] - p
			var next: Vector2 = points[(i + 1) % n] - p
			var cut := minf(radius, minf(prev.length(), next.length()) * 0.4)
			out.append(p + prev.normalized() * cut)
			out.append(p + (prev.normalized() + next.normalized()) * cut * 0.3)
			out.append(p + next.normalized() * cut)
		return out
