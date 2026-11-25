extends RefCounted
## Checks for carry weight (DESIGN.md section 4, "Weight"; `CarryLoad`):
## what items weigh, the light, medium and heavy tiers, what a load does to
## moving (a little faster light, slower and lower heavy, never a cap), the
## pack's haul counting, the rig's heat, and the watch showing the load.

const ItemCard := preload("res://core/ui/item_card.gd")

## About 11 kg: a runner's kit.
const LIGHT_KIT: Array[String] = ["smg_stinger", "knife_gutter", "boots_thruster", "frame_runner", "helm_seeker"]
## About 24 kg: a trooper's kit.
const MEDIUM_KIT: Array[String] = ["rifle_carbine", "blade_scrap", "jetpack_mk1", "frame_trooper", "helm_seeker"]
## About 63 kg: everything heavy at once.
const HEAVY_KIT: Array[String] = ["rifle_carbine", "hammer_breaker", "power_storm_cannon", "jetpack_mk1",
		"frame_bulwark", "helm_warden"]


static func run(t: Node) -> void:
	_items(t)
	_curves(t)
	await _loads(t)
	await _moving(t)


static func _items(t: Node) -> void:
	print("Carry weight: what things weigh")
	t.check(CarryLoad.weight_of("frame_bulwark") > CarryLoad.weight_of("frame_trooper")
			and CarryLoad.weight_of("frame_trooper") > CarryLoad.weight_of("frame_runner"),
			"a heavy frame outweighs a medium one, and that a light one")
	var heaviest := ""
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "melee") and (heaviest == "" or CarryLoad.weight_of(id) > CarryLoad.weight_of(heaviest)):
			heaviest = id
	t.check(heaviest == "hammer_breaker", "the hammer is the heaviest melee weapon (%s)" % heaviest)
	var light_power := ItemDB.all_ids().filter(func(id: String) -> bool:
			return ItemDB.has_tag(id, "power") and CarryLoad.weight_of(id) < 10.0)
	t.check(light_power.is_empty(),
			"every heavy weapon weighs 10 kg or more")
	t.check(CarryLoad.weight_of("jetpack_mk1") > CarryLoad.weight_of("wings_glide")
			and CarryLoad.weight_of("wings_glide") > CarryLoad.weight_of("boots_thruster")
			and is_equal_approx(CarryLoad.weight_of("jetpack_mk3"), CarryLoad.weight_of("jetpack_mk1")),
			"a jetpack is the heaviest rig and boots the lightest; a higher Mk weighs the same")
	t.check(CarryLoad.weight_of("bike_scrapper") == 0.0 and CarryLoad.weight_of("scrap_metal") > 0.0,
			"a vehicle rides on the watch for nothing; loot in the pack weighs something")
	t.check(ItemCard.facts("frame_bulwark").has("Weighs 22 kg"), "an item's card says what it weighs: %s"
			% str(ItemCard.facts("frame_bulwark")))
	var own_mults := ItemDB.all_ids().filter(func(id: String) -> bool:
			return ItemDB.item_stats(id).has("speed_mult") or ItemDB.item_stats(id).has("sprint_mult") \
					or ItemDB.item_stats(id).has("heat_mult"))
	t.check(own_mults.is_empty(), "no frame or pack slows you or heats your rig by a stat of its own any more: its weight does")


static func _curves(t: Node) -> void:
	print("Carry weight: tiers and what they do")
	t.check(CarryLoad.tier(10.0) == "light" and CarryLoad.tier(20.0) == "medium" and CarryLoad.tier(40.0) == "heavy",
			"under %d kg is light, %d kg and over heavy" % [CarryLoad.LIGHT_KG, CarryLoad.HEAVY_KG])
	var flat := true
	for kg in [CarryLoad.LIGHT_KG, 20.0, 26.0, CarryLoad.HEAVY_KG]:
		flat = flat and CarryLoad.speed_mult(kg) == 1.0 and CarryLoad.accel_mult(kg) == 1.0 \
				and CarryLoad.heat_mult(kg) == 1.0 and CarryLoad.jump_mult(kg) == 1.0
	t.check(flat, "a medium load moves exactly as tuned")
	t.check(CarryLoad.speed_mult(6.0) > 1.0 and CarryLoad.speed_mult(6.0) <= 1.06 + 0.0001
			and CarryLoad.speed_mult(11.0) < CarryLoad.speed_mult(6.0) and CarryLoad.heat_mult(6.0) < 1.0,
			"light is a little faster and runs a rig cooler, more so the lighter")
	var slower := true
	var last := 1.0
	for kg in range(33, 90, 3):
		var now := CarryLoad.speed_mult(kg)
		slower = slower and now <= last
		last = now
	t.check(slower and last >= CarryLoad.MIN_SPEED and CarryLoad.speed_mult(1000.0) == CarryLoad.MIN_SPEED,
			"heavy gets slower bit by bit, to a floor, with no limit on what you may carry")
	t.check(CarryLoad.jump_mult(CarryLoad.HEAVY_KG) == 1.0 and CarryLoad.jump_mult(40.0) < 1.0
			and CarryLoad.jump_mult(500.0) == CarryLoad.MIN_JUMP,
			"the jump only drops once the load is heavy, and never under %d%%" % roundi(CarryLoad.MIN_JUMP * 100.0))
	t.check(CarryLoad.heat_mult(50.0, true) > 1.0 and CarryLoad.heat_mult(50.0, true) < CarryLoad.heat_mult(50.0, false),
			"a jetpack carries a heavy load best: it builds only part of the extra heat")


