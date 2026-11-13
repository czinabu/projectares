extends RefCounted
## Checks for sidearms: the loadout slot, quick-draw when the primary runs dry,
## and how each sidearm fires. Called from the test runner
## (`-- --only sidearms` runs just these).

const StashRules := preload("res://core/account/stash_rules.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const SIDEARMS := ["pistol_service", "pistol_hand_cannon", "pistol_machine"]


static func run(t: Node) -> void:
	print("Sidearms")
	_slots(t)
	await _kit(t)
	await _quick_draw(t)
	await _firing(t)


static func _slots(t: Node) -> void:
	for id: String in SIDEARMS:
		t.check(ItemDB.has_item(id) and ItemDB.has_tag(id, "sidearm") and ItemDB.has_tag(id, "firearm"),
				"%s is a sidearm" % id)
		t.check(Loadout.fits("sidearm", id) and not Loadout.fits("primary", id),
				"%s fits the sidearm slot and not the primary slot" % id)
	t.check(not Loadout.fits("sidearm", "rifle_carbine") and Loadout.fits("primary", "rifle_carbine"),
			"a rifle fits the primary slot and not the sidearm slot")
	t.check(not Loadout.fits("sidearm", "blade_scrap"), "a blade is not a sidearm")
	t.check(BaseLayout.slot_for("pistol_machine") == "sidearm", "the base offers a sidearm for the sidearm slot")
	var stash: Array[String] = ["pistol_machine", "rifle_carbine"]
	t.check(StashRules.can_equip(stash, "sidearm", "pistol_machine")
			and not StashRules.can_equip(stash, "primary", "pistol_machine"),
			"the stash rules only take a sidearm in the sidearm slot")
	var loadout := {"primary": "rifle_carbine", "sidearm": "pistol_machine"}
	var kit := StashRules.checkout(stash, loadout, Worlds.get_world("ashfront"))
	t.check("pistol_machine" in kit and "rifle_carbine" in kit and not "blade_scrap" in kit
			and not "pistol_service" in kit, "a chosen sidearm deploys instead of the free one, and an empty melee slot stays empty")
	t.check(not ItemDB.has_tag("pistol_hand_cannon", "vendor"), "the hand cannon is loot only")
	t.check(ItemDB.has_tag("pistol_service", "starter"), "the service pistol is part of the free kit")


## One primary, one melee weapon and one sidearm, in that order, by default.
static func _kit(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 71)
	await t.frames(5)
	var p := raid.player
	t.check(p.weapons.size() == 3 and p.weapons[0] is Gun and not p.weapons[0].is_sidearm
			and p.weapons[1] is MeleeWeapon and p.weapons[2] is Gun and p.weapons[2].is_sidearm,
			"the free kit is a primary, a blade and a sidearm (%d weapons)" % p.weapons.size())
	t.check(p.weapon_for_key(1) == 0 and p.weapon_for_key(2) == 2 and p.weapon_for_key(3) == 1
			and p.weapon_for_key(4) == -1,
			"keys: 1 primary, 2 sidearm, 3 melee, 4 empty")
	p.cmd.switch_weapon = p.weapon_for_key(2)
	await t.frames(2)
	t.check(p.active_weapon_index == 2 and p.weapons[2].visual.visible and not p.weapons[0].visual.visible,
			"key 2 draws the sidearm")
	var seen: Array[int] = []
	for i in 4:
		p.active_weapon_index = p.cycle_weapon_index(1)
		seen.append(p.active_weapon_index)
	t.check(seen == [1, 0, 2, 1], "the wheel cycles sidearm, melee, primary in key order and wraps (%s)" % [seen])
	p.active_weapon_index = p.cycle_weapon_index(-1)
	t.check(p.active_weapon_index == 2, "wheel back from melee lands on the sidearm")
	raid.queue_free()
	await t.frames(2)


static func _shooter(t: Node, kit: Array) -> Array:
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = Vector3(0, 0, -3000)
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	ground.position.y = -0.5
	arena.add_child(ground)
	var shooter := Actor.new()
	arena.add_child(shooter)
	shooter.global_position = arena.global_position
	Loadout.equip(shooter, kit)
	await t.frames(3)
	return [arena, shooter]


static func _quick_draw(t: Node) -> void:
	var made := await _shooter(t, ["rifle_scrap", "blade_scrap", "pistol_service"])
	var shooter: Actor = made[1]
	var rifle := shooter.weapons[0] as Gun
	var pistol := shooter.weapons[2] as Gun
	rifle.ammo_in_mag = 1
	shooter.cmd.primary = true
	await t.frames(4)
	t.check(shooter.active_weapon_index == 2 and not rifle.is_reloading(),
			"running the primary dry with the trigger held draws the sidearm")
	var before := pistol.ammo_in_mag
	shooter.cmd.primary = false
	await t.frames(1)
	shooter.cmd.primary = true
	shooter.cmd.primary_pressed = true
	await t.frames(1)
	shooter.cmd.primary_pressed = false
	await t.frames(10)
	shooter.cmd.primary = false
	t.check(pistol.ammo_in_mag == before - 1, "the service pistol fires once per pull (%d -> %d)"
			% [before, pistol.ammo_in_mag])

	# With an empty sidearm the primary reloads as before.
	shooter.cmd.switch_weapon = 0
	await t.frames(1)
	shooter.cmd.switch_weapon = -1
	pistol.ammo_in_mag = 0
	rifle.ammo_in_mag = 0
	shooter.cmd.primary = true
	await t.frames(2)
	shooter.cmd.primary = false
	t.check(shooter.active_weapon_index == 0 and rifle.is_reloading(),
			"with no loaded sidearm, an empty primary reloads")
	made[0].queue_free()
	await t.frames(2)


static func _firing(t: Node) -> void:
	var made := await _shooter(t, ["pistol_hand_cannon", "pistol_machine"])
	var arena: Node3D = made[0]
	var shooter: Actor = made[1]
	var cannon := shooter.weapons[0] as Gun
	var machine := shooter.weapons[1] as Gun
	t.check(cannon.semi_auto and cannon.headshot_mult > 1.0 and not machine.semi_auto,
			"the hand cannon is semi-auto with a headshot bonus; the machine pistol is full-auto")
	t.check(machine.max_range < cannon.max_range and machine.spread_deg > cannon.spread_deg
			and machine.fire_interval < cannon.fire_interval,
			"the machine pistol fires faster but wider and shorter than the hand cannon")

	var target := Actor.new()
	arena.add_child(target)
	target.global_position = arena.global_position + Vector3(0, 0, -6)
	await t.frames(3)
	var eye := shooter.get_eye_position()
	var head := target.global_position + Vector3(0, Actor.BODY_HEIGHT - 0.1, 0)
	var chest := target.global_position + Vector3(0, 1.0, 0)
	var hit := Combat.trace(shooter, eye, eye + (head - eye) * 2.0)
	t.check(hit.get("collider") == target and Combat.is_headshot(hit), "a shot at the head is a headshot")
	hit = Combat.trace(shooter, eye, eye + (chest - eye) * 2.0)
	t.check(hit.get("collider") == target and not Combat.is_headshot(hit), "a shot at the chest is not")

	# A hand cannon headshot hits twice as hard as a body shot.
	cannon.spread_deg = 0.0
	cannon.bloom_per_shot = 0.0
	var shots := [[head, true], [chest, false]]
	var dealt: Array[float] = []
	for shot: Array in shots:
		target.health.health = target.health.max_health
		target.health.armor = 0.0
		var aim: Vector3 = (shot[0] - eye).normalized()
		shooter.cmd.aim_dir = aim
		await t.frames(40)
		var was := target.health.health
		shooter.cmd.primary = true
		shooter.cmd.primary_pressed = true
		await t.frames(1)
		shooter.cmd.primary = false
		shooter.cmd.primary_pressed = false
		await t.frames(1)
		dealt.append(was - target.health.health)
	t.check(dealt[0] > 0.0 and is_equal_approx(dealt[0], dealt[1] * cannon.headshot_mult),
			"a hand cannon headshot deals double (%.0f head, %.0f body)" % [dealt[0], dealt[1]])
	arena.queue_free()
	await t.frames(2)
