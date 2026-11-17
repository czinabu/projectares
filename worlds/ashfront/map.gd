extends Node3D
## Greybox Ashfront: one open battlefield, about 600 metres across.
##
## Rolling scorched ground, cratered by shelling and cut by trench lines, with
## five landmarks spread over it: a ruined foundry in the middle and four
## sites around it. Each landmark is a strongpoint with a depot and loot. Two
## armies start with two sites each, garrisoned, and muster their
## reinforcements on opposite sides of the rim; the foundry between them is
## nobody's. Between them lie the wrecks of war machines, which are the cover.
## Players drop in around the rim and ride or fly inward.
##
## The layout uses a fixed seed, so the map is the same every time while loot
## and spawns vary. The rest of the game relies only on the map contract in
## WorldDef. The ground, its collision and the navigation mesh are worked out
## once per run of the game and shared by every copy of the map.

const LAYOUT_SEED := 1337
## Metres between ground samples, and how many there are along each edge.
const CELL := 2.0
const SIDE := 321
## Beyond this distance from the middle the ground climbs into the rim.
const FIELD := 276.0
const RIM_HEIGHT := 46.0
## Players drop in on a ring this far out.
const SPAWN_RING := 248.0
const PLAYER_SPAWNS := 12
const HEIGHTS := [3.0, 6.0, 6.0, 10.0, 16.0]
const RAMP_LENGTH := 8.0
const RAMP_ANGLE_DEG := 15.0
const CRATERS := 80
const WRECKS := 56
## Fallen giants: the biggest wrecks, each a landmark with loot on its back.
const TITANS := 5
const COVER_LOTS := 44
const FIELD_PATROLS := 8
## Risk zones (DESIGN.md section 2): the core is the molten Foundry, the
## middle reaches past the four landmarks, the outer ring is the rest.
const CORE_RADIUS := 52.0
const MIDDLE_RADIUS := 225.0
## Gate outposts: safe bubbles on four of the rim's drop points, where
## players arrive. Each is a walled yard open toward the middle of the map.
const OUTPOSTS := [
	{"spawn": 2, "name": "Cinder Gate"},
	{"spawn": 5, "name": "Ember Gate"},
	{"spawn": 8, "name": "Slag Gate"},
	{"spawn": 11, "name": "Ash Gate"},
]
const OUTPOST_RADIUS := 13.0
## Jump ramps need level ground, so each gets a pad by the old front.
const RAMP_SPOTS := [Vector2(-52, -40), Vector2(58, -44), Vector2(-56, 44), Vector2(52, 40)]

## The landmarks: name, where, how wide, and how far the site is lifted above
## the ground around it.
const SITES := [
	{"name": "The Foundry", "at": Vector2(0, 0), "radius": 40.0, "lift": 0.0, "kind": "foundry", "army": ""},
	{"name": "Signal Hill", "at": Vector2(-150, -118), "radius": 28.0, "lift": 11.0, "kind": "hill", "army": "legion"},
	{"name": "Rustfall", "at": Vector2(158, -106), "radius": 32.0, "lift": 0.0, "kind": "graveyard", "army": "tide"},
	{"name": "The Breach", "at": Vector2(-142, 136), "radius": 32.0, "lift": 0.0, "kind": "breach", "army": "legion"},
	{"name": "Carrier Grave", "at": Vector2(134, 132), "radius": 34.0, "lift": 0.0, "kind": "carrier", "army": "tide"},
]
## The armies: what a site they hold shows as its holder, and where on the
## rim their reinforcements muster. The Legion has the west, the Tide the east.
const ARMIES := {
	"legion": {"holder_name": "the Legion", "muster": Vector2(-212, 4)},
	"tide": {"holder_name": "the Tide", "muster": Vector2(212, -4)},
}
const MUSTER_SPOTS := 6

## The Forge's tiers from the ground up: width and height of each block. The
## top is far over every flight rig's ceiling, so its upper tiers are only
## ever seen, never stood on.
const FORGE_AT := Vector2(2, -2)
const FORGE_TIERS := [Vector2(12.0, 8.0), Vector2(9.0, 22.0), Vector2(6.0, 24.0), Vector2(2.6, 20.0)]
const FORGE_BUTTRESS := Vector2(2.2, 36.0)
## The old front: which trench lines face across no man's land, so sandbags
## go on their lips and tank traps out in front of them.
const FRONT_LINES := [0, 1, 3, 4, 5]
const SANDBAG_EVERY := 15.0
const TRAP_OFFSET := 13.0
const TRAP_EVERY := 6.5
## How far the Forge's beacon is drawn: the whole map and past it.
const FAR_SIGHT := 2000.0
## Molten cracks running in to the core.
const CRACKS := 7
## What a cover lot is built from: concrete jersey barriers, sandbag walls and
## steel plates. `size` is length, height and depth.
const COVER_PIECES := [
	{"kind": "jersey", "size": Vector3(3.0, 1.1, 0.7)},
	{"kind": "sandbag", "size": Vector3(3.0, 1.0, 0.9)},
	{"kind": "plate", "size": Vector3(2.2, 1.6, 0.25)},
]

## Kept from the first map built in this run: { heights, collision, navmesh }.
static var _shared := {}

var nav_region: NavigationRegion3D
var terrain: Terrain
var _rng := RandomNumberGenerator.new()
## Dressing has its own generator so art never shifts the gameplay layout.
var _art_rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
## Flat ground: { at: Vector2, radius, height }.
var _pads: Array[Dictionary] = []
var _craters: Array[Dictionary] = []
## Trench lines as pairs of points.
var _trenches: Array[PackedVector2Array] = []
var _buildings: Array[Dictionary] = []
var _wrecks: Array[Dictionary] = []
var _cover_spots: Array[Vector3] = []
## Barricade pieces (jersey barriers, sandbag walls, plates, tank traps): the
## dressing draws each one by its "cover" meta over its plain collision box.
var _cover_pieces: Array[StaticBody3D] = []
## Everything solid standing on the ground: { at: Vector2, reach }.
var _solids: Array[Dictionary] = []
var _weather: Node3D
var _beacon: MeshInstance3D
var _beacon_light: OmniLight3D

@onready var GROUND := Look.surface("ground", {"tint": Color(0.4, 0.34, 0.31), "blend": "asphalt",
		"blend_amount": 0.45, "grime": 0.6, "saturation": 0.3, "scale": 0.16})
@onready var WALL := Look.surface("concrete", {"tint": Color(0.45, 0.4, 0.38), "grime": 0.8, "scale": 0.12})
@onready var COVER_METAL := Look.surface("metal", {"tint": Color(0.7, 0.42, 0.28), "scale": 0.45})
@onready var COVER_CONCRETE := Look.surface("concrete", {"tint": Color(0.8, 0.74, 0.68), "grime": 0.9, "scale": 0.5})
@onready var HULL := Look.surface("metal", {"tint": Color(0.62, 0.58, 0.55), "grime": 0.8, "scale": 0.3})
@onready var HULL_RUST := Look.surface("metal", {"tint": Color(0.8, 0.45, 0.3), "grime": 0.9, "scale": 0.35})


func _ready() -> void:
	_rng.seed = LAYOUT_SEED
	_noise.seed = LAYOUT_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_plan()
	_build_ground()
	_build_sites()
	_build_spawns()
	_build_field()
	_mark_zones()
	_art_rng.seed = LAYOUT_SEED
	_dress()
	set_process(Look.enabled)


func bake_navigation() -> void:
	if not _shared.has("navmesh"):
		var navmesh := NavigationMesh.new()
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		navmesh.geometry_collision_mask = Actor.LAYER_WORLD
		# Coarser than a street map needs: the ground is open and this keeps
		# the bake of a field this size to a moment.
		navmesh.cell_size = 0.5
		navmesh.cell_height = 0.25
		navmesh.agent_radius = 0.5
		navmesh.agent_height = 1.75
		navmesh.agent_max_climb = 0.5
		navmesh.agent_max_slope = 42.0
		nav_region.navigation_mesh = navmesh
		nav_region.bake_navigation_mesh(false)
		_shared["navmesh"] = navmesh
	nav_region.navigation_mesh = _shared["navmesh"]


## The height of the ground at a point on the map.
func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func _process(_delta: float) -> void:
	# The embers drift around whoever is looking, not over the whole field.
	var camera := get_viewport().get_camera_3d()
	if camera != null and is_instance_valid(_weather):
		_weather.global_position = Vector3(camera.global_position.x, camera.global_position.y + 6.0,
				camera.global_position.z)
	# The beacon breathes, slowly, like a warning light.
	if is_instance_valid(_beacon_light):
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0021)
		_beacon_light.light_energy = 2.0 + 6.0 * pulse
		_beacon.scale = Vector3.ONE * (0.85 + 0.3 * pulse)


