extends Node3D
## The model an actor wears. Added by `Look` as a child of the Actor; the
## Actor itself never knows about it. It reads the actor's state each frame
## and plays the matching animation, swaps greybox weapon parts for models,
## and plays the effects for shots and hits.

const MirrorScript := preload("res://core/visual/mirror.gd")
const Vfx := preload("res://core/visual/vfx.gd")
const WeaponArm := preload("res://core/visual/weapon_arm.gd")
const RigModel := preload("res://core/visual/rig_model.gd")
const Locomotion := preload("res://core/visual/locomotion.gd")
const Handheld := preload("res://core/phone/handheld.gd")
const UiTheme := preload("res://core/visual/ui_theme.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
## Clips that loop and are cut between in step, keeping the stride's phase.
const GAITS: Array[String] = ["walk", "run", "run_back", "run_left", "run_right", "move_gun"]
## Standing clips. Cuts into and out of them blend for longer, so stopping
## settles into the stand instead of snapping.
const STANDS: Array[String] = ["idle", "idle_gun", "aim_gun", "idle_melee"]

## Drawn cloaked now (see `_update_cloak`), and the shared shimmer material.
var _cloaked := false
## The weapon model being drawn as it materializes (a watch summon), if any.
var _materializing: Node3D
var _materialize_mat: ShaderMaterial
## The toy vehicle shown in the hand (`Actor.toy_in_hand`), how far it has
## digitized in (0 to 1), and the light it digitizes under.
var _toy_prop: Node3D
var _toy_in := 0.0
var _toy_mat: ShaderMaterial
## Seconds a toy takes to digitize into the hand off the watch.
var toy_summon_time := 0.35
## How the toy sits on the hand: a little ahead of the palm, upright and
## facing the way the actor faces, as it flies off.
var toy_on_palm := Vector3(0.0, 0.05, -0.06)
var _toy_released := false
static var _materialize_shader: Shader
static var _cloak_mat: Material

## How long a gun stays raised after the last shot, in seconds, standing or
## on the move; after that, moving, it goes back to its carry.
var aim_hold := 1.5
## Faster than this share of the actor's own walking pace (its walk speed
## with the gun's and rig's speed scaling), moving forward, the gun goes into
## its sprint carry, fully by the second.
var sprint_from := Vector2(1.08, 1.35)
## Blend times, in seconds: between two gaits, into or out of a stand, else.
var gait_blend := 0.2
var stand_blend := 0.35
var cut_blend := 0.15

## How far behind the back bone a back-worn rig sits, and how far the boots
## sit above and behind the ankle bone, in meters.
var back_gap := 0.11
var back_drop := -0.02
var boot_offset := Vector3(0, 0.0, 0.0)
## How fast wings spread and fold, in full swings per second.
var wing_speed := 3.5
## How long nozzles burn after an air jump, in seconds.
var burst_burn := 0.3
## Gliding, the body lies out flat, head first: how far it tips forward
## (radians), the height it tips about, and how fast it goes in and out of
## the pose (full changes per second). Arms trail back along the sides,
## a little out and up like a diver's, and the legs stay straight together.
## Directions are in the actor's frame before the tip: x right, y up, z back.
var glide_pitch := 1.4
var glide_pivot := 1.0
var glide_blend := 3.0
var glide_arm := Vector3(0.45, -1.0, 0.25)
var glide_leg := Vector3(0.06, -1.0, -0.06)
## How far the head tips back to look ahead while flying flat, and how far
## the feet point, in radians.
var glide_look := 1.0
var glide_toes := 1.0
## Free look behind in a glide (a backstroke, see `_look_roll`): lying on
## the back, the arms open out wide to the sides and a little up for
## balance, the legs part a little, and the head comes up off the pack to
## look back down the body past the feet (a negative look tips the chin in).
## Same frame as `glide_arm`. Blended in as the body rolls over.
var backstroke_arm := Vector3(0.95, -0.35, -0.3)
var backstroke_leg := Vector3(0.08, -1.0, -0.08)
var backstroke_look := -0.7
## Off the ground the legs stop running. `air_grace` seconds after leaving
## it (so steps and kerbs do not flicker) they go to an air pose, blended in
## at `air_blend` full changes a second. Each pose is a thigh and a shin
## direction per leg in the actor's frame (x right, y up, z back), the lead
## leg first. Leaping: lead knee up, the other leg trailing. Falling: both
## knees a little up and apart, ready to land. Hanging (jets lit or
## thrusting): legs loose under the body, trailing a little.
var air_grace := 0.12
var air_blend := 6.0
var air_toes := 0.45
var leap_legs := [Vector3(0.05, -1.0, -0.75), Vector3(0.0, -1.0, 0.7), Vector3(0.05, -1.0, 0.3), Vector3(0.0, -1.0, 0.55)]
var fall_legs := [Vector3(0.22, -1.0, -0.45), Vector3(0.0, -1.0, 0.5), Vector3(0.2, -1.0, -0.15), Vector3(0.0, -1.0, 0.6)]
var hang_legs := [Vector3(0.07, -1.0, -0.18), Vector3(0.0, -1.0, 0.4), Vector3(0.07, -1.0, 0.08), Vector3(0.0, -1.0, 0.5)]
## Taking off, the legs first push straight down off the ground, toes
## pointed, for `takeoff_time` seconds before they tuck into the leap. A
## running takeoff also leans into the jump, by up to `leap_lean` radians at
## `leap_lean_speed` m/s, and rights itself as the fall begins.
var push_legs := [Vector3(0.04, -1.0, 0.06), Vector3(0.0, -1.0, 0.12), Vector3(0.04, -1.0, 0.2), Vector3(0.0, -1.0, 0.3)]
var push_toes := 0.9
var takeoff_time := 0.22
var leap_lean := 0.32
var leap_lean_speed := 8.0
## Landing, the knees take it: a squat that deepens with how hard you came
## down (full at `land_full_speed` m/s, never less than `land_min` for a
## touchdown worth showing), let out over `land_time` seconds.
var land_full_speed := 14.0
var land_min := 0.3
var land_time := 0.4
## Vertical speed at which a jump counts as fully rising or fully falling.
var air_rise_speed := 4.0
## A jetpack boost flies the same way with the arms held down along the
## sides, a little off the body (Caleb's call: never reaching out ahead).
var boost_arm := Vector3(0.3, -1.0, 0.08)
## How fast the body follows a change of attitude, and the most it banks into
## a turn, in radians. The bank is the real one for the turn: tan = v * w / g.
var attitude_follow := 8.0
var max_bank := 1.1
var bank_follow := 5.0
## Hovering on a jetpack, the body leans the way it flies: radians at full
## fly speed, and how far the legs trail.
var hover_lean := 0.45
## How far a jetpack boost leans the body in as it sets off (radians from
## upright); it lies flat once at full boost speed.
var boost_start_lean := 0.5
## A sideways air dash while flat rolls the body once round its own length;
## after it, the body rights itself at this many radians a second.
var twist_speed := 7.0
## Thruster boots fly by thrust, and the body shows it. The boots must push
## against gravity, against the air (`boot_drag` m/s² for every m/s of
## speed) and toward wherever the flight is speeding up, so the body leans
## into that push (up to `boot_max_lean` radians), the legs point the
## nozzles away from it and the flames swivel up to `boot_gimbal` radians to
## fire straight back along it. Speeding up is read from velocity, smoothed
## at `boot_accel_rate` a second, so remote players match.
## Flying forward the body lies out (`boot_hero_pitch` from upright at
## cruise, `boot_hero_max` at dash speed), streamlined against the air the
## way a skydiver tracks, while the legs drop from the hips so the heel
## thrusters fire down and back: down holds you up, back drives you on.
## Never quite flat, or nothing would hold you up. One knee bends
## (`boot_knee`). The arms ride down by the sides, a little out and ahead
## (`boot_arm`, body frame as `glide_arm`), weapon in hand; shooting or
## aiming brings them up to it and lifts the chest by `boot_aim_ease` of the
## pitch so they have room. The flames stretch with the thrust,
## from `boot_flame_min` to `boot_flame_max` times their length.
var boot_drag := 0.85
var boot_accel_rate := 6.0
var boot_max_lean := 0.8
var boot_hero_pitch := 1.2
var boot_hero_max := 1.38
var boot_knee := 0.9
var boot_arm := Vector3(0.35, -1.0, -0.2)
var boot_aim_ease := 0.3
var boot_gimbal := 0.6
## How far the feet point while boots fire: flat, so each heel nozzle fires
## down its shin.
var boot_toes := 0.0
var boot_flame_min := 0.8
var boot_flame_max := 2.0

## Riding, the head turns at most this far (radians) toward the aim; the
## body stays facing along the vehicle.
var ride_head_turn := 1.1
## Where the wrist sits behind the resting hand spot when a rider holds a gun
## out, in the actor's frame along the aim.
var ride_gun_wrist := Vector3(0.0, -0.02, 0.1)
## Riding, a weapon slung on the back rides this much higher up the back, so
## its lower end clears the seat and the bike's tail.
var ride_sling_lift := 0.28

## Holstered weapons are worn on the body instead of vanishing: a gun is
## slung across the back, muzzle up over the right shoulder, and over the
## outside of a back rig (a jetpack or wings) when one is worn. A two-handed
## melee weapon crosses the back the other way; a one-handed blade hangs from
## the left hip. Distances in meters, in the actor's frame (x right, y up, z back).
var sling_tilt := deg_to_rad(35.0)
var sling_height := -0.2
## Where the back is behind the back bone with nothing worn, and how far the
## middle of a slung weapon sits out from the back or the rig's outer face.
var back_surface := 0.13
var sling_clearance := 0.04
## Over a rig with weapon rails down its sides (a jetpack or wing pack,
## whose back holds its heat gauge), a long weapon is clamped to the rail on its side instead,
## so it never hides the screen: its middle this far up the rail from the
## rail's middle, and this far out from the clamp faces.
var mount_rise := 0.02
var mount_clearance := 0.003
## How far up and down from its middle the rail's clamps hold a weapon.
var mount_band := 0.12
## A worn helmet carries its readouts on the back of the head, for third
## person and for anyone behind you: a health strip that drains and turns red,
## and a light for the helmet's own system. Placed over the "Head" bone.
var vitals_offset := Vector3(0.0, 0.05, 0.172)
## A worn helmet is a shell over the whole head (the head itself is hidden
## under it), with a faceplate in its glass colour and a fitting for what it
## does. Its middle sits this far from the "Head" bone, and the shell is this
## wide, tall and deep. The one model is worn in every view: first person
## leaves it out with the head (`hide_head`), never a copy of its own.
var helmet_offset := Vector3(0.0, 0.1, 0.0)
var helmet_size := Vector3(0.27, 0.31, 0.31)
var helmet_shell_color := Color(0.22, 0.23, 0.25)
## A worn armor frame is plates over the chest (on the "Chest" bone, front
## toward -Z), and from medium up a belly plate and shoulder pads (on the
## upper arm bones); heavy adds a collar. One model in every view.
var frame_offset := Vector3(0.0, 0.0, 0.0)
var pad_offset := Vector3(0.0, 0.0, 0.0)
var vitals_width := 0.13
var vitals_low := 0.35
var hip_offset := Vector3(-0.2, 0.08, 0.02)
## How far a sheathed blade tips from pointing straight up, toward the back.
var sheath_angle := deg_to_rad(138.0)
## A sidearm rides muzzle down in a holster on the right hip.
var holster_offset := Vector3(0.21, -0.02, 0.0)
## Switching weapons is shown, not instant: the hand reaches to the holster
## and puts the old weapon away, moves on to the next one's holster and draws
## it. Seconds for each move. Only the view waits; the actor switched the
## moment it was told.
var reach_time := 0.22
## How long a blade takes to slide out of its hilt when drawn, or back in
## when put away (`Look.set_extend`).
var fold_time := 0.18
var between_time := 0.14
var return_time := 0.2
## Far from the camera a body is posed less often: past each of these
## distances (metres, scaled by the camera's zoom so a scope brings detail
## back) its animation, legs and arm take one longer step every
## `detail_steps` frames instead of one each frame. View only.
var detail_ranges: Array[float] = [35.0, 80.0, 160.0]
var detail_steps: Array[int] = [1, 2, 3, 5]
## The field of view the ranges are for. A narrower view counts as closer.
var detail_fov := 80.0

var look: Node
var actor: Actor

var _player: AnimationPlayer
var _anims := {}
var _current := ""
var _current_sign := 1.0
var _weapons_seen := 0
var _wired := {}
var _flash_left := 0.0
var _materials: Array[ShaderMaterial] = []
var _skeleton: Skeleton3D
var _head_bone := -2
## The eyes, from the head bone (`eye_point`): metres up, and ahead along the
## view.
var eye_up := 0.08
var eye_ahead := 0.12
## The raised watch's glow on the left wrist, and how far it is up (0..1).
var _watch_glow: Node3D
var _watch_up := 0.0
const WATCH_GLOW := Color(0.35, 0.95, 1.0)
var _def := {}
## The flight rig being worn: its item id, the nodes holding its parts, its
## back part (or null), and a flame per nozzle.
var _rig_id := ""
var _rig_holders: Array[Node3D] = []
var _rig_back: Node3D
var _vitals: Node3D
var _helmet: Node3D
var _frame_parts: Array[Node3D] = []
## The frame `_frame_parts` were built for; "" for none.
var _frame_id := ""
## The helmet `_helmet` was built for; "" while bare-headed.
var _helmet_id := ""
var _flames: Array[Node3D] = []
var _burst_left := 0.0
var _spread := 0.0
## 0 standing, 1 flying flat.
var _glide := 0.0
## Bones the glide pose moves: [from, to] pairs to aim, per side.
var _glide_arms: Array = []
var _glide_legs: Array = []
var _glide_neck := -1
## 0 on the ground, 1 in the air pose; and within it, 0 leaping .. 1 falling
## and 0 ballistic .. 1 hanging from the jets.
var _air := 0.0
## Seconds the weapon stays out in flat flight after shooting or aiming, and
## how far the arms have come off the sides to hold it (0 sides, 1 holding).
var _flight_draw_left := 0.0
var _flight_hold := 0.0
var _air_fall := 0.0
var _air_hang := 0.0
## Boots (see `boot_drag`): the velocity lagging behind the real one (world
## space), how far into the thrust pose the body is (0..1) and how far into
## the forward flying pose, which way the exhaust blows (actor space, level,
## unit) and how hard, in g. `_body_turn` is the body's attitude this frame.
var _vel_lag := Vector3.ZERO
var _boot_w := 0.0
var _boot_hero := 0.0
var _exhaust := Vector3.DOWN
var _thrust_g := 1.0
var _body_turn := Basis.IDENTITY
## 1 at the moment of takeoff, running down to 0 over `takeoff_time`.
var _air_push := 0.0
var _was_airborne := false
## How deep the landing squat was, and how much of it is left (1..0).
var _land_depth := 0.0
var _land_left := 0.0
## 0 arms trailing wide (wings), 1 arms in at the sides (boost).
var _boost := 0.0
## Which way the body tips (the actor's space, level) times how far, radians.
var _tilt := Vector3.ZERO
## Roll about the body's length: banking into a turn (positive in a left
## turn), and from a sideways air dash (positive to the right).
var _bank := 0.0
var _twist := 0.0
## How far the model is turned to face the way it flies, radians.
var _face := 0.0
var _last_heading := 0.0
var _has_heading := false
## The actor's yaw last frame: while the body lies flat in flight its
## attitude is held in the world, not on the view (see `_update_glide`).
var _last_yaw := 0.0
## Free look in a glide: how far the body has rolled to face the view, about
## its own length (PI: on its back, a backstroke, looking behind).
var _look_roll := 0.0
## Free look in a glide: the body starts to roll toward the view once it is
## this far off the way it flies, and lies on its back by `look_roll_full`.
var look_roll_start := 0.6
var look_roll_full := 2.6
var _attack_left := 0.0
var _aim_left := 0.0
## Weapon -> the copy of it worn while holstered (null if it has no model),
## and the rig they were placed for.
var _stowed := {}
var _stowed_rig := ""
## Weapon -> the model node inside its worn copy, which lines up with the
## "Model" node under the weapon's own visual.
var _stowed_models := {}
## The weapon shown in the hand, the weapons the hand visits in turn while
## switching (putting `_in_hand` away first), the active weapon that plan is
## for, and how far into it the hand is.
var _in_hand: Weapon
## Melee weapon -> how far its held model is out (1) or folded away (0).
var _extend := {}
var _plan: Array[Weapon] = []
var _plan_for: Weapon
var _plan_t := 0.0
## The weapon moving between hand and holster now, and how far it has gone
## from the hand (0) to the holster (1).
var _moving: Weapon
var _moving_weight := 0.0
## Makes the model hold its weapon, or null for skins without the bones.
var arm: Node
## The head's parts while first person leaves them out (`hide_head`), and
## the bones that count as the head (the neck and everything above it).
var _head_hidden: Array[VisualInstance3D] = []
var _head_bones := {}
## The phone in the hands while `phone_up`, built the first time.
var _phone_prop: Node3D
## What the phone's face shows (`set_phone_screen`); null for lit glass.
var phone_screen: Material
## Matches the legs to the actor's speed and direction.
var locomotion: Node
## Frames between poses now (see `detail_ranges`), frames since the last one
## and the time they add up to.
var _detail_every := 1
var _detail_wait := 0
var _detail_delta := 0.0
## Weapon meshes whose shadows are off while the body is far (`_gear_shadows`).
var _unshadowed: Array[GeometryInstance3D] = []
## How the animation and skeleton ran on their own, to go back to.
var _own_modes: Array[int] = [AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE,
		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE]

func _ready() -> void:
	var skin_name: String = actor.get_meta("look", look.DEFAULT_SKIN)
	var def: Dictionary = look.SKINS.get(skin_name, look.SKINS[look.DEFAULT_SKIN])
	var built: Dictionary = look.character(skin_name, actor.get_meta("appearance", {}), String(actor.name))
	if built.is_empty():
		return
	var model: Node3D = built["model"]
	_materials = built["materials"]
	add_child(model)
	# Pack models face +Z. Actors face -Z.
	rotation.y = PI

	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player:
		for key: String in def.get("anims", {}):
			var found := _find_animation(def["anims"][key])
			if found != "":
				_anims[key] = found
				if key != "death" and key != "attack":
					_player.get_animation(found).loop_mode = Animation.LOOP_LINEAR
		_play("idle")
		_player.advance(0.0)
	look.stand_model(self, model, def["height"])
	_def = def
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton = skeleton
	# Before the arm, so the arm's hooks run after the legs have turned.
	locomotion = Locomotion.new()
	locomotion.name = "Locomotion"
	locomotion.actor = actor
	locomotion.skeleton = skeleton
	add_child(locomotion)
	locomotion.setup(def, _player, _anims)
	if skeleton and def.has("grip_bone"):
		arm = WeaponArm.new()
		arm.name = "WeaponArm"
		arm.actor = actor
		arm.skeleton = skeleton
		arm.look = look
		add_child(arm)
		arm.setup(def, _player.get_animation(_anims["idle_melee"]) if _player and _anims.has("idle_melee") else null)
		if _player:
			arm.calibrate(_player.get_animation(_anims["aim_gun"]) if _anims.has("aim_gun") else null,
					_player.get_animation(_anims["idle_melee"]) if _anims.has("idle_melee") else null)
		# After the arm has put the hand on the model's hand.
		skeleton.skeleton_updated.connect(_carry_moving)
	if skeleton:
		# Last, so the phone has the right hand whatever the arm was doing.
		locomotion.add_phone_hook()
	if skeleton:
		_setup_glide_pose(skeleton, def)

	# The greybox capsule stays as the actor's body node, but draws nothing.
	if actor.body_mesh:
		actor.body_mesh.mesh = null
		for child in actor.body_mesh.get_children():
			if child is MeshInstance3D:
				child.visible = false
	actor.health.damaged.connect(_on_damaged)
	actor.hit_confirmed.connect(_on_hit_confirmed)
	actor.flight.burst_fired.connect(_on_burst)
	actor.landed.connect(_on_landed)


func _find_animation(wanted: String) -> String:
	for anim_name in _player.get_animation_list():
		var short := String(anim_name).get_slice("|", String(anim_name).get_slice_count("|") - 1)
		if short == wanted:
			return anim_name
	return ""


## Plays a clip at a speed, negative to play it backwards. Moving from one
## walk or run clip to another keeps the point in the stride.
func _play(key: String, speed := 1.0) -> void:
	if _player == null or not _anims.has(key):
		return
	_player.speed_scale = speed
	_current_sign = signf(speed) if speed != 0.0 else 1.0
	if _current == key:
		return
	var phase := -1.0
	if _current in GAITS and key in GAITS and _player.current_animation_length > 0.0:
		phase = _player.current_animation_position / _player.current_animation_length
	var previous := _current
	_current = key
	if locomotion:
		locomotion.current_anim = _anims[key]
	var blend := gait_blend if phase >= 0.0 else cut_blend
	if key in STANDS or previous in STANDS:
		blend = stand_blend
	_player.play(_anims[key], blend)
	if phase >= 0.0:
		_player.seek(phase * _player.current_animation_length)


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_detail_delta += delta
	_detail_wait += 1
	if _detail_wait < _detail_every:
		# The actor puts its hand back every tick; keep the weapon on the
		# model's hand as it was last posed.
		if arm != null and _skeleton != null:
			arm.hold_weapon()
		return
	var step := _detail_delta
	_detail_delta = 0.0
	_detail_wait = 0
	_set_detail(detail_step())
	_update(step)
	if _detail_every > 1:
		if _player:
			_player.advance(step)
		if _skeleton:
			_skeleton.advance(step)


## How many frames apart this body is posed, from how far it is from the
## camera and how far the camera is zoomed in. Every frame without a camera.
func detail_step() -> int:
	if not is_inside_tree():
		return 1
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return 1
	var seen := camera.global_position.distance_to(global_position) \
			* tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(detail_fov) * 0.5)
	for i in detail_ranges.size():
		if seen < detail_ranges[i]:
			return detail_steps[mini(i, detail_steps.size() - 1)]
	return detail_steps[-1]


