extends RefCounted
## The armor frame models, built in code and worn the same in every view
## (`ActorSkin._update_frame` hangs each piece on the bone it moves with).
## Grounded military sci-fi (Caleb's tactical pass, concept in the shared
## folder's ares/tactical-gear): a fabric plate carrier with hard plates
## over it, padded straps, a cummerbund with webbing rows, pouches with
## flaps and buckles, a battle belt, segmented shoulder pads, bracers, and
## knee and shin pads, over the fitted undersuit (`ActorSkin.suit_outfit`).
##
## A frame's weight sets the bulk (light a slim carrier and caps, medium
## the full kit, heavy layered plate, a gorget, abdominal lames and
## greaves); its look (`ActorSkin.FRAME_STYLES`) the colours and the
## details that say what it does. Every piece is merged into a mesh per
## material (`GearShapes.merge`), listing its parts in the "parts" meta.
## Pieces on the torso are built round the chest bone, the belt round the
## hips; a limb piece stands up its limb (Y from the far joint toward this
## one, front -Z, +X out on the right) from the joint it hangs on.

const G := preload("res://core/visual/gear_shapes.gd")


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


static func _root(piece: String) -> Node3D:
	var root := Node3D.new()
	root.name = piece
	return root


## A pouch: a body, a flap over its top with a buckle, a seam along its foot.
static func pouch(root: Node3D, m: Kit, size: Vector3, at: Vector3, basis := Basis.IDENTITY, body: Material = null) -> void:
	G.box(root, "Pouch", size, body if body else m.fabric, at, minf(0.007, size.x * 0.15), basis)
	var flap := Vector3(size.x * 1.05, size.y * 0.34, size.z * 1.08)
	var top := at + basis * Vector3(0, size.y * 0.5 - flap.y * 0.45, -size.z * 0.02)
	G.box(root, "Flap", flap, m.strap, top, minf(0.006, flap.y * 0.3), basis)
	G.box(root, "Buckle", Vector3(size.x * 0.32, flap.y * 0.5, 0.006), m.metal, top + basis * Vector3(0, -flap.y * 0.35, -flap.z * 0.5),
			0.0015, basis)
	G.box(root, "Seam", Vector3(size.x * 1.02, 0.005, size.z * 1.03), m.strap, at + basis * Vector3(0, -size.y * 0.42, 0), 0.0015, basis)


