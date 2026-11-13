extends RefCounted
## Checks for the watch's summon carousel (DESIGN.md section 3): the three
## tabs, the weapons, vehicles and artifacts carried, summoning a weapon out
## of the pack with its materialize time and the watch's rest, the squad
## ping, and the pop-ups. Kept in its own file and called from the test
## runner.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const KIT: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light"]


static func run(t: Node) -> void:
	_rules(t)
	await _summon(t)
	await _card(t)
	await _ping_and_popups(t)
	await _everywhere(t)
	await _at_home(t)


static func _rules(t: Node) -> void:
	print("Watch: summon rules")
	t.check(Loadout.summonable("rifle_carbine") and Loadout.summonable("knife_gutter")
			and Loadout.summonable("pistol_machine") and not Loadout.summonable("scrap_metal")
			and not Loadout.summonable("artifact_cloak") and not Loadout.summonable("bike_scrapper"),
			"the watch summons guns and melee weapons, nothing else")
	var power := ""
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "power"):
			power = id
	t.check(power != "" and not Loadout.summonable(power), "a heavy weapon is never summoned out of a pack")
	t.check(Loadout.summon_time("pistol_machine") < Loadout.summon_time("rifle_carbine")
			and Loadout.summon_time("knife_gutter") < Loadout.summon_time("rifle_carbine"),
			"heavier weapons take longer to materialize (pistol %.1f s, rifle %.1f s)"
			% [Loadout.summon_time("pistol_machine"), Loadout.summon_time("rifle_carbine")])
	var slow := true
	for id: String in ItemDB.all_ids():
		if Loadout.summonable(id):
			slow = slow and Loadout.summon_time(id) >= 0.3 and Loadout.summon_cooldown(id) > Loadout.summon_time(id) * 2.0
			if ItemDB.has_tag(id, "two_handed"):
				slow = slow and Loadout.summon_time(id) > Loadout.summon_time("knife_gutter")
	t.check(slow, "no weapon materializes at once, and the watch rests longer than the weapon takes")
	t.check(Loadout.weapon_slot("rifle_carbine") == "primary" and Loadout.weapon_slot("pistol_machine") == "sidearm"
			and Loadout.weapon_slot("knife_gutter") == "melee", "each weapon takes the slot of its kind")
	var tabs: Array = []
	for tab: String in Hud.Wrist.TABS:
		tabs.append_array(Hud.Wrist.TAB_SLOTS[tab])
	t.check(Hud.Wrist.TABS == ["summon", "status", "mission"] and tabs == Hud.Wrist.SLOTS
			and Hud.Wrist.tab_of("weapon") == "summon" and Hud.Wrist.tab_of("standing") == "status"
			and Hud.Wrist.tab_of("contract") == "mission" and Hud.Wrist.tab_of("leave") == "mission",
			"the card has three tabs, Summon, Status and Mission, and every icon is on one")


