extends RefCounted
## The helmet models, one per visor `mode` (see `Visor`), built in code like
## every greybox shape and worn the same in every view (first person leaves
## it out with the head, `ActorSkin.hide_head`; never a copy of its own).
## Used through `ActorSkin.build_helmet`.
##
## Sci-fi soldier and cyberpunk, each an original design, tall rather than
## flat or wide (Caleb's call): a shell with a real outline (a
## superellipsoid, never a ball), glass in a frame, and the fittings that
## say what the visor does:
## - Junker (scrap, ""): a riveted bucket with a weld seam and a patch, a
##   gas mask with filter cans, one cracked round goggle ("Crack") and a
##   neck wrap.
## - Spotter ("zoom", recon): a sleek visor with a light and a glint, vents,
##   a rangefinder on the side ("Lens0".."Lens2"), ear pods, two antennas
##   and a spine.
## - Seeker ("scan", intel): a faceted face with three slits of lit glass
##   over a grille, ribbed ear plates, a sensor bar and the scan emitter
##   ("Fin") on the crown.
## - Warden ("threat", assault): a faceted shell under a "Brow", a prow
##   face with a chevron visor, cheek plates, sensor eyes, swept blades,
##   neck lames and a crest; seen from behind, panel seams, bolted ear
##   armour, a loop patch and an IFF strobe.
## - Ember ("thermal"): a tall ceramic shell and faceplate with one thermal
##   eye ("Lens"), a snout with hoses, crown fins, heat sinks and exhaust.
## - "slit": an army exo's closed helm, the Warden's shape in its colours.
## Worn with an armor frame, every helmet but the scrap visor takes the
## frame's plate, trim and fabric colours. Sized to the head per axis
## (`ActorSkin.helmet_size`).
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
	root.scale = FIT * size / HEAD
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


## The outside of a shell of radii `r` stood `thick` off it, at polar `p`
## and azimuth `a`, before any push: where fittings sit on it.
static func on_shell(r: Vector3, p: float, a: float, out := 0.0) -> Vector3:
	var dir := Vector3(sin(p) * sin(a), cos(p), -sin(p) * cos(a))
	var k := 1.0 / pow(pow(absf(dir.x), N) + pow(absf(dir.y), N) + pow(absf(dir.z), N), 1.0 / N)
	return dir * (r * k) + dir * out


## Which way is out from the head at polar `p`, azimuth `a`.
static func out_dir(p: float, a: float) -> Vector3:
	return Vector3(sin(p) * sin(a), cos(p), -sin(p) * cos(a))


