extends Node
## Headless test suite. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when everything passes, 1 otherwise.

var _passed := 0
var _failed := 0


func _ready() -> void:
	Profile.persist = false
	Profile.reset()
	await _run()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
	_test_registry()
	_test_health()
	_test_inventory_and_items()
	_test_flight_rig()
	await _test_raid_setup_and_movement()
	await _test_combat_and_loot()
	await _test_melee_defense()
	await _test_directional_melee()
	await _test_flight_rigs_and_abilities()
	await _test_extraction()
	await _test_loadouts()
	await _test_death()
	await _test_storm()
	await _test_bots_run()
	await _test_main_flow()
	await _test_every_world()
	await _test_frostline()


func check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what)


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_raid(p_seed: int, bots_think: bool) -> Raid:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed)
	if not bots_think:
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	return raid


func _end_raid(raid: Raid) -> void:
	raid.queue_free()
	await frames(2)


func _test_registry() -> void:
	print("World registry")
	var world := Worlds.get_world("ashfront")
	check(world != null, "ashfront is discovered from its folder")
	check(Worlds.all().size() >= 1, "registry lists worlds")
	check(world != null and world.starter_loadout().size() > 0, "world provides a starter loadout")


func _test_health() -> void:
	print("Health and armor")
	var h := HealthComponent.new()
	h.set_armor(50.0)
	h.apply_damage(DamageInfo.make(50.0, null, "bullet"))
	check(is_equal_approx(h.armor, 20.0), "armor absorbs 60% of a hit and degrades")
	check(is_equal_approx(h.health, 80.0), "the rest goes to health")
	var deaths := [0]
	h.died.connect(func(_i: DamageInfo) -> void: deaths[0] += 1)
	h.apply_damage(DamageInfo.make(500.0, null, "bullet"))
	h.apply_damage(DamageInfo.make(500.0, null, "bullet"))
	check(h.is_dead and deaths[0] == 1, "death fires exactly once")
	h.free()


func _test_inventory_and_items() -> void:
	print("Inventory and items")
	var inv := Inventory.new()
	inv.capacity = 2
	check(inv.add_item("scrap_metal") and inv.add_item("power_cell"), "items fit up to capacity")
	check(not inv.add_item("medkit"), "a full backpack refuses more")
	check(inv.total_value() == 135, "backpack value adds up")
	check(inv.remove_item("scrap_metal") and not inv.has_item("scrap_metal"), "items can be removed")
	inv.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var loot := Worlds.get_world("ashfront").roll_loot("rooftop", rng)
	check(loot.size() >= 2 and loot.all(func(id: String) -> bool: return ItemDB.has_item(id)),
			"world loot rolls are valid items")


func _test_flight_rig() -> void:
	print("Flight rig")
	var rig := FlightRig.new()
	check(rig.tick(true, 0.1) == 0.0, "no thrust without a rig equipped")
	rig.enabled = true
	check(rig.tick(true, 0.1) > 0.0 and rig.heat > 0.0, "thrust builds heat")
	for i in 100:
		rig.tick(true, 0.1)
	check(rig.overheated and rig.tick(true, 0.1) == 0.0, "overheating cuts thrust")
	for i in 100:
		rig.tick(false, 0.1)
	check(not rig.overheated and rig.heat == 0.0, "the rig cools down and recovers")
	rig.free()


func _test_raid_setup_and_movement() -> void:
	print("Raid setup and movement")
	var raid := await _new_raid(42, false)
	var p := raid.player
	check(p != null and p.is_player, "player spawns")
	check(raid.bots.size() == raid.world.bot_count, "all bots spawn")
	check(raid.exits.size() == 2, "map provides two exits")
	var caches := raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer)
	check(caches.size() >= 8, "loot caches are placed (%d)" % caches.size())
	check(p.weapons.size() == 2 and p.flight.enabled and p.health.armor == 30.0,
			"starter loadout is equipped")

	await frames(40)
	check(p.is_on_floor(), "player lands on the ground")

	var start := p.global_position
	p.cmd.yaw = 0.0
	p.cmd.move = Vector2(0, 1)
	await frames(30)
	p.cmd.move = Vector2.ZERO
	check(p.global_position.distance_to(start) > 1.0, "player walks")

	var ground_y := p.global_position.y
	p.cmd.jump_pressed = true
	p.cmd.jump = true
	await frames(1)
	p.cmd.jump_pressed = false
	await frames(50)
	check(p.global_position.y > ground_y + 3.0, "holding jump flies with the jetpack")
	check(p.flight.heat > 0.0, "flying builds heat")
	p.cmd.jump = false
	for i in 300:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	check(p.is_on_floor(), "player comes back down")
	await _end_raid(raid)


