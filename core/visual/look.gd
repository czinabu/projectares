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
const MELEE_SHADER := preload("res://assets/shaders/melee.gdshader")
const ActorSkin := preload("res://core/visual/actor_skin.gd")
const Human := preload("res://core/visual/human.gd")
const CHARACTER_SHADER := preload("res://assets/shaders/character.gdshader")
const Vfx := preload("res://core/visual/vfx.gd")
const RigModel := preload("res://core/visual/rig_model.gd")
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
## `idle` is a relaxed stand with the hands empty, `idle_gun` holds a gun low
## and `aim_gun` raises it to shoot from a stand (see `actor_skin.gd`).
## `stand_legs` is where the legs stand while a gun is held low.
const HUMAN_ANIMS := {"idle": "Idle_Neutral", "idle_gun": "Idle_Gun", "aim_gun": "Idle_Gun_Pointing",
	"stand_legs": "Idle_Neutral", "walk": "Walk", "run": "Run", "death": "Death",
	"idle_melee": "Idle_Sword", "attack": "Sword_Slash", "move_gun": "Run_Shoot",
	"run_back": "Run_Back", "run_left": "Run_Left", "run_right": "Run_Right"}
const HUMAN_ARM := ["UpperArm.R", "LowerArm.R", "Wrist.R"]
const HUMAN_OFF_ARM := ["UpperArm.L", "LowerArm.L", "Wrist.L"]
const HUMAN_FEET := ["Foot.L", "Foot.R"]
const HUMAN_SPINE := ["Abdomen", "Torso", "Chest"]
## Thigh, shin and foot of the leg that reaches forward in a slide, and of the
## one that folds under.
const HUMAN_LEAD_LEG := ["UpperLeg.L", "LowerLeg.L", "Foot.L"]
const HUMAN_TRAIL_LEG := ["UpperLeg.R", "LowerLeg.R", "Foot.R"]
const SKINS := {
	"raider": {
		"people": {"m": ["Swat", "Spacesuit", "Adventurer"], "f": ["Soldier", "SciFi", "Adventurer"]},
		"height": 1.8, "tint": Color(0.8, 0.82, 0.86), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
		"saturation": 0.75, "brightness": 0.85, "metal": 0.0, "rough": 0.85,
		"anims": HUMAN_ANIMS,
	},
	"scavenger": {
		"people": {"m": ["Punk", "Casual_Hoodie", "Casual_2", "Farmer", "Beach"], "f": ["Punk", "Worker", "Casual", "Medieval"]},
		"height": 1.76, "tint": Color(0.86, 0.76, 0.68), "grip_bone": "Middle1.R", "arm": HUMAN_ARM, "off_arm": HUMAN_OFF_ARM,
		"spine": HUMAN_SPINE, "neck": "Neck", "lead_leg": HUMAN_LEAD_LEG, "trail_leg": HUMAN_TRAIL_LEG,
		"back_bone": "Chest", "hip_bone": "Hips", "feet": HUMAN_FEET,
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

## Gun models picked by item tag, first match wins. Tags, never ids. An
## optional third value is the length in meters (default `GUN_LENGTH`).
const GUN_MODELS := [
	["hand_cannon", "Pistol_1.glb", 0.32],
	["machine_pistol", "SMG_2.glb", 0.34],
	["sidearm", "Pistol_1.glb", 0.24],
	["smg", "SMG_1.glb"],
	["marksman", "Sniper_2.glb"],
	["shotgun", "Shotgun_1.glb"],
	["starter", "AR_5.glb"],
	["rifle", "AR_2.glb"],
]
const DEFAULT_GUN := "AR_3.glb"
## Where attachments sit on each gun model. The optic sits on top of the gun
## and the muzzle device on the end of the barrel, both found from the mesh;
## this gives how far along the gun the optic goes (0 at the stock, 1 at the
## muzzle), and the grip and magazine mounts as [along, up from the bottom].
const GUN_MOUNTS := {
	"AR_5.glb": {"optic": 0.55, "grip": [0.82, 0.32], "magazine": [0.36, 0.3]},
	"AR_2.glb": {"optic": 0.5, "grip": [0.82, 0.62], "magazine": [0.6, 0.5]},
	"SMG_1.glb": {"optic": 0.62, "grip": [0.66, 0.62], "magazine": [0.84, 0.55]},
	"Sniper_2.glb": {"optic": 0.5, "grip": [0.72, 0.4], "magazine": [0.45, 0.32]},
	"Shotgun_1.glb": {"optic": 0.3, "grip": [0.62, 0.4], "magazine": [0.36, 0.45]},
	"AR_3.glb": {"optic": 0.5, "grip": [0.8, 0.5], "magazine": [0.55, 0.45]},
}
## Energy colour for a gun's glowing parts, picked by item tag, first match
## wins. The warm (wood and leather) parts of the pack's models become glowing
## cells and coils in this colour, and a glowing emitter ring sits on the muzzle.
const GUN_GLOW := [
	["hand_cannon", Color(0.8, 0.35, 1.0)],
	["machine_pistol", Color(1.0, 0.55, 0.15)],
	["sidearm", Color(0.3, 0.85, 1.0)],
	# Primaries, matching the cyan lit details on their attachments.
	["smg", Color(1.0, 0.55, 0.15)],
	["marksman", Color(0.8, 0.35, 1.0)],
	["shotgun", Color(1.0, 0.3, 0.25)],
	["rifle", Color(0.25, 0.9, 1.0)],
]
## Melee models picked by item tag, first match wins: file, length in meters,
## how far up from the pommel the hand grips it, and how it folds away when holstered (see `set_extend`): "blade" draws the
## blade into the hilt, "telescope" slides the shaft into itself, "" keeps
## its shape. No file means the model is built in code (see `_spear_model`).
const MELEE_MODELS := [
	["hammer", "Hammer.glb", 1.15, 0.3, ""],
	["knife", "Knife.glb", 0.5, 0.1, "blade"],
	["axe", "Axe.glb", 0.85, 0.12, ""],
	["spear", "", 2.1, 0.75, "telescope"],
	["starter", "Sword.glb", 1.15, 0.13, "blade"],
	["blade", "Katana.glb", 1.2, 0.14, "blade"],
]
const DEFAULT_MELEE := ["", "Sword.glb", 1.15, 0.13, "blade"]
const GUN_LENGTH := 0.72

## False on a headless server: nothing is dressed and no art is loaded.
var enabled := DisplayServer.get_name() != "headless"

var _materials := {}
var _noise: NoiseTexture2D
var _gear_materials := {}
## Mesh surface and placement -> how far up the model it runs (`_surface_span`).
var _spans := {}
## A foldable melee material's id -> its folded copy (see `set_extend`).
var _folded := {}
var _prop_sizes := {}
## Gun model file -> attachment slot -> mount point (see `mount_attachments`).
var _gun_mounts := {}
## Map props are drawn out to this many metres for each metre of their size
## (`_limit_draw_distance`), never nearer than `draw_distance_min`; one that
## would reach `draw_distance_cap` is drawn as far as the camera sees.
var draw_distance_per_metre := 70.0
var draw_distance_min := 40.0
var draw_distance_cap := 380.0


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
	elif node.name == "Map" and node.get_parent() is Raid:
		_limit_draw_distance.call_deferred(node)


## Small things in a map stop being drawn once they are too far away to
## make out: each mesh fades out at `draw_distance_per_metre` times its
## size, so a crate goes long before a building does. Big open maps draw
## hundreds of small props (and their shadows) otherwise. A mesh that
## already has a visibility range keeps it.
func _limit_draw_distance(map: Node3D) -> void:
	if not is_instance_valid(map):
		return
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.visibility_range_end > 0.0:
			continue
		var size := (mesh.global_transform * mesh.get_aabb()).size
		var reach := maxf(size.x, maxf(size.y, size.z)) * draw_distance_per_metre
		if reach >= draw_distance_cap:
			continue
		mesh.visibility_range_end = maxf(reach, draw_distance_min)
		mesh.visibility_range_end_margin = mesh.visibility_range_end * 0.15
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# --- Surfaces -----------------------------------------------------------------

## A world-space PBR material. `opts` may set: tint (Color), scale (float),
## blend (surface kind to mix in), blend_amount, wetness, snow, snow_patchy,
## grime, saturation, metal (overrides the kind's metalness),
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
		sm.set_shader_parameter("metal", opts.get("metal", def.get("metal", 0.0)))
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


## Power weapons are sci-fi through and through: dark armoured bodies
## with glowing coils, cells and vents in the weapon's own colour
## (`Gun.tracer_color`). Built from shapes, picked by tag, pointing along -Z.
func _power_model(gun: Gun) -> Node3D:
	var glow: Color = gun.tracer_color
	var body := _power_mat(Color(0.24, 0.26, 0.31), 0.45, 0.45)
	var trim := _power_mat(Color(0.5, 0.53, 0.58), 0.6, 0.35)
	var lit := _power_mat(glow, 0.0, 0.4, glow, 1.4)
	var holder := Node3D.new()
	holder.name = "Model"
	var tags: Array = ItemDB.get_item(gun.item_id).get("tags", [])
	if "railgun" in tags:
		# Two long rails with charge coils between them.
		_power_box(holder, Vector3(0.09, 0.12, 0.5), Vector3(0, -0.02, 0.0), body)
		for side in [-1.0, 1.0]:
			_power_box(holder, Vector3(0.025, 0.05, 0.85), Vector3(0.045 * side, 0.02, -0.55), trim)
		for i in 5:
			_power_box(holder, Vector3(0.07, 0.07, 0.03), Vector3(0, 0.02, -0.2 - i * 0.15), lit)
		_power_grip(holder, Vector3(0.05, 0.14, 0.08), Vector3(0, -0.14, 0.08), body, Vector3(0, -0.075, -0.2))
		_power_box(holder, Vector3(0.1, 0.05, 0.12), Vector3(0, 0.1, -0.05), lit)
	elif "launcher" in tags:
		# A wide plasma tube on the shoulder, glowing at both ends.
		_power_cyl(holder, 0.085, 0.85, Vector3(0, 0.02, -0.25), body)
		_power_cyl(holder, 0.095, 0.08, Vector3(0, 0.02, -0.66), lit)
		_power_cyl(holder, 0.095, 0.06, Vector3(0, 0.02, 0.17), trim)
		_power_box(holder, Vector3(0.04, 0.03, 0.5), Vector3(0, 0.11, -0.25), lit)
		_power_grip(holder, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.12, -0.05), body, Vector3(0, -0.06, -0.38))
		_power_box(holder, Vector3(0.12, 0.08, 0.12), Vector3(0.07, 0.05, -0.05), trim)
	elif "grenade_launcher" in tags:
		# Short barrel over a fat glowing drum of arc charges.
		_power_box(holder, Vector3(0.08, 0.1, 0.45), Vector3(0, 0.0, -0.15), body)
		_power_cyl(holder, 0.05, 0.35, Vector3(0, 0.05, -0.45), trim)
		var drum := _power_cyl(holder, 0.1, 0.12, Vector3(0, -0.06, -0.12), lit)
		drum.rotation = Vector3(0, 0, PI / 2.0)
		_power_grip(holder, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.13, 0.08), body, Vector3(0, -0.045, -0.3))
		_power_box(holder, Vector3(0.09, 0.02, 0.3), Vector3(0, 0.07, -0.15), lit)
	else:
		# Rotary pulse cannon: a ring of barrels around a glowing core.
		_power_box(holder, Vector3(0.16, 0.16, 0.36), Vector3(0, 0, 0.0), body)
		for i in 6:
			var a := TAU * i / 6.0
			_power_cyl(holder, 0.022, 0.7, Vector3(cos(a) * 0.065, sin(a) * 0.065, -0.5), trim)
		_power_cyl(holder, 0.03, 0.72, Vector3(0, 0, -0.5), lit)
		_power_cyl(holder, 0.11, 0.05, Vector3(0, 0, -0.25), lit)
		_power_box(holder, Vector3(0.18, 0.06, 0.2), Vector3(0, 0.12, 0.05), trim)
		_power_grip(holder, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.14, 0.1), body, Vector3(0, -0.085, -0.12))
	return holder


