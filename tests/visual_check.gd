extends Node
## Dev tool: runs a real raid with camera and HUD and saves screenshots, so the
## visuals can be checked without playing. Needs a display (or xvfb):
##   godot --path . res://tests/visual_check.tscn -- <output_dir>
## Add a world id after the folder to shoot only that world.

func _ready() -> void:
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	Profile.persist = false
	if args.size() > 1 and not args[1].begins_with("--"):
		await _world_shots(out_dir, args[1])
		get_tree().quit()
		return

	# `-- <output_dir> --rigs-only` shoots each flight rig being worn.
	if "--rigs-only" in args:
		await _rig_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --gait-only` shoots the legs: run, sprint, strafe, slide.
	if "--gait-only" in args:
		await _gait_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --idle-only` shoots the player standing still.
	if "--idle-only" in args:
		await _idle_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --visors-only` shoots each helmet's visor in first person.
	if "--visors-only" in args:
		await _visor_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --arena-only` shoots just the arena.
	if "--arena-only" in args:
		await _arena_shots(out_dir)
		get_tree().quit()
		return

	var hub := Hub.new()
	add_child(hub)
	hub.set_online_status("Connecting to 192.168.1.20...")
	hub.show_travel()
	await _settle(10)
	await _shot(out_dir.path_join("travel.png"))
	hub.open_station("wardrobe")
	# The customizer, on a few looks.
	var looks := [
		{"build": "f", "head": "Adventurer", "body": "Casual", "legs": "Worker", "feet": "Worker", "skin": 3, "hair": 5, "top": 6, "bottom": 1},
		{"build": "m", "head": "Casual_2", "body": "Casual_Hoodie", "legs": "Farmer", "feet": "Beach", "skin": 1, "hair": 2, "top": 3, "bottom": 0},
		{"build": "m", "head": "Farmer", "body": "Beach", "legs": "Casual_2", "feet": "Casual_2", "skin": 5, "hair": 0, "top": 0, "bottom": 0},
	]
	for i in looks.size():
		hub.character.set_appearance(looks[i])
		hub.character.show_customizer()
		hub.character._turn = 0.35
		await _settle(8)
		await _shot(out_dir.path_join("customizer_%d.png" % (i + 1)))
	hub.character.hide_customizer()
	hub.queue_free()
	await _base_shots(out_dir)
	# `-- <output_dir> --base-only` stops after the home base.
	if "--base-only" in args:
		get_tree().quit()
		return

	# `-- <output_dir> --war-only` shows the sky at three war intensities.
	if "--war-only" in args:
		await _war_shots(out_dir)
		get_tree().quit()
		return

	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)

	await _settle(90)
	await _shot(out_dir.path_join("first_person.png"))
	controller.wrist_raised = true
	await _settle(30)
	await _shot(out_dir.path_join("first_person_watch.png"))
	controller.wrist_raised = false
	await _settle(30)
	# Mid-burst, to catch the muzzle flash and impact sparks.
	Input.action_press("fire")
	await _settle(9)
	await _shot(out_dir.path_join("first_person_firing.png"))
	Input.action_release("fire")
	await _settle(20)
	Input.action_press("weapon_2")
	await _settle(30)
	Input.action_release("weapon_2")
	await _shot(out_dir.path_join("first_person_blade.png"))
	Input.action_press("alt_fire")
	await _settle(20)
	await _shot(out_dir.path_join("first_person_guard.png"))
	Input.action_release("alt_fire")
	await _settle(10)
	controller.stance = MeleeWeapon.Dir.LEFT
	await _settle(2)
	Input.action_press("alt_fire")
	await _settle(20)
	await _shot(out_dir.path_join("first_person_guard_left.png"))
	Input.action_release("alt_fire")
	# An enemy winding up a swing from its right, which arrives on your left.
	var foe := raid.bots[0]
	for child in foe.get_children():
		if child is BotBrain:
			child.set_physics_process(false)
	var ahead := raid.player.get_aim_dir()
	ahead.y = 0.0
	foe.global_position = raid.player.global_position + ahead.normalized() * 2.4
	foe.cmd.move = Vector2.ZERO
	foe.cmd.yaw = controller.yaw + PI
	foe.cmd.aim_dir = -ahead.normalized()
	# Each side an enemy can wind up from, a swing part way and at its end,
	# a guard, and a two-handed weapon, to check the arm, the grip and the
	# blade all show the side.
	var poses := [
		{"dir": MeleeWeapon.Dir.RIGHT, "file": "enemy_windup.png"},
		{"dir": MeleeWeapon.Dir.LEFT, "file": "enemy_windup_left.png"},
		{"dir": MeleeWeapon.Dir.OVERHEAD, "file": "enemy_windup_overhead.png"},
		{"dir": MeleeWeapon.Dir.RIGHT, "file": "enemy_swing_mid.png", "swing": 0.5},
		{"dir": MeleeWeapon.Dir.RIGHT, "file": "enemy_swing_end.png", "swing": 1.0},
		{"dir": MeleeWeapon.Dir.LEFT, "file": "enemy_guard_left.png", "guard": true},
		{"dir": MeleeWeapon.Dir.RIGHT, "file": "enemy_hammer_windup.png", "item": "hammer_breaker"},
		{"dir": MeleeWeapon.Dir.OVERHEAD, "file": "enemy_idle_blade.png", "idle": true},
		{"dir": MeleeWeapon.Dir.OVERHEAD, "file": "enemy_idle_hammer.png", "idle": true, "item": "hammer_breaker"},
	]
	for pose: Dictionary in poses:
		for w in foe.weapons:
			if w.visual:
				w.visual.queue_free()
			w.queue_free()
		foe.weapons.clear()
		var cleaver := MeleeWeapon.new()
		# Long enough to still be cocked when the shot is taken on a slow renderer.
		cleaver.light_windup = 60.0
		cleaver.light_damage = 0.0
		cleaver.light_stamina = 0.0
		cleaver.item_id = pose.get("item", "")
		foe.equip_weapon(cleaver)
		foe.active_weapon_index = 0
		foe.cmd.stance = pose["dir"]
		foe.cmd.secondary = pose.get("guard", false)
		await _settle(5)
		# Held until a physics tick has certainly seen it.
		for i in 6:
			foe.cmd.primary_pressed = not pose.has("guard") and not pose.has("idle") and not cleaver.is_winding_up()
			await _settle(1)
		foe.cmd.primary_pressed = false
		await _settle(14)
		if pose.has("swing"):
			# A swing lasts a few frames, so freeze the enemy part way through it.
			foe.set_physics_process(false)
			cleaver._windup_left = 0.0
			for i in 14:
				cleaver._swing_left = MeleeWeapon.SWING_TIME * (1.0 - pose["swing"]) + 0.017
				cleaver._animate(0.016)
				await _settle(1)
		await _shot(out_dir.path_join(pose["file"]))
		foe.set_physics_process(true)
	foe.cmd.secondary = false
	foe.global_position += Vector3(0, -200, 0)
	hud._on_hit_confirmed(raid.player, DamageInfo.make(1.0, raid.player, "melee"), false)
	Sfx.play("parry")
	await _settle(2)
	controller.toggle_view()
	await _settle(60)
	await _shot(out_dir.path_join("third_person.png"))
	controller.wrist_raised = true
	await _settle(30)
	await _shot(out_dir.path_join("third_person_watch.png"))
	controller.camera.fov = 110.0
	controller.base_fov_third = 110.0
	await _settle(30)
	await _shot(out_dir.path_join("third_person_watch_wide.png"))
	raid.queue_free()
	await _settle(2)
	await _world_shots(out_dir)
	get_tree().quit()


