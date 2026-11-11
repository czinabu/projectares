extends Node3D
## Greybox Ashfront: a grid of city blocks built from boxes.
##
## The layout uses a fixed seed, so the map is the same every raid while loot
## and spawns vary. This will be replaced by a hand-built scene later; the only
## thing the rest of the game relies on is the map contract in WorldDef.

const CELL := 14.0
const GRID := 8
const LAYOUT_SEED := 1337
const HEIGHTS := [3.0, 3.0, 6.0, 10.0, 16.0]

var nav_region: NavigationRegion3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = LAYOUT_SEED
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_blocks()


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
	env.background_color = Color(0.32, 0.1, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.55, 0.5)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.16, 0.1)
	env.fog_density = 0.008
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color(1.0, 0.8, 0.65)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var half := CELL * GRID * 0.5
	var span := half * 2.0 + 8.0
	_box(Vector3(span, 1.0, span), Vector3(0, -0.5, 0), Color(0.23, 0.2, 0.19))
	# Perimeter walls. Flying over them drops you into the void.
	var wall_color := Color(0.14, 0.12, 0.12)
	var edge := half + 3.5
	_box(Vector3(span, 14.0, 1.0), Vector3(0, 7, -edge), wall_color)
	_box(Vector3(span, 14.0, 1.0), Vector3(0, 7, edge), wall_color)
	_box(Vector3(1.0, 14.0, span), Vector3(-edge, 7, 0), wall_color)
	_box(Vector3(1.0, 14.0, span), Vector3(edge, 7, 0), wall_color)


func _build_blocks() -> void:
	var half := CELL * GRID * 0.5
	var open_cells: Array[Vector3] = []
	for gx in GRID:
		for gz in GRID:
			var center := Vector3(-half + CELL * (gx + 0.5), 0, -half + CELL * (gz + 0.5))
			var is_exit := (gx == 0 and gz == 0) or (gx == GRID - 1 and gz == GRID - 1)
			if is_exit:
				_add_exit(center)
			elif _rng.randf() < 0.5:
				_add_building(center)
			else:
				open_cells.append(center)

	# Deal the open cells out: player spawns, bot spawns, caches, then cover.
	_shuffle(open_cells)
	var index := 0
	for center in open_cells:
		var slot := index % 6
		if index < 4:
			_add_marker("spawn_player", center)
		elif slot <= 2:
			_add_marker("spawn_bot", center)
		elif slot <= 4:
			_add_marker("spawn_cache", center + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)))
			_add_cover(center)
		else:
			_add_cover(center)
		index += 1


func _add_building(center: Vector3) -> void:
	var w := _rng.randf_range(5.0, 9.0)
	var d := _rng.randf_range(5.0, 9.0)
	var h: float = HEIGHTS[_rng.randi() % HEIGHTS.size()]
	var shade := _rng.randf_range(0.26, 0.4)
	_box(Vector3(w, h, d), center + Vector3(0, h * 0.5, 0), Color(shade, shade * 0.92, shade * 0.88))
	if h >= 6.0 and _rng.randf() < 0.65:
		var marker := _add_marker("spawn_cache", center + Vector3(0, h, 0))
		marker.set_meta("loot_source", "rooftop")


func _add_cover(center: Vector3) -> void:
	for i in _rng.randi_range(1, 3):
		var size := Vector3(_rng.randf_range(1.2, 3.0), _rng.randf_range(1.0, 1.6), _rng.randf_range(1.2, 3.0))
		var offset := Vector3(_rng.randf_range(-4.5, 4.5), size.y * 0.5, _rng.randf_range(-4.5, 4.5))
		_box(size, center + offset, Color(0.42, 0.3, 0.2))


func _add_exit(center: Vector3) -> void:
	var zone := ExtractionZone.new()
	zone.add_to_group("exit")
	zone.position = center + Vector3(0, 2.0, 0)
	add_child(zone)


func _add_marker(group: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.add_to_group(group)
	marker.position = at
	add_child(marker)
	return marker


func _box(size: Vector3, at: Vector3, color: Color) -> StaticBody3D:
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	nav_region.add_child(body)
	return body


func _shuffle(list: Array[Vector3]) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := list[i]
		list[i] = list[j]
		list[j] = tmp
