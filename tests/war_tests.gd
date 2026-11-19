extends RefCounted
## The `war` checks. The test runner finds this file by itself and calls
## `run(t)`.

const WarDirector := preload("res://core/war/war_director.gd")


static func run(t: Node) -> void:
	print("War intensity")
	# The director on its own.
	var war := WarDirector.new()
	t.check(war.intensity == 0.0 and war.level_name() == "Quiet" and war.renown_bonus() == 1.0, "a new world is quiet")
	war.report_kill(Vector3(10, 0, 0), false)
	var after_bot := war.intensity
	war.report_kill(Vector3(30, 0, 0), true)
	t.check(after_bot > 0.0 and war.intensity - after_bot > after_bot, "kills heat the war up, a player's death most of all")
	t.check(war.centre.x > 10.0 and war.centre.x < 30.0, "the centre of the fighting drifts towards the newest kill")
	var before := war.intensity
	war.tick(5.0)
	t.check(war.intensity == before, "the heat holds for a while after the last kill")
	war.tick(war.calm_delay)
	war.tick(1.0)
	t.check(war.intensity < before, "then it cools")
	before = war.intensity
	var clash: Array[Vector3] = [Vector3(0, 0, 50)]
	war.tick(1.0, clash)
	t.check(war.intensity > before, "hostile players close together heat it up")
	for i in 400:
		war.report_kill(Vector3.ZERO, true)
	t.check(war.intensity == 1.0 and war.level_name() == "All-out war" and war.renown_bonus() == 1.5,
			"the meter tops out at 1, where kills pay half as much renown again")
	t.check(WarDirector.level_for(0.3) == "Skirmish" and WarDirector.level_for(0.6) == "Battle", "the meter has names for its stretches")
	war.tick(10000.0)
	war.tick(10000.0)
	t.check(war.intensity == 0.0, "a world left alone goes quiet again")
	var still := WarDirector.new()
	still.scale = 0.0
	still.report_kill(Vector3.ZERO, true)
	still.tick(1.0, clash)
	t.check(still.intensity == 0.0, "a world can keep its war meter still")

	# In a running world.
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(Worlds.get_world("ashfront"), 93)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var a := raid.add_player([], {}, "Alpha")
	var b := raid.add_player([], {}, "Bravo")
	a.global_position = Vector3(0, 300, 0)
	b.global_position = Vector3(0, 300, 200)
	a.set_physics_process(false)
	b.set_physics_process(false)
	await t.frames(30)
	t.check(raid.war.intensity == 0.0, "players far apart are not a war, however many there are")
	b.global_position = Vector3(0, 300, 20)
	await t.frames(30)
	var brewing := raid.war.intensity
	t.check(brewing > 0.0 and raid.war.centre.distance_to(Vector3(0, 300, 10)) < 1.0, "two hostile players near each other are (%.3f)" % brewing)
	t.check(is_equal_approx(raid.map.get_meta("war_intensity"), raid.war.intensity)
			and raid.map.get_meta("war_centre") == raid.war.centre, "the map is told how hot the war is, for the sky")
	b.global_position = Vector3(0, 300, 200)
	raid.bots[0].kill("bullet", a)
	await t.frames(2)
	t.check(raid.war.intensity > brewing, "a player killing a bot adds to it")
	var mid := raid.war.intensity
	raid.bots[1].kill("bullet", raid.bots[2])
	await t.frames(2)
	t.check(raid.war.intensity > mid and raid.war.intensity - mid < 0.02, "bots killing each other only keep it simmering")
	raid.war.intensity = raid.war.battle_ceiling
	raid.bots[1].kill("bullet", raid.bots[2])
	await t.frames(2)
	t.check(raid.war.intensity <= raid.war.battle_ceiling, "and never take it past a skirmish on their own")
	raid.war.intensity = 1.0
	await t.frames(2)
	var paid := a.renown
	raid.bots[3].kill("bullet", a)
	t.check(a.renown - paid > roundi(10 * 1.1), "kills pay more renown in a hot war (%d)" % (a.renown - paid))
	t.check(Hud.standing_text(a) != "" and WarDirector.level_for(raid.war.intensity) == "All-out war", "the HUD can name the war's level")
	await t._end_raid(raid)
	t.check(Worlds.get_world("frostline").war_scale == 0.0 and Worlds.get_world("ashfront").war_scale > 0.0,
			"Frostline stays quiet and Ashfront does not")

	# The mood: a blend between the calm and the war atmosphere a map supplies.
	var calm := Look.mood_values({"sun_energy": 2.0, "fog_color": Color(0.4, 0.4, 0.4)})
	var battle := Look.mood_values({"sun_energy": 1.0}, calm)
	t.check(battle.fog_color == calm.fog_color and battle.sun_energy == 1.0, "a war mood only says what changes")
	var half := Look.blend_moods(calm, battle, 0.5)
	t.check(is_equal_approx(half.sun_energy, 1.5) and Look.blend_moods(calm, battle, 0.0).sun_energy == 2.0
			and Look.blend_moods(calm, battle, 7.0).sun_energy == 1.0, "the mood blends with the meter and stops at the war mood")

	# The storm must not white out a fight. Caps, the distance curve, actors
	# thinning fog as they get near, and shots that ignore fog.
	var abusive := Look.soften_storm(Look.mood_values({
		"fog_density": 4.0, "fog_depth_begin": 2.0, "fog_depth_end": 18.0,
		"fog_height": 40.0, "fog_height_density": 3.0,
	}))
	t.check(abusive.fog_depth_begin >= Look.storm_fog_begin_min
			and abusive.fog_depth_end >= Look.storm_fog_solid_min
			and abusive.fog_density <= Look.storm_depth_amount_cap
			and abusive.fog_height <= Look.storm_fog_height_max
			and abusive.fog_height_density <= Look.storm_height_density_cap,
			"a war mood cannot ask for fog inside engagement range")
	var thin := Look.soften_storm(Look.mood_values({"fog_density": 0.4}))
	t.check(thin.fog_density <= Look.storm_fog_density_cap, "exponential war fog stays a light haze")
	var at_30 := Look.fog_amount_at(30.0, 1.7, Look.storm_depth_amount_cap, Look.storm_fog_begin_min,
			Look.storm_fog_solid_min, 1.0, true, 1.1, 0.0)
	var at_50 := Look.fog_amount_at(50.0, 1.7, Look.storm_depth_amount_cap, Look.storm_fog_begin_min,
			Look.storm_fog_solid_min, 1.0, true, 1.1, 0.0)
	var at_far := Look.fog_amount_at(Look.storm_fog_solid_min, 1.7, Look.storm_depth_amount_cap,
			Look.storm_fog_begin_min, Look.storm_fog_solid_min, 1.0, true, 1.1, 0.0)
	t.check(at_30 < 0.08 and at_50 < 0.22 and at_far > 0.8,
			"30 m stays clear, 50 m stays readable, the horizon goes (%.0f%%, %.0f%%, %.0f%%)" % [at_30 * 100.0, at_50 * 100.0, at_far * 100.0])
	t.check(is_equal_approx(Look.actor_fog_keep(8.0), Look.actor_fog_min)
			and Look.actor_fog_keep(50.0) < 0.85 and is_equal_approx(Look.actor_fog_keep(200.0), 1.0),
			"actors shed fog up close and take the full fog once they are far")
	var teal := Look.storm_accent(Color(0.25, 0.6, 1.0))
	var pink := Look.storm_accent(Color(0.85, 0.3, 0.2))
	t.check(teal.b > teal.r and teal.g > 0.5, "a cool faction reads as the teal energy glow")
	t.check(pink.r > 0.8 and pink.b > pink.g, "a warm faction is pushed toward pink so it clears the orange storm")
	var flash: StandardMaterial3D = load("res://core/visual/vfx.gd").flash_material()
	var shot := Fx.shot_material(Color(1.0, 0.8, 0.3))
	t.check(flash.disable_fog and shot.disable_fog and shot.emission_enabled,
			"muzzle flashes and tracers are not swallowed by fog")
	for path in ["res://assets/shaders/character.gdshader", "res://assets/shaders/gear.gdshader",
			"res://assets/shaders/melee.gdshader"]:
		var code := FileAccess.get_file_as_string(path)
		t.check("storm_pop" in code and "FOG" in code, "%s thins fog on actors" % path.get_file())
	# The ramp: a meter that jumps to all-out war eases, it does not snap.
	var holder := Node3D.new()
	t.add_child(holder)
	holder.set_meta("war_intensity", 1.0)
	holder.set_meta("war_centre", Vector3.ZERO)
	var mood := Look.WarMood.new()
	mood.follow = Look.storm_follow
	mood.calm = Look.mood_values({
		"fog_density": 0.5, "fog_depth_begin": 80.0, "fog_depth_end": 400.0, "sun_energy": 2.0,
	})
	mood.war = Look.soften_storm(Look.mood_values({
		"fog_density": 4.0, "fog_depth_begin": 2.0, "fog_depth_end": 18.0, "sun_energy": 1.0,
	}, mood.calm))
	mood.env = Environment.new()
	mood.sky_mat = ShaderMaterial.new()
	mood.sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	mood.sun = DirectionalLight3D.new()
	mood.column = Look._war_column()
	holder.add_child(mood)
	mood.add_child(mood.sun)
	mood.add_child(mood.column)
	mood._process(0.05)
	t.check(mood.shown > 0.0 and mood.shown < 0.05, "the storm eases in (%.3f in one tick)" % mood.shown)
	t.check(mood.env.fog_mode == Environment.FOG_MODE_DEPTH
			and mood.env.fog_depth_begin >= Look.storm_fog_begin_min
			and mood.env.fog_depth_end >= Look.storm_fog_solid_min
			and mood.env.fog_density <= Look.storm_depth_amount_cap + 0.001,
			"the live sky obeys the same cap")
	mood._process(30.0)
	t.check(mood.shown > 0.99 and mood.env.fog_depth_end >= Look.storm_fog_solid_min,
			"it arrives at the capped storm, not a whiteout")
	holder.queue_free()
	await t.frames(2)
