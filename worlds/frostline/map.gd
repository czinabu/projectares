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
##
## It stands on the Glacier planet type (DESIGN.md "Planet kit"): its sky
## and light, its snow, ice and banded rock on the ground, and its land and
## shards past the valley's walls out to the horizon, all view only.

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
## Where the Stilled Engine lies across the valley head, turned a little
## off square, on a bed of ground levelled for it (`engine_bed`).
const ENGINE_Z := -235.0
const ENGINE_RADIUS := 22.0
const ENGINE_LENGTH := 76.0
const ENGINE_YAW := PI / 2.0 + 0.12
## How far its axis stands over the bed: most of the drum is out of the ice.
const ENGINE_AXIS := ENGINE_RADIUS * 0.2
## The bed reaches this far past the drum, then blends back into the valley
## over the skirt.
const ENGINE_PAD := 6.0
const ENGINE_SKIRT := 18.0
## The Engine's inside (DESIGN.md "The Engine's inside"), measured in the
## drum's own frame (`engine_frame`): x across it (+ toward the glacier, the
## hatch on -x), y up from its axis, z along it (+ east). The hull is
## `ENGINE_HULL` thick, its outside where the old solid drum's was.
const ENGINE_HULL := 1.2
const ENGINE_SEGMENTS := 40
## The Drum Hall's floor is the bed, about 40 m across and 75 m long.
const HALL_FLOOR := -ENGINE_AXIS
## The hatch: a doorway through the hull on the valley side, floor to lintel.
const HATCH_Z := -12.0
const HATCH_WIDTH := 9.0
const HATCH_HEIGHT := 7.6
## Catwalks along both walls, this high over the floor, and how wide.
const CATWALK_UP := 8.0
const CATWALK_WIDTH := 3.2
## The Shaft: a well in the hall's east end with two switchback ramps
## (`SHAFT_RAMP` wide) down `SHAFT_DEPTH` metres, a landing halfway, to a
## floor where the way on to the Coil Galleries waits, sealed for now.
const SHAFT_FROM_Z := 6.0
const SHAFT_TO_Z := 31.0
const SHAFT_HALF := 11.0
const SHAFT_DEPTH := 26.0
const SHAFT_RAMP := 9.0
const SHAFT_LANDING := 4.0
## The Shaft's foot runs on west under the hall's floor, so the second ramp
## comes down into open floor rather than at a wall.
const SHAFT_FOOT := 7.0
## The valley's ground is dropped out of the way under the Shaft this far
## past its walls, so the heightfield's slope stays under the hall's floor.
const SHAFT_CLEAR := 3.0
## The Coil Galleries, on the Shaft's floor east of it, under the valley
## floor: two long halls 14 m across joined by three cross halls (a loop to
## fight round), coil alcoves off their outer walls and a channel of frozen
## coolant down the south hall. Each room is [x0, x1, z0, z1] in the drum's
## frame, all `GALLERY_UP` high.
const GALLERY_FLOOR := HALL_FLOOR - SHAFT_DEPTH
const GALLERY_UP := 9.0
const GALLERY_ROOMS := [
	[-5.0, 5.0, 31.0, 38.0],
	[-6.0, 6.0, 38.0, 48.0],
	[-6.0, 6.0, 69.0, 79.0],
	[-6.0, 6.0, 100.0, 110.0],
	[6.0, 20.0, 38.0, 110.0],
	[-20.0, -6.0, 38.0, 110.0],
	[20.0, 26.0, 52.0, 60.0],
	[20.0, 26.0, 84.0, 92.0],
	[-26.0, -20.0, 52.0, 60.0],
	[-26.0, -20.0, 84.0, 92.0],
	[-5.0, 5.0, 110.0, 114.0],
]
## The frozen coolant down the south gallery: the cold bites hardest there.
## A raised walkway along the north gallery's outer wall ([x0, x1, z0, z1]
## of its deck), `WALKWAY_UP` over the floor and reached by a ramp at each
## end, the galleries' high ground (like the hall's catwalks, a way round,
## not the way through).
const WALKWAY := [16.0, 20.0, 47.0, 101.0]
const WALKWAY_UP := 4.5
const WALKWAY_RAMP := 8.0
const GALLERY_COOLANT := [-15.0, -11.0, 40.0, 108.0]
## The Descent: a well past the galleries' east end, three ramps
## (`DESCENT_LANE` wide, each down a third of `DESCENT_DROP`) switching back
## along it between landings, to its foot, where the cable lift stops and the
## door to the Heart stands open in the east wall.
const DESCENT_FROM_Z := 114.0
const DESCENT_TO_Z := 176.0
const DESCENT_HALF := 11.0
const DESCENT_LANE := 10.0
const DESCENT_DROP := 40.0
const DESCENT_LANDING := 6.0
const DESCENT_FOOT := 18.0
const DESCENT_FLOOR := GALLERY_FLOOR - DESCENT_DROP
## How far the well's roof stands over the galleries' roof.
const DESCENT_ROOF := 3.0
## Where the collision ground is cut away ([x0, x1, z0, z1]) so the way on
## from the Shaft's foot passes the edge of the ground dropped under it. It is
## all under the hall's floor, so nobody can reach the hole from above.
const ENGINE_HOLE := [-6.5, 6.5, 32.5, 36.3]
## The cable lift (`WorldDef`'s "lift_stop"): its stop in the hall, its stop
## at the Descent's foot, and the switch beside that one that powers it
## (x, z in the drum's frame).
const LIFT_ID := "engine"
const LIFT_TOP := Vector2(15.5, -8.0)
const LIFT_FOOT := Vector2(-7.0, 169.0)
const LIFT_SWITCH := Vector2(-9.0, 174.0)
const LIFT_STOP := 2.6
const LIFT_CAGE := 6.0
## The Heart (DESIGN.md "The Engine's inside"): through a door
## `HEART_DOOR` wide in the Descent's east wall, a short way on
## (`HEART_WAY` long) to a round chamber `HEART_RADIUS` round its middle at
## `HEART_Z` and `HEART_UP` high, on the Descent's floor. A balcony runs
## round it `HEART_BALCONY` up (`HEART_LEDGE` deep), reached by a ramp up
## each side; four coolant pylons stand round the middle, the frozen core
## hangs over it, and the vault is in the far wall.
const HEART_KEEPER := "heart_warden"
const HEART_DOOR := 10.0
const HEART_DOOR_UP := 8.0
const HEART_WAY := 6.0
const HEART_RADIUS := 34.0
const HEART_Z := DESCENT_TO_Z + 1.0 + HEART_WAY + HEART_RADIUS
const HEART_UP := 34.0
const HEART_SEGMENTS := 40
const HEART_BALCONY := 9.0
const HEART_LEDGE := 3.5
## The pylons, at (+-`HEART_PYLON`, +-`HEART_PYLON`) off the middle, and
## the purge lanes they vent across the floor (`WorldDef`'s "purge"): the
## two diagonals together, then the two rows together.
const HEART_PYLON := 12.0
const PYLON_RADIUS := 1.8
const PURGE_WIDTH := 5.0
const PURGE_DAMAGE := 26.0
## The wall sockets the Heart Warden calls Wardens out of, by their angle
## from the far wall (the door is at 180).
const HEART_SOCKETS := [45.0, -45.0, 135.0, -135.0]
## How far round its middle the Heart Warden keeps its ground, and seconds
## before it wakes again after it falls.
const HEART_GROUND := 22.0
const HEART_RESPAWN := 600.0
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
## The planet's land past the map's edge rises this far, to meet the
## heightfield's mountains there (DESIGN.md "Planet kit").
const FAR_RIM := 80.0
## The planet's props stand this far past the rim's top, or further.
const PROPS_PAST_RIM := 24.0


## The ground the Engine lies on, levelled flat.
static func engine_bed() -> float:
	return floor_at(ENGINE_Z)


## The drum's own frame: its axis along local z, at `ENGINE_AXIS` over the bed.
static func engine_frame() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, ENGINE_YAW), Vector3(centre(ENGINE_Z), engine_bed() + ENGINE_AXIS, ENGINE_Z))


## A point in the drum's own frame.
static func engine_local(pos: Vector3) -> Vector3:
	if not _engine_known:
		_engine_inverse = engine_frame().affine_inverse()
		_engine_known = true
	return _engine_inverse * pos


static var _engine_inverse := Transform3D.IDENTITY
static var _engine_known := false


## Whether a point is inside the Engine: in the Drum Hall, down the Shaft,
## in the Coil Galleries or down the Descent.
static func inside_engine(pos: Vector3) -> bool:
	var p := engine_local(pos)
	var inner := ENGINE_RADIUS - ENGINE_HULL
	if absf(p.z) < ENGINE_LENGTH * 0.5 and p.x * p.x + p.y * p.y < inner * inner and p.y > HALL_FLOOR - 0.5:
		return true
	if absf(p.x) < SHAFT_HALF and p.z > SHAFT_FROM_Z - SHAFT_FOOT and p.z < SHAFT_TO_Z \
			and p.y > GALLERY_FLOOR - 0.5 and p.y <= HALL_FLOOR - 0.5:
		return true
	if p.y > GALLERY_FLOOR - 0.5 and p.y <= GALLERY_FLOOR + GALLERY_UP:
		for room: Array in GALLERY_ROOMS:
			if p.x > room[0] and p.x < room[1] and p.z > room[2] and p.z < room[3]:
				return true
	if absf(p.x) < DESCENT_HALF and p.z > DESCENT_FROM_Z and p.z < DESCENT_TO_Z \
			and p.y > DESCENT_FLOOR - 0.5 and p.y < GALLERY_FLOOR + GALLERY_UP + DESCENT_ROOF:
		return true
	return in_heart(pos)


## Whether a point is in the Heart or the way on to it from the Descent.
static func in_heart(pos: Vector3) -> bool:
	var p := engine_local(pos)
	if p.y <= DESCENT_FLOOR - 0.5 or p.y >= DESCENT_FLOOR + HEART_UP:
		return false
	if Vector2(p.x, p.z - HEART_Z).length() < HEART_RADIUS:
		return true
	return absf(p.x) < HEART_DOOR * 0.5 and p.z >= DESCENT_TO_Z - 0.5 and p.z <= HEART_Z


## Whether a point stands on the galleries' frozen coolant.
static func on_coolant(pos: Vector3) -> bool:
	var p := engine_local(pos)
	var c: Array = GALLERY_COOLANT
	return p.x > c[0] and p.x < c[1] and p.z > c[2] and p.z < c[3] \
			and p.y > GALLERY_FLOOR - 0.5 and p.y < GALLERY_FLOOR + 3.0


## How far down the Engine a point is: 0 in the hall, 1 at the Shaft's foot
## and in the galleries, 2 down the Descent, 3 in the Heart.
static func engine_depth(pos: Vector3) -> int:
	var p := engine_local(pos)
	if p.y > HALL_FLOOR - 2.0:
		return 0
	if p.y > GALLERY_FLOOR - 2.0:
		return 1
	if p.z > DESCENT_TO_Z:
		return 3
	return 2


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
## Ruined shacks on the shelves, between the huts: four walls with a doorway
## toward the valley, one wall broken open and the front of the roof fallen
## in. Out of the wind but unheated, so they chill you slowly instead of
## hurting (`WorldDef.indoor_chill`), and a whiteout leaks in.
const RUINS := [
	{"z": 150.0, "side": 1.0},
	{"z": 30.0, "side": -1.0},
	{"z": -55.0, "side": 1.0},
	{"z": -120.0, "side": -1.0},
]
## The rooms (`WorldDef`'s "indoors" markers): how much a heated hut warms
## anywhere inside (gentler than standing at its heater, so you thaw over a
## few seconds), and how much of a whiteout's extra cold gets into an
## open-fronted hut and into a broken ruin.
const HUT_HEAT := 5.0
const HUT_LEAK := 0.5
const RUIN_LEAK := 0.6
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
## The planet the map stands on (`WorldDef.planet_type`), set before it
## enters the tree; a map made on its own (as the checks do) takes the
## Glacier.
var planet: PlanetType
## The valley floor's rocks wear the planet's ground, so their tops hold
## snow and their sides show the banded rock of the walls.
var ROCK: Material

@onready var ICE_WALL := Look.surface("concrete", {"tint": Color(0.36, 0.5, 0.66), "snow": 0.35, "grime": 0.0,
		"scale": 0.06, "rough_mult": 0.4})
@onready var STEEL := Look.surface("metal", {"tint": Color(0.42, 0.46, 0.52), "snow": 0.8, "grime": 0.5, "scale": 0.3,
		"window_glow": Color(1.0, 0.6, 0.3), "lit_windows": 0.15})
@onready var HULL := Look.surface("metal", {"tint": Color(0.34, 0.38, 0.44), "snow": 0.45, "grime": 0.6, "scale": 0.08})
@onready var HULL_DARK := Look.surface("metal", {"tint": Color(0.22, 0.25, 0.3), "snow": 0.4, "grime": 0.7, "scale": 0.1})
@onready var DECK := Look.surface("metal", {"tint": Color(0.3, 0.33, 0.38), "snow": 0.25, "grime": 0.55, "scale": 0.15})
@onready var FROST := Look.surface("metal", {"tint": Color(0.78, 0.86, 0.95), "snow": 1.0, "grime": 0.0, "scale": 0.3})
@onready var COOLANT := Look.surface("metal", {"tint": Color(0.5, 0.78, 0.92), "snow": 0.6, "grime": 0.0, "scale": 0.2,
		"rough_mult": 0.15})