## The torso: the carrier, its plates and what hangs on it, round the chest
## bone. Named plates: "Chest" and "Back" always, "Side" for a cummerbund,
## "Collar" (the gorget) and "Belly" lames on heavy.
static func torso(weight: String, style: Dictionary) -> Node3D:
	var root := _root("FrameModel")
	var m := Kit.new(style)
	var heavy := weight == "heavy"
	var light := weight == "light"
	var mid := Vector3(0, -0.02, 0.0)
	# Scrap is strapped on crooked.
	var tilt := Basis(Vector3.BACK, 0.06) if "patches" in m.details else Basis.IDENTITY
	var rx := 0.15
	var rz := 0.125
	var low := -0.2
	var high := 0.12
	# The carrier: fabric front and back panels.
	var wrap := 0.95 if heavy else 0.82
	G.add(root, "Carrier", G.band(rx, rz, -wrap, wrap, low, high, 0.018, 0.012, 0.06), m.fabric, mid)
	G.add(root, "Carrier", G.band(rx, rz, PI - wrap, PI + wrap, low, high - 0.01, 0.018, 0.008, 0.06), m.fabric, mid)
	# The hard plates over them, thicker and further out the heavier it is.
	var pw := wrap * 0.82
	var front_z := -(rz + 0.018)
	if heavy:
		G.add(root, "Chest", G.band(rx + 0.018, rz + 0.02, -pw * 1.1, pw * 1.1, low + 0.04, high + 0.005, 0.024, 0.02, 0.1),
				m.plate, mid, tilt)
		# Layered abdominal lames below, each edged in steel.
		for k in 3:
			var top := low + 0.045 - k * 0.055
			G.add(root, "Belly" if k == 0 else "Belly%d" % k, G.band(rx + 0.012 + k * 0.004, rz + 0.016 + k * 0.004,
					-0.95 + k * 0.08, 0.95 - k * 0.08, top - 0.06, top, 0.016, 0.006), m.plate2 if k % 2 else m.plate, mid)
			G.add(root, "LameEdge", G.band(rx + 0.03 + k * 0.004, rz + 0.034 + k * 0.004, -0.9 + k * 0.08, 0.9 - k * 0.08,
					top - 0.008, top - 0.002, 0.004), m.metal, mid)
		G.add(root, "Back", G.band(rx + 0.018, rz + 0.02, PI - pw, PI + pw, low + 0.02, high, 0.024, 0.016, 0.08), m.plate, mid)
		# The gorget, edged in steel.
		G.add(root, "Collar", G.band(0.105, 0.098, -2.3, 2.3, high - 0.01, high + 0.06, 0.016, 0.0, -0.35), m.plate2,
				mid + Vector3(0, 0, -0.005))
		G.add(root, "CollarEdge", G.band(0.112, 0.105, -2.2, 2.2, high + 0.045, high + 0.055, 0.006, 0.0, -0.3), m.metal,
				mid + Vector3(0, 0, -0.005))
		G.add(root, "ChestEdge", G.band(rx + 0.04, rz + 0.042, -pw * 1.05, pw * 1.05, high - 0.012, high - 0.002, 0.006, 0.0, 0.1),
				m.metal, mid)
	else:
		var t := 0.014 if light else 0.018
		G.add(root, "Chest", G.band(rx + 0.016, rz + 0.018, -pw, pw, low + 0.06, high - 0.01, t, 0.016, 0.08), m.plate, mid, tilt)
		G.add(root, "Back", G.band(rx + 0.016, rz + 0.018, PI - pw, PI + pw, low + 0.04, high - 0.02, t, 0.012, 0.08), m.plate, mid)
	_plate_depth(root, m, mid, rx, rz, low, high, pw, heavy, light)
	# Padded shoulder straps over the top of each shoulder, buckled onto
	# the top of the plate in front and behind.
	var plate_z := rz + (0.044 if heavy else 0.036)
	for x: float in [-0.085, 0.085]:
		G.add(root, "Strap", G.band(0.07, 0.125, -0.15, PI + 0.15, -0.022, 0.022, 0.014), m.fabric,
				mid + Vector3(x, high - 0.015, 0.0), Basis(Vector3.BACK, PI * 0.5))
		for z: float in [-plate_z, plate_z]:
			G.box(root, "StrapBuckle", Vector3(0.048, 0.03, 0.01), m.strap, mid + Vector3(x, high - 0.032, z), 0.004,
					Basis(Vector3.RIGHT, 0.18 * signf(z)))
	# The cummerbund round the sides with webbing rows; elastic on light.
	for side: float in [-1.0, 1.0]:
		var from := wrap * 0.85 if side > 0 else -PI + wrap * 0.85
		var to := PI - wrap * 0.85 if side > 0 else -wrap * 0.85
		if light:
			for k in 2:
				G.add(root, "Elastic", G.band(rx - 0.004, rz - 0.004, from, to, low + 0.03 + k * 0.05, low + 0.055 + k * 0.05, 0.008),
						m.strap, mid)
			continue
		G.add(root, "Side", G.band(rx - 0.004, rz - 0.004, from, to, low, low + 0.13, 0.016, 0.004), m.fabric, mid)
		for k in 3:
			G.add(root, "Webbing", G.band(rx + 0.013, rz + 0.013, from + 0.05, to - 0.05, low + 0.025 + k * 0.035,
					low + 0.035 + k * 0.035, 0.004), m.strap, mid)
	# Magazine pouches across the front, each with its cell's lit gauge.
	var pz := front_z - 0.03 - (0.02 if heavy else 0.0)
	var mags := 2 if light else 3
	var py := low - 0.01 if heavy else low + 0.03
	for i in mags:
		var x := (i - (mags - 1) * 0.5) * 0.062
		pouch(root, m, Vector3(0.056, 0.085, 0.036), mid + Vector3(x, py, pz), Basis.IDENTITY, m.plate2 if heavy else m.fabric)
		G.box(root, "Gauge", Vector3(0.022, 0.005, 0.004), m.dim, mid + Vector3(x, py - 0.012, pz - 0.019), 0.001)
	if not heavy:
		# A thin status strip on the plate.
		G.box(root, "Status", Vector3(0.045, 0.006, 0.004), m.glow, mid + Vector3(-0.06, 0.06, front_z - 0.042), 0.001,
				Basis(Vector3.UP, 0.35))
	# A drag handle on every carrier.
	G.box(root, "Handle", Vector3(0.07, 0.018, 0.012), m.strap, mid + Vector3(0, high, rz + 0.045), 0.005)
	_torso_details(root, m, mid, rx, rz, low, high, front_z, pz, light)
	return G.merge(root)