func _test_combat_and_loot() -> void:
	print("Combat and loot")
	var raid := await _new_raid(43, false)
	var p := raid.player
	await frames(40)
	# Stand in the exit cell, which is always open ground.
	var arena := raid.exits[0].global_position
	arena.y = 0.1
	p.global_position = arena + Vector3(0, 0, 3)
	p.cmd.yaw = 0.0

	var bot_a := raid.bots[0]
	bot_a.global_position = p.global_position + Vector3(0, 0, -8)
	await frames(20)
	var bot_health := bot_a.health.health
	p.cmd.aim_dir = (bot_a.global_position + Vector3(0, 1, 0) - p.get_eye_position()).normalized()
	p.cmd.primary = true
	for i in 240:
		await get_tree().physics_frame
		if bot_a.is_dead:
			break
	p.cmd.primary = false
	check(bot_a.health.health < bot_health, "rifle damages a bot")
	check(bot_a.is_dead, "rifle kills a bot")
	check(raid.kills == 1, "the kill is counted")
	var gun := p.weapons[0] as Gun
	check(gun.ammo_in_mag < gun.mag_size or gun.reserve_ammo < 120, "shooting uses ammo")

	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	check(bags.size() == 1, "a dead bot drops a loot bag")
	if bags.size() == 1:
		var bag := bags[0] as LootContainer
		var before := p.inventory.items.size()
		p.global_position = bag.global_position + Vector3(0, 0, 1.5)
		await frames(10)
		p.cmd.aim_dir = (bag.global_position + Vector3(0, 0.25, 0) - p.get_eye_position()).normalized()
		await frames(1)
		check(p.find_interactable() == bag, "player can target the bag")
		p.cmd.interact_pressed = true
		await frames(1)
		p.cmd.interact_pressed = false
		check(p.inventory.items.size() > before, "looting moves items to the backpack")

	var bot_b := raid.bots[0]
	p.global_position = arena + Vector3(0, 0, 3)
	bot_b.global_position = p.global_position + Vector3(0, 0, -1.8)
	p.cmd.aim_dir = Vector3.FORWARD
	p.cmd.switch_weapon = 1
	await frames(2)
	p.cmd.switch_weapon = -1
	check(p.get_active_weapon() is MeleeWeapon, "weapon switching works")
	check(p.weapons[1].visual != null and p.weapons[1].visual.visible
			and not p.weapons[0].visual.visible, "only the weapon in hand is shown")
	var before_melee := bot_b.health.health
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	check(is_equal_approx(bot_b.health.health, before_melee), "a swing has a windup before it lands")
	await frames(12)
	check(bot_b.health.health < before_melee, "blade light attack hits")
	check(p.stamina < p.max_stamina, "attacking costs stamina")
	for i in 4:
		await frames(40)
		p.cmd.primary_pressed = true
		await frames(1)
		p.cmd.primary_pressed = false
	await frames(12)
	check(bot_b.is_dead, "blade combo kills")

	# Scavengers do not hurt each other; that is a world rule.
	if raid.bots.size() >= 2:
		var hit := Combat.deal(raid.bots[1], DamageInfo.make(10.0, raid.bots[0], "bullet"))
		check(not hit, "world rules block scav-on-scav damage")
	await _end_raid(raid)


func _test_extraction() -> void:
	print("Extraction")
	Profile.reset()
	var raid := await _new_raid(44, false)
	var results: Array[Dictionary] = []
	raid.ended.connect(func(r: Dictionary) -> void: results.append(r))
	var p := raid.player
	p.inventory.add_item("reactor_core")
	p.inventory.add_item("medkit")
	var exit_pos := raid.exits[1].global_position
	p.global_position = Vector3(exit_pos.x, 0.2, exit_pos.z)
	await frames(60)
	check(raid.extract_progress() > 0.0, "standing in an exit starts the countdown")
	check(results.is_empty(), "extraction is not instant")
	await frames(240)
	check(results.size() == 1 and results[0].outcome == "extracted", "raid ends as extracted")
	check("reactor_core" in Profile.stash and "medkit" in Profile.stash,
			"backpack loot lands in the stash")
	check(Profile.stash.size() == 2, "the free scrap kit is never stashed")
	check(Profile.raids_extracted == 1, "profile records the extraction")
	await _end_raid(raid)


func _test_death() -> void:
	print("Death")
	Profile.reset()
	var raid := await _new_raid(45, false)
	var results: Array[Dictionary] = []
	raid.ended.connect(func(r: Dictionary) -> void: results.append(r))
	var p := raid.player
	p.inventory.add_item("lattice_shard")
	Combat.deal(p, DamageInfo.make(9999.0, raid.bots[0], "bullet"))
	await frames(2)
	check(p.is_dead, "player can die")
	check(results.size() == 1 and results[0].outcome == "died", "raid ends as died")
	check(Profile.stash.is_empty(), "nothing reaches the stash on death")
	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	check(bags.size() == 1 and "lattice_shard" in (bags[0] as LootContainer).items
			and "rifle_scrap" in (bags[0] as LootContainer).items,
			"the player's gear and loot drop in a bag")
	await _end_raid(raid)


func _test_storm() -> void:
	print("Storm timer")
	var raid := await _new_raid(46, false)
	var results: Array[Dictionary] = []
	raid.ended.connect(func(r: Dictionary) -> void: results.append(r))
	raid.time_left = 0.05
	await frames(10)
	check(results.size() == 1 and results[0].outcome == "died" and results[0].cause == "storm",
			"running out of time kills the player")
	await _end_raid(raid)


