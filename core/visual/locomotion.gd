extends Node
## Makes a model's legs agree with how its actor is really moving. Owned by
## the actor's skin, which asks `choose` each frame which clip to play.
##
## Every walk or run clip is measured once from its own feet: the speed and
## direction a planted foot slides along the ground is how fast, and which
## way, the clip carries the body. Playing it at actual speed divided by
## that speed keeps the feet planted, so strides match speed. The clip whose
## direction is nearest the way the actor is going is picked (forward,
## backward, left, right, or a forward clip played in reverse), and the
## lower body turns by whatever angle is left over, while the spine turns
## back so the chest and arms keep facing the aim.
##
## Faster than a relaxed run, the stride lengthens instead of the legs only
## spinning quicker: the leg swing is stretched about its average pose and the
## body leans in, which is the sprint. A slide (`Actor.crouch`) bends the model
## into a slide pose over whatever clip is playing.
##
## Standing still with a gun held low, the legs and hips take their pose from
## a relaxed stand (`stand_legs`) instead of the gun clip's own wide stance,
## so the feet stay planted side by side while the arms keep the gun.
##
## Everything is read from the actor's velocity, which is the same on every
## machine: the server's own, a predicted local player, or a remote player
## whose velocity arrives with each state. Nothing here feeds back into the
## simulation.

const WeaponArm := preload("res://core/visual/weapon_arm.gd")

## Clips used for each pace. A key missing from the skin is skipped.
const WALK_KEYS: Array[String] = ["walk"]
const RUN_KEYS: Array[String] = ["run", "run_back", "run_left", "run_right", "move_gun"]

var actor: Actor
var skeleton: Skeleton3D

## Below this speed (m/s) the actor is standing.
var move_threshold := 0.4
## The walk clip is used up to this many times its own speed; above it, a run.
var walk_ceiling := 1.6
## Speeds used when a clip's feet cannot be measured, in m/s at playback 1.
var fallback_speed := {"walk": 2.5, "run": 7.0, "move_gun": 7.0}
## The playback speed range. Within it the feet stay planted.
var min_playback := 0.3
var max_playback := 2.6
## Playing a clip backwards costs this much (radians) when picking one, so a
## real clip for that direction wins when there is one.
var reverse_cost := 0.45
## The clip being played keeps playing unless another fits this much better
## (radians), so a heading on the border does not flicker between two.
var stickiness := 0.15
## The most the lower body turns from the aim, in radians.
var max_twist := deg_to_rad(80.0)
## How quickly the lower body turns, and how quickly the gun-holding upper
## body blends in and out (per second).
var twist_rate := 10.0
var overlay_rate := 8.0
## How quickly the velocity the legs follow catches up with the actor's. Online
## states land a few times a second; this hides the steps between them.
var velocity_follow := 14.0
## Above this playback speed a run lengthens its stride rather than spin the
## legs faster, up to `max_stride` times the clip's own stride.
var relaxed_cadence := 1.6
var max_stride := 1.7
## How much of the extra stride also lifts the feet higher.
var stride_lift := 0.6
## How far the body leans into the longest stride, in radians.
var sprint_lean := 0.25
var stride_rate := 3.0
## The slide pose: how far the hips drop (m) and the body leans back (radians),
## and where each leg points, in the actor's space along the slide (x right,
## y up, z back). The lead leg reaches out in front; the trailing one folds under.
var slide_drop := 0.5
var slide_lean := 0.18
var slide_lead_thigh := Vector3(0.05, -0.45, -0.9)
var slide_lead_shin := Vector3(0.0, -0.3, -0.95)
var slide_trail_thigh := Vector3(-0.1, -0.85, -0.5)
var slide_trail_shin := Vector3(0.0, -0.4, 0.9)

## Riding a vehicle the body sits on it: hips on the seat, leaning forward,
## hands on the grips and feet on the pegs (the vehicle's `seat_point`,
## `grip_points` and `peg_points`). How high the hip bone sits above the
## seat, where the ankle and wrist sit from a peg and a grip (vehicle frame,
## x out to that side, y up, z back), which way knees and elbows point, how
## far the head tips up to look ahead (share of the lean), and how fast the
## pose comes and goes (per second).
var ride_hip_height := 0.1
var ride_ankle := Vector3(0.0, 0.09, 0.07)
var ride_wrist := Vector3(0.02, 0.02, 0.07)
var ride_knee := Vector3(0.35, 0.5, -1.0)
var ride_elbow := Vector3(1.0, -0.5, 0.6)
var ride_look_up := 0.75
var ride_rate := 5.0

