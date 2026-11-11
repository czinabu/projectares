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
	if args.size() > 1:
		await _world_shots(out_dir, args[1])
		get_tree().quit()
		return

	var hub := Hub.new()
	add_child(hub)
	await _settle(10)
	await _shot(out_dir.path_join("hub.png"))
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
	raid.queue_free()
	await _settle(2)
	await _world_shots(out_dir)
	get_tree().quit()


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
	}
	for file: String in views:
		camera.look_at_from_position(views[file][0], views[file][1])
		await _settle(4)
		await _shot(out_dir.path_join(file))
	base.queue_free()
	await _settle(2)


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
	var to := lineup[1].global_position - raid.player.global_position
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


func _settle(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
