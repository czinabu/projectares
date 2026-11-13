extends Node
## Dev tool: runs a real raid with camera and HUD and saves screenshots, so the
## visuals can be checked without playing. Needs a display (or xvfb):
##   godot --path . res://tests/visual_check.tscn -- <output_dir>
## Add a world id after the folder to shoot only that world.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")

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

	# `-- <output_dir> --flight-only` shoots the attitudes in the air.
	# `--takeoff-only` shoots just the takeoff and the landing.
	if "--flight-only" in args or "--takeoff-only" in args:
		if "--flight-only" in args:
			await _flight_shots(out_dir)
		await _takeoff_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --gait-only` shoots the legs: run, sprint, strafe, slide.
	if "--gait-only" in args:
		await _gait_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --melee-only` shoots every melee weapon in hand.
	if "--melee-only" in args:
		var at := args.find("--melee-only")
		await _melee_shots(out_dir, args[at + 1] if at + 1 < args.size() else "")
		get_tree().quit()
		return

	# `-- <output_dir> --swing-only` films melee attacks frame by frame, one
	# row per move, so the motion (not one pose) can be judged.
	if "--swing-only" in args:
		await _swing_strips(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --views-only [row,row]` shoots each action in first
	# person, the third-person camera and from the front, side by side.
	if "--views-only" in args:
		var at := args.find("--views-only")
		await _view_shots(out_dir, args[at + 1] if args.size() > at + 1 else "")
		get_tree().quit()
		return
	# `-- <output_dir> --idle-only` shoots the player standing still.
	if "--idle-only" in args:
		await _idle_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --watch-only` shows the watch card raised: in first
	# person with no helmet (vitals on the card), with a helmet and a jetpack
	# (vitals and heat on the visor), each icon looked at, and in third person.
	# `--base-watch-only` shows just the home base's.
	if "--base-watch-only" in args:
		await _base_watch_shots(out_dir)
		get_tree().quit()
		return
	if "--watch-only" in args:
		await _watch_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --toys-only` shows the toy vehicles: on the watch, in
	# the hand, in the air, unpacking and unpacked.
	if "--toys-only" in args:
		await _toy_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --attachments-only` shoots the gunsmith bench with each
	# primary kitted out, and the view down a scope and a reflex sight.
	if "--attachments-only" in args:
		await _attachment_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --bench-only` shoots the gunsmith's workshop off the
	# armory and the bench in use: at rest, turning through the guns, and
	# turning through an attachment slot, as the player sees it.
	if "--bench-only" in args:
		await _bench_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --crafting-only` shoots the fabricator on the gunsmith
	# bench: in the starter bunker, in the armory, and its screen in use.
	if "--crafting-only" in args:
		await _crafting_shots(out_dir)
		get_tree().quit()
		return
	# `-- <output_dir> --holster-only [melee item id]` shoots holstered
	# weapons on the body, with that melee weapon in place of the kit's.
	if "--holster-only" in args:
		var at := args.find("--holster-only")
		await _holster_shots(out_dir, args[at + 1] if at + 1 < args.size() else "")
		get_tree().quit()
		return

	# `-- <output_dir> --ride-only` shoots the rider seated on a bike
	# (`RIDE_VEHICLE=<item id>` seats them on another vehicle).
	if "--ride-only" in args:
		await _ride_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --helmets-only` shoots each helmet and armor frame worn.
	if "--helmets-only" in args:
		await _helmet_shots(out_dir)
		get_tree().quit()
		return
	# `-- <output_dir> --visors-only` shoots each helmet's visor in first person.
	if "--visors-only" in args:
		await _visor_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --sidearms-only` shoots each sidearm model side on.
	if "--sidearms-only" in args:
		await _sidearm_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --hands-only` shoots the hands close up on every gun
	# and melee weapon, held low and aimed: each is held by its own grip.
	if "--hands-only" in args:
		await _hands_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --power-only` shoots the power weapons and their effects.
	if "--power-only" in args:
		await _power_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --artifacts-only` shows the artifacts at work: the
	# watch's artifact icon, Phase Cloak in first and third person, the
	# Time Rewind trail and the Static Bloom ring.
	if "--artifacts-only" in args:
		await _artifact_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --zones-only` shows Ashfront's risk zones: a gate
	# outpost from the field, and the burning core from its edge.
	if "--zones-only" in args:
		await _zone_shots(out_dir)
		get_tree().quit()
		return

	# `-- <output_dir> --phone-only` shows the phone held up, and someone
	# else holding theirs.
	if "--phone-only" in args:
		await _phone_shots(out_dir)
		get_tree().quit()
		return
	# `-- <output_dir> --arena-only` shoots just the arena.
	# `-- <output_dir> --hub-only` walks round the Concourse from fixed spots
	# and prints what a frame of it costs to draw.
	if "--hub-only" in args:
		await _hub_shots(out_dir)
		get_tree().quit()
		return

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
	Input.action_press("weapon_3")
	await _settle(30)
	Input.action_release("weapon_3")
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


func _watch_shots(out_dir: String) -> void:
	for helmet: String in ["", "helm_seeker"]:
		var raid := Raid.new()
		add_child(raid)
		var world := Worlds.get_world("ashfront")
		var kit: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light"]
		if helmet != "":
			kit.append(helmet)
		raid.start(world, 42, kit)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
		raid.state_for(raid.player).stowed.append("bike_raider")
		var p := raid.player
		# Loot in the pack for the carousel: two weapons, an artifact, scrap.
		for id: String in ["rifle_carbine", "knife_gutter", "artifact_cloak", "scrap_metal"]:
			p.inventory.add_item(id)
		p.health.health = p.health.max_health * 0.6
		p.stamina = p.max_stamina * 0.4
		p.flight.heat = p.flight.max_heat * 0.55
		p.flight.cool_per_sec = 0.0
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		var hud := Hud.new()
		hud.setup(raid, controller)
		raid.add_child(hud)
		await _settle(60)
		controller.wrist_raised = true
		await _settle(30)
		var tag := "helmet" if helmet != "" else "bare"
		await _shot(out_dir.path_join("watch_first_%s.png" % tag))
		if helmet == "":
			for i in Hud.Wrist.SLOTS.size():
				controller.watch_focus = i
				controller.watch_focus_moved = true
				await _settle(4)
				await _shot(out_dir.path_join("watch_look_%s.png" % Hud.Wrist.SLOTS[i]))
			# The weapon carousel on a weapon in the pack.
			controller.watch_focus = Hud.Wrist.SLOTS.find("weapon")
			controller.weapon_pick = 3
			await _settle(20)
			await _shot(out_dir.path_join("watch_carousel_pack_weapon.png"))
			controller.watch_focus_moved = false
		controller.toggle_view()
		await _settle(40)
		await _shot(out_dir.path_join("watch_third_%s.png" % tag))
		if helmet == "":
			# Third person on the carousel, then the summon: the carbine
			# digitizing into the hand, part way and done, in both views.
			controller.watch_focus = Hud.Wrist.SLOTS.find("weapon")
			controller.watch_focus_moved = true
			controller.weapon_pick = 3
			await _settle(20)
			await _shot(out_dir.path_join("watch_carousel_third.png"))
			controller.wrist_raised = false
			await _settle(30)
			raid.summon(p, "rifle_carbine")
			# Held half way through materializing for the picture.
			p.materialize_time = 30.0
			p.materialize_left = 15.0
			await _settle(10)
			await _shot(out_dir.path_join("summon_third_half.png"))
			p.materialize_left = 0.0
			await _settle(30)
			await _shot(out_dir.path_join("summon_third_done.png"))
			controller.toggle_view()
			raid.state_for(p).summon_ready_at = -INF
			await _settle(40)
			raid.summon(p, "rifle_scrap")
			p.materialize_time = 30.0
			p.materialize_left = 15.0
			await _settle(10)
			await _shot(out_dir.path_join("summon_first_half.png"))
			p.materialize_left = 0.0
			p.cmd.pitch = -0.25
			await _settle(10)
			raid.ping(p)
			await _settle(20)
			await _shot(out_dir.path_join("ping_first.png"))
		raid.queue_free()
		await _settle(3)
	await _base_watch_shots(out_dir)


## The watch raised in the home base, empty-handed (playtest: it half-raised
## with no card there): first person, then third.
func _base_watch_shots(out_dir: String) -> void:
	var base := HomeBase.new()
	base.show_gear(["bike_raider", "rifle_carbine"], {"vehicle": "bike_raider"})
	add_child(base)
	var controller := PlayerController.new()
	controller.setup(base.player)
	base.add_child(controller)
	var base_hud: CanvasLayer = preload("res://core/ui/base_hud.gd").new()
	base_hud.setup(base)
	base.add_child(base_hud)
	await _settle(60)
	controller.wrist_raised = true
	await _settle(30)
	await _shot(out_dir.path_join("watch_base_first.png"))
	controller.toggle_view()
	await _settle(40)
	await _shot(out_dir.path_join("watch_base_third.png"))
	# The pose itself, close up: from the front and from the left. These
	# cameras are not the player's, so the card stays turned to the player's.
	var close := Camera3D.new()
	close.fov = 50.0
	base.add_child(close)
	close.make_current()
	var p := base.player
	var face := p.find_child("WornWatch", true, false).get_child(0).get_node("Face") as Node3D
	var eye_dir := (p.get_eye_position() - face.global_position).normalized()
	print("watch face to eyes: %.0f degrees" % rad_to_deg(face.global_basis.y.normalized().angle_to(eye_dir)))
	for view: Array in [["front", Vector3(-0.5, 1.45, -1.4)], ["left", Vector3(-1.5, 1.4, -0.3)]]:
		close.look_at_from_position(p.global_transform * view[1], p.global_transform * Vector3(-0.1, 1.25, -0.2))
		await _settle(4)
		await _shot(out_dir.path_join("watch_base_pose_%s.png" % view[0]))
	base.queue_free()
	await _settle(3)


func _toy_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	var world := Worlds.get_world("ashfront")
	raid.start(world, 42, world.starter_loadout() + (["bike_scrapper"] as Array[String]))
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	raid.state_for(raid.player).stowed.append("bike_raider")
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await _settle(90)
	controller.wrist_raised = true
	await _settle(40)
	await _shot(out_dir.path_join("toys_watch_first.png"))
	controller.watch_index = 1
	await _settle(20)
	await _shot(out_dir.path_join("toys_watch_picked_second.png"))
	controller.watch_index = 0
	controller.take_picked_toy()
	await _settle(30)
	await _shot(out_dir.path_join("toys_in_hand.png"))
	controller.pitch = -0.1
	await _settle(5)
	controller.throw_held_toy()
	raid.throw_toy(raid.player, "bike_scrapper")
	await _settle(3)
	await _shot(out_dir.path_join("toys_in_air.png"))
	for i in 200:
		if raid.toys.is_empty():
			break
		await _settle(1)
	await _settle(1)
	await _shot(out_dir.path_join("toys_unpacking.png"))
	await _settle(60)
	await _shot(out_dir.path_join("toys_unpacked.png"))
	controller.toggle_view()
	controller.wrist_raised = true
	await _settle(60)
	await _shot(out_dir.path_join("toys_watch_third.png"))
	controller.take_picked_toy()
	await _settle(30)
	await _shot(out_dir.path_join("toys_in_hand_third.png"))
	raid.queue_free()
	await _settle(2)


## The body in the air: a jetpack hovering, boosting level and in a climb and
## barrel rolling in a sideways dash, wings level, banked into a turn each way and in a dive,
## and thruster boots skimming still, each way, aiming and dashing.
## Each from behind and from the side.
func _flight_shots(out_dir: String) -> void:
	# [name, rig, hovering, boosting, gliding, speed, climb, turn rate, look pitch, sideways air dash]
	var poses := [
		["jet_hover_strafe", "jetpack_mk2", true, false, false, 10.0, 0.0, 0.0, 0.0, 0, Vector3(1, 0, 0)],
		["jet_boost", "jetpack_mk2", true, true, false, 22.0, 0.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["jet_boost_setoff", "jetpack_mk2", true, true, false, 6.0, 0.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["jet_boost_climb", "jetpack_mk2", true, true, false, 16.0, 14.0, 0.0, 0.7, 0, Vector3.FORWARD],
		["jet_boost_roll", "jetpack_mk2", true, true, false, 22.0, 0.0, 0.0, 0.0, 1, Vector3.FORWARD],
		["air_leap", "jetpack_mk2", false, false, false, 7.0, 6.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["air_fall", "jetpack_mk2", false, false, false, 7.0, -12.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["jet_hover_forward", "jetpack_mk2", true, false, false, 10.0, 0.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["wings_level", "wings_glide", false, false, true, 16.0, -1.8, 0.0, 0.0, 0, Vector3.FORWARD],
		["wings_turn_left", "wings_glide", false, false, true, 16.0, -1.8, 1.4, 0.0, 0, Vector3.FORWARD],
		["wings_turn_right", "wings_glide", false, false, true, 16.0, -1.8, -1.4, 0.0, 0, Vector3.FORWARD],
		["wings_dive", "wings_glide", false, false, true, 24.0, -10.0, 0.0, -0.9, 0, Vector3.FORWARD],
		["wings_climb", "wings_glide", false, false, true, 18.0, 9.0, 0.0, 0.9, 0, Vector3.FORWARD],
		# Free look: flying one way, looking to the side and behind (a backstroke).
		["wings_freelook_side", "wings_glide", false, false, true, 16.0, -1.8, 0.0, 0.0, 0, Vector3(1, 0, 0)],
		["wings_freelook_back", "wings_glide", false, false, true, 16.0, -1.8, 0.0, 0.0, 0, Vector3.BACK],
		# Thruster boots skimming: still, at cruise each way, and dashing.
		["boots_hover", "boots_thruster", false, false, false, 0.0, 0.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["boots_forward", "boots_thruster", false, false, false, 15.0, 0.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["boots_forward_aim", "boots_thruster", false, false, false, 15.0, 0.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["boots_dash", "boots_thruster", false, false, false, 35.0, 0.0, 0.0, 0.0, 0, Vector3.FORWARD],
		["boots_strafe", "boots_thruster", false, false, false, 15.0, 0.0, 0.0, 0.0, 0, Vector3(1, 0, 0)],
		["boots_back", "boots_thruster", false, false, false, 15.0, 0.0, 0.0, 0.0, 0, Vector3.BACK],
	]
	for pose: Array in poses:
		var raid := Raid.new()
		add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", pose[1], "frame_trooper"])
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, -200, 0)
		var camera := Camera3D.new()
		camera.fov = 50.0
		raid.add_child(camera)
		camera.make_current()
		var p := raid.player
		await _settle(30)
		p.set_physics_process(false)
		p.global_position += Vector3(0, 6, 0)
		p.airborne_time = 1.0
		p.flight.is_hovering = pose[2]
		p.flight.is_boosting = pose[3]
		p.flight.is_thrusting = pose[2]
		p.flight.is_gliding = pose[4]
		p.flight.is_skimming = pose[1] == "boots_thruster"
		p.cmd.secondary = String(pose[0]).ends_with("_aim")
		p.cmd.free_look = String(pose[0]).contains("freelook")
		p.cmd.pitch = pose[8]
		var at := p.global_position
		var back := p.global_transform.basis.z
		var side := p.global_transform.basis.x
		var heading: Vector3 = p.global_transform.basis * (pose[10] as Vector3)
		var views := {
			"back": at + back * 3.4 + Vector3(0, 1.6, 0),
			"side": at + side * 3.4 + Vector3(0, 1.2, 0),
		}
		if pose[1] == "boots_thruster":
			views["front"] = at - back * 3.0 + side * 1.6 + Vector3(0, 1.4, 0)
		for view: String in views:
			camera.look_at_from_position(views[view], at + Vector3(0, 1.0, 0))
			# Fly the turn in place for a second so the bank settles.
			for i in 70:
				heading = heading.rotated(Vector3.UP, float(pose[7]) / 60.0)
				if absf(float(pose[7])) > 0.0 and i == 0:
					heading = p.global_transform.basis * (pose[10] as Vector3)
				p.velocity = heading * float(pose[5]) + Vector3(0, float(pose[6]), 0)
				# Physics is off, so the dash only runs out when cleared here.
				p.air_dash_left = p.flight.air_dash_time if int(pose[9]) != 0 and i >= 64 else 0.0
				p.air_dash_side = float(pose[9])
				await get_tree().process_frame
			await _shot(out_dir.path_join("flight_%s_%s.png" % [pose[0], view]))
		raid.queue_free()
		await _settle(3)


## A running jump from the side: the push off the ground, the lean into
## the leap, and the knees taking the landing.
func _takeoff_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "jetpack_mk2", "frame_trooper"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	var camera := Camera3D.new()
	camera.fov = 50.0
	raid.add_child(camera)
	camera.make_current()
	var p := raid.player
	await _settle(30)
	p.set_physics_process(false)
	var at := p.global_position
	camera.look_at_from_position(at + p.global_transform.basis.x * 3.4 + Vector3(0, 1.2, 0), at + Vector3(0, 1.0, 0))
	var forward := -p.global_transform.basis.z
	p.velocity = forward * 7.0
	await get_tree().create_timer(0.6).timeout
	p.airborne_time = 1.0
	p.velocity = forward * 7.0 + Vector3(0, 6, 0)
	await get_tree().create_timer(0.07).timeout
	await _shot(out_dir.path_join("flight_takeoff_push.png"))
	await get_tree().create_timer(0.4).timeout
	await _shot(out_dir.path_join("flight_takeoff_leap.png"))
	p.airborne_time = 0.0
	p.velocity = Vector3.ZERO
	p.landed.emit(7.0)
	await get_tree().create_timer(0.1).timeout
	await _shot(out_dir.path_join("flight_landing.png"))
	raid.queue_free()
	await _settle(3)


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


## The Concourse from the spots people stand: arriving, under the arcade, at
## the gates, up on a tower deck, and from high above. Prints the draw calls
## and objects of each view, the frame cost that grows with the map.
func _hub_shots(out_dir: String) -> void:
	var plaza := Worlds.social_world()
	var raid := Raid.new()
	add_child(raid)
	raid.start(plaza, 5)
	var map: Node3D = raid.map
	var camera := Camera3D.new()
	camera.far = 1500.0
	camera.fov = 75.0
	add_child(camera)
	camera.make_current()
	var arrival: Vector3 = map.get("ARRIVAL") if map.get("ARRIVAL") != null else Vector3.ZERO
	var views := [
		["arrival", arrival + Vector3(0, 1.7, 0), Vector3(0, 12, 0)],
		["plaza", Vector3(9, 1.7, 22), Vector3(-2, 2.5, -8)],
		["arrival_high", arrival + Vector3(0, 6, 9), Vector3(0, 6, -20)],
		["gates", Vector3(0, 2.5, -60), Vector3(0, 7, -100)],
		["market", Vector3(-14, 1.7, -46), Vector3(-40, 4, -42)],
		["deck", Vector3(26.5, 16.7, -64), Vector3(-30, 8, 40)],
		["screens", Vector3(0, 3, 62), Vector3(0, 7, 106)],
		["contracts", Vector3(30, 2.2, 86), Vector3(32, 3.2, 96)],
		["overview", Vector3(150, 120, 150), Vector3(0, 0, 0)],
	]
	for v: Array in views:
		camera.look_at_from_position(v[1], v[2])
		await _settle(20)
		await _shot(out_dir.path_join("hub_%s.png" % v[0]))
		print("  %s: %d draw calls, %d objects" % [v[0],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	camera.queue_free()
	raid.queue_free()
	await _settle(2)


## The home base with one of everything on show, from a few fixed angles.
func _base_shots(out_dir: String) -> void:
	var base := HomeBase.new()
	var gear := ["rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher", "blade_arc",
			"hammer_breaker", "knife_gutter", "axe_splitter", "spear_lancer", "pistol_machine", "pistol_hand_cannon",
			"optic_scope", "optic_reflex", "muzzle_suppressor", "grip_vertical", "frame_runner", "frame_trooper", "frame_bulwark", "jetpack_mk2", "boots_thruster",
			"wings_glide", "chip_blink", "chip_barrier", "chip_pulse", "bike_scrapper", "bike_raider", "medkit",
			"medkit", "scrap_metal", "scrap_metal", "scrap_metal", "alloy_ingot", "reactor_core", "lattice_shard"]
	var worn := {"primary": "dmr_longshot", "frame": "frame_bulwark", "vehicle": "bike_raider"}
	# The finished base first; the starter bunker is shot at the end.
	base.show_gear(gear, worn, BaseUpgrades.full())
	add_child(base)
	var camera := Camera3D.new()
	camera.fov = 75.0
	base.add_child(camera)
	camera.make_current()
	base.player.global_position = Vector3(3, 0.1, 2)
	await _settle(40)
	var views := {
		"base_overview.png": [Vector3(0, 3.2, 8.2), Vector3(0, 1.2, -4)],
		"base_armory.png": [Vector3(-6.5, 2.6, 1.0), Vector3(-17.0, 1.6, -0.5)],
		"base_weapons.png": [Vector3(-12.6, 2.0, 2.6), Vector3(-19, 1.9, -1.0)],
		"base_sidearms.png": [Vector3(-15.0, 1.9, 3.0), Vector3(-15.6, 1.8, -5)],
		"base_blades.png": [Vector3(-15.0, 1.9, -2.6), Vector3(-15.6, 1.4, 5)],
		"base_armor.png": [Vector3(-5.5, 2.0, -2.0), Vector3(-5.5, 1.1, -8.5)],
		"base_rigs.png": [Vector3(5.5, 2.0, -2.0), Vector3(5.5, 1.1, -8.5)],
		"base_garage.png": [Vector3(5.0, 2.6, 1.0), Vector3(16.0, 0.8, 0.0)],
		"base_range.png": [Vector3(0.0, 2.2, -14.0), Vector3(0.0, 1.4, -40.0)],
		"base_range_lane.png": [Vector3(-2.5, 1.8, -18.0), Vector3(1.0, 2.5, -45.0)],
		"base_shelves.png": [Vector3(-6.8, 2.0, 3.6), Vector3(-6.8, 1.6, 9)],
		"base_stations_left.png": [Vector3(-3.5, 2.2, 4.0), Vector3(-11.0, 1.0, 1.0)],
		"base_stations_right.png": [Vector3(4.0, 2.2, 1.0), Vector3(11.1, 1.0, 6.0)],
		"base_back_wall.png": [Vector3(0.0, 2.6, 4.0), Vector3(0.0, 1.5, -9.0)],
		"base_launch.png": [Vector3(4.0, 3.0, -1.0), Vector3(7.0, 1.0, 7.5)],
		"base_door.png": [Vector3(-1.5, 2.0, 3.0), Vector3(-2.0, 1.4, 9.0)],
		"base_range_board.png": [Vector3(0.0, 1.7, -10.6), Vector3(0.0, 4.0, -14.0)],
	}
	for file: String in views:
		camera.look_at_from_position(views[file][0], views[file][1])
		await _settle(4)
		await _shot(out_dir.path_join(file))
	# The suit-up bay, empty, then with the player suited up in it.
	var bay := HomeBase.SUIT_AT
	var facing := Basis.from_euler(Vector3(0, HomeBase.SUIT_YAW, 0))
	camera.look_at_from_position(bay + facing * Vector3(1.6, 2.0, 4.2), bay + Vector3(0, 1.1, 0))
	await _settle(4)
	await _shot(out_dir.path_join("base_suit_bay.png"))
	base.suit_up()
	# The arms move in real time: catch them at the body.
	await get_tree().create_timer(base.suit_time * 0.45).timeout
	await _shot(out_dir.path_join("base_suit_up.png"))
	await get_tree().create_timer(base.suit_time).timeout
	await _settle(4)
	await _shot(out_dir.path_join("base_suited.png"))
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
	# The starter bunker: what a new player sees, with every upgrade sealed.
	base.show_gear(gear, worn, [])
	base.set_scrip(1500)
	base.player.global_position = Vector3(3, 0.1, 5)
	await _settle(10)
	var bunker := {
		"bunker_overview.png": [Vector3(0, 3.2, 8.2), Vector3(0, 1.2, -4)],
		"bunker_nook.png": [Vector3(-5.5, 2.4, 2.5), Vector3(-15.0, 1.6, -0.5)],
		"bunker_garage.png": [Vector3(5.0, 2.6, 1.0), Vector3(16.0, 1.4, 0.0)],
		"bunker_range_door.png": [Vector3(0.0, 1.8, -4.5), Vector3(0.0, 1.7, -9.0)],
		"bunker_gear_post.png": [Vector3(-6.0, 1.6, -6.0), Vector3(-6.0, 1.4, -9.0)],
		"bunker_consoles.png": [Vector3(6.5, 2.0, 5.5), Vector3(11.1, 1.3, 7.0)],
		"bunker_bench.png": [Vector3(-8.2, 1.8, -0.2), Vector3(-9.2, 1.3, -2.8)],
	}
	for file: String in bunker:
		camera.make_current()
		camera.look_at_from_position(bunker[file][0], bunker[file][1])
		await _settle(4)
		await _shot(out_dir.path_join(file))
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
	# The floor's layout: from high over the stands, from the rim, from the
	# middle of the floor, and from a fighter's tunnel.
	var camera := Camera3D.new()
	camera.fov = 70.0
	arena.add_child(camera)
	camera.make_current()
	hud.visible = false
	overlay.visible = false
	for view: Array in [["arena_overview", Vector3(0, 48, 34), Vector3(0, 0, 0)],
			["arena_rim", Vector3(-22, 9, 22), Vector3(4, 2, -4)],
			["arena_floor", Vector3(0, 1.7, 17), Vector3(0, 3, 0)],
			["arena_tunnel", Vector3(-Arena.ArenaVenue.GATE_DISTANCE - 2.0, 1.7, 0), Vector3(0, 2, 0)],
			["arena_stands", Vector3(10, 6.5, 23), Vector3(-6, 2, -4)],
			["arena_board", Vector3(4, 1.7, 9), Vector3(0, 18, 0)]]:
		camera.look_at_from_position(view[1], view[2])
		await _settle(10)
		await _shot(out_dir.path_join("%s.png" % view[0]))
		print("%s: %d draw calls, %d objects" % [view[0],
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	camera.queue_free()


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


func _attachment_shots(out_dir: String) -> void:
	await _aim_shots(out_dir)
	if "--aim-only" in OS.get_cmdline_user_args():
		return
	var kits := {
		"rifle_scrap": ["optic_reflex", "muzzle_compensator", "grip_vertical", "mag_extended"],
		"rifle_carbine": ["optic_scope", "muzzle_suppressor", "grip_angled", "mag_drum"],
		"smg_stinger": ["optic_reflex", "muzzle_booster", "grip_vertical", "mag_quick"],
		"dmr_longshot": ["optic_longscope", "muzzle_suppressor", "grip_angled", "mag_extended"],
		"shotgun_breacher": ["optic_reflex", "muzzle_compensator", "grip_vertical", "mag_drum"],
	}
	var every: Array = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "attachment"):
			every.append(id)
	for primary: String in kits:
		var loadout := {"primary": primary}
		for id: String in kits[primary]:
			loadout[Loadout.attachment_slot(id)] = id
		var base := HomeBase.new()
		var stash: Array = every.duplicate()
		stash.append(primary)
		base.show_gear(stash, loadout, BaseUpgrades.full())
		add_child(base)
		var camera := Camera3D.new()
		camera.fov = 50.0
		base.add_child(camera)
		camera.make_current()
		base.player.global_position = Vector3(0, 0.1, 6)
		await _settle(20)
		# Views in the bench's own frame (+Z is where you stand to use it).
		var bench := Transform3D(Basis(Vector3.UP, HomeBase.BENCH_YAW), HomeBase.BENCH_AT)
		if primary == "rifle_scrap":
			camera.look_at_from_position(bench * Vector3(-0.6, 1.9, 3.2), bench * Vector3(0, 1.4, 0))
			await _settle(4)
			await _shot(out_dir.path_join("bench_overview.png"))
		camera.look_at_from_position(bench * Vector3(-0.25, 1.45, 1.0), bench * Vector3(0, 1.2, 0.0))
		await _settle(4)
		await _shot(out_dir.path_join("bench_%s.png" % primary))
		base.queue_free()
		await _settle(2)


## The fabricator beside the bench, and the craft screen on it.
func _crafting_shots(out_dir: String) -> void:
	for full: bool in [false, true]:
		var base := HomeBase.new()
		base.show_gear(["rifle_carbine", "optic_reflex", "jetpack_mk2", "mech_bulwark"], {"primary": "rifle_carbine"},
				BaseUpgrades.full() if full else [])
		add_child(base)
		var camera := Camera3D.new()
		camera.fov = 55.0
		base.add_child(camera)
		camera.make_current()
		base.player.global_position = Vector3(0, 0.1, 6)
		await _settle(20)
		var bench := base.bench_transform()
		camera.look_at_from_position(bench * Vector3(-0.3, 1.9, 1.7), bench * Vector3(2.0, 1.4, 0.8))
		await _settle(4)
		await _shot(out_dir.path_join("fabricator_%s.png" % ("armory" if full else "bunker")))
		camera.look_at_from_position(Vector3(-13.2, 2.2, 1.0), Vector3(-14.4, 1.3, 7.8))
		await _settle(4)
		await _shot(out_dir.path_join("fabricator_%s_front.png" % ("armory" if full else "bunker")))
		base.queue_free()
		await _settle(2)
	# The screen in use, as the player sees it, with one recipe ready.
	Profile.persist = false
	Profile.reset()
	Profile.welcome_granted = true
	Profile.scrip = 1000
	Profile.add_to_stash(["bp_jetpack", "bp_dmr_longshot", "upgrade_data", "upgrade_data", "upgrade_data",
			"power_cell", "power_cell", "alloy_ingot", "circuit_board"])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _settle(30)
	main.open_station(HomeBase.CRAFT_ID)
	await _settle(60)
	await _shot(out_dir.path_join("fabricator_screen.png"))
	main.queue_free()
	await _settle(2)


## The gunsmith's workshop off the armory, and the bench in use.
func _bench_shots(out_dir: String) -> void:
	var every: Array = ["rifle_carbine", "smg_stinger", "dmr_longshot"]
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "attachment"):
			every.append(id)
	var loadout := {"primary": "rifle_carbine", "optic": "optic_reflex", "grip": "grip_vertical"}
	for full: bool in [true, false]:
		var base := HomeBase.new()
		base.show_gear(every, loadout, BaseUpgrades.full() if full else [])
		add_child(base)
		var camera := Camera3D.new()
		camera.fov = 60.0
		base.add_child(camera)
		camera.make_current()
		base.player.global_position = Vector3(0, 0.1, 6)
		await _settle(20)
		var tag := "armory" if full else "bunker"
		# From the room, through the way into the armory.
		camera.look_at_from_position(Vector3(-6.0, 2.4, 0.0), Vector3(-16.0, 1.4, 2.5))
		await _settle(4)
		await _shot(out_dir.path_join("bench_%s_way_in.png" % tag))
		# Inside the armory, looking across to the workshop.
		camera.look_at_from_position(Vector3(-12.8 if not full else -17.0, 2.2, -3.5 if not full else -2.0), Vector3(-14.0, 1.3, 7.5))
		await _settle(4)
		await _shot(out_dir.path_join("bench_%s_workshop.png" % tag))
		if full:
			var view: Node3D = load("res://core/ui/bench_view.gd").new()
			view.base = base
			var at := base.bench_transform()
			camera.global_transform = Transform3D(Basis.looking_at(at * view.look_at_point - at * view.eye, Vector3.UP), at * view.eye)
			camera.fov = view.fov
			view.free()
			await _settle(4)
			await _shot(out_dir.path_join("bench_rest.png"))
			base.use_bench()
			base.bench_scroll(1)
			await _settle(6)
			await _shot(out_dir.path_join("bench_pick_gun.png"))
			base.bench_select()
			base.show_gear(every, {"primary": "smg_stinger", "optic": "optic_reflex", "grip": "grip_vertical"})
			base.bench_scroll(1)
			base.bench_select()
			base.bench_scroll(1)
			base.bench_scroll(1)
			await _settle(6)
			await _shot(out_dir.path_join("bench_pick_muzzle.png"))
		base.queue_free()
		await _settle(2)


## Aiming down each optic in first person, in a raid, and with iron sights.
func _aim_shots(out_dir: String) -> void:
	for kit: Array in [["rifle_carbine", "optic_scope", "muzzle_suppressor"], ["smg_stinger", "optic_reflex"],
			["dmr_longshot", "optic_longscope"], ["rifle_carbine"]]:
		var raid := Raid.new()
		add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, kit)
		for bot in raid.bots:
			bot.queue_free()
		var controller := PlayerController.new()
		controller.setup(raid.player)
		raid.add_child(controller)
		controller.set_physics_process(false)
		raid.player.cmd.yaw = controller.yaw
		await _settle(20)
		var name: String = kit[1] if kit.size() > 1 else "iron_sights"
		for aiming: bool in [false, true]:
			raid.player.cmd.secondary = aiming
			await _settle(40)
			await _shot(out_dir.path_join("aim_%s_%s.png" % [name, "on" if aiming else "off"]))
		raid.queue_free()
		await _settle(2)


func _artifact_shots(out_dir: String) -> void:
	for relic: String in ["artifact_cloak", "artifact_rewind", "artifact_bloom"]:
		var raid := Raid.new()
		add_child(raid)
		var kit: Array[String] = ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", relic]
		raid.start(Worlds.get_world("ashfront"), 42, kit)
		for bot in raid.bots:
			bot.get_node("Brain").set_physics_process(false)
			bot.global_position += Vector3(0, 0, 400)
		var p := raid.player
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		var hud := Hud.new()
		hud.setup(raid, controller)
		raid.add_child(hud)
		await _settle(60)
		var tag := relic.trim_prefix("artifact_")
		if relic == "artifact_cloak":
			controller.wrist_raised = true
			controller.watch_focus = Hud.Wrist.SLOTS.find("artifact")
			controller.watch_focus_moved = true
			await _settle(30)
			await _shot(out_dir.path_join("artifact_watch.png"))
			controller.wrist_raised = false
			await _settle(20)
			await _shot(out_dir.path_join("cloak_first_off.png"))
			# Long enough to outlast a slow software render.
			p.artifact.duration = 600.0
			p.artifact.activate()
			await _settle(30)
			await _shot(out_dir.path_join("cloak_first_on.png"))
			controller.toggle_view()
			await _settle(30)
			await _shot(out_dir.path_join("cloak_third_on.png"))
			p.artifact.on_attack()
			await _settle(30)
			await _shot(out_dir.path_join("cloak_third_off.png"))
		elif relic == "artifact_rewind":
			controller.toggle_view()
			await _settle(30)
			var start := p.global_position
			for i in 40:
				p.global_position = start + Vector3(0.15 * i, 0, 0.1 * i)
				await get_tree().physics_frame
			p.artifact.activate()
			await _settle(6)
			await _shot(out_dir.path_join("rewind_trail.png"))
		else:
			controller.toggle_view()
			await _settle(30)
			p.artifact.activate()
			await _settle(2)
			await _shot(out_dir.path_join("bloom_ring.png"))
		raid.queue_free()
		await _settle(3)


func _settle(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Each helmet's visor through its wearer's eyes: the Scav Visor, the
## Spotter resting and zoomed, the Seeker ready and just after a scan, the
## Warden with Threat Sense running, and the Ember in thermal.
func _visor_shots(out_dir: String) -> void:
	var scrap: Array[String] = ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"]
	for helmet: String in ["visor_scav", "helm_spotter", "helm_seeker", "helm_warden", "helm_ember"]:
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
		# A squadmate off to the left, a ping ahead, a contract held and a hot war,
		# so the heading strip has what it marks.
		var mate: Actor = raid.bots[3]
		mate.global_position = p.global_position + look * Vector3(-30, 0.3, -40)
		mate.display_name = "Rook"
		var mate_state := Raid.PlayerState.new()
		mate_state.actor = mate
		raid.players.append(mate_state)
		p.clan = "squad"
		mate.clan = "squad"
		raid.pinged.emit(p, p.global_position + look * Vector3(12, 0, -60))
		raid.war.intensity = 0.7
		raid.war.centre = p.global_position + look * Vector3(150, 0, -120)
		hud.contracts.assign([{"id": "cull", "title": "Kill 8 enemies", "stat": "kills", "goal": 8, "have": 3}])
		p.tally["kills"] = 2
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
		elif helmet == "helm_warden":
			var near: Actor = raid.bots[0]
			var to_near: Vector3 = near.global_position + Vector3(0, 1.1, 0) - p.get_eye_position()
			controller.yaw = atan2(-to_near.x, -to_near.z)
			controller.pitch = asin(to_near.normalized().y)
			var cache := LootContainer.new()
			cache.setup(["reactor_core", "scrap_metal", "medkit"], false, "Cache")
			raid.add_child(cache)
			cache.global_position = p.global_position + Basis(Vector3.UP, controller.yaw) * Vector3(-1.6, 0, -3.2)
			for aimer: Actor in [raid.bots[1], raid.bots[2]]:
				aimer.cmd.aim_dir = (p.global_position + Vector3(0, 0.9, 0) - aimer.get_eye_position()).normalized()
			p.visor.sense_threats()
			await _settle(12)
			p.visor.threatened.emit(p.global_position + look * Vector3(-20, 0, 6))
			await _settle(2)
			await _shot(out_dir.path_join("visor_helm_warden_sense.png"))
		elif helmet == "helm_ember":
			raid.bots[1].flight.enabled = true
			raid.bots[1].flight.heat = raid.bots[1].flight.max_heat
			controller._visor_level = 1
			await _settle(20)
			await _shot(out_dir.path_join("visor_helm_ember_thermal.png"))
		elif helmet == "helm_seeker":
			p.visor.scan()
			await _settle(12)
			await _shot(out_dir.path_join("visor_helm_seeker_scan.png"))
			p.visor.felt_scan.emit(p.global_position + look * Vector3(20, 0, 5))
			await _settle(30)
			await _shot(out_dir.path_join("visor_helm_seeker_after.png"))
		raid.queue_free()
		await _settle(3)


## Every helmet worn, and a bare head, from the front, the side and behind,
## one row each, in one sheet. The same model first person leaves out.
func _helmet_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -200, 0)
	var player := raid.player
	player.set_physics_process(false)
	player.cmd.yaw = player.rotation.y
	player.cmd.pitch = 0.0
	player.cmd.aim_dir = -player.global_basis.z
	await _settle(10)
	var skin: Node = player.get_node("Skin")
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	# A lamp beside the camera, so the face is not lost against the sky.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 6.0
	lamp.light_energy = 1.5
	cam.add_child(lamp)
	lamp.position = Vector3(0.6, 0.4, 0)
	# Each row: a helmet and an armor frame worn together.
	var helmets := ["", "visor_scav", "helm_spotter", "helm_seeker", "helm_warden", "helm_ember"]
	var frames := ["", "plate_light", "frame_runner", "frame_trooper", "frame_bulwark", "frame_trooper"]
	var sheet := Image.create(3 * 320, helmets.size() * 320, false, Image.FORMAT_RGBA8)
	for row in helmets.size():
		Loadout.wear_helmet(player, helmets[row])
		Loadout.wear_frame(player, frames[row])
		for k in 10:
			skin._process(1.0 / 60.0)
			await get_tree().process_frame
		var views := [-player.global_basis.z, player.global_basis.x, player.global_basis.z]
		for i in views.size():
			var head := player.global_position + Vector3(0, 1.45, 0)
			cam.global_position = head + (views[i] as Vector3) * 3.0 + Vector3(0, 0.15, 0)
			cam.look_at(head)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h / 4, h / 4, h / 2, h / 2))
			cut.resize(320, 320)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 320, 320), Vector2i(i * 320, row * 320))
	sheet.save_png(out_dir.path_join("helmets.png"))
	print("saved helmets.png")
	raid.queue_free()


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


func _zone_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var camera := Camera3D.new()
	camera.far = 900.0
	raid.add_child(camera)
	camera.make_current()
	var gate: Node3D = raid.outposts[0]
	var inward := -Vector3(gate.global_position.x, 0, gate.global_position.z).normalized()
	camera.global_position = gate.global_position + inward * 32.0 + Vector3(0, 9, 0)
	camera.look_at(gate.global_position + Vector3(0, 2, 0))
	await _settle(30)
	await _shot(out_dir.path_join("zone_outpost.png"))
	var ground: float = raid.map.call("ground_height", 0.0, 72.0)
	camera.global_position = Vector3(0, ground + 14.0, 78.0)
	camera.look_at(Vector3(0, ground, 0))
	await _settle(30)
	await _shot(out_dir.path_join("zone_core.png"))
	raid.queue_free()


## One row per melee weapon: held at rest, cocked for an overhead swing, and
## guarding, from the side. A tag after the flag shoots only that kind, close up.
func _melee_shots(out_dir: String, only := "") -> void:
	var ids: Array[String] = []
	var near := 0.45 if only != "" else 1.0
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "melee") and (only == "" or ItemDB.has_tag(id, only)):
			ids.append(id)
	var poses := ["rest", "windup", "guard"]
	var sheet := Image.create(poses.size() * 360, ids.size() * 360, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var raid := Raid.new()
		add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_scrap", ids[row], "jetpack_mk1", "plate_light"])
		for bot in raid.bots:
			bot.queue_free()
		var player := raid.player
		await _settle(10)
		player.cmd.switch_weapon = 1
		await _settle(5)
		player.cmd.switch_weapon = -1
		var blade := player.get_active_weapon() as MeleeWeapon
		blade.light_windup = 5.0
		var cam := Camera3D.new()
		raid.add_child(cam)
		cam.current = true
		cam.fov = 40.0
		for col in poses.size():
			player.cmd.primary_pressed = poses[col] == "windup"
			player.cmd.secondary = poses[col] == "guard"
			await _settle(2)
			player.cmd.primary_pressed = false
			await _settle(30)
			var at := player.global_position
			cam.global_position = at + (player.global_basis.x * 3.6 - player.global_basis.z * 1.2) * near + Vector3(0, 1.2, 0)
			cam.look_at(at + Vector3(0, 1.1 + (1.0 - near) * 0.3, 0))
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h / 2, 0, h, h))
			cut.resize(360, 360)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 360, 360), Vector2i(col * 360, row * 360))
		player.cmd.secondary = false
		print("shot %s" % ids[row])
		raid.queue_free()
		await _settle(2)
	sheet.save_png(out_dir.path_join("melee.png"))
	print("saved melee.png")


## Film strips of melee moves: one row per move, a frame every
## `SWING_STEP` frames from the press, seen from a front three-quarter view.
## Run with `--fixed-fps 60` so each frame is one tick.
const SWING_STEP := 3
const SWING_FRAMES := 12
func _swing_strips(out_dir: String) -> void:
	var moves := [
		["blade_scrap", "light_right"], ["blade_scrap", "light_overhead"], ["blade_scrap", "heavy"],
		["knife_gutter", "light_left"], ["knife_gutter", "heavy"], ["axe_splitter", "light_right"],
		["axe_splitter", "light_overhead"], ["hammer_breaker", "light_right"], ["hammer_breaker", "heavy"],
		["spear_lancer", "light_overhead"], ["spear_lancer", "heavy"], ["blade_scrap", "back"],
		["blade_scrap", "deflect"],
	]
	var cell := 240
	var sheet := Image.create(SWING_FRAMES * cell, moves.size() * cell, false, Image.FORMAT_RGBA8)
	for row in moves.size():
		var id: String = moves[row][0]
		var move: String = moves[row][1]
		var raid := Raid.new()
		add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_scrap", id, "jetpack_mk1", "plate_light"])
		for bot in raid.bots:
			bot.queue_free()
		var player := raid.player
		await _settle(10)
		player.cmd.switch_weapon = 1
		await _settle(5)
		player.cmd.switch_weapon = -1
		await _settle(40)
		var blade := player.get_active_weapon() as MeleeWeapon
		blade.light_stamina = 0.0
		blade.heavy_stamina = 0.0
		var cam := Camera3D.new()
		raid.add_child(cam)
		cam.current = true
		cam.fov = 40.0
		var at := player.global_position
		cam.global_position = at + player.global_basis.x * 1.6 - player.global_basis.z * 2.0 + Vector3(0, 1.5, 0)
		cam.look_at(at + Vector3(0, 1.25, 0))
		var stances := {"light_right": MeleeWeapon.Dir.RIGHT, "light_left": MeleeWeapon.Dir.LEFT}
		player.cmd.stance = stances.get(move, MeleeWeapon.Dir.OVERHEAD)
		await _settle(2)
		match move:
			"heavy":
				player.cmd.tertiary_pressed = true
			"back":
				blade._light_attack(0.0)
				blade._back_strike = true
			"deflect":
				player.cmd.secondary = true
			_:
				player.cmd.primary_pressed = true
		for col in SWING_FRAMES:
			if move == "combo" and col in [4, 8]:
				player.cmd.primary_pressed = true
				player.cmd.stance = MeleeWeapon.Dir.LEFT if col == 4 else MeleeWeapon.Dir.RIGHT
			if move == "deflect" and col == 2:
				var shot := DamageInfo.make(10.0, player, "bullet", at)
				player.get_active_weapon().modify_incoming(shot)
			# A press is read in the tick after it is set.
			await get_tree().physics_frame
			await get_tree().physics_frame
			player.cmd.primary_pressed = false
			player.cmd.tertiary_pressed = false
			for k in SWING_STEP - 2:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var h := frame.get_height()
			var w := frame.get_width()
			var cut := frame.get_region(Rect2i(w / 2 - h / 2, 0, h, h))
			cut.resize(cell, cell)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, cell, cell), Vector2i(col * cell, row * cell))
		player.cmd.secondary = false
		print("filmed %s %s" % [id, move])
		raid.queue_free()
		await _settle(2)
	sheet.save_png(out_dir.path_join("swings.png"))
	print("saved swings.png")


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
		if player.weapons[i] is Gun and not player.weapons[i].is_sidearm:
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


