extends RefCounted
## Checks for Frostline's defence grid (DESIGN.md "Frostline", step 7): the
## Wardens call each other to a fight they survive, and the Engine Sentinel
## guards the hatch, made for one player and tougher with more. Kept in its
## own file and called from the test runner.

const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]


static func run(t: Node) -> void:
	_settings(t)
	await _sentinel(t)
	await _linked(t)


static func _settings(t: Node) -> void:
	print("Grid: the world's settings")
	var frost := Worlds.get_world("frostline")
	var ash := Worlds.get_world("ashfront")
	t.check(frost.linked_factions.has("warden") and not frost.linked_factions.has("feral")
			and ash.linked_factions.is_empty(),
			"Frostline's Wardens are linked, its Ferals and Ashfront's armies are not")
	t.check(frost.boss_party_scale > 0.0 and ash.boss_party_scale == 0.0,
			"Frostline's boss scales with the players near it; Ashfront's warlords do not")
	t.check(frost.warlord_blueprint_chance > 0.0 and frost.warlord_blueprint_chance < ash.warlord_blueprint_chance,
			"a Frostline warlord may carry a war blueprint, rarer than in Ashfront")


static func _sentinel_of(raid: Raid) -> Actor:
	for bot in raid.bots:
		if is_instance_valid(bot) and bot.get_meta("boss", "") == "sentinel":
			return bot
	return null


static func _hold_still(raid: Raid) -> void:
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)


static func _sentinel(t: Node) -> void:
	print("Grid: the Engine Sentinel")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 91)
	_hold_still(raid)
	var boss := _sentinel_of(raid)
	var markers := raid._map_nodes("spawn_boss")
	var sentinels := markers.filter(func(m: Node3D) -> bool: return m.get_meta("boss", "") == "sentinel")
	var keepers := markers.filter(func(m: Node3D) -> bool: return m.get_meta("keeper", false))
	t.check(sentinels.size() == 1 and sentinels[0].get_meta("faction", "") == "warden"
			and keepers.size() == 1 and markers.size() == 2,
			"the map has two boss markers: the Sentinel, a Warden, at the Engine, and the Heart's keeper inside")
	t.check(boss != null and raid.warlords.has(boss), "a Sentinel stands guard as the world's core boss")
	if boss == null:
		raid.queue_free()
		return
	t.check(boss.display_name == "Engine Sentinel" and boss.faction == "warden"
			and boss.get_meta("look", "") == "colossus" and boss.stand_height > 3.0,
			"it is a Warden three metres tall")
	t.check(boss.rear_damage_mult > 1.0 and float(boss.get_meta("lock_time", 0.0)) > 0.0
			and boss.health.max_health >= 400.0,
			"with a weak spot in its back and a lance that holds its beam before it fires")
	t.check(boss.inventory.has_item("upgrade_data"), "and it carries upgrade data")
	# A client builds the same machine from the seed, faction and boss kind.
	var copy := raid.spawn_bot("Copy", Vector3(400, 0, 400), raid.bot_seeds[boss], true, "warden", 2, [], "sentinel")
	t.check(copy.display_name == boss.display_name and is_equal_approx(copy.stand_height, boss.stand_height)
			and is_equal_approx(copy.health.max_health, boss.health.max_health),
			"a client builds the same Sentinel from what it is sent")
	raid.bots.erase(copy)
	copy.queue_free()
	# One player fights it as it is; two near it make it tougher; it eases
	# back when they leave.
	var one := raid.add_player(KIT, {}, "One", "one")
	var two := raid.add_player(KIT, {}, "Two", "two")
	one.global_position = boss.global_position + Vector3(8, 0, 0)
	two.global_position = boss.global_position + Vector3(400, 0, 0)
	await t.frames(80)
	t.check(is_equal_approx(boss.toughness, 1.0), "alone, a player fights it as it is")
	# Hits from in front and from behind (its heat vent), alone.
	boss.cmd.yaw = 0.0
	one.global_position = boss.global_position + Vector3(0, 0, -8)
	var front := DamageInfo.make(60.0, one, "bullet")
	boss.modify_incoming(front)
	one.global_position = boss.global_position + Vector3(0, 0, 8)
	var rear := DamageInfo.make(60.0, one, "bullet")
	boss.modify_incoming(rear)
	t.check(is_equal_approx(front.amount, 60.0) and is_equal_approx(rear.amount, 60.0 * boss.rear_damage_mult),
			"alone its hits land in full, and double in its back (%.0f, %.0f)" % [front.amount, rear.amount])
	two.global_position = boss.global_position + Vector3(-8, 0, 0)
	await t.frames(80)
	t.check(is_equal_approx(boss.toughness, 1.0 + frost.boss_party_scale),
			"a second player near it makes it tougher (%.2f)" % boss.toughness)
	one.global_position = boss.global_position + Vector3(0, 0, -8)
	var shared := DamageInfo.make(60.0, one, "bullet")
	boss.modify_incoming(shared)
	t.check(is_equal_approx(shared.amount, 60.0 / boss.toughness), "so each hit does less (%.1f of 60)" % shared.amount)
	two.global_position = boss.global_position + Vector3(400, 0, 0)
	await t.frames(80)
	t.check(is_equal_approx(boss.toughness, 1.0), "and it eases back when they leave")
	# Killed, it comes back after a while, with the world's own news.
	var news: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: news.append(text))
	boss.health.apply_damage(DamageInfo.make(99999.0, null, "test"))
	await t.frames(3)
	raid._tick_bosses(0.0)
	raid._tick_bosses(frost.boss_respawn_time + 1.0)
	var back := _sentinel_of(raid)
	t.check(back != null and back != boss and not back.is_dead, "a dead Sentinel comes back")
	t.check(news.any(func(s: String) -> bool: return s.contains("Engine Sentinel")),
			"and the feed says so in the world's words (%s)" % [news])
	raid.queue_free()
	await t.frames(2)


