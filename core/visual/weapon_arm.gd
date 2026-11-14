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
## The melee hand offsets and shoulder turns live in `ActionPose`. Both
## views look at this same arm, so they swing the same way.
## Where the elbows point, in the actor's space.
var elbow := Vector3(0.8, 0.8, 0.3)
var off_elbow := Vector3(-0.8, 0.8, 0.3)
## Raising the watch (`ActionPose.watch`): where the left wrist comes up to,
## from the eyes along the aim (metres right, up and ahead, pitch clamped to
## `watch_pitch`), so it comes up into the line of sight in both views, and
## where that elbow points, in the actor's frame. The elbow stays out to the
## side and low, so the forearm lies across in front of the chest.
var watch_from_eyes := Vector3(-0.1, -0.1, -0.37)
var watch_pitch := Vector2(-0.7, 0.5)
var watch_elbow := Vector3(-1.0, 1.2, -0.15)
## With the watch up the forearm rolls so the back of the wrist, where the
## watch face is (`Hud.Wrist.FACE_AXIS` in the wrist bone), looks at the
## eyes, and the hand stays straight on from the forearm.
## The most the wrist bends to line the grip up with the blade, in radians.
var wrist_limit := 1.3
## The most the wrist bends from the aim clip's hold to lie along a gun's
## own pistol grip, in radians.
var grip_bend_limit := 0.6
## Where the off hand holds a two-handed weapon, along its handle from the
## grip, where the model does not say (`Look._fit_hands`).
var off_hand_at := -0.16
## A two-handed weapon at rest is carried across the body: where the weapon
## hand's wrist goes (actor frame) and which way the haft runs up from it,
## so the off hand reaches it too.
var carry_point := Vector3(0.14, 1.1, -0.22)
var carry_up := Vector3(-0.6, 0.75, -0.3)
## How far into that carry the arms are.
var _carry := 0.0
## Where the off fist should close on a two-handed blade's handle this
## frame (INF when it holds none), and what its reach was left short last
## frame, in the actor's frame.
var _off_spot := Vector3.INF
var _off_fix := Vector3.ZERO

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
var _forearm := -1
var _upper := -1
var _off_wrist := -1
var _off_upper := -1
var _off_forearm := -1
## The wrist's turn in the skeleton's space while a gun is raised to aim
## (the `aim_gun` clip), and the forearm's while a blade is held ready
## (`idle_melee`). Where the arm hangs differently, the weapon turns with it
## by the difference, so a gun held low points down with the hand instead of
## staying level with the aim. Null when the clips are missing.
var _aim_wrist: Variant = null
## The off wrist's turn in the same clip, where it holds the fore end: the
## off hand takes it, turned with the aim, while aiming down sights.
var _aim_off_wrist: Variant = null
## How far in front of the eyes the sight goes this frame: the gun's relief
## (`ActionPose.relief_for`), drawn in to what the arm can reach.
var _relief_now := 0.0
## The shoulder turn and lean of the aiming stance (`ActionPose.ads_stance`),
## eased by `_ads`, on top of any melee turn.
var _ads_turn := Vector2.ZERO
## How far the gun arm may reach while aiming, as a share of its length,
## so it never locks out straight.
var ads_reach := 0.97
## How far ahead of the gun hand's wrist the off wrist comes to wrap round
## a sidearm's grip, for working out whether the off arm can reach it.
var sidearm_wrap := 0.02
var _ready_forearm: Variant = null
var _spine: Array[int] = []
var _neck := -1
## Finger bone -> closed rotation, for each hand.
var _fist := {}
var _off_fist := {}
## The line through a closed fist that a handle lies along, in wrist space.
var _grip_axis := Vector3.ZERO
## Where a handle runs through the closed fist, in wrist space: the middle
## of the curled fingers, level with the first finger (what goes on a gun's
## trigger), and the same for the off hand (the middle of its fist).
var _hold_point: Variant = null
var _off_hold_point: Variant = null
## The middle of the weapon hand's closed fist, where a blade's handle runs.
var _ring_point: Variant = null
## The off hand's own axes in its wrist's space: from the wrist out along
## the fingers, and out of the palm. Null when the rig lacks the joints.
var _off_fingers: Variant = null
var _off_palm: Variant = null
## How far the off hand is on a gun: fully while aiming down sights or with
## the gun raised (`ActionPose.low` down), off while it hangs low or reloads.
var _support := 0.0
var _target := Node3D.new()
var _pole := Node3D.new()
var _off_target := Node3D.new()
var _off_pole := Node3D.new()
var _weight := 0.0
var _grip_weight := 0.0
var _off_weight := 0.0
var _gun_weight := 0.0
var _watch := 0.0
## How far a gun is up at the eye (`ActionPose.ads`), while it is shown.
var _ads := 0.0
## What the arm's reach left between the sight and its target last frame,
## in the actor's frame, added to the next reach so the sight settles on
## the eye line (the hand turns a little as the arm reaches).
var _ads_fix := Vector3.ZERO
## Where the off hand holds a long gun with no fore grip marker, and the
## off elbow's pole while aiming down sights (actor frame).
var ads_fore := Vector3(0.0, -0.07, -0.3)
var ads_off_elbow := Vector3(-0.6, 0.6, -0.1)
var _reach := Vector3.ZERO
var _turn := Vector2.ZERO
## How far a gun is in its carry on the move (`ActionPose.carry`), where
## the carry puts the gun hand's wrist this frame and how it turns the gun
## (both in the world, worked out from the chest once the body is posed).
var _gun_carry := 0.0
var _carry_wrist := Vector3.ZERO
var _carry_basis := Basis.IDENTITY
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
	_forearm = skeleton.find_bone(arm[1])
	_upper = skeleton.find_bone(arm[0])
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
		_off_forearm = skeleton.find_bone(off_arm[1])
		_off_wrist = skeleton.find_bone(off_arm[2])
		_off_upper = skeleton.find_bone(off_arm[0])
		var steady := Hook.new()
		steady.name = "SteadyHand"
		steady.run = _turn_off_hand
		skeleton.add_child(steady)
		var face := Hook.new()
		face.name = "WatchFace"
		face.run = _face_watch
		skeleton.add_child(face)
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


