extends Node3D
## The horde on Ashfront's battle shelves (DESIGN.md "The battle around
## you"): past the scenery army's fights, the shelves past the rim are
## crowded with the two armies' masses, thousands of far figures surging and
## firing, so the war reads as a whole planet at war and not a few squads.
## View only and never in a server: the map adds it only where `Look` is on,
## and nobody can reach the shelves, so nothing of it is ever seen up close.
##
## It costs two draw calls and nothing a frame on the processor: every
## figure is one instance laid once (`build`), and all the motion, the
## surging, the muzzle flashes and the blasts, is worked out on the graphics
## card from the time and each instance's own numbers (`horde.gdshader`).
## The crowd is a dark speck per figure, the fire is an added glow. The war
## (the map's "war_intensity") sets how much of it fires, the "Far battle
## scenery" setting (`GameSettings.war_share`) how many figures are drawn,
## and an ash storm (`Look.weather_cover`) hides it.

const GameSettings := preload("res://core/settings/game_settings.gd")

## Figures on all the shelves together, at the full setting.
const FIGURES := 2400
## Each army's colour of fire (as the scenery army's tracers).
const FIRE := [Color(1.0, 0.42, 0.08), Color(0.15, 0.7, 1.0)]

## Set by the map: the shelves and their flats (see the map's `SHELVES`),
## and the ground out there (`ground_at(x, z)`).
var shelves: Array = []
var flats: Array = []
var ground_at := Callable()

## Where each figure was laid (for checks; the drawing keeps its own copy).
var spots := PackedVector3Array()
var _crowd: MultiMeshInstance3D
var _fire: MultiMeshInstance3D
var _material: ShaderMaterial
var _fire_material: ShaderMaterial
var _shown := -1
var _heat := -1.0
var _veil := -1.0


func _ready() -> void:
	name = "Horde"
	if Look.enabled:
		build()


## Lays every figure once: on a shelf's flat, the two armies facing each
## other along it, thickest at the line between them.
func build() -> void:
	if shelves.is_empty() or flats.is_empty() or not ground_at.is_valid():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 6113
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/horde.gdshader") as Shader
	_fire_material = ShaderMaterial.new()
	_fire_material.shader = load("res://assets/shaders/horde_fire.gdshader") as Shader
	_fire_material.set_shader_parameter("fire_a", FIRE[0])
	_fire_material.set_shader_parameter("fire_b", FIRE[1])
	var crowd := _multimesh()
	var fire := _multimesh()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in FIGURES:
		var shelf: Dictionary = shelves[i % shelves.size()]
		var out: Vector2 = shelf["out"]
		var along := Vector2(-out.y, out.x)
		var lateral: Vector2 = shelf["lateral"]
		var flat: Vector2 = flats[rng.randi() % flats.size()]
		# Each shelf's flat has its own line between the armies, somewhere
		# along it; the two masses crowd up to it from either side.
		var line := lerpf(lateral.x, lateral.y, 0.3 + 0.4 * _hash(float(flats.find(flat)) + float(shelves.find(shelf)) * 7.0))
		var side := rng.randi() % 2
		var back := absf(rng.randfn(0.0, 38.0)) + 4.0
		var l := clampf(line + (back if side == 1 else -back), lateral.x + 4.0, lateral.y - 4.0)
		var d := rng.randf_range(flat.x + 2.0, flat.y - 2.0)
		var spot := out * d + along * l
		var at := Vector3(spot.x, float(ground_at.call(spot.x, spot.y)), spot.y)
		# Facing the line: the way it surges, in the crowd's own frame.
		var toward := along * (-1.0 if side == 1 else 1.0)
		var xform := Transform3D(Basis.IDENTITY, at)
		var data := Color(float(side), rng.randf(), rng.randf_range(0.6, 1.4), 0.0)
		var heading := Color(toward.x, toward.y, 0.0, 0.0)
		crowd.set_instance_transform(i, xform)
		crowd.set_instance_custom_data(i, data)
		crowd.set_instance_color(i, heading)
		fire.set_instance_transform(i, xform)
		fire.set_instance_custom_data(i, data)
		fire.set_instance_color(i, heading)
		spots.append(at)
		lo = lo.min(at)
		hi = hi.max(at)
	var bounds := AABB(lo - Vector3(20, 10, 20), hi - lo + Vector3(40, 40, 40))
	_crowd = _node(crowd, _material, bounds)
	_fire = _node(fire, _fire_material, bounds)
	_shown = -1
	_process(0.0)


func _multimesh() -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 1.8)
	quad.center_offset = Vector3(0.0, 0.9, 0.0)
	multi.mesh = quad
	multi.instance_count = FIGURES
	return multi


func _node(multi: MultiMesh, material: Material, bounds: AABB) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = bounds
	add_child(node)
	return node


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 4.1414) * 43758.5453, 1.0)


func _process(_delta: float) -> void:
	if _crowd == null:
		return
	var shown := int(FIGURES * GameSettings.war_share())
	if shown != _shown:
		_shown = shown
		_crowd.multimesh.visible_instance_count = shown
		_fire.multimesh.visible_instance_count = shown
	var map := get_parent()
	var heat := snappedf(clampf(float(map.get_meta("war_intensity", 0.0)), 0.0, 1.0) if map != null else 0.0, 0.02)
	if heat != _heat:
		_heat = heat
		_material.set_shader_parameter("heat", heat)
		_fire_material.set_shader_parameter("heat", heat)
	var veil := snappedf(Look.weather_cover, 0.02)
	if veil != _veil:
		_veil = veil
		_material.set_shader_parameter("veil", veil)
		_fire_material.set_shader_parameter("veil", veil)
		var hidden := veil >= 0.99
		_crowd.visible = not hidden
		_fire.visible = not hidden
