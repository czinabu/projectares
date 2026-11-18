extends RefCounted
## Enemy senses and squads (DESIGN.md "Enemy senses and squads"): bots react
## only to what they sense, only a few go to look at a noise or hunt one
## person, a chase is leashed to the bot's ground, a squadmate's callout is a
## snapshot, a lost contact is searched for and then let go, and a bot runs
## from a grenade. Called from the test runner (`-- --only bot_senses`).

const DT := 1.0 / 60.0


static func run(t: Node) -> void:
	print("Bot senses: hearing, hunters, leash, callouts, search, dodging")
	SquadBoard.clear()
	_claims(t)
	var raid: Raid = await t._new_raid(47, false)
	var player := raid.add_player()
	await t.frames(2)
	var soldiers: Array[Actor] = []
	for bot in raid.bots:
		if bot.get_active_weapon() is Gun and str(bot.get_meta("kind", "soldier")) == "soldier":
			soldiers.append(bot)
	t.check(soldiers.size() >= 12, "a dozen soldiers to test with (%d)" % soldiers.size())
	if soldiers.size() < 12:
		await t._end_raid(raid)
		return
	# Everyone else well away.
	for bot in raid.bots:
		if bot not in soldiers:
			bot.global_position = Vector3(-900, 0, -900)
	_footsteps(t, player)
	await _noise(t, raid, player, soldiers)
	await _leash(t, player, soldiers)
	await _callout(t, player, soldiers)
	await _search(t, player, soldiers)
	_prefers_army(t)
	_dodge(t, soldiers[0])
	_commander(t, raid)
	SquadBoard.clear()
	BotBrain._slots.clear()
	await t._end_raid(raid)


static func _claims(t: Node) -> void:
	var tps := Engine.physics_ticks_per_second
	var who := 700001
	t.check(SquadBoard.hunt(who, 1, 2, 100, 3.0) and SquadBoard.hunt(who, 2, 2, 100, 3.0),
			"two bots may hunt a person when two may")
	t.check(not SquadBoard.hunt(who, 3, 2, 101, 3.0), "a third may not")
	t.check(SquadBoard.hunt(who, 1, 2, 102, 3.0), "a hunter keeps its place")
	t.check(SquadBoard.hunters(who, 102) == 2, "two hunt the person")
	SquadBoard.stop_hunt(who, 1)
	t.check(SquadBoard.hunt(who, 3, 2, 103, 3.0), "a place let go is taken")
	t.check(SquadBoard.hunt(who, 4, 2, 103 + 4 * tps, 3.0), "and one that runs out is free again")
	t.check(SquadBoard.flank(who, 1, 0, 4.0) and not SquadBoard.flank(who, 2, 10, 4.0),
			"one bot at a time works round a person's flank")
	t.check(SquadBoard.flank(who, 2, 5 * tps, 4.0), "the next takes the flank once it runs out")
	SquadBoard.take_cover(Vector3(10, 0, 10), 1, 0, 4.0)
	t.check(not SquadBoard.cover_free(Vector3(11, 0, 10), 2, 10), "two bots never crowd one cover")
	t.check(SquadBoard.cover_free(Vector3(11, 0, 10), 1, 10), "a bot's own cover is free to it")
	t.check(SquadBoard.cover_free(Vector3(20, 0, 10), 2, 10), "cover further off is free")
	SquadBoard.clear()


static func _footsteps(t: Node, player: Actor) -> void:
	player.velocity = Vector3(player.sprint_speed, 0, 0)
	var sprint := BotBrain.noise_of(player)
	player.velocity = Vector3(player.walk_speed, 0, 0)
	var jog := BotBrain.noise_of(player)
	player.velocity = Vector3(2.0, 0, 0)
	var walk := BotBrain.noise_of(player)
	player.velocity = Vector3.ZERO
	if player.is_on_floor():
		t.check(sprint > jog and jog > 0.0 and walk == 0.0,
				"a sprint is heard furthest, a jog closer, a walk not at all (%.0f, %.0f, %.0f)" % [sprint, jog, walk])
	else:
		t.check(sprint == 0.0, "nothing on the ground is heard from someone in the air")


static func _reset(brains: Array[BotBrain]) -> void:
	SquadBoard.clear()
	for brain in brains:
		brain.state = BotBrain.State.PATROL
		brain._alert_left = 0.0
		brain._contact_id = 0
		brain._hunting = false
		brain._search.clear()
		brain.target = null


static func _brains(bots: Array[Actor]) -> Array[BotBrain]:
	var out: Array[BotBrain] = []
	for bot in bots:
		out.append(bot.get_node("Brain") as BotBrain)
	return out