## Learns how the arm is turned when a weapon is held the way its model is
## built to be held: a gun aimed (`aim`), a blade ready (`ready`).
func calibrate(aim: Animation, ready: Animation) -> void:
	if _wrist >= 0 and aim != null:
		_aim_wrist = clip_basis(skeleton, aim, _wrist)
	if _off_wrist >= 0 and aim != null:
		_aim_off_wrist = clip_basis(skeleton, aim, _off_wrist)
	if _forearm >= 0 and ready != null:
		_ready_forearm = clip_basis(skeleton, ready, _forearm)


## A bone's turn in skeleton space at the start of `clip`, from its rotation
## tracks (rest where a bone has none).
static func clip_basis(skel: Skeleton3D, clip: Animation, bone: int) -> Basis:
	var turns := {}
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var found := skel.find_bone(String(clip.track_get_path(track)).get_slice(":", 1))
		if found >= 0:
			turns[found] = clip.rotation_track_interpolate(track, 0.0)
	var out := Basis.IDENTITY
	var up := bone
	while up >= 0:
		var local: Basis = Basis(turns[up]) if turns.has(up) else skel.get_bone_rest(up).basis.orthonormalized()
		out = local * out
		up = skel.get_bone_parent(up)
	return out


## The weapon hand's turn in the world when it follows `bone` from how the
## bone sits in `calibrated` (where the weapon faces straight ahead).
func _follow_turn(bone: int, calibrated: Basis) -> Basis:
	var to_world := skeleton.global_basis.orthonormalized()
	var now := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var ahead := actor.global_basis.orthonormalized()
	return (to_world * now * calibrated.inverse() * to_world.inverse() * ahead).orthonormalized()


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
	var ring := _fist_ring(_fist, _wrist)
	if ring != Vector3.INF:
		_ring_point = ring
	if ring != Vector3.INF and _grip_axis != Vector3.ZERO:
		var index := _fist_point(["Index2", "Index1"])
		_hold_point = ring + _grip_axis * (index - ring).dot(_grip_axis) if index != Vector3.INF else ring
	if off_wrist >= 0:
		var off_ring := _fist_ring(_off_fist, off_wrist)
		if off_ring != Vector3.INF:
			_off_hold_point = off_ring
			var knuckle := _fist_point(["Middle1"], _off_fist, off_wrist)
			if knuckle != Vector3.INF and knuckle.length() > 0.001:
				var fingers := knuckle.normalized()
				var palm := (off_ring - knuckle) - fingers * (off_ring - knuckle).dot(fingers)
				if palm.length() > 0.001:
					_off_fingers = fingers
					_off_palm = palm.normalized()


## The middle of a closed fist's ring of fingers, in wrist space: the
## middle finger's three joints, closed.
func _fist_ring(fist: Dictionary, wrist: int) -> Vector3:
	var sum := Vector3.ZERO
	var found := 0
	for joint: String in ["Middle1", "Middle2", "Middle3"]:
		var at := _fist_point([joint], fist, wrist)
		if at != Vector3.INF:
			sum += at
			found += 1
	return sum / found if found == 3 else Vector3.INF


func _is_under(bone: int, ancestor: int) -> bool:
	var up := skeleton.get_bone_parent(bone)
	while up >= 0:
		if up == ancestor:
			return true
		up = skeleton.get_bone_parent(up)
	return false


