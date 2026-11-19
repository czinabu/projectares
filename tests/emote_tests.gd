extends RefCounted
## Checks for emotes (DESIGN.md "Emotes"): the list, how one travels in the
## command and online, the watch's emote icon, how the controller starts and
## ends one, and the pose on the one body (both views look at it). Kept in
## its own file and called from the test runner.


static func run(t: Node) -> void:
	_rules(t)
	_watch(t)
	await _controller(t)
	await _poses(t)


static func _rules(t: Node) -> void:
	print("Emotes: the list and the command")
	t.check(Emotes.IDS.size() == 8 and Emotes.IDS.size() <= ActorCommand.MAX_EMOTE,
			"eight emotes, each fits in the command")
	var round_trip := true
	for id in Emotes.IDS:
		round_trip = round_trip and Emotes.id_of(Emotes.number_of(id)) == id and Emotes.name_of(id) != ""
	t.check(round_trip and Emotes.id_of(0) == "" and Emotes.id_of(99) == "" and Emotes.number_of("nope") == 0,
			"each emote has a number and a name, and none is 0")
	t.check(Emotes.seconds_of("wave") > 0.0 and Emotes.seconds_of("sit") == 0.0,
			"a wave ends on its own, a sit holds until you move")
	var cmd := ActorCommand.new()
	cmd.emote = Emotes.number_of("taunt")
	cmd.stance = 2
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	t.check(copy.emote == cmd.emote and copy.stance == 2, "the emote travels in the command beside the stance")
	var sent: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	var online := ActorCommand.new()
	online.apply_array(sent)
	t.check(online.emote == cmd.emote and online.stance == 2, "and in the packed inputs a client sends")
	var bad := cmd.to_array()
	bad[ActorCommand.STANCE_INDEX] = -50
	online.apply_array(bad)
	t.check(online.emote == 0 and online.stance == 0, "a bad emote from another machine plays nothing")


static func _watch(t: Node) -> void:
	print("Emotes: the watch")
	t.check(Hud.Wrist.tab_of("emote") == "status" and "emote" in Hud.Wrist.SLOTS,
			"the emote icon is on the watch's Status tab")
	var slot := Hud.emote_slot(2, "point")
	t.check(slot.id == "emote" and slot.count == Emotes.IDS.size() and slot.index == 2
			and str(slot.detail).begins_with("Point") and "playing" in str(slot.detail) and "wheel" in slot.hints,
			"the icon turns through every emote and says which one is playing")
	var home := Hud.base_watch_slots("Home base", {}, [], 0, 1, "")
	t.check(home.size() == Hud.Wrist.SLOTS.size() and home[Hud.Wrist.SLOTS.find("emote")].id == "emote"
			and home[Hud.Wrist.SLOTS.find("emote")].index == 1, "the emote icon works at home too")


static func _controller(t: Node) -> void:
	print("Emotes: playing one from the watch")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("plaza"), 5, ["rifle_scrap", "blade_scrap", "pistol_service"])
	await t.frames(20)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	controller.set_physics_process(false)
	await t.frames(30)
	t.check(p.is_on_floor(), "the player stands on the plaza floor")
	# Up on the watch, onto the emote icon, open it, turn to the salute, click.
	controller.wrist_raised = true
	controller.watch_focus_moved = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("emote")
	t.check(controller.watch_takes_fire() and controller.click_watch() and controller.watch_open == "emote",
			"a click opens the emote icon")
	controller.step_watch(1)
	t.check(controller.emote_pick == 1, "the wheel turns through the emotes")
	t.check(controller.click_watch() and controller.emote_playing == "salute" and not controller.wrist_raised,
			"a click plays the picked emote and lowers the watch")
	var cmd := p.cmd
	cmd.clear_one_shots()
	controller._tick_emote(cmd, 0.1)
	t.check(cmd.emote == Emotes.number_of("salute"), "the emote goes out in the command")
	controller._tick_emote(cmd, Emotes.seconds_of("salute"))
	t.check(controller.emote_playing == "" and cmd.emote == 0, "a salute ends on its own")
	controller.start_emote("sit")
	controller._tick_emote(cmd, 30.0)
	t.check(controller.emote_playing == "sit" and cmd.emote == Emotes.number_of("sit"), "a sit holds")
	cmd.move = Vector2(0, 1)
	controller._tick_emote(cmd, 0.1)
	t.check(controller.emote_playing == "" and cmd.emote == 0, "moving gets you up")
	cmd.move = Vector2.ZERO
	controller.start_emote("dance")
	controller.phone_out = true
	controller._tick_emote(cmd, 0.1)
	t.check(controller.emote_playing == "", "the phone stops an emote")
	controller.phone_out = false
	# With a weapon out the emote puts it away, and that is not taken for a
	# weapon key that would end it.
	# (Set just now: the plaza puts weapons away on its next tick.)
	p.active_weapon_index = 0
	controller.start_emote("wave")
	cmd.switch_weapon = controller._pending_switch
	controller._tick_emote(cmd, 0.1)
	t.check(cmd.switch_weapon == ActorCommand.HOLSTER and controller.emote_playing == "wave",
			"an emote puts the weapon in hand away and plays on")
	cmd.switch_weapon = 0
	controller._tick_emote(cmd, 0.1)
	t.check(controller.emote_playing == "", "drawing a weapon ends it")
	# The shortcut keys: straight onto the emote icon, opened, and down again.
	controller.wrist_raised = false
	controller.watch_shortcut("emote")
	t.check(controller.wrist_raised and controller.focused_watch_icon() == "emote" and controller.watch_open == "emote",
			"the emote key raises the watch straight onto the opened emote wheel")
	controller.watch_shortcut("emote")
	t.check(not controller.wrist_raised, "and again lowers it")
	controller.watch_shortcut("map")
	t.check(controller.wrist_raised and controller.focused_watch_icon() == "map", "the map key raises it onto the map")
	controller.watch_shortcut("emote")
	t.check(controller.wrist_raised and controller.focused_watch_icon() == "emote", "and the emote key moves it over")
	controller.wrist_raised = false
	controller.watch_open = ""
	controller.emote_pick = Emotes.IDS.find("cheer")
	controller.quick_emote()
	t.check(controller.emote_playing == "cheer", "the quick emote key plays the one last picked")
	controller.quick_emote()
	t.check(controller.emote_playing == "", "and stops it")
	for action in ["emote_wheel", "quick_emote", "watch_map", "ping", "squad_chat", "friends"]:
		t.check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
				"the %s shortcut has a key" % action)
	t.check(_no_key_shared(), "no two actions share a key")
	# Everyone else's copy of the player plays what the command says.
	cmd.emote = Emotes.number_of("cheer")
	var pose := ActionPose.of(p)
	for i in 30:
		pose.advance_emote(1.0 / 30.0)
	t.check(pose.emote_id == "cheer" and pose.emote > 0.99, "the body's shared pose takes the emote in")
	p.airborne_time = 1.0
	for i in 30:
		pose.advance_emote(1.0 / 30.0)
	t.check(pose.emote <= 0.0 and pose.emote_id == "", "in the air no emote shows, whatever the command says")
	p.airborne_time = 0.0
	cmd.emote = 0
	controller.queue_free()
	raid.queue_free()
	await t.frames(2)


