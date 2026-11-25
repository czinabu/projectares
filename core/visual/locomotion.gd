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
## body leans in, which is the sprint. A slide (`Actor.slide_low`) bends the model
## into a slide pose over whatever clip is playing, and a crouch
## (`Actor.crouch`) sinks it onto bent knees the same way a landing squat
## does, over the stand or the walk, feet where the clip puts them.
##
## Standing still with a gun held low or raised, or a blade out, the legs and
## hips take their pose from a relaxed stand (`stand_legs`) instead of the
## clip's own wide stance, so the feet stay planted under the body while the
## arms keep the weapon.
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
## Aiming down sights on the move the spine, shoulders and head hold still:
## their turn follows the gait only over `aim_still_time` seconds, smoothing
## out the stride's swing (by how far the gun is up, `ActionPose.ads`). A
## shouldered gun's arm is near full stretch, and a swinging shoulder left
## the sight short and off the eye line on every back-swing.
var aim_still_time := 0.3
var _still := {}
var _still_delta := 0.0
## The head looks where its owner aims (the crosshair), the same in both
## views and for everyone watching, read from the command (`get_aim_dir`),
## so another player sees where you are looking. The neck takes `look_neck`
## of the turn and the head the rest; it turns no further than `look_reach`
## (radians) side to side from the way the chest faces, and tips back no
## further than `look_up` and down no further than `look_down` from it, so
## a body laid out in flight lifts its head the way a neck can rather than
## folding it back (playtest feedback). `look_follow` smooths the aim a
## little, mostly for remote players whose aim arrives in steps.
var look_reach := deg_to_rad(70.0)
var look_up := deg_to_rad(45.0)
var look_down := deg_to_rad(55.0)
var look_neck := 0.45
var look_follow := 30.0
var look_rate := 5.0
var look_weight := 0.0
## The aim the head follows, in the actor's frame.
var _look_dir := Vector3.FORWARD
var _head := -1
## The way the model faces, in the skeleton's space, and the way the head
## and chest face in their own bones' space at rest.
var _model_ahead := Vector3.ZERO
var _head_ahead := Vector3.ZERO
var _chest_ahead := Vector3.ZERO
var _chest_up := Vector3.ZERO
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
## A landing squat (`squat`, 0..1, set by the skin): how far the hips drop
## (m) and the body tips forward (radians) at a full one. The feet stay put.
var squat_drop := 0.3
var squat_lean := 0.22
var squat := 0.0
## The crouch (`Actor.crouch`): how far the hips drop (m) at a full crouch
## and how far the chest leans forward from the hips (radians); together
## they bring the head down about the eyes' drop (`Actor.crouch_eye_drop`)
## while the knees stay a ready bend, never a kneel. `crouch_lean` tips the
## whole body a little over the knees.
var crouch_drop := 0.3
var crouch_spine_lean := 0.5
var crouch_lean := 0.05
## Crouched the heels come up (radians the foot rolls onto its ball), so the
## ankle never folds flat over the foot; `foot_reach` is how far ahead of the
## ankle bone (m) the ball of the foot is.
var crouch_heel := 0.45
## A fighting stance while a melee weapon is out on the ground (DESIGN.md
## "Melee technique"): the knees bend (the hips drop `fight_drop` m and tip
## `fight_lean` radians forward) and, standing still, the feet stagger,
## the lead foot `fight_stagger` m forward and the trailing one as far
## back, apart by `fight_width` more than they stand, so the body stands ready to move
## rather than at ease. `fight` is how far into it the body is (0..1),
## eased at `fight_rate` a second. View only, from the actor and the weapon
## in hand, so every view agrees.
var fight_drop := 0.05
## Which way a sunk knee bends (`_sink`): forward over the toes, and out by
## this share of that, as knees track the feet.
var knee_out := 0.2
var fight_lean := 0.07
var fight_stagger := 0.13
var fight_width := 0.03
var fight_rate := 4.0
var fight := 0.0
var foot_reach := 0.13
## Crouched, the walk's feet stay this much as far from their average spot
## (a short, careful step), so the bent legs reach them without splaying.
var crouch_step := 0.55
var slide_drop := 0.5
## With the slide's own clips: how fast the drop into it plays (the pack's
## takes 0.83 s; the slide lasts `Actor.slide_time`), how long it takes to
## blend from the run into the drop (s), how fast the rise out plays, and
## the last share of the rise that fades into whatever comes next, so the
## legs pick up their run without a snap.
var slide_in_rate := 1.6
var slide_in_blend := 0.08
var slide_out_rate := 1.3
var slide_out_fade := 0.45
var slide_lean := 0.18
var slide_lead_thigh := Vector3(0.05, -0.45, -0.9)
var slide_lead_shin := Vector3(0.0, -0.3, -0.95)
var slide_trail_thigh := Vector3(-0.1, -0.85, -0.5)
var slide_trail_shin := Vector3(0.0, -0.4, 0.9)
## A skid on the feet (`skid`, the run-out of a fast flight landing, set
## by `ActorSkin`): the hips sink `skid_drop` m, the lead leg is braced out
## ahead nearly straight, the trailing leg bends under the body, and the
## feet stay planted instead of running. It stands in for the slide while
## it shows. Directions are along the travel, as for the slide.
var skid := false
var skid_weight := 0.0
var skid_rate := 9.0
var skid_drop := 0.2
var skid_lead_thigh := Vector3(-0.04, -0.62, -0.78)
var skid_lead_shin := Vector3(0.0, -0.86, -0.51)
var skid_trail_thigh := Vector3(0.06, -0.98, 0.05)
var skid_trail_shin := Vector3(0.0, -0.55, 0.84)
## The back straightens up out of the run against the skid, by this many
## radians at the base of the spine.
var skid_spine_lean := 0.35

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
## Holding the phone up (`ActorCommand.phone`), one-handed in the right hand
## as in life, in the actor's frame: where the phone's grip sits, where the
## right wrist goes (just behind it), which way the elbow bows, and how far
## the head and chest bow to look at it. It is held at the chest, a forearm
## out and a little right of the middle, below the face (Caleb's call: the
## same hold every view sees, never up at the eyes), so the face, the mirror
## and the world ahead stay clear. The left arm hangs by the side
## (`phone_rest`), out of the way of the screen.
var phone_at := Vector3(0.08, 1.35, -0.45)
var phone_wrist := Vector3(0.09, 1.30, -0.38)
var phone_elbow := Vector3(0.45, -1.0, 0.3)
var phone_rest := Vector3(-0.24, 0.92, -0.02)
var phone_rest_elbow := Vector3(-0.3, 0.0, 1.0)
## How far past the wrist (m) the middle of the fist is, where the phone's
## grip passes through it (`core/phone/handheld.gd`).
var phone_palm := 0.085
var phone_look_down := 0.42
var phone_chest := 0.06

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
## Whether the relaxed stand also sets the hips, or only the legs below
## them: a blade keeps its clip's hips, which the swings are tuned on.
var stand_legs_hips := true
## Off the ground on foot (set by the skin): the legs take the pack's jump
## (`anims["air_legs"]`, its legs only, below the hips) over the stand that
## plays under the air, eased in at `air_legs_rate` a second and out the
## same on touchdown, so a running jump does not snap the stride into a
## stand and back. A flight rig's own air poses come after it.
var air_legs := false
var air_legs_weight := 0.0
var air_legs_rate := 7.0
var _air_anim: Animation
var _air_tracks: Array = []
var _air_time := 0.0
## Room for worn armor: each upper arm swings out from the body so the
## elbow sits `arm_clear` m further out (a hanging hand about half again
## as much), past the plates and pouches a frame hangs at the sides. Set
## by whoever dresses the body in armor; 0 without it. The weapon arm's
## reach comes after, so a hand on a gun still finds its grip.
var arm_clear := 0.0
var stand_legs_weight := 0.0
## True while the phone is up; `phone_weight` is how far, read from the
## actor's shared `ActionPose.phone` so every view holds it the same way.
var phone_up := false
var phone_weight := 0.0
## Where the phone is in the right hand now, in the actor's frame; set by
## `phone_pose` (left at `phone_at` on a body without arms).
var phone_in_hand := Vector3.ZERO

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
## The slide's own clips, where a body has them: the drop into it
## (`anims["slide_start"]`), the slide held (`anims["slide"]`, looped) and
## the rise out of it (`anims["slide_exit"]`), each [animation, tracks] with
## tracks [bone, track, type] for the hips, the legs and the spine up to the
## chest, laid over whatever plays in place of the bent pose. The shoulders,
## arms and head stay the clip's under it, so a gun keeps its hold. A body
## with only the held clip snaps into and out of it on `Actor.slide_low`.
var _slide_anim: Animation
var _slide_clips: Array = [[], [], []]
## Where the slide is: `SLIDE_NONE`, dropping in, held or rising out, and how
## far into that part (seconds of its clip).
var _slide_phase := 0
var _slide_time := 0.0
const SLIDE_NONE := 0
const SLIDE_IN := 1
const SLIDE_HOLD := 2
const SLIDE_OUT := 3
## Shivering in the cold (`Actor.shivering`): how far into it the body is
## (eased, so it comes on and goes off gently), the shoulders hunched in by
## `shiver_hunch` radians and the chest trembling by `shiver_shake` at
## `shiver_rate` a second. The neck takes the tremor back, so the head (and
## first person's eyes on it) barely moves. View only, the same body in
## every view, and remote players match from the state.
var shiver := 0.0
var shiver_ease := 0.8
var shiver_hunch := 0.09
var shiver_shake := 0.016
var shiver_rate := 13.0
var _shiver_time := 0.0
## Leaning into a storm's wind (`Raid.weather`, DESIGN.md "Frostline"
## whiteouts): on the ground in a storm the chest leans upwind by up to
## `wind_lean` radians, by how strong the storm is where the body stands,
## and is buffeted by `wind_buffet` as the gusts come and go
## (`WeatherView.gust_now`). The neck takes the buffet back, so the eyes
## stay steady. View only, the same body in every view: everyone works it
## out from the same storm cell and where the body stands.
var windward := 0.0
var wind_lean := 0.24
var wind_buffet := 0.05
var wind_ease := 0.6
var _wind_dir := Vector3.FORWARD
var _wind_gust := 0.0
var _wind_time := 0.0
var _raid: Raid


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

	if player and anims.has("air_legs") and player.has_animation(anims["air_legs"]) and not _spine.is_empty():
		_air_anim = player.get_animation(anims["air_legs"])
		var hips := skeleton.find_bone(_hip_name)
		for track in _air_anim.get_track_count():
			if _air_anim.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := skeleton.find_bone(String(_air_anim.track_get_path(track)).get_slice(":", 1))
			if bone >= 0 and hips >= 0 and _is_under(bone, hips) and bone != _spine[0] and not _is_under(bone, _spine[0]):
				_air_tracks.append([bone, track])

	if player and anims.has("slide") and _spine.size() > 1:
		var keys := ["slide_start", "slide", "slide_exit"]
		for part in 3:
			if not anims.has(keys[part]) or not player.has_animation(anims[keys[part]]):
				continue
			var anim := player.get_animation(anims[keys[part]])
			var tracks := []
			for track in anim.get_track_count():
				var type := anim.track_get_type(track)
				if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
					continue
				var bone := skeleton.find_bone(String(anim.track_get_path(track)).get_slice(":", 1))
				if bone >= 0 and not _is_under(bone, _spine[_spine.size() - 1]):
					tracks.append([bone, track, type])
			_slide_clips[part] = [anim, tracks]
		_slide_anim = _slide_clips[1][0] if not _slide_clips[1].is_empty() else null

	# First, so everything after works from the planted legs.
	var stand := WeaponArm.Hook.new()
	stand.name = "StandLegs"
	stand.run = _stand_legs
	skeleton.add_child(stand)
	var clear := WeaponArm.Hook.new()
	clear.name = "ArmsClearArmor"
	clear.run = _clear_arms
	skeleton.add_child(clear)
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
	var low := WeaponArm.Hook.new()
	low.name = "CrouchPose"
	low.run = _crouch_pose
	skeleton.add_child(low)
	var stance := WeaponArm.Hook.new()
	stance.name = "FightStance"
	stance.run = _fight_pose
	skeleton.add_child(stance)
	var cold := WeaponArm.Hook.new()
	cold.name = "Shiver"
	cold.run = _shiver_pose
	skeleton.add_child(cold)
	var windy := WeaponArm.Hook.new()
	windy.name = "WindLean"
	windy.run = _wind_pose
	skeleton.add_child(windy)
	var land := WeaponArm.Hook.new()
	land.name = "SquatPose"
	land.run = _squat_pose
	skeleton.add_child(land)
	# After the squat, whose legs reach for planted feet: a skid's feet go
	# where its legs point.
	var skidding := WeaponArm.Hook.new()
	skidding.name = "SkidPose"
	skidding.run = _skid_pose
	skeleton.add_child(skidding)
	var seated := WeaponArm.Hook.new()
	seated.name = "RidePose"
	seated.run = _ride_pose
	skeleton.add_child(seated)
	# An emote's hips, legs and back, before the head looks round from them.
	var emoting := WeaponArm.Hook.new()
	emoting.name = "EmoteBody"
	emoting.run = _emote_body
	skeleton.add_child(emoting)
	_head = skeleton.find_bone(def.get("head", "Head"))
	var heading := WeaponArm.Hook.new()
	heading.name = "LookAtAim"
	heading.run = _look_pose
	skeleton.add_child(heading)


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
	_still_delta += delta
	twist = move_toward(twist, twist_target, twist_rate * delta * maxf(absf(twist_target - twist), 0.15))
	overlay_weight = move_toward(overlay_weight, 1.0 if overlay and not _overlay_tracks.is_empty() else 0.0,
			overlay_rate * delta)
	stride = move_toward(stride, stride_target, stride_rate * delta)
	stand_legs_weight = move_toward(stand_legs_weight, 1.0 if stand_legs and not _stand_tracks.is_empty() else 0.0,
			stand_legs_rate * delta)
	air_legs_weight = move_toward(air_legs_weight, 1.0 if air_legs and not _air_tracks.is_empty() else 0.0,
			air_legs_rate * delta)
	if _air_anim and _air_anim.length > 0.0:
		_air_time = fposmod(_air_time + delta, _air_anim.length) if air_legs_weight > 0.0 else 0.0
	shiver = move_toward(shiver, 1.0 if actor.shivering and not actor.is_dead else 0.0, shiver_ease * delta)
	skid_weight = move_toward(skid_weight, 1.0 if skid and not actor.is_dead else 0.0, skid_rate * delta)
	_update_look(delta)
	_shiver_time += delta
	_update_wind(delta)
	var shared := ActionPose.of(actor)
	shared.advance(delta)
	phone_weight = shared.phone
	var fighting := actor.get_active_weapon() is MeleeWeapon and not actor.is_dead and actor.vehicle == null \
			and actor.airborne_time <= 0.0 and actor.slide_low <= 0.001 and not (actor.cmd != null and actor.cmd.phone)
	fight = move_toward(fight, 1.0 if fighting else 0.0, fight_rate * delta)
	if _stand_anim and _stand_anim.length > 0.0:
		_stand_time = fposmod(_stand_time + delta, _stand_anim.length)
	_advance_slide(delta)
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
	_slide_clip()
	_stand_legs_clip()
	_air_legs_clip()


