extends RefCounted
## The armor frame models, built in code and worn the same in every view
## (`ActorSkin._update_frame` hangs each piece on the bone it moves with).
## Grounded military sci-fi, made for the people's bodies (Quaternius'
## Superhero builds): every plate is laid over the body's own measured shape
## (`body_fit.gd`, `GearShapes.sheet`), so it hugs the chest, the back, the
## shoulders and the limbs of whichever build wears it, standing off it by
## the padding under it and bridging the hollows, never a box or a tube.
##
## A frame's weight sets the bulk: light a sculpted chest and back shell on
## a slim harness, shoulder caps, forearm guards and knee and shin plates;
## medium a plate carrier with a cummerbund, pouches, layered pauldrons and
## thigh plates; heavy a full cuirass with a gorget, abdominal lames,
## faulds, big three-lame pauldrons, vambraces, cuisses and greaves. Its
## look (`ActorSkin.FRAME_STYLES`) sets the colours and the details that
## say what it does. Every piece is merged into a mesh per material
## (`GearShapes.merge`), listing its parts in the "parts" meta.
##
## Built in the body's own metres (the measured rig, before `Look` sizes
## it): `ActorSkin` scales a piece by the body's size as it hangs it. The
## torso is built round the "Chest" bone, the belt round the "Hips" bone;
## a limb piece stands up its limb (Y from the far joint toward this one,
## front -Z, +X out on the right) from the joint it hangs on.

const G := preload("res://core/visual/gear_shapes.gd")
const BodyFit := preload("res://core/visual/body_fit.gd")


## The materials one frame is made of.
class Kit:
	var plate: StandardMaterial3D
	var plate2: StandardMaterial3D
	var fabric: StandardMaterial3D
	var strap: StandardMaterial3D
	var metal: StandardMaterial3D
	var rubber: StandardMaterial3D
	var glow: StandardMaterial3D
	var dim: StandardMaterial3D
	var details: Array

	func _init(style: Dictionary) -> void:
		var rough: float = style.get("rough", 0.62)
		plate = G.mat(style["plate"], rough, style.get("metal_finish", 0.15))
		plate2 = G.mat(style["plate2"], minf(1.0, rough + 0.08), 0.2)
		fabric = G.mat(style["fabric"], 0.97)
		strap = G.mat(style["strap"], 0.95)
		metal = G.mat(style["metal"], 0.32, 0.85)
		rubber = G.mat(Color(0.05, 0.05, 0.055), 0.92)
		glow = G.glow(style["accent"], style.get("glow", 2.6))
		dim = G.glow(style["accent"], style.get("glow", 2.6) * 0.35)
		details = style.get("details", [])


## The trunk of the body a torso piece is built round: heights as a share
## `f` of the way from the hips bone (0) to the neck bone (1), so a plate
## lands on the same part of either build, and points relative to the bone
## the piece hangs on.
class Trunk:
	var build: String
	var origin: Vector3
	var low: float
	var high: float

	func _init(b: String, bone: String) -> void:
		build = b
		origin = BodyFit.bone(b, bone)
		low = BodyFit.bone(b, "Hips").y
		high = BodyFit.bone(b, "Neck").y

	## The height `f` of the way up the trunk, the body's frame.
	func y(f: float) -> float:
		return lerpf(low, high, f)

	## The skin at `f` toward angle `a` (0 front, PI/2 right), `gap` out,
	## relative to the bone. With `drape` (a share of the trunk) it hangs
	## straight down from the fullest point that far above, as a plate
	## falls from the chest instead of tucking in under it.
	func at(f: float, a: float, gap := 0.0, drape := 0.0) -> Vector3:
		var r := BodyFit.reach(build, y(f), a)
		for k in 4:
			if drape > 0.0:
				r = maxf(r, BodyFit.reach(build, y(f + drape * (k + 1) / 4.0), a))
		r += gap
		return Vector3(r * sin(a), y(f), BodyFit.axis_z() - r * cos(a)) - origin

	## Which way is out from the skin there, level.
	func out(a: float) -> Vector3:
		return Vector3(sin(a), 0.0, -cos(a))

	## A plate's inner face for `GearShapes.sheet`: from `f0` to `f1` up the
	## trunk and angle `a0` to `a1` round it, `gap` off the skin. `scoop`
	## lowers the top edge in the middle (a neckline), `bulge` swells the
	## middle out, `taper` narrows the top (+) or bottom (-) toward the middle.
	func wrap(f0: float, f1: float, a0: float, a1: float, gap: float, scoop := 0.0, bulge := 0.0, taper := 0.0,
			drape := 0.0) -> Callable:
		return func(u: float, v: float) -> Vector3:
			var mid := (a0 + a1) * 0.5
			var half := (a1 - a0) * 0.5 * (1.0 - maxf(taper, 0.0) * v - maxf(-taper, 0.0) * (1.0 - v))
			var a := mid + (u * 2.0 - 1.0) * half
			var w := 1.0 - absf(u * 2.0 - 1.0)
			var top := f1 - scoop * w * w
			var f := lerpf(f0, top, v)
			return at(f, a, gap + bulge * sin(PI * u) * sin(PI * v), minf(drape, top - f))


