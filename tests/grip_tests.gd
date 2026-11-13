extends RefCounted
## Every gun model is held by its own grip: `Look` finds the trigger guard,
## the pistol grip behind it and the fore end on the mesh, and the hands go
## there, the gun hand's wrist bent to the grip's rake. The same body in both
## views, so the checks read the posed bones (inside `skeleton_updated`).

const BLADES := ["blade_scrap", "blade_arc", "knife_gutter", "axe_splitter", "hammer_breaker", "spear_lancer"]
const GUNS := ["rifle_scrap", "rifle_carbine", "smg_stinger", "dmr_longshot", "shotgun_breacher",
		"pistol_service", "pistol_machine", "pistol_hand_cannon", "power_rail_lance", "power_storm_cannon"]


static func run(t: Node) -> void:
	print("Hands on each gun's own grip")
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 43, ["blade_scrap", "plate_light"])
	await t.frames(10)
	var p := raid.player
	var skin := p.get_node_or_null("Skin")
	t.check(skin != null and skin.arm != null and skin.arm._hold_point != null,
			"the player's model knows where a handle runs through its fist")
	if skin == null or skin.arm == null or skin.arm._hold_point == null:
		Look.enabled = false
		raid.queue_free()
		return
	p.set_physics_process(false)
	var arm = skin.arm
	var skel: Skeleton3D = arm.skeleton
	var holds := {}
	for id: String in GUNS:
		if ItemDB.has_tag(id, "power"):
			Loadout.set_power(p, id)
		else:
			Loadout.equip(p, [id, "blade_scrap", "plate_light"])
		var gun: Gun = null
		for i in p.weapons.size():
			if p.weapons[i] is Gun and p.weapons[i].item_id == id:
				gun = p.weapons[i]
				p.active_weapon_index = i
		if gun == null:
			t.check(false, "%s: equipped" % id)
			continue
		# Long enough for the hand to draw it.
		await t.frames(70)
		var hold: Variant = ActionPose.hold_local(gun)
		t.check(hold != null, "%s: its model has a grip the hand closes on" % id)
		if hold == null:
			continue
		var at: Transform3D = hold
		holds[id] = at
		var trigger := gun.visual.get_node_or_null("Trigger") as Node3D
		if trigger == null:
			trigger = gun.visual.get_node_or_null("Model/Trigger") as Node3D
		t.check(trigger != null and (gun.visual.global_transform.affine_inverse() * trigger.global_position).z < at.origin.z,
				"%s: the trigger is just ahead of the grip" % id)
		t.check(at.origin.y < ActionPose.sight_local(gun).y and at.basis.y.z <= 0.001 and at.basis.y.y > 0.6,
				"%s: the grip hangs under the sight, upright or raked back" % id)
		# Held at the hip and aiming: the fist's middle is on the grip and
		# the fist runs along it.
		for aiming: bool in [false, true]:
			p.cmd.secondary = aiming
			gun._aiming = aiming
			await t.frames(40)
			var seen := {}
			var catch := func() -> void:
				var wrist: Transform3D = skel.get_bone_global_pose(arm._wrist)
				seen["fist"] = skel.global_transform * (wrist * (arm._hold_point as Vector3))
				seen["fist_up"] = (skel.global_basis * (wrist.basis * arm._grip_axis)).normalized()
				seen["grip"] = gun.visual.global_transform * at.origin
				seen["grip_up"] = (gun.visual.global_basis * at.basis.y).normalized()
				if arm._off_palm != null:
					var off: Transform3D = skel.get_bone_global_pose(arm._off_wrist)
					seen["off_palm"] = (skel.global_basis * (off.basis * (arm._off_palm as Vector3))).normalized()
					seen["off_fist"] = skel.global_transform * (off * (arm._off_hold_point as Vector3))
			skel.skeleton_updated.connect(catch)
			await t.frames(3)
			skel.skeleton_updated.disconnect(catch)
			var how := "aiming" if aiming else "at the hip"
			var off: float = (seen["fist"] as Vector3).distance_to(seen["grip"])
			t.check(off < 0.01, "%s, %s: the fist closes on the grip (%.3f m off)" % [id, how, off])
			var lean := rad_to_deg((seen["fist_up"] as Vector3).angle_to(seen["grip_up"]))
			t.check(lean < 14.0, "%s, %s: the hand lies along the grip's rake (%.1f deg off)" % [id, how, lean])
			# Aiming, the off hand holds the gun too: palm up under a long
			# gun's fore end, palm in against the gun hand on a sidearm.
			if aiming and seen.has("off_palm"):
				var up := gun.visual.global_basis.y.normalized()
				var right := gun.visual.global_basis.x.normalized()
				var facing: float = (seen["off_palm"] as Vector3).dot(right if gun.is_sidearm else up)
				t.check(facing > 0.7, "%s: the off hand's palm %s (%.2f)" % [id, "is in against the gun hand" if gun.is_sidearm else "is up under the fore end", facing])
				var fore := gun.visual.get_node_or_null("ForeGrip") as Node3D
				if fore == null:
					fore = gun.visual.get_node_or_null("Model/ForeGrip") as Node3D
				var front: Vector3 = fore.global_position if fore != null and not gun.is_sidearm else seen["grip"]
				var line := Geometry3D.get_closest_point_to_segment(seen["off_fist"], front, seen["grip"])
				var gap: float = (seen["off_fist"] as Vector3).distance_to(line)
				# (A spinning cannon braced at the hip is out of the off arm's reach.)
				if not ActionPose.of(p).shoulders_never(gun):
					t.check(gap < 0.07, "%s: the off hand closes on the gun (%.3f m off)" % [id, gap])
		p.cmd.secondary = false
		gun._aiming = false
	# Gun models differ, so the hands do too.
	if holds.has("smg_stinger") and holds.has("rifle_carbine"):
		var smg: Transform3D = holds["smg_stinger"]
		var carbine: Transform3D = holds["rifle_carbine"]
		t.check(smg.origin.distance_to(carbine.origin) > 0.03 or smg.basis.y.angle_to(carbine.basis.y) > 0.1,
				"each gun model has its grip in its own place")
	# Blades too: the handle runs through the fist, and a two-handed
	# weapon's off hand closes further down the same handle.
	for id: String in BLADES:
		Loadout.equip(p, [id, "plate_light"])
		var blade: MeleeWeapon = null
		for i in p.weapons.size():
			if p.weapons[i] is MeleeWeapon:
				blade = p.weapons[i]
				p.active_weapon_index = i
		await t.frames(70)
		var model := blade.visual.get_node_or_null("Model") if blade != null else null
		t.check(model != null, "%s: dressed" % id)
		if model == null:
			continue
		var two: bool = Look.is_two_handed(blade)
		t.check(model.has_meta("off_grip") == two, "%s: %s" % [id, "a second hand's place on the handle" if two else "held in one hand"])
		var seen := {}
		var catch := func() -> void:
			var wrist: Transform3D = skel.get_bone_global_pose(arm._wrist)
			seen["fist"] = skel.global_transform * (wrist * (arm._ring_point as Vector3))
			seen["handle"] = blade.visual.global_position
			if arm._off_hold_point != null:
				seen["off"] = skel.global_transform * (skel.get_bone_global_pose(arm._off_wrist) * (arm._off_hold_point as Vector3))
			seen["off_handle"] = blade.visual.global_transform * Vector3(0.0, model.get_meta("off_grip", 0.0), 0.0)
		skel.skeleton_updated.connect(catch)
		await t.frames(3)
		skel.skeleton_updated.disconnect(catch)
		var off: float = (seen["fist"] as Vector3).distance_to(seen["handle"])
		t.check(off < 0.015, "%s: the handle runs through the fist (%.3f m off)" % [id, off])
		if two and seen.has("off"):
			# On the handle between its spot and the weapon hand (it slides
			# toward it where the arm cannot reach).
			var line := Geometry3D.get_closest_point_to_segment(seen["off"], seen["off_handle"], seen["handle"])
			var reach: float = (seen["off"] as Vector3).distance_to(line)
			var apart: float = (seen["off"] as Vector3).distance_to(seen["handle"])
			t.check(reach < 0.04 and apart > 0.07, "%s: the off hand closes on the handle beside the weapon hand (%.3f m off, %.2f m apart)" % [id, reach, apart])
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)
