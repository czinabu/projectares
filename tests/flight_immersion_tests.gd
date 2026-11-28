extends RefCounted
## Checks for the first person flight pass (Caleb's call): the limbs never
## sink into a flight rig, the rig is heard as worn in first person, the view
## bobs and leans with the flight, the watch throws up a hologram of the
## body, and the weather streaks across the visor at speed.
## Run from the main test runner. Nothing here starts a server.

const GameSettings := preload("res://core/settings/game_settings.gd")
const WeaponArmScript := preload("res://core/visual/weapon_arm.gd")


static func run(t: Node) -> void:
	print("Flight immersion")
	await _test_limbs_clear(t)
	await _test_worn_sound(t)
	await _test_view(t)
	_test_streaks(t)


static func _arena(t: Node) -> Node3D:
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = Vector3(3200, 0, -3200)
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 1, 60)
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0, -0.5, 0)
	arena.add_child(ground)
	return arena


## A dressed body in the air, its own physics off so the test sets what it
## does, built `build` ("m" or "f").
static func _flyer(t: Node, arena: Node3D, build: String, rig: String) -> Actor:
	var p := Actor.new()
	p.set_meta("appearance", {"build": build})
	arena.add_child(p)
	Loadout.equip(p, ["frame_trooper", rig])
	p.ground_map = arena
	await t.frames(3)
	p.set_physics_process(false)
	p.global_position = arena.global_position + Vector3(0, 12, 0)
	# One step up off the floor, so the body knows it is in the air.
	p.velocity = Vector3.UP
	p.move_and_slide()
	p.airborne_time = 1.0
	return p


## The deepest any limb of `skin` sinks into its rig over `count` frames,
## read after every pose.
static func _worst(t: Node, skin: Node, step: Callable, count: int) -> float:
	var skeleton: Skeleton3D = skin.get("_skeleton")
	var worst := [0.0]
	var probe: SkeletonModifier3D = WeaponArmScript.Hook.new()
	probe.set("run", func() -> void:
		worst[0] = maxf(worst[0], float(skin.call("rig_intrusion"))))
	skeleton.add_child(probe)
	for i in count:
		step.call(i)
		await t.get_tree().process_frame
	probe.free()
	return worst[0]


## Every flight pose of every rig model, on both bodies: no part of an arm
## or a leg sinks into the pack, a spread wing or the other boot.
static func _test_limbs_clear(t: Node) -> void:
	Look.enabled = true
	var arena := _arena(t)
	var worst_on := 0.0
	var worst_off := 0.0
	var where := ""
	var states := 0
	for build: String in ["m", "f"]:
		for rig: String in ["jetpack_mk1", "jetpack_mk3", "wings_glide", "boots_thruster"]:
			var p: Actor = await _flyer(t, arena, build, rig)
			var skin := p.get_node_or_null("Skin")
			if skin == null or skin.get("_skeleton") == null:
				t.check(false, "a dressed flyer has a skin (%s, %s)" % [build, rig])
				p.queue_free()
				continue
			var forward := -p.global_basis.z
			var f := p.flight
			var poses := _poses(rig)
			for pose: Dictionary in poses:
				for clear_on: bool in [false, true]:
					skin.set("rig_clear_on", clear_on)
					f.is_hovering = pose.get("hover", false)
					f.is_thrusting = pose.get("hover", false) or pose.get("thrust", false)
					f.is_gliding = pose.get("glide", false)
					f.is_boosting = pose.get("boost", false)
					f.is_skating = pose.get("skate", false)
					f.is_skimming = pose.get("skim", false)
					p.cmd = ActorCommand.new()
					p.cmd.move = pose.get("move", Vector2.ZERO)
					p.cmd.jump = pose.get("jump", false)
					p.cmd.descend = pose.get("descend", false)
					var speed: float = pose.get("speed", 0.0)
					var drop: float = pose.get("drop", 0.0)
					var turn: float = pose.get("turn", 0.0)
					var look_off: float = pose.get("look", 0.0)
					var yaw := p.rotation.y
					var step := func(i: int) -> void:
						p.rotation.y = yaw + turn * i + (look_off if i > 4 else 0.0)
						p.velocity = forward * speed + Vector3(0, -drop, 0)
					var deep: float = await _worst(t, skin, step, 40)
					p.rotation.y = yaw
					if clear_on:
						states += 1
						if deep > worst_on:
							worst_on = deep
							where = "%s body, %s, %s: %s" % [build, rig, pose.name, skin.get("rig_worst")]
					else:
						worst_off = maxf(worst_off, deep)
			p.queue_free()
			await t.frames(2)
	print("  limbs into the rig: %.3f m at worst without the keep-clear pass, %.3f m with it (%s)" % [worst_off, worst_on, where])
	t.check(states >= 60, "every rig's flight poses on both bodies are tried (%d)" % states)
	t.check(worst_on < 0.01, "no limb sinks into a flight rig in any flight pose (deepest %.3f m: %s)" % [worst_on, where])
	arena.queue_free()
	await t.frames(2)
	Look.enabled = false