## How quickly the relaxed-stand legs blend in and out (per second).
var stand_legs_rate := 4.0

## Clip key -> how the clip moves the body at playback speed 1, in the
## actor's space (x right, z back), m/s.
var gaits := {}
## The velocity the legs follow, in the actor's space.
var velocity := Vector3.ZERO
## How far the lower body is turned now and is turning to, in radians,
## positive toward the actor's left.
var twist := 0.0
var twist_target := 0.0
## Arms and head from the gun-holding run, for running any other way with a gun.
var overlay := false
var overlay_phase := 0.0
var overlay_weight := 0.0
## How much longer the stride is than the clip's own, now and wanted.
var stride := 1.0
var stride_target := 1.0
## The vehicle being ridden (null on foot), set by the skin each frame, and
## how far into the riding pose the body is. `ride_hands` is how much each
## hand (left, right) wants its grip; `ride_turn` turns the head, radians
## toward the left, so the rider looks where they aim.
var ride: Node3D
var ride_weight := 0.0
var ride_hands := Vector2.ONE
var ride_turn := 0.0
## Where the right wrist goes when it is off its grip holding a gun (skeleton
## space is worked out here; this is global), or null to leave the clip's arm.
var ride_gun_wrist: Variant = null
## The vehicle the pose is for, kept while the pose fades out after getting
## off, and how much each hand is on its grip now.
var _ride_on: Node3D
var _hands := Vector2.ZERO
## The clip playing now (its name in the model), whose average pose the
## stride is stretched about.
var current_anim := ""
## Whether the legs should take the relaxed stand now, and how far they have.
var stand_legs := false
var stand_legs_weight := 0.0

var _roots: Array[int] = []
var _spine: Array[int] = []
var _overlay_anim: Animation
## Bone -> rotation track in `_overlay_anim`.
var _overlay_tracks := {}
## Leg bones whose swing is stretched, and the feet moved with them.
var _legs: Array[int] = []
var _feet: Array[int] = []
## Clip name -> {bone: its average rotation (legs) or position (feet)}.
var _means := {}
## For the slide: [thigh, shin, foot] for the lead and trailing leg, and where
## each foot sits on its shin in the rest pose.
var _lead: Array[int] = []
var _trail: Array[int] = []
var _foot_on_shin := {}
## Upper arm, forearm and wrist, left then right, for the riding pose; the neck.
var _arms: Array = []
var _neck := -1
var _hip_name := ""
## The relaxed stand, and its tracks for the bones below the spine:
## [bone, track, type].
var _stand_anim: Animation
var _stand_tracks: Array = []
var _stand_time := 0.0


