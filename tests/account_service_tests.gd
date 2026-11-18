extends RefCounted
## Checks for the account service (DESIGN.md section 14, step 4): the
## program official servers share their accounts through
## (`core/account/account_service.gd`) and a game server's line to it
## (`core/account/account_link.gd`).
##
## First with the service and two links in this process: the key handshake,
## sign-in and tokens another server accepts, a life (deploy, bank, settle)
## held by the server that deployed it, every request done exactly once
## however often it is sent (receipts, kept across a restart), results that
## wait out an outage, a deploy that was never answered, a server that
## starts afresh, changes pushed to the other server, and the market.
##
## Then for real: the service and two game servers as their own programs,
## and a game that signs in on one and travels to the other on its token.
## Starts servers, so it runs in the online tier.
## `-- --groups AccountServiceTests` runs just these.

const AccountService := preload("res://core/account/account_service.gd")
const AccountLink := preload("res://core/account/account_link.gd")
const Accounts := preload("res://core/account/stash_service.gd")
const Market := preload("res://core/economy/market.gd")

const PORT := 25460          # the in-process service
const SERVICE_PORT := 25461  # the service as its own program
const GAME_PORT := 25463     # two game servers, here and 2 above
const KEY := "0123456789abcdef0123456789abcdef"


static func run(t: Node) -> void:
	print("The account service: one set of accounts for every official server")
	_tokens_at_home(t)
	await _in_process(t)
	await _for_real(t)


static func _dir(tag: String) -> String:
	return "user://test_service_%s_%d" % [tag, Time.get_ticks_usec()]


