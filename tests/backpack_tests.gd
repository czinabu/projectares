extends RefCounted
## Checks for bigger backpacks (Caleb's call: four sizes, 12/16/20/24, each
## bigger one weighing a little more, bought from the Outfitter): the
## items, `Loadout.wear_pack`, what is at stake, the shop, the gear room's
## hooks and the model worn on the back.

const Economy := preload("res://core/economy/economy.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const SkinScript := preload("res://core/visual/actor_skin.gd")
const KIT: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light"]
const PACKS: Array[String] = ["pack_rucksack", "pack_hauler", "pack_mule"]


static func run(t: Node) -> void:
	_items(t)
	await _worn(t)
	_model(t)


static func _items(t: Node) -> void:
	print("Backpacks: four sizes, bought from the Outfitter")
	var sizes: Array[int] = [Loadout.FIELD_PACK]
	var kgs: Array[float] = [0.0]
	for id in PACKS:
		var stats := ItemDB.item_stats(id)
		sizes.append(int(stats.get("capacity", 0)))
		kgs.append(CarryLoad.weight_of(id))
	t.check(sizes == ([12, 16, 20, 24] as Array[int]), "the field pack and three bigger ones: %s slots" % str(sizes))
	t.check(kgs[1] > kgs[0] and kgs[2] > kgs[1] and kgs[3] > kgs[2] and kgs[3] <= 5.0,
			"each bigger one weighs a little more empty, never much: %s kg" % str(kgs))
	t.check(PACKS.all(func(id: String) -> bool: return Loadout.slot_of(id) == "pack") and "pack" in Loadout.OPTIONAL_SLOTS,
			"they go in the backpack slot, which may be left empty for the field pack")
	t.check(PACKS.all(func(id: String) -> bool: return Economy.for_sale("outfitter", id) and id in Economy.stock("outfitter")),
			"the Outfitter sells all three for scrip")
	t.check(Economy.buy_price("pack_rucksack") < Economy.buy_price("pack_hauler")
			and Economy.buy_price("pack_hauler") < Economy.buy_price("pack_mule"),
			"bigger costs more: %d, %d, %d" % [Economy.buy_price("pack_rucksack"), Economy.buy_price("pack_hauler"),
			Economy.buy_price("pack_mule")])
	t.check(PACKS.all(func(id: String) -> bool: return BaseLayout.kind_for(id) == "pack_hooks")
			and BaseLayout.spots("pack_hooks") == 1 and BaseLayout.spots("pack_hooks", ["gear_hall"]) == 3,
			"at home they hang on hooks in the gear room, one in the starter bunker")


static func _worn(t: Node) -> void:
	print("Backpacks: worn into a world")
	var plain: Raid = await t._kit_raid(511, KIT)
	var sprint := plain.player.sprint_speed
	var walk := plain.player.walk_speed
	t.check(plain.player.inventory.capacity == 12 and plain.player.pack_id == "", "no backpack is the 12-slot field pack")
	await t._end_raid(plain)
	var kit := KIT.duplicate()
	kit.append("pack_hauler")
	kit.append("pack_rucksack")
	var raid: Raid = await t._kit_raid(512, kit)
	var p := raid.player
	t.check(p.pack_id == "pack_hauler" and p.inventory.capacity == 20, "a hauler worn holds 20")
	t.check(is_equal_approx(p.sprint_speed, sprint) and is_equal_approx(p.walk_speed, walk),
			"it costs nothing on its own but its weight (%.2f against %.2f)" % [p.sprint_speed, sprint])
	t.check(p.inventory.has_item("pack_rucksack"), "a second backpack in the kit is only carried")
	t.check("pack_hauler" in p.get_drop_items() and Hud.pack_text(p).contains("/20"), "the worn one is at stake like any gear, and the watch shows the room: %s"
			% Hud.pack_text(p))
	Loadout.wear_pack(p, "pack_mule")
	var kg := p.carry_kg()
	t.check(p.inventory.capacity == 24 and is_equal_approx(kg, CarryLoad.of_actor(p))
			and p.gear_items.count("pack_mule") == 1 and "pack_hauler" not in p.gear_items,
			"another goes on in its place, and the load weighs the new one (%.1f kg)" % kg)
	Loadout.wear_pack(p, "")
	t.check(p.inventory.capacity == 12 and p.carry_kg() < kg and p.pack_id == "",
			"taken off, the field pack is back and the load is lighter")
	for n in 12:
		p.inventory.add_item("scrap_metal")
	Loadout.wear_pack(p, "pack_rucksack")
	var held := p.inventory.items.size()
	Loadout.wear_pack(p, "")
	t.check(p.inventory.items.size() == held and p.inventory.is_full() and not p.inventory.add_item("scrap_metal"),
			"a smaller pack keeps what is already in it, but takes no more until there is room")
	# At home the base dresses the player in place (`Loadout.refit`).
	var fitted := KIT.duplicate()
	fitted.append("pack_mule")
	Loadout.refit(p, fitted)
	t.check(p.pack_id == "pack_mule" and p.inventory.capacity == 24, "a change of kit at home puts the new pack on")
	Loadout.refit(p, KIT)
	t.check(p.pack_id == "" and p.inventory.capacity == 12, "and takes it off")
	await t._end_raid(raid)


static func _model(t: Node) -> void:
	print("Backpacks: the model on the back")
	var heights: Array[float] = []
	var depths: Array[float] = []
	for size in [1, 2, 3]:
		var model := SkinScript.build_backpack(size, Color(0.33, 0.31, 0.24))
		var box := AABB()
		var first := true
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			var piece := part.transform * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
			box = piece if first else box.merge(piece)
			first = false
		heights.append(box.size.y)
		depths.append(box.position.z)
		model.free()
	t.check(heights[0] < heights[1] and heights[1] < heights[2], "each size stands taller on the back: %s" % str(heights))
	t.check(depths.all(func(z: float) -> bool: return z > -0.05), "and all of it sits behind the back (+Z), none in the body")
