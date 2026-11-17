class_name Fx
extends RefCounted
## Throwaway greybox effects. Skipped entirely on a headless server.


## A shot, bright enough to bloom and drawn with no fog, so a muzzle line
## still shows who fired when the storm is up. Walls still hide it.
static func shot_material(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.disable_fog = true
	return mat


static func tracer(parent: Node, from: Vector3, to: Vector3, color := Color(1.0, 0.85, 0.4)) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, length)
	mesh.material = shot_material(color)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var dir := (to - from).normalized()
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	node.look_at_from_position((from + to) * 0.5, to, up)
	parent.get_tree().create_timer(0.05).timeout.connect(node.queue_free)


## The most bullet marks left on walls at once; the oldest goes first.
const MAX_MARKS := 48
## How long a bullet mark stays on a wall, in seconds.
const MARK_LIFE := 8.0
## Impacts further from the camera than this are not drawn at all.
const IMPACT_RANGE := 70.0

static var _marks: Array[Node3D] = []
static var _mark_mesh: QuadMesh
static var _puff_mesh: SphereMesh


## Where a round struck: a quick puff off the surface, dust off the world or
## a hot spark off a body, and on the world a dark mark that stays a few
## seconds. `normal` is the face it struck (zero when unknown).
static func impact(parent: Node, at: Vector3, normal: Vector3, on_body: bool) -> void:
	if _headless(parent):
		return
	# Too far to be seen: a big battle fires thousands of rounds nobody sees land.
	var camera := parent.get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(at) > IMPACT_RANGE:
		return
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 1.0
		_puff_mesh.height = 2.0
		_puff_mesh.radial_segments = 8
		_puff_mesh.rings = 4
	var color := Color(1.0, 0.55, 0.25, 0.9) if on_body else Color(0.72, 0.68, 0.6, 0.7)
	var mat := _glow_mat(color)
	var puff := MeshInstance3D.new()
	puff.mesh = _puff_mesh
	puff.material_override = mat
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.scale = Vector3.ONE * 0.04
	parent.add_child(puff)
	puff.global_position = at + normal * 0.05
	var tween := puff.create_tween()
	tween.tween_property(puff, "scale", Vector3.ONE * (0.12 if on_body else 0.2), 0.16).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tween.tween_callback(puff.queue_free)
	if on_body or normal.is_zero_approx():
		return
	_leave_mark(parent, at, normal)


static func _leave_mark(parent: Node, at: Vector3, normal: Vector3) -> void:
	if _mark_mesh == null:
		_mark_mesh = QuadMesh.new()
		_mark_mesh.size = Vector2(0.1, 0.1)
		var mat := StandardMaterial3D.new()
		# A round hole with a scorched rim fading out, not a square.
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 1.0])
		ramp.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0.05, 0.04, 0.03, 0.95),
				Color(0.12, 0.1, 0.08, 0.5), Color(0.2, 0.18, 0.15, 0.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = ramp
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 32
		tex.height = 32
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mark_mesh.material = mat
	_marks = _marks.filter(func(m: Node3D) -> bool: return is_instance_valid(m))
	while _marks.size() >= MAX_MARKS:
		_marks.pop_front().queue_free()
	var mark := MeshInstance3D.new()
	mark.mesh = _mark_mesh
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mark)
	var up := Vector3.RIGHT if absf(normal.y) > 0.99 else Vector3.UP
	# A quad faces its +Z: look from behind the face so +Z points out of it.
	mark.look_at_from_position(at + normal * 0.012, at - normal, up)
	_marks.append(mark)
	var tween := mark.create_tween()
	tween.tween_interval(MARK_LIFE - 2.0)
	tween.tween_property(mark, "transparency", 1.0, 2.0)
	tween.tween_callback(mark.queue_free)


static func _headless(parent: Node) -> bool:
	return parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless"


static func _glow_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	return mat


## A charged shot's beam: thick, bright and slow to fade, so everyone can
## see where it came from.
static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, life := 0.6) -> void:
	if _headless(parent):
		return
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = 0.06
	mesh.height = length
	mesh.radial_segments = 6
	mesh.rings = 1
	var mat := shot_material(color, 0.9)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var dir := (to - from).normalized()
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	node.look_at_from_position((from + to) * 0.5, to, up)
	node.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, life)
	tween.parallel().tween_property(node, "scale", Vector3(0.2, 1.0, 0.2), life)
	tween.tween_callback(node.queue_free)


## A short glowing streak behind a round in flight.
static func trail(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if _headless(parent):
		return
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, length)
	var mat := shot_material(color, 0.7)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var dir := (to - from).normalized()
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	node.look_at_from_position((from + to) * 0.5, to, up)
	var tween := node.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(node.queue_free)


## A plasma or arc burst: a glowing ball that swells to `radius` and fades.
static func burst(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	if _headless(parent) or radius <= 0.0:
		return
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.75))
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ONE * 0.2
	parent.add_child(node)
	node.global_position = at
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = radius * 2.5
	node.add_child(light)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * radius, 0.18).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.45)
	tween.tween_callback(node.queue_free)


## A ring of light that sweeps out flat to `radius` and fades: a pulse that
## reaches everyone inside it (an artifact's Static Bloom).
static func ring(parent: Node, at: Vector3, radius: float, color: Color, life := 0.9) -> void:
	if _headless(parent) or radius <= 0.0:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.94
	mesh.outer_radius = 1.0
	mesh.rings = 48
	mesh.ring_segments = 6
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.9))
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3(0.3, 4.0, 0.3)
	parent.add_child(node)
	node.global_position = at
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3(radius, 4.0, radius), life * 0.6).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, life)
	tween.tween_callback(node.queue_free)


## A ghostly trail through `points`, left for a few seconds: where someone
## was snapped back along (an artifact's Time Rewind), so the shooter knows.
static func rewind_trail(parent: Node, points: PackedVector3Array, color: Color, life := 3.0) -> void:
	if _headless(parent) or points.size() < 2:
		return
	var root := Node3D.new()
	root.name = "RewindTrail"
	parent.add_child(root)
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.35))
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var lift := Vector3(0, 1.0, 0)
	for i in points.size() - 1:
		var from := points[i] + lift
		var to := points[i + 1] + lift
		var length := from.distance_to(to)
		if length < 0.05:
			continue
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.12, length)
		mesh.material = mat
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
		var dir := (to - from).normalized()
		var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
		node.look_at_from_position((from + to) * 0.5, to, up)
	# A ghost of the body where the rewind lands.
	var ghost := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	capsule.material = mat
	ghost.mesh = capsule
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ghost)
	ghost.global_position = points[0] + Vector3(0, 0.9, 0)
	var tween := root.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, life)
	tween.tween_callback(root.queue_free)