## A basis whose -Z looks along `dir` (for a lens or a pod set into a shell).
static func facing(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.BACK
	return Basis.looking_at(dir, up)


## A round fitting (a lens, a canister) of `radius` and `depth` standing out
## along `dir` at `at`.
static func disc(root: Node3D, part: String, radius: float, depth: float, material: Material, at: Vector3, dir: Vector3,
		sides := 16) -> void:
	G.cyl(root, part, radius, depth, material, at, facing(dir) * Basis(Vector3.RIGHT, PI * 0.5), sides)


## Junker (the scrap visor, ""): a tall riveted bucket welded up from
## scrap, a gas mask strapped under it with two filter cans splayed out, one
## round goggle eye (cracked) and a welded vision slot for the other, a
## riveted seam band, a welded ridge over the crown and a rag round the neck.
static func _scav(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.124, 0.142, 0.146)
	_r = r
	var dent := func(p: float, a: float) -> float:
		return 1.0 - 0.035 * exp(-pow((a - 0.9) / 0.35, 2.0) - pow((p - 0.7) / 0.3, 2.0)) \
				- 0.03 * exp(-pow((a + 2.2) / 0.4, 2.0) - pow((p - 1.1) / 0.3, 2.0))
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return G.pol(lerpf(0.02, -0.5, smoothstep(0.9, 1.5, aa)))
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.012, 32, 10, true, dent), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.06
	G.add(root, "Lip", hc(r * 1.04, lip, edge, -PI, PI, 0.008, 32, 1, true), m.plate2)
	# A riveted band round the middle where the two halves were joined.
	G.add(root, "Band", hc(r * 1.02, G.const_of(G.pol(0.36)), G.const_of(G.pol(0.26)), -PI, PI, 0.008, 32, 1, true), m.metal)
	for k in 16:
		var a := TAU * k / 16.0
		var at := on_shell(r, G.pol(0.31), a, 0.022)
		G.box(root, "Rivet", Vector3.ONE * 0.009, m.plate2, at, 0.002, facing(out_dir(G.pol(0.31), a)))
	# A welded ridge over the crown, front to back, its beads proud.
	G.add(root, "Weld", hc(r * 1.015, G.const_of(0.04), G.const_of(G.pol(-0.2)), -0.035, 0.035, 0.008, 2, 12, true), m.plate2)
	G.add(root, "Weld", hc(r * 1.015, G.const_of(0.04), G.const_of(G.pol(-0.3)), PI - 0.035, PI + 0.035, 0.008, 2, 12, true), m.plate2)
	# A patch bolted over a hole.
	var pat := on_shell(r, 0.75, -2.0, 0.014)
	G.box(root, "Patch", Vector3(0.05, 0.045, 0.006), m.metal, pat, 0.002, facing(out_dir(0.75, -2.0)) * Basis(Vector3.BACK, 0.3))
	# The gas mask under the brim: a rubber face from the eyes down.
	var mtop := func(_a: float) -> float: return G.pol(0.06)
	var mbot := func(a: float) -> float: return G.pol(lerpf(-0.95, -0.6, absf(a) / 1.5))
	var snout := func(p: float, a: float) -> float: return 1.0 + 0.1 * pow(maxf(0.0, cos(a)), 3.0) * smoothstep(1.7, 2.5, p)
	G.add(root, "Mask", hc(r * Vector3(0.96, 1.0, 0.98), mtop, mbot, -1.5, 1.5, 0.012, 20, 6, false, snout), m.rubber)
	# Two filter cans splayed down and out, ringed in the accent.
	for side: float in [-1.0, 1.0]:
		var dir := Vector3(side * 0.75, -0.45, -0.5).normalized()
		var at := Vector3(side * 0.052, -0.098, -0.142)
		disc(root, "Filter", 0.03, 0.05, m.plate2, at + dir * 0.022, dir, 14)
		disc(root, "FilterRing", 0.031, 0.008, m.dim, at + dir * 0.04, dir, 14)
		disc(root, "FilterCap", 0.024, 0.052, m.metal, at + dir * 0.026, dir, 14)
	# The eyes: a round goggle on the left (cracked), a welded slot on the right.
	var eye_l := Vector3(-0.042, 0.012, 0.0)
	eye_l.z = on_shell(r * Vector3(0.96, 1.0, 0.98), G.pol(0.04), -0.32).z - 0.004
	disc(root, "Goggle", 0.032, 0.028, m.plate2, eye_l, Vector3.FORWARD, 16)
	disc(root, "Glass", 0.026, 0.032, m.glass, eye_l, Vector3.FORWARD, 16)
	for c: Array in [[Vector3(-0.036, 0.02, 0.0), 0.7], [Vector3(-0.048, 0.008, 0.0), -0.4], [Vector3(-0.04, 0.004, 0.0), 2.0]]:
		var at: Vector3 = c[0]
		at.z = eye_l.z - 0.018
		G.box(root, "Crack", Vector3(0.02, 0.0025, 0.002), m.dim, at, 0.0005, Basis(Vector3.BACK, c[1]))
	var slot := Vector3(0.044, 0.012, eye_l.z + 0.002)
	G.box(root, "Slot", Vector3(0.058, 0.03, 0.016), m.metal, slot, 0.003)
	G.box(root, "Glass", Vector3(0.044, 0.008, 0.004), m.glass, slot + Vector3(0, 0, -0.008), 0.001)
	G.box(root, "SlotGlow", Vector3(0.03, 0.003, 0.002), m.dim, slot + Vector3(0, 0, -0.011), 0.0005)
	# A rag wound round the neck.
	var wrap := func(p: float, a: float) -> float: return 1.0 + 0.04 * sin(a * 5.0) * smoothstep(2.2, 2.6, p)
	G.add(root, "Wrap", G.cap(Vector3(0.112, 0.15, 0.13), G.const_of(G.pol(-0.62)), G.const_of(G.pol(-0.98)), -PI, PI, 0.012,
			24, 4, true, wrap), m.fabric)