func _test_bots_run() -> void:
	print("Bot AI")
	var raid := await _new_raid(47, true)
	var starts := {}
	for bot in raid.bots:
		starts[bot] = bot.global_position
	# Bring one bot face to face with the player to exercise the fight logic.
	var p := raid.player
	await frames(40)
	var bot := raid.bots[0]
	var arena := raid.exits[0].global_position
	p.global_position = Vector3(arena.x, 0.1, arena.z + 3.0)
	bot.global_position = Vector3(arena.x, 0.1, arena.z - 5.0)
	var health_before := p.health.health + p.health.armor
	await frames(360)
	var moved := 0
	for b: Actor in starts:
		if is_instance_valid(b) and b.global_position.distance_to(starts[b]) > 1.5:
			moved += 1
	check(moved >= 3, "bots patrol (%d moved)" % moved)
	check(p.health.health + p.health.armor < health_before, "a bot that sees the player attacks")
	await _end_raid(raid)


func _test_main_flow() -> void:
	print("Hub and raid flow")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(2)
	check(main.hub.visible and main.raid == null, "game starts in the hub")
	main.start_raid("ashfront")
	await frames(5)
	check(main.raid != null and not main.hub.visible, "deploying starts a raid")
	check(main.controller.camera.current and main.hud != null, "raid has a camera and HUD")
	var controller: PlayerController = main.controller
	check(controller.view_mode == PlayerController.ViewMode.FIRST and not controller.is_third_person(),
			"camera starts in first-person")
	# Melee and flight must not move the camera on their own.
	var p: Actor = main.raid.player
	await frames(40)
	Input.action_press("weapon_2")
	Input.action_press("jump")
	await frames(40)
	Input.action_release("weapon_2")
	Input.action_release("jump")
	check(p.get_active_weapon() is MeleeWeapon and not p.is_on_floor(),
			"real input reaches the actor (blade out, airborne)")
	check(not controller.is_third_person(), "camera stays put when using the blade or flying")
	check(p.hand_override, "first-person holds the weapon in front of the camera")
	# Melee side from the movement keys, once the player switches to them.
	Input.action_press("move_left")
	await frames(5)
	check(p.cmd.stance == MeleeWeapon.Dir.OVERHEAD, "movement keys do not change the melee side by default")
	controller.toggle_stance_control()
	await frames(5)
	check(p.cmd.stance == MeleeWeapon.Dir.LEFT and Profile.melee_control == "move",
			"after switching, strafing picks the melee side and the choice is remembered")
	Input.action_release("move_left")
	controller.toggle_stance_control()
	check(Profile.melee_control == "mouse", "switching again goes back to the mouse flick")
	controller.toggle_view()
	await frames(40)
	check(controller.is_third_person(), "the toggle switches to third-person")
	main.raid.player.kill("test")
	await frames(150)
	check(main.raid == null and main.hub.visible, "dying returns to the hub")
	main.queue_free()
	await frames(2)


## Sets up the player with the blade out, facing a brute that stands in reach.
func _duel(raid: Raid) -> Array:
	var p := raid.player
	await frames(40)
	var arena := raid.exits[0].global_position
	p.global_position = Vector3(arena.x, 0.1, arena.z + 3.0)
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD
	p.cmd.switch_weapon = 1
	var foe := raid.bots[0]
	foe.global_position = p.global_position + Vector3(0, 0, -2.0)
	foe.cmd.yaw = PI
	foe.cmd.aim_dir = Vector3.BACK
	# Give the foe a blade regardless of what the world rolled for it.
	for w in foe.weapons:
		w.queue_free()
	foe.weapons.clear()
	var blade := MeleeWeapon.new()
	blade.light_windup = 0.5
	blade.light_stamina = 0.0
	foe.equip_weapon(blade)
	foe.active_weapon_index = 0
	await frames(3)
	p.cmd.switch_weapon = -1
	return [p, foe, blade]


func _foe_swing(foe: Actor) -> void:
	foe.cmd.primary_pressed = true
	await frames(1)
	foe.cmd.primary_pressed = false