## One limb of the body a limb piece is built round (`BodyFit.limb_point`).
class Limb:
	var build: String
	var name: String
	var side: float
	var length: float

	func _init(b: String, limb: String, out: float) -> void:
		build = b
		name = limb
		side = out
		length = BodyFit.limb_length(b, limb)

	## The skin `t` of the way down the limb (0 the joint) toward angle `a`
	## (0 front, PI/2 the piece's +X), `gap` out.
	func at(t: float, a: float, gap := 0.0) -> Vector3:
		return BodyFit.limb_point(build, name, t * length, a, side, gap)

	## A plate's inner face: from `t0` to `t1` down the limb, `half` either
	## side of angle `centre`, `gap` off the skin; `bulge` swells it out in
	## the middle, `flare` opens its top end (+) out. Past the joint (`t`
	## under 0) it rolls in over the end of the limb like a dome (a
	## shoulder cap), never standing out as a shelf.
	func wrap(t0: float, t1: float, centre: float, half: float, gap: float, bulge := 0.0, flare := 0.0) -> Callable:
		return func(u: float, v: float) -> Vector3:
			var a := centre + (u * 2.0 - 1.0) * half
			var t := lerpf(t1, t0, v)
			var g := gap + bulge * sin(PI * u) * sin(PI * v) + flare * v * v
			if t >= 0.0:
				return at(t, a, g)
			var rim := at(0.0, a, g)
			var r := Vector2(rim.x, rim.z).length()
			var past := minf(-t * length, r * 0.92)
			var ring := sqrt(r * r - past * past)
			return Vector3(rim.x * ring / r, past, rim.z * ring / r)


static func _root(piece: String) -> Node3D:
	var root := Node3D.new()
	root.name = piece
	return root


## A plate over the body: `point` from a `Trunk.wrap` or `Limb.wrap`.
static func plate(root: Node3D, part: String, point: Callable, thick: float, material: Material, cols := 16, rows := 7) -> void:
	G.add(root, part, G.sheet(point, thick, cols, rows, minf(0.02, thick * 1.4 + 0.006)), material)


## Something flat stood on the skin at `at` facing `out`: a box `size`
## (x across, y up, z off the surface).
static func on(root: Node3D, part: String, size: Vector3, material: Material, at: Vector3, out: Vector3, r := 0.003,
		turn := 0.0) -> void:
	var z := -out.normalized()
	var x := Vector3.UP.cross(z).normalized() if absf(z.y) < 0.95 else Vector3.RIGHT
	var y := z.cross(x)
	var b := Basis(x, y, z) * Basis(Vector3.BACK, turn)
	G.box(root, part, size, material, at + out.normalized() * size.z * 0.5, r, b)


## A pouch on a surface facing `out`: a body, a flap over its top with a
## buckle, a seam along its foot.
static func pouch(root: Node3D, m: Kit, size: Vector3, at: Vector3, out: Vector3, body: Material = null) -> void:
	var z := -out.normalized()
	var x := Vector3.UP.cross(z).normalized() if absf(z.y) < 0.95 else Vector3.RIGHT
	var basis := Basis(x, z.cross(x), z)
	var mid := at + out.normalized() * size.z * 0.5
	G.box(root, "Pouch", size, body if body else m.fabric, mid, minf(0.007, size.x * 0.15), basis)
	var flap := Vector3(size.x * 1.05, size.y * 0.34, size.z * 1.08)
	var top := mid + basis * Vector3(0, size.y * 0.5 - flap.y * 0.45, 0)
	G.box(root, "Flap", flap, m.strap, top, minf(0.006, flap.y * 0.3), basis)
	G.box(root, "Buckle", Vector3(size.x * 0.32, flap.y * 0.5, 0.006), m.metal, top + basis * Vector3(0, -flap.y * 0.35, -flap.z * 0.5),
			0.0015, basis)
	G.box(root, "Seam", Vector3(size.x * 1.02, 0.005, size.z * 1.03), m.strap, mid + basis * Vector3(0, -size.y * 0.42, 0), 0.0015, basis)


