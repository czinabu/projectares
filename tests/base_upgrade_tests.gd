extends RefCounted
## Checks for home base upgrades: the catalog and its buying rules, where an
## account keeps what it owns, how the base's layout follows them, and the
## sealed bulkheads you buy them at. Called from the test runner
## (`-- --only base_upgrades` runs just these).

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")


static func run(t: Node) -> void:
	print("Home base upgrades")
	_rules(t)
	_layout(t)
	_accounts(t)
	await _bunker(t)
	await _buying(t)
	await _from_the_base(t)


## The catalog, and what may be bought when.
static func _rules(t: Node) -> void:
	t.check(BaseUpgrades.ids().size() == 12 and BaseUpgrades.total_price() == 26600,
			"twelve upgrades cost 26,600 scrip together")
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
	t.check(BaseUpgrades.blocked(["armory_alcove"], "heavy_wall") == "Not open yet." and not waiting.is_empty(),
			"an upgrade whose room is not built yet cannot be bought (%s)" % [waiting])
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


## The base with no upgrades: fewer spots, sealed rooms, shared consoles.
static func _bunker(t: Node) -> void:
	print("Home base starter bunker")
	var stash := _big_stash()
	var base := HomeBase.new()
	base.show_gear(stash, {})
	t.add_child(base)
	await t.frames(20)
	t.check(base.upgrades.is_empty() and _count(base, "rack_guns") == 4 and _count(base, "rack_sidearms") == 2
			and _count(base, "rack_melee") == 2 and _count(base, "bay") == 1 and _count(base, "armor_stand") == 1
			and _count(base, "rig_stand") == 1 and _count(base, "gunsmith") == 0 and _count(base, "supplies") <= 3
			and _count(base, "chip_case") == 0 and _count(base, "trophy") == 0,
			"a starter bunker shows a short rack, one bay and one stand of each kind")
	var nook_wall := -base.room_size.x * 0.5 - base.nook_depth
	var in_nook := true
	var all_inside := true
	for display in base.displays:
		all_inside = all_inside and base.inside(display.position)
		if BaseLayout.is_armory(display.kind):
			in_nook = in_nook and base.in_armory(display.position) and display.position.x > nook_wall
	t.check(in_nook and all_inside, "the starter rack hangs in the armory nook, in front of its sealed wall")
	t.check(base.in_workshop(base.bench_transform().origin) and base.inside(base.bench_transform().origin)
			and base.in_workshop(base.station(HomeBase.CRAFT_ID).position),
			"the starter bunker's bench and fabricator already stand in the workshop off the nook")
	# The workshop opens off the nook, and only into it: the sealed alcove
	# behind the nook's wall stays out of reach from the workshop too.
	var p := base.player
	for leg: Array in [[Vector3(-13.6, 0.1, 4.0), PI, "workshop"], [Vector3(-15.3, 0.1, 6.95), 0.0, "sealed"]]:
		p.global_position = base.to_global(leg[0])
		p.velocity = Vector3.ZERO
		p.cmd.yaw = leg[1]
		p.cmd.move = Vector2(0, 1)
		await t.frames(50)
		p.cmd.move = Vector2.ZERO
		await t.frames(2)
		var at := base.to_local(p.global_position)
		if leg[2] == "workshop":
			t.check(base.in_workshop(at), "you can walk from the nook into the workshop (%s)" % at)
		else:
			t.check(at.z > base.armory_size.z * 0.5 and at.x > -base.room_size.x * 0.5 - base.armory_size.x,
					"the workshop does not lead past the nook's sealed wall (%s)" % at)
	var shown: Array[String] = []
	for gate in base.bulkheads:
		shown.append(gate.id)
	shown.sort()
	var expected: Array[String] = ["armory_alcove", "bay_second", "bench_workshop", "finish", "firing_range",
			"gear_hall", "lounge", "ops_consoles", "trophy_hall"]
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
	p.global_position = base.to_global(Vector3(0, 0.1, -6.5))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.move = Vector2(0, 1)
	await t.frames(60)
	p.cmd.move = Vector2.ZERO
	await t.frames(2)
	t.check(not base.in_range(base.to_local(p.global_position)) and base.bulkhead("firing_range") != null,
			"the firing range's door is sealed")
	# The garage beyond the first bay is walled off.
	p.global_position = base.to_global(base.spot_transform("bay", 0).origin + Vector3(-2.6, 0.1, 0.9))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = PI
	p.cmd.move = Vector2(0, 1)
	await t.frames(90)
	p.cmd.move = Vector2.ZERO
	await t.frames(2)
	var reached: float = base.to_local(p.global_position).z
	t.check(reached < base.spot_transform("bay", 1).origin.z - 0.8 and base.bulkhead("bay_second") != null,
			"the garage past the first bay is closed off (walked to z %.1f)" % reached)
	# With nothing to spend, a bulkhead says why it stays shut.
	var gate := base.bulkhead("gear_hall")
	var asked := []
	base.upgrade_requested.connect(func(id: String) -> void: asked.append(id))
	gate.interact(p)
	gate.interact(p)
	t.check(asked.is_empty() and "Not enough scrip" in gate.get_prompt() and "Not enough scrip" in gate.status.text,
			"without the scrip a bulkhead cannot be bought, and says so")
	var lounge := base.bulkhead("lounge")
	base.set_scrip(99999)
	lounge.interact(p)
	lounge.interact(p)
	t.check(asked.is_empty() and "Not open yet" in lounge.get_prompt(), "an upgrade that is not built yet stays sealed")
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
	t.check(_count(base, "rack_melee") > 2 and base.in_armory(base.bench_transform().origin)
			and base.bench_transform().origin == HomeBase.BENCH_AT, "the armory alcove opens the full rack and takes the bench in (%d melee)" % _count(base, "rack_melee"))
	var heavy := base.bulkhead("heavy_wall")
	t.check(heavy != null and "Not open yet" in heavy.get_prompt() and base.bulkhead("armory_alcove") == null,
			"once the alcove is open the heavy weapon wall shows as the armory's next step")
	t.check(_count(base, "bay") == 2 and base.bulkhead("garage_full") != null and base.bulkhead("bay_second") == null,
			"the second bay parks a second bike and offers the full garage next")
	t.check(base.station("mastery") != null and base.station("records") != null and base.also_shows("trader").is_empty()
			and base.station_title("trader") == "Trader", "the ops consoles give the mastery bench and records their own")
	p.global_position = base.to_global(Vector3(0, 0.1, -6.5))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.move = Vector2(0, 1)
	await t.frames(60)
	p.cmd.move = Vector2.ZERO
	await t.frames(2)
	t.check(base.in_range(base.to_local(p.global_position)) and base.bulkhead("firing_range") == null,
			"the firing range's door opens once it is bought")
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
