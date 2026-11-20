extends Node3D
## The Basalt Rift's map (DESIGN.md "Basalt Rift (part one)"): a small,
## tall world over a sea of lava. The rift is about 300 m across inside
## cliffs. Nothing stands on its floor: the lava covers it (the world's
## `molten_level`, `LAVA_Y`) and burns whoever goes in. Everything you can
## stand on is basalt rising out of it:
##   - the Gate Shelf, a ledge on the south cliff where players land, with
##     the gate outpost and two depots;
##   - three mesas holding the strongpoints (`SITES`): the West and East
##     Stacks and, higher, the Anvil in the middle;
##   - iron bridges joining the Shelf and the three mesas, the only ways a
##     bot (or anyone without a rig) gets about;
##   - perches, single columns at every height, some with a cache and some
##     with a soldier, reached only by flying;
##   - the Crown in the north, the warlord's mesa, higher than any rig can
##     climb from the lava: only an updraft gets you there.
## Updrafts (`VENTS`) rise from vents in the lava: anyone in the air over
## one is carried up to its top (`updraft_at`, asked by the world's
## `updraft_at`). Gameplay shapes are plain shapes `Look` dresses; the lava
## sheet, the vents' glow and embers and everything past the cliffs are
## decoration on `_art_rng`, never `_rng`, so they cannot move the layout.

## Seeds the layout. Change it and every perch moves.
const LAYOUT_SEED := 7250
## The ground: `SIDE` samples `CELL` metres apart, (SIDE - 1) * CELL across.
const CELL := 4.0
const SIDE := 101
## Half the rift's floor; the cliffs climb past it over `RIM` metres to
## `CLIFF` high.
const FIELD := 150.0
const RIM := 50.0
const CLIFF := 64.0
## How far past the field the walls stand.
const EDGE := 8.0
## The rift's floor, under the lava, and the lava's top (the world's
## `molten_level`).
const FLOOR_Y := -4.0
const LAVA_Y := 0.0
## Where the zones change (the world's `zone_at`): south is outer.
const MIDDLE_FROM_Z := 60.0
const CORE_FROM_Z := -70.0
## The Gate Shelf: its top, its middle and its size across and deep. Its
## back runs into the south cliff.
const SHELF_TOP := 24.0
const SHELF_AT := Vector2(0.0, 134.0)
const SHELF_SIZE := Vector2(70.0, 44.0)
## The strongpoints, each on a mesa: name, where, how high its top stands
## and how wide it is.
const SITES := [
	{"name": "West Stack", "at": Vector2(-85.0, 10.0), "top": 18.0, "radius": 17.0},
	{"name": "The Anvil", "at": Vector2(0.0, -15.0), "top": 30.0, "radius": 19.0},
	{"name": "East Stack", "at": Vector2(85.0, 10.0), "top": 18.0, "radius": 17.0},
]
## The Crown, the warlord's mesa: no bridge reaches it.
const CROWN := {"name": "The Crown", "at": Vector2(0.0, -115.0), "top": 62.0, "radius": 20.0}
const BOSS_AT := Vector2(0.0, -115.0)
## The bridges, each between two places: "shelf_w", "shelf", "shelf_e" (the
## Shelf's front corners and middle) or a site's index.
const BRIDGES := [["shelf", 1], ["shelf_w", 0], ["shelf_e", 2], [0, 1], [2, 1]]
const BRIDGE_WIDTH := 3.5
## Updrafts: where each vent is in the lava and how high its air rises.
## Anyone in the air within `VENT_RADIUS` is carried up at up to
## `VENT_RISE` m/s (full in its middle `VENT_CORE` share, easing to nothing
## at its edge), easing off over the last `VENT_EASE` metres to its top.
const VENTS := [
	{"name": "Gate Draft", "at": Vector2(-17.0, 82.0), "top": 62.0},
	{"name": "Anvil Draft", "at": Vector2(28.0, 52.0), "top": 58.0},
	{"name": "West Draft", "at": Vector2(-118.0, -55.0), "top": 74.0},
	{"name": "East Draft", "at": Vector2(118.0, -55.0), "top": 74.0},
	{"name": "Crown Draft West", "at": Vector2(-34.0, -78.0), "top": 92.0},
	{"name": "Crown Draft East", "at": Vector2(34.0, -78.0), "top": 92.0},
]
const VENT_RADIUS := 8.0
const VENT_CORE := 0.6
const VENT_RISE := 9.0
const VENT_EASE := 12.0
## Perches: how many single columns stand about the rift, and their sizes.
const PERCHES := 24
const PERCH_RADIUS := Vector2(2.5, 6.0)
const PERCH_TOP := Vector2(6.0, 54.0)

