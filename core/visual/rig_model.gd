extends RefCounted
## Models for flight rigs, built in code like the rest of the greybox gear.
## Plain materials only, so a home base can build them headless; `Look`
## weathers them when the art layer is on.
##
## The item's stats pick the shape, as they pick how it flies (`FlightRig`):
##   jetpack - an armored back pack: a rounded, bevelled core with a screen
##             bay, and a rounded thruster tank either side with a nozzle
##             under each, canted out so the flames clear the legs, and a
##             lit pip per tier.
##   boots   - a slim cuff and a heel thruster faired into it on each foot.
##   wings   - a slim rounded back pack with two wings that retract into it,
##             and slide out of slots in its sides to glide.
##
## Every model is built for a wearer facing -Z, the Actor's forward, so the
## back is +Z. Back models put their origin on the spine at chest height;
## boots put theirs at the ankle. Named children the skin uses:
##   "Nozzle*"     Marker3D, flame start, pointing down (-Y). Its meta
##                 "flame" is Vector2(radius, length) for the flame.
##   "WingL/R"     Node3D hinges; `set_wing_spread` slides them in and out.
##   "HeatDisplay" Marker3D on a jetpack or wing pack: a clear flat face, looking back (+Z),
##                 kept free for an in-world heat readout. Its meta "size"
##                 (Vector2, meters) is the room there is.
##   "MountL/R"    Marker3D on a jetpack or wing pack: the face of the flush
##                 weapon rail on each back corner, where a holstered long
##                 weapon is clamped. +Y runs up the rail (leaning out at
##                 the top, so the two weapons stand in a slight V) and +X
##                 points straight out of the rail's face on the right side,
##                 into it on the left; the face is turned `mount_turn` from
##                 straight out toward the back, behind the shoulder blade.

const Self := preload("res://core/visual/rig_model.gd")

const DARK := Color(0.13, 0.13, 0.14)
## The harness plate against the back: lighter than the pack's dark trim,
## so in a side view it reads as part of the pack, not as a gap.
const HARNESS := Color(0.3, 0.31, 0.32)
const STEEL := Color(0.42, 0.42, 0.44)
const STRAP := Color(0.09, 0.085, 0.08)
const EMBER := Color(1.0, 0.55, 0.2)
## Where a back rig's shoulder straps run, either side of the spine, how
## wide they are, and the top of the harness plate they come out of.
const STRAP_X := 0.1
const STRAP_WIDTH := 0.05
const HARNESS_TOP := 0.15
## A boot thruster's cuff round the ankle: its radius across outside and
## inside, how much
## deeper it is front to back, where its middle is behind the ankle, and
## how far up it reaches. A body wearing it widens it to clear its leg
## (`ActorSkin._fit_worn`).
const CUFF_RADIUS := 0.062
const CUFF_INNER := 0.05
const CUFF_DEPTH := 1.15
const CUFF_Z := 0.01
const CUFF_TOP := 0.15

