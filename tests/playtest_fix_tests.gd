extends RefCounted
## Checks for fixes from Caleb's playtest of the rival raiders build: the
## bank and sign-out progress round the crosshair, the heavy weapon on key 4
## and back into the watch's chamber, and a garage that shows one of each
## vehicle before any duplicate. Kept in its own file and called from the
## test runner. (The steady aim on the move is checked in `ads_tests.gd`.)

const BaseLayout := preload("res://core/base/base_layout.gd")
const PhoneScript := preload("res://core/phone/phone.gd")


static func run(t: Node) -> void:
	_garage(t)
	await _progress_ring(t)
	await _heavy_weapon(t)


static func _garage(t: Node) -> void:
	print("Playtest fixes: the garage")
	var stash := ["rover_warden", "rover_warden", "bike_scrapper", "bike_raider"]
	var bays := BaseLayout.spots("bay", [])
	var shown: Array = BaseLayout.plan(stash, {}, []).filter(func(d: Dictionary) -> bool: return d.kind == "bay") \
			.map(func(d: Dictionary) -> String: return d.id)
	var types := {}
	for id: String in shown:
		types[id] = true
	t.check(types.size() == mini(bays, 3), "the garage shows a different vehicle in every bay before a duplicate (%s)"
			% ", ".join(shown))
	var full := ["rover_warden", "rover_warden", "bike_scrapper", "bike_raider", "mech_bulwark"]
	var all_bays: Array = BaseLayout.plan(full, {}, ["bay_second", "garage_full"]).filter(func(d: Dictionary) -> bool:
		return d.kind == "bay").map(func(d: Dictionary) -> String: return d.id)
	t.check(all_bays.slice(0, 4).has("bike_scrapper") and all_bays.slice(0, 4).has("bike_raider")
			and all_bays.slice(0, 4).has("rover_warden"),
			"with the bays to spare every type is parked first (%s)" % ", ".join(all_bays))


static func _progress_ring(t: Node) -> void:
	print("Playtest fixes: bank and sign-out progress")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 61, ["rifle_carbine"])
	await t.frames(3)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await t.frames(3)
	t.check(hud.progress_ring != null and hud.progress_ring.value < 0.0, "no ring round the crosshair with nothing going on")
	raid.state_for(p).last_combat = -100.0
	t.check(raid.begin_sign_out(p), "a sign-out starts")
	await t.frames(30)
	t.check(hud.progress_ring.value > 0.0 and hud.progress_ring.color == Hud.ProgressRing.LEAVING,
			"signing out fills a ring round the crosshair, watch down (%.2f)" % hud.progress_ring.value)
	t.check(hud._prompt.text.contains(" s "), "and the prompt counts the seconds (%s)" % hud._prompt.text)
	raid.cancel_sign_out(p)
	await t.frames(2)
	t.check(hud.progress_ring.value < 0.0, "cancelled, the ring goes")
	hud.queue_free()
	controller.queue_free()
	raid.queue_free()
	await t.frames(2)


static func _heavy_weapon(t: Node) -> void:
	print("Playtest fixes: the heavy weapon")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 62, ["rifle_carbine", "pistol_service", "blade_scrap"])
	await t.frames(3)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await t.frames(3)
	Loadout.set_power(p, "power_rail_lance", -1, -1, false)
	var heavy := Loadout.power_index(p)
	var before := p.active_weapon_index
	t.check(heavy >= 0 and before != heavy, "a heavy weapon waits in the watch's chamber")
	Input.action_press("weapon_4")
	await t.frames(3)
	Input.action_release("weapon_4")
	t.check(p.active_weapon_index == heavy and p.materialize_left > 0.0,
			"key 4 draws it, materializing as it does from the watch")
	await t.frames(5)
	# Picked on the watch while in hand: back into the chamber, never the pack.
	controller.weapon_pick = Hud.weapon_entries(p).map(func(e: Dictionary) -> int: return int(e.index)).find(heavy)
	controller.take_picked_weapon()
	await t.frames(3)
	t.check(p.active_weapon_index == before and Loadout.power_index(p) == heavy
			and not p.inventory.has_item("power_rail_lance"),
			"clicked on the watch in hand, it goes back into the chamber and the last weapon comes out")
	Input.action_press("weapon_4")
	await t.frames(3)
	Input.action_release("weapon_4")
	t.check(p.active_weapon_index == heavy, "and 4 draws it again")
	# The heavy takes the primary's place: going back costs the primary's
	# summon time, the sidearm does not.
	t.check(p.primary_in_watch, "with the heavy out, the primary waits in the watch")
	Input.action_press("weapon_2")
	await t.frames(2)
	Input.action_release("weapon_2")
	var sidearm := p.get_active_weapon() as Gun
	t.check(sidearm != null and sidearm.is_sidearm and p.materialize_left <= 0.0,
			"the sidearm comes out at once from the heavy")
	Input.action_press("weapon_1")
	await t.frames(2)
	Input.action_release("weapon_1")
	var primary := p.get_active_weapon() as Gun
	t.check(primary != null and not primary.is_sidearm and not primary.is_power() and p.materialize_left > 0.0
			and not p.primary_in_watch, "the primary materializes back out of the watch")
	await t.frames(int(Loadout.summon_time(primary.item_id) * 60.0) + 5)
	Input.action_press("weapon_2")
	await t.frames(2)
	Input.action_release("weapon_2")
	Input.action_press("weapon_1")
	await t.frames(2)
	Input.action_release("weapon_1")
	t.check(p.get_active_weapon() == primary and p.materialize_left <= 0.0,
			"once it is back, switching to it is instant again")
	# A spent heavy dissolves and the primary comes back through the watch.
	Input.action_press("weapon_4")
	await t.frames(2)
	Input.action_release("weapon_4")
	Loadout.set_power(p, "")
	await t.frames(2)
	t.check(p.get_active_weapon() == primary and p.materialize_left > 0.0,
			"a spent heavy hands the primary back, materializing")
	var listed := false
	for row: Array in PhoneScript.CONTROLS:
		listed = listed or str(row[1]).contains("{weapon_4}")
	t.check(listed, "the phone's Controls app lists key 4")
	controller.queue_free()
	raid.queue_free()
	await t.frames(2)
