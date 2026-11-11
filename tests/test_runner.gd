extends Node
## Headless test suite. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when everything passes, 1 otherwise.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const RaidRoster := preload("res://core/ui/raid_roster.gd")
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")
const LookTests := preload("res://tests/look_tests.gd")
const CustomizerTests := preload("res://tests/customizer_tests.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	Profile.persist = false
	Profile.reset()
	await _run()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
	# `-- --only online` runs a single group while working on it.
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--only") + 1] if "--only" in args and args.find("--only") + 1 < args.size() else ""
	if only != "":
		await call("_test_" + only)
		return
	_test_registry()
	_test_health()
	_test_inventory_and_items()
	_test_flight_rig()
	await _test_raid_setup_and_movement()
	await _test_combat_and_loot()
	await _test_melee_defense()
	await _test_directional_melee()
	await _test_flight_rigs_and_abilities()
	await _test_vehicle_driving()
	await _test_vehicle_raids()
	await _test_lag_compensation()
	await _test_extraction()
	await _test_loadouts()
	await _test_death()
	await _test_storm()
	await _test_bots_run()
	await _test_main_flow()
	await _test_every_world()
	await _test_frostline()
	await _test_mastery()
	await _test_nameplates_and_scoreboard()
	await _test_online()
	await _test_plaza()
	await _test_plaza_online()
	await _test_stash_service()
	await _test_phone()
	await _test_home_base()
	await LookTests.run(self)
	await CustomizerTests.run(self)


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
	var declared: Array[String] = Boot.declared_classes("res://")
	check("Actor" in declared and "Ability" in declared and "MeleeWeapon" in declared,
			"the boot check finds the project's script classes")
	check(Boot.find_missing_classes().is_empty(), "every script class is registered with Godot")
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
	check(main.nameplates != null and main.scoreboard != null and not main.scoreboard.visible,
			"raid has nameplates and a scoreboard, closed until Tab is held")
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
	# Riding pulls the camera back without touching the on-foot choice.
	var bike = main.raid.spawn_vehicle("bike_scrapper", p.global_position + Vector3(3, 0.3, 0), 0.0)
	await frames(5)
	check(bike.mount(p), "the player gets on a bike")
	await frames(40)
	check(controller.is_third_person() and controller.view_mode == PlayerController.ViewMode.FIRST,
			"riding uses third-person and keeps the on-foot view choice")
	controller.toggle_view()
	await frames(40)
	check(not controller.is_third_person(), "V still switches the view while riding")
	controller.toggle_view()
	bike.dismount()
	await frames(40)
	check(not controller.is_third_person(), "getting off returns to the on-foot view")
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


## A flat test ground with a jump ramp, away from any raid map.
func _vehicle_arena() -> Node3D:
	var arena := Node3D.new()
	arena.name = "VehicleArena"
	add_child(arena)
	arena.position = Vector3(0, 0, 2000)
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(400, 1, 400)
	var ground_col := CollisionShape3D.new()
	ground_col.shape = ground_shape
	ground.add_child(ground_col)
	ground.position.y = -0.5
	arena.add_child(ground)
	# The same ramp the map builds: 8 m long at 15 degrees, rising toward -Z.
	var angle := deg_to_rad(15.0)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = Actor.LAYER_WORLD
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(4, 0.4, 8)
	var ramp_col := CollisionShape3D.new()
	ramp_col.shape = ramp_shape
	ramp.add_child(ramp_col)
	ramp.position = Vector3(60, 4.0 * sin(angle) - 0.2 * cos(angle), -40)
	ramp.basis = Basis(Vector3.RIGHT, angle)
	arena.add_child(ramp)
	return arena


func _test_vehicle_driving() -> void:
	print("Vehicles: driving")
	var arena := _vehicle_arena()
	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	arena.add_child(bike)
	bike.position = Vector3(0, 0.3, 0)
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(3, 0.1, 0)
	await frames(20)
	check(bike.is_on_floor() and is_equal_approx(bike.max_speed, 22.0), "a bike settles and takes its item stats")
	var seat: Interactable = bike.get_node("Seat")
	check(seat.get_prompt().contains("Ride"), "a parked bike offers a ride")
	# The rider stands 3 m to the bike's +X side; yaw PI/2 faces -X.
	rider.cmd.yaw = PI / 2.0
	rider.cmd.pitch = -0.4
	check(rider.find_interactable() == seat, "looking at a bike targets its seat")
	rider.cmd.yaw = 0.0
	rider.cmd.pitch = 0.0
	seat.interact(rider)
	check(rider.vehicle == bike and bike.rider == rider, "interacting gets you on")

	var start: Vector3 = bike.global_position
	rider.cmd.move = Vector2(0, 1)
	await frames(120)
	var dist: float = bike.global_position.distance_to(start)
	check(dist > rider.sprint_speed * 2.0, "the bike outruns sprinting (%.1f m in 2 s)" % dist)
	check(bike.global_position.z < start.z - 10.0, "throttle drives the way the bike points")
	check(rider.global_position.distance_to(bike.global_position) < 1.0, "the rider stays on the seat")
	rider.cmd.sprint = true
	await frames(90)
	check(bike.speed > bike.max_speed + 1.0, "sprint boosts past normal top speed (%.1f)" % bike.speed)
	rider.cmd.sprint = false
	rider.cmd.move = Vector2(-1, 1)
	var heading_before: float = bike.heading
	await frames(30)
	check(bike.heading > heading_before + 0.3, "A steers left")
	rider.cmd.move = Vector2(0, -1)
	await frames(60)
	check(bike.speed < 1.0, "S brakes the bike to a stop")
	rider.cmd.move = Vector2.ZERO
	await frames(30)

	rider.cmd.interact_pressed = true
	await frames(1)
	rider.cmd.interact_pressed = false
	check(rider.vehicle == null and bike.rider == null, "E gets you off")
	var off: float = rider.global_position.distance_to(bike.global_position)
	check(off > 0.8 and off < 2.5, "you step off beside the bike")
	var walk_from := rider.global_position
	rider.cmd.move = Vector2(0, 1)
	await frames(30)
	rider.cmd.move = Vector2.ZERO
	check(rider.global_position.distance_to(walk_from) > 1.0, "back on foot, you walk again")

	# Anyone can take a parked bike, but not one that is being ridden.
	var thief := Actor.new()
	arena.add_child(thief)
	thief.position = bike.position + Vector3(-2, 0, 0)
	await frames(5)
	seat.interact(thief)
	check(thief.vehicle == bike, "someone else can take a parked bike")
	seat.interact(rider)
	check(rider.vehicle == null and bike.rider == thief, "a ridden bike cannot be taken")
	thief.kill("test")
	await frames(2)
	check(bike.rider == null and thief.vehicle == null, "the rider's death leaves the bike behind")

	# Ramp jump, and bailing out mid-air keeps the momentum.
	bike.position = Vector3(60, 0.3, 0)
	bike.heading = 0.0
	bike.speed = 0.0
	bike.velocity = Vector3.ZERO
	await frames(5)
	seat.interact(rider)
	rider.cmd.move = Vector2(0, 1)
	rider.cmd.sprint = true
	var top := 0.0
	var air := 0.0
	var bailed := false
	var bail_speed := 0.0
	for i in 240:
		await frames(1)
		top = maxf(top, bike.position.y)
		air = maxf(air, bike.airborne_time)
		if not bailed and bike.airborne_time > 0.2:
			rider.cmd.interact_pressed = true
			bailed = true
		elif bailed and bail_speed == 0.0:
			rider.cmd.interact_pressed = false
			bail_speed = rider.velocity.length()
			check(rider.vehicle == null and not rider.is_on_floor(), "you can bail out mid-air")
	check(air > 0.4 and top > 2.5, "a ramp launches the bike (%.2f s in the air, %.1f m up)" % [air, top])
	check(bail_speed > 10.0, "bailing out keeps the bike's momentum (%.1f m/s)" % bail_speed)
	arena.queue_free()
	await frames(2)


func _test_vehicle_raids() -> void:
	print("Vehicles: raids")
	var world := Worlds.get_world("ashfront")
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["bike_raider"])
	check(Profile.equip("vehicle", "bike_raider"), "a bike goes in the vehicle slot")
	var kit := Profile.checkout_loadout(world)
	check("bike_raider" in kit and "bike_raider" not in Profile.stash, "deploying takes the bike out of the stash")

	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 61, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(10)
	var p := raid.player
	var own: Array = raid.vehicles.filter(func(v: Node3D) -> bool:
		return v.get("item_id") == "bike_raider" and v.global_position.distance_to(p.global_position) < 5.0)
	check(own.size() == 1, "your bike is parked next to you")
	check("bike_raider" not in p.gear_items and not p.inventory.has_item("bike_raider"),
			"a bike is not carried and does not drop in your bag")
	check(raid.vehicles.size() >= 3, "the map parks abandoned bikes too (%d)" % (raid.vehicles.size() - 1))
	var ramps := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("spawn_vehicle"))
	check(ramps.size() == raid.vehicles.size() - 1, "every vehicle marker gets a bike")

	var results: Array[Dictionary] = []
	raid.ended.connect(func(r: Dictionary) -> void: results.append(r))
	var bike = own[0]
	check(bike.mount(p), "you can ride your own bike")
	var exit_pos := raid.exits[1].global_position
	bike.global_position = Vector3(exit_pos.x, 0.4, exit_pos.z)
	bike.velocity = Vector3.ZERO
	bike.speed = 0.0
	await frames(300)
	check(results.size() == 1 and results[0].outcome == "extracted", "riding into an exit extracts")
	check("bike_raider" in Profile.stash and "bike_raider" in results[0].get("kept_gear", []),
			"riding out takes the bike home")
	await _end_raid(raid)

	# Deploy with it again and die: the bike stays in the raid for anyone to take.
	check(Profile.equip("vehicle", "bike_raider"), "the bike can be equipped again")
	kit = Profile.checkout_loadout(world)
	var raid2 := Raid.new()
	add_child(raid2)
	raid2.start(world, 62, kit)
	for bot in raid2.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(5)
	var results2: Array[Dictionary] = []
	raid2.ended.connect(func(r: Dictionary) -> void: results2.append(r))
	raid2.player.kill("test")
	await frames(2)
	check(results2.size() == 1 and "bike_raider" in results2[0].lost and "bike_raider" not in Profile.stash,
			"dying loses the bike you brought")
	check(Profile.equipped("vehicle") == "", "a lost bike leaves the vehicle slot")
	await _end_raid(raid2)


## Every world folder must honour the map contract and run a raid headless.
func _test_every_world() -> void:
	print("Every world plugs in")
	check(Worlds.raid_worlds().size() >= 2, "registry finds more than one world (%d)" % Worlds.raid_worlds().size())
	var hub := Hub.new()
	add_child(hub)
	await frames(1)
	var buttons := hub.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
		return (b as Button).text.begins_with("Deploy to"))
	check(buttons.size() == Worlds.raid_worlds().size(), "the hub has a deploy button for every world")
	hub.queue_free()
	for world in Worlds.raid_worlds():
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
const MasteryDB := preload("res://core/progression/mastery_db.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const MasteryPanel := preload("res://core/progression/mastery_panel.gd")


func _mastery_raid(p_seed: int, kit: Array[String], picks: Dictionary) -> Raid:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed, kit, picks)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(5)
	return raid


