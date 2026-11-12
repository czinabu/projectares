extends RefCounted
## Checks for credits and the hub shops. Kept in its own file and called from
## the test runner (`-- --only economy` runs just these).

const Economy := preload("res://core/economy/economy.gd")
const ShopDB := preload("res://core/economy/shop_db.gd")
const ShopPanel := preload("res://core/economy/shop_panel.gd")
const StashService := preload("res://core/account/stash_service.gd")
const StashRules := preload("res://core/account/stash_rules.gd")


static func run(t: Node) -> void:
	_rules(t)
	_solo_profile(t)
	_service(t)
	await _hub(t)
	await _online(t)


static func _rules(t: Node) -> void:
	print("Economy: prices and shop stock")
	t.check(Economy.sell_price("scrap_metal") == ItemDB.item_value("scrap_metal")
			and Economy.sell_price("lattice_shard") == 2500, "loot sells for its full value")
	t.check(Economy.sell_price("rifle_carbine") == 180 and Economy.sell_price("dmr_longshot") == 360,
			"gear sells back for 40% of its value")
	t.check(Economy.sell_price("rifle_scrap") == 0 and Economy.sell_price("no_such_item") == 0,
			"the free scrap kit and unknown items cannot be sold")
	var every: Array[String] = []
	var loop_free := true
	var base_only := true
	for shop_id in ShopDB.ids():
		var stock := Economy.stock(shop_id)
		t.check(not stock.is_empty(), "the %s has stock" % ShopDB.shop_name(shop_id))
		for id in stock:
			every.append(id)
			loop_free = loop_free and Economy.sell_price(id) < Economy.buy_price(id)
			base_only = base_only and ItemDB.item_rarity(id) <= ItemDB.Rarity.UNCOMMON and not ItemDB.has_tag(id, "starter")
	t.check(loop_free, "nothing can be bought and sold back at a profit")
	t.check(base_only, "shops only stock base-level gear")
	t.check("rifle_carbine" in Economy.stock("armory") and "frame_trooper" in Economy.stock("outfitter")
			and "bike_scrapper" in Economy.stock("garage") and "furn_weapon_rack" in Economy.stock("furnisher"),
			"weapons, armor, vehicles and furniture each have their shop")
	t.check(not Economy.for_sale("armory", "frame_trooper") and not Economy.for_sale("nowhere", "rifle_carbine"),
			"a shop only sells its own kind of goods")
	for id: String in ["dmr_longshot", "blade_arc", "bike_raider", "frame_bulwark", "jetpack_mk2", "chip_blink",
			"lattice_shard", "reactor_core"]:
		t.check(id not in every, "%s is loot-only" % ItemDB.item_name(id))
	# Even a rare item wrongly tagged for vendors stays out of the shops.
	ItemDB.register("test_rare_vendor", "Mistagged Rare", ItemDB.Rarity.RARE, 100, ["weapon", "firearm", "vendor"])
	t.check(not Economy.for_sale("armory", "test_rare_vendor"), "a rare item is never for sale, whatever its tags")
	ItemDB._items.erase("test_rare_vendor")
	var furniture := Economy.stock("furnisher")
	var described := true
	var has_decor := false
	for id in furniture:
		var stats := ItemDB.item_stats(id)
		described = described and ItemDB.has_tag(id, "furniture") and stats.get("footprint") is Vector3 and stats.get("color") is Color
		has_decor = has_decor or ItemDB.has_tag(id, "decor")
	t.check(described and has_decor, "furniture and decorations carry a footprint and a color")
	var clothes := Economy.stock("tailor")
	t.check(not clothes.is_empty() and clothes.all(func(id: String) -> bool:
		return ItemDB.has_tag(id, "cosmetic") and not ItemDB.item_stats(id).get("outfits", []).is_empty()),
			"the tailor's clothing each names the outfits it unlocks")
	t.check(Economy.unlocked_outfits(["outfit_punk", "rifle_carbine", "outfit_punk", "outfit_suit"]) == (["m_Punk", "f_Punk", "m_Suit", "f_Suit"] as Array[String])
			and Economy.unlocked_outfits(["rifle_carbine"]).is_empty(), "owned clothing unlocks its outfits, and nothing else does")
	var home_goods := furniture + clothes
	for slot: String in Loadout.SLOTS:
		t.check(not home_goods.any(func(id: String) -> bool: return ItemDB.has_tag(id, Loadout.SLOTS[slot])),
				"furniture and clothing never fit the %s slot" % slot)
	var kit := StashRules.checkout(home_goods.duplicate(), {}, Worlds.get_world("ashfront"))
	t.check(not kit.any(func(id: String) -> bool: return id in home_goods), "furniture and clothing are never taken on a raid")

	print("Economy: buying and selling")
	var stash: Array[String] = ["scrap_metal", "scrap_metal", "power_cell", "rifle_carbine", "rifle_carbine"]
	var loadout := {"primary": "rifle_carbine"}
	var poor := Economy.buy(stash, 100, "armory", "rifle_carbine")
	t.check(not poor.ok and poor.credits == 100 and stash.size() == 5, "you cannot buy what you cannot afford")
	var bought := Economy.buy(stash, 1000, "armory", "smg_stinger")
	t.check(bought.ok and bought.credits == 580 and "smg_stinger" in stash, "buying takes the price and adds the item")
	t.check(not Economy.buy(stash, 99999, "armory", "dmr_longshot").ok and "dmr_longshot" not in stash,
			"loot-only gear cannot be bought at any price")
	t.check(not Economy.buy(stash, 99999, "armory", "rifle_scrap").ok, "the free scrap kit cannot be bought")
	var one := Economy.sell(stash, loadout, 0, "rifle_carbine", 1)
	t.check(one.ok and one.credits == 180 and stash.count("rifle_carbine") == 1 and loadout.get("primary") == "rifle_carbine",
			"selling a spare keeps the one you have equipped")
	var last := Economy.sell(stash, loadout, 0, "rifle_carbine", 5)
	t.check(last.ok and last.sold == 1 and last.credits == 180 and loadout.is_empty(),
			"selling more than you own sells what is there, and the slot empties")
	t.check(not Economy.sell(stash, loadout, 0, "rifle_carbine", 1).ok and not Economy.sell(stash, loadout, 0, "dmr_longshot", 1).ok,
			"you cannot sell what you do not have")
	t.check(Economy.loot_value(stash) == 160, "the stash's loot is valued at its sale price")
	var all := Economy.sell_loot(stash, 10)
	t.check(all.ok and all.sold == 3 and all.credits == 170 and stash == (["smg_stinger"] as Array[String]),
			"selling all loot leaves gear alone")
	t.check(not Economy.sell_loot(stash, 10).ok, "selling all loot with none says so")
	t.check(Economy.add(Economy.MAX_CREDITS, 500) == Economy.MAX_CREDITS and Economy.add(10, -50) == 0,
			"a balance stays between zero and the cap")

	print("Economy: what a run pays")
	t.check(Economy.payout({"outcome": "left", "scrip": 60}) == 60, "scrip carried out alive becomes credits")
	t.check(Economy.payout({"outcome": "left", "scrip": 60, "scrip_banked": 40}) == 100, "banked scrip pays as well")
	t.check(Economy.payout({"outcome": "died", "scrip": 60, "scrip_banked": 40}) == 40, "dying pays only what was banked")
	t.check(Economy.payout({"outcome": "left", "kills": 9}) == 0 and Economy.payout({}) == 0
			and Economy.payout({"outcome": "left", "scrip": -5, "scrip_banked": -5}) == 0, "no scrip, no pay")
	t.check(5 * Economy.KILL_BOUNTY < Economy.buy_price(Economy.stock("armory")[0]),
			"five kills with a free kit do not pay for the cheapest weapon")
	t.check(Economy.read_saved({}) == Economy.STARTING_CREDITS and Economy.read_saved({"credits": -40}) == 0
			and Economy.read_saved({"credits": "lots"}) == Economy.STARTING_CREDITS and Economy.read_saved({"credits": 75.0}) == 75,
			"saved balances are read safely, and old saves get the starting credits")


