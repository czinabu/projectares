extends RefCounted
## Checks for home base upgrades: the catalog and its buying rules, where an
## account keeps what it owns, how the base's layout follows them, and the
## sealed bulkheads you buy them at. Called from the test runner
## (`-- --only base_upgrades` runs just these).

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const StashRules := preload("res://core/account/stash_rules.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")
const BasePlan := preload("res://core/base/base_plan.gd")


static func run(t: Node) -> void:
	print("Home base upgrades")
	_rules(t)
	_layout(t)
	_accounts(t)
	await _bunker(t)
	await _buying(t)
	await _from_the_base(t)
	_plan_rules(t)
	await _plan_table(t)
	_design_rules(t)
	await _shapes(t)
	await _styles(t)
	_finish_rules(t)
	await _finishes(t)
	await _customizer(t)


## The catalog, and what may be bought when.
static func _rules(t: Node) -> void:
	var builds := BaseUpgrades.ids().filter(func(id: String) -> bool: return not BaseUpgrades.is_design(id))
	var build_price := 0
	for id: String in builds:
		build_price += BaseUpgrades.price(id)
	t.check(builds.size() == 12 and build_price == 26600,
			"twelve build upgrades cost 26,600 scrip together")
	var designs := BaseUpgrades.ids().filter(func(id: String) -> bool: return BaseUpgrades.is_design(id))
	t.check(Array(designs) == Array(BasePlan.unlocks()) and designs.size() == 19,
			"every other hub shape, room style and finish has one design unlock, and nothing else is a design")
	t.check(BaseUpgrades.blocked(["hub_ring", "hub_spine", "style_ops_bridge", "style_stores_cargo"], "finish") != "",
			"design unlocks never count toward the finish")
	t.check(BaseUpgrades.clean(null).is_empty() and BaseUpgrades.clean("junk").is_empty()
			and BaseUpgrades.clean(["finish", "no_such", "gear_hall", "gear_hall", 7]) == ["gear_hall", "finish"],
			"a saved list keeps known upgrades only, once each, in catalog order")
	var owned: Array[String] = []
	var bought := BaseUpgrades.buy(owned, 5000, "gear_hall")
	t.check(bought.ok and bought.scrip == 4000 and bought.spent == 1000 and owned == ["gear_hall"],
			"buying an upgrade takes its price and adds it to what you own")
	var again := BaseUpgrades.buy(owned, 4000, "gear_hall")
	t.check(not again.ok and again.scrip == 4000 and owned.size() == 1, "an upgrade is bought once")
	var early := BaseUpgrades.buy(owned, 4000, "garage_full")
	t.check(not early.ok and "second bay" in early.error and early.scrip == 4000 and owned.size() == 1,
			"a track's later step needs the one before it (%s)" % early.error)
	var poor := BaseUpgrades.buy(owned, 499, "ops_consoles")
	t.check(not poor.ok and poor.scrip == 499 and owned.size() == 1, "too little scrip buys nothing")
	t.check(not BaseUpgrades.buy(owned, 9999, "no_such").ok, "an unknown upgrade cannot be bought")
	t.check(BaseUpgrades.blocked(owned, "finish") != "" and BaseUpgrades.blocked(
			["gear_hall", "bay_second", "ops_consoles", "trophy_hall"], "finish") == "",
			"the finish needs any four upgrades first")
	# Whatever is behind an upgrade must exist before it is sold.
	var waiting: Array[String] = []
	for id in BaseUpgrades.ids():
		if not BaseUpgrades.is_ready(id):
			waiting.append(id)
	t.check(BaseUpgrades.blocked(["armory_alcove"], "heavy_wall") == ""
			and BaseUpgrades.blocked([], "lounge") == "Not open yet." and waiting == ["lounge"],
			"the heavy weapon wall can be bought once the alcove is open, and a room that is not built stays shut")
	var all: Array[String] = []
	var in_order := true
	for id in BaseUpgrades.full():
		in_order = in_order and BaseUpgrades.buy(all, 99999, id).ok
	t.check(in_order and all == BaseUpgrades.full() and not waiting.any(func(id: String) -> bool: return id in all),
			"every upgrade that is open can be bought, in catalog order")
	var cheap := 0
	for id in BaseUpgrades.full():
		if BaseUpgrades.price(id) <= 1500 and BaseUpgrades.blocked([], id) == "":
			cheap += 1
	t.check(cheap >= 3, "a new player has cheap first steps to choose from (%d)" % cheap)


## The starter bunker's test lane: three plates that drop when hit and pop
## back up, a hit counter, free weapons, and a sealed far end.
static func _test_lane(t: Node, base: HomeBase, p: Actor) -> void:
	t.check(base.lane_targets.size() == 3 and base.lane_size.x <= 3.0 and base.lane_size.z <= 15.0
			and base.lane_targets.all(func(target: HomeBase.RangeTarget) -> bool:
				return base.in_lane(target.home)), "three plates stand in a lane 3 m wide and 15 m long at most")
	var counter_z := -base.range_from() - base.lane_counter
	var metres: Array[int] = []
	for target in base.lane_targets:
		metres.append(int(round(counter_z - target.home.z)))
	t.check(metres == [4, 8, 12] and (base.range_sign.get_node("Name") as Label3D).text == "TEST LANE", "plates at 4, 8 and 12 m from the counter, under a lane sign")
	t.check(not p.weapons_locked, "weapons are free in the lane")
	var plate: HomeBase.RangeTarget = base.lane_targets[0]
	p.global_position = base.to_global(Vector3(plate.home.x, 0.1, counter_z + 1.0))
	p.velocity = Vector3.ZERO
	await t.frames(2)
	var eye := p.global_position + Vector3(0, p.eye_height, 0)
	var dir := (plate.to_global(plate.centre) - eye).normalized()
	p.cmd.yaw = atan2(-dir.x, -dir.z)
	p.cmd.pitch = asin(dir.y)
	p.cmd.aim_dir = dir
	await t.frames(10)
	var gun := p.get_active_weapon() as Gun
	t.check(gun != null and gun.reserve_ammo > 0, "the starter kit's gun is in hand in the lane")
	var shots := base.lane_shots
	p.cmd.primary_pressed = true
	p.cmd.primary = true
	await t.frames(1)
	p.cmd.primary_pressed = false
	p.cmd.primary = false
	await t.frames(3)
	t.check(base.lane_shots == shots + 1 and base.lane_hits == 1 and plate.hits == 1
			and "HITS 1" in base.lane_board.text and plate.rotation.x < -1.0 and plate.collision_layer == 0,
			"a hit on a plate counts on the lane's board and drops it (%s)" % base.lane_board.text.replace("\n", " / "))
	await t.frames(int(base.lane_pop * 60.0) + 30)
	t.check(is_zero_approx(plate.rotation.x) and plate.collision_layer == Actor.LAYER_WORLD,
			"the plate pops back up")
	p.cmd.aim_dir = Vector3.ZERO


