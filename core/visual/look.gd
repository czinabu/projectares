extends Node
## Autoload `Look`: the art layer.
##
## Gameplay scripts build plain greybox shapes and know nothing about art. This
## node watches the scene tree and dresses what appears: actors get animated
## models, held weapons get gun models, caches get crates. Maps ask it for
## surfaces, atmosphere and props. On a headless server it does nothing, so
## the simulation never depends on it.
##
## Nothing here names a world. Worlds pick from the generic kits below:
##   - surfaces by kind ("concrete", "asphalt", "metal", ...), see `SURFACES`
##   - skins by name, set with `actor.set_meta("look", "<skin>")`, see `SKINS`
##   - an atmosphere described by a dictionary, see `atmosphere`

const SURFACE_SHADER := preload("res://assets/shaders/surface.gdshader")
const SKY_SHADER := preload("res://assets/shaders/sky.gdshader")
const GEAR_SHADER := preload("res://assets/shaders/gear.gdshader")
const ActorSkin := preload("res://core/visual/actor_skin.gd")
const Human := preload("res://core/visual/human.gd")
const CHARACTER_SHADER := preload("res://assets/shaders/character.gdshader")
const Vfx := preload("res://core/visual/vfx.gd")
const UiTheme := preload("res://core/visual/ui_theme.gd")
const VEHICLE_SCRIPT := "res://core/vehicle/vehicle.gd"

const TEXTURES := "res://assets/textures/"
const PROPS := "res://assets/props/"
const WEAPONS := "res://assets/weapons/"
const CHARACTERS := "res://assets/characters/"

## Texture sets. `scale` is tiles per meter.
const SURFACES := {
	"concrete": {"tex": "Concrete012", "scale": 0.22},
	"asphalt": {"tex": "Asphalt021", "scale": 0.3},
	"road": {"tex": "Road001", "scale": 0.2},
	"brick": {"tex": "Bricks066", "scale": 0.35},
	"metal": {"tex": "Metal063", "scale": 0.4, "metal": 0.85},
	"ground": {"tex": "Ground037", "scale": 0.25},
}

## Character models. `height` is how tall the model stands in meters.
## `anims` maps what the actor is doing to an animation in the file.
## Walk and run clips are measured from their feet (`feet`, default
## Foot.L and Foot.R) so they play at the speed the actor moves; `run_back`,
## `run_left` and `run_right` are optional (see `locomotion.gd`).
## A skin lists one or more `scenes`; each actor wearing it gets one of them,
## so a squad is not a row of clones. A skin of `people` is built from parts
## instead (see `human.gd`): the actor's chosen appearance if it has one
## (`set_appearance`), otherwise a random mix of the outfits listed, per
## build. `saturation`, `brightness`, `metal` and
## `rough` are optional and tune the character shader: people keep their
## colors, machines are pulled toward worn metal.
const HUMAN_ANIMS := {"idle": "Idle_Gun_Pointing", "walk": "Walk", "run": "Run", "death": "Death",
	"idle_melee": "Idle_Sword", "attack": "Sword_Slash", "move_gun": "Run_Shoot",
	"run_back": "Run_Back", "run_left": "Run_Left", "run_right": "Run_Right"}
const HUMAN_ARM := ["UpperArm.R", "LowerArm.R", "Wrist.R"]
const HUMAN_OFF_ARM := ["UpperArm.L", "LowerArm.L", "Wrist.L"]
const HUMAN_SPINE := ["Abdomen", "Torso", "Chest"]
const SKINS := {
	"raider": {
		"people": {"m": ["Swat", "Spacesuit", "Adventurer"], "f": ["Soldier", "SciFi", "Adventurer"]},
		"height": 1.8, "tint": Color(0.8, 0.82, 0.86), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck",
		"saturation": 0.75, "brightness": 0.85, "metal": 0.0, "rough": 0.85,
		"anims": HUMAN_ANIMS,
	},
	"scavenger": {
		"people": {"m": ["Punk", "Casual_Hoodie", "Casual_2", "Farmer", "Beach"], "f": ["Punk", "Worker", "Casual", "Medieval"]},
		"height": 1.76, "tint": Color(0.86, 0.76, 0.68), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck",
		"saturation": 0.7, "brightness": 0.75, "metal": 0.0, "rough": 0.9,
		"anims": HUMAN_ANIMS,
	},
	"heavy": {
		"scenes": ["George.glb"], "height": 2.35, "tint": Color(0.55, 0.42, 0.38),
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "SwordSlash"},
	},
	"sentinel": {
		"scenes": ["Stan.glb"], "height": 2.2, "tint": Color(0.62, 0.68, 0.74),
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Punch"},
	},
	"stalker": {
		"scenes": ["Enemy_2Legs_Gun.glb"], "height": 1.7, "tint": Color(0.3, 0.32, 0.38),
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "death": "Death", "attack": "Attack"},
	},
}
const DEFAULT_SKIN := "raider"

