extends RefCounted
## The `mastery` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashRules := preload("res://core/account/stash_rules.gd")
const MasteryDB := preload("res://core/progression/mastery_db.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const MasteryPanel := preload("res://core/progression/mastery_panel.gd")


static func run(t: Node) -> void:
	print("Mastery")
	# Data: every track is reachable from an item, and every variant names real
	# stats and changes at least two of them (a sidegrade, not an upgrade).
	var item_for := {}
	for id in ["rifle_scrap", "rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher",
			"blade_scrap", "blade_arc", "hammer_breaker", "knife_gutter", "axe_splitter", "spear_lancer", "chip_blink", "chip_barrier", "chip_pulse",
			"plate_light", "frame_runner", "frame_trooper", "frame_bulwark"]:
		item_for[MasteryDB.track_for_item(id)] = id
	t.check(not item_for.has("") and item_for.size() == MasteryDB.TRACKS.size(),
			"every weapon, ability and frame trains a mastery track, and every track has gear")
	t.check(MasteryDB.track_for_item("jetpack_mk1") == "" and MasteryDB.track_for_item("medkit") == "",
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
	t.check(bad.is_empty(), "every variant changes real stats with a tradeoff %s" % [bad])

	# Levels and picks.
	t.check(MasteryDB.level_for_xp(0) == 0 and MasteryDB.level_for_xp(150) == 1
			and MasteryDB.level_for_xp(99999) == MasteryDB.max_level(), "XP maps to levels")
	var book := MasteryBook.new()
	t.check(not book.pick("rifle", "long_barrel"), "a locked variant cannot be picked")
	t.check(book.add_xp("rifle", 450) == 2 and book.level("rifle") == 2, "XP raises the level")
	t.check(book.pick("rifle", "long_barrel") and book.active_picks() == {"rifle": "long_barrel"},
			"an unlocked variant can be picked")
	t.check(not book.pick("rifle", "cut_down"), "higher variants stay locked")
	t.check(book.add_xp("nonsense", 100) == 0 and not book.xp.has("nonsense"), "unknown tracks are ignored")
	var copy := MasteryBook.new()
	copy.load_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	t.check(copy.xp_for("rifle") == 450 and copy.picked("rifle") == "long_barrel", "mastery survives a save")
	copy.load_dict({"xp": {"rifle": 10}, "picks": {"rifle": "long_barrel", 5: "x"}})
	t.check(copy.picked("rifle") == "" and copy.active_picks().is_empty(),
			"a saved pick above the saved level is dropped")

	# Variants change the gear the player deploys with, and only theirs.
	var kit: Array[String] = ["rifle_carbine", "blade_scrap", "jetpack_mk1", "frame_runner", "chip_blink"]
	var stock: Raid = await t._mastery_raid(70, kit, {})
	var sp := stock.player
	var stock_gun := sp.weapons[0] as Gun
	var stock_spread := stock_gun.spread_deg
	var stock_interval := stock_gun.fire_interval
	var stock_armor := sp.health.max_armor
	var stock_speed := sp.walk_speed
	var stock_cd := sp.ability.cooldown
	await t._end_raid(stock)
	var picks := {"rifle": "long_barrel", "frame_light": "stripped", "blink": "ward_step"}
	var raid: Raid = await t._mastery_raid(70, kit, picks)
	var p := raid.player
	var gun := p.weapons[0] as Gun
	t.check(gun.spread_deg < stock_spread and gun.fire_interval > stock_interval,
			"Long Barrel: tighter spread, slower fire")
	t.check(p.health.max_armor < stock_armor and p.walk_speed > stock_speed, "Stripped frame: less armor, faster")
	t.check(p.ability.cooldown > stock_cd and p.ability.blink_shield > 0.0, "Ward Step: shield, longer cooldown")
	var bot := raid.bots[0]
	var stock_bots := true
	for other in raid.bots:
		for w in other.weapons:
			var stats := ItemDB.item_stats(w.item_id)
			if w is Gun and stats.has("spread_deg") and not is_equal_approx((w as Gun).spread_deg, stats.spread_deg):
				stock_bots = false
	t.check(stock_bots and raid.mastery.actor == p, "bots deploy without the player's variants")

	# Ward Step: arriving from a blink is shielded.
	p.ability.activate()
	var before := p.health.health + p.health.armor
	Combat.deal(p, DamageInfo.make(20.0, bot, "bullet"))
	var loss: float = before - (p.health.health + p.health.armor)
	t.check(loss > 0.0 and loss < 10.0, "Ward Step shields you right after the blink (lost %.1f of 20)" % loss)

	# XP is earned by type: weapon hits and kills, ability uses, hits taken in the frame.
	var tracker := raid.mastery
	t.check(tracker.earned.get("blink", 0.0) >= tracker.xp_per_ability_use, "using an ability trains it")
	t.check(tracker.earned.get("frame_light", 0.0) > 0.0, "taking hits trains your frame")
	p._draw_weapon(p.weapon_for_key(1))
	Combat.deal(bot, DamageInfo.make(30.0, p, "bullet"))
	t.check(is_equal_approx(tracker.earned.get("rifle", 0.0), 30.0 * tracker.xp_per_damage),
			"hitting with a rifle trains rifle mastery")
	var bot_hp := bot.health.health + bot.health.armor + 1.0
	Combat.deal(bot, DamageInfo.make(bot_hp, p, "bullet"))
	t.check(bot.is_dead and tracker.earned.rifle >= bot_hp * tracker.xp_per_damage + tracker.xp_per_kill,
			"kills give bonus XP")
	t.check(not tracker.earned.has("blade"), "a holstered weapon earns nothing")

	# Dying keeps every point of mastery earned.
	Profile.reset()
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	p.kill("storm")
	await t.frames(2)
	var gained: Dictionary = results[0].get("mastery_xp", {}) if results.size() == 1 else {}
	t.check(results.size() == 1 and results[0].outcome == "died" and gained.get("rifle", 0) > 0,
			"the raid result reports mastery XP even on death")
	t.check(Profile.mastery.xp_for("rifle") == gained.get("rifle", -1)
			and Profile.mastery.xp_for("blink") == gained.get("blink", -1), "dying banks that XP in the profile")
	t.check(Profile.stash.is_empty(), "the gear itself is still lost")
	await t._end_raid(raid)

	# Leaving alive pays no bonus, so signing out again and again trains nothing.
	raid = await t._mastery_raid(71, kit, {})
	t.check(raid.mastery.report().is_empty(), "carrying gear alone earns no mastery")
	await t._end_raid(raid)

	# Hub: the panel shows the tracks of your loadout and what a raid earned.
	Profile.reset()
	Profile.loadout = StashRules.starter_loadout()
	var panel := MasteryPanel.new()
	t.add_child(panel)
	t.check(panel.loadout_tracks() == ["rifle", "blade", "frame_light"],
			"the scrap kit shows its mastery")
	Profile.mastery.add_xp("rifle", 200)
	var text := panel.describe_earned({"mastery_xp": {"rifle": 100}})
	t.check("Rifle +100" in text and "level 1!" in text, "the hub announces a level up")
	panel.refresh()
	await t.frames(1)
	t.check(panel._rows.get_child_count() == 3, "one row per loadout track")
	panel.queue_free()
	Profile.reset()


# --- Online ------------------------------------------------------------------