## How many spots each display kind has, by what is owned.
static func _layout(t: Node) -> void:
	var full := BaseUpgrades.full()
	var known := true
	var grows := true
	for kind: String in BaseLayout.KINDS:
		var entry: Dictionary = BaseLayout.KINDS[kind]
		for id: String in entry.get("steps", {}):
			known = known and BaseUpgrades.has_upgrade(id)
		grows = grows and BaseLayout.spots(kind, []) == int(entry["starter"]) \
				and BaseLayout.spots(kind, full) == int(entry["spots"]) and int(entry["starter"]) <= int(entry["spots"])
	t.check(known, "every step in the layout names a real upgrade")
	t.check(grows, "each display kind grows from its starter spots to its full spots")
	t.check(BaseLayout.spots("rack_guns") == 4 and BaseLayout.spots("rack_sidearms") == 2
			and BaseLayout.spots("rack_melee") == 2, "the starter rack holds 4 long guns, 2 sidearms and 2 melee")
	t.check(BaseLayout.spots("bay") == 1 and BaseLayout.spots("bay", ["bay_second"]) == 2
			and BaseLayout.spots("bay", ["bay_second", "garage_full"]) == 4, "the garage grows a bay at a time")
	var bikes: Array[String] = ["bike_scrapper", "bike_scrapper", "bike_scrapper"]
	t.check(BaseLayout.plan(bikes, {}).size() == 1 and BaseLayout.stored_away(bikes) == {"bay": 2}
			and BaseLayout.plan(bikes, {}, ["bay_second"]).size() == 2,
			"what does not fit on show is counted as stored, never lost")
	t.check(BaseLayout.plan(["chip_blink"], {}).is_empty() and BaseLayout.plan(["chip_blink"], {}, ["gear_hall"]).size() == 1,
			"ability chips go on show once the gear hall is bought")


## Where the list lives: the local profile solo, the server's account online.
static func _accounts(t: Node) -> void:
	Profile.reset()
	Profile.scrip = 1600
	var first: Dictionary = Profile.buy_upgrade("gear_hall")
	t.check(first.ok and Profile.scrip == 600 and Profile.base_upgrades == ["gear_hall"],
			"solo, the profile keeps the upgrades and pays for them")
	var second: Dictionary = Profile.buy_upgrade("trophy_hall")
	t.check(not second.ok and Profile.scrip == 600 and Profile.base_upgrades == ["gear_hall"],
			"a refused purchase changes nothing")
	Profile.reset()
	t.check(Profile.base_upgrades.is_empty(), "a fresh profile starts in the starter bunker")

	var service := Accounts.new()
	service.persist = false
	var signed: Dictionary = service.sign_in("Upgrader", "a-long-enough-secret-for-tests")
	var id: String = signed.account_id
	t.check(service.snapshot(id).base_upgrades == [], "a new account starts in the starter bunker")
	var paid: Dictionary = service.buy_upgrade(id, "ops_consoles")
	t.check(paid.ok and service.scrip_of(id) == 0 and service.snapshot(id).base_upgrades == ["ops_consoles"],
			"online, the server's account keeps the upgrades and pays for them")
	t.check(not service.buy_upgrade(id, "gear_hall").ok and not service.buy_upgrade(id, "heavy_wall").ok
			and not service.buy_upgrade("nobody", "gear_hall").ok and service.snapshot(id).base_upgrades.size() == 1,
			"the server refuses what the account cannot afford, what is not open and unknown accounts")
	var account: Accounts.Account = service.load_account(id)
	var saved := account.to_dict()
	var loaded := Accounts.Account.new()
	loaded.load_dict(saved)
	t.check(loaded.base_upgrades == ["ops_consoles"], "an account's upgrades survive a save")
	saved.erase("base_upgrades")
	loaded.load_dict(saved)
	t.check(loaded.base_upgrades.is_empty(), "a save from before upgrades existed opens in the starter bunker")
	service.change_scrip(id, 5000)
	service.deploy(id, Worlds.raid_worlds()[0])
	t.check(not service.buy_upgrade(id, "gear_hall").ok, "nothing is bought for the base while you are out in a world")
	service.cancel_deploy(id)
	# DEV MODE keeps a finished base to test in.
	var dev: Array[String] = ["gear_hall"]
	t.check(DevMode.top_up_base(dev) and dev == BaseUpgrades.full() and not DevMode.top_up_base(dev),
			"dev mode keeps the base fully upgraded")


## Everything worth showing, so every display kind has more than fits.
static func _big_stash() -> Array[String]:
	var stash: Array[String] = []
	var want := DevMode.wanted_items()
	for id: String in want:
		stash.append(id)
	stash.append_array(["bike_scrapper", "bike_scrapper", "bike_raider", "lattice_shard", "scrap_metal"])
	return stash


static func _count(base: HomeBase, kind: String) -> int:
	return base.displays.filter(func(d: HomeBase.Display) -> bool: return d.kind == kind).size()


## Caleb could not take his helmet off: helmets had no place in the room. They
## sit on a shelf over the armor stands, the worn one always among them, and
## using it there leaves the head bare.
static func _helmet_shelf(t: Node, stash: Array[String]) -> void:
	print("Home base helmet shelf")
	var owned := stash.duplicate()
	owned.append_array(["helm_warden", "helm_seeker", "helm_ember"])
	t.check(BaseLayout.kind_for("helm_warden") == "helmet_shelf" and BaseLayout.kind_for("visor_scav") == "helmet_shelf",
			"helmets go on the helmet shelf")
	var plan := BaseLayout.plan(StashRules.equippable(owned), {"helmet": "visor_scav"})
	var shelf := plan.filter(func(e: Dictionary) -> bool: return e["kind"] == "helmet_shelf")
	t.check(shelf.size() == BaseLayout.spots("helmet_shelf") and shelf.any(func(e: Dictionary) -> bool:
				return e["id"] == "visor_scav" and e["equipped"]),
			"the helmet worn is on show even when better ones fill the starter shelf")
	var base := HomeBase.new()
	base.show_gear(owned, {"helmet": "visor_scav"})
	t.add_child(base)
	await t.frames(20)
	var worn := base.display_for("visor_scav")
	t.check(worn != null and worn.equipped and base.inside(worn.position) and worn.has_node("Model/HelmetModel"),
			"the worn Scav Visor sits on the shelf as the helmet it is")
	t.check(base.player.visor.enabled and base.player.visor.item_id == "visor_scav", "and you wear it in the room")
	var asked := []
	base.equip_requested.connect(func(slot: String, id: String) -> void: asked.append([slot, id]))
	t._face_display(base.player, worn)
	await t.frames(2)
	t._face_display(base.player, worn)
	t.check(base.player.find_interactable() == worn and worn.get_prompt() == "[F] Take off Scav Visor (equipped)",
			"looking at it from the floor offers to take it off")
	await t._use(base.player)
	t.check(asked == [["helmet", ""]], "using it asks to leave the head bare")
	base.show_gear(owned, {})
	await t.frames(2)
	t.check(not base.player.visor.enabled and not base.displays.any(func(d: HomeBase.Display) -> bool: return d.equipped),
			"with it taken off you stand bareheaded")
	base.queue_free()
	await t.frames(2)


