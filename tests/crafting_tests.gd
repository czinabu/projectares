extends RefCounted
## Checks for blueprints and crafting (DESIGN.md section 10): the recipes and
## their rules, how a blueprint is learned when it reaches a stash, where an
## account keeps what it knows, where blueprints and upgrade data drop, and
## the fabricator on the home base's gunsmith bench. Called from the test
## runner (`-- --only crafting` runs just these).

const Crafting := preload("res://core/progression/crafting.gd")
const Economy := preload("res://core/economy/economy.gd")
const StashRules := preload("res://core/account/stash_rules.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")


static func run(t: Node) -> void:
	print("Blueprints and crafting")
	_recipes(t)
	_rules(t)
	_accounts(t)
	_drops(t)
	await _at_the_bench(t)


## Everything a Mk2 jetpack takes, and `extra` on top.
static func _jetpack_parts(extra: Array = []) -> Array[String]:
	var out: Array[String] = ["upgrade_data", "upgrade_data", "upgrade_data", "power_cell", "power_cell",
			"alloy_ingot"]
	for id: String in extra:
		out.append(id)
	return out


## The catalog is sound: every recipe makes a real item from a real blueprint
## out of real parts.
static func _recipes(t: Node) -> void:
	var sound := true
	for id in Crafting.ids():
		sound = sound and ItemDB.has_item(id) and StashRules.storable(id) \
				and ItemDB.has_tag(Crafting.blueprint_of(id), Crafting.BLUEPRINT_TAG) and Crafting.fee(id) > 0
		for part: String in Crafting.needs(id):
			sound = sound and ItemDB.has_item(part) and StashRules.storable(part) and Crafting.needs(id)[part] > 0
	t.check(sound and Crafting.ids().size() >= 10, "every recipe makes a real item from a real blueprint and real parts (%d)"
			% Crafting.ids().size())
	var used := true
	for print_id in Crafting.blueprints():
		used = used and not Crafting.made_from(print_id).is_empty()
	t.check(used and Crafting.blueprints().size() == 7, "every blueprint makes something (%d blueprints)"
			% Crafting.blueprints().size())
	# The design's minimum: the higher rig tiers, two guns, the mech and the jet.
	var rigs := true
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "flight_rig") and int(ItemDB.item_stats(id).get("tier", 1)) > 1:
			rigs = rigs and Crafting.has_recipe(id) and Crafting.needs(id).has(Crafting.UPGRADE_DATA)
	t.check(rigs, "every rig above Mk1 is crafted, and takes upgrade data")
	t.check(Crafting.needs("jetpack_mk3")[Crafting.UPGRADE_DATA] > Crafting.needs("jetpack_mk2")[Crafting.UPGRADE_DATA]
			and Crafting.fee("jetpack_mk3") > Crafting.fee("jetpack_mk2"), "a Mk3 costs more data and scrip than a Mk2")
	t.check(Crafting.has_recipe("mech_bulwark") and Crafting.has_recipe("jet_kestrel")
			and Crafting.has_recipe("dmr_longshot") and Crafting.has_recipe("shotgun_breacher")
			and not Crafting.needs("dmr_longshot").has(Crafting.UPGRADE_DATA),
			"the mech, the jet and two guns are crafted, the guns at base level with no upgrade data")
	var sold := false
	for id in Crafting.blueprints() + [Crafting.UPGRADE_DATA]:
		sold = sold or Economy.is_shop_item(id) or Loadout.SLOTS.keys().any(func(slot: String) -> bool: return Loadout.fits(slot, id))
	t.check(not sold and Economy.sell_price(Crafting.UPGRADE_DATA) == 0 and Economy.sell_price("bp_jetpack") > 0,
			"no shop sells a blueprint or upgrade data, neither is gear, and upgrade data cannot be sold")


