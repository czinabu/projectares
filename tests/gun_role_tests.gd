extends RefCounted
## Every gun has a range and a target it wins against (the gun bench,
## `gun_bench.tscn`): headshots pay on every gun, close-range guns fall off,
## and marksman rounds punch through plates. Checked with every round landing.

const Bench := preload("res://tests/gun_bench.gd")
const TROOPER := 85.0


static func run(t: Node) -> void:
	print("Gun roles")
	var carbine := Bench.make("rifle_carbine")
	var smg := Bench.make("smg_stinger")
	var dmr := Bench.make("dmr_longshot")
	var shotgun := Bench.make("shotgun_breacher")
	var cannon := Bench.make("pistol_hand_cannon")
	for id in Bench.guns():
		var gun := Bench.make(id)
		t.check(gun.headshot_mult >= 1.0 and (gun.pellets > 1 or gun.headshot_mult > 1.0),
				"%s: a headshot pays (x%.2f)" % [id, gun.headshot_mult])
		gun.free()
	# Falloff: full damage close in, easing down to its floor.
	t.check(smg.range_mult(5.0) == 1.0 and smg.range_mult(12.0) == 1.0, "an SMG hits full out to its falloff")
	t.check(smg.range_mult(20.0) < 1.0 and smg.range_mult(20.0) > smg.falloff_min, "and eases off past it")
	t.check(is_equal_approx(smg.range_mult(200.0), smg.falloff_min), "down to its floor")
	t.check(dmr.range_mult(200.0) == 1.0, "a marksman rifle keeps its damage at range")
	# Each gun wins somewhere.
	var near_smg := Bench.time_to_kill(smg, TROOPER, 5.0, false).y
	var near_rifle := Bench.time_to_kill(carbine, TROOPER, 5.0, false).y
	t.check(near_smg < near_rifle, "up close the SMG out-kills the carbine (%.2f s against %.2f s)" % [near_smg, near_rifle])
	var far_smg := Bench.time_to_kill(smg, TROOPER, 30.0, false).y
	var far_rifle := Bench.time_to_kill(carbine, TROOPER, 30.0, false).y
	t.check(far_rifle < far_smg, "at 30 m the carbine wins (%.2f s against %.2f s)" % [far_rifle, far_smg])
	t.check(Bench.time_to_kill(dmr, TROOPER, 60.0, true).x == 2,
			"two marksman headshots drop a mid kit through its plates")
	t.check(Bench.time_to_kill(dmr, TROOPER, 60.0, false).x <= 3, "three to the body do too")
	t.check(Bench.time_to_kill(shotgun, TROOPER, 5.0, false).x == 2, "two close shotgun blasts drop a mid kit")
	t.check(Bench.time_to_kill(shotgun, TROOPER, 30.0, false).x > 4, "a shotgun is no use at 30 m")
	t.check(Bench.time_to_kill(cannon, 0.0, 10.0, true).x == 2 and Bench.time_to_kill(cannon, 0.0, 10.0, false).x == 2,
			"the hand cannon drops a bare target in two")
	# Armor pierce reaches the hit.
	var health := HealthComponent.new()
	health.set_armor(TROOPER)
	var info := DamageInfo.make(dmr.damage, null, "bullet")
	info.armor_pierce = dmr.armor_pierce
	health.apply_damage(info)
	t.check(dmr.armor_pierce > 0.0 and health.health < 100.0 - dmr.damage * 0.4 - 0.01,
			"marksman rounds go partly past armor")
	health.free()
	for gun in [carbine, smg, dmr, shotgun, cannon]:
		gun.free()
