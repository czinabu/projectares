class_name WeatherView
extends Node3D
## What a storm crossing the map looks and sounds like (DESIGN.md "Weather:
## ash storms"), view only. The `Raid` adds one where `Look` is on and its
## world has weather; it reads `Raid.weather` (the server's word on a client)
## and never changes it.
##
## From outside a storm is a front: a churning mass of ash or snow on a
## steep dome as wide as the cell, with no hard outline (its sides and crown
## fade where they are seen edge on), its top heaped with billows that
## break the outline, and soft where it meets the ground. It thins as the
## camera comes up to it, so the way in is a thickening haze. Inside it, streaks are driven past on
## the wind and billows drift through around whichever camera draws the
## world, the wind howls, and the map's storm mood closes the fog in by how
## far in the camera is (the map's "weather_here" meta, read by
## `Look.WarMood`). The same for first and third person: only the camera
## differs.

const WALL_SHADER := preload("res://assets/shaders/storm_wall.gdshader")
const BILLOW_SHADER := preload("res://assets/shaders/storm_billow.gdshader")
## The dome is drawn in layers, each a little narrower and lower, churning
## at their own pace, so the front has depth.
const WALL_LAYERS := 2
## The dome's profile: rings up its side, cuts round it, and how square its
## shoulder is (2 a half ellipse, higher a steeper wall with a rounder crown).
const WALL_RINGS := 12
const WALL_CUTS := 64
const WALL_SHOULDER := 3.0
## The billows heaped round the dome's upper half (one draw for all).
const HEADS := 56
## The dome stands this far out from the cell's middle, as a share of its
## radius: inside the cell's soft edge (`Weather.core_share`), so when the
## camera reaches the dome and it thins away, the storm's own haze has
## already begun closing in. Walking in only ever thickens.
const WALL_REACH := 0.8
const STREAKS := 2000
const BILLOWS := 60
## Below this, inside a storm, the air around the camera is left empty.
const AIR_FROM := 0.02
## Spindrift (a kit with "drift"): plumes of snow torn off the edges the map
## offers (`weather_ridges()`), the nearest `DRIFTS` within `DRIFT_RANGE`
## of the camera where the storm is at least `DRIFT_FROM` strong, picked
## again every `DRIFT_EVERY` seconds.
const DRIFTS := 8
const DRIFT_RANGE := 150.0
const DRIFT_FROM := 0.15
const DRIFT_EVERY := 0.5
## The streaks' speed with the wind steady, and how much a gust adds:
## the gust is the cell's own push where the camera is (`Weather.gust_at`)
## plus a flurry that comes and goes every few seconds, so the snow is
## driven past in bursts, never at one even rate.
const STREAK_SPEED := Vector2(8.0, 13.0)
const GUST_BOOST := 0.9

var raid: Raid
## How far into a storm the camera is right now, 0 to 1.
var here := 0.0

