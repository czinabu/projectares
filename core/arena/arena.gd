class_name Arena
extends Raid
## The gladiator arena: duels, tournaments, and a crowd that wagers on them.
##
## An `Arena` is a `Raid` in the arena venue (core/arena/arena_venue.gd), so a
## server runs it, replicates it and lag compensates it exactly like a raid.
## Like `Raid` it has no camera, HUD or input code and runs headless.
##
## Everyone arrives in the stands. Bouts run one at a time from a queue:
##   CALLING   the next bout is announced and the crowd places wagers
##   COUNTDOWN the two fighters are in the pit at their gates, refreshed
##   FIGHT     until one yields (drops to 1 health) or the clock runs out
##   RESULT    wagers and stakes are paid out, then both go back to the stands
##
## Rules (the defaults, see the tuning values below):
##   - Nobody loses gear. Fighters use their own loadout; nothing drops,
##     nothing is looted, and a beaten fighter yields instead of dying.
##     No healing items and no vehicles in the pit.
##   - Only the two fighters in a running bout can hurt each other.
##   - Wagers are pooled per bout. Backers of the winner split the losing side's
##     pool in proportion to their stake, less the house cut. A draw, a
##     cancelled bout, or a bout with nobody backing one side refunds everyone.
##   - Fighters cannot bet on their own bout.
##   - A duel may carry a stake that both fighters put up; the winner takes both.
##   - A tournament charges an entry fee; the champion takes the pot. Empty
##     bracket slots are filled with bot gladiators (or byes with `bot_fill` off).
##
## The arena decides every result and every payout itself, and only in SOLO or
## SERVER mode. A client sends requests (`ask`) and shows the `board` the
## server sends it. Money moves only through `bank` (see `Bank`), keyed by the
## account id of each player (`set_key`).

## The board changed (new bout, phase, queue, wagers...). Solo and server.
signal board_changed
## Arena news for one player ("X challenges you", "Into the pit"). A server
## passes it on to that player; solo it shows as a notice.
signal told(actor: Actor, text: String)
## A bout ended. `winner` and `loser` are display names, both "" for a draw.
signal bout_finished(summary: Dictionary)

enum Phase { IDLE, CALLING, COUNTDOWN, FIGHT, RESULT }
const PHASE_NAMES := ["idle", "calling", "countdown", "fight", "result"]
const ArenaVenue := preload("res://core/arena/arena_venue.gd")
const StashServiceScript := preload("res://core/account/stash_service.gd")

# Tuning.
var call_time := 15.0
var countdown_time := 3.0
var fight_time := 90.0
var result_time := 5.0
## With nothing queued for this long, two bot gladiators put on an exhibition
## bout for the crowd to bet on. Below zero turns exhibitions off.
var exhibition_delay := 12.0
var min_bet := 5
var max_bet := 1000
var max_stake := 1000
## Share of the losing pool the house keeps.
var house_cut := 0.1
var tournament_fee := 25
var tournament_signup_time := 30.0
var tournament_max := 8
## Fill empty tournament slots with bot gladiators. Off, they become byes.
var bot_fill := true
## How long a challenge stays open.
var challenge_time := 60.0

## Where money and records go. See `Bank`. Null means nobody can bet.
var bank: Bank
## Client: what the server last sent about the arena, as `board_for` builds it.
var board := {}
## Client: sends a request to the server (set by `NetSession`).
var send_request := Callable()
var phase := Phase.IDLE
var phase_left := 0.0
## The bout in the pit, or null.
var bout: Bout
var queue: Array[Bout] = []
## Open challenges: {"from": Actor, "to": Actor, "stake": int, "left": float}.
var challenges: Array[Dictionary] = []
var tournament: Tournament
var last_result := ""

var _keys := {}           # Actor -> account key
var _gates: Array[Vector3] = [Vector3(-12, 0.1, 0), Vector3(12, 0.1, 0)]
var _idle_time := 0.0
var _bot_serial := 0
var _dirty := true


## One fight between two sides. A side is a player's Actor, or a bot seed
## (an int) until the bot is spawned for the bout.
class Bout:
	extends RefCounted

	## "duel", "practice", "exhibition" or "tournament".
	var kind := "duel"
	var sides: Array = [null, null]
	var fighters: Array[Actor] = [null, null]
	var names: Array[String] = ["", ""]
	var stake := 0
	## Account key -> [side, amount].
	var bets := {}
	var pools: Array[int] = [0, 0]
	var round_name := ""
	var winner := -1
	var spawned_bots: Array[Actor] = []

	func involves(actor: Actor) -> bool:
		if actor == null:
			return false
		for s: Variant in sides:
			if typeof(s) == TYPE_OBJECT and s == actor:
				return true
		return false


