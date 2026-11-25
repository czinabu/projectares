extends RefCounted
## Bots stay on the Basalt Rift's mesas. A patrol goal past a mesa's edge
## (or on another mesa) is walked to the edge's nearest walkable point and
## no further (`BotBrain._onto_nav`, `ARRIVE_STOP`). Before,
## most of the Rift's bots walked off a mesa and burned in the lava within
## a minute, with nobody there to fight them.


static func run(t: Node) -> void:
	print("Basalt Rift: bots stay on the mesas")
	var world := Worlds.get_world("rift")
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 7)
	var start := raid.bots.duplicate()
	var lowest := INF
	for bot: Actor in start:
		lowest = minf(lowest, bot.global_position.y)
	var map: Node3D = raid.map
	t.check(not start.is_empty() and lowest > map.LAVA_Y + 5.0,
			"rift: the bots start up on the mesas (%d of them)" % start.size())
	# 30 s of the bots' own patrols (the player stands still on the Shelf).
	var fell := 0
	var seen := {}
	for i in 30 * 60:
		await t.get_tree().physics_frame
		if i % 30 != 0:
			continue
		for bot: Variant in start:
			if not is_instance_valid(bot) or seen.has(bot):
				continue
			if (bot as Actor).global_position.y < map.LAVA_Y + 3.0:
				seen[bot] = true
				fell += 1
	t.check(fell == 0, "rift: no bot walks off a mesa into the lava in 30 s (%d did)" % fell)
	raid.queue_free()
	await t.frames(2)
