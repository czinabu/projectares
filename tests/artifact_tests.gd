extends RefCounted
## Checks for artifacts (DESIGN.md section 6): the items, one per outing on
## the watch, each effect and its counter, where they drop, and that they go
## home, drop on death and fit the stash and the base. Kept in its own file
## and called from the test runner.

const StashRules := preload("res://core/account/stash_rules.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const Economy := preload("res://core/economy/economy.gd")
const EFFECTS := ["rewind", "cloak", "overclock", "bloom"]


static func run(t: Node) -> void:
	_items(t)
	await _rewind(t)
	await _cloak(t)
	await _overclock(t)
	await _bloom(t)
	await _drops_and_results(t)


static func _artifact_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "artifact"):
			ids.append(id)
	return ids


static func _items(t: Node) -> void:
	print("Artifacts: items")
	var ids := _artifact_ids()
	t.check(ids.size() >= 4, "there are artifacts to find (%d)" % ids.size())
	var rules := true
	for id in ids:
		rules = rules and ItemDB.item_rarity(id) == ItemDB.Rarity.RELIC and not ItemDB.has_tag(id, "vendor") \
				and not Economy.is_shop_item(id) and StashRules.storable(id) and Loadout.fits("artifact", id) \
				and ItemDB.item_stats(id).get("effect", "") in EFFECTS and BaseLayout.kind_for(id) == "artifact_case"
	t.check(rules, "artifacts are relics, never sold, kept in the stash, worn in the artifact slot and shown in the case")
	t.check("artifact" in Loadout.OPTIONAL_SLOTS and BaseLayout.spots("artifact_case") >= 1,
			"the artifact slot is optional, and even the starter bunker has a case for one")

	var a := Actor.new()
	Loadout.equip(a, ["artifact_rewind", "artifact_cloak"])
	t.check(a.artifact.enabled and a.artifact.item_id == "artifact_rewind" and "artifact_rewind" in a.gear_items
			and "artifact_cloak" in a.inventory.items and "artifact_cloak" not in a.gear_items,
			"one artifact per outing: the first goes on the watch, a second is only carried")
	a.free()

	var cmd := ActorCommand.new()
	cmd.artifact_pressed = true
	var back := ActorCommand.new()
	back.apply_array(cmd.to_array())
	t.check(back.artifact_pressed and ActorCommand.ONE_SHOT_MASK & ActorCommand.FLAG_ARTIFACT_PRESSED != 0,
			"using the artifact travels in the command as a one-tick press")
	cmd.clear_one_shots()
	t.check(not cmd.artifact_pressed, "the press lasts one tick")

	var stash: Array[String] = ["artifact_cloak", "artifact_bloom"]
	var kit := StashRules.checkout(stash, {"artifact": "artifact_cloak"}, Worlds.get_world("ashfront"))
	t.check("artifact_cloak" in kit and "artifact_cloak" not in stash and "artifact_bloom" in stash,
			"deploying takes the chosen artifact out of the stash")
	var plan := BaseLayout.plan(["artifact_cloak"], {"artifact": "artifact_cloak"})
	t.check(plan.size() == 1 and plan[0].kind == "artifact_case" and plan[0].slot == "artifact" and plan[0].equipped,
			"the base shows an owned artifact in its case, marked when it is in the loadout")
	var home := Hud.base_watch_slots("Base", {"artifact": "artifact_cloak"})
	var at := Hud.Wrist.SLOTS.find("artifact")
	t.check(home[at].detail == "Phase Cloak" and not home[at].empty,
			"at home the watch's artifact icon names the one going out")


