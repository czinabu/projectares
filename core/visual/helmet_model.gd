extends RefCounted
## The helmet models, one per visor `mode` (see `Visor`), built in code like
## every greybox shape and worn the same in every view (first person leaves
## it out with the head, `ActorSkin.hide_head`; never a copy of its own).
## Used through `ActorSkin.build_helmet`.
##
## Grounded military sci-fi (Caleb's tactical pass, concept in the shared
## folder's ares/tactical-gear): every helmet is a shell with a real outline
## (a superellipsoid, so it reads as a helmet on a head, never a ball), a
## brow line and a rim, glass in a frame, and the fittings that say what
## the visor does:
## - Scrap visor (""): a dented pot with bolted patches, cracked goggles on
##   a strap and a cloth wrap.
## - Spotter ("zoom", recon): high-cut over the ears for a headset, side
##   rails, a respirator, a smoked half visor and a flip-down rangefinder.
## - Seeker ("scan", intel): full-cut, a wraparound visor under a heavy
##   brow, a vented jaw guard and the scan emitter on the crown.
## - Warden ("threat", assault): a low dome over a faceplate that juts to a
##   prow, a narrow lit slit, cheek plates, neck lames and sensor eyes all
##   round; seen from behind, panel seams, bolted ear armour under side
##   rails with a light on one, a loop patch and an IFF strobe on the crown.
## Worn with an armor frame, every helmet but the scrap visor takes the
## frame's plate, trim and fabric colours.
## - Ember ("thermal"): broad ceramic shell, a thermal lens in the middle of
##   the face and glowing heat sinks over the ears.
## - "slit": an army exo's closed helm, the Warden's shape in its colours.
## The head is hidden under a helmet, so each has a dark hood: an open face
## reads as a balaclava, never as a hole. A Mk2 wears a lit seam over the
## crown. Built from `GearShapes` and merged into a mesh per material.
## Front is -Z; the middle of the head is the origin.

const G := preload("res://core/visual/gear_shapes.gd")

## The head a helmet is built round (`ActorSkin.helmet_size`); a helmet is
## drawn this much smaller than its measure, so it sits on a head.
const HEAD := Vector3(0.27, 0.31, 0.31)
const FIT := 0.86
## The hood under every helmet.
const R := Vector3(0.127, 0.146, 0.146)

## How square the helmet being built is (the superellipsoid's power) and
## its shell's radii, set by each design.
static var N := 2.0
static var _r := Vector3(0.13, 0.115, 0.15)


## The materials one helmet is made of.
class Kit:
	var plate: StandardMaterial3D
	var plate2: StandardMaterial3D
	var fabric: StandardMaterial3D
	var metal: StandardMaterial3D
	var rubber: StandardMaterial3D
	var hood: StandardMaterial3D
	var glow: StandardMaterial3D
	var dim: StandardMaterial3D
	var visor: StandardMaterial3D
	var glass: StandardMaterial3D
	var glint: StandardMaterial3D
	var trim: StandardMaterial3D

	func _init(mode: String, accent: Color, shell: Color, colors := {}) -> void:
		var base: Color = PALETTE.get(mode, shell)
		if mode == "slit":
			base = shell
		var rough := 0.85 if mode == "" else 0.62
		# Worn with an armor frame, the shell takes the frame's colours (its
		# paint too), so helmet and plates read as one kit.
		base = colors.get("plate", base)
		plate = G.mat(base, rough, 0.15 if mode != "" else 0.35)
		plate2 = G.mat(colors.get("plate2", base.darkened(0.42)), 0.7, 0.2)
		fabric = G.mat(colors.get("fabric", base.darkened(0.3).lerp(Color(0.3, 0.28, 0.24), 0.5)), 0.97)
		metal = G.mat(Color(0.55, 0.56, 0.57), 0.32, 0.85)
		rubber = G.mat(Color(0.05, 0.05, 0.055), 0.92)
		hood = G.mat(Color(0.05, 0.05, 0.055), 0.95)
		glow = G.glow(accent, 2.6)
		dim = G.glow(accent, 0.9)
		visor = G.glow(accent, 1.2)
		glass = G.glass(accent)
		glint = G.glint()
		trim = G.glow(accent, 1.4)


## Each design's shell colour; "slit" takes the colour it is given.
const PALETTE := {
	"": Color(0.42, 0.3, 0.2),
	"zoom": Color(0.44, 0.48, 0.53),
	"scan": Color(0.36, 0.37, 0.27),
	"threat": Color(0.26, 0.27, 0.29),
	"thermal": Color(0.54, 0.55, 0.54),
}


