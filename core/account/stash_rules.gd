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
## are free and never stored, and power weapons are raid-only.


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
static func can_equip(stash: Array[String], slot: String, id: String) -> bool:
	return id in stash and Loadout.fits(slot, id)


## Drops loadout entries that are not a valid slot, or whose item is no longer
## in the stash. Returns true if anything changed.
static func validate_loadout(stash: Array[String], loadout: Dictionary) -> bool:
	var changed := false
	for slot: Variant in loadout.keys():
		var id: Variant = loadout[slot]
		if typeof(slot) != TYPE_STRING or typeof(id) != TYPE_STRING or not can_equip(stash, slot, id):
			loadout.erase(slot)
			changed = true
	return changed


## Takes the loadout out of `stash` for a raid and returns the full kit: the
## chosen gear, the world's free scrap item for every empty slot, and healing.
## `taken` (if given) receives just the items that left the stash, which is
## what has to be returned if the deploy is called off.
static func checkout(stash: Array[String], loadout: Dictionary, world: WorldDef,
		taken: Array[String] = []) -> Array[String]:
	validate_loadout(stash, loadout)
	var starter := world.starter_loadout()
	var kit: Array[String] = []
	for slot: String in Loadout.SLOTS:
		var id: String = loadout.get(slot, "")
		if id != "":
			stash.erase(id)
			kit.append(id)
			taken.append(id)
			continue
		for free_id in starter:
			if Loadout.fits(slot, free_id):
				kit.append(free_id)
				break
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
	return kit
