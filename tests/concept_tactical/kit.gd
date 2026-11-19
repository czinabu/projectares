extends RefCounted
## Concept tactical kit: three sets (light recon, medium line, heavy assault),
## each a helmet and an armor frame, hung on the real body's bones.

const Geo := preload("res://tests/concept_tactical/geo.gd")

## The head the helmets are built round (ActorSkin.helmet_size * 0.5 * 0.94).
const R := Vector3(0.127, 0.146, 0.146)

const SETS := {
	"runner": {
		"name": "Runner (light, recon)",
		"plate": Color(0.30, 0.34, 0.38), "plate2": Color(0.18, 0.2, 0.23), "fabric": Color(0.2, 0.22, 0.24),
		"strap": Color(0.1, 0.11, 0.12), "suit": Color(0.06, 0.065, 0.075), "accent": Color(0.3, 0.85, 1.0),
		"metal": Color(0.5, 0.53, 0.56), "helmet": "spotter",
	},
	"trooper": {
		"name": "Trooper (medium, line)",
		"plate": Color(0.36, 0.37, 0.27), "plate2": Color(0.24, 0.25, 0.19), "fabric": Color(0.42, 0.38, 0.28),
		"strap": Color(0.2, 0.19, 0.15), "suit": Color(0.07, 0.07, 0.065), "accent": Color(1.0, 0.7, 0.28),
		"metal": Color(0.48, 0.48, 0.46), "helmet": "seeker",
	},
	"bulwark": {
		"name": "Bulwark (heavy, assault)",
		"plate": Color(0.26, 0.27, 0.29), "plate2": Color(0.14, 0.145, 0.155), "fabric": Color(0.13, 0.13, 0.14),
		"strap": Color(0.08, 0.08, 0.085), "suit": Color(0.045, 0.045, 0.05), "accent": Color(1.0, 0.42, 0.12),
		"metal": Color(0.62, 0.6, 0.56), "helmet": "warden",
	},
}


class Mats:
	var plate: StandardMaterial3D
	var plate2: StandardMaterial3D
	var fabric: StandardMaterial3D
	var strap: StandardMaterial3D
	var metal: StandardMaterial3D
	var rubber: StandardMaterial3D
	var glow: StandardMaterial3D
	var dim: StandardMaterial3D
	var glass: StandardMaterial3D
	var visor: StandardMaterial3D
	var hood: StandardMaterial3D

	func _init(s: Dictionary) -> void:
		plate = Geo.mat(s["plate"], 0.62, 0.15)
		plate2 = Geo.mat(s["plate2"], 0.7, 0.2)
		fabric = Geo.mat(s["fabric"], 0.97, 0.0)
		strap = Geo.mat(s["strap"], 0.95, 0.0)
		metal = Geo.mat(s["metal"], 0.32, 0.85)
		rubber = Geo.mat(Color(0.05, 0.05, 0.055), 0.92, 0.0)
		glow = Geo.glow(s["accent"], 2.6)
		dim = Geo.glow(s["accent"], 0.9)
		glass = Geo.glass(s["accent"])
		visor = Geo.glow(s["accent"], 1.2)
		hood = Geo.mat(Color(0.05, 0.05, 0.055), 0.95, 0.0)


static func pol(y: float) -> float:
	return acos(clampf(y, -1.0, 1.0))


## ---------------------------------------------------------------- helmets

## How square the helmet being built is (a superellipsoid's power).
static var N := 2.0


static func hc(r: Vector3, top: Callable, bot: Callable, from: float, to: float, thick: float,
		az_steps := 24, pol_steps := 10, flat := false, push := Callable()) -> ArrayMesh:
	return Geo.cap(r, top, bot, from, to, thick, az_steps, pol_steps, flat, push, N)