## How much of each wing's span stays out of the pack when it is retracted,
## as a share of the full span: the wing is hidden there anyway.
var wing_stowed_span := 0.1
## Wing panel sizes, in meters.
var wing_span := 1.05
var wing_root_chord := 0.34
var wing_tip_chord := 0.12
var wing_sweep := 0.22
## How far each weapon rail leans out at the top, how far its face turns
## from straight out toward the back (all the way: a clamped weapon stands
## edge on behind the pack, slim from behind and clear of the arm), and its
## length.
var mount_lean := deg_to_rad(6.0)
var mount_turn := deg_to_rad(90.0)
var rail_length := 0.3
## How far a jetpack's nozzles cant out (and a little back) from straight
## down, so the flames clear the legs.
var nozzle_cant := 0.16
## How far behind the wing slots a wing pack's weapon rails stand: spread,
## the wings sweep back a little, and a clamped weapon must stay behind them.
var wing_rail_standoff := 0.11


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
## The rest is how the wings answer the air (the style pass, Caleb's call):
## `sweep` (0..1) folds them further back as the speed builds past the
## glide, `flex` (0..1) bends the tips up under load in a hard turn or
## pull, and `flutter` (radians) shakes them, as near a stall.
static func set_wing_spread(back: Node3D, amount: float, roll := 0.0, trim := 0.0,
		sweep := 0.0, flex := 0.0, flutter := 0.0) -> void:
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
		var twist := (side * roll * 0.35 - trim * 0.22 + flutter * side) * turn
		# Swept further back in a dive and at speed, spread wide in a flare.
		var back_sweep := Basis(Vector3.UP, -side * (maxf(trim, -0.4) * 0.3 + clampf(sweep, 0.0, 1.0) * 0.45) * turn)
		# Loaded up in a hard turn, the tips bend up off the back.
		var bend := Basis(Vector3.BACK, side * clampf(flex, 0.0, 1.0) * 0.28 * turn)
		hinge.basis = Basis(stowed.slerp(spread, turn)) * back_sweep * bend * Basis(Vector3.RIGHT, twist) \
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
	# Stronger packs are bigger, darker and carry stabilizer fins; every tier
	# also wears its number of lit pips on each pod.
	var heavy: bool = ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE
	var tier := int(ItemDB.item_stats(id).get("tier", 1))
	var armor := Color(0.27, 0.29, 0.33) if heavy else Color(0.33, 0.35, 0.31)
	var trim := Color(0.12, 0.12, 0.13)
	var glow := Color(0.35, 0.8, 1.0) if heavy else Color(0.4, 1.0, 0.75)
	var pod_r := 0.058 if heavy else 0.05
	var pod_h := 0.36 if heavy else 0.32
	var pod_x := 0.155 if heavy else 0.145
	var pod_z := 0.08

	_harness(root, 0.28, 0.42)
	# The armored core: a rounded shell, bevelled at its edges, with a raised
	# back plate over it.
	_pillow(root, Vector2(0.27, 0.43), 0.085, 0.06, Vector3(0, -0.03, 0.08), _mat(trim))
	_pillow(root, Vector2(0.23, 0.38), 0.02, 0.05, Vector3(0, -0.03, 0.13), _mat(armor))
	# A recessed screen bay in the plate, kept clear for a heat readout.
	var bay_at := Vector3(0, -0.02, 0.141)
	_pillow(root, Vector2(0.155, 0.175), 0.006, 0.02, bay_at, _mat(trim))
	var display := Marker3D.new()
	display.name = "HeatDisplay"
	display.position = bay_at + Vector3(0, 0, 0.004)
	display.set_meta("size", Vector2(0.13, 0.15))
	root.add_child(display)
	# Inset vent slits across the top and a lit seam under the bay.
	for i in 4:
		root.add_child(_box(Vector3(0.022, 0.006, 0.012), Vector3(-0.036 + i * 0.024, 0.115, 0.141), _mat(DARK)))
	root.add_child(_box(Vector3(0.11, 0.006, 0.006), Vector3(0, -0.125, 0.141), _mat(glow, 2.0)))

	for side: float in [-1.0, 1.0]:
		var x := side * pod_x
		# The thruster pod: a rounded tank, tucked in against the shell, with
		# a lit strip down its back where the wearer's own arm never covers it.
		root.add_child(_capsule(pod_r, pod_h + pod_r, Vector3(x, -0.03, pod_z), _mat(armor)))
		for y: float in [pod_h * 0.28, -pod_h * 0.28]:
			root.add_child(_cylinder(pod_r + 0.004, pod_r + 0.004, 0.014, Vector3(x, -0.03 + y, pod_z), _mat(trim), Vector3.ZERO, 16))
		root.add_child(_box(Vector3(0.006, pod_h * 0.32, 0.006), Vector3(x + side * pod_r * 0.5, -0.03, pod_z + pod_r * 0.86), _mat(glow, 2.0)))
		# Tier pips up the pod's back.
		for i in tier:
			root.add_child(_box(Vector3(0.012, 0.008, 0.004), Vector3(x - side * pod_r * 0.3, 0.06 + i * 0.016, pod_z + pod_r * 0.98), _mat(glow, 2.5)))
		_weapon_rail(root, side, Vector3(x, -0.03, pod_z), pod_r, glow)
		# The nozzle: a bell with a glowing throat, canted a little out and
		# back so the flame clears the legs.
		var nozzle_root := Node3D.new()
		var bottom := -0.03 - pod_h * 0.5 - pod_r * 0.3
		nozzle_root.position = Vector3(x, bottom, pod_z)
		nozzle_root.basis = Basis(Vector3.FORWARD, side * nozzle_cant) * Basis(Vector3.RIGHT, -nozzle_cant * 0.7)
		root.add_child(nozzle_root)
		nozzle_root.add_child(_cylinder(pod_r * 0.62, pod_r * 0.75, 0.026, Vector3(0, -0.013, 0), _mat(trim), Vector3.ZERO, 16))
		nozzle_root.add_child(_cylinder(pod_r * 0.6, pod_r * 0.9, 0.06, Vector3(0, -0.055, 0), _mat(STEEL), Vector3.ZERO, 16))
		nozzle_root.add_child(_cylinder(pod_r * 0.68, pod_r * 0.68, 0.004, Vector3(0, -0.084, 0), _mat(glow, 1.5), Vector3.ZERO, 16))
		var nozzle := Marker3D.new()
		nozzle.name = "Nozzle" + ("L" if side < 0.0 else "R")
		nozzle.position = Vector3(0, -0.086, 0)
		nozzle.set_meta("flame", Vector2(pod_r * 0.8, 0.7 if heavy else 0.55))
		nozzle_root.add_child(nozzle)
		if heavy:
			# A swept stabilizer back off the pod's outer side, clear of a
			# weapon on the rail behind it.
			var fin := _slab(_rounded(PackedVector2Array([Vector2(0, 0.06), Vector2(0.09, -0.03), Vector2(0.1, -0.11), Vector2(0, -0.08)]), 0.012),
					0.01, _mat(armor))
			fin.basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
			fin.position = Vector3(x + side * pod_r * 0.85, -0.11, pod_z + pod_r * 0.2)
			root.add_child(fin)
			root.add_child(_box(Vector3(0.005, 0.045, 0.005), Vector3(x + side * pod_r * 0.85, -0.18, pod_z + pod_r * 0.2 + 0.1), _mat(glow, 2.0)))
	return root


