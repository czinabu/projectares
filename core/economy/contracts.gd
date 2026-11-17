extends RefCounted
## The contract rules (DESIGN.md section 10, "Contracts and bounties"): the
## jobs on the hub's contract board, which ones are on offer today, taking,
## dropping and rerolling them, and how a finished life counts toward them.
## Shared by the local `Profile` and the server's `StashService`, like
## `Economy`: pure functions on plain data, no files, no network.
##
## Load with `const Contracts := preload("res://core/economy/contracts.gd")`.
##
## How contracts work:
##   - The board offers `DAILY_OFFERS` daily jobs and `WEEKLY_OFFERS` weekly
##     ones, picked from the pools below by the day (UTC) and the week, so
##     everyone sees the same board. You hold up to `MAX_ACTIVE` at a time.
##   - Progress counts only when you sign out alive (outcome "left"), so the
##     risk still matters. A death counts nothing.
##   - Counters come from the life's `tally` (kills, warlords, strongpoints,
##     vehicles ridden, artifact uses: `Raid._count`) and from what came home
##     (loot value, items by tag).
##   - A finished contract pays at once, into the account: scrip, plus any
##     reward items that exist (`items`), plus one item with `reward_tag` the
##     account does not know yet (a blueprint, once those exist).
##   - One reroll of the daily offers a day. A daily job expires at the end
##     of its day, a weekly one at the end of its week, done or not.
##   - Jobs push variety and never reward camping or farming new players:
##     nothing counts player kills, and an extract only counts with real loot.

## How many jobs you hold at once.
const MAX_ACTIVE := 3
const DAILY_OFFERS := 3
const WEEKLY_OFFERS := 1
## A sign-out only counts as an extract for a contract with at least this much
## loot home (carried out plus banked), so signing straight out farms nothing.
const EXTRACT_MIN_VALUE := 100
## Seconds in a day. Days are counted from the Unix epoch, in UTC.
const DAY := 86400

## The jobs. Each: "title" (what the board says), "stat" (what counts, see
## `amount`), "goal", "kind" ("daily" or "weekly"), "scrip" paid on finishing,
## and optionally "items" (item ids paid if they exist) and "reward_tag" (one
## item with that tag). Stats:
##   kills         enemies killed (bots, warlords and players alike)
##   warlords      warlords killed
##   strongpoints  strongpoints taken while standing in them
##   rides         vehicles ridden (each vehicle once a life)
##   artifacts     artifact uses
##   extracts      sign-outs with at least EXTRACT_MIN_VALUE of loot home
##   loot_value    the value of loot carried out and banked
##   carry:<tag>   items with that tag carried out and banked
const JOBS := {
	"cull": {"title": "Kill 8 enemies", "stat": "kills", "goal": 8, "kind": "daily", "scrip": 150},
	"warlord": {"title": "Take down a warlord", "stat": "warlords", "goal": 1, "kind": "daily", "scrip": 300,
			"items": ["upgrade_data"]},
	"sites": {"title": "Take 2 strongpoints", "stat": "strongpoints", "goal": 2, "kind": "daily", "scrip": 200,
			"items": ["upgrade_data"]},
	"ride": {"title": "Ride 2 vehicles", "stat": "rides", "goal": 2, "kind": "daily", "scrip": 120},
	"relic": {"title": "Use an artifact 2 times", "stat": "artifacts", "goal": 2, "kind": "daily", "scrip": 180},
	"haul": {"title": "Bring home 600 scrip of loot", "stat": "loot_value", "goal": 600, "kind": "daily", "scrip": 150},
	"salvage": {"title": "Bring home 4 materials", "stat": "carry:material", "goal": 4, "kind": "daily", "scrip": 140},
	"extract": {"title": "Sign out with loot 2 times", "stat": "extracts", "goal": 2, "kind": "daily", "scrip": 120},
	"veteran": {"title": "Sign out with loot 8 times", "stat": "extracts", "goal": 8, "kind": "weekly", "scrip": 700,
			"items": ["upgrade_data"], "reward_tag": "blueprint"},
	"warmonger": {"title": "Kill 50 enemies", "stat": "kills", "goal": 50, "kind": "weekly", "scrip": 800,
			"items": ["upgrade_data"], "reward_tag": "blueprint"},
	"tyrant": {"title": "Take down 3 warlords", "stat": "warlords", "goal": 3, "kind": "weekly", "scrip": 900,
			"items": ["upgrade_data"], "reward_tag": "blueprint"},
	"hoard": {"title": "Bring home 4000 scrip of loot", "stat": "loot_value", "goal": 4000, "kind": "weekly",
			"scrip": 750, "items": ["upgrade_data"], "reward_tag": "blueprint"},
}