static func helmet(design: String, s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ConceptHelmet"
	root.scale = Vector3.ONE * 0.84
	var m := Mats.new(s)
	# The balaclava under every helmet.
	Geo.add(root, Geo.cap(R * Vector3(0.92, 0.95, 0.93), Geo.const_of(0.0), Geo.const_of(PI * 0.97), -PI, PI, 0.003),
			m.hood, Vector3(0, -R.y * 0.08, R.z * 0.02))
	Geo.cyl(root, R.x * 0.62, R.y * 0.5, m.hood, Vector3(0, -R.y * 1.0, R.z * 0.12))
	N = {"spotter": 2.4, "seeker": 2.6, "warden": 2.8}[design]
	match design:
		"spotter":
			_spotter(root, m)
		"seeker":
			_seeker(root, m)
		"warden":
			_warden(root, m)
	N = 2.0
	return root


## High-cut recon helmet: the ears open for a headset, side rails, a front
## shroud carrying a flip-down rangefinder, and a smoked half visor.
static func _spotter(root: Node3D, m: Mats) -> void:
	var r := Vector3(0.133, 0.128, 0.152)
	# The cut: low over the brow, up high over the ears, down at the nape.
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		var y := 0.24
		if aa < 0.9:
			y = lerpf(0.26, 0.2, aa / 0.9)
		elif aa < 1.25:
			y = lerpf(0.2, -0.08, (aa - 0.9) / 0.35)
		elif aa < 2.1:
			y = -0.08
		else:
			y = lerpf(-0.08, -0.42, (aa - 2.1) / (PI - 2.1))
		return pol(y)
	var brow := func(p: float, a: float) -> float:
		# A brow line: the front is drawn flatter and juts a touch at the rim.
		var front := maxf(0.0, cos(a))
		return 1.0 - 0.05 * front * sin(p) + 0.04 * front * smoothstep(0.9, 1.3, p)
	Geo.add(root, hc(r, Geo.const_of(0.0), edge, -PI, PI, 0.012, 40, 10, false, brow), m.plate)
	# A rubber edge trim along the cut.
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.08
	Geo.add(root, hc(r * 1.035, lip, edge, -PI, PI, 0.006, 40, 1, false, brow), m.rubber)
	# A loop patch on top.
	Geo.box(root, Vector3(0.085, 0.008, 0.06), m.fabric, Vector3(0, r.y * 1.0, r.z * 0.12), 0.003,
			Basis(Vector3.RIGHT, -0.12))
	# Side rails.
	for side: float in [-1.0, 1.0]:
		var rail := Geo.box(root, Vector3(0.016, 0.022, 0.13), m.plate2, Vector3(side * r.x * 1.02, -0.005, -0.005), 0.003)
		rail.rotation = Vector3(0.18, 0, 0)
		for k in 4:
			Geo.box(root, Vector3(0.006, 0.006, 0.014), m.metal, Vector3(side * (r.x * 1.02 + 0.008), -0.004, -0.05 + k * 0.03), 0.001)
		# The headset ear cups under the rails.
		var cup := Geo.cyl(root, 0.045, 0.034, m.rubber, Vector3(side * (r.x * 0.98), -0.055, 0.005), Basis(Vector3.BACK, PI * 0.5), 16)
		Geo.cyl(root, 0.03, 0.012, m.plate2, Vector3(side * (r.x * 0.98 + 0.021), -0.055, 0.005), Basis(Vector3.BACK, PI * 0.5), 12)
		Geo.box(root, Vector3(0.004, 0.012, 0.012), m.dim, Vector3(side * (r.x * 0.98 + 0.028), -0.045, 0.02), 0.001)
		cup.name = "Cup"
	# A boom mic off the left cup.
	var boom := Geo.cyl(root, 0.004, 0.11, m.rubber, Vector3(-r.x * 0.88, -0.1, -0.06), Basis.from_euler(Vector3(PI * 0.5 - 0.35, 0.45, 0)))
	boom.name = "Boom"
	Geo.box(root, Vector3(0.016, 0.012, 0.02), m.rubber, Vector3(-r.x * 0.62, -0.115, -0.115), 0.004)
	# The front shroud and the rangefinder on its arm, flipped down over the right eye.
	var fy := 0.165
	Geo.box(root, Vector3(0.05, 0.03, 0.022), m.plate2, Vector3(0, r.y * 0.62, -r.z * 0.84), 0.005, Basis(Vector3.RIGHT, -0.5))
	Geo.box(root, Vector3(0.03, 0.05, 0.016), m.plate2, Vector3(0.012, r.y * 0.4, -r.z * 1.06), 0.004, Basis(Vector3.RIGHT, -0.15))
	var body := Geo.box(root, Vector3(0.05, 0.034, 0.06), m.plate2, Vector3(0.04, r.y * 0.16, -r.z * 1.14), 0.006)
	body.name = "Rangefinder"
	Geo.cyl(root, 0.015, 0.012, m.metal, Vector3(0.04, r.y * 0.16, -r.z * 1.14 - 0.034), Basis(Vector3.RIGHT, PI * 0.5), 14)
	Geo.cyl(root, 0.011, 0.004, m.glow, Vector3(0.04, r.y * 0.16, -r.z * 1.14 - 0.041), Basis(Vector3.RIGHT, PI * 0.5), 14)
	Geo.box(root, Vector3(0.012, 0.006, 0.01), m.glow, Vector3(0.068, r.y * 0.16 + 0.008, -r.z * 1.14 - 0.01), 0.001)
	# The half visor: smoked glass from cheek to cheek, under the brow.
	var vtop := func(_a: float) -> float: return pol(0.16)
	var vbot := func(a: float) -> float: return pol(lerpf(-0.36, -0.2, absf(a) / 1.45))
	var visor := Geo.add(root, hc(r * Vector3(1.06, 1.0, 1.1), vtop, vbot, -1.45, 1.45, 0.006, 26, 4), m.glass)
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ltop := func(a: float) -> float: return pol(lerpf(-0.34, -0.18, absf(a) / 1.3))
	var lbot := func(a: float) -> float: return pol(lerpf(-0.36, -0.2, absf(a) / 1.3))
	Geo.add(root, hc(r * Vector3(1.065, 1.0, 1.105), ltop, lbot, -1.3, 1.3, 0.004, 24, 1), m.dim)
	# Visor pivots at the temples.
	for side: float in [-1.0, 1.0]:
		Geo.cyl(root, 0.014, 0.012, m.metal, Vector3(side * r.x * 1.05, r.y * 0.1, -r.z * 0.3), Basis(Vector3.BACK, PI * 0.5), 10)
	# A half-face respirator under the visor, two filters angled down.
	var mtop := func(a: float) -> float: return pol(lerpf(-0.3, -0.18, absf(a) / 1.3))
	var mbot := func(_a: float) -> float: return pol(-0.92)
	var mask_push := func(p: float, a: float) -> float: return 1.0 + 0.06 * maxf(0.0, cos(a)) * smoothstep(1.8, 2.4, p)
	Geo.add(root, hc(Vector3(0.118, 0.128, 0.142), mtop, mbot, -1.3, 1.3, 0.012, 18, 5, false, mask_push), m.rubber)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 0.07, -0.085, -0.115)
		var b := Basis.from_euler(Vector3(PI * 0.5 - 0.5, side * 0.6, 0.0))
		Geo.cyl(root, 0.024, 0.026, m.plate2, at, b, 14)
		Geo.cyl(root, 0.018, 0.028, m.metal, at, b, 14)
	Geo.box(root, Vector3(0.03, 0.03, 0.02), m.plate2, Vector3(0, -0.105, -0.152), 0.006)
	Geo.box(root, Vector3(0.016, 0.004, 0.004), m.dim, Vector3(0, -0.1, -0.163), 0.001)
	# A strobe on the back.
	Geo.box(root, Vector3(0.03, 0.02, 0.012), m.plate2, Vector3(0, r.y * 0.62, r.z * 0.86), 0.004, Basis(Vector3.RIGHT, 0.6))
	Geo.box(root, Vector3(0.018, 0.006, 0.004), m.glow, Vector3(0, r.y * 0.64, r.z * 0.9), 0.001, Basis(Vector3.RIGHT, 0.6))
	# A counterweight pouch on the back.
	Geo.box(root, Vector3(0.07, 0.045, 0.03), m.fabric, Vector3(0, r.y * 0.15, r.z * 1.0), 0.008, Basis(Vector3.RIGHT, 0.12))


