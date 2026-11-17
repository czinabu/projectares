extends RefCounted
## Server saves never leave half a file and are backed up (DESIGN.md
## section 14, the hardening pass): `SafeFile` writes beside the real file
## and swaps it in, finds a save whose swap was cut short, and keeps rolling
## backups; the clans file saves that way too; and an account file that
## cannot be read is never overwritten by a new account. No server, so it
## runs in the offline tier. `-- --groups SaveSafetyTests` runs just these.

const SafeFile := preload("res://core/account/safe_file.gd")
const AccountStore := preload("res://core/account/account_store.gd")
const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Save safety: whole saves, found again after a crash, and backed up")
	var root := "user://test_save_safety_%d" % Time.get_ticks_usec()
	var dir := root.path_join("accounts")

	# A save is written whole, and the swap leaves nothing behind.
	var path := dir.path_join("one.json")
	t.check(SafeFile.write(path, "{\"a\": 1}") and SafeFile.read(path) == "{\"a\": 1}"
			and not FileAccess.file_exists(path + SafeFile.TEMP), "a save is written whole, with no leftover")
	t.check(SafeFile.write(path, "{\"a\": 2}") and SafeFile.read_json(path).a == 2.0, "a second save replaces the first")
	# A crash between writing and swapping: only the ".tmp" is left.
	DirAccess.rename_absolute(path, path + SafeFile.TEMP)
	t.check(SafeFile.exists(path) and SafeFile.read_json(path).a == 2.0,
			"a save whose swap was cut short is found in its .tmp")
	# A torn main file falls back to a whole .tmp beside it.
	var torn := FileAccess.open(path, FileAccess.WRITE)
	torn.store_string("{\"a\": ")
	torn.close()
	t.check(SafeFile.read_json(path).a == 2.0, "a torn save falls back to the whole one beside it")
	DirAccess.remove_absolute(path + SafeFile.TEMP)
	t.check(SafeFile.read_json(path) == null and SafeFile.read_json(dir.path_join("none.json")) == null,
			"a torn save with nothing beside it, or none at all, reads as nothing")
	DirAccess.remove_absolute(path)

	# An account that cannot be read is never written over.
	var service := StashService.new()
	service.save_dir = dir
	service.backup_every = 0.0
	var secret := StashService.new_secret()
	t.check(service.sign_in("Tamsin", secret).ok, "an account is made and saved")
	var store: RefCounted = service.store()
	store._bind("UPDATE accounts SET data = ? WHERE id = ?", ["not json", "tamsin"])
	var later := StashService.new()
	later.save_dir = dir
	later.backup_every = 0.0
	var refused := later.sign_in("Tamsin", secret)
	store._bind("SELECT data FROM accounts WHERE id = ?", ["tamsin"])
	t.check(not refused.ok and "backup" in str(refused.get("error", ""))
			and str(store._db.get("query_result")[0].data) == "not json",
			"an unreadable account refuses sign-in and is left as it was for the host to restore")
	store.write([service.load_account("tamsin").to_dict()])
	later.close()

	# Clans save through the same swap.
	var clans := ClanService.new()
	clans.open(dir, true)
	var made := clans.create("tamsin", "Swappers", "SWP")
	t.check(made.ok and FileAccess.file_exists(dir.path_join("clans.json"))
			and not FileAccess.file_exists(dir.path_join("clans.json") + SafeFile.TEMP),
			"the clans file is written whole, with no leftover")
	var reopened := ClanService.new()
	reopened.open(dir, true)
	t.check(reopened.name_of(made.clan) == "Swappers" and reopened.clan_of("tamsin") == made.clan,
			"a new server reads the clans back")

	# Backups: the whole folder, once when due, the newest few kept.
	var backed := StashService.new()
	backed.save_dir = dir
	backed.backups_kept = 2
	t.check(backed.backup_dir() == dir + "_backups", "backups go beside the save folder, never inside it")
	var first := backed.backup_if_due()
	var restored := StashService.new()
	restored.save_dir = first
	restored.backup_every = 0.0
	t.check(first != "" and FileAccess.file_exists(first.path_join(AccountStore.FILE_NAME))
			and not FileAccess.file_exists(first.path_join(AccountStore.FILE_NAME + "-wal"))
			and restored.load_account("tamsin") != null
			and FileAccess.file_exists(first.path_join("clans.json")),
			"the first backup copies every account (a clean copy of the database) and the clans")
	restored.close()
	t.check(backed.backup_if_due() == "", "the next backup waits for backup_every")
	for i in 3:
		SafeFile.backup(dir, backed.backup_dir(), backed.backups_kept)
	var kept := SafeFile.backups_in(backed.backup_dir())
	t.check(kept.size() == 2 and first.get_file() not in kept, "only the newest backups are kept")
	var off := StashService.new()
	off.save_dir = dir
	off.backup_every = 0.0
	var quiet := StashService.new()
	quiet.save_dir = dir
	quiet.persist = false
	t.check(off.backup_if_due() == "" and quiet.backup_if_due() == "",
			"no backups when they are off, or when nothing is saved")
	t.check(SafeFile.backup(root.path_join("missing"), root.path_join("missing_backups"), 2) == "",
			"a folder that is not there is not backed up")

	t._wipe_dir(root)
	t._wipe_dir(dir + "_backups")