var _kit := {}
var _wall: Node3D
var _wall_mats: Array[ShaderMaterial] = []
var _heads_mat: ShaderMaterial
var _air: Node3D
var _streaks: GPUParticles3D
var _billows: GPUParticles3D
var _wind: AudioStreamPlayer
## How hard the wind is blowing past the camera right now, 0 to 1 over
## its steady strength (view only, eased).
var gust := 0.0
var _gust_clock := 0.0
var _drifts: Array[GPUParticles3D] = []
var _ridges := PackedVector3Array()
var _drift_left := 0.0
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
	if bool(_kit.get("drift", false)) and raid != null and raid.map != null and raid.map.has_method("weather_ridges"):
		_ridges = raid.map.call("weather_ridges")
		for i in DRIFTS:
			var plume := _build_drift()
			_drifts.append(plume)
			add_child(plume)
	var stream := Sfx.get_stream(str(_kit.get("sound", "wind")))
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
	# Deep inside, the fog has the storm and the dome would be all but clear:
	# it is not drawn at all.
	var on := weather.kind != "" and weather.strength > 0.0 and here < 0.75
	_wall.visible = on
	if on:
		if not _has_centre or _shown_centre.distance_to(weather.centre) > 40.0:
			_shown_centre = weather.centre
		_shown_centre = _shown_centre.lerp(weather.centre, clampf(delta * 2.0, 0.0, 1.0))
		_has_centre = true
		_wall.global_position = Vector3(_shown_centre.x, _ground_under(_shown_centre) - 6.0, _shown_centre.z)
		var size := weather.radius * WALL_REACH / 100.0
		_wall.scale = Vector3(size, 1.0, size)
		# Seen from inside, the dome thins away: the fog does that work there.
		var opacity := 0.95 * weather.strength * lerpf(1.0, 0.0, smoothstep(0.1, 0.75, here))
		for mat in _wall_mats:
			mat.set_shader_parameter("opacity", opacity)
		_heads_mat.set_shader_parameter("opacity", opacity)
		_heads_mat.set_shader_parameter("size_scale", sqrt(size))
	else:
		_has_centre = false
	var in_air := here > AIR_FROM and camera != null
	_streaks.emitting = in_air
	_billows.emitting = in_air
	_air.visible = in_air
	_gust_clock += delta
	var gusting := 0.0
	var wind := Vector3(weather.velocity.x, 0.0, weather.velocity.z)
	wind = wind.normalized() if wind.length_squared() > 0.0001 else Vector3.RIGHT
	if in_air:
		gusting = gust_now(weather, camera.global_position, _gust_clock)
	gust = move_toward(gust, gusting, delta * (3.0 if gusting > gust else 1.2))
	if in_air:
		_air.global_position = camera.global_position
		_streaks.amount_ratio = here
		_billows.amount_ratio = here
		# A gust veers the snow off the wind's line a little, as well as
		# driving it harder.
		var across := Vector3(-wind.z, 0.0, wind.x)
		var push := weather.gust_at(camera.global_position)
		var veer := clampf(push.dot(across) / maxf(push.length(), 0.001), -1.0, 1.0) * 0.35 * gust
		var drive := (wind + across * veer).normalized()
		drive.y = float(_kit.get("fall", -0.06)) * (1.0 - 0.5 * gust)
		var streaks := _streaks.process_material as ParticleProcessMaterial
		streaks.direction = drive.normalized()
		streaks.initial_velocity_min = STREAK_SPEED.x * (1.0 + GUST_BOOST * gust)
		streaks.initial_velocity_max = STREAK_SPEED.y * (1.0 + GUST_BOOST * gust)
		(_billows.process_material as ParticleProcessMaterial).direction = drive.normalized()
		_streaks.speed_scale = 1.0 + 0.3 * gust
	_place_drifts(weather, camera, wind, delta)
	if _wind != null:
		var volume := linear_to_db(maxf(here, 0.001)) - 8.0 + 5.0 * gust
		_wind.volume_db = volume
		_wind.pitch_scale = 1.0 + 0.12 * gust
		if here > AIR_FROM and not _wind.playing:
			_wind.play()
		elif here <= AIR_FROM and _wind.playing:
			_wind.stop()


## How hard the wind gusts at `at` at `clock` seconds, 0 (the steady
## wind) to 1: the cell's own push there over its steady strength, times a
## flurry that builds and passes every few seconds. View only.
static func gust_now(weather: Weather, at: Vector3, clock: float) -> float:
	var s := weather.strength_at(at)
	if s <= 0.0:
		return 0.0
	var push := weather.gust_at(at).length()
	var most := push / maxf(s, 0.001)
	var steady := 0.0
	if weather.gust_most() > 0.0:
		steady = clampf(most / weather.gust_most() - 0.4, 0.0, 1.0)
	var flurry := maxf(0.0, sin(clock * 0.9) * 0.6 + sin(clock * 2.3 + 1.7) * 0.4)
	return clampf((0.35 * steady + 0.65 * flurry) * s, 0.0, 1.0)


