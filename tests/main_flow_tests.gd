extends RefCounted
## The `main_flow` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashRules := preload("res://core/account/stash_rules.gd")
const PortalTests := preload("res://tests/portal_tests.gd")


static func run(t: Node) -> void:
	print("Hub and raid flow")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(2)
	t.check(main.base != null and main.raid == null and not main.hub.visible and main.controller != null
			and main.controller.camera.current, "the game opens in your home base, not on a menu")
	t.check(main.base.station("launch") == null and main.base.door.get_prompt().contains("Head out"),
			"the base has no launch pad, and its door leads out to the plaza")
	await PortalTests.through_base(t, main)
	await PortalTests.onward_solo(t, main)
	main._leave_raid()
	main.go_home()
	await t.frames(2)
	# Something in hand to test with: a new player starts bare.
	Profile.loadout = StashRules.starter_loadout()
	main.start_raid("ashfront")
	await t.frames(5)
	t.check(main.raid != null and not main.hub.visible, "deploying starts a raid")
	t.check(main.controller.camera.current and main.hud != null, "raid has a camera and HUD")
	t.check(main.nameplates != null and main.scoreboard != null and not main.scoreboard.visible,
			"raid has nameplates and a scoreboard, closed until Q is held")
	var controller: PlayerController = main.controller
	t.check(controller.view_mode == PlayerController.ViewMode.FIRST and not controller.is_third_person(),
			"camera starts in first-person")
	controller.base_fov = 70.0
	controller.base_fov_third = 100.0
	t.check(is_equal_approx(controller.wanted_base_fov(), 70.0), "first person uses its own field of view")
	controller.toggle_view()
	t.check(is_equal_approx(controller.wanted_base_fov(), 100.0), "third person uses its own field of view")
	t.check(is_equal_approx(controller.view_distance(false), controller.third_person_distance)
			and controller.third_person_distance <= 2.5, "the third-person camera sits close, over the shoulder")
	t.check(controller.view_distance(true) < controller.view_distance(false) and controller.view_distance(true) > 0.5,
			"aiming moves it in further")
	controller.third_person_distance = 4.0
	t.check(is_equal_approx(controller.view_distance(false), 4.0), "and its distance can be set")
	controller.third_person_distance = 2.0
	controller.toggle_view()
	# Melee and flight must not move the camera on their own.
	var p: Actor = main.raid.player
	await t.frames(40)
	Input.action_press("weapon_3")
	Input.action_press("jump")
	await t.frames(40)
	Input.action_release("weapon_3")
	Input.action_release("jump")
	t.check(p.get_active_weapon() is MeleeWeapon and not p.is_on_floor(),
			"real input reaches the actor (blade out, airborne)")
	t.check(not controller.is_third_person(), "camera stays put when using the blade or flying")
	# Riding pulls the camera back without touching the on-foot choice.
	var bike = main.raid.spawn_vehicle("bike_scrapper", p.global_position + Vector3(3, 0.3, 0), 0.0)
	await t.frames(5)
	t.check(bike.mount(p), "the player gets on a bike")
	await t.frames(40)
	t.check(controller.is_third_person() and controller.view_mode == PlayerController.ViewMode.FIRST,
			"riding uses third-person and keeps the on-foot view choice")
	controller.toggle_view()
	await t.frames(40)
	t.check(not controller.is_third_person(), "V still switches the view while riding")
	controller.toggle_view()
	bike.dismount()
	await t.frames(40)
	t.check(not controller.is_third_person(), "getting off returns to the on-foot view")
	controller.toggle_view()
	await t.frames(40)
	t.check(controller.is_third_person(), "the toggle switches to third-person")
	# The HUD lives on your gear: a holographic watch and a counter on the gun.
	var wrist: Hud.Wrist = main.hud.wrist
	var holo := wrist.get_node("Hologram") as Node3D
	t.check(not controller.wrist_raised and not holo.visible, "the watch's hologram is down until you raise it")
	var x_key := InputEventAction.new()
	x_key.action = "check_wrist"
	x_key.pressed = true
	controller._unhandled_input(x_key)
	await t.frames(30)
	t.check(controller.wrist_raised and wrist.is_open() and holo.visible and wrist.get_parent() == p
			and wrist.text().contains(main.raid.world.display_name) and wrist.text().contains("Pack "),
			"X raises the watch, and in third person its card opens over your wrist")
	# Judged on a wide screen like a player's (headless, the window is a
	# small square).
	var window_was := t.get_tree().root.size
	t.get_tree().root.size = Vector2i(1600, 900)
	await t.frames(3)
	var card_width := holo.global_basis.get_scale().x * wrist.face_size.x
	var cam := controller.camera
	var card_left := cam.unproject_position(holo.global_position - cam.global_basis.x * card_width * 0.5)
	var card_right := cam.unproject_position(holo.global_position + cam.global_basis.x * card_width * 0.5)
	var screen := cam.get_viewport().get_visible_rect().size
	t.check(cam.global_position.distance_to(holo.global_position) > cam.global_position.distance_to(p.get_eye_position())
			and (card_right.x - card_left.x) > screen.x * 0.25 and card_left.x >= 0.0,
			"the third-person card stands past the character, big enough to read and whole on screen (%d px wide)"
			% roundi(card_right.x - card_left.x))
	var head_on_screen := cam.unproject_position(p.get_eye_position())
	# Only the card's bare right margin (`tp_tuck`) may sit behind the head;
	# its text stays clear of the character.
	var text_right := card_right.x - (card_right.x - card_left.x) * wrist.tp_tuck
	t.check(text_right < head_on_screen.x and text_right < screen.x * 0.5,
			"and beside the character, its text clear of the head and the crosshair (text to %d, head at %d, of %d)"
			% [roundi(text_right), roundi(head_on_screen.x), roundi(screen.x)])
	# Close to the body: its lower edge sits just over the watch.
	var edge_low := cam.unproject_position(holo.global_position - holo.global_basis.y * wrist.face_size.y * 0.5)
	var watch_at := cam.unproject_position(wrist.watch_position(p))
	t.check(edge_low.y < watch_at.y and watch_at.y - edge_low.y < screen.y * 0.1,
			"it sits close to the body, its lower edge just over the watch (%d px over it)" % roundi(watch_at.y - edge_low.y))
	# The light rises from the watch up into the card's lower edge (Caleb's
	# feedback: never slanting down to it), and runs outwards along it.
	var card_low := cam.unproject_position(holo.global_position - holo.global_basis.y * wrist.face_size.y * 0.5)
	var watch_seen := cam.unproject_position(wrist.watch_position(p))
	t.check(card_low.y < watch_seen.y and wrist.BEAM_SHADER.contains("TIME"),
			"the light rises from the watch up into the card, with bands running out along it (card edge at %d, watch at %d)"
			% [roundi(card_low.y), roundi(watch_seen.y)])
	# The weapon and toy holograms over the card are smaller than from the
	# eyes and stay in the view (Caleb's feedback: they were cut off at the
	# top); the card keeps its size.
	var rows_top := cam.unproject_position(holo.global_position + holo.global_basis.y
			* (wrist.face_size.y * 0.5 + wrist.rows_tall * wrist._row_scale))
	t.check(wrist._row_scale <= wrist.tp_rows and wrist._row_scale < 1.0 and rows_top.y >= 0.0,
			"the holograms over the card are drawn smaller and stay on screen (%.2f of their size, top at %d)"
			% [wrist._row_scale, roundi(rows_top.y)])
	t.get_tree().root.size = window_was
	await t.frames(2)
	var holo_mat := holo.material_override as ShaderMaterial
	t.check(not holo_mat.shader.code.contains("depth_test_disabled") and float(holo_mat.get_shader_parameter("backing")) > 0.3
			and float(holo_mat.get_shader_parameter("backing")) < 0.8,
			"in third person it is backed but still see-through, and the body in front of it hides what it covers")
	t.check(p.cmd.watch_up, "and the raised watch goes out with your inputs, so the arm glows for everyone")
	var icons: Array = []
	for slot in wrist.card.slots:
		icons.append(slot.id)
	t.check(icons == Hud.Wrist.SLOTS, "the card is a row of icons: %s" % ", ".join(icons))
	t.check((wrist.card.bars.is_empty()) if p.visor.enabled else (wrist.card.bars.size() >= 3),
			"in third person the card carries the vitals strip only with no helmet: a visor shows them flat in either view")
	# The mouse wheel steps across the card; the mouse only looks.
	var yaw_before := controller.yaw
	var weapon_before := p.active_weapon_index
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(-200.0, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		controller._unhandled_input(look)
		t.check(controller.yaw > yaw_before and not controller.watch_focus_moved,
				"with the watch up the mouse turns the view and leaves the card alone")
	controller.yaw = yaw_before
	for i in 20:
		controller.scroll(-1)
	await t.frames(2)
	t.check(controller.watch_focus == 0 and wrist.focused_id() == "weapon" and controller.weapon_pick == 0
			and wrist.card.focused_tab() == "summon",
			"scrolling up steps the card left to the weapons, on the Summon tab")
	controller.scroll(-1)
	t.check(controller.watch_focus == 0, "and it stops at the card's left end")
	controller.scroll(1)
	await t.frames(2)
	t.check(wrist.focused_id() == "vehicle" and controller.weapon_pick == 0,
			"scrolling down steps right an icon a notch, past the weapons without turning through them")
	for i in 10:
		if wrist.card.focused_tab() == "status":
			break
		controller.scroll(1)
		await t.frames(2)
	t.check(wrist.card.focused_tab() == "status" and wrist.focused_id() == "map"
			and wrist.text().begins_with(main.raid.world.display_name),
			"past the Summon tab the wheel steps on to Status: the map and your standing")
	for i in 20:
		controller.scroll(1)
	await t.frames(2)
	t.check(wrist.focused_id() == "leave" and wrist.card.focused_tab() == "mission",
			"and stops at the right end on sign-out, on the Mission tab")
	t.check(controller._pending_switch < 0 and p.active_weapon_index == weapon_before and is_equal_approx(controller.yaw, yaw_before),
			"with the watch up the wheel never switches weapons or turns the view")
	controller.toggle_view()
	await t.frames(40)
	t.check(wrist.get_parent() == p and holo.visible,
			"in first person the card rises off the watch on your own wrist, as in third person")
	var card_angle := holo.global_basis.get_scale().x * wrist.face_size.x / controller.camera.global_position.distance_to(holo.global_position)
	t.check(card_angle < 0.6, "the card is card-sized, not a panel (%.2f)" % card_angle)
	t.check(wrist.get_node("Beam").visible and (wrist.get_node("Beam") as MeshInstance3D).mesh.get_surface_count() > 0
			and is_equal_approx(float((holo.material_override as ShaderMaterial).get_shader_parameter("open")), 1.0),
			"light is thrown up from the watch face to the card, which is drawn as a hologram")
	t.check(Hud.Wrist.face_tint(0.1).r > 0.9 and Hud.Wrist.face_tint(1.0).b > 0.9,
			"the watch face glows red when you are low and cyan when you are well")
	controller._unhandled_input(x_key)
	await t.frames(30)
	t.check(not controller.wrist_raised and not holo.visible, "X again puts it away")
	var leaving := Hud.watch_slots(main.raid, p, 0, "", 0.5)
	var leave_at := Hud.Wrist.SLOTS.find("leave")
	t.check(is_equal_approx(float(leaving[leave_at].progress), 0.5) and Hud.default_focus(leaving) == leave_at,
			"signing out fills a ring on the sign-out icon, and the card opens on it")
	t.check(Hud.watch_slots(main.raid, p)[Hud.Wrist.SLOTS.find("artifact")].empty,
			"with no artifact on, the artifact slot is an empty socket")
	# One long frame must not throw the landing dip's spring (and the camera).
	controller._dip_speed = 9.0
	controller._update_dip(0.5)
	t.check(is_finite(controller._dip) and absf(controller._dip) < 0.3, "a long frame leaves the landing dip steady")
	var gun: Gun = null
	for w in p.weapons:
		if w is Gun:
			gun = w
	if gun != null and gun.visual != null:
		var counter := gun.visual.get_node_or_null(Hud.AMMO_COUNTER) as Label3D
		t.check(counter != null and counter.text == Hud.ammo_text(gun) and counter.text.begins_with(str(gun.ammo_in_mag)),
				"the gun counts its own rounds")
	# A jetpack's screen bay shows its heat. Headless there is no skin to
	# build the model, so a bay is fitted by hand as the rig model names it.
	var bay := Marker3D.new()
	bay.name = Hud.HEAT_DISPLAY
	bay.set_meta("size", Vector2(0.13, 0.15))
	p.add_child(bay)
	var had_flight := p.flight.enabled
	p.flight.enabled = true
	var cooling := p.flight.cool_per_sec
	p.flight.cool_per_sec = 0.0
	p.flight.heat = p.flight.max_heat * 0.5
	await t.frames(2)
	var gauge := bay.get_node_or_null(Hud.HEAT_READOUT)
	t.check(gauge != null and (gauge.get_node("Word") as Label3D).text == Hud.heat_text(p.flight)
			and Hud.heat_text(p.flight) == "50%", "the jetpack's screen bay shows its heat")
	t.check(is_equal_approx((gauge.get_node("Fill") as Node3D).scale.y, 0.5), "its gauge fills with the heat")
	p.flight.overheated = true
	t.check(Hud.heat_text(p.flight) == "HOT" and Hud.heat_color(0.5, true).r > 0.9, "an overheated pack reads HOT in red")
	p.flight.overheated = false
	p.flight.heat = 0.0
	p.flight.cool_per_sec = cooling
	p.flight.enabled = had_flight
	bay.queue_free()
	var buzzed: Array[String] = []
	main.hud.notice_sink = func(text: String) -> void: buzzed.append(text)
	main.raid.war_feed.emit("Test news")
	t.check(buzzed.size() == 1 and buzzed[0] == "Test news", "war news goes to the phone, not over the screen")
	main.hud.notice_sink = main.phone.show_notice
	var corpse: Actor = main.raid.player
	corpse.kill("test")
	await t.frames(10)
	t.check(main.raid != null and not main.hub.visible, "dying keeps you in the world")
	t.check((wrist.text().contains("You died") or wrist.text().contains("Killed by")) and wrist.raised,
			"going down raises the watch, and what the death cost is read off it")
	main._on_redeploy_requested()
	t.check(main.raid.player == corpse, "you cannot drop back in at once")
	main._redeploy_at = 0
	main._on_redeploy_requested()
	await t.frames(5)
	var reborn: Actor = main.raid.player
	t.check(reborn != corpse and not reborn.is_dead and main.controller.actor == reborn
			and main.controller.camera.current and main.hud.raid == main.raid,
			"Enter drops you back in with the camera and HUD on your new body")
	t.check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless",
			"the mouse stays captured across a redeploy")
	main._on_sign_out_requested()
	t.check(main.raid.sign_out_progress(reborn) >= 0.0, "L starts a sign-out")
	main._on_sign_out_requested()
	t.check(main.raid.sign_out_progress(reborn) < 0.0, "L again calls it off")
	main._on_sign_out_requested()
	main.raid.state_for(reborn).sign_out_left = 0.1
	await t.frames(90)
	t.check(main.raid == null and main.base != null and not main.hub.visible,
			"a finished sign-out takes you home to your base")
	main.start_raid("ashfront")
	await t.frames(5)
	main.raid.player.kill("test")
	await t.frames(5)
	main._on_sign_out_requested()
	await t.frames(2)
	t.check(main.raid == null and main.base != null, "L while down takes you home")
	main.queue_free()
	await t.frames(2)


## Sets up the player with the blade out, facing a brute that stands in reach.