## The helmet for `mode`, its glass lit in `glass`, sized round a head of
## `size`; `shell_color` colours an exo's closed helm ("slit"). `tier` 2
## adds the Mk2 trim. The model is merged: what it is made of is listed in
## its "parts" meta (`GearShapes.has_part`). `colors` ("plate", "plate2",
## "fabric") are the worn frame's (`ActorSkin.helmet_colors`), {} for the
## helmet's own.
static func build(mode: String, glass: Color, size: Vector3, shell_color: Color, tier := 1, colors := {}) -> Node3D:
	var root := Node3D.new()
	root.name = "HelmetModel"
	root.scale = Vector3.ONE * FIT * size.x / HEAD.x
	var m := Kit.new(mode, glass, shell_color, colors)
	_hood(root, m)
	N = {"": 2.2, "zoom": 2.6, "scan": 2.7, "threat": 3.0, "thermal": 2.6, "slit": 3.0}.get(mode, 2.4)
	match mode:
		"zoom":
			_spotter(root, m)
		"scan":
			_seeker(root, m)
		"threat", "slit":
			_warden(root, m)
		"thermal":
			_ember(root, m)
		_:
			_scav(root, m)
	if tier >= 2 and mode != "slit" and mode != "":
		# A lit seam from the brow over the crown to the nape.
		var seam := _r * 1.04
		G.add(root, "Mk2Trim", hc(seam, G.const_of(0.12), G.const_of(1.15), -0.03, 0.03, 0.004, 2, 6), m.trim)
		G.add(root, "Mk2TrimBack", hc(seam, G.const_of(0.12), G.const_of(1.6), PI - 0.03, PI + 0.03, 0.004, 2, 6), m.trim)
	N = 2.0
	return G.merge(root)


static func hc(r: Vector3, top: Callable, bot: Callable, from: float, to: float, thick: float,
		az_steps := 24, pol_steps := 10, flat := false, push := Callable()) -> ArrayMesh:
	return G.cap(r, top, bot, from, to, thick, az_steps, pol_steps, flat, push, N)


## The balaclava over the whole head, and the neck.
static func _hood(root: Node3D, m: Kit) -> void:
	# Kept under the lowest crown (the Warden's), so it never shows through.
	G.add(root, "Hood", G.cap(R * Vector3(0.92, 0.86, 0.93), G.const_of(0.0), G.const_of(PI * 0.97), -PI, PI, 0.003, 20, 8),
			m.hood, Vector3(0, -R.y * 0.16, R.z * 0.02))
	G.cyl(root, "Neck", R.x * 0.62, R.y * 0.5, m.hood, Vector3(0, -R.y * 1.0, R.z * 0.12))


