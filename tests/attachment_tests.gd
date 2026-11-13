extends RefCounted
## Checks for weapon attachments: the items, the four loadout slots, how they
## change a primary, that they ride with it into a raid and drop with it, and
## the gunsmith bench in the home base. Called from the test runner
## (`-- --only attachments` runs just these).

const StashRules := preload("res://core/account/stash_rules.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const Economy := preload("res://core/economy/economy.gd")


static func run(t: Node) -> void:
	print("Attachments")
	_items(t)
	_fitting(t)
	await _kit(t)
	await _scope_view(t)
	await _bench(t)
	await _bench_view(t)


static func _attachments() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "attachment"):
			out.append(id)
	return out


static func _items(t: Node) -> void:
	var all := _attachments()
	t.check(all.size() >= 10, "there are attachments to find (%d)" % all.size())
	# Helmets that zoom are tagged "optic" too, but are never a gun's optic.
	var helmets_as_optics: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "helmet") and Loadout.fits("optic", id):
			helmets_as_optics.append(id)
	t.check(helmets_as_optics.is_empty() and Loadout.fits("helmet", "helm_spotter"),
			"the Optic slot offers no helmets (%s)" % ", ".join(helmets_as_optics))
	var per_slot := {}
	for id in all:
		var slot := Loadout.attachment_slot(id)
		t.check(slot != "" and Loadout.fits(slot, id), "%s fits its own slot (%s)" % [id, slot])
		t.check(not Loadout.fits("primary", id) and not Loadout.fits("sidearm", id), "%s is not a weapon" % id)
		t.check(ItemDB.item_stats(id).has("model"), "%s has a shape to show on the gun" % id)
		per_slot[slot] = per_slot.get(slot, 0) + 1
		var sold := Economy.for_sale("armory", id)
		if ItemDB.item_rarity(id) > ItemDB.Rarity.UNCOMMON:
			t.check(not sold, "%s is too good to buy: loot only" % id)
	for slot: String in Loadout.ATTACHMENT_SLOTS:
		t.check(per_slot.get(slot, 0) >= 2 and slot in Loadout.OPTIONAL_SLOTS,
				"the %s slot is optional and has a choice of attachments" % slot)
	t.check(Economy.for_sale("armory", "optic_reflex") and not Economy.for_sale("armory", "optic_scope"),
			"the armory sells a reflex sight but not a scope")
	var stash: Array[String] = ["optic_scope", "rifle_carbine"]
	t.check(StashRules.can_equip(stash, "optic", "optic_scope") and not StashRules.can_equip(stash, "muzzle", "optic_scope")
			and not StashRules.can_equip(stash, "optic", "rifle_carbine"),
			"the stash rules only take an optic in the optic slot")
	t.check(BaseLayout.kind_for("mag_drum") == "gunsmith" and BaseLayout.slot_for("mag_drum") == "magazine",
			"the base hangs a drum mag on the gunsmith bench and equips it as the magazine")
	# Loot: the PvP world has every attachment somewhere; the gentle world only the basic tier.
	var ashfront := Worlds.get_world("ashfront")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var found := {}
	for i in 600:
		for source: String in ["cache", "rooftop"]:
			for id in ashfront.roll_loot(source, rng):
				found[id] = true
	t.check(all.all(func(id: String) -> bool: return found.has(id)), "every attachment can be found in Ashfront")
	var frost := Worlds.get_world("frostline")
	var rare_in_frost := false
	var frost_any := false
	for i in 600:
		for source: String in ["cache", "rooftop", "relay"]:
			for id in frost.roll_loot(source, rng):
				if ItemDB.has_tag(id, "attachment"):
					frost_any = true
					rare_in_frost = rare_in_frost or ItemDB.item_rarity(id) > ItemDB.Rarity.UNCOMMON
	t.check(frost_any and not rare_in_frost, "Frostline drops basic attachments and nothing rarer")


