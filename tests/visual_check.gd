extends Node
## Dev tool: runs a real raid with camera and HUD and saves screenshots, so the
## visuals can be checked without playing. Needs a display (or xvfb):
##   godot --path . res://tests/visual_check.tscn -- <output_dir>
## Add a world id after the folder to shoot only that world.
##
## A new mode is a file of its own: `tests/visual/<name>.gd` with
## `static func shoot(v: Node, out_dir: String, args: PackedStringArray)`,
## run by `--<name>-only` (underscores in the file name are dashes in the
## flag), with this node as `v` for its helpers (`v._settle`, `v._shot`).
## It is found by itself, so it never edits this file. (The modes below
## came before that.)

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BasePlan := preload("res://core/base/base_plan.gd")
const Vfx := preload("res://core/visual/vfx.gd")


func _ready() -> void:
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	Profile.persist = false
	if await _run_mode_file(out_dir, args):
		get_tree().quit()
		return
	if args.size() > 1 and not args[1].begins_with("--"):
		await _world_shots(out_dir, args[1])
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

	# `-- <output_dir> --melee-only` shoots every melee weapon in hand.
	if "--melee-only" in args:
		var at := args.find("--melee-only")
		await _melee_shots(out_dir, args[at + 1] if at + 1 < args.size() else "")
		get_tree().quit()
		return

	# `-- <output_dir> --swing-only` films melee attacks frame by frame, one
	# row per move, so the motion (not one pose) can be judged. Naming an
	# item after it (`--swing-only blade_arc`) films only that weapon's
	# moves, from the front three-quarter and from the eyes (first person).
	# `-- <output_dir> --technique-only <item id>` films one melee weapon's
	# held ready stance, every swing and every guard, from the front
	# three-quarter and from the eyes side by side, in one raid (quick to
	# run while tuning `ActionPose.techniques`).
	# `-- <output_dir> --bind-only [item id]` films two fighters, one
	# swinging into the other's guard from each side, a heavy and a parry,
	# from the side, to check the blades meet at one point (`ActionPose.bind`).
	if "--bind-only" in args:
		var at := args.find("--bind-only")
		await _bind_sheet(out_dir, args[at + 1] if at + 1 < args.size() and ItemDB.has_item(args[at + 1]) else "blade_scrap")
		get_tree().quit()
		return

	if "--technique-only" in args:
		var at := args.find("--technique-only")
		await _technique_sheet(out_dir, args[at + 1] if at + 1 < args.size() else "blade_scrap")
		get_tree().quit()
		return

	if "--swing-only" in args:
		var at := args.find("--swing-only")
		var only: String = args[at + 1] if at + 1 < args.size() and ItemDB.has_item(args[at + 1]) else ""
		await _swing_strips(out_dir, only)
		get_tree().quit()
		return

	# `-- <output_dir> --camera-only [row,row]` shoots both cameras and the
	# body from the side, looking level, up and down, aimed and with a blade.
	if "--camera-only" in args:
		var at := args.find("--camera-only")
		await _camera_shots(out_dir, args[at + 1] if args.size() > at + 1 and not args[at + 1].begins_with("--") else "")
		get_tree().quit()
		return
	# `-- <output_dir> --views-only [row,row]` shoots each action in first
	# person, the third-person camera and from the front, side by side.
	if "--views-only" in args:
		var at := args.find("--views-only")
		await _view_shots(out_dir, args[at + 1] if args.size() > at + 1 else "")
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
	# `-- <output_dir> --holster-only [melee item id]` shoots holstered
	# weapons on the body, with that melee weapon in place of the kit's.
	if "--holster-only" in args:
		var at := args.find("--holster-only")
		await _holster_shots(out_dir, args[at + 1] if at + 1 < args.size() else "")
		get_tree().quit()
		return

	# `-- <output_dir> --emotes-only` shoots every emote (`Emotes`) on the one
	# body: from the front at two beats, from the side, over the shoulder and
	# from the eyes. `EMOTE_ROWS=wave,sit` shoots only those.
	if "--emotes-only" in args:
		await _emote_shots(out_dir)
	# `-- <output_dir> --graphics-only` shoots what the graphics settings are
	# for: a line of soldiers out to 150 m in Ashfront and the home base, with
	# the settings as saved (`--aa <0-4>` picks the anti-aliasing, `--ink 0|1`
	# the edge ink on far shapes).
	# `-- <output_dir> --sightlines-only [level ...]` looks out over every
	# outdoor world through the player's own camera, in toward the middle
	# and out to the rim, at each View distance level (`GameSettings.
	# VIEW_DISTANCE`, all of them by default), and writes the draw calls and
	# primitives of each shot to sightlines.txt beside the pictures.
	if "--sightlines-only" in args:
		await _sightline_shots(out_dir, args)
		get_tree().quit()
		return

	if "--graphics-only" in args:
		await _graphics_shots(out_dir, args)
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
	_armed(raid)
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
	Input.action_press("alt_fire")
	await _settle(2)
	var own := raid.player.get_active_weapon() as MeleeWeapon
	if own:
		own.guard_dir = MeleeWeapon.Dir.LEFT
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
		# The blade picks its sides by its combo: start at the step for this one.
		cleaver.combo_step = [MeleeWeapon.Dir.LEFT, MeleeWeapon.Dir.RIGHT, MeleeWeapon.Dir.OVERHEAD].find(pose["dir"])
		foe.cmd.secondary = pose.get("guard", false)
		await _settle(5)
		if pose.has("guard"):
			cleaver.guard_dir = pose["dir"]
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
		_armed(raid)
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
	_armed(raid)
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
	var gear := ["rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher", "blade_arc",
			"hammer_breaker", "knife_gutter", "axe_splitter", "spear_lancer", "pistol_machine", "pistol_hand_cannon",
			"optic_scope", "optic_reflex", "muzzle_suppressor", "grip_vertical", "frame_runner", "frame_trooper", "frame_bulwark", "helm_warden", "helm_seeker", "helm_ember", "jetpack_mk2", "boots_thruster",
			"wings_glide", "chip_blink", "chip_barrier", "chip_pulse", "bike_scrapper", "bike_raider", "medkit",
			"medkit", "scrap_metal", "scrap_metal", "scrap_metal", "alloy_ingot", "reactor_core", "lattice_shard"]
	var worn := {"primary": "dmr_longshot", "frame": "frame_bulwark", "helmet": "helm_warden", "vehicle": "bike_raider"}
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
		"base_overview.png": [Vector3(0, 3.4, 9.2), Vector3(0, 1.2, -6)],
		"base_hub_back.png": [Vector3(0, 2.4, 6.5), Vector3(0, 1.5, -10)],
		"base_hub_left.png": [Vector3(5, 2.4, 0), Vector3(-11.5, 1.4, 0)],
		"base_hub_right.png": [Vector3(-5, 2.4, 0), Vector3(11.5, 1.4, 0)],
		"base_plan_table.png": [Vector3(1.5, 2.3, 3.6), Vector3(0.3, 1.0, 0)],
		"base_range.png": [Vector3(0.0, 2.2, -base.range_from() - 4.0), Vector3(0.0, 1.4, -base.range_from() - 30.0)],
		"base_corridor.png": [Vector3(0.0, 1.8, -7.0), Vector3(0.0, 1.5, -24.0)],
		"base_door.png": [Vector3(-1.5, 2.0, 3.0), Vector3(-2.0, 1.4, 10.0)],
		"base_deploy.png": [Vector3(3.0, 2.6, 1.0), Vector3(7.0, 1.2, 10.0)],
	}
	# Each room from its doorway, wherever it stands.
	for room: String in BasePlan.ROOMS:
		var xf := base.room_transform(room)
		views["base_room_%s.png" % room] = [xf * Vector3(0.0, 2.6, 3.6), xf * Vector3(0.0, 1.2, -7.5)]
	for file: String in views:
		camera.look_at_from_position(views[file][0], views[file][1])
		await _settle(4)
		await _shot(out_dir.path_join(file))
	# The wall mirror, with you in your loadout standing in front of it.
	var glass := HomeBase.MIRROR_AT
	base.player.position = glass + Vector3(0.0, -0.25, -1.8)
	base.player.cmd.yaw = 0.0
	base.wall_mirror.setup(base.player, camera)
	camera.look_at_from_position(glass + Vector3(-1.2, 1.4, -4.2), glass + Vector3(0, 1.2, 0))
	await _settle(8)
	await _shot(out_dir.path_join("base_wall_mirror.png"))
	# A station's screen, live on the console: from across the room, then
	# moved in to use it.
	var screen_view := SubViewport.new()
	screen_view.size = Vector2i(1280, 720)
	screen_view.disable_3d = true
	add_child(screen_view)
	var hub := Hub.new()
	screen_view.add_child(hub)
	for id: String in ["locker", "trader"]:
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
		"bunker_overview.png": [Vector3(0, 3.4, 9.2), Vector3(0, 1.2, -6)],
		"bunker_hub_left.png": [Vector3(5, 2.4, 0), Vector3(-11.5, 1.4, 0)],
		"bunker_hub_right.png": [Vector3(-5, 2.4, 0), Vector3(11.5, 1.4, 0)],
		"bunker_test_lane.png": [Vector3(0.0, 1.7, -base.range_from() + 1.5), Vector3(0.0, 1.5, -base.range_from() - 14.0)],
	}
	for room: String in BasePlan.ROOMS:
		var xf := base.room_transform(room)
		bunker["bunker_room_%s.png" % room] = [xf * Vector3(0.0, 2.6, 3.6), xf * Vector3(0.0, 1.2, -5.0)]
	for file: String in bunker:
		camera.make_current()
		camera.look_at_from_position(bunker[file][0], bunker[file][1])
		await _settle(4)
		await _shot(out_dir.path_join(file))
	# The full base again, rearranged at the plan table, and the table in use.
	var moved := {"W1": "garage", "W2": "armory", "N1": "ops", "N2": "stores", "E1": "gear", "E2": "workshop"}
	base.show_gear(gear, worn, BaseUpgrades.full(), moved)
	await _settle(10)
	for file: String in {"custom_hub_left.png": 0, "custom_hub_right.png": 0}:
		var from := Vector3(5, 2.4, 0) if "left" in file else Vector3(-5, 2.4, 0)
		camera.make_current()
		camera.look_at_from_position(from, Vector3(-11.5 if "left" in file else 11.5, 1.4, 0))
		await _settle(4)
		await _shot(out_dir.path_join(file))
	await _plan_table_shots(base, out_dir)
	camera.make_current()
	camera.fov = 75.0
	base.queue_free()
	await _settle(2)