## ---------------------------------------------------------------- torso

## The torso round the chest bone. Named plates: "Chest" and "Back" always,
## "Carrier" under them, "Strap" over the shoulders, "Side" for a
## cummerbund (not light), "Collar" (the gorget) and "Belly" lames on heavy.
static func torso(weight: String, style: Dictionary, build := "m") -> Node3D:
	var root := _root("FrameModel")
	var m := Kit.new(style)
	var b := Trunk.new(build, "Chest")
	var heavy := weight == "heavy"
	var light := weight == "light"
	# Scrap is strapped on crooked.
	var skew := 0.08 if "patches" in m.details else 0.0
	# The carrier (fabric) under the plates, front and back.
	var cw := 1.1 if light else 1.25
	var cg := 0.006
	plate(root, "Carrier", b.wrap(0.36 if light else 0.3, 0.86, -cw, cw, cg, 0.07, 0.0, 0.0, 0.25), 0.01, m.fabric)
	var bw := cw * 0.78
	plate(root, "Carrier", b.wrap(0.34 if light else 0.3, 0.88, PI - bw, PI + bw, cg, 0.03, 0.0, 0.18, 0.2), 0.01, m.fabric)
	# The hard plates: sculpted over the chest, thicker and further out the
	# heavier the frame.
	var pg: float = {"light": 0.018, "medium": 0.022, "heavy": 0.026}[weight]
	var pt: float = {"light": 0.012, "medium": 0.016, "heavy": 0.022}[weight]
	var pw: float = {"light": 0.85, "medium": 0.98, "heavy": 1.4}[weight]
	var chest_low := 0.42 if heavy else 0.5
	plate(root, "Chest", b.wrap(chest_low, 0.88, -pw + skew, pw + skew, pg, 0.07, 0.008, 0.12 if not heavy else 0.0, 0.25), pt, m.plate, 20, 9)
	# The back plate stays between the shoulder blades and narrows to the
	# top, so from behind it never reads wider than the back.
	var back_w: float = {"light": 0.68, "medium": 0.76, "heavy": 0.98}[weight]
	plate(root, "Back", b.wrap(0.44 if heavy else 0.48, 0.9, PI - back_w, PI + back_w, pg - 0.004, 0.03, 0.004, 0.2, 0.2), pt, m.plate, 20, 9)
	_plate_lines(root, m, b, chest_low, pw, pg + pt, heavy, back_w)
	if heavy:
		# The cuirass closes down the sides, layered abdominal lames under it,
		# each edged in steel.
		for side: float in [-1.0, 1.0]:
			plate(root, "SidePlate", b.wrap(0.46, 0.76, side * 1.5 - 0.42, side * 1.5 + 0.42, pg - 0.008), pt * 0.8, m.plate2, 8, 6)
		for k in 3:
			var top := 0.46 - k * 0.1
			var w := 1.3 - k * 0.1
			plate(root, "Belly" if k == 0 else "Belly%d" % k, b.wrap(top - 0.13, top, -w, w, pg - 0.004 + k * 0.004, 0.0, 0.004), pt * 0.8,
					m.plate2 if k % 2 else m.plate, 16, 4)
			plate(root, "LameEdge", b.wrap(top - 0.135, top - 0.12, -w + 0.04, w - 0.04, pg + pt * 0.8 + k * 0.004 - 0.006), 0.004, m.metal, 16, 1)
		# The gorget round the neck, edged in steel.
		plate(root, "Collar", b.wrap(0.86, 1.0, -2.4, 2.4, 0.02, 0.0, 0.0, -0.1), 0.016, m.plate2, 24, 4)
		plate(root, "CollarEdge", b.wrap(0.985, 1.0, -2.3, 2.3, 0.036), 0.006, m.metal, 24, 1)
	# Shoulder straps over each shoulder from the chest plate to the back.
	for side: float in [-1.0, 1.0]:
		var a := side * 0.42
		var points := []
		for k in 7:
			var s := float(k) / 6.0
			# Over the top: up the front, across the trapezius, down the back.
			var ang := lerpf(a, side * (PI - 0.42), s)
			var f := 0.86 + 0.12 * sin(PI * s)
			points.append(b.at(f, ang, cg + 0.006))
		_strap(root, m, points, 0.055 if heavy else 0.045, 0.012)
	# The cummerbund round the sides with webbing rows; elastic on light.
	for side: float in [-1.0, 1.0]:
		var a0 := side * (cw - 0.15)
		var a1 := side * (PI - cw + 0.15)
		if light:
			for k in 2:
				var f := 0.42 + k * 0.08
				plate(root, "Elastic", b.wrap(f, f + 0.035, minf(a0, a1), maxf(a0, a1), 0.004), 0.006, m.strap, 10, 1)
			continue
		plate(root, "Side", b.wrap(0.28, 0.55, minf(a0, a1), maxf(a0, a1), 0.008), 0.014, m.fabric, 10, 4)
		for k in 3:
			var f := 0.32 + k * 0.07
			plate(root, "Webbing", b.wrap(f, f + 0.018, minf(a0, a1) + 0.06, maxf(a0, a1) - 0.06, 0.022), 0.004, m.strap, 10, 1)
	# Magazine pouches across the front below the plate, each with its cell's
	# lit gauge.
	var mags := 2 if light else 3
	var pf := 0.36 if heavy else 0.42
	for i in mags:
		var a := (i - (mags - 1) * 0.5) * 0.36
		var at := b.at(pf, a, pg + pt + (0.004 if not heavy else 0.02))
		pouch(root, m, Vector3(0.058, 0.09, 0.036), at, b.out(a), m.plate2 if heavy else m.fabric)
		on(root, "Gauge", Vector3(0.022, 0.005, 0.004), m.dim, at + b.out(a) * 0.036 + Vector3(0, -0.012, 0), b.out(a), 0.001)
	if not heavy:
		# A thin status strip high on the plate.
		on(root, "Status", Vector3(0.045, 0.006, 0.004), m.glow, b.at(0.8, -0.32, pg + pt), b.out(-0.32), 0.001)
	# A drag handle at the top of the back plate.
	on(root, "Handle", Vector3(0.08, 0.02, 0.014), m.strap, b.at(0.9, PI, pg + pt), b.out(PI) + Vector3(0, 0.3, 0), 0.005)
	_torso_details(root, m, b, pg + pt, light, heavy)
	return G.merge(root)