func _stand_legs_clip() -> void:
	if stand_legs_weight <= 0.0 or _stand_anim == null:
		return
	var hips := -1 if stand_legs_hips else skeleton.find_bone(_hip_name)
	for entry: Array in _stand_tracks:
		var bone: int = entry[0]
		if bone == hips or (hips >= 0 and not _is_under(bone, hips)):
			continue
		if entry[2] == Animation.TYPE_ROTATION_3D:
			var q := _stand_anim.rotation_track_interpolate(entry[1], _stand_time)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(q, stand_legs_weight))
		else:
			var at := _stand_anim.position_track_interpolate(entry[1], _stand_time)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(at, stand_legs_weight))


## Lays the jump's legs over whatever plays while off the ground.
func _air_legs_clip() -> void:
	var weight := smoothstep(0.0, 1.0, air_legs_weight)
	if weight <= 0.001 or _air_anim == null:
		return
	for entry: Array in _air_tracks:
		var bone: int = entry[0]
		var q := _air_anim.rotation_track_interpolate(entry[1], _air_time)
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(q, weight))


## Swings each upper arm out from the body by `arm_clear` at the elbow:
## out along the line from the middle of the shoulders, across the arm.
func _clear_arms() -> void:
	if arm_clear <= 0.0 or _arms.size() < 2 or _arms[0].is_empty() or _arms[1].is_empty():
		return
	var meter := 1.0 / skeleton.global_basis.get_scale().y
	var middle := (skeleton.get_bone_global_pose(_arms[0][0]).origin + skeleton.get_bone_global_pose(_arms[1][0]).origin) * 0.5
	for arm: Array[int] in _arms:
		var pose := skeleton.get_bone_global_pose(arm[0])
		var along := skeleton.get_bone_global_pose(arm[1]).origin - pose.origin
		var length := along.length()
		var outward := pose.origin - middle
		outward -= along.normalized() * outward.dot(along.normalized())
		if length < 0.001 or outward.length() < 0.001:
			continue
		var axis := along.cross(outward).normalized()
		pose.basis = Basis(axis, atan(arm_clear * meter / length)) * pose.basis
		skeleton.set_bone_global_pose(arm[0], pose)


