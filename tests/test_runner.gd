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
const BasePlan := preload("res://core/base/base_plan.gd")
const BaseHudScript := preload("res://core/ui/base_hud.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	Profile.persist = false
	# A reset profile knows the game: the tour's lock on full-loot worlds is
	# for new players (the tour's own checks turn it back on).
	Profile.tour_on_reset = false
	Profile.onboarding = Profile.Onboarding.finished()
	# Most checks want a player ready to fight where they spawn, unhurt by the
	# ground; the risk zone checks turn the gates and hazards back on.
	Raid.zone_rules = false
	# The checks are written against worlds with their enemies, whatever the
	# project's switch says; servers this starts inherit it.
	Raid.enemies = true
	OS.set_environment("ARES_ENEMIES", "1")
	OS.set_environment("ARES_ENEMY_CAP", "0")
	# DEV MODE: tests never run on the dev save, whatever the machine has.
	DevMode.persist = false
	DevMode.enabled = false
	Profile.save_path = Profile.SAVE_PATH
	Profile.reset()
	# Accounts a previous run left behind hold that run's secrets and would
	# refuse this run's sign-ins, so every run starts with none.
	_wipe_dir(NET_ACCOUNTS)
	_wipe_dir(NET_ACCOUNTS + "_backups")
	var args := OS.get_cmdline_user_args()
	if "--list" in args:
		_list_groups()
		get_tree().quit(0)
		return
	await _run_selected(args)
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- Finding and picking groups --------------------------------------------
# Every `tests/*_tests.gd` file with a `static func run(t: Node)` is a group,
# found on its own (sorted by name), so a new group is a new file and never an
# edit here. A file whose `run` another test file calls (`RigLookTests` from
# `rig_models_tests.gd`) is part of that group instead. A group's name is its
# file's name without `_tests.gd` ("online", "camera"). Groups must pass in any
# order and alone, since CI splits them up.
#
# CI splits the suite in two tiers:
#   offline  groups that never start a server. They only count physics frames,
#            so CI runs them with `--fixed-fps 60`, which drops the real-time
#            wait and finishes in about a minute.
#   net      groups that start a server process and talk to it over ENet. They
#            need real time, so they run without `--fixed-fps`, split in shards.
# A group is `net` when its file (or a runner helper it calls) starts a server
# or makes a NetSession.
#   -- --list                  print every group and its tier
#   -- --only name             run one group (the same as --groups name)
#   -- --tier offline|net      run one tier
#   -- --shard 2/3             run the 2nd of 3 balanced slices (with or without --tier)
#   -- --groups a,b            run the named groups (names as --list prints them)
#   -- --times-out path.json   write how long each group took

const NET_MARKERS: Array[String] = ["_start_server(", "NetSession"]
const GROUP_TIMES := "res://tests/group_times.json"
const TESTS_DIR := "res://tests"

var _source_cache := ""
var _groups_cache: Array[String] = []


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


## Every group: the path of each `*_tests.gd` file that has a `run(t)` no
## other test file calls, sorted by name.
func _groups() -> Array[String]:
	if not _groups_cache.is_empty():
		return _groups_cache
	var files: Array[String] = []
	for file in DirAccess.get_files_at(TESTS_DIR):
		if file.ends_with("_tests.gd"):
			files.append(TESTS_DIR.path_join(file))
	files.sort()
	var called := {}
	var preload_re := RegEx.create_from_string("const (\\w+) := preload\\(\"(res://tests/\\w+_tests\\.gd)\"\\)")
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for m in preload_re.search_all(src):
			if src.contains(m.get_string(1) + ".run("):
				called[m.get_string(2)] = true
	for path in files:
		if not called.has(path) and FileAccess.get_file_as_string(path).contains("static func run("):
			_groups_cache.append(path)
	return _groups_cache


## A group's file and every test script it preloads, near or far, that did
## not compile. Such a script still loads, but every call on it does nothing,
## so its group would pass by running no checks at all.
func _broken_scripts(group: String) -> Array[String]:
	var broken: Array[String] = []
	var preload_re := RegEx.create_from_string("preload\\(\"(res://tests/[\\w/]+\\.gd)\"\\)")
	var seen := {group: true}
	var todo: Array[String] = [group]
	while not todo.is_empty():
		var path: String = todo.pop_back()
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			broken.append(path)
		for m in preload_re.search_all(FileAccess.get_file_as_string(path)):
			var dep := m.get_string(1)
			if not seen.has(dep) and dep != "res://tests/test_runner.gd":
				seen[dep] = true
				todo.append(dep)
	broken.sort()
	return broken


func _group_label(group: String) -> String:
	return group.get_file().trim_suffix("_tests.gd")


## The source of a group's file, or of a test file a group's file preloads
## under `const_name`.
func _module_source(const_name: String, from_src: String) -> String:
	var m := RegEx.create_from_string("const " + const_name + " := preload\\(\"(res://tests/\\w+\\.gd)\"\\)").search(from_src)
	return FileAccess.get_file_as_string(m.get_string(1)) if m != null else ""


func _is_net(group: String) -> bool:
	var src := _source()
	var call_re := RegEx.create_from_string("\\b(_[a-z]\\w*)\\(")
	var module_re := RegEx.create_from_string("\\b([A-Z]\\w*)\\.run\\(")
	var seen := {}
	var todo: Array[String] = []
	var files: Array[String] = [FileAccess.get_file_as_string(group)]
	while not files.is_empty():
		var body: String = files.pop_back()
		for marker in NET_MARKERS:
			if marker in body:
				return true
		for m in call_re.search_all(body):
			todo.append(m.get_string(1))
		for m in module_re.search_all(body):
			files.append(_module_source(m.get_string(1), body))
	# Runner helpers the group's files call (`t._join(...)`).
	while not todo.is_empty():
		var fn: String = todo.pop_back()
		if seen.has(fn):
			continue
		seen[fn] = true
		var body := _func_body(src, fn)
		for marker in NET_MARKERS:
			if marker in body:
				return true
		for m in call_re.search_all(body):
			todo.append(m.get_string(1))
	return false


func _list_groups() -> void:
	for group in _groups():
		print("%-6s %s" % ["net" if _is_net(group) else "offline", _group_label(group)])



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
	# Keep the groups' order inside the slice.
	return groups.filter(func(g: String) -> bool: return g in mine)


func _run_selected(args: PackedStringArray) -> void:
	var groups := _groups()
	var tier := _arg(args, "--tier")
	if tier != "":
		if tier not in ["offline", "net"]:
			check(false, "--tier must be offline or net, got '%s'" % tier)
			return
		groups = groups.filter(func(g: String) -> bool: return _is_net(g) == (tier == "net"))
	var names := _arg(args, "--groups") if _arg(args, "--only") == "" else _arg(args, "--only")
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
		var broken := _broken_scripts(group)
		for path in broken:
			check(false, "%s compiles" % path)
		if broken.is_empty():
			await (load(group) as GDScript).run(self)
		var seconds := (Time.get_ticks_msec() - started) / 1000.0
		took[_group_label(group)] = snappedf(seconds, 0.1)
		print("== %s: %.1fs%s" % [_group_label(group), seconds, "" if _failed == failed_before else ", FAILED"])
	var out := _arg(args, "--times-out")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(took, "\t", true))



