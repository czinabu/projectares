extends Node
## A game server's line to the account service
## (`core/account/account_service.gd`): what an official server holds in
## place of a `StashService` of its own. It offers the same calls, so
## `NetSession` talks to either without knowing which (`NetSession.stash`),
## and every session of one server shares one link.
##
## Load with `const AccountLink := preload("res://core/account/account_link.gd")`.
## It is a Node: add it to the tree so it is polled every frame.
##
## Calls come in three kinds.
##
## Read at once. `snapshot`, `is_deployed`, `scrip_of`, `showcase` and
## `name_of` answer from the link's own copy of each account that has a
## player signed in on this server. The service keeps those copies fresh: an
## answer carries the accounts it changed, and a change made from another
## server is pushed (`account_changed`).
##
## Awaited. `sign_in_with`, `equip`, `buy`, `deploy`, `market` and the rest
## send a request and return the service's answer; call them with `await`.
## An answer that has not come within `ANSWER_TIMEOUT`, or a request made
## while the service cannot be reached, returns {"ok": false, "error",
## "unanswered": true} so nothing ever waits on the service for long.
##
## Sure. `bank`, `settle`, `cancel_deploy`, `change_scrip`, `record_arena`, `arena_prize`,
## `record_race`, `keep_ghost`, `tune_race`
## and `cancel_all_deploys` carry a result the server alone knows (a life
## that ended, loot handed in), so they are never dropped: each stays
## queued, in order, and is sent again after every reconnect until the
## service answers it. The service does each request once however often it
## is sent (its receipts), so a repeat is safe. `bank`, `settle` and
## `cancel_deploy` can still be awaited for the answer; when it is late they
## return "unanswered" and carry on by themselves.
##
## A deploy that is never answered may or may not have taken the gear out,
## so the link follows it with a sure `undo_deploy` naming that very
## request: the gear goes back if it left, and no other deploy is touched.
##
## Besides accounts, the service keeps what every world shares, and the link
## holds this server's view of it:
## - `clans`: a copy of every clan, read at once (`clan_of`, `tag_of`); a
##   change is asked with `clan` and comes back to every server
##   (`clans_changed`).
## - The phone: `social` runs one request (`SocialService.run`) for a player
##   here; their phone as the service last sent it is `social_snapshot`, and
##   `social_changed` / `social_noticed` say when there is something new for
##   them, whichever world it came from.
## - `worlds`: every world a game server runs, where to reach it and how it
##   is doing. `announce` puts this server's own world on it.
##
## The queue is kept in memory. If this server stops with results still
## queued, those lives are lost with it and the service hands their gear
## back when the server next starts (its hello says "fresh"), the same as a
## server that keeps its own accounts.

