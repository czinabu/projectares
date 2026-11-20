extends RefCounted
## How a gun sits on the body through every way of moving, measured on the
## posed bones (inside `skeleton_updated`), the same body in both views:
## the off hand on the gun wherever both hands hold it, the gun pointed
## where it shoots in a fight, and some of the gun in the first-person
## frame in every hold (the camera is the eyes, so a gun carried below them
## disappears from the player's own view).

## [name, local velocity as a share of walk speed (x right, z back), slide,
## crouch, shooting, aiming]
const MOVES := [
	["stand hip", Vector3.ZERO, false, false, true, false],
	["stand aim", Vector3.ZERO, false, false, false, true],
	["jog", Vector3(0, 0, -1), false, false, false, false],
	["sprint", Vector3(0, 0, -1.6), false, false, false, false],
	["strafe", Vector3(-1, 0, 0), false, false, false, false],
	["run and shoot", Vector3(0, 0, -1), false, false, true, false],
	["slide", Vector3(0, 0, -1.8), true, false, false, false],
	["crouch walk", Vector3(0, 0, -0.5), false, true, false, false],
	["crouch hip", Vector3.ZERO, false, true, true, false],
]


static func run(t: Node) -> void:
	print("Guns held on the body through every way of moving")
	Look.enabled = true
	for id: String in ["rifle_carbine", "pistol_service"]:
		await _check_gun(t, id)
	Look.enabled = false


static func _check_gun(t: Node, id: String) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, [id, "blade_scrap", "plate_light"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	await t.frames(5)
	var p := raid.player
	for i in p.weapons.size():
		if p.weapons[i] is Gun and p.weapons[i].item_id == id:
			p._draw_weapon(i)
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await t.frames(60)
	p.set_physics_process(false)
	controller.set_physics_process(false)
	controller.view_mode = PlayerController.ViewMode.FIRST
	controller.pitch = -0.1
	p.cmd.pitch = controller.pitch
	p.cmd.yaw = controller.yaw
	var gun := p.get_active_weapon() as Gun
	var skin = p.get_node("Skin")
	var arm = skin.arm
	var skel: Skeleton3D = arm.skeleton
	var cam := controller.camera
	for move: Array in MOVES:
		var name: String = move[0]
		var low: bool = move[3]
		var hold := func() -> void:
			p.velocity = p.global_basis * ((move[1] as Vector3) * p.walk_speed)
			p.slide_left = 0.5 if move[2] else 0.0
			p.slide_low = 1.0 if move[2] else 0.0
			p.cmd.crouch = low
			p.crouched = low
			p.crouch = 1.0 if low else 0.0
			p.cmd.primary = move[4]
			p.cmd.secondary = move[5]
			gun._aiming = move[5]
		# A second and a half of game time, however fast the frames run.
		var waited := 0.0
		while waited < 1.5:
			hold.call()
			await t.get_tree().process_frame
			waited += t.get_process_delta_time()
		var seen := {}
		var catch := func() -> void:
			var at: Variant = ActionPose.hold_local(gun)
			if at == null:
				return
			var hold_at: Transform3D = at
			seen["grip"] = gun.visual.global_transform * hold_at.origin
			var fore := gun.visual.get_node_or_null("ForeGrip") as Node3D
			if fore == null:
				fore = gun.visual.get_node_or_null("Model/ForeGrip") as Node3D
			seen["fore"] = fore.global_position if fore != null else seen["grip"]
			seen["muzzle"] = gun.muzzle_point(p.hand.global_position)
			seen["ahead"] = -gun.visual.global_basis.z.normalized()
			if arm._off_hold_point != null:
				var off: Transform3D = skel.get_bone_global_pose(arm._off_wrist)
				seen["off_fist"] = skel.global_transform * (off * (arm._off_hold_point as Vector3))
		skel.skeleton_updated.connect(catch)
		for i in 3:
			hold.call()
			await t.get_tree().process_frame
		skel.skeleton_updated.disconnect(catch)
		if not seen.has("grip"):
			t.check(false, "%s, %s: posed" % [id, name])
			continue
		# A sidearm comes into one hand in a sprint or a slide, the other arm
		# free to pump or catch the ground.
		var both := not gun.is_sidearm or name not in ["sprint", "slide"]
		if seen.has("off_fist") and both:
			var front: Vector3 = seen["grip"] if gun.is_sidearm else seen["fore"]
			var line := Geometry3D.get_closest_point_to_segment(seen["off_fist"], front, seen["grip"])
			var gap: float = (seen["off_fist"] as Vector3).distance_to(line)
			t.check(gap < 0.07, "%s, %s: the off hand holds the gun (%.3f m off)" % [id, name, gap])
		if move[4] or move[5]:
			var aim := p.global_basis * Basis(Vector3.RIGHT, p.cmd.pitch) * Vector3.FORWARD
			var off_aim := rad_to_deg((seen["ahead"] as Vector3).angle_to(aim))
			t.check(off_aim < 8.0, "%s, %s: the gun points where it shoots (%.1f deg off)" % [id, name, off_aim])
		# Some of the gun in the first-person frame: its grip, its muzzle or
		# the middle between them.
		var shown := 0
		for spot: Vector3 in [seen["grip"], seen["muzzle"], ((seen["grip"] as Vector3) + (seen["muzzle"] as Vector3)) * 0.5]:
			if not cam.is_position_behind(spot) and cam.is_position_in_frustum(spot):
				shown += 1
		# Carried out of a fight, the gun may sit low, but some of it shows.
		t.check(shown >= (2 if move[4] or move[5] else 1), "%s, %s: the gun shows in the first-person view (%d of 3 points)" % [id, name, shown])
	controller.queue_free()
	raid.queue_free()
	await t.frames(3)
