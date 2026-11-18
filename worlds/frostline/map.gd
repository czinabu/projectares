extends Node3D
## Greybox Frostline: one long frozen river valley, about 600 metres from end
## to end.
##
## The valley runs north (-Z) from the river mouth, where players arrive, up
## through the Narrows and across a frozen lake to the glacier head, where
## the Stilled Engine lies half buried: the terraforming drum that once kept
## this world warm. Both walls step up in two tiers, a shelf about 14 m over
## the floor (heater huts, strongpoints, ramps up to them) and a rim about
## 40 m up that only flight reaches (old listening posts, the best caches).
## Fights here are about who holds the high side, not who reaches the middle.
##
## The layout uses a fixed seed, so the map is the same every time while loot
## and spawns vary. The rest of the game relies only on the map contract in
## WorldDef. The ground, its collision and the navigation mesh are worked out
## once per run of the game and shared by every copy of the map.

const LAYOUT_SEED := 4242
## Metres between ground samples, and how many there are along each edge.
const CELL := 2.0
const SIDE := 321
## Heights over the valley floor of the shelf and the rim.
const SHELF := 14.0
const RIM := 40.0
## How far past the floor's edge each step of the wall starts and ends.
const SHELF_FROM := 6.0
const SHELF_TO := 18.0
const RIM_TO := 26.0
## The risk zones run along the valley: the river mouth is the outer ring,
## the Narrows and the lake the middle, the glacier head the core.
const MIDDLE_FROM_Z := 40.0
const CORE_FROM_Z := -150.0
## Where the Stilled Engine lies across the valley head.
const ENGINE_Z := -235.0
const ENGINE_RADIUS := 22.0
const ENGINE_LENGTH := 76.0
## How far round the hatch the Engine Sentinel keeps its guard.
const SENTINEL_GROUND := 16.0
## The valley's end: the glacier climbs behind it (and the pack ice at the
## mouth past its mirror), so nothing on the ground lies further out.
const VALLEY_HEAD_Z := 262.0
## The frozen lake where the valley widens.
const LAKE_Z := -95.0
const LAKE_RADIUS := Vector2(44.0, 40.0)
## The middle of the lake is thin ice (`WorldDef.thin_ice`): within this
## share of its radius a heavy vehicle breaks through. The shore ice holds.
const THIN_ICE := 0.7


## How far out on the lake a point is: 0 at its middle, 1 at its shore.
static func lake_reach(x: float, z: float) -> float:
	return Vector2((x - centre(z)) / LAKE_RADIUS.x, (z - LAKE_Z) / LAKE_RADIUS.y).length()
## Ramps cut into the walls up to the shelf: which side, where the top is,
## and which way along the valley they run down.
const RAMPS := [
	{"side": -1.0, "top": 175.0, "down": 1.0},
	{"side": 1.0, "top": 60.0, "down": 1.0},
	{"side": -1.0, "top": -60.0, "down": 1.0},
	{"side": 1.0, "top": -185.0, "down": 1.0},
]
const RAMP_LENGTH := 50.0
const RAMP_WIDTH := 8.0
## The strongpoints, on the shelves and at the lake's north shore. Held by
## the Wardens to begin with.
const POSTS := [
	{"name": "Echo Post", "z": 150.0, "side": -1.0, "shelf": true},
	{"name": "Drift Post", "z": -142.0, "side": 0.0, "shelf": false},
	{"name": "Vigil Post", "z": -200.0, "side": 1.0, "shelf": true},
]
## Heater huts on the shelves: where to warm up and something worth a look.
const HUTS := [
	{"z": 205.0, "side": 1.0},
	{"z": 95.0, "side": -1.0},
	{"z": 20.0, "side": 1.0},
	{"z": -30.0, "side": -1.0},
	{"z": -105.0, "side": 1.0},
	{"z": -205.0, "side": -1.0},
]
## Warm vents on the valley floor, between the huts up on the shelves: the
## Engine's old heat lines still breathe here (z, and how far off the middle,
## clear of the frozen river).
const VENTS := [
	{"z": 200.0, "off": 18.0},
	{"z": 120.0, "off": -18.0},
	{"z": 40.0, "off": 17.0},
	{"z": -20.0, "off": -17.0},
	{"z": -70.0, "off": 46.0},
	{"z": -178.0, "off": -24.0},
]
## How much warmth each kind of place gives back, a second, and how far it
## reaches (see "The cold" in `WorldDef`).
const HEATER := {"radius": 3.4, "warmth": 10.0}
const VENT := {"radius": 3.5, "warmth": 6.0}
const CAMP := {"radius": 7.0, "warmth": 10.0}
const HATCH := {"radius": 5.0, "warmth": 8.0}
## The warm beacons: the only way out of the valley (`WorldDef.sign_out_at_beacons`).
## A beacon is a mast on the floor whose heat lamp powers up the lift home
## while someone holds it, so each one is also somewhere warm to stand.
const BEACONS := [
	{"name": "Mouth Beacon", "z": 232.0, "off": -22.0},
	{"name": "Narrows Beacon", "z": -2.0, "off": 24.0},
	{"name": "Lakeshore Beacon", "z": -60.0, "off": -40.0},
	{"name": "Glacier Beacon", "z": -180.0, "off": 24.0},
]
const BEACON := {"radius": 6.0, "warmth": 8.0}
## Old listening posts on the rims, reached only by flight.
const LISTENING := [
	{"z": 175.0, "side": 1.0},
	{"z": 110.0, "side": -1.0},
	{"z": 5.0, "side": 1.0},
	{"z": -60.0, "side": -1.0},
	{"z": -125.0, "side": -1.0},
	{"z": -190.0, "side": 1.0},
]

