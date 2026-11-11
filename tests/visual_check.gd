extends Node
## Dev tool: runs a real raid with camera and HUD and saves screenshots, so the
## visuals can be checked without playing. Needs a display (or xvfb):
##   godot --path . res://tests/visual_check.tscn -- <output_dir>

func _ready() -> void:
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	Profile.persist = false

	var hub := Hub.new()
	add_child(hub)
	await _settle(10)
	await _shot(out_dir.path_join("hub.png"))
	hub.queue_free()

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
	# Each side an enemy can wind up from, then its guard, to check the arm
	# and the blade both show the side.
	var poses := [[MeleeWeapon.Dir.RIGHT, "enemy_windup.png", false], [MeleeWeapon.Dir.LEFT, "enemy_windup_left.png", false],
			[MeleeWeapon.Dir.OVERHEAD, "enemy_windup_overhead.png", false], [MeleeWeapon.Dir.LEFT, "enemy_guard_left.png", true]]
	for pose: Array in poses:
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
		foe.equip_weapon(cleaver)
		foe.active_weapon_index = 0
		foe.cmd.stance = pose[0]
		foe.cmd.secondary = pose[2]
		await _settle(5)
		# Held until a physics tick has certainly seen it.
		for i in 6:
			foe.cmd.primary_pressed = not pose[2] and not cleaver.is_winding_up()
			await _settle(1)
		foe.cmd.primary_pressed = false
		await _settle(14)
		await _shot(out_dir.path_join(pose[1]))
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
func _world_shots(out_dir: String) -> void:
	for world in Worlds.all():
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
		for i in mini(4, raid.bots.size()):
			var bot := raid.bots[i]
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
		raid.queue_free()
		await _settle(2)


func _settle(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