func _build_environment() -> void:
	# A scorched plain under smoke: low orange sun, haze only toward the
	# horizon. Depth fog (fog_density here is how opaque the far end gets,
	# not an exponential haze) leaves engagement range clear.
	Look.atmosphere(self, {
		"sky_tint": Color(0.82, 0.6, 0.48),
		"sky_saturation": 0.3,
		"sky_energy": 0.75,
		"sky_rotation": 0.2,
		"fog_color": Color(0.36, 0.27, 0.22),
		"fog_density": 0.62,
		"fog_depth_begin": 64.0,
		"fog_depth_end": 360.0,
		"fog_depth_curve": 1.3,
		"fog_height": 1.1,
		"fog_height_density": 0.05,
		"haze_height": 0.28,
		"sun_scatter": 0.35,
		"sun_color": Color(1.0, 0.74, 0.52),
		"sun_energy": 1.9,
		"sun_angles": Vector3(-30, 38, 0),
		"ambient_color": Color(0.42, 0.43, 0.5),
		"ambient_energy": 1.3,
		"saturation": 0.85,
		"contrast": 1.12,
	}, {
		# All-out war: the horizon closes in and the sun goes dull red, but
		# fog does not start inside 28 m and is not solid before 120 m, so a
		# fight at 30–50 m stays readable. Look.soften_storm enforces that
		# floor even if these numbers are pushed. The column of smoke is
		# overhead, not a wall at eye level.
		"sky_tint": Color(0.55, 0.3, 0.24),
		"sky_saturation": 0.45,
		"sky_energy": 0.62,
		"fog_color": Color(0.5, 0.34, 0.24),
		"fog_density": 0.86,
		"fog_depth_begin": 28.0,
		"fog_depth_end": 120.0,
		"fog_depth_curve": 1.0,
		"fog_height": 1.1,
		"fog_height_density": 0.12,
		"haze_height": 0.4,
		"sun_color": Color(1.0, 0.58, 0.4),
		"sun_energy": 1.55,
		"ambient_color": Color(0.46, 0.4, 0.4),
		"ambient_energy": 1.35,
		"saturation": 0.78,
		"contrast": 1.12,
		"glow": 0.8,
	})
	Look.weather(self, "embers", 45.0)
	_weather = get_node_or_null("Weather")


# --- Layout ---------------------------------------------------------------------

## Decides where everything goes, in the flat, before there is any ground.
func _plan() -> void:
	for site: Dictionary in SITES:
		var at: Vector2 = site["at"]
		_pads.append({"at": at, "radius": site["radius"], "height": _rolling(at.x, at.y) + site["lift"]})
	for i in PLAYER_SPAWNS:
		var at := Vector2.from_angle(TAU * (i + 0.5) / PLAYER_SPAWNS) * SPAWN_RING
		_pads.append({"at": at, "radius": 9.0, "height": _rolling(at.x, at.y)})
	for army: String in ARMIES:
		var muster: Vector2 = ARMIES[army]["muster"]
		_pads.append({"at": muster, "radius": 13.0, "height": _rolling(muster.x, muster.y)})
	for at: Vector2 in RAMP_SPOTS:
		_pads.append({"at": at, "radius": 10.0, "height": _rolling(at.x, at.y)})
	_trenches = [
		# The Breach: two lines facing the middle, and a communication trench.
		PackedVector2Array([Vector2(-180, 96), Vector2(-132, 92), Vector2(-96, 110), Vector2(-88, 150)]),
		PackedVector2Array([Vector2(-196, 82), Vector2(-150, 70), Vector2(-104, 78)]),
		PackedVector2Array([Vector2(-132, 92), Vector2(-126, 118)]),
		# The old front across the middle of the field.
		PackedVector2Array([Vector2(-70, -64), Vector2(-20, -78), Vector2(34, -70), Vector2(84, -86)]),
		PackedVector2Array([Vector2(-84, 62), Vector2(-30, 74), Vector2(26, 66), Vector2(70, 80)]),
		PackedVector2Array([Vector2(96, -30), Vector2(110, 20), Vector2(100, 62)]),
	]
	for i in CRATERS:
		var radius := _rng.randf_range(6.0, 15.0)
		var at := _free_spot(radius, false)
		_craters.append({"at": at, "radius": radius, "depth": radius * _rng.randf_range(0.16, 0.26)})


## A random point on the field that is clear of every pad (and, when
## `reserve` is true, becomes one itself so nothing else lands on it).
func _free_spot(radius: float, reserve := true, flat := false) -> Vector2:
	var at := Vector2.ZERO
	for attempt in 40:
		at = Vector2(_rng.randf_range(-FIELD + 20.0, FIELD - 20.0), _rng.randf_range(-FIELD + 20.0, FIELD - 20.0))
		var clear := true
		for pad in _pads:
			if at.distance_to(pad["at"]) < float(pad["radius"]) * 1.5 + radius:
				clear = false
				break
		if clear:
			break
	if reserve:
		_pads.append({"at": at, "radius": radius, "height": _rolling(at.x, at.y), "soft": not flat})
	return at


## The lie of the land before anything is dug or levelled.
func _rolling(x: float, z: float) -> float:
	return _noise.get_noise_2d(x, z) * 9.0


func _build_ground() -> void:
	terrain = Terrain.new()
	terrain.name = "Ground"
	terrain.cell = CELL
	terrain.side = SIDE
	if not _shared.has("heights"):
		_shape_ground()
		_shared["heights"] = terrain.heights
		_shared["collision"] = terrain.collision_data()
	terrain.heights = _shared["heights"]
	terrain.build(GROUND, _shared["collision"])
	nav_region.add_child(terrain)
	# The rim is too steep to climb, and these stop anyone flying over it.
	var edge := terrain.extent() * 0.5 - 6.0
	for side: Vector3 in [Vector3(0, 0, -edge), Vector3(0, 0, edge), Vector3(-edge, 0, 0), Vector3(edge, 0, 0)]:
		var wall := StaticBody3D.new()
		wall.collision_layer = Actor.LAYER_WORLD
		wall.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(edge * 2.0 + 2.0, 600.0, 2.0) if side.x == 0.0 else Vector3(2.0, 600.0, edge * 2.0 + 2.0)
		var col := CollisionShape3D.new()
		col.shape = shape
		wall.add_child(col)
		wall.position = side + Vector3(0, 250.0, 0)
		wall.add_to_group("map_edge")
		add_child(wall)


func _shape_ground() -> void:
	var heights := PackedFloat32Array()
	heights.resize(SIDE * SIDE)
	var half := (SIDE - 1) * CELL * 0.5
	for iz in SIDE:
		for ix in SIDE:
			var x := ix * CELL - half
			var z := iz * CELL - half
			var h := _rolling(x, z) + _noise.get_noise_2d(x * 6.0 + 400.0, z * 6.0) * 1.1
			var out := maxf(absf(x), absf(z))
			h += smoothstep(FIELD, half, out) * RIM_HEIGHT
			heights[iz * SIDE + ix] = h
	terrain.heights = heights
	for crater in _craters:
		_stamp(crater["at"], float(crater["radius"]) * 1.5, func(h: float, d: float) -> float:
			var r: float = crater["radius"]
			var t := d / r
			if t < 1.0:
				return h - float(crater["depth"]) * (1.0 - t * t)
			# The thrown-up lip.
			return h + float(crater["depth"]) * 0.25 * (1.0 - smoothstep(1.0, 1.5, t)))
	for line in _trenches:
		for i in line.size() - 1:
			_stamp_trench(line[i], line[i + 1])
	for pad in _pads:
		if pad.get("soft", false):
			continue
		var radius: float = pad["radius"]
		_stamp(pad["at"], radius * 1.9, func(h: float, d: float) -> float:
			return lerpf(float(pad["height"]), h, smoothstep(radius, radius * 1.9, d)))


