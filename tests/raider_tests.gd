extends RefCounted
## Checks for rival raiders (DESIGN.md section 2, "Rival raiders"): bots that
## play the way a player does. Their kits, how they drop in, loot, fly, sign
## out and die. Kept in its own file and called from the test runner.


static func run(t: Node) -> void:
	_kits(t)
	var raid: Raid = await t._new_raid(5151, false)
	await _drop_in(t, raid)
	await _looting(t, raid)
	await _flight(t, raid)
	await _kit_care(t, raid)
	await _sign_out(t, raid)
	await _death(t, raid)
	_client_copy(t, raid)
	await _on_its_own(t, raid)
	await t._end_raid(raid)


static func _kits(t: Node) -> void:
	print("Rival raiders: kits")
	var world := Worlds.get_world("ashfront")
	t.check(world.raider_count > 0, "Ashfront keeps rival raiders")
	t.check(Worlds.get_world("frostline").raider_count == 0 and Worlds.get_world("plaza").raider_count == 0,
			"the gentle world and the plaza have none")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var whole := true
	var real := true
	var base_level := true
	var rigs := {}
	for i in 200:
		var kit := world.raider_kit(rng)
		var has := func(tag: String) -> bool:
			return kit.any(func(id: String) -> bool: return ItemDB.has_tag(id, tag))
		whole = whole and has.call("flight_rig") and has.call("melee") and has.call("sidearm") \
				and has.call("armor") and kit.any(func(id: String) -> bool: return Loadout.is_primary(id))
		for id in kit:
			real = real and ItemDB.has_item(id)
			base_level = base_level and not ItemDB.has_tag(id, "blueprint") and not ItemDB.has_tag(id, "power") \
					and not id.ends_with("_mk2") and not id.ends_with("_mk3")
			if ItemDB.has_tag(id, "flight_rig"):
				rigs[id] = true
	t.check(whole, "every raider comes in with a primary, a sidearm, a blade, a rig and a frame")
	t.check(real, "every piece of a raider's kit is a real item")
	t.check(base_level, "raiders carry base-level gear only: no Mk2 or Mk3, blueprints or heavy weapons")
	t.check(rigs.size() == 3, "raiders fly all three kinds of rig (%s)" % ", ".join(rigs.keys()))


static func _drop_in(t: Node, raid: Raid) -> void:
	print("Rival raiders: dropping in")
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var standing := raid._standing_bots()
	var bot := raid.spawn_raider()
	t.check(bot != null and raid.is_raider(bot) and raid.bots.has(bot), "a raider drops in and is listed as a bot")
	t.check(bot.faction.begins_with("raider:") and bot.faction != "raider",
			"a raider is a side of its own, apart from the players and the armies")
	t.check(raid.world.raider_names().has(bot.display_name), "a raider goes by a name (%s)" % bot.display_name)
	t.check(not bot.gear_items.is_empty() and bot.flight.enabled and bot.frame_id != "",
			"a raider wears its kit as a player would (%s)" % ", ".join(bot.gear_items))
	t.check(bot.has_meta("appearance") and not bot.has_meta("look"), "a raider looks like a person, not a soldier")
	t.check((bot.get_node("Brain") as BotBrain).flies, "a raider with a rig flies it")
	t.check(raid._is_extra(bot) and raid._standing_bots() == standing,
			"raiders are outside the armies: never ordered and never counted as soldiers")
	t.check(feed.any(func(line: String) -> bool: return line.begins_with(bot.display_name + " dropped in")),
			"everyone hears that a raider dropped in")
	var second := raid.spawn_raider()
	t.check(second != null and second.display_name != bot.display_name, "no two raiders share a name")
	t.check(raid.world.can_damage(bot, second, null) and raid.world.can_damage(bot, raid.bots[0], null),
			"raiders can hurt each other and the armies")
	raid._remove_actor(second)
	await t.frames(2)
	t.check(raid.raiders.size() == 1, "a raider taken away is no longer listed")


