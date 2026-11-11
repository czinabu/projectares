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