func _ready() -> void:
	if planet == null:
		planet = PlanetTypes.get_type("glacier")
	ROCK = Planet.ground_material(planet)
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
	_build_ruins()
	_build_listening_posts()
	_build_floor()
	_build_engine()
	_build_vents()
	_build_beacons()
	_build_deep_beacon()
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
		_ground_shared["collision"] = _cut_holes(terrain.collision_data(), int(terrain.extent()) + 1)
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
	_light_lift()
	_light_heart()
	# The snow blows round whoever is looking, not over the whole valley.
	var camera := get_viewport().get_camera_3d()
	if camera != null and is_instance_valid(_weather):
		# None falls inside the Engine.
		_weather.visible = not inside_engine(camera.global_position)
		_weather.global_position = Vector3(camera.global_position.x, camera.global_position.y - 8.0,
				camera.global_position.z)


func _build_environment() -> void:
	# A war that ended long ago: the Glacier's low bright sun on the snow,
	# long blue shadows, and clear air down the valley. The only warm colours
	# are the heaters' and the Engine's one teal light. The planet's storm
	# mood is the heart of a whiteout (DESIGN.md "Frostline"): the sun gone
	# to a pale smear, a body a shape at 30 m and gone by 70 m.
	Planet.atmosphere(self, planet)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		# A low sun throws long shadows: reach far enough to keep them.
		Look.GameSettings.fit_sun(sun, 220.0)
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
	return _engine_ground(x, z, h)


## The Engine's bed: flat under the drum and round it, blending back into
## the valley over the skirt, and dropped away under the Shaft (its floor
## and walls are the Engine's own; the drop stays under the hall's floor).
static func _engine_ground(x: float, z: float, h: float) -> float:
	var p := engine_local(Vector3(x, 0.0, z))
	if absf(p.x) < SHAFT_HALF + SHAFT_CLEAR and p.z > SHAFT_FROM_Z - SHAFT_FOOT - SHAFT_CLEAR \
			and p.z < SHAFT_TO_Z + SHAFT_CLEAR:
		return engine_bed() - SHAFT_DEPTH
	var across := maxf(absf(p.x) - ENGINE_RADIUS - ENGINE_PAD, 0.0)
	var along := maxf(absf(p.z) - ENGINE_LENGTH * 0.5 - ENGINE_PAD, 0.0)
	return lerpf(engine_bed(), h, smoothstep(0.0, ENGINE_SKIRT, Vector2(across, along).length()))


func _build_ground() -> void:
	terrain = Terrain.new()
	terrain.name = "Ground"
	terrain.cell = CELL
	terrain.side = SIDE
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		terrain.shape(_height)
		_ground_shared["collision"] = _cut_holes(terrain.collision_data(), int(terrain.extent()) + 1)
		_ground_shared["heights"] = terrain.heights
	var collision: PackedFloat32Array = _ground_shared["collision"]
	terrain.heights = _ground_shared["heights"]
	_ground_lock.unlock()
	terrain.build(Planet.ground_material(planet), collision)
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


## Cuts the collision ground away over `ENGINE_HOLE` (a heightfield's hole
## is a NaN height), so the way on from the Shaft's foot to the galleries
## passes the edge of the ground dropped under the Shaft. Only the collision:
## the drawn ground there is under the hall's floor.
static func _cut_holes(collision: PackedFloat32Array, width: int) -> PackedFloat32Array:
	var half := (width - 1) * 0.5
	var hole: Array = ENGINE_HOLE
	var frame := engine_frame()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector2 in [Vector2(hole[0], hole[2]), Vector2(hole[1], hole[2]), Vector2(hole[0], hole[3]),
			Vector2(hole[1], hole[3])]:
		var at := frame * Vector3(corner.x, 0.0, corner.y)
		low = Vector2(minf(low.x, at.x), minf(low.y, at.z))
		high = Vector2(maxf(high.x, at.x), maxf(high.y, at.z))
	for iz in range(maxi(int(floorf(low.y + half)), 0), mini(int(ceilf(high.y + half)) + 1, width)):
		for ix in range(maxi(int(floorf(low.x + half)), 0), mini(int(ceilf(high.x + half)) + 1, width)):
			var p := engine_local(Vector3(ix - half, 0.0, iz - half))
			if p.x > hole[0] and p.x < hole[1] and p.z > hole[2] and p.z < hole[3]:
				collision[iz * width + ix] = NAN
	return collision


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
		_add_depot(_ground(at), Vector2(side, 0.0))
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
			_bot_spot(_ground(at + Vector2(facing * 3.0, (k * 2 - 1) * 4.0)), "warden", 0 if k == 0 else 3,
					"post " + str(post["name"]), 13.0)


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
	_add_room(base, hut.rotation.y, Vector3(6.1, height, 5.1), HUT_HEAT, HUT_LEAK)


## Ruined shacks on the shelves (`RUINS`): out of the wind, no heater.
func _build_ruins() -> void:
	for ruin: Dictionary in RUINS:
		var at := shelf_point(ruin["z"], ruin["side"])
		var base := _ground(at)
		var shack := Node3D.new()
		shack.position = base
		# The doorway faces the valley (local +Z, turned like a hut).
		shack.rotation.y = PI / 2.0 * -float(ruin["side"])
		nav_region.add_child(shack)
		for part: Array in [
				# The back wall and the whole left wall.
				[Vector3(7.0, 3.2, 0.3), Vector3(0, 1.6, -3.0)],
				[Vector3(0.3, 3.2, 6.0), Vector3(-3.5, 1.6, 0)],
				# The right wall, broken open toward the front.
				[Vector3(0.3, 1.2, 6.0), Vector3(3.5, 0.6, 0)],
				[Vector3(0.3, 2.0, 2.8), Vector3(3.5, 2.2, -1.6)],
				# The front wall either side of the doorway.
				[Vector3(2.6, 3.2, 0.3), Vector3(-2.2, 1.6, 3.0)],
				[Vector3(2.6, 3.2, 0.3), Vector3(2.2, 1.6, 3.0)],
				# What is left of the roof, the front fallen in.
				[Vector3(7.4, 0.3, 4.2), Vector3(0, 3.35, -1.1)]]:
			_box(part[0], part[1], STEEL, shack)
		_add_room(base, shack.rotation.y, Vector3(6.7, 3.2, 5.7), 0.0, RUIN_LEAK)
		# Something worth the look, in the back corner.
		_add_marker("spawn_cache", base + shack.basis * Vector3(-2.4, 0.1, -2.0))


## A room out of the open cold (`WorldDef`'s "indoors"): a box `size` big
## standing at `at`, turned by `yaw`.
func _add_room(at: Vector3, yaw: float, size: Vector3, heat: float, leak: float) -> void:
	var room := _add_marker("indoors", at)
	room.rotation.y = yaw
	room.set_meta("size", size)
	room.set_meta("heat", heat)
	room.set_meta("leak", leak)


## Old listening posts on the rims: a bunker and a mast, with the rooftop
## haul on top. Wardens keep watch from some of them.
func _build_listening_posts() -> void:
	for i in LISTENING.size():
		var spot: Dictionary = LISTENING[i]
		var at := rim_point(spot["z"], spot["side"])
		var base := _ground(at)
		_box(Vector3(5, 4, 5), base + Vector3(0, 1.8, 0), STEEL)
		_box(Vector3(1, 8, 1), base + Vector3(0, 7.8, 0), STEEL)
		# The dish on the bunker's roof.
		var top := base + Vector3(0, 3.8, 0)
		SolidProp.place(nav_region, "Antenna_2.glb", 2.2, top + Vector3(1.4, 0, 1.0), -float(spot["side"]) * PI / 2.0, 0.5)
		_add_marker("spawn_cache", base + Vector3(0, 4.0, 0)).set_meta("loot_source", "rooftop")
		if i % 2 == 0:
			_bot_spot(_ground(at + Vector2(-float(spot["side"]) * 4.0, 0)), "warden", 2, "listening %d" % i, 8.0)


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
	# Four dens, each pocket at least 85 m from the next and from any
	# Warden's (DESIGN.md "Enemy layout": you never pull two at once).
	var dens: Array[float] = [100.0, 15.0, -75.0, LAKE_Z + LAKE_RADIUS.y]
	for k in dens.size():
		var z := dens[k]
		var side := 1.0 if k % 2 == 0 else -1.0
		var w := half_width(z) * (0.6 if absf(z - LAKE_Z) > LAKE_RADIUS.y else 0.95)
		# A pack of three to a den, close together, so they set out as one.
		var den := Vector2(centre(z) + side * w, z)
		for p in 3:
			_bot_spot(_ground(den + Vector2(-side * 3.0 * p, (p - 1) * 3.0)), "feral", 1, "den %d" % k, 14.0)


func _add_rocks(at: Vector2, count: int) -> void:
	var shapes := [Vector3(3, 1.6, 2.2), Vector3(5, 2.4, 3), Vector3(2, 1.2, 2)]
	for k in count:
		var size: Vector3 = shapes[(k + int(absf(at.x))) % 3]
		var spot := at + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5))
		var rock := _box(size + Vector3(0, 0.6, 0), _ground(spot) + Vector3(0, size.y * 0.5 - 0.3, 0), ROCK)
		rock.rotation = Vector3(0, _rng.randf() * TAU, _rng.randf_range(-0.08, 0.08))


## The Stilled Engine: a colossal drum lying across the valley head, ribbed
## and finned, and hollow (DESIGN.md "The Engine's inside"). Its back is the
## relay's old perch, the richest cache outside, reached only by flight; the
## foot of it is the core, with the core's caches round its hatch and the
## Engine Sentinel on guard. Through the hatch is the Drum Hall, and in the
## hall's east end the Shaft goes down.
func _build_engine() -> void:
	var frame := engine_frame()
	var base := Vector3(frame.origin.x, engine_bed(), frame.origin.z)
	_engine_at = base
	var engine := StaticBody3D.new()
	engine.name = "Engine"
	engine.collision_layer = Actor.LAYER_WORLD
	engine.collision_mask = 0
	engine.transform = frame
	nav_region.add_child(engine)
	_build_hull(engine)
	_build_hall(engine)
	_build_lift_top(engine)
	_build_shaft(engine)
	_flush_parts(engine)
	# Each level is its own mesh, so the lamps of one light it alone (a
	# mesh takes only so many lights).
	_build_galleries(engine)
	_flush_parts(engine)
	_build_descent(engine)
	_flush_parts(engine)
	_build_heart(engine)
	_flush_parts(engine)
	# The intake rings at its east end and the cooling fins along its back.
	for k in 3:
		_cylinder(engine, ENGINE_RADIUS - 4.0 - k * 5.0, 1.2, Vector3(0, 0, ENGINE_LENGTH * 0.5 + 0.4 + k * 0.4),
				HULL_DARK if k % 2 == 0 else HULL)
	for k in 7:
		_box(Vector3(8.0, 7.0, 1.2), Vector3(-6.0, ENGINE_RADIUS + 2.5, -18.0 + k * 6.0), HULL_DARK, engine)
	_add_marker("spawn_cache", base + Vector3(4.0, ENGINE_RADIUS * 1.2 + 0.2, 0)).set_meta("loot_source", "relay")
	# The Engine still breathes a little warmth out of its hatch.
	_add_warmth(_ground(_flat(frame * Vector3(-ENGINE_RADIUS - 3.0, HALL_FLOOR, HATCH_Z))), HATCH)
	# The defence grid's boss, the Engine Sentinel, guards the hatch.
	var boss := _add_marker("spawn_boss", _ground(_flat(frame * Vector3(-ENGINE_RADIUS - 9.0, HALL_FLOOR, HATCH_Z + 4.0))))
	boss.set_meta("faction", "warden")
	boss.set_meta("boss", "sentinel")
	boss.set_meta("radius", SENTINEL_GROUND)
	for x: float in [-14.0, 0.0, 14.0]:
		_add_marker("spawn_cache", _ground(Vector2(base.x + x, base.z + ENGINE_RADIUS + 7.0))).set_meta("loot_source", "cache_core")
	for x: float in [-20.0, 20.0]:
		_bot_spot(_ground(Vector2(base.x + x, base.z + ENGINE_RADIUS + 12.0)), "warden", 4, "core", 14.0)
	_add_rocks(Vector2(base.x - 10.0, base.z + ENGINE_RADIUS + 16.0), 3)
	_add_rocks(Vector2(base.x + 12.0, base.z + ENGINE_RADIUS + 18.0), 2)


static func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


