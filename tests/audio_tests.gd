extends RefCounted
## The game's sound past the guns (`docs/systems/audio.md`): footsteps by the
## ground under them, engines that wind up with speed, each world's
## ambience, and the plaza's music on its own volume. All of it is view
## only, so these checks run the pieces' rules headless, where `Sfx` itself
## stays silent.

const GameSettings := preload("res://core/settings/game_settings.gd")
const FrostMap := preload("res://worlds/frostline/map.gd")


static func run(t: Node) -> void:
	print("Audio")
	_files(t)
	_footsteps(t)
	_engines(t)
	_ambience(t)
	_music(t)
	_detail(t)


## Every world sound is in the repository (CC0, `assets/LICENSES.md`), and
## the loops loop with no seam to hear.
static func _files(t: Node) -> void:
	var missing: Array[String] = []
	for ground: String in Sfx.STEP_GROUNDS:
		for i in 5:
			var path := Sfx.WORLD_DIR + "step_%s_%d.ogg" % [ground, i + 1]
			if not ResourceLoader.exists(path):
				missing.append(path)
	for sound: String in Sfx.WORLD_LOOPS:
		if not ResourceLoader.exists(Sfx.WORLD_DIR + sound + ".ogg"):
			missing.append(sound)
	t.check(missing.is_empty(), "every footstep, engine, wind and music file is there %s" % [missing])
	var music := load(Sfx.WORLD_DIR + "music_plaza.ogg") as AudioStreamOggVorbis
	t.check(music != null and music.get_length() > 120.0, "the plaza's track runs minutes before it comes round again")
	var step := load(Sfx.WORLD_DIR + "step_snow_1.ogg") as AudioStream
	t.check(step != null and step.get_length() < 0.6, "a footstep is a short sound, not a loop")


static func _footsteps(t: Node) -> void:
	var walk := Footsteps.step_length(1.5)
	var run := Footsteps.step_length(6.0)
	var sprint := Footsteps.step_length(9.0)
	t.check(walk < run and run <= sprint, "a run's steps are longer than a walk's")
	t.check(1.5 / walk > 1.5 and 1.5 / walk < 2.5 and 9.0 / sprint < 4.5,
			"a walk is about two steps a second and a sprint not many more than three")
	var feet := Footsteps.new()
	t.check(feet.step_db(1.5, true) < feet.step_db(1.5, false) and feet.step_db(1.5, false) < feet.step_db(8.0, false),
			"a crouched step is quietest and a sprint loudest")
	feet.free()
	# The ground under the feet.
	t.check(Footsteps.ground_for(null, null, Vector3.ZERO) == "hard", "with nothing under the feet a step is hard")
	var deck := StaticBody3D.new()
	t.check(Footsteps.ground_for(deck, null, Vector3.ZERO) == "hard", "a built floor is hard underfoot")
	deck.set_meta("footstep", "wood")
	t.check(Footsteps.ground_for(deck, null, Vector3.ZERO) == "wood", "a piece that names its ground is heard as that")
	deck.free()
	var frost: WorldDef = Worlds.get_world("frostline")
	var ash: WorldDef = Worlds.get_world("ashfront")
	var ground := Terrain.new()
	t.check(Footsteps.ground_for(ground, frost, Vector3.ZERO) in ["snow", "hard"],
			"Frostline's open ground is snow (or ice, which is hard)")
	t.check(Footsteps.ground_for(ground, ash, Vector3.ZERO) == "dirt", "Ashfront's open ground is ash and dirt")
	ground.free()
	var cold := WorldDef.new()
	cold.take_planet("glacier")
	t.check(cold.footstep_ground(Vector3.ZERO) == "snow", "a world on the glacier steps in snow")
	cold.planet_grip = 0.3
	t.check(cold.footstep_ground(Vector3.ZERO) == "hard", "ground slick as ice is hard underfoot")
	cold.footsteps = "wood"
	cold.planet_grip = 1.0
	t.check(cold.footstep_ground(Vector3.ZERO) == "wood", "a world's own footstep ground wins over its planet's")
	for type_id: String in PlanetTypes.ids():
		t.check(PlanetTypes.get_type(type_id).footsteps in Sfx.STEP_GROUNDS,
				"the %s planet's ground has a footstep sound" % type_id)