## A strap laid along `points` (on the body), `width` wide, `thick` thick.
static func _strap(root: Node3D, m: Kit, points: Array, width: float, thick: float) -> void:
	var n := points.size()
	var point := func(u: float, v: float) -> Vector3:
		var f := v * (n - 1)
		var k := mini(int(f), n - 2)
		var p: Vector3 = (points[k] as Vector3).lerp(points[k + 1], f - k)
		var along: Vector3 = (points[k + 1] - points[k]).normalized()
		# Across the strap: level and square to its run.
		var across := along.cross(Vector3(p.x, 0.0, p.z).normalized() if Vector3(p.x, 0, p.z).length() > 0.01 else Vector3.FORWARD)
		across = across.normalized() if across.length() > 0.001 else Vector3.RIGHT
		return p + across * (u - 0.5) * width
	G.add(root, "Strap", G.sheet(point, thick, 2, (n - 1) * 2, 0.008), m.fabric)


## Depth on the chest and back plates, so they read as moulded armor: a
## raised rim round the top, a pressed line under the pecs and down the
## middle, and an ID placard on the chest.
static func _plate_lines(root: Node3D, m: Kit, b: Trunk, low: float, front_w: float, out: float, heavy: bool,
		back_w := 0.8) -> void:
	for back: float in [0.0, PI]:
		var pw := front_w if back == 0.0 else back_w * 0.85
		var top := 0.88 if back == 0.0 else 0.9
		var scoop := 0.07 if back == 0.0 else 0.03
		plate(root, "PlateRim", b.wrap(top - 0.03, top, back - pw + 0.04, back + pw - 0.04, out - 0.004, scoop), 0.007, m.plate2, 18, 1)
		# Under the pecs (front) or the shoulder blades (back).
		var f := lerpf(low, top, 0.42)
		plate(root, "PanelLine", b.wrap(f, f + 0.012, back - pw * 0.8, back + pw * 0.8, out - 0.002, -0.05), 0.004, m.plate2, 16, 1)
		# Down the middle.
		plate(root, "PanelLine", b.wrap(low + 0.04, top - 0.12, back - 0.02, back + 0.02, out - 0.002), 0.004, m.plate2, 1, 6)
	if heavy or front_w > 0.9:
		var at := b.at(0.78, 0.0, out)
		on(root, "Placard", Vector3(0.09, 0.034, 0.008), m.plate2, at, Vector3.FORWARD)
		on(root, "PlacardTag", Vector3(0.024, 0.01, 0.004), m.dim, at + Vector3(-0.026, 0, -0.008), Vector3.FORWARD, 0.001)


