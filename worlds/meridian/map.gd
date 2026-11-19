extends Node3D
## Greybox Meridian: Coilrun, a street circuit through a dead launch works on
## salt flats under a sun that never sets. It stands on the Salt Flat
## planet type (DESIGN.md "Planet kit"): its sky, light, salt pan, horizon
## and rocks, which the world hands over as `planet`.
##
## The track is data (`CONTROL`, `CHECKPOINTS`, `LINE`): `race_track()` hands
## the `RaceTrack` built from it to the `Race`, and the road, its edges and
## kerbs are laid along the same centre line, so what you see is what is
## judged. Sections, clockwise from the line: the Rail (the straight through
## the mass driver's coil rings), Breech Hairpin, the Crest, Capacitor Yard
## (rubble on the inside line a hover cushion rides over), the Spillway (a
## gap with a ramp for wheels and a level lip for a hover float), Tower
## Sweep, and the Pylon Chicane back onto the Rail.
##
## North of the pits is the second track, Skyhook (`skyhook.gd`), with its
## own bays, gantry, arches and board; racers pick a track by walking to its
## pit row from race control. Round both, decoration only: the stands, the
## crowd and the rest of the spectacle (`stands.gd`).
##
## Map contract, beyond WorldDef's (see `Race`): `race_track()` and
## `race_tracks()`; pit bays are
## "spawn_vehicle" markers whose "loot_source" names the machine; for the
## views, Label3D boards in group "race_board", the line's lights in group
## "race_light" (meta "index", 0 first), and one node per gate in group
## "race_gate" (meta "gate", the gate's index) with a Label3D child "Split".
## Pit tuning benches are Marker3D nodes in group "race_tune" (metas
## "track" and "machine") with a "Status" label; `Race.tune` fits there.
## Race control's desks are Marker3D nodes in group "race_desk" (metas
## "track" and "machine", an empty machine for the watch desk) with a
## Label3D child "Status" for `RaceView` to write on; each track's `pit` is
## where a finished racer is set down.

const TRACK_ID := "coilrun"
const TRACK_NAME := "Coilrun"
const TRACK_W := 14.0
const LAPS := 3
## The centre line's control points, clockwise. The bump after the hairpin
## is the Crest.
const CONTROL := [
	Vector3(-120, 0, 0), Vector3(0, 0, 0), Vector3(110, 0, 0), Vector3(165, 0, 15), Vector3(175, 0, 50),
	Vector3(148, 0, 72), Vector3(125, 3.2, 69), Vector3(102, 0, 66), Vector3(85, 0, 100), Vector3(110, 0, 145),
	Vector3(80, 0, 190), Vector3(68, 0, 250), Vector3(60, 0, 320), Vector3(20, 0, 400), Vector3(-60, 0, 430),
	Vector3(-140, 0, 400), Vector3(-180, 0, 320), Vector3(-190, 0, 230), Vector3(-225, 0, 160),
	Vector3(-200, 0, 110), Vector3(-230, 0, 60), Vector3(-190, 0, 18),
]
const LINE := Vector3(-80, 0, 0)
const CHECKPOINTS := [Vector3(175, 0, 50), Vector3(110, 0, 145), Vector3(20, 0, 400), Vector3(-200, 0, 110)]
## The dry coolant spillway the track jumps: along x at this z.
const CHANNEL_Z := 250.0
const CHANNEL_X := Vector2(-10.0, 200.0)
const CHANNEL_W := 12.0
const CHANNEL_DEPTH := 6.0
## The coil rings over the Rail.
const RAIL_FROM := -100.0
const RAIL_TO := 100.0
## Pit row, north of the line.
const PIT_Z := -30.0
const LAYOUT_SEED := 7071
## The planet's rocks stand no nearer than `FAR_CLEAR` to `FAR_CENTRE`, the
## middle of both circuits, so none lands on a road or a stand.
const FAR_CENTRE := Vector3(-40, 0, 100)
const FAR_CLEAR := 800.0

const CYAN := Color(0.3, 0.85, 1.0)
const AMBER := Color(1.0, 0.6, 0.2)
const SkyhookScript := preload("res://worlds/meridian/skyhook.gd")
const StandsScript := preload("res://worlds/meridian/stands.gd")
const SkylineScript := preload("res://worlds/meridian/skyline.gd")
const WorksScript := preload("res://worlds/meridian/works.gd")
## Half the salt pan's width: past it the dunes rise (`_build_far_land`),
## near enough that the works run up into them.
const GROUND_HALF := 900.0
## What the works keep clear of (`works.gd`): [centre, radius, and how far
## off trackside fences stay]: the pits and race control, the stands, the
## skyline's towers, cranes and booster.
const WORKS_KEEP_OUT := [
	[Vector3(-110, 0, -60), 100.0, 80.0], [Vector3(-45, 0, 40), 75.0, 80.0], [Vector3(150, 0, 38), 80.0, 62.0],
	[Vector3(-60, 0, 330), 80.0, 78.0], [Vector3(66, 0, 282), 45.0, 34.0], [Vector3(-186, 0, 275), 30.0, 30.0],
	[Vector3(-228, 0, -138), 50.0, 46.0], [Vector3(-145, 0, -100), 60.0, 40.0], [Vector3(430, 0, 300), 40.0],
	[Vector3(-560, 0, 230), 40.0], [Vector3(160, 0, -470), 40.0], [Vector3(360, 0, -200), 35.0],
	[Vector3(-520, 0, -300), 35.0], [Vector3(-300, 0, 640), 60.0],
]

var nav_region: Node3D
## The planet the map stands on (`WorldDef.planet_type`), set before it
## enters the tree.
var planet: PlanetType
var _track: RaceTrack
var _skyhook_track: RaceTrack
var _skyhook: RefCounted
var _rng := RandomNumberGenerator.new()
var _art_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = LAYOUT_SEED
	_art_rng.seed = LAYOUT_SEED
	race_track()
	nav_region = Node3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_environment()
	_build_ground()
	_build_road()
	_build_spillway()
	_build_yard_rubble()
	_build_pits()
	_build_gantry(_track)
	_build_gates(_track)
	_skyhook = SkyhookScript.new(self)
	_skyhook.call("build", race_tracks()[1])
	_build_race_control()
	_dress()