## The plan table in use, as the player sees it: the customizer on its
## screen, with the hologram beyond, on each tab.
func _plan_table_shots(base: HomeBase, out_dir: String) -> void:
	base.set_scrip(5200)
	base.use_plan()
	var view: Node3D = load("res://core/ui/bench_view.gd").new()
	view.base = base
	view.target = "plan"
	base.add_child(view)
	view.focus()
	await _settle(40)
	await _shot(out_dir.path_join("plan_table_layout.png"))
	view.panel.shape_pick = "ring"
	view.panel.base.plan_preview(view.panel.with_change("shape", "ring"))
	view.panel._refresh()
	await _settle(6)
	await _shot(out_dir.path_join("plan_table_layout_ring.png"))
	view.panel.show_tab("rooms")
	view.panel.socket_pick = "N1"
	view.panel._refresh()
	await _settle(6)
	await _shot(out_dir.path_join("plan_table_rooms.png"))
	view.panel.show_tab("styles")
	view.panel.room_pick = "gear"
	view.panel.style_pick = "ring"
	base.plan_preview(view.panel.with_change("style:gear", "ring"))
	base.plan_mark("gear")
	view.panel._refresh()
	await _settle(6)
	await _shot(out_dir.path_join("plan_table_styles.png"))
	view.panel.show_tab("finishes")
	view.panel.area_pick = "armory"
	view.panel.finish_pick = "brass"
	base.plan_mark("armory")
	view.panel._refresh()
	await _settle(6)
	await _shot(out_dir.path_join("plan_table_finishes.png"))
	view.leave()
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


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


