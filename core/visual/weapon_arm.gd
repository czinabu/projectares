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
## How much sooner than its reach a hand's hold on the helmet is full: the
## hand is moved up its reach (`ActorSkin.helmet_reach`), not blended there.
const HELMET_TAKE_UP := 4.0
## Taking the helmet off or putting it on (`ActionPose.helmet_hand`): where
## the off elbow points with the hand up at the head, and down at the hip
## clip (actor frame).
var helmet_elbow_up := Vector3(-0.9, 1.3, -0.3)
var helmet_elbow_down := Vector3(-0.9, 0.6, 0.4)
## Raising the watch (`ActionPose.watch`): where the left wrist comes up to,
## from the eyes along the aim (metres right, up and ahead, pitch clamped to
## `watch_pitch`), so it comes up into the line of sight in both views, and
## where that elbow points, in the actor's frame. The elbow stays out to the
## side and low, so the forearm lies across in front of the chest.
var watch_from_eyes := Vector3(-0.09, -0.1, -0.24)
var watch_pitch := Vector2(-0.7, 0.5)
var watch_elbow := Vector3(-1.0, 1.2, -0.15)
## A gun carried on the move rides the chest, but the arms take up this
## share of the run's bounce, as a person's do: the gun is moved with the
## eyes as they are steadied (`ActorSkin.eye_steadying`), and the chest's
## rocking with each stride is followed with a lag of `carry_steady_time`,
## so the gun stays put in front of the eyes rather than bouncing with
## every stride (playtest feedback: it bobbed all over the view). A crouch,
## a slide or a sprint's lean still comes through, just eased in.
var carry_steady := 0.9
var carry_steady_time := 0.25
## A gun held up at the hip on the move (in a fight, `ActorSkin.in_fight`,
## out of the carry and the sights) is held in the same steadied frame, at
## where the run-and-shoot clip has the wrist on average over one stride, so
## the clip's arm swing with each step never reaches the gun (Caleb's
## in-between wobble: it swung a hand's width every stride). It takes over
## as a stride's worth of the hold has been seen (`_hip_weight`), so a gun
## raised to shoot comes up at once and settles after.
var _hip_samples: Array = []
var _hip_seen := 0.0
var _hip_weight := 0.0
var _hip_dt := 0.0
## The clip's wrist this frame, and where the hip hold puts it (global).
var _hip_raw := Vector3.ZERO
var _hip_wrist := Vector3.ZERO
var _body_frame := Transform3D.IDENTITY
var _steady_lean := INF
var _steady_dt := 0.0
## With the watch up the forearm rolls so the back of the wrist, where the
## watch face is (`Hud.Wrist.FACE_AXIS` in the wrist bone), looks at the
## eyes, and the hand stays straight on from the forearm.
## The most the wrist bends to line the grip up with the blade, in radians.
var wrist_limit := 1.3
## The most the forearm rolls the fist round toward the blade before the
## wrist bends, in radians (a forearm turns about a half turn end to end).
var forearm_roll_limit := 2.8
## How near a half turn the roll the fist needs may be before it keeps the
## way it last rolled (radians), so it does not flip side to side.
var roll_keep := 0.7
var _last_roll := 0.0
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
## And how far ahead of it the off hand holds a long gun at the nearest
## (the fore end, slid back toward the grip as far as it goes), likewise.
var long_wrap := 0.12
var _ready_forearm: Variant = null
var _spine: Array[int] = []
var _neck := -1
## The head's tip onto a long gun's stock in the sights, eased with them
## (`ActionPose.cheek_long`): x toward the gun side, y forward, in radians.
var cheek := Vector2.ZERO
## How far the eyes move onto the stock with it, in the body's frame
## (`ActionPose.cheek_eye`).
var cheek_eye := Vector3.ZERO
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
## How far the empty hand is up as a guard behind a knife held ready (0..1).
var _guard := 0.0
## How far the off hand is on the handle under the weapon hand, for a
## one-handed blade held ready in both hands (the katana), 0..1.
var _hilt := 0.0
var _off_weight := 0.0
var _gun_weight := 0.0
## How closed the gun hand is round the grip: shut whenever a gun is in hand.
var _gun_fist := 0.0
var _watch := 0.0
## How far the off hand is on the helmet, taking it off or putting it on.
var _helm := 0.0
## How far a gun is up at the eye (`ActionPose.ads`), while it is shown.
var _ads := 0.0
## What the arm's reach left between the sight and its target last frame,
## in the actor's frame, added to the next reach so the sight settles on
## the eye line (the hand turns a little as the arm reaches).
var _ads_fix := Vector3.ZERO
## How much of that miss is taken back each frame.
## (More does not keep up with a stride any better: the walk itself is held
## still while aimed, `Locomotion.aim_still_time`.)
var ads_fix_gain := 0.5
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
## What the wall check wants `ActionPose.blocked` to ease to, and a count of
## pose steps so it casts every other one.
var _wall_want := 0.0
var _wall_steps := 0
## The actor's shared pose: what both views show the weapon hand doing.
var pose: ActionPose

## Keeping the arms out of the body and the armor on it (Caleb's call: no
## arm through the armor in any swing, held naturally; `--swing-clip-only`
## measures the real meshes). The trunk is learned as an outline
## (`learn_trunk`): in the chest bone's own frame, cut into `clear_band`
## slices up it from `clear_low` to `clear_high`, each slice the furthest
## the body or its armor reaches at `clear_bins` turns round it. An arm is
## a few points down it, each as thick as `upper_radius`, `fore_radius` or
## `hand_radius` plus a pad or bracer worn on it; one closer to the chest's
## middle than the outline there is in it. With a melee weapon out, before
## each arm reaches (`_keep_clear`) its hand rides the chest (`_ride`,
## `_ride_off`) and is held out by the armor's thickness (`_bulk`), then
## it takes a step a frame toward the least that clears it (`_clear_cost`):
## the elbow's pole turned, the hand out, the shoulder forward round its
## collarbone; once both have reached, an elbow still in is swung round
## its shoulder-to-wrist line (`_swivel_clear`). All eased in and out
## (`clear_turn_rate`, `clear_push_rate`, `clear_forth_rate`,
## `clear_swivel_rate`), so nothing pops. `keep_clear` off leaves the arms
## alone, to compare.
var keep_clear := true
var clear_bins := 24
var clear_band := 0.06
var clear_low := -0.62
var clear_high := 0.3
var upper_radius := 0.045
var fore_radius := 0.045
var hand_radius := 0.05
var clear_turn_rate := 10.0
var clear_push_rate := 1.6
var clear_forth_rate := 3.0
## The steps the arm is moved in, and how many there are at most: the
## elbow's pole turned (radians either way), the hand out (m), the
## shoulder forward round the collar bone (radians).
var clear_turn_step := 0.2
var clear_push_step := 0.05
var clear_forth_step := 0.1
const CLEAR_TURN_STEPS := 8
const CLEAR_PUSH_STEPS := 6
const CLEAR_FORTH_STEPS := 4
## Steps taken a frame at most.
const CLEAR_ROUNDS := 2
const CLEAR_STEPS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
## The outline: `clear_bins` radii per slice, 0 where nothing reaches.
var _trunk := PackedFloat32Array()
var _chest := -1
## What a worn pad and bracer add to the upper arm's and forearm's thickness.
var _arm_extra := Vector2.ZERO
## Per arm (weapon, off): the steps it is going toward and where it is
## eased to (turn, out, forward), and how long the last pose step was.
var _clear_want: Array[Vector3i] = [Vector3i.ZERO, Vector3i.ZERO]
var _clear_now: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _clear_dt := 0.0
var _clear_reach := 0.0
## How far (m) the armor worn stands off the chest (`learn_trunk`).
var _bulk := 0.0
## Per arm: the elbow's swing round its shoulder-to-wrist line
## (`_swivel_clear`), radians.
var _swivel: Array[float] = [0.0, 0.0]
var clear_swivel_step := 0.15
var clear_swivel_max := 1.5
var clear_swivel_rate := 25.0
## Where the chest stands at the ready, for `_ride`.
var _ride_base := Transform3D.IDENTITY
var _ride_set := false


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
	var spine: Array = def.get("spine", [])
	_chest = skeleton.find_bone(spine[-1]) if not spine.is_empty() else -1
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
	var clear := Hook.new()
	clear.name = "ClearReach"
	clear.run = _keep_clear.bind(0)
	skeleton.add_child(clear)
	reach_ik = _two_bone("ArmReach", arm, _target, _pole)
	var place := Hook.new()
	place.name = "PlaceWeapon"
	place.run = _place_weapon
	skeleton.add_child(place)
	var off_arm: Array = def.get("off_arm", [])
	if off_arm.size() == 3 and off_arm.all(func(bone: String) -> bool: return skeleton.find_bone(bone) >= 0):
		var clear_off := Hook.new()
		clear_off.name = "ClearOffReach"
		clear_off.run = _keep_clear.bind(1)
		skeleton.add_child(clear_off)
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
	# Once both arms have reached: each elbow swung round its shoulder-to-
	# wrist line out of the trunk, wherever the reach (or the clip) left it.
	var swivel := Hook.new()
	swivel.name = "ClearSwivel"
	swivel.run = _swivel_clear
	skeleton.add_child(swivel)
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