static func _summon(t: Node) -> void:
	print("Watch: summoning a weapon out of the pack")
	var raid: Raid = await t._kit_raid(81, KIT)
	var p := raid.player
	var state := raid.state_for(p)
	p.protected_left = 0.0
	p.inventory.add_item("scrap_metal")
	p.inventory.add_item("rifle_carbine")
	p.inventory.add_item("knife_gutter")
	var entries := Hud.weapon_entries(p)
	var ids: Array = entries.map(func(e: Dictionary) -> String: return e.id)
	t.check(ids == ["rifle_scrap", "pistol_service", "blade_scrap", "rifle_carbine", "knife_gutter"]
			and int(entries[0].index) >= 0 and int(entries[3].index) == -1,
			"the carousel lists the weapons worn, then the ones in the pack, and only weapons: %s" % ", ".join(ids))
	var changes := [0]
	var swaps: Array[String] = []
	raid.watch_changed.connect(func(_a: Actor) -> void: changes[0] += 1)
	p.weapon_swapped.connect(func(id: String, _mag: int, _reserve: int) -> void: swaps.append(id))
	t.check(raid.summon(p, "scrap_metal") != "" and raid.summon(p, "smg_stinger") != "" and swaps.is_empty(),
			"loot that is no weapon, and a weapon you do not carry, cannot be summoned")
	var carried := p.inventory.items.size()
	var worn := p.weapons.size()
	t.check(raid.summon(p, "rifle_carbine") == "" and swaps == (["rifle_carbine"] as Array[String]) and changes[0] == 1,
			"a weapon in the pack can be summoned")
	var gun := p.get_active_weapon() as Gun
	t.check(gun != null and gun.item_id == "rifle_carbine" and p.weapons.size() == worn
			and Loadout.worn_index(p, "primary") == p.active_weapon_index,
			"it materializes in your hand, in place of the primary you wore")
	t.check("rifle_carbine" in p.gear_items and "rifle_scrap" not in p.gear_items
			and p.inventory.has_item("rifle_scrap") and not p.inventory.has_item("rifle_carbine")
			and p.inventory.items.size() == carried and "rifle_carbine" in state.kit and "rifle_scrap" not in state.kit,
			"and the one you wore goes into the pack in its place, so the pack is no fuller")
	t.check("rifle_carbine" in p.get_drop_items() and "rifle_scrap" in p.get_drop_items(),
			"both are still what you would drop")
	t.check(p.materialize_left > 0.0 and is_equal_approx(p.materialize_time, Loadout.summon_time("rifle_carbine")),
			"it takes its time to materialize (%.1f s)" % p.materialize_time)
	var rounds := gun.ammo_in_mag
	t._aim_at(p, p.global_position + Vector3(0, 1.6, 30))
	p.cmd.primary = true
	p.cmd.primary_pressed = true
	await t.frames(10)
	p.cmd.primary_pressed = false
	t.check(gun.ammo_in_mag == rounds, "and cannot be fired until it has")
	await t.frames(ceili(p.materialize_time * 60.0) + 20)
	p.cmd.primary = false
	t.check(p.materialize_left <= 0.0 and gun.ammo_in_mag < rounds, "once it has, it fires")
	await t.frames(5)
	rounds = gun.ammo_in_mag
	var reserve := gun.reserve_ammo
	t.check(raid.summon_wait(p) > 0.0 and raid.summon(p, "knife_gutter") != "" and swaps.size() == 1
			and raid.summon_charge(p) < 1.0,
			"the watch rests after a summon (%.0f s), so weapons cannot be swapped freely in a fight" % raid.summon_wait(p))
	var slot := Hud.weapon_slot(raid, p, 3)
	t.check(float(slot.progress) >= 0.0 and "click" not in slot.hints and slot.detail.begins_with("Gutter Knife"),
			"the weapon icon shows the wait as a ring and offers no click")
	state.summon_ready_at = -INF
	slot = Hud.weapon_slot(raid, p, 3)
	t.check("click" in slot.hints and slot.detail.contains("pack") and int(slot.count) == 5 and int(slot.index) == 3,
			"rested, a weapon in the pack offers a click and says how long it takes: %s" % slot.detail)
	t.check(raid.summon(p, "knife_gutter") == "" and p.get_active_weapon().item_id == "knife_gutter"
			and p.inventory.has_item("blade_scrap") and p.materialize_time < Loadout.summon_time("rifle_carbine"),
			"a knife takes the melee slot and materializes faster")
	state.summon_ready_at = -INF
	t.check(raid.summon(p, "rifle_scrap") == "" and p.inventory.has_item("rifle_carbine"), "the old rifle can be summoned back")
	state.summon_ready_at = -INF
	t.check(raid.summon(p, "rifle_carbine") == "", "and the carbine again")
	gun = p.get_active_weapon() as Gun
	t.check(gun.ammo_in_mag == rounds and gun.reserve_ammo == reserve,
			"a gun put away comes back with the rounds it had, not a full magazine (%d/%d)" % [gun.ammo_in_mag, gun.reserve_ammo])
	state.summon_ready_at = -INF
	raid.begin_sign_out(p)
	t.check(raid.summon(p, "rifle_scrap") != "", "nothing is summoned while signing out")
	raid.begin_sign_out(p)
	# A client never decides.
	raid.mode = Raid.Mode.CLIENT
	t.check(raid.summon(p, "rifle_scrap") != "" and raid.ping(p) != "", "a client cannot summon or ping on its own")
	raid.mode = Raid.Mode.SOLO
	# What a remote copy does with the server's word.
	var copy := Actor.new()
	raid.add_child(copy)
	Loadout.equip(copy, KIT)
	var given := Loadout.swap_weapon(copy, "rifle_carbine", 7, 33)
	var shown := copy.get_active_weapon() as Gun
	t.check(given.id == "rifle_scrap" and shown.item_id == "rifle_carbine" and shown.ammo_in_mag == 7
			and shown.reserve_ammo == 33 and copy.inventory.items.is_empty() and copy.materialize_left > 0.0,
			"a copy of another player swaps the weapon it is told, with its rounds, and touches no pack")
	t.check(Loadout.swap_weapon(copy, "scrap_metal").id == "" and shown == copy.get_active_weapon(),
			"and ignores anything that is not a weapon")
	copy.queue_free()
	await t._end_raid(raid)


