extends RefCounted
## Models for flight rigs, built in code like the rest of the greybox gear.
## Plain materials only, so a home base can build them headless; `Look`
## weathers them when the art layer is on.
##
## The item's stats pick the shape, as they pick how it flies (`FlightRig`):
##   jetpack - a back pack with twin tanks and a nozzle under each.
##   boots   - a cuff and a heel thruster on each foot.
##   wings   - a slim back pack with two wings that retract into it, and
##             slide out of slots in its sides and swing flat to glide.
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
## way out each wing slides out of its slot on edge, then swings flat.
static func set_wing_spread(back: Node3D, amount: float) -> void:
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
		hinge.basis = Basis(stowed.slerp(spread, turn)) * Basis.from_scale(Vector3(span, 1.0, 1.0))
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
	# Stronger packs are bigger, painted and finned.
	var heavy: bool = ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE
	var paint := Color(0.5, 0.2, 0.12) if heavy else Color(0.36, 0.38, 0.3)
	var accent: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)] if heavy else EMBER
	var r := 0.085 if heavy else 0.072
	var tank_h := 0.44 if heavy else 0.4
	var tank_x := 0.115
	var tank_z := 0.035 + r + 0.01

	_harness(root, 0.3, 0.44)
	# The core between the tanks. Its back face is left bare for a heat readout.
	var core_z := 0.07
	var core_d := 0.1
	root.add_child(_box(Vector3(0.1, 0.36, core_d), Vector3(0, -0.04, core_z), _mat(DARK)))
	var display := Marker3D.new()
	display.name = "HeatDisplay"
	display.position = Vector3(0, 0.0, core_z + core_d * 0.5 + 0.002)
	display.set_meta("size", Vector2(0.09, 0.2))
	root.add_child(display)
	# Intake slats above the readout spot.
	for i in 3:
		root.add_child(_box(Vector3(0.11, 0.012, 0.02), Vector3(0, 0.15 - i * 0.022, core_z + core_d * 0.5), _mat(STEEL)))

	for x: float in [-tank_x, tank_x]:
		var tank := _cylinder(r, r, tank_h, Vector3(x, -0.03, tank_z), _mat(paint))
		root.add_child(tank)
		var cap := SphereMesh.new()
		cap.radius = r
		cap.height = r * 1.2
		cap.material = _mat(paint)
		var dome := MeshInstance3D.new()
		dome.mesh = cap
		dome.position = Vector3(x, -0.03 + tank_h * 0.5, tank_z)
		root.add_child(dome)
		# Bands, a valve on top and a lit stripe.
		for y: float in [tank_h * 0.32, -tank_h * 0.28]:
			root.add_child(_cylinder(r + 0.008, r + 0.008, 0.022, Vector3(x, -0.03 + y, tank_z), _mat(DARK)))
		root.add_child(_cylinder(0.014, 0.014, 0.06, Vector3(x, -0.03 + tank_h * 0.5 + r * 0.5, tank_z), _mat(STEEL)))
		root.add_child(_box(Vector3(0.01, tank_h * 0.4, 0.012), Vector3(x + signf(x) * (r - 0.002), 0.02, tank_z), _mat(accent, 1.2)))
		# The nozzle: a bell with a glowing throat.
		var bottom := -0.03 - tank_h * 0.5
		root.add_child(_cylinder(r * 0.55, r * 0.65, 0.05, Vector3(x, bottom - 0.02, tank_z), _mat(DARK)))
		root.add_child(_cylinder(r * 0.5, r * 0.85, 0.09, Vector3(x, bottom - 0.085, tank_z), _mat(STEEL)))
		root.add_child(_cylinder(r * 0.6, r * 0.6, 0.006, Vector3(x, bottom - 0.128, tank_z), _mat(EMBER, 0.8)))
		var nozzle := Marker3D.new()
		nozzle.name = "Nozzle" + ("L" if x < 0.0 else "R")
		nozzle.position = Vector3(x, bottom - 0.13, tank_z)
		nozzle.set_meta("flame", Vector2(r * 0.85, 0.7 if heavy else 0.55))
		root.add_child(nozzle)
		if heavy:
			# A swept fin on the outside of each tank.
			var side := signf(x)
			var fin := _slab(PackedVector2Array([Vector2(0, 0.12), Vector2(0.09, -0.06), Vector2(0.09, -0.2), Vector2(0, -0.14)]),
					0.014, _mat(paint))
			fin.position = Vector3(x + side * r, -0.06, tank_z)
			fin.basis = Basis(Vector3(side, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, side))
			root.add_child(fin)
	return root


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
		# Spread: flat, out to the side, a little dihedral. Stowed: on edge,
		# leading edge up, inside the shell.
		var spread := Quaternion(Vector3(0, 0, 1), side * 0.1)
		var stowed := Quaternion(Vector3(1, 0, 0), PI / 2.0)
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
func _cylinder(top: float, bottom: float, height: float, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
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
	# Make the outline counter-clockwise so the faces point the right way.
	var ccw := not Geometry2D.is_polygon_clockwise(outline)
	for face: float in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, face))
		for i in range(0, tris.size(), 3):
			var order := [0, 1, 2] if (face > 0.0) == ccw else [0, 2, 1]
			for k: int in order:
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
		if ccw:
			for v: Vector3 in [a0, b0, b1, a0, b1, a1]:
				st.add_vertex(v)
		else:
			for v: Vector3 in [a0, b1, b0, a0, a1, b1]:
				st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	return part