func check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what)


## Stands every guard of a world of encounter pockets (`WorldDef.pocket_wake`)
## at once, as if a player stood by each, for checks that want the whole
## garrison up (a server with nobody in it wakes none). `pocket_tests.gd`
## checks the waking itself.
func stand_pockets(raid: Raid) -> void:
	for key: Variant in raid._pockets:
		var pocket: Dictionary = raid._pockets[key]
		pocket.awake = true
		for i: int in pocket.guards:
			var guard: Dictionary = raid._guards[i]
			if guard.bot == null and guard.back_in <= 0.0:
				guard.bot = raid._add_guard(guard.marker)
	raid._seal_hives()


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
	# Walk (and later sneak) the way with nothing in front for 10 m, so
	# cover where the player happened to land cannot get in the way.
	var open_yaw := open_heading(p, 10.0)
	p.cmd.yaw = open_yaw
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
		# The bot faces away (-Z is forward at yaw 0), the player behind it,
		# along the open way found above.
		var away := Vector3(-sin(open_yaw), 0.0, -cos(open_yaw))
		bot.global_position = p.global_position + away * brain.close_sense_range * 0.6
		bot.cmd.yaw = open_yaw
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


## The middle of a depot (its Area's centre, about 2 m over the ground)
## whose pad is open along world Z for several metres both ways: groups
## that need clear, flat ground stage a fight there. A depot's terminal
## stands at its back edge, so this picks the one turned furthest to the
## side, which keeps the terminal off that line (and never one in a gate).
func _open_ground(raid: Raid) -> Vector3:
	# The first in map order that will do (the quietest: the Foundry's in
	# Ashfront, where no garrison stands round it), else the one turned
	# furthest to the side.
	var best: Depot = raid.depots[0]
	for depot: Depot in raid.depots:
		# Not one in a gate outpost: weapons are locked there.
		if raid.outpost_at(depot.global_position - Vector3(0, 2, 0)) != null:
			continue
		if absf(depot.global_basis.z.x) > 0.9:
			return depot.global_position
		if absf(depot.global_basis.z.x) > absf(best.global_basis.z.x) + 0.01:
			best = depot
	return best.global_position