func _test_mastery() -> void:
	print("Mastery")
	# Data: every track is reachable from an item, and every variant names real
	# stats and changes at least two of them (a sidegrade, not an upgrade).
	var item_for := {}
	for id in ["rifle_scrap", "rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher",
			"blade_scrap", "blade_arc", "hammer_breaker", "chip_blink", "chip_barrier", "chip_pulse",
			"plate_light", "frame_runner", "frame_trooper", "frame_bulwark"]:
		item_for[MasteryDB.track_for_item(id)] = id
	check(not item_for.has("") and item_for.size() == MasteryDB.TRACKS.size(),
			"every weapon, ability and frame trains a mastery track, and every track has gear")
	check(MasteryDB.track_for_item("jetpack_mk1") == "" and MasteryDB.track_for_item("medkit") == "",
			"flight rigs and consumables have no mastery")
	var bad: Array[String] = []
	for track: String in MasteryDB.TRACKS:
		var target: Object = null
		if ItemDB.has_tag(item_for[track], "firearm"):
			target = Gun.new()
		elif ItemDB.has_tag(item_for[track], "melee"):
			target = MeleeWeapon.new()
		elif ItemDB.has_tag(item_for[track], "ability"):
			target = Ability.new()
		for v: Dictionary in MasteryDB.variants(track):
			if v.mods.size() < 2:
				bad.append("%s/%s trades nothing" % [track, v.id])
			for stat: String in v.mods:
				if target != null and not stat in target or target == null and stat not in ["armor", "speed", "heat"]:
					bad.append("%s/%s: %s" % [track, v.id, stat])
		if target is Node:
			target.free()
	check(bad.is_empty(), "every variant changes real stats with a tradeoff %s" % [bad])

	# Levels and picks.
	check(MasteryDB.level_for_xp(0) == 0 and MasteryDB.level_for_xp(150) == 1
			and MasteryDB.level_for_xp(99999) == MasteryDB.max_level(), "XP maps to levels")
	var book := MasteryBook.new()
	check(not book.pick("rifle", "long_barrel"), "a locked variant cannot be picked")
	check(book.add_xp("rifle", 450) == 2 and book.level("rifle") == 2, "XP raises the level")
	check(book.pick("rifle", "long_barrel") and book.active_picks() == {"rifle": "long_barrel"},
			"an unlocked variant can be picked")
	check(not book.pick("rifle", "cut_down"), "higher variants stay locked")
	check(book.add_xp("nonsense", 100) == 0 and not book.xp.has("nonsense"), "unknown tracks are ignored")
	var copy := MasteryBook.new()
	copy.load_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	check(copy.xp_for("rifle") == 450 and copy.picked("rifle") == "long_barrel", "mastery survives a save")
	copy.load_dict({"xp": {"rifle": 10}, "picks": {"rifle": "long_barrel", 5: "x"}})
	check(copy.picked("rifle") == "" and copy.active_picks().is_empty(),
			"a saved pick above the saved level is dropped")

	# Variants change the gear the player deploys with, and only theirs.
	var kit: Array[String] = ["rifle_carbine", "blade_scrap", "jetpack_mk1", "frame_runner", "chip_blink"]
	var stock := await _mastery_raid(70, kit, {})
	var sp := stock.player
	var stock_gun := sp.weapons[0] as Gun
	var stock_spread := stock_gun.spread_deg
	var stock_interval := stock_gun.fire_interval
	var stock_armor := sp.health.max_armor
	var stock_speed := sp.walk_speed
	var stock_cd := sp.ability.cooldown
	await _end_raid(stock)
	var picks := {"rifle": "long_barrel", "frame_light": "stripped", "blink": "ward_step"}
	var raid := await _mastery_raid(70, kit, picks)
	var p := raid.player
	var gun := p.weapons[0] as Gun
	check(gun.spread_deg < stock_spread and gun.fire_interval > stock_interval,
			"Long Barrel: tighter spread, slower fire")
	check(p.health.max_armor < stock_armor and p.walk_speed > stock_speed, "Stripped frame: less armor, faster")
	check(p.ability.cooldown > stock_cd and p.ability.blink_shield > 0.0, "Ward Step: shield, longer cooldown")
	var bot := raid.bots[0]
	var stock_bots := true
	for other in raid.bots:
		for w in other.weapons:
			var stats := ItemDB.item_stats(w.item_id)
			if w is Gun and stats.has("spread_deg") and not is_equal_approx((w as Gun).spread_deg, stats.spread_deg):
				stock_bots = false
	check(stock_bots and raid.mastery.actor == p, "bots deploy without the player's variants")

	# Ward Step: arriving from a blink is shielded.
	p.ability.activate()
	var before := p.health.health + p.health.armor
	Combat.deal(p, DamageInfo.make(20.0, bot, "bullet"))
	var loss: float = before - (p.health.health + p.health.armor)
	check(loss > 0.0 and loss < 10.0, "Ward Step shields you right after the blink (lost %.1f of 20)" % loss)

	# XP is earned by type: weapon hits and kills, ability uses, hits taken in the frame.
	var tracker := raid.mastery
	check(tracker.earned.get("blink", 0.0) >= tracker.xp_per_ability_use, "using an ability trains it")
	check(tracker.earned.get("frame_light", 0.0) > 0.0, "taking hits trains your frame")
	Combat.deal(bot, DamageInfo.make(30.0, p, "bullet"))
	check(is_equal_approx(tracker.earned.get("rifle", 0.0), 30.0 * tracker.xp_per_damage),
			"hitting with a rifle trains rifle mastery")
	var bot_hp := bot.health.health + bot.health.armor + 1.0
	Combat.deal(bot, DamageInfo.make(bot_hp, p, "bullet"))
	check(bot.is_dead and tracker.earned.rifle >= bot_hp * tracker.xp_per_damage + tracker.xp_per_kill,
			"kills give bonus XP")
	check(not tracker.earned.has("blade"), "a holstered weapon earns nothing")

	# Dying keeps every point of mastery earned.
	Profile.reset()
	var results: Array[Dictionary] = []
	raid.ended.connect(func(r: Dictionary) -> void: results.append(r))
	p.kill("storm")
	await frames(2)
	var gained: Dictionary = results[0].get("mastery_xp", {}) if results.size() == 1 else {}
	check(results.size() == 1 and results[0].outcome == "died" and gained.get("rifle", 0) > 0,
			"the raid result reports mastery XP even on death")
	check(Profile.mastery.xp_for("rifle") == gained.get("rifle", -1)
			and Profile.mastery.xp_for("blink") == gained.get("blink", -1), "dying banks that XP in the profile")
	check(Profile.stash.is_empty(), "the gear itself is still lost")
	await _end_raid(raid)

	# Extracting adds a bonus for every piece of gear you bring home.
	raid = await _mastery_raid(71, kit, {})
	var bonus := raid.mastery.report(true)
	check(bonus.get("rifle", 0) == raid.mastery.xp_extract_bonus and bonus.has("blade")
			and bonus.has("frame_light") and bonus.has("blink"), "extracting trains all the gear you carried")
	await _end_raid(raid)

	# Hub: the panel shows the tracks of your loadout and what a raid earned.
	Profile.reset()
	var panel := MasteryPanel.new()
	add_child(panel)
	check(panel.loadout_tracks() == ["rifle", "blade", "frame_light"],
			"an empty loadout shows the scrap kit's mastery")
	Profile.mastery.add_xp("rifle", 200)
	var text := panel.describe_earned({"mastery_xp": {"rifle": 100}})
	check("Rifle +100" in text and "level 1!" in text, "the hub announces a level up")
	panel.refresh()
	await frames(1)
	check(panel._rows.get_child_count() == 3, "one row per loadout track")
	panel.queue_free()
	Profile.reset()


# --- Online ------------------------------------------------------------------

