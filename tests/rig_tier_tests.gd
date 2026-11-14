extends RefCounted
## Checks for flight rig tiers: each rig comes as Mk1, Mk2 and Mk3, and a
## higher tier adds about 15% to the rig's strength only (Caleb's call):
## jetpacks hover longer and climb higher, boots get a charge and a faster
## refill, wings glide faster and longer. Their weaknesses never improve.
## Only Mk1 drops; Mk2 and up are crafted.
## Run from the main test runner. Nothing here starts a server.

const FeelBench := preload("res://tests/feel_bench.gd")
const ASHFRONT := preload("res://worlds/ashfront/world.gd")
const FROSTLINE := preload("res://worlds/frostline/world.gd")
const Economy := preload("res://core/economy/economy.gd")
const StashRules := preload("res://core/account/stash_rules.gd")

## Each rig's tiers, Mk1 first.
const FAMILIES := {
	"jetpack": ["jetpack_mk1", "jetpack_mk2", "jetpack_mk3"],
	"wings": ["wings_glide", "wings_glide_mk2", "wings_glide_mk3"],
	"boots": ["boots_thruster", "boots_thruster_mk2", "boots_thruster_mk3"],
}


static func run(t: Node) -> void:
	print("Flight rig tiers")
	_test_items(t)
	_test_loot(t)
	_test_ceiling_rules(t)
	await _test_climbs(t)
	await _test_raid_ground(t)


## Every rig has three tiers. Up a tier its strength stats grow by about
## 15% (charges by one) and every other stat stays the Mk1's.
static func _test_items(t: Node) -> void:
	for family: String in FAMILIES:
		var ids: Array = FAMILIES[family]
		var strength: Array = ItemDB.RIG_STRENGTH[ids[0]]
		var base_stats := ItemDB.item_stats(ids[0])
		for i in ids.size():
			var id: String = ids[i]
			var rig := _rig(id)
			t.check(ItemDB.has_tag(id, "flight_rig") and rig.tier == i + 1, "%s is a Mk%d rig" % [id, i + 1])
			t.check(ItemDB.item_name(id).begins_with("Mk%d " % (i + 1)), "%s says its tier in its name" % id)
			t.check(is_equal_approx(rig.max_heat, 100.0), "%s keeps the same 100 heat bar" % id)
			if i == 0:
				rig.free()
				continue
			var stats := ItemDB.item_stats(id)
			var same := base_stats.keys().filter(func(stat: String) -> bool:
				return stat != "tier" and stat not in strength and ("-" + stat) not in strength \
						and str(stats.get(stat)) != str(base_stats[stat]))
			t.check(same.is_empty(), "%s improves only its strength; its weaknesses stay the Mk1's %s" % [id, same])
			var below := ItemDB.item_stats(ids[i - 1])
			for entry: String in strength:
				var stat := entry.trim_prefix("-")
				var step: float = float(stats[stat]) / maxf(float(below[stat]), 0.001)
				if entry.begins_with("-"):
					step = 1.0 / step
				var ok := int(stats[stat]) == int(below[stat]) + 1 if stat == "max_charges" \
						else absf(step - ItemDB.RIG_TIER_STEP) < 0.03
				t.check(ok, "%s: %s is %s (Mk%d: %s)" % [id, stat, str(stats[stat]), i, str(below[stat])])
			t.check(not ItemDB.has_tag(id, "vendor") and not ItemDB.has_tag(id, "starter")
					and ItemDB.item_rarity(id) >= ItemDB.Rarity.RARE and not Economy.is_shop_item(id),
					"%s is never sold or handed out" % id)
			t.check(ItemDB.item_rarity(id) >= ItemDB.item_rarity(ids[i - 1]) and ItemDB.item_value(id) > ItemDB.item_value(ids[i - 1]),
					"%s is at least as rare and worth more than the tier below" % id)
			# Mastery follows gear type tags, so every tier trains the same track.
			var tags: Array = ItemDB.get_item(id)["tags"]
			t.check(tags == ItemDB.get_item(ids[1])["tags"], "%s trains the same mastery as its other tiers" % id)
			t.check(StashRules.storable(id), "%s can be stashed" % id)
			rig.free()


