extends Node3D
## The Dune Sea's map (DESIGN.md "The Dune Sea"): about 1.8 km of
## wind-built dunes on the dunes planet's ground (`PlanetTerrain`), three
## times Ashfront's width. Players land at the south edge beside a gate
## outpost, two depots and a row of parked rovers. Wreck fields lie across
## the sand, each a few buried hulks with salvage crates ("spawn_crate")
## and raiders picking over them; salvage yards (strongpoints, each with a
## depot) are where a haul is banked out in the field; the Wreck Baron
## holds the deep sea in the north. Gameplay shapes are plain boxes that
## `Look` dresses; decoration uses `_art_rng`, never `_rng`, so it cannot
## move the layout.

## Seeds the layout. Change it and every spot moves.
const LAYOUT_SEED := 6196
## The ground: `SIDE` samples `CELL` metres apart, (SIDE - 1) * CELL across.
const CELL := 4.0
const SIDE := 461
## Half the playable square; the planet's rim rises past it to the walls.
const FIELD := 860.0
const HILLS := 40.0
## Where the zones change (the world's `zone_at`): south is outer.
const MIDDLE_FROM_Z := 420.0
const CORE_FROM_Z := -320.0
## Where players land.
const LANDING_Z := 800.0
## The salvage yards (strongpoints, each with a depot): name and where.
const SITES := [
	{"name": "West Yard", "at": Vector2(-480.0, 220.0)},
	{"name": "The Crossing", "at": Vector2(0.0, 80.0)},
	{"name": "East Yard", "at": Vector2(480.0, 220.0)},
	{"name": "Deep Yard", "at": Vector2(0.0, -420.0)},
]
## The wreck fields: where, how many hulks lie there and how many salvage
## crates stand among them. More and richer further north.
const WRECKS := [
	{"at": Vector2(-560.0, 600.0), "hulks": 3, "crates": 2},
	{"at": Vector2(300.0, 620.0), "hulks": 3, "crates": 2},
	{"at": Vector2(-240.0, 360.0), "hulks": 4, "crates": 3},
	{"at": Vector2(640.0, -20.0), "hulks": 4, "crates": 3},
	{"at": Vector2(-660.0, -120.0), "hulks": 4, "crates": 3},
	{"at": Vector2(240.0, -220.0), "hulks": 5, "crates": 4},
	{"at": Vector2(-340.0, -620.0), "hulks": 5, "crates": 4},
	{"at": Vector2(520.0, -640.0), "hulks": 5, "crates": 4},
]
## How far round a wreck field the ground is laid flat for its hulks.
const WRECK_RADIUS := 34.0
## A buried hauler's hull: long, half sunk in the sand.
const HULK := Vector3(5.0, 3.4, 14.0)
## How far a buried wreck field's hulks go down under the sand: past their
## tops, tilt and all.
const BURY_DEPTH := 4.0
## The share of each dune its steep lee face takes (`PlanetTerrain`
## "dune_slip"): wide enough that a rover climbs it, still a dune's shape.
const DUNE_SLIP := 0.36
## How much the far ring round the map smooths the dunes (`Planet.horizon`).
const HORIZON_SMOOTH := 1.0
## The Wreck Baron's ground in the deep sea.
const BOSS_AT := Vector2(0.0, -760.0)

## The ground every copy of the map shares, worked out once per run.
static var _ground_lock := Mutex.new()
static var _ground_shared := {}
static var _shared := {}

var planet: PlanetType
var terrain: Terrain
var nav_region: NavigationRegion3D
var _rng := RandomNumberGenerator.new()
var _art_rng := RandomNumberGenerator.new()
var _land: PlanetTerrain

@onready var WALL := Look.surface("concrete", {"tint": Color(0.5, 0.5, 0.48), "grime": 0.5, "scale": 0.25})
@onready var METAL := Look.surface("metal", {"tint": Color(0.42, 0.44, 0.45), "grime": 0.7, "scale": 0.3})
## A buried hauler's sand-scoured, rusted plate.
@onready var HULL := Look.surface("metal", {"tint": Color(0.78, 0.5, 0.32), "grime": 0.9, "scale": 0.15})


