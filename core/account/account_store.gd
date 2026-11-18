extends RefCounted
## Where the server's accounts are kept on disk: one SQLite database
## (`accounts.sqlite` in the accounts folder), through the godot-sqlite
## extension (`addons/godot-sqlite`, MIT). `StashService` is its only user and
## keeps the rules; this only reads and writes whole accounts.
##
## Every write is one SQLite transaction, so a write of several accounts (a
## trade) lands whole or not at all, even if the server dies halfway through.
## Each account is one row: its id, its shown name and the account's save
## (`StashService.Account.to_dict`) as JSON, the same data the old account
## files held.
##
## The first time the database opens in a folder that still holds the old
## account files (`<id>.json`), they are imported in one transaction and each
## is then renamed to `<id>.json.imported`, never deleted. A file whose
## account the database already has (the server stopped after the import but
## before the rename) is only renamed: the database wins. A file that is not
## an account (news, clans) or cannot be read is left where it is.
##
## Where the extension is missing (a platform the addon ships no library for),
## the store falls back to the old one-file-per-account JSON and says so in
## the log. Those writes are each atomic, but a write of several accounts is
## not, so a server that trades should run where SQLite loads.
##
## Load with `const AccountStore := preload("res://core/account/account_store.gd")`.

const SafeFile := preload("res://core/account/safe_file.gd")

const FILE_NAME := "accounts.sqlite"
const SCHEMA_VERSION := 1
## How long a write waits for another connection (a second server process on
## the same folder) to finish its own, in milliseconds.
const BUSY_TIMEOUT_MS := 5000
const IMPORTED_SUFFIX := ".imported"

## "sqlite" or "json" once opened, "" before.
var kind := ""
var dir := ""
## How many old account files the last `open` imported.
var imported := 0

var _db: Object = null
var _json_receipts := {}  # request id -> [answer, unix time] (JSON fallback only)


## True when the SQLite extension loaded in this build.
static func sqlite_available() -> bool:
	return ClassDB.class_exists(&"SQLite")


## Opens the store in folder `p_dir`, making it if needed. `force_json` keeps
## the old file format (tests use it to check the fallback).
func open(p_dir: String, force_json := false) -> bool:
	close()
	dir = p_dir
	imported = 0
	DirAccess.make_dir_recursive_absolute(dir)
	if force_json or not sqlite_available():
		if not force_json:
			push_warning("AccountStore: the SQLite extension is missing here; keeping accounts as JSON files in %s" % dir)
		kind = "json"
		return true
	var db: Object = ClassDB.instantiate(&"SQLite")
	db.set("path", ProjectSettings.globalize_path(dir.path_join(FILE_NAME)))
	db.set("verbosity_level", 0)
	if not db.call("open_db"):
		push_error("AccountStore: could not open %s: %s" % [dir.path_join(FILE_NAME), db.get("error_message")])
		return false
	_db = db
	kind = "sqlite"
	var ok := _exec("PRAGMA busy_timeout = %d" % BUSY_TIMEOUT_MS) \
			and _exec("PRAGMA journal_mode = WAL") \
			and _exec("PRAGMA synchronous = FULL") \
			and _exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)") \
			and _exec("CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, data TEXT NOT NULL, updated INTEGER NOT NULL)") \
			and _exec("CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY, answer TEXT NOT NULL, at INTEGER NOT NULL)") \
			and _bind("INSERT OR IGNORE INTO meta (key, value) VALUES ('schema', ?)", [str(SCHEMA_VERSION)])
	if not ok:
		push_error("AccountStore: could not set up %s" % dir.path_join(FILE_NAME))
		close()
		return false
	_import_json_files()
	return true


func close() -> void:
	if _db != null:
		_db.call("close_db")
		_db = null
	kind = ""


func is_open() -> bool:
	return kind != ""