## Kept from the first map built in this run: { navmesh }.
static var _shared := {}
## The ground may be worked out on another thread ahead of a visit
## (`prepare_shared`); whoever comes second waits for the first.
static var _ground_lock := Mutex.new()
## The shared ground, { heights, collision }, kept apart from `_shared` so
## only this is ever touched from two threads, and only under the lock.
static var _ground_shared := {}

var nav_region: NavigationRegion3D
var terrain: Terrain
var _rng := RandomNumberGenerator.new()
## Dressing has its own generator so art never shifts the gameplay layout.
var _art_rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _huts: Array[Dictionary] = []
var _posts: Array[Vector3] = []
var _engine_at := Vector3.ZERO
var _vents: Array[Vector3] = []
var _beacons: Array[Vector3] = []
var _camp := Vector3.ZERO
## Bot spawn spots, placed last in order of `rank`: the Raid fills the first
## `bot_count` markers at the start, so a mix of both factions comes first.
var _bot_spots: Array[Dictionary] = []
var _weather: Node3D

@onready var SNOW := Look.surface("ground", {"tint": Color(0.62, 0.68, 0.78), "snow": 0.85, "snow_patchy": 0.35,
		"grime": 0.0, "scale": 0.1, "rough_mult": 0.6, "saturation": 0.25})
@onready var ICE_WALL := Look.surface("concrete", {"tint": Color(0.36, 0.5, 0.66), "snow": 0.35, "grime": 0.0,
		"scale": 0.06, "rough_mult": 0.4})
@onready var ROCK := Look.surface("ground", {"tint": Color(0.3, 0.33, 0.38), "snow": 0.6, "grime": 0.3, "scale": 0.25})
@onready var STEEL := Look.surface("metal", {"tint": Color(0.42, 0.46, 0.52), "snow": 0.8, "grime": 0.5, "scale": 0.3,
		"window_glow": Color(1.0, 0.6, 0.3), "lit_windows": 0.15})
@onready var HULL := Look.surface("metal", {"tint": Color(0.34, 0.38, 0.44), "snow": 0.45, "grime": 0.6, "scale": 0.08})
@onready var HULL_DARK := Look.surface("metal", {"tint": Color(0.22, 0.25, 0.3), "snow": 0.4, "grime": 0.7, "scale": 0.1})


func _ready() -> void:
	_seed_layout()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_walls()
	_build_mouth()
	_build_posts()
	_build_huts()
	_build_listening_posts()
	_build_floor()
	_build_engine()
	_build_vents()
	_build_beacons()
	_place_bot_spots()
	_art_rng.seed = LAYOUT_SEED
	_dress()
	set_process(Look.enabled)


func _seed_layout() -> void:
	_rng.seed = LAYOUT_SEED
	_noise.seed = LAYOUT_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.02


## Works out the ground every copy of this map shares, on a map that is
## never added to the tree (`WorldDef.prepare_map`, off the main thread).
func prepare_shared() -> void:
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		_seed_layout()
		terrain = Terrain.new()
		terrain.cell = CELL
		terrain.side = SIDE
		terrain.shape(_height)
		_ground_shared["collision"] = terrain.collision_data()
		_ground_shared["heights"] = terrain.heights
		terrain.free()
		terrain = null
	_ground_lock.unlock()


func bake_navigation() -> void:
	if not _shared.has("navmesh"):
		var navmesh := NavigationMesh.new()
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		navmesh.geometry_collision_mask = Actor.LAYER_WORLD
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


## Where the wind lifts snow off an edge in a storm (`WeatherView`'s
## spindrift): along both rims' crests and the shelves' lips, every
## `RIDGE_STEP` metres down the valley.
const RIDGE_STEP := 14.0
var _ridges := PackedVector3Array()


func weather_ridges() -> PackedVector3Array:
	if not _ridges.is_empty():
		return _ridges
	var z := VALLEY_HEAD_Z
	while z > -VALLEY_HEAD_Z:
		for side: float in [-1.0, 1.0]:
			for out: float in [RIM_TO, SHELF_FROM]:
				var x := centre(z) + side * (half_width(z) + out)
				_ridges.append(Vector3(x, ground_height(x, z), z))
		z -= RIDGE_STEP
	return _ridges


func _process(_delta: float) -> void:
	# The snow blows round whoever is looking, not over the whole valley.
	var camera := get_viewport().get_camera_3d()
	if camera != null and is_instance_valid(_weather):
		_weather.global_position = Vector3(camera.global_position.x, camera.global_position.y - 8.0,
				camera.global_position.z)