## Ember (thermal): a tall rounded ceramic helm. One big thermal eye in the
## middle of a dark faceplate with a slit of glass across it, a rebreather
## snout with hoses running back, three cooling fins over the crown,
## glowing heat sinks over the ears and an exhaust at the back.
static func _ember(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.124, 0.14, 0.148)
	_r = r
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return G.pol(lerpf(0.3, -0.62, smoothstep(0.7, 1.5, aa)))
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.014, 40, 12), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.05
	G.add(root, "Lip", hc(r * 1.03, lip, edge, -PI, PI, 0.006, 40, 1), m.plate2)
	# The faceplate: dark, from the brow under the chin, a little proud.
	var face := func(p: float, a: float) -> float: return 1.0 + 0.04 * pow(maxf(0.0, cos(a)), 2.0)
	var ftop := func(a: float) -> float: return G.pol(lerpf(0.32, 0.18, absf(a) / 1.3))
	var fbot := func(a: float) -> float: return G.pol(lerpf(-0.95, -0.66, absf(a) / 1.3))
	G.add(root, "Mask", hc(r * Vector3(0.97, 1.0, 0.99), ftop, fbot, -1.3, 1.3, 0.016, 24, 8, false, face), m.plate2)
	var vtop := func(_a: float) -> float: return G.pol(0.13)
	var vbot := func(_a: float) -> float: return G.pol(0.04)
	G.add(root, "Glass", hc(r * Vector3(0.98, 1.0, 1.01), vtop, vbot, -1.15, 1.15, 0.012, 22, 2, false, face), m.glass)
	# The thermal eye: a ring, its glass and its lit pupil, between the eyes.
	var lens_at := on_shell(r * Vector3(0.97, 1.0, 0.99), G.pol(0.08), 0.0, 0.028)
	disc(root, "LensRing", 0.036, 0.034, m.metal, lens_at, Vector3.FORWARD, 20)
	disc(root, "Lens", 0.028, 0.038, m.glass, lens_at, Vector3.FORWARD, 20)
	disc(root, "LensEye", 0.01, 0.04, m.glow, lens_at, Vector3.FORWARD, 12)
	# The rebreather snout, and a hose from each side of it round to the back.
	var snout := on_shell(r, G.pol(-0.62), 0.0, 0.02)
	G.box(root, "Snout", Vector3(0.06, 0.05, 0.05), m.plate, snout, 0.012, Basis(Vector3.RIGHT, 0.35))
	for k in 3:
		G.box(root, "SnoutVent", Vector3(0.04, 0.004, 0.004), m.dim, snout + Vector3(0, -0.012 + k * 0.012, -0.027), 0.001,
				Basis(Vector3.RIGHT, 0.35))
	for side: float in [-1.0, 1.0]:
		var from := snout + Vector3(side * 0.03, -0.005, 0.01)
		var to := on_shell(r, G.pol(-0.5), side * 2.3, 0.02)
		var mid := on_shell(r, G.pol(-0.62), side * 1.2, 0.03)
		for seg: Array in [[from, mid], [mid, to]]:
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			G.cyl(root, "Hose", 0.009, a.distance_to(b) + 0.012, m.rubber, (a + b) * 0.5,
					Basis(Quaternion(Vector3.UP, (b - a).normalized())), 8)
	# Three cooling fins over the crown, front to back.
	for x: float in [-0.04, 0.0, 0.04]:
		var at := on_shell(r, 0.25 + absf(x) * 4.0, PI * 0.5 * signf(x) if x != 0.0 else 0.0, 0.0)
		at.x = x
		at.z = 0.02
		G.box(root, "CrownFin", Vector3(0.008, 0.024 - absf(x) * 0.15, 0.16), m.plate2, at + Vector3(0, 0.008, 0), 0.003)
	# Heat sinks over the ears: fins with light between them.
	for side: float in [-1.0, 1.0]:
		var at := on_shell(r, G.pol(-0.12), side * PI * 0.5, 0.0)
		G.box(root, "SinkGlow", Vector3(0.012, 0.06, 0.07), m.glow, at, 0.003)
		for k in 4:
			G.box(root, "Sink", Vector3(0.026, 0.072, 0.008), m.plate2, at + Vector3(side * 0.006, 0, -0.03 + k * 0.02), 0.002)
	# An exhaust grille low at the back.
	var ex := on_shell(r, G.pol(-0.3), PI, 0.008)
	G.box(root, "Exhaust", Vector3(0.07, 0.04, 0.016), m.plate2, ex, 0.004, Basis(Vector3.RIGHT, -0.2))
	for k in 3:
		G.box(root, "ExhaustGlow", Vector3(0.05, 0.004, 0.004), m.dim, ex + Vector3(0, -0.012 + k * 0.012, 0.009), 0.001,
				Basis(Vector3.RIGHT, -0.2))