## `def` is the skin's entry in `Look.SKINS`, `anims` maps keys to the clips
## found in the model. Works without a skeleton: clips then get the fallback
## speeds and nothing turns.
func setup(def: Dictionary, player: AnimationPlayer, anims: Dictionary) -> void:
	for key: String in WALK_KEYS + RUN_KEYS:
		if not anims.has(key):
			continue
		var travel := Vector3.ZERO
		if skeleton and player:
			travel = measure(player.get_animation(anims[key]), def.get("feet", ["Foot.L", "Foot.R"]))
		if travel.length() < move_threshold and fallback_speed.has(key):
			travel = Vector3(0.0, 0.0, -fallback_speed[key])
		if travel.length() >= move_threshold:
			gaits[key] = travel
	if skeleton == null:
		return
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_parent(bone) < 0:
			_roots.append(bone)
	for bone_name: String in def.get("spine", []):
		if skeleton.find_bone(bone_name) >= 0:
			_spine.append(skeleton.find_bone(bone_name))
	_lead = _bones(def.get("lead_leg", []))
	_trail = _bones(def.get("trail_leg", []))
	for leg in [_lead, _trail]:
		if leg.size() == 3:
			_legs.append_array(leg.slice(0, 2))
			_feet.append(leg[2])
			_foot_on_shin[leg[2]] = skeleton.get_bone_global_rest(leg[1]).affine_inverse() \
					* skeleton.get_bone_global_rest(leg[2])
	for chain_key: String in ["off_arm", "arm"]:
		var chain := _bones(def.get(chain_key, []))
		_arms.append(chain if chain.size() == 3 else ([] as Array[int]))
	_neck = skeleton.find_bone(def.get("neck", ""))
	_hip_name = def.get("hip_bone", "")
	if player:
		for key: String in gaits:
			if anims.has(key) and not _means.has(anims[key]):
				_means[anims[key]] = _average_pose(player.get_animation(anims[key]))
	if player and anims.has("move_gun") and not _spine.is_empty():
		_overlay_anim = player.get_animation(anims["move_gun"])
		for track in _overlay_anim.get_track_count():
			if _overlay_anim.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := skeleton.find_bone(String(_overlay_anim.track_get_path(track)).get_slice(":", 1))
			# Only the shoulders, arms and head: the spine stays the strafe
			# clip's own, which keeps the chest facing forward over the hips.
			if bone >= 0 and _is_under(bone, _spine[_spine.size() - 1]):
				_overlay_tracks[bone] = track

	if player and anims.has("stand_legs") and not _spine.is_empty():
		_stand_anim = player.get_animation(anims["stand_legs"])
		for track in _stand_anim.get_track_count():
			var type := _stand_anim.track_get_type(track)
			if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
				continue
			var bone := skeleton.find_bone(String(_stand_anim.track_get_path(track)).get_slice(":", 1))
			if bone >= 0 and bone != _spine[0] and not _is_under(bone, _spine[0]):
				_stand_tracks.append([bone, track, type])

	# First, so everything after works from the planted legs.
	var stand := WeaponArm.Hook.new()
	stand.name = "StandLegs"
	stand.run = _stand_legs
	skeleton.add_child(stand)
	# The arm's hooks are added after these, so it reaches from where the
	# turned body has put the shoulders.
	var upper := WeaponArm.Hook.new()
	upper.name = "GunUpperBody"
	upper.run = _overlay_upper
	skeleton.add_child(upper)
	var stretch := WeaponArm.Hook.new()
	stretch.name = "SprintStride"
	stretch.run = _stretch_stride
	skeleton.add_child(stretch)
	var legs := WeaponArm.Hook.new()
	legs.name = "LegsToTravel"
	legs.run = _turn_lower
	skeleton.add_child(legs)
	var slide := WeaponArm.Hook.new()
	slide.name = "SlidePose"
	slide.run = _slide_pose
	skeleton.add_child(slide)
	var seated := WeaponArm.Hook.new()
	seated.name = "RidePose"
	seated.run = _ride_pose
	skeleton.add_child(seated)


func _bones(names: Array) -> Array[int]:
	var out: Array[int] = []
	for bone_name: String in names:
		if skeleton.find_bone(bone_name) < 0:
			return []
		out.append(skeleton.find_bone(bone_name))
	return out


## The average rotation of each leg bone and position of each foot over a clip.
func _average_pose(anim: Animation) -> Dictionary:
	var out := {}
	if anim == null or anim.length <= 0.0:
		return out
	var tracks := _tracks_by_bone(anim)
	var steps := 32
	for bone in _legs + _feet:
		var own: Dictionary = tracks.get(bone, {})
		if bone in _legs and own.has(Animation.TYPE_ROTATION_3D):
			var sum := Vector4.ZERO
			var first := Quaternion.IDENTITY
			for i in steps:
				var q: Quaternion = anim.rotation_track_interpolate(own[Animation.TYPE_ROTATION_3D], anim.length * i / steps)
				if i == 0:
					first = q
				elif q.dot(first) < 0.0:
					q = -q
				sum += Vector4(q.x, q.y, q.z, q.w)
			sum = sum.normalized()
			out[bone] = Quaternion(sum.x, sum.y, sum.z, sum.w)
		elif bone in _feet and own.has(Animation.TYPE_POSITION_3D):
			var at := Vector3.ZERO
			for i in steps:
				at += anim.position_track_interpolate(own[Animation.TYPE_POSITION_3D], anim.length * i / steps)
			out[bone] = at / steps
	return out


