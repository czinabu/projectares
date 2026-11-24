extends RefCounted
## Aiming down sights is one body animation (`ActionPose.ads`) shared by
## both views: the hands bring the gun's sight up onto the line of the eyes
## and the off hand onto the gun. First person only differs in where the
## camera is, and it looks straight down the sight.


static func run(t: Node) -> void:
	print("Aiming down sights")
	await _check_without_skin(t)
	for kit: Array in [
			["rifle_carbine", "plain sights"],
			["rifle_carbine,optic_reflex", "a reflex sight"],
			["rifle_carbine,optic_scope", "a scope"],
			["dmr_longshot,optic_longscope", "an 8x scope"],
			["pistol_service", "a sidearm"],
			["power_rail_lance", "a power weapon"]]:
		await _check_with_skin(t, (kit[0] as String).split(","), kit[1])
	await _check_on_the_move(t)


static func _aim(p: Actor, gun: Gun, on: bool) -> void:
	p.cmd.secondary = on
	gun._aiming = on


## The shared state alone (headless: no model): it rises with aiming, drops
## for a reload, and a hip-braced gun never comes up.
static func _check_without_skin(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 41, ["rifle_carbine", "pistol_service"])
	await t.frames(3)
	var p := raid.player
	p.set_physics_process(false)
	var pose := ActionPose.of(p)
	p._draw_weapon(0)
	var rifle := p.get_active_weapon() as Gun
	_aim(p, rifle, true)
	for i in 30:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	t.check(is_equal_approx(pose.ads, 1.0), "aiming brings the gun up to the eye (%.2f)" % pose.ads)
	rifle._reload_left = rifle.reload_time * 0.5
	rifle._aiming = false
	for i in 30:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	t.check(pose.ads == 0.0, "a reload takes the gun down from the eye")
	rifle._reload_left = 0.0
	_aim(p, rifle, true)
	await t.frames(1)
	pose.advance(1.0 / 60.0)
	t.check(pose.ads > 0.0 and pose.ads < 0.5, "the gun eases up rather than snapping")
	_aim(p, rifle, false)
	for i in 30:
		await t.frames(1)
		pose.advance(1.0 / 30.0)
	t.check(pose.ads == 0.0, "letting go of aim lowers it again")
	# Locked weapons (behind the range's firing line) take no input: an aim
	# held across the line lets go instead of sticking.
	p.set_physics_process(true)
	p.cmd.secondary = true
	await t.frames(2)
	t.check(rifle.is_aiming(), "holding aim aims")
	p.weapons_locked = true
	await t.frames(2)
	t.check(not rifle.is_aiming(), "with weapons locked an aim held over lets go")
	t.check(p.get_active_weapon() == null, "and the weapon goes away (weapons only come out where they are free)")
	p.weapons_locked = false
	p.cmd.switch_weapon = 0
	await t.frames(1)
	p.cmd.switch_weapon = -1
	await t.frames(2)
	t.check(rifle.is_aiming(), "unlocked and drawn again, the held aim comes back")
	p.cmd.secondary = false
	p.set_physics_process(false)
	var pistol := p.weapons[1] as Gun
	t.check(pose.relief_for(pistol) > pose.relief_for(rifle) + 0.12,
			"a sidearm is held out at arm's length, a rifle shouldered close")
	var cannon := Gun.new()
	cannon.item_id = "power_storm_cannon"
	t.check(pose.shoulders_never(cannon) and not pose.shoulders_never(rifle),
			"a spinning cannon is braced at the hip, never shouldered")
	cannon.free()
	raid.queue_free()
	await t.frames(2)


