extends Node3D
## Your own arms and hands in first person, where the body is not drawn.
##
## A second copy of your character (same build, outfit and skin tone) hangs
## under the camera with only its torso part kept, so the arms that come into
## view are yours. It holds the clip of the weapon in hand (`aim_gun` for a
## gun, `idle_melee` for a blade) still, which shapes the fingers round the
## grip, and two-bone IK then brings the hands to wherever the controller put
## the weapon: the first-person hold that `ActionPose` moves the same way the
## third-person arm moves. The off hand rides on a gun's fore end or a
## two-handed blade's handle, and comes up to read the watch when it is
## raised, in place of the HUD's grey box forearm.
##
## Hands turn the way arms do (`_turn_hand`): each elbow is placed round
## its circle so the forearm meets the handle as the clip's fist does
## (`_elbow_for`), the forearm rolls the fist round, and the wrist only bends
## the rest, never past `wrist_limit`. A blade's fist need only lie along its
## round handle, and where the arm still falls short the blade goes with the
## fist (`_carry_in_fist`) rather than floating out of it.
##
## View only, like the rest of `Look`: no collision, nothing reads it back,
## and it is only built when there is a screen and a skin with the bones.

const WeaponArm := preload("res://core/visual/weapon_arm.gd")

var look: Node
var actor: Actor
var camera: Camera3D

## Where the copy's head bone sits in the camera's space: just behind the
## eye, so the torso stays out of view and the shoulders are where yours are.
var head_at := Vector3(0.0, -0.02, 0.06)
## The shoulders are brought this far forward of the copy's chest (camera
## space), as a gun's stock pulls them in to the cheek: the chest stays out
## of view behind the eye and the arms come in from the edges of the view,
## long enough to hold a rifle's fore end.
var shoulder_shift := Vector3(0.0, 0.0, -0.2)
## Where the elbows point, in the camera's space.
var elbow := Vector3(0.7, -0.9, 0.2)
var off_elbow := Vector3(-0.7, -0.9, 0.2)
var elbow_cocked := Vector3(0.8, 0.2, 0.3)
## Raising the watch: where the left wrist comes up to, in the camera's
## space, at the reference field of view.
var watch_at := Vector3(-0.1, -0.2, -0.32)
## A hand closes round a handle the way an arm would: the forearm rolls
## (from the elbow, as yours does) up to `fore_roll_limit` to bring the fist
## round, taking `fore_twist` of it while the wrist takes the rest, and the
## wrist then bends the fist onto the handle's line. The fist may turn about
## a round handle, so only that line has to match.
var fore_twist := 0.65
var fore_roll_limit := deg_to_rad(110.0)
## How far a wrist may bend off its forearm at most.
var wrist_limit := deg_to_rad(50.0)
## How far a hand on a fore end may turn about its palm to wrap the barrel.
var wrap_limit := deg_to_rad(70.0)
## Where the elbow goes is picked round its circle so the forearm meets the
## handle at the angle the clip's fist holds it; this much (radians of score
## per unit of turn away) keeps it near the usual pole, so it never flips up.
var elbow_habit := 0.6
## A sidearm is held with the off hand cupped under the grip: its clip offset
## from the weapon hand is shrunk by this much.
var sidearm_support := 0.35
## Where the off wrist sits from a gun's "ForeGrip" marker, in the gun's
## space (x right, y up, z back), so the palm comes up under the fore end.
var fore_wrist := Vector3(-0.03, -0.07, 0.06)
## How a blade is turned in the hand at rest (see `MeleeWeapon.REST_POSE`):
## the clip holds it that way, so poses are measured from it.
var blade_rest := Basis(Vector3.RIGHT, MeleeWeapon.REST_POSE)

