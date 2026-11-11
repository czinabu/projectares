extends RefCounted
## Server side of the phone: who is online, contacts, messages, invites and
## news. The dedicated server holds one `SocialService` beside its
## `StashService`; `NetSession` turns client requests into calls here and
## sends each affected player a fresh `snapshot` afterwards.
##
## Load with `const SocialService := preload("res://core/social/social_service.gd")`
## (no `class_name`, so it works before Godot rescans the project).
##
## Everything is keyed by account id (see `StashService.id_for_name`). A client
## never says who it is in a request: `NetSession` passes the account id the
## peer signed in with.
##
## Messages and contacts are saved per account, so a message to a saved
## contact who is offline is waiting for them at their next sign-in. Invites
## live only in memory and expire: they are about playing together now.
##
## Every call that can fail returns a Dictionary with "ok" (bool) and, when
## false, "error" (a short reason a client can show).

const SAVE_VERSION := 1
const MAX_MESSAGE := 240
## Messages kept per account, oldest dropped first.
const MAX_LOG := 120
const MAX_CONTACTS := 100
## Seconds an invite stays open.
const INVITE_SECONDS := 120.0
## At most this many messages per account in any RATE_WINDOW seconds.
const RATE_LIMIT := 6
const RATE_WINDOW := 10.0
## What an invite can be for: the raid on this server, or the inviter's base.
const INVITE_KINDS := ["world", "base"]
## Where a player can be. Other places (a social hub, a base) can add theirs.
const PLACE_NAMES := {"lobby": "In the lobby", "raid": "In a raid", "base": "At home base", "hub": "In the social hub"}

## Game news everyone sees, newest first. A server adds its own on top
## (`server_news`). Keep each one short: it is read on a phone.
const GAME_NEWS: Array[Dictionary] = [
	{"date": "2026-11-11", "title": "Phones are here",
		"body": "Press P to open your phone anywhere. Message players on your server, invite them to your raid or your base, change settings, and read the news."},
	{"date": "2026-11-11", "title": "Fair shots online",
		"body": "Online hits are now judged against what you saw on your screen, so aim straight at your target even on a slow connection."},
	{"date": "2026-11-10", "title": "The server keeps your stash",
		"body": "Online, every server keeps its own stash and loadout for you. Your solo stash stays safe at home."},
	{"date": "2026-11-09", "title": "Motorbikes",
		"body": "Put a bike in your vehicle slot and it waits beside you when you deploy. Extract riding it to keep it."},
]

## Where per-account social files live.
var save_dir := "user://accounts/social"
## Tests turn this off so they never touch real saves.
var persist := true
## News this server adds on top of `GAME_NEWS`, newest first.
var server_news: Array[Dictionary] = []

var _records := {}   # account id -> Record
var _online := {}    # account id -> {"name", "where"}
var _invites := {}   # invite id -> invite Dictionary
var _sent_times := {} # account id -> [unix seconds of recent messages]
var _next_id := 1


## One account's saved social data.
class Record:
	var id := ""
	var shown_name := ""
	## Account ids, in the order they were added.
	var contacts: Array[String] = []
	## Account id -> last name seen, so offline contacts keep a name.
	var names := {}
	var blocked: Array[String] = []
	## Messages sent and received, oldest first.
	var log: Array[Dictionary] = []
	var next_message := 1

	func to_dict() -> Dictionary:
		return {"version": SAVE_VERSION, "id": id, "name": shown_name, "contacts": contacts,
				"names": names, "blocked": blocked, "log": log, "next_message": next_message}

	func load_dict(data: Dictionary) -> void:
		id = str(data.get("id", ""))
		shown_name = str(data.get("name", ""))
		contacts.clear()
		for other: Variant in data.get("contacts", []):
			if typeof(other) == TYPE_STRING:
				contacts.append(other)
		var saved_names: Variant = data.get("names", {})
		names = saved_names if typeof(saved_names) == TYPE_DICTIONARY else {}
		blocked.clear()
		for other: Variant in data.get("blocked", []):
			if typeof(other) == TYPE_STRING:
				blocked.append(other)
		log.clear()
		for entry: Variant in data.get("log", []):
			if typeof(entry) == TYPE_DICTIONARY:
				log.append(entry)
		next_message = int(data.get("next_message", log.size() + 1))


# --- Presence ----------------------------------------------------------------

## A player signed in. `where` is a key of PLACE_NAMES.
func player_online(account_id: String, shown_name: String, where := "lobby") -> void:
	_online[account_id] = {"name": shown_name, "where": where}
	var record := _record(account_id)
	if record.shown_name != shown_name:
		record.shown_name = shown_name
		_save(record)


