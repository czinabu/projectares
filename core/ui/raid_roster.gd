extends RefCounted
## Who is playing in a raid, for the scoreboard and nameplates. UI only: it
## reads the raid and its actors and never changes them.
##
## On a solo or server raid the players come from `Raid.players`. On a client
## every actor that is not a bot is a player. A player comes back as a new actor every time they drop in, so
## the roster keeps one row per name and adds their kills up across lives. A
## player whose actor vanishes while alive has left the world.

const IN_RAID := "Fighting"
const DOWN := "Down"
const LEFT := "Left"

var raid: Raid
## The local player, or null on a server.
var me: Actor
## One per player seen: { name, status, kills, is_me, lives, renown, rank,
## bounty, marked }. `lives` maps
## each actor of theirs that was seen to the kills it made.
var entries: Array[Dictionary] = []
var _by_name := {}
var _watched := {}


func _init(p_raid: Raid, p_me: Actor = null) -> void:
	raid = p_raid
	set_me(p_me)


## Call again when the local player drops back in as a new actor.
func set_me(p_me: Actor) -> void:
	me = p_me
	if me != null and not _watched.has(me.get_instance_id()):
		_watched[me.get_instance_id()] = true
		me.hit_confirmed.connect(_on_my_hit.bind(me.get_instance_id()))


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
	var alive := {}
	var down := {}
	for actor in players_in(raid):
		var entry: Dictionary = _by_name.get(actor.display_name, {})
		if entry.is_empty():
			entry = {"name": actor.display_name, "status": IN_RAID, "kills": 0, "is_me": false,
					"lives": {}, "my_kills": {}}
			_by_name[actor.display_name] = entry
			entries.append(entry)
		if actor == me:
			entry.is_me = true
		var state := raid.state_for(actor)
		var id := actor.get_instance_id()
		if state != null:
			entry.lives[id] = state.kills
			entry.kills_known = true
		elif not entry.lives.has(id):
			entry.lives[id] = 0
		# Their newest body carries their standing.
		if not actor.is_dead or not entry.has("renown"):
			entry["renown"] = actor.renown
			entry["rank"] = actor.rank
			entry["bounty"] = actor.bounty
			entry["marked"] = actor.marked
		if actor.is_dead:
			down[entry.name] = true
		elif state == null or not state.finished:
			alive[entry.name] = true
	for entry in entries:
		if alive.has(entry.name):
			entry.status = IN_RAID
		elif down.has(entry.name):
			entry.status = DOWN
		elif entry.status == IN_RAID:
			entry.status = LEFT
		var total := 0
		for id: int in entry.lives:
			# Your own kills are also counted as you make them, for a client
			# that has not heard the server's count yet.
			total += maxi(entry.lives[id], entry.my_kills.get(id, 0))
		entry.kills = total
	entries.sort_custom(_before)


## Kills are known for players with a state here. Online, the server sends
## every player's count. Your own are also counted from your confirmed kills.
func kills_known(entry: Dictionary) -> bool:
	return entry.is_me or raid.mode != Raid.Mode.CLIENT or entry.get("kills_known", false)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var order := [IN_RAID, LEFT, DOWN]
	if a.status != b.status:
		return order.find(a.status) < order.find(b.status)
	if a.kills != b.kills:
		return a.kills > b.kills
	return String(a.name).naturalnocasecmp_to(b.name) < 0


func _on_my_hit(_target: Actor, _info: DamageInfo, lethal: bool, life: int) -> void:
	if not lethal or me == null:
		return
	var entry: Dictionary = _by_name.get(me.display_name, {})
	if not entry.is_empty():
		entry.my_kills[life] = entry.my_kills.get(life, 0) + 1