## A contact sheet of each sidearm's model, side on and from three quarters.
func _sidearm_shots(out_dir: String) -> void:
	var stage := Node3D.new()
	add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.16)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	stage.add_child(sun)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var ids := ["pistol_service", "pistol_machine", "pistol_hand_cannon"]
	var sheet := Image.create(2 * 480, ids.size() * 320, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var gun := Gun.new()
		gun.item_id = ids[row]
		gun.is_sidearm = true
		var model: Node3D = Look.weapon_model(gun)
		gun.free()
		if model == null:
			continue
		stage.add_child(model)
		var box: AABB = Look.model_bounds(model)
		var centre := box.get_center()
		for c in 2:
			var side := Vector3(1, 0.15, 0) if c == 0 else Vector3(1, 0.4, -0.9)
			cam.global_position = centre + side.normalized() * 1.1
			cam.look_at(centre)
			await _settle(2)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 240 * h / 720, h / 2 - 160 * h / 720, 480 * h / 720, 320 * h / 720))
			cut.resize(480, 320)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 480, 320), Vector2i(c * 480, row * 320))
		model.queue_free()
	sheet.save_png(out_dir.path_join("sidearms.png"))
	print("saved sidearms.png")
	stage.queue_free()


## The four power weapons side on (power_weapons.png), then one in use in a
## raid: a Rail Lance beam, a plasma burst and an arc burst (power_fire.png).
## The weapon hand close up on each weapon, from the side and from ahead,
## at the hip and aiming (a blade: at rest, both shots the same), one row a
## weapon. Every model is held by its own grip (`Look._measure_hold`,
## `Look._fit_hands`), so the hands sit differently on each.
func _hands_shots(out_dir: String) -> void:
	var ids := ["rifle_scrap", "rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher",
			"pistol_service", "pistol_machine", "pistol_hand_cannon", "power_rail_lance", "power_storm_cannon",
			"blade_scrap", "blade_arc", "knife_gutter", "axe_splitter", "hammer_breaker", "spear_lancer"]
	if OS.has_environment("HANDS_IDS"):
		ids = Array(OS.get_environment("HANDS_IDS").split(","))
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["blade_scrap", "plate_light"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	await _settle(30)
	var p := raid.player
	p.set_physics_process(false)
	p.cmd.pitch = 0.0
	var cam := Camera3D.new()
	cam.fov = 30.0
	raid.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("hands"))
	var cell := Vector2i(360, 300)
	var sheet := Image.create(4 * cell.x, ids.size() * cell.y, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var id: String = ids[row]
		if ItemDB.has_tag(id, "power"):
			Loadout.equip(p, ["blade_scrap", "plate_light"])
			Loadout.set_power(p, id)
		else:
			Loadout.equip(p, [id, "plate_light"])
		var weapon: Weapon = null
		for i in p.weapons.size():
			if p.weapons[i].item_id == id:
				weapon = p.weapons[i]
				p.active_weapon_index = i
		await _settle(70)
		var gun := weapon as Gun
		for col in 4:
			var aiming := col >= 2 and gun != null
			p.cmd.secondary = aiming
			if gun != null:
				gun._aiming = aiming
			await _settle(40 if col % 2 == 0 else 3)
			var hand: Vector3 = (p.hand.get_meta("shown") as Transform3D).origin if p.hand.has_meta("shown") else p.hand.global_position
			var right := p.global_basis.x.normalized()
			var ahead := -p.global_basis.z.normalized()
			var side := right * 0.75 + Vector3.UP * 0.12 if col % 2 == 0 else ahead * 0.65 + right * 0.4 + Vector3.UP * 0.1
			var focus := hand + ahead * (0.12 if gun != null and not gun.is_sidearm else 0.04)
			cam.global_position = focus + side * (1.6 if weapon is MeleeWeapon and Look.is_two_handed(weapon) else 1.0)
			cam.look_at(focus)
			await _settle(2)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			frame.save_png(out_dir.path_join("hands/%s_%d.png" % [id, col]))
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - cell.x * h / 720, h / 2 - cell.y * h / 720, 2 * cell.x * h / 720, 2 * cell.y * h / 720))
			cut.resize(cell.x, cell.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, cell), Vector2i(col * cell.x, row * cell.y))
		p.cmd.secondary = false
		if gun != null:
			gun._aiming = false
	sheet.save_png(out_dir.path_join("hands.png"))
	print("saved hands.png")
	raid.queue_free()


