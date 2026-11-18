extends RefCounted
## The camera pass: the head looks where its owner aims (the same body in
## both views), and the third-person camera stands over the shoulder, clear
## of the sight line, and keeps out of walls without popping.


static func run(t: Node) -> void:
	print("Cameras and the head on the aim")
	await _check_head_follows_aim(t)
	await _check_third_person(t)
	await _check_shown_motion(t)
	await _check_steady_on_the_run(t)


## The face turns to the aim, up and down, and never further round than
## `Locomotion.look_reach` from the chest; it eases off while the phone is out.
static func _check_head_follows_aim(t: Node) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 34, ["rifle_carbine", "blade_scrap", "plate_light"])
	await t.frames(20)
	var p := raid.player
	var skin := p.get_node_or_null("Skin")
	t.check(skin != null and skin.locomotion != null and skin.locomotion._head >= 0,
			"the player wears a model with a head that can look")
	if skin == null or skin.locomotion == null or skin.locomotion._head < 0:
		Look.enabled = false
		raid.queue_free()
		return
	p.set_physics_process(false)
	var loco = skin.locomotion
	var skel: Skeleton3D = loco.skeleton
	var face := [Vector3.ZERO, Vector3.ZERO]
	# Bone poses are only final inside the skeleton's update.
	var read := func() -> void:
		if loco._head_ahead != Vector3.ZERO:
			face[0] = (skel.global_basis.orthonormalized() * loco._facing(loco._head, loco._head_ahead)).normalized()
			var chest: int = loco._spine[loco._spine.size() - 1]
			face[1] = (skel.global_basis.orthonormalized() * loco._facing(chest, loco._chest_ahead)).normalized()
	skel.skeleton_updated.connect(read)
	for pitch: float in [0.6, -0.6, 0.0]:
		p.cmd.pitch = pitch
		p.cmd.aim_dir = p.global_basis.orthonormalized() * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
		await t.frames(30)
		t.check(face[0].angle_to(p.cmd.aim_dir) < 0.12,
				"the face looks along the aim at pitch %.1f (%.2f rad off)" % [pitch, face[0].angle_to(p.cmd.aim_dir)])
	# Aimed straight behind (the body cannot be): the head turns only so far.
	p.cmd.aim_dir = -(p.global_basis.orthonormalized() * Vector3.FORWARD)
	await t.frames(40)
	t.check(face[0].angle_to(face[1]) < loco.look_reach + 0.1 and face[0].angle_to(face[1]) > loco.look_reach * 0.7,
			"aimed behind, the head turns as far as it can and no further (%.2f rad)" % face[0].angle_to(face[1]))
	p.cmd.aim_dir = p.global_basis.orthonormalized() * Vector3.FORWARD
	await t.frames(20)
	skel.skeleton_updated.disconnect(read)
	# The phone bends the neck itself; the look gives way to it.
	p.cmd.phone = true
	await t.frames(40)
	t.check(loco.look_weight < 0.05, "with the phone out the head reads the phone, not the aim")
	p.cmd.phone = false
	await t.frames(40)
	t.check(loco.look_weight > 0.95, "and goes back to the aim after")
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)