func race_track() -> RaceTrack:
	if _track == null:
		var control: Array[Vector3] = []
		control.assign(CONTROL)
		var spots: Array[Vector3] = []
		spots.assign(CHECKPOINTS)
		_track = RaceTrack.build(TRACK_ID, TRACK_NAME, control, TRACK_W, spots, LINE, LAPS)
		# Pit row, between the wall and the bays.
		_track.pit = Vector3(-104, 0, PIT_Z + 10.0)
	return _track


## Coilrun first, then Skyhook.
func race_tracks() -> Array[RaceTrack]:
	if _skyhook_track == null:
		_skyhook_track = SkyhookScript.build_track()
	return [race_track(), _skyhook_track] as Array[RaceTrack]


## Level salt flats: the road's own height only rises on the Crest.
func ground_height(_x: float, _z: float) -> float:
	return 0.0


func _build_environment() -> void:
	# The sun stuck on the horizon: long shadows, a dusty orange sky with a
	# ringed giant in it.
	Planet.atmosphere(self, planet)


# --- Shapes ----------------------------------------------------------------------

func _box(size: Vector3, at: Vector3, material: Material, yaw := 0.0, solid := true) -> Node3D:
	var root: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = Actor.LAYER_WORLD
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = BoxShape3D.new()
		col.shape.size = size
		body.add_child(col)
		root = body
	else:
		root = Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.mesh.material = material
	root.add_child(mesh)
	root.position = at
	root.rotation.y = yaw
	nav_region.add_child(root)
	return root


func _glow(color: Color, energy: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _metal(tint: Color, grime := 0.5) -> Material:
	return Look.surface("metal", {"metal": 0.25, "tint": tint, "grime": grime, "scale": 0.3})


func _in_gap(p: Vector3) -> bool:
	return absf(p.z - CHANNEL_Z) < CHANNEL_W * 0.5 and p.x > CHANNEL_X.x and p.x < CHANNEL_X.y


func _dist_to_track(p: Vector3) -> float:
	return _track.offset(p, _track.locate(p))


func _yaw_at(i: int) -> float:
	return _track.heading(i)


# --- Ground and road ---------------------------------------------------------------

func _build_ground() -> void:
	var salt := Planet.ground_material(planet)
	var big := GROUND_HALF * 2.0
	var north := CHANNEL_Z - CHANNEL_W * 0.5
	var south := CHANNEL_Z + CHANNEL_W * 0.5
	_box(Vector3(big, 8, north + big * 0.5), Vector3(0, -4, (north - big * 0.5) * 0.5), salt)
	_box(Vector3(big, 8, big * 0.5 - south), Vector3(0, -4, (south + big * 0.5) * 0.5), salt)
	var w_left := CHANNEL_X.x + big * 0.5
	_box(Vector3(w_left, 8, CHANNEL_W), Vector3(-big * 0.5 + w_left * 0.5, -4, CHANNEL_Z), salt)
	var w_right := big * 0.5 - CHANNEL_X.y
	_box(Vector3(w_right, 8, CHANNEL_W), Vector3(CHANNEL_X.y + w_right * 0.5, -4, CHANNEL_Z), salt)
	var bed := Look.surface("concrete", {"tint": Color(0.5, 0.45, 0.42), "grime": 0.7})
	_box(Vector3(CHANNEL_X.y - CHANNEL_X.x, 1, CHANNEL_W), Vector3((CHANNEL_X.x + CHANNEL_X.y) * 0.5,
			-CHANNEL_DEPTH - 0.5, CHANNEL_Z), bed)
	_build_far_land(big * 0.5)


## Past the salt boxes the planet's own land runs on to the horizon, with
## its mesas, spires and slabs; none of it collides or is read by the race.
## Rocks keep clear of the circuits and the launch works round them.
func _build_far_land(half: float) -> void:
	if not Look.enabled:
		return
	var land := PlanetTerrain.new(planet.terrain, LAYOUT_SEED)
	add_child(Planet.horizon(planet, land, half))
	var height_of := func(x: float, z: float) -> float:
		return 0.0 if maxf(absf(x), absf(z)) < half else land.height_at(x, z)
	var clear := func(x: float, z: float) -> bool:
		return Vector2(x - FAR_CENTRE.x, z - FAR_CENTRE.z).length() > FAR_CLEAR
	PlanetProps.scatter(self, planet, height_of, half, LAYOUT_SEED + 3, clear)


## The road: one mesh along the centre line, with collision, glowing edge
## lines, and an embankment under the Crest.
func _build_road() -> void:
	var road := Look.surface("asphalt", {"tint": Color(0.62, 0.6, 0.62), "grime": 0.3, "scale": 0.25})
	var bank := Look.surface("concrete", {"tint": Color(0.7, 0.62, 0.55), "grime": 0.5})
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var pts := _track.points
	var n := pts.size()
	var lift := Vector3(0, 0.06, 0)
	for i in n:
		var j := (i + 1) % n
		var a := pts[i] + lift
		var b := pts[j] + lift
		if _in_gap(a) or _in_gap(b):
			continue
		var sa := _track.side(i) * TRACK_W * 0.5
		var sb := _track.side(j) * TRACK_W * 0.5
		var q := [a - sa, a + sa, b + sb, b - sb]
		for v: Vector3 in [q[0], q[2], q[1], q[0], q[3], q[2]]:
			top.set_normal(Vector3.UP)
			top.set_uv(Vector2(v.x, v.z) * 0.25)
			top.add_vertex(v)
			faces.append(v)
		# The embankment's walls where the road stands above the flats.
		if a.y > 0.1 or b.y > 0.1:
			for edge: Array in [[q[0], q[3]], [q[2], q[1]]]:
				var e0: Vector3 = edge[0]
				var e1: Vector3 = edge[1]
				var w := [e0, e1, Vector3(e1.x, 0, e1.z), Vector3(e0.x, 0, e0.z)]
				for v: Vector3 in [w[0], w[2], w[1], w[0], w[3], w[2]]:
					sides.add_vertex(v)
					faces.append(v)
		for s: float in [-1.0, 1.0]:
			var oa := _track.side(i) * s * (TRACK_W * 0.5 - 0.35)
			var ob := _track.side(j) * s * (TRACK_W * 0.5 - 0.35)
			var wa := _track.side(i) * 0.18
			var wb := _track.side(j) * 0.18
			var up := Vector3(0, 0.01, 0)
			var e := [a + oa - wa + up, a + oa + wa + up, b + ob + wb + up, b + ob - wb + up]
			for v: Vector3 in [e[0], e[2], e[1], e[0], e[3], e[2]]:
				lines.set_normal(Vector3.UP)
				lines.add_vertex(v)
	var body := StaticBody3D.new()
	body.name = "Road"
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)
	top.generate_tangents()
	var top_mesh := MeshInstance3D.new()
	top_mesh.mesh = top.commit()
	top_mesh.mesh.surface_set_material(0, road)
	body.add_child(top_mesh)
	sides.generate_normals()
	var side_mesh := sides.commit()
	if side_mesh != null and side_mesh.get_surface_count() > 0:
		var side_node := MeshInstance3D.new()
		side_node.mesh = side_mesh
		side_node.mesh.surface_set_material(0, bank)
		body.add_child(side_node)
	var line_node := MeshInstance3D.new()
	line_node.mesh = lines.commit()
	line_node.mesh.surface_set_material(0, _glow(CYAN, 2.5))
	line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(line_node)
	nav_region.add_child(body)
	# Kerbs on the outside of the corners, amber and white.
	for i in range(0, n, 3):
		var bend := _track.forward(i).cross(_track.forward((i + 6) % n)).y
		if absf(bend) < 0.12 or _in_gap(pts[i]):
			continue
		var outside := -signf(bend)
		var mat := _glow(AMBER, 2.0) if (i / 3) % 2 == 0 else _glow(Color(0.9, 0.9, 0.95), 0.6)
		_box(Vector3(1.2, 0.12, 1.6), pts[i] + _track.side(i) * outside * (TRACK_W * 0.5 + 0.6) + Vector3(0, 0.06, 0),
				mat, _yaw_at(i), false)
	# The line and the grid boxes behind it.
	var line_i: int = _track.gates[0].index
	_box(Vector3(TRACK_W, 0.03, 1.0), pts[line_i] + Vector3(0, 0.08, 0), _glow(Color.WHITE, 3.0), _yaw_at(line_i), false)
	for slot in _track.start_slots:
		_box(Vector3(2.6, 0.03, 0.25), slot.origin + slot.basis * Vector3(0, 0.08, -1.6), _glow(Color(0.9, 0.9, 1.0), 1.2),
				slot.basis.get_euler().y, false)