## How a clip moves the body at playback speed 1, in the actor's space, read
## from its feet: whichever foot is on the ground slides back under the body
## as fast as the body goes. Zero if the feet can't be found or don't slide.
func measure(anim: Animation, feet: Array) -> Vector3:
	if anim == null or skeleton == null or anim.length <= 0.0:
		return Vector3.ZERO
	var foot_bones: Array[int] = []
	for foot: String in feet:
		if skeleton.find_bone(foot) >= 0:
			foot_bones.append(skeleton.find_bone(foot))
	if foot_bones.is_empty():
		return Vector3.ZERO
	var tracks := _tracks_by_bone(anim)
	# Skeleton space to the actor's: scale, the model's half turn, all of it.
	var to_actor := actor.global_basis.inverse() * skeleton.global_basis
	var steps := 64
	var dt := anim.length / steps
	var spots := []
	var low := INF
	var high := -INF
	for foot in foot_bones:
		var path: Array[Vector3] = []
		for i in steps + 1:
			var at := to_actor * _bone_position(foot, anim, tracks, i * dt)
			path.append(at)
			low = minf(low, at.y)
			high = maxf(high, at.y)
		spots.append(path)
	if high - low < 0.0001:
		return Vector3.ZERO
	# A foot is on the ground while it is near the lowest any foot gets.
	var ground := low + (high - low) * 0.1
	var xs: Array[float] = []
	var zs: Array[float] = []
	for path: Array[Vector3] in spots:
		for i in steps:
			if maxf(path[i].y, path[i + 1].y) > ground:
				continue
			var slide := (path[i + 1] - path[i]) / dt
			xs.append(slide.x)
			zs.append(slide.z)
	if xs.is_empty():
		return Vector3.ZERO
	xs.sort()
	zs.sort()
	# The median ignores the moment a foot lands or lifts off.
	var mid := xs.size() >> 1
	return -Vector3(xs[mid], 0.0, zs[mid])


func _tracks_by_bone(anim: Animation) -> Dictionary:
	var out := {}
	for track in anim.get_track_count():
		var type := anim.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var bone := skeleton.find_bone(String(anim.track_get_path(track)).get_slice(":", 1))
		if bone < 0:
			continue
		if not out.has(bone):
			out[bone] = {}
		out[bone][type] = track
	return out


## Where a bone is in skeleton space at a time in a clip, from the clip's
## tracks and the rest pose for anything the clip leaves alone.
func _bone_position(bone: int, anim: Animation, tracks: Dictionary, time: float) -> Vector3:
	var at := Transform3D.IDENTITY
	var up := bone
	while up >= 0:
		var rest := skeleton.get_bone_rest(up)
		var own: Dictionary = tracks.get(up, {})
		var position: Vector3 = anim.position_track_interpolate(own[Animation.TYPE_POSITION_3D], time) \
				if own.has(Animation.TYPE_POSITION_3D) else rest.origin
		var rotation: Quaternion = anim.rotation_track_interpolate(own[Animation.TYPE_ROTATION_3D], time) \
				if own.has(Animation.TYPE_ROTATION_3D) else rest.basis.get_rotation_quaternion()
		var size: Vector3 = anim.scale_track_interpolate(own[Animation.TYPE_SCALE_3D], time) \
				if own.has(Animation.TYPE_SCALE_3D) else rest.basis.get_scale()
		at = Transform3D(Basis(rotation) * Basis.from_scale(size), position) * at
		up = skeleton.get_bone_parent(up)
	return at.origin


