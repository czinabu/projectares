extends RefCounted
## Checks for the war's artillery (DESIGN.md "Shelling"): salvos come down
## near the fighting, sooner the hotter the war, each spot marked before its
## shell lands; the shells hurt anyone near with nothing between, never a
## gate outpost, a spawn or a fresh arrival, and bots run from the mark.
## Kept in its own file and called from the test runner.

const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]


static func run(t: Node) -> void:
	_settings(t)
	# The test runner turns the zone rules off for everything else.
	Raid.zone_rules = true
	await _salvo(t)
	Raid.zone_rules = false


static func _settings(t: Node) -> void:
	print("Shelling: which worlds")
	t.check(Worlds.get_world("ashfront").shelling > 0.0, "Ashfront is shelled")
	for id: String in ["frostline", "plaza", "meridian"]:
		var world := Worlds.get_world(id)
		t.check(world == null or world.shelling == 0.0, "%s is not shelled" % id)
	t.check(Arena.ArenaVenue.new().shelling == 0.0, "nor is the arena")
	var shells := Shelling.new()
	t.check(shells.gap(1.0, 1.0) < shells.gap(0.0, 1.0) and shells.gap(0.0, 2.0) < shells.gap(0.0, 1.0),
			"salvos come sooner the hotter the war and the higher the world's rate")


static func _salvo(t: Node) -> void:
	print("Shelling: a salvo")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 63)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	var me := raid.add_player(KIT, {}, "Gunner", "gunner")
	var far := raid.add_player(KIT, {}, "Watcher", "watcher")
	await t.frames(3)
	var spot := raid._stand(Vector3(-150, 0, 40))
	me.global_position = spot
	far.global_position = raid._stand(spot + Vector3(0, 0, 40))
	# Walking out of the gate they arrived at gives a moment's protection.
	await t.frames(10)
	me.protected_left = 0.0
	far.protected_left = 0.0
	var called: Array = []
	var landed: Array[Vector3] = []
	raid.shells_called.connect(func(points: PackedVector3Array, lands_in: PackedFloat32Array) -> void:
		called.append([points, lands_in]))
	raid.shell_landed.connect(func(at: Vector3) -> void: landed.append(at))
	var shells := raid.shelling
	shells.shells = Vector2i(3, 3)
	var points := shells.call_at(raid, spot + Vector3(2, 0, 0), PI * 0.5)
	t.check(points.size() == 3 and called.size() == 1 and (called[0][1] as PackedFloat32Array)[0] == shells.warning,
			"a salvo is called and every spot is told with the seconds until it lands")
	var marked := Gun.live_rounds.filter(func(n: Variant) -> bool: return n is Shelling.Marker)
	t.check(marked.size() == 3, "each marked spot is a burst bots run from")
	var whole := me.health.health + me.health.armor
	await t.frames(int(shells.warning * 60.0) - 20)
	t.check(landed.is_empty() and me.health.health + me.health.armor == whole,
			"nothing lands and nobody is hurt while the spots are marked")
	await t.frames(int((shells.stagger * 2.0 + 0.5) * 60.0) + 20)
	t.check(landed.size() == 3, "then the shells land one after another")
	t.check(me.is_dead or me.health.health + me.health.armor < whole, "and hurt the player they landed beside")
	t.check(far.health.health == far.health.max_health, "but not one 40 m off")
	t.check(Gun.live_rounds.filter(func(n: Variant) -> bool: return n is Shelling.Marker).is_empty(),
			"the marks are gone once they land")
	# Where no shell may land.
	var gate: Node3D = raid.outposts[0]
	t.check(not shells.clear(raid, gate.global_position + Vector3(10, 0, 0)), "never at a gate outpost")
	var start: Node3D = raid._map_nodes("spawn_player")[0]
	t.check(not shells.clear(raid, start.global_position), "nor on a player spawn")
	far.protected_left = 3.0
	t.check(not shells.clear(raid, far.global_position + Vector3(4, 0, 0)), "nor beside someone just dropped in")
	far.protected_left = 0.0
	t.check(shells.clear(raid, far.global_position + Vector3(4, 0, 0)), "but out in the open, anywhere")
	t.check(shells.surface(raid, Vector3(-150, 0, 40)).y == raid._stand(Vector3(-150, 0, 40)).y
			or absf(shells.surface(raid, Vector3(-150, 0, 40)).y - raid.map.call("ground_height", -150.0, 40.0)) < 0.5,
			"a shell strikes the ground where nothing stands over it")
	# Left to itself the raid calls salvos near the fighting.
	shells.first = 0.5
	shells.reset(5)
	called.clear()
	for bot in raid.bots:
		bot.global_position = raid._stand(Vector3(-60, 0, 0))
	await t.frames(60)
	t.check(called.size() == 1, "the raid calls a salvo of its own once it is due")
	raid.queue_free()
	await t.frames(2)