func _wait_until(condition: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await frames(1)
	return condition.call()


const NET_ACCOUNTS := "user://test_accounts_net"
var _net_secrets := {}


func _wipe_dir(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for sub in DirAccess.get_directories_at(dir):
			_wipe_dir(dir.path_join(sub))
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _start_server(port: int, extra: Array[String]) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server", "--world", "ashfront", "--port", str(port), "--accounts", NET_ACCOUNTS])
	# One world alone on the port, unless the test asks for the plaza too.
	if "--plaza" not in extra:
		args.append("--no-plaza")
	args.append_array(PackedStringArray(extra))
	return OS.create_process(OS.get_executable_path(), args)


## A client in its own 3D world, so two clients in this process never collide.
## Each name keeps one secret for the whole test run, like a real player.
func _new_client(shown_name: String, secret := "") -> NetSession:
	var view := SubViewport.new()
	view.own_world_3d = true
	add_child(view)
	var session := NetSession.new()
	session.name = "Net"
	session.player_name = shown_name
	if not _net_secrets.has(shown_name):
		_net_secrets[shown_name] = StashService.new_secret()
	session.secret = secret if secret != "" else _net_secrets[shown_name]
	view.add_child(session)
	return session


## Connects and signs in, retrying while the server process is still starting
## up. Returns the session in the lobby, or null.
func _sign_in(session_name: String, port: int) -> NetSession:
	for attempt in 20:
		var session := _new_client(session_name)
		var state := {"failed": false}
		session.failed.connect(func(_reason: String) -> void: state.failed = true)
		session.join("127.0.0.1", port)
		await _wait_until(func() -> bool: return state.failed or not session.account.is_empty(), 240)
		if not session.account.is_empty():
			return session
		session.get_parent().queue_free()
		await frames(30)
	return null


## Signs in, equips `gear` (slot -> item id) in the lobby, and deploys.
func _join(session_name: String, port: int, gear := {}) -> NetSession:
	var session := await _sign_in(session_name, port)
	if session == null:
		return null
	for slot: String in gear:
		session.equip(slot, gear[slot])
	await _wait_until(func() -> bool:
		return gear.keys().all(func(slot: String) -> bool:
			return session.account.loadout.get(slot, "") == gear[slot]), 120)
	session.deploy()
	await _wait_until(func() -> bool: return session.raid != null and session.raid.player != null, 240)
	if session.raid != null and session.raid.player != null:
		return session
	session.get_parent().queue_free()
	await frames(2)
	return null


func _leave(session: NetSession) -> void:
	if session != null and is_instance_valid(session):
		session.get_parent().queue_free()
	await frames(2)


func _test_nameplates_and_scoreboard() -> void:
	print("Nameplates and scoreboard")
	check(InputMap.has_action("scoreboard") and InputMap.action_get_events("scoreboard").any(
			func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_TAB),
			"Tab is bound to the scoreboard")
	var raid := Raid.new()
	add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player([], {}, "Bravo")
	var c := raid.add_player([], {}, "Charlie")
	await frames(5)
	var roster := RaidRoster.new(raid, a)
	roster.refresh()
	var board := ScoreboardScript.new()
	board.setup(raid, a)
	raid.add_child(board)
	await frames(1)
	check(roster.entries.size() == 3 and roster.entries.all(
			func(e: Dictionary) -> bool: return e.status == RaidRoster.IN_RAID),
			"the roster lists every player as in the raid")
	check(roster.bots_alive() == raid.bots.size(), "the roster counts the bots still standing")
	b.kill("bullet", a)
	raid._on_actor_extracted(c)
	await frames(3)
	roster.refresh()
	var by_name := {}
	for e in roster.entries:
		by_name[e.name] = e
	check(by_name.Alpha.kills == 1 and by_name.Alpha.is_me and by_name.Alpha.status == RaidRoster.IN_RAID,
			"your kills are counted on the scoreboard")
	check(by_name.Bravo.status == RaidRoster.DOWN, "a player who died shows as down")
	check(by_name.Charlie.status == RaidRoster.EXTRACTED, "a player who left alive shows as extracted")
	check(roster.entries[0].name == "Alpha", "players still in the raid are listed first")

	check(not board.visible, "the scoreboard is closed until asked for")
	board.show_board(true)
	var rows: Array = board.rows()
	check(board.visible and rows.size() == 3 and rows[0] == ["Alpha (you)", RaidRoster.IN_RAID, "1"],
			"the scoreboard shows each player's name, status and kills")
	board.show_board(false)
	check(not board.visible, "the scoreboard closes again")

	# Nameplates, high above the map so only the test's own wall can block the view.
	var d := raid.add_player([], {}, "Delta")
	var camera := Camera3D.new()
	raid.add_child(camera)
	camera.make_current()
	var plates := NameplatesScript.new()
	plates.setup(raid, a)
	raid.add_child(plates)
	var sky := a.global_position + Vector3(0, 120, 0)
	var place := func(d_offset: Vector3, facing: Vector3) -> void:
		a.global_position = sky
		d.global_position = sky + d_offset
		b.global_position = sky + Vector3(0, 0, -5)
		camera.global_position = sky + Vector3(0, 1.6, 0)
		camera.look_at(camera.global_position + facing)
		plates.update_plates()
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	var shown: Dictionary = plates.plates()
	check(shown.has(d.get_instance_id()) and not shown.has(a.get_instance_id()),
			"another player in view gets a nameplate, you do not")
	check(not shown.has(b.get_instance_id()), "a player who is down has no nameplate")
	if shown.has(d.get_instance_id()):
		var plate: Control = shown[d.get_instance_id()]
		var label: Label = plate.get_child(0)
		var middle := camera.get_viewport().get_visible_rect().size * 0.5
		check(label.text == "Delta" and plate.position.x < middle.x and plate.position.x + plate.size.x > middle.x,
				"the nameplate carries the name and sits over the player")
	place.call(Vector3(0, -0.5, -10), Vector3.BACK)
	check(plates.plates().is_empty(), "no nameplate for a player behind you")
	place.call(Vector3(0, -0.5, -(plates.max_distance + 5.0)), Vector3.FORWARD)
	check(plates.plates().is_empty(), "no nameplate past the nameplate range")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(6, 6, 0.5)
	wall.add_child(shape)
	raid.add_child(wall)
	wall.global_position = sky + Vector3(0, 1, -5)
	await frames(1)
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	check(plates.plates().is_empty(), "no nameplate through a wall")
	wall.queue_free()
	await frames(1)
	d.kill("bullet")
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	check(plates.plates().is_empty(), "the nameplate goes when the player goes down")
	await _end_raid(raid)


func _test_online() -> void:
	print("Online: commands and raids with several players")
	var cmd := ActorCommand.new()
	cmd.move = Vector2(0.5, -1.0)
	cmd.yaw = 1.25
	cmd.pitch = -0.4
	cmd.aim_dir = Vector3(0, 0, -1)
	cmd.sprint = true
	cmd.primary = true
	cmd.dash = true
	cmd.ability_pressed = true
	cmd.stance = 2
	cmd.switch_weapon = 1
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	check(copy.move.is_equal_approx(cmd.move.limit_length(1.0)) and is_equal_approx(copy.yaw, 1.25)
			and copy.sprint and copy.primary and copy.dash and copy.ability_pressed
			and not copy.jump and not copy.heal_pressed and copy.stance == 2 and copy.switch_weapon == 1,
			"a command survives the trip through its network form")
	copy.apply_array([99.0, 99.0, "x", 50.0, NAN, 0.0, 0.0, 0, 7, 99])
	check(copy.move.length() <= 1.001 and is_zero_approx(copy.yaw) and copy.pitch <= 1.5
			and copy.aim_dir == Vector3.ZERO and copy.stance == 2 and copy.switch_weapon <= 8,
			"a command from the network is clamped to legal values")
	copy.apply_array([1.0])
	check(copy.stance == 2, "a malformed command is ignored")
	check(cmd.flags() & ActorCommand.ONE_SHOT_MASK != 0 and cmd.flags() & ActorCommand.HELD_MASK != 0
			and ActorCommand.ONE_SHOT_MASK & ActorCommand.HELD_MASK == 0, "held keys and presses are told apart")

	# A server raid with two players, no network involved.
	Profile.reset()
	Profile.welcome_granted = true
	var raid := Raid.new()
	add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 70)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	check(raid.player == null and raid.players.is_empty() and raid.bots.size() == raid.world.bot_count,
			"a server raid starts with bots and no players")
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player(["rifle_carbine", "blade_scrap", "jetpack_mk1", "plate_light"], {}, "Bravo")
	await frames(20)
	check(raid.players.size() == 2 and a.weapons.size() == 2 and b.weapons[0].display_name == "Ashfront Carbine"
			and not a.is_player, "players join a server raid with their own kits")
	var finished := []
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void: finished.append([actor, result]))
	var ended := [false]
	raid.ended.connect(func(_r: Dictionary) -> void: ended[0] = true)
	b.kill("bullet", a)
	await frames(5)
	check(finished.size() == 1 and finished[0][0] == b and finished[0][1].outcome == "died"
			and "rifle_carbine" in finished[0][1].lost, "a player who dies gets their own result")
	check(raid.state_for(a).kills == 1 and not raid.is_over and not ended[0] and not a.is_dead,
			"the raid carries on for the others, and the kill is credited")
	check(Profile.stash.is_empty() and Profile.raids_played == 0, "a server raid never touches a profile")
	a.inventory.add_item("scrap_metal")
	raid._on_actor_extracted(a)
	await frames(2)
	check(finished.size() == 2 and finished[1][1].outcome == "extracted"
			and "scrap_metal" in finished[1][1].brought_home, "an extracting player gets a result listing what comes home")
	Raid.apply_result(finished[1][1])
	check("scrap_metal" in Profile.stash and Profile.raids_extracted == 1, "the result can be applied to the player's own profile")
	raid.remove_player(b)
	await _end_raid(raid)
	Profile.reset()

	# Containers and vehicles are announced, so a server can replicate them.
	raid = Raid.new()
	add_child(raid)
	var announced := {"containers": 0, "vehicles": 0, "removed": 0}
	raid.container_spawned.connect(func(_c: LootContainer) -> void: announced.containers += 1)
	raid.vehicle_spawned.connect(func(_v: Node3D) -> void: announced.vehicles += 1)
	raid.vehicle_removed.connect(func(_v: Node3D) -> void: announced.removed += 1)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var map_vehicles := raid.vehicles.size()
	check(announced.containers > 3 and announced.vehicles == map_vehicles, "a server raid announces its caches and vehicles")
	var rider := raid.add_player(raid.world.starter_loadout() + (["bike_scrapper"] as Array[String]), {}, "Rider")
	await frames(10)
	check(raid.vehicles.size() == map_vehicles + 1 and raid.state_for(rider).deployed_vehicles == (["bike_scrapper"] as Array[String]),
			"a player who brings a vehicle to a server raid finds it beside them")
	var own_bike: Node3D = raid.vehicles[raid.vehicles.size() - 1]
	check(own_bike.call("mount", rider), "they can ride it")
	var outcome := [{}]
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: outcome[0] = r)
	var bags_before: int = announced.containers
	raid._on_actor_extracted(rider)
	await frames(3)
	check("bike_scrapper" in outcome[0].get("brought_home", []) and announced.removed == 1
			and (not is_instance_valid(own_bike) or own_bike not in raid.vehicles), "extracting on a vehicle takes it home and out of the raid")
	check(announced.containers == bags_before, "extracting leaves no loot bag behind")
	await _end_raid(raid)

	print("Online: a real server and two clients")
	_wipe_dir(NET_ACCOUNTS)
	var port := 24811
	var pid := _start_server(port, [])
	check(pid > 0, "a dedicated server process starts")
	var alpha := await _join("Alpha", port)
	check(alpha != null, "a client connects and joins the raid")
	if alpha == null:
		OS.kill(pid)
		return
	var world := Worlds.get_world("ashfront")
	check(alpha.raid.mode == Raid.Mode.CLIENT and alpha.raid.player.weapons.size() == 2
			and alpha.raid.player.is_player and not Combat.authoritative,
			"the client has its own actor and leaves damage to the server")
	await _wait_until(func() -> bool: return alpha.raid.bots.size() == world.bot_count, 180)
	check(alpha.raid.bots.size() == world.bot_count, "the client sees the server's bots")
	check(alpha.raid.time_left > 0.0 and alpha.raid.time_left < world.raid_duration, "the raid clock comes from the server")
	var bravo := await _join("Bravo", port)
	check(bravo != null, "a second client joins the same raid")
	if bravo != null:
		var see_each_other := func() -> bool:
			return bravo.actor_for(alpha.my_actor_id) != null and alpha.actor_for(bravo.my_actor_id) != null
		await _wait_until(see_each_other, 180)
		var seen := bravo.actor_for(alpha.my_actor_id)
		check(seen != null and seen.display_name == "Alpha" and seen.weapons.size() == 2 and not seen.is_player,
				"each client sees the other player, with their name and gear")
		check(bravo.raid.players.size() == 2 and bravo.raid.active_players().size() == 2
				and alpha.raid.bots.size() == world.bot_count,
				"a client's raid lists the players, separate from the bots")
		if seen != null:
			var from := seen.global_position
			alpha.raid.player.cmd.move = Vector2(0, 1)
			await frames(90)
			alpha.raid.player.cmd.move = Vector2.ZERO
			await frames(30)
			var moved := from.distance_to(seen.global_position)
			check(moved > 3.0, "one player's movement reaches the other through the server (%.1f m)" % moved)
			var apart := seen.global_position.distance_to(alpha.raid.player.global_position)
			check(apart < 2.0, "both clients agree where that player is (%.2f m apart)" % apart)
		var roster := RaidRoster.new(bravo.raid, bravo.raid.player)
		roster.refresh()
		var names := roster.entries.map(func(e: Dictionary) -> String: return e.name)
		check(roster.entries.size() == 2 and "Alpha" in names and "Bravo" in names
				and roster.entries.all(func(e: Dictionary) -> bool: return e.status == RaidRoster.IN_RAID),
				"a client's scoreboard lists both players and none of the bots")
	await _leave(bravo)
	await _leave(alpha)
	OS.kill(pid)
	await frames(30)

	print("Online: fighting through the server")
	port = 24812
	pid = _start_server(port, ["--bots", "0", "--squad-spawn"])
	alpha = await _join("Alpha", port, {"vehicle": "bike_scrapper"})
	bravo = await _join("Bravo", port) if alpha != null else null
	check(alpha != null and bravo != null, "two clients join a squad-spawn server")
	if alpha != null and bravo != null:
		await _wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) != null, 180)
		var me := alpha.raid.player
		var target := alpha.actor_for(bravo.my_actor_id)
		var victim := bravo.raid.player
		var face := func(point: Vector3) -> void:
			var aim := point - me.get_eye_position()
			me.cmd.aim_dir = aim.normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			me.cmd.pitch = asin(clampf(aim.normalized().y, -1.0, 1.0))
		var press_use := func() -> void:
			me.cmd.interact_pressed = true
			await frames(1)
			me.cmd.interact_pressed = false

		# Loot caches and the bike Alpha brought exist on both clients.
		await _wait_until(func() -> bool: return not alpha.vehicles().is_empty() and not bravo.vehicles().is_empty(), 120)
		check(alpha.containers().size() > 3 and alpha.containers().size() == bravo.containers().size(),
				"both clients see the server's loot caches (%d)" % alpha.containers().size())
		check(alpha.vehicles().size() >= 1 and bravo.vehicles().size() == alpha.vehicles().size(),
				"both clients see the vehicle a player brought")
		var bike: Node3D = null
		for v: Node3D in alpha.vehicles():
			if bike == null or v.global_position.distance_to(me.global_position) \
					< bike.global_position.distance_to(me.global_position):
				bike = v
		if bike != null:
			var their_bike: Node3D = null
			for v: Node3D in bravo.vehicles():
				if v.global_position.distance_to(bike.global_position) < 1.5:
					their_bike = v
			face.call(bike.global_position + Vector3(0, 0.6, 0))
			await frames(6)
			await press_use.call()
			await _wait_until(func() -> bool: return me.vehicle == bike, 90)
			check(me.vehicle == bike and bike.get("rider") == me, "pressing use on the bike mounts it, by the server's say")
			var bike_from := bike.global_position
			me.cmd.move = Vector2(0, 1)
			await frames(30)
			me.cmd.move = Vector2.ZERO
			await frames(10)
			check(bike.global_position.distance_to(bike_from) > 0.5
					and me.global_position.distance_to(bike.global_position) < 1.5,
					"the server drives the bike and the rider goes with it")
			var seen_rider := bravo.actor_for(alpha.my_actor_id)
			check(their_bike != null and their_bike.get("rider") == seen_rider
					and their_bike.global_position.distance_to(bike.global_position) < 3.0,
					"the other client sees the same player riding the same bike")
			await press_use.call()
			await _wait_until(func() -> bool: return me.vehicle == null, 90)
			check(me.vehicle == null and bike.get("rider") == null, "pressing use again gets off")
			await frames(20)
		check(alpha.raid.bots.is_empty() and target != null
				and me.global_position.distance_to(target.global_position) < 12.0,
				"squad spawn puts the players together")
		var hits := [0]
		var notices: Array[String] = []
		me.hit_confirmed.connect(func(_t: Actor, _i: DamageInfo, _l: bool) -> void: hits[0] += 1)
		me.notice.connect(func(text: String) -> void: notices.append(text))
		var result := [{}]
		bravo.run_finished.connect(func(r: Dictionary) -> void: result[0] = r)
		var before := victim.health.health + victim.health.armor
		me.cmd.primary = true
		for i in 600:
			if target == null or not is_instance_valid(target) or target.is_dead or not result[0].is_empty():
				break
			var aim := (target.global_position + Vector3(0, 1.1, 0)) - me.get_eye_position()
			me.cmd.aim_dir = aim.normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			# Close in, so nothing on the map sits between them.
			me.cmd.move = Vector2(0, 1) if aim.length() > 4.0 else Vector2.ZERO
			if i % 40 == 39:
				me.cmd.reload_pressed = true
			await frames(1)
			me.cmd.reload_pressed = false
		me.cmd.primary = false
		me.cmd.move = Vector2.ZERO
		check(hits[0] > 0, "the shooter is told about hits the server confirmed (%d)" % hits[0])
		await _wait_until(func() -> bool: return not result[0].is_empty(), 240)
		check(victim.health.health + victim.health.armor < before or victim.is_dead,
				"the victim's health drops on their own screen")
		check(result[0].get("outcome", "") == "died" and not result[0].get("lost", []).is_empty(),
				"the server tells a player their run is over and what they lost")
		await _wait_until(func() -> bool: return victim.is_dead, 60)
		check(victim.is_dead, "the dead player falls on their own screen")
		check(notices.any(func(text: String) -> bool: return text.begins_with("Killed ")),
				"the killer gets the kill notice from the server")
		var scores := func() -> bool:
			var mine := alpha.raid.state_for(me)
			var theirs := bravo.raid.state_for(bravo.actor_for(alpha.my_actor_id))
			return mine != null and mine.kills == 1 and theirs != null and theirs.kills == 1
		await _wait_until(scores, 90)
		check(scores.call() and alpha.raid.kills == 1, "every client is told each player's kill count")
		# The dead player's bag appears for the killer, who walks over and loots it.
		var found: Array[LootContainer] = []
		var find_bag := func() -> bool:
			for c: Variant in alpha.containers():
				if is_instance_valid(c) and c.is_bag and found.is_empty():
					found.append(c)
			return not found.is_empty()
		await _wait_until(find_bag, 120)
		var bag: LootContainer = found[0] if not found.is_empty() else null
		check(bag != null and not bag.items.is_empty(), "the dead player's bag appears on the killer's screen")
		if bag != null:
			var bag_id := bag.get_instance_id()
			var carried := me.inventory.items.size()
			var looted := func() -> bool: return me.inventory.items.size() > carried
			for i in 600:
				if looted.call() or not is_instance_valid(bag):
					break
				face.call(bag.global_position + Vector3(0, 0.3, 0))
				var gap := Vector2(bag.global_position.x - me.global_position.x,
						bag.global_position.z - me.global_position.z).length()
				me.cmd.move = Vector2(0, 1) if gap > 1.6 else Vector2.ZERO
				me.cmd.interact_pressed = gap <= 2.6 and i % 10 == 0
				await frames(1)
			me.cmd.move = Vector2.ZERO
			me.cmd.interact_pressed = false
			await _wait_until(looted, 60)
			check(looted.call(), "looting the bag fills the backpack from the server (%d items)" % me.inventory.items.size())
			check(notices.any(func(text: String) -> bool: return text.begins_with("Looted ")),
					"the looter is told what they picked up")
			var bag_gone := func() -> bool: return not is_instance_id_valid(bag_id)
			await _wait_until(bag_gone, 90)
			check(bag_gone.call(), "the emptied bag disappears on the client too")
		await _wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) == null, 400)
		check(alpha.actor_for(bravo.my_actor_id) == null, "a dead player is removed from the other client's raid")
	await _leave(bravo)
	await _leave(alpha)
	OS.kill(pid)
	await frames(30)
	await _test_online_stash()
	await _test_online_movement()
	await _test_online_lag_compensation()
	await _test_online_riding()
	_wipe_dir(NET_ACCOUNTS)
	check(Combat.authoritative, "leaving an online raid hands damage back to this game")


