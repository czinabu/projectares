extends RefCounted
## The Basalt Rift (`worlds/rift/`, DESIGN.md "Basalt Rift (part one)"): the
## world plugs in, you land on the Gate Shelf, the bridges join the Shelf
## and the three mesas while the Crown stands alone, the lava burns whoever
## goes in and what they drop floats on it, and the updrafts carry a flyer
## up past their rig's ceiling. The runner finds this file by itself.


static func run(t: Node) -> void:
	print("Basalt Rift: the world plugs in")
	var world := Worlds.get_world("rift")
	t.check(world != null and world in Worlds.raid_worlds() and world.id in Portal.destinations(),
			"rift: the registry finds it and a squad portal can lead there")
	if world == null:
		return
	var rng := RandomNumberGenerator.new()
	var real := true
	for source: String in ["cache", "bot", "airship_part", "airship_hold"]:
		for i in 50:
			rng.seed = i
			real = real and world.roll_loot(source, rng).all(func(id: String) -> bool: return ItemDB.has_item(id))
	t.check(real and world.starter_loadout().all(func(id: String) -> bool: return ItemDB.has_item(id)),
			"rift: every loot table and the starter kit are real items")
	t.check(world.death_drops_scrip and "jetpack_mk1" in world.starter_loadout(),
			"rift: Ashfront's death rule (scrip, not gear), and the starter kit flies")
	_check_updraft_data(t, world)
	_check_rig_wings(t)
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 7)
	await t.frames(3)
	var map: Node3D = raid.map
	var me := raid.player
	t.check(me != null and not me.is_dead and absf(me.global_position.y - map.SHELF_TOP) < 1.0,
			"rift: you land on the Gate Shelf, %.0f m over the lava" % map.SHELF_TOP)
	t.check(world.zone_at(me.global_position) == 0 and raid.outpost_at(me.global_position) != null,
			"rift: you land in the outer ring, inside the gate outpost")
	t.check(not raid.depots.is_empty() and raid.strongpoints.size() == map.SITES.size(),
			"rift: the map has depots and its strongpoints")
	t.check(map.ground_height(0.0, 0.0) < map.LAVA_Y and map.perches.size() == map.PERCHES,
			"rift: the rift's floor lies under the lava, and %d perches stand out of it" % map.perches.size())
	var kinds := {}
	for bot in raid.bots:
		kinds[bot.get_meta("kind", "")] = true
	t.check(raid.bots.size() >= world.bot_count and kinds.keys().all(func(k: String) -> bool:
			return k in world.ROSTER or k == ""), "rift: the roster's bots spawn (%s)" % ", ".join(kinds.keys()))
	t.check(raid.bots.all(func(b: Actor) -> bool: return b.weapons.size() > 0 and b.faction != me.faction),
			"rift: every bot is armed and hostile")
	var walls := raid.get_tree().get_nodes_in_group("map_edge").filter(func(w: Node) -> bool:
			return map.is_ancestor_of(w))
	t.check(walls.size() == 4 and walls.all(func(w: Node3D) -> bool:
			return maxf(absf(w.global_position.x), absf(w.global_position.z)) <= map.FIELD + 10.0),
			"rift: walls keep everyone off the cliff tops")
	await _check_paths(t, raid, map)
	await _check_lava(t, raid, map)
	await _check_updraft_flight(t, raid, map)
	_check_boots_from_floor(t, raid, map)
	# Signing out works from the Shelf.
	me = raid.player
	if me.is_dead:
		await t._end_raid(raid)
		return
	me.global_position = (raid.get_tree().get_nodes_in_group("spawn_player")[0] as Node3D).global_position \
			+ Vector3(0, 0.1, 0)
	me.velocity = Vector3.ZERO
	me.set_physics_process(false)
	var left := []
	raid.player_finished.connect(func(_who: Actor, result: Dictionary) -> void: left.append(result.get("outcome", "")))
	raid.begin_sign_out(me)
	var state := raid.state_for(me)
	if state != null:
		state.sign_out_left = 0.05
	await t.frames(10)
	t.check(left == ["left"], "rift: a sign-out takes you home")
	await t._end_raid(raid)


