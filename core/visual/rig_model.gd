extends RefCounted
## Models for flight rigs, built in code like the rest of the greybox gear.
## Plain materials only, so a home base can build them headless; `Look`
## weathers them when the art layer is on.
##
## The item's stats pick the shape, as they pick how it flies (`FlightRig`):
##   jetpack - an armored back pack: a faceted core with a screen bay, and a
##             cowled thruster pod either side with a nozzle under each.
##   boots   - a cuff and a heel thruster on each foot.
##   wings   - a slim back pack with two wings that retract into it, and
##             slide out of slots in its sides to glide.
##
## Every model is built for a wearer facing -Z, the Actor's forward, so the
## back is +Z. Back models put their origin on the spine at chest height;
## boots put theirs at the ankle. Named children the skin uses:
##   "Nozzle*"     Marker3D, flame start, pointing down (-Y). Its meta
##                 "flame" is Vector2(radius, length) for the flame.
##   "WingL/R"     Node3D hinges; `set_wing_spread` slides them in and out.
##   "HeatDisplay" Marker3D on a jetpack: a clear flat face, looking back (+Z),
##                 kept free for an in-world heat readout. Its meta "size"
##                 (Vector2, meters) is the room there is.
##   "MountL/R"    Marker3D on a jetpack: the outer face of the weapon rail on
##                 each side, where a holstered long weapon is clamped. +Y
##                 runs up the rail (leaning out at the top, so the two
##                 weapons stand in a slight V) and +X points straight out
##                 of the clamp faces on the right side, into them on the left.

const Self := preload("res://core/visual/rig_model.gd")

const DARK := Color(0.13, 0.13, 0.14)
const STEEL := Color(0.42, 0.42, 0.44)
const STRAP := Color(0.09, 0.085, 0.08)
const EMBER := Color(1.0, 0.55, 0.2)

## How much of each wing's span stays out of the pack when it is retracted,
## as a share of the full span: the wing is hidden there anyway.
var wing_stowed_span := 0.1
## Wing panel sizes, in meters.
var wing_span := 1.05
var wing_root_chord := 0.34
var wing_tip_chord := 0.12
var wing_sweep := 0.22
## How far each weapon rail on a jetpack leans out at the top, and its length.
var mount_lean := deg_to_rad(6.0)
var rail_length := 0.3
## How far a clamp's prongs reach out past the rail to grip a weapon.
var clamp_reach := 0.05


## Which model an item gets: "jetpack", "boots", "wings", or "" if it is not a
## flight rig.
static func kind_for(id: String) -> String:
	if not ItemDB.has_tag(id, "flight_rig"):
		return ""
	var stats := ItemDB.item_stats(id)
	if float(stats.get("glide_fall_speed", 0.0)) > 0.0:
		return "wings"
	if float(stats.get("thrust_accel", 1.0)) <= 0.0:
		return "boots"
	return "jetpack"


## The part worn on the back, or null for rigs worn only on the feet.
static func build_back(id: String) -> Node3D:
	var maker := Self.new()
	match kind_for(id):
		"jetpack":
			return maker._jetpack(id)
		"wings":
			return maker._wing_pack(id)
	return null


## One boot thruster. `side` is -1 for the left foot, 1 for the right. Null
## for rigs that put nothing on the feet.
static func build_boot(id: String, side: float) -> Node3D:
	if kind_for(id) != "boots":
		return null
	return Self.new()._boot(id, side)


