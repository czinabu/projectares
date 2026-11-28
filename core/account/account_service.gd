extends Node
## The account service: the one program that holds every player's account on
## official servers (DESIGN.md section 14). It runs headless
## (`-- --account-service`, see `main.gd`), keeps the accounts in SQLite
## through the same `StashService` a friends' server holds in its own memory,
## and runs the player market's board beside it, since a trade moves goods
## between accounts. So every rule still exists once, in GDScript.
##
## Game servers are its only clients. Each connects with an `AccountLink`
## (`core/account/account_link.gd`) over a WebSocket and proves it holds the
## service key; players never reach this program. A friends' server does not
## use it at all and keeps its own accounts.
##
## Load with `const AccountService := preload("res://core/account/account_service.gd")`.
##
## The connection, one binary message each way per step (`pack`):
##   service: {"hello": nonce, "protocol"}
##   server:  {"server": its id, "nonce", "proof", "protocol", "fresh"}
##   service: {"welcome": true, "proof", "returned"} or {"refused": why}
## Each proof is an HMAC of the other side's nonce with the service key, so
## neither side sends the key and each knows the other holds it. A server
## that says it is "fresh" (its program just started) gets every deploy it
## held returned first: the lives it was running are gone, which is never
## the player's fault.
##
## After that the server sends requests {"id", "call", "args"} and gets
## {"re": id, "answer", "accounts"} back, where "accounts" is a fresh
## snapshot of each account the request changed that the server has a
## player signed in to. The service also sends, unasked,
## {"push": "accounts", "accounts"} when such an account changes from
## elsewhere (a market sale paid to a seller on another server) and
## {"push": "market"} when the board changes.
##
## Exactly once. A server that does not hear an answer sends the request
## again with the same id. Every save a request makes is written in one
## SQLite transaction together with its receipt (the id and the answer,
## `StashService.end_hold`), so the second copy is answered from the
## receipt and nothing is done twice, even if this program stopped between
## the two. Market requests are the exception: the board keeps its own file,
## so a server sends each of those once and never again.
##
## What every world shares besides accounts lives here too, since each world
## is its own program (DESIGN.md section 14, "Scaling"):
## - Clans (`ClanService`). "clan" asks for a change; every server holds a
##   copy of the whole list ("clans", and {"push": "clans", "state"} when it
##   changes), so who is in which clan is read at once.
## - The phone (`SocialService`): who is online, contacts, messages and
##   invites, across every world. "social" runs one request
##   (`SocialService.run`); each server is then sent the phone snapshots and
##   notices of its own players ({"push": "social", "snapshots", "notices"}).
##   A player is online while any server has them signed in (a seat each).
## - The directory of worlds. Each server says which world it runs, where
##   players reach it and how it is doing ("announce"); every server is sent
##   the lot ({"push": "worlds", "worlds"}), which is where a gate's route
##   and the sign over it come from. A server that goes away is taken out.
## Who is online and the directory change all the time, so those two are
## sent at most once every `PUSH_EVERY` seconds.
##
## Sign-in. "sign_in" takes the credentials a player gave their server
## (`StashService.sign_in_with`) and answers with the account id and a
## token. Any other server of this service can then let that player in on
## the token alone: it asks "sign_in" with {"method": "token"}.

const StashService := preload("res://core/account/stash_service.gd")
const MarketService := preload("res://core/economy/market_service.gd")
const SafeFile := preload("res://core/account/safe_file.gd")
const SocialService := preload("res://core/social/social_service.gd")

## The version of the messages between a game server and this service. Both
## must agree; it is not the game's `NetSession.PROTOCOL`.
const PROTOCOL := 2
const DEFAULT_PORT := 24700
## The file the service key is kept in, inside the accounts folder.
const KEY_FILE := "service_key"
## The environment variable that holds the key instead of the file.
const KEY_ENV := "ARES_SERVICE_KEY"
## The largest message either side sends, in bytes.
const MAX_MESSAGE := 4 * 1024 * 1024
## Seconds a new connection has to finish its hello.
const HELLO_TIMEOUT := 10.0
## Seconds a receipt is kept, and how often old ones are cleared out.
const RECEIPT_LIFE := 3600.0
const PRUNE_EVERY := 600.0
## Seconds between pushes of what changes all the time: who is online and
## how each world is doing.
const PUSH_EVERY := 1.0