## Learning and crafting, on plain data.
static func _rules(t: Node) -> void:
	var stash: Array[String] = ["medkit", "bp_jetpack", "bp_mech_bulwark", "bp_jetpack"]
	var known: Array[String] = []
	var learned := Crafting.learn(stash, known)
	t.check(learned.size() == 2 and known == ["bp_jetpack", "bp_mech_bulwark"] and stash == ["medkit", "bp_jetpack"],
			"a blueprint that reaches the stash is learned, and a spare copy stays as loot")
	t.check(Crafting.learn(stash, known).is_empty() and stash.size() == 2, "a known blueprint is not learned twice")
	t.check(Crafting.clean(null).is_empty() and Crafting.clean(["bp_mech_bulwark", "medkit", 3, "bp_jetpack", "bp_jetpack"])
			== ["bp_jetpack", "bp_mech_bulwark"], "a saved list keeps real blueprints only, once each")

	var parts := _jetpack_parts(["medkit"])
	var unknown := Crafting.craft(parts, [], 9999, "jetpack_mk2")
	t.check(not unknown.ok and "Blueprint" in unknown.error and parts.size() == 7,
			"nothing is crafted without its blueprint (%s)" % unknown.error)
	var poor := Crafting.craft(parts, known, 399, "jetpack_mk2")
	t.check(not poor.ok and poor.scrip == 399 and parts.size() == 7, "too little scrip crafts nothing")
	var short: Array[String] = ["upgrade_data", "power_cell", "power_cell", "alloy_ingot"]
	var missing := Crafting.craft(short, known, 9999, "jetpack_mk2")
	t.check(not missing.ok and "2 more Upgrade Data" in missing.error and short.size() == 4,
			"a missing part is named and nothing is taken (%s)" % missing.error)
	var made := Crafting.craft(parts, known, 1000, "jetpack_mk2")
	t.check(made.ok and made.scrip == 600 and made.spent == 400 and parts == ["medkit", "jetpack_mk2"]
			and known.size() == 2, "a craft takes the parts, the data and the fee, and the blueprint stays")
	t.check(not Crafting.craft(parts, known, 9999, "jetpack_mk2").ok and not Crafting.craft(parts, known, 9999, "medkit").ok,
			"a second one needs its parts again, and what has no recipe cannot be crafted")
	var garage: Array[String] = ["reactor_core", "alloy_ingot", "alloy_ingot", "alloy_ingot", "power_cell", "power_cell"]
	var mech := Crafting.craft(garage, known, 2000, "mech_bulwark")
	t.check(mech.ok and mech.scrip == 0 and garage == ["mech_bulwark"] and Loadout.fits("vehicle", "mech_bulwark"),
			"the mech is built from its blueprint and parts, and parks like any vehicle")


