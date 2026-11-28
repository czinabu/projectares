extends RefCounted
## `--kit-only`, a mode `visual_check.gd` finds by itself. Ashfront's field
## landmarks clad in kit pieces (`worlds/ashfront/kit_dress.gd`), each from
## the field, near and far: name, from, toward, eye height over the ground,
## aim height over the ground there.

const VIEWS := [
	["forge_far", Vector2(90, 70), Vector2(2, -2), 2.0, 30.0],
	["forge_near", Vector2(28, -4), Vector2(2, -2), 1.7, 12.0],
	["forge_mouth", Vector2(2, 18), Vector2(2, -2), 1.7, 3.0],
	["forge_air", Vector2(-40, -36), Vector2(2, -2), 30.0, 20.0],
]


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.visible = false
	raid.player.visible = false
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.far = 3000.0
	raid.add_child(camera)
	camera.make_current()
	var ground := func(x: float, z: float) -> float: return float(raid.map.call("scenery_height", x, z))
	for view: Array in VIEWS:
		var from: Vector2 = view[1]
		var to: Vector2 = view[2]
		var eye := Vector3(from.x, ground.call(from.x, from.y) + float(view[3]), from.y)
		var aim := Vector3(to.x, ground.call(to.x, to.y) + float(view[4]), to.y)
		camera.look_at_from_position(eye, aim)
		await v._settle(40)
		await v._shot(out_dir.path_join("kit_%s.png" % view[0]))
	raid.queue_free()