static func _linked(t: Node) -> void:
	print("Grid: the Wardens call each other")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 92)
	_hold_still(raid)
	var me := raid.add_player(KIT, {}, "Caller", "caller")
	await t.frames(3)
	var wardens: Array[Actor] = []
	var ferals: Array[Actor] = []
	for bot in raid.bots:
		if bot.get_meta("boss", "") != "":
			bot.global_position = Vector3(900, 0, 900)
			continue
		if bot.faction == "warden":
			wardens.append(bot)
		elif bot.faction == "feral":
			ferals.append(bot)
	var made := 0
	while wardens.size() < 4 and made < 6:
		var extra := raid.spawn_bot("Extra%d" % made, Vector3(0, 0, 0), 1000 + made, false, "warden")
		var brain := BotBrain.new()
		brain.name = "Brain"
		extra.add_child(brain)
		brain.set_physics_process(false)
		extra.set_physics_process(false)
		extra.health.damaged.connect(raid._on_linked_hurt.bind(extra))
		wardens.append(extra)
		made += 1
	# Everyone else far away, out of the way.
	for bot in raid.bots:
		if bot not in wardens:
			bot.global_position = Vector3(-900, 0, -900)
	var at := Vector3(0, 2, 0)
	wardens[0].global_position = at
	wardens[1].global_position = at + Vector3(20, 0, 0)
	wardens[2].global_position = at + Vector3(frost.linked_factions["warden"] + 30.0, 0, 0)
	wardens[3].global_position = at + Vector3(0, 0, 25)
	me.global_position = at + Vector3(0, 0, -30)
	for w in wardens:
		(w.get_node("Brain") as BotBrain).state = BotBrain.State.PATROL
		# Posted where they stand, so the call is within their leash.
		(w.get_node("Brain") as BotBrain).post_to(w.global_position, 12.0)
		w.health.health = w.health.max_health
		w.health.armor = 0.0
	var calls: Array[Actor] = []
	raid.grid_called.connect(func(bot: Actor, _source: Actor) -> void: calls.append(bot))
	Combat.deal(wardens[0], DamageInfo.make(10.0, me, "bullet", wardens[0].global_position))
	var near := wardens[1].get_node("Brain") as BotBrain
	var far := wardens[2].get_node("Brain") as BotBrain
	t.check(calls.size() == 1 and calls[0] == wardens[0], "a Warden hurt and still standing calls the grid")
	t.check(near.state == BotBrain.State.CHASE and far.state == BotBrain.State.PATROL,
			"Wardens within range come to look; one past it stays on patrol")
	# It calls at most so often.
	Combat.deal(wardens[0], DamageInfo.make(5.0, me, "bullet", wardens[0].global_position))
	t.check(calls.size() == 1, "a second hit straight after calls nobody new")
	# A kill in one blow calls nobody, so a clean kill stays quiet.
	near.state = BotBrain.State.PATROL
	wardens[1].global_position = wardens[3].global_position + Vector3(10, 0, 0)
	Combat.deal(wardens[3], DamageInfo.make(9999.0, me, "melee", wardens[3].global_position))
	t.check(wardens[3].is_dead and calls.size() == 1 and near.state == BotBrain.State.PATROL,
			"a Warden killed in one blow calls nobody")
	# Ferals are not on the grid.
	if not ferals.is_empty():
		var feral := ferals[0]
		feral.global_position = at + Vector3(5, 0, 5)
		feral.health.health = feral.health.max_health
		Combat.deal(feral, DamageInfo.make(5.0, me, "bullet", feral.global_position))
		t.check(calls.size() == 1, "a Feral hurt calls nobody: only the Wardens are linked")
	raid.queue_free()
	await t.frames(2)