## Where it lives: the local profile solo, the server's account online.
static func _accounts(t: Node) -> void:
	Profile.reset()
	Profile.scrip = 1000
	Profile.add_to_stash(_jetpack_parts(["bp_jetpack"]))
	t.check(Profile.blueprints == ["bp_jetpack"] and "bp_jetpack" not in Profile.stash,
			"solo, a blueprint brought home is learned by the profile")
	var made: Dictionary = Profile.craft("jetpack_mk2")
	t.check(made.ok and Profile.scrip == 600 and Profile.stash == ["jetpack_mk2"] and Profile.equip("rig", "jetpack_mk2"),
			"solo, the profile crafts into its stash and the result equips")
	var again: Dictionary = Profile.craft("jetpack_mk2")
	t.check(not again.ok and Profile.scrip == 600 and Profile.stash.size() == 1, "a refused craft changes nothing")
	# A crafted rig is at stake like any gear; the blueprint is not.
	var kit := Profile.checkout_loadout(Worlds.raid_worlds()[0])
	t.check("jetpack_mk2" in kit and "jetpack_mk2" not in Profile.stash and Profile.blueprints == ["bp_jetpack"],
			"a crafted rig leaves the stash when deployed, and the blueprint stays home")
	Profile.reset()
	t.check(Profile.blueprints.is_empty(), "a fresh profile knows no blueprints")

	var service := Accounts.new()
	service.persist = false
	var id: String = service.sign_in("Crafter", "a-long-enough-secret-for-tests").account_id
	t.check(service.snapshot(id).blueprints == [], "a new account knows no blueprints")
	t.check(not service.craft(id, "jetpack_mk2").ok and not service.craft("nobody", "jetpack_mk2").ok,
			"the server refuses a craft without the blueprint, and unknown accounts")
	var world: WorldDef = Worlds.raid_worlds()[0]
	service.deploy(id, world)
	service.bank(id, ["bp_wings_glide", "upgrade_data"])
	t.check(service.snapshot(id).blueprints == ["bp_wings_glide"] and "upgrade_data" in service.snapshot(id).stash,
			"a blueprint banked at a depot is learned at once, and banked upgrade data is kept")
	t.check(not service.craft(id, "wings_glide_mk2").ok, "nothing is crafted while you are out in a world")
	service.settle(id, {"outcome": "left", "brought_home": _jetpack_parts(["bp_jetpack", "bp_jetpack"])})
	var snap: Dictionary = service.snapshot(id)
	t.check(snap.blueprints == ["bp_jetpack", "bp_wings_glide"] and snap.stash.count("bp_jetpack") == 1,
			"a blueprint carried out alive is learned, and a spare copy is loot")
	var before: int = service.scrip_of(id)
	var crafted: Dictionary = service.craft(id, "jetpack_mk2")
	snap = service.snapshot(id)
	t.check(crafted.ok and service.scrip_of(id) == before - 400 and "jetpack_mk2" in snap.stash
			and "power_cell" not in snap.stash and snap.stash.count("upgrade_data") == 1,
			"online, the server crafts into the account's stash and takes the parts and the fee")
	service.deploy(id, world)
	service.settle(id, {"outcome": "died", "brought_home": []})
	t.check(service.snapshot(id).blueprints.size() == 2, "dying never loses a blueprint")
	var account: Accounts.Account = service.load_account(id)
	var saved := account.to_dict()
	var loaded := Accounts.Account.new()
	loaded.load_dict(saved)
	t.check(loaded.blueprints == ["bp_jetpack", "bp_wings_glide"], "an account's blueprints survive a save")
	saved.erase("blueprints")
	loaded.load_dict(saved)
	t.check(loaded.blueprints == ["bp_jetpack"] and "bp_jetpack" not in loaded.stash,
			"a save from before blueprints existed learns the ones in its stash")
	# DEV MODE knows every blueprint, so the mech and jet can be built there.
	var dev: Array[String] = []
	t.check(DevMode.top_up_blueprints(dev) and dev == Crafting.blueprints() and not DevMode.top_up_blueprints(dev),
			"dev mode knows every blueprint")