## Which clip to play for a velocity in the actor's space, or {} to stand.
## Returns {"key", "speed" (playback speed, negative to play it backwards),
## "twist" (radians to turn the lower body, positive toward the left)}.
## `armed` means a gun is up, which runs forward with the gun-holding clip.
## `current` and `current_sign` are what is playing now.
func choose(local_velocity: Vector3, armed: bool, current := "", current_sign := 1.0) -> Dictionary:
	var flat := Vector3(local_velocity.x, 0.0, local_velocity.z)
	var speed := flat.length()
	if speed < move_threshold or gaits.is_empty():
		return {}
	var walking: bool = gaits.has("walk") and speed < gaits["walk"].length() * walk_ceiling
	var keys := WALK_KEYS if walking else RUN_KEYS
	var candidates: Array[String] = []
	for key: String in keys:
		if not gaits.has(key):
			continue
		if key == "move_gun" and not armed:
			continue
		if key == "run" and armed and gaits.has("move_gun"):
			continue
		candidates.append(key)
	if candidates.is_empty():
		candidates.assign(gaits.keys().filter(func(k: String) -> bool: return armed or k != "move_gun"))
		if candidates.is_empty():
			candidates.assign(gaits.keys())
	var want := heading(flat)
	var best := {}
	var best_cost := INF
	for key in candidates:
		for sign: float in [1.0, -1.0]:
			var travel: Vector3 = gaits[key] * sign
			var off := wrapf(want - heading(travel), -PI, PI)
			var cost := absf(off) + (reverse_cost if sign < 0.0 else 0.0)
			if key == current and sign == current_sign:
				cost -= stickiness
			if cost < best_cost:
				best_cost = cost
				best = {"key": key, "sign": sign, "off": off}
	var native: float = gaits[best["key"]].length()
	# A run lengthens its stride past a relaxed cadence; a walk never does.
	var reach := 1.0 if walking or _means.is_empty() else clampf(speed / (native * relaxed_cadence), 1.0, max_stride)
	var playback := clampf(speed / (native * reach), min_playback, max_playback)
	return {"key": best["key"], "speed": playback * best["sign"], "stride": reach,
		"twist": clampf(best["off"], -max_twist, max_twist)}


## The angle of a direction in the actor's space: 0 straight ahead, positive
## toward the left.
static func heading(v: Vector3) -> float:
	return atan2(-v.x, -v.z)


## Each frame, before `choose`: follows the actor's velocity and eases the
## lower body and the gun-holding upper body toward what was last chosen.
func update(delta: float) -> void:
	if actor == null:
		return
	var local := actor.global_basis.orthonormalized().inverse() * actor.velocity
	velocity = velocity.lerp(local, 1.0 - exp(-velocity_follow * delta))
	twist = move_toward(twist, twist_target, twist_rate * delta * maxf(absf(twist_target - twist), 0.15))
	overlay_weight = move_toward(overlay_weight, 1.0 if overlay and not _overlay_tracks.is_empty() else 0.0,
			overlay_rate * delta)
	stride = move_toward(stride, stride_target, stride_rate * delta)
	stand_legs_weight = move_toward(stand_legs_weight, 1.0 if stand_legs and not _stand_tracks.is_empty() else 0.0,
			stand_legs_rate * delta)
	if _stand_anim and _stand_anim.length > 0.0:
		_stand_time = fposmod(_stand_time + delta, _stand_anim.length)
	if ride != null and is_instance_valid(ride):
		_ride_on = ride
	if _ride_on != null and not is_instance_valid(_ride_on):
		_ride_on = null
	var riding := ride != null and _ride_on != null
	ride_weight = move_toward(ride_weight, 1.0 if riding else 0.0, ride_rate * delta)
	_hands = _hands.move_toward(ride_hands if riding else Vector2.ZERO, ride_rate * delta)
	if ride_weight <= 0.0:
		_ride_on = null


## Puts the hips and legs in the relaxed stand, under whatever the upper body
## is doing.
func _stand_legs() -> void:
	if stand_legs_weight <= 0.0 or _stand_anim == null:
		return
	for entry: Array in _stand_tracks:
		var bone: int = entry[0]
		if entry[2] == Animation.TYPE_ROTATION_3D:
			var q := _stand_anim.rotation_track_interpolate(entry[1], _stand_time)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(q, stand_legs_weight))
		else:
			var at := _stand_anim.position_track_interpolate(entry[1], _stand_time)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(at, stand_legs_weight))