func _duel(raid: Raid) -> Array:
	var p := raid.player
	await frames(40)
	var arena := _open_ground(raid)
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
	blade.light_tell = 0.0
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


func open_heading(actor: Actor, reach: float) -> float:
	var chest := actor.global_position + Vector3(0, 1.0, 0)
	for k in 8:
		var yaw := TAU * k / 8.0
		var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var ray := PhysicsRayQueryParameters3D.create(chest, chest + ahead * reach, Actor.LAYER_WORLD)
		if actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			return yaw
	return 0.0


## `kit` and the other id lists the helpers take are plain arrays, so a
## group's file can pass a literal (a typed parameter refuses one there).
func _kit_raid(p_seed: int, kit: Array) -> Raid:
	var ids: Array[String] = []
	ids.assign(kit)
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed, ids)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(40)
	return raid


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
	# Every move below heads along the view: point it in toward the middle,
	# not out at the rim (a drop by the rim ran out of heat there).
	p.cmd.yaw = atan2(p.global_position.x, p.global_position.z)
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
	# the boost stays level until jump climbs. Aim let go: a boost is
	# travel, and aim held brings you upright (Caleb's call).
	p.cmd.pitch = PI / 4.0
	p.cmd.secondary = false
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
	check(boost_heat > 0.0 and boost_heat < hover_heat * 0.3, "boosting is the jetpack's cruise: far cooler than hovering")
	p.cmd.sprint = false
	p.cmd.secondary = true
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
	# Aim let go, so the jets boost (aim held would bring you upright).
	p.cmd.secondary = false
	p.cmd.sprint = true
	p.cmd.move = Vector2(0, 1)
	await frames(10)
	check(p.flight.is_boosting and p.air_aim() == 1.0, "boosting spoils the aim")
	var gun := p.get_active_weapon() as Gun
	if gun:
		var wild := gun.current_spread_deg()
		p.cmd.sprint = false
		p.cmd.secondary = true
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
	# Feet on the ground: the open ground is a heightfield, not a solid.
	p.global_position = Raid.of(p)._stand(Vector3(0.0, 0.0, 60.0))
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


func _lowest_point(node: Node3D) -> float:
	var low := INF
	for mesh_node: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box := mesh_node.get_aabb()
		for i in 8:
			low = minf(low, (mesh_node.global_transform * box.get_endpoint(i)).y)
	return low


const MapScript_Frost := preload("res://worlds/frostline/map.gd")


const MasteryDB := preload("res://core/progression/mastery_db.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const MasteryPanel := preload("res://core/progression/mastery_panel.gd")


func _mastery_raid(p_seed: int, kit: Array, picks: Dictionary) -> Raid:
	var ids: Array[String] = []
	ids.assign(kit)
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), p_seed, ids, picks)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await frames(5)
	return raid


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


func _start_server(port: int, extra: Array, world := "ashfront") -> int:
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


func _step_spread(actor: Actor, ticks: int) -> Vector2:
	var least := 99.0
	var most := 0.0
	var prev := actor.global_position
	for i in ticks:
		await frames(1)
		var moved := actor.global_position.distance_to(prev)
		prev = actor.global_position
		least = minf(least, moved)
		most = maxf(most, moved)
	return Vector2(least, most)


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


## How high off the ground `_run_is_clear` sweeps the body from: a step
## or a kerb under it is climbed, not a wall.
const RUN_KNEE := 0.35


## Whether `actor` could run `reach` metres along `dir` (flat, unit length)
## from `from` without meeting a wall, a wreck, a bike or another actor. It
## follows the ground, so a slope does not count as a wall.
func _run_is_clear(actor: Actor, from: Vector3, dir: Vector3, reach: float) -> bool:
	return _clear_metres(actor, from, dir, reach) >= reach