## The same view of Ashfront when quiet, in a battle and in all-out war.
func _war_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	_armed(raid)
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
		_armed(raid)
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
func _swing_strips(out_dir: String, only := "") -> void:
	if only != "":
		for view: String in ["face", "side", "first"]:
			var picked: Array = []
			for move: String in ["light_right", "light_left", "light_overhead", "heavy_right", "heavy", "combo", "guard_left", "guard_overhead"]:
				picked.append([only, move])
			await _film_swings(out_dir.path_join("swings_%s_%s.png" % [only, view]), picked, view)
		return
	var moves := [
		["blade_scrap", "light_right"], ["blade_scrap", "light_overhead"], ["blade_scrap", "heavy"],
		["knife_gutter", "light_left"], ["knife_gutter", "heavy"], ["axe_splitter", "light_right"],
		["axe_splitter", "light_overhead"], ["hammer_breaker", "light_right"], ["hammer_breaker", "heavy"],
		["spear_lancer", "light_overhead"], ["spear_lancer", "heavy"], ["blade_scrap", "back"],
		["blade_scrap", "deflect"],
	]
	await _film_swings(out_dir.path_join("swings.png"), moves, "front")


## Films `moves` ([item id, move] rows) into one sheet at `path`, from the
## front three-quarter or from the eyes ("first": the head left out, as the
## first-person camera does).
func _film_swings(path: String, moves: Array, view: String) -> void:
	var cell := 240
	var sheet := Image.create(SWING_FRAMES * cell, moves.size() * cell, false, Image.FORMAT_RGBA8)
	for row in moves.size():
		var id: String = moves[row][0]
		var move: String = moves[row][1]
		var raid := Raid.new()
		add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_scrap", id, "jetpack_mk1", "plate_light"])
		_armed(raid)
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
		# The spawn may be inside a gate outpost, where weapons are locked.
		raid.zone_rules = false
		player.weapons_locked = false
		var cam := Camera3D.new()
		raid.add_child(cam)
		cam.current = true
		cam.fov = 40.0
		var at := player.global_position
		cam.global_position = at + player.global_basis.x * 1.6 - player.global_basis.z * 2.0 + Vector3(0, 1.5, 0)
		cam.look_at(at + Vector3(0, 1.25, 0))
		var skin: Node = player.get_node_or_null("Skin")
		if view in ["face", "side"]:
			# Close up on the body from its front three-quarter, or side on
			# from its right, lit from the camera so the blade reads.
			var ahead := -player.global_basis.z
			var right := player.global_basis.x
			var spot := ahead * 2.2 + right * 1.3 if view == "face" else right * 2.8 + ahead * 0.4
			cam.global_position = at + spot + Vector3(0, 1.45, 0)
			cam.look_at(at + Vector3(0, 1.3, 0))
			var lamp := OmniLight3D.new()
			lamp.omni_range = 8.0
			lamp.light_energy = 2.0
			raid.add_child(lamp)
			lamp.global_position = cam.global_position + Vector3(0, 0.6, 0)
		if view == "first" and skin != null:
			cam.fov = 75.0
			cam.near = 0.02
			cam.cull_mask &= ~(1 << (16 - 1))  # Mirror.HEAD_LAYER
			skin.hide_head(true)
		var stances := {"light_right": MeleeWeapon.Dir.RIGHT, "light_left": MeleeWeapon.Dir.LEFT,
				"heavy_right": MeleeWeapon.Dir.RIGHT, "guard_left": MeleeWeapon.Dir.LEFT}
		blade.combo_step = [MeleeWeapon.Dir.LEFT, MeleeWeapon.Dir.RIGHT, MeleeWeapon.Dir.OVERHEAD].find(
				stances.get(move, MeleeWeapon.Dir.OVERHEAD))
		await _settle(2)
		match move:
			"heavy", "heavy_right":
				player.cmd.tertiary_pressed = true
			"guard_left", "guard_overhead":
				player.cmd.secondary = true
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
			if move == "deflect" and col == 2:
				var shot := DamageInfo.make(10.0, player, "bullet", at)
				player.get_active_weapon().modify_incoming(shot)
			# A press is read in the tick after it is set.
			await get_tree().physics_frame
			await get_tree().physics_frame
			if view == "first" and skin != null:
				var aimed: Basis = player.global_basis.orthonormalized() * Basis(Vector3.RIGHT, player.cmd.pitch)
				var eye: Variant = skin.eye_point(aimed)
				cam.global_transform = Transform3D(aimed, eye if eye != null else player.get_eye_position())
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
	sheet.save_png(path)
	print("saved %s" % path)