func _ready() -> void:
	if planet == null:
		planet = PlanetTypes.get_type("dunes")
	_seed_layout()
	Planet.atmosphere(self, planet)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_landing()
	_build_sites()
	_build_wrecks()
	_build_core()
	_art_rng.seed = LAYOUT_SEED + 1
	_dress()


func _seed_layout() -> void:
	_rng.seed = LAYOUT_SEED
	var recipe := PlanetTypes.get_type("dunes").terrain.duplicate()
	recipe["field"] = FIELD
	# Sand you can drive: no terrace steps on the playable sand (they stay
	# on the rim's buttes past it) and slip faces a wheel can climb.
	recipe["terrace_field"] = 0.0
	recipe["dune_slip"] = DUNE_SLIP
	_land = PlanetTerrain.new(recipe, LAYOUT_SEED)


## Works out the shared ground on a map never added to the tree (the
## world's `prepare_map`, off the main thread): plain data only.
func prepare_shared() -> void:
	_ground_lock.lock()
	if not _ground_shared.has("heights"):
		_seed_layout()
		var ground := Terrain.new()
		ground.cell = CELL
		ground.side = SIDE
		ground.shape(_height)
		_ground_shared["collision"] = ground.collision_data()
		_ground_shared["heights"] = ground.heights
		ground.free()
	_ground_lock.unlock()


func bake_navigation() -> void:
	if not _shared.has("navmesh"):
		var navmesh := NavigationMesh.new()
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		navmesh.geometry_collision_mask = Actor.LAYER_WORLD
		navmesh.cell_size = 1.0
		navmesh.cell_height = 0.5
		navmesh.agent_radius = 0.5
		navmesh.agent_height = 1.75
		navmesh.agent_max_climb = 0.5
		navmesh.agent_max_slope = 42.0
		nav_region.navigation_mesh = navmesh
		nav_region.bake_navigation_mesh(false)
		_shared["navmesh"] = navmesh
	nav_region.navigation_mesh = _shared["navmesh"]


func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## The roads a convoy drives (the world's `convoy_vehicles`): yard to yard
## across the open sand, passing the wreck fields at 60 m, clear of their
## hulks and the yards' walls.
const CONVOY_ROUTES := [
	[Vector2(-480.0, 175.0), Vector2(-300.0, 330.0), Vector2(-60.0, 80.0), Vector2(240.0, -160.0), Vector2(0.0, -370.0)],
	[Vector2(480.0, 175.0), Vector2(580.0, -20.0), Vector2(240.0, -160.0), Vector2(60.0, -420.0)],
	[Vector2(-480.0, 175.0), Vector2(-600.0, -120.0), Vector2(-340.0, -560.0), Vector2(-60.0, -420.0)],
	[Vector2(-480.0, 175.0), Vector2(0.0, 140.0), Vector2(480.0, 175.0)],
]


func convoy_routes() -> Array:
	var out := []
	for route: Array in CONVOY_ROUTES:
		var points: Array[Vector3] = []
		for i in route.size() - 1:
			# A point every 60 m or so, so the road follows the sand.
			var from: Vector2 = route[i]
			var to: Vector2 = route[i + 1]
			var steps := maxi(1, ceili(from.distance_to(to) / 60.0))
			for s in steps:
				points.append(_ground(from.lerp(to, float(s) / steps)))
		points.append(_ground(route[route.size() - 1]))
		out.append(points)
	return out


# --- The shape of the ground -------------------------------------------------

## The planet's dunes, laid flat round the landing, the yards and the wreck
## fields (to the dunes' own height there, so a flat sits in the sand), rising
## to the rim past the field.
func _height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _land.height_at(x, z)
	var flat := 1.0 - smoothstep(30.0, 60.0, p.distance_to(Vector2(0.0, LANDING_Z)))
	var level := _land.height_at(0.0, LANDING_Z) if flat > 0.0 else 0.0
	for site: Dictionary in SITES:
		var near := 1.0 - smoothstep(30.0, 50.0, p.distance_to(site["at"]))
		if near > flat:
			flat = near
			level = _land.height_at((site["at"] as Vector2).x, (site["at"] as Vector2).y)
	for wreck: Dictionary in WRECKS:
		var near := 1.0 - smoothstep(WRECK_RADIUS, WRECK_RADIUS + 22.0, p.distance_to(wreck["at"]))
		if near > flat:
			flat = near
			level = _land.height_at((wreck["at"] as Vector2).x, (wreck["at"] as Vector2).y)
	var boss := 1.0 - smoothstep(34.0, 54.0, p.distance_to(BOSS_AT))
	if boss > flat:
		flat = boss
		level = _land.height_at(BOSS_AT.x, BOSS_AT.y)
	return lerpf(h, level, flat)


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


