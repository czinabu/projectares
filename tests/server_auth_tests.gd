extends RefCounted
## The hardening pass on the server (DESIGN.md section 14): signing in and
## the version check happen in the connection handshake
## (`SceneMultiplayer.auth_callback`), so an old, unknown or wrongly signed
## game never connects; the server never relays one client's calls to
## another; and each player's requests are limited (`NetSession.RequestLimits`).
## Starts a server, so it runs in the online tier.
## `-- --groups ServerAuthTests` runs just these.

const PORT := 25311
const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Server hardening: sign-in in the handshake, no relay, request limits")
	_limits(t)
	_client_answers(t)

	var pid: int = t._start_server(PORT, ["--bots", "0"] as Array[String])
	var ada: NetSession = await t._sign_in("Ada", PORT)
	t.check(ada != null, "a game of this version signs in during the handshake")
	if ada == null:
		OS.kill(pid)
		return

	# Another version, or not a game at all, is answered and turned away.
	var older: Dictionary = await _raw_sign_in(t, {"protocol": NetSession.PROTOCOL - 1, "name": "Olde",
			"secret": StashService.new_secret()})
	t.check(not older.answer.get("ok", true) and older.answer.get("outdated", "") == "client"
			and int(older.answer.get("protocol", 0)) == NetSession.PROTOCOL and not older.connected,
			"an older game is told it is the one out of date, with the server's version, and never connects")
	var newer: Dictionary = await _raw_sign_in(t, {"protocol": NetSession.PROTOCOL + 1, "name": "Neue",
			"secret": StashService.new_secret()})
	t.check(newer.answer.get("outdated", "") == "server" and not newer.connected,
			"a newer game is told the server is the one out of date")
	var junk: Dictionary = await _raw_sign_in(t, PackedByteArray([7, 7, 7]))
	t.check(not junk.answer.get("ok", true) and not junk.connected, "a sign-in that is not one is turned away")
	var wrong: Dictionary = await _raw_sign_in(t, {"protocol": NetSession.PROTOCOL, "name": "Ada",
			"secret": StashService.new_secret()})
	t.check(not wrong.answer.get("ok", true) and str(wrong.answer.get("error", "")) != "" and not wrong.connected,
			"someone else's name with the wrong secret never connects")

	# No relay: a client only ever sees the server.
	var bo: NetSession = await t._sign_in("Bodil", PORT)
	await t.frames(10)
	t.check(bo != null and Array(ada._api.get_peers()) == [1] and Array(bo._api.get_peers()) == [1],
			"with two players on, each game only knows the server")

	# Too many requests: told to slow down, and a flood is cut off.
	var errors: Array[String] = []
	ada.lobby_error.connect(func(reason: String) -> void: errors.append(reason))
	for i in 80:
		ada._request_equip.rpc_id(1, "primary", "")
	await t._wait_until(func() -> bool: return errors.any(func(e: String) -> bool: return "Slow down" in e), 120)
	t.check(errors.any(func(e: String) -> bool: return "Slow down" in e) and ada._is_connected(),
			"a burst of lobby requests past the limit is told to slow down and stays connected")
	if bo != null:
		var dropped := [false]
		bo.failed.connect(func(_reason: String) -> void: dropped[0] = true)
		bo.disconnected.connect(func() -> void: dropped[0] = true)
		for i in 600:
			bo._request_ping.rpc_id(1)
		await t._wait_until(func() -> bool: return dropped[0], 240)
		t.check(dropped[0], "a connection that floods the server is dropped")
	var cy: NetSession = await t._sign_in("Cyra", PORT)
	t.check(cy != null and ada._is_connected(), "the server keeps serving everyone else")

	await t._leave(ada)
	await t._leave(bo)
	await t._leave(cy)
	OS.kill(pid)
	await t.frames(30)


