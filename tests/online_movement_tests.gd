extends RefCounted
## The `online_movement` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Online: smooth movement on a bad connection")
	var port := 24816
	var pid: int = t._start_server(port, ["--bots", "0", "--squad-spawn"])
	var dana: NetSession = await t._join("Dana", port)
	var eli: NetSession = await t._join("Eli", port) if dana != null else null
	t.check(dana != null and eli != null, "two clients join for the movement checks")
	if dana == null or eli == null:
		await t._leave(eli)
		await t._leave(dana)
		OS.kill(pid)
		return
	await t._wait_until(func() -> bool: return eli.actor_for(dana.my_actor_id) != null, 180)
	var me := dana.raid.player
	var seen := eli.actor_for(dana.my_actor_id)
	await t.frames(30)

	# 120 ms each way: the server's answers describe where you were a quarter
	# of a second ago.
	dana.simulated_lag = 0.12
	await t.frames(40)
	dana.max_correction = 0.0
	var from := me.global_position
	var worst_step := 0.0
	var last := from
	# Run where there is room: the other player and the drop point's wall
	# stand somewhere around.
	me.cmd.yaw = t._yaw_toward(t._clear_run(me, from, Vector3.FORWARD, 22.0))
	await t.frames(20)
	me.cmd.move = Vector2(0, 1)
	me.cmd.sprint = true
	for i in 150:
		await t.frames(1)
		# A pull backwards shows up as a tick that moves you less than nothing.
		var step := (me.global_position - last).dot((me.global_position - from).normalized()) if i > 20 else 0.0
		worst_step = minf(worst_step, step)
		last = me.global_position
	var ran := from.distance_to(me.global_position)
	me.cmd.move = Vector2.ZERO
	me.cmd.sprint = false
	t.check(ran > 6.0, "a lagging player still runs at full speed (%.1f m)" % ran)
	t.check(dana.max_correction < 0.4, "running on a slow connection needs no real correction (worst %.2f m)" % dana.max_correction)
	t.check(worst_step > -0.02, "the player is never pulled backwards while running (%.3f m)" % worst_step)
	await t.frames(90)
	var apart := seen.global_position.distance_to(me.global_position) if is_instance_valid(seen) else 99.0
	t.check(apart < 0.5, "after stopping, the other player sees them where they are (%.2f m apart)" % apart)

	# How long a press takes to show on the other player's screen, on a clean
	# connection, to compare with a lossy one below.
	dana.simulated_lag = 0.04
	await t.frames(60)
	var clean_delay: float = await t._press_delay(me, seen, 6)
	# One in five input packets lost: a single-tick press must still arrive.
	dana.simulated_loss = 0.2
	await t.frames(60)
	dana.max_correction = 0.0
	var ground := me.global_position.y
	var top := 0.0
	var seen_jumps := 0
	for jump in 5:
		me.cmd.jump_pressed = true
		await t.frames(1)
		me.cmd.jump_pressed = false
		var seen_top := 0.0
		for i in 80:
			await t.frames(1)
			top = maxf(top, me.global_position.y - ground)
			seen_top = maxf(seen_top, seen.global_position.y - ground)
		if seen_top > 0.6:
			seen_jumps += 1
	t.check(top > 0.6, "the player jumps on their own screen at once (%.2f m)" % top)
	t.check(seen_jumps == 5, "every jump reaches the server despite lost packets (%d of 5 seen by the other player)" % seen_jumps)
	# Steady loss must not leave the server playing inputs late: by now the
	# old input queue sat at its limit, five ticks (about 80 ms) behind.
	var lossy_delay: float = await t._press_delay(me, seen, 6)
	t.check(lossy_delay < clean_delay + 2.5 and lossy_delay < 8.5,
			"steady packet loss adds no lasting input delay (a press shows after %.1f ticks, %.1f on a clean connection)"
			% [lossy_delay, clean_delay])
	dana.simulated_loss = 0.0

	# A bad moment: every packet for a sixth of a second is lost, with a press
	# in the middle of it. The first packet through still carries the press.
	await t.frames(60)
	dana.simulated_loss = 1.0
	await t.frames(4)
	me.cmd.jump_pressed = true
	await t.frames(1)
	me.cmd.jump_pressed = false
	await t.frames(5)
	dana.simulated_loss = 0.0
	var burst_top := 0.0
	for i in 80:
		await t.frames(1)
		burst_top = maxf(burst_top, seen.global_position.y - ground)
	t.check(burst_top > 0.6, "a press made while every packet is being lost still reaches the server (%.2f m)" % burst_top)

	# Free flight is predicted like running: jump, hold aim to light the
	# jets, fly sideways, and the server agrees all the way.
	if me.flight.can_hover():
		await t.frames(60)
		me.cmd.jump_pressed = true
		await t.frames(1)
		me.cmd.jump_pressed = false
		await t.frames(12)
		me.cmd.secondary = true
		dana.max_correction = 0.0
		me.cmd.jump = true
		await t.frames(30)
		me.cmd.jump = false
		me.cmd.move = Vector2(1, 0)
		await t.frames(60)
		me.cmd.move = Vector2.ZERO
		await t.frames(40)
		var up := me.global_position.y - ground
		t.check(me.flight.is_hovering and up > 2.0, "a lagging player hovers on their own screen (%.1f m up)" % up)
		t.check(dana.max_correction < 0.4, "free flight on a slow connection needs no real correction (worst %.2f m)" % dana.max_correction)
		t.check(is_instance_valid(seen) and seen.flight.is_hovering and seen.global_position.distance_to(me.global_position) < 0.6,
				"the other player sees them hovering in the same place")
		me.cmd.descend = true
		await t._wait_until(func() -> bool: return me.is_on_floor(), 300)
		me.cmd.descend = false
		await t.frames(30)
		t.check(not me.flight.is_hovering and not seen.flight.is_hovering, "landing puts the jets out on both screens")
		me.cmd.secondary = false

	# Other players glide between updates instead of stepping.
	me.cmd.move = Vector2(1, 0)
	await t.frames(30)
	var even: Vector2 = await t._step_spread(seen, 60)
	t.check(even.x > 0.0 and even.y < even.x * 2.5 + 0.02,
			"another player's movement is even from tick to tick (%.3f to %.3f m)" % [even.x, even.y])
	# And when updates come unevenly, late and then several at once (a bad
	# connection, or a busy machine): a late update is about an earlier
	# moment, so it must not pull the body back to it.
	eli.simulated_jitter = 0.08
	await t.frames(30)
	var uneven: Vector2 = await t._step_spread(seen, 180)
	eli.simulated_jitter = 0.0
	me.cmd.move = Vector2.ZERO
	t.check(uneven.x > 0.0 and uneven.y < uneven.x * 2.0 + 0.02,
			"another player's movement stays even when updates arrive unevenly (%.3f to %.3f m)" % [uneven.x, uneven.y])
	await t.frames(90)
	var settled := seen.global_position.distance_to(me.global_position) if is_instance_valid(seen) else 99.0
	t.check(settled < 0.5, "and they still end up where they are (%.2f m apart)" % settled)
	await t._leave(eli)
	await t._leave(dana)
	OS.kill(pid)
	await t.frames(30)


## The least and most `actor` moves in one tick, over `ticks` ticks, as
## (least, most).