## Where a finger joint sits in wrist space when the fist is closed. Tries
## each name in turn, since not every rig has every joint.
func _fist_point(names: Array, fist: Dictionary = {}, wrist := -1) -> Vector3:
	if fist.is_empty():
		fist = _fist
		wrist = _wrist
	for bone: int in fist:
		var bone_name := skeleton.get_bone_name(bone)
		if not names.any(func(n: String) -> bool: return bone_name.begins_with(n)):
			continue
		var at := Transform3D.IDENTITY
		var up := bone
		while up >= 0 and up != wrist:
			var local := skeleton.get_bone_rest(up)
			if fist.has(up):
				local.basis = Basis(fist[up]).scaled(local.basis.get_scale())
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
	var holding := melee != null and melee.visual != null and not actor.is_dead
	var reaching := holding and shared.reach_weight > 0.0
	_weight = shared.reach_weight if holding else move_toward(_weight, 0.0, delta * 9.0)
	_grip_weight = move_toward(_grip_weight, 1.0 if holding else 0.0, delta * 8.0)
	var two_handed: bool = holding and look.is_two_handed(melee)
	_off_weight = move_toward(_off_weight, 1.0 if two_handed else 0.0, delta * 8.0)
	_carry = move_toward(_carry, 1.0 if two_handed else 0.0, delta * 6.0)
	if reaching:
		_reach = shared.reach + melee.visual.position
	_turn = shared.turn if holding else _turn.lerp(Vector2.ZERO, 1.0 - exp(-26.0 * delta))
	var gun := actor.get_active_weapon() as Gun
	_gun_weight = shared.reload if gun != null and gun.visual != null and gun.visual.visible \
			and not actor.is_dead else 0.0
	# The watch takes the left hand off any two-handed hold while it is up.
	_watch = shared.watch if not actor.is_dead else 0.0
	_ads = shared.ads if gun != null and gun.visual != null and gun.visual.visible \
			and not actor.is_dead and override_weight <= 0.001 else 0.0
	if _ads <= 0.0:
		_ads_fix = Vector3.ZERO
	var raised := 0.0
	_gun_carry = 0.0
	if gun != null and gun.visual != null and gun.visual.visible and not actor.is_dead and override_weight <= 0.001:
		raised = (1.0 - shared.low) * (1.0 - shared.reload)
		_gun_carry = shared.carry if _weight <= 0.001 else 0.0
		raised = lerpf(raised, shared.carry_support(gun), _gun_carry)
	_support = maxf(_ads, raised)
	_ads_turn = shared.ads_stance(gun) * _ads if _ads > 0.0 else Vector2.ZERO

	reach_ik.influence = _weight
	var aim := Basis(Vector3.RIGHT, actor.cmd.pitch)
	_target.global_position = actor.global_transform * (Actor.HAND_REST + aim * _reach)
	# At rest a two-handed weapon is carried across the body; an attack or
	# guard takes the hand from there.
	var carried := _carry * (1.0 - _weight)
	if carried > 0.0:
		var carry := actor.global_transform * carry_point
		_target.global_position = carry if _weight <= 0.0 else _target.global_position.lerp(carry, carried)
		reach_ik.influence = minf(_weight + carried, 1.0)
	if override_weight > 0.001:
		# Reaching for a holster takes the hand over from any hold or guard.
		var holster := actor.global_transform * override_point
		var held_by := reach_ik.influence
		_target.global_position = holster if held_by <= 0.0 else _target.global_position.lerp(holster, override_weight)
		reach_ik.influence = maxf(held_by, override_weight)
	# Cocked for a windup the elbow rides high; thrown through, it drops.
	_pole.global_position = actor.global_transform * (elbow.lerp(shared.elbow_pole(), _weight) if holding else elbow)
	if off_ik:
		off_ik.influence = maxf(maxf(_off_weight, _support) * (1.0 - _watch), _watch)
		var off_pole := off_elbow.lerp(ads_off_elbow, _support) if _off_weight <= 0.0 else off_elbow
		_off_pole.global_position = actor.global_transform * off_pole.lerp(watch_elbow, _watch)
		if _watch > 0.0:
			_off_target.global_position = watch_point()


## Where the raised watch's wrist goes, in the world: below and ahead of
## the eyes along the aim, so you look straight at it.
func watch_point() -> Vector3:
	var pitch := clampf(actor.cmd.pitch, watch_pitch.x, watch_pitch.y)
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, pitch)
	return actor.get_eye_position() + aim * watch_from_eyes


## Once the off arm has reached for the watch: roll the forearm so the watch
## face looks back at the eyes, and keep the hand straight on from it. The
## pose is only shown; nothing reads it back.
func _face_watch() -> void:
	if _watch <= 0.0 or _off_forearm < 0 or _off_wrist < 0:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var eye := to_skeleton * actor.get_eye_position()
	var fore := skeleton.get_bone_global_pose(_off_forearm)
	var wrist := skeleton.get_bone_global_pose(_off_wrist)
	var along := (wrist.origin - fore.origin).normalized()
	if along == Vector3.ZERO:
		return
	# The hand as it sits straight on from the forearm (its rest turn).
	var rest := skeleton.get_bone_rest(_off_wrist).basis.orthonormalized()
	# The forearm rolls about its own length to turn the face to the eyes.
	var face_now := (fore.basis.orthonormalized() * rest * Hud.Wrist.FACE_AXIS).normalized()
	var to_eye := eye - wrist.origin
	to_eye -= along * to_eye.dot(along)
	face_now -= along * face_now.dot(along)
	if to_eye.length() > 0.001 and face_now.length() > 0.001:
		var roll := face_now.signed_angle_to(to_eye, along) * _watch
		fore.basis = Basis(along, roll) * fore.basis
		skeleton.set_bone_global_pose(_off_forearm, fore)
	var straight := fore.basis.orthonormalized() * rest
	var hand := wrist.basis.orthonormalized().slerp(straight, _watch)
	skeleton.set_bone_global_pose(_off_wrist, Transform3D(hand, skeleton.get_bone_global_pose(_off_wrist).origin))


