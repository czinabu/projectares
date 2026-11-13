extends RefCounted
## The home base upgrades: what can be bought, what each costs and what it
## needs first. Shared by the local `Profile` and the server's `StashService`,
## so solo and online play follow the same rules. Pure functions on plain
## data, like `Economy` and `StashRules`: no files, no network.
##
## Load with `const BaseUpgrades := preload("res://core/base/base_upgrades.gd")`.
##
## An account keeps a list of the upgrade ids it owns, beside its stash and
## scrip (never in the stash: an upgrade is not an item and is never lost).
## A base with no upgrades is the starter bunker. Upgrades never add combat
## power or storage: they add room to show gear, convenience and places to
## show off. `BaseLayout` reads the list for how many spots each display kind
## has, and `HomeBase` for which rooms exist.
##
## Prices are placeholders until a playtest measures scrip per life.

## Upgrade id -> its entry, in the order the tracks are listed:
##   title        the name on its bulkhead
##   track        which of the five tracks it belongs to
##   price        scrip, paid once
##   needs        upgrade ids that must be owned first
##   needs_count  how many upgrades (any) must be owned first
##   adds         one line on what it adds, for its price panel
##   ready        false while what is behind it is not built: it is shown
##                sealed and cannot be bought yet
const UPGRADES := {
	"armory_alcove": {"title": "Armory alcove", "track": "Armory", "price": 1200,
		"adds": "The nook opens into the full armory:\n12 long guns, 8 sidearms, 6 melee"},
	"heavy_wall": {"title": "Heavy weapon wall", "track": "Armory", "price": 4000, "needs": ["armory_alcove"],
		"adds": "Banked heavy weapons hang here", "ready": false},
	"bay_second": {"title": "Second bay", "track": "Garage", "price": 600,
		"adds": "Room for 2 vehicles on show"},
	"garage_full": {"title": "Full garage", "track": "Garage", "price": 2000, "needs": ["bay_second"],
		"adds": "4 bays and a lift that turns\nyour best vehicle"},
	"bench_workshop": {"title": "Workshop bench", "track": "Gunsmith", "price": 3000, "needs": ["armory_alcove"],
		"adds": "A bigger pegboard: 12 attachments"},
	"bench_master": {"title": "Master bench", "track": "Gunsmith", "price": 8000, "needs": ["bench_workshop"],
		"adds": "A master gunsmith's bench"},
	"gear_hall": {"title": "Gear hall", "track": "Halls", "price": 1000,
		"adds": "6 armor stands, 4 rig stands\nand the ability chip case"},
	"trophy_hall": {"title": "Trophy hall", "track": "Halls", "price": 1500,
		"adds": "The trophy shelf for relics and loot,\nand a full supplies shelf"},
	"lounge": {"title": "Lounge", "track": "Halls", "price": 800,
		"adds": "Room for furniture and decor", "ready": false},
	"ops_consoles": {"title": "Ops consoles", "track": "Headquarters", "price": 500,
		"adds": "The mastery bench and records\nget consoles of their own"},
	"firing_range": {"title": "Firing range", "track": "Headquarters", "price": 2500,
		"adds": "Targets to shoot at with endless ammo.\nNothing there is lost"},
	"teleporter": {"title": "Squad teleporter pad", "track": "Headquarters", "price": 5000, "needs": ["ops_consoles"],
		"adds": "Squadmates visit and launch together", "ready": false},
	"finish": {"title": "Finish", "track": "Headquarters", "price": 1500, "needs_count": 4,
		"adds": "Wall panels, lighting and trim"},
}


## Every upgrade id, in catalog order.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in UPGRADES:
		out.append(id)
	return out


static func has_upgrade(id: String) -> bool:
	return UPGRADES.has(id)


static func title(id: String) -> String:
	return str(UPGRADES[id]["title"]) if UPGRADES.has(id) else id


static func price(id: String) -> int:
	return int(UPGRADES[id]["price"]) if UPGRADES.has(id) else 0


static func adds(id: String) -> String:
	return str(UPGRADES[id].get("adds", "")) if UPGRADES.has(id) else ""


## False while what the upgrade opens is not built yet.
static func is_ready(id: String) -> bool:
	return UPGRADES.has(id) and bool(UPGRADES[id].get("ready", true))


## Every upgrade that can be bought today: the finished base.
static func full() -> Array[String]:
	var out: Array[String] = []
	for id: String in UPGRADES:
		if is_ready(id):
			out.append(id)
	return out


## A saved or sent list made safe: known ids only, each once, in catalog
## order. Anything else (a save from before upgrades existed, junk) gives the
## starter bunker.
static func clean(saved: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(saved) != TYPE_ARRAY:
		return out
	for id: String in UPGRADES:
		if id in saved:
			out.append(id)
	return out


## Why `id` cannot be bought by someone who owns `owned`, leaving money
## aside, or "" if it can.
static func blocked(owned: Array, id: String) -> String:
	if not UPGRADES.has(id):
		return "No such upgrade."
	if id in owned:
		return "You already own that."
	if not is_ready(id):
		return "Not open yet."
	for need: String in UPGRADES[id].get("needs", []):
		if need not in owned:
			return "Needs the %s first." % title(need).to_lower()
	var count := int(UPGRADES[id].get("needs_count", 0))
	if owned.size() < count:
		return "Needs any %d upgrades first." % count
	return ""


## Buys one upgrade into `owned`. Returns {"ok", "scrip", "spent"} with the
## new balance, or {"ok": false, "error", "scrip"} with nothing changed.
static func buy(owned: Array[String], scrip: int, id: String) -> Dictionary:
	var why := blocked(owned, id)
	if why != "":
		return {"ok": false, "error": why, "scrip": scrip}
	var cost := price(id)
	if scrip < cost:
		return {"ok": false, "error": "Not enough scrip.", "scrip": scrip}
	owned.append(id)
	# Kept in catalog order, so two accounts with the same upgrades match.
	var sorted := clean(owned)
	owned.clear()
	owned.append_array(sorted)
	return {"ok": true, "scrip": scrip - cost, "spent": cost}


## What every upgrade costs together.
static func total_price() -> int:
	var total := 0
	for id: String in UPGRADES:
		total += price(id)
	return total