## Today, as a day number (UTC days since the epoch). `unix` is seconds; pass
## one in tests, leave it out for now.
static func today(unix: float = -1.0) -> int:
	if unix < 0.0:
		unix = Time.get_unix_time_from_system()
	return int(floor(unix / DAY))


## The week a day falls in. Weeks start on Monday (the epoch was a Thursday).
static func week_of(day: int) -> int:
	return int(floor((day + 3) / 7.0))


static func job(id: String) -> Dictionary:
	return JOBS.get(id, {})


static func ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in JOBS:
		if JOBS[id].kind == kind:
			out.append(id)
	return out


## The jobs on offer on `day`: the dailies then the weeklies. `reroll` > 0
## picks a fresh set of dailies, avoiding `avoid` where it can.
static func offers_for(day: int, reroll := 0, avoid: Array = []) -> Array[String]:
	var out: Array[String] = _pick(ids("daily"), DAILY_OFFERS, hash(["daily", day, reroll]), avoid)
	out.append_array(_pick(ids("weekly"), WEEKLY_OFFERS, hash(["weekly", week_of(day)]), []))
	return out


static func _pick(pool: Array[String], count: int, seed_value: int, avoid: Array) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fresh := pool.filter(func(id: String) -> bool: return id not in avoid)
	var rest := pool.filter(func(id: String) -> bool: return id in avoid)
	var out: Array[String] = []
	for list: Array in [fresh, rest]:
		while not list.is_empty() and out.size() < count:
			out.append(list.pop_at(rng.randi_range(0, list.size() - 1)))
	return out


## A clean contract state from a save (or nothing), brought up to `day`.
## {"day", "offers": [ids], "active": [{"id", "have", "day"}], "done": [ids],
## "rerolled": bool}. An active job keeps the day it was taken, which is how
## it expires.
static func clean(saved: Variant, day: int) -> Dictionary:
	var state := {"day": day, "offers": offers_for(day), "active": [], "done": [], "rerolled": false}
	if typeof(saved) != TYPE_DICTIONARY:
		return state
	var old_day := int(saved.get("day", day))
	for entry: Variant in saved.get("active", []):
		if typeof(entry) != TYPE_DICTIONARY or not JOBS.has(str(entry.get("id", ""))):
			continue
		var id := str(entry.id)
		if state.active.size() < MAX_ACTIVE and not state.active.any(func(a: Dictionary) -> bool: return a.id == id):
			state.active.append({"id": id, "have": maxi(0, int(entry.get("have", 0))),
					"day": int(entry.get("day", old_day))})
	for id: Variant in saved.get("done", []):
		if typeof(id) == TYPE_STRING and JOBS.has(id) and id not in state.done:
			state.done.append(id)
	if old_day == day:
		state.rerolled = bool(saved.get("rerolled", false))
		var offers: Array[String] = []
		for id: Variant in saved.get("offers", []):
			if typeof(id) == TYPE_STRING and JOBS.has(id) and id not in offers:
				offers.append(id)
		if not offers.is_empty():
			state.offers = offers
		state.day = old_day
	return refresh(state, day)


## Moves a state on to `day`: expired jobs drop off, and a new day brings new
## offers and a fresh reroll. Returns the same dictionary.
static func refresh(state: Dictionary, day: int) -> Dictionary:
	state.active = state.active.filter(func(entry: Dictionary) -> bool: return not expired(entry, day))
	if int(state.day) != day:
		var new_week := week_of(int(state.day)) != week_of(day)
		state.done = state.done.filter(func(id: String) -> bool:
			return job(id).kind == "weekly" and not new_week)
		state.day = day
		state.offers = offers_for(day)
		state.rerolled = false
	return state


## True once an active job's time is up: a daily after its day, a weekly
## after its week.
static func expired(entry: Dictionary, day: int) -> bool:
	var taken := int(entry.get("day", day))
	if job(entry.get("id", "")).get("kind", "daily") == "weekly":
		return week_of(taken) != week_of(day)
	return taken != day


## Takes a job off the board. Returns {"ok"} or {"ok": false, "error"}.
static func take(state: Dictionary, id: String, day: int) -> Dictionary:
	refresh(state, day)
	if id not in state.offers:
		return _fail("That contract is not on the board.")
	if id in state.done:
		return _fail("You already finished that one.")
	if state.active.any(func(entry: Dictionary) -> bool: return entry.id == id):
		return _fail("You already hold that contract.")
	if state.active.size() >= MAX_ACTIVE:
		return _fail("You hold %d contracts already. Drop one first." % MAX_ACTIVE)
	state.active.append({"id": id, "have": 0, "day": day})
	return {"ok": true}