## The ground every copy of the map shares, worked out once per run.
static var _ground_lock := Mutex.new()
static var _ground_shared := {}
static var _shared := {}

var planet: PlanetType
var terrain: Terrain
var nav_region: NavigationRegion3D
## Every perch placed: {at (Vector2), radius, top}. Read by the tests.
var perches: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _art_rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _rock: Material

@onready var METAL := Look.surface("metal", {"tint": Color(0.3, 0.27, 0.25), "grime": 0.8, "scale": 0.3})


func _ready() -> void:
	if planet == null:
		planet = PlanetTypes.get_type("basalt")
	_seed_layout()
	Planet.atmosphere(self, planet)
	_rock = Planet.ground_material(planet)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_shelf()
	_build_sites()
	_build_crown()
	_build_bridges()
	_build_perches()
	_art_rng.seed = LAYOUT_SEED + 1
	_dress()


func _seed_layout() -> void:
	_rng.seed = LAYOUT_SEED
	_noise.seed = LAYOUT_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.02


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


## Only what stands in the navigation region is walked: the Shelf, the
## mesas, the bridges and the perches. The rift's floor under the lava is
## outside it, so no bot ever plans a path through the lava.
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


## The rift's floor under the lava (and the cliffs past it): where a rig's
## ceiling is measured from, so no rig climbs from the lava to the Crown.
func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## How fast the air rises at `pos` (m/s): the vents' updrafts. Static, so
## the world asks it with no map built (a server and a client agree).
static func updraft_at(pos: Vector3) -> float:
	if pos.y < LAVA_Y:
		return 0.0
	for vent: Dictionary in VENTS:
		var at: Vector2 = vent["at"]
		var off := Vector2(pos.x - at.x, pos.z - at.y).length()
		if off >= VENT_RADIUS:
			continue
		var top: float = vent["top"]
		if pos.y >= top:
			continue
		var across := 1.0 - smoothstep(VENT_RADIUS * VENT_CORE, VENT_RADIUS, off)
		var up := clampf((top - pos.y) / VENT_EASE, 0.0, 1.0)
		return VENT_RISE * across * up
	return 0.0


# --- The shape of the ground -------------------------------------------------

## The rift's floor a little rough under the lava, the cliffs climbing past
## the field.
func _height(x: float, z: float) -> float:
	var h := FLOOR_Y + _noise.get_noise_2d(x, z) * 0.8
	var out := maxf(absf(x), absf(z)) - FIELD
	if out > 0.0:
		h += smoothstep(0.0, RIM, out) * (CLIFF - FLOOR_Y)
	return h


## The floor and cliffs: solid (a body falls onto them, into the lava) but
## outside the navigation region.
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
	terrain.build(_rock, collision)
	add_child(terrain)
	# Nobody leaves the rift: walls stand just past the cliffs' foot, so no
	# one lands on the cliff tops either (a rig's ceiling counts from the
	# ground under it, and up there that is the cliff).
	var edge := FIELD + EDGE
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

## The Gate Shelf: a ledge on the south cliff. Player spawns inside the gate
## outpost, a depot either side and a few blocks of cover at its lip.
func _build_shelf() -> void:
	var low := FLOOR_Y - 1.0
	_box(Vector3(SHELF_SIZE.x, SHELF_TOP - low, SHELF_SIZE.y),
			Vector3(SHELF_AT.x, (SHELF_TOP + low) * 0.5, SHELF_AT.y), _rock)
	var top := Vector3(SHELF_AT.x, SHELF_TOP, SHELF_AT.y)
	var outpost := _add_marker("outpost", top + Vector3(0, 0, -4.0))
	outpost.set_meta("name", "Rift Gate")
	outpost.set_meta("radius", 16.0)
	for i in 6:
		_add_marker("spawn_player", top + Vector3((i - 2.5) * 5.0, 0.0, 2.0 + (i % 2) * 3.0))
	for side: float in [-1.0, 1.0]:
		_add_depot(top + Vector3(side * 14.0, 0.0, -8.0))
	# Cover along the lip, gaps left for the bridges.
	for x: float in [-26.0, -12.0, 12.0, 26.0]:
		_box(Vector3(5.0, 1.3, 1.2), top + Vector3(x, 0.65, -SHELF_SIZE.y * 0.5 + 3.0), _rock)


