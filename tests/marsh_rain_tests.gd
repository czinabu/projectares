extends RefCounted
## Checks for the Spore Marsh's rain storms (DESIGN.md "The Spore Marsh",
## Caleb's call: cover and quiet): the shared weather with `weather_kind`
## "rain", which cuts sight, drowns shots and footsteps, and washes the
## spores out of the air so guns foul slower. Down a Rootway is out of it.

const Rootway := preload("res://worlds/marsh/rootway.gd")
const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]


static func run(t: Node) -> void:
	print("Marsh: rain storms")
	_settings(t)
	await _in_the_rain(t)


static func _settings(t: Node) -> void:
	var marsh := Worlds.get_world("marsh")
	t.check(marsh.weather_kind == "rain" and marsh.weather_name == "Rain storm", "the marsh has rain storms")
	t.check(marsh.weather_sight < 1.0 and marsh.weather_carry < Worlds.get_world("ashfront").weather_carry,
			"they cut sight, and drown sound more than an ash storm does")
	t.check(marsh.weather_fouling < 1.0, "and guns foul slower in them")
	t.check(marsh.weather_gust < Worlds.get_world("ashfront").weather_gust, "with lighter gusts than an ash storm")
	for id: String in ["ashfront", "frostline"]:
		t.check(is_equal_approx(Worlds.get_world(id).weather_fouling, 1.0), "%s's storms leave fouling alone" % id)
	t.check(not Look.weather_kit("rain").is_empty() and Look.weather_kit("rain").get("sound") == "rain",
			"the rain has its own look and sound")


static func _in_the_rain(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("marsh"), 6)
	for bot in raid.bots:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	var me := raid.add_player(KIT, {}, "Rainy", "rainy")
	await t.frames(2)
	var gun: Gun = null
	for weapon in me.weapons:
		if weapon is Gun:
			gun = weapon
	if gun == null or raid.bots.is_empty():
		t.check(false, "the player has a gun and the marsh has wildlife")
		raid.queue_free()
		return
	t.check(raid.weather.kind == "" and raid.weather.next_in > 0.0, "the marsh starts dry, rain on its way")
	me.process_mode = Node.PROCESS_MODE_DISABLED
	var here := Vector3(0, 60, 0)
	me.global_position = here
	var clear_foul := gun.foul_rate()
	var clear_reach := gun.noise_reach()
	raid.weather.start()
	raid.weather.centre = here
	raid.weather.velocity = Vector3(0.001, 0, 0)
	raid.weather.age = raid.world.weather_ramp * 2.0
	raid.weather.life = 10000.0
	raid.weather.strength = 1.0
	t.check(is_equal_approx(raid.weather.sight_at(here), raid.world.weather_sight), "in its thick sight is cut")
	t.check(gun.foul_rate() < clear_foul * 0.5 and gun.foul_rate() > 0.0,
			"a gun fouls slower in the rain (%.2f against %.2f)" % [gun.foul_rate(), clear_foul])
	var wet_reach := gun.noise_reach()
	t.check(wet_reach < clear_reach * 0.5, "a shot is heard less far in the rain (%.0f m against %.0f m)" % [wet_reach, clear_reach])
	# A bot between the two reaches hears a shot in clear air, not in the rain.
	var bot: Actor = raid.bots[0]
	bot.global_position = here + Vector3((wet_reach + clear_reach) * 0.5, 0, 0)
	var heard := [0]
	var count := func(_at: Vector3, _source: Actor) -> void: heard[0] += 1
	bot.heard.connect(count)
	Combat.noise(me, here, gun.noise_reach())
	t.check(heard[0] == 0, "wildlife out of earshot in the rain does not hear a shot")
	raid.weather.centre = here + Vector3(raid.weather.radius * 4.0, 0, 0)
	Combat.noise(me, here, gun.noise_reach())
	t.check(heard[0] == 1, "but hears it from the same spot in clear air")
	bot.heard.disconnect(count)
	t.check(is_equal_approx(gun.foul_rate(), clear_foul), "out of the rain a gun fouls as usual")
	# Down a Rootway is out of the weather.
	var way: Dictionary = Rootway.ROOTWAYS[0]
	var deep := Rootway.frame(way) * Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR + 1.0, Rootway.CHAMBER_Z)
	raid.weather.centre = deep
	t.check(raid.weather.strength_at(deep) == 0.0, "down a Rootway it never rains")
	# The watch says so.
	me.global_position = Vector3(raid.weather.centre.x, 0, raid.weather.centre.z) + Vector3(30, 0, 0)
	raid.weather.centre = me.global_position
	t.check(raid.zone_label(me).ends_with("rain storm"), "the watch's zone line says you are in a rain storm (%s)" % raid.zone_label(me))
	t.check(raid.status().get("storm") == "Rain storm", "and the world's status says it is raining")
	raid.queue_free()
	await t.frames(2)