## A solid part of a body, in the body's own space, turned by `basis`. Its
## shape is drawn with every other part of the same material as one mesh
## (`_flush_parts`): the Engine is hundreds of parts.
func _part(body: StaticBody3D, size: Vector3, at: Vector3, material: Material, basis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = Transform3D(basis, at)
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch(material).append_from(mesh, 0, Transform3D(basis, at))


## Material -> SurfaceTool, filled by `_part` and `_tank`.
var _batches := {}


func _batch(material: Material) -> SurfaceTool:
	if not _batches.has(material):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[material] = tool
	return _batches[material]


## Turns every batch into one mesh on `body`.
func _flush_parts(body: Node3D) -> void:
	for material: Material in _batches:
		var mesh := (_batches[material] as SurfaceTool).commit()
		mesh.surface_set_material(0, material)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		body.add_child(node)
	_batches.clear()


## A slab from `low` to `high` (each (z, y) in the drum's frame, its top
## along that line) between `x_from` and `x_to`: a ramp.
func _slope(body: StaticBody3D, x_from: float, x_to: float, a: Vector2, b: Vector2, material: Material,
		thick := 0.8) -> void:
	var run := b - a
	var tilt := atan2(-run.y, run.x)
	var basis := Basis(Vector3.RIGHT, tilt)
	var mid := Vector3((x_from + x_to) * 0.5, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5)
	_part(body, Vector3(x_to - x_from, thick, run.length()), mid - basis.y * thick * 0.5, material, basis)


## The hull: a ring of panels round the axis (none under the bed), cut by
## the hatch, the six bands round it and the two end walls.
func _build_hull(engine: StaticBody3D) -> void:
	var step := TAU / ENGINE_SEGMENTS
	var mid := ENGINE_RADIUS - ENGINE_HULL * 0.5
	var width := step * ENGINE_RADIUS + 0.3
	for i in ENGINE_SEGMENTS:
		var a := -PI + (float(i) + 0.5) * step
		var up := cos(a) * mid
		if up < HALL_FLOOR - 2.5:
			continue
		var basis := Basis(Vector3.BACK, -a)
		var at := Vector3(sin(a), cos(a), 0.0) * mid
		if sin(a) < -0.5 and up < HALL_FLOOR + HATCH_HEIGHT - 2.0:
			# The hatch's opening, floor to lintel, on the valley side.
			var west := HATCH_Z - HATCH_WIDTH * 0.5 + ENGINE_LENGTH * 0.5
			var east := ENGINE_LENGTH * 0.5 - HATCH_Z - HATCH_WIDTH * 0.5
			_part(engine, Vector3(width, ENGINE_HULL, west), at + Vector3(0, 0, -ENGINE_LENGTH * 0.5 + west * 0.5), HULL, basis)
			_part(engine, Vector3(width, ENGINE_HULL, east), at + Vector3(0, 0, ENGINE_LENGTH * 0.5 - east * 0.5), HULL, basis)
		else:
			_part(engine, Vector3(width, ENGINE_HULL, ENGINE_LENGTH), at, HULL, basis)
		for k in 6:
			var z := -ENGINE_LENGTH * 0.4 + k * ENGINE_LENGTH * 0.16
			if up > HALL_FLOOR - 2.5:
				_part(engine, Vector3(width + 0.2, 1.4, 2.4), Vector3(sin(a), cos(a), 0.0) * (ENGINE_RADIUS + 0.7)
						+ Vector3(0, 0, z), HULL_DARK, basis)
	# The hatch's frame: a post either side and the lintel over it.
	var face := -(ENGINE_RADIUS - ENGINE_HULL * 0.5)
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(1.8, HATCH_HEIGHT + 1.0, 1.0),
				Vector3(face, HALL_FLOOR + (HATCH_HEIGHT + 1.0) * 0.5, HATCH_Z + side * (HATCH_WIDTH * 0.5 + 0.5)), HULL_DARK)
	_part(engine, Vector3(1.8, 1.0, HATCH_WIDTH + 2.0), Vector3(face, HALL_FLOOR + HATCH_HEIGHT + 0.5, HATCH_Z), HULL_DARK)
	# The end walls, laid in strips across the drum's round.
	var y := HALL_FLOOR - 1.0
	while y < ENGINE_RADIUS:
		var strip := minf(1.6, ENGINE_RADIUS - y)
		var level := y + strip * 0.5
		var rim := ENGINE_RADIUS - 0.3
		var half := sqrt(maxf(rim * rim - level * level, 0.0))
		for end: float in [-1.0, 1.0]:
			_part(engine, Vector3(half * 2.0, strip, ENGINE_HULL),
					Vector3(0, level, end * (ENGINE_LENGTH * 0.5 - ENGINE_HULL * 0.5)), HULL_DARK)
		y += strip


## How far across the hall is at a height `up` over its axis.
static func _hall_half(up: float) -> float:
	var inner := ENGINE_RADIUS - ENGINE_HULL
	return sqrt(maxf(inner * inner - up * up, 0.0))


## The Drum Hall: the bed floored over, catwalks along both walls with a
## ramp up at each end, the stator rings' frozen vanes overhead, fallen
## vanes and crates for cover, coolant tanks, the engine bay's heater, two
## caches and the hall's guards.
func _build_hall(engine: StaticBody3D) -> void:
	var f := HALL_FLOOR
	var half := _hall_half(f)
	var west := -ENGINE_LENGTH * 0.5
	var east := ENGINE_LENGTH * 0.5
	# The floor, round the Shaft's well.
	_part(engine, Vector3(half * 2.0, 1.0, SHAFT_FROM_Z - west), Vector3(0, f - 0.48, (west + SHAFT_FROM_Z) * 0.5), DECK)
	_part(engine, Vector3(half * 2.0, 1.0, east - SHAFT_TO_Z), Vector3(0, f - 0.48, (east + SHAFT_TO_Z) * 0.5), DECK)
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(half - SHAFT_HALF, 1.0, SHAFT_TO_Z - SHAFT_FROM_Z),
				Vector3(side * (half + SHAFT_HALF) * 0.5, f - 0.48, (SHAFT_FROM_Z + SHAFT_TO_Z) * 0.5), DECK)
	# Catwalks along both walls, a railing on the open side, ramps up.
	var walk := f + CATWALK_UP
	var out := _hall_half(walk + 2.0) - 0.4
	var inner := out - CATWALK_WIDTH
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(CATWALK_WIDTH, 0.4, ENGINE_LENGTH - 2.4), Vector3(side * (out - CATWALK_WIDTH * 0.5), walk - 0.2, 0), STEEL)
		for span: Vector2 in [Vector2(west + 1.2, -27.0), Vector2(-11.0, 7.0), Vector2(23.0, east - 1.2)]:
			_part(engine, Vector3(0.2, 1.1, span.y - span.x), Vector3(side * inner, walk + 0.55, (span.x + span.y) * 0.5), HULL_DARK)
		var lane := Vector2(side * (inner - 3.4), side * inner)
		_slope(engine, minf(lane.x, lane.y), maxf(lane.x, lane.y), Vector2(-26.0, walk), Vector2(-12.0, f), STEEL, 0.5)
		_slope(engine, minf(lane.x, lane.y), maxf(lane.x, lane.y), Vector2(8.0, f), Vector2(22.0, walk), STEEL, 0.5)
	# The stator rings: frozen vanes standing in from the hull overhead.
	for z: float in [-24.0, 0.0, 22.0]:
		for k in 9:
			var a := (float(k) - 4.0) * 0.3
			if cos(a) < 0.5:
				continue
			var vane_mid := ENGINE_RADIUS - ENGINE_HULL - 4.0
			_part(engine, Vector3(1.2, 8.0, 2.4), Vector3(sin(a), cos(a), 0.0) * vane_mid + Vector3(0, 0, z), STEEL,
					Basis(Vector3.BACK, -a))
	# Fallen vanes, low cover; crates and coolant tanks to stand behind.
	for spot: Array in HALL_VANES:
		var at: Vector2 = spot[0]
		_part(engine, Vector3(9.0, 1.4, 2.4), Vector3(at.x, f + 0.7, at.y), STEEL, Basis(Vector3.UP, spot[1]))
	for at: Vector2 in HALL_CRATES:
		_part(engine, Vector3(3.0, 2.6, 3.0), Vector3(at.x, f + 1.3, at.y), HULL_DARK)
	for at: Vector2 in HALL_TANKS:
		_tank(engine, Vector3(at.x, f, at.y))
	var frame := engine_frame()
	_add_warmth(frame * Vector3(-6.0, f, west + 4.0), ENGINE_BAY)
	_add_marker("spawn_cache", frame * Vector3(12.0, f + 0.1, west + 4.0)).set_meta("loot_source", "engine")
	_add_marker("spawn_cache", frame * Vector3(-(out - CATWALK_WIDTH * 0.5), walk + 0.1, east - 4.0)).set_meta("loot_source", "engine")
	for at: Vector3 in [Vector3(-4.0, f, -22.0), Vector3(8.0, f, -12.0), Vector3(2.0, f, -32.0),
			Vector3(out - CATWALK_WIDTH * 0.5, walk, 0.0)]:
		_guard(frame * (at + Vector3(0, 0.1, 0)), HALL_GUARD, "hall")


## Where the hall's fallen vanes lie (x, z in the drum's frame; a turn).
const HALL_VANES := [
	[Vector2(-8.0, -28.0), 0.4], [Vector2(6.0, -20.0), -0.9], [Vector2(-10.0, -4.0), 1.2],
	[Vector2(7.0, -2.0), 0.2], [Vector2(0.0, -14.0), -0.3], [Vector2(-3.0, 2.0), 0.8],
]
const HALL_CRATES := [Vector2(-12.0, -20.0), Vector2(14.0, -32.0), Vector2(4.0, -28.0), Vector2(-14.0, 2.0)]
const HALL_TANKS := [Vector2(-17.5, -33.0), Vector2(17.5, -33.0), Vector2(-17.5, -2.0), Vector2(17.5, 2.0)]
## How far each guard keeps from its post.
const HALL_GUARD := 12.0
## How near a player comes before a pocket inside the Engine wakes (metres):
## its walls hide it from further off.
const ENGINE_WAKE := 50.0
## The lift switch's own guards stay close by it.
const SWITCH_GUARDS := [Vector2(-4.0, 173.5), Vector2(-6.5, 175.0)]
const SWITCH_GUARD := 5.0
const SHAFT_GUARD := 9.0
## The Engine's warm pockets inside: the hall's engine bay and the
## Shaft's foot. Somewhere to get warm again on the way down.
const ENGINE_BAY := {"radius": 4.0, "warmth": 9.0}


## A coolant tank standing on the floor: something solid to hide behind.
func _tank(engine: StaticBody3D, at: Vector3, radius := 1.6, height := 5.0, material: Material = null) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = at + Vector3(0, height * 0.5, 0)
	engine.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	_batch(material if material != null else HULL_DARK).append_from(mesh, 0, col.transform)


## The Shaft: walls down to its floor, a railing round its lip, the first
## ramp down along the back wall to the landing at the east end, the second
## back along the front wall to the floor. At the foot, the Shaft's heater,
## its caches, its guards and the sealed way on to the Coil Galleries.
func _build_shaft(engine: StaticBody3D) -> void:
	var f := HALL_FLOOR
	var low := f - SHAFT_DEPTH
	var mid_y := f - SHAFT_DEPTH * 0.5
	var length := SHAFT_TO_Z - SHAFT_FROM_Z
	var mid_z := (SHAFT_FROM_Z + SHAFT_TO_Z) * 0.5
	var foot := SHAFT_FROM_Z - SHAFT_FOOT
	var deep := SHAFT_TO_Z - foot
	var deep_z := (foot + SHAFT_TO_Z) * 0.5
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(1.0, SHAFT_DEPTH + 1.0, deep + 2.0), Vector3(side * (SHAFT_HALF + 0.5), mid_y - 0.5, deep_z), ICE_WALL)
		_part(engine, Vector3(0.3, 1.1, length), Vector3(side * (SHAFT_HALF + 0.15), f + 0.55, mid_z), HULL_DARK)
	_part(engine, Vector3(SHAFT_HALF * 2.0 + 2.0, SHAFT_DEPTH + 1.0, 1.0), Vector3(0, mid_y - 0.5, foot - 0.5), ICE_WALL)
	# The east wall, cut by the way on to the Coil Galleries.
	var door := GALLERY_ROOMS[0] as Array
	var door_top := low + GALLERY_UP
	# The way on's own walls and roof (`_build_galleries`) stand in the
	# doorway's first metre, so these leave room for them.
	var jamb := float(door[1]) + 1.0
	var beside := SHAFT_HALF + 1.0 - jamb
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(beside, SHAFT_DEPTH + 1.0, 1.0),
				Vector3(side * (jamb + beside * 0.5), mid_y - 0.5, SHAFT_TO_Z + 0.5), ICE_WALL)
	_part(engine, Vector3(jamb * 2.0, f - door_top - 1.0, 1.0),
			Vector3(0, (f + door_top + 1.0) * 0.5, SHAFT_TO_Z + 0.5), ICE_WALL)
	_part(engine, Vector3(SHAFT_HALF * 2.0, 1.1, 0.3), Vector3(0, f + 0.55, SHAFT_TO_Z - 0.15), HULL_DARK)
	var gap := SHAFT_HALF - SHAFT_RAMP
	_part(engine, Vector3(SHAFT_HALF + gap, 1.1, 0.3), Vector3((-SHAFT_HALF + gap) * 0.5, f + 0.55, SHAFT_FROM_Z + 0.15), HULL_DARK)
	# Down: the first ramp along the back (+x), the landing, the second along the front.
	var turn := SHAFT_TO_Z - SHAFT_LANDING
	_slope(engine, gap, SHAFT_HALF, Vector2(SHAFT_FROM_Z, f), Vector2(turn, mid_y), DECK)
	_part(engine, Vector3(SHAFT_HALF * 2.0, 0.8, SHAFT_LANDING), Vector3(0, mid_y - 0.4, turn + SHAFT_LANDING * 0.5), DECK)
	_slope(engine, -SHAFT_HALF, -gap, Vector2(SHAFT_FROM_Z, low), Vector2(turn, mid_y), DECK)
	_part(engine, Vector3(SHAFT_HALF * 2.0, 1.0, deep), Vector3(0, low - 0.48, deep_z), DECK)
	# Rails along the ramps' open sides.
	_slope(engine, gap - 0.3, gap, Vector2(SHAFT_FROM_Z, f + 1.1), Vector2(turn, mid_y + 1.1), HULL_DARK, 1.1)
	_slope(engine, -gap, -gap + 0.3, Vector2(SHAFT_FROM_Z, low + 1.1), Vector2(turn, mid_y + 1.1), HULL_DARK, 1.1)
	var frame := engine_frame()
	_add_warmth(frame * Vector3(4.0, low, turn), ENGINE_BAY)
	for at: Vector3 in [Vector3(7.0, low, SHAFT_TO_Z - 2.5), Vector3(0.0, mid_y, SHAFT_TO_Z - 2.0)]:
		_add_marker("spawn_cache", frame * (at + Vector3(0, 0.1, 0))).set_meta("loot_source", "engine")
	for at: Vector3 in [Vector3(-4.0, mid_y, turn + 2.0), Vector3(4.0, low, 18.0), Vector3(-1.0, low, turn),
			Vector3(-4.0, low, foot + 2.5)]:
		_guard(frame * (at + Vector3(0, 0.1, 0)), SHAFT_GUARD, "shaft")


