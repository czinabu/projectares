class_name Planet
extends RefCounted
## Puts a `PlanetType` on a map (DESIGN.md "Planet kit"): its sky and light
## (through `Look.atmosphere`, so war and storm moods work as they do now),
## its ground material, the far horizon ring, the air's drift and the props
## scattered on the ground. All of it is view only: on a headless server
## only the plain sun `Look.atmosphere` always adds exists, and the ground's
## collision is the map's own `Terrain`, built from `PlanetTerrain`.

const SKY_SHADER := preload("res://assets/shaders/planet_sky.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/planet_ground.gdshader")
const GameSettings := preload("res://core/settings/game_settings.gd")

## The ground's layers, in the order of the shader's `textured` and `tile`.
const LAYERS: Array[String] = ["base", "rock", "cap", "patch"]

static var _grounds := {}


## Where a scanned surface's map lives (`PlanetType.surfaces`).
static func surface_path(folder: String, map: String) -> String:
	return "res://assets/textures/%s/%s.jpg" % [folder, map]


## The sky, light and air of `type` on `parent`. `war` is a world's own war
## mood, if it has one (it keeps the planet's sky and only changes the light).
static func atmosphere(parent: Node3D, type: PlanetType, war := {}) -> void:
	Look.atmosphere(parent, type.calm, war, type.storm)
	if not Look.enabled:
		return
	var env_node := parent.get_node_or_null("Atmosphere") as WorldEnvironment
	if env_node == null:
		return
	var sky_mat := sky_material(type)
	env_node.environment.sky.sky_material = sky_mat
	env_node.environment.sky.radiance_size = Sky.RADIANCE_SIZE_64
	var mood := parent.get_node_or_null("WarMood")
	if mood != null:
		mood.sky_mat = sky_mat
	var sun := parent.get_node_or_null("Sun") as DirectionalLight3D
	Look.apply_mood(Look.mood_values(type.calm), env_node.environment, sky_mat, sun)
	if not type.smoke.is_empty():
		parent.add_child(GroundSmoke.make(type.smoke, env_node.environment))
	# Far ground is part of the planet now, so the sun's shadows reach further
	# out, in fewer, cheaper splits beyond the fight.
	if sun != null:
		sun.directional_shadow_max_distance = 200.0
		sun.directional_shadow_fade_start = 0.85


static func sky_material(type: PlanetType) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("cloud_noise", Look._noise_texture())
	for key: String in type.sky:
		mat.set_shader_parameter(key, type.sky[key])
	return mat


## One material per planet type, shared by the ground, the horizon and the
## rocks, so they always match and batch together.
static func ground_material(type: PlanetType) -> Material:
	if _grounds.has(type.id):
		return _grounds[type.id]
	var mat: Material
	if not Look.enabled:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = type.ground.get("base_a", Color.GRAY)
		mat = plain
	else:
		var sm := ShaderMaterial.new()
		sm.shader = GROUND_SHADER
		sm.set_shader_parameter("noise_tex", Look._noise_texture())
		var textured := Vector4.ZERO
		for i in LAYERS.size():
			var folder := String(type.surfaces.get(LAYERS[i], ""))
			if folder == "":
				continue
			sm.set_shader_parameter(LAYERS[i] + "_albedo", load(surface_path(folder, "Color")))
			sm.set_shader_parameter(LAYERS[i] + "_normal", load(surface_path(folder, "NormalGL")))
			textured[i] = 1.0
		sm.set_shader_parameter("textured", textured)
		for key: String in type.ground:
			sm.set_shader_parameter(key, type.ground[key])
		mat = sm
	_grounds[type.id] = mat
	return mat