func _test_melee_defense() -> void:
	print("Block, parry and stamina")
	var raid := await _new_raid(48, false)
	var setup: Array = await _duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var total := func() -> float: return p.health.health + p.health.armor

	# Unblocked hit.
	var before: float = total.call()
	await _foe_swing(foe)
	await frames(40)
	check(total.call() < before, "an unblocked swing hurts")

	# Held block: guard raised long before the hit lands.
	await frames(60)
	before = total.call()
	var stamina_before := p.stamina
	p.cmd.secondary = true
	await frames(30)
	await _foe_swing(foe)
	await frames(40)
	check(is_equal_approx(total.call(), before), "a held block stops a melee hit")
	check(p.stamina < stamina_before, "blocking costs stamina")
	check(foe.stagger_left <= 0.0, "a plain block does not stagger the attacker")
	p.cmd.secondary = false

	# Parry: guard raised just before the hit lands (windup is 30 frames).
	await frames(90)
	before = total.call()
	stamina_before = p.stamina
	await _foe_swing(foe)
	await frames(22)
	p.cmd.secondary = true
	await frames(12)
	p.cmd.secondary = false
	check(is_equal_approx(total.call(), before), "a parry takes no damage")
	check(foe.stagger_left > 0.0, "a parry staggers the attacker")
	check(p.riposte_left > 0.0, "a parry readies a riposte")
	var foe_before := foe.health.health
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	await frames(12)
	var blade := p.get_active_weapon() as MeleeWeapon
	check(is_equal_approx(foe_before - foe.health.health, blade.light_damage * blade.riposte_mult),
			"the riposte hits harder")

	# A staggered attacker cannot swing.
	foe.stagger(1.0)
	before = total.call()
	await _foe_swing(foe)
	await frames(40)
	check(is_equal_approx(total.call(), before), "a staggered attacker cannot attack")

	# Blocking from behind does nothing.
	await frames(60)
	before = total.call()
	p.cmd.yaw = PI
	p.cmd.aim_dir = Vector3.BACK
	p.cmd.secondary = true
	await frames(30)
	await _foe_swing(foe)
	await frames(40)
	check(total.call() < before, "a block does not cover your back")
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD

	# Bullets: a held guard only stops part of one.
	await frames(60)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	var blocked_loss: float = before - total.call()
	check(blocked_loss > 0.0 and blocked_loss < 20.0, "a blade turns aside part of a bullet")

	# Guard break: no stamina left to pay for the block.
	p.stamina = 2.0
	before = total.call()
	Combat.deal(p, DamageInfo.make(30.0, foe, "melee"))
	check(total.call() < before and p.stagger_left > 0.0, "an empty stamina bar means a guard break")
	p.cmd.secondary = false

	# Stamina comes back.
	p.stagger_left = 0.0
	await frames(180)
	check(p.stamina > 40.0, "stamina regenerates")

	# Hit confirmation reaches the attacker.
	var hits := [0]
	p.hit_confirmed.connect(func(_t: Actor, _i: DamageInfo, _l: bool) -> void: hits[0] += 1)
	Combat.deal(foe, DamageInfo.make(5.0, p, "bullet"))
	check(hits[0] == 1, "the attacker is told when a hit lands")
	await _end_raid(raid)

	# Recoil bloom.
	var gun_raid := await _new_raid(49, false)
	var shooter := gun_raid.player
	await frames(40)
	var gun := shooter.weapons[0] as Gun
	var calm := gun.current_spread_deg()
	shooter.cmd.primary = true
	await frames(40)
	check(gun.current_spread_deg() > calm, "sustained fire widens the spread")
	shooter.cmd.primary = false
	await frames(60)
	check(is_equal_approx(gun.current_spread_deg(), calm), "the spread settles when you stop")
	await _end_raid(gun_raid)

	# A brute rushes and swings on its own.
	var brute_raid := await _new_raid(50, true)
	var duel: Array = await _duel(brute_raid)
	var victim: Actor = duel[0]
	var brute: Actor = duel[1]
	brute.global_position = victim.global_position + Vector3(0, 0, -7.0)
	var victim_before := victim.health.health + victim.health.armor
	await frames(300)
	check(victim.health.health + victim.health.armor < victim_before, "a melee bot closes in and hits")
	await _end_raid(brute_raid)