## Spotter (zoom, recon): a sleek full helm, tall and narrow. A smooth
## wraparound visor under a shallow brow, lit along its foot; a sculpted
## mouth guard; a three-lens rangefinder on an arm over the right eye; slim
## ear pods ringed in light; a raised spine over the crown and two short
## antennas swept back off the left.
static func _spotter(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.12, 0.142, 0.148)
	_r = r
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return G.pol(lerpf(0.16, -0.66, smoothstep(0.85, 1.55, aa)))
	var brow := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		return 1.0 + 0.04 * front * smoothstep(0.95, 1.3, p) - 0.03 * front * sin(p)
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.012, 40, 12, false, brow), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.05
	G.add(root, "Lip", hc(r * 1.03, lip, edge, -PI, PI, 0.006, 40, 1, false, brow), m.rubber)
	# A raised spine over the crown, brow to nape.
	G.add(root, "Spine", hc(r * 1.012, G.const_of(G.pol(0.86)), G.const_of(G.pol(-0.4)), PI - 0.12, PI + 0.12, 0.012, 3, 12), m.plate2)
	G.add(root, "Spine", hc(r * 1.012, G.const_of(0.0), G.const_of(G.pol(0.4)), -0.12, 0.12, 0.012, 3, 8), m.plate2)
	G.add(root, "SpineLight", hc(r * 1.012 + Vector3.ONE * 0.012, G.const_of(G.pol(0.8)), G.const_of(G.pol(0.2)), PI - 0.02, PI + 0.02,
			0.003, 1, 8), m.dim)
	# The visor: smoked glass cheek to cheek, lit along its foot.
	var vtop := func(a: float) -> float: return G.pol(lerpf(0.16, 0.1, absf(a) / 1.5))
	var vbot := func(a: float) -> float: return G.pol(lerpf(-0.3, -0.12, absf(a) / 1.5))
	var swell := func(p: float, a: float) -> float: return 1.0 + 0.05 * pow(maxf(0.0, cos(a)), 2.0)
	G.add(root, "Glass", hc(r * Vector3(1.02, 1.0, 1.04), vtop, vbot, -1.5, 1.5, 0.008, 28, 5, false, swell), m.glass)
	var ltop := func(a: float) -> float: return G.pol(lerpf(-0.3, -0.12, absf(a) / 1.5) + 0.012)
	var lbot := func(a: float) -> float: return G.pol(lerpf(-0.3, -0.12, absf(a) / 1.5) - 0.006)
	G.add(root, "VisorLight", hc(r * Vector3(1.03, 1.0, 1.05), ltop, lbot, -1.4, 1.4, 0.004, 26, 1, false, swell), m.dim)
	var gtop := func(a: float) -> float: return G.pol(lerpf(0.08, 0.04, absf(a) / 1.2))
	var gbot := func(a: float) -> float: return G.pol(lerpf(0.065, 0.03, absf(a) / 1.2))
	G.add(root, "Glint", hc(r * Vector3(1.03, 1.0, 1.05), gtop, gbot, -1.0, 0.6, 0.002, 18, 1, false, swell), m.glint)
	# The mouth guard: a sculpted plate from under the visor round the chin.
	var jtop := func(a: float) -> float: return G.pol(lerpf(-0.32, -0.14, absf(a) / 1.5))
	var jbot := func(a: float) -> float: return G.pol(lerpf(-0.96, -0.68, absf(a) / 1.5))
	var chin := func(p: float, a: float) -> float: return 1.0 + 0.07 * pow(maxf(0.0, cos(a)), 2.0) * smoothstep(1.8, 2.5, p)
	G.add(root, "Guard", hc(r * Vector3(1.0, 1.02, 1.0), jtop, jbot, -1.5, 1.5, 0.014, 22, 6, true, chin), m.plate2)
	for k in 4:
		G.box(root, "Vent", Vector3(0.028 - k * 0.004, 0.004, 0.006), m.rubber, Vector3(0, -0.07 - k * 0.012, -0.162 + k * 0.004), 0.001)
	# The rangefinder: an arm from the right temple to three lenses over the eye.
	var temple := on_shell(r, G.pol(0.2), 1.25, 0.014)
	G.box(root, "Arm", Vector3(0.014, 0.014, 0.07), m.metal, temple + Vector3(-0.004, 0, -0.03), 0.003, Basis(Vector3.UP, -0.5))
	var body := Vector3(0.05, 0.03, -0.175)
	G.box(root, "Rangefinder", Vector3(0.044, 0.04, 0.03), m.plate2, body, 0.006)
	for k in 3:
		var at := body + Vector3(-0.01 + (k % 2) * 0.02, 0.01 - (k / 2) * 0.02, -0.016)
		disc(root, "Lens%d" % k, 0.008 if k else 0.011, 0.006, m.glow if k == 0 else m.glass, at, Vector3.FORWARD, 12)
	# Ear pods ringed in light.
	for side: float in [-1.0, 1.0]:
		var at := on_shell(r, G.pol(-0.18), side * PI * 0.5, 0.008)
		disc(root, "Pod", 0.034, 0.022, m.plate2, at, Vector3(side, 0, 0), 18)
		disc(root, "PodRing", 0.035, 0.006, m.dim, at + Vector3(side * 0.008, 0, 0), Vector3(side, 0, 0), 18)
		disc(root, "PodCap", 0.024, 0.026, m.metal, at, Vector3(side, 0, 0), 14)
	# Two short antennas swept back off the left pod.
	for k in 2:
		var at := on_shell(r, G.pol(-0.05), -PI * 0.5 - 0.3 - k * 0.25, 0.01)
		G.cyl(root, "Antenna", 0.0035, 0.12 - k * 0.03, m.rubber, at + Vector3(-0.004, 0.045, 0.04),
				Basis.from_euler(Vector3(-0.9, 0, 0.15)), 6)