## The updrafts as data: strong in a vent's middle, gone at its edge and
## over its top; the Crown above every rig's ceiling from the lava, and a
## vent beside it that rises past it.
static func _check_updraft_data(t: Node, world: WorldDef) -> void:
	var map_script: GDScript = load("res://worlds/rift/map.gd")
	var vents: Array = map_script.get("VENTS")
	var rise: float = map_script.get("VENT_RISE")
	var radius: float = map_script.get("VENT_RADIUS")
	var vent: Dictionary = vents[0]
	var at: Vector2 = vent["at"]
	var top: float = vent["top"]
	t.check(is_equal_approx(world.updraft_at(Vector3(at.x, 10.0, at.y)), rise),
			"rift: an updraft lifts at %.0f m/s in its middle" % rise)
	t.check(world.updraft_at(Vector3(at.x + radius + 0.5, 10.0, at.y)) == 0.0
			and world.updraft_at(Vector3(at.x, top + 1.0, at.y)) == 0.0
			and world.updraft_at(Vector3(at.x, top - 2.0, at.y)) < rise * 0.5,
			"rift: it is gone past its edge and over its top, and eases off just under it")
	t.check(Worlds.get_world("ashfront").updraft_at(Vector3(at.x, 10.0, at.y)) == 0.0,
			"rift: other worlds have no updrafts")
	var crown: Dictionary = map_script.get("CROWN")
	var floor_y: float = map_script.get("FLOOR_Y")
	var highest := 0.0
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "flight_rig"):
			highest = maxf(highest, float(ItemDB.item_stats(id).get("ceiling", 0.0)))
	var ride := vents.any(func(v: Dictionary) -> bool:
			return float(v["top"]) > float(crown["top"]) + 10.0 \
					and (v["at"] as Vector2).distance_to(crown["at"]) < 70.0)
	t.check(float(crown["top"]) > floor_y + highest and ride,
			"rift: the Crown (%.0f m) is over every rig's ceiling from the lava (%.0f m), and an updraft beside it rises past it"
			% [crown["top"], floor_y + highest])


## Wings in an updraft spend no glide stamina.
static func _check_rig_wings(t: Node) -> void:
	var rig := FlightRig.new()
	_wings(rig)
	rig.is_gliding = true
	rig.tick(false, 1.0)
	var spent := rig.heat
	rig.heat = 0.0
	rig.in_updraft = true
	rig.tick(false, 1.0)
	t.check(spent > 0.0 and is_zero_approx(rig.heat),
			"rift: gliding spends stamina (%.1f a second), but not in an updraft" % spent)
	rig.free()


static func _wings(rig: FlightRig) -> void:
	var stats := ItemDB.item_stats("wings_glide")
	for key: String in stats:
		if key in rig:
			rig.set(key, stats[key])
	rig.enabled = true


## The bridges: a bot can walk from the Shelf to every strongpoint, but no
## path reaches the Crown.
static func _check_paths(t: Node, raid: Raid, map: Node3D) -> void:
	var nav := map.get_world_3d().navigation_map
	for i in 600:
		if NavigationServer3D.map_get_iteration_id(nav) > 0:
			break
		await t.frames(1)
	var from := Vector3(map.SHELF_AT.x, map.SHELF_TOP, map.SHELF_AT.y)
	var reached := 0
	# The region joins the map a few frames after the bake.
	await t.frames(5)
	for site: Dictionary in map.SITES:
		var to := Vector3(site["at"].x, site["top"], site["at"].y)
		var path := NavigationServer3D.map_get_path(nav, from, to, true)
		if not path.is_empty() and path[path.size() - 1].distance_to(to) < 2.0:
			reached += 1
		else:
			print("    no way to %s (%d points, ends at %s)" % [site["name"], path.size(),
					path[path.size() - 1] if path.size() > 0 else "nowhere"])
	t.check(reached == map.SITES.size(), "rift: the bridges join the Shelf to all %d mesas (%d reached)"
			% [map.SITES.size(), reached])
	var crown := Vector3(map.CROWN["at"].x, map.CROWN["top"], map.CROWN["at"].y)
	var path := NavigationServer3D.map_get_path(nav, from, crown, true)
	t.check(path.is_empty() or path[path.size() - 1].distance_to(crown) > 10.0,
			"rift: no path reaches the Crown")
	t.check(raid.get_tree().get_nodes_in_group("rift_bridge").size() == map.BRIDGES.size(),
			"rift: %d bridges stand over the lava" % map.BRIDGES.size())