## A raid with `kit` on a floor of our own high above the field, bots idle.
static func _floor_raid(t: Node, p_seed: int, kit: Array[String]) -> Raid:
	var raid: Raid = await t._kit_raid(p_seed, kit)
	var floor_at := Vector3(0, 400, 4000)
	var floor := StaticBody3D.new()
	floor.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	var col := CollisionShape3D.new()
	col.shape = shape
	floor.add_child(col)
	raid.add_child(floor)
	floor.global_position = floor_at - Vector3(0, 0.5, 0)
	for bot in raid.bots:
		bot.global_position = floor_at + Vector3(randf_range(-80, 80), 0, 90)
	raid.player.global_position = floor_at
	raid.player.protected_left = 0.0
	raid.player.flight.ceiling = 0.0
	await t.frames(15)
	return raid


static func _press(t: Node, p: Actor) -> void:
	p.cmd.artifact_pressed = true
	await t.frames(1)
	p.cmd.artifact_pressed = false
	await t.frames(1)


static func _rewind(t: Node) -> void:
	print("Artifacts: Time Rewind")
	var raid := await _floor_raid(t, 71, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "artifact_rewind"])
	var p := raid.player
	var slot := Hud.watch_slots(raid, p)[Hud.Wrist.SLOTS.find("artifact")]
	t.check(not slot.empty and slot.detail == "Time Rewind" and slot.value == "1" and "click" in slot.hints,
			"the watch's artifact icon names it, counts its uses and offers a click")
	# Remember only time on our floor, not the drop in.
	p.artifact.attune(p.artifact.item_id)
	var start := p.global_position
	await t.frames(60)
	p.global_position = start + Vector3(8, 0, 0)
	Combat.deal(p, DamageInfo.make(40.0, raid.bots[0], "bullet"))
	var hurt := p.health.health
	await t.frames(5)
	await _press(t, p)
	t.check(p.global_position.distance_to(start) < 1.5,
			"Time Rewind snaps you back to where you were (%.1f m off)" % p.global_position.distance_to(start))
	t.check(p.health.health > hurt and is_equal_approx(p.health.health, p.health.max_health), "and as healthy as you were (%.0f from %.0f)" % [p.health.health, hurt])
	t.check(p.artifact.last_trail.size() >= 2 and p.artifact.last_trail[-1].distance_to(start + Vector3(8, 0, 0)) < 1.0,
			"it leaves a trail from where you were to where you went back to")
	var now := p.global_position
	p.global_position = now + Vector3(5, 0, 0)
	await t.frames(30)
	await _press(t, p)
	t.check(p.artifact.is_spent() and p.global_position.distance_to(now + Vector3(5, 0, 0)) < 1.0,
			"it works once an outing")
	slot = Hud.watch_slots(raid, p)[Hud.Wrist.SLOTS.find("artifact")]
	t.check(slot.empty and slot.detail.contains("spent") and slot.hints.is_empty(), "a spent artifact shows spent on the watch")
	await t._end_raid(raid)


static func _cloak(t: Node) -> void:
	print("Artifacts: Phase Cloak")
	var raid := await _floor_raid(t, 72, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "artifact_cloak"])
	var p := raid.player
	var bot: Actor = raid.bots[0]
	bot.global_position = p.global_position + Vector3(0, 0, -12)
	bot.cmd.yaw = PI
	await t.frames(3)
	var brain: BotBrain = bot.get_node("Brain")
	t.check(brain._find_target() == p, "a bot facing you sees you")
	raid.begin_sign_out(p)
	await _press(t, p)
	t.check(p.is_cloaked() and p.artifact.cooldown_left > 0.0, "Phase Cloak hides you and goes on cooldown")
	t.check(brain._find_target() == null, "a bot does not see a cloaked player at range")
	bot.global_position = p.global_position + Vector3(0, 0, -3)
	await t.frames(2)
	t.check(brain._find_target() == p, "but notices one right beside it")
	var state := raid.state_for(p)
	var left := state.sign_out_left
	await t.frames(30)
	t.check(is_equal_approx(state.sign_out_left, left), "a sign-out waits while you are cloaked")
	(p.weapons[0] as Gun).fired.emit(p.get_eye_position(), p.get_eye_position() + Vector3.FORWARD)
	t.check(not p.is_cloaked(), "firing breaks the cloak")
	await t.frames(30)
	t.check(state.sign_out_left < left, "and the sign-out carries on")
	await t._end_raid(raid)


