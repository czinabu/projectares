extends RefCounted
## `--battle-only`, a mode `visual_check.gd` finds by itself.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.visible = false
	# From the top of Signal Hill, out over the field.
	var eye := raid._stand(Vector3(-140, 0, -108)) + Vector3(0, 2.0, 0)
	raid.player.global_position = eye - Vector3(0, 1.7, 0)
	raid.player.visible = false
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 3000.0
	raid.add_child(cam)
	cam.make_current()
	var aim := raid._stand(Vector3(-60, 0, -30)) + Vector3(0, 6, 0)
	cam.look_at_from_position(eye, aim)
	# Each shot looks across the nearest fight's line from its side, far
	# enough out that nothing is faded: wide from above, close at eye height.
	var shots := [["wide", 60.0, 420, 100.0, 30.0], ["close", 30.0, 520, 74.0, 4.0], ["later", 60.0, 700, 100.0, 30.0]]
	var frame := 0
	var battle: Node = null
	for i in shots.size():
		var shot: Array = shots[i]
		while frame < int(shot[2]):
			frame += 1
			raid.war.intensity = 0.8
			raid.war.centre = Vector3(-60, 0, -30)
			if frame == int(shot[2]) - 40:
				battle = raid.map.get_node_or_null("Battle")
				if battle != null:
					var near: Dictionary = {}
					for fight: Dictionary in battle.fight_list():
						if near.is_empty() or cam.global_position.distance_to(fight.centre) < cam.global_position.distance_to(near.centre):
							near = fight
					if not near.is_empty():
						var centre := raid._stand(near.centre)
						# The side with the clearest line onto the fight: from
						# across its line first, then round the compass.
						var side: Vector3 = (near.axis as Vector3).cross(Vector3.UP).normalized()
						var at := Vector3.ZERO
						var best := -INF
						for turn in 8:
							var dir := side.rotated(Vector3.UP, TAU * turn / 8.0)
							var spot := raid._stand(near.centre + dir * float(shot[3])) + Vector3(0, float(shot[4]), 0)
							var clear := INF
							for step in range(1, 10):
								var p := spot.lerp(centre + Vector3(0, 1.4, 0), step / 10.0)
								clear = minf(clear, p.y - float(raid.map.call("ground_height", p.x, p.z)))
							if clear > best + 0.5:
								best = clear
								at = spot
						cam.fov = float(shot[1])
						cam.look_at_from_position(at, centre + Vector3(0, 1.4, 0))
			await v.get_tree().process_frame
		await v.get_tree().process_frame
		await RenderingServer.frame_post_draw
		if battle != null:
			var shown := 0
			for soldier: Dictionary in battle.soldiers():
				shown += 1 if float(soldier.fade) > 0.0 else 0
			print("battle: baked ", battle.baked.keys(), ", fights ", battle.fight_list().map(func(f: Dictionary) -> Vector3: return f.centre),
					", extras shown ", shown, " of ", battle.soldiers().size())
		var file := "battle_%d_%s.png" % [i + 1, shot[0]]
		v.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
		print("saved ", file)
	raid.queue_free()
