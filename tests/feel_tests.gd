extends RefCounted
## Checks for core feel: the server's input buffer (no input delay left behind
## by lost packets), smooth flight and responsive guns.
## Run from the main test runner. None of it starts a server, so it runs in
## the offline tier: the session script is named only by its path here.

const Net := preload("res://core/net/net_session.gd")


static func run(t: Node) -> void:
	print("Feel: the server's input buffer")
	_test_input_buffer(t)
	print("Feel: flight")
	await _test_wings(t)
	print("Feel: guns and the view")
	await _test_guns(t)
	_test_view(t)


## Flat ground far from everything else, to move an actor about on.
static func _ground(t: Node, at: Vector3) -> Node3D:
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = at
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(600, 1, 600)
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	ground.position.y = -0.5
	arena.add_child(ground)
	return arena


static func _actor(arena: Node3D, kit: Array) -> Actor:
	var actor := Actor.new()
	arena.add_child(actor)
	Loadout.equip(actor, kit)
	actor.position = Vector3(0, 0.05, 0)
	return actor


## Runs `ticks` ticks and returns the hardest change of velocity in one of
## them, as m/s².
static func _jolt(t: Node, actor: Actor, ticks: int) -> float:
	var worst := 0.0
	var last := actor.velocity
	for i in ticks:
		await t.get_tree().physics_frame
		worst = maxf(worst, (actor.velocity - last).length() * Engine.physics_ticks_per_second)
		last = actor.velocity
	return worst


