extends RefCounted
## The new player's tour: a handler who messages you on the phone, one step
## at a time, from putting on your first gear to banking your first loot.
## Pure rules on plain data, like `Contracts`: the state is a small
## dictionary kept in the local `Profile` (`Profile.onboarding`), and
## `main.gd` feeds it what the player just did (`notify`).
##
## Load with `const Onboarding := preload("res://core/progression/onboarding.gd")`.
##
## How it works:
##   - Every step finishes on the action itself (`STEPS[i].event`), never on
##     a button. `main.gd` reports actions as events, and also reports what
##     is already true when a step starts (gear on, a contract held, standing
##     in the plaza), so a step the player has already done passes at once.
##   - The handler's messages arrive in the phone's Messages app (offline
##     too), and the current step's short objective sits on the watch card
##     and the visor glass. There is no overlay (Caleb's immersion rule).
##   - It is a view of the player's own progress, never a rule of the game:
##     nothing is locked or handed out by it, and a server never reads it.
##   - The phone's Settings (System tab) skips it or plays it again.
##   - Dev mode never runs it (`main.gd` checks `DevMode.active()`).
##   - World names come from `Worlds`, by what each world is (the safe zone,
##     a world that keeps your gear on death, a full-loot world), never by id.

const HANDLER_ID := "handler"
const HANDLER_NAME := "Handler"

const ACTIVE := "active"
const SKIPPED := "skipped"
const DONE := "done"

## Events (`notify`):
##   equipped   a weapon is on the loadout
##   watch      the watch was raised
##   target     a plate or target was hit at home (test lane or range)
##   plaza      standing in the safe zone
##   contract   a contract is held
##   deployed   out in a world where gear is at risk
##   banked     loot banked at a depot, or a sign-out finished in a world
##
## Each step: "id", "event" that finishes it, "objective" (the short line on
## the watch and visor) and "message" (what the handler sends when it
## starts). `{plaza}`, `{gentle}` and `{harsh}` are filled with world names.
const STEPS: Array[Dictionary] = [
	{"id": "gear", "event": "equipped",
		"objective": "Put on your gear in the armory",
		"message": "Welcome home, recruit. I'm your handler, and I'll walk you through the basics. "
			+ "You've got nothing on yet. Your welcome crate is in the armory: walk up to the rifle on the rack "
			+ "and use it to put it on. The frame on its stand and the helmet shelf work the same way."},
	{"id": "watch", "event": "watch",
		"objective": "Raise your watch",
		"message": "Good, you're armed. Everything you do out there runs through your watch. "
			+ "Raise it with {watch_key}. Its Summon tab holds your weapons and your bike."},
	{"id": "lane", "event": "target",
		"objective": "Hit a plate on the test lane",
		"message": "Now try that weapon. The door in the back wall opens on your test lane. "
			+ "Draw your gun with {primary_key} and hit one of the plates. Nothing in here is real damage."},
	{"id": "plaza", "event": "plaza",
		"objective": "Head out to {plaza}",
		"message": "Nice shooting. Time to meet people. The exit by the mirror goes out to {plaza}, "
			+ "where everyone on the server gathers."},
	{"id": "contract", "event": "contract",
		"objective": "Take a job at the contract board",
		"message": "This is {plaza}. Find the contract board and take a job. "
			+ "Jobs pay scrip when you get home alive."},
	{"id": "deploy", "event": "deployed",
		"objective": "Go to {gentle}",
		"message": "Start in {gentle}. It's the place to learn: if you die there you keep the gear you wore, "
			+ "and only your pack is lost. Walk through its gate, or open a portal from your watch."},
	{"id": "bank", "event": "banked",
		"objective": "Bank your loot at a depot",
		"message": "You're in. Grab what you can, then stand in a depot to bank it, "
			+ "or sign out at a gate outpost. Either way it goes home to your stash."},
]

## Sent when the last step is done.
const DONE_MESSAGE := ("That's the basics, and it's all yours now. {harsh} is open to you, but be warned: "
		+ "it's full loot. Die there and everything you carried stays behind. Good luck out there.")
## Sent when the tour is skipped.
const SKIP_MESSAGE := "Understood, you're on your own. If you want the tour again, it's in Settings."


## A fresh tour, for a new player.
static func fresh() -> Dictionary:
	return {"state": ACTIVE, "step": STEPS[0].id}


## A tour that will not start, for a player who already knows the game.
static func finished() -> Dictionary:
	return {"state": DONE, "step": ""}


## A saved tour, checked: anything unreadable is a finished one, so an odd
## save never sends a veteran back through it.
static func clean(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return finished()
	var state := str(raw.get("state", ""))
	if state == ACTIVE and index_of(str(raw.get("step", ""))) >= 0:
		return {"state": ACTIVE, "step": str(raw.step)}
	if state == SKIPPED:
		return {"state": SKIPPED, "step": ""}
	return finished()


static func index_of(step_id: String) -> int:
	for i in STEPS.size():
		if STEPS[i].id == step_id:
			return i
	return -1


static func is_active(tour: Dictionary) -> bool:
	return tour.get("state", "") == ACTIVE and index_of(str(tour.get("step", ""))) >= 0


## The step being worked on, or {} when the tour is not running.
static func current(tour: Dictionary) -> Dictionary:
	return STEPS[index_of(tour.step)] if is_active(tour) else {}


## The player did `event`. Finishes the current step if it was waiting for
## it and moves to the next (or ends the tour). Returns true if it moved.
static func notify(tour: Dictionary, event: String) -> bool:
	var step := current(tour)
	if step.is_empty() or step.event != event:
		return false
	var next := index_of(step.id) + 1
	if next >= STEPS.size():
		tour.state = DONE
		tour.step = ""
	else:
		tour.step = STEPS[next].id
	return true


static func skip(tour: Dictionary) -> void:
	tour.state = SKIPPED
	tour.step = ""


static func restart(tour: Dictionary) -> void:
	tour.state = ACTIVE
	tour.step = STEPS[0].id


## The handler's messages so far, oldest first: one for each step reached
## while the tour runs. The ending (`DONE_MESSAGE`, `SKIP_MESSAGE`) is sent
## live by `main.gd` and not kept. `p_names` fills the names (see `names`).
static func messages(tour: Dictionary, p_names: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if is_active(tour):
		for i in index_of(tour.step) + 1:
			out.append(fill(STEPS[i].message, p_names))
	return out


## The objective line for the watch and visor, or "" when none.
static func objective(tour: Dictionary, p_names: Dictionary) -> String:
	var step := current(tour)
	return fill(step.objective, p_names) if not step.is_empty() else ""


static func fill(text: String, p_names: Dictionary) -> String:
	return text.format(p_names)


## The names a message can use, from the worlds this game has and the keys
## the player has bound: the safe zone, the first world that keeps gear on
## death (else the first raid world), the first full-loot world (else the
## first raid world), and the watch and primary weapon keys.
static func names(watch_key := "X", primary_key := "1") -> Dictionary:
	var plaza := Worlds.social_world()
	var raids := Worlds.raid_worlds()
	var gentle: WorldDef = raids[0] if not raids.is_empty() else null
	var harsh: WorldDef = gentle
	for world in raids:
		if world.keep_gear_on_death:
			gentle = world
			break
	for world in raids:
		if world.gear_at_risk and not world.keep_gear_on_death:
			harsh = world
			break
	return {
		"plaza": plaza.display_name if plaza != null else "the plaza",
		"gentle": gentle.display_name if gentle != null else "a world",
		"harsh": harsh.display_name if harsh != null else "the full-loot world",
		"watch_key": watch_key,
		"primary_key": primary_key,
	}
