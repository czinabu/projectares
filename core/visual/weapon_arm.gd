extends Node
## Makes a skinned model hold its weapon. Owned by the actor's skin, and only
## built for skins that name the bones (`grip_bone`, `arm`, ...).
##
## The game decides where a blade points: the weapon's own greybox poses show
## the side of a windup, swing or guard, and they are what a player reads to
## parry. This script makes the body agree with the blade instead of the other
## way round. It reaches the weapon arm to where the pose puts the handle,
## turns the wrist to the blade, closes the fingers, twists the shoulders into
## the attack, and brings the off hand in for two-handed weapons.
##
## Nothing here feeds back into the simulation. The actor resets its hand node
## every physics tick and no gameplay code reads it.

## Runs a callback at its place in the skeleton's modifier order.
class Hook extends SkeletonModifier3D:
	var run: Callable

	func _process_modification() -> void:
		if run.is_valid():
			run.call()


var actor: Actor
var skeleton: Skeleton3D
var look: Node

## From the grip bone to where the weapon's handle sits, in the hand's space.
var grip_offset := Vector3.ZERO
## The melee hand offsets and shoulder turns live in `ActionPose`, which
## first person reads too, so both views swing the same way.
## Where the elbows point, in the actor's space.
var elbow := Vector3(0.8, 0.8, 0.3)
var off_elbow := Vector3(-0.8, 0.8, 0.3)
## Raising the watch (`ActionPose.watch`): where the left hand comes up to,
## in front of the chest, and where that elbow points, in the actor's frame.
var watch_at := Vector3(-0.04, 1.3, -0.36)
var watch_elbow := Vector3(-0.9, 0.7, 0.0)
## The most the wrist bends to line the grip up with the blade, in radians.
var wrist_limit := 1.3
## Where the off hand holds a two-handed weapon, along its handle from the grip.
var off_hand_at := -0.16

var grip_bone := -1
## Set by the skin while drawing or putting a weapon away: a point in the
## actor's frame the weapon hand reaches for, and how far it gives in to it.
var override_point := Vector3.ZERO
var override_weight := 0.0
## Set by the skin while riding: how closed each hand (left, right) is round
## a handlebar grip.
var ride_grip := Vector2.ZERO
var reach_ik: TwoBoneIK3D
var off_ik: TwoBoneIK3D

var _wrist := -1
var _spine: Array[int] = []
var _neck := -1
## Finger bone -> closed rotation, for each hand.
var _fist := {}
var _off_fist := {}
## The line through a closed fist that a handle lies along, in wrist space.
var _grip_axis := Vector3.ZERO
var _target := Node3D.new()
var _pole := Node3D.new()
var _off_target := Node3D.new()
var _off_pole := Node3D.new()
var _weight := 0.0
var _grip_weight := 0.0
var _off_weight := 0.0
var _gun_weight := 0.0
var _watch := 0.0
var _reach := Vector3.ZERO
var _turn := Vector2.ZERO
## The actor's shared pose: what both views show the weapon hand doing.
var pose: ActionPose


## `def` is the skin's entry in `Look.SKINS`. `fist_animation` is one where
## the weapon hand is closed around a handle; its finger pose is borrowed.
func setup(def: Dictionary, fist_animation: Animation) -> void:
	grip_bone = skeleton.find_bone(def.get("grip_bone", ""))
	if grip_bone < 0:
		return
	skeleton.skeleton_updated.connect(hold_weapon)
	var arm: Array = def.get("arm", [])
	if arm.size() != 3 or arm.any(func(bone: String) -> bool: return skeleton.find_bone(bone) < 0):
		return
	_wrist = skeleton.find_bone(arm[2])
	for bone: String in def.get("spine", []):
		if skeleton.find_bone(bone) >= 0:
			_spine.append(skeleton.find_bone(bone))
	_neck = skeleton.find_bone(def.get("neck", ""))
	for node: Node3D in [_target, _pole, _off_target, _off_pole]:
		add_child(node)
		node.top_level = true

	var turn := Hook.new()
	turn.name = "BodyTurn"
	turn.run = _turn_body
	skeleton.add_child(turn)
	var gun_reach := Hook.new()
	gun_reach.name = "GunReach"
	gun_reach.run = _reach_gun
	skeleton.add_child(gun_reach)
	reach_ik = _two_bone("ArmReach", arm, _target, _pole)
	var place := Hook.new()
	place.name = "PlaceWeapon"
	place.run = _place_weapon
	skeleton.add_child(place)
	var off_arm: Array = def.get("off_arm", [])
	if off_arm.size() == 3 and off_arm.all(func(bone: String) -> bool: return skeleton.find_bone(bone) >= 0):
		off_ik = _two_bone("OffArmReach", off_arm, _off_target, _off_pole)
	var grip := Hook.new()
	grip.name = "Grip"
	grip.run = _close_grip
	skeleton.add_child(grip)
	_learn_fist(fist_animation, arm[2], def.get("off_arm", ["", "", ""])[2])