## Scrap visor: a dented pot helmet welded from two, with patches bolted
## over the holes, a work lamp taped to the brow, goggles on a strap, one
## lens cracked and flickering, and a cloth wrap.
static func _scav(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.13, 0.11, 0.148)
	_r = r
	var dent := func(p: float, a: float) -> float:
		# Dents: a few soft hollows knocked into the crown.
		return 1.0 - 0.04 * exp(-pow((a - 0.9) / 0.35, 2.0) - pow((p - 0.7) / 0.3, 2.0)) \
				- 0.03 * exp(-pow((a + 2.2) / 0.4, 2.0) - pow((p - 1.0) / 0.3, 2.0))
	G.add(root, "Shell", hc(r, G.const_of(0.0), G.const_of(G.pol(0.12)), -PI, PI, 0.01, 32, 9, false, dent), m.plate)
	G.add(root, "Lip", hc(r * 1.05, G.const_of(G.pol(0.2)), G.const_of(G.pol(0.1)), -PI, PI, 0.008, 32, 1), m.plate2)
	# Patches bolted on, a rivet at each corner.
	for p: Array in [[0.7, 0.55, Vector2(0.06, 0.045), 0.3], [-2.0, 0.5, Vector2(0.05, 0.05), -0.2]]:
		var a: float = p[0]
		var y: float = p[1]
		var out := Vector3(sin(a), 0.0, -cos(a))
		var at := Vector3(sin(a) * r.x * 0.98, r.y * y, -cos(a) * r.z * 0.98) * 1.02
		var basis := Basis.looking_at(-out) * Basis(Vector3.BACK, p[3])
		var size: Vector2 = p[2]
		G.box(root, "Patch", Vector3(size.x, size.y, 0.006), m.metal, at, 0.002, basis)
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			G.box(root, "Rivet", Vector3.ONE * 0.008, m.plate2, at + basis * Vector3(c.x * size.x * 0.38, c.y * size.y * 0.36, 0.004), 0.002)
	# The goggles: a strap round the head, two round lenses, one cracked.
	G.add(root, "Strap", G.band(0.124, 0.142, -PI, PI, -0.012, 0.012, 0.006), m.rubber, Vector3(0, 0.0, 0.0))
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 0.042, 0.0, -0.142)
		G.cyl(root, "Goggle", 0.03, 0.026, m.plate2, at, Basis(Vector3.RIGHT, PI * 0.5), 14)
		G.cyl(root, "Glass", 0.024, 0.028, m.glass, at, Basis(Vector3.RIGHT, PI * 0.5), 14)
	G.box(root, "Bridge", Vector3(0.03, 0.01, 0.012), m.plate2, Vector3(0, 0.0, -0.146), 0.002)
	for c: Array in [[Vector3(0.04, 0.008, -0.157), 0.7], [Vector3(0.05, -0.006, -0.157), -0.4], [Vector3(0.033, -0.008, -0.157), 2.0]]:
		G.box(root, "Crack", Vector3(0.022, 0.0025, 0.002), m.dim, c[0], 0.0005, Basis(Vector3.BACK, c[1]))
	# A welded seam over the crown where two pots were joined, its beads proud.
	G.add(root, "Weld", hc(r * 1.012, G.const_of(0.05), G.const_of(G.pol(0.2)), -PI * 0.5 - 0.04, -PI * 0.5 + 0.04, 0.006, 2, 10),
			m.plate2)
	G.add(root, "Weld", hc(r * 1.012, G.const_of(0.05), G.const_of(G.pol(0.2)), PI * 0.5 - 0.04, PI * 0.5 + 0.04, 0.006, 2, 10),
			m.plate2)
	# A scavenged work lamp taped to the brow, its lens lit, and its cell
	# cabled down the side.
	G.box(root, "Lamp", Vector3(0.034, 0.024, 0.03), m.plate2, Vector3(-0.045, r.y * 0.62, -r.z * 0.93), 0.004,
			Basis(Vector3.RIGHT, -0.35))
	G.cyl(root, "Lamp", 0.01, 0.006, m.visor, Vector3(-0.045, r.y * 0.6, -r.z * 1.02), Basis(Vector3.RIGHT, PI * 0.5 - 0.35), 10)
	G.box(root, "Tape", Vector3(0.05, 0.008, 0.034), m.fabric, Vector3(-0.045, r.y * 0.62, -r.z * 0.93), 0.002,
			Basis(Vector3.RIGHT, -0.35))
	G.box(root, "Cell", Vector3(0.012, 0.04, 0.026), m.plate2, Vector3(-r.x * 1.02, r.y * 0.25, -0.03), 0.003)
	G.add(root, "Cable", G.band(r.x * 1.03, r.z * 1.0, -1.6, -0.35, r.y * 0.38, r.y * 0.4, 0.004), m.rubber)
	# A cloth wrap over the mouth and the neck.
	var wrap := func(p: float, a: float) -> float: return 1.0 + 0.05 * maxf(0.0, cos(a)) * smoothstep(1.9, 2.4, p)
	G.add(root, "Wrap", G.cap(Vector3(0.122, 0.135, 0.142), G.const_of(G.pol(-0.22)), G.const_of(G.pol(-0.98)), -PI, PI, 0.01,
			24, 5, true, wrap), m.fabric)


## Thermal helmet: a broad ceramic shell over the ears, a thermal lens in
## the middle of the face under a slit of glass, heat sinks glowing over
## the ears and an exhaust grille at the back.
static func _ember(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.142, 0.115, 0.15)
	_r = r
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return G.pol(lerpf(0.2, -0.6, smoothstep(0.8, 1.4, aa)))
	var shape := func(p: float, a: float) -> float:
		return 1.0 - 0.05 * maxf(0.0, cos(a)) * sin(p)
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.014, 40, 12, false, shape), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.06
	G.add(root, "Lip", hc(r * 1.03, lip, edge, -PI, PI, 0.006, 40, 1, false, shape), m.plate2)
	# The face: a dark mask from the brow down, a slit of glass across it.
	var ftop := func(a: float) -> float: return G.pol(lerpf(0.22, 0.12, absf(a) / 1.4))
	var fbot := func(a: float) -> float: return G.pol(lerpf(-0.9, -0.6, absf(a) / 1.4))
	var face := func(p: float, a: float) -> float: return 1.0 + 0.08 * pow(maxf(0.0, cos(a)), 2.0) * smoothstep(1.6, 2.4, p)
	G.add(root, "Mask", hc(r * Vector3(0.98, 1.0, 1.0), ftop, fbot, -1.4, 1.4, 0.016, 24, 8, false, face), m.plate2)
	var vtop := func(_a: float) -> float: return G.pol(0.12)
	var vbot := func(_a: float) -> float: return G.pol(0.0)
	G.add(root, "Glass", hc(r * Vector3(0.99, 1.0, 1.015), vtop, vbot, -1.2, 1.2, 0.012, 22, 2, false, face), m.glass)
	# The thermal lens: a ring, the glass and its lit eye.
	var lens_at := Vector3(0.0, -0.035, -r.z * 1.04)
	G.cyl(root, "LensRing", 0.032, 0.03, m.metal, lens_at, Basis(Vector3.RIGHT, PI * 0.5), 18)
	G.cyl(root, "Lens", 0.025, 0.034, m.glass, lens_at, Basis(Vector3.RIGHT, PI * 0.5), 18)
	G.cyl(root, "LensEye", 0.009, 0.036, m.glow, lens_at, Basis(Vector3.RIGHT, PI * 0.5), 12)
	# Heat sinks over the ears: fins with light between them.
	for side: float in [-1.0, 1.0]:
		var x := side * r.x * 1.0
		G.box(root, "SinkGlow", Vector3(0.012, 0.06, 0.07), m.glow, Vector3(x, -0.02, 0.01), 0.003)
		for k in 4:
			G.box(root, "Sink", Vector3(0.024, 0.07, 0.008), m.plate2, Vector3(x + side * 0.004, -0.02, -0.022 + k * 0.021), 0.002)
	# An exhaust grille low at the back.
	G.box(root, "Exhaust", Vector3(0.07, 0.04, 0.016), m.plate2, Vector3(0, -0.04, r.z * 1.0), 0.004, Basis(Vector3.RIGHT, -0.2))
	for k in 3:
		G.box(root, "ExhaustGlow", Vector3(0.05, 0.004, 0.004), m.dim, Vector3(0, -0.052 + k * 0.012, r.z * 1.0 + 0.009), 0.001,
				Basis(Vector3.RIGHT, -0.2))