## Each flight rig on a player, at rest and firing (thrusting, an air jump's
## burn, or gliding), from behind, the side and the front.
func _rig_shots(out_dir: String) -> void:
	for id: String in ["jetpack_mk1", "jetpack_mk2", "boots_thruster", "wings_glide"]:
		var raid := Raid.new()
		add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", id, "frame_trooper"])
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -200, 0)
		var camera := Camera3D.new()
		camera.fov = 50.0
		raid.add_child(camera)
		camera.make_current()
		var p := raid.player
		# The HUD lights a jetpack's screen bay with its heat; hidden, so
		# nothing else of it shows.
		var hud := Hud.new()
		hud.setup(raid, null)
		hud.visible = false
		raid.add_child(hud)
		await _settle(30)
		p.set_physics_process(false)
		p.flight.heat = p.flight.max_heat * 0.55
		var at := p.global_position
		var back := p.global_transform.basis.z
		var side := p.global_transform.basis.x
		var skin := p.get_node("Skin")
		var views := {
			"back": at + back * 2.6 + side * 0.6 + Vector3(0, 1.7, 0),
			"side": at + side * 2.6 + back * 0.9 + Vector3(0, 1.3, 0),
			"front": at - back * 2.6 + side * 0.9 + Vector3(0, 1.5, 0),
			"above": at + back * 1.6 + side * 0.4 + Vector3(0, 3.2, 0),
		}
		for active: bool in [false, true]:
			p.flight.is_thrusting = active and p.flight.thrust_accel > 0.0
			p.flight.is_gliding = active and p.flight.can_glide()
			for view: String in views:
				if active and p.flight.burst_velocity > 0.0 and not p.flight.can_glide():
					skin._burst_left = 10.0
				camera.look_at_from_position(views[view], at + Vector3(0, 0.95 if view != "front" else 1.0, 0))
				await _settle(30 if active and view == "back" else 6)
				await _shot(out_dir.path_join("rig_%s_%s%s.png" % [id, view, "_on" if active else ""]))
		raid.queue_free()
		await _settle(3)