## Posed every frame, the model's animation and skeleton run on their own as
## usual; posed less often, `_process` steps them by hand.
func _set_detail(every: int) -> void:
	every = maxi(every, 1)
	if (every > 1) == (_detail_every > 1):
		_detail_every = every
		return
	_detail_every = every
	if _player:
		if every > 1:
			_own_modes[0] = _player.callback_mode_process
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if every > 1 \
				else _own_modes[0]
	if _skeleton:
		if every > 1:
			_own_modes[1] = _skeleton.modifier_callback_mode_process
		_skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL if every > 1 \
				else _own_modes[1]
	if every > 1:
		# Spread the bodies out, so they do not all take their step together.
		_detail_wait = int(get_instance_id() % every)
	_gear_shadows(every == 1)


## Weapons cast shadows only on a body posed every frame (close by): further
## out a gun's shadow is a few pixels, but it costs a draw in every shadow
## split. Only what cast a shadow before is switched back on.
func _gear_shadows(on: bool) -> void:
	if on:
		for node in _unshadowed:
			if is_instance_valid(node):
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_unshadowed.clear()
		return
	var holders: Array[Node] = []
	for weapon in actor.weapons:
		if weapon.visual:
			holders.append(weapon.visual)
	for worn: Variant in _stowed.values():
		if worn != null and is_instance_valid(worn):
			holders.append(worn)
	for holder in holders:
		for node in holder.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			if geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_unshadowed.append(geometry)


func _update(delta: float) -> void:
	if actor.body_mesh:
		visible = actor.body_mesh.visible
	if actor.weapons.size() != _weapons_seen or _has_bare_weapon():
		_dress_weapons()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_set_flash(0.0)
	_flight_draw_left = aim_hold if actor.cmd.primary or actor.cmd.secondary else maxf(_flight_draw_left - delta, 0.0)
	_flight_hold = move_toward(_flight_hold, 1.0 if _flight_draw_left > 0.0 else 0.0, glide_blend * delta)
	_update_boot_thrust(delta)
	_update_rig(delta)
	_update_glide(delta)
	_update_stowed()
	_update_switch(delta)
	_update_helmet()
	_update_frame()
	_update_vitals()
	_update_phone()
	_update_watch_glow(delta)
	_update_cloak()
	_update_materialize()
	_update_toy(delta)
	_aim_left = maxf(_aim_left - delta, 0.0)
	var weapon := actor.get_active_weapon()
	if phone_up() or toy_up():
		# Hands on the phone or a toy: stand as if empty-handed.
		weapon = null
	var melee := weapon as MeleeWeapon
	if weapon is Gun and (actor.cmd.primary or actor.cmd.secondary):
		_aim_left = aim_hold
	if locomotion == null:
		return
	_update_ride()
	locomotion.update(delta)
	locomotion.twist_target = 0.0
	locomotion.stride_target = 1.0
	locomotion.overlay = false
	locomotion.stand_legs = false
	ActionPose.of(actor).carry_wanted = false
	if actor.is_dead:
		_play("death")
		return
	if melee and melee.is_winding_up() and _attack_left <= 0.0:
		_attack_left = 0.6
		_current = ""
		_play("attack", 1.3)
	_attack_left -= delta
	if _attack_left > 0.0:
		return
	# In a fight (shooting, aiming, reloading, or just after) the gun stays up
	# on the move, pointing where it shoots; out of one it is carried.
	var armed := weapon != null and melee == null and _anims.has("move_gun") and in_fight(weapon)
	# Read from velocity alone, so a remote player, whose velocity comes with
	# each state from the server, moves its legs the same as a local one.
	var gait: Dictionary = {} if actor.vehicle != null or _glide > 0.0 else \
			locomotion.choose(locomotion.velocity, armed, _current, _current_sign)
	var airborne := is_airborne()
	_update_air(delta, airborne)
	if actor.vehicle != null:
		# Seated by the locomotion's riding pose over the clip of an empty,
		# armed or blade-holding stand, which still decides the weapon arm.
		_play("idle_melee" if melee and _anims.has("idle_melee") else stand_key(weapon))
	elif _glide > 0.0:
		_play("idle")
	elif airborne:
		# No ground under the feet: never a run cycle. A stand plays under
		# the air pose, so the arms keep their hold on the weapon.
		_play("idle_melee" if melee and _anims.has("idle_melee") else stand_key(weapon))
		locomotion.stand_legs = _current == "idle_gun"
	elif actor.is_sliding():
		# The slide pose bends whatever plays under it; the arms keep their
		# hold: a gun carried, or raised to shoot out of the slide.
		_play("idle_melee" if melee and _anims.has("idle_melee") else stand_key(weapon))
		locomotion.twist_target = clampf(Locomotion.heading(locomotion.velocity), -locomotion.max_twist, locomotion.max_twist)
	elif not gait.is_empty():
		_play(gait["key"], gait["speed"])
		locomotion.twist_target = gait["twist"]
		locomotion.stride_target = gait["stride"]
		locomotion.overlay = armed and gait["key"] != "move_gun"
		if _player and _player.current_animation_length > 0.0:
			locomotion.overlay_phase = _player.current_animation_position / _player.current_animation_length
	elif melee and _anims.has("idle_melee"):
		_play("idle_melee")
	else:
		_play(stand_key(weapon))
		locomotion.stand_legs = _current == "idle_gun"
	_update_carry(weapon, gait, airborne)


