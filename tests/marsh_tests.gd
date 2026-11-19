extends RefCounted
## Checks for the Spore Marsh (DESIGN.md "Spore Marsh"): a co-op PvE world
## of wildlife, where guns foul, bloaters burst into spore clouds and the
## Grey Matriarch is the main source of artifacts. Kept in its own file and
## called from the test runner.

const Crafting := preload("res://core/progression/crafting.gd")
const Economy := preload("res://core/economy/economy.gd")
const Market := preload("res://core/economy/market.gd")
const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]


static func run(t: Node) -> void:
	_settings(t)
	_close_air(t)
	_loot(t)
	await _fouling(t)
	await _wildlife(t)
	await _brood_and_lurkers(t)
	await _clouds(t)


static func _settings(t: Node) -> void:
	print("Marsh: the world's settings")
	var marsh := Worlds.get_world("marsh")
	var ash := Worlds.get_world("ashfront")
	t.check(marsh != null and marsh in Worlds.raid_worlds() and marsh.planet == "marsh",
			"the Spore Marsh is a world you deploy into, on the marsh planet")
	if marsh == null:
		return
	t.check(marsh.keep_gear_on_death and marsh.players_allied and marsh.war_scale == 0.0
			and marsh.power_weapon_rate == 0.0, "co-op and gentle: no PvP, you keep what you wear, no war, no heavy weapons")
	t.check(marsh.gun_fouling > 0.0 and ash.gun_fouling == 0.0 and Worlds.get_world("frostline").gun_fouling == 0.0,
			"guns foul in the marsh and nowhere else")
	t.check(marsh.shot_carry > 1.0 and marsh.shot_carry > PlanetTypes.get_type("marsh").rules["shot_carry"],
			"gunshots carry far in the quiet marsh, so they wake it")
	t.check(marsh.warlord_artifact_chance > ash.warlord_artifact_chance
			and marsh.pod_artifact_chance > ash.pod_artifact_chance,
			"it is the main source of artifacts: its bosses and pods carry them more often than the war's")
	t.check(marsh.contract_tag == "marsh" and not marsh.contract_jobs().is_empty()
			and marsh.contract_jobs().values().all(func(job: Dictionary) -> bool: return not str(job.stat).begins_with("kills:player")),
			"it has its own contracts, and none counts player kills")
	var hurt := DamageInfo.new()
	var a := Actor.new()
	var b := Actor.new()
	a.faction = "stalker"
	b.faction = "stalker"
	t.check(not marsh.can_damage(a, b, hurt), "no beast hurts its own kind")
	b.faction = "shellback"
	t.check(marsh.can_damage(a, b, hurt), "but the kinds hunt each other")
	a.faction = "keeper"
	b.faction = "broodling"
	t.check(not marsh.can_damage(a, b, hurt) and not marsh.can_damage(b, a, hurt),
			"a brood keeper and its broodlings are one kind")
	a.free()
	b.free()


static func _close_air(t: Node) -> void:
	print("Marsh: the forests' close air")
	var marsh := Worlds.get_world("marsh")
	var map_script: GDScript = load("res://worlds/marsh/map.gd")
	var forest: Dictionary = map_script.FORESTS[2]
	var heart: Vector2 = forest["at"]
	var inside := Vector3(heart.x, 0.0, heart.y)
	var open := Vector3(heart.x, 0.0, heart.y) + Vector3(float(forest["radius"]) + 30.0, 0.0, 0.0)
	t.check(map_script.close_at(inside.x, inside.z) > 0.99 and map_script.close_at(open.x, open.z) == 0.0,
			"the air is close under a forest's caps and open out on the water")
	t.check(marsh.sight_at(inside) < 40.0 and marsh.sight_at(open) == INF
			and Worlds.get_world("ashfront").sight_at(inside) == INF,
			"under the caps sight is cut to close quarters; out on the water, and in other worlds, it is not")
	var type := PlanetTypes.get_type("marsh")
	t.check(not type.close.is_empty() and float(type.close["fog_depth_end"]) < 60.0
			and not type.smoke.get("banks", {}).is_empty(),
			"the marsh planet shuts its air in under cover and drifts its mist in banks")
	# The fog's floor comes down with the close air, as it does in a storm.
	var env := Environment.new()
	var mood := Look.mood_values(type.calm)
	var shut := Look.blend_moods(mood, Look.mood_values(type.close, mood), 1.0)
	Look.close_cover = 0.0
	Look.apply_fog(env, mood)
	var open_end := env.fog_depth_end
	Look.close_cover = 1.0
	Look.apply_fog(env, shut)
	t.check(env.fog_depth_end < 60.0 and open_end > 100.0,
			"the view shuts in under the caps (solid by %.0f m) and opens out over the water (%.0f m)" % [env.fog_depth_end, open_end])
	Look.close_cover = 0.0
	# The banks drift with the wind but come back to the same air.
	var a: Vector2 = Planet.GroundSmoke.bank_spot(3, -2, 55.0, Vector2(0.8, 0.3), 10.0)
	var b: Vector2 = Planet.GroundSmoke.bank_spot(3, -2, 55.0, Vector2(0.8, 0.3), 20.0)
	t.check(a != b and a.x >= 165.0 and a.x < 220.0 and a.y >= -110.0 and a.y < -55.0,
			"a mist bank drifts with the wind and stays in its own stretch of air")


