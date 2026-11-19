extends RefCounted
## The `health` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Health and armor")
	var h := HealthComponent.new()
	h.set_armor(50.0)
	h.apply_damage(DamageInfo.make(50.0, null, "bullet"))
	t.check(is_equal_approx(h.armor, 20.0), "armor absorbs 60% of a hit and degrades")
	t.check(is_equal_approx(h.health, 80.0), "the rest goes to health")
	var deaths := [0]
	h.died.connect(func(_i: DamageInfo) -> void: deaths[0] += 1)
	h.apply_damage(DamageInfo.make(500.0, null, "bullet"))
	h.apply_damage(DamageInfo.make(500.0, null, "bullet"))
	t.check(h.is_dead and deaths[0] == 1, "death fires exactly once")
	h.free()
