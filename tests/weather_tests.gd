extends RefCounted
## Checks for the weather (DESIGN.md "Weather: ash storms"): a storm cell
## that crosses the map, cuts sight, scans and how far shots carry, pushes
## flight rigs with gusts, covers a push, and reaches clients as one small
## message. Run from the main test runner. Nothing here starts a server.

const NetSessionScript := preload("res://core/net/net_session.gd")
const Strongpoint := preload("res://core/war/strongpoint.gd")


static func run(t: Node) -> void:
	print("Weather: ash storms")
	_test_cell(t)
	_test_world_hooks(t)
	_test_soften(t)
	await _test_in_ashfront(t)


## A world with storms on, for the arithmetic.
static func _stormy() -> WorldDef:
	var world := WorldDef.new()
	world.weather_kind = "ash"
	world.weather_name = "Ash storm"
	return world


static func _test_cell(t: Node) -> void:
	var world := _stormy()
	var weather := Weather.new()
	weather.setup(world, 11)
	t.check(weather.kind == "" and not weather.active()
			and weather.next_in >= world.weather_first.x and weather.next_in <= world.weather_first.y,
			"a world starts in clear air, with the first storm a few minutes off")
	weather.tick(weather.next_in + 0.1)
	t.check(weather.kind == "ash" and weather.velocity.length() > 0.0 and weather.life > 60.0,
			"then a storm starts and moves")
	var from := weather.centre
	t.check(Vector2(from.x, from.z).length() >= world.weather_field,
			"it comes in from beyond the rim (%.0f m out)" % Vector2(from.x, from.z).length())
	weather.tick(world.weather_ramp * 0.5)
	var building := weather.strength
	weather.tick(world.weather_ramp)
	t.check(building > 0.2 and building < 0.8 and is_equal_approx(weather.strength, 1.0),
			"it builds up over its first %d s" % int(world.weather_ramp))
	t.check(weather.centre.distance_to(from) > 1.0, "and crosses the map")
	var middle := weather.centre
	t.check(is_equal_approx(weather.strength_at(middle), 1.0)
			and is_equal_approx(weather.strength_at(middle + Vector3(weather.radius * 0.5, 30.0, 0.0)), 1.0),
			"full strength over its core, at any height")
	var edge := weather.strength_at(middle + Vector3(weather.radius * 0.8, 0.0, 0.0))
	t.check(edge > 0.0 and edge < 1.0 and weather.strength_at(middle + Vector3(weather.radius + 1.0, 0.0, 0.0)) == 0.0,
			"its edge is soft, and outside it the air is clear")
	t.check(is_equal_approx(weather.sight_at(middle), world.weather_sight)
			and is_equal_approx(weather.carry_at(middle), world.weather_carry),
			"in the thick of it sight is cut to half and shots carry less")
	var outside := middle + Vector3(weather.radius * 2.0, 0.0, 0.0)
	t.check(weather.sight_at(outside) == 1.0 and is_equal_approx(weather.sight_between(middle, outside), world.weather_sight),
			"sight between two places is the worse of the two")
	# Gusts: an acceleration, never a jolt, and only where you are.
	var most := 0.0
	var varies := false
	var first := weather.gust_at(middle)
	for i in 40:
		var spot := middle + Vector3(i * 4.0 - 80.0, 10.0, i * 2.0 - 40.0)
		var gust := weather.gust_at(spot)
		most = maxf(most, gust.length())
		varies = varies or not gust.is_equal_approx(first)
		if i == 0:
			t.check(gust.is_equal_approx(weather.gust_at(spot)), "a gust depends only on where you are")
	t.check(most > world.weather_gust * 0.5 and most <= world.weather_gust * 1.4 and varies,
			"gusts push up to about %.0f m/s², rising and falling across the storm (%.1f)" % [world.weather_gust, most])
	t.check(weather.gust_at(outside) == Vector3.ZERO, "no gusts outside it")
	# The wire.
	var copy := Weather.new()
	copy.unpack(weather.pack())
	t.check(copy.kind == "ash" and copy.centre.is_equal_approx(weather.centre)
			and copy.velocity.is_equal_approx(weather.velocity) and is_equal_approx(copy.strength, weather.strength)
			and is_equal_approx(copy.strength_at(middle), weather.strength_at(middle)),
			"a client gets the whole cell in one small message")
	var at := copy.centre
	copy.advance(2.0)
	t.check(copy.centre.is_equal_approx(at + weather.velocity * 2.0), "and carries it on between updates")
	copy.unpack(["", 0.0, 0.0, 0.0, 0.0, 150.0, 0.7])
	t.check(copy.kind == "" and copy.strength == 0.0 and copy.strength_at(at) == 0.0, "an ended storm clears the air")
	# It ends once it has crossed, and the quiet spell starts.
	weather.tick(weather.life)
	t.check(weather.kind == "" and weather.strength_at(middle) == 0.0
			and weather.next_in >= world.weather_gap.x and weather.next_in <= world.weather_gap.y,
			"once it has crossed it ends, and the next comes after a quiet spell")
	var calm := Weather.new()
	calm.setup(WorldDef.new(), 3)
	calm.tick(100000.0)
	t.check(calm.kind == "", "a world without weather never has a storm")


