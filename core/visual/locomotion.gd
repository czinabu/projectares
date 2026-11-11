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

## Clip key -> how the clip moves the body at playback speed 1, in the
## actor's space (x right, z back), m/s.
var gaits := {}
## The velocity the legs follow, in the actor's space.
var velocity := Vector3.ZERO
## How far the lower body is turned now and is turning to, in radians,
## positive toward the actor's left.
var twist := 0.0
var twist_target := 0.0
## Upper body from the gun-holding run, for running any other way with a gun.
var overlay := false
var overlay_phase := 0.0
var overlay_weight := 0.0

var _roots: Array[int] = []
var _spine: Array[int] = []
var _overlay_anim: Animation
## Bone -> rotation track in `_overlay_anim`.
var _overlay_tracks := {}


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
	if player and anims.has("move_gun") and not _spine.is_empty():
		_overlay_anim = player.get_animation(anims["move_gun"])
		for track in _overlay_anim.get_track_count():
			if _overlay_anim.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := skeleton.find_bone(String(_overlay_anim.track_get_path(track)).get_slice(":", 1))
			if bone >= 0 and (bone == _spine[0] or _is_under(bone, _spine[0])):
				_overlay_tracks[bone] = track

	# The arm's hooks are added after these, so it reaches from where the
	# turned body has put the shoulders.
	var upper := WeaponArm.Hook.new()
	upper.name = "GunUpperBody"
	upper.run = _overlay_upper
	skeleton.add_child(upper)
	var legs := WeaponArm.Hook.new()
	legs.name = "LegsToTravel"
	legs.run = _turn_lower
	skeleton.add_child(legs)


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
	var walking := gaits.has("walk") and speed < gaits["walk"].length() * walk_ceiling
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
	var playback := clampf(speed / native, min_playback, max_playback)
	return {"key": best["key"], "speed": playback * best["sign"],
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