## Where blueprints and upgrade data come from: the PvP world only.
static func _drops(t: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pvp: WorldDef = null
	var gentle := true
	for world: WorldDef in Worlds.raid_worlds():
		var hands_out := world.warlord_blueprint_chance > 0.0 or world.pod_blueprint_chance > 0.0 \
				or world.warlord_upgrade_data > 0 or world.pod_upgrade_data > 0
		if world.keep_gear_on_death:
			gentle = gentle and not hands_out
			var found := false
			for i in 300:
				for source: String in ["cache", "rooftop", "bot"]:
					for id in world.roll_loot(source, rng):
						found = found or ItemDB.has_tag(id, "blueprint") or id == Crafting.UPGRADE_DATA
			gentle = gentle and not found
		elif hands_out:
			pvp = world
	t.check(pvp != null and gentle, "blueprints and upgrade data come from the full-loot world, never a gentle one")
	if pvp == null:
		return
	var prints := {}
	var data := 0
	for i in 2000:
		for id in pvp.roll_loot("rooftop", rng):
			if ItemDB.has_tag(id, "blueprint"):
				prints[id] = true
			elif id == Crafting.UPGRADE_DATA:
				data += 1
	t.check(prints.size() == 5 and data > 0 and not prints.has("bp_mech_bulwark") and not prints.has("bp_jet_kestrel"),
			"rooftops hold rig and gun blueprints and upgrade data, never a vehicle blueprint (%d kinds)" % prints.size())
	var from_events := {}
	for i in 400:
		for id in pvp.roll_crafting_loot(rng, 1.0, 2):
			from_events[id] = from_events.get(id, 0) + 1
	t.check(from_events.has("bp_mech_bulwark") and from_events.has("bp_jet_kestrel")
			and from_events.get(Crafting.UPGRADE_DATA, 0) == 800,
			"a warlord or a supply pod can carry any blueprint, the mech's and the jet's included, with upgrade data")
	t.check(pvp.roll_crafting_loot(rng, 0.0, 0).is_empty(), "a world with the chances at zero hands out nothing")


## The whole path solo: the fabricator on the bench, crafting from the profile.
static func _at_the_bench(t: Node) -> void:
	print("The fabricator")
	# In a bare base: it is a thing in the room you walk up to and use.
	var room := HomeBase.new()
	room.show_gear([], {})
	t.add_child(room)
	await t.frames(20)
	var asked := []
	room.station_requested.connect(func(id: String) -> void: asked.append(id))
	var post := room.station(HomeBase.CRAFT_ID)
	t._face_display(room.player, post)
	await t.frames(2)
	t.check(room.player.find_interactable() == post, "the fabricator can be walked up to and looked at")
	await t._use(room.player)
	t.check(asked == [HomeBase.CRAFT_ID], "using it asks for the craft screen")
	room.read_only = true
	t.check("not yours" in post.get_prompt(), "a visitor cannot use someone else's fabricator")
	room.queue_free()
	await t.frames(2)

	Profile.reset()
	Profile.welcome_granted = true
	Profile.scrip = 1000
	Profile.add_to_stash(_jetpack_parts(["bp_jetpack"]))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	var base: HomeBase = main.base
	var console := base.station(HomeBase.CRAFT_ID)
	t.check(console != null and console.screen != null and console.get_prompt().begins_with("[F] Fabricator"),
			"the starter bunker's bench has a fabricator")
	var bench := base.bench_transform()
	var beside := bench.affine_inverse() * console.position
	t.check(base.in_workshop(console.position) and absf(beside.x) > 1.2 and beside.distance_to(Vector3.ZERO) < 3.0,
			"it stands beside the bench in the workshop, out of the rack's way")
	console.interact(base.player)
	await t.frames(2)
	var hub: Hub = main.hub
	t.check(hub.visible and hub.station == "craft" and hub._sections["craft"].visible and not hub._sections["shop"].visible
			and hub._title.text == "FABRICATOR" and main.station_screen != null
			and main.station_screen.get_parent() == console.screen,
			"using it opens the craft screen on the console itself")
	var panel := hub._craft
	var row: Node = hub._craft._rows.get_node_or_null("Recipe_jetpack_mk2")
	var locked: Node = hub._craft._rows.get_node_or_null("Recipe_mech_bulwark")
	t.check(row != null and not row.get_node("Craft").disabled and locked != null and locked.get_node("Craft").disabled
			and "3 Upgrade Data (have 3)" in panel.cost_text("jetpack_mk2"),
			"a recipe you can make is offered with its cost; one without its blueprint is listed but locked")
	row.get_node("Craft").pressed.emit()
	await t.frames(3)
	t.check(Profile.stash == ["jetpack_mk2"] and Profile.scrip == 600 and "Crafted" in panel._message.text,
			"crafting takes the parts and the fee and puts the rig in the stash")
	t.check(base.display_for("jetpack_mk2") == null, "the room waits for you to step away")
	hub.close()
	await t.frames(3)
	t.check(base.display_for("jetpack_mk2") != null and base.scrip == 600,
			"stepping away shows the new rig on its stand, and the room's prices know your scrip")
	base.show_gear(Profile.stash, Profile.loadout, ["armory_alcove"])
	await t.frames(3)
	var moved := base.station(HomeBase.CRAFT_ID)
	t.check(moved != null and moved != console and base.in_armory(base.to_local(moved.global_position))
			and base.stations.count(moved) == 1, "the fabricator stays beside the bench when the alcove opens")
	main.queue_free()
	await t.frames(2)
	Profile.reset()
