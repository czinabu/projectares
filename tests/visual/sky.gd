extends RefCounted
## `--sky-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --sidearms-only` shoots each sidearm model side on.
## `-- <output_dir> --impacts-only`: bullet marks and puffs on a wall, a
## spark off a body, and every hit marker kind in a row (impacts.png).
## `-- <output_dir> --shells-only`: a salvo of the war's artillery in
## Ashfront from where a player stands, from the red marks to the dirt
## column left after (shells_1_marked.png to shells_5_after.png). Run with
## `--fixed-fps 60`.
## `-- <output_dir> --battle-only`: Ashfront's scenery army from where a
## player stands, wide and through a narrow view (battle_1_wide.png,
## battle_2_close.png, battle_3_later.png). Run with `--fixed-fps 60`.
## `-- <output_dir> --sky-only`: Ashfront's busy low sky from Signal Hill:
## a gunship raking a fight, fighters going over, a dropship falling and
## its crash (sky_1_gunship.png to sky_4_crash.png). Run with `--fixed-fps 60`.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.visible = false
	var eye := raid._stand(Vector3(-140, 0, -108)) + Vector3(0, 2.0, 0)
	raid.player.global_position = eye - Vector3(0, 1.7, 0)
	raid.player.visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 3000.0
	raid.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(eye, raid._stand(Vector3(-60, 0, -30)) + Vector3(0, 40, 0))
	var sky: Node = raid.map.get_node_or_null("LowSky")
	if sky == null:
		push_error("no low sky")
		raid.queue_free()
		return
	sky.set("_next_gunship", 9999.0)
	sky.set("_next_pair", 9999.0)
	sky.set("_next_wreck", 9999.0)
	# The army needs a while to place its fights first.
	for i in 200:
		raid.war.intensity = 0.9
		raid.war.centre = Vector3(-60, 0, -30)
		await v.get_tree().process_frame
	var run: Dictionary = sky.call("send_gunship")
	run.t = (sky.GUNSHIP_RUN - sky.STRAFE_REACH * 0.7) / sky.GUNSHIP_SPEED
	var pair: Dictionary = {}
	var wreck: Dictionary = {}
	var beats := [["gunship", 70], ["fighters", 50], ["wreck", 90], ["crash", 150]]
	for i in beats.size():
		var beat: Array = beats[i]
		if beat[0] == "fighters":
			pair = sky.call("send_fighters")
			var way: Vector3 = pair.way
			var nearest: float = (eye - (pair.from as Vector3)).dot(way) / float(sky.FIGHTER_SPEED)
			pair.t = nearest - 3.2
		elif beat[0] == "wreck":
			wreck = sky.call("drop_wreck")
			wreck.t = float(wreck.time) * 0.4
		elif beat[0] == "crash":
			wreck.t = maxf(float(wreck.t), float(wreck.time) - 0.4)
		var frames := int(beat[1])
		for f in frames:
			raid.war.intensity = 0.9
			# Each from close by beside it, so it reads in a still.
			var look := Vector3.INF
			var from := eye
			var fov := 45.0
			match beat[0]:
				"gunship":
					if not sky._gunships.is_empty():
						look = sky.gunship_at(run)
						var side := Vector3(-run.way.z, 0.0, run.way.x)
						from = look + side * 110.0 - Vector3(0, 45, 0) - (run.way as Vector3) * 40.0
				"fighters":
					look = sky.lead_at(pair)
					from = look + Vector3(-pair.way.z, 0.0, pair.way.x) * 90.0 - Vector3(0, 30, 0) + (pair.way as Vector3) * 120.0
				"wreck":
					look = sky.wreck_point(wreck.from, wreck.to, float(wreck.t) / float(wreck.time))
					var toward := (Vector3(wreck.to.x, 0, wreck.to.z) - Vector3(wreck.from.x, 0, wreck.from.z)).normalized()
					from = look + Vector3(-toward.z, 0, toward.x) * 160.0 - Vector3(0, 40, 0)
				"crash":
					# From the field, out over the rim, as a player sees it.
					var out := Vector3(wreck.to.x, 0, wreck.to.z).normalized()
					from = raid._stand(out * float(sky.field) * 0.35) + Vector3(0, 8, 0)
					look = (wreck.to as Vector3) + Vector3(0, 40, 0)
					fov = 60.0
			if look.is_finite():
				cam.fov = fov
				cam.look_at_from_position(from, look)
			await v.get_tree().process_frame
		await RenderingServer.frame_post_draw
		print("sky: gunships ", sky._gunships.size(), ", tracers ", sky._tracers.size(), ", pairs ", sky._pairs.size(), ", wrecks ", sky._wrecks.size())
		var file := "sky_%d_%s.png" % [i + 1, beat[0]]
		v.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
		print("saved ", file)
	raid.queue_free()