## The Spillway: a ramp on the left half for wheels, chevrons on the level
## lip of the right half for a hover float.
func _build_spillway() -> void:
	var i := _track.locate(Vector3(68, 0, CHANNEL_Z - CHANNEL_W * 0.5 - 2.0))
	var guard := 0
	while not _in_gap(_track.points[(i + 1) % _track.points.size()]) and guard < 20:
		i += 1
		guard += 1
	var at := _track.points[i]
	var fwd := _track.forward(i)
	var side := _track.side(i)
	# Wheels can only cross on the ramp: they keep to the left half from well
	# before it to the far bank.
	var n := _track.points.size()
	_track.keep_to((i - 30 + n) % n, (i + 10) % n, -TRACK_W * 0.25, "wheels")
	var ramp_mat := _metal(Color(0.6, 0.48, 0.32))
	var prism := PrismMesh.new()
	prism.size = Vector3(9.0, 1.4, TRACK_W * 0.46)
	prism.left_to_right = 1.0
	prism.material = ramp_mat
	var ramp := StaticBody3D.new()
	ramp.name = "SpillwayRamp"
	ramp.collision_layer = Actor.LAYER_WORLD
	ramp.collision_mask = 0
	ramp.position = at + side * (-TRACK_W * 0.25) - fwd * 4.5 + Vector3(0, 0.76, 0)
	ramp.basis = Basis(fwd.cross(Vector3.UP).normalized(), Vector3.UP, -fwd).orthonormalized()
	var shape_node := CollisionShape3D.new()
	shape_node.shape = prism.create_convex_shape()
	shape_node.rotation.y = PI / 2.0
	ramp.add_child(shape_node)
	var mesh := MeshInstance3D.new()
	mesh.mesh = prism
	mesh.rotation.y = PI / 2.0
	ramp.add_child(mesh)
	nav_region.add_child(ramp)
	for k in 3:
		_box(Vector3(TRACK_W * 0.45, 0.04, 0.5), at + side * (TRACK_W * 0.25) - fwd * (1.0 + k * 2.0) + Vector3(0, 0.09, 0),
				_glow(CYAN, 3.0), atan2(-fwd.x, -fwd.z), false)


## Shattered insulator plates scattered over the inside of the Capacitor
## Yard's esses. Flat and loose: they mark the inside line, and stop nothing
## (rough ground that slows wheels is still to come, DESIGN.md section 9).
func _build_yard_rubble() -> void:
	var debris := Look.surface("concrete", {"tint": Color(0.7, 0.66, 0.6), "grime": 0.6})
	var n := _track.points.size()
	var from := _track.locate(Vector3(85, 0, 100))
	var to := _track.locate(Vector3(80, 0, 190))
	var i := from
	while i != to:
		var bend := _track.forward(i).cross(_track.forward((i + 4) % n)).y
		# `side` is the right; a bend to the left (bend > 0) has its inside left.
		var inside := -signf(bend) if absf(bend) > 0.02 else 1.0
		for j in 2:
			var off := _rng.randf_range(0.6, TRACK_W * 0.42)
			var at := _track.points[i] + _track.side(i) * inside * off + _track.forward(i) * _rng.randf_range(-1, 1)
			_box(Vector3(_rng.randf_range(0.5, 1.4), _rng.randf_range(0.05, 0.12), _rng.randf_range(0.4, 1.0)),
					at + Vector3(0, 0.08, 0), debris, _rng.randf() * TAU, false)
		i = (i + 2) % n
		if posmod(to - i, n) < 2:
			break