func _test_loadouts() -> void:
	print("Loadouts")
	var world := Worlds.get_world("ashfront")
	Profile.reset()
	Profile.grant_welcome_crate()
	var crate_size := Profile.stash.size()
	Profile.grant_welcome_crate()
	check(crate_size > 0 and Profile.stash.size() == crate_size, "the welcome crate is granted once")

	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "frame_bulwark", "hammer_breaker", "medkit", "medkit", "medkit", "scrap_metal"])
	check(not Profile.equip("primary", "hammer_breaker"), "an item cannot go in the wrong slot")
	check(not Profile.equip("primary", "dmr_longshot"), "an item you do not own cannot be equipped")
	check(Profile.equip("primary", "rifle_carbine") and Profile.equip("frame", "frame_bulwark")
			and Profile.equip("melee", "hammer_breaker"), "owned gear equips into its slot")

	var kit := Profile.checkout_loadout(world)
	check("rifle_carbine" in kit and "frame_bulwark" in kit and "hammer_breaker" in kit,
			"deploying takes the chosen gear")
	check("jetpack_mk1" in kit, "an empty slot gets the free scrap item")
	check(kit.count("medkit") == 2 and "field_dressing" not in kit, "up to two medkits come along")
	check(Profile.stash == (["medkit", "scrap_metal"] as Array[String]), "deployed gear leaves the stash")

	# Extract with the gear: it all comes home.
	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 60, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	var p := raid.player
	var gun := p.weapons[0] as Gun
	var hammer := p.weapons[1] as MeleeWeapon
	check(gun.display_name == "Ashfront Carbine" and is_equal_approx(gun.damage, 24.0), "weapon stats come from the item")
	check(hammer.display_name == "Breaker Hammer" and is_equal_approx(hammer.heavy_damage, 95.0), "melee stats come from the item")
	check(is_equal_approx(p.health.armor, 140.0), "the frame sets armor")
	var base := Actor.new()
	check(p.walk_speed < base.walk_speed and p.flight.heat_per_sec > FlightRig.new().heat_per_sec,
			"a heavy frame is slower and runs the jetpack hotter")
	base.free()
	var results: Array[Dictionary] = []
	raid.ended.connect(func(r: Dictionary) -> void: results.append(r))
	var exit_pos := raid.exits[0].global_position
	p.global_position = Vector3(exit_pos.x, 0.2, exit_pos.z)
	await frames(300)
	check(results.size() == 1 and results[0].outcome == "extracted", "raid with a loadout extracts")
	check("rifle_carbine" in Profile.stash and "frame_bulwark" in Profile.stash and "hammer_breaker" in Profile.stash,
			"extracting brings your gear home")
	check("jetpack_mk1" not in Profile.stash and "rifle_scrap" not in Profile.stash, "scrap gear does not come home")
	check(Profile.equipped("primary") == "rifle_carbine", "the loadout stays equipped after extracting")
	await _end_raid(raid)

	# Die with the gear: it is gone and the slot empties.
	kit = Profile.checkout_loadout(world)
	raid = Raid.new()
	add_child(raid)
	raid.start(world, 61, kit)
	await frames(3)
	raid.player.kill("test")
	await frames(2)
	check("rifle_carbine" not in Profile.stash and "frame_bulwark" not in Profile.stash, "dying loses your gear")
	check(Profile.equipped("primary") == "" and Profile.equipped("frame") == "", "lost gear leaves the loadout")
	await _end_raid(raid)

	# With nothing owned, the kit is the full free scrap kit.
	Profile.reset()
	Profile.welcome_granted = true
	kit = Profile.checkout_loadout(world)
	check(kit == world.starter_loadout(), "an empty stash deploys the scrap kit")

	# Healing uses any heal item and its own strength.
	raid = await _new_raid(62, false)
	p = raid.player
	await frames(40)
	Combat.deal(p, DamageInfo.make(80.0, null, "bullet"))
	var hurt := p.health.health
	p.cmd.heal_pressed = true
	await frames(1)
	p.cmd.heal_pressed = false
	await frames(200)
	check(is_equal_approx(p.health.health - hurt, 30.0) and p.inventory.count_with_tag("heal") == 0,
			"a field dressing heals its own amount and is used up")

	# Shotgun: several pellets per shot.
	var shotgun := Gun.new()
	Loadout._setup_weapon(shotgun, "shotgun_breacher", ItemDB.item_stats("shotgun_breacher"))
	p.equip_weapon(shotgun)
	p.cmd.switch_weapon = 2
	var arena := raid.exits[0].global_position
	p.global_position = Vector3(arena.x, 0.1, arena.z + 3.0)
	var target := raid.bots[0]
	target.global_position = p.global_position + Vector3(0, 0, -3.0)
	await frames(10)
	p.cmd.switch_weapon = -1
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = (target.global_position + Vector3(0, 1, 0) - p.get_eye_position()).normalized()
	var before := target.health.health
	p.cmd.primary = true
	await frames(1)
	p.cmd.primary = false
	await frames(2)
	check(before - target.health.health > shotgun.damage * 3.0, "a shotgun lands several pellets at once")
	check(shotgun.ammo_in_mag == 5, "a shotgun blast uses one shell")
	await _end_raid(raid)

	# The hub offers what you own.
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "dmr_longshot", "frame_runner"])
	var hub := Hub.new()
	add_child(hub)
	await frames(2)
	check(hub.options_for("primary") == (["dmr_longshot", "rifle_carbine"] as Array[String])
			and hub.options_for("frame") == (["frame_runner"] as Array[String]),
			"the hub lists owned gear per slot")
	hub._on_picked(1, "primary")
	check(Profile.equipped("primary") == "dmr_longshot", "picking in the hub equips the item")
	hub._on_picked(0, "primary")
	check(Profile.equipped("primary") == "", "picking the scrap kit unequips")
	hub.queue_free()
	Profile.reset()
	Profile.welcome_granted = true


