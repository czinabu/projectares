extends RefCounted
## Checks for the safety nets (DESIGN.md section 10, "Safety nets"): salvage
## for crafted gear lost with the body, and the one insured item recalled
## home instead of dropping in the bag. The rules, the profile, the server's
## accounts, a death in a world, and the screen on the fabricator. Called
## from the test runner (`-- --only safety_nets` runs just these).

const SafetyNets := preload("res://core/economy/safety_nets.gd")
const Crafting := preload("res://core/progression/crafting.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const Hud := preload("res://core/ui/hud.gd")


static func run(t: Node) -> void:
	print("Salvage and insurance")
	_salvage_rules(t)
	_insurance_rules(t)
	_profile(t)
	_accounts(t)
	await _in_a_world(t)
	await _at_the_fabricator(t)


static func _salvage_rules(t: Node) -> void:
	var sound := true
	for id in Crafting.ids():
		var parts := SafetyNets.salvage_of(id)
		var recipe: Dictionary = Crafting.RECIPES[id].get("parts", {})
		var total := 0
		for part: String in recipe:
			total += int(recipe[part])
			sound = sound and parts.count(part) <= int(recipe[part])
		sound = sound and parts.size() == maxi(1, roundi(total * SafetyNets.SALVAGE_SHARE)) \
				and Crafting.UPGRADE_DATA not in parts
	t.check(sound, "every crafted item pays back %d%% of its parts, never more of one than it took, and no upgrade data"
			% roundi(SafetyNets.SALVAGE_SHARE * 100.0))
	var mk3 := SafetyNets.salvage_of("jetpack_mk3")
	t.check(mk3.size() == 2 and ItemDB.item_value(mk3[0]) >= ItemDB.item_value("alloy_ingot")
			and ItemDB.item_value(mk3[1]) >= ItemDB.item_value("alloy_ingot"),
			"a lost Mk3 rig hands back its rarest parts first (%s)" % [mk3])
	t.check(SafetyNets.salvage_of("rifle_carbine").is_empty() and SafetyNets.salvage_of("rifle_scrap").is_empty()
			and not SafetyNets.salvages("upgrade_data"), "gear without a recipe pays no salvage")
	t.check(SafetyNets.salvage_all(["jetpack_mk2", "rifle_carbine", "jetpack_mk2"]).size() == 4,
			"each lost crafted item pays its own salvage")


static func _insurance_rules(t: Node) -> void:
	t.check(SafetyNets.insurable("rifle_carbine") and SafetyNets.insurable("jetpack_mk3")
			and SafetyNets.insurable("dmr_longshot"), "slot gear can be insured, crafted or not")
	var refused := true
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "starter") or ItemDB.has_tag(id, "power") or ItemDB.has_tag(id, "artifact") \
				or ItemDB.has_tag(id, "vehicle") or Loadout.slot_of(id) == "":
			refused = refused and not SafetyNets.insurable(id)
	t.check(refused, "the scrap kit, heavy weapons, artifacts, vehicles and loot cannot be insured")
	t.check(SafetyNets.premium("rifle_carbine") == roundi(ItemDB.item_value("rifle_carbine") * SafetyNets.PREMIUM_SHARE),
			"a policy costs a share of the item's value")

	var policy := SafetyNets.fresh()
	var owned := ["rifle_carbine", "dmr_longshot"]
	var paid := SafetyNets.insure(policy, owned, 1000, "rifle_carbine", 100.0)
	t.check(paid.ok and paid.scrip == 1000 - SafetyNets.premium("rifle_carbine") and policy.item == "rifle_carbine",
			"insuring takes the premium and starts the policy")
	t.check(not SafetyNets.insure(policy, owned, 1000, "dmr_longshot", 100.0).ok and policy.item == "rifle_carbine",
			"one policy at a time")
	t.check(not SafetyNets.insure(SafetyNets.fresh(), owned, 10, "dmr_longshot", 100.0).ok
			and not SafetyNets.insure(SafetyNets.fresh(), owned, 9999, "jetpack_mk2", 100.0).ok,
			"no policy without the scrip, or on something you do not own")
	t.check(SafetyNets.covered(policy, ["dmr_longshot"]) == "" and SafetyNets.covered(policy, ["rifle_carbine"]) == "rifle_carbine",
			"a deploy is covered only if it took the insured item")
	t.check(not SafetyNets.claim(policy, "dmr_longshot", 200.0) and policy.item == "rifle_carbine",
			"recalling anything else claims nothing")
	t.check(SafetyNets.claim(policy, "rifle_carbine", 200.0) and policy.item == ""
			and SafetyNets.wait_left(policy, 200.0) == SafetyNets.COOLDOWN, "a claim ends the policy and starts the wait")
	t.check(not SafetyNets.insure(policy, owned, 1000, "dmr_longshot", 300.0).ok
			and SafetyNets.insure(policy, owned, 1000, "dmr_longshot", 200.0 + SafetyNets.COOLDOWN).ok,
			"a new policy waits out the cooldown")
	t.check(SafetyNets.lapse(policy, ["rifle_carbine"]) and policy.item == ""
			and SafetyNets.wait_left(policy, 200.0 + SafetyNets.COOLDOWN) == 0.0,
			"a policy on something no longer owned lapses, with no wait")
	var cleaned := SafetyNets.clean({"item": "plate_light", "ready_at": -5})
	t.check(cleaned.item == "" and cleaned.ready_at == 0.0 and SafetyNets.clean(null) == SafetyNets.fresh(),
			"a saved policy is checked as it loads")