static func _fitting(t: Node) -> void:
	var bare := HomeBase.bench_gun("rifle_carbine", [])
	var gun := HomeBase.bench_gun("rifle_carbine", ["mag_extended", "optic_scope", "muzzle_suppressor", "grip_vertical"])
	t.check(gun.mag_size == roundi(bare.mag_size * 1.5) and gun.ammo_in_mag == gun.mag_size
			and gun.reload_time > bare.reload_time,
			"an extended mag holds half again as many rounds, loaded, and reloads slower (%d -> %d)"
			% [bare.mag_size, gun.mag_size])
	t.check(gun.ads_zoom > 2.0 and bare.ads_zoom == 1.0 and gun.aim_zoom() == gun.ads_zoom,
			"a scope zooms in when aiming")
	t.check(gun.ads_spread_mult < bare.ads_spread_mult and gun.spread_deg > bare.spread_deg,
			"a scope steadies aimed shots and loosens hip fire")
	t.check(gun.quiet and not bare.quiet and gun.damage < bare.damage, "a suppressor quiets the gun for some damage")
	t.check(gun.recoil_kick_deg < bare.recoil_kick_deg, "a vertical grip cuts the kick")
	t.check(gun.attachment_in("optic") == "optic_scope" and gun.attachment_in("magazine") == "mag_extended",
			"the gun knows what is in each slot")
	var doubled := HomeBase.bench_gun("rifle_carbine", ["optic_reflex", "optic_longscope"])
	t.check(doubled.attachments.size() == 1 and doubled.attachment_in("optic") == "optic_reflex",
			"only one optic fits at a time")
	var visual := gun.build_visual()
	var sight := visual.get_node_or_null("Attachments/optic/Sight")
	t.check(visual.get_node_or_null("Attachments/muzzle") != null and sight != null,
			"the attachments are on the gun's model, and the optic has a line of sight")
	t.check(sight != null and sight.position.y > 0.03, "the optic's sight line sits above the gun")
	var spec := "\n".join(HomeBase.spec_lines(gun, bare))
	t.check("Magazine" in spec and "Zoom" in spec and "Suppressed" in spec,
			"the bench card says what the attachments change")
	visual.free()
	for made: Gun in [bare, gun, doubled]:
		made.free()


## Attachments go on the primary only, ride into a raid with it, and drop with it.
static func _kit(t: Node) -> void:
	var stash: Array[String] = ["rifle_carbine", "optic_reflex", "mag_drum", "pistol_machine"]
	var loadout := {"primary": "rifle_carbine", "optic": "optic_reflex", "magazine": "mag_drum", "sidearm": "pistol_machine"}
	var kit := StashRules.checkout(stash, loadout, Worlds.get_world("ashfront"))
	t.check("optic_reflex" in kit and "mag_drum" in kit and not "optic_reflex" in stash,
			"fitted attachments leave the stash with the kit")
	t.check(not kit.any(func(id: String) -> bool: return ItemDB.has_tag(id, "muzzle") or ItemDB.has_tag(id, "grip")),
			"empty attachment slots deploy with nothing")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 72, kit)
	await t.frames(5)
	var p := raid.player
	var primary := p.weapons[0] as Gun
	var sidearm: Gun = null
	for weapon in p.weapons:
		if weapon is Gun and weapon.is_sidearm:
			sidearm = weapon
	t.check(primary != null and primary.item_id == "rifle_carbine" and primary.attachment_in("optic") == "optic_reflex"
			and primary.attachment_in("magazine") == "mag_drum", "the primary deploys with its attachments on")
	t.check(primary != null and primary.ammo_in_mag == primary.mag_size and primary.mag_size > 50,
			"the drum mag deploys full (%d)" % (primary.mag_size if primary else 0))
	t.check(sidearm != null and sidearm.attachments.is_empty(), "the sidearm gets no attachments")
	# A power weapon comes as it is.
	if not ItemDB.has_item("test_power_gun"):
		ItemDB.register("test_power_gun", "Test Power Gun", ItemDB.Rarity.EPIC, 0,
				["weapon", "firearm", "power"], {"damage": 40.0})
	t.check(not Loadout.is_primary("test_power_gun"),
			"a power weapon takes no attachments")
	ItemDB._items.erase("test_power_gun")
	t.check("optic_reflex" in p.get_drop_items() and "mag_drum" in p.get_drop_items(),
			"attachments are carried gear: they drop with you")
	raid.queue_free()
	await t.frames(2)