## A single elimination bracket.
class Tournament:
	extends RefCounted

	var entrants: Array = []
	var running := false
	var signup_left := 0.0
	var pot := 0
	var round := 0
	## This round's bouts, and the sides that won through so far.
	var bouts: Array = []
	var advancing: Array = []

	## True while the actor is still in it: signed up, or not yet knocked out.
	func has(actor: Actor) -> bool:
		if not running:
			return actor in entrants
		if actor in advancing:
			return true
		for b: Variant in bouts:
			if b.winner < 0 and b.involves(actor):
				return true
		return false


## Where the arena's money goes. Keys are account ids online, "local" solo.
class Bank:
	extends RefCounted

	func credits(_key: String) -> int:
		return 0

	## Adds `delta` (negative to take). False, changing nothing, if it cannot.
	func change(_key: String, _delta: int) -> bool:
		return false

	func record(_key: String, _won: bool) -> void:
		pass


## Solo: the local profile's credits.
class ProfileBank:
	extends Bank

	func credits(_key: String) -> int:
		return Profile.credits

	func change(_key: String, delta: int) -> bool:
		return Profile.change_credits(delta)

	func record(_key: String, won: bool) -> void:
		Profile.record_arena(won)


## Server: the accounts a `StashService` keeps.
class StashBank:
	extends Bank

	var service: StashServiceScript

	func _init(p_service: StashServiceScript) -> void:
		service = p_service

	func credits(key: String) -> int:
		return service.credits_of(key)

	func change(key: String, delta: int) -> bool:
		return service.change_credits(key, delta)

	func record(key: String, won: bool) -> void:
		service.record_arena(key, won)


# --- Starting ------------------------------------------------------------------

## A solo arena: you, the stands, and bot gladiators. Credits come from the
## local profile.
func start_solo(p_kit: Array = [], p_mastery: Dictionary = {}) -> void:
	bank = ProfileBank.new()
	start(ArenaVenue.new(), -1, p_kit, p_mastery)
	set_key(player, "local")


func _setup(p_world: WorldDef, p_seed: int) -> void:
	apply_to_profile = false
	super(p_world, p_seed)
	p_world.set("arena", self)
	var gates: Array[Vector3] = [ArenaVenue.entry_point(0), ArenaVenue.entry_point(1)]
	for node in _map_nodes("arena_gate"):
		gates[int(node.get_meta("side", 0)) % 2] = node.global_position
	_gates = gates


## The account a player's money and record belong to.
func set_key(actor: Actor, key: String) -> void:
	if actor != null:
		_keys[actor] = key
		_dirty = true


func key_of(actor: Actor) -> String:
	return _keys.get(actor, "")


## The arena's own kit rules: no healing and no vehicles in the pit.
func add_player(p_kit: Array = [], p_mastery: Dictionary = {}, p_name := "Raider",
		p_owner := "", p_renown := 0, p_drop := "") -> Actor:
	var kit: Array[String] = []
	for id: String in (p_kit if not p_kit.is_empty() else world.starter_loadout()):
		if not ItemDB.has_tag(id, "heal") and not ItemDB.has_tag(id, "vehicle"):
			kit.append(id)
	var actor := super(kit, p_mastery, p_name, p_owner, p_renown, p_drop)
	_dirty = true
	return actor


# --- Rules -------------------------------------------------------------------

## True only for the two fighters of a bout that is on, against each other.
func may_hurt(attacker: Node, target: Node) -> bool:
	if phase != Phase.FIGHT or bout == null:
		return false
	return (attacker == bout.fighters[0] and target == bout.fighters[1]) \
			or (attacker == bout.fighters[1] and target == bout.fighters[0])


## True if the actor is fighting, or waiting for a bout or tournament.
func is_busy(actor: Actor) -> bool:
	if bout != null and bout.involves(actor):
		return true
	for queued in queue:
		if queued.involves(actor):
			return true
	return tournament != null and tournament.has(actor)