## A contact sheet of where holstered weapons are worn: one row each for the
## blade in hand (gun slung on the back) and the gun in hand (blade on the hip),
## with the jetpack on and off, seen from four sides; then everything
## holstered on each flight rig in turn (holster_rigs.png).
func _holster_shots(out_dir: String, melee_id := "") -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	_armed(raid)
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


## The camera pass: each row held still and shot from the eyes, from the
## third-person camera and from the right side, where the head and chest show
## whether they follow the aim. Saves `camera.png` and each shot full size
## under `camera/`. `CAM_ROWS` or the argument picks rows.
func _camera_shots(out_dir: String, only := "") -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "blade_scrap", "pistol_service", "jetpack_mk1",
			"plate_light", "helm_spotter"])
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
	var skin: Node = p.get_node("Skin")
	var slot := {}
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			slot["blade"] = i
		elif p.weapons[i] is Gun and p.weapons[i].is_sidearm:
			slot["pistol"] = i
		elif p.weapons[i] is Gun and not slot.has("rifle"):
			slot["rifle"] = i
	var outside := Camera3D.new()
	outside.fov = 40.0
	raid.add_child(outside)
	# [row, weapon, pitch, aimed]
	var rows := [["level", "rifle", -0.05, false], ["look_up", "rifle", 0.6, false],
			["look_down", "rifle", -0.6, false], ["ads", "rifle", -0.05, true], ["ads_up", "rifle", 0.5, true],
			["pistol_ads", "pistol", -0.05, true], ["blade", "blade", -0.05, false], ["blade_down", "blade", -0.6, false]]
	if only == "" and OS.has_environment("CAM_ROWS"):
		only = OS.get_environment("CAM_ROWS")
	if only != "":
		rows = rows.filter(func(r: Array) -> bool: return r[0] in only.split(","))
	var size := Vector2i(400, 300)
	var sheet := Image.create(3 * size.x, rows.size() * size.y, false, Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("camera"))
	for row in rows.size():
		var kind: String = rows[row][0]
		p.active_weapon_index = slot[rows[row][1]]
		controller.pitch = rows[row][2]
		p.cmd.pitch = controller.pitch
		p.cmd.yaw = controller.yaw
		p.cmd.aim_dir = Basis.from_euler(Vector3(p.cmd.pitch, p.cmd.yaw, 0.0)) * Vector3.FORWARD
		var aimed: bool = rows[row][3]
		for col in 3:
			controller.view_mode = PlayerController.ViewMode.FIRST if col == 0 else PlayerController.ViewMode.THIRD
			outside.current = col == 2
			controller.camera.current = col != 2
			if col == 2:
				var at := p.global_position
				outside.global_position = at + p.global_basis * Vector3(2.6, 1.4, -0.4)
				outside.look_at(at + Vector3(0, 1.3, 0))
			for k in 40:
				p.cmd.secondary = aimed
				for w in p.weapons:
					if w is Gun:
						w._aiming = aimed and w == p.get_active_weapon()
				skin._aim_left = 1.0 if rows[row][1] != "blade" else 0.0
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			frame.save_png(out_dir.path_join("camera/%s_%s.png" % [kind, ["first", "third", "side"][col]]))
			var w := frame.get_width()
			var h := frame.get_height()
			var cut_w := h * size.x / size.y
			var cut := frame.get_region(Rect2i((w - cut_w) / 2, 0, cut_w, h))
			cut.resize(size.x, size.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, row * size.y))
		print("shot %s" % kind)
	sheet.save_png(out_dir.path_join("camera.png"))
	print("saved camera.png")
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
			OS.get_environment("VIEW_SIDEARM") if OS.has_environment("VIEW_SIDEARM") else "pistol_service", "jetpack_mk1",
			OS.get_environment("VIEW_FRAME") if OS.has_environment("VIEW_FRAME") else "plate_light"]
	# `VIEW_FRAME=<item id>` picks the armor frame worn, and `VIEW_PITCH`
	# tips the view (negative looks down), to see what the plates block.
	# `VIEW_OPTIC=<item id>` fits an optic to the rifle, for the aim rows.
	if OS.has_environment("VIEW_OPTIC"):
		kit.append(OS.get_environment("VIEW_OPTIC"))
	raid.start(Worlds.get_world("ashfront"), 42, kit)
	_armed(raid)
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
	controller.pitch = OS.get_environment("VIEW_PITCH").to_float() if OS.has_environment("VIEW_PITCH") else -0.05
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
			if col == 2:
				# From the front and a little to the right, so the arms show.
				# Placed before the body settles, so it is posed up close.
				var at := p.global_position
				outside.global_position = at + p.global_basis * Vector3(1.4, 1.5, -3.4)
				outside.look_at(at + Vector3(0, 1.2, 0))
			for k in 45:
				hold.call()
				await get_tree().process_frame
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