## A scope magnifies inside its lens only (picture in picture): the aimed
## view itself stays as wide as plain sights, while its zoom is big.
static func _scope_view(t: Node) -> void:
	var holder := Node3D.new()
	t.add_child(holder)
	var actor := Actor.new()
	holder.add_child(actor)
	Loadout.equip(actor, ["rifle_carbine", "optic_scope"])
	var plain := Actor.new()
	holder.add_child(plain)
	Loadout.equip(plain, ["rifle_carbine"])
	var controller := PlayerController.new()
	controller.actor = actor
	await t.frames(2)
	var scoped := actor.weapons[0] as Gun
	t.check(scoped.scope_lens and scoped.aim_zoom() > 2.0
			and is_equal_approx(controller.aim_fov(scoped), controller.ads_fov)
			and is_equal_approx(controller.aim_fov(plain.weapons[0]), controller.ads_fov),
			"a scope magnifies in its lens and leaves the rest of the aimed view as wide as iron sights")
	controller.free()
	holder.queue_free()
	await t.frames(2)


## The gunsmith bench holds one gun at a time. Using it, the wheel turns
## through your guns and then each attachment slot's choices, each shown on
## the gun at once; a click picks, and only a pick asks for an equip.
static func _bench(t: Node) -> void:
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine", "smg_stinger", "optic_scope", "optic_reflex", "grip_angled", "grip_angled"],
			{"primary": "rifle_carbine", "optic": "optic_scope"})
	t.add_child(base)
	await t.frames(2)
	var hung := 0
	for display in base.displays:
		if display.kind == "gunsmith":
			hung += 1
	t.check(hung == 0 and base.display_for("optic_scope") == null and BaseLayout.stored_away(base.stash).is_empty(),
			"attachments are no longer hung on a pegboard, nor counted as stored away")
	var bench_gun := base.get_node_or_null("Displays/BenchGun")
	t.check(bench_gun != null and bench_gun.get_meta("display_item", "") == "rifle_carbine"
			and bench_gun.find_child("optic", true, false) != null,
			"the primary sits on the bench with its scope on")
	var bench := bench_gun as HomeBase.Bench
	var used := [0]
	base.bench_used.connect(func() -> void: used[0] += 1)
	var asked := []
	base.equip_requested.connect(func(slot: String, id: String) -> void: asked.append([slot, id]))
	t.check(bench != null and bench.get_prompt().begins_with("[F] Gunsmith bench"), "the bench offers itself to use")
	t._face_display(base.player, bench)
	await t.frames(2)
	t.check(base.player.find_interactable() == bench and base.in_workshop(base.to_local(base.player.global_position)),
			"the bench can be walked up to from inside the workshop and looked at")
	await t._use(base.player)
	t.check(used[0] == 1 and base.bench_open and base.bench_picking and base.bench_row == 0
			and base.bench_choice == "rifle_carbine", "using the bench starts on your gun, ready to turn")
	t.check(base.bench_choices("primary") == ["rifle_carbine", "smg_stinger", "rifle_scrap", ""]
			and base.bench_choices("optic") == ["", "optic_scope", "optic_reflex"] and base.bench_choices("grip") == ["", "grip_angled"],
			"the wheel turns through each gun once (then the free one, then none) and each slot's owned attachments")
	base.bench_scroll(1)
	await t.frames(1)
	bench_gun = base.get_node_or_null("Displays/BenchGun")
	var card := base.get_node_or_null("Displays/SpecCard") as Label3D
	t.check(bench_gun != null and bench_gun.get_meta("display_item", "") == "smg_stinger"
			and bench_gun.find_child("optic", true, false) != null and asked.is_empty()
			and card != null and "‹ Stinger SMG ›" in card.text,
			"a notch of the wheel puts the next gun on the bench at once, fitted the same, without equipping it")
	base.bench_select()
	t.check(asked == [["primary", "smg_stinger"]] and not base.bench_picking and base.bench_row == 1,
			"a click picks the gun and moves on to its attachments (%s)" % [asked])
	base.show_gear(base.stash, {"primary": "smg_stinger", "optic": "optic_scope"})
	await t.frames(1)
	asked.clear()
	base.bench_scroll(1)
	base.bench_scroll(1)
	t.check(base.bench_row == 3 and not base.bench_picking, "with no row open the wheel moves between the slots")
	base.bench_select()
	t.check(base.bench_picking and base.bench_choice == "", "a click opens the grip slot on what is fitted (nothing)")
	base.bench_scroll(1)
	await t.frames(1)
	bench_gun = base.get_node_or_null("Displays/BenchGun")
	card = base.get_node_or_null("Displays/SpecCard") as Label3D
	t.check(bench_gun != null and bench_gun.find_child("grip", true, false) != null and asked.is_empty()
			and "‹ Angled Grip ›" in card.text, "turning the grip slot shows the grip on the gun before it is picked")
	t.check(base.bench_back() and not base.bench_picking, "a step back drops the grip on show")
	await t.frames(1)
	bench_gun = base.get_node_or_null("Displays/BenchGun")
	t.check(asked.is_empty() and bench_gun.find_child("grip", true, false) == null, "and takes it back off the gun")
	base.bench_scroll(-1)
	base.bench_scroll(-1)
	base.bench_select()
	base.bench_scroll(1)
	t.check(base.bench_choice == "optic_reflex", "the optic slot turns from the scope to the reflex sight")
	base.bench_select()
	t.check(asked == [["optic", "optic_reflex"]], "a click fits the optic on show (%s)" % [asked])
	t.check(not base.bench_back(), "with nothing open a step back means leaving")
	base.leave_bench()
	t.check(not base.bench_open, "stepping away puts the bench at rest")
	var on_rack := base.display_for("smg_stinger")
	t.check(on_rack != null and not on_rack.get_node("Model").visible and "ON THE BENCH" in on_rack.get_node("Plate").text
			and on_rack.has_node("Mount"), "the rack's pegs for the gun on the bench stand empty")
	card = base.get_node_or_null("Displays/SpecCard") as Label3D
	var stats := base.get_node_or_null("Displays/SpecStats") as Label3D
	t.check(card != null and stats != null and "Zoom" in stats.text and "OPTIC" in card.text and "4x Ranger Scope" in card.text,
			"the card behind the gun lists each slot and what the scope changes")
	base.read_only = true
	var visiting := base.get_node_or_null("Displays/BenchGun") as HomeBase.Bench
	if visiting:
		visiting.interact(base.player)
	t.check(visiting != null and used[0] == 1 and not base.bench_open and not visiting.get_prompt().begins_with("[F]"),
			"a visitor sees the gun on someone else's bench but cannot use it")
	base.read_only = false
	base.queue_free()
	await t.frames(2)


