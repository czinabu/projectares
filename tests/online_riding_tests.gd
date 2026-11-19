extends RefCounted
## The `online_riding` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Online: riding responds at once on a slow connection")
	var port := 24819
	var pid: int = t._start_server(port, ["--bots", "0", "--squad-spawn"])
	var faye: NetSession = await t._join("Faye", port, {"vehicle": "bike_scrapper"})
	var gus: NetSession = await t._join("Gus", port) if faye != null else null
	t.check(faye != null and gus != null, "two clients join for the riding checks")
	var bike: Node3D = null
	if faye != null and gus != null:
		await t._throw_own_bike(faye)
		await t._wait_until(func() -> bool: return not faye.vehicles().is_empty(), 120)
		for v: Node3D in faye.vehicles():
			if bike == null or v.global_position.distance_to(faye.raid.player.global_position) \
					< bike.global_position.distance_to(faye.raid.player.global_position):
				bike = v
	if bike == null:
		t.check(false, "the rider's bike is there")
		await t._leave(gus)
		await t._leave(faye)
		OS.kill(pid)
		await t.frames(30)
		return
	var me := faye.raid.player
	# The other player steps out of the bike's way.
	var walker := gus.raid.player
	var aside := walker.global_position - bike.global_position
	aside.y = 0.0
	aside = t._clear_run(walker, walker.global_position,
			aside.normalized() if aside.length() > 0.1 else Vector3.BACK, 8.0)
	walker.cmd.yaw = t._yaw_toward(aside)
	walker.cmd.move = Vector2(0, 1)
	await t.frames(100)
	walker.cmd.move = Vector2.ZERO
	var aim := bike.global_position + Vector3(0, 0.6, 0) - me.get_eye_position()
	me.cmd.aim_dir = aim.normalized()
	me.cmd.yaw = t._yaw_toward(aim)
	me.cmd.pitch = asin(clampf(aim.normalized().y, -1.0, 1.0))
	await t.frames(6)
	me.cmd.interact_pressed = true
	await t.frames(1)
	me.cmd.interact_pressed = false
	await t._wait_until(func() -> bool: return me.vehicle == bike, 90)
	t.check(me.vehicle == bike, "the rider gets on")
	faye.simulated_lag = 0.12
	await t.frames(40)
	faye.max_correction = 0.0
	var from := bike.global_position
	me.cmd.move = Vector2(0, 1)
	# The server only hears about it after 120 ms, about 7 ticks.
	await t.frames(6)
	t.check(bike.global_position.distance_to(from) > 0.06,
			"on a 120 ms connection the bike pulls away the moment the throttle opens (%.2f m)" % bike.global_position.distance_to(from))
	var heading: float = bike.get("heading")
	me.cmd.move = Vector2(0.7, 1)
	await t.frames(40)
	t.check(absf(angle_difference(heading, bike.get("heading"))) > 0.3, "steering turns the bike at once")
	me.cmd.move = Vector2(-0.5, 1)
	await t.frames(40)
	me.cmd.move = Vector2(0, -1)
	await t._wait_until(func() -> bool: return float(bike.get("speed")) <= 0.5, 120)
	me.cmd.move = Vector2.ZERO
	t.check(faye.max_correction < 0.5, "the server agrees with the predicted ride (worst %.2f m)" % faye.max_correction)
	await t.frames(60)
	var their_bike: Node3D = null
	for v: Node3D in gus.vehicles():
		if their_bike == null or v.global_position.distance_to(bike.global_position) \
				< their_bike.global_position.distance_to(bike.global_position):
			their_bike = v
	var apart := their_bike.global_position.distance_to(bike.global_position) if their_bike != null else 99.0
	t.check(apart < 0.5, "after stopping, the other player sees the bike where the rider has it (%.2f m apart)" % apart)
	t.check(me.vehicle == bike and me.global_position.distance_to(bike.global_position) < 1.5,
			"the rider stays on the predicted bike")
	await t._leave(gus)
	await t._leave(faye)
	OS.kill(pid)
	await t.frames(30)
