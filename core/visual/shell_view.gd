class_name ShellView
extends Node3D
## Draws and sounds the war's artillery (`Raid.shells_called`, DESIGN.md
## "Shelling"). Each spot is marked from the moment it is called: a column
## of red light up out of the ground and a ring round where it will hurt,
## pulsing faster as the shell comes in. A falling whistle gives the last
## second away, then the shell lands in three beats: a flash that lights the
## ground round it, a fireball throwing a fan of dirt up and out, and a dark
## column left rising and drifting off. Its blast is heard and jolts the view
## (`PlayerController.feel_blast`) once its sound has had time to arrive.
## View only: the raid adds it only where `Look` is on, it times each shell
## from what it was told, and nothing reads it back.

## The mark: how tall and wide its column is, and the ring's colour.
const COLUMN := Vector2(1.4, 60.0)
const MARK := Color(1.0, 0.14, 0.05)
## The whistle starts this long before a shell lands.
const WHISTLE := 1.1
## How far a blast is heard, and the speed its sound travels at.
const REACH := 420.0
const SOUND_SPEED := 340.0
## Seconds a blast's cloud lasts, and the most left drifting at once (the
## oldest goes first).
const CLOUD_LIFE := 16.0
const MAX_CLOUDS := 10
## Puffs in a blast: thrown dirt, the fireball and the column.
const DIRT := 26
const FIREBALL := 8
const COLUMN_PUFFS := 16

var raid: Raid
var _incoming: Array[Dictionary] = []
var _clouds: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _smoke_shader: Shader
var _mark_shader: Shader


func _ready() -> void:
	name = "Shells"
	_rng.seed = 11
	_smoke_shader = load("res://assets/shaders/shell_smoke.gdshader") as Shader
	_mark_shader = load("res://assets/shaders/shell_mark.gdshader") as Shader
	raid.shells_called.connect(_on_called)


func _on_called(points: PackedVector3Array, lands_in: PackedFloat32Array) -> void:
	for i in mini(points.size(), lands_in.size()):
		var mark := _mark(points[i], lands_in[i])
		_incoming.append({"at": points[i], "left": lands_in[i], "full": maxf(lands_in[i], 0.1),
				"mark": mark, "whistled": false})


func _process(delta: float) -> void:
	for shot: Dictionary in _incoming.duplicate():
		shot.left = float(shot.left) - delta
		var mark: Node3D = shot.mark
		if is_instance_valid(mark):
			var urgency := 1.0 - clampf(float(shot.left) / float(shot.full), 0.0, 1.0)
			(mark.get_meta("column_mat") as ShaderMaterial).set_shader_parameter("urgency", urgency)
		if not shot.whistled and float(shot.left) <= WHISTLE:
			shot.whistled = true
			Sfx.play("shell_whistle", shot.at + Vector3(0.0, 25.0, 0.0), -2.0, 120.0)
		if float(shot.left) <= 0.0:
			_incoming.erase(shot)
			if is_instance_valid(mark):
				mark.queue_free()
			_blast(shot.at)
	for cloud: Dictionary in _clouds.duplicate():
		cloud.age = float(cloud.age) + delta
		var node: Node3D = cloud.node
		if float(cloud.age) >= CLOUD_LIFE or not is_instance_valid(node):
			_clouds.erase(cloud)
			if is_instance_valid(node):
				node.queue_free()
			continue
		(cloud.mat as ShaderMaterial).set_shader_parameter("age", cloud.age)


## The red column and the ring round where it will hurt.
func _mark(at: Vector3, _lands_in: float) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	node.global_position = at
	var tube := CylinderMesh.new()
	tube.top_radius = COLUMN.x
	tube.bottom_radius = COLUMN.x
	tube.height = COLUMN.y
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 12
	tube.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = _mark_shader
	tube.material = mat
	var column := MeshInstance3D.new()
	column.mesh = tube
	column.position.y = COLUMN.y * 0.5
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(column)
	node.set_meta("column_mat", mat)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.93
	ring.outer_radius = 1.0
	ring.rings = 40
	ring.ring_segments = 4
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = MARK
	ring.material = ring_mat
	var edge := MeshInstance3D.new()
	edge.mesh = ring
	var reach := raid.shelling.radius if raid.shelling != null else 9.0
	edge.scale = Vector3(reach, 3.0, reach)
	edge.position.y = 0.15
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(edge)
	var glow := OmniLight3D.new()
	glow.light_color = MARK
	glow.light_energy = 1.6
	glow.omni_range = 8.0
	glow.position.y = 1.0
	node.add_child(glow)
	return node