## The strongpoints: a mesa each, with lower columns stood round it, cover
## on its top, a depot, a cache and the rift's soldiers posted on it.
func _build_sites() -> void:
	for site: Dictionary in SITES:
		var at: Vector2 = site["at"]
		var top: float = site["top"]
		var radius: float = site["radius"]
		_mesa(at, radius, top)
		var centre := Vector3(at.x, top, at.y)
		var point := _add_marker("strongpoint", centre)
		point.set_meta("name", site["name"])
		point.set_meta("radius", radius - 2.0)
		_cover(at, radius, top)
		_add_depot(centre + Vector3(radius * 0.45, 0.0, radius * 0.3))
		_add_marker("spawn_cache", centre + Vector3(-3.0, 0.1, 3.0))
		for i in 3:
			var spot := at + Vector2.from_angle(i * TAU / 3.0 + 0.5) * radius * 0.4
			_add_marker("spawn_bot", Vector3(spot.x, top, spot.y)).set_meta("faction", "rift")


## The Crown: the highest mesa, the warlord's, with the best caches.
func _build_crown() -> void:
	var at: Vector2 = CROWN["at"]
	var top: float = CROWN["top"]
	var radius: float = CROWN["radius"]
	_mesa(at, radius, top)
	_cover(at, radius, top)
	var boss := _add_marker("spawn_boss", Vector3(at.x, top, at.y))
	boss.set_meta("faction", "rift")
	boss.set_meta("radius", radius)
	for i in 3:
		var spot := at + Vector2.from_angle(i * TAU / 3.0 + 0.4) * radius * 0.55
		_add_marker("spawn_cache", Vector3(spot.x, top + 0.1, spot.y))


## Iron bridges between the Shelf and the mesas, railed both sides.
func _build_bridges() -> void:
	for pair: Array in BRIDGES:
		var a := _bridge_end(pair[0], pair[1])
		var b := _bridge_end(pair[1], pair[0])
		_bridge(a, b)


## Where a bridge from `from` towards `to` starts: a little inside the
## Shelf's lip or a mesa's edge, at its top.
func _bridge_end(from: Variant, to: Variant) -> Vector3:
	var lip := SHELF_AT.y - SHELF_SIZE.y * 0.5 + 1.5
	match from:
		"shelf":
			return Vector3(0.0, SHELF_TOP, lip)
		"shelf_w":
			return Vector3(-SHELF_SIZE.x * 0.5 + 4.0, SHELF_TOP, lip)
		"shelf_e":
			return Vector3(SHELF_SIZE.x * 0.5 - 4.0, SHELF_TOP, lip)
	var site: Dictionary = SITES[int(from)]
	var at: Vector2 = site["at"]
	var toward := _place_at(to) - at
	# A six-sided top reaches only cos(30°) of its radius on its flat sides.
	var spot := at + toward.normalized() * (float(site["radius"]) * 0.86 - 1.5)
	return Vector3(spot.x, site["top"], spot.y)


func _place_at(place: Variant) -> Vector2:
	if place is String:
		var end := _bridge_end(place, 0)
		return Vector2(end.x, end.z)
	return SITES[int(place)]["at"]