## The land past a map's edge, out to the type's `horizon.reach`: one mesh,
## no collision, no shadow, rings spaced wider with distance so the vertex
## count stays flat (about 21,000) whatever the reach. Its height is the
## planet's own ground, raised into mountains toward the far edge.
## `inner` is where the map's own ground ends (half its width).
static func horizon(type: PlanetType, ground: PlanetTerrain, inner: float) -> MeshInstance3D:
	var reach := float(type.horizon.get("reach", 2600.0))
	var peaks := float(type.horizon.get("peaks", 120.0))
	var rings := 64
	var spokes := 320
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var ridge := FastNoiseLite.new()
	ridge.seed = 91
	ridge.frequency = 0.0016
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5
	# Start inside the map's corners so there is never a gap at a diagonal,
	# a little under the ground so the seam hides.
	var start := inner * 0.92
	for ri in rings + 1:
		var t := float(ri) / rings
		var r := start * pow(reach / start, t)
		for si in spokes:
			var a := TAU * si / spokes
			var x := cos(a) * r
			var z := sin(a) * r
			var h := ground.height_at(x, z)
			var far := smoothstep(start * 1.2, reach * 0.55, r)
			var k := (ridge.get_noise_2d(x, z) + 1.0) * 0.5
			h += k * k * peaks * far
			# Inside the square map, sink the ring under its ground.
			if maxf(absf(x), absf(z)) < inner:
				h -= 12.0
			verts.append(Vector3(x, h, z))
	for ri in rings:
		for si in spokes:
			var a := ri * spokes + si
			var b := ri * spokes + (si + 1) % spokes
			var c := a + spokes
			var d := b + spokes
			indices.append_array([a, c, b, b, c, d])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		st.add_vertex(v)
	for i in indices:
		st.add_index(i)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, ground_material(type))
	var node := MeshInstance3D.new()
	node.name = "Horizon"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.extra_cull_margin = peaks
	return node


## What drifts in the air round the viewer: "embers", "ash", "snow" (the
## kinds `Look.weather` has) and "rain", "sand", "spores". `thick` scales
## the amount, for a storm. View only.
static func weather(parent: Node3D, kind: String, extent := 40.0, height := 24.0, thick := 1.0) -> GPUParticles3D:
	if not Look.enabled or kind == "":
		return null
	if kind in ["embers", "ash", "snow"]:
		Look.weather(parent, kind, extent, height)
		var made := parent.get_node_or_null("Weather") as GPUParticles3D
		if made != null:
			made.amount = int(made.amount * thick)
		return made
	var particles := GPUParticles3D.new()
	particles.name = "Weather"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(extent, height * 0.5, extent)
	var quad := QuadMesh.new()
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = Look._soft_dot()
	match kind:
		"rain":
			particles.amount = int(9000 * thick)
			particles.lifetime = 1.4
			mat.gravity = Vector3(1.5, -26.0, 0.6)
			mat.initial_velocity_min = 8.0
			mat.initial_velocity_max = 12.0
			mat.direction = Vector3(0.05, -1, 0.02)
			mat.spread = 3.0
			mat.color = Color(0.8, 0.9, 0.9, 0.16)
			quad.size = Vector2(0.008, 0.45)
			draw.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			draw.albedo_texture = null
		"sand":
			particles.amount = int(4000 * thick)
			particles.lifetime = 2.5
			mat.gravity = Vector3(16.0, -0.6, 5.0)
			mat.initial_velocity_min = 6.0
			mat.initial_velocity_max = 14.0
			mat.direction = Vector3(1, 0.05, 0.3)
			mat.spread = 12.0
			mat.turbulence_enabled = true
			mat.turbulence_noise_scale = 4.0
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.15
			mat.color = Color(0.85, 0.62, 0.4, 0.45)
			mat.scale_min = 0.6
			mat.scale_max = 1.6
			quad.size = Vector2(0.06, 0.06)
			draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		"spores":
			particles.amount = int(700 * thick)
			particles.lifetime = 14.0
			mat.gravity = Vector3(0.1, 0.12, 0.05)
			mat.initial_velocity_max = 0.3
			mat.turbulence_enabled = true
			mat.turbulence_noise_scale = 5.0
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.15
			mat.color = Color(0.6, 2.4, 1.6, 0.9)
			mat.scale_min = 0.4
			mat.scale_max = 1.3
			quad.size = Vector2(0.06, 0.06)
			draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = draw
	particles.process_material = mat
	particles.draw_pass_1 = quad
	particles.preprocess = particles.lifetime
	particles.position.y = height * 0.5
	particles.visibility_aabb = AABB(Vector3(-extent, -height, -extent), Vector3(extent, height, extent) * 2.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)
	return particles


