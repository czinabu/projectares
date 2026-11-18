class_name WarCommander
extends RefCounted
## An army's commander (DESIGN.md "Army commanders"): every round of orders
## it keeps a garrison on each site its army holds, splits the rest into
## fireteams and sends each team at an objective: an own site under attack
## first, then open sites, then the other army's, weighed by how far off
## they are, how hard they are held and whether a storm covers the push.
## Teams spread over several objectives rather than all going one way, and a
## fight that is being lost stops drawing teams, so they pull back to
## something better. Players are never an objective: an army fights the
## other army for ground, and a player meets it where it is going.
##
## Plain rules on plain data (`plan`), so it is cheap and testable; the
## `Raid` runs it on the authority (`Raid._tick_orders`) and carries out the
## orders with `BotBrain.post_to`.

const Strongpoint := preload("res://core/war/strongpoint.gd")

## Bots in a fireteam.
var team_size := 5
## The most of an army's teams one objective may take, as a share.
var objective_share := 0.6
## How much an objective is worth next to another (times its base).
var defend_weight := 2.5
var open_weight := 1.5
var storm_weight := 2.0
## Each enemy soldier near an enemy site makes it this much less attractive.
var held_weight := 0.25
## Outnumbered by more than this near an objective, a fight is being lost:
## it is worth only `losing_weight` as much, and teams go elsewhere.
var losing_odds := 2.0
var losing_weight := 0.2


## The orders for one army: {bot: Strongpoint}, and each bot's fireteam
## number in `teams` ({bot: int}, from `first_team` up). `sites` are all the
## strongpoints; `strength` is how many soldiers of each side stand near
## each site ({Strongpoint: {faction: count}}); `storm` the sites a storm
## covers. Garrisons take `garrison` bots per held site, nearest first.
func plan(faction: String, army: Array, sites: Array, strength: Dictionary, storm: Array,
		garrison: int, teams: Dictionary, first_team: int) -> Dictionary:
	var orders := {}
	var spare: Array = army.duplicate()
	var mine := "faction:" + faction
	for point: Strongpoint in sites:
		if point.holder != mine or spare.is_empty():
			continue
		spare.sort_custom(func(a: Actor, b: Actor) -> bool:
			return a.global_position.distance_squared_to(point.global_position) \
					< b.global_position.distance_squared_to(point.global_position))
		for i in mini(garrison, spare.size()):
			orders[spare.pop_front()] = point
	var groups := fireteams(spare)
	if groups.is_empty():
		return orders
	var cap := maxi(1, ceili(groups.size() * objective_share))
	var taken := {}
	var n := first_team
	for group: Array in groups:
		var centre := Vector3.ZERO
		for bot: Actor in group:
			centre += bot.global_position
		centre /= group.size()
		var best: Strongpoint = null
		var best_score := 0.0
		for point: Strongpoint in sites:
			var count := int(taken.get(point, 0))
			if count >= cap:
				continue
			var score := worth(faction, point, centre, strength.get(point, {}), point in storm) / (1.0 + count)
			if score > best_score:
				best_score = score
				best = point
		if best == null:
			continue
		taken[best] = int(taken.get(best, 0)) + 1
		for bot: Actor in group:
			orders[bot] = best
			teams[bot] = n
		n += 1
	return orders


## What one site is worth to `faction`'s team at `from`.
func worth(faction: String, point: Strongpoint, from: Vector3, near: Dictionary, storm: bool) -> float:
	var mine := "faction:" + faction
	var ours := int(near.get(faction, 0))
	var theirs := 0
	for side: String in near:
		if side != faction:
			theirs += int(near[side])
	var score := 1000.0 / (40.0 + point.global_position.distance_to(from))
	if point.holder == mine:
		# Our own: only worth a team while someone is taking it from us.
		if not point.contested and (point.taker == "" or point.taker == mine):
			return 0.0
		score *= defend_weight
	elif point.holder == "":
		score *= open_weight
	else:
		score /= 1.0 + theirs * held_weight
	if storm:
		score *= storm_weight
	if theirs > maxi(ours, 1) * losing_odds:
		score *= losing_weight
	return score


## Splits soldiers into fireteams of about `team_size` that stand near one
## another: each team starts from the soldier furthest out and takes its
## nearest neighbours.
func fireteams(soldiers: Array) -> Array:
	var left: Array = soldiers.duplicate()
	var out: Array = []
	if left.is_empty():
		return out
	var centre := Vector3.ZERO
	for bot: Actor in left:
		centre += bot.global_position
	centre /= left.size()
	while not left.is_empty():
		var far := 0
		for i in left.size():
			if (left[i] as Actor).global_position.distance_squared_to(centre) \
					> (left[far] as Actor).global_position.distance_squared_to(centre):
				far = i
		var lead: Actor = left.pop_at(far)
		left.sort_custom(func(a: Actor, b: Actor) -> bool:
			return a.global_position.distance_squared_to(lead.global_position) \
					< b.global_position.distance_squared_to(lead.global_position))
		var group: Array = [lead]
		while group.size() < team_size and not left.is_empty():
			group.append(left.pop_front())
		# A last straggler or two join the team before rather than go alone.
		if group.size() <= team_size / 2 and not out.is_empty():
			(out.back() as Array).append_array(group)
		else:
			out.append(group)
	return out