## Runs `change(height, distance)` over every ground sample within `reach` of `at`.
func _stamp(at: Vector2, reach: float, change: Callable) -> void:
	var half := (SIDE - 1) * CELL * 0.5
	var x0 := maxi(int((at.x - reach + half) / CELL), 0)
	var x1 := mini(int((at.x + reach + half) / CELL) + 1, SIDE - 1)
	var z0 := maxi(int((at.y - reach + half) / CELL), 0)
	var z1 := mini(int((at.y + reach + half) / CELL) + 1, SIDE - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var d := Vector2(ix * CELL - half, iz * CELL - half).distance_to(at)
			if d <= reach:
				terrain.heights[iz * SIDE + ix] = change.call(terrain.heights[iz * SIDE + ix], d)


## A trench between two points: deep enough to hide in, with sides a soldier
## can still walk up.
func _stamp_trench(a: Vector2, b: Vector2) -> void:
	var half := (SIDE - 1) * CELL * 0.5
	var reach := 6.0
	var x0 := maxi(int((minf(a.x, b.x) - reach + half) / CELL), 0)
	var x1 := mini(int((maxf(a.x, b.x) + reach + half) / CELL) + 1, SIDE - 1)
	var z0 := maxi(int((minf(a.y, b.y) - reach + half) / CELL), 0)
	var z1 := mini(int((maxf(a.y, b.y) + reach + half) / CELL) + 1, SIDE - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var p := Vector2(ix * CELL - half, iz * CELL - half)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			if d < reach:
				var i := iz * SIDE + ix
				var dug := _rolling(p.x, p.y) - 1.9 * (1.0 - smoothstep(1.5, 4.5, d)) \
						+ 0.5 * smoothstep(4.5, 5.0, d) * (1.0 - smoothstep(5.0, 6.0, d))
				terrain.heights[i] = minf(terrain.heights[i], dug) if d < 4.5 else maxf(terrain.heights[i], dug)


func _ground(at: Vector2) -> Vector3:
	return terrain.on_ground(at.x, at.y)


# --- Landmarks --------------------------------------------------------------------

func _build_sites() -> void:
	for site: Dictionary in SITES:
		var at: Vector2 = site["at"]
		var radius: float = site["radius"]
		var centre := _ground(at)
		var marker := _add_marker("strongpoint", centre)
		marker.set_meta("name", site["name"])
		marker.set_meta("radius", radius)
		match site["kind"]:
			"foundry":
				_build_foundry(at)
			"hill":
				_build_hill(at)
			"graveyard":
				_build_graveyard(at)
			"breach":
				_build_breach(at)
			"carrier":
				_build_carrier(at)
		# The depot sits on the side facing the middle of the map, or north at the middle.
		var inward := -at.normalized() if at.length() > 1.0 else Vector2(0, -1)
		_add_depot(_open(at + inward * (radius - 10.0), 6.0))
		# The army that starts here, its garrison, and a bike for whoever takes the place.
		var army: String = site["army"]
		if army != "":
			marker.set_meta("holder", army)
			marker.set_meta("holder_name", ARMIES[army]["holder_name"])
			for i in 4:
				var post := _add_marker("spawn_bot", _open(at + Vector2.from_angle(TAU * i / 4.0 + 0.6) * radius * 0.45))
				post.set_meta("faction", army)
		var bike := _add_marker("spawn_vehicle", _open(at - inward.orthogonal() * (radius - 6.0), 2.0))
		bike.rotation.y = atan2(-inward.x, -inward.y)


## The middle of the map: the shells of a works, tall enough that the best
## loot sits on roofs only a flight rig reaches.
func _build_foundry(at: Vector2) -> void:
	var lots := [Vector2(-16, -12), Vector2(14, -16), Vector2(-18, 14), Vector2(16, 12), Vector2(0, 26)]
	for i in lots.size():
		var h: float = [16.0, 10.0, 10.0, 6.0, 6.0][i]
		_add_building(at + lots[i], Vector3(_rng.randf_range(8.0, 11.0), h, _rng.randf_range(8.0, 11.0)), true)
	# The Forge: the spire everything on the field points at, and a landmark
	# you can steer by from anywhere. Solid all the way up.
	_build_forge(at + FORGE_AT)
	# The stack it replaced drew one number; keep drawing it so the rest of
	# the layout stays where it was.
	_rng.randf()
	for offset: Vector2 in [Vector2(-4, 4), Vector2(18, -30), Vector2(28, -2), Vector2(-30, 0)]:
		_add_cover(_ground(at + offset))
		_add_marker("spawn_cache", _open(at + offset + Vector2(2.5, 1.5)))


func _build_forge(at: Vector2) -> void:
	var base := _ground(at)
	var dark := Look.surface("metal", {"tint": Color(0.5, 0.45, 0.42), "grime": 1.0, "scale": 0.12})
	var y := -1.0
	for tier: Vector2 in FORGE_TIERS:
		var height := tier.y + (1.0 if y < 0.0 else 0.0)
		_box(Vector3(tier.x, height, tier.x), base + Vector3(0, y + height * 0.5, 0), dark if y > 0.0 else WALL)
		y += height
	# Four buttresses on the plinth's corners, standing proud of the tower.
	var corner := FORGE_TIERS[0].x * 0.5 - FORGE_BUTTRESS.x * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(FORGE_BUTTRESS.x, FORGE_BUTTRESS.y, FORGE_BUTTRESS.x),
					base + Vector3(sx * corner, FORGE_BUTTRESS.y * 0.5 - 1.0, sz * corner), dark)
	_buildings.append({"center": base, "size": Vector3(FORGE_TIERS[0].x, y, FORGE_TIERS[0].x), "landmark": true})


## A hill with a relay station on top. Whoever holds it sees half the field.
func _build_hill(at: Vector2) -> void:
	_add_building(at + Vector2(-6, -4), Vector3(8.0, 4.0, 6.0), true)
	_add_building(at + Vector2(8, 6), Vector3(5.0, 3.0, 5.0), false)
	# The mast.
	_add_building(at + Vector2(7, -9), Vector3(1.6, 26.0, 1.6), false)
	for i in 5:
		var spot := at + Vector2.from_angle(TAU * i / 5.0 + 0.3) * 19.0
		_add_wall(_ground(spot), Vector3(6.0, 1.3, 1.0), -Vector2.from_angle(TAU * i / 5.0 + 0.3).angle() + PI * 0.5)
	_add_marker("spawn_cache", _open(at + Vector2(-1, 5)))
	_add_marker("spawn_cache", _open(at + Vector2(12, -2)))


## Where a column of war machines was caught in the open.
func _build_graveyard(at: Vector2) -> void:
	for i in 7:
		var spot := at + Vector2.from_angle(TAU * i / 7.0 + 0.2) * _rng.randf_range(8.0, 26.0)
		_add_wreck(spot, i % 3, _rng.randf_range(0.0, TAU), 1.0 + 0.5 * float(i == 0))
	_add_marker("spawn_cache", _open(at + Vector2(3, 2)))
	_add_marker("spawn_cache", _open(at + Vector2(-14, 10)))
	_add_marker("spawn_cache", _open(at + Vector2(12, -16)))


## A fortified line with a hole blown through it.
func _build_breach(at: Vector2) -> void:
	for i in 7:
		if i == 3:
			continue
		var spot := at + Vector2((i - 3) * 9.0, -22.0 + absf(i - 3) * 2.0)
		_add_wall(_ground(spot), Vector3(8.0, 4.5, 1.6), 0.0)
	_add_building(at + Vector2(-14, 2), Vector3(7.0, 3.0, 6.0), true)
	_add_building(at + Vector2(15, 6), Vector3(6.0, 6.0, 6.0), true)
	for offset: Vector2 in [Vector2(-2, -12), Vector2(4, 14)]:
		_add_cover(_ground(at + offset))
		_add_marker("spawn_cache", _open(at + offset + Vector2(2.0, 2.0)))


## The broken hull of something that fell out of the sky. Its upper decks
## count as rooftops.
func _build_carrier(at: Vector2) -> void:
	var yaw := 0.5
	var along := Vector2(sin(yaw), cos(yaw))
	for i in 3:
		# The hull lies along one side of the site, leaving the middle open.
		var spot := at + along * (i - 1) * 21.0 + along.orthogonal() * ((i - 1) * 3.0 - 15.0)
		var size := Vector3(14.0, [10.0, 15.0, 8.0][i], 19.0)
		var base := _ground(spot)
		var body := _box(size, base + Vector3(0, size.y * 0.5 - 1.0, 0), HULL)
		body.rotation = Vector3(0.05 * (i - 1), yaw, 0.08 * (1 - i))
		_wrecks.append({"at": base, "size": size, "burning": i == 1})
		_buildings.append({"center": base, "size": Vector3(18.0, size.y, 21.0), "wreck": true})
		var deck := _add_marker("spawn_cache", base + Vector3(0, size.y - 0.3, 0))
		deck.set_meta("loot_source", "rooftop")
	# The tail fin still stands over the wreck.
	var fin := _box(Vector3(1.6, 22.0, 9.0), _ground(at + along * 27.0 - along.orthogonal() * 15.0) + Vector3(0, 13.0, 0), HULL_RUST)
	fin.rotation = Vector3(-0.3, yaw, 0.1)
	# A wing, torn off and dug into the ground: a ramp onto the hull.
	var wing := _box(Vector3(7.0, 0.6, 20.0), _ground(at - along.orthogonal() * 30.0) + Vector3(0, 2.6, 0), HULL_RUST)
	wing.rotation = Vector3(0.28, yaw + PI * 0.5, 0.0)
	_add_marker("spawn_cache", _open(at + along.orthogonal() * 12.0))
	_add_cover(_ground(at + along.orthogonal() * 14.0 + along * 6.0))


# --- The rim and the open field ---------------------------------------------------

func _build_spawns() -> void:
	var gates := {}
	for gate: Dictionary in OUTPOSTS:
		gates[gate["spawn"]] = gate["name"]
	for i in PLAYER_SPAWNS:
		var dir := Vector2.from_angle(TAU * (i + 0.5) / PLAYER_SPAWNS)
		var at := dir * SPAWN_RING
		if gates.has(i):
			_build_outpost(at, dir, gates[i])
		else:
			# The other drop points are open ground: a low wall to land behind.
			_add_wall(_ground(at - dir * 6.0), Vector3(6.0, 1.4, 1.0), -dir.angle() + PI * 0.5)
		# At every other drop point a bike.
		if i % 2 == 0:
			var bike := _add_marker("spawn_vehicle", _ground(at + dir.orthogonal() * 7.0))
			bike.rotation.y = atan2(dir.x, dir.y)


## A gate outpost: a walled yard open toward the middle (the gate), with a
## depot at the back and the players' arrival spots. The Raid makes it safe
## from the "outpost" marker.
func _build_outpost(at: Vector2, dir: Vector2, title: String) -> void:
	var marker := _add_marker("outpost", _ground(at))
	marker.set_meta("name", title)
	marker.set_meta("radius", OUTPOST_RADIUS)
	var segments := 12
	for k in segments:
		var angle := TAU * (k + 0.5) / segments
		var out := Vector2.from_angle(angle)
		# Leave the side facing the middle open: that is the gate.
		if out.dot(-dir) > 0.8:
			continue
		var spot := at + out * (OUTPOST_RADIUS + 0.6)
		_add_wall(_ground(spot), Vector3(7.2, 2.4, 0.8), -angle + PI * 0.5)
	# The gate posts either side of the opening.
	for side: float in [-1.0, 1.0]:
		var post := at - dir * (OUTPOST_RADIUS + 0.6) + dir.orthogonal() * side * 4.6
		var base := _ground(post)
		_box(Vector3(1.0, 7.0, 1.0), base + Vector3(0, 3.0, 0), COVER_CONCRETE)
	_add_depot(_ground(at + dir * 7.0))
	for spot: Vector2 in [at + dir.orthogonal() * 4.0, at - dir.orthogonal() * 4.0, at - dir * 3.0]:
		_add_marker("spawn_player", _ground(spot))


## Risk zones: caches pay by the zone they stand in (rooftops keep their own
## table), and a warlord holds the core.
func _mark_zones() -> void:
	for node in get_children():
		if not node.is_in_group("spawn_cache") or node.get_meta("loot_source", "cache") != "cache":
			continue
		var out := Vector2(node.position.x, node.position.z).length()
		if out <= CORE_RADIUS:
			node.set_meta("loot_source", "cache_core")
		elif out > MIDDLE_RADIUS:
			node.set_meta("loot_source", "cache_outer")
	var boss := _add_marker("spawn_boss", _open(Vector2(-6, 6), 2.0))
	boss.set_meta("radius", 30.0)
	# He serves neither army: both fight him for the Foundry.
	boss.set_meta("faction", "warlord")


func _build_field() -> void:
	for i in TITANS:
		_add_wreck(_free_spot(26.0), 3, _rng.randf_range(0.0, TAU), 1.0)
	for i in WRECKS:
		var big := _rng.randf_range(0.9, 2.2)
		var at := _free_spot(7.0 * big)
		_add_wreck(at, _rng.randi() % 3, _rng.randf_range(0.0, TAU), big)
	for i in COVER_LOTS:
		var at := _free_spot(6.0)
		_add_cover(_ground(at))
		if i % 3 == 0:
			_add_marker("spawn_cache", _open(at + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))))
	# Patrols start on their own army's half of the field.
	for i in FIELD_PATROLS:
		var army := "legion" if i % 2 == 0 else "tide"
		var at := _free_spot(5.0)
		for attempt in 30:
			if (at.x < 0.0) == (army == "legion") and absf(at.x) > 30.0:
				break
			_pads.pop_back()
			at = _free_spot(5.0)
		_add_marker("spawn_bot", _open(at)).set_meta("faction", army)
	# Where each army's reinforcements arrive: a camp at the rim.
	for army: String in ARMIES:
		var muster: Vector2 = ARMIES[army]["muster"]
		var inward := -muster.normalized()
		for i in MUSTER_SPOTS:
			var spot := muster + inward.orthogonal() * (i % 3 - 1) * 5.0 + inward * (i / 3) * 5.0
			_add_marker("spawn_bot", _open(spot)).set_meta("faction", army)
		_add_wall(_ground(muster + inward * 13.0), Vector3(9.0, 1.4, 1.0), -inward.angle() + PI * 0.5)
		_add_cover(_ground(muster - inward * 7.0))
	for i in RAMP_SPOTS.size():
		_add_ramp_lot(_ground(RAMP_SPOTS[i]), i * PI * 0.5)
	_fortify_front()


