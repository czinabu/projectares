extends RefCounted
## Checks for dropping items out of the pack from the watch's pack list
## (`Raid.drop_item`, `PlayerController.drop_picked_from_pack`): the item
## leaves the pack and lies in a bag anyone may loot, drops made in one spot
## share a bag, a gun keeps its rounds, and a safe zone refuses it.

const KIT: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light"]


static func run(t: Node) -> void:
	await _drops(t)
	await _watch_drops(t)


static func _bags_near(raid: Raid, at: Vector3, reach: float) -> Array[LootContainer]:
	var out: Array[LootContainer] = []
	for node in raid.get_tree().get_nodes_in_group("loot_containers"):
		var bag := node as LootContainer
		if bag != null and bag.is_bag and not bag.is_queued_for_deletion() \
				and bag.global_position.distance_to(at) <= reach:
			out.append(bag)
	return out


static func _drops(t: Node) -> void:
	print("Pack drop: out of the pack into a bag on the ground")
	var raid: Raid = await t._kit_raid(412, KIT)
	var p := raid.player
	p.inventory.add_item("scrap_metal")
	p.inventory.add_item("rifle_carbine")
	p.inventory.add_item("scrap_metal")
	var carried := p.inventory.items.size()
	var at := p.global_position
	t.check(_bags_near(raid, at, 4.0).is_empty(), "no bag lies here before a drop")
	var notices: Array[String] = []
	p.notice.connect(func(text: String) -> void: notices.append(text))
	t.check(raid.drop_item(p, "ammo_crate_none") != "" and p.inventory.items.size() == carried,
			"something not in the pack cannot be dropped")
	t.check(raid.drop_item(p, "scrap_metal") == "" and p.inventory.items.size() == carried - 1
			and p.inventory.items.count("scrap_metal") == 1, "an item in the pack can be dropped, one at a time")
	t.check(notices.has("Dropped %s" % ItemDB.item_name("scrap_metal")), "with a notice saying what went")
	await t.frames(2)
	var bags := _bags_near(raid, at, 4.0)
	t.check(bags.size() == 1 and bags[0].items == (["scrap_metal"] as Array[String])
			and bags[0].global_position.y <= at.y + 0.6,
			"it lies in a bag at your feet: %d bag(s)" % bags.size())
	p.stowed_rounds["rifle_carbine"] = [3, 11]
	t.check(raid.drop_item(p, "rifle_carbine") == "" and not p.stowed_rounds.has("rifle_carbine"),
			"a gun put away with rounds can be dropped, and its rounds go with it")
	await t.frames(2)
	bags = _bags_near(raid, at, 4.0)
	t.check(bags.size() == 1 and bags[0].items.size() == 2 and "rifle_carbine" in bags[0].items,
			"a second drop in the same spot goes in the same bag")
	var bag := bags[0]
	# Someone else picks it up: a bot here stands in for another player.
	var other := raid.bots[0] if not raid.bots.is_empty() else null
	t.check(other != null, "a bot to loot the bag")
	if other != null:
		other.inventory.items.clear()
		bag.interact(other)
		t.check(other.inventory.has_item("scrap_metal") and other.inventory.has_item("rifle_carbine")
				and other.stowed_rounds.get("rifle_carbine", []) == [3, 11],
				"anyone may loot it, and the gun comes with the rounds it was dropped with, not refilled")
		await t.frames(2)
		t.check(not is_instance_valid(bag) or bag.is_queued_for_deletion(), "an emptied bag is cleared away")
	# Far from the last bag, the next drop is a bag of its own.
	p.global_position = at + Vector3(raid.drop_bag_reach + 3.0, 0, 0)
	await t.frames(2)
	t.check(raid.drop_item(p, "scrap_metal") == "", "dropping again further on")
	await t.frames(2)
	t.check(_bags_near(raid, p.global_position, 1.5).size() == 1, "makes a new bag where you stand now")

	# A safe zone (and anywhere nothing is at stake) refuses it.
	p.inventory.add_item("scrap_metal")
	var safe := raid.world.safe_zone
	raid.world.safe_zone = true
	carried = p.inventory.items.size()
	t.check(raid.drop_item(p, "scrap_metal") != "" and p.inventory.items.size() == carried
			and not Hud.can_drop_here(raid), "a safe zone refuses a drop, and the watch knows")
	raid.world.safe_zone = safe
	t.check(Hud.can_drop_here(raid) and not Hud.can_drop_here(null), "out in a world it is allowed; at home it is not")
	await t._end_raid(raid)


static func _watch_drops(t: Node) -> void:
	print("Pack drop: the interact key on the opened pack list")
	var raid: Raid = await t._kit_raid(413, KIT)
	var p := raid.player
	p.inventory.add_item("scrap_metal")
	p.inventory.add_item("rifle_carbine")
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var asked: Array[String] = []
	controller.pack_drop_requested.connect(func(id: String) -> void:
		asked.append(id)
		raid.drop_item(p, id))
	controller.wrist_raised = true
	controller.watch_focus_moved = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("pack")
	t.check(not controller.is_on_pack_list(), "closed, the pack icon does not drop")
	t.check(controller.click_watch() and controller.watch_open == "pack" and controller.is_on_pack_list(),
			"opened, the pack list takes the interact key")
	var slot := Hud.pack_slot(p, 0, raid)
	t.check(slot.hints.has(Hud.key_cap("interact")) and Hud.key_cap("interact").begins_with("key:"),
			"its line shows the interact key's cap beside the wheel: %s" % ", ".join(slot.hints))
	controller.pack_pick = 0
	controller.drop_picked_from_pack()
	await t.frames(2)
	t.check(asked == (["scrap_metal"] as Array[String]) and p.inventory.items == (["rifle_carbine"] as Array[String])
			and controller.is_watch_up() and controller.watch_open == "pack",
			"the picked item is dropped, and the watch stays on the list for the next")
	controller.drop_picked_from_pack()
	await t.frames(2)
	t.check(p.inventory.items.is_empty() and not controller.is_on_pack_list(),
			"the next item moves up under the pick; an empty pack has nothing left to drop")
	t.check(not Hud.pack_slot(p, 0, raid).hints.has(Hud.key_cap("interact")), "and shows no key")
	controller.queue_free()
	await t._end_raid(raid)