## What says which frame it is, on top of its weight.
static func _torso_details(root: Node3D, m: Kit, b: Trunk, out: float, light: bool, heavy: bool) -> void:
	var d := m.details
	if "patches" in d:
		# Patch plates bolted over the rust, a rivet at each corner.
		for p: Array in [[0.7, 0.35, Vector2(0.075, 0.055), 0.25], [0.58, -0.4, Vector2(0.06, 0.05), -0.18]]:
			var at := b.at(p[0], p[1], out)
			var size: Vector2 = p[2]
			on(root, "Patch", Vector3(size.x, size.y, 0.007), m.metal, at, b.out(p[1]), 0.002, p[3])
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var turn := Basis(Vector3.UP, -float(p[1])) * Basis(Vector3.BACK, p[3])
				on(root, "Rivet", Vector3.ONE * 0.01, m.plate2, at + turn * Vector3(c.x * size.x * 0.38, c.y * size.y * 0.36, 0) + b.out(p[1]) * 0.006,
						b.out(p[1]), 0.003)
	if "spine" in d or light:
		# A slim spine panel on the back; a runner's lit down its length.
		on(root, "BackPanel", Vector3(0.06, 0.16, 0.022), m.plate2, b.at(0.66, PI, out), b.out(PI), 0.008)
		on(root, "PanelLight", Vector3(0.008, 0.12, 0.004), m.glow, b.at(0.66, PI, out + 0.022), b.out(PI), 0.001)
	if "radio" in d:
		# A radio on the left side, its antenna up the back.
		var a := -1.75
		on(root, "Radio", Vector3(0.05, 0.11, 0.04), m.fabric, b.at(0.5, a, 0.02), b.out(a), 0.008)
		on(root, "RadioHead", Vector3(0.035, 0.03, 0.045), m.plate2, b.at(0.5, a, 0.02) + Vector3(0, 0.07, 0), b.out(a), 0.005)
		on(root, "RadioLight", Vector3(0.006, 0.006, 0.006), m.glow, b.at(0.5, a, 0.065) + Vector3(0, 0.07, 0), b.out(a), 0.001)
		G.cyl(root, "Antenna", 0.003, 0.32, m.rubber, b.at(0.86, -2.6, out + 0.01) + Vector3(0, 0.14, 0), Basis(Vector3.BACK, 0.12), 6)
	if "admin" in d:
		# An admin pouch over the mags, its tag lit.
		var at := b.at(0.53, 0.0, out + 0.002)
		on(root, "Admin", Vector3(0.12, 0.06, 0.02), m.fabric, at, Vector3.FORWARD, 0.006)
		on(root, "AdminTag", Vector3(0.05, 0.02, 0.004), m.glow, at + Vector3(0.025, 0, -0.02), Vector3.FORWARD, 0.001)
	if "hydration" in d:
		# A hydration carrier on the back, webbing across it.
		plate(root, "Hydration", b.wrap(0.48, 0.82, PI - 0.55, PI + 0.55, out + 0.004, 0.0, 0.02), 0.03, m.fabric, 10, 6)
		for k in 4:
			var f := 0.52 + k * 0.08
			plate(root, "Webbing", b.wrap(f, f + 0.014, PI - 0.56, PI + 0.56, out + 0.032), 0.004, m.strap, 10, 1)
	if "vents" in d:
		# Heat vents in the back plate, glowing: it runs hot.
		for x: float in [-0.32, 0.32]:
			on(root, "VentFrame", Vector3(0.06, 0.12, 0.012), m.plate2, b.at(0.68, PI + x, out), b.out(PI + x), 0.003)
			for k in 4:
				on(root, "Vent", Vector3(0.044, 0.008, 0.006), m.glow, b.at(0.68, PI + x, out + 0.01) + Vector3(0, -0.04 + k * 0.026, 0),
						b.out(PI + x), 0.001)
	if "chevrons" in d:
		for x: float in [-1.0, 1.0]:
			on(root, "Chevron", Vector3(0.05, 0.008, 0.004), m.glow, b.at(0.66, x * 0.42, out), b.out(x * 0.42), 0.001, x * 0.35)
	if "quilt" in d:
		# A padded collar and quilted rings at the waist.
		plate(root, "Quilt", b.wrap(0.88, 1.0, -PI, PI, 0.004, 0.0, 0.006, -0.1), 0.016, m.fabric, 24, 3)
		for k in 2:
			var f := 0.24 - k * 0.07
			plate(root, "Quilt", b.wrap(f - 0.06, f, -PI, PI, 0.004, 0.0, 0.006), 0.012, m.fabric, 24, 2)
	if "coils" in d:
		# Heat coils glowing across the chest plate.
		for k in 3:
			var f := 0.6 + k * 0.06
			plate(root, "Coil", b.wrap(f, f + 0.012, -0.55, 0.55, out + 0.001), 0.003, m.glow, 12, 1)
	if "heater" in d:
		# A heater pack low on the back, its grille lit.
		on(root, "Heater", Vector3(0.16, 0.1, 0.05), m.plate, b.at(0.4, PI, out), b.out(PI), 0.01)
		for k in 3:
			on(root, "Grille", Vector3(0.11, 0.008, 0.004), m.glow, b.at(0.4, PI, out + 0.05) + Vector3(0, -0.025 + k * 0.025, 0),
					b.out(PI), 0.001)


