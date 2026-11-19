extends RefCounted
## The `directional_melee` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Timing melee")
	var over := MeleeWeapon.Dir.OVERHEAD
	var left := MeleeWeapon.Dir.LEFT
	var right := MeleeWeapon.Dir.RIGHT
	t.check(MeleeWeapon.mirror(left) == right and MeleeWeapon.mirror(right) == left
			and MeleeWeapon.mirror(over) == over, "left and right mirror, overhead does not")
	t.check(MeleeWeapon.swing_from(left) == right and MeleeWeapon.swing_from(right) == left
			and MeleeWeapon.swing_from(over) == over, "a swing to one side starts on the other")

	var raid: Raid = await t._new_raid(51, false)
	var setup: Array = await t._duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var foe_blade: MeleeWeapon = setup[2]
	var blade := p.get_active_weapon() as MeleeWeapon
	var total := func() -> float: return p.health.health + p.health.armor

	# The blade picks its own sides: a combo runs left, right, overhead,
	# whatever the command's stance says.
	var sides: Array[int] = []
	for i in 3:
		foe.cmd.stance = right
		await t._foe_swing(foe)
		await t.frames(2)
		sides.append(foe_blade.attack_dir)
		await t.frames(50)
	t.check(sides == [right, left, over], "a combo runs through its sides by itself (%s)" % [sides])
	await t.frames(90)

	# Any guard meets a swing from the front, and turns to its side.
	p.stamina = p.max_stamina
	p.cmd.secondary = true
	await t.frames(30)
	var before: float = total.call()
	await t._foe_swing(foe)
	await t.frames(40)
	t.check(is_equal_approx(total.call(), before), "a guard stops a swing from either side")
	t.check(blade.guard_dir == MeleeWeapon.mirror(foe_blade.attack_dir), "the guard turns to meet the swing")
	p.cmd.secondary = false
	await t.frames(90)

	# Timing pays: a guard raised just before the hit costs far less than
	# one held up through the whole swing.
	p.stamina = p.max_stamina
	await t._foe_swing(foe)
	await t.frames(10)
	var stamina_before := p.stamina
	p.cmd.secondary = true
	await t.frames(30)
	var timed_cost := stamina_before - p.stamina
	p.cmd.secondary = false
	await t.frames(90)
	p.stamina = p.max_stamina
	stamina_before = p.stamina
	p.cmd.secondary = true
	await t.frames(40)
	await t._foe_swing(foe)
	await t.frames(40)
	var held_cost := stamina_before - p.stamina
	p.cmd.secondary = false
	t.check(timed_cost > 0.0 and timed_cost < held_cost * 0.5,
			"a timed block costs a sliver (%.1f) next to a held one (%.1f)" % [timed_cost, held_cost])
	await t.frames(90)

	# Holding the guard drains stamina, faster the longer it is held.
	p.stamina = p.max_stamina
	p.cmd.secondary = true
	await t.frames(60)
	var early := p.stamina
	await t.frames(60)
	var mid := p.stamina
	await t.frames(60)
	t.check(p.max_stamina - early > 0.0 and (early - mid) < (mid - p.stamina),
			"a held guard drains stamina, faster as it is held")
	p.cmd.secondary = false
	await t.frames(30)

	# Mashing is not timing: a guard raised again right after one dropped
	# with nothing to meet gets no timed block.
	p.stamina = p.max_stamina
	p.cmd.secondary = true
	await t.frames(3)
	p.cmd.secondary = false
	await t.frames(2)
	p.cmd.secondary = true
	await t.frames(2)
	t.check(not blade.in_timed_window() and not blade.in_parry_window("melee"), "a mashed guard is not timed")
	p.cmd.secondary = false
	await t.frames(60)

	# A guard that met its hit in time is rearmed at once for the next.
	await t._foe_swing(foe)
	await t.frames(20)
	p.cmd.secondary = true
	await t.frames(15)
	p.cmd.secondary = false
	await t.frames(2)
	p.cmd.secondary = true
	await t.frames(2)
	t.check(blade.in_timed_window(), "a guard that met its hit in time comes straight back up timed")
	p.cmd.secondary = false
	foe.stagger_left = 0.0
	await t.frames(90)

	# Interrupts: a quicker blow that lands on a swing in its windup cuts it off.
	foe.stagger_left = 0.0
	p.stamina = p.max_stamina
	p.riposte_left = 0.0
	before = total.call()
	await t._foe_swing(foe)
	await t.frames(1)
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	await t.frames(25)
	t.check(foe.stagger_left > 0.0 and not foe_blade.is_winding_up(), "a blow that lands mid-windup interrupts it")
	await t.frames(30)
	t.check(is_equal_approx(total.call(), before), "the interrupted swing never lands")
	foe.stagger_left = 0.0
	await t.frames(60)

	# A blow on someone standing ready never holds them.
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	await t.frames(25)
	t.check(foe.stagger_left <= 0.0, "a light on a foe at rest does not stagger them")

	# The evade: with no rig, Alt rolls; a swing landing mid-roll passes
	# through, and the weapon waits out the roll and a moment after.
	await t.frames(60)
	var rig_on := p.flight.enabled
	if rig_on:
		t.check(p.dodge_style(true) in ["thrust", "jet_step", "flap"], "a rig dodges its own way")
	p.flight.enabled = false
	t.check(p.dodge_style(true) == "roll" and p.dodge_style(false) == "dash", "with no rig the dodge is a roll")
	p.stamina = p.max_stamina
	foe.stagger_left = 0.0
	before = total.call()
	var from := p.global_position
	await t._foe_swing(foe)
	await t.frames(20)
	p.cmd.move = Vector2(1, 0)
	p.cmd.dash = true
	await t.frames(1)
	p.cmd.dash = false
	await t.frames(3)
	t.check(p.dodging() and p.evade_left > 0.0 and p.dodge_shown == "roll", "Alt starts a roll")
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	t.check(not blade.is_winding_up(), "no swing comes out of a roll")
	await t.frames(20)
	p.cmd.move = Vector2.ZERO
	t.check(is_equal_approx(total.call(), before), "a swing that lands mid-roll passes through")
	var rolled := Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
	t.check(rolled > 2.0 and rolled < 5.0, "a roll carries the body a few metres (%.1f m)" % rolled)
	await t.frames(40)
	t.check(not p.dodging(), "the weapon answers again once the roll is over")
	p.flight.enabled = rig_on
	p.global_position = from
	p.velocity = Vector3.ZERO

	# The kick breaks a held guard open and goes through it.
	await t.frames(30)
	p.stamina = p.max_stamina
	foe.stagger_left = 0.0
	foe.cmd.secondary = true
	await t.frames(30)
	p.cmd.kick_pressed = true
	await t.frames(1)
	p.cmd.kick_pressed = false
	t.check(blade.is_kicking() and blade.is_winding_up(), "V starts a kick with a windup")
	await t.frames(int(blade.kick_windup * 60.0) + 4)
	t.check(foe.stagger_left > 0.0, "a kick breaks a held guard open")
	foe.cmd.secondary = false
	await t.frames(90)

	# A swing beats a kick: a light thrown into a kick's windup lands first.
	foe.stagger_left = 0.0
	p.stagger_left = 0.0
	foe_blade.kick_stamina = 0.0
	foe.cmd.kick_pressed = true
	await t.frames(1)
	foe.cmd.kick_pressed = false
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	await t.frames(int((blade.light_windup + blade.light_tell) * 60.0) + 2)
	t.check(foe.stagger_left > 0.0 and not foe_blade.is_winding_up(), "a swing into a kick's windup cuts it off")
	await t.frames(90)

	# A feint: aim early in a heavy's windup lets it go and raises the guard.
	foe.stagger_left = 0.0
	p.stagger_left = 0.0
	p.stamina = p.max_stamina
	p.cmd.tertiary_pressed = true
	await t.frames(1)
	p.cmd.tertiary_pressed = false
	await t.frames(3)
	t.check(blade.is_winding_up(), "a heavy winds up")
	var feint_from := p.stamina
	p.cmd.secondary = true
	await t.frames(3)
	t.check(not blade.is_winding_up() and blade.is_blocking() and p.stamina < feint_from,
			"aim early in a heavy feints it into a guard, for stamina")
	p.cmd.secondary = false
	await t.frames(60)

	# A heavy straight off a light is quicker, and comes from the side.
	p.stamina = p.max_stamina
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	await t.frames(int((blade.light_windup + blade.light_tell + blade.light_recover) * 60.0) + 2)
	p.cmd.tertiary_pressed = true
	await t.frames(1)
	p.cmd.tertiary_pressed = false
	await t.frames(1)
	t.check(blade._windup_kind == "heavy" and blade._windup_total < blade.heavy_windup * 0.9
			and blade.attack_dir != MeleeWeapon.Dir.OVERHEAD, "a heavy off a light carries the string on")
	await t.frames(90)

	# Two strikes about to land together clash.
	foe_blade._windup_kind = "light"
	foe_blade._windup_left = blade.clash_window * 0.5
	t.check(blade.clashes_with(foe_blade) and blade.guess_outcome(foe) == "clash", "strikes landing together clash")
	foe_blade._windup_left = 0.3
	t.check(not blade.clashes_with(foe_blade), "a swing far from landing does not clash")
	foe_blade._windup_left = 0.0
	foe_blade._windup_kind = ""

	# Bullets ignore sides: any guard turns part of one aside.
	await t.frames(60)
	p.cmd.secondary = true
	await t.frames(30)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	var loss: float = before - total.call()
	t.check(loss > 0.0 and loss < 20.0, "any guard turns aside part of a bullet")
	p.cmd.secondary = false
	await t._end_raid(raid)
