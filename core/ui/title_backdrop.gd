class_name TitleBackdrop
extends Node3D
## What plays behind the start screen: the lane between worlds. The camera
## drifts down an endless dark corridor of gate frames, the same square arches
## that stand on the hub's gate terrace, with thin light streaks running past.
## Now and then a frame carries the name of a world you can deploy to
## (`Worlds.raid_worlds()`), so this never names one itself.
##
## On Start, `jump()` throws it into transit: the speed climbs, the streaks
## stretch, the view widens, and the lane flares to white.
##
## The camera stands still and the lane moves past it, wrapping round, so it
## runs forever with a fixed amount of geometry. Nothing here takes input,
## and it does nothing that a headless run cares about.

## Cruise speed down the lane (m/s) and the top speed of a jump.
var cruise_speed := 22.0
var jump_speed := 520.0
## Seconds a jump takes to reach full speed and flare.
var jump_time := 1.15
## Gate frames: how many are in the lane, how far apart, and their size.
var gate_count := 14
var gate_spacing := 34.0
var gate_size := Vector2(15, 9)
## One gate in this many is amber; the rest are cyan.
var amber_every := 5
## One gate in this many carries a world's name.
var name_every := 4
## Light streaks along the walls of the lane.
var streak_count := 160
var streak_length := 6.0
var fov := 52.0
var jump_fov := 100.0
## The slow sway of the view as it drifts, so it never feels on rails.
var sway_roll := 2.2
var sway_period := 11.0

const UiTheme := preload("res://core/visual/ui_theme.gd")
const CYAN := Color(0.3, 0.85, 1.0)
const AMBER := Color(1.0, 0.62, 0.22)
const VOID := Color(0.01, 0.014, 0.035)

var camera: Camera3D
var speed := 0.0
## 0 while cruising, rising to 1 through a jump.
var jump_amount := 0.0
var _gates: Array[Node3D] = []
var _streaks: MultiMeshInstance3D
var _streak_spots: PackedVector3Array = []
var _env: Environment
var _time := 0.0
var _jumping := false
var _names: Array[String] = []
var _next_name := 0


func _ready() -> void:
	speed = cruise_speed
	for world in Worlds.raid_worlds():
		_names.append(world.display_name.to_upper())
	_build_environment()
	camera = Camera3D.new()
	camera.fov = fov
	camera.far = 900.0
	add_child(camera)
	camera.make_current()
	for i in gate_count:
		var gate := _build_gate(i)
		gate.position.z = -gate_spacing * (i + 1)
		add_child(gate)
		_gates.append(gate)
	_build_streaks()
	_build_rails()


func _process(delta: float) -> void:
	_time += delta
	advance(delta * speed)
	var sway := sin(_time * TAU / sway_period)
	camera.rotation = Vector3(deg_to_rad(0.6) * sin(_time * TAU / (sway_period * 1.7)), 0.0,
			deg_to_rad(sway_roll) * sway * (1.0 - jump_amount))
	camera.fov = lerpf(fov, jump_fov, ease(jump_amount, 2.4))
	if _env:
		_env.glow_intensity = lerpf(0.7, 2.6, jump_amount)


## Moves the lane `distance` metres past the camera. Gates and streaks that
## pass behind it go round to the far end.
func advance(distance: float) -> void:
	var lane := gate_spacing * gate_count
	for i in _gates.size():
		var gate := _gates[i]
		gate.position.z += distance
		while gate.position.z > gate_spacing * 0.5:
			gate.position.z -= lane
			_relabel(gate)
	if _streaks == null:
		return
	var stretch := 1.0 + jump_amount * 14.0
	var multimesh := _streaks.multimesh
	for i in _streak_spots.size():
		var spot := _streak_spots[i]
		spot.z += distance
		while spot.z > 10.0:
			spot.z -= lane
		_streak_spots[i] = spot
		multimesh.set_instance_transform(i,
				Transform3D(Basis.from_scale(Vector3(1, 1, stretch)), spot))


## Throws the lane into transit. Returns once it has flared to white.
func jump() -> void:
	if _jumping:
		return
	_jumping = true
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "speed", jump_speed, jump_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "jump_amount", 1.0, jump_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished


