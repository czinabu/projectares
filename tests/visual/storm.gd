extends RefCounted
## `--storm-only`, a mode `visual_check.gd` finds by itself.

const Vfx := preload("res://core/visual/vfx.gd")


## Peak storm, looking down a line of enemies at engagement range, with the
## smoke column standing on the camera. One frame is enough to judge whether
## a fight can still be read.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	raid.war.cooling = 0.0
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	# Just outside a gate, looking into the field, which is the view that
	# went brown in the playtest. The column is planted on the camera.
	var gate: Node3D = raid.outposts[0]
	var forward := -Vector3(gate.global_position.x, 0.0, gate.global_position.z).normalized()
	var origin := gate.global_position + forward * 22.0
	origin.y = raid.map.call("ground_height", origin.x, origin.z)
	var line: Array[Actor] = []
	for bot in raid.bots:
		if line.size() >= 4 or bot.is_dead:
			continue
		line.append(bot)
	var side := Vector3(-forward.z, 0.0, forward.x)
	var distances: Array[float] = [14.0, 32.0, 50.0, 78.0]
	var lateral: Array[float] = [-5.0, -1.6, 1.6, 5.0]
	for i in line.size():
		var at := origin + forward * distances[i] + side * lateral[i]
		var gy: float = raid.map.call("ground_height", at.x, at.z)
		line[i].global_position = Vector3(at.x, gy, at.z)
		line[i].velocity = Vector3.ZERO
		line[i].rotation.y = atan2(-forward.x, -forward.z)
	for bot in raid.bots:
		if bot not in line:
			bot.global_position += Vector3(0, -400, 0)
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.far = 800.0
	raid.add_child(cam)
	cam.current = true
	var eye := origin + Vector3(0, 1.65, 0)
	cam.global_position = eye
	# Aim at the line, not at a fixed height: the ground in front of a gate
	# rises, and a low aim looks into the slope.
	var focus: Vector3 = line[mini(1, line.size() - 1)].global_position + Vector3(0, 1.2, 0) if not line.is_empty() else origin + forward * 30.0
	cam.look_at(focus)
	raid.war.intensity = 1.0
	raid.war.centre = origin
	raid.map.set_meta("war_intensity", 1.0)
	raid.map.set_meta("war_centre", origin)
	var mood: Node = raid.map.get_node("WarMood")
	mood.follow = 100.0
	await v._settle(40)
	var smoke := mood.get_node("WarColumn/Smoke") as GPUParticles3D
	smoke.preprocess = 8.0
	smoke.restart()
	await v._settle(12)
	var from := eye + forward * 8.0 + side * 2.4
	var to := origin + forward * 62.0 + side * 2.4 + Vector3(0, 1.1, 0)
	_hold_shot(v, raid, from, to, Color(1.0, 0.78, 0.35))
	Vfx.muzzle_flash(raid, from, (to - from).normalized())
	await v._shot(out_dir.path_join("storm_peak.png"))
	raid.queue_free()


## A tracer left in the frame. Uses the same material shots do, so a change
## to how tracers survive fog shows up here.
static func _hold_shot(v: Node, parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, length)
	var mat: Material
	if Fx.new().has_method("shot_material"):
		mat = Fx.shot_material(color)
	else:
		var plain := StandardMaterial3D.new()
		plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plain.albedo_color = color
		mat = plain
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var dir := (to - from).normalized()
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	node.look_at_from_position((from + to) * 0.5, to, up)