static func _profile(t: Node) -> void:
	Profile.reset()
	Profile.scrip = 1000
	Profile.add_to_stash(["rifle_carbine"])
	t.check(Profile.insure("rifle_carbine").ok and Profile.insurance.item == "rifle_carbine"
			and Profile.scrip == 1000 - SafetyNets.premium("rifle_carbine"), "solo, the profile insures from its stash")
	var copy := Profile.to_dict()
	Profile.insurance = SafetyNets.fresh()
	Profile.load_dict(copy)
	t.check(Profile.insurance.item == "rifle_carbine", "a policy survives a save")
	Profile.equip("primary", "rifle_carbine")
	var kit := Profile.checkout_loadout(Worlds.get_world("ashfront"))
	t.check(Profile.insured_in(kit) == "rifle_carbine", "a deploy with the insured item is covered")
	Raid.apply_result({"outcome": "died", "brought_home": ["rifle_carbine"], "recalled": "rifle_carbine",
			"salvage": ["power_cell"]})
	t.check("rifle_carbine" in Profile.stash and "power_cell" in Profile.stash and Profile.insurance.item == ""
			and Profile.insurance.ready_at > 0.0, "solo, a death sends the recalled item and the salvage home and spends the policy")
	Profile.reset()


static func _accounts(t: Node) -> void:
	var service := Accounts.new()
	service.persist = false
	service.time_override = 1000.0
	var id: String = service.sign_in("Insured", "a-long-enough-secret-for-tests").account_id
	t.check(SafetyNets.clean(service.snapshot(id).insurance) == SafetyNets.fresh(), "a new account holds no policy")
	var account: Accounts.Account = service.load_account(id)
	account.add_items(["rifle_carbine", "jetpack_mk2"])
	account.scrip = 1000
	t.check(not service.insure(id, "insure", "dmr_longshot").ok, "the server refuses to insure what you do not own")
	t.check(service.insure(id, "insure", "rifle_carbine").ok
			and service.snapshot(id).insurance.item == "rifle_carbine"
			and service.scrip_of(id) == 1000 - SafetyNets.premium("rifle_carbine"),
			"the server insures an item and takes the premium")
	service.equip(id, "primary", "rifle_carbine")
	service.equip(id, "rig", "jetpack_mk2")
	var world := Worlds.get_world("ashfront")
	var deployed: Dictionary = service.deploy(id, world)
	t.check(deployed.ok and deployed.insured == "rifle_carbine", "the deploy names the insured item for the raid")
	t.check(not service.insure(id, "cancel").ok and service.snapshot(id).insurance.item == "rifle_carbine",
			"nothing changes on a policy while you are out in a world")
	service.settle(id, {"outcome": "died", "brought_home": ["rifle_carbine"], "recalled": "rifle_carbine",
			"salvaged": ["jetpack_mk2"], "salvage": SafetyNets.salvage_of("jetpack_mk2")})
	var snap: Dictionary = service.snapshot(id)
	t.check("rifle_carbine" in snap.stash and "jetpack_mk2" not in snap.stash
			and snap.stash.count("power_cell") + snap.stash.count("cryo_core") + snap.stash.count("alloy_ingot") == 2,
			"settling a death brings the insured item home and pays the lost rig's salvage")
	t.check(snap.insurance.item == "" and float(snap.insurance.ready_at) == 1000.0 + SafetyNets.COOLDOWN,
			"the claim spends the policy and starts the wait on the account")
	t.check(not service.insure(id, "insure", "rifle_carbine").ok, "the account waits out the cooldown")
	service.time_override = 1000.0 + SafetyNets.COOLDOWN
	t.check(service.insure(id, "insure", "rifle_carbine").ok, "then insures again")
	var saved := service.load_account(id).to_dict()
	var loaded := Accounts.Account.new()
	loaded.load_dict(saved)
	t.check(loaded.insurance.item == "rifle_carbine", "an account's policy survives a save")
	t.check(service.insure(id, "cancel").ok and service.snapshot(id).insurance.item == "", "a policy can be cancelled")
	# Sold: the policy lapses.
	var again: Dictionary = service.insure(id, "insure", "rifle_carbine")
	service.unequip(id, "primary")
	# Every copy: a new account's welcome gear has one too.
	var sold: Dictionary = service.sell(id, "rifle_carbine", 9)
	t.check(again.ok and sold.ok and service.snapshot(id).insurance.item == "",
			"selling the insured item ends the policy")


