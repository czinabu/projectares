extends RefCounted
## The `online_lag_compensation` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Online: a lagging shooter hits what is on their screen")
	var with_rewind: Array = await t._lagged_shots(24817, [])
	var without: Array = await t._lagged_shots(24818, ["--no-rewind"])
	t.check(with_rewind.size() == 2 and without.size() == 2, "two duels on a slow connection ran")
	if with_rewind.size() != 2 or without.size() != 2:
		return
	t.check(with_rewind[0] >= 4,
			"aiming straight at a running player on a 100 ms connection hits (%d of %d)" % with_rewind)
	t.check(without[0] <= 1,
			"without rewinding the same shots miss, so the hits come from lag compensation (%d of %d)" % without)


## Dana, on a 100 ms connection, aims exactly where she sees Eli while he
## strafes past, and fires single shots. Returns [hits, shots], or [] if the
## players could not join.
