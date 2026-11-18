extends RefCounted
## The safety nets (DESIGN.md section 10, "Safety nets"): salvage on loss and
## one insured item. Losses should sting without wiping out the work behind
## them. Shared by the local `Profile` and the server's `StashService`, so solo
## and online follow the same rules. Pure functions on plain data, like
## `Economy`: no files, no network.
##
## Salvage: a crafted item (one with a `Crafting` recipe) taken out of the
## stash and lost with the body pays back `SALVAGE_SHARE` of its recipe's
## parts, rarest parts first. Never the scrip fee or the upgrade data, and
## nothing for gear that was dropped or handed over before the death, or
## picked up in the world. The `Raid` decides what was lost
## (`Raid._finish_player`'s "salvaged" and "salvage").
##
## Insurance: one policy per account, on one item that goes in a loadout
## slot, paid up front (`premium`). An insured item on the body at a death is
## recalled home instead of dropping in the bag (`Raid._recall_insured`), so
## no second copy of anything is ever made. A claim ends the policy and the
## next one waits `COOLDOWN`. A policy whose item is no longer owned (sold,
## traded, lost uninsured) lapses with no wait (`lapse`).
##
## A policy is a dictionary: {"item": id or "", "ready_at": unix seconds}.
##
## Load with `const SafetyNets := preload("res://core/economy/safety_nets.gd")`.
##
## All the numbers are placeholders to tune by play (DESIGN.md section 13).

const Crafting := preload("res://core/progression/crafting.gd")

## The share of a lost crafted item's recipe parts that comes back.
const SALVAGE_SHARE := 0.4
## A policy costs this share of the item's value.
const PREMIUM_SHARE := 0.25
## Seconds after a claim before a new policy can be bought.
const COOLDOWN := 12.0 * 3600.0
## Loadout slots whose gear can never be insured: heavy weapons, artifacts
## and vehicles (vehicles ride the watch, and a heavy or an artifact is a
## prize of the war that must stay at stake).
const UNINSURABLE_SLOTS: Array[String] = ["power", "artifact", "vehicle"]


# --- Salvage -----------------------------------------------------------------

## True if losing `id` pays salvage: it has a fabricator recipe.
static func salvages(id: String) -> bool:
	return Crafting.has_recipe(id)


## The parts losing one `id` pays back, rarest first: each part's count times
## the share, rounded down, then made up to the share of the whole recipe
## (rounded, at least one part) from the rarest parts. Empty for anything
## without a recipe.
static func salvage_of(id: String) -> Array[String]:
	var out: Array[String] = []
	if not salvages(id):
		return out
	var parts: Dictionary = Crafting.RECIPES[id].get("parts", {})
	var total := 0
	for part: String in parts:
		total += int(parts[part])
	if total <= 0:
		return out
	var due := maxi(1, roundi(total * SALVAGE_SHARE))
	var rarest := _rarest_first(parts.keys())
	var left := {}
	for part: String in rarest:
		var whole := floori(int(parts[part]) * SALVAGE_SHARE)
		for i in whole:
			out.append(part)
		left[part] = int(parts[part]) - whole
	while out.size() < due:
		var added := false
		for part: String in rarest:
			if out.size() >= due:
				break
			if int(left[part]) > 0:
				out.append(part)
				left[part] = int(left[part]) - 1
				added = true
		if not added:
			break
	return _rarest_first(out)