## Every world from a few fixed angles, with some of its bots lined up in
## front of the player so their models can be checked.
func _world_shots(out_dir: String, only := "") -> void:
	for world in Worlds.all():
		if only != "" and world.id != only:
			continue
		var raid := Raid.new()
		add_child(raid)
		raid.start(world, 42)
		var camera := Camera3D.new()
		camera.fov = 75.0
		raid.add_child(camera)
		camera.make_current()
		var p := raid.player.global_position
		var toward := -Vector3(p.x, 0, p.z).normalized()
		var side := toward.cross(Vector3.UP)
		var lineup: Array[Actor] = []
		lineup.assign(raid.bots.slice(0, 4))
		if world.safe_zone:
			# A safe zone has no bots: line up other players in their gear instead.
			var kits := [["dmr_longshot", "frost_ice_axe", "wings_glide", "frame_bulwark"],
					["smg_stinger", "blade_scrap", "jetpack_mk1", "frame_runner"],
					["rifle_carbine", "blade_scrap", "jetpack_mk1", "frame_trooper"]]
			for k in kits.size():
				lineup.append(raid.add_player(kits[k].filter(func(id: String) -> bool: return ItemDB.has_item(id)),
						{}, ["Vex", "Juno", "Ash"][k]))
		for i in lineup.size():
			var bot := lineup[i]
			for child in bot.get_children():
				if child is BotBrain:
					child.set_physics_process(false)
			bot.global_position = p + toward * 5.0 + side * (i * 2.0 - 3.0) + Vector3(0, 0.2, 0)
			bot.cmd.move = Vector2.ZERO
			bot.cmd.primary = false
			bot.cmd.yaw = atan2(toward.x, toward.z)
		await _settle(60)
		camera.look_at_from_position(p - toward * 3.0 + Vector3(0, 2.2, 0), p + toward * 6.0 + Vector3(0, 1.0, 0))
		await _settle(4)
		await _shot(out_dir.path_join("%s_characters.png" % world.id))
		camera.look_at_from_position(p + Vector3(0, 1.7, 0) - toward, Vector3(0, 7, 0))
		await _settle(4)
		await _shot(out_dir.path_join("%s_street.png" % world.id))
		camera.look_at_from_position(p * 0.45 + Vector3(0, 30, 0), Vector3(0, 2, 0))
		await _settle(4)
		await _shot(out_dir.path_join("%s_overview.png" % world.id))
		# A map with strongpoints: one shot of each, from the side facing out.
		var site_index := 0
		for site in get_tree().get_nodes_in_group("strongpoint"):
			if not raid.map.is_ancestor_of(site):
				continue
			var at: Vector3 = site.global_position
			var out := Vector3(at.x, 0, at.z).normalized() if Vector3(at.x, 0, at.z).length() > 1.0 else Vector3(0.6, 0, 0.8)
			var from := at + out.rotated(Vector3.UP, 0.5) * (float(site.get_meta("radius", 30.0)) + 34.0)
			if raid.map.has_method("ground_height"):
				from.y = raid.map.call("ground_height", from.x, from.z)
			camera.far = 1500.0
			camera.look_at_from_position(from + Vector3(0, 9, 0), at + Vector3(0, 5, 0))
			await _settle(8)
			await _shot(out_dir.path_join("%s_site_%d.png" % [world.id, site_index]))
			site_index += 1
		if world.safe_zone:
			await _plaza_shots(out_dir, raid, camera, lineup)
		raid.queue_free()
		await _settle(2)