static func _looting(t: Node, raid: Raid) -> void:
	print("Rival raiders: looting")
	var entry: Dictionary = raid.raiders[0]
	var bot: Actor = entry.bot
	var brain := bot.get_node("Brain") as BotBrain
	raid._tick_raiders(0.05)
	var cache: Variant = entry.cache
	t.check(cache is LootContainer and not (cache as LootContainer).items.is_empty() and brain.has_errand,
			"a raider picks a cache with something in it and heads for it")
	if not cache is LootContainer:
		return
	var container := cache as LootContainer
	var held := bot.inventory.items.size()
	bot.global_position = container.global_position + Vector3(0.5, 0, 0)
	raid._tick_raiders(0.05)
	t.check(bot.inventory.items.size() > held and entry.visited.has(container) and not brain.has_errand,
			"at the cache it loots it, the way a player does")
	raid._tick_raiders(0.05)
	t.check(entry.cache != container, "and it moves on to another cache")
	await t.frames(1)


static func _flight(t: Node, raid: Raid) -> void:
	print("Rival raiders: flight")
	var bot: Actor = raid.raiders[0].bot
	var brain := bot.get_node("Brain") as BotBrain
	# Swap whatever rig it rolled for a jetpack, so the check is the same every run.
	Loadout.equip(bot, ["jetpack_mk1"])
	# Standing still, the brain out of the way, so it reads as stuck.
	brain.set_physics_process(false)
	bot.cmd.apply_array(ActorCommand.new().to_array())
	await t.frames(30)
	var cmd := ActorCommand.new()
	cmd.move = Vector2(0, 1)
	brain._unstick(cmd, 0.05)
	t.check(not cmd.jump, "a raider does not lift off the moment it slows")
	brain._unstick(cmd, brain.stuck_time + 0.1)
	brain._unstick(cmd, 0.05)
	t.check(bot.is_on_floor() and cmd.jump and cmd.secondary, "a raider stuck against something lifts off on its jets")
	var hop := ActorCommand.new()
	brain._hop_in = 0.0
	bot.flight.heat = 0.0
	brain._combat_hop(hop, 0.05)
	var up := ActorCommand.new()
	brain._combat_hop(up, 0.05)
	t.check(hop.jump_pressed and up.secondary and up.jump, "in a gunfight a jetpack raider takes off and hovers")
	brain._hop_left = 0.0
	brain.set_physics_process(true)


static func _sign_out(t: Node, raid: Raid) -> void:
	print("Rival raiders: signing out")
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var entry: Dictionary = raid.raiders[0]
	var bot: Actor = entry.bot
	var brain := bot.get_node("Brain") as BotBrain
	brain.state = BotBrain.State.PATROL
	entry.leaves_at = raid.clock
	raid._tick_raiders(0.05)
	t.check(float(entry.sign_out_left) > 0.0 and brain.holding and not brain.has_errand,
			"once its stay is up a raider stops to sign out")
	brain.state = BotBrain.State.CHASE
	raid._tick_raiders(1.0)
	t.check(is_equal_approx(float(entry.sign_out_left), raid.world.sign_out_time), "a fight starts its sign-out over")
	brain.state = BotBrain.State.PATROL
	raid._tick_raiders(raid.world.sign_out_time + 0.1)
	await t.frames(2)
	t.check(not is_instance_valid(bot) or not raid.bots.has(bot), "it leaves the world once the sign-out ends")
	t.check(raid.raiders.is_empty() and feed.any(func(line: String) -> bool: return line.contains("signed out with")),
			"and everyone hears it got out")


static func _death(t: Node, raid: Raid) -> void:
	print("Rival raiders: death")
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var bot := raid.spawn_raider()
	var gear := bot.gear_items.duplicate()
	var respawns := raid._bot_respawns.size()
	var bags_before := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag).size()
	raid._raider_in = 0.0
	bot.kill("test", raid.player)
	await t.frames(2)
	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	var dropped: Array[String] = []
	for bag: LootContainer in bags:
		dropped.append_array(bag.items)
	t.check(bags.size() == bags_before + 1 and gear.all(func(id: String) -> bool: return dropped.has(id)),
			"a dead raider drops its whole kit in a bag")
	t.check(raid.raiders.is_empty() and raid._bot_respawns.size() == respawns,
			"it is not replaced by the army")
	t.check(raid._raider_in >= raid.world.raider_gap - 1.0, "another raider drops in after the usual gap")
	t.check(feed.any(func(line: String) -> bool: return line.contains("killed " + bot.display_name)),
			"everyone hears who killed it")