func _power_shots(out_dir: String) -> void:
	var stage := Node3D.new()
	add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.16)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	stage.add_child(sun)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var ids := ["power_rail_lance", "power_helion", "power_arc_mortar", "power_storm_cannon"]
	var sheet := Image.create(2 * 480, ids.size() * 320, false, Image.FORMAT_RGBA8)
	for row in ids.size():
		var gun := Gun.new()
		Loadout._setup_weapon(gun, ids[row], ItemDB.item_stats(ids[row]))
		var model: Node3D = Look.weapon_model(gun)
		gun.free()
		if model == null:
			continue
		stage.add_child(model)
		var box: AABB = Look.model_bounds(model)
		var centre := box.get_center()
		for c in 2:
			var side := Vector3(1, 0.15, 0) if c == 0 else Vector3(1, 0.4, -0.9)
			cam.global_position = centre + side.normalized() * 2.9
			cam.look_at(centre)
			await _settle(2)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 240 * h / 720, h / 2 - 160 * h / 720, 480 * h / 720, 320 * h / 720))
			cut.resize(480, 320)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 480, 320), Vector2i(c * 480, row * 320))
		model.queue_free()
	sheet.save_png(out_dir.path_join("power_weapons.png"))
	print("saved power_weapons.png")
	stage.queue_free()

	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.queue_free()
	var player := raid.player
	await _settle(30)
	player.velocity = Vector3.ZERO
	var rack := raid.spawn_container(["power_rail_lance"], false, LootContainer.RACK_LABEL,
			player.global_position + Vector3(2.0, 0, -2.0))
	rack.interact(player)
	await _settle(10)
	var lance := player.get_active_weapon() as Gun
	var shot_cam := Camera3D.new()
	raid.add_child(shot_cam)
	shot_cam.current = true
	shot_cam.fov = 60.0
	shot_cam.global_position = player.global_position + Vector3(3.2, 2.4, 3.5)
	shot_cam.look_at(player.global_position + Vector3(0, 1.2, -8))
	player.cmd.aim_dir = Vector3(0, 0.02, -1).normalized()
	player.cmd.yaw = 0.0
	player.cmd.primary = true
	for i in 70:
		await get_tree().physics_frame
		if lance.ammo_in_mag < lance.mag_size:
			break
	player.cmd.primary = false
	var ahead := player.global_position + Vector3(0, 0, -14)
	Fx.burst(raid, player.global_position + Vector3(-4, 1.5, -7), 3.0, Color(1.0, 0.45, 0.15))
	Fx.burst(raid, player.global_position + Vector3(5, 1.5, -6), 3.0, Color(0.7, 0.45, 1.0))
	rack.set_items(["power_storm_cannon"])
	await _settle(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("power_fire.png"))
	print("saved power_fire.png")
	raid.queue_free()


