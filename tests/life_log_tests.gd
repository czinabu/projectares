extends RefCounted
## The life log (DESIGN.md "Challenge and balance data"): every life a
## player finishes leaves one line saying where and how it ended. Called
## from the test runner.

const Report := preload("res://tests/life_report.gd")


static func run(t: Node) -> void:
	print("Life log: where lives end")
	Profile.reset()
	var dir := OS.get_user_data_dir().path_join("test_life_log")
	_clear(dir)
	var was := LifeLog.directory
	LifeLog.directory = dir
	var raid: Raid = await t._new_raid(46, false)
	var p := raid.player
	var bot := raid.bots[0]
	var brain := bot.get_node("Brain") as BotBrain
	brain.target = p
	raid.clock += 42.0
	p.inventory.add_item("lattice_shard")
	Combat.deal(p, DamageInfo.make(9999.0, bot, "bullet"))
	await t.frames(2)
	var line: Dictionary = raid.life_log.recent.back() if not raid.life_log.recent.is_empty() else {}
	var kind := "%s:%s" % [bot.faction, str(bot.get_meta("kind", "soldier"))]
	t.check(line.get("outcome") == "died" and line.get("world") == "ashfront" and line.get("killer") == kind,
			"a death leaves a line naming the world and the kind of bot that did it")
	t.check(int(line.get("hunters", 0)) >= 1, "it counts the bots that were after the player")
	t.check(float(line.get("alive", 0.0)) >= 42.0 and int(line.get("zone", -1)) == raid.world.zone_at(p.global_position),
			"it says how long the life ran and which risk zone it ended in")
	t.check(int(line.get("carried_value", 0)) >= ItemDB.total_value(["lattice_shard"]),
			"it says what the body carried")

	var again := raid.add_player([], {}, "You")
	await t.frames(2)
	var state := raid.state_for(again)
	state.last_combat = -INF
	raid.begin_sign_out(again)
	raid._tick_sign_outs(60.0)
	await t.frames(2)
	var left: Dictionary = raid.life_log.recent.back()
	t.check(left.get("outcome") == "left" and left.get("killer") == "" and int(left.get("hunters", -1)) == 0,
			"a sign-out leaves a line too, with no killer")

	var read := LifeLog.read_all(dir, "ashfront")
	t.check(read.size() == 2, "both lines were written to the day's file")
	var summary := Report.summarize(read)
	t.check(summary.lives == 2 and summary.died == 1 and summary.left == 1,
			"the report counts the lives, deaths and sign-outs")
	t.check(summary.killers.get(kind, 0) == 1, "and what killed whom")
	await t._end_raid(raid)

	# Clients and safe zones keep no log.
	LifeLog.directory = ""
	var quiet: Raid = await t._new_raid(47, false)
	var before := LifeLog.read_all(dir).size()
	Combat.deal(quiet.player, DamageInfo.make(9999.0, quiet.bots[0], "bullet"))
	await t.frames(2)
	t.check(quiet.life_log.recent.size() == 1 and LifeLog.read_all(dir).size() == before,
			"with no folder set the line is kept in memory only")
	await t._end_raid(quiet)
	LifeLog.directory = was
	_clear(dir)


static func _clear(dir: String) -> void:
	var listing := DirAccess.open(dir)
	if listing == null:
		return
	for name in listing.get_files():
		listing.remove(name)


