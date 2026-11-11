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
const ICE := Color(0.6, 0.68, 0.75)
const ROCK := Color(0.3, 0.33, 0.38)
const STEEL := Color(0.42, 0.44, 0.48)

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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.74, 0.8, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.78, 0.88)
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.87, 0.92)
	env.fog_density = 0.018
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22, -60, 0)
	sun.light_color = Color(0.9, 0.95, 1.0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var span := RADIUS * 2.0 + 8.0
	_box(Vector3(span, 1.0, span), Vector3(0, -0.5, 0), ICE, 0.0)
	# Ice cliffs on all sides. Flying over them drops you into the void.
	var edge := RADIUS + 3.5
	var cliff := Color(0.5, 0.57, 0.65)
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
		_box(Vector3(8, height, 6), center + Vector3(0, height * 0.5, 0), STEEL.darkened(0.15), -angle)
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


func _polar(radius: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


func _add_marker(group: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.add_to_group(group)
	marker.position = at
	add_child(marker)
	return marker


func _box(size: Vector3, at: Vector3, color: Color, yaw: float) -> StaticBody3D:
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	nav_region.add_child(body)
	return body