## True while the clip has the whole body and the arms are left to it: dead,
## or rolling (`ActionPose.rolling`).
func _let_go() -> bool:
	return actor.is_dead or _pose().rolling()


func _pose() -> ActionPose:
	if pose == null or not is_instance_valid(pose):
		pose = ActionPose.of(actor)
	return pose


## Places the reach targets and eases the holds for a pose `delta` after the
## last one. Only the body's skin steps the arm, with each of its poses (a
## far body is posed every few frames, `ActorSkin.detail_step`), so the holds
## ease by the time since the last pose and nothing is placed for a frame
## the skeleton is not posed in.
func step(delta: float) -> void:
	if reach_ik == null or actor == null or not is_instance_valid(actor):
		return
	var shared := _pose()
	shared.advance(delta)
	_steady_dt += delta
	_clear_dt = delta
	_hip_dt += delta
	var melee := actor.get_active_weapon() as MeleeWeapon
	var holding := melee != null and melee.visual != null and not _let_go()
	var reaching := holding and shared.reach_weight > 0.0
	_weight = shared.reach_weight if holding else move_toward(_weight, 0.0, delta * 9.0)
	_grip_weight = move_toward(_grip_weight, 1.0 if holding else 0.0, delta * 8.0)
	# A katana's two hands are its hilt grip below, not the carry.
	var two_handed: bool = holding and look.is_carried(melee)
	_off_weight = move_toward(_off_weight, 1.0 if two_handed else 0.0, delta * 8.0)
	var off_hold := shared.ready_off(melee) if holding else ""
	# An empty off hand stays up as a guard through attacks and guards too,
	# as a fighter's does (it used to drop to the side on every swing).
	_guard = move_toward(_guard, 1.0 if off_hold == "guard" else 0.0, delta * 8.0)
	# A katana's cuts keep the off hand on the handle all the way through
	# (`ActionPose.cut_grip`); held ready it is there too.
	var hilt_to := maxf(shared.held_ready if off_hold == "hilt" else 0.0, shared.cut_grip if holding else 0.0)
	# A two-handed katana never lets go: the off hand stays on the hilt.
	if holding and look.is_two_handed(melee):
		hilt_to = 1.0
	_hilt = hilt_to if not two_handed else move_toward(_hilt, 0.0, delta * 8.0)
	_carry = move_toward(_carry, 1.0 if two_handed else 0.0, delta * 6.0)
	if reaching:
		# The technique says exactly where the hand goes (`ActionPose.techniques`);
		# the blade's own greybox shift is taken back out in `hold_weapon`.
		_reach = shared.reach
	_turn = shared.turn if holding else _turn.lerp(Vector2.ZERO, 1.0 - exp(-26.0 * delta))
	if shared.toy_throw_t >= 0.0:
		_turn = shared.toy_turn()
	var gun := actor.get_active_weapon() as Gun
	_check_wall(gun, shared, delta)
	_gun_weight = maxf(shared.reload, shared.inspect_for("gun")) if gun != null and gun.visual != null \
			and gun.visual.visible and not _let_go() else 0.0
	# The watch takes the left hand off any two-handed hold while it is up.
	_watch = shared.watch if not _let_go() else 0.0
	_helm = ActionPose.helmet_hand(shared.helmet) if not _let_go() else 0.0
	_ads = shared.ads if gun != null and gun.visual != null and gun.visual.visible \
			and not _let_go() and override_weight <= 0.001 else 0.0
	if _ads <= 0.0:
		_ads_fix = Vector3.ZERO
	var raised := 0.0
	_gun_carry = 0.0
	if gun != null and gun.visual != null and gun.visual.visible and not _let_go() and override_weight <= 0.001:
		raised = (1.0 - shared.low) * (1.0 - shared.reload) * (1.0 - shared.inspect_for("gun"))
		# Lowered out of a fight (standing at ease), it is held at the low
		# ready in both hands as on the move, not hung from one hand by the
		# clip (which ran the gun through the arm).
		_gun_carry = maxf(shared.carry, shared.low) if _weight <= 0.001 else 0.0
		raised = lerpf(raised, shared.carry_support(gun), _gun_carry)
	_support = maxf(_ads, raised)
	var in_hand := gun != null and gun.visual != null and gun.visual.visible and not _let_go()
	_gun_fist = move_toward(_gun_fist, 1.0 if in_hand else 0.0, delta * 8.0)
	# Held up at the hip the body blades part way into the aiming stance, so
	# the off shoulder comes forward and the off hand reaches the fore end.
	var hip_up := 0.0
	if gun != null and gun.visual != null and gun.visual.visible and not _let_go() and override_weight <= 0.001 \
			and _weight <= 0.001:
		hip_up = (1.0 - shared.low) * (1.0 - shared.reload) * (1.0 - shared.inspect_for("gun")) * (1.0 - _gun_carry)
	# Carried at a low ready in both hands it blades a little too; at port in
	# a sprint the gun is across the chest and the shoulders stay square.
	var carried_low := 0.0
	if gun != null and not gun.is_sidearm:
		# On the move only: stood at ease the body stays square.
		carried_low = minf(_gun_carry, shared.carry) * (1.0 - shared.sprint) * shared.carry_stance_share
	var stance := maxf(maxf(_ads, hip_up * shared.hip_stance_share), carried_low)
	_ads_turn = shared.ads_stance(gun) * stance if stance > 0.0 else Vector2.ZERO
	var weld := _ads if _ads > 0.0 and shared.cheeks(gun) else 0.0
	cheek = shared.cheek_long * weld
	cheek_eye = shared.cheek_eye * weld

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
	if shared.toy > 0.0 and not _let_go():
		# A toy vehicle held up or thrown: the hand follows the shared throw,
		# taking over from any hold, and the elbow rides up as it cocks.
		var toy_spot := actor.global_transform * shared.toy_hand_point()
		var held_by := reach_ik.influence
		_target.global_position = toy_spot if held_by <= 0.0 else _target.global_position.lerp(toy_spot, shared.toy)
		reach_ik.influence = maxf(held_by, shared.toy)
		_pole.global_position = _pole.global_position.lerp(actor.global_transform * shared.toy_elbow, shared.toy_elbow_raise())
	# Looking over a toy vehicle held up: the hand brings it in front of
	# the chest, and the wrist turns it (`_inspect_wrist`).
	var hand_look := shared.inspect_for("hand")
	if hand_look > 0.0 and _weight <= 0.001 and override_weight <= 0.001:
		_target.global_position = _target.global_position.lerp(shared.inspect_point(), hand_look)
		reach_ik.influence = maxf(reach_ik.influence, hand_look)
	# Both hands lift the helmet off the head (and set it back on): with
	# nothing in it, the weapon hand comes up to its right side too and lets
	# go as the helmet comes down (`ActionPose.helmet_both`).
	var both := ActionPose.helmet_both(shared.helmet) if actor.get_active_weapon() == null \
			and actor.vehicle == null and not _let_go() and shared.toy <= 0.0 else 0.0
	if both > 0.0:
		var skin := get_parent()
		var grip: Variant = skin.helmet_reach(1.0, both) if skin != null and skin.has_method("helmet_reach") else null
		if grip != null:
			# The hand follows its reach up (`ActorSkin.helmet_reach`) under
			# a quickly full hold, so the arm never swings out sideways as a
			# half-blended pose would.
			var on := minf(both * HELMET_TAKE_UP, 1.0)
			var held_by := reach_ik.influence
			_target.global_position = grip if held_by <= 0.0 else _target.global_position.lerp(grip as Vector3, on)
			reach_ik.influence = maxf(held_by, on)
			var up := Vector3(-helmet_elbow_up.x, helmet_elbow_up.y, helmet_elbow_up.z)
			_pole.global_position = _pole.global_position.lerp(actor.global_transform * up, both)
	if off_ik:
		var held := maxf(maxf(maxf(maxf(_off_weight, _support), _guard), _hilt) * (1.0 - _watch), _watch)
		var helm_on := minf(_helm * HELMET_TAKE_UP, 1.0)
		off_ik.influence = maxf(held * (1.0 - helm_on), helm_on)
		var off_pole := off_elbow.lerp(ads_off_elbow, _support) if _off_weight <= 0.0 else off_elbow
		off_pole = off_pole.lerp(watch_elbow, _watch)
		if _helm > 0.0:
			var down := ActionPose.helmet_carry(shared.helmet)
			off_pole = off_pole.lerp(helmet_elbow_up.lerp(helmet_elbow_down, down), _helm)
		_off_pole.global_position = actor.global_transform * off_pole
		if _watch > 0.0 or _helm > 0.0:
			_off_target.global_position = _off_goal(watch_point() if _watch > 0.0 else _off_target.global_position)


