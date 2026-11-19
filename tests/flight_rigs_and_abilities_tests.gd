extends RefCounted
## The `flight_rigs_and_abilities` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Flight rigs and abilities")
	var press_jump := func(a: Actor) -> void:
		a.cmd.jump_pressed = true
		await t.frames(1)
		a.cmd.jump_pressed = false

	# Thruster boots: kicks and dashes on charges, a short skim, no heat.
	var raid: Raid = await t._kit_raid(60, ["rifle_scrap", "blade_scrap", "boots_thruster", "plate_light"])
	var p := raid.player
	t.check(p.flight.display_name == "Mk1 Thruster Boots" and p.flight.burst_velocity > 0.0
			and is_zero_approx(p.flight.thrust_accel) and p.flight.can_skim(), "boots stats come from the item")
	t.check(p.flight.max_charges == 4 and p.flight.charges == 4, "Mk1 boots carry 4 charges, full when put on")
	await press_jump.call(p)
	await t.frames(10)
	var height := p.global_position.y
	await press_jump.call(p)
	t.check(p.velocity.y > 8.0 and p.flight.charges == 3 and is_zero_approx(p.flight.heat),
			"pressing jump in the air kicks you upward on a charge, not heat")
	await t.frames(15)
	t.check(p.global_position.y > height + 1.0, "the kick gains height")
	p.cmd.move = Vector2(1, 0)
	var side_before := (p.global_basis.inverse() * p.velocity).x
	await press_jump.call(p)
	t.check((p.global_basis.inverse() * p.velocity).x > side_before + 5.0, "boots kick you the way you steer")
	p.cmd.move = Vector2.ZERO
	for i in 3:
		await press_jump.call(p)
		await t.frames(2)
	t.check(p.flight.charges == 0, "kicking over and over spends the charges (%d left)" % p.flight.charges)
	var vy := p.velocity.y
	await press_jump.call(p)
	t.check(p.velocity.y <= vy, "boots out of charges do nothing")
	await t.frames(int(p.flight.charge_time * 60.0) + 2)
	t.check(p.flight.charges == 1, "a charge comes back every %.1f s, even in the air" % p.flight.charge_time)
	p.cmd.jump = true
	await t.frames(2)
	t.check(not p.flight.is_hovering, "boots cannot hover")
	p.cmd.jump = false
	for i in 400:
		await t.get_tree().physics_frame
		if p.is_on_floor():
			break
	await t._check_boot_skim(p)
	await t._end_raid(raid)

	# Glide wings: launch, then fall slowly and travel far.
	raid = await t._kit_raid(61, ["rifle_scrap", "blade_scrap", "wings_glide", "plate_light"])
	p = raid.player
	# These check the handling high up, not the ceiling (`_test_rig_tiers`).
	p.flight.ceiling = 0.0
	p.global_position += Vector3(0, 30, 0)
	p.velocity = Vector3.ZERO
	await t.frames(30)
	t.check(p.velocity.y < -5.0 and not p.flight.is_gliding, "wings do nothing until you hold jump")
	p.cmd.jump = true
	var start := p.global_position
	await t.frames(60)
	t.check(p.flight.is_gliding and p.velocity.y >= -p.flight.glide_fall_speed - 0.01,
			"holding jump while falling glides at a gentle sink rate")
	var travelled := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	t.check(travelled > 8.0, "gliding carries you forward (%.1f m in a second)" % travelled)
	p.cmd.jump = false
	await t.frames(5)
	t.check(not p.flight.is_gliding, "letting go stops the glide")
	await t._check_glide_flying(p)
	await t._check_wing_moves(p)
	await t._end_raid(raid)

	# The Mk2 jetpack: cruise, wide turns, coasting, a steady hover to shoot from.
	raid = await t._kit_raid(65, ["rifle_scrap", "blade_scrap", "jetpack_mk2", "frame_bulwark"])
	raid.player.flight.ceiling = 0.0
	await t._check_jetpack_cruise(raid.player)
	await t._end_raid(raid)

	# The jetpack still works and does not burst or glide.
	raid = await t._kit_raid(62, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"])
	p = raid.player
	p.flight.ceiling = 0.0
	await press_jump.call(p)
	await t.frames(10)
	p.cmd.jump = true
	await press_jump.call(p)
	await t.frames(30)
	t.check(p.flight.is_thrusting and not p.flight.is_gliding and not p.is_on_floor(),
			"the jetpack still flies by holding jump")
	p.cmd.jump = false
	await t._check_free_flight(p)
	t.check(not p.ability.enabled and p.ability.status_text() == "", "no ability without an ability item")
	p.cmd.ability_pressed = true
	await t.frames(2)
	p.cmd.ability_pressed = false
	t.check(p.ability.cooldown_left <= 0.0, "pressing the ability key with none equipped does nothing")
	await t._end_raid(raid)

	# Phase Step.
	raid = await t._kit_raid(63, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_blink"])
	p = raid.player
	t.check(p.ability.enabled and p.ability.effect == "blink" and "chip_blink" in p.gear_items,
			"an ability item equips into the ability slot")
	var arena := raid.depots[0].global_position
	p.global_position = Vector3(arena.x, arena.y - 1.9, arena.z + 3.0)
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD
	await t.frames(5)
	var before_pos := p.global_position
	p.cmd.ability_pressed = true
	await t.frames(1)
	p.cmd.ability_pressed = false
	var moved := before_pos.distance_to(p.global_position)
	t.check(moved > 2.0 and moved <= p.ability.blink_range + 0.5, "Phase Step moves you forward (%.1f m)" % moved)
	t.check(p.ability.cooldown_left > 0.0 and not p.ability.is_ready(), "an ability goes on cooldown")
	before_pos = p.global_position
	p.cmd.ability_pressed = true
	await t.frames(2)
	p.cmd.ability_pressed = false
	t.check(before_pos.distance_to(p.global_position) < 0.5, "an ability cannot be used while on cooldown")
	p.ability.cooldown_left = 0.0
	p.cmd.aim_dir = Vector3.DOWN
	await t.frames(2)
	p.cmd.ability_pressed = true
	await t.frames(1)
	p.cmd.ability_pressed = false
	await t.frames(10)
	t.check(p.global_position.y > arena.y - 2.5, "Phase Step stops short of the ground and walls")
	await t._end_raid(raid)

	# Kinetic Barrier.
	raid = await t._kit_raid(64, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_barrier"])
	p = raid.player
	var foe := raid.bots[0]
	var total := func() -> float: return p.health.health + p.health.armor
	var before: float = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	t.check(is_equal_approx(before - total.call(), 20.0), "without the barrier a hit lands in full")
	p.cmd.ability_pressed = true
	await t.frames(1)
	p.cmd.ability_pressed = false
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	t.check(p.ability.is_active() and is_equal_approx(before - total.call(), 8.0), "the barrier cuts damage by 60%")
	await t.frames(int(p.ability.duration * 60.0) + 10)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	t.check(not p.ability.is_active() and is_equal_approx(before - total.call(), 20.0), "the barrier runs out")
	await t._end_raid(raid)

	# Shock Pulse.
	raid = await t._kit_raid(65, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_pulse"])
	p = raid.player
	var near := raid.bots[0]
	var far := raid.bots[1]
	near.global_position = p.global_position + Vector3(3, 0, 0)
	far.global_position = p.global_position + Vector3(30, 0, 0)
	await t.frames(3)
	var near_before := near.health.health + near.health.armor
	var far_before := far.health.health + far.health.armor
	p.cmd.ability_pressed = true
	await t.frames(1)
	p.cmd.ability_pressed = false
	t.check(near.health.health + near.health.armor < near_before and near.stagger_left > 0.0,
			"Shock Pulse hurts and staggers someone close")
	t.check(is_equal_approx(far.health.health + far.health.armor, far_before) and far.stagger_left <= 0.0,
			"Shock Pulse does not reach someone far away")
	await t._end_raid(raid)

	# Stash, hub and crates.
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["chip_pulse", "wings_glide"])
	t.check(Profile.equip("ability", "chip_pulse") and Profile.equip("rig", "wings_glide")
			and not Profile.equip("ability", "wings_glide"), "abilities and rigs equip into their own slots")
	var kit := Profile.checkout_loadout(Worlds.get_world("ashfront"))
	t.check("chip_pulse" in kit and "wings_glide" in kit and "jetpack_mk1" not in kit,
			"the kit carries the chosen ability and rig")
	Profile.reset()
	Profile.welcome_granted = true
	kit = Profile.checkout_loadout(Worlds.get_world("ashfront"))
	var has_ability := false
	for id in kit:
		if ItemDB.has_tag(id, "ability"):
			has_ability = true
	t.check(not has_ability, "an empty ability slot deploys with no ability")
	Profile.grant_gear_crates()
	t.check(Profile.stash.is_empty() and Profile.GEAR_CRATES.is_empty(),
			"no free test-gear crate goes to every player (dev mode has the gear)")
	Profile.reset()
	Profile.grant_welcome_crate()
	var welcome := Profile.stash.size()
	Profile.grant_welcome_crate()
	t.check(welcome == Profile.WELCOME_CRATE.size() and Profile.stash.size() == welcome
			and "bike_scrapper" in Profile.stash and "wings_glide" not in Profile.stash
			and Profile.base_upgrades.is_empty() and Profile.blueprints.is_empty(),
			"a new player gets the welcome crate once, with the starter bike, and a starter bunker")
	Profile.reset()


## A flat test ground with a jump ramp, away from any raid map.