## Lengthens the stride: each leg bone swings further from its average pose
## in the clip, and each foot travels further from its average spot, so a
## planted foot slides back `stride` times as fast. The body leans in.
func _stretch_stride() -> void:
	if stride <= 1.001 or not _means.has(current_anim):
		return
	var means: Dictionary = _means[current_anim]
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var up := (to_skeleton * Vector3.UP).normalized()
	for bone in _feet:
		if not means.has(bone):
			continue
		var parent := skeleton.get_bone_parent(bone)
		var local_up := up if parent < 0 else (skeleton.get_bone_global_pose(parent).basis.inverse() * up).normalized()
		var mean: Vector3 = means[bone]
		var off := skeleton.get_bone_pose_position(bone) - mean
		var lift := local_up * local_up.dot(off)
		skeleton.set_bone_pose_position(bone, mean + (off - lift) * stride + lift * (1.0 + (stride - 1.0) * stride_lift))
	# The legs reach for where the feet have gone.
	for leg in [_lead, _trail]:
		if leg.size() == 3:
			_reach(leg, skeleton.get_bone_global_pose(leg[2]).origin)
	if not _spine.is_empty():
		var lean := sprint_lean * clampf((stride - 1.0) / maxf(max_stride - 1.0, 0.01), 0.0, 1.0)
		var right := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.RIGHT).normalized()
		var pose := skeleton.get_bone_global_pose(_spine[0])
		pose.basis = Basis(right, -lean) * pose.basis
		skeleton.set_bone_global_pose(_spine[0], pose)