static func _solo_profile(t: Node) -> void:
	print("Economy: the solo profile")
	var saved := [Profile.stash.duplicate(), Profile.loadout.duplicate(), Profile.credits, Profile.kills,
			Profile.raids_played, Profile.raids_extracted]
	Profile.reset()
	t.check(Profile.credits == Economy.STARTING_CREDITS, "a new profile starts with credits")
	t.check(Profile.buy("armory", "rifle_carbine").ok and Profile.credits == 50 and "rifle_carbine" in Profile.stash,
			"the profile buys from a shop")
	t.check(Profile.equip("primary", "rifle_carbine"), "bought gear equips like found gear")
	t.check(not Profile.buy("garage", "bike_scrapper").ok and Profile.credits == 50, "a failed purchase costs nothing")
	Profile.add_to_stash(["alloy_ingot", "circuit_board"])
	t.check(Profile.sell_loot().ok and Profile.credits == 360 and "rifle_carbine" in Profile.stash,
			"selling loot pays into the profile")
	t.check(Profile.sell("rifle_carbine").ok and Profile.credits == 540 and Profile.equipped("primary") == "",
			"selling equipped gear empties its slot")
	Profile.record_raid({"outcome": "left", "kills": 2, "scrip": 40})
	t.check(Profile.credits == 580, "a finished life pays the scrip brought home")
	t.check(Profile.change_credits(-500) and Profile.credits == 80 and not Profile.change_credits(-81) and Profile.credits == 80
			and Profile.change_credits(20) and Profile.credits == 100, "other systems can charge and pay credits, never below zero")
	Profile.stash.assign(saved[0])
	Profile.loadout = saved[1]
	Profile.credits = saved[2]
	Profile.kills = saved[3]
	Profile.raids_played = saved[4]
	Profile.raids_extracted = saved[5]