static func _card(t: Node) -> void:
	print("Watch: the carousel card")
	var kit: Array[String] = KIT.duplicate()
	kit.append("artifact_rewind")
	var raid: Raid = await t._kit_raid(82, kit)
	var p := raid.player
	p.inventory.add_item("rifle_carbine")
	p.inventory.add_item("artifact_cloak")
	p.inventory.add_item("medkit") if ItemDB.has_item("medkit") else null
	var slots := Hud.watch_slots(raid, p)
	var ids: Array = slots.map(func(s: Dictionary) -> String: return s.id)
	t.check(ids == Hud.Wrist.SLOTS and slots.all(func(s: Dictionary) -> bool: return s.tab == Hud.Wrist.tab_of(s.id)),
			"the card's icons, tab after tab: %s" % ", ".join(ids))
	t.check(Hud.pack_text(p).begins_with("Pack %d/%d" % [p.inventory.items.size(), p.inventory.capacity])
			and Hud.pack_text(p).contains("worth") and Hud.wrist_text(raid, p, {}, 0.0).contains("Pack "),
			"the pack is folded into Summon: how full it is and what it is worth (%s)" % Hud.pack_text(p))
	var contract: Dictionary = slots[Hud.Wrist.SLOTS.find("contract")]
	t.check(contract.empty and contract.tab == "mission" and slots[Hud.Wrist.SLOTS.find("leave")].detail == "Sign out",
			"Mission keeps a place for the contract, beside sign-out")
	t.check(Hud.artifact_entries(p) == (["artifact_rewind", "artifact_cloak"] as Array[String]),
			"the artifacts carried: the one attuned, then any in the pack")
	var relic: Dictionary = Hud.watch_slots(raid, p, 0, "", -1.0, 0.0, {"artifact": 1})[Hud.Wrist.SLOTS.find("artifact")]
	t.check(relic.detail.begins_with("Phase Cloak") and "click" not in relic.hints and int(relic.count) == 2,
			"an artifact in the pack is shown but cannot be used: one per outing (%s)" % relic.detail)

	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	var asked: Array[String] = []
	controller.summon_requested.connect(func(id: String) -> void: asked.append(id))
	controller.wrist_raised = true
	for i in 20:
		controller.scroll(-1)
	await t.frames(20)
	t.check(hud.wrist.focused_id() == "weapon" and not controller.is_picking_weapons() and controller.watch_open == ""
			and hud.wrist.card.focused_tab() == "summon" and hud.wrist.text().contains("Pack ")
			and "click" in hud.wrist.focused_hints() and not "wheel" in hud.wrist.focused_hints(),
			"with the watch up the wheel reaches the weapons icon, on the Summon tab, and offers a click to open it")
	controller.scroll(1)
	await t.frames(2)
	t.check(hud.wrist.focused_id() == "vehicle" and controller.weapon_pick == 0,
			"on the main row the wheel moves between icons, never through their lists (Caleb's call)")
	controller.scroll(-1)
	t.check(controller.watch_takes_fire() and controller.click_watch() and controller.watch_open == "weapon"
			and controller.is_picking_weapons() and controller.wrist_raised and asked.is_empty(),
			"a click opens the weapons, and nothing is drawn yet")
	await t.frames(20)
	t.check(hud.wrist.weapons_shown().size() == 4 and hud.wrist.get_node("Hologram/Weapons").visible
			and hud.wrist.get_node("Hologram/Weapons").get_child_count() == 4,
			"the weapons carried stand over the card as holograms")
	t.check(hud.wrist.text().begins_with("Scrap Rifle") and hud.wrist.text().contains("in hand"),
			"the weapon in your hand says so: %s" % hud.wrist.text().get_slice("\n", 0))
	controller.scroll(1)
	await t.frames(2)
	t.check(controller.weapon_pick == 1 and controller._pending_switch < 0 and hud.wrist.focused_id() == "weapon"
			and "click" in hud.wrist.focused_hints() and "wheel" in hud.wrist.focused_hints(),
			"opened, the wheel turns through the weapons without switching, and a worn one offers a click")
	var sidearm := int(Hud.weapon_entries(p)[1].index)
	t.check(controller.click_watch() and controller._pending_switch == sidearm and not controller.wrist_raised
			and asked.is_empty(), "a click on a worn weapon draws it and lowers the watch")
	controller._pending_switch = -1
	controller.wrist_raised = true
	controller.watch_focus_moved = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("weapon")
	controller.click_watch()
	controller.scroll(1)
	controller.scroll(1)
	await t.frames(2)
	t.check(controller.weapon_pick == 3 and hud.wrist.text().begins_with("Ashfront Carbine")
			and hud.wrist.text().get_slice("\n", 0).contains("pack"),
			"past the worn weapons come the ones in the pack: %s" % hud.wrist.text().get_slice("\n", 0))
	for i in 5:
		controller.scroll(1)
	await t.frames(2)
	t.check(hud.wrist.focused_id() == "weapon" and controller.weapon_pick == Hud.weapon_entries(p).size() - 1,
			"an opened list stops at its end; the wheel never leaves it")
	controller.weapon_pick = 3
	t.check(controller.watch_takes_fire() and controller.click_watch() and asked == (["rifle_carbine"] as Array[String])
			and controller._pending_switch < 0 and not controller.wrist_raised,
			"a click on one asks the world to summon it, and lowers the watch")
	controller.wrist_raised = true
	controller.watch_focus_moved = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("weapon")
	controller.click_watch()
	t.check(controller.close_watch_icon() and controller.watch_open == "" and not controller.is_picking_weapons(),
			"a right click closes the list, back to the icons")
	controller.scroll(1)
	controller.scroll(1)
	await t.frames(2)
	t.check(hud.wrist.focused_id() == "artifact" and not controller.is_on_artifact() and controller.watch_takes_fire(),
			"on the artifacts (one attuned, one carried) a click first opens them")
	controller.click_watch()
	controller.scroll(1)
	t.check(controller.artifact_pick == 1 and not controller.is_on_artifact() and not controller.watch_takes_fire(),
			"on a carried artifact a click does nothing")
	controller.scroll(-1)
	t.check(controller.artifact_pick == 0 and controller.is_on_artifact(), "on the attuned one it uses it")
	controller.close_watch_icon()
	for i in 2:
		controller.scroll(1)
	await t.frames(2)
	t.check(hud.wrist.card.focused_tab() == "status" and hud.wrist.focused_id() == "standing",
			"then Status: the map and your standing")
	for i in 20:
		controller.scroll(1)
	await t.frames(2)
	t.check(hud.wrist.card.focused_tab() == "mission" and hud.wrist.focused_id() == "leave", "and Mission, ending on sign-out")
	controller.wrist_raised = false
	t.check(not controller.click_watch() and not controller.watch_takes_fire(), "with the watch down a click is a shot")
	# At home the same card says what goes out.
	var home := Hud.base_watch_slots("Home base", {"primary": "rifle_carbine", "melee": "knife_gutter"})
	t.check(home.map(func(s: Dictionary) -> String: return s.id) == Hud.Wrist.SLOTS
			and home[0].detail.contains("Ashfront Carbine") and home[0].detail.contains("Gutter Knife"),
			"at home the weapon icon names what you deploy with")
	controller.queue_free()
	hud.queue_free()
	await t._end_raid(raid)