## With a model: the sight comes onto the eye line, the off hand onto the
## gun, the pose is the same whichever view is on, and the first-person
## camera looks down the sight wherever a physics tick parked the hand.
static func _check_with_skin(t: Node, kit: Array, what: String) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	var power := ""
	var gear: Array = ["blade_scrap", "plate_light"]
	for id: String in kit:
		if ItemDB.has_tag(id, "power"):
			power = id
		else:
			gear.append(id)
	raid.start(Worlds.get_world("ashfront"), 42, gear)
	await t.frames(10)
	var p := raid.player
	if power != "":
		Loadout.set_power(p, power)
	var skin := p.get_node_or_null("Skin")
	t.check(skin != null and skin.arm != null, "%s: the player wears a model with a weapon arm" % what)
	if skin == null or skin.arm == null:
		Look.enabled = false
		raid.queue_free()
		return
	# A power weapon summoned from the watch materializes before it can be
	# used (`Actor.materialize_left`, game time), so it is aimed once it has.
	while p.materialize_left > 0.0:
		await t.frames(1)
	p.set_physics_process(false)
	var gun: Gun = null
	for i in p.weapons.size():
		if p.weapons[i] is Gun and (power == "" or p.weapons[i].item_id == power):
			gun = p.weapons[i]
			p.active_weapon_index = i
			break
	await t.frames(60)
	var pose := ActionPose.of(p)
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	controller.set_physics_process(false)
	controller.view_mode = PlayerController.ViewMode.FIRST
	await t.frames(5)
	var before := ActionPose.sight_shown(gun)
	var eye_before: Vector3 = skin.eye_point(p.global_basis.orthonormalized() * Basis(Vector3.RIGHT, p.cmd.pitch))
	_aim(p, gun, true)
	# Two thirds of a second of game time, however fast the frames run.
	var waited := 0.0
	while waited < 0.66:
		await t.get_tree().process_frame
		waited += t.get_process_delta_time()
	t.check(pose.ads > 0.99, "%s: the gun is up (%.2f)" % [what, pose.ads])
	var aimed := p.global_basis.orthonormalized() * Basis(Vector3.RIGHT, p.cmd.pitch)
	var ahead := -aimed.z
	# Bone poses are only final while the skeleton reports its update.
	var arm = skin.arm
	var skel: Skeleton3D = arm.skeleton
	var seen := {}
	var catch := func() -> void:
		seen["eye"] = skin.eye_point(aimed)
		seen["off"] = skel.global_transform * skel.get_bone_global_pose(arm._off_wrist).origin
		if arm._aim_wrist != null:
			seen["hand_way"] = arm._follow_turn(arm._wrist, arm._held_wrist(gun))
	skel.skeleton_updated.connect(catch)
	await t.frames(3)
	skel.skeleton_updated.disconnect(catch)
	var eye: Vector3 = seen["eye"]
	var sight := ActionPose.sight_shown(gun)
	var off_line := (sight - eye) - ahead * (sight - eye).dot(ahead)
	t.check(off_line.length() < 0.015,
			"%s: the sight is on the eye line (%.3f m off)" % [what, off_line.length()])
	var relief := (sight - eye).dot(ahead)
	t.check(absf(relief - pose.relief_now) < 0.03 and pose.relief_now <= pose.relief_for(gun) + 0.001,
			"%s: the sight sits its relief in front of the eye (%.2f m)" % [what, relief])
	# Held below the eyes, it comes up onto them (the eyes come down onto a
	# long gun's stock some way too, `ActionPose.cheek_eye`).
	t.check(before.y < eye_before.y - 0.08 and sight.y > before.y,
			"%s: aiming raises the gun from its hold (%.2f below the eyes, then %.2f)" % [what, eye_before.y - before.y, sight.y - before.y])
	var off_hand: Vector3 = skin.arm._off_target.global_position
	t.check(skin.arm.off_ik.influence > 0.99, "%s: the off hand comes onto the gun" % what)
	var gun_box_reach := off_hand.distance_to(gun.visual.global_position)
	t.check(gun_box_reach < 0.45, "%s: the off hand holds the gun (%.2f m from it)" % [what, gun_box_reach])
	var off_wrist: Vector3 = seen.get("off", Vector3.ZERO)
	t.check(off_wrist.distance_to(off_hand) < 0.06,
			"%s: the off hand reaches the gun (%.3f m short)" % [what, off_wrist.distance_to(off_hand)])
	if arm._aim_wrist != null:
		var hand_way: Basis = seen["hand_way"]
		var twist := rad_to_deg(hand_way.get_rotation_quaternion().angle_to(aimed.get_rotation_quaternion()))
		t.check(twist < 8.0, "%s: the gun hand sits round the grip as it does aiming from the hip (%.1f deg off)" % [what, twist])
	if gun.is_sidearm:
		t.check(pose.relief_now > 0.15, "%s: a sidearm is held out in both hands (%.2f m)" % [what, pose.relief_now])
	# First person looks straight down the sight.
	var cam: Camera3D = controller.camera
	var cam_off := (sight - cam.global_position) - ahead * (sight - cam.global_position).dot(ahead)
	t.check(cam_off.length() < 0.01 and controller.sighted,
			"%s: first person looks down the sight (%.3f m off)" % [what, cam_off.length()])
	if gun.scope_lens:
		# Picture in picture: the world around the scope stays as wide as
		# plain sights, and the lens shows the view magnified by the zoom.
		var lens := gun.visual.find_child("Lens", true, false) as MeshInstance3D
		var glass := ActionPose.shown_global(gun, lens.global_transform)
		var reach := (glass.origin - cam.global_position).dot(ahead)
		var seen_deg := rad_to_deg(2.0 * atan((lens.mesh as QuadMesh).size.y * 0.5 * glass.basis.get_scale().y / reach))
		t.check(controller.scoped() and lens.material_override != null
				and absf(controller._scope_cam.fov * gun.aim_zoom() - seen_deg) < seen_deg * 0.15 + 0.5,
				"%s: the lens shows the view magnified %.1fx (%.1f of %.1f deg)" % [what, gun.aim_zoom(), controller._scope_cam.fov, seen_deg])
		t.check(seen_deg < cam.fov * 0.7 and absf(controller.aim_fov(gun) - controller.ads_fov) < 0.01,
				"%s: the scope is a picture in the middle of the view, the world around it still seen (%.0f of %.0f deg)" % [what, seen_deg, cam.fov])
		# The glass sits nearer the eye than any part of the scope and inside
		# its rim, so no edge of the tube crosses the picture.
		var mount := lens.get_parent() as Node3D
		var half_glass := (lens.mesh as QuadMesh).size.x * 0.5
		var crossed := ""
		for part in mount.find_children("*", "MeshInstance3D", true, false):
			var piece := part as MeshInstance3D
			if piece == lens or not piece.visible:
				continue
			var box := mount.global_transform.affine_inverse() * piece.global_transform * piece.get_aabb()
			var past := box.end.z > lens.position.z - 0.0001
			var round_glass := Vector2(box.get_center().x - lens.position.x, box.get_center().y - lens.position.y).length() < half_glass
			if past and round_glass:
				crossed = piece.name
		t.check(crossed == "", "%s: nothing of the scope stands between the eye and its picture (%s)" % [what, crossed])
		# The picture's zoom follows the lens as it is drawn, never where a
		# physics tick parked the hand (Caleb's jumpy 4x and 8x picture).
		var steady := controller._scope_cam.fov
		var parked := p.hand.position
		p.hand.position = Actor.HAND_REST
		controller._update_scope(gun)
		t.check(absf(controller._scope_cam.fov - steady) < 0.05,
				"%s: a parked hand leaves the scope's zoom alone (%.2f, was %.2f deg)" % [what, controller._scope_cam.fov, steady])
		p.hand.position = parked
	# The stutter: a physics tick parks the hand node at its rest; the view
	# must follow the sight as drawn, not where the tick left it.
	var shown_local: Transform3D = p.hand.get_meta("shown_local")
	p.hand.position = Actor.HAND_REST
	t.check(ActionPose.sight_shown(gun).distance_to(sight) < 0.005,
			"%s: a physics tick's parked hand does not move the sight the view follows" % what)
	await t.frames(3)
	# Third person shows the same body: only the camera moves.
	controller.view_mode = PlayerController.ViewMode.THIRD
	await t.frames(30)
	var third_local: Transform3D = p.hand.get_meta("shown_local")
	t.check(third_local.origin.distance_to(shown_local.origin) < 0.01,
			"%s: third person holds the gun exactly where first person does" % what)
	t.check(cam.global_position.distance_to(eye) > 0.5, "%s: third person, the camera is behind" % what)
	_aim(p, gun, false)
	await t.frames(40)
	t.check(pose.ads == 0.0 and not controller.sighted, "%s: letting go lowers the gun" % what)
	if gun.scope_lens:
		var glass := gun.visual.find_child("Lens", true, false) as MeshInstance3D
		t.check(not controller.scoped() and glass.material_override == null, "%s: lowered, the lens is plain glass again" % what)
	controller.queue_free()
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)