static func _service(t: Node) -> void:
	print("Economy: the server owns the balance")
	var world := Worlds.get_world("ashfront")
	var dir := "user://test_economy_%d" % Time.get_ticks_usec()
	var service := StashService.new()
	service.save_dir = dir
	var secret := StashService.new_secret()
	var id: String = service.sign_in("Coin Tester", secret).account_id
	var snap := service.snapshot(id)
	t.check(snap.credits == Economy.STARTING_CREDITS, "a new account starts with credits, and the snapshot shows them")
	var before: int = snap.stash.size()
	t.check(not service.buy(id, "armory", "dmr_longshot").ok and not service.buy(id, "outfitter", "rifle_carbine").ok
			and service.snapshot(id).credits == Economy.STARTING_CREDITS and service.snapshot(id).stash.size() == before,
			"the server refuses loot-only gear and the wrong shop")
	t.check(service.buy(id, "furnisher", "furn_bunk").ok and service.snapshot(id).credits == 350
			and "furn_bunk" in service.snapshot(id).stash, "the server sells furniture into the stash")
	t.check(not service.buy(id, "garage", "bike_scrapper").ok and service.snapshot(id).credits == 350,
			"the server refuses a purchase the account cannot afford")
	t.check(not service.buy("nobody", "armory", "rifle_carbine").ok and not service.sell("nobody", "medkit").ok,
			"unknown accounts cannot trade")
	t.check(service.sell(id, "bike_scrapper").ok and service.snapshot(id).credits == 590
			and "bike_scrapper" not in service.snapshot(id).stash, "the server buys gear back")
	t.check(not service.sell(id, "bike_scrapper").ok and service.snapshot(id).credits == 590,
			"the server will not buy what the account does not have")

	t.check(service.credits_of(id) == 590 and service.credits_of("nobody") == 0, "the server reports a balance")
	t.check(not service.change_credits(id, -591) and service.credits_of(id) == 590 and not service.change_credits("nobody", 5),
			"a charge that would go below zero is refused whole")
	t.check(service.change_credits(id, -90) and service.change_credits(id, 90) and service.credits_of(id) == 590,
			"server code can charge and pay an account")
	t.check(service.buy(id, "tailor", "outfit_scout").ok and service.sell(id, "outfit_scout").ok and service.credits_of(id) == 500
			and service.change_credits(id, 90), "the server sells clothing, and buys it back for less")

	# A fresh service reads the balance from disk.
	var restarted := StashService.new()
	restarted.save_dir = dir
	t.check(restarted.snapshot(id).credits == 590 and "furn_bunk" in restarted.snapshot(id).stash,
			"the balance and purchases survive a server restart")

	# Money is only made by getting loot home.
	restarted.equip(id, "primary", "rifle_carbine")
	restarted.deploy(id, world)
	t.check(not restarted.buy(id, "armory", "smg_stinger").ok and not restarted.sell(id, "furn_bunk").ok,
			"the shops are closed to an account that is out in a raid")
	restarted.settle(id, {"outcome": "died", "brought_home": [], "kills": 4, "scrip": 500, "scrip_banked": 20})
	var dead := restarted.snapshot(id)
	t.check(dead.credits == 610 and "rifle_carbine" not in dead.stash,
			"dying loses the gear, keeps the bank, and pays only the scrip that was banked")
	restarted.deploy(id, world)
	restarted.settle(id, {"outcome": "extracted", "brought_home": ["power_cell", "scrap_metal", "dmr_longshot"], "kills": 1, "scrip": 20})
	t.check(restarted.snapshot(id).credits == 630, "getting home pays the scrip carried")
	t.check(restarted.sell(id, "").ok and restarted.snapshot(id).credits == 765
			and "dmr_longshot" in restarted.snapshot(id).stash, "selling all loot keeps found gear")
	t.check(not restarted.sell(id, "").ok, "there is no loot left to sell")

	# A hand-edited or damaged save cannot mint money.
	var path := dir.path_join(id + ".json")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["credits"] = 1e12
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var capped := StashService.new()
	capped.save_dir = dir
	t.check(capped.snapshot(id).credits == Economy.MAX_CREDITS, "a saved balance is capped when it loads")
	t._wipe_dir(dir)


