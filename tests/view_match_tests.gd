extends RefCounted
## First and third person show the same action the same way: both read one
## `ActionPose` per actor. Third person it moves the model's arm (`WeaponArm`,
## `ActorSkin`), first person the weapon in front of the camera
## (`PlayerController.first_person_hold`).


static func run(t: Node) -> void:
	print("First and third person match")
	await _check_without_skin(t)
	await _check_with_skin(t)


## The shared state works with no model at all (headless, or a skin without
## the bones), and the first-person hold follows it.
static func _check_without_skin(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 31, ["rifle_carbine", "blade_scrap"])
	await t.frames(3)
	var p := raid.player
	p.set_physics_process(false)
	var pose := ActionPose.of(p)
	t.check(pose != null and ActionPose.of(p) == pose and p.get_node(ActionPose.NODE_NAME) == pose,
			"an actor has one shared pose, made on first use")
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	controller.set_process(false)
	controller.set_physics_process(false)
	var rest := controller.first_person_hold(pose)
	t.check(rest.origin.is_equal_approx(PlayerController.FIRST_PERSON_HAND) and rest.basis.is_equal_approx(Basis.IDENTITY),
			"at rest the first-person hold is the usual one")

	# A reload moves the gun in both views by the same offset.
	var gun := p.weapons[0] as Gun
	p.active_weapon_index = 0
	gun.ammo_in_mag = 0
	gun.start_reload()
	t.check(gun.is_reloading(), "the gun is reloading")
	gun._reload_left = gun.reload_time * 0.5
	await t.frames(1)
	pose.advance(0.016)
	t.check(is_equal_approx(pose.reload, 1.0), "halfway through a reload the gun is at its deepest")
	var mid := controller.first_person_hold(pose)
	t.check(mid.origin.y < rest.origin.y - 0.05 and mid.basis.get_euler().z > 0.3,
			"first person, a reload brings the gun down and tips it over")
	gun._reload_left = gun.reload_time * 0.97
	await t.frames(1)
	pose.advance(0.016)
	t.check(pose.reload > 0.0 and pose.reload < 0.5, "a reload eases in")
	gun._reload_left = 0.0
	await t.frames(1)
	pose.advance(0.016)
	t.check(pose.reload == 0.0 and controller.first_person_hold(pose).origin.is_equal_approx(rest.origin),
			"after a reload the gun is back in its hold")

	# Melee: the same windup offsets move the first-person hand, same sides.
	var blade := p.weapons[1] as MeleeWeapon
	p.active_weapon_index = 1
	var held := {}
	for side: int in [MeleeWeapon.Dir.LEFT, MeleeWeapon.Dir.RIGHT, MeleeWeapon.Dir.OVERHEAD]:
		blade._windup_left = 1.0
		blade.attack_dir = side
		for i in 30:
			await t.frames(1)
			pose.advance(1.0 / 30.0)
		held[side] = controller.first_person_hold(pose).origin
		t.check(pose.reach.distance_to(pose.arm_windup[side]) < 0.02 and pose.reach_weight > 0.99,
				"the shared pose reaches for the %s windup" % ["left", "right", "overhead"][side])
	t.check(held[MeleeWeapon.Dir.LEFT].x < held[MeleeWeapon.Dir.RIGHT].x - 0.2,
			"first person, a left windup holds the blade further left, as third person does")
	t.check(held[MeleeWeapon.Dir.OVERHEAD].y > maxf(held[MeleeWeapon.Dir.LEFT].y, held[MeleeWeapon.Dir.RIGHT].y),
			"first person, an overhead windup raises the blade highest, as third person does")
	# Through a swing the hand crosses to the follow-through side.
	blade._windup_left = 0.0
	blade.attack_dir = MeleeWeapon.Dir.RIGHT
	blade._swing_left = MeleeWeapon.SWING_TIME
	var before := controller.first_person_hold(pose).origin
	for i in 20:
		await t.frames(1)
		blade._swing_left = maxf(blade._swing_left - MeleeWeapon.SWING_TIME / 10.0, 0.0)
		pose.advance(1.0 / 60.0)
	var after := controller.first_person_hold(pose).origin
	t.check(after.x < before.x - 0.2 and after.y < before.y, "first person, a swing from the right sweeps across and down")
	blade._swing_left = 0.0
	pose._follow_left = 0.0
	for i in 40:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	t.check(pose.reach_weight == 0.0 and controller.first_person_hold(pose).origin.distance_to(rest.origin) < 0.01,
			"once the swing is over the blade is back in its hold")

	# A switch: the hand drops toward the holster's side and out of view.
	pose.switch_point = Vector3(-0.2, 0.95, 0.0)
	pose.switch_weight = 1.0
	var stowing := controller.first_person_hold(pose)
	t.check(stowing.origin.y < -0.6 and stowing.origin.x < 0.0, "first person, switching drops the hand toward the holster")
	pose.switch_weight = 0.0

	# The phone comes up from the command, the same for every view.
	p.cmd.phone = true
	for i in 20:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	t.check(is_equal_approx(pose.phone, 1.0), "the shared pose brings the phone up from the command")
	p.cmd.phone = false
	for i in 20:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	t.check(pose.phone == 0.0, "and puts it away again")
	raid.queue_free()
	await t.frames(2)


