extends RefCounted
## Each world's own enemies (Caleb's call: "own rosters"). The Basalt Rift
## is the Crown's cult (zealots, sharpshooters, Slag Brutes) with its lava
## beasts: Magma Crawlers that burn the ground they cross and Cinder Hounds
## in dens on the outer stacks. The Dune Sea's raiders gain a Salvage Runner
## with a knife, and a Dune Burrower lies under the sand of every other
## wreck field, bolder in a sandstorm, at peace with the raiders.

const KIT: Array[String] = ["rifle_scrap", "plate_light"]


static func run(t: Node) -> void:
	print("Enemy rosters")
	var holder := Node3D.new()
	t.add_child(holder)
	_rift_roster(t, holder)
	_dunes_roster(t, holder)
	holder.queue_free()
	await _trail(t)
	await _storm_bold(t)


## The first equip seed from 0 up that makes a bot of `kind` in `world`.
static func seed_for(world: WorldDef, kind: String, holder: Node3D, faction := "") -> int:
	for i in 400:
		var bot := Actor.new()
		bot.faction = faction
		holder.add_child(bot)
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		world.equip_bot(bot, rng)
		var got := str(bot.get_meta("kind", ""))
		bot.free()
		if got == kind:
			return i
	return -1


static func _equipped(world: WorldDef, holder: Node3D, faction: String, p_seed: int) -> Actor:
	var bot := Actor.new()
	bot.faction = faction
	holder.add_child(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	world.equip_bot(bot, rng)
	return bot


static func _rift_roster(t: Node, holder: Node3D) -> void:
	var rift := Worlds.get_world("rift")
	var roster: Dictionary = rift.get_script().get_script_constant_map()["ROSTER"]
	t.check(roster["grunt"]["look"] == "zealot" and roster["marksman"]["look"] == "sharpshooter"
			and roster["brute"]["look"] == "slag_brute", "the Rift's soldiers are the Crown's cult")
	for look: String in ["zealot", "sharpshooter"]:
		t.check(Look.SKINS[look].has("people") and Look.SKINS[look].get("paint", "") != "",
				"a %s is a person in the cult's plate" % look)
	t.check(Look.SKINS["cinder_hound"].get("creature", "") == "hound"
			and Look.SKINS["magma_crawler"].get("creature", "") == "crawler", "the lava beasts have bodies of their own")
	var crawler := _equipped(rift, holder, "", seed_for(rift, "crawler", holder))
	var trail: Dictionary = crawler.get_meta("trail", {})
	t.check(crawler.display_name == "Magma Crawler" and crawler.faction == "rift" and trail.get("kind", "") == "fire"
			and float(trail.get("damage", 0.0)) > 0.0, "a Magma Crawler fights for the cult and leaves burning ground")
	t.check(crawler.rear_damage_mult > 1.0 and crawler.health.max_health >= 300.0 and crawler.walk_speed < 3.0,
			"slow and armored, soft behind")
	crawler.free()
	var hound := _equipped(rift, holder, "hound", 1)
	t.check(hound.display_name == "Cinder Hound" and hound.faction == "rift" and hound.get_meta("look", "") == "cinder_hound"
			and hound.get_meta("edge_guard", false) and hound.sprint_speed >= 9.0 and hound.health.max_health <= 120.0,
			"a den's guard is a fast, fragile Cinder Hound of the cult's, which keeps to its mesa")
	hound.free()
	var map: Node3D = rift.create_map()
	holder.add_child(map)
	var dens := map.get_tree().get_nodes_in_group("spawn_guard").filter(
			func(m: Node) -> bool: return map.is_ancestor_of(m) and m.get_meta("faction", "") == "hound")
	var on_stacks := dens.all(func(m: Node3D) -> bool: return absf(m.global_position.x) > 60.0 and m.global_position.y > 10.0)
	t.check(dens.size() == 6 and on_stacks, "a pack of three hounds dens on each outer stack (%d)" % dens.size())
	map.free()


static func _dunes_roster(t: Node, holder: Node3D) -> void:
	var dunes := Worlds.get_world("dunes")
	var runner := _equipped(dunes, holder, "", seed_for(dunes, "runner", holder))
	t.check(runner.display_name == "Salvage Runner" and runner.get_meta("look", "") == "salvage_runner"
			and runner.weapons[0] is MeleeWeapon and runner.sprint_speed > 8.6 and int(runner.get_meta("flankers", 0)) >= 2,
			"a Salvage Runner closes in fast on a flank with a knife")
	var burrower := _equipped(dunes, holder, "burrower", 1)
	t.check(burrower.display_name == "Dune Burrower" and burrower.faction == "burrower"
			and burrower.get_meta("lies_low", false) and float(burrower.get_meta("storm_bold", 0.0)) > 0.0
			and Look.SKINS[burrower.get_meta("look", "")].get("lurks", 0.0) > 0.0,
			"a lair's guard is a Dune Burrower under the sand, bolder in a storm")
	var player := Actor.new()
	player.faction = "player"
	holder.add_child(player)
	t.check(not dunes.can_damage(burrower, runner, null) and not dunes.can_damage(runner, burrower, null),
			"burrowers and raiders leave each other be")
	t.check(dunes.can_damage(burrower, player, null) and dunes.can_damage(player, burrower, null),
			"but a burrower bites a stranger")
	for body: Actor in [runner, burrower, player]:
		body.free()
	var map: Node3D = dunes.create_map()
	holder.add_child(map)
	var lairs := map.get_tree().get_nodes_in_group("spawn_guard").filter(
			func(m: Node) -> bool: return map.is_ancestor_of(m) and m.get_meta("faction", "") == "burrower")
	t.check(lairs.size() == 4, "a burrower lies in every other wreck field (%d)" % lairs.size())
	map.free()


## A crawler's trail: a cloud of burning ground as it moves on, none while
## it stands, hurting the other side.
static func _trail(t: Node) -> void:
	print("Enemy rosters: burning ground")
	var rift := Worlds.get_world("rift")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(rift, 33)
	for bot in raid.bots:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	var me := raid.add_player(KIT, {}, "Cutter", "cutter")
	await t.frames(2)
	me.protected_left = 0.0
	var holder := Node3D.new()
	t.add_child(holder)
	var crawler := raid.spawn_bot("Crawler", me.global_position + Vector3(6.0, 0.5, 0.0), seed_for(rift, "crawler", holder),
			false, "rift")
	holder.queue_free()
	var told: Array = []
	raid.cloud_burst.connect(func(_at: Vector3, _r: float, _s: float, kind: String) -> void: told.append(kind))
	await t.frames(60)
	var first := raid.clouds.size()
	t.check(first == 1 and told == ["fire"], "a crawler leaves burning ground where it is, and everyone is told")
	await t.frames(150)
	t.check(raid.clouds.size() == first, "but not another while it stands on it")
	crawler.global_position += Vector3(4.0, 0.0, 0.0)
	await t.frames(120)
	t.check(raid.clouds.size() == first + 1, "and another as it moves on")
	var spot: Vector3 = raid.clouds[-1].at
	me.global_position = Vector3(spot.x, me.global_position.y, spot.z)
	await t.frames(5)
	var health := me.health.health
	await t.frames(80)
	t.check(me.health.health < health, "the burning ground hurts a player who stands in it")
	raid.queue_free()
	await t.frames(1)


## A burrower feels further and follows further in a sandstorm.
static func _storm_bold(t: Node) -> void:
	print("Enemy rosters: a burrower in a storm")
	var dunes := Worlds.get_world("dunes")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(dunes, 5)
	await t.frames(2)
	var burrower: Actor = null
	for bot in raid.bots:
		if is_instance_valid(bot) and bot.faction == "burrower":
			burrower = bot
	if burrower == null:
		t.check(false, "a burrower to test with")
		raid.queue_free()
		return
	var brain := burrower.get_node("Brain") as BotBrain
	brain.call("_find_target")
	var calm := brain.storm_boost
	var at := burrower.global_position
	var far := at + Vector3(brain.patrol_radius + brain.leash * 1.5, 0, 0)
	var held_back: bool = not brain.call("_within_leash", far)
	var w := raid.weather
	w.kind = "sand"
	w.radius = dunes.weather_radius
	w.centre = Vector3(at.x, 0.0, at.z)
	w.strength = 1.0
	brain.call("_find_target")
	t.check(is_equal_approx(calm, 1.0) and brain.storm_boost > 2.0,
			"in a sandstorm a burrower feels further (x%.1f)" % brain.storm_boost)
	t.check(held_back and brain.call("_within_leash", far), "and follows further from its lair")
	raid.queue_free()
	await t.frames(1)