const AccountService := preload("res://core/account/account_service.gd")
const StashRules := preload("res://core/account/stash_rules.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const SafeFile := preload("res://core/account/safe_file.gd")

## An account of a player on this server changed from somewhere else (or a
## late answer arrived): `snapshot` now says something new.
signal account_changed(account_id: String)
## The market's board changed.
signal market_changed
## The link is up (again).
signal linked
## The copy of the clans (`clans`) changed.
signal clans_changed
## A player here has a new phone snapshot (`social_snapshot`).
signal social_changed(account_id: String)
## A line for a player here to be shown now (a message came, an invite).
signal social_noticed(account_id: String, text: String)
## The directory of worlds (`worlds`) changed.
signal worlds_changed

## Seconds an awaited call waits for its answer.
const ANSWER_TIMEOUT := 5.0
## Seconds between tries to reach the service, and after a refusal.
const RETRY_EVERY := 2.0
const RETRY_REFUSED := 15.0
const UNANSWERED := "The account service is not answering. Try again in a moment."

## Where the service listens: "ws://host:port", or "wss://" through a TLS proxy.
var url := "ws://127.0.0.1:%d" % AccountService.DEFAULT_PORT
## The service key (`AccountService.load_key`).
var key := ""
## This server's name to the service. It must stay the same across restarts
## of this server and differ from every other server's, since the service
## keeps each deploy under the name of the server that holds it.
var server_id := "server"
## This server's own folder, for the one thing it still keeps itself: its
## certificate. Accounts, clans and phone records are the service's.
var save_dir := "user://accounts"
var persist := true
## Seconds an awaited call waits (`ANSWER_TIMEOUT`); tests shorten it.
var answer_timeout := ANSWER_TIMEOUT
var retry_every := RETRY_EVERY
var backup_every := 3600.0
var backups_kept := 48

## A copy of the service's clans (`ClanService.load_state`). Read only:
## changes go through `clan`.
var clans := ClanService.new()
## Every world a game server of this service runs: world id -> {"host" (""
## for the address players already use), "port", "max", "status"
## (`Raid.status()`)}.
var worlds := {}

var _phones := {}      # account id -> phone snapshot, for accounts signed in here
var _announced := {}   # world id -> what this server last said about its own world
var _socket: WebSocketPeer = null
var _state := "down"   # "down", "connecting", "hello", "up"
var _nonce := ""
var _fresh := true
var _retry_in := 0.0
var _boot := Crypto.new().generate_random_bytes(6).hex_encode()
var _next := 1
## Every request not answered yet, oldest first.
var _queue: Array[Request] = []
var _mirror := {}      # account id -> its snapshot, for accounts signed in here
var _names := {}       # account id -> shown name, for anyone asked about
var _owed := {}        # account id -> scrip changes sent and not answered yet
var _said_down := false


class Request:
	signal done(answer: Variant)
	var id := ""
	var what := ""
	var args: Array = []
	## Never dropped: sent again until answered.
	var sure := false
	## Never sent twice (the market, which has no receipts).
	var once := false
	var sent := false
	## The caller is still waiting on `done`.
	var waiting := true
	var waited := 0.0
	## The scrip this request changes that `scrip_of` already counts.
	var owed := 0


func _process(delta: float) -> void:
	poll(delta)


## True: accounts live in the account service (see `StashService.is_remote`).
func is_remote() -> bool:
	return true


## Whether the service is reachable right now.
func is_up() -> bool:
	return _state == "up"


## How many requests wait for an answer (the sure ones wait as long as it takes).
func queued() -> int:
	return _queue.size()


# --- Read at once -------------------------------------------------------------

func snapshot(account_id: String) -> Dictionary:
	if not _mirror.has(account_id):
		return _fail("No such account.")
	var copy: Dictionary = _mirror[account_id].duplicate(true)
	copy["scrip"] = scrip_of(account_id)
	return copy


func is_deployed(account_id: String) -> bool:
	return bool(_mirror.get(account_id, {}).get("deployed", false))


func scrip_of(account_id: String) -> int:
	return maxi(0, int(_mirror.get(account_id, {}).get("scrip", 0)) + int(_owed.get(account_id, 0)))


## The name an account shows. One this server has not heard of yet reads as
## its id (ids are made from names) and is asked for, so it is right the
## next time.
func name_of(account_id: String) -> String:
	if _mirror.has(account_id):
		return str(_mirror[account_id].get("name", account_id))
	if not _names.has(account_id):
		_names[account_id] = account_id
		_learn_names([account_id])
	return str(_names[account_id])


func _learn_names(ids: Array) -> void:
	var answer: Variant = await _ask("names", [ids])
	if typeof(answer) == TYPE_DICTIONARY and typeof(answer.get("names")) == TYPE_DICTIONARY:
		for id: Variant in answer.names:
			_names[str(id)] = str(answer.names[id])
	else:
		for id: Variant in ids:
			_names.erase(id)


## The kit an account would deploy with, with nothing taken (`StashService.showcase`).
func showcase(account_id: String, world: WorldDef) -> Dictionary:
	if not _mirror.has(account_id):
		return _fail("No such account.")
	var account: Dictionary = _mirror[account_id]
	var stash: Array[String] = []
	stash.assign(account.get("stash", []))
	var kit := StashRules.checkout(stash, (account.get("loadout", {}) as Dictionary).duplicate(), world)
	var mastery := MasteryBook.new()
	mastery.load_dict(account.get("mastery", {}))
	return {"ok": true, "kit": kit, "picks": mastery.active_picks()}


# --- Awaited ------------------------------------------------------------------

func sign_in_with(credentials: Dictionary) -> Dictionary:
	return await _ask("sign_in", [credentials])


## A new recovery code for the account (`StashService.make_recovery_code`).
func make_recovery_code(account_id: String) -> Dictionary:
	return await _ask("recovery_code", [account_id])


func fetch(account_id: String) -> Dictionary:
	if _mirror.has(account_id):
		return snapshot(account_id)
	return await _ask("fetch", [account_id])


## Nobody is signed in to this account on this server any more.
func release(account_id: String) -> void:
	_phones.erase(account_id)
	if _mirror.has(account_id):
		_mirror.erase(account_id)
		_ask("release", [account_id])


func equip(account_id: String, slot: String, item_id: String) -> Dictionary:
	return await _ask("equip", [account_id, slot, item_id])


func unequip(account_id: String, slot: String) -> Dictionary:
	return await _ask("unequip", [account_id, slot])


func pick_mastery(account_id: String, track: String, variant_id: String) -> Dictionary:
	return await _ask("pick_mastery", [account_id, track, variant_id])


func buy(account_id: String, shop_id: String, item_id: String) -> Dictionary:
	return await _ask("buy", [account_id, shop_id, item_id])


func sell(account_id: String, item_id: String, count: int = 1) -> Dictionary:
	return await _ask("sell", [account_id, item_id, count])


func buy_upgrade(account_id: String, upgrade_id: String) -> Dictionary:
	return await _ask("buy_upgrade", [account_id, upgrade_id])


func place_room(account_id: String, socket: String, room: String) -> Dictionary:
	return await _ask("place_room", [account_id, socket, room])


func contract(account_id: String, action: String, job_id: String = "") -> Dictionary:
	return await _ask("contract", [account_id, action, job_id])


func craft(account_id: String, item_id: String) -> Dictionary:
	return await _ask("craft", [account_id, item_id])


func insure(account_id: String, action: String, item_id: String = "") -> Dictionary:
	return await _ask("insure", [account_id, action, item_id])


## Takes the loadout out of the stash for a life in `world`
## (`StashService.deploy`). Where no gear is at risk nothing leaves the
## stash, so the kit is read here.
func deploy(account_id: String, world: WorldDef) -> Dictionary:
	if not world.gear_at_risk:
		return showcase(account_id, world)
	return await _ask("deploy", [account_id, world.id])


## One request at the market kiosk: "list", "buy" or "cancel". Returns
## {"ok", "result" (the board's own answer), "board" (the asker's view)}.
func market(action: String, account_id: String, item_id: String, a: int, b: int) -> Dictionary:
	return await _ask("market", [action, account_id, item_id, a, b], false, true)


## The market board as `account_id` sees it (`MarketService.snapshot`), or
## {} if the service did not answer.
func board(account_id: String) -> Dictionary:
	var answer: Dictionary = await _ask("board", [account_id])
	return {} if answer.has("unanswered") or answer.get("ok", true) == false else answer


# --- Clans, the phone and the directory of worlds ----------------------------

## One request at the clan hall: "create" (name, tag), "join" (clan id) or
## "leave" (`ClanService.ask`). The copy here is up to date when it returns.
func clan(action: String, account_id: String, a := "", b := "") -> Dictionary:
	var answer: Dictionary = await _ask("clan", [action, account_id, a, b], false, true)
	if answer.get("ok", false) and typeof(answer.get("state")) == TYPE_DICTIONARY:
		clans.load_state(answer.state)
		clans_changed.emit()
	return answer


## One request of the phone's for a player here (`SocialService.run`).
## Whatever it changes for other players reaches them through their own
## servers; this player's phone is fresh when it returns.
func social(action: String, account_id: String, args: Array = []) -> Dictionary:
	var answer: Dictionary = await _ask("social", [action, account_id, args], false, true)
	if typeof(answer.get("snapshot")) == TYPE_DICTIONARY and _mirror.has(account_id):
		_phones[account_id] = answer.snapshot
	return answer


## The phone of a player here as the service last sent it, or {}.
func social_snapshot(account_id: String) -> Dictionary:
	return _phones.get(account_id, {})


## Puts this server's world on the directory, or says how it is doing now:
## {"world", "host", "port", "max", "status"}. Said again by itself whenever
## the link comes back.
func announce(info: Dictionary) -> void:
	_announced[str(info.get("world", ""))] = info
	if _state != "up":
		return
	var answer: Dictionary = await _ask("announce", [info], false, true)
	if answer.get("ok", false):
		_take_worlds(answer.get("worlds"))


func _take_worlds(sent: Variant) -> void:
	if typeof(sent) != TYPE_DICTIONARY or sent == worlds:
		return
	worlds = sent
	worlds_changed.emit()


func _fetch_clans() -> void:
	var answer: Dictionary = await _ask("clans", [])
	if answer.get("ok", false) and typeof(answer.get("state")) == TYPE_DICTIONARY:
		clans.load_state(answer.state)
		clans_changed.emit()


# --- Sure ---------------------------------------------------------------------

func bank(account_id: String, items: Array) -> Dictionary:
	return await _ask("bank", [account_id, items], true)


func settle(account_id: String, result: Dictionary) -> Dictionary:
	return await _ask("settle", [account_id, result], true)


func cancel_deploy(account_id: String) -> Dictionary:
	return await _ask("cancel_deploy", [account_id], true)


## Hands back every deploy this server holds (it is shutting a world down).
func cancel_all_deploys() -> void:
	_ask("release_deploys", [], true)


## Adds `delta` scrip (a cost when negative). Answers at once from what the
## link holds, and the change itself is sure to follow: a wager cannot wait
## on the service. Refuses, changing nothing, if it would go below zero.
func change_scrip(account_id: String, delta: int) -> bool:
	if not _mirror.has(account_id):
		# Someone who has left this server (a wager paid out after they
		# went): a payment still reaches them; a cost cannot be checked.
		if delta < 0:
			return false
		_ask("change_scrip", [account_id, delta], true)
		return true
	if scrip_of(account_id) + delta < 0:
		return false
	_owed[account_id] = int(_owed.get(account_id, 0)) + delta
	_ask("change_scrip", [account_id, delta], true, false, delta)
	return true


func record_arena(account_id: String, won: bool) -> void:
	_ask("record_arena", [account_id, won], true)


func arena_prize(account_id: String, week: int, items: Array) -> void:
	_ask("arena_prize", [account_id, week, items], true)


func record_race(account_id: String, result: Dictionary) -> void:
	_ask("record_race", [account_id, result], true)


func tune_race(account_id: String, machine: String, kit: String) -> void:
	_ask("tune_race", [account_id, machine, kit], true)


func keep_ghost(account_id: String, track_id: String, machine: String, lap: float, packed: String) -> void:
	_ask("keep_ghost", [account_id, track_id, machine, float(lap), packed], true)


## The fastest kept ghost among `ids` on a track (`StashService.race_ghost`).
func race_ghost(ids: Array, track_id: String, machine := "") -> Dictionary:
	var answer: Dictionary = await _ask("race_ghost", [ids, track_id, machine])
	return answer if answer.get("ok", false) else {"ok": false}


## `ids`' best laps (`StashService.race_bests`), or [] unanswered.
func race_bests(ids: Array) -> Array:
	var answer: Dictionary = await _ask("race_bests", [ids])
	return answer.get("rows", []) if typeof(answer.get("rows")) == TYPE_ARRAY else []


# --- What a server still keeps itself ----------------------------------------

## Null: there is no account store here.
func store() -> RefCounted:
	return null


func backup_dir() -> String:
	return save_dir.trim_suffix("/") + "_backups"


## Nothing to back up here: accounts, clans and phone records are the
## service's, which backs them up itself.
func backup_if_due() -> String:
	return ""


func close() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_state = "down"


# --- The connection -----------------------------------------------------------

## Keeps the connection up, sends what is queued and hands out answers.
## Called every frame once the link is in the tree.
func poll(delta := 0.0) -> void:
	if _state == "down":
		_retry_in -= delta
		if _retry_in <= 0.0:
			_connect()
	else:
		_socket.poll()
		var state := _socket.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_dropped(retry_every)
		elif state == WebSocketPeer.STATE_OPEN:
			if _state == "connecting":
				_state = "hello"
			while _socket != null and _socket.get_available_packet_count() > 0:
				_receive(AccountService.unpack(_socket.get_packet()))
	_tick_waits(delta)


func _connect() -> void:
	_socket = AccountService.roomy(WebSocketPeer.new())
	var err := _socket.connect_to_url(url, TLSOptions.client() if url.begins_with("wss://") else null)
	if err != OK:
		_dropped(retry_every)
		return
	_state = "connecting"


func _dropped(retry: float) -> void:
	if _state == "up" or not _said_down:
		_said_down = true
		push_warning("AccountLink: no connection to the account service at %s; retrying" % url)
	if _socket != null:
		_socket.close()
	_socket = null
	_state = "down"
	_retry_in = retry
	# What was sent and not answered goes again once the link is back, apart
	# from what must never be sent twice.
	for request: Request in _queue.duplicate():
		if request.once and request.sent:
			_queue.erase(request)
			_finish(request, _unanswered())
		request.sent = false


func _receive(message: Dictionary) -> void:
	if message.has("refused"):
		push_error("AccountLink: the account service refused this server: %s" % message.refused)
		_dropped(RETRY_REFUSED)
	elif _state == "hello" and message.has("hello"):
		_nonce = AccountService.new_nonce()
		_socket.put_packet(AccountService.pack({"server": server_id, "nonce": _nonce,
				"proof": AccountService.proof(key, str(message.hello), server_id),
				"protocol": AccountService.PROTOCOL, "fresh": _fresh}))
	elif _state == "hello" and message.get("welcome", false):
		# The service proves it holds the key too, before any sign-in is sent.
		if not AccountService.same(str(message.get("proof", "")), AccountService.proof(key, _nonce, "service")):
			push_error("AccountLink: %s is not the account service this server was set up for" % url)
			_dropped(RETRY_REFUSED)
			return
		_up()
	elif _state == "up" and message.has("re"):
		_answered(message)
	elif _state == "up" and message.get("push", "") == "accounts":
		for account_id: String in _take_accounts(message.get("accounts")):
			account_changed.emit(account_id)
	elif _state == "up" and message.get("push", "") == "market":
		market_changed.emit()
	elif _state == "up" and message.get("push", "") == "clans":
		if typeof(message.get("state")) == TYPE_DICTIONARY:
			clans.load_state(message.state)
			clans_changed.emit()
	elif _state == "up" and message.get("push", "") == "worlds":
		_take_worlds(message.get("worlds"))
	elif _state == "up" and message.get("push", "") == "social":
		var snapshots: Variant = message.get("snapshots")
		if typeof(snapshots) == TYPE_DICTIONARY:
			for account_id: Variant in snapshots:
				if _mirror.has(account_id) and typeof(snapshots[account_id]) == TYPE_DICTIONARY:
					_phones[account_id] = snapshots[account_id]
					social_changed.emit(account_id)
		var notices: Variant = message.get("notices")
		if typeof(notices) == TYPE_DICTIONARY:
			for account_id: Variant in notices:
				if _mirror.has(account_id) and typeof(notices[account_id]) == TYPE_ARRAY:
					for text: Variant in notices[account_id]:
						social_noticed.emit(account_id, str(text))


func _up() -> void:
	_state = "up"
	_said_down = false
	print("AccountLink: connected to the account service at %s as %s" % [url, server_id])
	if not _fresh and not _mirror.is_empty():
		# Back after a drop: say who is still here, and catch up on them.
		_catch_up()
	_fresh = false
	for request in _queue:
		_send(request)
	_fetch_clans()
	for world_id: String in _announced:
		announce(_announced[world_id])
	linked.emit()


func _catch_up() -> void:
	var request := Request.new()
	request.id = _new_id()
	request.what = "watch"
	request.args = [_mirror.keys()]
	_queue.push_front(request)
	var answer: Variant = await request.done
	if typeof(answer) == TYPE_DICTIONARY:
		for account_id: String in _take_accounts(answer.get("accounts")):
			account_changed.emit(account_id)


## Queues a request and returns its answer. See the kinds at the top.
func _ask(what: String, args: Array, sure := false, once := false, owed := 0) -> Variant:
	var request := Request.new()
	request.owed = owed
	request.id = _new_id()
	request.what = what
	request.args = args
	request.sure = sure
	request.once = once
	if _state != "up":
		# Nothing waits on a service that cannot be reached; a sure request
		# is kept for when it can.
		if sure:
			request.waiting = false
			_queue.append(request)
		return _unanswered()
	_queue.append(request)
	_send(request)
	return await request.done


func _send(request: Request) -> void:
	if _state != "up" or request.sent:
		return
	request.sent = true
	_socket.put_packet(AccountService.pack({"id": request.id, "call": request.what, "args": request.args}))


func _answered(message: Dictionary) -> void:
	var id := str(message.get("re", ""))
	var answer: Variant = message.get("answer")
	var request: Request = null
	for queued: Request in _queue:
		if queued.id == id:
			request = queued
			break
	if request != null:
		_queue.erase(request)
		if request.owed != 0:
			var account_id: String = request.args[0]
			_owed[account_id] = int(_owed.get(account_id, 0)) - request.owed
			if int(_owed[account_id]) == 0:
				_owed.erase(account_id)
		if request.what == "sign_in" and typeof(answer) == TYPE_DICTIONARY and answer.get("ok", false):
			_mirror[str(answer.account_id)] = {}
	var changed := _take_accounts(message.get("accounts"))
	if request == null:
		# Its caller stopped waiting long ago (a call that is not sure).
		for account_id in changed:
			account_changed.emit(account_id)
		return
	if request.waiting:
		_finish(request, answer)
		return
	if request.sure and typeof(answer) == TYPE_DICTIONARY and not answer.get("ok", true):
		push_warning("AccountLink: the account service refused %s for %s: %s" % [request.what,
				request.args[0] if not request.args.is_empty() else "", answer.get("error", "")])
	for account_id in changed:
		account_changed.emit(account_id)


## Copies the snapshots the service sent for accounts this server holds.
## Returns their ids.
func _take_accounts(sent: Variant) -> Array[String]:
	var taken: Array[String] = []
	if typeof(sent) != TYPE_DICTIONARY:
		return taken
	for account_id: Variant in sent:
		if _mirror.has(account_id) and typeof(sent[account_id]) == TYPE_DICTIONARY and sent[account_id].get("ok", false):
			_mirror[account_id] = sent[account_id]
			taken.append(account_id)
	return taken


func _tick_waits(delta: float) -> void:
	for request: Request in _queue.duplicate():
		if not request.waiting:
			continue
		request.waited += delta
		if request.waited < answer_timeout:
			continue
		if not request.sure:
			_queue.erase(request)
		if request.what == "deploy":
			# Did the gear leave the stash? Either way, it goes back.
			_ask("undo_deploy", [request.args[0], request.id], true)
		_finish(request, _unanswered())


func _finish(request: Request, answer: Variant) -> void:
	if request.waiting:
		request.waiting = false
		request.done.emit(answer)


func _new_id() -> String:
	_next += 1
	return "%s:%s:%d" % [server_id, _boot, _next]


static func _unanswered() -> Dictionary:
	return {"ok": false, "error": UNANSWERED, "unanswered": true}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