## A power weapon's hand grip, a box hanging under it, and the "Grip" and
## "Trigger" markers where the gun hand closes on it (see `_measure_hold`),
## and the "ForeGrip" marker at `fore`, where the off hand holds it.
func _power_grip(holder: Node3D, size: Vector3, at: Vector3, mat: Material, fore: Vector3) -> void:
	_power_box(holder, size, at, mat)
	var support := Marker3D.new()
	support.name = "ForeGrip"
	support.position = fore
	holder.add_child(support)
	var hold := Marker3D.new()
	hold.name = "Grip"
	hold.position = at + Vector3(0.0, size.y * 0.5 - 0.035, 0.0)
	hold.set_meta("up", Vector3.UP)
	holder.add_child(hold)
	var trigger := Marker3D.new()
	trigger.name = "Trigger"
	trigger.position = hold.position + Vector3(0.0, 0.0, -size.z * 0.5 - 0.015)
	holder.add_child(trigger)


func _power_mat(color: Color, metal: float, rough: float, glow := Color.BLACK,
		glow_energy := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	if glow_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = glow_energy
	return mat


func _power_box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


## A cylinder lying along -Z (the barrel direction).
func _power_cyl(parent: Node3D, radius: float, length: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.rotation = Vector3(PI / 2.0, 0, 0)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


## The model for a held weapon, or null to keep the greybox one.
func weapon_model(weapon: Weapon) -> Node3D:
	if weapon is MeleeWeapon:
		return _melee_model(weapon)
	if not weapon is Gun:
		return null
	if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, "power"):
		return _power_model(weapon as Gun)
	var file := DEFAULT_GUN
	var length := GUN_LENGTH
	for entry: Array in GUN_MODELS:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			file = entry[1]
			length = entry[2] if entry.size() > 2 else GUN_LENGTH
			break
	var model := _instance(WEAPONS + file)
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	_fit(model, WEAPONS + file, length, false)
	for entry: Array in GUN_GLOW:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			_energize(model, holder, entry[1])
			break
	_weather_model(model, 0.8 if weapon.item_id == "" else 0.5, 0.75)
	# The packs point guns along +X. Hands hold them pointing along -Z.
	holder.rotation.y = PI / 2.0
	holder.position = Vector3(0, -0.1, -0.08)
	holder.set_meta("gun_file", file)
	holder.set_meta("gun_length", length)
	return holder


## Moves a gun's attachments (the "Attachments" child of `visual`, see
## `Gun.build_attachment`) from the greybox mounts onto its real model (the
## "Model" child that `weapon_model` built). Safe to call more than once.
func mount_attachments(visual: Node3D) -> void:
	var fitted := visual.get_node_or_null("Attachments") as Node3D
	var model := visual.get_node_or_null("Model") as Node3D
	if model == null or not model.has_meta("gun_file"):
		return
	var file: String = model.get_meta("gun_file")
	# One model is used at more than one size (two pistols), so it is
	# measured once per size.
	var key := "%s@%.3f" % [file, float(model.get_meta("gun_length", GUN_LENGTH))]
	if not _gun_mounts.has(key):
		_gun_mounts[key] = _measure_mounts(model, GUN_MOUNTS.get(file, GUN_MOUNTS[DEFAULT_GUN]))
	var mounts: Dictionary = _gun_mounts[key]
	if fitted != null:
		for part in fitted.get_children():
			if part is Node3D and mounts.has(part.name):
				(part as Node3D).position = mounts[part.name]
				part.set_meta("mounted", true)
	_place_muzzle(visual, fitted, mounts)
	if fitted == null:
		return
	# An optic raised to see over the front sight stands on a riser.
	var optic := fitted.get_node_or_null("optic") as Node3D
	if optic and mounts.has("rail") and not optic.has_node("Riser"):
		var rise: float = optic.position.y - float(mounts["rail"])
		if rise > 0.003:
			var riser := Weapon.make_part(Vector3(0.026, rise, 0.07), Vector3(0, -rise * 0.5, 0), Color(0.1, 0.11, 0.13))
			riser.name = "Riser"
			optic.add_child(riser)


## Puts a "Muzzle" marker on the gun's visual where shots leave it: the front
## of the barrel, or of a fitted muzzle device. Muzzle flashes and tracers
## start there in both views (`Gun.muzzle_point`). A "ForeGrip" marker shows
## where the off hand holds it, and an "IronSight" marker where the eye looks
## along it.
func _place_muzzle(visual: Node3D, fitted: Node3D, mounts: Dictionary) -> void:
	if not mounts.has("muzzle"):
		return
	var at: Vector3 = mounts["muzzle"]
	var device := fitted.get_node_or_null("muzzle") as Node3D if fitted != null else null
	if device != null:
		var box := model_bounds(device)
		if box.size != Vector3.ZERO:
			at = fitted.transform * Vector3(box.get_center().x, box.get_center().y, box.position.z)
	_marker(visual, "Muzzle").position = at
	# The rear of the plain sights, where an eye looks along the gun when
	# aiming without an optic (`ActionPose.sight_local`): just over whatever
	# stands highest along the top, a little behind the optic's spot.
	if mounts.has("optic"):
		_marker(visual, "IronSight").position = (mounts["optic"] as Vector3) + Vector3(0.0, 0.012, 0.06)
	# Where the off hand holds the fore end, first person (the fore grip
	# mount, or a fitted grip).
	if mounts.has("grip"):
		var grip := fitted.get_node_or_null("grip") as Node3D if fitted != null else null
		_marker(visual, "ForeGrip").position = grip.position if grip != null else mounts.get("fore", mounts["grip"])
	# Where the gun hand closes on the pistol grip and which way the grip
	# runs, and the trigger, found from the model (`_measure_hold`).
	if mounts.has("hold"):
		var hold := _marker(visual, "Grip")
		hold.position = mounts["hold"]
		hold.set_meta("up", mounts["hold_up"])
		_marker(visual, "Trigger").position = mounts["trigger"]


func _marker(visual: Node3D, marker_name: String) -> Marker3D:
	var marker := visual.get_node_or_null(marker_name) as Marker3D
	if marker == null:
		marker = Marker3D.new()
		marker.name = marker_name
		visual.add_child(marker)
	return marker


## Finds the attachment mounts on a gun model, in the space of its parent.
func _measure_mounts(model: Node3D, along: Dictionary) -> Dictionary:
	var points := PackedVector3Array()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != model.get_parent():
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		for v in mesh_node.mesh.get_faces():
			points.append(xform * v)
	if points.is_empty():
		return {}
	var low := points[0]
	var high := points[0]
	for p in points:
		low = low.min(p)
		high = high.max(p)
	var length := high.z - low.z
	var height := high.y - low.y
	var mid_x := (low.x + high.x) * 0.5
	# The optic sits on whatever is highest around its spot.
	var optic_z := high.z - float(along.get("optic", 0.5)) * length
	var top := -INF
	# Sights further forward (a front post) must not block the optic's view.
	var ahead := -INF
	# The muzzle device goes on the middle of whatever is at the very front.
	var front_low := INF
	var front_high := -INF
	for p in points:
		if absf(p.z - optic_z) < length * 0.08:
			top = maxf(top, p.y)
		elif p.z < optic_z:
			ahead = maxf(ahead, p.y)
		if p.z < low.z + length * 0.03:
			front_low = minf(front_low, p.y)
			front_high = maxf(front_high, p.y)
	var out := {
		"optic": Vector3(mid_x, maxf(top if top > -INF else high.y, ahead + 0.004), optic_z),
		"rail": top if top > -INF else high.y,
		"muzzle": Vector3(mid_x, (front_low + front_high) * 0.5 if front_high > -INF else low.y + height * 0.7, low.z),
	}
	for slot: String in ["grip", "magazine"]:
		var spot: Array = along.get(slot, [0.6, 0.4])
		out[slot] = Vector3(mid_x, low.y + float(spot[1]) * height, high.z - float(spot[0]) * length)
	_measure_hold(points, low, high, out)
	return out


## Where the hands go on a gun model, read off its side outline (the mesh
## seen from the side, in squares a 160th of its length): the trigger guard is the
## hole low in the outline, the pistol grip the solid just behind it running
## down, and the fore end the underside some way ahead of the guard. Adds to
## `out` (all in the gun's visual space) "hold" (the grip's middle, level
## with the trigger, where the fist closes), "hold_up" (up along the grip),
## "trigger", and "fore" (where the off hand cups the fore end). Adds none
## when the outline has no trigger guard.
## How far ahead of the trigger the off hand reaches along a long gun, and
## how far under the fore end's underside the middle of its fist is.
const FORE_REACH := 0.26
const FORE_CUP := 0.015


func _measure_hold(points: PackedVector3Array, low: Vector3, high: Vector3, out: Dictionary) -> void:
	var size_cell := maxf((high.z - low.z) / 160.0, 0.0015)
	var nz := int((high.z - low.z) / size_cell) + 2
	var ny := int((high.y - low.y) / size_cell) + 2
	var cells := func(metres: float) -> int:
		return maxi(int(round(metres / size_cell)), 1)
	var solid := PackedByteArray()
	solid.resize(nz * ny)
	var cell := func(q: Vector3) -> Vector2:
		return Vector2((q.z - low.z) / size_cell, (q.y - low.y) / size_cell)
	for i in range(0, points.size() - 2, 3):
		var a: Vector2 = cell.call(points[i])
		var b: Vector2 = cell.call(points[i + 1])
		var c: Vector2 = cell.call(points[i + 2])
		var area := (b - a).cross(c - a)
		for corner: Vector2 in [a, b, c]:
			solid[clampi(int(corner.x), 0, nz - 1) * ny + clampi(int(corner.y), 0, ny - 1)] = 1
		if absf(area) < 0.0001:
			continue
		for z in range(maxi(int(minf(a.x, minf(b.x, c.x))), 0), mini(int(maxf(a.x, maxf(b.x, c.x))) + 1, nz)):
			for y in range(maxi(int(minf(a.y, minf(b.y, c.y))), 0), mini(int(maxf(a.y, maxf(b.y, c.y))) + 1, ny)):
				var q := Vector2(z + 0.5, y + 0.5)
				var u := (b - q).cross(c - q) / area
				var v := (c - q).cross(a - q) / area
				if u >= -0.02 and v >= -0.02 and 1.0 - u - v >= -0.02:
					solid[z * ny + y] = 1
	# Everything empty that the outside cannot reach is a hole.
	var mark := PackedInt32Array()
	mark.resize(nz * ny)
	var todo: Array[int] = []
	for z in nz:
		todo.append(z * ny)
		todo.append(z * ny + ny - 1)
	for y in ny:
		todo.append(y)
		todo.append((nz - 1) * ny + y)
	_flood(solid, mark, todo, nz, ny, -1)
	var holes: Array[Dictionary] = []
	for start in nz * ny:
		if solid[start] == 0 and mark[start] == 0:
			holes.append(_flood(solid, mark, [start], nz, ny, holes.size() + 1))
	# The guard: the front-most finger-sized hole low in the outline with a
	# grip behind it (on a bullpup the thumbhole behind the grip is a hole
	# too, and a bigger one).
	holes.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p["front"] < q["front"])
	var mid_x: float = (out["muzzle"] as Vector3).x
	var to_space := func(z: float, yy: float) -> Vector3:
		return Vector3(mid_x, low.y + (yy + 0.5) * size_cell, low.z + (z + 0.5) * size_cell)
	var bore := int(((out["muzzle"] as Vector3).y - low.y) / size_cell)
	for guard in holes:
		var size: Vector2i = guard["size"]
		if size.x < cells.call(0.009) or size.y < cells.call(0.008) or size.x > cells.call(0.1) \
				or size.y > cells.call(0.07) or float(guard["top"]) > ny * 0.75:
			continue
		var grip := _trace_grip(solid, guard, nz, ny, cells)
		if grip.is_empty():
			continue
		var level: float = float(guard["top"] + guard["bottom"]) * 0.5
		# The fist closes behind the guard, never in it.
		var hold_z := maxf(grip["k"] * level + grip["m"], float(guard["back"]) + cells.call(0.012))
		out["hold"] = to_space.call(hold_z, level)
		out["hold_up"] = Vector3(0.0, 1.0, grip["k"]).normalized()
		out["trigger"] = to_space.call(float(guard["front"] + guard["back"]) * 0.5, level)
		# The fore end: the underside FORE_REACH ahead of the trigger, or
		# the front of the gun where it is shorter, the palm under the
		# barrel's own part of the outline (not a magazine hanging below).
		var fore_z := maxi(int(guard["front"]) - cells.call(FORE_REACH), cells.call(0.03))
		var under := clampi(bore, 0, ny - 1)
		# Down from the bore to the barrel or fore end's top, then to its
		# underside.
		while under > 0 and solid[fore_z * ny + under] == 0 and bore - under < cells.call(0.04):
			under -= 1
		if solid[fore_z * ny + under] == 1:
			while under > 0 and solid[fore_z * ny + under - 1] == 1 and bore - under < cells.call(0.08):
				under -= 1
			# The palm cups the underside, the fist's middle just under it.
			out["fore"] = to_space.call(fore_z, under - 0.5) + Vector3(0.0, -FORE_CUP, 0.0)
		return


