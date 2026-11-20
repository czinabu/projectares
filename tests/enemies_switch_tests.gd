extends RefCounted
## The enemies switch (`Raid.enemies`): with it off, a world starts and
## stays without enemies (armies, bosses, guards, raiders, the events that
## bring bots) and keeps the rest; on again, the same world fights as it
## did. Every enemy system stays in the code.


static func run(t: Node) -> void:
	print("Enemies switch")
	_wanted(t)
	for id: String in ["ashfront", "marsh", "rift"]:
		await _world_without(t, id)
	await _back_on(t)


static func _wanted(t: Node) -> void:
	var was := OS.get_environment("ARES_ENEMIES")
	OS.set_environment("ARES_ENEMIES", "")
	t.check(not Raid.enemies_wanted(PackedStringArray()),
			"by default (the project's stability pass) enemies are off")
	t.check(Raid.enemies_wanted(PackedStringArray(["--enemies"])), "--enemies turns them on")
	t.check(Raid.enemies_wanted(PackedStringArray(["--bots", "40"])), "and asking for bots does too")
	t.check(not Raid.enemies_wanted(PackedStringArray(["--bots", "40", "--no-enemies"])), "--no-enemies wins")
	OS.set_environment("ARES_ENEMIES", "1")
	t.check(Raid.enemies_wanted(PackedStringArray()), "a server inherits ARES_ENEMIES=1 from what started it")
	OS.set_environment("ARES_ENEMIES", was)


static func _world_without(t: Node, id: String) -> void:
	Raid.enemies = false
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world(id), 77)
	await t.frames(5)
	t.check(raid.bots.is_empty(), "%s starts with no enemies (%d bots)" % [id, raid.bots.size()])
	t.check(raid.player != null and not raid.player.is_dead, "%s still has its player" % id)
	t.check(not raid.start_event("warlord") and not raid.start_event("convoy") and not raid.start_event("airship"),
			"%s brings no bots in an event" % id)
	# Time passes: reinforcements, raiders and respawns all come due.
	raid._reinforce_in = 0.0
	raid._raider_in = 0.0
	for i in 120:
		raid._tick_bots(1.0)
		raid._tick_raiders(1.0)
		raid._tick_bosses(1.0)
		raid._tick_guards(1.0)
	t.check(raid.bots.is_empty() and raid.raiders.is_empty(), "%s stays empty as time passes" % id)
	t.check(raid.army_size() == 0 and raid.bot_target() == 0, "%s wants no army" % id)
	raid.queue_free()
	await t.frames(2)
	Raid.enemies = true


static func _back_on(t: Node) -> void:
	Raid.enemies = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("marsh"), 77)
	await t.frames(3)
	t.check(raid.bots.size() >= Worlds.get_world("marsh").bot_count,
			"switched on, the same world has its army back (%d bots)" % raid.bots.size())
	raid.queue_free()
	await t.frames(2)