## High-cut recon helmet: the ears open for a headset, side rails, a front
## shroud carrying a flip-down rangefinder, and a smoked half visor.
static func _spotter(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.13, 0.112, 0.15)
	_r = r
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
		return G.pol(y)
	var brow := func(p: float, a: float) -> float:
		# A brow line: the front is drawn flatter and juts a touch at the rim.
		var front := maxf(0.0, cos(a))
		return 1.0 - 0.05 * front * sin(p) + 0.04 * front * smoothstep(0.9, 1.3, p)
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.012, 40, 10, false, brow), m.plate)
	# A rubber edge trim along the cut.
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.08
	G.add(root, "Part", hc(r * 1.035, lip, edge, -PI, PI, 0.006, 40, 1, false, brow), m.rubber)
	# A loop patch on top.
	G.box(root, "Part", Vector3(0.085, 0.008, 0.06), m.fabric, Vector3(0, r.y * 1.0, r.z * 0.12), 0.003,
			Basis(Vector3.RIGHT, -0.12))
	# Side rails.
	for side: float in [-1.0, 1.0]:
		var rail := G.box(root, "Part", Vector3(0.016, 0.022, 0.13), m.plate2, Vector3(side * r.x * 1.02, -0.005, -0.005), 0.003)
		rail.rotation = Vector3(0.18, 0, 0)
		for k in 4:
			G.box(root, "Part", Vector3(0.006, 0.006, 0.014), m.metal, Vector3(side * (r.x * 1.02 + 0.008), -0.004, -0.05 + k * 0.03), 0.001)
		# The headset ear cups under the rails.
		var cup := G.cyl(root, "Part", 0.045, 0.034, m.rubber, Vector3(side * (r.x * 0.98), -0.055, 0.005), Basis(Vector3.BACK, PI * 0.5), 16)
		G.cyl(root, "Part", 0.03, 0.012, m.plate2, Vector3(side * (r.x * 0.98 + 0.021), -0.055, 0.005), Basis(Vector3.BACK, PI * 0.5), 12)
		G.box(root, "Part", Vector3(0.004, 0.012, 0.012), m.dim, Vector3(side * (r.x * 0.98 + 0.028), -0.045, 0.02), 0.001)
		cup.name = "Cup"
	# A boom mic off the left cup.
	var boom := G.cyl(root, "Part", 0.004, 0.11, m.rubber, Vector3(-r.x * 0.88, -0.1, -0.06), Basis.from_euler(Vector3(PI * 0.5 - 0.35, 0.45, 0)))
	boom.name = "Boom"
	G.box(root, "Part", Vector3(0.016, 0.012, 0.02), m.rubber, Vector3(-r.x * 0.62, -0.115, -0.115), 0.004)
	# The front shroud and the rangefinder on its arm, flipped down over the right eye.
	G.box(root, "Part", Vector3(0.05, 0.03, 0.022), m.plate2, Vector3(0, r.y * 0.62, -r.z * 0.84), 0.005, Basis(Vector3.RIGHT, -0.5))
	G.box(root, "Part", Vector3(0.03, 0.05, 0.016), m.plate2, Vector3(0.012, r.y * 0.4, -r.z * 1.06), 0.004, Basis(Vector3.RIGHT, -0.15))
	var body := G.box(root, "Part", Vector3(0.05, 0.034, 0.06), m.plate2, Vector3(0.04, r.y * 0.16, -r.z * 1.14), 0.006)
	body.name = "Rangefinder"
	G.cyl(root, "Part", 0.015, 0.012, m.metal, Vector3(0.04, r.y * 0.16, -r.z * 1.14 - 0.034), Basis(Vector3.RIGHT, PI * 0.5), 14)
	G.cyl(root, "Lens0", 0.011, 0.004, m.glow, Vector3(0.04, r.y * 0.16, -r.z * 1.14 - 0.041), Basis(Vector3.RIGHT, PI * 0.5), 14)
	G.box(root, "Part", Vector3(0.012, 0.006, 0.01), m.glow, Vector3(0.068, r.y * 0.16 + 0.008, -r.z * 1.14 - 0.01), 0.001)
	# The half visor: smoked glass from cheek to cheek, under the brow.
	var vtop := func(_a: float) -> float: return G.pol(0.16)
	var vbot := func(a: float) -> float: return G.pol(lerpf(-0.36, -0.2, absf(a) / 1.45))
	var visor := G.add(root, "Glass", hc(r * Vector3(1.06, 1.0, 1.1), vtop, vbot, -1.45, 1.45, 0.006, 26, 4), m.glass)
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ltop := func(a: float) -> float: return G.pol(lerpf(-0.34, -0.18, absf(a) / 1.3))
	var lbot := func(a: float) -> float: return G.pol(lerpf(-0.36, -0.2, absf(a) / 1.3))
	G.add(root, "Part", hc(r * Vector3(1.065, 1.0, 1.105), ltop, lbot, -1.3, 1.3, 0.004, 24, 1), m.dim)
	# A frame along the top of the visor, and a glint across the glass.
	var ftop2 := func(_a: float) -> float: return G.pol(0.2)
	var fbot2 := func(_a: float) -> float: return G.pol(0.14)
	G.add(root, "Part", hc(r * Vector3(1.075, 1.0, 1.115), ftop2, fbot2, -1.5, 1.5, 0.008, 26, 1), m.plate2)
	var gtop := func(a: float) -> float: return G.pol(lerpf(0.08, 0.04, absf(a) / 1.2))
	var gbot := func(a: float) -> float: return G.pol(lerpf(0.065, 0.03, absf(a) / 1.2))
	G.add(root, "Part", hc(r * Vector3(1.068, 1.0, 1.108), gtop, gbot, -1.0, 0.6, 0.002, 18, 1), m.glint)
	# Visor pivots at the temples.
	for side: float in [-1.0, 1.0]:
		G.cyl(root, "Part", 0.014, 0.012, m.metal, Vector3(side * r.x * 1.05, r.y * 0.1, -r.z * 0.3), Basis(Vector3.BACK, PI * 0.5), 10)
	# A half-face respirator under the visor, two filters angled down.
	var mtop := func(a: float) -> float: return G.pol(lerpf(-0.3, -0.18, absf(a) / 1.3))
	var mbot := func(_a: float) -> float: return G.pol(-0.92)
	var mask_push := func(p: float, a: float) -> float: return 1.0 + 0.06 * maxf(0.0, cos(a)) * smoothstep(1.8, 2.4, p)
	G.add(root, "Part", hc(Vector3(0.118, 0.128, 0.142), mtop, mbot, -1.3, 1.3, 0.012, 18, 5, false, mask_push), m.rubber)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 0.07, -0.085, -0.115)
		var b := Basis.from_euler(Vector3(PI * 0.5 - 0.5, side * 0.6, 0.0))
		G.cyl(root, "Part", 0.024, 0.026, m.plate2, at, b, 14)
		G.cyl(root, "Part", 0.018, 0.028, m.metal, at, b, 14)
	G.box(root, "Part", Vector3(0.03, 0.03, 0.02), m.plate2, Vector3(0, -0.105, -0.152), 0.006)
	G.box(root, "Part", Vector3(0.016, 0.004, 0.004), m.dim, Vector3(0, -0.1, -0.163), 0.001)
	# A strobe on the back.
	G.box(root, "Part", Vector3(0.03, 0.02, 0.012), m.plate2, Vector3(0, r.y * 0.62, r.z * 0.86), 0.004, Basis(Vector3.RIGHT, 0.6))
	G.box(root, "Part", Vector3(0.018, 0.006, 0.004), m.glow, Vector3(0, r.y * 0.64, r.z * 0.9), 0.001, Basis(Vector3.RIGHT, 0.6))
	# A counterweight pouch on the back.
	G.box(root, "Part", Vector3(0.07, 0.045, 0.03), m.fabric, Vector3(0, r.y * 0.15, r.z * 1.0), 0.008, Basis(Vector3.RIGHT, 0.12))