## The pistol grip behind a trigger guard (a hole in the outline, see
## `_flood`), read row by row from the guard's top down: the line down its
## middle as z = k * y + m in cells, or empty where nothing runs down. Where
## the solid behind the guard runs on back (a stock's wrist, as on a pump
## gun), the hand closes just behind the guard and the grip leans back
## along the wrist's underside.
func _trace_grip(solid: PackedByteArray, guard: Dictionary, nz: int, ny: int, cells: Callable) -> Dictionary:
	var mids := PackedVector2Array()
	var unders := PackedVector2Array()
	var widest: int = cells.call(0.055)
	var from: int = int(guard["back"]) - cells.call(0.01)
	var last_back := -1
	var long := false
	for y in range(int(guard["top"]), maxi(int(guard["top"]) - cells.call(0.13), -1), -1):
		var z := from
		while z < nz - 1 and z <= from + cells.call(0.05) and solid[z * ny + y] == 0:
			z += 1
		if solid[z * ny + y] == 0:
			break
		var front := z
		while z < nz and solid[z * ny + y] == 1:
			z += 1
		if z - front > widest:
			long = true
			if y <= int(guard["bottom"]):
				unders.append(Vector2(front, y))
			from = front - cells.call(0.01)
			continue
		# Where the back edge jumps the grip has ended (or run into a stock).
		if last_back >= 0 and absi(z - last_back) > cells.call(0.02):
			break
		mids.append(Vector2((front + z) * 0.5, y))
		from = front - cells.call(0.01)
		last_back = z
	if long and mids.size() < 4 or mids.size() < 2:
		# A stock's wrist: the hand behind the guard, the grip leaning back
		# as the front of the solid behind the guard does below it.
		var k := -1.0
		if unders.size() >= 2:
			k = minf((unders[unders.size() - 1].x - unders[0].x) / minf(unders[unders.size() - 1].y - unders[0].y, -1.0), -0.3)
		var back: float = float(guard["back"]) + cells.call(0.022)
		return {"k": k, "m": back - k * float(guard["top"] + guard["bottom"]) * 0.5}
	# A line through the middles, by least squares.
	var sy := 0.0
	var sz := 0.0
	var syy := 0.0
	var syz := 0.0
	for r in mids:
		sy += r.y
		sz += r.x
		syy += r.y * r.y
		syz += r.y * r.x
	var count := float(mids.size())
	var k := (count * syz - sy * sz) / maxf(count * syy - sy * sy, 0.0001)
	# Grips rake back, from upright to about 40 degrees.
	k = clampf(k, -0.85, 0.0)
	return {"k": k, "m": (sz - k * sy) / count}