func _blast(at: Vector3) -> void:
	Fx.ring(self, at + Vector3(0.0, 0.3, 0.0), 16.0, Color(1.0, 0.55, 0.3), 0.7)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.45)
	flash.light_energy = 14.0
	flash.omni_range = 60.0
	flash.omni_attenuation = 1.4
	add_child(flash)
	flash.global_position = at + Vector3(0.0, 4.0, 0.0)
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 2.0, 0.25)
	tween.tween_property(flash, "light_energy", 0.0, 1.6)
	tween.tween_callback(flash.queue_free)
	_cloud(at)
	# Heard, and felt, once the sound gets there.
	var camera := get_viewport().get_camera_3d()
	var delay := camera.global_position.distance_to(at) / SOUND_SPEED if camera else 0.0
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(_arrive.bind(at))


func _arrive(at: Vector3) -> void:
	if not is_inside_tree():
		return
	Sfx.play("shell_blast", at, 6.0, REACH, 30.0)
	for node in get_tree().get_nodes_in_group("player_controllers"):
		var controller := node as PlayerController
		if controller and is_instance_valid(controller.actor) and Raid.together(controller.actor, self):
			controller.feel_blast(at)


## The blast's cloud: one MultiMesh of puffs thrown out from the heart.
func _cloud(at: Vector3) -> void:
	while _clouds.size() >= MAX_CLOUDS:
		var old: Dictionary = _clouds.pop_front()
		if is_instance_valid(old.node):
			(old.node as Node3D).queue_free()
	var puffs: Array[Array] = []
	for i in DIRT:
		var up := _rng.randf_range(3.0, 22.0)
		var side := _rng.randf() * TAU
		var out := up * _rng.randf_range(0.1, 0.5)
		puffs.append([at + Vector3(sin(side) * out, up, cos(side) * out), _rng.randf_range(2.5, 5.5),
				Color(0.1, 0.075, 0.055, 0.92), Color(_rng.randf(), 0.25, -0.4, _rng.randf_range(4.0, 7.0))])
	for i in FIREBALL:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.0), _rng.randf_range(-1, 1)).normalized()
		puffs.append([at + Vector3(0.0, 2.0, 0.0) + dir * _rng.randf_range(1.0, 4.0), _rng.randf_range(4.5, 7.5),
				Color(0.3, 0.14, 0.06, 0.95), Color(_rng.randf(), 3.5, 0.8, _rng.randf_range(2.5, 4.0))])
	for i in COLUMN_PUFFS:
		var high := _rng.randf_range(1.0, 18.0)
		var wide := 1.5 + high * 0.2
		puffs.append([at + Vector3(_rng.randf_range(-wide, wide), high, _rng.randf_range(-wide, wide)),
				4.0 + high * 0.3, Color(0.075, 0.065, 0.06, 0.85),
				Color(_rng.randf(), 0.45, _rng.randf_range(0.8, 1.6), CLOUD_LIFE * _rng.randf_range(0.7, 1.0))])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = _smoke_shader
	mat.set_shader_parameter("centre", at + Vector3(0.0, 1.0, 0.0))
	mat.set_shader_parameter("age", 0.0)
	quad.material = mat
	multimesh.mesh = quad
	multimesh.instance_count = puffs.size()
	for i in puffs.size():
		var puff: Array = puffs[i]
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(puff[1])), puff[0]))
		multimesh.set_instance_color(i, puff[2])
		multimesh.set_instance_custom_data(i, puff[3])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = Vector3.ZERO
	node.custom_aabb = AABB(at + Vector3(-40.0, -10.0, -40.0), Vector3(80.0, 80.0, 80.0))
	_clouds.append({"node": node, "mat": mat, "age": 0.0})