## ---------------------------------------------------------------- belt

## A battle belt round the hips with pouches; heavy adds armored faulds.
static func belt(weight: String, style: Dictionary, build := "m") -> Node3D:
	var root := _root("BeltModel")
	var m := Kit.new(style)
	var b := Trunk.new(build, "Hips")
	var f0 := 0.08
	var f1 := 0.16
	for half: float in [0.0, PI]:
		plate(root, "Belt", b.wrap(f0, f1, half - PI * 0.5, half + PI * 0.5, 0.004), 0.012, m.strap, 16, 2)
	var mid := (f0 + f1) * 0.5
	on(root, "BeltBuckle", Vector3(0.05, 0.036, 0.01), m.metal, b.at(mid, 0.0, 0.016), Vector3.FORWARD, 0.003)
	var pouches := [[-1.35, Vector3(0.055, 0.075, 0.04)], [1.35, Vector3(0.055, 0.075, 0.04)], [2.3, Vector3(0.075, 0.065, 0.04)]]
	if weight == "light":
		pouches = [[-1.45, Vector3(0.05, 0.065, 0.032)]]
	for p: Array in pouches:
		var a: float = p[0]
		pouch(root, m, p[1], b.at(mid - 0.04, a, 0.016), b.out(a))
	# Plates hung from the back of the belt over the seat (a culet): one on
	# light, two lames on medium, three on heavy, bridging the glutes.
	var lames: int = {"light": 1, "medium": 2, "heavy": 3}[weight]
	var half: float = {"light": 0.75, "medium": 0.95, "heavy": 1.15}[weight]
	var drop: float = {"light": 0.22, "medium": 0.17, "heavy": 0.15}[weight]
	for k in lames:
		var top := f0 + 0.02 - k * (drop - 0.04)
		var g := 0.012 + k * 0.004
		plate(root, "Rear" if k == 0 else "Rear%d" % k, b.wrap(top - drop, top, PI - half + k * 0.06, PI + half - k * 0.06, g, 0.0, 0.006),
				0.012 if weight == "light" else 0.015, m.plate if k % 2 == 0 else m.plate2, 14, 4)
		plate(root, "LameEdge", b.wrap(top - drop - 0.005, top - drop + 0.01, PI - half + k * 0.06 + 0.04, PI + half - k * 0.06 - 0.04, g + 0.012), 0.004,
				m.metal if weight == "heavy" else m.rubber, 14, 1)
	if weight == "heavy":
		# Faulds: plates hung from the belt over the front of the hips.
		for side: float in [-1.0, 1.0]:
			plate(root, "Fauld", b.wrap(-0.06, f0 + 0.01, minf(side * 0.18, side * 1.15), maxf(side * 0.18, side * 1.15), 0.02, 0.0, 0.006,
					-0.15), 0.016, m.plate, 10, 4)
	return G.merge(root)


## ---------------------------------------------------------------- limbs