## The Coil Galleries: the rooms floored, roofed and walled, cover down
## both long halls, coil stacks in the alcoves, the coolant channel, a
## heater in the middle cross hall, caches and the galleries' guards.
func _build_galleries(engine: StaticBody3D) -> void:
	var g := GALLERY_FLOOR
	var shaft := [-SHAFT_HALF, SHAFT_HALF, SHAFT_FROM_Z - SHAFT_FOOT, SHAFT_TO_Z]
	var well := [-DESCENT_HALF, DESCENT_HALF, DESCENT_FROM_Z, DESCENT_TO_Z]
	_room_walls(engine, GALLERY_ROOMS, [shaft, well], g, GALLERY_UP, HULL)
	for room: Array in GALLERY_ROOMS:
		var size := Vector2(room[1] - room[0], room[3] - room[2])
		var mid := Vector2(room[0] + room[1], room[2] + room[3]) * 0.5
		_part(engine, Vector3(size.x, 1.0, size.y), Vector3(mid.x, g + GALLERY_UP + 0.5, mid.y), HULL_DARK)
		_floor_round(engine, room, GALLERY_COOLANT, g)
	var c: Array = GALLERY_COOLANT
	_part(engine, Vector3(c[1] - c[0], 1.0, c[3] - c[2]),
			Vector3((c[0] + c[1]) * 0.5, g - 0.48, (c[2] + c[3]) * 0.5), COOLANT)
	for at: Vector2 in GALLERY_CRATES:
		_part(engine, Vector3(3.0, 2.6, 3.0), Vector3(at.x, g + 1.3, at.y), HULL_DARK)
	for spot: Array in GALLERY_HOUSINGS:
		var at: Vector2 = spot[0]
		_part(engine, Vector3(5.0, 1.6, 2.4), Vector3(at.x, g + 0.8, at.y), STEEL, Basis(Vector3.UP, spot[1]))
	for at: Vector2 in coil_spots():
		_tank(engine, Vector3(at.x, g, at.y), COIL_RADIUS, 5.0, STEEL)
		# The plinth, frost cap and conduit the dressing draws round it
		# (`_dress_gallery_shell`).
		for part: Array in [[COIL_RADIUS + 0.3, 0.4, g], [COIL_RADIUS + 0.05, 0.35, g + 5.0], [0.45, GALLERY_UP - 5.2, g + 5.2]]:
			var drum := CylinderShape3D.new()
			drum.radius = part[0]
			drum.height = part[1]
			var col := CollisionShape3D.new()
			col.shape = drum
			col.position = Vector3(at.x, float(part[2]) + float(part[1]) * 0.5, at.y)
			engine.add_child(col)
	_build_walkway(engine)
	var frame := engine_frame()
	_add_warmth(frame * Vector3(0.0, g, 74.0), ENGINE_BAY)
	for at: Vector2 in [Vector2(21.6, 56.0), Vector2(21.6, 88.0), Vector2(-21.6, 88.0), Vector2(0.0, 106.0)]:
		_add_marker("spawn_cache", frame * Vector3(at.x, g + 0.1, at.y)).set_meta("loot_source", "engine")
	for at: Vector2 in [Vector2(13.0, 46.0), Vector2(14.0, 90.0), Vector2(12.0, 72.0), Vector2(-17.5, 58.0),
			Vector2(-8.5, 96.0), Vector2(3.0, 103.0)]:
		_guard(frame * Vector3(at.x, g + 0.1, at.y), HALL_GUARD, "galleries south" if at.y < 75.0 else "galleries north")
	_guard(frame * Vector3(18.0, g + WALKWAY_UP + 0.1, 70.0), HALL_GUARD, "galleries south")


## The north gallery's walkway: a deck on posts along the outer wall, a
## ramp up at each end and a rail on its open side.
func _build_walkway(engine: StaticBody3D) -> void:
	var g := GALLERY_FLOOR
	var w: Array = WALKWAY
	var top := g + WALKWAY_UP
	var x0: float = w[0]
	var x1: float = w[1]
	var z0: float = w[2]
	var z1: float = w[3]
	_part(engine, Vector3(x1 - x0, 0.5, z1 - z0), Vector3((x0 + x1) * 0.5, top - 0.25, (z0 + z1) * 0.5), DECK)
	_slope(engine, x0, x1, Vector2(z0 - WALKWAY_RAMP, g), Vector2(z0, top), DECK)
	_slope(engine, x0, x1, Vector2(z1, top), Vector2(z1 + WALKWAY_RAMP, g), DECK)
	# The rail on the open side, up the ramps too.
	_part(engine, Vector3(0.3, 1.1, z1 - z0), Vector3(x0 + 0.15, top + 0.55, (z0 + z1) * 0.5), HULL_DARK)
	_slope(engine, x0, x0 + 0.3, Vector2(z0 - WALKWAY_RAMP + 2.0, g + 1.1 + WALKWAY_UP * 2.0 / WALKWAY_RAMP),
			Vector2(z0, top + 1.1), HULL_DARK, 1.1)
	_slope(engine, x0, x0 + 0.3, Vector2(z1, top + 1.1),
			Vector2(z1 + WALKWAY_RAMP - 2.0, g + 1.1 + WALKWAY_UP * 2.0 / WALKWAY_RAMP), HULL_DARK, 1.1)
	# Posts under its open edge.
	var z := z0 + 4.0
	while z < z1 - 2.0:
		_part(engine, Vector3(0.5, WALKWAY_UP - 0.5, 0.5), Vector3(x0 + 0.4, g + (WALKWAY_UP - 0.5) * 0.5, z), STEEL)
		z += 9.0


## Low cover down the galleries: crates, and fallen coil housings (x, z;
## a turn), clear of the coolant.
const GALLERY_CRATES := [Vector2(10.0, 58.0), Vector2(16.5, 66.0), Vector2(9.5, 84.0), Vector2(16.0, 100.0),
		Vector2(-18.0, 48.0), Vector2(-8.5, 66.0), Vector2(-18.0, 80.0), Vector2(-8.5, 90.0)]
const GALLERY_HOUSINGS := [[Vector2(13.0, 78.0), 0.3], [Vector2(-8.5, 52.0), 1.4], [Vector2(-17.5, 100.0), -0.2],
		[Vector2(12.0, 42.0), -0.5]]
const COIL_RADIUS := 1.3


## Where the Engine Coils stand: two in each alcove, against its back wall.
static func coil_spots() -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for room: Array in GALLERY_ROOMS.slice(6, 10):
		var out := 1.0 if room[0] > 0.0 else -1.0
		var back: float = room[1] if out > 0.0 else room[0]
		var mid := (float(room[2]) + float(room[3])) * 0.5
		for k: float in [-2.2, 2.2]:
			spots.append(Vector2(back - out * (COIL_RADIUS + 0.4), mid + k))
	return spots


## A room's floor at `y`, round a `hole` that some other floor fills.
func _floor_round(engine: StaticBody3D, room: Array, hole: Array, y: float) -> void:
	var x0 := maxf(room[0], hole[0])
	var x1 := minf(room[1], hole[1])
	var z0 := maxf(room[2], hole[2])
	var z1 := minf(room[3], hole[3])
	var pieces: Array = [room]
	if x0 < x1 and z0 < z1:
		pieces = [[room[0], x0, room[2], room[3]], [x1, room[1], room[2], room[3]],
				[x0, x1, room[2], z0], [x0, x1, z1, room[3]]]
	for piece: Array in pieces:
		var size := Vector2(piece[1] - piece[0], piece[3] - piece[2])
		if size.x <= 0.0 or size.y <= 0.0:
			continue
		_part(engine, Vector3(size.x, 1.0, size.y),
				Vector3((piece[0] + piece[1]) * 0.5, y - 0.48, (piece[2] + piece[3]) * 0.5), DECK)


## Walls round a set of rooms on a metre grid ([x0, x1, z0, z1], whole
## metres), from under their floor at `y` to over their roof `up` higher:
## along every edge with rock beyond, none where another room or one of the
## `open` spaces (built on their own) carries on. Runs along one line are
## one wall, stretched to close the corners.
func _room_walls(engine: StaticBody3D, rooms: Array, open: Array, y: float, up: float, material: Material) -> void:
	var inside := {}
	for room: Array in rooms:
		for ix in range(int(room[0]), int(room[1])):
			for iz in range(int(room[2]), int(room[3])):
				inside[Vector2i(ix, iz)] = true
	var near := inside.duplicate()
	for room: Array in open:
		for ix in range(int(room[0]), int(room[1])):
			for iz in range(int(room[2]), int(room[3])):
				near[Vector2i(ix, iz)] = true
	# Faces by side (+x, -x, +z, -z) and line: the cells along it.
	var faces := [{}, {}, {}, {}]
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell: Vector2i in inside:
		for k in 4:
			var beyond: Vector2i = cell + steps[k]
			if near.has(beyond):
				continue
			var line := beyond.x if k < 2 else beyond.y
			var along := cell.y if k < 2 else cell.x
			var lines: Dictionary = faces[k]
			if not lines.has(line):
				lines[line] = []
			(lines[line] as Array).append(along)
	var tall := up + 2.0
	var mid_y := y + up * 0.5
	for k in 4:
		var lines: Dictionary = faces[k]
		for line: int in lines:
			var cells: Array = lines[line]
			cells.sort()
			var start: int = cells[0]
			for i in cells.size():
				var last: int = cells[i]
				if i + 1 < cells.size() and int(cells[i + 1]) == last + 1:
					continue
				var a := start
				var b := last + 1
				# Close a corner with rock beyond it.
				var before := Vector2i(line, a - 1) if k < 2 else Vector2i(a - 1, line)
				var after := Vector2i(line, b) if k < 2 else Vector2i(b, line)
				var from := float(a) - (0.0 if near.has(before) else 1.0)
				var to := float(b) + (0.0 if near.has(after) else 1.0)
				var out := float(line) + 0.5
				if k < 2:
					_part(engine, Vector3(1.0, tall, to - from), Vector3(out, mid_y, (from + to) * 0.5), material)
				else:
					_part(engine, Vector3(to - from, tall, 1.0), Vector3((from + to) * 0.5, mid_y, out), material)
				if i + 1 < cells.size():
					start = cells[i + 1]