static func _ping_and_popups(t: Node) -> void:
	print("Watch: squad ping and pop-ups")
	var raid: Raid = await t._kit_raid(83, KIT)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await t.frames(2)
	var pings: Array[Vector3] = []
	raid.pinged.connect(func(_a: Actor, at: Vector3) -> void: pings.append(at))
	var spot := p.global_position + p.global_basis * Vector3(0, 0, -8)
	t._aim_at(p, spot)
	await t.frames(2)
	t.check(raid.ping(p) == "" and pings.size() == 1 and pings[0].distance_to(p.global_position) < raid.ping_range,
			"a ping marks the spot you are looking at")
	await t.frames(2)
	t.check(hud.pings_shown() == 1, "and stands in the world as a marker for you")
	t.check(raid.ping(p) != "" and pings.size() == 1, "pings cannot be spammed")
	var asked := [0]
	controller.ping_requested.connect(func() -> void: asked[0] += 1)
	controller.wrist_raised = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("ping")
	controller.watch_focus_moved = true
	t.check(controller.watch_takes_fire() and controller.click_watch() and asked[0] == 1 and controller.wrist_raised,
			"a click on the ping icon asks for a ping and keeps the watch up")
	# A stranger's ping is not yours to see.
	var other := raid.bots[0]
	raid.pinged.emit(other, spot)
	t.check(not Visor.allied(p, other) and hud.pings_shown() == 1, "only your side's pings are shown to you")
	await t.frames(ceili(raid.ping_time * 60.0) + 10)
	t.check(hud.pings_shown() == 0, "a ping fades after %d s" % roundi(raid.ping_time))
	# Pop-ups: only while they matter.
	t.check(Hud.flight_popup(p) == "", "on the ground the card says nothing about the rig")
	p.airborne_time = 1.0
	t.check(Hud.flight_popup(p) != "", "in the air the rig's status pops up on the card: %s" % Hud.flight_popup(p))
	p.airborne_time = 0.0
	hud.wrist.show_card(Hud.watch_slots(raid, p), 0, "", 1.0, [] as Array[float], [] as Array[String],
			{"summon": Hud.pack_text(p)}, "JETPACK HOT")
	t.check(hud.wrist.text().contains("JETPACK HOT") and hud.wrist.text().contains("Pack "),
			"the card reads back its pop-up and the pack's line")
	hud.wrist.show_card(Hud.watch_slots(raid, p), 0, "You died\n1: Quiet drop", 0.0, [] as Array[float])
	t.check(hud.wrist.text() == "You died\n1: Quiet drop", "down, the card is the death report and the landing choices")
	controller.queue_free()
	hud.queue_free()
	await t._end_raid(raid)