## True while `weapon` (a gun) is in a fight: shooting or aiming now or in
## the last `aim_hold`, or reloading. Read from the command and the gun, so
## a remote player's gun comes up when they shoot too.
func in_fight(weapon: Weapon) -> bool:
	var gun := weapon as Gun
	if gun == null:
		return false
	return _aim_left > 0.0 or gun.is_aiming() or gun.is_reloading()


## Tells the shared pose how the gun in hand is carried on the move: out of
## a fight, moving on foot (or sliding, or in a running jump), a gun goes to
## its carry, the low ready at a jog and the sprint carry at a sprint, and
## bobs with the stride. View only, from velocity, so remote players match.
func _update_carry(weapon: Weapon, gait: Dictionary, airborne: bool) -> void:
	var pose := ActionPose.of(actor)
	var gun := weapon as Gun
	var flat := Vector3(locomotion.velocity.x, 0.0, locomotion.velocity.z)
	var moving: bool = flat.length() > locomotion.move_threshold
	var on_foot := actor.vehicle == null and _glide <= 0.0 and not actor.is_dead and not phone_up()
	pose.carry_wanted = gun != null and gun.visual != null and on_foot and not in_fight(gun) \
			and (actor.is_sliding() or (moving and (airborne or not gait.is_empty())))
	var pace := actor.walk_speed * gun.move_speed_mult() if gun != null else actor.walk_speed
	if actor.flight.enabled:
		pace *= actor.flight.ground_speed_mult
	var ratio := flat.length() / maxf(pace, 0.1)
	# Forward only: a strafe or a backpedal keeps the low ready.
	var ahead := clampf(-flat.z / maxf(flat.length(), 0.001), 0.0, 1.0)
	var sprinting := not airborne and not actor.is_sliding() and not gait.is_empty()
	pose.sprint_wanted = smoothstep(sprint_from.x, sprint_from.y, ratio) * smoothstep(0.6, 0.9, ahead) if sprinting else 0.0
	if not gait.is_empty() and _player and _player.current_animation_length > 0.0:
		pose.stride_phase = _player.current_animation_position / _player.current_animation_length
		pose.stride_amount = clampf(ratio / sprint_from.y, 0.0, 1.0)
	else:
		pose.stride_amount = 0.0


## True while the body lies flat in flight (gliding or boosting) and is not
## shooting or aiming: the weapon in hand is shown worn. View only; first
## person puts it away too, since both views show the same body.
func flies_stowed() -> bool:
	if actor.is_dead or actor.vehicle != null:
		return false
	if not (actor.flight.is_gliding or actor.flight.is_boosting):
		return false
	return _flight_draw_left <= 0.0


## First person looks out from inside the head, so the head and whatever
## is worn on it go on `Mirror.HEAD_LAYER`, which that camera leaves out
## (everyone else's camera, the mirror's and the shadows still see it). The
## rest of the body is drawn as it is in third person: the view is the only
## difference (Caleb's rule). Called every frame by the controller.
func hide_head(on: bool) -> void:
	var bit := 1 << (MirrorScript.HEAD_LAYER - 1)
	if not on:
		for node in _head_hidden:
			if is_instance_valid(node) and node.layers == bit:
				node.layers = node.get_meta("layers_before", 1)
		_head_hidden.clear()
		return
	if _skeleton == null:
		return
	if _head_bones.is_empty():
		var neck := _skeleton.find_bone("Neck")
		if neck < 0:
			neck = _skeleton.find_bone("Head")
		var stack: Array[int] = []
		if neck >= 0:
			stack.append(neck)
		while not stack.is_empty():
			var bone: int = stack.pop_back()
			_head_bones[_skeleton.get_bone_name(bone)] = true
			for child in _skeleton.get_bone_children(bone):
				stack.append(child)
	for node in _skeleton.get_children():
		var parts: Array[Node] = []
		if node is MeshInstance3D and node.get_meta("slot", "") == "head":
			parts.append(node)
		elif node is BoneAttachment3D and _head_bones.has((node as BoneAttachment3D).bone_name):
			parts.append_array(node.find_children("*", "VisualInstance3D", true, false))
		for part: Node in parts:
			var visual := part as VisualInstance3D
			if visual.layers != bit:
				visual.set_meta("layers_before", visual.layers)
				visual.layers = bit
				if not _head_hidden.has(visual):
					_head_hidden.append(visual)


## Where the model's eyes are, for a first-person camera: in front of the
## head bone along the view (`look`), so the camera looks out of the face
## rather than from inside the skull or the collar, and moves with the head
## as the body leans. Null without a head bone.
func eye_point(look: Basis) -> Variant:
	if _skeleton == null:
		return null
	if _head_bone == -2:
		_head_bone = _skeleton.find_bone("Head")
	if _head_bone < 0:
		return null
	var head: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone).origin
	return head + Vector3.UP * eye_up + look * Vector3(0.0, 0.0, -eye_ahead)


## True while the actor holds their phone up (`ActorCommand.phone`, which
## travels with the held keys, so remote players show it too). The weapon is
## worn meanwhile and drawn again when the phone goes away.
func phone_up() -> bool:
	return actor.cmd.phone and not actor.is_dead and actor.vehicle == null


## Eases the phone hold in and out and keeps the phone itself in the right
## hand, the fist round its grip and its screen turned up to the face.
func _update_phone() -> void:
	if locomotion == null:
		return
	locomotion.phone_up = phone_up()
	var w: float = locomotion.phone_weight
	if w <= 0.0:
		if _phone_prop:
			_phone_prop.visible = false
		return
	if _phone_prop == null:
		_phone_prop = _build_phone_prop()
		add_child(_phone_prop)
	_phone_prop.visible = w > 0.5
	var held: Vector3 = locomotion.phone_in_hand if locomotion.phone_in_hand != Vector3.ZERO else locomotion.phone_at
	var at: Vector3 = actor.global_transform * held
	var eyes := actor.global_transform * Vector3(0.0, actor.eye_height, 0.0)
	var face := (eyes - at).normalized()
	# Upright in the hand, its face turned to the eyes.
	var basis := Basis.looking_at(-face, Vector3.UP)
	_phone_prop.global_transform = Transform3D(basis, at)


## The phone in the hand: the handheld (`core/phone/handheld.gd`), the one
## model every view shows, with a faint light from its screen so a player on
## their phone reads from afar. Its face shows `phone_screen` when set (your
## own phone's screen), else lit glass.
func _build_phone_prop() -> Node3D:
	var root := Handheld.build(phone_screen)
	root.name = "PhoneProp"
	_phone_prop = root
	_dress_phone_screen()
	var glow := OmniLight3D.new()
	glow.light_color = UiTheme.ACCENT.lerp(Color.WHITE, 0.4)
	glow.light_energy = 0.3
	glow.omni_range = 0.6
	glow.position = -Handheld.grip_in_body() + Vector3(0.0, 0.0, 0.08)
	glow.shadow_enabled = false
	root.add_child(glow)
	return root


## The phone being held, or null while it is put away (or never built).
func handheld() -> Node3D:
	return _phone_prop if _phone_prop != null and _phone_prop.visible else null


## Sets what the phone shows on its face and its holo panel: your own
## phone's screen, or null for lit glass and an unreadable sheen.
func set_phone_screen(screen: Material) -> void:
	phone_screen = screen
	_dress_phone_screen()


func _dress_phone_screen() -> void:
	var face := Handheld.face_of(_phone_prop)
	if face != null:
		face.set_surface_override_material(0, phone_screen if phone_screen != null else Handheld.glass_material())
	var holo := Handheld.holo_of(_phone_prop)
	if holo != null:
		var picture: Texture2D = (phone_screen as StandardMaterial3D).albedo_texture if phone_screen is StandardMaterial3D else null
		holo.material_override = Handheld.holo_material(picture)


## True once the actor has been off the ground long enough to show it.
## Read from the actor's own timer, which a client keeps for remote players
## too (it simulates them from their commands).
func is_airborne() -> bool:
	return not actor.is_dead and actor.vehicle == null and actor.airborne_time > air_grace


## A touchdown: starts the landing squat. Called for remote players too,
## whose landing this game simulates from their commands.
func _on_landed(impact_speed: float) -> void:
	if impact_speed < 1.0 or actor.is_dead or actor.vehicle != null:
		return
	_land_depth = clampf(impact_speed / land_full_speed, land_min, 1.0)
	_land_left = 1.0


## Eases the air pose in and out and between its shapes, and plays out the
## takeoff push and the landing squat.
func _update_air(delta: float, airborne: bool) -> void:
	_air = move_toward(_air, 1.0 if airborne else 0.0, air_blend * delta)
	if airborne and not _was_airborne:
		# Going up is a takeoff; walking off a ledge is not.
		_air_push = 1.0 if actor.velocity.y > 1.0 else 0.0
		_land_left = 0.0
	_was_airborne = airborne
	_air_push = move_toward(_air_push, 0.0, delta / takeoff_time)
	_land_left = move_toward(_land_left, 0.0, delta / land_time)
	if locomotion:
		# Down fast, up slow: sin over the squat's life, peaking early.
		var life := 1.0 - _land_left
		locomotion.squat = _land_depth * sin(PI * pow(life, 0.55)) if _land_left > 0.0 and not actor.is_sliding() and actor.vehicle == null else 0.0
	if not airborne:
		return
	var follow := 1.0 - exp(-attitude_follow * delta)
	var jets := actor.flight.is_hovering or actor.flight.is_thrusting or actor.flight.is_skimming
	_air_hang = lerpf(_air_hang, 1.0 if jets else 0.0, follow)
	_air_fall = lerpf(_air_fall, clampf(0.5 - actor.velocity.y / (2.0 * air_rise_speed), 0.0, 1.0), follow)


## The clip for standing still out of a fight: hands empty, a gun held low,
## or a gun raised while the actor shoots or aims and for `aim_hold` after.
## Skins without the gun clips fall back to plain `idle`.
func stand_key(weapon: Weapon) -> String:
	if phone_up() and _anims.has("idle_gun"):
		# The fist of a gun held low closes round the phone's grip.
		return "idle_gun"
	if weapon == null or weapon is MeleeWeapon or weapon.visual == null:
		return "idle"
	if actor.cmd.primary or actor.cmd.secondary:
		_aim_left = aim_hold
	if _aim_left > 0.0 and _anims.has("aim_gun"):
		return "aim_gun"
	return "idle_gun" if _anims.has("idle_gun") else "idle"


## True when a weapon was swapped in without the count changing.
func _has_bare_weapon() -> bool:
	for weapon in actor.weapons:
		if weapon.visual and not weapon.visual.has_meta("dressed"):
			return true
	return false


## Swaps greybox gun parts for a model and wires up shot effects. Runs again
## whenever the actor's weapon list changes.
func _dress_weapons() -> void:
	_weapons_seen = actor.weapons.size()
	for weapon in actor.weapons:
		if weapon.visual == null:
			continue
		# Shot effects belong to this skin, so a skin that replaces an earlier
		# one wires them up again even though the models are already on.
		var gun := weapon as Gun
		if gun and not _wired.has(gun):
			_wired[gun] = true
			gun.fired.connect(_on_fired.bind(gun))
		if weapon.visual.has_meta("dressed"):
			continue
		weapon.visual.set_meta("dressed", true)
		var model: Node3D = look.weapon_model(weapon)
		if model:
			for child in weapon.visual.get_children():
				if child is MeshInstance3D:
					child.visible = false
			weapon.visual.add_child(model)
			look.mount_attachments(weapon.visual)
		elif weapon is MeleeWeapon:
			look.restyle_melee(weapon.visual)
	if _detail_every > 1:
		_gear_shadows(false)