## The base with no upgrades: fewer spots, sealed rooms, shared consoles.
static func _bunker(t: Node) -> void:
	print("Home base starter bunker")
	var stash := _big_stash()
	var base := HomeBase.new()
	base.show_gear(stash, StashRules.starter_loadout())
	t.add_child(base)
	await t.frames(20)
	t.check(base.upgrades.is_empty() and _count(base, "rack_guns") == 4 and _count(base, "rack_sidearms") == 2
			and _count(base, "rack_melee") == 2 and _count(base, "bay") == 1 and _count(base, "armor_stand") == 1
			and _count(base, "rig_stand") == 1 and _count(base, "gunsmith") == 0 and _count(base, "supplies") <= 3
			and _count(base, "chip_case") == 0 and _count(base, "trophy") == 0,
			"a starter bunker shows a short rack, one bay and one stand of each kind")
	await _helmet_shelf(t, stash)
	var armory_frame := base.room_transform("armory").affine_inverse()
	var in_nook := true
	var all_inside := true
	for display in base.displays:
		all_inside = all_inside and base.inside(display.position)
		if BaseLayout.is_armory(display.kind):
			var local := armory_frame * display.position
			in_nook = in_nook and base.in_armory(display.position) and local.z > -base.small_depth
	t.check(in_nook and all_inside, "the starter rack hangs in the armory's small form, in front of its sealed wall")
	t.check(base.in_workshop(base.bench_transform().origin) and base.inside(base.bench_transform().origin)
			and base.in_workshop(base.station(HomeBase.CRAFT_ID).position),
			"the starter bunker's bench and fabricator already stand in the workshop")
	# Walk from the hub into the workshop, and into the armory up to its
	# sealed wall, never past it.
	var p := base.player
	for room: String in ["workshop", "armory"]:
		var door := base.room_transform(room)
		var into := -door.basis.z
		p.global_position = base.to_global(door * Vector3(0, 0.1, 2.0))
		p.velocity = Vector3.ZERO
		p.cmd.yaw = atan2(-into.x, -into.z)
		p.cmd.move = Vector2(0, 1)
		await t.frames(150)
		p.cmd.move = Vector2.ZERO
		await t.frames(2)
		var at := base.to_local(p.global_position)
		var deep := -(door.affine_inverse() * at).z
		if room == "workshop":
			t.check(base.in_workshop(at), "you can walk from the hub into the workshop (%s)" % at)
		else:
			t.check(base.in_armory(at) and deep < base.small_depth,
					"the armory's sealed wall stops you %.1f m in, short of %.1f m" % [deep, base.small_depth])
	var shown: Array[String] = []
	for gate in base.bulkheads:
		shown.append(gate.id)
	shown.sort()
	var expected: Array[String] = ["armory_alcove", "bay_second", "bench_workshop", "finish", "firing_range",
			"garage_full", "gear_hall", "ops_consoles", "trophy_hall"]
	t.check(shown == expected, "every upgrade still to buy is on show in the room (%s)" % [shown])
	var priced := true
	for gate in base.bulkheads:
		var price := gate.get_node("Price") as Label3D
		var title := gate.get_node("Title") as Label3D
		priced = priced and price != null and HomeBase.commas(BaseUpgrades.price(gate.id)) in price.text \
				and title.text == BaseUpgrades.title(gate.id).to_upper() and base.inside(gate.position)
	t.check(priced and HomeBase.commas(1200) == "1,200" and HomeBase.commas(31600) == "31,600" and HomeBase.commas(500) == "500",
			"each one names what is behind it and its price, in the room")
	# The mastery bench and records share a console until the ops consoles.
	t.check(base.station("mastery") == null and base.station("records") == null and base.station("trader") != null
			and base.also_shows("trader") == ["mastery"] and base.also_shows("wardrobe") == ["records"]
			and base.station_title("trader") == "Trader and mastery bench"
			and base.station("trader").get_prompt() == "[F] Trader and mastery bench: Buy and sell, pick mastery variants",
			"the trader's console doubles as the mastery bench, the wardrobe's as the records")
	# The firing range is shut.
	p.global_position = base.to_global(Vector3(0, 0.1, -base.range_from() + 2.0))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.move = Vector2(0, 1)
	await t.frames(60)
	p.cmd.move = Vector2.ZERO
	await t.frames(2)
	var lane_at := base.to_local(p.global_position)
	t.check(base.in_lane(lane_at) and base.bulkhead("firing_range") != null
			and base.bulkhead("firing_range").position.z < lane_at.z,
			"the starter bunker's door leads to a test lane, sealed from the range at its far end")
	await _test_lane(t, base, p)
	# The garage past its small form is walled off.
	var garage := base.room_transform("garage")
	var deeper := -garage.basis.z
	p.global_position = base.to_global(garage * Vector3(0, 0.1, -1.0))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = atan2(-deeper.x, -deeper.z)
	p.cmd.move = Vector2(0, 1)
	await t.frames(120)
	p.cmd.move = Vector2.ZERO
	await t.frames(2)
	var reached := -(garage.affine_inverse() * base.to_local(p.global_position)).z
	t.check(reached < base.small_depth and base.bulkhead("bay_second") != null and base.bulkhead("garage_full") != null,
			"the garage past its small form is closed off (walked %.1f m in)" % reached)
	# With nothing to spend, a bulkhead says why it stays shut.
	var gate := base.bulkhead("gear_hall")
	var asked := []
	base.upgrade_requested.connect(func(id: String) -> void: asked.append(id))
	gate.interact(p)
	gate.interact(p)
	t.check(asked.is_empty() and "Not enough scrip" in gate.get_prompt() and "Not enough scrip" in gate.status.text,
			"without the scrip a bulkhead cannot be bought, and says so")
	t.check(base.bulkhead("lounge") == null, "an upgrade that is not built yet has no panel in the base")
	base.queue_free()
	await t.frames(2)
	# Someone else's bunker: sealed, with nothing for sale.
	var visited := HomeBase.new()
	visited.read_only = true
	visited.owner_name = "Kestrel"
	visited.show_gear(stash, {}, ["gear_hall"])
	t.add_child(visited)
	await t.frames(3)
	visited.upgrade_requested.connect(func(id: String) -> void: asked.append(id))
	var theirs := visited.bulkhead("trophy_hall")
	theirs.interact(visited.player)
	theirs.interact(visited.player)
	t.check(asked.is_empty() and theirs.get_prompt() == "Trophy hall (sealed)" and visited.bulkhead("gear_hall") == null
			and _count(visited, "armor_stand") > 1, "a visitor sees the upgrades its owner has, and can buy nothing")
	visited.queue_free()
	await t.frames(2)


