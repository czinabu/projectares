extends RefCounted
## The `plaza` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Plaza safe zone")
	var plaza := Worlds.social_world()
	t.check(plaza != null and plaza.safe_zone, "the registry finds a safe-zone world")
	if plaza == null:
		return
	t.check(not Worlds.raid_worlds().has(plaza) and Worlds.raid_worlds().size() == Worlds.all().size() - 1,
			"safe zones are not listed as worlds to deploy into")
	var raid := Raid.new()
	t.add_child(raid)
	raid.mode = Raid.Mode.SERVER
	raid.start_server(plaza, 5)
	var kit: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "field_dressing"]
	var a := raid.add_player(kit, {}, "Ada")
	var b := raid.add_player(kit, {}, "Bo")
	await t.frames(20)
	t.check(raid.bots.is_empty(), "no bots in the plaza")
	t.check(raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer).is_empty(), "no loot in the plaza")
	t.check(a.is_on_floor() and b.is_on_floor(), "players stand on the plaza floor")
	t.check(a.gear_items.size() >= 3 and a.weapons.size() == 2, "players wear their loadout (%d pieces)" % a.gear_items.size())
	t.check(a.weapons_locked and b.weapons_locked, "weapons are locked in a safe zone")

	# Shooting and swinging do nothing.
	b.global_position = a.global_position + Basis(Vector3.UP, a.cmd.yaw) * Vector3(0, 0, -4)
	await t.frames(2)
	var gun := a.weapons[0] as Gun
	var ammo: int = gun.ammo_in_mag
	a.cmd.primary = true
	a.cmd.primary_pressed = true
	await t.frames(30)
	a.cmd.primary = false
	a.cmd.primary_pressed = false
	t.check(gun.ammo_in_mag == ammo, "a held trigger fires nothing")
	t.check(b.health.health == b.health.max_health, "nobody is hurt")
	a.cmd.switch_weapon = 1
	await t.frames(2)
	a.cmd.switch_weapon = -1
	t.check(a.active_weapon_index == -1, "weapons stay away in a safe zone: arriving unarmed, nothing can be drawn")
	var hit := Combat.deal(b, DamageInfo.make(50.0, a, "bullet", b.global_position))
	t.check(not hit and b.health.health == b.health.max_health, "Combat refuses every hit in a safe zone")

	# A fall off the map puts you back, unharmed.
	b.global_position = Vector3(0, -40, 0)
	await t.frames(3)
	t.check(not b.is_dead and b.global_position.y > -1.0, "falling out puts you back at the arrival pad")

	# Portals: one per raid world, plus home and the clan hall.
	var portals := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("portal"))
	var destinations := portals.map(func(n: Node) -> String: return n.get_meta("destination", ""))
	var all_worlds := Worlds.raid_worlds().all(func(w: WorldDef) -> bool: return ("world:" + w.id) in destinations)
	t.check(all_worlds, "there is a deploy gate for every raid world")
	t.check("home" in destinations, "there is a door to the home base")
	t.check("clans" in destinations, "there is a clan hall")
	t.check("market" in destinations, "there is a player market kiosk (the Exchange)")
	t.check(portals.all(func(n: Node) -> bool: return n.get_meta("label", "") != ""), "every portal says where it goes")
	# Shops are physical places: a storefront for each one the game has.
	var shops: Array = raid.map.shops()
	var fronts := portals.filter(func(n: Node) -> bool: return n.is_in_group("shop_front"))
	t.check(fronts.size() == shops.size() and shops.all(func(entry: Dictionary) -> bool:
		return ("shop:" + str(entry.id)) in destinations), "every shop has a storefront (%d)" % fronts.size())
	var apart := true
	for one: Node3D in portals:
		for other: Node3D in portals:
			if one != other and one.global_position.distance_to(other.global_position) < 5.5:
				apart = false
	t.check(apart, "no two doorways overlap")
	var reachable := portals.all(func(n: Node) -> bool:
		return (n as Node3D).global_position.length() < raid.map.RADIUS and absf((n as Node3D).global_position.y) < 0.5)
	t.check(reachable, "every portal is on the plaza floor")
	# An open district, not a courtyard: the skyline's landing decks stay in
	# reach of the thruster boots (three kicks top 15 m).
	var decks := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("landing_deck"))
	t.check(raid.map.RADIUS >= 120.0 and decks.size() >= 6 and decks.all(func(n: Node) -> bool:
		return (n as Node3D).global_position.y <= 15.5), "the hub is open and its landing decks are in boot reach (%d)" % decks.size())
	var floor_hit := raid.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(0, 5, raid.map.RADIUS - 6.0), Vector3(0, -5, raid.map.RADIUS - 6.0), Actor.LAYER_WORLD))
	t.check(not floor_hit.is_empty(), "the deck reaches out to the balcony rail")
	var deck: Node3D = decks[0] if not decks.is_empty() else null
	var deck_hit := {} if deck == null else raid.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(deck.global_position + Vector3(0, 5, 0),
			deck.global_position - Vector3(0, 5, 0), Actor.LAYER_WORLD))
	t.check(not deck_hit.is_empty() and absf(deck_hit.position.y - deck.global_position.y) < 0.3,
			"a landing deck is solid where it is marked")
	# The megacity round the deck is scenery the view must reach (Caleb's
	# "tall and grand"): drawn far enough, and never built headless.
	t.check(float(raid.map.get_meta("view_far", 0.0)) >= 3000.0 and raid.map.find_child("Megacity", false, false) == null,
			"the Concourse draws its megacity far off, and a server builds none of it")

	# Leaving takes you and nothing else: no body, no bag.
	raid.remove_player(b)
	await t.frames(3)
	t.check(not is_instance_valid(b) or b.is_queued_for_deletion(), "a player who leaves is simply gone")
	t.check(raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer).is_empty(), "leaving drops no bag")
	t.check(raid.players.size() == 1, "the others stay")

	# A warzone in the same process keeps its own rules.
	var war := Raid.new()
	t.add_child(war)
	war.start(Worlds.get_world("ashfront"), 3)
	for bot in war.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(3)
	t.check(Worlds.of(a) == plaza and Worlds.of(war.player).id == "ashfront", "each actor answers to its own world")
	var foe := war.bots[0]
	t.check(Combat.deal(foe, DamageInfo.make(5.0, war.player, "bullet", foe.global_position)), "the warzone still deals damage")
	t.check(not Combat.deal(a, DamageInfo.make(5.0, war.player, "bullet", a.global_position)),
			"a warzone hit cannot reach into the plaza")
	t.check(not Combat.deal(foe, DamageInfo.make(5.0, a, "bullet", foe.global_position)),
			"a plaza player cannot hurt anyone in the warzone")
	await t._end_raid(war)
	await t._end_raid(raid)