## One melee weapon's whole technique on one sheet: a row per move (the
## ready stance, each light, the heavies, each guard), frames every
## `SWING_STEP` ticks, each frame from the front three-quarter (left) and
## from the eyes (right), rendered together by two sub-viewports.
func _bind_sheet(out_dir: String, id: String) -> void:
	var moves := ["light_right", "light_left", "light_overhead", "heavy", "parry"]
	var frames := 10
	var cell := 320
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_scrap", id, "plate_light"])
	var player := raid.player
	var foe: Actor = null
	for bot in raid.bots:
		if foe == null:
			foe = bot
			for child in bot.get_children():
				if child is BotBrain:
					child.set_physics_process(false)
		else:
			bot.global_position += Vector3(0, -300, 0)
	await _settle(10)
	# Players arrive unarmed: the blade is drawn as a player would.
	raid.zone_rules = false
	player.weapons_locked = false
	for i in player.weapons.size():
		if player.weapons[i] is MeleeWeapon:
			player._draw_weapon(i)
	await _settle(40)
	foe.weapons_locked = false
	# The foe dressed and armed through the kit like anyone, so its blade
	# has its model and stats.
	Loadout.refit(foe, [id, "plate_light"])
	for i in foe.weapons.size():
		if foe.weapons[i] is MeleeWeapon:
			foe._draw_weapon(i)
	await _settle(20)
	var blade := player.get_active_weapon() as MeleeWeapon
	blade.light_stamina = 0.0
	blade.heavy_stamina = 0.0
	blade.light_damage = 0.0
	blade.heavy_damage = 0.0
	blade.heavy_lunge = 0.0
	blade.light_step = 0.0
	var at := player.global_position
	var ahead := -player.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var right := ahead.cross(Vector3.UP)
	foe.global_position = at + ahead * 2.1
	foe.cmd.yaw = player.cmd.yaw + PI
	foe.cmd.aim_dir = -ahead
	foe.cmd.move = Vector2.ZERO
	foe.thin(1)
	var views := []
	for view in ["side", "behind"]:
		var port := SubViewport.new()
		port.size = Vector2i(cell, cell)
		port.world_3d = get_viewport().world_3d
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(port)
		var cam := Camera3D.new()
		port.add_child(cam)
		cam.current = true
		cam.fov = 40.0
		views.append(cam)
	var mid := at + ahead * 1.05
	views[0].global_position = mid + right * 3.6 + Vector3(0, 1.4, 0)
	views[0].look_at(mid + Vector3(0, 1.3, 0))
	views[1].global_position = at - ahead * 1.6 - right * 1.0 + Vector3(0, 1.9, 0)
	views[1].look_at(mid + Vector3(0, 1.3, 0))
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 2.0
	raid.add_child(lamp)
	lamp.global_position = mid + right * 2.0 + Vector3(0, 2.4, 0)
	var sheet := Image.create(frames * 2 * cell, moves.size() * cell, false, Image.FORMAT_RGBA8)
	var start := player.global_transform
	var foe_start := foe.global_transform
	for row in moves.size():
		var move: String = moves[row]
		player.global_transform = start
		foe.global_transform = foe_start
		player.velocity = Vector3.ZERO
		foe.stagger_left = 0.0
		player.stagger_left = 0.0
		foe.stamina = foe.max_stamina
		blade.combo_step = ["light_right", "light_left", "light_overhead"].find(move) if move.begins_with("light") else 0
		# A guard held well before the swing blocks it; one raised just
		# before it lands parries it.
		foe.cmd.secondary = move != "parry"
		await _settle(30)
		if move == "heavy":
			player.cmd.tertiary_pressed = true
		else:
			player.cmd.primary_pressed = true
		var wind := blade.heavy_windup if move == "heavy" else blade.light_windup + blade.light_tell
		var contact_tick := int(wind * 60.0)
		var tick := 0
		for col in frames:
			for k in 2:
				if move == "parry" and tick == contact_tick - 6:
					foe.cmd.secondary = true
				await get_tree().physics_frame
				tick += 1
				# `physics_frame` comes before the tick runs: a press is
				# let go only once a tick has seen it.
				if tick >= 2:
					player.cmd.primary_pressed = false
					player.cmd.tertiary_pressed = false
			# Film from a few ticks before the contact through the bind.
			if col == 0:
				while tick < contact_tick - 4:
					await get_tree().physics_frame
					tick += 1
					if move == "parry" and tick == contact_tick - 6:
						foe.cmd.secondary = true
			for k in 2:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			for v in 2:
				var img: Image = views[v].get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((col * 2 + v) * cell, row * cell))
		foe.cmd.secondary = false
		await _settle(60)
		print("filmed bind %s %s" % [id, move])
	var path := out_dir.path_join("bind_%s.png" % id)
	sheet.save_png(path)
	print("saved %s" % path)


