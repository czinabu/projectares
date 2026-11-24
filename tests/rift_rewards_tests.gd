extends RefCounted
## The Basalt Rift's rig rewards (DESIGN.md "Basalt Rift (part three)"): the
## Crown's caches, the Lord of the Crown and the Sky Leviathan pay upgrade
## data and rig blueprints (only rig blueprints), and the two hardest fights
## carry the earned thruster trails. The runner finds this file by itself.

const RIG_BLUEPRINTS: Array[String] = ["bp_jetpack", "bp_boots_thruster", "bp_wings_glide"]
const Crafting := preload("res://core/progression/crafting.gd")


static func run(t: Node) -> void:
	print("Basalt Rift: the rig rewards")
	var world := Worlds.get_world("rift")
	if world == null:
		t.check(false, "rift rewards: the world is registered")
		return
	_blueprints(t, world)
	_crown(t, world)
	_leviathan(t, world)
	_warlord(t, world)
	await _crown_caches(t, world)


## Every blueprint the rift hands out steps a rig up.
static func _blueprints(t: Node, world: WorldDef) -> void:
	var rng := RandomNumberGenerator.new()
	var seen := {}
	var only_rigs := true
	for i in 300:
		rng.seed = i
		for id in world.roll_crafting_loot(rng, 1.0, 1):
			if ItemDB.has_tag(id, "blueprint"):
				seen[id] = true
				only_rigs = only_rigs and id in RIG_BLUEPRINTS
	t.check(only_rigs and seen.size() == RIG_BLUEPRINTS.size(),
			"rift rewards: the rift's blueprints are the flight rigs', every one of them, nothing else")
	var crafted := RIG_BLUEPRINTS.all(func(bp: String) -> bool:
		return ItemDB.has_tag(bp, "blueprint") and not Crafting.made_from(bp).is_empty())
	t.check(crafted, "rift rewards: each rig blueprint crafts a higher Mk")
	rng.seed = 1
	var data := world.roll_crafting_loot(rng, 0.0, 2)
	t.check(data == (["upgrade_data", "upgrade_data"] as Array[String]), "rift rewards: upgrade data is paid as asked")


## The Crown's caches are where the rig rewards turn up most.
static func _crown(t: Node, world: WorldDef) -> void:
	var rng := RandomNumberGenerator.new()
	var crown_data := 0
	var cache_data := 0
	var blueprints := 0
	for i in 200:
		rng.seed = i
		var crown := world.roll_loot("crown", rng)
		crown_data += crown.count("upgrade_data")
		for id in crown:
			if id in RIG_BLUEPRINTS:
				blueprints += 1
		rng.seed = i
		cache_data += world.roll_loot("cache", rng).count("upgrade_data")
	t.check(crown_data > 50 and blueprints > 10 and cache_data == 0,
			"rift rewards: the Crown's caches pay upgrade data and rig blueprints, the plain caches do not")


## The Leviathan's broken parts sometimes drop upgrade data; its hold always
## pays some, often a rig blueprint, and now and then the Leviathan trail.
static func _leviathan(t: Node, world: WorldDef) -> void:
	var rng := RandomNumberGenerator.new()
	var part_data := 0
	var hold_ok := true
	var hold_blueprints := 0
	var trails := 0
	for i in 200:
		rng.seed = i
		part_data += world.roll_loot("airship_part", rng).count("upgrade_data")
		rng.seed = i
		var hold := world.roll_loot("airship_hold", rng)
		hold_ok = hold_ok and hold.count("upgrade_data") >= 2
		for id in hold:
			if id in RIG_BLUEPRINTS:
				hold_blueprints += 1
			if id == "trail_leviathan":
				trails += 1
	t.check(part_data > 10, "rift rewards: a broken weak spot sometimes drops upgrade data")
	t.check(hold_ok and hold_blueprints > 60 and hold_blueprints < 140,
			"rift rewards: the Leviathan's hold always pays upgrade data, and about half the time a rig blueprint")
	t.check(trails > 15 and trails < 70 and RigTrail.earned(RigTrail.of_item("trail_leviathan")),
			"rift rewards: now and then the hold carries the earned Leviathan trail")


## The Lord of the Crown carries upgrade data, often a rig blueprint, and now
## and then the earned Magma trail.
static func _warlord(t: Node, world: WorldDef) -> void:
	t.check(world.warlord_upgrade_data >= 1 and world.warlord_blueprint_chance > 0.0,
			"rift rewards: the Lord of the Crown carries upgrade data and maybe a rig blueprint")
	t.check(world.warlord_paint == "trail_magma" and world.warlord_paint_chance > 0.0
			and RigTrail.earned(RigTrail.of_item(world.warlord_paint)),
			"rift rewards: and now and then the earned Magma trail")


## On the map, the Crown's three caches roll from the Crown's table.
static func _crown_caches(t: Node, world: WorldDef) -> void:
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 11)
	await t.frames(2)
	var crown := 0
	for marker in raid.get_tree().get_nodes_in_group("spawn_cache"):
		if str(marker.get_meta("loot_source", "cache")) == "crown":
			crown += 1
	t.check(crown == 3, "rift rewards: the Crown's three caches roll from the Crown's table")
	raid.queue_free()
	await t.frames(1)
