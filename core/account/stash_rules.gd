extends RefCounted
## The gear rules for a stash and its loadout, shared by the local `Profile`
## and the server's `StashService`, so offline and online play follow the
## same rules. Pure functions on plain data: no autoloads touched except
## `ItemDB`, no files, no network.
##
## Load with `preload("res://core/account/stash_rules.gd")`.
##
## The rules: the stash is safe. Whatever is in the loadout leaves the stash
## when you deploy, and only comes back if you leave the world alive. Loot
## banked at a depot is added while you are out. Starter (scrap) items
## are free and never stored: every player owns one of each, to equip like
## any other piece (`free_items`). An empty slot is empty (Caleb's call: you
## can go bare), and power weapons are raid-only.

## The one player state: what a player takes from place to place. Your solo
## profile and your account on a server you host yourself (`main.gd
## host_and_join`) are the same player, so these keys are handed whole between
## them (`Profile.adopt_account`, `StashService.host_profile`), never merged.
const CARRIED: Array[String] = ["stash", "loadout", "mastery", "raids_played", "raids_extracted", "kills",
		"renown", "scrip", "arena_wins", "arena_losses", "base_upgrades", "blueprints"]


## Set on a save once its loadout follows the bare rule: from then on an
## empty slot means nothing at all. A save without it is from when an empty
## slot meant the free scrap item, so `upgrade_loadout` fills those slots
## once (with the scrap item they always deployed with) and sets it.
const BARE_KEY := "loadout_bare"


## The free scrap gear every player owns, one of each: the starter items
## that go in a loadout slot. Equipped like stash gear, but never taken from
## or put in a stash.
static func free_items() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "starter") and Loadout.slot_of(id) != "":
			out.append(id)
	return out


## True if `id` is free scrap gear (see `free_items`).
static func is_free(id: Variant) -> bool:
	return typeof(id) == TYPE_STRING and ItemDB.has_item(id) and ItemDB.has_tag(id, "starter") \
			and Loadout.slot_of(id) != ""


## What a player can equip from: the stash plus one of each free item.
static func equippable(stash: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(stash)
	for id in free_items():
		if id not in out:
			out.append(id)
	return out


## The loadout a player with nothing chosen yet starts in: the free scrap
## piece in each slot that has one.
static func starter_loadout() -> Dictionary:
	var out := {}
	for id in free_items():
		var slot := Loadout.slot_of(id)
		if not out.has(slot):
			out[slot] = id
	return out


## Brings a loadout saved before the bare rule up to it: every empty slot
## that used to deploy its free scrap item gets that item equipped, so
## nobody loses what they were wearing. Does nothing to a save that already
## has `BARE_KEY`.
static func upgrade_loadout(data: Dictionary, loadout: Dictionary) -> void:
	if bool(data.get(BARE_KEY, false)):
		return
	var start := starter_loadout()
	for slot: String in start:
		if str(loadout.get(slot, "")) == "":
			loadout[slot] = start[slot]


## True if an item may be stored in a stash at all.
static func storable(id: Variant) -> bool:
	return typeof(id) == TYPE_STRING and ItemDB.has_item(id) and not ItemDB.has_tag(id, "starter") \
			and not ItemDB.has_tag(id, "power")


## Adds the storable items in `ids` to `stash`. Returns how many were added.
static func add_items(stash: Array[String], ids: Array) -> int:
	var added := 0
	for id: Variant in ids:
		if storable(id):
			stash.append(id)
			added += 1
	return added


## True if the stash item `id` can go in loadout slot `slot`.
## Free scrap gear always can.
static func can_equip(stash: Array[String], slot: String, id: String) -> bool:
	return (id in stash or is_free(id)) and Loadout.fits(slot, id)


## Drops loadout entries that are not a valid slot, or whose item is no longer
## in the stash. Gear that was lost (died with, sold) is replaced by the free
## scrap piece for its slot, if there is one: only taking something off on
## purpose leaves a slot bare. Returns true if anything changed.
static func validate_loadout(stash: Array[String], loadout: Dictionary) -> bool:
	var changed := false
	var start := starter_loadout()
	for slot: Variant in loadout.keys():
		var id: Variant = loadout[slot]
		if typeof(slot) != TYPE_STRING or typeof(id) != TYPE_STRING or not can_equip(stash, slot, id):
			loadout.erase(slot)
			changed = true
			if typeof(slot) == TYPE_STRING and typeof(id) == TYPE_STRING and ItemDB.has_item(id) \
					and Loadout.fits(slot, id) and start.has(slot):
				loadout[slot] = start[slot]
	return changed


## Takes the loadout out of `stash` for a raid and returns the full kit: the
## chosen gear (free scrap pieces cost nothing) and healing. An empty slot
## stays empty. With nothing at all the kit is `[Loadout.BARE]`, since an
## empty kit means the world's scrap kit to `Raid.add_player`.
## `taken` (if given) receives just the items that left the stash, which is
## what has to be returned if the deploy is called off.
static func checkout(stash: Array[String], loadout: Dictionary, world: WorldDef,
		taken: Array[String] = []) -> Array[String]:
	validate_loadout(stash, loadout)
	var starter := world.starter_loadout()
	var kit: Array[String] = []
	for slot: String in Loadout.SLOTS:
		var id: String = loadout.get(slot, "")
		if id == "":
			continue
		kit.append(id)
		if not is_free(id):
			stash.erase(id)
			taken.append(id)
	var heals := 0
	for id in stash.duplicate():
		if heals >= Loadout.MAX_HEAL_ITEMS:
			break
		if ItemDB.has_tag(id, "heal"):
			stash.erase(id)
			kit.append(id)
			taken.append(id)
			heals += 1
	if heals == 0:
		for free_id in starter:
			if ItemDB.has_tag(free_id, "heal"):
				kit.append(free_id)
				break
	if kit.is_empty():
		kit.append(Loadout.BARE)
	return kit
