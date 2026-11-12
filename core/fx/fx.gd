class_name Fx
extends RefCounted
## Throwaway greybox effects. Skipped entirely on a headless server.


static func tracer(parent: Node, from: Vector3, to: Vector3, color := Color(1.0, 0.85, 0.4)) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var dir := (to - from).normalized()
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	node.look_at_from_position((from + to) * 0.5, to, up)
	parent.get_tree().create_timer(0.05).timeout.connect(node.queue_free)


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
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.9))
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
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.7))
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