# --- Pit row, the line and the gates -------------------------------------------------

## Pit row, north of the line behind a low wall: the pit building, the bays
## with the stock machines, the arrival pad, race control and the board.
func _build_pits() -> void:
	var wall := Look.surface("metal", {"metal": 0.25, "tint": Color(0.36, 0.37, 0.42), "grime": 0.3,
			"window_glow": Color(0.5, 0.85, 1.0), "lit_windows": 0.5})
	var dark := _metal(Color(0.14, 0.14, 0.17), 0.2)
	# The pit wall: between pit row and the track, with a gap at each end.
	_box(Vector3(120, 1.1, 0.8), Vector3(-90, 0.55, -TRACK_W * 0.5 - 4.0), _metal(Color(0.5, 0.5, 0.55)))
	var pits := _box(Vector3(80, 7, 12), Vector3(-90, 3.5, PIT_Z - 14.0), wall)
	Look.make_building(pits.get_child(1), Vector3(80, 7, 12), 3.0)
	# Bays: four of each machine, lit pads facing the track.
	for k in 8:
		var x := -140.0 + k * 9.0
		var source := "bay_scrapper" if k < 4 else "bay_raider"
		var marker := Marker3D.new()
		marker.add_to_group("spawn_vehicle")
		marker.set_meta("loot_source", source)
		marker.position = Vector3(x, 0.1, PIT_Z + 4.0)
		marker.rotation.y = PI
		add_child(marker)
		_box(Vector3(4.0, 0.04, 6.0), Vector3(x, 0.03, PIT_Z + 4.0), _glow(AMBER if k < 4 else CYAN, 0.8, 0.5),
				0.0, false)
		var tag := Label3D.new()
		tag.text = "SCRAPPER" if k < 4 else "RAIDER"
		tag.font_size = 64
		tag.pixel_size = 0.008
		tag.modulate = AMBER if k < 4 else CYAN
		tag.position = Vector3(x, 0.05, PIT_Z + 7.4)
		tag.rotation = Vector3(-PI / 2.0, 0, 0)
		add_child(tag)
	# The tuning benches, behind each machine's bays.
	_tune_bench(Vector3(-126.5, 0, PIT_Z - 3.0), TRACK_ID, "bike_scrapper", AMBER)
	_tune_bench(Vector3(-90.5, 0, PIT_Z - 3.0), TRACK_ID, "bike_raider", CYAN)
	# Where a racer arrives: by the pit building's door.
	var spawn := Marker3D.new()
	spawn.add_to_group("spawn_player")
	spawn.position = Vector3(-160, 0.3, PIT_Z - 2.0)
	add_child(spawn)
	var pad := MeshInstance3D.new()
	pad.mesh = CylinderMesh.new()
	pad.mesh.top_radius = 2.6
	pad.mesh.bottom_radius = 2.6
	pad.mesh.height = 0.1
	pad.mesh.material = _glow(AMBER, 1.5, 0.7)
	pad.position = spawn.position + Vector3(0, -0.24, 0)
	add_child(pad)
	# Race control: a sign over the bays saying how a run starts.
	var sign := Label3D.new()
	sign.text = "RACE CONTROL · COILRUN\nTake a machine from a bay to start a time trial"
	sign.font_size = 72
	sign.pixel_size = 0.01
	sign.modulate = CYAN
	sign.position = Vector3(-108, 8.6, PIT_Z - 7.9)
	add_child(sign)
	# The board: on two legs at the far end of pit row, facing the track.
	var bx := -30.0
	for x: float in [bx - 11.0, bx + 11.0]:
		_box(Vector3(1.2, 16, 1.2), Vector3(x, 8, PIT_Z - 4.0), dark)
	_box(Vector3(26, 13, 0.8), Vector3(bx, 18, PIT_Z - 4.0), dark)
	var screen := MeshInstance3D.new()
	screen.mesh = QuadMesh.new()
	screen.mesh.size = Vector2(25, 12)
	screen.mesh.material = _glow(Color(0.02, 0.05, 0.08), 0.6)
	screen.position = Vector3(bx, 18, PIT_Z - 3.55)
	add_child(screen)
	var head := Label3D.new()
	head.text = "%s  ·  STREET  ·  TIME TRIAL" % TRACK_NAME.to_upper()
	head.font_size = 96
	head.pixel_size = 0.012
	head.modulate = AMBER
	head.position = Vector3(bx, 22.6, PIT_Z - 3.5)
	add_child(head)
	var rows := Label3D.new()
	rows.name = "Board"
	rows.add_to_group("race_board")
	rows.text = "No times yet"
	rows.font_size = 72
	rows.pixel_size = 0.012
	rows.line_spacing = 8
	rows.modulate = Color(0.6, 0.9, 1.0)
	rows.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rows.position = Vector3(bx, 17.0, PIT_Z - 3.5)
	add_child(rows)


## The gantry over a track's line: five lights that count a run down. A
## track other than the first tags them with its id (`tag`).
func _build_gantry(track: RaceTrack, tag := "", color := Color(0.6, 0.9, 1.0)) -> void:
	var steel := _metal(Color(0.32, 0.33, 0.38), 0.4)
	var i: int = track.gates[0].index
	var at := track.points[i]
	var yaw := track.heading(i)
	var side := track.side(i)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(1.2, 9, 1.2), at + side * s * (TRACK_W * 0.5 + 1.5) + Vector3(0, 4.5, 0), steel, yaw)
	_box(Vector3(TRACK_W + 4.2, 1.8, 1.6), at + Vector3(0, 9.2, 0), steel, yaw, false)
	for k in Race.LIGHTS:
		var pod := MeshInstance3D.new()
		pod.name = "%sLight%d" % [tag.capitalize(), k]
		pod.add_to_group("race_light")
		pod.set_meta("index", k)
		if tag != "":
			pod.set_meta("track", tag)
		pod.mesh = SphereMesh.new()
		pod.mesh.radius = 0.55
		pod.mesh.height = 1.1
		pod.mesh.material = _glow(Color(0.15, 0.05, 0.05), 0.2)
		pod.position = at + side * (-5.0 + k * 2.5) + Vector3(0, 9.2, 0) - track.forward(i) * 0.85
		add_child(pod)
	var sign := Label3D.new()
	sign.text = track.display_name.to_upper()
	sign.font_size = 160
	sign.pixel_size = 0.01
	sign.modulate = color
	sign.position = at + Vector3(0, 11.0, 0) - track.forward(i) * 0.9
	sign.rotation.y = yaw
	add_child(sign)