## Everything that drops is Mk1 (DESIGN.md section 10): no world's loot
## table holds a rig or helmet above Mk1, since Mk2 and up are crafted from
## blueprints. Mk1 rigs and helmets still drop on Ashfront's rooftops.
static func _test_loot(t: Node) -> void:
	var found: Array = []
	for world: Script in [ASHFRONT, FROSTLINE]:
		for value: Variant in world.get_script_constant_map().values():
			if value is Array:
				for entry: Variant in value:
					if entry is Dictionary and (entry as Dictionary).has("id"):
						found.append(entry["id"])
	t.check(not found.is_empty(), "the worlds' loot tables can be read (%d entries)" % found.size())
	for family: String in FAMILIES:
		for id: String in FAMILIES[family].slice(1):
			t.check(id not in found, "%s never drops: it is crafted" % id)
	var helmets := ItemDB.all_ids().filter(func(id: String) -> bool:
		return ItemDB.has_tag(id, "helmet") and id.ends_with("_mk2"))
	t.check(helmets.size() >= 4, "there are Mk2 helmets to check (%d)" % helmets.size())
	for id: String in helmets:
		t.check(id not in found and not Economy.is_shop_item(id), "%s is never found or sold: it is crafted" % id)
	var rooftop: Array = ASHFRONT.ROOFTOP_TABLE.map(func(e: Dictionary) -> String: return e["id"])
	t.check(rooftop.has("wings_glide") and rooftop.has("boots_thruster"), "Mk1 rigs drop on Ashfront's rooftops")
	t.check(rooftop.has("helm_spotter") and rooftop.has("helm_ember"), "Mk1 helmets drop on Ashfront's rooftops")


## The ceiling only limits lift: a climb eases off under it, and a kick or
## pulse near it is cut so it tops out there, or refused without heat.
static func _test_ceiling_rules(t: Node) -> void:
	var rig := FlightRig.new()
	rig.enabled = true
	rig.burst_velocity = 14.0
	rig.burst_heat = 20.0
	rig.ceiling = 25.0
	rig.altitude = 60.0
	t.check(is_equal_approx(rig.climb_room(), 1.0) and rig.lift_cap(20.0) == INF,
			"a rig that does not know its altitude has no ceiling")
	rig.altitude_known = true
	rig.altitude = 10.0
	t.check(is_equal_approx(rig.climb_room(), 1.0) and rig.try_burst(rig.lift_cap(20.0)) == 14.0,
			"well under the ceiling a rig climbs and kicks in full")
	rig.altitude = 23.0
	t.check(rig.climb_room() > 0.0 and rig.climb_room() < 1.0, "the climb eases off just under the ceiling")
	var cap := rig.lift_cap(20.0)
	var kick := rig.try_burst(cap)
	t.check(kick > 0.0 and kick < 14.0 and is_equal_approx(kick * kick / 40.0, 2.0),
			"a kick near the ceiling tops out on it (%.1f m/s)" % kick)
	var heat := rig.heat
	rig.altitude = 25.0
	t.check(rig.at_ceiling() and rig.try_burst(rig.lift_cap(20.0)) == 0.0 and rig.heat == heat,
			"at the ceiling a kick is refused and costs nothing")
	rig.pulse_velocity = 11.0
	rig.pulse_heat = 10.0
	t.check(rig.try_pulse(rig.lift_cap(20.0)) == 0.0 and rig.heat == heat, "so is a wing pulse")
	rig.ceiling = 0.0
	t.check(rig.try_burst(rig.lift_cap(20.0)) == 14.0, "a ceiling of 0 means none")
	rig.free()
	var actor := Actor.new()
	t.check(is_nan(actor.ground_level()), "outside a raid nothing says where the ground is")
	actor.free()


