class_name WeatherView
extends Node3D
## What a storm crossing the map looks and sounds like (DESIGN.md "Weather:
## ash storms"), view only. The `Raid` adds one where `Look` is on and its
## world has weather; it reads `Raid.weather` (the server's word on a client)
## and never changes it.
##
## From outside a storm is a wall: a churning curtain of ash or snow on an
## open cylinder as wide as the cell. Inside it, streaks are driven past on
## the wind and billows drift through around whichever camera draws the
## world, the wind howls, and the map's storm mood closes the fog in by how
## far in the camera is (the map's "weather_here" meta, read by
## `Look.WarMood`). The same for first and third person: only the camera
## differs.

const WALL_SHADER := preload("res://assets/shaders/storm_wall.gdshader")
## The wall is drawn in layers, each a little narrower and lower, so its
## edge has depth.
const WALL_LAYERS := 3
const STREAKS := 2000
const BILLOWS := 60
## Below this, inside a storm, the air around the camera is left empty.
const AIR_FROM := 0.02

var raid: Raid
## How far into a storm the camera is right now, 0 to 1.
var here := 0.0

var _kit := {}
var _wall: Node3D
var _wall_mats: Array[ShaderMaterial] = []
var _air: Node3D
var _streaks: GPUParticles3D
var _billows: GPUParticles3D
var _wind: AudioStreamPlayer
## Where the wall is drawn: eased onto the cell, so a server update never
## makes it jump.
var _shown_centre := Vector3.ZERO
var _has_centre := false


func _ready() -> void:
	name = "WeatherView"
	_kit = Look.weather_kit(raid.world.weather_kind if raid != null and raid.world != null else "")
	_wall = _build_wall()
	add_child(_wall)
	_air = Node3D.new()
	_air.name = "Air"
	add_child(_air)
	_streaks = _build_streaks()
	_billows = _build_billows()
	_air.add_child(_streaks)
	_air.add_child(_billows)
	var stream := Sfx.get_stream("wind")
	if stream != null:
		_wind = AudioStreamPlayer.new()
		_wind.stream = stream
		_wind.volume_db = -60.0
		add_child(_wind)


func _process(delta: float) -> void:
	if raid == null or not is_instance_valid(raid) or raid.map == null:
		return
	var weather := raid.weather
	var camera := get_viewport().get_camera_3d()
	here = weather.strength_at(camera.global_position) if camera != null else 0.0
	raid.map.set_meta("weather_here", here)
	var on := weather.kind != "" and weather.strength > 0.0
	_wall.visible = on
	if on:
		if not _has_centre or _shown_centre.distance_to(weather.centre) > 40.0:
			_shown_centre = weather.centre
		_shown_centre = _shown_centre.lerp(weather.centre, clampf(delta * 2.0, 0.0, 1.0))
		_has_centre = true
		_wall.global_position = Vector3(_shown_centre.x, _ground_under(_shown_centre) - 6.0, _shown_centre.z)
		var size := weather.radius / 100.0
		_wall.scale = Vector3(size, 1.0, size)
		# Seen from inside, the wall thins: the fog does that work there.
		for mat in _wall_mats:
			mat.set_shader_parameter("opacity", 0.95 * weather.strength * lerpf(1.0, 0.3, here))
	else:
		_has_centre = false
	var in_air := here > AIR_FROM and camera != null
	_streaks.emitting = in_air
	_billows.emitting = in_air
	_air.visible = in_air
	if in_air:
		_air.global_position = camera.global_position
		_streaks.amount_ratio = here
		_billows.amount_ratio = here
		var wind := Vector3(weather.velocity.x, 0.0, weather.velocity.z)
		wind = wind.normalized() if wind.length_squared() > 0.0001 else Vector3.RIGHT
		wind.y = float(_kit.get("fall", -0.06))
		(_streaks.process_material as ParticleProcessMaterial).direction = wind.normalized()
		(_billows.process_material as ParticleProcessMaterial).direction = wind.normalized()
	if _wind != null:
		var volume := linear_to_db(maxf(here, 0.001)) - 8.0
		_wind.volume_db = volume
		if here > AIR_FROM and not _wind.playing:
			_wind.play()
		elif here <= AIR_FROM and _wind.playing:
			_wind.stop()


func _ground_under(at: Vector3) -> float:
	if raid.map.has_method("ground_height"):
		return float(raid.map.call("ground_height", at.x, at.z))
	return 0.0


## The wall, built for a 100 m radius and scaled to the cell.
func _build_wall() -> Node3D:
	var root := Node3D.new()
	root.name = "Wall"
	var height: float = _kit.get("wall_height", 90.0)
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	var fast := FastNoiseLite.new()
	fast.frequency = 0.02
	fast.fractal_octaves = 5
	fast.seed = 7
	noise.noise = fast
	for layer in WALL_LAYERS:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 100.0 * (1.0 - layer * 0.08)
		cylinder.bottom_radius = 100.0 * (1.0 - layer * 0.04)
		cylinder.height = height * (1.0 - layer * 0.15)
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		cylinder.radial_segments = 64
		cylinder.rings = 1
		var mat := ShaderMaterial.new()
		mat.shader = WALL_SHADER
		mat.set_shader_parameter("noise_tex", noise)
		mat.set_shader_parameter("tint", _kit.get("wall_tint", Color(0.2, 0.1, 0.08)))
		mat.set_shader_parameter("lit", _kit.get("wall_lit", Color(0.5, 0.3, 0.2)))
		mat.set_shader_parameter("churn", 1.0 + layer * 0.4)
		cylinder.material = mat
		_wall_mats.append(mat)
		var mesh := MeshInstance3D.new()
		mesh.name = "Layer%d" % layer
		mesh.mesh = cylinder
		mesh.position.y = cylinder.height * 0.5
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
	root.visible = false
	return root


## Thin streaks of ash or snow driven past on the wind, close round the camera.
func _build_streaks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Streaks"
	particles.amount = STREAKS
	particles.lifetime = 3.0
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(22, 7, 22)
	mat.direction = Vector3.RIGHT
	mat.spread = 8.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 13.0
	mat.gravity = Vector3.ZERO
	mat.particle_flag_align_y = true
	mat.color = _kit.get("streak", Color(0.55, 0.32, 0.22, 0.55))
	particles.process_material = mat
	var quad := QuadMesh.new()
	quad.size = _kit.get("streak_size", Vector2(0.025, 0.55))
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A streak right at the lens would be a plank across the view: they fade
	# in from a couple of metres out.
	draw.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	draw.distance_fade_min_distance = 1.0
	draw.distance_fade_max_distance = 4.0
	quad.material = draw
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## Big soft billows of ash or snow drifting through.
func _build_billows() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Billows"
	particles.amount = BILLOWS
	particles.lifetime = 9.0
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 40, 120))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(30, 3, 30)
	mat.direction = Vector3.RIGHT
	mat.spread = 15.0
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 6.0
	mat.scale_max = 12.0
	mat.color = _kit.get("billow", Color(0.42, 0.24, 0.17, 0.22))
	particles.process_material = mat
	var quad := QuadMesh.new()
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.proximity_fade_enabled = true
	draw.proximity_fade_distance = 2.0
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = ramp
	draw.albedo_texture = soft
	quad.material = draw
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles
