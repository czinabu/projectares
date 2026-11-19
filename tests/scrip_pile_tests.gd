extends RefCounted
## Checks for scrip piles and the back room (DESIGN.md "Scrip piles", Caleb's
## call for Ashfront): a death drops no gear but a pile of scrip worth it and
## one bonus item from the pack, a bounty lies in the pile, a bot's pile grows
## with the war, visors mark piles near you, and the plaza's back room sells
## two Rare pieces a day at a markup. Called from the test runner
## (`-- --only ScripPileTests` runs just these).

const Economy := preload("res://core/economy/economy.gd")
const ShopDB := preload("res://core/economy/shop_db.gd")


static func run(t: Node) -> void:
	print("Scrip piles and the back room")
	_back_room(t)
	await _player_pile(t)
	await _bonus_and_bots(t)
	await _artifacts(t)
	await _visor_marks(t)


static func _back_room(t: Node) -> void:
	var pool := Economy.black_market_pool()
	var sound := not pool.is_empty()
	for id in pool:
		sound = sound and ItemDB.item_rarity(id) == ItemDB.Rarity.RARE and not ItemDB.has_tag(id, "power") \
				and not ItemDB.has_tag(id, "artifact") and not ItemDB.has_tag(id, "vehicle") \
				and not Economy.is_trade_good(id) and int(ItemDB.item_stats(id).get("tier", 1)) == 1
	t.check(sound, "the back room deals only in Rare gear: no heavy weapons, artifacts, vehicles, loot or crafted Mk2+ (%d pieces)"
			% pool.size())
	var day := 20500
	var today := Economy.black_market_stock(day)
	t.check(today.size() == Economy.BLACK_MARKET_PICKS and today[0] != today[1]
			and Economy.black_market_stock(day) == today, "it stocks %d different pieces a day, the same all day"
			% Economy.BLACK_MARKET_PICKS)
	var changes := false
	for d in range(day + 1, day + 8):
		changes = changes or Economy.black_market_stock(d) != today
	t.check(changes, "and different pieces on other days")
	var piece: String = Economy.stock(Economy.BLACK_MARKET)[0] if not Economy.stock(Economy.BLACK_MARKET).is_empty() else ""
	t.check(piece != "" and Economy.for_sale(Economy.BLACK_MARKET, piece) and not Economy.for_sale("armory", piece)
			and Economy.price_in(Economy.BLACK_MARKET, piece) == int(ceil(ItemDB.item_value(piece) * Economy.BLACK_MARKET_MARKUP))
			and Economy.sell_price(piece) < Economy.price_in(Economy.BLACK_MARKET, piece),
			"today's piece is for sale only there, at a markup, and sells back for less")
	var stash: Array[String] = []
	var poor := Economy.buy(stash, 100, Economy.BLACK_MARKET, piece)
	var rich := Economy.buy(stash, 99999, Economy.BLACK_MARKET, piece)
	t.check(not poor.ok and rich.ok and rich.spent == Economy.price_in(Economy.BLACK_MARKET, piece) and piece in stash,
			"buying there charges the marked-up price")
	t.check(ShopDB.shop(Economy.BLACK_MARKET).get("stall", false) and Economy.price_in("armory", "rifle_carbine")
			== Economy.buy_price("rifle_carbine"), "it is a stall, and every other shop keeps its prices")


static func _start(t: Node, p_seed: int) -> Raid:
	var raid := Raid.new()
	raid.apply_to_profile = false
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), p_seed)
	raid.war.scale = 0.0
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	return raid


static func _piles_near(raid: Raid, at: Vector3) -> Array:
	return raid.piles.filter(func(n: Variant) -> bool:
		return is_instance_valid(n) and (n as Node3D).global_position.distance_to(at) < 2.0)