## A client builds a raider from the kit the server sends, not from the seed.
static func _client_copy(t: Node, raid: Raid) -> void:
	print("Rival raiders: a client's copy")
	var kit: Array[String] = ["rifle_carbine", "pistol_machine", "axe_splitter", "boots_thruster", "frame_runner"]
	var copy := raid.spawn_bot("RaiderCopy", Vector3(0, 30, 0), 99, false, "raider:Copy", 0, kit)
	t.check(copy.gear_items.size() == kit.size() and copy.flight.enabled and copy.frame_id == "frame_runner"
			and not copy.has_meta("look"), "the same kit makes the same raider, not a soldier")
	raid._remove_actor(copy)


## Left to itself, a raider gets to a cache and loots it.
static func _on_its_own(t: Node, raid: Raid) -> void:
	print("Rival raiders: on their own")
	var bot := raid.spawn_raider()
	var entry: Dictionary = raid.raiders.filter(func(e: Dictionary) -> bool: return e.bot == bot)[0]
	# Only the walk and the looting are checked here: nobody picks a fight.
	for other in raid.bots:
		other.faction = bot.faction
	var start := bot.global_position
	for i in 60 * 60:
		await t.frames(1)
		if not is_instance_valid(bot) or bot.is_dead or not entry.visited.is_empty():
			break
	t.check(is_instance_valid(bot) and not entry.visited.is_empty(),
			"a raider walks to a cache and loots it by itself (moved %.0f m)"
			% (bot.global_position.distance_to(start) if is_instance_valid(bot) else -1.0))


## A raider looks after its kit like a player: heals, reloads, goes back to
## the primary, and falls back to the blade once every gun is dry.
static func _kit_care(t: Node, raid: Raid) -> void:
	print("Rival raiders: looking after the kit")
	var bot := raid.spawn_raider()
	var brain := bot.get_node("Brain") as BotBrain
	brain.set_physics_process(false)
	t.check(brain.uses_kit and brain.skill_range == raid.world.raider_skill,
			"a raider aims from the world's raider skill and looks after its kit")
	Loadout.equip(bot, ["smg_stinger", "pistol_machine", "knife_gutter", "medkit"])
	var primary := brain._primary_index()
	var sidearm := -1
	var blade := brain._blade_index()
	for i in bot.weapons.size():
		if bot.weapons[i] is Gun and (bot.weapons[i] as Gun).is_sidearm:
			sidearm = i
	brain.state = BotBrain.State.PATROL
	brain.target = null
	bot.health.health = bot.health.max_health * 0.5
	var cmd := ActorCommand.new()
	brain._tend_kit(cmd)
	t.check(cmd.heal_pressed, "hurt between fights, it heals from its pack")
	bot.health.health = bot.health.max_health
	bot._draw_weapon(sidearm)
	cmd = ActorCommand.new()
	brain._tend_kit(cmd)
	t.check(cmd.switch_weapon == primary, "between fights it puts its primary back in hand")
	bot._draw_weapon(primary)
	var gun := bot.weapons[primary] as Gun
	gun.ammo_in_mag = 1
	cmd = ActorCommand.new()
	brain._tend_kit(cmd)
	t.check(cmd.reload_pressed, "and tops up a part-used mag")
	brain.state = BotBrain.State.ATTACK
	for w in bot.weapons:
		if w is Gun:
			(w as Gun).ammo_in_mag = 0
			(w as Gun).reserve_ammo = 0
	cmd = ActorCommand.new()
	brain._tend_kit(cmd)
	t.check(cmd.switch_weapon == blade, "in a fight with every gun dry, it draws its blade")
	cmd = ActorCommand.new()
	bot.health.health = bot.health.max_health * 0.5
	brain._tend_kit(cmd)
	t.check(not cmd.heal_pressed, "it does not stop to heal in a fight at half health")
	brain.state = BotBrain.State.PATROL
	raid._remove_actor(bot)
	await t.frames(2)