## Each call a game server may make and the types of its arguments. Calls in
## `HELD` change accounts and are done exactly once.
const CALLS := {
	"sign_in": [TYPE_DICTIONARY],
	"recovery_code": [TYPE_STRING],
	"watch": [TYPE_ARRAY],
	"release": [TYPE_STRING],
	"fetch": [TYPE_STRING],
	"names": [TYPE_ARRAY],
	"equip": [TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"unequip": [TYPE_STRING, TYPE_STRING],
	"pick_mastery": [TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"buy": [TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"sell": [TYPE_STRING, TYPE_STRING, TYPE_INT],
	"buy_upgrade": [TYPE_STRING, TYPE_STRING],
	"place_room": [TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"contract": [TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"craft": [TYPE_STRING, TYPE_STRING],
	"insure": [TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"deploy": [TYPE_STRING, TYPE_STRING],
	"undo_deploy": [TYPE_STRING, TYPE_STRING],
	"bank": [TYPE_STRING, TYPE_ARRAY],
	"settle": [TYPE_STRING, TYPE_DICTIONARY],
	"cancel_deploy": [TYPE_STRING],
	"release_deploys": [],
	"change_scrip": [TYPE_STRING, TYPE_INT],
	"record_arena": [TYPE_STRING, TYPE_BOOL],
	"arena_prize": [TYPE_STRING, TYPE_INT, TYPE_ARRAY],
	"record_race": [TYPE_STRING, TYPE_DICTIONARY],
	"keep_ghost": [TYPE_STRING, TYPE_STRING, TYPE_STRING, TYPE_FLOAT, TYPE_STRING],
	"tune_race": [TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"race_ghost": [TYPE_ARRAY, TYPE_STRING, TYPE_STRING],
	"race_bests": [TYPE_ARRAY],
	"market": [TYPE_STRING, TYPE_STRING, TYPE_STRING, TYPE_INT, TYPE_INT],
	"board": [TYPE_STRING],
	"clan": [TYPE_STRING, TYPE_STRING, TYPE_STRING, TYPE_STRING],
	"clans": [],
	"social": [TYPE_STRING, TYPE_STRING, TYPE_ARRAY],
	"announce": [TYPE_DICTIONARY],
}
const HELD: Array[String] = ["equip", "unequip", "pick_mastery", "buy", "sell", "buy_upgrade", "place_room", "contract",
		"craft", "insure", "deploy", "undo_deploy", "bank", "settle", "cancel_deploy", "release_deploys", "change_scrip",
		"record_arena", "arena_prize", "record_race", "keep_ghost", "tune_race"]

## The accounts. Set its `save_dir` or `persist` before `start`.
var stash := StashService.new()
## The player market's board, saved beside the accounts.
var market := MarketService.new()
## Who is in which clan, saved beside the accounts.
var clans := ClanService.new()
## The phone's records (contacts, messages) and who is online, in a `social`
## folder beside the accounts.
var social := SocialService.new()
## What every game server must prove it holds. Set by `start` from
## `load_key` unless already set.
var key := ""
## The address to listen on. Only this computer by default: a game server on
## another machine needs "*" here and a private network or a TLS proxy in
## between, since players' sign-ins pass over this connection.
var bind := "127.0.0.1"
## Requests answered since the start, for the log.
var answered := 0

var _tcp := TCPServer.new()
var _links: Array[Link] = []
var _since_prune := 0.0
var _since_push := 0.0
## World id -> {"host", "port", "max", "status", "server"}: the world each
## connected game server runs.
var _worlds := {}
var _worlds_dirty := false
var _presence_dirty := false


## One game server's connection.
class Link:
	var socket := WebSocketPeer.new()
	var nonce := ""
	var server_id := ""
	var ready := false
	var greeted := false
	var age := 0.0
	## Account ids this server has a player signed in to.
	var watching := {}


# --- The key and the wire, shared with `AccountLink` -------------------------

## The service key: the environment variable `KEY_ENV`, else the file `path`.
## With `create`, a missing file is made with a fresh random key (the
## service does this on its first start; game servers only read it).
static func load_key(path: String, create := false) -> String:
	var from_env := OS.get_environment(KEY_ENV).strip_edges()
	if from_env != "":
		return from_env
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	if not create:
		return ""
	var made := Crypto.new().generate_random_bytes(32).hex_encode()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return made if SafeFile.write(path, made + "\n") else ""


## What proves a side holds `p_key`: an HMAC of the other side's nonce.
static func proof(p_key: String, nonce: String, who: String) -> String:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, p_key.to_utf8_buffer(),
			(nonce + ":" + who).to_utf8_buffer()).hex_encode()


static func same(a: String, b: String) -> bool:
	return Crypto.new().constant_time_compare(a.to_utf8_buffer(), b.to_utf8_buffer())


static func new_nonce() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


static func pack(message: Dictionary) -> PackedByteArray:
	return var_to_bytes(message)


## The message in `data`, or {} if it is not one. Never decodes objects.
static func unpack(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_MESSAGE:
		return {}
	var message: Variant = bytes_to_var(data)
	return message if typeof(message) == TYPE_DICTIONARY else {}


## A socket set up to carry whole account snapshots.
static func roomy(socket: WebSocketPeer) -> WebSocketPeer:
	socket.inbound_buffer_size = MAX_MESSAGE
	socket.outbound_buffer_size = MAX_MESSAGE
	socket.max_queued_packets = 8192
	return socket


# --- Running ------------------------------------------------------------------

## Opens the accounts and starts listening. Returns OK or an error.
func start(port := DEFAULT_PORT) -> Error:
	# Game servers outlive a restart of this program, so a deploy found saved
	# is still a life being played, not a lost one.
	stash.returns_lost_deploys = false
	stash.track_touched = true
	if key == "":
		key = load_key(stash.save_dir.path_join(KEY_FILE), stash.persist)
	if key.length() < 16:
		push_error("AccountService: no service key (set %s or keep one in %s)" % [KEY_ENV,
				stash.save_dir.path_join(KEY_FILE)])
		return ERR_UNCONFIGURED
	if stash.persist and stash.store() == null:
		return ERR_CANT_OPEN
	market.open(stash.save_dir, stash.persist)
	clans.open(stash.save_dir, stash.persist)
	social.persist = stash.persist
	social.save_dir = stash.save_dir.path_join("social")
	social.load_server_news(stash.save_dir.path_join("news.json"))
	stash.backup_if_due()
	return _tcp.listen(port, bind)


func _exit_tree() -> void:
	stop()


func stop() -> void:
	for link in _links:
		link.socket.close()
	_links.clear()
	_tcp.stop()
	stash.close()


## How many game servers are connected and signed in.
func servers() -> int:
	return _links.filter(func(link: Link) -> bool: return link.ready).size()


func _process(delta: float) -> void:
	poll(delta)


## Takes new connections and answers what the connected servers sent.
func poll(delta := 0.0) -> void:
	while _tcp.is_connection_available():
		var link := Link.new()
		roomy(link.socket)
		if link.socket.accept_stream(_tcp.take_connection()) == OK:
			_links.append(link)
	for link: Link in _links.duplicate():
		link.socket.poll()
		link.age += delta
		var state := link.socket.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED or (not link.ready and link.age > HELLO_TIMEOUT):
			if link.ready:
				print("AccountService: %s disconnected" % link.server_id)
				_forget_server(link.server_id)
			link.socket.close()
			_links.erase(link)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			continue
		if not link.greeted:
			link.greeted = true
			link.nonce = new_nonce()
			link.socket.put_packet(pack({"hello": link.nonce, "protocol": PROTOCOL}))
		while link.socket.get_available_packet_count() > 0:
			var message := unpack(link.socket.get_packet())
			if link.ready:
				_answer(link, message)
			else:
				_greet(link, message)
	_since_push += delta
	if _since_push >= PUSH_EVERY:
		_since_push = 0.0
		_push_what_changed()
	_since_prune += delta
	if _since_prune >= PRUNE_EVERY:
		_since_prune = 0.0
		var store: RefCounted = stash.store()
		if store != null:
			store.prune_receipts(RECEIPT_LIFE)
		stash.backup_if_due()


## A new connection's answer to the hello.
func _greet(link: Link, message: Dictionary) -> void:
	var server_id := str(message.get("server", "")).left(64)
	var problem := ""
	if int(message.get("protocol", -1)) != PROTOCOL:
		problem = "This game server and the account service are different versions."
	elif server_id == "" or not same(str(message.get("proof", "")), proof(key, link.nonce, server_id)):
		problem = "Wrong service key."
	if problem != "":
		link.socket.put_packet(pack({"refused": problem, "protocol": PROTOCOL}))
		link.socket.close(1008, problem)
		print("AccountService: refused a connection (%s)" % problem)
		return
	# One connection for each server: a newer one takes over.
	for other: Link in _links.duplicate():
		if other != link and other.server_id == server_id:
			other.socket.close()
			_links.erase(other)
	link.server_id = server_id
	link.ready = true
	var returned := 0
	if message.get("fresh", false):
		# Whatever an earlier run of this server left behind is gone with it.
		_forget_server(server_id)
		stash.touched.clear()
		stash.begin_hold()
		returned = stash.release_deploys(server_id)
		stash.end_hold()
		# A player may be on another server by now: it hears the gear is back.
		_tell_others(link, stash.touched.duplicate())
	link.socket.put_packet(pack({"welcome": true, "protocol": PROTOCOL, "returned": returned,
			"proof": proof(key, str(message.get("nonce", "")), "service")}))
	print("AccountService: %s connected%s" % [server_id,
			" (%d deploys returned)" % returned if returned > 0 else ""])


# --- Requests -----------------------------------------------------------------

func _answer(link: Link, message: Dictionary) -> void:
	var id := str(message.get("id", ""))
	var what := str(message.get("call", ""))
	var args: Variant = message.get("args")
	if id == "" or not _fits(what, args):
		link.socket.put_packet(pack({"re": id, "answer": _fail("The account service does not know that request."),
				"accounts": {}}))
		return
	answered += 1
	var held := what in HELD
	if held:
		var kept := _receipt(id)
		if not kept.is_empty():
			# Sent twice: answered the first time, and that answer was lost.
			var again := {}
			if typeof(args[0] if args.size() > 0 else null) == TYPE_STRING and link.watching.has(args[0]):
				again[args[0]] = stash.snapshot(args[0])
			link.socket.put_packet(pack({"re": id, "answer": kept.answer, "accounts": again}))
			return
	var answer: Variant
	stash.touched.clear()
	if held:
		stash.begin_hold()
		answer = _run(link, id, what, args)
		var receipt := Marshalls.variant_to_base64({"answer": answer})
		if not stash.end_hold([id, receipt]).ok:
			answer = _fail("The account service could not save that. Try again in a moment.")
		elif stash.store() == null:
			_memory_receipts[id] = receipt
	else:
		# Sign-ins and the market save as they go; the rest only read.
		answer = _run(link, id, what, args)
	var changed: Array = stash.touched.duplicate()
	var mine := {}
	for account_id: String in changed:
		if link.watching.has(account_id):
			mine[account_id] = stash.snapshot(account_id)
	# What the request was about goes back too, changed or not, so the server
	# always ends up holding what the service holds.
	if what != "release" and args.size() > 0 and typeof(args[0]) == TYPE_STRING and link.watching.has(args[0]) \
			and not mine.has(args[0]):
		mine[args[0]] = stash.snapshot(args[0])
	if typeof(answer) == TYPE_DICTIONARY and link.watching.has(str(answer.get("account_id", ""))):
		mine[answer.account_id] = stash.snapshot(answer.account_id)
	link.socket.put_packet(pack({"re": id, "answer": answer, "accounts": mine}))
	_tell_others(link, changed)


## Sends each other server the accounts in `changed` that it has a player
## signed in to.
func _tell_others(from: Link, changed: Array) -> void:
	if changed.is_empty():
		return
	for other: Link in _links:
		if other == from or not other.ready:
			continue
		var theirs := {}
		for account_id: String in changed:
			if other.watching.has(account_id):
				theirs[account_id] = stash.snapshot(account_id)
		if not theirs.is_empty():
			other.socket.put_packet(pack({"push": "accounts", "accounts": theirs}))


func _run(link: Link, id: String, what: String, args: Array) -> Variant:
	match what:
		"sign_in":
			var result: Dictionary = stash.sign_in_with(args[0])
			if result.ok:
				link.watching[result.account_id] = true
			return result
		"watch":
			# A server back after its connection dropped says who it still has.
			for account_id: Variant in args[0]:
				if typeof(account_id) == TYPE_STRING and stash.load_account(account_id) != null:
					link.watching[account_id] = true
			var all := {}
			for account_id: String in link.watching:
				all[account_id] = stash.snapshot(account_id)
			return {"ok": true, "accounts": all}
		"recovery_code":
			return stash.make_recovery_code(args[0])
		"release":
			link.watching.erase(args[0])
			return {"ok": true}
		"fetch":
			return stash.snapshot(args[0])
		"names":
			var names := {}
			for account_id: Variant in args[0]:
				if typeof(account_id) == TYPE_STRING:
					names[account_id] = stash.name_of(account_id)
			return {"ok": true, "names": names}
		"deploy":
			var world := NetSession.world_for(args[1])
			if world == null:
				return _fail("The account service does not know that world.")
			return stash.deploy(args[0], world, link.server_id, id)
		"bank", "settle", "cancel_deploy":
			# Only the server that holds the deploy may touch it.
			if not stash.holds_deploy(args[0], link.server_id):
				return _fail("Not in a raid.")
			return stash.callv(what, args)
		"release_deploys":
			return {"ok": true, "returned": stash.release_deploys(link.server_id)}
		"change_scrip":
			return {"ok": stash.change_scrip(args[0], args[1])}
		"record_arena":
			stash.record_arena(args[0], args[1])
			return {"ok": true}
		"arena_prize":
			return stash.arena_prize(args[0], args[1], args[2])
		"record_race":
			return stash.record_race(args[0], args[1])
		"keep_ghost":
			return stash.keep_ghost(args[0], args[1], args[2], args[3], args[4])
		"tune_race":
			return stash.tune_race(args[0], args[1], args[2])
		"race_ghost":
			return stash.race_ghost(args[0], args[1], args[2])
		"race_bests":
			return {"ok": true, "rows": stash.race_bests(args[0])}
		"market":
			return _market(args[0], args[1], args[2], args[3], args[4])
		"board":
			market.expire(stash)
			return _board(args[0])
		"clan":
			return _clan(args[0], args[1], args[2], args[3])
		"clans":
			return {"ok": true, "state": clans.state()}
		"social":
			return _social(link, args[0], args[1], args[2])
		"announce":
			return _announce(link, args[0])
	# Everything else is the `StashService` call of the same name.
	return stash.callv(what, args)


## One request at the market kiosk, as a session of a server that keeps its
## own accounts would run it (`NetSession._request_market`). The server has
## already checked that the player stands in a safe zone.
func _market(action: String, account_id: String, item_id: String, a: int, b: int) -> Dictionary:
	var result: Dictionary
	if stash.is_deployed(account_id):
		result = _fail("Not while you are in the field.")
	elif action == "list":
		result = market.list(stash, account_id, item_id, a, b)
	elif action == "buy":
		result = market.buy(stash, account_id, a, b)
	elif action == "cancel":
		result = market.cancel(stash, account_id, a)
	else:
		return _fail("The account service does not know that request.")
	if result.ok:
		for link in _links:
			if link.ready:
				link.socket.put_packet(pack({"push": "market"}))
	return {"ok": true, "result": result, "board": _board(account_id)}


func _board(account_id: String) -> Dictionary:
	return market.snapshot(account_id, stash.name_of)


# --- Clans, the phone and the directory of worlds ----------------------------

## One request at the clan hall (`ClanService.ask`). A change goes to every
## server, and comes back with the answer so the asker has it first.
func _clan(action: String, account_id: String, a: String, b: String) -> Dictionary:
	if stash.is_deployed(account_id):
		return _fail("Not while you are in the field.")
	var result := clans.ask(action, account_id, a.left(64), b.left(16))
	if result.ok:
		result["state"] = clans.state()
		for link in _links:
			if link.ready:
				link.socket.put_packet(pack({"push": "clans", "state": result.state}))
	return result


## One request of the phone's (`SocialService.run`). A seat is named by the
## server that holds it, so one server can never give up another's.
func _social(link: Link, action: String, account_id: String, args: Array) -> Dictionary:
	if action in ["online", "offline", "where"] and not args.is_empty() and typeof(args.back()) == TYPE_STRING:
		args = args.duplicate()
		args[args.size() - 1] = _seat(link.server_id, args.back())
	var result := social.run(action, account_id, args)
	var tell: Array = result.tell
	if SocialService.EVERYONE in tell:
		_presence_dirty = true
	for other: Link in _links:
		if not other.ready:
			continue
		var snapshots := {}
		var notices := {}
		for told: String in tell:
			if told != SocialService.EVERYONE and other.watching.has(told) and (other != link or told != account_id):
				snapshots[told] = social.snapshot(told)
		for told: String in result.notices:
			if other.watching.has(told):
				notices[told] = result.notices[told]
		if not snapshots.is_empty() or not notices.is_empty():
			other.socket.put_packet(pack({"push": "social", "snapshots": snapshots, "notices": notices}))
	# The asker's own phone comes back with the answer.
	result["snapshot"] = social.snapshot(account_id)
	return result


static func _seat(server_id: String, seat: String) -> String:
	return "%s/%s" % [server_id, seat.left(64)]


## A game server says which world it runs: {"world", "host" ("" for the
## address its players already use), "port", "max", "status"
## (`Raid.status()`)}. Answers with the whole directory.
func _announce(link: Link, info: Dictionary) -> Dictionary:
	var world_id := str(info.get("world", "")).left(32)
	var port := int(info.get("port", 0))
	if NetSession.world_for(world_id) == null or port <= 0 or port > 65535:
		return _fail("The account service does not know that world.")
	var status: Variant = info.get("status")
	var entry := {"host": str(info.get("host", "")).left(255), "port": port, "max": maxi(0, int(info.get("max", 0))),
			"status": status if typeof(status) == TYPE_DICTIONARY else {}, "server": link.server_id}
	if _worlds.get(world_id, {}) != entry:
		_worlds[world_id] = entry
		_worlds_dirty = true
	return {"ok": true, "worlds": directory()}


## Every world a connected game server runs: world id -> {"host", "port",
## "max", "status"}.
func directory() -> Dictionary:
	var out := {}
	for world_id: String in _worlds:
		var entry: Dictionary = _worlds[world_id].duplicate(true)
		entry.erase("server")
		out[world_id] = entry
	return out


## A game server went away: its world is off the directory and everyone it
## had signed in is off it.
func _forget_server(server_id: String) -> void:
	for world_id: String in _worlds.keys():
		if _worlds[world_id].server == server_id:
			_worlds.erase(world_id)
			_worlds_dirty = true
	if social.drop_seats(_seat(server_id, "")):
		_presence_dirty = true


## Sends every server what changed since the last time: the directory, and
## the phones of its players when who is online did.
func _push_what_changed() -> void:
	if _worlds_dirty:
		_worlds_dirty = false
		var worlds := directory()
		for link in _links:
			if link.ready:
				link.socket.put_packet(pack({"push": "worlds", "worlds": worlds}))
	if _presence_dirty:
		_presence_dirty = false
		for link in _links:
			if not link.ready:
				continue
			var snapshots := {}
			for account_id: String in link.watching:
				if social.is_online(account_id):
					snapshots[account_id] = social.snapshot(account_id)
			if not snapshots.is_empty():
				link.socket.put_packet(pack({"push": "social", "snapshots": snapshots, "notices": {}}))


## The answer kept for a request already done, or {}.
func _receipt(id: String) -> Dictionary:
	var store: RefCounted = stash.store()
	var text: String = store.receipt(id) if store != null else str(_memory_receipts.get(id, ""))
	if text == "":
		return {}
	var kept: Variant = Marshalls.base64_to_variant(text)
	return kept if typeof(kept) == TYPE_DICTIONARY and kept.has("answer") else {}


## Receipts when nothing is saved (tests).
var _memory_receipts := {}


static func _fits(what: String, args: Variant) -> bool:
	if not CALLS.has(what) or typeof(args) != TYPE_ARRAY:
		return false
	var types: Array = CALLS[what]
	if args.size() != types.size():
		return false
	for i in types.size():
		if typeof(args[i]) != types[i]:
			return false
	return true


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
