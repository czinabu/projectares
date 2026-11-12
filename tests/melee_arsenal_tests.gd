extends RefCounted
## Checks for the knife, the axe and the spear: what sets each apart, and how
## they fit the shops, loot and mastery. Called from the test runner
## (`-- --only melee_arsenal` runs just these).

const Economy := preload("res://core/economy/economy.gd")
const MasteryDB := preload("res://core/progression/mastery_db.gd")

const KNIFE := "knife_gutter"
const AXE := "axe_splitter"
const SPEAR := "spear_lancer"


static func run(t: Node) -> void:
	_data(t)
	await _in_raid(t)


static func _data(t: Node) -> void:
	print("Melee arsenal: items, shops, loot and mastery")
	for id: String in [KNIFE, AXE, SPEAR]:
		t.check(ItemDB.has_tag(id, "weapon") and ItemDB.has_tag(id, "melee")
				and not ItemDB.has_tag(id, "starter"), "%s is a melee weapon" % ItemDB.item_name(id))
		var blade := _make(id)
		t.check(blade.light_windup >= 0.08 and blade.heavy_windup >= 0.2,
				"%s keeps a windup you can see, so it can be parried" % ItemDB.item_name(id))
		blade.free()
	t.check(Economy.for_sale("armory", KNIFE) and Economy.for_sale("armory", AXE),
			"the Armory sells the knife and the axe")
	t.check(not Economy.for_sale("armory", SPEAR) and ItemDB.item_rarity(SPEAR) == ItemDB.Rarity.RARE,
			"the spear is rare and loot-only")
	t.check(ItemDB.item_value(KNIFE) < ItemDB.item_value("hammer_breaker")
			and ItemDB.item_value(AXE) > ItemDB.item_value("hammer_breaker"), "the knife is the cheap pick")
	t.check(Economy.sell_price(KNIFE) < Economy.buy_price(KNIFE) and Economy.sell_price(AXE) < Economy.buy_price(AXE),
			"the new blades cannot be flipped for profit")

	# Every one turns up somewhere, the spear only where flying pays.
	var found := {}
	for world_id: String in ["ashfront", "frostline"]:
		var world: WorldDef = Worlds.get_world(world_id)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for source: String in ["cache", "rooftop", "relay"]:
			for i in 400:
				for id in world.roll_loot(source, rng):
					var sources: Array = found.get(id, [])
					if source not in sources:
						sources.append(source)
					found[id] = sources
	t.check(found.has(KNIFE) and found.has(AXE) and found.has(SPEAR), "all three can be looted")
	t.check(found.get(SPEAR, []) == ["rooftop"], "the spear is only found on rooftops")

	t.check(MasteryDB.track_for_item(KNIFE) == "knife" and MasteryDB.track_for_item(AXE) == "axe"
			and MasteryDB.track_for_item(SPEAR) == "spear", "each trains its own mastery track")
	t.check(MasteryDB.track_for_item("frost_ice_axe") == "axe", "Frostline's Ice Axe counts as an axe")

	var held := MeleeWeapon.new()
	held.item_id = SPEAR
	t.check(Look.is_two_handed(held), "the spear takes both hands, so it is slung on the back")
	held.item_id = KNIFE
	t.check(not Look.is_two_handed(held), "the knife is one-handed, so it hangs at the hip")
	held.item_id = AXE
	t.check(not Look.is_two_handed(held), "the axe is one-handed, so it hangs at the hip")
	held.free()


static func _make(id: String) -> MeleeWeapon:
	var blade := MeleeWeapon.new()
	Loadout._setup_weapon(blade, id, ItemDB.item_stats(id))
	return blade


## Gives `who` only `id` (or a plain blade for ""), in hand.
static func _arm(t: Node, who: Actor, id: String) -> MeleeWeapon:
	for w in who.weapons:
		if w.visual:
			w.visual.queue_free()
		w.queue_free()
	who.weapons.clear()
	var blade := _make(id) if id != "" else MeleeWeapon.new()
	blade.light_stamina = 0.0
	who.equip_weapon(blade)
	who.active_weapon_index = 0
	await t.frames(2)
	return blade


static func _reset(foe: Actor) -> void:
	foe.health.health = foe.health.max_health
	foe.health.armor = 0.0
	foe.stagger_left = 0.0
	foe.stamina = foe.max_stamina
	foe.velocity = Vector3.ZERO


## Places the foe `dist` meters in front of `p` and `up` above, facing p or away.
static func _place(p: Actor, foe: Actor, dist: float, up := 0.0, facing_away := false) -> void:
	foe.global_position = p.global_position + Vector3(0, up, -dist)
	foe.cmd.yaw = 0.0 if facing_away else PI
	foe.cmd.aim_dir = Vector3.FORWARD if facing_away else Vector3.BACK