## A contact sheet of where holstered weapons are worn: one row each for the
## blade in hand (gun slung on the back) and the gun in hand (blade on the hip),
## with the jetpack on and off, seen from four sides; then everything
## holstered on each flight rig in turn (holster_rigs.png).
func _holster_shots(out_dir: String, melee_id := "") -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.queue_free()
	var player := raid.player
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	if ItemDB.has_tag(melee_id, "melee"):
		for w in player.weapons.duplicate():
			if w is MeleeWeapon:
				player.weapons.erase(w)
				if w.visual:
					w.visual.queue_free()
				w.queue_free()
		var swap := MeleeWeapon.new()
		Loadout._setup_weapon(swap, melee_id, ItemDB.item_stats(melee_id))
		player.equip_weapon(swap)
	await _settle(10)
	var skin: Node = player.get_node("Skin")
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var gun := -1
	var blade := -1
	var sidearm := -1
	for i in player.weapons.size():
		if skin.is_sidearm(player.weapons[i]):
			sidearm = i
		elif player.weapons[i] is Gun:
			gun = i
		elif player.weapons[i] is MeleeWeapon:
			blade = i
	var rig_on := player.flight.enabled
	var rows := [[blade, rig_on], [gun, rig_on], [blade, false], [gun, false], [-1, rig_on]]
	var sheet := Image.create(4 * 320, rows.size() * 360, false, Image.FORMAT_RGBA8)
	for row in rows.size():
		player.active_weapon_index = rows[row][0]
		player._refresh_weapon_visuals()
		player.flight.enabled = rows[row][1]
		for k in 60:
			skin._process(1.0 / 60.0)
			await get_tree().process_frame
		var sides: Array[Vector3] = [player.global_basis.z, player.global_basis.x, -player.global_basis.x,
				(player.global_basis.z - player.global_basis.x).normalized()]
		for c in sides.size():
			var at := player.global_position + Vector3(0, 1.0, 0)
			cam.global_position = at + sides[c] * 4.0
			cam.look_at(at)
			await _settle(1)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
			cut.resize(320, 360)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(c * 320, row * 360))
	sheet.save_png(out_dir.path_join("holster.png"))
	print("saved holster.png")
	# Everything holstered on every rig: clamped to a jetpack's side rails,
	# slung over wings, across the back with boots or nothing on.
	var rig_was := player.flight.item_id
	var rigs: Array[String] = ["jetpack_mk1", "jetpack_mk2", "wings_glide", "boots_thruster", ""]
	var rig_sheet := Image.create(4 * 320, rigs.size() * 360, false, Image.FORMAT_RGBA8)
	player.active_weapon_index = -1
	player._refresh_weapon_visuals()
	for row in rigs.size():
		player.flight.item_id = rigs[row]
		player.flight.enabled = rigs[row] != ""
		for k in 60:
			skin._process(1.0 / 60.0)
			await get_tree().process_frame
		var sides: Array[Vector3] = [player.global_basis.z, player.global_basis.x, -player.global_basis.x,
				(player.global_basis.z - player.global_basis.x).normalized()]
		for c in sides.size():
			var at := player.global_position + Vector3(0, 1.1, 0)
			cam.global_position = at + sides[c] * 3.0
			cam.look_at(at)
			await _settle(1)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
			cut.resize(320, 360)
			cut.convert(Image.FORMAT_RGBA8)
			rig_sheet.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(c * 320, row * 360))
	rig_sheet.save_png(out_dir.path_join("holster_rigs.png"))
	print("saved holster_rigs.png")
	player.flight.item_id = rig_was
	# A switch, frame by frame from behind and to the right: gun to blade,
	# blade to sidearm (if carried), then holstered.
	var steps := [blade, sidearm if sidearm >= 0 else gun, -1]
	player.active_weapon_index = gun
	player.flight.enabled = rig_on
	for k in 60:
		skin._process(1.0 / 60.0)
		await get_tree().process_frame
	# Driven by hand at a steady 60 fps: a slow render would otherwise skip
	# the whole switch between two frames.
	skin.set_process(false)
	var strip := Image.create(10 * 320, steps.size() * 360, false, Image.FORMAT_RGBA8)
	for row in steps.size():
		player.active_weapon_index = steps[row]
		player._refresh_weapon_visuals()
		for c in 10:
			for k in 4:
				skin._process(1.0 / 60.0)
				await get_tree().process_frame
			var at := player.global_position + Vector3(0, 1.1, 0)
			cam.global_position = at + (player.global_basis.z * 0.8 + player.global_basis.x).normalized() * 3.2
			cam.look_at(at)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
			cut.resize(320, 360)
			cut.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(c * 320, row * 360))
	skin.set_process(true)
	strip.save_png(out_dir.path_join("holster_switch.png"))
	print("saved holster_switch.png")
	player.flight.enabled = rig_on
	raid.queue_free()