## Caleb's call: every vehicle, the jet included, can be thrown and every
## weapon summoned in every world, the plaza included.
static func _everywhere(t: Node) -> void:
	print("Watch: every vehicle and weapon in every world")
	var vehicles: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "vehicle"):
			vehicles.append(id)
	for world: WorldDef in Worlds.all():
		var raid := Raid.new()
		t.add_child(raid)
		raid.start(world, 91, world.starter_loadout() + vehicles)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, 0, 3000)
		await t.frames(10)
		var p := raid.player
		var state := raid.state_for(p)
		p.protected_left = 0.0
		var landed: Array[String] = []
		var refused: Array[String] = []
		var unpacked := [false]
		raid.toy_landed.connect(func(_a: Actor, _id: String, _at: Vector3, ok: bool) -> void: unpacked[0] = ok)
		for id in vehicles:
			var ok := false
			# Some spots are walled in; try round the thrower before giving up.
			for turn in 8:
				state.toy_ready_at = raid.clock
				var ahead := Basis(Vector3.UP, TAU * turn / 8.0) * Vector3(0, 0, -9)
				var aim := (p.global_position + ahead - p.get_eye_position()).normalized()
				p.cmd.aim_dir = aim
				p.cmd.yaw = atan2(-aim.x, -aim.z)
				p.cmd.pitch = asin(clampf(aim.y, -1.0, 1.0))
				var why := raid.throw_toy(p, id)
				if why != "":
					refused.append("%s: %s" % [id, why])
					break
				unpacked[0] = false
				await t._wait_until(func() -> bool: return raid.toys.is_empty(), 300)
				if unpacked[0]:
					ok = true
					break
			if ok:
				landed.append(id)
				# Pack it again so the next one has room.
				var vehicle: Node3D = raid.vehicles[raid.vehicles.size() - 1]
				raid.remove_vehicle(vehicle)
				state.parked.erase(vehicle)
				state.stowed.append(id)
		t.check(landed == vehicles, "every vehicle unpacks in %s (%s)%s" % [world.id, ", ".join(landed),
				"" if refused.is_empty() else "; refused " + "; ".join(refused)])
		# A weapon carried in the pack can be summoned here too.
		p.inventory.add_item("rifle_carbine")
		state.summon_ready_at = raid.clock
		t.check(raid.summon(p, "rifle_carbine") == "" and Loadout.worn_index(p, "primary") >= 0
				and p.weapons[Loadout.worn_index(p, "primary")].item_id == "rifle_carbine",
				"a weapon in the pack is summoned in %s" % world.id)
		raid.queue_free()
		await t.frames(2)


