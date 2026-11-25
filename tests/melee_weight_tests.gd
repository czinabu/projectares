extends RefCounted
## Checks that a two-handed weapon shows its weight (view only): it holds
## its follow-through through the first part of its recovery before hauling
## the weapon back up, where a one-hander starts back at once, and its
## landed hits pause longer (`-- --groups melee_weight` runs just these).

const Arsenal := preload("res://tests/melee_arsenal_tests.gd")


static func run(t: Node) -> void:
	print("Melee weight: two-handers end in their weight")
	var hammer := Arsenal._make("hammer_breaker")
	var sword := Arsenal._make("blade_scrap")
	var held := []
	for blade: MeleeWeapon in [hammer, sword]:
		# A third of the way through a recovery after a strike.
		blade._recover_total = 0.6
		blade._cooldown = 0.4
		held.append(ActionPose.recover_left(blade))
	t.check(is_equal_approx(held[0], 1.0) and held[1] < 0.9,
			"a third into its recovery the hammer still holds its follow-through, the sword is on its way back (%.2f, %.2f)" % held)
	hammer._cooldown = 0.0001
	t.check(ActionPose.recover_left(hammer) < 0.01, "and the hammer is back up by the end of it")
	t.check(MeleeWeapon.HITSTOP * MeleeWeapon.TWO_HAND_HITSTOP > MeleeWeapon.HITSTOP * 1.5,
			"a two-hander's landed hit pauses longer than a one-hander's")
	hammer.free()
	sword.free()