func _build_environment() -> void:
	# A war that ended long ago: a low bright sun on the snow, long blue
	# shadows, and clear air down the valley. The only warm colours are the
	# heaters' and the Engine's one teal light.
	Look.atmosphere(self, {
		"sky_tint": Color(0.78, 0.86, 1.0),
		"sky_saturation": 0.35,
		"sky_energy": 1.0,
		"fog_color": Color(0.62, 0.72, 0.86),
		"fog_density": 0.0016,
		"haze_height": 0.4,
		"sun_color": Color(1.0, 0.9, 0.76),
		"sun_energy": 1.8,
		"sun_angles": Vector3(-11, -35, 0),
		"ambient_color": Color(0.45, 0.56, 0.75),
		"ambient_energy": 0.7,
		"saturation": 0.85,
		"contrast": 1.12,
	}, {}, {
		# The heart of a whiteout (DESIGN.md "Frostline"): the sun gone to a
		# pale smear, everything the same blue-white, a body a shape at
		# 30 m and gone by 70 m (Look.soften_weather keeps it from closing
		# in further). Flat light, so the snow and the sky run together.
		"sky_tint": Color(0.86, 0.9, 0.96),
		"sky_saturation": 0.15,
		"sky_energy": 0.9,
		"fog_color": Color(0.8, 0.85, 0.92),
		"fog_density": 0.985,
		"fog_depth_begin": 4.0,
		"fog_depth_end": 55.0,
		"fog_depth_curve": 0.8,
		"haze_height": 1.0,
		"sun_color": Color(0.9, 0.93, 1.0),
		"sun_energy": 0.45,
		"ambient_color": Color(0.7, 0.76, 0.86),
		"ambient_energy": 1.3,
		"saturation": 0.6,
		"contrast": 0.95,
	})
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		# A low sun throws long shadows: reach far enough to keep them.
		sun.directional_shadow_max_distance = 220.0
	Look.weather(self, "snow", 40.0, 24.0)
	_weather = get_node_or_null("Weather")


# --- The shape of the valley ------------------------------------------------------

## The middle of the valley floor at `z`: it bends gently.
static func centre(z: float) -> float:
	return 16.0 * sin(z / 70.0)


## How far the floor reaches either side of the middle at `z`.
static func half_width(z: float) -> float:
	if z > 150.0:
		return 80.0
	if z > MIDDLE_FROM_Z:
		return lerpf(30.0, 80.0, smoothstep(MIDDLE_FROM_Z, 150.0, z))
	if z > -40.0:
		return lerpf(62.0, 30.0, smoothstep(-40.0, MIDDLE_FROM_Z, z))
	return 62.0


## The height of the valley floor at `z`: level at the mouth, a step up to
## the lake, and a climb onto the glacier.
static func floor_at(z: float) -> float:
	if z > -40.0:
		return lerpf(4.0, 0.0, smoothstep(-40.0, 280.0, z))
	if z > CORE_FROM_Z:
		return 4.0
	return lerpf(4.0, 26.0, smoothstep(CORE_FROM_Z, -300.0, z))


## Where on the shelf of `side` (-1 west, 1 east) a thing at `z` stands.
static func shelf_point(z: float, side: float) -> Vector2:
	return Vector2(centre(z) + side * (half_width(z) + (SHELF_FROM + SHELF_TO) * 0.5), z)


static func rim_point(z: float, side: float) -> Vector2:
	return Vector2(centre(z) + side * (half_width(z) + RIM_TO + 10.0), z)


func _height(x: float, z: float) -> float:
	var across := x - centre(z)
	var d := absf(across)
	var w := half_width(z)
	var f := floor_at(z)
	var n := _noise.get_noise_2d(x, z)
	var h := f + n * 0.4
	var t := d - w
	if d < w:
		# The river cut, frozen over, and the lake.
		if z > -40.0 and d < 12.0:
			h = f - 0.8 * (1.0 - smoothstep(8.0, 12.0, d))
		var lake := Vector2(across / LAKE_RADIUS.x, (z - LAKE_Z) / LAKE_RADIUS.y).length()
		if lake < 1.15:
			h = lerpf(f - 0.6, h, smoothstep(0.95, 1.15, lake))
	else:
		var shelf := SHELF + n * 0.5
		var rim := RIM + n * 3.0
		if t < SHELF_FROM:
			h = f + shelf * smoothstep(0.0, SHELF_FROM, t)
		elif t < SHELF_TO:
			h = f + shelf
		elif t < RIM_TO + 14.0:
			h = f + lerpf(shelf, rim, smoothstep(SHELF_TO, RIM_TO, t))
		else:
			# Mountains past the rim: nobody goes there.
			h = f + rim + smoothstep(RIM_TO + 14.0, RIM_TO + 40.0, t) * 50.0
	# Ramps: a ledge along the foot of the wall that climbs from the floor to
	# the shelf, wide enough to walk and drive up.
	for ramp: Dictionary in RAMPS:
		if signf(across) != float(ramp["side"]):
			continue
		var along := (z - float(ramp["top"])) * float(ramp["down"])
		if along < -2.0 or along > RAMP_LENGTH or t < -RAMP_WIDTH or t > SHELF_FROM + 1.0:
			continue
		h = maxf(h, f + SHELF * (1.0 - clampf(along / RAMP_LENGTH, 0.0, 1.0)))
	# The valley head: the glacier climbs behind the Engine and closes the end.
	h += smoothstep(-262.0, -310.0, z) * 60.0
	# The river mouth runs out onto a frozen sea that rises into pack ice.
	h += smoothstep(296.0, 318.0, z) * 30.0
	return h


