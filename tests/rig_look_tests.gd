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
