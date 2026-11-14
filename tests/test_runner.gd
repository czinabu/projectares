extends Node
## Headless test suite. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when everything passes, 1 otherwise.

const StashRules := preload("res://core/account/stash_rules.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const RaidRoster := preload("res://core/ui/raid_roster.gd")
const NameplatesScript := preload("res://core/ui/nameplates.gd")
const ScoreboardScript := preload("res://core/ui/scoreboard.gd")
const Strongpoint := preload("res://core/war/strongpoint.gd")
const WarDirector := preload("res://core/war/war_director.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")
const LookTests := preload("res://tests/look_tests.gd")
const RigLookTests := preload("res://tests/rig_look_tests.gd")
const RigTierTests := preload("res://tests/rig_tier_tests.gd")
const RigBalanceTests := preload("res://tests/rig_balance_tests.gd")
const HoverbikeTests := preload("res://tests/hoverbike_tests.gd")
const EconomyTests := preload("res://tests/economy_tests.gd")
const MeleeArsenalTests := preload("res://tests/melee_arsenal_tests.gd")
const MeleeFeelTests := preload("res://tests/melee_feel_tests.gd")
const MeleeViabilityTests := preload("res://tests/melee_viability_tests.gd")
const BotAimTests := preload("res://tests/bot_aim_tests.gd")
const CustomizerTests := preload("res://tests/customizer_tests.gd")
const BattlefieldTests := preload("res://tests/battlefield_tests.gd")
const VisorTests := preload("res://tests/visor_tests.gd")
const SidearmTests := preload("res://tests/sidearm_tests.gd")
const BaseUpgradeTests := preload("res://tests/base_upgrade_tests.gd")
const CraftingTests := preload("res://tests/crafting_tests.gd")
const AttachmentTests := preload("res://tests/attachment_tests.gd")
const PowerWeaponTests := preload("res://tests/power_weapon_tests.gd")
const ArtifactTests := preload("res://tests/artifact_tests.gd")
const WatchTests := preload("res://tests/watch_tests.gd")
const PortalTests := preload("res://tests/portal_tests.gd")
const ContractTests := preload("res://tests/contract_tests.gd")
const FeelTests := preload("res://tests/feel_tests.gd")
const ViewMatchTests := preload("res://tests/view_match_tests.gd")
const AdsTests := preload("res://tests/ads_tests.gd")
const GripTests := preload("res://tests/grip_tests.gd")
const TravelTests := preload("res://tests/travel_tests.gd")
const BareLoadoutTests := preload("res://tests/bare_loadout_tests.gd")
const OnboardingTests := preload("res://tests/onboarding_tests.gd")
const TravelOnlineTests := preload("res://tests/travel_online_tests.gd")
const RiskZoneTests := preload("res://tests/risk_zone_tests.gd")
const InspectTests := preload("res://tests/inspect_tests.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	Profile.persist = false
	# Most checks want a player ready to fight where they spawn, unhurt by the
	# ground; the risk zone checks turn the gates and hazards back on.
	Raid.zone_rules = false
	# DEV MODE: tests never run on the dev save, whatever the machine has.
	DevMode.persist = false
	DevMode.enabled = false
	Profile.save_path = Profile.SAVE_PATH
	Profile.reset()
	# Accounts a previous run left behind hold that run's secrets and would
	# refuse this run's sign-ins, so every run starts with none.
	_wipe_dir(NET_ACCOUNTS)
	var args := OS.get_cmdline_user_args()
	if "--list" in args:
		_list_groups()
		get_tree().quit(0)
		return
	if "--tier" in args or "--shard" in args or "--groups" in args:
		await _run_selected(args)
	else:
		await _run()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- Picking groups for CI -------------------------------------------------
# CI splits the suite in two tiers:
#   offline  groups that never start a server. They only count physics frames,
#            so CI runs them with `--fixed-fps 60`, which drops the real-time
#            wait and finishes in about a minute.
#   net      groups that start a server process and talk to it over ENet. They
#            need real time, so they run without `--fixed-fps`, split in shards.
# The groups are read from `_run()` itself and a group is `net` when it (or any
# helper it calls) starts a server or makes a NetSession, so a new group needs
# no change here.
#   -- --list                  print every group and its tier
#   -- --tier offline|net      run one tier
#   -- --shard 2/3             run the 2nd of 3 balanced slices (with or without --tier)
#   -- --groups a,b            run the named groups (names as --list prints them)
#   -- --times-out path.json   write how long each group took

const NET_MARKERS: Array[String] = ["_start_server(", "NetSession"]
const GROUP_TIMES := "res://tests/group_times.json"

var _source_cache := ""


func _arg(args: PackedStringArray, flag: String) -> String:
	var at := args.find(flag)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else ""


func _source() -> String:
	if _source_cache == "":
		_source_cache = (get_script() as Script).source_code
		if _source_cache == "":
			_source_cache = FileAccess.get_file_as_string("res://tests/test_runner.gd")
	return _source_cache


## The text of `func fn_name(...)` up to the next top-level func.
func _func_body(src: String, fn_name: String) -> String:
	var start := src.find("\nfunc " + fn_name + "(")
	if start < 0:
		return ""
	var stop := src.find("\nfunc ", start + 1)
	return src.substr(start, (stop if stop >= 0 else src.length()) - start)


## Every group `_run()` calls, in order: `_test_x` methods and `Module.run(self)` files.
func _groups() -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("^\\t(?:await )?(\\w+)(?:\\.run\\(self\\)|\\(\\))\\s*$")
	for line in _func_body(_source(), "_run").split("\n"):
		var m := re.search(line)
		if m != null:
			out.append(m.get_string(1))
	return out


func _group_label(group: String) -> String:
	return group.trim_prefix("_test_")


func _module_source(const_name: String) -> String:
	var mod: Variant = (get_script() as Script).get_script_constant_map().get(const_name)
	return (mod as Script).source_code if mod is Script else ""


func _is_net(group: String) -> bool:
	var src := _source()
	var call_re := RegEx.create_from_string("\\b(_[a-z]\\w*)\\(")
	var module_re := RegEx.create_from_string("\\b([A-Z]\\w*)\\.run\\(")
	var seen := {}
	var todo: Array[String] = [group]
	while not todo.is_empty():
		var fn: String = todo.pop_back()
		if seen.has(fn):
			continue
		seen[fn] = true
		var body := _module_source(fn) if fn[0] == fn[0].to_upper() and fn[0] != "_" else _func_body(src, fn)
		for marker in NET_MARKERS:
			if marker in body:
				return true
		for m in call_re.search_all(body):
			todo.append(m.get_string(1))
		for m in module_re.search_all(body):
			todo.append(m.get_string(1))
	return false


func _list_groups() -> void:
	for group in _groups():
		print("%-6s %s" % ["net" if _is_net(group) else "offline", _group_label(group)])


## Splits groups into `count` slices of about equal run time, using the last
## measured times (unknown groups count as an average one).
func _shard(groups: Array[String], index: int, count: int) -> Array[String]:
	var times: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROUP_TIMES)) \
			if FileAccess.file_exists(GROUP_TIMES) else null
	if parsed is Dictionary:
		times = parsed
	var known: Array = times.values()
	var fallback: float = 5.0 if known.is_empty() else known.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / known.size()
	var weight := func(g: String) -> float: return float(times.get(_group_label(g), fallback))
	var ordered := groups.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool:
		return weight.call(a) > weight.call(b) or (weight.call(a) == weight.call(b) and a < b))
	var loads: Array[float] = []
	loads.resize(count)
	loads.fill(0.0)
	var mine: Array[String] = []
	for g in ordered:
		var lightest := loads.find(loads.min())
		loads[lightest] += weight.call(g)
		if lightest == index:
			mine.append(g)
	# Keep `_run()` order inside the slice.
	return groups.filter(func(g: String) -> bool: return g in mine)


func _run_selected(args: PackedStringArray) -> void:
	var groups := _groups()
	var tier := _arg(args, "--tier")
	if tier != "":
		if tier not in ["offline", "net"]:
			check(false, "--tier must be offline or net, got '%s'" % tier)
			return
		groups = groups.filter(func(g: String) -> bool: return _is_net(g) == (tier == "net"))
	var names := _arg(args, "--groups")
	if names != "":
		var wanted := names.split(",", false)
		for name in wanted:
			check(groups.any(func(g: String) -> bool: return _group_label(g) == name), "group '%s' exists" % name)
		groups = groups.filter(func(g: String) -> bool: return _group_label(g) in wanted)
	var shard := _arg(args, "--shard")
	if shard != "":
		var parts := shard.split("/")
		var index := int(parts[0]) - 1
		var count := int(parts[1]) if parts.size() == 2 else 0
		if count < 1 or index < 0 or index >= count:
			check(false, "--shard must look like 2/3, got '%s'" % shard)
			return
		groups = _shard(groups, index, count)
	print("Running %d groups: %s" % [groups.size(), ", ".join(groups.map(_group_label))])
	var took := {}
	for group in groups:
		var failed_before := _failed
		var started := Time.get_ticks_msec()
		if group.begins_with("_test_"):
			await call(group)
		else:
			await (get_script() as Script).get_script_constant_map()[group].run(self)
		var seconds := (Time.get_ticks_msec() - started) / 1000.0
		took[_group_label(group)] = snappedf(seconds, 0.1)
		print("== %s: %.1fs%s" % [_group_label(group), seconds, "" if _failed == failed_before else ", FAILED"])
	var out := _arg(args, "--times-out")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(took, "\t", true))


func _run() -> void:
	# `-- --only online` runs a single group while working on it.
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--only") + 1] if "--only" in args and args.find("--only") + 1 < args.size() else ""
	if only != "":
		await call("_test_" + only)
		return
	_test_registry()
	_test_health()
	_test_inventory_and_items()
	_test_flight_rig()
	await _test_raid_setup_and_movement()
	await _test_combat_and_loot()
	await _test_melee_defense()
	await _test_directional_melee()
	await _test_melee_arsenal()
	await _test_melee_feel()
	await _test_melee_viability()
	await _test_bot_aim()
	await _test_flight_rigs_and_abilities()
	await _test_rig_tiers()
	await RigBalanceTests.run(self)
	await _test_vehicle_driving()
	await _test_vehicle_roster()
	await _test_hoverbike()
	await _test_vehicle_raids()
	await _test_vehicle_toys()
	await _test_toy_throw_pose()
	await _test_vehicle_toys_online()
	await _test_lag_compensation()
	await _test_extraction()
	await _test_loadouts()
	await _test_death()
	await _test_storm()
	await _test_bots_run()
	await _test_start_screen()
	await _test_main_flow()
	await _test_every_world()
	await _test_frostline()
	await _test_mastery()
	await _test_nameplates_and_scoreboard()
	await _test_renown()
	await _test_war()
	await _test_strongpoints()
	await _test_events()
	await _test_drops()
	await _test_world_heat()
	await _test_clans()
	await _test_scrip()
	await _test_online()
	await _test_online_stash()
	await _test_online_movement()
	await _test_online_lag_compensation()
	await _test_online_riding()
	await _test_online_pillion()
	await _test_plaza()
	await _test_plaza_online()
	await _test_stash_service()
	await _test_phone()
	await _test_dev_mode()
	await _test_home_base()
	_test_refit()
	await BaseUpgradeTests.run(self)
	await ContractTests.run(self)
	await CraftingTests.run(self)
	await _test_arena()
	await _test_arena_floor()
	await _test_online_arena()
	await TravelTests.run(self)
	await BareLoadoutTests.run(self)
	await OnboardingTests.run(self)
	await TravelOnlineTests.run(self)
	await _test_look()
	await _test_rig_models()
	await _test_customizer()
	await _test_economy()
	await _test_battlefield()
	await _test_visors()
	await _test_sidearms()
	await _test_attachments()
	await _test_power_weapons()
	await _test_artifacts()
	await _test_risk_zones()
	await _test_watch()
	await _test_portals()
	await _test_feel()
	await _test_view_match()
	await _test_ads()
	await _test_grips()
	await _test_inspect()


func _test_view_match() -> void:
	await ViewMatchTests.run(self)


func _test_ads() -> void:
	await AdsTests.run(self)


func _test_grips() -> void:
	await GripTests.run(self)


func _test_inspect() -> void:
	await InspectTests.run(self)


func _test_feel() -> void:
	await FeelTests.run(self)


func _test_look() -> void:
	await LookTests.run(self)


func _test_rig_models() -> void:
	print("Flight rig models")
	await RigLookTests.run(self)


func _test_rig_tiers() -> void:
	await RigTierTests.run(self)


func _test_customizer() -> void:
	await CustomizerTests.run(self)


func _test_melee_arsenal() -> void:
	await MeleeArsenalTests.run(self)


func _test_melee_feel() -> void:
	await MeleeFeelTests.run(self)


func _test_melee_viability() -> void:
	await MeleeViabilityTests.run(self)


func _test_bot_aim() -> void:
	await BotAimTests.run(self)


func _test_economy() -> void:
	await EconomyTests.run(self)


func _test_sidearms() -> void:
	await SidearmTests.run(self)


func _test_attachments() -> void:
	await AttachmentTests.run(self)


func _test_battlefield() -> void:
	await BattlefieldTests.run(self)


func _test_visors() -> void:
	await VisorTests.run(self)


func _test_power_weapons() -> void:
	await PowerWeaponTests.run(self)


func _test_artifacts() -> void:
	await ArtifactTests.run(self)


func _test_risk_zones() -> void:
	await RiskZoneTests.run(self)


func _test_watch() -> void:
	await WatchTests.run(self)


func _test_portals() -> void:
	await PortalTests.run(self)


func check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what)


func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _new_raid(p_seed: int, bots_think: bool) -> Raid:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed)
	if not bots_think:
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	return raid


func _end_raid(raid: Raid) -> void:
	raid.queue_free()
	await frames(2)


func _test_registry() -> void:
	var declared: Array[String] = Boot.declared_classes("res://")
	check("Actor" in declared and "Ability" in declared and "MeleeWeapon" in declared,
			"the boot check finds the project's script classes")
	check(Boot.find_missing_classes().is_empty(), "every script class is registered with Godot")
	print("World registry")
	var world := Worlds.get_world("ashfront")
	check(world != null, "ashfront is discovered from its folder")
	check(Worlds.all().size() >= 1, "registry lists worlds")
	check(world != null and world.starter_loadout().size() > 0, "world provides a starter loadout")


func _test_health() -> void:
	print("Health and armor")
	var h := HealthComponent.new()
	h.set_armor(50.0)
	h.apply_damage(DamageInfo.make(50.0, null, "bullet"))
	check(is_equal_approx(h.armor, 20.0), "armor absorbs 60% of a hit and degrades")
	check(is_equal_approx(h.health, 80.0), "the rest goes to health")
	var deaths := [0]
	h.died.connect(func(_i: DamageInfo) -> void: deaths[0] += 1)
	h.apply_damage(DamageInfo.make(500.0, null, "bullet"))
	h.apply_damage(DamageInfo.make(500.0, null, "bullet"))
	check(h.is_dead and deaths[0] == 1, "death fires exactly once")
	h.free()


func _test_inventory_and_items() -> void:
	print("Inventory and items")
	var inv := Inventory.new()
	inv.capacity = 2
	check(inv.add_item("scrap_metal") and inv.add_item("power_cell"), "items fit up to capacity")
	check(not inv.add_item("medkit"), "a full backpack refuses more")
	check(inv.total_value() == 135, "backpack value adds up")
	check(inv.remove_item("scrap_metal") and not inv.has_item("scrap_metal"), "items can be removed")
	inv.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var loot := Worlds.get_world("ashfront").roll_loot("rooftop", rng)
	check(loot.size() >= 2 and loot.all(func(id: String) -> bool: return ItemDB.has_item(id)),
			"world loot rolls are valid items")


func _test_flight_rig() -> void:
	print("Flight rig")
	var rig := FlightRig.new()
	check(rig.tick(true, 0.1) == 0.0, "no thrust without a rig equipped")
	rig.enabled = true
	check(rig.tick(true, 0.1) > 0.0 and rig.heat > 0.0, "thrust builds heat")
	for i in 100:
		rig.tick(true, 0.1)
	check(rig.overheated and rig.tick(true, 0.1) == 0.0, "overheating cuts thrust")
	for i in 100:
		rig.tick(false, 0.1)
	check(not rig.overheated and rig.heat == 0.0, "the rig cools down and recovers")
	var bursts := [0]
	rig.burst_fired.connect(func() -> void: bursts[0] += 1)
	rig.try_burst()
	check(bursts[0] == 0, "a rig without a burst signals nothing")
	rig.burst_velocity = 10.0
	rig.burst_heat = 60.0
	rig.try_burst()
	rig.try_burst()
	rig.try_burst()
	check(bursts[0] == 1 and not rig.overheated, "a burst that would go far past the heat limit is refused, not fired")
	rig.heat = 0.0
	rig.burst_heat = 34.0
	var kicks := 0
	for i in 5:
		if rig.try_burst() > 0.0:
			kicks += 1
	check(kicks == 3 and rig.overheated, "the last burst of a set may tip the rig over and overheat it (%d)" % kicks)
	rig.heat = 0.0
	rig.overheated = false
	rig.launch_once = true
	rig.launched = false
	check(rig.try_burst() > 0.0 and rig.try_burst() == 0.0, "a launch-once rig launches once per takeoff")
	rig.heat = 90.0
	rig.is_hovering = true
	rig.coast(1.0)
	check(is_equal_approx(rig.heat, 90.0 - rig.coast_cool) and not rig.is_thrusting, "coasting idles the jets and cools fast")
	rig.heat = 50.0
	rig.is_gliding = true
	rig.glide_cool = 12.0
	rig.tick(false, 0.1)
	check(is_equal_approx(rig.heat, 50.0 - 1.2), "gliding cools at the glide rate with no delay")
	rig.is_gliding = false
	rig.pulse_velocity = 11.0
	rig.pulse_heat = 30.0
	rig.heat = 0.0
	var pulses := 0
	for i in 5:
		if rig.try_pulse() > 0.0:
			pulses += 1
	check(pulses == 3, "pulses are limited by heat (%d in a row)" % pulses)
	rig.free()


func _test_raid_setup_and_movement() -> void:
	print("Raid setup and movement")
	var raid := await _new_raid(42, false)
	var p := raid.player
	check(p != null and p.is_player, "player spawns")
	check(raid.bots.size() == raid.world.bot_count + raid._bosses.size(), "all bots spawn")
	check(raid.depots.size() >= 2, "map provides depots to bank at")
	var caches := raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer)
	check(caches.size() >= 8, "loot caches are placed (%d)" % caches.size())
	check(p.weapons.size() == 3 and p.flight.enabled and p.health.armor == 30.0,
			"starter loadout is equipped")

	await frames(40)
	check(p.is_on_floor(), "player lands on the ground")

	var start := p.global_position
	p.cmd.yaw = 0.0
	p.cmd.move = Vector2(0, 1)
	await frames(30)
	p.cmd.move = Vector2.ZERO
	check(p.global_position.distance_to(start) > 1.0, "player walks")

	var ground_y := p.global_position.y
	p.cmd.jump_pressed = true
	p.cmd.jump = true
	await frames(1)
	p.cmd.jump_pressed = false
	await frames(50)
	check(p.global_position.y > ground_y + 3.0, "holding jump flies with the jetpack")
	check(p.flight.heat > 0.0, "flying builds heat")
	p.cmd.jump = false
	for i in 300:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	check(p.is_on_floor(), "player comes back down")
	await _check_slide(p)
	await _check_crouch(p)
	await _end_raid(raid)


## Sliding: only from a fast run on the ground, skids from a burst down to a
## crawl, drops the eyes, and a jump ends it. Checked on the movement step
## itself, then once through the physics loop.
func _check_slide(p: Actor) -> void:
	var fast := Vector3(0, 0, -p.sprint_speed)
	var dt := 1.0 / 60.0
	p.stamina = p.max_stamina
	p.cmd.slide = true
	p._simulate_slide(Vector3(0, 0, -3.0), true, false, dt)
	check(not p.is_sliding(), "a slide needs a running start")
	p._simulate_slide(fast, false, false, dt)
	check(not p.is_sliding(), "a slide can't start in the air")
	var stand_eyes := p.get_eye_position().y
	var going := p._simulate_slide(fast, true, false, dt)
	check(p.is_sliding() and going.length() >= p.slide_speed - 0.5 and p.stamina < p.max_stamina,
			"sliding from a sprint bursts forward and costs stamina")
	p.cmd.slide = false
	var speeds: Array[float] = [going.length()]
	for i in 30:
		going = p._simulate_slide(going, true, false, dt)
		speeds.append(going.length())
	check(speeds[-1] < speeds[0] and speeds[-1] >= p.slide_end_speed, "a slide skids down toward a crawl")
	check(going.normalized().is_equal_approx(fast.normalized()), "a slide keeps its line")
	check(p.get_eye_position().y < stand_eyes - 0.3, "sliding drops the eyes")
	p.cmd.slide = true
	p.cmd.jump_pressed = true
	p._simulate_slide(going, true, false, dt)
	check(not p.is_sliding(), "jumping ends a slide")
	p.cmd.jump_pressed = false
	p._simulate_slide(fast, true, false, dt)
	check(not p.is_sliding(), "a slide can't be chained straight into another")
	p.cmd.slide = false
	for i in 120:
		p._simulate_slide(Vector3.ZERO, true, false, dt)
	check(is_zero_approx(p.slide_low) and is_equal_approx(p.get_eye_position().y, stand_eyes), "the actor stands back up")

	# Through the physics loop, as the server and every client run it.
	p.velocity = p.global_basis * Vector3(0, 0, -p.sprint_speed)
	p.cmd.move = Vector2.ZERO
	p.cmd.slide = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	p.cmd.slide = false
	check(p.is_sliding(), "pressing slide while running slides")
	var cmd := ActorCommand.new()
	cmd.slide = true
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	check(copy.slide and cmd.flags() & ActorCommand.ONE_SHOT_MASK & ActorCommand.FLAG_SLIDE != 0,
			"a slide press travels with the command, as a one-shot")
	copy.clear_one_shots()
	check(not copy.slide, "a slide press lasts one tick")
	for i in 90:
		await get_tree().physics_frame


## Crouching: the crouch key toggles it (and slides from a sprint), it walks
## slow, drops the eyes and the body so low cover hides it, keeps you down
## under a low ceiling, steadies the aim, lets you creep up on a bot, and
## travels with the command as a held key.
func _check_crouch(p: Actor) -> void:
	for i in 60:
		await get_tree().physics_frame
		if p.is_on_floor() and not p.is_sliding() and p.slide_low <= 0.0:
			break
	p.cmd.move = Vector2.ZERO
	p.velocity = Vector3.ZERO
	await frames(2)
	var stand_eyes := p.get_eye_position().y

	# The key, as the controller reads it (not in the tree, so it never reads Input).
	var keys := PlayerController.new()
	keys.setup(p)
	p.cmd.sprint = false
	p.cmd.move = Vector2(0, 1)
	keys.crouch_key(true)
	check(p.cmd.crouch and not p.cmd.slide, "the crouch key crouches when not sprinting")
	keys.crouch_key(false)
	check(p.cmd.crouch, "the crouch stays on after the key comes up (a toggle)")
	keys.crouch_key(true)
	check(not p.cmd.crouch, "pressing it again stands you up")
	keys.crouch_key(true)
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	keys.crouch_key(false)
	check(not p.cmd.crouch, "sprinting stands you up")
	p.cmd.sprint_pressed = false
	keys.crouch_key(true)
	check(p.cmd.slide and not p.cmd.crouch, "the crouch key while sprinting forward is a slide")
	p.cmd.slide = false
	p.cmd.sprint = false
	keys.crouch_key(true)
	p.cmd.jump_pressed = true
	keys.crouch_key(false)
	check(not p.cmd.crouch, "jumping stands you up")
	p.cmd.jump_pressed = false
	keys.free()

	# Crouched: lower eyes, a shorter body, a slow walk.
	p.cmd.move = Vector2.ZERO
	p.cmd.crouch = true
	await frames(20)
	check(p.crouched and is_equal_approx(p.crouch, 1.0), "the actor crouches")
	check(absf(p.get_eye_position().y - (stand_eyes - p.crouch_eye_drop)) < 0.01, "crouching drops the eyes")
	check(is_equal_approx(p.body_height(), Actor.CROUCH_HEIGHT) and is_equal_approx(p._body_shape.height, Actor.CROUCH_HEIGHT),
			"crouching lowers the body's collision")
	var steady := p.aim_steadiness()
	check(steady < 1.0, "crouched on the ground the aim is steadier")
	var gun := p.weapons[0] as Gun
	if gun:
		p.cmd.crouch = false
		await frames(20)
		var standing_spread := gun.current_spread_deg()
		p.cmd.crouch = true
		await frames(20)
		check(gun.current_spread_deg() < standing_spread, "a crouched gun spreads less")
	p.cmd.yaw = 0.0
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	await frames(30)
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(speed <= p.crouch_speed + 0.01 and speed > 1.0, "crouched you walk slowly, sprint held or not (%.1f m/s)" % speed)
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	p.velocity = Vector3.ZERO
	await frames(10)

	# Low cover: a shot over a wall too low to hide behind standing up hits
	# the standing head and passes over the crouched one.
	var from := p.global_position + Vector3(0, 1.5, -10)
	var to := p.global_position + Vector3(0, 1.5, 10)
	check(Combat.capsule_entry(from, to, p.global_position, p.body_height()).is_empty(),
			"a shot at standing head height passes over a crouched body")
	check(not Combat.capsule_entry(from, to, p.global_position).is_empty(), "and hits a standing one")
	var head_hit := {"position": p.global_position + Vector3(0, Actor.CROUCH_HEIGHT - 0.1, 0), "collider": p,
			"feet": p.global_position}
	check(Combat.is_headshot(head_hit), "a crouched head is lower down")

	# Under a low ceiling there is no room to stand: you stay down.
	var roof := StaticBody3D.new()
	roof.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.2, 4)
	shape.shape = box
	roof.add_child(shape)
	p.get_parent().add_child(roof)
	roof.global_position = p.global_position + Vector3(0, Actor.CROUCH_HEIGHT + 0.2, 0)
	await frames(2)
	check(not p.room_to_stand(), "a low ceiling leaves no room to stand")
	p.cmd.crouch = false
	await frames(20)
	check(p.crouched and p.body_height() < Actor.BODY_HEIGHT - 0.3, "under it you stay crouched")
	roof.queue_free()
	await frames(20)
	check(not p.crouched and is_zero_approx(p.crouch) and is_equal_approx(p.body_height(), Actor.BODY_HEIGHT),
			"out from under it you stand up")
	check(is_equal_approx(p.get_eye_position().y - p.global_position.y, p.eye_height), "standing puts the eyes back")

	# Bots sense a crouched actor behind them only closer in.
	var bot: Actor = null
	for other in get_tree().get_nodes_in_group("actors"):
		if other is Actor and other != p and other.get_node_or_null("Brain") is BotBrain and not other.is_dead:
			bot = other
			break
	check(bot != null, "a bot to sneak up on")
	if bot:
		var brain := bot.get_node("Brain") as BotBrain
		var bot_was := bot.global_position
		var bot_yaw := bot.cmd.yaw
		# The bot faces away (-Z is forward at yaw 0), the player behind it.
		bot.global_position = p.global_position + Vector3(0, 0, -brain.close_sense_range * 0.6)
		bot.cmd.yaw = 0.0
		bot.velocity = Vector3.ZERO
		bot.process_mode = Node.PROCESS_MODE_DISABLED
		brain.target = null
		p.cmd.crouch = false
		await frames(20)
		var heard_standing := brain._find_target() == p
		p.cmd.crouch = true
		await frames(20)
		var heard_crouched := brain._find_target() == p
		check(heard_standing and not heard_crouched, "a bot senses someone behind it standing, not crouched (%s, %s)"
				% [heard_standing, heard_crouched])
		bot.global_position = bot_was
		bot.cmd.yaw = bot_yaw
		bot.process_mode = Node.PROCESS_MODE_INHERIT

	# It travels with the command as a held key, so everyone sees the crouch.
	var cmd := ActorCommand.new()
	cmd.crouch = true
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	copy.clear_one_shots()
	check(copy.crouch and cmd.flags() & ActorCommand.HELD_MASK & ActorCommand.FLAG_CROUCH != 0,
			"a crouch travels with the command as a held key")
	var packed := NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))
	var unpacked := ActorCommand.new()
	unpacked.apply_array(packed[0][1])
	check(unpacked.crouch, "and survives the packed input")
	p.cmd.crouch = false
	await frames(20)


func _test_combat_and_loot() -> void:
	print("Combat and loot")
	var raid := await _new_raid(43, false)
	var p := raid.player
	await frames(40)
	# Stand in the exit cell, which is always open ground.
	var arena := raid.depots[0].global_position
	arena.y -= 1.9
	p.global_position = arena + Vector3(0, 0, 3)
	p.cmd.yaw = 0.0

	var bot_a := raid.bots[0]
	bot_a.global_position = p.global_position + Vector3(0, 0, -8)
	await frames(20)
	var bot_health := bot_a.health.health
	p.cmd.aim_dir = (bot_a.global_position + Vector3(0, 1, 0) - p.get_eye_position()).normalized()
	p.cmd.primary = true
	for i in 240:
		await get_tree().physics_frame
		if bot_a.is_dead:
			break
	p.cmd.primary = false
	check(bot_a.health.health < bot_health, "rifle damages a bot")
	check(bot_a.is_dead, "rifle kills a bot")
	check(raid.kills == 1, "the kill is counted")
	var gun := p.weapons[0] as Gun
	check(gun.ammo_in_mag < gun.mag_size or gun.reserve_ammo < 120, "shooting uses ammo")

	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	check(bags.size() == 1, "a dead bot drops a loot bag")
	if bags.size() == 1:
		var bag := bags[0] as LootContainer
		var before := p.inventory.items.size()
		p.global_position = bag.global_position + Vector3(0, 0, 1.5)
		await frames(10)
		p.cmd.aim_dir = (bag.global_position + Vector3(0, 0.25, 0) - p.get_eye_position()).normalized()
		await frames(1)
		check(p.find_interactable() == bag, "player can target the bag")
		p.cmd.interact_pressed = true
		await frames(1)
		p.cmd.interact_pressed = false
		check(p.inventory.items.size() > before, "looting moves items to the backpack")

	var bot_b := raid.bots[0]
	p.global_position = arena + Vector3(0, 0, 3)
	bot_b.global_position = p.global_position + Vector3(0, 0, -1.8)
	p.cmd.aim_dir = Vector3.FORWARD
	p.cmd.switch_weapon = 1
	await frames(2)
	p.cmd.switch_weapon = -1
	check(p.get_active_weapon() is MeleeWeapon, "weapon switching works")
	check(p.weapons[1].visual != null and p.weapons[1].visual.visible
			and not p.weapons[0].visual.visible, "only the weapon in hand is shown")
	# The holster key puts the weapon away and draws it again. It travels as
	# an index, not a toggle, so a repeated packet changes nothing.
	p.cmd.switch_weapon = ActorCommand.HOLSTER
	await frames(2)
	p.cmd.switch_weapon = -1
	check(p.get_active_weapon() == null and p.last_drawn == 1 and not p.weapons[1].visual.visible,
			"the holster key puts the weapon in hand away")
	p.cmd.switch_weapon = ActorCommand.HOLSTER
	await frames(2)
	check(p.get_active_weapon() == null, "holstering with nothing in hand does nothing")
	p.cmd.switch_weapon = p.last_drawn
	await frames(2)
	p.cmd.switch_weapon = -1
	check(p.get_active_weapon() == p.weapons[1], "drawing again takes out the weapon that was put away")
	var before_melee := bot_b.health.health
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	check(is_equal_approx(bot_b.health.health, before_melee), "a swing has a windup before it lands")
	await frames(12)
	check(bot_b.health.health < before_melee, "blade light attack hits")
	check(p.stamina < p.max_stamina, "attacking costs stamina")
	for i in 4:
		await frames(40)
		p.cmd.primary_pressed = true
		await frames(1)
		p.cmd.primary_pressed = false
	await frames(12)
	check(bot_b.is_dead, "blade combo kills")

	# Scavengers do not hurt each other; that is a world rule.
	if raid.bots.size() >= 2:
		var hit := Combat.deal(raid.bots[1], DamageInfo.make(10.0, raid.bots[0], "bullet"))
		check(not hit, "world rules block scav-on-scav damage")
	await _end_raid(raid)


func _test_extraction() -> void:
	print("Depots and signing out")
	Profile.reset()
	var raid := await _new_raid(44, false)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var p := raid.player
	p.inventory.add_item("reactor_core")
	p.inventory.add_item("medkit")
	var bot := raid.bots[0]
	var depot_pos := raid.depots[1].global_position
	p.global_position = Vector3(depot_pos.x, depot_pos.y - 1.8, depot_pos.z)
	bot.global_position = Vector3(depot_pos.x + 2.0, depot_pos.y - 1.8, depot_pos.z)
	await frames(60)
	check(raid.bank_progress() > 0.0, "standing in a depot starts the hold")
	check(Profile.stash.is_empty(), "banking is not instant")
	check(is_zero_approx(raid.depots[1].progress_for(bot)), "a bot cannot use a depot")
	await frames(240)
	check("reactor_core" in Profile.stash and not p.inventory.has_item("reactor_core"),
			"the depot sends the backpack to the stash")
	check(p.inventory.has_item("medkit") and "medkit" not in Profile.stash, "healing stays with you")
	check(results.is_empty() and not p.is_dead, "banking does not end your stay")
	await frames(30)
	check(is_zero_approx(raid.bank_progress()), "with nothing left to bank the depot does nothing")

	check(raid.begin_sign_out(p) and raid.sign_out_progress(p) >= 0.0, "a sign-out starts out of a fight")
	Combat.deal(p, DamageInfo.make(5.0, bot, "bullet"))
	check(raid.sign_out_progress(p) < 0.0, "taking a hit cancels the sign-out")
	check(not raid.begin_sign_out(p), "a sign-out cannot start in a fight")
	raid.clock += raid.world.combat_time + 1.0
	p.inventory.add_item("alloy_ingot")
	check(raid.begin_sign_out(p), "once the fight is over it can")
	raid.cancel_sign_out(p)
	check(raid.sign_out_progress(p) < 0.0, "a sign-out can be called off")
	raid.begin_sign_out(p)
	raid.state_for(p).sign_out_left = 0.2
	await frames(30)
	check(results.size() == 1 and results[0].outcome == "left", "a finished sign-out ends the life as left")
	check("reactor_core" in results[0].banked and results[0].banked_value == ItemDB.item_value("reactor_core"),
			"the result lists what was banked")
	check("alloy_ingot" in Profile.stash and "medkit" in Profile.stash, "what you carried comes home")
	check(Profile.stash.size() == 3, "the free scrap kit is never stashed")
	check(Profile.raids_extracted == 1, "the profile records leaving alive")
	await _end_raid(raid)


func _test_death() -> void:
	print("Death and dropping back in")
	Profile.reset()
	var raid := await _new_raid(45, false)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var p := raid.player
	var bot := raid.bots[0]
	p.inventory.add_item("lattice_shard")
	Combat.deal(p, DamageInfo.make(9999.0, bot, "bullet"))
	await frames(2)
	check(p.is_dead, "player can die")
	check(results.size() == 1 and results[0].outcome == "died" and results[0].killed_by == bot.display_name,
			"the life ends as died and names the killer")
	check(Profile.stash.is_empty(), "nothing reaches the stash on death")
	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	check(bags.size() == 1 and "lattice_shard" in (bags[0] as LootContainer).items
			and "rifle_scrap" in (bags[0] as LootContainer).items,
			"the player's gear and loot drop in a bag")
	check(Hud.death_text(results[0], 0.0).contains(bot.display_name) and Hud.death_text(results[0], 0.0).contains("Enter")
			and not Hud.death_text(results[0], 2.0).contains("Enter"),
			"the death screen names the killer and offers to drop back in once the wait is over")

	# The world carries on, and the same player drops back into it.
	var again := raid.add_player([], {}, "You")
	await frames(2)
	check(raid.player == again and not again.is_dead and raid.players.size() == 1,
			"dropping back in starts a new life in the same world")
	check(not is_instance_valid(p) or p.is_queued_for_deletion(), "the old body is cleared away")
	check(is_instance_valid(bags[0]) and "lattice_shard" in (bags[0] as LootContainer).items,
			"the bag is still where you fell")
	check(again.protected_left > 0.0 and not Combat.deal(again, DamageInfo.make(10.0, bot, "bullet"))
			and is_equal_approx(again.health.health, again.health.max_health),
			"a player who just dropped in cannot be hurt")
	Combat.deal(bot, DamageInfo.make(1.0, again, "bullet"))
	check(is_zero_approx(again.protected_left) and Combat.deal(again, DamageInfo.make(10.0, bot, "bullet")),
			"attacking gives the protection up")
	again.kill("test")
	await frames(2)
	check(results.size() == 2 and Profile.raids_played == 2, "every life is recorded")
	await _end_raid(raid)


func _test_storm() -> void:
	print("A world that never ends")
	var raid := await _new_raid(46, false)
	var world := raid.world
	var p := raid.player
	var count := raid.bots.size()
	raid.bots[0].kill("test")
	await frames(2)
	check(raid.bots.size() == count - 1 and raid._bot_respawns.size() == 1, "a dead bot is queued to be replaced")
	raid._bot_respawns[0] = 0.05
	await frames(10)
	var newest: Actor = raid.bots[-1]
	check(raid.bots.size() == count and not newest.is_dead and newest.has_node("Brain"),
			"a new bot takes its place")
	check(newest.global_position.distance_to(p.global_position) > 20.0, "it arrives away from the player")

	var cache: LootContainer = raid._caches[0].container
	cache.set_items([])
	await frames(3)
	check(raid._caches[0].refill_in > 0.0, "an emptied cache starts to refill")
	raid._caches[0].refill_in = 0.05
	await frames(10)
	check(not cache.items.is_empty(), "the cache fills up again")

	var spot: Dictionary = raid._parking[0]
	var bike: Node3D = spot.vehicle
	check(raid._is_parked(bike), "a bike waits at each parking spot")
	bike.global_position = p.global_position + Vector3(2.0, 0.5, 0.0)
	spot.empty_for = world.vehicle_respawn_time - 0.05
	await frames(10)
	check(spot.vehicle != bike and raid._is_parked(spot.vehicle), "a bike that left its spot is replaced there")
	raid._idle[bike] = world.vehicle_respawn_time
	await frames(3)
	check(not is_instance_valid(bike) or bike.is_queued_for_deletion(), "a bike nobody rides is cleared away")
	check(spot.vehicle in raid.vehicles, "a parked bike is never cleared away")

	var is_bag := func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag and not n.is_queued_for_deletion()
	var old_bags := raid.get_children().filter(is_bag)
	var lifetime := world.bag_lifetime
	world.bag_lifetime = 0.2
	raid.bots[1].kill("test")
	await frames(2)
	var bags := raid.get_children().filter(func(n: Node) -> bool: return is_bag.call(n) and n not in old_bags)
	check(bags.size() >= 1, "a dead bot drops a bag")
	var bag_ids := bags.map(func(n: Node) -> int: return n.get_instance_id())
	world.bag_lifetime = lifetime
	await get_tree().create_timer(0.5).timeout
	await frames(2)
	check(bag_ids.all(func(id: int) -> bool: return not is_instance_id_valid(id)), "old bags are cleared away")
	raid.clock = 100000.0
	await frames(5)
	check(not p.is_dead, "no storm ever comes for the player")
	await _end_raid(raid)


func _test_bots_run() -> void:
	print("Bot AI")
	var raid := await _new_raid(47, true)
	var starts := {}
	for bot in raid.bots:
		starts[bot] = bot.global_position
	# Bring one bot face to face with the player to exercise the fight logic.
	var p := raid.player
	await frames(40)
	var bot := raid.bots[0]
	var arena := raid.depots[0].global_position
	p.global_position = Vector3(arena.x, arena.y - 1.9, arena.z + 3.0)
	bot.global_position = Vector3(arena.x, arena.y - 1.9, arena.z - 5.0)
	var health_before := p.health.health + p.health.armor
	await frames(360)
	var moved := 0
	for b: Actor in starts:
		if is_instance_valid(b) and b.global_position.distance_to(starts[b]) > 1.5:
			moved += 1
	check(moved >= 3, "bots patrol (%d moved)" % moved)
	check(p.health.health + p.health.armor < health_before, "a bot that sees the player attacks")
	await _end_raid(raid)


func _test_main_flow() -> void:
	print("Hub and raid flow")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(2)
	check(main.base != null and main.raid == null and not main.hub.visible and main.controller != null
			and main.controller.camera.current, "the game opens in your home base, not on a menu")
	check(main.base.station("launch") == null and main.base.door.get_prompt().contains("Head out"),
			"the base has no launch pad, and its door leads out to the plaza")
	await PortalTests.through_base(self, main)
	main._leave_raid()
	main.go_home()
	await frames(2)
	# Something in hand to test with: a new player starts bare.
	Profile.loadout = StashRules.starter_loadout()
	main.start_raid("ashfront")
	await frames(5)
	check(main.raid != null and not main.hub.visible, "deploying starts a raid")
	check(main.controller.camera.current and main.hud != null, "raid has a camera and HUD")
	check(main.nameplates != null and main.scoreboard != null and not main.scoreboard.visible,
			"raid has nameplates and a scoreboard, closed until Q is held")
	var controller: PlayerController = main.controller
	check(controller.view_mode == PlayerController.ViewMode.FIRST and not controller.is_third_person(),
			"camera starts in first-person")
	controller.base_fov = 70.0
	controller.base_fov_third = 100.0
	check(is_equal_approx(controller.wanted_base_fov(), 70.0), "first person uses its own field of view")
	controller.toggle_view()
	check(is_equal_approx(controller.wanted_base_fov(), 100.0), "third person uses its own field of view")
	check(is_equal_approx(controller.view_distance(false), controller.third_person_distance)
			and controller.third_person_distance <= 2.5, "the third-person camera sits close, over the shoulder")
	check(controller.view_distance(true) < controller.view_distance(false) and controller.view_distance(true) > 0.5,
			"aiming moves it in further")
	controller.third_person_distance = 4.0
	check(is_equal_approx(controller.view_distance(false), 4.0), "and its distance can be set")
	controller.third_person_distance = 2.0
	controller.toggle_view()
	# Melee and flight must not move the camera on their own.
	var p: Actor = main.raid.player
	await frames(40)
	Input.action_press("weapon_3")
	Input.action_press("jump")
	await frames(40)
	Input.action_release("weapon_3")
	Input.action_release("jump")
	check(p.get_active_weapon() is MeleeWeapon and not p.is_on_floor(),
			"real input reaches the actor (blade out, airborne)")
	check(not controller.is_third_person(), "camera stays put when using the blade or flying")
	# Melee side from the movement keys by default (Caleb: Jedi Academy
	# style controls as the baseline), the mouse flick after switching. A
	# save from before the default changed may still say "mouse": start
	# from the default either way.
	if controller.stance_control != PlayerController.StanceControl.MOVE:
		controller.toggle_stance_control()
	Input.action_press("move_left")
	await frames(5)
	check(p.cmd.stance == MeleeWeapon.Dir.LEFT and Profile.melee_control == "move",
			"by default strafing picks the melee side")
	Input.action_release("move_left")
	controller.toggle_stance_control()
	Input.action_press("move_right")
	await frames(5)
	check(p.cmd.stance == MeleeWeapon.Dir.LEFT and Profile.melee_control == "mouse",
			"after switching to the mouse flick, the movement keys leave the side alone, and the choice is remembered")
	Input.action_release("move_right")
	controller.toggle_stance_control()
	check(Profile.melee_control == "move", "switching again goes back to the movement keys")
	# Riding pulls the camera back without touching the on-foot choice.
	var bike = main.raid.spawn_vehicle("bike_scrapper", p.global_position + Vector3(3, 0.3, 0), 0.0)
	await frames(5)
	check(bike.mount(p), "the player gets on a bike")
	await frames(40)
	check(controller.is_third_person() and controller.view_mode == PlayerController.ViewMode.FIRST,
			"riding uses third-person and keeps the on-foot view choice")
	controller.toggle_view()
	await frames(40)
	check(not controller.is_third_person(), "V still switches the view while riding")
	controller.toggle_view()
	bike.dismount()
	await frames(40)
	check(not controller.is_third_person(), "getting off returns to the on-foot view")
	controller.toggle_view()
	await frames(40)
	check(controller.is_third_person(), "the toggle switches to third-person")
	# The HUD lives on your gear: a holographic watch and a counter on the gun.
	var wrist: Hud.Wrist = main.hud.wrist
	var holo := wrist.get_node("Hologram") as Node3D
	check(not controller.wrist_raised and not holo.visible, "the watch's hologram is down until you raise it")
	var x_key := InputEventAction.new()
	x_key.action = "check_wrist"
	x_key.pressed = true
	controller._unhandled_input(x_key)
	await frames(30)
	check(controller.wrist_raised and wrist.is_open() and holo.visible and wrist.get_parent() == p
			and wrist.text().contains(main.raid.world.display_name) and wrist.text().contains("Pack "),
			"X raises the watch, and in third person its card opens over your wrist")
	# Judged on a wide screen like a player's (headless, the window is a
	# small square).
	var window_was := get_tree().root.size
	get_tree().root.size = Vector2i(1600, 900)
	await frames(3)
	var card_width := holo.global_basis.get_scale().x * wrist.face_size.x
	var cam := controller.camera
	var card_left := cam.unproject_position(holo.global_position - cam.global_basis.x * card_width * 0.5)
	var card_right := cam.unproject_position(holo.global_position + cam.global_basis.x * card_width * 0.5)
	var screen := cam.get_viewport().get_visible_rect().size
	check(cam.global_position.distance_to(holo.global_position) > cam.global_position.distance_to(p.get_eye_position())
			and (card_right.x - card_left.x) > screen.x * 0.25 and card_left.x >= 0.0,
			"the third-person card stands past the character, big enough to read and whole on screen (%d px wide)"
			% roundi(card_right.x - card_left.x))
	var head_on_screen := cam.unproject_position(p.get_eye_position())
	# Only the card's bare right margin (`tp_tuck`) may sit behind the head;
	# its text stays clear of the character.
	var text_right := card_right.x - (card_right.x - card_left.x) * wrist.tp_tuck
	check(text_right < head_on_screen.x and text_right < screen.x * 0.5,
			"and beside the character, its text clear of the head and the crosshair (text to %d, head at %d, of %d)"
			% [roundi(text_right), roundi(head_on_screen.x), roundi(screen.x)])
	# Close to the body: its lower edge sits just over the watch.
	var edge_low := cam.unproject_position(holo.global_position - holo.global_basis.y * wrist.face_size.y * 0.5)
	var watch_at := cam.unproject_position(wrist.watch_position(p))
	check(edge_low.y < watch_at.y and watch_at.y - edge_low.y < screen.y * 0.1,
			"it sits close to the body, its lower edge just over the watch (%d px over it)" % roundi(watch_at.y - edge_low.y))
	# The light rises from the watch up into the card's lower edge (Caleb's
	# feedback: never slanting down to it), and runs outwards along it.
	var card_low := cam.unproject_position(holo.global_position - holo.global_basis.y * wrist.face_size.y * 0.5)
	var watch_seen := cam.unproject_position(wrist.watch_position(p))
	check(card_low.y < watch_seen.y and wrist.BEAM_SHADER.contains("TIME"),
			"the light rises from the watch up into the card, with bands running out along it (card edge at %d, watch at %d)"
			% [roundi(card_low.y), roundi(watch_seen.y)])
	# The weapon and toy holograms over the card are smaller than from the
	# eyes and stay in the view (Caleb's feedback: they were cut off at the
	# top); the card keeps its size.
	var rows_top := cam.unproject_position(holo.global_position + holo.global_basis.y
			* (wrist.face_size.y * 0.5 + wrist.rows_tall * wrist._row_scale))
	check(wrist._row_scale <= wrist.tp_rows and wrist._row_scale < 1.0 and rows_top.y >= 0.0,
			"the holograms over the card are drawn smaller and stay on screen (%.2f of their size, top at %d)"
			% [wrist._row_scale, roundi(rows_top.y)])
	get_tree().root.size = window_was
	await frames(2)
	var holo_mat := holo.material_override as ShaderMaterial
	check(not holo_mat.shader.code.contains("depth_test_disabled") and float(holo_mat.get_shader_parameter("backing")) > 0.3
			and float(holo_mat.get_shader_parameter("backing")) < 0.8,
			"in third person it is backed but still see-through, and the body in front of it hides what it covers")
	check(p.cmd.watch_up, "and the raised watch goes out with your inputs, so the arm glows for everyone")
	var icons: Array = []
	for slot in wrist.card.slots:
		icons.append(slot.id)
	check(icons == Hud.Wrist.SLOTS, "the card is a row of icons: %s" % ", ".join(icons))
	check(wrist.card.bars.size() >= 3, "in third person the card carries the vitals strip, since there is no glass")
	# The mouse wheel steps across the card; the mouse only looks.
	var yaw_before := controller.yaw
	var weapon_before := p.active_weapon_index
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(-200.0, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		controller._unhandled_input(look)
		check(controller.yaw > yaw_before and not controller.watch_focus_moved,
				"with the watch up the mouse turns the view and leaves the card alone")
	controller.yaw = yaw_before
	for i in 20:
		controller.scroll(-1)
	await frames(2)
	check(controller.watch_focus == 0 and wrist.focused_id() == "weapon" and controller.weapon_pick == 0
			and wrist.card.focused_tab() == "summon",
			"scrolling up steps the card left to the weapons, on the Summon tab")
	controller.scroll(-1)
	check(controller.watch_focus == 0, "and it stops at the card's left end")
	controller.scroll(1)
	await frames(2)
	check(wrist.focused_id() == "vehicle" and controller.weapon_pick == 0,
			"scrolling down steps right an icon a notch, past the weapons without turning through them")
	for i in 10:
		if wrist.card.focused_tab() == "status":
			break
		controller.scroll(1)
		await frames(2)
	check(wrist.card.focused_tab() == "status" and wrist.focused_id() == "map"
			and wrist.text().begins_with(main.raid.world.display_name) and wrist.card.bars.size() >= 3,
			"past the Summon tab the wheel steps on to Status: the map and your standing, under the vitals strip")
	for i in 20:
		controller.scroll(1)
	await frames(2)
	check(wrist.focused_id() == "leave" and wrist.card.focused_tab() == "mission",
			"and stops at the right end on sign-out, on the Mission tab")
	check(controller._pending_switch < 0 and p.active_weapon_index == weapon_before and is_equal_approx(controller.yaw, yaw_before),
			"with the watch up the wheel never switches weapons or turns the view")
	controller.toggle_view()
	await frames(40)
	check(wrist.get_parent() == p and holo.visible,
			"in first person the card rises off the watch on your own wrist, as in third person")
	var card_angle := holo.global_basis.get_scale().x * wrist.face_size.x / controller.camera.global_position.distance_to(holo.global_position)
	check(card_angle < 0.6, "the card is card-sized, not a panel (%.2f)" % card_angle)
	check(wrist.get_node("Beam").visible and (wrist.get_node("Beam") as MeshInstance3D).mesh.get_surface_count() > 0
			and is_equal_approx(float((holo.material_override as ShaderMaterial).get_shader_parameter("open")), 1.0),
			"light is thrown up from the watch face to the card, which is drawn as a hologram")
	check(Hud.Wrist.face_tint(0.1).r > 0.9 and Hud.Wrist.face_tint(1.0).b > 0.9,
			"the watch face glows red when you are low and cyan when you are well")
	controller._unhandled_input(x_key)
	await frames(30)
	check(not controller.wrist_raised and not holo.visible, "X again puts it away")
	var leaving := Hud.watch_slots(main.raid, p, 0, "", 0.5)
	var leave_at := Hud.Wrist.SLOTS.find("leave")
	check(is_equal_approx(float(leaving[leave_at].progress), 0.5) and Hud.default_focus(leaving) == leave_at,
			"signing out fills a ring on the sign-out icon, and the card opens on it")
	check(Hud.watch_slots(main.raid, p)[Hud.Wrist.SLOTS.find("artifact")].empty,
			"with no artifact on, the artifact slot is an empty socket")
	# One long frame must not throw the landing dip's spring (and the camera).
	controller._dip_speed = 9.0
	controller._update_dip(0.5)
	check(is_finite(controller._dip) and absf(controller._dip) < 0.3, "a long frame leaves the landing dip steady")
	var gun: Gun = null
	for w in p.weapons:
		if w is Gun:
			gun = w
	if gun != null and gun.visual != null:
		var counter := gun.visual.get_node_or_null(Hud.AMMO_COUNTER) as Label3D
		check(counter != null and counter.text == Hud.ammo_text(gun) and counter.text.begins_with(str(gun.ammo_in_mag)),
				"the gun counts its own rounds")
	# A jetpack's screen bay shows its heat. Headless there is no skin to
	# build the model, so a bay is fitted by hand as the rig model names it.
	var bay := Marker3D.new()
	bay.name = Hud.HEAT_DISPLAY
	bay.set_meta("size", Vector2(0.13, 0.15))
	p.add_child(bay)
	var had_flight := p.flight.enabled
	p.flight.enabled = true
	var cooling := p.flight.cool_per_sec
	p.flight.cool_per_sec = 0.0
	p.flight.heat = p.flight.max_heat * 0.5
	await frames(2)
	var gauge := bay.get_node_or_null(Hud.HEAT_READOUT)
	check(gauge != null and (gauge.get_node("Word") as Label3D).text == Hud.heat_text(p.flight)
			and Hud.heat_text(p.flight) == "50%", "the jetpack's screen bay shows its heat")
	check(is_equal_approx((gauge.get_node("Fill") as Node3D).scale.y, 0.5), "its gauge fills with the heat")
	p.flight.overheated = true
	check(Hud.heat_text(p.flight) == "HOT" and Hud.heat_color(0.5, true).r > 0.9, "an overheated pack reads HOT in red")
	p.flight.overheated = false
	p.flight.heat = 0.0
	p.flight.cool_per_sec = cooling
	p.flight.enabled = had_flight
	bay.queue_free()
	var buzzed: Array[String] = []
	main.hud.notice_sink = func(text: String) -> void: buzzed.append(text)
	main.raid.war_feed.emit("Test news")
	check(buzzed.size() == 1 and buzzed[0] == "Test news", "war news goes to the phone, not over the screen")
	main.hud.notice_sink = main.phone.show_notice
	var corpse: Actor = main.raid.player
	corpse.kill("test")
	await frames(10)
	check(main.raid != null and not main.hub.visible, "dying keeps you in the world")
	check((wrist.text().contains("You died") or wrist.text().contains("Killed by")) and wrist.raised,
			"going down raises the watch, and what the death cost is read off it")
	main._on_redeploy_requested()
	check(main.raid.player == corpse, "you cannot drop back in at once")
	main._redeploy_at = 0
	main._on_redeploy_requested()
	await frames(5)
	var reborn: Actor = main.raid.player
	check(reborn != corpse and not reborn.is_dead and main.controller.actor == reborn
			and main.controller.camera.current and main.hud.raid == main.raid,
			"Enter drops you back in with the camera and HUD on your new body")
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless",
			"the mouse stays captured across a redeploy")
	main._on_sign_out_requested()
	check(main.raid.sign_out_progress(reborn) >= 0.0, "L starts a sign-out")
	main._on_sign_out_requested()
	check(main.raid.sign_out_progress(reborn) < 0.0, "L again calls it off")
	main._on_sign_out_requested()
	main.raid.state_for(reborn).sign_out_left = 0.1
	await frames(90)
	check(main.raid == null and main.base != null and not main.hub.visible,
			"a finished sign-out takes you home to your base")
	main.start_raid("ashfront")
	await frames(5)
	main.raid.player.kill("test")
	await frames(5)
	main._on_sign_out_requested()
	await frames(2)
	check(main.raid == null and main.base != null, "L while down takes you home")
	main.queue_free()
	await frames(2)


## Sets up the player with the blade out, facing a brute that stands in reach.
func _duel(raid: Raid) -> Array:
	var p := raid.player
	await frames(40)
	var arena := raid.depots[0].global_position
	p.global_position = Vector3(arena.x, arena.y - 1.9, arena.z + 3.0)
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD
	p.cmd.switch_weapon = 1
	var foe := raid.bots[0]
	foe.global_position = p.global_position + Vector3(0, 0, -2.0)
	foe.cmd.yaw = PI
	foe.cmd.aim_dir = Vector3.BACK
	# It was a far-off bot a moment ago; the test drives it tick by tick.
	foe.thin(1)
	# Give the foe a blade regardless of what the world rolled for it.
	for w in foe.weapons:
		w.queue_free()
	foe.weapons.clear()
	var blade := MeleeWeapon.new()
	blade.light_windup = 0.5
	blade.light_stamina = 0.0
	foe.equip_weapon(blade)
	foe.active_weapon_index = 0
	await frames(3)
	p.cmd.switch_weapon = -1
	return [p, foe, blade]


func _foe_swing(foe: Actor) -> void:
	foe.cmd.primary_pressed = true
	await frames(1)
	foe.cmd.primary_pressed = false


func _test_melee_defense() -> void:
	print("Block, parry and stamina")
	var raid := await _new_raid(48, false)
	var setup: Array = await _duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var total := func() -> float: return p.health.health + p.health.armor

	# Unblocked hit.
	var before: float = total.call()
	await _foe_swing(foe)
	await frames(40)
	check(total.call() < before, "an unblocked swing hurts")

	# Held block: guard raised long before the hit lands.
	await frames(60)
	before = total.call()
	var stamina_before := p.stamina
	p.cmd.secondary = true
	await frames(30)
	await _foe_swing(foe)
	await frames(40)
	check(is_equal_approx(total.call(), before), "a held block stops a melee hit")
	check(p.stamina < stamina_before, "blocking costs stamina")
	check(foe.stagger_left <= 0.0, "a plain block does not stagger the attacker")
	p.cmd.secondary = false

	# Parry: guard raised just before the hit lands (windup is 30 frames).
	await frames(90)
	before = total.call()
	stamina_before = p.stamina
	await _foe_swing(foe)
	await frames(22)
	p.cmd.secondary = true
	await frames(12)
	p.cmd.secondary = false
	check(is_equal_approx(total.call(), before), "a parry takes no damage")
	check(foe.stagger_left > 0.0, "a parry staggers the attacker")
	check(p.riposte_left > 0.0, "a parry readies a riposte")
	var foe_before := foe.health.health
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	await frames(12)
	var blade := p.get_active_weapon() as MeleeWeapon
	check(is_equal_approx(foe_before - foe.health.health, blade.light_damage * blade.riposte_mult),
			"the riposte hits harder")

	# A staggered attacker cannot swing.
	foe.stagger(1.0)
	before = total.call()
	await _foe_swing(foe)
	await frames(40)
	check(is_equal_approx(total.call(), before), "a staggered attacker cannot attack")

	# Blocking from behind does nothing.
	await frames(60)
	before = total.call()
	p.cmd.yaw = PI
	p.cmd.aim_dir = Vector3.BACK
	p.cmd.secondary = true
	await frames(30)
	await _foe_swing(foe)
	await frames(40)
	check(total.call() < before, "a block does not cover your back")
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD

	# Bullets: a held guard only stops part of one.
	await frames(60)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	var blocked_loss: float = before - total.call()
	check(blocked_loss > 0.0 and blocked_loss < 20.0, "a blade turns aside part of a bullet")

	# Guard break: no stamina left to pay for the block.
	p.stamina = 2.0
	before = total.call()
	Combat.deal(p, DamageInfo.make(30.0, foe, "melee"))
	check(total.call() < before and p.stagger_left > 0.0, "an empty stamina bar means a guard break")
	p.cmd.secondary = false

	# Stamina comes back.
	p.stagger_left = 0.0
	await frames(180)
	check(p.stamina > 40.0, "stamina regenerates")

	# Hit confirmation reaches the attacker.
	var hits := [0]
	p.hit_confirmed.connect(func(_t: Actor, _i: DamageInfo, _l: bool) -> void: hits[0] += 1)
	Combat.deal(foe, DamageInfo.make(5.0, p, "bullet"))
	check(hits[0] == 1, "the attacker is told when a hit lands")
	await _end_raid(raid)

	# Recoil bloom.
	var gun_raid := await _new_raid(49, false)
	var shooter := gun_raid.player
	await frames(40)
	var gun := shooter.weapons[0] as Gun
	var calm := gun.current_spread_deg()
	shooter.cmd.primary = true
	await frames(40)
	check(gun.current_spread_deg() > calm, "sustained fire widens the spread")
	shooter.cmd.primary = false
	await frames(60)
	check(is_equal_approx(gun.current_spread_deg(), calm), "the spread settles when you stop")
	await _end_raid(gun_raid)

	# A brute rushes and swings on its own.
	var brute_raid := await _new_raid(50, true)
	var duel: Array = await _duel(brute_raid)
	var victim: Actor = duel[0]
	var brute: Actor = duel[1]
	brute.global_position = victim.global_position + Vector3(0, 0, -7.0)
	var victim_before := victim.health.health + victim.health.armor
	await frames(300)
	check(victim.health.health + victim.health.armor < victim_before, "a melee bot closes in and hits")
	await _end_raid(brute_raid)


func _test_loadouts() -> void:
	print("Loadouts")
	var world := Worlds.get_world("ashfront")
	Profile.reset()
	Profile.grant_welcome_crate()
	var crate_size := Profile.stash.size()
	Profile.grant_welcome_crate()
	check(crate_size > 0 and Profile.stash.size() == crate_size, "the welcome crate is granted once")

	Profile.reset()
	Profile.welcome_granted = true
	# Wearing the scrap kit (a new player starts bare and puts it on by hand).
	Profile.loadout = StashRules.starter_loadout()
	Profile.add_to_stash(["rifle_carbine", "frame_bulwark", "hammer_breaker", "medkit", "medkit", "medkit", "scrap_metal"])
	check(not Profile.equip("primary", "hammer_breaker"), "an item cannot go in the wrong slot")
	check(not Profile.equip("primary", "dmr_longshot"), "an item you do not own cannot be equipped")
	check(Profile.equip("primary", "rifle_carbine") and Profile.equip("frame", "frame_bulwark")
			and Profile.equip("melee", "hammer_breaker"), "owned gear equips into its slot")

	var kit := Profile.checkout_loadout(world)
	check("rifle_carbine" in kit and "frame_bulwark" in kit and "hammer_breaker" in kit,
			"deploying takes the chosen gear")
	check("jetpack_mk1" in kit, "a scrap piece left on deploys with the rest")
	check(kit.count("medkit") == 2 and "field_dressing" not in kit, "up to two medkits come along")
	check(Profile.stash == (["medkit", "scrap_metal"] as Array[String]), "deployed gear leaves the stash")

	# Leave alive with the gear: it all comes home.
	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 60, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	var p := raid.player
	var gun := p.weapons[0] as Gun
	var hammer := p.weapons[1] as MeleeWeapon
	check(gun.display_name == "Ashfront Carbine" and is_equal_approx(gun.damage, 24.0), "weapon stats come from the item")
	check(hammer.display_name == "Breaker Hammer" and is_equal_approx(hammer.heavy_damage, 95.0), "melee stats come from the item")
	check(is_equal_approx(p.health.armor, float(ItemDB.item_stats("frame_bulwark").armor)), "the frame sets armor")
	var base := Actor.new()
	check(p.walk_speed < base.walk_speed and is_equal_approx(p.flight.heat_per_sec, FlightRig.new().heat_per_sec),
			"a heavy frame is slower, and a jetpack carries it without running hotter")
	var wings := Actor.new()
	Loadout.equip(wings, ["wings_glide", "frame_bulwark"])
	check(wings.flight.glide_heat > ItemDB.item_stats("wings_glide")["glide_heat"],
			"a heavy frame runs other rigs hotter: the wings' glide stamina drains faster")
	wings.free()
	base.free()
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	raid.begin_sign_out(p)
	raid.state_for(p).sign_out_left = 0.1
	await frames(20)
	check(results.size() == 1 and results[0].outcome == "left", "a life with a loadout ends by signing out")
	check("rifle_carbine" in Profile.stash and "frame_bulwark" in Profile.stash and "hammer_breaker" in Profile.stash,
			"leaving alive brings your gear home")
	check("jetpack_mk1" not in Profile.stash and "rifle_scrap" not in Profile.stash, "scrap gear does not come home")
	check(Profile.equipped("primary") == "rifle_carbine", "the loadout stays equipped after leaving")
	await _end_raid(raid)

	# Die with the gear: it is gone and the slot empties.
	kit = Profile.checkout_loadout(world)
	raid = Raid.new()
	add_child(raid)
	raid.start(world, 61, kit)
	await frames(3)
	raid.player.kill("test")
	await frames(2)
	check("rifle_carbine" not in Profile.stash and "frame_bulwark" not in Profile.stash, "dying loses your gear")
	check(Profile.equipped("primary") == "rifle_scrap" and Profile.equipped("frame") == "plate_light",
			"lost gear leaves the loadout, and the free scrap piece takes its slot")
	await _end_raid(raid)

	# A new player has nothing on, so deploys bare; the scrap kit put on by
	# hand deploys as the full free scrap kit.
	Profile.reset()
	Profile.welcome_granted = true
	kit = Profile.checkout_loadout(world)
	check(kit.all(func(id: String) -> bool: return ItemDB.has_tag(id, "heal")),
			"a new player with nothing equipped deploys bare (healing aside): %s" % [kit])
	Profile.loadout = StashRules.starter_loadout()
	kit = Profile.checkout_loadout(world)
	check(kit == world.starter_loadout(), "with the scrap kit put on, an empty stash deploys the scrap kit")

	# Healing uses any heal item and its own strength.
	raid = await _new_raid(62, false)
	p = raid.player
	await frames(40)
	Combat.deal(p, DamageInfo.make(80.0, null, "bullet"))
	var hurt := p.health.health
	p.cmd.heal_pressed = true
	await frames(1)
	p.cmd.heal_pressed = false
	await frames(200)
	check(is_equal_approx(p.health.health - hurt, 30.0) and p.inventory.count_with_tag("heal") == 0,
			"a field dressing heals its own amount and is used up")

	# Shotgun: several pellets per shot.
	var shotgun := Gun.new()
	Loadout._setup_weapon(shotgun, "shotgun_breacher", ItemDB.item_stats("shotgun_breacher"))
	p.equip_weapon(shotgun)
	p.cmd.switch_weapon = p.weapons.size() - 1
	var arena := raid.depots[0].global_position
	p.global_position = Vector3(arena.x, arena.y - 1.9, arena.z + 3.0)
	var target := raid.bots[0]
	target.global_position = p.global_position + Vector3(0, 0, -3.0)
	await frames(10)
	p.cmd.switch_weapon = -1
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = (target.global_position + Vector3(0, 1, 0) - p.get_eye_position()).normalized()
	var before := target.health.health
	p.cmd.primary = true
	await frames(1)
	p.cmd.primary = false
	await frames(2)
	check(before - target.health.health > shotgun.damage * 3.0, "a shotgun lands several pellets at once")
	check(shotgun.ammo_in_mag == 5, "a shotgun blast uses one shell")
	await _end_raid(raid)

	# The hub offers what you own.
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "dmr_longshot", "frame_runner"])
	var hub := Hub.new()
	add_child(hub)
	await frames(2)
	check(hub.options_for("primary") == (["dmr_longshot", "rifle_carbine", "rifle_scrap"] as Array[String])
			and hub.options_for("frame") == (["frame_runner", "plate_light"] as Array[String]),
			"the hub lists owned gear per slot, and the free scrap piece")
	hub._on_picked(1, "primary")
	check(Profile.equipped("primary") == "dmr_longshot", "picking in the hub equips the item")
	hub._on_picked(0, "primary")
	check(Profile.equipped("primary") == "", "picking None unequips")
	hub.queue_free()
	Profile.reset()
	Profile.welcome_granted = true


func _test_directional_melee() -> void:
	print("Directional melee")
	var over := MeleeWeapon.Dir.OVERHEAD
	var left := MeleeWeapon.Dir.LEFT
	var right := MeleeWeapon.Dir.RIGHT
	check(MeleeWeapon.mirror(left) == right and MeleeWeapon.mirror(right) == left
			and MeleeWeapon.mirror(over) == over, "left and right mirror, overhead does not")
	check(MeleeWeapon.guard_covers(right, left) and not MeleeWeapon.guard_covers(left, left)
			and MeleeWeapon.guard_covers(left, -1), "a guard covers the side the swing arrives on")

	# Mouse flicks pick the stance.
	check(PlayerController.stance_from_flick(Vector2(-80, 10), over, 45.0) == left
			and PlayerController.stance_from_flick(Vector2(80, -10), over, 45.0) == right
			and PlayerController.stance_from_flick(Vector2(5, -80), left, 45.0) == over,
			"flicking the mouse left, right or up picks that side")
	check(PlayerController.stance_from_flick(Vector2(10, 5), left, 45.0) == left
			and PlayerController.stance_from_flick(Vector2(0, 90), right, 45.0) == right,
			"small or downward mouse movement keeps the stance")

	check(PlayerController.stance_from_move(Vector2(-1, 0), over) == left
			and PlayerController.stance_from_move(Vector2(1, 0.3), over) == right
			and PlayerController.stance_from_move(Vector2(0, 1), left) == over,
			"strafing left or right or moving forward picks that side")
	check(PlayerController.stance_from_move(Vector2.ZERO, left) == left
			and PlayerController.stance_from_move(Vector2(0, -1), right) == right,
			"standing still or backing up keeps the stance")

	var raid := await _new_raid(51, false)
	var setup: Array = await _duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var foe_blade: MeleeWeapon = setup[2]
	var blade := p.get_active_weapon() as MeleeWeapon
	var total := func() -> float: return p.health.health + p.health.armor

	# The foe swings to its right, so it comes from its left and arrives on
	# the player's right.
	check(MeleeWeapon.swing_from(left) == right and MeleeWeapon.swing_from(right) == left
			and MeleeWeapon.swing_from(over) == over, "a swing to one side starts on the other")
	foe.cmd.stance = right
	p.cmd.stance = left
	p.cmd.secondary = true
	await frames(30)
	var before: float = total.call()
	await _foe_swing(foe)
	await frames(10)
	check(foe_blade.is_winding_up() and foe_blade.attack_dir == left,
			"a swing keeps the side it started from (a right swing comes from the left)")
	check(Hud.incoming_side(p) == right, "the HUD warns which side to guard")
	await frames(30)
	check(total.call() < before, "a guard on the wrong side stops nothing")
	check(Hud.incoming_side(p) == -1, "the warning clears after the swing")

	# Changing stance while the guard is up does not move it.
	p.cmd.stance = right
	await frames(30)
	check(blade.guard_dir == left, "a guard keeps the side it was raised on")
	p.cmd.secondary = false
	await frames(60)

	# Guard the correct side.
	p.cmd.secondary = true
	await frames(30)
	check(blade.guard_dir == right, "raising the guard again takes the new stance")
	before = total.call()
	await _foe_swing(foe)
	await frames(40)
	check(is_equal_approx(total.call(), before), "a guard on the correct side blocks the hit")
	p.cmd.secondary = false

	# A parry needs the correct side too.
	await frames(90)
	p.cmd.stance = over
	before = total.call()
	await _foe_swing(foe)
	await frames(22)
	p.cmd.secondary = true
	await frames(12)
	p.cmd.secondary = false
	check(total.call() < before and foe.stagger_left <= 0.0, "a parry on the wrong side fails")
	await frames(90)
	p.cmd.stance = right
	p.stagger_left = 0.0
	before = total.call()
	await _foe_swing(foe)
	await frames(22)
	p.cmd.secondary = true
	await frames(12)
	p.cmd.secondary = false
	check(is_equal_approx(total.call(), before) and foe.stagger_left > 0.0, "a parry on the correct side lands")

	# The player's attacks carry their direction, and the foe can guard them.
	await frames(120)
	foe.stagger_left = 0.0
	p.riposte_left = 0.0
	# A swing to the player's right comes from their left and arrives on the
	# foe's right: guarding the same side as the swing's stance meets it.
	p.cmd.stance = right
	foe.cmd.stance = right
	foe.cmd.secondary = true
	await frames(30)
	var foe_before := foe.health.health + foe.health.armor
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	await frames(20)
	check(is_equal_approx(foe.health.health + foe.health.armor, foe_before), "an enemy guarding the right side blocks you")
	await frames(40)
	p.cmd.stance = over
	p.cmd.primary_pressed = true
	await frames(1)
	p.cmd.primary_pressed = false
	await frames(20)
	check(foe.health.health + foe.health.armor < foe_before, "attacking a side the enemy is not guarding gets through")
	foe.cmd.secondary = false

	# Bullets ignore direction: any guard turns part of one aside.
	p.cmd.stance = left
	p.cmd.secondary = true
	await frames(30)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	var loss: float = before - total.call()
	check(loss > 0.0 and loss < 20.0, "any guard turns aside part of a bullet")
	p.cmd.secondary = false
	await _end_raid(raid)

	# A guarding brute picks a side and holds it between swings.
	var brute_raid := await _new_raid(52, true)
	var duel: Array = await _duel(brute_raid)
	var brute: Actor = duel[1]
	var brute_blade: MeleeWeapon = duel[2]
	var guarded := false
	var sides := {}
	for i in 600:
		await frames(1)
		if brute_blade.is_blocking():
			guarded = true
		if brute_blade.is_winding_up():
			sides[brute_blade.attack_dir] = true
	check(guarded, "a melee bot guards between swings")
	check(sides.size() >= 2, "a melee bot varies the side it attacks from")
	await _end_raid(brute_raid)


## A raid whose player carries exactly `kit`, standing in the open.
func _kit_raid(p_seed: int, kit: Array[String]) -> Raid:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(40)
	return raid


func _test_flight_rigs_and_abilities() -> void:
	print("Flight rigs and abilities")
	var press_jump := func(a: Actor) -> void:
		a.cmd.jump_pressed = true
		await frames(1)
		a.cmd.jump_pressed = false

	# Thruster boots: kicks and dashes on charges, a short skim, no heat.
	var raid := await _kit_raid(60, ["rifle_scrap", "blade_scrap", "boots_thruster", "plate_light"])
	var p := raid.player
	check(p.flight.display_name == "Mk1 Thruster Boots" and p.flight.burst_velocity > 0.0
			and is_zero_approx(p.flight.thrust_accel) and p.flight.can_skim(), "boots stats come from the item")
	check(p.flight.max_charges == 4 and p.flight.charges == 4, "Mk1 boots carry 4 charges, full when put on")
	await press_jump.call(p)
	await frames(10)
	var height := p.global_position.y
	await press_jump.call(p)
	check(p.velocity.y > 8.0 and p.flight.charges == 3 and is_zero_approx(p.flight.heat),
			"pressing jump in the air kicks you upward on a charge, not heat")
	await frames(15)
	check(p.global_position.y > height + 1.0, "the kick gains height")
	p.cmd.move = Vector2(1, 0)
	var side_before := (p.global_basis.inverse() * p.velocity).x
	await press_jump.call(p)
	check((p.global_basis.inverse() * p.velocity).x > side_before + 5.0, "boots kick you the way you steer")
	p.cmd.move = Vector2.ZERO
	for i in 3:
		await press_jump.call(p)
		await frames(2)
	check(p.flight.charges == 0, "kicking over and over spends the charges (%d left)" % p.flight.charges)
	var vy := p.velocity.y
	await press_jump.call(p)
	check(p.velocity.y <= vy, "boots out of charges do nothing")
	await frames(int(p.flight.charge_time * 60.0) + 2)
	check(p.flight.charges == 1, "a charge comes back every %.1f s, even in the air" % p.flight.charge_time)
	p.cmd.jump = true
	await frames(2)
	check(not p.flight.is_hovering, "boots cannot hover")
	p.cmd.jump = false
	for i in 400:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	await _check_boot_skim(p)
	await _end_raid(raid)

	# Glide wings: launch, then fall slowly and travel far.
	raid = await _kit_raid(61, ["rifle_scrap", "blade_scrap", "wings_glide", "plate_light"])
	p = raid.player
	# These check the handling high up, not the ceiling (`_test_rig_tiers`).
	p.flight.ceiling = 0.0
	p.global_position += Vector3(0, 30, 0)
	p.velocity = Vector3.ZERO
	await frames(30)
	check(p.velocity.y < -5.0 and not p.flight.is_gliding, "wings do nothing until you hold jump")
	p.cmd.jump = true
	var start := p.global_position
	await frames(60)
	check(p.flight.is_gliding and p.velocity.y >= -p.flight.glide_fall_speed - 0.01,
			"holding jump while falling glides at a gentle sink rate")
	var travelled := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	check(travelled > 8.0, "gliding carries you forward (%.1f m in a second)" % travelled)
	p.cmd.jump = false
	await frames(5)
	check(not p.flight.is_gliding, "letting go stops the glide")
	await _check_glide_flying(p)
	await _check_wing_moves(p)
	await _end_raid(raid)

	# The Mk2 jetpack: cruise, wide turns, coasting, a steady hover to shoot from.
	raid = await _kit_raid(65, ["rifle_scrap", "blade_scrap", "jetpack_mk2", "frame_bulwark"])
	raid.player.flight.ceiling = 0.0
	await _check_jetpack_cruise(raid.player)
	await _end_raid(raid)

	# The jetpack still works and does not burst or glide.
	raid = await _kit_raid(62, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"])
	p = raid.player
	p.flight.ceiling = 0.0
	await press_jump.call(p)
	await frames(10)
	p.cmd.jump = true
	await press_jump.call(p)
	await frames(30)
	check(p.flight.is_thrusting and not p.flight.is_gliding and not p.is_on_floor(),
			"the jetpack still flies by holding jump")
	p.cmd.jump = false
	await _check_free_flight(p)
	check(not p.ability.enabled and p.ability.status_text() == "", "no ability without an ability item")
	p.cmd.ability_pressed = true
	await frames(2)
	p.cmd.ability_pressed = false
	check(p.ability.cooldown_left <= 0.0, "pressing the ability key with none equipped does nothing")
	await _end_raid(raid)

	# Phase Step.
	raid = await _kit_raid(63, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_blink"])
	p = raid.player
	check(p.ability.enabled and p.ability.effect == "blink" and "chip_blink" in p.gear_items,
			"an ability item equips into the ability slot")
	var arena := raid.depots[0].global_position
	p.global_position = Vector3(arena.x, arena.y - 1.9, arena.z + 3.0)
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD
	await frames(5)
	var before_pos := p.global_position
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	var moved := before_pos.distance_to(p.global_position)
	check(moved > 2.0 and moved <= p.ability.blink_range + 0.5, "Phase Step moves you forward (%.1f m)" % moved)
	check(p.ability.cooldown_left > 0.0 and not p.ability.is_ready(), "an ability goes on cooldown")
	before_pos = p.global_position
	p.cmd.ability_pressed = true
	await frames(2)
	p.cmd.ability_pressed = false
	check(before_pos.distance_to(p.global_position) < 0.5, "an ability cannot be used while on cooldown")
	p.ability.cooldown_left = 0.0
	p.cmd.aim_dir = Vector3.DOWN
	await frames(2)
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	await frames(10)
	check(p.global_position.y > arena.y - 2.5, "Phase Step stops short of the ground and walls")
	await _end_raid(raid)

	# Kinetic Barrier.
	raid = await _kit_raid(64, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_barrier"])
	p = raid.player
	var foe := raid.bots[0]
	var total := func() -> float: return p.health.health + p.health.armor
	var before: float = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	check(is_equal_approx(before - total.call(), 20.0), "without the barrier a hit lands in full")
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	check(p.ability.is_active() and is_equal_approx(before - total.call(), 8.0), "the barrier cuts damage by 60%")
	await frames(int(p.ability.duration * 60.0) + 10)
	before = total.call()
	Combat.deal(p, DamageInfo.make(20.0, foe, "bullet"))
	check(not p.ability.is_active() and is_equal_approx(before - total.call(), 20.0), "the barrier runs out")
	await _end_raid(raid)

	# Shock Pulse.
	raid = await _kit_raid(65, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "chip_pulse"])
	p = raid.player
	var near := raid.bots[0]
	var far := raid.bots[1]
	near.global_position = p.global_position + Vector3(3, 0, 0)
	far.global_position = p.global_position + Vector3(30, 0, 0)
	await frames(3)
	var near_before := near.health.health + near.health.armor
	var far_before := far.health.health + far.health.armor
	p.cmd.ability_pressed = true
	await frames(1)
	p.cmd.ability_pressed = false
	check(near.health.health + near.health.armor < near_before and near.stagger_left > 0.0,
			"Shock Pulse hurts and staggers someone close")
	check(is_equal_approx(far.health.health + far.health.armor, far_before) and far.stagger_left <= 0.0,
			"Shock Pulse does not reach someone far away")
	await _end_raid(raid)

	# Stash, hub and crates.
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["chip_pulse", "wings_glide"])
	check(Profile.equip("ability", "chip_pulse") and Profile.equip("rig", "wings_glide")
			and not Profile.equip("ability", "wings_glide"), "abilities and rigs equip into their own slots")
	var kit := Profile.checkout_loadout(Worlds.get_world("ashfront"))
	check("chip_pulse" in kit and "wings_glide" in kit and "jetpack_mk1" not in kit,
			"the kit carries the chosen ability and rig")
	Profile.reset()
	Profile.welcome_granted = true
	kit = Profile.checkout_loadout(Worlds.get_world("ashfront"))
	var has_ability := false
	for id in kit:
		if ItemDB.has_tag(id, "ability"):
			has_ability = true
	check(not has_ability, "an empty ability slot deploys with no ability")
	Profile.grant_gear_crates()
	check(Profile.stash.is_empty() and Profile.GEAR_CRATES.is_empty(),
			"no free test-gear crate goes to every player (dev mode has the gear)")
	Profile.reset()
	Profile.grant_welcome_crate()
	var welcome := Profile.stash.size()
	Profile.grant_welcome_crate()
	check(welcome == Profile.WELCOME_CRATE.size() and Profile.stash.size() == welcome
			and "bike_scrapper" in Profile.stash and "wings_glide" not in Profile.stash
			and Profile.base_upgrades.is_empty() and Profile.blueprints.is_empty(),
			"a new player gets the welcome crate once, with the starter bike, and a starter bunker")
	Profile.reset()


## A flat test ground with a jump ramp, away from any raid map.
func _vehicle_arena() -> Node3D:
	var arena := Node3D.new()
	arena.name = "VehicleArena"
	add_child(arena)
	arena.position = Vector3(0, 0, 2000)
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(400, 1, 400)
	var ground_col := CollisionShape3D.new()
	ground_col.shape = ground_shape
	ground.add_child(ground_col)
	ground.position.y = -0.5
	arena.add_child(ground)
	# The same ramp the map builds: 8 m long at 15 degrees, rising toward -Z.
	var angle := deg_to_rad(15.0)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = Actor.LAYER_WORLD
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(4, 0.4, 8)
	var ramp_col := CollisionShape3D.new()
	ramp_col.shape = ramp_shape
	ramp.add_child(ramp_col)
	ramp.position = Vector3(60, 4.0 * sin(angle) - 0.2 * cos(angle), -40)
	ramp.basis = Basis(Vector3.RIGHT, angle)
	arena.add_child(ramp)
	return arena


## Jetpack free flight. `p` is in the air with a jetpack, jump let go.
func _check_free_flight(p: Actor) -> void:
	var heat_rate := p.flight.heat_per_sec
	p.flight.heat_per_sec = 4.0
	p.flight.heat = 0.0
	p.global_position.y += 25.0
	p.velocity = Vector3.ZERO
	p.cmd.jump_pressed = true
	await frames(1)
	p.cmd.jump_pressed = false
	check(not p.flight.is_hovering, "tapping jump in the air no longer lights the jets")
	await frames(10)
	check(not p.flight.is_hovering and p.velocity.y < -1.0, "with aim let go a jetpack does not hover: you fall")
	p.cmd.secondary = true
	await frames(1)
	check(p.flight.is_hovering, "holding aim in the air lights the jets")
	await frames(40)
	var held := p.global_position.y
	await frames(40)
	check(absf(p.global_position.y - held) < 0.2 and absf(p.velocity.y) < 0.1, "the jetpack hovers with nothing held")
	p.cmd.move = Vector2(1, 0)
	await frames(40)
	var side := (p.global_basis.inverse() * p.velocity).x
	check(side > p.flight.fly_speed - 0.5 and absf(p.global_position.y - held) < 0.2, "hovering strafes level (%.1f m/s)" % side)
	p.cmd.move = Vector2.ZERO
	await frames(40)
	check(Vector2(p.velocity.x, p.velocity.z).length() < 0.5, "letting go of the keys stops you in the air")
	p.cmd.descend = true
	await frames(30)
	check(p.velocity.y < -p.flight.descend_speed + 0.5, "the descend key sinks")
	p.cmd.descend = false
	p.cmd.jump = true
	await frames(40)
	check(p.velocity.y > p.flight.max_rise_speed - 0.5, "holding jump climbs")
	p.cmd.jump = false
	var hover_heat := p.flight.heat
	await frames(30)
	hover_heat = p.flight.heat - hover_heat
	p.cmd.sprint = true
	p.cmd.move = Vector2(0, 1)
	await frames(2)
	check(p.flight.boost_speed > 0.0 or not p.flight.is_boosting, "a jetpack without a boost does not boost")
	p.cmd.move = Vector2.ZERO
	p.cmd.sprint = false
	var boost_was := p.flight.boost_speed
	p.flight.boost_speed = 22.0
	# Head first along the view's heading. Looking up 45 degrees only aims:
	# the boost stays level until jump climbs.
	p.cmd.pitch = PI / 4.0
	p.cmd.sprint = true
	p.cmd.move = Vector2(0, 1)
	var boost_heat := p.flight.heat
	await frames(30)
	boost_heat = p.flight.heat - boost_heat
	await frames(60)
	var along := p.velocity.dot(Basis(Vector3.UP, p.cmd.yaw) * Vector3.FORWARD)
	check(p.flight.is_boosting and along > p.flight.boost_speed - 1.0 and absf(p.velocity.y) < 1.0,
			"sprinting forward boosts head first along the view's heading, level whatever the pitch (%.1f m/s)" % along)
	p.cmd.jump = true
	await frames(30)
	check(p.flight.is_boosting and p.velocity.y > 5.0, "holding jump climbs during a boost")
	p.cmd.jump = false
	check(boost_heat > hover_heat * 2.0, "boosting runs hotter than hovering")
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	p.cmd.pitch = 0.0
	await frames(5)
	check(p.flight.is_hovering and not p.flight.is_boosting, "letting go of the boost drops back to a hover while aim is held")
	# Aim let go: the jets go out. A Shift press in the air boosts with no
	# hover first, and the speed builds rather than snapping on.
	p.cmd.secondary = false
	await frames(30)
	check(not p.flight.is_hovering and p.velocity.y < -1.0, "letting go of aim puts the jets out")
	p.velocity = Vector3.ZERO
	p.cmd.sprint = true
	await frames(5)
	check(not p.flight.is_boosting, "Shift held from before does not boost on its own")
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	check(p.flight.is_boosting and p.flight.is_hovering, "a Shift press in the air boosts with aim let go")
	var early := p.velocity.dot(Basis(Vector3.UP, p.cmd.yaw) * Vector3.FORWARD)
	await frames(90)
	along = p.velocity.dot(Basis(Vector3.UP, p.cmd.yaw) * Vector3.FORWARD)
	check(p.flight.is_boosting and along > early + 3.0 and along > p.flight.boost_speed - 1.0 and absf(p.velocity.y) < 1.0,
			"the boost accelerates you forward (%.1f then %.1f m/s)" % [early, along])
	p.cmd.sprint = false
	await frames(5)
	check(not p.flight.is_hovering and not p.flight.is_boosting, "letting go of Shift without aim ends the flight")
	p.cmd.secondary = true
	p.velocity = Vector3.ZERO
	p.flight.boost_speed = boost_was
	# Shift + a move key dashes that way on heat, and the hover carries on.
	await frames(30)
	var dash_heat := p.flight.heat
	var dash_stamina := p.stamina
	p.cmd.move = Vector2(-1, 0)
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	p.cmd.move = Vector2.ZERO
	await frames(3)
	var dash_side := (Basis(Vector3.UP, p.cmd.yaw).inverse() * p.velocity).x
	check(dash_side < -(p.flight.air_dash_speed - 2.0) and p.flight.heat > dash_heat + p.flight.air_dash_heat * 0.8
			and is_equal_approx(p.stamina, dash_stamina),
			"Shift + A dashes left off a hover, on heat (%.1f m/s)" % dash_side)
	var heat_after := p.flight.heat
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	check(p.flight.heat < heat_after + 2.0, "a second press right away waits for the cooldown")
	p.cmd.sprint = false
	await frames(60)
	dash_side = (Basis(Vector3.UP, p.cmd.yaw).inverse() * p.velocity).x
	check(p.flight.is_hovering and absf(dash_side) < 3.0, "after the dash the jets hold you where you were going")
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	await frames(3)
	var ahead := (Basis(Vector3.UP, p.cmd.yaw).inverse() * p.velocity).z
	check(ahead < -(p.flight.air_dash_speed - 2.0), "Shift alone dashes forward (%.1f m/s)" % -ahead)
	p.cmd.sprint = false
	await frames(40)
	p.flight.heat_per_sec = 4000.0
	await frames(60)
	check(p.flight.overheated and not p.flight.is_hovering and p.velocity.y < 0.0, "overheating puts the jets out and you fall")
	p.cmd.secondary = false
	p.flight.heat_per_sec = heat_rate
	for i in 400:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	p.flight.heat = 0.0
	p.flight.overheated = false
	p.cmd.jump_pressed = true
	await frames(1)
	p.cmd.jump_pressed = false
	p.cmd.jump = true
	await frames(1)
	check(not p.flight.is_hovering, "a jump off the ground does not light the jets")
	p.cmd.jump = false
	# A sprinting jump stays a jump: Shift held from the ground never boosts.
	for i in 400:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	p.cmd.sprint = true
	p.cmd.move = Vector2(0, 1)
	await frames(10)
	p.cmd.jump_pressed = true
	await frames(1)
	p.cmd.jump_pressed = false
	await frames(5)
	check(not p.is_on_floor() and not p.flight.is_boosting, "a sprinting jump does not boost")
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	var copy := ActorCommand.new()
	p.cmd.descend = true
	p.cmd.sprint_pressed = true
	copy.apply_array(p.cmd.to_array())
	check(copy.descend and copy.sprint_pressed, "descend and a sprint press travel in the network command")
	p.cmd.descend = false
	p.cmd.sprint_pressed = false


## The Mk2 jetpack. `p` stands on the ground in heavy armor.
func _check_jetpack_cruise(p: Actor) -> void:
	var mk2 := ItemDB.item_stats("jetpack_mk2")
	check(p.flight.heavy_lift and is_equal_approx(p.flight.heat_per_sec, mk2["heat_per_sec"]),
			"a jetpack carries heavy armor without running hotter")
	check(is_equal_approx(p.flight.fly_speed, FlightRig.CRUISE_SPEED), "the jetpack cruises at its cruise speed")
	p.global_position.y += 150.0
	p.velocity = Vector3.ZERO
	p.flight.heat = 0.0
	await frames(2)
	p.cmd.secondary = true
	await frames(30)
	var still := p.flight.heat
	await frames(60)
	still = p.flight.heat - still
	check(p.flight.is_hovering and is_equal_approx(p.air_aim(), p.flight.flight_aim) and p.air_aim() <= 0.1 + 0.001,
			"a lit jetpack holding still aims nearly as steady as on the ground (+10%)")
	p.cmd.yaw = 0.0
	p.cmd.move = Vector2(0, 1)
	await frames(60)
	var cruise := p.flight.heat
	await frames(60)
	cruise = p.flight.heat - cruise
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(absf(speed - FlightRig.CRUISE_SPEED) < 0.5, "jets cruise at %.1f m/s" % speed)
	check(absf(cruise - still) < 0.2, "cruising costs the same heat as holding a hover (%.2f against %.2f)" % [cruise, still])
	# Steer hard right at speed: the heading comes round slowly.
	var before := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	p.cmd.move = Vector2(1, 0)
	await frames(30)
	var turned := before.angle_to(Vector3(p.velocity.x, 0, p.velocity.z).normalized())
	check(turned < p.flight.cruise_turn_rate * 0.5 + 0.1 and Vector2(p.velocity.x, p.velocity.z).length() > 10.0,
			"a jetpack at cruise makes wide turns (%.2f rad in half a second)" % turned)
	p.cmd.move = Vector2.ZERO
	await frames(60)
	check(Vector2(p.velocity.x, p.velocity.z).length() < 0.5, "and stops dead when you let go")
	p.flight.heat = 60.0
	p.cmd.descend = true
	await frames(30)
	check(p.flight.is_coasting and not p.flight.is_thrusting and p.flight.heat < 60.0 - p.flight.coast_cool * 0.4,
			"coasting idles the jets and cools them (%.0f heat)" % p.flight.heat)
	check(p.velocity.y < -p.flight.descend_speed + 0.5, "and sinks")
	check(Hud.rig_text(p).contains("coasting") and Hud.rig_text(p).contains("LOCKABLE"),
			"the watch says the jets are coasting and still hot enough to lock onto")
	p.cmd.descend = false
	p.cmd.sprint = true
	p.cmd.move = Vector2(0, 1)
	await frames(10)
	check(p.flight.is_boosting and p.air_aim() == 1.0, "boosting spoils the aim")
	var gun := p.get_active_weapon() as Gun
	if gun:
		var wild := gun.current_spread_deg()
		p.cmd.sprint = false
		p.cmd.move = Vector2.ZERO
		await frames(5)
		check(gun._air_spread() < p.air_spread_deg * 0.11 and gun.current_spread_deg() < wild - 0.01,
				"a gun spreads wider in the air than from a hover")
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	p.cmd.secondary = false


## Boots skimming, dashing, grazing, the 10 m ceiling and the ground speed.
## `p` stands on open ground with thruster boots.
func _check_boot_skim(p: Actor) -> void:
	p.global_position = Vector3(0.0, p.global_position.y, 60.0)
	for i in 200:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	await frames(10)
	p.flight.fill()
	var ground := p.global_position.y
	# Faster on foot (Caleb's call: +15%).
	p.cmd.yaw = 0.0
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	await frames(40)
	var run := Vector2(p.velocity.x, p.velocity.z).length()
	check(absf(run - p.sprint_speed * 1.15) < 0.3, "boots sprint 15%% faster (%.1f m/s)" % run)
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	await frames(30)
	p.cmd.jump_pressed = true
	p.cmd.jump = true
	await frames(1)
	p.cmd.jump_pressed = false
	await frames(30)
	check(p.flight.is_skimming and not p.is_on_floor() and absf(p.velocity.y) < 0.5,
			"holding jump off a jump skims, holding the height")
	check(p.flight.skim_band() == 0 and p.air_aim() == 0.0, "skimming low aims steady")
	p.cmd.move = Vector2(0, 1)
	await frames(20)
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	check(absf(speed - p.flight.skim_speed) < 0.5, "boots skim at %.1f m/s" % speed)
	p.cmd.move = Vector2.ZERO
	await frames(60)
	check(not p.flight.is_skimming and p.velocity.y < 0.0 and is_zero_approx(p.flight.heat),
			"the skim runs out after %.1f s and you drop, with no heat" % p.flight.skim_time)
	p.cmd.jump = false
	for i in 200:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	await frames(2)
	check(is_equal_approx(p.flight.skim_left, p.flight.skim_time), "landing refills the skim")
	check(Hud.rig_text(p).begins_with("dashes "), "the watch shows the dash charges (%s)" % Hud.rig_text(p))
	# A dash on a charge, not stamina, with a graze window and steady aim.
	p.flight.fill()
	p.cmd.jump_pressed = true
	await frames(1)
	p.cmd.jump_pressed = false
	await frames(8)
	var stamina := p.stamina
	p.cmd.move = Vector2(1, 0)
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	await frames(2)
	var side := (p.global_basis.inverse() * p.velocity).x
	check(side > p.flight.air_dash_speed - 1.0 and p.flight.charges == 3 and is_equal_approx(p.stamina, stamina),
			"Shift + D dashes the boots right on a charge (%.1f m/s)" % side)
	check(p.air_aim() == 0.0, "mid-dash the boots aim steady")
	var total := p.health.health + p.health.armor
	p.protected_left = 0.0
	Combat.deal(p, DamageInfo.make(20.0, null, "bullet"))
	var grazed := total - (p.health.health + p.health.armor)
	check(p.graze_left > 0.0 and is_equal_approx(grazed, 20.0 * p.flight.graze_mult),
			"a round in the dash's graze window only grazes (%.1f of 20)" % grazed)
	await frames(15)
	total = p.health.health + p.health.armor
	Combat.deal(p, DamageInfo.make(20.0, null, "bullet"))
	check(is_equal_approx(total - (p.health.health + p.health.armor), 20.0), "after the window a round lands in full")
	var jet := FlightRig.new()
	check(p.flight.air_dash_speed > ItemDB.item_stats("wings_glide")["air_dash_speed"]
			and p.flight.air_dash_speed * p.flight.air_dash_time > jet.air_dash_speed * jet.air_dash_time,
			"boots dash further than wings or a jetpack (their edge)")
	jet.free()
	p.cmd.sprint = false
	p.cmd.move = Vector2.ZERO
	for i in 200:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	# Kicks top out at the 10 m ceiling.
	p.flight.fill()
	p.cmd.jump_pressed = true
	await frames(1)
	p.cmd.jump_pressed = false
	var top := 0.0
	for i in 300:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y - ground)
		p.cmd.jump_pressed = p.velocity.y <= 0.0 and not p.cmd.jump_pressed
	p.cmd.jump_pressed = false
	check(top > 8.0 and top < p.flight.ceiling + 0.6, "kicks top out at the boots' %.0f m ceiling (%.1f m)" % [p.flight.ceiling, top])
	# No fall damage in boots.
	for i in 400:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	p.global_position.y = ground + 30.0
	p.velocity = Vector3.ZERO
	total = p.health.health + p.health.armor
	for i in 400:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	check(is_equal_approx(total, p.health.health + p.health.armor), "boots take no fall damage from 30 m")


## The wings' own moves. `p` is gliding high up with glide wings.
func _check_wing_moves(p: Actor) -> void:
	# A fast touchdown turns into a slide; a slow one does not.
	p.velocity = Vector3(0, -2, -10)
	p._slide_landing()
	check(not p.is_sliding(), "wings touching down slowly just land")
	p.velocity = Vector3(0, -2, -22)
	p._slide_landing()
	check(p.is_sliding() and p._slide_from >= 21.9, "wings touching down fast slide on, keeping the speed")
	p.slide_left = 0.0
	# High over the middle of the map, flying across it.
	p.global_position = Vector3(0.0, 160.0, 90.0)
	p.velocity = Vector3(0, -1, -15)
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.jump = true
	p.flight.heat = 0.0
	p.flight.overheated = false
	await frames(30)
	check(p.flight.is_gliding, "gliding")
	check(Hud.rig_text(p).begins_with("Air ") and Hud.rig_text(p).contains("boosts 2"),
			"the watch shows airspeed and the boosts left")
	# No pulses: after the launch wings cannot climb on their own (Caleb's call).
	p.flight.launched = true
	var start_y := p.global_position.y
	p.cmd.jump_pressed = true
	await frames(1)
	p.cmd.jump_pressed = false
	await frames(30)
	check(p.global_position.y < start_y, "pressing jump in a glide does not climb")
	# The main gun is stowed while the wings are out, and aim is poor.
	check(p.wings_block(p.weapons[0]) and p.air_aim() > 1.0, "only a sidearm fires with the wings spread, and it spreads wide")
	# Shift + D is a wing boost, never a sidestep: wings fly where they point.
	await frames(130)
	var side_before := (Basis(Vector3.UP, p.cmd.yaw).inverse() * p.velocity).x
	var speed_before := Vector2(p.velocity.x, p.velocity.z).length()
	var charges_before := p.flight.charges
	p.cmd.move = Vector2(1, 0)
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	p.cmd.move = Vector2.ZERO
	await frames(5)
	var side := (Basis(Vector3.UP, p.cmd.yaw).inverse() * p.velocity).x
	check(absf(side - side_before) < 2.0 and Vector2(p.velocity.x, p.velocity.z).length() > speed_before + p.flight.glide_boost - 1.0
			and p.flight.charges == charges_before - 1,
			"Shift + D boosts the wings ahead on a charge, never sideways (%.1f m/s sideways)" % side)
	await frames(30)
	var heading := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	check(heading.dot(Basis(Vector3.UP, p.cmd.yaw) * Vector3.FORWARD) > 0.95, "and the glide carries on the way you face")
	# Two boosts a flight, and they come back only on the ground.
	await frames(60)
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	await frames(90)
	var speed_now := Vector2(p.velocity.x, p.velocity.z).length()
	p.cmd.sprint_pressed = true
	await frames(1)
	p.cmd.sprint_pressed = false
	await frames(3)
	check(p.flight.charges == 0 and Vector2(p.velocity.x, p.velocity.z).length() < speed_now + 2.0,
			"a third boost in one flight does nothing")
	await frames(120)
	check(p.flight.charges == 0, "boosts do not come back in the air")
	# Glide stamina: 25 s of gliding, then the wings fold and you drop.
	p.flight.heat = p.flight.max_heat - p.flight.glide_heat * 0.5
	await frames(40)
	check(p.flight.overheated and not p.flight.is_gliding, "out of glide stamina the wings fold (%.0f)" % p.flight.heat)
	p.flight.heat = 0.0
	p.flight.overheated = false
	await frames(5)
	# Stalling: slow below the stall speed and the wings sink fast.
	p.velocity = Vector3(0, 0, -3)
	await frames(2)
	check(p._glide_sink() >= p.flight.stall_sink - 0.01, "a stalled glide sinks fast")
	p.cmd.jump = false
	await frames(30)
	check(not p.wings_block(p.weapons[0]), "folding the wings brings the main gun back")


## Wings fly like wings. `p` is high up with glide wings, jump let go.
func _check_glide_flying(p: Actor) -> void:
	p.global_position.y += 40.0
	p.velocity = Vector3(0, -1, 0)
	p.cmd.jump = true
	await frames(120)
	var cruise := Vector2(p.velocity.x, p.velocity.z).length()
	check(absf(cruise - p.flight.glide_speed) < 0.5, "a level glide settles at glide speed (%.1f)" % cruise)
	# The wings fly where you look, like a bird's: turning the view banks
	# the glide round onto it, and looking down never dives it.
	var before := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	p.cmd.yaw -= PI / 2.0
	p.cmd.pitch = -0.9
	await frames(20)
	var turning := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	check(before.signed_angle_to(turning, Vector3.UP) < -0.2 and p.velocity.y > -p.flight.glide_fall_speed * 2.5,
			"looking right banks the glide round to the right, without diving")
	await frames(100)
	var view := Basis(Vector3.UP, p.cmd.yaw) * Vector3.FORWARD
	before = Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	check(before.dot(view) > 0.999, "and it settles on the way you look")
	p.cmd.pitch = 0.0
	# Holding a strafe key banks the glide round harder, in an arc.
	p.cmd.move = Vector2(1, 0)
	await frames(10)
	var during := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	var swung := before.angle_to(during)
	check(swung > 0.1 and swung < 0.5, "a strafe key banks the wings round in an arc (%.2f rad)" % swung)
	check(before.signed_angle_to(during, Vector3.UP) < 0.0, "and the right key turns right")
	p.cmd.move = Vector2.ZERO
	# Letting go, the wings roll back onto the view and fly straight on it.
	await frames(90)
	var after := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	check(after.dot(view) > 0.999, "letting go, the wings come back onto the view")
	await frames(30)
	check(after.dot(Vector3(p.velocity.x, 0, p.velocity.z).normalized()) > 0.999, "and then fly straight on")
	p.cmd.move = Vector2(0, 1)
	await frames(150)
	var dived := Vector2(p.velocity.x, p.velocity.z).length()
	check(dived > cruise * 1.3 and p.velocity.y < -8.0, "forward dives for speed (%.1f m/s)" % dived)
	p.cmd.move = Vector2(0, -1)
	var low := p.global_position.y
	await frames(60)
	check(p.flight.is_gliding and p.global_position.y > low + 4.0, "back pulls up and climbs on that speed (%.1f m)" % (p.global_position.y - low))
	await frames(240)
	var slow := Vector2(p.velocity.x, p.velocity.z).length()
	check(slow < cruise * 0.8 and p.velocity.y < 0.0, "the climb runs out as the speed does")
	p.cmd.move = Vector2.ZERO
	p.cmd.pitch = 0.0
	p.cmd.jump = false


func _test_vehicle_driving() -> void:
	print("Vehicles: driving")
	var arena := _vehicle_arena()
	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	arena.add_child(bike)
	bike.position = Vector3(0, 0.3, 0)
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(3, 0.1, 0)
	await frames(20)
	check(bike.is_on_floor() and is_equal_approx(bike.max_speed, 22.0), "a bike settles and takes its item stats")
	var seat: Interactable = bike.get_node("Seat")
	check(seat.get_prompt().contains("Ride"), "a parked bike offers a ride")
	# The rider stands 3 m to the bike's +X side; yaw PI/2 faces -X.
	rider.cmd.yaw = PI / 2.0
	rider.cmd.pitch = -0.4
	check(rider.find_interactable() == seat, "looking at a bike targets its seat")
	rider.cmd.yaw = 0.0
	rider.cmd.pitch = 0.0
	seat.interact(rider)
	check(rider.vehicle == bike and bike.rider == rider, "interacting gets you on")
	# Seated, not standing on the bike: the eyes (and the head a shot finds)
	# are about where a seated rider's are, and the pose's anchors line up.
	await frames(2)
	var eye_up: float = rider.get_eye_position().y - bike.global_position.y
	check(eye_up > 1.3 and eye_up < 1.8, "a rider sits low on the bike (eyes %.2f m up)" % eye_up)
	var seat_at: Vector3 = bike.seat_point
	check(bike.grip_points.size() == 2 and bike.peg_points.size() == 2, "a bike has two grips and two pegs")
	check(bike.grip_points[0].x < 0.0 and bike.grip_points[1].x > 0.0 and bike.peg_points[0].x < 0.0 \
			and bike.peg_points[1].x > 0.0, "grips and pegs are listed left then right")
	check(bike.grip_points[0].z < seat_at.z and bike.grip_points[0].y > seat_at.y and bike.peg_points[0].y < seat_at.y,
			"grips are ahead of and above the seat, pegs below it")

	var start: Vector3 = bike.global_position
	rider.cmd.move = Vector2(0, 1)
	await frames(120)
	var dist: float = bike.global_position.distance_to(start)
	check(dist > rider.sprint_speed * 2.0, "the bike outruns sprinting (%.1f m in 2 s)" % dist)
	check(bike.global_position.z < start.z - 10.0, "throttle drives the way the bike points")
	check(rider.global_position.distance_to(bike.global_position) < 1.0, "the rider stays on the seat")
	rider.cmd.sprint = true
	await frames(90)
	check(bike.speed > bike.max_speed + 1.0, "sprint boosts past normal top speed (%.1f)" % bike.speed)
	rider.cmd.sprint = false
	rider.cmd.move = Vector2(-1, 1)
	var heading_before: float = bike.heading
	await frames(30)
	check(bike.heading > heading_before + 0.3, "A steers left")
	var model: Node3D = bike.get_node("Model")
	check(bike.lean < -0.05 and model.rotation.z > 0.05, "the bike leans into a left turn (%.2f)" % bike.lean)
	rider.cmd.move = Vector2(0, -1)
	await frames(60)
	check(bike.speed < 1.0, "S brakes the bike to a stop")
	rider.cmd.move = Vector2.ZERO
	await frames(30)

	rider.cmd.interact_pressed = true
	await frames(1)
	rider.cmd.interact_pressed = false
	check(rider.vehicle == null and bike.rider == null, "F gets you off")
	var off: float = rider.global_position.distance_to(bike.global_position)
	check(off > 0.8 and off < 2.5, "you step off beside the bike")
	var walk_from := rider.global_position
	rider.cmd.move = Vector2(0, 1)
	await frames(30)
	rider.cmd.move = Vector2.ZERO
	check(rider.global_position.distance_to(walk_from) > 1.0, "back on foot, you walk again")

	# Anyone can take a parked bike, but not one that is being ridden.
	var thief := Actor.new()
	arena.add_child(thief)
	thief.position = bike.position + Vector3(-2, 0, 0)
	await frames(5)
	seat.interact(thief)
	check(thief.vehicle == bike, "someone else can take a parked bike")
	seat.interact(rider)
	check(rider.vehicle == null and bike.rider == thief, "a ridden bike cannot be taken")
	thief.kill("test")
	await frames(2)
	check(bike.rider == null and thief.vehicle == null, "the rider's death leaves the bike behind")

	# Ramp jump, and bailing out mid-air keeps the momentum.
	bike.position = Vector3(60, 0.3, 0)
	bike.heading = 0.0
	bike.speed = 0.0
	bike.velocity = Vector3.ZERO
	await frames(5)
	seat.interact(rider)
	rider.cmd.move = Vector2(0, 1)
	rider.cmd.sprint = true
	var top := 0.0
	var air := 0.0
	var bailed := false
	var bail_speed := 0.0
	for i in 240:
		await frames(1)
		top = maxf(top, bike.position.y)
		air = maxf(air, bike.airborne_time)
		if not bailed and bike.airborne_time > 0.2:
			rider.cmd.interact_pressed = true
			bailed = true
		elif bailed and bail_speed == 0.0:
			rider.cmd.interact_pressed = false
			bail_speed = rider.velocity.length()
			check(rider.vehicle == null and not rider.is_on_floor(), "you can bail out mid-air")
	check(air > 0.4 and top > 2.5, "a ramp launches the bike (%.2f s in the air, %.1f m up)" % [air, top])
	check(bail_speed > 10.0, "bailing out keeps the bike's momentum (%.1f m/s)" % bail_speed)
	arena.queue_free()
	await frames(2)


func _test_vehicle_roster() -> void:
	print("Vehicles: rover, mech and jet")
	var arena := _vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(-40, 0.1, 0)
	await frames(5)
	var bike_turn: float = ItemDB.item_stats("bike_scrapper").get("turn_rate", 2.3)
	for id: String in ["rover_warden", "mech_bulwark", "jet_kestrel"]:
		check(ItemDB.has_tag(id, "vehicle") and ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE
				and not ItemDB.has_tag(id, "vendor"), "%s is a vehicle item, never sold" % id)
		var v = VehicleScript.new()
		v.setup(id)
		arena.add_child(v)
		v.position = Vector3(0, 0.5, 0)
		await frames(20)
		var model: Node3D = v.get_node("Model")
		check(v.is_on_floor() and model != null and model.get_child_count() > 10,
				"%s stands on the ground with its own greybox body" % id)
		var parked_dip := _lowest_point(model) - arena.global_position.y
		check(absf(parked_dip) < 0.05, "%s rests on the ground, not in it (lowest point %.3f m)" % [id, parked_dip])
		# The ground is the arena's floor, at the arena's height (and the ramp
		# is far away): track the deepest the model goes from here on.
		var dip := {"min": INF}
		var watch_dip := func() -> void:
			var off: Vector3 = v.global_position - arena.global_position
			if is_instance_valid(model) and off.distance_to(Vector3(60, 0, -40)) > 15.0 \
					and absf(off.x) < 190.0 and absf(off.z) < 190.0:
				dip.min = minf(dip.min, _lowest_point(model) - arena.global_position.y)
		get_tree().physics_frame.connect(watch_dip)
		var seat_at: Vector3 = v.seat_point
		check(v.grip_points.size() == 2 and v.peg_points.size() == 2
				and v.grip_points[0].x < v.grip_points[1].x and v.peg_points[0].x < v.peg_points[1].x,
				"%s lists two grips and two pegs, left then right" % id)
		check(v.grip_points[0].z < seat_at.z and v.grip_points[0].y > seat_at.y and v.peg_points[0].y < seat_at.y,
				"%s puts its grips ahead of and above the seat, its pegs below" % id)
		check(v.mount(rider) and rider.vehicle == v, "%s can be ridden" % id)
		await frames(2)
		var eye_up: float = rider.get_eye_position().y - v.global_position.y
		check(eye_up > seat_at.y + 0.3 and eye_up < seat_at.y + 1.0,
				"%s seats its rider on the seat (eyes %.2f m up, seat %.2f)" % [id, eye_up, seat_at.y])
		var toy: Node3D = VehicleScript.toy_model(id)
		check(toy.get_node_or_null("Model") != null, "%s has a toy for the watch" % id)
		toy.free()

		var start: Vector3 = v.global_position
		match id:
			"rover_warden":
				# The driver sees out: straight ahead from a seated driver's
				# eyes, nothing but see-through glass stands in the way.
				var eye := seat_at + Vector3(0.0, 0.78, 0.0)
				var blocked: Array[String] = []
				var glassed := false
				for node in model.find_children("*", "MeshInstance3D", true, false):
					var part := node as MeshInstance3D
					var box: AABB = (model.global_transform.affine_inverse() * part.global_transform) * part.get_aabb()
					for ahead: Vector3 in [Vector3(0, 0, -3), Vector3(0, -0.4, -3), Vector3(0.6, 0, -3), Vector3(-0.6, 0, -3)]:
						if box.intersects_segment(eye, eye + ahead) == null:
							continue
						var mat := part.material_override as BaseMaterial3D
						if mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
							glassed = true
						else:
							blocked.append("%s at %s" % [part.name, part.position])
						break
				check(blocked.is_empty() and glassed,
						"the rover's driver looks out through a see-through windscreen (blocked by %s)" % [blocked])
				rider.cmd.move = Vector2(0, 1)
				await frames(240)
				check(v.speed > FlightRig.CRUISE_SPEED, "the rover outruns flight cruise on the ground (%.1f m/s)" % v.speed)
				check(v.turn_rate < bike_turn and absf(v.lean) < 0.1, "the rover turns slower than a bike and does not lean in")
			"mech_bulwark":
				rider.cmd.move = Vector2(1, 0)
				var heading_before: float = v.heading
				await frames(30)
				check(v.heading < heading_before - 0.3 and v.global_position.distance_to(start) < 0.5,
						"the mech turns on the spot")
				rider.cmd.move = Vector2(0, 1)
				await frames(120)
				check(v.speed > 5.0 and v.speed <= v.max_speed + 0.1, "the mech walks, slowly (%.1f m/s)" % v.speed)
				var legs: Array = model.find_children("Leg?", "", false, false)
				var apart := 0.0
				for i in 30:
					await frames(1)
					if legs.size() == 2:
						apart = maxf(apart, absf(legs[0].rotation.x - legs[1].rotation.x))
				check(legs.size() == 2 and apart > 0.3, "its legs stride as it walks (%.2f apart)" % apart)
				rider.cmd.jump_pressed = true
				await frames(1)
				rider.cmd.jump_pressed = false
				var top: float = v.global_position.y
				for i in 60:
					await frames(1)
					top = maxf(top, v.global_position.y)
				check(top > start.y + 1.5, "jump-jets hop the mech up (%.1f m)" % (top - start.y))
				check(v._jump_wait > 0.0, "and need a moment before the next hop")
			"jet_kestrel":
				rider.cmd.jump = true
				rider.cmd.move = Vector2(0, 1)
				await frames(30)
				check(v.is_on_floor() and v.speed < v.takeoff_speed, "the jet rolls along the ground until it is fast enough")
				await frames(300)
				var climbed: float = v.global_position.y - start.y
				check(climbed > 5.0, "past takeoff speed, jump lifts it into the air (%.1f m up)" % climbed)
				rider.cmd.jump = false
				rider.cmd.move = Vector2.ZERO
				await frames(120)
				check(not v.is_on_floor() and v.speed >= v.stall_speed - 0.1,
						"off the throttle it keeps flying, it never hovers (%.1f m/s)" % v.speed)
				check(rider.global_position.distance_to(v.global_position) < 2.0, "the pilot rides along")
				rider.cmd.move = Vector2(-1, 0)
				await frames(20)
				check(v.lean < -0.2, "it banks into a turn (%.2f)" % v.lean)
				rider.cmd.move = Vector2.ZERO
				# Back over the middle of the floor, so it comes down on it.
				v.global_position = arena.global_position + Vector3(0, 12, 0)
				v.velocity = Vector3.ZERO
				v.speed = v.stall_speed
				await frames(2)
				v.dismount()
				var height: float = v.global_position.y
				await frames(60)
				check(v.global_position.y < height - 3.0, "with nobody at the stick it drops")
				await _wait_until(func() -> bool: return v.is_on_floor(), 600)
				await frames(30)
				check(v.is_on_floor(), "and comes down on the ground")
		get_tree().physics_frame.disconnect(watch_dip)
		check(dip.min > -0.06, "%s never sinks into the ground driving, landing or hopping (deepest %.3f m)" % [id, dip.min])
		rider.cmd.move = Vector2.ZERO
		rider.cmd.jump = false
		v.dismount()
		v.queue_free()
		await frames(2)
		rider.global_position = arena.global_position + Vector3(-40, 0.2, 0)
		rider.velocity = Vector3.ZERO
		await frames(10)

	# On the watch: heavier vehicles take longer to recharge.
	var world := Worlds.get_world("ashfront")
	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 73, world.starter_loadout() + (["jet_kestrel", "mech_bulwark"] as Array[String]))
	await frames(5)
	check(raid.toy_recharge("bike_scrapper") == raid.toy_cooldown
			and raid.toy_recharge("rover_warden") > raid.toy_recharge("bike_scrapper")
			and raid.toy_recharge("mech_bulwark") > raid.toy_recharge("rover_warden"),
			"heavier vehicles take longer for the watch to recharge")
	var p := raid.player
	raid.queue_free()
	arena.queue_free()
	await frames(2)


func _test_hoverbike() -> void:
	await HoverbikeTests.run(self)


## The lowest point of every mesh under `node`, in world height.
func _lowest_point(node: Node3D) -> float:
	var low := INF
	for mesh_node: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box := mesh_node.get_aabb()
		for i in 8:
			low = minf(low, (mesh_node.global_transform * box.get_endpoint(i)).y)
	return low


func _test_vehicle_raids() -> void:
	print("Vehicles: raids")
	var world := Worlds.get_world("ashfront")
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["bike_raider"])
	check(Profile.equip("vehicle", "bike_raider"), "a bike goes in the vehicle slot")
	var kit := Profile.checkout_loadout(world)
	check("bike_raider" in kit and "bike_raider" not in Profile.stash, "deploying takes the bike out of the stash")

	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 61, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(10)
	var p := raid.player
	check(raid.stowed_for(p) == (["bike_raider"] as Array[String]), "your bike rides on your watch as a toy")
	var map_bikes := raid.vehicles.size()
	var own: Array = [raid.spawn_vehicle("bike_raider", p.global_position + Vector3(2.5, 0.3, 0), 0.0)]
	raid.state_for(p).stowed.clear()
	check("bike_raider" not in p.gear_items and not p.inventory.has_item("bike_raider"),
			"a bike is not carried and does not drop in your bag")
	check(raid.vehicles.size() >= 3, "the map parks abandoned bikes too (%d)" % (raid.vehicles.size() - 1))
	var ramps := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("spawn_vehicle"))
	check(ramps.size() == map_bikes and map_bikes == raid.vehicles.size() - 1, "every vehicle marker gets a bike")

	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var bike = own[0]
	check(bike.mount(p), "you can ride your own bike")
	raid.begin_sign_out(p)
	raid.state_for(p).sign_out_left = 0.1
	await frames(20)
	check(results.size() == 1 and results[0].outcome == "left", "you can sign out in the saddle")
	check("bike_raider" in Profile.stash and "bike_raider" in results[0].get("kept_gear", []),
			"riding out takes the bike home")
	await _end_raid(raid)

	# Deploy with it again and die: the bike stays in the raid for anyone to take.
	check(Profile.equip("vehicle", "bike_raider"), "the bike can be equipped again")
	kit = Profile.checkout_loadout(world)
	var raid2 := Raid.new()
	add_child(raid2)
	raid2.start(world, 62, kit)
	for bot in raid2.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(5)
	var results2: Array[Dictionary] = []
	raid2.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results2.append(r))
	raid2.player.kill("test")
	await frames(2)
	check(results2.size() == 1 and "bike_raider" in results2[0].lost and "bike_raider" not in Profile.stash,
			"dying loses the bike you brought")
	check(Profile.equipped("vehicle") == "", "a lost bike leaves the vehicle slot")
	await _end_raid(raid2)


## Every world folder must honour the map contract and run a raid headless.
func _test_every_world() -> void:
	print("Every world plugs in")
	check(Worlds.raid_worlds().size() >= 2, "registry finds more than one world (%d)" % Worlds.raid_worlds().size())
	var every := true
	for world in Worlds.raid_worlds():
		every = every and world.id in Portal.destinations()
	check(every, "a squad portal from the watch can lead to every world")
	for world in Worlds.raid_worlds():
		var kit := world.starter_loadout()
		check(not kit.is_empty() and kit.all(func(id: String) -> bool: return ItemDB.has_item(id)),
				"%s: starter loadout is valid items" % world.id)
		var raid := Raid.new()
		add_child(raid)
		raid.start(world, 99)
		await frames(3)
		check(raid.player != null and not raid.player.is_dead, "%s: player spawns" % world.id)
		check(raid.bots.size() == world.bot_count + raid._bosses.size(), "%s: all bots spawn" % world.id)
		check(not raid.depots.is_empty(), "%s: map provides depots" % world.id)
		var caches := raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer)
		check(caches.size() >= 4, "%s: loot caches are placed (%d)" % [world.id, caches.size()])
		var all_valid := true
		for cache: LootContainer in caches:
			for id in cache.items:
				if not ItemDB.has_item(id):
					all_valid = false
		for bot in raid.bots:
			for id in bot.get_drop_items():
				if not ItemDB.has_item(id):
					all_valid = false
		check(all_valid, "%s: every cache and bot carries real items" % world.id)
		for bot in raid.bots:
			check(bot.weapons.size() > 0 and bot.faction != raid.player.faction,
					"%s: %s is armed and hostile" % [world.id, bot.display_name])
			break
		await frames(120)
		check(raid.clock > 1.0 and raid.bots.size() + raid._bot_respawns.size() == world.bot_count + raid._bosses.size(),
				"%s: the world runs with bots thinking" % world.id)
		await _end_raid(raid)


func _test_frostline() -> void:
	print("Frostline")
	var world := Worlds.get_world("frostline")
	check(world != null, "frostline is discovered from its folder")
	if world == null:
		return
	check(ItemDB.has_item("frost_signal_core") and ItemDB.has_tag("frost_ice_axe", "melee"),
			"a world registers its own items")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var relay := world.roll_loot("relay", rng)
	check(relay.size() >= 3, "the relay mast cache rolls rich loot")
	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 7)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	var factions := {}
	for bot in raid.bots:
		factions[bot.faction] = factions.get(bot.faction, []) + [bot]
	check(factions.has("warden") and factions.has("feral"), "both enemy factions spawn")
	var relay_caches := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and n.global_position.y > 20.0)
	check(relay_caches.size() == 1, "a cache sits on top of the relay mast")
	if factions.has("warden") and factions.has("feral"):
		var warden: Actor = factions.warden[0]
		var feral: Actor = factions.feral[0]
		check(Combat.deal(feral, DamageInfo.make(5.0, warden, "bullet")), "wardens and ferals hurt each other")
		check(Combat.deal(raid.player, DamageInfo.make(5.0, feral, "melee")), "ferals hurt the player")
		var ally := Actor.new()
		raid.add_child(ally)
		check(not Combat.deal(ally, DamageInfo.make(5.0, raid.player, "bullet"))
				and not Combat.deal(raid.player, DamageInfo.make(5.0, ally, "bullet")),
				"players cannot hurt each other on a PvE world")
		ally.queue_free()
		if factions.warden.size() >= 2:
			check(not Combat.deal(factions.warden[1], DamageInfo.make(5.0, warden, "bullet")),
					"a faction does not hurt itself")
	# The gentle world: basic loot, and death only costs the backpack.
	var gear_tags := ["weapon", "armor", "flight_rig", "ability", "vehicle"]
	var too_good: Array[String] = []
	for source: String in ["cache", "rooftop", "relay", "warden", "feral", "vehicle"]:
		for i in 300:
			for id in world.roll_loot(source, rng):
				var is_gear := gear_tags.any(func(tag: String) -> bool: return ItemDB.has_tag(id, tag))
				if is_gear and ItemDB.item_rarity(id) > ItemDB.Rarity.UNCOMMON and not id.begins_with("frost_") \
						and id not in too_good:
					too_good.append(id)
	check(too_good.is_empty(), "Frostline only drops basic gear, apart from its own (%s)" % ", ".join(too_good))
	var ash_gear: Array[String] = []
	var ashfront := Worlds.get_world("ashfront")
	for i in 300:
		for id in ashfront.roll_loot("rooftop", rng):
			if ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE and ItemDB.has_tag(id, "weapon") and id not in ash_gear:
				ash_gear.append(id)
	check(ash_gear.size() >= 3, "the PvP world is where rare weapons drop (%d kinds)" % ash_gear.size())
	await _end_raid(raid)
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "frame_trooper"])
	Profile.equip("primary", "rifle_carbine")
	Profile.equip("frame", "frame_trooper")
	raid = Raid.new()
	add_child(raid)
	raid.start(world, 8, Profile.checkout_loadout(world))
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	var gentle: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: gentle.append(r))
	raid.player.inventory.add_item("frost_cryo_cell")
	raid.player.kill("melee", raid.bots[0])
	await frames(2)
	var dropped := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	check(dropped.size() == 1 and "frost_cryo_cell" in (dropped[0] as LootContainer).items
			and "rifle_carbine" not in (dropped[0] as LootContainer).items,
			"on a gentle world only the backpack drops when you die")
	check(gentle.size() == 1 and gentle[0].outcome == "died" and "rifle_carbine" in gentle[0].kept_gear
			and "frost_cryo_cell" in gentle[0].lost and "rifle_carbine" not in gentle[0].lost
			and Hud.death_text(gentle[0], 0.0).contains("Kept"),
			"the result says what was kept and what was lost")
	check("rifle_carbine" in Profile.stash and "frame_trooper" in Profile.stash
			and Profile.equipped("primary") == "rifle_carbine" and "frost_cryo_cell" not in Profile.stash,
			"your equipped gear is back in the stash and still in the loadout")
	var kit_again := Profile.checkout_loadout(world)
	check("rifle_carbine" in kit_again, "so you drop back in with the same gear")
	Profile.reset()
	Profile.welcome_granted = true
	# The ice axe is real gear: it equips as a melee weapon with its stats.
	var axe_holder := Actor.new()
	add_child(axe_holder)
	Loadout.equip(axe_holder, ["frost_ice_axe"])
	var axe := axe_holder.weapons[0] as MeleeWeapon if not axe_holder.weapons.is_empty() else null
	check(axe != null and is_equal_approx(axe.heavy_lunge, 12.0), "the ice axe equips with its own stats")
	axe_holder.queue_free()
	await _end_raid(raid)
const MasteryDB := preload("res://core/progression/mastery_db.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const MasteryPanel := preload("res://core/progression/mastery_panel.gd")


func _mastery_raid(p_seed: int, kit: Array[String], picks: Dictionary) -> Raid:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed, kit, picks)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(5)
	return raid


func _test_mastery() -> void:
	print("Mastery")
	# Data: every track is reachable from an item, and every variant names real
	# stats and changes at least two of them (a sidegrade, not an upgrade).
	var item_for := {}
	for id in ["rifle_scrap", "rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher",
			"blade_scrap", "blade_arc", "hammer_breaker", "knife_gutter", "axe_splitter", "spear_lancer", "chip_blink", "chip_barrier", "chip_pulse",
			"plate_light", "frame_runner", "frame_trooper", "frame_bulwark"]:
		item_for[MasteryDB.track_for_item(id)] = id
	check(not item_for.has("") and item_for.size() == MasteryDB.TRACKS.size(),
			"every weapon, ability and frame trains a mastery track, and every track has gear")
	check(MasteryDB.track_for_item("jetpack_mk1") == "" and MasteryDB.track_for_item("medkit") == "",
			"flight rigs and consumables have no mastery")
	var bad: Array[String] = []
	for track: String in MasteryDB.TRACKS:
		var target: Object = null
		if ItemDB.has_tag(item_for[track], "firearm"):
			target = Gun.new()
		elif ItemDB.has_tag(item_for[track], "melee"):
			target = MeleeWeapon.new()
		elif ItemDB.has_tag(item_for[track], "ability"):
			target = Ability.new()
		for v: Dictionary in MasteryDB.variants(track):
			if v.mods.size() < 2:
				bad.append("%s/%s trades nothing" % [track, v.id])
			for stat: String in v.mods:
				if target != null and not stat in target or target == null and stat not in ["armor", "speed", "heat"]:
					bad.append("%s/%s: %s" % [track, v.id, stat])
		if target is Node:
			target.free()
	check(bad.is_empty(), "every variant changes real stats with a tradeoff %s" % [bad])

	# Levels and picks.
	check(MasteryDB.level_for_xp(0) == 0 and MasteryDB.level_for_xp(150) == 1
			and MasteryDB.level_for_xp(99999) == MasteryDB.max_level(), "XP maps to levels")
	var book := MasteryBook.new()
	check(not book.pick("rifle", "long_barrel"), "a locked variant cannot be picked")
	check(book.add_xp("rifle", 450) == 2 and book.level("rifle") == 2, "XP raises the level")
	check(book.pick("rifle", "long_barrel") and book.active_picks() == {"rifle": "long_barrel"},
			"an unlocked variant can be picked")
	check(not book.pick("rifle", "cut_down"), "higher variants stay locked")
	check(book.add_xp("nonsense", 100) == 0 and not book.xp.has("nonsense"), "unknown tracks are ignored")
	var copy := MasteryBook.new()
	copy.load_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	check(copy.xp_for("rifle") == 450 and copy.picked("rifle") == "long_barrel", "mastery survives a save")
	copy.load_dict({"xp": {"rifle": 10}, "picks": {"rifle": "long_barrel", 5: "x"}})
	check(copy.picked("rifle") == "" and copy.active_picks().is_empty(),
			"a saved pick above the saved level is dropped")

	# Variants change the gear the player deploys with, and only theirs.
	var kit: Array[String] = ["rifle_carbine", "blade_scrap", "jetpack_mk1", "frame_runner", "chip_blink"]
	var stock := await _mastery_raid(70, kit, {})
	var sp := stock.player
	var stock_gun := sp.weapons[0] as Gun
	var stock_spread := stock_gun.spread_deg
	var stock_interval := stock_gun.fire_interval
	var stock_armor := sp.health.max_armor
	var stock_speed := sp.walk_speed
	var stock_cd := sp.ability.cooldown
	await _end_raid(stock)
	var picks := {"rifle": "long_barrel", "frame_light": "stripped", "blink": "ward_step"}
	var raid := await _mastery_raid(70, kit, picks)
	var p := raid.player
	var gun := p.weapons[0] as Gun
	check(gun.spread_deg < stock_spread and gun.fire_interval > stock_interval,
			"Long Barrel: tighter spread, slower fire")
	check(p.health.max_armor < stock_armor and p.walk_speed > stock_speed, "Stripped frame: less armor, faster")
	check(p.ability.cooldown > stock_cd and p.ability.blink_shield > 0.0, "Ward Step: shield, longer cooldown")
	var bot := raid.bots[0]
	var stock_bots := true
	for other in raid.bots:
		for w in other.weapons:
			var stats := ItemDB.item_stats(w.item_id)
			if w is Gun and stats.has("spread_deg") and not is_equal_approx((w as Gun).spread_deg, stats.spread_deg):
				stock_bots = false
	check(stock_bots and raid.mastery.actor == p, "bots deploy without the player's variants")

	# Ward Step: arriving from a blink is shielded.
	p.ability.activate()
	var before := p.health.health + p.health.armor
	Combat.deal(p, DamageInfo.make(20.0, bot, "bullet"))
	var loss: float = before - (p.health.health + p.health.armor)
	check(loss > 0.0 and loss < 10.0, "Ward Step shields you right after the blink (lost %.1f of 20)" % loss)

	# XP is earned by type: weapon hits and kills, ability uses, hits taken in the frame.
	var tracker := raid.mastery
	check(tracker.earned.get("blink", 0.0) >= tracker.xp_per_ability_use, "using an ability trains it")
	check(tracker.earned.get("frame_light", 0.0) > 0.0, "taking hits trains your frame")
	Combat.deal(bot, DamageInfo.make(30.0, p, "bullet"))
	check(is_equal_approx(tracker.earned.get("rifle", 0.0), 30.0 * tracker.xp_per_damage),
			"hitting with a rifle trains rifle mastery")
	var bot_hp := bot.health.health + bot.health.armor + 1.0
	Combat.deal(bot, DamageInfo.make(bot_hp, p, "bullet"))
	check(bot.is_dead and tracker.earned.rifle >= bot_hp * tracker.xp_per_damage + tracker.xp_per_kill,
			"kills give bonus XP")
	check(not tracker.earned.has("blade"), "a holstered weapon earns nothing")

	# Dying keeps every point of mastery earned.
	Profile.reset()
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	p.kill("storm")
	await frames(2)
	var gained: Dictionary = results[0].get("mastery_xp", {}) if results.size() == 1 else {}
	check(results.size() == 1 and results[0].outcome == "died" and gained.get("rifle", 0) > 0,
			"the raid result reports mastery XP even on death")
	check(Profile.mastery.xp_for("rifle") == gained.get("rifle", -1)
			and Profile.mastery.xp_for("blink") == gained.get("blink", -1), "dying banks that XP in the profile")
	check(Profile.stash.is_empty(), "the gear itself is still lost")
	await _end_raid(raid)

	# Leaving alive pays no bonus, so signing out again and again trains nothing.
	raid = await _mastery_raid(71, kit, {})
	check(raid.mastery.report().is_empty(), "carrying gear alone earns no mastery")
	await _end_raid(raid)

	# Hub: the panel shows the tracks of your loadout and what a raid earned.
	Profile.reset()
	Profile.loadout = StashRules.starter_loadout()
	var panel := MasteryPanel.new()
	add_child(panel)
	check(panel.loadout_tracks() == ["rifle", "blade", "frame_light"],
			"the scrap kit shows its mastery")
	Profile.mastery.add_xp("rifle", 200)
	var text := panel.describe_earned({"mastery_xp": {"rifle": 100}})
	check("Rifle +100" in text and "level 1!" in text, "the hub announces a level up")
	panel.refresh()
	await frames(1)
	check(panel._rows.get_child_count() == 3, "one row per loadout track")
	panel.queue_free()
	Profile.reset()


# --- Online ------------------------------------------------------------------

func _wait_until(condition: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await frames(1)
	return condition.call()


const NET_ACCOUNTS := "user://test_accounts_net"
var _net_secrets := {}


func _wipe_dir(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for sub in DirAccess.get_directories_at(dir):
			_wipe_dir(dir.path_join(sub))
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _start_server(port: int, extra: Array[String], world := "ashfront") -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server", "--world", world, "--port", str(port), "--accounts", NET_ACCOUNTS])
	# One world alone on the port, unless the test asks for the plaza too.
	if "--plaza" not in extra:
		args.append("--no-plaza")
	# Like this process (see `_ready`), unless the test checks the gates.
	if "--zone-rules" not in extra:
		args.append("--no-zone-rules")
	args.append_array(PackedStringArray(extra))
	return OS.create_process(OS.get_executable_path(), args)


## A client in its own 3D world, so two clients in this process never collide.
## Each name keeps one secret for the whole test run, like a real player.
func _new_client(shown_name: String, secret := "") -> NetSession:
	var view := SubViewport.new()
	view.own_world_3d = true
	add_child(view)
	var session := NetSession.new()
	session.name = "Net"
	session.player_name = shown_name
	if not _net_secrets.has(shown_name):
		_net_secrets[shown_name] = StashService.new_secret()
	session.secret = secret if secret != "" else _net_secrets[shown_name]
	view.add_child(session)
	return session


## Connects and signs in, retrying while the server process is still starting
## up. Returns the session in the lobby, or null.
func _sign_in(session_name: String, port: int) -> NetSession:
	for attempt in 20:
		var session := _new_client(session_name)
		var state := {"failed": false}
		session.failed.connect(func(_reason: String) -> void: state.failed = true)
		session.join("127.0.0.1", port)
		await _wait_until(func() -> bool: return state.failed or not session.account.is_empty(), 240)
		if not session.account.is_empty():
			return session
		session.get_parent().queue_free()
		await frames(30)
	return null


## Signs in, equips `gear` (slot -> item id) in the lobby, and deploys.
## A new account starts bare, so test players put on the scrap kit first and
## `gear` on top of it.
func _join(session_name: String, port: int, p_gear := {}) -> NetSession:
	var session := await _sign_in(session_name, port)
	if session == null:
		return null
	var gear := StashRules.starter_loadout()
	gear.merge(p_gear, true)
	for slot: String in gear:
		session.equip(slot, gear[slot])
	await _wait_until(func() -> bool:
		return gear.keys().all(func(slot: String) -> bool:
			return session.account.loadout.get(slot, "") == gear[slot]), 120)
	session.deploy()
	await _wait_until(func() -> bool: return session.raid != null and session.raid.player != null, 240)
	if session.raid != null and session.raid.player != null:
		return session
	session.get_parent().queue_free()
	await frames(2)
	return null


func _leave(session: NetSession) -> void:
	if session != null and is_instance_valid(session):
		session.get_parent().queue_free()
	await frames(2)


func _test_nameplates_and_scoreboard() -> void:
	print("Nameplates and scoreboard")
	check(InputMap.has_action("scoreboard") and InputMap.action_get_events("scoreboard").any(
			func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_Q),
			"Q is bound to the scoreboard")
	var raid := Raid.new()
	add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player([], {}, "Bravo")
	var c := raid.add_player([], {}, "Charlie")
	await frames(5)
	var roster := RaidRoster.new(raid, a)
	roster.refresh()
	var board := ScoreboardScript.new()
	board.setup(raid, a)
	raid.add_child(board)
	await frames(1)
	check(roster.entries.size() == 3 and roster.entries.all(
			func(e: Dictionary) -> bool: return e.status == RaidRoster.IN_RAID),
			"the roster lists every player as in the raid")
	check(roster.bots_alive() == raid.bots.size(), "the roster counts the bots still standing")
	b.kill("bullet", a)
	raid._leave(raid.state_for(c))
	await frames(3)
	roster.refresh()
	var by_name := {}
	for e in roster.entries:
		by_name[e.name] = e
	check(by_name.Alpha.kills == 1 and by_name.Alpha.is_me and by_name.Alpha.status == RaidRoster.IN_RAID,
			"your kills are counted on the scoreboard")
	check(by_name.Bravo.status == RaidRoster.DOWN, "a player who died shows as down")
	check(by_name.Charlie.status == RaidRoster.LEFT, "a player who left alive shows as left")
	check(roster.entries[0].name == "Alpha", "players still in the raid are listed first")

	# Bravo drops back in as a new actor and stays one row on the board.
	var b2 := raid.add_player([], {}, "Bravo")
	raid.bots[0].kill("bullet", b2)
	await frames(2)
	roster.refresh()
	check(roster.entries.size() == 3 and by_name.Bravo.status == RaidRoster.IN_RAID and by_name.Bravo.kills == 1,
			"a player who drops back in keeps one row on the board")
	b2.kill("bullet", a)
	b = raid.add_player([], {}, "Bravo")
	raid.bots[0].kill("bullet", b)
	b.kill("bullet", a)
	await frames(2)
	roster.refresh()
	check(roster.entries.size() == 3 and by_name.Bravo.kills == 2 and by_name.Bravo.status == RaidRoster.DOWN
			and by_name.Alpha.kills == 3, "kills add up across a player's lives")

	check(not board.visible, "the scoreboard is closed until asked for")
	board.show_board(true)
	var rows: Array = board.rows()
	check(board.visible and rows.size() == 3 and rows[0].slice(0, 3) == ["Alpha (you)", RaidRoster.IN_RAID, "3"],
			"the scoreboard shows each player's name, status and kills")
	board.show_board(false)
	check(not board.visible, "the scoreboard closes again")

	# Nameplates, high above the map so only the test's own wall can block the view.
	var d := raid.add_player([], {}, "Delta")
	var camera := Camera3D.new()
	raid.add_child(camera)
	camera.make_current()
	var plates := NameplatesScript.new()
	plates.setup(raid, a)
	raid.add_child(plates)
	var sky := a.global_position + Vector3(0, 120, 0)
	var place := func(d_offset: Vector3, facing: Vector3) -> void:
		a.global_position = sky
		d.global_position = sky + d_offset
		b.global_position = sky + Vector3(0, 0, -5)
		camera.global_position = sky + Vector3(0, 1.6, 0)
		camera.look_at(camera.global_position + facing)
		plates.update_plates()
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	var shown: Dictionary = plates.plates()
	check(shown.has(d.get_instance_id()) and not shown.has(a.get_instance_id()),
			"another player in view gets a nameplate, you do not")
	check(not shown.has(b.get_instance_id()), "a player who is down has no nameplate")
	if shown.has(d.get_instance_id()):
		var plate: Control = shown[d.get_instance_id()]
		var label: Label = plate.get_child(0)
		var middle := camera.get_viewport().get_visible_rect().size * 0.5
		check(label.text == "Delta  Recruit" and plate.position.x < middle.x and plate.position.x + plate.size.x > middle.x,
				"the nameplate carries the name and rank and sits over the player")
	place.call(Vector3(0, -0.5, -10), Vector3.BACK)
	check(plates.plates().is_empty(), "no nameplate for a player behind you")
	place.call(Vector3(0, -0.5, -(plates.max_distance + 5.0)), Vector3.FORWARD)
	check(plates.plates().is_empty(), "no nameplate past the nameplate range")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(6, 6, 0.5)
	wall.add_child(shape)
	raid.add_child(wall)
	wall.global_position = sky + Vector3(0, 1, -5)
	await frames(1)
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	check(plates.plates().is_empty(), "no nameplate through a wall")
	wall.queue_free()
	await frames(1)
	d.kill("bullet")
	place.call(Vector3(0, -0.5, -10), Vector3.FORWARD)
	check(plates.plates().is_empty(), "the nameplate goes when the player goes down")
	await _end_raid(raid)


func _test_renown() -> void:
	print("Renown and bounties")
	# The ledger on its own: plain arithmetic.
	var book := RenownLedger.new()
	book.enter("ana", "Ana", 190)
	book.enter("ben", "Ben")
	check(book.bot_killed("ana") == 10 and book.bot_killed("ana") == 11,
			"a bot kill pays renown, and each kill in a streak pays a little more")
	var ana := book.get_standing("ana")
	check(ana.renown == 21 and ana.lifetime == 211 and RenownLedger.rank_for(ana.lifetime) == 1
			and RenownLedger.rank_name(1) == "Raider", "lifetime renown raises your rank")
	check(RenownLedger.to_next_rank(211) == 589 and RenownLedger.to_next_rank(999999) == 0,
			"the next rank says how far away it is")
	book.get_standing("ben").renown = 400
	check(book.marked() == "ben", "the living player with the most renown is the Marked")
	var paid := book.player_died("ben", "ana")
	check(paid.lost == 40 and paid.stolen == 40 and paid.marked and book.get_standing("ben").renown == 360,
			"dying costs a tenth of your session renown")
	check(paid.gain == 120 + 40 + book.marked_bonus and ana.renown == 21 + paid.gain,
			"the killer gets the kill, the stolen share and the bonus for the Marked")
	check(book.marked() == "ana", "a dead player is not the Marked")
	book.enter("ben", "Ben")
	check(book.get_standing("ben").renown == 360, "session renown carries into the next life")
	var before := ana.renown
	check(book.player_died("ben", "ana", true).gain == roundi(10 * 1.3) + 36,
			"killing someone in the scrap kit pays almost nothing for the kill")
	check(book.bounty_of("ana") == 0, "two player kills are not a bounty yet")
	book.enter("ben", "Ben")
	book.player_died("ben", "ana", true)
	check(book.bounty_of("ana") == 150 and not book.is_exposed("ana"), "three player kills in one life put a price on you")
	for i in 2:
		book.enter("ben", "Ben")
		book.player_died("ben", "ana", true)
	check(book.bounty_of("ana") == 250 and book.is_exposed("ana"), "five show you to everyone")
	book.enter("cy", "Cy")
	var claim := book.player_died("ana", "cy")
	check(claim.bounty == 250 and claim.gain >= 250 + 100 and book.bounty_of("ana") == 0
			and ana.player_streak == 0, "the killer collects the bounty and the streak ends")
	check(ana.lifetime > before + 190, "death never takes lifetime renown")
	book.leave("ana")
	check(book.get_standing("ana") == null, "leaving the world ends the session")

	# In a running world.
	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 91)
	# Keep the war quiet here, so kills pay their plain value.
	raid.war.scale = 0.0
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var results := {}
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void:
		results[actor.display_name] = result)
	var kit: Array[String] = ["rifle_carbine", "frame_trooper"]
	var hunter := raid.add_player(kit, {}, "Hunter", "acct-hunter", 900)
	var prey := raid.add_player(kit, {}, "Prey", "acct-prey", 0)
	await frames(3)
	check(hunter.rank == 2 and prey.rank == 0 and hunter.renown == 0, "a player arrives with their rank and no session renown")
	var notices: Array[String] = []
	hunter.notice.connect(func(text: String) -> void: notices.append(text))
	raid.bots[0].kill("bullet", hunter)
	check(hunter.renown == 10 and hunter.streak == 1 and notices.size() == 1
			and notices[0].begins_with("Killed ") and notices[0].ends_with("+10 renown"),
			"killing a bot pays renown and says so")
	check(feed.is_empty(), "bot kills stay out of the world feed")
	raid.renown.get_standing("acct-prey").renown = 500
	prey.kill("bullet", hunter)
	await frames(2)
	check(results.has("Prey") and results.Prey.renown_lost == 50 and results.Prey.renown_now == 450,
			"a death reports the renown it cost")
	check(hunter.renown == 10 + 110 + 50 + raid.renown.marked_bonus,
			"the killer is paid for the kill, the share and the Marked (%d)" % hunter.renown)
	check(feed.has("Hunter [Veteran] killed Prey [Recruit], the Marked"), "a player kill is announced with ranks (%s)" % " / ".join(feed))
	check(hunter.marked and feed.has("Hunter is now the Marked"), "the new Marked is announced")
	check("Renown lost: 50" in Hud.death_text(results.Prey, 0.0), "the death screen shows the renown lost")
	for i in 2:
		prey = raid.add_player(kit, {}, "Prey", "acct-prey", 0)
		await frames(1)
		prey.kill("bullet", hunter)
		await frames(1)
	check(hunter.bounty == 150 and feed.has("Hunter has a bounty of 150"), "three player kills announce a bounty")
	check(Hud.standing_text(hunter).begins_with("Veteran   Renown ") and "BOUNTY 150" in Hud.standing_text(hunter)
			and "THE MARKED" in Hud.standing_text(hunter), "the HUD shows your rank, renown and bounty")
	check(NameplatesScript.plate_text(hunter) == "Hunter  Veteran  MARKED  Bounty 150", "a nameplate shows rank, the Marked and the bounty")
	var roster := RaidRoster.new(raid, prey)
	roster.refresh()
	var row: Dictionary = roster.entries.filter(func(e: Dictionary) -> bool: return e.name == "Hunter")[0]
	check(ScoreboardScript.renown_cell(row) == "Veteran  %d  MARKED  Bounty 150" % hunter.renown, "the scoreboard lists renown and bounties")
	for i in 2:
		prey = raid.add_player(kit, {}, "Prey", "acct-prey", 0)
		await frames(1)
		prey.kill("bullet", hunter)
		await frames(1)
	check(hunter.exposed and feed.any(func(text: String) -> bool: return text.begins_with("Hunter is exposed")),
			"five player kills expose you to everyone")

	# A hunted player's plate shows through a wall and at any distance.
	var far := raid.add_player(kit, {}, "Far", "acct-far", 0)
	var camera := Camera3D.new()
	raid.add_child(camera)
	camera.make_current()
	var plates := NameplatesScript.new()
	plates.setup(raid, far)
	raid.add_child(plates)
	hunter.global_position = Vector3(0, 300, -200)
	far.global_position = Vector3(0, 300, 0)
	camera.global_position = Vector3(0, 301.6, 0)
	camera.look_at(Vector3(0, 301.6, -200))
	await frames(2)
	plates.update_plates()
	check(plates.plates().has(hunter.get_instance_id()), "an exposed player's nameplate shows from across the map")
	hunter.exposed = false
	hunter.marked = false
	plates.update_plates()
	check(not plates.plates().has(hunter.get_instance_id()), "an ordinary player's does not")
	plates.queue_free()
	camera.queue_free()

	# The bounty is paid out, and renown reaches the account.
	var earned_before := hunter.renown
	var avenger := raid.add_player(kit, {}, "Avenger", "acct-avenger", 0)
	await frames(1)
	hunter.kill("bullet", avenger)
	await frames(2)
	check(avenger.renown >= 250 + 100 and feed.any(func(text: String) -> bool:
			return text.begins_with("Avenger [") and text.ends_with("and claimed a bounty of 250")),
			"killing a hunted player pays their bounty")
	check(results.Hunter.renown >= 0 and results.Hunter.renown_lost == int(floor(earned_before * 0.1)),
			"the hunted player's last life reports its renown")
	var avenger_renown := avenger.renown
	raid.clock += 1000.0
	raid.begin_sign_out(avenger)
	for i in 800:
		if results.has("Avenger"):
			break
		await frames(1)
	check(results.has("Avenger") and results.Avenger.outcome == "left" and results.Avenger.renown == avenger_renown
			and raid.renown.get_standing("acct-avenger") == null,
			"signing out keeps the renown you earned and ends the session")
	var was_persist := Profile.persist
	Profile.persist = false
	var had := Profile.renown
	Profile.record_raid({"outcome": "died", "renown": 75})
	check(Profile.renown == had + 75, "lifetime renown is saved with the profile")
	Profile.renown = had
	Profile.raids_played -= 1
	Profile.persist = was_persist
	check(Hub.renown_text(250) == "Rank Raider   Renown 250   (550 to Veteran)", "the hub shows your rank and what the next one takes")
	await _end_raid(raid)


func _test_war() -> void:
	print("War intensity")
	# The director on its own.
	var war := WarDirector.new()
	check(war.intensity == 0.0 and war.level_name() == "Quiet" and war.renown_bonus() == 1.0, "a new world is quiet")
	war.report_kill(Vector3(10, 0, 0), false)
	var after_bot := war.intensity
	war.report_kill(Vector3(30, 0, 0), true)
	check(after_bot > 0.0 and war.intensity - after_bot > after_bot, "kills heat the war up, a player's death most of all")
	check(war.centre.x > 10.0 and war.centre.x < 30.0, "the centre of the fighting drifts towards the newest kill")
	var before := war.intensity
	war.tick(5.0)
	check(war.intensity == before, "the heat holds for a while after the last kill")
	war.tick(war.calm_delay)
	war.tick(1.0)
	check(war.intensity < before, "then it cools")
	before = war.intensity
	var clash: Array[Vector3] = [Vector3(0, 0, 50)]
	war.tick(1.0, clash)
	check(war.intensity > before, "hostile players close together heat it up")
	for i in 400:
		war.report_kill(Vector3.ZERO, true)
	check(war.intensity == 1.0 and war.level_name() == "All-out war" and war.renown_bonus() == 1.5,
			"the meter tops out at 1, where kills pay half as much renown again")
	check(WarDirector.level_for(0.3) == "Skirmish" and WarDirector.level_for(0.6) == "Battle", "the meter has names for its stretches")
	war.tick(10000.0)
	war.tick(10000.0)
	check(war.intensity == 0.0, "a world left alone goes quiet again")
	var still := WarDirector.new()
	still.scale = 0.0
	still.report_kill(Vector3.ZERO, true)
	still.tick(1.0, clash)
	check(still.intensity == 0.0, "a world can keep its war meter still")

	# In a running world.
	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 93)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player([], {}, "Bravo")
	a.global_position = Vector3(0, 300, 0)
	b.global_position = Vector3(0, 300, 200)
	a.set_physics_process(false)
	b.set_physics_process(false)
	await frames(30)
	check(raid.war.intensity == 0.0, "players far apart are not a war, however many there are")
	b.global_position = Vector3(0, 300, 20)
	await frames(30)
	var brewing := raid.war.intensity
	check(brewing > 0.0 and raid.war.centre.distance_to(Vector3(0, 300, 10)) < 1.0, "two hostile players near each other are (%.3f)" % brewing)
	check(is_equal_approx(raid.map.get_meta("war_intensity"), raid.war.intensity)
			and raid.map.get_meta("war_centre") == raid.war.centre, "the map is told how hot the war is, for the sky")
	b.global_position = Vector3(0, 300, 200)
	raid.bots[0].kill("bullet", a)
	await frames(2)
	check(raid.war.intensity > brewing, "a player killing a bot adds to it")
	var mid := raid.war.intensity
	raid.bots[1].kill("bullet", raid.bots[2])
	await frames(2)
	check(raid.war.intensity > mid and raid.war.intensity - mid < 0.02, "bots killing each other only keep it simmering")
	raid.war.intensity = raid.war.battle_ceiling
	raid.bots[1].kill("bullet", raid.bots[2])
	await frames(2)
	check(raid.war.intensity <= raid.war.battle_ceiling, "and never take it past a skirmish on their own")
	raid.war.intensity = 1.0
	await frames(2)
	var paid := a.renown
	raid.bots[3].kill("bullet", a)
	check(a.renown - paid > roundi(10 * 1.1), "kills pay more renown in a hot war (%d)" % (a.renown - paid))
	check(Hud.standing_text(a) != "" and WarDirector.level_for(raid.war.intensity) == "All-out war", "the HUD can name the war's level")
	await _end_raid(raid)
	check(Worlds.get_world("frostline").war_scale == 0.0 and Worlds.get_world("ashfront").war_scale > 0.0,
			"Frostline stays quiet and Ashfront does not")

	# The mood: a blend between the calm and the war atmosphere a map supplies.
	var calm := Look.mood_values({"sun_energy": 2.0, "fog_color": Color(0.4, 0.4, 0.4)})
	var battle := Look.mood_values({"sun_energy": 1.0}, calm)
	check(battle.fog_color == calm.fog_color and battle.sun_energy == 1.0, "a war mood only says what changes")
	var half := Look.blend_moods(calm, battle, 0.5)
	check(is_equal_approx(half.sun_energy, 1.5) and Look.blend_moods(calm, battle, 0.0).sun_energy == 2.0
			and Look.blend_moods(calm, battle, 7.0).sun_energy == 1.0, "the mood blends with the meter and stops at the war mood")


func _test_strongpoints() -> void:
	print("Strongpoints")
	# One site on its own.
	var site := Strongpoint.new()
	site.title = "Mill"
	site.capture_time = 10.0
	add_child(site)
	check(site.covers(Vector3(5, 2, 5)) and not site.covers(Vector3(40, 0, 0)) and not site.covers(Vector3(0, 90, 0)),
			"a site covers the ground around it, not the sky far above")
	var red := {"red": {"count": 1, "name": "Red", "player": true}}
	check(not site.tick(4.0, red) and site.taker == "red" and is_equal_approx(site.progress, 0.4), "standing in a site alone starts taking it")
	check(site.status(false) == "Mill: unclaimed, Red taking it 40%", "its status says who is taking it")
	var both := red.duplicate()
	both["blue"] = {"count": 2, "name": "Blue", "player": false}
	site.tick(50.0, both)
	check(site.contested and is_equal_approx(site.progress, 0.4), "two sides inside freeze it")
	site.tick(1.0, {})
	check(not site.contested and is_equal_approx(site.progress, 0.2), "an abandoned capture drains away")
	check(site.tick(8.0, red) and site.holder == "red" and site.holder_is_player and site.progress == 0.0, "finishing the capture takes the site")
	check(site.status(true) == "Mill: yours" and site.status(false) == "Mill: held by Red", "its status says who holds it")
	var crowd := {"blue": {"count": 3, "name": "Blue", "player": false}}
	site.tick(4.0, crowd)
	check(is_equal_approx(site.progress, 0.6), "a crowd takes a site faster")
	site.tick(1.0, red)
	check(site.taker == "blue" and site.progress < 0.6, "the holder standing in it pushes a capture back")
	site.queue_free()

	# In a running co-op world.
	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("frostline"), 97)
	check(raid.strongpoints.size() == 3 and raid.strongpoints[0].title == "Echo Post"
			and raid.strongpoints.all(func(p: Strongpoint) -> bool: return p.holder == "faction:warden" and not p.holder_is_player),
			"Frostline has three strongpoints, held by the Wardens to begin with")
	for i in raid.bots.size():
		var bot := raid.bots[i]
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(400 + i * 4, 0, 400)
	var point := raid.strongpoints[0]
	for p in raid.strongpoints:
		p.capture_time = 0.3
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var a := raid.add_player([], {}, "Alpha", "acct-a")
	var b := raid.add_player([], {}, "Bravo", "acct-b")
	a.set_physics_process(false)
	b.set_physics_process(false)
	b.global_position = Vector3(-300, 0, -300)
	var notices: Array[String] = []
	a.notice.connect(func(text: String) -> void: notices.append(text))
	a.global_position = point.global_position + Vector3(2, 0, 0)
	check(raid.strongpoint_at(a) == point and Hud.sites_text(raid, a) == "Echo Post: held by the Wardens", "the HUD names the site you stand in")
	await frames(40)
	check(point.holder == "players" and point.holder_is_player and raid.holds(a, point) and raid.holds(b, point),
			"in a co-op world a site one player takes belongs to them all")
	check(feed.has("The raiders took Echo Post from the Wardens"), "taking a site from the bots is announced (%s)" % " / ".join(feed))
	check(a.renown == 150 and b.renown == 0 and notices.has("Took Echo Post   +150 renown"), "the players who were there are paid renown")
	check(Hud.sites_text(raid, a) == "Echo Post: yours" and Hud.sites_text(raid, b) == "Held 1/3",
			"the HUD shows what you hold")
	var warden: Actor = raid.bots.filter(func(bot: Actor) -> bool: return bot.faction == "warden")[0]
	warden.global_position = point.global_position + Vector3(-3, 0, 0)
	await frames(5)
	check(point.contested and point.holder == "players" and "contested" in Hud.sites_text(raid, a), "an enemy walking in contests it")
	a.global_position = Vector3(-300, 0, -280)
	await frames(40)
	check(point.holder == "faction:warden" and not raid.holds(a, point) and feed.has("The Wardens took Echo Post from the raiders"),
			"bots left alone in a site take it back, and everyone hears")
	warden.global_position = Vector3(380, 0, 400)
	a.global_position = point.global_position
	await frames(40)
	check(raid.holds(a, point), "and it can be taken again")

	# A site you hold is where you drop in.
	var c := raid.add_player([], {}, "Charlie", "acct-c")
	check(point.covers(c.global_position), "a player drops in at a strongpoint their side holds")
	warden.global_position = point.global_position + Vector3(-3, 0, 0)
	await frames(3)
	var d := raid.add_player([], {}, "Delta", "acct-d")
	check(not point.covers(d.global_position), "but not at one that is being fought over")
	warden.global_position = Vector3(380, 0, 400)
	await frames(3)

	# The bots push back.
	for bot in raid.bots:
		(bot.get_node("Brain") as BotBrain).post_to(Vector3.ZERO, 10.0)
	raid._assault_in = 0.0
	await frames(2)
	var sent := raid.bots.filter(func(bot: Actor) -> bool:
		return (bot.get_node("Brain") as BotBrain)._home.distance_to(point.global_position) < 0.1)
	check(feed.has("Echo Post is under attack") and sent.size() == Worlds.get_world("frostline").assault_size,
			"every so often bots are sent to retake a site players hold (%d sent)" % sent.size())
	await _end_raid(raid)

	# Where players fight each other, a site is its taker's alone.
	var pvp := Raid.new()
	add_child(pvp)
	pvp.apply_to_profile = false
	pvp.start_server(Worlds.get_world("ashfront"), 98)
	var e := pvp.add_player([], {}, "Echo", "acct-e")
	var f := pvp.add_player([], {}, "Fox", "acct-f")
	check(pvp.side_of(e)[0] == "acct-e" and pvp.side_of(e)[0] != pvp.side_of(f)[0] and pvp.side_of(e)[2],
			"in a PvP world every player is their own side")
	check(pvp.side_of(pvp.bots[0])[0] == "faction:" + pvp.bots[0].faction and not pvp.side_of(pvp.bots[0])[2],
			"and each bot faction is one")
	await _end_raid(pvp)

	# Online: a client hears who holds each site.
	_wipe_dir(NET_ACCOUNTS)
	var port := 24831
	var pid := _start_server(port, ["--bots", "0"], "frostline")
	var gale := await _join("Gale", port)
	check(gale != null, "a client joins a world with strongpoints")
	if gale != null:
		var told := func() -> bool:
			return gale.raid.strongpoints.size() == 3 and gale.raid.strongpoints.all(
					func(p: Strongpoint) -> bool: return p.holder_name == "the Wardens")
		await _wait_until(told, 180)
		check(told.call() and Hud.sites_text(gale.raid, gale.raid.player) == "Held 0/3",
				"the server tells a client who holds each strongpoint")
		await _leave(gale)
	OS.kill(pid)
	await frames(10)


func _test_events() -> void:
	print("World events")
	var world := Worlds.get_world("ashfront")
	var rng := RandomNumberGenerator.new()
	var rarity := func(ids: Array) -> int:
		var total := 0
		for id: String in ids:
			total += ItemDB.item_rarity(id)
		return total
	var quiet := 0
	var hot := 0
	for i in 200:
		rng.seed = i
		quiet += rarity.call(world.roll_war_loot("cache", rng, 0.0))
		rng.seed = i
		hot += rarity.call(world.roll_war_loot("cache", rng, 1.0))
	check(hot > quiet, "caches hold rarer loot in an all-out war (%d against %d)" % [hot, quiet])
	rng.seed = 5
	var plain := world.roll_loot("cache", rng)
	rng.seed = 5
	check(world.roll_war_loot("cache", rng, 0.0) == plain, "a quiet world's loot is unchanged")

	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(world, 41)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var a := raid.add_player([], {}, "Alpha", "acct-a")
	a.set_physics_process(false)
	var before := raid.bots.size()
	check(raid.event.is_empty(), "a world starts with no event running")

	# A supply pod.
	check(raid.start_event("supply_pod") and raid.event.kind == "supply_pod", "a supply pod can come down")
	var pod: LootContainer = raid._event_pod
	check(pod != null and pod.items.size() >= 4 and feed.size() == 1 and feed[0].begins_with("A supply pod came down "),
			"it holds a good haul and everyone hears where it is (%s)" % " / ".join(feed))
	check(not raid.start_event("warlord"), "only one event runs at a time")
	pod.set_items([])
	await frames(3)
	check(raid.event.is_empty(), "the event ends once the pod is emptied")
	await frames(2)

	# A warlord and his escort.
	feed.clear()
	check(raid.start_event("warlord") and raid.bots.size() == before + 1 + world.warlord_escort, "a warlord arrives with an escort")
	var lord: Actor = raid._event_bots.filter(func(b: Actor) -> bool: return raid.warlords.has(b))[0]
	for bot in raid._event_bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	check(lord.display_name == "Warlord" and lord.health.max_health >= 180.0 and feed[0].begins_with("A warlord has arrived "),
			"the warlord is far tougher than his men (%s, %.0f health)" % [lord.display_name, lord.health.max_health])
	var carried := lord.inventory.items.size()
	check(carried >= 3, "the warlord carries loot worth the fight (%d items)" % carried)
	var respawns := raid._bot_respawns.size()
	Combat.deal(lord, DamageInfo.make(9999.0, a, "bullet"))
	await frames(3)
	check(feed.any(func(t: String) -> bool: return t.begins_with("Alpha") and t.ends_with("killed the warlord")),
			"killing the warlord pays renown and is announced (%d, %s)" % [a.renown, " / ".join(feed)])
	check(a.renown >= 310, "the warlord's renown comes on top of the kill (%d)" % a.renown)
	check(raid.event.is_empty() and raid._bot_respawns.size() == respawns, "the event ends with him, and nobody takes his place")

	# An event nobody deals with is cleared away.
	raid.start_event("warlord")
	raid.event.ends = raid.clock
	await frames(3)
	check(raid.event.is_empty() and raid.warlords.size() == raid._bosses.size() and feed.has("The warlord has moved on"),
			"an event nobody answers ends on its own")
	await frames(2)
	check(raid.bots.size() <= before + world.warlord_escort, "and its bots leave with it")

	# The timer.
	raid._event_in = 0.05
	await frames(6)
	check(not raid.event.is_empty(), "events come round on their own")
	raid.queue_free()
	await frames(2)


func _test_drops() -> void:
	print("Drop map")
	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("frostline"), 12)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var ids := func(owner: String) -> Array:
		return raid.drop_choices(owner).map(func(c: Dictionary) -> String: return c.id)
	check(ids.call("acct-a") == ["safe"], "with no war and no ground held there is one place to land")
	var point := raid.strongpoints[1]
	point.hold("players", "the raiders", true)
	check(ids.call("acct-a") == ["safe", "point:1"], "a strongpoint your side holds is offered")
	var a := raid.add_player([], {}, "Alpha", "acct-a", 0, "point:1")
	a.set_physics_process(false)
	check(point.covers(a.global_position), "choosing it lands you there")
	var b := raid.add_player([], {}, "Bravo", "acct-b", 0, "safe")
	b.set_physics_process(false)
	check(not point.covers(b.global_position), "the quiet drop keeps you away from your strongpoints")
	point.contested = true
	check(ids.call("acct-a") == ["safe"], "a site being fought over is not offered")
	point.contested = false
	point.hold("faction:warden", "the Wardens", false)
	var c := raid.add_player([], {}, "Charlie", "acct-c", 0, "point:1")
	c.set_physics_process(false)
	check(not point.covers(c.global_position), "asking for a site you do not hold lands you somewhere quiet")

	# Into the fight.
	raid.war.intensity = 0.6
	raid.war.centre = raid._map_nodes("spawn_player")[0].global_position + Vector3(3, 0, 3)
	check(ids.call("acct-d") == ["safe", "hot"], "once a battle is on you may land beside it")
	var d := raid.add_player([], {}, "Delta", "acct-d", 0, "hot")
	d.set_physics_process(false)
	check(d.global_position.distance_to(raid.war.centre) < 12.0 and d.protected_left > 0.0,
			"that lands you at the nearest drop point to the fighting, still protected (%.0f m)" % d.global_position.distance_to(raid.war.centre))
	raid.war.intensity = 0.0
	var e := raid.add_player([], {}, "Echo", "acct-e", 0, "hot")
	e.set_physics_process(false)
	check(e.global_position.distance_to(d.global_position) > 12.0, "with no battle, asking for one lands you somewhere quiet")

	var result := {"killed_by": "Bot"}
	var text := Hud.death_text(result, 0.0, [{"id": "safe", "title": "Quiet drop", "note": "away from the fighting"},
			{"id": "point:1", "title": "Drift Post", "note": "a strongpoint you hold"}])
	check("1: Quiet drop, away from the fighting" in text and "2: Drift Post, a strongpoint you hold" in text and "Enter" in text,
			"the death screen lists where you can land")
	check(not "1:" in Hud.death_text(result, 0.0, [{"id": "safe", "title": "Quiet drop", "note": ""}])
			and not "1:" in Hud.death_text(result, 2.0, raid.drop_choices("acct-a")),
			"it stays out of the way with one choice, or while you wait")
	raid.queue_free()
	await frames(2)


func _test_scrip() -> void:
	print("Carried scrip")
	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("frostline"), 31)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	var results := {}
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void: results[actor.display_name] = result)
	var a := raid.add_player([], {}, "Alpha", "acct-a")
	var b := raid.add_player([], {}, "Bravo", "acct-b")
	a.set_physics_process(false)
	b.set_physics_process(false)
	a.global_position = Vector3(-200, 0, -200)
	b.global_position = Vector3(-200, 0, -230)
	Combat.deal(raid.bots[0], DamageInfo.make(9999.0, a, "bullet"))
	Combat.deal(raid.bots[0], DamageInfo.make(9999.0, a, "bullet"))
	await frames(2)
	check(a.scrip == 2 * StashService.Economy.KILL_BOUNTY and "%d scrip" % (2 * StashService.Economy.KILL_BOUNTY) in Hud.wrist_text(raid, a, {}, 0.0) and b.scrip == 0,
			"kills pay scrip that you carry (%d)" % a.scrip)

	# Banking makes it safe.
	var depot := raid.depots[0]
	var k := StashService.Economy.KILL_BOUNTY
	depot.actor_banked.emit(a)
	check(a.scrip == 0 and raid.state_for(a).scrip_banked == 2 * k, "a depot banks the scrip you carry")
	Combat.deal(raid.bots[0], DamageInfo.make(9999.0, a, "bullet"))
	await frames(2)
	check(a.scrip == k, "more kills pay more")

	# Dying drops what was not banked.
	a.protected_left = 0.0
	Combat.deal(a, DamageInfo.make(9999.0, raid.bots[1], "bullet"))
	await frames(2)
	var bag: LootContainer = null
	for node in raid.get_children():
		if node is LootContainer and node.is_bag and node.scrip > 0:
			bag = node
	check(bag != null and bag.scrip == k and "%d scrip" % k in bag.get_prompt(), "what you carried drops with your bag (%s)" % (bag.get_prompt() if bag else "no bag"))
	check(results.has("Alpha") and results.Alpha.scrip == 0 and results.Alpha.scrip_banked == 2 * k and results.Alpha.scrip_lost == k
			and StashService.Economy.payout(results.Alpha) == 2 * k and "Scrip dropped: %d" % k in Hud.death_text(results.Alpha, 0.0),
			"the dead keep only what they banked")
	if bag != null:
		bag.interact(b)
		await frames(2)
		check(b.scrip == k, "whoever loots the bag takes the scrip (%d)" % b.scrip)

	# Leaving alive carries it home.
	raid._leave(raid.state_for(b))
	check(results.has("Bravo") and results.Bravo.scrip == k and StashService.Economy.payout(results.Bravo) == k,
			"signing out carries your scrip home")
	raid.queue_free()
	await frames(2)


func _test_online() -> void:
	print("Online: commands and raids with several players")
	var cmd := ActorCommand.new()
	cmd.move = Vector2(0.5, -1.0)
	cmd.yaw = 1.25
	cmd.pitch = -0.4
	cmd.aim_dir = Vector3(0, 0, -1)
	cmd.sprint = true
	cmd.primary = true
	cmd.dash = true
	cmd.ability_pressed = true
	cmd.stance = 2
	cmd.switch_weapon = 1
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	check(copy.move.is_equal_approx(cmd.move) and is_equal_approx(copy.yaw, 1.25)
			and copy.sprint and copy.primary and copy.dash and copy.ability_pressed
			and not copy.jump and not copy.heal_pressed and copy.stance == 2 and copy.switch_weapon == 1,
			"a command survives the trip through its network form")
	cmd.watch_up = true
	var packed: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	copy.apply_array(packed)
	check(copy.watch_up and int(packed[ActorCommand.FLAGS_INDEX]) & ActorCommand.HELD_MASK & ActorCommand.FLAG_WATCH_UP != 0,
			"a raised watch travels with the held keys, so others see it")
	copy.apply_array([99.0, 99.0, "x", 50.0, NAN, 0.0, 0.0, 0, 7, 99])
	check(copy.move == Vector2.ONE and is_zero_approx(copy.yaw) and copy.pitch <= 1.5
			and copy.aim_dir == Vector3.ZERO and copy.stance == 2 and copy.switch_weapon <= 8,
			"a command from the network is clamped to legal values")
	# The server must play the very move the client predicted with. A
	# keyboard diagonal is (1, 1), and riding with throttle and steer held is
	# exactly that; shortened on the way, the server rode a slower, wider turn.
	var diagonal := ActorCommand.new()
	for move: Vector2 in [Vector2(1, 1), Vector2(0.7, 1), Vector2(-0.5, 1), Vector2(-1, -1)]:
		diagonal.move = move
		var sent: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, diagonal.to_array(), 0]]))[0][1]
		copy.apply_array(sent)
		check(copy.move.is_equal_approx(move), "a move of %s reaches the server as the client predicted it (%s)" % [move, copy.move])
	cmd.switch_weapon = ActorCommand.HOLSTER
	copy.apply_array(cmd.to_array())
	check(copy.switch_weapon == ActorCommand.HOLSTER, "putting the weapon away survives the network form")
	cmd.switch_weapon = 1
	copy.apply_array([1.0])
	check(copy.stance == 2, "a malformed command is ignored")
	check(cmd.flags() & ActorCommand.ONE_SHOT_MASK != 0 and cmd.flags() & ActorCommand.HELD_MASK != 0
			and ActorCommand.ONE_SHOT_MASK & ActorCommand.HELD_MASK == 0, "held keys and presses are told apart")

	# A server raid with two players, no network involved.
	Profile.reset()
	Profile.welcome_granted = true
	var raid := Raid.new()
	add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 70)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	check(raid.player == null and raid.players.is_empty() and raid.bots.size() == raid.world.bot_count + raid._bosses.size(),
			"a server raid starts with bots and no players")
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player(["rifle_carbine", "blade_scrap", "jetpack_mk1", "plate_light"], {}, "Bravo")
	await frames(20)
	check(raid.players.size() == 2 and a.weapons.size() == 3 and b.weapons[0].display_name == "Ashfront Carbine"
			and not a.is_player, "players join a server raid with their own kits")
	var finished := []
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void: finished.append([actor, result]))
	b.kill("bullet", a)
	await frames(5)
	check(finished.size() == 1 and finished[0][0] == b and finished[0][1].outcome == "died"
			and "rifle_carbine" in finished[0][1].lost, "a player who dies gets their own result")
	check(raid.state_for(a).kills == 1 and not a.is_dead and raid.active_players() == ([a] as Array[Actor]),
			"the raid carries on for the others, and the kill is credited")
	var b_again := raid.add_player([], {}, "Bravo")
	check(raid.active_players().size() == 2 and b_again.protected_left > 0.0
			and b_again.global_position.distance_to(a.global_position) > 10.0,
			"the dead player drops back in, protected and away from the others")
	var banked := []
	raid.player_banked.connect(func(actor: Actor, items: Array) -> void: banked.append([actor, items]))
	b_again.inventory.add_item("alloy_ingot")
	var depot := raid.depots[0]
	b_again.global_position = Vector3(depot.global_position.x, depot.global_position.y - 1.8, depot.global_position.z)
	await frames(int(raid.world.depot_hold_time * 60.0) + 30)
	check(banked.size() == 1 and banked[0][0] == b_again and banked[0][1] == ["alloy_ingot"]
			and not b_again.inventory.has_item("alloy_ingot"),
			"a depot works for players on a server, and reports what was banked")
	# A dropped connection leaves the body standing until its sign-out ends.
	b_again.cmd.move = Vector2(0, 1)
	raid.remove_player(b_again)
	check(not b_again.is_dead and raid.sign_out_progress(b_again) >= 0.0 and b_again.cmd.move == Vector2.ZERO,
			"a player who disconnects leaves a helpless body behind")
	raid.cancel_sign_out(b_again)
	Combat.deal(b_again, DamageInfo.make(5.0, a, "bullet"))
	check(raid.sign_out_progress(b_again) >= 0.0, "that sign-out cannot be called off, by them or by a hit")
	var wait_before: float = raid.state_for(b_again).sign_out_left
	raid.remove_player(b_again)
	check(raid.state_for(b_again).sign_out_left <= wait_before, "asking twice never makes the wait longer")
	b_again.kill("bullet", a)
	await frames(2)
	check(finished.size() == 2 and finished[1][1].outcome == "died" and raid.state_for(a).kills == 2,
			"a body that is killed before its sign-out ends is a death")
	finished.remove_at(1)
	check(Profile.stash.is_empty() and Profile.raids_played == 0, "a server raid never touches a profile")
	a.inventory.add_item("scrap_metal")
	raid._leave(raid.state_for(a))
	await frames(2)
	check(finished.size() == 2 and finished[1][1].outcome == "left"
			and "scrap_metal" in finished[1][1].brought_home, "a player who leaves gets a result listing what comes home")
	Raid.apply_result(finished[1][1])
	check("scrap_metal" in Profile.stash and Profile.raids_extracted == 1, "the result can be applied to the player's own profile")
	await _end_raid(raid)
	Profile.reset()

	# Containers and vehicles are announced, so a server can replicate them.
	raid = Raid.new()
	add_child(raid)
	var announced := {"containers": 0, "vehicles": 0, "removed": 0}
	raid.container_spawned.connect(func(_c: LootContainer) -> void: announced.containers += 1)
	raid.vehicle_spawned.connect(func(_v: Node3D) -> void: announced.vehicles += 1)
	raid.vehicle_removed.connect(func(_v: Node3D) -> void: announced.removed += 1)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var map_vehicles := raid.vehicles.size()
	check(announced.containers > 3 and announced.vehicles == map_vehicles, "a server raid announces its caches and vehicles")
	var rider := raid.add_player(raid.world.starter_loadout() + (["bike_scrapper"] as Array[String]), {}, "Rider")
	await frames(10)
	check(raid.vehicles.size() == map_vehicles and raid.state_for(rider).deployed_vehicles == (["bike_scrapper"] as Array[String])
			and raid.stowed_for(rider) == (["bike_scrapper"] as Array[String]),
			"a player who brings a vehicle to a server raid has it on their watch")
	raid.state_for(rider).stowed.clear()
	var own_bike: Node3D = raid.spawn_vehicle("bike_scrapper", rider.global_position + Vector3(2.5, 0.3, 0), 0.0)
	check(own_bike.call("mount", rider), "they can ride it")
	var outcome := [{}]
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: outcome[0] = r)
	var bags_before: int = announced.containers
	raid._leave(raid.state_for(rider))
	await frames(3)
	check("bike_scrapper" in outcome[0].get("brought_home", []) and announced.removed == 1
			and (not is_instance_valid(own_bike) or own_bike not in raid.vehicles), "leaving on a vehicle takes it home and out of the raid")
	check(announced.containers == bags_before, "leaving alive drops no loot bag")
	await _end_raid(raid)

	print("Online: a real server and two clients")
	_wipe_dir(NET_ACCOUNTS)
	var port := 24811
	var pid := _start_server(port, [])
	check(pid > 0, "a dedicated server process starts")
	var alpha := await _join("Alpha", port)
	check(alpha != null, "a client connects and joins the raid")
	if alpha == null:
		OS.kill(pid)
		return
	var world := Worlds.get_world("ashfront")
	check(alpha.raid.mode == Raid.Mode.CLIENT and alpha.raid.player.weapons.size() == 3
			and alpha.raid.player.is_player and not Combat.authoritative,
			"the client has its own actor and leaves damage to the server")
	await _wait_until(func() -> bool: return alpha.raid.bots.size() == world.bot_count, 180)
	check(alpha.raid.bots.size() == world.bot_count + alpha.raid._map_nodes("spawn_boss").size(),
			"the client sees the server's bots")
	# Interest: the client hears about itself and what is near in every
	# update, and about the far side of the field a fraction as often.
	await frames(30)
	alpha.entries_received.clear()
	# Counted in the server's updates, not in time: a server sharing a busy
	# machine sends fewer a second, and the shares are what matter.
	await _wait_until(func() -> bool: return int(alpha.entries_received.get(alpha.my_actor_id, 0)) >= 60, 900)
	var own_updates := int(alpha.entries_received.get(alpha.my_actor_id, 0))
	var heard := 0
	var seldom := 0
	var far_bots := 0
	var thinned := 0
	for bot in alpha.raid.bots:
		var updates := int(alpha.entries_received.get(alpha._ids.get(bot, -1), 0))
		heard += updates
		if bot.global_position.distance_to(alpha.raid.player.global_position) > NetSession.MID_RANGE + 10.0:
			far_bots += 1
			if updates >= 2 and updates <= own_updates / 4:
				seldom += 1
			if bot.tick_every > 1:
				thinned += 1
	check(own_updates >= 60, "a client hears about its own player in every update (%d updates)" % own_updates)
	check(far_bots >= 10 and seldom == far_bots,
			"and about bots across the field only now and then (%d of %d far bots)" % [seldom, far_bots])
	check(heard < world.bot_count * own_updates / 2,
			"so a big field costs a fraction of the traffic (%d bot updates, %d if all were sent)"
			% [heard, world.bot_count * own_updates])
	check(thinned == far_bots, "the client also simulates far bots in longer steps (%d of %d)" % [thinned, far_bots])
	var bravo := await _join("Bravo", port)
	check(bravo != null, "a second client joins the same raid")
	if bravo != null:
		var see_each_other := func() -> bool:
			return bravo.actor_for(alpha.my_actor_id) != null and alpha.actor_for(bravo.my_actor_id) != null
		await _wait_until(see_each_other, 180)
		var seen := bravo.actor_for(alpha.my_actor_id)
		check(seen != null and seen.display_name == "Alpha" and seen.weapons.size() == 3 and not seen.is_player,
				"each client sees the other player, with their name and gear")
		check(bravo.raid.players.size() == 2 and bravo.raid.active_players().size() == 2
				and alpha.raid.bots.size() == world.bot_count + alpha.raid._map_nodes("spawn_boss").size(),
				"a client's raid lists the players, separate from the bots")
		if seen != null:
			var from := seen.global_position
			# Walk where there is room, so nothing knocks the two screens apart.
			var walker := alpha.raid.player
			walker.cmd.yaw = _yaw_toward(_clear_run(walker, walker.global_position, Vector3.FORWARD, 14.0))
			await frames(10)
			walker.cmd.move = Vector2(0, 1)
			await frames(90)
			alpha.raid.player.cmd.move = Vector2.ZERO
			# On a busy machine the server can be a moment behind the walker.
			await _wait_until(func() -> bool: return from.distance_to(seen.global_position) > 3.0, 240)
			await frames(30)
			var moved := from.distance_to(seen.global_position)
			check(moved > 3.0, "one player's movement reaches the other through the server (%.1f m)" % moved)
			# The server may still be playing the last inputs on a busy machine.
			var agree := func() -> bool:
				return seen.global_position.distance_to(alpha.raid.player.global_position) < 2.0
			await _wait_until(agree, 120)
			var apart := seen.global_position.distance_to(alpha.raid.player.global_position)
			check(apart < 2.0, "both clients agree where that player is (%.2f m apart)" % apart)
		var roster := RaidRoster.new(bravo.raid, bravo.raid.player)
		roster.refresh()
		var names := roster.entries.map(func(e: Dictionary) -> String: return e.name)
		check(roster.entries.size() == 2 and "Alpha" in names and "Bravo" in names
				and roster.entries.all(func(e: Dictionary) -> bool: return e.status == RaidRoster.IN_RAID),
				"a client's scoreboard lists both players and none of the bots")
	await _leave(bravo)
	await _leave(alpha)
	OS.kill(pid)
	await frames(30)

	print("Online: fighting through the server")
	port = 24812
	pid = _start_server(port, ["--bots", "0", "--squad-spawn"])
	alpha = await _join("Alpha", port, {"vehicle": "bike_scrapper"})
	bravo = await _join("Bravo", port) if alpha != null else null
	check(alpha != null and bravo != null, "two clients join a squad-spawn server")
	if alpha != null and bravo != null:
		await _wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) != null, 180)
		# Alpha walks back from the bike to Bravo and then to the bag, and the
		# drop point's wall can stand between: it finds the way round.
		await _lay_navigation(alpha)
		var me := alpha.raid.player
		var target := alpha.actor_for(bravo.my_actor_id)
		var victim := bravo.raid.player
		# Measured before Alpha walks off to the bike and rides it.
		var spawn_gap := me.global_position.distance_to(target.global_position) if target != null else INF
		var face := func(point: Vector3) -> void:
			var aim := point - me.get_eye_position()
			me.cmd.aim_dir = aim.normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			me.cmd.pitch = asin(clampf(aim.normalized().y, -1.0, 1.0))
		var press_use := func() -> void:
			me.cmd.interact_pressed = true
			await frames(1)
			me.cmd.interact_pressed = false

		# Loot caches and the bike Alpha brought exist on both clients.
		await _throw_own_bike(alpha)
		await _wait_until(func() -> bool: return not alpha.vehicles().is_empty() and not bravo.vehicles().is_empty(), 120)
		check(alpha.containers().size() > 3 and alpha.containers().size() == bravo.containers().size(),
				"both clients see the server's loot caches (%d)" % alpha.containers().size())
		check(alpha.vehicles().size() >= 1 and bravo.vehicles().size() == alpha.vehicles().size(),
				"both clients see the vehicle a player brought")
		var bike: Node3D = null
		for v: Node3D in alpha.vehicles():
			if bike == null or v.global_position.distance_to(me.global_position) \
					< bike.global_position.distance_to(me.global_position):
				bike = v
		if bike != null:
			var their_bike: Node3D = null
			for v: Node3D in bravo.vehicles():
				if v.global_position.distance_to(bike.global_position) < 1.5:
					their_bike = v
			face.call(bike.global_position + Vector3(0, 0.6, 0))
			await frames(6)
			await press_use.call()
			await _wait_until(func() -> bool: return me.vehicle == bike, 90)
			check(me.vehicle == bike and bike.get("rider") == me, "pressing use on the bike mounts it, by the server's say")
			var bike_from := bike.global_position
			me.cmd.move = Vector2(0, 1)
			await frames(30)
			me.cmd.move = Vector2.ZERO
			await frames(10)
			check(bike.global_position.distance_to(bike_from) > 0.5
					and me.global_position.distance_to(bike.global_position) < 1.5,
					"the server drives the bike and the rider goes with it")
			var seen_rider := bravo.actor_for(alpha.my_actor_id)
			# The bike is still rolling to a stop, and the other client's view
			# of it trails by a few ticks: up to 2.9 m at this speed. Let it
			# come to rest before comparing.
			var same_ride := func() -> bool:
				return their_bike != null and their_bike.get("rider") == seen_rider \
						and their_bike.global_position.distance_to(bike.global_position) < 1.5
			await _wait_until(same_ride, 120)
			check(same_ride.call(), "the other client sees the same player riding the same bike")
			await press_use.call()
			await _wait_until(func() -> bool: return me.vehicle == null, 90)
			check(me.vehicle == null and bike.get("rider") == null, "pressing use again gets off")
			await frames(20)
		check(alpha.raid.bots.is_empty() and target != null and spawn_gap < 12.0,
				"squad spawn puts the players together (%.1f m apart)" % spawn_gap)
		var hits := [0]
		var notices: Array[String] = []
		me.hit_confirmed.connect(func(_t: Actor, _i: DamageInfo, _l: bool) -> void: hits[0] += 1)
		me.notice.connect(func(text: String) -> void: notices.append(text))
		var result := [{}]
		bravo.run_finished.connect(func(r: Dictionary) -> void: result[0] = r)
		var before := victim.health.health + victim.health.armor
		var war_feed: Array[String] = []
		bravo.raid.war_feed.connect(func(text: String) -> void: war_feed.append(text))
		me.cmd.primary = true
		for i in 600:
			if target == null or not is_instance_valid(target) or target.is_dead or not result[0].is_empty():
				break
			var aim := (target.global_position + Vector3(0, 1.1, 0)) - me.get_eye_position()
			me.cmd.aim_dir = aim.normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			# Close in, round the drop point's wall if it is in the way, so
			# nothing on the map sits between them.
			me.cmd.move = _move_toward(me, target.global_position) if aim.length() > 4.0 else Vector2.ZERO
			if i % 40 == 39:
				me.cmd.reload_pressed = true
			await frames(1)
			me.cmd.reload_pressed = false
		me.cmd.primary = false
		me.cmd.move = Vector2.ZERO
		check(hits[0] > 0, "the shooter is told about hits the server confirmed (%d)" % hits[0])
		await _wait_until(func() -> bool: return not result[0].is_empty(), 240)
		check(victim.health.health + victim.health.armor < before or victim.is_dead,
				"the victim's health drops on their own screen")
		check(result[0].get("outcome", "") == "died" and not result[0].get("lost", []).is_empty(),
				"the server tells a player their run is over and what they lost")
		await _wait_until(func() -> bool: return victim.is_dead, 60)
		check(victim.is_dead, "the dead player falls on their own screen")
		check(notices.any(func(text: String) -> bool: return text.begins_with("Killed ")),
				"the killer gets the kill notice from the server")
		var scores := func() -> bool:
			var mine := alpha.raid.state_for(me)
			var theirs := bravo.raid.state_for(bravo.actor_for(alpha.my_actor_id))
			return mine != null and mine.kills == 1 and theirs != null and theirs.kills == 1
		await _wait_until(scores, 90)
		check(scores.call() and alpha.raid.kills == 1, "every client is told each player's kill count")
		var famous := func() -> bool:
			var seen := bravo.actor_for(alpha.my_actor_id)
			return me.renown > 0 and seen != null and seen.renown == me.renown and seen.streak == 1
		await _wait_until(famous, 90)
		check(famous.call(), "the server tells every client the killer's renown (%d)" % me.renown)
		check(war_feed.any(func(text: String) -> bool: return " killed " in text),
				"the kill is announced to everyone in the world (%s)" % " / ".join(war_feed))
		# The dead player's bag appears for the killer, who walks over and loots it.
		var found: Array[LootContainer] = []
		var find_bag := func() -> bool:
			for c: Variant in alpha.containers():
				if is_instance_valid(c) and c.is_bag and found.is_empty():
					found.append(c)
			return not found.is_empty()
		await _wait_until(find_bag, 120)
		var bag: LootContainer = found[0] if not found.is_empty() else null
		check(bag != null and not bag.items.is_empty(), "the dead player's bag appears on the killer's screen")
		if bag != null:
			var bag_id := bag.get_instance_id()
			var carried := me.inventory.items.size()
			var looted := func() -> bool: return me.inventory.items.size() > carried
			for i in 600:
				if looted.call() or not is_instance_valid(bag):
					break
				face.call(bag.global_position + Vector3(0, 0.3, 0))
				var gap := Vector2(bag.global_position.x - me.global_position.x,
						bag.global_position.z - me.global_position.z).length()
				me.cmd.move = _move_toward(me, bag.global_position) if gap > 1.6 else Vector2.ZERO
				me.cmd.interact_pressed = gap <= 2.6 and i % 10 == 0
				await frames(1)
			me.cmd.move = Vector2.ZERO
			me.cmd.interact_pressed = false
			await _wait_until(looted, 60)
			check(looted.call(), "looting the bag fills the backpack from the server (%d items)" % me.inventory.items.size())
			# The notice is its own message and can land a moment after the backpack.
			var told_loot := func() -> bool:
				return notices.any(func(text: String) -> bool: return text.begins_with("Looted "))
			await _wait_until(told_loot, 60)
			check(told_loot.call(), "the looter is told what they picked up")
			var bag_gone := func() -> bool: return not is_instance_id_valid(bag_id)
			await _wait_until(bag_gone, 90)
			check(bag_gone.call(), "the emptied bag disappears on the client too")
		await _wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) == null, 400)
		check(alpha.actor_for(bravo.my_actor_id) == null, "a dead player is removed from the other client's raid")

		# Bravo is still connected, and drops back into the same world.
		var dead_id := bravo.my_actor_id
		var world_before := bravo.raid
		bravo.deploy()
		var back := func() -> bool:
			return bravo.my_actor_id != dead_id and bravo.raid != null and bravo.raid.player != null \
					and is_instance_valid(bravo.raid.player) and not bravo.raid.player.is_dead
		await _wait_until(back, 300)
		check(back.call() and bravo.raid == world_before and bravo.raid.player != victim,
				"a dead player drops back into the same world without reconnecting")
		await _wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) != null, 180)
		check(alpha.actor_for(bravo.my_actor_id) != null and bravo.raid.players.size() == 2
				and bravo.containers().size() == alpha.containers().size(),
				"the other client sees them return, and they still see the world")
		# The watch's summon, online: Alpha materializes a weapon looted from the bag.
		# Prefer one unlike the weapon worn in its slot, so the swap is visible.
		var looted_weapon := ""
		for id in me.inventory.items:
			if not Loadout.summonable(id):
				continue
			var worn_at := Loadout.worn_index(me, Loadout.weapon_slot(id))
			var differs: bool = worn_at < 0 or me.weapons[worn_at].item_id != id
			if looted_weapon == "" or differs:
				looted_weapon = id
				if differs:
					break
		check(looted_weapon != "", "the bag held a weapon to summon (%s)" % looted_weapon)
		if looted_weapon != "" and back.call():
			var slot := Loadout.weapon_slot(looted_weapon)
			var worn_before: String = me.weapons[Loadout.worn_index(me, slot)].item_id
			var pack_before := me.inventory.items.size()
			check(alpha.raid.summon(me, looted_weapon) != "" and me.weapons[Loadout.worn_index(me, slot)].item_id == worn_before,
					"a client cannot summon a weapon on its own")
			alpha.summon("smg_stinger" if looted_weapon != "smg_stinger" and worn_before != "smg_stinger" else "rifle_carbine")
			await frames(30)
			check(me.weapons[Loadout.worn_index(me, slot)].item_id == worn_before and me.inventory.items.size() == pack_before,
					"the server refuses a weapon that is not in the pack it keeps")
			var swaps := [0]
			me.weapon_swapped.connect(func(_id: String, _m: int, _r: int) -> void: swaps[0] += 1)
			alpha.summon(looted_weapon)
			var summoned := func() -> bool:
				var at := Loadout.worn_index(me, slot)
				return swaps[0] > 0 and at >= 0 and me.weapons[at].item_id == looted_weapon and at == me.active_weapon_index \
						and (worn_before == looted_weapon or me.inventory.has_item(worn_before))
			await _wait_until(summoned, 180)
			check(summoned.call() and looted_weapon in me.gear_items and me.inventory.items.size() == pack_before,
					"the server summons it: it is in the hand, and the one worn is in the pack")
			check(me.materialize_time > 0.0, "it materializes on the summoner's screen (%.1f s)" % me.materialize_time)
			await _wait_until(func() -> bool: return alpha.raid.summon_wait(me) > 0.0, 60)
			check(alpha.raid.summon_wait(me) > 0.0, "and the client is told its watch is resting")
			var seen_swap := func() -> bool:
				var there := bravo.actor_for(alpha.my_actor_id)
				return there != null and there.weapons.any(func(w: Weapon) -> bool: return w.item_id == looted_weapon) \
						and (worn_before == looted_weapon
						or not there.weapons.any(func(w: Weapon) -> bool: return w.item_id == worn_before))
			await _wait_until(seen_swap, 180)
			check(seen_swap.call(), "the other client sees the summoned weapon on them")
			# The watch's store, online: the summoned weapon goes back into the pack.
			await _wait_until(func() -> bool: return me.materialize_left <= 0.0, 180)
			var stores := [0]
			me.weapon_stored.connect(func(_id: String, _m: int, _r: int) -> void: stores[0] += 1)
			var pack_now := me.inventory.items.size()
			alpha.store(looted_weapon)
			var put_away := func() -> bool:
				return stores[0] > 0 and Loadout.worn_index(me, slot) < 0 and me.inventory.items.size() == pack_now + 1
			await _wait_until(put_away, 240)
			check(put_away.call() and looted_weapon not in me.gear_items,
					"the server stores the weapon in hand: it fades out and is in the pack")
			var seen_store := func() -> bool:
				var there := bravo.actor_for(alpha.my_actor_id)
				return there != null and Loadout.worn_index(there, slot) < 0
			await _wait_until(seen_store, 180)
			check(seen_store.call(), "the other client sees it put away")
			# A ping reaches the pinger; a stranger on another side hears nothing.
			var ping_heard := [0, 0]
			alpha.raid.pinged.connect(func(_a: Actor, _at: Vector3) -> void: ping_heard[0] += 1)
			bravo.raid.pinged.connect(func(_a: Actor, _at: Vector3) -> void: ping_heard[1] += 1)
			me.cmd.pitch = -0.6
			me.cmd.aim_dir = Vector3.ZERO
			await frames(10)
			alpha.ping()
			await _wait_until(func() -> bool: return ping_heard[0] > 0, 120)
			await frames(20)
			var allied: bool = alpha.raid.world.players_allied
			check(ping_heard[0] == 1 and ping_heard[1] == (1 if allied else 0),
					"a ping reaches the pinger and their side, nobody else")
		if back.call():
			var from := bravo.raid.player.global_position
			# Walk where there is room: a drop point has a wall and a bike by it.
			bravo.raid.player.cmd.yaw = _yaw_toward(_clear_run(bravo.raid.player, from, Vector3.FORWARD, 10.0))
			await frames(10)
			bravo.raid.player.cmd.move = Vector2(0, 1)
			await frames(60)
			bravo.raid.player.cmd.move = Vector2.ZERO
			await frames(20)
			var seen_again := alpha.actor_for(bravo.my_actor_id)
			check(bravo.raid.player.global_position.distance_to(from) > 2.0 and seen_again != null
					and seen_again.global_position.distance_to(bravo.raid.player.global_position) < 2.0,
					"the new body answers to their input, on both screens")
			# Signing out is asked of the server, and ends the stay alive.
			result[0] = {}
			await frames(int(world.combat_time * 60.0))
			bravo.sign_out()
			var counting := func() -> bool: return bravo.raid.sign_out_progress(bravo.raid.player) >= 0.0
			await _wait_until(counting, 120)
			check(counting.call(), "the server starts a sign-out and the client shows the countdown")
			await _wait_until(func() -> bool: return not result[0].is_empty(), int(world.sign_out_time * 60.0) + 240)
			check(result[0].get("outcome", "") == "left", "a finished sign-out ends the life as left")
			await _wait_until(func() -> bool: return alpha.actor_for(bravo.my_actor_id) == null, 120)
			check(alpha.actor_for(bravo.my_actor_id) == null, "a player who left is gone from the other client's world")
	await _leave(bravo)
	await _leave(alpha)
	OS.kill(pid)
	await frames(30)
	_wipe_dir(NET_ACCOUNTS)
	check(Combat.authoritative, "leaving an online raid hands damage back to this game")


## How many ticks a jump pressed by `me` takes to show on the copy of them
## another client sees (`seen`), averaged over `presses` jumps.
func _press_delay(me: Actor, seen: Actor, presses: int) -> float:
	var total := 0
	for press in presses:
		var ground := seen.global_position.y
		me.cmd.jump_pressed = true
		await frames(1)
		me.cmd.jump_pressed = false
		var took := 0
		while took < 60 and seen.global_position.y < ground + 0.05:
			await frames(1)
			took += 1
		total += took
		await _wait_until(func() -> bool: return me.is_on_floor() and seen.is_on_floor(), 120)
		# Not on a beat: presses land anywhere between two state updates.
		await frames(13 + press)
	return float(total) / presses


func _test_online_movement() -> void:
	print("Online: smooth movement on a bad connection")
	var port := 24816
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var dana := await _join("Dana", port)
	var eli := await _join("Eli", port) if dana != null else null
	check(dana != null and eli != null, "two clients join for the movement checks")
	if dana == null or eli == null:
		await _leave(eli)
		await _leave(dana)
		OS.kill(pid)
		return
	await _wait_until(func() -> bool: return eli.actor_for(dana.my_actor_id) != null, 180)
	var me := dana.raid.player
	var seen := eli.actor_for(dana.my_actor_id)
	await frames(30)

	# 120 ms each way: the server's answers describe where you were a quarter
	# of a second ago.
	dana.simulated_lag = 0.12
	await frames(40)
	dana.max_correction = 0.0
	var from := me.global_position
	var worst_step := 0.0
	var last := from
	# Run where there is room: the other player and the drop point's wall
	# stand somewhere around.
	me.cmd.yaw = _yaw_toward(_clear_run(me, from, Vector3.FORWARD, 22.0))
	await frames(20)
	me.cmd.move = Vector2(0, 1)
	me.cmd.sprint = true
	for i in 150:
		await frames(1)
		# A pull backwards shows up as a tick that moves you less than nothing.
		var step := (me.global_position - last).dot((me.global_position - from).normalized()) if i > 20 else 0.0
		worst_step = minf(worst_step, step)
		last = me.global_position
	var ran := from.distance_to(me.global_position)
	me.cmd.move = Vector2.ZERO
	me.cmd.sprint = false
	check(ran > 6.0, "a lagging player still runs at full speed (%.1f m)" % ran)
	check(dana.max_correction < 0.4, "running on a slow connection needs no real correction (worst %.2f m)" % dana.max_correction)
	check(worst_step > -0.02, "the player is never pulled backwards while running (%.3f m)" % worst_step)
	await frames(90)
	var apart := seen.global_position.distance_to(me.global_position) if is_instance_valid(seen) else 99.0
	check(apart < 0.5, "after stopping, the other player sees them where they are (%.2f m apart)" % apart)

	# How long a press takes to show on the other player's screen, on a clean
	# connection, to compare with a lossy one below.
	dana.simulated_lag = 0.04
	await frames(60)
	var clean_delay := await _press_delay(me, seen, 6)
	# One in five input packets lost: a single-tick press must still arrive.
	dana.simulated_loss = 0.2
	await frames(60)
	dana.max_correction = 0.0
	var ground := me.global_position.y
	var top := 0.0
	var seen_jumps := 0
	for jump in 5:
		me.cmd.jump_pressed = true
		await frames(1)
		me.cmd.jump_pressed = false
		var seen_top := 0.0
		for i in 80:
			await frames(1)
			top = maxf(top, me.global_position.y - ground)
			seen_top = maxf(seen_top, seen.global_position.y - ground)
		if seen_top > 0.6:
			seen_jumps += 1
	check(top > 0.6, "the player jumps on their own screen at once (%.2f m)" % top)
	check(seen_jumps == 5, "every jump reaches the server despite lost packets (%d of 5 seen by the other player)" % seen_jumps)
	# Steady loss must not leave the server playing inputs late: by now the
	# old input queue sat at its limit, five ticks (about 80 ms) behind.
	var lossy_delay := await _press_delay(me, seen, 6)
	check(lossy_delay < clean_delay + 2.5 and lossy_delay < 8.5,
			"steady packet loss adds no lasting input delay (a press shows after %.1f ticks, %.1f on a clean connection)"
			% [lossy_delay, clean_delay])
	dana.simulated_loss = 0.0

	# A bad moment: every packet for a sixth of a second is lost, with a press
	# in the middle of it. The first packet through still carries the press.
	await frames(60)
	dana.simulated_loss = 1.0
	await frames(4)
	me.cmd.jump_pressed = true
	await frames(1)
	me.cmd.jump_pressed = false
	await frames(5)
	dana.simulated_loss = 0.0
	var burst_top := 0.0
	for i in 80:
		await frames(1)
		burst_top = maxf(burst_top, seen.global_position.y - ground)
	check(burst_top > 0.6, "a press made while every packet is being lost still reaches the server (%.2f m)" % burst_top)

	# Free flight is predicted like running: jump, hold aim to light the
	# jets, fly sideways, and the server agrees all the way.
	if me.flight.can_hover():
		await frames(60)
		me.cmd.jump_pressed = true
		await frames(1)
		me.cmd.jump_pressed = false
		await frames(12)
		me.cmd.secondary = true
		dana.max_correction = 0.0
		me.cmd.jump = true
		await frames(30)
		me.cmd.jump = false
		me.cmd.move = Vector2(1, 0)
		await frames(60)
		me.cmd.move = Vector2.ZERO
		await frames(40)
		var up := me.global_position.y - ground
		check(me.flight.is_hovering and up > 2.0, "a lagging player hovers on their own screen (%.1f m up)" % up)
		check(dana.max_correction < 0.4, "free flight on a slow connection needs no real correction (worst %.2f m)" % dana.max_correction)
		check(is_instance_valid(seen) and seen.flight.is_hovering and seen.global_position.distance_to(me.global_position) < 0.6,
				"the other player sees them hovering in the same place")
		me.cmd.descend = true
		await _wait_until(func() -> bool: return me.is_on_floor(), 300)
		me.cmd.descend = false
		await frames(30)
		check(not me.flight.is_hovering and not seen.flight.is_hovering, "landing puts the jets out on both screens")
		me.cmd.secondary = false

	# Other players glide between updates instead of stepping.
	me.cmd.move = Vector2(1, 0)
	await frames(30)
	var biggest := 0.0
	var smallest := 99.0
	var prev := seen.global_position
	for i in 60:
		await frames(1)
		var moved := seen.global_position.distance_to(prev)
		prev = seen.global_position
		biggest = maxf(biggest, moved)
		smallest = minf(smallest, moved)
	me.cmd.move = Vector2.ZERO
	check(smallest > 0.0 and biggest < smallest * 2.5 + 0.02,
			"another player's movement is even from tick to tick (%.3f to %.3f m)" % [smallest, biggest])
	await _leave(eli)
	await _leave(dana)
	OS.kill(pid)
	await frames(30)


## The yaw that turns an actor to look along `dir`.
static func _yaw_toward(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Gives a client's world a navigation mesh, so `_move_toward` can find the
## way round walls in it. Only the server's world has one otherwise (bots are
## the server's). The first one in a run takes a moment to work out, so call
## this while nothing is being timed.
func _lay_navigation(session: NetSession) -> void:
	if session.raid.map.has_method("bake_navigation"):
		session.raid.map.call("bake_navigation")
	var nav_map := session.raid.get_world_3d().navigation_map
	await _wait_until(func() -> bool:
		return not NavigationServer3D.map_get_path(nav_map, session.raid.player.global_position,
				session.raid.player.global_position + Vector3(3, 0, 0), true).is_empty(), 300)


## The move input that walks `actor` toward `point` whichever way it is
## facing, round walls the way a bot goes (along the map's navigation mesh,
## see `_lay_navigation`). A walk straight at something stops dead at the
## first wall between. Without a mesh it is a straight walk.
func _move_toward(actor: Actor, point: Vector3) -> Vector2:
	var from := actor.global_position
	var next := point
	var nav_map := actor.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		for corner in NavigationServer3D.map_get_path(nav_map, from, point, true):
			if Vector2(corner.x - from.x, corner.z - from.z).length() > 0.6:
				next = corner
				break
	var dir := Vector3(next.x - from.x, 0.0, next.z - from.z)
	if dir.length() < 0.01:
		return Vector2.ZERO
	dir = Basis(Vector3.UP, actor.cmd.yaw).inverse() * dir.normalized()
	return Vector2(dir.x, -dir.z)


## Whether `actor` could run `reach` metres along `dir` (flat, unit length)
## from `from` without meeting a wall, a wreck, a bike or another actor. It
## follows the ground, so a slope does not count as a wall.
func _run_is_clear(actor: Actor, from: Vector3, dir: Vector3, reach: float) -> bool:
	var space := actor.get_world_3d().direct_space_state
	var skip: Array[RID] = []
	for other in get_tree().get_nodes_in_group("actors"):
		if other is Actor and Raid.together(other, actor):
			skip.append((other as Actor).get_rid())
			var to: Vector3 = (other as Actor).global_position - from
			to.y = 0.0
			var along := to.dot(dir)
			if other != actor and along > 0.0 and along < reach + 1.0 and (to - dir * along).length() < 1.6:
				return false
	var last := Vector3.ZERO
	for i in int(reach) + 1:
		var above := from + dir * float(i) + Vector3(0, 4.0, 0)
		var down := PhysicsRayQueryParameters3D.create(above, above + Vector3(0, -12.0, 0))
		down.exclude = skip
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			return false
		var chest: Vector3 = floor_hit.position + Vector3(0, 0.9, 0)
		if i > 0:
			if absf(chest.y - last.y) > 0.7:
				return false
			var ray := PhysicsRayQueryParameters3D.create(last, chest)
			ray.exclude = skip
			if not space.intersect_ray(ray).is_empty():
				return false
		last = chest
	return true


## A flat direction `actor` can run `reach` metres in from `from`: `prefer`
## if that is clear, otherwise the nearest clear one to it.
func _clear_run(actor: Actor, from: Vector3, prefer: Vector3, reach: float) -> Vector3:
	for i in 16:
		var turn := TAU / 16.0 * float((i + 1) / 2) * (1.0 if i % 2 == 1 else -1.0)
		var dir := prefer.rotated(Vector3.UP, turn)
		if _run_is_clear(actor, from, dir, reach):
			return dir
	return prefer


func _test_online_lag_compensation() -> void:
	print("Online: a lagging shooter hits what is on their screen")
	var with_rewind := await _lagged_shots(24817, [])
	var without := await _lagged_shots(24818, ["--no-rewind"])
	check(with_rewind.size() == 2 and without.size() == 2, "two duels on a slow connection ran")
	if with_rewind.size() != 2 or without.size() != 2:
		return
	check(with_rewind[0] >= 4,
			"aiming straight at a running player on a 100 ms connection hits (%d of %d)" % with_rewind)
	check(without[0] <= 1,
			"without rewinding the same shots miss, so the hits come from lag compensation (%d of %d)" % without)


## Dana, on a 100 ms connection, aims exactly where she sees Eli while he
## strafes past, and fires single shots. Returns [hits, shots], or [] if the
## players could not join.
func _lagged_shots(port: int, extra: Array[String]) -> Array:
	var args: Array[String] = ["--bots", "0", "--squad-spawn"]
	args.append_array(extra)
	var pid := _start_server(port, args)
	var dana := await _join("Dana", port)
	var eli := await _join("Eli", port) if dana != null else null
	if dana != null and eli != null:
		await _wait_until(func() -> bool: return dana.actor_for(eli.my_actor_id) != null, 180)
	var seen := dana.actor_for(eli.my_actor_id) if dana != null and eli != null else null
	if seen == null:
		await _leave(eli)
		await _leave(dana)
		OS.kill(pid)
		await frames(30)
		return []
	var me := dana.raid.player
	var runner := eli.raid.player
	var hits := [0]
	me.hit_confirmed.connect(func(target: Actor, _info: DamageInfo, _lethal: bool) -> void:
		if target == seen:
			hits[0] += 1)
	dana.simulated_lag = 0.1
	# Eli just dropped in, and cannot be hurt until his protection runs out.
	await frames(int(Worlds.get_world("ashfront").spawn_protection * 60.0) + 40)
	# Eli backs away from Dana for some room, then strafes across her view.
	var away := runner.global_position - me.global_position
	away.y = 0.0
	runner.cmd.yaw = _yaw_toward(-away.normalized() if away.length() > 0.1 else Vector3.FORWARD)
	runner.cmd.move = Vector2(0, -1)
	await frames(30)
	# He strafes to whichever side has room, so nothing stops him mid-run.
	var right := Vector3.RIGHT.rotated(Vector3.UP, runner.cmd.yaw)
	var room_right := _run_is_clear(runner, runner.global_position, right, 12.0)
	var room_left := _run_is_clear(runner, runner.global_position, -right, 12.0)
	runner.cmd.move = Vector2(1, 0) if room_right or not room_left else Vector2(-1, 0)
	me.cmd.secondary = true
	var shots := 0
	for i in 80:
		if is_instance_valid(seen) and not seen.is_dead:
			var dir := (seen.global_position + Vector3(0, 1.1, 0) - me.get_eye_position()).normalized()
			me.cmd.aim_dir = dir
			me.cmd.yaw = _yaw_toward(dir)
			me.cmd.pitch = asin(dir.y)
			me.cmd.primary = i >= 20 and i % 12 == 8 and shots < 5
			if me.cmd.primary:
				shots += 1
		await frames(1)
	me.cmd.primary = false
	me.cmd.secondary = false
	runner.cmd.move = Vector2.ZERO
	await frames(40)
	await _leave(eli)
	await _leave(dana)
	OS.kill(pid)
	await frames(30)
	return [hits[0], shots]


func _test_online_riding() -> void:
	print("Online: riding responds at once on a slow connection")
	var port := 24819
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var faye := await _join("Faye", port, {"vehicle": "bike_scrapper"})
	var gus := await _join("Gus", port) if faye != null else null
	check(faye != null and gus != null, "two clients join for the riding checks")
	var bike: Node3D = null
	if faye != null and gus != null:
		await _throw_own_bike(faye)
		await _wait_until(func() -> bool: return not faye.vehicles().is_empty(), 120)
		for v: Node3D in faye.vehicles():
			if bike == null or v.global_position.distance_to(faye.raid.player.global_position) \
					< bike.global_position.distance_to(faye.raid.player.global_position):
				bike = v
	if bike == null:
		check(false, "the rider's bike is there")
		await _leave(gus)
		await _leave(faye)
		OS.kill(pid)
		await frames(30)
		return
	var me := faye.raid.player
	# The other player steps out of the bike's way.
	var walker := gus.raid.player
	var aside := walker.global_position - bike.global_position
	aside.y = 0.0
	aside = _clear_run(walker, walker.global_position,
			aside.normalized() if aside.length() > 0.1 else Vector3.BACK, 8.0)
	walker.cmd.yaw = _yaw_toward(aside)
	walker.cmd.move = Vector2(0, 1)
	await frames(100)
	walker.cmd.move = Vector2.ZERO
	var aim := bike.global_position + Vector3(0, 0.6, 0) - me.get_eye_position()
	me.cmd.aim_dir = aim.normalized()
	me.cmd.yaw = _yaw_toward(aim)
	me.cmd.pitch = asin(clampf(aim.normalized().y, -1.0, 1.0))
	await frames(6)
	me.cmd.interact_pressed = true
	await frames(1)
	me.cmd.interact_pressed = false
	await _wait_until(func() -> bool: return me.vehicle == bike, 90)
	check(me.vehicle == bike, "the rider gets on")
	faye.simulated_lag = 0.12
	await frames(40)
	faye.max_correction = 0.0
	var from := bike.global_position
	me.cmd.move = Vector2(0, 1)
	# The server only hears about it after 120 ms, about 7 ticks.
	await frames(6)
	check(bike.global_position.distance_to(from) > 0.06,
			"on a 120 ms connection the bike pulls away the moment the throttle opens (%.2f m)" % bike.global_position.distance_to(from))
	var heading: float = bike.get("heading")
	me.cmd.move = Vector2(0.7, 1)
	await frames(40)
	check(absf(angle_difference(heading, bike.get("heading"))) > 0.3, "steering turns the bike at once")
	me.cmd.move = Vector2(-0.5, 1)
	await frames(40)
	me.cmd.move = Vector2(0, -1)
	await _wait_until(func() -> bool: return float(bike.get("speed")) <= 0.5, 120)
	me.cmd.move = Vector2.ZERO
	check(faye.max_correction < 0.5, "the server agrees with the predicted ride (worst %.2f m)" % faye.max_correction)
	await frames(60)
	var their_bike: Node3D = null
	for v: Node3D in gus.vehicles():
		if their_bike == null or v.global_position.distance_to(bike.global_position) \
				< their_bike.global_position.distance_to(bike.global_position):
			their_bike = v
	var apart := their_bike.global_position.distance_to(bike.global_position) if their_bike != null else 99.0
	check(apart < 0.5, "after stopping, the other player sees the bike where the rider has it (%.2f m apart)" % apart)
	check(me.vehicle == bike and me.global_position.distance_to(bike.global_position) < 1.5,
			"the rider stays on the predicted bike")
	await _leave(gus)
	await _leave(faye)
	OS.kill(pid)
	await frames(30)


func _test_online_pillion() -> void:
	print("Online: a passenger behind the rider")
	_wipe_dir(NET_ACCOUNTS)
	# Hal owns a Raider hoverbike: put one in the account before the server reads it.
	var service := StashService.new()
	service.save_dir = NET_ACCOUNTS
	if not _net_secrets.has("Hal"):
		_net_secrets["Hal"] = StashService.new_secret()
	service.sign_in("Hal", _net_secrets["Hal"])
	var account := service.load_account(StashService.id_for_name("Hal"))
	account.add_items(["bike_raider"])
	service._save(account)
	var port := 24881
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var hal := await _join("Hal", port, {"vehicle": "bike_raider"})
	var ida := await _join("Ida", port) if hal != null else null
	check(hal != null and ida != null, "two clients join for the passenger checks")
	var bike: Node3D = null
	if hal != null and ida != null:
		await _throw_own_bike(hal)
		for v: Node3D in hal.vehicles():
			if v.get("item_id") == "bike_raider":
				bike = v
	if bike == null:
		check(false, "the hoverbike is there")
		await _leave(ida)
		await _leave(hal)
		OS.kill(pid)
		await frames(30)
		return
	var me := hal.raid.player
	_aim_at(me, bike.global_position + Vector3(0, 0.6, 0))
	await frames(6)
	me.cmd.interact_pressed = true
	await frames(1)
	me.cmd.interact_pressed = false
	await _wait_until(func() -> bool: return me.vehicle == bike, 90)
	check(me.vehicle == bike, "the rider gets on the hoverbike")
	# Ida walks up and climbs on behind.
	var her := ida.raid.player
	var her_bike: Node3D = null
	for v: Node3D in ida.vehicles():
		if v.get("item_id") == "bike_raider":
			her_bike = v
	for i in 400:
		var gap := her_bike.global_position - her.global_position if her_bike != null else Vector3.ZERO
		gap.y = 0.0
		if gap.length() < 2.0:
			break
		her.cmd.yaw = _yaw_toward(gap)
		her.cmd.pitch = 0.0
		her.cmd.aim_dir = Vector3.ZERO
		her.cmd.move = Vector2(0, 1)
		await frames(1)
	her.cmd.move = Vector2.ZERO
	await frames(10)
	if her_bike != null:
		_aim_at(her, her_bike.global_position + Vector3(0, 0.7, 0.3))
	await frames(6)
	her.cmd.interact_pressed = true
	await frames(1)
	her.cmd.interact_pressed = false
	var ida_on_hal := func() -> Actor:
		return hal._actors.get(ida.my_actor_id)
	await _wait_until(func() -> bool:
		return her.vehicle == her_bike and bike.get("passenger") != null and bike.get("passenger") == ida_on_hal.call(), 120)
	check(her.vehicle == her_bike and her_bike.get("passenger") == her and her_bike.get("rider") != null,
			"the passenger sits behind the rider in their own game")
	check(bike.get("passenger") != null and bike.get("passenger") == ida_on_hal.call() and bike.get("rider") == me,
			"and the rider's game seats them there too")
	# The rider drives two up on a slow connection; the server agrees.
	hal.simulated_lag = 0.12
	await frames(40)
	hal.max_correction = 0.0
	var from := bike.global_position
	me.cmd.move = Vector2(0, 1)
	await frames(60)
	me.cmd.move = Vector2(-0.8, 1)
	await frames(40)
	me.cmd.move = Vector2(0, -1)
	await _wait_until(func() -> bool: return float(bike.get("speed")) <= 0.5, 150)
	me.cmd.move = Vector2.ZERO
	var carried := bike.global_position.distance_to(from)
	check(carried > 3.0, "the hoverbike carries both (%.1f m)" % carried)
	check(hal.max_correction < 0.6, "the server agrees with the predicted two-up drift (worst %.2f m)" % hal.max_correction)
	await frames(60)
	var apart := her_bike.global_position.distance_to(bike.global_position)
	check(apart < 0.6 and her.global_position.distance_to(her_bike.global_position) < 1.5,
			"the passenger is carried where the rider has it (%.2f m apart)" % apart)
	# F lets the passenger off; the rider stays on.
	her.cmd.interact_pressed = true
	await frames(1)
	her.cmd.interact_pressed = false
	await _wait_until(func() -> bool: return her.vehicle == null and bike.get("passenger") == null, 120)
	check(her.vehicle == null and bike.get("passenger") == null and me.vehicle == bike,
			"F lets the passenger off for everyone and the rider rides on")
	await _leave(ida)
	await _leave(hal)
	OS.kill(pid)
	await frames(30)


## Aims an actor at a point, the way a controller would.
func _aim_at(actor: Actor, point: Vector3) -> void:
	var aim := (point - actor.get_eye_position()).normalized()
	actor.cmd.aim_dir = aim
	actor.cmd.yaw = atan2(-aim.x, -aim.z)
	actor.cmd.pitch = asin(clampf(aim.y, -1.0, 1.0))


func _test_vehicle_toys() -> void:
	print("Vehicles: toys on the watch")
	var toy: Node3D = VehicleScript.toy_model("bike_scrapper")
	check(toy.get_node_or_null("Model") != null and is_equal_approx(toy.scale.x, VehicleScript.TOY_SCALE)
			and toy.find_children("*", "CollisionShape3D", true, false).is_empty(),
			"a toy is the vehicle's own model, toy-sized, with no collision")
	toy.free()
	var world := Worlds.get_world("ashfront")
	var raid := Raid.new()
	add_child(raid)
	raid.start(world, 71, world.starter_loadout() + (["bike_scrapper"] as Array[String]))
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, 0, 3000)
	await frames(10)
	var p := raid.player
	var state := raid.state_for(p)
	var before := raid.vehicles.size()
	check(raid.stowed_for(p) == (["bike_scrapper"] as Array[String]), "a brought bike starts as a toy on the watch")
	# Stand on a wide open floor, well away from the map.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Actor.LAYER_WORLD
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(80, 1, 80)
	var floor_col := CollisionShape3D.new()
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	raid.add_child(floor_body)
	floor_body.global_position = Vector3(0, 199.5, 2500)
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(6, 6, 1)
	var wall_col := CollisionShape3D.new()
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	raid.add_child(wall)
	wall.global_position = Vector3(30, 203, 2500)
	p.global_position = Vector3(0, 200.05, 2500)
	p.velocity = Vector3.ZERO
	await frames(5)

	var events := {"thrown": 0, "landed": [], "watch": 0}
	raid.toy_thrown.connect(func(_a: Actor, _id: String, _from: Vector3, _v: Vector3) -> void: events.thrown += 1)
	raid.toy_landed.connect(func(_a: Actor, _id: String, _at: Vector3, ok: bool) -> void: events.landed.append(ok))
	raid.watch_changed.connect(func(_a: Actor) -> void: events.watch += 1)
	check(raid.throw_toy(p, "bike_raider") != "" and events.thrown == 0, "a toy that is not on your watch cannot be thrown")
	_aim_at(p, p.global_position + Vector3(0, 1.6, -10))
	var throws_before := p.toy_throws
	check(raid.throw_toy(p, "bike_scrapper") == "" and events.thrown == 0 and raid.toys.size() == 1
			and raid.stowed_for(p).is_empty() and p.toy_in_hand == "bike_scrapper" and p.toy_throws == throws_before + 1,
			"throwing takes the toy off the watch and starts the throw with it in the hand")
	check(raid.hold_toy(p, "bike_scrapper") != "" and raid.throw_toy(p, "bike_scrapper") != "",
			"nothing else goes in the hand or is thrown while the arm comes through")
	await frames(int(raid.toy_windup * 60.0) - 6)
	check(events.thrown == 0 and p.toy_in_hand == "bike_scrapper", "the toy stays in the hand through the windup")
	await _wait_until(func() -> bool: return events.thrown == 1, 30)
	var flying: Dictionary = raid.toys[0] if not raid.toys.is_empty() else {}
	check(events.thrown == 1 and p.toy_in_hand == "" and flying.get("node") != null,
			"then it leaves the hand and flies")
	check(is_equal_approx(raid.toy_windup, ActionPose.of(p).toy_release),
			"the toy leaves the hand when the throw shown lets go of it")
	check(raid.vehicles.size() == before, "nothing unpacks while the toy is in the air")
	var last_basis := Basis()
	while not raid.toys.is_empty() and raid.toys[0].get("node") != null:
		last_basis = (raid.toys[0].node as Node3D).basis.orthonormalized()
		await get_tree().physics_frame
	check(last_basis.y.dot(Vector3.UP) > 0.95 and absf(last_basis.z.dot(Basis(Vector3.UP, p.cmd.yaw).z)) > 0.95,
			"the toy turns its flip and comes down level, facing the way it unpacks")
	await _wait_until(func() -> bool: return not events.landed.is_empty(), 240)
	var bike: Node3D = raid.vehicles[raid.vehicles.size() - 1] if raid.vehicles.size() > before else null
	check(events.landed == [true] and bike != null and bike.get("item_id") == "bike_scrapper",
			"the toy unpacks into the bike where it lands")
	if bike != null:
		var away := Vector3(bike.global_position.x - p.global_position.x, 0, bike.global_position.z - p.global_position.z)
		check(away.z < -4.0 and away.length() < 25.0 and absf(away.x) < 2.0,
				"it lands ahead of the thrower, where they aimed (%.1f m)" % away.length())
		check(float(bike.get("unpack_left")) > 0.0 and not bike.call("mount", p), "it grows from toy size, and cannot be ridden until it has")
		await frames(60)
		check(float(bike.get("unpack_left")) == 0.0 and bike.get_node("Model").scale.is_equal_approx(Vector3.ONE)
				and bike.is_on_floor(), "then it stands full size on the ground")
		check(raid.toy_wait(p) > 0.0, "the watch needs a moment before the next throw")

		# Packing it up again.
		p.global_position = bike.global_position + Vector3(2.0, 0.1, 0)
		_aim_at(p, bike.global_position + Vector3(0, 0.6, 0))
		await frames(2)
		check(raid.pack_vehicle(p) == "" and raid.stowed_for(p) == (["bike_scrapper"] as Array[String])
				and raid.vehicles.size() == before, "looking at your bike and packing it puts the toy back on the watch")
		await frames(2)
		check(raid.throw_toy(p, "bike_scrapper") != "" and raid.stowed_for(p).size() == 1, "you cannot throw again until the watch recharges")
		state.toy_ready_at = raid.clock

	# No room: thrown at the foot of a wall, it comes back.
	p.global_position = Vector3(27.5, 200.05, 2502.2)
	await frames(3)
	_aim_at(p, Vector3(29.4, 200.0, 2501.3))
	events.landed.clear()
	check(raid.throw_toy(p, "bike_scrapper") == "", "the toy can be thrown at a wall")
	await frames(int(raid.toy_windup * 60.0) + 4)
	_aim_at(p, Vector3(29.4, 200.0, 2501.3))
	await _wait_until(func() -> bool: return not events.landed.is_empty(), 240)
	check(events.landed == [false] and raid.vehicles.size() == before and raid.stowed_for(p).size() == 1
			and raid.toy_wait(p) == 0.0, "with no room to unpack, the toy jumps back onto the watch")
	check(not raid.has_room_to_unpack(p.global_position, 0.0) and raid.has_room_to_unpack(Vector3(-20, 200.0, 2500), 0.0),
			"room means clear of walls, people and other vehicles")

	# Holding a toy up is only the look: it stays on the watch.
	check(raid.hold_toy(p, "bike_scrapper") == "" and p.toy_in_hand == "bike_scrapper"
			and raid.stowed_for(p).size() == 1, "a toy taken in hand shows there and stays on the watch")
	check(raid.hold_toy(p, "bike_raider") != "" and p.toy_in_hand == "", "only a toy on the watch can be held")
	# Knocked out of the throw: on a vehicle before it leaves the hand.
	p.global_position = Vector3(0, 200.05, 2500)
	var saddle: Node3D = raid.spawn_vehicle("bike_raider", Vector3(3, 200.3, 2500), 0.0)
	await frames(10)
	events.thrown = 0
	check(raid.throw_toy(p, "bike_scrapper") == "", "a throw starts")
	saddle.call("mount", p)
	await frames(int(raid.toy_windup * 60.0) + 4)
	check(events.thrown == 0 and raid.stowed_for(p).size() == 1 and raid.toy_wait(p) == 0.0 and p.toy_in_hand == "",
			"a throw cut short before it leaves the hand puts the toy back on the watch")
	saddle.call("dismount")
	raid.remove_vehicle(saddle)

	# Limits.
	p.global_position = Vector3(0, 200.05, 2500)
	var spare: Node3D = raid.spawn_vehicle("bike_raider", Vector3(3, 200.3, 2500), 0.0)
	await frames(10)
	check(spare.call("mount", p) and raid.throw_toy(p, "bike_scrapper") != "", "you cannot throw from the saddle")
	spare.call("dismount")
	raid.begin_sign_out(p)
	check(raid.throw_toy(p, "bike_scrapper") != "", "you cannot throw while signing out")
	raid.cancel_sign_out(p)
	world.vehicle_toys = false
	check(raid.throw_toy(p, "bike_scrapper") != "", "a world can keep vehicles on the watch")
	world.vehicle_toys = true
	_aim_at(p, spare.global_position + Vector3(0, 0.6, 0))
	await frames(2)
	check(raid.pack_vehicle(p) == "" and raid.stowed_for(p).size() == 2, "a bike found in the field packs onto the watch too")
	var third: Node3D = raid.spawn_vehicle("bike_raider", Vector3(3, 200.3, 2500), 0.0)
	await frames(10)
	_aim_at(p, third.global_position + Vector3(0, 0.6, 0))
	await frames(2)
	check(raid.pack_vehicle(p) != "" and third in raid.vehicles, "the watch holds only so many (%d)" % raid.watch_capacity)
	check(events.watch >= 4, "the watch reports every change")

	# The controller: the watch key takes a toy in hand, fire throws it.
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var asked: Array[String] = []
	controller.toy_throw_requested.connect(func(id: String) -> void: asked.append(id))
	_aim_at(p, p.global_position + Vector3(0, 1.6, 10))
	# The watch: raised, it shows the toys; the wheel picks, fire takes one.
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	controller.wrist_raised = true
	check(controller.is_browsing_toys(), "raising the watch with toys on it lets you pick one")
	var weapon_before := p.active_weapon_index
	var vehicle_at := Hud.Wrist.SLOTS.find("vehicle")
	check(not controller.is_picking_toys() and controller.focused_watch_icon() == "vehicle",
			"the card opens on the vehicles, closed: the toys wait for a click")
	check(controller.watch_takes_fire() and controller.click_watch() and controller.watch_open == "vehicle"
			and controller.is_picking_toys() and controller.held_toy == "", "a click opens the vehicle icon's list")
	controller.scroll(1)
	check(controller.watch_index == 1 and controller._pending_switch < 0 and p.active_weapon_index == weapon_before,
			"with the list open the wheel turns through the toys, not the weapons")
	controller.scroll(1)
	check(controller.watch_focus == vehicle_at and controller.watch_index == 1 and controller.is_picking_toys(),
			"the list stops at its last toy; the wheel never leaves it")
	check(controller.close_watch_icon() and controller.watch_open == "" and not controller.is_picking_toys(),
			"a right click closes the list")
	controller.scroll(1)
	check(controller.watch_focus == vehicle_at + 1 and controller.watch_index == 1,
			"closed, the wheel steps across the icons and leaves the pick alone")
	controller.scroll(-1)
	check(controller.watch_focus == vehicle_at and controller.watch_index == 1, "back on the vehicles, the second toy still picked")
	controller.wrist_raised = false
	controller.scroll(1)
	check(controller._pending_switch >= 0, "with the watch down the wheel switches weapons again")
	controller._pending_switch = -1
	controller.wrist_raised = true
	check(controller.click_watch() and controller.watch_open == "vehicle", "raised again, a click opens the toys")
	await get_tree().process_frame
	await get_tree().process_frame
	check(hud.wrist.toys_shown() == raid.stowed_for(p) and hud.wrist.get_node("Hologram/Toys").get_child_count() == 2,
			"the watch stands each toy over its hologram")
	var shown := hud.wrist.get_node("Hologram/Toys")
	check(shown.get_child(1).scale.x > shown.get_child(0).scale.x and hud.wrist.focused_id() == "vehicle"
			and hud.wrist.text().begins_with("Raider Hoverbike") and shown.visible,
			"the card opens on the vehicles, the picked toy stands out and the watch names it")
	check("wheel" in hud.wrist.focused_hints() and "click" in hud.wrist.focused_hints()
			and not hud.wrist.text().contains("click"), "its controls are glyphs, not words")
	check(Hud.Wrist.toy_tint(true, true) != Hud.Wrist.toy_tint(true, false), "the toys dim while the watch recharges")
	controller.take_picked_toy()
	check(controller.held_toy == "bike_raider" and not controller.wrist_raised and not controller.is_browsing_toys(),
			"fire takes the picked toy into the hand and lowers the wrist")
	controller.hold_toy("")
	# Looking at a bike with the watch up, the click packs it instead.
	var packs := [0]
	controller.pack_requested.connect(func() -> void: packs[0] += 1)
	controller.wrist_raised = true
	_aim_at(p, third.global_position + Vector3(0, 0.6, 0))
	controller.yaw = p.cmd.yaw
	controller.pitch = p.cmd.pitch
	await frames(2)
	check(controller.pack_target() == third and controller.click_watch() and packs[0] == 1 and controller.held_toy == "",
			"with the watch up, clicking on a bike asks to pack it")
	hud._process(0.016)
	check(hud.wrist.text().begins_with("Pack Raider Hoverbike") and hud.wrist.focused_hints() == ["click"],
			"and the watch says so, with a click glyph")
	_aim_at(p, p.global_position + Vector3(0, 1.6, 10))
	controller.yaw = p.cmd.yaw
	controller.pitch = p.cmd.pitch
	await frames(2)
	controller.wrist_raised = false
	check(controller.pack_target() == null and not controller.click_watch(), "with the watch down a click is an ordinary shot")
	hud.queue_free()
	var held_asked: Array[String] = []
	controller.toy_hold_requested.connect(func(id: String) -> void:
		held_asked.append(id)
		raid.hold_toy(p, id))
	controller.hold_toy("bike_scrapper")
	check(controller.held_toy == "bike_scrapper" and held_asked == (["bike_scrapper"] as Array[String])
			and p.toy_in_hand == "bike_scrapper", "a toy off the watch goes into the hand, for everyone to see")
	p.cmd.primary_pressed = true
	controller._use_toy_hand(p.cmd)
	check(asked == (["bike_scrapper"] as Array[String]) and controller.held_toy == "" and not p.cmd.primary_pressed,
			"fire throws the toy instead of shooting")
	p.cmd.primary_pressed = true
	p.cmd.primary = true
	controller._use_toy_hand(p.cmd)
	check(not p.cmd.primary_pressed and not p.cmd.primary, "the weapon takes no fire while the arm comes through the throw")
	controller.hold_toy("bike_scrapper")
	check(controller.held_toy == "", "nor does another toy come into the hand mid-throw")
	controller._toy_busy_left = 0.0
	controller.hold_toy("bike_scrapper")
	p.cmd.secondary_pressed = true
	controller._use_toy_hand(p.cmd)
	check(controller.held_toy == "" and asked.size() == 1 and held_asked.back() == "" and p.toy_in_hand == "",
			"aim puts the toy back on the watch")
	controller.queue_free()

	# Leaving with toys on the watch takes them home; dying loses them.
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	raid._leave(state)
	await frames(2)
	check(results.size() == 1 and "bike_scrapper" in results[0].brought_home and "bike_raider" in results[0].brought_home
			and "bike_scrapper" not in results[0].lost, "signing out takes the toys on your watch home")
	await _end_raid(raid)

	var raid2 := Raid.new()
	add_child(raid2)
	raid2.start(world, 72, world.starter_loadout() + (["bike_scrapper"] as Array[String]))
	for bot in raid2.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(5)
	var results2: Array[Dictionary] = []
	raid2.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results2.append(r))
	raid2.player.kill("test")
	await frames(2)
	check(results2.size() == 1 and "bike_scrapper" in results2[0].lost and "bike_scrapper" not in results2[0].get("brought_home", []),
			"dying loses the toy on your watch")
	await _end_raid(raid2)


## The toy in the hand and the throw are one shared pose (`ActionPose`), so
## first and third person and everyone around see the same arm.
func _test_toy_throw_pose() -> void:
	print("Vehicles: holding and throwing a toy")
	var arena := _vehicle_arena()
	var p := Actor.new()
	arena.add_child(p)
	await frames(2)
	var pose := ActionPose.of(p)
	check(pose.toy == 0.0 and pose.toy_shown() == "" and not pose.toy_busy(), "an empty hand shows no toy")
	p.toy_in_hand = "bike_scrapper"
	pose.toy_hand_free = false
	pose.advance_toy(0.5)
	check(pose.toy == 0.0 and pose.toy_busy(), "the toy waits for the weapon to be put away, keeping it away meanwhile")
	pose.toy_hand_free = true
	pose.advance_toy(0.1)
	check(pose.toy > 0.0 and pose.toy < 1.0, "then the hand comes up for it, eased")
	pose.advance_toy(1.0)
	var held := pose.toy_hand_point()
	check(pose.toy == 1.0 and pose.toy_shown() == "bike_scrapper" and held.z < -0.3 and held.y > 1.2,
			"held up in front, in view of the eyes")
	p.toy_throws += 1
	var path: Array[Vector3] = []
	var shown_at_release := ""
	var turned := 0.0
	var t := 0.0
	pose.advance_toy(0.0)
	while pose.toy_throw_t >= 0.0 and t < 2.0:
		path.append(pose.toy_hand_point())
		turned = minf(turned, pose.toy_turn().x)
		if pose.toy_throw_t < pose.toy_release - 0.02:
			shown_at_release = pose.toy_shown()
		if pose.toy_throw_t >= pose.toy_release:
			p.toy_in_hand = ""
		pose.advance_toy(1.0 / 60.0)
		t += 1.0 / 60.0
	var back: Vector3 = path.reduce(func(a: Vector3, b: Vector3) -> Vector3: return b if b.z > a.z else a, path[0])
	var low: Vector3 = path.reduce(func(a: Vector3, b: Vector3) -> Vector3: return b if b.y < a.y else a, path[0])
	check(back.z > 0.0 and back.y > pose.shoulder.y, "the throw draws the toy back over the shoulder (%.2f, %.2f)" % [back.y, back.z])
	check(turned < -0.3, "the shoulders turn back into it")
	check(low.y < held.y - 0.2 and low.z < 0.0, "and follows through down across the body")
	check(shown_at_release == "bike_scrapper", "the toy is in the hand until the release")
	check(absf(t - pose.toy_throw_time) < 0.05 and pose.toy == 0.0 and not pose.toy_busy(),
			"the hand is given back once the throw is through")
	# A toy that stays on record a moment after it flew (online, until the
	# server says so) is not held up again.
	p.toy_in_hand = "bike_scrapper"
	p.toy_throws += 1
	pose.advance_toy(0.0)
	for i in 60:
		pose.advance_toy(1.0 / 60.0)
	check(pose.toy_shown() == "" and pose.toy == 0.0, "a thrown toy does not come back to the hand while the world catches up")
	arena.queue_free()
	await frames(2)


## Has an online client throw the bike on its watch, turning until it finds
## room, and waits for the bike to stand unpacked close by.
func _throw_own_bike(session: NetSession) -> void:
	var me := session.raid.player
	var before: Array = session.vehicles().duplicate()
	var thrown := func() -> Node3D:
		for v: Node3D in session.vehicles():
			if is_instance_valid(v) and v not in before and float(v.get("unpack_left")) <= 0.0 \
					and v.global_position.distance_to(me.global_position) < 25.0:
				return v
		return null
	await _wait_until(func() -> bool: return not session.raid.stowed_for(me).is_empty(), 180)
	# Throw the bike along open ground and walk to that one. The map's own
	# bikes may stand behind a wall, and a walk that gets stuck wanders off and
	# fails every check after it.
	for turn in 4:
		if thrown.call() != null or session.raid.stowed_for(me).is_empty():
			break
		var toward := Vector3.FORWARD.rotated(Vector3.UP, turn * PI * 0.5)
		me.cmd.yaw = _yaw_toward(_clear_run(me, me.global_position, toward, 12.0))
		me.cmd.pitch = -0.2
		me.cmd.aim_dir = Vector3.ZERO
		await frames(10)
		session.throw_toy(session.raid.stowed_for(me)[0])
		await _wait_until(func() -> bool: return thrown.call() != null, 240)
	var bike: Node3D = thrown.call()
	if bike == null:
		for v: Node3D in session.vehicles():
			if is_instance_valid(v) and (bike == null or v.global_position.distance_to(me.global_position)
					< bike.global_position.distance_to(me.global_position)):
				bike = v
	if bike == null:
		return
	# Walk up to it, close enough to get on.
	for i in 400:
		var gap := bike.global_position - me.global_position
		gap.y = 0.0
		if gap.length() < 2.2:
			break
		me.cmd.yaw = _yaw_toward(gap)
		me.cmd.pitch = 0.0
		me.cmd.aim_dir = Vector3.ZERO
		me.cmd.move = Vector2(0, 1)
		await frames(1)
	me.cmd.move = Vector2.ZERO
	await frames(20)


func _test_vehicle_toys_online() -> void:
	print("Online: throwing a toy vehicle")
	_wipe_dir(NET_ACCOUNTS)
	var port := 24871
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var ivy := await _join("Ivy", port, {"vehicle": "bike_scrapper"})
	var jon := await _join("Jon", port) if ivy != null else null
	check(ivy != null and jon != null, "two clients join for the toy checks")
	if ivy != null and jon != null:
		var me := ivy.raid.player
		await _wait_until(func() -> bool: return not ivy.raid.stowed_for(me).is_empty(), 180)
		check(ivy.raid.stowed_for(me) == (["bike_scrapper"] as Array[String]) and jon.raid.stowed_for(jon.raid.player).is_empty(),
				"the server tells each player what is on their own watch")
		await _wait_until(func() -> bool: return not ivy.vehicles().is_empty(), 120)
		var before := ivy.vehicles().size()
		var before_there := jon.vehicles().size()
		check(ivy.raid.throw_toy(me, "bike_scrapper") != "" and ivy.raid.toys.is_empty(), "a client cannot unpack a vehicle on its own")
		ivy.throw_toy("bike_raider")
		await frames(30)
		check(ivy.vehicles().size() == before and ivy.raid.stowed_for(me).size() == 1, "the server refuses a toy the player does not have")
		# The toy in the hand shows to the other player too.
		var ivy_there: Actor = jon._actors.get(ivy.my_actor_id)
		ivy.hold_toy("bike_scrapper")
		check(me.toy_in_hand == "bike_scrapper", "your own hand shows the toy at once")
		await _wait_until(func() -> bool: return ivy_there != null and ivy_there.toy_in_hand == "bike_scrapper", 120)
		check(ivy_there != null and ivy_there.toy_in_hand == "bike_scrapper", "the other player sees the toy in your hand")
		ivy.hold_toy("")
		await _wait_until(func() -> bool: return ivy_there != null and ivy_there.toy_in_hand == "", 120)
		check(ivy_there != null and ivy_there.toy_in_hand == "", "and sees it put back")
		var throws_seen := ivy_there.toy_throws if ivy_there != null else 0
		# Thrown where there is room: the other player may be standing in the way.
		var seen_flying := false
		for turn in 4:
			if ivy.vehicles().size() > before or ivy.raid.stowed_for(me).is_empty():
				break
			me.cmd.yaw = turn * PI * 0.5
			me.cmd.pitch = -0.2
			me.cmd.aim_dir = Vector3.ZERO
			await frames(10)
			ivy.throw_toy("bike_scrapper")
			await _wait_until(func() -> bool: return not jon.raid.toys.is_empty(), 120)
			seen_flying = seen_flying or not jon.raid.toys.is_empty()
			await _wait_until(func() -> bool:
				return ivy.vehicles().size() > before or (jon.raid.toys.is_empty() and not ivy.raid.stowed_for(me).is_empty()), 300)
			await frames(20)
		check(seen_flying, "the other player sees the toy fly")
		check(ivy_there != null and ivy_there.toy_throws > throws_seen and ivy_there.toy_in_hand == "",
				"and sees the arm throw it, the hand empty once it flies")
		await _wait_until(func() -> bool: return ivy.vehicles().size() > before and jon.vehicles().size() > before_there, 300)
		check(ivy.vehicles().size() == before + 1 and jon.vehicles().size() == before_there + 1,
				"it unpacks on the server and both clients get the bike")
		check(ivy.raid.stowed_for(me).is_empty() and ivy.raid.toy_wait(me) > 0.0, "the thrower's watch empties and starts recharging")
		var bike: Node3D = null
		for v: Node3D in ivy.vehicles():
			if v.get("item_id") == "bike_scrapper" and (bike == null or v.global_position.distance_to(me.global_position)
					< bike.global_position.distance_to(me.global_position)):
				bike = v
		check(bike != null and bike.global_position.distance_to(me.global_position) < 30.0, "the bike is where the toy landed, near the thrower")
	await _leave(ivy)
	await _leave(jon)
	OS.kill(pid)
	await frames(30)


func _test_lag_compensation() -> void:
	print("Lag compensation: hits are tested where the attacker saw the target")
	var arena := _vehicle_arena()
	var shooter := Actor.new()
	arena.add_child(shooter)
	shooter.global_position = arena.global_position
	var target := Actor.new()
	arena.add_child(target)
	target.global_position = arena.global_position + Vector3(0, 0, -8)
	Loadout.equip(shooter, ["rifle_scrap"])
	await frames(5)
	var eye := shooter.get_eye_position()
	var chest := Vector3(0, 1.1, 0)
	var now: Vector3 = target.global_position
	var then: Vector3 = now + Vector3(3, 0, 0)
	var hit := Combat.trace(shooter, eye, eye + (now + chest - eye) * 3.0)
	check(hit.get("collider") == target, "with nothing to make up, a shot hits where the target is")
	check(Combat.positions_seen_by(shooter).is_empty(), "offline nothing is rewound")

	# What a lagging shooter saw: the target three metres to the side.
	Combat.rewind = func(attacker: Actor) -> Dictionary:
		return {target: then} if attacker == shooter else {}
	hit = Combat.trace(shooter, eye, eye + (now + chest - eye) * 3.0)
	check(hit.get("collider") != target, "a rewound target is not hit where it has moved on to")
	hit = Combat.trace(shooter, eye, eye + (then + chest - eye) * 3.0)
	check(hit.get("collider") == target and hit.position.distance_to(then + chest) < 0.5,
			"a rewound target is hit where the shooter saw it")
	hit = Combat.trace(target, target.get_eye_position(), shooter.global_position + chest)
	check(hit.get("collider") == shooter, "anyone without a rewind shoots at the present")
	hit = Combat.trace(shooter, eye, eye + Vector3(0, 0, -1) * 20.0 + Vector3(0, 10, 0))
	check(hit.is_empty() or hit.get("collider") is not Actor, "a shot over everyone's head hits nobody")

	# Walls still stop the shot.
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2, 4, 0.4)
	var wall_col := CollisionShape3D.new()
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	arena.add_child(wall)
	wall.global_position = arena.global_position.lerp(then, 0.5) + Vector3(0, 1, 0)
	await frames(2)
	hit = Combat.trace(shooter, eye, eye + (then + chest - eye) * 3.0)
	check(hit.get("collider") == wall, "a wall in front of where the target was still stops the shot")
	wall.queue_free()
	await frames(2)

	# The gun uses it.
	var before := target.health.health + target.health.armor
	var dir := (then + chest - eye).normalized()
	shooter.cmd.aim_dir = dir
	shooter.cmd.yaw = _yaw_toward(dir)
	shooter.cmd.primary = true
	await frames(1)
	shooter.cmd.primary = false
	check(target.health.health + target.health.armor < before, "a rifle shot at where the target was seen lands")

	# Every attacker has their own view of the others.
	var seen_close := now + Vector3(0, 0, 6.5)
	Combat.rewind = func(attacker: Actor) -> Dictionary:
		return {target: seen_close} if attacker == shooter else {}
	check(Combat.positions_seen_by(shooter).get(target) == seen_close and Combat.positions_seen_by(target).is_empty(),
			"each attacker gets their own view of the others")
	Combat.rewind = Callable()
	check(Combat.positions_seen_by(shooter).is_empty(), "clearing the rewind goes back to the present")
	arena.queue_free()
	await frames(2)


func _test_online_stash() -> void:
	print("Online: the server owns the stash")
	var local_stash := Profile.stash.duplicate()
	var port := 24813
	var pid := _start_server(port, ["--bots", "0", "--squad-spawn"])
	var cara := await _sign_in("Cara", port)
	check(cara != null, "a client signs in and waits in the lobby")
	if cara == null:
		OS.kill(pid)
		return
	check(cara.raid == null and cara.my_actor_id < 0, "signing in does not enter the raid")
	check("rifle_carbine" in cara.account.stash and cara.account.loadout.is_empty()
			and not cara.account.has("secret_hash"),
			"the lobby shows the stash the server keeps, with a new account's crates, nothing equipped")

	# Someone else cannot take the name.
	var thief := _new_client("Cara", StashService.new_secret())
	var refusal := [""]
	thief.failed.connect(func(reason: String) -> void: refusal[0] = reason)
	thief.join("127.0.0.1", port)
	await _wait_until(func() -> bool: return refusal[0] != "", 240)
	check(refusal[0] != "" and thief.refused and thief.account.is_empty(), "the same name with another secret is refused (%s)" % refusal[0])
	await _leave(thief)

	# Loadout changes are requests. The server checks them against its stash.
	var errors: Array[String] = []
	cara.lobby_error.connect(func(reason: String) -> void: errors.append(reason))
	cara.equip("primary", "dmr_longshot")
	await _wait_until(func() -> bool: return not errors.is_empty(), 120)
	check(errors.size() == 1 and cara.account.loadout.get("primary", "") == "",
			"the server refuses gear the account does not own")
	cara.equip("primary", "rifle_carbine")
	await _wait_until(func() -> bool: return cara.account.loadout.get("primary", "") == "rifle_carbine", 120)
	check(cara.account.loadout.get("primary", "") == "rifle_carbine", "owned gear equips through the server")
	cara.pick_mastery("rifle", "cut_down")
	await _wait_until(func() -> bool: return errors.size() == 2, 120)
	check(errors.size() == 2 and cara.account.mastery.get("picks", {}).is_empty(), "a locked mastery variant is refused")
	# Home base upgrades are bought on the server too, at its price.
	check(cara.account.get("base_upgrades", ["?"]) == [] and int(cara.account.scrip) == 500,
			"a new account starts in the starter bunker")
	cara.buy_upgrade("ops_consoles")
	await _wait_until(func() -> bool: return cara.account.get("base_upgrades", []) == ["ops_consoles"], 120)
	check(cara.account.get("base_upgrades", []) == ["ops_consoles"] and int(cara.account.scrip) == 0,
			"the server sells a base upgrade and takes the scrip")
	cara.buy_upgrade("gear_hall")
	await _wait_until(func() -> bool: return errors.size() == 3, 120)
	check(errors.size() == 3 and cara.account.get("base_upgrades", []).size() == 1,
			"the server refuses an upgrade the account cannot pay for")
	# Crafting is decided on the server too: no blueprint, no craft.
	check(cara.account.get("blueprints", ["?"]) == [], "a new account knows no blueprints")
	cara.craft("jetpack_mk2")
	await _wait_until(func() -> bool: return errors.size() == 4, 120)
	check(errors.size() == 4 and "jetpack_mk2" not in cara.account.stash and int(cara.account.scrip) == 0,
			"the server refuses a craft without its blueprint (%s)" % [errors.back()])

	cara.deploy()
	await _wait_until(func() -> bool: return cara.raid != null and cara.raid.player != null, 240)
	check(cara.raid != null and cara.raid.player != null, "deploying from the lobby enters the raid")
	if cara.raid != null and cara.raid.player != null:
		var state := cara.raid.state_for(cara.raid.player)
		check(state != null and "rifle_carbine" in state.kit and state.kit.count("medkit") == 2,
				"the kit is the one the server took from the stash")
		await _wait_until(func() -> bool: return cara.account.deployed, 120)
		check(cara.account.deployed and "rifle_carbine" not in cara.account.stash and "medkit" not in cara.account.stash,
				"deployed gear has left the server stash")
	# Dropping the connection leaves the body in the world for the sign-out
	# time. Nobody kills it here, so the gear then comes home.
	await _leave(cara)
	await frames(30)
	cara = await _sign_in("Cara", port)
	check(cara != null, "the same name and secret sign back in")
	if cara != null:
		check(cara.account.deployed and "rifle_carbine" not in cara.account.stash,
				"the body is still out there, with the gear on it")
		var refused: Array[String] = []
		cara.lobby_error.connect(func(reason: String) -> void: refused.append(reason))
		cara.deploy()
		await _wait_until(func() -> bool: return not refused.is_empty(), 120)
		check(refused.size() == 1 and cara.raid == null, "you cannot drop in again while your old body stands")
		await _wait_until(func() -> bool: return not cara.account.deployed,
				int(Worlds.get_world("ashfront").sign_out_time * 60.0) + 300)
		check(not cara.account.deployed and "rifle_carbine" in cara.account.stash
				and cara.account.loadout.get("primary", "") == "rifle_carbine" and cara.account.raids_played == 1
				and cara.account.raids_extracted == 1,
				"the body survived its sign-out: the gear is home and the lobby is told")
		check("bike_scrapper" in cara.account.stash, "gear that stayed in the stash is safe")
	await _leave(cara)
	OS.kill(pid)
	await frames(30)

	# A new server process reads the same accounts from disk.
	pid = _start_server(port + 1, ["--bots", "0"])
	cara = await _sign_in("Cara", port + 1)
	check(cara != null and cara.account.raids_played == 1 and "rifle_carbine" in cara.account.stash,
			"the stash survives a server restart")
	await _leave(cara)
	OS.kill(pid)
	check(Profile.stash == local_stash, "online play never touches the local stash")

	print("Online: the hub as a lobby")
	var hub := Hub.new()
	add_child(hub)
	await frames(1)
	var service := StashService.new()
	service.persist = false
	var id: String = service.sign_in("Lobby Tester", StashService.new_secret()).account_id
	var asked: Array = []
	hub.online_equip_requested.connect(func(slot: String, item_id: String) -> void: asked.append([slot, item_id]))
	hub.enter_lobby(service.snapshot(id), Worlds.get_world("ashfront"))
	check(hub.in_lobby() and hub.options_for("primary") == (["rifle_carbine", "rifle_scrap"] as Array[String])
			and hub.equipped("primary") == "", "in a lobby the hub lists the server's stash and the free scrap, nothing on yet")
	var loadout_before := Profile.loadout.duplicate()
	hub._on_picked(1, "primary")
	check(asked == [["primary", "rifle_carbine"]] and Profile.loadout == loadout_before,
			"picking gear in a lobby asks the server and leaves the local profile alone")
	service.equip(id, "primary", "rifle_carbine")
	hub.update_account(service.snapshot(id))
	check(hub.equipped("primary") == "rifle_carbine" and "rifle" in hub._mastery.loadout_tracks(),
			"the hub shows the loadout the server confirmed")
	hub.leave_lobby()
	check(not hub.in_lobby() and hub.equipped("primary") == Profile.equipped("primary"), "leaving the lobby shows the solo stash again")
	hub.queue_free()


# --- Server-owned stash --------------------------------------------------------

const StashService := preload("res://core/account/stash_service.gd")


func _test_plaza() -> void:
	print("Plaza safe zone")
	var plaza := Worlds.social_world()
	check(plaza != null and plaza.safe_zone, "the registry finds a safe-zone world")
	if plaza == null:
		return
	check(not Worlds.raid_worlds().has(plaza) and Worlds.raid_worlds().size() == Worlds.all().size() - 1,
			"safe zones are not listed as worlds to deploy into")
	var raid := Raid.new()
	add_child(raid)
	raid.mode = Raid.Mode.SERVER
	raid.start_server(plaza, 5)
	var kit: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "field_dressing"]
	var a := raid.add_player(kit, {}, "Ada")
	var b := raid.add_player(kit, {}, "Bo")
	await frames(20)
	check(raid.bots.is_empty(), "no bots in the plaza")
	check(raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer).is_empty(), "no loot in the plaza")
	check(a.is_on_floor() and b.is_on_floor(), "players stand on the plaza floor")
	check(a.gear_items.size() >= 3 and a.weapons.size() == 2, "players wear their loadout (%d pieces)" % a.gear_items.size())
	check(a.weapons_locked and b.weapons_locked, "weapons are locked in a safe zone")

	# Shooting and swinging do nothing.
	b.global_position = a.global_position + Basis(Vector3.UP, a.cmd.yaw) * Vector3(0, 0, -4)
	await frames(2)
	var gun := a.weapons[0] as Gun
	var ammo: int = gun.ammo_in_mag
	a.cmd.primary = true
	a.cmd.primary_pressed = true
	await frames(30)
	a.cmd.primary = false
	a.cmd.primary_pressed = false
	check(gun.ammo_in_mag == ammo, "a held trigger fires nothing")
	check(b.health.health == b.health.max_health, "nobody is hurt")
	a.cmd.switch_weapon = 1
	await frames(2)
	a.cmd.switch_weapon = -1
	check(a.active_weapon_index == 1, "weapons can still be drawn to show them")
	var hit := Combat.deal(b, DamageInfo.make(50.0, a, "bullet", b.global_position))
	check(not hit and b.health.health == b.health.max_health, "Combat refuses every hit in a safe zone")

	# A fall off the map puts you back, unharmed.
	b.global_position = Vector3(0, -40, 0)
	await frames(3)
	check(not b.is_dead and b.global_position.y > -1.0, "falling out puts you back at the arrival pad")

	# Portals: one per raid world, plus home and the clan hall.
	var portals := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("portal"))
	var destinations := portals.map(func(n: Node) -> String: return n.get_meta("destination", ""))
	var all_worlds := Worlds.raid_worlds().all(func(w: WorldDef) -> bool: return ("world:" + w.id) in destinations)
	check(all_worlds, "there is a deploy gate for every raid world")
	check("home" in destinations, "there is a door to the home base")
	check("clans" in destinations, "there is a clan hall")
	check(portals.all(func(n: Node) -> bool: return n.get_meta("label", "") != ""), "every portal says where it goes")
	# Shops are physical places: a storefront for each one the game has.
	var shops: Array = raid.map.shops()
	var fronts := portals.filter(func(n: Node) -> bool: return n.is_in_group("shop_front"))
	check(fronts.size() == shops.size() and shops.all(func(entry: Dictionary) -> bool:
		return ("shop:" + str(entry.id)) in destinations), "every shop has a storefront (%d)" % fronts.size())
	var apart := true
	for one: Node3D in portals:
		for other: Node3D in portals:
			if one != other and one.global_position.distance_to(other.global_position) < 5.5:
				apart = false
	check(apart, "no two doorways overlap")
	var reachable := portals.all(func(n: Node) -> bool:
		return (n as Node3D).global_position.length() < raid.map.RADIUS and absf((n as Node3D).global_position.y) < 0.5)
	check(reachable, "every portal is on the plaza floor")
	# An open district, not a courtyard: the skyline's landing decks stay in
	# reach of the thruster boots (three kicks top 15 m).
	var decks := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("landing_deck"))
	check(raid.map.RADIUS >= 120.0 and decks.size() >= 6 and decks.all(func(n: Node) -> bool:
		return (n as Node3D).global_position.y <= 15.5), "the hub is open and its landing decks are in boot reach (%d)" % decks.size())
	var floor_hit := raid.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(0, 5, raid.map.RADIUS - 6.0), Vector3(0, -5, raid.map.RADIUS - 6.0), Actor.LAYER_WORLD))
	check(not floor_hit.is_empty(), "the deck reaches out to the balcony rail")
	var deck: Node3D = decks[0] if not decks.is_empty() else null
	var deck_hit := {} if deck == null else raid.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(deck.global_position + Vector3(0, 5, 0),
			deck.global_position - Vector3(0, 5, 0), Actor.LAYER_WORLD))
	check(not deck_hit.is_empty() and absf(deck_hit.position.y - deck.global_position.y) < 0.3,
			"a landing deck is solid where it is marked")

	# Leaving takes you and nothing else: no body, no bag.
	raid.remove_player(b)
	await frames(3)
	check(not is_instance_valid(b) or b.is_queued_for_deletion(), "a player who leaves is simply gone")
	check(raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer).is_empty(), "leaving drops no bag")
	check(raid.players.size() == 1, "the others stay")

	# A warzone in the same process keeps its own rules.
	var war := Raid.new()
	add_child(war)
	war.start(Worlds.get_world("ashfront"), 3)
	for bot in war.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	check(Worlds.of(a) == plaza and Worlds.of(war.player).id == "ashfront", "each actor answers to its own world")
	var foe := war.bots[0]
	check(Combat.deal(foe, DamageInfo.make(5.0, war.player, "bullet", foe.global_position)), "the warzone still deals damage")
	check(not Combat.deal(a, DamageInfo.make(5.0, war.player, "bullet", a.global_position)),
			"a warzone hit cannot reach into the plaza")
	check(not Combat.deal(foe, DamageInfo.make(5.0, a, "bullet", foe.global_position)),
			"a plaza player cannot hurt anyone in the warzone")
	await _end_raid(war)
	await _end_raid(raid)


func _test_clans() -> void:
	print("Clans: players who stand together")
	const ClanPanel := preload("res://core/social/clan_panel.gd")
	var clans := ClanService.new()
	clans.persist = false
	var names := func(id: String) -> String: return id.capitalize()
	check(not clans.create("ada", "x", "WLF").ok and not clans.create("ada", "Wolves", "!").ok
			and not clans.create("", "Wolves", "WLF").ok, "a clan needs a real name, a tag and a founder")
	var made := clans.create("ada", "  The   Wolves ", "w-lf!")
	check(made.ok and clans.name_of(made.clan) == "The Wolves" and clans.tag_of(made.clan) == "WLF",
			"founding a clan cleans its name and tag")
	check(not clans.create("bo", "the wolves", "XX").ok and not clans.create("bo", "Others", "wlf").ok,
			"names and tags are not shared")
	check(not clans.create("ada", "Second", "SEC").ok and not clans.join("ada", made.clan).ok,
			"an account is in one clan at most")
	check(clans.join("bo", made.clan).ok and clans.clan_of("bo") == made.clan and not clans.join("cy", "nope").ok,
			"others join it by id")
	clans.max_members = 2
	check(not clans.join("cy", made.clan).ok, "a full clan takes nobody")
	clans.max_members = 24
	var seen: Dictionary = clans.snapshot("bo", names)
	check(seen.clan.name == "The Wolves" and seen.clan.members == ["Ada", "Bo"] and seen.clan.leader == "Ada"
			and not seen.clan.is_leader and seen.clans.size() == 1 and seen.clans[0].members == 2
			and not str(seen).contains("ada"), "a member sees the roster by name, never by account")
	check(ClanPanel.lines(seen)[0] == "[WLF] The Wolves" and ClanPanel.lines(seen)[1] == "Ada  (leader)"
			and ClanPanel.lines(clans.snapshot("cy", names)) == ["[WLF] The Wolves  2 members"]
			and ClanPanel.lines({})[0].begins_with("No clans"), "the hall's screen lists it")
	check(clans.leave("ada").ok and clans.snapshot("bo", names).clan.is_leader and clans.clan_of("ada") == "",
			"when the leader goes the next member leads")
	check(clans.leave("bo").ok and clans.snapshot("bo", names).clans.is_empty() and not clans.leave("bo").ok,
			"a clan with nobody left is gone")

	# Saved and read back.
	var dir := "user://test_clans"
	_wipe_dir(dir)
	var saved := ClanService.new()
	saved.open(dir, true)
	var kept: String = saved.create("ada", "Keepers", "KEEP").clan
	saved.join("bo", kept)
	var again := ClanService.new()
	again.open(dir, true)
	check(again.clan_of("bo") == kept and again.members_of(kept) == ["ada", "bo"] and again.tag_of(kept) == "KEEP"
			and not again.create("cy", "Keepers", "K2").ok, "clans are saved with the accounts")
	_wipe_dir(dir)

	# In a warzone clanmates are one side.
	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 3)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	raid.set_team("acct-a", "c1", "Wolves")
	raid.set_team("acct-b", "c1", "Wolves")
	var a := raid.add_player([], {}, "Ada", "acct-a")
	var b := raid.add_player([], {}, "Bo", "acct-b")
	var c := raid.add_player([], {}, "Cy", "acct-c")
	for actor: Actor in [a, b, c]:
		actor.set_physics_process(false)
		actor.protected_left = 0.0
	a.clan = "c1"
	b.clan = "c1"
	check(raid.side_of(a)[0] == raid.side_of(b)[0] and raid.side_of(a)[1] == "Wolves"
			and raid.side_of(c)[0] != raid.side_of(a)[0] and Visor.allied(a, b) and not Visor.allied(a, c),
			"clanmates are one side, and a stranger is not")
	if not raid.strongpoints.is_empty():
		var point := raid.strongpoints[0]
		point.hold(raid.side_of(a)[0], "Wolves", true)
		check(raid.holds(b, point) and not raid.holds(c, point), "ground one clanmate takes is held by the clan")
		check("point:%d" % point.index in raid.drop_choices("acct-b").map(func(d: Dictionary) -> String: return d.id)
				and "point:%d" % point.index not in raid.drop_choices("acct-c").map(func(d: Dictionary) -> String: return d.id),
				"and a clanmate can drop in on it")
	var before := b.health.health
	check(not Combat.deal(b, DamageInfo.make(20.0, a, "bullet")) and b.health.health == before,
			"clanmates cannot hurt each other")
	check(Combat.deal(c, DamageInfo.make(20.0, a, "bullet")) and Combat.deal(a, DamageInfo.make(5.0, c, "bullet")),
			"everyone else is fair game")
	raid.set_team("acct-b", "")
	check(raid._player_side("acct-b") == "acct-b", "leaving the team puts a player back on their own")
	raid.queue_free()
	await frames(2)


func _test_world_heat() -> void:
	print("World heat: what a doorway says about the world behind it")
	const PlazaView := preload("res://core/social/plaza_view.gd")
	var raid := Raid.new()
	add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("frostline"), 0)
	var empty := raid.status()
	check(empty.players == 0 and empty.level == "Quiet" and empty.bounty == 0 and empty.event == "",
			"an empty world reports itself quiet")
	var a := raid.add_player([], {}, "Ada", "acct_a")
	raid.add_player([], {}, "Bo", "acct_b")
	a.bounty = 150
	raid.war.intensity = 0.62
	raid.start_event("warlord")
	var busy := raid.status()
	check(busy.players == 2 and busy.level == "Battle" and busy.bounty == 150 and busy.event != "",
			"a busy one reports players, war level, top bounty and event: %s" % PlazaView.heat_text(busy))
	check(not str(busy).contains("Ada") and not busy.has("centre"), "and never who or where anyone is")
	check(PlazaView.heat_text({}) == "" and PlazaView.heat_text(empty) == "QUIET   0 players",
			"the sign is blank until the server speaks, and short when nothing is on")
	check(PlazaView.heat_text(busy).contains("2 players") and PlazaView.heat_text(busy).contains("Top bounty 150")
			and PlazaView.heat_text({"players": 1, "level": "Skirmish"}) == "SKIRMISH   1 player",
			"it lists players and the top bounty")
	check(PlazaView.heat_color(1.0).g < PlazaView.heat_color(0.0).g, "the sign reddens as the war heats up")
	raid.queue_free()
	await frames(2)

	# A client cleans what it is told.
	var net := NetSession.new()
	add_child(net)
	net._world_status({"ashfront": {"players": -4, "war": 9.0, "level": "x".repeat(200), "bounty": "12"}, 7: {}, "bad": 3})
	var got: Dictionary = net.world_status.get("ashfront", {})
	check(net.world_status.size() == 1 and got.players == 0 and got.war == 1.0 and got.level.length() <= 24
			and got.bounty == 12, "a client cleans the status it is sent")
	net.queue_free()
	await frames(1)


## A squad portal in the plaza, online: Pia (`ada`) opens one from the
## watch and her clanmate Pax (`bo`) walks through it. The server decides.
func _plaza_portal(ada: NetSession, bo: NetSession) -> void:
	await _wait_until(func() -> bool: return ada.raid.side_of(ada.raid.player)[0] != "", 30)
	ada.open_portal("ashfront")
	await _wait_until(func() -> bool: return not bo.raid.portals.is_empty() and not ada.raid.portals.is_empty(), 240)
	var seen: Portal = bo.raid.portals[0] if not bo.raid.portals.is_empty() else null
	check(seen != null and seen.destination == "ashfront" and seen.usable and seen.opener_name == "Pia",
			"a portal opened from the watch shows up for the squad, ready to use")
	if seen == null:
		return
	var travelled: Array[String] = []
	bo.portal_travel.connect(func(destination: String) -> void: travelled.append(destination))
	var walker := bo.raid.player
	await frames(int(seen.unfold_time * 60.0) + 10)
	for step in 360:
		var to := seen.global_position - walker.global_position
		to.y = 0.0
		walker.cmd.yaw = atan2(-to.x, -to.z)
		walker.cmd.move = Vector2(0, 1) if to.length() > 0.2 else Vector2.ZERO
		await frames(1)
		if not travelled.is_empty() or not is_instance_valid(seen):
			break
	walker.cmd.move = Vector2.ZERO
	check(travelled == ["ashfront"], "a squadmate who walks in is sent through by the server")


func _test_plaza_online() -> void:
	print("Plaza online: a shared safe zone beside the warzone")
	const PlazaView := preload("res://core/social/plaza_view.gd")
	var port := 24861
	_wipe_dir(NET_ACCOUNTS)
	var pid := _start_server(port, ["--plaza", "--bots", "0"])
	var ada := await _join("Pia", port, {"primary": "rifle_carbine"})
	check(ada != null, "a client walks into the server's plaza")
	if ada == null:
		OS.kill(pid)
		return
	check(ada.world_id == "plaza" and ada.raid.world.safe_zone, "the server's front door is the plaza")
	check(ada.routes.get("ashfront", -1) == port + 1, "the plaza says where the warzone runs")
	await _wait_until(func() -> bool: return ada.world_status.has("ashfront"), 240)
	var quiet: Dictionary = ada.world_status.get("ashfront", {})
	check(quiet.get("players", -1) == 0 and quiet.get("level", "") == "Quiet" and not ada.world_status.has("plaza"),
			"the plaza hears how the warzone is doing: %s" % PlazaView.heat_text(quiet))
	var me := ada.raid.player
	check("rifle_carbine" in me.gear_items and me.weapons_locked, "you wear your loadout, with weapons locked")
	await frames(30)
	check(not ada.account.deployed and "rifle_carbine" in ada.account.stash,
			"wearing gear in the plaza takes nothing out of the stash")

	var bo := await _join("Pax", port, {"primary": "smg_stinger"} if "smg_stinger" in ada.account.stash else {})
	check(bo != null, "a second player joins the plaza")
	if bo != null:
		await _wait_until(func() -> bool: return RaidRoster.players_in(ada.raid).size() == 2, 240)
		var seen: Array[Actor] = RaidRoster.players_in(ada.raid).filter(func(a: Actor) -> bool: return a != me)
		check(seen.size() == 1 and seen[0].display_name == "Pax", "players see each other by name")
		if seen.size() == 1:
			var bo_seen := seen[0]
			var card := PlazaView.gear_lines(bo_seen)
			var bo_gear: Array = bo.raid.player.gear_items
			check(not card.is_empty() and card.all(func(line: Dictionary) -> bool: return line.id in bo_gear),
					"you can read what another player is wearing (%d pieces)" % card.size())
			# Bo walks; Ada sees it.
			var from := bo_seen.global_position
			bo.raid.player.cmd.move = Vector2(0, 1)
			await frames(60)
			bo.raid.player.cmd.move = Vector2.ZERO
			check(bo_seen.global_position.distance_to(from) > 2.0, "movement is shared (%.1f m)" % bo_seen.global_position.distance_to(from))
			# Ada aims at Bo and holds the trigger. Nothing happens.
			var aim := (bo_seen.global_position + Vector3(0, 1.1, 0) - me.get_eye_position()).normalized()
			me.cmd.yaw = atan2(-aim.x, -aim.z)
			me.cmd.aim_dir = aim
			me.cmd.primary = true
			me.cmd.primary_pressed = true
			await frames(60)
			me.cmd.primary = false
			var bo_me := bo.raid.player
			check(bo_me.health.health == bo_me.health.max_health and not bo_me.is_dead, "nobody can be shot in the plaza")
			# Aim again where Bo is now: the view of him can still settle after he stops.
			aim = (bo_seen.global_position + Vector3(0, 1.1, 0) - me.get_eye_position()).normalized()
			var looking := PlazaView.inspect_target(ada.raid, me, me.get_eye_position(), aim, 60.0, 9.0)
			check(looking == bo_seen, "looking at a player picks them for the gear card")
			check(PlazaView.gear_tag(bo_seen).begins_with(bo_seen.display_name.to_upper()) and "Kit worth" in PlazaView.gear_tag(bo_seen),
					"their gear is written on a tag over their head")

	# The contract board: taking a job is the server's call, and the answer
	# comes back in the account.
	var job: String = ada.account.get("contracts", {}).get("offers", [""])[0]
	ada.contract_ask("take", job)
	await _wait_until(func() -> bool: return ada.account.get("contracts", {}).get("active", []).size() == 1, 240)
	check(job != "" and ada.account.contracts.active[0].id == job, "the plaza's contract board takes a job on the server")
	# The clan hall: Pia founds a clan, Pax joins it, and both wear its tag.
	ada.clan_ask("create", "Night Shift", "ns")
	await _wait_until(func() -> bool: return not ada.clan_state.get("clan", {}).is_empty(), 240)
	check(ada.clan_state.get("clan", {}).get("tag", "") == "NS" and ada.clan_state.clan.is_leader,
			"founding a clan at the hall makes you its leader")
	await _wait_until(func() -> bool: return me.clan_tag == "NS", 240)
	check(me.clan_tag == "NS" and me.clan == "", "you wear the tag at once, and the plaza stays a safe zone")
	if bo != null:
		await _wait_until(func() -> bool: return bo.clan_state.get("clans", []).size() == 1, 240)
		check(bo.clan_state.get("clans", []).size() == 1 and bo.clan_state.clan.is_empty(),
				"everyone in the plaza sees the new clan listed")
		bo.clan_ask("join", str(ada.clan_state.clan.id))
		await _wait_until(func() -> bool: return ada.clan_state.clan.get("members", []).size() == 2, 240)
		check(ada.clan_state.clan.get("members", []) == ["Pia", "Pax"], "a second player joins it: %s" % [ada.clan_state.clan.get("members", [])])
		var pax_seen: Array[Actor] = RaidRoster.players_in(ada.raid).filter(func(a: Actor) -> bool: return a != me)
		await _wait_until(func() -> bool: return pax_seen.size() == 1 and pax_seen[0].clan_tag == "NS", 240)
		check(pax_seen.size() == 1 and PlazaView.gear_tag(pax_seen[0]).begins_with("[NS] PAX"),
				"and the tag is on the card over their head")
		ada.clan_ask("create", "Second", "SEC")
		await frames(30)
		check(ada.clan_state.clan.get("tag", "") == "NS", "you cannot found a second clan while in one")
		await _plaza_portal(ada, bo)

	# Through the gate: the same account, now in the warzone's lobby.
	var war_port: int = ada.routes.get("ashfront", -1)
	await _leave(ada)
	if bo != null:
		await _wait_until(func() -> bool: return RaidRoster.players_in(bo.raid).size() == 1, 240)
		check(RaidRoster.players_in(bo.raid).size() == 1, "a player who leaves is gone from the plaza")
		check(bo.containers().is_empty(), "and leaves no bag behind")
	var ada_war := await _sign_in("Pia", war_port)
	check(ada_war != null and ada_war.world_id == "ashfront", "the gate leads to the warzone on the next port")
	if ada_war != null:
		check(ada_war.account.loadout.get("primary", "") == "rifle_carbine" and "rifle_carbine" in ada_war.account.stash,
				"the account is the same one: loadout and stash carry over")
		ada_war.deploy()
		await _wait_until(func() -> bool: return ada_war.raid != null and ada_war.raid.player != null, 240)
		await _wait_until(func() -> bool: return ada_war.account.deployed, 120)
		check(ada_war.raid != null and not ada_war.raid.world.safe_zone and ada_war.account.deployed
				and not ada_war.raid.player.weapons_locked, "deploying there is a real raid with gear at stake")
		check(ada_war.clan_state.get("clan", {}).get("tag", "") == "NS" and ada_war.raid.player.clan_tag == "NS"
				and ada_war.raid.player.clan != "", "the clan follows you into the warzone, where it is your side")
		ada_war.clan_ask("leave")
		await frames(30)
		check(ada_war.clan_state.get("clan", {}).get("tag", "") == "NS", "nobody changes sides in the field")
		if bo != null:
			await _wait_until(func() -> bool: return bo.world_status.get("ashfront", {}).get("players", 0) == 1, 600)
			check(bo.world_status.get("ashfront", {}).get("players", 0) == 1,
					"someone still in the plaza sees the warzone fill up")
		await _leave(ada_war)
	await _leave(bo)

	# The whole trip through the game's own flow.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(2)
	Profile.player_name = "Quill"
	# Joined the way a player does: from the phone's Servers app.
	main.phone.open("servers")
	main.phone.join_server("127.0.0.1:%d" % port)
	check(not main.phone.is_open and main.base == null and main.net != null,
			"joining from the phone puts it away and heads out of the base")
	await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
	check(main.raid != null and main.raid.world.safe_zone and main.plaza_view != null and not main.hub.visible,
			"joining a server puts you in its plaza")
	if main.raid != null:
		var gate: Node3D = null
		for node in get_tree().get_nodes_in_group("portal"):
			if main.raid.map.is_ancestor_of(node) and node.get_meta("destination", "") == "world:ashfront":
				gate = node
		check(gate != null and PlazaView.portal_at(main.raid, gate.global_position) == gate
				and PlazaView.portal_at(main.raid, Vector3(0, 0, 20)) == null, "standing in a gate offers the trip")
		check(gate != null and PlazaView.prompt_for(gate, main.net.routes).begins_with("[F]")
				and PlazaView.prompt_for(gate, {}).contains("closed"), "a gate to a world the server lacks is closed")
		var heat: Label3D = main.plaza_view.heat_signs.get("ashfront")
		await _wait_until(func() -> bool: return heat != null and heat.visible, 240)
		check(heat != null and heat.visible and heat.text.begins_with("QUIET") and gate != null
				and heat.global_position.y > gate.global_position.y + 3.0,
				"the sign over the gate says how that world is doing")
		main.use_portal("clans")
		await frames(3)
		check(main.shop_view != null and main.shop_screen != null and main.shop_view.panel.has_signal("asked"),
				"the clan hall door opens its terminal")
		main.close_shop()
		await frames(2)
		var shops: Array = main.raid.map.shops()
		if not shops.is_empty():
			var shop_id: String = shops[0].id
			var stall: Node3D = null
			for front: Node in main.raid.get_tree().get_nodes_in_group("shop_front"):
				if front.get_meta("shop_id", "") == shop_id and main.raid.map.is_ancestor_of(front):
					stall = front
			main.raid.player.global_position = stall.global_position + Vector3(0, 0.1, 0)
			main.use_portal("shop:" + shop_id)
			await frames(3)
			check(main.shop_view != null and main.shop_view.panel.shop_filter == shop_id
					and main.controller.input_blocked and main.raid != null,
					"a storefront opens that shop's screen without leaving the plaza")
			check(main.shop_screen != null and main.shop_screen.get_parent() == stall.get_node("Screen")
					and main.shop_screen.focused and main.get_viewport().get_camera_3d() != main.controller.camera
					and main.hud != null and not main.hud.visible and not main.plaza_view.visible,
					"the shop comes up on the terminal on its counter and the view moves in to it")
			var panel: Control = main.shop_view.panel
			var before: int = panel.scrip()
			var stock: Array = panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
				return (b as Button).text.begins_with("Buy") and not (b as Button).disabled)
			check(not stock.is_empty() and before > 0, "the stall shows stock and your scrip on this server (%d)" % before)
			if not stock.is_empty():
				(stock[0] as Button).pressed.emit()
				await _wait_until(func() -> bool:
					return main.shop_view != null and main.shop_view.panel.scrip() < before, 240)
				check(main.shop_view.panel.scrip() < before, "buying at the stall goes through the server")
			main.close_shop()
			await frames(2)
			check(main.shop_view == null and main.shop_screen == null and not main.controller.input_blocked
					and main.get_viewport().get_camera_3d() == main.controller.camera and main.hud.visible,
					"stepping away gives control, the view and the HUD back")
		main.use_portal("world:ashfront")
		await _wait_until(func() -> bool:
			return main.raid != null and main.raid.player != null and main.raid.world.id == "ashfront", 600)
		check(main.raid != null and main.raid.world.id == "ashfront" and main.base == null and not main.hub.visible
				and main.net != null and main.net.world_id == "ashfront",
				"using a gate deploys you straight into that world, not into a lobby")
		# Straight back, as going home while down does (the body stays out
		# there a moment, so the stall above came first).
		main._return_to_lobby({})
		await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null and main.raid.world.safe_zone, 600)
		check(main.raid != null and main.raid.world.safe_zone, "leaving the world leads back to the plaza")
		if main.raid != null and main.raid.player != null:
			var back_gate: Node3D = null
			for node in get_tree().get_nodes_in_group("portal"):
				if main.raid.map.is_ancestor_of(node) and node.get_meta("destination", "") == "world:ashfront":
					back_gate = node
			var off: Vector3 = main.raid.player.global_position - back_gate.global_position
			check(Vector2(off.x, off.z).length() < float(back_gate.get_meta("radius", 2.0)) + 4.0,
					"and you arrive in front of that world's gate (%.1f m)" % Vector2(off.x, off.z).length())
		main.use_portal("home")
		await _wait_until(func() -> bool: return main.base != null, 600)
		check(main.base != null and main.raid == null and main.hub.in_lobby(),
				"the quarters door opens your home base on the server's stash")
		check(main.base != null and main.base.door.get_prompt().contains("Back to"),
				"the base's door leads back to the plaza")
		main.base.leave_requested.emit()
		await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
		check(main.base == null and main.raid != null and main.raid.world.safe_zone,
				"the base's door leads back to the plaza")
		main.use_portal("leave")
		await frames(5)
		check(main.net == null and main.raid == null and main.base != null and not main.hub.in_lobby(),
				"the exit leaves the server and takes you home")
		check(Profile.home_server == "127.0.0.1:%d" % port, "the door remembers the server you joined from the phone")
		# Straight out of the door: no screen, back in that server's plaza.
		main.base.leave_requested.emit()
		check(main.hub.station == "" and main.station_screen == null, "the door opens no screen")
		await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 600)
		check(main.raid != null and main.raid.world.safe_zone and main.net != null and main._server_pid <= 0,
				"the door of your own base leads straight to the plaza of the server it remembers")
		main.phone.open("servers")
		await frames(1)
		check(main.phone._body.find_children("*", "Label", true, false).any(
				func(label: Label) -> bool: return label.text == "Connected as Quill"),
				"online, the phone's Servers app says who you are on the server")
		main.phone.leave_server()
		await frames(5)
		check(main.net == null and main.raid == null and main.base != null and not main.hub.in_lobby()
				and not main.phone.is_open, "the phone's Servers app leaves the server and takes you home")
	OS.kill(pid)
	await frames(30)
	# The remembered server is gone: the door starts a server of your own,
	# with every world behind the plaza's gates.
	main.host_port = port + 20
	main.host_args = PackedStringArray(["--accounts", NET_ACCOUNTS, "--bots", "0"])
	if main.base != null:
		main.base.leave_requested.emit()
		await _wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 3600)
		check(main.raid != null and main.raid.world.safe_zone and main._server_pid > 0,
				"with that server gone the door starts one of your own and walks you into its plaza")
		var open_gates := 0
		for world in Worlds.raid_worlds():
			open_gates += 1 if main.net != null and main.net.routes.has(world.id) else 0
		check(open_gates == Worlds.raid_worlds().size() and open_gates > 0,
				"a server of your own runs every world, so the gates are where you choose (%d open)" % open_gates)
		check(Profile.home_server == "127.0.0.1:%d" % port, "the door still remembers the server it could not reach")
		if main.raid != null:
			main.use_portal("leave")
			await frames(5)
		check(main._server_pid <= 0 and main.base != null, "leaving stops your own server and takes you home")
	Profile.home_server = ""
	main._stop_local_server()
	main.queue_free()
	await frames(30)


func _test_stash_service() -> void:
	print("Server stash service")
	var world := Worlds.get_world("ashfront")
	var profile_stash := Profile.stash.duplicate()
	var dir := "user://test_accounts_%d" % Time.get_ticks_usec()
	var service := StashService.new()
	service.save_dir = dir
	var secret := StashService.new_secret()
	check(secret.length() >= StashService.MIN_SECRET and secret != StashService.new_secret(), "secrets are long and random")

	check(not service.sign_in("x", secret).ok, "a too-short name is refused")
	check(not service.sign_in("Vex", "short").ok, "a weak secret is refused")
	var first := service.sign_in("Vex Runner", secret)
	check(first.ok and first.created and first.account_id == "vex_runner", "the first sign-in creates the account")
	var again := service.sign_in("vex runner", secret)
	check(again.ok and not again.created and again.account_id == "vex_runner", "the same name and secret sign back in")
	check(not service.sign_in("Vex Runner", StashService.new_secret()).ok, "someone else's secret cannot take the name")
	var id: String = first.account_id

	var snap := service.snapshot(id)
	check(snap.ok and "rifle_carbine" in snap.stash and "bike_scrapper" in snap.stash, "a new account gets the welcome and gear crates")
	check(not snap.has("secret_hash") and not snap.has("salt"), "a snapshot carries no secrets")
	var crate_size: int = snap.stash.size()
	service.sign_in("Vex Runner", secret)
	check(service.snapshot(id).stash.size() == crate_size, "crates are granted only once")

	check(not service.equip(id, "primary", "dmr_longshot").ok, "the server refuses gear the account does not own")
	check(not service.equip(id, "melee", "rifle_carbine").ok, "the server refuses gear in the wrong slot")
	check(service.equip(id, "primary", "rifle_carbine").ok and service.equip(id, "frame", "frame_trooper").ok,
			"owned gear equips")
	check(not service.pick_mastery(id, "rifle", "cut_down").ok, "a locked mastery variant cannot be picked")

	var deploy := service.deploy(id, world)
	check(deploy.ok and "rifle_carbine" in deploy.kit and "frame_trooper" in deploy.kit, "deploying hands back the kit")
	check(deploy.kit.count("medkit") == 2, "deploying takes the healing items")
	var after_deploy: Array = service.snapshot(id).stash
	check("rifle_carbine" not in after_deploy and "medkit" not in after_deploy, "deployed gear leaves the server stash")
	check(not service.deploy(id, world).ok, "an account cannot deploy twice at once")
	check(not service.equip(id, "primary", "rifle_carbine").ok, "the loadout is locked during a raid")

	# A server crash mid-raid: a fresh service loads the save and returns the gear.
	var restarted := StashService.new()
	restarted.save_dir = dir
	var reloaded := restarted.snapshot(id)
	check(reloaded.ok and not reloaded.deployed and "rifle_carbine" in reloaded.stash and reloaded.stash.count("medkit") == 2,
			"an unsettled deploy is returned after a restart")
	check(reloaded.loadout.get("primary", "") == "rifle_carbine", "the loadout survives a restart")
	check(restarted.sign_in("Vex Runner", secret).ok and not restarted.sign_in("Vex Runner", StashService.new_secret()).ok,
			"sign-in still checks the secret after a restart")

	# Bank, then leave a real raid alive, and settle its result.
	deploy = restarted.deploy(id, world)
	var raid := Raid.new()
	raid.apply_to_profile = false
	add_child(raid)
	raid.start(world, 61, deploy.kit, deploy.picks)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(3)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	check(restarted.bank(id, ["alloy_ingot", "rifle_scrap", "no_such_item"]).ok
			and restarted.snapshot(id).stash.count("alloy_ingot") == 1
			and "rifle_scrap" not in restarted.snapshot(id).stash and restarted.snapshot(id).deployed,
			"banked loot reaches the stash while still deployed, and scrap never does")
	raid.player.inventory.add_item("scrap_metal")
	raid.begin_sign_out(raid.player)
	raid.state_for(raid.player).sign_out_left = 0.1
	await frames(20)
	check(results.size() == 1 and results[0].outcome == "left", "the server-stash life ends by leaving")
	if results.size() == 1:
		check(restarted.settle(id, results[0]).ok, "the result settles")
	var home := restarted.snapshot(id)
	check("rifle_carbine" in home.stash and "scrap_metal" in home.stash and home.raids_extracted == 1,
			"leaving alive brings gear and loot into the server stash")
	check(not home.deployed and not restarted.settle(id, results[0] if results.size() == 1 else {}).ok,
			"a result cannot be settled twice")
	check(not restarted.bank(id, ["alloy_ingot"]).ok, "nothing can be banked from the hub")
	check(Profile.stash == profile_stash, "the server stash never touches the local profile")
	await _end_raid(raid)

	# Dying loses the deployed gear.
	deploy = restarted.deploy(id, world)
	restarted.settle(id, {"outcome": "died", "brought_home": [], "kills": 2, "mastery_xp": {"rifle": 999999}})
	home = restarted.snapshot(id)
	check("rifle_carbine" not in home.stash and home.loadout.get("primary", "") == "rifle_scrap",
			"dying loses the gear, and the free scrap gun takes its slot")
	check(home.kills == 2 and restarted.pick_mastery(id, "rifle", "cut_down").ok, "mastery XP is kept after death")

	# A join that never happened gives everything back.
	var before: Array = restarted.snapshot(id).stash
	restarted.deploy(id, world)
	check(restarted.cancel_deploy(id).ok and restarted.snapshot(id).stash.size() == before.size(),
			"cancelling a deploy returns the gear")
	check(restarted.snapshot("nobody").ok == false and not restarted.deploy("nobody", world).ok,
			"unknown accounts are refused")

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# --- The phone ---------------------------------------------------------------

const SocialService := preload("res://core/social/social_service.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const Handheld := preload("res://core/phone/handheld.gd")


## Stands in for `ActorSkin` in the phone tests: a hand holding `held`.
class HandSkin extends Node:
	var held: Node3D
	var phone_screen: Material
	var locomotion: Object = self

	func handheld() -> Node3D:
		return held

	func set_phone_screen(screen: Material) -> void:
		phone_screen = screen
		var face := Handheld.face_of(held)
		if face != null:
			face.set_surface_override_material(0, screen)
const MirrorScript := preload("res://core/visual/mirror.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")
const DevEconomy := preload("res://core/economy/economy.gd")
const DevStashRules := preload("res://core/account/stash_rules.gd")
const DevBaseUpgrades := preload("res://core/base/base_upgrades.gd")


## DEV MODE: the temporary testing mode (`core/dev/dev_mode.gd`). Delete this
## group along with it.
func _test_dev_mode() -> void:
	print("Dev mode (temporary)")
	DevMode.persist = false
	DevMode.enabled = false
	check(DevMode.available(), "dev mode can be switched on in a debug run")
	check(DevMode.raid_cheats().is_empty(), "with dev mode off a raid gets no cheats")

	# The dev stash: every piece of gear, healing in bulk, max scrip.
	var stash: Array[String] = []
	check(DevMode.top_up(stash) == DevEconomy.MAX_SCRIP, "dev mode holds as many scrip as a stash can")
	var every_fit := true
	for id: String in ItemDB.all_ids():
		if not DevStashRules.storable(id):
			check(id not in stash, "%s (starter or power) never enters a dev stash" % id)
			continue
		for slot: String in Loadout.SLOTS:
			if Loadout.fits(slot, id) and id not in stash:
				every_fit = false
	check(every_fit, "every rig, gun, blade, helmet, ability, attachment and vehicle is in the dev stash")
	check(stash.count("medkit") == DevMode.CONSUMABLE_COPIES, "the dev stash has healing in bulk")
	var full := stash.size()
	DevMode.top_up(stash)
	check(stash.size() == full, "topping up again adds nothing")
	stash.erase("wings_glide")
	DevMode.top_up(stash)
	check("wings_glide" in stash and stash.size() == full, "gear lost in a run comes back on the next top-up")

	# The dev save never touches the real one, and you stay you.
	var real_path := "user://test_profile_real.json"
	var dev_path := "user://test_profile_dev.json"
	for path in [real_path, dev_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	Profile.reset()
	Profile.persist = true
	Profile.save_path = real_path
	Profile.player_name = "Tester"
	Profile.add_to_stash(["rifle_carbine", "rifle_carbine", "rifle_carbine"])
	var real_scrip := Profile.scrip
	Profile.use_save(dev_path)
	Profile.scrip = DevMode.top_up(Profile.stash)
	Profile.save()
	check(Profile.save_path == dev_path and "helm_ember_mk2" in Profile.stash and Profile.player_name == "Tester",
			"the dev save has everything and keeps who you are")
	Profile.use_save(real_path)
	check("helm_ember_mk2" not in Profile.stash and Profile.stash.count("rifle_carbine") >= 3
			and Profile.scrip == real_scrip, "switching back finds the real stash untouched")
	Profile.use_save(dev_path)
	check("helm_ember_mk2" in Profile.stash and Profile.scrip == DevEconomy.MAX_SCRIP,
			"the dev save is kept between switches")
	Profile.persist = false
	Profile.save_path = Profile.SAVE_PATH
	Profile.player_name = "Raider"
	Profile.reset()
	for path in [real_path, dev_path]:
		DirAccess.remove_absolute(path)

	# A save from before the fresh start (free test gear, a full base, leaked
	# dev scrip) is set back to a fresh player once, keeping who you are.
	Profile.reset()
	var old_save := Profile.to_dict()
	old_save.erase("fresh_start")
	old_save.player_name = "Caleb"
	old_save.online_secret = "kept-secret"
	old_save.stash = ["wings_glide", "boots_thruster", "chip_blink", "helm_ember_mk2"]
	old_save.scrip = DevEconomy.MAX_SCRIP
	old_save.base_upgrades = DevBaseUpgrades.full()
	old_save.welcome_granted = true
	Profile.load_dict(old_save)
	check(Profile.fresh_start < Profile.FRESH_START, "a save from before the fresh start is spotted")
	Profile.start_fresh()
	Profile.grant_welcome_crate()
	check(Profile.player_name == "Caleb" and Profile.online_secret == "kept-secret"
			and Profile.scrip == DevEconomy.STARTING_SCRIP and Profile.base_upgrades.is_empty()
			and "wings_glide" not in Profile.stash and "helm_ember_mk2" not in Profile.stash
			and "bike_scrapper" in Profile.stash and Profile.fresh_start == Profile.FRESH_START,
			"the fresh start keeps who you are and leaves a new player's stash, scrip and base")
	Profile.load_dict(Profile.to_dict())
	check(Profile.fresh_start == Profile.FRESH_START, "and it happens only once")
	Profile.player_name = "Raider"
	Profile.online_secret = ""
	Profile.reset()

	# A dev server's snapshots never go back into the real save: the game only
	# takes on snapshots from a server it hosted from the same save.
	var main_view: Node = load("res://core/main.gd").new()
	main_view._server_pid = 1
	main_view._join_address = "127.0.0.1"
	main_view._hosted_save = Profile.DEV_SAVE_PATH
	var dev_snapshot := {"ok": true, "stash": ["helm_ember_mk2"], "scrip": DevEconomy.MAX_SCRIP,
			"base_upgrades": DevBaseUpgrades.full()}
	main_view._keep_profile_in_step(dev_snapshot)
	check("helm_ember_mk2" not in Profile.stash and Profile.base_upgrades.is_empty()
			and Profile.scrip == DevEconomy.STARTING_SCRIP,
			"turning dev mode off on your own dev server leaks nothing into the real profile")
	main_view._hosted_save = Profile.save_path
	main_view._keep_profile_in_step(dev_snapshot)
	check("helm_ember_mk2" in Profile.stash, "a server hosted from this save still keeps it in step")
	main_view._server_pid = -1
	main_view.free()
	Profile.reset()

	# Online: a server hosted in dev mode tops up the host's account only, and
	# the host is whoever claims the handed profile with its secret, never
	# just someone using the host's name.
	var service := StashService.new()
	service.persist = false
	service.dev_host = true
	var host_secret := StashService.new_secret()
	service.host_profile = {"player_name": "Dev Host", "online_secret": host_secret}
	var host_id: String = service.sign_in("Dev Host", host_secret).account_id
	var friend_id: String = service.sign_in("Dev Friend", StashService.new_secret()).account_id
	var spoofed := StashService.new()
	spoofed.persist = false
	spoofed.dev_host = true
	spoofed.host_profile = {"player_name": "Dev Host", "online_secret": host_secret}
	var faker: String = spoofed.sign_in("Dev Host", StashService.new_secret()).account_id
	check("helm_ember_mk2" not in spoofed.snapshot(faker).stash,
			"signing in with the host's name but not their secret gets no dev stash")
	var host_view := service.snapshot(host_id)
	check("helm_ember_mk2" in host_view.stash and host_view.scrip == DevEconomy.MAX_SCRIP,
			"a dev server gives the host's account everything and max scrip")
	check("helm_ember_mk2" not in service.snapshot(friend_id).stash, "other players on it get nothing extra")
	var host_account = service.load_account(host_id)
	host_account.stash.erase("wings_glide")
	check("wings_glide" in service.snapshot(host_id).stash, "gear the host lost comes back on the server too")

	# Cheats in a solo raid.
	DevMode.enabled = true
	check(DevMode.raid_cheats().size() == DevMode.CHEATS.size(), "dev mode on hands a raid its cheats")
	DevMode.set_cheat("ammo", false)
	check(not DevMode.raid_cheats().has("ammo"), "a cheat can be switched off on its own")
	DevMode.set_cheat("ammo", true)
	var raid := await _new_raid(77, false)
	raid.set_dev_cheats(DevMode.raid_cheats())
	await frames(2)
	var me := raid.player
	me.protected_left = 0.0
	var bot: Actor = raid.bots[0] if not raid.bots.is_empty() else null
	var hit := Combat.deal(me, DamageInfo.make(500.0, bot, "bullet"))
	check(not hit and not me.is_dead and me.dev_invulnerable, "god mode: no hit gets through")
	me.flight.heat = me.flight.max_heat
	me.flight.overheated = true
	me.ability.cooldown_left = 5.0
	var gun: Gun = null
	for weapon in me.weapons:
		if weapon is Gun:
			gun = weapon
	if gun != null:
		gun.ammo_in_mag = 0
	await frames(2)
	check(me.flight.heat == 0.0 and not me.flight.overheated, "endless flight heat")
	check(me.ability.cooldown_left == 0.0, "no ability cooldowns")
	check(gun != null and gun.ammo_in_mag == gun.mag_size, "endless ammo keeps the magazine full")
	raid.set_dev_cheats({})
	await frames(1)
	me.protected_left = 0.0
	check(not me.dev_invulnerable and Combat.deal(me, DamageInfo.make(5.0, bot, "bullet")),
			"turning god mode off lets hits through again")
	await _end_raid(raid)
	var server := Raid.new()
	server.mode = Raid.Mode.SERVER
	server.set_dev_cheats({"god": true})
	check(server.dev_cheats.is_empty(), "an online server raid never runs dev cheats")
	server.free()

	# The switch lives in the phone's settings.
	DevMode.enabled = false
	var phone: CanvasLayer = PhoneScript.new()
	add_child(phone)
	await frames(1)
	var changes := [0]
	phone.dev_mode_changed.connect(func() -> void: changes[0] += 1)
	phone.toggle()
	phone.open_app("settings")
	check("dev" in phone.settings_tabs(), "in a debug run the phone's settings have a Dev tab")
	for child in phone._body.get_children():
		check(not (child is CheckButton and (child as CheckButton).text.begins_with("Dev mode")),
				"the dev switches stay off the other tabs")
	phone.open_settings_tab("dev")
	await frames(1)
	var switch_shown := false
	for child in phone._body.get_children():
		if child is CheckButton and (child as CheckButton).text.begins_with("Dev mode"):
			switch_shown = true
	check(switch_shown, "the phone's settings have the dev mode switch")
	phone.set_dev_mode(true)
	check(DevMode.enabled and changes[0] == 1, "the phone turns dev mode on")
	phone.set_dev_mode(false)
	check(not DevMode.enabled and changes[0] == 2, "and off again")
	phone.close()
	phone.queue_free()
	await frames(1)


func _test_phone() -> void:
	_test_social_service()
	_test_game_settings()
	await _test_phone_view()
	await _test_phone_escape()
	await _test_online_phone()


func _test_social_service() -> void:
	print("Phone: the server's social service")
	var social := SocialService.new()
	social.persist = false
	social.player_online("ana", "Ana")
	social.player_online("ben", "Ben")
	var snap := social.snapshot("ana", 1000.0)
	check(snap.contacts.size() == 1 and snap.contacts[0].id == "ben" and snap.contacts[0].online
			and snap.contacts[0].where == "lobby" and not snap.contacts[0].saved,
			"everyone signed in to the server shows up as a contact, without you")
	social.set_where("ben", "raid")
	check(social.snapshot("ana", 1000.0).contacts[0].where == "raid", "contacts show where a player is")

	var sent := social.send_message("ana", "ben", "  meet at the\nnorth exit  ", 1000.0)
	check(sent.ok and sent.message.text == "meet at the north exit",
			"a message is delivered with control characters stripped")
	check(social.snapshot("ben", 1000.0).messages.size() == 1 and social.snapshot("ana", 1000.0).messages.size() == 1,
			"both sides keep the message")
	check(not social.send_message("ana", "ben", "   ", 1000.0).ok, "an empty message is refused")
	check(not social.send_message("ana", "ana", "hi", 1000.0).ok, "you cannot message yourself")
	check(not social.send_message("ana", "zed", "hi", 1000.0).ok, "you cannot message someone who is not here")
	check(social.send_message("ana", "ben", "x".repeat(1000), 1001.0).message.text.length() == SocialService.MAX_MESSAGE,
			"a long message is cut to the limit")
	var accepted := 0
	for i in 10:
		if social.send_message("ana", "ben", "spam %d" % i, 1002.0).ok:
			accepted += 1
	check(accepted == SocialService.RATE_LIMIT - 2, "messages are rate limited")
	check(social.send_message("ana", "ben", "later", 1002.0 + SocialService.RATE_WINDOW + 1.0).ok,
			"the limit wears off")

	# Saved contacts can be messaged while they are offline.
	check(social.add_contact("ana", "ben").ok and social.snapshot("ana", 1100.0).contacts[0].saved, "a player can be saved as a contact")
	check(not social.add_contact("ana", "nobody").ok, "only people you have met can be saved")
	social.player_offline("ben")
	var offline_snap := social.snapshot("ana", 1100.0)
	check(offline_snap.contacts.size() == 1 and not offline_snap.contacts[0].online and offline_snap.contacts[0].name == "Ben",
			"a saved contact stays listed, by name, when they leave")
	check(social.send_message("ana", "ben", "see you tomorrow", 1100.0).ok, "a saved contact can be messaged while offline")
	social.player_online("ben", "Ben")
	var log: Array = social.snapshot("ben", 1100.0).messages
	check(log[log.size() - 1].text == "see you tomorrow", "the message is waiting when they come back")

	# Invites.
	check(not social.invite("ana", "ben", "party", "ashfront", 1200.0).ok, "only raids and bases can be invited to")
	check(not social.invite("ana", "zed", "world", "ashfront", 1200.0).ok, "only players online can be invited")
	var made := social.invite("ana", "ben", "world", "ashfront", 1200.0)
	check(made.ok and social.invites_for("ben", 1200.0).size() == 1 and social.invites_for("ana", 1200.0).is_empty(),
			"an invite reaches only the player invited")
	social.invite("ana", "ben", "world", "ashfront", 1201.0)
	check(social.invites_for("ben", 1201.0).size() == 1, "a repeat invite replaces the old one")
	social.invite("ana", "ben", "base", "", 1201.0)
	var open: Array[Dictionary] = social.invites_for("ben", 1201.0)
	check(open.size() == 2, "raid and base invites are separate")
	var world_invite: Dictionary = open[0] if open[0].kind == "world" else open[1]
	check(not social.answer_invite("ana", world_invite.id, true, 1202.0).ok, "only the invited player can answer")
	var answer := social.answer_invite("ben", world_invite.id, true, 1202.0)
	check(answer.ok and answer.accepted and answer.invite.world_id == "ashfront", "an accepted invite says where to go")
	check(not social.answer_invite("ben", world_invite.id, true, 1202.0).ok, "an invite is answered once")
	check(social.invites_for("ben", 1201.0 + SocialService.INVITE_SECONDS + 1.0).is_empty(), "invites expire")

	# Blocking.
	social.invite("ana", "ben", "world", "ashfront", 1300.0)
	social.block("ben", "ana")
	check(social.invites_for("ben", 1300.0).is_empty(), "blocking drops their open invites")
	check(not social.send_message("ana", "ben", "hello?", 1300.0).ok and not social.invite("ana", "ben", "base", "", 1300.0).ok,
			"a blocked player can no longer message or invite")
	var ben_view := social.snapshot("ben", 1300.0)
	check(ben_view.contacts.size() == 1 and ben_view.contacts[0].blocked, "a blocked player is listed as blocked")
	social.unblock("ben", "ana")
	check(social.send_message("ana", "ben", "hello again", 1400.0).ok, "unblocking lets them through again")

	# Leaving drops invites; news always has the game's own.
	social.invite("ana", "ben", "world", "ashfront", 1500.0)
	social.player_offline("ana")
	check(social.invites_for("ben", 1500.0).is_empty(), "invites from a player who left are gone")
	check(social.snapshot("ben", 1500.0).news.size() == SocialService.GAME_NEWS.size(), "the phone gets the game news")
	social.server_news.append({"date": "today", "title": "Double loot weekend", "body": "Caches hold more."})
	check(social.news()[0].title == "Double loot weekend", "server news comes first")

	# Saved social data survives a restart.
	var dir := "user://test_social"
	_wipe_dir(dir)
	var saving := SocialService.new()
	saving.save_dir = dir
	saving.player_online("ana", "Ana")
	saving.player_online("ben", "Ben")
	saving.add_contact("ana", "ben")
	saving.send_message("ben", "ana", "kept", 2000.0)
	var reloaded := SocialService.new()
	reloaded.save_dir = dir
	var kept := reloaded.snapshot("ana", 2000.0)
	check(kept.contacts.size() == 1 and kept.contacts[0].name == "Ben" and kept.messages[0].text == "kept",
			"contacts and messages are saved per account")
	_wipe_dir(dir)


func _test_game_settings() -> void:
	print("Phone: settings")
	GameSettings.persist = false
	GameSettings.reset()
	GameSettings.set_value("mouse_sensitivity", 99.0)
	GameSettings.set_value("field_of_view", 10.0)
	GameSettings.set_value("master_volume", 0.5)
	GameSettings.set_value("nonsense", 1)
	check(is_equal_approx(GameSettings.mouse_sensitivity, GameSettings.SENSITIVITY_RANGE.y)
			and is_equal_approx(GameSettings.field_of_view, GameSettings.FOV_RANGE.x), "settings are clamped to sane values")
	check(not GameSettings.to_dict().has("nonsense"), "unknown settings are ignored")
	var bus := AudioServer.get_bus_index("Master")
	check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.01, "volume reaches the audio bus")
	GameSettings.reset()
	GameSettings.apply()


## The Controls app lists every key from the input map as it is right now.
func _test_phone_controls(phone: CanvasLayer) -> void:
	var listed := {}
	var unknown: Array[String] = []
	for section: Array in PhoneScript.CONTROLS:
		for row: Array in section[1]:
			var spec: String = row[1]
			var at := spec.find("{")
			while at >= 0:
				var end := spec.find("}", at)
				var action := spec.substr(at + 1, end - at - 1)
				listed[action] = true
				if not InputMap.has_action(action):
					unknown.append(action)
				at = spec.find("{", end)
	check(unknown.is_empty(), "the Controls app names only real input actions (%s)" % ", ".join(unknown))
	var missing: Array[String] = []
	var setup: GDScript = preload("res://core/input_setup.gd")
	for action: String in setup.KEY_ACTIONS.keys() + setup.MOUSE_ACTIONS.keys():
		if not listed.has(action) and action not in missing:
			missing.append(action)
	check(missing.is_empty(), "every keybind is listed in the phone's Controls app (missing: %s)" % ", ".join(missing))
	check(PhoneScript.key_name("interact") == "F" and PhoneScript.key_name("fire") == "Left mouse",
			"keys are named the way a player reads them")
	InputMap.add_action("test_twice")
	var first_key := InputEventKey.new()
	first_key.physical_keycode = KEY_Q
	InputMap.action_add_event("test_twice", first_key)
	var thumb := InputEventMouseButton.new()
	thumb.button_index = MOUSE_BUTTON_XBUTTON1
	InputMap.action_add_event("test_twice", thumb)
	check(PhoneScript.key_name("test_twice") == "Q or Mouse back", "an action bound twice shows both")
	InputMap.erase_action("test_twice")
	check(not InputMap.has_action("roll_left") and not InputMap.has_action("roll_right"),
			"Q and E fly nothing: the air dash is Shift + a move key")
	check(PhoneScript.controls_text("Hold {jump}") == "Hold Space", "a key spec reads from the input map")
	phone.open_app("controls")
	check(phone.app == "controls" and phone._title.text == "Controls" and phone._body.get_child_count() > 20,
			"the phone has a Controls app")
	# Rebinding shows straight away, since the list reads the input map.
	var old_events := InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_K
	InputMap.action_add_event("interact", rebound)
	check(PhoneScript.controls_text("{interact}") == "K", "a rebound key shows in the Controls app")
	InputMap.action_erase_events("interact")
	for event: InputEvent in old_events:
		InputMap.action_add_event("interact", event)
	check(PhoneScript.key_name("interact") == "F", "the binding is put back")
	phone.open_app("settings")
	var link := false
	for child in phone._body.get_children():
		if child is Button and (child as Button).text.contains("every key"):
			link = true
	check(link, "settings link to the Controls app")


func _test_phone_escape() -> void:
	print("Phone: Tab and Esc")
	check(PhoneScript.key_name("toggle_view") == "Tab" and PhoneScript.key_name("scoreboard") == "Q",
			"Tab switches the camera and Q holds the scoreboard")
	var phone: CanvasLayer = PhoneScript.new()
	add_child(phone)
	await frames(1)
	var esc_key := InputEventKey.new()
	esc_key.keycode = KEY_ESCAPE
	esc_key.pressed = true
	check(not phone.opens_on_escape(esc_key), "Esc leaves the phone shut where a screen has the mouse")
	phone.mouse_in_world = true
	check(phone.opens_on_escape(esc_key), "Esc is the phone's when the world has the mouse")
	phone._unhandled_input(esc_key)
	check(phone.is_open and phone.app == "settings", "Esc in the world opens the phone at Settings")
	phone._unhandled_input(esc_key)
	check(not phone.is_open, "Esc again closes the phone")
	phone.queue_free()
	await frames(1)


func _test_phone_view() -> void:
	print("Phone: the menu itself")
	var phone: CanvasLayer = PhoneScript.new()
	add_child(phone)
	await frames(1)
	var events: Array = []
	phone.opened_changed.connect(func(open: bool) -> void: events.append(open))
	phone.settings_changed.connect(func() -> void: events.append("settings"))
	check(not phone.is_open and not phone.online(), "the phone starts put away and offline")
	check(phone.unseen_news() == SocialService.GAME_NEWS.size(), "unread news is counted")
	phone.toggle()
	check(phone.is_open and events == [true], "the phone opens")
	await _test_phone_home(phone)
	phone.open_app("news")
	check(phone.unseen_news() == 0 and phone._body.get_child_count() == SocialService.GAME_NEWS.size(),
			"news can be read offline")
	phone.open_app("contacts")
	check(phone._body.get_child_count() == 1, "offline, contacts explain how to reach players")
	await _test_phone_controls(phone)
	GameSettings.persist = false
	phone.open_app("settings")
	check(phone.settings_tab == "input" and phone._tabs.visible and phone._tabs.get_child_count() == phone.settings_tabs().size(),
			"settings open on the Input tab, with a row of tabs")
	phone.open_settings_tab("view")
	await frames(1)
	var sliders := 0
	for child in phone._body.get_children():
		if child is PanelContainer and child.find_children("*", "HSlider", true, false).size() > 0:
			sliders += 1
	check(phone.settings_tab == "view" and sliders == 4, "the View tab has the fields of view, the camera distance and the first-person pullback")
	phone.open_app("news")
	check(not phone._tabs.visible, "other apps have no tabs")
	phone.open_app("settings")
	phone.change_setting("field_of_view", 95.0)
	check(is_equal_approx(GameSettings.field_of_view, 95.0) and "settings" in events, "settings change from the phone")
	phone.change_setting("field_of_view_third", 105.0)
	check(is_equal_approx(GameSettings.field_of_view_third, 105.0) and is_equal_approx(GameSettings.field_of_view, 95.0),
			"first and third person keep their own field of view")
	check(GameSettings.to_dict().has("field_of_view_third"), "the third-person field of view is saved")
	check(is_equal_approx(GameSettings.camera_distance, 2.0), "the third-person camera starts close, over the shoulder")
	phone.change_setting("camera_distance", 3.5)
	check(is_equal_approx(GameSettings.camera_distance, 3.5) and GameSettings.to_dict().has("camera_distance"),
			"the phone sets how far back the third-person camera sits, and it is saved")
	phone.change_setting("camera_distance", 99.0)
	check(is_equal_approx(GameSettings.camera_distance, GameSettings.CAMERA_DISTANCE_RANGE.y), "within its range")
	GameSettings.camera_distance = 2.0
	check(GameSettings.eye_pullback > 0.0, "the first-person camera starts pulled back a little from the face")
	phone.change_setting("eye_pullback", 99.0)
	check(is_equal_approx(GameSettings.eye_pullback, GameSettings.EYE_PULLBACK_RANGE.y)
			and GameSettings.to_dict().has("eye_pullback"), "it can be set from the phone, within its range")
	GameSettings.eye_pullback = 0.15
	phone.close()
	check(not phone.is_open and events[events.size() - 1] == false, "the phone closes")

	# In a raid, the phone stops the character and frees the mouse.
	var raid := await _new_raid(91, false)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	await frames(2)
	controller.input_blocked = true
	controller.phone_out = true
	await frames(2)
	check(raid.player.cmd.move == Vector2.ZERO and not raid.player.cmd.primary, "with the phone out the character lets go of the controls")
	check(raid.player.cmd.phone, "and holds the phone up")
	controller.input_blocked = false
	controller.phone_out = false
	await frames(2)
	check(not raid.player.cmd.phone, "putting it away lowers it")

	# Third person eases the camera in over the shoulder to read the phone in
	# the hand; first person only drops the eyes to it.
	var reader := HandSkin.new()
	reader.name = "Skin"
	reader.held = Handheld.build()
	var had_skin := raid.player.has_node("Skin")
	if not had_skin:
		raid.player.add_child(reader)
		raid.player.add_child(reader.held)
		reader.held.position = Vector3(0.15, 1.4, -0.4)
		await frames(1)
		var face := controller.phone_panel()
		check(face != null and face == Handheld.face_of(reader.held), "the controller finds the phone in the hand")
		check(reader.held.find_child("Holo", true, false) == null and reader.held.find_child("Beam", true, false) == null,
				"nothing floats off the phone: its screen is read in the hand, in every view")
		controller.view_mode = PlayerController.ViewMode.THIRD
		controller.input_blocked = true
		controller.phone_out = true
		for i in 40:
			await frames(1)
		check(controller.phone_read > 0.99, "with the phone out in third person the camera eases in to read it")
		check(controller.camera.global_position.distance_to(face.global_position) < 1.5
				and absf(controller.camera.global_basis.x.normalized().dot(face.global_basis.y.normalized())) < 0.1,
				"and frames it beside the head with its lines level")
		var to_face := controller.camera.global_transform.affine_inverse() * face.global_position
		check(to_face.z < 0.0 and to_face.x > 0.0, "the phone sits in view, right of the crosshair")
		var square := -(controller.camera.global_basis.z.normalized()).dot(face.global_basis.z.normalized())
		check(square < -0.7, "the camera looks nearly square onto the screen, so it reads")
		check(_phone_share(controller) > 0.3, "and the phone stands large in the view")
		controller.phone_out = false
		controller.input_blocked = false
		for i in 40:
			await frames(1)
		check(controller.phone_read == 0.0, "putting it away eases the camera back out")
		controller.view_mode = PlayerController.ViewMode.FIRST
		var pitch_before := controller.pitch
		controller.input_blocked = true
		controller.phone_out = true
		for i in 40:
			await frames(1)
		check(controller.phone_read == 0.0, "first person reads the phone from the eyes, with no reading camera")
		check(absf(controller.camera.global_rotation.x - controller.phone_view_pitch) < 0.02
				and is_equal_approx(controller.pitch, pitch_before),
				"the eyes drop to the phone in the hand, while the aim stays where it was")
		check(controller.phone_zoomed() and controller.camera.fov < controller.wanted_base_fov() - 10.0
				and absf(controller.camera.fov - controller.phone_fit_fov()) < 1.0,
				"the view zooms in on the phone in the hand so it can be read (Caleb's pick)")
		check(_phone_share(controller) > 0.3 and _phone_share(controller) <= controller.phone_zoom + 0.02,
				"the phone stands a good share of the view's height, all of it in frame")
		# Wide or narrow, the field of view setting ends at the same phone.
		var share := _phone_share(controller)
		controller.base_fov = 110.0
		for i in 40:
			await frames(1)
		check(absf(_phone_share(controller) - share) < 0.05, "a wide field of view zooms just as far in on the phone")
		controller.base_fov = 80.0
		controller.phone_out = false
		controller.input_blocked = false
		for i in 40:
			await frames(1)
		check(absf(controller.camera.global_rotation.x - pitch_before) < 0.02, "and come back up when it is put away")
		check(not controller.phone_zoomed() and absf(controller.camera.fov - controller.wanted_base_fov()) < 1.0,
				"and the zoom eases back out")
	else:
		reader.held.free()
		reader.free()
	await _end_raid(raid)
	GameSettings.reset()
	phone.queue_free()
	await frames(1)


## How much of the view's height the phone in the hand fills, from its corners.
func _phone_share(controller: PlayerController) -> float:
	var face := controller.phone_panel() as VisualInstance3D
	var box := face.get_aabb()
	var low := INF
	var high := -INF
	for i in 8:
		var at := controller.camera.unproject_position(face.global_transform * box.get_endpoint(i))
		low = minf(low, at.y)
		high = maxf(high, at.y)
	return (high - low) / controller.camera.get_viewport().get_visible_rect().size.y


## The home screen, its icons and badges, going back, and the phone held up
## in front of a camera with the scene dimmed behind it.
func _test_phone_home(phone: CanvasLayer) -> void:
	check(phone.app == PhoneScript.HOME and phone._home.visible and not phone._page.visible,
			"the phone opens on its home screen")
	check(phone._icons.size() == PhoneScript.APPS.size() and phone._icons.keys().all(
			func(a: String) -> bool: return a in PhoneScript.APPS), "every app has an icon on the home screen")
	check(phone._icons["news"].badge == SocialService.GAME_NEWS.size() and phone._icons["settings"].badge == 0,
			"unread news shows as a badge on the News icon")
	phone._icons["news"].tapped.emit()
	check(phone.app == "news" and phone._page.visible and not phone._home.visible and phone._title.text == "News",
			"tapping an icon opens the app")
	check(phone._icons["news"].badge == 0, "reading the news clears its badge")
	phone.go_back()
	check(phone.app == PhoneScript.HOME and phone._home.visible, "back goes home")
	phone.open_app("messages")
	phone.chat_with = "someone"
	phone.go_back()
	check(phone.app == "messages" and phone.chat_with == "", "back from a conversation goes to the list of them")
	phone.go_home()
	check(phone.app == PhoneScript.HOME, "the home bar goes home from anywhere")
	phone.close()
	phone.open()
	check(phone.app == PhoneScript.HOME, "it opens where it was left")
	check(phone._status.text.length() == 5 and phone._who.text == "Solo" and phone._bars.strength == 0,
			"the status bar has the time, no signal and Solo while offline")
	check(phone._readouts["link"].value.text == "SOLO" and phone._readouts["news"].value.text == str(SocialService.GAME_NEWS[0].title),
			"the home screen reads out the link and the latest news")
	phone._readouts["news"].tapped.emit()
	check(phone.app == "news", "a readout opens its app")
	phone.go_home()

	# No hand to hold it: the screen shows flat, and a click on it lands on it.
	await _drawn_frames(2)
	check(phone._flat.visible and phone._device == null, "with no hand to hold it the screen shows flat")
	var middle: Vector2 = phone._flat.get_global_rect().get_center()
	check(phone.screen_point(middle).distance_to(Vector2(phone.screen_size) * 0.5) < 1.0,
			"a click on the flat screen lands in the same spot on the phone")
	check(phone.screen_point(phone._flat.get_global_rect().position - Vector2(5, 5)).x < 0.0, "a click beside it misses")

	# The device itself: the one handheld every view shows, held by its grip.
	var held: Node3D = Handheld.build()
	var face := Handheld.face_of(held)
	check(face != null and face.mesh.get_surface_count() == 2 and face.position.y > 0.0,
			"the handheld's screen is a face of its own, above the grip at its origin")
	check(held.get_node_or_null("Handle") != null and held.get_node("Handle").position == Vector3.ZERO,
			"the grip is where the hand closes, at the handheld's origin")
	held.free()
	var slab: ArrayMesh = PhoneScript.rounded_slab(Vector2(0.15, 0.3), 0.02, 0.03)
	check(slab.get_surface_count() == 2 and slab.get_aabb().size.is_equal_approx(Vector3(0.15, 0.3, 0.02)),
			"the phone is a rounded slab, its face a surface of its own")
	# Held in a hand: a click on the handheld's face lands on the screen.
	var stage := Node3D.new()
	add_child(stage)
	var camera := Camera3D.new()
	camera.fov = 75.0
	stage.add_child(camera)
	camera.make_current()
	var holder := Node3D.new()
	stage.add_child(holder)
	var skin := HandSkin.new()
	skin.name = "Skin"
	holder.add_child(skin)
	var in_hand: Node3D = Handheld.build()
	stage.add_child(in_hand)
	in_hand.position = Vector3(0.0, -0.25, -0.45)
	skin.held = in_hand
	phone.set_holder(holder)
	await _drawn_frames(2)
	check(phone._device == Handheld.face_of(in_hand) and not phone._flat.visible,
			"with a hand to hold it, the phone is the handheld in that hand, not a flat screen")
	check(Handheld.face_of(in_hand).get_surface_override_material(0) == phone._face_mat,
			"and its face shows this phone's screen")
	var on_face := camera.unproject_position(Handheld.face_of(in_hand).global_transform * Vector3(0.0, 0.0, Handheld.DEPTH * 0.5))
	check(phone.screen_point(on_face).distance_to(Vector2(phone.screen_size) * 0.5) < 4.0,
			"the mouse on the handheld's own screen lands on the screen, in every view")
	check(phone.screen_point(Vector2(1, 1)).x < 0.0, "the mouse off the handheld misses it")
	check((phone._face_mat as StandardMaterial3D).albedo_texture == phone._screen.get_texture(),
			"the handheld's face shows the phone's screen")
	phone.set_holder(null)
	phone.close()
	await _drawn_frames(2)
	check(not phone._flat.visible, "put away, the flat screen goes too")
	phone.open()
	camera.queue_free()
	stage.queue_free()
	await _drawn_frames(1)

	# The flag that shows everyone else the phone is a held key.
	var cmd := ActorCommand.new()
	cmd.phone = true
	var back := ActorCommand.new()
	back.apply_array(cmd.to_array())
	check(back.phone and cmd.flags() & ActorCommand.HELD_MASK & ActorCommand.FLAG_PHONE != 0,
			"holding the phone travels with the held keys, so others see it")


## Frames drawn, not physics ticks: the phone is placed as the view is drawn.
func _drawn_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _test_online_phone() -> void:
	print("Online: phones reach other players")
	var port := 24851
	_wipe_dir(NET_ACCOUNTS)
	var pid := _start_server(port, ["--bots", "0"])
	var ana := await _sign_in("Ana", port)
	var ben := await _sign_in("Ben", port)
	check(ana != null and ben != null, "two players sign in")
	if ana == null or ben == null:
		await _leave(ana)
		await _leave(ben)
		OS.kill(pid)
		return
	var sees := func(session: NetSession, who: String) -> bool:
		for entry: Dictionary in session.social_state.get("contacts", []):
			if entry.id == who and entry.online:
				return true
		return false
	await _wait_until(func() -> bool: return sees.call(ana, "ben") and sees.call(ben, "ana"), 240)
	check(sees.call(ana, "ben") and sees.call(ben, "ana"), "each phone lists the other player online")

	var phone: CanvasLayer = PhoneScript.new()
	add_child(phone)
	phone.set_session(ben)
	var notices: Array[String] = []
	ben.social_notice.connect(func(text: String) -> void: notices.append(text))
	ana.send_message("ben", "Want to run the docks?")
	await _wait_until(func() -> bool: return phone.unread_count() == 1, 240)
	check(phone.unread_count() == 1 and phone.conversation_with("ana")[0].text == "Want to run the docks?",
			"a message arrives on the other phone, unread")
	check(notices.any(func(t: String) -> bool: return t.contains("docks")), "it pops up as a notice")
	phone.open()
	phone.open_chat("ana")
	check(phone.unread_count() == 0, "opening the conversation marks it read")
	phone.send_message("ana", "Sure")
	await _wait_until(func() -> bool: return ana.social_state.get("messages", []).size() == 2, 240)
	check(ana.social_state.get("messages", []).size() == 2, "the reply goes back through the server")

	# A raid invite: accepting it deploys into the same server's raid.
	var accepted: Array = []
	ben.world_invite_accepted.connect(func(invite: Dictionary) -> void: accepted.append(invite))
	var ana_notices: Array[String] = []
	ana.social_notice.connect(func(text: String) -> void: ana_notices.append(text))
	ana.send_invite("ben", "world")
	await _wait_until(func() -> bool: return phone.invites().size() == 1, 240)
	check(phone.invites().size() == 1 and phone.invites()[0].kind == "world", "the invite shows on the phone")
	phone.answer_invite(int(phone.invites()[0].id), true)
	await _wait_until(func() -> bool: return not accepted.is_empty(), 240)
	check(accepted.size() == 1 and accepted[0].world_id == "ashfront", "accepting tells the game where to go")
	await _wait_until(func() -> bool: return ana_notices.any(func(t: String) -> bool: return t.contains("accepted")), 240)
	check(ana_notices.any(func(t: String) -> bool: return t.contains("accepted")), "the inviter hears it was accepted")

	# A base invite carries the owner's gear for a read-only visit.
	var visits: Array = []
	ben.base_visit_requested.connect(func(owner: String, owner_stash: Array, _loadout: Dictionary, upgrades: Array) -> void:
		visits.append([owner, owner_stash, upgrades]))
	ana.send_invite("ben", "base")
	await _wait_until(func() -> bool: return phone.invites().size() == 1, 240)
	phone.answer_invite(int(phone.invites()[0].id), true)
	await _wait_until(func() -> bool: return not visits.is_empty(), 240)
	check(visits.size() == 1 and visits[0][0] == "Ana" and "rifle_carbine" in visits[0][1] and visits[0][2] == [],
			"accepting a base invite brings the owner's stash and base upgrades to show")

	# Presence follows the player into the raid.
	ana.deploy()
	await _wait_until(func() -> bool:
		return ben.social_state.get("contacts", []).any(func(c: Dictionary) -> bool: return c.id == "ana" and c.where == "raid"), 240)
	check(ben.social_state.get("contacts", []).any(func(c: Dictionary) -> bool: return c.id == "ana" and c.where == "raid"),
			"contacts show who is in the raid")

	# Blocking is enforced by the server.
	var errors: Array[String] = []
	ana.social_error.connect(func(reason: String) -> void: errors.append(reason))
	phone.change_contact("block", "ana")
	await _wait_until(func() -> bool: return phone.contact("ana").get("blocked", false), 240)
	ana.send_message("ben", "hello?")
	await _wait_until(func() -> bool: return not errors.is_empty(), 240)
	check(not errors.is_empty() and phone.conversation_with("ana").size() == 2, "a blocked player's messages are refused")

	await _leave(ana)
	await _wait_until(func() -> bool: return not sees.call(ben, "ana"), 240)
	check(not sees.call(ben, "ana"), "a player who leaves goes offline on the other phones")
	phone.queue_free()
	await _leave(ben)
	OS.kill(pid)
	await frames(30)
	_wipe_dir(NET_ACCOUNTS)


## Stands the actor in front of a home base display, looking at it.
func _face_display(actor: Actor, display: Node3D) -> void:
	var out: Vector3 = display.global_transform.basis.z
	actor.global_position = Vector3(display.global_position.x, 0.1, display.global_position.z) + out * 2.0
	actor.velocity = Vector3.ZERO
	var eye := actor.global_position + Vector3(0, actor.eye_height, 0)
	# Aim at the middle of the display's hit box.
	var col: CollisionShape3D = null
	for child in display.get_children():
		if child is CollisionShape3D:
			col = child
	var dir := (col.global_position - eye).normalized()
	actor.cmd.yaw = atan2(-dir.x, -dir.z)
	actor.cmd.pitch = asin(dir.y)
	actor.cmd.aim_dir = dir


func _use(actor: Actor) -> void:
	actor.cmd.interact_pressed = true
	await frames(1)
	actor.cmd.interact_pressed = false
	await frames(1)


## Every weapon hangs on the one armory rack, in the alcove with the bench
## and the locker at its way in; nothing else is shown there.
func _test_armory(base: HomeBase) -> void:
	print("Home base armory")
	var weapons: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "weapon") and not ItemDB.has_tag(id, "starter"):
			weapons.append(id)
	var every_weapon := true
	for id in weapons:
		every_weapon = every_weapon and BaseLayout.is_armory(BaseLayout.kind_for(id))
	check(not weapons.is_empty() and every_weapon, "every weapon belongs on the armory rack (%d weapons)" % weapons.size())
	var spots := 0
	var in_alcove := true
	var others_out := true
	for kind: String in BaseLayout.KINDS:
		var last := int(BaseLayout.KINDS[kind]["spots"]) - 1
		var ends := [base.spot_transform(kind, 0).origin, base.spot_transform(kind, last).origin]
		if BaseLayout.is_armory(kind):
			spots += last + 1
			for at: Vector3 in ends:
				in_alcove = in_alcove and base.in_armory(at)
		elif kind != "gunsmith":
			for at: Vector3 in ends:
				others_out = others_out and not base.in_armory(at)
	check(in_alcove and BaseLayout.ARMORY.size() == 3, "the rack's sections all hang inside the armory")
	check(others_out, "armor, rigs, the garage and the shelves stay in the main room")
	check(spots > 14, "the rack holds more weapons than the old gun rack and blade wall did (%d spots)" % spots)
	await _test_suit_up(base)
	# The bench has a corner of its own off the armory, clear of the rack
	# and of the walk in, with the fabricator beside it.
	var bench_at := base.bench_transform().origin
	var craft := base.station(HomeBase.CRAFT_ID)
	var clear := true
	for display in base.displays:
		if BaseLayout.is_armory(display.kind):
			clear = clear and display.position.distance_to(bench_at) > 2.0 and not base.in_workshop(display.position)
	check(base.in_armory(bench_at) and base.in_workshop(bench_at) and bench_at.z > base.armory_size.z * 0.5
			and craft != null and base.in_workshop(craft.position) and clear and base.has_node("WorkshopSign"),
			"the gunsmith bench and the fabricator stand in a workshop of their own off the armory, clear of the rack")
	var locker: Vector3 = HomeBase.STATIONS["locker"]["at"]
	check(not base.in_armory(locker) and absf(locker.x + base.room_size.x * 0.5) < 1.5
			and absf(locker.z) < base.armory_opening * 0.5 + 2.0, "the locker stands beside the way into the armory")
	check(base.has_node("ArmorySign") and base.has_node("ArmorySill"), "a sign over the way in names the armory")
	# Signage: nothing mirrored from behind, names only up close, one title each.
	var mirrored := 0
	var bench_titles := 0
	for node in base.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		if label.double_sided and label.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
			mirrored += 1
		if label.text == base.bench_name().to_upper():
			bench_titles += 1
	check(mirrored == 0, "no wall label can be read mirrored from behind (%d can)" % mirrored)
	check(bench_titles == 1 and not base.has_node("Displays/Sign_bay") and not base.has_node("Displays/Sign_gunsmith"),
			"the bench and the garage carry one title each, not a second section sign")
	var plates_near := true
	for display in base.displays:
		var plate := display.get_node("Plate") as Label3D
		plates_near = plates_near and plate.visibility_range_end > 0.0 and plate.visibility_range_end <= 6.0
	check(plates_near, "item names show only from close up")
	# The way in is open: walk from the room to the rack.
	var walker := base.player
	var was := walker.global_position
	walker.global_position = base.to_global(Vector3(-9.0, 0.1, -2.5))
	walker.velocity = Vector3.ZERO
	await frames(2)
	walker.cmd.yaw = PI / 2.0
	walker.cmd.move = Vector2(0, 1)
	await frames(90)
	walker.cmd.move = Vector2.ZERO
	check(base.in_armory(base.to_local(walker.global_position)), "you can walk from the room into the armory")
	walker.global_position = was
	walker.velocity = Vector3.ZERO
	await frames(2)


## Your own base dresses you in your loadout the moment you change it, with
## no bay to walk to (Caleb's call), and a mirror on the wall shows it.
func _test_suit_up(base: HomeBase) -> void:
	print("Home base: your loadout is on you, and the wall mirror")
	var mirror_at := HomeBase.MIRROR_AT
	var front := base.room_size.z * 0.5
	check(base.wall_mirror != null and base.wall_mirror.wall_mounted and base.wall_mirror.is_inside_tree()
			and base.inside(Vector3(mirror_at.x, 0, mirror_at.z)) and absf(mirror_at.z - front) < 0.3,
			"every base has a mirror on its front wall")
	check(base.wall_mirror != null and base.wall_mirror.global_basis.z.dot(Vector3(0, 0, -1)) > 0.99,
			"its glass faces into the room")
	check(not HomeBase.STATIONS.has("launch") and not HomeBase.STATIONS.has("arena") and base.bulkhead("teleporter") == null
			and not BaseUpgrades.has_upgrade("teleporter"),
			"no launch pad, arena gate or teleporter clutters the base: you leave through a portal from the watch")
	# One deploy area along the front wall, beside the exit, so the middle of
	# the room is clear; the shelves and the gear bays line the other walls.
	var in_deploy := func(at: Vector3) -> bool:
		return at.x >= HomeBase.DEPLOY_FROM_X and at.x <= HomeBase.DEPLOY_TO_X and at.z > front - HomeBase.DEPLOY_DEPTH
	check(in_deploy.call(mirror_at) and base.has_node("DeploySign"), "the mirror stands in the deploy area by the front wall")
	var shelved := true
	for kind: String in HomeBase.STORAGE_ROWS:
		for i in int(BaseLayout.KINDS[kind]["spots"]):
			var at := base.spot_transform(kind, i).origin
			shelved = shelved and base.inside(at) and at.z > front - 1.0 and at.x < -1.5
	check(shelved, "supplies, chips and trophies sit on the storage wall left of the door")
	var stands_back := true
	for kind: String in ["armor_stand", "rig_stand"]:
		for i in int(BaseLayout.KINDS[kind]["spots"]):
			stands_back = stands_back and base.spot_transform(kind, i).origin.z < -front + 1.5
	check(stands_back, "armor and rig stands stand in the gear bays along the back wall")
	check(base.door.get_child_count() > 4 and base.has_node("ScoreBoard/RangeBoard"),
			"the exit is a framed door and the range's score is on a board in the room")
	check(not base.has_node("SuitUpBay"), "there is no suit-up bay to walk to")
	var kit := base.suit_kit()
	check(base.loadout.get("primary", "") in kit and kit.size() == base.loadout.keys().filter(func(slot: String) -> bool:
				return not ItemDB.has_tag(base.loadout[slot], "vehicle")).size()
			and not kit.any(func(id: String) -> bool: return ItemDB.has_tag(id, "vehicle")),
			"the kit is your loadout and nothing else, empty slots bare, with vehicles left parked (%s)" % [kit])
	var worn := base.player
	var carried: Array[String] = []
	for weapon in worn.weapons:
		carried.append(weapon.item_id)
	check(base.suited and base.loadout.get("primary", "") in carried and worn.gear_items.size() >= kit.size() - 1,
			"you are already wearing your loadout in your base (%s)" % [carried])
	check(worn.weapons_locked, "weapons locked: nobody fights at home")
	# Change the loadout where you stand: it goes straight on, there, on the
	# same body (a new one stopped you dead: the stutter on every equip).
	worn.position = Vector3(-2.0, 0.1, 1.5)
	worn.cmd.yaw = 1.1
	worn.velocity = Vector3(3.0, 0.0, 1.0)
	var kept := base.loadout.duplicate()
	var kept_stash := base.stash.duplicate()
	var changed := base.loadout.duplicate()
	changed["primary"] = "dmr_longshot"
	var kept_weapons: Array[Weapon] = []
	for weapon in worn.weapons:
		if weapon.item_id != kept.get("primary", ""):
			kept_weapons.append(weapon)
	var kept_displays := {}
	for display in base.displays:
		if display.kind not in ["rack_guns", "bench"]:
			kept_displays[display] = true
	var replaced := []
	base.player_replaced.connect(func(actor: Actor) -> void: replaced.append(actor), CONNECT_ONE_SHOT)
	base.show_gear(base.stash + ["dmr_longshot"], changed)
	base.suit_up()
	var moving_on := worn.velocity
	await frames(3)
	var dressed := base.player
	check(replaced.is_empty() and dressed == worn and dressed.weapons.any(func(w: Weapon) -> bool: return w.item_id == "dmr_longshot")
			and not dressed.weapons.any(func(w: Weapon) -> bool: return w.item_id == kept.get("primary", "")),
			"equipping something puts it on you at once, on the same body")
	check(kept_weapons.all(func(w: Weapon) -> bool: return is_instance_valid(w) and w in dressed.weapons),
			"what you did not change stays on you as it was, model and all")
	check(dressed.position.distance_to(Vector3(-2.0, 0.1, 1.5)) < 0.3 and absf(dressed.cmd.yaw - 1.1) < 0.01
			and moving_on == Vector3(3.0, 0.0, 1.0),
			"right where you stand, facing the same way, still moving (%s)" % moving_on)
	check(dressed.weapons_locked and dressed.gear_items.has("dmr_longshot") and not dressed.gear_items.has(kept.get("primary", "")),
			"still locked, and the worn gear list follows the swap (%s)" % [dressed.gear_items])
	var still_shown := 0
	for display in base.displays:
		if kept_displays.has(display):
			still_shown += 1
	check(still_shown > 0 and still_shown >= kept_displays.size() - 2,
			"the room keeps the displays that did not change (%d of %d)" % [still_shown, kept_displays.size()])
	var names_unique := true
	var seen := {}
	for display in base.displays:
		names_unique = names_unique and not seen.has(display.name) and display.name == "%s_%d" % [display.kind, display.index]
		seen[display.name] = true
	check(names_unique, "every display keeps its plain name")
	base.show_gear(base.stash, changed)
	await frames(2)
	check(replaced.is_empty() and base.player == dressed, "showing the same loadout again changes nothing")
	for c in base.player_replaced.get_connections():
		if c.flags & CONNECT_ONE_SHOT:
			base.player_replaced.disconnect(c.callable)
	base.show_gear(kept_stash, kept)
	await frames(3)
	await _test_garage_and_range(base)
	var visitor := HomeBase.new()
	visitor.read_only = true
	visitor.show_gear(["rifle_carbine"], {"primary": "rifle_carbine"})
	add_child(visitor)
	await frames(2)
	var guest := visitor.player
	visitor.show_gear(["rifle_carbine", "dmr_longshot"], {"primary": "dmr_longshot"})
	await frames(2)
	check(visitor.player == guest and not visitor.suited and guest.weapons.is_empty(),
			"in someone else's base you stay as you came: their gear never goes on you")
	check(visitor.wall_mirror != null, "their base has a mirror too")
	visitor.queue_free()
	await frames(2)


## Bikes park in the garage off the right wall; behind the back wall the
## firing range frees a suited player's weapons and scores what they hit.
func _test_garage_and_range(base: HomeBase) -> void:
	print("Home base garage and firing range")
	var parked := true
	for i in int(BaseLayout.KINDS["bay"]["spots"]):
		parked = parked and base.in_garage(base.spot_transform("bay", i).origin)
	check(parked and base.has_node("GarageSign"), "every garage bay is in the garage off the room")
	var clear := true
	for id: String in HomeBase.STATIONS:
		var at: Vector3 = HomeBase.STATIONS[id]["at"]
		clear = clear and base.inside(at) and not base.in_garage(at) and not base.in_armory(at) and not base.in_range(at)
	check(clear, "the consoles stand in the main room, clear of the garage, armory and range")
	var all_on_range := true
	for target in base.targets:
		all_on_range = all_on_range and base.in_range(target.home)
	check(base.targets.size() >= 6 and all_on_range, "the range has targets down its lane (%d)" % base.targets.size())
	var kinds := {}
	for target in base.targets:
		kinds[target.kind] = true
	check(kinds.has("plate") and kinds.has("slider") and kinds.has("drone"), "standing, sliding and flying targets")
	check(base.firing_line >= 6.0 and base.range_size.z >= 45.0 and base.range_size.x >= 10.0,
			"the range is wide and long, with a clear lobby between the door and the firing line")
	var p := base.player
	check(p.weapons_locked, "weapons stay locked in the main room")
	# Walk through the door in the back wall.
	p.global_position = base.to_global(Vector3(0, 0.1, -6.5))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.move = Vector2(0, 1)
	await frames(60)
	p.cmd.move = Vector2.ZERO
	await frames(2)
	check(base.in_range(base.to_local(p.global_position)), "you can walk through the back wall into the range")
	check(not p.weapons_locked, "past the line your weapons are free")
	var gun := p.get_active_weapon() as Gun
	check(gun != null and gun.reserve_ammo >= gun.mag_size * 4, "and never run dry")
	# Shoot the nearest plate.
	var plate: HomeBase.RangeTarget = base.targets[0]
	var line_z := -base.room_size.z * 0.5 - base.firing_line
	p.global_position = base.to_global(Vector3(plate.home.x, 0.1, line_z - 0.8))
	p.velocity = Vector3.ZERO
	await frames(2)
	var eye := p.global_position + Vector3(0, p.eye_height, 0)
	var dir := (plate.to_global(plate.centre) - eye).normalized()
	p.cmd.yaw = atan2(-dir.x, -dir.z)
	p.cmd.pitch = asin(dir.y)
	p.cmd.aim_dir = dir
	await frames(10)
	var shots_before := base.range_shots
	for i in 3:
		p.cmd.primary_pressed = true
		p.cmd.primary = true
		await frames(1)
		p.cmd.primary_pressed = false
		p.cmd.primary = false
		await frames(20)
	check(base.range_shots > shots_before and base.range_hits > 0 and plate.hits > 0,
			"shots on the range are counted and hits on a plate score (%d shots, %d hits)" % [base.range_shots, base.range_hits])
	check("HITS" in base.range_board.text and base.range_last != "", "the board over the lane keeps score")
	# Back into the room: locked again.
	p.global_position = base.to_global(Vector3(0, 0.1, 2.0))
	p.velocity = Vector3.ZERO
	await frames(3)
	check(p.weapons_locked, "weapons lock again back in the room")


## `Loadout.refit` dresses an actor in place (the home base's equip, which
## used to build a new actor and stuttered). Whatever it is changed to, it
## must end up wearing exactly what a fresh `Loadout.equip` would.
func _test_refit() -> void:
	print("Loadout refit: changing gear in place")
	var kits: Array = [
		["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light"],
		["rifle_carbine", "optic_reflex", "muzzle_compensator", "blade_scrap", "pistol_service", "boots_thruster", "frame_bulwark", "helm_spotter", "chip_blink", "artifact_cloak"],
		["rifle_carbine", "optic_scope", "blade_arc", "jetpack_mk1", "frame_bulwark", "helm_warden", "chip_pulse"],
		["smg_stinger", "pistol_machine", "wings_glide", "frame_trooper"],
		[],
		["dmr_longshot", "optic_longscope", "spear_lancer", "jetpack_mk1", "frame_trooper", "helm_ember", "artifact_rewind"],
	]
	var worn := Actor.new()
	add_child(worn)
	var all_match := true
	var why := ""
	var kept_blade: Weapon = null
	for i in kits.size():
		var kit: Array = kits[i]
		Loadout.refit(worn, kit)
		var fresh := Actor.new()
		add_child(fresh)
		Loadout.equip(fresh, kit)
		var a := _refit_summary(worn)
		var b := _refit_summary(fresh)
		if a != b:
			all_match = false
			why = "kit %d: %s vs %s" % [i, a, b]
		fresh.free()
		if i == 1:
			kept_blade = worn.weapons.filter(func(w: Weapon) -> bool: return w.item_id == "blade_scrap")[0]
		if i == 2:
			check(not is_instance_valid(kept_blade) or kept_blade.is_queued_for_deletion(),
					"a weapon taken off is freed")
	check(all_match, "after every change the actor wears exactly what a fresh equip would %s" % why)
	Loadout.refit(worn, kits[1])
	var blade: Weapon = worn.weapons.filter(func(w: Weapon) -> bool: return w.item_id == "blade_scrap")[0]
	var gun: Weapon = worn.weapons.filter(func(w: Weapon) -> bool: return w.item_id == "rifle_carbine")[0]
	worn.active_weapon_index = worn.weapons.find(blade)
	var changed: Array = kits[1].duplicate()
	changed.erase("optic_reflex")
	changed.erase("chip_blink")
	changed.append("frame_trooper")
	changed.erase("frame_bulwark")
	Loadout.refit(worn, changed)
	check(blade in worn.weapons and worn.get_active_weapon() == blade,
			"a weapon you keep keeps its node, and stays in hand")
	check(gun not in worn.weapons and worn.weapons.any(func(w: Weapon) -> bool: return w.item_id == "rifle_carbine"),
			"a primary whose attachments change is built again with them")
	worn.free()


func _refit_summary(actor: Actor) -> Dictionary:
	var gear := actor.gear_items.duplicate()
	gear.sort()
	var guns := []
	for weapon in actor.weapons:
		var gun := weapon as Gun
		guns.append([weapon.item_id, gun.mag_size if gun else 0, snappedf(gun.spread_deg, 0.001) if gun else 0.0,
				gun.ads_zoom if gun else 0.0, gun.attachments.duplicate() if gun else []])
	return {"gear": gear, "weapons": guns, "walk": snappedf(actor.walk_speed, 0.001), "sprint": snappedf(actor.sprint_speed, 0.001),
			"rig": [actor.flight.enabled, actor.flight.item_id, snappedf(actor.flight.heat_per_sec, 0.001),
				snappedf(actor.flight.glide_heat, 0.001), snappedf(actor.flight.burst_heat, 0.001), actor.flight.heavy_lift],
			"armor": [actor.frame_id, actor.health.max_armor, actor.health.armor], "heat": snappedf(actor.heat_signature, 0.001),
			"helmet": [actor.visor.enabled, actor.visor.item_id, actor.visor.mode],
			"chip": [actor.ability.enabled, actor.ability.item_id], "artifact": [actor.artifact.enabled, actor.artifact.item_id, actor.artifact.uses_left]}


func _test_home_base() -> void:
	print("Home base layout")
	check(BaseLayout.kind_for("dmr_longshot") == "rack_guns" and BaseLayout.kind_for("hammer_breaker") == "rack_melee"
			and BaseLayout.kind_for("pistol_machine") == "rack_sidearms" and BaseLayout.kind_for("power_rail_lance") == "rack_guns"
			and BaseLayout.kind_for("frame_bulwark") == "armor_stand" and BaseLayout.kind_for("wings_glide") == "rig_stand"
			and BaseLayout.kind_for("chip_blink") == "chip_case" and BaseLayout.kind_for("bike_raider") == "bay"
			and BaseLayout.kind_for("medkit") == "supplies" and BaseLayout.kind_for("lattice_shard") == "trophy",
			"tags decide where an item is shown")
	check(BaseLayout.slot_for("rifle_carbine") == "primary" and BaseLayout.slot_for("bike_scrapper") == "vehicle"
			and BaseLayout.slot_for("scrap_metal") == "", "gear knows its loadout slot, loot has none")
	var stash: Array[String] = ["rifle_carbine", "dmr_longshot", "rifle_carbine", "blade_arc", "frame_trooper",
			"bike_scrapper", "bike_scrapper", "bike_raider", "medkit", "medkit", "medkit", "scrap_metal",
			"lattice_shard", "chip_blink", "jetpack_mk2", "no_such_item"]
	# The finished base: `_test_base_upgrades` covers the starter bunker.
	var full := BaseUpgrades.full()
	var plan := BaseLayout.plan(stash, {"primary": "rifle_carbine", "vehicle": "bike_scrapper"}, full)
	var by_kind := {}
	for entry in plan:
		if not by_kind.has(entry["kind"]):
			by_kind[entry["kind"]] = []
		by_kind[entry["kind"]].append(entry)
	var guns: Array = by_kind.get("rack_guns", [])
	check(guns.size() == 2 and guns[0]["id"] == "dmr_longshot" and guns[0]["index"] == 0
			and guns[1]["id"] == "rifle_carbine", "the most valuable gun gets the first spot")
	check(guns[1]["count"] == 2 and guns[1]["equipped"] and not guns[0]["equipped"],
			"copies share a spot with a count, and the equipped gun is marked")
	var bays: Array = by_kind.get("bay", [])
	check(bays.size() == 3 and bays[0]["id"] == "bike_raider", "every bike you own is parked")
	check(bays.filter(func(e: Dictionary) -> bool: return e["equipped"]).size() == 1,
			"only one of two identical bikes is marked as equipped")
	check(by_kind.get("trophy", []).size() == 2 and by_kind["trophy"][0]["id"] == "lattice_shard"
			and by_kind.get("supplies", []).size() == 1 and by_kind["supplies"][0]["count"] == 3,
			"loot goes on the trophy shelf and medkits with the supplies")
	check(plan.filter(func(e: Dictionary) -> bool: return e["id"] == "no_such_item").is_empty(),
			"unknown items are never shown")
	check(BaseLayout.plan([], {}, full).is_empty() and BaseLayout.stored_away(stash, full).is_empty(),
			"an empty stash is an empty base, and nothing is stored away while it fits")
	var many: Array[String] = []
	for i in 6:
		many.append("bike_scrapper")
	check(BaseLayout.plan(many, {}, full).size() == 4 and BaseLayout.stored_away(many, full) == {"bay": 2},
			"a full garage keeps the rest in storage")

	print("Home base room")
	var base := HomeBase.new()
	base.show_gear(stash, {"primary": "rifle_carbine"}, full)
	add_child(base)
	await frames(30)
	check(base.displays.size() == BaseLayout.plan(StashRules.equippable(stash), {"primary": "rifle_carbine"}, full).size(),
			"the room builds one display per planned spot, the free scrap pieces included")
	check(base.player != null and base.player.is_on_floor() and base.suited
			and base.player.weapons.any(func(w: Weapon) -> bool: return w.item_id == "rifle_carbine"),
			"you stand in your base already wearing your loadout")
	var start := base.player.global_position
	base.player.cmd.move = Vector2(0, 1)
	await frames(30)
	base.player.cmd.move = Vector2.ZERO
	check(base.player.global_position.distance_to(start) > 1.5, "you can walk around it")
	var spots := {}
	var apart := true
	for display in base.displays:
		var key := "%s/%d" % [display.kind, display.index]
		apart = apart and not spots.has(key) and base.inside(display.position)
		spots[key] = true
	check(apart, "every display has its own spot inside the room")
	await _test_armory(base)
	var asked := []
	base.equip_requested.connect(func(slot: String, id: String) -> void: asked.append([slot, id]))
	var dmr := base.display_for("dmr_longshot")
	_face_display(base.player, dmr)
	await frames(2)
	# Aim again from where the feet settled: the eye height decides which row
	# of the rack the look lands on.
	_face_display(base.player, dmr)
	check(base.player.find_interactable() == dmr and dmr.get_prompt() == "[F] Equip Longshot DMR",
			"looking at a gun on the rack offers to equip it")
	await _use(base.player)
	check(asked == [["primary", "dmr_longshot"]], "using it asks for that gun in the primary slot")
	var carbine := base.display_for("rifle_carbine")
	check(carbine.equipped and carbine.has_node("EquippedMark") and not dmr.has_node("EquippedMark"),
			"equipped gear is marked on its display")
	_face_display(base.player, carbine)
	await frames(2)
	await _use(base.player)
	check(asked.size() == 2 and asked[1] == ["primary", ""], "using equipped gear asks to take it off")
	var shard := base.display_for("lattice_shard")
	_face_display(base.player, shard)
	await frames(2)
	await _use(base.player)
	check(base.player.find_interactable() == shard and shard.get_prompt() == "Lattice Shard" and asked.size() == 2,
			"loot is only for looking at")
	var hud = BaseHudScript.new()
	hud.setup(base)
	base.add_child(hud)
	await frames(2)
	var lines: Array[String] = hud.describe(shard)
	check(lines[0] == "Lattice Shard" and "Relic" in lines[1], "the overlay names what you look at and its rarity")
	check(hud.tag.visible and hud.tag.text == lines[1] and hud.tag.global_position.distance_to(shard.global_position) < 2.0,
			"what it is shows on a tag over the gear itself, not on the screen")
	# Riding, F gets you off, so the vehicle under you is not offered
	# (playtest: "Warden Rover (ridden)" stayed on the screen in the base).
	var stood_at := base.player.global_position
	var ride = VehicleScript.new()
	ride.setup("rover_warden")
	ride.local_only = true
	base.add_child(ride)
	ride.global_position = stood_at + Vector3(0, 0.3, 0)
	await frames(2)
	check(ride.mount(base.player), "you can climb on a vehicle in the base")
	var aim_was := base.player.cmd.aim_dir
	base.player.cmd.aim_dir = Vector3(0.0, -1.0, -0.2)
	await frames(3)
	check(base.player.find_interactable() != null and hud.get("_prompt").text == "",
			"riding in the base, the vehicle under you is not offered on the screen")
	base.player.cmd.aim_dir = aim_was
	ride.dismount()
	ride.queue_free()
	base.player.global_position = stood_at
	await frames(2)
	# The watch works at home as in a raid (playtest: X half-raised the arm
	# with no card): it rises with the key and its card has every icon.
	check(hud.wrist != null and not hud.wrist.raised, "the base wears the watch, lowered")
	var watch_keys := PlayerController.new()
	watch_keys.setup(base.player)
	base.add_child(watch_keys)
	watch_keys.wrist_raised = true
	await frames(30)
	var watch_icons: Array = hud.wrist.card.slots.map(func(slot: Dictionary) -> String: return slot.id)
	check(hud.wrist.raised and hud.wrist.raise_amount >= 1.0 and watch_icons == Hud.Wrist.SLOTS
			and base.player.cmd.watch_up, "X raises the watch in the base and its card opens: %s" % ", ".join(watch_icons))
	var home := Hud.base_watch_slots("Home base", {"vehicle": "bike_raider"})
	var home_vehicle: Dictionary = home[Hud.Wrist.SLOTS.find("vehicle")]
	check(home[Hud.Wrist.SLOTS.find("map")].detail == "Home base" and home_vehicle.detail == ItemDB.item_name("bike_raider")
			and not home_vehicle.empty and Hud.base_watch_slots("Home base", {})[Hud.Wrist.SLOTS.find("vehicle")].empty,
			"at home the card says where you are and which vehicle you deploy with")
	watch_keys.wrist_raised = false
	await frames(30)
	check(hud.wrist.raise_amount <= 0.0 and not base.player.cmd.watch_up, "X lowers it again")
	# The raised wrist comes up into the line of sight from the eyes, so the
	# card over it is in view (playtest: it stayed under the view in first
	# person), wherever you are looking.
	var arm = preload("res://core/visual/weapon_arm.gd").new()
	arm.actor = base.player
	var in_view := true
	for look_pitch: float in [-0.4, 0.0, 0.4]:
		base.player.cmd.pitch = look_pitch
		var aim_dir: Vector3 = base.player.global_basis * Basis(Vector3.RIGHT, look_pitch) * Vector3.FORWARD
		var to_wrist: Vector3 = arm.watch_point() - base.player.get_eye_position()
		in_view = in_view and rad_to_deg(aim_dir.angle_to(to_wrist)) < 30.0 and to_wrist.length() < 0.6
	base.player.cmd.pitch = 0.0
	arm.free()
	check(in_view, "the raised watch comes up in front of the eyes, wherever you look")
	# A change of gear dresses the same body, and the watch on it keeps
	# working (playtest: X did nothing after suiting up).
	watch_keys.queue_free()
	await frames(2)
	var regeared := base.loadout.duplicate()
	regeared["primary"] = "dmr_longshot" if base.loadout.get("primary", "") != "dmr_longshot" else "rifle_carbine"
	base.show_gear(base.stash + [regeared.primary], regeared)
	await frames(3)
	var suited_keys := PlayerController.new()
	suited_keys.setup(base.player)
	base.add_child(suited_keys)
	suited_keys.wrist_raised = true
	await frames(30)
	check(is_instance_valid(hud.wrist) and hud.wrist.get_parent() == base.player and hud.wrist.raise_amount >= 1.0
			and hud.wrist.card.slots.size() == Hud.Wrist.SLOTS.size(), "the watch still raises after suiting up")
	suited_keys.queue_free()
	await frames(2)
	check(base.get_node("Banner/Title").text == "HOME BASE" and "press F" in base.banner_text(),
			"the base's name and how it works hang on a banner in the room")
	for kind: String in BaseLayout.KINDS:
		var bike_or_gear: Array = by_kind.get(kind, [])
		if bike_or_gear.is_empty():
			continue
		var shown := base.display_for(bike_or_gear[0]["id"])
		_face_display(base.player, shown)
		await frames(2)
		check(base.player.find_interactable() == shown, "a %s display can be walked up to and looked at" % kind)
	base.show_gear(["blade_arc"], {})
	await frames(2)
	check(base.displays.size() == 1 + StashRules.free_items().size() and base.display_for("dmr_longshot") == null,
			"gear that leaves the stash leaves the base")
	var left := [0]
	base.leave_requested.connect(func() -> void: left[0] += 1)
	_face_display(base.player, base.door)
	await frames(2)
	await _use(base.player)
	check(left[0] == 1, "the door asks to go back to the hub")
	base.read_only = true
	base.show_gear(["dmr_longshot"], {"primary": "dmr_longshot"})
	await frames(2)
	_face_display(base.player, base.displays[0])
	await frames(2)
	await _use(base.player)
	check(asked.size() == 2 and base.displays[0].get_prompt() == "Longshot DMR (equipped)",
			"a base you are visiting cannot be changed")
	base.queue_free()
	await frames(2)

	print("Home base from the hub")
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "dmr_longshot", "frame_bulwark", "bike_scrapper", "alloy_ingot"])
	Profile.equip("primary", "rifle_carbine")
	Profile.base_upgrades = BaseUpgrades.full()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(2)
	await frames(20)
	check(main.base != null and not main.hub.visible and main.raid == null, "you start in your home base")
	check(main.controller != null and main.controller.camera.current and main.base_hud != null,
			"the base has a camera and an overlay")
	check(main.base.displays.size() == 5 + StashRules.free_items().size() and main.base.display_for("rifle_carbine").equipped,
			"it shows your stash and what you have equipped")
	# Real input: look at the DMR and press F.
	var target: Node3D = main.base.display_for("dmr_longshot")
	_face_display(main.base.player, target)
	main.controller.yaw = main.base.player.cmd.yaw
	main.controller.pitch = main.base.player.cmd.pitch
	await frames(3)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(2)
	check(Profile.equipped("primary") == "dmr_longshot", "pressing E on a rack changes your loadout")
	check(main.base.display_for("dmr_longshot").equipped and not main.base.display_for("rifle_carbine").equipped,
			"the displays show the change")
	main.base.equip_requested.emit("vehicle", "bike_scrapper")
	main.base.equip_requested.emit("primary", "frame_bulwark")
	check(Profile.equipped("vehicle") == "bike_scrapper" and Profile.equipped("primary") == "dmr_longshot",
			"a parked bike can be picked, and gear cannot go in the wrong slot")
	# No bay to walk to: what you picked is already on you, and the controls
	# and camera went with you into the new body.
	await frames(3)
	var suited: Actor = main.base.player
	check(main.base.suited and suited.weapons.any(func(w: Weapon) -> bool: return w.item_id == "dmr_longshot"),
			"the DMR you picked off the rack is in your hands at once")
	check(main.controller.actor == suited and main.controller.camera.current,
			"the controls and camera follow you into your new gear")
	check(main.base.wall_mirror.viewer == suited and main.base.wall_mirror.eye == main.controller.camera,
			"the wall mirror shows you")
	check(main.hub.equipped("primary") == "dmr_longshot", "the locker shows the loadout chosen in the base")
	# Every station opens its screen over the room, and Esc steps away.
	for id: String in HomeBase.STATIONS:
		if id == "arena":
			continue  # A way out, not a screen: the arena tests use it.
		var console: HomeBase.Station = main.base.station(id)
		_face_display(main.base.player, console)
		main.controller.yaw = main.base.player.cmd.yaw
		main.controller.pitch = main.base.player.cmd.pitch
		await frames(2)
		check(main.base.player.find_interactable() == console and console.get_prompt().begins_with("[F]"),
				"the %s can be walked up to and used" % id)
		console.interact(main.base.player)
		await frames(2)
		check(main.hub.visible and main.hub.station == id and main.controller.input_blocked
				and not main.base_hud.visible, "the %s opens its screen" % id)
		check(main.station_screen != null and main.station_screen.get_parent() == console.screen
				and main.station_screen.focused and main.get_viewport().get_camera_3d() != main.controller.camera
				and not main._travel.visible, "the %s's screen comes up on the console and the view moves in to it" % id)
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		main.hub._unhandled_input(esc)
		await frames(2)
		check(not main.hub.visible and not main.controller.input_blocked and main.base_hud.visible
				and main.station_screen == null and main.get_viewport().get_camera_3d() == main.controller.camera,
				"Esc steps away from the %s and gives the view back" % id)
	# The screen is used by clicking on it in the world: a click where the
	# records board's "Step away" button shows goes to that button.
	main.open_station("records")
	await get_tree().create_timer(0.6).timeout
	var live: WorldScreen = main.station_screen
	var cam := main.get_viewport().get_camera_3d()
	var mid := cam.unproject_position(live.global_position)
	check(live.screen_point(cam.project_ray_origin(mid), cam.project_ray_normal(mid)).distance_to(
			Vector2(main.hub_screen.size) * 0.5) < 2.0, "the middle of the view is the middle of the screen")
	var step_away: Button = main.hub._close_button
	var spot := step_away.get_global_rect().get_center()
	var on_glass := Vector3((spot.x / main.hub_screen.size.x - 0.5) * live.size.x,
			(0.5 - spot.y / main.hub_screen.size.y) * live.size.y, 0.0)
	var at := cam.unproject_position(live.global_transform * on_glass)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		main.get_viewport().push_input(click)
		await frames(1)
	await frames(2)
	check(not main.hub.visible and main.station_screen == null and not main.controller.input_blocked,
			"clicking a button on the screen in the world presses it")
	main.open_station("wardrobe")
	await frames(2)
	check(main.hub.character.is_customizing(), "the wardrobe opens the customizer")
	main.hub.character.hide_customizer()
	await frames(2)
	check(not main.hub.visible and not main.controller.input_blocked, "finishing in the customizer steps away")
	main.open_station("mastery")
	check(main.hub._sections["mastery"].visible and not main.hub._sections["loadout"].visible,
			"a station shows only its own part of the old menu")
	main.hub.close()
	check(main.base.door.get_prompt().contains(Worlds.social_world().display_name),
			"the door of your own base says it leads out to the plaza")
	check(not HomeBase.STATIONS.has("uplink") and not Hub.STATIONS.has("uplink") and main.base.station("uplink") == null
			and not main.hub._sections.has("online"), "the base has no uplink console: going online is on the phone")
	main.phone.open("servers")
	await frames(1)
	var address_edit: LineEdit = main.phone._address_edit
	check(main.phone.app == "servers" and address_edit != null and address_edit.text == Profile.last_server
			and main.phone._body.find_child("NameEdit", true, false) != null
			and main.phone._body.find_children("*", "OptionButton", true, false).is_empty(),
			"the phone's Servers app takes your name and a server's address, and never asks for a map")
	main.phone.join_server("   ")
	await frames(1)
	check(main.net == null and main.base != null and main.phone.link_status == "Type the server's address first.",
			"joining with no address asks for one and stays home")
	main._leave_from_phone()
	check(main.net == null and main.base != null, "leaving with no server does nothing")
	main.phone.set_link_status("")
	main.phone.close()
	var door_path := "user://test_door_%d.json" % Time.get_ticks_usec()
	var real_path := Profile.save_path
	Profile.save_path = door_path
	Profile.persist = true
	Profile.home_server = "10.0.0.7:4000"
	Profile.save()
	Profile.home_server = ""
	Profile.load_profile()
	check(Profile.home_server == "10.0.0.7:4000", "the profile remembers the server your door leads to")
	Profile.persist = false
	Profile.save_path = real_path
	Profile.home_server = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(door_path))
	# A server's stash is shown while in its lobby, and the local one is left alone.
	main.hub.update_account({"name": "Vex", "stash": ["blade_arc", "bike_raider"], "loadout": {"melee": "blade_arc"},
			"mastery": {}, "raids_played": 0, "raids_extracted": 0, "kills": 0})
	main.enter_base()
	await frames(5)
	check(main.base.displays.size() == BaseLayout.plan(StashRules.equippable(["blade_arc", "bike_raider"]),
				{"melee": "blade_arc"}, main.base.upgrades).size()
			and main.base.display_for("blade_arc").equipped and main.base.display_for("rifle_scrap") != null,
			"in a lobby the base shows the stash that server keeps")
	main.base.equip_requested.emit("vehicle", "bike_raider")
	check(Profile.equipped("vehicle") == "bike_scrapper", "online changes go to the server, not the local profile")
	main._on_online_account_changed({"name": "Vex", "stash": ["blade_arc", "bike_raider"],
			"loadout": {"melee": "blade_arc", "vehicle": "bike_raider"}, "mastery": {},
			"raids_played": 0, "raids_extracted": 0, "kills": 0})
	await frames(2)
	check(main.base.display_for("bike_raider").equipped, "the base updates when the server answers")
	main.leave_base()
	main.hub.leave_lobby()
	await frames(3)
	main.visit_base("Kestrel", ["lattice_shard", "hammer_breaker"], {"melee": "hammer_breaker"}, ["trophy_hall"])
	await frames(5)
	check(main.base != null and main.base.read_only and main.base.owner_name == "Kestrel"
			and main.base.displays.size() == 2 and main.base.upgrades == ["trophy_hall"],
			"someone else's base can be visited, with the upgrades they have")
	var own_melee := Profile.equipped("melee")
	main.base.displays[0].interact(main.base.player)
	main.base.displays[1].interact(main.base.player)
	check(Profile.equipped("melee") == own_melee, "visiting never changes your own loadout")
	main.base.station("locker").interact(main.base.player)
	check(not main.hub.visible, "another player's stations cannot be used")
	main.base.leave_requested.emit()
	await frames(3)
	check(main.base != null and not main.base.read_only, "the door of a base you visit takes you home")
	main.leave_base()
	await frames(3)
	main.start_raid("ashfront")
	await frames(5)
	check(main.raid != null and main.raid.player.weapons[0].item_id == "dmr_longshot",
			"gear picked in the base is what you deploy with")
	main.raid.player.kill("test")
	await frames(150)
	main.queue_free()
	await frames(2)
	Profile.reset()


# --- Arena ---------------------------------------------------------------------

## Scrip in a dictionary, for arena tests that need several wallets.
class FakeBank:
	extends Arena.Bank

	var money := {}
	var wins := {}
	var losses := {}

	func scrip(key: String) -> int:
		return money.get(key, 0)

	func change(key: String, delta: int) -> bool:
		if scrip(key) + delta < 0:
			return false
		money[key] = scrip(key) + delta
		return true

	func record(key: String, won: bool) -> void:
		var book := wins if won else losses
		book[key] = int(book.get(key, 0)) + 1


## A server arena with quick bouts and no exhibitions, and `names` in the stands.
func _quick_arena(names: Array) -> Arena:
	var arena := Arena.new()
	add_child(arena)
	arena.call_time = 0.3
	arena.countdown_time = 0.1
	arena.fight_time = 30.0
	arena.result_time = 0.1
	arena.exhibition_delay = -1.0
	arena.tournament_signup_time = 0.2
	var bank := FakeBank.new()
	arena.bank = bank
	arena.start_server(Arena.ArenaVenue.new(), 5)
	for n: String in names:
		var actor := arena.add_player(["blade_scrap", "plate_light", "medkit"], {}, n)
		arena.set_key(actor, n)
		bank.money[n] = 500
	await frames(3)
	return arena


## Waits for the arena to reach `phase` (an Arena.Phase).
func _arena_phase(arena: Arena, p: int, max_frames := 240) -> bool:
	return await _wait_until(func() -> bool: return arena.phase == p, max_frames)


## Plays the bout in the pit to the end: `side` lands hits until the other yields.
func _win_bout(arena: Arena, side: int) -> void:
	await _arena_phase(arena, Arena.Phase.FIGHT)
	var bout := arena.bout
	for i in 50:
		if arena.phase != Arena.Phase.FIGHT:
			break
		Combat.deal(bout.fighters[1 - side], DamageInfo.make(40.0, bout.fighters[side], "blade"))
		await frames(1)
	await _arena_phase(arena, Arena.Phase.IDLE)


## The Pit's floor: cover, tunnels and doors, the rising barriers, the
## ceiling, and bots finding their way round it all.
func _test_arena_floor() -> void:
	print("Arena: the floor, tunnels and rising barriers")
	var V := Arena.ArenaVenue
	check(V.doors_open("fight", 0.0) and V.doors_open("fight", V.DOOR_OPEN_TIME - 0.1)
			and not V.doors_open("fight", V.DOOR_OPEN_TIME + 0.1) and not V.doors_open("countdown", -1.0),
			"the tunnel doors open as the fight starts and close behind the fighters")
	check(V.barrier_raise(0, -1.0) == 1.0 and V.barrier_raise(1, -1.0) == 0.0
			and V.barrier_raise(0, V.BARRIER_PERIOD + V.BARRIER_MOVE) == 0.0
			and V.barrier_raise(1, V.BARRIER_PERIOD + V.BARRIER_MOVE) == 1.0
			and V.barrier_raise(0, V.BARRIER_PERIOD * 2.0 + V.BARRIER_MOVE) == 1.0,
			"the rising barriers take turns, one pair up at a time")
	var mid := V.barrier_raise(1, V.BARRIER_PERIOD + V.BARRIER_MOVE * 0.5)
	check(mid > 0.1 and mid < 0.9, "a barrier rises over a moment, not all at once")
	check(V.in_tunnel(Vector3(-V.GATE_DISTANCE, 0.1, 0)) and not V.in_pit(Vector3(-V.GATE_DISTANCE, 0.1, 0))
			and not V.in_tunnel(Vector3(0, 0.1, V.GATE_DISTANCE)) and V.in_pit(V.entry_point(1))
			and not V.in_tunnel(Vector3(-V.GATE_DISTANCE, V.WALL_HEIGHT, 0)),
			"each tunnel runs under the stands, apart from the floor and the seats over it")

	var arena := await _quick_arena(["ana", "bo"])
	var map := arena.map
	var gates := arena._map_nodes("arena_gate")
	check(gates.size() == 2 and gates.all(func(g: Node3D) -> bool: return V.in_tunnel(g.global_position)),
			"both fighters wait in a tunnel")
	var space := map.get_world_3d().direct_space_state
	var gate_line := PhysicsRayQueryParameters3D.create(V.entry_point(0) + Vector3(0, 1.7, 0),
			V.entry_point(1) + Vector3(0, 1.7, 0), Actor.LAYER_WORLD)
	check(not space.intersect_ray(gate_line).is_empty(), "cover blocks the line from one gate to the other")
	var up := PhysicsRayQueryParameters3D.create(Vector3(3, 2, 3), Vector3(3, 40, 3), Actor.LAYER_WORLD)
	var lid := space.intersect_ray(up)
	check(not lid.is_empty() and absf(lid.position.y - V.CEILING) < 0.2, "a ceiling keeps flight over the floor")
	var meshes := map.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() < 30, "the venue is a handful of meshes, not hundreds of boxes (%d)" % meshes.size())
	var nav: NavigationRegion3D = map.get("nav_region")
	check(nav != null and nav.navigation_mesh != null and nav.navigation_mesh.get_polygon_count() > 10,
			"bots get a navigation mesh round the cover")

	# A practice bout: doors shut while the fighters wait, open for the fight,
	# shut again behind them; the barriers follow the clock.
	var ana: Actor = arena.players[0].actor
	arena.request(ana, "practice", {})
	await _arena_phase(arena, Arena.Phase.COUNTDOWN)
	var door: Node3D = map.get_node("Door0")
	var shut_y := door.position.y
	check(V.in_tunnel(ana.global_position), "a fighter is brought in to their tunnel")
	await _arena_phase(arena, Arena.Phase.FIGHT)
	await frames(2)
	check(door.position.y < shut_y - 2.0, "the door sinks open when the fight starts")
	arena.phase_left = arena.fight_time - V.DOOR_OPEN_TIME - 0.5
	await frames(2)
	check(is_equal_approx(door.position.y, shut_y) and V.in_pit(ana.global_position),
			"once the doors close, a fighter still in the tunnel is put on the floor")
	var barriers := get_tree().get_nodes_in_group("arena_barrier").filter(func(b: Node) -> bool:
		return map.is_ancestor_of(b))
	var heights := barriers.map(func(b: Node3D) -> float: return b.position.y)
	arena.phase_left = arena.fight_time - V.BARRIER_PERIOD - V.BARRIER_MOVE - 0.2
	await frames(2)
	var moved := 0
	for i in barriers.size():
		if absf(barriers[i].position.y - heights[i]) > 1.0:
			moved += 1
	check(barriers.size() == 4 and moved == 4, "every rising barrier changes over when the pairs swap")
	arena.queue_free()
	await frames(2)


func _test_arena() -> void:
	print("Arena: wagers, duels and tournaments")
	var bets := {"cara": [0, 100], "dax": [1, 50], "eve": [0, 50]}
	var paid := Arena.wager_payouts(bets, 0, 0.1)
	# 50 on the losing side, 5 to the house, 45 shared 2:1 by red's backers.
	check(paid.get("cara", 0) == 130 and paid.get("eve", 0) == 65 and not paid.has("dax"),
			"backers of the winner split the losing pool by stake, less the house cut")
	paid = Arena.wager_payouts(bets, -1, 0.1)
	check(paid.cara == 100 and paid.dax == 50 and paid.eve == 50, "a draw refunds every wager")
	paid = Arena.wager_payouts({"cara": [0, 100]}, 1, 0.1)
	check(paid.get("cara", 0) == 100, "with nobody on the other side, the wager comes back")

	var venue := Arena.ArenaVenue.new()
	check(venue.gear_at_risk == false and venue.new_raid() is Arena and Worlds.get_world(venue.id) == null,
			"the arena is a gear-safe venue with its own rules, not a deploy target")
	check(NetSession.world_for("arena") != null and NetSession.world_for("ashfront") != null,
			"online sessions can run the arena or a world")
	var hp := HealthComponent.new()
	hp.min_health = 1.0
	hp.apply_damage(DamageInfo.make(500.0, null, "blade"))
	check(not hp.is_dead and is_equal_approx(hp.health, 1.0), "a floor on health turns a killing blow into a yield")
	hp.free()

	# Solo: you, the stands and bot gladiators.
	Profile.reset()
	var stash_before := Profile.stash.duplicate()
	var arena := Arena.new()
	add_child(arena)
	arena.call_time = 0.3
	arena.countdown_time = 0.1
	arena.result_time = 0.1
	arena.exhibition_delay = -1.0
	arena.start_solo(["rifle_carbine", "blade_scrap", "plate_light", "medkit", "bike_scrapper"])
	await frames(5)
	var me := arena.player
	check(me != null and not Arena.ArenaVenue.in_pit(me.global_position) and me.global_position.y > 2.0,
			"you arrive in the stands")
	check(me.weapons.size() == 2 and "medkit" not in me.gear_items and arena.vehicles.is_empty(),
			"you bring your own weapons, but no healing or vehicles into the arena")
	check(not Combat.deal(me, DamageInfo.make(30.0, null, "bullet")) and is_equal_approx(me.health.health, me.health.max_health),
			"nobody can hurt the crowd")
	me.global_position = Vector3(0, 0.5, 0)
	await frames(2)
	check(not Arena.ArenaVenue.in_pit(me.global_position), "spectators who drop into the pit are put back in the stands")
	arena.ask("bet", {"side": 0, "amount": 10})
	check(Profile.scrip == StashService.Economy.STARTING_SCRIP, "bets are refused when no bout is being called")
	arena.ask("practice")
	check(arena.queue.size() == 1 or arena.bout != null, "you can ask for a practice bout")
	await _arena_phase(arena, Arena.Phase.CALLING, 30)
	var board := arena.view_board()
	check(board.phase == "calling" and board.bout.names[0] == "You" and board.bout.names[1] != "",
			"the bout is called with both fighters' names")
	arena.ask("bet", {"side": 0, "amount": 10})
	check(Profile.scrip == StashService.Economy.STARTING_SCRIP and not arena.bout.bets.has("local"),
			"fighters cannot bet on their own bout")
	await _arena_phase(arena, Arena.Phase.FIGHT)
	var bot: Actor = arena.bout.fighters[1]
	check(Arena.ArenaVenue.in_bounds(me.global_position) and bot != null and bot in arena.bots
			and me.health.min_health > 0.0, "the fighters are in the pit and cannot die")
	check(Combat.deal(bot, DamageInfo.make(5.0, me, "blade")) and not Combat.deal(me, DamageInfo.make(5.0, null, "fall")),
			"only the two fighters can hurt each other")
	Combat.deal(me, DamageInfo.make(5000.0, bot, "blade"))
	check(not me.is_dead and me.health.health <= 1.01, "a beaten fighter yields instead of dying")
	await _arena_phase(arena, Arena.Phase.IDLE)
	await frames(3)
	check(Profile.arena_losses == 1 and Profile.arena_wins == 0, "the bout goes on your arena record")
	check(not Arena.ArenaVenue.in_pit(me.global_position) and is_equal_approx(me.health.health, me.health.max_health)
			and me.health.min_health == 0.0, "both go back to the stands, patched up")
	check(not is_instance_valid(bot) or bot.is_queued_for_deletion() or bot not in arena.bots,
			"the bot gladiator leaves the arena after the bout")
	check(me.weapons.size() == 2 and Profile.stash == stash_before, "nothing was lost and the stash is untouched")

	# An exhibition between two bots, with a wager from the crowd.
	arena.exhibition_delay = 0.1
	await _arena_phase(arena, Arena.Phase.CALLING, 60)
	check(arena.bout != null and arena.bout.kind == "exhibition", "with nothing queued, bot gladiators put on an exhibition")
	arena.ask("bet", {"side": 1, "amount": 50})
	check(Profile.scrip == StashService.Economy.STARTING_SCRIP - 50 and arena.bout.pools[1] == 50,
			"the crowd can bet while a bout is being called")
	arena.ask("bet", {"side": 0, "amount": 50})
	check(arena.bout.pools[0] == 0, "you cannot back both sides")
	arena.exhibition_delay = -1.0
	await _win_bout(arena, 0)
	check(Profile.scrip == StashService.Economy.STARTING_SCRIP, "a wager nobody took the other side of is refunded")
	arena.queue_free()
	await frames(3)
	check(Profile.stash == stash_before, "leaving the arena takes nothing from the stash")
	Profile.reset()

	# From your base: a portal from the watch opens it, with its own overlay.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(2)
	check(main.base.open_portal(Arena.ArenaVenue.ID) == "", "a portal from the base's watch can lead to the arena")
	await frames(int(main.base.portal.unfold_time * 60.0) + 4)
	main.base.player.global_position = main.base.portal.global_position
	await frames(8)
	check(main.raid is Arena and not main.hub.visible and main.base == null
			and main.raid.get_node_or_null("ArenaHud") != null
			and main.controller != null, "walking through it opens the arena")
	var hud: CanvasLayer = main.raid.get_node("ArenaHud")
	await frames(20)
	var faces := get_tree().get_nodes_in_group("arena_board").filter(func(face: Node) -> bool:
		return main.raid.map.is_ancestor_of(face))
	check(faces.size() == Arena.ArenaVenue.BOARD_FACES and faces.all(func(face: Node) -> bool:
			return face.get_children().any(func(c: Node) -> bool: return c is WorldScreen)),
			"the bout is shown on the big board over the pit, on every side")
	var booths := get_tree().get_nodes_in_group("arena_booth").filter(func(b: Node) -> bool:
		return main.raid.map.is_ancestor_of(b))
	check(booths.size() == Arena.ArenaVenue.BOOTHS, "the stands have bookmakers' booths")
	var booth: Node3D = booths[0]
	check(hud.booth_at(main.raid, booth.global_position + Vector3(0.3, 0.1, 0)) == booth
			and hud.booth_at(main.raid, Vector3.ZERO) == null, "a booth is used by standing at it")
	hud.open_booth(booth)
	await frames(3)
	check(hud.booth_open and hud.booth_screen.get_parent() == booth.get_node("Screen")
			and main.controller.input_blocked and main.get_viewport().get_camera_3d() != main.controller.camera
			and not main.hud.visible, "the booth's screen comes up with the view moved in to it")
	check(hud.get("_panel").get_child_count() > 3, "the booth lists what you can do")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	hud.booth_view.push_input(esc, true)
	await frames(3)
	check(not hud.booth_open and not main.controller.input_blocked and main.hud.visible
			and main.get_viewport().get_camera_3d() == main.controller.camera, "Esc steps away from the booth")
	hud.leave_requested.emit()
	await frames(5)
	check(main.raid == null and main.base != null and not main.hub.visible, "leaving the arena takes you home")
	# A gate inside a world (the plaza's) opens the arena from there.
	main.start_raid(Worlds.all()[0].id)
	await frames(5)
	main.open_arena()
	await frames(5)
	check(main.raid is Arena and main.raid.player != null, "the arena can be opened from inside a world")
	main.leave_arena()
	await frames(3)
	main.queue_free()
	await frames(2)
	Profile.reset()

	# A server arena: a staked duel between players, with the crowd betting.
	arena = await _quick_arena(["Ash", "Bex", "Cy", "Dov"])
	var bank: FakeBank = arena.bank
	var ash := arena.players[0].actor
	var bex := arena.players[1].actor
	var cy := arena.players[2].actor
	var dov := arena.players[3].actor
	check(not arena.request(ash, "challenge", {"to": String(bex.name), "stake": 9999}).ok,
			"a stake above the limit is refused")
	check(arena.request(ash, "challenge", {"to": String(bex.name), "stake": 50}).ok, "a player can challenge another")
	var board_b := arena.board_for(bex)
	check(board_b.challenges.size() == 1 and board_b.challenges[0].incoming and board_b.challenges[0].from == "Ash",
			"the challenged player sees it on their board")
	check(not arena.request(cy, "accept", {"from": String(ash.name)}).ok, "nobody else can accept it")
	check(arena.request(bex, "accept", {"from": String(ash.name)}).ok and bank.money.Ash == 450 and bank.money.Bex == 450,
			"accepting puts up both stakes")
	await _arena_phase(arena, Arena.Phase.CALLING, 30)
	check(arena.request(cy, "bet", {"side": 0, "amount": 100}).ok and arena.request(dov, "bet", {"side": 1, "amount": 50}).ok,
			"the crowd bets on both sides")
	check(not arena.request(ash, "bet", {"side": 0, "amount": 10}).ok, "a fighter cannot bet on their own duel")
	check(not arena.request(cy, "bet", {"side": 0, "amount": 1}).ok, "bets below the minimum are refused")
	await _arena_phase(arena, Arena.Phase.FIGHT)
	check(not Combat.deal(cy, DamageInfo.make(10.0, ash, "blade")), "a fighter cannot hurt the crowd")
	await _win_bout(arena, 0)
	check(bank.money.Ash == 550 and bank.money.Bex == 450, "the winner takes both stakes")
	check(bank.money.Cy == 545 and bank.money.Dov == 450, "the winner's backers are paid from the losing pool")
	check(bank.wins.get("Ash", 0) == 1 and bank.losses.get("Bex", 0) == 1, "both fighters' records are kept")
	check(not ash.is_dead and not bex.is_dead and ash.weapons.size() == 1 and bex.weapons.size() == 1,
			"nobody died and nobody lost a weapon")

	# Leaving mid-bout forfeits it.
	arena.request(cy, "challenge", {"to": String(dov.name), "stake": 0})
	arena.request(dov, "accept", {"from": String(cy.name)})
	await _arena_phase(arena, Arena.Phase.FIGHT)
	var summary := [{}]
	arena.bout_finished.connect(func(r: Dictionary) -> void: summary[0] = r, CONNECT_ONE_SHOT)
	arena.remove_player(dov)
	await frames(2)
	check(summary[0].get("winner", "") == "Cy", "a fighter who leaves forfeits the bout")
	await _arena_phase(arena, Arena.Phase.IDLE)

	# A tournament: three players and a bot gladiator in a four-slot bracket.
	for who in [ash, bex, cy]:
		check(arena.request(who, "join_tournament", {}).ok, "%s enters the tournament" % who.display_name)
	check(bank.money.Ash == 525 and arena.tournament.pot == 75, "the entry fee goes into the pot")
	check(not arena.request(ash, "join_tournament", {}).ok, "nobody enters twice")
	var after_fees := bank.money.duplicate()
	var champion := [""]
	for i in 6:
		if arena.tournament == null:
			break
		await _arena_phase(arena, Arena.Phase.FIGHT, 120)
		if arena.bout == null:
			break
		# The player on the red side wins each bout, if there is one.
		var side := 0 if arena.bout.sides[0] is Actor else 1
		if arena.tournament != null and arena.tournament.round > 0:
			champion[0] = arena.bout.names[side]
		await _win_bout(arena, side)
	await frames(5)
	check(arena.tournament == null and arena.last_result.ends_with("is the champion"),
			"the bracket plays out to a champion (%s)" % arena.last_result)
	var champ_key: String = champion[0]
	check(champ_key != "" and bank.money.get(champ_key, 0) == int(after_fees.get(champ_key, 0)) + 75,
			"the champion takes the pot")

	# Shutting the arena down mid-bout hands wagers and stakes back.
	arena.request(ash, "challenge", {"to": String(bex.name), "stake": 20})
	arena.request(bex, "accept", {"from": String(ash.name)})
	await _arena_phase(arena, Arena.Phase.CALLING, 30)
	arena.request(cy, "bet", {"side": 1, "amount": 30})
	var before := [bank.money.Ash + 20, bank.money.Bex + 20, bank.money.Cy + 30]
	arena.queue_free()
	await frames(2)
	check(bank.money.Ash == before[0] and bank.money.Bex == before[1] and bank.money.Cy == before[2],
			"an arena that shuts down refunds open wagers and stakes")


func _test_online_arena() -> void:
	print("Arena: online")
	var service := StashService.new()
	service.persist = false
	var made := service.sign_in("Wren", StashService.new_secret())
	var stash_before: Array = service.snapshot(made.account_id).stash
	check(service.scrip_of("wren") == StashService.Economy.STARTING_SCRIP, "a new account starts with scrip")
	check(not service.change_scrip("wren", -10000) and service.change_scrip("wren", -50)
			and service.scrip_of("wren") == StashService.Economy.STARTING_SCRIP - 50, "scrip never go below zero")
	service.equip("wren", "primary", "rifle_carbine")
	var deployed := service.deploy("wren", Arena.ArenaVenue.new())
	check(deployed.ok and "rifle_carbine" in deployed.kit and service.snapshot("wren").stash == stash_before
			and not service.is_deployed("wren"), "entering the arena hands out the loadout without taking it")

	_wipe_dir(NET_ACCOUNTS)
	var port := 24821
	var pid := _start_server(port, ["--bots", "0"])
	var arena_port := port + 10
	var ash := await _join("Ashe", arena_port)
	var bex := await _join("Brix", arena_port)
	check(ash != null and bex != null and ash.raid is Arena and bex.raid is Arena,
			"players join the server's arena on its own port")
	if ash == null or bex == null:
		OS.kill(pid)
		await _leave(ash)
		await _leave(bex)
		return
	check(not ash.account.get("deployed", true), "nothing left the stash to enter the arena")
	var ash_arena: Arena = ash.raid
	await _wait_until(func() -> bool: return ash_arena.board.get("players", []).size() == 1, 240)
	check(ash_arena.board.get("you", {}).get("scrip", 0) == StashService.Economy.STARTING_SCRIP
			and ash_arena.board.players[0].name == "Brix", "each player gets the board, with their scrip")
	var notices: Array[String] = []
	ash.raid.player.notice.connect(func(text: String) -> void: notices.append(text))
	ash_arena.ask("bet", {"side": 0, "amount": 10})
	await _wait_until(func() -> bool: return not notices.is_empty(), 120)
	check(notices.size() == 1 and notices[0].begins_with("Bets are closed"), "the server refuses a bad request with a notice")
	ash_arena.ask("challenge", {"to": ash_arena.board.players[0].node, "stake": 25})
	var bex_arena: Arena = bex.raid
	await _wait_until(func() -> bool: return not bex_arena.board.get("challenges", []).is_empty(), 240)
	check(not bex_arena.board.get("challenges", []).is_empty(), "the challenge reaches the other player")
	if not bex_arena.board.get("challenges", []).is_empty():
		bex_arena.ask("accept", {"from": bex_arena.board.challenges[0].from_node})
	await _wait_until(func() -> bool: return bex_arena.board.get("phase", "") == "calling", 240)
	check(bex_arena.board.get("phase", "") == "calling" and bex_arena.board.bout.names == ["Ashe", "Brix"]
			and bex_arena.board.bout.stake == 50, "the server calls the duel with both stakes in the purse")
	check(int(bex_arena.board.get("you", {}).get("scrip", 0)) == StashService.Economy.STARTING_SCRIP - 25,
			"the stake is taken from the server's account")
	OS.kill(pid)
	await _leave(ash)
	await _leave(bex)

	# With the plaza: its routes point the arena gate at the arena's port.
	port = 24841
	pid = _start_server(port, ["--bots", "0", "--plaza"])
	var visitor := await _sign_in("Vale", port)
	check(visitor != null, "a client signs in to the plaza")
	if visitor != null:
		await _wait_until(func() -> bool: return visitor.routes.has("arena"), 240)
		check(int(visitor.routes.get("arena", -1)) == port + 10, "the plaza's routes include the arena")
		await _leave(visitor)
		var fighter := await _join("Vale", port + 10)
		check(fighter != null and fighter.raid is Arena, "the arena runs beside the plaza on the same server")
		await _leave(fighter)
	OS.kill(pid)
	_wipe_dir(NET_ACCOUNTS)


func _test_start_screen() -> void:
	print("-- start screen")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/start.tscn",
			"the game launches on the start screen")
	var screen := StartScreen.new()
	add_child(screen)
	await frames(2)
	check(screen.start_button != null and screen.start_button.text == "START", "it offers Start")
	check(screen.title_text == "PROJECT ARES", "it shows the game title")
	var count := [0]
	screen.start_pressed.connect(func() -> void: count[0] += 1)
	screen.start_button.pressed.emit()
	screen.start_button.pressed.emit()
	check(count[0] == 1, "pressing Start fires once, however often it is pressed")
	screen.queue_free()
	var by_key := StartScreen.new()
	add_child(by_key)
	await frames(1)
	var keyed := [0]
	by_key.start_pressed.connect(func() -> void: keyed[0] += 1)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	by_key._unhandled_input(space)
	check(keyed[0] == 1, "Space starts the game too")
	by_key.queue_free()
	await frames(1)
	# Behind it: the lane between worlds, running forever on a fixed set of gates.
	var backdrop := TitleBackdrop.new()
	add_child(backdrop)
	await frames(2)
	check(backdrop.camera != null and backdrop.camera.is_current(), "the start screen has its own camera")
	var gates := backdrop.get_children().filter(func(n: Node) -> bool: return n.has_node("Sign"))
	check(gates.size() == backdrop.gate_count, "the lane is a row of gate frames")
	var zs := func() -> Array: return gates.map(func(g: Node3D) -> float: return g.position.z)
	backdrop.advance(backdrop.gate_spacing * backdrop.gate_count * 3.3)
	var after: Array = zs.call()
	var lane := backdrop.gate_spacing * backdrop.gate_count
	check(after.all(func(z: float) -> bool: return z <= backdrop.gate_spacing * 0.5 and z > -lane),
			"gates that pass the camera go round to the far end, so the lane never runs out")
	var signs := gates.map(func(g: Node) -> String: return (g.get_node("Sign") as Label3D).text) \
			.filter(func(t: String) -> bool: return t != "")
	var names := Worlds.raid_worlds().map(func(w: WorldDef) -> String: return w.display_name.to_upper())
	check(not signs.is_empty() and signs.all(func(t: String) -> bool: return t in names),
			"some gates carry the names of the worlds you can deploy to")
	backdrop.jump_time = 0.1
	await backdrop.jump()
	await frames(1)
	check(backdrop.speed >= backdrop.jump_speed * 0.99 and backdrop.camera.fov > backdrop.fov + 20.0,
			"Start throws the lane into a jump")
	backdrop.queue_free()
	await frames(1)
