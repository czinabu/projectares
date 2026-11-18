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
		"adds": "Banked heavy weapons hang above the long guns"},
	"bay_second": {"title": "Second bay", "track": "Garage", "price": 600,
		"adds": "Room for 2 vehicles on show"},
	"garage_full": {"title": "Full garage", "track": "Garage", "price": 2000, "needs": ["bay_second"],
		"adds": "4 bays and a lift that turns\nyour best vehicle"},
	"bench_workshop": {"title": "Workshop bench", "track": "Gunsmith", "price": 3000, "needs": ["armory_alcove"],
		"adds": "A bigger bench: a parts cabinet\nand a second lamp"},
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
	"finish": {"title": "Finish", "track": "Headquarters", "price": 1500, "needs_count": 4,
		"adds": "Wall panels, lighting and trim"},
	# Designs (`BasePlan.SHAPES` and `STYLES`): another hub shape or another
	# style for a room, bought at the plan table and free to switch to after.
	"hub_ring": {"title": "Ring hub", "track": "Designs", "price": 4000,
		"adds": "An eight-sided rotunda round the plan table"},
	"hub_spine": {"title": "Spine hub", "track": "Designs", "price": 3000,
		"adds": "A long gallery, three rooms down each side"},
	"hub_courtyard": {"title": "Courtyard hub", "track": "Designs", "price": 6000,
		"adds": "A big lit court under a skylight"},
	"style_armory_vault": {"title": "Vault armory", "track": "Designs", "price": 1500,
		"adds": "A double-sided island rack"},
	"style_armory_gallery": {"title": "Gallery armory", "track": "Designs", "price": 2000,
		"adds": "Long guns in lit cases"},
	"style_workshop_island": {"title": "Island workshop", "track": "Designs", "price": 1000,
		"adds": "The bench in the middle of the room"},
	"style_workshop_pit": {"title": "Pit workshop", "track": "Designs", "price": 1200,
		"adds": "A side bench by an inspection pit"},
	"style_garage_showroom": {"title": "Showroom garage", "track": "Designs", "price": 1800,
		"adds": "A turntable in the middle of the garage"},
	"style_garage_lift": {"title": "Lift rack garage", "track": "Designs", "price": 1500,
		"adds": "Vehicles parked over each other"},
	"style_ops_war_table": {"title": "War table ops", "track": "Designs", "price": 1500,
		"adds": "Consoles round a lit map table"},
	"style_ops_bridge": {"title": "Bridge ops", "track": "Designs", "price": 1500,
		"adds": "Consoles in a row under a wide screen"},
	"style_gear_ring": {"title": "Ring gear hall", "track": "Designs", "price": 1500,
		"adds": "Armor round a lit dais"},
	"style_gear_lockers": {"title": "Locker gear hall", "track": "Designs", "price": 1200,
		"adds": "A locker for each suit"},
	"style_stores_plinths": {"title": "Plinth stores", "track": "Designs", "price": 1000,
		"adds": "Trophies on lit plinths"},
	"style_stores_cargo": {"title": "Cargo stores", "track": "Designs", "price": 800,
		"adds": "Crate stacks and a pallet rack"},
}

## The track of the design unlocks: they change how the base looks, never
## what it holds, and never count toward an upgrade's `needs_count`.
const DESIGNS := "Designs"


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


## True for a design unlock (a hub shape or a room style, `BasePlan`).
static func is_design(id: String) -> bool:
	return UPGRADES.has(id) and str(UPGRADES[id].get("track", "")) == DESIGNS


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
	var built := owned.filter(func(other: Variant) -> bool: return not is_design(str(other)))
	if built.size() < count:
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