## Full-cut intel helmet: covers the ears, a mandible jaw guard with vents,
## a wide wraparound visor under a heavy brow, and a scan emitter on the crown.
static func _seeker(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.132, 0.115, 0.152)
	_r = r
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		var y := lerpf(0.22, -0.55, smoothstep(0.75, 1.4, aa))
		if aa > 2.3:
			y = lerpf(-0.55, -0.62, (aa - 2.3) / (PI - 2.3))
		return G.pol(y)
	var shape := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		var back := maxf(0.0, -cos(a))
		# Swept back over the nape, a flat face.
		return 1.0 - 0.06 * front * sin(p) + 0.05 * back * smoothstep(1.2, 2.0, p)
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.014, 44, 12, false, shape), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.07
	G.add(root, "Part", hc(r * 1.03, lip, edge, -PI, PI, 0.006, 44, 1, false, shape), m.plate2)
	# Brow plate: a hard ridge over the visor.
	var btop := func(a: float) -> float: return G.pol(lerpf(0.42, 0.3, absf(a) / 1.6))
	var bbot := func(a: float) -> float: return G.pol(lerpf(0.2, 0.12, absf(a) / 1.6))
	G.add(root, "Part", hc(r * Vector3(1.08, 1.0, 1.12), btop, bbot, -1.6, 1.6, 0.016, 26, 3, false, shape), m.plate2)
	# Wide wraparound visor.
	var vtop := func(a: float) -> float: return G.pol(lerpf(0.2, 0.12, absf(a) / 1.55))
	var vbot := func(a: float) -> float: return G.pol(lerpf(-0.22, -0.1, absf(a) / 1.55))
	var visor := G.add(root, "Glass", hc(r * Vector3(1.05, 1.0, 1.07), vtop, vbot, -1.55, 1.55, 0.006, 28, 4, false, shape), m.glass)
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A lit line under the visor.
	var ltop := func(a: float) -> float: return G.pol(lerpf(-0.22, -0.1, absf(a) / 1.45))
	var lbot := func(a: float) -> float: return G.pol(lerpf(-0.25, -0.13, absf(a) / 1.45))
	G.add(root, "Part", hc(r * Vector3(1.06, 1.0, 1.08), ltop, lbot, -1.45, 1.45, 0.004, 24, 1, false, shape), m.glow)
	# The visor's frame: a band under it and bezels at its ends; a glint.
	var ubot := func(a: float) -> float: return G.pol(lerpf(-0.32, -0.19, absf(a) / 1.55))
	G.add(root, "Part", hc(r * Vector3(1.075, 1.0, 1.1), lbot, ubot, -1.58, 1.58, 0.01, 28, 1, false, shape), m.plate2)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(sin(side * 1.58) * r.x * 1.06, -0.005, -cos(side * 1.58) * r.z * 1.06)
		G.box(root, "Part", Vector3(0.016, 0.05, 0.03), m.plate2, at, 0.004)
		G.box(root, "Part", Vector3(0.004, 0.012, 0.012), m.dim, at + Vector3(side * 0.009, 0, 0), 0.001)
	var gtop := func(a: float) -> float: return G.pol(lerpf(0.12, 0.07, absf(a) / 1.2))
	var gbot := func(a: float) -> float: return G.pol(lerpf(0.1, 0.055, absf(a) / 1.2))
	G.add(root, "Part", hc(r * Vector3(1.058, 1.0, 1.078), gtop, gbot, -1.1, 0.5, 0.002, 18, 1, false, shape), m.glint)
	# The mandible: a jaw guard wrapping the chin, set out from the face.
	var jtop := func(a: float) -> float: return G.pol(lerpf(-0.27, -0.12, absf(a) / 1.5))
	var jbot := func(a: float) -> float: return G.pol(lerpf(-0.95, -0.62, absf(a) / 1.5))
	var jaw_shape := func(p: float, a: float) -> float:
		return 1.0 + 0.04 * maxf(0.0, cos(a)) - 0.04 * smoothstep(2.4, 2.9, p)
	G.add(root, "Part", hc(r * Vector3(1.0, 1.08, 1.0), jtop, jbot, -1.5, 1.5, 0.016, 20, 5, false, jaw_shape), m.plate)
	# Breathing vents on the jaw.
	for side: float in [-1.0, 1.0]:
		for k in 3:
			G.box(root, "Part", Vector3(0.022, 0.005, 0.01), m.rubber,
					Vector3(side * 0.04, -r.y * (0.5 + k * 0.1), -r.z * 1.07 + k * 0.008), 0.001, Basis(Vector3.UP, side * 0.45))
		G.box(root, "Part", Vector3(0.006, 0.07, 0.03), m.metal, Vector3(side * r.x * 0.92, -r.y * 0.5, -r.z * 0.62), 0.002,
				Basis(Vector3.UP, side * 0.9))
	# Scan emitter on the crown: housing, lit ring, dome.
	var crown := Vector3(0, r.y * 0.96, r.z * 0.1)
	G.cyl(root, "Part", 0.05, 0.022, m.plate2, crown, Basis.IDENTITY, 20)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.041
	ring.outer_radius = 0.049
	G.add(root, "Fin", ring, m.glow, crown + Vector3(0, 0.012, 0))
	G.add(root, "Part", hc(Vector3(0.036, 0.018, 0.036), G.const_of(0.0), G.const_of(PI * 0.5), -PI, PI, 0.002, 16, 4), m.metal,
			crown + Vector3(0, 0.012, 0))
	# A sensor pod on the left with an antenna; a camera block on the right.
	G.box(root, "Part", Vector3(0.03, 0.05, 0.08), m.plate2, Vector3(-r.x * 1.07, r.y * 0.12, 0.0), 0.007)
	G.box(root, "Part", Vector3(0.004, 0.012, 0.05), m.glow, Vector3(-r.x * 1.07 - 0.016, r.y * 0.16, -0.005), 0.001)
	G.cyl(root, "Part", 0.0035, 0.22, m.rubber, Vector3(-r.x * 1.0, r.y * 0.8, r.z * 0.45), Basis.from_euler(Vector3(-0.5, 0, 0.18)), 6)
	G.box(root, "Part", Vector3(0.028, 0.036, 0.05), m.plate2, Vector3(r.x * 1.07, r.y * 0.1, -0.02), 0.006)
	G.cyl(root, "Part", 0.011, 0.012, m.glass, Vector3(r.x * 1.07, r.y * 0.1, -0.05), Basis(Vector3.RIGHT, PI * 0.5), 12)