func _add_building(at: Vector2, size: Vector3, lootable: bool) -> void:
	var base := _ground(at)
	var shade := _rng.randf_range(0.26, 0.4)
	var tint := Color(shade, shade * 0.92, shade * 0.88) * 2.4
	var kind := "brick" if size.y <= 6.0 and shade > 0.33 else "concrete"
	# Sunk a little, so no slope shows daylight under a wall.
	var body := _box(size + Vector3(0, 1.5, 0), base + Vector3(0, size.y * 0.5 - 0.75, 0),
			Look.surface(kind, {"tint": tint, "grime": 0.7}))
	Look.make_building(body.get_child(1), size, shade * 100.0)
	_buildings.append({"center": base, "size": size})
	if lootable and size.y >= 6.0:
		var marker := _add_marker("spawn_cache", base + Vector3(0, size.y, 0))
		marker.set_meta("loot_source", "rooftop")


## A length of wall, turned to `yaw`.
func _add_wall(base: Vector3, size: Vector3, yaw: float) -> void:
	var body := _box(size + Vector3(0, 1.0, 0), base + Vector3(0, size.y * 0.5 - 0.5, 0), COVER_CONCRETE)
	body.rotation.y = yaw


## A barricade facing the middle of the map: a short bowed line of jersey
## barriers, sandbag walls and steel plates, so a cover lot reads as a
## position someone held, not boxes dropped at random.
func _add_cover(center: Vector3) -> void:
	var flat := Vector2(center.x, center.z)
	var inward := -flat.normalized() if flat.length() > 1.0 else Vector2(0, -1)
	var along := inward.orthogonal()
	var yaw := atan2(along.x, along.y)
	var count := _rng.randi_range(2, 4)
	for i in count:
		# The draws a lot has always made, so the layout after it stays put.
		var rolled := Vector3(_rng.randf_range(1.2, 3.0), _rng.randf_range(1.0, 1.6), _rng.randf_range(1.2, 3.0))
		var jitter := Vector2(_rng.randf_range(-4.5, 4.5), _rng.randf_range(-4.5, 4.5))
		var slot := i - (count - 1) * 0.5
		var spot := flat + along * (slot * 3.3 + jitter.x * 0.1) - inward * (absf(slot) * 0.8 + jitter.y * 0.08)
		var base := terrain.on_ground(spot.x, spot.y)
		var piece: Dictionary = COVER_PIECES[(i + int(rolled.x * 10.0)) % COVER_PIECES.size()]
		var size: Vector3 = piece["size"]
		size.x = clampf(rolled.x + rolled.z, 2.6, 3.4) if piece["kind"] != "plate" else size.x
		var body := _box(size + Vector3(0, 0.8, 0), base + Vector3(0, size.y * 0.5 - 0.4, 0),
				COVER_CONCRETE if piece["kind"] == "jersey" else COVER_METAL)
		body.rotation.y = yaw
		body.set_meta("cover", piece["kind"])
		_cover_pieces.append(body)
		_cover_spots.append(terrain.on_ground(spot.x - inward.x * 1.2, spot.y - inward.y * 1.2))


