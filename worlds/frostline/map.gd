extends Node3D
## Greybox Frostline: a round glacier shelf around a central relay mast.
##
## Layout is radial rather than a grid: a mast in the middle, a ring of six
## outposts, broken ice ridges for cover, and exits on the outer rim. Positions
## are fixed with a seeded jitter, so the map is the same every raid while loot
## and spawns vary. Only the map contract in WorldDef matters to the rest of
## the game.

const RADIUS := 58.0
const OUTPOST_RING := 32.0
const RIDGE_RINGS := [18.0, 44.0]
const RIM := 50.0
const LAYOUT_SEED := 4242

var _art_rng := RandomNumberGenerator.new()
var _huts: Array[Dictionary] = []

@onready var ICE := Look.surface("ground", {"tint": Color(0.3, 0.42, 0.55), "snow": 1.0, "snow_patchy": 1.0,
		"grime": 0.0, "scale": 0.12, "rough_mult": 0.35, "saturation": 0.3})
@onready var CLIFF := Look.surface("concrete", {"tint": Color(0.55, 0.66, 0.78), "snow": 0.9, "grime": 0.0,
		"scale": 0.08, "rough_mult": 0.5})
@onready var ROCK := Look.surface("ground", {"tint": Color(0.4, 0.44, 0.5), "snow": 1.0, "grime": 0.3, "scale": 0.3})
@onready var STEEL := Look.surface("metal", {"tint": Color(0.5, 0.54, 0.6), "snow": 1.0, "grime": 0.5, "scale": 0.3,
		"window_glow": Color(0.5, 0.8, 1.0), "lit_windows": 0.12})
@onready var STEEL_DARK := Look.surface("metal", {"tint": Color(0.36, 0.39, 0.44), "snow": 1.0, "grime": 0.6,
		"scale": 0.3, "window_glow": Color(0.5, 0.8, 1.0), "lit_windows": 0.12})

var nav_region: NavigationRegion3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = LAYOUT_SEED
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_relay()
	_build_outposts()
	_build_ridges()
	_build_rim()
	_art_rng.seed = LAYOUT_SEED
	_dress()


func bake_navigation() -> void:
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = Actor.LAYER_WORLD
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.5
	nav_region.navigation_mesh = navmesh
	nav_region.bake_navigation_mesh(false)


func _build_environment() -> void:
	# Whiteout: a flat grey sky, a weak low sun, and snow blowing sideways.
	Look.atmosphere(self, {
		"sky_tint": Color(0.82, 0.88, 0.96),
		"sky_saturation": 0.25,
		"sky_energy": 0.8,
		"fog_color": Color(0.58, 0.63, 0.7),
		"fog_density": 0.013,
		"haze_height": 0.5,
		"sun_color": Color(0.92, 0.95, 1.0),
		"sun_energy": 1.6,
		"sun_angles": Vector3(-20, -60, 0),
		"ambient_color": Color(0.72, 0.78, 0.86),
		"ambient_energy": 1.2,
		"saturation": 0.8,
		"contrast": 1.05,
	})
	Look.weather(self, "snow", RADIUS)


func _build_ground() -> void:
	var span := RADIUS * 2.0 + 8.0
	_box(Vector3(span, 1.0, span), Vector3(0, -0.5, 0), ICE, 0.0)
	# Ice cliffs on all sides. Flying over them drops you into the void.
	var edge := RADIUS + 3.5
	var cliff := CLIFF
	_box(Vector3(span, 16.0, 1.0), Vector3(0, 8, -edge), cliff, 0.0)
	_box(Vector3(span, 16.0, 1.0), Vector3(0, 8, edge), cliff, 0.0)
	_box(Vector3(1.0, 16.0, span), Vector3(-edge, 8, 0), cliff, 0.0)
	_box(Vector3(1.0, 16.0, span), Vector3(edge, 8, 0), cliff, 0.0)


## The relay: a squat base you can walk around, and a mast only flight reaches.
func _build_relay() -> void:
	_box(Vector3(10, 4, 10), Vector3(0, 2, 0), STEEL, PI / 4.0)
	_box(Vector3(3, 18, 3), Vector3(0, 13, 0), STEEL, PI / 4.0)
	_box(Vector3(6, 0.5, 6), Vector3(0, 22.25, 0), STEEL, PI / 4.0)
	_add_marker("spawn_cache", Vector3(0, 22.5, 0)).set_meta("loot_source", "relay")
	_add_marker("spawn_cache", Vector3(3.2, 4, 0)).set_meta("loot_source", "rooftop")
	for i in 4:
		var angle := TAU * i / 4.0
		_add_marker("spawn_bot", _polar(10.0, angle))
	for i in 2:
		_add_marker("spawn_cache", _polar(7.5, TAU * i / 2.0 + PI / 4.0))