## The rider on a bike: rows of hands-free with weapons slung, a gun drawn, a
## blade drawn, and leaning into a right turn; each from the side, the front
## quarter, behind and above-behind. Then the riding view in first person.
func _ride_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.queue_free()
	raid.bots.clear()
	var player := raid.player
	await _settle(10)
	# A flat deck well above the map, so nothing stands in the shots.
	var at := player.global_position + Vector3(0, 40, 0)
	var deck := StaticBody3D.new()
	var deck_shape := CollisionShape3D.new()
	deck_shape.shape = BoxShape3D.new()
	deck_shape.shape.size = Vector3(40, 1, 40)
	deck.add_child(deck_shape)
	var deck_mesh := MeshInstance3D.new()
	deck_mesh.mesh = BoxMesh.new()
	deck_mesh.mesh.size = Vector3(40, 1, 40)
	deck.add_child(deck_mesh)
	raid.add_child(deck)
	deck.global_position = at - Vector3(0, 0.5, 0)
	var ride_id := OS.get_environment("RIDE_VEHICLE")
	if ride_id == "" or not ItemDB.has_tag(ride_id, "vehicle"):
		ride_id = "bike_raider"
	var bike: Node3D = raid.spawn_vehicle(ride_id, at + Vector3(0, 0.3, 0), 0.6)
	# Bigger vehicles are framed from further out and higher up.
	var seat_y: float = bike.seat_point.y
	var frame_out := maxf(1.0, seat_y / 0.98)
	if bike.model != "bike":
		frame_out = maxf(frame_out, bike.body_size.z / 2.6)
	await _settle(20)
	bike.mount(player)
	player.set_physics_process(false)
	player.rotation.y = 0.6
	var skin: Node = player.get_node("Skin")
	var gun := -1
	var blade := -1
	for i in player.weapons.size():
		if player.weapons[i] is MeleeWeapon:
			blade = i
		elif player.weapons[i] is Gun and gun < 0:
			gun = i
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	# [weapon, lean]
	var rows := [[-1, 0.0], [gun, 0.0], [blade, 0.0], [-1, 0.3]]
	var sheet := Image.create(4 * 320, rows.size() * 360, false, Image.FORMAT_RGBA8)
	for row in rows.size():
		player.active_weapon_index = rows[row][0]
		player._refresh_weapon_visuals()
		bike.set_physics_process(rows[row][1] == 0.0)
		bike.lean = rows[row][1]
		bike.get_node("Model").rotation = Vector3(0.0, 0.0, -bike.lean)
		await _settle(60)
		var b: Basis = bike.global_basis
		var sides: Array[Vector3] = [b.x, (b.x - b.z).normalized(), b.z, (b.z * 0.8 + Vector3.UP * 0.7).normalized()]
		for c in sides.size():
			var look_at := bike.global_position + Vector3(0, seat_y - 0.13, 0)
			cam.global_position = look_at + (sides[c] + Vector3.UP * 0.15).normalized() * 6.5 * frame_out
			cam.look_at(look_at)
			await _settle(1)
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			var w := frame.get_width()
			var h := frame.get_height()
			var cut := frame.get_region(Rect2i(w / 2 - 160 * h / 720, h / 2 - 180 * h / 720, 320 * h / 720, 360 * h / 720))
			cut.resize(320, 360)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(0, 0, 320, 360), Vector2i(c * 320, row * 360))
	sheet.save_png(out_dir.path_join("ride.png"))
	print("saved ride.png")
	# Close in on the hands and feet, hands free, from the left and above-front.
	player.active_weapon_index = -1
	player._refresh_weapon_visuals()
	bike.set_physics_process(true)
	await _settle(40)
	var close := [[(-bike.global_basis.x * 2.4 + Vector3(0, 0.2, 0)) * frame_out, "ride_close_side.png"],
		[(-bike.global_basis.z * 1.6 + bike.global_basis.x * 0.9 + Vector3(0, 1.0, 0)) * frame_out, "ride_close_front.png"]]
	for shot in close:
		var focus: Vector3 = bike.global_position + bike.global_basis * (bike.seat_point + Vector3(0, 0.02, -0.38))
		cam.global_position = focus + shot[0]
		cam.look_at(focus)
		await _settle(2)
		await _shot(out_dir.path_join(shot[1]))
	cam.queue_free()
	bike.set_physics_process(true)
	player.set_physics_process(true)
	player.active_weapon_index = -1
	var controller := PlayerController.new()
	controller.setup(player)
	raid.add_child(controller)
	controller.ride_view = PlayerController.ViewMode.THIRD
	await _settle(40)
	await _shot(out_dir.path_join("ride_third.png"))
	controller.ride_view = PlayerController.ViewMode.FIRST
	await _settle(40)
	await _shot(out_dir.path_join("ride_first.png"))
	raid.queue_free()