func _test_directional_melee() -> void:
	print("Directional melee")
	var over := MeleeWeapon.Dir.OVERHEAD
	var left := MeleeWeapon.Dir.LEFT
	var right := MeleeWeapon.Dir.RIGHT
	check(MeleeWeapon.mirror(left) == right and MeleeWeapon.mirror(right) == left
			and MeleeWeapon.mirror(over) == over, "left and right mirror, overhead does not")
	check(MeleeWeapon.guard_covers(right, left) and not MeleeWeapon.guard_covers(left, left)
			and MeleeWeapon.guard_covers(left, -1), "a guard covers the side the swing arrives on")

	# Mouse flicks pick the stance.
	check(PlayerController.stance_from_flick(Vector2(-80, 10), over, 45.0) == left
			and PlayerController.stance_from_flick(Vector2(80, -10), over, 45.0) == right
			and PlayerController.stance_from_flick(Vector2(5, -80), left, 45.0) == over,
			"flicking the mouse left, right or up picks that side")
	check(PlayerController.stance_from_flick(Vector2(10, 5), left, 45.0) == left
			and PlayerController.stance_from_flick(Vector2(0, 90), right, 45.0) == right,
			"small or downward mouse movement keeps the stance")

	check(PlayerController.stance_from_move(Vector2(-1, 0), over) == left
			and PlayerController.stance_from_move(Vector2(1, 0.3), over) == right
			and PlayerController.stance_from_move(Vector2(0, 1), left) == over,
			"strafing left or right or moving forward picks that side")
	check(PlayerController.stance_from_move(Vector2.ZERO, left) == left
			and PlayerController.stance_from_move(Vector2(0, -1), right) == right,
			"standing still or backing up keeps the stance")

	var raid := await _new_raid(51, false)
	var setup: Array = await _duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var foe_blade: MeleeWeapon = setup[2]
	var blade := p.get_active_weapon() as MeleeWeapon
	var total := func() -> float: return p.health.health + p.health.armor

	# The foe swings from its left, which arrives on the player's right.
	foe.cmd.stance = left
	p.cmd.stance = left
	p.cmd.secondary = true
	await frames(30)
	var before: float = total.call()
	await _foe_swing(foe)
	await frames(10)
	check(foe_blade.is_winding_up() and foe_blade.attack_dir == left, "a swing takes the stance it started in")
	check(Hud.incoming_side(p) == right, "the HUD warns which side to guard")
	await frames(30)
	check(total.call() < before, "a guard on the wrong side stops nothing")
	check(Hud.incoming_side(p) == -1, "the warning clears after the swing")

	# Changing stance while the guard is up does not move it.
	p.cmd.stance = right
	await frames(30)
	check(blade.guard_dir == left, "a guard keeps the side it was raised on")
	p.cmd.secondary = false
	await frames(60)

	# Guard the correct side.
	p.cmd.secondary = true
	await frames(30)
	check(blade.guard_dir == right, "raising the guard again takes the new stance")
	before = total.call()
	await _foe_swing(foe)
	await frames(40)
	check(is_equal_approx(total.call(), before), "a guard on the correct side blocks the hit")
	p.cmd.secondary = false

	# A parry needs the correct side too.
	await frames(90)
	p.cmd.stance = over
	before = total.call()
	await _foe_swing(foe)
	await frames(22)
	p.cmd.secondary = true
	await frames(12)
	p.cmd.secondary = false
	check(total.call() < before and foe.stagger_left <= 0.0, "a parry on the wrong side fails")
	await frames(90)
	p.cmd.stance = right
	p.stagger_left = 0.0
	before = total.call()
	await _foe_swing(foe)
	await frames(22)
	p.cmd.secondary = true
	await frames(12)
	p.cmd.secondary = false
	check(is_equal_approx(total.call(), before) and foe.stagger_left > 0.0, "a parry on the correct side lands")

	# The player's attacks carry their direction, and the foe can guard them.
	await frames(120)
	foe.stagger_left = 0.0
	p.riposte_left = 0.0
	p.cmd.stance = right
	foe.cmd.stance = left
	foe.cmd.secondary = true
	await frames(30)
	var foe_before := foe.health.health + foe.health.armor
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	await frames(20)
	check(is_equal_approx(foe.health.health + foe.health.armor, foe_before), "an enemy guarding the right side blocks you")
	await frames(40)
	p.cmd.stance = over
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	await frames(20)
	check(foe.health.health + foe.health.armor < foe_before, "attacking a side the enemy is not guarding gets through")
	foe.cmd.secondary = false

	# Bullets ignore direction: any guard turns part of one aside.
	p.cmd.stance = left
	p.cmd.secondary = true
	await frames(30)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	var loss: float = before - total.call()
	check(loss > 0.0 and loss < 20.0, "any guard turns aside part of a bullet")
	p.cmd.secondary = false
	await _end_raid(raid)

	# A guarding brute picks a side and holds it between swings.
	var brute_raid := await _new_raid(52, true)
	var duel: Array = await _duel(brute_raid)
	var brute: Actor = duel[1]
	var brute_blade: MeleeWeapon = duel[2]
	var guarded := false
	var sides := {}
	for i in 600:
		await frames(1)
		if brute_blade.is_blocking():
			guarded = true
		if brute_blade.is_winding_up():
			sides[brute_blade.attack_dir] = true
	check(guarded, "a melee bot guards between swings")
	check(sides.size() >= 2, "a melee bot varies the side it attacks from")
	await _end_raid(brute_raid)


## A raid whose player carries exactly `kit`, standing in the open.
func _kit_raid(p_seed: int, kit: Array[String]) -> Raid:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(40)
	return raid


