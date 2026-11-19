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
var _noise := FastNoiseLite.new()
var _pools := FastNoiseLite.new()
## Every stalk placed: { at (its foot), radius, height, cap (cap radius) }.
var _stalks: Array[Dictionary] = []
var _stations: Array[Vector3] = []
var _stalk_bodies: Array[StaticBody3D] = []
## Bot spawn spots, placed last in order of `rank`: the Raid fills the first
## `bot_count` markers at the start, so every kind comes early.
var _bot_spots: Array[Dictionary] = []
var _weather: Node3D
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


## Whether a point is under the black water (its surface is `WATER_Y`).
func in_water(pos: Vector3) -> bool:
	return pos.y < WATER_Y and ground_height(pos.x, pos.z) < WATER_Y - 0.1


func _process(_delta: float) -> void:
	# The spores drift round whoever is looking, not over the whole basin.
	var camera := get_viewport().get_camera_3d()
	if camera != null and is_instance_valid(_weather):
		_weather.global_position = Vector3(camera.global_position.x, camera.global_position.y - 6.0,
				camera.global_position.z)


func _build_environment() -> void:
	# A drowned basin at dusk: the planet's green sky and pale moons, the
	# mist lying low over the water (the planet's "smoke") and the spores
	# drifting in it. The forests' gills are the warm lights.
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
## basin; the ground stands through it wherever it is dry.
func _dress_water(art: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.008, 0.014, 0.013, 0.96)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.22
	mat.metallic = 0.0
	mat.metallic_specular = 0.35
	var plane := PlaneMesh.new()
	plane.size = Vector2(BASIN * 2.0 + 20.0, BASIN * 2.0 + 20.0)
	plane.material = mat
	var water := MeshInstance3D.new()
	water.name = "BlackWater"
	water.mesh = plane
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0, WATER_Y, 0)
	art.add_child(water)


## Each stalk wears the planet's own fungus (a ridged stem, a curling cap
## and glowing gills) over its greybox trunk, scaled to it.
func _dress_stalks(art: Node3D) -> void:
	for body: StaticBody3D in _stalk_bodies:
		var height: float = body.get_meta("height", 10.0)
		var across := float(body.get_meta("cap", 3.0)) / 0.32
		var stalk := MeshInstance3D.new()
		var shape := PlanetProps.mesh("stalk", _art_rng.randi() % PlanetProps.VARIANTS, planet) as ArrayMesh
		stalk.mesh = shape
		var turned := Basis(Vector3.UP, _art_rng.randf() * TAU) * Basis.from_scale(Vector3(across, height, across))
		# The planet's stalks lean; stand this one so its cap is over the
		# trunk, where the cap stands to be walked on.
		if shape != null and shape.get_surface_count() > 1:
			var top: Vector3 = turned * (shape.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
			var tilt := Basis(Quaternion(top.normalized(), Vector3.UP))
			turned = tilt * Basis(Vector3.UP, 0.0).scaled(Vector3.ONE * height / maxf(top.length(), 0.01)) * turned
		stalk.transform = Transform3D(turned, body.position + Vector3(0, -0.4, 0))
		art.add_child(stalk)
		for child in body.get_children():
			if child is MeshInstance3D:
				child.visible = false
	_dress_gill_lights(art)


## A few warm lights under the biggest caps, so the forests glow at dusk.
func _dress_gill_lights(art: Node3D) -> void:
	var lit := 0
	for stalk: Dictionary in _stalks:
		if float(stalk.height) < 14.0 or lit >= 24:
			continue
		lit += 1
		var light := OmniLight3D.new()
		light.light_color = Color(0.45, 1.0, 0.75)
		light.light_energy = 1.2
		light.omni_range = float(stalk.cap) * 2.2
		light.shadow_enabled = false
		light.position = stalk.at + Vector3(0, float(stalk.height) - 1.0, 0)
		art.add_child(light)


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