func _build_ground() -> void:
	terrain = Terrain.new()
	terrain.name = "Ground"
	terrain.cell = CELL
	terrain.side = SIDE
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		terrain.shape(_height)
		_ground_shared["collision"] = terrain.collision_data()
		_ground_shared["heights"] = terrain.heights
	var collision: PackedFloat32Array = _ground_shared["collision"]
	terrain.heights = _ground_shared["heights"]
	_ground_lock.unlock()
	terrain.build(SNOW, collision)
	nav_region.add_child(terrain)
	# Nobody leaves over the mountains.
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


func _ground(at: Vector2) -> Vector3:
	return terrain.on_ground(at.x, at.y)


## Ice slabs stood along both walls in a steady rhythm, at the foot of the
## cliff and on the shelf's face: the same three sizes over and over. They
## are cover along the wall's foot, and they hide the heightfield's steps.
func _build_walls() -> void:
	var sizes := [Vector3(7, 15, 3), Vector3(5, 12, 3), Vector3(9, 17, 3.5)]
	var z := 290.0
	var i := 0
	while z > -262.0:
		for side: float in [-1.0, 1.0]:
			if _on_ramp(z, side):
				continue
			var w := half_width(z)
			var f := floor_at(z)
			var low: Vector3 = sizes[(i + int(side > 0.0)) % 3]
			var body := _box(low, Vector3(centre(z) + side * (w + 2.5), f + low.y * 0.4, z), ICE_WALL)
			body.rotation = Vector3(0, PI / 2.0 + side * 0.06, side * 0.08)
			var high: Vector3 = sizes[(i + 1) % 3] * Vector3(1, 1.4, 1)
			var upper := _box(high, Vector3(centre(z) + side * (w + SHELF_TO + 2.0), f + SHELF + high.y * 0.35, z), ICE_WALL)
			upper.rotation = Vector3(0, PI / 2.0, side * 0.1)
		z -= 13.0
		i += 1


func _on_ramp(z: float, side: float) -> bool:
	for ramp: Dictionary in RAMPS:
		var along := (z - float(ramp["top"])) * float(ramp["down"])
		if float(ramp["side"]) == side and along > -8.0 and along < RAMP_LENGTH + 8.0:
			return true
	return false


## The river mouth: where players arrive, with a depot either side of the
## river and a few rocks to land behind.
func _build_mouth() -> void:
	for i in 6:
		var z := 268.0 + (i % 2) * 10.0
		var x := centre(z) + (floori(i / 2.0) - 1) * 34.0 + (6.0 if i % 2 else -6.0)
		_add_marker("spawn_player", _ground(Vector2(x, z)))
	# The camp's fire between the spawns, to set out warm and come back to.
	_camp = _ground(Vector2(centre(262.0) + 17.0, 262.0))
	_add_warmth(_camp, CAMP)
	for side: float in [-1.0, 1.0]:
		var at := Vector2(centre(250.0) + side * 30.0, 250.0)
		_add_depot(_ground(at))
		_add_rocks(at + Vector2(side * 8.0, -6.0), 2)


## The three strongpoints: a hut and a low wall round its yard, a depot
## beside it, a cache inside and the Wardens who hold it.
func _build_posts() -> void:
	for post: Dictionary in POSTS:
		var z: float = post["z"]
		var side: float = post["side"]
		var at := shelf_point(z, side) if post["shelf"] else Vector2(centre(z), z)
		var base := _ground(at)
		_posts.append(base)
		var marker := _add_marker("strongpoint", base)
		marker.set_meta("name", post["name"])
		marker.set_meta("radius", 13.0)
		marker.set_meta("holder", "warden")
		marker.set_meta("holder_name", "the Wardens")
		# The hut stands against the wall, open toward the valley.
		var facing := -side if side != 0.0 else 1.0
		var hut_at := at + Vector2(-facing * 3.0, 0.0) if side != 0.0 else at + Vector2(0, -6.0)
		_add_hut(_ground(hut_at), facing, true)
		for k in 3:
			var spot := at + Vector2(facing * 6.0, (k - 1) * 6.0) if side != 0.0 else at + Vector2((k - 1) * 7.0, 7.0)
			var wall := _box(Vector3(5.0, 1.4, 0.8), _ground(spot) + Vector3(0, 0.5, 0), STEEL)
			wall.rotation.y = PI / 2.0 if side != 0.0 else 0.0
		_add_depot(_ground(at + (Vector2(0, -9.0) if side != 0.0 else Vector2(-12.0, 0))))
		_add_marker("spawn_cache", base + Vector3(0, 0.1, 0))
		for k in 2:
			_bot_spot(_ground(at + Vector2(facing * 3.0, (k * 2 - 1) * 4.0)), "warden", 0 if k == 0 else 3)


## A heater hut: three walls and a roof against the cliff, open toward the
## valley, with a heater at the back.
func _build_huts() -> void:
	for hut: Dictionary in HUTS:
		var at := shelf_point(hut["z"], hut["side"])
		_add_hut(_ground(at), -float(hut["side"]), false)
		_add_marker("spawn_cache", _ground(at) + Vector3(0, 0.1, 0))