func _test_flight_rigs_and_abilities() -> void:
	print("Flight rigs and abilities")
	var press_jump := func(a: Actor) -> void:
		a.cmd.jump_pressed = true
		await frames(1)
		a.cmd.jump_pressed = false

	# Thruster boots: no sustained lift, a kick per press, limited by heat.
	var raid := await _kit_raid(60, ["rifle_scrap", "blade_scrap", "boots_thruster", "plate_light"])
	var p := raid.player
	check(p.flight.display_name == "Thruster Boots" and p.flight.burst_velocity > 0.0
			and is_zero_approx(p.flight.thrust_accel), "boots stats come from the item")
	await press_jump.call(p)
	await frames(20)
	p.cmd.jump = true
	await frames(10)
	check(not p.flight.is_thrusting and p.velocity.y < 0.0, "boots give no lift from holding jump")
	p.cmd.jump = false
	var height := p.global_position.y
	await press_jump.call(p)
	check(p.velocity.y > 8.0 and p.flight.heat > 0.0, "pressing jump in the air kicks you upward and costs heat")
	await frames(15)
	check(p.global_position.y > height + 1.0, "the kick gains height")
	for i in 6:
		await press_jump.call(p)
		await frames(4)
	check(p.flight.overheated, "boosting over and over overheats the boots")
	var vy := p.velocity.y
	await press_jump.call(p)
	check(p.velocity.y <= vy, "overheated boots do nothing")
	await _end_raid(raid)

	# Glide wings: launch, then fall slowly and travel far.
	raid = await _kit_raid(61, ["rifle_scrap", "blade_scrap", "wings_glide", "plate_light"])
	p = raid.player
	p.global_position += Vector3(0, 30, 0)
	p.velocity = Vector3.ZERO
	await frames(30)
	check(p.velocity.y < -5.0 and not p.flight.is_gliding, "wings do nothing until you hold jump")
	p.cmd.jump = true
	var start := p.global_position
	await frames(60)
	check(p.flight.is_gliding and p.velocity.y >= -p.flight.glide_fall_speed - 0.01,
			"holding jump while falling glides at a gentle sink rate")
	var travelled := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	check(travelled > 8.0, "gliding carries you forward (%.1f m in a second)" % travelled)
	p.cmd.jump = false
	await frames(5)
	check(not p.flight.is_gliding, "letting go stops the glide")
	await _end_raid(raid)

	# The jetpack still works and does not burst or glide.
	raid = await _kit_raid(62, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"])
	p = raid.player
	await press_jump.call(p)
	await frames(10)
	p.cmd.jump = true
	await press_jump.call(p)
	await frames(30)
	check(p.flight.is_thrusting and not p.flight.is_gliding and not p.is_on_floor(),
			"the jetpack still flies by holding jump")
	p.cmd.jump = false
	check(not p.ability.enabled and p.ability.status_text() == "", "no ability without an ability item")
	p.cmd.ability_pressed = true
	await frames(2)
	p.cmd.ability_pressed = false
	check(p.ability.cooldown_left <= 0.0, "pressing the ability key with none equipped does nothing")
	await _end_raid(raid)

	# Phase Step.
	raid = await _kit_raid(63, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_blink"])
	p = raid.player
	check(p.ability.enabled and p.ability.effect == "blink" and "chip_blink" in p.gear_items,
			"an ability item equips into the ability slot")
	var arena := raid.exits[0].global_position
	p.global_position = Vector3(arena.x, 0.1, arena.z + 3.0)
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD
	await frames(5)
	var before_pos := p.global_position
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	var moved := before_pos.distance_to(p.global_position)
	check(moved > 2.0 and moved <= p.ability.blink_range + 0.5, "Phase Step moves you forward (%.1f m)" % moved)
	check(p.ability.cooldown_left > 0.0 and not p.ability.is_ready(), "an ability goes on cooldown")
	before_pos = p.global_position
	p.cmd.ability_pressed = true
	await frames(2)
	p.cmd.ability_pressed = false
	check(before_pos.distance_to(p.global_position) < 0.5, "an ability cannot be used while on cooldown")
	p.ability.cooldown_left = 0.0
	p.cmd.aim_dir = Vector3.DOWN
	await frames(2)
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	await frames(10)
	check(p.global_position.y > -0.5, "Phase Step stops short of the ground and walls")
	await _end_raid(raid)

	# Kinetic Barrier.
	raid = await _kit_raid(64, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_barrier"])
	p = raid.player
	var foe := raid.bots[0]
	var total := func() -> float: return p.health.health + p.health.armor
	var before: float = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	check(is_equal_approx(before - total.call(), 20.0), "without the barrier a hit lands in full")
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	check(p.ability.is_active() and is_equal_approx(before - total.call(), 8.0), "the barrier cuts damage by 60%")
	await frames(int(p.ability.duration * 60.0) + 10)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	check(not p.ability.is_active() and is_equal_approx(before - total.call(), 20.0), "the barrier runs out")
	await _end_raid(raid)

	# Shock Pulse.
	raid = await _kit_raid(65, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_pulse"])
	p = raid.player
	var near := raid.bots[0]
	var far := raid.bots[1]
	near.global_position = p.global_position + Vector3(3, 0, 0)
	far.global_position = p.global_position + Vector3(30, 0, 0)
	await frames(3)
	var near_before := near.health.health + near.health.armor
	var far_before := far.health.health + far.health.armor
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	check(near.health.health + near.health.armor < near_before and near.stagger_left > 0.0,
			"Shock Pulse hurts and staggers someone close")
	check(is_equal_approx(far.health.health + far.health.armor, far_before) and far.stagger_left <= 0.0,
			"Shock Pulse does not reach someone far away")
	await _end_raid(raid)

	# Stash, hub and crates.
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["chip_pulse", "wings_glide"])
	check(Profile.equip("ability", "chip_pulse") and Profile.equip("rig", "wings_glide")
			and not Profile.equip("ability", "wings_glide"), "abilities and rigs equip into their own slots")
	var kit := Profile.checkout_loadout(Worlds.get_world("ashfront"))
	check("chip_pulse" in kit and "wings_glide" in kit and "jetpack_mk1" not in kit,
			"the kit carries the chosen ability and rig")
	Profile.reset()
	Profile.welcome_granted = true
	kit = Profile.checkout_loadout(Worlds.get_world("ashfront"))
	var has_ability := false
	for id in kit:
		if ItemDB.has_tag(id, "ability"):
			has_ability = true
	check(not has_ability, "an empty ability slot deploys with no ability")
	Profile.grant_gear_crates()
	var crate_size := Profile.stash.size()
	Profile.grant_gear_crates()
	check(crate_size > 0 and Profile.stash.size() == crate_size and "chip_blink" in Profile.stash,
			"the flight and abilities crate is granted once")
	Profile.reset()


## Every world folder must honour the map contract and run a raid headless.
func _test_every_world() -> void:
	print("Every world plugs in")
	check(Worlds.all().size() >= 2, "registry finds more than one world (%d)" % Worlds.all().size())
	var hub := Hub.new()
	add_child(hub)
	await frames(1)
	var buttons := hub.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
		return (b as Button).text.begins_with("Deploy to"))
	check(buttons.size() == Worlds.all().size(), "the hub has a deploy button for every world")
	hub.queue_free()
	for world in Worlds.all():
		var kit := world.starter_loadout()
		check(not kit.is_empty() and kit.all(func(id: String) -> bool: return ItemDB.has_item(id)),
				"%s: starter loadout is valid items" % world.id)
		var raid := Raid.new()
		add_child(raid)
		raid.start(world, 99)
		await frames(3)
		check(raid.player != null and not raid.player.is_dead, "%s: player spawns" % world.id)
		check(raid.bots.size() == world.bot_count, "%s: all bots spawn" % world.id)
		check(not raid.exits.is_empty(), "%s: map provides exits" % world.id)
		var caches := raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer)
		check(caches.size() >= 4, "%s: loot caches are placed (%d)" % [world.id, caches.size()])
		var all_valid := true
		for cache: LootContainer in caches:
			for id in cache.items:
				if not ItemDB.has_item(id):
					all_valid = false
		for bot in raid.bots:
			for id in bot.get_drop_items():
				if not ItemDB.has_item(id):
					all_valid = false
		check(all_valid, "%s: every cache and bot carries real items" % world.id)
		for bot in raid.bots:
			check(bot.weapons.size() > 0 and bot.faction != raid.player.faction,
					"%s: %s is armed and hostile" % [world.id, bot.display_name])
			break
		await frames(120)
		check(not raid.is_over or raid.player.is_dead, "%s: a raid runs with bots thinking" % world.id)
		await _end_raid(raid)


func _test_frostline() -> void:
	print("Frostline")
	var world := Worlds.get_world("frostline")
	check(world != null, "frostline is discovered from its folder")
	if world == null:
		return
	check(ItemDB.has_item("frost_signal_core") and ItemDB.has_tag("frost_ice_axe", "melee"),
			"a world registers its own items")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var relay := world.roll_loot("relay", rng)
	check(relay.size() >= 3, "the relay mast cache rolls rich loot")
	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 7)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	var factions := {}
	for bot in raid.bots:
		factions[bot.faction] = factions.get(bot.faction, []) + [bot]
	check(factions.has("warden") and factions.has("feral"), "both enemy factions spawn")
	var relay_caches := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and n.global_position.y > 20.0)
	check(relay_caches.size() == 1, "a cache sits on top of the relay mast")
	if factions.has("warden") and factions.has("feral"):
		var warden: Actor = factions.warden[0]
		var feral: Actor = factions.feral[0]
		check(Combat.deal(feral, DamageInfo.make(5.0, warden, "bullet")), "wardens and ferals hurt each other")
		check(Combat.deal(raid.player, DamageInfo.make(5.0, feral, "melee")), "ferals hurt the player")
		if factions.warden.size() >= 2:
			check(not Combat.deal(factions.warden[1], DamageInfo.make(5.0, warden, "bullet")),
					"a faction does not hurt itself")
	# The ice axe is real gear: it equips as a melee weapon with its stats.
	var axe_holder := Actor.new()
	add_child(axe_holder)
	Loadout.equip(axe_holder, ["frost_ice_axe"])
	var axe := axe_holder.weapons[0] as MeleeWeapon if not axe_holder.weapons.is_empty() else null
	check(axe != null and is_equal_approx(axe.heavy_lunge, 12.0), "the ice axe equips with its own stats")
	axe_holder.queue_free()
	await _end_raid(raid)