static func _test_world_hooks(t: Node) -> void:
	var world := _stormy()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 20:
		var path := world.weather_path(rng)
		var a: Vector3 = path[0]
		var b: Vector3 = path[1]
		var mid := (a + b) * 0.5
		if Vector2(mid.x, mid.z).length() > world.weather_field * 0.6 or a.distance_to(b) < world.weather_field * 2.0:
			t.check(false, "a storm's path crosses near the middle of the map")
			return
	t.check(true, "a storm's path crosses near the middle of the map, rim to rim")
	var ashfront := Worlds.get_world("ashfront")
	t.check(ashfront.weather_kind == "ash" and ashfront.weather_pushes and ashfront.weather_name == "Ash storm",
			"Ashfront has ash storms that cover a push")
	for id in ["plaza", "arena"]:
		var other := Worlds.get_world(id)
		if other != null:
			t.check(other.weather_kind == "", "%s has no storms" % id)
	t.check(ItemDB.item_stats("wings_glide").gust_mult > ItemDB.item_stats("jetpack_mk1").gust_mult
			and ItemDB.item_stats("jetpack_mk1").gust_mult > ItemDB.item_stats("boots_thruster").gust_mult,
			"wings catch the wind worst, the jetpack less and boots barely")
	# The cold and tracks hooks Frostline's whiteouts use.
	world.weather_cold = 2.0
	var weather := Weather.new()
	weather.setup(world, 2)
	weather.start()
	weather.tick(world.weather_ramp)
	t.check(is_equal_approx(weather.cold_at(weather.centre), 2.0) and weather.cold_at(weather.centre
			+ Vector3(weather.radius * 3.0, 0, 0)) == 1.0, "a storm can make the cold bite harder in its thick")
	var tracks := Tracks.new()
	tracks.add(Vector3(0, 0, 0), 0.0, Tracks.Kind.LEFT, 0.0)
	tracks.add(Vector3(5, 0, 0), 0.0, Tracks.Kind.RIGHT, 0.0)
	tracks.add(Vector3(80, 0, 0), 0.0, Tracks.Kind.LEFT, 0.0)
	tracks.wipe(Vector3.ZERO, 30.0)
	t.check(tracks.count() == 1 and tracks.near(Vector3(80, 0, 0), 1.0).size() == 1,
			"a storm can wipe the tracks under it and leave the rest")


static func _test_soften(t: Node) -> void:
	var m := Look.mood_values({"fog_depth_begin": 0.0, "fog_depth_end": 10.0, "fog_density": 1.0})
	var soft := Look.soften_weather(m)
	t.check(soft.fog_depth_begin >= Look.weather_fog_begin_min and soft.fog_depth_end >= Look.weather_fog_solid_min
			and soft.fog_density <= Look.weather_depth_amount_cap, "a storm's fog never closes into the face")
	var war := Look.soften_storm(m)
	t.check(war.fog_depth_end > soft.fog_depth_end, "but it may close in further than the war's haze")
	var ashfront := Worlds.get_world("ashfront")
	t.check(ashfront.weather_sight <= 0.5, "bots and scans see half as far in the thick of an ash storm")
	# Caleb's pick: a body is a shape at 30 m and gone by 70 m at the heart.
	var at30 := Look.fog_amount_at(30.0, 1.0, 0.985, 4.0, 55.0, 0.8, true, 0.0, 0.0) * Look.actor_fog_keep(30.0)
	var at70 := Look.fog_amount_at(70.0, 1.0, 0.985, 4.0, 55.0, 0.8, true, 0.0, 0.0) * Look.actor_fog_keep(70.0)
	t.check(at30 < 0.75 and at70 > 0.95, "at its heart a body is a shape at 30 m (%.2f fog) and gone by 70 m (%.2f)" % [at30, at70])


