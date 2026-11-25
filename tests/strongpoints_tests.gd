extends RefCounted
## The `strongpoints` checks. The test runner finds this file by itself and calls
## `run(t)`.

const Strongpoint := preload("res://core/war/strongpoint.gd")
const NET_ACCOUNTS := "user://test_accounts_net"


static func run(t: Node) -> void:
	print("Strongpoints")
	# One site on its own.
	var site := Strongpoint.new()
	site.title = "Mill"
	site.capture_time = 10.0
	t.add_child(site)
	t.check(site.covers(Vector3(5, 2, 5)) and not site.covers(Vector3(40, 0, 0)) and not site.covers(Vector3(0, 90, 0)),
			"a site covers the ground around it, not the sky far above")
	var red := {"red": {"count": 1, "name": "Red", "player": true}}
	t.check(not site.tick(4.0, red) and site.taker == "red" and is_equal_approx(site.progress, 0.4), "standing in a site alone starts taking it")
	t.check(site.status(false) == "Mill: unclaimed, Red taking it 40%", "its status says who is taking it")
	var both := red.duplicate()
	both["blue"] = {"count": 2, "name": "Blue", "player": false}
	site.tick(50.0, both)
	t.check(site.contested and is_equal_approx(site.progress, 0.4), "two sides inside freeze it")
	site.tick(1.0, {})
	t.check(not site.contested and is_equal_approx(site.progress, 0.2), "an abandoned capture drains away")
	t.check(site.tick(8.0, red) and site.holder == "red" and site.holder_is_player and site.progress == 0.0, "finishing the capture takes the site")
	t.check(site.status(true) == "Mill: yours" and site.status(false) == "Mill: held by Red", "its status says who holds it")
	var crowd := {"blue": {"count": 3, "name": "Blue", "player": false}}
	site.tick(4.0, crowd)
	t.check(is_equal_approx(site.progress, 0.6), "a crowd takes a site faster")
	site.tick(1.0, red)
	t.check(site.taker == "blue" and site.progress < 0.6, "the holder standing in it pushes a capture back")
	site.queue_free()

	# In a running co-op world.
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	# Tried with an army walking the valley, as Frostline had before its
	# pockets (`pocket_tests` has those): put back at the end.
	var frost := Worlds.get_world("frostline")
	var kept := [frost.bot_count, frost.pocket_wake]
	frost.bot_count = 22
	frost.pocket_wake = 0.0
	raid.start_server(frost, 97)
	t.check(raid.strongpoints.size() == 3 and raid.strongpoints[0].title == "Echo Post"
			and raid.strongpoints.all(func(p: Strongpoint) -> bool: return p.holder == "faction:warden" and not p.holder_is_player),
			"Frostline has three strongpoints, held by the Wardens to begin with")
	for i in raid.bots.size():
		var bot := raid.bots[i]
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(400 + i * 4, 0, 400)
	var point := raid.strongpoints[0]
	for p in raid.strongpoints:
		p.capture_time = 0.3
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var a := raid.add_player([], {}, "Alpha", "acct-a")
	var b := raid.add_player([], {}, "Bravo", "acct-b")
	a.set_physics_process(false)
	b.set_physics_process(false)
	b.global_position = Vector3(-300, 0, -300)
	var notices: Array[String] = []
	a.notice.connect(func(text: String) -> void: notices.append(text))
	a.global_position = point.global_position + Vector3(2, 0, 0)
	t.check(raid.strongpoint_at(a) == point and Hud.sites_text(raid, a) == "Echo Post: held by the Wardens", "the HUD names the site you stand in")
	await t.frames(40)
	t.check(point.holder == "players" and point.holder_is_player and raid.holds(a, point) and raid.holds(b, point),
			"in a co-op world a site one player takes belongs to them all")
	t.check(feed.has("The raiders took Echo Post from the Wardens"), "taking a site from the bots is announced (%s)" % " / ".join(feed))
	t.check(a.renown == 150 and b.renown == 0 and notices.has("Took Echo Post   +150 renown"), "the players who were there are paid renown")
	t.check(Hud.sites_text(raid, a) == "Echo Post: yours" and Hud.sites_text(raid, b) == "Held 1/3",
			"the HUD shows what you hold")
	var warden: Actor = raid.bots.filter(func(bot: Actor) -> bool: return bot.faction == "warden")[0]
	warden.global_position = point.global_position + Vector3(-3, 0, 0)
	await t.frames(5)
	t.check(point.contested and point.holder == "players" and "contested" in Hud.sites_text(raid, a), "an enemy walking in contests it")
	a.global_position = Vector3(-300, 0, -280)
	await t.frames(40)
	t.check(point.holder == "faction:warden" and not raid.holds(a, point) and feed.has("The Wardens took Echo Post from the raiders"),
			"bots left alone in a site take it back, and everyone hears")
	warden.global_position = Vector3(380, 0, 400)
	a.global_position = point.global_position
	await t.frames(40)
	t.check(raid.holds(a, point), "and it can be taken again")

	# A site you hold is where you drop in.
	var c := raid.add_player([], {}, "Charlie", "acct-c")
	t.check(point.covers(c.global_position), "a player drops in at a strongpoint their side holds")
	warden.global_position = point.global_position + Vector3(-3, 0, 0)
	await t.frames(3)
	var d := raid.add_player([], {}, "Delta", "acct-d")
	t.check(not point.covers(d.global_position), "but not at one that is being fought over")
	warden.global_position = Vector3(380, 0, 400)
	await t.frames(3)

	# The bots push back.
	for bot in raid.bots:
		(bot.get_node("Brain") as BotBrain).post_to(Vector3.ZERO, 10.0)
	raid._assault_in = 0.0
	await t.frames(2)
	var sent := raid.bots.filter(func(bot: Actor) -> bool:
		return (bot.get_node("Brain") as BotBrain)._home.distance_to(point.global_position) < 0.1)
	t.check(feed.has("Echo Post is under attack") and sent.size() == Worlds.get_world("frostline").assault_size,
			"every so often bots are sent to retake a site players hold (%d sent)" % sent.size())
	await t._end_raid(raid)
	frost.bot_count = kept[0]
	frost.pocket_wake = kept[1]

	# Where players fight each other, a site is its taker's alone.
	var pvp := Raid.new()
	t.add_child(pvp)
	pvp.apply_to_profile = false
	pvp.start_server(Worlds.get_world("ashfront"), 98)
	var e := pvp.add_player([], {}, "Echo", "acct-e")
	var f := pvp.add_player([], {}, "Fox", "acct-f")
	t.check(pvp.side_of(e)[0] == "acct-e" and pvp.side_of(e)[0] != pvp.side_of(f)[0] and pvp.side_of(e)[2],
			"in a PvP world every player is their own side")
	t.check(pvp.side_of(pvp.bots[0])[0] == "faction:" + pvp.bots[0].faction and not pvp.side_of(pvp.bots[0])[2],
			"and each bot faction is one")
	await t._end_raid(pvp)

	# Online: a client hears who holds each site.
	t._wipe_dir(NET_ACCOUNTS)
	var port := 24831
	# With the zone rules on, so the cold runs (Frostline has no gates or
	# burning ground for them to get in the way).
	var pid: int = t._start_server(port, ["--bots", "0", "--zone-rules"], "frostline")
	var gale: NetSession = await t._join("Gale", port)
	t.check(gale != null, "a client joins a world with strongpoints")
	if gale != null:
		var told := func() -> bool:
			return gale.raid.strongpoints.size() == 3 and gale.raid.strongpoints.all(
					func(p: Strongpoint) -> bool: return p.holder_name == "the Wardens")
		await t._wait_until(told, 180)
		t.check(told.call() and Hud.sites_text(gale.raid, gale.raid.player) == "Held 0/3",
				"the server tells a client who holds each strongpoint")
		var heard := func() -> bool:
			var me := gale.raid.player
			return me != null and (me.body_heat < me.max_body_heat or me.warming)
		await t._wait_until(heard, 240)
		t.check(heard.call(), "in the cold, the server tells a client their body heat")
		var printed := func() -> bool:
			return gale.raid.tracks.count() > 0
		await t._wait_until(printed, 240)
		t.check(printed.call(), "and sends it the footprints near it in the snow")
		await t._leave(gale)
	OS.kill(pid)
	await t.frames(10)
