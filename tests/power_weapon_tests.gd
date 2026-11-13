extends RefCounted
## Checks for power weapons: the four sci-fi guns, power racks and the
## watch's heavy chamber they are scanned into and summoned from, where they
## turn up, and that they never reach a stash. Kept in its own file and called from the test runner.

const PowerArmory := preload("res://core/war/power_armory.gd")
const StashRules := preload("res://core/account/stash_rules.gd")


static func run(t: Node) -> void:
	print("Power weapons: items")
	var ids := PowerArmory.all_power_ids()
	t.check(ids.size() == 4, "there are four power weapons (%d)" % ids.size())
	var data_only := true
	for id in ids:
		data_only = data_only and ItemDB.has_tag(id, "firearm") and not ItemDB.has_tag(id, "vendor") \
				and not StashRules.storable(id) and ItemDB.item_rarity(id) == ItemDB.Rarity.EPIC
	t.check(data_only, "power weapons are epic firearms that are never sold or stored")
	var kinds := {}
	for id in ids:
		kinds[ItemDB.item_stats(id).get("damage_kind", "bullet")] = true
	t.check(not kinds.has("bullet"), "every power weapon fires something sci-fi, not bullets (%s)" % [kinds.keys()])

	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 91)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(30)
	var p := raid.player
	# Clear ground: high above the field, on a floor of our own.
	var floor_at := Vector3(0, 400, 4000)
	var floor := StaticBody3D.new()
	floor.collision_layer = Actor.LAYER_WORLD
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(200, 1, 200)
	var floor_col := CollisionShape3D.new()
	floor_col.shape = floor_shape
	floor.add_child(floor_col)
	raid.add_child(floor)
	floor.global_position = floor_at - Vector3(0, 0.5, 0)
	for bot in raid.bots:
		bot.global_position = floor_at + Vector3(randf_range(-80, 80), 0, 90)
	p.global_position = floor_at
	p.protected_left = 0.0
	await t.frames(10)

	print("Power weapons: racks and the power slot")
	var rack := raid.spawn_container(["power_rail_lance"], false, LootContainer.RACK_LABEL, floor_at + Vector3(0, 0, -2))
	await t.frames(2)
	raid.player = p
	t.check(rack.is_rack() and rack.get_prompt() == "[F] Scan Rail Lance into your watch",
			"a rack offers its power weapon: %s" % rack.get_prompt())
	var weapon_count := p.weapons.size()
	var pack_before := p.inventory.items.duplicate()
	var kit_guns := p.weapons.duplicate()
	var changes := []
	p.power_changed.connect(func(id: String, mag: int, reserve: int) -> void: changes.append([id, mag, reserve]))
	var in_hand := p.get_active_weapon()
	rack.interact(p)
	await t.frames(2)
	t.check(Loadout.power_index(p) >= 0 and p.weapons.size() == weapon_count + 1 and p.get_active_weapon() == in_hand,
			"scanning it fills the watch's heavy chamber, and what you held stays in hand")
	t.check(p.weapon_for_key(1) != Loadout.power_index(p) and not p.slot_order().has(Loadout.power_index(p))
			and p.weapon_for_key(4) == -1 and not InputMap.has_action("weapon_4"),
			"no key and no wheel turn draws it: only the watch")
	var carousel: Array = Hud.weapon_entries(p).map(func(e: Dictionary) -> String: return e.id)
	t.check(carousel.has("power_rail_lance"), "it is on the watch's weapon carousel: %s" % ", ".join(carousel))
	await _summon_heavy(t, p)
	var held := p.get_active_weapon() as Gun
	t.check(held != null and held.item_id == "power_rail_lance" and Loadout.power_index(p) == p.active_weapon_index,
			"summoned from the watch, it is in hand")
	var kept_kit := true
	for w in kit_guns:
		kept_kit = kept_kit and w in p.weapons
	t.check(kept_kit and rack.items.is_empty() and "power_rail_lance" in p.gear_items and p.inventory.items == pack_before,
			"your own weapons stay with you, and nothing goes in the pack")
	t.check(changes.size() == 1 and changes[0][0] == "power_rail_lance", "the change is announced for the network")
	t.check(held.controls_hint().contains("charge") and held.status_text().contains("4 shots"),
			"the rail lance tells you to charge it and counts its shots")

	print("Power weapons: Rail Lance")
	var a := raid.bots[0]
	var b := raid.bots[1]
	var c := raid.bots[2]
	for bot in [a, b, c]:
		bot.health.set_armor(0.0)
		bot.health.health = bot.health.max_health
	a.global_position = floor_at + Vector3(0, 0, -10)
	b.global_position = floor_at + Vector3(0, 0, -14)
	c.global_position = floor_at + Vector3(0, 0, -18)
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(4, 4, 0.3)
	var wall_col := CollisionShape3D.new()
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	raid.add_child(wall)
	wall.global_position = floor_at + Vector3(0, 1.5, -6)
	await t.frames(5)
	p.cmd.aim_dir = (a.global_position + Vector3(0, 1.0, 0) - p.get_eye_position()).normalized()
	var before := held.ammo_in_mag
	p.cmd.primary = true
	await t.frames(20)
	t.check(held.ammo_in_mag == before and held.charge_fraction() > 0.1, "holding the trigger charges, nothing fires yet")
	p.cmd.primary = false
	await t.frames(2)
	t.check(held.charge_fraction() == 0.0 and held.ammo_in_mag == before, "letting go early wastes nothing")
	p.cmd.primary = true
	for i in 70:
		await t.frames(1)
		if held.ammo_in_mag < before:
			break
	p.cmd.primary = false
	t.check(held.ammo_in_mag == before - 1, "a full charge fires one slug")
	t.check(a.health.health < a.health.max_health and b.health.health < b.health.max_health
			and c.health.health < c.health.max_health,
			"the slug goes through the wall and three bodies in a row")
	t.check(c.health.health > a.health.health,
			"it loses some punch at each thing it passes")
	wall.queue_free()

	print("Power weapons: spent weapons")
	held.ammo_in_mag = 0
	held.reserve_ammo = 0
	t.check(held.is_spent() and held.status_text().contains("spent"), "an empty power weapon says it is spent")
	await t.frames(2)
	t.check(Loadout.power_index(p) < 0 and p.weapons.size() == weapon_count and p.get_active_weapon() != null
			and not "power_rail_lance" in p.gear_items and changes.back()[0] == "",
			"a spent power weapon is thrown away and you hold one of your own again")

	print("Power weapons: Helion and heat lock")
	for bot in [a, b, c]:
		bot.global_position = floor_at + Vector3(60, 0, 60)
	# Fresh targets: the slug may have killed the first ones.
	a = raid.bots[3]
	b = raid.bots[4]
	c = raid.bots[5]
	for bot in [a, b, c]:
		bot.health.set_armor(0.0)
	rack.set_items(["power_helion"])
	rack.interact(p)
	await t.frames(2)
	await _summon_heavy(t, p)
	var helion := p.get_active_weapon() as Gun
	t.check(helion.item_id == "power_helion" and rack.items.is_empty(), "a restocked rack hands out another")
	a.global_position = floor_at + Vector3(3, 0, -20)
	b.global_position = floor_at + Vector3(-8, 0, -24)
	await t.frames(3)
	a.flight.enabled = true
	a.flight.heat = a.flight.max_heat * 0.8
	var locked := Gun.heat_target(p, Vector3.FORWARD, helion.heat_seek_cone, helion.heat_seek_range)
	t.check(locked == a, "a rocket locks onto a hot jetpack near the aim, not a cold body")
	a.flight.heat = 0.0
	t.check(Gun.heat_target(p, Vector3.FORWARD, helion.heat_seek_cone, helion.heat_seek_range) == null,
			"with no heat there is nothing to lock")
	var a_before := a.health.health
	var b_before := b.health.health
	b.global_position = a.global_position + Vector3(2.5, 0, 0)
	await t.frames(3)
	p.cmd.aim_dir = (a.global_position + Vector3(0, 1.0, 0) - p.get_eye_position()).normalized()
	p.cmd.primary = true
	await t.frames(2)
	p.cmd.primary = false
	t.check(helion.ammo_in_mag == 0 and helion.reserve_ammo == 3, "the launcher fires one rocket")
	var rounds := raid.get_children().filter(func(n: Node) -> bool: return n is Gun.Round)
	t.check(rounds.size() == 1, "the rocket is a round in flight, not a hitscan shot")
	await t.frames(60)
	t.check(a.health.health < a_before and b.health.health < b_before,
			"its plasma burst hurts the target and whoever stands beside it")
	t.check(raid.get_children().filter(func(n: Node) -> bool: return n is Gun.Round).is_empty(),
			"the round is gone once it bursts")

	print("Power weapons: Arc Mortar")
	rack.set_items(["power_arc_mortar"])
	t.check(rack.get_prompt() == "[F] Scan Arc Mortar into your watch, leave your Helion Plasma Launcher",
			"holding one, the rack offers a trade: %s" % rack.get_prompt())
	rack.interact(p)
	await t.frames(2)
	await _summon_heavy(t, p)
	var mortar := p.get_active_weapon() as Gun
	t.check(mortar.item_id == "power_arc_mortar" and p.weapons.size() == weapon_count + 1
			and rack.items == (["power_helion"] as Array[String])
			and rack.ammo.get("power_helion", [[9, 9]])[0] == [0, 3],
			"you carry one at a time: the launcher goes on the rack with the shots it had left")
	for bot in raid.bots:
		if not bot.is_dead and not bot in [a, b, c]:
			a = bot
			break
	a.health.set_armor(0.0)
	a.global_position = floor_at + Vector3(0, 0, -12)
	# Behind a low wall: the charge has to be lobbed over it.
	var cover := StaticBody3D.new()
	cover.collision_layer = Actor.LAYER_WORLD
	var cover_shape := BoxShape3D.new()
	cover_shape.size = Vector3(6, 2.2, 0.4)
	var cover_col := CollisionShape3D.new()
	cover_col.shape = cover_shape
	cover.add_child(cover_col)
	raid.add_child(cover)
	cover.global_position = floor_at + Vector3(0, 1.1, -8)
	await t.frames(3)
	p.cmd.aim_dir = Vector3(0, 0.866, -0.5).normalized()
	p.cmd.primary = true
	await t.frames(2)
	p.cmd.primary = false
	t.check(mortar.ammo_in_mag == 5, "the mortar lobs one charge")
	await t.frames(150)
	t.check(a.health.health < a.health.max_health, "an arc charge lobbed over cover hurts whoever hides behind it")
	cover.queue_free()

	print("Power weapons: Storm Cannon")
	rack.set_items(["power_storm_cannon"])
	rack.ammo.clear()
	rack.interact(p)
	await t.frames(2)
	await _summon_heavy(t, p)
	var cannon := p.get_active_weapon() as Gun
	var full := cannon.ammo_in_mag
	p.cmd.aim_dir = Vector3.FORWARD
	p.cmd.primary = true
	await t.frames(20)
	t.check(cannon.ammo_in_mag == full and cannon.spin_fraction() > 0.2, "the cannon spins up before it fires")
	await t.frames(60)
	t.check(cannon.ammo_in_mag < full - 5, "spun up, it pours out shots")
	t.check(p.get_active_weapon().move_speed_mult() < 0.6, "fully spun, it slows you right down")
	p.cmd.primary = false
	await t.frames(90)
	t.check(cannon.spin_fraction() == 0.0 and is_equal_approx(cannon.move_speed_mult(), 1.0),
			"let go and the barrels spin down, and you speed up again")

	print("Power weapons: where they turn up")
	var armory := raid.armory
	t.check(armory.enabled() and armory._sites.size() == raid.strongpoints.size(),
			"every strongpoint has a power rack")
	var site_rack: LootContainer = armory._sites[0].rack
	t.check(site_rack.is_rack() and site_rack.items.is_empty(), "a strongpoint rack starts empty")
	var quiet_wait: float = armory._sites[0].restock_in
	raid.war.intensity = 1.0
	armory.tick(1.0)
	t.check(quiet_wait - float(armory._sites[0].restock_in) > 2.5, "an all-out war restocks racks three times as fast")
	armory._sites[0].restock_in = 0.01
	armory.tick(0.1)
	t.check(site_rack.items.size() == 1 and ItemDB.has_tag(site_rack.items[0], "power"),
			"a strongpoint rack is stocked with a power weapon")
	var pod_racks := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_rack())
	raid.event = {}
	raid.start_event("supply_pod")
	var after_pod := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_rack())
	t.check(after_pod.size() == pod_racks.size() + 1, "a supply pod brings a power weapon with it")
	var quiet_hits := 0
	var war_hits := 0
	raid.war.intensity = 0.0
	for i in 300:
		var spot := armory.on_cache_refilled(floor_at + Vector3(0, 0, 50))
		if spot:
			quiet_hits += 1
			spot.free()
	raid.war.intensity = 1.0
	for i in 300:
		var spot := armory.on_cache_refilled(floor_at + Vector3(0, 0, 50))
		if spot:
			war_hits += 1
			spot.free()
	t.check(quiet_hits > 0 and war_hits > quiet_hits * 2,
			"a refilled cache sometimes has a rack, far more often in a war (%d quiet, %d at war)" % [quiet_hits, war_hits])
	var frost := Worlds.get_world("frostline")
	t.check(frost.power_weapon_rate == 0.0 and Worlds.get_world("ashfront").power_weapon_rate > 0.0,
			"power weapons are a war-world thing: Frostline has none")

	print("Power weapons: death and going home")
	cannon.ammo_in_mag = 40
	var finished := []
	raid.player_finished.connect(func(_actor: Actor, result: Dictionary) -> void: finished.append(result))
	var racks_before := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_rack()).size()
	var death_spot := p.global_position
	p.kill("bullet")
	await t.frames(3)
	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return (n is LootContainer and (n as LootContainer).is_bag and not (n as LootContainer).is_rack()
				and (n as Node3D).global_position.distance_to(death_spot) < 3.0))
	var in_bags := false
	for bag: LootContainer in bags:
		in_bags = in_bags or "power_storm_cannon" in bag.items
	var dropped := raid.get_children().filter(func(n: Node) -> bool:
		return (n is LootContainer and (n as LootContainer).is_rack()
				and (n as Node3D).global_position.distance_to(death_spot) < 1.5))
	var racks_after := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_rack()).size()
	t.check(not in_bags and racks_after == racks_before + 1 and dropped.size() == 1,
			"a dead player's power weapon is left on a rack, not in the bag")
	if dropped.size() == 1:
		t.check((dropped[0] as LootContainer).ammo.get("power_storm_cannon", [[0, 0]])[0][0] == 40,
				"with the shots it had left")
	t.check(finished.size() == 1 and not "power_storm_cannon" in finished[0].lost
			and not "power_storm_cannon" in finished[0].brought_home, "a power weapon is never counted as lost or brought home")

	raid.queue_free()
	await t.frames(2)


## Draws the heavy chamber's weapon the way the watch does (a switch in the
## command) and waits out its materialize time, which must be there.
static func _summon_heavy(t: Node, p: Actor) -> void:
	p.cmd.switch_weapon = Loadout.power_index(p)
	await t.frames(2)
	p.cmd.switch_weapon = -1
	var heavy := p.get_active_weapon()
	t.check(heavy != null and ItemDB.has_tag(heavy.item_id, "power") and p.materialize_left > 0.0,
			"summoned, a heavy weapon materializes before it can fire (%.1f s)" % p.materialize_time)
	await t._wait_until(func() -> bool: return p.materialize_left <= 0.0, 300)
