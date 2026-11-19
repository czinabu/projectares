extends RefCounted
## The `drops` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Drop map")
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("frostline"), 12)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var ids := func(owner: String) -> Array:
		return raid.drop_choices(owner).map(func(c: Dictionary) -> String: return c.id)
	t.check(ids.call("acct-a") == ["safe"], "with no war and no ground held there is one place to land")
	var point := raid.strongpoints[1]
	point.hold("players", "the raiders", true)
	t.check(ids.call("acct-a") == ["safe", "point:1"], "a strongpoint your side holds is offered")
	var a := raid.add_player([], {}, "Alpha", "acct-a", 0, "point:1")
	a.set_physics_process(false)
	t.check(point.covers(a.global_position), "choosing it lands you there")
	var b := raid.add_player([], {}, "Bravo", "acct-b", 0, "safe")
	b.set_physics_process(false)
	t.check(not point.covers(b.global_position), "the quiet drop keeps you away from your strongpoints")
	point.contested = true
	t.check(ids.call("acct-a") == ["safe"], "a site being fought over is not offered")
	point.contested = false
	point.hold("faction:warden", "the Wardens", false)
	var c := raid.add_player([], {}, "Charlie", "acct-c", 0, "point:1")
	c.set_physics_process(false)
	t.check(not point.covers(c.global_position), "asking for a site you do not hold lands you somewhere quiet")

	# Into the fight.
	raid.war.intensity = 0.6
	raid.war.centre = raid._map_nodes("spawn_player")[0].global_position + Vector3(3, 0, 3)
	t.check(ids.call("acct-d") == ["safe", "hot"], "once a battle is on you may land beside it")
	var d := raid.add_player([], {}, "Delta", "acct-d", 0, "hot")
	d.set_physics_process(false)
	t.check(d.global_position.distance_to(raid.war.centre) < 12.0 and d.protected_left > 0.0,
			"that lands you at the nearest drop point to the fighting, still protected (%.0f m)" % d.global_position.distance_to(raid.war.centre))
	raid.war.intensity = 0.0
	var e := raid.add_player([], {}, "Echo", "acct-e", 0, "hot")
	e.set_physics_process(false)
	t.check(e.global_position.distance_to(d.global_position) > 12.0, "with no battle, asking for one lands you somewhere quiet")

	var result := {"killed_by": "Bot"}
	var text := Hud.death_text(result, 0.0, [{"id": "safe", "title": "Quiet drop", "note": "away from the fighting"},
			{"id": "point:1", "title": "Drift Post", "note": "a strongpoint you hold"}])
	t.check("1: Quiet drop, away from the fighting" in text and "2: Drift Post, a strongpoint you hold" in text and "Enter" in text,
			"the death screen lists where you can land")
	t.check(not "1:" in Hud.death_text(result, 0.0, [{"id": "safe", "title": "Quiet drop", "note": ""}])
			and not "1:" in Hud.death_text(result, 2.0, raid.drop_choices("acct-a")),
			"it stays out of the way with one choice, or while you wait")
	raid.queue_free()
	await t.frames(2)