## The Descent: the well's walls and roof, its floor, three ramps switching
## back between a landing at each end (the first and the third along the
## north lane, the second along the south), rails on every open edge, the
## foot's heater, caches and guards, the cable lift's lower stop and its
## switch, and the sealed door to the Heart in the east wall.
func _build_descent(engine: StaticBody3D) -> void:
	var g := GALLERY_FLOOR
	var step := DESCENT_DROP / 3.0
	var bottom := DESCENT_FLOOR
	var top := g + GALLERY_UP + DESCENT_ROOF
	var h := DESCENT_HALF
	var from := DESCENT_FROM_Z
	var to := DESCENT_TO_Z
	var west := from + DESCENT_LANDING
	var east := to - DESCENT_FOOT
	var length := to - from
	var mid_z := (from + to) * 0.5
	var base := bottom - 1.0
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(1.0, top - base, length + 2.0), Vector3(side * (h + 0.5), (top + base) * 0.5, mid_z), ICE_WALL)
	# The east wall, open where the door to the Heart stands.
	var post := h + 1.0 - HEART_DOOR * 0.5
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(post, top - base, 1.0), Vector3(side * (HEART_DOOR * 0.5 + post * 0.5), (top + base) * 0.5, to + 0.5), ICE_WALL)
	_part(engine, Vector3(HEART_DOOR, top - bottom - HEART_DOOR_UP, 1.0),
			Vector3(0, (top + bottom + HEART_DOOR_UP) * 0.5, to + 0.5), ICE_WALL)
	# The west wall, open where the way from the galleries comes in. The way
	# on's own walls and roof stand in its last metre.
	var door := GALLERY_ROOMS[GALLERY_ROOMS.size() - 1] as Array
	var jamb := float(door[1]) + 1.0
	_part(engine, Vector3(h * 2.0 + 2.0, g - 1.0 - base, 1.0), Vector3(0, (g - 1.0 + base) * 0.5, from - 0.5), ICE_WALL)
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(h + 1.0 - jamb, GALLERY_UP + 2.0, 1.0),
				Vector3(side * (jamb + (h + 1.0 - jamb) * 0.5), g + GALLERY_UP * 0.5, from - 0.5), ICE_WALL)
	_part(engine, Vector3(h * 2.0 + 2.0, top - g - GALLERY_UP - 1.0, 1.0),
			Vector3(0, (top + g + GALLERY_UP + 1.0) * 0.5, from - 0.5), ICE_WALL)
	_part(engine, Vector3(h * 2.0 + 2.0, 1.0, length + 2.0), Vector3(0, top + 0.5, mid_z), HULL_DARK)
	_part(engine, Vector3(h * 2.0, 1.0, length), Vector3(0, bottom - 0.48, mid_z), DECK)
	# The landings: the top one level with the galleries, the east one under
	# the first ramp's foot, the west one under the top.
	_part(engine, Vector3(h * 2.0, 1.0, DESCENT_LANDING), Vector3(0, g - 0.48, from + DESCENT_LANDING * 0.5), DECK)
	_part(engine, Vector3(h * 2.0, 0.8, DESCENT_LANDING), Vector3(0, g - step - 0.4, east + DESCENT_LANDING * 0.5), DECK)
	_part(engine, Vector3(h * 2.0, 0.8, DESCENT_LANDING), Vector3(0, g - step * 2.0 - 0.4, from + DESCENT_LANDING * 0.5), DECK)
	# The ramps. The third is solid down to the floor, so nothing gets under it.
	var lane := h - DESCENT_LANE
	_slope(engine, lane, h, Vector2(west, g), Vector2(east, g - step), DECK)
	_slope(engine, -h, -lane, Vector2(west, g - step * 2.0), Vector2(east, g - step), DECK)
	_slope(engine, lane, h, Vector2(west, g - step * 2.0), Vector2(east, bottom), DECK, 14.0)
	# Rails along the ramps' inner edges and across the landings' open edges.
	_slope(engine, lane, lane + 0.3, Vector2(west, g + 1.1), Vector2(east, g - step + 1.1), HULL_DARK, 1.1)
	_slope(engine, -lane - 0.3, -lane, Vector2(west, g - step * 2.0 + 1.1), Vector2(east, g - step + 1.1), HULL_DARK, 1.1)
	_slope(engine, lane, lane + 0.3, Vector2(west, g - step * 2.0 + 1.1), Vector2(east, bottom + 1.1), HULL_DARK, 1.1)
	_part(engine, Vector3(h + lane, 1.1, 0.3), Vector3((lane - h) * 0.5, g + 0.55, west - 0.15), HULL_DARK)
	_part(engine, Vector3(lane * 2.0, 1.1, 0.3), Vector3(0, g - step + 0.55, east + 0.15), HULL_DARK)
	_part(engine, Vector3(h * 2.0, 1.1, 0.3), Vector3(0, g - step + 0.55, east + DESCENT_LANDING - 0.15), HULL_DARK)
	_part(engine, Vector3(lane * 2.0, 1.1, 0.3), Vector3(0, g - step * 2.0 + 0.55, west - 0.15), HULL_DARK)
	# Cover at the foot and on the east landing.
	for at: Vector3 in [Vector3(-6.0, g - step, east + 3.0), Vector3(3.0, bottom, 165.0), Vector3(-2.0, bottom, 161.0)]:
		_part(engine, Vector3(3.0, 2.6, 3.0), at + Vector3(0, 1.3, 0), HULL_DARK)
	# The cable lift's lower stop and its switch.
	_lift_cage(engine, Vector3(LIFT_FOOT.x, bottom, LIFT_FOOT.y), bottom + GALLERY_UP)
	_part(engine, Vector3(1.4, 1.3, 0.8), Vector3(LIFT_SWITCH.x, bottom + 0.65, LIFT_SWITCH.y + 1.2), STEEL)
	var frame := engine_frame()
	var lift_stop := _add_marker("lift_stop", frame * Vector3(LIFT_FOOT.x, bottom + 0.1, LIFT_FOOT.y))
	lift_stop.set_meta("lift", LIFT_ID)
	lift_stop.set_meta("radius", LIFT_STOP)
	var switch := _add_marker("lift_power", frame * Vector3(LIFT_SWITCH.x, bottom + 0.1, LIFT_SWITCH.y))
	switch.set_meta("lift", LIFT_ID)
	switch.set_meta("radius", LIFT_STOP)
	switch.set_meta("name", "Cable lift")
	_add_warmth(frame * Vector3(5.0, bottom, 172.0), ENGINE_BAY)
	for at: Vector3 in [Vector3(8.0, g - step, east + 3.0), Vector3(9.0, bottom, 174.0)]:
		_add_marker("spawn_cache", frame * (at + Vector3(0, 0.1, 0))).set_meta("loot_source", "engine")
	for at: Vector3 in [Vector3(4.0, g, from + 3.0), Vector3(-6.0, g - step, east + 1.5),
			Vector3(5.0, g - step * 2.0, from + 3.0), Vector3(6.0, bottom, 167.0), Vector3(-3.0, bottom, 163.5)]:
		_guard(frame * (at + Vector3(0, 0.1, 0)), SHAFT_GUARD, "descent" if at.y > bottom else "lift")
	# Two more keep the lift's switch: powering it is a fight, never free.
	for at: Vector2 in SWITCH_GUARDS:
		_guard(frame * Vector3(at.x, bottom + 0.1, at.y), SWITCH_GUARD, "lift")


## The cable lift's upper stop, in the hall beside the Shaft.
func _build_lift_top(engine: StaticBody3D) -> void:
	var f := HALL_FLOOR
	_lift_cage(engine, Vector3(LIFT_TOP.x, f, LIFT_TOP.y), f + CATWALK_UP - 1.0)
	var stop := _add_marker("lift_stop", engine_frame() * Vector3(LIFT_TOP.x, f + 0.1, LIFT_TOP.y))
	stop.set_meta("lift", LIFT_ID)
	stop.set_meta("radius", LIFT_STOP)


## A lift cage standing on the floor at `at`: a post at each corner up to
## its head at `head`, something to stand behind while it is called.
func _lift_cage(engine: StaticBody3D, at: Vector3, head: float) -> void:
	var half := LIFT_CAGE * 0.5
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_part(engine, Vector3(0.4, head - at.y, 0.4),
				Vector3(at.x + corner.x * (half - 0.2), (at.y + head) * 0.5, at.z + corner.y * (half - 0.2)), STEEL)
	_part(engine, Vector3(LIFT_CAGE, 0.5, LIFT_CAGE), Vector3(at.x, head + 0.25, at.z), HULL_DARK)


## The Heart: the way on from the Descent's door, the round chamber with its
## balcony, ramps, pylons and cover, and everything its keeper's fight is
## made of, as map markers (`WorldDef`'s "spawn_boss", "boss_socket",
## "purge" and "vault"; the deep beacon is `_build_deep_beacon`).
func _build_heart(engine: StaticBody3D) -> void:
	var bottom := DESCENT_FLOOR
	var c := HEART_Z
	var r := HEART_RADIUS
	var up := HEART_UP
	var frame := engine_frame()
	# The way on: a floor, walls (deep enough to close the chamber's wall on
	# each side of its doorway) and a roof.
	var way_from := DESCENT_TO_Z
	var way_to := c - r + 2.5
	var way_mid := (way_from + way_to) * 0.5
	_part(engine, Vector3(HEART_DOOR + 4.0, 1.0, way_to - way_from), Vector3(0, bottom - 0.48, way_mid), DECK)
	for side: float in [-1.0, 1.0]:
		_part(engine, Vector3(2.0, HEART_DOOR_UP + 1.0, way_to - way_from + 1.0),
				Vector3(side * (HEART_DOOR * 0.5 + 1.0), bottom + (HEART_DOOR_UP + 1.0) * 0.5, way_mid), ICE_WALL)
	_part(engine, Vector3(HEART_DOOR + 4.0, 1.0, way_to - way_from + 1.0), Vector3(0, bottom + HEART_DOOR_UP + 0.5, way_mid), HULL_DARK)
	_add_warmth(frame * Vector3(0, bottom, way_from + 3.0), ENGINE_BAY)
	# The chamber: floor and roof, and its wall round in segments, open at the
	# door. A segment's inner face stands at the radius.
	_part(engine, Vector3(r * 2.0 + 4.0, 1.0, r * 2.0 + 4.0), Vector3(0, bottom - 0.48, c), DECK)
	_part(engine, Vector3(r * 2.0 + 4.0, 1.0, r * 2.0 + 4.0), Vector3(0, bottom + up + 0.5, c), HULL_DARK)
	var step := TAU / HEART_SEGMENTS
	var wide := r * step + 0.3
	for i in HEART_SEGMENTS:
		var a := (float(i) + 0.5) * step
		var turn := Basis(Vector3.UP, a)
		var out := Vector3(sin(a), 0, cos(a))
		if absf(wrapf(a - PI, -PI, PI)) > step * 0.6:
			_part(engine, Vector3(wide, up + 1.0, 1.2), out * (r + 0.6) + Vector3(0, bottom + up * 0.5, c), ICE_WALL, turn)
		else:
			var over := up - HEART_DOOR_UP
			_part(engine, Vector3(wide, over + 0.5, 1.2), out * (r + 0.6) + Vector3(0, bottom + HEART_DOOR_UP + over * 0.5 + 0.25, c),
					ICE_WALL, turn)
		# The balcony round it, and its rail but where the ramps come up.
		var ledge := r - HEART_LEDGE * 0.5
		_part(engine, Vector3((r - HEART_LEDGE * 0.5) * step + 0.4, 0.8, HEART_LEDGE + 0.2),
				out * ledge + Vector3(0, bottom + HEART_BALCONY - 0.4, c), DECK, turn)
		if absf(absf(wrapf(a, -PI, PI)) - deg_to_rad(70.0)) > deg_to_rad(12.0):
			_part(engine, Vector3((r - HEART_LEDGE) * step + 0.2, 1.1, 0.3),
					out * (r - HEART_LEDGE + 0.15) + Vector3(0, bottom + HEART_BALCONY + 0.55, c), HULL_DARK, turn)
	# A ramp up each side to a landing on the balcony.
	for side: float in [-1.0, 1.0]:
		var near := 24.0
		var far := 28.5
		var xs := [near, far] if side > 0.0 else [-far, -near]
		_slope(engine, xs[0], xs[1], Vector2(c - 12.0, bottom), Vector2(c + 8.0, bottom + HEART_BALCONY), DECK, 1.0)
		var rail_x := side * near
		_slope(engine, rail_x - 0.15, rail_x + 0.15, Vector2(c - 12.0, bottom + 1.1), Vector2(c + 8.0, bottom + HEART_BALCONY + 1.1), HULL_DARK, 1.1)
		_part(engine, Vector3(r - 22.5, 0.8, 6.0), Vector3(side * (22.5 + (r - 22.5) * 0.5), bottom + HEART_BALCONY - 0.4, c + 11.0), DECK)
	# The pylons, floor to roof: cover a solo player dashes round.
	for spot: Vector2 in heart_pylons():
		_tank(engine, Vector3(spot.x, bottom, spot.y), PYLON_RADIUS, up, HULL_DARK)
		# The collar the dressing puts round its foot (`_dress_heart`).
		var collar := CylinderShape3D.new()
		collar.radius = PYLON_RADIUS + 0.6
		collar.height = 1.2
		var foot := CollisionShape3D.new()
		foot.shape = collar
		foot.position = Vector3(spot.x, bottom + 0.6, spot.y)
		engine.add_child(foot)
	# Cover: fallen housings and crates off the middle.
	for spot: Array in [[Vector2(-19.0, c - 17.0), 0.4], [Vector2(18.0, c - 19.0), -0.3], [Vector2(-21.0, c + 15.0), 1.2],
			[Vector2(20.0, c + 16.0), -1.0], [Vector2(0.0, c - 22.0), 0.0]]:
		var at: Vector2 = spot[0]
		_part(engine, Vector3(5.0, 1.6, 2.2), Vector3(at.x, bottom + 0.8, at.y), HULL_DARK, Basis(Vector3.UP, float(spot[1])))
	for at: Vector2 in [Vector2(-8.0, c - 25.0), Vector2(9.0, c + 22.0)]:
		_part(engine, Vector3(3.0, 2.6, 3.0), Vector3(at.x, bottom + 1.3, at.y), HULL_DARK)
	# The keeper, in the middle under the core.
	var boss := _add_marker("spawn_boss", frame * Vector3(0, bottom + 0.1, c + 2.0))
	boss.set_meta("faction", "warden")
	boss.set_meta("boss", HEART_KEEPER)
	boss.set_meta("keeper", true)
	boss.set_meta("radius", HEART_GROUND)
	boss.set_meta("arena", r)
	boss.set_meta("respawn", HEART_RESPAWN)
	boss.set_meta("name", "The Heart")
	# Its wall sockets, its purge lanes, its vault and the deep beacon.
	for angle: float in HEART_SOCKETS:
		var a := deg_to_rad(angle)
		var socket := _add_marker("boss_socket", frame * Vector3(sin(a) * (r - 2.5), bottom + 0.1, c + cos(a) * (r - 2.5)))
		socket.set_meta("keeper", HEART_KEEPER)
		socket.set_meta("faction", "warden")
	for lane: Array in heart_purges():
		var from: Vector2 = lane[0]
		var to: Vector2 = lane[1]
		var purge := _add_marker("purge", frame * Vector3(from.x, bottom + 0.1, from.y))
		purge.set_meta("keeper", HEART_KEEPER)
		purge.set_meta("toward", frame * Vector3(to.x, bottom + 0.1, to.y))
		purge.set_meta("width", PURGE_WIDTH)
		purge.set_meta("damage", PURGE_DAMAGE)
	var vault := _add_marker("vault", frame * Vector3(0, bottom + 0.1, c + r - 4.0))
	vault.basis = frame.basis
	vault.set_meta("keeper", HEART_KEEPER)