# --- Places ------------------------------------------------------------------

## The landing at the south edge: player spawns inside a gate outpost, a
## depot either side and a row of parked vehicles, rovers mostly, for the
## haul.
func _build_landing() -> void:
	var outpost := _add_marker("outpost", _ground(Vector2(0.0, LANDING_Z)))
	outpost.set_meta("name", "Dune Sea Gate")
	outpost.set_meta("radius", 16.0)
	for i in 6:
		_add_marker("spawn_player", _ground(Vector2((i - 2.5) * 5.0, LANDING_Z + 4.0 + (i % 2) * 3.0)))
	for side: float in [-1.0, 1.0]:
		_add_depot(_ground(Vector2(side * 12.0, LANDING_Z - 6.0)))
		for i in 3:
			var spot := _add_marker("spawn_vehicle", _ground(Vector2(side * (24.0 + i * 6.0), LANDING_Z - 4.0))
					+ Vector3(0, 0.5, 0))
			spot.rotation.y = PI
	_box(Vector3(18.0, 0.4, 10.0), _ground(Vector2(0.0, LANDING_Z + 4.0)) + Vector3(0, 0.2, 0), METAL)


## The strongpoints across the middle: a low walled yard each, a depot by
## it, a cache inside and the faction's soldiers posted round it.
func _build_sites() -> void:
	for site: Dictionary in SITES:
		var at: Vector2 = site["at"]
		var point := _add_marker("strongpoint", _ground(at))
		point.set_meta("name", site["name"])
		point.set_meta("radius", 14.0)
		for side in 4:
			var along := Vector2.from_angle(side * PI * 0.5)
			var across := Vector2(-along.y, along.x)
			for half: float in [-1.0, 1.0]:
				var spot := at + along * 16.0 + across * half * 9.0
				# Sunk a little into the ground, so no gap opens under it.
				_box(Vector3(10.0 if absf(along.x) < 0.5 else 1.2, 1.8, 1.2 if absf(along.x) < 0.5 else 10.0),
						_ground(spot) + Vector3(0, 0.6, 0), WALL)
		_add_depot(_ground(at + Vector2(24.0, 0.0)))
		_add_marker("spawn_cache", _ground(at + Vector2(-5.0, 5.0)) + Vector3(0, 0.1, 0))
		for i in 3:
			_add_marker("spawn_bot", _ground(at + Vector2.from_angle(i * TAU / 3.0) * 8.0)).set_meta("faction", "dunes")