var model: Node3D
var skeleton: Skeleton3D
var _player: AnimationPlayer
var _anims := {}
var _clip := ""
var _wrist := -1
var _off_wrist := -1
var _shoulders: Array[int] = []
var _grip := -1
## The finger bones that close round a handle (from the grip bone out).
var _fingers: Array[int] = []
var _ik: TwoBoneIK3D
var _off_ik: TwoBoneIK3D
var _target := Node3D.new()
var _pole := Node3D.new()
var _off_target := Node3D.new()
var _off_pole := Node3D.new()
## The wrist turns the hooks give the hands this frame, in the world.
var _wrist_turn := Basis.IDENTITY
var _off_turn := Basis.IDENTITY
var _off_weight := 0.0
## How each clip wrist sits on its forearm, measured each frame before the reach.
var _rel := Basis.IDENTITY
var _off_rel := Basis.IDENTITY
var _fore := -1
var _off_fore := -1
## The handle's line in each hand (in the clip's hand frame) and in the
## world, or zero where the whole hand turns as the clip holds it.
var _axis_hand := Vector3.ZERO
var _axis_world := Vector3.ZERO
var _off_axis_hand := Vector3.ZERO
var _off_axis_world := Vector3.ZERO
## For a hand on a fore end, the barrel's line too (hand frame and world),
## which the fingers wrap across once the palm is on the gun.
var _off_wrap_hand := Vector3.ZERO
var _off_wrap_world := Vector3.ZERO
## How the weapon hand ended up on the weapon last frame (in the weapon's
## frame), so this frame's reach puts the fist on the grip, and the weapon
## it was for.
var _hand_on_weapon := Basis.IDENTITY
var _hand_for: Object
var _watch := 0.0
## The watch on the copy's left wrist.
var _worn_watch: Node3D


## Builds the copy. False when there is no skin with arms to copy.
func build(skin_name: String, appearance: Dictionary) -> bool:
	var def: Dictionary = look.SKINS.get(skin_name, look.SKINS[look.DEFAULT_SKIN])
	var arm: Array = def.get("arm", [])
	var off_arm: Array = def.get("off_arm", [])
	if arm.size() != 3 or off_arm.size() != 3:
		return false
	var built: Dictionary = look.character(skin_name, appearance, String(actor.name))
	if built.is_empty():
		return false
	model = built["model"]
	add_child(model)
	# Pack models face +Z; the camera looks down -Z.
	model.rotation.y = PI
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return false
	_wrist = skeleton.find_bone(arm[2])
	_off_wrist = skeleton.find_bone(off_arm[2])
	_fore = skeleton.find_bone(arm[1])
	_off_fore = skeleton.find_bone(off_arm[1])
	_grip = skeleton.find_bone(def.get("grip_bone", ""))
	var finger := _grip
	while finger >= 0:
		_fingers.append(finger)
		var next := skeleton.get_bone_children(finger)
		finger = next[0] if next.size() > 0 else -1
	for bone: String in [arm[0], off_arm[0]]:
		_shoulders.append(skeleton.find_bone(bone))
	if _wrist < 0 or _off_wrist < 0 or _grip < 0:
		return false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Only the torso part carries the arms; the rest would only get in
		# the way of the view (or of the near plane).
		var slot: String = mesh.get_meta("slot", "body")
		if slot != "body":
			mesh.visible = false
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player:
		for key: String in ["aim_gun", "idle_melee", "idle"]:
			var wanted: String = def.get("anims", {}).get(key, "")
			for found in _player.get_animation_list():
				if found == wanted or found.ends_with("/" + wanted):
					_anims[key] = found
		_hold_clip("idle")
	look.stand_model(self, model, def["height"])
	var head := skeleton.find_bone("Head")
	if head < 0:
		head = skeleton.find_bone(def.get("neck", ""))
	if head >= 0:
		var at := global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(head).origin)
		model.position += head_at - at
	for node: Node3D in [_target, _pole, _off_target, _off_pole]:
		add_child(node)
		node.top_level = true
	var measure := WeaponArm.Hook.new()
	measure.name = "Measure"
	measure.run = _measure
	skeleton.add_child(measure)
	_ik = _two_bone("ArmReach", arm, _target, _pole)
	_off_ik = _two_bone("OffArmReach", off_arm, _off_target, _off_pole)
	var wrists := WeaponArm.Hook.new()
	wrists.name = "Wrists"
	wrists.run = _turn_wrists
	skeleton.add_child(wrists)
	var attach := BoneAttachment3D.new()
	attach.name = "WornWatch"
	attach.bone_name = off_arm[2]
	skeleton.add_child(attach)
	_worn_watch = Hud.Wrist._watch()
	var s := skeleton.global_basis.get_scale()
	_worn_watch.scale = Vector3(1.0 / maxf(s.x, 0.001), 1.0 / maxf(s.y, 0.001), 1.0 / maxf(s.z, 0.001))
	attach.add_child(_worn_watch)
	return true