static func _loot(t: Node) -> void:
	print("Marsh: what it pays")
	var marsh := Worlds.get_world("marsh")
	if marsh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var relics := 0
	var prints := {}
	var rare_gear := false
	for i in 400:
		for source: String in ["cache", "station", "hollow", "cap", "den"]:
			for id in marsh.roll_loot(source, rng):
				if ItemDB.has_tag(id, "artifact"):
					relics += 1
				elif ItemDB.has_tag(id, "blueprint"):
					prints[id] = true
				else:
					rare_gear = rare_gear or int(ItemDB.item_stats(id).get("tier", 1)) > 1
	t.check(relics > 0, "the forests' hollows, caps and the den hold artifacts now and then (%d)" % relics)
	t.check(prints.size() == 2 and prints.keys().all(func(id: String) -> bool: return ItemDB.has_tag(id, "expedition")),
			"its own blueprints turn up there, the marsh's own (%s)" % [prints.keys()])
	var melee := true
	for print_id: String in ["bp_blade_hook", "bp_spear_reed"]:
		for made in Crafting.made_from(print_id):
			melee = melee and ItemDB.has_tag(made, "melee") and not Crafting.needs(made).has(Crafting.UPGRADE_DATA)
	t.check(melee and Crafting.made_from("bp_blade_hook").size() == 1,
			"they make melee weapons, new options, never a higher Mk")
	t.check(not rare_gear, "no Mk2 rig or helmet drops there")
	t.check(ItemDB.has_tag("trophy_matriarch_fang", "trophy") and Economy.sell_price("trophy_matriarch_fang") == 0
			and "trophy" in Market.UNTRADEABLE_TAGS, "the Matriarch's trophy is a keepsake: never traded or sold")
	t.check(ItemDB.item_rarity("paint_spore") == ItemDB.Rarity.RELIC and ArmorPaint.PAINTS.has("spore")
			and marsh.warlord_paint == "paint_spore", "and her armor paint is earned, a Relic")


static func _gun(t: Node, raid: Raid) -> Array:
	var me := raid.add_player(KIT, {}, "Fouler", "fouler")
	await t.frames(2)
	var gun: Gun = null
	for weapon in me.weapons:
		if weapon is Gun:
			gun = weapon
	return [me, gun]


static func _fouling(t: Node) -> void:
	print("Marsh: guns foul")
	for world_id: String in ["marsh", "ashfront"]:
		var raid := Raid.new()
		t.add_child(raid)
		raid.start_server(Worlds.get_world(world_id), 4)
		for bot in raid.bots:
			bot.process_mode = Node.PROCESS_MODE_DISABLED
		var made: Array = await _gun(t, raid)
		var gun: Gun = made[1]
		if gun == null:
			t.check(false, "the player has a gun")
			raid.queue_free()
			return
		gun.reserve_ammo = 999
		var spread := gun.current_spread_deg()
		var fired := 0
		for i in 60:
			gun.ammo_in_mag = gun.mag_size
			if gun.jammed:
				break
			gun._fire()
			fired += 1
		if world_id == "marsh":
			t.check(gun.jammed and fired < 60 and fired > 10,
					"a long burst fouls the gun until it jams (%d shots)" % fired)
			t.check(gun.current_spread_deg() > spread * 1.3, "and fouling widens the spread")
			gun.tick(gun.fire_interval + 0.05)
			var before := gun.shots_fired
			var cmd := ActorCommand.new()
			cmd.primary = true
			cmd.primary_pressed = true
			gun.handle_input(cmd, 0.016)
			t.check(gun.shots_fired == before and gun.is_reloading(), "a jammed gun does not fire; a pull starts clearing it")
			gun.tick(gun.reload_time + 0.1)
			t.check(not gun.jammed and gun.fouling == 0.0, "the reload clears the jam and the fouling")
			for i in 10:
				gun._fire()
			var left := gun.fouling
			gun.tick(1.0)
			t.check(left > 0.2 and gun.fouling < left, "a gun left to rest clears on its own")
		else:
			t.check(not gun.jammed and gun.fouling == 0.0, "Ashfront's guns never foul")
		raid.queue_free()
		await t.frames(1)