func _add_hut(base: Vector3, facing: float, post: bool) -> void:
	var hut := Node3D.new()
	hut.position = base
	# The open side faces +X when `facing` is 1, -X when it is -1.
	hut.rotation.y = PI / 2.0 * facing
	nav_region.add_child(hut)
	var height := 3.4 if not post else 4.2
	for part: Array in [
			[Vector3(6.4, height, 0.3), Vector3(0, height * 0.5, -2.6)],
			[Vector3(0.3, height, 5.2), Vector3(-3.1, height * 0.5, 0)],
			[Vector3(0.3, height, 5.2), Vector3(3.1, height * 0.5, 0)],
			[Vector3(6.8, 0.3, 5.8), Vector3(0, height + 0.15, 0)],
			# The heater against the back wall.
			[Vector3(1.4, 1.4, 0.9), Vector3(0, 0.7, -1.9)]]:
		_box(part[0], part[1], STEEL, hut)
	_huts.append({"at": base, "facing": facing, "height": height})
	# Its heater warms the inside of the hut.
	_add_warmth(base + hut.basis * Vector3(0, 0, -0.6), HEATER)


## Old listening posts on the rims: a bunker and a mast, with the rooftop
## haul on top. Wardens keep watch from some of them.
func _build_listening_posts() -> void:
	for i in LISTENING.size():
		var spot: Dictionary = LISTENING[i]
		var at := rim_point(spot["z"], spot["side"])
		var base := _ground(at)
		_box(Vector3(5, 4, 5), base + Vector3(0, 1.8, 0), STEEL)
		_box(Vector3(1, 8, 1), base + Vector3(0, 7.8, 0), STEEL)
		_add_marker("spawn_cache", base + Vector3(0, 4.0, 0)).set_meta("loot_source", "rooftop")
		if i % 2 == 0:
			_bot_spot(_ground(at + Vector2(-float(spot["side"]) * 4.0, 0)), "warden", 2)


## The valley floor: rock for cover in a few repeated shapes, caches among
## them, and the Feral packs' dens in the Narrows and round the lake.
func _build_floor() -> void:
	var placed := 0
	var attempts := 0
	while placed < 46 and attempts < 400:
		attempts += 1
		var z := _rng.randf_range(-215.0, 285.0)
		var w := half_width(z) - RAMP_WIDTH - 4.0
		var x := centre(z) + _rng.randf_range(-w, w)
		if absf(x - centre(z)) < 13.0 and z > -40.0:
			continue
		var lake := Vector2((x - centre(z)) / LAKE_RADIUS.x, (z - LAKE_Z) / LAKE_RADIUS.y).length()
		if lake < 1.2 or absf(z - ENGINE_Z) < ENGINE_RADIUS + 8.0:
			continue
		_add_rocks(Vector2(x, z), _rng.randi_range(1, 3))
		if placed % 4 == 0:
			_add_marker("spawn_cache", _ground(Vector2(x + 3.5, z)))
		placed += 1
	var dens: Array[float] = [20.0, -20.0, -60.0, LAKE_Z + LAKE_RADIUS.y + 6.0, LAKE_Z - 10.0]
	for k in dens.size():
		var z := dens[k]
		var side := 1.0 if k % 2 == 0 else -1.0
		var w := half_width(z) * (0.6 if absf(z - LAKE_Z) > LAKE_RADIUS.y else 0.95)
		_bot_spot(_ground(Vector2(centre(z) + side * w, z)), "feral", 1)


func _add_rocks(at: Vector2, count: int) -> void:
	var shapes := [Vector3(3, 1.6, 2.2), Vector3(5, 2.4, 3), Vector3(2, 1.2, 2)]
	for k in count:
		var size: Vector3 = shapes[(k + int(absf(at.x))) % 3]
		var spot := at + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5))
		var rock := _box(size + Vector3(0, 0.6, 0), _ground(spot) + Vector3(0, size.y * 0.5 - 0.3, 0), ROCK)
		rock.rotation = Vector3(0, _rng.randf() * TAU, _rng.randf_range(-0.08, 0.08))


