extends RefCounted
## Checks for the weak-laptop frame savers: the "Auto" render scale
## (`GameSettings.AutoScale`, `AutoScale.next_step`), the glow switch, a saved
## Graphics quality pick following what the pick became, and the war mood
## leaving the sky alone while it holds still (`Look.WarMood`, whose every
## sky write redraws the sky's light map), and the suit keeping its levels
## of detail, so a far body draws few triangles.

const GameSettings := preload("res://core/settings/game_settings.gd")
const LookScript := preload("res://core/visual/look.gd")
const SuitShape := preload("res://core/visual/suit_shape.gd")
const Human := preload("res://core/visual/human.gd")


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
	await t.frames(2)
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

	# The suit's baked parts keep levels of detail, as the bodies' import makes.
	for build: String in Human.BUILDS:
		for part: String in SuitShape.PARTS:
			var path := SuitShape.baked_path(build, part)
			var mesh := load(path) as ArrayMesh if ResourceLoader.exists(path) else null
			var lods := 0
			if mesh != null and mesh.get_surface_count() > 0:
				lods = (RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", []) as Array).size()
			t.check(lods > 0, "the suit's %s for build %s has levels of detail for far away" % [part, build])

	# A shaped face and a cut of hair keep levels of detail.
	var HeadShape := preload("res://core/visual/head_shape.gd")
	var rig: Node3D = (load(Human.rig_path("m")) as PackedScene).instantiate()
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var hair := HeadShape.dress(skeleton, "m", ["Hair_Long:bob"], "broad", Human.FACES["broad"][1])
	var head := skeleton.find_child("PartHead", false, false) as MeshInstance3D
	var cut := skeleton.find_child(hair[0], false, false) as MeshInstance3D if not hair.is_empty() else null
	t.check(head != null and _lod_count(head.mesh) > 0 and cut != null and _lod_count(cut.mesh) > 0,
			"a shaped face and a cut of hair keep levels of detail for far away")
	rig.free()

	# A gun attachment's alike parts become one mesh each; named parts stay.
	var optic := Node3D.new()
	for i in 6:
		optic.add_child(Weapon.make_part(Vector3(0.01, 0.01, 0.01), Vector3(i * 0.02, 0, 0), Color(0.1, 0.11, 0.13)))
	for i in 4:
		optic.add_child(Weapon.make_part(Vector3(0.002, 0.002, 0.002), Vector3(0, i * 0.01, 0), Color(0.25, 0.9, 1.0), true))
	var lens := Weapon.make_part(Vector3(0.01, 0.01, 0.001), Vector3.ZERO, Color.WHITE)
	lens.name = "Lens"
	optic.add_child(lens)
	LookScript.merge_pieces(optic, true, true)
	t.check(optic.get_child_count() == 3 and optic.has_node("Lens"),
			"an attachment's parts set alike merge into one mesh per look, keeping its named lens")
	optic.free()

	# A big merged model (a vehicle) gets levels of detail; a few boxes do not.
	var model := Node3D.new()
	var mat := StandardMaterial3D.new()
	for i in 4:
		var wheel := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.radial_segments = 48
		cylinder.rings = 4
		cylinder.material = mat
		wheel.mesh = cylinder
		wheel.position = Vector3(i, 0, 0)
		model.add_child(wheel)
	LookScript.merge_pieces(model, true, false, true)
	var merged := model.get_child(0) as MeshInstance3D
	t.check(model.get_child_count() == 1 and merged != null and _lod_count(merged.mesh) > 0,
			"a big merged model gets levels of detail for far away")
	model.free()


static func _lod_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return (RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", []) as Array).size()
