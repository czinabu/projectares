extends Node3D
## Greybox Ashfront: one open battlefield, about 600 metres across.
##
## Rolling scorched ground, cratered by shelling and cut by trench lines, with
## five landmarks spread over it: a ruined foundry in the middle and four
## sites around it. Each landmark is a strongpoint with a depot, loot and a
## garrison. Between them lie the wrecks of war machines, which are the cover.
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
## Jump ramps need level ground, so each gets a pad by the old front.
const RAMP_SPOTS := [Vector2(-52, -40), Vector2(58, -44), Vector2(-56, 44), Vector2(52, 40)]

## The landmarks: name, where, how wide, and how far the site is lifted above
## the ground around it.
const SITES := [
	{"name": "The Foundry", "at": Vector2(0, 0), "radius": 40.0, "lift": 0.0, "kind": "foundry"},
	{"name": "Signal Hill", "at": Vector2(-150, -118), "radius": 28.0, "lift": 11.0, "kind": "hill"},
	{"name": "Rustfall", "at": Vector2(158, -106), "radius": 32.0, "lift": 0.0, "kind": "graveyard"},
	{"name": "The Breach", "at": Vector2(-142, 136), "radius": 32.0, "lift": 0.0, "kind": "breach"},
	{"name": "Carrier Grave", "at": Vector2(134, 132), "radius": 34.0, "lift": 0.0, "kind": "carrier"},
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
## Everything solid standing on the ground: { at: Vector2, reach }.
var _solids: Array[Dictionary] = []
var _weather: Node3D

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


func _build_environment() -> void:
	# A scorched plain under smoke: low orange sun, haze to the horizon, embers.
	Look.atmosphere(self, {
		"sky_tint": Color(0.82, 0.6, 0.48),
		"sky_saturation": 0.3,
		"sky_energy": 0.75,
		"sky_rotation": 0.2,
		"fog_color": Color(0.36, 0.27, 0.22),
		"fog_density": 0.0085,
		"sun_scatter": 0.35,
		"sun_color": Color(1.0, 0.74, 0.52),
		"sun_energy": 1.9,
		"sun_angles": Vector3(-30, 38, 0),
		"ambient_color": Color(0.42, 0.43, 0.5),
		"ambient_energy": 1.3,
		"saturation": 0.85,
		"contrast": 1.12,
	}, {
		# The same plain in the middle of a battle: the smoke closes in, the sun
		# goes to a dull red and the light drains away. It stops well short of
		# black, so a fight stays readable.
		"sky_tint": Color(0.55, 0.3, 0.24),
		"sky_saturation": 0.4,
		"sky_energy": 0.42,
		"fog_color": Color(0.2, 0.13, 0.11),
		"fog_density": 0.0135,
		"sun_color": Color(1.0, 0.6, 0.45),
		"sun_energy": 1.05,
		"ambient_color": Color(0.42, 0.36, 0.38),
		"ambient_energy": 1.15,
		"saturation": 0.72,
		"contrast": 1.16,
		"glow": 0.95,
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
		# A garrison, and a bike for whoever takes the place.
		for i in 4:
			_add_marker("spawn_bot", _open(at + Vector2.from_angle(TAU * i / 4.0 + 0.6) * radius * 0.45))
		var bike := _add_marker("spawn_vehicle", _open(at - inward.orthogonal() * (radius - 6.0), 2.0))
		bike.rotation.y = atan2(-inward.x, -inward.y)


## The middle of the map: the shells of a works, tall enough that the best
## loot sits on roofs only a flight rig reaches.
func _build_foundry(at: Vector2) -> void:
	var lots := [Vector2(-16, -12), Vector2(14, -16), Vector2(-18, 14), Vector2(16, 12), Vector2(0, 26)]
	for i in lots.size():
		var h: float = [16.0, 10.0, 10.0, 6.0, 6.0][i]
		_add_building(at + lots[i], Vector3(_rng.randf_range(8.0, 11.0), h, _rng.randf_range(8.0, 11.0)), true)
	# The stack: a landmark you can steer by from anywhere.
	_add_building(at + Vector2(2, -2), Vector3(3.5, 34.0, 3.5), false)
	for offset: Vector2 in [Vector2(-4, 4), Vector2(18, -30), Vector2(28, -2), Vector2(-30, 0)]:
		_add_cover(_ground(at + offset))
		_add_marker("spawn_cache", _open(at + offset + Vector2(2.5, 1.5)))


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
	for i in PLAYER_SPAWNS:
		var dir := Vector2.from_angle(TAU * (i + 0.5) / PLAYER_SPAWNS)
		var at := dir * SPAWN_RING
		_add_marker("spawn_player", _ground(at))
		# A low wall to drop in behind, and at every other spawn a bike.
		_add_wall(_ground(at - dir * 6.0), Vector3(6.0, 1.4, 1.0), -dir.angle() + PI * 0.5)
		if i % 2 == 0:
			var bike := _add_marker("spawn_vehicle", _ground(at + dir.orthogonal() * 7.0))
			bike.rotation.y = atan2(dir.x, dir.y)


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
	for i in FIELD_PATROLS:
		_add_marker("spawn_bot", _open(_free_spot(5.0)))
	for i in RAMP_SPOTS.size():
		_add_ramp_lot(_ground(RAMP_SPOTS[i]), i * PI * 0.5)


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


func _add_cover(center: Vector3) -> void:
	for i in _rng.randi_range(2, 4):
		var size := Vector3(_rng.randf_range(1.2, 3.0), _rng.randf_range(1.0, 1.6), _rng.randf_range(1.2, 3.0))
		var offset := Vector2(_rng.randf_range(-4.5, 4.5), _rng.randf_range(-4.5, 4.5))
		var base := terrain.on_ground(center.x + offset.x, center.z + offset.y)
		_box(size + Vector3(0, 0.8, 0), base + Vector3(0, size.y * 0.5 - 0.4, 0), COVER_METAL if i % 2 == 0 else COVER_CONCRETE)
		_cover_spots.append(terrain.on_ground(base.x + size.x * 0.5 + 0.5, base.z))


## The wreck of a war machine: a crawler hull, a fallen strider, or a downed
## lifter. Plain boxes that stop bullets; `Look` and the dressing do the rest.
func _add_wreck(at: Vector2, kind: int, yaw: float, big: float) -> void:
	var base := _ground(at)
	var turn := Basis(Vector3.UP, yaw)
	var size := Vector3.ZERO
	match kind:
		0:
			# Crawler: a long low hull with a turret knocked askew.
			size = Vector3(4.4, 2.4, 8.0) * big
			var hull := _box(size, base + Vector3(0, size.y * 0.5 - 0.5, 0), HULL)
			hull.rotation = Vector3(_rng.randf_range(-0.08, 0.08), yaw, _rng.randf_range(-0.1, 0.1))
			var turret := _box(Vector3(2.8, 1.3, 3.2) * big, base + turn * Vector3(0.3, size.y + 0.1, -0.6), HULL_RUST)
			turret.rotation = Vector3(0.0, yaw + 0.7, 0.12)
			var barrel := _box(Vector3(0.5, 0.5, 5.5) * big, base + turn * Vector3(1.8, size.y + 0.2, -3.6), HULL)
			barrel.rotation = Vector3(-0.12, yaw + 0.7, 0.0)
		1:
			# Strider: the body on its side, one leg still reaching up.
			size = Vector3(5.0, 3.6, 6.0) * big
			var body := _box(size, base + Vector3(0, size.y * 0.5 - 0.8, 0), HULL_RUST)
			body.rotation = Vector3(0.0, yaw, 0.38)
			var leg := _box(Vector3(1.1, 11.0, 1.1) * big, base + turn * Vector3(-3.2, 4.0 * big, 1.0), HULL)
			leg.rotation = Vector3(0.3, yaw, -0.42)
			var fallen := _box(Vector3(1.1, 1.1, 10.0) * big, base + turn * Vector3(4.4, 0.3, -2.0), HULL)
			fallen.rotation = Vector3(0.06, yaw + 0.5, 0.0)
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
			# Lifter: a broken-backed fuselage with one wing slab left.
			size = Vector3(3.6, 3.2, 12.0) * big
			var front := _box(Vector3(size.x, size.y, size.z * 0.5), base + turn * Vector3(0, size.y * 0.5 - 0.6, -size.z * 0.27), HULL)
			front.rotation = Vector3(0.14, yaw, 0.06)
			var back := _box(Vector3(size.x, size.y, size.z * 0.5), base + turn * Vector3(0.6, size.y * 0.5 - 0.3, size.z * 0.27), HULL_RUST)
			back.rotation = Vector3(-0.2, yaw + 0.16, -0.1)
			var wing := _box(Vector3(9.0, 0.5, 3.4) * big, base + turn * Vector3(5.4 * big, 1.5, 0.5), HULL)
			wing.rotation = Vector3(0.0, yaw, -0.26)
	_wrecks.append({"at": base, "size": size, "burning": _rng.randf() < 0.4})
	_cover_spots.append(_ground(at + Vector2.from_angle(yaw) * (size.x * 0.5 + 2.0)))


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
	_dress_horizon(art)


func _dress_rooftops(art: Node3D) -> void:
	for b in _buildings:
		if b.get("wreck", false):
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


## Litter of a long war: gun turrets, burnt-out tanks, tents, fences.
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
	var big := [["Wreck_Tank.glb", 7.0], ["Turret_Cannon.glb", 3.4], ["Turret_Gun.glb", 2.6], ["Tent.glb", 4.5],
			["Fence.glb", 4.0], ["Support_Long.glb", 5.0]]
	for i in 70:
		var at := Vector2(_art_rng.randf_range(-FIELD, FIELD), _art_rng.randf_range(-FIELD, FIELD))
		if _blocked(at):
			continue
		var pick: Array = big[_art_rng.randi() % big.size()]
		var p := Look.prop(pick[0], pick[1], 1.0)
		p.position = _ground(at) + Vector3(0, -0.15, 0)
		p.rotation = Vector3(_art_rng.randf_range(-0.12, 0.12), _art_rng.randf() * TAU, _art_rng.randf_range(-0.12, 0.12))
		art.add_child(p)


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
	for b in _buildings:
		var size: Vector3 = b["size"]
		var c: Vector3 = b["center"]
		if absf(at.x - c.x) < size.x * 0.5 + 1.0 and absf(at.y - c.z) < size.z * 0.5 + 1.0:
			return true
	for w in _wrecks:
		var c: Vector3 = w["at"]
		if at.distance_to(Vector2(c.x, c.z)) < 10.0:
			return true
	return false


## Dead giants on the rim, fading into the smoke: the hulks of machines far
## bigger than anything left on the field, and the spires they were fighting over.
func _dress_horizon(art: Node3D) -> void:
	var half := (SIDE - 1) * CELL * 0.5
	var hulk := Look.surface("metal", {"tint": Color(0.3, 0.27, 0.26), "grime": 1.0, "scale": 0.08})
	for i in 40:
		var angle := TAU * i / 40.0 + _art_rng.randf_range(-0.06, 0.06)
		var dir := Vector3(cos(angle), 0, sin(angle))
		var reach := (half + _art_rng.randf_range(10.0, 120.0)) / maxf(absf(dir.x), absf(dir.z))
		var spire := i % 4 == 0
		var size := Vector3(_art_rng.randf_range(10, 22), _art_rng.randf_range(70, 150), _art_rng.randf_range(10, 22)) if spire \
				else Vector3(_art_rng.randf_range(30, 70), _art_rng.randf_range(16, 34), _art_rng.randf_range(18, 30))
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = hulk
		node.mesh = mesh
		node.position = dir * reach + Vector3(0, RIM_HEIGHT + size.y * 0.5 - 8.0, 0)
		node.rotation = Vector3(_art_rng.randf_range(-0.05, 0.05), _art_rng.randf() * TAU,
				_art_rng.randf_range(-0.4, 0.4))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		art.add_child(node)