## Where the raised watch's wrist goes, in the world: below and ahead of
## the model's eyes (`ActorSkin.eye_point`, steadied on the move, down with
## a crouch, ahead with a run's lean) along the aim, so you look straight
## at it however the body is carried.
func watch_point() -> Vector3:
	var pitch := clampf(actor.cmd.pitch, watch_pitch.x, watch_pitch.y)
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, pitch)
	var skin := get_parent()
	var eye: Variant = skin.eye_point(aim) if skin != null and skin.has_method("eye_point") else null
	if eye == null:
		eye = actor.get_eye_position()
	return (eye as Vector3) + aim * watch_from_eyes


## Where the off hand goes, given where it would go otherwise (`at`):
## taking the helmet off or putting it on, it goes to the helmet's side
## (`ActorSkin.helmet_grip`) instead, as far as it is on it.
func _off_goal(at: Vector3) -> Vector3:
	if _helm <= 0.0:
		return at
	var skin := get_parent()
	var grip: Variant = skin.helmet_reach(-1.0, _helm) if skin != null and skin.has_method("helmet_reach") else null
	return at if grip == null else at.lerp(grip as Vector3, minf(_helm * HELMET_TAKE_UP, 1.0))


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
	var gun := actor.get_active_weapon() as Gun
	var in_hand := gun != null and gun.visual != null and gun.visual.visible and not _let_go() and _wrist >= 0
	if in_hand:
		_hold_at_hip()
	else:
		_hip_samples.clear()
		_hip_seen = 0.0
		_hip_weight = 0.0
	if _gun_carry > 0.0 and _wrist >= 0 and _weight <= 0.001:
		_reach_carry()
	if _ads > 0.0 and _wrist >= 0 and _weight <= 0.001:
		_reach_sight()
		return
	if _gun_carry > 0.0 and _wrist >= 0 and _weight <= 0.001:
		# Coming out of the carry into a look over.
		if pose.inspect_for("gun") > 0.0:
			_target.global_position = _target.global_position.lerp(pose.inspect_point(), pose.inspect_for("gun"))
		return
	if _wrist < 0 or override_weight > 0.001 or _weight > 0.001:
		return
	if _gun_weight <= 0.0:
		# Held up at the hip: the clip's hold with the stride taken out.
		if in_hand and _hip_weight > 0.0:
			_target.global_position = _hip_wrist
			reach_ik.influence = 1.0
		return
	var wrist := _hip_wrist
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
	_target.global_position = wrist + aim * pose.gun_offset().origin
	if pose.reload > 0.0:
		_target.global_position = _target.global_position.lerp(pose.reload_point(), pose.reload)
	var looking := pose.inspect_for("gun")
	if looking > 0.0:
		_target.global_position = _target.global_position.lerp(pose.inspect_point(), looking)
	reach_ik.influence = 1.0


## Carrying a gun on the move: the wrist goes where the carry puts it
## (`ActionPose.carry_point`, from the chest), eased in by `_gun_carry`, and
## the gun's turn for this frame is worked out for `hold_weapon`.
func _reach_carry() -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun == null:
		return
	var frame := _body_frame
	# Placed in the upright body's frame: the head stays up through a run's
	# lean, so the gun keeps its place in the view (leaned with the chest,
	# "under the eyes" swung back toward the hips).
	var upright := actor.global_basis.orthonormalized()
	_carry_wrist = _hip_wrist.lerp(_carry_anchor(upright) + upright * _pose().carry_point(gun), _gun_carry)
	_carry_basis = (frame.basis * ActionPose.turn_basis(_pose().carry_turn(gun))).orthonormalized()
	_target.global_position = _carry_wrist
	reach_ik.influence = 1.0


## The frame a carried gun is placed in: the actor's, riding the chest. Its
## origin moves with the chest (the run's bounce, a sprint's lean, a slide's
## drop) and it tips forward and back with `ActionPose.carry_body_follow` of
## the chest's lean, so a point given in the actor's frame at chest height
## stays at the same place on the body. The chest's twist with each stride is
## left out: a gun held in both hands stays steady on the line of the run;
## and the arms take up most of its bounce (`carry_steady`).
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
	# The chest rocks fore and aft with each stride as well as bouncing;
	# the gun takes the steadied lean, or its muzzle would nod every step.
	if not is_finite(_steady_lean) or absf(_steady_lean - lean) > 1.0:
		_steady_lean = lean
	else:
		_steady_lean = lerpf(_steady_lean, lean, 1.0 - exp(-_steady_dt / maxf(carry_steady_time, 0.01)))
	_steady_dt = 0.0
	lean = lerpf(lean, _steady_lean, carry_steady)
	var basis := body.basis * Basis(Vector3.RIGHT, -lean * _pose().carry_body_follow)
	var chest_rest := body.affine_inverse() * (to_world * rest.origin)
	var skin := get_parent()
	var steadied: Vector3 = skin.eye_steadying() if skin != null and skin.has_method("eye_steadying") else Vector3.ZERO
	return Transform3D(basis, to_world * now.origin - basis * chest_rest + steadied * carry_steady)