## Gives a job up, and its progress with it. It can be taken again.
static func drop(state: Dictionary, id: String, day: int) -> Dictionary:
	refresh(state, day)
	var before: int = state.active.size()
	state.active = state.active.filter(func(entry: Dictionary) -> bool: return entry.id != id)
	return {"ok": true} if state.active.size() < before else _fail("You do not hold that contract.")


## Swaps today's daily offers for another set, once a day. Jobs you hold
## stay yours.
static func reroll(state: Dictionary, day: int) -> Dictionary:
	refresh(state, day)
	if state.rerolled:
		return _fail("The board rerolls once a day.")
	var old_dailies: Array = state.offers.filter(func(id: String) -> bool: return job(id).kind == "daily")
	var fresh := offers_for(day, 1, old_dailies)
	state.offers = fresh
	state.rerolled = true
	return {"ok": true}


## What a finished life adds to a stat (see `JOBS`). `result` is a raid's
## `player_finished` dictionary from the authority.
static func amount(stat: String, result: Dictionary) -> int:
	if result.get("outcome", "") != "left":
		return 0
	var home: Array = []
	for key: String in ["loot", "banked"]:
		var list: Variant = result.get(key, [])
		if typeof(list) == TYPE_ARRAY:
			home.append_array(list)
	match stat:
		"extracts":
			return 1 if ItemDB.total_value(home) >= EXTRACT_MIN_VALUE else 0
		"loot_value":
			return maxi(0, ItemDB.total_value(home))
	if stat.begins_with("carry:"):
		var tag := stat.trim_prefix("carry:")
		return home.filter(func(id: Variant) -> bool:
			return typeof(id) == TYPE_STRING and ItemDB.has_tag(id, tag)).size()
	var tally: Variant = result.get("tally", {})
	return maxi(0, int(tally.get(stat, 0))) if typeof(tally) == TYPE_DICTIONARY else 0


## What a job shows this life before it is counted: `tally` is the life's
## counters so far (`Actor.tally`). Only the tally's stats can be shown live.
static func live(stat: String, tally: Dictionary) -> int:
	return maxi(0, int(tally.get(stat, 0)))


## Counts a finished life toward the jobs held, and finishes the ones that
## reach their goal. `known` lists items the account already has for good
## (learned blueprints), so a reward tag skips them. Returns {"scrip": paid,
## "items": [granted ids], "finished": [titles]}; the caller pays them.
static func settle(state: Dictionary, result: Dictionary, day: int, known: Array = []) -> Dictionary:
	refresh(state, day)
	var out := {"scrip": 0, "items": [], "finished": []}
	if result.get("outcome", "") != "left":
		return out
	var still: Array = []
	for entry: Dictionary in state.active:
		var info := job(entry.id)
		entry.have = mini(int(entry.have) + amount(info.stat, result), int(info.goal))
		if entry.have < int(info.goal):
			still.append(entry)
			continue
		out.scrip += int(info.get("scrip", 0))
		for id: Variant in info.get("items", []):
			if typeof(id) == TYPE_STRING and ItemDB.has_item(id):
				out.items.append(id)
		var tagged := reward_for(str(info.get("reward_tag", "")), hash([entry.id, day]), known)
		if tagged != "":
			out.items.append(tagged)
		out.finished.append(info.title)
		state.done.append(entry.id)
	state.active = still
	return out


## One item with `tag` that is not in `known`, picked by `seed_value`, or "".
static func reward_for(tag: String, seed_value: int, known: Array = []) -> String:
	if tag == "":
		return ""
	var pool: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, tag) and id not in known:
			pool.append(id)
	if pool.is_empty():
		return ""
	pool.sort()
	return pool[posmod(seed_value, pool.size())]


## What the reward of a job reads as: "300 scrip + Upgrade data".
static func reward_text(id: String) -> String:
	var info := job(id)
	var parts: Array[String] = ["%d scrip" % int(info.get("scrip", 0))]
	for item: Variant in info.get("items", []):
		if typeof(item) == TYPE_STRING and ItemDB.has_item(item):
			parts.append(ItemDB.item_name(item))
	var tag := str(info.get("reward_tag", ""))
	if tag != "" and ItemDB.all_ids().any(func(item: String) -> bool: return ItemDB.has_tag(item, tag)):
		parts.append("a %s" % tag)
	return " + ".join(parts)


## The jobs held, for views: [{"id", "title", "have", "goal", "stat"}].
static func held(state: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(state) != TYPE_DICTIONARY:
		return out
	for entry: Variant in state.get("active", []):
		if typeof(entry) != TYPE_DICTIONARY or not JOBS.has(str(entry.get("id", ""))):
			continue
		var info := job(entry.id)
		out.append({"id": entry.id, "title": info.title, "have": int(entry.get("have", 0)),
				"goal": int(info.goal), "stat": info.stat})
	return out


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