## A shoulder pad for the side `out` (-1 left, 1 right): a cap over the
## shoulder ("Pad") and lames down the outside of the upper arm ("Pad1",
## ...), more and bigger the heavier the frame, each with an edge; medium
## and heavy add a plate down the upper arm ("Rerebrace").
static func pauldron(weight: String, style: Dictionary, out: float, build := "m") -> Node3D:
	var root := _root("PadModel")
	var m := Kit.new(style)
	var arm := Limb.new(build, "UpperArm", out)
	var lames: int = {"light": 1, "medium": 2, "heavy": 3}[weight]
	var gap: float = {"light": 0.006, "medium": 0.009, "heavy": 0.013}[weight]
	var thick: float = {"light": 0.009, "medium": 0.012, "heavy": 0.016}[weight]
	var spread: float = {"light": 1.3, "medium": 1.5, "heavy": 1.75}[weight]
	var lateral := PI * 0.5 * out
	# The cap: over the top of the shoulder, from in past the joint out
	# over the deltoid, swelling at its crown.
	var cap_end: float = {"light": 0.2, "medium": 0.24, "heavy": 0.28}[weight]
	plate(root, "Pad", arm.wrap(-0.28, cap_end, lateral, spread, gap, 0.004 + thick * 0.4), thick, m.plate, 14, 9)
	plate(root, "PadEdge", arm.wrap(cap_end - 0.025, cap_end, lateral, spread - 0.05, gap + thick + 0.002), 0.005,
			m.plate2 if weight == "light" else m.metal, 14, 1)
	for i in lames:
		var top := cap_end - 0.06 + i * 0.1
		var g := gap + 0.004 + i * 0.002
		plate(root, "Pad%d" % (i + 1), arm.wrap(top, top + 0.12, lateral, spread - 0.25 - i * 0.12, g, 0.006), thick,
				m.plate2 if i % 2 == 0 else m.plate, 12, 4)
		plate(root, "LameEdge", arm.wrap(top + 0.11, top + 0.12, lateral, spread - 0.3 - i * 0.12, g + thick), 0.004,
				m.metal if weight == "heavy" else m.rubber, 12, 1)
	if "admin" in m.details or "stripe" in m.details:
		# A unit patch on the cap.
		on(root, "Patch", Vector3(0.036, 0.026, 0.004), m.glow, arm.at(0.12, lateral, gap + thick + 0.012), arm.at(0.12, lateral) - arm.at(0.12, lateral + PI))
	if weight != "light":
		plate(root, "Rerebrace", arm.wrap(0.5, 0.82, lateral, 1.3, gap * 0.6), thick * 0.8, m.plate, 10, 4)
	return G.merge(root)


## A forearm piece: an elbow cop and a guard down the back of the forearm
## (a full vambrace on heavy); the left arm's carries a small lit display.
static func forearm(weight: String, style: Dictionary, out: float, build := "m") -> Node3D:
	var root := _root("BracerModel")
	var m := Kit.new(style)
	var arm := Limb.new(build, "LowerArm", out)
	var thick := 0.008 if weight == "light" else 0.012
	var lateral := PI * 0.5 * out
	# The elbow: round the point of it, at the back in the rest pose.
	plate(root, "Elbow", arm.wrap(-0.12, 0.12, PI, 1.2, 0.01, 0.014), thick, m.plate if weight == "heavy" else m.rubber, 10, 5)
	var half: float = {"light": 1.3, "medium": 1.6, "heavy": 2.5}[weight]
	plate(root, "Bracer", arm.wrap(0.3, 0.9, lateral, half, 0.01, 0.004, -0.01), thick, m.plate, 14, 6)
	if weight != "light":
		plate(root, "BracerEdge", arm.wrap(0.3, 0.33, lateral, half - 0.05, 0.01 + thick), 0.004, m.metal, 14, 1)
	if out < 0.0:
		var at := arm.at(0.62, lateral, 0.012 + thick)
		on(root, "Display", Vector3(0.04, 0.028, 0.004), m.dim, at, arm.at(0.62, lateral) - arm.at(0.62, lateral + PI), 0.001)
	return G.merge(root)