## A hard-light arch over each of a track's checkpoints, with its number and
## a place for the racer's split (`RaceView` writes it). A track other than
## the first tags them with its id (`tag`).
func _build_gates(track: RaceTrack, tag := "", color := CYAN) -> void:
	for g in range(1, track.gates.size()):
		var gate: Dictionary = track.gates[g]
		var i: int = gate.index
		var at: Vector3 = gate.at
		var yaw := track.heading(i)
		var root := Node3D.new()
		root.name = "%sGate%d" % [tag.capitalize(), g]
		root.add_to_group("race_gate")
		root.set_meta("gate", g)
		if tag != "":
			root.set_meta("track", tag)
		root.position = at
		root.rotation.y = yaw
		add_child(root)
		var frame := _glow(color, 2.5, 0.55)
		var w := track.width
		for s: float in [-1.0, 1.0]:
			_arch_part(root, Vector3(0.4, 7, 0.4), Vector3(s * (w * 0.5 + 0.8), 3.5, 0), frame)
		_arch_part(root, Vector3(w + 2.0, 0.4, 0.4), Vector3(0, 7, 0), frame)
		_arch_part(root, Vector3(w + 1.2, 6.6, 0.05), Vector3(0, 3.6, 0), _glow(color, 0.6, 0.06))
		var num := Label3D.new()
		num.text = "CHECKPOINT %d / %d" % [g, track.gates.size() - 1]
		num.font_size = 72
		num.pixel_size = 0.012
		num.modulate = Color(0.6, 0.9, 1.0)
		# Facing the racers coming up to it (a Label3D faces +z, back down
		# the track here).
		num.position = Vector3(0, 7.8, 0)
		num.double_sided = true
		root.add_child(num)
		var split := Label3D.new()
		split.name = "Split"
		split.text = ""
		split.font_size = 220
		split.pixel_size = 0.012
		split.position = Vector3(0, 9.8, 0)
		root.add_child(split)


func _arch_part(root: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.mesh.material = mat
	mesh.position = at
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)


## Where racers arrive: a board pointing to each track's pit row, facing
## the arrival pad.
func _build_race_control() -> void:
	var at := Vector3(-166, 0, -42)
	var dark := _metal(Color(0.12, 0.12, 0.15), 0.2)
	for x: float in [-4.5, 4.5]:
		_box(Vector3(0.4, 6.5, 0.4), at + Vector3(x, 3.25, -0.3), dark)
	_box(Vector3(13, 2.6, 0.3), at + Vector3(0, 5.2, -0.3), dark, 0.0, false)
	for spec: Array in [["COILRUN · bays by the pit building", AMBER, 5.8],
			["SKYHOOK · bays to the north", Color(1.0, 0.3, 0.7), 4.6]]:
		var label := Label3D.new()
		label.text = spec[0]
		label.font_size = 64
		label.pixel_size = 0.01
		label.modulate = spec[1]
		label.position = at + Vector3(0, float(spec[2]), -0.1)
		add_child(label)
	# The desks under it: race on each machine, or watch, for each track.
	var x := -181.0
	for spec: Array in [[TRACK_ID, AMBER], [SkyhookScript.TRACK_ID, Color(1.0, 0.3, 0.7)]]:
		for machine: String in ["bike_scrapper", "bike_raider", ""]:
			_desk(Vector3(x, 0, -37.5), str(spec[0]), machine, spec[1])
			x += 4.0
		x += 10.0


## A desk at race control: a lit pedestal and the marker `RaceView` and the
## `Race` read (group "race_desk"), its words on the "Status" label.
func _desk(at: Vector3, track_id: String, machine: String, color: Color) -> void:
	var marker := Marker3D.new()
	marker.add_to_group("race_desk")
	marker.set_meta("track", track_id)
	marker.set_meta("machine", machine)
	marker.position = at
	add_child(marker)
	_box(Vector3(1.6, 1.05, 0.7), at + Vector3(0, 0.525, -0.6), _metal(Color(0.14, 0.14, 0.17), 0.2))
	_box(Vector3(1.5, 0.05, 0.6), at + Vector3(0, 1.08, -0.6), _glow(CYAN if machine == "" else color, 1.6, 0.8),
			0.0, false)
	var label := Label3D.new()
	label.name = "Status"
	label.font_size = 48
	label.pixel_size = 0.006
	label.modulate = CYAN if machine == "" else color
	label.position = Vector3(0, 1.9, -0.6)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.text = desk_title(track_id, machine)
	marker.add_child(label)


## A pit tuning bench for one machine: a tool counter and the marker the
## `Race` and `RaceView` read (group "race_tune", metas "track" and
## "machine"), its words on the "Status" label. `back` is the side of the
## marker the counter stands on (-1 toward -z).
func _tune_bench(at: Vector3, track_id: String, machine: String, color: Color, back := -1.0) -> void:
	var marker := Marker3D.new()
	marker.add_to_group("race_tune")
	marker.set_meta("track", track_id)
	marker.set_meta("machine", machine)
	marker.position = at
	add_child(marker)
	_box(Vector3(2.4, 0.95, 0.8), at + Vector3(0, 0.475, 0.7 * back), _metal(Color(0.2, 0.2, 0.22), 0.4))
	_box(Vector3(2.3, 0.05, 0.7), at + Vector3(0, 0.98, 0.7 * back), _glow(color, 1.2, 0.6), 0.0, false)
	_box(Vector3(2.4, 1.4, 0.1), at + Vector3(0, 1.65, 1.1 * back), _metal(Color(0.1, 0.1, 0.12), 0.3))
	var label := Label3D.new()
	label.name = "Status"
	label.font_size = 40
	label.pixel_size = 0.005
	label.modulate = color
	label.position = Vector3(0, 1.7, 1.0 * back)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.text = "%s TUNING" % ("SCRAPPER" if machine == "bike_scrapper" else "RAIDER")
	marker.add_child(label)


