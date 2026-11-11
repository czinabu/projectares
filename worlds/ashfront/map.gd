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
## Open lots that get a jump ramp and a parked bike instead of cover.
const RAMP_LOTS := 3
const RAMP_LENGTH := 8.0
const RAMP_ANGLE_DEG := 15.0

var nav_region: NavigationRegion3D
var _rng := RandomNumberGenerator.new()
## Dressing has its own generator so art never shifts the gameplay layout.
var _art_rng := RandomNumberGenerator.new()
var _buildings: Array[Dictionary] = []
var _cover_spots: Array[Vector3] = []
var _open_lots: Array[Vector3] = []

@onready var GROUND := Look.surface("asphalt", {"tint": Color(0.62, 0.56, 0.52), "blend": "ground",
		"blend_amount": 0.5, "wetness": 0.6, "grime": 0.0, "saturation": 0.35})
@onready var WALL := Look.surface("concrete", {"tint": Color(0.45, 0.4, 0.38), "grime": 0.8, "scale": 0.12})
@onready var COVER_METAL := Look.surface("metal", {"tint": Color(0.7, 0.42, 0.28), "scale": 0.45})
@onready var COVER_CONCRETE := Look.surface("concrete", {"tint": Color(0.8, 0.74, 0.68), "grime": 0.9, "scale": 0.5})


func _ready() -> void:
	_rng.seed = LAYOUT_SEED
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Geometry"
	add_child(nav_region)
	_build_ground()
	_build_blocks()
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
	# A burnt city under smoke: low orange sun, heavy haze, embers in the air.
	Look.atmosphere(self, {
		"sky_tint": Color(0.82, 0.6, 0.48),
		"sky_saturation": 0.3,
		"sky_energy": 0.75,
		"sky_rotation": 0.2,
		"fog_color": Color(0.33, 0.24, 0.19),
		"fog_density": 0.011,
		"sun_scatter": 0.35,
		"sun_color": Color(1.0, 0.74, 0.52),
		"sun_energy": 1.9,
		"sun_angles": Vector3(-36, 38, 0),
		"ambient_color": Color(0.42, 0.43, 0.5),
		"ambient_energy": 1.3,
		"saturation": 0.85,
		"contrast": 1.12,
	})
	Look.weather(self, "embers", CELL * GRID * 0.5)


func _build_ground() -> void:
	var half := CELL * GRID * 0.5
	var span := half * 2.0 + 8.0
	_box(Vector3(span, 1.0, span), Vector3(0, -0.5, 0), GROUND)
	# Perimeter walls. Flying over them drops you into the void.
	var wall_color := WALL
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
	# A few cover lots become ramp lots with a bike parked by the ramp.
	_shuffle(open_cells)
	var index := 0
	var ramps := 0
	for center in open_cells:
		var slot := index % 6
		if index < 4:
			_add_marker("spawn_player", center)
			_open_lots.append(center)
		elif slot <= 2:
			_add_marker("spawn_bot", center)
		elif slot <= 4:
			_add_marker("spawn_cache", center + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)))
			_add_cover(center)
		elif ramps < RAMP_LOTS:
			_add_ramp_lot(center, ramps * PI * 0.5)
			ramps += 1
		else:
			_add_cover(center)
		index += 1


func _add_building(center: Vector3) -> void:
	var w := _rng.randf_range(5.0, 9.0)
	var d := _rng.randf_range(5.0, 9.0)
	var h: float = HEIGHTS[_rng.randi() % HEIGHTS.size()]
	var shade := _rng.randf_range(0.26, 0.4)
	var size := Vector3(w, h, d)
	var tint := Color(shade, shade * 0.92, shade * 0.88) * 2.4
	var kind := "brick" if h <= 6.0 and shade > 0.33 else "concrete"
	var body := _box(size, center + Vector3(0, h * 0.5, 0), Look.surface(kind, {"tint": tint, "grime": 0.7}))
	Look.make_building(body.get_child(1), size, shade * 100.0)
	_buildings.append({"center": center, "size": size})
	if h >= 6.0 and _rng.randf() < 0.65:
		var marker := _add_marker("spawn_cache", center + Vector3(0, h, 0))
		marker.set_meta("loot_source", "rooftop")


