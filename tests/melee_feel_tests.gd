extends RefCounted
## Checks for how melee answers: presses kept while the blade is busy, quick
## taps, lunges that reach the foe, strikes that count a body's width, the
## air-lunge, and the feedback a strike gives at once. Called from the test
## runner (`-- --groups melee_feel` runs just these).

const Arsenal := preload("res://tests/melee_arsenal_tests.gd")


static func run(t: Node) -> void:
	print("Melee feel: buffering, lunges, contact and recovery")
	var raid: Raid = await t._new_raid(53, false)
	var setup: Array = await t._duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	foe.health.max_health = 900.0
	p.protected_left = 0.0
	foe.protected_left = 0.0
	var blade := await Arsenal._arm(t, p, "")
	var hits := [0]
	foe.health.damaged.connect(func(_i: DamageInfo) -> void: hits[0] += 1)

	# A press made mid-swing is kept and plays once the blade is free.
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 2.0)
	hits[0] = 0
	await _tap(t, p, 1)
	await t.frames(4)
	t.check(blade.is_busy(), "the blade is busy right after a swing starts")
	await _tap(t, p, 1)
	await t.frames(int((blade.light_windup + blade.light_recover) * 60.0) + int(blade.light_windup * 60.0) + 8)
	t.check(hits[0] == 2, "a press made mid-swing is kept and lands as the next cut")
	t.check(blade.combo_step == 2, "a kept press carries on the combo")

	# A tap made long before the blade is free is forgotten.
	await t.frames(90)
	Arsenal._reset(foe)
	hits[0] = 0
	blade.heavy_recover = 1.0
	await Arsenal._hold_attack(t, p, blade)
	await _tap(t, p, 1)
	await t.frames(int((blade.heavy_windup + blade.heavy_recover) * 60.0) + 20)
	t.check(hits[0] == 1, "a stale tap is not played long after it was made")
	blade.heavy_recover = 0.5

	# The time a tap is held counts toward its windup.
	await t.frames(90)
	Arsenal._reset(foe)
	await _tap(t, p, 6)
	t.check(blade.is_winding_up() and blade._windup_left <= blade.light_windup * blade.light_windup_floor + 0.001,
			"a tap held for a moment swings sooner")
	await t.frames(10)
	t.check(blade.recover_progress() >= 0.0 and blade.recover_progress() < 1.0,
			"the recovery after a strike can be seen")
	await t.frames(60)
	t.check(blade.recover_progress() < 0.0, "the recovery ends once the blade is ready")

	# A heavy lunges to the foe and stops at striking distance.
	await t.frames(30)
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 5.0)
	await t.frames(1)
	var gap_before := _flat_gap(p, foe)
	await Arsenal._hold_attack(t, p, blade)
	t.check(blade.is_lunging(), "a heavy at a foe in front lunges")
	await t.frames(int(blade.heavy_windup * 60.0) + 4)
	var gap_after := _flat_gap(p, foe)
	t.check(gap_after < gap_before - 1.5 and gap_after > 0.8, "the lunge closes the gap without passing the foe")
	t.check(is_equal_approx(foe.health.max_health - foe.health.health, blade.heavy_damage), "the lunge lands its heavy")

	# With nobody in front a heavy only steps.
	await t.frames(90)
	Arsenal._reset(foe)
	foe.global_position = p.global_position + Vector3(0, 0, 9.0)
	var start := p.global_position
	await Arsenal._hold_attack(t, p, blade)
	await t.frames(int(blade.heavy_windup * 60.0) + 20)
	var moved := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	t.check(moved > 0.3 and moved < blade.heavy_step + 0.3, "a heavy at nobody is a short step")

	# A strike reaches a body, not only its middle.
	await t.frames(90)
	t.check(await Arsenal._strike(t, p, foe, blade, blade.reach + 0.15) > 0.0,
			"a strike that reaches the edge of a body lands")
	t.check(await Arsenal._strike(t, p, foe, blade, blade.reach + 0.6) == 0.0, "a strike well out of reach misses")

	# The attacker's view hears of a strike at once, with a guess at the guard.
	var seen: Array = []
	blade.contact.connect(func(target: Actor, outcome: String, _at: Vector3) -> void: seen.append([target, outcome]))
	await Arsenal._strike(t, p, foe, blade, 2.0)
	t.check(seen.size() == 1 and seen[0][0] == foe and seen[0][1] == "hit", "a strike reports its contact")
	var foe_blade := MeleeWeapon.new()
	foe.weapons.clear()
	foe.equip_weapon(foe_blade)
	foe.active_weapon_index = 0
	foe.cmd.stance = MeleeWeapon.Dir.OVERHEAD
	foe.cmd.secondary = true
	await t.frames(30)
	seen.clear()
	blade.attack_dir = MeleeWeapon.Dir.OVERHEAD
	await Arsenal._strike(t, p, foe, blade, 2.0)
	t.check(seen.size() == 1 and seen[0][1] == "block", "a strike into a raised guard is reported as blocked")
	foe.cmd.secondary = false

	# A heavy being held back shows its side before the windup.
	await t.frames(30)
	Arsenal._place(p, foe, 2.0)
	# A swing to the foe's right comes from its left, at the player's right.
	foe.cmd.stance = MeleeWeapon.Dir.RIGHT
	foe.cmd.primary = true
	foe.cmd.primary_pressed = true
	await t.frames(1)
	foe.cmd.primary_pressed = false
	await t.frames(4)
	t.check(foe_blade.is_charging() and Hud.incoming_side(p) == MeleeWeapon.Dir.RIGHT,
			"a heavy being charged warns which side to guard")
	foe.cmd.primary = false
	await t.frames(60)

	# Putting the blade away mid-slam means the slam never lands.
	Arsenal._reset(foe)
	p.global_position += Vector3(0, 6.0, 0)
	foe.global_position = p.global_position + Vector3(0, -6.0, -2.0)
	await t.frames(2)
	await Arsenal._hold_attack(t, p, blade)
	t.check(blade._slamming, "a heavy in the air with nobody airborne in front is a dive slam")
	blade.on_holster()
	await t.frames(60)
	t.check(p.is_on_floor() and is_equal_approx(foe.health.health, foe.health.max_health),
			"a slam put away before it lands does nothing")

	# The magnetic air-lunge: a heavy at an airborne foe pulls you to them.
	await t.frames(30)
	Arsenal._reset(foe)
	p.velocity = Vector3.ZERO
	p.global_position += Vector3(0, 8.0, 0)
	foe.global_position = p.global_position + Vector3(0, 0, -5.0)
	foe.cmd.yaw = PI
	await t.frames(2)
	await Arsenal._hold_attack(t, p, blade)
	t.check(blade._air_lunge and blade.is_lunging() and not blade._slamming,
			"a heavy at an airborne foe in the aim cone is an air-lunge")
	t.check(blade.status_text().ends_with("air lunge"), "the air-lunge says so")
	await t.frames(int(blade.heavy_windup * 60.0) + 4)
	t.check(foe.health.health < foe.health.max_health, "the air-lunge reaches and strikes the foe")
	await t.frames(120)
	await t._end_raid(raid)

	# The view kick springs back on its own and never moves the aim.
	var view := PlayerController.new()
	view.kick_view(Vector2(0.02, -0.03))
	var aim := Vector2(view.yaw, view.pitch)
	var peak := 0.0
	for i in 120:
		view._update_shake(1.0 / 60.0)
		peak = maxf(peak, view.view_shake().length())
	t.check(peak > 0.005 and view.view_shake().is_zero_approx(), "a strike's view kick shows, then settles")
	t.check(Vector2(view.yaw, view.pitch) == aim, "the view kick never moves the aim")
	view.free()


## Presses the attack button and holds it `frames` ticks before letting go.
static func _tap(t: Node, p: Actor, frames: int) -> void:
	p.cmd.primary = true
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	if frames > 1:
		await t.frames(frames - 1)
	p.cmd.primary = false
	await t.frames(1)


static func _flat_gap(a: Actor, b: Actor) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