func _test_online_movement() -> void:
	print("Online: smooth movement on a bad connection")
	var port := 24816
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var dana := await _join("Dana", port)
	var eli := await _join("Eli", port) if dana != null else null
	check(dana != null and eli != null, "two clients join for the movement checks")
	if dana == null or eli == null:
		await _leave(eli)
		await _leave(dana)
		OS.kill(pid)
		return
	await _wait_until(func() -> bool: return eli.actor_for(dana.my_actor_id) != null, 180)
	var me := dana.raid.player
	var seen := eli.actor_for(dana.my_actor_id)
	await frames(30)

	# 120 ms each way: the server's answers describe where you were a quarter
	# of a second ago.
	dana.simulated_lag = 0.12
	await frames(40)
	dana.max_correction = 0.0
	var from := me.global_position
	var worst_step := 0.0
	var last := from
	me.cmd.move = Vector2(0, 1)
	me.cmd.sprint = true
	for i in 150:
		await frames(1)
		# A pull backwards shows up as a tick that moves you less than nothing.
		var step := (me.global_position - last).dot((me.global_position - from).normalized()) if i > 20 else 0.0
		worst_step = minf(worst_step, step)
		last = me.global_position
	var ran := from.distance_to(me.global_position)
	me.cmd.move = Vector2.ZERO
	me.cmd.sprint = false
	check(ran > 6.0, "a lagging player still runs at full speed (%.1f m)" % ran)
	check(dana.max_correction < 0.4, "running on a slow connection needs no real correction (worst %.2f m)" % dana.max_correction)
	check(worst_step > -0.02, "the player is never pulled backwards while running (%.3f m)" % worst_step)
	await frames(90)
	var apart := seen.global_position.distance_to(me.global_position) if is_instance_valid(seen) else 99.0
	check(apart < 0.5, "after stopping, the other player sees them where they are (%.2f m apart)" % apart)

	# One in five input packets lost: a single-tick press must still arrive.
	dana.simulated_lag = 0.04
	dana.simulated_loss = 0.2
	await frames(60)
	dana.max_correction = 0.0
	var ground := me.global_position.y
	var top := 0.0
	var seen_jumps := 0
	for jump in 5:
		me.cmd.jump_pressed = true
		await frames(1)
		me.cmd.jump_pressed = false
		var seen_top := 0.0
		for i in 80:
			await frames(1)
			top = maxf(top, me.global_position.y - ground)
			seen_top = maxf(seen_top, seen.global_position.y - ground)
		if seen_top > 0.6:
			seen_jumps += 1
	check(top > 0.6, "the player jumps on their own screen at once (%.2f m)" % top)
	check(seen_jumps == 5, "every jump reaches the server despite lost packets (%d of 5 seen by the other player)" % seen_jumps)
	dana.simulated_loss = 0.0

	# Other players glide between updates instead of stepping.
	me.cmd.move = Vector2(1, 0)
	await frames(30)
	var biggest := 0.0
	var smallest := 99.0
	var prev := seen.global_position
	for i in 60:
		await frames(1)
		var moved := seen.global_position.distance_to(prev)
		prev = seen.global_position
		biggest = maxf(biggest, moved)
		smallest = minf(smallest, moved)
	me.cmd.move = Vector2.ZERO
	check(smallest > 0.0 and biggest < smallest * 2.5 + 0.02,
			"another player's movement is even from tick to tick (%.3f to %.3f m)" % [smallest, biggest])
	await _leave(eli)
	await _leave(dana)
	OS.kill(pid)
	await frames(30)


## The yaw that turns an actor to look along `dir`.
static func _yaw_toward(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _test_online_lag_compensation() -> void:
	print("Online: a lagging shooter hits what is on their screen")
	var with_rewind := await _lagged_shots(24817, [])
	var without := await _lagged_shots(24818, ["--no-rewind"])
	check(with_rewind.size() == 2 and without.size() == 2, "two duels on a slow connection ran")
	if with_rewind.size() != 2 or without.size() != 2:
		return
	check(with_rewind[0] >= 4,
			"aiming straight at a running player on a 100 ms connection hits (%d of %d)" % with_rewind)
	check(without[0] <= 1,
			"without rewinding the same shots miss, so the hits come from lag compensation (%d of %d)" % without)


## Dana, on a 100 ms connection, aims exactly where she sees Eli while he
## strafes past, and fires single shots. Returns [hits, shots], or [] if the
## players could not join.
func _lagged_shots(port: int, extra: Array[String]) -> Array:
	var args: Array[String] = ["--bots", "0", "--squad-spawn"]
	args.append_array(extra)
	var pid := _start_server(port, args)
	var dana := await _join("Dana", port)
	var eli := await _join("Eli", port) if dana != null else null
	if dana != null and eli != null:
		await _wait_until(func() -> bool: return dana.actor_for(eli.my_actor_id) != null, 180)
	var seen := dana.actor_for(eli.my_actor_id) if dana != null and eli != null else null
	if seen == null:
		await _leave(eli)
		await _leave(dana)
		OS.kill(pid)
		await frames(30)
		return []
	var me := dana.raid.player
	var runner := eli.raid.player
	var hits := [0]
	me.hit_confirmed.connect(func(target: Actor, _info: DamageInfo, _lethal: bool) -> void:
		if target == seen:
			hits[0] += 1)
	dana.simulated_lag = 0.1
	await frames(40)
	# Eli backs away from Dana for some room, then strafes across her view.
	var away := runner.global_position - me.global_position
	away.y = 0.0
	runner.cmd.yaw = _yaw_toward(-away.normalized() if away.length() > 0.1 else Vector3.FORWARD)
	runner.cmd.move = Vector2(0, -1)
	await frames(30)
	runner.cmd.move = Vector2(1, 0)
	me.cmd.secondary = true
	var shots := 0
	for i in 80:
		if is_instance_valid(seen) and not seen.is_dead:
			var dir := (seen.global_position + Vector3(0, 1.1, 0) - me.get_eye_position()).normalized()
			me.cmd.aim_dir = dir
			me.cmd.yaw = _yaw_toward(dir)
			me.cmd.pitch = asin(dir.y)
			me.cmd.primary = i >= 20 and i % 12 == 8 and shots < 5
			if me.cmd.primary:
				shots += 1
		await frames(1)
	me.cmd.primary = false
	me.cmd.secondary = false
	runner.cmd.move = Vector2.ZERO
	await frames(40)
	await _leave(eli)
	await _leave(dana)
	OS.kill(pid)
	await frames(30)
	return [hits[0], shots]


func _test_online_riding() -> void:
	print("Online: riding responds at once on a slow connection")
	var port := 24819
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var faye := await _join("Faye", port, {"vehicle": "bike_scrapper"})
	var gus := await _join("Gus", port) if faye != null else null
	check(faye != null and gus != null, "two clients join for the riding checks")
	var bike: Node3D = null
	if faye != null and gus != null:
		await _wait_until(func() -> bool: return not faye.vehicles().is_empty(), 120)
		for v: Node3D in faye.vehicles():
			if bike == null or v.global_position.distance_to(faye.raid.player.global_position) \
					< bike.global_position.distance_to(faye.raid.player.global_position):
				bike = v
	if bike == null:
		check(false, "the rider's bike is there")
		await _leave(gus)
		await _leave(faye)
		OS.kill(pid)
		await frames(30)
		return
	var me := faye.raid.player
	var aim := bike.global_position + Vector3(0, 0.6, 0) - me.get_eye_position()
	me.cmd.aim_dir = aim.normalized()
	me.cmd.yaw = _yaw_toward(aim)
	me.cmd.pitch = asin(clampf(aim.normalized().y, -1.0, 1.0))
	await frames(6)
	me.cmd.interact_pressed = true
	await frames(1)
	me.cmd.interact_pressed = false
	await _wait_until(func() -> bool: return me.vehicle == bike, 90)
	check(me.vehicle == bike, "the rider gets on")
	faye.simulated_lag = 0.12
	await frames(40)
	faye.max_correction = 0.0
	var from := bike.global_position
	me.cmd.move = Vector2(0, 1)
	# The server only hears about it after 120 ms, about 7 ticks.
	await frames(6)
	check(bike.global_position.distance_to(from) > 0.06,
			"on a 120 ms connection the bike pulls away the moment the throttle opens (%.2f m)" % bike.global_position.distance_to(from))
	var heading: float = bike.get("heading")
	me.cmd.move = Vector2(0.7, 1)
	await frames(40)
	check(absf(angle_difference(heading, bike.get("heading"))) > 0.3, "steering turns the bike at once")
	me.cmd.move = Vector2(-0.5, 1)
	await frames(40)
	me.cmd.move = Vector2(0, -1)
	await _wait_until(func() -> bool: return float(bike.get("speed")) <= 0.5, 120)
	me.cmd.move = Vector2.ZERO
	check(faye.max_correction < 0.5, "the server agrees with the predicted ride (worst %.2f m)" % faye.max_correction)
	await frames(60)
	var their_bike: Node3D = null
	for v: Node3D in gus.vehicles():
		if their_bike == null or v.global_position.distance_to(bike.global_position) \
				< their_bike.global_position.distance_to(bike.global_position):
			their_bike = v
	var apart := their_bike.global_position.distance_to(bike.global_position) if their_bike != null else 99.0
	check(apart < 0.5, "after stopping, the other player sees the bike where the rider has it (%.2f m apart)" % apart)
	check(me.vehicle == bike and me.global_position.distance_to(bike.global_position) < 1.5,
			"the rider stays on the predicted bike")
	await _leave(gus)
	await _leave(faye)
	OS.kill(pid)
	await frames(30)


func _test_lag_compensation() -> void:
	print("Lag compensation: hits are tested where the attacker saw the target")
	var arena := _vehicle_arena()
	var shooter := Actor.new()
	arena.add_child(shooter)
	shooter.global_position = arena.global_position
	var target := Actor.new()
	arena.add_child(target)
	target.global_position = arena.global_position + Vector3(0, 0, -8)
	Loadout.equip(shooter, ["rifle_scrap"])
	await frames(5)
	var eye := shooter.get_eye_position()
	var chest := Vector3(0, 1.1, 0)
	var now: Vector3 = target.global_position
	var then: Vector3 = now + Vector3(3, 0, 0)
	var hit := Combat.trace(shooter, eye, eye + (now + chest - eye) * 3.0)
	check(hit.get("collider") == target, "with nothing to make up, a shot hits where the target is")
	check(Combat.positions_seen_by(shooter).is_empty(), "offline nothing is rewound")

	# What a lagging shooter saw: the target three metres to the side.
	Combat.rewind = func(attacker: Actor) -> Dictionary:
		return {target: then} if attacker == shooter else {}
	hit = Combat.trace(shooter, eye, eye + (now + chest - eye) * 3.0)
	check(hit.get("collider") != target, "a rewound target is not hit where it has moved on to")
	hit = Combat.trace(shooter, eye, eye + (then + chest - eye) * 3.0)
	check(hit.get("collider") == target and hit.position.distance_to(then + chest) < 0.5,
			"a rewound target is hit where the shooter saw it")
	hit = Combat.trace(target, target.get_eye_position(), shooter.global_position + chest)
	check(hit.get("collider") == shooter, "anyone without a rewind shoots at the present")
	hit = Combat.trace(shooter, eye, eye + Vector3(0, 0, -1) * 20.0 + Vector3(0, 10, 0))
	check(hit.is_empty() or hit.get("collider") is not Actor, "a shot over everyone's head hits nobody")

	# Walls still stop the shot.
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2, 4, 0.4)
	var wall_col := CollisionShape3D.new()
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	arena.add_child(wall)
	wall.global_position = arena.global_position.lerp(then, 0.5) + Vector3(0, 1, 0)
	await frames(2)
	hit = Combat.trace(shooter, eye, eye + (then + chest - eye) * 3.0)
	check(hit.get("collider") == wall, "a wall in front of where the target was still stops the shot")
	wall.queue_free()
	await frames(2)

	# The gun uses it.
	var before := target.health.health + target.health.armor
	var dir := (then + chest - eye).normalized()
	shooter.cmd.aim_dir = dir
	shooter.cmd.yaw = _yaw_toward(dir)
	shooter.cmd.primary = true
	await frames(1)
	shooter.cmd.primary = false
	check(target.health.health + target.health.armor < before, "a rifle shot at where the target was seen lands")

	# Every attacker has their own view of the others.
	var seen_close := now + Vector3(0, 0, 6.5)
	Combat.rewind = func(attacker: Actor) -> Dictionary:
		return {target: seen_close} if attacker == shooter else {}
	check(Combat.positions_seen_by(shooter).get(target) == seen_close and Combat.positions_seen_by(target).is_empty(),
			"each attacker gets their own view of the others")
	Combat.rewind = Callable()
	check(Combat.positions_seen_by(shooter).is_empty(), "clearing the rewind goes back to the present")
	arena.queue_free()
	await frames(2)