## Depth on the hard plates, so they read as moulded armor, never slabs: a
## raised rim along the top and down each side, two pressed panel lines
## across them, and an ID placard on the chest plate.
static func _plate_depth(root: Node3D, m: Kit, mid: Vector3, rx: float, rz: float, low: float, high: float, pw: float,
		heavy: bool, light: bool) -> void:
	# Where the plate's face is: its offset off the carrier plus its thickness.
	var out := 0.044 if heavy else (0.032 if light else 0.036)
	var top := high + (0.005 if heavy else -0.01)
	var bottom := low + (0.04 if heavy else 0.06)
	for back: float in [0.0, PI]:
		var span := pw * (1.1 if heavy and back == 0.0 else 1.0)
		var top_here := top - (0.01 if back > 0.0 else 0.0)
		var bottom_here := bottom - (0.02 if back > 0.0 else 0.0)
		G.add(root, "PlateRim", G.band(rx + out - 0.006, rz + out - 0.006, back - span, back + span, top_here - 0.012, top_here, 0.008),
				m.plate2, mid)
		for side: float in [-1.0, 1.0]:
			var a := back + side * (span - 0.04)
			G.add(root, "PlateRim", G.band(rx + out - 0.006, rz + out - 0.006, minf(a, a - side * 0.06), maxf(a, a - side * 0.06),
					bottom_here, top_here - 0.012, 0.007), m.plate2, mid)
		for k in 2:
			var y := lerpf(bottom_here, top_here, 0.36 + k * 0.3)
			# Following the plate's swell, just proud of it.
			G.add(root, "PanelLine", G.band(rx + out - 0.002, rz + out - 0.002, back - span * 0.82, back + span * 0.82, y, y + 0.004, 0.004,
					0.014), m.plate2, mid)
	if not light:
		# An ID placard high on the chest, with a lit tag.
		G.box(root, "Placard", Vector3(0.09, 0.034, 0.008), m.plate2, mid + Vector3(0.0, top - 0.04, -rz - out - 0.012), 0.003)
		G.box(root, "PlacardTag", Vector3(0.024, 0.01, 0.004), m.dim, mid + Vector3(-0.026, top - 0.04, -rz - out - 0.017), 0.001)