## Poses a wing pack: 0 retracted into the pack, 1 spread to glide. On the
## way out each wing slides out of its slot, then its tip lifts.
## `roll` (-1..1, positive banking right) twists the two wings opposite ways
## like ailerons, and `trim` (-1 flare .. 1 dive) pitches both together.
static func set_wing_spread(back: Node3D, amount: float, roll := 0.0, trim := 0.0) -> void:
	if back == null:
		return
	var t := clampf(amount, 0.0, 1.0)
	for wing_name: String in ["WingL", "WingR"]:
		var hinge := back.get_node_or_null(wing_name) as Node3D
		if hinge == null:
			continue
		var stowed: Quaternion = hinge.get_meta("stowed")
		var spread: Quaternion = hinge.get_meta("spread")
		var span: float = lerpf(hinge.get_meta("stowed_span"), 1.0, smoothstep(0.0, 0.6, t))
		var turn := smoothstep(0.4, 1.0, t)
		var side := -1.0 if wing_name == "WingL" else 1.0
		var twist := (side * roll * 0.35 - trim * 0.22) * turn
		# Swept further back in a dive, spread wide in a flare.
		var sweep := Basis(Vector3.UP, -side * maxf(trim, -0.4) * 0.3 * turn)
		hinge.basis = Basis(stowed.slerp(spread, turn)) * sweep * Basis(Vector3.RIGHT, twist) \
				* Basis.from_scale(Vector3(span, 1.0, 1.0))
		hinge.visible = t > 0.02
	back.set_meta("spread", t)


## Every flame start in a model.
static func nozzles(model: Node3D) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	if model == null:
		return out
	for node in model.find_children("Nozzle*", "Marker3D", true, false):
		out.append(node as Marker3D)
	return out


# --- Jetpack ---------------------------------------------------------------------

