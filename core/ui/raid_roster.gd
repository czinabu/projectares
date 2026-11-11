extends RefCounted
## Who is playing in a raid, for the scoreboard and nameplates. UI only: it
## reads the raid and its actors and never changes them.
##
## On a solo or server raid the players come from `Raid.players`. A client's
## raid has no player states, so there every actor that is not a bot is a
## player. A player who vanishes while alive has extracted (a dropped player
## is killed first), so the roster remembers everyone it has seen.

const IN_RAID := "In raid"
const DOWN := "Down"
const EXTRACTED := "Extracted"

var raid: Raid
## The local player, or null on a server.
var me: Actor
## One per player seen: { id, name, status, kills, is_me }.
var entries: Array[Dictionary] = []
var _by_id := {}
var _my_kills := 0


func _init(p_raid: Raid, p_me: Actor = null) -> void:
	raid = p_raid
	me = p_me
	if me != null:
		me.hit_confirmed.connect(_on_my_hit)


## Players currently in the raid, alive or dead.
static func players_in(p_raid: Raid) -> Array[Actor]:
	var out: Array[Actor] = []
	if p_raid == null:
		return out
	if p_raid.mode != Raid.Mode.CLIENT:
		for state in p_raid.players:
			if is_instance_valid(state.actor):
				out.append(state.actor)
		return out
	for child in p_raid.get_children():
		var actor := child as Actor
		if actor != null and not actor.is_queued_for_deletion() and not p_raid.bots.has(actor):
			out.append(actor)
	return out


## Bots still standing.
func bots_alive() -> int:
	var count := 0
	for bot in raid.bots:
		if is_instance_valid(bot) and not bot.is_dead:
			count += 1
	return count


func refresh() -> void:
	var present := {}
	for actor in players_in(raid):
		var id := actor.get_instance_id()
		present[id] = true
		var entry: Dictionary = _by_id.get(id, {})
		if entry.is_empty():
			entry = {"id": id, "name": actor.display_name, "status": IN_RAID, "kills": 0,
					"is_me": actor == me}
			_by_id[id] = entry
			entries.append(entry)
		entry.name = actor.display_name
		var state := raid.state_for(actor)
		if actor.is_dead:
			entry.status = DOWN
		elif state != null and state.finished:
			entry.status = EXTRACTED
		else:
			entry.status = IN_RAID
		if state != null:
			entry.kills = state.kills
		elif entry.is_me:
			entry.kills = _my_kills
	for entry in entries:
		if not present.has(entry.id) and entry.status == IN_RAID:
			entry.status = EXTRACTED
	entries.sort_custom(_before)


## Kills are only known for players with a state here (solo, server) and for
## yourself, counted from your own confirmed kills.
func kills_known(entry: Dictionary) -> bool:
	return entry.is_me or raid.mode != Raid.Mode.CLIENT


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var order := [IN_RAID, EXTRACTED, DOWN]
	if a.status != b.status:
		return order.find(a.status) < order.find(b.status)
	if a.kills != b.kills:
		return a.kills > b.kills
	return String(a.name).naturalnocasecmp_to(b.name) < 0


func _on_my_hit(_target: Actor, _info: DamageInfo, lethal: bool) -> void:
	if lethal:
		_my_kills += 1
