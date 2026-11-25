extends RefCounted
## Checks the first weapon ability, the Breaker Hammer's ground pound
## (`MeleeWeapon.weapon_ability`): its own key and press on the wire, a
## windup anyone can read, a ring that knocks everyone on the ground near
## back and off their feet, a guard that stops it, and a cooldown
## (`-- --groups weapon_ability` runs just these).

const Arsenal := preload("res://tests/melee_arsenal_tests.gd")

const HAMMER := "hammer_breaker"


static func run(t: Node) -> void:
	_data(t)
	_wire(t)
	await _in_raid(t)


static func _data(t: Node) -> void:
	print("Weapon ability: the data")
	var hammer := Arsenal._make(HAMMER)
	t.check(hammer.ability == "ground_pound", "the Breaker Hammer has the ground pound")
	t.check(hammer.ability_windup > hammer.heavy_windup,
			"the pound winds up longer than a heavy, so anyone near can read it (%.2f s)" % hammer.ability_windup)
	t.check(hammer.ability_cooldown >= 8.0, "and it is spent for a while after (%.0f s)" % hammer.ability_cooldown)
	t.check(hammer.ability_damage < hammer.light_damage, "it knocks people down more than it hurts them")
	hammer.free()
	var others := []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "melee") and id != HAMMER and str(ItemDB.item_stats(id).get("ability", "")) != "":
			others.append(id)
	t.check(others.is_empty(), "no other weapon has an ability yet (%s)" % [others])
	t.check(InputMap.has_action("weapon_ability"), "the weapon ability has a key of its own")


static func _wire(t: Node) -> void:
	print("Weapon ability: the press travels")
	var cmd := ActorCommand.new()
	cmd.weapon_ability_pressed = true
	cmd.lamp = true
	cmd.kick_pressed = true
	t.check(ActorCommand.ONE_SHOT_MASK & ActorCommand.FLAG_WEAPON_ABILITY_PRESSED != 0
			and ActorCommand.HELD_MASK & ActorCommand.FLAG_WEAPON_ABILITY_PRESSED == 0, "the press is a one-shot")
	var sent: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	var back := ActorCommand.new()
	back.apply_array(sent)
	t.check(back.weapon_ability_pressed and back.lamp and back.kick_pressed,
			"the press crosses the wire in its own byte, past the first 32 bits, and leaves the others alone")
	cmd.weapon_ability_pressed = false
	sent = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	back.apply_array(sent)
	t.check(not back.weapon_ability_pressed and back.lamp, "and no press stays no press")
	back.weapon_ability_pressed = true
	back.clear_one_shots()
	t.check(not back.weapon_ability_pressed, "it lasts one tick")


static func _press(t: Node, p: Actor) -> void:
	p.cmd.weapon_ability_pressed = true
	await t.frames(1)
	p.cmd.weapon_ability_pressed = false


static func _in_raid(t: Node) -> void:
	print("Weapon ability: the ground pound in a fight")
	var raid: Raid = await t._new_raid(53, false)
	var setup: Array = await t._duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var foe_blade: MeleeWeapon = setup[2]
	foe.health.max_health = 500.0
	p.protected_left = 0.0
	foe.protected_left = 0.0
	var hammer := await Arsenal._arm(t, p, HAMMER)

	# In range and on the ground: knocked back, off its feet.
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 3.0)
	await t.frames(2)
	var start := foe.global_position
	var health := foe.health.health
	var stamina := p.stamina
	await _press(t, p)
	t.check(hammer.is_pounding() and hammer.is_winding_up(), "the pound winds up first")
	t.check(p.stamina < stamina, "and costs stamina")
	await t.frames(int(hammer.ability_windup * 60.0) - 6)
	t.check(foe.health.health == health and foe.stagger_left <= 0.0, "nothing lands during the windup")
	await t.frames(10)
	t.check(is_equal_approx(health - foe.health.health, hammer.ability_damage),
			"it lands for a little damage (%.0f)" % (health - foe.health.health))
	t.check(foe.stagger_left > 0.5, "and knocks the foe off its feet (staggered %.2f s)" % foe.stagger_left)
	await t.frames(30)
	var pushed := Vector2(foe.global_position.x - start.x, foe.global_position.z - start.z)
	t.check(pushed.y < -1.0, "and back, away from the hammer (%.1f m)" % pushed.length())
	t.check(hammer.ability_left > hammer.ability_cooldown - 2.0, "then it cools down")

	# Spent: a second press does nothing until it has cooled.
	await t.frames(int(hammer.ability_recover * 60.0) + 10)
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 3.0)
	stamina = p.stamina
	await _press(t, p)
	t.check(not hammer.is_winding_up() and p.stamina == stamina, "a press while it cools does nothing")
	t.check(hammer.status_text().contains("pound in"), "the weapon line says when it is back: %s" % hammer.status_text())

	# Out of the ring, or above it, nothing.
	hammer.ability_left = 0.0
	Arsenal._reset(foe)
	Arsenal._place(p, foe, hammer.ability_radius + 2.0)
	await t.frames(2)
	health = foe.health.health
	await _press(t, p)
	await t.frames(int(hammer.ability_windup * 60.0) + 4)
	t.check(foe.health.health == health and foe.stagger_left <= 0.0, "past the ring's edge it does nothing")
	await t.frames(int(hammer.ability_recover * 60.0) + 4)
	hammer.ability_left = 0.0
	Arsenal._reset(foe)
	await _press(t, p)
	await t.frames(int(hammer.ability_windup * 60.0) - 2)
	Arsenal._place(p, foe, 2.0, 3.0)
	foe.velocity = Vector3.ZERO
	health = foe.health.health
	await t.frames(4)
	t.check(foe.health.health == health and foe.stagger_left <= 0.0, "a flier above it is not touched")
	await t.frames(int(hammer.ability_recover * 60.0) + 30)

	# A guard raised in time stops it, like any melee hit.
	hammer.ability_left = 0.0
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 3.0)
	foe.cmd.secondary = true
	await t.frames(30)
	Arsenal._place(p, foe, 3.0)
	health = foe.health.health
	await _press(t, p)
	await t.frames(int(hammer.ability_windup * 60.0) + 4)
	t.check(foe.health.health == health and foe_blade.is_blocking() and foe.stagger_left <= 0.0,
			"a raised guard stops it and keeps its feet")
	foe.cmd.secondary = false
	await t.frames(2)