## Steps the slide through its clips: the drop into it as it starts, the
## held slide looped while it lasts, and the rise out once it ends (cut
## short by a jump out of it). A part the body has no clip for is skipped.
func _advance_slide(delta: float) -> void:
	if _slide_anim == null or actor == null:
		return
	var sliding := actor.is_sliding() and actor.vehicle == null
	if sliding and _slide_phase in [SLIDE_NONE, SLIDE_OUT]:
		_slide_phase = SLIDE_IN if not _slide_clips[0].is_empty() else SLIDE_HOLD
		_slide_time = 0.0
	elif not sliding and _slide_phase in [SLIDE_IN, SLIDE_HOLD]:
		# Off the ground the body has left the slide: no getting up.
		_slide_phase = SLIDE_OUT if not _slide_clips[2].is_empty() and actor.airborne_time <= 0.0 else SLIDE_NONE
		_slide_time = 0.0
	match _slide_phase:
		SLIDE_IN:
			_slide_time += delta * slide_in_rate
			var length: float = (_slide_clips[0][0] as Animation).length
			if _slide_time >= length:
				_slide_phase = SLIDE_HOLD
				_slide_time = fposmod(_slide_time - length, maxf(_slide_anim.length, 0.001))
		SLIDE_HOLD:
			_slide_time = fposmod(_slide_time + delta, maxf(_slide_anim.length, 0.001))
		SLIDE_OUT:
			_slide_time += delta * slide_out_rate
			if _slide_time >= (_slide_clips[2][0] as Animation).length or actor.airborne_time > 0.0:
				_slide_phase = SLIDE_NONE
				_slide_time = 0.0