## Buying at a bulkhead, and what each upgrade opens.
static func _buying(t: Node) -> void:
	print("Home base bulkheads")
	var stash := _big_stash()
	var base := HomeBase.new()
	base.show_gear(stash, {})
	base.set_scrip(5000)
	t.add_child(base)
	await t.frames(20)
	var asked := []
	base.upgrade_requested.connect(func(id: String) -> void: asked.append(id))
	var p := base.player
	for id: String in ["gear_hall", "firing_range", "bay_second", "armory_alcove", "bench_workshop"]:
		var each := base.bulkhead(id)
		t._face_display(p, each)
		await t.frames(2)
		t.check(p.find_interactable() == each, "the %s panel can be walked up to and looked at" % BaseUpgrades.title(id).to_lower())
	var gate := base.bulkhead("gear_hall")
	t._face_display(p, gate)
	await t.frames(2)
	t.check(gate.get_prompt() == "[F] Buy Gear hall: 1,000 scrip" and gate.status.text == "Press F to buy",
			"a bulkhead you can afford offers itself for its price")
	await t._use(p)
	t.check(asked.is_empty() and gate.armed() and gate.get_prompt().begins_with("[F] Press again to confirm"),
			"the first press only asks you to confirm")
	await t._use(p)
	t.check(asked == ["gear_hall"] and not gate.armed(), "the second press asks to buy it")
	base.confirm_time = 0.0
	await t._use(p)
	await t._use(p)
	t.check(asked.size() == 1, "a confirm that comes too late does not buy")
	base.confirm_time = 4.0
	# Whoever owns the account answers with the new list.
	base.set_scrip(4000)
	base.show_gear(stash, {}, ["gear_hall"])
	await t.frames(3)
	t.check(base.bulkhead("gear_hall") == null and _count(base, "armor_stand") > 1 and _count(base, "rig_stand") > 1
			and _count(base, "chip_case") > 0, "the gear hall puts every stand and the chip case on show")
	var before := base.bulkheads.size()
	base.show_gear(stash, {})
	await t.frames(2)
	t.check(base.bulkheads.size() == before and base.owns("gear_hall"),
			"showing the gear again without naming upgrades keeps the base as it is")
	base.show_gear(stash, {}, ["armory_alcove", "bay_second", "gear_hall", "firing_range", "ops_consoles"])
	await t.frames(3)
	t.check(_count(base, "rack_melee") > 2 and base.in_workshop(base.bench_transform().origin),
			"the armory alcove opens the full rack, and the bench stays in the workshop (%d melee)" % _count(base, "rack_melee"))
	var heavy := base.bulkhead("heavy_wall")
	t.check(heavy != null and heavy.get_prompt() == "[F] Buy Heavy weapon wall: 4,000 scrip"
			and base.bulkhead("armory_alcove") == null,
			"once the alcove is open the heavy weapon wall can be bought")
	t.check(_count(base, "bay") == 2 and base.bulkhead("garage_full") != null and base.bulkhead("bay_second") == null,
			"the second bay parks a second bike and offers the full garage next")
	t.check(base.station("mastery") != null and base.station("records") != null and base.also_shows("trader").is_empty()
			and base.station_title("trader") == "Trader", "the ops consoles give the mastery bench and records their own")
	p.global_position = base.to_global(Vector3(0, 0.1, -base.range_from() + 2.0))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.move = Vector2(0, 1)
	await t.frames(60)
	p.cmd.move = Vector2.ZERO
	await t.frames(2)
	t.check(base.in_range(base.to_local(p.global_position)) and base.bulkhead("firing_range") == null
			and not base.in_lane(base.to_local(p.global_position)) and base.lane_targets.is_empty()
			and base.get_node_or_null("TestLane") == null,
			"the firing range's door opens once it is bought, and the test lane goes")
	base.show_gear(stash, {}, BaseUpgrades.full())
	await t.frames(3)
	var left: Array[String] = []
	for each in base.bulkheads:
		left.append(each.id)
	t.check(left.all(func(id: String) -> bool: return not BaseUpgrades.is_ready(id)) and _count(base, "bay") == 4
			and _count(base, "gunsmith") == 0 and base.bench_name() == "Master bench" and _count(base, "trophy") > 0,
			"a finished base has only the rooms still to be built left sealed (%s)" % [left])
	base.queue_free()
	await t.frames(2)


## The whole path solo: a bulkhead in your own base, paid from the profile.
static func _from_the_base(t: Node) -> void:
	print("Home base upgrades from the base")
	Profile.reset()
	Profile.welcome_granted = true
	Profile.scrip = 1500
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	var base: HomeBase = main.base
	t.check(base != null and base.upgrades.is_empty() and base.scrip == 1500,
			"you start in the starter bunker, with your scrip on its panels")
	var gate := base.bulkhead("gear_hall")
	gate.interact(base.player)
	gate.interact(base.player)
	await t.frames(3)
	t.check(Profile.base_upgrades == ["gear_hall"] and Profile.scrip == 500 and main.base == base and base.owns("gear_hall")
			and base.scrip == 500 and base.bulkhead("gear_hall") == null,
			"confirming at a bulkhead buys the upgrade and opens it in front of you")
	var pricey := base.bulkhead("trophy_hall")
	pricey.interact(base.player)
	pricey.interact(base.player)
	await t.frames(2)
	t.check(Profile.base_upgrades.size() == 1 and Profile.scrip == 500, "what you cannot afford stays sealed")
	main.open_station("trader")
	await t.frames(2)
	t.check(main.hub.visible and main.hub._sections["shop"].visible and main.hub._sections["mastery"].visible
			and not main.hub._sections["records"].visible and "MASTERY" in main.hub._title.text,
			"the shared console shows the trader and the mastery bench on one screen")
	main.hub.close()
	await t.frames(2)
	base.upgrade_requested.emit("ops_consoles")
	await t.frames(3)
	t.check(Profile.scrip == 0 and base.station("mastery") != null, "the ops consoles are bought the same way")
	main.open_station("trader")
	await t.frames(2)
	t.check(main.hub._sections["shop"].visible and not main.hub._sections["mastery"].visible,
			"and the trader's console is the trader's alone again")
	main.hub.close()
	await t.frames(2)
	main.queue_free()
	await t.frames(2)
	Profile.reset()