## Bends the model into a slide as the actor crouches: the hips drop and lean
## back, the lead leg reaches forward along the slide, the trailing leg folds
## under, and each foot is put back on the end of its shin.
func _slide_pose() -> void:
	var weight := actor.crouch if actor else 0.0
	if weight <= 0.001:
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var along := to_skeleton * Basis(Vector3.UP, twist)
	var up := (along * Vector3.UP).normalized()
	var right := (along * Vector3.RIGHT).normalized()
	var meter := 1.0 / skeleton.global_basis.get_scale().y
	var pivot := skeleton.global_transform.affine_inverse() * actor.global_position
	var drop := Transform3D(Basis.IDENTITY, pivot - up * slide_drop * meter * weight) \
			* Transform3D(Basis(right, slide_lean * weight), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	for bone in _roots:
		skeleton.set_bone_global_pose(bone, drop * skeleton.get_bone_global_pose(bone))
	for pair in [[_lead, slide_lead_thigh, slide_lead_shin], [_trail, slide_trail_thigh, slide_trail_shin]]:
		var leg: Array[int] = pair[0]
		if leg.size() != 3:
			continue
		_point_bone(leg[0], (along * pair[1]).normalized(), weight, skeleton.get_bone_rest(leg[1]).origin.normalized())
		_point_bone(leg[1], (along * pair[2]).normalized(), weight, (_foot_on_shin[leg[2]].origin as Vector3).normalized())
		var foot := skeleton.get_bone_global_pose(leg[2])
		var on_shin: Transform3D = skeleton.get_bone_global_pose(leg[1]) * _foot_on_shin[leg[2]]
		skeleton.set_bone_global_pose(leg[2], foot.interpolate_with(on_shin, weight))


## Sits the body on the vehicle being ridden: the hips go onto the seat, the
## spine leans forward, the feet reach the pegs and the hands the grips, and
## the head comes up to look ahead. The skin has already turned the whole
## model to face along the vehicle and lean with it. Runs after the slide and
## before the weapon arm, so a held weapon still gets its hold and swings.
func _ride_pose() -> void:
	if ride_weight <= 0.0 or _ride_on == null or not is_instance_valid(_ride_on) or not _ride_on.is_inside_tree():
		return
	var w := smoothstep(0.0, 1.0, ride_weight)
	var model := _ride_on.get_node_or_null("Model") as Node3D
	var frame: Transform3D = model.global_transform if model else _ride_on.global_transform
	# From the vehicle's frame to the skeleton's (scale and all).
	var to_skeleton := skeleton.global_transform.affine_inverse() * frame
	var right := (to_skeleton.basis * Vector3.RIGHT).normalized()
	var up := (to_skeleton.basis * Vector3.UP).normalized()

	var hips := skeleton.find_bone(_hip_name)
	if hips >= 0:
		var seat: Vector3 = _ride_on.get("seat_point")
		var want := to_skeleton * (seat + Vector3(0.0, ride_hip_height, 0.0))
		var shift := (want - skeleton.get_bone_global_pose(hips).origin) * w
		for bone in _roots:
			var pose := skeleton.get_bone_global_pose(bone)
			pose.origin += shift
			skeleton.set_bone_global_pose(bone, pose)
	var lean: float = _ride_on.get("rider_lean")
	if not _spine.is_empty():
		var bend := Basis(right, -lean * w / _spine.size())
		for bone in _spine:
			var pose := skeleton.get_bone_global_pose(bone)
			pose.basis = bend * pose.basis
			skeleton.set_bone_global_pose(bone, pose)

	var pegs: Array = _ride_on.get("peg_points")
	for leg in [_lead, _trail]:
		if leg.size() != 3 or pegs.size() != 2:
			continue
		var side := _side_of(leg[0])
		var peg: Vector3 = pegs[0 if side < 0.0 else 1]
		var ankle := to_skeleton * (peg + Vector3(ride_ankle.x * side, ride_ankle.y, ride_ankle.z))
		var knee := to_skeleton.basis * Vector3(ride_knee.x * side, ride_knee.y, ride_knee.z)
		_bend(leg, _foot_on_shin[leg[2]].origin, ankle, knee, w)
		var foot := skeleton.get_bone_global_pose(leg[2])
		var on_shin: Transform3D = skeleton.get_bone_global_pose(leg[1]) * _foot_on_shin[leg[2]]
		skeleton.set_bone_global_pose(leg[2], foot.interpolate_with(on_shin, w))

	var grips: Array = _ride_on.get("grip_points")
	for i in _arms.size():
		var arm: Array[int] = _arms[i]
		var hand := _hands.x if i == 0 else _hands.y
		var hold := w * hand
		var gun_hand := i == 1 and ride_gun_wrist != null
		if gun_hand:
			# A gun held out one-handed toward the aim, the other hand on the bar.
			hold = w
		if arm.size() != 3 or grips.size() != 2 or hold <= 0.001:
			continue
		var side := _side_of(arm[0])
		var grip: Vector3 = grips[0 if side < 0.0 else 1]
		var wrist := to_skeleton * (grip + Vector3(ride_wrist.x * side, ride_wrist.y, ride_wrist.z))
		if gun_hand:
			var aim: Vector3 = skeleton.global_transform.affine_inverse() * (ride_gun_wrist as Vector3)
			wrist = aim.lerp(wrist, hand)
		var elbow := to_skeleton.basis * Vector3(ride_elbow.x * side, ride_elbow.y, ride_elbow.z)
		_bend(arm, skeleton.get_bone_rest(arm[2]).origin, wrist, elbow, hold)

	if _neck >= 0:
		var pose := skeleton.get_bone_global_pose(_neck)
		pose.basis = Basis(up, ride_turn * w) * Basis(right, lean * ride_look_up * w) * pose.basis
		skeleton.set_bone_global_pose(_neck, pose)


## How far each hand (left, right) is round its grip now.
func grip_hold() -> Vector2:
	return _hands * smoothstep(0.0, 1.0, ride_weight)


## -1 for a bone on the left of the body (".L"), 1 otherwise.
func _side_of(bone: int) -> float:
	return -1.0 if skeleton.get_bone_name(bone).ends_with(".L") else 1.0


## Bends a [root, middle, end] limb so the end reaches `target` (skeleton
## space), the middle joint bowing toward `pole`. `end_at` is where the end
## sits in the middle bone's space, so this works for the human rig's feet,
## which are not children of the shin. Leaves the end bone itself alone.
func _bend(limb: Array[int], end_at: Vector3, target: Vector3, pole: Vector3, weight: float) -> void:
	var root := skeleton.get_bone_global_pose(limb[0]).origin
	var middle := skeleton.get_bone_global_pose(limb[1])
	var scale := middle.basis.get_scale().y
	var a := (middle.origin - root).length()
	var b := end_at.length() * scale
	var to := target - root
	if a < 0.0001 or b < 0.0001 or to.length() < 0.0001:
		return
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := to.normalized()
	var bow := pole - dir * dir.dot(pole)
	if bow.length() < 0.0001:
		return
	bow = bow.normalized()
	var cos_root := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var joint := root + dir * cos_root * a + bow * sqrt(1.0 - cos_root * cos_root) * a
	_point_bone(limb[0], (joint - root).normalized(), weight, skeleton.get_bone_rest(limb[1]).origin.normalized())
	var joint_now := skeleton.get_bone_global_pose(limb[1]).origin
	_point_bone(limb[1], (root + dir * d - joint_now).normalized(), weight, end_at.normalized())


## Bends a [thigh, shin, foot] leg so the ankle lands on `target` (skeleton
## space), keeping the knee bent the way it is now. The foot keeps its turn.
func _reach(leg: Array[int], target: Vector3) -> void:
	var foot := skeleton.get_bone_global_pose(leg[2])
	var hip := skeleton.get_bone_global_pose(leg[0]).origin
	var knee_now := skeleton.get_bone_global_pose(leg[1]).origin
	var thigh_axis := skeleton.get_bone_rest(leg[1]).origin
	var shin_axis: Vector3 = _foot_on_shin[leg[2]].origin
	var scale := skeleton.get_bone_global_pose(leg[0]).basis.get_scale().y
	var a := thigh_axis.length() * scale
	var b := shin_axis.length() * scale
	var to := target - hip
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := to.normalized()
	var bend := knee_now - hip
	var pole := (bend - dir * dir.dot(bend))
	if pole.length() < 0.0001:
		return
	pole = pole.normalized()
	var cos_hip := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var knee := hip + dir * cos_hip * a + pole * sqrt(1.0 - cos_hip * cos_hip) * a
	_point_bone(leg[0], (knee - hip).normalized(), 1.0, thigh_axis.normalized())
	_point_bone(leg[1], (hip + dir * d - knee).normalized(), 1.0, shin_axis.normalized())
	foot.origin = (skeleton.get_bone_global_pose(leg[1]) * _foot_on_shin[leg[2]]).origin
	skeleton.set_bone_global_pose(leg[2], foot)


## Turns a bone so the direction `axis` (in its own space; +Y, as glTF bones
## point, by default) points along `dir`.
func _point_bone(bone: int, dir: Vector3, weight: float, axis := Vector3.UP) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var now := (pose.basis * axis).normalized()
	if now.dot(dir) > 0.9999:
		return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(now, dir), weight)
	pose.basis = Basis(turn) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)