## Six huts around the mast. Each faces the centre, with a cache at its door.
func _build_outposts() -> void:
	for i in 6:
		var angle := TAU * i / 6.0 + _rng.randf_range(-0.12, 0.12)
		var center := _polar(OUTPOST_RING, angle)
		var height: float = [4.0, 6.0, 9.0][i % 3]
		var hut := _box(Vector3(8, height, 6), center + Vector3(0, height * 0.5, 0), STEEL_DARK, -angle)
		Look.make_building(hut.get_child(1), Vector3(8, height, 6), float(i) * 7.0)
		_huts.append({"center": center, "height": height, "yaw": -angle})
		_add_marker("spawn_cache", _polar(OUTPOST_RING - 5.5, angle))
		_add_marker("spawn_bot", _polar(OUTPOST_RING + 6.0, angle + 0.15))
		if height >= 6.0:
			_add_marker("spawn_cache", center + Vector3(0, height, 0)).set_meta("loot_source", "rooftop")


## Broken ice ridges, chest high, laid along two rings so sightlines stay long
## but there is always somewhere to duck.
func _build_ridges() -> void:
	for ring: float in RIDGE_RINGS:
		var count := 8 if ring < 30.0 else 12
		for i in count:
			var angle := TAU * (i + 0.5) / count + _rng.randf_range(-0.1, 0.1)
			var length := _rng.randf_range(5.0, 9.0)
			var height := _rng.randf_range(1.2, 2.2)
			var at := _polar(ring + _rng.randf_range(-2.0, 2.0), angle) + Vector3(0, height * 0.5, 0)
			# Tangent to the ring: the long side faces the centre.
			_box(Vector3(length, height, 1.6), at, ROCK, -angle + PI / 2.0)


## Exits on opposite sides of the rim, player spawns between them.
func _build_rim() -> void:
	for angle: float in [PI / 6.0, PI / 6.0 + PI]:
		var zone := ExtractionZone.new()
		zone.add_to_group("exit")
		zone.position = _polar(RIM, angle) + Vector3(0, 2.0, 0)
		add_child(zone)
	for i in 4:
		var angle := PI / 6.0 + PI / 4.0 + i * PI / 2.0
		_add_marker("spawn_player", _polar(RIM + 2.0, angle))



## Decoration only: no collision, nothing the game depends on.
func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	# The mast: a dish array, a red beacon, and floodlights on the base.
	for i in 3:
		var dish := Look.prop("Antenna_2.glb", 2.6, 0.5)
		dish.position = Vector3(0, 22.5, 0) + _polar(2.0, TAU * i / 3.0)
		dish.rotation.y = -TAU * i / 3.0
		art.add_child(dish)
	var whip := Look.prop("Antenna_1.glb", 7.0, 0.5)
	whip.position = Vector3(0, 22.5, 0)
	art.add_child(whip)
	var beacon := Look.lamp(Color(1.0, 0.15, 0.1), 6.0, 30.0)
	beacon.position = Vector3(0, 29.0, 0)
	art.add_child(beacon)
	for i in 4:
		var flood := Look.lamp(Color(0.7, 0.85, 1.0), 3.0, 16.0)
		flood.position = _polar(8.5, TAU * i / 4.0 + PI / 4.0) + Vector3(0, 4.5, 0)
		art.add_child(flood)
	# Outposts: gear on the roof, a lamp over the door, junk by the wall.
	for hut in _huts:
		var center: Vector3 = hut["center"]
		var top := center + Vector3(0, hut["height"], 0)
		var facing := Basis(Vector3.UP, hut["yaw"])
		for file: String in ["AC.glb", "Antenna_1.glb"]:
			var p := Look.prop(file, 3.5 if file == "Antenna_1.glb" else 1.6, 0.5)
			p.position = top + facing * Vector3(_art_rng.randf_range(-3, 3), 0, _art_rng.randf_range(-2, 2))
			art.add_child(p)
		var inward := -center.normalized()
		var door := Look.lamp(Color(1.0, 0.75, 0.45), 3.0, 10.0)
		door.position = center + inward * 3.6 + Vector3(0, 2.6, 0)
		art.add_child(door)
		var junk := Look.prop(["PropaneTank.glb", "Computer_Large.glb", "GasCan.glb"][_art_rng.randi() % 3], 1.2, 0.6)
		junk.position = center + inward * 3.5 + inward.cross(Vector3.UP) * 2.6
		junk.rotation.y = _art_rng.randf() * TAU
		art.add_child(junk)
	# Ice peaks beyond the cliffs, lost in the whiteout.
	for i in 30:
		var angle := TAU * i / 30.0 + _art_rng.randf_range(-0.08, 0.08)
		var size := Vector3(_art_rng.randf_range(20, 44), _art_rng.randf_range(22, 60), _art_rng.randf_range(20, 44))
		var peak := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = size
		mesh.left_to_right = _art_rng.randf_range(0.25, 0.75)
		mesh.material = CLIFF
		peak.mesh = mesh
		var dir := Vector3(cos(angle), 0, sin(angle))
		var dist := RADIUS + _art_rng.randf_range(24.0, 70.0)
		peak.position = dir * dist / maxf(absf(dir.x), absf(dir.z)) + Vector3(0, size.y * 0.5 - 2.0, 0)
		peak.rotation.y = _art_rng.randf() * TAU
		art.add_child(peak)


func _polar(radius: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


func _add_marker(group: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.add_to_group(group)
	marker.position = at
	add_child(marker)
	return marker


func _box(size: Vector3, at: Vector3, material: Material, yaw: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	body.rotation.y = yaw
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