## How much of the slide's clips are laid over the body now: blended in
## from the run at the start of the drop, whole while held, faded into
## what comes next at the end of the rise. With only the held clip, the
## crouch into the slide (`Actor.slide_low`).
func slide_weight() -> float:
	if actor == null or _slide_anim == null:
		return 0.0
	if _slide_clips[0].is_empty() and _slide_clips[2].is_empty():
		return smoothstep(0.0, 1.0, actor.slide_low)
	match _slide_phase:
		SLIDE_IN:
			return smoothstep(0.0, slide_in_blend * slide_in_rate, _slide_time)
		SLIDE_HOLD:
			return 1.0
		SLIDE_OUT:
			var length: float = (_slide_clips[2][0] as Animation).length
			return 1.0 - smoothstep(length * (1.0 - slide_out_fade), length, _slide_time)
	return 0.0


## Lays the slide's clips over the hips, legs and spine,
## before the legs turn to travel, so the slide goes the way the body moves.
func _slide_clip() -> void:
	var weight := slide_weight() * (1.0 - skid_weight)
	if weight <= 0.001:
		return
	var clip: Array = _slide_clips[1]
	if _slide_phase == SLIDE_IN:
		clip = _slide_clips[0]
	elif _slide_phase == SLIDE_OUT:
		clip = _slide_clips[2]
	var anim: Animation = clip[0]
	var time := minf(_slide_time, anim.length)
	for entry: Array in clip[1]:
		var bone: int = entry[0]
		if entry[2] == Animation.TYPE_ROTATION_3D:
			var q := anim.rotation_track_interpolate(entry[1], time)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(q, weight))
		else:
			var at := anim.position_track_interpolate(entry[1], time)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(at, weight))


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
	var weight := slide_shown() if actor else 0.0
	if weight <= 0.001 or _slide_anim != null:
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


## How far the slide shows: the actor's, less what a skid stands in for.
func slide_shown() -> float:
	return actor.slide_low * (1.0 - skid_weight) if actor != null else 0.0


## Braces the legs in a skid (`skid`): the hips sink, the lead leg reaches
## out ahead nearly straight, the trailing leg folds under, and each foot is
## put back on the end of its shin, so the feet plant instead of running.
func _skid_pose() -> void:
	var weight := smoothstep(0.0, 1.0, skid_weight)
	if weight <= 0.001 or actor == null:
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var along := to_skeleton * Basis(Vector3.UP, twist)
	var up := (to_skeleton * Vector3.UP).normalized()
	var meter := 1.0 / skeleton.global_basis.get_scale().y
	var sink := Transform3D(Basis.IDENTITY, -up * skid_drop * meter * weight)
	for bone in _roots:
		skeleton.set_bone_global_pose(bone, sink * skeleton.get_bone_global_pose(bone))
	for pair in [[_lead, skid_lead_thigh, skid_lead_shin], [_trail, skid_trail_thigh, skid_trail_shin]]:
		var leg: Array[int] = pair[0]
		if leg.size() != 3:
			continue
		_point_bone(leg[0], (along * pair[1]).normalized(), weight, skeleton.get_bone_rest(leg[1]).origin.normalized())
		_point_bone(leg[1], (along * pair[2]).normalized(), weight, (_foot_on_shin[leg[2]].origin as Vector3).normalized())
		var foot := skeleton.get_bone_global_pose(leg[2])
		var on_shin: Transform3D = skeleton.get_bone_global_pose(leg[1]) * _foot_on_shin[leg[2]]
		skeleton.set_bone_global_pose(leg[2], foot.interpolate_with(on_shin, weight))
	if not _spine.is_empty():
		var right := (along * Vector3.RIGHT).normalized()
		var pose := skeleton.get_bone_global_pose(_spine[0])
		pose.basis = Basis(right, skid_spine_lean * weight) * pose.basis
		skeleton.set_bone_global_pose(_spine[0], pose)


## Cold: the chest hunches in and trembles, a fast uneven shake, and the neck
## takes the tremor back so the head stays steady.
func _shiver_pose() -> void:
	if shiver <= 0.001 or _spine.is_empty():
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var right := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.RIGHT).normalized()
	var forward := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.FORWARD).normalized()
	var t := _shiver_time * shiver_rate
	var shake := shiver_shake * shiver * (sin(t) * 0.6 + sin(t * 1.73 + 1.1) * 0.4)
	var sway := shiver_shake * shiver * 0.5 * sin(t * 1.31 + 2.0)
	var chest := _spine[_spine.size() - 1]
	var pose := skeleton.get_bone_global_pose(chest)
	var turn := Basis(right, -shiver_hunch * shiver + shake) * Basis(forward, sway)
	pose.basis = turn * pose.basis
	skeleton.set_bone_global_pose(chest, pose)
	if _neck >= 0 and _is_under(_neck, chest):
		var neck := skeleton.get_bone_global_pose(_neck)
		neck.basis = Basis(forward, -sway) * Basis(right, -shake) * neck.basis
		skeleton.set_bone_global_pose(_neck, neck)


## How far into a storm's wind the body stands, and which way it blows.
func _update_wind(delta: float) -> void:
	_wind_time += delta
	if _raid == null or not is_instance_valid(_raid):
		_raid = Raid.of(actor)
	var into := 0.0
	if _raid != null and _raid.weather != null and _raid.weather.kind != "" and not actor.is_dead \
			and actor.vehicle == null and actor.airborne_time <= 0.0:
		var weather := _raid.weather
		into = weather.strength_at(actor.global_position)
		if into > 0.0:
			var wind := Vector3(weather.velocity.x, 0.0, weather.velocity.z)
			if wind.length_squared() > 0.0001:
				_wind_dir = wind.normalized()
			_wind_gust = WeatherView.gust_now(weather, actor.global_position, _wind_time)
	windward = move_toward(windward, into, wind_ease * delta)
	if windward <= 0.0:
		_wind_gust = 0.0


func _wind_pose() -> void:
	if windward <= 0.001 or _spine.is_empty():
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	var upwind := (to_skeleton * -_wind_dir).normalized()
	var up := (to_skeleton * Vector3.UP).normalized()
	var axis := up.cross(upwind)
	if axis.length_squared() < 0.0001:
		return
	axis = axis.normalized()
	var buffet := wind_buffet * windward * _wind_gust * sin(_wind_time * 7.0) \
			+ wind_buffet * 0.5 * windward * sin(_wind_time * 2.1 + 0.6)
	var lean := wind_lean * windward * (0.75 + 0.25 * _wind_gust)
	# Bent from the bottom of the spine, more at each bone up, so the whole
	# upper body leans in rather than the chest alone.
	var chest := _spine[_spine.size() - 1]
	var shares := 0.0
	for i in _spine.size():
		shares += float(i + 1)
	for i in _spine.size():
		var bone: int = _spine[i]
		var pose := skeleton.get_bone_global_pose(bone)
		var share := float(i + 1) / shares
		pose.basis = Basis(axis, (lean + buffet) * share) * pose.basis
		skeleton.set_bone_global_pose(bone, pose)
	if _neck >= 0 and _is_under(_neck, chest):
		# The head ducks into the wind a little, but keeps its line: the
		# neck takes back the buffet and some of the lean.
		var neck := skeleton.get_bone_global_pose(_neck)
		neck.basis = Basis(axis, -buffet - lean * 0.45) * neck.basis
		skeleton.set_bone_global_pose(_neck, neck)