## Over the shoulder, further out when aiming, so the head is never on the
## sight line; a wall behind brings the camera in at once and lets it back
## out gently; a bigger vehicle is framed from further back.
static func _check_third_person(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 35, ["rifle_carbine", "blade_scrap"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	await t.frames(5)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await t.frames(5)
	p.set_physics_process(false)
	controller.set_physics_process(false)
	controller.pitch = 0.0
	controller.view_mode = PlayerController.ViewMode.THIRD
	var gun := p.weapons[0] as Gun
	p.active_weapon_index = 0
	var side_of := func() -> Vector3:
		var look := controller.camera.global_basis.orthonormalized()
		return look.inverse() * (controller.camera.global_position - p.get_eye_position())
	await t.frames(60)
	var rest: Vector3 = side_of.call()
	t.check(rest.x > 0.4 and rest.z > controller.third_person_distance * 0.9,
			"third person sits back over the right shoulder (%s)" % rest)
	gun._aiming = true
	p.cmd.secondary = true
	await t.frames(60)
	var aimed: Vector3 = side_of.call()
	t.check(aimed.z < rest.z - 0.4 and aimed.x >= rest.x,
			"aiming moves the camera in and out over the shoulder (%s)" % aimed)
	# The eyes stand this far off the camera's line through the crosshair.
	var off_line := Vector2(aimed.x, aimed.y).length()
	t.check(off_line > 0.45, "aimed, the head is clear of the sight line (%.2f m off it)" % off_line)
	gun._aiming = false
	p.cmd.secondary = false
	await t.frames(60)
	# A wall a metre behind the eyes.
	var behind := p.global_basis.orthonormalized() * Vector3.BACK
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(8, 6, 0.3)
	wall.add_child(shape)
	raid.add_child(wall)
	wall.global_transform = Transform3D(p.global_basis.orthonormalized(), p.get_eye_position() + behind * 1.15)
	await t.frames(3)
	var held: Vector3 = side_of.call()
	t.check(held.z < 1.0 - controller.camera_radius + 0.05, "a wall behind brings the camera in at once (%.2f m back)" % held.z)
	wall.queue_free()
	await t.frames(3)
	var easing: Vector3 = side_of.call()
	t.check(easing.z < controller.third_person_distance - 0.3, "and it eases back out, not in one jump (%.2f m)" % easing.z)
	await t.frames(90)
	t.check((side_of.call() as Vector3).z > controller.third_person_distance * 0.9, "until it is back where it was")
	# Framing a vehicle by its size.
	var bike: Node3D = raid.spawn_vehicle("bike_scrapper", p.global_position + Vector3(4, 0.3, 0), 0.0)
	var rover_id := "rover_warden"
	await t.frames(3)
	bike.mount(p)
	var on_bike := controller.view_distance(false)
	t.check(is_equal_approx(controller.ride_scale(), 1.0), "a bike is framed as a bike")
	bike.dismount()
	if rover_id != "":
		var rover: Node3D = raid.spawn_vehicle(rover_id, p.global_position + Vector3(-6, 0.3, 0), 0.0)
		await t.frames(3)
		rover.mount(p)
		t.check(controller.view_distance(false) > on_bike + 0.5, "a rover is framed from further back than a bike")
	raid.queue_free()
	await t.frames(2)


## Between ticks a body is shown on its way from the last tick to the next,
## and put back where the simulation left it before the next tick.
static func _check_shown_motion(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 36, ["rifle_carbine"])
	await t.frames(3)
	var p := raid.player
	p.set_physics_process(false)
	var motion := ShownMotion.new()
	motion.name = "ShownMotion"
	p.add_child(motion)
	motion.set_process(false)
	t.check(ShownMotion.of(p) == motion, "a body's shown motion is found on it")
	var a := p.global_position
	motion.show_at(100, 0.0)
	p.global_position = a + Vector3(1.0, 0.0, 0.0)
	motion.show_at(101, 0.5)
	t.check(p.global_position.distance_to(a + Vector3(0.5, 0.0, 0.0)) < 0.001,
			"half way between ticks the body is shown half way along its move")
	motion.show_at(101, 0.75)
	t.check(p.global_position.distance_to(a + Vector3(0.75, 0.0, 0.0)) < 0.001, "and further along later in the frame")
	motion.restore()
	t.check(p.global_position.distance_to(a + Vector3(1.0, 0.0, 0.0)) < 0.001,
			"before the next tick it is back where the simulation left it")
	p.global_position = a + Vector3(20.0, 0.0, 0.0)
	motion.show_at(102, 0.5)
	t.check(p.global_position.distance_to(a + Vector3(20.0, 0.0, 0.0)) < 0.001, "a jump is shown at once, not slid across")
	motion.restore()
	motion.live_yaw = 1.0
	motion.show_at(102, 0.5)
	t.check(absf(wrapf(p.global_rotation.y - 1.0, -PI, PI)) < 0.001, "the player's own body turns with the mouse every frame")
	# Moved by something else while shown (a teleport): left there.
	p.global_position = a + Vector3(-5.0, 0.0, 0.0)
	motion.restore()
	t.check(p.global_position.distance_to(a + Vector3(-5.0, 0.0, 0.0)) < 0.001, "a body moved while shown stays where it was put")
	raid.queue_free()
	await t.frames(2)


## First person on the run, not aiming: the carried gun and the raised
## watch stay put in the view rather than bobbing with every stride
## (playtest feedback), and the watch is in view crouched too.
static func _check_steady_on_the_run(t: Node) -> void:
	Look.enabled = true
	for what: String in ["gun", "watch", "watch crouched"]:
		var raid := Raid.new()
		t.add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap"])
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -500, 0)
		await t.frames(3)
		var p := raid.player
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		controller.set_physics_process(false)
		controller.view_mode = PlayerController.ViewMode.FIRST
		# Along open ground.
		controller.yaw = 1.57
		var skel := p.find_child("*Skeleton*", true, false) as Skeleton3D
		var cam := controller.camera
		var span := [Vector3.INF, -Vector3.INF]
		var seen := [0, 0]
		var watching := what != "gun"
		# Read as drawn, inside the skeleton's update.
		var read := func() -> void:
			seen[0] += 1
			if seen[0] < 150:
				return
			var at: Vector3
			if watching:
				var wrist := skel.find_bone(Hud.Wrist.WRIST_BONE)
				at = skel.global_transform * skel.get_bone_global_pose(wrist).origin
			else:
				at = (p.get_active_weapon() as Gun).muzzle_point(p.hand.global_position)
			if not cam.is_position_behind(at) and cam.is_position_in_frustum(at):
				seen[1] += 1
			var local := cam.global_transform.affine_inverse() * at
			span[0] = (span[0] as Vector3).min(local)
			span[1] = (span[1] as Vector3).max(local)
		skel.skeleton_updated.connect(read)
		for i in 300:
			p.cmd.move = Vector2(0, 1)
			p.cmd.crouch = what == "watch crouched"
			p.cmd.watch_up = watching
			await t.get_tree().process_frame
		skel.skeleton_updated.disconnect(read)
		var swing: Vector3 = ((span[1] as Vector3) - (span[0] as Vector3)) * 1000.0
		var speed := Vector2(p.velocity.x, p.velocity.z).length()
		var counted: int = seen[0] - 149
		if what == "gun":
			t.check(speed > p.walk_speed * 0.8 and swing.x < 40.0 and swing.y < 40.0,
					"running, the carried gun holds still in the view (%.0f mm side, %.0f mm up and down at %.1f m/s)" % [swing.x, swing.y, speed])
		else:
			t.check(seen[1] >= counted and counted > 100,
					"%s, the raised watch stays in view (%d of %d frames)" % [what, seen[1], counted])
			t.check(swing.x < 35.0 and swing.y < 35.0,
					"%s on the move, the raised watch holds still in the view (%.0f mm side, %.0f mm up and down)" % [what, swing.x, swing.y])
		controller.queue_free()
		raid.queue_free()
		await t.frames(3)
	Look.enabled = false