## The wreck of a war machine: a tank, a fallen strider, a crashed dropship or
## a titan. Each sits the way it came to rest, not tumbled at random; plain
## boxes that stop bullets, and the dressing adds the rest.
func _add_wreck(at: Vector2, kind: int, yaw: float, big: float) -> void:
	var base := _ground(at)
	var turn := Basis(Vector3.UP, yaw)
	var size := Vector3.ZERO
	match kind:
		0:
			# Tank: a low hull on its tracks, the turret knocked round and the
			# barrel drooping.
			size = Vector3(4.4, 2.0, 8.0) * big
			var settle := Vector2(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.1, 0.1)) * 0.3
			var hull := _box(size, base + Vector3(0, size.y * 0.5 - 0.2, 0), HULL)
			hull.rotation = Vector3(settle.x, yaw, settle.y)
			for side: float in [-1.0, 1.0]:
				var track := _box(Vector3(0.9, 1.3, 8.6) * big, base + turn * Vector3(side * (size.x * 0.5 + 0.35 * big), 0.45 * big, 0), HULL_RUST)
				track.rotation = Vector3(settle.x, yaw, settle.y)
			var turret := _box(Vector3(2.8, 1.2, 3.2) * big, base + turn * Vector3(0.0, size.y + 0.3 * big, 0.6 * big), HULL)
			turret.rotation.y = yaw + 0.6
			var barrel := _box(Vector3(0.45, 0.45, 5.0) * big, base + turn * Vector3(1.4 * big, size.y + 0.1 * big, -2.6 * big), HULL)
			barrel.rotation = Vector3(-0.1, yaw + 0.6, 0.0)
		1:
			# Strider: the cockpit on its side, one leg folded up at the knee,
			# the other lying out straight.
			size = Vector3(5.0, 3.6, 6.0) * big
			var body := _box(size, base + Vector3(0, size.y * 0.5 - 0.8, 0), HULL_RUST)
			body.rotation = Vector3(0.0, yaw, 0.38)
			var thigh := _box(Vector3(1.3, 6.0, 1.3) * big, base + turn * Vector3(-3.4, 3.4, 0.6) * big, HULL)
			thigh.rotation = Vector3(0.0, yaw, -0.5)
			var shin := _box(Vector3(1.1, 6.5, 1.1) * big, base + turn * Vector3(-7.4, 4.0, 0.6) * big, HULL)
			shin.rotation = Vector3(0.0, yaw, 0.55)
			var fallen := _box(Vector3(1.1, 1.1, 10.0) * big, base + turn * Vector3(4.4, 0.3, -2.0), HULL)
			fallen.rotation = Vector3(0.0, yaw + 0.5, 0.0)
		3:
			# Titan: a walker the height of a tower block, face down, with
			# two legs still standing where it stopped.
			size = Vector3(15.0, 9.0, 24.0)
			var torso := _box(size, base + Vector3(0, size.y * 0.5 - 1.5, 0), HULL)
			torso.rotation = Vector3(0.1, yaw, -0.07)
			var head := _box(Vector3(7.0, 6.0, 8.0), base + turn * Vector3(1.0, 2.0, -15.5), HULL_RUST)
			head.rotation = Vector3(0.35, yaw + 0.2, 0.1)
			for leg_side: float in [-1.0, 1.0]:
				var shin := _box(Vector3(3.2, 30.0, 3.2), base + turn * Vector3(leg_side * 9.0, 12.0, 19.0 + leg_side * 3.0), HULL)
				shin.rotation = Vector3(0.22 * leg_side, yaw, 0.16 * leg_side)
			var arm := _box(Vector3(2.6, 2.6, 19.0), base + turn * Vector3(-13.0, 0.8, -6.0), HULL_RUST)
			arm.rotation = Vector3(0.05, yaw - 0.5, 0.0)
			var back := _add_marker("spawn_cache", base + Vector3(0, size.y - 0.9, 0))
			back.set_meta("loot_source", "rooftop")
		_:
			# Dropship: came in low, nose first, broke its back on landing and
			# left a furrow behind it.
			size = Vector3(3.6, 3.2, 12.0) * big
			var front := _box(Vector3(size.x, size.y, size.z * 0.55), base + turn * Vector3(0, size.y * 0.5 - 0.9, -size.z * 0.24), HULL)
			front.rotation = Vector3(0.16, yaw, 0.0)
			var back := _box(Vector3(size.x * 0.95, size.y * 0.9, size.z * 0.45), base + turn * Vector3(0.3, size.y * 0.45 - 0.2, size.z * 0.28), HULL_RUST)
			back.rotation = Vector3(-0.05, yaw + 0.12, 0.0)
			for side: float in [-1.0, 1.0]:
				# One wing still on, the other snapped and lying in the dirt.
				var wing := _box(Vector3(4.2, 0.45, 2.8) * big,
						base + turn * Vector3(side * (size.x * 0.5 + 2.0 * big), size.y * 0.5 if side > 0.0 else 0.3, size.z * 0.12), HULL)
				wing.rotation = Vector3(0.0, yaw, -0.12 * side if side > 0.0 else 0.08)
			var fin := _box(Vector3(0.4, 2.6, 2.6) * big, base + turn * Vector3(0.3, size.y + 0.6 * big, size.z * 0.42), HULL_RUST)
			fin.rotation = Vector3(-0.05, yaw + 0.12, 0.0)
	_wrecks.append({"at": base, "size": size, "burning": _rng.randf() < 0.4, "kind": kind, "yaw": yaw, "big": big})
	_cover_spots.append(_ground(at + Vector2.from_angle(yaw) * (size.x * 0.5 + 2.0)))


## The front lines, dug in: sandbag walls along the lips of the trenches
## facing no man's land, with gaps to climb out through, and a row of tank
## traps out in front. Placed along the trench lines, not drawn at random,
## and kept clear of every marker and solid already down.
func _fortify_front() -> void:
	var keep_clear: Array[Vector2] = []
	for node in get_children():
		if node is Marker3D or node is Depot:
			keep_clear.append(Vector2(node.position.x, node.position.z))
	var clear := func(spot: Vector2, room: float) -> bool:
		for site: Dictionary in SITES:
			if spot.distance_to(site["at"]) < float(site["radius"]) * 0.8:
				return false
		for pad in _pads:
			if not pad.get("soft", false) and spot.distance_to(pad["at"]) < float(pad["radius"]) + room:
				return false
		for mark in keep_clear:
			if spot.distance_to(mark) < room + 2.5:
				return false
		for solid in _solids:
			if spot.distance_to(solid["at"]) < float(solid["reach"]) + room:
				return false
		return true
	for index: int in FRONT_LINES:
		var line: PackedVector2Array = _trenches[index]
		var walked := SANDBAG_EVERY * 0.5
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var along := (b - a).normalized()
			var out := along.orthogonal()
			if out.dot(-(a + b) * 0.5) < 0.0:
				out = -out
			var length := a.distance_to(b)
			var yaw := atan2(along.x, along.y)
			# Sandbags on the lip toward the enemy.
			var d := walked
			while d < length:
				var spot := a + along * d + out * 5.2
				if clear.call(spot, 1.8):
					var base := terrain.on_ground(spot.x, spot.y)
					var wall := _box(Vector3(3.4, 1.0 + 0.6, 0.9), base + Vector3(0, 0.5 - 0.3, 0), WALL)
					wall.rotation.y = yaw
					wall.set_meta("cover", "sandbag")
					_cover_pieces.append(wall)
				d += SANDBAG_EVERY
			walked = d - length
			# Tank traps out in front, every third one left out for a lane.
			var k := 0
			var t := TRAP_EVERY * 0.5
			while t < length:
				var spot := a + along * t + out * TRAP_OFFSET
				if k % 3 != 2 and clear.call(spot, 1.2):
					var base := terrain.on_ground(spot.x, spot.y)
					var trap := _box(Vector3(1.5, 1.2, 1.5), base + Vector3(0, 0.5, 0), HULL)
					trap.rotation.y = yaw + 0.4 * k
					trap.set_meta("cover", "trap")
					_cover_pieces.append(trap)
				k += 1
				t += TRAP_EVERY


## A jump ramp facing `yaw`, with a bike marker parked off to one side.
func _add_ramp_lot(center: Vector3, yaw: float) -> void:
	var angle := deg_to_rad(RAMP_ANGLE_DEG)
	var thickness := 0.4
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	# Sit the low end flush with the ground; the high end lifts toward -Z.
	body.position = center + Vector3(0, RAMP_LENGTH * 0.5 * sin(angle) - thickness * 0.5 * cos(angle), 0)
	body.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, angle)
	var size := Vector3(4.0, thickness, RAMP_LENGTH)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = Look.surface("metal", {"tint": Color(0.75, 0.55, 0.3), "scale": 0.5})
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	nav_region.add_child(body)
	# Parked back from the low end and to the side, pointing up the ramp.
	var spot := center + Basis(Vector3.UP, yaw) * Vector3(3.5, 0, 5.0)
	var marker := _add_marker("spawn_vehicle", terrain.on_ground(spot.x, spot.z))
	marker.rotation.y = yaw


func _add_depot(at: Vector3) -> void:
	var zone := Depot.new()
	zone.add_to_group("depot")
	zone.position = at + Vector3(0, 2.0, 0)
	add_child(zone)