## Pays out a bout's wagers. Returns account key -> credits to hand back
## (stake plus winnings). `winner` is 0 or 1, or -1 for a draw. Pure: used by
## `_settle` and by the tests.
static func wager_payouts(bets: Dictionary, winner: int, cut: float) -> Dictionary:
	var pools: Array[int] = [0, 0]
	for key: String in bets:
		pools[int(bets[key][0])] += int(bets[key][1])
	var out := {}
	# A draw, or nobody on one side: there was no contest to bet on.
	if winner < 0 or pools[0] == 0 or pools[1] == 0:
		for key: String in bets:
			out[key] = int(bets[key][1])
		return out
	var losing: int = pools[1 - winner]
	var share := losing - int(floor(losing * cut))
	for key: String in bets:
		if int(bets[key][0]) == winner:
			var stake := int(bets[key][1])
			out[key] = stake + int(floor(float(stake) * share / pools[winner]))
	return out


# --- Requests ------------------------------------------------------------------

## Anything a player can ask the arena. Online the server calls this with the
## sender's own actor, so nobody can act for someone else. Returns {"ok"} or
## {"ok": false, "error"}.
##   "challenge"        {"to": node name, "stake": int}
##   "accept"/"decline" {"from": node name}
##   "practice"         {} fight a bot gladiator
##   "bet"              {"side": 0 or 1, "amount": int}
##   "join_tournament", "leave_tournament"
func request(actor: Actor, action: String, args: Dictionary) -> Dictionary:
	if mode == Mode.CLIENT or actor == null or actor.is_dead or state_for(actor) == null:
		return _fail("You are not in the arena.")
	var result: Dictionary
	match action:
		"challenge":
			result = _challenge(actor, _player_named(str(args.get("to", ""))), int(args.get("stake", 0)))
		"accept":
			result = _accept(actor, _player_named(str(args.get("from", ""))))
		"decline":
			result = _decline(actor, _player_named(str(args.get("from", ""))))
		"practice":
			result = _practice(actor)
		"bet":
			result = _bet(actor, int(args.get("side", -1)), int(args.get("amount", 0)))
		"join_tournament":
			result = _join_tournament(actor)
		"leave_tournament":
			result = _leave_tournament(actor)
		_:
			result = _fail("Unknown request.")
	_dirty = true
	return result


## The local player asks: straight to the rules here, or to the server online.
## A refusal shows up as a notice.
func ask(action: String, args := {}) -> void:
	if mode == Mode.CLIENT:
		if send_request.is_valid():
			send_request.call(action, args)
		return
	var result := request(player, action, args)
	if not result.ok and player != null:
		_tell(player, result.error)


func _challenge(actor: Actor, target: Actor, stake: int) -> Dictionary:
	if target == null or target == actor:
		return _fail("Pick someone in the arena to challenge.")
	if stake < 0 or stake > max_stake:
		return _fail("Stakes go up to %d." % max_stake)
	if is_busy(actor):
		return _fail("You already have a bout lined up.")
	if is_busy(target):
		return _fail("%s already has a bout lined up." % target.display_name)
	if stake > 0 and (bank == null or bank.credits(key_of(actor)) < stake):
		return _fail("You do not have %d credits." % stake)
	for c in challenges:
		if c.from == actor and c.to == target:
			return _fail("You already challenged %s." % target.display_name)
	challenges.append({"from": actor, "to": target, "stake": stake, "left": challenge_time})
	var staked := " for %d credits" % stake if stake > 0 else ""
	_tell(target, "%s challenges you to a duel%s" % [actor.display_name, staked])
	return {"ok": true}


func _accept(actor: Actor, from: Actor) -> Dictionary:
	var found := _find_challenge(from, actor)
	if found.is_empty():
		return _fail("That challenge is gone.")
	challenges.erase(found)
	if is_busy(actor) or is_busy(from):
		return _fail("One of you already has a bout lined up.")
	var stake: int = found.stake
	if stake > 0:
		if bank == null or not bank.change(key_of(from), -stake):
			return _fail("%s cannot cover the stake any more." % from.display_name)
		if not bank.change(key_of(actor), -stake):
			bank.change(key_of(from), stake)
			return _fail("You do not have %d credits." % stake)
	# Neither of them can take up another challenge now.
	challenges = challenges.filter(func(c: Dictionary) -> bool:
		return c.from != actor and c.to != actor and c.from != from and c.to != from)
	var duel := _new_bout("duel", from, actor)
	duel.stake = stake * 2
	queue.append(duel)
	_tell(from, "%s accepted your duel" % actor.display_name)
	return {"ok": true}


