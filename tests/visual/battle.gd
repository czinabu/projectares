extends RefCounted
## `--battle-only`, a mode `visual_check.gd` finds by itself. The scenery
## army on the battle shelves past the rim, as a player sees it from the
## field: from the middle, from across the field and from the rim's foot,
## looking out at each shelf, in a hot war. `--fov <deg>` narrows the view.


static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.visible = false
	raid.player.visible = false
	var fov := 70.0
	var at_fov := args.find("--fov")
	if at_fov >= 0 and at_fov + 1 < args.size():
		fov = float(args[at_fov + 1])
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 3000.0
	raid.add_child(cam)
	cam.make_current()
	var map: Node = raid.map
	# Let the war heat up and the fights come up on the shelves.
	raid.player.global_position = raid._stand(Vector3(0, 0, 0))
	cam.look_at_from_position(raid._stand(Vector3.ZERO) + Vector3(0, 1.7, 0), Vector3(400, 60, 150))
	for frame in 360:
		raid.war.intensity = 0.85
		raid.war.centre = Vector3(0, 0, 0)
		await v.get_tree().process_frame
	var shelves: Array = map.get("SHELVES")
	var names := ["east", "west", "north"]
	# [name, where on the field, eye height].
	var spots := [["middle", 0.0, 1.7], ["across", -0.6, 1.7], ["rim_foot", 0.7, 1.7]]
	for s in shelves.size():
		var shelf: Dictionary = shelves[s]
		var out: Vector2 = shelf["out"]
		var lateral: Vector2 = shelf["lateral"]
		var along := Vector2(-out.y, out.x)
		var mid := along * (lateral.x + lateral.y) * 0.5
		var target2 := out * 440.0 + mid
		# Aim at a fight on this shelf when there is one.
		var battle_now: Node = map.get_node_or_null("Battle")
		if battle_now != null:
			for fight: Dictionary in battle_now.fight_list():
				var c: Vector3 = fight.centre
				if Vector2(c.x, c.z).dot(out) > 300.0:
					target2 = Vector2(c.x, c.z)
					break
		var target := Vector3(target2.x, float(map.call("scenery_height", target2.x, target2.y)) + 4.0, target2.y)
		for spot: Array in spots:
			var from2 := out * 276.0 * float(spot[1]) + mid * 0.5
			var eye := raid._stand(Vector3(from2.x, 0, from2.y)) + Vector3(0, float(spot[2]), 0)
			raid.player.global_position = eye - Vector3(0, 1.7, 0)
			cam.look_at_from_position(eye, target)
			for frame in 90:
				raid.war.intensity = 0.85
				await v.get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file := "battle_%s_%s.png" % [names[s], spot[0]]
			v.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
			print("saved ", file)
	var battle: Node = map.get_node_or_null("Battle")
	if battle != null:
		var shown := 0
		for soldier: Dictionary in battle.soldiers():
			shown += 1 if float(soldier.fade) > 0.0 else 0
		print("battle: fights ", battle.fight_list().size(), ", extras shown ", shown, " of ", battle.soldiers().size())
	raid.queue_free()