## An army's push warns first (DESIGN.md "Challenge and balance data"): a
## horn and a war feed line, and an arrow on the watch map.
static func pushes(t: Node) -> void:
	print("Army pushes: told before they land")
	var raid: Raid = await t._new_raid(48, false)
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var heard: Array[bool] = []
	raid.army_pushed.connect(func(_s: int, _f: Vector3, _t: String, loud: bool) -> void: heard.append(loud))
	var army: Array = raid.bots.filter(func(b: Actor) -> bool: return b.faction == "legion")
	t.check(army.size() >= Raid.PUSH_MIN, "the Legion has enough bots to push")
	# As if the world had just begun: no orders given yet.
	raid._push_target.clear()
	raid._push_loud_at.clear()
	raid.pushes.clear()
	raid._note_army_target("legion", raid.strongpoints[0], army)
	t.check(heard.is_empty() and feed.is_empty(), "the first orders of a world are set quietly")
	raid._note_army_target("legion", raid.strongpoints[1], army)
	t.check(heard == [true] and feed.size() == 1 and feed[0].begins_with("The Legion is pushing on ")
			and feed[0].contains(raid.strongpoints[1].title),
			"a new push is announced, by the army's name: %s" % [feed])
	var marks := Hud.map_marks(raid, raid.player)
	t.check(marks.pushes.size() == 1, "the watch map draws the push as an arrow")
	raid._note_army_target("legion", raid.strongpoints[2], army)
	t.check(heard == [true, false] and feed.size() == 1 and raid.live_pushes().size() == 1
			and int(raid.live_pushes()[0].site) == 2,
			"a change soon after only moves the arrow, without another horn")
	raid._note_army_target("legion", raid.strongpoints[2], army.slice(0, 1))
	t.check(heard.size() == 2, "the same target again is no news")
	raid.clock += Raid.PUSH_SHOWN + 1.0
	t.check(raid.live_pushes().is_empty() and Hud.map_marks(raid, raid.player).pushes.is_empty(),
			"after a minute the arrow is gone")
	await t._end_raid(raid)


## Fresh players land away from strong ones (DESIGN.md "Challenge and
## balance data"): someone who brought little gear arrives at the gate
## furthest from anyone who came in strong.
static func fresh_drops(t: Node) -> void:
	print("Fresh players land away from strong ones")
	var raid := Raid.new()
	t.add_child(raid)
	raid.mode = Raid.Mode.SERVER
	raid.start_server(Worlds.get_world("ashfront"), 49)
	await t.frames(3)
	var strong_kit: Array[String] = ["dmr_longshot", "frame_bulwark", "helm_warden", "jetpack_mk2",
			"pistol_hand_cannon", "blade_arc"]
	var mid_kit: Array[String] = ["rifle_carbine", "frame_trooper", "helm_spotter", "jetpack_mk1",
			"pistol_machine", "knife_gutter"]
	var strong := raid.add_player(strong_kit, {}, "Ace", "ace")
	var other := raid.add_player(mid_kit, {}, "Bo", "bo")
	await t.frames(2)
	t.check(raid.is_strong(raid.state_for(strong)) and not raid.is_strong(raid.state_for(other))
			and not raid.is_fresh(raid.state_for(other)),
			"a crafted kit counts as strong, a mid kit as neither")
	for bot in raid.bots:
		bot.global_position = Vector3(0, -5000, 0)
	var spawns := raid._map_nodes("spawn_player")
	var fresh := Raid.PlayerState.new()
	t.check(raid.is_fresh(fresh), "the scrap kit counts as fresh")
	var steady := Raid.PlayerState.new()
	steady.kit.assign(mid_kit)
	# The strong player stands at one gate and someone else at the gate
	# furthest from it: a plain arrival keeps clear of both, a fresh one
	# keeps further from the strong one.
	strong.global_position = spawns[0].global_position
	var far := 0
	for i in spawns.size():
		if spawns[i].global_position.distance_to(strong.global_position) \
				> spawns[far].global_position.distance_to(strong.global_position):
			far = i
	other.global_position = spawns[far].global_position
	var picked_fresh: Vector3 = spawns[raid._safest_spawn(spawns, fresh)].global_position
	var picked_plain: Vector3 = spawns[raid._safest_spawn(spawns, steady)].global_position
	var d_fresh := picked_fresh.distance_to(strong.global_position)
	var d_plain := picked_plain.distance_to(strong.global_position)
	t.check(d_fresh > d_plain + 1.0, "a fresh player lands further from the strong one (%.0f m against %.0f m)"
			% [d_fresh, d_plain])
	await t._end_raid(raid)