## Puts the spindrift plumes on the nearest edges the storm is tearing
## snow off, each blowing downwind and up off its edge by how strong the
## storm is there.
func _place_drifts(weather: Weather, camera: Camera3D, wind: Vector3, delta: float) -> void:
	if _drifts.is_empty():
		return
	_drift_left -= delta
	var on := weather.kind != "" and weather.strength > 0.0 and camera != null
	if not on:
		for plume in _drifts:
			plume.emitting = false
		return
	if _drift_left > 0.0:
		return
	_drift_left = DRIFT_EVERY
	var from := camera.global_position
	var picks: Array = []
	for point in _ridges:
		var away := Vector2(point.x - from.x, point.z - from.z).length()
		if away > DRIFT_RANGE:
			continue
		var s := weather.strength_at(point)
		if s < DRIFT_FROM:
			continue
		picks.append([away, point, s])
	picks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _drifts.size():
		var plume := _drifts[i]
		if i >= picks.size():
			plume.emitting = false
			continue
		var point: Vector3 = picks[i][1]
		var s: float = picks[i][2]
		plume.global_position = point + Vector3(0, 1.0, 0)
		plume.rotation.y = atan2(wind.x, wind.z)
		plume.amount_ratio = s
		var lift := wind + Vector3.UP * 0.35
		(plume.process_material as ParticleProcessMaterial).direction = plume.global_basis.inverse() * lift.normalized()
		plume.emitting = true


## One plume of spindrift: soft puffs torn off an edge and streamed away
## downwind, rising and thinning as they go.
func _build_drift() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Drift"
	particles.amount = 70
	particles.lifetime = 4.0
	particles.local_coords = false
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-50, -10, -50), Vector3(100, 50, 100))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(7, 0.5, 2)
	mat.direction = Vector3.FORWARD
	mat.spread = 12.0
	mat.initial_velocity_min = 7.0
	mat.initial_velocity_max = 12.0
	mat.gravity = Vector3(0, -0.6, 0)
	mat.damping_min = 0.5
	mat.damping_max = 1.0
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	var fade := Gradient.new()
	var tint: Color = _kit.get("billow", Color(1, 1, 1, 0.3))
	fade.set_color(0, Color(tint.r, tint.g, tint.b, tint.a * 1.6))
	fade.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	mat.color_ramp = fade_tex
	particles.process_material = mat
	var quad := QuadMesh.new()
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.proximity_fade_enabled = true
	draw.proximity_fade_distance = 1.5
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


func _ground_under(at: Vector3) -> float:
	if raid.map.has_method("ground_height"):
		return float(raid.map.call("ground_height", at.x, at.z))
	return 0.0


## The front, built for a 100 m radius and scaled to the cell: the dome's
## layers and the billows heaped on it.
func _build_wall() -> Node3D:
	var root := Node3D.new()
	root.name = "Wall"
	var height: float = _kit.get("wall_height", 90.0)
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	var fast := FastNoiseLite.new()
	# Broad and soft: a storm's billows are tens of metres across.
	fast.frequency = 0.008
	fast.fractal_octaves = 4
	fast.seed = 7
	noise.noise = fast
	var tint: Color = _kit.get("wall_tint", Color(0.2, 0.1, 0.08))
	var lit: Color = _kit.get("wall_lit", Color(0.5, 0.3, 0.2))
	for layer in WALL_LAYERS:
		var mat := ShaderMaterial.new()
		mat.shader = WALL_SHADER
		mat.set_shader_parameter("noise_tex", noise)
		mat.set_shader_parameter("tint", tint)
		mat.set_shader_parameter("lit", lit)
		mat.set_shader_parameter("churn", 1.0 + layer * 0.5)
		mat.set_shader_parameter("seed", layer * 0.31)
		_wall_mats.append(mat)
		var mesh := MeshInstance3D.new()
		mesh.name = "Layer%d" % layer
		mesh.mesh = dome_mesh(100.0 * (1.0 - layer * 0.1), height * (1.0 - layer * 0.18))
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
	_heads_mat = ShaderMaterial.new()
	_heads_mat.shader = BILLOW_SHADER
	_heads_mat.set_shader_parameter("noise_tex", noise)
	_heads_mat.set_shader_parameter("tint", tint)
	_heads_mat.set_shader_parameter("lit", lit)
	root.add_child(_build_heads(height))
	root.visible = false
	return root