func _decline(actor: Actor, from: Actor) -> Dictionary:
	var found := _find_challenge(from, actor)
	if found.is_empty():
		return _fail("That challenge is gone.")
	challenges.erase(found)
	if from != null:
		_tell(from, "%s declined your duel" % actor.display_name)
	return {"ok": true}


func _practice(actor: Actor) -> Dictionary:
	if is_busy(actor):
		return _fail("You already have a bout lined up.")
	queue.append(_new_bout("practice", actor, _next_bot_seed()))
	return {"ok": true}


func _bet(actor: Actor, side: int, amount: int) -> Dictionary:
	if bout == null or phase != Phase.CALLING:
		return _fail("Bets are closed. Wait for the next bout to be called.")
	if side != 0 and side != 1:
		return _fail("Bet on red or blue.")
	if bout.involves(actor):
		return _fail("Fighters cannot bet on their own bout.")
	var key := key_of(actor)
	if bank == null or key == "":
		return _fail("You have no credits here.")
	var already: Array = bout.bets.get(key, [side, 0])
	if int(already[0]) != side:
		return _fail("You already backed the other side.")
	if amount < min_bet or int(already[1]) + amount > max_bet:
		return _fail("Bets are %d to %d credits a bout." % [min_bet, max_bet])
	if not bank.change(key, -amount):
		return _fail("You do not have %d credits." % amount)
	bout.bets[key] = [side, int(already[1]) + amount]
	bout.pools[side] += amount
	return {"ok": true}


func _join_tournament(actor: Actor) -> Dictionary:
	if tournament != null and tournament.running:
		return _fail("A tournament is under way. Sign up for the next one.")
	if is_busy(actor):
		return _fail("You already have a bout lined up.")
	if tournament != null and tournament.entrants.size() >= tournament_max:
		return _fail("The bracket is full.")
	if tournament_fee > 0 and (bank == null or not bank.change(key_of(actor), -tournament_fee)):
		return _fail("The entry fee is %d credits." % tournament_fee)
	if tournament == null:
		tournament = Tournament.new()
		tournament.signup_left = tournament_signup_time
	tournament.entrants.append(actor)
	tournament.pot += tournament_fee
	if tournament.entrants.size() >= tournament_max:
		tournament.signup_left = 0.0
	return {"ok": true}


func _leave_tournament(actor: Actor) -> Dictionary:
	if tournament == null or actor not in tournament.entrants or tournament.running:
		return _fail("You can only drop out before the tournament starts.")
	tournament.entrants.erase(actor)
	tournament.pot -= tournament_fee
	if bank != null and tournament_fee > 0:
		bank.change(key_of(actor), tournament_fee)
	if tournament.entrants.is_empty():
		tournament = null
	return {"ok": true}


# --- Running bouts ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if world == null:
		return
	if mode == Mode.CLIENT:
		# Count down between the server's updates.
		if board.has("phase_left"):
			board.phase_left = maxf(float(board.phase_left) - delta, 0.0)
		_drive_stage()
		return
	_tick_challenges(delta)
	_tick_tournament(delta)
	match phase:
		Phase.IDLE:
			if not queue.is_empty():
				_call_bout(queue.pop_front())
			elif exhibition_delay >= 0.0 and not active_players().is_empty():
				_idle_time += delta
				if _idle_time >= exhibition_delay:
					_call_bout(_new_bout("exhibition", _next_bot_seed(), _next_bot_seed()))
		Phase.CALLING:
			_tick_phase(delta)
			if phase_left <= 0.0:
				_bring_in_fighters()
		Phase.COUNTDOWN:
			_tick_phase(delta)
			_hold_in_pit()
			if bout.winner < 0 and phase_left <= 0.0:
				_set_phase(Phase.FIGHT, fight_time)
		Phase.FIGHT:
			_tick_phase(delta)
			_hold_in_pit()
			_judge()
		Phase.RESULT:
			_tick_phase(delta)
			if phase_left <= 0.0:
				_clear_pit()
	_keep_crowd_out()
	_drive_stage()
	if _dirty:
		_dirty = false
		board_changed.emit()


func _tick_phase(delta: float) -> void:
	phase_left = maxf(phase_left - delta, 0.0)


func _set_phase(p: Phase, duration: float) -> void:
	phase = p
	phase_left = duration
	_dirty = true


