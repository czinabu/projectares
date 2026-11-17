extends RefCounted
## Handling: a gun is steadiest still and aimed. Moving widens the hip spread
## by speed, a sprint costs a beat before the gun can fire (and pulling the
## trigger ends it), and aimed spread comes in over the gun's `ads_time`.


static func run(t: Node) -> void:
	print("Gun handling")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 53, ["rifle_carbine", "pistol_service"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(10)
	var p := raid.player
	var at := Vector3(0, 400, -4600)
	var floor := StaticBody3D.new()
	floor.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(400, 1, 400)
	var col := CollisionShape3D.new()
	col.shape = shape
	floor.add_child(col)
	raid.add_child(floor)
	floor.global_position = at - Vector3(0, 0.5, 0)
	for bot in raid.bots:
		bot.global_position = at + Vector3(randf_range(-150, 150), 0, 180)
	p.global_position = at
	p.protected_left = 0.0
	p.active_weapon_index = 0
	var gun := p.weapons[0] as Gun
	gun.reserve_ammo = 500
	await t.frames(20)

	# Standing still, then moving: the hip spread widens with speed.
	var still := gun.current_spread_deg()
	p.cmd.move = Vector2(0, 1)
	await t.frames(40)
	var walking := gun.current_spread_deg()
	p.cmd.sprint = true
	await t.frames(40)
	var sprinting := gun.current_spread_deg()
	t.check(gun.move_share() > 0.9, "a sprint is full speed for the spread (%.2f)" % gun.move_share())
	t.check(still < walking and walking < sprinting,
			"hip spread grows with speed: still %.2f, walk %.2f, sprint %.2f" % [still, walking, sprinting])

	# Pulling the trigger mid-sprint ends the sprint, and the gun fires once
	# it has come up.
	t.check(p.sprint_recover > 0.0, "a sprint keeps the gun down")
	var before := gun.ammo_in_mag
	p.cmd.primary = true
	await t.frames(2)
	t.check(gun.ammo_in_mag == before, "the first instant of the pull fires nothing")
	var waited := 0
	while gun.ammo_in_mag == before and waited < 60:
		await t.frames(1)
		waited += 1
	var horizontal := Vector2(p.velocity.x, p.velocity.z).length()
	t.check(gun.ammo_in_mag < before and waited >= 8 and waited <= 16,
			"the gun fires about %.2f s after the pull (%d ticks)" % [p.sprint_out_time, waited + 2])
	t.check(horizontal <= p.walk_speed * 1.05, "pulling the trigger ended the sprint (%.1f m/s)" % horizontal)
	p.cmd.primary = false
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	await t.frames(40)

	# A semi-auto pull made while the gun comes up from a sprint is kept.
	p.active_weapon_index = 1
	var pistol := p.weapons[1] as Gun
	await t.frames(5)
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	await t.frames(30)
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	var rounds := pistol.ammo_in_mag
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	await t.frames(30)
	t.check(pistol.ammo_in_mag == rounds - 1, "a click while the gun comes up from a sprint fires once it is up")
	p.active_weapon_index = 0
	await t.frames(30)

	# Aimed spread comes in over the gun's ads_time.
	var hip := gun.current_spread_deg()
	p.cmd.secondary = true
	await t.frames(2)
	var snap := gun.current_spread_deg()
	await t.frames(int(gun.ads_time * 60.0) + 5)
	var settled := gun.current_spread_deg()
	t.check(snap < hip and settled < snap,
			"aiming tightens over %.2f s: hip %.2f, a snap %.2f, settled %.2f" % [gun.ads_time, hip, snap, settled])
	t.check(is_equal_approx(gun.aim_in(), 1.0), "the gun is fully up")
	p.cmd.secondary = false
	await t.frames(2)
	t.check(gun.aim_in() == 0.0, "letting go drops it at once")
	t.check(ItemDB.item_stats("pistol_service").get("ads_time", 0.25) < ItemDB.item_stats("dmr_longshot").get("ads_time", 0.25),
			"a pistol comes up quicker than a marksman rifle")
	floor.queue_free()
	raid.queue_free()
	await t.frames(2)
