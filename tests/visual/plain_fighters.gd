extends RefCounted
## `--plain-fighters-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --plain-fighters-only` shoots the plain fighters' own
## touches ("gear", `ActorSkin._build_gear`) in a row on open ground: the
## Legion Marksman, the Tide Runner, the Dune Sea's Sand Raider and Dune
## Marksman, beside a plain Legionnaire to compare. Front, side and back,
## and each head close from the front and three quarters.

const PICKS := [["ashfront", "legion", "soldier"], ["ashfront", "legion", "marksman"], ["ashfront", "tide", "runner"],
		["dunes", "dunes", "grunt"], ["dunes", "dunes", "marksman"]]


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("dunes"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position += Vector3(0, -400, 0)
	var player := raid.player
	player.set_physics_process(false)
	player.visible = false
	var ground := func(at: Vector3) -> Vector3:
		return Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z)
	var origin: Vector3 = ground.call(player.global_position + Vector3(30, 0, 0))
	var line: Array[Actor] = []
	for pick: Array in PICKS:
		var world := Worlds.get_world(pick[0])
		for i in 400:
			var bot := Actor.new()
			bot.faction = pick[1]
			bot.set_meta("zone", 1)
			var rng := RandomNumberGenerator.new()
			rng.seed = i
			world.equip_bot(bot, rng)
			if bot.get_meta("kind", "") == pick[2]:
				bot.set_physics_process(false)
				raid.add_child(bot)
				line.append(bot)
				break
			bot.free()
	for i in line.size():
		line[i].global_position = ground.call(origin + Vector3((i - (line.size() - 1) * 0.5) * 1.6, 0, 0))
		line[i].rotation.y = 0.0
		if line[i].get_active_weapon() == null:
			line[i]._draw_weapon(line[i].weapon_for_key(1))
	var cam := Camera3D.new()
	cam.fov = 40.0
	raid.add_child(cam)
	cam.current = true
	await v._settle(40)
	var mid := origin + Vector3(0, 1.0, 0)
	for view: Array in [["front", Vector3(0, 0.4, -9.0)], ["side", Vector3(9.0, 0.4, 0)], ["back", Vector3(0, 0.4, 9.0)]]:
		cam.look_at_from_position(mid + view[1], mid)
		await v._settle(4)
		await v._shot(out_dir.path_join("plain_%s.png" % view[0]))
	cam.fov = 30.0
	for i in line.size():
		var head := line[i].global_position + Vector3(0, 1.55, 0)
		for view: Array in [["face", Vector3(0, 0.05, -1.6)], ["quarter", Vector3(1.1, 0.1, -1.1)], ["rear", Vector3(-1.0, 0.15, 1.2)]]:
			cam.look_at_from_position(head + view[1], head + Vector3(0, -0.2, 0))
			await v._settle(3)
			await v._shot(out_dir.path_join("plain_%d_%s.png" % [i, view[0]]))
	raid.queue_free()