## The deep beacon in the Heart and its warmth, both dark while the Heart
## Warden stands. Placed after the valley's beacons, so theirs come first.
func _build_deep_beacon() -> void:
	var at := engine_frame() * Vector3(0, DESCENT_FLOOR + 0.1, HEART_Z + 20.0)
	var beacon := _add_marker("beacon", at)
	beacon.set_meta("name", "The deep beacon")
	beacon.set_meta("radius", BEACON["radius"])
	beacon.set_meta("keeper", HEART_KEEPER)
	var warm := _add_marker("warmth", at)
	warm.set_meta("radius", BEACON["radius"])
	warm.set_meta("warmth", BEACON["warmth"])
	warm.set_meta("keeper", HEART_KEEPER)


## The pylons round the Heart's middle (x, z in the drum's frame).
static func heart_pylons() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		out.append(Vector2(k.x * HEART_PYLON, HEART_Z + k.y * HEART_PYLON))
	return out


## The purge lanes, each from a pylon's foot to the next one's ([from, to],
## x, z in the drum's frame), in the order they are vented: the two
## diagonals (an X over the middle), then the two rows (either side of it).
static func heart_purges() -> Array:
	var p := heart_pylons()
	var out := []
	for pair: Array in [[0, 2], [1, 3], [0, 1], [3, 2]]:
		var a: Vector2 = p[pair[0]]
		var b: Vector2 = p[pair[1]]
		var along := (b - a).normalized() * (PYLON_RADIUS + 0.4)
		out.append([a + along, b - along])
	return out


## A Warden of the Engine's garrison (`WorldDef`'s "spawn_guard"), one of
## its section's pocket, which wakes only when a player is close: walls
## hide it from further off.
func _guard(at: Vector3, radius: float, pocket: String) -> void:
	var marker := _add_marker("spawn_guard", at)
	marker.set_meta("faction", "warden")
	marker.set_meta("radius", radius)
	marker.set_meta("pocket", "engine " + pocket)
	marker.set_meta("wake", ENGINE_WAKE)


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
		# The heat lamp the dressing hangs on top (`_dress_beacons`).
		SolidProp.box(nav_region, Vector3(1.1, 0.5, 1.1), Transform3D(Basis.IDENTITY, at + Vector3(0, 5.2, 0)))


## A place that gives body heat back (`WorldDef`'s "The cold").
func _add_warmth(at: Vector3, kind: Dictionary) -> void:
	var marker := _add_marker("warmth", at + Vector3(0, 0.1, 0))
	marker.set_meta("radius", kind["radius"])
	marker.set_meta("warmth", kind["warmth"])


## A spot of one of the valley's encounter pockets (`WorldDef.pocket_wake`):
## a guard of `faction` who keeps to `radius` metres round it, waking with
## the rest of `pocket`. It is also a "spawn_bot" marker, where a world
## event comes in.
func _bot_spot(at: Vector3, faction: String, rank: int, pocket: String, radius: float) -> void:
	_bot_spots.append({"at": at, "faction": faction, "rank": rank, "order": _bot_spots.size(),
			"pocket": pocket, "radius": radius})


func _place_bot_spots() -> void:
	_bot_spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rank < b.rank or (a.rank == b.rank and a.order < b.order))
	for spot in _bot_spots:
		_add_marker("spawn_bot", spot.at).set_meta("faction", spot.faction)
		var guard := _add_marker("spawn_guard", spot.at)
		guard.set_meta("faction", spot.faction)
		guard.set_meta("pocket", spot.pocket)
		guard.set_meta("radius", spot.radius)


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


## A depot whose uplink terminal stands on the `back` side of its pad (a
## direction on the ground; zero leaves it on the +Z side).
func _add_depot(at: Vector3, back := Vector2.ZERO) -> void:
	var zone := Depot.new()
	zone.add_to_group("depot")
	zone.position = at + Vector3(0, 2.0, 0)
	if back != Vector2.ZERO:
		zone.rotation.y = atan2(back.x, back.y)
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


## The Engine's one light still blinks over its hatch. Inside, the grid's
## teal still glows along the catwalks and round the stator rings, a few
## amber work lamps burn, and the sealed way on at the Shaft's foot shows
## its warning stripe.
func _dress_engine(art: Node3D) -> void:
	var frame := engine_frame()
	var teal := _glow(Color(0.2, 1.0, 0.85), 6.0)
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.material = teal
	bulb.mesh = sphere
	bulb.position = frame * Vector3(-ENGINE_RADIUS - 0.6, HALL_FLOOR + HATCH_HEIGHT + 1.4, HATCH_Z)
	bulb.set_meta("walk_through", "a warning lamp over the hatch")
	art.add_child(bulb)
	var light := Look.lamp(Color(0.2, 1.0, 0.85), 5.0, 22.0)
	light.position = frame * Vector3(-ENGINE_RADIUS - 2.0, HALL_FLOOR + HATCH_HEIGHT + 1.0, HATCH_Z)
	art.add_child(light)
	var blink := create_tween().set_loops()
	blink.tween_property(light, "light_energy", 0.3, 0.15).set_delay(1.6)
	blink.tween_property(light, "light_energy", 5.0, 0.15)
	var strip := _glow(Color(0.2, 1.0, 0.85), 3.0)
	var amber := _glow(Color(1.0, 0.55, 0.2), 3.0)
	var walk := HALL_FLOOR + CATWALK_UP
	var inner := _hall_half(walk + 2.0) - 0.4 - CATWALK_WIDTH
	for side: float in [-1.0, 1.0]:
		_glow_box(art, frame, Vector3(0.3, 0.15, ENGINE_LENGTH - 4.0), Vector3(side * (inner + 0.4), walk - 0.5, 0), strip)
		_glow_box(art, frame, Vector3(0.3, 0.12, SHAFT_TO_Z - SHAFT_FROM_Z), Vector3(side * (SHAFT_HALF - 0.3),
				HALL_FLOOR - SHAFT_DEPTH * 0.5 + 3.0, (SHAFT_FROM_Z + SHAFT_TO_Z) * 0.5), strip)
	for z: float in [-24.0, 0.0, 22.0]:
		_lamp_at(art, frame * Vector3(0, 9.0, z), Color(0.45, 0.85, 1.0), 6.0, 36.0)
	for spot: Vector3 in [Vector3(-12.0, 6.0, -32.0), Vector3(12.0, 6.0, -8.0), Vector3(-12.0, 6.0, 16.0)]:
		_lamp_at(art, frame * (spot + Vector3(0, HALL_FLOOR, 0)), Color(1.0, 0.6, 0.3), 4.0, 18.0)
	# Down the Shaft.
	var mid := (SHAFT_FROM_Z + SHAFT_TO_Z) * 0.5
	_lamp_at(art, frame * Vector3(0, HALL_FLOOR - 6.0, mid), Color(1.0, 0.6, 0.3), 5.0, 26.0)
	_lamp_at(art, frame * Vector3(0, HALL_FLOOR - SHAFT_DEPTH + 6.0, mid), Color(0.3, 0.9, 1.0), 5.0, 26.0)
	# The way on to the galleries: a lit frame round the Shaft's east door.
	var low := GALLERY_FLOOR
	_glow_box(art, frame, Vector3(10.0, 0.3, 0.2), Vector3(0, low + GALLERY_UP - 0.2, SHAFT_TO_Z - 0.05), strip)
	for x: float in [-5.0, 5.0]:
		_glow_box(art, frame, Vector3(0.3, GALLERY_UP, 0.2), Vector3(x, low + GALLERY_UP * 0.5, SHAFT_TO_Z - 0.05), strip)
	_dress_galleries(art, frame, strip, amber)
	_dress_descent(art, frame, strip, amber)
	_dress_lift(art, frame)
	_dress_heart(art, frame, amber)


## The galleries: lamps down both halls (cold blue over the coolant), a lit
## strip along every long wall, glowing bands round the Engine Coils and a
## faint light off the coolant.
func _dress_galleries(art: Node3D, frame: Transform3D, strip: Material, amber: Material) -> void:
	var g := GALLERY_FLOOR
	var roof := g + GALLERY_UP
	var cool := _glow(Color(0.7, 0.95, 1.0), 4.0)
	var warm := _glow(Color(1.0, 0.75, 0.45), 4.0)
	for z: float in [50.0, 74.0, 98.0]:
		_hung_lamp(art, frame, Vector3(11.0, roof - 1.0, z), roof, cool, Color(0.35, 0.95, 1.0), 4.5, 24.0)
		_hung_lamp(art, frame, Vector3(-13.0, roof - 1.0, z), roof, cool, Color(0.45, 0.7, 1.0), 4.0, 24.0)
	for z: float in [43.0, 105.0]:
		_hung_lamp(art, frame, Vector3(0.0, roof - 1.6, z), roof, warm, Color(1.0, 0.6, 0.3), 3.5, 16.0)
	_dress_gallery_shell(g)
	# Strips along the long halls' walls, broken where a cross hall or an
	# alcove opens in them.
	for run: Array in GALLERY_WALL_RUNS:
		var face: float = run[0]
		var into := 0.55 if face < 10.0 else -0.55
		for side: float in [-1.0, 1.0]:
			var length: float = float(run[2]) - float(run[1]) - 1.0
			_glow_box(art, frame, Vector3(0.2, 0.12, length),
					Vector3(side * (face + into), g + 2.6, (float(run[1]) + float(run[2])) * 0.5), strip)
	var coil := _glow(Color(1.0, 0.55, 0.2), 4.0)
	var band := CylinderMesh.new()
	band.top_radius = COIL_RADIUS + 0.06
	band.bottom_radius = COIL_RADIUS + 0.06
	band.height = 0.25
	band.radial_segments = 14
	band.material = coil
	for at: Vector2 in coil_spots():
		for up: float in [1.2, 2.5, 3.8]:
			var ring := MeshInstance3D.new()
			ring.mesh = band
			ring.position = frame * Vector3(at.x, g + up, at.y)
			art.add_child(ring)
	var c: Array = GALLERY_COOLANT
	var cold := _glow(Color(0.5, 0.85, 1.0), 1.2)
	for x: float in [c[0] + 0.1, c[1] - 0.1]:
		_glow_box(art, frame, Vector3(0.12, 0.05, c[3] - c[2]), Vector3(x, g + 0.03, (c[2] + c[3]) * 0.5), cold)
	_glow_box(art, frame, Vector3(0.3, 0.3, 0.2), Vector3(0, g + GALLERY_UP - 0.4, 110.1), amber)
	var mist := StandardMaterial3D.new()
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.albedo_color = Color(0.75, 0.9, 1.0, 0.09)
	mist.cull_mode = BaseMaterial3D.CULL_DISABLED
	for up: float in [0.25, 0.6, 1.0]:
		_glow_box(art, frame, Vector3(c[1] - c[0] + 0.6, 0.01, c[3] - c[2] - 1.0),
				Vector3((c[0] + c[1]) * 0.5, g + up, (c[2] + c[3]) * 0.5), mist)
	# The walkway's edge, lit like the hall's catwalks.
	var w: Array = WALKWAY
	_glow_box(art, frame, Vector3(0.2, 0.12, float(w[3]) - float(w[2])),
			Vector3(float(w[0]) + 0.1, g + WALKWAY_UP - 0.4, (float(w[2]) + float(w[3])) * 0.5), strip)
	_flush_deco(art, frame)


