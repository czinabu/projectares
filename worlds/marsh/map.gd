extends Node3D
## Greybox Spore Marsh: a drowned basin about 400 metres across, ringed by
## low wooded hills (DESIGN.md "More worlds", "Spore Marsh").
##
## Players come in on the dry southern shore. North of it the ground breaks
## up into hummocks between pools of black water, and the fungus forests
## stand in it: giant stalks close enough together that a fight in one is
## over in a few metres (Caleb's call: mist and fungus keep fights short).
## The richest caches lie on the biggest caps, which only flight reaches,
## and in the hollows at the heart of each forest. The north end, the core,
## is the Grey Matriarch's den.
##
## The layout uses a fixed seed, so the map is the same every time while loot
## and spawns vary. The rest of the game relies only on the map contract in
## WorldDef. The ground, its collision and the navigation mesh are worked out
## once per run of the game and shared by every copy of the map.
##
## It stands on the Spore Marsh planet type (DESIGN.md "Planet kit"): its
## sky, its moss and black water on the ground, its mist and its drifting
## spores, all view only.

const Flora := preload("res://worlds/marsh/flora.gd")
const Rootway := preload("res://worlds/marsh/rootway.gd")

const LAYOUT_SEED := 7171
## Metres between ground samples, and how many there are along each edge.
const CELL := 2.0
const SIDE := 241
## How far from the middle the basin floor reaches before the hills rise.
const BASIN := 190.0
## The black water's surface. Pools are dug below it; the hummocks stand
## a little over it.
const WATER_Y := 0.0
const DRY := 0.6
const POOL_DEPTH := 1.1
## The zones run south to north: the shore, the drowned middle, the core.
const MIDDLE_FROM_Z := 70.0
const CORE_FROM_Z := -70.0
## The southern shore, where players arrive: kept dry and open.
const SHORE_Z := 150.0
## The fungus forests: where each stands, how far it reaches, and how many
## stalks it holds. The last, in the core, is the Matriarch's.
const FORESTS := [
	{"at": Vector2(-95.0, 70.0), "radius": 38.0, "stalks": 26, "name": "the Westwood"},
	{"at": Vector2(85.0, 45.0), "radius": 34.0, "stalks": 22, "name": "the Gillwood"},
	{"at": Vector2(-30.0, -20.0), "radius": 42.0, "stalks": 30, "name": "the Deepwood"},
	{"at": Vector2(110.0, -85.0), "radius": 32.0, "stalks": 20, "name": "the Rotwood"},
	{"at": Vector2(-15.0, -140.0), "radius": 40.0, "stalks": 28, "name": "the Matriarch's den"},
]
## A stalk's trunk: never closer to the next than this, so squads get
## through (Caleb's ask: no way narrower than 9 m is for dungeons; out
## here 5 m between trunks keeps a forest walkable for a party).
const STALK_GAP := 5.0
## The survey stations: old huts on the dry ground with a depot each.
const STATIONS := [
	{"at": Vector2(30.0, 95.0), "name": "Survey Two"},
	{"at": Vector2(-120.0, -40.0), "name": "Survey Five"},
	{"at": Vector2(130.0, -10.0), "name": "Survey Seven"},
]
## The Grey Matriarch's lair, in the heart of the core forest.
const DEN := Vector2(-15.0, -150.0)
const DEN_RADIUS := 22.0
## The hills past the basin: nobody goes there.
const HILLS := 30.0
## How far past the map's edge the planet's own land starts.
const FAR_RIM := 60.0

## Kept from the first map built in this run: { navmesh }.
static var _shared := {}
## The ground may be worked out on another thread ahead of a visit
## (`prepare_shared`); whoever comes second waits for the first.
static var _ground_lock := Mutex.new()
static var _ground_shared := {}

var nav_region: NavigationRegion3D
var terrain: Terrain
var _rng := RandomNumberGenerator.new()
## Dressing has its own generator so art never shifts the gameplay layout.
var _art_rng := RandomNumberGenerator.new()
## How awake each stalk's gills are (0 to 1), by `_stalks` index; view only.
var _gill_glow: Array[float] = []
var _noise := FastNoiseLite.new()
var _pools := FastNoiseLite.new()
## Every stalk placed: { at (its foot), radius, height, cap (cap radius) }.
var _stalks: Array[Dictionary] = []
var _stations: Array[Vector3] = []
var _stalk_bodies: Array[StaticBody3D] = []
## Where each hive stands (its foot), for the dressing.
var _hives: Array[Vector3]
## The far giants (`Flora.build_giants`), view only.
var _giants: MeshInstance3D
## Bot spawn spots, placed last in order of `rank`: the Raid fills the first
## `bot_count` markers at the start, so every kind comes early.
var _bot_spots: Array[Dictionary] = []
var _weather: Node3D
## Each Rootway's navigation region (`Rootway.build`), baked with the map's.
var _rootways: Array[NavigationRegion3D] = []
## The Rootways' vents and chamber lights (`Rootway.dress`), view only.
var _rootway_views := {}
## The planet the map stands on (`WorldDef.planet_type`), set before it
## enters the tree; a map made on its own (as the checks do) takes the marsh.
var planet: PlanetType

@onready var STALK := Look.surface("concrete", {"tint": Color(0.5, 0.46, 0.4), "grime": 0.6, "scale": 0.2})
@onready var CAP := Look.surface("concrete", {"tint": Color(0.38, 0.46, 0.4), "grime": 0.3, "scale": 0.1})
@onready var HUT := Look.surface("metal", {"tint": Color(0.4, 0.43, 0.4), "grime": 0.8, "scale": 0.3})


