extends RefCounted
## The `melee_defense` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Block, parry and stamina")
	var raid: Raid = await t._new_raid(48, false)
	var setup: Array = await t._duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var total := func() -> float: return p.health.health + p.health.armor

	# Unblocked hit.
	var before: float = total.call()
	await t._foe_swing(foe)
	await t.frames(40)
	t.check(total.call() < before, "an unblocked swing hurts")

	# Held block: guard raised long before the hit lands.
	await t.frames(60)
	before = total.call()
	var stamina_before := p.stamina
	p.cmd.secondary = true
	await t.frames(30)
	await t._foe_swing(foe)
	await t.frames(40)
	t.check(is_equal_approx(total.call(), before), "a held block stops a melee hit")
	t.check(p.stamina < stamina_before, "blocking costs stamina")
	t.check(foe.stagger_left <= 0.0, "a plain block does not stagger the attacker")
	p.cmd.secondary = false

	# Parry: guard raised just before the hit lands (windup is 30 frames).
	await t.frames(90)
	before = total.call()
	stamina_before = p.stamina
	await t._foe_swing(foe)
	await t.frames(22)
	p.cmd.secondary = true
	await t.frames(12)
	p.cmd.secondary = false
	t.check(is_equal_approx(total.call(), before), "a parry takes no damage")
	t.check(foe.stagger_left > 0.0, "a parry staggers the attacker")
	t.check(p.riposte_left > 0.0, "a parry readies a riposte")
	var foe_before := foe.health.health
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	await t.frames(25)
	var blade := p.get_active_weapon() as MeleeWeapon
	t.check(is_equal_approx(foe_before - foe.health.health, blade.light_damage * blade.riposte_mult),
			"the riposte hits harder")

	# A staggered attacker cannot swing.
	foe.stagger(1.0)
	before = total.call()
	await t._foe_swing(foe)
	await t.frames(40)
	t.check(is_equal_approx(total.call(), before), "a staggered attacker cannot attack")

	# Blocking from behind does nothing.
	await t.frames(60)
	before = total.call()
	p.cmd.yaw = PI
	p.cmd.aim_dir = Vector3.BACK
	p.cmd.secondary = true
	await t.frames(30)
	await t._foe_swing(foe)
	await t.frames(40)
	t.check(total.call() < before, "a block does not cover your back")
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD

	# Bullets: a held guard only stops part of one.
	await t.frames(60)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	var blocked_loss: float = before - total.call()
	t.check(blocked_loss > 0.0 and blocked_loss < 20.0, "a blade turns aside part of a bullet")

	# Guard break: no stamina left to pay for the block.
	p.stamina = 2.0
	before = total.call()
	Combat.deal(p, DamageInfo.make(30.0, foe, "melee"))
	t.check(total.call() < before and p.stagger_left > 0.0, "an empty stamina bar means a guard break")
	p.cmd.secondary = false

	# Stamina comes back.
	p.stagger_left = 0.0
	await t.frames(180)
	t.check(p.stamina > 40.0, "stamina regenerates")

	# Hit confirmation reaches the attacker.
	var hits := [0]
	p.hit_confirmed.connect(func(_t: Actor, _i: DamageInfo, _l: bool) -> void: hits[0] += 1)
	Combat.deal(foe, DamageInfo.make(5.0, p, "bullet"))
	t.check(hits[0] == 1, "the attacker is told when a hit lands")
	await t._end_raid(raid)

	# Recoil bloom.
	var gun_raid: Raid = await t._new_raid(49, false)
	var shooter := gun_raid.player
	await t.frames(40)
	var gun := shooter.weapons[0] as Gun
	var calm := gun.current_spread_deg()
	shooter.cmd.primary = true
	await t.frames(40)
	t.check(gun.current_spread_deg() > calm, "sustained fire widens the spread")
	shooter.cmd.primary = false
	await t.frames(60)
	t.check(is_equal_approx(gun.current_spread_deg(), calm), "the spread settles when you stop")
	await t._end_raid(gun_raid)

	# A brute rushes and swings on its own.
	var brute_raid: Raid = await t._new_raid(50, true)
	var duel: Array = await t._duel(brute_raid)
	var victim: Actor = duel[0]
	var brute: Actor = duel[1]
	brute.global_position = victim.global_position + Vector3(0, 0, -7.0)
	# Posted where it stands, so it is not off back to its own post.
	(brute.get_node("Brain") as BotBrain).post_to(brute.global_position, 4.0)
	var victim_before := victim.health.health + victim.health.armor
	await t.frames(300)
	t.check(victim.health.health + victim.health.armor < victim_before, "a melee bot closes in and hits")
	await t._end_raid(brute_raid)