func _test_online_stash() -> void:
	print("Online: the server owns the stash")
	var local_stash := Profile.stash.duplicate()
	var port := 24813
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var cara := await _sign_in("Cara", port)
	check(cara != null, "a client signs in and waits in the lobby")
	if cara == null:
		OS.kill(pid)
		return
	check(cara.raid == null and cara.my_actor_id < 0, "signing in does not enter the raid")
	check("rifle_carbine" in cara.account.stash and cara.account.loadout.is_empty() and not cara.account.has("secret_hash"),
			"the lobby shows the stash the server keeps, with a new account's crates")

	# Someone else cannot take the name.
	var thief := _new_client("Cara", StashService.new_secret())
	var refusal := [""]
	thief.failed.connect(func(reason: String) -> void: refusal[0] = reason)
	thief.join("127.0.0.1", port)
	await _wait_until(func() -> bool: return refusal[0] != "", 240)
	check(refusal[0] != "" and thief.refused and thief.account.is_empty(), "the same name with another secret is refused (%s)" % refusal[0])
	await _leave(thief)

	# Loadout changes are requests. The server checks them against its stash.
	var errors: Array[String] = []
	cara.lobby_error.connect(func(reason: String) -> void: errors.append(reason))
	cara.equip("primary", "dmr_longshot")
	await _wait_until(func() -> bool: return not errors.is_empty(), 120)
	check(errors.size() == 1 and cara.account.loadout.is_empty(), "the server refuses gear the account does not own")
	cara.equip("primary", "rifle_carbine")
	await _wait_until(func() -> bool: return cara.account.loadout.get("primary", "") == "rifle_carbine", 120)
	check(cara.account.loadout.get("primary", "") == "rifle_carbine", "owned gear equips through the server")
	cara.pick_mastery("rifle", "cut_down")
	await _wait_until(func() -> bool: return errors.size() == 2, 120)
	check(errors.size() == 2 and cara.account.mastery.get("picks", {}).is_empty(), "a locked mastery variant is refused")

	cara.deploy()
	await _wait_until(func() -> bool: return cara.raid != null and cara.raid.player != null, 240)
	check(cara.raid != null and cara.raid.player != null, "deploying from the lobby enters the raid")
	if cara.raid != null and cara.raid.player != null:
		var state := cara.raid.state_for(cara.raid.player)
		check(state != null and "rifle_carbine" in state.kit and state.kit.count("medkit") == 2,
				"the kit is the one the server took from the stash")
		await _wait_until(func() -> bool: return cara.account.deployed, 120)
		check(cara.account.deployed and "rifle_carbine" not in cara.account.stash and "medkit" not in cara.account.stash,
				"deployed gear has left the server stash")
	# Dropping the connection mid-raid counts as a death: the gear is gone.
	await _leave(cara)
	await frames(30)
	cara = await _sign_in("Cara", port)
	check(cara != null, "the same name and secret sign back in")
	if cara != null:
		check(not cara.account.deployed and "rifle_carbine" not in cara.account.stash
				and cara.account.loadout.get("primary", "") == "" and cara.account.raids_played == 1,
				"the server settled the run: the carbine is lost and the slot is empty")
		check("bike_scrapper" in cara.account.stash, "gear that stayed in the stash is safe")
	await _leave(cara)
	OS.kill(pid)
	await frames(30)

	# A new server process reads the same accounts from disk.
	pid = _start_server(port + 1, ["--bots", "0"])
	cara = await _sign_in("Cara", port + 1)
	check(cara != null and cara.account.raids_played == 1 and "rifle_carbine" not in cara.account.stash,
			"the stash survives a server restart")
	await _leave(cara)
	OS.kill(pid)
	check(Profile.stash == local_stash, "online play never touches the local stash")

	print("Online: the hub as a lobby")
	var hub := Hub.new()
	add_child(hub)
	await frames(1)
	var service := StashService.new()
	service.persist = false
	var id: String = service.sign_in("Lobby Tester", StashService.new_secret()).account_id
	var asked: Array = []
	hub.online_equip_requested.connect(func(slot: String, item_id: String) -> void: asked.append([slot, item_id]))
	hub.enter_lobby(service.snapshot(id), Worlds.get_world("ashfront"))
	check(hub.in_lobby() and hub.options_for("primary") == (["rifle_carbine"] as Array[String])
			and hub.equipped("primary") == "", "in a lobby the hub lists the server's stash")
	var loadout_before := Profile.loadout.duplicate()
	hub._on_picked(1, "primary")
	check(asked == [["primary", "rifle_carbine"]] and Profile.loadout == loadout_before,
			"picking gear in a lobby asks the server and leaves the local profile alone")
	service.equip(id, "primary", "rifle_carbine")
	hub.update_account(service.snapshot(id))
	check(hub.equipped("primary") == "rifle_carbine" and "rifle" in hub._mastery.loadout_tracks(),
			"the hub shows the loadout the server confirmed")
	hub.leave_lobby()
	check(not hub.in_lobby() and hub.equipped("primary") == Profile.equipped("primary"), "leaving the lobby shows the solo stash again")
	hub.queue_free()


# --- Server-owned stash --------------------------------------------------------

const StashService := preload("res://core/account/stash_service.gd")


func _test_plaza() -> void:
	print("Plaza safe zone")
	var plaza := Worlds.social_world()
	check(plaza != null and plaza.safe_zone, "the registry finds a safe-zone world")
	if plaza == null:
		return
	check(not Worlds.raid_worlds().has(plaza) and Worlds.raid_worlds().size() == Worlds.all().size() - 1,
			"safe zones are not listed as worlds to deploy into")
	var raid := Raid.new()
	add_child(raid)
	raid.mode = Raid.Mode.SERVER
	raid.start_server(plaza, 5)
	var kit: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "field_dressing"]
	var a := raid.add_player(kit, {}, "Ada")
	var b := raid.add_player(kit, {}, "Bo")
	await frames(20)
	check(raid.bots.is_empty(), "no bots in the plaza")
	check(raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer).is_empty(), "no loot in the plaza")
	check(a.is_on_floor() and b.is_on_floor(), "players stand on the plaza floor")
	check(a.gear_items.size() >= 3 and a.weapons.size() == 2, "players wear their loadout (%d pieces)" % a.gear_items.size())
	check(a.weapons_locked and b.weapons_locked, "weapons are locked in a safe zone")

	# Shooting and swinging do nothing.
	b.global_position = a.global_position + Basis(Vector3.UP, a.cmd.yaw) * Vector3(0, 0, -4)
	await frames(2)
	var gun := a.weapons[0] as Gun
	var ammo: int = gun.ammo_in_mag
	a.cmd.primary = true
	a.cmd.primary_pressed = true
	await frames(30)
	a.cmd.primary = false
	a.cmd.primary_pressed = false
	check(gun.ammo_in_mag == ammo, "a held trigger fires nothing")
	check(b.health.health == b.health.max_health, "nobody is hurt")
	a.cmd.switch_weapon = 1
	await frames(2)
	a.cmd.switch_weapon = -1
	check(a.active_weapon_index == 1, "weapons can still be drawn to show them")
	var hit := Combat.deal(b, DamageInfo.make(50.0, a, "bullet", b.global_position))
	check(not hit and b.health.health == b.health.max_health, "Combat refuses every hit in a safe zone")
	var time_before := raid.time_left
	await frames(30)
	check(raid.time_left == time_before and not raid.is_over, "there is no storm timer")

	# A fall off the map puts you back, unharmed.
	b.global_position = Vector3(0, -40, 0)
	await frames(3)
	check(not b.is_dead and b.global_position.y > -1.0, "falling out puts you back at the arrival pad")

	# Portals: one per raid world, plus home and the clan hall.
	var portals := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("portal"))
	var destinations := portals.map(func(n: Node) -> String: return n.get_meta("destination", ""))
	var all_worlds := Worlds.raid_worlds().all(func(w: WorldDef) -> bool: return ("world:" + w.id) in destinations)
	check(all_worlds, "there is a deploy gate for every raid world")
	check("home" in destinations, "there is a door to the home base")
	check("clans" in destinations, "there is a clan hall")
	check(portals.all(func(n: Node) -> bool: return n.get_meta("label", "") != ""), "every portal says where it goes")
	# Shops are physical places: a storefront for each one the game has.
	var shops: Array = raid.map.shops()
	var fronts := portals.filter(func(n: Node) -> bool: return n.is_in_group("shop_front"))
	check(fronts.size() == shops.size() and shops.all(func(entry: Dictionary) -> bool:
		return ("shop:" + str(entry.id)) in destinations), "every shop has a storefront (%d)" % fronts.size())
	var apart := true
	for one: Node3D in portals:
		for other: Node3D in portals:
			if one != other and one.global_position.distance_to(other.global_position) < 5.5:
				apart = false
	check(apart, "no two doorways overlap")
	var reachable := portals.all(func(n: Node) -> bool:
		return (n as Node3D).global_position.length() < 50.0 and absf((n as Node3D).global_position.y) < 0.5)
	check(reachable, "every portal is on the plaza floor")

	# Leaving takes you and nothing else: no body, no bag.
	raid.remove_player(b)
	await frames(3)
	check(not is_instance_valid(b) or b.is_queued_for_deletion(), "a player who leaves is simply gone")
	check(raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer).is_empty(), "leaving drops no bag")
	check(raid.players.size() == 1, "the others stay")

	# A warzone in the same process keeps its own rules.
	var war := Raid.new()
	add_child(war)
	war.start(Worlds.get_world("ashfront"), 3)
	for bot in war.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	check(Worlds.of(a) == plaza and Worlds.of(war.player).id == "ashfront", "each actor answers to its own world")
	var foe := war.bots[0]
	check(Combat.deal(foe, DamageInfo.make(5.0, war.player, "bullet", foe.global_position)), "the warzone still deals damage")
	check(not Combat.deal(a, DamageInfo.make(5.0, war.player, "bullet", a.global_position)),
			"a warzone hit cannot reach into the plaza")
	check(not Combat.deal(foe, DamageInfo.make(5.0, a, "bullet", foe.global_position)),
			"a plaza player cannot hurt anyone in the warzone")
	await _end_raid(war)
	await _end_raid(raid)


