extends RefCounted
## TEMPORARY dev mode: everything unlocked for testing, plus a few cheats.
## Caleb's call (2026-11): it stays until the game is further along, then
## comes out. Everything it touches is marked "DEV MODE", so removing it is:
## delete `core/dev/`, then delete each line or block marked "DEV MODE".
##
## Load with `const DevMode := preload("res://core/dev/dev_mode.gd")`.
## Like `GameSettings` it is one shared copy held in static vars, kept in its
## own file so it never mixes with the real stash save.
##
## What it does, solo only:
##   - Swaps the local `Profile` onto a separate dev save
##     (`Profile.DEV_SAVE_PATH`), so the real stash is never touched, and keeps
##     that dev stash topped up with every piece of gear, clothing and
##     furniture, plenty of medkits, and as many scrip as a stash holds.
##   - Cheats in a solo `Raid` (`Raid.dev_cheats`, applied by the `Raid` to
##     its own players only): god mode, endless flight heat, endless ammo and
##     no ability cooldowns.
## It never reaches online play: the server keeps its own stash
## (`StashService`) and a `Raid` only applies cheats in `Mode.SOLO`.
## It is off and cannot be turned on in an exported game (`available`).

const StashRules := preload("res://core/account/stash_rules.gd")
const Economy := preload("res://core/economy/economy.gd")
const SAVE_PATH := "user://dev_mode.json"
## How many of each kind of item a dev stash is kept at.
const GEAR_COPIES := 1
const CONSUMABLE_COPIES := 10
const CHEATS := ["god", "heat", "ammo", "cooldowns"]
const CHEAT_NAMES := {"god": "God mode (no damage)", "heat": "Endless flight heat",
		"ammo": "Endless ammo, no reloads", "cooldowns": "No ability cooldowns"}

## Tests turn this off so they never touch a real file.
static var persist := true
static var enabled := false
## Cheat name (see `CHEATS`) -> on. Only matter while `enabled`.
static var cheats := {"god": true, "heat": true, "ammo": true, "cooldowns": true}
static var _loaded := false


## True only when running from the editor or a debug run, never in an
## exported game. Dev mode cannot be turned on otherwise.
static func available() -> bool:
	return OS.is_debug_build() and not OS.has_feature("template")


## True when dev mode is on and allowed here.
static func active() -> bool:
	return enabled and available()


## Loads once. Safe to call any number of times.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not persist or not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	enabled = bool(data.get("enabled", false))
	var saved: Variant = data.get("cheats", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for cheat: String in CHEATS:
			if saved.has(cheat):
				cheats[cheat] = bool(saved[cheat])


static func set_enabled(on: bool) -> void:
	enabled = on and available()
	save()


static func set_cheat(cheat: String, on: bool) -> void:
	if cheat in CHEATS:
		cheats[cheat] = on
		save()


## The cheats a solo raid should run with now: {} when dev mode is off.
static func raid_cheats() -> Dictionary:
	if not active():
		return {}
	var out := {}
	for cheat: String in CHEATS:
		if cheats.get(cheat, false):
			out[cheat] = true
	return out


static func save() -> void:
	if not persist:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("DevMode: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"enabled": enabled, "cheats": cheats}, "\t"))


## Every storable item a dev stash keeps, with how many: all gear that fits a
## loadout slot, clothing and furniture once each, and healing in bulk. Loot
## that is only worth selling is left out; the scrip cover that.
static func wanted_items() -> Dictionary:
	var want := {}
	for id: String in ItemDB.all_ids():
		if not StashRules.storable(id):
			continue
		if ItemDB.has_tag(id, "consumable"):
			want[id] = CONSUMABLE_COPIES
		elif _fits_any_slot(id) or ItemDB.has_tag(id, "cosmetic") or ItemDB.has_tag(id, "furniture"):
			want[id] = GEAR_COPIES
	return want


## Tops a stash up to `wanted_items` and returns the scrip to hold
## (`Economy.MAX_SCRIP`). Adds only what is missing, so gear lost in a raid
## comes back and nothing piles up. Plain data, so it works on any stash.
static func top_up(stash: Array[String]) -> int:
	var want := wanted_items()
	for id: String in want:
		var missing: int = want[id] - stash.count(id)
		for i in missing:
			stash.append(id)
	return Economy.MAX_SCRIP


static func _fits_any_slot(id: String) -> bool:
	for slot: String in Loadout.SLOTS:
		if Loadout.fits(slot, id):
			return true
	return false