## How many metres (up to `reach`) `actor` could run along `dir` from `from`
## before something stops it. The body is swept from step to step from knee
## height up, not just a ray at the chest: a ray ran over a bike's seat or a
## low wreck, and the run then stopped against it after a metre or two (the
## flaky "a lagging player still runs at full speed" check on CI).
func _clear_metres(actor: Actor, from: Vector3, dir: Vector3, reach: float) -> float:
	var space := actor.get_world_3d().direct_space_state
	var skip: Array[RID] = []
	var stop := reach
	for other in get_tree().get_nodes_in_group("actors"):
		if other is Actor and Raid.together(other, actor):
			skip.append((other as Actor).get_rid())
			var to: Vector3 = (other as Actor).global_position - from
			to.y = 0.0
			var along := to.dot(dir)
			if other != actor and along > 0.0 and along < reach + 1.0 and (to - dir * along).length() < 1.6:
				stop = minf(stop, maxf(along - 1.6, 0.0))
	var body := CapsuleShape3D.new()
	body.radius = Actor.BODY_RADIUS + 0.05
	body.height = Actor.BODY_HEIGHT - RUN_KNEE
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = body
	sweep.exclude = skip
	sweep.collision_mask = actor.collision_mask
	var last := Vector3.ZERO
	var last_floor := Vector3.ZERO
	for i in int(stop) + 1:
		var above := from + dir * float(i) + Vector3(0, 4.0, 0)
		var down := PhysicsRayQueryParameters3D.create(above, above + Vector3(0, -12.0, 0))
		down.exclude = skip
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			return maxf(i - 1, 0)
		var ground: Vector3 = floor_hit.position
		var chest: Vector3 = ground + Vector3(0, 0.9, 0)
		if i > 0:
			if absf(chest.y - last.y) > 0.7:
				return i - 1
			var ray := PhysicsRayQueryParameters3D.create(last, chest)
			ray.exclude = skip
			if not space.intersect_ray(ray).is_empty():
				return i - 1
			# From over the higher of the two floors, so a slope is not
			# taken for a wall.
			var lift := maxf(last_floor.y, ground.y) + RUN_KNEE + body.height * 0.5
			sweep.transform = Transform3D(Basis.IDENTITY, Vector3(last_floor.x, lift, last_floor.z))
			sweep.motion = Vector3(ground.x - last_floor.x, 0.0, ground.z - last_floor.z)
			if space.cast_motion(sweep)[0] < 1.0:
				return i - 1
		last = chest
		last_floor = ground
	return stop


## A flat direction `actor` can run `reach` metres in from `from`: `prefer`
## if that is clear, otherwise the nearest clear one to it, and where none
## is the one with the longest clear run.
func _clear_run(actor: Actor, from: Vector3, prefer: Vector3, reach: float) -> Vector3:
	var best := prefer
	var best_metres := -1.0
	for i in 16:
		var turn := TAU / 16.0 * float((i + 1) / 2) * (1.0 if i % 2 == 1 else -1.0)
		var dir := prefer.rotated(Vector3.UP, turn)
		var metres := _clear_metres(actor, from, dir, reach)
		if metres >= reach:
			return dir
		if metres > best_metres:
			best_metres = metres
			best = dir
	return best


func _lagged_shots(port: int, extra: Array) -> Array:
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


func _aim_at(actor: Actor, point: Vector3) -> void:
	var aim := (point - actor.get_eye_position()).normalized()
	actor.cmd.aim_dir = aim
	actor.cmd.yaw = atan2(-aim.x, -aim.z)
	actor.cmd.pitch = asin(clampf(aim.y, -1.0, 1.0))


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