func _technique_sheet(out_dir: String, id: String) -> void:
	var moves := ["ready", "light_right", "light_left", "light_overhead", "heavy",
			"guard_right", "guard_left", "guard_overhead", "reel"]
	var frames := 10
	var cell := 200
	var wide := 356
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_scrap", id, "plate_light"])
	_armed(raid)
	for bot in raid.bots:
		bot.queue_free()
	var player := raid.player
	await _settle(10)
	# Out of any safe zone's rules first, or the switch is refused.
	raid.zone_rules = false
	player.weapons_locked = false
	player.cmd.switch_weapon = player.weapons.size() - 1
	for i in player.weapons.size():
		if player.weapons[i] is MeleeWeapon:
			player.cmd.switch_weapon = i
	await _settle(5)
	player.cmd.switch_weapon = -1
	await _settle(40)
	var blade := player.get_active_weapon() as MeleeWeapon
	blade.light_stamina = 0.0
	blade.heavy_stamina = 0.0
	var skin: Node = player.get_node_or_null("Skin")
	var views := []
	for view in ["face", "side", "first"]:
		var port := SubViewport.new()
		# The eyes see a 16:9 screen, as the game does.
		port.size = Vector2i(wide if view == "first" else cell, cell)
		port.world_3d = get_viewport().world_3d
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(port)
		var cam := Camera3D.new()
		port.add_child(cam)
		cam.current = true
		if view == "first":
			cam.fov = 75.0
			cam.near = 0.02
			cam.cull_mask &= ~(1 << (16 - 1))  # Mirror.HEAD_LAYER
		else:
			cam.fov = 40.0
		views.append(cam)
	if skin != null:
		skin.hide_head(true)
	var at := player.global_position
	var ahead := -player.global_basis.z
	var right := player.global_basis.x
	views[0].global_position = at + ahead * 2.4 + right * 1.4 + Vector3(0, 1.5, 0)
	views[0].look_at(at + Vector3(0, 1.2, 0))
	views[1].global_position = at + right * 2.8 + ahead * 0.4 + Vector3(0, 1.45, 0)
	views[1].look_at(at + Vector3(0, 1.25, 0))
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 2.0
	raid.add_child(lamp)
	lamp.global_position = views[0].global_position + Vector3(0, 0.8, 0)
	var sheet := Image.create(frames * (2 * cell + wide), moves.size() * cell, false, Image.FORMAT_RGBA8)
	var start := player.global_transform
	var yaw := player.cmd.yaw
	var dirs := {"right": MeleeWeapon.Dir.RIGHT, "left": MeleeWeapon.Dir.LEFT, "overhead": MeleeWeapon.Dir.OVERHEAD}
	for row in moves.size():
		var move: String = moves[row]
		var side: String = move.get_slice("_", 1) if "_" in move else "overhead"
		# A swing goes toward its stance: the side it comes from is the mirror.
		var dir: int = dirs[side]
		# The blade picks its sides by the combo: start each light at the step
		# that swings from `side`.
		blade.combo_step = [MeleeWeapon.Dir.RIGHT, MeleeWeapon.Dir.LEFT, MeleeWeapon.Dir.OVERHEAD].find(dir)
		player.stagger_left = 0.0
		# A heavy lunges: every move starts from the same spot.
		player.global_transform = start
		player.velocity = Vector3.ZERO
		player.cmd.yaw = yaw
		await _settle(3)
		match move.get_slice("_", 0):
			"heavy":
				player.cmd.tertiary_pressed = true
			"guard":
				player.cmd.secondary = true
			"light":
				player.cmd.primary_pressed = true
			"reel":
				player.stagger(1.2)
		for col in frames:
			await get_tree().physics_frame
			await get_tree().physics_frame
			if move.begins_with("guard"):
				# A guard turns to meet a swing; with none coming, show each side.
				blade.guard_dir = dir as MeleeWeapon.Dir
			player.cmd.primary_pressed = false
			player.cmd.tertiary_pressed = false
			if skin != null:
				var aimed: Basis = player.global_basis.orthonormalized() * Basis(Vector3.RIGHT, player.cmd.pitch)
				var eye: Variant = skin.eye_point(aimed)
				views[2].global_transform = Transform3D(aimed, eye if eye != null else player.get_eye_position())
			for k in SWING_STEP - 2:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			for v in 3:
				var img: Image = views[v].get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(col * (2 * cell + wide) + v * cell, row * cell))
		player.cmd.secondary = false
		await _settle(45)
		print("filmed %s %s" % [id, move])
	var path := out_dir.path_join("technique_%s.png" % id)
	sheet.save_png(path)
	print("saved %s" % path)