## The flight poses each kind of rig flies in.
static func _poses(rig: String) -> Array:
	var out := []
	if rig.begins_with("jetpack"):
		out.append({"name": "hovering", "hover": true})
		for x in [-1, 0, 1]:
			for y in [-1, 0, 1]:
				if x != 0 or y != 0:
					out.append({"name": "hover stick %d,%d" % [x, y], "hover": true, "move": Vector2(x, y), "speed": 6.0 * y})
		out.append({"name": "climbing", "hover": true, "jump": true})
		out.append({"name": "dropping", "hover": true, "descend": true})
		out.append({"name": "turning left", "hover": true, "turn": 0.06, "speed": 8.0})
		out.append({"name": "turning right", "hover": true, "turn": -0.06, "speed": 8.0})
		out.append({"name": "boosting", "thrust": true, "boost": true, "speed": 20.0})
	elif rig.begins_with("wings"):
		out.append({"name": "gliding", "glide": true, "speed": 22.0, "drop": 3.0})
		out.append({"name": "leading left", "glide": true, "speed": 22.0, "drop": 3.0, "look": 0.6})
		out.append({"name": "leading right", "glide": true, "speed": 22.0, "drop": 3.0, "look": -0.6})
		out.append({"name": "diving", "glide": true, "speed": 30.0, "drop": 8.0, "move": Vector2(0, 1)})
		out.append({"name": "diving into a turn", "glide": true, "speed": 30.0, "drop": 8.0, "move": Vector2(0, 1), "look": 0.6})
		out.append({"name": "pulling up", "glide": true, "speed": 24.0, "drop": -4.0, "move": Vector2(0, -1)})
		out.append({"name": "pulling up into a turn", "glide": true, "speed": 24.0, "drop": -4.0, "move": Vector2(0, -1), "look": -0.6})
		out.append({"name": "stalling", "glide": true, "speed": 6.0, "drop": 6.0, "move": Vector2(0, -1)})
		out.append({"name": "boosting", "glide": true, "boost": true, "speed": 30.0})
		out.append({"name": "banking hard", "glide": true, "speed": 24.0, "turn": 0.05, "look": 0.6})
	else:
		out.append({"name": "skating", "skate": true, "speed": 14.0})
		out.append({"name": "carving left", "skate": true, "speed": 14.0, "move": Vector2(-1, 1), "turn": 0.05})
		out.append({"name": "carving right", "skate": true, "speed": 14.0, "move": Vector2(1, 1), "turn": -0.05})
		out.append({"name": "skimming", "skim": true, "thrust": true, "speed": 10.0})
		out.append({"name": "thrusting up", "thrust": true, "jump": true})
		for x in [-1, 1]:
			out.append({"name": "thrust stick %d" % x, "thrust": true, "move": Vector2(x, 0)})
		out.append({"name": "turning", "thrust": true, "turn": 0.06, "speed": 6.0})
	return out


## In first person the worn rig is heard whole, not swinging round the ears.
static func _test_worn_sound(t: Node) -> void:
	Look.enabled = true
	var arena := _arena(t)
	var p: Actor = await _flyer(t, arena, "m", "jetpack_mk1")
	var skin := p.get_node("Skin")
	var voice := skin.get_node_or_null("RigVoice") as AudioStreamPlayer3D
	if voice == null:
		# With no sound files loaded (headless), a stand-in voice.
		voice = AudioStreamPlayer3D.new()
		skin.add_child(voice)
		skin.set("_rig_voice", voice)
	if voice != null:
		skin.set("worn_view", true)
		skin.call("_update_rig_voice", true)
		var worn_pan := voice.panning_strength
		var worn_fall := voice.attenuation_model
		skin.set("worn_view", false)
		skin.call("_update_rig_voice", true)
		t.check(worn_pan < 0.5 and worn_fall == AudioStreamPlayer3D.ATTENUATION_DISABLED,
				"worn in first person, the rig's roar barely pans and does not fall off with the ear's distance")
		t.check(voice.panning_strength == 1.0 and voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
				"seen from outside, it is heard from where it is")
	p.queue_free()
	arena.queue_free()
	await t.frames(2)
	Look.enabled = false