## Waits on `condition` in real time: sockets need the clock, not frames.
static func _until(t: Node, condition: Callable, seconds := 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		OS.delay_msec(2)
		await t.frames(1)
	return condition.call()


static func _service(t: Node, dir: String, port := PORT) -> AccountService:
	var service := AccountService.new()
	service.stash.save_dir = dir
	service.stash.backup_every = 0.0
	service.key = KEY
	t.add_child(service)
	var err := service.start(port)
	t.check(err == OK, "the account service starts (%s)" % error_string(err))
	return service


static func _link(t: Node, server_id: String, port := PORT, key := KEY) -> AccountLink:
	var link := AccountLink.new()
	link.url = "ws://127.0.0.1:%d" % port
	link.key = key
	link.server_id = server_id
	link.persist = false
	link.retry_every = 0.2
	t.add_child(link)
	return link


static func _stop(t: Node, service: AccountService) -> void:
	service.stop()
	service.queue_free()
	await t.frames(2)


## A server that keeps its own accounts hands out tokens too, so the game
## signs in the same way everywhere.
static func _tokens_at_home(t: Node) -> void:
	var stash := Accounts.new()
	stash.persist = false
	var secret := Accounts.new_secret()
	var first: Dictionary = stash.sign_in_with({"method": "secret", "name": "Tova", "secret": secret})
	t.check(first.ok and str(first.get("token", "")).length() >= 32, "signing in with the secret hands out a token")
	var by_token: Dictionary = stash.sign_in_with({"method": "token", "token": first.token})
	t.check(by_token.ok and by_token.account_id == first.account_id and not by_token.has("token"),
			"the token signs in to the same account")
	var bad: Dictionary = stash.sign_in_with({"method": "token", "token": "not-a-token"})
	t.check(not bad.ok and bad.get("expired", false), "an unknown token is refused as expired, to sign in again")
	var again: Dictionary = stash.sign_in_with({"method": "secret", "name": "Tova", "secret": secret})
	t.check(again.ok and again.token != first.token and not stash.verify(first.token).ok and stash.verify(again.token).ok,
			"signing in with the secret again replaces the token")
	t.check(not stash.sign_in_with({"method": "steam", "ticket": "x"}).ok,
			"a way of signing in this server does not know is refused")


static func _in_process(t: Node) -> void:
	var dir := _dir("inproc")
	var service := _service(t, dir)
	var ashfront := Worlds.get_world("ashfront")

	# The handshake: only a server that holds the key gets in.
	var stranger := _link(t, "stranger", PORT, "ffffffffffffffffffffffffffffffff")
	var a := _link(t, "world-a")
	await _until(t, a.is_up)
	t.check(a.is_up(), "a game server with the service key connects")
	await _until(t, func() -> bool: return stranger._retry_in > 1.0, 3.0)
	t.check(not stranger.is_up() and service.servers() == 1, "one with the wrong key is refused")
	stranger.queue_free()
	var b := _link(t, "world-b")
	await _until(t, b.is_up)

	# Sign-in through one server; the token is good on the other.
	var secret := Accounts.new_secret()
	var signed: Dictionary = await a.sign_in_with({"method": "secret", "name": "Ada Vane", "secret": secret})
	var ada: String = signed.get("account_id", "")
	t.check(signed.get("ok", false) and signed.get("created", false) and ada == "ada_vane",
			"a player signs in through a game server and the account is made in the service")
	t.check(a.snapshot(ada).get("ok", false) and a.snapshot(ada).name == "Ada Vane" and a.name_of(ada) == "Ada Vane"
			and not b.snapshot(ada).get("ok", false),
			"the server they are on holds a copy of the account to read at once; another server does not")
	t.check(FileAccess.file_exists(dir.path_join("accounts.sqlite")) and service.stash.store().has(ada),
			"the account is in the service's database")
	var wrong: Dictionary = await b.sign_in_with({"method": "secret", "name": "Ada Vane", "secret": Accounts.new_secret()})
	t.check(not wrong.get("ok", true), "the wrong secret is refused whichever server asks")
	var travelled: Dictionary = await b.sign_in_with({"method": "token", "token": signed.get("token", "")})
	t.check(travelled.get("ok", false) and travelled.get("account_id", "") == ada and b.snapshot(ada).get("ok", false),
			"another server lets the player in on the token alone, and now holds the account too")
	var forged: Dictionary = await b.sign_in_with({"method": "token", "token": "f".repeat(64)})
	t.check(not forged.get("ok", true) and forged.get("expired", false), "a made-up token is refused")

	# Lobby requests are the same rules, a service away.
	var heard: Array[String] = []
	b.account_changed.connect(func(id: String) -> void: heard.append(id))
	var equipped: Dictionary = await a.equip(ada, "primary", "rifle_carbine")
	t.check(equipped.get("ok", false) and a.snapshot(ada).loadout.get("primary", "") == "rifle_carbine",
			"equipping through the link answers and the server's copy follows")
	var nonsense: Dictionary = await a.equip(ada, "primary", "medkit")
	t.check(not nonsense.get("ok", true) and str(nonsense.get("error", "")) != "", "a refused request says why")
	await _until(t, func() -> bool: return b.snapshot(ada).get("loadout", {}).get("primary", "") == "rifle_carbine", 2.0)
	t.check(b.snapshot(ada).loadout.get("primary", "") == "rifle_carbine" and heard.has(ada),
			"a change made through one server is pushed to the other the player is signed in on")

	# A life: only the server that deployed it may bank into it or settle it.
	var kit: Dictionary = await a.deploy(ada, ashfront)
	t.check(kit.get("ok", false) and "rifle_carbine" in kit.get("kit", []) and a.is_deployed(ada)
			and "rifle_carbine" not in a.snapshot(ada).stash,
			"a deploy takes the loadout out of the stash and hands back the kit")
	t.check(not (await b.deploy(ada, ashfront)).get("ok", true), "an account is deployed once at a time, across servers")
	t.check(not (await b.settle(ada, {"outcome": "left", "brought_home": ["scrap_metal"]})).get("ok", true)
			and not (await b.bank(ada, ["scrap_metal"])).get("ok", true) and service.stash.is_deployed(ada),
			"another server cannot bank into or settle that life")
	var banked: Dictionary = await a.bank(ada, ["alloy_ingot", "alloy_ingot"])
	t.check(banked.get("ok", false) and a.snapshot(ada).stash.count("alloy_ingot") == 2, "loot handed in at a depot reaches the stash")
	var settled: Dictionary = await a.settle(ada, {"outcome": "left", "brought_home": ["rifle_carbine", "circuit_board"],
			"kills": 2})
	t.check(settled.get("ok", false) and not a.is_deployed(ada) and "circuit_board" in a.snapshot(ada).stash
			and "rifle_carbine" in a.snapshot(ada).stash and int(a.snapshot(ada).raids_extracted) == 1,
			"settling a finished life brings home what was carried")
	# Where no gear is at risk the kit is read on the spot and nothing leaves.
	var arena := NetSession.world_for(NetSession.ArenaVenue.ID)
	var shown: Dictionary = a.showcase(ada, arena)
	t.check(shown.get("ok", false) and "rifle_carbine" in shown.kit and "rifle_carbine" in a.snapshot(ada).stash,
			"a kit where nothing is at risk is read from the server's copy, with nothing taken")

	# Exactly once: the same request sent again is answered, not done again.
	var before := service.stash.scrip_of(ada)
	var a_side: AccountService.Link = service._links.filter(func(l: AccountService.Link) -> bool: return l.server_id == "world-a")[0]
	for i in 3:
		service._answer(a_side, {"id": "world-a:test:1", "call": "change_scrip", "args": [ada, 50]})
	t.check(service.stash.scrip_of(ada) == before + 50, "a request sent three times with one id is done once (%d -> %d)"
			% [before, service.stash.scrip_of(ada)])
	await _until(t, func() -> bool: return a.scrip_of(ada) == before + 50, 2.0)

	# Wagers answer at once and the change follows.
	t.check(a.change_scrip(ada, -30) and a.scrip_of(ada) == before + 20 and not a.change_scrip(ada, -100000)
			and a.scrip_of(ada) == before + 20,
			"a wager is taken from the server's copy at once and an overdraft is refused")
	await _until(t, func() -> bool: return service.stash.scrip_of(ada) == before + 20, 2.0)
	t.check(service.stash.scrip_of(ada) == before + 20 and a.scrip_of(ada) == before + 20 and a.queued() == 0,
			"and the service's balance follows")

	# The market: the board is the service's, shared by every server.
	var bo_signed: Dictionary = await b.sign_in_with({"method": "secret", "name": "Bodil", "secret": Accounts.new_secret()})
	var bo: String = bo_signed.get("account_id", "")
	service.stash.change_scrip(bo, 5000)
	var price := Market.board_value("alloy_ingot")
	var listed: Dictionary = await a.market("list", ada, "alloy_ingot", 2, price)
	t.check(listed.get("ok", false) and listed.result.get("ok", false) and a.snapshot(ada).stash.count("alloy_ingot") == 0
			and (listed.board.get("listings", []) as Array).size() == 1,
			"a listing put up through one server takes the goods and shows on the board")
	var ada_scrip := a.scrip_of(ada)
	var board: Dictionary = await b.board(bo)
	var listing_id := int((board.get("listings", [{}]) as Array)[0].get("id", -1))
	var bought: Dictionary = await b.market("buy", bo, "", listing_id, 2)
	t.check(bought.get("ok", false) and bought.result.get("ok", false) and b.snapshot(bo).stash.count("alloy_ingot") == 2,
			"a player on another server buys it")
	await _until(t, func() -> bool: return a.scrip_of(ada) > ada_scrip, 2.0)
	t.check(a.scrip_of(ada) > ada_scrip, "and the seller's server hears they were paid")

	# The service stops and comes back: the life is still held, results wait.
	await a.equip(ada, "primary", "rifle_carbine")
	var out: Dictionary = await a.deploy(ada, ashfront)
	t.check(out.get("ok", false), "deployed again")
	await _stop(t, service)
	await _until(t, func() -> bool: return not a.is_up(), 3.0)
	var home := ["rifle_carbine", "circuit_board"]
	var late: Dictionary = await a.settle(ada, {"outcome": "left", "brought_home": home})
	t.check(late.get("unanswered", false) and a.queued() == 1,
			"with the service down a finished life answers at once as unanswered, and is kept")
	t.check((await a.equip(ada, "primary", "")).get("unanswered", false) and a.queued() == 1,
			"a lobby request does not wait on a service that is down, and is not kept")
	service = _service(t, dir)
	t.check(service.stash.is_deployed(ada), "after a restart the service still holds the deploy: the life goes on")
	# The receipt was written with the change, so it outlives the restart.
	t.check(not service._receipt("world-a:test:1").is_empty(),
			"the receipt of an answered request is still there after a restart")
	await _until(t, func() -> bool: return a.is_up() and a.queued() == 0)
	t.check(a.queued() == 0 and not service.stash.is_deployed(ada) and service.stash.count_of(ada, "rifle_carbine") == 1
			and int(service.stash.snapshot(ada).raids_extracted) == 2,
			"when the service is back the kept result is settled, once")
	await _until(t, func() -> bool: return not a.is_deployed(ada), 2.0)
	t.check(not a.is_deployed(ada), "and the server's copy catches up")

	# A deploy that is never answered is undone, whichever way it went.
	service.set_process(false)
	a.answer_timeout = 0.3
	var silent: Dictionary = await a.deploy(ada, ashfront)
	t.check(silent.get("unanswered", false), "a deploy the service does not answer in time is refused to the player")
	service.set_process(true)
	await _until(t, func() -> bool: return a.queued() == 0 and not a.is_deployed(ada), 3.0)
	t.check(not service.stash.is_deployed(ada) and service.stash.count_of(ada, "rifle_carbine") == 1,
			"and whatever it took out of the stash is put back")
	a.answer_timeout = AccountLink.ANSWER_TIMEOUT

	# A server that starts afresh gets the deploys it held back.
	t.check((await a.deploy(ada, ashfront)).get("ok", false) and service.stash.is_deployed(ada), "deployed once more")
	a.queue_free()
	await t.frames(2)
	var reborn := _link(t, "world-a")
	await _until(t, reborn.is_up)
	t.check(reborn.is_up() and not service.stash.is_deployed(ada) and service.stash.count_of(ada, "rifle_carbine") == 1,
			"a game server that starts afresh has the lives it was running handed back")

	reborn.queue_free()
	b.queue_free()
	await _stop(t, service)
	t._wipe_dir(dir)


## The service and two game servers as programs of their own.
static func _for_real(t: Node) -> void:
	var dir := _dir("real")
	var godot := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var service_pid := OS.create_process(godot, PackedStringArray(["--headless", "--path", project, "--",
			"--account-service", "--port", str(SERVICE_PORT), "--accounts", dir]))
	# The service makes its key on first start; the game servers read it.
	var key_file := dir.path_join(AccountService.KEY_FILE)
	await _until(t, func() -> bool: return FileAccess.file_exists(key_file), 30.0)
	t.check(FileAccess.file_exists(key_file), "the service makes its key on its first start")
	var pids: Array[int] = [service_pid]
	for i in 2:
		pids.append(OS.create_process(godot, PackedStringArray(["--headless", "--path", project, "--",
				"--server", "--world", "ashfront", "--no-plaza", "--no-arena", "--no-zone-rules", "--bots", "0",
				"--port", str(GAME_PORT + i * 2), "--accounts", dir + "_server%d" % i,
				"--account-url", "ws://127.0.0.1:%d" % SERVICE_PORT, "--service-key", ProjectSettings.globalize_path(key_file),
				"--server-id", "test-world-%d" % i])))

	var eve: NetSession = await t._sign_in("Eve", GAME_PORT)
	t.check(eve != null and eve.ticket != "", "a game signs in on an official server and is handed a token")
	if eve == null:
		for pid in pids:
			OS.kill(pid)
		return
	eve.equip("primary", "rifle_carbine")
	await t._wait_until(func() -> bool: return eve.account.get("loadout", {}).get("primary", "") == "rifle_carbine", 240)
	t.check(eve.account.get("loadout", {}).get("primary", "") == "rifle_carbine",
			"equipping in the lobby goes through the account service and comes back")
	t.check(not DirAccess.dir_exists_absolute(dir + "_server0") or not FileAccess.file_exists((dir + "_server0").path_join("accounts.sqlite")),
			"the game server keeps no accounts of its own")
	var ticket := eve.ticket
	await t._leave(eve)

	# On to the second server with the token only: the same account.
	var onward: NetSession = t._new_client("Eve", "not-the-secret-at-all-0000")
	onward.ticket = ticket
	var state := {"failed": ""}
	onward.failed.connect(func(reason: String) -> void: state.failed = reason)
	onward.join("127.0.0.1", GAME_PORT + 2)
	await t._wait_until(func() -> bool: return state.failed != "" or not onward.account.is_empty(), 600)
	t.check(not onward.account.is_empty() and onward.account.get("loadout", {}).get("primary", "") == "rifle_carbine",
			"the next server lets the game in on its token, with the same account (%s)" % state.failed)
	onward.deploy()
	await t._wait_until(func() -> bool: return onward.raid != null and onward.raid.player != null, 480)
	t.check(onward.raid != null and onward.raid.player != null
			and onward.raid.player.weapons.any(func(w: Weapon) -> bool: return w.item_id == "rifle_carbine"),
			"and deploys them with the kit the service took out of the stash")
	await t._leave(onward)

	# A token that is no good falls back to the secret on the same connection.
	var stale: NetSession = t._new_client("Eve")
	stale.ticket = "e".repeat(64)
	stale.join("127.0.0.1", GAME_PORT)
	await t._wait_until(func() -> bool: return not stale.account.is_empty(), 600)
	t.check(not stale.account.is_empty() and stale.ticket != "" and stale.ticket != "e".repeat(64),
			"a token that has run out signs in with the secret instead, and gets a new one")
	await t._leave(stale)

	for pid in pids:
		OS.kill(pid)
	await t.frames(30)
	t._wipe_dir(dir)
	t._wipe_dir(dir + "_server0")
	t._wipe_dir(dir + "_server1")