func _ready() -> void:
	if planet == null:
		planet = PlanetTypes.get_type("marsh")
	_seed_layout()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_shore()
	_build_forests()
	_build_stations()
	_build_den()
	_build_open()
	_build_hives()
	_build_lurkers()
	var root_floor := Look.surface("ground", {"tint": Color(0.5, 0.46, 0.36), "grime": 0.7, "scale": 0.3})
	_rootways = Rootway.build(self, root_floor, Rootway.wall_material() if Look.enabled else STALK)
	_place_bot_spots()
	_art_rng.seed = LAYOUT_SEED
	_dress()
	set_process(Look.enabled)


func _seed_layout() -> void:
	_rng.seed = LAYOUT_SEED
	_noise.seed = LAYOUT_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.035
	_pools.seed = LAYOUT_SEED + 1
	_pools.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_pools.frequency = 0.012


## Works out the ground every copy of this map shares, on a map that is
## never added to the tree (`WorldDef.prepare_map`, off the main thread).
func prepare_shared() -> void:
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		_seed_layout()
		terrain = Terrain.new()
		terrain.cell = CELL
		terrain.side = SIDE
		terrain.holes = Rootway.holes()
		terrain.shape(_height)
		_ground_shared["collision"] = terrain.collision_data()
		_ground_shared["heights"] = terrain.heights
		terrain.free()
		terrain = null
	_ground_lock.unlock()


func bake_navigation() -> void:
	if not _shared.has("navmesh"):
		var navmesh := _new_navmesh()
		nav_region.navigation_mesh = navmesh
		nav_region.bake_navigation_mesh(false)
		_shared["navmesh"] = navmesh
	nav_region.navigation_mesh = _shared["navmesh"]
	for i in _rootways.size():
		var key := "rootway%d" % i
		if not _shared.has(key):
			var navmesh := _new_navmesh()
			_rootways[i].navigation_mesh = navmesh
			_rootways[i].bake_navigation_mesh(false)
			_shared[key] = navmesh
		_rootways[i].navigation_mesh = _shared[key]


func _new_navmesh() -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = Actor.LAYER_WORLD
	navmesh.cell_size = 0.5
	navmesh.cell_height = 0.25
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.5
	navmesh.agent_max_slope = 42.0
	return navmesh


## The height of the ground at a point on the map.
func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## Whether a point is under the black water (its surface is `WATER_Y`).
func in_water(pos: Vector3) -> bool:
	return pos.y < WATER_Y and ground_height(pos.x, pos.z) < WATER_Y - 0.1


func _process(_delta: float) -> void:
	# The spores drift round whoever is looking, not over the whole basin.
	var camera := get_viewport().get_camera_3d()
	if camera != null and is_instance_valid(_weather):
		_weather.global_position = Vector3(camera.global_position.x, camera.global_position.y - 6.0,
				camera.global_position.z)
	# Under the caps the mist shuts in (the planet's close air), and the far
	# giants go into it, as they do in a storm.
	if camera != null:
		var close := close_at(camera.global_position.x, camera.global_position.z)
		# Down a Rootway the air is as close as it gets.
		if Rootway.inside(camera.global_position):
			close = 1.0
		set_meta("close_here", close)
		if _giants != null:
			Flora.set_veil(_giants, maxf(close, float(get_meta("weather_here", 0.0))))
	if not _rootway_views.is_empty():
		Rootway.animate(_rootway_views, get_meta("keepers", {}), Time.get_ticks_msec() * 0.001)


## One of the Rootways' spore vents warns (1), vents (2) or goes quiet (0)
## (`Raid.purge_changed`, by its place among the map's "purge" markers;
## view only).
func show_purge(index: int, state: int) -> void:
	var vents: Array = _rootway_views.get("vents", [])
	if index < 0 or index >= vents.size():
		return
	var view: Dictionary = vents[index]
	view.state = state
	view.since = Time.get_ticks_msec() * 0.001


## How far a point is under a forest's caps, 0 out in the open to 1 well
## inside: the close air the view blends in ("close_here") and the sight a
## bot has there (the world's `sight_at`). From the layout alone.
const CLOSE_INSIDE := 6.0
const CLOSE_OUTSIDE := 14.0
static func close_at(x: float, z: float) -> float:
	var most := 0.0
	for forest: Dictionary in FORESTS:
		var radius := float(forest["radius"])
		var dist := Vector2(x, z).distance_to(forest["at"])
		most = maxf(most, 1.0 - smoothstep(radius - CLOSE_INSIDE, radius + CLOSE_OUTSIDE, dist))
	return most


func _build_environment() -> void:
	# A drowned basin at dusk: the planet's green sky and pale moons, the
	# mist lying low over the water (the planet's "smoke") and the spores
	# drifting in it. The forests' gills are the warm lights.
	# The mist banks lie on the water, never under it.
	set_meta("mist_floor", WATER_Y)
	Planet.atmosphere(self, planet)
	Planet.weather(self, str(planet.weather.get("air", "spores")), 36.0, 18.0)
	_weather = get_node_or_null("Weather")


# --- The shape of the basin -------------------------------------------------------

## How much of a point the pools take: over 0 is under the black water.
func _wet(x: float, z: float) -> float:
	var w := _pools.get_noise_2d(x, z) * 1.6 - 0.05
	# The shore and the station yards are dry.
	w -= smoothstep(SHORE_Z - 30.0, SHORE_Z + 10.0, z) * 1.5
	for station: Dictionary in STATIONS:
		var at: Vector2 = station["at"]
		w -= (1.0 - smoothstep(10.0, 22.0, Vector2(x, z).distance_to(at))) * 1.5
	w -= (1.0 - smoothstep(DEN_RADIUS * 0.6, DEN_RADIUS + 6.0, Vector2(x, z).distance_to(DEN))) * 1.5
	return w