## The view: it leans into a turn, bobs with the push, and the watch's
## hologram is up in first person flight only, and only with its setting on.
static func _test_view(t: Node) -> void:
	Look.enabled = true
	var arena := _arena(t)
	var p: Actor = await _flyer(t, arena, "m", "jetpack_mk1")
	var skin := p.get_node("Skin")
	p.flight.is_hovering = true
	p.flight.is_thrusting = true
	var controller := PlayerController.new()
	controller.setup(p)
	arena.add_child(controller)
	controller.set_physics_process(false)
	controller.view_mode = PlayerController.ViewMode.FIRST
	await t.frames(2)
	# Turning hard: the body leads into it, and so does the view.
	skin.set("_lead_turn", 1.0)
	skin.set("_lead_w", 1.0)
	var lean := float(skin.call("flight_lean"))
	t.check(lean > 0.05, "turning, a hovering body leans into the turn (%.2f rad)" % lean)
	# A hard push up sinks the eyes, and they spring back.
	var bobbed := 0.0
	for i in 20:
		p.velocity = Vector3(0, i * 1.0, 0)
		controller._update_flight_bob(skin, 1.0, 1.0 / 60.0)
		bobbed = minf(bobbed, controller._flight_bob)
	t.check(bobbed < -0.005 and bobbed > -float(controller.flight_bob_max) - 0.001,
			"a push up sinks the eyes a little (%.3f m), never more than the most" % bobbed)
	for i in 120:
		p.velocity = Vector3(0, 19, 0)
		controller._update_flight_bob(skin, 0.0, 1.0 / 60.0)
	t.check(absf(controller._flight_bob) < 0.004, "with no flight, the eyes settle back (%.3f m)" % controller._flight_bob)
	# The hologram.
	t.check(FlightHolo.flying(p), "a hovering body is flying for the hologram")
	var was := GameSettings.flight_hologram
	GameSettings.flight_hologram = true
	t.check(FlightHolo.wanted(p, controller, false), "the hologram is up flying in first person")
	t.check(not FlightHolo.wanted(p, controller, true), "but not with a card in front of the eyes")
	controller.view_mode = PlayerController.ViewMode.THIRD
	controller._cam_dist = 3.0
	t.check(not FlightHolo.wanted(p, controller, false), "nor in third person, where the body itself is seen")
	controller.view_mode = PlayerController.ViewMode.FIRST
	controller._cam_dist = 0.0
	GameSettings.flight_hologram = false
	t.check(not FlightHolo.wanted(p, controller, false), "and the phone's setting turns it off")
	GameSettings.flight_hologram = was
	var holo := FlightHolo.new()
	arena.add_child(holo)
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.global_position = p.get_eye_position()
	camera.current = true
	for i in 6:
		holo.update(p, camera, true, camera.global_position + camera.global_basis * Vector3(-0.2, -0.25, -0.45), 1.0 / 30.0)
		await t.get_tree().process_frame
	var drawn := holo.get_node("Figure") as MeshInstance3D
	var mesh := drawn.mesh as ImmediateMesh
	t.check(holo.visible and mesh.get_surface_count() > 0, "the hologram draws the body from its posed bones")
	var wrist := camera.global_position + camera.global_basis * Vector3(-0.2, -0.25, -0.45)
	var near := holo.global_position.distance_to(wrist)
	t.check(near < 0.15, "it is thrown up off the watch on the wrist, not pinned to the screen (%.2f m off it)" % near)
	holo.update(p, camera, true, Vector3.INF, 1.0 / 30.0)
	t.check(not holo.visible, "with no watch on the wrist there is nothing to throw it up")
	for i in 20:
		holo.update(p, camera, false, wrist, 1.0 / 30.0)
	t.check(not holo.visible, "and fades away once it is not wanted")
	controller.queue_free()
	p.queue_free()
	arena.queue_free()
	await t.frames(2)
	Look.enabled = false


## The weather streaks across the visor only flying fast through weather.
static func _test_streaks(t: Node) -> void:
	var visor := VisorHud.new()
	t.check(visor.streaks_wanted(30.0, true, 1.0, 0.0) > 0.5, "flying fast through a storm streaks the visor")
	t.check(visor.streaks_wanted(30.0, false, 1.0, 0.0) == 0.0, "but not on the ground")
	t.check(visor.streaks_wanted(8.0, true, 1.0, 0.0) == 0.0, "nor flying slowly")
	t.check(visor.streaks_wanted(30.0, true, 0.0, 0.0) == 0.0, "nor in clear, warm air")
	var cold := visor.streaks_wanted(38.0, true, 0.0, 0.5)
	t.check(cold > 0.2 and cold < 0.6, "the cold alone frosts it faintly (%.2f)" % cold)
	visor.free()