## A bridge's deck from `a` to `b` (its top meets both), with a rail each
## side; one body, so the collision checks see it as one solid.
func _bridge(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = (a + b) * 0.5
	body.basis = Basis.looking_at(b - a, Vector3.UP)
	body.add_to_group("rift_bridge")
	nav_region.add_child(body)
	_piece(body, Vector3(BRIDGE_WIDTH, 0.6, length), Vector3(0, -0.3, 0))
	for side: float in [-1.0, 1.0]:
		_piece(body, Vector3(0.25, 0.9, length), Vector3(side * (BRIDGE_WIDTH * 0.5 - 0.125), 0.45, 0))


## Perches: single columns over the lava at every height, kept clear of the
## mesas, the bridges, the vents and each other. Some hold a cache, some a
## soldier posted on them; the highest are above any rig's ceiling.
func _build_perches() -> void:
	var tries := 0
	while perches.size() < PERCHES and tries < 2000:
		tries += 1
		var at := Vector2(_rng.randf_range(-FIELD + 12.0, FIELD - 12.0),
				_rng.randf_range(-FIELD + 12.0, SHELF_AT.y - SHELF_SIZE.y * 0.5 - 12.0))
		var radius := _rng.randf_range(PERCH_RADIUS.x, PERCH_RADIUS.y)
		# Higher to the north.
		var north := clampf((MIDDLE_FROM_Z - at.y) / (MIDDLE_FROM_Z + FIELD), 0.0, 1.0)
		var top := lerpf(PERCH_TOP.x, PERCH_TOP.y, clampf(north * 0.7 + _rng.randf() * 0.5, 0.0, 1.0))
		if not _clear_for(at, radius):
			continue
		_column(at, radius, top, nav_region)
		perches.append({"at": at, "radius": radius, "top": top})
		var n := perches.size()
		if n % 3 == 0 and radius >= 3.5:
			_add_marker("spawn_cache", Vector3(at.x, top + 0.1, at.y))
		elif n % 4 == 1 and radius >= 4.0:
			_add_marker("spawn_bot", Vector3(at.x, top, at.y)).set_meta("faction", "rift")


func _clear_for(at: Vector2, radius: float) -> bool:
	for site: Dictionary in SITES + [CROWN]:
		if at.distance_to(site["at"]) < float(site["radius"]) + radius + 8.0:
			return false
	for vent: Dictionary in VENTS:
		if at.distance_to(vent["at"]) < VENT_RADIUS + radius + 6.0:
			return false
	for pair: Array in BRIDGES:
		var a := _bridge_end(pair[0], pair[1])
		var b := _bridge_end(pair[1], pair[0])
		var near := Geometry2D.get_closest_point_to_segment(at, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if at.distance_to(near) < radius + BRIDGE_WIDTH + 4.0:
			return false
	for perch: Dictionary in perches:
		if at.distance_to(perch["at"]) < float(perch["radius"]) + radius + 7.0:
			return false
	return true


# --- Building blocks ---------------------------------------------------------

## A mesa: a broad column with lower ones stood round its sides, steps a
## flyer can land on and cover for whoever holds the top.
func _mesa(at: Vector2, radius: float, top: float) -> void:
	_column(at, radius, top, nav_region)
	var flanks := 5
	for i in flanks:
		var angle := i * TAU / flanks + _rng.randf_range(-0.3, 0.3)
		var r := _rng.randf_range(3.0, 5.0)
		var spot := at + Vector2.from_angle(angle) * (radius + r * 0.4)
		_column(spot, r, top - _rng.randf_range(3.0, 12.0), nav_region)


## Blocks of basalt on a mesa's top to fight from.
func _cover(at: Vector2, radius: float, top: float) -> void:
	for i in 4:
		var angle := i * TAU / 4.0 + PI * 0.25
		var spot := at + Vector2.from_angle(angle) * radius * 0.62
		var block := _box(Vector3(3.2, 1.4, 1.2), Vector3(spot.x, top + 0.7, spot.y), _rock)
		block.rotation.y = -angle + PI * 0.5


## A six-sided basalt column standing from under the lava to `top`.
func _column(at: Vector2, radius: float, top: float, parent: Node) -> StaticBody3D:
	var low := FLOOR_Y - 1.0
	var height := top - low
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.04
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = _rock
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = Vector3(at.x, low + height * 0.5, at.y)
	body.rotation.y = _rng.randf() * TAU
	body.add_to_group("rift_column")
	var col := CollisionShape3D.new()
	col.shape = mesh.create_convex_shape(true, false)
	body.add_child(col)
	var view := MeshInstance3D.new()
	view.mesh = mesh
	body.add_child(view)
	parent.add_child(body)
	return body


## One box of a bigger body (a bridge's deck or rail).
func _piece(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = at
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = METAL
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position = at
	body.add_child(view)


# --- Decoration --------------------------------------------------------------

## View only: the lava sheet and its glow, the vents' heat columns and
## embers, and the planet's land past the cliffs to the horizon. Its own
## seed, so it never moves the layout. Named "Dressing", as every map's is.
func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	_dress_lava(art)
	for vent: Dictionary in VENTS:
		_dress_vent(art, vent)
	var land := PlanetTerrain.new(planet.terrain, LAYOUT_SEED)
	var half := terrain.extent() * 0.5
	art.add_child(Planet.horizon(planet, land, half))
	var height_of := func(x: float, z: float) -> float:
		return terrain.height_at(x, z) if maxf(absf(x), absf(z)) < half else land.height_at(x, z)
	var clear := func(x: float, z: float) -> bool:
		return maxf(absf(x), absf(z)) > FIELD + 20.0
	PlanetProps.scatter(art, planet, height_of, half, LAYOUT_SEED + 3, clear)


## One sheet of lava over the whole floor (`Look`'s "lava": crust and
## drifting seams), and a few broad lights from below.
func _dress_lava(art: Node3D) -> void:
	var sheet := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (FIELD + RIM) * 2.0
	plane.material = Look.trim("lava")
	sheet.mesh = plane
	sheet.position = Vector3(0.0, LAVA_Y, 0.0)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.name = "Lava"
	art.add_child(sheet)
	for i in 8:
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.4, 0.14)
		glow.light_energy = 1.4
		glow.omni_range = 60.0
		glow.shadow_enabled = false
		var at := Vector2(_art_rng.randf_range(-FIELD, FIELD), _art_rng.randf_range(-FIELD, FIELD * 0.6))
		glow.position = Vector3(at.x, LAVA_Y + 12.0, at.y)
		art.add_child(glow)


## A vent: a brighter boil in the lava, a column of heat haze up to its top
## and embers riding it, so an updraft reads from across the rift.
func _dress_vent(art: Node3D, vent: Dictionary) -> void:
	var at: Vector2 = vent["at"]
	var top: float = vent["top"]
	var boil := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = VENT_RADIUS * 0.7
	disc.bottom_radius = VENT_RADIUS * 0.7
	disc.height = 0.1
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(0.4, 0.12, 0.03)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.55, 0.15)
	hot.emission_energy_multiplier = 5.0
	disc.material = hot
	boil.mesh = disc
	boil.position = Vector3(at.x, LAVA_Y + 0.06, at.y)
	boil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(boil)
	var haze := ShaderMaterial.new()
	haze.shader = Look.HAZE_BEAM_SHADER
	haze.set_shader_parameter("tint", Color(1.0, 0.45, 0.15))
	haze.set_shader_parameter("strength", 0.22)
	haze.set_shader_parameter("top_fade", 0.9)
	haze.set_shader_parameter("foot", 1.0)
	haze.set_shader_parameter("near_fade", 50.0)
	var column := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = VENT_RADIUS * 0.9
	tube.bottom_radius = VENT_RADIUS * 0.7
	tube.height = top - LAVA_Y
	tube.cap_top = false
	tube.cap_bottom = false
	tube.material = haze
	column.mesh = tube
	column.position = Vector3(at.x, LAVA_Y + tube.height * 0.5, at.y)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Air: nothing to bump into.
	column.set_meta("walk_through", true)
	art.add_child(column)
	var embers := GPUParticles3D.new()
	embers.amount = 160
	embers.lifetime = (top - LAVA_Y) / VENT_RISE
	embers.preprocess = embers.lifetime
	embers.visibility_aabb = AABB(Vector3(-VENT_RADIUS, 0.0, -VENT_RADIUS), Vector3(VENT_RADIUS * 2.0, top + 4.0,
			VENT_RADIUS * 2.0))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = VENT_RADIUS * 0.6
	motion.direction = Vector3.UP
	motion.spread = 6.0
	motion.initial_velocity_min = VENT_RISE * 0.8
	motion.initial_velocity_max = VENT_RISE * 1.1
	motion.gravity = Vector3.ZERO
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.6
	embers.process_material = motion
	var spark := QuadMesh.new()
	spark.size = Vector2(0.35, 0.35)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_color = Color(1.0, 0.6, 0.2)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.5, 0.15)
	glow.emission_energy_multiplier = 4.0
	spark.material = glow
	embers.draw_pass_1 = spark
	embers.position = Vector3(at.x, LAVA_Y + 0.5, at.y)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	art.add_child(embers)


# --- Helpers -----------------------------------------------------------------

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
	return body
