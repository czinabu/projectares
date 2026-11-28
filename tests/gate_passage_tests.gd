extends RefCounted
## The `gate_passage` checks: between places the view is the passage through
## a gate (`GateLook.transit`, `Main._fade_travel`), never a dark or flat
## screen. It takes the colours of where you are going, says what a slow
## trip waits for in one small line, and opens onto the place as it stands.
## The test runner finds this file by itself.

const GateLook := preload("res://core/visual/gate_look.gd")


static func run(t: Node) -> void:
	print("Gate passage")
	# The passage is read from the destination's planet, like its gate.
	var mat := GateLook.transit()
	t.check(mat.get_shader_parameter("tint") == GateLook.DEFAULT_COLOR, "with no world it glows the plain gate colour")
	for world in Worlds.raid_worlds():
		var type := world.planet_type()
		if type == null:
			continue
		GateLook.aim_transit(mat, type)
		var params := GateLook.window_params(type)
		t.check(mat.get_shader_parameter("tint") == GateLook.world_color(type)
				and mat.get_shader_parameter("zenith") == params["zenith"]
				and mat.get_shader_parameter("ground") == params["ground"],
				"the passage to %s glows in its gate's colour and opens on its sky and ground" % world.id)

	# In the game: the passage covers the trip from the first frame.
	Profile.reset()
	Profile.welcome_granted = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	var target: WorldDef = Worlds.raid_worlds()[0]
	main.travel_quiet = 0.3
	main._show_travel("Travelling to %s..." % target.display_name, target)
	await t.frames(2)
	var cover: ColorRect = main._cover
	var shader := cover.material as ShaderMaterial
	t.check(cover.color.a >= 0.99 and shader != null, "stepping in, the passage fills the view at once")
	t.check(shader.get_shader_parameter("tint") == Look.gate_color(target.planet_type()),
			"it is the colour of %s's gate" % target.id)
	t.check(not main._travel_text.visible, "a quick trip says nothing")
	var began := float(shader.get_shader_parameter("t"))
	await t.frames(30)
	t.check(float(shader.get_shader_parameter("t")) > began, "the passage streams past while the trip runs")
	t.check(cover.color.a >= 0.99 and float(shader.get_shader_parameter("arrive")) == 0.0,
			"it never fades to a flat screen while waiting")
	t.check(main._travel_text.visible and main._travel_text.text == ("Travelling to %s..." % target.display_name).to_upper(),
			"a slow trip says what it waits for in a line: %s" % main._travel_text.text)

	# The place stands: the far end opens and the world fades in behind it.
	main.go_home()
	await t.frames(3)
	t.check(main.passage_open() > 0.0 and main.passage_open() < 1.0 and float(shader.get_shader_parameter("arrive")) > 0.0,
			"arriving, the passage opens onto the place")
	t.check(not main._travel_text.visible, "and the line goes")
	await t.frames(60)
	t.check(cover.color.a < 0.01 and main.passage_open() >= 0.99 and not cover.visible,
			"then it is gone, not drawn at all, and you stand in the place")

	# The next trip home is plain: no world's colours carried over.
	main._show_travel("Going home...")
	await t.frames(2)
	t.check(shader.get_shader_parameter("tint") == GateLook.DEFAULT_COLOR, "a trip to no world is the plain passage")
	main.go_home()
	await t.frames(40)
	main.queue_free()
	await t.frames(2)