static func _test_wings(t: Node) -> void:
	var arena := _ground(t, Vector3(0, 0, -6000))
	var p := _actor(arena, ["pistol_service", "wings_glide"])
	await t.frames(5)
	# Handling only: a long session of moves, so no glide stamina limit and
	# fresh boosts where needed (both have checks of their own).
	p.flight.glide_heat = 0.0
	p.global_position.y = 300.0
	p.velocity = Vector3(0, -1, 0)
	await t.frames(40)
	# Opening the wings in a fall, diving, levelling out and pulling up: the
	# wings ease into each, they never snap in one tick.
	var fall := p.velocity.y
	p.cmd.jump = true
	var worst := await _jolt(t, p, 60)
	t.check(p.flight.is_gliding and fall < -10.0 and p.velocity.y >= -p.flight.glide_fall_speed - 0.01,
			"wings opened in a fall catch it and settle into the glide")
	p.cmd.move = Vector2(0, 1)
	worst = maxf(worst, await _jolt(t, p, 120))
	var dive := p.velocity.y
	p.cmd.move = Vector2.ZERO
	await t.frames(1)
	t.check(dive < -9.0 and p.velocity.y < dive * 0.8, "letting go of a dive eases out of it (%.1f then %.1f m/s down)" % [dive, p.velocity.y])
	worst = maxf(worst, await _jolt(t, p, 30))
	t.check(p.velocity.y >= -p.flight.glide_fall_speed - 0.01, "and is level again within half a second")
	p.cmd.move = Vector2(0, 1)
	await t.frames(120)
	p.cmd.move = Vector2(0, -1)
	worst = maxf(worst, await _jolt(t, p, 90))
	p.cmd.move = Vector2.ZERO
	t.check(worst < 90.0, "opening the wings, diving, levelling and pulling up never snap (hardest %.0f m/s² in a tick)" % worst)
	# The bank rolls in: a tap nudges the heading, a hold comes right round,
	# and letting go the wings come back onto the view.
	await t.frames(120)
	var before := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	p.cmd.move = Vector2(1, 0)
	await t.frames(3)
	p.cmd.move = Vector2.ZERO
	await t.frames(4)
	var nudged := before.angle_to(Vector3(p.velocity.x, 0, p.velocity.z).normalized())
	t.check(nudged > 0.005 and nudged < 0.08, "a tap of a strafe key nudges the wings' heading (%.3f rad)" % nudged)
	await t.frames(90)
	before = Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	p.cmd.move = Vector2(1, 0)
	await t.frames(30)
	var swung := before.angle_to(Vector3(p.velocity.x, 0, p.velocity.z).normalized())
	t.check(swung > p.flight.glide_turn_rate * 0.5 * 0.7, "and holding it turns at the full rate (%.2f rad in half a second)" % swung)
	p.cmd.move = Vector2.ZERO
	await t.frames(120)
	# Looking round in a glide: the wings bank round onto the view's heading
	# like a bird's and fly the way you face, never sideways to it.
	var flying := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	p.cmd.yaw = wrapf(atan2(-flying.x, -flying.z) + 2.4, -PI, PI)
	var view := Basis(Vector3.UP, p.cmd.yaw) * Vector3.FORWARD
	worst = await _jolt(t, p, 150)
	var off := view.angle_to(Vector3(p.velocity.x, 0, p.velocity.z).normalized())
	t.check(off < 0.05 and p.flight.is_gliding, "looking round turns the glide the way you face (%.3f rad off)" % off)
	t.check(worst < 90.0, "and the wings bank round onto it without a snap (hardest %.0f m/s² in a tick)" % worst)
	var settled := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	await t.frames(30)
	t.check(settled.angle_to(Vector3(p.velocity.x, 0, p.velocity.z).normalized()) < 0.02 and absf(p._bank) < 0.1,
			"and it levels out on the view instead of swinging past")
	# Free look: held, the wings fly straight on while the view looks away;
	# let go and they come round onto the view again.
	p.cmd.free_look = true
	var held := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	p.cmd.yaw = wrapf(p.cmd.yaw + 1.5, -PI, PI)
	await t.frames(60)
	t.check(held.dot(Vector3(p.velocity.x, 0, p.velocity.z).normalized()) > 0.999,
			"holding free look, the wings fly straight on while you look away")
	var copy := ActorCommand.new()
	copy.apply_array(p.cmd.to_array())
	t.check(copy.free_look, "free look travels in the network command")
	p.cmd.free_look = false
	view = Basis(Vector3.UP, p.cmd.yaw) * Vector3.FORWARD
	await t.frames(150)
	t.check(view.angle_to(Vector3(p.velocity.x, 0, p.velocity.z).normalized()) < 0.05,
			"and letting go the wings come round onto the view")
	await t.frames(60)
	# A wing boost thrusts you the way you face and the glide keeps the speed.
	var cruising := Vector2(p.velocity.x, p.velocity.z).length()
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	await t.frames(1)
	p.cmd.sprint_pressed = false
	p.cmd.sprint = false
	var kicked := Vector2(p.velocity.x, p.velocity.z).length()
	await t.frames(60)
	var carried := Vector2(p.velocity.x, p.velocity.z).length()
	t.check(kicked > cruising + p.flight.glide_boost * 0.9 and p.flight.charges < p.flight.max_charges,
			"Shift in a glide boosts you ahead, on a charge (%.1f to %.1f m/s)" % [cruising, kicked])
	t.check(carried > cruising + p.flight.glide_boost * 0.7 and view.angle_to(Vector3(p.velocity.x, 0, p.velocity.z).normalized()) < 0.05,
			"and the glide carries that speed on the way you face (%.1f m/s a second later)" % carried)
	# Shift + D is the same boost: wings never dash sideways.
	await t.frames(120)
	p.cmd.move = Vector2(1, 0)
	p.cmd.sprint_pressed = true
	await t.frames(1)
	p.cmd.sprint_pressed = false
	p.cmd.move = Vector2.ZERO
	var side := (Basis(Vector3.UP, p.cmd.yaw).inverse() * p.velocity).x
	t.check(absf(side) < 2.0, "Shift + D in a glide never throws you sideways (%.1f m/s)" % side)
	await t.frames(240)
	# Shift + S with the wings pulled up climbs, keeping the heading.
	var climb_heading := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	var height := p.global_position.y
	p.flight.charges = p.flight.max_charges
	p.cmd.move = Vector2(0, -1)
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	await t.frames(1)
	p.cmd.sprint_pressed = false
	var rise := p.velocity.y
	await t.frames(40)
	p.cmd.sprint = false
	var flat := Vector3(p.velocity.x, 0, p.velocity.z)
	t.check(rise > p.flight.glide_boost_climb * 0.8 and p.flight.charges == p.flight.max_charges - 1,
			"Shift + S in a glide boosts upward, on a charge (%.1f m/s up)" % rise)
	t.check(p.global_position.y > height + 2.0 and flat.normalized().dot(climb_heading) > 0.95
			and flat.length() >= p.flight.glide_speed * p.flight.glide_stall - 0.01 and p.flight.is_gliding,
			"and gains height flying on the same way, never backwards (%.1f m higher)" % (p.global_position.y - height))
	p.cmd.move = Vector2.ZERO
	# Pulled up hard in a turn, the wings bleed their speed and stall into a
	# sinking spiral instead of circling in place for free.
	await t.frames(240)
	p.cmd.move = Vector2(1, -1)
	await t.frames(300)
	var spiral := Vector2(p.velocity.x, p.velocity.z).length()
	t.check(p.glide_stalled() and p.velocity.y < -p.flight.stall_sink + 0.5,
			"S + D bleeds the speed into a stall that sinks (%.1f m/s ahead, %.1f down)" % [spiral, -p.velocity.y])
	p.cmd.move = Vector2.ZERO
	await t.frames(120)
	t.check(not p.glide_stalled() and Vector2(p.velocity.x, p.velocity.z).length() > p.flight.glide_speed * p.flight.glide_stall,
			"letting go, the nose drops and the wings fly again")
	arena.queue_free()
	await t.frames(2)