## Where a gun held up at the hip has its wrist this frame (`_hip_wrist`).
## The gun is the anchor and the hands follow it, as in true first-person
## shooters: the wrist goes to a spot set from the eyes along the aim
## (`ActionPose.hip_from_eyes`), so the gun is up in the lower part of the
## view, pointed where it shoots, close enough in for the off hand to reach
## its fore end, and the stride's swing never reaches it (the eyes are
## steadied). The new body's arms are shorter than the clip's reach, so the
## clip's own hold left the off hand short of the gun (Caleb's gun handling
## pass). A gun braced at the hip (`ActionPose.shoulders_never`) is held the
## same way, lower (`ActionPose.hip_from_eyes_braced`). A gun held on a
## vehicle keeps the clip's hold, averaged over the last stride.
func _hold_at_hip() -> void:
	_body_frame = carry_frame()
	_hip_raw = skeleton.global_transform * skeleton.get_bone_global_pose(_wrist).origin
	var dt := _hip_dt
	_hip_dt = 0.0
	var gun := actor.get_active_weapon() as Gun
	var shared := _pose()
	if gun != null and actor.vehicle == null:
		_hip_samples.clear()
		_hip_seen = 0.0
		_hip_weight = (1.0 - shared.low) if _weight <= 0.001 else 0.0
		_hip_wrist = _hip_raw.lerp(hip_point(gun), _hip_weight) if _hip_weight > 0.0 else _hip_raw
		return
	_average_clip_wrist(dt)


## Whether a wall stands in front of the muzzle of a gun held up at the hip,
## eased into `ActionPose.blocked`. One ray from the eyes along the aim, as
## long as the eyes' reach to the muzzle, every other pose step, and only
## while a gun is up out of the sights; the world only, never bodies.
func _check_wall(gun: Gun, shared: ActionPose, delta: float) -> void:
	var up := gun != null and gun.visual != null and gun.visual.visible and not _let_go() \
			and shared.low < 0.5 and shared.carry < 0.5 and shared.ads < 0.5 and is_inside_tree()
	_wall_steps += 1
	if not up:
		_wall_want = 0.0
	elif _wall_steps % 2 == 0:
		var box := ActionPose.model_box(gun)
		var reach := shared.hip_from_eyes(gun).length() + box.size.z * 0.9
		var from := actor.get_eye_position()
		var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch) * Vector3.FORWARD
		var query := PhysicsRayQueryParameters3D.create(from, from + aim * reach, Actor.LAYER_WORLD)
		query.exclude = [actor.get_rid()]
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		_wall_want = 0.0 if hit.is_empty() else clampf((reach - from.distance_to(hit.position)) / maxf(box.size.z * 0.6, 0.1), 0.0, 1.0)
	shared.blocked = move_toward(shared.blocked, _wall_want, delta * shared.wall_rate)


## Where the gun hand's wrist goes to hold `gun` up at the hip (global): from
## the model's eyes along the aim, its pitch clamped to `ActionPose.hip_pitch`
## so a look straight up or down does not throw the arm out of reach.
func hip_point(gun: Gun) -> Vector3:
	var shared := _pose()
	var pitch := clampf(actor.cmd.pitch, shared.hip_pitch.x, shared.hip_pitch.y)
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, pitch)
	var body := actor.global_basis.orthonormalized()
	var drawn_in := Vector3(0.0, shared.wall_raise, shared.wall_back) * shared.blocked
	return _eyes_now(aim) + aim * (shared.hip_from_eyes(gun) + drawn_in) + body * shared.sway


## The clip's wrist in the steadied frame the carry rides (`carry_frame`,
## kept in `_body_frame`), averaged over the last stride, so the body's
## turns, crouches and leans come through and a stride's swing does not.
## Standing, carried or on a vehicle, the clip's own hold is left alone.
func _average_clip_wrist(dt: float) -> void:
	var flat := Vector2(actor.velocity.x, actor.velocity.z).length()
	var holding := flat > 0.6 and actor.vehicle == null and _gun_carry < 0.5 and _weight <= 0.001
	if not holding:
		_hip_samples.clear()
		_hip_seen = 0.0
	elif dt > 0.0:
		_hip_samples.append([_body_frame.affine_inverse() * _hip_raw, dt])
		_hip_seen += dt
		var stride := _stride_time()
		while _hip_samples.size() > 1 and _hip_seen - float(_hip_samples[0][1]) >= stride:
			_hip_seen -= float(_hip_samples[0][1])
			_hip_samples.pop_front()
	var want := smoothstep(0.0, 1.0, clampf(_hip_seen / _stride_time(), 0.0, 1.0)) if holding else 0.0
	_hip_weight = move_toward(_hip_weight, want, dt * 4.0) if want < _hip_weight else want
	if _hip_samples.is_empty() or _hip_weight <= 0.0:
		_hip_wrist = _hip_raw
		return
	var sum := Vector3.ZERO
	var time := 0.0
	for sample: Array in _hip_samples:
		sum += (sample[0] as Vector3) * float(sample[1])
		time += float(sample[1])
	_hip_wrist = _hip_raw.lerp(_body_frame * (sum / maxf(time, 0.0001)), _hip_weight)


## The model's eyes as posed now (`ActorSkin.eye_point`, steadied on the
## move), looking along `look`; the actor's eye spot without a head.
func _eyes_now(look: Basis) -> Vector3:
	var skin := get_parent()
	var eye: Variant = skin.eye_point(look) if skin != null and skin.has_method("eye_point") else null
	return actor.get_eye_position() if eye == null else eye as Vector3


## Where a carry is placed from: level with the eyes, so the gun keeps its
## height in the view, but back in line with the shoulders, which the arms
## reach from (a run's lean and a crouch put the head well ahead of them).
func _carry_anchor(upright: Basis) -> Vector3:
	var eye := _eyes_now(upright)
	if _upper < 0 or _off_upper < 0:
		return eye
	var shoulders := skeleton.global_transform * ((skeleton.get_bone_global_pose(_upper).origin
			+ skeleton.get_bone_global_pose(_off_upper).origin) * 0.5)
	var back := upright.z.normalized()
	return eye + back * (shoulders - eye).dot(back)


## How long one stride of the clip playing takes, in seconds.
func _stride_time() -> float:
	var skin := get_parent()
	var player: AnimationPlayer = skin.get("_player") if skin != null else null
	if player == null or player.current_animation_length <= 0.0:
		return 0.5
	return clampf(player.current_animation_length / maxf(absf(player.get_playing_speed()), 0.1), 0.25, 1.5)


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
	# Both hands hold it: the off arm has to reach round the gun hand on a
	# sidearm, or the fore end of a long gun, so the gun comes back until it
	# can.
	if _off_upper >= 0 and _off_forearm >= 0 and _off_wrist >= 0:
		var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(_off_upper).origin
		var elbow := skeleton.global_transform * skeleton.get_bone_global_pose(_off_forearm).origin
		var off_wrist := skeleton.global_transform * skeleton.get_bone_global_pose(_off_wrist).origin
		var length := (shoulder.distance_to(elbow) + elbow.distance_to(off_wrist)) * ads_reach
		var ahead := -aimed.z
		var d := reach + ahead * (sidearm_wrap if gun.is_sidearm else long_wrap) - shoulder
		if d.length() > length:
			var along := d.dot(ahead)
			var back := along - sqrt(maxf(along * along - (d.length_squared() - length * length), 0.0))
			back = clampf(back, 0.0, _relief_now)
			_relief_now -= back
			reach -= ahead * back
	_pose().relief_now = _relief_now
	# Out of a carry the gun comes up from where it was carried, and from
	# the hip as steadied as it was held there.
	var from := _carry_wrist if _gun_carry > 0.0 else _hip_wrist
	_target.global_position = from + (reach - from) * _ads
	reach_ik.influence = 1.0