## Before the arm reaches: during a reload, move the gun hand from where the
## animation holds it by the shared reload offset; aiming down sights, move
## it so the gun's sight comes up onto the line of the eyes.
func _reach_gun() -> void:
	if _gun_carry > 0.0 and _wrist >= 0 and _weight <= 0.001:
		_reach_carry()
	if _ads > 0.0 and _wrist >= 0 and _weight <= 0.001:
		_reach_sight()
		return
	if _gun_carry > 0.0 and _wrist >= 0 and _weight <= 0.001:
		return
	if _gun_weight <= 0.0 or _wrist < 0 or override_weight > 0.001 or _weight > 0.001:
		return
	var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_wrist).origin
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
	_target.global_position = wrist + aim * pose.gun_offset().origin
	reach_ik.influence = 1.0


## Carrying a gun on the move: the wrist goes where the carry puts it
## (`ActionPose.carry_point`, from the chest), eased in by `_gun_carry`, and
## the gun's turn for this frame is worked out for `hold_weapon`.
func _reach_carry() -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun == null:
		return
	var frame := carry_frame()
	var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_wrist).origin
	_carry_wrist = wrist.lerp(frame * _pose().carry_point(gun), _gun_carry)
	_carry_basis = (frame.basis * ActionPose.turn_basis(_pose().carry_turn(gun))).orthonormalized()
	_target.global_position = _carry_wrist
	reach_ik.influence = 1.0


## The frame a carried gun is placed in: the actor's, riding the chest. Its
## origin moves with the chest (the run's bounce, a sprint's lean, a slide's
## drop) and it tips forward and back with `ActionPose.carry_body_follow` of
## the chest's lean, so a point given in the actor's frame at chest height
## stays at the same place on the body. The chest's twist with each stride is
## left out: a gun held in both hands stays steady on the line of the run.
func carry_frame() -> Transform3D:
	var body := actor.global_transform.orthonormalized()
	if _spine.is_empty():
		return body
	var chest := _spine[_spine.size() - 1]
	var to_world := skeleton.global_transform
	var now := skeleton.get_bone_global_pose(chest)
	var rest := skeleton.get_bone_global_rest(chest)
	var to_actor := body.basis.inverse() * to_world.basis.orthonormalized()
	var up_skeleton := (to_actor.inverse() * Vector3.UP).normalized()
	var bone_up := rest.basis.orthonormalized().inverse() * up_skeleton
	var up := (to_actor * (now.basis.orthonormalized() * bone_up)).normalized()
	var lean := atan2(-up.z, maxf(up.y, 0.05))
	var basis := body.basis * Basis(Vector3.RIGHT, -lean * _pose().carry_body_follow)
	var chest_rest := body.affine_inverse() * (to_world * rest.origin)
	return Transform3D(basis, to_world * now.origin - basis * chest_rest)


## Aiming down sights: where the hand would put the sight this frame (from
## the animation's grip and the way `hold_weapon` hangs the gun from it), and
## the hand moved by the difference to `sight_target`, eased by `_ads`.
func _reach_sight() -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun == null or gun.visual == null or grip_bone < 0:
		return
	var aimed := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
	var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_wrist).origin
	var grip := skeleton.global_transform * skeleton.get_bone_global_pose(grip_bone).origin
	var sight_now := grip + aimed * (grip_offset + gun.visual.transform * ActionPose.sight_local(gun))
	var hold: Variant = ActionPose.hold_local(gun)
	if hold != null and _hold_point != null and _aim_wrist != null:
		# The fist on the grip, with the wrist as it will be turned to the
		# aim once the arm has reached.
		var held := _held_wrist(gun)
		var now := skeleton.get_bone_global_pose(_wrist)
		var turned := Basis((now.basis.orthonormalized() * _aim_wrist.orthonormalized().inverse() * held).get_rotation_quaternion() \
				.slerp(_aim_basis(held).get_rotation_quaternion(), _ads))
		var fist := skeleton.global_transform * (Transform3D(turned * Basis.from_scale(now.basis.get_scale()), now.origin) * (_hold_point as Vector3))
		sight_now = fist + aimed * (gun.visual.transform * ActionPose.sight_local(gun) - gun.visual.transform * (hold as Transform3D).origin)
	var fix := actor.global_basis.orthonormalized() * _ads_fix
	_relief_now = _pose().relief_for(gun)
	var reach := wrist + sight_target(gun, aimed) - sight_now + fix
	# Out of the arm's reach (a sidearm held well out), the gun comes back
	# toward the eye along the sight line until the arm can hold it.
	if _upper >= 0:
		var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(_upper).origin
		var elbow := skeleton.global_transform * skeleton.get_bone_global_pose(_forearm).origin
		var length := (shoulder.distance_to(elbow) + elbow.distance_to(wrist)) * ads_reach
		var ahead := -aimed.z
		var d := reach - shoulder
		if d.length() > length:
			var along := d.dot(ahead)
			var back := along - sqrt(maxf(along * along - (d.length_squared() - length * length), 0.0))
			back = clampf(back, 0.0, _relief_now)
			_relief_now -= back
			reach -= ahead * back
	# A sidearm is held in both hands: the off arm has to reach round the
	# gun hand too, so the gun comes back until it can.
	if gun.is_sidearm and _off_upper >= 0 and _off_forearm >= 0 and _off_wrist >= 0:
		var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(_off_upper).origin
		var elbow := skeleton.global_transform * skeleton.get_bone_global_pose(_off_forearm).origin
		var off_wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_off_wrist).origin
		var length := (shoulder.distance_to(elbow) + elbow.distance_to(off_wrist)) * ads_reach
		var ahead := -aimed.z
		var d := reach + ahead * sidearm_wrap - shoulder
		if d.length() > length:
			var along := d.dot(ahead)
			var back := along - sqrt(maxf(along * along - (d.length_squared() - length * length), 0.0))
			back = clampf(back, 0.0, _relief_now)
			_relief_now -= back
			reach -= ahead * back
	_pose().relief_now = _relief_now
	# Out of a carry the gun comes up from where it was carried.
	var from := _carry_wrist if _gun_carry > 0.0 else wrist
	_target.global_position = from + (reach - from) * _ads
	reach_ik.influence = 1.0