const StashService := preload("res://core/account/stash_service.gd")


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
	var bad_rows: Array[String] = []
	var settings_script: Script = GameSettings
	for row: Dictionary in GameSettings.SCHEMA:
		var kind: String = row.get("kind", "")
		var hidden: bool = row.get("tab", "") == "" and kind in ["list", "text"] and row.has("default")
		var whole: bool = hidden or (row.get("tab", "") in PhoneScript.SETTINGS_TABS and row.has("label")
				and row.has("default") and (kind == "toggle" or (kind == "slider" and row.has("range")
				and row.has("step")) or (kind == "choice" and row.has("choices"))))
		if not whole or settings_script.get(row["key"]) == null:
			bad_rows.append(row.get("key", "?"))
	check(bad_rows.is_empty(), "every setting's row is whole, on a phone tab (or kept off them) and has its var (%s)" % ", ".join(bad_rows))
	var bus := AudioServer.get_bus_index("Master")
	check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.01, "volume reaches the audio bus")
	GameSettings.set_value("anti_aliasing", 99)
	check(GameSettings.anti_aliasing == GameSettings.ANTI_ALIASING.size() - 1 and GameSettings.to_dict().has("anti_aliasing"),
			"edge smoothing is clamped to the modes there are and saved")
	GameSettings.set_value("anti_aliasing", 0)
	GameSettings.apply_graphics()
	var root := get_tree().root
	var off := root.msaa_3d == Viewport.MSAA_DISABLED and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED
	GameSettings.set_value("anti_aliasing", 4)
	GameSettings.apply_graphics()
	check(off and root.msaa_3d == Viewport.MSAA_4X and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA,
			"edge smoothing reaches the main view")
	GameSettings.set_value("anti_aliasing", 2)
	GameSettings.set_value("edge_ink", true)
	var ink_smaa := GameSettings.ink_shown()
	GameSettings.set_value("anti_aliasing", 3)
	check(ink_smaa and not GameSettings.ink_shown() and GameSettings.to_dict().has("edge_ink"),
			"the far-shape outline is saved, and left out with MSAA, which gives it no depth to read")
	# Slower graphics cards: shadows, render scale and ambient occlusion,
	# each reaching a world that is already standing. High is the world as
	# it was made.
	var sun := DirectionalLight3D.new()
	sun.add_to_group(GameSettings.SUN_GROUP)
	add_child(sun)
	GameSettings.set_value("shadows", 0)
	GameSettings.fit_sun(sun, 200.0)
	var high := sun.shadow_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
			and is_equal_approx(sun.directional_shadow_max_distance, 200.0)
	GameSettings.set_value("shadows", 2)
	GameSettings.apply_graphics()
	var low := sun.shadow_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS \
			and sun.directional_shadow_max_distance < 200.0
	GameSettings.set_value("shadows", 99)
	GameSettings.apply_graphics()
	check(high and low and not sun.shadow_enabled and GameSettings.to_dict().has("shadows"),
			"the shadow setting reaches a standing world's sun, and High is the world's own")
	GameSettings.set_value("shadows", 0)
	GameSettings.apply_graphics()
	check(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 200.0),
			"and back to High, the world's own shadows again")
	sun.free()
	var atmosphere := WorldEnvironment.new()
	atmosphere.environment = Environment.new()
	atmosphere.environment.ssao_enabled = true
	atmosphere.add_to_group(GameSettings.ATMOSPHERE_GROUP)
	add_child(atmosphere)
	GameSettings.set_value("ambient_occlusion", false)
	GameSettings.apply_graphics()
	check(not atmosphere.environment.ssao_enabled and GameSettings.to_dict().has("ambient_occlusion"),
			"ambient occlusion can be switched off")
	atmosphere.free()
	GameSettings.set_value("render_scale", 2)
	GameSettings.apply_graphics()
	var scaled := root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR and root.scaling_3d_scale < 1.0
	GameSettings.set_value("render_scale", 0)
	GameSettings.apply_graphics()
	check(scaled and is_equal_approx(root.scaling_3d_scale, 1.0) and GameSettings.to_dict().has("render_scale"),
			"the render scale reaches the main view, full size by default")
	# Battle smoke (PlanetType.smoke): a setting that switches the volume and
	# the volumetric fog it needs, thicker with the war and in a storm.
	var smoke_env := Environment.new()
	var smoke := Planet.GroundSmoke.make(PlanetTypes.get_type("ashland").smoke, smoke_env)
	add_child(smoke)
	GameSettings.set_value("ground_smoke", false)
	GameSettings.apply_graphics()
	var smoke_off := not smoke.visible and not smoke_env.volumetric_fog_enabled
	GameSettings.set_value("ground_smoke", true)
	GameSettings.apply_graphics()
	check(smoke_off and smoke.visible and smoke_env.volumetric_fog_enabled and GameSettings.to_dict().has("ground_smoke"),
			"battle smoke is a saved setting that switches the smoke and its volumetric fog")
	check(smoke.density_for(0.0, 0.0) < smoke.density_for(1.0, 0.0) and smoke.density_for(1.0, 0.0) < smoke.density_for(1.0, 1.0),
			"battle smoke thickens with the war and thicker still in a storm")
	smoke.queue_free()
	# View distance (Caleb: a short view spoils it): a planet's far land
	# ring is drawn whole at High, the lower levels draw a share of it, and
	# every level scales how far a dressed map's props are drawn, live.
	var horizon := Planet.horizon_far(PlanetTypes.get_type("glacier"))
	GameSettings.set_value("view_distance", GameSettings.VIEW_DISTANCE_DEFAULT)
	var reach_high := GameSettings.view_far_for(horizon, 400.0)
	GameSettings.set_value("view_distance", GameSettings.VIEW_DISTANCE.size() - 1)
	var reach_low := GameSettings.view_far_for(horizon, 400.0)
	check(GameSettings.VIEW_DISTANCE[GameSettings.VIEW_DISTANCE_DEFAULT][0] == "High"
			and reach_high > float(PlanetTypes.get_type("glacier").horizon["reach"])
			and reach_low < reach_high and reach_low >= 400.0
			and is_equal_approx(GameSettings.view_far_for(0.0, 400.0), 400.0)
			and GameSettings.to_dict().has("view_distance"),
			"the view reaches past a planet's far land ring at High, less on Low, never under the base reach")
	var drawn := Node3D.new()
	add_child(drawn)
	var crate := MeshInstance3D.new()
	var crate_box := BoxMesh.new()
	crate_box.size = Vector3.ONE
	crate.mesh = crate_box
	drawn.add_child(crate)
	var hall := MeshInstance3D.new()
	var hall_box := BoxMesh.new()
	hall_box.size = Vector3(40, 12, 40)
	hall.mesh = hall_box
	drawn.add_child(hall)
	var rocks := MultiMeshInstance3D.new()
	rocks.visibility_range_end = 220.0
	drawn.add_child(rocks)
	GameSettings.set_value("view_distance", GameSettings.VIEW_DISTANCE_DEFAULT)
	Look._limit_draw_distance(drawn)
	var crate_high := crate.visibility_range_end
	var as_made := is_equal_approx(crate_high, Look.draw_distance_per_metre) and hall.visibility_range_end == 0.0 \
			and is_equal_approx(rocks.visibility_range_end, 220.0)
	GameSettings.set_value("view_distance", GameSettings.VIEW_DISTANCE.size() - 1)
	GameSettings.apply_graphics()
	var low_cut := crate.visibility_range_end < crate_high and hall.visibility_range_end > 0.0 \
			and rocks.visibility_range_end < 220.0 and root.mesh_lod_threshold > 1.0
	GameSettings.set_value("view_distance", 0)
	GameSettings.apply_graphics()
	var ultra := crate.visibility_range_end > crate_high and hall.visibility_range_end == 0.0 \
			and rocks.visibility_range_end > 220.0 and root.mesh_lod_threshold < 1.0
	GameSettings.set_value("view_distance", GameSettings.VIEW_DISTANCE_DEFAULT)
	GameSettings.apply_graphics()
	check(as_made and low_cut and ultra and is_equal_approx(crate.visibility_range_end, crate_high)
			and is_equal_approx(root.mesh_lod_threshold, 1.0),
			"View distance scales a standing map's prop reach and mesh detail, and High is the map as made")
	drawn.free()
	# Far ground and walls shimmer without mipmaps, so every world texture
	# keeps them (and is not re-imported without them when seen in 3D).
	var bare: Array[String] = []
	for folder in DirAccess.get_directories_at("res://assets/textures"):
		for file in DirAccess.get_files_at("res://assets/textures".path_join(folder)):
			if not file.ends_with(".import"):
				continue
			var cfg := ConfigFile.new()
			cfg.load("res://assets/textures".path_join(folder).path_join(file))
			if not bool(cfg.get_value("params", "mipmaps/generate", false)):
				bare.append(folder.path_join(file))
	check(bare.is_empty(), "world textures have mipmaps (%s)" % ", ".join(bare))
	GameSettings.reset()
	GameSettings.apply()
	GameSettings.apply_graphics()