static func _loads(t: Node) -> void:
	print("Carry weight: worn into a world")
	var raid: Raid = await t._kit_raid(611, LIGHT_KIT)
	var p := raid.player
	t.check(CarryLoad.tier(p.carry_kg()) == "light", "a runner's kit is light (%.1f kg)" % p.carry_kg())
	await t._end_raid(raid)
	raid = await t._kit_raid(612, HEAVY_KIT)
	p = raid.player
	t.check(CarryLoad.tier(p.carry_kg()) == "heavy", "a bulwark, hammer and heavy weapon is heavy (%.1f kg)" % p.carry_kg())
	await t._end_raid(raid)

	raid = await t._kit_raid(613, MEDIUM_KIT)
	p = raid.player
	var kg := p.carry_kg()
	t.check(CarryLoad.tier(kg) == "medium" and is_equal_approx(p.carry_speed, 1.0),
			"a trooper's kit is medium (%.1f kg) and moves as tuned" % kg)
	var told: Array[float] = []
	p.carry_changed.connect(func(now: float) -> void: told.append(now))
	for n in 10:
		p.inventory.add_item("alloy_ingot")
	t.check(p.carry_kg() > kg and told.size() == 1 and is_equal_approx(told[0], p.carry_kg()),
			"loot in the pack is carried too: the load grows to %.1f kg, said once" % p.carry_kg())
	t.check(Hud.pack_text(p).contains(CarryLoad.label(p.carry_kg())),
			"the watch's pack line shows the tier and weight: %s" % Hud.pack_text(p))
	var hauled := p.carry_kg()
	Loadout.wear_frame(p, "frame_bulwark")
	t.check(p.carry_kg() > hauled and CarryLoad.tier(p.carry_kg()) == "heavy",
			"a heavy frame put on makes it heavy (%.1f kg)" % p.carry_kg())
	p.refresh_carry()
	t.check(p.carry_speed < 1.0 and p.carry_jump < 1.0 and p.flight.load_heat > 1.0,
			"and it slows the run (%.2f), lowers the jump (%.2f) and heats the rig (%.2f)"
			% [p.carry_speed, p.carry_jump, p.flight.load_heat])
	var mass := p.carry_kg()
	Loadout.wear_rig(p, "wings_glide")
	p.refresh_carry()
	t.check(p.flight.load_heat > CarryLoad.heat_mult(mass, true) and is_equal_approx(p.flight.load_heat,
			CarryLoad.heat_mult(p.carry_kg(), false)), "wings carry the load's heat in full, where a jetpack took part")
	p.carry_sent = 5.0
	p.mark_carry()
	t.check(is_equal_approx(p.carry_kg(), 5.0) and p.carry_speed > 1.0,
			"a load sent by the server is the one used, so a client's guess matches it")
	await t._end_raid(raid)


## Runs `kit` on flat ground: its top sprint speed and how high it jumps.
static func _run_and_jump(t: Node, ground: Node3D, kit: Array[String]) -> Vector2:
	var a := Actor.new()
	ground.add_child(a)
	Loadout.equip(a, kit)
	a.position = Vector3(0, 0.05, 0)
	await t.frames(20)
	a.cmd.move = Vector2(0, 1)
	a.cmd.sprint = true
	await t.frames(90)
	var speed := Vector2(a.velocity.x, a.velocity.z).length()
	a.cmd.move = Vector2.ZERO
	a.cmd.sprint = false
	await t.frames(60)
	var from := a.global_position.y
	var top := from
	a.cmd.jump_pressed = true
	await t.frames(1)
	a.cmd.jump_pressed = false
	for i in 90:
		await t.frames(1)
		top = maxf(top, a.global_position.y)
	a.queue_free()
	return Vector2(speed, top - from)


static func _moving(t: Node) -> void:
	print("Carry weight: how a load moves")
	var ground := Node3D.new()
	ground.position = Vector3(0, 0, 4000)
	t.add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(400, 1, 400)
	var col := CollisionShape3D.new()
	col.shape = shape
	floor_body.add_child(col)
	floor_body.position.y = -0.5
	ground.add_child(floor_body)
	var light: Vector2 = await _run_and_jump(t, ground, LIGHT_KIT)
	var medium: Vector2 = await _run_and_jump(t, ground, MEDIUM_KIT)
	var heavy: Vector2 = await _run_and_jump(t, ground, HEAVY_KIT)
	print("    sprint m/s and jump m: light %.2f / %.2f, medium %.2f / %.2f, heavy %.2f / %.2f"
			% [light.x, light.y, medium.x, medium.y, heavy.x, heavy.y])
	t.check(light.x > medium.x and medium.x > heavy.x and heavy.x > medium.x * 0.75,
			"light outruns medium and medium outruns heavy, but heavy still runs")
	t.check(absf(light.y - medium.y) < 0.03 and medium.y > 1.15 and medium.y < 1.3,
			"a light or medium load jumps the usual 1.2 m (%.2f m)" % medium.y)
	t.check(heavy.y < medium.y - 0.05 and heavy.y > 0.96, "a heavy load jumps lower, never under about 1 m (%.2f m)" % heavy.y)
	ground.queue_free()
	await t.frames(2)