static func _test_guns(t: Node) -> void:
	var arena := _ground(t, Vector3(0, 0, -7000))
	var p := _actor(arena, ["pistol_service"])
	await t.frames(20)
	var pistol := p.weapons[0] as Gun
	var press := func() -> void:
		p.cmd.primary_pressed = true
		await t.frames(1)
		p.cmd.primary_pressed = false
	# A semi-auto fired a moment early still fires, as soon as it can.
	await press.call()
	t.check(pistol.ammo_in_mag == pistol.mag_size - 1, "a semi-auto fires on the pull")
	await t.frames(int(pistol.fire_interval * 60.0) - 5)
	await press.call()
	t.check(pistol.ammo_in_mag == pistol.mag_size - 1, "a pull between shots does not fire early")
	await t.frames(6)
	t.check(pistol.ammo_in_mag == pistol.mag_size - 2, "but it is remembered, and fires the moment the gun is ready")
	await t.frames(30)
	t.check(pistol.ammo_in_mag == pistol.mag_size - 2, "one pull is one shot")
	await press.call()
	await press.call()
	await t.frames(40)
	t.check(pistol.ammo_in_mag == pistol.mag_size - 3, "a pull long before the gun is ready is forgotten")
	# The same for a pull as a reload ends.
	p.cmd.reload_pressed = true
	await t.frames(1)
	p.cmd.reload_pressed = false
	await t.frames(int(pistol.reload_time * 60.0) - 4)
	await press.call()
	await t.frames(8)
	t.check(pistol.ammo_in_mag == pistol.mag_size - 1, "a pull as a reload ends fires when it is done")
	# Spread is a round cone as wide as the gun says, never a square.
	var aim := Vector3(0.3, 0.2, -1.0).normalized()
	var spread := deg_to_rad(4.5)
	var widest := 0.0
	var mean := Vector3.ZERO
	for i in 400:
		var dir := Gun.spread_dir(aim, spread, fmod(i * 0.618034, 1.0), (i % 20 + 1) / 20.0)
		widest = maxf(widest, aim.angle_to(dir))
		mean += dir
	t.check(widest < spread * 1.01 and widest > spread * 0.98, "shots spread over a round cone exactly as wide as the gun's spread")
	t.check(aim.angle_to(mean.normalized()) < 0.01 and is_equal_approx(aim.angle_to(Gun.spread_dir(aim, spread, 0.3, 0.0)), 0.0),
			"centred on the aim")
	t.check(Gun.spread_dir(Vector3.UP, spread, 0.25, 1.0).is_normalized(), "also when aiming straight up")
	# A harder kicking gun jumps further in the hand, and less when aimed.
	var smg := Gun.new()
	Loadout._setup_weapon(smg, "smg_stinger", ItemDB.item_stats("smg_stinger"))
	var cannon := Gun.new()
	Loadout._setup_weapon(cannon, "pistol_hand_cannon", ItemDB.item_stats("pistol_hand_cannon"))
	t.check(cannon.model_kick().x > smg.model_kick().x * 2.0 and cannon.model_kick().x <= Gun.MODEL_KICK.x * Gun.MODEL_KICK_MAX + 0.0001,
			"a hand cannon jumps further in the hand than an SMG, within a limit")
	var hip := cannon.model_kick()
	cannon._aiming = true
	t.check(cannon.model_kick().x < hip.x * 0.5, "and a gun jumps less while aimed, so a scope stays off the eye")
	smg.free()
	cannon.free()
	arena.queue_free()
	await t.frames(2)