## A weapon rail on the back of a back rig's side, on the curve of whatever
## stands there (a pod or the shell, `radius` from `at`; `standoff` further
## back on a fairing, where something slides out of that side): a flush
## mag-lock strip with two lit lock pads, its face turned `mount_turn` from
## straight out toward the back, so a clamped weapon stands edge on behind
## the pack, clear of the arm and the screen, and leaning out at the top.
## Nothing sticks out of it while it is empty. Holstered long weapons are
## worn against it ("MountL/R").
func _weapon_rail(root: Node3D, side: float, at: Vector3, radius: float, glow: Color, standoff := 0.0) -> void:
	if standoff > 0.0:
		# A fairing back from the pack's side to where the rail stands, so
		# the rail reads as part of the pack, not on a stalk.
		# It starts behind the side's slot, so nothing sliding out meets it.
		var fairing := _pillow_mesh(Vector2(standoff + radius - 0.03, rail_length * 0.85), 0.018, 0.02, _mat(DARK))
		fairing.basis = Basis(Vector3.UP, PI / 2.0)
		fairing.position = Vector3(at.x, at.y, at.z + (standoff + radius + 0.03) * 0.5)
		root.add_child(fairing)
		at.z += standoff
	var basis := Basis(Vector3.BACK, -side * mount_lean) * Basis(Vector3.UP, -side * mount_turn)
	var out := basis.x * side
	var up := basis.y
	var face := at + Vector3(out.x, 0.0, out.z).normalized() * radius
	var thick := 0.008
	var strip := _pillow_mesh(Vector2(0.028, rail_length), thick, 0.012, _mat(DARK))
	strip.basis = basis * Basis(Vector3.UP, side * PI / 2.0)
	strip.position = face + out * thick * 0.5
	root.add_child(strip)
	# The lock pads: a lit dot near each end of the strip.
	for t: float in [-0.38, 0.38]:
		var pad := _cylinder(0.007, 0.007, 0.003, Vector3.ZERO, _mat(glow, 2.0), Vector3.ZERO, 12)
		pad.basis = basis * Basis(Vector3.BACK, -side * PI / 2.0)
		pad.position = face + up * rail_length * t + out * (thick + 0.0015)
		root.add_child(pad)
	var mount := Marker3D.new()
	mount.name = "Mount" + ("L" if side < 0.0 else "R")
	mount.basis = basis
	mount.position = face + out * thick
	root.add_child(mount)