## The base's plan: which room stands in which socket, kept on the profile
## solo and on the account online.
static func _plan_rules(t: Node) -> void:
	print("Home base plan")
	t.check(BasePlan.clean(null) == BasePlan.DEFAULT and BasePlan.clean("junk") == BasePlan.DEFAULT
			and BasePlan.clean(null).keys() == Array(BasePlan.SOCKETS) + ["shape", "styles", "finishes"],
			"a missing or broken plan is the default one, in socket order")
	var odd := BasePlan.clean({"W1": "garage", "W2": "garage", "N1": "no_such", "E2": 7})
	var once := {}
	for socket: String in BasePlan.SOCKETS:
		once[odd[socket]] = true
	t.check(odd["W1"] == "garage" and once.size() == BasePlan.ROOMS.size(),
			"a doubled, unknown or missing room is put right: every room stands once")
	var moved := BasePlan.place(BasePlan.DEFAULT, "E1", "armory")
	t.check(moved["E1"] == "armory" and moved["W1"] == BasePlan.DEFAULT["E1"] and BasePlan.DEFAULT["W1"] == "armory",
			"moving a room swaps it with the room that stood there, and never changes the plan given")
	t.check(BasePlan.place(BasePlan.DEFAULT, "X9", "armory") == BasePlan.DEFAULT
			and BasePlan.place(BasePlan.DEFAULT, "E1", "lounge") == BasePlan.DEFAULT,
			"an unknown socket or room changes nothing")
	Profile.reset()
	t.check(Profile.place_room("N1", "garage").ok and Profile.base_plan["N1"] == "garage"
			and Profile.to_dict()["base_plan"]["N1"] == "garage", "solo, the profile keeps the plan and saves it")
	var data := Profile.to_dict()
	Profile.reset()
	t.check(Profile.base_plan == BasePlan.DEFAULT, "a fresh profile has the default plan")
	Profile.load_dict(data)
	t.check(Profile.base_plan["N1"] == "garage", "the plan survives a save")
	Profile.reset()
	var service := Accounts.new()
	service.persist = false
	var id: String = service.sign_in("Planner", "a-long-enough-secret-for-tests").account_id
	t.check(service.snapshot(id).base_plan == BasePlan.DEFAULT, "a new account has the default plan")
	service.change_scrip(id, 5000)
	service.deploy(id, Worlds.raid_worlds()[0])
	t.check(service.place_room(id, "W1", "ops").ok and service.snapshot(id).base_plan["W1"] == "ops",
			"online, the account keeps the plan, and it may be changed while out in a world: it moves nothing")
	service.cancel_deploy(id)
	t.check(not service.place_room(id, "W1", "lounge").ok and not service.place_room(id, "Z1", "ops").ok
			and not service.place_room("nobody", "W1", "ops").ok, "the server refuses unknown rooms, sockets and accounts")
	var saved := service.load_account(id).to_dict()
	var loaded := Accounts.Account.new()
	loaded.load_dict(saved)
	t.check(loaded.base_plan["W1"] == "ops", "an account's plan survives a save")
	saved.erase("base_plan")
	loaded.load_dict(saved)
	t.check(loaded.base_plan == BasePlan.DEFAULT, "a save from before the plan opens with the default one")
	t.check("base_plan" in StashRules.CARRIED, "your own server is handed your plan with the rest of you")


## The plan table in the middle of the hub: walk up, turn to a socket, pick a
## room for it, and the base asks to move it; the rooms follow the plan.
static func _plan_table(t: Node) -> void:
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine"], {"primary": "rifle_carbine"})
	t.add_child(base)
	await t.frames(20)
	var table := base.plan_table
	t.check(table != null and base.room_at(table.position) == "" and base.inside(table.position)
			and table.get_prompt().begins_with("[F] Plan table"), "the plan table stands in the hub and offers itself")
	t._face_display(base.player, table)
	await t.frames(2)
	var found := base.player.find_interactable()
	t.check(found == table, "it can be walked up to and looked at (%s)" % [found.name if found else "nothing"])
	var used := [0]
	var placed := []
	base.plan_used.connect(func() -> void: used[0] += 1)
	base.room_placed.connect(func(socket: String, room: String) -> void: placed.append([socket, room]))
	await t._use(base.player)
	t.check(used[0] == 1 and base.plan_open and base.plan_hover.is_empty(), "using it takes the table up")
	var choice := "garage"
	base.plan_preview(BasePlan.place(base.base_plan, "N1", choice))
	t.check(base.plan_shown()["N1"] == choice and base.base_plan["N1"] == BasePlan.DEFAULT["N1"] and placed.is_empty(),
			"the table shows a room pointed at in its socket, without moving anything yet")
	t.check(base.plan_change("N1", choice) == "" and placed == [["N1", choice]], "a pick asks to move the room there")
	var armory_before := base.room_transform("armory")
	var plan := BasePlan.place(base.base_plan, "N1", choice)
	base.show_gear(base.stash, base.loadout, null, plan)
	await t.frames(3)
	var rack := base.spot_transform("rack_guns", 0).origin
	t.check(base.base_plan["N1"] == choice
			and base.room_at(base.room_transform(choice) * Vector3(0, 0.1, -1.0)) == choice and base.in_armory(rack),
			"the rooms follow the plan, and what is on show goes with its room")
	var shown := base.display_for("rifle_carbine")
	t.check(shown != null and base.in_armory(shown.position) and (choice != "armory" or not armory_before.is_equal_approx(base.room_transform("armory"))),
			"a gun on the rack moves with the armory")
	base.leave_plan()
	t.check(not base.plan_open and base.plan_hover.is_empty(), "stepping away closes the table and drops the preview")
	base.queue_free()
	await t.frames(2)
	var visited := HomeBase.new()
	visited.read_only = true
	visited.show_gear([], {}, [], {"W1": "garage", "E1": "armory"})
	t.add_child(visited)
	await t.frames(3)
	visited.use_plan()
	t.check(visited.room_at(visited.socket_transform("W1") * Vector3(0, 0.1, -1.0)) == "garage" and not visited.plan_open,
			"a visited base stands as its owner laid it out, and its table cannot be used")
	visited.queue_free()
	await t.frames(2)


