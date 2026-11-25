extends RefCounted
## Checks the melee balance budget (Caleb's call: weapons differ in damage,
## but each spends about the same budget its own way, and rarity buys a more
## unusual trait, never more power; DESIGN.md "What each axis means"). A
## weapon's score is its damage a second, times how often a swing lands (a
## slow, readable windup is parried, dodged and interrupted more), times its
## reach, its area (arc) and its traits, against the scrap blade's. Every
## melee item, world ones too, must score within `BAND`, and the weights
## below are a first guess for playtesting to correct. Prints the table it
## checks (`-- --groups melee_balance` runs just these).

const Arsenal := preload("res://tests/melee_arsenal_tests.gd")

## The weapon every other is measured against: a score of 1.
const REFERENCE := "blade_scrap"
const BAND := 0.15
## Damage per point of stamina, light and heavy alike.
const STAMINA_BAND := Vector2(1.7, 3.2)

## Landing: each second of windup past the reference's costs this share.
const LIGHT_TELL_COST := 1.0
const HEAVY_TELL_COST := 0.4
## Area: this share of the score per arc past the reference's 110 degrees.
const ARC_WEIGHT := 0.3
## Traits, each a share of the score.
const BACKSTAB_WEIGHT := 0.08 # per step of backstab_mult past 1
const GUARD_CRUSH_WEIGHT := 0.07 # per step of guard_crush past 1
const PARRY_WEIGHT := 3.0 # per second of parry_window past 0.22
const TWO_HAND_WEIGHT := 0.12 # heavies that stagger and break armor
const HEAVY_STAGGER_WEIGHT := 0.1 # per 0.6 s of spear stagger
const CLOSE_WEAKNESS_WEIGHT := 0.25 # per share of damage lost up close
const FLIER_WEIGHT := 0.04 # reaches well overhead
const MOVE_WEIGHT := 0.5 # per step of move speed past a one-hander's
const LUNGE_WEIGHT := 0.01 # per m/s of heavy lunge past 9
const SLAM_WEIGHT := 0.0015 # per point of slam damage x radius / 4.5 past the reference
## Weapon abilities (`MeleeWeapon.ability`), each a share of the score.
const ABILITY_WEIGHTS := {"ground_pound": 0.04}


static func run(t: Node) -> void:
	print("Melee balance: every weapon spends the same budget its own way")
	var ref := measure(REFERENCE)
	var ids: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "melee"):
			ids.append(id)
	t.check(ids.size() >= 7, "every melee weapon is measured (%d)" % ids.size())
	print("  %-16s %-8s %5s %5s %5s %5s %5s %6s" % ["weapon", "rarity", "light", "heavy", "hits", "L/sta", "H/sta", "score"])
	var out_of_band := []
	var stamina_off := []
	var best := {}
	var scores := {}
	for id in ids:
		var m := measure(id)
		var score: float = m.score / ref.score
		scores[id] = score
		print("  %-16s %-8s %5.0f %5.0f %5d %5.1f %5.1f %6.2f" % [id, ItemDB.rarity_name(id), m.light_damage,
				m.heavy_damage, m.hits, m.light_eff, m.heavy_eff, score])
		if absf(score - 1.0) > BAND:
			out_of_band.append(id)
		for eff: float in [m.light_eff, m.heavy_eff]:
			if eff < STAMINA_BAND.x or eff > STAMINA_BAND.y:
				stamina_off.append(id)
		var rarity := ItemDB.item_rarity(id)
		best[rarity] = maxf(best.get(rarity, 0.0), score)
	t.check(out_of_band.is_empty(), "every melee weapon scores within %d%% of the scrap blade (%s)" % [int(BAND * 100), out_of_band])
	t.check(stamina_off.is_empty(), "every melee weapon does about as much for its stamina (%s)" % [stamina_off])
	var common: float = best.get(ItemDB.Rarity.COMMON, 0.0)
	var climbs := []
	for rarity: int in best:
		if rarity > ItemDB.Rarity.COMMON and best[rarity] > common + BAND:
			climbs.append(ItemDB.Rarity.keys()[rarity])
	t.check(climbs.is_empty(), "a rarer melee weapon never out-scores the best common one past the band (%s)" % [climbs])
	t.check(scores.get("hammer_breaker", 0.0) > 0.0 and _per_hit("hammer_breaker") > _per_hit("axe_splitter")
			and _per_hit("axe_splitter") > _per_hit(REFERENCE) and _per_hit(REFERENCE) > _per_hit("knife_gutter"),
			"the slower the weapon type, the harder each hit: hammer, axe, sword, knife")
	var hammer := Arsenal._make("hammer_breaker")
	t.check(hammer.heavy_damage < 100.0, "no heavy kills an unarmored person in one blow")
	hammer.free()


## A weapon's stats and its budget score (unscaled; divide by the reference's).
static func measure(id: String) -> Dictionary:
	var b := Arsenal._make(id)
	var light_cycle := b.light_windup + b.light_recover
	var combo := b.light_damage * (2.0 + b.combo_finisher_mult) / 3.0
	var dps := (combo / light_cycle + b.heavy_damage / (b.heavy_windup + b.heavy_recover)) * 0.5
	var landing := (1.0 - LIGHT_TELL_COST * (b.light_windup - 0.1)) * (1.0 - HEAVY_TELL_COST * (b.heavy_windup - 0.4))
	var reach := sqrt(b.reach / 2.8)
	var area := 1.0 + ARC_WEIGHT * (b.arc_deg / 110.0 - 1.0)
	var traits := 1.0
	traits += BACKSTAB_WEIGHT * (b.backstab_mult - 1.0)
	traits += GUARD_CRUSH_WEIGHT * (b.guard_crush - 1.0)
	traits += PARRY_WEIGHT * (b.parry_window - 0.22)
	traits += TWO_HAND_WEIGHT if b.is_two_handed() else 0.0
	traits += HEAVY_STAGGER_WEIGHT * b.heavy_stagger / 0.6
	traits -= CLOSE_WEAKNESS_WEIGHT * (1.0 - b.close_mult) if b.close_range > 0.0 else 0.0
	traits += FLIER_WEIGHT if b.vertical_reach > 3.0 else 0.0
	traits += MOVE_WEIGHT * (b.move_speed_mult() - b.one_hand_speed)
	traits += LUNGE_WEIGHT * (b.heavy_lunge - 9.0)
	traits += SLAM_WEIGHT * (b.slam_damage * b.slam_radius - 55.0 * 4.5) / 4.5
	traits += ABILITY_WEIGHTS.get(b.ability, 0.0)
	var hits := 0
	var left := 100.0
	while left > 0.0:
		left -= b.light_damage * (b.combo_finisher_mult if hits % 3 == 2 else 1.0)
		hits += 1
	var out := {
		"score": dps * landing * reach * area * traits,
		"light_damage": b.light_damage, "heavy_damage": b.heavy_damage, "hits": hits,
		"light_eff": b.light_damage / b.light_stamina, "heavy_eff": b.heavy_damage / b.heavy_stamina,
	}
	b.free()
	return out


static func _per_hit(id: String) -> float:
	var b := Arsenal._make(id)
	var out := b.light_damage + b.heavy_damage
	b.free()
	return out