func _height(x: float, z: float) -> float:
	var n := _noise.get_noise_2d(x, z)
	var wet := _wet(x, z)
	var h := WATER_Y + DRY + 0.5 + n * 0.8
	if wet > 0.0:
		# Under the black water: a soft bank down to the pool's bed.
		h = lerpf(h, WATER_Y - POOL_DEPTH + n * 0.2, smoothstep(0.0, 0.35, wet))
	# The hills round the basin.
	# Rounded at the corners, so the slope has no crease.
	var corner := 40.0
	var out := Vector2(maxf(absf(x) - BASIN + corner, 0.0), maxf(absf(z) - BASIN + corner, 0.0)).length() - corner
	if out > 0.0:
		h = lerpf(h, WATER_Y + DRY + 26.0, smoothstep(0.0, HILLS, out))
	return h


func _build_ground() -> void:
	terrain = Terrain.new()
	terrain.name = "Ground"
	terrain.cell = CELL
	terrain.side = SIDE
	# The Rootways' cuts are open ground.
	terrain.holes = Rootway.holes()
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		terrain.shape(_height)
		_ground_shared["collision"] = terrain.collision_data()
		_ground_shared["heights"] = terrain.heights
	var collision: PackedFloat32Array = _ground_shared["collision"]
	terrain.heights = _ground_shared["heights"]
	_ground_lock.unlock()
	terrain.build(Planet.ground_material(planet), collision)
	nav_region.add_child(terrain)
	# Nobody leaves over the hills.
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


## The southern shore: where players arrive, with a depot either side.
func _build_shore() -> void:
	for i in 6:
		var x := (i - 2.5) * 22.0
		var z := SHORE_Z + 18.0 + (i % 2) * 8.0
		_add_marker("spawn_player", _ground(Vector2(x, z)))
	for side: float in [-1.0, 1.0]:
		_add_depot(_ground(Vector2(side * 45.0, SHORE_Z + 4.0)))


## The fungus forests: stalks stood a few metres apart, each a trunk and a
## cap. The tallest caps hold a cache only flight reaches, and the forest's
## heart a hollow cache among the roots. Stalker packs den in them.
func _build_forests() -> void:
	for f in FORESTS.size():
		var forest: Dictionary = FORESTS[f]
		var centre: Vector2 = forest["at"]
		var radius: float = forest["radius"]
		var placed: Array[Dictionary] = []
		var tries := 0
		while placed.size() < int(forest["stalks"]) and tries < 400:
			tries += 1
			var at := centre + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius
			var trunk := _rng.randf_range(0.6, 1.5)
			var ok := true
			for other: Dictionary in _stalks:
				if Vector2(other.at.x, other.at.z).distance_to(at) < STALK_GAP + trunk + float(other.radius):
					ok = false
					break
			# Leave the heart open for the hollow, and the den for its keeper.
			if at.distance_to(centre) < 7.0 or (f == FORESTS.size() - 1 and at.distance_to(DEN) < DEN_RADIUS * 0.6):
				ok = false
			if not ok:
				continue
			var height := trunk * _rng.randf_range(9.0, 14.0)
			var stalk := {"at": _ground(at), "radius": trunk, "height": height, "cap": trunk * 5.5}
			_add_stalk(stalk)
			placed.append(stalk)
		# The tallest two caps hold the cap caches.
		placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.height > b.height)
		for k in mini(2, placed.size()):
			var top: Dictionary = placed[k]
			_add_marker("spawn_cache", top.at + Vector3(0, top.height + 0.6, 0)).set_meta("loot_source", "cap")
		# The hollow at the heart: a ring of roots round the cache.
		var heart := _ground(centre)
		for r in 5:
			var root := _box(Vector3(3.2, 1.1, 0.9), heart + Vector3.FORWARD.rotated(Vector3.UP, r * TAU / 5.0) * 4.2
					+ Vector3(0, 0.3, 0), STALK)
			root.rotation = Vector3(0, r * TAU / 5.0 + PI / 2.0, 0.15)
		_add_marker("spawn_cache", heart + Vector3(0, 0.1, 0)).set_meta("loot_source", "hollow")
		# Its stalker pack, round the heart; a bloater or two drifts at the edges.
		if f < FORESTS.size() - 1:
			for k in 3:
				_bot_spot(_ground(centre + Vector2.from_angle(k * TAU / 3.0) * 10.0), "stalker", 0 if k == 0 else 3)
			_bot_spot(_ground(centre + Vector2.from_angle(f * 1.3) * (radius - 4.0)), "bloater", 1)