## Playtest feedback: aimed on the move, the sight bounced all over the view.
## Walking aimed (at the aiming walk, never a run), the first-person view
## must hold within a couple of centimetres of the eyes' steady line, and a
## run unaimed must not bob the view much more.
static func _check_on_the_move(t: Node) -> void:
	Look.enabled = true
	for aim: bool in [true, false]:
		var raid := Raid.new()
		t.add_child(raid)
		raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", "optic_reflex", "blade_scrap", "plate_light"])
		await t.frames(10)
		var p := raid.player
		for i in p.weapons.size():
			if p.weapons[i] is Gun:
				p.active_weapon_index = i
				break
		var controller := PlayerController.new()
		controller.setup(p)
		raid.add_child(controller)
		controller.set_physics_process(false)
		controller.view_mode = PlayerController.ViewMode.FIRST
		var cam: Camera3D = controller.camera
		var span := [Vector3.INF, -Vector3.INF]
		var seen := [0]
		# Read within the frame, after the camera is placed and while the body
		# is still where it is shown (`ShownMotion`), so only the bob is left.
		var probe := Probe.new()
		probe.read = func() -> void:
			seen[0] += 1
			if seen[0] < 50:
				return
			var aimed := p.global_basis.orthonormalized() * Basis(Vector3.RIGHT, p.cmd.pitch)
			var offset := aimed.inverse() * (cam.global_position - p.get_eye_position())
			span[0] = (span[0] as Vector3).min(offset)
			span[1] = (span[1] as Vector3).max(offset)
		raid.add_child(probe)
		for i in 150:
			p.cmd.secondary = aim
			p.cmd.move = Vector2(0, 1)
			await t.get_tree().process_frame
		probe.queue_free()
		var swing: Vector3 = (span[1] - span[0]) * 1000.0
		var speed := Vector2(p.velocity.x, p.velocity.z).length()
		if aim:
			t.check(speed < p.walk_speed * 0.7, "aimed, you walk rather than run (%.1f m/s)" % speed)
			t.check(swing.x < 30.0 and swing.y < 30.0,
					"aimed on the move, the view holds steady (%.0f mm side, %.0f mm up and down)" % [swing.x, swing.y])
		else:
			t.check(swing.x < 30.0 and swing.y < 50.0,
					"running, the view bobs only a little (%.0f mm side, %.0f mm up and down)" % [swing.x, swing.y])
		controller.queue_free()
		raid.queue_free()
		await t.frames(3)
	Look.enabled = false


## Calls `read` each frame after everything else has processed.
class Probe extends Node:
	var read := Callable()

	func _ready() -> void:
		process_priority = 10000

	func _process(_delta: float) -> void:
		if read.is_valid():
			read.call()