## Ashfront and the home base for judging edges and how far things read: a
## line of soldiers at 15 to 150 m looking into the field, a wide look over
## it, and the base's main room and range. Shot with the graphics settings
## as they are (`--aa <level>` sets the anti-aliasing and `--ink 0|1` the
## edge ink first, when the game has those settings), so the same command
## gives before and after.
func _graphics_shots(out_dir: String, args: PackedStringArray) -> void:
	var GameSettings: GDScript = load("res://core/settings/game_settings.gd")
	GameSettings.set("persist", false)
	var at := args.find("--aa")
	if at >= 0 and at + 1 < args.size():
		GameSettings.call("set_value", "anti_aliasing", int(args[at + 1]))
	at = args.find("--ink")
	if at >= 0 and at + 1 < args.size():
		GameSettings.call("set_value", "edge_ink", args[at + 1] != "0")
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	_armed(raid)
	raid.war.cooling = 0.0
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	raid.player.set_physics_process(false)
	raid.player.visible = false
	var gate: Node3D = raid.outposts[0]
	var forward := -Vector3(gate.global_position.x, 0.0, gate.global_position.z).normalized()
	var origin := gate.global_position + forward * 22.0
	origin.y = raid.map.call("ground_height", origin.x, origin.z)
	var side := Vector3(-forward.z, 0.0, forward.x)
	var distances: Array[float] = [15.0, 30.0, 50.0, 75.0, 105.0, 150.0]
	var lateral: Array[float] = [-4.0, 2.5, -2.0, 1.5, -1.0, 0.8]
	var line: Array[Actor] = []
	for bot in raid.bots:
		if line.size() >= distances.size() or bot.is_dead:
			continue
		line.append(bot)
	for i in line.size():
		var spot := origin + forward * distances[i] + side * lateral[i]
		line[i].global_position = Vector3(spot.x, raid.map.call("ground_height", spot.x, spot.z), spot.z)
		line[i].velocity = Vector3.ZERO
		line[i].rotation.y = atan2(-side.x, -side.z)
	for bot in raid.bots:
		if bot not in line:
			bot.global_position += Vector3(0, -400, 0)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 800.0
	raid.add_child(cam)
	cam.current = true
	# Up on a ridge of rubble, so the rise in front of the gate does not hide
	# the line.
	var eye := origin + Vector3(0, 7.0, 0)
	cam.global_position = eye
	var mid := line[mini(2, line.size() - 1)].global_position if not line.is_empty() else origin + forward * 50.0
	cam.look_at(mid + Vector3(0, 1.0, 0))
	await _settle(60)
	await _shot(out_dir.path_join("ashfront_line.png"))
	cam.global_position = eye + Vector3(0, 12.0, 0) - forward * 8.0
	cam.look_at(origin + forward * 120.0)
	await _settle(10)
	await _shot(out_dir.path_join("ashfront_wide.png"))
	raid.queue_free()
	await _settle(4)

	var base := HomeBase.new()
	base.show_gear(["rifle_carbine", "smg_stinger", "dmr_longshot", "blade_arc", "frame_trooper", "helm_warden",
			"jetpack_mk2", "bike_raider"], {"primary": "rifle_carbine", "frame": "frame_trooper", "helmet": "helm_warden"},
			BaseUpgrades.full())
	add_child(base)
	var camera := Camera3D.new()
	camera.fov = 75.0
	base.add_child(camera)
	camera.make_current()
	base.player.global_position = Vector3(3, 0.1, 2)
	await _settle(40)
	var views := {
		"base_overview.png": [Vector3(0, 3.2, 8.2), Vector3(0, 1.2, -4)],
		"base_range.png": [Vector3(0.0, 2.2, -14.0), Vector3(0.0, 1.4, -40.0)],
	}
	for file: String in views:
		camera.global_position = views[file][0]
		camera.look_at(views[file][1])
		await _settle(6)
		await _shot(out_dir.path_join(file))
	base.queue_free()


## Players arrive unarmed (`Loadout.arrive_unarmed`); the shots here show
## the weapon in hand, so it is drawn as a player would.
func _armed(raid: Raid) -> void:
	if raid.player != null and raid.player.get_active_weapon() == null:
		raid.player._draw_weapon(raid.player.weapon_for_key(1))


