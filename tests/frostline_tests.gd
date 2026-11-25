extends RefCounted
## The `frostline` checks. The test runner finds this file by itself and calls
## `run(t)`.

const MapScript_Frost := preload("res://worlds/frostline/map.gd")


static func run(t: Node) -> void:
	print("Frostline")
	var world := Worlds.get_world("frostline")
	t.check(world != null, "frostline is discovered from its folder")
	if world == null:
		return
	t.check(ItemDB.has_item("frost_signal_core") and ItemDB.has_tag("frost_ice_axe", "melee"),
			"a world registers its own items")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var relay := world.roll_loot("relay", rng)
	t.check(relay.size() >= 3, "the relay mast cache rolls rich loot")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(world, 7)
	# The valley's enemies are pockets that wake near a player: visit a den
	# and a post.
	_wake_near(raid, "feral")
	_wake_near(raid, "warden")
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(3)
	var factions := {}
	for bot in raid.bots:
		factions[bot.faction] = factions.get(bot.faction, []) + [bot]
	t.check(factions.has("warden") and factions.has("feral"), "both enemy factions spawn")
	var relay_caches := raid._caches.filter(func(c: Dictionary) -> bool: return c.source == "relay")
	t.check(relay_caches.size() == 1 and (relay_caches[0].container as Node3D).global_position.y
			> raid.map.call("ground_height", 0.0, MapScript_Frost.ENGINE_Z) + 20.0,
			"one cache sits on the Stilled Engine's back, where only flight reaches")
	var rim_caches := raid._caches.filter(func(c: Dictionary) -> bool: return c.source == "rooftop")
	t.check(rim_caches.size() >= 4, "the rims' listening posts hold the rooftop caches (%d)" % rim_caches.size())
	var zones := {}
	for c: Dictionary in raid._caches:
		zones[world.zone_at((c.container as Node3D).global_position)] = true
	t.check(zones.has(0) and zones.has(1) and zones.has(2), "there are caches in every zone, from the river mouth to the core")
	var map := raid.map
	var outside := map.call("ground_height", MapScript_Frost.centre(0.0), 0.0) as float
	var shelf := MapScript_Frost.shelf_point(0.0, 1.0)
	t.check(map.call("ground_height", shelf.x, shelf.y) - outside > 10.0,
			"the walls step up to a shelf over the valley floor")
	# The region is built off the main thread: wait until the map has it.
	var nav_map := raid.map.get_world_3d().navigation_map
	for i in 600:
		if NavigationServer3D.map_get_closest_point(nav_map, Vector3(0, 0, 250)) != Vector3.ZERO:
			break
		await t.frames(1)
	var path := NavigationServer3D.map_get_path(nav_map,
			Vector3(MapScript_Frost.centre(230.0), map.call("ground_height", MapScript_Frost.centre(230.0), 230.0), 230.0),
			Vector3(MapScript_Frost.shelf_point(150.0, -1.0).x, 0, 150.0) + Vector3(0, map.call("ground_height",
					MapScript_Frost.shelf_point(150.0, -1.0).x, 150.0), 0), true)
	t.check(path.size() > 1 and path[path.size() - 1].y > outside + 10.0,
			"a ramp leads up from the floor to the shelf (path ends at %s)" % (path[path.size() - 1] if path.size() > 0 else "nowhere"))
	if factions.has("warden") and factions.has("feral"):
		var warden: Actor = factions.warden[0]
		var feral: Actor = factions.feral[0]
		t.check(Combat.deal(feral, DamageInfo.make(5.0, warden, "bullet")), "wardens and ferals hurt each other")
		t.check(Combat.deal(raid.player, DamageInfo.make(5.0, feral, "melee")), "ferals hurt the player")
		var ally := Actor.new()
		raid.add_child(ally)
		t.check(not Combat.deal(ally, DamageInfo.make(5.0, raid.player, "bullet"))
				and not Combat.deal(raid.player, DamageInfo.make(5.0, ally, "bullet")),
				"players cannot hurt each other on a PvE world")
		ally.queue_free()
		if factions.warden.size() >= 2:
			t.check(not Combat.deal(factions.warden[1], DamageInfo.make(5.0, warden, "bullet")),
					"a faction does not hurt itself")
	# The gentle world: basic loot, and death only costs the backpack.
	var gear_tags := ["weapon", "armor", "flight_rig", "ability", "vehicle"]
	var too_good: Array[String] = []
	for source: String in ["cache", "cache_core", "rooftop", "relay", "warden", "feral", "vehicle"]:
		for i in 300:
			for id in world.roll_loot(source, rng):
				var is_gear := gear_tags.any(func(tag: String) -> bool: return ItemDB.has_tag(id, tag))
				if is_gear and ItemDB.item_rarity(id) > ItemDB.Rarity.UNCOMMON and not id.begins_with("frost_") \
						and id not in too_good:
					too_good.append(id)
	t.check(too_good.is_empty(), "Frostline only drops basic gear, apart from its own (%s)" % ", ".join(too_good))
	var ash_gear: Array[String] = []
	var ashfront := Worlds.get_world("ashfront")
	for i in 300:
		for id in ashfront.roll_loot("rooftop", rng):
			if ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE and ItemDB.has_tag(id, "weapon") and id not in ash_gear:
				ash_gear.append(id)
	t.check(ash_gear.size() >= 3, "the PvP world is where rare weapons drop (%d kinds)" % ash_gear.size())
	await t._end_raid(raid)
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "frame_trooper"])
	Profile.equip("primary", "rifle_carbine")
	Profile.equip("frame", "frame_trooper")
	raid = Raid.new()
	t.add_child(raid)
	raid.start(world, 8, Profile.checkout_loadout(world))
	_wake_near(raid, "warden")
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(3)
	var gentle: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: gentle.append(r))
	raid.player.inventory.add_item("frost_cryo_cell")
	raid.player.kill("melee", raid.bots[0])
	await t.frames(2)
	var dropped := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	t.check(dropped.size() == 1 and "frost_cryo_cell" in (dropped[0] as LootContainer).items
			and "rifle_carbine" not in (dropped[0] as LootContainer).items,
			"on a gentle world only the backpack drops when you die")
	t.check(gentle.size() == 1 and gentle[0].outcome == "died" and "rifle_carbine" in gentle[0].kept_gear
			and "frost_cryo_cell" in gentle[0].lost and "rifle_carbine" not in gentle[0].lost
			and Hud.death_text(gentle[0], 0.0).contains("Kept"),
			"the result says what was kept and what was lost")
	t.check("rifle_carbine" in Profile.stash and "frame_trooper" in Profile.stash
			and Profile.equipped("primary") == "rifle_carbine" and "frost_cryo_cell" not in Profile.stash,
			"your equipped gear is back in the stash and still in the loadout")
	var kit_again := Profile.checkout_loadout(world)
	t.check("rifle_carbine" in kit_again, "so you drop back in with the same gear")
	Profile.reset()
	Profile.welcome_granted = true
	# The ice axe is real gear: it equips as a melee weapon with its stats.
	var axe_holder := Actor.new()
	t.add_child(axe_holder)
	Loadout.equip(axe_holder, ["frost_ice_axe"])
	var axe := axe_holder.weapons[0] as MeleeWeapon if not axe_holder.weapons.is_empty() else null
	t.check(axe != null and is_equal_approx(axe.heavy_lunge, 12.0), "the ice axe equips with its own stats")
	axe_holder.queue_free()
	await t._end_raid(raid)


## Walks the player over to the first pocket of `faction` and lets it wake.
static func _wake_near(raid: Raid, faction: String) -> void:
	for marker in raid._map_nodes("spawn_guard"):
		if str(marker.get_meta("faction", "")) == faction and not str(marker.get_meta("pocket", "")).begins_with("engine"):
			raid.player.global_position = marker.global_position + Vector3(30, 1, 0)
			raid._tick_pockets()
			return
