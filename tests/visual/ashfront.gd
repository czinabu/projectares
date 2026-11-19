extends RefCounted
## `--ashfront-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --ashfront-only` shoots Ashfront's look from fixed
## spots: a gate looking in, the open field, the middle ring, the core's
## edge and from high over a corner, to compare the dressing before and after.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	raid.player.visible = false
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.far = 1500.0
	raid.add_child(camera)
	camera.make_current()
	var ground := func(x: float, z: float) -> float: return raid.map.call("ground_height", x, z)
	# From, toward, eye height above the ground at each.
	var views := [
		["gate", Vector2(-125, -150), Vector2(0, 0), 2.0],
		["field", Vector2(-150, 30), Vector2(0, 0), 2.0],
		["middle", Vector2(80, 150), Vector2(0, 0), 2.0],
		["core_edge", Vector2(30, 80), Vector2(0, 0), 3.0],
		["rustfall", Vector2(210, -40), Vector2(158, -106), 4.0],
		["high", Vector2(-230, 230), Vector2(0, 0), 60.0],
		["skyline", Vector2(60, 20), Vector2(260, -120), 2.0],
		["tide_push", Vector2(140, 22), Vector2(70, -4), 4.0],
		["air_assault", Vector2(-190, -60), Vector2(-90, -12), 6.0],
		["breach_striders", Vector2(-50, 175), Vector2(-100, 125), 4.0],
		# Driving: down the Legion's runway, along the east road through
		# the tank column, and up the road to Signal Hill.
		["runway", Vector2(-205, 4.4), Vector2(-60, 2), 2.5],
		["east_road", Vector2(150, -9), Vector2(60, -2), 2.0],
		["hill_road", Vector2(-198, -24), Vector2(-150, -118), 2.5],
		# The Works: up its street from the mouth, from the first gantry,
		# over it from the air, along the cross street, and from the field.
		["works_mouth", Vector2(2, 214), Vector2(0, 0), 1.8],
		["works_gantry", Vector2(0, 187), Vector2(0, 0), 7.6],
		["works_air", Vector2(70, 236), Vector2(0, 150), 45.0],
		["works_cross", Vector2(46, 158), Vector2(-20, 152), 1.8],
		["works_field", Vector2(-95, 205), Vector2(0, 150), 2.0],
	]
	for view: Array in views:
		var from: Vector2 = view[1]
		var to: Vector2 = view[2]
		var eye := Vector3(from.x, ground.call(from.x, from.y) + float(view[3]), from.y)
		var aim := Vector3(to.x, ground.call(to.x, to.y) + 8.0, to.y)
		camera.look_at_from_position(eye, aim)
		await v._settle(40)
		await v._shot(out_dir.path_join("ashfront_%s.png" % view[0]))
	# Straight down over the whole field, north up, with the haze off: the
	# layout as a map. 1.5 px a metre at 1600x900, the middle at the centre.
	var envs := raid.map.find_children("*", "WorldEnvironment", true, false)
	for env_node in envs:
		(env_node as WorldEnvironment).environment.fog_enabled = false
		(env_node as WorldEnvironment).environment.volumetric_fog_enabled = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 600.0
	camera.look_at_from_position(Vector3(0, 700, 0), Vector3.ZERO, Vector3(0, 0, -1))
	await v._settle(20)
	await v._shot(out_dir.path_join("ashfront_map.png"))
	for env_node in envs:
		(env_node as WorldEnvironment).environment.fog_enabled = true
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	# The same view from the field toward the Forge, quiet, in a battle and
	# in all-out war, with the fighting just ahead.
	raid.war.cooling = 0.0
	var mood := raid.map.get_node("WarMood")
	var from := Vector2(-150, 30)
	var eye := Vector3(from.x, ground.call(from.x, from.y) + 2.0, from.y)
	camera.look_at_from_position(eye, Vector3(0, ground.call(0.0, 0.0) + 20.0, 0))
	for step: Array in [[0.0, "quiet"], [0.55, "battle"], [1.0, "all_out"]]:
		raid.war.intensity = step[0]
		raid.war.centre = Vector3(-80, 0, 15)
		mood.follow = 100.0
		await v._settle(200 if step[0] > 0.0 else 60)
		await v._shot(out_dir.path_join("ashfront_war_%s.png" % step[1]))
	raid.queue_free()