## A desk's own words, before `RaceView` adds the next race's.
static func desk_title(track_id: String, machine: String) -> String:
	var track_name := TRACK_NAME if track_id == TRACK_ID else SkyhookScript.TRACK_NAME
	if machine == "":
		return "%s\nWATCH THE RACE" % track_name.to_upper()
	return "%s · %s\nRACE" % [track_name.to_upper(), "SCRAPPER" if machine == "bike_scrapper" else "RAIDER"]


# --- Decoration only: no collision, nothing the game depends on ----------------------

func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	_dress_rail(art)
	_dress_launch_ramp(art)
	_dress_yard(art)
	_dress_tower(art)
	_dress_pylons(art)
	_dress_spectacle(art)
	for i in 6:
		var lamp := Look.prop("Light_Street_2.glb", 7.0, 0.3)
		if lamp:
			lamp.position = Vector3(-60 + i * 30.0, 0, -TRACK_W * 0.5 - 6.0)
			art.add_child(lamp)


func _ring(parent: Node3D, inner: float, outer: float, at: Vector3, rot: Vector3, mat: Material, segments := 8) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 48
	torus.ring_segments = segments
	torus.material = mat
	ring.mesh = torus
	ring.position = at
	ring.rotation = rot
	parent.add_child(ring)


## The mass driver's coil rings over the Rail, half sunk in the salt, each
## with its live band still glowing.
func _dress_rail(art: Node3D) -> void:
	var coil := _metal(Color(0.4, 0.4, 0.44), 0.6)
	var x := RAIL_FROM
	var k := 0
	while x <= RAIL_TO:
		_ring(art, 11.0, 13.0, Vector3(x, 3.0, 0), Vector3(0, 0, PI / 2.0), coil)
		_ring(art, 10.85, 11.15, Vector3(x, 3.0, 0), Vector3(0, 0, PI / 2.0),
				_glow(CYAN if k % 4 != 3 else AMBER, 3.0), 6)
		x += 22.0
		k += 1


## Past the hairpin the rail climbs off the flats into the sky and breaks
## off mid-air, a red beacon at its end: seen from all over the track.
func _dress_launch_ramp(art: Node3D) -> void:
	var steel := _metal(Color(0.32, 0.32, 0.36), 0.7)
	var start := Vector3(240, 0, 0)
	var pitch := deg_to_rad(16.0)
	var dir := Vector3(cos(pitch), sin(pitch), 0)
	var length := 900.0
	for s: float in [-6.0, 6.0]:
		var beam := MeshInstance3D.new()
		beam.mesh = BoxMesh.new()
		beam.mesh.size = Vector3(length, 2.5, 2.0)
		beam.mesh.material = steel
		beam.position = start + dir * length * 0.5 + Vector3(0, 0, s)
		beam.rotation.z = pitch
		art.add_child(beam)
	var d := 30.0
	var k := 0
	while d < length:
		var at := start + dir * d
		if at.y > 6.0 and k % 2 == 0:
			for s: float in [-7.0, 7.0]:
				var leg := MeshInstance3D.new()
				leg.mesh = BoxMesh.new()
				leg.mesh.size = Vector3(2.5, at.y, 2.5)
				leg.mesh.material = steel
				leg.position = Vector3(at.x, at.y * 0.5, s)
				art.add_child(leg)
		_ring(art, 8.0, 9.6, at + Vector3(0, 6, 0), Vector3(0, 0, PI / 2.0 + pitch), steel)
		if k % 3 == 0:
			_ring(art, 7.9, 8.15, at + Vector3(0, 6, 0), Vector3(0, 0, PI / 2.0 + pitch), _glow(CYAN, 2.5), 6)
		d += 40.0
		k += 1
	var beacon := MeshInstance3D.new()
	beacon.mesh = SphereMesh.new()
	beacon.mesh.radius = 3.0
	beacon.mesh.height = 6.0
	beacon.mesh.material = _glow(Color(1.0, 0.25, 0.15), 6.0)
	beacon.position = start + dir * length + Vector3(0, 4, 0)
	art.add_child(beacon)


func _dress_yard(art: Node3D) -> void:
	var steel := _metal(Color(0.75, 0.7, 0.62), 0.8)
	var placed := 0
	var tries := 0
	while placed < 28 and tries < 600:
		tries += 1
		var p := Vector3(_art_rng.randf_range(30, 170), 0, _art_rng.randf_range(90, 220))
		if _dist_to_track(p) < 13.0 or _in_gap(p):
			continue
		var h := _art_rng.randf_range(6.0, 13.0)
		var can := MeshInstance3D.new()
		can.mesh = CylinderMesh.new()
		can.mesh.top_radius = 2.6
		can.mesh.bottom_radius = 2.8
		can.mesh.height = h
		can.mesh.material = steel
		can.position = p + Vector3(0, h * 0.5, 0)
		art.add_child(can)
		var cap := MeshInstance3D.new()
		cap.mesh = CylinderMesh.new()
		cap.mesh.top_radius = 2.0
		cap.mesh.bottom_radius = 2.0
		cap.mesh.height = 0.4
		cap.mesh.material = _glow(CYAN, 1.5)
		cap.position = p + Vector3(0, h + 0.2, 0)
		art.add_child(cap)
		placed += 1