## One action per row, held still: as you see it in first person, in the
## third-person camera, and from the front. Both views read the actor's one
## `ActionPose`, so each row should read the same way across.
func _view_shots(out_dir: String, only := "") -> void:
	var raid := Raid.new()
	add_child(raid)
	# `VIEW_GUN` and `VIEW_SIDEARM` pick the guns (each model is held by
	# its own grip, so compare them).
	var kit := [OS.get_environment("VIEW_GUN") if OS.has_environment("VIEW_GUN") else "rifle_carbine",
			OS.get_environment("VIEW_MELEE") if OS.has_environment("VIEW_MELEE") else "blade_scrap",
			OS.get_environment("VIEW_SIDEARM") if OS.has_environment("VIEW_SIDEARM") else "pistol_service", "jetpack_mk1", "plate_light"]
	# `VIEW_OPTIC=<item id>` fits an optic to the rifle, for the aim rows.
	if OS.has_environment("VIEW_OPTIC"):
		kit.append(OS.get_environment("VIEW_OPTIC"))
	raid.start(Worlds.get_world("ashfront"), 42, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -500, 0)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await _settle(30)
	p.set_physics_process(false)
	controller.set_physics_process(false)
	controller.pitch = -0.05
	p.cmd.pitch = controller.pitch
	p.cmd.yaw = controller.yaw
	var skin: Node = p.get_node("Skin")
	var pose := ActionPose.of(p)
	var gun_at := -1
	var blade_at := -1
	var pistol_at := -1
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			blade_at = i
		elif p.weapons[i] is Gun and p.weapons[i].is_sidearm:
			pistol_at = i
		elif p.weapons[i] is Gun and gun_at < 0:
			gun_at = i
	var gun := p.weapons[gun_at] as Gun
	var blade := p.weapons[blade_at] as MeleeWeapon
	var outside := Camera3D.new()
	outside.fov = 40.0
	raid.add_child(outside)
	var rows := ["gun_ready", "ads", "pistol_ads", "gun_low", "pistol_low", "blade_idle", "reload", "switch", "windup_left", "windup_right", "windup_overhead",
			"swing", "guard", "watch"]
	if only != "":
		rows = rows.filter(func(r: String) -> bool: return r in only.split(","))
	var size := Vector2i(400, 300)
	var sheet := Image.create(3 * size.x, rows.size() * size.y, false, Image.FORMAT_RGBA8)
	for row in rows.size():
		var kind: String = rows[row]
		var melee := kind.begins_with("windup") or kind == "swing" or kind == "guard" or kind == "blade_idle"
		p.active_weapon_index = blade_at if melee else (pistol_at if kind.begins_with("pistol") else gun_at)
		for w in p.weapons:
			if w is Gun:
				w._aiming = false
		blade._windup_left = 0.0
		blade._swing_left = 0.0
		blade._blocking = false
		gun._reload_left = 0.0
		controller.wrist_raised = kind == "watch"
		p.cmd.watch_up = kind == "watch"
		p.cmd.primary = false
		p.cmd.secondary = false
		skin._aim_left = 0.0
		for k in 40:
			await get_tree().process_frame
		var hold := func() -> void:
			blade._animate(1.0 / 60.0)
			match kind:
				"gun_ready":
					skin._aim_left = 1.0
				"ads", "pistol_ads":
					p.cmd.secondary = true
					(p.get_active_weapon() as Gun)._aiming = true
				"reload":
					gun._reload_left = gun.reload_time * 0.5
				"switch":
					p.active_weapon_index = blade_at
					skin._plan_t = minf(skin._plan_t, skin.reach_time * 0.85)
				"windup_left", "windup_right", "windup_overhead":
					blade._windup_left = 1.0
					blade._windup_kind = "light"
					blade.attack_dir = {"windup_left": MeleeWeapon.Dir.LEFT, "windup_right": MeleeWeapon.Dir.RIGHT,
							"windup_overhead": MeleeWeapon.Dir.OVERHEAD}[kind]
				"swing":
					blade.attack_dir = MeleeWeapon.Dir.RIGHT
					blade._swing_left = MeleeWeapon.SWING_TIME * 0.45
				"guard":
					blade._blocking = true
					blade.guard_dir = MeleeWeapon.Dir.LEFT
		for col in 3:
			controller.view_mode = PlayerController.ViewMode.FIRST if col == 0 else PlayerController.ViewMode.THIRD
			outside.current = col == 2
			controller.camera.current = col != 2
			for k in 45:
				hold.call()
				await get_tree().process_frame
			if col == 2:
				# From the front and a little to the right, so the arms show.
				var at := p.global_position
				outside.global_position = at + p.global_basis * Vector3(1.4, 1.5, -3.4)
				outside.look_at(at + Vector3(0, 1.2, 0))
			hold.call()
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			# Each shot full size too, to judge up close.
			DirAccess.make_dir_recursive_absolute(out_dir.path_join("views"))
			frame.save_png(out_dir.path_join("views/%s_%s.png" % [kind, ["first", "third", "front"][col]]))
			var w := frame.get_width()
			var h := frame.get_height()
			var cut_h := h
			var cut_w := cut_h * size.x / size.y
			var cut := frame.get_region(Rect2i((w - cut_w) / 2, 0, cut_w, cut_h))
			cut.resize(size.x, size.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, row * size.y))
		print("shot %s" % kind)
	sheet.save_png(out_dir.path_join("views.png"))
	print("saved views.png")
	raid.queue_free()


