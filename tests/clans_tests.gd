extends RefCounted
## The `clans` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Clans: players who stand together")
	const ClanPanel := preload("res://core/social/clan_panel.gd")
	var clans := ClanService.new()
	clans.persist = false
	var names := func(id: String) -> String: return id.capitalize()
	t.check(not clans.create("ada", "x", "WLF").ok and not clans.create("ada", "Wolves", "!").ok
			and not clans.create("", "Wolves", "WLF").ok, "a clan needs a real name, a tag and a founder")
	var made := clans.create("ada", "  The   Wolves ", "w-lf!")
	t.check(made.ok and clans.name_of(made.clan) == "The Wolves" and clans.tag_of(made.clan) == "WLF",
			"founding a clan cleans its name and tag")
	t.check(not clans.create("bo", "the wolves", "XX").ok and not clans.create("bo", "Others", "wlf").ok,
			"names and tags are not shared")
	t.check(not clans.create("ada", "Second", "SEC").ok and not clans.join("ada", made.clan).ok,
			"an account is in one clan at most")
	t.check(clans.join("bo", made.clan).ok and clans.clan_of("bo") == made.clan and not clans.join("cy", "nope").ok,
			"others join it by id")
	clans.max_members = 2
	t.check(not clans.join("cy", made.clan).ok, "a full clan takes nobody")
	clans.max_members = 24
	var seen: Dictionary = clans.snapshot("bo", names)
	t.check(seen.clan.name == "The Wolves" and seen.clan.members == ["Ada", "Bo"] and seen.clan.leader == "Ada"
			and not seen.clan.is_leader and seen.clans.size() == 1 and seen.clans[0].members == 2
			and not str(seen).contains("ada"), "a member sees the roster by name, never by account")
	t.check(ClanPanel.lines(seen)[0] == "[WLF] The Wolves" and ClanPanel.lines(seen)[1] == "Ada  (leader)"
			and ClanPanel.lines(clans.snapshot("cy", names)) == ["[WLF] The Wolves  2 members"]
			and ClanPanel.lines({})[0].begins_with("No clans"), "the hall's screen lists it")
	t.check(clans.leave("ada").ok and clans.snapshot("bo", names).clan.is_leader and clans.clan_of("ada") == "",
			"when the leader goes the next member leads")
	t.check(clans.leave("bo").ok and clans.snapshot("bo", names).clans.is_empty() and not clans.leave("bo").ok,
			"a clan with nobody left is gone")

	# Saved and read back.
	var dir := "user://test_clans"
	t._wipe_dir(dir)
	var saved := ClanService.new()
	saved.open(dir, true)
	var kept: String = saved.create("ada", "Keepers", "KEEP").clan
	saved.join("bo", kept)
	var again := ClanService.new()
	again.open(dir, true)
	t.check(again.clan_of("bo") == kept and again.members_of(kept) == ["ada", "bo"] and again.tag_of(kept) == "KEEP"
			and not again.create("cy", "Keepers", "K2").ok, "clans are saved with the accounts")
	t._wipe_dir(dir)

	# In a warzone clanmates are one side.
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 3)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	raid.set_team("acct-a", "c1", "Wolves")
	raid.set_team("acct-b", "c1", "Wolves")
	var a := raid.add_player([], {}, "Ada", "acct-a")
	var b := raid.add_player([], {}, "Bo", "acct-b")
	var c := raid.add_player([], {}, "Cy", "acct-c")
	for actor: Actor in [a, b, c]:
		actor.set_physics_process(false)
		actor.protected_left = 0.0
	a.clan = "c1"
	b.clan = "c1"
	t.check(raid.side_of(a)[0] == raid.side_of(b)[0] and raid.side_of(a)[1] == "Wolves"
			and raid.side_of(c)[0] != raid.side_of(a)[0] and Visor.allied(a, b) and not Visor.allied(a, c),
			"clanmates are one side, and a stranger is not")
	if not raid.strongpoints.is_empty():
		var point := raid.strongpoints[0]
		point.hold(raid.side_of(a)[0], "Wolves", true)
		t.check(raid.holds(b, point) and not raid.holds(c, point), "ground one clanmate takes is held by the clan")
		t.check("point:%d" % point.index in raid.drop_choices("acct-b").map(func(d: Dictionary) -> String: return d.id)
				and "point:%d" % point.index not in raid.drop_choices("acct-c").map(func(d: Dictionary) -> String: return d.id),
				"and a clanmate can drop in on it")
	var before := b.health.health
	t.check(not Combat.deal(b, DamageInfo.make(20.0, a, "bullet")) and b.health.health == before,
			"clanmates cannot hurt each other")
	t.check(Combat.deal(c, DamageInfo.make(20.0, a, "bullet")) and Combat.deal(a, DamageInfo.make(5.0, c, "bullet")),
			"everyone else is fair game")
	raid.set_team("acct-b", "")
	t.check(raid._player_side("acct-b") == "acct-b", "leaving the team puts a player back on their own")
	raid.queue_free()
	await t.frames(2)