## Battle smoke lying low over the ground (`PlanetType.smoke`): one
## volumetric fog box that follows the camera and stands on the ground under
## it, thicker as the war heats up and in a storm (the map's "war_intensity"
## and "weather_here" metas, as `Look.WarMood` reads them). View only, and
## off with `GameSettings.ground_smoke`.
class GroundSmoke:
	extends Node3D

	## How far round the camera the smoke reaches.
	var reach := 500.0
	var depth := 18.0
	var density := 0.08
	var war_mult := 0.5
	var storm_mult := 1.0
	var env: Environment
	var volume: FogVolume
	var material: FogMaterial

	static func make(p: Dictionary, p_env: Environment) -> GroundSmoke:
		var smoke := GroundSmoke.new()
		smoke.name = "GroundSmoke"
		smoke.env = p_env
		smoke.depth = float(p.get("depth", 18.0))
		smoke.density = float(p.get("density", 0.08))
		smoke.war_mult = float(p.get("war", 0.5))
		smoke.storm_mult = float(p.get("storm", 1.0))
		smoke.material = FogMaterial.new()
		smoke.material.albedo = p.get("colour", Color(0.45, 0.44, 0.44))
		smoke.material.height_falloff = 0.15
		smoke.material.edge_fade = 0.2
		var noise := FastNoiseLite.new()
		noise.frequency = 0.025
		var tex := NoiseTexture3D.new()
		tex.noise = noise
		tex.width = 64
		tex.height = 32
		tex.depth = 64
		tex.seamless = true
		smoke.material.density_texture = tex
		smoke.volume = FogVolume.new()
		smoke.volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		smoke.volume.size = Vector3(smoke.reach * 2.0, smoke.depth, smoke.reach * 2.0)
		smoke.volume.material = smoke.material
		smoke.add_child(smoke.volume)
		smoke.add_to_group("ground_smoke")
		p_env.volumetric_fog_density = 0.0
		p_env.volumetric_fog_albedo = smoke.material.albedo
		p_env.volumetric_fog_anisotropy = 0.3
		p_env.volumetric_fog_length = 200.0
		p_env.volumetric_fog_detail_spread = 2.0
		p_env.volumetric_fog_gi_inject = 1.0
		p_env.volumetric_fog_ambient_inject = 0.8
		smoke.show_smoke(GameSettings.ground_smoke)
		return smoke

	func show_smoke(on: bool) -> void:
		visible = on
		set_process(on)
		if env != null:
			env.volumetric_fog_enabled = on

	## How thick it is for a war intensity and a share of storm, 0 to 1.
	func density_for(war: float, storm: float) -> float:
		return density * (1.0 + war_mult * clampf(war, 0.0, 1.0) + storm_mult * clampf(storm, 0.0, 1.0))

	func _process(_delta: float) -> void:
		var map := get_parent()
		material.density = density_for(float(map.get_meta("war_intensity", 0.0)), float(map.get_meta("weather_here", 0.0)))
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var at := camera.global_position
		var ground := at.y - 2.0
		if map.has_method("ground_height"):
			ground = float(map.call("ground_height", at.x, at.z))
		# Stood on the ground under the camera: thickest at the foot, thinning
		# upward through `depth`.
		volume.global_position = Vector3(at.x, ground + depth * 0.5 - 2.0, at.z)