## The saved account with this id (its `to_dict`), or {} if there is none or
## it cannot be read.
func read(id: String) -> Dictionary:
	if kind == "json":
		var path := _json_path(id)
		if not SafeFile.exists(path):
			return {}
		var parsed: Variant = SafeFile.read_json(path)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("AccountStore: %s is unreadable" % path)
			return {}
		return parsed
	if kind != "sqlite" or not _bind("SELECT data FROM accounts WHERE id = ?", [id]):
		return {}
	var rows: Array = _db.get("query_result")
	if rows.is_empty():
		return {}
	var data: Variant = JSON.parse_string(str(rows[0].get("data", "")))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("AccountStore: the saved account %s is unreadable" % id)
		return {}
	return data


func has(id: String) -> bool:
	if kind == "json":
		return SafeFile.exists(_json_path(id))
	if kind != "sqlite" or not _bind("SELECT 1 AS found FROM accounts WHERE id = ?", [id]):
		return false
	return not (_db.get("query_result") as Array).is_empty()


## Every account id saved, sorted.
func ids() -> Array[String]:
	var out: Array[String] = []
	if kind == "json":
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".json"):
				out.append(file.get_basename())
	elif kind == "sqlite" and _exec("SELECT id FROM accounts"):
		for row: Dictionary in _db.get("query_result"):
			out.append(str(row.get("id", "")))
	out.sort()
	return out


## Writes the accounts (each a `to_dict` with an "id") as one transaction:
## all of them or, if anything fails, none. Returns whether they were written.
## `receipt` ([request id, answer text], see `receipt`) is written in that
## same transaction, so a request's changes and the record that it was
## answered land together or not at all.
func write(accounts: Array, receipt: Array = []) -> bool:
	if accounts.is_empty() and receipt.is_empty():
		return true
	if kind == "json":
		var all_ok := true
		for data: Dictionary in accounts:
			all_ok = _write_json(data) and all_ok
		if all_ok and receipt.size() == 2:
			_json_receipts[str(receipt[0])] = [str(receipt[1]), int(Time.get_unix_time_from_system())]
		return all_ok
	if kind != "sqlite" or not _exec("BEGIN IMMEDIATE"):
		return false
	var now := int(Time.get_unix_time_from_system())
	if receipt.size() == 2 and not _bind("INSERT OR REPLACE INTO receipts (id, answer, at) VALUES (?, ?, ?)",
			[str(receipt[0]), str(receipt[1]), now]):
		_exec("ROLLBACK")
		return false
	for data: Dictionary in accounts:
		if not _bind("INSERT INTO accounts (id, name, data, updated) VALUES (?, ?, ?, ?) "
				+ "ON CONFLICT(id) DO UPDATE SET name = excluded.name, data = excluded.data, updated = excluded.updated",
				[str(data.get("id", "")), str(data.get("name", "")), JSON.stringify(data), now]):
			push_warning("AccountStore: could not save %s: %s" % [data.get("id", ""), _db.get("error_message")])
			_exec("ROLLBACK")
			return false
	if not _exec("COMMIT"):
		_exec("ROLLBACK")
		return false
	return true


## The answer kept for request `id` (see `write`), or "" if that request was
## never answered here. The account service uses it to answer a request it
## is sent twice (the first answer was lost on the way) without doing it
## twice. The JSON fallback only remembers them until the program stops.
func receipt(id: String) -> String:
	if kind == "json":
		return str(_json_receipts[id][0]) if _json_receipts.has(id) else ""
	if kind != "sqlite" or not _bind("SELECT answer FROM receipts WHERE id = ?", [id]):
		return ""
	var rows: Array = _db.get("query_result")
	return "" if rows.is_empty() else str(rows[0].get("answer", ""))


## Forgets receipts older than `seconds`. A request is only ever repeated
## while its sender still waits for the answer, so they are short-lived.
func prune_receipts(seconds: float) -> void:
	var before := int(Time.get_unix_time_from_system() - seconds)
	if kind == "json":
		for id: String in _json_receipts.keys():
			if int(_json_receipts[id][1]) < before:
				_json_receipts.erase(id)
	elif kind == "sqlite":
		_bind("DELETE FROM receipts WHERE at < ?", [before])


