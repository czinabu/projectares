extends RefCounted
## The helmet models, one per visor `mode` (see `Visor`), built in code like
## every greybox shape and worn the same in every view (first person leaves
## it out with the head, `ActorSkin.hide_head`; never a copy of its own).
## Used through `ActorSkin.build_helmet`.
##
## Every helmet is the same few layers, so each design is only its shape and
## its fitting (DESIGN.md "Helmets"):
## - a dark hood over the whole head (the head is hidden under a helmet), so
##   an open face reads as a balaclava, never as a hole;
## - a shell: an ellipsoid cap cut along a rim line (`Style.rim`), high over
##   the ears on a light helmet, low round the jaw on a closed one;
## - the glass in the visor's colour, the wearer's display;
## - the mode's fitting, which shows what it does: a rangefinder pod
##   (zoom), an emitter crown (scan), sensor eyes all round (threat), a
##   thermal lens and heat sinks (thermal).
## Goggles (DESIGN.md "Goggles") will be the same glass and fitting on a
## strap round the hood, with no shell.
## Front is -Z; the middle of the head is the origin.

## How far the glass glows: lit enough to read as a powered display, never
## so bright it reads as a lamp.
const GLASS_GLOW := 0.45
## A Mk2 helmet's trim: a lit seam along the crown in the glass colour.
const TRIM_GLOW := 1.4
## How much smaller than the head's measure the shell is drawn, so a helmet
## sits on a head rather than round it like a bowl.
const FIT := 0.94

## The shape every surface of the helmet being built follows (see `Shape`),
## set for each design by `build`.
static var _shape := Shape.new()


## How one design bends the ellipsoid its plates lie on, so each helmet has
## an outline of its own: `flat` flattens the front, `sweep` draws the back
## out and down, `bulk` widens the sides, `ridge` raises a crest along the
## middle, `facets` cuts it into that many flat faces round.
class Shape:
	var flat := 0.0
	var sweep := 0.0
	var bulk := 0.0
	var ridge := 0.0
	var crown := 1.0
	var facets := 0

	static func of(mode: String) -> Shape:
		var s := Shape.new()
		match mode:
			"zoom":
				# Low and flat: a high-cut recon shell.
				s.crown = 0.82
				s.flat = 0.12
			"scan":
				# A smooth egg swept back.
				s.sweep = 0.3
				s.crown = 1.04
				s.flat = 0.08
			"threat":
				# Angular plates with a crest.
				s.facets = 10
				s.ridge = 0.1
				s.flat = 0.15
			"thermal":
				# Broad over the ears, where the heat sinks are.
				s.bulk = 0.12
				s.crown = 0.92
				s.flat = 0.1
			"":
				s.crown = 0.9
				s.flat = 0.06
		return s


