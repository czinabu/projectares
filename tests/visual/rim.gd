extends RefCounted
## `--rim-only`, a mode `visual_check.gd` finds by itself. Ashfront's rim as
## a player sees it from the field: from the middle and from near each side,
## looking out at each of the four walls, then from high over a corner.


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
	# Name, from, toward, eye height above the ground.
	var views := [
		["north", Vector2(20, -120), Vector2(40, -330), 2.0],
		["east", Vector2(150, 40), Vector2(330, 10), 2.0],
		["south", Vector2(-30, 120), Vector2(-60, 330), 2.0],
		["west", Vector2(-150, -40), Vector2(-330, -10), 2.0],
		["near_east", Vector2(240, -60), Vector2(330, -90), 2.0],
		["corner", Vector2(-200, -200), Vector2(-330, -330), 2.0],
		["high", Vector2(-120, 160), Vector2(200, -260), 70.0],
		["close", Vector2(240, 40), Vector2(316, -80), 40.0],
	]
	for view: Array in views:
		var from: Vector2 = view[1]
		var to: Vector2 = view[2]
		var eye := Vector3(from.x, ground.call(from.x, from.y) + float(view[3]), from.y)
		var aim := Vector3(to.x, ground.call(to.x, to.y) + 10.0, to.y)
		camera.look_at_from_position(eye, aim)
		await v._settle(40)
		await v._shot(out_dir.path_join("rim_%s.png" % view[0]))
	raid.queue_free()