## The ids of every saved account that has gear out in a world (a deploy
## that was never settled), sorted.
func deployed_ids() -> Array[String]:
	var out: Array[String] = []
	if kind == "json":
		for id in ids():
			if str(read(id).get("deployed_world", "")) != "":
				out.append(id)
	elif kind == "sqlite" and _exec("SELECT id FROM accounts WHERE json_extract(data, '$.deployed_world') != ''"):
		for row: Dictionary in _db.get("query_result"):
			out.append(str(row.get("id", "")))
	out.sort()
	return out


## Copies the whole store into `to_dir` as it stands right now: the database
## with `VACUUM INTO` (a consistent copy even while the server writes; never
## copy the live file and its WAL by hand), or the account files. Returns
## whether it worked.
func backup_to(to_dir: String) -> bool:
	DirAccess.make_dir_recursive_absolute(to_dir)
	if kind == "json":
		var all_ok := true
		for id in ids():
			all_ok = DirAccess.copy_absolute(_json_path(id), to_dir.path_join(id + ".json")) == OK and all_ok
		return all_ok
	var target := ProjectSettings.globalize_path(to_dir.path_join(FILE_NAME))
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	return kind == "sqlite" and _bind("VACUUM INTO ?", [target])


# --- The one-time import of the old account files ---------------------------

func _import_json_files() -> void:
	var found := {}  # id -> account data, for files whose account is new here
	var settled: Array[String] = []  # files to rename once the import is in
	var files := DirAccess.get_files_at(dir)
	for file in files:
		# An old save whose last swap was cut short is only its ".tmp".
		var torn := file.ends_with(".json" + SafeFile.TEMP)
		if not file.ends_with(".json") and not torn:
			continue
		var name := file.trim_suffix(SafeFile.TEMP) if torn else file
		if torn and name in files:
			continue  # read with its whole file
		var id := name.get_basename()
		# A quiet parse: a file that is not JSON is simply not an account.
		var json := JSON.new()
		var data: Variant = json.data if json.parse(SafeFile.read(dir.path_join(name))) == OK else null
		if not _looks_like_account(data, id) and not torn and (name + SafeFile.TEMP) in files:
			var temp := JSON.new()
			data = temp.data if temp.parse(FileAccess.get_file_as_string(dir.path_join(name + SafeFile.TEMP))) == OK else null
		if not _looks_like_account(data, id):
			continue  # not an account (news, clans), or unreadable: left alone
		settled.append(file)
		if not torn and (name + SafeFile.TEMP) in files:
			settled.append(name + SafeFile.TEMP)
		if not has(id):
			found[id] = data
	if settled.is_empty():
		return
	if not found.is_empty() and not write(found.values()):
		push_error("AccountStore: importing the old account files failed; they stay as they are")
		return
	imported = found.size()
	for file in settled:
		var from := dir.path_join(file)
		var to := from + IMPORTED_SUFFIX
		if FileAccess.file_exists(to):
			to = "%s.%d%s" % [from, Time.get_unix_time_from_system(), IMPORTED_SUFFIX]
		DirAccess.rename_absolute(from, to)
	if imported > 0:
		print("AccountStore: imported %d account file(s) into %s" % [imported, dir.path_join(FILE_NAME)])


static func _looks_like_account(data: Variant, id: String) -> bool:
	return typeof(data) == TYPE_DICTIONARY and str(data.get("id", "")) == id \
			and data.has("secret_hash") and data.has("salt")


# --- Internals ---------------------------------------------------------------

func _exec(sql: String) -> bool:
	return _db != null and bool(_db.call("query", sql))


func _bind(sql: String, args: Array) -> bool:
	return _db != null and bool(_db.call("query_with_bindings", sql, args))


func _json_path(id: String) -> String:
	return dir.path_join(id + ".json")


## The old format, written whole and swapped in (`SafeFile`).
func _write_json(data: Dictionary) -> bool:
	return SafeFile.write(_json_path(str(data.get("id", ""))), JSON.stringify(data, "\t"))