func _jetpack(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Jetpack"
	# Stronger packs are bigger, darker and carry stabilizer fins.
	var heavy: bool = ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE
	var armor := Color(0.27, 0.29, 0.33) if heavy else Color(0.33, 0.35, 0.31)
	var trim := Color(0.12, 0.12, 0.13)
	var glow := Color(0.35, 0.8, 1.0) if heavy else Color(0.4, 1.0, 0.75)
	var pod_r := 0.058 if heavy else 0.05
	var pod_h := 0.36 if heavy else 0.32
	var pod_x := 0.175 if heavy else 0.165
	var pod_z := 0.075

	_harness(root, 0.3, 0.44)
	# The armored core: a faceted shell with a raised plate on its back.
	var shell := _slab(PackedVector2Array([Vector2(-0.12, 0.21), Vector2(0.12, 0.21), Vector2(0.155, 0.15),
			Vector2(0.155, -0.17), Vector2(0.09, -0.25), Vector2(-0.09, -0.25), Vector2(-0.155, -0.17),
			Vector2(-0.155, 0.15)]), 0.09, _mat(trim))
	shell.position = Vector3(0, -0.03, 0.08)
	root.add_child(shell)
	var plate := _slab(PackedVector2Array([Vector2(-0.1, 0.19), Vector2(0.1, 0.19), Vector2(0.135, 0.13),
			Vector2(0.135, -0.15), Vector2(0.075, -0.22), Vector2(-0.075, -0.22), Vector2(-0.135, -0.15),
			Vector2(-0.135, 0.13)]), 0.02, _mat(armor))
	plate.position = Vector3(0, -0.03, 0.135)
	root.add_child(plate)
	# A recessed screen bay in the plate, kept clear for a heat readout.
	var bay_at := Vector3(0, -0.02, 0.146)
	root.add_child(_box(Vector3(0.15, 0.17, 0.006), bay_at, _mat(trim)))
	var display := Marker3D.new()
	display.name = "HeatDisplay"
	display.position = bay_at + Vector3(0, 0, 0.004)
	display.set_meta("size", Vector2(0.13, 0.15))
	root.add_child(display)
	# Vents across the top and a lit seam under the bay.
	for i in 4:
		root.add_child(_box(Vector3(0.012, 0.03, 0.03), Vector3(-0.045 + i * 0.03, 0.15, 0.142), _mat(trim)))
	root.add_child(_box(Vector3(0.11, 0.008, 0.008), Vector3(0, -0.13, 0.147), _mat(glow, 2.0)))
	# A short sensor mast on one shoulder.
	root.add_child(_box(Vector3(0.018, 0.12, 0.018), Vector3(-0.1, 0.24, 0.1), _mat(trim)))
	root.add_child(_box(Vector3(0.012, 0.012, 0.012), Vector3(-0.1, 0.305, 0.1), _mat(glow, 2.5)))

	for side: float in [-1.0, 1.0]:
		var x := side * pod_x
		# The thruster pod, faceted, with a lit strip down its outside.
		root.add_child(_cylinder(pod_r, pod_r, pod_h, Vector3(x, -0.04, pod_z), _mat(armor), Vector3.ZERO, 8))
		root.add_child(_cylinder(pod_r * 0.8, pod_r, 0.04, Vector3(x, -0.04 + pod_h * 0.5 + 0.02, pod_z), _mat(trim), Vector3.ZERO, 8))
		for y: float in [pod_h * 0.3, -pod_h * 0.3]:
			root.add_child(_cylinder(pod_r + 0.006, pod_r + 0.006, 0.018, Vector3(x, -0.04 + y, pod_z), _mat(trim), Vector3.ZERO, 8))
		root.add_child(_box(Vector3(0.008, pod_h * 0.35, 0.01), Vector3(x + side * (pod_r + 0.002), -0.04, pod_z), _mat(glow, 2.0)))
		# An armor cowl over the pod's outer face.
		var cowl := _slab(PackedVector2Array([Vector2(-0.05, 0.16), Vector2(0.03, 0.18), Vector2(0.06, 0.1),
				Vector2(0.06, -0.12), Vector2(0.0, -0.18), Vector2(-0.05, -0.14)]), 0.014, _mat(armor))
		cowl.basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
		cowl.position = Vector3(x + side * (pod_r + 0.012), -0.02, pod_z)
		root.add_child(cowl)
		_weapon_rail(root, side, Vector3(x + side * (pod_r + 0.019), -0.02, pod_z), glow)
		# The nozzle: a faceted bell with a glowing throat.
		var bottom := -0.04 - pod_h * 0.5
		root.add_child(_cylinder(pod_r * 0.7, pod_r * 0.8, 0.03, Vector3(x, bottom - 0.015, pod_z), _mat(trim), Vector3.ZERO, 8))
		root.add_child(_cylinder(pod_r * 0.62, pod_r * 0.95, 0.07, Vector3(x, bottom - 0.065, pod_z), _mat(STEEL), Vector3.ZERO, 8))
		root.add_child(_cylinder(pod_r * 0.7, pod_r * 0.7, 0.006, Vector3(x, bottom - 0.098, pod_z), _mat(glow, 1.5), Vector3.ZERO, 8))
		var nozzle := Marker3D.new()
		nozzle.name = "Nozzle" + ("L" if side < 0.0 else "R")
		nozzle.position = Vector3(x, bottom - 0.1, pod_z)
		nozzle.set_meta("flame", Vector2(pod_r * 0.85, 0.7 if heavy else 0.55))
		root.add_child(nozzle)
		if heavy:
			# A swept stabilizer off each cowl.
			# Swept back off the pod rather than out to the side, so it never
			# crosses a weapon clamped to the rail.
			var fin := _slab(PackedVector2Array([Vector2(0, 0.06), Vector2(0.1, -0.04), Vector2(0.11, -0.12), Vector2(0, -0.08)]),
					0.012, _mat(armor))
			fin.basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
			fin.position = Vector3(x, -0.1, pod_z + pod_r * 0.6)
			root.add_child(fin)
			root.add_child(_box(Vector3(0.006, 0.05, 0.006), Vector3(x, -0.18, pod_z + pod_r * 0.6 + 0.11), _mat(glow, 2.0)))
	return root


## A weapon rail on the outer face of a jetpack's pod cowl (`at`): a bar
## that stands on the cowl at its foot and leans out at the top on a longer
## post, with a clamp near each end. Holstered long weapons are worn against
## the clamps ("MountL/R"), so they sit on the pack, not beside it.
func _weapon_rail(root: Node3D, side: float, at: Vector3, glow: Color) -> void:
	var lean := Basis(Vector3.BACK, -side * mount_lean)
	var out := lean * Vector3(side, 0, 0)
	var up := lean * Vector3.UP
	var thick := 0.014
	var foot := at + Vector3(0, -rail_length * 0.5, 0)
	var centre := foot + up * rail_length * 0.5 + out * thick * 0.5
	var bar := _box(Vector3(thick, rail_length, 0.026), Vector3.ZERO, _mat(STEEL))
	bar.basis = lean
	bar.position = centre
	root.add_child(bar)
	# Posts back to the cowl: a short one at the foot, a longer one up top.
	for t: float in [0.12, 0.88]:
		var on_rail := foot + up * rail_length * t
		var gap := absf(on_rail.x - at.x) + 0.004
		root.add_child(_box(Vector3(gap, 0.022, 0.02), Vector3(at.x + side * gap * 0.5, on_rail.y, at.z), _mat(DARK)))
	# The clamps: a jaw block on the rail's face, with a prong reaching out
	# past the weapon's front and back to grip it, and a lit latch.
	var jaw := 0.012
	for t: float in [0.2, 0.8]:
		var at_t := foot + up * rail_length * t
		var block := _box(Vector3(jaw, 0.034, 0.09), Vector3.ZERO, _mat(DARK))
		block.basis = lean
		block.position = at_t + out * (thick + jaw * 0.5)
		root.add_child(block)
		for z: float in [-1.0, 1.0]:
			var prong := _box(Vector3(clamp_reach, 0.03, 0.01), Vector3.ZERO, _mat(DARK))
			prong.basis = lean
			prong.position = at_t + out * (thick + jaw + clamp_reach * 0.5) + Vector3(0, 0, z * 0.04)
			root.add_child(prong)
		var latch := _box(Vector3(0.012, 0.008, 0.004), Vector3.ZERO, _mat(glow, 2.0))
		latch.basis = lean
		latch.position = at_t + out * (thick + jaw + clamp_reach * 0.6) + Vector3(0, 0, 0.046)
		root.add_child(latch)
	var mount := Marker3D.new()
	mount.name = "Mount" + ("L" if side < 0.0 else "R")
	mount.basis = lean
	mount.position = foot + up * rail_length * 0.5 + out * (thick + jaw)
	root.add_child(mount)


## Back plate and shoulder straps, shared by every back-worn rig.
func _harness(root: Node3D, width: float, height: float) -> void:
	root.add_child(_box(Vector3(width, height, 0.035), Vector3(0, -0.06, 0.018), _mat(DARK)))
	for x: float in [-0.1, 0.1]:
		root.add_child(_box(Vector3(0.05, 0.03, 0.26), Vector3(x, 0.13, -0.1), _mat(STRAP)))
		root.add_child(_box(Vector3(0.05, 0.24, 0.025), Vector3(x, 0.02, -0.225), _mat(STRAP)))
		root.add_child(_box(Vector3(0.03, 0.03, 0.03), Vector3(x, -0.08, -0.235), _mat(STEEL)))
	# A waist strap clip.
	root.add_child(_box(Vector3(width * 0.9, 0.04, 0.03), Vector3(0, -0.29, 0.02), _mat(STRAP)))


# --- Wings ----------------------------------------------------------------------

func _wing_pack(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WingPack"
	var accent: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)]
	var paint := Color(0.34, 0.42, 0.48)
	_harness(root, 0.28, 0.4)
	# A slim shell with a ridge down the middle and a wing slot down each side.
	root.add_child(_box(Vector3(0.28, 0.44, 0.08), Vector3(0, -0.06, 0.075), _mat(paint)))
	root.add_child(_cylinder(0.04, 0.04, 0.28, Vector3(0, 0.16, 0.075), _mat(paint), Vector3(0, 0, PI / 2.0)))
	for x: float in [-0.141, 0.141]:
		root.add_child(_box(Vector3(0.006, 0.38, 0.03), Vector3(x, -0.06, 0.075), _mat(STRAP)))
	root.add_child(_box(Vector3(0.04, 0.38, 0.03), Vector3(0, -0.06, 0.125), _mat(DARK)))
	root.add_child(_box(Vector3(0.012, 0.3, 0.012), Vector3(0, -0.06, 0.142), _mat(accent, 1.2)))
	# One short launch nozzle at the bottom.
	root.add_child(_cylinder(0.035, 0.05, 0.07, Vector3(0, -0.305, 0.075), _mat(STEEL)))
	root.add_child(_cylinder(0.04, 0.04, 0.006, Vector3(0, -0.342, 0.075), _mat(EMBER, 0.8)))
	var nozzle := Marker3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0, -0.345, 0.075)
	nozzle.set_meta("flame", Vector2(0.045, 0.5))
	root.add_child(nozzle)

	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "WingL" if side < 0.0 else "WingR"
		hinge.position = Vector3(side * 0.03, -0.06, 0.075)
		# The wings lie in the plane of the back, leading edge toward the head,
		# so they are level when the wearer flies flat (see `ActorSkin`).
		# Stowed: inside the shell. Spread: slid out, tips swept a little up
		# off the back.
		var stowed := Quaternion(Vector3(1, 0, 0), PI / 2.0)
		var spread := Quaternion(Vector3(0, 1, 0), -side * 0.12) * stowed
		hinge.set_meta("spread", spread)
		hinge.set_meta("stowed", stowed)
		hinge.set_meta("stowed_span", wing_stowed_span)
		hinge.add_child(_wing(side, paint, accent))
		root.add_child(hinge)
	set_wing_spread(root, 0.0)
	return root


