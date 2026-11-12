class_name ClanService
extends RefCounted
## Clans: who is in which, kept by the server. A clan is a name, a short tag
## and a list of account ids; an account is in one clan at most. Membership
## is keyed by the account id a peer signed in with, never by anything the
## client claims. `NetSession` turns requests into calls here and tells the
## `Raid` which players stand together (`Raid.set_team`).
##
## One file, `clans.json`, in `save_dir`. Every session of a server shares one
## service, like the `StashService`.

const SAVE_VERSION := 1
const NAME_MIN := 3
const NAME_MAX := 24
const TAG_MIN := 2
const TAG_MAX := 4

## Where `clans.json` lives.
var save_dir := "user://accounts"
## Tests turn this off so they never touch real saves.
var persist := true
## The most members a clan may have.
var max_members := 24

var _clans := {}    # clan id -> {"name", "tag", "leader", "members": [account ids]}
var _member := {}   # account id -> clan id
var _next_id := 1
var _opened := false


## Reads the saved clans, once. Later calls do nothing, so sessions that
## share a service can each call it.
func open(p_dir: String, p_persist: bool) -> void:
	if _opened:
		return
	_opened = true
	save_dir = p_dir
	persist = p_persist
	if not persist or not FileAccess.file_exists(_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("clans")) != TYPE_DICTIONARY:
		return
	_next_id = maxi(1, int(parsed.get("next_id", 1)))
	for id: Variant in parsed.clans:
		var saved: Variant = parsed.clans[id]
		if typeof(saved) != TYPE_DICTIONARY or typeof(saved.get("members")) != TYPE_ARRAY:
			continue
		var members: Array[String] = []
		for account: Variant in saved.members:
			if typeof(account) == TYPE_STRING and account != "" and not _member.has(account) \
					and members.size() < max_members:
				members.append(account)
		var name := clean_name(str(saved.get("name", "")))
		var tag := clean_tag(str(saved.get("tag", "")))
		if members.is_empty() or name.length() < NAME_MIN or tag.length() < TAG_MIN:
			continue
		var leader := str(saved.get("leader", ""))
		_clans[str(id)] = {"name": name, "tag": tag, "leader": leader if leader in members else members[0],
				"members": members}
		for account in members:
			_member[account] = str(id)


## A clan name as it is kept: printable, single spaces, trimmed.
static func clean_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		var code := ch.unicode_at(0)
		if code < 32 or ch in "[]<>{}":
			continue
		if ch == " " and out.ends_with(" "):
			continue
		out += ch
	return out.left(NAME_MAX).strip_edges()


## A tag as it is kept: capital letters and digits only.
static func clean_tag(raw: String) -> String:
	var out := ""
	for ch in raw.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out.left(TAG_MAX)


## Founds a clan with `account_id` as its leader.
func create(account_id: String, raw_name: String, raw_tag: String) -> Dictionary:
	if account_id == "":
		return _fail("Sign in first.")
	if _member.has(account_id):
		return _fail("Leave your clan first.")
	var name := clean_name(raw_name)
	var tag := clean_tag(raw_tag)
	if name.length() < NAME_MIN:
		return _fail("A clan name needs at least %d characters." % NAME_MIN)
	if tag.length() < TAG_MIN:
		return _fail("A tag is %d to %d letters or digits." % [TAG_MIN, TAG_MAX])
	for id: String in _clans:
		if _clans[id].name.to_lower() == name.to_lower():
			return _fail("That name is taken.")
		if _clans[id].tag == tag:
			return _fail("That tag is taken.")
	var clan_id := "c%d" % _next_id
	_next_id += 1
	var members: Array[String] = [account_id]
	_clans[clan_id] = {"name": name, "tag": tag, "leader": account_id, "members": members}
	_member[account_id] = clan_id
	_save()
	return {"ok": true, "clan": clan_id}


func join(account_id: String, clan_id: String) -> Dictionary:
	if account_id == "":
		return _fail("Sign in first.")
	if _member.has(account_id):
		return _fail("Leave your clan first.")
	if not _clans.has(clan_id):
		return _fail("That clan is gone.")
	var clan: Dictionary = _clans[clan_id]
	if clan.members.size() >= max_members:
		return _fail("That clan is full.")
	clan.members.append(account_id)
	_member[account_id] = clan_id
	_save()
	return {"ok": true, "clan": clan_id}


## Leaves the clan. The longest-standing member takes over from a leader who
## goes, and a clan with nobody left is gone.
func leave(account_id: String) -> Dictionary:
	if not _member.has(account_id):
		return _fail("You are not in a clan.")
	var clan_id: String = _member[account_id]
	var clan: Dictionary = _clans[clan_id]
	clan.members.erase(account_id)
	_member.erase(account_id)
	if clan.members.is_empty():
		_clans.erase(clan_id)
	elif clan.leader == account_id:
		clan.leader = clan.members[0]
	_save()
	return {"ok": true, "clan": clan_id}


## The id of the clan an account is in, or "".
func clan_of(account_id: String) -> String:
	return _member.get(account_id, "")


func name_of(clan_id: String) -> String:
	return _clans[clan_id].name if _clans.has(clan_id) else ""


func tag_of(clan_id: String) -> String:
	return _clans[clan_id].tag if _clans.has(clan_id) else ""


func members_of(clan_id: String) -> Array[String]:
	var out: Array[String] = []
	if _clans.has(clan_id):
		out.assign(_clans[clan_id].members)
	return out


## What one player is shown: their own clan with its members by name, and
## every clan there is to join, biggest first. `shown_name` turns an account
## id into a display name, so no account id leaves the server.
func snapshot(account_id: String, shown_name: Callable) -> Dictionary:
	var mine := {}
	var clan_id := clan_of(account_id)
	if clan_id != "":
		var clan: Dictionary = _clans[clan_id]
		var names: Array[String] = []
		for member: String in clan.members:
			names.append(str(shown_name.call(member)))
		mine = {"id": clan_id, "name": clan.name, "tag": clan.tag, "members": names,
				"leader": str(shown_name.call(clan.leader)), "is_leader": clan.leader == account_id}
	var listed: Array[Dictionary] = []
	for id: String in _clans:
		listed.append({"id": id, "name": _clans[id].name, "tag": _clans[id].tag,
				"members": _clans[id].members.size(), "full": _clans[id].members.size() >= max_members})
	listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.members > b.members if a.members != b.members else a.name < b.name)
	return {"clan": mine, "clans": listed}


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}


func _path() -> String:
	return save_dir.path_join("clans.json")


func _save() -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	var file := FileAccess.open(_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"version": SAVE_VERSION, "next_id": _next_id, "clans": _clans}))