## Hub shapes and room styles: what is free, what must be unlocked, and how a
## change is checked solo and on the server.
static func _design_rules(t: Node) -> void:
	print("Home base designs")
	t.check(BasePlan.unlock_for("shape", "hall") == "" and BasePlan.unlock_for("shape", "ring") == "hub_ring"
			and BasePlan.unlock_for("style:armory", "rack") == "" and BasePlan.unlock_for("style:armory", "vault") == "style_armory_vault"
			and BasePlan.unlock_for("W1", "ops") == "", "the hall and each room's first style are free; the rest need an unlock")
	for room: String in BasePlan.ROOMS:
		t.check(BasePlan.STYLES.has(room) and BasePlan.styles(room).size() == 3, "%s has three styles" % room)
	var locked := BasePlan.change(BasePlan.DEFAULT, [], "shape", "ring")
	t.check(not locked.ok and "ring" in str(locked.error).to_lower(), "a locked shape is refused (%s)" % locked.get("error", ""))
	var open := BasePlan.change(BasePlan.DEFAULT, ["hub_ring"], "shape", "ring")
	t.check(open.ok and open.plan["shape"] == "ring" and open.plan["W1"] == BasePlan.DEFAULT["W1"] and BasePlan.DEFAULT["shape"] == "hall",
			"an unlocked shape is taken up, the rooms keep their sockets, and the plan given never changes")
	var styled := BasePlan.change(open.plan, ["style_gear_ring"], "style:gear", "ring")
	t.check(styled.ok and styled.plan["styles"]["gear"] == "ring" and styled.plan["shape"] == "ring",
			"an unlocked style goes on its room and keeps the rest")
	t.check(not BasePlan.change(BasePlan.DEFAULT, ["style_gear_ring"], "style:armory", "ring").ok
			and not BasePlan.change(BasePlan.DEFAULT, [], "shape", "dome").ok
			and not BasePlan.change(BasePlan.DEFAULT, [], "style:lounge", "rack").ok
			and not BasePlan.change(BasePlan.DEFAULT, [], "colour", "red").ok,
			"a style of another room, an unknown shape, room or change is refused")
	t.check(BasePlan.change(styled.plan, [], "shape", "hall").ok, "going back to a free choice needs nothing")
	var odd := BasePlan.clean({"shape": "dome", "styles": {"armory": "no_such", "gear": "ring"}})
	t.check(odd["shape"] == "hall" and odd["styles"]["armory"] == "rack" and odd["styles"]["gear"] == "ring",
			"an unknown shape or style falls back to the free one; a known one is kept whatever is owned")
	Profile.reset()
	Profile.scrip = 10000
	t.check(not Profile.place_room("shape", "spine").ok and Profile.base_plan["shape"] == "hall", "solo, a locked shape is refused")
	t.check(Profile.buy_upgrade("hub_spine").ok and Profile.scrip == 7000 and Profile.place_room("shape", "spine").ok
			and Profile.base_plan["shape"] == "spine", "bought once with scrip, it can be used")
	t.check(Profile.place_room("shape", "hall").ok and Profile.place_room("shape", "spine").ok and Profile.scrip == 7000,
			"switching back and forth is free after")
	var data := Profile.to_dict()
	Profile.reset()
	Profile.load_dict(data)
	t.check(Profile.base_plan["shape"] == "spine" and "hub_spine" in Profile.base_upgrades, "the shape and its unlock survive a save")
	Profile.reset()
	var service := Accounts.new()
	service.persist = false
	var id: String = service.sign_in("Designer", "a-long-enough-secret-for-tests").account_id
	t.check(not service.place_room(id, "style:stores", "cargo").ok, "the server refuses a style the account has not unlocked")
	service.change_scrip(id, 2000)
	var before: int = service.snapshot(id).scrip
	t.check(service.buy_upgrade(id, "style_stores_cargo").ok and service.place_room(id, "style:stores", "cargo").ok
			and service.snapshot(id).base_plan["styles"]["stores"] == "cargo" and service.snapshot(id).scrip == before - 800,
			"online the unlock is bought from the account's scrip and the style kept on its plan")


## Every hub shape stands whole: each socket's room opens off the hub and
## clear of the others, the corridor and the range, and you can walk in.
static func _shapes(t: Node) -> void:
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine"], {"primary": "rifle_carbine"}, BaseUpgrades.full())
	t.add_child(base)
	await t.frames(10)
	for shape: String in BasePlan.SHAPES:
		var plan := BasePlan.clean(null)
		plan["shape"] = shape
		base.show_gear(base.stash, base.loadout, null, plan)
		await t.frames(3)
		t.check(base.hub_shape() == shape and base.room_size == HomeBase.HUB_SIZES[shape], "%s: the hub takes its shape" % shape)
		var sockets_ok := true
		for socket: String in BasePlan.SOCKETS:
			var xf := base.socket_transform(socket)
			var room: String = base.base_plan[socket]
			# Just inside the doorway is the room; just outside it the hub.
			sockets_ok = sockets_ok and base.room_at(xf * Vector3(0, 0.1, -1.0)) == room \
					and base.in_hub(xf * Vector3(0, 0.1, 1.2)) and not base.in_corridor(xf * Vector3(0, 0.1, -1.0))
			for other: String in BasePlan.SOCKETS:
				if other != socket:
					var far := base.socket_transform(other)
					sockets_ok = sockets_ok and base.room_at(far * Vector3(0, 0.1, -1.0)) != room
			# A room's far corners stay clear of the range.
			for corner: Vector3 in [Vector3(-4.7, 0.1, -9.7), Vector3(4.7, 0.1, -9.7)]:
				sockets_ok = sockets_ok and not base.in_range(xf * corner)
		t.check(sockets_ok, "%s: every room opens off the hub, clear of the others and the range" % shape)
		var spawn := base.spawn_point
		var mirror := base.mirror_at()
		var locker := base.station_transform("locker").origin
		var span := base.deploy_span()
		t.check(base.in_hub(spawn) and base.in_hub(mirror - Vector3(0, 0, 0.3)) and base.in_hub(locker)
				and span.y - span.x >= 1.5 and mirror.x > span.x and mirror.x < span.y
				and base.in_hub(Vector3(0, 0.1, base.room_size.z * 0.5 - 0.5)) and base.in_corridor(Vector3(0, 0.1, -base.room_size.z * 0.5 - 0.5)),
				"%s: the door, locker, mirror and deploy area stand on its front wall, the corridor behind it" % shape)
		t.check(base.has_node("Door") and base.range_board != null and base.course_board != null and base.wall_mirror.position.is_equal_approx(mirror),
				"%s: the door, the range and the course are built for it" % shape)
		# Walk from the hub into the armory.
		var walker := base.player
		var armory_door := base.room_transform("armory")
		walker.global_position = base.to_global(armory_door * Vector3(0, 0.1, 2.5))
		walker.velocity = Vector3.ZERO
		await t.frames(2)
		var into := -armory_door.basis.z
		walker.cmd.yaw = atan2(-into.x, -into.z)
		walker.cmd.move = Vector2(0, 1)
		await t.frames(90)
		walker.cmd.move = Vector2.ZERO
		t.check(base.in_armory(base.to_local(walker.global_position)), "%s: you can walk from the hub into the armory" % shape)
		# Standing at the far end of the hall, then the shape changes: you
		# are put back in the hub.
		walker.global_position = base.to_global(Vector3(0, 0.1, -base.room_size.z * 0.5 + 0.8))
	var back := BasePlan.clean(null)
	base.show_gear(base.stash, base.loadout, null, back)
	await t.frames(3)
	t.check(base.inside(base.to_local(base.player.global_position)) and base.find_children("Door*", "", false, false).size() == 1,
			"changing the shape builds one hub, and keeps you inside it")
	base.queue_free()
	await t.frames(2)