## The galleries' shell, so they read as the inside of a machine: ribs up
## the long walls, beams across the roof, pipes and cable trays along the
## walls, the coils' plinths, frosted caps and conduits, kerbs along the
## coolant. All of it decoration, merged.
func _dress_gallery_shell(g: float) -> void:
	var roof := g + GALLERY_UP
	for run: Array in GALLERY_WALL_RUNS:
		var face: float = run[0]
		var into := 1.0 if face < 10.0 else -1.0
		for side: float in [-1.0, 1.0]:
			var z: float = float(run[1]) + 1.0
			while z < float(run[2]) - 0.5:
				_deco(Vector3(0.4, GALLERY_UP, 0.7), Vector3(side * (face + into * 0.25), g + GALLERY_UP * 0.5, z), HULL_DARK)
				z += 4.0
			var length: float = float(run[2]) - float(run[1])
			var mid := (float(run[1]) + float(run[2])) * 0.5
			if into < 0.0:
				for up: float in [7.0, 7.7]:
					_deco_cyl(0.22, length, Vector3(side * (face - 0.6), g + up, run[1]), STEEL, Basis(Vector3.RIGHT, PI / 2.0))
			else:
				_deco(Vector3(0.7, 0.15, length), Vector3(side * (face + 0.55), g + 7.4, mid), STEEL)
				_deco(Vector3(0.7, 0.4, 0.05), Vector3(side * (face + 0.55), g + 7.55, mid), HULL_DARK)
	var z := 41.0
	while z < 109.0:
		for x: float in [-13.0, 13.0]:
			_deco(Vector3(14.0, 0.7, 0.6), Vector3(x, roof - 0.35, z), HULL_DARK)
		z += 6.0
	for at: Vector2 in coil_spots():
		_deco_cyl(COIL_RADIUS + 0.3, 0.4, Vector3(at.x, g, at.y), HULL_DARK)
		_deco_cyl(COIL_RADIUS + 0.05, 0.35, Vector3(at.x, g + 5.0, at.y), FROST)
		_deco_cyl(0.45, GALLERY_UP - 5.2, Vector3(at.x, g + 5.2, at.y), STEEL)
	var c: Array = GALLERY_COOLANT
	for x: float in [c[0] - 0.15, c[1] + 0.15]:
		_deco(Vector3(0.3, 0.2, c[3] - c[2]), Vector3(x, g + 0.1, (c[2] + c[3]) * 0.5), STEEL)


## The long halls' walls ([x of the face, z from, z to]), broken where a
## cross hall or an alcove opens in them.
const GALLERY_WALL_RUNS := [[6.0, 48.0, 69.0], [6.0, 79.0, 100.0], [20.0, 38.0, 52.0], [20.0, 60.0, 84.0],
		[20.0, 92.0, 110.0]]


## The Descent: a lamp over each landing and the foot, strips down the
## lanes, and the open door to the Heart, marked out in amber.
func _dress_descent(art: Node3D, frame: Transform3D, strip: Material, amber: Material) -> void:
	var g := GALLERY_FLOOR
	var step := DESCENT_DROP / 3.0
	var mid := (DESCENT_FROM_Z + DESCENT_TO_Z) * 0.5
	var top := g + GALLERY_UP + DESCENT_ROOF
	var cool := _glow(Color(0.7, 0.95, 1.0), 4.0)
	var warm := _glow(Color(1.0, 0.75, 0.45), 4.0)
	_hung_lamp(art, frame, Vector3(0, g + GALLERY_UP, DESCENT_FROM_Z + 3.0), top, cool, Color(0.35, 0.95, 1.0), 4.5, 26.0)
	_hung_lamp(art, frame, Vector3(0, g - step + 6.0, DESCENT_TO_Z - DESCENT_FOOT + 3.0), top, warm, Color(1.0, 0.6, 0.3), 4.5, 26.0)
	_hung_lamp(art, frame, Vector3(0, g - step * 2.0 + 6.0, DESCENT_FROM_Z + 3.0), top, cool, Color(0.35, 0.95, 1.0), 4.5, 26.0)
	_hung_lamp(art, frame, Vector3(0, DESCENT_FLOOR + 7.0, DESCENT_TO_Z - 8.0), top, warm, Color(1.0, 0.6, 0.3), 5.0, 28.0)
	_hung_lamp(art, frame, Vector3(0, g - step * 1.5, mid), top, cool, Color(0.45, 0.7, 1.0), 4.0, 30.0)
	# The well's lining: ribs up its long walls, girders under its roof and
	# pipes down either side of the Heart's door.
	var base := DESCENT_FLOOR
	var z := DESCENT_FROM_Z + 2.0
	while z < DESCENT_TO_Z - 1.0:
		for side: float in [-1.0, 1.0]:
			_deco(Vector3(0.4, top - base, 0.8), Vector3(side * (DESCENT_HALF - 0.2), (top + base) * 0.5, z), HULL_DARK)
		_deco(Vector3(DESCENT_HALF * 2.0, 0.8, 0.6), Vector3(0, top - 0.4, z), HULL_DARK)
		z += 6.0
	for x: float in [-8.0, -7.2, 7.2, 8.0]:
		_deco_cyl(0.3, top - base, Vector3(x, base, DESCENT_TO_Z - 0.4), STEEL)
	for side: float in [-1.0, 1.0]:
		_glow_box(art, frame, Vector3(0.2, 0.12, DESCENT_TO_Z - DESCENT_FROM_Z - 2.0),
				Vector3(side * (DESCENT_HALF - 0.1), g - step, mid), strip)
	var low := DESCENT_FLOOR
	var face := DESCENT_TO_Z - 0.05
	_glow_box(art, frame, Vector3(10.0, 0.4, 0.2), Vector3(0, low + 8.2, face), amber)
	for x: float in [-5.0, 5.0]:
		_glow_box(art, frame, Vector3(0.4, 8.0, 0.2), Vector3(x, low + 4.0, face), amber)
	# The seal's two leaves, drawn back into the wall either side.
	for side: float in [-1.0, 1.0]:
		_deco(Vector3(0.6, HEART_DOOR_UP - 0.2, 1.4), Vector3(side * (HEART_DOOR * 0.5 + 0.3), low + HEART_DOOR_UP * 0.5, face + 0.5), STEEL)
	_flush_deco(art, frame)


## The cable lift: cables up from each cage's head, a light ring on its
## floor and a lamp, red while the lift is dead and teal while it runs
## (`_light_lift`, from the map's "lift_power" meta the `Raid` sets).
func _dress_lift(art: Node3D, frame: Transform3D) -> void:
	_lift_glow = _glow(LIFT_DEAD, 2.0)
	var cable := _glow(Color(0.5, 0.55, 0.6), 0.2)
	for stop: Vector3 in [Vector3(LIFT_TOP.x, HALL_FLOOR, LIFT_TOP.y), Vector3(LIFT_FOOT.x, DESCENT_FLOOR, LIFT_FOOT.y)]:
		var head := HALL_FLOOR + CATWALK_UP - 1.0 if stop.y == HALL_FLOOR else DESCENT_FLOOR + GALLERY_UP
		var roof := HALL_FLOOR + 22.0 if stop.y == HALL_FLOOR else GALLERY_FLOOR + GALLERY_UP + DESCENT_ROOF
		for k: float in [-1.0, 1.0]:
			_glow_box(art, frame, Vector3(0.12, roof - head, 0.12),
					Vector3(stop.x + k * 0.8, (roof + head) * 0.5, stop.z), cable)
		var half := LIFT_CAGE * 0.5 - 0.3
		for k: float in [-1.0, 1.0]:
			_glow_box(art, frame, Vector3(LIFT_CAGE - 0.6, 0.06, 0.15), Vector3(stop.x, stop.y + 0.07, stop.z + k * half), _lift_glow)
			_glow_box(art, frame, Vector3(0.15, 0.06, LIFT_CAGE - 0.6), Vector3(stop.x + k * half, stop.y + 0.07, stop.z), _lift_glow)
		var light := Look.lamp(LIFT_DEAD, 2.0, 9.0)
		light.position = frame * Vector3(stop.x, head - 0.6, stop.z)
		art.add_child(light)
		_lift_lights.append(light)
		_dress_cage(stop, head, roof)
		for cage in _flush_deco(art, frame):
			# A cage you step into: its bars are too thin to stop anyone.
			cage.set_meta("walk_through", "the lift's cage")
	_glow_box(art, frame, Vector3(1.0, 0.5, 0.1), Vector3(LIFT_SWITCH.x, DESCENT_FLOOR + 1.2, LIFT_SWITCH.y + 0.75), _lift_glow)


## A lift cage that reads as one: a deck plate, a frame round its head, a
## barred back to the wall and bars along its sides, and the headgear its
## cables run over, up under the roof.
func _dress_cage(stop: Vector3, head: float, roof: float) -> void:
	var half := LIFT_CAGE * 0.5
	var wall := 1.0 if stop.x > 0.0 else -1.0
	_deco(Vector3(LIFT_CAGE - 0.5, 0.06, LIFT_CAGE - 0.5), stop + Vector3(0, 0.03, 0), STEEL)
	for k: float in [-1.0, 1.0]:
		_deco(Vector3(LIFT_CAGE, 0.3, 0.3), Vector3(stop.x, head - 0.15, stop.z + k * (half - 0.2)), HULL_DARK)
		_deco(Vector3(0.3, 0.3, LIFT_CAGE), Vector3(stop.x + k * (half - 0.2), head - 0.15, stop.z), HULL_DARK)
		# Bars along the sides, above head height and at the waist.
		for up: float in [1.1, head - stop.y - 1.2]:
			_deco(Vector3(LIFT_CAGE - 0.4, 0.1, 0.1), Vector3(stop.x, stop.y + up, stop.z + k * (half - 0.2)), STEEL)
	var bar_x := stop.x + wall * (half - 0.2)
	var z := -half + 0.7
	while z < half - 0.5:
		_deco(Vector3(0.08, head - stop.y - 0.4, 0.08), Vector3(bar_x, (head + stop.y) * 0.5, stop.z + z), STEEL)
		z += 0.5
	_deco(Vector3(3.0, 1.2, 2.2), Vector3(stop.x, roof - 0.6, stop.z), HULL_DARK)
	_deco_cyl(0.8, 0.3, Vector3(stop.x, roof - 2.0, stop.z - 0.15), STEEL, Basis(Vector3.RIGHT, PI / 2.0))
	_deco(Vector3(0.3, 1.0, 0.6), Vector3(stop.x, roof - 1.6, stop.z), HULL_DARK)


