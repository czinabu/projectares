extends RefCounted
## First and third person differ only in where the camera is: both look at
## the same body, posed from one `ActionPose` per actor, holding the same
## weapon in the same hand.


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
	var mid := pose.gun_offset()
	t.check(mid.origin.y < -0.05 and mid.basis.get_euler().z > 0.3,
			"a reload brings the gun down and tips it over")
	gun._reload_left = gun.reload_time * 0.97
	await t.frames(1)
	pose.advance(0.016)
	t.check(pose.reload > 0.0 and pose.reload < 0.5, "a reload eases in")
	gun._reload_left = 0.0
	await t.frames(1)
	pose.advance(0.016)
	t.check(pose.reload == 0.0 and pose.gun_offset() == Transform3D.IDENTITY,
			"after a reload the gun is back in its hold")

	# Melee: the windup reaches toward its side.
	var blade := p.weapons[1] as MeleeWeapon
	p.active_weapon_index = 1
	var held := {}
	for side: int in [MeleeWeapon.Dir.LEFT, MeleeWeapon.Dir.RIGHT, MeleeWeapon.Dir.OVERHEAD]:
		blade._windup_left = 1.0
		blade.attack_dir = side
		for i in 30:
			await t.frames(1)
			pose.advance(1.0 / 30.0)
		held[side] = pose.reach
		t.check(pose.reach.distance_to(pose.arm_windup[side]) < 0.02 and pose.reach_weight > 0.99,
				"the shared pose reaches for the %s windup" % ["left", "right", "overhead"][side])
	t.check(held[MeleeWeapon.Dir.LEFT].x < held[MeleeWeapon.Dir.RIGHT].x - 0.2,
			"a left windup holds the blade further left")
	t.check(held[MeleeWeapon.Dir.OVERHEAD].y > maxf(held[MeleeWeapon.Dir.LEFT].y, held[MeleeWeapon.Dir.RIGHT].y),
			"an overhead windup raises the blade highest")
	# Through a swing the hand crosses to the follow-through side.
	blade._windup_left = 0.0
	blade.attack_dir = MeleeWeapon.Dir.RIGHT
	blade._swing_left = MeleeWeapon.SWING_TIME
	var before: Vector3 = pose.reach
	for i in 20:
		await t.frames(1)
		blade._swing_left = maxf(blade._swing_left - MeleeWeapon.SWING_TIME / 10.0, 0.0)
		pose.advance(1.0 / 60.0)
	var after: Vector3 = pose.reach
	t.check(after.x < before.x - 0.2 and after.y < before.y, "a swing from the right sweeps across and down")
	blade._swing_left = 0.0
	pose._follow_left = 0.0
	for i in 40:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	t.check(pose.reach_weight == 0.0, "once the swing is over the blade is back in its hold")

	# Holding the button draws the arm back toward the swing's side, and
	# after a strike the arm eases back from the follow-through as the blade
	# recovers.
	blade.stance = MeleeWeapon.Dir.LEFT
	blade._charge = blade.hold_time
	for i in 30:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	var from := MeleeWeapon.swing_from(blade.stance)
	t.check(pose.reach.distance_to(pose.arm_windup[from]) < 0.02 and pose.elbow_raise > 0.9,
			"holding toward a heavy draws the arm back to the side the swing comes from")
	blade._charge = -1.0
	blade.attack_dir = MeleeWeapon.Dir.RIGHT
	blade._recover_total = 1.0
	blade._cooldown = 0.9
	t.check(is_equal_approx(ActionPose.recover_left(blade), 1.0 - smoothstep(0.0, 1.0, 0.1)),
			"just after a strike the arm still holds most of its follow-through")
	blade._cooldown = 0.05
	t.check(ActionPose.recover_left(blade) < 0.02, "and is nearly back once the blade is ready")
	blade._cooldown = 0.0
	blade._recover_total = 0.0
	for i in 40:
		await t.frames(1)
		pose.advance(1.0 / 30.0)

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

	# Switching: the gun stays in hand until the hand has reached its holster.
	p.active_weapon_index = blade_at
	await t.frames(1)
	t.check(gun.visual.visible and not blade.visual.visible, "a switch starts with the old weapon still in hand")
	var peak := 0.0
	for i in 60:
		await t.frames(1)
		peak = maxf(peak, skin._moving_weight)
	t.check(peak > 0.9, "the hand goes all the way to the holster")
	t.check(blade.visual.visible and not gun.visual.visible and skin._moving_weight == 0.0,
			"the switch ends with the new weapon in hand")
	p.active_weapon_index = gun_at
	await t.frames(60)
	# Flying flat puts the weapon away.
	p.flight.is_boosting = true
	p.flight.enabled = true
	skin._flight_draw_left = 0.0
	t.check(skin.flies_stowed(), "boosting with nothing to shoot, the weapon is put away")
	p.flight.is_boosting = false
	await t.frames(30)

	# A reload moves the model's hand by the shared offset.
	p.active_weapon_index = gun_at
	await t.frames(30)
	gun.ammo_in_mag = 0
	gun.start_reload()
	gun._reload_left = gun.reload_time * 0.5
	await t.frames(40)
	t.check(skin.arm._gun_weight > 0.99, "the model's arm follows the reload")
	var aim := p.global_basis.orthonormalized() * Basis(Vector3.RIGHT, p.cmd.pitch)
	var wanted := aim * pose.gun_offset().basis
	t.check(p.hand.global_basis.orthonormalized().is_equal_approx(wanted.orthonormalized()),
			"the gun tips in the hand by the reload turn")
	gun._reload_left = 0.0
	await t.frames(10)

	# Raising the watch lifts the model's left arm, from the command, so a
	# remote player's does too.
	p.cmd.watch_up = true
	await t.frames(20)
	t.check(is_equal_approx(pose.watch, 1.0), "the shared pose raises the watch from the command")
	t.check(skin.arm.off_ik != null and is_equal_approx(skin.arm.off_ik.influence, 1.0),
			"a raised watch lifts the left arm")
	p.cmd.watch_up = false
	await t.frames(20)
	t.check(pose.watch == 0.0 and (skin.arm.off_ik == null or skin.arm.off_ik.influence < 0.01),
			"lowering the watch lets the arm down")

	# Standing still with a gun, it is held low.
	p.cmd.primary = false
	p.cmd.secondary = false
	skin._aim_left = 0.0
	await t.get_tree().create_timer(1.2).timeout
	t.check(pose.low_wanted and pose.low > 0.9, "standing still, the gun is held low")
	# Held low, the gun hangs with the hand rather than
	# staying level with the aim.
	await t.frames(2)
	var muzzle_way := -p.hand.global_basis.z.normalized()
	var ahead := -p.global_basis.z.normalized()
	t.check(skin.arm._aim_wrist != null and muzzle_way.dot(ahead) < 0.95,
			"a gun held low points down with the hand (%.2f)" % muzzle_way.dot(ahead))
	# Shots are drawn from the barrel where the model holds it.
	var marker := gun.visual.get_node_or_null("Muzzle") as Node3D
	t.check(marker != null, "the gun's model has a muzzle marker")
	if marker != null:
		p.hand.set_meta("shown", p.hand.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
		t.check(gun.muzzle_point(Vector3.ZERO).distance_to(marker.global_position + p.hand.global_basis * Vector3(0, 1, 0)) < 0.01,
				"a shot's flash and tracer start at the muzzle as the gun is drawn, not where the hand was parked")
		p.hand.remove_meta("shown")
	# First person is the same body seen from the eyes: the camera only leaves
	# out the head, and every other part (arms, gun, pack) is still drawn.
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	controller.set_physics_process(false)
	controller.view_mode = PlayerController.ViewMode.FIRST
	await t.frames(3)
	var head_bit := 1 << (preload("res://core/visual/mirror.gd").HEAD_LAYER - 1)
	var cam: Camera3D = controller.camera
	t.check(cam != null and cam.cull_mask & head_bit == 0, "first person, the camera leaves out the head")
	var drawn := {}
	for mesh in skin.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.visible and m.layers & cam.cull_mask != 0:
			drawn[m.get_meta("slot", "")] = true
	t.check(drawn.has("body") and not drawn.has("head"), "first person, your own body is drawn but not your head")
	var gun_drawn := false
	for mesh in gun.visual.find_children("*", "MeshInstance3D", true, false):
		gun_drawn = gun_drawn or ((mesh as MeshInstance3D).is_visible_in_tree() and (mesh as MeshInstance3D).layers & cam.cull_mask != 0)
	t.check(gun_drawn, "first person, the gun is the one in the model's hand")
	controller.view_mode = PlayerController.ViewMode.THIRD
	await t.frames(3)
	var head_back := false
	for mesh in skin.find_children("*", "MeshInstance3D", true, false):
		if mesh.get_meta("slot", "") == "head":
			head_back = (mesh as MeshInstance3D).layers & cam.cull_mask != 0
	t.check(head_back, "third person, the head is drawn again")
	controller.queue_free()
	p.cmd.secondary = true
	await t.get_tree().create_timer(0.5).timeout
	t.check(pose.low < 0.1, "aiming raises it again (low %.2f, stand %s)" % [pose.low, skin._current])
	p.cmd.secondary = false
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)