## The Stilled Engine: a colossal drum sunk into the glacier across the
## valley head, ribbed and finned. Its back is the relay's old perch, the
## richest cache on the map, reached only by flight; the foot of it is the
## core, with the core's caches round its hatch.
func _build_engine() -> void:
	var base := _ground(Vector2(centre(ENGINE_Z), ENGINE_Z))
	_engine_at = base
	var engine := StaticBody3D.new()
	engine.collision_layer = Actor.LAYER_WORLD
	engine.collision_mask = 0
	engine.position = base + Vector3(0, ENGINE_RADIUS * 0.2, 0)
	engine.rotation = Vector3(0.0, PI / 2.0 + 0.12, 0.0)
	nav_region.add_child(engine)
	_cylinder(engine, ENGINE_RADIUS, ENGINE_LENGTH, Vector3.ZERO, HULL)
	for k in 6:
		_cylinder(engine, ENGINE_RADIUS + 1.4, 2.4, Vector3(0, 0, -ENGINE_LENGTH * 0.4 + k * ENGINE_LENGTH * 0.16), HULL_DARK)
	# The intake rings at its end and the cooling fins along its back.
	for k in 3:
		_cylinder(engine, ENGINE_RADIUS - 4.0 - k * 5.0, 1.2, Vector3(0, 0, ENGINE_LENGTH * 0.5 + 0.4 + k * 0.4),
				HULL_DARK if k % 2 == 0 else HULL)
	var top := ENGINE_RADIUS * 1.2
	for k in 7:
		_box(Vector3(8.0, 7.0, 1.2), Vector3(-6.0, ENGINE_RADIUS + 2.5, -18.0 + k * 6.0), HULL_DARK, engine)
	_add_marker("spawn_cache", base + Vector3(4.0, top + 0.2, 0)).set_meta("loot_source", "relay")
	# The hatch at its foot, toward the valley.
	var hatch := base + Vector3(-6.0, 0, ENGINE_RADIUS + 2.0)
	_box(Vector3(5, 6, 1), hatch + Vector3(0, 3, 0), HULL_DARK)
	# The Engine still breathes a little warmth out of its hatch.
	_add_warmth(_ground(Vector2(hatch.x, hatch.z + 3.0)), HATCH)
	# The defence grid's boss, the Engine Sentinel, guards the hatch.
	var boss := _add_marker("spawn_boss", _ground(Vector2(hatch.x + 4.0, hatch.z + 7.0)))
	boss.set_meta("faction", "warden")
	boss.set_meta("boss", "sentinel")
	boss.set_meta("radius", SENTINEL_GROUND)
	for x: float in [-14.0, 0.0, 14.0]:
		_add_marker("spawn_cache", _ground(Vector2(base.x + x, base.z + ENGINE_RADIUS + 7.0))).set_meta("loot_source", "cache_core")
	for x: float in [-20.0, 20.0]:
		_bot_spot(_ground(Vector2(base.x + x, base.z + ENGINE_RADIUS + 12.0)), "warden", 4)
	_add_rocks(Vector2(base.x - 10.0, base.z + ENGINE_RADIUS + 16.0), 3)
	_add_rocks(Vector2(base.x + 12.0, base.z + ENGINE_RADIUS + 18.0), 2)


## The warm vents on the floor: a grate, low enough to walk over.
func _build_vents() -> void:
	for vent: Dictionary in VENTS:
		var z: float = vent["z"]
		var at := _ground(Vector2(centre(z) + float(vent["off"]), z))
		_vents.append(at)
		_add_warmth(at, VENT)


## The warm beacons: a mast to stand by (no random numbers, so the layout
## around them is the same as without them).
func _build_beacons() -> void:
	for beacon: Dictionary in BEACONS:
		var z: float = beacon["z"]
		var at := _ground(Vector2(centre(z) + float(beacon["off"]), z))
		_beacons.append(at)
		var marker := _add_marker("beacon", at + Vector3(0, 0.1, 0))
		marker.set_meta("name", beacon["name"])
		marker.set_meta("radius", BEACON["radius"])
		_add_warmth(at, BEACON)
		_box(Vector3(0.5, 5.0, 0.5), at + Vector3(0, 2.5, 0), STEEL)


## A place that gives body heat back (`WorldDef`'s "The cold").
func _add_warmth(at: Vector3, kind: Dictionary) -> void:
	var marker := _add_marker("warmth", at + Vector3(0, 0.1, 0))
	marker.set_meta("radius", kind["radius"])
	marker.set_meta("warmth", kind["warmth"])


func _bot_spot(at: Vector3, faction: String, rank: int) -> void:
	_bot_spots.append({"at": at, "faction": faction, "rank": rank, "order": _bot_spots.size()})


func _place_bot_spots() -> void:
	_bot_spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rank < b.rank or (a.rank == b.rank and a.order < b.order))
	for spot in _bot_spots:
		_add_marker("spawn_bot", spot.at).set_meta("faction", spot.faction)


func _cylinder(parent: Node3D, radius: float, length: float, at: Vector3, material: Material) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = length
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = at
	col.rotation.x = PI / 2.0
	parent.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation.x = PI / 2.0
	parent.add_child(node)


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


## A solid box. With a `parent` it is a part of that body (in its space),
## otherwise a body of its own in the map.
func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> Node3D:
	var body: Node3D = parent
	var offset := at
	if parent == null or not parent is StaticBody3D:
		var own := StaticBody3D.new()
		own.collision_layer = Actor.LAYER_WORLD
		own.collision_mask = 0
		own.position = at
		(parent if parent != null else nav_region).add_child(own)
		body = own
		offset = Vector3.ZERO
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = offset
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	mesh_node.position = offset
	body.add_child(mesh_node)
	return body


# --- Dressing ---------------------------------------------------------------------

## Everything below is decoration: no collision, nothing the game depends on.
func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	_dress_ice(art)
	_dress_huts(art)
	_dress_warmth(art)
	_dress_beacons(art)
	_dress_engine(art)
	_dress_listening_posts(art)
	_dress_horizon(art)