func _test_plaza_online() -> void:
	print("Plaza online: a shared safe zone beside the warzone")
	const PlazaView := preload("res://core/social/plaza_view.gd")
	var port := 24861
	_wipe_dir(NET_ACCOUNTS)
	var pid := _start_server(port, ["--plaza", "--bots", "0"])
	var ada := await _join("Pia", port, {"primary": "rifle_carbine"})
	check(ada != null, "a client walks into the server's plaza")
	if ada == null:
		OS.kill(pid)
		return
	check(ada.world_id == "plaza" and ada.raid.world.safe_zone, "the server's front door is the plaza")
	check(ada.routes.get("ashfront", -1) == port + 1, "the plaza says where the warzone runs")
	var me := ada.raid.player
	check("rifle_carbine" in me.gear_items and me.weapons_locked, "you wear your loadout, with weapons locked")
	await frames(30)
	check(not ada.account.deployed and "rifle_carbine" in ada.account.stash,
			"wearing gear in the plaza takes nothing out of the stash")

	var bo := await _join("Pax", port, {"primary": "smg_stinger"} if "smg_stinger" in ada.account.stash else {})
	check(bo != null, "a second player joins the plaza")
	if bo != null:
		await _wait_until(func() -> bool: return RaidRoster.players_in(ada.raid).size() == 2, 240)
		var seen: Array[Actor] = RaidRoster.players_in(ada.raid).filter(func(a: Actor) -> bool: return a != me)
		check(seen.size() == 1 and seen[0].display_name == "Pax", "players see each other by name")
		if seen.size() == 1:
			var bo_seen := seen[0]
			var card := PlazaView.gear_lines(bo_seen)
			var bo_gear: Array = bo.raid.player.gear_items
			check(not card.is_empty() and card.all(func(line: Dictionary) -> bool: return line.id in bo_gear),
					"you can read what another player is wearing (%d pieces)" % card.size())
			# Bo walks; Ada sees it.
			var from := bo_seen.global_position
			bo.raid.player.cmd.move = Vector2(0, 1)
			await frames(60)
			bo.raid.player.cmd.move = Vector2.ZERO
			check(bo_seen.global_position.distance_to(from) > 2.0, "movement is shared (%.1f m)" % bo_seen.global_position.distance_to(from))
			# Ada aims at Bo and holds the trigger. Nothing happens.
			var aim := (bo_seen.global_position + Vector3(0, 1.1, 0) - me.get_eye_position()).normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			me.cmd.aim_dir = aim
			me.cmd.primary = true
			me.cmd.primary_pressed = true
			await frames(60)
			me.cmd.primary = false
			var bo_me := bo.raid.player
			check(bo_me.health.health == bo_me.health.max_health and not bo_me.is_dead, "nobody can be shot in the plaza")
			var looking := PlazaView.inspect_target(ada.raid, me, me.get_eye_position(), aim, 60.0, 9.0)
			check(looking == bo_seen, "looking at a player picks them for the gear card")

	# Through the gate: the same account, now in the warzone's lobby.
	var war_port: int = ada.routes.get("ashfront", -1)
	await _leave(ada)
	if bo != null:
		await _wait_until(func() -> bool: return RaidRoster.players_in(bo.raid).size() == 1, 240)
		check(RaidRoster.players_in(bo.raid).size() == 1, "a player who leaves is gone from the plaza")
		check(bo.containers().is_empty(), "and leaves no bag behind")
	var ada_war := await _sign_in("Pia", war_port)
	check(ada_war != null and ada_war.world_id == "ashfront", "the gate leads to the warzone on the next port")
	if ada_war != null:
		check(ada_war.account.loadout.get("primary", "") == "rifle_carbine" and "rifle_carbine" in ada_war.account.stash,
				"the account is the same one: loadout and stash carry over")
		ada_war.deploy()
		await _wait_until(func() -> bool: return ada_war.raid != null and ada_war.raid.player != null, 240)
		await _wait_until(func() -> bool: return ada_war.account.deployed, 120)
		check(ada_war.raid != null and not ada_war.raid.world.safe_zone and ada_war.account.deployed
				and not ada_war.raid.player.weapons_locked, "deploying there is a real raid with gear at stake")
		await _leave(ada_war)
	await _leave(bo)

	# The whole trip through the game's own flow.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(2)
	Profile.player_name = "Quill"
	main.join_online("127.0.0.1:%d" % port)
	await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
	check(main.raid != null and main.raid.world.safe_zone and main.plaza_view != null and not main.hub.visible,
			"joining a server puts you in its plaza")
	if main.raid != null:
		var gate: Node3D = null
		for node in get_tree().get_nodes_in_group("portal"):
			if main.raid.map.is_ancestor_of(node) and node.get_meta("destination", "") == "world:ashfront":
				gate = node
		check(gate != null and PlazaView.portal_at(main.raid, gate.global_position) == gate
				and PlazaView.portal_at(main.raid, Vector3(0, 0, 20)) == null, "standing in a gate offers the trip")
		check(gate != null and PlazaView.prompt_for(gate, main.net.routes).begins_with("[E]")
				and PlazaView.prompt_for(gate, {}).contains("closed"), "a gate to a world the server lacks is closed")
		main.use_portal("clans")
		check(main.raid != null, "the clan hall is not open yet")
		main.use_portal("world:ashfront")
		await _wait_until(func() -> bool:
			return main.net != null and main.net.world_id == "ashfront" and not main.net.account.is_empty(), 600)
		check(main.hub.in_lobby() and main.raid == null and main.hub.visible and main.net != null
				and main.net.world_id == "ashfront", "using a gate takes you to that world's lobby")
		main.leave_server()
		await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
		check(main.raid != null and main.raid.world.safe_zone, "leaving the lobby leads back to the plaza")
		var shops: Array = main.raid.map.shops()
		if not shops.is_empty():
			var shop_id: String = shops[0].id
			main.use_portal("shop:" + shop_id)
			await frames(3)
			check(main.shop_view != null and main.shop_view.panel.shop_filter == shop_id
					and main.controller.input_blocked and main.raid != null,
					"a storefront opens that shop's screen without leaving the plaza")
			var panel: Control = main.shop_view.panel
			var before: int = panel.credits()
			var stock: Array = panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
				return (b as Button).text.begins_with("Buy") and not (b as Button).disabled)
			check(not stock.is_empty() and before > 0, "the stall shows stock and your credits on this server (%d)" % before)
			if not stock.is_empty():
				(stock[0] as Button).pressed.emit()
				await _wait_until(func() -> bool:
					return main.shop_view != null and main.shop_view.panel.credits() < before, 240)
				check(main.shop_view.panel.credits() < before, "buying at the stall goes through the server")
			main.close_shop()
			await frames(2)
			check(main.shop_view == null and not main.controller.input_blocked, "stepping away gives control back")
		main.use_portal("home")
		await _wait_until(func() -> bool: return main.base != null, 600)
		check(main.base != null and main.raid == null and main.hub.in_lobby(),
				"the quarters door opens your home base on the server's stash")
		main.leave_base()
		await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
		check(main.base == null and main.raid != null and main.raid.world.safe_zone,
				"the base's door leads back to the plaza")
		main.use_portal("leave")
		await frames(5)
		check(main.net == null and main.raid == null and main.hub.visible and not main.hub.in_lobby(),
				"the exit leaves the server")
	main.queue_free()
	OS.kill(pid)
	await frames(30)


func _test_stash_service() -> void:
	print("Server stash service")
	var world := Worlds.get_world("ashfront")
	var profile_stash := Profile.stash.duplicate()
	var dir := "user://test_accounts_%d" % Time.get_ticks_usec()
	var service := StashService.new()
	service.save_dir = dir
	var secret := StashService.new_secret()
	check(secret.length() >= StashService.MIN_SECRET and secret != StashService.new_secret(), "secrets are long and random")

	check(not service.sign_in("x", secret).ok, "a too-short name is refused")
	check(not service.sign_in("Vex", "short").ok, "a weak secret is refused")
	var first := service.sign_in("Vex Runner", secret)
	check(first.ok and first.created and first.account_id == "vex_runner", "the first sign-in creates the account")
	var again := service.sign_in("vex runner", secret)
	check(again.ok and not again.created and again.account_id == "vex_runner", "the same name and secret sign back in")
	check(not service.sign_in("Vex Runner", StashService.new_secret()).ok, "someone else's secret cannot take the name")
	var id: String = first.account_id

	var snap := service.snapshot(id)
	check(snap.ok and "rifle_carbine" in snap.stash and "bike_scrapper" in snap.stash, "a new account gets the welcome and gear crates")
	check(not snap.has("secret_hash") and not snap.has("salt"), "a snapshot carries no secrets")
	var crate_size: int = snap.stash.size()
	service.sign_in("Vex Runner", secret)
	check(service.snapshot(id).stash.size() == crate_size, "crates are granted only once")

	check(not service.equip(id, "primary", "dmr_longshot").ok, "the server refuses gear the account does not own")
	check(not service.equip(id, "melee", "rifle_carbine").ok, "the server refuses gear in the wrong slot")
	check(service.equip(id, "primary", "rifle_carbine").ok and service.equip(id, "frame", "frame_trooper").ok,
			"owned gear equips")
	check(not service.pick_mastery(id, "rifle", "cut_down").ok, "a locked mastery variant cannot be picked")

	var deploy := service.deploy(id, world)
	check(deploy.ok and "rifle_carbine" in deploy.kit and "frame_trooper" in deploy.kit, "deploying hands back the kit")
	check(deploy.kit.count("medkit") == 2, "deploying takes the healing items")
	var after_deploy: Array = service.snapshot(id).stash
	check("rifle_carbine" not in after_deploy and "medkit" not in after_deploy, "deployed gear leaves the server stash")
	check(not service.deploy(id, world).ok, "an account cannot deploy twice at once")
	check(not service.equip(id, "primary", "rifle_carbine").ok, "the loadout is locked during a raid")

	# A server crash mid-raid: a fresh service loads the save and returns the gear.
	var restarted := StashService.new()
	restarted.save_dir = dir
	var reloaded := restarted.snapshot(id)
	check(reloaded.ok and not reloaded.deployed and "rifle_carbine" in reloaded.stash and reloaded.stash.count("medkit") == 2,
			"an unsettled deploy is returned after a restart")
	check(reloaded.loadout.get("primary", "") == "rifle_carbine", "the loadout survives a restart")
	check(restarted.sign_in("Vex Runner", secret).ok and not restarted.sign_in("Vex Runner", StashService.new_secret()).ok,
			"sign-in still checks the secret after a restart")

	# Extract from a real raid and settle its result.
	deploy = restarted.deploy(id, world)
	var raid := Raid.new()
	raid.apply_to_profile = false
	add_child(raid)
	raid.start(world, 61, deploy.kit, deploy.picks)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	var results: Array[Dictionary] = []
	raid.ended.connect(func(r: Dictionary) -> void: results.append(r))
	raid.player.inventory.add_item("scrap_metal")
	var exit_pos := raid.exits[0].global_position
	raid.player.global_position = Vector3(exit_pos.x, 0.2, exit_pos.z)
	await frames(300)
	check(results.size() == 1 and results[0].outcome == "extracted", "the server-stash raid extracts")
	if results.size() == 1:
		check(restarted.settle(id, results[0]).ok, "the result settles")
	var home := restarted.snapshot(id)
	check("rifle_carbine" in home.stash and "scrap_metal" in home.stash and home.raids_extracted == 1,
			"extracting brings gear and loot into the server stash")
	check(not home.deployed and not restarted.settle(id, results[0] if results.size() == 1 else {}).ok,
			"a result cannot be settled twice")
	check(Profile.stash == profile_stash, "the server stash never touches the local profile")
	await _end_raid(raid)

	# Dying loses the deployed gear.
	deploy = restarted.deploy(id, world)
	restarted.settle(id, {"outcome": "died", "brought_home": [], "kills": 2, "mastery_xp": {"rifle": 999999}})
	home = restarted.snapshot(id)
	check("rifle_carbine" not in home.stash and home.loadout.get("primary", "") == "", "dying loses the gear and empties the slot")
	check(home.kills == 2 and restarted.pick_mastery(id, "rifle", "cut_down").ok, "mastery XP is kept after death")

	# A join that never happened gives everything back.
	var before: Array = restarted.snapshot(id).stash
	restarted.deploy(id, world)
	check(restarted.cancel_deploy(id).ok and restarted.snapshot(id).stash.size() == before.size(),
			"cancelling a deploy returns the gear")
	check(restarted.snapshot("nobody").ok == false and not restarted.deploy("nobody", world).ok,
			"unknown accounts are refused")

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# --- The phone ---------------------------------------------------------------

