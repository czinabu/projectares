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


static func _attachments() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "attachment"):
			out.append(id)
	return out


static func _items(t: Node) -> void:
	var all := _attachments()
	t.check(all.size() >= 10, "there are attachments to find (%d)" % all.size())
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
	var spec := HomeBase.spec_text(gun, bare)
	t.check("Magazine" in spec and "Zoom" in spec and "4x Ranger Scope" in spec and "Suppressed" in spec,
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


## Aiming with a scope narrows the view more than plain sights do.
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
	t.check(controller.aim_fov(actor.weapons[0]) < controller.aim_fov(plain.weapons[0]) / 2.0
			and is_equal_approx(controller.aim_fov(plain.weapons[0]), controller.ads_fov),
			"a scope zooms the aimed view much further than iron sights")
	controller.free()
	holder.queue_free()
	await t.frames(2)


## The gunsmith bench shows the stash's attachments; using one fits it.
static func _bench(t: Node) -> void:
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine", "optic_scope", "grip_angled", "grip_angled"],
			{"primary": "rifle_carbine", "optic": "optic_scope"})
	t.add_child(base)
	await t.frames(2)
	var scope := base.display_for("optic_scope")
	var grip := base.display_for("grip_angled")
	t.check(scope != null and scope.kind == "gunsmith" and scope.equipped and scope.slot == "optic",
			"a fitted scope hangs on the bench, marked equipped")
	t.check(grip != null and grip.count == 2 and not grip.equipped and grip.get_prompt().begins_with("[F] Equip"),
			"a spare grip on the bench offers to fit")
	var asked := []
	base.equip_requested.connect(func(slot: String, id: String) -> void: asked.append([slot, id]))
	if grip:
		grip.interact(base.player)
	if scope:
		scope.interact(base.player)
	t.check(asked == [["grip", "grip_angled"], ["optic", ""]], "using the bench fits and takes off attachments (%s)" % [asked])
	var bench_gun := base.get_node_or_null("Displays/BenchGun")
	t.check(bench_gun != null and bench_gun.get_meta("display_item", "") == "rifle_carbine"
			and bench_gun.find_child("optic", true, false) != null,
			"the primary sits in the vise with its scope on")
	var card := base.get_node_or_null("Displays/SpecCard") as Label3D
	t.check(card != null and "Zoom" in card.text, "a card by the vise lists what the scope changes")
	var spot := base.spot_transform("gunsmith", 0).origin
	var last := base.spot_transform("gunsmith", 11).origin
	var half := base.room_size * 0.5
	t.check(absf(spot.x) < half.x and absf(spot.z) < half.z and absf(last.x) < half.x and last.y > 0.5,
			"the bench's pegboard is inside the room")
	base.queue_free()
	await t.frames(2)