## Settings › Input lists every key from the input map as it is right now.
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
	check(PhoneScript.key_name("free_look") == "E", "free look is held on E, clear of the space bar")
	check(PhoneScript.controls_text("Hold {jump}") == "Hold Space", "a key spec reads from the input map")
	phone.open_settings_tab("input")
	await frames(1)
	check(phone.app == "settings" and "controls" not in PhoneScript.APPS
			and phone._body.find_child("Key_interact", true, false) != null and phone._body.get_child_count() > 20,
			"Settings › Input lists every key (the Keys app moved there)")
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


func _test_phone_escape() -> void:
	print("Phone: Tab and Esc")
	check(PhoneScript.key_name("toggle_view") == "Tab" and PhoneScript.key_name("scoreboard") == "O",
			"Tab switches the camera and O holds the scoreboard")
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
	var fresh: CanvasLayer = PhoneScript.new()
	var opens_on: String = fresh.settings_tab
	fresh.free()
	phone.open_settings_tab("view")
	check(opens_on == "view" and phone.settings_tabs()[0] == "view" and phone._tabs.visible
			and phone._tabs.get_child_count() == phone.settings_tabs().size(),
			"settings open on the View tab, first in a row of tabs")
	await frames(1)
	var first_toggle: CheckButton = phone._body.find_children("*", "CheckButton", true, false)[0]
	check(first_toggle.text == "Fullscreen" and phone._body.get_child(1) == first_toggle
			and phone._body.find_children("*", "OptionButton", true, false)[0].get_index() < 6
			and phone._body.find_children("*", "OptionButton", true, false)[0].get_item_text(0) == GameSettings.ANTI_ALIASING[0][0],
			"fullscreen and smooth edges sit at the top of Settings (Caleb's call)")
	check(first_toggle.button_pressed == GameSettings.window_is_full(),
			"the fullscreen switch shows whether the window really is fullscreen")
	await _check_pages_fit(phone)
	phone.open_app("settings")
	phone.open_settings_tab("view")
	await frames(1)
	# Dragging a field of view or camera slider previews the view live.
	var previews: Array = []
	phone.preview_changed.connect(func(on: bool) -> void: previews.append(on))
	var fov_slider: HSlider = phone._body.find_children("*", "HSlider", true, false)[0]
	var fov_was := GameSettings.field_of_view
	phone._start_preview(fov_slider)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(40, 0)
	phone._input(drag)
	check(phone.previewing and previews == [true] and GameSettings.field_of_view > fov_was,
			"dragging the field of view slider previews it live, following the mouse's motion")
	var let_go := InputEventMouseButton.new()
	let_go.button_index = MOUSE_BUTTON_LEFT
	phone._input(let_go)
	check(not phone.previewing and previews == [true, false], "letting go ends the preview")
	GameSettings.field_of_view = fov_was
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

	# Third person leaves the camera where it is (the phone throws a hologram,
	# `phone_hologram_tests.gd`); first person drops the eyes to it and zooms in.
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
		controller.view_mode = PlayerController.ViewMode.THIRD
		controller.input_blocked = true
		controller.phone_out = true
		for i in 40:
			await frames(1)
		check(controller.is_third_person() and not controller.phone_zoomed()
				and absf(controller.camera.fov - controller.wanted_base_fov()) < 1.0,
				"with the phone out in third person the view does not zoom in on the hand")
		check(absf(controller.camera.global_rotation.x - controller.pitch) < 0.02,
				"nor drop the eyes to it: the camera stays where it was, the world in view")
		controller.phone_out = false
		controller.input_blocked = false
		for i in 40:
			await frames(1)
		controller.view_mode = PlayerController.ViewMode.FIRST
		var pitch_before := controller.pitch
		controller.input_blocked = true
		controller.phone_out = true
		for i in 40:
			await frames(1)
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
		controller.phone_preview = true
		for i in 40:
			await frames(1)
		check(not controller.phone_zoomed() and absf(controller.camera.fov - controller.wanted_base_fov()) < 1.0,
				"while a view slider is dragged the zoom lets go, so the field of view shows as it is")
		controller.phone_preview = false
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


