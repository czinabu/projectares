extends RefCounted
## Checks for what makes melee a real answer to guns: one- and two-handed
## weapons, blades past armor, the dash-strike, the back strike, the timed
## bullet deflect, and silent kills. Called from the test runner
## (`-- --groups melee_viability` runs just these).

const Arsenal := preload("res://tests/melee_arsenal_tests.gd")


static func run(t: Node) -> void:
	_data(t)
	_motion(t)
	await _in_raid(t)


static func _data(t: Node) -> void:
	print("Melee viability: hold classes, armor and small arms")
	var melee := 0
	var mismatched := []
	for id: String in ItemDB.all_ids():
		if not ItemDB.has_tag(id, "melee"):
			continue
		melee += 1
		if ItemDB.has_tag(id, "one_handed") == ItemDB.has_tag(id, "two_handed"):
			mismatched.append(id)
	t.check(melee >= 6 and mismatched.is_empty(),
			"every melee item is tagged one-handed or two-handed, never both (%s)" % [mismatched])
	var held := MeleeWeapon.new()
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "melee"):
			held.item_id = id
			if Look.is_two_handed(held) != ItemDB.has_tag(id, "two_handed"):
				t.check(false, "%s: the hands follow its hold tag" % id)
	held.free()

	var knife := Arsenal._make("knife_gutter")
	var sword := Arsenal._make("blade_scrap")
	var hammer := Arsenal._make("hammer_breaker")
	var spear := Arsenal._make("spear_lancer")
	t.check(hammer.is_two_handed() and spear.is_two_handed() and not sword.is_two_handed()
			and not knife.is_two_handed(), "the hammer and spear take both hands, the knife and sword one")
	t.check(knife.move_speed_mult() > sword.move_speed_mult() and sword.move_speed_mult() > 1.0
			and hammer.move_speed_mult() < 1.0 and spear.move_speed_mult() < 1.0,
			"one-handers move faster than empty hands (the knife fastest), two-handers slower")
	t.check(hammer.heavy_stagger_now() > 0.0 and sword.heavy_stagger_now() == 0.0
			and spear.heavy_stagger_now() >= spear.heavy_stagger,
			"a two-hander's heavy staggers, a one-hander's does not")
	t.check(hammer.armor_break_now() > 0.0 and sword.armor_break_now() == 0.0, "two-handers break armor")
	t.check(sword.stops_round("rifle_scrap") and sword.stops_round("pistol_service")
			and not sword.stops_round("dmr_longshot") and not sword.stops_round("power_rail_lance"),
			"a guard stops small arms, never a marksman round or a power weapon")
	t.check(sword.deflect_window <= 0.3 and sword.guard_rearm > 0.0 and sword.deflect_stamina > 0.0,
			"the deflect is short, has a cooldown and costs stamina")
	for blade in [knife, sword, hammer, spear]:
		blade.free()

	# Armor soaks a bullet, but a blade goes past it; a breaker tears it off.
	var health := HealthComponent.new()
	health.set_armor(50.0)
	var shot := DamageInfo.make(20.0, null, "bullet")
	var lost := health.apply_damage(shot)
	t.check(lost < 20.0 and health.armor < 50.0, "armor soaks part of a bullet")
	health.health = 100.0
	health.set_armor(50.0)
	var cut := DamageInfo.make(20.0, null, "melee")
	cut.armor_pierce = 1.0
	t.check(is_equal_approx(health.apply_damage(cut), 20.0) and is_equal_approx(health.armor, 50.0),
			"a blade goes straight past armor")
	cut.armor_break = 0.5
	health.apply_damage(cut)
	t.check(is_equal_approx(health.armor, 40.0), "an armor-breaking hit tears plates off")
	health.free()