const SocialService := preload("res://core/social/social_service.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const PhoneScript := preload("res://core/phone/phone.gd")


func _test_phone() -> void:
	_test_social_service()
	_test_game_settings()
	await _test_phone_view()
	await _test_online_phone()


func _test_social_service() -> void:
	print("Phone: the server's social service")
	var social := SocialService.new()
	social.persist = false
	social.player_online("ana", "Ana")
	social.player_online("ben", "Ben")
	var snap := social.snapshot("ana", 1000.0)
	check(snap.contacts.size() == 1 and snap.contacts[0].id == "ben" and snap.contacts[0].online
			and snap.contacts[0].where == "lobby" and not snap.contacts[0].saved,
			"everyone signed in to the server shows up as a contact, without you")
	social.set_where("ben", "raid")
	check(social.snapshot("ana", 1000.0).contacts[0].where == "raid", "contacts show where a player is")

	var sent := social.send_message("ana", "ben", "  meet at the\nnorth exit  ", 1000.0)
	check(sent.ok and sent.message.text == "meet at the north exit",
			"a message is delivered with control characters stripped")
	check(social.snapshot("ben", 1000.0).messages.size() == 1 and social.snapshot("ana", 1000.0).messages.size() == 1,
			"both sides keep the message")
	check(not social.send_message("ana", "ben", "   ", 1000.0).ok, "an empty message is refused")
	check(not social.send_message("ana", "ana", "hi", 1000.0).ok, "you cannot message yourself")
	check(not social.send_message("ana", "zed", "hi", 1000.0).ok, "you cannot message someone who is not here")
	check(social.send_message("ana", "ben", "x".repeat(1000), 1001.0).message.text.length() == SocialService.MAX_MESSAGE,
			"a long message is cut to the limit")
	var accepted := 0
	for i in 10:
		if social.send_message("ana", "ben", "spam %d" % i, 1002.0).ok:
			accepted += 1
	check(accepted == SocialService.RATE_LIMIT - 2, "messages are rate limited")
	check(social.send_message("ana", "ben", "later", 1002.0 + SocialService.RATE_WINDOW + 1.0).ok,
			"the limit wears off")

	# Saved contacts can be messaged while they are offline.
	check(social.add_contact("ana", "ben").ok and social.snapshot("ana", 1100.0).contacts[0].saved, "a player can be saved as a contact")
	check(not social.add_contact("ana", "nobody").ok, "only people you have met can be saved")
	social.player_offline("ben")
	var offline_snap := social.snapshot("ana", 1100.0)
	check(offline_snap.contacts.size() == 1 and not offline_snap.contacts[0].online and offline_snap.contacts[0].name == "Ben",
			"a saved contact stays listed, by name, when they leave")
	check(social.send_message("ana", "ben", "see you tomorrow", 1100.0).ok, "a saved contact can be messaged while offline")
	social.player_online("ben", "Ben")
	var log: Array = social.snapshot("ben", 1100.0).messages
	check(log[log.size() - 1].text == "see you tomorrow", "the message is waiting when they come back")

	# Invites.
	check(not social.invite("ana", "ben", "party", "ashfront", 1200.0).ok, "only raids and bases can be invited to")
	check(not social.invite("ana", "zed", "world", "ashfront", 1200.0).ok, "only players online can be invited")
	var made := social.invite("ana", "ben", "world", "ashfront", 1200.0)
	check(made.ok and social.invites_for("ben", 1200.0).size() == 1 and social.invites_for("ana", 1200.0).is_empty(),
			"an invite reaches only the player invited")
	social.invite("ana", "ben", "world", "ashfront", 1201.0)
	check(social.invites_for("ben", 1201.0).size() == 1, "a repeat invite replaces the old one")
	social.invite("ana", "ben", "base", "", 1201.0)
	var open: Array[Dictionary] = social.invites_for("ben", 1201.0)
	check(open.size() == 2, "raid and base invites are separate")
	var world_invite: Dictionary = open[0] if open[0].kind == "world" else open[1]
	check(not social.answer_invite("ana", world_invite.id, true, 1202.0).ok, "only the invited player can answer")
	var answer := social.answer_invite("ben", world_invite.id, true, 1202.0)
	check(answer.ok and answer.accepted and answer.invite.world_id == "ashfront", "an accepted invite says where to go")
	check(not social.answer_invite("ben", world_invite.id, true, 1202.0).ok, "an invite is answered once")
	check(social.invites_for("ben", 1201.0 + SocialService.INVITE_SECONDS + 1.0).is_empty(), "invites expire")

	# Blocking.
	social.invite("ana", "ben", "world", "ashfront", 1300.0)
	social.block("ben", "ana")
	check(social.invites_for("ben", 1300.0).is_empty(), "blocking drops their open invites")
	check(not social.send_message("ana", "ben", "hello?", 1300.0).ok and not social.invite("ana", "ben", "base", "", 1300.0).ok,
			"a blocked player can no longer message or invite")
	var ben_view := social.snapshot("ben", 1300.0)
	check(ben_view.contacts.size() == 1 and ben_view.contacts[0].blocked, "a blocked player is listed as blocked")
	social.unblock("ben", "ana")
	check(social.send_message("ana", "ben", "hello again", 1400.0).ok, "unblocking lets them through again")

	# Leaving drops invites; news always has the game's own.
	social.invite("ana", "ben", "world", "ashfront", 1500.0)
	social.player_offline("ana")
	check(social.invites_for("ben", 1500.0).is_empty(), "invites from a player who left are gone")
	check(social.snapshot("ben", 1500.0).news.size() == SocialService.GAME_NEWS.size(), "the phone gets the game news")
	social.server_news.append({"date": "today", "title": "Double loot weekend", "body": "Caches hold more."})
	check(social.news()[0].title == "Double loot weekend", "server news comes first")

	# Saved social data survives a restart.
	var dir := "user://test_social"
	_wipe_dir(dir)
	var saving := SocialService.new()
	saving.save_dir = dir
	saving.player_online("ana", "Ana")
	saving.player_online("ben", "Ben")
	saving.add_contact("ana", "ben")
	saving.send_message("ben", "ana", "kept", 2000.0)
	var reloaded := SocialService.new()
	reloaded.save_dir = dir
	var kept := reloaded.snapshot("ana", 2000.0)
	check(kept.contacts.size() == 1 and kept.contacts[0].name == "Ben" and kept.messages[0].text == "kept",
			"contacts and messages are saved per account")
	_wipe_dir(dir)


func _test_game_settings() -> void:
	print("Phone: settings")
	GameSettings.persist = false
	GameSettings.reset()
	GameSettings.set_value("mouse_sensitivity", 99.0)
	GameSettings.set_value("field_of_view", 10.0)
	GameSettings.set_value("master_volume", 0.5)
	GameSettings.set_value("nonsense", 1)
	check(is_equal_approx(GameSettings.mouse_sensitivity, GameSettings.SENSITIVITY_RANGE.y)
			and is_equal_approx(GameSettings.field_of_view, GameSettings.FOV_RANGE.x), "settings are clamped to sane values")
	check(not GameSettings.to_dict().has("nonsense"), "unknown settings are ignored")
	var bus := AudioServer.get_bus_index("Master")
	check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.01, "volume reaches the audio bus")
	GameSettings.reset()
	GameSettings.apply()


func _test_phone_view() -> void:
	print("Phone: the menu itself")
	var phone: CanvasLayer = PhoneScript.new()
	add_child(phone)
	await frames(1)
	var events: Array = []
	phone.opened_changed.connect(func(open: bool) -> void: events.append(open))
	phone.settings_changed.connect(func() -> void: events.append("settings"))
	check(not phone.is_open and not phone.online(), "the phone starts put away and offline")
	check(phone.unseen_news() == SocialService.GAME_NEWS.size(), "unread news is counted")
	phone.toggle()
	check(phone.is_open and events == [true], "the phone opens")
	phone.open_app("news")
	check(phone.unseen_news() == 0 and phone._body.get_child_count() == SocialService.GAME_NEWS.size(),
			"news can be read offline")
	phone.open_app("contacts")
	check(phone._body.get_child_count() == 1, "offline, contacts explain how to reach players")
	GameSettings.persist = false
	phone.open_app("settings")
	phone.change_setting("field_of_view", 95.0)
	check(is_equal_approx(GameSettings.field_of_view, 95.0) and "settings" in events, "settings change from the phone")
	phone.close()
	check(not phone.is_open and events[events.size() - 1] == false, "the phone closes")

	# In a raid, the phone stops the character and frees the mouse.
	var raid := await _new_raid(91, false)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	await frames(2)
	controller.input_blocked = true
	await frames(2)
	check(raid.player.cmd.move == Vector2.ZERO and not raid.player.cmd.primary, "with the phone out the character lets go of the controls")
	controller.input_blocked = false
	await _end_raid(raid)
	GameSettings.reset()
	phone.queue_free()
	await frames(1)


func _test_online_phone() -> void:
	print("Online: phones reach other players")
	var port := 24851
	_wipe_dir(NET_ACCOUNTS)
	var pid := _start_server(port, ["--bots", "0"])
	var ana := await _sign_in("Ana", port)
	var ben := await _sign_in("Ben", port)
	check(ana != null and ben != null, "two players sign in")
	if ana == null or ben == null:
		await _leave(ana)
		await _leave(ben)
		OS.kill(pid)
		return
	var sees := func(session: NetSession, who: String) -> bool:
		for entry: Dictionary in session.social_state.get("contacts", []):
			if entry.id == who and entry.online:
				return true
		return false
	await _wait_until(func() -> bool: return sees.call(ana, "ben") and sees.call(ben, "ana"), 240)
	check(sees.call(ana, "ben") and sees.call(ben, "ana"), "each phone lists the other player online")

	var phone: CanvasLayer = PhoneScript.new()
	add_child(phone)
	phone.set_session(ben)
	var notices: Array[String] = []
	ben.social_notice.connect(func(text: String) -> void: notices.append(text))
	ana.send_message("ben", "Want to run the docks?")
	await _wait_until(func() -> bool: return phone.unread_count() == 1, 240)
	check(phone.unread_count() == 1 and phone.conversation_with("ana")[0].text == "Want to run the docks?",
			"a message arrives on the other phone, unread")
	check(notices.any(func(t: String) -> bool: return t.contains("docks")), "it pops up as a notice")
	phone.open()
	phone.open_chat("ana")
	check(phone.unread_count() == 0, "opening the conversation marks it read")
	phone.send_message("ana", "Sure")
	await _wait_until(func() -> bool: return ana.social_state.get("messages", []).size() == 2, 240)
	check(ana.social_state.get("messages", []).size() == 2, "the reply goes back through the server")

	# A raid invite: accepting it deploys into the same server's raid.
	var accepted: Array = []
	ben.world_invite_accepted.connect(func(invite: Dictionary) -> void: accepted.append(invite))
	var ana_notices: Array[String] = []
	ana.social_notice.connect(func(text: String) -> void: ana_notices.append(text))
	ana.send_invite("ben", "world")
	await _wait_until(func() -> bool: return phone.invites().size() == 1, 240)
	check(phone.invites().size() == 1 and phone.invites()[0].kind == "world", "the invite shows on the phone")
	phone.answer_invite(int(phone.invites()[0].id), true)
	await _wait_until(func() -> bool: return not accepted.is_empty(), 240)
	check(accepted.size() == 1 and accepted[0].world_id == "ashfront", "accepting tells the game where to go")
	await _wait_until(func() -> bool: return ana_notices.any(func(t: String) -> bool: return t.contains("accepted")), 240)
	check(ana_notices.any(func(t: String) -> bool: return t.contains("accepted")), "the inviter hears it was accepted")

	# A base invite carries the owner's gear for a read-only visit.
	var visits: Array = []
	ben.base_visit_requested.connect(func(owner: String, owner_stash: Array, _loadout: Dictionary) -> void:
		visits.append([owner, owner_stash]))
	ana.send_invite("ben", "base")
	await _wait_until(func() -> bool: return phone.invites().size() == 1, 240)
	phone.answer_invite(int(phone.invites()[0].id), true)
	await _wait_until(func() -> bool: return not visits.is_empty(), 240)
	check(visits.size() == 1 and visits[0][0] == "Ana" and "rifle_carbine" in visits[0][1],
			"accepting a base invite brings the owner's stash to show")

	# Presence follows the player into the raid.
	ana.deploy()
	await _wait_until(func() -> bool:
		return ben.social_state.get("contacts", []).any(func(c: Dictionary) -> bool: return c.id == "ana" and c.where == "raid"), 240)
	check(ben.social_state.get("contacts", []).any(func(c: Dictionary) -> bool: return c.id == "ana" and c.where == "raid"),
			"contacts show who is in the raid")

	# Blocking is enforced by the server.
	var errors: Array[String] = []
	ana.social_error.connect(func(reason: String) -> void: errors.append(reason))
	phone.change_contact("block", "ana")
	await _wait_until(func() -> bool: return phone.contact("ana").get("blocked", false), 240)
	ana.send_message("ben", "hello?")
	await _wait_until(func() -> bool: return not errors.is_empty(), 240)
	check(not errors.is_empty() and phone.conversation_with("ana").size() == 2, "a blocked player's messages are refused")

	await _leave(ana)
	await _wait_until(func() -> bool: return not sees.call(ben, "ana"), 240)
	check(not sees.call(ben, "ana"), "a player who leaves goes offline on the other phones")
	phone.queue_free()
	await _leave(ben)
	OS.kill(pid)
	await frames(30)
	_wipe_dir(NET_ACCOUNTS)