## Shows every holstered weapon where it is worn, and hides the one in hand.
func _update_stowed() -> void:
	if _skeleton == null:
		return
	if _stowed_rig != _rig_id:
		_stowed_rig = _rig_id
		_clear_stowed()
	for weapon: Variant in _stowed.keys():
		if not is_instance_valid(weapon) or not weapon in actor.weapons:
			if _stowed[weapon]:
				_stowed[weapon].queue_free()
			_stowed.erase(weapon)
			_stowed_models.erase(weapon)
			_extend.erase(weapon)
	for weapon in actor.weapons:
		# Every weapon gets its worn copy, the one in hand too, so a draw
		# can start from it.
		if weapon.visual != null and not actor.is_dead and not _stowed.has(weapon):
			_stowed[weapon] = _stow(weapon)
	# Riding, what is slung on the back moves up it, clear of the seat.
	var lift := ride_sling_lift * (smoothstep(0.0, 1.0, locomotion.ride_weight) if locomotion else 0.0)
	for weapon: Variant in _stowed:
		var root: Node3D = _stowed[weapon]
		if root == null or not root.get_meta("slung", false):
			continue
		var holder := root.get_node_or_null("Part") as Node3D
		if holder != null and holder.has_meta("rest"):
			var rest: Transform3D = holder.get_meta("rest")
			holder.transform = Transform3D(rest.basis, rest.origin + (holder.get_meta("up") as Vector3) * lift)


## Plays a weapon switch: the hand reaches to each holster in `_plan` in turn,
## a weapon put away goes onto the body as the hand arrives, and one drawn
## leaves the body and comes back with the hand. Then shows each weapon in
## its place: the one in hand on the hand, the rest where they are worn.
func _update_switch(delta: float) -> void:
	var active := actor.get_active_weapon()
	# Flying flat with the arms at the sides, the weapon is worn, not left
	# hanging in the air where the hands were. Shooting or aiming draws it.
	if flies_stowed() or phone_up() or toy_up():
		active = null
	if _in_hand != null and (not is_instance_valid(_in_hand) or not _in_hand in actor.weapons):
		_in_hand = null
	_moving = null
	_moving_weight = 0.0
	var instant := arm == null or actor.is_dead or _skeleton == null
	if instant or (_plan.is_empty() and _in_hand == active):
		_in_hand = active
		_plan_for = active
		_plan.clear()
	elif _plan_for != active or _plan.is_empty():
		# A new switch, or a change of mind halfway: go from what is in hand.
		_plan.clear()
		for weapon in [_in_hand, active]:
			if weapon != null and _stowed_models.get(weapon) != null and not weapon in _plan:
				_plan.append(weapon)
		_plan_for = active
		_plan_t = 0.0
		if _plan.is_empty():
			_in_hand = active
	if not _plan.is_empty():
		_plan_t += delta
		_play_plan()
	if arm:
		arm.override_weight = _moving_weight if _moving else 0.0
		if _moving:
			arm.override_point = _hand_at_holster(_moving)
	var pose := ActionPose.of(actor)
	pose.low_wanted = _current == "idle_gun"
	# A toy comes up only once the weapon is put away.
	pose.toy_hand_free = _in_hand == null
	for weapon in actor.weapons:
		if weapon.visual:
			weapon.visual.visible = weapon == _in_hand
		var worn: Node3D = _stowed.get(weapon)
		if worn:
			worn.visible = weapon != _in_hand and weapon.visual != null and not actor.is_dead
	_update_fold(delta)


## A blade slides out of its hilt once it is in hand and back in as the hand
## takes it to put it away, so it is worn folded (see `_stow`). A weapon
## already in hand when first seen starts out.
func _update_fold(delta: float) -> void:
	for weapon in actor.weapons:
		if not weapon is MeleeWeapon or weapon.visual == null:
			continue
		var held: Node3D = weapon.visual.get_node_or_null("Model")
		if held == null:
			continue
		var target := 1.0 if weapon == _in_hand and (_plan.is_empty() or weapon == _plan_for) else 0.0
		var now: float = _extend.get(weapon, -1.0)
		var next := target if now < 0.0 else move_toward(now, target, delta / fold_time)
		if next != now:
			look.set_extend(held, next)
			_extend[weapon] = next


## Where the plan has got to at `_plan_t`: which weapon the hand is with,
## how far toward its holster, and what has changed hands on the way.
func _play_plan() -> void:
	var arrive: Array[float] = []
	for i in _plan.size():
		arrive.append(reach_time + between_time * i)
	var last := arrive[arrive.size() - 1]
	for i in _plan.size():
		if _plan_t >= arrive[i]:
			var weapon := _plan[i]
			# Arriving at a holster: put the weapon away, or take it out.
			if weapon == _in_hand and weapon != _plan_for:
				_in_hand = null
			elif weapon == _plan_for:
				_in_hand = weapon
	if _plan_t >= last + return_time:
		_plan.clear()
		_in_hand = _plan_for
		return
	if _plan_t < arrive[0]:
		_moving = _plan[0]
		_moving_weight = smoothstep(0.0, reach_time, _plan_t)
	elif _plan_t < last:
		var i := int((_plan_t - reach_time) / between_time)
		var u := (_plan_t - arrive[i]) / between_time
		# Between two holsters the hand carries nothing it has not put away.
		_moving = _plan[i + 1] if u > 0.5 else _plan[i]
		_moving_weight = 1.0
	else:
		_moving = _plan[_plan.size() - 1]
		_moving_weight = 1.0 - smoothstep(last, last + return_time, _plan_t)


## Where the weapon hand goes to take a weapon from its holster: the spot its
## hand point has in the worn copy, in the actor's frame.
func _hand_at_holster(weapon: Weapon) -> Vector3:
	var model: Node3D = _stowed_models.get(weapon)
	var held: Node3D = weapon.visual.get_node_or_null("Model") if weapon.visual else null
	if model == null or held == null or not model.is_inside_tree():
		return Actor.HAND_REST
	var hand: Transform3D = model.global_transform * held.transform.affine_inverse()
	return actor.global_transform.affine_inverse() * hand.origin


## After the hand is placed each frame: the weapon moving between hand and
## holster is turned and carried from how it is held toward how it is worn,
## so it lands exactly in place when the hand gets there.
func _carry_moving() -> void:
	for weapon in actor.weapons:
		var held: Node3D = weapon.visual.get_node_or_null("Model") if weapon.visual else null
		if held == null:
			continue
		if not held.has_meta("held_at"):
			held.set_meta("held_at", held.transform)
		var base: Transform3D = held.get_meta("held_at")
		var worn: Node3D = _stowed_models.get(weapon)
		if weapon != _moving or worn == null or _moving_weight <= 0.0 or not worn.is_inside_tree():
			held.transform = base
			continue
		var from := weapon.visual.global_transform * base
		held.global_transform = from.interpolate_with(worn.global_transform, _moving_weight)


func _clear_stowed() -> void:
	for weapon: Variant in _stowed:
		if _stowed[weapon]:
			_stowed[weapon].queue_free()
	_stowed.clear()
	_stowed_models.clear()


## Where a holstered weapon is worn: {"bone", "at" (from the bone, actor
## frame), "basis" (turns the model from how it is held), "centre" (true to
## hang it by its middle rather than its grip)}.
func stow_place(weapon: Weapon) -> Dictionary:
	var back_bone: String = _def.get("back_bone", "")
	var out := Vector3(0.0, sling_height, back_surface + sling_clearance)
	if _rig_back:
		var box: AABB = look.model_bounds(_rig_back)
		out.z = back_gap + box.end.z + sling_clearance
	if weapon is MeleeWeapon and not look.is_two_handed(weapon):
		# Blades stand along +Y with the grip at the origin: tip it down and
		# back from the hip, grip up by the belt.
		return {"bone": _def.get("hip_bone", ""), "at": hip_offset, "basis": Basis(Vector3.RIGHT, sheath_angle),
			"centre": false}
	if is_sidearm(weapon):
		# Muzzle down, grip to the rear, its side to the world.
		return {"bone": _def.get("hip_bone", ""), "at": holster_offset, "basis": Basis(Vector3.RIGHT, -PI / 2.0),
			"centre": false}
	var side := 1.0 if weapon is Gun else -1.0
	# Guns point along -Z in the hand, top up: roll it onto its side so its
	# profile shows, and stand it muzzle up. Long blades already stand up.
	var upright := Basis.IDENTITY if weapon is MeleeWeapon \
			else Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.BACK, PI / 2.0)
	var mount := _rig_back.get_node_or_null("MountR" if side > 0.0 else "MountL") as Marker3D if _rig_back else null
	if mount:
		# Clamped to the rail on the pack's side (gun right, long blade left),
		# leaning out with it. `_stow` moves it out by its own half width.
		return {"bone": back_bone, "at": Vector3(0, back_drop, back_gap) + mount.position + mount.basis.y * mount_rise,
			"basis": mount.basis * upright, "centre": true, "out": mount.basis.x * side, "upright": upright, "side": side}
	if weapon is MeleeWeapon:
		# Head up over the left shoulder, crossing a slung gun.
		return {"bone": back_bone, "at": out + Vector3(0, 0, sling_clearance), "basis": Basis(Vector3.BACK, sling_tilt),
			"centre": true}
	# A gun leans over the right shoulder.
	return {"bone": back_bone, "at": out, "basis": Basis(Vector3.BACK, -sling_tilt) * upright, "centre": true}


## What the light on a helmet's back says: "" (a plain visor has none),
## "running" (zoomed, scanning, sensing, thermal on), "ready" or "charging".
static func helmet_light(v: Visor) -> String:
	if not v.enabled or v.mode == "":
		return ""
	if v.is_zoomed() or v.is_sensing() or v.thermal_on:
		return "running"
	match v.mode:
		"scan", "threat":
			return "ready" if v.cooldown_left <= 0.0 else "charging"
		"thermal":
			return "ready" if v.charge_fraction() >= 0.25 else "charging"
	return "ready"


## Puts the worn helmet on the head, rebuilt when another goes on, and hides
## the head under it. Bare-headed, the head shows again.
func _update_helmet() -> void:
	var id := actor.visor.item_id if actor.visor.enabled else ""
	if id == _helmet_id and (id == "" or is_instance_valid(_helmet)):
		return
	_helmet_id = id
	if _helmet != null and is_instance_valid(_helmet):
		_helmet.queue_free()
	_helmet = null
	if _skeleton != null:
		for node in _skeleton.get_children():
			if node is MeshInstance3D and node.get_meta("slot", "") == "head":
				(node as MeshInstance3D).visible = id == ""
	if id == "":
		return
	var bone: String = "Head" if _skeleton and _skeleton.find_bone("Head") >= 0 else _def.get("neck", "")
	_helmet = _hang(build_helmet(actor.visor.mode, actor.visor.glass_color, helmet_size, helmet_shell_color),
			"Helmet", bone, helmet_offset, Vector3(0.0, _def.get("height", 1.8) * 0.93, 0.0) + helmet_offset)