## One wing, lying flat (in XZ), reaching out along `side` * X from its hinge,
## leading edge forward (-Z) and swept back toward the tip.
func _wing(side: float, paint: Color, accent: Color) -> Node3D:
	var wing := Node3D.new()
	wing.name = "Panel"
	var span := wing_span
	var lead_tip := wing_sweep
	var outline := PackedVector2Array([
		Vector2(0.0, -wing_root_chord * 0.5),
		Vector2(span, -wing_root_chord * 0.5 + lead_tip),
		Vector2(span, -wing_root_chord * 0.5 + lead_tip + wing_tip_chord),
		Vector2(0.0, wing_root_chord * 0.5),
	])
	# `_slab` lies in XY; turn it flat so its Y becomes Z.
	var panel := _slab(outline, 0.018, _mat(paint))
	panel.basis = Basis(Vector3(side, 0, 0), Vector3(0, 0, 1), Vector3(0, -side, 0))
	wing.add_child(panel)
	# A spar down the leading edge, ribs across, and a light at the tip.
	var spar_len := Vector2(span, lead_tip).length()
	var spar := _box(Vector3(spar_len, 0.03, 0.03), Vector3(side * span * 0.5, 0.0, -wing_root_chord * 0.5 + lead_tip * 0.5), _mat(DARK))
	spar.rotation.y = -side * atan2(lead_tip, span)
	wing.add_child(spar)
	for f: float in [0.33, 0.66]:
		var x := span * f
		var front := -wing_root_chord * 0.5 + lead_tip * f
		var back := wing_root_chord * 0.5 + (lead_tip + wing_tip_chord - wing_root_chord) * f
		wing.add_child(_box(Vector3(0.016, 0.026, back - front), Vector3(side * x, 0.0, (front + back) * 0.5), _mat(DARK)))
	var tip := _box(Vector3(0.03, 0.03, wing_tip_chord * 0.8),
			Vector3(side * span, 0.0, -wing_root_chord * 0.5 + lead_tip + wing_tip_chord * 0.5), _mat(accent, 1.6))
	tip.name = "TipLight"
	wing.add_child(tip)
	# A painted stripe near the trailing edge.
	wing.add_child(_box(Vector3(span * 0.5, 0.022, 0.025), Vector3(side * span * 0.42, 0.0, wing_root_chord * 0.5 - 0.04 + (lead_tip + wing_tip_chord - wing_root_chord) * 0.42), _mat(accent, 0.6)))
	return wing