## Closed assault helm: faceted, a crest, a narrow T visor, heavy cheek
## plates, a neck guard of lames, and sensor eyes all round.
static func _warden(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.134, 0.106, 0.152)
	_r = r
	# The dome: cut at the brow in front, low over the ears and nape.
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return G.pol(lerpf(0.2, -0.55, smoothstep(0.9, 1.6, aa)))
	var dome := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		# A hard brow ridge along the cut.
		return 1.0 + 0.09 * front * smoothstep(1.05, 1.36, p) - 0.04 * front * sin(p)
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.018, 40, 12, false, dome), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.06
	G.add(root, "Brow", hc(r * 1.03, lip, edge, -PI, PI, 0.006, 40, 1, false, dome), m.metal)
	# The faceplate: from the brow to under the chin, jutting to a prow.
	var face := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		return 1.0 + 0.2 * pow(front, 3.0) * smoothstep(1.6, 2.5, p)
	var ftop := func(a: float) -> float: return G.pol(lerpf(0.16, 0.05, absf(a) / 1.55))
	var fbot := func(a: float) -> float: return G.pol(lerpf(-0.92, -0.6, absf(a) / 1.55))
	G.add(root, "Part", hc(r * Vector3(0.98, 1.0, 1.0), ftop, fbot, -1.55, 1.55, 0.018, 12, 5, true, face), m.plate2)
	# The visor slit: dark glass, a thin lit line inside it.
	var vtop := func(a: float) -> float: return G.pol(lerpf(0.06, 0.03, absf(a) / 1.1))
	var vbot := func(a: float) -> float: return G.pol(lerpf(-0.04, -0.03, absf(a) / 1.1))
	G.add(root, "Glass", hc(r * Vector3(0.995, 1.0, 1.02), vtop, vbot, -1.1, 1.1, 0.02, 22, 1, true, face), m.glass)
	var ltop := func(a: float) -> float: return G.pol(lerpf(0.015, 0.0, absf(a) / 1.0))
	var lbot := func(a: float) -> float: return G.pol(lerpf(-0.01, -0.012, absf(a) / 1.0))
	G.add(root, "Part", hc(r * Vector3(1.0, 1.0, 1.03), ltop, lbot, -1.0, 1.0, 0.02, 22, 1, true, face), m.visor)
	# Cheek plates layered over the faceplate, with breather grilles.
	for side: float in [-1.0, 1.0]:
		var from := 0.55 if side > 0 else -1.85
		var to := 1.85 if side > 0 else -0.55
		var ctop := func(_a: float) -> float: return G.pol(-0.12)
		var cbot := func(a: float) -> float: return G.pol(lerpf(-0.78, -0.62, absf(absf(a) - 0.55) / 1.3))
		G.add(root, "Part", hc(r * Vector3(1.07, 1.0, 1.06), ctop, cbot, from, to, 0.018, 10, 4, true, face), m.plate)
		for k in 3:
			G.box(root, "Part", Vector3(0.006, 0.006, 0.03), m.rubber, Vector3(side * 0.06, -0.075 - k * 0.014, -0.135), 0.001,
					Basis(Vector3.UP, side * 0.7))
		# Sensor eyes round the sides and back (threat sense).
		for k in 2:
			var a := side * (1.5 + k * 0.85)
			var at := Vector3(sin(a) * r.x * 1.05, r.y * 0.22, -cos(a) * r.z * 1.02)
			var look := Basis.looking_at(Vector3(sin(a), 0, -cos(a))) * Basis(Vector3.RIGHT, PI * 0.5)
			G.cyl(root, "Part", 0.013, 0.014, m.plate2, at, look, 10)
			G.cyl(root, "Part", 0.008, 0.004, m.glow, at + Vector3(sin(a), 0, -cos(a)) * 0.008, look, 10)
	# Neck guard: two lames at the back.
	for k in 2:
		var ntop := func(_a: float) -> float: return G.pol(-0.48 - k * 0.2)
		var nbot := func(_a: float) -> float: return G.pol(-0.72 - k * 0.2)
		G.add(root, "Part", hc(r * (1.06 + k * 0.05), ntop, nbot, PI - 1.6, PI + 1.6, 0.014, 20, 2, false), m.plate2 if k else m.plate)
	# A low crest fin from the brow back over the crown.
	var fin := G.box(root, "Part", Vector3(0.018, 0.026, 0.2), m.plate2, Vector3(0, r.y * 0.98, 0.0), 0.006, Basis(Vector3.RIGHT, 0.08))
	fin.name = "Crest"
	G.box(root, "Part", Vector3(0.02, 0.005, 0.14), m.dim, Vector3(0, r.y * 0.98 + 0.014, 0.01), 0.001, Basis(Vector3.RIGHT, 0.08))
	_warden_back(root, m, r, edge)