## A world name to hang on a gate, taking turns through the raid worlds.
func next_name() -> String:
	if _names.is_empty():
		return ""
	var name := _names[_next_name % _names.size()]
	_next_name += 1
	return name


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = VOID
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 0.9
	_env.fog_enabled = true
	_env.fog_light_color = VOID
	_env.fog_density = 1.0
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_depth_begin = gate_spacing * 3.0
	_env.fog_depth_end = gate_spacing * gate_count
	var holder := WorldEnvironment.new()
	holder.environment = _env
	add_child(holder)


## One gate frame: four thin lit bars round the lane with a dark collar, and a
## sign above it that some gates use.
func _build_gate(index: int) -> Node3D:
	var gate := Node3D.new()
	var color := AMBER if index % amber_every == amber_every - 1 else CYAN
	var w := gate_size.x
	var h := gate_size.y
	var bar := 0.12
	var lit := _glow(color, 0.9)
	var dark := _glow(Color(0.04, 0.05, 0.08), 0.0)
	for side: float in [-1.0, 1.0]:
		_bar(gate, Vector3(bar, h, bar), Vector3(side * w * 0.5, 0, 0), lit)
		_bar(gate, Vector3(0.9, h + 1.4, 0.6), Vector3(side * (w * 0.5 + 0.55), 0, 0), dark)
		_bar(gate, Vector3(w, bar, bar), Vector3(0, side * h * 0.5, 0), lit)
		_bar(gate, Vector3(w + 2.0, 0.7, 0.6), Vector3(0, side * (h * 0.5 + 0.45), 0), dark)
		# Short ticks inside the corners, the way the hub's arches are marked.
		for end: float in [-1.0, 1.0]:
			_bar(gate, Vector3(1.2, 0.06, 0.06), Vector3(end * (w * 0.5 - 0.9), side * (h * 0.5 - 0.35), 0), lit)
	var sign := Label3D.new()
	sign.name = "Sign"
	sign.font = load(UiTheme.FONT_PATH) as Font
	sign.font_size = 96
	sign.pixel_size = 0.012
	sign.outline_size = 0
	sign.modulate = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6)
	sign.shaded = false
	sign.position = Vector3(-w * 0.5 + 0.4, h * 0.5 - 1.0, 0)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gate.add_child(sign)
	gate.set_meta("index", index)
	_relabel(gate)
	return gate


func _relabel(gate: Node3D) -> void:
	var sign := gate.get_node_or_null("Sign") as Label3D
	if sign == null:
		return
	var index: int = gate.get_meta("index", 0)
	gate.set_meta("index", index + gate_count)
	sign.text = next_name() if index % name_every == 1 else ""


## Dim guide lines down the corners of the lane, out to where the fog takes
## them: they give the lane its depth while nothing passes.
func _build_rails() -> void:
	var length := gate_spacing * gate_count
	var rail := _glow(CYAN * 0.12, 0.0)
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			_bar(self, Vector3(0.05, 0.05, length), Vector3(x * (gate_size.x * 0.5 - 0.6), y * (gate_size.y * 0.5 - 0.6),
					-length * 0.5), rail)


## Thin streaks of light along the walls, floor and ceiling of the lane.
func _build_streaks() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, streak_length)
	mesh.material = _glow(Color(0.6, 0.85, 1.0), 0.9)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = streak_count
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var lane := gate_spacing * gate_count
	for i in streak_count:
		# Round the inside of the frames, kept off the middle of the view.
		var angle := rng.randf() * TAU
		var reach := Vector2(cos(angle) * gate_size.x * 0.46, sin(angle) * gate_size.y * 0.46)
		reach *= rng.randf_range(0.75, 1.0)
		_streak_spots.append(Vector3(reach.x, reach.y, -rng.randf() * lane))
	_streaks = MultiMeshInstance3D.new()
	_streaks.multimesh = multimesh
	add_child(_streaks)
	advance(0.0)



func _bar(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color * (1.0 + energy) if energy > 0.0 else color
	material.albedo_color.a = 1.0
	return material