## The helmet model for a visor `mode` (see `Visor`): a shell of `size` round
## the head, front toward -Z, a faceplate lit in `glass`, and the mode's
## fitting: twin lenses (zoom), a sensor fin (scan), a brow and cheek plates
## (threat), one round lens (thermal). A plain visor is a dull, cracked band.
static func build_helmet(mode: String, glass: Color, size: Vector3, shell_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "HelmetModel"
	var shell := _solid(shell_color, 0.0)
	var plate := _solid(shell_color.lightened(0.12), 0.0)
	var lit := _solid(glass, 0.9 if mode != "" else 0.25)
	# The dome and the band round the sides and back.
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 1.0
	_piece(root, "Shell", dome, shell, Vector3(0, 0.0, 0), size)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.5
	neck.bottom_radius = 0.55
	neck.height = 1.0
	_piece(root, "Neck", neck, shell, Vector3(0, -size.y * 0.45, size.z * 0.06),
			Vector3(size.x * 0.55, size.y * 0.2, size.z * 0.55))
	# The faceplate: glass over the eyes, wrapped round the front of the shell.
	var face := SphereMesh.new()
	face.radius = 0.5
	face.height = 1.0
	_piece(root, "Glass", face, lit, Vector3(0, -size.y * 0.04, -size.z * 0.12),
			Vector3(size.x * 0.96, size.y * 0.4, size.z * 0.84))
	if mode == "":
		# A plain visor's glass is cracked across.
		var crack := _piece(root, "Crack", BoxMesh.new(), _solid(Color(0.05, 0.05, 0.05), 0.0),
				Vector3(size.x * 0.12, -size.y * 0.02, -size.z * 0.535), Vector3(size.x * 0.32, 0.006, 0.006))
		crack.rotation.z = 0.5
		return root
	match mode:
		"zoom":
			# Twin lens barrels over the right eye, out from the glass.
			var tube := CylinderMesh.new()
			tube.top_radius = 0.5
			tube.bottom_radius = 0.5
			tube.height = 1.0
			for i in 2:
				var barrel := _piece(root, "Lens%d" % i, tube, plate,
						Vector3(size.x * (0.16 + 0.13 * i), size.y * 0.02, -size.z * 0.5 + 0.03 * i),
						Vector3(0.05 - 0.01 * i, 0.09, 0.05 - 0.01 * i))
				barrel.rotation.x = PI * 0.5
				var cap := _piece(root, "LensGlass%d" % i, tube, lit,
						barrel.position + Vector3(0, 0, -0.046), Vector3(0.04 - 0.01 * i, 0.004, 0.04 - 0.01 * i))
				cap.rotation.x = PI * 0.5
		"scan":
			# A sensor fin along the crown with a lit edge.
			_piece(root, "Fin", BoxMesh.new(), plate, Vector3(0, size.y * 0.48, size.z * 0.08),
					Vector3(0.022, 0.05, size.z * 0.6))
			_piece(root, "FinEdge", BoxMesh.new(), lit, Vector3(0, size.y * 0.48 + 0.026, size.z * 0.08),
					Vector3(0.026, 0.006, size.z * 0.5))
		"threat":
			# A heavy brow and plates down the cheeks.
			_piece(root, "Brow", BoxMesh.new(), plate, Vector3(0, size.y * 0.17, -size.z * 0.4),
					Vector3(size.x * 0.9, 0.035, 0.07))
			for side: float in [-1.0, 1.0]:
				var cheek := _piece(root, "Cheek", BoxMesh.new(), plate,
						Vector3(side * size.x * 0.44, -size.y * 0.2, -size.z * 0.22), Vector3(0.03, 0.1, 0.11))
				cheek.rotation.y = side * 0.5
		"thermal":
			# One round lens in the middle of the glass.
			var ring := CylinderMesh.new()
			ring.top_radius = 0.5
			ring.bottom_radius = 0.5
			ring.height = 1.0
			var lens := _piece(root, "Lens", ring, plate, Vector3(0, -size.y * 0.04, -size.z * 0.53),
					Vector3(0.11, 0.04, 0.11))
			lens.rotation.x = PI * 0.5
			var eye := _piece(root, "LensGlass", ring, _solid(glass, 1.6), lens.position + Vector3(0, 0, -0.022),
					Vector3(0.08, 0.004, 0.08))
			eye.rotation.x = PI * 0.5
	return root


## The colour every frame's plates are drawn in.
const FRAME_COLOR := Color(0.46, 0.48, 0.45)


## How heavy a frame looks: "light", "medium" or "heavy", from its tags.
static func frame_weight(id: String) -> String:
	if ItemDB.has_tag(id, "frame_heavy"):
		return "heavy"
	return "medium" if ItemDB.has_tag(id, "frame_medium") else "light"


## Puts the worn armor frame's plates on the body, rebuilt when another goes on.
func _update_frame() -> void:
	var id := actor.frame_id
	if id == _frame_id and (id == "" or (not _frame_parts.is_empty() and is_instance_valid(_frame_parts[0]))):
		return
	_frame_id = id
	for part in _frame_parts:
		if is_instance_valid(part):
			part.queue_free()
	_frame_parts.clear()
	if id == "" or _skeleton == null:
		return
	var weight := frame_weight(id)
	var height: float = _def.get("height", 1.8)
	_frame_parts.append(_hang(build_frame(weight, FRAME_COLOR), "Frame", _def.get("back_bone", ""), frame_offset,
			Vector3(0.0, height * 0.72, 0.0) + frame_offset))
	if weight == "light":
		return
	for side: String in ["L", "R"]:
		var out := -1.0 if side == "L" else 1.0
		_frame_parts.append(_hang(build_pad(weight, FRAME_COLOR, out), "Pad" + side, "UpperArm." + side,
				Vector3(pad_offset.x * out, pad_offset.y, pad_offset.z),
				Vector3(0.2 * out, height * 0.8, 0.0)))


## A frame's plates for its `weight`, front toward -Z, built round the chest
## bone and shaped to the torso (thin curved shells, bevelled at the edges,
## a finger's width off the body), so they never stand out like boxes. The
## tier shows in coverage, not bulk: light is a breastplate, medium wraps it
## round the ribs and adds a belly lame, heavy closes it into a cuirass with
## a back plate, a second lame and a collar.
static func build_frame(weight: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "FrameModel"
	var shell := _solid(color, 0.0)
	var trim := _solid(color.darkened(0.45), 0.0)
	# The torso round the chest bone, with the plates' gap off it.
	var rx := 0.128 + FRAME_GAP
	var rz := 0.108 + FRAME_GAP
	var mid := Vector3(0.0, 0.0, 0.005)
	var wrap := {"light": 0.95, "medium": 1.35, "heavy": 1.7}[weight] as float
	var low := {"light": -0.06, "medium": -0.1, "heavy": -0.12}[weight] as float
	_plate(root, "Chest", _shell(rx, rz, -wrap, wrap, low, 0.11, FRAME_THICK, 0.012, 0.08), shell, mid)
	# A lit seam down the middle of the breastplate.
	_plate(root, "Seam", _shell(rx + FRAME_THICK, rz + FRAME_THICK, -0.03, 0.03, low + 0.03, 0.08, 0.004, 0.012),
			_solid(Color(0.4, 0.85, 0.9), 0.8), mid)
	# The lower edge of the breastplate, a darker band.
	_plate(root, "Trim", _shell(rx + 0.002, rz + 0.002, -wrap * 0.92, wrap * 0.92, low - 0.008, low + 0.01,
			FRAME_THICK + 0.004), trim, mid)
	if weight != "light":
		# Lames over the belly, narrower than the chest, each just under the last.
		var lames := 2 if weight == "heavy" else 1
		for i in lames:
			var top := low - 0.02 - i * 0.07
			_plate(root, "Belly" if i == 0 else "Belly%d" % i,
					_shell(0.114 + FRAME_GAP, 0.1 + FRAME_GAP, -1.0, 1.0, top - 0.06, top, FRAME_THICK, 0.004), shell, mid)
	if weight == "heavy":
		_plate(root, "Back", _shell(rx, rz, PI - 1.2, PI + 1.2, low, 0.11, FRAME_THICK, 0.008, 0.08), shell, mid)
		# A low collar round the base of the neck, under the chin.
		_plate(root, "Collar", _shell(0.1, 0.09, -2.3, 2.3, 0.115, 0.15, FRAME_THICK, 0.0, -0.3), trim,
				Vector3(0.0, 0.0, -0.01))
	return root


## A shoulder cap for the side `out` (-1 left, 1 right), curved over the top
## of the arm from the collarbone to the outside of the shoulder; heavy adds
## a second lame under it.
static func build_pad(weight: String, color: Color, out: float) -> Node3D:
	var root := Node3D.new()
	root.name = "PadModel"
	var heavy := weight == "heavy"
	var r := 0.07 if heavy else 0.062
	var length := 0.12 if heavy else 0.1
	var lames := 2 if heavy else 1
	for i in lames:
		# A band round the arm's front-to-back line: built round Y, then laid on Z.
		var cap := _plate(root, "Pad" if i == 0 else "Pad%d" % i,
				_shell(r + i * 0.008, r + i * 0.008, -0.35, 1.45 - i * 0.3, -length * 0.5, length * 0.5,
				FRAME_THICK, 0.006), _solid(color if i == 0 else color.darkened(0.25), 0.0),
				Vector3(0.0, -i * 0.03, 0.0))
		# Round Y the shell runs from -Z; turned so it runs from up, over the
		# top and down the outside of this shoulder.
		cap.basis = Basis(Vector3.RIGHT, PI * 0.5)
		if out < 0.0:
			cap.basis = Basis(Vector3.UP, PI) * cap.basis
	return root


## How thick a plate is, and how far off the body it rides.
const FRAME_THICK := 0.011
const FRAME_GAP := 0.012


static func _plate(root: Node3D, piece_name: String, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = piece_name
	part.mesh = mesh
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	part.material_override = mat
	part.position = at
	root.add_child(part)
	return part


## A curved plate: a band of an upright elliptical cylinder of radii `rx`
## and `rz`, from angle `from` to `to` (0 at -Z, growing toward +X) and
## height `low` to `high`, `thick` thick and thinning to a bevel at its
## edges. `bulge` swells its middle out and `flare` widens its top (a
## negative flare narrows it, for a collar).
static func _shell(rx: float, rz: float, from: float, to: float, low: float, high: float, thick: float,
		bulge := 0.0, flare := 0.0) -> ArrayMesh:
	var cols := maxi(4, ceili((to - from) / 0.12))
	var rows := 5
	# The bevel runs in this far from each edge, less on a narrow band.
	var bevel := minf(0.022, 0.3 * minf(high - low, (to - from) * rx))
	var outer := []
	var inner := []
	var normals := []
	for j in rows + 1:
		var v := float(j) / rows
		var row_out := []
		var row_in := []
		var row_n := []
		for i in cols + 1:
			var u := float(i) / cols
			var a := lerpf(from, to, u)
			var grow := 1.0 + flare * (v - 0.5) + bulge * sin(PI * v) * sin(PI * u) / maxf(rx, 0.01)
			var at := Vector3(rx * grow * sin(a), lerpf(low, high, v), -rz * grow * cos(a))
			var n := Vector3(sin(a) / rx, 0.0, -cos(a) / rz).normalized()
			var edge := minf(minf(u, 1.0 - u) * (to - from) * rx, minf(v, 1.0 - v) * (high - low))
			var t := thick * lerpf(0.3, 1.0, smoothstep(0.0, bevel, edge))
			row_in.append(at)
			row_out.append(at + n * t)
			row_n.append(n)
		outer.append(row_out)
		inner.append(row_in)
		normals.append(row_n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows:
		for i in cols:
			_shell_quad(st, [outer[j][i], outer[j][i + 1], outer[j + 1][i + 1], outer[j + 1][i]],
					[normals[j][i], normals[j][i + 1], normals[j + 1][i + 1], normals[j + 1][i]], 1.0)
			_shell_quad(st, [inner[j][i], inner[j][i + 1], inner[j + 1][i + 1], inner[j + 1][i]],
					[normals[j][i], normals[j][i + 1], normals[j + 1][i + 1], normals[j + 1][i]], -1.0)
	# The rims: bottom, top, then the two sides.
	for i in cols:
		for j: int in [0, rows]:
			var down: Vector3 = Vector3.DOWN if j == 0 else Vector3.UP
			_shell_quad(st, [inner[j][i], inner[j][i + 1], outer[j][i + 1], outer[j][i]], [down, down, down, down], 1.0)
	for j in rows:
		for i: int in [0, cols]:
			var side: Vector3 = (inner[j][mini(i + 1, cols)] - inner[j][maxi(i - 1, 0)]).normalized() * (1.0 if i == cols else -1.0)
			_shell_quad(st, [inner[j][i], inner[j + 1][i], outer[j + 1][i], outer[j][i]], [side, side, side, side], 1.0)
	return st.commit()


static func _shell_quad(st: SurfaceTool, at: Array, n: Array, sign: float) -> void:
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal((n[k] as Vector3) * sign)
		st.add_vertex(at[k])


static func _solid(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.35) if energy > 0.0 else color
	mat.roughness = 0.2 if energy > 0.0 else 0.6
	mat.metallic = 0.0 if energy > 0.0 else 0.35
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color.darkened(0.2)
		mat.emission_energy_multiplier = energy
	return mat


static func _piece(root: Node3D, piece_name: String, mesh: PrimitiveMesh, mat: Material, at: Vector3,
		size: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = piece_name
	var own := mesh.duplicate() as PrimitiveMesh
	own.material = mat
	part.mesh = own
	part.position = at
	part.scale = size
	root.add_child(part)
	return part


func _update_vitals() -> void:
	var worn := actor.visor.enabled and not actor.is_dead
	if not worn:
		if _vitals:
			_vitals.visible = false
		return
	if _vitals == null or not is_instance_valid(_vitals):
		_build_vitals()
	_vitals.visible = true
	var share := clampf(actor.health.health / maxf(actor.health.max_health, 1.0), 0.0, 1.0)
	var ink := actor.visor.glass_color
	var low := share < vitals_low
	var color := Color(1.0, 0.25, 0.15) if low else ink
	var fill := _vitals.find_child("Fill", true, false) as MeshInstance3D
	fill.scale.x = maxf(0.001, share)
	fill.position.x = -vitals_width * 0.5 + vitals_width * share * 0.5
	var beat := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.009) if low else 1.0
	_glow(fill, color, 1.8 * beat)
	var light := _vitals.find_child("Light", true, false) as MeshInstance3D
	var state := helmet_light(actor.visor)
	light.visible = state != ""
	match state:
		"running":
			_glow(light, ink, 1.5 + 1.2 * sin(Time.get_ticks_msec() * 0.012))
		"ready":
			_glow(light, ink, 2.2)
		"charging":
			_glow(light, ink.darkened(0.6), 0.3)


## Under a Phase Cloak (`Artifact`) everything the actor wears or holds is
## drawn as a faint shimmer at its edges instead of solid, casting no shadow.
## It is the same body in every view, so first person sees its own arms and
## gun go too. Each piece's own material and shadow come back afterwards.
func _update_cloak() -> void:
	var on := actor.is_cloaked() and not actor.is_dead
	if not on and not _cloaked:
		return
	_cloaked = on
	for node in actor.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var dressed := geometry.has_meta("cloak_saved")
		if on and not dressed and not _own_display(geometry):
			geometry.set_meta("cloak_saved", [geometry.material_override, geometry.cast_shadow, geometry.visible])
			if geometry.material_override != null:
				# A piece that runs its own material (a gauge, a counter, a
				# glow) keeps it and is put out of sight instead.
				geometry.visible = false
			else:
				geometry.material_override = cloak_material()
				geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif not on and dressed:
			var saved: Array = geometry.get_meta("cloak_saved")
			if saved[0] == null:
				geometry.material_override = null
				geometry.cast_shadow = saved[1]
			else:
				geometry.visible = saved[2]
			geometry.remove_meta("cloak_saved")


## True for what only the player reads, held to their own wrist: the
## watch's card (`Hud.Wrist`). A cloak leaves it as it is.
func _own_display(node: Node) -> bool:
	while node != null and node != actor:
		if node.name == "Wrist":
			return true
		node = node.get_parent()
	return false


## True while the body is drawn cloaked (for checks).
func is_drawn_cloaked() -> bool:
	return _cloaked


## The shimmer a cloaked body is drawn with: nothing face on, a thin cold
## glow where its edges turn away, so a sharp eye can still spot it.
static func cloak_material() -> Material:
	if _cloak_mat == null:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;
uniform vec3 rim : source_color = vec3(0.55, 0.75, 1.0);
uniform float strength = 0.5;
void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float ripple = 0.7 + 0.3 * sin(TIME * 9.0 + FRAGCOORD.y * 0.08);
	ALBEDO = rim * edge * strength * ripple;
	ALPHA = edge * strength;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_cloak_mat = mat
	return _cloak_mat


## A weapon summoned from the watch (`Loadout.swap_weapon`) digitizes into
## the hand: its model fades in from nothing under a shimmer of light while
## `Actor.materialize_left` runs down, and one stored back fades out the same
## way as `Actor.dematerialize_left` runs down. It is the one weapon in the one hand,
## so both views and everyone around see the same thing.
func _update_materialize() -> void:
	var weapon := actor.get_active_weapon()
	# Stored back through the watch, it runs the other way: the solid model
	# breaks up into the same light and fades out of the hand.
	var storing := actor.storing_weapon()
	var fading := storing != null and storing == weapon
	var model: Node3D = weapon.visual if weapon != null and (actor.materialize_left > 0.0 or fading) \
			and weapon.visual != null and is_instance_valid(weapon.visual) else null
	if _materializing != null and (model != _materializing or not is_instance_valid(_materializing)):
		if is_instance_valid(_materializing):
			_set_materialize(_materializing, 1.0)
		_materializing = null
	if model == null:
		return
	_materializing = model
	if fading:
		_set_materialize(model, actor.dematerialize_left / maxf(actor.dematerialize_time, 0.01))
	else:
		_set_materialize(model, 1.0 - actor.materialize_left / maxf(actor.materialize_time, 0.01))


## Draws `model` as `done` (0 to 1) materialized: 1 is the plain model.
func _set_materialize(model: Node3D, done: float) -> void:
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.transparency = clampf(1.0 - done, 0.0, 1.0) * 0.9
		geometry.material_overlay = materialize_material() if done < 1.0 else null
	if _materialize_mat != null:
		_materialize_mat.set_shader_parameter("done", done)


## How far the weapon in hand has materialized, 0 to 1 (for checks).
func materialized() -> float:
	if _materializing != null and actor.storing_weapon() != null:
		return clampf(actor.dematerialize_left / maxf(actor.dematerialize_time, 0.01), 0.0, 1.0)
	if _materializing == null or actor.materialize_time <= 0.0:
		return 1.0
	return clampf(1.0 - actor.materialize_left / actor.materialize_time, 0.0, 1.0)


## The light a materializing weapon is drawn under: fine scanlines that
## thin out as it becomes solid. One material per body, since each is at
## its own point in the fade.
func materialize_material() -> Material:
	if _materialize_shader == null:
		_materialize_shader = Shader.new()
		_materialize_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled;
uniform vec3 glow : source_color = vec3(0.35, 0.95, 1.0);
uniform float done = 0.0;
void fragment() {
	float lines = 0.5 + 0.5 * sin(FRAGCOORD.y * 0.9 - TIME * 30.0);
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float left = 1.0 - done;
	ALBEDO = glow * (0.35 + lines * 0.9 + edge) * left;
	ALPHA = clamp((0.25 + lines * 0.5 + edge * 0.5) * left, 0.0, 1.0);
}
"""
	if _materialize_mat == null:
		_materialize_mat = ShaderMaterial.new()
		_materialize_mat.shader = _materialize_shader
	return _materialize_mat


## True while the right hand is on a toy vehicle (held up or mid-throw):
## the weapon is put away meanwhile and drawn again after.
func toy_up() -> bool:
	return ActionPose.of(actor).toy_busy()


## A toy vehicle off the watch (`Actor.toy_in_hand`) digitizes into the
## right hand like a summoned weapon, is held up and thrown overarm
## (`ActionPose.toy_hand_point`), and leaves the hand at the release, where
## the toy the world flies takes over. It is the one toy in the one hand,
## facing the way the actor faces, so both views and everyone around see the
## same thing.
func _update_toy(delta: float) -> void:
	var pose := ActionPose.of(actor)
	pose.advance(delta)
	var id := pose.toy_shown()
	var shown: String = _toy_prop.get_meta("display_item", "") if _toy_prop != null else ""
	if shown != id and _toy_prop != null:
		_toy_prop.queue_free()
		_toy_prop = null
	# The whoosh of the throw, once, as it leaves the hand.
	var released := pose.toy_throw_t >= pose.toy_release
	if released and not _toy_released and pose.toy_throw_t < pose.toy_throw_time:
		Sfx.play("swing", actor.hand.global_position, -4.0)
	_toy_released = released
	if id == "":
		_toy_in = 0.0
		return
	if _toy_prop == null:
		_toy_prop = VehicleScript.toy_model(id)
		_toy_prop.name = "Toy"
		actor.hand.add_child(_toy_prop)
		_toy_in = 0.0
		Sfx.play("loot", actor.hand.global_position, -10.0)
	# It digitizes in once the hand is up for it.
	if pose.toy >= 0.5 or pose.toy_throw_t >= 0.0:
		_toy_in = move_toward(_toy_in, 1.0, delta / maxf(toy_summon_time, 0.01))
	var grown := ease(_toy_in, 0.5)
	var size := Vector3.ONE * VehicleScript.TOY_SCALE * lerpf(0.4, 1.0, grown)
	# Kept in the hand's own frame, so it moves with the hand wherever the
	# hand is put this frame, turned to face the way the actor faces.
	var turn := actor.hand.global_basis.orthonormalized().inverse() * actor.global_basis.orthonormalized()
	_toy_prop.transform = Transform3D(turn * Basis.from_scale(size), turn * toy_on_palm)
	_set_toy_digitized(grown if _toy_in < 1.0 else 1.0)


## How far the toy in the hand has digitized in, 0 to 1 (for checks).
func toy_digitized() -> float:
	return _toy_in if _toy_prop != null else 0.0


## The toy in the hand, or null (for checks).
func toy_prop() -> Node3D:
	return _toy_prop


func _set_toy_digitized(done: float) -> void:
	if _toy_mat == null:
		materialize_material()
		_toy_mat = ShaderMaterial.new()
		_toy_mat.shader = _materialize_shader
	for node in _toy_prop.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.transparency = clampf(1.0 - done, 0.0, 1.0) * 0.9
		geometry.material_overlay = _toy_mat if done < 1.0 else null
	_toy_mat.set_shader_parameter("done", done)


## A raised watch (`ActorCommand.watch_up`) glows on the left wrist, so
## anyone can see who is looking at their watch: a small lit spark over the
## wrist and a soft light on the arm. Only that it is up shows, never what is
## on it. Fades in and out with the raise.
func _update_watch_glow(delta: float) -> void:
	var goal := 1.0 if actor.cmd.watch_up and not actor.is_dead else 0.0
	_watch_up = move_toward(_watch_up, goal, delta / 0.18)
	if _watch_up <= 0.0:
		if _watch_glow != null and is_instance_valid(_watch_glow):
			_watch_glow.visible = false
		return
	if _watch_glow == null or not is_instance_valid(_watch_glow):
		if _skeleton == null or _skeleton.find_bone("Wrist.L") < 0:
			return
		var attach := BoneAttachment3D.new()
		attach.name = "WatchGlow"
		attach.bone_name = "Wrist.L"
		_skeleton.add_child(attach)
		var spark := MeshInstance3D.new()
		spark.name = "Spark"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.03, 0.02)
		spark.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = WATCH_GLOW
		spark.material_override = mat
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attach.add_child(spark)
		var light := OmniLight3D.new()
		light.name = "Light"
		light.light_color = WATCH_GLOW
		light.omni_range = 0.6
		attach.add_child(light)
		# Undo the model's import scale so the glow keeps its size.
		var s := _skeleton.global_basis.get_scale()
		for child: Node3D in [spark, light]:
			child.scale = Vector3(1.0 / maxf(s.x, 0.001), 1.0 / maxf(s.y, 0.001), 1.0 / maxf(s.z, 0.001))
		_watch_glow = attach
	_watch_glow.visible = true
	var spark_node := _watch_glow.get_node("Spark") as MeshInstance3D
	# On the watch face, out of the back of the wrist (`Hud.Wrist.FACE_AXIS`).
	spark_node.position = Hud.Wrist.FACE_AXIS * 0.02 / maxf(_skeleton.global_basis.get_scale().x, 0.001)
	if actor.body_mesh:
		spark_node.layers = actor.body_mesh.layers
	(spark_node.material_override as StandardMaterial3D).albedo_color = Color(WATCH_GLOW, 0.85 * _watch_up)
	(_watch_glow.get_node("Light") as OmniLight3D).light_energy = 0.6 * _watch_up


func _build_vitals() -> void:
	var root := Node3D.new()
	var back := _quad(Vector2(vitals_width + 0.012, 0.026), Color(0.02, 0.025, 0.03), 0.0)
	root.add_child(back)
	var fill := _quad(Vector2(vitals_width, 0.016), Color.WHITE, 1.8)
	fill.name = "Fill"
	fill.position.z = 0.001
	root.add_child(fill)
	var light := _quad(Vector2(0.028, 0.028), Color.WHITE, 2.0)
	light.name = "Light"
	light.position = Vector3(vitals_width * 0.5 + 0.024, 0.0, 0.001)
	root.add_child(light)
	var bone: String = "Head" if _skeleton and _skeleton.find_bone("Head") >= 0 else _def.get("neck", "")
	_vitals = _hang(root, "Vitals", bone, vitals_offset,
			Vector3(0.0, _def.get("height", 1.8) * 0.93, 0.0) + vitals_offset)


static func _quad(size: Vector2, color: Color, energy: float) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material_override = mat
	_glow(quad, color, energy)
	return quad


static func _glow(quad: MeshInstance3D, color: Color, energy: float) -> void:
	var mat := quad.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = energy


## A small gun worn in a hip holster rather than slung (`Weapon.is_sidearm`).
static func is_sidearm(weapon: Weapon) -> bool:
	return weapon is Gun and (weapon.is_sidearm or (weapon.item_id != "" and ItemDB.has_tag(weapon.item_id, "sidearm")))


## Builds the worn copy of a holstered weapon. Purely a view: the weapon's own
## node stays on the actor's hand, hidden.
func _stow(weapon: Weapon) -> Node3D:
	var model: Node3D = look.weapon_model(weapon)
	if model == null:
		return null
	# Worn folded away, so a blade does not stick out from the hip.
	look.set_extend(model, 0.0)
	var place := stow_place(weapon)
	var pivot := Node3D.new()
	pivot.add_child(model)
	if place["centre"]:
		model.position -= look.folded_bounds(model).get_center()
	pivot.basis = place["basis"]
	var at: Vector3 = place["at"]
	if place.has("out"):
		# Clamped: its near side rests on the clamp faces.
		at += (place["out"] as Vector3) * (_near_side(model, place["upright"], place["side"]) + mount_clearance)
	var fallback: Vector3 = Vector3(0.0, _def.get("height", 1.8) * 0.7, 0.0) + at
	var root := _hang(pivot, "Stowed" + str(actor.weapons.find(weapon)), place["bone"], at, fallback)
	# Riding lifts what is slung on the back clear of the seat; a weapon
	# clamped to a rail stays in its clamps (it rides beside the seat).
	root.set_meta("slung", place["centre"] and not place.has("out"))
	_stowed_models[weapon] = model
	return root


## How far a centred, stood-up weapon reaches toward the pack (-X for a
## weapon on the right, `side` 1; +X on the left) where the
## rail's clamps hold it, so a spear head or a magazine further along does
## not hold the part in the clamps off the rail. Measured from the meshes,
## unfolded; falls back to half the folded width.
func _near_side(model: Node3D, upright: Basis, side: float) -> float:
	var stood: AABB = Transform3D(upright, Vector3.ZERO) * look.folded_bounds(model)
	var band := mount_band
	var near := -INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var xform := mesh_node.transform
		var up := mesh_node.get_parent()
		while up != null and up != model.get_parent():
			if up is Node3D:
				xform = (up as Node3D).transform * xform
			up = up.get_parent()
		xform = Transform3D(upright, Vector3.ZERO) * xform
		for i in mesh_node.mesh.get_surface_count():
			var verts: PackedVector3Array = mesh_node.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xform * v
				if absf(p.y + mount_rise) <= band:
					near = maxf(near, -side * p.x)
	if near == -INF:
		return stood.size.x * 0.5
	return near


func _on_fired(from: Vector3, to: Vector3, gun: Gun) -> void:
	_aim_left = aim_hold
	var parent := actor.get_parent()
	if parent == null:
		return
	var fallback := from + (to - from).normalized() * 0.9
	if gun.visual and gun.visual.is_inside_tree():
		fallback = gun.visual.global_transform * Vector3(0, -0.04, -0.5)
	# From the barrel as it is held in this view, along the barrel.
	var muzzle := gun.muzzle_point(fallback)
	var along := -gun.visual.global_basis.z.normalized() if gun.visual and gun.visual.is_inside_tree() \
			else (to - from).normalized()
	if not gun.quiet:
		Vfx.muzzle_flash(parent, muzzle, along)
	if from.distance_to(to) < gun.max_range - 0.5:
		Vfx.impact(parent, to, (from - to).normalized())


func _on_hit_confirmed(target: Actor, info: DamageInfo, _lethal: bool) -> void:
	if target == null or not is_instance_valid(target) or info.kind == "bullet":
		return
	var parent := actor.get_parent()
	if parent:
		var at := target.global_position + Vector3(0, 1.1, 0)
		Vfx.impact(parent, at, (actor.global_position - target.global_position).normalized(), info.blocked or info.parried)


func _on_damaged(_info: DamageInfo) -> void:
	_flash_left = 0.07
	_set_flash(0.8)


func _set_flash(amount: float) -> void:
	for mat in _materials:
		mat.set_shader_parameter("flash", amount)


## Keeps the worn flight rig in step with the actor: puts on the model of
## whatever rig is equipped, burns the nozzles while it thrusts or just after
## an air jump, and spreads the wings while gliding.
func _update_rig(delta: float) -> void:
	var id := actor.flight.item_id if actor.flight.enabled else ""
	if id != _rig_id:
		_wear_rig(id)
	if _rig_holders.is_empty():
		return
	_burst_left = maxf(0.0, _burst_left - delta)
	var burning := not actor.is_dead and (actor.flight.is_thrusting or actor.flight.is_skimming or _burst_left > 0.0)
	for flame in _flames:
		flame.visible = burning
		if burning and actor.flight.can_skim():
			_aim_flame(flame)
	if _rig_back and _rig_back.has_node("WingL"):
		var want := 1.0 if actor.flight.is_gliding and not actor.is_dead else 0.0
		var was := _spread
		_spread = move_toward(_spread, want, wing_speed * delta)
		if _spread != was or _spread > 0.0:
			RigModel.set_wing_spread(_rig_back, _spread, clampf(-_bank / max_bank, -1.0, 1.0), actor.glide_trim())


## Sets the whole model's attitude in the air, about the actor's middle.
## Gliding or boosting it lies flat along the way it flies (nose down in a
## dive, up in a climb), turned to face that way and banked into the turn.
## Hovering it leans the way it drifts. A sideways air dash barrel rolls it.
## All of it is read from velocity and the simulated actor, so remote
## players match.
## The arms and legs are posed by `_pose_glide`, last in the skeleton's order.
func _update_glide(delta: float) -> void:
	var alive := not actor.is_dead and actor.vehicle == null
	var flat := alive and (actor.flight.is_gliding or actor.flight.is_boosting)
	_glide = move_toward(_glide, 1.0 if flat else 0.0, glide_blend * delta)
	_boost = move_toward(_boost, 1.0 if alive and actor.flight.is_boosting else 0.0, glide_blend * delta)

	var local := actor.global_basis.inverse() * actor.velocity
	var level := Vector3(local.x, 0.0, local.z)
	var speed := level.length()
	var dir := level / speed if speed > 0.5 else Vector3.FORWARD
	var tilt := Vector3.ZERO
	var face := 0.0
	var bank := 0.0
	if flat:
		var path := atan2(actor.velocity.y, maxf(speed, 0.5)) if actor.velocity.length() > 1.0 else 0.0
		var lie := glide_pitch
		if not actor.flight.is_gliding:
			# A jetpack boost speeds you up into a prone, head-first pose:
			# leaning in as it sets off, flat out at full boost speed.
			var gained := clampf(speed / maxf(actor.flight.boost_speed, 1.0), 0.0, 1.0)
			lie = lerpf(boost_start_lean, PI / 2.0, smoothstep(0.0, 1.0, gained))
		if speed <= 0.5:
			dir = Vector3.FORWARD
		tilt = dir * clampf(lie - path, 0.0, PI * 0.95)
		face = Locomotion.heading(dir)
		# Bank for the turn being flown: how fast the heading is swinging.
		var heading := atan2(-actor.velocity.x, -actor.velocity.z)
		if _has_heading and speed > 2.0 and delta > 0.0:
			var rate := wrapf(heading - _last_heading, -PI, PI) / delta
			bank = clampf(atan(speed * rate / 9.8), -max_bank, max_bank)
		_last_heading = heading
		_has_heading = speed > 2.0
	else:
		_has_heading = false
		if alive and actor.flight.is_hovering:
			tilt = dir * hover_lean * clampf(speed / maxf(actor.flight.fly_speed, 0.1), 0.0, 1.0)
		elif alive and _boot_w > 0.0 and is_airborne():
			tilt = _boot_tilt() * smoothstep(0.0, 1.0, _boot_w)
		elif alive and _air > 0.0 and is_airborne():
			# A running jump leans into it, and rights itself for the landing.
			tilt = dir * leap_lean * clampf(speed / leap_lean_speed, 0.0, 1.0) * (1.0 - _air_fall)
	# The actor turns with the view, and this model is its child. While the
	# body is laid out in flight, a look round must not drag it round with
	# the camera and then let it swing back: undo the view's turn first, so
	# the attitude eases only toward the way the body really flies.
	var yaw := actor.global_rotation.y
	if _glide > 0.0 or _boost > 0.0:
		var turned := wrapf(yaw - _last_yaw, -PI, PI)
		_face -= turned
		_tilt = _tilt.rotated(Vector3.UP, -turned)
	_last_yaw = yaw
	var follow := 1.0 - exp(-attitude_follow * delta)
	_tilt = _tilt.lerp(tilt, follow)
	_face = lerp_angle(wrapf(_face, -PI, PI), face, follow)
	_bank = lerpf(_bank, bank, 1.0 - exp(-bank_follow * delta))
	# Free look in a glide: the body twists round its own length to face the
	# view, so looking behind lays it on its back (a backstroke) while the
	# wings fly on, and a sidearm aims back past the feet.
	var look_roll := 0.0
	if flat and actor.flight.is_gliding and actor.cmd.free_look:
		var off := wrapf(face, -PI, PI)
		look_roll = -signf(off) * smoothstep(look_roll_start, look_roll_full, absf(off)) * PI
	_look_roll = lerp_angle(_look_roll, look_roll, 1.0 - exp(-bank_follow * delta))
	# A sideways air dash: one full roll over the dash; then the body rights
	# itself the short way round.
	if flat and actor.air_dash_left > 0.0 and absf(actor.air_dash_side) > 0.5:
		_twist += signf(actor.air_dash_side) * TAU / maxf(actor.flight.air_dash_time, 0.05) * delta
	else:
		_twist = wrapf(_twist, -PI, PI)
		_twist = move_toward(_twist, 0.0, twist_speed * delta)

	var angle := _tilt.length()
	var tip := Basis(Vector3.UP.cross(_tilt / angle).normalized(), angle) if angle > 0.001 else Basis.IDENTITY
	# A positive bank or twist rolls to the right: right side down.
	var turn := tip * Basis(Vector3.UP, _face - _bank + _twist + _look_roll)
	_body_turn = turn
	var pivot := Vector3(0, glide_pivot, 0)
	transform = Transform3D(turn * Basis(Vector3.UP, PI), pivot - turn * pivot)
	var seated: Variant = ride_frame()
	if seated != null and locomotion != null and locomotion.ride_weight > 0.0:
		transform = transform.interpolate_with(seated, smoothstep(0.0, 1.0, locomotion.ride_weight))


## Tells the legs' riding pose what is being ridden and what the hands may do:
## the left hand always takes its grip, the right one only while nothing is
## in it (holster with Z to ride with both hands). The head turns to the aim.
func _update_ride() -> void:
	var vehicle: Node3D = actor.vehicle if not actor.is_dead else null
	locomotion.ride = vehicle
	if arm:
		# The right hand's fingers wrap the phone while it is up.
		var phone_grip := Vector2(0.0, 0.6 * smoothstep(0.0, 1.0, locomotion.phone_weight))
		arm.ride_grip = locomotion.grip_hold().max(phone_grip)
	if vehicle == null:
		return
	var free := _in_hand == null and _plan.is_empty()
	locomotion.ride_hands = Vector2(1.0, 1.0 if free else 0.0)
	# A gun in hand is held out toward the aim, where it would be on foot.
	var gun := _in_hand as Gun
	locomotion.ride_gun_wrist = null
	if gun != null and _plan.is_empty():
		var aim := Basis(Vector3.RIGHT, actor.cmd.pitch)
		locomotion.ride_gun_wrist = actor.global_transform * (Actor.HAND_REST + aim * ride_gun_wrist)
	locomotion.ride_turn = clampf(wrapf(actor.global_rotation.y - vehicle.global_rotation.y, -PI, PI), -ride_head_turn, ride_head_turn)


## Where the model goes while riding, in the actor's frame: facing along the
## vehicle rather than the aim, and tipped with the bike's lean and pitch
## about its wheels. Null on foot. The vehicle carries the actor at its
## `seat_offset`, so that is where the model's feet start from.
func ride_frame() -> Variant:
	var vehicle: Node3D = locomotion.get("_ride_on") if locomotion else null
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		return null
	var model := vehicle.get_node_or_null("Model") as Node3D
	var frame: Transform3D = model.global_transform if model else vehicle.global_transform
	var offset: Vector3 = vehicle.get("seat_offset")
	return actor.global_transform.affine_inverse() * frame * Transform3D(Basis(Vector3.UP, PI), offset)


func _setup_glide_pose(skeleton: Skeleton3D, def: Dictionary) -> void:
	var arm_bones := {"L": ["UpperArm.L", "LowerArm.L", "Wrist.L"], "R": ["UpperArm.R", "LowerArm.R", "Wrist.R"]}
	for side: String in ["L", "R"]:
		var chain: Array = def.get("off_arm" if side == "L" else "arm", arm_bones[side])
		_glide_arms.append(_bone_chain(skeleton, chain, -1.0 if side == "L" else 1.0))
	var feet: Array = def.get("feet", [])
	for i in feet.size():
		var foot := String(feet[i])
		var suffix := foot.get_slice(".", 1)
		_glide_legs.append(_bone_chain(skeleton, ["UpperLeg." + suffix, "LowerLeg." + suffix, foot], -1.0 if i == 0 else 1.0))
	_glide_neck = skeleton.find_bone(def.get("neck", ""))
	var hook := WeaponArm.Hook.new()
	hook.name = "GlidePose"
	hook.run = _pose_glide
	skeleton.add_child(hook)


## [bones..., side] for a limb, or [] if the skeleton lacks any of them.
func _bone_chain(skeleton: Skeleton3D, names: Array, side: float) -> Array:
	var out := []
	for bone_name: String in names:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			return []
		out.append(bone)
	out.append(side)
	return out


## Straightens the limbs into the flying pose, blended by how far into it
## the body is. Runs after the animation, the legs and the weapon arm.
func _pose_glide() -> void:
	if _skeleton == null:
		return
	_pose_air()
	if _glide <= 0.0:
		return
	var w := smoothstep(0.0, 1.0, _glide)

	# From the body's own frame (before the tip) to the skeleton's.
	# The skin faces the model's way, turned half round from the actor.
	var to_skeleton := _skeleton.basis.orthonormalized().inverse() * _model_basis_inverse() * Basis(Vector3.UP, PI)
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	# How far over onto the back free look has rolled the body.
	var back := smoothstep(0.35, 0.9, absf(_look_roll) / PI)
	for limb: Array in _glide_arms:
		if limb.is_empty():
			continue
		var arm_dir := glide_arm.lerp(boost_arm, smoothstep(0.0, 1.0, _boost)).lerp(backstroke_arm, back)
		var wanted := to_skeleton * Vector3(arm_dir.x * limb[3], arm_dir.y, arm_dir.z)
		# Shooting or aiming, the arms keep their hold on the weapon.
		var arm_w := w * (1.0 - smoothstep(0.0, 1.0, _flight_hold))
		_aim_bone(limb[0], limb[1], wanted, arm_w)
		_aim_bone(limb[1], limb[2], wanted, arm_w)
	for limb: Array in _glide_legs:
		if not limb.is_empty():
			var leg := glide_leg.lerp(backstroke_leg, back)
			_pose_leg(limb, to_skeleton * Vector3(leg.x * limb[3], leg.y, leg.z), right, w)
	if _glide_neck >= 0:
		var pose := _skeleton.get_bone_global_pose(_glide_neck)
		pose.basis = Basis((to_skeleton * Vector3.RIGHT).normalized(), lerpf(glide_look, backstroke_look, back) * w) * pose.basis
		_skeleton.set_bone_global_pose(_glide_neck, pose)


## Bends the legs into the air pose. The flat flying pose, applied after,
## takes over as the body lies out.
func _pose_air() -> void:
	var w := smoothstep(0.0, 1.0, _air) * (1.0 - smoothstep(0.0, 1.0, _glide))
	if w <= 0.0:
		return
	var to_skeleton := _skeleton.basis.orthonormalized().inverse() * _model_basis_inverse() * Basis(Vector3.UP, PI)
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	for i in _glide_legs.size():
		var limb: Array = _glide_legs[i]
		if limb.is_empty():
			continue
		var at := mini(i, 1) * 2
		var push := smoothstep(0.0, 1.0, _air_push)
		var thigh: Vector3 = (leap_legs[at] as Vector3).lerp(fall_legs[at], _air_fall).lerp(hang_legs[at], _air_hang) \
				.lerp(push_legs[at], push)
		var shin: Vector3 = (leap_legs[at + 1] as Vector3).lerp(fall_legs[at + 1], _air_fall).lerp(hang_legs[at + 1], _air_hang) \
				.lerp(push_legs[at + 1], push)
		var toes := lerpf(air_toes, push_toes, push)
		if _boot_w > 0.0:
			# Boots firing: the legs point the nozzles down the exhaust.
			var bw := smoothstep(0.0, 1.0, _boot_w)
			var legs := _boot_legs(i, float(limb[3]))
			thigh = thigh.lerp(legs[0], bw)
			shin = shin.lerp(legs[1], bw)
			toes = lerpf(toes, boot_toes, bw)
		_pose_leg(limb, to_skeleton * Vector3(thigh.x * limb[3], thigh.y, thigh.z), right, w,
				to_skeleton * Vector3(shin.x * limb[3], shin.y, shin.z), toes)
	var arm_w := w * smoothstep(0.0, 1.0, _boot_w) * _boot_hero * (1.0 - smoothstep(0.0, 1.0, _flight_hold))
	if arm_w > 0.001:
		# Lying out, the arms ride by the sides until there is aiming to do.
		for limb: Array in _glide_arms:
			if limb.is_empty():
				continue
			var wanted := to_skeleton * Vector3(boot_arm.x * limb[3], boot_arm.y, boot_arm.z)
			_aim_bone(limb[0], limb[1], wanted, arm_w)
			_aim_bone(limb[1], limb[2], wanted, arm_w)
	if _boot_w > 0.0 and _glide_neck >= 0:
		# Lying out, the head comes up to look where it flies.
		var pose := _skeleton.get_bone_global_pose(_glide_neck)
		var pitch := maxf(-_tilt.z, 0.0) * 0.75 * smoothstep(0.0, 1.0, _boot_w) * w
		pose.basis = Basis(right, pitch) * pose.basis
		_skeleton.set_bone_global_pose(_glide_neck, pose)


## Lays a leg along `dir`, or bends it: the thigh along `dir` and the shin
## along `shin_dir` when one is given. The human rig's foot is an IK handle
## under the root, not a child of the shin, so it is carried to the end of
## the shin by hand, turned with it and pointed by `toes` radians.
func _pose_leg(limb: Array, dir: Vector3, right: Vector3, w: float, shin_dir := Vector3.ZERO, toes := -1.0) -> void:
	if shin_dir == Vector3.ZERO:
		shin_dir = dir
	if toes < 0.0:
		toes = glide_toes
	var shin := _skeleton.get_bone_global_pose(limb[1])
	var foot := _skeleton.get_bone_global_pose(limb[2])
	var reach := foot.origin - shin.origin
	# The shin's line to the foot, held in the shin's own frame.
	var along := shin.basis.inverse() * reach
	_aim_bone(limb[0], limb[1], dir, w)
	shin = _skeleton.get_bone_global_pose(limb[1])
	var now := shin.basis * along
	if now.length_squared() < 0.000001:
		return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(now.normalized(), shin_dir.normalized()), w)
	shin.basis = Basis(turn) * shin.basis
	_skeleton.set_bone_global_pose(limb[1], shin)
	# Turn the foot as the shin turned in all, then point the toes.
	var whole := Quaternion(reach.normalized(), (Basis(turn) * now).normalized())
	foot.origin = shin.origin + Basis(turn) * now
	foot.basis = Basis(right, toes * w) * Basis(whole) * foot.basis
	_skeleton.set_bone_global_pose(limb[2], foot)


## From this skin's space to the skeleton's parent, turns only.
func _model_basis_inverse() -> Basis:
	var up := _skeleton.get_parent()
	var basis := Basis.IDENTITY
	while up != null and up != self:
		if up is Node3D:
			basis = (up as Node3D).basis.orthonormalized() * basis
		up = up.get_parent()
	return basis.inverse()


## Turns `bone` (in the skeleton's space) so its child lies along `dir`.
func _aim_bone(bone: int, child: int, dir: Vector3, weight: float) -> void:
	var pose := _skeleton.get_bone_global_pose(bone)
	var now := _skeleton.get_bone_global_pose(child).origin - pose.origin
	if now.length_squared() < 0.000001:
		return
	var turn := Quaternion(now.normalized(), dir.normalized())
	pose.basis = Basis(Quaternion.IDENTITY.slerp(turn, weight)) * pose.basis
	_skeleton.set_bone_global_pose(bone, pose)


## Reads what thruster boots are doing from the actor's velocity: how hard
## they push and which way (see `boot_drag`), and eases the body into or out
## of the thrust pose and the forward flying pose.
func _update_boot_thrust(delta: float) -> void:
	var v := actor.velocity
	_vel_lag = _vel_lag.lerp(v, 1.0 - exp(-boot_accel_rate * delta)) if delta > 0.0 else v
	var boots := actor.flight.enabled and actor.flight.can_skim()
	var burning := boots and not actor.is_dead and actor.vehicle == null and is_airborne() \
			and (actor.flight.is_skimming or actor.air_dash_left > 0.0 or _burst_left > 0.0)
	_boot_w = move_toward(_boot_w, 1.0 if burning else 0.0, air_blend * delta)
	if not boots:
		_boot_hero = 0.0
		return
	var to_local := actor.global_basis.inverse()
	var local := to_local * v
	var accel := to_local * ((v - _vel_lag) * boot_accel_rate)
	var level := Vector3(local.x, 0.0, local.z)
	var push := accel + level * boot_drag + Vector3(0.0, 9.8, 0.0)
	# Boots only push: never down, however fast a sink is caught.
	push.y = maxf(push.y, 2.0)
	var follow := 1.0 - exp(-attitude_follow * delta)
	_exhaust = _exhaust.lerp(-push.normalized(), follow).normalized()
	_thrust_g = lerpf(_thrust_g, push.length() / 9.8, follow)
	# Forward flying: how much of the speed is ahead, at cruise speed or more.
	var ahead := -local.z
	var cruise := maxf(actor.flight.skim_speed, 1.0)
	var lined := clampf(ahead / maxf(level.length(), 0.1), 0.0, 1.0)
	var hero := smoothstep(0.45, 0.9, ahead / cruise) * lined * lined if burning else 0.0
	_boot_hero = lerpf(_boot_hero, hero, follow)


## The body's lean while boots fire, as `_update_glide` takes it: into the
## push, and lying out ahead in forward flight.
func _boot_tilt() -> Vector3:
	var push := Vector3(-_exhaust.x, 0.0, -_exhaust.z)
	var lean := Vector3.ZERO
	if push.length() > 0.001:
		lean = push.normalized() * minf(atan2(push.length(), -_exhaust.y), boot_max_lean)
	var ahead := -(actor.global_basis.inverse() * actor.velocity).z
	var cruise := maxf(actor.flight.skim_speed, 1.0)
	var pitch := lerpf(boot_hero_pitch, boot_hero_max,
			clampf((ahead - cruise) / maxf(actor.flight.air_dash_speed, 1.0), 0.0, 1.0))
	pitch *= 1.0 - boot_aim_ease * smoothstep(0.0, 1.0, _flight_hold)
	return lean.lerp(Vector3.FORWARD * pitch, _boot_hero)


## Thigh and shin directions for leg `i` while boots fire, in the body's own
## frame before the tip and mirrored for `side` (as `_pose_air` reads them):
## both legs follow the exhaust, a little apart; the second leg's knee bends,
## more in forward flight.
func _boot_legs(i: int, side: float) -> Array:
	var along := _body_turn.inverse() * _exhaust
	along = Vector3(along.x * side, along.y, along.z)
	var thigh := (along + Vector3(0.06, 0.0, 0.0)).normalized()
	if i == 0:
		return [thigh, thigh]
	var bend := 0.2 + boot_knee * _boot_hero
	return [Basis(Vector3.RIGHT, bend * 0.3) * thigh, Basis(Vector3.RIGHT, -bend * 0.7) * thigh]


## Swivels a boot flame to blow along the exhaust, as far as its nozzle can
## turn (`boot_gimbal`), and stretches it with the thrust.
func _aim_flame(flame: Node3D) -> void:
	var nozzle := flame.get_parent() as Node3D
	if nozzle == null:
		return
	var want := (nozzle.global_basis.inverse() * (actor.global_basis * _exhaust)).normalized()
	var angle := Vector3.DOWN.angle_to(want)
	var dir := Vector3.DOWN.slerp(want, minf(1.0, boot_gimbal / angle)) if angle > 0.001 else Vector3.DOWN
	var stretch := clampf(_thrust_g, boot_flame_min, boot_flame_max)
	var swivel := Basis(Quaternion(Vector3.DOWN, dir.normalized())) if angle > 0.001 else Basis.IDENTITY
	flame.basis = swivel * Basis.from_scale(Vector3(sqrt(stretch), stretch, sqrt(stretch)))


func _on_burst() -> void:
	_burst_left = burst_burn


## Swaps the rig model for the one `id` needs ("" takes it off).
func _wear_rig(id: String) -> void:
	_rig_id = id
	for holder in _rig_holders:
		holder.queue_free()
	_rig_holders.clear()
	_flames.clear()
	_rig_back = null
	_spread = 0.0
	if id == "":
		return
	var back := RigModel.build_back(id)
	if back:
		_rig_back = back
		_wear_part(back, _def.get("back_bone", ""), Vector3(0, back_drop, back_gap), Vector3(0, _def.get("height", 1.8) * 0.74, back_gap + 0.06))
	var feet: Array = _def.get("feet", [])
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var boot := RigModel.build_boot(id, side)
		if boot == null:
			continue
		var bone: String = feet[i] if feet.size() == 2 else ""
		_wear_part(boot, bone, boot_offset, Vector3(side * 0.12, 0.1, 0.0))
	var lit := false
	for holder in _rig_holders:
		for nozzle in RigModel.nozzles(holder):
			var size: Vector2 = nozzle.get_meta("flame", Vector2(0.05, 0.5))
			var flame := Vfx.nozzle_flame(size.x, size.y, not lit)
			lit = true
			flame.visible = false
			nozzle.add_child(flame)
			_flames.append(flame)


## Hangs a rig part on a bone so it moves with the body (see `_hang`).
func _wear_part(part: Node3D, bone_name: String, offset: Vector3, fallback: Vector3) -> void:
	look._weather_model(part, 0.5, 0.6)
	_rig_holders.append(_hang(part, "Rig" + part.name, bone_name, offset, fallback))


## Hangs a part on a bone so it moves with the body, and returns the node to
## free to take it off. Parts are built in meters for a wearer facing the
## actor's way; this undoes the model's scale and turn so they come out that
## way. `offset` is from the bone, in the actor's frame. Skins without the
## bone get the part at `fallback` (actor frame), fixed to the body.
func _hang(part: Node3D, holder_name: String, bone_name: String, offset: Vector3, fallback: Vector3) -> Node3D:
	var bone := _skeleton.find_bone(bone_name) if _skeleton and bone_name != "" else -1
	var holder := Node3D.new()
	holder.name = holder_name
	holder.add_child(part)
	var to_actor := actor.global_transform.affine_inverse()
	if bone < 0:
		add_child(holder)
		holder.transform = global_transform.affine_inverse() * actor.global_transform * Transform3D(Basis.IDENTITY, fallback)
		return holder
	var attach := BoneAttachment3D.new()
	attach.name = holder_name
	attach.bone_name = bone_name
	_skeleton.add_child(attach)
	attach.add_child(holder)
	holder.name = "Part"
	# Where the bone sits at rest, as the actor sees it, and where the part goes.
	var bone_at := to_actor * _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)
	var want := Transform3D(Basis.IDENTITY, bone_at.origin + offset)
	holder.transform = bone_at.affine_inverse() * want
	# What moving the part up the body (actor frame) is, in the holder's parent.
	holder.set_meta("rest", holder.transform)
	holder.set_meta("up", bone_at.basis.inverse() * Vector3.UP)
	return attach