## The home base with one of everything on show, from a few fixed angles.
func _base_shots(out_dir: String) -> void:
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher", "blade_arc",
			"hammer_breaker", "frame_runner", "frame_trooper", "frame_bulwark", "jetpack_mk2", "boots_thruster",
			"wings_glide", "chip_blink", "chip_barrier", "chip_pulse", "bike_scrapper", "bike_raider", "medkit",
			"medkit", "scrap_metal", "scrap_metal", "scrap_metal", "alloy_ingot", "reactor_core", "lattice_shard"],
			{"primary": "dmr_longshot", "frame": "frame_bulwark", "vehicle": "bike_raider"})
	add_child(base)
	var camera := Camera3D.new()
	camera.fov = 75.0
	base.add_child(camera)
	camera.make_current()
	base.player.global_position = Vector3(3, 0.1, 2)
	await _settle(40)
	var views := {
		"base_overview.png": [Vector3(0, 3.2, 8.2), Vector3(0, 1.2, -4)],
		"base_weapons.png": [Vector3(-3, 1.9, -4.2), Vector3(-4.5, 1.5, -9)],
		"base_blades.png": [Vector3(6, 1.9, -5.2), Vector3(6, 1.5, -9)],
		"base_armor.png": [Vector3(-6.0, 1.8, -1.5), Vector3(-11, 1.2, -2.5)],
		"base_rigs.png": [Vector3(6.0, 1.8, -1.0), Vector3(11, 1.2, -1.0)],
		"base_garage.png": [Vector3(-1.0, 2.0, 3.2), Vector3(-2.5, 0.6, -1.5)],
		"base_shelves.png": [Vector3(-6.5, 1.8, 4.6), Vector3(-7, 1.2, 9)],
		"base_stations_left.png": [Vector3(-1.5, 2.2, 6.5), Vector3(-6.6, 1.0, 3.1)],
		"base_stations_right.png": [Vector3(1.5, 2.2, 6.5), Vector3(6.6, 1.0, 3.1)],
		"base_launch.png": [Vector3(0, 2.4, 7.8), Vector3(0, 0.6, 1.5)],
	}
	for file: String in views:
		camera.look_at_from_position(views[file][0], views[file][1])
		await _settle(4)
		await _shot(out_dir.path_join(file))
	# A station's screen, live on the console: from across the room, then
	# moved in to use it.
	var screen_view := SubViewport.new()
	screen_view.size = Vector2i(1280, 720)
	screen_view.disable_3d = true
	add_child(screen_view)
	var hub := Hub.new()
	screen_view.add_child(hub)
	for id: String in ["locker", "trader", "launch"]:
		hub.open_station(id)
		var live := WorldScreen.new()
		live.size = HomeBase.SCREEN_SIZE
		live.viewport = screen_view
		base.station(id).screen.add_child(live)
		var face: Node3D = base.station(id).screen
		camera.make_current()
		camera.look_at_from_position(face.global_position + face.global_basis.z * 3.2 + Vector3(0, 0.3, 0), face.global_position)
		await _settle(6)
		await _shot(out_dir.path_join("base_%s_console.png" % id))
		live.focus()
		await _settle(30)
		await _shot(out_dir.path_join("base_%s_screen.png" % id))
		live.unfocus()
		live.queue_free()
		hub.close()
	screen_view.queue_free()
	base.queue_free()
	await _settle(2)


