extends RefCounted
## The `world_heat` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("World heat: what a doorway says about the world behind it")
	const PlazaView := preload("res://core/social/plaza_view.gd")
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("frostline"), 0)
	var empty := raid.status()
	t.check(empty.players == 0 and empty.level == "Quiet" and empty.bounty == 0 and empty.event == "",
			"an empty world reports itself quiet")
	var a := raid.add_player([], {}, "Ada", "acct_a")
	raid.add_player([], {}, "Bo", "acct_b")
	a.bounty = 150
	raid.war.intensity = 0.62
	raid.start_event("warlord")
	var busy := raid.status()
	t.check(busy.players == 2 and busy.level == "Battle" and busy.bounty == 150 and busy.event != "",
			"a busy one reports players, war level, top bounty and event: %s" % PlazaView.heat_text(busy))
	var outside := busy.duplicate()
	var wanted: Array = outside.get("wanted", [])
	outside.erase("wanted")
	t.check(not str(outside).contains("Ada") and not busy.has("centre")
			and wanted.all(func(w: Dictionary) -> bool: return w.keys() == ["name", "clan", "bounty", "marked"]),
			"and never where anyone is: the only who is the most wanted's name and bounty")
	t.check(PlazaView.heat_text({}) == "" and PlazaView.heat_text(empty) == "QUIET   0 players",
			"the sign is blank until the server speaks, and short when nothing is on")
	t.check(PlazaView.heat_text(busy).contains("2 players") and PlazaView.heat_text(busy).contains("Top bounty 150")
			and PlazaView.heat_text({"players": 1, "level": "Skirmish"}) == "SKIRMISH   1 player",
			"it lists players and the top bounty")
	t.check(PlazaView.heat_color(1.0).g < PlazaView.heat_color(0.0).g, "the sign reddens as the war heats up")
	raid.queue_free()
	await t.frames(2)

	# A client cleans what it is told.
	var net := NetSession.new()
	t.add_child(net)
	net._world_status({"ashfront": {"players": -4, "war": 9.0, "level": "x".repeat(200), "bounty": "12"}, 7: {}, "bad": 3})
	var got: Dictionary = net.world_status.get("ashfront", {})
	t.check(net.world_status.size() == 1 and got.players == 0 and got.war == 1.0 and got.level.length() <= 24
			and got.bounty == 12, "a client cleans the status it is sent")
	net.queue_free()
	await t.frames(1)


## A squad portal in the plaza, online: Pia (`ada`) opens one from the
## watch and her clanmate Pax (`bo`) walks through it. The server decides.
