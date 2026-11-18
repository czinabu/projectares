extends RefCounted
## Reconnecting after a dropped connection (DESIGN.md section 14, "Reconnect
## on its own"): the body stays standing (`Raid.remove_player`), a new
## sign-in to the account takes it back (`NetSession._back`,
## `Raid.reclaim_player`) with no deploy, and the game does that on its own
## (`Main._on_online_disconnected`). Starts a server, so it runs in the
## online tier. `-- --groups ReconnectTests` runs just these.

const PORT := 25341


static func run(t: Node) -> void:
	print("Reconnect: back into your body after a drop")
	_client_side(t)
	var pid: int = t._start_server(PORT, ["--bots", "0"] as Array[String])
	await _session_level(t)
	await _game_level(t)
	OS.kill(pid)
	await t.frames(30)


## How a game takes the server's word on coming back.
static func _client_side(t: Node) -> void:
	var session := NetSession.new()
	t.add_child(session)
	session._back(NetSession.BACK_IN_BODY)
	t.check(session.resuming and session.missed_outcome == "", "told it is going back in its body, a game waits for it")
	var other := NetSession.new()
	t.add_child(other)
	other._back("left")
	other._back("anything else")
	t.check(not other.resuming and other.missed_outcome == "left", "or hears how the life it missed ended")
	other._replaced()
	t.check(other.replaced, "and a connection let go for a newer sign-in knows it")
	session.queue_free()
	other.queue_free()


## Two sessions with one account: a drop, a sign-in that takes the body
## back, and a sign-in that pushes an older live connection out.
static func _session_level(t: Node) -> void:
	var first: NetSession = await t._join("Rook", PORT)
	t.check(first != null, "a player is out in a world")
	if first == null:
		return
	await t.frames(30)
	var body_id := first.my_actor_id
	var stood_at: Vector3 = first.raid.player.global_position
	# The connection drops: the server hears the peer go.
	first._api.multiplayer_peer.close()
	await t._leave(first)
	await t.frames(30)

	var back: NetSession = await t._sign_in("Rook", PORT)
	t.check(back != null, "the same account signs in again")
	if back == null:
		return
	await t._wait_until(func() -> bool: return back.raid != null and back.raid.player != null, 240)
	t.check(back.resuming and back.my_actor_id == body_id and back.raid != null and back.raid.player != null,
			"signing in again puts you back in the body you left, with no deploy")
	if back.raid != null and back.raid.player != null:
		t.check(back.raid.player.global_position.distance_to(stood_at) < 2.0,
				"standing where it was left (%.2f m)" % back.raid.player.global_position.distance_to(stood_at))
		var state := back.raid.state_for(back.raid.player)
		t.check(state != null and state.sign_out_left < 0.0, "with no sign-out running on it")
	t.check(back.account.get("deployed", false), "and the life goes on: nothing was settled")

	# Another game signs in while this one is still connected (or its drop
	# has not been noticed yet): the older one is told, and the body moves.
	var dropped := [false]
	back.disconnected.connect(func() -> void: dropped[0] = true)
	var third: NetSession = await t._sign_in("Rook", PORT)
	await t._wait_until(func() -> bool: return dropped[0] and third != null and third.raid != null \
			and third.raid.player != null, 240)
	t.check(back.replaced and dropped[0], "an older connection is told it was replaced, so it does not fight back")
	t.check(third != null and third.resuming and third.my_actor_id == body_id,
			"and the newest sign-in takes the body over")
	await t._leave(back)
	if third != null:
		third.sign_out()
	await t._leave(third)


## The game itself: a drop out in a world reconnects on its own, and a
## server that is gone ends in the base with a reason.
static func _game_level(t: Node) -> void:
	Profile.reset()
	Profile.home_server = ""
	Profile.player_name = "Quill"
	Profile.welcome_granted = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.host_args = PackedStringArray(["--accounts", t.NET_ACCOUNTS, "--bots", "0"])
	t.add_child(main)
	await t.frames(20)
	main.join_online("127.0.0.1:%d" % PORT, false)
	await t._wait_until(func() -> bool: return main.net != null and not main.net.account.is_empty() \
			and main.base != null, 900)
	t.check(main.net != null and main.base != null, "the game signs in to a world's lobby")
	if main.net == null:
		await _done(t, main)
		return
	main.net.deploy()
	await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 900)
	t.check(main.raid != null and main.raid.player != null, "and deploys")
	if main.raid == null:
		await _done(t, main)
		return
	await t.frames(30)
	var body_id: int = main.net.my_actor_id

	# The connection drops out in the world.
	_drop(main)
	await t.frames(2)
	t.check(main.raid == null and main.net != null and main._reconnect_until > 0,
			"a drop starts reconnecting on its own, with no button")
	await t._wait_until(func() -> bool: return main.raid != null and main.raid.player != null, 900)
	t.check(main.raid != null and main.net != null and main.net.resuming and main.net.my_actor_id == body_id
			and main._reconnect_until == 0, "the game reconnects and puts you back in your body")

	# A drop in the lobby comes back to the lobby.
	if main.raid != null:
		main.net.sign_out()
		await t._wait_until(func() -> bool: return main.raid == null and main.base != null \
				and main.net != null and not main.net.account.is_empty(), 1800)
	t.check(main.raid == null and main.base != null, "signed out, back in the lobby")
	_drop(main)
	await t._wait_until(func() -> bool: return main._reconnect_until == 0 and main.net != null \
			and not main.net.account.is_empty() and main.base != null and main.hub.in_lobby(), 900)
	t.check(main.net != null and main.base != null and main.hub.in_lobby() and main.raid == null,
			"a drop in a world's lobby reconnects to the lobby")

	# Nobody answers: given up on once the window closes, home with a reason.
	main.reconnect_window = 2.0
	var port_taken: int = main._join_port
	main._join_port = PORT + 7
	_drop(main)
	await t._wait_until(func() -> bool: return main._reconnect_until == 0 and main.net == null, 900)
	t.check(main.net == null and main.base != null and not main.hub.in_lobby(),
			"when the server never answers, the game gives up and goes home")
	main._join_port = port_taken
	await _done(t, main)


## Cuts the game's connection the way a network fault would look to it.
static func _drop(main: Node) -> void:
	var net: NetSession = main.net
	if net == null:
		return
	net._api.multiplayer_peer.close()
	net._on_server_disconnected()


static func _done(t: Node, main: Node) -> void:
	main.queue_free()
	await t.frames(10)
	Profile.reset()