func _call_bout(next: Bout) -> void:
	_idle_time = 0.0
	# A player who left since it was queued forfeits it.
	for side in 2:
		var s: Variant = next.sides[side]
		if typeof(s) == TYPE_OBJECT and (not _is_actor(s) or s.is_dead or state_for(s) == null):
			_forfeit_unplayed(next, side)
			return
	bout = next
	for side in 2:
		bout.names[side] = _side_name(bout.sides[side])
	_set_phase(Phase.CALLING, call_time)
	last_result = ""


func _bring_in_fighters() -> void:
	for side in 2:
		var s: Variant = bout.sides[side]
		var fighter: Actor
		if typeof(s) == TYPE_OBJECT:
			fighter = s if _is_actor(s) else null
			if fighter == null or fighter.is_dead:
				_end_bout(1 - side, "%s left the arena" % bout.names[side])
				return
		else:
			fighter = _spawn_gladiator(int(s), _gates[side])
			bout.spawned_bots.append(fighter)
		bout.fighters[side] = fighter
		bout.names[side] = fighter.display_name
		fighter.global_position = _gates[side]
		fighter.velocity = Vector3.ZERO
		refresh_fighter(fighter)
		fighter.health.min_health = 1.0
		_tell(fighter, "Into the pit. Fight!")
	_set_phase(Phase.COUNTDOWN, countdown_time)


## Full health, armor, stamina and ammo for a bout. Also run on a client's own
## copy of a fighter, so its guns agree with the server's.
static func refresh_fighter(fighter: Actor) -> void:
	fighter.health.health = fighter.health.max_health
	fighter.health.armor = fighter.health.max_armor
	fighter.stamina = fighter.max_stamina
	fighter.stagger_left = 0.0
	fighter.protected_left = 0.0
	fighter.heal_time_left = 0.0
	fighter.flight.heat = 0.0
	for weapon in fighter.weapons:
		var gun := weapon as Gun
		if gun:
			gun.ammo_in_mag = gun.mag_size
			gun.reserve_ammo = maxi(gun.reserve_ammo, gun.mag_size * 4)


func _spawn_gladiator(equip_seed: int, at: Vector3) -> Actor:
	_bot_serial += 1
	var bot := spawn_bot("Gladiator%d" % _bot_serial, at, equip_seed)
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = equip_seed
	# The pit is small and round: they always know where the other one is.
	brain.fov_deg = 360.0
	brain.sight_range = 60.0
	brain.give_up_time = 60.0
	bot.add_child(brain)
	bot.died.connect(_on_actor_died)
	world.on_spawn(bot)
	actor_spawned.emit(bot)
	return bot


func _judge() -> void:
	var down := [false, false]
	for side in 2:
		var f: Actor = bout.fighters[side]
		down[side] = f == null or not is_instance_valid(f) or f.is_dead \
				or f.health.health <= f.health.min_health + 0.01
	if down[0] and down[1]:
		_end_bout(-1, "Both fighters fell")
	elif down[0]:
		_end_bout(1, "%s yields" % bout.names[0])
	elif down[1]:
		_end_bout(0, "%s yields" % bout.names[1])
	elif phase_left <= 0.0:
		# Time: the one with more of their health left wins.
		var share := [0.0, 0.0]
		for side in 2:
			var f: Actor = bout.fighters[side]
			share[side] = f.health.health / maxf(f.health.max_health, 1.0)
		if absf(share[0] - share[1]) < 0.01:
			_end_bout(-1, "Time. A draw")
		else:
			var won := 0 if share[0] > share[1] else 1
			_end_bout(won, "Time. %s wins on points" % bout.names[won])


func _end_bout(winner: int, how: String) -> void:
	bout.winner = winner
	for f in bout.fighters:
		if f != null and is_instance_valid(f):
			f.health.min_health = 0.0
			f.cmd.primary = false
	_settle(bout)
	var summary := {
		"kind": bout.kind,
		"winner": bout.names[winner] if winner >= 0 else "",
		"loser": bout.names[1 - winner] if winner >= 0 else "",
		"how": how,
	}
	last_result = how if winner < 0 or "wins" in how else "%s. %s wins" % [how, bout.names[winner]]
	for f in bout.fighters:
		if f != null and is_instance_valid(f):
			_tell(f, last_result)
	if bout.kind == "tournament" and tournament != null:
		tournament.advancing.append(bout.sides[winner] if winner >= 0 else bout.sides[0])
	_set_phase(Phase.RESULT, result_time if phase >= Phase.COUNTDOWN else 0.5)
	bout_finished.emit(summary)