## Fills the connected empty cells from `todo` with `id` and returns the
## region's extent in cells.
func _flood(solid: PackedByteArray, mark: PackedInt32Array, todo: Array, nz: int, ny: int, id: int) -> Dictionary:
	var region := {"front": nz, "back": -1, "top": -1, "bottom": ny, "cells": 0}
	while not todo.is_empty():
		var at: int = todo.pop_back()
		if solid[at] == 1 or mark[at] != 0:
			continue
		mark[at] = id
		var z := at / ny
		var y := at % ny
		region["cells"] += 1
		region["front"] = mini(region["front"], z)
		region["back"] = maxi(region["back"], z)
		region["bottom"] = mini(region["bottom"], y)
		region["top"] = maxi(region["top"], y)
		if z > 0: todo.append(at - ny)
		if z < nz - 1: todo.append(at + ny)
		if y > 0: todo.append(at - 1)
		if y < ny - 1: todo.append(at + 1)
	region["size"] = Vector2i(region["back"] - region["front"] + 1, region["top"] - region["bottom"] + 1)
	return region


## Gives a gun model a sci-fi energy look in `glow`: warm parts become glowing
## cells, the dark body gets a cool gunmetal sheen, and an emitter ring sits on
## the muzzle. `holder` is the model's parent; guns point along +X in it.
func _energize(model: Node3D, holder: Node3D, glow: Color) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var c := source.albedo_color
			var mat := source.duplicate() as BaseMaterial3D
			if c.r - c.b > 0.08 and c.r > 0.15:
				mat.albedo_color = glow.darkened(0.3)
				mat.emission_enabled = true
				mat.emission = glow
				mat.emission_energy_multiplier = 2.2
			else:
				mat.albedo_color = c.lerp(Color(0.32, 0.36, 0.42), 0.35)
			mesh_node.set_surface_override_material(i, mat)
	var box := model_bounds(model)
	var ring := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	var radius := box.size.y * 0.07
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = box.size.x * 0.035
	var mat := StandardMaterial3D.new()
	mat.albedo_color = glow
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = 1.6
	tube.material = mat
	ring.mesh = tube
	ring.name = "Emitter"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.rotation.z = PI / 2.0
	ring.position = Vector3(box.end.x, box.position.y + box.size.y * 0.78, box.get_center().z)
	holder.add_child(ring)