func _two_bone(ik_name: String, bones: Array, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = ik_name
	ik.setting_count = 1
	ik.set_root_bone_name(0, bones[0])
	ik.set_middle_bone_name(0, bones[1])
	ik.set_end_bone_name(0, bones[2])
	ik.influence = 1.0
	skeleton.add_child(ik)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	return ik


## Holds the first frame of a clip still: the fingers' grip and the arms'
## starting pose for the IK.
func _hold_clip(key: String) -> void:
	if _player == null or not _anims.has(key) or _clip == key:
		return
	_clip = key
	_player.play(_anims[key], 0.0)
	_player.seek(0.0, true)
	_player.pause()


## The weapon whose model is in the hand now, or null.
func held_visual() -> Node3D:
	var weapon := actor.get_active_weapon()
	if weapon != null and weapon.visual != null and weapon.visual.visible:
		return weapon.visual
	return null


## Called by the controller each frame after it has placed the hand.
## `shown` is whether first person is being drawn at all; `watch` how far
## the watch is raised (0..1); `toy` true while a toy vehicle is in the hand.
func update(shown: bool, watch: float, toy: bool) -> void:
	var weapon := actor.get_active_weapon()
	var held := held_visual()
	visible = shown and (held != null or toy or watch > 0.0)
	_watch = watch
	if not visible:
		return
	if weapon is MeleeWeapon:
		_hold_clip("idle_melee")
	elif held != null:
		_hold_clip("aim_gun")
	else:
		_hold_clip("idle")
	var two_handed: bool = held != null and (weapon is Gun or look.is_two_handed(weapon))
	_off_weight = 1.0 if two_handed else 0.0
	_ik.influence = 1.0 if held != null or toy else 0.0
	_off_ik.influence = maxf(_off_weight, watch)
	_worn_watch.visible = true


## Before the arms reach: where each hand goes this frame. The clip's hands
## are moved as one with the weapon, from how the clip holds it (weapon
## straight ahead) to how the weapon is held now.
func _measure() -> void:
	var cam := camera.global_transform
	var to_world := skeleton.global_transform
	var shift := to_world.basis.inverse() * (cam.basis * shoulder_shift)
	for bone in _shoulders:
		var at := skeleton.get_bone_global_pose(bone)
		at.origin += shift
		skeleton.set_bone_global_pose(bone, at)
	_rel = _local_turn(_fore, _wrist)
	_off_rel = _local_turn(_off_fore, _off_wrist)
	var anchor := actor.hand.global_transform.orthonormalized()
	var rest := cam.basis.orthonormalized()
	var held := held_visual()
	if held != null:
		anchor = held.global_transform.orthonormalized()
		if actor.get_active_weapon() is MeleeWeapon:
			rest = rest * blade_rest
	var turn := anchor.basis * rest.inverse()
	var weapon := actor.get_active_weapon()
	var basis_world := to_world.basis.orthonormalized()
	var wrist := to_world * skeleton.get_bone_global_pose(_wrist).origin
	var grip := _fist_point()
	var wrist_basis := basis_world * skeleton.get_bone_global_pose(_wrist).basis.orthonormalized()
	_wrist_turn = turn * wrist_basis
	# A blade's handle is round: the fist only has to lie along it.
	_axis_hand = Vector3.ZERO
	if weapon is MeleeWeapon and held != null:
		_axis_hand = wrist_basis.inverse() * (rest * Vector3.UP)
		_axis_world = anchor.basis * Vector3.UP
	if _hand_for != held:
		_hand_for = held
		_hand_on_weapon = anchor.basis.inverse() * _wrist_turn
	var hand := (anchor.basis * _hand_on_weapon).orthonormalized()
	var new_wrist := anchor.origin - hand * (wrist_basis.inverse() * (grip - wrist))
	_target.global_position = new_wrist
	# The elbow rides high with the arm cocked for a windup, as third person.
	var raise := ActionPose.of(actor).elbow_raise if actor.get_active_weapon() is MeleeWeapon else 0.0
	_pole.global_position = _elbow_for(0, _fore, _wrist, new_wrist, _rel, _axis_hand, _axis_world, cam * elbow.lerp(elbow_cocked, raise))

	var off := to_world * skeleton.get_bone_global_pose(_off_wrist).origin
	var off_basis := basis_world * skeleton.get_bone_global_pose(_off_wrist).basis.orthonormalized()
	var off_at := new_wrist + turn * (off - wrist)
	var fore := held.get_node_or_null("ForeGrip") as Node3D if held != null else null
	if weapon is Gun and (weapon as Gun).is_sidearm:
		off_at = new_wrist + turn * ((off - wrist) * sidearm_support)
	elif weapon is Gun and fore != null:
		# The palm under the fore end: the wrist sits a hand's width below
		# and behind it.
		off_at = fore.global_position + anchor.basis * fore_wrist
	elif weapon is MeleeWeapon and held != null:
		off_at = held.global_transform * Vector3(0.0, -0.16, 0.0)
	_off_turn = turn * off_basis
	# The off hand cups a fore end, palm against the gun's underside, or
	# wraps a long handle: only that line has to match.
	_off_axis_hand = Vector3.ZERO
	var off_line := Vector3.ZERO
	if weapon is Gun and fore != null and not (weapon as Gun).is_sidearm:
		off_line = Vector3.UP
	elif weapon is MeleeWeapon and held != null:
		off_line = Vector3.UP
	_off_wrap_hand = Vector3.ZERO
	if off_line != Vector3.ZERO and _watch <= 0.0:
		_off_axis_hand = off_basis.inverse() * (rest * off_line)
		_off_axis_world = anchor.basis * off_line
		if weapon is Gun:
			_off_wrap_hand = off_basis.inverse() * (rest * Vector3.BACK)
			_off_wrap_world = anchor.basis * Vector3.BACK
	if _watch > 0.0:
		var k := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(80.0) * 0.5)
		var up := cam * Vector3(watch_at.x * k, watch_at.y * k, watch_at.z)
		off_at = up if _off_weight <= 0.0 else off_at.lerp(up, _watch)
		# Turn the forearm so the watch face looks back at the eye.
		var face := (off_basis * Vector3.UP).normalized()
		var to_eye := (cam.origin - up).normalized()
		var swing := Quaternion(face, to_eye)
		_off_turn = (off_basis if _off_weight <= 0.0 else _off_turn).slerp(Basis(swing) * off_basis, _watch)
	_off_target.global_position = off_at
	_off_pole.global_position = _elbow_for(1, _off_fore, _off_wrist, off_at, _off_rel, _off_axis_hand, _off_axis_world, cam * off_elbow)