## Money and records for a finished bout. Only ever runs on the authority.
func _settle(done: Bout) -> void:
	if bank != null:
		var paid := wager_payouts(done.bets, done.winner, house_cut)
		for key: String in paid:
			bank.change(key, int(paid[key]))
		done.bets.clear()
		if done.stake > 0:
			if done.winner >= 0:
				if _is_actor(done.sides[done.winner]):
					bank.change(key_of(done.sides[done.winner]), done.stake)
			else:
				for side in 2:
					if _is_actor(done.sides[side]):
						bank.change(key_of(done.sides[side]), done.stake / 2)
		if done.winner >= 0:
			for side in 2:
				var s: Variant = done.sides[side]
				if _is_actor(s) and key_of(s) != "":
					bank.record(key_of(s), side == done.winner)
	_dirty = true


## Sends both fighters back to the stands and calls the next bout.
func _clear_pit() -> void:
	for f in bout.fighters:
		if f == null or not is_instance_valid(f) or f.is_dead:
			continue
		if f in bout.spawned_bots:
			continue
		f.health.min_health = 0.0
		refresh_fighter(f)
		_to_stands(f)
	for bot in bout.spawned_bots:
		if is_instance_valid(bot):
			_remove_actor(bot)
	bout = null
	_set_phase(Phase.IDLE, 0.0)


## How far into the running fight it is, in seconds, or -1 outside a fight.
## A client reads it from the board the server sent.
func fight_elapsed() -> float:
	if mode == Mode.CLIENT:
		if board.get("phase", "") != "fight":
			return -1.0
		return fight_time - float(board.get("phase_left", fight_time))
	return fight_time - phase_left if phase == Phase.FIGHT else -1.0


## The phase by name, from the board on a client.
func phase_name() -> String:
	return String(board.get("phase", "idle")) if mode == Mode.CLIENT else PHASE_NAMES[phase]


## Moves the venue's doors and rising barriers to match the bout. Every
## machine works it out from the same phase and clock, so it needs no
## messages of its own.
func _drive_stage() -> void:
	if map != null and map.has_method("set_stage"):
		map.call("set_stage", phase_name(), fight_elapsed())


## Keeps fighters inside the pit during a bout. While they wait, and while the
## doors are open, their tunnel counts too; anyone left in a tunnel once the
## doors close is put on the floor at their door.
func _hold_in_pit() -> void:
	var waiting := phase == Phase.COUNTDOWN
	var tunnels := waiting or ArenaVenue.doors_open(phase_name(), fight_elapsed())
	for side in 2:
		var f: Actor = bout.fighters[side]
		if f == null or not is_instance_valid(f) or f.is_dead:
			continue
		var at := f.global_position
		if ArenaVenue.in_pit(at) or (tunnels and ArenaVenue.in_tunnel(at)):
			continue
		f.global_position = _gates[side] if waiting else ArenaVenue.entry_point(side)
		f.velocity = Vector3.ZERO


## Nobody but the fighters goes into the pit, whatever they fly or jump with.
func _keep_crowd_out() -> void:
	for state in players:
		var a := state.actor
		if a == null or not is_instance_valid(a) or a.is_dead:
			continue
		if bout != null and phase >= Phase.COUNTDOWN and a in bout.fighters:
			continue
		if ArenaVenue.in_bounds(a.global_position):
			_to_stands(a)


func _to_stands(actor: Actor) -> void:
	var spots := _map_nodes("spawn_player")
	if spots.is_empty():
		return
	var spot := spots[rng.randi() % spots.size()]
	actor.global_position = spot.global_position
	actor.velocity = Vector3.ZERO


# --- Tournaments ---------------------------------------------------------------

func _tick_tournament(delta: float) -> void:
	if tournament == null:
		return
	if not tournament.running:
		tournament.signup_left -= delta
		if tournament.signup_left <= 0.0:
			_start_tournament()
		return
	# Wait for this round's bouts to be fought.
	for b in tournament.bouts:
		if b.winner < 0 and (b == bout or b in queue):
			return
	if tournament.advancing.size() <= 1:
		_crown()
	else:
		_next_round(tournament.advancing.duplicate())