func _add_stalk(stalk: Dictionary) -> void:
	_stalks.append(stalk)
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = stalk.at
	_stalk_bodies.append(body)
	body.set_meta("height", stalk.height)
	body.set_meta("cap", stalk.cap)
	nav_region.add_child(body)
	var trunk := CylinderShape3D.new()
	trunk.radius = stalk.radius
	trunk.height = stalk.height
	var col := CollisionShape3D.new()
	col.shape = trunk
	col.position = Vector3(0, stalk.height * 0.5 - 0.5, 0)
	body.add_child(col)
	var cap := CylinderShape3D.new()
	cap.radius = stalk.cap
	cap.height = 0.6
	var cap_col := CollisionShape3D.new()
	cap_col.shape = cap
	cap_col.position = Vector3(0, stalk.height, 0)
	body.add_child(cap_col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = stalk.radius * 0.8
	mesh.bottom_radius = stalk.radius
	mesh.height = stalk.height
	mesh.radial_segments = 10
	mesh.material = STALK
	var node := MeshInstance3D.new()
	node.name = "Trunk"
	node.mesh = mesh
	node.position = col.position
	body.add_child(node)
	var top := CylinderMesh.new()
	top.top_radius = stalk.cap * 0.7
	top.bottom_radius = stalk.cap
	top.height = 0.6
	top.radial_segments = 16
	top.material = CAP
	var cap_node := MeshInstance3D.new()
	cap_node.name = "Cap"
	cap_node.mesh = top
	cap_node.position = cap_col.position
	body.add_child(cap_node)


## The survey stations: a hut with its back to the water, a depot by its
## door and a cache inside. Shellbacks graze the banks round them.
func _build_stations() -> void:
	for i in STATIONS.size():
		var station: Dictionary = STATIONS[i]
		var at: Vector2 = station["at"]
		var base := _ground(at)
		_stations.append(base)
		var hut := Node3D.new()
		hut.position = base
		hut.rotation.y = i * 1.1
		nav_region.add_child(hut)
		for part: Array in [
				[Vector3(7.0, 3.4, 0.3), Vector3(0, 1.7, -3.0)],
				[Vector3(0.3, 3.4, 6.0), Vector3(-3.4, 1.7, 0)],
				[Vector3(0.3, 3.4, 6.0), Vector3(3.4, 1.7, 0)],
				[Vector3(7.4, 0.3, 6.6), Vector3(0, 3.55, 0)]]:
			_box(part[0], part[1], HUT, hut)
		_add_marker("spawn_cache", base + Vector3(0, 0.1, 0)).set_meta("loot_source", "station")
		_add_depot(_ground(at + Vector2(0, 9.0).rotated(-hut.rotation.y)))
		_bot_spot(_ground(at + Vector2(16.0, 0).rotated(i * 2.0)), "shellback", 0 if i == 0 else 2)
		_bot_spot(_ground(at + Vector2(-14.0, 6.0).rotated(i * 2.0)), "bloater", 4)


## The Grey Matriarch's den: a clearing ringed by roots in the core forest.
func _build_den() -> void:
	var at := _ground(DEN)
	for r in 9:
		if r == 4:
			# The way in, from the south.
			continue
		var spot := at + Vector3.FORWARD.rotated(Vector3.UP, r * TAU / 9.0) * DEN_RADIUS
		var root := _box(Vector3(6.0, 1.6, 1.4), spot + Vector3(0, 0.5, 0), STALK)
		root.rotation = Vector3(0, r * TAU / 9.0 + PI / 2.0, 0.1)
	var boss := _add_marker("spawn_boss", at + Vector3(0, 0.1, 0))
	boss.set_meta("boss", "matriarch")
	boss.set_meta("faction", "stalker")
	boss.set_meta("radius", DEN_RADIUS)
	_add_marker("spawn_cache", at + Vector3(4.0, 0.1, -6.0)).set_meta("loot_source", "den")
	for k in 2:
		_bot_spot(_ground(DEN + Vector2(-8.0 + k * 16.0, 12.0)), "stalker", 1)


## The open marsh between the forests: hummocks with a cache now and then,
## and the shellbacks and bloaters that wander it.
func _build_open() -> void:
	var placed := 0
	var tries := 0
	while placed < 18 and tries < 300:
		tries += 1
		var at := Vector2(_rng.randf_range(-170.0, 170.0), _rng.randf_range(-170.0, SHORE_Z - 10.0))
		if _wet(at.x, at.y) > -0.1 or _near_forest(at, 6.0):
			continue
		_add_marker("spawn_cache", _ground(at) + Vector3(0, 0.1, 0))
		if placed % 3 == 0:
			_bot_spot(_ground(at + Vector2(6.0, 0)), "shellback" if placed % 2 == 0 else "bloater", 2)
		placed += 1


## A brood hive in each forest but the Matriarch's: a mound of chitin and
## egg sacs a little off the forest's heart, sealed while its brood keeper
## stands ("spawn_guard" with the same "hive"), spilling broodlings at
## anyone near it. No dice: it takes the first clear spot round the heart.
const HIVE_FROM_HEART := 15.0
const HIVE_CLEAR := 4.5
const BROOD := {"brood": "broodling", "brood_every": 7.0, "brood_max": 4, "brood_range": 24.0}


func _build_hives() -> void:
	for f in FORESTS.size() - 1:
		var forest: Dictionary = FORESTS[f]
		var centre: Vector2 = forest["at"]
		# The first dry spot round the heart, else the driest one there is
		# (the Deepwood stands in its pools).
		var spot := Vector2.INF
		var driest := INF
		for out in [HIVE_FROM_HEART, HIVE_FROM_HEART - 4.0, HIVE_FROM_HEART + 4.0, HIVE_FROM_HEART + 8.0, HIVE_FROM_HEART + 14.0]:
			for k in 24:
				var at := centre + Vector2.from_angle(f * 1.9 + k * TAU / 24.0) * float(out)
				if not _clear_of_stalks(at, HIVE_CLEAR):
					continue
				var wet := _wet(at.x, at.y)
				if wet < driest:
					driest = wet
					spot = at
			if driest < 0.0:
				break
		if not spot.is_finite():
			continue
		var foot := _ground(spot)
		_hives.append(foot)
		var key := "hive%d" % f
		var body := StaticBody3D.new()
		body.name = "Hive"
		body.collision_layer = Actor.LAYER_WORLD
		body.collision_mask = 0
		body.position = foot
		nav_region.add_child(body)
		var shape := CylinderShape3D.new()
		shape.radius = 1.7
		shape.height = 2.6
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(0, 1.1, 0)
		body.add_child(col)
		var mound := SphereMesh.new()
		mound.radius = 1.9
		mound.height = 3.0
		mound.material = CAP
		var mesh := MeshInstance3D.new()
		mesh.name = "Mound"
		mesh.mesh = mound
		mesh.position = Vector3(0, 0.9, 0)
		body.add_child(mesh)
		var cache := _add_marker("spawn_cache", foot + Vector3(0, 0.1, -2.6))
		cache.set_meta("loot_source", "hive")
		cache.set_meta("hive", key)
		var guard := _add_marker("spawn_guard", _ground(spot + (centre - spot).normalized() * 5.0))
		guard.set_meta("faction", "keeper")
		guard.set_meta("hive", key)
		guard.set_meta("radius", 9.0)
		for meta: String in BROOD:
			guard.set_meta(meta, BROOD[meta])


func _clear_of_stalks(at: Vector2, margin: float) -> bool:
	for stalk: Dictionary in _stalks:
		if Vector2(stalk.at.x, stalk.at.z).distance_to(at) < float(stalk.radius) + margin:
			return false
	return true


## Lurkers lie at the deepest spots of the pools, well apart, out of the
## forests and off the shore: each a "spawn_guard" that never leaves its
## pool. Found by a fixed sweep of the basin, no dice.
const LURKERS := 7
const LURKER_GAP := 45.0
const LURKER_DEEP := 0.6


func _build_lurkers() -> void:
	var spots: Array[Vector2] = []
	var step := 6.0
	var z := -170.0
	while z < SHORE_Z - 30.0 and spots.size() < LURKERS:
		var x := -170.0 + fmod(absf(z) * 0.37, step)
		while x < 170.0 and spots.size() < LURKERS:
			var at := Vector2(x, z)
			x += step
			if _wet(at.x, at.y) < LURKER_DEEP or _near_forest(at, 6.0):
				continue
			if spots.any(func(other: Vector2) -> bool: return other.distance_to(at) < LURKER_GAP):
				continue
			spots.append(at)
		z += step * 1.7
	for at in spots:
		var guard := _add_marker("spawn_guard", _ground(at))
		guard.set_meta("faction", "lurker")
		guard.set_meta("radius", 4.0)


func _near_forest(at: Vector2, margin: float) -> bool:
	for forest: Dictionary in FORESTS:
		if at.distance_to(forest["at"]) < float(forest["radius"]) + margin:
			return true
	return false


func _bot_spot(at: Vector3, faction: String, rank: int) -> void:
	_bot_spots.append({"at": at, "faction": faction, "rank": rank, "order": _bot_spots.size()})


func _place_bot_spots() -> void:
	_bot_spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rank < b.rank or (a.rank == b.rank and a.order < b.order))
	for spot in _bot_spots:
		_add_marker("spawn_bot", spot.at).set_meta("faction", spot.faction)


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
	_dress_water(art)
	_dress_stalks(art)
	_dress_horizon(art)