func _two_bone(ik_name: String, bones: Array, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = ik_name
	ik.setting_count = 1
	ik.set_root_bone_name(0, bones[0])
	ik.set_middle_bone_name(0, bones[1])
	ik.set_end_bone_name(0, bones[2])
	ik.influence = 0.0
	skeleton.add_child(ik)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	return ik


## Reads the closed-hand finger pose out of an animation, mirrors it for the
## off hand, and works out which way a handle runs through the fist.
func _learn_fist(animation: Animation, wrist_name: String, off_wrist_name: String) -> void:
	if animation == null:
		return
	var off_wrist := skeleton.find_bone(off_wrist_name)
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name := String(animation.track_get_path(track)).get_slice(":", 1)
		var bone := skeleton.find_bone(bone_name)
		if bone < 0 or not _is_under(bone, _wrist):
			continue
		var closed: Quaternion = animation.rotation_track_interpolate(track, 0.0)
		_fist[bone] = closed
		# The rig is mirrored left to right, so the same curl on the other
		# hand is the same rotation reflected across the body's middle.
		var twin := skeleton.find_bone(bone_name.trim_suffix(".R") + ".L") if bone_name.ends_with(".R") \
				else skeleton.find_bone(bone_name.trim_suffix(".L") + ".R")
		if twin >= 0 and off_wrist >= 0 and _is_under(twin, off_wrist):
			_off_fist[twin] = Quaternion(closed.x, -closed.y, -closed.z, closed.w)
	# A handle lies across the closed fingers, from the little finger's
	# knuckle to the first finger's, with the blade coming out past the thumb.
	var first := _fist_point(["Index2", "Index3"])
	var little := _fist_point(["Pinky2", "Pinky3"])
	if first != Vector3.INF and little != Vector3.INF and first.distance_to(little) > 0.0001:
		_grip_axis = (first - little).normalized()


func _is_under(bone: int, ancestor: int) -> bool:
	var up := skeleton.get_bone_parent(bone)
	while up >= 0:
		if up == ancestor:
			return true
		up = skeleton.get_bone_parent(up)
	return false


## Where a finger joint sits in wrist space when the fist is closed. Tries
## each name in turn, since not every rig has every joint.
func _fist_point(names: Array) -> Vector3:
	for bone: int in _fist:
		var bone_name := skeleton.get_bone_name(bone)
		if not names.any(func(n: String) -> bool: return bone_name.begins_with(n)):
			continue
		var at := Transform3D.IDENTITY
		var up := bone
		while up >= 0 and up != _wrist:
			var local := skeleton.get_bone_rest(up)
			if _fist.has(up):
				local.basis = Basis(_fist[up]).scaled(local.basis.get_scale())
			at = local * at
			up = skeleton.get_bone_parent(up)
		return at.origin
	return Vector3.INF


## The hand offset the current melee state asks for, or null when the
## animation should have the arm. The same offset moves the first-person hand.
func arm_reach(melee: MeleeWeapon) -> Variant:
	return _pose().arm_reach(melee)


## The shoulder turn and lean that go with `arm_reach`.
func body_turn(melee: MeleeWeapon) -> Vector2:
	return _pose().body_turn(melee)


func _pose() -> ActionPose:
	if pose == null or not is_instance_valid(pose):
		pose = ActionPose.of(actor)
	return pose


func _process(delta: float) -> void:
	if reach_ik == null or actor == null or not is_instance_valid(actor):
		return
	var shared := _pose()
	shared.advance(delta)
	var melee := actor.get_active_weapon() as MeleeWeapon
	var holding := melee != null and melee.visual != null and not actor.is_dead and not actor.hand_override
	var reaching := holding and shared.reach_weight > 0.0
	_weight = shared.reach_weight if holding else move_toward(_weight, 0.0, delta * 9.0)
	_grip_weight = move_toward(_grip_weight, 1.0 if holding else 0.0, delta * 8.0)
	var two_handed: bool = holding and look.is_two_handed(melee)
	_off_weight = move_toward(_off_weight, 1.0 if two_handed else 0.0, delta * 8.0)
	if reaching:
		_reach = shared.reach + melee.visual.position
	_turn = shared.turn if holding else _turn.lerp(Vector2.ZERO, 1.0 - exp(-26.0 * delta))
	var gun := actor.get_active_weapon() as Gun
	_gun_weight = shared.reload if gun != null and gun.visual != null and gun.visual.visible \
			and not actor.is_dead and not actor.hand_override else 0.0
	# The watch takes the left hand off any two-handed hold while it is up.
	_watch = shared.watch if not actor.is_dead and not actor.hand_override else 0.0

	reach_ik.influence = _weight
	var aim := Basis(Vector3.RIGHT, actor.cmd.pitch)
	_target.global_position = actor.global_transform * (Actor.HAND_REST + aim * _reach)
	if override_weight > 0.001 and not actor.hand_override:
		# Reaching for a holster takes the hand over from any hold or guard.
		var holster := actor.global_transform * override_point
		_target.global_position = holster if _weight <= 0.0 else _target.global_position.lerp(holster, override_weight)
		reach_ik.influence = maxf(_weight, override_weight)
	_pole.global_position = actor.global_transform * elbow
	if off_ik:
		off_ik.influence = maxf(_off_weight * (1.0 - _watch), _watch)
		_off_pole.global_position = actor.global_transform * off_elbow.lerp(watch_elbow, _watch)
		if _watch > 0.0:
			_off_target.global_position = actor.global_transform * watch_at


## Before the arm reaches: during a reload, move the gun hand from where the
## animation holds it by the shared reload offset, which first person shows
## the same way.
func _reach_gun() -> void:
	if _gun_weight <= 0.0 or _wrist < 0 or override_weight > 0.001 or _weight > 0.001:
		return
	var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_wrist).origin
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
	_target.global_position = wrist + aim * pose.gun_offset(false).origin
	reach_ik.influence = 1.0