## Full-cut intel helmet: covers the ears, a mandible jaw guard with vents,
## a wide wraparound visor under a heavy brow, and a scan emitter on the crown.
static func _seeker(root: Node3D, m: Mats) -> void:
	var r := Vector3(0.136, 0.13, 0.154)
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		var y := lerpf(0.22, -0.55, smoothstep(0.75, 1.4, aa))
		if aa > 2.3:
			y = lerpf(-0.55, -0.62, (aa - 2.3) / (PI - 2.3))
		return pol(y)
	var shape := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		var back := maxf(0.0, -cos(a))
		# Swept back over the nape, a flat face.
		return 1.0 - 0.06 * front * sin(p) + 0.05 * back * smoothstep(1.2, 2.0, p)
	Geo.add(root, hc(r, Geo.const_of(0.0), edge, -PI, PI, 0.014, 44, 12, false, shape), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.07
	Geo.add(root, hc(r * 1.03, lip, edge, -PI, PI, 0.006, 44, 1, false, shape), m.plate2)
	# Brow plate: a hard ridge over the visor.
	var btop := func(a: float) -> float: return pol(lerpf(0.42, 0.3, absf(a) / 1.6))
	var bbot := func(a: float) -> float: return pol(lerpf(0.2, 0.12, absf(a) / 1.6))
	Geo.add(root, hc(r * Vector3(1.08, 1.0, 1.12), btop, bbot, -1.6, 1.6, 0.016, 26, 3, false, shape), m.plate2)
	# Wide wraparound visor.
	var vtop := func(a: float) -> float: return pol(lerpf(0.2, 0.12, absf(a) / 1.55))
	var vbot := func(a: float) -> float: return pol(lerpf(-0.22, -0.1, absf(a) / 1.55))
	var visor := Geo.add(root, hc(r * Vector3(1.05, 1.0, 1.07), vtop, vbot, -1.55, 1.55, 0.006, 28, 4, false, shape), m.glass)
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A lit line under the visor.
	var ltop := func(a: float) -> float: return pol(lerpf(-0.22, -0.1, absf(a) / 1.45))
	var lbot := func(a: float) -> float: return pol(lerpf(-0.25, -0.13, absf(a) / 1.45))
	Geo.add(root, hc(r * Vector3(1.06, 1.0, 1.08), ltop, lbot, -1.45, 1.45, 0.004, 24, 1, false, shape), m.glow)
	# The mandible: a jaw guard wrapping the chin, set out from the face.
	var jtop := func(a: float) -> float: return pol(lerpf(-0.27, -0.12, absf(a) / 1.5))
	var jbot := func(a: float) -> float: return pol(lerpf(-0.95, -0.62, absf(a) / 1.5))
	var jaw_shape := func(p: float, a: float) -> float:
		return 1.0 + 0.04 * maxf(0.0, cos(a)) - 0.04 * smoothstep(2.4, 2.9, p)
	Geo.add(root, hc(r * Vector3(1.0, 1.08, 1.0), jtop, jbot, -1.5, 1.5, 0.016, 20, 5, false, jaw_shape), m.plate)
	# Breathing vents on the jaw.
	for side: float in [-1.0, 1.0]:
		for k in 3:
			Geo.box(root, Vector3(0.022, 0.005, 0.01), m.rubber,
					Vector3(side * 0.04, -r.y * (0.5 + k * 0.1), -r.z * 1.07 + k * 0.008), 0.001, Basis(Vector3.UP, side * 0.45))
		Geo.box(root, Vector3(0.006, 0.07, 0.03), m.metal, Vector3(side * r.x * 0.92, -r.y * 0.5, -r.z * 0.62), 0.002,
				Basis(Vector3.UP, side * 0.9))
	# Scan emitter on the crown: housing, lit ring, dome.
	var crown := Vector3(0, r.y * 0.96, r.z * 0.1)
	Geo.cyl(root, 0.05, 0.022, m.plate2, crown, Basis.IDENTITY, 20)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.041
	ring.outer_radius = 0.049
	Geo.add(root, ring, m.glow, crown + Vector3(0, 0.012, 0))
	Geo.add(root, hc(Vector3(0.036, 0.018, 0.036), Geo.const_of(0.0), Geo.const_of(PI * 0.5), -PI, PI, 0.002, 16, 4), m.metal,
			crown + Vector3(0, 0.012, 0))
	# A sensor pod on the left with an antenna; a camera block on the right.
	Geo.box(root, Vector3(0.03, 0.05, 0.08), m.plate2, Vector3(-r.x * 1.07, r.y * 0.12, 0.0), 0.007)
	Geo.box(root, Vector3(0.004, 0.012, 0.05), m.glow, Vector3(-r.x * 1.07 - 0.016, r.y * 0.16, -0.005), 0.001)
	Geo.cyl(root, 0.0035, 0.22, m.rubber, Vector3(-r.x * 1.0, r.y * 0.8, r.z * 0.45), Basis.from_euler(Vector3(-0.5, 0, 0.18)), 6)
	Geo.box(root, Vector3(0.028, 0.036, 0.05), m.plate2, Vector3(r.x * 1.07, r.y * 0.1, -0.02), 0.006)
	Geo.cyl(root, 0.011, 0.012, m.glass, Vector3(r.x * 1.07, r.y * 0.1, -0.05), Basis(Vector3.RIGHT, PI * 0.5), 12)


## Closed assault helm: faceted, a crest, a narrow T visor, heavy cheek
## plates, a neck guard of lames, and sensor eyes all round.
static func _warden(root: Node3D, m: Mats) -> void:
	var r := Vector3(0.136, 0.122, 0.155)
	# The dome: cut at the brow in front, low over the ears and nape.
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return pol(lerpf(0.2, -0.55, smoothstep(0.9, 1.6, aa)))
	var dome := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		# A hard brow ridge along the cut.
		return 1.0 + 0.05 * front * smoothstep(1.0, 1.32, p) - 0.03 * front * sin(p)
	Geo.add(root, hc(r, Geo.const_of(0.0), edge, -PI, PI, 0.018, 40, 12, false, dome), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.06
	Geo.add(root, hc(r * 1.03, lip, edge, -PI, PI, 0.006, 40, 1, false, dome), m.metal)
	# The faceplate: from the brow to under the chin, jutting to a prow.
	var face := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		return 1.0 + 0.2 * pow(front, 3.0) * smoothstep(1.6, 2.5, p)
	var ftop := func(a: float) -> float: return pol(lerpf(0.16, 0.05, absf(a) / 1.55))
	var fbot := func(a: float) -> float: return pol(lerpf(-0.92, -0.6, absf(a) / 1.55))
	Geo.add(root, hc(r * Vector3(0.98, 1.0, 1.0), ftop, fbot, -1.55, 1.55, 0.018, 30, 10, false, face), m.plate2)
	# The visor slit: dark glass, a thin lit line inside it.
	var vtop := func(a: float) -> float: return pol(lerpf(0.06, 0.03, absf(a) / 1.1))
	var vbot := func(a: float) -> float: return pol(lerpf(-0.04, -0.03, absf(a) / 1.1))
	Geo.add(root, hc(r * Vector3(0.995, 1.0, 1.02), vtop, vbot, -1.1, 1.1, 0.02, 22, 1, true, face), m.glass)
	var ltop := func(a: float) -> float: return pol(lerpf(0.015, 0.0, absf(a) / 1.0))
	var lbot := func(a: float) -> float: return pol(lerpf(-0.01, -0.012, absf(a) / 1.0))
	Geo.add(root, hc(r * Vector3(1.0, 1.0, 1.03), ltop, lbot, -1.0, 1.0, 0.02, 22, 1, true, face), m.visor)
	# Cheek plates layered over the faceplate, with breather grilles.
	for side: float in [-1.0, 1.0]:
		var from := 0.55 if side > 0 else -1.85
		var to := 1.85 if side > 0 else -0.55
		var ctop := func(_a: float) -> float: return pol(-0.12)
		var cbot := func(a: float) -> float: return pol(lerpf(-0.78, -0.62, absf(absf(a) - 0.55) / 1.3))
		Geo.add(root, hc(r * Vector3(1.07, 1.0, 1.06), ctop, cbot, from, to, 0.018, 10, 4, true, face), m.plate)
		for k in 3:
			Geo.box(root, Vector3(0.006, 0.006, 0.03), m.rubber, Vector3(side * 0.06, -0.075 - k * 0.014, -0.135), 0.001,
					Basis(Vector3.UP, side * 0.7))
		# Sensor eyes round the sides and back (threat sense).
		for k in 2:
			var a := side * (1.5 + k * 0.85)
			var at := Vector3(sin(a) * r.x * 1.05, r.y * 0.22, -cos(a) * r.z * 1.02)
			var look := Basis.looking_at(Vector3(sin(a), 0, -cos(a))) * Basis(Vector3.RIGHT, PI * 0.5)
			Geo.cyl(root, 0.013, 0.014, m.plate2, at, look, 10)
			Geo.cyl(root, 0.008, 0.004, m.glow, at + Vector3(sin(a), 0, -cos(a)) * 0.008, look, 10)
	# Neck guard: two lames at the back.
	for k in 2:
		var ntop := func(_a: float) -> float: return pol(-0.48 - k * 0.2)
		var nbot := func(_a: float) -> float: return pol(-0.72 - k * 0.2)
		Geo.add(root, hc(r * (1.06 + k * 0.05), ntop, nbot, PI - 1.6, PI + 1.6, 0.014, 20, 2, false), m.plate2 if k else m.plate)
	# A low crest fin from the brow back over the crown.
	var fin := Geo.box(root, Vector3(0.018, 0.026, 0.2), m.plate2, Vector3(0, r.y * 0.98, 0.0), 0.006, Basis(Vector3.RIGHT, 0.08))
	fin.name = "Crest"
	Geo.box(root, Vector3(0.02, 0.005, 0.14), m.dim, Vector3(0, r.y * 0.98 + 0.014, 0.01), 0.001, Basis(Vector3.RIGHT, 0.08))


## ---------------------------------------------------------------- armor

## Hangs a set's armor on `skin` (an ActorSkin). Returns the holders.
static func dress(skin: Node, set_id: String) -> Array[Node3D]:
	var s: Dictionary = SETS[set_id]
	var m := Mats.new(s)
	var parts: Array[Node3D] = []
	var chest: Vector3 = skin.call("_rest_at", "Chest")
	parts.append(_hang(skin, _torso(set_id, m), "Chest", chest))
	parts.append(_hang(skin, _belt(set_id, m), "Hips", skin.call("_rest_at", "Hips")))
	for side: String in ["L", "R"]:
		var out := -1.0 if side == "L" else 1.0
		parts.append(_hang_limb(skin, _pauldron(set_id, m, out), "UpperArm." + side, "LowerArm." + side, out))
		parts.append(_hang_limb(skin, _forearm(set_id, m, out), "LowerArm." + side, "Wrist." + side, out))
		parts.append(_hang_limb(skin, _thigh(set_id, m, out), "UpperLeg." + side, "LowerLeg." + side, out))
		parts.append(_hang_limb(skin, _shin(set_id, m, out), "LowerLeg." + side, "Foot." + side, out))
	return parts


## Hangs `part`, built in the actor's frame round `at`, on `bone`.
static func _hang(skin: Node, part: Node3D, bone: String, at: Vector3) -> Node3D:
	return skin.call("_hang", part, part.name, bone, Vector3.ZERO, at)


## Hangs a limb piece built standing up (Y from the far joint toward this
## one, front -Z, out +X on the right) with its origin at `bone`'s joint.
static func _hang_limb(skin: Node, part: Node3D, bone: String, child: String, out: float) -> Node3D:
	var a: Vector3 = skin.call("_rest_at", bone)
	var b: Vector3 = skin.call("_rest_at", child)
	var up := (a - b).normalized()
	var front := Vector3.FORWARD - up * up.dot(Vector3.FORWARD)
	if front.length() < 0.1:
		front = Vector3.FORWARD
	front = front.normalized()
	var x := up.cross(-front).normalized()
	var basis := Basis(x, up, -front)
	var holder: Node3D = skin.call("_hang", part, part.name, bone, Vector3.ZERO, a)
	part.basis = basis
	return holder


## Torso: carrier, plates and pouches round the chest bone.
static func _torso(set_id: String, m: Mats) -> Node3D:
	var root := Node3D.new()
	root.name = "Torso"
	var S := preload("res://core/visual/actor_skin.gd")
	var heavy := set_id == "bulwark"
	var light := set_id == "runner"
	var mid := Vector3(0, -0.02, 0.0)
	var rx := 0.15
	var rz := 0.125
	var low := -0.2
	var high := 0.12
	# The carrier: fabric front and back panels.
	var wrap := 0.82 if not heavy else 0.95
	Geo.add(root, S._shell(rx, rz, -wrap, wrap, low, high, 0.018, 0.012, 0.06), m.fabric, mid)
	Geo.add(root, S._shell(rx, rz, PI - wrap, PI + wrap, low, high - 0.01, 0.018, 0.008, 0.06), m.fabric, mid)
	# Hard plates over them.
	var pw := wrap * 0.82
	var front_z := -(rz + 0.018)
	if heavy:
		Geo.add(root, S._shell(rx + 0.018, rz + 0.02, -pw * 1.1, pw * 1.1, low + 0.04, high + 0.005, 0.024, 0.02, 0.1), m.plate, mid)
		# Layered abdominal lames below.
		for k in 3:
			var top := low + 0.045 - k * 0.055
			Geo.add(root, S._shell(rx + 0.012 + k * 0.004, rz + 0.016 + k * 0.004, -0.95 + k * 0.08, 0.95 - k * 0.08, top - 0.06, top,
					0.016, 0.006), m.plate2 if k % 2 else m.plate, mid)
			Geo.add(root, S._shell(rx + 0.03 + k * 0.004, rz + 0.034 + k * 0.004, -0.9 + k * 0.08, 0.9 - k * 0.08, top - 0.008, top - 0.002,
					0.004), m.metal, mid)
		# Back plate with hot vents.
		Geo.add(root, S._shell(rx + 0.018, rz + 0.02, PI - pw, PI + pw, low + 0.02, high, 0.024, 0.016, 0.08), m.plate, mid)
		for x: float in [-0.05, 0.05]:
			Geo.box(root, Vector3(0.055, 0.1, 0.012), m.plate2, mid + Vector3(x, -0.02, rz + 0.065), 0.003)
			for k in 4:
				Geo.box(root, Vector3(0.04, 0.007, 0.006), m.glow, mid + Vector3(x, -0.055 + k * 0.024, rz + 0.072), 0.001)
		# Gorget.
		Geo.add(root, S._shell(0.105, 0.098, -2.3, 2.3, high - 0.01, high + 0.06, 0.016, 0.0, -0.35), m.plate2, mid + Vector3(0, 0, -0.005))
		Geo.add(root, S._shell(0.112, 0.105, -2.2, 2.2, high + 0.045, high + 0.055, 0.006, 0.0, -0.3), m.metal, mid + Vector3(0, 0, -0.005))
		# Metal edge round the breastplate's top.
		Geo.add(root, S._shell(rx + 0.04, rz + 0.042, -pw * 1.05, pw * 1.05, high - 0.012, high - 0.002, 0.006, 0.0, 0.1), m.metal, mid)
		# A hazard chevron pair and a status strip.
		for x: float in [-1.0, 1.0]:
			Geo.box(root, Vector3(0.05, 0.008, 0.004), m.glow, mid + Vector3(x * 0.075, 0.04, front_z - 0.055), 0.001,
					Basis(Vector3.BACK, x * 0.35))
	else:
		var t := 0.014 if light else 0.018
		Geo.add(root, S._shell(rx + 0.016, rz + 0.018, -pw, pw, low + 0.06, high - 0.01, t, 0.016, 0.08), m.plate, mid)
		Geo.add(root, S._shell(rx + 0.016, rz + 0.018, PI - pw, PI + pw, low + 0.04, high - 0.02, t, 0.012, 0.08), m.plate, mid)
		# A thin status strip on the plate.
		Geo.box(root, Vector3(0.045, 0.006, 0.004), m.glow, mid + Vector3(-0.06, 0.06, front_z - 0.042), 0.001,
				Basis(Vector3.UP, 0.35))
	# Shoulder straps: padded, over the top of each shoulder.
	for x: float in [-0.085, 0.085]:
		var strap := Geo.add(root, S._shell(0.07, 0.125, -0.15, PI + 0.15, -0.022, 0.022, 0.014, 0.0),
				m.fabric, mid + Vector3(x, high - 0.015, 0.0), Basis(Vector3.BACK, PI * 0.5))
		strap.name = "Strap"
		Geo.box(root, Vector3(0.05, 0.03, 0.012), m.strap, mid + Vector3(x, high - 0.005, -rz - 0.03), 0.004,
				Basis(Vector3.RIGHT, 0.35))
	# The cummerbund round the sides, MOLLE rows on it.
	if not light:
		for side: float in [-1.0, 1.0]:
			var from := wrap * 0.85 if side > 0 else -PI + wrap * 0.85
			var to := PI - wrap * 0.85 if side > 0 else -wrap * 0.85
			Geo.add(root, S._shell(rx - 0.004, rz - 0.004, from, to, low, low + 0.13, 0.016, 0.004), m.fabric, mid)
			for k in 3:
				Geo.add(root, S._shell(rx + 0.013, rz + 0.013, from + 0.05, to - 0.05, low + 0.025 + k * 0.035, low + 0.035 + k * 0.035, 0.004),
						m.strap, mid)
	else:
		# Elastic side straps only.
		for side: float in [-1.0, 1.0]:
			var from := wrap * 0.85 if side > 0 else -PI + wrap * 0.85
			var to := PI - wrap * 0.85 if side > 0 else -wrap * 0.85
			for k in 2:
				Geo.add(root, S._shell(rx - 0.004, rz - 0.004, from, to, low + 0.03 + k * 0.05, low + 0.055 + k * 0.05, 0.008), m.strap, mid)
	# Front: magazine pouches and an admin pouch.
	var pz := front_z - 0.03 - (0.02 if heavy else 0.0)
	var mags := 2 if light else 3
	var py := low + 0.03
	if heavy:
		py = low - 0.01
	for i in mags:
		var x := (i - (mags - 1) * 0.5) * 0.062
		Geo.box(root, Vector3(0.056, 0.085, 0.036), m.fabric if not heavy else m.plate2, mid + Vector3(x, py, pz), 0.006)
		Geo.box(root, Vector3(0.058, 0.022, 0.04), m.strap, mid + Vector3(x, py + 0.038, pz - 0.001), 0.005)
		# A mag cell's lit gauge.
		Geo.box(root, Vector3(0.022, 0.005, 0.004), m.dim, mid + Vector3(x, py + 0.01, pz - 0.019), 0.001)
	if set_id == "trooper":
		Geo.box(root, Vector3(0.12, 0.06, 0.02), m.fabric, mid + Vector3(0, low + 0.12, pz + 0.012), 0.006)
		Geo.box(root, Vector3(0.05, 0.022, 0.004), m.glow, mid + Vector3(0.025, low + 0.125, pz - 0.0), 0.001)
		# Radio on the left side, its antenna up the back.
		Geo.box(root, Vector3(0.04, 0.1, 0.06), m.fabric, mid + Vector3(-rx - 0.03, low + 0.07, 0.01), 0.008)
		Geo.box(root, Vector3(0.03, 0.03, 0.045), m.plate2, mid + Vector3(-rx - 0.03, low + 0.13, 0.01), 0.005)
		Geo.box(root, Vector3(0.006, 0.006, 0.006), m.glow, mid + Vector3(-rx - 0.05, low + 0.13, -0.005), 0.001)
		Geo.cyl(root, 0.003, 0.3, m.rubber, mid + Vector3(-rx + 0.01, high + 0.06, rz + 0.04), Basis(Vector3.BACK, 0.12), 6)
		# Back panel: hydration and a drag handle.
		Geo.box(root, Vector3(0.15, 0.2, 0.04), m.fabric, mid + Vector3(0, -0.04, rz + 0.05), 0.012)
		for k in 4:
			Geo.box(root, Vector3(0.152, 0.006, 0.042), m.strap, mid + Vector3(0, -0.11 + k * 0.04, rz + 0.05), 0.002)
	if light:
		# A slim pack: a single flat utility panel on the back.
		Geo.box(root, Vector3(0.12, 0.12, 0.025), m.fabric, mid + Vector3(0, -0.02, rz + 0.04), 0.008)
		Geo.box(root, Vector3(0.006, 0.08, 0.004), m.glow, mid + Vector3(0, -0.02, rz + 0.054), 0.001)
	# A drag handle on every carrier.
	Geo.box(root, Vector3(0.07, 0.018, 0.012), m.strap, mid + Vector3(0, high + 0.0, rz + 0.045), 0.005)
	return root


## Battle belt and pouches round the hips.
static func _belt(set_id: String, m: Mats) -> Node3D:
	var root := Node3D.new()
	root.name = "Belt"
	var S := preload("res://core/visual/actor_skin.gd")
	var mid := Vector3(0, 0.07, 0.02)
	var rx := 0.15
	var rz := 0.12
	Geo.add(root, S._shell(rx, rz, -PI, PI, -0.02, 0.025, 0.014), m.strap, mid)
	Geo.box(root, Vector3(0.05, 0.035, 0.01), m.metal, mid + Vector3(0, 0.002, -rz - 0.016), 0.003)
	var pouches := [[-1.3, Vector3(0.05, 0.07, 0.04)], [1.3, Vector3(0.05, 0.07, 0.04)], [2.2, Vector3(0.07, 0.06, 0.04)]]
	if set_id == "runner":
		pouches = [[-1.4, Vector3(0.045, 0.06, 0.03)]]
	for p: Array in pouches:
		var a: float = p[0]
		var size: Vector3 = p[1]
		var at := mid + Vector3(sin(a) * (rx + 0.03), -0.02, -cos(a) * (rz + 0.03))
		Geo.box(root, size, m.fabric, at, 0.007, Basis(Vector3.UP, -a))
		Geo.box(root, Vector3(size.x * 1.04, 0.018, size.z * 1.05), m.strap, at + Vector3(0, size.y * 0.42, 0), 0.004, Basis(Vector3.UP, -a))
	if set_id == "bulwark":
		# Armored faulds over the hips at the front.
		for side: float in [-1.0, 1.0]:
			var from := 0.15 if side > 0 else -1.1
			var to := 1.1 if side > 0 else -0.15
			Geo.add(root, S._shell(rx + 0.02, rz + 0.02, from, to, -0.08, 0.0, 0.016, 0.004, -0.1), m.plate, mid)
	return root


## Upper arm: segmented pauldron for medium and heavy, a cap for light.
static func _pauldron(set_id: String, m: Mats, out: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Pauldron"
	var S := preload("res://core/visual/actor_skin.gd")
	var lames: int = {"runner": 1, "trooper": 2, "bulwark": 3}[set_id]
	var r: float = {"runner": 0.06, "trooper": 0.068, "bulwark": 0.078}[set_id]
	var thick: float = {"runner": 0.01, "trooper": 0.013, "bulwark": 0.018}[set_id]
	# Facing outward: the band runs round the arm centred on its outside.
	var centre := PI * 0.5 * out
	# The dome over the top of the shoulder.
	var dome := Geo.cap(Vector3(r * 1.1, r * 0.9, r * 1.15), Geo.const_of(0.0), Geo.const_of(1.35),
			centre - 1.9, centre + 1.9, thick, 16, 5)
	Geo.add(root, dome, m.plate, Vector3(out * 0.012, 0.0, 0.0))
	Geo.add(root, Geo.cap(Vector3(r * 1.1, r * 0.9, r * 1.15) + Vector3.ONE * thick, Geo.const_of(1.25), Geo.const_of(1.35),
			centre - 1.9, centre + 1.9, 0.005, 16, 1), m.metal if set_id != "runner" else m.plate2, Vector3(out * 0.012, 0.0, 0.0))
	for i in lames:
		var top := -0.012 - i * 0.042
		Geo.add(root, S._shell(r * 1.02 + i * 0.004, r * 1.06 + i * 0.004, centre - 1.35 + i * 0.1, centre + 1.35 - i * 0.1,
				top - 0.045, top, thick, 0.004, 0.0), m.plate2 if i % 2 == 0 else m.plate, Vector3(out * 0.01, 0, 0))
		if set_id == "bulwark":
			Geo.add(root, S._shell(r * 1.02 + i * 0.004 + thick, r * 1.06 + i * 0.004 + thick, centre - 1.3 + i * 0.1, centre + 1.3 - i * 0.1,
					top - 0.045, top - 0.038, 0.004), m.metal, Vector3(out * 0.01, 0, 0))
	if set_id == "trooper":
		# A unit patch on the lower lame.
		Geo.box(root, Vector3(0.006, 0.026, 0.036), m.glow, Vector3(out * (r + 0.022), -0.06, 0), 0.002)
	if set_id != "runner":
		# A rerebrace down the outside of the upper arm.
		Geo.add(root, S._shell(0.052, 0.056, centre - 1.2, centre + 1.2, -0.24, -0.11, thick * 0.8, 0.004), m.plate, Vector3.ZERO)
	return root


## Forearm: a bracer, with an elbow pad.
static func _forearm(set_id: String, m: Mats, out: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Forearm"
	var S := preload("res://core/visual/actor_skin.gd")
	var thick := 0.008 if set_id == "runner" else 0.012
	# Elbow pad at the joint, round its back.
	Geo.add(root, Geo.cap(Vector3(0.045, 0.045, 0.045), Geo.const_of(0.6), Geo.const_of(2.4), PI - 1.3, PI + 1.3, thick, 10, 5),
			m.rubber if set_id != "bulwark" else m.plate, Vector3(0, -0.01, 0.006))
	# The bracer along the outer forearm.
	var centre := PI * 0.5 * out
	Geo.add(root, S._shell(0.042, 0.04, centre - 1.6, centre + 1.6, -0.19, -0.05, thick, 0.004, -0.08), m.plate, Vector3.ZERO)
	if set_id != "runner":
		Geo.add(root, S._shell(0.042 + thick, 0.04 + thick, centre - 1.5, centre + 1.5, -0.12, -0.11, 0.004), m.metal, Vector3.ZERO)
	# A wrist display on the left arm.
	if out < 0.0:
		Geo.box(root, Vector3(0.006, 0.028, 0.04), m.dim, Vector3(out * 0.052, -0.15, 0.0), 0.001)
	return root


## Thigh: a plate down the front, a drop-leg pouch on the right.
static func _thigh(set_id: String, m: Mats, out: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Thigh"
	var S := preload("res://core/visual/actor_skin.gd")
	if set_id == "bulwark":
		for k in 2:
			var top := -0.03 - k * 0.11
			Geo.add(root, S._shell(0.09 + k * 0.006, 0.085 + k * 0.006, -0.6 + out * 0.4, 0.6 + out * 0.9, top - 0.13, top, 0.016, 0.006, -0.06),
					m.plate if k == 0 else m.plate2, Vector3.ZERO)
	elif set_id == "trooper":
		Geo.add(root, S._shell(0.088, 0.084, -0.7, 0.7, -0.24, -0.08, 0.012, 0.006), m.plate, Vector3.ZERO)
	if out > 0.0:
		# The drop-leg pouch on two straps.
		for k in 2:
			Geo.add(root, S._shell(0.082, 0.08, -PI, PI, -0.1 - k * 0.09, -0.085 - k * 0.09, 0.006), m.strap, Vector3.ZERO)
		Geo.box(root, Vector3(0.03, 0.12, 0.07), m.fabric, Vector3(0.1, -0.15, 0.0), 0.008)
		Geo.box(root, Vector3(0.032, 0.025, 0.074), m.strap, Vector3(0.1, -0.1, 0.0), 0.006)
		if set_id == "runner":
			Geo.box(root, Vector3(0.006, 0.04, 0.004), m.glow, Vector3(0.117, -0.16, -0.02), 0.001)
	return root


## Shin: knee pad, and a greave for heavy.
static func _shin(set_id: String, m: Mats, out: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Shin"
	var S := preload("res://core/visual/actor_skin.gd")
	var r: float = {"runner": 0.058, "trooper": 0.064, "bulwark": 0.07}[set_id]
	var knee := Geo.cap(Vector3(r, r * 1.2, r), Geo.const_of(0.5), Geo.const_of(2.3), -1.4, 1.4, 0.016, 12, 6)
	Geo.add(root, knee, m.rubber if set_id == "runner" else m.plate, Vector3(0, 0.0, -0.01))
	Geo.add(root, Geo.cap(Vector3(r, r * 1.2, r) * 0.6 + Vector3(0, 0, 0.02), Geo.const_of(0.9), Geo.const_of(1.9), -0.7, 0.7, 0.008, 6, 3),
			m.plate2 if set_id != "runner" else m.plate, Vector3(0, 0.0, -0.045))
	for k in 2:
		Geo.add(root, S._shell(0.055, 0.055, -PI, PI, 0.03 - k * 0.11, 0.045 - k * 0.11, 0.006), m.strap, Vector3(0, -0.02, 0))
	if set_id == "bulwark":
		Geo.add(root, S._shell(0.056, 0.058, -1.3, 1.3, -0.36, -0.07, 0.016, 0.008, -0.08), m.plate, Vector3.ZERO)
		Geo.add(root, S._shell(0.074, 0.076, -0.15, 0.15, -0.34, -0.09, 0.006), m.metal, Vector3.ZERO)
	elif set_id == "trooper":
		Geo.add(root, S._shell(0.052, 0.054, -0.9, 0.9, -0.3, -0.12, 0.01, 0.006, -0.06), m.plate2, Vector3.ZERO)
	return root