## Seeker (scan, intel): a tall rounded closed helm with a flat faceted
## faceplate, its eyes three stacked slits of light, a vertical breather
## grille under them, the scan emitter on the crown and two sensor stalks
## raked back from the temples.
static func _seeker(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.122, 0.146, 0.148)
	_r = r
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return G.pol(lerpf(0.26, -0.7, smoothstep(0.85, 1.5, aa)))
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.014, 44, 12), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.05
	G.add(root, "Lip", hc(r * 1.03, lip, edge, -PI, PI, 0.006, 44, 1), m.plate2)
	# The faceplate, faceted and flat to the front.
	var flat := func(p: float, a: float) -> float: return 1.0 - 0.05 * maxf(0.0, cos(a)) * sin(p) + 0.03 * smoothstep(2.2, 2.7, p)
	var ftop := func(a: float) -> float: return G.pol(lerpf(0.3, 0.2, absf(a) / 1.35))
	var fbot := func(a: float) -> float: return G.pol(lerpf(-0.97, -0.72, absf(a) / 1.35))
	G.add(root, "Face", hc(r * Vector3(1.0, 1.0, 1.02), ftop, fbot, -1.35, 1.35, 0.016, 10, 7, true, flat), m.plate2)
	# Three slits of glass across the eyes, each lit along its middle.
	for k in 3:
		var y := 0.14 - k * 0.075
		var w := 0.95 - k * 0.22
		var top := func(_a: float) -> float: return G.pol(y)
		var bot := func(_a: float) -> float: return G.pol(y - 0.035)
		G.add(root, "Glass", hc(r * Vector3(1.0, 1.0, 1.035), top, bot, -w, w, 0.016, 12, 1, true, flat), m.glass)
		var ltop := func(_a: float) -> float: return G.pol(y - 0.014)
		var lbot := func(_a: float) -> float: return G.pol(y - 0.022)
		G.add(root, "SlitLight", hc(r * Vector3(1.0, 1.0, 1.04), ltop, lbot, -w + 0.1, w - 0.1, 0.016, 10, 1, true, flat), m.visor)
	# A vertical breather grille over the mouth.
	for k in 5:
		var x := (k - 2) * 0.012
		var at := on_shell(r * Vector3(1.0, 1.0, 1.02), G.pol(-0.62), x / r.z, 0.03)
		G.box(root, "Grille", Vector3(0.005, 0.04, 0.008), m.rubber, at, 0.001)
	# The scan emitter on the crown: housing, a lit ring, a dome.
	var crown := Vector3(0, r.y * 1.02, r.z * 0.12)
	G.cyl(root, "Emitter", 0.044, 0.02, m.plate2, crown, Basis.IDENTITY, 20)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.036
	ring.outer_radius = 0.044
	G.add(root, "Fin", ring, m.glow, crown + Vector3(0, 0.011, 0))
	G.add(root, "Dome", hc(Vector3(0.03, 0.016, 0.03), G.const_of(0.0), G.const_of(PI * 0.5), -PI, PI, 0.002, 16, 4), m.metal,
			crown + Vector3(0, 0.011, 0))
	# Ribbed ear plates, and a sensor bar across the back of the head.
	for side: float in [-1.0, 1.0]:
		var etop := func(_a: float) -> float: return G.pol(0.2)
		var ebot := func(_a: float) -> float: return G.pol(-0.45)
		G.add(root, "EarPlate", hc(r * 1.02, etop, ebot, side * 1.35 - 0.38, side * 1.35 + 0.38, 0.012, 8, 4, true), m.plate2)
		for k in 4:
			var y := 0.1 - k * 0.14
			var rtop := func(_a: float) -> float: return G.pol(y)
			var rbot := func(_a: float) -> float: return G.pol(y - 0.04)
			G.add(root, "Rib", hc(r * 1.02 + Vector3.ONE * 0.012, rtop, rbot, side * 1.35 - 0.3, side * 1.35 + 0.3, 0.004, 6, 1, true),
					m.rubber)
	var btop := func(_a: float) -> float: return G.pol(0.18)
	var bbot := func(_a: float) -> float: return G.pol(0.06)
	G.add(root, "SensorBar", hc(r * 1.02, btop, bbot, PI - 1.0, PI + 1.0, 0.012, 14, 1, true), m.plate2)
	var stop := func(_a: float) -> float: return G.pol(0.135)
	var sbot := func(_a: float) -> float: return G.pol(0.105)
	G.add(root, "SensorLight", hc(r * 1.02 + Vector3.ONE * 0.012, stop, sbot, PI - 0.8, PI + 0.8, 0.003, 12, 1, true), m.dim)
	# Two sensor stalks raked back from the temples, lit at their tips.
	for side: float in [-1.0, 1.0]:
		var at := on_shell(r, G.pol(0.3), side * 1.5, 0.012)
		var tilt := Basis.from_euler(Vector3(-1.0, 0, side * -0.35))
		G.box(root, "StalkBase", Vector3(0.02, 0.03, 0.04), m.plate2, at, 0.005)
		G.cyl(root, "Stalk", 0.005, 0.11, m.metal, at + tilt * Vector3(0, 0.055, 0), tilt, 8)
		G.box(root, "StalkTip", Vector3(0.012, 0.012, 0.012), m.glow, at + tilt * Vector3(0, 0.112, 0), 0.003, tilt)