static func _overclock(t: Node) -> void:
	print("Artifacts: Overclock Core")
	var raid := await _floor_raid(t, 73, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "artifact_overclock"])
	var p := raid.player
	await _press(t, p)
	t.check(p.artifact.is_active() and p.flight.heat_free, "Overclock Core starts")
	p.cmd.jump_pressed = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	p.cmd.jump = true
	await t.frames(90)
	t.check(not p.is_on_floor() and p.flight.heat < 1.0, "the rig flies with no heat (%.1f)" % p.flight.heat)
	p.artifact.active_left = 0.05
	await t.frames(5)
	t.check(not p.flight.heat_free and p.flight.overheated and is_equal_approx(p.flight.heat, p.flight.max_heat),
			"when it ends the rig locks up overheated")
	p.cmd.jump = false
	await t._end_raid(raid)


static func _bloom(t: Node) -> void:
	print("Artifacts: Static Bloom")
	var raid := await _floor_raid(t, 74, ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "artifact_bloom"])
	var p := raid.player
	var near: Actor = raid.bots[0]
	var far: Actor = raid.bots[1]
	for bot in [near, far]:
		bot.flight.enabled = true
		bot.flight.thrust_accel = 20.0
	near.global_position = p.global_position + Vector3(6, 0, 0)
	far.global_position = p.global_position + Vector3(60, 0, 0)
	await t.frames(3)
	await _press(t, p)
	t.check(not p.flight.working() and not near.flight.working() and far.flight.working(),
			"Static Bloom shuts off every rig near you, yours included, and none further out")
	t.check(not p.flight.can_hover() and p.flight.try_burst() == 0.0, "a jammed rig does nothing")
	await t.frames(roundi(p.artifact.jam_time * 60.0) + 20)
	t.check(p.flight.working() and near.flight.working(), "rigs come back after a few seconds")
	await t._end_raid(raid)


static func _drops_and_results(t: Node) -> void:
	print("Artifacts: drops, going home and dying")
	var world := Worlds.get_world("ashfront")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var found := {}
	for i in 100:
		found[world.roll_artifact(rng, 1.0)] = true
	t.check(found.size() == _artifact_ids().size() and found.keys().all(func(id: String) -> bool:
			return ItemDB.has_tag(id, "artifact")), "every artifact can drop")
	t.check(world.roll_artifact(rng, 0.0) == "" and world.warlord_artifact_chance > 0.0
			and Worlds.get_world("frostline").warlord_artifact_chance == 0.0
			and Worlds.get_world("frostline").pod_artifact_chance == 0.0,
			"warlords carry them in the war worlds, not in the gentle one")

	var kit: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "artifact_cloak"]
	var raid: Raid = await t._kit_raid(75, kit)
	var chance := world.warlord_artifact_chance
	world.warlord_artifact_chance = 1.0
	raid.start_event("warlord")
	world.warlord_artifact_chance = chance
	var carried := false
	for bot: Actor in raid._event_bots:
		carried = carried or bot.inventory.count_with_tag("artifact") > 0
	t.check(carried, "a warlord can carry an artifact to take off him")

	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, result: Dictionary) -> void: results.append(result))
	raid._leave(raid.state_for(raid.player))
	t.check(results.size() == 1 and "artifact_cloak" in results[0].kept_gear,
			"signing out takes the artifact home")
	await t._end_raid(raid)

	raid = await t._kit_raid(76, kit)
	results.clear()
	raid.player_finished.connect(func(_a: Actor, result: Dictionary) -> void: results.append(result))
	raid.player.kill("test")
	await t.frames(2)
	t.check(results.size() == 1 and "artifact_cloak" in results[0].lost,
			"dying in the war world drops the artifact with your bag")
	await t._end_raid(raid)