## Holds the gun up while the legs run some other way: the spine and arms
## take their pose from the gun-holding run at the same point in the stride.
func _overlay_upper() -> void:
	if overlay_weight <= 0.0 or _overlay_anim == null:
		return
	var time := fposmod(overlay_phase, 1.0) * _overlay_anim.length
	for bone: int in _overlay_tracks:
		var pose: Quaternion = _overlay_anim.rotation_track_interpolate(_overlay_tracks[bone], time)
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(pose, overlay_weight))


## Turns the whole model about the actor's middle toward where it is going,
## then turns the spine back so the chest still faces the aim.
func _turn_lower() -> void:
	if absf(twist) < 0.001 or actor == null:
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var up := (to_skeleton * Vector3.UP).normalized()
	var pivot := skeleton.global_transform.affine_inverse() * actor.global_position
	var turn := Transform3D(Basis(up, twist), Vector3.ZERO)
	var about := Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot)
	for bone in _roots:
		skeleton.set_bone_global_pose(bone, about * skeleton.get_bone_global_pose(bone))
	if _spine.is_empty():
		return
	var back := Basis(up, -twist / _spine.size())
	for bone in _spine:
		var pose := skeleton.get_bone_global_pose(bone)
		pose.basis = back * pose.basis
		skeleton.set_bone_global_pose(bone, pose)


func _is_under(bone: int, ancestor: int) -> bool:
	var up := skeleton.get_bone_parent(bone)
	while up >= 0:
		if up == ancestor:
			return true
		up = skeleton.get_bone_parent(up)
	return false