## Every room style lays out every spot its room has inside the room, whole
## and small, and stands its stations and bench there too.
static func _styles(t: Node) -> void:
	var base := HomeBase.new()
	t.add_child(base)
	await t.frames(5)
	var kinds := {}
	for kind: String in HomeBase.KIND_ROOMS:
		kinds[kind] = true
	for room: String in BasePlan.STYLES:
		for style: String in BasePlan.STYLES[room]:
			var inside := true
			var apart := true
			for whole: bool in [true, false]:
				if not whole and str(BasePlan.ROOMS[room]["opens"]) == "":
					continue
				var depth := base.socket_size.z if whole else base.small_depth
				var spots: Array[Vector3] = []
				for kind: String in kinds:
					if HomeBase.KIND_ROOMS[kind] != room:
						continue
					var count := int(BaseLayout.KINDS[kind]["spots"]) if whole else int(BaseLayout.KINDS[kind].get("starter", 0))
					if kind == "bay" and not whole:
						count = 2
					for i in count:
						var at := base.style_room_spot(kind, i, style, whole).origin
						inside = inside and absf(at.x) < base.socket_size.x * 0.5 and at.z < 0.0 and at.z > -depth
						for other in spots:
							apart = apart and other.distance_to(at) > 0.3
						spots.append(at)
				var ids: Array = ["bench"] if room == "workshop" else []
				for id: String in HomeBase.STATIONS:
					if HomeBase.STATIONS[id]["room"] == room:
						ids.append(id)
				for id: String in ids:
					var at := base.style_station_spot(room, id, style, whole, Transform3D.IDENTITY).origin
					if at != Vector3.ZERO:
						inside = inside and absf(at.x) < base.socket_size.x * 0.5 and at.z < 0.0 and at.z > -depth
			t.check(inside and apart, "%s in the %s style: every spot stands in the room, apart, whole and small" % [room, style])
	# A style on: the room is furnished for it and the displays stand there.
	var stash := ["rifle_carbine", "smg_stinger", "frame_runner", "helm_warden"]
	var plan := BasePlan.clean(null)
	plan["styles"]["armory"] = "gallery"
	plan["styles"]["gear"] = "ring"
	plan["styles"]["workshop"] = "pit"
	base.show_gear(stash, {"primary": "rifle_carbine"}, BaseUpgrades.full(), plan)
	await t.frames(3)
	var gun := base.display_for("smg_stinger")
	var cases := base.find_children("Case_*", "", true, false)
	var bench := base.room_transform("workshop").affine_inverse() * base.bench_transform()
	t.check(gun != null and base.in_armory(gun.position) and absf(gun.basis.x.y) > 0.9 and cases.size() == 12,
			"the gallery armory stands each long gun upright in a case of its own")
	t.check(base.in_workshop(base.bench_transform().origin) and absf(bench.basis.z.x) > 0.9,
			"the pit workshop stands the bench along its side wall, and the bench goes with it")
	var frame := base.display_for("frame_runner")
	t.check(frame != null and base.room_at(frame.position) == "gear" and base.has_node("Room_N1/Dais"),
			"the ring gear hall stands its armor round the dais")
	base.queue_free()
	await t.frames(2)


## Finishes: steel is free, the rest are bought once and go on any room or
## the hub.
static func _finish_rules(t: Node) -> void:
	print("Home base finishes")
	var plan := BasePlan.clean(null)
	t.check(plan["finishes"].size() == 7 and plan["finishes"].values().all(func(f: String) -> bool: return f == "steel")
			and plan["finishes"] == BasePlan.DEFAULT["finishes"], "a new base is steel everywhere: the hub and all six rooms")
	t.check(BasePlan.unlock_for("finish:hub", "steel") == "" and BasePlan.unlock_for("finish:garage", "brass") == "finish_brass"
			and BasePlan.unlock_for("finish:armory", "brass") == "finish_brass", "steel is free; one unlock per finish, whatever it goes on")
	for finish: String in BasePlan.FINISHES:
		t.check(HomeBase.FINISH_LOOKS.has(finish) and BasePlan.FINISHES[finish]["swatch"].size() == 4,
				"the %s finish has a look and a swatch" % finish)
	var locked := BasePlan.change(plan, [], "finish:garage", "brass")
	t.check(not locked.ok and "brass" in str(locked.error).to_lower(), "a finish not unlocked is refused")
	var one := BasePlan.change(plan, ["finish_brass"], "finish:garage", "brass")
	var two := BasePlan.change(one.plan, ["finish_brass"], "finish:hub", "brass")
	t.check(one.ok and two.ok and two.plan["finishes"]["garage"] == "brass" and two.plan["finishes"]["hub"] == "brass"
			and two.plan["finishes"]["armory"] == "steel" and plan["finishes"]["garage"] == "steel",
			"once bought it goes on any room and the hub, leaving the rest as they were")
	t.check(not BasePlan.change(plan, ["finish_brass"], "finish:lounge", "brass").ok
			and not BasePlan.change(plan, [], "finish:hub", "gold").ok, "an unknown room or finish is refused")
	var odd := BasePlan.clean({"finishes": {"hub": "gold", "ops": "ceramic"}})
	t.check(odd["finishes"]["hub"] == "steel" and odd["finishes"]["ops"] == "ceramic" and odd["finishes"]["gear"] == "steel",
			"an unknown or missing finish is steel")
	Profile.reset()
	Profile.scrip = 5000
	t.check(not Profile.place_room("finish:ops", "ceramic").ok, "solo, a finish not bought is refused")
	t.check(Profile.buy_upgrade("finish_ceramic").ok and Profile.scrip == 3500 and Profile.place_room("finish:ops", "ceramic").ok
			and Profile.place_room("finish:hub", "ceramic").ok and Profile.scrip == 3500,
			"bought once, it goes on as many rooms as you like for free")
	var data := Profile.to_dict()
	Profile.reset()
	Profile.load_dict(data)
	t.check(Profile.base_plan["finishes"]["ops"] == "ceramic" and Profile.base_plan["finishes"]["hub"] == "ceramic",
			"the finishes survive a save")
	Profile.reset()