## With the model: third person and first person play the same switch,
## reload and watch raise, from the same state.
static func _check_with_skin(t: Node) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 32, ["rifle_carbine", "blade_scrap", "jetpack_mk1", "plate_light"])
	await t.frames(20)
	var p := raid.player
	var skin := p.get_node_or_null("Skin")
	t.check(skin != null and skin.arm != null, "the player wears a model with a weapon arm")
	if skin == null or skin.arm == null:
		Look.enabled = false
		raid.queue_free()
		return
	p.set_physics_process(false)
	var pose := ActionPose.of(p)
	var gun_at := -1
	var blade_at := -1
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			blade_at = i
		elif p.weapons[i] is Gun and gun_at < 0:
			gun_at = i
	var gun := p.weapons[gun_at] as Gun
	var blade := p.weapons[blade_at]
	p.active_weapon_index = gun_at
	await t.frames(30)

	for first: bool in [false, true]:
		var view := "first person" if first else "third person"
		p.hand_override = first
		p.active_weapon_index = gun_at
		await t.frames(30)
		# Switching plays out in both views: the gun stays in hand until the
		# hand has reached its holster.
		p.active_weapon_index = blade_at
		await t.frames(1)
		t.check(gun.visual.visible and not blade.visual.visible, view + ": a switch starts with the old weapon still in hand")
		var peak := 0.0
		for i in 60:
			await t.frames(1)
			peak = maxf(peak, pose.switch_weight)
		t.check(peak > 0.9, view + ": the hand goes all the way to the holster")
		t.check(blade.visual.visible and not gun.visual.visible and pose.switch_weight == 0.0,
				view + ": the switch ends with the new weapon in hand")
		p.active_weapon_index = gun_at
		await t.frames(60)
		# Flying flat puts the weapon away in both views.
		p.flight.is_boosting = true
		p.flight.enabled = true
		skin._flight_draw_left = 0.0
		t.check(skin.flies_stowed(), view + ": boosting with nothing to shoot, the weapon is put away")
		p.flight.is_boosting = false
		await t.frames(30)

	# A reload moves the model's hand by the shared offset, third person.
	p.hand_override = false
	p.active_weapon_index = gun_at
	await t.frames(30)
	gun.ammo_in_mag = 0
	gun.start_reload()
	gun._reload_left = gun.reload_time * 0.5
	await t.frames(40)
	t.check(skin.arm._gun_weight > 0.99, "third person, the model's arm follows the reload")
	var aim := p.global_basis.orthonormalized() * Basis(Vector3.RIGHT, p.cmd.pitch)
	var wanted := aim * pose.gun_offset(false).basis
	t.check(p.hand.global_basis.orthonormalized().is_equal_approx(wanted.orthonormalized()),
			"third person, the gun tips in the hand by the same reload turn first person shows")
	gun._reload_left = 0.0
	await t.frames(10)

	# Raising the watch lifts the model's left arm, from the same amount.
	pose.watch = 1.0
	await t.frames(2)
	pose.watch = 1.0
	skin.arm._process(0.016)
	t.check(skin.arm.off_ik != null and is_equal_approx(skin.arm.off_ik.influence, 1.0),
			"third person, a raised watch lifts the left arm")
	pose.watch = 0.0
	skin.arm._process(0.016)
	t.check(skin.arm.off_ik == null or skin.arm.off_ik.influence < 0.01, "lowering the watch lets the arm down")

	# Standing still with a gun, third person holds it low; first person too.
	p.cmd.primary = false
	p.cmd.secondary = false
	skin._aim_left = 0.0
	await t.get_tree().create_timer(1.2).timeout
	t.check(pose.low_wanted and pose.low > 0.9, "standing still, the gun is held low")
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	controller.set_process(false)
	controller.set_physics_process(false)
	t.check(controller.first_person_hold(pose).origin.y < PlayerController.FIRST_PERSON_HAND.y - 0.05,
			"first person lowers the gun too")
	# Held low, third person, the gun hangs with the hand rather than
	# staying level with the aim.
	await t.frames(2)
	var muzzle_way := -p.hand.global_basis.z.normalized()
	var ahead := -p.global_basis.z.normalized()
	t.check(skin.arm._aim_wrist != null and muzzle_way.dot(ahead) < 0.95,
			"third person, a gun held low points down with the hand (%.2f)" % muzzle_way.dot(ahead))
	# Shots are drawn from the barrel where the model holds it.
	var marker := gun.visual.get_node_or_null("Muzzle") as Node3D
	t.check(marker != null, "the gun's model has a muzzle marker")
	if marker != null:
		p.hand.set_meta("shown", p.hand.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
		t.check(gun.muzzle_point(Vector3.ZERO).distance_to(marker.global_position + p.hand.global_basis * Vector3(0, 1, 0)) < 0.01,
				"a shot's flash and tracer start at the muzzle as the gun is drawn, not where the hand was parked")
		p.hand.remove_meta("shown")
	# First person, your own arms hold the weapon.
	p.hand_override = true
	controller._update_arms(true)
	var arms: Node3D = controller._arms
	t.check(arms != null and controller.has_arms(), "first person builds a copy of your arms")
	if arms != null:
		arms.update(true, 0.0, false)
		t.check(arms.visible and arms._ik.influence > 0.9 and arms._off_ik.influence > 0.9,
				"with a gun in hand both arms reach for it")
		var parts := {}
		for mesh in arms.model.find_children("*", "MeshInstance3D", true, false):
			parts[mesh.get_meta("slot", "")] = (mesh as MeshInstance3D).visible
		t.check(parts.get("body", false) and not parts.get("head", true), "only the torso part with the arms is drawn")
		arms.update(false, 0.0, false)
		t.check(not arms.visible, "the arms go away out of first person")
	p.hand_override = false
	p.cmd.secondary = true
	await t.get_tree().create_timer(0.5).timeout
	t.check(pose.low < 0.1, "aiming raises it again (low %.2f, stand %s)" % [pose.low, skin._current])
	p.cmd.secondary = false
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)