## The arena from the stands, during an exhibition bout, with its overlay.
func _arena_shots(out_dir: String) -> void:
	var arena := Arena.new()
	add_child(arena)
	arena.call_time = 1.0
	arena.countdown_time = 0.5
	arena.exhibition_delay = 0.2
	arena.start_solo(["rifle_carbine", "blade_scrap", "plate_light"])
	var controller := PlayerController.new()
	controller.setup(arena.player)
	arena.add_child(controller)
	var hud := Hud.new()
	hud.setup(arena, controller)
	arena.add_child(hud)
	var overlay: CanvasLayer = preload("res://core/arena/arena_hud.gd").new()
	overlay.setup(arena)
	arena.add_child(overlay)
	# Look down into the pit from where you stand.
	var to_center := -arena.player.global_position
	controller.yaw = atan2(-to_center.x, -to_center.z)
	controller.pitch = 0.1
	await _settle(60)
	await _shot(out_dir.path_join("arena_calling.png"))
	# A bookmaker's booth in the stands, from its spot and then in use.
	var booth: Node3D = get_tree().get_nodes_in_group("arena_booth")[0]
	var stood := arena.player.global_position
	arena.player.global_position = booth.global_position + Vector3(0, 0.1, 0)
	var to_booth: Vector3 = (booth.get_node("Screen") as Node3D).global_position - booth.global_position
	controller.yaw = atan2(-to_booth.x, -to_booth.z)
	controller.pitch = 0.0
	await _settle(30)
	await _shot(out_dir.path_join("arena_booth.png"))
	overlay.open_booth(booth)
	hud.visible = false
	arena.player.hand.visible = false
	await _settle(40)
	await _shot(out_dir.path_join("arena_booth_screen.png"))
	overlay.close_booth()
	hud.visible = true
	arena.player.hand.visible = true
	arena.player.global_position = stood
	controller.yaw = atan2(-to_center.x, -to_center.z)
	controller.pitch = -0.35
	await _settle(200)
	await _shot(out_dir.path_join("arena_fight.png"))
	controller.view_mode = PlayerController.ViewMode.THIRD
	await _settle(30)
	await _shot(out_dir.path_join("arena_third_person.png"))


## The plaza as a player sees it: the gates, and another player's gear card.
func _plaza_shots(out_dir: String, raid: Raid, camera: Camera3D, lineup: Array[Actor]) -> void:
	camera.look_at_from_position(Vector3(0, 5, -12), Vector3(0, 6, -40))
	await _settle(4)
	await _shot(out_dir.path_join("%s_gates.png" % raid.world.id))
	camera.look_at_from_position(Vector3(8, 4, -8), Vector3(30, 3, -30))
	await _settle(4)
	await _shot(out_dir.path_join("%s_market.png" % raid.world.id))
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	var view: CanvasLayer = load("res://core/social/plaza_view.gd").new()
	view.setup(raid, {})
	raid.add_child(view)
	# The line-up may have been cleared away by now; shoot whoever is left.
	var subject: Actor = null
	for other in lineup:
		if is_instance_valid(other):
			subject = other
	if subject:
		var to := subject.global_position - raid.player.global_position
		controller.yaw = atan2(-to.x, -to.z)
		controller.pitch = -0.05
		await _settle(30)
		await _shot(out_dir.path_join("%s_inspect.png" % raid.world.id))
	for portal in get_tree().get_nodes_in_group("portal"):
		if portal.get_meta("destination", "") == "home":
			raid.player.global_position = portal.global_position + Vector3(0, 0.2, 0)
			controller.yaw = PI / 2.0
	await _settle(30)
	await _shot(out_dir.path_join("%s_portal.png" % raid.world.id))
	# A storefront's terminal, from its pad and then in use.
	var stall: Node3D = get_tree().get_nodes_in_group("shop_front")[0]
	var mount: Node3D = stall.get_node("Screen")
	raid.player.global_position = stall.global_position + Vector3(0, 0.2, 0)
	var to_screen := mount.global_position - raid.player.global_position
	controller.yaw = atan2(-to_screen.x, -to_screen.z)
	controller.pitch = -0.1
	await _settle(30)
	await _shot(out_dir.path_join("%s_stall.png" % raid.world.id))
	var screen_view := SubViewport.new()
	screen_view.size = Vector2i(1280, 720)
	screen_view.disable_3d = true
	var shop: Control = (load("res://core/main.gd") as GDScript).ShopView.new()
	shop.panel = load("res://core/economy/shop_panel.gd").new()
	shop.panel.set("shop_filter", stall.get_meta("shop_id", ""))
	screen_view.add_child(shop)
	raid.add_child(screen_view)
	var live := WorldScreen.new()
	live.viewport = screen_view
	mount.add_child(live)
	live.focus()
	hud.visible = false
	view.visible = false
	await _settle(40)
	await _shot(out_dir.path_join("%s_stall_screen.png" % raid.world.id))
	live.unfocus()