## Caleb's "everyone converges on me": a shot heard by ten patrolling
## soldiers sends only the nearest few to look; the rest turn to face it.
static func _noise(t: Node, _raid: Raid, player: Actor, soldiers: Array[Actor]) -> void:
	var group := soldiers.slice(0, 10)
	var brains := _brains(group)
	_reset(brains)
	var at := player.global_position
	for i in group.size():
		group[i].global_position = at + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / group.size()) * (12.0 + i * 2.0)
		brains[i].post_to(group[i].global_position, 12.0)
	await t.frames(1)
	Combat.noise(player, at, 45.0)
	var looking := 0
	var alert := 0
	for brain in brains:
		if brain.state == BotBrain.State.CHASE:
			looking += 1
		elif brain._alert_left > 0.0:
			alert += 1
	t.check(looking == brains[0].noise_lookers, "only %d of ten go to look at a shot (%d)" % [brains[0].noise_lookers, looking])
	t.check(alert == group.size() - looking, "the rest turn to face it (%d)" % alert)
	t.check(brains[0].state == BotBrain.State.CHASE and brains[1].state == BotBrain.State.CHASE,
			"the nearest ones are the ones that go")
	var chaser := brains[0]
	t.check(chaser._last_seen.distance_to(at) <= 12.0 * 0.1 * 1.5,
			"a shot is placed only roughly, by how far off it was (%.1f m)" % chaser._last_seen.distance_to(at))
	# Another shot from the same place: still the same few.
	Combat.noise(player, at, 45.0)
	looking = 0
	for brain in brains:
		if brain.state == BotBrain.State.CHASE:
			looking += 1
	t.check(looking == brains[0].noise_lookers, "shooting again draws nobody new (%d)" % looking)
	_reset(brains)


## A chase is leashed: a bot never goes to look at something far past its ground.
static func _leash(t: Node, player: Actor, soldiers: Array[Actor]) -> void:
	var bot := soldiers[0]
	var brain := bot.get_node("Brain") as BotBrain
	_reset([brain])
	bot.global_position = player.global_position + Vector3(0, 0, 40)
	brain.post_to(player.global_position + Vector3(0, 0, 100), 10.0)
	Combat.noise(player, player.global_position, 120.0)
	t.check(brain.state == BotBrain.State.PATROL and brain._alert_left > 0.0,
			"a shot far past a bot's post turns its head but not its feet")
	t.check(not brain._within_leash(player.global_position) and brain._within_leash(brain.home() + Vector3(20, 0, 0)),
			"its leash runs from its post")
	_reset([brain])
	await t.frames(1)


## A callout tells squadmates nearby where the person is now, once.
static func _callout(t: Node, player: Actor, soldiers: Array[Actor]) -> void:
	var spotter := soldiers[0]
	var mate := soldiers[1]
	var far := soldiers[2]
	var brains := _brains([spotter, mate, far] as Array[Actor])
	_reset(brains)
	far.faction = spotter.faction
	mate.faction = spotter.faction
	var at := player.global_position
	spotter.global_position = at + Vector3(15, 0, 0)
	mate.global_position = spotter.global_position + Vector3(0, 0, 10)
	far.global_position = spotter.global_position + Vector3(0, 0, brains[0].callout_range + 15.0)
	for i in brains.size():
		brains[i].post_to(brains[i].actor.global_position, 12.0)
	brains[0]._called_at = -1000.0
	brains[0].target = player
	brains[0]._new_contact()
	t.check(brains[1].state == BotBrain.State.PATROL, "nobody is told before the spotter has reacted")
	brains[0]._call_out(player)
	t.check(brains[1].state == BotBrain.State.CHASE and brains[1]._last_seen.distance_to(at) < 0.5,
			"a squadmate nearby comes to where the person was called out")
	t.check(brains[2].state == BotBrain.State.PATROL and brains[2]._alert_left <= 0.0,
			"one past the callout's range hears nothing")
	# Not live tracking: the person moves on, the squadmate still goes to the old place.
	player.global_position += Vector3(0, 0, -20)
	t.check(brains[1]._last_seen.distance_to(at) < 0.5, "a callout is a snapshot, never tracking")
	player.global_position = at
	brains[1].state = BotBrain.State.PATROL
	brains[0]._call_out(player)
	t.check(brains[1].state == BotBrain.State.PATROL, "a bot calls out at most every few seconds")
	_reset(brains)
	await t.frames(1)