## A pole for an arm reaching to `at` (world) that puts its elbow where the
## forearm meets the handle line `line` at the angle the clip's hand keeps it
## (`line_hand` in the hand, carried by `rel`): out of all the elbows on the
## circle the arm allows, the best fit, held near the usual pole `usual`.
func _elbow_for(side: int, fore: int, wrist: int, at: Vector3, rel: Basis, line_hand: Vector3, line: Vector3, usual: Vector3) -> Vector3:
	if line_hand == Vector3.ZERO:
		return usual
	var to_world := skeleton.global_transform
	var shoulder := to_world * skeleton.get_bone_global_pose(_shoulders[side]).origin
	var elbow_at := to_world * skeleton.get_bone_global_pose(fore).origin
	var wrist_at := to_world * skeleton.get_bone_global_pose(wrist).origin
	var upper := shoulder.distance_to(elbow_at)
	var lower := elbow_at.distance_to(wrist_at)
	var reach := shoulder.distance_to(at)
	if reach >= upper + lower - 0.005 or reach < 0.01:
		return usual
	var way := (at - shoulder) / reach
	var a := (upper * upper - lower * lower + reach * reach) / (2.0 * reach)
	var r := sqrt(maxf(upper * upper - a * a, 0.0))
	var centre := shoulder + way * a
	var x := (usual - centre)
	x = (x - way * x.dot(way)).normalized()
	if x == Vector3.ZERO:
		return usual
	var y := way.cross(x)
	var keep := acos(clampf((rel * line_hand).normalized().y, -1.0, 1.0))
	var want := line.normalized()
	var best := 0.0
	var best_score := INF
	for i in 36:
		var t := (float(i) / 36.0 - 0.5) * TAU
		var e := centre + (x * cos(t) + y * sin(t)) * r
		var score := absf((at - e).normalized().angle_to(want) - keep) + elbow_habit * absf(t)
		if score < best_score:
			best_score = score
			best = t
	return centre + (x * cos(best) + y * sin(best)) * (r + 0.3)


## After the arms reach: turn each wrist so the hand meets the weapon the way
## the clip holds it.
func _turn_wrists() -> void:
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	if _ik.influence > 0.0:
		var hand := _turn_hand(_fore, _wrist, _rel, to_skeleton * _wrist_turn, _axis_hand, to_skeleton * _axis_world)
		var held := held_visual()
		if held != null and _axis_hand != Vector3.ZERO and is_visible_in_tree():
			_carry_in_fist(held, hand)
		if held != null:
			var world := skeleton.global_basis.orthonormalized() * hand
			_hand_on_weapon = held.global_basis.orthonormalized().inverse() * world
	if _off_ik.influence > 0.0:
		var off_hand := _turn_hand(_off_fore, _off_wrist, _off_rel, to_skeleton * _off_turn, _off_axis_hand, to_skeleton * _off_axis_world)
		if _off_wrap_hand != Vector3.ZERO and _off_axis_hand != Vector3.ZERO:
			# Palm on the gun; now turn it about the palm so the fingers
			# wrap across the barrel as the clip's do.
			var palm := (to_skeleton * _off_axis_world).normalized()
			var have := off_hand * _off_wrap_hand
			var want := to_skeleton * _off_wrap_world
			have -= palm * have.dot(palm)
			want -= palm * want.dot(palm)
			if have.length() > 0.1 and want.length() > 0.1:
				var spin := clampf(have.signed_angle_to(want, palm), -wrap_limit, wrap_limit)
				_set_turn(_off_wrist, Basis(palm, spin) * off_hand)