## A thigh piece for the side `out`: a plate down the front and outside
## ("Tasset", two lames on heavy), and on the right a drop-leg pouch on two
## straps.
static func thigh(weight: String, style: Dictionary, out: float, build := "m") -> Node3D:
	var root := _root("TassetModel")
	var m := Kit.new(style)
	var leg := Limb.new(build, "UpperLeg", out)
	var centre := 0.45 * out
	match weight:
		"heavy":
			# A full cuisse: three lames down the front and outside, and a
			# plate over the back of the thigh.
			for k in 3:
				var top := 0.03 + k * 0.27
				plate(root, "Tasset" if k == 0 else "Tasset%d" % k, leg.wrap(top, top + 0.31, centre, 1.6 - k * 0.12, 0.018 + (2 - k) * 0.004, 0.006),
						0.016, m.plate if k % 2 == 0 else m.plate2, 14, 5)
				plate(root, "LameEdge", leg.wrap(top + 0.29, top + 0.31, centre, 1.55 - k * 0.12, 0.034 + (2 - k) * 0.004), 0.004, m.metal, 14, 1)
			plate(root, "ThighBack", leg.wrap(0.2, 0.72, PI, 1.05, 0.014, 0.006), 0.014, m.plate2, 12, 5)
		"medium":
			# Two plates down the front and outside, the lower one over the
			# knee's top.
			plate(root, "Tasset", leg.wrap(0.06, 0.5, centre, 1.3, 0.016, 0.006), 0.013, m.plate, 14, 5)
			plate(root, "Tasset1", leg.wrap(0.46, 0.84, centre * 0.6, 1.05, 0.013, 0.005), 0.012, m.plate2, 12, 4)
		_:
			plate(root, "Tasset", leg.wrap(0.1, 0.6, centre, 0.95, 0.012, 0.005), 0.009, m.plate, 12, 5)
	if out > 0.0:
		for k in 2:
			var t := 0.2 + k * 0.22
			plate(root, "LegStrap", leg.wrap(t, t + 0.035, PI, PI - 0.001, 0.003), 0.006, m.strap, 20, 1)
		var at := leg.at(0.38, PI * 0.5, 0.01)
		pouch(root, m, Vector3(0.075, 0.13, 0.032), at, Vector3(1, 0, 0))
		if "spine" in m.details:
			on(root, "LegLight", Vector3(0.006, 0.05, 0.004), m.glow, at + Vector3(0.034, -0.01, -0.02), Vector3(1, 0, 0), 0.001)
	return G.merge(root)


## A shin piece: a knee cop over the knee and a guard down the shin, a full
## greave with a steel ridge on heavy.
static func shin(weight: String, style: Dictionary, out: float, build := "m") -> Node3D:
	var root := _root("ShinModel")
	var m := Kit.new(style)
	var leg := Limb.new(build, "LowerLeg", out)
	var knee_gap: float = {"light": 0.012, "medium": 0.016, "heavy": 0.02}[weight]
	plate(root, "Knee", leg.wrap(-0.1, 0.1, 0.0, 1.25, knee_gap, 0.02), 0.016, m.rubber if weight == "light" else m.plate, 12, 6)
	plate(root, "KneeCap", leg.wrap(-0.06, 0.06, 0.0, 0.6, knee_gap + 0.022, 0.01), 0.008, m.plate if weight == "light" else m.plate2, 8, 4)
	for k in 2:
		var t := -0.02 + k * 0.17
		plate(root, "KneeStrap", leg.wrap(t, t + 0.03, PI, PI - 0.001, 0.003), 0.006, m.strap, 20, 1)
	match weight:
		"heavy":
			# A full greave: the front shell, a calf plate behind and wings
			# off the sides of the knee.
			plate(root, "Greave", leg.wrap(0.14, 0.9, 0.0, 1.9, 0.014, 0.006), 0.016, m.plate, 16, 8)
			plate(root, "GreaveRidge", leg.wrap(0.16, 0.86, 0.0, 0.12, 0.032), 0.006, m.metal, 2, 8)
			plate(root, "Calf", leg.wrap(0.18, 0.8, PI, 1.25, 0.012, 0.008), 0.014, m.plate2, 12, 7)
			for side: float in [-1.0, 1.0]:
				plate(root, "KneeWing", leg.wrap(-0.08, 0.12, side * 1.35, 0.4, knee_gap + 0.006, 0.01), 0.012, m.plate2, 6, 4)
		"medium":
			plate(root, "Greave", leg.wrap(0.15, 0.86, 0.0, 1.4, 0.013, 0.005), 0.012, m.plate2, 14, 7)
			plate(root, "Calf", leg.wrap(0.24, 0.66, PI, 0.9, 0.01, 0.006), 0.01, m.plate, 10, 5)
		_:
			plate(root, "Greave", leg.wrap(0.18, 0.8, 0.0, 1.0, 0.011, 0.004), 0.008, m.plate, 12, 6)
	return G.merge(root)