## Gun models picked by item tag, first match wins. Tags, never ids.
const GUN_MODELS := [
	["smg", "SMG_1.glb"],
	["marksman", "Sniper_2.glb"],
	["shotgun", "Shotgun_1.glb"],
	["starter", "AR_5.glb"],
	["rifle", "AR_2.glb"],
]
const DEFAULT_GUN := "AR_3.glb"
## Melee models picked by item tag, first match wins: file, length in meters,
## how far up from the pommel the hand grips it, and whether it takes both hands.
const MELEE_MODELS := [
	["hammer", "Hammer.glb", 1.15, 0.3, true],
	["starter", "Sword.glb", 1.15, 0.13, false],
	["blade", "Katana.glb", 1.2, 0.14, false],
]
const DEFAULT_MELEE := ["", "Sword.glb", 1.15, 0.13, false]
const GUN_LENGTH := 0.72

## False on a headless server: nothing is dressed and no art is loaded.
var enabled := DisplayServer.get_name() != "headless"

var _materials := {}
var _noise: NoiseTexture2D
var _gear_materials := {}
var _prop_sizes := {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	if enabled:
		UiTheme.apply()


## A dark backdrop with a warm glow low in the frame, for menu screens.
func backdrop() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.2, 0.11, 0.06))
	gradient.set_color(1, Color(0.035, 0.035, 0.04))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 1.05)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	return texture


func _on_node_added(node: Node) -> void:
	if not enabled:
		return
	if node.has_meta("display_item"):
		_dress_display.call_deferred(node)
	elif node is Actor:
		_dress_actor.call_deferred(node)
	elif node is LootContainer:
		_dress_cache.call_deferred(node)
	elif node is Depot:
		_dress_depot.call_deferred(node)
	elif node is CharacterBody3D and node.get_script() != null \
			and node.get_script().resource_path == VEHICLE_SCRIPT:
		_dress_vehicle.call_deferred(node)


# --- Surfaces -----------------------------------------------------------------

## A world-space PBR material. `opts` may set: tint (Color), scale (float),
## blend (surface kind to mix in), blend_amount, wetness, snow, snow_patchy,
## grime, saturation,
## rough_mult, lit_windows (chance 0..1), window_glow (Color).
func surface(kind: String, opts := {}) -> Material:
	var key := kind + str(opts)
	if _materials.has(key):
		return _materials[key]
	var def: Dictionary = SURFACES.get(kind, SURFACES["concrete"])
	var tint: Color = opts.get("tint", Color.WHITE)
	var mat: Material
	if not enabled:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = tint * 0.5
		mat = plain
	else:
		var sm := ShaderMaterial.new()
		sm.shader = SURFACE_SHADER
		_set_textures(sm, "", def["tex"])
		sm.set_shader_parameter("noise_tex", _noise_texture())
		sm.set_shader_parameter("tint", tint)
		sm.set_shader_parameter("tex_scale", opts.get("scale", def["scale"]))
		sm.set_shader_parameter("metal", def.get("metal", 0.0))
		sm.set_shader_parameter("rough_mult", opts.get("rough_mult", 1.0))
		sm.set_shader_parameter("wetness", opts.get("wetness", 0.0))
		sm.set_shader_parameter("snow", opts.get("snow", 0.0))
		sm.set_shader_parameter("grime", opts.get("grime", 0.4))
		sm.set_shader_parameter("snow_patchy", opts.get("snow_patchy", 0.0))
		sm.set_shader_parameter("saturation", opts.get("saturation", 0.8))
		sm.set_shader_parameter("window_lit_chance", opts.get("lit_windows", 0.05))
		sm.set_shader_parameter("window_glow", opts.get("window_glow", Color(1.0, 0.62, 0.3)))
		if opts.has("blend"):
			var other: Dictionary = SURFACES.get(opts["blend"], def)
			_set_textures(sm, "blend_", other["tex"])
			sm.set_shader_parameter("blend_amount", opts.get("blend_amount", 0.5))
		mat = sm
	_materials[key] = mat
	return mat