## What says which frame it is, on top of its weight.
static func _torso_details(root: Node3D, m: Kit, mid: Vector3, rx: float, rz: float, low: float, high: float,
		front_z: float, pz: float, light: bool) -> void:
	var d := m.details
	if "patches" in d:
		# Patch plates bolted over the rust, a rivet at each corner.
		for p: Array in [[Vector3(0.05, 0.03, 0.0), Vector2(0.07, 0.05), 0.25], [Vector3(-0.06, -0.02, 0.0), Vector2(0.055, 0.05), -0.18]]:
			var at: Vector3 = mid + p[0] + Vector3(0, 0, front_z - 0.02)
			var size: Vector2 = p[1]
			var b := Basis(Vector3.BACK, p[2])
			G.box(root, "Patch", Vector3(size.x, size.y, 0.007), m.metal, at, 0.002, b)
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				G.box(root, "Rivet", Vector3.ONE * 0.01, m.plate2, at + b * Vector3(c.x * size.x * 0.38, c.y * size.y * 0.36, -0.004), 0.003)
	if "spine" in d or light:
		# A slim utility panel on the back; a runner's with cool vents down it.
		G.box(root, "BackPanel", Vector3(0.12, 0.12, 0.025), m.fabric, mid + Vector3(0, -0.02, rz + 0.04), 0.008)
		G.box(root, "PanelLight", Vector3(0.006, 0.08, 0.004), m.glow, mid + Vector3(0, -0.02, rz + 0.054), 0.001)
	if "radio" in d:
		# A radio on the left side, its antenna up the back.
		G.box(root, "Radio", Vector3(0.04, 0.1, 0.06), m.fabric, mid + Vector3(-rx - 0.03, low + 0.07, 0.01), 0.008)
		G.box(root, "RadioHead", Vector3(0.03, 0.03, 0.045), m.plate2, mid + Vector3(-rx - 0.03, low + 0.13, 0.01), 0.005)
		G.box(root, "RadioLight", Vector3(0.006, 0.006, 0.006), m.glow, mid + Vector3(-rx - 0.05, low + 0.13, -0.005), 0.001)
		G.cyl(root, "Antenna", 0.003, 0.3, m.rubber, mid + Vector3(-rx + 0.01, high + 0.06, rz + 0.04), Basis(Vector3.BACK, 0.12), 6)
	if "admin" in d:
		# An admin pouch over the mags, its tag lit.
		G.box(root, "Admin", Vector3(0.12, 0.06, 0.02), m.fabric, mid + Vector3(0, low + 0.12, pz + 0.012), 0.006)
		G.box(root, "AdminTag", Vector3(0.05, 0.022, 0.004), m.glow, mid + Vector3(0.025, low + 0.125, pz), 0.001)
	if "hydration" in d:
		# A hydration carrier on the back, webbing across it.
		G.box(root, "Hydration", Vector3(0.15, 0.2, 0.04), m.fabric, mid + Vector3(0, -0.04, rz + 0.05), 0.012)
		for k in 4:
			G.box(root, "Webbing", Vector3(0.152, 0.006, 0.042), m.strap, mid + Vector3(0, -0.11 + k * 0.04, rz + 0.05), 0.002)
	if "vents" in d:
		# Heat vents in the back plate, glowing: it runs hot.
		for x: float in [-0.05, 0.05]:
			G.box(root, "VentFrame", Vector3(0.055, 0.1, 0.012), m.plate2, mid + Vector3(x, -0.02, rz + 0.065), 0.003)
			for k in 4:
				G.box(root, "Vent", Vector3(0.04, 0.007, 0.006), m.glow, mid + Vector3(x, -0.055 + k * 0.024, rz + 0.072), 0.001)
	if "chevrons" in d:
		for x: float in [-1.0, 1.0]:
			G.box(root, "Chevron", Vector3(0.05, 0.008, 0.004), m.glow, mid + Vector3(x * 0.075, 0.04, front_z - 0.055), 0.001,
					Basis(Vector3.BACK, x * 0.35))
	if "quilt" in d:
		# A padded collar and quilted rings at the waist.
		G.add(root, "Quilt", G.band(0.098, 0.088, -PI, PI, high - 0.01, high + 0.035, 0.016, 0.012, -0.2), m.fabric,
				mid + Vector3(0, 0, -0.005))
		for k in 2:
			var top := low - 0.004 - k * 0.034
			G.add(root, "Quilt", G.band(rx - 0.01, rz - 0.01, -PI, PI, top - 0.032, top, 0.012, 0.01), m.fabric, mid)
	if "coils" in d:
		# Heat coils glowing across the chest plate.
		for k in 3:
			var y := low + 0.09 + k * 0.03
			G.add(root, "Coil", G.band(rx + 0.034, rz + 0.04, -0.6, 0.6, y, y + 0.006, 0.003), m.glow, mid)
	if "heater" in d:
		# A heater pack low on the back, its grille lit.
		G.box(root, "Heater", Vector3(0.15, 0.1, 0.05), m.plate, mid + Vector3(0, low + 0.02, rz + 0.06), 0.01)
		for k in 3:
			G.box(root, "Grille", Vector3(0.11, 0.008, 0.004), m.glow, mid + Vector3(0, low - 0.005 + k * 0.025, rz + 0.087), 0.001)