static func _poses(t: Node) -> void:
	print("Emotes: on the body")
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("plaza"), 6, [Loadout.BARE])
	await t.frames(20)
	var p := raid.player
	var skin := p.get_node_or_null("Skin")
	t.check(skin != null and skin.arm != null, "the player wears a model")
	if skin == null or skin.arm == null:
		Look.enabled = false
		raid.queue_free()
		return
	await t.frames(30)
	var skel: Skeleton3D = skin.arm.skeleton
	var bones := {"hand_r": skel.find_bone("Wrist.R"), "hand_l": skel.find_bone("Wrist.L"),
			"hips": skel.find_bone("Hips"), "head": skel.find_bone("Head")}
	var standing := await _read(t, p, skin, skel, bones, 0)
	var cheer := await _read(t, p, skin, skel, bones, Emotes.number_of("cheer"))
	t.check(cheer.hand_r.y > standing.head.y and cheer.hand_l.y > standing.head.y,
			"a cheer puts both hands over the head (%.2f, %.2f over %.2f)" % [cheer.hand_r.y, cheer.hand_l.y, standing.head.y])
	var wave := await _read(t, p, skin, skel, bones, Emotes.number_of("wave"))
	t.check(wave.hand_r.y > standing.head.y - 0.1 and wave.hand_l.y < standing.hips.y + 0.2,
			"a wave raises one hand only")
	var sit := await _read(t, p, skin, skel, bones, Emotes.number_of("sit"))
	t.check(sit.hips.y < 0.4 and sit.head.y < standing.head.y - 0.4,
			"sitting puts the hips on the ground (%.2f m up)" % sit.hips.y)
	t.check(sit.eye != null and standing.eye != null and (sit.eye as Vector3).y < (standing.eye as Vector3).y - 0.4,
			"the eyes come down with the head, so first person sits too")
	var point := await _read(t, p, skin, skel, bones, Emotes.number_of("point"))
	var ahead := p.get_aim_dir()
	t.check((point.hand_r - standing.hand_r).dot(ahead) > 0.25, "pointing reaches the hand out where you look")
	await _read(t, p, skin, skel, bones, 0)
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)


## Plays emote `number` (0 for none) a while, then where the bones are in the
## actor's frame, read while the skeleton reports its update, and the eyes.
static func _read(t: Node, p: Actor, skin: Node, skel: Skeleton3D, bones: Dictionary, number: int) -> Dictionary:
	p.cmd.emote = number
	await t.frames(45)
	var seen := {}
	var read := func() -> void:
		var to_actor := p.global_transform.affine_inverse() * skel.global_transform
		for key: String in bones:
			seen[key] = to_actor * skel.get_bone_global_pose(bones[key]).origin
		var eye: Variant = skin.eye_point(p.global_basis)
		seen["eye"] = p.global_transform.affine_inverse() * (eye as Vector3) if eye != null else null
	skel.skeleton_updated.connect(read)
	await t.frames(3)
	skel.skeleton_updated.disconnect(read)
	return seen


## True if no key or mouse button is bound to two actions.
static func _no_key_shared() -> bool:
	var seen := {}
	for action: StringName in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key := ""
			if event is InputEventKey:
				key = "key %d" % (event as InputEventKey).physical_keycode
			elif event is InputEventMouseButton:
				key = "mouse %d" % (event as InputEventMouseButton).button_index
			if key == "":
				continue
			if seen.has(key) and seen[key] != action:
				print("    %s is bound to %s and %s" % [key, seen[key], action])
				return false
			seen[key] = action
	return true