## Follows the aim (in the actor's frame) for the head, and eases the look in
## or out: out while dead or reading the phone (which bends the neck itself).
func _update_look(delta: float) -> void:
	var wanted := 0.0 if actor.is_dead else 1.0 - clampf(phone_weight, 0.0, 1.0)
	look_weight = move_toward(look_weight, wanted, look_rate * delta)
	var aim := actor.global_basis.orthonormalized().inverse() * actor.get_aim_dir()
	if aim.length_squared() < 0.0001:
		return
	aim = aim.normalized()
	var follow := 1.0 - exp(-look_follow * delta)
	# Blended and normalized (not `slerp`, which errors on nearly parallel
	# directions): the steps are small.
	var blended := _look_dir.lerp(aim, follow)
	_look_dir = blended.normalized() if blended.length_squared() > 0.01 else aim


## The way `bone` faces now, in the skeleton's space, from the way it faces
## at rest in its own space (`ahead`).
func _facing(bone: int, ahead: Vector3) -> Vector3:
	return (skeleton.get_bone_global_pose(bone).basis.orthonormalized() * ahead).normalized()


## Turns the neck and head so the face looks along the aim, kept within
## `look_reach`, `look_up` and `look_down` of the chest. Works from wherever the body has been put
## (a crouch, a lean, a seat, flying), so the eyes end up on the aim.
func _look_pose() -> void:
	if look_weight <= 0.0 or _head < 0 or _neck < 0 or _spine.is_empty() or actor == null:
		return
	var chest := _spine[_spine.size() - 1]
	if _model_ahead == Vector3.ZERO:
		# The skin stands the model facing the actor's forward; the head and
		# chest face that way at rest.
		var skin := get_parent() as Node3D
		if skin == null:
			return
		var skeleton_in_skin := skin.global_basis.orthonormalized().inverse() * skeleton.global_basis.orthonormalized()
		_model_ahead = (skeleton_in_skin.inverse() * (skin.basis.orthonormalized().inverse() * Vector3.FORWARD)).normalized()
		_head_ahead = (skeleton.get_bone_global_rest(_head).basis.orthonormalized().inverse() * _model_ahead).normalized()
		_chest_ahead = (skeleton.get_bone_global_rest(chest).basis.orthonormalized().inverse() * _model_ahead).normalized()
		var model_up := (skeleton_in_skin.inverse() * (skin.basis.orthonormalized().inverse() * Vector3.UP)).normalized()
		_chest_up = (skeleton.get_bone_global_rest(chest).basis.orthonormalized().inverse() * model_up).normalized()
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var want := (to_skeleton * _look_dir).normalized()
	# The aim as a turn and a tip in the chest's own frame, each held to
	# what a neck can do.
	var chest_ahead := _facing(chest, _chest_ahead)
	var chest_up := _facing(chest, _chest_up)
	chest_up = (chest_up - chest_ahead * chest_up.dot(chest_ahead)).normalized()
	var chest_side := chest_ahead.cross(chest_up)
	var yaw := atan2(want.dot(chest_side), want.dot(chest_ahead))
	var tip := asin(clampf(want.dot(chest_up), -1.0, 1.0))
	var held_yaw := clampf(yaw, -look_reach, look_reach)
	var held_tip := clampf(tip, -look_down, look_up)
	if held_yaw != yaw or held_tip != tip:
		want = (chest_ahead * cos(held_yaw) + chest_side * sin(held_yaw)) * cos(held_tip) + chest_up * sin(held_tip)
	var w := smoothstep(0.0, 1.0, look_weight)
	var now := _facing(_head, _head_ahead)
	if now.dot(want) > 0.99999:
		return
	var neck := skeleton.get_bone_global_pose(_neck)
	var turn := Quaternion.IDENTITY.slerp(Quaternion(now, want), w * look_neck)
	neck.basis = Basis(turn) * neck.basis
	skeleton.set_bone_global_pose(_neck, neck)
	now = _facing(_head, _head_ahead)
	var head := skeleton.get_bone_global_pose(_head)
	head.basis = Basis(Quaternion.IDENTITY.slerp(Quaternion(now, want), w)) * head.basis
	skeleton.set_bone_global_pose(_head, head)


## A landing squat: see `_sink`.
func _squat_pose() -> void:
	_sink(squat_drop, squat_lean, clampf(squat, 0.0, 1.0))


## The crouch, over the stand or the walk: see `_sink`. Not while sliding,
## which has its own pose, nor under the rise out of a slide.
func _crouch_pose() -> void:
	if actor == null or slide_shown() > 0.001 or skid_weight > 0.001:
		return
	var weight := smoothstep(0.0, 1.0, actor.crouch) * (1.0 - slide_weight())
	if weight <= 0.001:
		return
	if _means.has(current_anim):
		# Shorter steps: each foot comes in toward its average spot.
		# Along the ground only: a foot's height stays the clip's.
		var means: Dictionary = _means[current_anim]
		var keep := lerpf(1.0, crouch_step, weight)
		var up := (skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized() * Vector3.UP).normalized()
		for bone in _feet:
			if not means.has(bone):
				continue
			var parent := skeleton.get_bone_parent(bone)
			var local_up := up if parent < 0 else (skeleton.get_bone_global_pose(parent).basis.inverse() * up).normalized()
			var mean: Vector3 = means[bone]
			var off := skeleton.get_bone_pose_position(bone) - mean
			var rise := local_up.dot(off)
			var lift := local_up * rise
			# A foot swinging through (above its average height) stays lower,
			# so the trailing foot never kicks up behind; a planted one stays put.
			skeleton.set_bone_pose_position(bone, mean + (off - lift) * keep + lift * (keep if rise > 0.0 else 1.0))
	_sink(crouch_drop, crouch_lean, weight, crouch_heel)
	if not _spine.is_empty():
		var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
		var right := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.RIGHT).normalized()
		var pose := skeleton.get_bone_global_pose(_spine[0])
		pose.basis = Basis(right, -crouch_spine_lean * weight) * pose.basis
		skeleton.set_bone_global_pose(_spine[0], pose)


