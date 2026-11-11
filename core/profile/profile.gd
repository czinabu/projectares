extends Node
## Autoload `Profile`: what the player keeps between raids. Shared by all worlds.
## Saved locally for now; the online phase moves this to a backend.

const SAVE_PATH := "user://profile.json"

## Tests turn this off so they never touch a real save.
var persist := true
var stash: Array[String] = []
var raids_played := 0
var raids_extracted := 0
var kills := 0


func _ready() -> void:
	load_profile()


func reset() -> void:
	stash.clear()
	raids_played = 0
	raids_extracted = 0
	kills = 0


func add_to_stash(ids: Array) -> void:
	for id: String in ids:
		stash.append(id)
	save()


func record_raid(result: Dictionary) -> void:
	raids_played += 1
	if result.get("outcome", "") == "extracted":
		raids_extracted += 1
	kills += result.get("kills", 0)
	save()


func stash_value() -> int:
	return ItemDB.total_value(stash)


func save() -> void:
	if not persist:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Profile: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"stash": stash,
		"raids_played": raids_played,
		"raids_extracted": raids_extracted,
		"kills": kills,
	}, "\t"))


func load_profile() -> void:
	if not persist or not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Profile: save file is unreadable, starting fresh")
		return
	stash.clear()
	for id: Variant in data.get("stash", []):
		if typeof(id) == TYPE_STRING and ItemDB.has_item(id):
			stash.append(id)
	raids_played = int(data.get("raids_played", 0))
	raids_extracted = int(data.get("raids_extracted", 0))
	kills = int(data.get("kills", 0))