## How each weapon's attacks are shown: its own swing style, a swing that
## speeds into the hit and eases out, a windup that keeps coiling.
static func _motion(t: Node) -> void:
	print("Melee viability: swing styles and timing")
	var styles := {}
	for id: String in ItemDB.all_ids():
		if not ItemDB.has_tag(id, "melee"):
			continue
		var blade := Arsenal._make(id)
		for style in [blade.swing_style, blade.heavy_style]:
			if style not in ["slash", "thrust", "chop", ""] or blade.swing_style == "":
				t.check(false, "%s has a known swing style" % id)
		styles[id] = [blade.swing_style, blade.heavy_style]
		blade.free()
	t.check(styles["spear_lancer"][0] == "thrust", "the spear thrusts")
	t.check(styles["axe_splitter"][0] == "chop" and styles["hammer_breaker"][0] == "chop", "the axe and hammer chop")
	t.check(styles["blade_scrap"][0] == "slash" and styles["blade_arc"][0] == "slash", "swords slash")
	t.check(styles["knife_gutter"] == ["slash", "thrust"], "the knife slashes, and its heavy is a stab")

	var sword := Arsenal._make("blade_scrap")
	sword._windup_kind = "light"
	sword._windup_left = 0.3
	sword._windup_total = 0.3
	sword._swing_lead = 0.09
	t.check(sword.swing_arc() < 0.0 and sword.windup_coil() == 0.0, "early in a windup no swing shows yet")
	sword._windup_left = 0.15
	var coil_mid := sword.windup_coil()
	sword._windup_left = 0.1
	t.check(sword.windup_coil() > coil_mid and coil_mid > 0.0, "the windup keeps drawing back as it goes on")
	sword._windup_left = 0.06
	var early := sword.swing_arc()
	sword._windup_left = 0.03
	var late := sword.swing_arc()
	t.check(early >= 0.0 and late > early and late - early > early, "the swing starts before the hit and speeds up into it")
	sword._windup_left = 0.0
	sword._swing_time = MeleeWeapon.SWING_TIME
	sword._swing_left = sword._swing_time
	t.check(is_equal_approx(sword.swing_arc(), 0.5), "the blade is mid-arc as the hit lands")
	sword._swing_left = sword._swing_time * 0.5
	var mid := sword.swing_arc()
	sword._swing_left = 0.0001
	t.check(mid > 0.5 and mid - 0.5 > sword.swing_arc() - mid, "and slows through the follow-through")
	sword.free()

	var pose := ActionPose.new()
	var spear := Arsenal._make("spear_lancer")
	var plain := Arsenal._make("blade_scrap")
	var axe := Arsenal._make("axe_splitter")
	var knife := Arsenal._make("knife_gutter")
	var right := MeleeWeapon.Dir.RIGHT
	t.check(pose.follow_reach(spear, right).z < -0.3 and pose.windup_reach(spear, right).z > 0.2,
			"a thrust draws the hand back, then drives it out ahead")
	t.check(pose.windup_reach(axe, right).y > pose.windup_reach(plain, right).y + 0.15,
			"a chop is raised higher than a slash")
	t.check(pose.follow_reach(axe, right).y < pose.follow_reach(plain, right).y, "and ends lower")
	t.check(pose.windup_reach(knife, MeleeWeapon.Dir.LEFT).length() < pose.windup_reach(plain, MeleeWeapon.Dir.LEFT).length(),
			"a knife's swings are tighter than a sword's")
	var hammer := Arsenal._make("hammer_breaker")
	hammer._shown_kind = "light"
	t.check(hammer.is_two_handed() and MeleeWeapon.TWO_HAND_SWING > 1.0, "a two-hander swings slower, with its weight")
	for blade in [spear, plain, axe, knife, hammer]:
		blade.free()
	pose.free()


