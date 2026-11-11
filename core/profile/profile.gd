extends Node
## Autoload `Profile`: what the player keeps between raids. Shared by all worlds.
## Saved locally for now; the online phase moves this to a backend.
##
## Gear rules: the stash is safe. Whatever is in the loadout leaves the stash
## when you deploy, and only comes back if you extract.

const SAVE_PATH := "user://profile.json"
## Given once to every profile so there is gear to try loadouts with.
const WELCOME_CRATE: Array[String] = ["rifle_carbine", "frame_trooper", "medkit", "medkit"]

## Tests turn this off so they never touch a real save.
var persist := true
var stash: Array[String] = []
## Slot name (see Loadout.SLOTS) -> item id. A missing slot uses the free scrap kit.
var loadout := {}
var welcome_granted := false
var raids_played := 0
var raids_extracted := 0
var kills := 0


func _ready() -> void:
	load_profile()
	grant_welcome_crate()


func reset() -> void:
	stash.clear()
	loadout.clear()
	welcome_granted = false
	raids_played = 0
	raids_extracted = 0
	kills = 0


func grant_welcome_crate() -> void:
	if welcome_granted:
		return
	welcome_granted = true
	add_to_stash(WELCOME_CRATE)


## Adds items to the stash. Starter kit items are free and never stashed.
func add_to_stash(ids: Array) -> void:
	for id: String in ids:
		if ItemDB.has_item(id) and not ItemDB.has_tag(id, "starter"):
			stash.append(id)
	save()


## Puts a stash item in a loadout slot. Returns false if it does not fit.
func equip(slot: String, id: String) -> bool:
	if not Loadout.SLOTS.has(slot) or id not in stash or not ItemDB.has_tag(id, Loadout.SLOTS[slot]):
		return false
	loadout[slot] = id
	save()
	return true


func unequip(slot: String) -> void:
	loadout.erase(slot)
	save()


func equipped(slot: String) -> String:
	return loadout.get(slot, "")


## Drops loadout entries whose item is no longer in the stash (lost in a raid).
func validate_loadout() -> void:
	for slot: String in loadout.keys():
		if loadout[slot] not in stash:
			loadout.erase(slot)
	save()


## Takes the loadout out of the stash for a raid and returns the full kit:
## chosen gear, the world's free scrap item for every empty slot, and healing.
func checkout_loadout(world: WorldDef) -> Array[String]:
	validate_loadout()
	var starter := world.starter_loadout()
	var kit: Array[String] = []
	for slot: String in Loadout.SLOTS:
		var id := equipped(slot)
		if id != "":
			stash.erase(id)
			kit.append(id)
			continue
		for free_id in starter:
			if ItemDB.has_tag(free_id, Loadout.SLOTS[slot]):
				kit.append(free_id)
				break
	var heals := 0
	for id in stash.duplicate():
		if heals >= Loadout.MAX_HEAL_ITEMS:
			break
		if ItemDB.has_tag(id, "heal"):
			stash.erase(id)
			kit.append(id)
			heals += 1
	if heals == 0:
		for free_id in starter:
			if ItemDB.has_tag(free_id, "heal"):
				kit.append(free_id)
				break
	save()
	return kit


func record_raid(result: Dictionary) -> void:
	raids_played += 1
	if result.get("outcome", "") == "extracted":
		raids_extracted += 1
	kills += result.get("kills", 0)
	validate_loadout()


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
		"version": 2,
		"stash": stash,
		"loadout": loadout,
		"welcome_granted": welcome_granted,
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
		if typeof(id) == TYPE_STRING and ItemDB.has_item(id) and not ItemDB.has_tag(id, "starter"):
			stash.append(id)
	loadout.clear()
	var saved_loadout: Variant = data.get("loadout", {})
	if typeof(saved_loadout) == TYPE_DICTIONARY:
		for slot: Variant in saved_loadout:
			if typeof(slot) == TYPE_STRING and typeof(saved_loadout[slot]) == TYPE_STRING:
				loadout[slot] = saved_loadout[slot]
	welcome_granted = bool(data.get("welcome_granted", false))
	raids_played = int(data.get("raids_played", 0))
	raids_extracted = int(data.get("raids_extracted", 0))
	kills = int(data.get("kills", 0))
	validate_loadout()