## See `--sightlines-only` in `_ready`.
func _sightline_shots(out_dir: String, args: PackedStringArray) -> void:
	var GameSettings: GDScript = load("res://core/settings/game_settings.gd")
	GameSettings.set("persist", false)
	var levels: Array = []
	var has_levels: bool = GameSettings.call("to_dict").has("view_distance")
	for i in range(args.find("--sightlines-only") + 1, args.size()):
		if args[i].is_valid_int():
			levels.append(int(args[i]))
	if levels.is_empty():
		levels = range((GameSettings.get("VIEW_DISTANCE") as Array).size()) if has_levels else [-1]
	var report := PackedStringArray()
	var worlds: Array = ["ashfront", "frostline", "meridian", "plaza", "arena"]
	for world_id: String in worlds:
		for level: int in levels:
			if level >= 0:
				GameSettings.call("set_value", "view_distance", level)
			var raid: Raid
			if world_id == "arena":
				var arena := Arena.new()
				add_child(arena)
				arena.start_solo(["rifle_carbine"])
				raid = arena
			else:
				raid = Raid.new()
				add_child(raid)
				var world := Worlds.social_world() if world_id == "plaza" else Worlds.get_world(world_id)
				raid.start(world, 42)
			for bot in raid.bots:
				bot.get_node("Brain").set_physics_process(false)
			var controller := PlayerController.new()
			controller.setup(raid.player)
			raid.add_child(controller)
			await _settle(30)
			var spawn := raid.player.global_position
			var to_mid := Vector3(-spawn.x, 0.0, -spawn.z)
			if to_mid.length() < 20.0:
				to_mid = Vector3(0, 0, -20)
			raid.player.set_physics_process(false)
			# From the spawn toward the middle, from halfway in out over the
			# rim, and from 50 m over the spawn.
			var half := spawn + to_mid * 0.5
			for look: Array in [["in", spawn, to_mid, 0.03], ["rim", half, -to_mid, 0.03], ["high", spawn + Vector3(0, 50, 0), to_mid, -0.2]]:
				var at: Vector3 = look[1]
				if look[0] == "rim" and raid.map.has_method("ground_height"):
					at.y = float(raid.map.call("ground_height", at.x, at.z))
				raid.player.global_position = at
				var dir: Vector3 = look[2]
				controller.yaw = atan2(-dir.x, -dir.z)
				controller.pitch = look[3]
				await _settle(25)
				await RenderingServer.frame_post_draw
				var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
				var name := "%s_%s_%s" % [world_id, look[0], "before" if level < 0 else str(level)]
				var cam := get_viewport().get_camera_3d()
				report.append("%s far=%d draws=%d primitives=%d" % [name, int(cam.far) if cam != null else 0, draws, prims])
				print(report[-1])
				await _shot(out_dir.path_join(name + ".png"))
			raid.queue_free()
			await _settle(5)
	var file := FileAccess.open(out_dir.path_join("sightlines.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(report) + "\n")


## Every emote, a row each (`emotes.png`, full size under `emotes/`): from
## the front at two beats, from the right, third person and first person.
func _emote_shots(out_dir: String) -> void:
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("plaza"), 42, [Loadout.BARE])
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await _settle(30)
	p.set_physics_process(false)
	controller.set_physics_process(false)
	controller.pitch = -0.05
	p.cmd.pitch = controller.pitch
	p.cmd.yaw = controller.yaw
	# The body faces the way the view does (physics is off, so set it here).
	p.rotation.y = controller.yaw
	var pose := ActionPose.of(p)
	var outside := Camera3D.new()
	outside.fov = 40.0
	raid.add_child(outside)
	var rows: Array = Emotes.IDS.duplicate()
	if OS.has_environment("EMOTE_ROWS"):
		rows = Array(OS.get_environment("EMOTE_ROWS").split(","))
	# [seconds in, camera]: 0 from the front, 1 from the right, 2 third person, 3 first person.
	var cols := [[0.5, 0], [1.2, 0], [1.2, 1], [1.2, 2], [1.2, 3]]
	var size := Vector2i(320, 240)
	var sheet := Image.create(cols.size() * size.x, rows.size() * size.y, false, Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("emotes"))
	for row in rows.size():
		var id: String = rows[row]
		p.cmd.emote = Emotes.number_of(id)
		for k in 60:
			await get_tree().process_frame
		for col in cols.size():
			var at_time: float = cols[col][0]
			var cam: int = cols[col][1]
			controller.view_mode = PlayerController.ViewMode.FIRST if cam == 3 else PlayerController.ViewMode.THIRD
			outside.current = cam <= 1
			controller.camera.current = cam > 1
			for k in 10:
				pose.emote_clock = at_time
				await get_tree().process_frame
			var at := p.global_position
			if cam == 0:
				outside.global_position = at + p.global_basis * Vector3(0.0, 1.2, -3.4)
			elif cam == 1:
				outside.global_position = at + p.global_basis * Vector3(3.4, 1.2, 0.0)
			outside.look_at(at + Vector3(0, 0.95, 0))
			pose.emote_clock = at_time
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			frame.save_png(out_dir.path_join("emotes/%s_%d_%s.png" % [id, int(at_time * 100), ["front", "right", "third", "first"][cam]]))
			var w := frame.get_width()
			var h := frame.get_height()
			var cut_w := h * size.x / size.y
			var cut := frame.get_region(Rect2i((w - cut_w) / 2, 0, cut_w, h))
			cut.resize(size.x, size.y)
			cut.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cut, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, row * size.y))
		print("shot %s" % id)
	sheet.save_png(out_dir.path_join("emotes.png"))
	print("saved emotes.png")
	raid.queue_free()


## Runs the `tests/visual/` file a `--<name>-only` flag names, if there is
## one. True when it ran.
func _run_mode_file(out_dir: String, args: PackedStringArray) -> bool:
	for arg in args:
		if not (arg.begins_with("--") and arg.ends_with("-only")):
			continue
		var path := "res://tests/visual/%s.gd" % arg.trim_prefix("--").trim_suffix("-only").replace("-", "_")
		if ResourceLoader.exists(path):
			var mode: Variant = load(path)
			await mode.shoot(self, out_dir, args)
			return true
	return false