## Where the sight of `gun` goes when it is fully up: on the line out of
## the model's eyes, `_relief_now` in front of them.
func sight_target(gun: Gun, aimed: Basis) -> Vector3:
	var skin := get_parent()
	var eye: Variant = skin.eye_point(aimed) if skin != null and skin.has_method("eye_point") else null
	if eye == null:
		eye = actor.get_eye_position()
	return (eye as Vector3) + aimed * Vector3(0.0, 0.0, -_relief_now)


## Turns the spine toward the attack before the arms reach, so they reach
## from where the shoulders have gone. The neck turns back to keep the eyes
## on the target.
func _turn_body() -> void:
	var turn := _turn + _ads_turn
	if _spine.is_empty() or turn.length_squared() < 0.000001:
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var share := 1.0 / _spine.size()
	var step := Basis(to_skeleton * Vector3.UP, turn.x * share) * Basis(to_skeleton * Vector3.RIGHT, turn.y * share)
	for bone in _spine:
		_rotate_bone(bone, step)
	if _neck >= 0:
		_rotate_bone(_neck, Basis(to_skeleton * Vector3.UP, -turn.x * 0.7) * Basis(to_skeleton * Vector3.RIGHT, -turn.y * 0.5))


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
	_off_spot = Vector3.INF
	if _off_weight <= 0.0:
		_off_fix = Vector3.ZERO
	_bend_to_grip()
	_turn_to_carry()
	if _support > 0.0:
		_steady_gun()
	if _grip_weight <= 0.0:
		return
	var melee := actor.get_active_weapon() as MeleeWeapon
	if melee == null or melee.visual == null:
		return
	if _grip_axis != Vector3.ZERO:
		var pose := skeleton.get_bone_global_pose(_wrist)
		var now := (pose.basis.orthonormalized() * _grip_axis).normalized()
		# Toward where the blade is about to be turned (the hand node itself
		# may still be where a physics tick parked it).
		var aimed := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
		var turn := _blade_turn(aimed) * melee.visual.transform.basis.orthonormalized()
		var blade := (skeleton.global_basis.orthonormalized().inverse() * turn.y).normalized()
		var bend := Quaternion(now, blade)
		var angle := minf(bend.get_angle(), wrist_limit) * _grip_weight
		if angle > 0.001:
			pose.basis = Basis(bend.get_axis().normalized(), angle) * pose.basis
			skeleton.set_bone_global_pose(_wrist, pose)
	hold_weapon()
	# Each model says where on its handle the off hand closes (`Look._fit_hands`);
	# the off arm reaches its wrist so the fist's middle is there.
	var model := melee.visual.get_node_or_null("Model")
	var along: float = model.get_meta("off_grip", off_hand_at) if model != null else off_hand_at
	var handle := melee.visual.global_transform * Vector3(0.0, along, 0.0)
	# Out of the off arm's reach (a long haft hanging at the side), the hand
	# slides up the handle toward the weapon hand until it can hold it.
	if _off_upper >= 0 and _off_forearm >= 0 and absf(along) > Look.HAND_WIDTH * 0.8:
		var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(_off_upper).origin
		var elbow := skeleton.global_transform * skeleton.get_bone_global_pose(_off_forearm).origin
		var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_off_wrist).origin
		var length := (shoulder.distance_to(elbow) + elbow.distance_to(wrist)) * ads_reach
		# Toward the weapon hand, along the handle.
		var up := melee.visual.global_basis.y.normalized() * -signf(along)
		var d := handle - shoulder
		if d.length() > length:
			var toward := d.dot(up)
			var slide := -toward - sqrt(maxf(toward * toward - (d.length_squared() - length * length), 0.0))
			handle += up * clampf(slide, 0.0, absf(along) - Look.HAND_WIDTH * 0.8)
	_off_spot = handle
	if _off_hold_point != null and _off_wrist >= 0:
		handle -= skeleton.global_basis * (skeleton.get_bone_global_pose(_off_wrist).basis * (_off_hold_point as Vector3))
		handle += actor.global_basis.orthonormalized() * _off_fix
	_off_target.global_position = handle.lerp(watch_point(), _watch)