static func _hub(t: Node) -> void:
	print("Economy: the shop screen")
	var saved := [Profile.stash.duplicate(), Profile.loadout.duplicate(), Profile.credits]
	Profile.reset()
	Profile.credits = 1000
	Profile.add_to_stash(["scrap_metal", "scrap_metal", "reactor_core"])
	var hub := Hub.new()
	t.add_child(hub)
	await t.frames(1)
	var shop: ShopPanel = hub._shop
	t.check(shop.tabs() == (["armory", "outfitter", "garage", "furnisher", "tailor", "sell"] as Array[String])
			and shop.current == "armory" and shop.credits() == 1000, "the hub shows every shop and your credits")
	shop.buy("armory", "hammer_breaker")
	t.check(Profile.credits == 500 and "hammer_breaker" in Profile.stash and "hammer_breaker" in hub.options_for("melee"),
			"buying solo pays from the profile and the loadout picker offers the item")
	shop.buy("garage", "bike_scrapper")
	t.check(Profile.credits == 500 and shop._message.visible, "a purchase you cannot afford shows why")
	shop.open_tab("sell")
	t.check(shop.sellable() == (["reactor_core", "hammer_breaker", "scrap_metal"] as Array[String]),
			"the sell tab lists the stash, most valuable first")
	shop.sell("", 1)
	t.check(Profile.credits == 1450 and Profile.stash == (["hammer_breaker"] as Array[String]), "sell all loot sells only loot")
	# Clothing from the Tailor unlocks its outfit in the customizer.
	var look_before: Dictionary = Profile.appearance.duplicate()
	var punk := {"build": "m", "head": "Punk", "body": "Punk", "legs": "Punk", "feet": "Punk"}
	t.check(not hub.character.options_for("body").any(func(o: Array) -> bool: return o[0] == "Punk")
			and Look.clean_appearance(punk, Profile.owned_outfits())["body"] != "Punk",
			"an outfit you do not own is not offered and cannot be worn")
	shop.buy("tailor", "outfit_punk")
	t.check("outfit_punk" in Profile.stash and hub.character.options_for("body").any(func(o: Array) -> bool: return o[0] == "Punk"),
			"buying clothing adds its outfit to the customizer")
	Profile.set_appearance(punk)
	t.check(Profile.appearance["body"] == "Punk" and Look.clean_appearance(punk, Profile.owned_outfits())["body"] == "Punk",
			"owned clothing can be worn")
	t.check(Look.clean_appearance(punk, Economy.unlocked_outfits(["rifle_carbine"]))["body"] != "Punk",
			"a server whose stash lacks the clothing puts starter clothes on instead")
	shop.sell("outfit_punk", 1)
	t.check(Look.clean_appearance(Profile.appearance, Profile.owned_outfits())["body"] != "Punk",
			"selling the clothing takes the outfit off again")
	Profile.appearance = look_before
	shop.shop_filter = "garage"
	shop.refresh()
	t.check(shop.tabs() == (["garage", "sell"] as Array[String]) and shop.current == "sell",
			"a vendor stall can show a single shop")
	shop.shop_filter = ""

	# In a lobby the panel only asks. The server's snapshot is what it shows.
	var service := StashService.new()
	service.persist = false
	var id: String = service.sign_in("Shop Tester", StashService.new_secret()).account_id
	var asked: Array = []
	hub.online_buy_requested.connect(func(shop_id: String, item_id: String) -> void: asked.append([shop_id, item_id]))
	hub.online_sell_requested.connect(func(item_id: String, count: int) -> void: asked.append([item_id, count]))
	hub.enter_lobby(service.snapshot(id), Worlds.get_world("ashfront"))
	var local := [Profile.credits, Profile.stash.duplicate()]
	shop.buy("armory", "smg_stinger")
	shop.sell("medkit", 1)
	t.check(asked == [["armory", "smg_stinger"], ["medkit", 1]] and Profile.credits == local[0] and Profile.stash == local[1],
			"in a lobby, trading asks the server and leaves the local profile alone")
	t.check(shop.credits() == Economy.STARTING_CREDITS, "in a lobby the screen shows the server's balance")
	service.buy(id, "armory", "smg_stinger")
	hub.update_account(service.snapshot(id))
	t.check(shop.credits() == 80 and "smg_stinger" in hub.options_for("primary"), "the hub shows what the server confirmed")
	hub.leave_lobby()
	t.check(shop.credits() == Profile.credits, "leaving the lobby shows the solo balance again")
	hub.refresh({"outcome": "extracted", "loot": [], "loot_value": 0, "kills": 2, "scrip": 40})
	t.check("+40 credits" in hub._result.text, "the result line shows the scrip brought home")
	hub.queue_free()
	await t.frames(2)
	Profile.stash.assign(saved[0])
	Profile.loadout = saved[1]
	Profile.credits = saved[2]