static func _in_raid(t: Node) -> void:
	print("Melee viability: in a fight")
	var raid: Raid = await t._new_raid(54, false)
	var setup: Array = await t._duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var foe_blade: MeleeWeapon = setup[2]
	foe.health.max_health = 900.0
	p.protected_left = 0.0
	foe.protected_left = 0.0

	# A blade cut ignores the foe's armor.
	var sword := await Arsenal._arm(t, p, "blade_scrap")
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 2.0)
	foe.health.set_armor(80.0)
	await t.frames(1)
	Arsenal._place(p, foe, 2.0)
	var before := foe.health.health
	sword._strike(sword.light_damage, "light")
	t.check(is_equal_approx(before - foe.health.health, sword.light_damage) and is_equal_approx(foe.health.armor, 80.0),
			"an armored foe takes a blade's full damage, and the armor is untouched")

	# A two-handed heavy staggers and breaks armor.
	var hammer := await Arsenal._arm(t, p, "hammer_breaker")
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 2.0)
	foe.health.set_armor(80.0)
	await t.frames(1)
	Arsenal._place(p, foe, 2.0)
	hammer._strike(hammer.heavy_damage, "heavy")
	t.check(foe.stagger_left > 0.0 and foe.health.armor < 80.0, "a hammer heavy staggers and breaks armor")

	# The dash-strike: sprinting, a heavy reaches a foe 9 m away.
	sword = await Arsenal._arm(t, p, "blade_scrap")
	sword.heavy_stamina = 0.0
	sword.dash_stamina = 0.0
	var reached := func(sprint: bool) -> Array:
		Arsenal._reset(foe)
		p.velocity = Vector3.ZERO
		foe.global_position = p.global_position + Vector3(0, 0, -9.0)
		foe.cmd.yaw = PI
		foe.cmd.aim_dir = Vector3.BACK
		await t.frames(20)
		Arsenal._reset(foe)
		var start := p.global_position
		var hp := foe.health.health
		sword._sprinting = sprint
		sword._heavy_attack()
		var dashed := sword._dashing
		await t.frames(int(sword.heavy_windup * 60.0) + 6)
		return [start.distance_to(p.global_position), hp - foe.health.health, dashed]
	var walk: Array = await reached.call(false)
	var dash: Array = await reached.call(true)
	t.check(walk[1] == 0.0 and walk[0] < 4.5, "without a sprint the heavy only lunges a few metres and misses")
	t.check(dash[2] and dash[0] > 5.5 and dash[1] > 0.0, "sprinting, the heavy dashes about 9 m and lands")
	await t.frames(60)

	# The back strike: backing off with a foe right behind, a light stabs back.
	sword = await Arsenal._arm(t, p, "blade_scrap")
	var back_hit := func(backing: bool) -> float:
		Arsenal._reset(foe)
		foe.global_position = p.global_position + Vector3(0, 0, 1.6)
		await t.frames(1)
		foe.global_position = p.global_position + Vector3(0, 0, 1.6)
		var hp := foe.health.health
		sword._backing = backing
		sword._light_attack(0.0)
		await t.frames(int(sword.light_windup * 60.0) + 4)
		p.velocity = Vector3.ZERO
		sword._backing = false
		await t.frames(40)
		return hp - foe.health.health
	t.check(await back_hit.call(false) == 0.0, "a plain light misses a foe behind you")
	t.check(is_equal_approx(await back_hit.call(true), sword.light_damage * sword.back_strike_mult),
			"moving back, a light is a back strike that hits the foe behind")

	# The timed deflect, on the foe's blade, against the player's shots.
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 6.0)
	var bullet := func(id: String) -> DamageInfo:
		var info := DamageInfo.make(20.0, p, "bullet", foe.global_position)
		info.weapon_id = id
		Combat.deal(foe, info)
		return info
	foe.cmd.secondary = true
	await t.frames(3)
	var hp := foe.health.health
	var first: DamageInfo = bullet.call("rifle_scrap")
	var second: DamageInfo = bullet.call("rifle_scrap")
	t.check(first.parried and second.parried and foe.health.health == hp,
			"a guard raised just in time deflects every rifle round from the front")
	var marksman: DamageInfo = bullet.call("dmr_longshot")
	t.check(not marksman.parried and not marksman.blocked and foe.health.health < hp,
			"a marksman round goes through a fresh guard")
	await t.frames(int(foe_blade.deflect_window * 60.0) + 6)
	Arsenal._reset(foe)
	var late: DamageInfo = bullet.call("rifle_scrap")
	t.check(not late.parried and late.blocked and late.amount > 0.0,
			"after the window a held guard only turns aside part of a round")
	foe.cmd.secondary = false
	await t.frames(3)
	foe.cmd.secondary = true
	await t.frames(2)
	var spam: DamageInfo = bullet.call("rifle_scrap")
	t.check(not spam.parried, "a guard raised again straight away does not deflect")
	foe.cmd.secondary = false
	await t.frames(int(foe_blade.guard_rearm * 60.0) + 4)
	foe.cmd.secondary = true
	await t.frames(2)
	var stamina := foe.stamina
	var rearmed: DamageInfo = bullet.call("rifle_scrap")
	t.check(rearmed.parried and foe.stamina < stamina, "once it has rearmed it deflects again, for stamina")
	foe.cmd.secondary = false
	await t.frames(3)

	# Silent kills: gunfire brings a patrolling bot to look, a blade does not.
	var guard: Actor = raid.bots[1]
	var brain := guard.get_node("Brain") as BotBrain
	guard.global_position = p.global_position + Vector3(12.0, 0.0, 0.0)
	brain.state = BotBrain.State.PATROL
	var heard := [0]
	guard.heard.connect(func(_at: Vector3, _source: Actor) -> void: heard[0] += 1)
	sword = await Arsenal._arm(t, p, "blade_scrap")
	Arsenal._reset(foe)
	foe.health.max_health = 100.0
	foe.health.health = 10.0
	Arsenal._place(p, foe, 2.0)
	await t.frames(1)
	Arsenal._place(p, foe, 2.0)
	sword._strike(sword.light_damage, "light")
	await t.frames(2)
	t.check(foe.is_dead and heard[0] == 0 and brain.state == BotBrain.State.PATROL,
			"a blade kill makes no noise: the patrol nearby carries on")
	Combat.noise(guard, guard.global_position, 45.0)
	t.check(heard[0] == 0, "a bot's own gunfire never pulls patrols about")
	Combat.noise(p, p.global_position, 45.0)
	t.check(heard[0] == 1 and brain.state == BotBrain.State.CHASE, "a player's gunshot brings the patrol to look")
	await t._end_raid(raid)
