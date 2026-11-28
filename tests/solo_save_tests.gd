extends RefCounted
## Solo saves survive a crash (the launch checklist, "Crash-safe saves"):
## the profile is written whole or not at all (`SafeFile`), the last good
## save is kept beside it (`Profile.BACKUP`) and loaded when the save itself
## is torn, a save that cannot be read either way is kept aside
## (`Profile.BROKEN`) rather than written over, and the settings file is
## written whole too. No server, so it runs in the offline tier.

const ProfileScript := preload("res://core/profile/profile.gd")
const SafeFile := preload("res://core/account/safe_file.gd")


static func run(t: Node) -> void:
	print("Solo saves: whole, backed up, and found again after a crash")
	var dir := "user://test_solo_save_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("profile.json")

	var p: Node = ProfileScript.new()
	p.persist = true
	p.save_path = path
	p.scrip = 111
	p.save()
	t.check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + SafeFile.TEMP),
			"a solo save is written whole, with no leftover")
	p.scrip = 222
	p.save()
	t.check(int(SafeFile.read_json(path + ProfileScript.BACKUP).scrip) == 111,
			"the save before it is kept as the backup")

	# A crash mid-write tears the file: the backup is loaded instead.
	var torn := FileAccess.open(path, FileAccess.WRITE)
	torn.store_string("{\"scrip\": 9")
	torn.close()
	var q: Node = _load(path)
	t.check(q.scrip == 111, "a torn save loads the backup (%d)" % q.scrip)
	t.check(FileAccess.file_exists(path + ProfileScript.BROKEN), "and the torn file is kept aside")
	q.scrip = 333
	q.save()
	t.check(int(SafeFile.read_json(path + ProfileScript.BACKUP).scrip) == 111,
			"saving over a torn file never pushes out the good backup")
	t.check(_load(path).scrip == 333, "the next save loads whole again")

	# A swap cut short leaves only the ".tmp": it is found.
	DirAccess.rename_absolute(path, path + SafeFile.TEMP)
	t.check(_load(path).scrip == 333, "a save whose swap was cut short is found in its .tmp")
	DirAccess.rename_absolute(path + SafeFile.TEMP, path)

	# Nothing readable at all: a fresh start, and the broken file is kept.
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("not json")
	junk.close()
	DirAccess.remove_absolute(path + ProfileScript.BACKUP)
	var r: Node = _load(path)
	t.check(r.scrip != 333 and SafeFile.read(path + ProfileScript.BROKEN) == "not json",
			"a save that cannot be read starts fresh and keeps the broken file aside")
	for n: Node in [p, q, r]:
		n.free()

	# Settings are written whole too.
	var src := FileAccess.get_file_as_string("res://core/settings/game_settings.gd")
	t.check("SafeFile.write(SAVE_PATH" in src and "SafeFile.read_json(SAVE_PATH)" in src,
			"the settings file is saved whole and read back the same way")
	_remove_tree(dir)


static func _load(path: String) -> Node:
	var p: Node = ProfileScript.new()
	p.persist = true
	p.save_path = path
	p.load_profile()
	return p


static func _remove_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
