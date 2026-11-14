extends RefCounted
## The inspect key: whatever is in the hand (a gun, a blade, a toy vehicle)
## is brought in closer, turned so each side shows, and put back to the
## ready hold. It is a held flag on the command (`ActorCommand.inspect`), so
## everyone who sees the player sees it, and the one body is posed by
## `ActionPose` and `WeaponArm`, so first and third person match.


static func run(t: Node) -> void:
	print("Inspecting what is in the hand")
	_check_command(t)
	_check_key(t)
	_check_turns(t)
	await _check_controller(t)
	await _check_pose(t)


## The flag travels with the held keys, both ways.
static func _check_command(t: Node) -> void:
	var cmd := ActorCommand.new()
	cmd.inspect = true
	var copy := ActorCommand.new()
	copy.apply_array(cmd.to_array())
	t.check(copy.inspect, "looking over the item in hand survives the command's network form")
	var packed: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	copy.apply_array(packed)
	t.check(copy.inspect and int(packed[ActorCommand.FLAGS_INDEX]) & ActorCommand.HELD_MASK & ActorCommand.FLAG_INSPECT != 0,
			"and it is a held key, so the server passes it on and others see it")
	t.check(ActorCommand.FLAG_INSPECT & ActorCommand.ONE_SHOT_MASK == 0
			and ActorCommand.FLAG_INSPECT & (ActorCommand.STATE_HOVERING | ActorCommand.STATE_SHELTERED) == 0,
			"its bit is its own (not a press, not a state bit the server sets)")
	cmd.clear_one_shots()
	t.check(cmd.inspect, "it is not cleared with the one-tick presses")


## I is free, bound to nothing else.
static func _check_key(t: Node) -> void:
	var setup: GDScript = preload("res://core/input_setup.gd")
	var keys: Dictionary = setup.KEY_ACTIONS
	t.check(keys.get("inspect", 0) == KEY_I, "the inspect key is I")
	var sharing: Array[String] = []
	for action: String in keys:
		if action != "inspect" and keys[action] == keys.get("inspect", 0):
			sharing.append(action)
	t.check(sharing.is_empty(), "no other action shares the inspect key (%s)" % ", ".join(sharing))


## The turns show one side, then the other, then the top, and end square.
static func _check_turns(t: Node) -> void:
	var length := ActionPose.INSPECT_SECONDS
	t.check(ActionPose.inspect_turn(0.0) == Vector3.ZERO and ActionPose.inspect_turn(length) == Vector3.ZERO
			and ActionPose.inspect_turn(length + 1.0) == Vector3.ZERO, "a look over starts and ends square in the hand")
	var near := ActionPose.inspect_turn(1.0)
	var far := ActionPose.inspect_turn(2.2)
	var top := ActionPose.inspect_turn(3.0)
	t.check(near.y > 0.8 and far.y < 0.0 and far.z < -0.8 and top.x > 0.4,
			"it swings across to show one side, rolls out to show the other, then tips up to show the top")
	var jolt := 0.0
	var last := Vector3.ZERO
	for i in range(1, 341):
		var now := ActionPose.inspect_turn(i * length / 340.0)
		jolt = maxf(jolt, (now - last).length())
		last = now
	t.check(jolt < 0.05, "the turns ease from one to the next, never jumping (largest step %.3f rad)" % jolt)


static func _check_controller(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 51, ["rifle_carbine", "blade_scrap", "pistol_service"])
	await t.frames(5)
	var p := raid.player
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	await t.frames(2)
	controller.start_inspect()
	await t.frames(2)
	t.check(p.cmd.inspect and controller.inspect_left > 0.0, "the inspect key sends the look over with the held keys")
	await t.frames(int(ActionPose.INSPECT_SECONDS * Engine.physics_ticks_per_second) + 4)
	t.check(not p.cmd.inspect, "a look over ends on its own once the turns are done")
	controller.start_inspect()
	await t.frames(2)
	controller._pending_switch = 1
	await t.frames(2)
	t.check(not p.cmd.inspect, "switching weapon stops it")
	controller.start_inspect()
	await t.frames(2)
	controller.wrist_raised = true
	await t.frames(2)
	t.check(not p.cmd.inspect, "raising the watch stops it")
	controller.start_inspect()
	await t.frames(2)
	t.check(not p.cmd.inspect, "and it will not start with the watch up")
	controller.wrist_raised = false
	controller.phone_out = true
	controller.start_inspect()
	await t.frames(2)
	t.check(not p.cmd.inspect, "nor with the phone out")
	controller.phone_out = false
	p.active_weapon_index = -1
	controller.start_inspect()
	await t.frames(2)
	t.check(not p.cmd.inspect, "with nothing in hand there is nothing to look over")
	raid.state_for(p).stowed.append("bike_scrapper")
	controller.held_toy = "bike_scrapper"
	controller.start_inspect()
	await t.frames(2)
	t.check(p.cmd.inspect, "a toy vehicle in the hand can be looked over")
	controller.held_toy = ""
	raid.queue_free()
	await t.frames(2)


