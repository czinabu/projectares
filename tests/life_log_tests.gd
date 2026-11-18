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