static func _test_view(t: Node) -> void:
	var p := Actor.new()
	var controller := PlayerController.new()
	controller.actor = p
	var gun := Gun.new()
	gun.recoil_kick_deg = 2.0
	gun.recoil_side_deg = 0.0
	var kick := deg_to_rad(gun.recoil_kick_deg)
	# A shot's kick reaches the view over a few frames, then settles back.
	controller._on_gun_fired(Vector3.ZERO, Vector3.ZERO, gun)
	t.check(is_zero_approx(controller.pitch), "a shot does not snap the view in one frame")
	controller._update_recoil(1.0 / 60.0)
	t.check(controller.pitch > kick * 0.3 and controller.pitch < kick * 0.8, "the kick arrives over a few frames")
	for i in 4:
		controller._update_recoil(1.0 / 60.0)
	t.check(controller.pitch > kick * 0.9, "and is all there within a tenth of a second (%.0f%%)" % (controller.pitch / kick * 100.0))
	for i in 60:
		controller._update_recoil(1.0 / 60.0)
	t.check(absf(controller.pitch) < kick * 0.02, "once the trigger rests the view settles back to where it was aimed")
	# Kick the player pulled down against is theirs to keep.
	controller.pitch = 0.0
	controller._on_gun_fired(Vector3.ZERO, Vector3.ZERO, gun)
	for i in 5:
		controller._update_recoil(1.0 / 60.0)
	controller.pitch -= controller._kick_held
	controller._kick_held = 0.0
	var held := controller.pitch
	for i in 60:
		controller._update_recoil(1.0 / 60.0)
	t.check(is_equal_approx(controller.pitch, held), "kick you pulled down against is not given back")
	# Speed widens the view, from a sprint up.
	t.check(is_zero_approx(controller.speed_fov_for(p.sprint_speed)) and controller.speed_fov_for(FlightRig.CRUISE_SPEED) > 1.0
			and controller.speed_fov_for(FlightRig.CRUISE_SPEED) < controller.speed_fov * 0.5
			and is_equal_approx(controller.speed_fov_for(40.0), controller.speed_fov),
			"speed widens the view: nothing at a sprint, a little at cruise, all of it in a dive or on a bike")
	# A landing dips the view and it springs back.
	controller._on_landed(12.0)
	var deepest := 0.0
	for i in 20:
		controller._update_dip(1.0 / 60.0)
		deepest = maxf(deepest, controller._dip)
	t.check(deepest > 0.08 and deepest < controller.land_dip_max, "a hard landing dips the view (%.2f m)" % deepest)
	for i in 60:
		controller._update_dip(1.0 / 60.0)
	t.check(is_zero_approx(controller._dip), "and it springs back to rest")
	gun.free()
	controller.free()
	p.free()


static func _input(number: int, flags := 0, switch := -1) -> Array:
	var cmd := ActorCommand.new().to_array()
	cmd[ActorCommand.FLAGS_INDEX] = flags
	cmd[ActorCommand.SWITCH_INDEX] = switch
	return [number, cmd, number]