static func _player_pile(t: Node) -> void:
	t.check(Worlds.get_world("ashfront").death_drops_scrip and not Worlds.get_world("frostline").death_drops_scrip,
			"Ashfront drops scrip piles; Frostline keeps its own death rules")
	var raid := _start(t, 301)
	var kit: Array[String] = ["rifle_carbine", "frame_trooper"]
	var dead := raid.add_player(kit, {}, "Fallen", "acct-fallen", 0, "", "rifle_carbine")
	var taker := raid.add_player([], {}, "Taker", "acct-taker", 0)
	await t.frames(2)
	dead.global_position = Vector3(-150, 0, -150)
	taker.global_position = Vector3(-150, 0, -120)
	dead.set_physics_process(false)
	taker.set_physics_process(false)
	raid.state_for(dead).scrip = 40
	dead.scrip = 40
	dead.inventory.items.assign(["medkit"])
	var worn := dead.gear_items.duplicate()
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var at := dead.global_position
	dead.protected_left = 0.0
	dead.kill("bullet", raid.bots[0])
	await t.frames(2)
	var piles := _piles_near(raid, at)
	var pile: LootContainer = piles[0] if piles.size() == 1 else null
	var worth := 0
	for id in worn:
		if id != "rifle_carbine":
			worth += Economy.sell_price(id)
	t.check(pile != null and pile.items == ["medkit"] and pile.scrip == worth + 40,
			"a dead player drops a scrip pile worth what a trader pays for their gear, plus what they carried, and a bonus from the pack (%s, %d of %d)"
			% [pile.items if pile else [], pile.scrip if pile else -1, worth + 40])
	var bagged := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag and not (n as LootContainer).pile \
				and (n as Node3D).global_position.distance_to(at) < 3.0)
	t.check(bagged.is_empty() and pile != null and not worn.any(func(id: String) -> bool: return id in pile.items),
			"none of their worn gear drops")
	var r: Dictionary = results[0] if not results.is_empty() else {}
	t.check(r.get("recalled", "") == "rifle_carbine" and "rifle_carbine" in r.get("brought_home", [])
			and r.get("scrip_lost", 0) == 40 and "frame_trooper" in r.get("lost", []),
			"the insured gun still goes home and isn't counted in the pile; the rest is lost")
	if pile == null:
		raid.queue_free()
		await t.frames(2)
		return
	t.check(pile.get_prompt().begins_with("[F] Take Medkit"), "the pile offers its bonus item")
	var before := taker.scrip
	raid._tick_piles()
	t.check(taker.scrip == before and is_instance_valid(pile), "nobody grabs a pile from a distance")
	taker.global_position = pile.global_position + Vector3(0.5, 0, 0.3)
	raid._tick_piles()
	await t.frames(2)
	t.check(taker.scrip == before + worth + 40 and "medkit" in taker.inventory.items,
			"running over the pile takes its scrip and the bonus item")
	t.check(not is_instance_valid(pile) or pile.is_queued_for_deletion(), "and the emptied pile goes")
	raid.queue_free()
	await t.frames(2)