func _settle(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Each helmet's visor through its wearer's eyes: the Scav Visor, the
## Spotter resting and zoomed, the Seeker ready and just after a scan.
func _visor_shots(out_dir: String) -> void:
	var scrap: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"]
	for helmet: String in ["visor_scav", "helm_spotter", "helm_seeker"]:
		var raid := Raid.new()
		add_child(raid)
		var kit := scrap.duplicate()
		kit.append(helmet)
		raid.start(Worlds.get_world("ashfront"), 42, kit)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
		var p := raid.player
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		var hud := Hud.new()
		hud.setup(raid, controller)
		raid.add_child(hud)
		await _settle(30)
		var look := Basis.from_euler(Vector3(0.0, controller.yaw, 0.0))
		var places := [Vector3(3, 0.3, -14), Vector3(-5, 0.3, -24), Vector3(9, 0.3, -30)]
		for i in places.size():
			raid.bots[i].global_position = p.global_position + look * places[i]
			raid.bots[i].cmd.yaw = controller.yaw + PI
		p.health.health = 28.0 if helmet == "visor_scav" else p.health.max_health
		await _settle(20)
		await _shot(out_dir.path_join("visor_%s.png" % helmet))
		if helmet == "helm_spotter":
			var to_bot: Vector3 = raid.bots[1].global_position + Vector3(0, 1.1, 0) - p.get_eye_position()
			controller.yaw = atan2(-to_bot.x, -to_bot.z)
			controller.pitch = asin(to_bot.normalized().y)
			controller._visor_level = 1
			await _settle(40)
			await _shot(out_dir.path_join("visor_helm_spotter_zoom.png"))
			p.visor.add_tag(raid.bots[1], 5.0)
			await _settle(6)
			await _shot(out_dir.path_join("visor_helm_spotter_tag.png"))
		elif helmet == "helm_seeker":
			p.visor.scan()
			await _settle(12)
			await _shot(out_dir.path_join("visor_helm_seeker_scan.png"))
			p.visor.felt_scan.emit(p.global_position + look * Vector3(20, 0, 5))
			await _settle(30)
			await _shot(out_dir.path_join("visor_helm_seeker_after.png"))
		raid.queue_free()
		await _settle(3)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


## The same view of Ashfront when quiet, in a battle and in all-out war.
func _war_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	raid.war.cooling = 0.0
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	var mood := raid.map.get_node("WarMood")
	for step: Array in [[0.0, "war_quiet"], [0.55, "war_battle"], [1.0, "war_all_out"]]:
		raid.war.intensity = step[0]
		raid.war.centre = raid.player.global_position + raid.player.get_aim_dir() * 170.0
		mood.follow = 100.0
		await _settle(240 if step[0] > 0.0 else 60)
		await _shot(out_dir.path_join(step[1] + ".png"))
	raid.queue_free()


## Contact sheets of the player's legs, side on and from the front, holding
## still while the skin is fed a velocity: one row of frames per way of moving.
func _gait_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.queue_free()
	var player := raid.player
	player.set_physics_process(false)
	await _settle(10)
	var skin: Node = player.get_node("Skin")
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var moves := [
		["jog", Vector3(0, 0, -player.walk_speed), 0.0],
		["sprint", Vector3(0, 0, -player.sprint_speed), 0.0],
		["strafe", Vector3(-player.walk_speed, 0, 0), 0.0],
		["diagonal", Vector3(-4.2, 0, -4.2), 0.0],
		["backpedal", Vector3(0, 0, player.walk_speed), 0.0],
		["slide", Vector3(0, 0, -player.slide_speed), 1.0],
	]
	for view: String in ["side", "front"]:
		var sheet := Image.create(6 * 320, moves.size() * 360, false, Image.FORMAT_RGBA8)
		for row in moves.size():
			var move: Array = moves[row]
			player.slide_left = 0.5 if move[2] > 0.0 else 0.0
			player.crouch = move[2]
			player.velocity = player.global_basis * move[1]
			for i in 6:
				for k in 5:
					skin._process(1.0 / 60.0)
					await get_tree().process_frame
				var at := player.global_position
				var side := player.global_basis.x if view == "side" else -player.global_basis.z
				cam.global_position = at + side * 5.5 + Vector3(0, 0.9, 0)
				cam.look_at(at + Vector3(0, 0.9, 0))
				await RenderingServer.frame_post_draw
				var frame := get_viewport().get_texture().get_image()
				var w := frame.get_width()
				var h := frame.get_height()
				var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
				cut.resize(320, 360)
				cut.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(i * 320, row * 360))
		sheet.save_png(out_dir.path_join("gait_%s.png" % view))
		print("saved gait_%s.png" % view)
	raid.queue_free()