## The frozen river and lake: plates of clear ice over the channel, cracked.
func _dress_ice(art: Node3D) -> void:
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.42, 0.6, 0.72)
	ice.roughness = 0.12
	ice.metallic_specular = 0.8
	var deep := StandardMaterial3D.new()
	deep.albedo_color = Color(0.3, 0.48, 0.6)
	deep.roughness = 0.08
	var crack := StandardMaterial3D.new()
	crack.albedo_color = Color(0.9, 0.97, 1.0)
	crack.roughness = 0.5
	var z := 290.0
	while z > -40.0:
		var c := centre(z - 3.0)
		var plate := _visual_box(Vector3(18.0, 0.1, 6.4), Vector3(c, terrain.height_at(c, z - 3.0) + 0.04, z - 3.0), ice)
		plate.rotation = Vector3(atan2(floor_at(z) - floor_at(z - 6.0), 6.0), atan2(centre(z - 6.0) - centre(z), -6.0) + PI, 0)
		art.add_child(plate)
		if _art_rng.randf() < 0.35:
			var line := _visual_box(Vector3(_art_rng.randf_range(4, 9), 0.12, 0.12),
					Vector3(c + _art_rng.randf_range(-5, 5), terrain.height_at(c, z - 3.0) + 0.06, z - 3.0), crack)
			line.rotation.y = _art_rng.randf() * TAU
			art.add_child(line)
		z -= 6.0
	var lake_at := Vector3(centre(LAKE_Z), floor_at(LAKE_Z) - 0.56, LAKE_Z)
	var lake := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.1
	disc.radial_segments = 14
	disc.material = deep
	lake.mesh = disc
	lake.position = lake_at
	lake.scale = Vector3(LAKE_RADIUS.x * 1.02, 1.0, LAKE_RADIUS.y * 1.02)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(lake)
	# The thin ice in the middle: darker, clearer ice you can see the water
	# through, so it is read before it is driven onto.
	var thin := StandardMaterial3D.new()
	thin.albedo_color = Color(0.13, 0.25, 0.36)
	thin.roughness = 0.03
	thin.metallic_specular = 1.0
	var black := MeshInstance3D.new()
	black.mesh = disc.duplicate()
	(black.mesh as CylinderMesh).material = thin
	(black.mesh as CylinderMesh).radial_segments = 24
	black.position = lake_at + Vector3(0.0, 0.015, 0.0)
	black.scale = Vector3(LAKE_RADIUS.x * THIN_ICE, 1.0, LAKE_RADIUS.y * THIN_ICE)
	black.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(black)
	for k in 24:
		var a := _art_rng.randf() * TAU
		var r := _art_rng.randf_range(0.1, 0.9)
		var line := _visual_box(Vector3(_art_rng.randf_range(5, 14), 0.12, 0.14),
				lake_at + Vector3(cos(a) * r * LAKE_RADIUS.x, 0.06, sin(a) * r * LAKE_RADIUS.y), crack)
		line.rotation.y = _art_rng.randf() * TAU
		art.add_child(line)


func _visual_box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	node.mesh = mesh
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A heater glowing at the back of every hut, its grille lit, and a vent
## pipe on the roof.
func _dress_huts(art: Node3D) -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.5, 0.15)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.42, 0.1)
	glow.emission_energy_multiplier = 4.0
	for hut in _huts:
		var turn := Basis(Vector3.UP, PI / 2.0 * float(hut["facing"]))
		var base: Vector3 = hut["at"]
		for k in 4:
			var bar := _visual_box(Vector3(1.0, 0.1, 0.05), base + turn * Vector3(0, 0.4 + k * 0.25, -1.43), glow)
			bar.basis = turn
			art.add_child(bar)
		var lamp := Look.lamp(Color(1.0, 0.5, 0.2), 4.0, 9.0)
		lamp.position = base + turn * Vector3(0, 1.4, 0)
		art.add_child(lamp)
		var pipe := Look.prop("Pipe_1.glb", 2.4, 0.6)
		pipe.position = base + turn * Vector3(2.0, float(hut["height"]) + 0.3, -1.8)
		art.add_child(pipe)


## The vents glow orange under their grates and steam, and the camp at the
## river mouth has a fire drum: you can see warmth from a way off.
func _dress_warmth(art: Node3D) -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.45, 0.12)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.4, 0.1)
	glow.emission_energy_multiplier = 3.0
	var grate := StandardMaterial3D.new()
	grate.albedo_color = Color(0.12, 0.13, 0.15)
	grate.metallic = 0.6
	grate.roughness = 0.5
	for at in _vents:
		art.add_child(_visual_box(Vector3(2.2, 0.06, 2.2), at + Vector3(0, 0.04, 0), glow))
		for k in 5:
			art.add_child(_visual_box(Vector3(2.4, 0.12, 0.14), at + Vector3(0, 0.1, -0.9 + k * 0.45), grate))
		var lamp := Look.lamp(Color(1.0, 0.5, 0.2), 2.5, 7.0)
		lamp.position = at + Vector3(0, 0.8, 0)
		art.add_child(lamp)
		art.add_child(_steam(at + Vector3(0, 0.2, 0), 1.0))
	# The camp: a fire drum, glowing through its holes.
	var drum := MeshInstance3D.new()
	var body := CylinderMesh.new()
	body.top_radius = 0.45
	body.bottom_radius = 0.45
	body.height = 0.9
	body.material = grate
	drum.mesh = body
	drum.position = _camp + Vector3(0, 0.45, 0)
	art.add_child(drum)
	art.add_child(_visual_box(Vector3(0.7, 0.1, 0.7), _camp + Vector3(0, 0.92, 0), glow))
	var fire := Look.lamp(Color(1.0, 0.5, 0.18), 5.0, 12.0)
	fire.position = _camp + Vector3(0, 1.6, 0)
	art.add_child(fire)
	var flicker := create_tween().set_loops()
	flicker.tween_property(fire, "light_energy", 3.6, 0.22)
	flicker.tween_property(fire, "light_energy", 5.2, 0.31)
	art.add_child(_steam(_camp + Vector3(0, 1.0, 0), 0.6))