## The damage one light strike from `blade` does to `foe`, judged right now.
static func _strike(t: Node, p: Actor, foe: Actor, blade: MeleeWeapon, dist: float, up := 0.0,
		facing_away := false) -> float:
	_reset(foe)
	_place(p, foe, dist, up, facing_away)
	await t.frames(1)
	_place(p, foe, dist, up, facing_away)
	var before := foe.health.health
	blade._strike(blade.light_damage, "light")
	return before - foe.health.health


static func _in_raid(t: Node) -> void:
	print("Melee arsenal: knife, axe and spear in a fight")
	var raid: Raid = await t._new_raid(52, false)
	var setup: Array = await t._duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	foe.health.max_health = 500.0
	p.protected_left = 0.0
	foe.protected_left = 0.0

	# Knife: a cut from behind does far more than one from the front.
	var knife := await _arm(t, p, KNIFE)
	var front: float = await _strike(t, p, foe, knife, 1.6)
	var back: float = await _strike(t, p, foe, knife, 1.6, 0.0, true)
	t.check(is_equal_approx(front, knife.light_damage), "a knife cut from the front does plain damage")
	t.check(is_equal_approx(back, knife.light_damage * knife.backstab_mult), "a knife cut from behind is a backstab")
	var plain := await _arm(t, p, "")
	back = await _strike(t, p, foe, plain, 1.6, 0.0, true)
	t.check(is_equal_approx(back, plain.light_damage), "other blades get no backstab bonus")
	knife = await _arm(t, p, KNIFE)
	t.check(await _strike(t, p, foe, knife, 2.5) == 0.0, "the knife is short: it misses at sword range")

	# Axe: a guard that stops it pays far more stamina.
	var foe_blade := foe.get_active_weapon() as MeleeWeapon
	var drain := func(blade: MeleeWeapon) -> float:
		_reset(foe)
		_place(p, foe, 2.0)
		foe.cmd.secondary = true
		await t.frames(30)
		_place(p, foe, 2.0)
		var stamina := foe.stamina
		var health := foe.health.health
		blade._strike(blade.light_damage, "light")
		var spent := stamina - foe.stamina
		t.check(foe.health.health == health and foe_blade.is_blocking(), "%s: a held guard stops the hit" % blade.display_name)
		foe.cmd.secondary = false
		await t.frames(2)
		return spent
	plain = await _arm(t, p, "")
	var plain_drain: float = await drain.call(plain)
	var axe := await _arm(t, p, AXE)
	var axe_drain: float = await drain.call(axe)
	t.check(is_equal_approx(axe_drain, axe.light_damage * foe_blade.block_stamina_per_damage * axe.guard_crush)
			and axe_drain > plain_drain * 2.5, "blocking an axe costs far more stamina")
	# Three axe chops on a full guard break it.
	_reset(foe)
	_place(p, foe, 2.0)
	foe.cmd.secondary = true
	await t.frames(30)
	_place(p, foe, 2.0)
	for i in 3:
		axe._strike(axe.light_damage, "light")
	t.check(foe.stagger_left > 0.0 and not foe_blade.is_blocking(), "three axe chops break a full guard")
	foe.cmd.secondary = false
	await t.frames(2)

	# Spear: long reach, high reach, weak up close.
	var spear := await _arm(t, p, SPEAR)
	t.check(await _strike(t, p, foe, spear, 3.8) == spear.light_damage, "the spear reaches past sword range")
	t.check(await _strike(t, p, foe, spear, 1.0) == spear.light_damage * spear.close_mult,
			"inside the point the spear does half damage")
	t.check(await _strike(t, p, foe, spear, 2.0, 3.2) == spear.light_damage, "the spear pokes a flier overhead")
	plain = await _arm(t, p, "")
	t.check(await _strike(t, p, foe, plain, 3.8) == 0.0 and await _strike(t, p, foe, plain, 2.0, 3.2) == 0.0,
			"a sword reaches neither")

	# The spear's heavy thrust staggers, through the real input path.
	spear = await _arm(t, p, SPEAR)
	_reset(foe)
	foe.global_position = p.global_position + Vector3(0, 0, -3.2)
	foe.cmd.yaw = PI
	foe.cmd.aim_dir = Vector3.BACK
	await t.frames(70)
	_reset(foe)
	p.cmd.tertiary_pressed = true
	await t.frames(1)
	p.cmd.tertiary_pressed = false
	await t.frames(int(spear.heavy_windup * 60.0) + 6)
	t.check(foe.health.health < foe.health.max_health and foe.stagger_left > 0.0, "a heavy spear thrust staggers")
	# A blocked thrust does not.
	await t.frames(90)
	_reset(foe)
	foe.global_position = p.global_position + Vector3(0, 0, -3.2)
	foe.cmd.secondary = true
	await t.frames(30)
	p.cmd.tertiary_pressed = true
	await t.frames(1)
	p.cmd.tertiary_pressed = false
	await t.frames(int(spear.heavy_windup * 60.0) + 6)
	t.check(foe.stagger_left <= 0.0, "a blocked heavy thrust does not stagger")
	foe.cmd.secondary = false
	await t._end_raid(raid)