## At home the watch summons every vehicle and weapon the owner has: a
## vehicle unpacks in the base to be ridden and packs back, a weapon is
## equipped. Nothing is stored or lost.
static func _at_home(t: Node) -> void:
	print("Watch: summoning at home")
	var vehicles: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "vehicle"):
			vehicles.append(id)
	var stash: Array[String] = ["rifle_carbine", "smg_stinger", "knife_gutter", "scrap_metal", "power_rail_lance"]
	stash.append_array(vehicles)
	stash.append(vehicles[0])
	var base := HomeBase.new()
	base.show_gear(stash, {"primary": "rifle_carbine", "vehicle": vehicles[0]}, BaseUpgrades.full())
	t.add_child(base)
	await t.frames(5)
	var p := base.player
	t.check(base.watch_vehicles() == vehicles, "every vehicle owned is on the watch at home, one of each: %s"
			% ", ".join(base.watch_vehicles()))
	t.check(base.watch_weapons() == (["smg_stinger", "knife_gutter", "rifle_scrap", "blade_scrap", "pistol_service"] as Array[String]),
			"every weapon owned and not worn is on the carousel, the free scrap ones too, and nothing else: %s" % ", ".join(base.watch_weapons()))
	# Stand mid-room and aim across it.
	p.global_position = base.to_global(Vector3(-2.0, 0.1, 0.0))
	p.cmd.yaw = PI / 2.0
	p.cmd.pitch = -0.3
	p.cmd.aim_dir = Vector3.ZERO
	await t.frames(5)
	var unpacked: Array[String] = []
	for id in vehicles:
		if base.throw_toy(p, id) == "" and is_instance_valid(base.out_vehicles.get(id)):
			unpacked.append(id)
			await t.frames(50)
			var vehicle: Node3D = base.out_vehicles[id]
			if id == vehicles[0]:
				t.check(not base.watch_vehicles().has(id) and float(vehicle.get("unpack_left")) == 0.0,
						"a thrown vehicle unpacks in the base and is off the watch while it is out")
				t.check(vehicle.call("mount", p) and p.vehicle == vehicle, "it can be ridden at home")
				p.cmd.interact_pressed = true
				await t.frames(3)
				p.cmd.interact_pressed = false
				t.check(p.vehicle == null, "and got off again, with no server")
				p.global_position = base.to_global(Vector3(-2.0, 0.1, 0.0))
				await t.frames(3)
			# Pack it by looking at it.
			var aim := (vehicle.global_position + Vector3(0, 0.6, 0) - p.get_eye_position()).normalized()
			p.cmd.aim_dir = aim
			p.cmd.yaw = atan2(-aim.x, -aim.z)
			p.cmd.pitch = asin(clampf(aim.y, -1.0, 1.0))
			await t.frames(2)
			if base.pack_vehicle(p) != "":
				vehicle.queue_free()
				base.out_vehicles.erase(id)
			await t.frames(2)
			p.cmd.yaw = PI / 2.0
			p.cmd.pitch = -0.3
			p.cmd.aim_dir = Vector3.ZERO
	t.check(unpacked == vehicles, "every vehicle unpacks at home (%s)" % ", ".join(unpacked))
	t.check(base.out_vehicles.is_empty() and base.watch_vehicles() == vehicles, "and each packs back onto the watch")
	var asked: Array = []
	base.equip_requested.connect(func(slot: String, id: String) -> void: asked.append([slot, id]))
	base.read_only = true
	t.check(base.watch_vehicles().is_empty() and base.watch_weapons().is_empty() and base.throw_toy(p, vehicles[0]) != "",
			"nothing is summoned in someone else's base")
	base.queue_free()
	await t.frames(2)