## The black water: one dark, glossy sheet at the waterline over the whole
## basin; the ground stands through it wherever it is dry. It is left out
## over the Rootways' cuts, which go down below it.
func _dress_water(art: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.008, 0.014, 0.013, 0.96)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.22
	mat.metallic = 0.0
	mat.metallic_specular = 0.35
	var reach := BASIN + 10.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for piece in water_pieces(Rect2(-reach, -reach, reach * 2.0, reach * 2.0), Rootway.holes()):
		var a := Vector3(piece.position.x, 0.0, piece.position.y)
		var b := Vector3(piece.end.x, 0.0, piece.position.y)
		var c := Vector3(piece.end.x, 0.0, piece.end.y)
		var d := Vector3(piece.position.x, 0.0, piece.end.y)
		for p: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(p)
	st.set_material(mat)
	var water := MeshInstance3D.new()
	water.name = "BlackWater"
	water.mesh = st.commit()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0, WATER_Y, 0)
	art.add_child(water)


## `area` less the `holes`, as rectangles: bands across z between the
## holes' edges, each split along x round the holes it crosses.
static func water_pieces(area: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var edges: Array[float] = [area.position.y, area.end.y]
	for hole in holes:
		edges.append(clampf(hole.position.y, area.position.y, area.end.y))
		edges.append(clampf(hole.end.y, area.position.y, area.end.y))
	edges.sort()
	var out: Array[Rect2] = []
	for i in edges.size() - 1:
		var z0 := edges[i]
		var z1 := edges[i + 1]
		if z1 - z0 < 0.001:
			continue
		var mid := (z0 + z1) * 0.5
		var cuts: Array[Vector2] = []
		for hole in holes:
			if mid > hole.position.y and mid < hole.end.y:
				cuts.append(Vector2(hole.position.x, hole.end.x))
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var x := area.position.x
		for cut in cuts:
			if cut.x > x:
				out.append(Rect2(x, z0, cut.x - x, z1 - z0))
			x = maxf(x, cut.y)
		if area.end.x > x:
			out.append(Rect2(x, z0, area.end.x - x, z1 - z0))
	return out


## Whether (x, z) is in a Rootway's cut, where nothing of the floor grows.
func in_cut(x: float, z: float) -> bool:
	return Rootway.in_cut(x, z)


## The giant fungus over the greybox stalks, all of it one mesh for the
## flesh and one for the gills (`fungus.gdshader`): a tapering trunk that
## flares at the foot and leans a little, a broad cap whose top sits on the
## cap's collision (so standing on it looks right) and whose rim curls
## down, and glowing gills under it.
func _dress_stalks(art: Node3D) -> void:
	var flesh := SurfaceTool.new()
	flesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gills := SurfaceTool.new()
	gills.begin(Mesh.PRIMITIVE_TRIANGLES)
	for stalk: Dictionary in _stalks:
		_fungus(flesh, gills, stalk)
	for body: StaticBody3D in _stalk_bodies:
		for child in body.get_children():
			if child is MeshInstance3D:
				child.visible = false
	var shader := load("res://assets/shaders/fungus.gdshader") as Shader
	var flesh_mat := ShaderMaterial.new()
	flesh_mat.shader = shader
	var gill_mat := ShaderMaterial.new()
	gill_mat.shader = shader
	gill_mat.set_shader_parameter("gills", 1.0)
	flesh.generate_normals()
	gills.generate_normals()
	flesh.set_material(flesh_mat)
	gills.set_material(gill_mat)
	var mesh := flesh.commit()
	gills.commit(mesh)
	var node := MeshInstance3D.new()
	node.name = "Fungus"
	node.mesh = mesh
	art.add_child(node)
	_dress_gill_lights(art)
	_dress_glowcaps(art)
	_dress_moss(art)
	_dress_reeds(art)
	_dress_hives(art)
	Flora.build_floor(self, art, LAYOUT_SEED + 23)
	_rootway_views = Rootway.dress(art, LAYOUT_SEED + 31, ground_height)


const FUNGUS_SIDES := 14
const FUNGUS_RINGS := 10
const CAP_RINGS := 7


## One stalk, in the map's space, into the two surfaces.
func _fungus(flesh: SurfaceTool, gills: SurfaceTool, stalk: Dictionary) -> void:
	var foot: Vector3 = stalk.at
	var h: float = stalk.height
	var r: float = stalk.radius
	var big: float = stalk.cap
	var lean := Vector2(_art_rng.randf_range(-1.0, 1.0), _art_rng.randf_range(-1.0, 1.0)) * r * 0.35
	var twist := _art_rng.randf() * TAU
	# Each cap's own gills (`fungus.gdshader` reads the vertex colour): how
	# bright (most dim, a few awake), which way the hue leans and how fine
	# the ribs run. Small caps glow less.
	var awake := pow(_art_rng.randf(), 1.3) * lerpf(0.5, 1.0, smoothstep(6.0, 18.0, h))
	var tone := Color(0.3 + 0.7 * awake, _art_rng.randf(), _art_rng.randf(), 1.0)
	_gill_glow.append(awake)
	var centre := func(t: float) -> Vector3:
		return foot + Vector3(lean.x * t * t, -0.8 + t * (h + 0.9), lean.y * t * t)
	var trunk_r := func(t: float) -> float:
		return r * lerpf(1.0, 0.72, t) * (1.0 + 0.9 * (1.0 - smoothstep(0.0, 0.14, t)))
	# The trunk, ridged lengthways.
	var rings: Array[PackedVector3Array] = []
	var vs: Array[float] = []
	for ri in FUNGUS_RINGS + 1:
		var t := float(ri) / FUNGUS_RINGS
		var ring := PackedVector3Array()
		for si in FUNGUS_SIDES:
			var a := TAU * si / FUNGUS_SIDES + twist
			var ridge := 1.0 + 0.07 * sin(a * 5.0 + t * 4.0)
			ring.append(centre.call(t) + Vector3(cos(a), 0, sin(a)) * trunk_r.call(t) * ridge)
		rings.append(ring)
		vs.append(t * 0.92)
	# The cap's top, from the middle out to the curled rim.
	var top_at: Vector3 = centre.call(1.0)
	var middle := Vector3(top_at.x, foot.y + h + 0.35, top_at.z)
	var top_y := func(s: float) -> float:
		return middle.y - big * 0.16 * pow(s, 2.2) - big * 0.1 * pow(s, 8.0)
	var cap: Array[PackedVector3Array] = []
	for ri in CAP_RINGS + 1:
		var s := float(ri) / CAP_RINGS
		var ring := PackedVector3Array()
		for si in FUNGUS_SIDES * 2:
			var a := TAU * si / (FUNGUS_SIDES * 2) + twist
			var wob := 1.0 + 0.05 * sin(a * 3.0 + twist * 2.0) * s
			ring.append(Vector3(middle.x + cos(a) * big * s * wob, top_y.call(s), middle.z + sin(a) * big * s * wob))
		cap.append(ring)
	_lathe(flesh, rings, vs, false, tone)
	var cap_v: Array[float] = []
	for ri in CAP_RINGS + 1:
		cap_v.append(1.0)
	_lathe(flesh, cap, cap_v, true, tone)
	# The gills: from the rim (just under its edge) back in to the trunk.
	var under: Array[PackedVector3Array] = []
	var stem := float(trunk_r.call(1.0)) / big
	for ri in CAP_RINGS + 1:
		var s := lerpf(1.0, stem, float(ri) / CAP_RINGS)
		var ring := PackedVector3Array()
		for si in FUNGUS_SIDES * 2:
			var a := TAU * si / (FUNGUS_SIDES * 2) + twist
			var wob := 1.0 + 0.05 * sin(a * 3.0 + twist * 2.0) * s
			var y: float = top_y.call(s) - 0.18 - (1.0 - s) * big * 0.1
			ring.append(Vector3(middle.x + cos(a) * big * s * wob, y, middle.z + sin(a) * big * s * wob))
		under.append(ring)
	_lathe(gills, under, cap_v, true, tone)


## Joins rings of points into a band of quads facing out (or up, for a cap
## whose rings run outward); `v` is each ring's UV.y, `tone` every vertex's
## colour.
func _lathe(st: SurfaceTool, rings: Array[PackedVector3Array], v: Array[float], outward: bool, tone := Color.WHITE) -> void:
	for ri in rings.size() - 1:
		var a_ring := rings[ri]
		var b_ring := rings[ri + 1]
		var n := a_ring.size()
		for si in n:
			var sj := (si + 1) % n
			var quad := [a_ring[si], a_ring[sj], b_ring[si], b_ring[sj]]
			var u0 := float(si) / n
			var u1 := float(si + 1) / n
			var uv := [Vector2(u0, v[ri]), Vector2(u1, v[ri]), Vector2(u0, v[ri + 1]), Vector2(u1, v[ri + 1])]
			var order := [0, 2, 1, 1, 2, 3] if outward else [0, 1, 2, 1, 3, 2]
			for k: int in order:
				st.set_color(tone)
				st.set_uv(uv[k])
				st.add_vertex(quad[k])


## A few warm lights under the biggest caps, so the forests glow at dusk.
func _dress_gill_lights(art: Node3D) -> void:
	var lit := 0
	for i in _stalks.size():
		var stalk: Dictionary = _stalks[i]
		if float(stalk.height) < 14.0 or _gill_glow[i] < 0.35 or lit >= 24:
			continue
		lit += 1
		var light := OmniLight3D.new()
		light.light_color = Color(0.45, 1.0, 0.75)
		light.light_energy = 0.4 + 0.8 * _gill_glow[i]
		light.omni_range = float(stalk.cap) * 2.2
		light.shadow_enabled = false
		light.position = stalk.at + Vector3(0, float(stalk.height) - 1.0, 0)
		art.add_child(light)


## Small glowcaps in clumps over the forests' floors and along the banks:
## one mesh, drawn many times, lighting the ground a little at dusk.
func _dress_glowcaps(art: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem: Array[PackedVector3Array] = []
	var cap: Array[PackedVector3Array] = []
	var v: Array[float] = []
	for ri in 3:
		var t := ri / 2.0
		var ring := PackedVector3Array()
		var dome := PackedVector3Array()
		for si in 8:
			var a := TAU * si / 8.0
			ring.append(Vector3(cos(a) * 0.035, t * 0.22, sin(a) * 0.035))
			var s := float(ri) / 2.0
			dome.append(Vector3(cos(a) * 0.13 * s, 0.27 - 0.08 * s * s, sin(a) * 0.13 * s))
		stem.append(ring)
		cap.append(dome)
		v.append(t)
	_lathe(st, stem, v, false)
	_lathe(st, cap, v, true)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.55, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 0.6)
	mat.emission_energy_multiplier = 0.9
	mat.roughness = 0.4
	st.set_material(mat)
	var caps := MultiMesh.new()
	caps.transform_format = MultiMesh.TRANSFORM_3D
	caps.mesh = st.commit()
	var spots: Array[Transform3D] = []
	var tries := 0
	while spots.size() < GLOWCAPS and tries < GLOWCAPS * 6:
		tries += 1
		var forest: Dictionary = FORESTS[_art_rng.randi() % FORESTS.size()]
		var clump: Vector2 = forest["at"] + Vector2.from_angle(_art_rng.randf() * TAU) * _art_rng.randf() * (float(forest["radius"]) + 12.0)
		var ground := ground_height(clump.x, clump.y)
		if ground < WATER_Y + 0.05:
			continue
		for k in _art_rng.randi_range(3, 9):
			var at := clump + Vector2(_art_rng.randf_range(-0.9, 0.9), _art_rng.randf_range(-0.9, 0.9))
			var size := _art_rng.randf_range(0.6, 2.2)
			var basis := Basis(Vector3.UP, _art_rng.randf() * TAU).scaled(Vector3.ONE * size)
			if in_cut(at.x, at.y):
				continue
			spots.append(Transform3D(basis, Vector3(at.x, ground_height(at.x, at.y) - 0.02, at.y)))
	caps.instance_count = spots.size()
	for i in spots.size():
		caps.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Glowcaps"
	node.multimesh = caps
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(node)


const GLOWCAPS := 1400
const MOSS := 3200
const REEDS := 2600


## Moss hummocks: low soft mounds round each stalk's foot and over the
## forests' floors, thinning out to the bare mud between them.
func _dress_moss(art: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dome: Array[PackedVector3Array] = []
	var v: Array[float] = []
	for ri in 4:
		var s := float(ri) / 3.0
		var ring := PackedVector3Array()
		for si in 9:
			var a := TAU * si / 9.0
			var wob := 1.0 + 0.18 * sin(a * 3.0)
			ring.append(Vector3(cos(a) * s * wob, 0.2 * (1.0 - s * s) - 0.04, sin(a) * s * wob))
		dome.append(ring)
		v.append(s)
	_lathe(st, dome, v, true)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.36, 0.5, 0.2)
	mat.albedo_texture = load(Planet.surface_path(String(planet.surfaces["base"]), "Color"))
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.6
	mat.roughness = 1.0
	st.set_material(mat)
	var moss := MultiMesh.new()
	moss.transform_format = MultiMesh.TRANSFORM_3D
	moss.use_colors = true
	moss.mesh = st.commit()
	var spots: Array[Transform3D] = []
	var tints: Array[Color] = []
	var tries := 0
	while spots.size() < MOSS and tries < MOSS * 4:
		tries += 1
		var at: Vector2
		if tries % 3 == 0:
			var forest: Dictionary = FORESTS[_art_rng.randi() % FORESTS.size()]
			at = forest["at"] + Vector2.from_angle(_art_rng.randf() * TAU) * sqrt(_art_rng.randf()) * float(forest["radius"])
		else:
			var stalk: Dictionary = _stalks[_art_rng.randi() % _stalks.size()]
			var foot: Vector3 = stalk.at
			at = Vector2(foot.x, foot.z) + Vector2.from_angle(_art_rng.randf() * TAU) * (float(stalk.radius) * 1.6 + _art_rng.randf() * 4.0)
		var ground := ground_height(at.x, at.y)
		if ground < WATER_Y - 0.1 or in_cut(at.x, at.y):
			continue
		var size := _art_rng.randf_range(0.4, 1.4)
		var basis := Basis(Vector3.UP, _art_rng.randf() * TAU).scaled(Vector3(size * _art_rng.randf_range(0.8, 1.6), size * 0.6, size))
		spots.append(Transform3D(basis, Vector3(at.x, ground, at.y)))
		tints.append(Color(0.9, 1.0, 0.9).lerp(Color(0.55, 0.62, 0.4), _art_rng.randf()))
	moss.instance_count = spots.size()
	for i in spots.size():
		moss.set_instance_transform(i, spots[i])
		moss.set_instance_color(i, tints[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Moss"
	node.multimesh = moss
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(node)


## Each hive's egg sacs: lit, swollen globes heaped on the mound and
## spilling round its foot, and a low light under them.
func _dress_hives(art: Node3D) -> void:
	if _hives.is_empty():
		return
	var egg := SphereMesh.new()
	egg.radius = 0.5
	egg.height = 1.0
	egg.radial_segments = 12
	egg.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.62, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.95, 0.45)
	mat.emission_energy_multiplier = 0.8
	mat.roughness = 0.3
	egg.material = mat
	var eggs := MultiMesh.new()
	eggs.transform_format = MultiMesh.TRANSFORM_3D
	eggs.mesh = egg
	var spots: Array[Transform3D] = []
	for foot in _hives:
		for i in 26:
			var a := _art_rng.randf() * TAU
			var r := _art_rng.randf_range(0.6, 2.6)
			var up := maxf(0.0, 2.0 - r * 0.75) + _art_rng.randf() * 0.3
			var size := _art_rng.randf_range(0.25, 0.6)
			spots.append(Transform3D(Basis.from_scale(Vector3(size, size * 1.25, size)),
					foot + Vector3(cos(a) * r, up, sin(a) * r)))
		var light := OmniLight3D.new()
		light.light_color = Color(0.6, 1.0, 0.5)
		light.light_energy = 0.9
		light.omni_range = 9.0
		light.position = foot + Vector3(0, 1.5, 0)
		art.add_child(light)
	eggs.instance_count = spots.size()
	for i in spots.size():
		eggs.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = "HiveEggs"
	node.multimesh = eggs
	art.add_child(node)


## Reeds where the black water meets the mud: clumps of thin blades, a few
## with seed heads, along every bank.
func _dress_reeds(art: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LAYOUT_SEED + 11
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 11:
		var a := TAU * b / 11.0 + rng.randf() * 0.5
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.35)
		var tall := rng.randf_range(0.9, 1.9)
		var foot := Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.18 - Vector3(0, 0.15, 0)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.022
		var top := foot + Vector3(0, tall, 0) + lean
		var mid := foot + Vector3(0, tall * 0.55, 0) + lean * 0.3
		# A blade: two quads narrowing to a point, darker at the foot.
		var dark := Color(0.55, 0.6, 0.5)
		for tri in [[foot - side, foot + side, mid + side * 0.7], [foot - side, mid + side * 0.7, mid - side * 0.7], [mid - side * 0.7, mid + side * 0.7, top]]:
			for p: Vector3 in tri:
				st.set_color(dark.lerp(Color.WHITE, clampf((p.y + 0.15) / tall, 0.0, 1.0)))
				st.add_vertex(p)
		if b % 4 == 0:
			# A seed head: a dark spindle near the top.
			var head := foot + Vector3(0, tall * 0.85, 0) + lean * 0.7
			var w := Vector3(-sin(a), 0, cos(a)) * 0.05
			var up := Vector3(0, 0.16, 0)
			for tri in [[head - w, head + w, head + up], [head - w, head - up, head + w]]:
				for p: Vector3 in tri:
					st.set_color(Color(0.35, 0.22, 0.14))
					st.add_vertex(p)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.26, 0.3, 0.14)
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var reeds := MultiMesh.new()
	reeds.transform_format = MultiMesh.TRANSFORM_3D
	reeds.mesh = st.commit()
	var spots: Array[Transform3D] = []
	var tries := 0
	while spots.size() < REEDS and tries < REEDS * 30:
		tries += 1
		var at := Vector2(_art_rng.randf_range(-BASIN, BASIN), _art_rng.randf_range(-BASIN, BASIN))
		var ground := ground_height(at.x, at.y)
		# Only the edge: just under the water to just over it.
		if ground < WATER_Y - 0.4 or ground > WATER_Y + 0.3 or in_cut(at.x, at.y):
			continue
		var size := _art_rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, _art_rng.randf() * TAU).scaled(Vector3(size, size * _art_rng.randf_range(0.8, 1.3), size))
		spots.append(Transform3D(basis, Vector3(at.x, ground, at.y)))
	reeds.instance_count = spots.size()
	for i in spots.size():
		reeds.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Reeds"
	node.multimesh = reeds
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(node)


func _dress_horizon(art: Node3D) -> void:
	var recipe := planet.terrain.duplicate()
	recipe["rim"] = FAR_RIM
	var land := PlanetTerrain.new(recipe, LAYOUT_SEED)
	var half := terrain.extent() * 0.5
	art.add_child(Planet.horizon(planet, land, half))
	var height_of := func(x: float, z: float) -> float:
		return terrain.height_at(x, z) if maxf(absf(x), absf(z)) < half else land.height_at(x, z)
	var clear := func(x: float, z: float) -> bool:
		return maxf(absf(x), absf(z)) > BASIN + 8.0
	PlanetProps.scatter(art, planet, height_of, half, LAYOUT_SEED + 3, clear)
	# The giants far off in the haze (Caleb's call: scale).
	_giants = Flora.build_giants(self, art, height_of, LAYOUT_SEED + 21, (planet.sky.get("horizon_color", Color.GRAY) as Color).lerp(planet.calm.get("fog_color", Color.GRAY) as Color, 0.5))