## Where the sight of `gun` goes when it is fully up: on the line out of
## the model's eyes, `_relief_now` in front of them.
func sight_target(gun: Gun, aimed: Basis) -> Vector3:
	var skin := get_parent()
	var eye: Variant = skin.eye_point(aimed) if skin != null and skin.has_method("eye_point") else null
	if eye == null:
		eye = actor.get_eye_position()
	return (eye as Vector3) + aimed * (Vector3(0.0, 0.0, -_relief_now) + _pose().sight_aside(gun))


## Turns the spine toward the attack before the arms reach, so they reach
## from where the shoulders have gone. The neck turns back to keep the eyes
## on the target.
func _turn_body() -> void:
	var turn := _turn + _ads_turn
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	if _neck >= 0 and cheek != Vector2.ZERO:
		var tip := cheek_basis()
		_rotate_bone(_neck, to_skeleton * tip * to_skeleton.inverse())
	if _spine.is_empty() or turn.length_squared() < 0.000001:
		return
	var share := 1.0 / _spine.size()
	var step := Basis(to_skeleton * Vector3.UP, turn.x * share) * Basis(to_skeleton * Vector3.RIGHT, turn.y * share)
	for bone in _spine:
		_rotate_bone(bone, step)
	if _neck >= 0:
		_rotate_bone(_neck, Basis(to_skeleton * Vector3.UP, -turn.x * 0.7) * Basis(to_skeleton * Vector3.RIGHT, -turn.y * 0.5))


## The cheek weld's tip of the head (`cheek`), in the actor's frame: toward
## the gun side, then forward.
func cheek_basis() -> Basis:
	return Basis(Vector3.BACK, -cheek.x) * Basis(Vector3.RIGHT, -cheek.y)


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
	if _off_weight <= 0.0 and _hilt <= 0.0:
		_off_fix = Vector3.ZERO
	_inspect_wrist()
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
		# A reverse grip: the blade leaves the fist on the little-finger side.
		if _pose().ready_reversed(melee):
			blade = -blade
		# First the forearm rolls the fist round toward the blade (it turns
		# far more freely than the wrist bends), then the wrist bends the
		# rest of the way, so a backhand still holds the blade out the way
		# the swing has it rather than wherever the wrist ran out.
		if _forearm >= 0:
			var elbow := skeleton.get_bone_global_pose(_forearm).origin
			var along := pose.origin - elbow
			if along.length() > 0.01:
				along = along.normalized()
				var now_flat := now - along * now.dot(along)
				var want_flat := blade - along * blade.dot(along)
				if now_flat.length() > 0.05 and want_flat.length() > 0.05:
					var wanted := now_flat.normalized().signed_angle_to(want_flat.normalized(), along)
					# Near a half turn either way is as far: keep rolling the
					# way it rolled last frame, or it flips each step.
					if absf(wanted) > PI - roll_keep and signf(wanted) != signf(_last_roll) and _last_roll != 0.0:
						wanted -= signf(wanted) * TAU
					# With the blade nearly along the forearm the roll it asks
					# for is barely defined and can swing half a turn in a
					# frame, throwing the hand across: there the forearm keeps
					# most of the roll it had.
					wanted = lerpf(_last_roll, wanted, smoothstep(0.1, 0.4, want_flat.length()))
					_last_roll = wanted
					var roll := clampf(wanted, -forearm_roll_limit, forearm_roll_limit) * _grip_weight
					if absf(roll) > 0.001:
						pose.basis = Basis(along, roll) * pose.basis
						skeleton.set_bone_global_pose(_wrist, pose)
						now = (pose.basis.orthonormalized() * _grip_axis).normalized()
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
	if _hilt > 0.0 and _off_weight <= 0.0:
		# Held ready in both hands: the off fist right under the weapon hand.
		along = -Look.HAND_WIDTH
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
	if _guard > 0.0:
		handle = handle.lerp(actor.global_transform * _pose().off_guard, _guard)
	_off_target.global_position = _off_goal(handle.lerp(watch_point(), _watch))


## Looking over what is in the hand (`ActionPose.inspect`): once the arm
## has reached, the wrist turns the way the item is turned, so the hand
## turns it rather than the item turning in a still hand.
func _inspect_wrist() -> void:
	var shared := _pose()
	if _wrist < 0 or shared.inspecting() == "":
		return
	var aimed := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
	var world := aimed * shared.inspect_basis() * aimed.inverse()
	var to_skeleton := skeleton.global_basis.orthonormalized()
	_rotate_bone(_wrist, (to_skeleton.inverse() * world * to_skeleton).orthonormalized())


## Aiming down sights the off hand comes onto the gun: the fore grip of a
## long gun, cupped under the grip of a sidearm.
func _steady_gun() -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun == null or gun.visual == null or off_ik == null:
		return
	# The hand turns with the gun as it is held in the aim clip, so a wrist
	# never twists round the grip.
	# Held up at the hip on the move it is turned the same, so a stride's
	# roll of the forearm never nods the muzzle (`_hold_at_hip`).
	var turned := maxf(_ads, _hip_weight * (1.0 - _gun_carry))
	if _aim_wrist != null and turned > 0.0:
		_turn_to_aim(_wrist, _held_wrist(gun), turned)
	hold_weapon()
	if _ads > 0.99:
		var aimed := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
		var miss := sight_target(gun, aimed) - actor.hand.global_transform * (gun.visual.transform * ActionPose.sight_local(gun))
		_ads_fix = (_ads_fix + actor.global_basis.orthonormalized().inverse() * miss * ads_fix_gain).limit_length(0.1)
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
	_off_target.global_position = _off_goal(at.lerp(watch_point(), _watch))


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
	if gun == null or gun.visual == null or not gun.visual.visible or _let_go() or _aim_wrist == null or _wrist < 0:
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
	_curl(_fist, maxf(maxf(_grip_weight, _gun_fist), ride_grip.y))
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
	# Held ready, the weapon stands in the fist the way its hold says.
	var shared := _pose()
	var melee := actor.get_active_weapon() as MeleeWeapon
	# An attack or guard turns the blade the way its technique has it,
	# whatever the weapon's own greybox pose is doing (that is taken back out).
	var cut: Variant = shared.technique_blade(melee) if melee != null and melee.visual != null else null
	if cut != null:
		turn = turn.slerp(aimed * (cut as Basis) * melee.visual.transform.basis.orthonormalized().inverse(),
				clampf(shared.reach_weight, 0.0, 1.0))
	if shared.held_ready > 0.0:
		var stood: Variant = shared.ready_turn(melee)
		if stood != null:
			turn = turn.slerp(aimed * (stood as Basis), shared.held_ready)
	if _carry > 0.0:
		var body := actor.global_basis.orthonormalized()
		var up := (body * carry_up).normalized()
		var side := up.cross(body.z).normalized()
		var across := Basis(side, up, side.cross(up).normalized())
		turn = turn.slerp(across, _carry * hang)
	if _pose().inspecting() == "melee":
		turn = turn * _pose().inspect_basis()
	return turn


## Through a swing or guard, rolls the weapon about its own length so its
## striking face (`ActionPose.cut_edge`) turns as near the way the
## technique has it as it can. The fist settle above puts the blade where
## the wrist could turn it, which alone can leave an axe's bit or a
## hammer's face pointing off to the side when the wrist runs out of bend;
## a handle turning in the fist is free, so the face still leads.
func _face_strike(melee: MeleeWeapon, aimed: Basis) -> void:
	var cut: Variant = pose.technique_blade(melee)
	var weight := clampf(pose.reach_weight, 0.0, 1.0)
	if cut == null or weight <= 0.0:
		return
	var own := melee.visual.transform.basis.orthonormalized()
	var held := actor.hand.global_basis.orthonormalized() * own
	var along := held.y.normalized()
	var face := held * pose.cut_edge
	var wanted := aimed * (cut as Basis) * pose.cut_edge
	face -= along * face.dot(along)
	wanted -= along * wanted.dot(along)
	if face.length() < 0.05 or wanted.length() < 0.05:
		return
	var angle := face.normalized().signed_angle_to(wanted.normalized(), along) * weight
	if absf(angle) > 0.001:
		actor.hand.global_basis = Basis(along, angle) * actor.hand.global_basis.orthonormalized()


