extends RefCounted
## `--heavies-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --heavies-only` shoots Ashfront's armies side by side
## (soldiers, exo troopers, walkers) front and back, a walker close from
## the front, side and back, the line at 50 m in a peak
## storm, and a walker's tracking beam locking on.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	const HeavyUnitTests := preload("res://tests/heavy_unit_tests.gd")
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -400, 0)
		bot.set_physics_process(false)
	var player := raid.player
	var gate: Node3D = raid.outposts[0]
	var forward := -Vector3(gate.global_position.x, 0.0, gate.global_position.z).normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var origin := gate.global_position + forward * 24.0
	var ground := func(at: Vector3) -> Vector3:
		return Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z)
	origin = ground.call(origin)
	player.set_physics_process(false)
	player.global_position = origin
	player.visible = false
	# A Legion and a Tide soldier, an exo of each, and a walker of each.
	var line: Array[Actor] = []
	var picks := [["soldier", "legion"], ["soldier", "tide"], ["exo", "legion"], ["exo", "tide"],
			["walker", "legion"], ["walker", "tide"]]
	var next_seed := 10
	for pick: Array in picks:
		var bot: Actor = null
		for i in 600:
			next_seed += 1
			var b := raid.spawn_bot("Line%d" % next_seed, origin + Vector3(0, 0, 0), next_seed, false, pick[1], 2)
			if b.get_meta("kind", "") == pick[0]:
				bot = b
				break
			raid.bots.erase(b)
			b.free()
		if bot:
			line.append(bot)
	var place := func(distance: float) -> void:
		for i in line.size():
			var at: Vector3 = ground.call(origin + forward * distance + side * ((i - (line.size() - 1) * 0.5) * 2.1))
			line[i].global_position = at
			line[i].velocity = Vector3.ZERO
			line[i].cmd.yaw = atan2(forward.x, forward.z)
			line[i].cmd.secondary = false
			line[i].cmd.pitch = 0.0
			line[i].cmd.aim_dir = Vector3.ZERO
	place.call(7.0)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 800.0
	raid.add_child(cam)
	cam.current = true
	await v._settle(40)
	var mid: Vector3 = ground.call(origin + forward * 7.0)
	cam.look_at_from_position(ground.call(origin) + Vector3(0, 1.8, 0), mid + Vector3(0, 1.2, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("heavies_front.png"))
	cam.look_at_from_position(ground.call(mid + forward * 7.0) + Vector3(0, 1.8, 0), mid + Vector3(0, 1.3, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("heavies_back.png"))
	# The exo troopers close, three quarters from behind.
	var exo := line[2] if line.size() > 2 else line[0]
	cam.look_at_from_position(ground.call(exo.global_position + forward * 2.6 + side * 1.6) + Vector3(0, 1.7, 0),
			exo.global_position + Vector3(0, 1.3, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("exo_close.png"))
	# A walker close, three quarters from the front, from the side, and three
	# quarters from behind on its vent.
	var walker_close: Actor = null
	for bot in line:
		if bot.get_meta("kind", "") == "walker":
			walker_close = bot
			break
	if walker_close:
		var at := walker_close.global_position
		var views := [["walker_close_front.png", -forward * 5.5 + side * 3.5],
				["walker_close_side.png", side * 6.5 - forward * 0.5],
				["walker_close_back.png", forward * 5.0 - side * 3.5]]
		for view: Array in views:
			cam.look_at_from_position(ground.call(at + view[1]) + Vector3(0, 1.9, 0), at + Vector3(0, 1.6, 0))
			await v._settle(4)
			await v._shot(out_dir.path_join(view[0]))
	# Peak storm, the line at 50 m.
	raid.war.intensity = 1.0
	raid.war.centre = origin
	raid.map.set_meta("war_intensity", 1.0)
	raid.map.set_meta("war_centre", origin)
	var mood: Node = raid.map.get_node("WarMood")
	mood.follow = 100.0
	place.call(50.0)
	await v._settle(40)
	cam.fov = 45.0
	# From a little up, so a rise in the ground does not hide the line.
	var far: Vector3 = ground.call(origin + forward * 50.0)
	cam.look_at_from_position(Vector3(origin.x, maxf(ground.call(origin).y, far.y) + 8.0, origin.z),
			far + Vector3(0, 1.2, 0))
	await v._settle(4)
	await v._shot(out_dir.path_join("heavies_storm_50m.png"))
	# A walker's beam on a flier: building, then locked.
	raid.war.intensity = 0.0
	raid.map.set_meta("war_intensity", 0.0)
	place.call(14.0)
	var walker: Actor = null
	for bot in line:
		if bot.get_meta("kind", "") == "walker":
			walker = bot
			break
	if walker:
		player.visible = true
		player.global_position = walker.global_position - forward * 16.0 + side * 3.0 + Vector3(0, 7.0, 0)
		var eye := walker.get_eye_position()
		var to := (player.global_position + Vector3(0, 1.0, 0) - eye).normalized()
		walker.cmd.aim_dir = to
		walker.cmd.yaw = atan2(-to.x, -to.z)
		walker.cmd.pitch = asin(to.y)
		walker.cmd.secondary = true
		cam.fov = 60.0
		var middle := (eye + player.global_position) * 0.5
		var view: Vector3 = ground.call(middle + side * 14.0 + forward * 4.0) + Vector3(0, 2.5, 0)
		cam.look_at_from_position(view, middle)
		await v._settle(2)
		await v._shot(out_dir.path_join("walker_beam_building.png"))
		await v._settle(60)
		await v._shot(out_dir.path_join("walker_beam_locked.png"))
	raid.queue_free()