func _add_marker(group: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.add_to_group(group)
	marker.position = at
	add_child(marker)
	return marker


func _box(size: Vector3, at: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	nav_region.add_child(body)
	_solids.append({"at": Vector2(at.x, at.z), "reach": Vector2(size.x, size.z).length() * 0.5})
	return body


## The ground at the open spot nearest to `at`: clear of every wall and wreck
## built so far, with `room` metres to spare.
func _open(at: Vector2, room := 1.2) -> Vector3:
	for ring in 12:
		for step in maxi(ring * 6, 1):
			var spot := at + Vector2.from_angle(TAU * step / maxf(ring * 6.0, 1.0)) * ring * 1.5
			var clear := true
			for solid in _solids:
				if spot.distance_to(solid["at"]) < float(solid["reach"]) + room:
					clear = false
					break
			if clear:
				return _ground(spot)
	return _ground(at)


# --- Dressing ---------------------------------------------------------------------

## Everything below is decoration: no collision, nothing the game depends on.
func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	_dress_rooftops(art)
	_dress_field(art)
	_dress_fires(art)
	_dress_core(art)
	_dress_forge(art)
	_dress_wrecks(art)
	_dress_cover(art)
	_dress_cracks(art)
	_dress_outposts(art)
	_dress_horizon(art)


func _dress_rooftops(art: Node3D) -> void:
	for b in _buildings:
		if b.get("wreck", false) or b.get("landmark", false):
			continue
		var size: Vector3 = b["size"]
		var top: Vector3 = b["center"] + Vector3(0, size.y, 0)
		if size.x < 4.0:
			continue
		for i in _art_rng.randi_range(1, 3):
			var file: String = ["AC.glb", "AC_Side.glb", "AC_Stacked.glb", "Antenna_1.glb", "Antenna_2.glb", "Tank.glb"][_art_rng.randi() % 6]
			var p := Look.prop(file, 3.2 if file == "Antenna_1.glb" else 1.5)
			p.position = top + Vector3(_art_rng.randf_range(-0.35, 0.35) * size.x, 0, _art_rng.randf_range(-0.35, 0.35) * size.z)
			p.rotation.y = _art_rng.randi() % 4 * PI / 2.0
			art.add_child(p)
		# A parapet so roofs do not end in a knife edge.
		var rim := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x + 0.3, 0.35, size.z + 0.3)
		mesh.material = WALL
		rim.mesh = mesh
		rim.position = top + Vector3(0, -0.1, 0)
		art.add_child(rim)


## Litter of a long war, left where people were: kit behind the cover they
## held, tents at each army's muster, and guns dug in behind the sandbags.
func _dress_field(art: Node3D) -> void:
	var litter := ["GasCan.glb", "PropaneTank.glb", "Trashcan.glb", "Backpack.glb", "Computer.glb", "Support.glb"]
	for spot in _cover_spots:
		if _art_rng.randf() < 0.5:
			continue
		var file: String = litter[_art_rng.randi() % litter.size()]
		var p := Look.prop(file, _art_rng.randf_range(0.5, 0.9), 0.9)
		p.position = spot
		p.rotation.y = _art_rng.randf() * TAU
		art.add_child(p)
	for army: String in ARMIES:
		var muster: Vector2 = ARMIES[army]["muster"]
		var inward := -muster.normalized()
		for i in 3:
			var spot := muster - inward * 9.0 + inward.orthogonal() * (i - 1) * 7.0
			var tent := Look.prop("Tent.glb", 4.5, 1.0)
			tent.position = _ground(spot) + Vector3(0, -0.1, 0)
			tent.rotation.y = atan2(inward.x, inward.y)
			art.add_child(tent)
	var count := 0
	for piece in _cover_pieces:
		if piece.get_meta("cover", "") != "sandbag":
			continue
		count += 1
		if count % 4 != 0:
			continue
		# The wall's face, turned to look over it toward the middle.
		var out := Basis(Vector3.UP, piece.rotation.y).x
		out = Vector3(-out.z, 0, out.x)
		if out.dot(-Vector3(piece.position.x, 0, piece.position.z)) < 0.0:
			out = -out
		var gun := Look.prop("Turret_Gun.glb", 2.2, 1.0)
		var spot := piece.position - out * 1.6
		gun.position = terrain.on_ground(spot.x, spot.z)
		gun.rotation.y = atan2(out.x, out.z)
		art.add_child(gun)


## The core reads as dangerous from across the field: molten slag pooled
## between the works, a red glow under the smoke and heat haze over it all.
## Decoration only; the burn itself is `hazard_at` in the world.
func _dress_core(art: Node3D) -> void:
	var slag := StandardMaterial3D.new()
	slag.albedo_color = Color(0.25, 0.06, 0.02)
	slag.emission_enabled = true
	slag.emission = Color(1.0, 0.36, 0.08)
	slag.emission_energy_multiplier = 2.6
	slag.roughness = 0.35
	for i in 16:
		var at := Vector2.from_angle(_art_rng.randf() * TAU) * _art_rng.randf_range(8.0, CORE_RADIUS - 6.0)
		if _under_building(at, 5.0):
			continue
		var pool := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		var width := _art_rng.randf_range(2.5, 5.5)
		disc.top_radius = width
		disc.bottom_radius = width
		disc.height = 0.1
		disc.material = slag
		pool.mesh = disc
		pool.scale = Vector3(1.0, 1.0, _art_rng.randf_range(0.5, 1.0))
		pool.rotation.y = _art_rng.randf() * TAU
		pool.position = _ground(at) + Vector3(0, 0.06, 0)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.add_child(pool)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.42, 0.15)
		glow.light_energy = 2.2
		glow.omni_range = width * 3.0
		glow.position = pool.position + Vector3(0, 1.2, 0)
		art.add_child(glow)
	for i in 4:
		var at := Vector2.from_angle(TAU * i / 4.0 + 0.4) * CORE_RADIUS * 0.6
		art.add_child(_smoke(_ground(at) + Vector3(0, 1.0, 0), 5.0))
	# The rim of the core: a line of glowing cracks you see before you cross it,
	# each laid on the ground where it lies.
	var scorch := StandardMaterial3D.new()
	scorch.albedo_color = Color(0.08, 0.04, 0.03)
	scorch.emission_enabled = true
	scorch.emission = Color(0.9, 0.24, 0.05)
	scorch.emission_energy_multiplier = 1.2
	var crack := BoxMesh.new()
	crack.size = Vector3(0.7, 0.12, 3.2)
	crack.material = scorch
	for k in 72:
		var angle := TAU * k / 72.0 + _art_rng.randf_range(-0.01, 0.01)
		var at := Vector2.from_angle(angle) * CORE_RADIUS
		if _blocked(at):
			continue
		var piece := MeshInstance3D.new()
		piece.mesh = crack
		piece.position = _ground(at) + Vector3(0, 0.02, 0)
		piece.rotation.y = -angle
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.add_child(piece)


## Gate outposts are lit in a calm green, with their name and rule on the gate.
func _dress_outposts(art: Node3D) -> void:
	for node in get_children():
		if not node.is_in_group("outpost"):
			continue
		var at := Vector2(node.position.x, node.position.z)
		var inward := -at.normalized()
		var gate := at + inward * (OUTPOST_RADIUS + 0.6)
		var plate := Label3D.new()
		plate.text = "%s\nSAFE ZONE · WEAPONS LOCKED" % str(node.get_meta("name", "Outpost")).to_upper()
		plate.font_size = 96
		plate.pixel_size = 0.01
		plate.modulate = Color(0.6, 1.0, 0.75)
		plate.outline_size = 16
		plate.position = _ground(gate) + Vector3(0, 8.6, 0)
		plate.rotation.y = atan2(inward.x, inward.y)
		art.add_child(plate)
		for side: float in [-1.0, 1.0]:
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(0.45, 1.0, 0.6)
			lamp.light_energy = 2.0
			lamp.omni_range = 14.0
			lamp.position = _ground(gate + inward.orthogonal() * side * 4.6) + Vector3(0, 6.8, 0)
			art.add_child(lamp)


## Whether a point is within `margin` metres of a building's footprint.
func _under_building(at: Vector2, margin: float) -> bool:
	for b in _buildings:
		var size: Vector3 = b["size"]
		var c: Vector3 = b["center"]
		if absf(at.x - c.x) < size.x * 0.5 + margin and absf(at.y - c.z) < size.z * 0.5 + margin:
			return true
	return false


## Some wrecks still burn: a fire, its light, and smoke that leans downwind.
func _dress_fires(art: Node3D) -> void:
	var lit := 0
	for wreck in _wrecks:
		if not wreck["burning"]:
			continue
		var size: Vector3 = wreck["size"]
		var at: Vector3 = wreck["at"] + Vector3(_art_rng.randf_range(-1.0, 1.0), size.y * 0.7, _art_rng.randf_range(-1.0, 1.0))
		art.add_child(_smoke(at, size.x * 0.35))
		var fire := Look.prop("Bonfire.glb", 1.6, 0.3)
		fire.position = at
		art.add_child(fire)
		if lit < 16:
			lit += 1
			var glow := Look.lamp(Color(1.0, 0.45, 0.15), 7.0, 22.0)
			glow.position = at + Vector3(0, 1.2, 0)
			art.add_child(glow)


func _smoke(at: Vector3, width: float) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.amount = 36
	smoke.lifetime = 14.0
	smoke.preprocess = 14.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = width
	mat.direction = Vector3(0.35, 1, 0.12)
	mat.spread = 10.0
	mat.gravity = Vector3(0.5, 0.15, 0.2)
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 4.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.9, 0.35, 0.1, 0.0))
	fade.add_point(0.06, Color(0.32, 0.14, 0.08, 0.6))
	fade.add_point(0.4, Color(0.09, 0.08, 0.08, 0.5))
	fade.set_color(fade.get_point_count() - 1, Color(0.06, 0.06, 0.06, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	mat.color_ramp = fade_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(13, 13)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = Look._soft_dot()
	quad.material = draw
	smoke.process_material = mat
	smoke.draw_pass_1 = quad
	smoke.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 90, 80))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = at
	return smoke