## Each beacon wears a heat lamp at the top of its mast and a ring of light
## on the snow round it, the size of the ground you hold to power it up.
func _dress_beacons(art: Node3D) -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.62, 0.25)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.2)
	glow.emission_energy_multiplier = 2.5
	var radius: float = BEACON["radius"]
	for at in _beacons:
		art.add_child(_visual_box(Vector3(1.1, 0.5, 1.1), at + Vector3(0, 5.2, 0), glow))
		var lamp := Look.lamp(Color(1.0, 0.6, 0.25), 4.0, radius * 2.0)
		lamp.position = at + Vector3(0, 5.6, 0)
		art.add_child(lamp)
		for k in 16:
			var a := TAU * k / 16.0
			var dash := _visual_box(Vector3(0.3, 0.05, radius * TAU / 32.0),
					at + Vector3(cos(a) * radius, 0.08, sin(a) * radius), glow)
			dash.rotation.y = -a
			art.add_child(dash)
		art.add_child(_steam(at + Vector3(0, 5.6, 0), 0.5))


## Warm air rising off something into the cold: soft white puffs.
func _steam(at: Vector3, size: float) -> CPUParticles3D:
	var puffs := CPUParticles3D.new()
	puffs.position = at
	puffs.amount = 14
	puffs.lifetime = 3.2
	puffs.local_coords = false
	puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puffs.emission_sphere_radius = 0.6 * size
	puffs.direction = Vector3.UP
	puffs.spread = 12.0
	puffs.gravity = Vector3(0.4, 0.5, 0)
	puffs.initial_velocity_min = 0.6
	puffs.initial_velocity_max = 1.1
	puffs.scale_amount_min = 1.0 * size
	puffs.scale_amount_max = 2.2 * size
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	puffs.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(0.95, 0.97, 1.0, 0.32))
	puffs.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _puff_texture()
	quad.material = mat
	puffs.mesh = quad
	return puffs


## A soft round puff, made once.
func _puff_texture() -> Texture2D:
	if not _shared.has("puff"):
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = ramp
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_shared["puff"] = tex
	return _shared["puff"]


## The Engine's one light still blinks over its hatch.
func _dress_engine(art: Node3D) -> void:
	var teal := StandardMaterial3D.new()
	teal.albedo_color = Color(0.3, 1.0, 0.9)
	teal.emission_enabled = true
	teal.emission = Color(0.2, 1.0, 0.85)
	teal.emission_energy_multiplier = 6.0
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.material = teal
	bulb.mesh = sphere
	bulb.position = _engine_at + Vector3(-6.0, 6.8, ENGINE_RADIUS + 2.6)
	art.add_child(bulb)
	var light := Look.lamp(Color(0.2, 1.0, 0.85), 5.0, 22.0)
	light.position = bulb.position + Vector3(0, -0.3, 1.5)
	art.add_child(light)
	var blink := create_tween().set_loops()
	blink.tween_property(light, "light_energy", 0.3, 0.15).set_delay(1.6)
	blink.tween_property(light, "light_energy", 5.0, 0.15)


func _dress_listening_posts(art: Node3D) -> void:
	for spot: Dictionary in LISTENING:
		var at := rim_point(spot["z"], spot["side"])
		var top := _ground(at) + Vector3(0, 3.8, 0)
		var dish := Look.prop("Antenna_2.glb", 2.2, 0.5)
		dish.position = top + Vector3(1.4, 0, 1.0)
		dish.rotation.y = -float(spot["side"]) * PI / 2.0
		art.add_child(dish)


## Ice peaks beyond the rims, fading into the haze.
func _dress_horizon(art: Node3D) -> void:
	for i in 26:
		var z := lerpf(300.0, -300.0, float(i) / 25.0) + _art_rng.randf_range(-10.0, 10.0)
		for side: float in [-1.0, 1.0]:
			var size := Vector3(_art_rng.randf_range(30, 60), _art_rng.randf_range(40, 90), _art_rng.randf_range(30, 60))
			var peak := MeshInstance3D.new()
			var mesh := PrismMesh.new()
			mesh.size = size
			mesh.left_to_right = _art_rng.randf_range(0.25, 0.75)
			mesh.material = ICE_WALL
			peak.mesh = mesh
			var x := centre(z) + side * (half_width(z) + RIM_TO + _art_rng.randf_range(60.0, 110.0))
			peak.position = Vector3(x, terrain.height_at(x, z) + size.y * 0.5 - 6.0, z)
			peak.rotation.y = _art_rng.randf() * TAU
			peak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			art.add_child(peak)