## The one body brings each item in and turns it, and puts it back.
static func _check_pose(t: Node) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 52, ["rifle_carbine", "blade_scrap", "pistol_service"])
	await t.frames(10)
	var p := raid.player
	var skin := p.get_node_or_null("Skin")
	if skin == null or skin.arm == null:
		t.check(false, "the player has a posed body to check")
		Look.enabled = false
		raid.queue_free()
		return
	p.set_physics_process(false)
	var pose := ActionPose.of(p)
	for i in p.weapons.size():
		var weapon: Weapon = p.weapons[i]
		var kind := "sidearm" if weapon is Gun and weapon.is_sidearm else ("gun" if weapon is Gun else "blade")
		p.active_weapon_index = i
		p.cmd.inspect = false
		await t.frames(70)
		var eye := p.get_eye_position()
		var ahead := -p.global_basis.z
		var ready_at := weapon.visual.global_position
		var ready_turn := weapon.visual.global_basis.orthonormalized()
		p.cmd.inspect = true
		await t.frames(20)
		pose.inspect_clock = 1.0
		await t.frames(1)
		var in_at := weapon.visual.global_position
		var in_turn := weapon.visual.global_basis.orthonormalized()
		var turned := rad_to_deg(Quaternion(ready_turn).angle_to(Quaternion(in_turn)))
		t.check(pose.inspecting() != "", "%s: looked over from the command alone, so anyone who gets it sees the same" % kind)
		var side := p.global_basis.x
		t.check((in_at - eye).dot(side) < (ready_at - eye).dot(side) - 0.04,
				"%s: brought in toward the middle of the body (%.2f m in)" % [kind, (ready_at - in_at).dot(side)])
		t.check((in_at - eye).dot(ahead) > 0.1, "%s: still in front of the eyes, where first person sees it" % kind)
		t.check(turned > 25.0, "%s: turned in the hand to show a side (%.0f degrees)" % [kind, turned])
		p.cmd.inspect = false
		await t.frames(60)
		var back := rad_to_deg(Quaternion(ready_turn).angle_to(Quaternion(weapon.visual.global_basis.orthonormalized())))
		t.check(weapon.visual.global_position.distance_to(ready_at) < 0.05 and back < 6.0 and pose.inspect <= 0.0,
				"%s: back to the ready hold once done (%.2f m, %.0f degrees off)" % [kind,
				weapon.visual.global_position.distance_to(ready_at), back])
	# A toy vehicle held up off the watch (`Actor.toy_in_hand`, which
	# everyone sees): brought in and turned the same way.
	p.active_weapon_index = -1
	p.cmd.inspect = false
	p.toy_in_hand = "bike_scrapper"
	await t.frames(70)
	var toy: Node3D = skin.toy_prop()
	t.check(toy != null, "toy: held up in the hand")
	if toy != null:
		var toy_ready := toy.global_position
		var toy_turn := toy.global_basis.orthonormalized()
		p.cmd.inspect = true
		await t.frames(20)
		pose.inspect_clock = 1.0
		await t.frames(1)
		var turned := rad_to_deg(Quaternion(toy_turn).angle_to(Quaternion(toy.global_basis.orthonormalized())))
		t.check(pose.inspecting() == "hand" and turned > 25.0 and toy.global_position.distance_to(toy_ready) > 0.05,
				"toy: brought in and turned to show a side (%.0f degrees)" % turned)
		p.cmd.inspect = false
		await t.frames(60)
		var back := rad_to_deg(Quaternion(toy_turn).angle_to(Quaternion(toy.global_basis.orthonormalized())))
		t.check(toy.global_position.distance_to(toy_ready) < 0.05 and back < 6.0, "toy: back to the hold once done")
	p.toy_in_hand = ""
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)
