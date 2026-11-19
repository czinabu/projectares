extends RefCounted
## `--shells-only`, a mode `visual_check.gd` finds by itself.


## A contact sheet of each sidearm's model, side on and from three quarters.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	raid.player.visible = false
	var eye := raid._stand(Vector3(-168, 0, 10)) + Vector3(0, 1.7, 0)
	raid.player.global_position = eye + Vector3(0, -1.7, -60)
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 3000.0
	raid.add_child(cam)
	cam.make_current()
	var aim := raid._stand(Vector3(-140, 0, 14))
	cam.look_at_from_position(eye, aim + Vector3(0, 5, 0))
	await v._settle(30)
	var shells := raid.shelling
	shells.shells = Vector2i(4, 4)
	shells.call_at(raid, aim, deg_to_rad(20.0))
	# Seconds into the salvo for each shot: marked, about to land, the
	# blast, the dirt thrown up, and the column after.
	var beats := [["marked", 1.0], ["incoming", shells.warning - 0.15], ["blast", shells.warning + 0.12],
			["thrown", shells.warning + shells.stagger * 3.0 + 0.6], ["after", shells.warning + shells.stagger * 3.0 + 5.0]]
	# Run with `--fixed-fps 60`, so each frame is a sixtieth of a second.
	var frame := 0
	for i in beats.size():
		var beat: Array = beats[i]
		while frame < int(float(beat[1]) * 60.0):
			frame += 1
			await v.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := "shells_%d_%s.png" % [i + 1, beat[0]]
		v.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
		print("saved ", file)
	raid.queue_free()