## Aiming down sights the off hand comes onto the gun: the fore grip of a
## long gun, cupped under the grip of a sidearm.
func _steady_gun() -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun == null or gun.visual == null or off_ik == null:
		return
	# The hand turns with the gun as it is held in the aim clip, so a wrist
	# never twists round the grip.
	if _aim_wrist != null and _ads > 0.0:
		_turn_to_aim(_wrist, _held_wrist(gun), _ads)
	hold_weapon()
	if _ads > 0.99:
		var aimed := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
		var miss := sight_target(gun, aimed) - actor.hand.global_transform * (gun.visual.transform * ActionPose.sight_local(gun))
		_ads_fix = (_ads_fix + actor.global_basis.orthonormalized().inverse() * miss * 0.5).limit_length(0.1)
	var at: Vector3
	var fore := gun.visual.get_node_or_null("ForeGrip") as Node3D
	if fore == null:
		fore = gun.visual.get_node_or_null("Model/ForeGrip") as Node3D
	var hold: Variant = ActionPose.hold_local(gun)
	if gun.is_sidearm and hold != null:
		# Wrapped round the gun hand's fingers from the off side.
		at = gun.visual.global_transform * ((hold as Transform3D).origin + _pose().ads_cup)
	elif gun.is_sidearm:
		at = actor.hand.global_position + actor.hand.global_basis * _pose().ads_cup
	elif fore != null:
		at = fore.global_position
	else:
		at = gun.visual.global_transform * (ActionPose.sight_local(gun) + ads_fore)
	# The off arm reaches its wrist; the fist's middle goes on the spot.
	var cupped: Variant = _support_turn(gun)
	if _off_hold_point != null and cupped != null:
		at -= skeleton.global_basis * ((cupped as Basis) * (_off_hold_point as Vector3))
	# Out of the off arm's reach, the hand slides back along the gun toward
	# the grip until it can hold it (a short arm takes the fore end nearer).
	if _off_upper >= 0 and _off_forearm >= 0:
		var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(_off_upper).origin
		var elbow := skeleton.global_transform * skeleton.get_bone_global_pose(_off_forearm).origin
		var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_off_wrist).origin
		var length := (shoulder.distance_to(elbow) + elbow.distance_to(wrist)) * ads_reach
		var back := -gun.visual.global_basis.z.normalized()
		var grip_at: Vector3 = gun.visual.global_transform * (hold as Transform3D).origin if hold != null else actor.hand.global_position
		var room := maxf((at - grip_at).dot(back) - 0.06, 0.0)
		var d := at - shoulder
		if d.length() > length:
			var along := d.dot(back)
			var slide := along - sqrt(maxf(along * along - (d.length_squared() - length * length), 0.0))
			at -= back * clampf(slide, 0.0, room)
	_off_target.global_position = at.lerp(watch_point(), _watch)


## After the off arm has reached: its hand turns as the aim clip holds the
## fore end, turned with the aim, so it supports the gun rather than
## twisting across it.
func _turn_off_hand() -> void:
	# A two-handed blade: what the reach left between the off fist and its
	# spot on the handle goes onto the next frame's reach, so it settles on.
	if _off_spot != Vector3.INF and _off_hold_point != null and _off_wrist >= 0 and _watch <= 0.0:
		var fist := skeleton.global_transform * (skeleton.get_bone_global_pose(_off_wrist) * (_off_hold_point as Vector3))
		_off_fix = (_off_fix + actor.global_basis.orthonormalized().inverse() * (_off_spot - fist) * 0.5).limit_length(0.15)
	var gun := actor.get_active_weapon() as Gun
	var cupped: Variant = _support_turn(gun) if _support > 0.0 else null
	if cupped == null or _off_wrist < 0:
		return
	var weight := _support * (1.0 - _watch)
	var pose := skeleton.get_bone_global_pose(_off_wrist)
	var now := pose.basis.orthonormalized()
	pose.basis = Basis(now.get_rotation_quaternion().slerp((cupped as Basis).get_rotation_quaternion(), weight)) \
			* Basis.from_scale(pose.basis.get_scale())
	skeleton.set_bone_global_pose(_off_wrist, pose)