## Back plate and shoulder straps, shared by every back-worn rig.
func _harness(root: Node3D, width: float, height: float) -> void:
	_pillow(root, Vector2(width, height), 0.03, 0.05, Vector3(0, -0.06, 0.018), _mat(HARNESS))
	# Straps for a wearer of no particular shape, in "Straps": a body
	# wearing it lays its own over its shoulders and armor
	# (`ActorSkin._fit_straps`) and hides these.
	var straps := Node3D.new()
	straps.name = "Straps"
	root.add_child(straps)
	for x: float in [-STRAP_X, STRAP_X]:
		straps.add_child(_box(Vector3(STRAP_WIDTH, 0.026, 0.26), Vector3(x, 0.13, -0.1), _mat(STRAP)))
		straps.add_child(_box(Vector3(STRAP_WIDTH, 0.24, 0.02), Vector3(x, 0.02, -0.225), _mat(STRAP)))
		straps.add_child(_capsule(0.014, 0.05, Vector3(x, -0.08, -0.237), _mat(STEEL), Vector3(0, 0, PI / 2.0)))
	# A waist strap clip.
	root.add_child(_box(Vector3(width * 0.9, 0.036, 0.026), Vector3(0, -0.29, 0.02), _mat(STRAP)))


# --- Wings ----------------------------------------------------------------------