## The phone held up in first and third person (home screen, an app, the
## Settings list), and a player seen holding their phone.
func _phone_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	var phone: CanvasLayer = load("res://core/phone/phone.gd").new()
	add_child(phone)
	await _settle(60)
	for bot in raid.bots:
		bot.set_physics_process(false)
		for child in bot.get_children():
			if child is BotBrain:
				child.set_physics_process(false)
	phone.open()
	controller.input_blocked = true
	controller.phone_out = true
	phone.set_holder(raid.player)
	await _settle(30)
	await _shot(out_dir.path_join("phone_home.png"))
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_screen.png"))
	phone.open_app("news")
	await _settle(10)
	await _shot(out_dir.path_join("phone_news.png"))
	phone.open_app("settings")
	await _settle(10)
	await _shot(out_dir.path_join("phone_settings.png"))
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_settings_screen.png"))
	phone.open_settings_tab("view")
	await _settle(10)
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_settings_view_screen.png"))
	phone.open_settings_tab("dev")
	await _settle(10)
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_settings_dev_screen.png"))
	phone.go_home()
	controller.toggle_view()
	await _settle(40)
	await _shot(out_dir.path_join("phone_third_person.png"))
	controller.toggle_view()
	phone.close()
	controller.phone_out = false
	await _settle(30)
	await _shot(out_dir.path_join("phone_put_away.png"))
	# The player on their phone as everyone else sees them: the controller
	# keeps holding it up (third person, so the body is drawn) while a camera
	# of our own looks on from in front and from the side.
	controller.toggle_view()
	controller.input_blocked = true
	controller.phone_out = true
	phone.set_holder(raid.player)
	var me: Actor = raid.player
	var cam := Camera3D.new()
	cam.fov = 40.0
	raid.add_child(cam)
	cam.make_current()
	var facing := Basis(Vector3.UP, controller.yaw)
	for view: Array in [["phone_other_player.png", Vector3(0.35, 1.45, -2.6)], ["phone_other_player_side.png", Vector3(2.4, 1.5, -0.9)],
			["phone_over_shoulder.png", Vector3(0.45, 1.85, 0.9)]]:
		var eye: Vector3 = me.global_position + facing * (view[1] as Vector3)
		cam.look_at_from_position(eye, me.global_position + Vector3(0, 1.15, 0))
		await _settle(40)
		await _shot(out_dir.path_join(view[0]))
	# From the eyes, as first person shows the real body: a camera at the
	# eye point looking where the head looks, past the head itself.
	# The head is left out, as first person leaves it out of its camera.
	for node in me.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var on_head: bool = mesh.get_meta("slot", "") == "head"
		var up := mesh.get_parent()
		while up != null and up != me and not on_head:
			if up is BoneAttachment3D and String((up as BoneAttachment3D).bone_name) in ["Head", "Neck", "neck", "head"]:
				on_head = true
			up = up.get_parent()
		if on_head:
			mesh.visible = false
	var eyes: Vector3 = me.global_position + Vector3(0, me.eye_height, 0)
	cam.fov = 75.0
	cam.near = 0.12
	cam.look_at_from_position(eyes, eyes + facing * Vector3(0.0, -0.3, -1.0))
	await _settle(20)
	await _shot(out_dir.path_join("phone_from_eyes.png"))
	phone.queue_free()
	raid.queue_free()
	await _settle(3)