## Melee models stand along +Y with the handle down, the way the greybox
## blade is built, so the weapon's own windup, swing and guard poses carry over.
func _melee_model(weapon: Weapon) -> Node3D:
	var pick := _melee_pick(weapon)
	if pick[1] == "":
		var spear := _spear_model(pick[2], pick[3], energy_color(weapon.item_id), energy_strength(weapon.item_id))
		# Its grip is wrapped where the weapon hand goes, so it keeps that spot.
		_fit_hands(spear, "spear@%.2f" % pick[2], is_two_handed(weapon), pick[3])
		return spear
	var model := _instance(WEAPONS + pick[1])
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	_fit(model, WEAPONS + pick[1], pick[2], true)
	_tech_melee(holder, energy_color(weapon.item_id), energy_strength(weapon.item_id),
			0.7 if weapon.item_id == "" or ItemDB.has_tag(weapon.item_id, "starter") else 0.3,
			{"mode": pick[4]})
	holder.position.y = -pick[3]
	_fit_hands(holder, "%s@%.2f" % [pick[1], pick[2]], is_two_handed(weapon))
	return holder


## Where the hands go on a melee model, read off its shape: sliced along its
## length (pommel at the bottom), the handle runs up to the first slice
## clearly wider than the rest below (a guard or a head). The weapon hand
## closes just under the guard on a short handle and near the end of a long
## haft; the holder
## moves so that spot, on the handle's middle line, is the visual's origin
## (where the fist is). A two-handed weapon also gets an "off_grip" meta:
## where the off hand closes, from the weapon hand along the handle: a
## hand's width below on a short handle (a long sword's two-hand grip), up
## the haft on a long one, which is carried across the body
## (`WeaponArm.carry_point`) with the weapon hand low near its end. A
## model with no handle found keeps `holder`'s place. `key` caches the
## measuring per model.
const HAND_WIDTH := 0.095
## How far up a long haft the off hand closes above the weapon hand.
const HAND_CARRY := 0.3
## How much wider than the handle below it a guard or head is.
const HANDLE_GUARD := 1.15
var _handles := {}


