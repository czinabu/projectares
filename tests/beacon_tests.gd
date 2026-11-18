extends RefCounted
## Checks for Frostline's warm beacons (DESIGN.md "Frostline", "Getting
## out"): the only way out of the valley is to power up a beacon, which
## counts only while you hold it and runs faster for every other player
## powering it with you. A fight still cancels it. Kept in its own file and
## called from the test runner.

const MapScript := preload("res://worlds/frostline/map.gd")


static func run(t: Node) -> void:
	print("Warm beacons")
	var frost := Worlds.get_world("frostline")
	t.check(frost.sign_out_at_beacons and not Worlds.get_world("ashfront").sign_out_at_beacons,
			"Frostline signs out at warm beacons, Ashfront anywhere")
	Raid.zone_rules = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 4242)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	await t.frames(3)
	_on_the_map(t, raid)
	await _together(t, raid)
	await _alone(t, raid, raid.add_player([], {}, "You", "you"))
	raid.queue_free()
	await t.frames(2)
	# Without the zone rules (the rest of the suite) it is the old sign-out.
	Raid.zone_rules = false
	var plain := Raid.new()
	t.add_child(plain)
	plain.start_server(frost, 4242)
	var anyone := plain.add_player([], {}, "Anyone", "anyone")
	await t.frames(2)
	plain.state_for(anyone).last_combat = -1000.0
	t.check(plain.begin_sign_out(anyone), "without the zone rules a sign-out starts anywhere")
	plain.queue_free()
	await t.frames(2)


static func _on_the_map(t: Node, raid: Raid) -> void:
	t.check(raid.beacons.size() == MapScript.BEACONS.size(), "the valley has its beacons (%d)" % raid.beacons.size())
	var zones := {}
	for b in raid.beacons:
		zones[raid.world.zone_at(b.global_position)] = true
		t.check(String(b.get_meta("name", "")) != "" and raid.beacon_at(b.global_position) == b,
				"%s has a name and is its own beacon" % b.get_meta("name", "?"))
	t.check(zones.size() == 3, "there is a beacon in every zone of the valley")
	var on_ground := raid.beacons.all(func(b: Node3D) -> bool:
		return absf(b.global_position.y - raid.map.call("ground_height", b.global_position.x, b.global_position.z)) < 0.5)
	t.check(on_ground, "every beacon stands on the floor, where anyone can walk to it")
	var warm := raid.beacons.all(func(b: Node3D) -> bool:
		return raid.warmth.any(func(w: Node3D) -> bool:
			return w.global_position.distance_to(b.global_position) < 1.0))
	t.check(warm, "and every beacon is somewhere warm to stand")


static func _put(raid: Raid, actor: Actor, at: Vector3) -> void:
	actor.global_position = raid._stand(Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z))
	actor.velocity = Vector3.ZERO


static func _alone(t: Node, raid: Raid, me: Actor) -> void:
	await t.frames(2)
	var state := raid.state_for(me)
	state.last_combat = -1000.0
	# Out on the open floor, away from any beacon.
	_put(raid, me, Vector3(MapScript.centre(100.0) + 25.0, 0, 100.0))
	await t.frames(1)
	t.check(raid.beacon_at(me.global_position) == null and not raid.begin_sign_out(me)
			and state.sign_out_left < 0.0, "away from a beacon you cannot sign out")
	var beacon: Node3D = raid.beacons[0]
	_put(raid, me, beacon.global_position + Vector3(2, 0, 0))
	await t.frames(1)
	t.check(raid.zone_label(me).ends_with("· beacon"), "the watch says you stand at a beacon")
	t.check(raid.begin_sign_out(me) and is_equal_approx(state.sign_out_total, raid.world.beacon_sign_out_time)
			and state.at_beacon == beacon, "at a beacon the sign-out starts (%.0f s)" % state.sign_out_total)
	await t.frames(60)
	var spent := state.sign_out_total - state.sign_out_left
	t.check(spent > 0.7 and spent < 1.3, "it counts down while you hold it (%.2f s in a second)" % spent)
	# Walk away: the count waits.
	_put(raid, me, beacon.global_position + Vector3(20, 0, 0))
	await t.frames(2)
	var held := state.sign_out_left
	await t.frames(60)
	t.check(state.sign_out_left >= 0.0 and is_equal_approx(state.sign_out_left, held) and state.count_rate == 0.0,
			"away from the beacon the count waits, it does not start over")
	_put(raid, me, beacon.global_position + Vector3(1, 0, 0))
	await t.frames(30)
	t.check(state.sign_out_left < held and state.count_rate == 1.0, "back at the beacon it carries on")
	# A fight cancels it, as anywhere.
	raid._mark_combat(state)
	t.check(state.sign_out_left < 0.0 and state.at_beacon == null, "a fight cancels a beacon sign-out")
	state.last_combat = -1000.0
	# Seen through to the end, you leave like any sign-out.
	var outcome := [""]
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void:
		if actor == me:
			outcome[0] = result.get("outcome", ""), CONNECT_ONE_SHOT)
	t.check(raid.begin_sign_out(me), "and it can be started again")
	state.sign_out_left = 0.2
	await t.frames(30)
	t.check(outcome[0] == "left", "a powered beacon takes you home (%s)" % outcome[0])


static func _together(t: Node, raid: Raid) -> void:
	var beacon: Node3D = raid.beacons[1]
	var a := raid.add_player([], {}, "First", "first")
	var b := raid.add_player([], {}, "Second", "second")
	await t.frames(2)
	var sa := raid.state_for(a)
	var sb := raid.state_for(b)
	sa.last_combat = -1000.0
	sb.last_combat = -1000.0
	_put(raid, a, beacon.global_position + Vector3(2, 0, 0))
	_put(raid, b, beacon.global_position + Vector3(-2, 0, 0))
	await t.frames(1)
	t.check(raid.begin_sign_out(a) and raid.begin_sign_out(b), "two players power the same beacon")
	await t.frames(60)
	var rate := minf(1.0 + raid.world.beacon_join_bonus, raid.world.beacon_join_cap)
	t.check(is_equal_approx(sa.count_rate, rate) and is_equal_approx(sb.count_rate, rate),
			"together it powers up faster (x%.1f)" % sa.count_rate)
	var spent := sa.sign_out_total - sa.sign_out_left
	t.check(spent > rate * 0.75, "and the count shows it (%.2f s in a second)" % spent)
	# One walks off: the other carries on alone at the plain pace.
	_put(raid, b, beacon.global_position + Vector3(25, 0, 0))
	await t.frames(3)
	t.check(is_equal_approx(sa.count_rate, 1.0) and sb.count_rate == 0.0,
			"when one walks off, the other carries on at the plain pace")
	raid.cancel_sign_out(a)
	raid.cancel_sign_out(b)
	t.check(sa.at_beacon == null and is_equal_approx(sa.count_rate, 1.0), "a cancelled sign-out lets go of the beacon")