## Turns the spine toward the attack before the arms reach, so they reach
## from where the shoulders have gone. The neck turns back to keep the eyes
## on the target.
func _turn_body() -> void:
	if _spine.is_empty() or _turn.length_squared() < 0.000001:
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var share := 1.0 / _spine.size()
	var step := Basis(to_skeleton * Vector3.UP, _turn.x * share) * Basis(to_skeleton * Vector3.RIGHT, _turn.y * share)
	for bone in _spine:
		_rotate_bone(bone, step)
	if _neck >= 0:
		_rotate_bone(_neck, Basis(to_skeleton * Vector3.UP, -_turn.x * 0.7) * Basis(to_skeleton * Vector3.RIGHT, -_turn.y * 0.5))


## Rotates a bone in place, in the skeleton's space.
func _rotate_bone(bone: int, by: Basis) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = by * pose.basis
	skeleton.set_bone_global_pose(bone, pose)


## Once the weapon arm has reached: bend the wrist so the grip lines up with
## the blade, put the weapon in the hand, and tell the off hand where the
## handle now is. The actor parks the hand node at its resting spot every
## physics tick, so the weapon has to be placed here, before the off arm
## reaches for it.
func _place_weapon() -> void:
	if _grip_weight <= 0.0:
		return
	var melee := actor.get_active_weapon() as MeleeWeapon
	if melee == null or melee.visual == null:
		return
	if _grip_axis != Vector3.ZERO:
		var pose := skeleton.get_bone_global_pose(_wrist)
		var now := (pose.basis.orthonormalized() * _grip_axis).normalized()
		var blade := (skeleton.global_basis.orthonormalized().inverse() * melee.visual.global_basis.y).normalized()
		var bend := Quaternion(now, blade)
		var angle := minf(bend.get_angle(), wrist_limit) * _grip_weight
		if angle > 0.001:
			pose.basis = Basis(bend.get_axis().normalized(), angle) * pose.basis
			skeleton.set_bone_global_pose(_wrist, pose)
	hold_weapon()
	var handle := melee.visual.global_transform * Vector3(0.0, off_hand_at, 0.0)
	_off_target.global_position = handle.lerp(actor.global_transform * watch_at, _watch)


## Last of all, close the fingers round the handle.
func _close_grip() -> void:
	_curl(_fist, maxf(_grip_weight, ride_grip.y))
	_curl(_off_fist, maxf(_off_weight, ride_grip.x))


func _curl(fist: Dictionary, weight: float) -> void:
	if weight <= 0.0:
		return
	for bone: int in fist:
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(fist[bone], weight))


## Puts the actor's hand node, which carries the weapon, on the model's hand.
## The controller owns the hand in first person, so this leaves it alone then.
func hold_weapon() -> void:
	if grip_bone < 0 or actor.hand_override or actor.is_dead:
		return
	var grip: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(grip_bone).origin
	var gun := actor.get_active_weapon() as Gun
	if gun != null and pose != null and is_instance_valid(pose):
		# The gun turns in the hand through a reload, as it does first person.
		actor.hand.global_basis = actor.global_basis.orthonormalized() \
				* Basis(Vector3.RIGHT, actor.cmd.pitch) * pose.gun_offset(false).basis
	var held := grip_offset
	# A blade's guard and windup poses shift it off the hand node. The arm
	# reaches for that spot instead, so take the shift back out here.
	var melee := actor.get_active_weapon() as MeleeWeapon
	if melee and melee.visual:
		held -= melee.visual.position
	actor.hand.global_position = grip + actor.hand.global_basis * held
