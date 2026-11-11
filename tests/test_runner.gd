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
	await _test_extraction()
	await _test_death()
	await _test_storm()
	await _test_bots_run()
	await _test_main_flow()


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
	check(p.weapons.size() == 2 and p.flight.enabled and p.health.armor == 50.0,
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
	check(bot_b.health.health < before_melee, "blade light attack hits")
	for i in 3:
		await frames(40)
		p.cmd.primary_pressed = true
		await frames(1)
		p.cmd.primary_pressed = false
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
	var carried := p.inventory.items.size()
	var exit_pos := raid.exits[1].global_position
	p.global_position = Vector3(exit_pos.x, 0.2, exit_pos.z)
	await frames(60)
	check(raid.extract_progress() > 0.0, "standing in an exit starts the countdown")
	check(results.is_empty(), "extraction is not instant")
	await frames(240)
	check(results.size() == 1 and results[0].outcome == "extracted", "raid ends as extracted")
	check(Profile.stash.size() == carried and "reactor_core" in Profile.stash,
			"backpack loot lands in the stash")
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
	controller.toggle_view()
	await frames(40)
	check(controller.is_third_person(), "the toggle switches to third-person")
	main.raid.player.kill("test")
	await frames(150)
	check(main.raid == null and main.hub.visible, "dying returns to the hub")
	main.queue_free()
	await frames(2)