static func _in_a_world(t: Node) -> void:
	Profile.reset()
	# The bag path: Ashfront's scrip piles are checked in scrip_pile_tests.gd
	# (there the insured item is recalled before the pile is counted).
	var ashfront := Worlds.get_world("ashfront")
	ashfront.death_drops_scrip = false
	await _in_a_bag_world(t)
	ashfront.death_drops_scrip = true


static func _in_a_bag_world(t: Node) -> void:
	var kit: Array[String] = ["rifle_carbine", "jetpack_mk2", "blade_scrap"]
	var raid := Raid.new()
	raid.apply_to_profile = false
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 81, kit, {}, "", 0, "", "rifle_carbine")
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(30)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	# Something crafted picked up in the world is loot, not salvage.
	raid.player.inventory.add_item("dmr_longshot")
	raid.player.kill("test")
	await t.frames(2)
	var bag: LootContainer = null
	for child in raid.get_children():
		if child is LootContainer and (child as LootContainer).is_bag:
			bag = child
	t.check(bag != null and "rifle_carbine" not in bag.items and "jetpack_mk2" in bag.items and "dmr_longshot" in bag.items,
			"the insured item is recalled from the body; the rest drops in the bag for the killer")
	var r: Dictionary = results[0] if not results.is_empty() else {}
	t.check(r.get("recalled", "") == "rifle_carbine" and "rifle_carbine" in r.get("brought_home", [])
			and "rifle_carbine" not in r.get("lost", []), "the result sends the recalled item home")
	t.check(r.get("salvaged", []) == ["jetpack_mk2"] and r.get("salvage", []) == SafetyNets.salvage_of("jetpack_mk2"),
			"the crafted rig lost with the body pays salvage; the looted DMR does not")
	t.check("Insured, recalled home: " in Hud.death_text(r, 0.0) and "Salvaged: " in Hud.death_text(r, 0.0),
			"the death report on the watch says what came home")
	raid.queue_free()
	await t.frames(2)

	# Signing out claims nothing and salvages nothing.
	raid = Raid.new()
	raid.apply_to_profile = false
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 82, kit, {}, "", 0, "", "rifle_carbine")
	await t.frames(5)
	results.clear()
	raid.player_finished.connect(func(_a: Actor, r2: Dictionary) -> void: results.append(r2))
	raid._leave(raid.state_for(raid.player))
	t.check(results.size() == 1 and results[0].recalled == "" and results[0].salvaged.is_empty(),
			"signing out spends no policy and pays no salvage")
	raid.queue_free()
	await t.frames(2)

	# An item not in the kit is never recalled, whatever the policy says.
	raid = Raid.new()
	raid.apply_to_profile = false
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 83, kit, {}, "", 0, "", "dmr_longshot")
	await t.frames(5)
	results.clear()
	raid.player_finished.connect(func(_a: Actor, r3: Dictionary) -> void: results.append(r3))
	raid.player.inventory.add_item("dmr_longshot")
	raid.player.kill("test")
	await t.frames(2)
	t.check(results.size() == 1 and results[0].recalled == "", "a looted copy of the insured item is not recalled")
	raid.queue_free()
	await t.frames(2)


static func _at_the_fabricator(t: Node) -> void:
	Profile.reset()
	Profile.welcome_granted = true
	Profile.scrip = 1000
	Profile.add_to_stash(["rifle_carbine"])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	var base: HomeBase = main.base
	var console := base.station(HomeBase.CRAFT_ID)
	console.interact(base.player)
	await t.frames(2)
	var hub: Hub = main.hub
	t.check(hub.visible and hub._sections["insure"].visible and hub._sections["craft"].visible,
			"the fabricator's screen offers insurance beside the crafting")
	var row: Node = hub._insure._rows.get_node_or_null("Insure_rifle_carbine")
	t.check(row != null and not row.get_node("Insure").disabled, "an item you own is offered with its premium")
	row.get_node("Insure").pressed.emit()
	await t.frames(3)
	t.check(Profile.insurance.item == "rifle_carbine" and "insured" in hub._insure._message.text
			and "Insured: " in hub._insure._policy.text, "insuring there starts the policy and says so")
	hub.close()
	main.queue_free()
	await t.frames(2)
	Profile.reset()