## Where the arm cannot quite bring the fist onto a blade's handle, the blade
## goes where the fist is rather than floating free of it: the hand node is
## turned and moved so the handle lies along the fist, through the grip.
func _carry_in_fist(held: Node3D, hand: Basis) -> void:
	var to_world := skeleton.global_transform
	var fist := (to_world.basis.orthonormalized() * hand * _axis_hand).normalized()
	var line := (held.global_basis * Vector3.UP).normalized()
	var grip := _fist_point()
	var turn := Basis(Quaternion(line, fist)) if line.angle_to(fist) > 0.001 else Basis.IDENTITY
	var shown := Transform3D(turn * held.global_basis, grip)
	var on_hand := actor.hand.global_transform.affine_inverse() * held.global_transform
	actor.hand.global_transform = shown * on_hand.affine_inverse()


## Turns a hand the way an arm does and returns its new turn (skeleton
## space). With no handle line (`line_hand` zero) the hand takes `wanted`
## outright. Otherwise the fist is brought onto the line `line` from where the
## forearm carries it (`rel`, as the clip holds it): the forearm rolls it
## round first, and the wrist bends the rest.
func _turn_hand(fore: int, wrist: int, rel: Basis, wanted: Basis, line_hand: Vector3, line: Vector3) -> Basis:
	if line_hand == Vector3.ZERO:
		_set_turn(wrist, wanted)
		return wanted.orthonormalized()
	var fore_pose := skeleton.get_bone_global_pose(fore)
	var fore_basis := fore_pose.basis.orthonormalized()
	var along := (fore_basis * Vector3.UP).normalized()
	var want := line.normalized()
	var have := (fore_basis * rel * line_hand).normalized()
	# The roll about the forearm that best brings the fist round.
	var have_flat := have - along * have.dot(along)
	var want_flat := want - along * want.dot(along)
	var roll := 0.0
	if have_flat.length() > 0.15 and want_flat.length() > 0.15:
		roll = clampf(have_flat.signed_angle_to(want_flat, along), -fore_roll_limit, fore_roll_limit)
	fore_basis = fore_basis * Basis(Vector3.UP, roll * fore_twist)
	fore_pose.basis = fore_basis.scaled(fore_pose.basis.get_scale())
	skeleton.set_bone_global_pose(fore, fore_pose)
	var hand := Basis(along, roll * (1.0 - fore_twist)) * (fore_basis * rel).orthonormalized()
	# The wrist bends the fist onto the line.
	have = (hand * line_hand).normalized()
	var bend := have.angle_to(want)
	if bend > 0.001:
		var axis := have.cross(want)
		if axis.length_squared() < 1e-8:
			axis = along.cross(have)
		hand = Basis(axis.normalized(), minf(bend, wrist_limit)) * hand
	_set_turn(wrist, hand)
	return hand.orthonormalized()


## The middle of the closed fist (world), where a handle passes through:
## among the curled finger joints and the palm below the knuckles, not on
## the knuckle itself.
func _fist_point() -> Vector3:
	var to_world := skeleton.global_transform
	var knuckle := skeleton.get_bone_global_pose(_grip).origin
	var palm := skeleton.get_bone_global_pose(_wrist).origin.lerp(knuckle, 0.6)
	var sum := palm
	for bone in _fingers:
		sum += skeleton.get_bone_global_pose(bone).origin
	return to_world * (sum / float(_fingers.size() + 1))


## How bone `child` is turned from bone `parent`, in the current pose.
func _local_turn(parent: int, child: int) -> Basis:
	var a := skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	var b := skeleton.get_bone_global_pose(child).basis.orthonormalized()
	return a.inverse() * b


func _set_turn(bone: int, turn: Basis) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = turn.orthonormalized().scaled(pose.basis.get_scale())
	skeleton.set_bone_global_pose(bone, pose)