func _wing_pack(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WingPack"
	var accent: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)]
	var paint := Color(0.34, 0.42, 0.48)
	_harness(root, 0.26, 0.4)
	# A slim rounded shell with a spine ridge, a wing slot down each side
	# and a rounded cap over the top.
	_pillow(root, Vector2(0.27, 0.44), 0.075, 0.07, Vector3(0, -0.06, 0.075), _mat(paint))
	_pillow(root, Vector2(0.21, 0.36), 0.012, 0.05, Vector3(0, -0.07, 0.116), _mat(paint.darkened(0.15)))
	root.add_child(_capsule(0.036, 0.26, Vector3(0, 0.15, 0.075), _mat(paint), Vector3(0, 0, PI / 2.0)))
	for x: float in [-0.136, 0.136]:
		root.add_child(_box(Vector3(0.004, 0.36, 0.026), Vector3(x, -0.06, 0.075), _mat(STRAP)))
	# A screen bay up top, kept clear for the heat readout as on a jetpack,
	# and the ridge below it.
	var bay_at := Vector3(0, 0.03, 0.124)
	_pillow(root, Vector2(0.15, 0.16), 0.006, 0.02, bay_at, _mat(DARK))
	var display := Marker3D.new()
	display.name = "HeatDisplay"
	display.position = bay_at + Vector3(0, 0, 0.004)
	display.set_meta("size", Vector2(0.13, 0.14))
	root.add_child(display)
	root.add_child(_capsule(0.016, 0.2, Vector3(0, -0.17, 0.124), _mat(DARK)))
	root.add_child(_box(Vector3(0.008, 0.15, 0.008), Vector3(0, -0.17, 0.14), _mat(accent, 1.2)))
	# One short launch nozzle at the bottom.
	root.add_child(_cylinder(0.035, 0.048, 0.06, Vector3(0, -0.3, 0.075), _mat(STEEL)))
	root.add_child(_cylinder(0.038, 0.038, 0.004, Vector3(0, -0.331, 0.075), _mat(EMBER, 0.8)))
	var nozzle := Marker3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0, -0.334, 0.075)
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
		# The weapon rail stands off the back corner, behind the wing slot,
		# so a clamped weapon never meets a wing sliding out.
		_weapon_rail(root, side, Vector3(side * 0.135, -0.08, 0.075), 0.03, accent, wing_rail_standoff)
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
	var tier := int(ItemDB.item_stats(id).get("tier", 1))
	var paint := Color(0.32, 0.33, 0.36)
	# A slim cuff close round the ankle, open so the leg goes through it,
	# with a strap round it, and a lit strip and the tier pips up its
	# outside ("Side").
	var cuff := _cuff(CUFF_RADIUS, CUFF_INNER, 0.02, CUFF_TOP - 0.005, _mat(paint))
	cuff.name = "Cuff"
	root.add_child(cuff)
	var strap := _cuff(CUFF_RADIUS + 0.004, CUFF_RADIUS - 0.004, 0.047, 0.063, _mat(STRAP))
	strap.name = "CuffStrap"
	root.add_child(strap)
	var outside := Node3D.new()
	outside.name = "Side"
	root.add_child(outside)
	outside.add_child(_box(Vector3(0.006, 0.05, 0.03), Vector3(side * 0.063, 0.1, -0.015), _mat(accent, 1.3)))
	for i in tier:
		outside.add_child(_box(Vector3(0.004, 0.006, 0.012), Vector3(side * 0.064, 0.13 + i * 0.012, 0.03), _mat(accent, 2.0)))
	# The heel thruster ("Heel"): a rounded pod faired into the back of the
	# cuff, firing straight down, with a small swept fin running back off it.
	var heel := Node3D.new()
	heel.name = "Heel"
	root.add_child(heel)
	var pod_z := 0.085
	heel.add_child(_capsule(0.036, 0.15, Vector3(0, 0.06, pod_z), _mat(DARK)))
	heel.add_child(_cylinder(0.039, 0.039, 0.012, Vector3(0, 0.1, pod_z), _mat(STEEL), Vector3.ZERO, 16))
	heel.add_child(_cylinder(0.026, 0.04, 0.04, Vector3(0, -0.025, pod_z), _mat(STEEL), Vector3.ZERO, 16))
	heel.add_child(_cylinder(0.029, 0.029, 0.004, Vector3(0, -0.046, pod_z), _mat(EMBER, 0.8), Vector3.ZERO, 16))
	var nozzle := Marker3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0, -0.048, pod_z)
	nozzle.set_meta("flame", Vector2(0.032, 0.32))
	heel.add_child(nozzle)
	var fin := _slab(_rounded(PackedVector2Array([Vector2(0, 0.06), Vector2(0.045, -0.01), Vector2(0.045, -0.06), Vector2(0, -0.035)]), 0.008),
			0.008, _mat(paint))
	fin.basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	fin.position = Vector3(0, 0.06, pod_z + 0.032)
	heel.add_child(fin)
	return root


## Opens a boot thruster's cuff `grow` wider (metres across, front to back)
## round a leg or shin armor bigger than it was made for: the cuff and its
## strap rebuilt that much wider, the lit side moved out and the heel
## thruster moved back with them.
static func fit_boot(boot: Node3D, side: float, grow: Vector2) -> void:
	var cuff := boot.get_node_or_null("Cuff") as MeshInstance3D
	var strap := boot.get_node_or_null("CuffStrap") as MeshInstance3D
	if cuff == null or strap == null:
		return
	cuff.mesh = _cuff(CUFF_RADIUS, CUFF_INNER, 0.02, CUFF_TOP - 0.005, cuff.material_override, grow).mesh
	strap.mesh = _cuff(CUFF_RADIUS + 0.004, CUFF_RADIUS - 0.004, 0.047, 0.063, strap.material_override, grow).mesh
	(boot.get_node("Side") as Node3D).position = Vector3(side * grow.x, 0.0, 0.0)
	(boot.get_node("Heel") as Node3D).position = Vector3(0.0, 0.0, grow.y)