## A battle belt round the hips with pouches; heavy adds armored faulds.
static func belt(weight: String, style: Dictionary) -> Node3D:
	var root := _root("BeltModel")
	var m := Kit.new(style)
	var mid := Vector3(0, 0.07, 0.02)
	var rx := 0.15
	var rz := 0.12
	G.add(root, "Belt", G.band(rx, rz, -PI, PI, -0.02, 0.025, 0.014), m.strap, mid)
	G.box(root, "BeltBuckle", Vector3(0.05, 0.035, 0.01), m.metal, mid + Vector3(0, 0.002, -rz - 0.016), 0.003)
	var pouches := [[-1.3, Vector3(0.05, 0.07, 0.04)], [1.3, Vector3(0.05, 0.07, 0.04)], [2.2, Vector3(0.07, 0.06, 0.04)]]
	if weight == "light":
		pouches = [[-1.4, Vector3(0.045, 0.06, 0.03)]]
	for p: Array in pouches:
		var a: float = p[0]
		pouch(root, m, p[1], mid + Vector3(sin(a) * (rx + 0.03), -0.02, -cos(a) * (rz + 0.03)), Basis(Vector3.UP, -a))
	if weight == "heavy":
		for side: float in [-1.0, 1.0]:
			var from := 0.15 if side > 0 else -1.1
			var to := 1.1 if side > 0 else -0.15
			G.add(root, "Fauld", G.band(rx + 0.02, rz + 0.02, from, to, -0.08, 0.0, 0.016, 0.004, -0.1), m.plate, mid)
	return G.merge(root)


## A shoulder pad for the side `out` (-1 left, 1 right): a dome over the
## shoulder and lames down the outside of the arm ("Pad", "Pad1", ...), more
## and bigger the heavier the frame, each with an edge; medium and heavy
## add a plate down the upper arm.
static func pauldron(weight: String, style: Dictionary, out: float) -> Node3D:
	var root := _root("PadModel")
	var m := Kit.new(style)
	var lames: int = {"light": 1, "medium": 2, "heavy": 3}[weight]
	var r: float = {"light": 0.06, "medium": 0.068, "heavy": 0.078}[weight]
	var thick: float = {"light": 0.01, "medium": 0.013, "heavy": 0.018}[weight]
	var centre := PI * 0.5 * out
	var dome_r := Vector3(r * 1.1, r * 0.9, r * 1.15)
	G.add(root, "Pad", G.cap(dome_r, G.const_of(0.0), G.const_of(1.35), centre - 1.9, centre + 1.9, thick, 16, 5), m.plate,
			Vector3(out * 0.012, 0.0, 0.0))
	G.add(root, "PadEdge", G.cap(dome_r + Vector3.ONE * thick, G.const_of(1.25), G.const_of(1.35), centre - 1.9, centre + 1.9, 0.005, 16, 1),
			m.plate2 if weight == "light" else m.metal, Vector3(out * 0.012, 0.0, 0.0))
	for i in lames:
		var top := -0.012 - i * 0.042
		var rr := r * 1.02 + i * 0.004
		G.add(root, "Pad%d" % (i + 1), G.band(rr, rr * 1.04, centre - 1.35 + i * 0.1, centre + 1.35 - i * 0.1, top - 0.045, top, thick, 0.004),
				m.plate2 if i % 2 == 0 else m.plate, Vector3(out * 0.01, 0, 0))
		G.add(root, "LameEdge", G.band(rr + thick, rr * 1.04 + thick, centre - 1.3 + i * 0.1, centre + 1.3 - i * 0.1, top - 0.045, top - 0.039,
				0.004), m.metal if weight == "heavy" else m.rubber, Vector3(out * 0.01, 0, 0))
	if "admin" in m.details or "stripe" in m.details:
		# A unit patch on the lower lame.
		G.box(root, "Patch", Vector3(0.006, 0.026, 0.036), m.glow, Vector3(out * (r + 0.022), -0.06, 0), 0.002)
	if weight != "light":
		G.add(root, "Rerebrace", G.band(0.052, 0.056, centre - 1.2, centre + 1.2, -0.24, -0.11, thick * 0.8, 0.004), m.plate)
	return G.merge(root)


