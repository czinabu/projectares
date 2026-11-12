extends RefCounted
## Decides what a home base puts on show: which stash items go on which rack,
## stand, bay or shelf. Pure functions on plain data (a stash and a loadout),
## so the same plan works for the local `Profile` and for the account a
## server keeps, and can be checked without building the room.
##
## Load with `preload("res://core/base/base_layout.gd")`.
##
## The base adds no storage of its own. It is a view of the stash: an item is
## on show because it is in the stash, and it leaves the room when it leaves
## the stash (deployed and lost, for example).

## Display kinds, in the order the room is planned. Each entry: the item tag
## that puts an item there, how many spots the room has, and whether every
## copy gets its own spot (vehicles) or copies share one with a count.
const KINDS := {
	"gun_rack": {"tag": "firearm", "spots": 8, "per_copy": false, "title": "Gun rack"},
	"blade_wall": {"tag": "melee", "spots": 6, "per_copy": false, "title": "Blade wall"},
	"armor_stand": {"tag": "armor", "spots": 6, "per_copy": false, "title": "Armor stands"},
	"rig_stand": {"tag": "flight_rig", "spots": 4, "per_copy": false, "title": "Flight rigs"},
	"chip_case": {"tag": "ability", "spots": 6, "per_copy": false, "title": "Ability chips"},
	"bay": {"tag": "vehicle", "spots": 4, "per_copy": true, "title": "Garage"},
	"supplies": {"tag": "consumable", "spots": 6, "per_copy": false, "title": "Supplies"},
	# Anything else worth keeping: materials, relics, augments.
	"trophy": {"tag": "", "spots": 8, "per_copy": false, "title": "Trophy shelf"},
}


## The display kind an item belongs to, by its tags.
static func kind_for(id: String) -> String:
	for kind: String in KINDS:
		var tag: String = KINDS[kind]["tag"]
		if tag != "" and ItemDB.has_tag(id, tag):
			return kind
	return "trophy"


## The loadout slot an item can be equipped in, or "" if it is not gear.
static func slot_for(id: String) -> String:
	for slot: String in Loadout.SLOTS:
		if Loadout.fits(slot, id):
			return slot
	return ""


## Plans the room. Returns one Dictionary per filled spot:
##   id        the item on show
##   kind      a key of KINDS
##   index     which spot of that kind, from 0
##   count     how many copies the stash holds
##   slot      the loadout slot it fits, or ""
##   equipped  true if it is in the loadout right now
## Within a kind the most valuable items get the first spots. Items that do
## not fit are left in storage: see `stored_away`.
static func plan(stash: Array, loadout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by_kind := _sorted_by_kind(stash)
	for kind: String in KINDS:
		var ids: Array = by_kind.get(kind, [])
		var spots: int = KINDS[kind]["spots"]
		# Only one copy can be equipped, so only the first spot shows it.
		var marked := {}
		for i in mini(ids.size(), spots):
			var id: String = ids[i]
			var slot := slot_for(id)
			var worn: bool = slot != "" and loadout.get(slot, "") == id and not marked.has(id)
			if worn:
				marked[id] = true
			out.append({
				"id": id,
				"kind": kind,
				"index": i,
				"count": stash.count(id),
				"slot": slot,
				"equipped": worn,
			})
	return out


## How many items of each kind are owned but have no free spot: kind -> count.
## Copies that share a spot are on show, so they are not counted.
static func stored_away(stash: Array) -> Dictionary:
	var out := {}
	var by_kind := _sorted_by_kind(stash)
	for kind: String in by_kind:
		var extra: int = by_kind[kind].size() - int(KINDS[kind]["spots"])
		if extra > 0:
			out[kind] = extra
	return out


## kind -> the ids that want a spot there, most valuable first. One entry per
## distinct item, or per copy for kinds that park every copy.
static func _sorted_by_kind(stash: Array) -> Dictionary:
	var out := {}
	for id: Variant in stash:
		if typeof(id) != TYPE_STRING or not ItemDB.has_item(id):
			continue
		var kind := kind_for(id)
		if not out.has(kind):
			out[kind] = []
		if KINDS[kind]["per_copy"] or id not in out[kind]:
			out[kind].append(id)
	for kind: String in out:
		out[kind].sort_custom(func(a: String, b: String) -> bool:
			if ItemDB.item_value(a) != ItemDB.item_value(b):
				return ItemDB.item_value(a) > ItemDB.item_value(b)
			return a < b)
	return out