## A player left the server. Their invites go with them.
func player_offline(account_id: String) -> void:
	_online.erase(account_id)
	for invite_id: int in _invites.keys():
		var invite: Dictionary = _invites[invite_id]
		if invite.from == account_id or invite.to == account_id:
			_invites.erase(invite_id)


func set_where(account_id: String, where: String) -> void:
	if _online.has(account_id):
		_online[account_id].where = where


func is_online(account_id: String) -> bool:
	return _online.has(account_id)


func where(account_id: String) -> String:
	return _online.get(account_id, {}).get("where", "")


## Account ids of everyone online.
func online_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_online.keys())
	return out


func name_of(account_id: String) -> String:
	if _online.has(account_id):
		return _online[account_id].name
	var record := _record(account_id)
	return record.shown_name if record.shown_name != "" else account_id


# --- Contacts ----------------------------------------------------------------

## Saves someone you have met on this server as a contact.
func add_contact(account_id: String, other: String) -> Dictionary:
	if other == account_id:
		return _fail("That is you.")
	var record := _record(account_id)
	if other in record.contacts:
		return {"ok": true}
	if not _online.has(other) and not record.names.has(other):
		return _fail("Nobody by that name is on this server.")
	if record.contacts.size() >= MAX_CONTACTS:
		return _fail("Your contact list is full.")
	record.contacts.append(other)
	record.names[other] = name_of(other)
	_save(record)
	return {"ok": true}


func remove_contact(account_id: String, other: String) -> Dictionary:
	var record := _record(account_id)
	record.contacts.erase(other)
	_save(record)
	return {"ok": true}


## Blocks someone: their messages and invites stop reaching you.
func block(account_id: String, other: String) -> Dictionary:
	if other == account_id:
		return _fail("That is you.")
	var record := _record(account_id)
	if other not in record.blocked:
		record.blocked.append(other)
		record.names[other] = name_of(other)
	for invite_id: int in _invites.keys():
		if _invites[invite_id].from == other and _invites[invite_id].to == account_id:
			_invites.erase(invite_id)
	_save(record)
	return {"ok": true}


func unblock(account_id: String, other: String) -> Dictionary:
	var record := _record(account_id)
	record.blocked.erase(other)
	_save(record)
	return {"ok": true}


func has_blocked(account_id: String, other: String) -> bool:
	return other in _record(account_id).blocked


# --- Messages ----------------------------------------------------------------

## Sends a text message. The receiver must be online or one of your saved
## contacts. Returns {"ok", "message"}.
func send_message(from: String, to: String, text: String, now := -1.0) -> Dictionary:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	text = clean_text(text)
	if text == "":
		return _fail("Type a message first.")
	if to == from:
		return _fail("That is you.")
	var sender := _record(from)
	if not _online.has(to) and to not in sender.contacts:
		return _fail("They are not on this server. Save them as a contact to message them later.")
	if has_blocked(to, from):
		# Said plainly, so nobody keeps writing into the void.
		return _fail("%s is not taking your messages." % name_of(to))
	var recent: Array = _sent_times.get_or_add(from, [])
	while not recent.is_empty() and now - float(recent[0]) > RATE_WINDOW:
		recent.pop_front()
	if recent.size() >= RATE_LIMIT:
		return _fail("Slow down a little.")
	recent.append(now)
	var receiver := _record(to)
	var message := {"from": from, "from_name": name_of(from), "to": to, "to_name": name_of(to),
			"text": text, "time": now}
	sender.names[to] = message.to_name
	receiver.names[from] = message.from_name
	for record: Record in [sender, receiver]:
		var copy := message.duplicate()
		copy["id"] = record.next_message
		record.next_message += 1
		record.log.append(copy)
		while record.log.size() > MAX_LOG:
			record.log.pop_front()
		_save(record)
	return {"ok": true, "message": message}


## Text that is safe to show: no control characters, trimmed, not too long.
static func clean_text(text: String) -> String:
	var out := ""
	for c in text:
		if c.unicode_at(0) >= 32:
			out += c
		elif c == "\t" or c == "\n":
			out += " "
	return out.strip_edges().left(MAX_MESSAGE)


# --- Invites -----------------------------------------------------------------