static func _bonus_and_bots(t: Node) -> void:
	var raid := _start(t, 302)
	var kit: Array[String] = ["rifle_carbine"]
	var who := raid.add_player(kit, {}, "Packer", "acct-packer", 0)
	await t.frames(2)
	var state := raid.state_for(who)
	who.inventory.items.assign(["medkit", "dmr_longshot", "rifle_carbine"])
	var drops := who.get_drop_items()
	var dice := RandomNumberGenerator.new()
	dice.seed = 7
	var world := raid.world
	var chance := world.pile_found_chance
	world.pile_found_chance = 0.0
	var small := true
	for i in 20:
		small = small and raid.pile_bonus(who, state, drops, dice) == "medkit"
	world.pile_found_chance = 1.0
	var found := true
	for i in 20:
		found = found and raid.pile_bonus(who, state, drops, dice) == "dmr_longshot"
	world.pile_found_chance = chance
	t.check(small, "the bonus is usually something small from the pack")
	t.check(found, "now and then it is gear found this life, never a spare brought from the stash or worn gear")
	who.inventory.items.assign(["field_dressing", "rifle_carbine"])
	t.check(raid.pile_bonus(who, state, who.get_drop_items(), dice) == "",
			"the free scrap kit and gear brought along are never the bonus")

	# A bot's pile is a share of its pack, more in a hot war.
	var expected := roundi((Economy.sell_price("alloy_ingot") + Economy.sell_price("dmr_longshot")) * world.bot_pile_share)
	var worths: Array[int] = []
	var bonuses: Array = []
	world.pile_found_chance = 0.0
	for heat: float in [0.0, 1.0]:
		var bot: Actor = raid.bots[0]
		bot.inventory.items.assign(["alloy_ingot", "alloy_ingot", "dmr_longshot"])
		var at := bot.global_position
		raid.war.intensity = heat
		bot.kill("bullet", who)
		await t.frames(1)
		var piles := _piles_near(raid, at)
		worths.append((piles[0] as LootContainer).scrip if piles.size() == 1 else -1)
		bonuses.append((piles[0] as LootContainer).items if piles.size() == 1 else [])
	world.pile_found_chance = chance
	t.check(worths[0] == expected and bonuses[0] == ["alloy_ingot"],
			"a bot's pile is a share of what its pack sells for, beside a bonus from it (%d of %d)" % [worths[0], expected])
	t.check(worths[1] > worths[0] and worths[1] <= roundi(expected * (1.0 + world.pile_war_bonus)) + 1,
			"and grows as the war heats up (%d to %d)" % [worths[0], worths[1]])
	raid.queue_free()
	await t.frames(2)


## Caleb's call: a carried artifact drops as itself, attuned or in the pack,
## and is not sold into the pile, so artifacts keep changing hands.
static func _artifacts(t: Node) -> void:
	var raid := _start(t, 304)
	var kit: Array[String] = ["rifle_carbine", "artifact_cloak"]
	var who := raid.add_player(kit, {}, "Keeper", "acct-keeper", 0)
	await t.frames(2)
	who.inventory.items.assign(["artifact_rewind"])
	var at := who.global_position
	var worth := 0
	for id in who.get_drop_items():
		if not ItemDB.has_tag(id, "artifact"):
			worth += Economy.sell_price(id)
	who.protected_left = 0.0
	who.kill("bullet", raid.bots[0])
	await t.frames(2)
	var piles := _piles_near(raid, at)
	var pile: LootContainer = piles[0] if piles.size() == 1 else null
	t.check(pile != null and "artifact_cloak" in pile.items and "artifact_rewind" in pile.items
			and pile.scrip == worth, "carried artifacts drop as themselves beside the pile, not sold into it (%s, %d of %d)"
			% [pile.items if pile else [], pile.scrip if pile else -1, worth])
	raid.queue_free()
	await t.frames(2)


static func _visor_marks(t: Node) -> void:
	var raid := _start(t, 303)
	var viewer := raid.add_player(["helm_spotter"] as Array[String], {}, "Viewer", "acct-viewer", 0)
	await t.frames(2)
	viewer.global_position = Vector3(-120, 0, -120)
	viewer.set_physics_process(false)
	var near := raid.spawn_container([], true, "near", viewer.global_position + Vector3(20, 0, 0), 50, 0)
	var hot := raid.spawn_container([], true, "hot", viewer.global_position + Vector3(0, 0, 30), 300, 250)
	var far := raid.spawn_container([], true, "far", viewer.global_position + Vector3(raid.world.pile_seen_range + 40.0, 0, 0), 50, 0)
	var visor := VisorHud.new()
	visor.raid = raid
	var marks := visor.nearby_piles(viewer)
	t.check(marks.size() == 2 and marks[0] == near and marks[1] == hot and far not in marks,
			"a visor shows the scrip piles near you, nearest first, and none far off")
	var kinds: Array = []
	if viewer.visor != null and viewer.visor.mode != "":
		for mark in visor.compass_marks(viewer):
			kinds.append(mark.kind)
		t.check("pile" in kinds and "bounty" in kinds, "a bounty pile is marked apart from a plain one (%s)" % [kinds])
	visor.free()
	raid.queue_free()
	await t.frames(2)