## Lost contact is searched for, then let go.
static func _search(t: Node, player: Actor, soldiers: Array[Actor]) -> void:
	var bot := soldiers[3]
	var brain := bot.get_node("Brain") as BotBrain
	_reset([brain])
	bot.global_position = player.global_position + Vector3(10, 0, 0)
	brain.post_to(bot.global_position, 12.0)
	brain.hear_callout(player.global_position, player)
	t.check(brain.state == BotBrain.State.CHASE, "told of a person, a bot goes to look")
	var cmd := bot.cmd
	brain._lost(cmd, DT)
	t.check(not brain._search.is_empty() and brain._search.size() >= 2,
			"it plans where to look: the last sighting and round it (%d)" % brain._search.size())
	t.check(cmd.move.length() > 0.0, "and sets off")
	brain._lost_time = brain.give_up_time + 0.1
	brain._lost(cmd, DT)
	t.check(brain.state == BotBrain.State.PATROL and brain._alert_left > 0.0 and brain._contact_id == 0,
			"after a while it gives up and goes back to its ground")
	_reset([brain])
	await t.frames(1)


static func _prefers_army(t: Node) -> void:
	var brain := BotBrain.new()
	t.check(brain.person_bias > 1.0, "an army fights the other army first: a person at the same range is second choice")
	brain.free()


## A grenade landing beside a bot sends it running.
static func _dodge(t: Node, bot: Actor) -> void:
	var brain := bot.get_node("Brain") as BotBrain
	brain.dodge_chance = Vector2(1.0, 1.0)
	var before := Gun.live_rounds.size()
	var shot := Gun.Round.new()
	shot.kind = "grenade"
	shot.splash_radius = 4.0
	shot.velocity = Vector3.ZERO
	bot.get_parent().add_child(shot)
	shot.global_position = bot.global_position + Vector3(2.0, 0.5, 0.0)
	t.check(Gun.live_rounds.has(shot), "a grenade in flight is known to bots")
	brain._think_danger()
	t.check(brain._dodge_left > 0.0, "a bot beside a grenade runs from it")
	var cmd := bot.cmd
	cmd.move = Vector2.ZERO
	brain._dodge(cmd, DT)
	var dir := Basis(Vector3.UP, cmd.yaw) * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	t.check(dir.dot(bot.global_position - shot.global_position) > 0.0 and cmd.sprint, "away from it, at a sprint")
	brain._dodge_left = 0.0
	brain.dodge_chance = Vector2(0.45, 0.9)
	shot.get_parent().remove_child(shot)
	shot.free()
	t.check(Gun.live_rounds.size() == before, "and forgets it once it is gone")


## An army's commander: what a site is worth, and teams spread over several.
static func _commander(t: Node, raid: Raid) -> void:
	var boss := WarCommander.new()
	var sites := raid.strongpoints
	var point: Raid.Strongpoint = sites[0]
	var keep := [point.holder, point.contested, point.taker]
	var from := point.global_position + Vector3(60, 0, 0)
	point.holder = "faction:legion"
	point.contested = false
	point.taker = ""
	t.check(boss.worth("legion", point, from, {}, false) == 0.0, "a site of its own nobody is taking needs no team")
	point.contested = true
	var defend := boss.worth("legion", point, from, {}, false)
	point.contested = false
	point.holder = ""
	var open := boss.worth("legion", point, from, {}, false)
	point.holder = "faction:tide"
	var theirs := boss.worth("legion", point, from, {}, false)
	t.check(defend > open and open > theirs, "defending comes first, then open ground, then the other army's")
	var held_hard := boss.worth("legion", point, from, {"tide": 6, "legion": 6}, false)
	t.check(held_hard < theirs, "a site held hard is worth less")
	var losing := boss.worth("legion", point, from, {"tide": 6, "legion": 2}, false)
	t.check(losing < held_hard * 0.5, "a fight being lost stops drawing teams")
	t.check(boss.worth("legion", point, from, {}, true) > theirs * 1.5, "a storm over a site makes it a push")
	point.holder = keep[0]
	point.contested = keep[1]
	point.taker = keep[2]
	# Fireteams: everyone in one, about the team size each, nobody alone.
	var army: Array = []
	for bot in raid.bots:
		if army.size() < 23:
			army.append(bot)
	var groups := boss.fireteams(army)
	var count := 0
	var smallest := 99
	for group: Array in groups:
		count += group.size()
		smallest = mini(smallest, group.size())
	t.check(count == army.size() and smallest > boss.team_size / 2, "every soldier marches in a fireteam (%d teams)" % groups.size())