# --- Parts ----------------------------------------------------------------------

## An open band round the ankle, `outer` to `inner` radius across (deeper
## front to back by `CUFF_DEPTH`, its middle `CUFF_Z` back) from `low` to
## `high` up, its edges rounded over, opened `grow` wider (across, front to
## back).
static func _cuff(outer: float, inner: float, low: float, high: float, mat: Material, grow := Vector2.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	var lip := minf((outer - inner) * 0.5, (high - low) * 0.3)
	# The band's outline as it goes round: inner wall up, over the top, down
	# the outer wall and back under.
	var section := [Vector2(inner, low + lip), Vector2(inner, high - lip), Vector2(inner + lip, high), Vector2(outer - lip, high),
			Vector2(outer, high - lip), Vector2(outer, low + lip), Vector2(outer - lip, low), Vector2(inner + lip, low)]
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for k in section.size():
			var p: Vector2 = section[k]
			var q: Vector2 = section[(k + 1) % section.size()]
			var v := [_cuff_at(p, a0, grow), _cuff_at(q, a0, grow), _cuff_at(q, a1, grow), _cuff_at(p, a1, grow)]
			st.add_vertex(v[0])
			st.add_vertex(v[2])
			st.add_vertex(v[1])
			st.add_vertex(v[0])
			st.add_vertex(v[3])
			st.add_vertex(v[2])
	st.generate_normals()
	var part := MeshInstance3D.new()
	part.mesh = st.commit()
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	part.material_override = mat
	return part


static func _cuff_at(p: Vector2, a: float, grow: Vector2) -> Vector3:
	return Vector3(sin(a) * (p.x + grow.x), p.y, CUFF_Z - cos(a) * (p.x * CUFF_DEPTH + grow.y))


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


## A rounded slab: `size` (x wide, y tall) with corners of `radius`, `depth`
## deep along Z, and a bevel round its face (a second, thinner-edged slab
## inset over it), centred on `at`.
func _pillow(root: Node3D, size: Vector2, depth: float, radius: float, at: Vector3, mat: Material) -> void:
	var part := _pillow_mesh(size, depth, radius, mat)
	part.position = at
	root.add_child(part)


func _pillow_mesh(size: Vector2, depth: float, radius: float, mat: Material) -> Node3D:
	var holder := Node3D.new()
	var bevel := minf(0.008, minf(size.x, size.y) * 0.12)
	var back := _slab(_round_rect(size, radius), maxf(depth - bevel * 2.0, depth * 0.4), mat)
	holder.add_child(back)
	var inset := Vector2(maxf(size.x - bevel * 2.0, size.x * 0.6), maxf(size.y - bevel * 2.0, size.y * 0.6))
	holder.add_child(_slab(_round_rect(inset, maxf(radius - bevel, 0.002)), depth, mat))
	return holder


## The outline of a `size` rectangle round its middle with corners of `radius`.
static func _round_rect(size: Vector2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(size.x, size.y) * 0.5)
	var hx := size.x * 0.5 - r
	var hy := size.y * 0.5 - r
	var out := PackedVector2Array()
	var steps := 4
	for corner in 4:
		var c := Vector2(hx if corner == 0 or corner == 3 else -hx, hy if corner < 2 else -hy)
		for i in steps + 1:
			var a := (corner + float(i) / steps) * PI * 0.5
			out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## `outline` with each corner cut into a short round of `radius`.
static func _rounded(outline: PackedVector2Array, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := outline.size()
	for i in n:
		var p := outline[i]
		var prev := (outline[(i + n - 1) % n] - p)
		var next := (outline[(i + 1) % n] - p)
		var cut := minf(radius, minf(prev.length(), next.length()) * 0.4)
		out.append(p + prev.normalized() * cut)
		out.append(p + (prev.normalized() + next.normalized()) * cut * 0.3)
		out.append(p + next.normalized() * cut)
	return out


## A capsule standing on Y (`height` end to end), turned by `rot` (Euler).
func _capsule(radius: float, height: float, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 16
	mesh.rings = 4
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = rot
	return part