## The fighting stance (`fight`): feet staggered while standing still, the
## knees bent under the stand or the walk. Less of it in a crouch, which
## bends the knees already.
func _fight_pose() -> void:
	var weight := smoothstep(0.0, 1.0, fight) * (1.0 - smoothstep(0.0, 1.0, actor.crouch))
	if weight <= 0.001 or _lead.size() != 3 or _trail.size() != 3:
		return
	var still := 1.0 - clampf(Vector2(velocity.x, velocity.z).length() / 1.5, 0.0, 1.0)
	if still > 0.001:
		var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
		var meter := 1.0 / skeleton.global_basis.get_scale().y
		var forward := (to_skeleton * Vector3.FORWARD).normalized() * meter
		var side := (to_skeleton * Vector3.RIGHT).normalized() * meter
		var amount := weight * still
		# Footwork (`ActionPose.footwork`): a step in moves the lead foot, a
		# step back the trailing one, so the stance opens or gathers.
		var step := ActionPose.of(actor).footwork
		for i in 2:
			var foot: int = _lead[2] if i == 0 else _trail[2]
			var pose := skeleton.get_bone_global_pose(foot)
			var way := 1.0 if i == 0 else -1.0
			# The lead (left) foot steps forward and a touch out to its side,
			# the trailing (right) one back and out to its own.
			pose.origin += (forward * fight_stagger * way - side * fight_width * way) * amount
			var moved := maxf(step, 0.0) if i == 0 else minf(step, 0.0)
			pose.origin += forward * moved * amount
			skeleton.set_bone_global_pose(foot, pose)
	# Driving in, the hips drop and the chest leans into it; stepping back,
	# it rocks back.
	var stepped := ActionPose.of(actor).footwork
	_sink(fight_drop + absf(stepped) * 0.15, fight_lean + stepped * 0.6, weight)


## Sinks the body onto bent knees, feet planted where they were: the hips
## drop `drop` meters and tip forward `lean` radians at a full `weight`, and
## each leg is bent to still reach its foot. Everything above the hips (the
## arms, the gun and its sights, a held blade) comes down with them.
## `heel` (radians) rolls each foot forward onto its ball, toes kept where
## they were, so a deep bend lifts the heels rather than folding the ankle.
func _sink(drop_m: float, lean: float, weight: float, heel := 0.0) -> void:
	if weight <= 0.001 or actor == null or _lead.size() != 3 or _trail.size() != 3:
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var up := (to_skeleton * Vector3.UP).normalized()
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	var meter := 1.0 / skeleton.global_basis.get_scale().y
	var pivot := skeleton.global_transform.affine_inverse() * actor.global_position
	var feet: Array[Transform3D] = [skeleton.get_bone_global_pose(_lead[2]), skeleton.get_bone_global_pose(_trail[2])]
	var drop := Transform3D(Basis.IDENTITY, pivot - up * drop_m * meter * weight) \
			* Transform3D(Basis(right, -lean * weight), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	for bone in _roots:
		skeleton.set_bone_global_pose(bone, drop * skeleton.get_bone_global_pose(bone))
	if heel > 0.0:
		var forward := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.FORWARD).normalized()
		var side := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.RIGHT).normalized()
		var roll := Basis(side, -heel * weight)
		for i in 2:
			var toe := feet[i].origin + forward * foot_reach * meter
			feet[i] = Transform3D(roll * feet[i].basis, toe + roll * (feet[i].origin - toe))
	# The knees bend forward over the toes, a touch out (`knee_out`): bent
	# the way the stand's knee happened to point, a relaxed leg's knee
	# swung out sideways and the leg flared.
	var ahead := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.FORWARD).normalized()
	var aside := (to_skeleton * Basis(Vector3.UP, twist) * Vector3.RIGHT).normalized()
	var legs := [_lead, _trail]
	for i in 2:
		var leg: Array[int] = legs[i]
		var out := signf((feet[i].origin - pivot).dot(aside))
		_reach(leg, feet[i].origin, ahead + aside * out * knee_out)
		skeleton.set_bone_global_pose(leg[2], feet[i])


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
	# The lean is the whole back's, from the hips to the neck, whatever slouch
	# the clip had: the back is turned to lie at `rider_lean` from upright.
	var lean: float = _ride_on.get("rider_lean")
	if not _spine.is_empty() and _neck >= 0:
		var want := Basis(right, -lean) * up
		var start := skeleton.get_bone_global_pose(_neck).origin - skeleton.get_bone_global_pose(_spine[0]).origin
		var goal := start.normalized().slerp(want, w) if start.length_squared() > 0.000001 else want
		# Each bone turns about its own joint, so the chord from the bottom of
		# the back to the neck lags: a few passes settle it on the lean.
		for i in 3:
			var back := skeleton.get_bone_global_pose(_neck).origin - skeleton.get_bone_global_pose(_spine[0]).origin
			if back.length_squared() < 0.000001:
				break
			var share := Quaternion.IDENTITY.slerp(Quaternion(back.normalized(), goal), 1.0 / _spine.size())
			for bone in _spine:
				var pose := skeleton.get_bone_global_pose(bone)
				pose.basis = Basis(share) * pose.basis
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


## Adds the phone hold. Called by the skin after the weapon arm is set up,
## so it runs last and the right hand is the phone's, whatever was in it.
## Everything about the hold is in `phone_pose`, so it is one swap away from
## a shared hand pose.
func add_phone_hook() -> void:
	if skeleton == null:
		return
	var hold := WeaponArm.Hook.new()
	hold.name = "PhonePose"
	hold.run = phone_pose
	skeleton.add_child(hold)


