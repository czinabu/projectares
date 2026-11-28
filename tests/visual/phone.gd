extends RefCounted
## `--phone-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --phone-only` shows the phone held up, and someone
## else holding theirs.


## The phone held up in first and third person (home screen, an app, the
## Settings list), and a player seen holding their phone.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	v._armed(raid)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	var phone: CanvasLayer = load("res://core/phone/phone.gd").new()
	v.add_child(phone)
	await v._settle(60)
	for bot in raid.bots:
		bot.set_physics_process(false)
		for child in bot.get_children():
			if child is BotBrain:
				child.set_physics_process(false)
	phone.open()
	controller.input_blocked = true
	controller.phone_out = true
	phone.set_holder(raid.player)
	await v._settle(30)
	await v._shot(out_dir.path_join("phone_home.png"))
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_screen.png"))
	phone.open_app("news")
	await v._settle(10)
	await v._shot(out_dir.path_join("phone_news.png"))
	# The Racing app with a few races run (a copy: the profile is put back).
	var racing_before: Dictionary = Profile.racing.duplicate(true)
	var league := preload("res://core/race/race_league.gd")
	var state: Dictionary = league.fresh()
	for result: Dictionary in [{"track": "coilrun", "place": 2, "field": 8, "behind": ["pip", "moss"]},
			{"track": "skyhook", "place": 5, "field": 8, "ahead": ["moss"], "behind": ["haro"]},
			{"track": "coilrun", "place": 1, "field": 8, "behind": ["pip", "haro"]}]:
		state = league.apply(state, result, 1).state
	Profile.racing = state
	phone.open_app("racing")
	await v._settle(10)
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_racing_screen.png"))
	Profile.racing = racing_before
	phone.open_app("settings")
	await v._settle(10)
	await v._shot(out_dir.path_join("phone_settings.png"))
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_settings_screen.png"))
	# A wide field of view setting reads the phone just as well.
	controller.base_fov = 110.0
	await v._settle(30)
	await v._shot(out_dir.path_join("phone_settings_wide.png"))
	controller.base_fov = 80.0
	phone.open_settings_tab("view")
	await v._settle(10)
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_settings_view_screen.png"))
	# Dragging a view slider: the view shows itself as it is, live.
	controller.phone_preview = true
	controller.base_fov = 100.0
	await v._settle(30)
	await v._shot(out_dir.path_join("phone_settings_preview.png"))
	controller.phone_preview = false
	controller.base_fov = 80.0
	phone.open_settings_tab("dev")
	await v._settle(10)
	phone._screen.get_texture().get_image().save_png(out_dir.path_join("phone_settings_dev_screen.png"))
	phone.go_home()
	controller.toggle_view()
	await v._settle(40)
	await v._shot(out_dir.path_join("phone_third_person.png"))
	phone.open_app("settings")
	await v._settle(20)
	await v._shot(out_dir.path_join("phone_settings_third.png"))
	phone.go_home()
	# The Mirror app's mirror, in third person and then first: you should see
	# yourself in it past the phone in your hand.
	var mirror: Node3D = load("res://core/visual/mirror.gd").new()
	mirror.setup(raid.player, controller.camera)
	raid.player.get_parent().add_child(mirror)
	controller.phone_mirror = mirror
	phone.open_app("mirror")
	await v._settle(40)
	await v._shot(out_dir.path_join("phone_mirror_third.png"))
	# Third person's dressing room: the camera in front, the hologram beside.
	mirror.visible = false
	controller.dressing_room = true
	phone.dressing = true
	await v._settle(40)
	await v._shot(out_dir.path_join("phone_dressing_room.png"))
	controller.dressing_turn = 0.9
	await v._settle(20)
	await v._shot(out_dir.path_join("phone_dressing_room_turned.png"))
	controller.dressing_room = false
	controller.dressing_turn = 0.0
	phone.dressing = false
	mirror.visible = true
	controller.toggle_view()
	# As `Main` has it: the mirror stands, the view frames your reflection
	# and the phone's screen is thrown up beside it.
	phone.set_mirror_up(true)
	await v._settle(40)
	await v._shot(out_dir.path_join("phone_mirror_first.png"))
	# Lowered to look in the mirror: the whole kit shows, in both views.
	phone.set_mirror_lowered(true)
	controller.phone_out = phone.held()
	await v._settle(40)
	await v._shot(out_dir.path_join("phone_mirror_lowered_first.png"))
	controller.toggle_view()
	await v._settle(40)
	await v._shot(out_dir.path_join("phone_mirror_lowered_third.png"))
	controller.toggle_view()
	phone.set_mirror_lowered(false)
	phone.mirror_up = false
	controller.phone_out = true
	controller.phone_mirror = null
	mirror.queue_free()
	phone.go_home()
	phone.close()
	controller.phone_out = false
	await v._settle(30)
	await v._shot(out_dir.path_join("phone_put_away.png"))
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
		await v._settle(40)
		await v._shot(out_dir.path_join(view[0]))
	# The Mirror's relaxed stand, as the glass and everyone else see it: the
	# phone low at the hip, the head up (the dressing room's held pose).
	controller.dressing_room = true
	cam.make_current()
	for view: Array in [["phone_mirror_pose.png", Vector3(0.0, 1.35, -2.4)], ["phone_mirror_pose_side.png", Vector3(2.2, 1.4, -0.9)]]:
		var eye: Vector3 = me.global_position + facing * (view[1] as Vector3)
		cam.look_at_from_position(eye, me.global_position + Vector3(0, 1.05, 0))
		await v._settle(40)
		await v._shot(out_dir.path_join(view[0]))
	controller.dressing_room = false
	cam.make_current()
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
	await v._settle(20)
	await v._shot(out_dir.path_join("phone_from_eyes.png"))
	phone.queue_free()
	raid.queue_free()
	await v._settle(3)