# --- Boots ----------------------------------------------------------------------

func _boot(id: String, side: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BootL" if side < 0.0 else "BootR"
	var accent: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)]
	var paint := Color(0.32, 0.33, 0.36)
	# A cuff around the ankle, with a lit strip and a strap.
	root.add_child(_box(Vector3(0.14, 0.11, 0.16), Vector3(0, 0.09, 0.005), _mat(paint)))
	root.add_child(_box(Vector3(0.145, 0.02, 0.165), Vector3(0, 0.05, 0.005), _mat(STRAP)))
	root.add_child(_box(Vector3(0.012, 0.06, 0.06), Vector3(side * 0.072, 0.1, -0.02), _mat(accent, 1.3)))
	# The heel thruster: a pod behind the heel, firing straight down.
	var pod_z := 0.1
	root.add_child(_cylinder(0.042, 0.042, 0.13, Vector3(0, 0.06, pod_z), _mat(DARK)))
	root.add_child(_cylinder(0.046, 0.046, 0.02, Vector3(0, 0.11, pod_z), _mat(STEEL)))
	root.add_child(_cylinder(0.028, 0.045, 0.05, Vector3(0, -0.03, pod_z), _mat(STEEL)))
	root.add_child(_cylinder(0.032, 0.032, 0.005, Vector3(0, -0.056, pod_z), _mat(EMBER, 0.8)))
	var nozzle := Marker3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0, -0.058, pod_z)
	nozzle.set_meta("flame", Vector2(0.035, 0.32))
	root.add_child(nozzle)
	# A small fin running back off the pod.
	var fin := _slab(PackedVector2Array([Vector2(0, 0.06), Vector2(0.05, -0.02), Vector2(0.05, -0.07), Vector2(0, -0.04)]),
			0.01, _mat(paint))
	fin.basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	fin.position = Vector3(0, 0.06, pod_z + 0.04)
	root.add_child(fin)
	return root


