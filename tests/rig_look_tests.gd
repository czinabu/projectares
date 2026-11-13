extends RefCounted
## Checks for flight rig models: what each rig looks like, where it is worn,
## and that its flames and wings follow the rig. Called from the test runner.

const RigModel := preload("res://core/visual/rig_model.gd")


static func run(t: Node) -> void:
	# Built from plain shapes, so they work headless too.
	t.check(RigModel.kind_for("jetpack_mk1") == "jetpack" and RigModel.kind_for("jetpack_mk2") == "jetpack"
			and RigModel.kind_for("boots_thruster") == "boots" and RigModel.kind_for("wings_glide") == "wings",
			"each flight rig picks its model from its stats")
	t.check(RigModel.kind_for("rifle_scrap") == "", "gear that is not a flight rig gets no rig model")
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "flight_rig"):
			var back := RigModel.build_back(id)
			var boot := RigModel.build_boot(id, 1.0)
			t.check(back != null or boot != null, "flight rig %s has a model" % id)
			for part: Node3D in [back, boot]:
				if part:
					t.check(not RigModel.nozzles(part).is_empty(), "flight rig %s has a nozzle to burn" % id)
					t.check(part.find_children("*", "CollisionObject3D", true, false).is_empty(), "rig model %s has no collision" % id)
					part.free()

	var pack := RigModel.build_back("jetpack_mk1")
	t.check(RigModel.nozzles(pack).size() == 2, "a jetpack has a nozzle under each tank")
	var display := pack.get_node_or_null("HeatDisplay") as Marker3D
	t.check(display != null and display.position.z > 0.05 and display.get_meta("size", Vector2.ZERO).x > 0.05,
			"a jetpack keeps a clear face on its back for a heat readout")
	var mk1_size := Look.model_bounds(pack).size
	pack.free()
	var mk2 := RigModel.build_back("jetpack_mk2")
	t.check(Look.model_bounds(mk2).size.length() > mk1_size.length(), "the Mk2 jetpack is the bigger pack")
	mk2.free()
	t.check(RigModel.build_back("boots_thruster") == null and RigModel.build_boot("jetpack_mk1", 1.0) == null,
			"boots go only on the feet, and a jetpack only on the back")

	var wings := RigModel.build_back("wings_glide")
	var tip := wings.get_node("WingR/Panel/TipLight") as Node3D
	var stowed_tip := _in(wings, tip)
	var stowed_hidden := not (wings.get_node("WingR") as Node3D).visible
	RigModel.set_wing_spread(wings, 1.0)
	var spread_tip := _in(wings, tip)
	t.check(absf(stowed_tip.x) < 0.15 and stowed_hidden, "retracted wings are tucked inside the pack")
	t.check(spread_tip.x > 0.9 and absf(spread_tip.y) < 0.4, "spread wings reach out to the side")
	var left_tip := _in(wings, wings.get_node("WingL/Panel/TipLight") as Node3D)
	t.check(left_tip.is_equal_approx(Vector3(-spread_tip.x, spread_tip.y, spread_tip.z)), "the wings are mirror images")
	wings.free()

	# Worn in a raid, with the art layer on.
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 21, ["rifle_carbine", "blade_scrap", "jetpack_mk1", "plate_light"])
	await t.frames(30)
	var p := raid.player
	p.set_physics_process(false)
	var skin := p.get_node("Skin")
	var skeleton := skin.find_child("Skeleton3D", true, false) as Skeleton3D
	var jet := skin.find_child("Jetpack", true, false) as Node3D
	t.check(jet != null and jet.get_parent().get_parent() is BoneAttachment3D
			and (jet.get_parent().get_parent() as BoneAttachment3D).bone_name == "Chest",
			"the jetpack is strapped to the chest bone, so it moves with the body")
	if jet:
		t.check((skin as Node3D).transform.basis.y.y > 0.99, "a jetpack flies upright")
		var at := p.to_local(jet.global_position)
		t.check(at.z > 0.0 and at.y > 1.0 and at.y < 1.6 and absf(at.x) < 0.1, "the jetpack sits on the player's back")
		t.check(jet.global_basis.get_scale().is_equal_approx(Vector3.ONE * jet.global_basis.get_scale().x)
				and absf(jet.global_basis.get_scale().x - 1.0) < 0.05, "the jetpack is built to the player's size")
		var flames := jet.find_children("Flame", "Node3D", true, false)
		t.check(flames.size() == 2 and not flames.any(func(f: Node3D) -> bool: return f.visible), "the nozzles are cold at rest")
		p.flight.is_thrusting = true
		await t.frames(2)
		# The flames are set when a frame is drawn, and on a busy machine two
		# physics ticks can pass inside one. The signal comes before the frame's
		# own work, so the second one is the first that is sure to follow it.
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		t.check(flames.all(func(f: Node3D) -> bool: return f.visible), "both nozzles burn while thrusting")
		var down := (flames[0] as Node3D).global_basis.y.normalized()
		t.check(down.y > 0.8, "the flames point down")
		p.flight.is_thrusting = false
		await t.frames(2)
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		t.check(not flames.any(func(f: Node3D) -> bool: return f.visible), "the nozzles go out when thrust stops")

	# A new rig swaps the model.
	_equip(p, "boots_thruster")
	await t.frames(2)
	t.check(skin.find_child("Jetpack", true, false) == null or skin.find_child("Jetpack", true, false).is_queued_for_deletion(),
			"taking the jetpack off takes its model off")
	var boots := skin.find_children("Boot*", "Node3D", true, false)
	t.check(boots.size() == 2, "thruster boots go on both feet")
	var feet := {}
	for boot: Node3D in boots:
		var attach := boot.get_parent().get_parent() as BoneAttachment3D
		if attach:
			feet[attach.bone_name] = boot
	t.check(feet.has("Foot.L") and feet.has("Foot.R"), "each boot is strapped to its own foot")
	if feet.size() == 2:
		var left := p.to_local((feet["Foot.L"] as Node3D).global_position)
		var right := p.to_local((feet["Foot.R"] as Node3D).global_position)
		t.check(left.x < right.x and left.y < 0.35 and right.y < 0.35, "the boots are on the feet, left on the left")
		var boot_flames := skin.find_children("Flame", "Node3D", true, false)
		t.check(boot_flames.size() == 2 and not boot_flames.any(func(f: Node3D) -> bool: return f.visible), "boot thrusters are cold at rest")
		p.flight.heat = 0.0
		p.flight.burst_velocity = 10.0
		p.flight.try_burst()
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		t.check(boot_flames.all(func(f: Node3D) -> bool: return f.visible), "an air jump fires the heel thrusters")
		await t.get_tree().create_timer(0.5).timeout
		t.check(not boot_flames.any(func(f: Node3D) -> bool: return f.visible), "the heel thrusters only burn for a moment")

	# Off the ground the legs never run: a stand plays under an air pose
	# with the knees bent, and the run comes back on landing.
	p.velocity = -p.global_basis.z * 7.0
	await t.get_tree().create_timer(0.5).timeout
	t.check(String(skin._current) in skin.GAITS, "on the ground, moving plays a run or walk")
	var foot_bone: int = skin._glide_legs[0][2] if not skin._glide_legs.is_empty() and not skin._glide_legs[0].is_empty() else -1
	var foot_height := func() -> float:
		skin._pose_glide()
		return p.to_local(skeleton.to_global(skeleton.get_bone_global_pose(foot_bone).origin)).y
	p.airborne_time = 1.0
	p.velocity = -p.global_basis.z * 7.0 + Vector3(0, 5, 0)
	await t.get_tree().create_timer(0.5).timeout
	t.check(skin.is_airborne() and not (String(skin._current) in skin.GAITS), "in the air, moving never plays the run")
	if foot_bone >= 0:
		var leaping: float = foot_height.call()
		t.check(leaping > 0.12, "a jump lifts the lead knee (foot %.2f m up)" % leaping)
		p.flight.is_hovering = true
		p.velocity = -p.global_basis.z * 7.0
		await t.get_tree().create_timer(0.6).timeout
		var hanging: float = foot_height.call()
		t.check(not (String(skin._current) in skin.GAITS) and hanging < leaping,
				"hovering, the legs hang loose instead of running (foot %.2f m up)" % hanging)
		p.flight.is_hovering = false
	p.airborne_time = 0.0
	await t.get_tree().create_timer(0.5).timeout
	t.check(String(skin._current) in skin.GAITS and skin._air < 0.01, "landing brings the run back")

	# Takeoff and landing: a jump starts with a push off the ground, a
	# running one leans into it, and the knees take the landing.
	p.airborne_time = 1.0
	p.velocity = -p.global_basis.z * 7.0 + Vector3(0, 5, 0)
	await t.frames(3)
	t.check(skin._air_push > 0.5, "leaving the ground starts with a push-off (%.2f)" % skin._air_push)
	await t.get_tree().create_timer(0.4).timeout
	t.check(skin._air_push < 0.01, "the push-off is over in a moment")
	var running_lean: float = skin._tilt.length()
	t.check(running_lean > 0.15, "a running takeoff leans into the jump (%.2f rad)" % running_lean)
	p.airborne_time = 0.0
	p.landed.emit(10.0)
	await t.get_tree().create_timer(0.1).timeout
	var squat: float = skin.locomotion.squat
	t.check(squat > 0.2, "landing bends the knees (%.2f)" % squat)
	await t.get_tree().create_timer(0.6).timeout
	t.check(skin.locomotion.squat < 0.01, "and stands up again")
	p.landed.emit(0.5)
	await t.frames(2)
	t.check(skin.locomotion.squat < 0.01, "stepping off a kerb does not squat")
	p.velocity = Vector3(0, 5, 0)
	p.airborne_time = 1.0
	await t.get_tree().create_timer(0.4).timeout
	t.check(skin._tilt.length() < 0.05, "a standing jump goes straight up (%.2f rad)" % skin._tilt.length())
	p.airborne_time = 0.0
	await t.frames(2)
	p.velocity = Vector3.ZERO
	p.airborne_time = 1.0

	# A jetpack boost lays the body out head first with the arms down at the
	# sides; a hover leans the way it drifts; a sideways air dash rolls it over.
	_equip(p, "jetpack_mk2")
	await t.frames(2)
	p.flight.is_hovering = true
	p.velocity = p.global_basis.x * 10.0
	await t.get_tree().create_timer(0.6).timeout
	var hover_axis := p.global_basis.inverse() * (skin as Node3D).global_basis.y
	t.check(hover_axis.x > 0.2 and hover_axis.y > 0.8, "a hovering body leans the way it drifts")
	p.flight.is_boosting = true
	p.velocity = -p.global_basis.z * 22.0
	await t.get_tree().create_timer(0.7).timeout
	var boost_axis := p.global_basis.inverse() * (skin as Node3D).global_basis.y
	t.check(boost_axis.z < -0.95, "a boost lays the body out flat, head first")
	if skeleton and skeleton.find_bone("Wrist.R") >= 0 and skeleton.find_bone("Head") >= 0:
		# Modifier poses only last for the skeleton's update: run it by hand.
		skin._pose_glide()
		var wrist_at := p.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Wrist.R")).origin))
		var head_at := p.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin))
		var hips_at := p.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin)) \
				if skeleton.find_bone("Hips") >= 0 else Vector3.ZERO
		t.check(wrist_at.z > head_at.z + 0.4 and absf(wrist_at.z - hips_at.z) < 0.35 and absf(wrist_at.x) < 0.6,
				"boosting, the arms lie back along the sides, not out ahead")
	var held := p.get_active_weapon()
	if held and held.visual:
		t.check(skin.flies_stowed() and not held.visual.visible, "boosting, the weapon is worn instead of hanging where the hands were")
		p.cmd.secondary = true
		await t.get_tree().create_timer(0.8).timeout
		t.check(held.visual.visible and skin._flight_hold > 0.9, "aiming in a boost draws it again")
		p.cmd.secondary = false
		await t.get_tree().create_timer(2.6).timeout
		t.check(not held.visual.visible, "and it goes back when you stop")
	var belly := p.global_basis.inverse() * (skin as Node3D).global_basis.z
	p.air_dash_side = 1.0
	p.air_dash_left = p.flight.air_dash_time
	await t.get_tree().create_timer(p.flight.air_dash_time * 0.45).timeout
	var rolled := p.global_basis.inverse() * (skin as Node3D).global_basis.z
	t.check(belly.angle_to(rolled) > 1.0, "a sideways air dash barrel rolls the body in flight")
	p.air_dash_left = 0.0
	await t.get_tree().create_timer(0.8).timeout
	rolled = p.global_basis.inverse() * (skin as Node3D).global_basis.z
	t.check(belly.angle_to(rolled) < 0.1, "after the dash the body rights itself")
	p.flight.is_hovering = false
	p.flight.is_boosting = false
	p.velocity = Vector3.ZERO
	await t.get_tree().create_timer(0.6).timeout
	t.check((skin as Node3D).transform.basis.y.y > 0.99, "the body stands up again after a boost")

	# Thruster boots lean into their push, point the nozzles down the
	# exhaust and swivel the flames along it; flying forward the body lies
	# out like a diver, never quite flat, and a dash flattens it further.
	_equip(p, "boots_thruster")
	p.flight.skim_speed = 15.0
	p.flight.air_dash_speed = 20.0
	await t.frames(2)
	var heel_flames: Array[Node3D] = []
	heel_flames.assign(skin.find_children("Flame", "Node3D", true, false).filter(
			func(n: Node) -> bool: return not n.is_queued_for_deletion()))
	var exhaust := func() -> Vector3:
		return p.global_basis.inverse() * -(heel_flames[0].global_basis.y.normalized())
	var body_pitch := func() -> float:
		return (p.global_basis.inverse() * (skin as Node3D).global_basis.y).angle_to(Vector3.UP)
	p.flight.is_skimming = true
	p.velocity = Vector3.ZERO
	await t.get_tree().create_timer(0.8).timeout
	t.check(body_pitch.call() < 0.15, "skimming in place, the boots hold the body upright (%.2f rad)" % body_pitch.call())
	t.check(heel_flames.size() == 2 and heel_flames.all(func(f: Node3D) -> bool: return f.visible)
			and exhaust.call().y < -0.9, "and the heel flames fire straight down")
	p.velocity = -p.global_basis.z * 15.0
	await t.get_tree().create_timer(0.9).timeout
	var cruise_pitch: float = body_pitch.call()
	var cruise_axis := p.global_basis.inverse() * (skin as Node3D).global_basis.y
	t.check(cruise_axis.z < -0.8 and cruise_pitch > 1.0 and cruise_pitch < 1.45,
			"skimming forward, the body lies out head first but never flat (%.2f rad)" % cruise_pitch)
	var cruise_exhaust: Vector3 = exhaust.call()
	t.check(cruise_exhaust.y < -0.4 and cruise_exhaust.z > 0.4,
			"the heel flames fire down and back: holding you up and driving you on (%s)" % cruise_exhaust)
	if skeleton and skeleton.find_bone("Head") >= 0 and foot_bone >= 0:
		skin._pose_glide()
		var head_at := p.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin))
		var foot_at := p.to_local(skeleton.to_global(skeleton.get_bone_global_pose(foot_bone).origin))
		t.check(head_at.z < foot_at.z - 1.0 and foot_at.y < head_at.y,
				"head out ahead, feet trailing below and behind (head %s, foot %s)" % [head_at, foot_at])
	p.cmd.secondary = true
	await t.get_tree().create_timer(0.9).timeout
	var aim_pitch: float = body_pitch.call()
	t.check(aim_pitch < cruise_pitch - 0.2, "aiming lifts the chest so the arms have room (%.2f rad)" % aim_pitch)
	var held_gun := p.get_active_weapon()
	if held_gun and held_gun.visual:
		var aim_dir := (p.global_basis * Basis(Vector3.RIGHT, p.cmd.pitch) * Vector3.FORWARD).normalized()
		var gun_at := p.to_local(held_gun.visual.global_position)
		t.check(held_gun.visual.visible and (-held_gun.visual.global_basis.z).normalized().dot(aim_dir) > 0.95
				and gun_at.z < 0.0 and gun_at.y > 0.5, "lying out, the gun is held ahead and still points along the aim")
	p.cmd.secondary = false
	await t.get_tree().create_timer(skin.aim_hold + 1.0).timeout
	p.velocity = -p.global_basis.z * 35.0
	await t.get_tree().create_timer(0.9).timeout
	t.check(body_pitch.call() > cruise_pitch + 0.05 and body_pitch.call() < PI / 2.0,
			"a dash flattens the body further (%.2f rad)" % body_pitch.call())
	t.check(heel_flames[0].scale.y > 1.3, "and the flames stretch with the harder push (%.2f)" % heel_flames[0].scale.y)
	p.velocity = p.global_basis.x * 15.0
	await t.get_tree().create_timer(0.9).timeout
	var strafe_axis := p.global_basis.inverse() * (skin as Node3D).global_basis.y
	t.check(strafe_axis.x > 0.4 and body_pitch.call() < skin.boot_max_lean + 0.05,
			"skimming sideways, the body rolls into the push (%s)" % strafe_axis)
	t.check(exhaust.call().x < -0.3, "and the flames blow the other way")
	p.velocity = p.global_basis.z * 15.0
	await t.get_tree().create_timer(0.9).timeout
	var back_axis := p.global_basis.inverse() * (skin as Node3D).global_basis.y
	t.check(back_axis.z > 0.4 and body_pitch.call() < skin.boot_max_lean + 0.05,
			"skimming backward, the body leans back, never lying out (%s)" % back_axis)
	p.flight.is_skimming = false
	p.velocity = Vector3.ZERO
	await t.get_tree().create_timer(0.9).timeout
	t.check((skin as Node3D).transform.basis.y.y > 0.99 and skin._boot_w < 0.01, "letting go of the boots stands the body up")

	_equip(p, "wings_glide")
	await t.frames(2)
	var pack_node := skin.find_child("WingPack", true, false) as Node3D
	t.check(pack_node != null and skin.find_children("Boot*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return not n.is_queued_for_deletion()).is_empty(), "glide wings replace the boots")
	if pack_node:
		var wing_tip := pack_node.get_node("WingR/Panel/TipLight") as Node3D
		var stowed_at := p.to_local(wing_tip.global_position)
		t.check(absf(stowed_at.x) < 0.2 and not wing_tip.is_visible_in_tree(), "the wings stay retracted on the ground")
		p.flight.is_gliding = true
		await t.get_tree().create_timer(0.5).timeout
		var spread_at := p.to_local(wing_tip.global_position)
		t.check(absf(spread_at.x) > 1.0 and wing_tip.is_visible_in_tree(), "the wings slide out while gliding")
		var up := (skin as Node3D).transform.basis.y
		t.check(up.z < -0.9 and up.y < 0.4, "gliding lays the body out flat, head first")
		t.check(absf(spread_at.y - p.to_local(pack_node.global_position).y) < 0.25,
				"with the body flat, the wings spread level with it")
		# Fly a steady turn to the right: the body faces the way it flies
		# and banks into the turn, right wing down.
		var port_tip := pack_node.get_node("WingL/Panel/TipLight") as Node3D
		var flying := -p.global_basis.z
		for i in 60:
			flying = flying.rotated(Vector3.UP, -1.4 / 60.0)
			p.velocity = flying * 16.0 + Vector3(0, -1.8, 0)
			await t.get_tree().process_frame
		var bank_gap := port_tip.global_position.y - wing_tip.global_position.y
		t.check(bank_gap > 0.6, "wings bank into a right turn, right wing down (%.2f m)" % bank_gap)
		var nose_dir := (skin as Node3D).global_basis.y
		t.check(Vector3(nose_dir.x, 0, nose_dir.z).normalized().dot(flying) > 0.9, "the gliding body faces the way it flies")
		for i in 90:
			flying = flying.rotated(Vector3.UP, 1.4 / 60.0)
			p.velocity = flying * 16.0 + Vector3(0, -1.8, 0)
			await t.get_tree().process_frame
		bank_gap = port_tip.global_position.y - wing_tip.global_position.y
		t.check(bank_gap < -0.6, "and into a left turn, left wing down (%.2f m)" % bank_gap)
		p.velocity = flying * 24.0 + Vector3(0, -10.0, 0)
		await t.get_tree().create_timer(0.6).timeout
		t.check((skin as Node3D).global_basis.y.y < -0.2, "a dive points the nose down")
		t.check(absf(port_tip.global_position.y - wing_tip.global_position.y) < 0.2, "flying straight levels the wings")
		p.velocity = Vector3.ZERO
		p.flight.is_gliding = false
		await t.get_tree().create_timer(0.5).timeout
		t.check(absf(p.to_local(wing_tip.global_position).x) < 0.2, "the wings retract after gliding")
		t.check((skin as Node3D).transform.basis.y.y > 0.99, "the body stands up again after gliding")

	# A rig on a home base stand is the same model on a mannequin.
	var base := HomeBase.new()
	base.show_gear(["jetpack_mk2", "boots_thruster", "wings_glide"], {})
	t.add_child(base)
	await t.frames(3)
	var shown := {}
	for node in base.find_children("*", "", true, false):
		if node.has_meta("display_item") and ItemDB.has_tag(node.get_meta("display_item"), "flight_rig"):
			var model := node.get_node_or_null("Model")
			if model and model.has_node("Mannequin"):
				shown[node.get_meta("display_item")] = model
	t.check(shown.size() == 3, "every flight rig on show stands on a mannequin")
	if shown.size() == 3:
		t.check((shown["jetpack_mk2"] as Node).has_node("Jetpack") and (shown["wings_glide"] as Node).has_node("WingPack")
				and (shown["boots_thruster"] as Node).has_node("BootL"), "each stand shows the rig's real model")
	base.queue_free()
	raid.queue_free()
	Look.enabled = false
	await t.frames(2)


static func _equip(actor: Actor, id: String) -> void:
	actor.flight.item_id = id
	actor.flight.display_name = ItemDB.item_name(id)
	actor.flight.enabled = true


## A node's position in `root`'s space, before either is in the tree.
static func _in(root: Node3D, node: Node3D) -> Vector3:
	var xform := node.transform
	var up := node.get_parent()
	while up != null and up != root:
		xform = (up as Node3D).transform * xform
		up = up.get_parent()
	return xform.origin