## The radius of the dome `height` high at `up` metres, over a base of
## `radius`: a steep wall with a rounded crown, a little flared at the foot.
static func dome_radius(radius: float, height: float, up: float) -> float:
	var h := clampf(up / height, 0.0, 1.0)
	var r := pow(maxf(1.0 - pow(h, WALL_SHOULDER), 0.0), 1.0 / WALL_SHOULDER)
	return radius * r * (1.0 + 0.06 * (1.0 - h) * (1.0 - h))


## One layer of the dome: rings up a revolved profile, closed at the crown,
## open at the foot (it stands below the ground). u runs round it, v up it.
static func dome_mesh(radius: float, height: float) -> ArrayMesh:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in WALL_RINGS + 1:
		# Rings bunch towards the crown, where the profile turns.
		var v := sin(float(ring) / WALL_RINGS * PI * 0.5)
		var up := v * height
		var r := dome_radius(radius, height, up)
		var step := height * 0.01
		var slope := (dome_radius(radius, height, minf(up + step, height)) - dome_radius(radius, height, maxf(up - step, 0.0))) / (minf(up + step, height) - maxf(up - step, 0.0))
		# The profile's outward normal in (out, up): its tangent is (slope, 1).
		var flat := Vector2(1.0, -slope).normalized()
		if ring == WALL_RINGS:
			flat = Vector2(0.0, 1.0)
		for cut in WALL_CUTS + 1:
			var u := float(cut) / WALL_CUTS
			var angle := u * TAU
			var out := Vector3(cos(angle), 0.0, sin(angle))
			points.append(out * r + Vector3(0.0, up, 0.0))
			normals.append((out * flat.x + Vector3.UP * flat.y).normalized())
			uvs.append(Vector2(u, v))
	var row := WALL_CUTS + 1
	for ring in WALL_RINGS:
		for cut in WALL_CUTS:
			var a := ring * row + cut
			var b := a + row
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The billows heaped on the dome: soft puffs round its upper half and
## crown, each facing the camera (`storm_billow.gdshader`), all one draw.
## Laid out with their own RNG, so they never touch the game's.
func _build_heads(height: float) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	multi.mesh = quad
	multi.instance_count = HEADS
	for i in HEADS:
		var angle := (float(i) + rng.randf_range(-0.4, 0.4)) / HEADS * TAU
		# Most ride the shoulder, where the outline is; a quarter heap the
		# crown, so from above it is a cloud top, not a lid.
		var crown := i % 4 == 0
		var h := rng.randf_range(0.82, 0.96) if crown else rng.randf_range(0.4, 0.85)
		var up := h * height
		var r := dome_radius(100.0, height, up) * (sqrt(rng.randf()) * 0.8 if crown else rng.randf_range(0.88, 0.98))
		var at := Vector3(cos(angle) * r, up, sin(angle) * r)
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		multi.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(20.0, 38.0) * height / 90.0, 0.0, 0.0))
	var heads := MultiMeshInstance3D.new()
	heads.name = "Heads"
	heads.multimesh = multi
	heads.material_override = _heads_mat
	heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The puffs swell past the points they are set on.
	heads.custom_aabb = AABB(Vector3(-140, -20, -140), Vector3(280, height + 60.0, 280))
	return heads


## Thin streaks of ash or snow driven past on the wind, close round the camera.
func _build_streaks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Streaks"
	# A kit may ask for more, shorter-lived streaks (rain falls out of the
	# box round the camera faster than snow is blown through it).
	particles.amount = int(_kit.get("streaks", STREAKS))
	particles.lifetime = float(_kit.get("streak_life", 3.0))
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