## Invites someone online to join you. `kind` is "world" (the raid on this
## server, `world_id`) or "base" (your home base). Returns {"ok", "invite"}.
func invite(from: String, to: String, kind: String, world_id := "", now := -1.0) -> Dictionary:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	if kind not in INVITE_KINDS:
		return _fail("That is not something you can invite people to.")
	if to == from:
		return _fail("That is you.")
	if not _online.has(to):
		return _fail("%s is not online." % name_of(to))
	if has_blocked(to, from):
		return _fail("%s is not taking your invites." % name_of(to))
	# A fresh invite replaces an older one of the same kind.
	for invite_id: int in _invites.keys():
		var old: Dictionary = _invites[invite_id]
		if old.from == from and old.to == to and old.kind == kind:
			_invites.erase(invite_id)
	var made := {"id": _next_id, "from": from, "from_name": name_of(from), "to": to, "kind": kind,
			"world_id": world_id if kind == "world" else "", "expires": now + INVITE_SECONDS}
	_next_id += 1
	_invites[made.id] = made
	return {"ok": true, "invite": made}


## Accepts or declines an invite sent to `account_id`. Returns {"ok", "invite"}.
func answer_invite(account_id: String, invite_id: int, accept: bool, now := -1.0) -> Dictionary:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	_expire(now)
	var found: Dictionary = _invites.get(invite_id, {})
	if found.is_empty() or found.to != account_id:
		return _fail("That invite has run out.")
	_invites.erase(invite_id)
	if accept and not _online.has(found.from):
		return _fail("%s has left the server." % found.from_name)
	return {"ok": true, "invite": found, "accepted": accept}


## Open invites sent to `account_id`.
func invites_for(account_id: String, now := -1.0) -> Array[Dictionary]:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	_expire(now)
	var out: Array[Dictionary] = []
	for invite: Dictionary in _invites.values():
		if invite.to == account_id:
			out.append(invite)
	return out


func _expire(now: float) -> void:
	for invite_id: int in _invites.keys():
		if float(_invites[invite_id].expires) <= now:
			_invites.erase(invite_id)


# --- News --------------------------------------------------------------------

## Server news first, then the game's own.
func news() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(server_news)
	out.append_array(GAME_NEWS)
	return out


## Reads extra news from a JSON file: an array of {"date", "title", "body"}.
## A server operator drops it in the accounts folder as `news.json`.
func load_server_news(path: String) -> void:
	server_news.clear()
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_ARRAY:
		push_warning("SocialService: %s is not a list of news" % path)
		return
	for entry: Variant in data:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("title"):
			server_news.append({"date": str(entry.get("date", "")).left(20),
					"title": str(entry.title).left(80), "body": str(entry.get("body", "")).left(600)})


# --- Snapshot ----------------------------------------------------------------

## What a client's phone shows. Safe to send over the network.
## contacts: [{id, name, online, where, saved, blocked}], online players first.
## messages: [{id, from, from_name, to, to_name, text, time}], oldest first.
## invites: open invites to this player.
func snapshot(account_id: String, now := -1.0) -> Dictionary:
	var record := _record(account_id)
	var contacts: Array[Dictionary] = []
	var listed := {}
	for other: String in online_ids():
		if other != account_id and other not in record.blocked:
			listed[other] = true
			contacts.append(_contact_entry(record, other))
	for other: String in record.contacts:
		if not listed.has(other):
			listed[other] = true
			contacts.append(_contact_entry(record, other))
	for other: String in record.blocked:
		if not listed.has(other):
			contacts.append(_contact_entry(record, other))
	return {
		"account_id": account_id,
		"contacts": contacts,
		"messages": record.log.duplicate(true),
		"invites": invites_for(account_id, now),
		"news": news(),
	}


func _contact_entry(record: Record, other: String) -> Dictionary:
	var online := _online.has(other)
	var shown: String = _online[other].name if online else str(record.names.get(other, other))
	return {"id": other, "name": shown, "online": online, "where": where(other),
			"saved": other in record.contacts, "blocked": other in record.blocked}


# --- Storage -----------------------------------------------------------------

func _record(account_id: String) -> Record:
	if _records.has(account_id):
		return _records[account_id]
	var record := Record.new()
	record.id = account_id
	var path := _path_for(account_id)
	if persist and FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY and str(data.get("id", "")) == account_id:
			record.load_dict(data)
		else:
			push_warning("SocialService: %s is unreadable" % path)
	_records[account_id] = record
	return record


func _path_for(account_id: String) -> String:
	return save_dir.path_join(account_id + ".json")


func _save(record: Record) -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	var path := _path_for(record.id)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("SocialService: could not write %s" % temp)
		return
	file.store_string(JSON.stringify(record.to_dict(), "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(temp, path)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