## Stands the actor in front of a home base display, looking at it.
func _face_display(actor: Actor, display: Node3D) -> void:
	var out: Vector3 = display.global_transform.basis.z
	actor.global_position = Vector3(display.global_position.x, 0.1, display.global_position.z) + out * 2.0
	actor.velocity = Vector3.ZERO
	var eye := actor.global_position + Vector3(0, actor.eye_height, 0)
	# Aim at the middle of the display's hit box.
	var col: CollisionShape3D = null
	for child in display.get_children():
		if child is CollisionShape3D:
			col = child
	var dir := (col.global_position - eye).normalized()
	actor.cmd.yaw = atan2(-dir.x, -dir.z)
	actor.cmd.pitch = asin(dir.y)
	actor.cmd.aim_dir = dir


func _use(actor: Actor) -> void:
	actor.cmd.interact_pressed = true
	await frames(1)
	actor.cmd.interact_pressed = false
	await frames(1)


func _test_home_base() -> void:
	print("Home base layout")
	check(BaseLayout.kind_for("dmr_longshot") == "gun_rack" and BaseLayout.kind_for("hammer_breaker") == "blade_wall"
			and BaseLayout.kind_for("frame_bulwark") == "armor_stand" and BaseLayout.kind_for("wings_glide") == "rig_stand"
			and BaseLayout.kind_for("chip_blink") == "chip_case" and BaseLayout.kind_for("bike_raider") == "bay"
			and BaseLayout.kind_for("medkit") == "supplies" and BaseLayout.kind_for("lattice_shard") == "trophy",
			"tags decide where an item is shown")
	check(BaseLayout.slot_for("rifle_carbine") == "primary" and BaseLayout.slot_for("bike_scrapper") == "vehicle"
			and BaseLayout.slot_for("scrap_metal") == "", "gear knows its loadout slot, loot has none")
	var stash: Array[String] = ["rifle_carbine", "dmr_longshot", "rifle_carbine", "blade_arc", "frame_trooper",
			"bike_scrapper", "bike_scrapper", "bike_raider", "medkit", "medkit", "medkit", "scrap_metal",
			"lattice_shard", "chip_blink", "jetpack_mk2", "no_such_item"]
	var plan := BaseLayout.plan(stash, {"primary": "rifle_carbine", "vehicle": "bike_scrapper"})
	var by_kind := {}
	for entry in plan:
		if not by_kind.has(entry["kind"]):
			by_kind[entry["kind"]] = []
		by_kind[entry["kind"]].append(entry)
	var guns: Array = by_kind.get("gun_rack", [])
	check(guns.size() == 2 and guns[0]["id"] == "dmr_longshot" and guns[0]["index"] == 0
			and guns[1]["id"] == "rifle_carbine", "the most valuable gun gets the first spot")
	check(guns[1]["count"] == 2 and guns[1]["equipped"] and not guns[0]["equipped"],
			"copies share a spot with a count, and the equipped gun is marked")
	var bays: Array = by_kind.get("bay", [])
	check(bays.size() == 3 and bays[0]["id"] == "bike_raider", "every bike you own is parked")
	check(bays.filter(func(e: Dictionary) -> bool: return e["equipped"]).size() == 1,
			"only one of two identical bikes is marked as equipped")
	check(by_kind.get("trophy", []).size() == 2 and by_kind["trophy"][0]["id"] == "lattice_shard"
			and by_kind.get("supplies", []).size() == 1 and by_kind["supplies"][0]["count"] == 3,
			"loot goes on the trophy shelf and medkits with the supplies")
	check(plan.filter(func(e: Dictionary) -> bool: return e["id"] == "no_such_item").is_empty(),
			"unknown items are never shown")
	check(BaseLayout.plan([], {}).is_empty() and BaseLayout.stored_away(stash).is_empty(),
			"an empty stash is an empty base, and nothing is stored away while it fits")
	var many: Array[String] = []
	for i in 6:
		many.append("bike_scrapper")
	check(BaseLayout.plan(many, {}).size() == 4 and BaseLayout.stored_away(many) == {"bay": 2},
			"a full garage keeps the rest in storage")

	print("Home base room")
	var base := HomeBase.new()
	base.show_gear(stash, {"primary": "rifle_carbine"})
	add_child(base)
	await frames(30)
	check(base.displays.size() == plan.size(), "the room builds one display per planned spot")
	check(base.player != null and base.player.is_on_floor() and base.player.weapons.is_empty(),
			"you stand in the base unarmed")
	var start := base.player.global_position
	base.player.cmd.move = Vector2(0, 1)
	await frames(30)
	base.player.cmd.move = Vector2.ZERO
	check(base.player.global_position.distance_to(start) > 1.5, "you can walk around it")
	var spots := {}
	var apart := true
	for display in base.displays:
		var key := "%s/%d" % [display.kind, display.index]
		apart = apart and not spots.has(key) and absf(display.global_position.x) < base.room_size.x * 0.5 \
				and absf(display.global_position.z) < base.room_size.z * 0.5
		spots[key] = true
	check(apart, "every display has its own spot inside the room")
	var asked := []
	base.equip_requested.connect(func(slot: String, id: String) -> void: asked.append([slot, id]))
	var dmr := base.display_for("dmr_longshot")
	_face_display(base.player, dmr)
	await frames(2)
	check(base.player.find_interactable() == dmr and dmr.get_prompt() == "[E] Equip Longshot DMR",
			"looking at a gun on the rack offers to equip it")
	await _use(base.player)
	check(asked == [["primary", "dmr_longshot"]], "using it asks for that gun in the primary slot")
	var carbine := base.display_for("rifle_carbine")
	check(carbine.equipped and carbine.has_node("EquippedMark") and not dmr.has_node("EquippedMark"),
			"equipped gear is marked on its display")
	_face_display(base.player, carbine)
	await frames(2)
	await _use(base.player)
	check(asked.size() == 2 and asked[1] == ["primary", ""], "using equipped gear asks to take it off")
	var shard := base.display_for("lattice_shard")
	_face_display(base.player, shard)
	await frames(2)
	await _use(base.player)
	check(base.player.find_interactable() == shard and shard.get_prompt() == "Lattice Shard" and asked.size() == 2,
			"loot is only for looking at")
	var hud = BaseHudScript.new()
	hud.setup(base)
	base.add_child(hud)
	await frames(2)
	var lines: Array[String] = hud.describe(shard)
	check(lines[0] == "Lattice Shard" and "Relic" in lines[1], "the overlay names what you look at and its rarity")
	for kind: String in BaseLayout.KINDS:
		var bike_or_gear: Array = by_kind.get(kind, [])
		if bike_or_gear.is_empty():
			continue
		var shown := base.display_for(bike_or_gear[0]["id"])
		_face_display(base.player, shown)
		await frames(2)
		check(base.player.find_interactable() == shown, "a %s display can be walked up to and looked at" % kind)
	base.show_gear(["blade_arc"], {})
	await frames(2)
	check(base.displays.size() == 1 and base.display_for("dmr_longshot") == null,
			"gear that leaves the stash leaves the base")
	var left := [0]
	base.leave_requested.connect(func() -> void: left[0] += 1)
	_face_display(base.player, base.door)
	await frames(2)
	await _use(base.player)
	check(left[0] == 1, "the door asks to go back to the hub")
	base.read_only = true
	base.show_gear(["dmr_longshot"], {"primary": "dmr_longshot"})
	await frames(2)
	_face_display(base.player, base.displays[0])
	await frames(2)
	await _use(base.player)
	check(asked.size() == 2 and base.displays[0].get_prompt() == "Longshot DMR (equipped)",
			"a base you are visiting cannot be changed")
	base.queue_free()
	await frames(2)

	print("Home base from the hub")
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "dmr_longshot", "frame_bulwark", "bike_scrapper", "alloy_ingot"])
	Profile.equip("primary", "rifle_carbine")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(2)
	main.hub.base_requested.emit()
	await frames(20)
	check(main.base != null and not main.hub.visible and main.raid == null, "the hub opens your home base")
	check(main.controller != null and main.controller.camera.current and main.base_hud != null,
			"the base has a camera and an overlay")
	check(main.base.displays.size() == 5 and main.base.display_for("rifle_carbine").equipped,
			"it shows your stash and what you have equipped")
	main.start_raid("ashfront")
	check(main.raid == null, "you cannot deploy from inside the base")
	# Real input: look at the DMR and press E.
	var target: Node3D = main.base.display_for("dmr_longshot")
	_face_display(main.base.player, target)
	main.controller.yaw = main.base.player.cmd.yaw
	main.controller.pitch = main.base.player.cmd.pitch
	await frames(3)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(2)
	check(Profile.equipped("primary") == "dmr_longshot", "pressing E on a rack changes your loadout")
	check(main.base.display_for("dmr_longshot").equipped and not main.base.display_for("rifle_carbine").equipped,
			"the displays show the change")
	main.base.equip_requested.emit("vehicle", "bike_scrapper")
	main.base.equip_requested.emit("primary", "frame_bulwark")
	check(Profile.equipped("vehicle") == "bike_scrapper" and Profile.equipped("primary") == "dmr_longshot",
			"a parked bike can be picked, and gear cannot go in the wrong slot")
	main.base.leave_requested.emit()
	await frames(3)
	check(main.base == null and main.hub.visible and main.controller == null, "the door leads back to the hub")
	check(main.hub.equipped("primary") == "dmr_longshot", "the hub shows the loadout chosen in the base")
	# A server's stash is shown while in its lobby, and the local one is left alone.
	main.hub.update_account({"name": "Vex", "stash": ["blade_arc", "bike_raider"], "loadout": {"melee": "blade_arc"},
			"mastery": {}, "raids_played": 0, "raids_extracted": 0, "kills": 0})
	main.enter_base()
	await frames(5)
	check(main.base.displays.size() == 2 and main.base.display_for("blade_arc").equipped,
			"in a lobby the base shows the stash that server keeps")
	main.base.equip_requested.emit("vehicle", "bike_raider")
	check(Profile.equipped("vehicle") == "bike_scrapper", "online changes go to the server, not the local profile")
	main._on_online_account_changed({"name": "Vex", "stash": ["blade_arc", "bike_raider"],
			"loadout": {"melee": "blade_arc", "vehicle": "bike_raider"}, "mastery": {},
			"raids_played": 0, "raids_extracted": 0, "kills": 0})
	await frames(2)
	check(main.base.display_for("bike_raider").equipped, "the base updates when the server answers")
	main.leave_base()
	main.hub.leave_lobby()
	await frames(3)
	main.visit_base("Kestrel", ["lattice_shard", "hammer_breaker"], {"melee": "hammer_breaker"})
	await frames(5)
	check(main.base != null and main.base.read_only and main.base.owner_name == "Kestrel"
			and main.base.displays.size() == 2, "someone else's base can be visited")
	main.base.displays[0].interact(main.base.player)
	main.base.displays[1].interact(main.base.player)
	check(Profile.equipped("melee") == "", "visiting never changes your own loadout")
	main.leave_base()
	await frames(3)
	main.start_raid("ashfront")
	await frames(5)
	check(main.raid != null and main.raid.player.weapons[0].item_id == "dmr_longshot",
			"gear picked in the base is what you deploy with")
	main.raid.player.kill("test")
	await frames(150)
	main.queue_free()
	await frames(2)
	Profile.reset()