func _fit_hands(holder: Node3D, key: String, two_handed: bool, fixed_grip := -1.0) -> void:
	var at := holder.position
	holder.position = Vector3.ZERO
	if not _handles.has(key):
		_handles[key] = _measure_handle(holder)
	var handle: Dictionary = _handles[key]
	holder.position = at
	if handle.is_empty():
		return
	var bottom: float = handle["bottom"]
	var top: float = handle["top"]
	var span := top - bottom
	var grip := top - HAND_WIDTH * 0.55
	if span >= 0.35:
		grip = bottom + HAND_WIDTH
	if fixed_grip >= 0.0:
		grip = fixed_grip
	grip = clampf(grip, bottom + HAND_WIDTH * 0.4, maxf(top - HAND_WIDTH * 0.4, bottom + HAND_WIDTH * 0.4))
	var centre: Vector2 = handle["centre"]
	holder.position = Vector3(-centre.x, -grip, -centre.y)
	if two_handed:
		if span < 0.35:
			holder.set_meta("off_grip", -maxf(minf(HAND_WIDTH, grip - bottom - HAND_WIDTH * 0.3), HAND_WIDTH * 0.8))
		else:
			holder.set_meta("off_grip", maxf(minf(HAND_CARRY, top - grip - HAND_WIDTH * 0.5), HAND_WIDTH * 0.8))


## A melee model's handle in its holder's space: {"bottom", "top"} up its
## length and "centre" (x, z) across it, or empty when nothing marks where
## it ends (a knife all one width keeps its table grip).
func _measure_handle(holder: Node3D) -> Dictionary:
	var points := PackedVector3Array()
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != holder:
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		for v in mesh_node.mesh.get_faces():
			points.append(xform * v)
	if points.size() < 3:
		return {}
	var low := points[0]
	var high := points[0]
	for q in points:
		low = low.min(q)
		high = high.max(q)
	var slice := maxf((high.y - low.y) / 120.0, 0.004)
	var count := int((high.y - low.y) / slice) + 1
	var lows: Array[Vector3] = []
	var highs: Array[Vector3] = []
	for i in count:
		lows.append(Vector3.INF)
		highs.append(-Vector3.INF)
	# Every triangle, sampled finer than a slice, so long faces count too.
	for i in range(0, points.size() - 2, 3):
		var a := points[i]
		var b := points[i + 1]
		var c := points[i + 2]
		var steps := mini(int(maxf(absf(a.y - b.y), maxf(absf(b.y - c.y), absf(a.y - c.y))) / (slice * 0.5)) + 1, 400)
		for u in steps + 1:
			for v in steps + 1 - u:
				var q := a + (b - a) * (float(u) / steps) + (c - a) * (float(v) / steps)
				var row := clampi(int((q.y - low.y) / slice), 0, count - 1)
				lows[row] = lows[row].min(q)
				highs[row] = highs[row].max(q)
	# The handle runs up from the bottom to the guard, cross-guard or head:
	# the first slice clearly wider than anything below it (a pommel too).
	var widest := 0.0
	var guard := -1
	for row in count:
		if lows[row] == Vector3.INF:
			continue
		var size := highs[row] - lows[row]
		var width := maxf(size.x, size.z)
		if row * slice > HAND_WIDTH and width > widest * HANDLE_GUARD:
			guard = row
			break
		widest = maxf(widest, width)
	if guard < 0:
		return {}
	var best := Vector2i(0, guard)
	var centre := Vector2.ZERO
	for row in range(best.x, best.y):
		centre += Vector2(lows[row].x + highs[row].x, lows[row].z + highs[row].z) * 0.5
	centre /= best.y - best.x
	return {"bottom": low.y + best.x * slice, "top": low.y + best.y * slice, "centre": centre}


## The glow a melee weapon's energy edge takes: its rarity color, with plain
## Common gear in the cyan of the scrap kit.
func energy_color(item_id: String) -> Color:
	var rarity := ItemDB.item_rarity(item_id) if item_id != "" else ItemDB.Rarity.COMMON
	if rarity == ItemDB.Rarity.COMMON:
		return Color(0.3, 0.85, 1.0)
	return ItemDB.RARITY_COLORS[rarity]


## Rarer weapons burn brighter.
func energy_strength(item_id: String) -> float:
	return 1.0 + 0.2 * (ItemDB.item_rarity(item_id) if item_id != "" else 0)


## Restyles a melee model as tech (see assets/shaders/melee.gdshader): light
## parts become alloy with an energy edge in `glow` (`strength` times as
## bright), dark parts black polymer with glowing seams. `root` is the holder,
## so seams are spaced in meters. `fold` says how the model folds away when
## holstered: {"mode": "blade"} finds the blade (the parts that start highest
## up the model) and draws it into the hilt; {"hilt", "slide", "keep"} in
## meters up the model slides `slide` meters above `hilt` down to `keep` of
## its length, and carries everything above along with it.
func _tech_melee(root: Node3D, glow: Color, strength: float, wear: float, fold := {}) -> void:
	var surfaces: Array[Dictionary] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != root:
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var span := _surface_span(mesh_node.mesh, i, xform)
			surfaces.append({"node": mesh_node, "index": i, "source": source, "xform": xform,
				"low": span.x, "high": span.y})
	# Where the model folds, in meters up the model, and which parts move.
	var hilt := INF
	var slide := 0.0
	var keep := 1.0
	var mode: String = fold.get("mode", "")
	if mode == "blade" and not surfaces.is_empty():
		var top: Dictionary = surfaces[0]
		for s in surfaces:
			if s["high"] > top["high"]:
				top = s
		var length: float = top["high"]
		var start: float = top["low"]
		hilt = start
		for s in surfaces:
			if s["low"] >= start - 0.1 * length:
				hilt = minf(hilt, s["low"])
		slide = length
		keep = 0.0
	elif fold.has("hilt"):
		hilt = fold["hilt"]
		slide = fold["slide"]
		keep = fold["keep"]
	for s in surfaces:
		var mesh_node: MeshInstance3D = s["node"]
		var xform: Transform3D = s["xform"]
		var retract := {}
		# A blade folds only the parts that start at the hilt, so a guard
		# or pommel cast in one piece with the hilt keeps its shape.
		if hilt < INF and (mode != "blade" or s["low"] >= hilt - 0.001):
			var inv := xform.affine_inverse()
			var axis := inv.basis * Vector3.UP
			retract = {"origin": inv * Vector3(0, hilt, 0), "axis": axis.normalized(),
				"slide": slide * axis.length(), "keep": keep}
		mesh_node.set_surface_override_material(s["index"],
				_tech_material(s["source"], glow, strength, wear, xform.basis.get_scale().y,
					mesh_node.mesh.get_aabb(), retract))
	if hilt < INF:
		root.set_meta("fold", {"hilt": hilt, "slide": slide, "keep": keep})