## Between poses of a body posed every few frames (`ActorSkin.detail_step`):
## the hand node back where `hold_weapon` last showed it, in the actor's
## frame, since the skeleton's bones only hold what the arm reached inside
## its update.
func hold_shown() -> void:
	if actor.is_dead or not actor.hand.has_meta("shown_local"):
		hold_weapon()
		return
	actor.hand.global_transform = actor.global_transform * (actor.hand.get_meta("shown_local") as Transform3D)


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
		# A shot tips the muzzle up and it settles back (`ActionPose.tip`);
		# in the sights the view takes the recoil instead.
		var tipped := (pose.tip + pose.blocked * pose.wall_tip) * (1.0 - _ads) * (1.0 - pose.low)
		if absf(tipped) > 0.0001:
			turn = turn.orthonormalized() * Basis(Vector3.RIGHT, tipped)
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
		if pose.ready_reversed(melee):
			fist = -fist
		var blade := (actor.hand.global_basis.orthonormalized() * melee.visual.transform.basis.orthonormalized() * Vector3.UP).normalized()
		var settle := Quaternion(blade, fist)
		actor.hand.global_basis = Basis(Quaternion.IDENTITY.slerp(settle, _grip_weight)) * actor.hand.global_basis.orthonormalized()
		_face_strike(melee, aimed)
		if shared and pose.bind_turn > 0.0:
			# In a bind the blade turns in the fist to point at the meeting
			# spot, so both blades cross there (`ActionPose.bind`).
			var to_bind := pose.bind_at - grip
			if to_bind.length() > 0.05:
				var along := (actor.hand.global_basis.orthonormalized() * melee.visual.transform.basis.orthonormalized() * Vector3.UP).normalized()
				var meet := Quaternion(along, to_bind.normalized())
				actor.hand.global_basis = Basis(Quaternion.IDENTITY.slerp(meet, pose.bind_turn)) * actor.hand.global_basis.orthonormalized()
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


## Learns the trunk's outline (see `clear_bins`): the body's own skin on the
## trunk's bones, and every worn piece in `parts` hung on a bone that is
## not an arm's, taken as they sit at rest. `arm_extra` is how much thicker
## a pad makes the upper arm and a bracer the forearm. Called by the skin
## whenever what is worn changes.
func learn_trunk(parts: Array, arm_extra := Vector2.ZERO) -> void:
	_arm_extra = arm_extra
	_trunk = PackedFloat32Array()
	if skeleton == null or _chest < 0:
		return
	var slices := int(ceil((clear_high - clear_low) / clear_band))
	_trunk.resize(slices * clear_bins)
	_trunk.fill(0.0)
	var chest_rest := skeleton.get_bone_global_rest(_chest).affine_inverse()
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var trunk_bones := ["Chest", "Torso", "Abdomen", "Hips", "Neck"]
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin == null or mi.mesh == null or not String(mi.name) in ["PartBody", "PartLegs"]:
			continue
		var at := to_skeleton * mi.global_transform
		var owners := {}
		for i in mi.skin.get_bind_count():
			var bone := skeleton.find_bone(mi.skin.get_bind_name(i)) if mi.skin.get_bind_name(i) != "" else mi.skin.get_bind_bone(i)
			owners[i] = skeleton.get_bone_name(bone) if bone >= 0 else ""
		for surface in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(surface)
			if arr[Mesh.ARRAY_BONES] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(1, verts.size())
			for k in verts.size():
				var best := 0
				for j in per:
					if weights[k * per + j] > weights[k * per + best]:
						best = j
				if String(owners.get(bones[k * per + best], "")) in trunk_bones:
					_widen(chest_rest * (at * verts[k]))
	var bare := _trunk.duplicate()
	for part: Variant in parts:
		if not is_instance_valid(part) or not part is BoneAttachment3D:
			continue
		var bone := skeleton.find_bone((part as BoneAttachment3D).bone_name)
		if bone < 0 or _is_arm_bone(skeleton.get_bone_name(bone)):
			continue
		# Where the piece sits on its bone, carried to that bone at rest.
		var onto := chest_rest * skeleton.get_bone_global_rest(bone) * (part as Node3D).global_transform.affine_inverse()
		for node in (part as Node).find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or not mi.is_inside_tree():
				continue
			var at := onto * mi.global_transform
			for surface in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					_widen(at * v)
	# How much the armor stands off the body round the chest, on average
	# where it covers it: the hands are held that much further out.
	var added := 0.0
	var covered := 0
	for i in _trunk.size():
		var slice := clear_low + (i / clear_bins + 0.5) * clear_band
		if slice > -0.3 and slice < 0.1 and bare[i] > 0.0 and _trunk[i] > bare[i]:
			added += _trunk[i] - bare[i]
			covered += 1
	_bulk = added / covered / _unit() if covered > 0 else 0.0
	# Round the shoulders the arms at rest are clear: what the outline took
	# in from a shoulder's own bulk (an armpit, a collar's edge) is no
	# body for the arm beside it to keep out of.
	var unit := _unit()
	for bones: Array in [[_upper, _forearm, _wrist], [_off_upper, _off_forearm, _off_wrist]]:
		if bones.has(-1):
			continue
		var at: Array[Vector3] = []
		for b: int in bones:
			at.append(chest_rest * skeleton.get_bone_global_rest(b).origin)
		for t: float in [0.4, 0.55, 0.7, 0.85, 1.0]:
			_carve(at[0].lerp(at[1], t), (upper_radius + _arm_extra.x) * unit)
		for t: float in [0.35, 0.7, 1.0]:
			_carve(at[1].lerp(at[2], t), (fore_radius + _arm_extra.y) * unit)


## Pulls the outline in so `at` (the chest's rest frame), `radius` thick,
## is just clear of it.
func _carve(at: Vector3, radius: float) -> void:
	var slice := int(floor((at.y - clear_low) / clear_band))
	if slice < 0 or slice * clear_bins >= _trunk.size():
		return
	var b := _bin(at)
	var room := maxf(Vector2(at.x, at.z).length() - radius - 0.002, 0.0)
	for k in [-1, 0, 1]:
		var i := slice * clear_bins + posmod(b + k, clear_bins)
		_trunk[i] = minf(_trunk[i], room)


func _is_arm_bone(bone: String) -> bool:
	for arm: String in ["Shoulder", "UpperArm", "LowerArm", "Wrist", "Thumb", "Index", "Middle", "Ring", "Pinky"]:
		if bone.begins_with(arm):
			return true
	return false


## Takes a point (the chest's rest frame) into the outline.
func _widen(at: Vector3) -> void:
	var slice := int(floor((at.y - clear_low) / clear_band))
	if slice < 0 or slice * clear_bins >= _trunk.size():
		return
	var i := slice * clear_bins + _bin(at)
	_trunk[i] = maxf(_trunk[i], Vector2(at.x, at.z).length())


func _bin(at: Vector3) -> int:
	return posmod(int(floor((atan2(at.z, at.x) + PI) / TAU * clear_bins)), clear_bins)


## How far `at` (the skeleton's space) is inside the trunk's outline, with
## `radius` of its own; 0 or less is clear.
func _depth(at: Vector3, radius: float, chest: Transform3D) -> float:
	var c := chest * at
	var slice := int(floor((c.y - clear_low) / clear_band))
	if slice < 0 or slice * clear_bins >= _trunk.size():
		return 0.0
	var b := _bin(c)
	var reach := 0.0
	for k in [-1, 0, 1]:
		reach = maxf(reach, _trunk[slice * clear_bins + posmod(b + k, clear_bins)])
	if reach <= 0.0:
		return 0.0
	return reach + radius - Vector2(c.x, c.z).length()