## Plays `ticks` ticks of a client sending one numbered input a tick over a
## connection that loses packets, each packet repeating every input the
## server has not had yet. Returns what the server made of it.
static func _play_link(buffer: Net.InputBuffer, ticks: int, lost: Callable, press_every := 0) -> Dictionary:
	var unanswered: Array = []
	var presses_sent := 0
	var presses_played := 0
	var behind := 0
	var worst := 0
	var order_ok := true
	var last_played := buffer.played
	var from := buffer.newest
	for tick in ticks:
		var number := from + tick + 1
		var pressed := press_every > 0 and tick % press_every == 0
		if pressed:
			presses_sent += 1
		unanswered.append(_input(number, ActorCommand.FLAG_JUMP_PRESSED if pressed else 0))
		if unanswered.size() > Net.MAX_INPUTS_PER_PACKET:
			unanswered.pop_front()
		if not lost.call(tick):
			buffer.receive(unanswered.duplicate(true))
			# The answer: the server has everything up to here.
			unanswered = unanswered.filter(func(input: Array) -> bool: return input[0] > buffer.newest)
		var input := buffer.next()
		if not input.is_empty() and int(input[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_JUMP_PRESSED != 0:
			presses_played += 1
		order_ok = order_ok and buffer.played >= last_played
		last_played = buffer.played
		behind += number - buffer.played
		worst = maxi(worst, number - buffer.played)
	return {"sent": presses_sent, "played": presses_played, "behind": float(behind) / ticks, "worst": worst,
			"order": order_ok}


static func _test_input_buffer(t: Node) -> void:
	var never := func(_tick: int) -> bool: return false
	var buffer := Net.InputBuffer.new()
	var clean := _play_link(buffer, 300, never, 7)
	t.check(clean.played == clean.sent and buffer.guessed == 0 and buffer.skipped == 0 and buffer.played == 300,
			"on a clean connection every input is played once, in order, with no guessing")
	t.check(is_zero_approx(clean.behind), "and the server is never behind the player's inputs")

	# One packet in five lost, for ten seconds. The old queue filled to its
	# limit here and stayed five or six inputs (about 80 ms) behind.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	buffer = Net.InputBuffer.new()
	var lossy := _play_link(buffer, 600, func(_tick: int) -> bool: return rng.randf() < 0.2, 7)
	t.check(lossy.behind < 0.5 and buffer.queue.size() <= 1,
			"with one packet in five lost the server stays with the player's inputs (%.2f behind on average, %d waiting)"
			% [lossy.behind, buffer.queue.size()])
	t.check(lossy.played == lossy.sent, "and every press is still played exactly once (%d of %d)" % [lossy.played, lossy.sent])
	t.check(lossy.order and buffer.guessed > 60, "lost ticks are played as guesses, and the count never goes back")

	# A lost packet: the tick is guessed and counted, and the real input is
	# skipped when it arrives with the next one, keeping its press.
	buffer = Net.InputBuffer.new()
	buffer.receive([_input(1)])
	buffer.next()
	t.check(buffer.next().is_empty() and buffer.played == 2 and buffer.guessed == 1,
			"a tick with nothing to play is a guess that counts as the next input")
	buffer.receive([_input(2, ActorCommand.FLAG_DASH, 1), _input(3)])
	var third := buffer.next()
	t.check(third[0] == 3 and buffer.played == 3 and buffer.queue.is_empty(),
			"the input the guess stood in for is skipped when it arrives late")
	t.check(int(third[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_DASH != 0 and third[1][ActorCommand.SWITCH_INDEX] == 1,
			"and its press and weapon switch ride on the next input played")
	t.check(int(_input(4)[1][ActorCommand.FLAGS_INDEX]) == 0 and buffer.next().is_empty(), "a kept press is played once")

	# A trigger tapped for a single tick, in an input that is skipped: the
	# tap rides on the next input played. A client running under 60 frames a
	# second sends its inputs two to a packet, so one late packet used to eat
	# every other input, and with it any shot that short.
	buffer = Net.InputBuffer.new()
	buffer.receive([_input(1)])
	buffer.next()
	buffer.next()
	buffer.receive([_input(2, ActorCommand.FLAG_PRIMARY), _input(3)])
	var tapped := buffer.next()
	t.check(tapped[0] == 3 and int(tapped[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_PRIMARY != 0,
			"a trigger tapped in an input that arrives late still fires, on the next input played")
	buffer.receive([_input(4)])
	t.check(int(buffer.next()[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_PRIMARY == 0, "a kept tap is played once")
	# Held before the skipped input and let go after it: the guess already
	# played that tick with the key down, so nothing is added.
	buffer = Net.InputBuffer.new()
	buffer.receive([_input(1, ActorCommand.FLAG_PRIMARY)])
	buffer.next()
	buffer.next()
	buffer.receive([_input(2, ActorCommand.FLAG_PRIMARY), _input(3)])
	t.check(int(buffer.next()[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_PRIMARY == 0,
			"a key that was already held is not held a tick longer")
	# The same for inputs folded away after a burst.
	buffer = Net.InputBuffer.new()
	var taps: Array = []
	for number in range(1, 13):
		taps.append(_input(number, ActorCommand.FLAG_PRIMARY if number == 3 else 0))
	buffer.receive(taps)
	t.check(int(buffer.next()[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_PRIMARY != 0
			and int(buffer.next()[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_PRIMARY == 0,
			"a tap in an input folded away after a burst is played once too")
	# Every other input skipped, as for a client at 30 frames a second after
	# one late packet: each tap is still played exactly once.
	buffer = Net.InputBuffer.new()
	buffer.receive([_input(1), _input(2)])
	buffer.next()
	buffer.next()
	buffer.next()
	var taps_played := 0
	for pair in 40:
		var number := 3 + pair * 2
		buffer.receive([_input(number, ActorCommand.FLAG_PRIMARY if pair % 3 == 0 else 0), _input(number + 1)])
		for tick in 2:
			var input := buffer.next()
			if not input.is_empty() and int(input[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_PRIMARY != 0:
				taps_played += 1
	t.check(taps_played == 14 and buffer.skipped >= 40,
			"with inputs arriving in pairs, one always late, every tap is played once (%d of 14, %d inputs skipped)"
			% [taps_played, buffer.skipped])

	# Late and still the newest: the player's inputs are running later than
	# the server thought, so it is played after all.
	buffer = Net.InputBuffer.new()
	buffer.receive([_input(1)])
	buffer.next()
	buffer.next()
	buffer.receive([_input(2, ActorCommand.FLAG_SPRINT)])
	var late := buffer.next()
	t.check(not late.is_empty() and late[0] == 2 and buffer.played == 2,
			"a late input that is the newest there is gets played, under the number the guess took")
	buffer.receive([_input(3)])
	t.check(buffer.next()[0] == 3 and buffer.played == 3, "and the inputs after it carry on in order")

	# A long silence is a stall, not a run of guesses.
	buffer = Net.InputBuffer.new()
	buffer.receive([_input(1)])
	for i in 100:
		buffer.next()
	t.check(buffer.played == 1 + Net.MAX_GUESSED_INPUTS,
			"the server guesses only %d inputs ahead of what it has received" % Net.MAX_GUESSED_INPUTS)
	var resumed: Array = []
	for number in range(2, 14):
		buffer.receive([_input(number)])
		var input := buffer.next()
		resumed.append(input[0] if not input.is_empty() else 0)
	t.check(not 0 in resumed and resumed[-1] == 13 and buffer.played == 13,
			"after a stall the newest keys are played at once and the count picks up (%s)" % str(resumed))

	# A burst after a stall is folded down, and spare inputs do not stay.
	buffer = Net.InputBuffer.new()
	var burst: Array = []
	for number in range(1, 13):
		burst.append(_input(number, ActorCommand.FLAG_RELOAD_PRESSED if number == 2 else 0))
	buffer.receive(burst)
	t.check(buffer.queue.size() == Net.MAX_QUEUED_INPUTS, "a burst is folded down to the queue limit")
	var first := buffer.next()
	t.check(int(first[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_RELOAD_PRESSED != 0, "keeping the presses of what was folded")
	var steady := _play_link(buffer, 120, never)
	t.check(buffer.queue.is_empty() and steady.order,
			"inputs that stay spare are trimmed away, so a burst leaves no delay behind (%d waiting)" % buffer.queue.size())

	# Inputs travel packed small: a full packet fits in one datagram.
	var full: Array = []
	for number in Net.MAX_INPUTS_PER_PACKET:
		full.append(_input(70000 + number, ActorCommand.FLAG_SPRINT_PRESSED | ActorCommand.FLAG_JUMP, ActorCommand.HOLSTER))
	full[3][1][0] = -0.5
	full[3][1][2] = 123.25
	full[3][1][ActorCommand.STANCE_INDEX] = 2
	var packet := Net.pack_inputs(full)
	t.check(packet.size() < 1200, "a full input packet fits in one datagram (%d bytes)" % packet.size())
	t.check(Net.unpack_inputs(packet) == full, "and unpacks to the same inputs")
	packet.resize(packet.size() - 1)
	t.check(Net.unpack_inputs(packet).is_empty(), "a packet of the wrong size is refused")

	# A new life starts clean: nothing is guessed before its first input, and
	# packets from the old life are ignored.
	buffer.rest()
	var before := buffer.played
	t.check(buffer.next().is_empty() and buffer.played == before and not buffer.live, "nothing is guessed between lives")
	buffer.receive([_input(before - 1), _input(before + 1)])
	t.check(buffer.next()[0] == before + 1 and buffer.live, "a new life plays only inputs made after the old one")