## The right hand brings the phone up in front of the chest and the head
## bows to look at it. View only, from `phone_weight`.
func phone_pose() -> void:
	if phone_weight <= 0.0 or skeleton == null or actor == null:
		return
	var w := smoothstep(0.0, 1.0, phone_weight)
	var to_skeleton := skeleton.global_transform.affine_inverse() * actor.global_transform
	var right := (to_skeleton.basis * Vector3.RIGHT).normalized()
	if not _spine.is_empty():
		var chest := _spine[_spine.size() - 1]
		var pose := skeleton.get_bone_global_pose(chest)
		pose.basis = Basis(right, -phone_chest * w) * pose.basis
		skeleton.set_bone_global_pose(chest, pose)
	for arm: Array[int] in _arms:
		if arm.size() != 3:
			continue
		if _side_of(arm[0]) < 0.0:
			_bend(arm, skeleton.get_bone_rest(arm[2]).origin, to_skeleton * phone_rest,
					to_skeleton.basis * phone_rest_elbow, w)
			continue
		var wrist := to_skeleton * phone_wrist
		var elbow := to_skeleton.basis * phone_elbow
		_bend(arm, skeleton.get_bone_rest(arm[2]).origin, wrist, elbow, w)
		# The phone sits in the palm, a hand's length on from the wrist.
		var to_actor := to_skeleton.affine_inverse()
		var wrist_now := to_actor * skeleton.get_bone_global_pose(arm[2]).origin
		var elbow_now := to_actor * skeleton.get_bone_global_pose(arm[1]).origin
		phone_in_hand = wrist_now + (wrist_now - elbow_now).normalized() * phone_palm
	if _neck >= 0:
		var pose := skeleton.get_bone_global_pose(_neck)
		pose.basis = Basis(right, -phone_look_down * w) * pose.basis
		skeleton.set_bone_global_pose(_neck, pose)


# --- Emotes -------------------------------------------------------------------
# An emote (`Emotes`) is posed on the one body from `ActionPose.emote`, so
# every view and every machine shows it the same. The hips, legs and back go
# in `_emote_body` (before the head looks round), the arms in `emote_pose`,
# the last hook of all, so they take the hands whatever was in them. Places
# are in the actor's frame (metres: x right, y up, -z ahead, the feet at 0),
# with elbows given as the way each bows.

## Sitting on the ground: where the hips go, the ankles reach (out in front,
## knees up) and the hands rest behind, and how far the back leans.
var sit_hips := Vector3(0.0, 0.16, 0.06)
var sit_ankle := Vector3(0.15, 0.08, -0.42)
var sit_knee := Vector3(0.15, 1.0, -0.5)
var sit_hand := Vector3(0.24, 0.12, 0.24)
var sit_lean := 0.22
## How fast each beat runs (beats a second) for the emotes that move.
var wave_rate := 1.8
var cheer_rate := 2.2
var dance_rate := 1.05
var taunt_rate := 1.6


## Adds the emote's arms. Called by the skin after the phone hold.
func add_emote_hook() -> void:
	if skeleton == null:
		return
	var arms := WeaponArm.Hook.new()
	arms.name = "EmoteArms"
	arms.run = emote_pose
	skeleton.add_child(arms)


## The emote shown now and how far in it is ("" and 0 for none).
func _emote_now() -> Array:
	if skeleton == null or actor == null:
		return ["", 0.0, 0.0]
	var shared := ActionPose.of(actor)
	if shared.emote <= 0.001 or shared.emote_id == "":
		return ["", 0.0, 0.0]
	return [shared.emote_id, smoothstep(0.0, 1.0, shared.emote), shared.emote_clock]


func _emote_body() -> void:
	var now := _emote_now()
	var id: String = now[0]
	var w: float = now[1]
	var t: float = now[2]
	if id == "":
		return
	match id:
		"sit":
			_emote_sit(w)
		"lean":
			_emote_hips(Vector3(0.05, -0.02, 0.02), 0.06, -0.06, w)
		"dance":
			var beat := t * dance_rate * TAU
			_emote_hips(Vector3(0.07 * sin(beat), -0.05 * (0.5 - 0.5 * cos(beat * 2.0)), 0.0),
					-0.08 * sin(beat), 0.05, w)
			_emote_back(-0.04, 0.22 * sin(beat), w)
		"cheer":
			_emote_hips(Vector3(0.0, -0.04 * absf(sin(t * cheer_rate * PI)), 0.0), 0.0, 0.0, w)
			_emote_back(0.1, 0.0, w)
		"salute":
			_emote_back(0.05, 0.0, w)
		"taunt":
			_emote_back(0.12, 0.0, w)
		"point":
			_emote_back(-0.05, 0.0, w)


func emote_pose() -> void:
	var now := _emote_now()
	var id: String = now[0]
	var w: float = now[1]
	var t: float = now[2]
	if id == "":
		return
	match id:
		"wave":
			var swing := 0.09 * sin(t * wave_rate * TAU)
			_emote_arm(1.0, Vector3(0.36 + swing, 1.72, -0.12), Vector3(1.0, -0.6, 0.1), w)
		"salute":
			_emote_arm(1.0, Vector3(0.16, 1.63, -0.13), Vector3(1.0, -0.2, -0.2), w)
		"point":
			_emote_point(w)
		"cheer":
			var pump := 0.06 * sin(t * cheer_rate * TAU)
			_emote_arm(1.0, Vector3(0.27, 1.98 + pump, -0.08), Vector3(1.0, 0.0, 0.2), w)
			_emote_arm(-1.0, Vector3(-0.27, 1.98 - pump, -0.08), Vector3(-1.0, 0.0, 0.2), w)
		"sit":
			_emote_arm(1.0, sit_hand, Vector3(0.3, 0.0, 1.0), w)
			_emote_arm(-1.0, Vector3(-sit_hand.x, sit_hand.y, sit_hand.z), Vector3(-0.3, 0.0, 1.0), w)
		"lean":
			# Arms folded across the chest.
			_emote_arm(1.0, Vector3(-0.1, 1.2, -0.22), Vector3(1.0, -0.5, 0.2), w)
			_emote_arm(-1.0, Vector3(0.1, 1.25, -0.2), Vector3(-1.0, -0.5, 0.2), w)
		"dance":
			var beat := 0.5 + 0.5 * sin(t * dance_rate * TAU)
			_emote_arm(1.0, Vector3(0.26, 1.3 + 0.42 * beat, -0.24), Vector3(1.0, -0.6, 0.3), w)
			_emote_arm(-1.0, Vector3(-0.26, 1.3 + 0.42 * (1.0 - beat), -0.24), Vector3(-1.0, -0.6, 0.3), w)
		"taunt":
			# Come on: one hand beckons, the other on the hip.
			var pull := 0.5 + 0.5 * sin(t * taunt_rate * TAU)
			_emote_arm(1.0, Vector3(0.14, 1.24 + 0.06 * pull, -0.44 + 0.13 * pull), Vector3(0.6, -1.0, 0.2), w)
			_emote_arm(-1.0, Vector3(-0.21, 0.98, 0.0), Vector3(-1.0, 0.0, 0.3), w)