## The deepest any point down the arm goes into the trunk, with the elbow
## where a two-bone reach from `shoulder` to `hand` bent toward `pole` puts
## it. The top of the upper arm is in the shoulder, so it starts halfway.
func _arm_depth(shoulder: Vector3, hand: Vector3, pole: Vector3, upper: float, fore: float, chest: Transform3D) -> float:
	var elbow := _elbow(shoulder, hand, pole, upper, fore)
	var worst := -INF
	var unit := _unit()
	for t: float in [0.75, 1.0]:
		worst = maxf(worst, _depth(shoulder.lerp(elbow, t), (upper_radius + _arm_extra.x) * unit, chest))
	for t: float in [0.35, 0.7]:
		worst = maxf(worst, _depth(elbow.lerp(hand, t), (fore_radius + _arm_extra.y) * unit, chest))
	worst = maxf(worst, _depth(hand, hand_radius * unit, chest))
	return worst


## The deepest any point of an arm posed shoulder, elbow, wrist goes in.
func _posed_depth(shoulder: Vector3, elbow: Vector3, hand: Vector3, chest: Transform3D) -> float:
	var worst := -INF
	var unit := _unit()
	for t: float in [0.75, 1.0]:
		worst = maxf(worst, _depth(shoulder.lerp(elbow, t), (upper_radius + _arm_extra.x) * unit, chest))
	for t: float in [0.35, 0.7]:
		worst = maxf(worst, _depth(elbow.lerp(hand, t), (fore_radius + _arm_extra.y) * unit, chest))
	return worst


## After both arms have reached (`_keep_clear` steers them as they do, from
## where it reckons they will be): any arm still in the trunk has its elbow
## swung round the line from its shoulder to its wrist, the fewest degrees
## that clear it (`clear_swivel_step` at a time, to `clear_swivel_max`),
## eased (`clear_swivel_rate`, quick: the arm can sweep into the trunk in a
## few frames). The wrist keeps its place and its turn, so
## the weapon stays where it was put and the hand where it holds.
func _swivel_clear() -> void:
	var dt := maxf(_clear_dt, 1.0 / 240.0)
	var on := keep_clear and not _trunk.is_empty() and _chest >= 0 and actor != null \
			and actor.get_active_weapon() is MeleeWeapon and not actor.is_dead
	var chest := skeleton.get_bone_global_pose(_chest).affine_inverse() if on else Transform3D.IDENTITY
	for which in 2:
		var upper := _upper if which == 0 else _off_upper
		var fore := _forearm if which == 0 else _off_forearm
		var wrist := _wrist if which == 0 else _off_wrist
		var want := 0.0
		if on and upper >= 0 and fore >= 0 and wrist >= 0:
			var s := skeleton.get_bone_global_pose(upper).origin
			var e := skeleton.get_bone_global_pose(fore).origin
			var w := skeleton.get_bone_global_pose(wrist).origin
			var line := (w - s).normalized() if w.distance_to(s) > 0.001 else Vector3.DOWN
			var now: float = _swivel[which]
			var turned := s + (e - s).rotated(line, now)
			want = now
			var here := _posed_depth(s, turned, w, chest)
			if here > 0.0:
				# The nearest turn from where it is that clears it, the way
				# it turned last first, as far as it can swing in a frame;
				# else the clearest of those.
				var side := signf(now) if now != 0.0 else 1.0
				var best := here
				var reach := mini(ceili(clear_swivel_rate * dt / clear_swivel_step), 10)
				for k in range(1, reach + 1):
					var found := false
					for sign: float in [side, -side]:
						var turn := clampf(now + sign * k * clear_swivel_step, -clear_swivel_max, clear_swivel_max)
						var depth := _posed_depth(s, s + (e - s).rotated(line, turn), w, chest)
						if depth < best:
							best = depth
							want = turn
						if depth <= 0.0:
							found = true
							break
					if found:
						break
			elif now != 0.0:
				# Clear: back toward none a step at a time while it stays so.
				var back := move_toward(now, 0.0, clear_swivel_step)
				if _posed_depth(s, s + (e - s).rotated(line, back), w, chest) <= 0.0:
					want = back
		var eased := move_toward(_swivel[which], want, clear_swivel_rate * dt)
		_swivel[which] = eased
		if absf(eased) < 0.0001 or upper < 0 or wrist < 0:
			continue
		var s := skeleton.get_bone_global_pose(upper).origin
		var keep := skeleton.get_bone_global_pose(wrist)
		var line := (keep.origin - s).normalized() if keep.origin.distance_to(s) > 0.001 else Vector3.DOWN
		var turn := Basis(line, eased)
		var arm := skeleton.get_bone_global_pose(upper)
		skeleton.set_bone_global_pose(upper, Transform3D(turn * arm.basis, arm.origin))
		skeleton.set_bone_global_pose(wrist, keep)


static func _elbow(shoulder: Vector3, hand: Vector3, pole: Vector3, upper: float, fore: float) -> Vector3:
	var line := hand - shoulder
	var d := clampf(line.length(), 0.001, upper + fore - 0.001)
	var n := line.normalized() if line.length() > 0.0001 else Vector3.DOWN
	var along := (upper * upper - fore * fore + d * d) / (2.0 * d)
	var out := sqrt(maxf(upper * upper - along * along, 0.0))
	var bend := (pole - shoulder) - n * n.dot(pole - shoulder)
	bend = bend.normalized() if bend.length() > 0.0001 else n.cross(Vector3.RIGHT).normalized()
	return shoulder + n * along + bend * out