static func _bot_of(raid: Raid, faction: String) -> Actor:
	for bot in raid.bots:
		if is_instance_valid(bot) and bot.faction == faction and not bot.has_meta("boss"):
			return bot
	return null


static func _wildlife(t: Node) -> void:
	print("Marsh: the wildlife")
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 12)
	for bot in raid.bots:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	var kinds := {}
	for marker in raid._map_nodes("spawn_bot"):
		kinds[marker.get_meta("faction", "")] = true
	t.check(kinds.has("stalker") and kinds.has("shellback") and kinds.has("bloater"),
			"the map has dens for stalkers, shellbacks and bloaters")
	var stalker := _bot_of(raid, "stalker")
	var shellback := _bot_of(raid, "shellback")
	var bloater := _bot_of(raid, "bloater")
	t.check(stalker != null and shellback != null and bloater != null, "all three kinds are out in the marsh")
	if stalker == null or shellback == null or bloater == null:
		raid.queue_free()
		return
	t.check(stalker.get_active_weapon() is MeleeWeapon and stalker.sprint_speed > 8.0
			and float(stalker.get_meta("feint_chance", 0.0)) > 0.3,
			"stalkers are quick hunters with claws, that feint")
	var brain := stalker.get_node_or_null("Brain") as BotBrain
	t.check(brain != null and is_equal_approx(brain.feint_chance, float(stalker.get_meta("feint_chance"))),
			"and their brains feint as often as the kind says")
	t.check(shellback.rear_damage_mult > 2.0 and shellback.health.armor > 50.0 and shellback.sprint_speed < 5.0,
			"shellbacks are slow and armored, with a soft rear")
	t.check(bloater.get_active_weapon() is MeleeWeapon and not marsh.death_burst(bloater).is_empty()
			and marsh.death_burst(stalker).is_empty(), "bloaters, and only they, burst when they die")
	for bot: Actor in [stalker, shellback, bloater]:
		t.check(Look.SKINS.has(str(bot.get_meta("look", ""))) and Look.SKINS[bot.get_meta("look")].get("bare", false),
				"a %s wears a beast's own body, with nothing in its hand" % bot.faction)
	# A client builds the same beast from what it is sent.
	var copy := raid.spawn_bot("Copy", Vector3(150, 0, 150), raid.bot_seeds[shellback], false, "shellback", 1)
	t.check(copy.display_name == shellback.display_name and is_equal_approx(copy.stand_height, shellback.stand_height),
			"a client builds the same shellback from the seed and kind")
	raid.bots.erase(copy)
	copy.queue_free()
	# The Grey Matriarch at her den.
	var boss: Actor = null
	for bot in raid.bots:
		if is_instance_valid(bot) and bot.get_meta("boss", "") == "matriarch":
			boss = bot
	t.check(boss != null and raid.warlords.has(boss) and boss.display_name == "Grey Matriarch"
			and boss.stand_height > 2.5 and marsh.zone_at(boss.global_position) == 2,
			"the Grey Matriarch stands guard in the core, a stalker taller than anyone")
	raid.queue_free()
	await t.frames(1)


static func _clouds(t: Node) -> void:
	print("Marsh: spore clouds")
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 21)
	for bot in raid.bots:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	var me := raid.add_player(KIT, {}, "Cutter", "cutter")
	await t.frames(2)
	me.protected_left = 0.0
	var bloater := _bot_of(raid, "bloater")
	var stalker := _bot_of(raid, "stalker")
	var other := _bot_of(raid, "bloater")
	for bot in raid.bots:
		if is_instance_valid(bot) and bot.faction == "bloater" and bot != bloater:
			other = bot
	if bloater == null or stalker == null:
		t.check(false, "a bloater and a stalker to test with")
		raid.queue_free()
		return
	var spot := me.global_position + Vector3(2.0, 0, 0)
	bloater.global_position = spot
	stalker.global_position = me.global_position + Vector3(-1.5, 0, 0)
	if other != null and other != bloater:
		other.global_position = me.global_position + Vector3(0, 0, 2.0)
	var told: Array = []
	raid.cloud_burst.connect(func(at: Vector3, radius: float, _s: float, _k: String) -> void: told.append([at, radius]))
	var kill := DamageInfo.new()
	kill.amount = 999.0
	kill.source = me
	kill.position = spot
	kill.kind = "melee"
	Combat.deal(bloater, kill)
	t.check(bloater.is_dead and raid.clouds.size() == 1 and told.size() == 1,
			"a bloater cut down bursts into a spore cloud, and everyone is told")
	var my_health := me.health.health
	var its_health := stalker.health.health
	var other_health: float = other.health.health if other != null and other != bloater else 0.0
	await t.frames(90)
	t.check(me.health.health < my_health, "the cloud hurts the player in it")
	t.check(stalker.health.health < its_health, "and any beast of another kind")
	if other != null and other != bloater:
		t.check(is_equal_approx(other.health.health, other_health), "but not another bloater")
	me.global_position += Vector3(60, 0, 0)
	await t.frames(5)
	var away := me.health.health
	await t.frames(90)
	t.check(is_equal_approx(me.health.health, away), "out of the cloud nothing hurts")
	raid.clouds[0].left = 0.1
	await t.frames(20)
	t.check(raid.clouds.is_empty(), "and the cloud thins away")
	raid.queue_free()
	await t.frames(1)


