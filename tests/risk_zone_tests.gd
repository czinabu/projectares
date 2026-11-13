extends RefCounted
## Checks for Ashfront's risk zones and gate outposts (DESIGN.md section 2,
## "Risk zones"): the tiers, the burning core and its boss, the loot by
## zone, and the outposts' shelter, entry rules and protection on the way
## out. Kept in its own file and called from the test runner.

const MapScript := preload("res://worlds/ashfront/map.gd")


static func run(t: Node) -> void:
	_zones(t)
	Raid.zone_rules = true
	var raid: Raid = await t._new_raid(4242, false)
	_map(t, raid)
	await _shelter(t, raid)
	await _turned_away(t, raid)
	await _hazard(t, raid)
	await _boss(t, raid)
	await t._end_raid(raid)
	Raid.zone_rules = false


static func _zones(t: Node) -> void:
	print("Risk zones: tiers and loot")
	var world := Worlds.get_world("ashfront")
	t.check(world.zone_at(Vector3.ZERO) == 2 and world.zone_at(Vector3(-150, 0, -118)) == 1
			and world.zone_at(Vector3(248, 0, 0)) == 0, "Ashfront is a core, a middle and an outer ring")
	t.check(world.hazard_at(Vector3(10, 0, 5)) > 0.0 and world.hazard_at(Vector3(120, 0, 0)) == 0.0,
			"only the core burns")
	t.check(Worlds.get_world("frostline").zone_at(Vector3.ZERO) == -1
			and Worlds.get_world("frostline").hazard_at(Vector3.ZERO) == 0.0, "a world without zones has none")
	t.check(world.zone_name(0) != "" and world.zone_name(2) != "" and world.zone_name(-1) == "",
			"each tier has a name for the watch")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var outer := 0.0
	var core := 0.0
	var outer_count := 0
	var core_count := 0
	for i in 200:
		var a := world.roll_loot("cache_outer", rng)
		var b := world.roll_loot("cache_core", rng)
		outer_count += a.size()
		core_count += b.size()
		for id in a:
			outer += ItemDB.item_rarity(id)
		for id in b:
			core += ItemDB.item_rarity(id)
	t.check(core_count > outer_count and core / core_count > outer / outer_count,
			"core caches hold more and rarer loot than the outer ring's")
	var bad := false
	for i in 200:
		for id in world.roll_loot("cache_core", rng) + world.roll_loot("cache_outer", rng):
			bad = bad or not ItemDB.has_item(id)
	t.check(not bad, "every zone's loot is a real item")
	t.check(ActorCommand.STATE_SHELTERED & (ActorCommand.HELD_MASK | ActorCommand.ONE_SHOT_MASK
			| ActorCommand.STATE_HOVERING) == 0, "the sheltered bit is a bit of its own")


static func _map(t: Node, raid: Raid) -> void:
	print("Risk zones: the map")
	t.check(raid.outposts.size() == MapScript.OUTPOSTS.size(), "Ashfront has its gate outposts")
	var spawns_inside := true
	for marker in raid._map_nodes("spawn_player"):
		spawns_inside = spawns_inside and raid.outpost_at(marker.global_position) != null
	t.check(spawns_inside, "players arrive inside the gate outposts")
	var depots := 0
	for gate in raid.outposts:
		for depot in raid.depots:
			if raid.outpost_at(depot.global_position - Vector3(0, 2, 0)) == gate:
				depots += 1
				break
	t.check(depots == raid.outposts.size(), "every outpost has a depot to bank at")
	var sources := {}
	for cache in raid._caches:
		sources[cache.source] = true
	t.check(sources.has("cache_core") and sources.has("cache_outer") and sources.has("cache"),
			"caches pay by the zone they stand in")
	var outer_bots: Array[float] = []
	var middle_bots: Array[float] = []
	var marked := true
	for bot in raid.bots:
		marked = marked and bot.has_meta("zone")
		if raid.warlords.has(bot):
			continue
		if int(bot.get_meta("zone", -1)) == 0:
			outer_bots.append(bot.health.max_health)
		elif int(bot.get_meta("zone", -1)) == 1:
			middle_bots.append(bot.health.max_health)
	t.check(marked, "every bot knows the zone it arrived in")
	t.check(not outer_bots.is_empty() and not middle_bots.is_empty()
			and _mean(outer_bots) < _mean(middle_bots), "soldiers in the middle are tougher than on the rim")