## Moves the hips by `offset` (actor frame) and tips them `roll` about the
## way ahead and `lean` about the right, the feet left planted where they
## were and the legs bent to reach them.
func _emote_hips(offset: Vector3, roll: float, lean: float, weight: float) -> void:
	if weight <= 0.001 or _lead.size() != 3 or _trail.size() != 3:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse() * actor.global_transform
	var hips := skeleton.find_bone(_hip_name)
	var pivot := skeleton.get_bone_global_pose(hips).origin if hips >= 0 \
			else to_skeleton * Vector3(0.0, 0.9, 0.0)
	var right := (to_skeleton.basis * Vector3.RIGHT).normalized()
	var ahead := (to_skeleton.basis * Vector3.FORWARD).normalized()
	var feet: Array[Transform3D] = [skeleton.get_bone_global_pose(_lead[2]), skeleton.get_bone_global_pose(_trail[2])]
	var turn := Basis(ahead, roll * weight) * Basis(right, lean * weight)
	var move := Transform3D(Basis.IDENTITY, pivot + to_skeleton.basis * offset * weight) \
			* Transform3D(turn, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	for bone in _roots:
		skeleton.set_bone_global_pose(bone, move * skeleton.get_bone_global_pose(bone))
	var legs := [_lead, _trail]
	for i in 2:
		var leg: Array[int] = legs[i]
		_reach(leg, feet[i].origin)
		skeleton.set_bone_global_pose(leg[2], feet[i])


## Leans the back `back` radians (back is positive) and turns the chest
## `twist` about the up, shared down the spine.
func _emote_back(back: float, twist: float, weight: float) -> void:
	if weight <= 0.001 or _spine.is_empty():
		return
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	var up := (to_skeleton * Vector3.UP).normalized()
	var share := weight / _spine.size()
	for bone in _spine:
		var pose := skeleton.get_bone_global_pose(bone)
		pose.basis = Basis(up, twist * share) * Basis(right, back * share) * pose.basis
		skeleton.set_bone_global_pose(bone, pose)


## Sits the body on the ground: hips down, knees up, feet out in front, the
## back leaning onto the hands behind it (`emote_pose`).
func _emote_sit(weight: float) -> void:
	var to_skeleton := skeleton.global_transform.affine_inverse() * actor.global_transform
	var hips := skeleton.find_bone(_hip_name)
	if hips >= 0:
		var want := to_skeleton * sit_hips
		var shift := (want - skeleton.get_bone_global_pose(hips).origin) * weight
		for bone in _roots:
			var pose := skeleton.get_bone_global_pose(bone)
			pose.origin += shift
			skeleton.set_bone_global_pose(bone, pose)
	_emote_back(sit_lean, 0.0, weight)
	for leg in [_lead, _trail]:
		if leg.size() != 3:
			continue
		var side := _side_of(leg[0])
		var ankle := to_skeleton * Vector3(sit_ankle.x * side, sit_ankle.y, sit_ankle.z)
		var knee := to_skeleton.basis * Vector3(sit_knee.x * side, sit_knee.y, sit_knee.z)
		_bend(leg, _foot_on_shin[leg[2]].origin, ankle, knee, weight)
		var foot := skeleton.get_bone_global_pose(leg[2])
		var on_shin: Transform3D = skeleton.get_bone_global_pose(leg[1]) * _foot_on_shin[leg[2]]
		skeleton.set_bone_global_pose(leg[2], foot.interpolate_with(on_shin, weight * 0.7))


## Points the right arm straight along the aim, where the head is looking.
func _emote_point(weight: float) -> void:
	for arm: Array[int] in _arms:
		if arm.size() != 3 or _side_of(arm[0]) < 0.0:
			continue
		var to_skeleton := skeleton.global_transform.affine_inverse() * actor.global_transform
		var to_actor := to_skeleton.affine_inverse()
		var shoulder := to_actor * skeleton.get_bone_global_pose(arm[0]).origin
		var elbow := to_actor * skeleton.get_bone_global_pose(arm[1]).origin
		var wrist := to_actor * skeleton.get_bone_global_pose(arm[2]).origin
		var reach := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
		var aim := (actor.global_basis.orthonormalized().inverse() * actor.get_aim_dir()).normalized()
		# Never back through the body: at most out to the side.
		aim.z = minf(aim.z, -0.15)
		_emote_arm(1.0, shoulder + aim.normalized() * reach * 0.95, Vector3(0.4, -1.0, 0.3), weight)


## Reaches the arm on `side` (1 right, -1 left) to `wrist`, its elbow bowing
## toward `elbow`, both in the actor's frame.
func _emote_arm(side: float, wrist: Vector3, elbow: Vector3, weight: float) -> void:
	if weight <= 0.001:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse() * actor.global_transform
	for arm: Array[int] in _arms:
		if arm.size() != 3 or signf(_side_of(arm[0])) != signf(side):
			continue
		_bend(arm, skeleton.get_bone_rest(arm[2]).origin, to_skeleton * wrist, to_skeleton.basis * elbow, weight)


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
## space), keeping the knee bent the way it is now, or toward `knee_toward`
## (skeleton space) where given. The foot keeps its turn.
func _reach(leg: Array[int], target: Vector3, knee_toward := Vector3.ZERO) -> void:
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
	var bend := knee_now - hip if knee_toward == Vector3.ZERO else knee_toward
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
	if overlay_weight > 0.0 and _overlay_anim != null:
		var time := fposmod(overlay_phase, 1.0) * _overlay_anim.length
		for bone: int in _overlay_tracks:
			var pose: Quaternion = _overlay_anim.rotation_track_interpolate(_overlay_tracks[bone], time)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(pose, overlay_weight))
	_hold_upper_still()


## While aimed, the upper body follows the gait with a lag (`aim_still_time`).
func _hold_upper_still() -> void:
	var delta := _still_delta
	_still_delta = 0.0
	var steady := ActionPose.of(actor).ads if actor != null else 0.0
	if steady <= 0.0:
		_still.clear()
		return
	var follow := 1.0 - exp(-delta / maxf(aim_still_time, 0.01))
	for bone: int in _spine + _overlay_tracks.keys():
		var now := skeleton.get_bone_pose_rotation(bone)
		var kept: Quaternion = _still.get(bone, now)
		if kept.dot(now) < 0.0:
			kept = -kept
		kept = kept.slerp(now, follow)
		_still[bone] = kept
		skeleton.set_bone_pose_rotation(bone, now.slerp(kept, steady))


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