## The Heart: ribs up its wall, lamps under its roof, the frozen core hung
## over the middle (`_core_glow`, lit by the keeper's phase), coolant
## strips up the pylons, the sockets lit in the wall, the vault's door, the
## deep beacon's mast (dark until the keeper falls) and the purge lanes,
## hidden until one warns (`show_purge`).
func _dress_heart(art: Node3D, frame: Transform3D, amber: Material) -> void:
	var bottom := DESCENT_FLOOR
	var c := HEART_Z
	var r := HEART_RADIUS
	var roof := bottom + HEART_UP
	var cool := _glow(Color(0.7, 0.95, 1.0), 4.0)
	var coolant := _glow(Color(0.3, 0.9, 1.0), 3.0)
	for spot: Vector2 in [Vector2(0, c + 24.0), Vector2(24.0, c), Vector2(-24.0, c), Vector2(0, c - 24.0)]:
		_hung_lamp(art, frame, Vector3(spot.x, roof - 8.0, spot.y), roof, cool, Color(0.4, 0.8, 1.0), 4.5, 34.0)
	var step := TAU / HEART_SEGMENTS
	for i in HEART_SEGMENTS:
		var a := float(i) * step
		var out := Vector3(sin(a), 0, cos(a))
		var turn := Basis(Vector3.UP, a)
		var from := bottom + (HEART_DOOR_UP + 1.0 if absf(wrapf(a - PI, -PI, PI)) < step * 1.2 else 0.0)
		_deco(Vector3(0.5, roof - from, 0.8), out * (r - 0.3) + Vector3(0, (roof + from) * 0.5, c), HULL_DARK, turn)
		# Roof beams out from the middle.
		if i % 4 == 0:
			_deco(Vector3(0.7, 0.9, r - 6.0), out * (r * 0.5 + 3.0) + Vector3(0, roof - 0.45, c), HULL_DARK, turn)
	# The core: a frozen sphere banded in frost, hung on cables from the roof.
	var core_at := Vector3(0, bottom + 19.0, c)
	_core_glow = _glow(CORE_COLD, 2.5)
	var sphere := SphereMesh.new()
	sphere.radius = 4.5
	sphere.height = 9.0
	sphere.material = _core_glow
	var core := MeshInstance3D.new()
	core.mesh = sphere
	core.position = frame * core_at
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(core)
	for k in 3:
		var band := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, float(k) * PI / 3.0)
		_deco_cyl(4.8, 0.6, core_at - band.y * 0.3, FROST, band)
	for k: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		var top := Vector3(k.x * 6.0, roof, c + k.y * 6.0)
		var low := core_at + Vector3(k.x * 2.6, 2.6, k.y * 2.6)
		var run := top - low
		var basis := Basis(Quaternion(Vector3.UP, run.normalized()))
		_deco_cyl(0.15, run.length(), low, STEEL, basis)
	_core_light = Look.lamp(CORE_COLD, 3.0, 40.0)
	_core_light.position = frame * core_at
	art.add_child(_core_light)
	# The pylons: frost bands and coolant strips up each.
	for spot: Vector2 in heart_pylons():
		var y := bottom + 3.0
		while y < roof - 1.0:
			_deco_cyl(PYLON_RADIUS + 0.2, 0.45, Vector3(spot.x, y, spot.y), FROST)
			y += 6.0
		for k: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_glow_box(art, frame, Vector3(0.18, HEART_UP - 2.0, 0.18),
					Vector3(spot.x + k.x * (PYLON_RADIUS + 0.05), bottom + HEART_UP * 0.5, spot.y + k.y * (PYLON_RADIUS + 0.05)), coolant)
		_deco_cyl(PYLON_RADIUS + 0.6, 1.2, Vector3(spot.x, bottom, spot.y), HULL_DARK)
	# The sockets: a dark recess framed in light, under the balcony.
	for angle: float in HEART_SOCKETS:
		var a := deg_to_rad(angle)
		var out := Vector3(sin(a), 0, cos(a))
		var turn := Basis(Vector3.UP, a)
		var at := out * (r - 0.25) + Vector3(0, bottom, c)
		_deco(Vector3(3.4, 4.6, 0.3), at + Vector3(0, 2.3, 0), HULL_DARK, turn)
		var side := turn.x
		for k: float in [-1.0, 1.0]:
			_glow_box(art, frame, Vector3(0.25, 4.8, 0.25), at - out * 0.2 + side * k * 1.8 + Vector3(0, 2.4, 0), coolant)
		_glow_box(art, frame, Vector3(3.8, 0.25, 0.25), at - out * 0.2 + Vector3(0, 4.8, 0), coolant)
	# The vault's door in the far wall: a round door ringed in amber, bolted.
	var door_at := Vector3(0, bottom + 5.5, c + r - 0.5)
	var face := Basis(Vector3.RIGHT, PI * 0.5)
	_deco_cyl(5.2, 0.5, door_at - face.y * 0.25, HULL_DARK, face)
	_deco_cyl(4.4, 0.6, door_at - face.y * 0.6, STEEL, face)
	for k in 8:
		var a := float(k) * TAU / 8.0
		_deco(Vector3(0.6, 0.6, 0.4), door_at + Vector3(cos(a) * 3.6, sin(a) * 3.6, -0.9), HULL_DARK)
	for k in 16:
		var a := float(k) * TAU / 16.0
		_glow_box(art, frame, Vector3(1.9, 0.25, 0.2), door_at + Vector3(cos(a) * 5.05, sin(a) * 5.05, -0.55), amber)
	_lamp_at(art, frame * (door_at + Vector3(0, 4.0, -4.0)), Color(1.0, 0.65, 0.3), 3.0, 20.0)
	# The deep beacon: a mast, its head dark until the keeper falls.
	var mast := Vector3(0, bottom, c + 20.0)
	_deco(Vector3(0.5, 5.0, 0.5), mast + Vector3(0, 2.5, 0), STEEL)
	_deep_glow = _glow(BEACON_DARK, 0.5)
	_glow_box(art, frame, Vector3(1.0, 0.8, 1.0), mast + Vector3(0, 5.4, 0), _deep_glow)
	for k: float in [-1.0, 1.0]:
		_glow_box(art, frame, Vector3(BEACON["radius"] * 2.0, 0.05, 0.2), mast + Vector3(0, 0.06, k * BEACON["radius"]), _deep_glow)
		_glow_box(art, frame, Vector3(0.2, 0.05, BEACON["radius"] * 2.0), mast + Vector3(k * BEACON["radius"], 0.06, 0), _deep_glow)
	_deep_light = Look.lamp(BEACON_LIT, 0.0, 14.0)
	_deep_light.position = frame * (mast + Vector3(0, 5.0, 0))
	art.add_child(_deep_light)
	_flush_deco(art, frame)
	# The purge lanes: a sheet over the floor that flashes while it warns
	# and a wall of coolant while it vents.
	for lane: Array in heart_purges():
		var from: Vector2 = lane[0]
		var to: Vector2 = lane[1]
		var run := to - from
		var mid := Vector3((from.x + to.x) * 0.5, bottom, (from.y + to.y) * 0.5)
		var turn := Basis(Vector3.UP, atan2(run.x, run.y))
		var sheet_mat := _purge_material()
		var sheet := _visual_box(Vector3(PURGE_WIDTH, 0.04, run.length()), Vector3.ZERO, sheet_mat)
		sheet.transform = frame * Transform3D(turn, mid + Vector3(0, 0.08, 0))
		sheet.visible = false
		art.add_child(sheet)
		var wall_mat := _purge_material()
		var wall := _visual_box(Vector3(PURGE_WIDTH, 2.8, run.length()), Vector3.ZERO, wall_mat)
		wall.transform = frame * Transform3D(turn, mid + Vector3(0, 1.4, 0))
		wall.visible = false
		art.add_child(wall)
		_purge_views.append({"sheet": sheet, "wall": wall, "sheet_mat": sheet_mat, "wall_mat": wall_mat,
				"state": 0, "since": 0.0})


func _purge_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(PURGE_WARN, 0.0)
	return m


const CORE_COLD := Color(0.45, 0.78, 1.0)
const CORE_THAW := Color(1.0, 0.5, 0.2)
const CORE_DEAD := Color(0.12, 0.16, 0.2)
const BEACON_DARK := Color(0.15, 0.2, 0.24)
const BEACON_LIT := Color(1.0, 0.7, 0.35)
const PURGE_WARN := Color(1.0, 0.6, 0.15)
const PURGE_VENT := Color(0.75, 0.95, 1.0)
var _core_glow: StandardMaterial3D
var _core_light: OmniLight3D
var _deep_glow: StandardMaterial3D
var _deep_light: OmniLight3D
var _purge_views: Array[Dictionary] = []
var _heart_phase := 1


## One of the Heart's purge lanes warns (1), vents (2) or goes quiet (0)
## (`Raid.purge_changed`, by its place among the map's "purge" markers;
## view only).
func show_purge(index: int, state: int) -> void:
	if index < 0 or index >= _purge_views.size():
		return
	var view: Dictionary = _purge_views[index]
	view.state = state
	view.since = Time.get_ticks_msec() * 0.001


## Lights the Heart from its keeper's phase (the map's "keepers" meta, set
## by the `Raid`) and plays the purge lanes (view only).
func _light_heart() -> void:
	if _core_glow == null:
		return
	var phase := int((get_meta("keepers", {}) as Dictionary).get(HEART_KEEPER, 1))
	var now := Time.get_ticks_msec() * 0.001
	if phase != _heart_phase:
		_heart_phase = phase
		var lit := phase == 0
		_deep_glow.albedo_color = BEACON_LIT if lit else BEACON_DARK
		_deep_glow.emission = _deep_glow.albedo_color
		_deep_glow.emission_energy_multiplier = 4.0 if lit else 0.5
		_deep_light.light_energy = 5.0 if lit else 0.0
		var color := CORE_COLD if phase == 1 else (CORE_THAW if phase == 2 else CORE_DEAD)
		_core_glow.albedo_color = color
		_core_glow.emission = color
		_core_glow.emission_energy_multiplier = 0.2 if phase == 0 else 2.5
		_core_light.light_color = color
		_core_light.light_energy = 0.3 if phase == 0 else 3.0
	if phase == 2:
		# The thawing core throbs.
		var throb := 0.5 + 0.5 * sin(now * 5.0)
		_core_glow.emission_energy_multiplier = 2.0 + throb * 3.0
		_core_light.light_energy = 2.5 + throb * 2.5
	for view: Dictionary in _purge_views:
		var state := int(view.state)
		var age := now - float(view.since)
		(view.sheet as Node3D).visible = state != 0
		(view.wall as Node3D).visible = state == 2
		if state == 1:
			# Flashing faster as the vent comes.
			var flash := 0.5 + 0.5 * sin(age * (10.0 + age * 14.0))
			(view.sheet_mat as StandardMaterial3D).albedo_color = Color(PURGE_WARN, 0.2 + 0.55 * flash)
		elif state == 2:
			(view.sheet_mat as StandardMaterial3D).albedo_color = Color(PURGE_VENT, 0.85)
			(view.wall_mat as StandardMaterial3D).albedo_color = Color(PURGE_VENT, clampf(0.55 - age * 0.5, 0.1, 0.55))


const LIFT_DEAD := Color(1.0, 0.25, 0.15)
const LIFT_LIVE := Color(0.2, 1.0, 0.85)
var _lift_glow: StandardMaterial3D
var _lift_lights: Array[OmniLight3D] = []
var _lift_live := false


## Lights the lift while it runs (view only).
func _light_lift() -> void:
	if _lift_glow == null:
		return
	var powers: Dictionary = get_meta("lift_power", {})
	var live := float(powers.get(LIFT_ID, 0.0)) > 0.0
	if live == _lift_live:
		return
	_lift_live = live
	var color := LIFT_LIVE if live else LIFT_DEAD
	_lift_glow.albedo_color = color
	_lift_glow.emission = color
	for light in _lift_lights:
		light.light_color = color


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## A lit strip with no collision, in the drum's frame.
func _glow_box(art: Node3D, frame: Transform3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = frame * Transform3D(Basis.IDENTITY, at)
	art.add_child(node)


## Decoration merged like `_part` but with no collision: boxes and
## cylinders in the drum's frame, one mesh per material per `_flush_deco`.
var _deco_batches := {}


func _deco(size: Vector3, at: Vector3, material: Material, basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_deco_batch(material).append_from(mesh, 0, Transform3D(basis, at))


## A cylinder standing on `at` (its axis up, or turned by `basis`).
func _deco_cyl(radius: float, height: float, at: Vector3, material: Material, basis := Basis.IDENTITY) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	_deco_batch(material).append_from(mesh, 0, Transform3D(basis, at + basis.y * height * 0.5))


func _deco_batch(material: Material) -> SurfaceTool:
	if not _deco_batches.has(material):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_deco_batches[material] = tool
	return _deco_batches[material]


func _flush_deco(art: Node3D, frame: Transform3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for material: Material in _deco_batches:
		var mesh := (_deco_batches[material] as SurfaceTool).commit()
		mesh.surface_set_material(0, material)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.transform = frame
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.add_child(node)
		out.append(node)
	_deco_batches.clear()
	return out


## A lamp hung from the roof at `roof`: a rod, a housing and a lit panel
## under it, so the light comes from something.
func _hung_lamp(art: Node3D, frame: Transform3D, at: Vector3, roof: float, panel: Material, color: Color,
		energy: float, reach: float) -> void:
	if roof - at.y > 0.6:
		_deco(Vector3(0.1, roof - at.y, 0.1), Vector3(at.x, (roof + at.y) * 0.5, at.z), STEEL)
	_deco(Vector3(1.6, 0.35, 0.9), at + Vector3(0, 0.15, 0), HULL_DARK)
	_deco(Vector3(1.4, 0.05, 0.7), at - Vector3(0, 0.05, 0), panel)
	_lamp_at(art, frame * (at - Vector3(0, 0.5, 0)), color, energy, reach)


func _lamp_at(art: Node3D, at: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := Look.lamp(color, energy, reach)
	light.position = at
	art.add_child(light)


## Past the valley's walls the Glacier's own land runs on to the horizon;
## none of it collides. The land near the map's edge is raised
## (`FAR_RIM`) to meet the mountains the heightfield ends on. The planet's
## boulders and shards stand only up on those mountains, past the rim
## (`PROPS_PAST_RIM`), never where anyone fights or takes cover.
func _dress_horizon(art: Node3D) -> void:
	var recipe := planet.terrain.duplicate()
	recipe["rim"] = FAR_RIM
	var land := PlanetTerrain.new(recipe, LAYOUT_SEED)
	var half := terrain.extent() * 0.5
	art.add_child(Planet.horizon(planet, land, half))
	var height_of := func(x: float, z: float) -> float:
		return terrain.height_at(x, z) if maxf(absf(x), absf(z)) < half else land.height_at(x, z)
	var clear := func(x: float, z: float) -> bool:
		return absf(x - centre(z)) - half_width(z) > RIM_TO + PROPS_PAST_RIM
	PlanetProps.scatter(art, planet, height_of, half, LAYOUT_SEED + 3, clear)