## The helmet for `mode`, its glass lit in `glass`, sized round a head of
## `size`, in `shell_color` (each design tints it its own way). `tier` 2
## adds the Mk2 trim.
static func build(mode: String, glass: Color, size: Vector3, shell_color: Color, tier := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "HelmetModel"
	var r := size * 0.5 * FIT
	var kit := Kit.new(mode, glass, shell_color)
	_shape = Shape.of(mode)
	_hood(root, r, kit)
	match mode:
		"slit":
			_closed_helm(root, size, kit)
		"zoom":
			_spotter(root, r, kit)
		"scan":
			_seeker(root, r, kit)
		"threat":
			_warden(root, r, kit)
		"thermal":
			_ember(root, r, kit)
		_:
			_scav(root, r, kit)
	if tier >= 2 and mode != "slit" and mode != "":
		# A lit seam from the brow over the crown to the nape.
		_piece_mesh(root, "Mk2Trim", _surface(r.x * 1.075, r.y * 1.075, r.z * 1.075, -0.035, 0.035,
				[[0.0, r.y * 0.55]], [[0.0, r.y * 1.08]], 0.004, 2, 6), kit.trim)
		_piece_mesh(root, "Mk2TrimBack", _surface(r.x * 1.075, r.y * 1.075, r.z * 1.075, PI - 0.035, PI + 0.035,
				[[0.0, r.y * 0.35]], [[0.0, r.y * 1.08]], 0.004, 2, 6), kit.trim)
	_shape = Shape.new()
	return root


## The materials one helmet is made of.
class Kit:
	var shell: StandardMaterial3D
	var plate: StandardMaterial3D
	var dark: StandardMaterial3D
	var hood: StandardMaterial3D
	var glass: StandardMaterial3D
	var lit: StandardMaterial3D
	var trim: StandardMaterial3D
	var colour: Color

	func _init(mode: String, glass_color: Color, base: Color) -> void:
		colour = glass_color
		# Each design wears its own tone of the shell colour.
		var tone: Color = {
			"": Color(0.42, 0.33, 0.24),
			"zoom": Color(0.42, 0.39, 0.31),
			"scan": Color(0.3, 0.36, 0.35),
			"threat": Color(0.26, 0.3, 0.37),
			"thermal": Color(0.3, 0.27, 0.25),
		}.get(mode, base)
		var tinted := base.lerp(tone, 0.6)
		shell = _mat(tinted, 0.72, 0.15)
		plate = _mat(tinted.lightened(0.12), 0.62, 0.25)
		dark = _mat(Color(0.07, 0.075, 0.08), 0.75, 0.1)
		hood = _mat(Color(0.05, 0.05, 0.055), 0.95, 0.0)
		glass = _mat(glass_color.darkened(0.85), 0.05, 0.8)
		glass.emission_enabled = true
		glass.emission = glass_color.darkened(0.2)
		glass.emission_energy_multiplier = GLASS_GLOW if mode != "" else 0.18
		lit = _mat(glass_color.darkened(0.3), 0.2, 0.0)
		lit.emission_enabled = true
		lit.emission = glass_color
		lit.emission_energy_multiplier = 1.8
		trim = _mat(glass_color.darkened(0.3), 0.2, 0.0)
		trim.emission_enabled = true
		trim.emission = glass_color
		trim.emission_energy_multiplier = TRIM_GLOW

	static func _mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = rough
		mat.metallic = metal
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat


## The hood and the neck under every helmet.
static func _hood(root: Node3D, r: Vector3, kit: Kit) -> void:
	_piece_mesh(root, "Hood", _surface(r.x * 0.93, r.y * 0.95, r.z * 0.92, -PI, PI, [[0.0, -r.y * 0.97]],
			[[0.0, r.y * 0.98]], 0.004, 24, 10), kit.hood).position = Vector3(0, -r.y * 0.1, r.z * 0.02)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.5
	neck.bottom_radius = 0.55
	neck.height = 1.0
	_piece(root, "Neck", neck, kit.hood, Vector3(0, -r.y * 0.98, r.z * 0.12),
			Vector3(r.x * 1.15, r.y * 0.45, r.z * 1.15))


## The cap of the helmet: the ellipsoid above the rim line `rim` ([angle
## from the front, height] keys, mirrored both sides).
## A lip runs round the rim, a little proud of the shell, so the edge reads.
static func _cap(root: Node3D, r: Vector3, rim: Array, mat: Material, grow := 1.0) -> MeshInstance3D:
	var cap := _piece_mesh(root, "Shell", _surface(r.x * grow, r.y * grow, r.z * grow, -PI, PI, rim,
			[[0.0, r.y * grow]], 0.007, 40, 9), mat)
	var lip_low := []
	var lip_high := []
	for key: Array in rim:
		lip_low.append([key[0], float(key[1]) - 0.002])
		lip_high.append([key[0], float(key[1]) + 0.016])
	var lip := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
	lip.albedo_color = lip.albedo_color.darkened(0.35)
	_piece_mesh(root, "Lip", _surface(r.x * grow * 1.05, r.y * grow * 1.05, r.z * grow * 1.05, -PI, PI,
			lip_low, lip_high, 0.006, 40, 1), lip)
	return cap


## Scav Visor: a scrap pot. Welded from mismatched patch plates with rivets,
## a cracked visor bolted down over the eyes on two hinge bolts, tape and a
## loop of wire. Dim: it shows only how hurt you are.
static func _scav(root: Node3D, r: Vector3, kit: Kit) -> void:
	_cap(root, r, [[0.0, r.y * 0.25], [1.1, -r.y * 0.25], [PI, -r.y * 0.45]], kit.shell)
	var patches := [
		[-0.55, 0.15, r.y * 0.3, r.y * 0.85, Color(0.33, 0.3, 0.24)],
		[0.9, 1.55, -r.y * 0.1, r.y * 0.55, Color(0.45, 0.24, 0.16)],
		[2.3, 3.0, 0.0, r.y * 0.7, Color(0.28, 0.3, 0.27)],
		[-2.1, -1.4, -r.y * 0.25, r.y * 0.3, Color(0.4, 0.35, 0.28)],
	]
	for i in patches.size():
		var p: Array = patches[i]
		var mat := Kit._mat(p[4], 0.85, 0.25)
		_piece_mesh(root, "Patch%d" % i, _surface(r.x * 1.07, r.y * 1.07, r.z * 1.07, p[0], p[1],
				[[0.0, p[2]]], [[0.0, p[3]]], 0.006, 4, 3), mat)
		# Rivets at the corners of each patch.
		for a: float in [p[0] + 0.06, p[1] - 0.06]:
			for h: float in [p[2] + 0.012, p[3] - 0.012]:
				_stud(root, "Rivet", _on_ellipsoid(r * 1.11, a, h), 0.007, kit.dark)
	# The visor: a cracked half band over the eyes.
	var g := _piece_mesh(root, "Glass", _surface(r.x * 1.1, r.y * 1.1, r.z * 1.1, -1.0, 1.0,
			[[0.0, -r.y * 0.42], [0.8, -r.y * 0.3]], [[0.0, r.y * 0.2], [0.8, r.y * 0.14]], 0.006, 16, 3), kit.glass)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its frame along the top, and the hinge bolts at the temples.
	_piece_mesh(root, "VisorFrame", _surface(r.x * 1.12, r.y * 1.12, r.z * 1.12, -1.05, 1.05,
			[[0.0, r.y * 0.17]], [[0.0, r.y * 0.3]], 0.008, 16, 2), kit.dark)
	for side: float in [-1.0, 1.0]:
		var bolt := _round(root, "Hinge", _on_ellipsoid(r * 1.12, side * 1.12, -r.y * 0.05), 0.022, 0.03, kit.plate)
		bolt.rotation.z = PI * 0.5
	var crack := _piece(root, "Crack", BoxMesh.new(), Kit._mat(Color(0.9, 0.85, 0.7), 0.3, 0.0),
			_on_ellipsoid(r * 1.13, 0.3, -r.y * 0.12), Vector3(r.x * 0.5, 0.004, 0.004))
	crack.rotation = Vector3(0, -0.3, 0.55)
	var crack2 := _piece(root, "Crack2", BoxMesh.new(), crack.mesh.material,
			_on_ellipsoid(r * 1.13, 0.45, -r.y * 0.05), Vector3(r.x * 0.22, 0.004, 0.004))
	crack2.rotation = Vector3(0, -0.45, -0.7)
	# A strip of tape over the left side, and a loop of wire behind the ear.
	var tape := _piece(root, "Tape", BoxMesh.new(), Kit._mat(Color(0.55, 0.52, 0.42), 0.95, 0.0),
			_on_ellipsoid(r * 1.08, -1.25, r.y * 0.45), Vector3(0.012, 0.09, 0.03))
	tape.rotation = Vector3(0.35, -1.25, 0)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	var wire := _piece(root, "Wire", torus, Kit._mat(Color(0.6, 0.35, 0.18), 0.4, 0.8),
			_on_ellipsoid(r * 1.07, 1.9, -r.y * 0.3), Vector3(0.06, 0.06, 0.06))
	wire.rotation = Vector3(0.3, 0, PI * 0.5)


## Spotter: a high-cut recon helmet with a rangefinder pod. A low shell cut
## up over the ears, rails along its sides, a comms headset in the cutouts
## (an antenna on the left), and over the right eye an articulated arm off
## the brow mount holding twin lens barrels (4x and 8x), whose glass is the
## glint people see. A narrow amber strip of glass under it.
static func _spotter(root: Node3D, r: Vector3, kit: Kit) -> void:
	_cap(root, r, [[0.0, r.y * 0.28], [0.8, r.y * 0.12], [1.05, r.y * 0.35], [1.55, r.y * 0.35],
			[1.85, -r.y * 0.15], [PI, -r.y * 0.38]], kit.shell)
	# Rails along each side, above the cutout.
	for side: float in [-1.0, 1.0]:
		var rail := _piece_mesh(root, "Rail", _surface(r.x * 1.09, r.y * 1.09, r.z * 1.09,
				side * 1.65 - 0.35, side * 1.65 + 0.35,
				[[0.0, r.y * 0.38]], [[0.0, r.y * 0.5]], 0.012, 6, 1), kit.dark)
		rail.position.x += side * 0.002
		# The headset cup in the cutout.
		var cup := _round(root, "EarCup", Vector3(side * r.x * 1.05, -r.y * 0.12, r.z * 0.02), 0.048, 0.035, kit.dark)
		cup.rotation.z = PI * 0.5
		var cap := _round(root, "EarCap", Vector3(side * (r.x * 1.05 + 0.018), -r.y * 0.12, r.z * 0.02), 0.034,
				0.006, kit.plate)
		cap.rotation.z = PI * 0.5
	var antenna := _round(root, "Antenna", Vector3(-r.x * 1.12, r.y * 0.35, r.z * 0.25), 0.004, 0.22, kit.dark)
	antenna.rotation.x = -0.35
	_stud(root, "AntennaTip", antenna.position + Vector3(0, 0.11, 0.04), 0.007, kit.lit)
	# The mount on the brow, the arm and the pod over the right eye.
	var mount := _piece(root, "Mount", BoxMesh.new(), kit.dark, Vector3(0, r.y * 0.38, -r.z * 0.880),
			Vector3(0.05, 0.035, 0.022))
	mount.rotation.x = -0.35
	var arm := _piece(root, "Arm", BoxMesh.new(), kit.plate, Vector3(r.x * 0.22, r.y * 0.2, -r.z * 0.986),
			Vector3(0.05, 0.012, 0.02))
	arm.rotation.z = -0.5
	var pod := _piece(root, "Pod", BoxMesh.new(), kit.plate, Vector3(r.x * 0.38, -r.y * 0.02, -r.z * 1.030),
			Vector3(0.075, 0.048, 0.06))
	pod.rotation.y = -0.15
	_piece(root, "PodTop", BoxMesh.new(), kit.dark, pod.position + Vector3(0, 0.027, 0.005),
			Vector3(0.06, 0.008, 0.045))
	for i in 2:
		var at := pod.position + Vector3(-0.016 + 0.034 * i, 0.0, -0.035 - 0.01 * (1 - i))
		var radius := 0.018 - 0.006 * i
		var barrel := _round(root, "Lens%d" % i, at, radius, 0.035 + 0.02 * (1 - i), kit.dark)
		barrel.rotation.x = PI * 0.5
		var lens := _round(root, "LensGlass%d" % i, at + Vector3(0, 0, -0.019 - 0.01 * (1 - i)),
				radius * 0.8, 0.003, kit.lit)
		lens.rotation.x = PI * 0.5
	# The laser rangefinder's emitter on top of the pod.
	_stud(root, "Ranger", pod.position + Vector3(0.03, 0.03, -0.025), 0.006,
			Kit._mat(Color(1.0, 0.2, 0.15), 0.3, 0.0))
	var g := _piece_mesh(root, "Glass", _surface(r.x * 1.06, r.y * 1.06, r.z * 1.06, -0.85, 0.85,
			[[0.0, -r.y * 0.3]], [[0.0, r.y * 0.12], [0.85, r.y * 0.2]], 0.006, 14, 2), kit.glass)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A mesh face guard over the mouth.
	_piece_mesh(root, "Mask", _surface(r.x * 1.02, r.y * 1.02, r.z * 1.04, -0.9, 0.9,
			[[0.0, -r.y * 0.9], [0.9, -r.y * 0.7]], [[0.0, -r.y * 0.4], [0.9, -r.y * 0.3]], 0.01, 12, 3), kit.dark)


## Seeker: a scanner. A rounded shell with a full wraparound band of glass,
## an emitter ring on the crown that the pulse comes from, a sensor fin
## running back from it with a lit edge, sensor nodes on the temples and
## two antenna whips off the back.
static func _seeker(root: Node3D, r: Vector3, kit: Kit) -> void:
	_cap(root, r, [[0.0, r.y * 0.2], [1.2, -r.y * 0.45], [PI, -r.y * 0.6]], kit.shell)
	var g := _piece_mesh(root, "Glass", _surface(r.x * 1.06, r.y * 1.06, r.z * 1.06, -1.75, 1.75,
			[[0.0, -r.y * 0.26], [1.5, -r.y * 0.12]], [[0.0, r.y * 0.17], [1.5, r.y * 0.1]], 0.007, 24, 3), kit.glass)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A lit line along the foot of the glass, the scanner's band.
	_piece_mesh(root, "GlassEdge", _surface(r.x * 1.075, r.y * 1.075, r.z * 1.075, -1.7, 1.7,
			[[0.0, -r.y * 0.29], [1.5, -r.y * 0.15]], [[0.0, -r.y * 0.25], [1.5, -r.y * 0.11]], 0.004, 24, 1), kit.lit)
	# A brow band over the glass.
	_piece_mesh(root, "Brow", _surface(r.x * 1.08, r.y * 1.08, r.z * 1.08, -1.8, 1.8,
			[[0.0, r.y * 0.16]], [[0.0, r.y * 0.3]], 0.01, 24, 2), kit.plate)
	# The jaw: a smooth guard under the glass.
	_piece_mesh(root, "Jaw", _surface(r.x * 1.03, r.y * 1.03, r.z * 1.05, -1.3, 1.3,
			[[0.0, -r.y * 0.88], [1.3, -r.y * 0.55]], [[0.0, -r.y * 0.36], [1.3, -r.y * 0.25]], 0.012, 16, 3), kit.shell)
	# The emitter on the crown: a housing, a lit ring and a dome over it.
	var crown := Vector3(0, r.y * 0.97, r.z * 0.05)
	_round(root, "Emitter", crown, 0.06, 0.02, kit.dark)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.82
	ring.outer_radius = 1.0
	_piece(root, "EmitterRing", ring, kit.lit, crown + Vector3(0, 0.011, 0), Vector3(0.052, 0.05, 0.052))
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 1.0
	_piece(root, "EmitterDome", dome, kit.plate, crown + Vector3(0, 0.012, 0), Vector3(0.06, 0.03, 0.06))
	# The fin from the emitter back over the crown.
	var fin := _piece(root, "Fin", BoxMesh.new(), kit.plate, Vector3(0, r.y * 0.88, r.z * 0.62),
			Vector3(0.016, 0.04, r.z * 0.75))
	fin.rotation.x = 0.55
	var edge := _piece(root, "FinEdge", BoxMesh.new(), kit.lit, fin.position + Vector3(0, 0.022, 0.012),
			Vector3(0.019, 0.005, r.z * 0.6))
	edge.rotation.x = 0.55
	# Sensor nodes at the temples, and antenna whips off the back.
	for side: float in [-1.0, 1.0]:
		var node := _round(root, "Sensor", _on_ellipsoid(r * 1.07, side * 1.6, r.y * 0.4), 0.026, 0.024, kit.dark)
		node.rotation.z = PI * 0.5
		var eye := _round(root, "SensorGlass", _on_ellipsoid(r * 1.07, side * 1.6, r.y * 0.4)
				+ Vector3(side * 0.013, 0, 0), 0.016, 0.003, kit.lit)
		eye.rotation.z = PI * 0.5
		var whip := _round(root, "Whip", Vector3(side * r.x * 0.55, r.y * 0.85, r.z * 0.85), 0.0035, 0.2, kit.dark)
		whip.rotation = Vector3(0.75, 0, -side * 0.25)


## Warden: a closed tactical helmet that watches every side. A full shell
## down round the jaw, a mandible guard, a heavy brow over a narrow visor
## slit, cheek plates, and sensor eyes in a row back along each side of the
## visor and one high on the back: Threat Sense sees who aims at you.
static func _warden(root: Node3D, r: Vector3, kit: Kit) -> void:
	_cap(root, r, [[0.0, r.y * 0.25], [0.95, r.y * 0.1], [1.2, -r.y * 0.75], [PI, -r.y * 0.75]], kit.shell)
	# The visor: set back under the brow, a narrow wide slit.
	var g := _piece_mesh(root, "Glass", _surface(r.x * 1.0, r.y * 1.0, r.z * 1.02, -1.0, 1.0,
			[[0.0, -r.y * 0.24], [1.0, -r.y * 0.1]], [[0.0, r.y * 0.25], [1.0, r.y * 0.12]], 0.006, 16, 2), kit.glass)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The mandible: a faceted guard over the mouth and jaw, a chin ridge.
	_piece_mesh(root, "Mandible", _surface(r.x * 1.1, r.y * 1.08, r.z * 1.12, -1.2, 1.2,
			[[0.0, -r.y * 0.95], [1.2, -r.y * 0.6]], [[0.0, -r.y * 0.24], [1.0, -r.y * 0.1], [1.2, -r.y * 0.1]],
			0.016, 10, 4), kit.plate)
	_piece(root, "Chin", BoxMesh.new(), kit.dark, Vector3(0, -r.y * 0.62, -r.z * 0.994), Vector3(0.03, 0.06, 0.02))
	for i in 3:
		_piece(root, "Vent", BoxMesh.new(), kit.dark, Vector3(0, -r.y * (0.42 + 0.11 * i), -r.z * 1.18 + 0.004 * i),
				Vector3(0.06 - 0.008 * i, 0.006, 0.01))
	# The brow, overhanging the visor, swept back at the sides.
	_piece_mesh(root, "Brow", _surface(r.x * 1.13, r.y * 1.1, r.z * 1.16, -1.25, 1.25,
			[[0.0, r.y * 0.24], [1.25, r.y * 0.12]], [[0.0, r.y * 0.42], [1.25, r.y * 0.26]], 0.02, 14, 2), kit.plate)
	for side: float in [-1.0, 1.0]:
		# A cheek plate over the side of the mandible.
		_piece_mesh(root, "Cheek", _surface(r.x * 1.16, r.y * 1.1, r.z * 1.12, side * 1.05 - 0.25, side * 1.05 + 0.25,
				[[0.0, -r.y * 0.75]], [[0.0, -r.y * 0.2]], 0.016, 4, 3), kit.dark)
		# Sensor eyes back along the side.
		for i in 3:
			var a := side * (1.05 + 0.26 * i)
			var eye := _round(root, "SensorEye", _on_ellipsoid(r * 1.06, a, r.y * 0.05), 0.011 - 0.002 * i, 0.012,
					kit.lit)
			eye.basis = Basis(Quaternion(Vector3.UP, eye.position.normalized()))
	# One eye on the back, high, over the vitals strip.
	var back := _round(root, "RearEye", _on_ellipsoid(r * 1.04, PI, r.y * 0.62), 0.014, 0.014, kit.lit)
	back.rotation.x = PI * 0.5 - 0.6
	_piece(root, "RearHousing", BoxMesh.new(), kit.dark, _on_ellipsoid(r * 1.0, PI, r.y * 0.62),
			Vector3(0.05, 0.03, 0.02))


## Ember: thermal. A dark shell with a thermal lens out front (deep glass
## in a ringed housing over a smoked visor), stacked heat sinks over each
## ear glowing where they meet the shell, and a respirator: it runs hot.
static func _ember(root: Node3D, r: Vector3, kit: Kit) -> void:
	_cap(root, r, [[0.0, r.y * 0.3], [1.1, -r.y * 0.35], [PI, -r.y * 0.55]], kit.shell)
	var smoke := Kit._mat(kit.colour.darkened(0.85), 0.05, 0.7)
	smoke.emission_enabled = true
	smoke.emission = kit.colour
	smoke.emission_energy_multiplier = 0.25
	var g := _piece_mesh(root, "Glass", _surface(r.x * 1.05, r.y * 1.05, r.z * 1.05, -1.05, 1.05,
			[[0.0, -r.y * 0.32], [1.0, -r.y * 0.2]], [[0.0, r.y * 0.25], [1.0, r.y * 0.16]], 0.006, 16, 2), smoke)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The respirator: a guard over the mouth and a filter on each side.
	_piece_mesh(root, "Respirator", _surface(r.x * 1.06, r.y * 1.05, r.z * 1.1, -1.0, 1.0,
			[[0.0, -r.y * 0.98], [1.0, -r.y * 0.65]], [[0.0, -r.y * 0.32], [1.0, -r.y * 0.25]], 0.014, 12, 4),
			kit.plate)
	var filter := _round(root, "Filter", Vector3(0, -r.y * 0.72, -r.z * 1.008), 0.032, 0.04, kit.dark)
	filter.rotation.x = PI * 0.5 - 0.5
	for i in 3:
		var slot := _round(root, "FilterRing", filter.position + Vector3(0, -0.008 * i, -0.012 * i) * 0.0
				+ Vector3(0, 0.01 - 0.01 * i, -0.004), 0.034, 0.004, kit.plate)
		slot.rotation.x = filter.rotation.x
	# The lens: a ringed housing out over the visor, the glass deep in it.
	var at := Vector3(0, -r.y * 0.02, -r.z * 1.008)
	var housing := _round(root, "Lens", at, 0.04, 0.05, kit.dark)
	housing.rotation.x = PI * 0.5
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 1.0
	var ring := _piece(root, "LensRing", torus, kit.plate, at + Vector3(0, 0, -0.026), Vector3(0.045, 0.04, 0.045))
	ring.rotation.x = PI * 0.5
	var eye := _round(root, "LensGlass", at + Vector3(0, 0, -0.022), 0.027, 0.004, kit.lit)
	eye.rotation.x = PI * 0.5
	# Heat sinks over the ears: fins stacked up the side, lit at the root.
	for side: float in [-1.0, 1.0]:
		_piece(root, "SinkGlow", BoxMesh.new(), kit.lit, Vector3(side * r.x * 1.13, -r.y * 0.05, r.z * 0.1),
				Vector3(0.006, 0.1, 0.075))
		for i in 5:
			var fin := _piece(root, "Sink", BoxMesh.new(), kit.dark,
					Vector3(side * r.x * 1.2, -r.y * 0.3 + i * 0.022, r.z * 0.1), Vector3(0.03, 0.006, 0.09))
			fin.rotation.y = side * 0.1
	# A vent down the back of the crown.
	for i in 3:
		_piece(root, "Vent", BoxMesh.new(), kit.dark, _on_ellipsoid(r * 1.01, PI, r.y * (0.55 + 0.12 * i)),
				Vector3(0.07, 0.006, 0.012))


## An exo trooper's closed helmet: a faceplate over the whole front, one
## narrow slit lit across the eyes, a heavy brow over it, cheek guards and a
## jaw plate.
static func _closed_helm(root: Node3D, size: Vector3, kit: Kit) -> void:
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 1.0
	_piece(root, "Shell", dome, kit.shell, Vector3.ZERO, size)
	var slit := Kit._mat(kit.colour.darkened(0.3), 0.2, 0.0)
	slit.emission_enabled = true
	slit.emission = kit.colour
	slit.emission_energy_multiplier = 1.4
	_piece(root, "Faceplate", dome, kit.plate, Vector3(0, -size.y * 0.06, -size.z * 0.1),
			Vector3(size.x * 0.98, size.y * 0.66, size.z * 0.86))
	_piece(root, "Slit", BoxMesh.new(), slit, Vector3(0, size.y * 0.02, -size.z * 0.52),
			Vector3(size.x * 0.62, size.y * 0.07, 0.02))
	_piece(root, "Brow", BoxMesh.new(), kit.plate, Vector3(0, size.y * 0.12, -size.z * 0.46),
			Vector3(size.x * 0.92, 0.04, 0.07))
	_piece(root, "Jaw", BoxMesh.new(), kit.plate, Vector3(0, -size.y * 0.3, -size.z * 0.38),
			Vector3(size.x * 0.6, 0.07, 0.1))
	for side: float in [-1.0, 1.0]:
		var cheek := _piece(root, "Cheek", BoxMesh.new(), kit.plate,
				Vector3(side * size.x * 0.42, -size.y * 0.16, -size.z * 0.26), Vector3(0.035, 0.12, 0.13))
		cheek.rotation.y = side * 0.45


## A point on the ellipsoid of radii `r` at `angle` round from the front
## (toward +X) and `height` up.
static func _on_ellipsoid(r: Vector3, angle: float, height: float) -> Vector3:
	var f := _shape.facets
	if f > 0:
		# Flat faces: the point lies on the chord between the corners either side.
		var step := TAU / f
		var a0 := floorf((angle + step * 0.5) / step) * step - step * 0.5
		var t := (angle - a0) / step
		return _shaped(r, a0, height).lerp(_shaped(r, a0 + step, height), t)
	return _shaped(r, angle, height)


## A point on the ellipsoid bent by `_shape`.
static func _shaped(r: Vector3, angle: float, height: float) -> Vector3:
	var ry := r.y * (_shape.crown if height > 0.0 else 1.0)
	var lat := asin(clampf(height / r.y, -0.999, 0.999))
	var c := cos(lat)
	var at := Vector3(r.x * c * sin(angle), ry * sin(lat), -r.z * c * cos(angle))
	var front := maxf(0.0, cos(angle))
	if at.z < 0.0:
		at.z *= 1.0 - _shape.flat * front * front
	else:
		at.z *= 1.0 + _shape.sweep * (0.4 + 0.6 * maxf(0.0, sin(lat)))
	at.x *= 1.0 + _shape.bulk * absf(sin(angle)) * c
	if _shape.ridge > 0.0 and height > 0.0:
		at.y += _shape.ridge * r.y * exp(-pow(at.x / (r.x * 0.18), 2.0)) * sin(lat)
	return at


## A height along a rim: `keys` are [angle from the front, height] pairs,
## the same both sides, eased between.
static func _rim_at(keys: Array, angle: float) -> float:
	var a := absf(angle)
	if keys.size() == 1 or a <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var k0: Array = keys[i - 1]
		var k1: Array = keys[i]
		if a <= float(k1[0]):
			var t := smoothstep(0.0, 1.0, (a - float(k0[0])) / maxf(float(k1[0]) - float(k0[0]), 0.0001))
			return lerpf(float(k0[1]), float(k1[1]), t)
	return float(keys[keys.size() - 1][1])


## A curved plate on an ellipsoid of radii `rx`, `ry`, `rz`: from angle
## `from` to `to` (0 at the front, toward +X), between the heights `low`
## and `high` (rim keys, see `_rim_at`), `thick` thick and thinning to a
## bevel at its edges. Closed at the top when it reaches the pole.
static func _surface(rx: float, ry: float, rz: float, from: float, to: float, low: Array, high: Array,
		thick: float, cols: int, rows: int) -> ArrayMesh:
	var r := Vector3(rx, ry, rz)
	var outer := []
	var inner := []
	var normals := []
	var full := to - from >= TAU - 0.001
	for j in rows + 1:
		var v := float(j) / rows
		var row_out := []
		var row_in := []
		var row_n := []
		for i in cols + 1:
			var u := float(i) / cols
			var a := lerpf(from, to, u)
			var h := lerpf(_rim_at(low, a), _rim_at(high, a), v)
			var at := _on_ellipsoid(r, a, h)
			var n := _normal_at(r, a, h, at)
			var edge := minf(1.0 if full else minf(u, 1.0 - u) * 4.0, minf(v, 1.0 - v) * 3.0)
			var t := thick * lerpf(0.35, 1.0, clampf(edge, 0.0, 1.0))
			row_in.append(at)
			row_out.append(at + n * t)
			row_n.append(n)
		outer.append(row_out)
		inner.append(row_in)
		normals.append(row_n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows:
		for i in cols:
			_quad(st, [outer[j][i], outer[j][i + 1], outer[j + 1][i + 1], outer[j + 1][i]],
					[normals[j][i], normals[j][i + 1], normals[j + 1][i + 1], normals[j + 1][i]], 1.0)
			_quad(st, [inner[j][i], inner[j][i + 1], inner[j + 1][i + 1], inner[j + 1][i]],
					[normals[j][i], normals[j][i + 1], normals[j + 1][i + 1], normals[j + 1][i]], -1.0)
	for i in cols:
		for j: int in [0, rows]:
			var n: Vector3 = Vector3.DOWN if j == 0 else Vector3.UP
			_quad(st, [inner[j][i], inner[j][i + 1], outer[j][i + 1], outer[j][i]], [n, n, n, n], 1.0)
	if not full:
		for j in rows:
			for i: int in [0, cols]:
				var side: Vector3 = (inner[j][mini(i + 1, cols)] - inner[j][maxi(i - 1, 0)]).normalized() \
						* (1.0 if i == cols else -1.0)
				_quad(st, [inner[j][i], inner[j + 1][i], outer[j + 1][i], outer[j][i]], [side, side, side, side], 1.0)
	return st.commit()


## The outward normal of the bent ellipsoid at `at` (angle `a`, height `h`).
static func _normal_at(r: Vector3, a: float, h: float, at: Vector3) -> Vector3:
	var e := 0.002
	var hh := clampf(h, -r.y * 0.99 + e, r.y * 0.99 - e)
	var da := _on_ellipsoid(r, a + e, hh) - _on_ellipsoid(r, a - e, hh)
	var dh := _on_ellipsoid(r, a, hh + e) - _on_ellipsoid(r, a, hh - e)
	var n := dh.cross(da)
	if n.length_squared() < 1e-12:
		n = Vector3(at.x / (r.x * r.x), at.y / (r.y * r.y), at.z / (r.z * r.z))
	n = n.normalized()
	return n if n.dot(at) >= 0.0 else -n


static func _quad(st: SurfaceTool, at: Array, n: Array, sign: float) -> void:
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal((n[k] as Vector3) * sign)
		st.add_vertex(at[k])


static func _piece_mesh(root: Node3D, piece_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = piece_name
	part.mesh = mesh
	part.material_override = mat
	root.add_child(part)
	return part


static func _piece(root: Node3D, piece_name: String, mesh: PrimitiveMesh, mat: Material, at: Vector3,
		size: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = piece_name
	var own := mesh.duplicate() as PrimitiveMesh
	own.material = mat
	part.mesh = own
	part.position = at
	part.scale = size
	root.add_child(part)
	return part


## A short upright cylinder (turn it to point it), `radius` round and
## `length` long.
static func _round(root: Node3D, piece_name: String, at: Vector3, radius: float, length: float,
		mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.name = piece_name
	part.mesh = mesh
	part.position = at
	root.add_child(part)
	return part


static func _stud(root: Node3D, piece_name: String, at: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.name = piece_name
	part.mesh = mesh
	part.position = at
	root.add_child(part)
	return part
