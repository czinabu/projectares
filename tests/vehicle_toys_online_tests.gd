extends RefCounted
## The `vehicle_toys_online` checks. The test runner finds this file by itself and calls
## `run(t)`.

const NET_ACCOUNTS := "user://test_accounts_net"


static func run(t: Node) -> void:
	print("Online: throwing a toy vehicle")
	t._wipe_dir(NET_ACCOUNTS)
	var port := 24871
	var pid: int = t._start_server(port, ["--bots", "0", "--squad-spawn"])
	var ivy: NetSession = await t._join("Ivy", port, {"vehicle": "bike_scrapper"})
	var jon: NetSession = await t._join("Jon", port) if ivy != null else null
	t.check(ivy != null and jon != null, "two clients join for the toy checks")
	if ivy != null and jon != null:
		var me := ivy.raid.player
		await t._wait_until(func() -> bool: return not ivy.raid.stowed_for(me).is_empty(), 180)
		t.check(ivy.raid.stowed_for(me) == (["bike_scrapper"] as Array[String]) and jon.raid.stowed_for(jon.raid.player).is_empty(),
				"the server tells each player what is on their own watch")
		await t._wait_until(func() -> bool: return not ivy.vehicles().is_empty(), 120)
		var before := ivy.vehicles().size()
		var before_there := jon.vehicles().size()
		t.check(ivy.raid.throw_toy(me, "bike_scrapper") != "" and ivy.raid.toys.is_empty(), "a client cannot unpack a vehicle on its own")
		ivy.throw_toy("bike_raider")
		await t.frames(30)
		t.check(ivy.vehicles().size() == before and ivy.raid.stowed_for(me).size() == 1, "the server refuses a toy the player does not have")
		# The toy in the hand shows to the other player too.
		var ivy_there: Actor = jon._actors.get(ivy.my_actor_id)
		ivy.hold_toy("bike_scrapper")
		t.check(me.toy_in_hand == "bike_scrapper", "your own hand shows the toy at once")
		await t._wait_until(func() -> bool: return ivy_there != null and ivy_there.toy_in_hand == "bike_scrapper", 120)
		t.check(ivy_there != null and ivy_there.toy_in_hand == "bike_scrapper", "the other player sees the toy in your hand")
		ivy.hold_toy("")
		await t._wait_until(func() -> bool: return ivy_there != null and ivy_there.toy_in_hand == "", 120)
		t.check(ivy_there != null and ivy_there.toy_in_hand == "", "and sees it put back")
		var throws_seen := ivy_there.toy_throws if ivy_there != null else 0
		# Thrown where there is room: the other player may be standing in the way.
		var seen_flying := false
		for turn in 4:
			if ivy.vehicles().size() > before or ivy.raid.stowed_for(me).is_empty():
				break
			me.cmd.yaw = turn * PI * 0.5
			me.cmd.pitch = -0.2
			me.cmd.aim_dir = Vector3.ZERO
			await t.frames(10)
			ivy.throw_toy("bike_scrapper")
			await t._wait_until(func() -> bool: return not jon.raid.toys.is_empty(), 120)
			seen_flying = seen_flying or not jon.raid.toys.is_empty()
			await t._wait_until(func() -> bool:
				return ivy.vehicles().size() > before or (jon.raid.toys.is_empty() and not ivy.raid.stowed_for(me).is_empty()), 300)
			await t.frames(20)
		t.check(seen_flying, "the other player sees the toy fly")
		t.check(ivy_there != null and ivy_there.toy_throws > throws_seen and ivy_there.toy_in_hand == "",
				"and sees the arm throw it, the hand empty once it flies")
		await t._wait_until(func() -> bool: return ivy.vehicles().size() > before and jon.vehicles().size() > before_there, 300)
		t.check(ivy.vehicles().size() == before + 1 and jon.vehicles().size() == before_there + 1,
				"it unpacks on the server and both clients get the bike")
		t.check(ivy.raid.stowed_for(me).is_empty() and ivy.raid.toy_wait(me) > 0.0, "the thrower's watch empties and starts recharging")
		var bike: Node3D = null
		for v: Node3D in ivy.vehicles():
			if v.get("item_id") == "bike_scrapper" and (bike == null or v.global_position.distance_to(me.global_position)
					< bike.global_position.distance_to(me.global_position)):
				bike = v
		t.check(bike != null and bike.global_position.distance_to(me.global_position) < 30.0, "the bike is where the toy landed, near the thrower")
	await t._leave(ivy)
	await t._leave(jon)
	OS.kill(pid)
	await t.frames(30)