## Turns a box mesh into a building face: windows are laid out from its size.
func make_building(mesh_node: MeshInstance3D, size: Vector3, seed_value: float) -> void:
	if not enabled:
		return
	mesh_node.set_instance_shader_parameter("box_size", size)
	mesh_node.set_instance_shader_parameter("seed", seed_value)


func _set_textures(mat: ShaderMaterial, prefix: String, tex: String) -> void:
	var dir := TEXTURES + tex + "/"
	mat.set_shader_parameter(prefix + "albedo_tex", load(dir + "Color.jpg"))
	mat.set_shader_parameter(prefix + "normal_tex", load(dir + "NormalGL.jpg"))
	if prefix == "":
		mat.set_shader_parameter("rough_tex", load(dir + "Roughness.jpg"))


func _noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 512
		_noise.height = 512
		_noise.seamless = true
		_noise.noise = noise
	return _noise


# --- Atmosphere ---------------------------------------------------------------

## Sky, fog, sun and post-processing for a map. Keys, all optional:
##   sky (hdr file name), sky_tint, sky_energy, sky_saturation, sky_rotation,
##   fog_color, fog_density, sun_color, sun_energy, sun_angles (degrees),
##   ambient_color, ambient_energy, exposure, saturation, contrast, glow.
## `war` holds the same keys for the same place in the middle of a battle.
## When it is given, the mood blends from `p` towards it as the map's
## "war_intensity" meta climbs from 0 to 1, and a column of smoke stands over
## its "war_centre" meta. Whoever runs the world sets those metas; nothing
## here knows who.
## On a headless server this only adds a plain sun, which nothing sees.
func atmosphere(parent: Node3D, p := {}, war := {}) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = p.get("sun_angles", Vector3(-45, 30, 0))
	sun.light_color = p.get("sun_color", Color.WHITE)
	sun.light_energy = p.get("sun_energy", 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_blur = 1.5
	parent.add_child(sun)
	if not enabled:
		return

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("panorama", load("res://assets/sky/" + p.get("sky", "kloppenheim_06_puresky_2k.hdr")))
	sky_mat.set_shader_parameter("rotation", p.get("sky_rotation", 0.0))
	sky_mat.set_shader_parameter("haze_height", p.get("haze_height", 0.22))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.fog_sun_scatter = p.get("sun_scatter", 0.15)
	env.fog_height = p.get("fog_height", 30.0)
	env.fog_height_density = p.get("fog_height_density", 0.0)
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.6
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.name = "Atmosphere"
	world_env.environment = env
	parent.add_child(world_env)
	var calm := mood_values(p)
	apply_mood(calm, env, sky_mat, sun)
	if war.is_empty():
		return
	var mood := WarMood.new()
	mood.name = "WarMood"
	mood.calm = calm
	mood.war = mood_values(war, calm)
	mood.env = env
	mood.sky_mat = sky_mat
	mood.sun = sun
	mood.column = _war_column()
	parent.add_child(mood)
	mood.add_child(mood.column)


## The part of an atmosphere that can shift while a world runs, with every
## key filled in. Keys missing from `p` come from `fallback`, or from the
## defaults when there is none.
func mood_values(p: Dictionary, fallback := {}) -> Dictionary:
	var fog: Color = p.get("fog_color", fallback.get("fog_color", Color(0.5, 0.5, 0.5)))
	var base := {
		"sky_tint": Color.WHITE, "sky_energy": 1.0, "sky_saturation": 1.0,
		"fog_color": fog, "fog_density": 0.01,
		"sun_color": Color.WHITE, "sun_energy": 1.0,
		"ambient_color": fog.lerp(Color.WHITE, 0.4), "ambient_energy": 1.0,
		"exposure": 1.0, "saturation": 0.9, "contrast": 1.08, "glow": 0.7,
	}
	var out := {}
	for key: String in base:
		out[key] = p.get(key, fallback.get(key, base[key]))
	return out


## A mood part of the way from `a` to `b`.
func blend_moods(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key: String in a:
		out[key] = lerp(a[key], b.get(key, a[key]), clampf(t, 0.0, 1.0))
	return out


func apply_mood(m: Dictionary, env: Environment, sky_mat: ShaderMaterial, sun: DirectionalLight3D) -> void:
	sky_mat.set_shader_parameter("tint", m.sky_tint)
	sky_mat.set_shader_parameter("energy", m.sky_energy)
	sky_mat.set_shader_parameter("saturation", m.sky_saturation)
	sky_mat.set_shader_parameter("haze_color", m.fog_color)
	env.fog_light_color = m.fog_color
	env.fog_density = m.fog_density
	env.ambient_light_color = m.ambient_color
	env.ambient_light_energy = m.ambient_energy
	env.tonemap_exposure = m.exposure
	env.glow_intensity = m.glow
	env.adjustment_saturation = m.saturation
	env.adjustment_contrast = m.contrast
	sun.light_color = m.sun_color
	sun.light_energy = m.sun_energy


## Smoke, ash and red light standing over the heaviest fighting.
func _war_column() -> Node3D:
	var column := Node3D.new()
	column.name = "WarColumn"
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 260
	smoke.lifetime = 22.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 14.0
	mat.direction = Vector3(0.15, 1, 0.05)
	mat.spread = 12.0
	mat.gravity = Vector3(0.5, 0.0, 0.2)
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 8.0
	mat.scale_min = 0.6
	mat.scale_max = 1.5
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 3.0
	mat.turbulence_influence_min = 0.02
	mat.turbulence_influence_max = 0.08
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.5, 0.16, 0.07, 0.0))
	fade.add_point(0.08, Color(0.2, 0.09, 0.06, 0.55))
	fade.add_point(0.5, Color(0.07, 0.06, 0.06, 0.5))
	fade.set_color(fade.get_point_count() - 1, Color(0.05, 0.05, 0.05, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	mat.color_ramp = fade_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(46, 46)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = _soft_dot()
	draw.disable_fog = true
	quad.material = draw
	smoke.process_material = mat
	smoke.draw_pass_1 = quad
	smoke.visibility_aabb = AABB(Vector3(-90, -10, -90), Vector3(180, 260, 180))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.emitting = false
	column.add_child(smoke)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(1.0, 0.25, 0.1)
	glow.omni_range = 70.0
	glow.light_energy = 0.0
	glow.position.y = 14.0
	column.add_child(glow)
	return column


## Shifts a map's mood with the war. Reads the metas "war_intensity" and
## "war_centre" from the node it was added to, and eases towards them so the
## sky never snaps. View only.
class WarMood:
	extends Node

	## How fast the mood follows the meter, per second.
	var follow := 0.12
	## The column of smoke shows above this intensity.
	var column_from := 0.3
	var calm := {}
	var war := {}
	var env: Environment
	var sky_mat: ShaderMaterial
	var sun: DirectionalLight3D
	var column: Node3D
	## The intensity shown right now.
	var shown := 0.0

	func _process(delta: float) -> void:
		var parent := get_parent()
		var target := clampf(float(parent.get_meta("war_intensity", 0.0)), 0.0, 1.0)
		shown = move_toward(shown, target, follow * delta)
		show_intensity(shown, parent.get_meta("war_centre", Vector3.ZERO))

	## Sets the mood for an intensity at once. `_process` calls this with the eased value.
	func show_intensity(value: float, centre: Vector3) -> void:
		shown = value
		Look.apply_mood(Look.blend_moods(calm, war, value), env, sky_mat, sun)
		var smoke: GPUParticles3D = column.get_node("Smoke")
		var glow: OmniLight3D = column.get_node("Glow")
		var strength := clampf((value - column_from) / maxf(1.0 - column_from, 0.001), 0.0, 1.0)
		smoke.emitting = strength > 0.0
		smoke.amount_ratio = maxf(strength, 0.05)
		glow.light_energy = strength * 6.0
		if strength > 0.0:
			column.global_position = column.global_position.lerp(centre, 0.02) \
					if column.global_position.distance_to(centre) < 120.0 else centre


## Drifting particles that fill the air over the whole map: "embers", "snow"
## or "ash". Purely visual.
func weather(parent: Node3D, kind: String, extent: float, height := 26.0) -> void:
	if not enabled:
		return
	var particles := GPUParticles3D.new()
	particles.name = "Weather"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(extent, height * 0.5, extent)
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 6.0
	var quad := QuadMesh.new()
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = _soft_dot()
	match kind:
		"embers":
			particles.amount = 900
			particles.lifetime = 9.0
			mat.gravity = Vector3(0.6, 0.5, 0.2)
			mat.initial_velocity_min = 0.3
			mat.initial_velocity_max = 1.6
			mat.direction = Vector3(0.4, 1, 0.1)
			mat.spread = 60.0
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.2
			mat.color = Color(3.2, 1.1, 0.25)
			mat.scale_min = 0.5
			mat.scale_max = 1.4
			quad.size = Vector2(0.05, 0.05)
			draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"snow":
			particles.amount = 2600
			particles.lifetime = 8.0
			mat.gravity = Vector3(-1.6, -1.8, 0.7)
			mat.initial_velocity_min = 0.5
			mat.initial_velocity_max = 2.5
			mat.direction = Vector3(-1, -0.4, 0.3)
			mat.spread = 35.0
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.15
			mat.color = Color(0.95, 0.97, 1.0, 0.85)
			mat.scale_min = 0.5
			mat.scale_max = 1.5
			quad.size = Vector2(0.07, 0.07)
		_:
			particles.amount = 700
			particles.lifetime = 12.0
			mat.gravity = Vector3(0.4, -0.35, 0.2)
			mat.initial_velocity_max = 0.6
			mat.turbulence_influence_min = 0.05
			mat.turbulence_influence_max = 0.2
			mat.color = Color(0.3, 0.28, 0.27, 0.7)
			mat.scale_min = 0.5
			mat.scale_max = 1.6
			quad.size = Vector2(0.06, 0.06)
	quad.material = draw
	particles.process_material = mat
	particles.draw_pass_1 = quad
	particles.preprocess = particles.lifetime
	particles.position.y = height * 0.5
	particles.visibility_aabb = AABB(Vector3(-extent, -height, -extent), Vector3(extent, height, extent) * 2.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)


var _dot: GradientTexture2D

func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = gradient
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 32
		_dot.height = 32
	return _dot


# --- Props --------------------------------------------------------------------

## A prop model from assets/props, scaled so its longest side is `size` meters
## and resting on the ground. No collision: props never change gameplay.
## Returns null on a headless server.
func prop(file: String, size: float, wear := 0.6) -> Node3D:
	if not enabled:
		return null
	var holder := Node3D.new()
	var model := _instance(PROPS + file)
	if model == null:
		return holder
	holder.add_child(model)
	_fit(model, PROPS + file, size, false)
	_weather_model(model, wear, 0.3)
	return holder


## Lighting for a closed room: a flat ambient fill and a dark backdrop, so an
## interior is readable without a sun. Does nothing on a headless server.
func interior(parent: Node3D, ambient: Color, energy: float) -> void:
	if not enabled:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.name = "Interior"
	world_env.environment = env
	parent.add_child(world_env)


## A small light with no shadow, for lamps and fires.
func lamp(color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	return light


func _instance(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Look: missing model %s" % path)
		return null
	return scene.instantiate() as Node3D


## Scales `model` so it measures `target` meters (tallest side if `by_height`,
## else longest side), centers it on X and Z, and rests it on y = 0.
func _fit(model: Node3D, key: String, target: float, by_height: bool) -> void:
	var box: AABB
	if _prop_sizes.has(key):
		box = _prop_sizes[key]
	else:
		box = model_bounds(model)
		_prop_sizes[key] = box
	var measure := box.size.y if by_height else maxf(box.size.x, maxf(box.size.y, box.size.z))
	if measure <= 0.0001:
		return
	var s := target / measure
	model.scale *= s
	var center := box.get_center()
	model.position -= Vector3(center.x, box.position.y, center.z) * s


## Bounds of every mesh under `root`, in `root`'s parent space. Works before
## the node is in the tree.
static func model_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != root.get_parent():
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		var box := xform * mesh_node.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## Swaps a model's clean pack materials for worn ones that keep its colors.
func _weather_model(model: Node3D, wear: float, metal: float) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			mesh_node.set_surface_override_material(i, _worn(source, wear, metal))


func _worn(source: BaseMaterial3D, wear: float, metal: float) -> ShaderMaterial:
	var key := "%d/%.2f/%.2f" % [source.get_instance_id(), wear, metal]
	if _gear_materials.has(key):
		return _gear_materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = GEAR_SHADER
	if source.albedo_texture:
		mat.set_shader_parameter("base_tex", source.albedo_texture)
	mat.set_shader_parameter("base_color", source.albedo_color)
	if source.emission_enabled:
		mat.set_shader_parameter("emission_color", source.emission * source.emission_energy_multiplier)
	var dir := TEXTURES + "Metal063/"
	mat.set_shader_parameter("grime_albedo", load(dir + "Color.jpg"))
	mat.set_shader_parameter("grime_rough", load(dir + "Roughness.jpg"))
	mat.set_shader_parameter("wear", wear)
	mat.set_shader_parameter("metal", metal)
	_gear_materials[key] = mat
	return mat


# --- Dressing what the game spawns -----------------------------------------------

func _dress_actor(actor: Actor) -> void:
	if not is_instance_valid(actor) or actor.has_node("Skin"):
		return
	var skin := ActorSkin.new()
	skin.name = "Skin"
	skin.look = self
	skin.actor = actor
	actor.add_child(skin)


## Gives an actor a chosen appearance (see `human.gd`), now or before it is
## dressed. Cosmetic only, and safe on a headless server, where it just
## records the choice so it can be sent on to clients.
func set_appearance(actor: Actor, appearance: Variant) -> void:
	actor.set_meta("appearance", Human.sanitize(appearance))
	var old := actor.get_node_or_null("Skin")
	if not enabled or old == null:
		return
	old.name = "OldSkin"
	old.queue_free()
	_dress_actor(actor)


## The model a skin wears, with its materials made: {"model": Node3D,
## "materials": Array[ShaderMaterial]}, or {} when the art is missing.
## `appearance` only matters for skins of people; `who` picks a steady random
## look for anyone who has not chosen one.
func character(skin_name: String, appearance: Dictionary = {}, who := "") -> Dictionary:
	var def: Dictionary = SKINS.get(skin_name, SKINS[DEFAULT_SKIN])
	var model: Node3D
	var chosen := {}
	if def.has("people"):
		chosen = Human.sanitize(appearance) if not appearance.is_empty() else Human.for_name(who, def["people"])
		model = Human.build(self, chosen)
	else:
		var scenes: Array = def["scenes"]
		model = _instance(CHARACTERS + scenes[hash(who) % scenes.size()])
	if model == null:
		return {}
	for hidden: String in def.get("hide", []):
		var node := model.find_child(hidden, true, false) as Node3D
		if node:
			node.visible = false
	var materials: Array[ShaderMaterial] = []
	var tint: Color = def.get("tint", Color.WHITE)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = CHARACTER_SHADER
			if source.albedo_texture:
				mat.set_shader_parameter("base_tex", source.albedo_texture)
			mat.set_shader_parameter("base_color", source.albedo_color)
			mat.set_shader_parameter("tint", tint)
			for param: String in ["saturation", "brightness", "metal", "rough"]:
				if def.has(param):
					mat.set_shader_parameter(param, def[param])
			if source.emission_enabled:
				mat.set_shader_parameter("emission_color", source.emission * 2.5)
			if not chosen.is_empty():
				var pick := Human.color_for(chosen, mesh_node.get_meta("slot", ""), source.resource_name)
				if pick.has("color"):
					mat.set_shader_parameter("recolor", pick["color"])
					mat.set_shader_parameter("recolor_amount", 1.0)
					mat.set_shader_parameter("recolor_shading", 1.0 if pick["keep_shading"] else 0.0)
			mesh_node.set_surface_override_material(i, mat)
			materials.append(mat)
	return {"model": model, "materials": materials}


## Scales a character model to `height` meters and puts its feet at the
## origin of `holder`, the node it sits under, going by where the skeleton's
## bones are in the current pose. Mesh bounds are no use here: skinned meshes
## report their unposed size.
func stand_model(holder: Node3D, model: Node3D, height: float) -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fit(model, "skin:" + model.name, height, true)
		return
	var to_holder := holder.global_transform.affine_inverse() * skeleton.global_transform
	var low := INF
	var high := -INF
	for i in skeleton.get_bone_count():
		var y := (to_holder * skeleton.get_bone_global_pose(i).origin).y
		low = minf(low, y)
		high = maxf(high, y)
	if high - low < 0.001:
		return
	# Bones stop at the ankle and the base of the head; allow for both ends.
	var s := height / ((high - low) * 1.22)
	model.scale *= s
	model.position.y = -low * s + height * 0.06


## A valid appearance from anything a save file or a client hands over.
func clean_appearance(raw: Variant, owned: Array = []) -> Dictionary:
	return Human.player_look(raw, owned)


## The model for a held weapon, or null to keep the greybox one.
func weapon_model(weapon: Weapon) -> Node3D:
	if weapon is MeleeWeapon:
		return _melee_model(weapon)
	if not weapon is Gun:
		return null
	var file := DEFAULT_GUN
	for entry: Array in GUN_MODELS:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			file = entry[1]
			break
	var model := _instance(WEAPONS + file)
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	_fit(model, WEAPONS + file, GUN_LENGTH, false)
	_weather_model(model, 0.8 if weapon.item_id == "" else 0.5, 0.75)
	# The packs point guns along +X. Hands hold them pointing along -Z.
	holder.rotation.y = PI / 2.0
	holder.position = Vector3(0, -0.1, -0.08)
	return holder


## Melee models stand along +Y with the handle down, the way the greybox
## blade is built, so the weapon's own windup, swing and guard poses carry over.
func _melee_model(weapon: Weapon) -> Node3D:
	var pick := _melee_pick(weapon)
	var model := _instance(WEAPONS + pick[1])
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	_fit(model, WEAPONS + pick[1], pick[2], true)
	_weather_model(model, 0.75 if weapon.item_id == "" or ItemDB.has_tag(weapon.item_id, "starter") else 0.35, 0.85)
	holder.position.y = -pick[3]
	return holder


func _melee_pick(weapon: Weapon) -> Array:
	for entry: Array in MELEE_MODELS:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			return entry
	return DEFAULT_MELEE


## True when the weapon is held with both hands.
func is_two_handed(weapon: Weapon) -> bool:
	return weapon is MeleeWeapon and _melee_pick(weapon)[4]


## Fallback when a melee model is missing: greybox parts keep their shape and get metal and a hot edge.
func restyle_melee(visual: Node3D) -> void:
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var source := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D if mesh_node.mesh else null
		if source == null:
			continue
		var mat := source.duplicate() as StandardMaterial3D
		if mat.emission_enabled:
			mat.emission_energy_multiplier = 1.5
			mat.albedo_color = mat.albedo_color * 0.25
		else:
			mat.metallic = 0.9
			mat.roughness = 0.35
			mat.albedo_color = mat.albedo_color * 0.7
		mesh_node.material_override = mat


func _dress_cache(cache: LootContainer) -> void:
	if not is_instance_valid(cache) or cache.has_node("Crate"):
		return
	var marker: MeshInstance3D = null
	for child in cache.get_children():
		if child is MeshInstance3D:
			marker = child
			break
	if marker == null:
		return
	var box := marker.mesh as BoxMesh
	var size := box.size if box else Vector3(1, 0.8, 0.8)
	var crate := prop("Backpack.glb" if cache.is_bag else "Lootbox.glb", maxf(size.x, size.z) * (0.9 if cache.is_bag else 1.15), 0.7)
	crate.name = "Crate"
	cache.add_child(crate)
	# The game colors the marker mesh by the best item inside. Keep that signal
	# as a glowing band around the crate rather than a whole glowing box.
	var band := BoxMesh.new()
	band.size = Vector3(size.x * 1.08, 0.05, size.z * 1.08)
	marker.mesh = band
	marker.position.y = size.y * (0.2 if cache.is_bag else 0.55)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _dress_depot(zone: Depot) -> void:
	if not is_instance_valid(zone) or zone.has_node("Pad"):
		return
	# A landing pad under the zone and flares at its corners.
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(zone.size.x, 0.12, zone.size.z)
	mesh.material = surface("metal", {"tint": Color(0.5, 0.52, 0.5), "scale": 0.5})
	pad.mesh = mesh
	pad.position.y = -zone.size.y * 0.5 + 0.06
	zone.add_child(pad)
	var light := lamp(Color(0.25, 1.0, 0.55), 2.5, 14.0)
	light.position.y = -zone.size.y * 0.5 + 2.0
	zone.add_child(light)
	for child in zone.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node == pad:
			continue
		var source := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D
		if source == null:
			continue
		var mat := source.duplicate() as StandardMaterial3D
		mat.albedo_color.a = 0.07
		mat.emission_energy_multiplier = 1.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_node.material_override = mat


## Something on show (a home base display): a node with the meta
## "display_item" (an item id) and a "Model" child holding its greybox shape.
## Weapons get their real model, laid out the way the greybox one was;
## vehicles get the worn paint they have in a raid.
func _dress_display(display: Node3D) -> void:
	if not is_instance_valid(display):
		return
	var model := display.get_node_or_null("Model") as Node3D
	if model == null or model.has_meta("dressed"):
		return
	var id: String = display.get_meta("display_item")
	var weapon: Weapon = null
	if ItemDB.has_tag(id, "firearm"):
		weapon = Gun.new()
	elif ItemDB.has_tag(id, "melee"):
		weapon = MeleeWeapon.new()
	if weapon == null:
		# `_dress_vehicle` marks the model itself, and leaves other shapes alone.
		if ItemDB.has_tag(id, "vehicle"):
			_dress_vehicle(display)
		return
	model.set_meta("dressed", true)
	weapon.item_id = id
	var real := weapon_model(weapon)
	weapon.free()
	var grey := model.get_child(0) as Node3D if model.get_child_count() > 0 else null
	if real == null or grey == null:
		return
	# The real model sits where the hand would hold it, inside the greybox
	# shape's own turn and scale.
	var holder := Node3D.new()
	holder.transform = grey.transform
	holder.add_child(real)
	model.remove_child(grey)
	grey.queue_free()
	model.add_child(holder)


func _dress_vehicle(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle):
		return
	var model := vehicle.get_node_or_null("Model") as Node3D
	if model == null or model.has_meta("dressed"):
		return
	model.set_meta("dressed", true)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var source := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D if mesh_node.mesh else null
		if source == null:
			continue
		if source.emission_enabled:
			var lit := source.duplicate() as StandardMaterial3D
			lit.emission_energy_multiplier = 4.0
			mesh_node.material_override = lit
			var beam := SpotLight3D.new()
			beam.light_color = Color(1.0, 0.9, 0.7)
			beam.light_energy = 6.0
			beam.spot_range = 26.0
			beam.spot_angle = 28.0
			beam.shadow_enabled = false
			beam.position = mesh_node.position + Vector3(0, 0, -0.1)
			model.add_child(beam)
		else:
			mesh_node.material_override = _worn(source, 0.7, 0.7)