## Warden (threat, assault): a faceted, angular closed helm that juts to a
## prow at the chin, a chevron visor pointing down, a heavy brow, layered
## cheek plates and neck lames, sensor eyes all round, and two blades swept
## back off the temples.
static func _warden(root: Node3D, m: Kit) -> void:
	var r := Vector3(0.126, 0.14, 0.152)
	_r = r
	var edge := func(a: float) -> float:
		var aa := absf(wrapf(a, -PI, PI))
		return G.pol(lerpf(0.2, -0.6, smoothstep(0.9, 1.6, aa)))
	var dome := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		return 1.0 + 0.08 * front * smoothstep(1.05, 1.36, p) - 0.03 * front * sin(p)
	G.add(root, "Shell", hc(r, G.const_of(0.0), edge, -PI, PI, 0.018, 24, 9, true, dome), m.plate)
	var lip := func(a: float) -> float: return float(edge.call(a)) - 0.05
	G.add(root, "Brow", hc(r * 1.03, lip, edge, -PI, PI, 0.006, 24, 1, true, dome), m.metal)
	# The faceplate: from the brow to under the chin, jutting to a prow.
	var face := func(p: float, a: float) -> float:
		var front := maxf(0.0, cos(a))
		return 1.0 + 0.18 * pow(front, 3.0) * smoothstep(1.6, 2.5, p)
	var ftop := func(a: float) -> float: return G.pol(lerpf(0.18, 0.06, absf(a) / 1.55))
	var fbot := func(a: float) -> float: return G.pol(lerpf(-0.95, -0.62, absf(a) / 1.55))
	G.add(root, "Face", hc(r * Vector3(0.98, 1.0, 1.0), ftop, fbot, -1.55, 1.55, 0.018, 12, 6, true, face), m.plate2)
	# The chevron visor: a slit that dips to a point in the middle.
	var vtop := func(a: float) -> float: return G.pol(0.08 - 0.06 * (1.0 - absf(a) / 1.1) + 0.03)
	var vbot := func(a: float) -> float: return G.pol(0.08 - 0.06 * (1.0 - absf(a) / 1.1) - 0.03)
	G.add(root, "Glass", hc(r * Vector3(0.995, 1.0, 1.02), vtop, vbot, -1.1, 1.1, 0.02, 22, 1, true, face), m.glass)
	var ltop := func(a: float) -> float: return G.pol(0.08 - 0.06 * (1.0 - absf(a) / 1.0) + 0.005)
	var lbot := func(a: float) -> float: return G.pol(0.08 - 0.06 * (1.0 - absf(a) / 1.0) - 0.005)
	G.add(root, "VisorLight", hc(r * Vector3(1.0, 1.0, 1.03), ltop, lbot, -1.0, 1.0, 0.02, 22, 1, true, face), m.visor)
	# Cheek plates layered over the faceplate, with breather slots.
	for side: float in [-1.0, 1.0]:
		var from := 0.5 if side > 0 else -1.85
		var to := 1.85 if side > 0 else -0.5
		var ctop := func(_a: float) -> float: return G.pol(-0.14)
		var cbot := func(a: float) -> float: return G.pol(lerpf(-0.8, -0.6, absf(absf(a) - 0.5) / 1.3))
		G.add(root, "Cheek", hc(r * Vector3(1.07, 1.0, 1.06), ctop, cbot, from, to, 0.018, 8, 4, true, face), m.plate)
		for k in 3:
			G.box(root, "Slot", Vector3(0.006, 0.006, 0.03), m.rubber, Vector3(side * 0.062, -0.085 - k * 0.015, -0.14), 0.001,
					Basis(Vector3.UP, side * 0.7))
		# Sensor eyes round the sides and back (threat sense).
		for k in 2:
			var a := side * (1.5 + k * 0.85)
			var at := on_shell(r, G.pol(0.24), a, 0.02)
			disc(root, "SensorEye", 0.013, 0.014, m.plate2, at, out_dir(G.pol(0.24), a), 10)
			disc(root, "SensorLight", 0.008, 0.004, m.glow, at + out_dir(G.pol(0.24), a) * 0.008, out_dir(G.pol(0.24), a), 10)
		# A blade swept back off the temple.
		var base := on_shell(r, G.pol(0.55), side * 1.3, 0.016)
		var sweep := Basis.from_euler(Vector3(-1.15, side * -0.25, side * -0.2))
		G.box(root, "Blade", Vector3(0.008, 0.11, 0.03), m.plate2, base + sweep * Vector3(0, 0.05, 0), 0.003, sweep)
		G.box(root, "BladeEdge", Vector3(0.009, 0.08, 0.004), m.dim, base + sweep * Vector3(0, 0.055, -0.016), 0.001, sweep)
	# Neck guard: two lames at the back.
	for k in 2:
		var ntop := func(_a: float) -> float: return G.pol(-0.52 - k * 0.2)
		var nbot := func(_a: float) -> float: return G.pol(-0.76 - k * 0.2)
		G.add(root, "NeckLame", hc(r * (1.06 + k * 0.05), ntop, nbot, PI - 1.6, PI + 1.6, 0.014, 12, 2, true), m.plate2 if k else m.plate)
	# A low crest from the brow back over the crown.
	var fin := G.box(root, "Crest", Vector3(0.016, 0.022, 0.2), m.plate2, Vector3(0, r.y * 1.08, 0.0), 0.005, Basis(Vector3.RIGHT, 0.08))
	fin.name = "Crest"
	G.box(root, "CrestLight", Vector3(0.018, 0.004, 0.14), m.dim, Vector3(0, r.y * 1.08 + 0.012, 0.01), 0.001, Basis(Vector3.RIGHT, 0.08))
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
	# A raised rear plate over the back of the dome, bolted at its corners,
	# ending above the vitals strip.
	G.add(root, "RearPlate", hc(skin, G.const_of(G.pol(0.62)), G.const_of(G.pol(0.1)), PI - 0.75, PI + 0.75,
			0.012, 10, 4, true), m.plate2)
	for a: float in [PI - 0.6, PI + 0.6]:
		for y: float in [0.52, 0.18]:
			var dir := Vector3(sin(a) * sqrt(1.0 - y * y), y, -cos(a) * sqrt(1.0 - y * y))
			G.cyl(root, "Bolt", 0.006, 0.006, m.metal, dir * (skin + Vector3.ONE * 0.012),
					Basis.looking_at(dir) * Basis(Vector3.RIGHT, PI * 0.5), 8)
	# Battery cells low on the back either side of the vitals strip, wired
	# into the rear plate.
	for side: float in [-1.0, 1.0]:
		var a := PI + side * 1.1
		var cell := Vector3(sin(a) * (skin.x + 0.012), -r.y * 0.28, -cos(a) * (skin.z + 0.012))
		var turn := Basis(Vector3.UP, -a)
		G.box(root, "Battery", Vector3(0.034, 0.056, 0.024), m.plate2, cell, 0.005, turn)
		G.box(root, "Part", Vector3(0.026, 0.006, 0.026), m.metal, cell + Vector3(0, 0.03, 0), 0.001, turn)
		G.box(root, "Part", Vector3(0.004, 0.03, 0.004), m.dim, cell + turn * Vector3(0, 0, 0.013), 0.001, turn)
		G.cyl(root, "Part", 0.003, 0.05, m.rubber, cell + Vector3(-side * 0.012, 0.045, 0.004),
				Basis(Vector3.BACK, side * 0.6), 6)
	# A loop patch high on the back, and an IFF strobe on the crown behind the crest.
	G.add(root, "Patch", hc(skin, G.const_of(G.pol(0.86)), G.const_of(G.pol(0.66)), PI - 0.42, PI + 0.42, 0.005, 6, 2),
			m.fabric)
	G.box(root, "Strobe", Vector3(0.03, 0.016, 0.034), m.plate2, Vector3(0, skin.y * 0.88, skin.z * 0.55), 0.005,
			Basis(Vector3.RIGHT, 0.55))
	G.box(root, "Part", Vector3(0.016, 0.005, 0.02), m.dim, Vector3(0, skin.y * 0.88 + 0.009, skin.z * 0.55 + 0.004), 0.001,
			Basis(Vector3.RIGHT, 0.55))