func _start_tournament() -> void:
	var field: Array = tournament.entrants.filter(func(a: Actor) -> bool:
		return is_instance_valid(a) and not a.is_dead and state_for(a) != null)
	if field.is_empty():
		tournament = null
		_dirty = true
		return
	var size := 2
	while size < field.size():
		size *= 2
	size = maxi(size, 4) if bot_fill else size
	while bot_fill and field.size() < size:
		field.append(_next_bot_seed())
	field.shuffle()
	tournament.running = true
	_next_round(field)


func _next_round(field: Array) -> void:
	tournament.round += 1
	tournament.bouts.clear()
	tournament.advancing.clear()
	var label := "Final" if field.size() <= 2 else ("Semi-final" if field.size() <= 4 else "Round %d" % tournament.round)
	var i := 0
	while i < field.size():
		if i + 1 >= field.size():
			# An odd one out goes straight through.
			tournament.advancing.append(field[i])
			break
		var b := _new_bout("tournament", field[i], field[i + 1])
		b.round_name = label
		tournament.bouts.append(b)
		queue.append(b)
		i += 2
	_dirty = true


func _crown() -> void:
	var champion: Variant = tournament.advancing[0] if not tournament.advancing.is_empty() else null
	var name := _side_name(champion) if champion != null else "Nobody"
	last_result = "%s is the champion" % name
	if _is_actor(champion) and bank != null and tournament.pot > 0:
		bank.change(key_of(champion), tournament.pot)
		_tell(champion, "You won the tournament and %d credits" % tournament.pot)
	tournament = null
	_dirty = true


# --- Helpers -------------------------------------------------------------------

func _new_bout(kind: String, a: Variant, b: Variant) -> Bout:
	var made := Bout.new()
	made.kind = kind
	made.sides = [a, b]
	made.names = [_side_name(a), _side_name(b)]
	return made


## A queued bout that cannot be fought because a side left: the other side
## wins it without a fight (stakes go to them, no wagers were taken yet).
func _forfeit_unplayed(b: Bout, missing: int) -> void:
	b.winner = 1 - missing
	_settle(b)
	if b.kind == "tournament" and tournament != null:
		tournament.advancing.append(b.sides[1 - missing])
	last_result = "%s forfeits" % b.names[missing]
	_dirty = true


func _side_name(side: Variant) -> String:
	if typeof(side) == TYPE_OBJECT:
		return side.display_name if _is_actor(side) else "?"
	# A bot that has not been spawned: work out its name from its seed.
	var probe := RandomNumberGenerator.new()
	probe.seed = int(side)
	probe.randi()
	return ArenaVenue.GLADIATOR_NAMES[probe.randi() % ArenaVenue.GLADIATOR_NAMES.size()]


func _next_bot_seed() -> int:
	return rng.randi()


func _player_named(node_name: String) -> Actor:
	for state in players:
		if state.actor != null and is_instance_valid(state.actor) and String(state.actor.name) == node_name:
			return state.actor
	return null


func _find_challenge(from: Actor, to: Actor) -> Dictionary:
	for c in challenges:
		if c.from == from and c.to == to:
			return c
	return {}


func _tick_challenges(delta: float) -> void:
	for c in challenges.duplicate():
		c.left -= delta
		if c.left <= 0.0 or not is_instance_valid(c.from) or not is_instance_valid(c.to):
			challenges.erase(c)
			_dirty = true


func _tell(actor: Variant, text: String) -> void:
	if not _is_actor(actor):
		return
	if mode == Mode.SOLO:
		actor.notice.emit(text)
	told.emit(actor, text)


## True for a live Actor. Safe on freed objects and on bot seeds.
static func _is_actor(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value) and value is Actor


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}


## In the arena nobody dies for real except by leaving (a disconnect, or the
## game closing). That forfeits any bout they were in. Nothing is dropped.
func _on_actor_died(actor: Actor, info: DamageInfo) -> void:
	var state := state_for(actor)
	if bout != null and actor in bout.fighters and bout.winner < 0:
		var side := bout.fighters.find(actor)
		_end_bout(1 - side, "%s left the pit" % bout.names[side])
	challenges = challenges.filter(func(c: Dictionary) -> bool: return c.from != actor and c.to != actor)
	if tournament != null and not tournament.running and actor in tournament.entrants:
		_leave_tournament(actor)
	if state != null and not state.finished:
		state.finished = true
		player_finished.emit(actor, {
			"outcome": "left_arena",
			"cause": info.kind,
			"world_id": world.id,
			"loot": [],
			"kept_gear": actor.gear_items.duplicate(),
			"brought_home": [],
			"loot_value": 0,
			"lost": [],
			"kills": 0,
			"mastery_xp": {},
			"time_in_raid": 0.0,
		})
	elif state == null:
		bots.erase(actor)
	_dirty = true
	get_tree().create_timer(1.0).timeout.connect(_remove_actor.bind(actor))


