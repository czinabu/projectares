extends RefCounted
## Checks for Ashfront's far war past the rim (DESIGN.md "The battle around
## you"): the "Far battle scenery" setting each graphics pick sets and what
## it thins, the battle shelves' steps, the horde laid on them, and the
## flares over real fights. The scenery army on the shelves is checked in
## `battle_tests.gd`.

const GameSettings := preload("res://core/settings/game_settings.gd")
const MAP := preload("res://worlds/ashfront/map.gd")
const HORDE := preload("res://worlds/ashfront/horde.gd")
const FLARES := preload("res://worlds/ashfront/flares.gd")


static func run(t: Node) -> void:
	print("Battle shelves: the far war past the rim")
	_setting(t)
	_shelves(t)
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	_horde(t, raid)
	_flares(t, raid)
	raid.queue_free()


static func _setting(t: Node) -> void:
	var was := GameSettings.persist
	GameSettings.persist = false
	GameSettings.ensure_loaded()
	var picks := [GameSettings.GRAPHICS_HIGH, GameSettings.GRAPHICS_MEDIUM, GameSettings.GRAPHICS_LOW, GameSettings.GRAPHICS_LOWEST]
	var shares: Array[float] = []
	for pick: int in picks:
		GameSettings.set_value("graphics", pick)
		shares.append(GameSettings.war_share())
	t.check(is_equal_approx(shares[0], 1.0) and is_equal_approx(shares[1], 1.0),
			"High and Medium keep the whole far war")
	t.check(shares[2] < 1.0 and shares[3] < shares[2] and shares[3] > 0.0,
			"Low thins it and Lowest thins it more, but neither turns it off")
	GameSettings.set_value("graphics", GameSettings.GRAPHICS_HIGH)
	GameSettings.persist = was


static func _shelves(t: Node) -> void:
	# Out along each shelf's middle, the flats climb step by step and sit
	# level, and between shelves the far land is left as it was.
	var climbs := true
	var level := true
	for shelf: Dictionary in MAP.SHELVES:
		var out: Vector2 = shelf["out"]
		var lateral: Vector2 = shelf["lateral"]
		var l := (lateral.x + lateral.y) * 0.5
		var last := -INF
		for flat: Vector2 in MAP.shelf_flats():
			var a := out * flat.x + Vector2(-out.y, out.x) * l
			var b := out * flat.y + Vector2(-out.y, out.x) * l
			var ha := MAP.FarLand.shelf(a.x, a.y)
			var hb := MAP.FarLand.shelf(b.x, b.y)
			climbs = climbs and ha.x > last + 10.0 and is_equal_approx(ha.y, 1.0)
			level = level and absf(ha.x - hb.x) < 1.0
			last = ha.x
	t.check(climbs, "each shelf climbs in steps away from the rim")
	t.check(level, "and each step's flat is level")
	t.check(MAP.FarLand.shelf(0.0, 500.0).y == 0.0 and MAP.FarLand.shelf(500.0, -200.0).y == 0.0,
			"the land between the shelves is left alone")


static func _horde(t: Node, raid: Raid) -> void:
	var horde: Node3D = raid.map.call("make_horde")
	horde.set_process(false)
	raid.map.add_child(horde)
	horde.call("build")
	var crowd := horde.get("_crowd") as MultiMeshInstance3D
	t.check(crowd != null and crowd.multimesh.instance_count == HORDE.FIGURES, "the horde lays all its figures once")
	var walls := float(raid.map.terrain.extent()) * 0.5 - 6.0
	var outside := true
	var grounded := true
	var spots: PackedVector3Array = horde.get("spots")
	for at in spots:
		outside = outside and maxf(absf(at.x), absf(at.z)) > walls + 20.0
		grounded = grounded and absf(at.y - float(raid.map.call("scenery_height", at.x, at.z))) < 0.5
	outside = outside and spots.size() == HORDE.FIGURES
	t.check(outside and grounded, "every figure stands on a shelf, past the walls")
	t.check(horde.get_child_count() == 2, "it is two draws: the crowd and its fire")
	horde.call("_process", 0.0)
	var full := crowd.multimesh.visible_instance_count
	GameSettings.war_scenery = 2
	horde.call("_process", 0.0)
	t.check(crowd.multimesh.visible_instance_count < full, "a lighter setting draws fewer figures")
	GameSettings.war_scenery = 0
	horde.queue_free()


static func _flares(t: Node, raid: Raid) -> void:
	var flares: Node3D = FLARES.new()
	raid.map.add_child(flares)
	flares.set_process(false)
	t.check(not flares.call("launch_over_fight"), "no flare goes up with no fight in sight")
	var ground := raid._stand(Vector3(40, 0, 40))
	var flare: Dictionary = flares.call("launch", ground)
	var top := 0.0
	var lit_seen := false
	for i in 40:
		flares.call("_tick_flares", 0.1)
		top = maxf(top, (flare.node as Node3D).global_position.y)
		lit_seen = lit_seen or (flare.light as OmniLight3D).light_energy > 0.5
	t.check(top > ground.y + 40.0 and lit_seen, "a flare climbs high over the fight and lights it")
	var high := (flare.node as Node3D).global_position.y
	for i in 30:
		flares.call("_tick_flares", 0.1)
	t.check((flare.node as Node3D).global_position.y < high, "it sinks as it burns")
	for i in 300:
		flares.call("_tick_flares", 0.1)
	t.check(flares.call("flares").is_empty(), "and burns out")
	flares.queue_free()