## What a Warden shows from behind and the sides (Caleb's screenshot: it read
## as a plain dark dome next to the tactical armor): seams cut into the dome,
## bolted ear armour with accessory rails over it, a light on the right rail,
## a loop patch and an IFF strobe high on the back. The back of the head at
## the vitals strip's height (`ActorSkin.vitals_offset`) is left clear.
static func _warden_back(root: Node3D, m: Kit, r: Vector3, edge: Callable) -> void:
	# The dome's outside (its shell stands 0.018 off `r`), where these sit.
	var skin := r + Vector3.ONE * 0.017
	# Panel seams down the dome, from the crown to the rim.
	for a: float in [-2.35, -0.95, 0.95, 2.35]:
		var stop := func(x: float) -> float: return float(edge.call(x)) - 0.05
		G.add(root, "Seam", hc(skin, G.const_of(G.pol(0.93)), stop, a - 0.02, a + 0.02, 0.004, 1, 8), m.rubber)
	for side: float in [-1.0, 1.0]:
		var from := side * 1.2 if side > 0 else -2.1
		var to := 2.1 if side > 0 else -1.2
		# Ear armour: a raised plate over each side, in the trim colour.
		var etop := func(_a: float) -> float: return G.pol(0.22)
		var ebot := func(_a: float) -> float: return G.pol(-0.5)
		G.add(root, "EarArmor", hc(skin, etop, ebot, from, to, 0.012, 10, 5, true), m.plate2)
		var mid := side * 1.65
		var out := Vector3(sin(mid), 0, -cos(mid))
		for k in 4:
			var at := Vector3(sin(mid + (k % 2 - 0.5) * 0.5) * (skin.x + 0.012), r.y * (0.08 - (0.5 if k >= 2 else 0.0)),
					-cos(mid + (k % 2 - 0.5) * 0.5) * (skin.z + 0.012))
			G.cyl(root, "Bolt", 0.006, 0.006, m.metal, at, Basis.looking_at(out) * Basis(Vector3.RIGHT, PI * 0.5), 8)
		# An accessory rail along the top of the ear armour, slotted.
		var rail_at := Vector3(side * (skin.x + 0.012), r.y * 0.3, r.z * 0.06)
		G.box(root, "Rail", Vector3(0.014, 0.02, 0.15), m.plate2, rail_at, 0.003, Basis(Vector3.RIGHT, 0.12))
		for k in 5:
			G.box(root, "Part", Vector3(0.006, 0.022, 0.008), m.metal,
					rail_at + Vector3(side * 0.006, 0.0, -0.06 + k * 0.03), 0.001, Basis(Vector3.RIGHT, 0.12))
	# A light clipped to the right rail, its lens forward.
	var lamp := Vector3(skin.x + 0.03, r.y * 0.3, -r.z * 0.2)
	G.box(root, "Lamp", Vector3(0.024, 0.026, 0.05), m.plate2, lamp, 0.005)
	G.cyl(root, "Part", 0.01, 0.006, m.dim, lamp + Vector3(0, 0, -0.026), Basis(Vector3.RIGHT, PI * 0.5), 12)
	# A loop patch high on the back, and an IFF strobe on the crown behind the crest.
	G.add(root, "Patch", hc(skin, G.const_of(G.pol(0.86)), G.const_of(G.pol(0.66)), PI - 0.42, PI + 0.42, 0.005, 6, 2),
			m.fabric)
	G.box(root, "Strobe", Vector3(0.03, 0.016, 0.034), m.plate2, Vector3(0, skin.y * 0.88, skin.z * 0.55), 0.005,
			Basis(Vector3.RIGHT, 0.55))
	G.box(root, "Part", Vector3(0.016, 0.005, 0.02), m.dim, Vector3(0, skin.y * 0.88 + 0.009, skin.z * 0.55 + 0.004), 0.001,
			Basis(Vector3.RIGHT, 0.55))