## Every rig climbs from the street flown its own way (the feel bench's
## climb, all at once on their own patches of ground). Each tier reaches its
## heights, none goes over its ceiling, and nothing jolts on the way.
static func _test_climbs(t: Node) -> void:
	var results := {}
	var index := 0
	for family: String in FAMILIES:
		for id: String in FAMILIES[family]:
			var arena := Node3D.new()
			t.add_child(arena)
			arena.position = Vector3(-6000.0 + index * 400.0, 0, 6000)
			index += 1
			var ground := StaticBody3D.new()
			ground.collision_layer = Actor.LAYER_WORLD
			var shape := BoxShape3D.new()
			shape.size = Vector3(300, 1, 300)
			var col := CollisionShape3D.new()
			col.shape = shape
			ground.add_child(col)
			ground.position.y = -0.5
			arena.add_child(ground)
			var actor := Actor.new()
			arena.add_child(actor)
			Loadout.equip(actor, ["pistol_service", id])
			actor.position = Vector3(0, 0.05, 0)
			actor.ground_map = arena
			_climb_one(t, actor, id, results)
	await t.frames(10)
	for i in 60 * 60:
		if results.size() == index:
			break
		await t.frames(1)
	for family: String in FAMILIES:
		for id: String in FAMILIES[family]:
			var r: Dictionary = results.get(id, {})
			if r.is_empty():
				t.check(false, "%s finished its climb" % id)
				continue
			var reach: float = r["ceiling"] - 1.5 if family == "jetpack" else (8.0 if family == "boots" else 3.0)
			t.check(r["top"] >= reach, "%s climbs to %.0f m (%.1f m, %.0f s)" % [id, reach, r["top"], r["at"]])
			if family == "wings":
				t.check(r["top"] < 8.0, "%s cannot climb on its own: a launch and two boosts (%.1f m)" % [id, r["top"]])
			t.check(r["top"] <= r["ceiling"] + 0.25, "%s never goes over its %.0f m ceiling (%.1f m)" % [id, r["ceiling"], r["top"]])
			t.check(r["jolt"] <= 45.0, "%s climbs without a jolt (%.0f m/s²)" % [id, r["jolt"]])
			(r["actor"] as Actor).get_parent().queue_free()


## Climbs one actor as high as it will go and files the result under `id`.
static func _climb_one(t: Node, actor: Actor, id: String, results: Dictionary) -> void:
	var tier := actor.flight.tier
	var jolt := [0.0]
	var last := [actor.velocity]
	var step := func(count: int, move: String) -> void:
		for i in count:
			await t.get_tree().physics_frame
			if not move.begins_with("!"):
				jolt[0] = maxf(jolt[0], (actor.velocity - last[0]).length() * Engine.physics_ticks_per_second)
			last[0] = actor.velocity
	await t.frames(3)
	var top: Vector2 = await FeelBench.climb(actor, 40.0, step)
	results[id] = {"actor": actor, "tier": tier, "top": top.x, "at": top.y, "ceiling": actor.flight.ceiling, "jolt": jolt[0]}


## In a raid the ceiling is measured from the map's ground, not a roof.
static func _test_raid_ground(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 70, ["rifle_scrap", "jetpack_mk1"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(20)
	var p := raid.player
	var ground: float = raid.map.call("ground_height", p.global_position.x, p.global_position.z)
	t.check(is_equal_approx(p.ground_level(), ground), "in Ashfront the ground is the terrain under you")
	p.global_position.y = ground + 45.0
	p.velocity = Vector3.ZERO
	await t.frames(2)
	t.check(p.flight.altitude_known and absf(p.flight.altitude - 45.0) < 2.0,
			"the rig knows its height over the ground (%.1f m)" % p.flight.altitude)
	p.cmd.secondary = true
	p.cmd.jump = true
	await t.frames(30)
	t.check(p.flight.is_hovering and p.velocity.y <= 0.05,
			"above its ceiling a Mk1 jetpack holds you up but climbs no higher")
	p.cmd.jump = false
	p.cmd.secondary = false
	raid.queue_free()
	await t.frames(2)


## A rig set up from an item's stats, the way `Loadout.equip` does it.
static func _rig(id: String) -> FlightRig:
	var rig := FlightRig.new()
	Loadout._apply_stats(rig, ItemDB.item_stats(id))
	return rig