static func _brood_and_lurkers(t: Node) -> void:
	print("Marsh: lurkers, brood keepers and hives")
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 21)
	for bot in raid.bots:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	var lurkers: Array = raid._guards.filter(func(g: Dictionary) -> bool: return g.bot != null and (g.bot as Actor).faction == "lurker")
	var keepers: Array = raid._guards.filter(func(g: Dictionary) -> bool: return g.bot != null and (g.bot as Actor).faction == "keeper")
	t.check(lurkers.size() >= 5, "lurkers lie in the pools (%d)" % lurkers.size())
	t.check(keepers.size() == 4, "a brood keeper guards a hive in each forest but the Matriarch's (%d)" % keepers.size())
	if lurkers.is_empty() or keepers.is_empty():
		raid.queue_free()
		return
	var map := raid.map
	var water_y: float = map.get("WATER_Y")
	var all_wet := lurkers.all(func(g: Dictionary) -> bool:
		var at: Vector3 = (g.marker as Node3D).global_position
		return float(map.call("ground_height", at.x, at.z)) < water_y - 0.5)
	t.check(all_wet, "every lurker's post is deep under the black water")
	var lurker: Actor = lurkers[0].bot
	var brain := lurker.get_node("Brain") as BotBrain
	t.check(brain.lies_low and brain.sight_range < 10.0 and brain.leash < 10.0 and raid._is_extra(lurker),
			"a lurker lies low, sees only close by and never leaves its pool")
	lurker.global_position = brain.home()
	var cmd := ActorCommand.new()
	brain._patrol(cmd, 0.1)
	t.check(cmd.crouch and cmd.move == Vector2.ZERO, "at its post with nothing to fight, it lies down and stays still")
	t.check(float(Look.SKINS["lurker"].get("lurks", 0.0)) > 0.3, "and its body sinks under the water while it lies low")
	# The hives.
	var hives: Array = raid._caches.filter(func(c: Dictionary) -> bool: return c.source == "hive")
	t.check(hives.size() == 4 and hives.all(func(c: Dictionary) -> bool: return (c.container as LootContainer).sealed != ""),
			"each hive is sealed while its keeper stands")
	var guard: Dictionary = keepers[0]
	var keeper: Actor = guard.bot
	var hive: Dictionary = hives.filter(func(c: Dictionary) -> bool: return c.hive == (guard.marker as Node3D).get_meta("hive"))[0]
	var box := hive.container as LootContainer
	var me := raid.add_player(KIT, {}, "Hunter", "hunter")
	await t.frames(2)
	var count := box.items.size()
	box.interact(me)
	t.check(box.items.size() == count and count > 0, "nobody loots a sealed hive")
	# Standing near, the hive spills broodlings, up to its cap.
	me.global_position = (guard.marker as Node3D).global_position + Vector3(6, 0.5, 0)
	for i in 80:
		raid._tick_brood(guard, 1.0)
	var brood: Array = guard.brood
	t.check(brood.size() == int((guard.marker as Node3D).get_meta("brood_max")) and brood.all(func(b: Actor) -> bool:
			return b.faction == "broodling" and raid._is_extra(b) and b.stand_height < 1.2),
			"near a hive its keeper spills broodlings, little stalkers, up to a cap (%d)" % brood.size())
	t.check(keeper.health.max_health > 400.0 and keeper.health.armor > 0.0 and keeper.stand_height > 2.0,
			"the keeper is big and armored")
	keeper.health.apply_damage(DamageInfo.make(99999.0, null, "test"))
	await t.frames(2)
	raid._tick_guards(0.1)
	t.check(box.sealed == "", "once the keeper falls, the hive opens")
	box.interact(me)
	t.check(box.items.size() < count, "and can be looted")
	var spilled := brood.size()
	raid._tick_brood(guard, 60.0)
	t.check(brood.size() <= spilled, "a fallen keeper spills nothing more")
	raid._tick_guards(marsh.guard_respawn_time + 1.0)
	t.check(box.sealed != "", "and when a new keeper comes, the hive is sealed again")
	raid.queue_free()
	await t.frames(1)
