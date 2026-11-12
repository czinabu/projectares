extends RefCounted
## Checks for core feel: the server's input buffer (no input delay left behind
## by lost packets), smooth flight and responsive guns.
## Run from the main test runner.


static func run(t: Node) -> void:
	print("Feel: the server's input buffer")
	_test_input_buffer(t)


static func _input(number: int, flags := 0, switch := -1) -> Array:
	var cmd := ActorCommand.new().to_array()
	cmd[ActorCommand.FLAGS_INDEX] = flags
	cmd[ActorCommand.SWITCH_INDEX] = switch
	return [number, cmd, number]


## Plays `ticks` ticks of a client sending one numbered input a tick over a
## connection that loses packets, each packet repeating every input the
## server has not had yet. Returns what the server made of it.
static func _play_link(buffer: NetSession.InputBuffer, ticks: int, lost: Callable, press_every := 0) -> Dictionary:
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
		if unanswered.size() > NetSession.MAX_INPUTS_PER_PACKET:
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
	var buffer := NetSession.InputBuffer.new()
	var clean := _play_link(buffer, 300, never, 7)
	t.check(clean.played == clean.sent and buffer.guessed == 0 and buffer.skipped == 0 and buffer.played == 300,
			"on a clean connection every input is played once, in order, with no guessing")
	t.check(is_zero_approx(clean.behind), "and the server is never behind the player's inputs")

	# One packet in five lost, for ten seconds. The old queue filled to its
	# limit here and stayed five or six inputs (about 80 ms) behind.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	buffer = NetSession.InputBuffer.new()
	var lossy := _play_link(buffer, 600, func(_tick: int) -> bool: return rng.randf() < 0.2, 7)
	t.check(lossy.behind < 0.5 and buffer.queue.size() <= 1,
			"with one packet in five lost the server stays with the player's inputs (%.2f behind on average, %d waiting)"
			% [lossy.behind, buffer.queue.size()])
	t.check(lossy.played == lossy.sent, "and every press is still played exactly once (%d of %d)" % [lossy.played, lossy.sent])
	t.check(lossy.order and buffer.guessed > 60, "lost ticks are played as guesses, and the count never goes back")

	# A lost packet: the tick is guessed and counted, and the real input is
	# skipped when it arrives with the next one, keeping its press.
	buffer = NetSession.InputBuffer.new()
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

	# Late and still the newest: the player's inputs are running later than
	# the server thought, so it is played after all.
	buffer = NetSession.InputBuffer.new()
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
	buffer = NetSession.InputBuffer.new()
	buffer.receive([_input(1)])
	for i in 100:
		buffer.next()
	t.check(buffer.played == 1 + NetSession.MAX_GUESSED_INPUTS,
			"the server guesses only %d inputs ahead of what it has received" % NetSession.MAX_GUESSED_INPUTS)
	var resumed: Array = []
	for number in range(2, 14):
		buffer.receive([_input(number)])
		var input := buffer.next()
		resumed.append(input[0] if not input.is_empty() else 0)
	t.check(not 0 in resumed and resumed[-1] == 13 and buffer.played == 13,
			"after a stall the newest keys are played at once and the count picks up (%s)" % str(resumed))

	# A burst after a stall is folded down, and spare inputs do not stay.
	buffer = NetSession.InputBuffer.new()
	var burst: Array = []
	for number in range(1, 13):
		burst.append(_input(number, ActorCommand.FLAG_RELOAD_PRESSED if number == 2 else 0))
	buffer.receive(burst)
	t.check(buffer.queue.size() == NetSession.MAX_QUEUED_INPUTS, "a burst is folded down to the queue limit")
	var first := buffer.next()
	t.check(int(first[1][ActorCommand.FLAGS_INDEX]) & ActorCommand.FLAG_RELOAD_PRESSED != 0, "keeping the presses of what was folded")
	var steady := _play_link(buffer, 120, never)
	t.check(buffer.queue.is_empty() and steady.order,
			"inputs that stay spare are trimmed away, so a burst leaves no delay behind (%d waiting)" % buffer.queue.size())

	# Inputs travel packed small: a full packet fits in one datagram.
	var full: Array = []
	for number in NetSession.MAX_INPUTS_PER_PACKET:
		full.append(_input(70000 + number, ActorCommand.FLAG_ROLL_RIGHT | ActorCommand.FLAG_JUMP, ActorCommand.HOLSTER))
	full[3][1][0] = -0.5
	full[3][1][2] = 123.25
	full[3][1][ActorCommand.STANCE_INDEX] = 2
	var packet := NetSession.pack_inputs(full)
	t.check(packet.size() < 1200, "a full input packet fits in one datagram (%d bytes)" % packet.size())
	t.check(NetSession.unpack_inputs(packet) == full, "and unpacks to the same inputs")
	packet.resize(packet.size() - 1)
	t.check(NetSession.unpack_inputs(packet).is_empty(), "a packet of the wrong size is refused")

	# A new life starts clean: nothing is guessed before its first input, and
	# packets from the old life are ignored.
	buffer.rest()
	var before := buffer.played
	t.check(buffer.next().is_empty() and buffer.played == before and not buffer.live, "nothing is guessed between lives")
	buffer.receive([_input(before - 1), _input(before + 1)])
	t.check(buffer.next()[0] == before + 1 and buffer.live, "a new life plays only inputs made after the old one")