## The wreck fields: buried haulers half sunk in the sand, salvage crates
## standing among them, a cache in one hull's lee, raiders picking it over
## and a vehicle left at the edge of some.
func _build_wrecks() -> void:
	for index in WRECKS.size():
		var wreck: Dictionary = WRECKS[index]
		var at: Vector2 = wreck["at"]
		var hulks := int(wreck["hulks"])
		var lie := _rng.randf() * TAU
		# The field a sandstorm can bury: its hulks are its children, so
		# they sink with it.
		var field := Marker3D.new()
		field.name = "WreckField%d" % index
		field.add_to_group("salvage_field")
		field.position = _ground(at)
		field.set_meta("radius", WRECK_RADIUS)
		field.set_meta("sink", BURY_DEPTH)
		field.set_meta("title", "a wreck field")
		nav_region.add_child(field)
		for i in hulks:
			var spot := at + Vector2.from_angle(lie + i * TAU / hulks) * _rng.randf_range(12.0, WRECK_RADIUS - 10.0)
			var hull := _box(HULK, _ground(spot) + Vector3(0, HULK.y * 0.5 - 1.2, 0) - field.position, HULL, field)
			hull.rotation = Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf() * TAU, _rng.randf_range(-0.1, 0.1))
			hull.name = "Hulk"
		for i in int(wreck["crates"]):
			var spot := at + Vector2.from_angle(lie + (i + 0.5) * TAU / hulks) * _rng.randf_range(5.0, 9.0)
			_add_marker("spawn_crate", _ground(spot))
		_add_marker("spawn_cache", _ground(at + Vector2.from_angle(lie + PI) * 3.0) + Vector3(0, 0.1, 0))
		for i in 2 + index / 3:
			_add_marker("spawn_bot", _ground(at + Vector2.from_angle(lie + i * 2.1 + 1.0) * 18.0)).set_meta("faction", "dunes")
		# Every other field has a Dune Burrower under its sand (the world's
		# `equip_bot` makes a guard of faction "burrower" one), posted
		# between the hulks where the crates are carried out.
		if index % 2 == 1:
			var lair := _add_marker("spawn_guard", _ground(at + Vector2.from_angle(lie + PI * 1.5) * WRECK_RADIUS * 0.4))
			lair.set_meta("faction", "burrower")
			lair.set_meta("radius", 6.0)
		if index % 2 == 0:
			var parked := _add_marker("spawn_vehicle", _ground(at + Vector2.from_angle(lie + PI * 0.5) * (WRECK_RADIUS + 6.0))
					+ Vector3(0, 0.5, 0))
			parked.rotation.y = lie


## The core: the warlord's ground with the best caches.
func _build_core() -> void:
	var boss := _add_marker("spawn_boss", _ground(BOSS_AT))
	boss.set_meta("faction", "dunes")
	boss.set_meta("radius", 25.0)
	for i in 3:
		_add_marker("spawn_cache", _ground(BOSS_AT + Vector2.from_angle(i * TAU / 3.0 + 0.4) * 12.0) + Vector3(0, 0.1, 0))
	for i in 4:
		var at := BOSS_AT + Vector2.from_angle(i * PI * 0.5 + PI * 0.25) * 20.0
		_box(Vector3(4.0, 3.0, 4.0), _ground(at) + Vector3(0, 1.5, 0), WALL)


## View only: the planet's land runs on past the walls to the horizon, its
## spires and boulders standing out there (never on the playable sand, where
## anything that stands is a solid of its own). Its own seed, so it never
## moves the layout.
func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	var land := far_land()
	var half := terrain.extent() * 0.5
	art.add_child(Planet.horizon(planet, land, half, HORIZON_SMOOTH))
	var height_of := func(x: float, z: float) -> float:
		return terrain.height_at(x, z) if maxf(absf(x), absf(z)) < half else land.height_at(x, z)
	var clear := func(x: float, z: float) -> bool:
		return maxf(absf(x), absf(z)) > FIELD + 20.0
	PlanetProps.scatter(art, planet, height_of, half, LAYOUT_SEED + 3, clear)


## The ground of the far ring round the map (`Planet.horizon`) and the props
## out there: the same ground as the playable sand (`_land`, its field and
## all), so the ring meets the map's edge at the map's height instead of
## standing tens of metres over it. It is drawn smoothed (`HORIZON_SMOOTH`),
## so the dunes' slip faces and the rim's terraces read as dunes out there,
## not as sheets folded into the sky.
func far_land() -> PlanetTerrain:
	return _land


# --- Helpers -----------------------------------------------------------------

func _ground(at: Vector2) -> Vector3:
	return terrain.on_ground(at.x, at.y)


func _near_site(at: Vector2, margin: float) -> bool:
	for site: Dictionary in SITES:
		if at.distance_to(site["at"]) < margin:
			return true
	for wreck: Dictionary in WRECKS:
		if at.distance_to(wreck["at"]) < margin:
			return true
	return at.distance_to(BOSS_AT) < margin


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


## A solid greybox block (collision and a mesh `Look` dresses).
func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> StaticBody3D:
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
	(parent if parent != null else nav_region).add_child(body)
	return body