static func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(values.size(), 1.0)


static func _put(raid: Raid, actor: Actor, at: Vector3) -> void:
	actor.global_position = raid._stand(Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z))
	actor.velocity = Vector3.ZERO


static func _shelter(t: Node, raid: Raid) -> void:
	print("Risk zones: gate outposts")
	var me := raid.player
	var state := raid.state_for(me)
	var gate := raid.outposts[0]
	_put(raid, me, gate.global_position)
	await t.frames(3)
	t.check(state.sheltered and me.weapons_locked, "inside a gate outpost weapons are locked")
	t.check(raid.zone_label(me).contains("safe"), "the watch says the outpost is safe")
	var bot := raid.bots[0]
	var info := DamageInfo.new()
	info.amount = 30.0
	info.source = bot
	var before := me.health.health
	Combat.deal(me, info)
	t.check(me.health.health == before, "nobody can hurt you inside an outpost")
	t.check(raid.begin_sign_out(me) and is_equal_approx(raid.state_for(me).sign_out_left, raid.world.outpost_sign_out_time),
			"signing out at a gate is quick")
	raid.cancel_sign_out(me)
	# Walking out: protected for a moment, until you fire.
	var out := Vector3(gate.global_position.x, 0, gate.global_position.z).normalized()
	_put(raid, me, gate.global_position - out * (MapScript.OUTPOST_RADIUS + 6.0))
	await t.frames(2)
	t.check(not state.sheltered and not me.weapons_locked and me.protected_left > 0.0,
			"leaving an outpost unlocks weapons with a moment of protection")
	me.cmd.primary = true
	await t.frames(2)
	me.cmd.primary = false
	t.check(me.protected_left <= 0.0, "firing gives that protection up")


static func _turned_away(t: Node, raid: Raid) -> void:
	var me := raid.player
	var state := raid.state_for(me)
	var gate := raid.outposts[1]
	state.last_combat = raid.clock
	_put(raid, me, gate.global_position)
	await t.frames(2)
	var flat := Vector2(me.global_position.x - gate.global_position.x, me.global_position.z - gate.global_position.z)
	t.check(not state.sheltered and not me.weapons_locked and flat.length() > MapScript.OUTPOST_RADIUS,
			"someone in a fight is turned away at the gate")
	state.last_combat = -INF
	me.bounty = 50
	_put(raid, me, gate.global_position)
	await t.frames(1)
	t.check(not state.sheltered, "someone carrying a bounty is turned away too")
	me.bounty = 0
	_put(raid, me, gate.global_position)
	await t.frames(2)
	t.check(state.sheltered, "out of the fight, the gate lets them in")
	_put(raid, me, gate.global_position * 0.5)
	await t.frames(2)


static func _hazard(t: Node, raid: Raid) -> void:
	print("Risk zones: the core")
	var me := raid.player
	var state := raid.state_for(me)
	_put(raid, me, Vector3(18, 0, -30))
	await t.frames(1)
	me.protected_left = 0.0
	state.leaving_gate = false
	me.health.health = me.health.max_health
	await t.frames(150)
	t.check(me.health.health < me.health.max_health, "the core's molten ground burns you")
	t.check(raid.zone_label(me).begins_with(raid.world.zone_name(2)), "the watch says you are in the core")


static func _boss(t: Node, raid: Raid) -> void:
	var boss: Actor = null
	for b in raid._bosses:
		boss = b.bot
	t.check(boss != null and raid.warlords.has(boss) and raid.world.zone_at(boss.global_position) == 2,
			"a warlord holds the core")
	t.check(raid._is_extra(boss), "the boss is not part of the armies")
	var wait := raid.world.boss_respawn_time
	raid.world.boss_respawn_time = 0.5
	boss.kill("test")
	await t.frames(60)
	var back: Variant = raid._bosses[0].bot
	t.check(back != null and is_instance_valid(back) and back != boss and raid.warlords.has(back),
			"a dead boss comes back after a while")
	raid.world.boss_respawn_time = wait
