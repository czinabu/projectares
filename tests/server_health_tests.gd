extends RefCounted
## The `server_health` checks. The test runner finds this file by itself and calls
## `run(t)`.
##
## DEV MODE: the temporary testing mode (`core/dev/dev_mode.gd`). Delete this
## group along with it.


static func run(t: Node) -> void:
	print("Server health line")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	raid.add_player([], {}, "Pat", "pat")
	var session := NetSession.new()
	session.world_id = "ashfront"
	session.raid = raid
	var health := ServerHealth.new()
	health.sessions = [session] as Array[NetSession]
	health.sink = func(_line: String) -> void: pass
	t.add_child(health)
	await t.frames(3)
	var line := health.report()
	t.check(line.begins_with("Health: up "), "the health line starts with Health")
	t.check("ashfront 1 players %d bots" % raid.bots.size() in line,
			"the health line counts the players and bots in each session")
	t.check(" ms of %.1f" % ServerHealth.budget_ms() in line, "the health line gives the tick budget")
	health.queue_free()
	session.free()
	await t._end_raid(raid)