## True if a building or wreck covers `at`, or it is on a landmark.
func _blocked(at: Vector2) -> bool:
	for site: Dictionary in SITES:
		if at.distance_to(site["at"]) < float(site["radius"]):
			return true
	if _under_building(at, 1.0):
		return true
	for w in _wrecks:
		var c: Vector3 = w["at"]
		if at.distance_to(Vector2(c.x, c.z)) < 10.0:
			return true
	return false


## The Forge dressed: a teal band at the top of each tier, a furnace mouth
## glowing on every face of the plinth, molten metal pouring down two faces,
## smoke from its shoulders and the red beacon on the needle.
func _dress_forge(art: Node3D) -> void:
	var base := _ground(FORGE_AT)
	var y := -1.0
	var teal := Look.trim("teal")
	for tier: Vector2 in FORGE_TIERS:
		var height := tier.y + (1.0 if y < 0.0 else 0.0)
		y += height
		art.add_child(_slab(Vector3(tier.x + 0.2, 0.35, tier.x + 0.2), base + Vector3(0, y - 0.9, 0), teal))
	var plinth: Vector2 = FORGE_TIERS[0]
	var tower: Vector2 = FORGE_TIERS[1]
	# Ribs up the tower's faces, so it reads as built, not a plain block.
	var rib_y := plinth.y - 1.0
	for t in range(1, 3):
		var tier: Vector2 = FORGE_TIERS[t]
		for k in 4:
			var face := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
			for side: float in [-1.0, 1.0]:
				var rib := _slab(Vector3(0.7, tier.y, 0.5), base + face * (tier.x * 0.5 + 0.2)
						+ face.cross(Vector3.UP) * side * (tier.x * 0.5 - 0.9) + Vector3(0, rib_y + tier.y * 0.5, 0), WALL, true)
				rib.rotation.y = k * PI * 0.5
				art.add_child(rib)
		rib_y += tier.y
	art.add_child(_slab(Vector3(plinth.x + 0.12, 0.7, plinth.x + 0.12), base + Vector3(0, plinth.y - 1.6, 0), Look.trim("hazard")))
	for k in 4:
		var face := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
		var mouth := _slab(Vector3(2.6, 4.2, 0.2), base + face * (plinth.x * 0.5 + 0.05) + Vector3(0, 2.1, 0), Look.trim("orange"))
		mouth.rotation.y = k * PI * 0.5
		art.add_child(mouth)
		var glow := Look.lamp(Color(1.0, 0.45, 0.15), 4.0, 24.0)
		glow.position = base + face * (plinth.x * 0.5 + 3.0) + Vector3(0, 2.5, 0)
		art.add_child(glow)
		if k % 2 == 0:
			# The pour, beside the furnace mouth: down the tower, across the
			# plinth's roof and over its lip to the ground.
			var slag := Look.trim("slag")
			var aside := face.cross(Vector3.UP) * 2.2
			var parts := [
				[Vector3(1.5, tower.y - 4.0, 0.3), face * (tower.x * 0.5 + 0.1) + Vector3(0, plinth.y - 1.0 + (tower.y - 4.0) * 0.5, 0)],
				[Vector3(1.5, 0.25, (plinth.x - tower.x) * 0.5 + 0.3), face * ((plinth.x + tower.x) * 0.25 + 0.1) + Vector3(0, plinth.y - 0.85, 0)],
				[Vector3(1.6, plinth.y - 1.0, 0.3), face * (plinth.x * 0.5 + 0.2) + Vector3(0, (plinth.y - 1.0) * 0.5, 0)],
			]
			for part: Array in parts:
				var pour := _slab(part[0], base + aside + part[1], slag)
				pour.rotation.y = k * PI * 0.5
				art.add_child(pour)
	for side: float in [-1.0, 1.0]:
		art.add_child(_smoke(base + Vector3(side * tower.x * 0.4, plinth.y + tower.y - 1.0, -side * tower.x * 0.4), 2.0))
	_beacon = _slab(Vector3(2.2, 2.2, 2.2), base + Vector3(0, y + 0.8, 0), Look.trim("beacon"))
	art.add_child(_beacon)
	# The halo that finds the beacon from the rim, through the smoke.
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 16)
	quad.material = Look.trim("halo")
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Seen from anywhere on the map: never faded out with the small props.
	halo.visibility_range_end = FAR_SIGHT
	_beacon.visibility_range_end = FAR_SIGHT
	_beacon.add_child(halo)
	_beacon_light = Look.lamp(Color(1.0, 0.12, 0.08), 6.0, 40.0)
	_beacon_light.position = _beacon.position
	art.add_child(_beacon_light)


## A plain dressed box with no collision and no shadow.
func _slab(size: Vector3, at: Vector3, material: Material, shadow := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	node.mesh = mesh
	node.position = at
	if not shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The wrecks finished off by one detail each, the same detail on every one
## of a kind: a tank's dead teal running light along its hull, a strider's
## cockpit slit, a dropship's hazard-striped fin and the furrow it ploughed.
func _dress_wrecks(art: Node3D) -> void:
	var furrows: Array[PackedVector2Array] = []
	for wreck in _wrecks:
		if not wreck.has("kind"):
			continue
		var base: Vector3 = wreck["at"]
		var yaw: float = wreck["yaw"]
		var big: float = wreck["big"]
		var size: Vector3 = wreck["size"]
		var turn := Basis(Vector3.UP, yaw)
		match int(wreck["kind"]):
			0:
				for side: float in [-1.0, 1.0]:
					var light := _slab(Vector3(0.08, 0.12, size.z * 0.7), base + turn * Vector3(side * (size.x * 0.5 + 0.03), size.y * 0.55, 0), Look.trim("teal"))
					light.rotation.y = yaw
					art.add_child(light)
			1:
				var slit := _slab(Vector3(size.x * 0.6, 0.25, 0.08), Vector3.ZERO, Look.trim("teal"))
				slit.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.38)),
						base + Vector3(0, size.y * 0.5 - 0.8, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.15, -size.z * 0.5 - 0.05))
				art.add_child(slit)
			2:
				var fin := _slab(Vector3(0.45, 1.0 * big, 2.65 * big), base + turn * Vector3(0.3, size.y + 0.6 * big, size.z * 0.42), Look.trim("hazard"))
				fin.rotation = Vector3(-0.05, yaw + 0.12, 0.0)
				art.add_child(fin)
				var behind := Vector2(sin(yaw), cos(yaw))
				var from := Vector2(base.x, base.z) + behind * size.z * 0.5
				furrows.append(PackedVector2Array([from, from + behind * size.z * 1.6]))
	_ground_strips(art, furrows, 2.2, Look.trim("scorch"), 0.04)