## Contact sheets of the player standing still, side on and from the front: one
## row each for empty hands, a gun held low, a gun raised to shoot, and coming
## to a stop from a jog. Frames are spread over a few seconds to show breathing.
func _idle_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.queue_free()
	var player := raid.player
	player.set_physics_process(false)
	await _settle(10)
	var skin: Node = player.get_node("Skin")
	var gun := -1
	for i in player.weapons.size():
		if player.weapons[i] is Gun:
			gun = i
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var rows := ["empty", "gun_low", "gun_raised", "stop"]
	for view: String in ["side", "front"]:
		var sheet := Image.create(6 * 320, rows.size() * 360, false, Image.FORMAT_RGBA8)
		for row in rows.size():
			var kind: String = rows[row]
			player.active_weapon_index = -1 if kind == "empty" else gun
			for i in player.weapons.size():
				if player.weapons[i].visual:
					player.weapons[i].visual.visible = i == player.active_weapon_index
			player.cmd.primary = kind == "gun_raised"
			player.velocity = player.global_basis * Vector3(0, 0, -player.walk_speed) if kind == "stop" else Vector3.ZERO
			for k in 60:
				skin._process(1.0 / 60.0)
				await get_tree().process_frame
			player.velocity = Vector3.ZERO
			for i in 6:
				for k in (4 if kind == "stop" else 20):
					skin._process(1.0 / 60.0)
					await get_tree().process_frame
				var at := player.global_position
				var side := player.global_basis.x if view == "side" else player.global_basis.z
				cam.global_position = at + side * 5.5 + Vector3(0, 0.9, 0)
				cam.look_at(at + Vector3(0, 0.9, 0))
				await RenderingServer.frame_post_draw
				var frame := get_viewport().get_texture().get_image()
				var w := frame.get_width()
				var h := frame.get_height()
				var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
				cut.resize(320, 360)
				cut.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(i * 320, row * 360))
		sheet.save_png(out_dir.path_join("idle_%s.png" % view))
		print("saved idle_%s.png" % view)
	player.cmd.primary = false
	raid.queue_free()