## The cracked cooling tower the Tower Sweep runs round.
func _dress_tower(art: Node3D) -> void:
	var concrete := Look.surface("concrete", {"tint": Color(0.75, 0.68, 0.6), "grime": 0.7, "scale": 0.05})
	var c := Vector3(-60, 0, 330)
	for part: Array in [[38.0, 26.0, 40.0, 0.0], [26.0, 30.0, 34.0, 40.0]]:
		var m := MeshInstance3D.new()
		m.mesh = CylinderMesh.new()
		m.mesh.bottom_radius = part[0]
		m.mesh.top_radius = part[1]
		m.mesh.height = part[2]
		m.mesh.radial_segments = 32
		m.mesh.material = concrete
		m.position = c + Vector3(0, float(part[3]) + float(part[2]) * 0.5, 0)
		art.add_child(m)
	_ring(art, 29.0, 31.0, c + Vector3(0, 74, 0), Vector3.ZERO, _glow(AMBER, 1.2))


## Relay pylons the chicane threads through, red lamps on top.
func _dress_pylons(art: Node3D) -> void:
	var steel := _metal(Color(0.32, 0.32, 0.35), 0.5)
	for p: Vector3 in [Vector3(-190, 0, 185), Vector3(-240, 0, 135), Vector3(-180, 0, 125), Vector3(-255, 0, 85),
			Vector3(-208, 0, 45)]:
		if _dist_to_track(p) < 12.0:
			continue
		for s: float in [-1.5, 1.5]:
			var post := MeshInstance3D.new()
			post.mesh = BoxMesh.new()
			post.mesh.size = Vector3(0.6, 26, 0.6)
			post.mesh.material = steel
			post.position = p + Vector3(s, 13, 0)
			art.add_child(post)
		for h: float in [6.0, 12.0, 18.0, 24.0]:
			var bar := MeshInstance3D.new()
			bar.mesh = BoxMesh.new()
			bar.mesh.size = Vector3(4.0, 0.4, 0.4)
			bar.mesh.material = steel
			bar.position = p + Vector3(0, h, 0)
			art.add_child(bar)
		var dot := MeshInstance3D.new()
		dot.mesh = SphereMesh.new()
		dot.mesh.radius = 0.5
		dot.mesh.height = 1.0
		dot.mesh.material = _glow(Color(1.0, 0.2, 0.1), 5.0)
		dot.position = p + Vector3(0, 27, 0)
		art.add_child(dot)


# --- The spectacle: stands, crowds, the big screen ----------------------------------

## Everything that makes a race an event, decoration only (`stands.gd`):
## the two-tier Meridian Grandstand along the Rail, stands round Breech
## Hairpin and the Spillway landing, terraces round the cooling tower, a
## footbridge over the run to the chicane, viewing barges over the infield,
## race control's tower and big screen, Skyhook's stand and stilts, and the
## world round them: mesas, the dead launch works, searchlights and camera
## drones (`skyline.gd`), and the works' districts, roads, car parks, the
## infield festival and the trackside fences (`works.gd`).
func _dress_spectacle(art: Node3D) -> void:
	var st: RefCounted = StandsScript.new(art, LAYOUT_SEED + 1)
	_dress_grandstand(st)
	# Round the outside of Breech Hairpin.
	var hairpin := Vector3(150, 0, 38)
	st.call("curved_stand", hairpin, 46.0, -1.25, 1.0, 9, 14)
	st.call("section_sign", "BREECH HAIRPIN", Transform3D(Basis(Vector3.UP, -PI / 2.0), hairpin + Vector3(70, 24, 0)), AMBER)
	# Both sides of the Spillway's landing.
	st.call("stand", Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(88, 0, 282)), 40.0, 12, 1.6, 1.0, 2.0)
	st.call("stand", Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(44, 0, 282)), 40.0, 12, 1.6, 1.0, 2.0)
	st.call("section_sign", "SPILLWAY", Transform3D(Basis(Vector3.UP, PI), Vector3(66, 16, 306)), AMBER)
	# Terraces round the cooling tower's foot, open to the north.
	var tower := Vector3(-60, 0, 330)
	st.call("curved_stand", tower, 52.0, -0.15 * PI, 1.15 * PI, 16, 8, 1.5, 1.4, 1.5, true)
	_ring(art, 27.5, 28.6, tower + Vector3(0, 42, 0), Vector3.ZERO, _glow(CYAN, 3.0), 6)
	_dress_bridge(st)
	_dress_barges(st)
	_dress_control_tower(st)
	_skyhook.call("dress", st)
	SkylineScript.new(st, LAYOUT_SEED + 2).call("build", race_tracks())
	st.call("finish")
	WorksScript.new(art, LAYOUT_SEED + 4, WORKS_KEEP_OUT.duplicate(true)).call("build", race_tracks())


## The Meridian Grandstand: two tiers along the Rail opposite the pits,
## sky boxes between them, a canopy and the circuit's name on the roof,
## floodlights behind, and a lit catch fence in front.
func _dress_grandstand(st: RefCounted) -> void:
	var xf := Transform3D(Basis(), Vector3(-45, 0, 19))
	var length := 200.0
	var lower: float = st.call("stand", xf, length, 18)
	var deck := 3.0 + 18 * 0.9
	var boxes := lower + 2.0
	st.call("box", Vector3(length, 5.0, 4.0), xf * Transform3D(Basis(), Vector3(0, deck + 2.5, boxes)), st.get("dark"))
	st.call("box", Vector3(length - 2, 3.4, 0.1), xf * Transform3D(Basis(), Vector3(0, deck + 2.6, boxes - 2.05)),
			st.call("glow", Color(0.5, 0.8, 1.0), 1.4, 0.55))
	var upper: float = st.call("stand", xf * Transform3D(Basis(), Vector3(0, 0, boxes + 2.0)), length, 16, 1.6, 1.15, deck + 5.0)
	var top := deck + 5.0 + 16 * 1.15 + 6.0
	st.call("canopy", xf, length, boxes + 2.0 + upper, top, 6.0)
	st.call("label", "MERIDIAN CIRCUIT", xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, top + 6.0, -2.0)), 900, CYAN, 0.03)
	for x: float in [-length * 0.5 - 6, -length * 0.17, length * 0.17, length * 0.5 + 6]:
		st.call("mast", xf * Vector3(x, 0, boxes + 40.0), top + 18.0)
	# The catch fence: lit posts and faint glass between the track and the stand.
	var fence_z := TRACK_W * 0.5 + 5.5
	var x := -140.0
	while x <= 55.0:
		st.call("box", Vector3(0.3, 5, 0.3), Transform3D(Basis(), Vector3(x, 2.5, fence_z)), st.get("dark"))
		st.call("box", Vector3(0.32, 0.6, 0.32), Transform3D(Basis(), Vector3(x, 5.1, fence_z)), st.call("glow", CYAN, 4.0))
		x += 6.0
	st.call("box", Vector3(196, 4.6, 0.05), Transform3D(Basis(), Vector3(-42.5, 2.4, fence_z)), st.get("glass"))