static func _engines(t: Node) -> void:
	var machine: CharacterBody3D = load(Look.VEHICLE_SCRIPT).new()
	t.check(EngineSound.kind_of(machine) == "ground", "a machine on wheels has a ground engine")
	machine.set("hovers", true)
	t.check(EngineSound.kind_of(machine) == "hover", "a hoverbike whines")
	machine.set("flies", true)
	t.check(EngineSound.kind_of(machine) == "air", "anything that flies roars")
	machine.free()
	var engine := EngineSound.new()
	var idle := engine.voice(0.0, 24.0)
	var top := engine.voice(24.0, 24.0)
	var boost := engine.voice(32.0, 24.0)
	t.check(idle.x < top.x and top.x < boost.x, "an engine winds up with speed, and past its top on a boost")
	t.check(idle.y < top.y and is_equal_approx(top.y, boost.y), "it gets louder with speed, never past its top")
	t.check(is_equal_approx(engine.voice(-6.0, 24.0).x, engine.voice(6.0, 24.0).x), "reversing sounds like going forward")
	engine.free()


static func _ambience(t: Node) -> void:
	var map: Node3D = FrostMap.new()
	var ears: Soundscape = map.make_soundscape()
	t.check(ears.wind_sound == "wind_cold" and ears.wind_db > -20.0, "Frostline's cold wind always blows, and loud")
	t.check(not ears.accents.is_empty() and ears.accents[0]["sound"] == "ice_crack", "the ice groans far off now and then")
	var shelter := Soundscape.new()
	t.check(ears.fire_rate.y < shelter.fire_rate.y, "Frostline's far gunfire is rarer than Ashfront's war")
	ears.free()
	map.free()
	t.check(shelter.shelter_wind_db > 0.0 and shelter.shelter_rumble_db > 0.0,
			"under cover the wind drops away and the rumble rises")
	shelter.free()


static func _music(t: Node) -> void:
	t.check(Worlds.get_world("plaza").music == "plaza", "the Concourse plays the plaza's track")
	t.check(Worlds.get_world("ashfront").music == "" and Worlds.get_world("frostline").music == "",
			"the war worlds play no score: the war is what you hear")
	var row := {}
	for setting: Dictionary in GameSettings.SCHEMA:
		if setting["key"] == "music_volume":
			row = setting
	t.check(row.get("tab", "") == "system" and row.get("kind", "") == "slider", "the phone has a Music volume of its own")
	var bus := GameSettings.music_bus()
	t.check(bus > 0 and AudioServer.get_bus_name(bus) == GameSettings.MUSIC_BUS and GameSettings.music_bus() == bus,
			"the music has its own bus, made once")
	t.check(AudioServer.get_bus_send(bus) == &"Master", "the music's bus goes through the main volume")
	var was := GameSettings.music_volume
	GameSettings.music_volume = 0.0
	GameSettings.apply()
	t.check(AudioServer.is_bus_mute(bus), "music at nothing is off")
	GameSettings.music_volume = was
	GameSettings.apply()
	t.check(not AudioServer.is_bus_mute(bus) or was <= 0.001, "music back up is heard again")


## Kept light on a laptop: the Low and Lowest presets turn the sound
## detail down with the war scenery, and fewer steps and engines are heard.
static func _detail(t: Node) -> void:
	var was := GameSettings.war_scenery
	GameSettings.war_scenery = 0
	var full := Sfx.engines_at_once()
	var full_detail := Sfx.sound_detail()
	GameSettings.war_scenery = GameSettings.WAR_SCENERY.size() - 1
	t.check(Sfx.sound_detail() < full_detail and Sfx.engines_at_once() < full and Sfx.engines_at_once() >= 2,
			"on the lightest scenery fewer engines run at once (but always a couple)")
	var low: Array = GameSettings.GRAPHICS[GameSettings.GRAPHICS_LOW]
	t.check(int(low[GameSettings.GRAPHICS_KEYS.find("war_scenery") + 1]) > 0, "the Low preset turns the sound detail down")
	GameSettings.war_scenery = was
	# The bodies in earshot share one budget of steps: a crowd all stepping
	# at once is heard as only a few.
	var heard := 0
	for i in 60:
		if Sfx.take_step():
			heard += 1
	t.check(heard > 0 and heard <= 10, "a crowd stepping all at once is heard only a few at a time (%d)" % heard)