## Each barricade piece drawn over its plain box: a jersey barrier's sloped
## concrete, a sandbag wall laid in courses, a steel plate with hazard
## stripes along its top, and a tank trap of three crossed beams.
func _dress_cover(art: Node3D) -> void:
	var bags := MultiMesh.new()
	bags.transform_format = MultiMesh.TRANSFORM_3D
	var bag := BoxMesh.new()
	bag.size = Vector3(0.62, 0.24, 0.42)
	bag.material = Look.trim("sandbag")
	bags.mesh = bag
	var beams := MultiMesh.new()
	beams.transform_format = MultiMesh.TRANSFORM_3D
	var beam := BoxMesh.new()
	beam.size = Vector3(0.22, 0.22, 2.0)
	beam.material = HULL
	beams.mesh = beam
	var bag_at: Array[Transform3D] = []
	var beam_at: Array[Transform3D] = []
	for piece in _cover_pieces:
		var kind: String = piece.get_meta("cover", "")
		var shown := piece.get_child(1) as MeshInstance3D
		var size: Vector3 = (shown.mesh as BoxMesh).size
		var frame := Transform3D(Basis(Vector3.UP, piece.rotation.y), piece.position)
		var ground_y := -size.y * 0.5 + 0.8 * 0.5
		match kind:
			"sandbag":
				shown.queue_free()
				var length := size.x
				for course in 4:
					var count := int(length / 0.6)
					for n in count:
						var x := -length * 0.5 + 0.3 + n * (length - 0.6) / maxf(count - 1, 1) + (0.15 if course % 2 == 1 else 0.0)
						for row: float in [-0.2, 0.2]:
							if course == 3 and row > 0.0:
								continue
							bag_at.append(frame * Transform3D(Basis(Vector3.UP, 0.04 * ((n + course) % 3 - 1)),
									Vector3(clampf(x, -length * 0.5 + 0.3, length * 0.5 - 0.3), ground_y - 0.15 + course * 0.24, row)))
			"trap":
				shown.queue_free()
				for axis in 3:
					var turn := Basis.from_euler([Vector3(0.6, 0.0, 0.0), Vector3(0.0, 0.0, 0.6) * 1.0 + Vector3(0, PI * 0.5, 0), Vector3(PI * 0.5, 0.35, 0.0)][axis])
					beam_at.append(frame * Transform3D(turn, Vector3(0, ground_y + 0.9, 0)))
			"plate":
				art.add_child(_slab(Vector3(size.x + 0.02, 0.3, size.z + 0.02), Vector3.ZERO, Look.trim("hazard")))
				art.get_child(art.get_child_count() - 1).transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5 - 0.55, 0))
			"jersey":
				# The barrier's sloped foot, so it reads as a cast barrier.
				var foot := _slab(Vector3(size.x, 0.45, size.z + 0.5), Vector3.ZERO, COVER_CONCRETE, true)
				foot.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, ground_y + 0.2, 0))
				art.add_child(foot)
	for set: Array in [[bags, bag_at], [beams, beam_at]]:
		var mm: MultiMesh = set[0]
		var list: Array = set[1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		art.add_child(node)


## Cracks of molten metal running in from the field to the core's rim, so
## the ground itself leads the eye to the Forge. Each is drawn in segments
## laid on the ground, wider near the core, and stops where something stands.
func _dress_cracks(art: Node3D) -> void:
	var lines: Array[PackedVector2Array] = []
	for k in CRACKS:
		var angle := TAU * (k + 0.5) / CRACKS + _art_rng.randf_range(-0.15, 0.15)
		var line := PackedVector2Array()
		var reach := _art_rng.randf_range(120.0, 175.0)
		var r := CORE_RADIUS - 2.0
		var drift := 0.0
		while r < reach:
			drift = clampf(drift + _art_rng.randf_range(-0.05, 0.05), -0.12, 0.12)
			line.append(Vector2.from_angle(angle + drift) * r)
			r += 2.0
		lines.append(line)
	# A charred bed under each crack, then the glow in it.
	_ground_strips(art, lines, 3.2, Look.trim("scorch"), 0.08, true)
	_ground_strips(art, lines, 0.6, Look.trim("crack"), 0.12, true)


## Draws each polyline as short boxes laid on the ground and tipped with it,
## in one MultiMesh. `taper` narrows a line toward its far end.
func _ground_strips(art: Node3D, lines: Array[PackedVector2Array], width: float, material: Material, lift: float, taper := false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.1, 1.0)
	box.material = material
	mm.mesh = box
	var placed: Array[Transform3D] = []
	for line in lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var mid := (a + b) * 0.5
			if _crack_blocked(mid):
				continue
			var pa := terrain.on_ground(a.x, a.y)
			var pb := terrain.on_ground(b.x, b.y)
			var along := pb - pa
			var t := float(i) / maxf(line.size() - 1, 1)
			var w := width * (lerpf(1.0, 0.35, t) if taper else 1.0)
			var forward := along.normalized()
			var right := forward.cross(Vector3.UP).normalized()
			var up := right.cross(forward)
			var basis := Basis(right * w, up, forward * (along.length() + 0.3))
			placed.append(Transform3D(basis, (pa + pb) * 0.5 + up * lift))
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(node)


func _crack_blocked(at: Vector2) -> bool:
	for solid in _solids:
		if at.distance_to(solid["at"]) < float(solid["reach"]) + 0.5:
			return true
	return false


## The skyline: a few huge, simple shapes past the rim, each placed on
## purpose so the world reads as enormous. A capital ship that came down
## nose first in the north, each army's smokestacks behind its muster, a
## megabridge broken in the southwest, a toppled tower in the northeast,
## and between them the low line of a ruined city. Built from four pieces
## (hull, stack, pylon, block) used over and over.
func _dress_horizon(art: Node3D) -> void:
	var hulk := Look.trim("distant")
	var floor_y := RIM_HEIGHT - 8.0
	var at := func(angle_deg: float, reach: float, up := 0.0) -> Vector3:
		var a := deg_to_rad(angle_deg)
		return Vector3(cos(a) * reach, floor_y + up, sin(a) * reach)
	var put := func(size: Vector3, xform: Transform3D) -> void:
		var node := _slab(size, Vector3.ZERO, hulk)
		node.transform = xform
		art.add_child(node)
	# The capital ship, nose buried, hull rising away to the east.
	var ship_at: Vector3 = at.call(-95.0, 520.0)
	var ship := Transform3D(Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, -0.36), ship_at + Vector3(0, 40, 0))
	put.call(Vector3(46, 30, 300), ship)
	put.call(Vector3(30, 22, 60), ship * Transform3D(Basis.IDENTITY, Vector3(0, -2, -170)))
	put.call(Vector3(22, 36, 34), ship * Transform3D(Basis.IDENTITY, Vector3(0, 30, 95)))
	for side: float in [-1.0, 1.0]:
		put.call(Vector3(18, 18, 30), ship * Transform3D(Basis.IDENTITY, Vector3(side * 16, -4, 160)))
	art.add_child(_plume(ship * Vector3(0, 12, 120), 10.0))
	# Smokestacks, four to an army, behind each muster, joined by a hall.
	for angle: float in [184.0, -4.0]:
		var hall_at: Vector3 = at.call(angle, 440.0)
		var face := Basis(Vector3.UP, -deg_to_rad(angle))
		put.call(Vector3(40, 34, 120), Transform3D(face, hall_at + Vector3(0, 17, 0)))
		for n in 4:
			var height: float = [150.0, 120.0, 135.0, 105.0][n]
			var stack: Vector3 = hall_at + face * Vector3(0, 0, (n - 1.5) * 30.0)
			var node := MeshInstance3D.new()
			var tube := CylinderMesh.new()
			tube.top_radius = 4.5
			tube.bottom_radius = 6.5
			tube.height = height
			tube.radial_segments = 8
			tube.material = hulk
			node.mesh = tube
			node.position = stack + Vector3(0, height * 0.5, 0)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(node)
			if n % 2 == 0:
				art.add_child(_plume(stack + Vector3(0, height, 0), 4.0))
	# The megabridge: two pylons, half the deck still up, half fallen.
	var bridge_at: Vector3 = at.call(130.0, 470.0)
	var span := Basis(Vector3.UP, -deg_to_rad(130.0) + PI * 0.5)
	for side: float in [-1.0, 1.0]:
		put.call(Vector3(26, 160, 26), Transform3D(span, bridge_at + span * Vector3(side * 85, 80, 0)))
	put.call(Vector3(80, 10, 30), Transform3D(span, bridge_at + span * Vector3(-45, 150, 0)))
	put.call(Vector3(96, 10, 30), Transform3D(span * Basis(Vector3.BACK, -1.05), bridge_at + span * Vector3(52, 72, 0)))
	# The toppled tower, leaning on the rim.
	var tower_at: Vector3 = at.call(-40.0, 470.0)
	var lean := Basis(Vector3.UP, -deg_to_rad(-40.0)) * Basis(Vector3.BACK, 0.62)
	put.call(Vector3(48, 240, 48), Transform3D(lean, tower_at + Vector3(0, 90, 0)))
	put.call(Vector3(56, 12, 56), Transform3D(lean, tower_at + Vector3(0, 90, 0) + lean * Vector3(0, 60, 0)))
	# Broken pylons in the south, the bridge's sisters.
	for n in 3:
		var pylon_at: Vector3 = at.call(70.0 + n * 14.0, 450.0 + n * 25.0)
		var height: float = [120.0, 75.0, 95.0][n]
		put.call(Vector3(26, height, 26), Transform3D(Basis(Vector3.UP, n * 0.4), pylon_at + Vector3(0, height * 0.5, 0)))
	# The ruined city between the set pieces: square blocks, upright, gapped.
	var landmarks := [-95.0, 184.0, -4.0, 130.0, -40.0, 84.0]
	var angle := -180.0
	while angle < 180.0:
		var near := false
		for mark: float in landmarks:
			if absf(wrapf(angle - mark, -180.0, 180.0)) < 16.0:
				near = true
		if not near:
			var width := _art_rng.randf_range(24.0, 44.0)
			var height := _art_rng.randf_range(30.0, 70.0)
			var block_at: Vector3 = at.call(angle, _art_rng.randf_range(400.0, 470.0), height * 0.5)
			var face := Basis(Vector3.UP, -deg_to_rad(angle))
			put.call(Vector3(width, height, width * 0.7), Transform3D(face, block_at))
			# Most blocks were shelled: a narrower broken storey left on one side.
			if _art_rng.randf() < 0.6:
				var side := _art_rng.randf_range(-0.3, 0.3) * width
				var storey := _art_rng.randf_range(10.0, 26.0)
				put.call(Vector3(width * 0.35, storey, width * 0.5), Transform3D(face, block_at + face * Vector3(side, (height + storey) * 0.5, 0)))
		angle += _art_rng.randf_range(7.0, 11.0)


## A tall smoke plume for the skyline: the fire smoke, scaled up to be read
## from across the map.
func _plume(at: Vector3, width: float) -> GPUParticles3D:
	var plume := _smoke(at, width)
	(plume.draw_pass_1 as QuadMesh).size = Vector2(40, 40)
	var mat := plume.process_material as ParticleProcessMaterial
	mat.initial_velocity_min = 7.0
	mat.initial_velocity_max = 10.0
	plume.visibility_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 260, 300))
	return plume