## A footbridge packed with people over the run to the chicane.
func _dress_bridge(st: RefCounted) -> void:
	var i := _track.locate(Vector3(-186, 0, 275))
	var at := _track.points[i]
	var side := _track.side(i)
	var fwd := _track.forward(i)
	var basis := Basis(side, Vector3.UP, side.cross(Vector3.UP).normalized())
	var xf := Transform3D(basis, at + Vector3(0, 9, 0))
	var dark: Material = st.get("dark")
	st.call("box", Vector3(46, 1.2, 6), xf, dark)
	for s: float in [-1.0, 1.0]:
		st.call("box", Vector3(46, 0.3, 0.2), xf * Transform3D(Basis(), Vector3(0, -0.5, s * 3.1)), st.call("glow", AMBER, 3.0))
		st.call("box", Vector3(3, 9, 6), Transform3D(basis, at + side * s * 21.0 + Vector3(0, 4.5, 0)), st.get("steel"))
		st.call("box", Vector3(46, 1.4, 0.15), xf * Transform3D(Basis(), Vector3(0, 1.3, s * 2.9)), st.get("glass"))
	st.call("fill_deck", xf * Transform3D(Basis(), Vector3(0, 0.6, 0)), Vector2(20, 2.4), 110, atan2(fwd.x, fwd.z))
	st.call("label", "PYLON BRIDGE", Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), at + Vector3(0, 11.5, 0) - fwd * 3.2),
			400, AMBER, 0.02)


## Viewing barges hanging over the infield on lit thrusters, full of people.
func _dress_barges(st: RefCounted) -> void:
	var dark: Material = st.get("dark")
	var jet := _glow(CYAN, 3.0, 0.5)
	for spec: Array in [[Vector3(40, 34, 120), 0.4], [Vector3(-20, 42, 250), -0.2], [Vector3(160, 30, 140), 1.2],
			[Vector3(-110, 38, 180), 0.9]]:
		var xf := Transform3D(Basis(Vector3.UP, spec[1]), spec[0])
		st.call("box", Vector3(30, 2.5, 12), xf, dark)
		st.call("box", Vector3(22, 3, 8), xf * Transform3D(Basis(), Vector3(0, -2.6, 0)), st.get("steel"))
		st.call("box", Vector3(30.2, 0.3, 12.2), xf * Transform3D(Basis(), Vector3(0, -0.6, 0)), st.call("glow", AMBER, 2.5))
		for s: float in [-1.0, 1.0]:
			st.call("box", Vector3(30, 1.2, 0.12), xf * Transform3D(Basis(), Vector3(0, 1.9, s * 5.9)), st.get("glass"))
			for e: float in [-11.0, 11.0]:
				var cone := MeshInstance3D.new()
				cone.mesh = CylinderMesh.new()
				cone.mesh.top_radius = 1.3
				cone.mesh.bottom_radius = 0.4
				cone.mesh.height = 5.0
				cone.mesh.material = jet
				cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				cone.transform = xf * Transform3D(Basis(), Vector3(e, -5.5, s * 4.0))
				(st.get("root") as Node3D).add_child(cone)
		st.call("fill_deck", xf * Transform3D(Basis(), Vector3(0, 1.25, 0)), Vector2(14, 5.3), 120)


## Race control's tower over the pits, and the big screen beside it facing
## the grandstand across the Rail.
func _dress_control_tower(st: RefCounted) -> void:
	var dark: Material = st.get("dark")
	var at := Vector3(-60, 0, -62)
	st.call("box", Vector3(14, 52, 14), Transform3D(Basis(), at + Vector3(0, 26, 0)), dark)
	for k in 10:
		st.call("box", Vector3(14.2, 0.2, 14.2), Transform3D(Basis(), at + Vector3(0, 5 + k * 5, 0)), st.call("glow", CYAN, 1.5))
	st.call("box", Vector3(26, 6, 22), Transform3D(Basis(), at + Vector3(0, 55, 4)), st.get("steel"))
	st.call("box", Vector3(26.2, 3.6, 22.2), Transform3D(Basis(), at + Vector3(0, 55, 4)),
			st.call("glow", Color(0.5, 0.8, 1.0), 1.0, 0.5))
	var screen := Vector3(-60, 30, -50)
	st.call("box", Vector3(50, 24, 1.5), Transform3D(Basis(), screen), dark)
	st.call("box", Vector3(48, 22, 0.1), Transform3D(Basis(), screen + Vector3(0, 0, 0.8)),
			st.call("glow", Color(0.02, 0.06, 0.1), 1.0))
	st.call("label", "MERIDIAN  ·  COILRUN  ·  SKYHOOK", Transform3D(Basis(), screen + Vector3(0, 7.5, 0.9)), 300, AMBER, 0.012)
	# The board's times, shown big for the stand.
	var rows := Label3D.new()
	rows.add_to_group("race_board")
	rows.text = ""
	rows.font_size = 260
	rows.pixel_size = 0.014
	rows.modulate = Color(0.6, 0.9, 1.0)
	rows.position = screen + Vector3(0, -1.5, 0.9)
	(st.get("root") as Node3D).add_child(rows)