## How the off hand turns to hold `gun`, in the skeleton's space, or null:
## under a long gun's fore end palm up, the fingers across beneath it and
## curling up its far side, the thumb along the near side toward the
## muzzle; on a sidearm palm in against the gun hand, the fingers wrapped
## down round its fingers, the thumb along the frame.
func _support_turn(gun: Gun) -> Variant:
	if gun == null or gun.visual == null or _off_fingers == null:
		return null
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	var turn := gun.visual.global_basis.orthonormalized()
	var fingers: Vector3
	var palm: Vector3
	if gun.is_sidearm:
		# Wrapped round the gun hand from the side, thumb forward along the
		# frame: the hand points ahead and a little up from a wrist kept in
		# line with the forearm, palm in against the grip.
		fingers = turn * Vector3(0.2, 0.3, -1.0)
		palm = turn * Vector3(1.0, 0.0, 0.0)
	else:
		fingers = turn * Vector3(1.0, 0.35, -0.15)
		palm = turn * Vector3(0.0, 1.0, 0.0)
	fingers = (to_skeleton * fingers).normalized()
	palm = to_skeleton * palm
	palm = (palm - fingers * palm.dot(fingers)).normalized()
	var local_fingers: Vector3 = _off_fingers
	var local_palm: Vector3 = _off_palm
	var wanted := Basis(fingers, palm, fingers.cross(palm))
	var own := Basis(local_fingers, local_palm, local_fingers.cross(local_palm))
	return (wanted * own.inverse()).orthonormalized()


## Carrying, the wrist turns with the carried gun, so the fist stays round
## its grip however the gun is carried (low, across the chest, tucked).
func _turn_to_carry() -> void:
	if _gun_carry <= 0.0 or _aim_wrist == null or _wrist < 0:
		return
	var gun := actor.get_active_weapon() as Gun
	if gun == null or gun.visual == null:
		return
	var weight := _gun_carry * (1.0 - _ads)
	if weight <= 0.0:
		return
	var wanted := _turned_basis(_carry_basis, _held_wrist(gun))
	var pose := skeleton.get_bone_global_pose(_wrist)
	var now := pose.basis.orthonormalized()
	pose.basis = Basis(now.get_rotation_quaternion().slerp(wanted.get_rotation_quaternion(), weight)) \
			* Basis.from_scale(pose.basis.get_scale())
	skeleton.set_bone_global_pose(_wrist, pose)


## Sets `bone` (a wrist) to how it sits in `calibrated` (the aim clip, gun
## straight ahead), turned to the current aim, by `weight`: the inverse of
## `_follow_turn`.
func _turn_to_aim(bone: int, calibrated: Basis, weight: float) -> void:
	if weight <= 0.0:
		return
	var wanted := _aim_basis(calibrated)
	var pose := skeleton.get_bone_global_pose(bone)
	var now := pose.basis.orthonormalized()
	pose.basis = Basis(now.get_rotation_quaternion().slerp(wanted.get_rotation_quaternion(), weight)) \
			* Basis.from_scale(pose.basis.get_scale())
	skeleton.set_bone_global_pose(bone, pose)


## A wrist's turn in the skeleton's space as it sits in `calibrated` (the
## aim clip, gun straight ahead), turned to the current aim.
func _aim_basis(calibrated: Basis) -> Basis:
	return _turned_basis(actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch), calibrated)


## A wrist's turn in the skeleton's space as it sits in `calibrated` (the
## aim clip, gun straight ahead), with the gun turned to `gun_turn` (world).
func _turned_basis(gun_turn: Basis, calibrated: Basis) -> Basis:
	var to_world := skeleton.global_basis.orthonormalized()
	var ahead := actor.global_basis.orthonormalized()
	return (to_world.inverse() * gun_turn * ahead.inverse() * to_world * calibrated.orthonormalized()).orthonormalized()


## How the gun hand's wrist sits holding `gun` aimed straight ahead: the
## aim clip's wrist, bent so the closed fist lies along this gun's own
## pistol grip (`ActionPose.hold_local`), within `grip_bend_limit`. Each gun
## model rakes its grip its own way, so each is held a little differently.
func _held_wrist(gun: Gun) -> Basis:
	var calibrated: Basis = (_aim_wrist as Basis).orthonormalized() if _aim_wrist != null else Basis.IDENTITY
	var hold: Variant = ActionPose.hold_local(gun)
	if hold == null or _aim_wrist == null or _grip_axis == Vector3.ZERO or gun.visual == null:
		return calibrated
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var up := (to_skeleton * gun.visual.transform.basis.orthonormalized() * (hold as Transform3D).basis.y).normalized()
	var fist := (calibrated * _grip_axis).normalized()
	var bend := Quaternion(fist, up)
	if bend.get_angle() > grip_bend_limit:
		bend = Quaternion(bend.get_axis().normalized(), grip_bend_limit)
	return Basis(bend) * calibrated


