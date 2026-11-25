extends RefCounted
## Checks for the weak-laptop frame savers: the "Auto" render scale
## (`GameSettings.AutoScale`, `AutoScale.next_step`), the glow switch, a saved
## Graphics quality pick following what the pick became, and the war mood
## leaving the sky alone while it holds still (`Look.WarMood`, whose every
## sky write redraws the sky's light map).

const GameSettings := preload("res://core/settings/game_settings.gd")
const LookScript := preload("res://core/visual/look.gd")


static func run(t: Node) -> void:
	GameSettings.persist = false
	GameSettings.reset()

	# Auto's steps.
	var target := GameSettings.AUTO_TARGET_MS
	var start := GameSettings.AUTO_SCALE_START
	var last := GameSettings.AUTO_SCALES.size() - 1
	t.check(GameSettings.AutoScale.next_step(start, target * 1.2) == start + 1,
			"Auto drops a step when the card runs over its aim")
	t.check(GameSettings.AutoScale.next_step(start, target * 2.0) == start + 2,
			"and two when it runs far over")
	t.check(GameSettings.AutoScale.next_step(last, target * 3.0) == last, "never under the smallest scale")
	t.check(GameSettings.AutoScale.next_step(start, target * 0.4) == start - 1,
			"Auto sharpens a step when the card has plenty of room")
	t.check(GameSettings.AutoScale.next_step(start, target * 0.8) == start,
			"and holds when the sharper step would not fit")
	t.check(GameSettings.AutoScale.next_step(0, 1.0) == 0, "never over full size")
	t.check(GameSettings.AutoScale.next_step(start, 0.0) == start, "with no timing it holds")

	# Auto on the main view.
	var root := t.get_tree().root
	# (`set_value` leaves the view alone with no window: applied by hand.)
	GameSettings.set_value("render_scale", GameSettings.RENDER_SCALE_AUTO)
	GameSettings.apply_graphics()
	await t.frames(1)
	var auto := root.get_node_or_null(GameSettings.AutoScale.NODE_NAME)
	t.check(auto != null and is_equal_approx(root.scaling_3d_scale, GameSettings.AUTO_SCALES[start]),
			"picking Auto starts the main view on its middle scale, with its timer running")
	GameSettings.set_value("render_scale", 0)
	GameSettings.apply_graphics()
	await t.frames(1)
	t.check(not is_instance_valid(auto) and is_equal_approx(root.scaling_3d_scale, 1.0),
			"picking a fixed scale stops Auto and draws at that scale")

	# Glow follows its switch on a world's atmosphere.
	var atmosphere := WorldEnvironment.new()
	atmosphere.environment = Environment.new()
	atmosphere.environment.glow_enabled = true
	GameSettings.set_value("bloom", false)
	GameSettings.fit_atmosphere(atmosphere)
	t.check(not atmosphere.environment.glow_enabled, "switching the glow off takes it off a world")
	GameSettings.set_value("bloom", true)
	GameSettings.fit_atmosphere(atmosphere)
	t.check(atmosphere.environment.glow_enabled, "and on again")
	atmosphere.free()

	# A saved pick takes the pick's rows as they are now.
	GameSettings.reset()
	GameSettings.use_saved({"graphics": GameSettings.GRAPHICS_LOW, "shadows": 2, "render_scale": 2,
			"view_distance": 2, "ambient_occlusion": false, "ground_smoke": false, "anti_aliasing": 1,
			"edge_ink": true})
	t.check(GameSettings.graphics == GameSettings.GRAPHICS_LOW
			and GameSettings.render_scale == GameSettings.RENDER_SCALE_AUTO and not GameSettings.bloom,
			"a player saved on Low gets what Low is now")
	GameSettings.reset()
	GameSettings.use_saved({"graphics": GameSettings.GRAPHICS_CUSTOM, "shadows": 3, "render_scale": 1})
	t.check(GameSettings.graphics == GameSettings.GRAPHICS_CUSTOM and GameSettings.shadows == 3
			and GameSettings.render_scale == 1, "settings chosen by hand are kept as they were")
	GameSettings.reset()
	GameSettings.apply_graphics()
	await t.frames(1)

	# The war mood writes the sky only when it moves.
	var map := Node3D.new()
	map.set_meta("war_intensity", 0.0)
	t.add_child(map)
	var mood: Node = LookScript.WarMood.new()
	var calm: Dictionary = Look.mood_values({})
	mood.calm = calm
	mood.war = Look.mood_values({"sky_tint": Color(0.5, 0.2, 0.1)}, calm)
	mood.follow = 100.0
	mood.env = Environment.new()
	mood.sky_mat = ShaderMaterial.new()
	mood.sky_mat.shader = LookScript.SKY_SHADER
	mood.sun = DirectionalLight3D.new()
	map.add_child(mood.sun)
	map.add_child(mood)
	mood.set_process(false)
	mood._process(0.016)
	var marker := Color(0.123, 0.456, 0.789)
	mood.sky_mat.set_shader_parameter("tint", marker)
	mood._process(0.016)
	mood._process(0.016)
	t.check(mood.sky_mat.get_shader_parameter("tint") == marker,
			"a war mood holding still leaves the sky's material alone")
	map.set_meta("war_intensity", 1.0)
	mood._process(0.016)
	t.check(mood.sky_mat.get_shader_parameter("tint") != marker, "and writes it when the war moves")
	t.check(not LookScript.WarMood.mood_moved(Vector3(0.5, 0, 0), Vector3(0.501, 0, 0))
			and LookScript.WarMood.mood_moved(Vector3(0.5, 0, 0), Vector3(0.51, 0, 0))
			and LookScript.WarMood.mood_moved(Vector3(0.999, 0, 0), Vector3(1.0, 0, 0)),
			"a step too small to see is skipped, a real one or one that lands on full war is not")
	map.queue_free()
	await t.frames(1)