# --- Parts ----------------------------------------------------------------------

func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.4
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	return part


## A cylinder standing on Y, turned by `rot` (Euler).
func _cylinder(top: float, bottom: float, height: float, at: Vector3, mat: Material, rot := Vector3.ZERO, sides := 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = rot
	return part


## A flat plate cut to `outline` (in XY), `thickness` deep along Z and
## centered on it. For wings and fins.
func _slab(outline: PackedVector2Array, thickness: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := thickness * 0.5
	var tris := Geometry2D.triangulate_polygon(outline)
	# Every face is wound both ways, so the plate shows whichever way a
	# caller turns or mirrors it; the extra copies sit inside and are never seen.
	var ccw := not Geometry2D.is_polygon_clockwise(outline)
	for face: float in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, face))
		for i in range(0, tris.size(), 3):
			for k: int in [0, 1, 2, 0, 2, 1]:
				var p := outline[tris[i + k]]
				st.add_vertex(Vector3(p.x, p.y, half * face))
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var edge := (b - a).normalized()
		var out := Vector2(edge.y, -edge.x) if ccw else Vector2(-edge.y, edge.x)
		st.set_normal(Vector3(out.x, out.y, 0))
		var a0 := Vector3(a.x, a.y, -half)
		var a1 := Vector3(a.x, a.y, half)
		var b0 := Vector3(b.x, b.y, -half)
		var b1 := Vector3(b.x, b.y, half)
		for v: Vector3 in [a0, b1, b0, a0, a1, b1, a0, b0, b1, a0, b1, a1]:
			st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	return part