## A dropped connection leaves at once: there is no gear to fight over, and
## a fighter who goes forfeits their bout.
func remove_player(actor: Actor) -> void:
	var state := state_for(actor)
	if state == null:
		return
	if not state.finished and not actor.is_dead:
		actor.kill("disconnect")
		return
	players.erase(state)


## There is no sign-out in the arena: you leave through the arena panel.
func begin_sign_out(actor: Actor, _forced := false) -> bool:
	_tell(actor, "Use \"Leave the arena\" on the arena panel")
	return false


func _remove_actor(actor: Actor) -> void:
	_keys.erase(actor)
	super(actor)


## A server or a solo arena that goes away mid-bout hands every wager and
## stake back, and refunds tournament entries.
func _exit_tree() -> void:
	if mode != Mode.CLIENT and bank != null:
		var open: Array[Bout] = []
		if bout != null and bout.winner < 0:
			open.append(bout)
		open.append_array(queue)
		for b in open:
			b.winner = -1
			for key: String in b.bets:
				bank.change(key, int(b.bets[key][1]))
			b.bets.clear()
			if b.stake > 0:
				for side in 2:
					if _is_actor(b.sides[side]):
						bank.change(key_of(b.sides[side]), b.stake / 2)
		if tournament != null:
			for a: Variant in tournament.entrants:
				if _is_actor(a):
					bank.change(key_of(a), tournament_fee)
		bout = null
		queue.clear()
		tournament = null
	super()


# --- The board ------------------------------------------------------------------

## What `viewer` should see: the bout, the queue, challenges for them, the
## tournament, and their own money. Plain data, sent to clients as is.
func board_for(viewer: Actor) -> Dictionary:
	var out := {
		"phase": PHASE_NAMES[phase],
		"phase_left": phase_left,
		"last_result": last_result,
		"min_bet": min_bet,
		"max_bet": max_bet,
		"fee": tournament_fee,
		"bout": {},
		"queue": [],
		"challenges": [],
		"players": [],
		"tournament": {},
		"you": {},
	}
	if bout != null:
		var fighters: Array = []
		for side in 2:
			var f: Actor = bout.fighters[side]
			fighters.append(String(f.name) if f != null and is_instance_valid(f) else "")
		out.bout = {"kind": bout.kind, "names": bout.names.duplicate(), "nodes": fighters,
				"pools": bout.pools.duplicate(), "stake": bout.stake, "round": bout.round_name,
				"winner": bout.winner}
	for b in queue:
		out.queue.append("%s vs %s (%s)" % [b.names[0], b.names[1], b.round_name if b.round_name != "" else b.kind])
	for c in challenges:
		if c.to == viewer or c.from == viewer:
			out.challenges.append({"from": c.from.display_name, "from_node": String(c.from.name),
					"to": c.to.display_name, "incoming": c.to == viewer, "stake": c.stake})
	for state in players:
		var a := state.actor
		if a != viewer and a != null and is_instance_valid(a) and not a.is_dead and not state.finished:
			out.players.append({"name": a.display_name, "node": String(a.name), "busy": is_busy(a)})
	if tournament != null:
		var names: Array = []
		for a: Variant in tournament.entrants:
			names.append(_side_name(a))
		out.tournament = {"running": tournament.running, "entrants": names, "pot": tournament.pot,
				"starts_in": maxf(tournament.signup_left, 0.0), "round": tournament.round}
	if viewer != null:
		var key := key_of(viewer)
		var you := {"credits": bank.credits(key) if bank != null and key != "" else 0,
				"busy": is_busy(viewer), "fighting": bout != null and viewer in bout.fighters,
				"entered": tournament != null and tournament.has(viewer)}
		if bout != null and bout.bets.has(key):
			you["bet_side"] = bout.bets[key][0]
			you["bet"] = bout.bets[key][1]
		out.you = you
	return out


## The board the local player should see: built here solo, sent by the
## server online.
func view_board() -> Dictionary:
	return board if mode == Mode.CLIENT else board_for(player)