## Each room and the hub are built in their own finish.
static func _finishes(t: Node) -> void:
	var base := HomeBase.new()
	var plan := BasePlan.clean(null)
	plan["finishes"]["armory"] = "blackout"
	plan["finishes"]["hub"] = "ceramic"
	base.show_gear([], {}, BaseUpgrades.full(), plan)
	t.add_child(base)
	await t.frames(5)
	var armory := base.get_node("Room_%s" % BasePlan.socket_of(base.base_plan, "armory"))
	var garage := base.get_node("Room_%s" % BasePlan.socket_of(base.base_plan, "garage"))
	var wall_of := func(finish: String) -> Color:
		return HomeBase.FINISH_LOOKS[finish]["wall"]["tint"] * 0.5
	t.check(_tints(armory).has(wall_of.call("blackout")) and not _tints(armory).has(wall_of.call("steel")),
			"the armory is built in blackout")
	t.check(_tints(garage).has(wall_of.call("steel")) and not _tints(garage).has(wall_of.call("blackout")),
			"the garage stays steel")
	var hub_tints := {}
	for node in base._static_nodes:
		if is_instance_valid(node):
			hub_tints.merge(_tints(node))
	t.check(hub_tints.has(wall_of.call("ceramic")) and not hub_tints.has(wall_of.call("steel")), "the hub is built in ceramic")
	plan["finishes"]["hub"] = "steel"
	base.show_gear([], {}, null, plan)
	await t.frames(2)
	hub_tints = {}
	for node in base._static_nodes:
		if is_instance_valid(node):
			hub_tints.merge(_tints(node))
	t.check(hub_tints.has(wall_of.call("steel")) and not hub_tints.has(wall_of.call("ceramic")),
			"a new finish for the hub builds its shell again")
	base.queue_free()
	await t.frames(2)


## The colours of every plain material under `node` (headless, `Look`
## gives each surface a plain one of half its tint).
static func _tints(node: Node) -> Dictionary:
	var out := {}
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var box := (mesh as MeshInstance3D).mesh as BoxMesh
		if box != null and box.material is StandardMaterial3D:
			out[(box.material as StandardMaterial3D).albedo_color] = true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		var mat: Variant = ((node as MeshInstance3D).mesh as BoxMesh).material
		if mat is StandardMaterial3D:
			out[mat.albedo_color] = true
	return out


## The customizer on the plan table: its tabs, a preview on the hologram, a
## pick, an unlock bought with a confirming click and put in use.
static func _customizer(t: Node) -> void:
	var base := HomeBase.new()
	base.show_gear([], {})
	t.add_child(base)
	await t.frames(5)
	base.set_scrip(5000)
	var placed := []
	var bought := []
	base.room_placed.connect(func(key: String, value: String) -> void: placed.append([key, value]))
	base.upgrade_requested.connect(func(id: String) -> void: bought.append(id))
	base.use_plan()
	var view: Node3D = load("res://core/ui/bench_view.gd").new()
	view.base = base
	view.target = "plan"
	base.add_child(view)
	view.focus()
	await t.frames(3)
	var panel: Control = view.panel
	t.check(panel != null and view.screen != null and view.screen.get_parent() == base.plan_screen(),
			"the customizer is mounted on the table's screen")
	t.check(panel.find_child("Tab_layout", true, false) != null and panel.find_child("Shape_ring", true, false) != null
			and panel.state_of("shape", "hall") == "used" and panel.state_of("shape", "ring") == "locked",
			"the layout tab shows every shape, the one in use and the ones to unlock")
	(panel.find_child("Shape_ring", true, false) as Button).mouse_entered.emit()
	t.check(base.plan_shown()["shape"] == "ring" and base.base_plan["shape"] == "hall", "pointing at a shape shows it on the table")
	panel.act("shape", "ring")
	await t.frames(2)
	t.check(bought.is_empty() and panel.confirming == ["shape", "ring"] and "Confirm" in str((panel.find_child("Action", true, false) as Button).text),
			"the first click on a locked shape asks to confirm the price")
	panel.act("shape", "ring")
	t.check(bought == ["hub_ring"] and placed.is_empty(), "the second click asks to buy its unlock")
	base.show_gear([], {}, ["hub_ring"])
	await t.frames(3)
	t.check(placed == [["shape", "ring"]], "once bought, it is put in use")
	panel.show_tab("rooms")
	await t.frames(2)
	t.check(panel.find_child("Socket_N1", true, false) != null, "the rooms tab draws a doorway for each socket")
	panel.socket_pick = "N1"
	panel._refresh()
	await t.frames(2)
	(panel.find_child("Room_garage", true, false) as Button).pressed.emit()
	t.check(placed.back() == ["N1", "garage"], "a room picked for a doorway asks to move it there")
	panel.show_tab("styles")
	panel.room_pick = "ops"
	panel._refresh()
	await t.frames(2)
	t.check(panel.find_child("Style_bridge", true, false) != null and panel.state_of("style:ops", "consoles") == "used",
			"the styles tab shows the room's three styles")
	panel.show_tab("finishes")
	await t.frames(2)
	t.check(panel.find_child("FinishArea_hub", true, false) != null and panel.find_child("Finish_blackout", true, false) != null
			and panel.state_of("finish:hub", "steel") == "used" and panel.state_of("finish:hub", "gunmetal") == "locked",
			"the finishes tab lists the hub and the rooms and every finish")
	base.show_gear([], {}, ["hub_ring", "finish_gunmetal"])
	await t.frames(2)
	panel.area_pick = "ops"
	panel.act("finish:ops", "gunmetal")
	t.check(placed.back() == ["finish:ops", "gunmetal"], "an owned finish picked for a room asks to put it on")
	placed.clear()
	panel.finish_pick = "gunmetal"
	panel._refresh()
	await t.frames(2)
	(panel.find_child("FinishAll", true, false) as Button).pressed.emit()
	t.check(placed.size() == BasePlan.areas().size(), "one click puts the finish on the hub and every room")
	panel.socket_pick = "W1"
	panel.show_tab("rooms")
	t.check(panel.back() and panel.socket_pick == "" and not panel.back(), "a right click steps back, then leaves")
	view.leave()
	t.check(not base.plan_open and view.screen == null, "leaving takes the screen down")
	await t.frames(2)
	base.queue_free()
	await t.frames(2)