## Every app and every Settings tab fits the phone's glass (Caleb's report:
## pages ran off the right edge, as if zoomed in).
func _check_pages_fit(phone: CanvasLayer) -> void:
	var glass: float = phone.screen_size.x - phone.glass_inset.x - phone.glass_inset.z
	var wide: Array[String] = []
	var pages: Array = []
	for tab: String in phone.settings_tabs():
		pages.append(["settings", tab])
	for app_name: String in PhoneScript.APPS:
		if app_name != "settings":
			pages.append([app_name, ""])
	for page: Array in pages:
		if page[1] != "":
			phone.settings_tab = page[1]
		phone.open_app(page[0])
		await frames(2)
		if phone._page.size.x > glass - 30.0 or phone._tabs.get_combined_minimum_size().x > glass - 30.0:
			wide.append("%s %s (%d px)" % [page[0], page[1], phone._page.size.x])
	check(wide.is_empty(), "every phone app and settings tab fits the glass (%s)" % ", ".join(wide))


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
	ben.base_visit_requested.connect(func(owner: String, owner_stash: Array, _loadout: Dictionary, upgrades: Array,
			plan: Dictionary) -> void:
		visits.append([owner, owner_stash, upgrades, plan]))
	ana.send_invite("ben", "base")
	await _wait_until(func() -> bool: return phone.invites().size() == 1, 240)
	phone.answer_invite(int(phone.invites()[0].id), true)
	await _wait_until(func() -> bool: return not visits.is_empty(), 240)
	check(visits.size() == 1 and visits[0][0] == "Ana" and "rifle_carbine" in visits[0][1] and visits[0][2] == []
			and BasePlan.clean(visits[0][3]) == BasePlan.DEFAULT,
			"accepting a base invite brings the owner's stash, base upgrades and plan to show")

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
	check(in_alcove and BaseLayout.ARMORY.size() == 4, "the rack's sections all hang inside the armory")
	check(others_out, "armor, rigs, the garage and the shelves stay in the main room")
	check(spots > 14, "the rack holds more weapons than the old gun rack and blade wall did (%d spots)" % spots)
	await _test_suit_up(base)
	# The bench and the fabricator have a room of their own, clear of the
	# rack.
	var bench_at := base.bench_transform().origin
	var craft := base.station(HomeBase.CRAFT_ID)
	var clear := true
	for display in base.displays:
		if BaseLayout.is_armory(display.kind):
			clear = clear and display.position.distance_to(bench_at) > 2.0 and not base.in_workshop(display.position)
	check(base.in_workshop(bench_at) and not base.in_armory(bench_at)
			and craft != null and base.in_workshop(craft.position) and clear,
			"the gunsmith bench and the fabricator stand in the workshop, a room of their own clear of the rack")
	var locker: Vector3 = HomeBase.STATIONS["locker"]["at"]
	check(base.room_at(locker) == "" and base.inside(locker) and absf(locker.z - base.room_size.z * 0.5) < 1.0,
			"the locker stands in the hub by the way out")
	var plates := 0
	for room: String in BasePlan.ROOMS:
		plates += 1 if base.has_node("Plate_" + BasePlan.title(room).to_pascal_case()) else 0
	check(plates == BasePlan.ROOMS.size(), "a plate over each doorway names its room (%d of %d)" % [plates, BasePlan.ROOMS.size()])
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
	var armory_door := base.room_transform("armory")
	walker.global_position = base.to_global(armory_door * Vector3(0, 0.1, 2.5))
	walker.velocity = Vector3.ZERO
	await frames(2)
	var into := -armory_door.basis.z
	walker.cmd.yaw = atan2(-into.x, -into.z)
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
	check(in_deploy.call(mirror_at) and not base.has_node("DeploySign"),
			"the mirror stands in the deploy area by the front wall, with no sign over it")
	var shelved := true
	for kind: String in HomeBase.STORAGE_ROWS:
		for i in int(BaseLayout.KINDS[kind]["spots"]):
			var at := base.spot_transform(kind, i).origin
			shelved = shelved and base.room_at(at) == HomeBase.KIND_ROOMS[kind]
	check(shelved, "supplies and trophies sit on the shelves in the stores, chips in the gear hall")
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
	check(parked, "every garage bay is in the garage")
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
	# Walk down the corridor and through the range door.
	p.global_position = base.to_global(Vector3(0, 0.1, -base.range_from() + 2.0))
	p.velocity = Vector3.ZERO
	p.cmd.yaw = 0.0
	p.cmd.pitch = 0.0
	p.cmd.move = Vector2(0, 1)
	await frames(60)
	p.cmd.move = Vector2.ZERO
	await frames(2)
	check(base.in_range(base.to_local(p.global_position)), "you can walk down the corridor into the range")
	check(not p.weapons_locked, "past the line your weapons are free")
	check(p.get_active_weapon() == null, "but stay away until you draw one")
	p.cmd.switch_weapon = p.weapon_for_key(1)
	await frames(2)
	p.cmd.switch_weapon = -1
	var gun := p.get_active_weapon() as Gun
	check(gun != null and gun.reserve_ammo >= gun.mag_size * 4, "and never run dry")
	# Shoot the nearest plate.
	var plate: HomeBase.RangeTarget = base.targets[0]
	var line_z := -base.range_from() - base.firing_line
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