## How high up a melee model a point `y` meters from its pommel sits once
## folded away (`fold` as `_tech_melee` stores it on the holder).
static func fold_height(y: float, fold: Dictionary) -> float:
	var d: float = y - fold["hilt"]
	if d <= 0.0:
		return y
	var slide: float = fold["slide"]
	var keep: float = fold["keep"]
	return fold["hilt"] + (d * keep if d < slide else d - slide * (1.0 - keep))


## `model_bounds` of a melee model as it is worn, folded away.
static func folded_bounds(model: Node3D) -> AABB:
	var box := model_bounds(model)
	if not model.has_meta("fold"):
		return box
	var top := fold_height(box.end.y - model.position.y, model.get_meta("fold")) + model.position.y
	box.size.y = maxf(top - box.position.y, 0.0)
	return box


## How far up the model (its +Y, in the holder) one surface of a mesh runs.
func _surface_span(mesh: Mesh, surface: int, xform: Transform3D) -> Vector2:
	var key := "%d/%d/%s" % [mesh.get_instance_id(), surface, xform]
	if _spans.has(key):
		return _spans[key]
	var span := Vector2(INF, -INF)
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	for v in verts:
		var y := (xform * v).y
		span = Vector2(minf(span.x, y), maxf(span.y, y))
	_spans[key] = span
	return span


## Folds a melee model away (`extend` 0, how it is worn holstered) or out
## (1, how it is held), or anywhere between while it is drawn or put away.
## Only models built by `weapon_model` fold; anything else is left alone.
## Fully out or folded share materials between every copy; in between, the
## model gets its own until it settles.
func set_extend(model: Node3D, extend: float) -> void:
	if model == null:
		return
	extend = clampf(extend, 0.0, 1.0)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_surface_override_material(i) as ShaderMaterial
			if mat == null:
				continue
			var full: ShaderMaterial = mat.get_meta("tech_full") if mat.has_meta("tech_full") \
					else (mat if mat.has_meta("tech_fold") else null)
			if full == null:
				continue
			var folded: ShaderMaterial = _folded[full.get_instance_id()]
			var pick: ShaderMaterial
			if extend >= 1.0:
				pick = full
			elif extend <= 0.0:
				pick = folded
			else:
				pick = mat if mat != full and mat != folded else full.duplicate() as ShaderMaterial
				pick.set_meta("tech_full", full)
				pick.set_shader_parameter("extend", extend)
			if pick != mat:
				mesh_node.set_surface_override_material(i, pick)


## Which part of a melee model a pack color is: 1 for bare light metal (an
## edge or head), 0.5 for mid grey metal (a guard or fitting), 0 for anything
## colored or dark (wood, leather, wraps).
static func tech_part(color: Color) -> float:
	var saturation := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
	var light := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	if saturation > 0.12 or light < 0.3:
		return 0.0
	return 1.0 if light > 0.45 else 0.5


## Which axis a flat blade is wide along (0 for X, 2 for Z), or -1 when the
## part is not flat enough to have a cutting edge.
static func edge_axis(box: AABB) -> int:
	var wide := maxf(box.size.x, box.size.z)
	var thin := minf(box.size.x, box.size.z)
	if wide <= 0.0 or thin > wide * 0.5:
		return -1
	return 0 if box.size.x >= box.size.z else 2


func _tech_material(source: BaseMaterial3D, glow: Color, strength: float, wear: float, meters: float,
		box: AABB, retract := {}) -> ShaderMaterial:
	var key := "tech/%d/%s/%.2f/%.2f/%.4f/%s/%s" % [source.get_instance_id(), glow.to_html(), strength, wear, meters,
		box, retract]
	if _gear_materials.has(key):
		return _gear_materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = MELEE_SHADER
	if source.albedo_texture:
		mat.set_shader_parameter("base_tex", source.albedo_texture)
	mat.set_shader_parameter("base_color", source.albedo_color)
	mat.set_shader_parameter("energy_color", glow)
	mat.set_shader_parameter("energy", strength)
	mat.set_shader_parameter("box_min", box.position)
	mat.set_shader_parameter("box_max", box.end)
	mat.set_shader_parameter("edge_axis", edge_axis(box))
	mat.set_shader_parameter("seam_scale", 6.0 * meters)
	mat.set_shader_parameter("part", tech_part(source.albedo_color))
	var dir := TEXTURES + "Metal063/"
	mat.set_shader_parameter("grime_albedo", load(dir + "Color.jpg"))
	mat.set_shader_parameter("grime_rough", load(dir + "Roughness.jpg"))
	mat.set_shader_parameter("wear", wear)
	if not retract.is_empty():
		mat.set_shader_parameter("fold_origin", retract["origin"])
		mat.set_shader_parameter("fold_axis", retract["axis"])
		mat.set_shader_parameter("fold_slide", retract["slide"])
		mat.set_shader_parameter("fold_keep", retract["keep"])
		mat.set_shader_parameter("extend", 1.0)
		# The copy worn holstered, folded away; `set_extend` swaps between them.
		mat.set_meta("tech_fold", true)
		var folded := mat.duplicate() as ShaderMaterial
		folded.set_shader_parameter("extend", 0.0)
		folded.set_meta("tech_full", mat)
		_folded[mat.get_instance_id()] = folded
	_gear_materials[key] = mat
	return mat


