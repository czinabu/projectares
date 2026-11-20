extends RefCounted
## The `combat_and_loot` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Combat and loot")
	var raid: Raid = await t._new_raid(43, false)
	var p := raid.player
	await t.frames(40)
	# Stand in the exit cell, which is always open ground.
	var arena: Vector3 = t._open_ground(raid)
	arena.y -= 1.9
	p.global_position = arena + Vector3(0, 0, 3)
	p.cmd.yaw = 0.0

	var bot_a := raid.bots[0]
	bot_a.global_position = p.global_position + Vector3(0, 0, -8)
	await t.frames(20)
	var bot_health := bot_a.health.health
	p.cmd.aim_dir = (bot_a.global_position + Vector3(0, 1, 0) - p.get_eye_position()).normalized()
	p.cmd.primary = true
	for i in 240:
		await t.get_tree().physics_frame
		if bot_a.is_dead:
			break
	p.cmd.primary = false
	t.check(bot_a.health.health < bot_health, "rifle damages a bot")
	t.check(bot_a.is_dead, "rifle kills a bot")
	t.check(raid.kills == 1, "the kill is counted")
	var gun := p.weapons[0] as Gun
	t.check(gun.ammo_in_mag < gun.mag_size or gun.reserve_ammo < 120, "shooting uses ammo")

	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	t.check(bags.size() == 1, "a dead bot drops a loot bag")
	if bags.size() == 1:
		var bag := bags[0] as LootContainer
		var before := p.inventory.items.size()
		p.global_position = bag.global_position + Vector3(0, 0, 1.5)
		await t.frames(10)
		p.cmd.aim_dir = (bag.global_position + Vector3(0, 0.25, 0) - p.get_eye_position()).normalized()
		await t.frames(1)
		t.check(p.find_interactable() == bag, "player can target the bag")
		p.cmd.interact_pressed = true
		await t.frames(1)
		p.cmd.interact_pressed = false
		t.check(p.inventory.items.size() > before, "looting moves items to the backpack")

	# A rifleman, not a blade-carrying heavy, an exo or a walker: which one
	# comes first depends on how the seed falls, and they take more than this combo.
	var bot_b := raid.bots[0]
	for other in raid.bots:
		if not other.is_dead and other.get_meta("kind", "soldier") == "soldier" \
				and not other.weapons.any(func(w: Weapon) -> bool: return w is MeleeWeapon):
			bot_b = other
			break
	p.global_position = arena + Vector3(0, 0, 3)
	bot_b.global_position = p.global_position + Vector3(0, 0, -1.8)
	p.cmd.aim_dir = Vector3.FORWARD
	p.cmd.switch_weapon = 1
	await t.frames(2)
	p.cmd.switch_weapon = -1
	t.check(p.get_active_weapon() is MeleeWeapon, "weapon switching works")
	t.check(p.weapons[1].visual != null and p.weapons[1].visual.visible
			and not p.weapons[0].visual.visible, "only the weapon in hand is shown")
	# The holster key puts the weapon away and draws it again. It travels as
	# an index, not a toggle, so a repeated packet changes nothing.
	p.cmd.switch_weapon = ActorCommand.HOLSTER
	await t.frames(2)
	p.cmd.switch_weapon = -1
	t.check(p.get_active_weapon() == null and p.last_drawn == 1 and not p.weapons[1].visual.visible,
			"the holster key puts the weapon in hand away")
	p.cmd.switch_weapon = ActorCommand.HOLSTER
	await t.frames(2)
	t.check(p.get_active_weapon() == null, "holstering with nothing in hand does nothing")
	p.cmd.switch_weapon = p.last_drawn
	await t.frames(2)
	p.cmd.switch_weapon = -1
	t.check(p.get_active_weapon() == p.weapons[1], "drawing again takes out the weapon that was put away")
	var before_melee := bot_b.health.health
	p.cmd.primary_pressed = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	t.check(is_equal_approx(bot_b.health.health, before_melee), "a swing has a windup before it lands")
	await t.frames(12)
	t.check(bot_b.health.health < before_melee, "blade light attack hits")
	t.check(p.stamina < p.max_stamina, "attacking costs stamina")
	for i in 4:
		await t.frames(40)
		p.cmd.primary_pressed = true
		await t.frames(1)
		p.cmd.primary_pressed = false
	await t.frames(12)
	t.check(bot_b.is_dead, "blade combo kills")

	# Scavengers do not hurt each other; that is a world rule.
	if raid.bots.size() >= 2:
		var hit := Combat.deal(raid.bots[1], DamageInfo.make(10.0, raid.bots[0], "bullet"))
		t.check(not hit, "world rules block scav-on-scav damage")
	await t._end_raid(raid)