## The limiter on its own: a burst, then a steady rate, then a flood.
static func _limits(t: Node) -> void:
	var limits := NetSession.RequestLimits.new()
	var burst := int(NetSession.RequestLimits.KINDS.social[1])
	var allowed := 0
	for i in burst + 5:
		if limits.allow(7, "social", 0):
			allowed += 1
	t.check(allowed == burst, "a player gets a burst of requests at once (%d)" % allowed)
	t.check(not limits.allow(7, "social", 1) and limits.allow(7, "social", 40),
			"then a steady rate as the bucket refills by tick")
	t.check(limits.allow(8, "social", 1) and limits.allow(7, "lobby", 40), "each player and kind has its own bucket")
	t.check(limits.may_warn(7, 40) and not limits.may_warn(7, 41)
			and limits.may_warn(7, 41 + NetSession.RequestLimits.WARN_EVERY), "slow-down notices are spaced out")
	t.check(not limits.flooding(7), "a few refused requests are not a flood")
	for i in NetSession.RequestLimits.KICK_AFTER:
		limits.allow(7, "social", 41)
	t.check(limits.flooding(7) and not limits.flooding(8), "hundreds refused at once are")
	limits.forget(7)
	t.check(not limits.flooding(7) and limits.allow(7, "social", 41), "a player who leaves starts afresh")
	var steady := 0
	for tick in 600:
		if limits.allow(9, "input", tick):
			steady += 1
	t.check(steady == 600, "a game's own input, one packet a tick, is never limited")


## How a game takes the server's answer to signing in.
static func _client_answers(t: Node) -> void:
	var cases := [
		[{"ok": false, "protocol": NetSession.PROTOCOL + 1, "outdated": "client"}, "client"],
		[{"ok": false, "protocol": NetSession.PROTOCOL - 1, "outdated": "server"}, "server"],
		[{"ok": true, "protocol": NetSession.PROTOCOL - 1, "world": "ashfront"}, "server"],
		[{"ok": false, "protocol": NetSession.PROTOCOL, "error": "That name belongs to someone else."}, ""],
	]
	for case: Array in cases:
		var session := NetSession.new()
		t.add_child(session)
		var said := [""]
		session.failed.connect(func(reason: String) -> void: said[0] = reason)
		session._client_auth(1, var_to_bytes(case[0]))
		t.check(session.outdated == case[1] and session.refused and said[0] != "",
				"a game told %s knows which side is out of date (\"%s\")" % [JSON.stringify(case[0]), said[0]])
		session.queue_free()
	var updater := NetSession.new()
	t.add_child(updater)
	var reason := [""]
	updater.failed.connect(func(text: String) -> void: reason[0] = text)
	updater._client_auth(1, var_to_bytes({"ok": false, "protocol": NetSession.PROTOCOL + 1, "outdated": "client"}))
	t.check("update" in reason[0] and "Servers app" in reason[0],
			"an out-of-date game is pointed at the update on the phone")
	updater.queue_free()
	var unknown := NetSession.new()
	t.add_child(unknown)
	unknown._client_auth(1, var_to_bytes({"ok": true, "protocol": NetSession.PROTOCOL, "world": "no_such_world"}))
	t.check(unknown.refused and unknown.outdated == "", "a server running a world this game lacks is refused")
	unknown.queue_free()
	t.check(NetSession.UPDATE_URL.begins_with("https://"), "the update link is a web page")


## Connects with a bare SceneMultiplayer and sends `hello` as the sign-in
## (a Dictionary, or raw bytes). Returns {"answer", "connected"}.
static func _raw_sign_in(t: Node, hello: Variant) -> Dictionary:
	var holder := Node.new()
	t.add_child(holder)
	var api := SceneMultiplayer.new()
	t.get_tree().set_multiplayer(api, holder.get_path())
	var out := {"answer": {}, "connected": false}
	api.auth_callback = func(_id: int, data: PackedByteArray) -> void:
		var answer: Variant = bytes_to_var(data)
		out.answer = answer if answer is Dictionary else {}
	api.auth_timeout = 5.0
	api.peer_authenticating.connect(func(id: int) -> void:
		api.send_auth(id, hello if hello is PackedByteArray else var_to_bytes(hello)))
	api.connected_to_server.connect(func() -> void: out.connected = true)
	api.peer_connected.connect(func(_id: int) -> void: out.connected = true)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	peer.host.compress(NetSession.COMPRESSION)
	api.multiplayer_peer = peer
	await t._wait_until(func() -> bool: return not (out.answer as Dictionary).is_empty(), 240)
	# Even if this side completed, the server must never let it in.
	if 1 in api.get_authenticating_peers():
		api.complete_auth(1)
	await t.frames(20)
	if api.multiplayer_peer != null:
		api.multiplayer_peer.close()
	t.get_tree().set_multiplayer(null, holder.get_path())
	holder.queue_free()
	return out