func _add_cover(center: Vector3) -> void:
	for i in _rng.randi_range(1, 3):
		var size := Vector3(_rng.randf_range(1.2, 3.0), _rng.randf_range(1.0, 1.6), _rng.randf_range(1.2, 3.0))
		var offset := Vector3(_rng.randf_range(-4.5, 4.5), size.y * 0.5, _rng.randf_range(-4.5, 4.5))
		_box(size, center + offset, COVER_METAL if i % 2 == 0 else COVER_CONCRETE)
		_cover_spots.append(center + Vector3(offset.x, 0, offset.z) + Vector3(size.x * 0.5 + 0.5, 0, 0))


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
	var marker := _add_marker("spawn_vehicle", center + Basis(Vector3.UP, yaw) * Vector3(3.5, 0, 5.0))
	marker.rotation.y = yaw


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



## Everything below is decoration: no collision, nothing the game depends on.
func _dress() -> void:
	if not Look.enabled:
		return
	var art := Node3D.new()
	art.name = "Dressing"
	add_child(art)
	_dress_rooftops(art)
	_dress_streets(art)
	_dress_skyline(art)


func _dress_rooftops(art: Node3D) -> void:
	for b in _buildings:
		var size: Vector3 = b["size"]
		var top: Vector3 = b["center"] + Vector3(0, size.y, 0)
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


func _dress_streets(art: Node3D) -> void:
	var litter := ["GasCan.glb", "PropaneTank.glb", "Trashcan.glb", "Backpack.glb", "Computer.glb", "TV_1.glb"]
	for spot in _cover_spots:
		if _art_rng.randf() < 0.5:
			continue
		var file: String = litter[_art_rng.randi() % litter.size()]
		var p := Look.prop(file, _art_rng.randf_range(0.5, 0.9), 0.9)
		p.position = spot
		p.rotation.y = _art_rng.randf() * TAU
		art.add_child(p)
	# Barrel fires in a few lots: warm pools of light in the haze.
	var fires := 0
	for spot in _cover_spots:
		if fires >= 6 or _art_rng.randf() < 0.8:
			continue
		fires += 1
		var fire := Look.prop("Bonfire.glb", 1.1, 0.3)
		fire.position = spot + Vector3(0, 0, 1.2)
		art.add_child(fire)
		var glow := Look.lamp(Color(1.0, 0.5, 0.18), 5.0, 11.0)
		glow.position.y = 0.7
		fire.add_child(glow)
	# Dead street lamps along the grid lines, a few still working.
	var half := CELL * GRID * 0.5
	var lit := 0
	for gx in range(1, GRID, 2):
		for gz in range(1, GRID, 2):
			var at := Vector3(-half + CELL * gx, 0, -half + CELL * gz)
			if _blocked(at):
				continue
			var post := Look.prop("Light_Street_1.glb", 6.0, 0.8)
			post.position = at
			post.rotation.y = _art_rng.randi() % 4 * PI / 2.0
			post.rotation.z = _art_rng.randf_range(-0.06, 0.06)
			art.add_child(post)
			if lit < 5 and _art_rng.randf() < 0.45:
				lit += 1
				var bulb := Look.lamp(Color(1.0, 0.8, 0.55), 4.0, 13.0)
				bulb.position.y = 5.4
				post.add_child(bulb)


## True if a building footprint covers `at`.
func _blocked(at: Vector3) -> bool:
	for b in _buildings:
		var size: Vector3 = b["size"]
		var d: Vector3 = at - b["center"]
		if absf(d.x) < size.x * 0.5 + 0.6 and absf(d.z) < size.z * 0.5 + 0.6:
			return true
	return false


## Ruined towers beyond the walls, fading into the smoke.
func _dress_skyline(art: Node3D) -> void:
	var half := CELL * GRID * 0.5
	var tower := Look.surface("concrete", {"tint": Color(0.5, 0.44, 0.4), "grime": 0.9, "scale": 0.1, "lit_windows": 0.03})
	for i in 46:
		var angle := TAU * i / 46.0 + _art_rng.randf_range(-0.05, 0.05)
		var dist := half + _art_rng.randf_range(16.0, 70.0)
		var size := Vector3(_art_rng.randf_range(9, 20), _art_rng.randf_range(18, 70), _art_rng.randf_range(9, 20))
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = tower
		node.mesh = mesh
		# Square to the grid, pushed out past the wall.
		var dir := Vector3(cos(angle), 0, sin(angle))
		var reach := dist / maxf(absf(dir.x), absf(dir.z))
		node.position = dir * reach + Vector3(0, size.y * 0.5 - 1.0, 0)
		node.rotation.z = _art_rng.randf_range(-0.03, 0.03)
		art.add_child(node)
		Look.make_building(node, size, float(i) * 3.1)


func _shuffle(list: Array[Vector3]) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := list[i]
		list[i] = list[j]
		list[j] = tmp