## No pack has a spear, so it is built here: a dark shaft, alloy collars
## and a long leaf head, standing along +Y like the pack models.
func _spear_model(length: float, grip: float, glow: Color, strength: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Model"
	var model := Node3D.new()
	model.name = "Spear"
	holder.add_child(model)
	var shaft := StandardMaterial3D.new()
	shaft.albedo_color = Color(0.2, 0.2, 0.22)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.63, 0.66)
	steel.metallic = 0.9
	steel.roughness = 0.35
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.12, 0.11, 0.1)
	wrap.roughness = 0.95
	var head_len := 0.34
	var shaft_len := length - head_len
	_spear_part(model, _cylinder(0.018, shaft_len), Vector3(0, shaft_len * 0.5, 0), shaft)
	_spear_part(model, _cylinder(0.024, 0.3), Vector3(0, grip, 0), wrap)
	_spear_part(model, _cylinder(0.022, 0.06), Vector3(0, 0.03, 0), steel)
	_spear_part(model, _cylinder(0.026, 0.07), Vector3(0, shaft_len - 0.02, 0), steel)
	# The head: a flattened double cone, widest a third of the way up.
	var lower := CylinderMesh.new()
	lower.top_radius = 0.055
	lower.bottom_radius = 0.02
	lower.height = head_len * 0.3
	_spear_part(model, lower, Vector3(0, shaft_len + head_len * 0.15, 0), steel, Vector3(1, 1, 0.3))
	var upper := CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 0.055
	upper.height = head_len * 0.7
	_spear_part(model, upper, Vector3(0, shaft_len + head_len * 0.65, 0), steel, Vector3(1, 1, 0.3))
	# Holstered, the shaft above the butt collar slides into itself and
	# carries the head down with it.
	_tech_melee(holder, glow, strength, 0.3, {"hilt": 0.2, "slide": shaft_len - 0.3, "keep": 0.2})
	holder.position.y = -grip
	return holder


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return mesh


func _spear_part(model: Node3D, mesh: PrimitiveMesh, at: Vector3, mat: Material, scale := Vector3.ONE) -> void:
	var part := MeshInstance3D.new()
	mesh.material = mat
	part.mesh = mesh
	part.position = at
	part.scale = scale
	model.add_child(part)


func _melee_pick(weapon: Weapon) -> Array:
	for entry: Array in MELEE_MODELS:
		if weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, entry[0]):
			return entry
	return DEFAULT_MELEE


## True when the weapon is held with both hands: the item's "two_handed"
## tag (`MeleeWeapon.is_two_handed_id`), the same flag gameplay reads.
## The one place a view asks; the grip and the sling follow it.
func is_two_handed(weapon: Weapon) -> bool:
	return weapon is MeleeWeapon and MeleeWeapon.is_two_handed_id(weapon.item_id)


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
	if cache.is_rack():
		_dress_power_rack(cache, marker, size)
		return
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


## A power rack: an armoured weapon stand with glowing clamps and a thin
## light column, so a power weapon can be spotted across the field. The
## game's marker (coloured by what is inside) stays as the glowing cradle.
func _dress_power_rack(rack: LootContainer, marker: MeshInstance3D, size: Vector3) -> void:
	var frame := Node3D.new()
	frame.name = "Crate"
	rack.add_child(frame)
	var steel := _power_mat(Color(0.24, 0.26, 0.31), 0.5, 0.45)
	var cyan := Color(0.35, 0.95, 1.0)
	var lit := _power_mat(cyan, 0.0, 0.4, cyan, 1.6)
	_power_box(frame, Vector3(size.x * 1.2, 0.12, size.z * 1.0), Vector3(0, 0.06, 0), steel)
	for side in [-1.0, 1.0]:
		_power_box(frame, Vector3(0.1, 1.3, 0.1), Vector3(size.x * 0.5 * side, 0.7, 0), steel)
		_power_box(frame, Vector3(0.14, 0.06, 0.3), Vector3(size.x * 0.5 * side, 1.05, 0), lit)
	_power_box(frame, Vector3(size.x * 1.05, 0.06, 0.06), Vector3(0, 1.36, 0), lit)
	var column := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.04
	beam.bottom_radius = 0.04
	beam.height = 9.0
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(cyan.r, cyan.g, cyan.b, 0.35)
	beam.material = glow
	column.mesh = beam
	column.position.y = 1.4 + beam.height * 0.5
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame.add_child(column)
	var light := lamp(cyan, 1.5, 6.0)
	light.position.y = 1.2
	frame.add_child(light)
	# The marker becomes the cradle the weapon rests in.
	var cradle := BoxMesh.new()
	cradle.size = Vector3(size.x * 0.9, 0.08, 0.22)
	marker.mesh = cradle
	marker.position.y = 0.9
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
		elif ItemDB.has_tag(id, "flight_rig"):
			_dress_rig_stand(model, id)
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
	# Attachments fitted to a gun on show move across onto the real model.
	var fitted := grey.get_node_or_null("Attachments")
	if fitted:
		grey.remove_child(fitted)
		holder.add_child(fitted)
		mount_attachments(holder)
	model.remove_child(grey)
	grey.queue_free()
	model.add_child(holder)


## A flight rig on show: its real model on a faceless mannequin, which stands
## with its back to the room so a back-worn rig faces you. Boots stand on
## the base.
func _dress_rig_stand(model: Node3D, id: String) -> void:
	model.set_meta("dressed", true)
	for child in model.get_children():
		model.remove_child(child)
		child.queue_free()
	var dummy := StandardMaterial3D.new()
	dummy.albedo_color = Color(0.22, 0.22, 0.24)
	var stand := Node3D.new()
	stand.name = "Mannequin"
	for piece: Array in [[Vector3(0.7, 0.08, 0.7), Vector3(0, 0.04, 0)], [Vector3(0.1, 0.9, 0.1), Vector3(0, 0.5, 0)],
			[Vector3(0.42, 0.6, 0.24), Vector3(0, 1.25, 0)], [Vector3(0.24, 0.26, 0.24), Vector3(0, 1.72, 0)]]:
		var box := BoxMesh.new()
		box.size = piece[0]
		box.material = dummy
		var part := MeshInstance3D.new()
		part.mesh = box
		part.position = piece[1]
		stand.add_child(part)
	model.add_child(stand)
	var back := RigModel.build_back(id)
	if back:
		back.position = Vector3(0, 1.36, 0.12)
		if back.has_node("WingL"):
			RigModel.set_wing_spread(back, 0.55)
		_weather_model(back, 0.5, 0.6)
		model.add_child(back)
	for side: float in [-1.0, 1.0]:
		var boot := RigModel.build_boot(id, side)
		if boot:
			# Set down on the base either side of the pole, heel to the room.
			boot.position = Vector3(side * 0.16, 0.15, 0.05)
			_weather_model(boot, 0.5, 0.6)
			model.add_child(boot)


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