## Before the gun is placed: bend the gun hand's wrist from how the clip
## holds it to how it holds this gun's grip (`_held_wrist`). The gun itself
## still points where the clip and the aim say; only the hand turns on it.
func _bend_to_grip() -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun == null or gun.visual == null or not gun.visual.visible or actor.is_dead or _aim_wrist == null or _wrist < 0:
		return
	var weight := 1.0 - override_weight
	if weight <= 0.0:
		return
	var calibrated: Basis = (_aim_wrist as Basis).orthonormalized()
	var bend := calibrated.inverse() * _held_wrist(gun)
	var pose := skeleton.get_bone_global_pose(_wrist)
	var now := pose.basis.orthonormalized()
	var bent := now * bend
	pose.basis = Basis(now.get_rotation_quaternion().slerp(bent.get_rotation_quaternion(), weight)) * Basis.from_scale(pose.basis.get_scale())
	skeleton.set_bone_global_pose(_wrist, pose)


## Last of all, close the fingers round the handle.
func _close_grip() -> void:
	_curl(_fist, maxf(_grip_weight, ride_grip.y))
	_curl(_off_fist, maxf(maxf(_off_weight, _support * (1.0 - _watch)), ride_grip.x))


func _curl(fist: Dictionary, weight: float) -> void:
	if weight <= 0.0:
		return
	for bone: int in fist:
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(fist[bone], weight))


## How a blade's hand node turns before it settles into the fist: at rest
## where the forearm takes it (a walk swings it, a run carries it), or for
## a two-handed weapon carried across the body, the haft up and over to the
## left; an attack or guard takes it back to the aim.
func _blade_turn(aimed: Basis) -> Basis:
	var hang := clampf(1.0 - _pose().reach_weight, 0.0, 1.0)
	var turn := aimed.slerp(_follow_turn(_forearm, _ready_forearm), hang) if _ready_forearm != null else aimed
	if _carry > 0.0:
		var body := actor.global_basis.orthonormalized()
		var up := (body * carry_up).normalized()
		var side := up.cross(body.z).normalized()
		var across := Basis(side, up, side.cross(up).normalized())
		turn = turn.slerp(across, _carry * hang)
	return turn


## Puts the actor's hand node, which carries the weapon, on the model's hand.
func hold_weapon() -> void:
	if grip_bone < 0 or actor.is_dead:
		return
	var grip: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(grip_bone).origin
	var gun := actor.get_active_weapon() as Gun
	var melee := actor.get_active_weapon() as MeleeWeapon
	var aimed := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
	var shared := pose != null and is_instance_valid(pose)
	if gun != null and shared:
		# Held low, the gun hangs with the hand; raised, it points where it
		# shoots. It turns in the hand through a reload.
		var turn := aimed
		if _aim_wrist != null and pose.low > 0.0:
			turn = aimed.slerp(_follow_turn(_wrist, _held_wrist(gun)), pose.low)
		# Carried on the move, it turns the way the carry holds it.
		if _gun_carry > 0.0:
			turn = turn.orthonormalized().slerp(_carry_basis, _gun_carry)
		actor.hand.global_basis = turn * pose.gun_offset().basis
	elif melee != null and shared and _ready_forearm != null:
		actor.hand.global_basis = _blade_turn(aimed)
	if melee != null and melee.visual != null and _grip_axis != Vector3.ZERO and _wrist >= 0 and _grip_weight > 0.0:
		# The blade lies along the closed fist, wherever the wrist could
		# actually turn: the hand carries it, it never turns past the hand.
		var fist := (skeleton.global_basis.orthonormalized() * skeleton.get_bone_global_pose(_wrist).basis.orthonormalized()
				* _grip_axis).normalized()
		var blade := (actor.hand.global_basis.orthonormalized() * melee.visual.transform.basis.orthonormalized() * Vector3.UP).normalized()
		var settle := Quaternion(blade, fist)
		actor.hand.global_basis = Basis(Quaternion.IDENTITY.slerp(settle, _grip_weight)) * actor.hand.global_basis.orthonormalized()
	var held := grip_offset
	# A blade's guard and windup poses shift it off the hand node. The arm
	# reaches for that spot instead, so take the shift back out here.
	if melee and melee.visual:
		held -= melee.visual.position
		# Its handle runs through the middle of the closed fist.
		if _ring_point != null and _wrist >= 0:
			grip = skeleton.global_transform * (skeleton.get_bone_global_pose(_wrist) * (_ring_point as Vector3))
	actor.hand.global_position = grip + actor.hand.global_basis * held
	# A gun with a known grip sits with that grip in the closed fist, the
	# first finger level with the trigger: every gun model sits in the hand
	# by its own grip, not by one spot shared by all.
	var hold: Variant = ActionPose.hold_local(gun) if gun != null and gun.visual != null else null
	if hold != null and _hold_point != null and _wrist >= 0:
		var fist := skeleton.global_transform * (skeleton.get_bone_global_pose(_wrist) * (_hold_point as Vector3))
		actor.hand.global_position = fist - actor.hand.global_basis * (gun.visual.transform * (hold as Transform3D).origin)
	actor.hand.set_meta("shown", actor.hand.global_transform)
	# The same, kept from the actor, for a view that follows it the next
	# frame after the actor has moved on (`ActionPose.sight_shown`).
	actor.hand.set_meta("shown_local", actor.global_transform.affine_inverse() * actor.hand.global_transform)
