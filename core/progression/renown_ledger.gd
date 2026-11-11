extends RefCounted
## Renown: who you are in a world. One ledger lives in each `Raid` and keeps a
## standing per player for as long as they keep coming back to that world.
## Plain data and arithmetic, so it works the same on a headless server.
##
## Two numbers matter. Session renown (`Standing.renown`) is what is at stake:
## kills raise it and every death hands a share of it to the killer. Lifetime
## renown only ever grows, sets the rank, and is saved with the account from
## the `renown` entry of a finished life's result.

## Lifetime renown needed for each rank, lowest first.
const RANKS := [
	[0, "Recruit"],
	[200, "Raider"],
	[800, "Veteran"],
	[2500, "Reaver"],
	[7000, "Warlord"],
	[20000, "Legend"],
]

## Renown for killing a bot, and for killing a player.
var bot_kill := 10
var player_kill := 100
## Killing someone in nothing but the free scrap kit pays this share, so
## farming new arrivals is pointless.
var scrap_kill_factor := 0.1
## Each kill in a life after the first pays this much more, up to the cap.
var streak_step := 0.1
var streak_cap := 2.0
## The share of session renown a death takes. A player who made the kill gets it.
var death_share := 0.1
## Player kills in one life that put a price on you, and that show you to everyone.
var bounty_streak := 3
var exposed_streak := 5
## The price, per player kill in the streak.
var bounty_per_kill := 50
## The Marked is the living player with the most session renown, once they
## have at least this much. Killing them pays the bonus on top.
var marked_floor := 300
var marked_bonus := 250

## Multiplies what a kill itself pays. The `Raid` raises it as the war heats up.
var pay_scale := 1.0

## Owner key -> Standing.
var standings := {}


## One player's standing in this world.
class Standing:
	extends RefCounted

	var owner := ""
	var name := ""
	## Session renown: at stake on every death.
	var renown := 0
	## Lifetime renown, counting what this session has added.
	var lifetime := 0
	## Renown gained in the current life, for the result.
	var earned := 0
	## Kills in the current life, and how many of those were players.
	var streak := 0
	var player_streak := 0
	## In the world and alive.
	var alive := false


## Starts a life for `owner`. Session renown carries over from earlier lives.
func enter(owner: String, name: String, lifetime := 0) -> Standing:
	var standing: Standing = standings.get(owner)
	if standing == null:
		standing = Standing.new()
		standing.owner = owner
		standing.lifetime = maxi(lifetime, 0)
		standings[owner] = standing
	standing.name = name
	standing.earned = 0
	standing.streak = 0
	standing.player_streak = 0
	standing.alive = true
	return standing


func get_standing(owner: String) -> Standing:
	return standings.get(owner)


## `owner` left the world alive: the session is over and nothing is at stake.
func leave(owner: String) -> void:
	standings.erase(owner)


## `killer` killed a bot. Returns the renown gained.
func bot_killed(killer: String) -> int:
	var standing: Standing = standings.get(killer)
	if standing == null:
		return 0
	standing.streak += 1
	return _gain(standing, roundi(bot_kill * _streak_factor(standing) * pay_scale))


## `victim` died. `killer` is the owner key of the player who did it, or ""
## for a bot or the world. `scrap` means the victim wore only the free kit.
## Returns { lost, gain, stolen, bounty, marked } where `gain` is everything
## the killer got and includes the stolen share, the bounty and the bonus.
func player_died(victim: String, killer := "", scrap := false) -> Dictionary:
	var out := {"lost": 0, "gain": 0, "stolen": 0, "bounty": 0, "marked": false}
	var dead: Standing = standings.get(victim)
	if dead == null:
		return out
	var was_marked := marked() == victim
	var price := bounty_of(victim)
	out.lost = int(floor(dead.renown * death_share))
	dead.renown -= out.lost
	dead.streak = 0
	dead.player_streak = 0
	dead.alive = false
	var winner: Standing = standings.get(killer)
	if winner == null or winner == dead:
		return out
	winner.streak += 1
	winner.player_streak += 1
	var base := player_kill * (scrap_kill_factor if scrap else 1.0)
	var gain := roundi(base * _streak_factor(winner) * pay_scale) + int(out.lost) + price
	if was_marked:
		gain += marked_bonus
	out.gain = _gain(winner, gain)
	out.stolen = out.lost
	out.bounty = price
	out.marked = was_marked
	return out


## The price on `owner`'s head, or 0.
func bounty_of(owner: String) -> int:
	var standing: Standing = standings.get(owner)
	if standing == null or not standing.alive or standing.player_streak < bounty_streak:
		return 0
	return standing.player_streak * bounty_per_kill


## Whether everyone can see where `owner` is.
func is_exposed(owner: String) -> bool:
	var standing: Standing = standings.get(owner)
	return standing != null and standing.alive and standing.player_streak >= exposed_streak


## The owner key of the Marked, or "" when nobody qualifies.
func marked() -> String:
	var best: Standing = null
	for owner: String in standings:
		var standing: Standing = standings[owner]
		if not standing.alive or standing.renown < marked_floor:
			continue
		if best == null or standing.renown > best.renown:
			best = standing
	return best.owner if best != null else ""


## The rank (an index into RANKS) for a lifetime renown.
static func rank_for(lifetime: int) -> int:
	var rank := 0
	for i in RANKS.size():
		if lifetime >= int(RANKS[i][0]):
			rank = i
	return rank


static func rank_name(rank: int) -> String:
	return RANKS[clampi(rank, 0, RANKS.size() - 1)][1]


## Lifetime renown still needed for the next rank, or 0 at the top.
static func to_next_rank(lifetime: int) -> int:
	var rank := rank_for(lifetime)
	if rank >= RANKS.size() - 1:
		return 0
	return int(RANKS[rank + 1][0]) - lifetime


func _streak_factor(standing: Standing) -> float:
	return minf(1.0 + streak_step * maxi(standing.streak - 1, 0), streak_cap)


func _gain(standing: Standing, amount: int) -> int:
	standing.renown += amount
	standing.lifetime += amount
	standing.earned += amount
	return amount