## The parts paid for every item in `ids`.
static func salvage_all(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in ids:
		if typeof(id) == TYPE_STRING:
			out.append_array(salvage_of(id))
	return out


static func _rarest_first(ids: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(ids)
	out.sort_custom(func(a: String, b: String) -> bool:
		var va := ItemDB.item_value(a)
		var vb := ItemDB.item_value(b)
		return va > vb if va != vb else a < b)
	return out


## "1 Reactor Core, 1 Engine Coil".
static func describe(parts: Array) -> String:
	var counts := {}
	var order: Array[String] = []
	for part: Variant in parts:
		var id := str(part)
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var bits: Array[String] = []
	for id in order:
		bits.append("%d %s" % [counts[id], ItemDB.item_name(id)])
	return ", ".join(bits)


# --- Insurance ---------------------------------------------------------------

## A fresh policy: nothing insured, no wait.
static func fresh() -> Dictionary:
	return {"item": "", "ready_at": 0.0}


## A saved or sent policy made safe.
static func clean(saved: Variant) -> Dictionary:
	var policy := fresh()
	if typeof(saved) != TYPE_DICTIONARY:
		return policy
	var item := str(saved.get("item", ""))
	policy.item = item if insurable(item) else ""
	policy.ready_at = maxf(0.0, float(saved.get("ready_at", 0.0)))
	return policy


## True if `id` may be insured: gear that goes in a loadout slot, not the
## free scrap kit, and not a heavy weapon, an artifact or a vehicle.
static func insurable(id: String) -> bool:
	if id == "" or not ItemDB.has_item(id) or ItemDB.has_tag(id, "starter"):
		return false
	var slot := Loadout.slot_of(id)
	return slot != "" and slot not in UNINSURABLE_SLOTS and ItemDB.item_value(id) > 0


## What insuring `id` costs.
static func premium(id: String) -> int:
	return maxi(1, roundi(ItemDB.item_value(id) * PREMIUM_SHARE))


## Seconds until a new policy can be bought (0 when it can).
static func wait_left(policy: Dictionary, now: float) -> float:
	return maxf(0.0, float(policy.get("ready_at", 0.0)) - now)


## Ends the policy if its item is no longer owned (`owned`: the stash plus
## anything out on a deploy). No wait: nothing was claimed. True if it lapsed.
static func lapse(policy: Dictionary, owned: Array) -> bool:
	var item := str(policy.get("item", ""))
	if item == "" or item in owned:
		return false
	policy.item = ""
	return true


## Why `id` cannot be insured now, or "".
static func blocked(policy: Dictionary, owned: Array, scrip: int, id: String, now: float) -> String:
	if not insurable(id):
		return "That cannot be insured."
	if id not in owned:
		return "You do not own that."
	if str(policy.get("item", "")) != "":
		return "You already hold a policy. Cancel it first."
	if wait_left(policy, now) > 0.0:
		return "A new policy is ready in %s." % wait_text(wait_left(policy, now))
	if scrip < premium(id):
		return "Not enough scrip."
	return ""


## Insures `id`: takes the premium and starts the policy.
## Returns {"ok", "scrip"} and an "error" when refused, like `Economy.buy`.
static func insure(policy: Dictionary, owned: Array, scrip: int, id: String, now: float) -> Dictionary:
	var why := blocked(policy, owned, scrip, id, now)
	if why != "":
		return {"ok": false, "error": why, "scrip": scrip}
	policy.item = id
	return {"ok": true, "scrip": scrip - premium(id)}


## Ends the policy with no refund and no wait.
static func cancel(policy: Dictionary) -> Dictionary:
	if str(policy.get("item", "")) == "":
		return {"ok": false, "error": "No policy to cancel."}
	policy.item = ""
	return {"ok": true}


## The insured item if this deploy took it out of the stash, else "": only
## then may the `Raid` recall it.
static func covered(policy: Dictionary, taken: Array) -> String:
	var item := str(policy.get("item", ""))
	return item if item != "" and item in taken else ""


## A finished life recalled `recalled`: if it is the insured item the policy
## pays out, ends, and the next one waits `COOLDOWN`. True if it was claimed.
static func claim(policy: Dictionary, recalled: String, now: float) -> bool:
	if recalled == "" or str(policy.get("item", "")) != recalled:
		return false
	policy.item = ""
	policy.ready_at = now + COOLDOWN
	return true


## "11 h 20 min", "5 min".
static func wait_text(seconds: float) -> String:
	var minutes := ceili(seconds / 60.0)
	if minutes >= 60:
		return "%d h %d min" % [floori(minutes / 60.0), minutes % 60]
	return "%d min" % maxi(1, minutes)
