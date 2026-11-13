extends RefCounted
## Blueprints and crafting (DESIGN.md section 10): what can be made at the
## gunsmith bench, from which blueprint, and what each craft costs. Shared by
## the local `Profile` and the server's `StashService`, so solo and online
## play follow the same rules. Pure functions on plain data, like `Economy`
## and `BaseUpgrades`: no files, no network.
##
## Load with `const Crafting := preload("res://core/progression/crafting.gd")`.
##
## How it works:
##   - A blueprint is an item tagged "blueprint". It is found out in a world
##     and is at stake like anything carried. Once it reaches a stash it is
##     learned (`learn`): its id moves to the account's list of known
##     blueprints, kept beside the stash and scrip, and is never lost. A
##     second copy of one already known stays in the stash as loot to sell.
##   - A recipe makes one item from a known blueprint. It costs scrip, parts
##     (materials from the stash) and, for a Mk2 or Mk3, upgrade data (the
##     item `UPGRADE_DATA`, kept in the stash once it is home).
##   - What is made is ordinary gear: it goes in the stash and is at stake in
##     the PvP world. The blueprint stays, so it can be made again.
##
## Every cost here is a placeholder until a playtest (DESIGN.md section 13).

const BLUEPRINT_TAG := "blueprint"
## The item a Mk2 or Mk3 craft spends, beside its parts.
const UPGRADE_DATA := "upgrade_data"

## What each craft of a tier costs in upgrade data and scrip. Mk1 crafts (a
## gun, a vehicle) take no data and name their own fee.
const TIER_DATA := {2: 3, 3: 6}
const TIER_SCRIP := {2: 400, 3: 900}

## Result item id -> its recipe:
##   blueprint  the blueprint item that must be known
##   tier       2 or 3 for a higher Mk (costs `TIER_DATA` and `TIER_SCRIP`)
##   scrip      the fee, for a recipe with no tier
##   parts      item id -> how many, taken from the stash
## Listed in the order the bench shows them.
const RECIPES := {
	"jetpack_mk2": {"blueprint": "bp_jetpack", "tier": 2, "parts": {"power_cell": 2, "alloy_ingot": 1}},
	"jetpack_mk3": {"blueprint": "bp_jetpack", "tier": 3, "parts": {"alloy_ingot": 2, "reactor_core": 1}},
	"boots_thruster_mk2": {"blueprint": "bp_boots_thruster", "tier": 2, "parts": {"power_cell": 2, "alloy_ingot": 1}},
	"boots_thruster_mk3": {"blueprint": "bp_boots_thruster", "tier": 3, "parts": {"alloy_ingot": 2, "reactor_core": 1}},
	"wings_glide_mk2": {"blueprint": "bp_wings_glide", "tier": 2, "parts": {"power_cell": 2, "alloy_ingot": 1}},
	"wings_glide_mk3": {"blueprint": "bp_wings_glide", "tier": 3, "parts": {"alloy_ingot": 2, "reactor_core": 1}},
	"dmr_longshot": {"blueprint": "bp_dmr_longshot", "scrip": 300, "parts": {"alloy_ingot": 1, "circuit_board": 2}},
	"shotgun_breacher": {"blueprint": "bp_shotgun_breacher", "scrip": 300, "parts": {"alloy_ingot": 1, "scrap_metal": 3}},
	"mech_bulwark": {"blueprint": "bp_mech_bulwark", "scrip": 2000,
		"parts": {"reactor_core": 1, "alloy_ingot": 3, "power_cell": 2}},
	"jet_kestrel": {"blueprint": "bp_jet_kestrel", "scrip": 2000,
		"parts": {"reactor_core": 1, "alloy_ingot": 2, "circuit_board": 4}},
}


## Every craftable item id, in the order the bench shows them.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in RECIPES:
		out.append(id)
	return out


static func has_recipe(id: String) -> bool:
	return RECIPES.has(id)


## The blueprint item a recipe needs, or "".
static func blueprint_of(id: String) -> String:
	return str(RECIPES[id]["blueprint"]) if RECIPES.has(id) else ""


## What a blueprint makes, in bench order.
static func made_from(blueprint: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in RECIPES:
		if RECIPES[id]["blueprint"] == blueprint:
			out.append(id)
	return out


## Every blueprint item id, in the order they were registered.
static func blueprints() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, BLUEPRINT_TAG):
			out.append(id)
	return out


## What one craft costs in scrip.
static func fee(id: String) -> int:
	if not RECIPES.has(id):
		return 0
	var recipe: Dictionary = RECIPES[id]
	return int(recipe.get("scrip", TIER_SCRIP.get(int(recipe.get("tier", 1)), 0)))


## What one craft takes out of the stash: item id -> how many, the upgrade
## data first.
static func needs(id: String) -> Dictionary:
	var out := {}
	if not RECIPES.has(id):
		return out
	var recipe: Dictionary = RECIPES[id]
	var data := int(TIER_DATA.get(int(recipe.get("tier", 1)), 0))
	if data > 0:
		out[UPGRADE_DATA] = data
	var parts: Dictionary = recipe.get("parts", {})
	for part: String in parts:
		out[part] = int(parts[part])
	return out


## A saved or sent list of known blueprints made safe: real blueprint ids
## only, each once, in registry order. Anything else gives none.
static func clean(saved: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(saved) != TYPE_ARRAY:
		return out
	for id in blueprints():
		if id in saved:
			out.append(id)
	return out


## Learns every blueprint in `stash` that `known` lacks: one copy leaves the
## stash and its id joins `known`. Copies of one already known stay as loot.
## Call it whenever items reach a stash. Returns the ids newly learned.
static func learn(stash: Array[String], known: Array[String]) -> Array[String]:
	var learned: Array[String] = []
	for id: String in stash.duplicate():
		if ItemDB.has_tag(id, BLUEPRINT_TAG) and id not in known:
			stash.erase(id)
			known.append(id)
			learned.append(id)
	if not learned.is_empty():
		# Kept in registry order, so two accounts that know the same match.
		var sorted := clean(known)
		known.clear()
		known.append_array(sorted)
	return learned


## Why `id` cannot be crafted from this stash, these known blueprints and
## this much scrip, or "" if it can.
static func blocked(stash: Array, known: Array, scrip: int, id: String) -> String:
	if not RECIPES.has(id):
		return "That cannot be crafted."
	if blueprint_of(id) not in known:
		return "Blueprint not found yet."
	var need := needs(id)
	for part: String in need:
		var short: int = need[part] - stash.count(part)
		if short > 0:
			return "Needs %d more %s." % [short, ItemDB.item_name(part)]
	if scrip < fee(id):
		return "Not enough scrip."
	return ""


## Crafts one `id` into `stash`, taking its parts and data out. Returns
## {"ok", "scrip", "spent", "made"} with the new balance, or
## {"ok": false, "error", "scrip"} with nothing changed.
static func craft(stash: Array[String], known: Array, scrip: int, id: String) -> Dictionary:
	var why := blocked(stash, known, scrip, id)
	if why != "":
		return {"ok": false, "error": why, "scrip": scrip}
	var need := needs(id)
	for part: String in need:
		for i in int(need[part]):
			stash.erase(part)
	stash.append(id)
	var cost := fee(id)
	return {"ok": true, "scrip": scrip - cost, "spent": cost, "made": id}