static func _test_in_ashfront(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 31)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	await t.frames(3)
	t.check(raid.weather.kind == "" and raid.weather.next_in > 0.0, "Ashfront starts clear, a storm on its way")
	# A bot and a player 25 m apart, high over the field where nothing is in
	# the way, the bot facing the player.
	var bot: Actor = raid.bots[0]
	var p := raid.player
	p.set_physics_process(false)
	bot.global_position = Vector3(0, 90, 0)
	p.global_position = Vector3(0, 90, -25)
	bot.cmd.yaw = 0.0
	var brain := bot.get_node("Brain") as BotBrain
	t.check(brain._find_target() == p, "in clear air a bot spots someone 25 m off")
	raid.weather.start()
	raid.weather.centre = Vector3(0, 0, 0)
	raid.weather.velocity = Vector3(0.001, 0, 0)
	raid.weather.age = raid.world.weather_ramp * 2.0
	raid.weather.life = 10000.0
	raid.weather.strength = 1.0
	t.check(brain._find_target() == null, "in the thick of an ash storm it does not (sight %.0f m)"
			% (brain.sight_range * raid.weather.sight_at(bot.global_position)))
	p.global_position = Vector3(0, 90, -15)
	t.check(brain._find_target() == p, "but it still does up close")
	# Shots carry less in it.
	var gun: Gun = null
	for weapon in p.weapons:
		if weapon is Gun:
			gun = weapon
	if gun != null:
		var inside := gun.shot_carry()
		p.global_position = Vector3(raid.weather.radius * 2.0, 90, 0)
		t.check(inside < gun.shot_carry(), "a shot carries less inside the storm (%.2f against %.2f)" % [inside, gun.shot_carry()])
	# Gusts push a rig in the air, never a body on foot.
	p.global_position = Vector3(20, 90, 10)
	var push := raid.weather.gust_at(p.global_position)
	p.velocity = Vector3.ZERO
	p.call("_take_gusts", false, 0.1)
	t.check(p.flight.enabled and p.velocity.is_equal_approx(push * p.flight.gust_mult * 0.1) and p.velocity.length() > 0.0,
			"a storm's gusts push a flight rig in the air")
	p.velocity = Vector3.ZERO
	p.call("_take_gusts", true, 0.1)
	t.check(p.velocity == Vector3.ZERO, "and leave someone on the ground alone")
	# The watch and the plaza's signs say so.
	p.global_position = Vector3(10, 0, 10)
	t.check(raid.zone_label(p).ends_with("ash storm"), "the watch's zone line says you are in an ash storm (%s)" % raid.zone_label(p))
	t.check(raid.status().get("storm") == "Ash storm", "and the world's status says a storm is on")
	var marks := Hud.map_marks(raid, p)
	t.check(marks.get("storm") is Dictionary and float(marks.storm.radius) > 0.0, "the watch map draws the storm")
	# Cover for a push: an army goes for a storm-covered site over a nearer clear one.
	# Somewhere a nearer site and one a little further off are far enough
	# apart that a storm over the second leaves the first clear.
	var near_site: Strongpoint = null
	var far_site: Strongpoint = null
	var from := Vector3.ZERO
	if raid.strongpoints.size() >= 2:
		for gx in range(-12, 13):
			for gz in range(-12, 13):
				if far_site != null:
					break
				var spot := Vector3(gx * 20.0, 0.0, gz * 20.0)
				var sites := raid.strongpoints.duplicate()
				sites.sort_custom(func(a: Strongpoint, b: Strongpoint) -> bool:
					return a.global_position.distance_to(spot) < b.global_position.distance_to(spot))
				var d1: float = sites[0].global_position.distance_to(spot)
				var d2: float = sites[1].global_position.distance_to(spot)
				if d2 <= d1 * 1.8 and sites[0].global_position.distance_to(sites[1].global_position) > raid.weather.radius:
					near_site = sites[0]
					far_site = sites[1]
					from = spot
	if far_site != null:
		var anchor := Node3D.new()
		raid.add_child(anchor)
		anchor.global_position = from
		var army := [anchor]
		for point in raid.strongpoints:
			point.holder = ""
		raid.weather.centre = Vector3(far_site.global_position.x, 0.0, far_site.global_position.z)
		var pick: Strongpoint = raid._army_target("test", [], army)
		t.check(pick == far_site and raid.weather.strength_at(near_site.global_position) < Raid.STORM_COVER,
				"an army pushes a site the storm covers over a nearer clear one")
		raid.weather.centre = Vector3(5000, 0, 5000)
		t.check(raid._army_target("test", [], army) != far_site, "with no storm over it, the nearer site comes first")
		anchor.queue_free()
	t.check(far_site != null, "the map has sites to push")
	# Clients hear the cell from the server.
	var session := NetSessionScript.new()
	var client := Raid.new()
	t.add_child(client)
	client.start_client(Worlds.get_world("ashfront"))
	session.raid = client
	raid.weather.centre = Vector3(12, 0, 34)
	session.call("_weather", raid.weather.pack())
	t.check(client.weather.kind == "ash" and client.weather.centre.is_equal_approx(raid.weather.centre)
			and is_equal_approx(client.weather.strength_at(raid.weather.centre), 1.0),
			"a client takes the server's word for the storm")
	session.call("_weather", ["ash", "x"])
	t.check(client.weather.centre.is_equal_approx(raid.weather.centre), "and ignores a malformed one")
	session.free()
	client.queue_free()
	raid.queue_free()
	await t.frames(2)
