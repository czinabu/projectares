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
	await _budget(t)


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


static func _budget(t: Node) -> void:
	print("Enemy budget")
	var was := OS.get_environment("ARES_ENEMY_CAP")
	OS.set_environment("ARES_ENEMY_CAP", "")
	t.check(Raid.enemy_cap_wanted(PackedStringArray()) == 16, "the project's cap is 16 enemies a world")
	t.check(Raid.enemy_cap_wanted(PackedStringArray(["--enemy-cap", "40"])) == 40, "--enemy-cap sets another")
	OS.set_environment("ARES_ENEMY_CAP", was)
	Raid.enemies = true
	Raid.enemy_cap = 16
	Raid.near_full_cap = 4
	for id: String in ["ashfront", "marsh"]:
		var raid := Raid.new()
		t.add_child(raid)
		raid.start(Worlds.get_world(id), 77)
		await t.frames(3)
		t.check(raid.bots.size() <= 16 and raid.bots.size() >= 8,
				"%s starts within the cap (%d of %d its own)" % [id, raid.bots.size(), Worlds.get_world(id).bot_count])
		raid.war.intensity = 1.0
		raid._reinforce_in = 0.0
		raid._raider_in = 0.0
		for i in 200:
			raid._tick_bots(1.0)
			raid._tick_raiders(1.0)
			raid._tick_guards(1.0)
			raid._tick_bosses(1.0)
		raid.start_event("warlord")
		t.check(raid.bots.size() <= 16, "%s stays within it in a hot war (%d)" % [id, raid.bots.size()])
		# Everyone near the player: only the nearest 4 think every tick.
		for k in raid.bots.size():
			raid.bots[k].global_position = raid.player.global_position + Vector3(3.0 + k, 0.0, 0.0)
		raid._detail_in = 0.0
		raid._tick_detail(0.1)
		var full := raid.bots.filter(func(b: Actor) -> bool: return b.tick_every == 1).size()
		t.check(full == mini(4, raid.bots.size()), "%s: %d of the %d bots beside the player run every tick" % [id, full, raid.bots.size()])
		raid.queue_free()
		await t.frames(2)
	Raid.enemy_cap = 0
	Raid.near_full_cap = 0