## Before arm `which` (0 the weapon arm, 1 the off arm) reaches: steers its
## elbow, and if need be its hand, out of the trunk (see `clear_bins`).
func _keep_clear(which: int) -> void:
	var ik := reach_ik if which == 0 else off_ik
	var target := _target if which == 0 else _off_target
	var pole_node := _pole if which == 0 else _off_pole
	var upper := _upper if which == 0 else _off_upper
	var fore := _forearm if which == 0 else _off_forearm
	var wrist := _wrist if which == 0 else _off_wrist
	var collar := skeleton.get_bone_parent(upper) if skeleton != null and upper >= 0 else -1
	var on := keep_clear and ik != null and not _trunk.is_empty() and upper >= 0 and fore >= 0 and wrist >= 0 \
			and collar >= 0 and actor != null and actor.get_active_weapon() is MeleeWeapon and not actor.is_dead
	var want: Vector3i = _clear_want[which]
	if not on:
		want = Vector3i.ZERO
	var held := ik.influence if ik != null else 0.0
	var dt := maxf(_clear_dt, 1.0 / 240.0)
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var shoulder := Vector3.ZERO
	var hand := Vector3.ZERO
	var pole := Vector3.ZERO
	var out := Vector3.ZERO
	var up := Vector3.UP
	var forth := 0.0
	# This frame's placing of the weapon put the off hand on its handle.
	var on_handle := which == 1 and _off_spot != Vector3.INF and maxf(_off_weight, _hilt) > 0.05
	var unit := _unit()
	if on:
		shoulder = skeleton.get_bone_global_pose(upper).origin
		# Where the arm will be: the clip's arm, taken toward the reach as
		# far as the reach holds it (an arm the clip alone moves, the off
		# arm beside a one-handed weapon, is kept clear the same way).
		var clip_elbow := skeleton.get_bone_global_pose(fore).origin
		var clip_hand := skeleton.get_bone_global_pose(wrist).origin
		var bent := clip_elbow - Geometry3D.get_closest_point_to_segment_uncapped(clip_elbow, shoulder, clip_hand)
		var clip_pole := clip_elbow + bent.normalized() * 0.3 if bent.length() > 0.001 else to_skeleton * pole_node.global_position
		var reach_to := to_skeleton * target.global_position
		# (Not a weapon in both hands: its head's path is the cut, and a
		# heavy head carried along the lunge would lead flat on.)
		var two_hands: bool = look != null and look.is_two_handed(actor.get_active_weapon())
		if which == 0 and not two_hands:
			reach_to += _ride(held)
		elif which == 0:
			_ride(0.0)
		elif not on_handle:
			reach_to = _ride_off(reach_to, held)
		hand = clip_hand.lerp(reach_to, held)
		# Armor stands off the chest: a hand in front of it is held out as
		# much further (not a weapon in both hands: the off hand could not
		# follow it).
		var chest_now := skeleton.get_bone_global_pose(_chest)
		var flat := chest_now.affine_inverse() * hand
		var from_middle := chest_now.basis * Vector3(flat.x, 0.0, flat.z)
		var both: bool = look != null and look.is_two_handed(actor.get_active_weapon())
		if not both and _bulk > 0.0 and from_middle.length() > 0.0001:
			hand += from_middle.normalized() * _bulk * unit * held
		pole = clip_pole.lerp(to_skeleton * pole_node.global_position, held)
		var upper_len := clip_elbow.distance_to(shoulder)
		var fore_len := clip_hand.distance_to(clip_elbow)
		var chest_pose := skeleton.get_bone_global_pose(_chest)
		var chest := chest_pose.affine_inverse()
		_clear_reach = (upper_len + fore_len) * 0.97
		# Out of the trunk for a hand: ahead of the chest (which leans and
		# turns through a swing) and away from its middle.
		var ahead := (chest_pose.basis * skeleton.get_bone_global_rest(_chest).basis.inverse() \
				* (to_skeleton.basis * -actor.global_basis.z)).normalized()
		var c := chest * hand
		var away := chest_pose.basis * Vector3(c.x, 0.0, c.z)
		out = (ahead + (away.normalized() if away.length() > 0.0001 else ahead)).normalized()
		# The shoulder comes forward round the collar bone (the body's up).
		up = (to_skeleton.basis * actor.global_basis.y).normalized()
		var root := skeleton.get_bone_global_pose(collar).origin
		forth = signf(up.cross(shoulder - root).dot(ahead))
		# Both hands on the handle stay where they hold it (the off hand
		# could not follow the weapon hand further out); a free off hand
		# moves out only a little.
		var pushes := 0 if on_handle else (CLEAR_PUSH_STEPS if which == 0 else CLEAR_PUSH_STEPS / 2)
		if which == 0 and both:
			pushes = 0
		# Both hands on a handle round the shoulders further forward.
		var forths := CLEAR_FORTH_STEPS * 3 / 2 if both else CLEAR_FORTH_STEPS
		# A step a frame toward the least that clears it (`_clear_cost`):
		# the elbow turned, the hand moved out, the shoulder brought forward,
		# each eased back off once it is not needed.
		var args := [shoulder, root, hand, pole, out, up, forth, upper_len, fore_len, chest]
		var best := _clear_cost(want, args)
		for round in CLEAR_ROUNDS:
			if best <= _clear_quiet(want) and want == Vector3i.ZERO:
				break
			var from_want := want
			for step: Vector3i in CLEAR_STEPS:
				var next := from_want + step
				if absi(next.x) > CLEAR_TURN_STEPS or next.y < 0 or next.y > pushes or next.z < 0 or next.z > forths:
					continue
				var cost := _clear_cost(next, args)
				if cost < best - 0.0001:
					best = cost
					want = next
			if want == from_want:
				break
		_clear_want[which] = want
	var eased: Vector3 = _clear_now[which]
	var goal := Vector3(want.x * clear_turn_step, want.y * clear_push_step, want.z * clear_forth_step)
	eased = Vector3(move_toward(eased.x, goal.x, clear_turn_rate * dt), move_toward(eased.y, goal.y, clear_push_rate * dt),
			move_toward(eased.z, goal.z, clear_forth_rate * dt))
	_clear_now[which] = eased
	if not on or eased.is_zero_approx():
		return
	# The reach takes the whole arm over, from where it would have been.
	if eased.z > 0.0:
		var collar_pose := skeleton.get_bone_global_pose(collar)
		var turn := Basis(up, forth * eased.z)
		skeleton.set_bone_global_pose(collar, Transform3D(turn * collar_pose.basis, collar_pose.origin))
		shoulder = collar_pose.origin + turn * (shoulder - collar_pose.origin)
	var to_hand: Vector3 = hand + out * eased.y * unit
	if to_hand.distance_to(shoulder) > _clear_reach:
		to_hand = shoulder + (to_hand - shoulder).normalized() * _clear_reach
	var line := (to_hand - shoulder).normalized() if to_hand.distance_to(shoulder) > 0.0001 else Vector3.DOWN
	var from := skeleton.global_transform
	pole_node.global_position = from * (shoulder + (pole - shoulder).rotated(line, eased.x))
	if not on_handle:
		target.global_position = from * to_hand
	ik.influence = 1.0


## What arm pose `want` (steps of pole turn, hand out, shoulder forward)
## costs: mostly how deep it is in the trunk, then how far it is from the
## arm as it was asked for, so it eases back once it is clear.
func _clear_cost(want: Vector3i, args: Array) -> float:
	var shoulder: Vector3 = args[0]
	var root: Vector3 = args[1]
	var hand: Vector3 = args[2]
	var pole: Vector3 = args[3]
	var unit := _unit()
	if want.z > 0:
		shoulder = root + (shoulder - root).rotated(args[5], float(args[6]) * want.z * clear_forth_step)
	var to: Vector3 = hand + (args[4] as Vector3) * want.y * clear_push_step * unit
	if to.distance_to(shoulder) > _clear_reach:
		to = shoulder + (to - shoulder).normalized() * _clear_reach
	var line := (to - shoulder).normalized() if to.distance_to(shoulder) > 0.0001 else Vector3.DOWN
	var turned := shoulder + (pole - shoulder).rotated(line, want.x * clear_turn_step)
	var depth := _arm_depth(shoulder, to, turned, args[7], args[8], args[9]) / unit
	return maxf(depth, 0.0) * 10.0 + _clear_quiet(want)


## What `want` costs for moving the arm at all.
func _clear_quiet(want: Vector3i) -> float:
	return absi(want.x) * clear_turn_step * 0.01 + want.y * clear_push_step * 0.1 + want.z * clear_forth_step * 0.02


## How far (the skeleton's space) the chest has gone from where it stands
## at the ready: a step in drops the hips and leans the chest into the cut
## (`Locomotion._sink`), and a hand reached for in the actor's frame would
## be left behind in it. The weapon hand rides it while it reaches.
func _ride(held: float) -> Vector3:
	var now := skeleton.get_bone_global_pose(_chest)
	var dt := maxf(_clear_dt, 1.0 / 240.0)
	var ready := _weight <= 0.05 and absf(_pose().footwork) < 0.01
	if not _ride_set:
		_ride_base = now
		_ride_set = true
	elif ready:
		_ride_base = _ride_base.interpolate_with(now, 1.0 - exp(-8.0 * dt))
	return (now.origin - _ride_base.origin) * held


## A free off hand (its guard) rides the chest whole, turn and all, from
## the weapon hand's reckoning this frame: `at` carried with it.
func _ride_off(at: Vector3, held: float) -> Vector3:
	if not _ride_set:
		return at
	var moved := skeleton.get_bone_global_pose(_chest) * _ride_base.affine_inverse()
	return at.lerp(moved * at, held)


## Metres in the skeleton's own space (the model is scaled to the body).
func _unit() -> float:
	var scale := skeleton.global_basis.get_scale().y if skeleton != null else 1.0
	return 1.0 / scale if scale > 0.0001 else 1.0