## The lava burns a bot that goes in, and a player; what the player drops
## floats on it.
static func _check_lava(t: Node, raid: Raid, map: Node3D) -> void:
	var spot := Vector2(-60.0, 60.0)
	var floor_y: float = map.call("ground_height", spot.x, spot.y)
	var bot: Actor = null
	for b in raid.bots:
		if is_instance_valid(b) and not b.is_dead and not raid.warlords.has(b):
			bot = b
			break
	bot.global_position = Vector3(spot.x, floor_y + 0.2, spot.y)
	bot.velocity = Vector3.ZERO
	await t.frames(60)
	t.check(bot.is_dead, "rift: a bot that falls in the lava burns to death within a second")
	var me := raid.player
	me.protected_left = 0.0
	# Scrip in hand, so the death leaves a pile.
	raid.state_for(me).scrip = 120
	me.scrip = 120
	var spawned: Array[LootContainer] = []
	raid.container_spawned.connect(func(c: LootContainer) -> void: spawned.append(c))
	# Dead in the air over the lava: what drops comes down on the lava, not in it.
	me.global_position = Vector3(spot.x + 10.0, 15.0, spot.y)
	me.velocity = Vector3.ZERO
	t.check(absf(raid.drop_spot(me).y - map.LAVA_Y) < 0.01,
			"rift: what someone drops dying over the lava floats on it")
	me.global_position = Vector3(spot.x + 10.0, floor_y + 0.2, spot.y)
	await t.frames(60)
	t.check(me.is_dead, "rift: so does a player")
	var floating := spawned.filter(func(c: LootContainer) -> bool:
			return is_instance_valid(c) and absf(c.global_position.y - map.LAVA_Y) < 0.5)
	t.check(not floating.is_empty(), "rift: their scrip floats on the lava for a flyer to grab")
	# Back in on the Shelf, as the stash's owner does after a death.
	raid.add_player(raid.world.starter_loadout())
	await t.frames(3)


## A jetpack hovering in an updraft is carried up past its ceiling to the
## vent's top; out of one it stops at the ceiling.
static func _check_updraft_flight(t: Node, raid: Raid, map: Node3D) -> void:
	var me := raid.player
	if me == null or me.is_dead:
		t.check(false, "rift: a player to fly the updraft")
		return
	me.protected_left = 999.0
	var vent: Dictionary = map.VENTS[4]
	var at: Vector2 = vent["at"]
	me.global_position = Vector3(at.x, 30.0, at.y)
	me.velocity = Vector3.ZERO
	me.cmd.secondary = true
	await t.frames(2)
	t.check(me.flight.enabled and me.flight.is_hovering and me.flight.in_updraft,
			"rift: a jetpack hovering over a vent rides its updraft")
	t.check(raid.zone_label(me).ends_with("updraft"), "rift: the watch says so (%s)" % raid.zone_label(me))
	var ceiling: float = map.FLOOR_Y + me.flight.ceiling
	await t.frames(60 * 9)
	t.check(me.global_position.y > ceiling + 15.0 and me.global_position.y < float(vent["top"]) + 1.0,
			"rift: it carries you up past your rig's ceiling (%.0f m) towards its top (%.0f m; at %.0f m)"
			% [ceiling, vent["top"], me.global_position.y])
	# Out of the updraft, the same hover only holds.
	me.global_position = Vector3(at.x + 30.0, ceiling + 10.0, at.y)
	me.velocity = Vector3.ZERO
	await t.frames(60)
	var held := me.global_position.y
	me.cmd.jump = true
	await t.frames(60)
	me.cmd.jump = false
	t.check(not me.flight.in_updraft and me.global_position.y < held + 1.0,
			"rift: out of an updraft a rig over its ceiling climbs no higher")
	me.cmd.secondary = false
	me.protected_left = 0.0


## Boots count their ceiling from the floor last stood on, so a kick in
## the air off a mesa still lifts; a jetpack still counts from the lava's
## floor, so it never stacks a mesa's height onto its ceiling.
static func _check_boots_from_floor(t: Node, raid: Raid, map: Node3D) -> void:
	var me := raid.player
	if me == null or me.is_dead:
		return
	var anvil: Dictionary = map.SITES[1]
	var top: float = anvil["top"]
	var rig := me.flight
	var was := {"item_id": rig.item_id, "ceiling": rig.ceiling, "enabled": rig.enabled}
	var heights := {}
	for id: String in ["boots_thruster", "jetpack_mk1"]:
		rig.item_id = id
		rig.ceiling = float(ItemDB.item_stats(id).get("ceiling", 0.0))
		rig.enabled = true
		me.global_position = Vector3(anvil["at"].x, top, anvil["at"].y)
		me.call("_measure_altitude", true)
		me.global_position.y = top + 3.0
		me.call("_measure_altitude", false)
		heights[id] = rig.altitude
	t.check(absf(float(heights["boots_thruster"]) - 3.0) < 0.01
			and float(heights["jetpack_mk1"]) > top,
			"rift: boots count their ceiling from the mesa they kicked off (%.0f m up), a jetpack from the lava's floor (%.0f m)"
			% [heights["boots_thruster"], heights["jetpack_mk1"]])
	for key: String in was:
		rig.set(key, was[key])
