extends RefCounted
## Server saves that never leave half a file, and rolling backups of them.
##
## `write` puts the text beside the real file and swaps it in, so a crash
## mid-write leaves the old file whole. If the swap itself was cut short, the
## new text is still in the ".tmp" beside it, and `read` and `exists` find it
## there. `StashService`, `SocialService` and `ClanService` all save this way.
##
## `backup` copies a whole save folder into a dated folder of its own and
## keeps only the newest few, so a bad save or a bug that empties a stash can
## be undone by hand (docs/hosting.md, "Backups").
##
## Load with `const SafeFile := preload("res://core/account/safe_file.gd")`.

const TEMP := ".tmp"


## Saves `text` at `path` whole or not at all. Returns false (with a warning)
## if it could not be written.
static func write(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + TEMP
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("SafeFile: could not write %s" % temp)
		return false
	file.store_string(text)
	file.close()
	# A rename over the old file replaces it in one step. Only where that is
	# refused is the old file removed first; `read` still finds the ".tmp".
	if DirAccess.rename_absolute(temp, path) == OK:
		return true
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp, path) == OK


## True if `path` was saved, even if its last swap was cut short.
static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + TEMP)


## The saved text at `path`, or "" if there is none. A file left only as its
## ".tmp" (the swap was cut short) is read from there.
static func read(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	if FileAccess.file_exists(path + TEMP):
		return FileAccess.get_file_as_string(path + TEMP)
	return ""


## The saved JSON at `path`, or null if there is none or it does not parse.
## A whole file that does not parse falls back to a ".tmp" that does.
static func read_json(path: String) -> Variant:
	var data: Variant = JSON.parse_string(read(path)) if exists(path) else null
	if data == null and FileAccess.file_exists(path) and FileAccess.file_exists(path + TEMP):
		data = JSON.parse_string(FileAccess.get_file_as_string(path + TEMP))
	return data


## Copies every file under `dir` (its subfolders too) into a new folder
## under `into`, named by the time, and deletes all but the newest `keep`
## backups there. Returns the new folder, or "" if there was nothing to copy.
static func backup(dir: String, into: String, keep: int) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "-")
	var target := into.path_join(stamp)
	var n := 1
	while DirAccess.dir_exists_absolute(target):
		n += 1
		target = into.path_join("%s-%d" % [stamp, n])
	if _copy_tree(dir, target) == 0:
		DirAccess.remove_absolute(target)
		return ""
	prune(into, keep)
	return target


## The backups under `into`, oldest first.
static func backups_in(into: String) -> PackedStringArray:
	var dirs := DirAccess.get_directories_at(into) if DirAccess.dir_exists_absolute(into) else PackedStringArray()
	dirs.sort()
	return dirs


## Deletes all but the newest `keep` backups under `into`.
static func prune(into: String, keep: int) -> void:
	var dirs := backups_in(into)
	for i in maxi(0, dirs.size() - maxi(keep, 1)):
		_remove_tree(into.path_join(dirs[i]))


static func _copy_tree(from: String, to: String) -> int:
	var copied := 0
	DirAccess.make_dir_recursive_absolute(to)
	for file in DirAccess.get_files_at(from):
		if file.ends_with(TEMP) and FileAccess.file_exists(from.path_join(file.trim_suffix(TEMP))):
			continue
		if DirAccess.copy_absolute(from.path_join(file), to.path_join(file)) == OK:
			copied += 1
	for sub in DirAccess.get_directories_at(from):
		copied += _copy_tree(from.path_join(sub), to.path_join(sub))
	return copied


static func _remove_tree(dir: String) -> void:
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