## A forearm piece: an elbow pad and a bracer down the outside of the arm;
## the left arm's carries a small lit display.
static func forearm(weight: String, style: Dictionary, out: float) -> Node3D:
	var root := _root("BracerModel")
	var m := Kit.new(style)
	var thick := 0.008 if weight == "light" else 0.012
	G.add(root, "Elbow", G.cap(Vector3(0.045, 0.045, 0.045), G.const_of(0.6), G.const_of(2.4), PI - 1.3, PI + 1.3, thick, 10, 5),
			m.plate if weight == "heavy" else m.rubber, Vector3(0, -0.01, 0.006))
	var centre := PI * 0.5 * out
	G.add(root, "Bracer", G.band(0.042, 0.04, centre - 1.6, centre + 1.6, -0.19, -0.05, thick, 0.004, -0.08), m.plate)
	if weight != "light":
		G.add(root, "BracerEdge", G.band(0.042 + thick, 0.04 + thick, centre - 1.5, centre + 1.5, -0.12, -0.11, 0.004), m.metal)
	if out < 0.0:
		G.box(root, "Display", Vector3(0.006, 0.028, 0.04), m.dim, Vector3(out * 0.052, -0.15, 0.0), 0.001)
	return G.merge(root)


## A thigh piece for the side `out`: a plate down the front ("Tasset", two
## lames on heavy), and on the right a drop-leg pouch on two straps.
static func thigh(weight: String, style: Dictionary, out: float) -> Node3D:
	var root := _root("TassetModel")
	var m := Kit.new(style)
	match weight:
		"heavy":
			for k in 2:
				var top := -0.03 - k * 0.11
				G.add(root, "Tasset" if k == 0 else "Tasset%d" % k, G.band(0.09 + k * 0.006, 0.085 + k * 0.006, -0.6 + out * 0.4,
						0.6 + out * 0.9, top - 0.13, top, 0.016, 0.006, -0.06), m.plate if k == 0 else m.plate2)
		"medium":
			G.add(root, "Tasset", G.band(0.088, 0.084, -0.7, 0.7, -0.24, -0.08, 0.012, 0.006), m.plate)
		_:
			G.add(root, "Tasset", G.band(0.086, 0.082, -0.5, 0.5, -0.22, -0.12, 0.008, 0.005), m.plate)
	if out > 0.0:
		for k in 2:
			G.add(root, "LegStrap", G.band(0.082, 0.08, -PI, PI, -0.1 - k * 0.09, -0.085 - k * 0.09, 0.006), m.strap)
		pouch(root, m, Vector3(0.07, 0.12, 0.03), Vector3(0.1, -0.15, 0.0), Basis(Vector3.UP, -PI * 0.5))
		if "spine" in m.details:
			G.box(root, "LegLight", Vector3(0.006, 0.04, 0.004), m.glow, Vector3(0.117, -0.16, -0.02), 0.001)
	return G.merge(root)


## A shin piece: a knee pad on straps and a guard down the shin, a full
## greave with a steel ridge on heavy.
static func shin(weight: String, style: Dictionary, _out: float) -> Node3D:
	var root := _root("ShinModel")
	var m := Kit.new(style)
	var r: float = {"light": 0.058, "medium": 0.064, "heavy": 0.07}[weight]
	G.add(root, "Knee", G.cap(Vector3(r, r * 1.2, r), G.const_of(0.5), G.const_of(2.3), -1.4, 1.4, 0.016, 12, 6),
			m.rubber if weight == "light" else m.plate, Vector3(0, 0.0, -0.01))
	G.add(root, "KneeCap", G.cap(Vector3(r, r * 1.2, r) * 0.6 + Vector3(0, 0, 0.02), G.const_of(0.9), G.const_of(1.9), -0.7, 0.7, 0.008, 6, 3),
			m.plate if weight == "light" else m.plate2, Vector3(0, 0.0, -0.045))
	for k in 2:
		G.add(root, "KneeStrap", G.band(0.055, 0.055, -PI, PI, 0.03 - k * 0.11, 0.045 - k * 0.11, 0.006), m.strap, Vector3(0, -0.02, 0))
	match weight:
		"heavy":
			G.add(root, "Greave", G.band(0.056, 0.058, -1.3, 1.3, -0.36, -0.07, 0.016, 0.008, -0.08), m.plate)
			G.add(root, "GreaveRidge", G.band(0.074, 0.076, -0.15, 0.15, -0.34, -0.09, 0.006), m.metal)
		"medium":
			G.add(root, "Greave", G.band(0.052, 0.054, -0.9, 0.9, -0.3, -0.12, 0.01, 0.006, -0.06), m.plate2)
		_:
			G.add(root, "Greave", G.band(0.05, 0.052, -0.6, 0.6, -0.26, -0.13, 0.007, 0.004, -0.05), m.plate)
	return G.merge(root)