static func _online(t: Node) -> void:
	print("Economy: trading with a real server")
	var local := [Profile.credits, Profile.stash.duplicate()]
	var port := 24841
	var pid: int = t._start_server(port, ["--bots", "0"] as Array[String])
	# A name of its own each run: the test server keeps accounts on disk, and
	# the secret is new every run.
	var shown := "Dana %d" % (Time.get_ticks_usec() % 1000000)
	var dana: NetSession = await t._sign_in(shown, port)
	t.check(dana != null, "a client signs in to the shop server")
	if dana == null:
		OS.kill(pid)
		return
	t.check(dana.account.get("credits", -1) == Economy.STARTING_CREDITS, "the lobby shows the balance the server keeps")
	var errors: Array[String] = []
	dana.lobby_error.connect(func(reason: String) -> void: errors.append(reason))
	dana.buy("armory", "dmr_longshot")
	await t._wait_until(func() -> bool: return errors.size() == 1, 240)
	t.check(errors.size() == 1 and "dmr_longshot" not in dana.account.stash
			and dana.account.credits == Economy.STARTING_CREDITS, "the server refuses to sell loot-only gear")
	dana.buy("armory", "smg_stinger")
	await t._wait_until(func() -> bool: return "smg_stinger" in dana.account.stash, 240)
	t.check("smg_stinger" in dana.account.stash and dana.account.credits == 80, "buying goes through the server")
	dana.buy("armory", "smg_stinger")
	await t._wait_until(func() -> bool: return errors.size() == 2, 240)
	t.check(errors.size() == 2 and dana.account.stash.count("smg_stinger") == 1 and dana.account.credits == 80,
			"the server refuses a purchase the account cannot afford")
	dana.sell("bike_scrapper", 50)
	await t._wait_until(func() -> bool: return "bike_scrapper" not in dana.account.stash, 240)
	t.check("bike_scrapper" not in dana.account.stash and dana.account.credits == 320,
			"selling goes through the server, which counts what is really there")
	dana.equip("primary", "smg_stinger")
	await t._wait_until(func() -> bool: return dana.account.loadout.get("primary", "") == "smg_stinger", 240)
	t.check(dana.account.loadout.get("primary", "") == "smg_stinger", "bought gear equips for the next raid")
	await t._leave(dana)
	await t.frames(20)
	dana = await t._sign_in(shown, port)
	t.check(dana != null and dana.account.credits == 320 and "smg_stinger" in dana.account.stash,
			"the balance is still there after signing back in")
	await t._leave(dana)
	OS.kill(pid)
	t.check(Profile.credits == local[0] and Profile.stash == local[1], "online trading never touches the local profile")