## In the game, using the bench brings the view to it; the wheel, a click and
## Esc work it, and stepping away gives the player back the room.
static func _bench_view(t: Node) -> void:
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["rifle_carbine", "smg_stinger", "optic_reflex"])
	Profile.equip("primary", "rifle_carbine")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	var base: HomeBase = main.base
	var bench := base.get_node("Displays/BenchGun") as HomeBase.Bench
	bench.interact(base.player)
	await t.frames(30)
	var view: Node3D = main.bench_view
	var camera := t.get_viewport().get_camera_3d()
	var bench_at := base.global_transform * base.bench_transform()
	t.check(view != null and main.controller.input_blocked and camera != null and camera.name == "BenchCamera"
			and camera.global_position.distance_to(bench_at * Vector3(0, 1.5, 0)) < 2.5,
			"using the bench moves the view in to it and takes the mouse from the controller")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	view._unhandled_input(wheel)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	view._unhandled_input(click)
	await t.frames(3)
	t.check(Profile.loadout.get("primary", "") == "smg_stinger" and base.loadout.get("primary", "") == "smg_stinger"
			and base.get_node("Displays/BenchGun").get_meta("display_item", "") == "smg_stinger",
			"a notch and a click put the next gun on the bench as your primary")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	view._unhandled_input(esc)
	await t.frames(3)
	t.check(main.bench_view == null and not main.controller.input_blocked and not base.bench_open
			and t.get_viewport().get_camera_3d() != null and t.get_viewport().get_camera_3d().name != "BenchCamera",
			"Esc steps away from the bench and gives back the view and the controls")
	main.queue_free()
	await t.frames(2)
	Profile.reset()
