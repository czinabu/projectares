extends Node3D
## The model an actor wears. Added by `Look` as a child of the Actor; the
## Actor itself never knows about it. It reads the actor's state each frame
## and plays the matching animation, swaps greybox weapon parts for models,
## and plays the effects for shots and hits.

const MirrorScript := preload("res://core/visual/mirror.gd")
const Vfx := preload("res://core/visual/vfx.gd")
const WeaponArm := preload("res://core/visual/weapon_arm.gd")
const RigModel := preload("res://core/visual/rig_model.gd")
const HelmetModel := preload("res://core/visual/helmet_model.gd")
const ArmorModel := preload("res://core/visual/armor_model.gd")
const Human := preload("res://core/visual/human.gd")
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
## How long a soldier's gun must have been down before raising it barks.
var bark_calm := 4.0
var _calm_for := 0.0
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
## How long it stays raised after aiming is let go without a shot: a tap of
## aim is not a fight, so the gun goes back to its carry almost at once
## rather than being held up at the hip, half raised, for `aim_hold`
## (Caleb's in-between wobble).
var aim_release_hold := 0.25
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
## Gliding down onto the ground, the body flares for the landing: from
## `flare_height` meters over what is below it pitches up toward
## `flare_pitch` (radians from upright), the legs swing down under it and
## the wings tip up to brake, all the way at `flare_full` meters. It eases
## in and out at `flare_rate` a second. View only, read from the actor.
var flare_height := 3.5
var flare_full := 0.8
var flare_pitch := 0.45
var flare_rate := 5.0
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
## A helmet taken off (`Actor.helmet_stow`) is clipped to the belt at the
## back of the left hip, behind a sheathed blade (`hip_offset`), its face
## turned back and a little out and its crown tipped out, so its narrow
## side is against the hip and it stands clear of the body: its middle this
## far from the "Hips" bone (actor frame), turned by `helmet_clip_turn`
## (yaw, then the tip out, radians). Both hands lift it off the head, the
## weapon hand letting go on the way down (`ActionPose.helmet_both`), and
## the off hand takes it there and back (`ActionPose.helmet_hand`), holding it by its side (`helmet_grip_out`
## out from its middle, `helmet_grip_drop` under it) and lifting it ahead
## and out round the body on the way (`helmet_swing_ahead`, `helmet_swing`).
## One model in every view, as on the head.
var helmet_clip := Vector3(-0.26, 0.06, 0.19)
var helmet_clip_turn := Vector2(PI * 0.85, 0.25)
var helmet_grip_out := 0.13
## How far below the helmet's middle the wrist goes, so the fingers close
## round its side rather than reaching over it.
var helmet_grip_drop := 0.09
var helmet_swing := 0.08
var helmet_swing_ahead := 0.4
## Where a hand hangs before it reaches for the helmet (actor frame, the
## off hand's side; scaled with the body's height), and how far ahead the
## reach bows out on its way up.
var helmet_hand_rest := Vector3(0.21, 1.06, -0.06)
var helmet_reach_ahead := 0.18
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
## A body the camera does not frame, past the first range, is posed this
## many frames apart (inside it, where its shadow may well be in view, it
## keeps the first step, so a body at the frame's edge never flips its
## animation between running by itself and by hand). It is posed at once
## when it comes into frame. View only.
var offscreen_step := 8

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
## Breath in the cold (`_update_breath`): a puff of fog from the mouth every
## `breath_every` seconds, quicker shivering or out of breath; only within
## `breath_range` metres of the camera.
var breath_every := 2.8
var breath_hard_every := 1.3
var breath_range := 35.0
var _breath: CPUParticles3D
var _breath_in := 0.0
## The head bone where the last skeleton update left it, all poses applied
## (`_note_head`), in the skeleton's frame.
var _posed_head := Vector3.INF
## The eyes, from the head bone (`eye_point`): metres up, and ahead along the
## view.
var eye_up := 0.08
var eye_ahead := 0.12
## The eyes (where first person looks from, and what an aimed gun is
## brought up to) are steadied on the move: the stride's bob of the head is
## smoothed away over `aim_steady_time` seconds, as a person's eyes stay level
## while they run. Fully while aimed (`ActionPose.ads`), so the gun holds still
## and the body bobs under it, and `eye_steady` of it otherwise, so a run
## still reads in the view without throwing it about (playtest feedback: the
## head bobbed several centimetres a stride).
var aim_steady_time := 0.3
var eye_steady := 0.9
## The most the steadied eyes may trail the head (metres): enough to take
## out a stride's bob, never so much that a big move of the head (a hard
## landing's squat, a dive pulled out of, a flight pose) leaves the eyes
## behind inside the neck, the collar or the chest (Caleb's first-person
## clipping: the camera saw the inside of the armor's gorget).
var eye_steady_reach := 0.05
var _steady_head := Vector3.INF
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
## The helmet: `_helmet` is what holds it on the head, `_helmet_clip` on the
## hip, `_helmet_carry` in the hand between, and `_helmet_model` the one
## model, moved between them (`_place_helmet`).
var _helmet: Node3D
var _helmet_clip: Node3D
var _helmet_carry: Node3D
var _helmet_model: Node3D
var _helmet_at := ""
## The body's sun shadow, drawn in one piece (`_update_shadow_body`), and
## what it was made from.
var _shadow_body: MeshInstance3D
var _shadow_parts := 0
var _frame_parts: Array[Node3D] = []
## The frame `_frame_parts` were built for; "" for none.
var _frame_id := ""
## The clothes the undersuit replaced, by slot, to give back (`_wear_undersuit`).
var _street := {}
## The person this body is dressed as (empty for a skin that is not a person).
var _appearance := {}
## The helmet `_helmet` was built for; "" while bare-headed.
var _helmet_id := ""
## A walker's tracking beam (`_update_beam`) and how long it has held its aim.
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _beam_held := 0.0
var _flames: Array[Node3D] = []
var _burst_left := 0.0
var _spread := 0.0
## 0 standing, 1 flying flat.
var _glide := 0.0
## Wings: how far the body has flared out of the glide for a landing, 0 to 1
## (see `flare_height`).
var _flare := 0.0
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
## Out of the camera's frame when last posed (`detail_step`).
var _offscreen := false
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
	_appearance = built.get("chosen", {})
	add_child(model)
	# Pack models face +Z. Actors face -Z.
	rotation.y = PI

	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player:
		for key: String in def.get("anims", {}):
			var found := _find_animation(def["anims"][key])
			if found != "":
				_anims[key] = found
				if key not in ["death", "attack", "roll", "kick"]:
					_player.get_animation(found).loop_mode = Animation.LOOP_LINEAR
		_play("idle")
		_player.advance(0.0)
	look.stand_model(self, model, def["height"])
	_def = def
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton = skeleton
	if def.get("chassis", "") == "walker":
		_build_walker()
	if def.get("creature", "") != "":
		_build_creature(str(def["creature"]))
	if def.get("suit", false):
		_build_exo_suit()
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
		skeleton.skeleton_updated.connect(_note_head)

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
	_mark_storm()


## A body is several skinned parts (head, body, legs, feet), each of a few
## materials, and every part's every surface used to cost a draw in every
## sun shadow split. The shadow is drawn instead by one shadow-only copy
## of the parts showing, merged into a single surface on the same skeleton
## and bones, so it has exactly the body's shape and pose; the parts
## themselves cast none. Rebuilt whenever a part comes or goes (a helmet
## hides the head). A part that is not skinned, or is drawn on another
## layer, keeps its own shadow. View only.
func _update_shadow_body() -> void:
	if _skeleton == null:
		return
	var parts: Array[MeshInstance3D] = []
	var key := 17
	for node in _skeleton.get_children():
		var part := node as MeshInstance3D
		if part == null or part == _shadow_body or part.skin == null or part.mesh == null:
			continue
		if part.has_meta("shadow_merged") or (part.visible and part.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON):
			key = hash([key, part.get_instance_id(), part.visible, part.mesh.get_rid().get_id()])
			if part.visible:
				parts.append(part)
	if key == _shadow_parts and (_shadow_body == null or is_instance_valid(_shadow_body)):
		return
	_shadow_parts = key
	if _shadow_body != null and is_instance_valid(_shadow_body):
		_shadow_body.queue_free()
	_shadow_body = null
	var shaped: Array = look.shadow_body(parts) if not parts.is_empty() else []
	for part in parts:
		if part.has_meta("shadow_merged") and (shaped.is_empty() or not (shaped[2] as Array).has(part)):
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			part.remove_meta("shadow_merged")
	if shaped.is_empty():
		return
	var body := MeshInstance3D.new()
	body.name = "ShadowBody"
	body.mesh = shaped[0]
	body.skin = shaped[1]
	body.transform = (shaped[2][0] as MeshInstance3D).transform
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_skeleton.add_child(body)
	body.skeleton = body.get_path_to(_skeleton)
	_shadow_body = body
	for part: MeshInstance3D in shaped[2]:
		part.set_meta("shadow_merged", true)
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The body's one-piece shadow (for checks), or null.
func shadow_body() -> MeshInstance3D:
	return _shadow_body if _shadow_body != null and is_instance_valid(_shadow_body) else null


## Faction rim and a lighter fog on this body, its gear and its weapons.
func _mark_storm() -> void:
	if actor == null or look == null:
		return
	look.mark_storm_readable(actor, look.storm_accent(actor.body_color))


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
	_steady_eyes(delta)
	if _def.get("beam", false):
		_update_beam(delta)
		_aim_cannon()
	_detail_delta += delta
	_detail_wait += 1
	var arrived := _offscreen and _comes_into_frame()
	if _detail_wait < _detail_every and not arrived:
		# The actor puts its hand back every tick; keep the weapon on the
		# model's hand as it was last posed. The bones read back here are
		# the clip's, not where the arm reached (an aimed gun, a look over),
		# so the hand goes where it was last shown, carried with the actor.
		if arm != null and _skeleton != null:
			arm.hold_shown()
		return
	var step := _detail_delta
	_detail_delta = 0.0
	_detail_wait = 0
	_set_detail(detail_step())
	if arrived and _detail_every > 1:
		# Bodies a turn of the view brings in all come in on one frame;
		# spread their next poses out again, as `_set_detail` does.
		_detail_wait = int(get_instance_id() % _detail_every)
	_update(step)
	if _detail_every > 1:
		if _player:
			_player.advance(step)
		if _skeleton:
			_skeleton.advance(step)
	if arm != null:
		arm.step(step)


## How many frames apart this body is posed, from how far it is from the
## camera, how far the camera is zoomed in and whether it frames the body at
## all. Every frame without a camera.
func detail_step() -> int:
	_offscreen = false
	if not is_inside_tree():
		return 1
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return 1
	var seen := camera.global_position.distance_to(global_position) \
			* tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(detail_fov) * 0.5)
	if not framed_by(camera):
		_offscreen = true
		return detail_steps[0] if seen < detail_ranges[0] else offscreen_step
	for i in detail_ranges.size():
		if seen < detail_ranges[i]:
			return detail_steps[mini(i, detail_steps.size() - 1)]
	return detail_steps[-1]


## Whether any of the body is inside `camera`'s view: a ball round it as
## tall as it stands, with room for what it holds or wears.
func framed_by(camera: Camera3D) -> bool:
	var height := actor.body_height() if actor != null and is_instance_valid(actor) else 1.8
	var centre := global_position + Vector3.UP * height * 0.5
	var radius := height * 0.5 + 1.0
	for plane in camera.get_frustum():
		if plane.distance_to(centre) > radius:
			return false
	return true


## A body posed less often for being out of frame, now in it: posed at once,
## so a turn of the view never finds it standing still.
func _comes_into_frame() -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera != null and framed_by(camera)


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


## Weapons, a helmet and armor plates cast shadows only on a body posed
## every frame (close by): further out their shadow is a few pixels inside
## the body's own, but each costs a draw in every shadow split. Only what
## cast a shadow before is switched back on.
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
	for held: Node3D in [_helmet, _helmet_clip, _helmet_carry]:
		if held != null and is_instance_valid(held):
			holders.append(held)
	for part: Variant in _frame_parts:
		if part != null and is_instance_valid(part):
			holders.append(part)
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
	_update_shadow_body()
	_update_frame()
	_update_vitals()
	_update_phone()
	_update_watch_glow(delta)
	_update_cloak()
	_update_breath(delta)
	_update_materialize()
	_update_weapon_hum()
	_update_toy(delta)
	_update_bark(delta)
	_aim_left = maxf(_aim_left - delta, 0.0)
	var weapon := actor.get_active_weapon()
	if phone_up() or toy_up():
		# Hands on the phone or a toy: stand as if empty-handed.
		weapon = null
	var melee := weapon as MeleeWeapon
	if weapon is Gun:
		_hold_up(actor.cmd.primary, actor.cmd.secondary)
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
	if actor.dodge_left > 0.0 and actor.dodge_shown == "roll" and _anims.has("roll"):
		# The evade with no rig: a roll along the ground, the clip timed to it.
		if _current != "roll":
			var length := _player.get_animation(_anims["roll"]).length
			_play("roll", length / maxf(actor.roll_time, 0.05))
			_player.seek(0.0, true)
		return
	if melee and melee.is_kicking() and _current != "kick" and _anims.has("kick"):
		# The kick is the body's: the clip has the legs, timed to land with it.
		var kick_time := melee.kick_windup + melee.kick_recover
		_attack_left = kick_time
		_current = ""
		_play("kick", _player.get_animation(_anims["kick"]).length / maxf(kick_time, 0.05))
		_player.seek(0.0, true)
	if melee and melee.is_winding_up() and not melee.is_kicking() and _attack_left <= 0.0:
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
## its carry, the low ready at a jog (and crouched, even standing still,
## so the gun never hangs between the knees) and the sprint carry at a sprint, and
## bobs with the stride. View only, from velocity, so remote players match.
func _update_carry(weapon: Weapon, gait: Dictionary, airborne: bool) -> void:
	var pose := ActionPose.of(actor)
	var gun := weapon as Gun
	var flat := Vector3(locomotion.velocity.x, 0.0, locomotion.velocity.z)
	var moving: bool = flat.length() > locomotion.move_threshold
	var on_foot := actor.vehicle == null and _glide <= 0.0 and not actor.is_dead and not phone_up()
	pose.carry_wanted = gun != null and gun.visual != null and on_foot and not in_fight(gun) \
			and (actor.is_sliding() or (actor.crouched and not airborne) or (moving and (airborne or not gait.is_empty())))
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


## Emitted each time the skeleton is posed, with how far (world) the eyes
## (`eye_point`, steadied) moved with the head since it was last posed. The first-person camera was placed from the
## head as last posed, before this frame's pose, so it follows by as much
## (`PlayerController._on_head_posed`): a quick move of the head (a landing's
## squat and spring) otherwise left the eyes a frame behind, in the neck.
signal head_posed(by: Vector3)


## Keeps the head bone as posed, which is only final inside the skeleton's
## update (see `eye_point`).
func _note_head() -> void:
	if _head_bone == -2:
		_head_bone = _skeleton.find_bone("Head") if _skeleton else -1
	if _head_bone >= 0:
		var before := _posed_head
		_posed_head = _skeleton.get_bone_global_pose(_head_bone).origin
		if before.is_finite():
			# The eyes as `eye_point` places them, steadied, before and after.
			var moved := _posed_head - before
			if _steady_head.is_finite():
				moved += _steady_offset(_posed_head) - _steady_offset(before)
			head_posed.emit(_skeleton.global_basis * moved)


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
	var local := _head_local()
	if _steady_head.is_finite():
		local += _steady_offset(local)
	var head: Vector3 = _skeleton.global_transform * local
	return head + Vector3.UP * eye_up + look * Vector3(0.0, 0.0, -eye_ahead)


## How far, in the world, the eyes are moved off the head as it is posed
## now by their steadying (`eye_steady`): what takes the stride's bob out
## of the view. `WeaponArm.carry_frame` moves a carried gun by it too, from
## inside the skeleton's update, so the arms hold the gun steady in front
## of the steadied eyes.
func eye_steadying() -> Vector3:
	if _skeleton == null or _head_bone < 0 or not _steady_head.is_finite():
		return Vector3.ZERO
	var head := _skeleton.get_bone_global_pose(_head_bone).origin
	return _skeleton.global_basis * _steady_offset(head)


## How far the steadied eyes stand off `head` (skeleton space): the share of
## the lag the view takes (`eye_steady`, all of it while aimed), never more
## than `eye_steady_reach`, so the eyes stay in the drawn head.
func _steady_offset(head: Vector3) -> Vector3:
	var steady := lerpf(eye_steady, 1.0, ActionPose.of(actor).ads)
	return ((_steady_head - head) * steady).limit_length(eye_steady_reach)


## Follows the head (`_head_local`) with a lag of `aim_steady_time`, which
## smooths the stride's bob out of it while keeping crouches and the like.
func _steady_eyes(delta: float) -> void:
	if _skeleton == null or _head_bone < 0:
		return
	# The head as it was last shown (`_note_head`): with the shoulders' aim
	# stance and every other turn in. Read outside the skeleton's update the
	# bone is only the clip's, and the arm (which reaches inside it) and the
	# camera would follow two different heads.
	var local := _head_local()
	if not _steady_head.is_finite() or _steady_head.distance_to(local) > 0.5:
		# First frame, or a jump (a teleport, getting on a bike): no lag.
		_steady_head = local
		return
	_steady_head = _steady_head.lerp(local, 1.0 - exp(-delta / maxf(aim_steady_time, 0.01)))


## The head, in the skeleton's space, as the body is posed: as it was last
## drawn (`_note_head`). Outside the skeleton's update the bone is only the
## clip's, and much of what moves the head happens only in the posed
## skeleton (riding, crouching, sliding, a landing's squat, the air and
## flight poses, the head on the aim), so eyes on the clip's head stood in
## the body's neck or collar whenever those moved it.
func _head_local() -> Vector3:
	if _posed_head.is_finite():
		return _posed_head
	return _skeleton.get_bone_global_pose(_head_bone).origin


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


## Sets what the phone shows on its face: your own phone's screen, or null
## for lit glass.
func set_phone_screen(screen: Material) -> void:
	phone_screen = screen
	_dress_phone_screen()


func _dress_phone_screen() -> void:
	var face := Handheld.face_of(_phone_prop)
	if face != null:
		face.set_surface_override_material(0, phone_screen if phone_screen != null else Handheld.glass_material())


## True once the actor has been off the ground long enough to show it.
## Read from the actor's own timer, which a client keeps for remote players
## too (it simulates them from their commands).
func is_airborne() -> bool:
	return not actor.is_dead and actor.vehicle == null and actor.airborne_time > air_grace


## A touchdown: starts the landing squat. Called for remote players too,
## whose landing this game simulates from their commands.
## A strike from this body met a guard: both blades are drawn meeting at
## one point between the two (`ActionPose.bind`), chest high and out on the
## side the swing comes from, and the spark is struck there. View only.
func _on_blade_contact(target: Actor, outcome: String, _at: Vector3, blade: MeleeWeapon) -> void:
	if outcome == "hit" or target == null or not is_instance_valid(target) or not is_instance_valid(actor):
		return
	var at := bind_point(actor, target, blade.attack_dir)
	ActionPose.of(actor).bind(at)
	ActionPose.of(target).bind(at)
	if actor.is_inside_tree():
		Fx.burst(actor.get_parent(), at, 0.1 if outcome == "block" else 0.16,
				Color(1.0, 0.85, 0.4) if outcome == "parry" else Color(0.55, 0.75, 1.0))


## Where two fighters' blades meet for a strike from `dir`: half way between
## them, chest high, out to the side the swing comes from (higher for one
## over the top), so every guarded strike meets in the same place.
static func bind_point(attacker: Actor, defender: Actor, dir: int) -> Vector3:
	var a := attacker.global_position
	var b := defender.global_position
	var across := b - a
	across.y = 0.0
	var right := across.normalized().cross(Vector3.UP) if across.length() > 0.01 else attacker.global_basis.x
	var height := minf(attacker.body_height(), defender.body_height()) * 0.72
	var side := -MeleeWeapon._side(dir) * 0.22
	var lift := 0.22 if dir == MeleeWeapon.Dir.OVERHEAD else 0.0
	return (a + b) * 0.5 + right * side + Vector3(0.0, height + lift, 0.0)


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
	_hold_up(actor.cmd.primary, actor.cmd.secondary)
	if _aim_left > 0.0 and _anims.has("aim_gun"):
		return "aim_gun"
	return "idle_gun" if _anims.has("idle_gun") else "idle"


## Keeps a gun raised: `aim_hold` from the trigger, only `aim_release_hold`
## past letting go of aim.
func _hold_up(trigger: bool, aiming: bool) -> void:
	if trigger:
		_aim_left = aim_hold
	elif aiming:
		_aim_left = maxf(_aim_left, aim_release_hold)


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
		var blade := weapon as MeleeWeapon
		if blade and not _wired.has(blade):
			_wired[blade] = true
			blade.contact.connect(_on_blade_contact.bind(blade))
		if weapon.visual.has_meta("dressed"):
			continue
		weapon.visual.set_meta("dressed", true)
		# A beast's weapon is its own body: nothing is shown in its "hand".
		if _def.get("bare", false):
			for child in weapon.visual.get_children():
				if child is Node3D:
					child.visible = false
			continue
		var model: Node3D = look.weapon_model(weapon)
		if model:
			for child in weapon.visual.get_children():
				if child is MeshInstance3D:
					child.visible = false
			weapon.visual.add_child(model)
			look.mount_attachments(weapon.visual)
		elif weapon is MeleeWeapon:
			look.restyle_melee(weapon.visual)
	_mark_storm()
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
			_mark_storm()
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
		# The draw is heard as the hand takes it (a summon has its own sound).
		if active != null and actor.materialize_left <= 0.0:
			Sfx.play("draw_gun" if active is Gun else "draw_blade", actor.global_position + Vector3.UP * 1.2,
					-8.0 if actor.is_player else -12.0, 18.0)
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
## the head under it. Bare-headed, the head shows again, and so it does with
## the helmet taken off and clipped to the hip (`_place_helmet`).
func _update_helmet() -> void:
	var id := actor.visor.item_id if actor.visor.enabled else ""
	# A skin that comes with its own helmet (an exo trooper's) wears it when
	# no helmet is worn: lit in the body's colour, the side it fights for.
	var own: String = _def.get("helmet", "") if id == "" else ""
	if own != "":
		id = "skin:" + own
	if id == _helmet_id and (id == "" or is_instance_valid(_helmet)):
		_place_helmet(own == "")
		return
	_helmet_id = id
	for held: Node3D in [_helmet, _helmet_clip, _helmet_carry]:
		if held != null and is_instance_valid(held):
			held.queue_free()
	_helmet = null
	_helmet_clip = null
	_helmet_carry = null
	_helmet_model = null
	_helmet_at = ""
	_show_head(id == "")
	if id == "":
		return
	var bone: String = "Head" if _skeleton and _skeleton.find_bone("Head") >= 0 else _def.get("neck", "")
	var mode := actor.visor.mode if own == "" else own
	var glass := actor.visor.glass_color if own == "" else actor.body_color.lightened(0.2)
	var tier := actor.visor.tier if own == "" else 1
	_helmet = _hang(build_helmet(mode, glass, helmet_size, helmet_shell_color, tier),
			"Helmet", bone, helmet_offset, Vector3(0.0, _def.get("height", 1.8) * 0.93, 0.0) + helmet_offset, true)
	_helmet_model = _helmet.find_child("HelmetModel", true, false) as Node3D
	if _helmet_model == null:
		_helmet_model = _helmet.get_child(0).get_child(0) as Node3D if _helmet is BoneAttachment3D \
				else _helmet.get_child(0) as Node3D
	_helmet_at = "head"
	if own == "":
		# Somewhere to clip it and something to carry it in, made with it.
		var clip := Node3D.new()
		clip.name = "Clip"
		_helmet_clip = _hang(clip, "HelmetClip", _def.get("hip_bone", ""), helmet_clip,
				Vector3(0.0, _def.get("height", 1.8) * 0.5, 0.0) + helmet_clip)
		var holder := _held_part(_helmet_clip)
		holder.transform = holder.transform * Transform3D(Basis(Vector3.UP, helmet_clip_turn.x)
				* Basis(Vector3.BACK, -helmet_clip_turn.y), Vector3.ZERO)
		_helmet_carry = Node3D.new()
		_helmet_carry.name = "HelmetCarry"
		add_child(_helmet_carry)
		_helmet_carry.top_level = true
		_place_helmet(true)
	if _detail_every > 1:
		_gear_shadows(false)


## Shows the head's own meshes (the face, the hair), or hides them under a
## helmet.
func _show_head(on: bool) -> void:
	if _skeleton == null:
		return
	for node in _skeleton.get_children():
		if node is MeshInstance3D and node.get_meta("slot", "") == "head":
			(node as MeshInstance3D).visible = on


## Heads in the packs that are headgear, not a face (a helmet and visor, a
## void suit's hood): with the worn helmet taken off, a face shows instead.
const HEADGEAR_HEADS := {"m": ["Swat", "Spacesuit"], "f": []}


## With the helmet off the head (`_place_helmet`), a person whose head part is
## itself headgear (`HEADGEAR_HEADS`) shows their build's plain face in its
## place, so a helmet never comes off another helmet; it goes back once the
## helmet is on. View only: the appearance is untouched.
func _bare_face(on: bool) -> void:
	var build: String = _appearance.get("build", "")
	if _skeleton == null or build == "":
		return
	for node in _skeleton.get_children():
		var part := node as MeshInstance3D
		if part == null or part.get_meta("slot", "") != "head":
			continue
		if on and not _street.has("head") and _appearance.get("head", "") in HEADGEAR_HEADS.get(build, []):
			_suit_part(part, "head", Human.STARTER[build][0])
		elif not on and _street.has("head"):
			_give_back(part, "head")


## Puts back the part `_suit_part` took off `slot`.
func _give_back(part: MeshInstance3D, slot: String) -> void:
	var kept: Dictionary = _street[slot]
	_street.erase(slot)
	_drop_materials(part)
	part.mesh = kept["mesh"]
	part.skin = kept["skin"]
	var mats: Array = kept["mats"]
	for i in mats.size():
		part.set_surface_override_material(i, mats[i])
		if mats[i] is ShaderMaterial:
			_materials.append(mats[i])


## The node a `_hang` holder keeps its part in (moved and turned with it).
func _held_part(hung: Node3D) -> Node3D:
	return hung.get_child(0) as Node3D if hung is BoneAttachment3D else hung


## Moves the helmet to where `Actor.helmet_stow` has it as shown
## (`ActionPose.helmet`): on the head, in the off hand on its way, or on its
## hip clip, and shows the face while it is off the head. In the hand it is
## carried from the head's place to the clip's along a swing out round the
## body, and the hand follows it (`helmet_grip`). View only.
func _place_helmet(may_stow: bool) -> void:
	if _helmet_model == null or not is_instance_valid(_helmet_model):
		return
	var stow := ActionPose.of(actor).helmet if may_stow and _helmet_clip != null else 0.0
	var at := ActionPose.helmet_place(stow)
	if at != _helmet_at:
		var parent: Node3D = _held_part(_helmet) if at == "head" \
				else (_held_part(_helmet_clip) if at == "hip" else _helmet_carry)
		_helmet_model.reparent(parent, false)
		_helmet_model.transform = Transform3D.IDENTITY
		if at != "head":
			# Off the head it is no longer left out of first person with it.
			_unhide(_helmet_model)
		_show_head(at != "head")
		_bare_face(at != "head")
		_helmet_at = at
	if at == "hand":
		_helmet_carry.global_transform = helmet_carried(ActionPose.helmet_carry(stow))


## Where the helmet is carried at `carry` (0 at the head, 1 on the clip), in
## the world: between the two places as the body has them now, swung out
## ahead and to the left on the way, so it comes forward off the face and
## passes round the shoulder, not through it.
func helmet_carried(carry: float) -> Transform3D:
	var head := _held_part(_helmet).global_transform
	var clip := _held_part(_helmet_clip).global_transform
	var out := head.interpolate_with(clip, carry)
	var left := -actor.global_basis.x.normalized()
	var ahead := -actor.global_basis.z.normalized()
	# Lifted forward off the face first, so it passes low through the view.
	out.origin += (left * helmet_swing + ahead * helmet_swing_ahead) * sin(PI * carry)
	return out


## Where a hand holds the helmet, in the world, or null with none to hold:
## by its left side (`side` -1, the off hand) or its right (1, the weapon
## hand), wherever it is (`WeaponArm` reaches for it).
func helmet_grip(side := -1.0) -> Variant:
	if _helmet_model == null or not is_instance_valid(_helmet_model) or _helmet_clip == null:
		return null
	var stow := ActionPose.of(actor).helmet
	var place := ActionPose.helmet_place(stow)
	var middle: Vector3
	if place == "hand":
		middle = helmet_carried(ActionPose.helmet_carry(stow)).origin
	else:
		middle = _held_part(_helmet if place == "head" else _helmet_clip).global_position
	return middle + actor.global_basis.x.normalized() * helmet_grip_out * side - actor.global_basis.y.normalized() * helmet_grip_drop


## Where a hand reaches on its way to the helmet, in the world: `u` 0 is
## the hand hanging at its side (`helmet_hand_rest`), 1 on its grip
## (`helmet_grip`). The way bows out ahead, so the arm comes up in front
## of the body as a person's does, never out to the side.
func helmet_reach(side: float, u: float) -> Variant:
	var grip: Variant = helmet_grip(side)
	if grip == null:
		return null
	var scale := float(_def.get("height", 1.8)) / 1.8
	var rest := actor.global_transform * (Vector3(helmet_hand_rest.x * side, helmet_hand_rest.y * scale, helmet_hand_rest.z))
	var ahead := -actor.global_basis.z.normalized()
	var t := smoothstep(0.0, 1.0, u)
	return rest.lerp(grip as Vector3, t) + ahead * helmet_reach_ahead * sin(PI * t)


## Puts what `hide_head` moved to the head's layer back on its own.
func _unhide(root: Node) -> void:
	var bit := 1 << (MirrorScript.HEAD_LAYER - 1)
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual.layers == bit:
			visual.layers = visual.get_meta("layers_before", 1)
		_head_hidden.erase(visual)


## The helmet model for a visor `mode` (see `Visor`): a shell of `size` round
## the head, front toward -Z, glass lit in `glass` and the mode's fitting,
## each design its own (`helmet_model.gd`). `tier` 2 adds the Mk2 trim.
static func build_helmet(mode: String, glass: Color, size: Vector3, shell_color: Color, tier := 1) -> Node3D:
	return HelmetModel.G.cached("helmet:%s:%s:%s:%s:%d" % [mode, glass.to_html(), size, shell_color.to_html(), tier],
			func() -> Node3D: return HelmetModel.build(mode, glass, size, shell_color, tier))


## An exo trooper's cooling pack, front toward -Z (against the back): a
## squat housing, two finned radiator stacks standing proud of it and a
## coolant strip down the middle lit in `lit` (the side it fights for).
static func build_cooler(color: Color, lit: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "CoolerModel"
	var shell := _solid(color.darkened(0.15), 0.0)
	var dark := _solid(color.darkened(0.5), 0.0)
	_piece(root, "Housing", BoxMesh.new(), shell, Vector3(0, 0, 0.02), Vector3(0.34, 0.4, 0.13))
	_piece(root, "Lid", BoxMesh.new(), shell, Vector3(0, 0.22, 0.0), Vector3(0.3, 0.05, 0.16))
	for side: float in [-1.0, 1.0]:
		var stack := CylinderMesh.new()
		stack.top_radius = 0.5
		stack.bottom_radius = 0.5
		stack.height = 1.0
		_piece(root, "Stack", stack, dark, Vector3(side * 0.12, 0.05, 0.12), Vector3(0.09, 0.44, 0.09))
		for i in 5:
			_piece(root, "Fin", stack, shell, Vector3(side * 0.12, -0.12 + i * 0.075, 0.12),
					Vector3(0.12, 0.012, 0.12))
	_piece(root, "Coolant", BoxMesh.new(), _solid(lit.lightened(0.25), 1.2), Vector3(0, 0.0, 0.09),
			Vector3(0.035, 0.28, 0.01))
	return root


## Hangs `part` on `bone` so that, at rest, it sits at `at` (actor space).
func _hang_at(part: Node3D, holder_name: String, bone_name: String, at: Vector3) -> Node3D:
	var bone := _skeleton.find_bone(bone_name) if _skeleton else -1
	var offset := at
	if bone >= 0:
		offset = at - _rest_at(bone_name)
	return _hang(part, holder_name, bone_name if bone >= 0 else "", offset, at, true)


## Where a bone sits at rest, as the actor sees it.
func _rest_at(bone_name: String) -> Vector3:
	var bone := _skeleton.find_bone(bone_name)
	var to_actor := actor.global_transform.affine_inverse()
	return (to_actor * _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)).origin


## The Kiln Walker's own body (Caleb's call: not a stock model), built round
## the walking skeleton of the skin's scene, whose own mesh is hidden: a low,
## wide armored hull carried level between two heavy legs, the cannon built
## into its glacis at the height of the walker's eyes (where the tracking
## beam starts), the heat vent let into the rear armor (the weak spot: hits
## from behind or above), hip drums, armored thighs, pistons down the shins
## and broad splayed feet. Gunmetal, with panels and a lit sensor slit in
## the army's colour. Faceted low-poly blocks, like the rest of the game.
## Everything hangs on the bone it moves with, so the walk clip drives it.
func _build_walker() -> void:
	if _skeleton == null:
		return
	var metal := _solid(Color(0.36, 0.37, 0.39), 0.0)
	var dark := _solid(Color(0.13, 0.13, 0.14), 0.0)
	var piston := _solid(Color(0.6, 0.61, 0.62), 0.0)
	var paint := _solid(actor.body_color.darkened(0.3), 0.0)
	var lit := _solid(actor.body_color.lightened(0.2), 2.4)
	var hip := _rest_at("UpperLeg.L")
	var hull_bone := "Body"
	var eye := actor.eye_height
	var top := minf(eye + 0.22, actor.stand_height - 0.02)
	var low := hip.y - 0.16
	var mid := hip.y + 0.18
	var deck := eye - 0.2
	var hull := Node3D.new()
	hull.name = "WalkerHull"
	# Low and wide: the belly flares out to the hull's widest line over the
	# hips, the casemate slopes in to a deck with a long glacis, and the gun
	# house on the deck carries the cannon. Each is [left, right, front, back].
	var belly_lo := [-0.72, 0.72, -0.72, 0.76]
	var waist := [-0.88, 0.88, -1.05, 0.98]
	var shoulder := [-0.82, 0.82, -0.5, 0.88]
	var roof := [-0.62, 0.62, -0.28, 0.7]
	_block(hull, "Belly", dark, low, belly_lo, mid, waist)
	_block(hull, "Casemate", metal, mid, waist, deck, shoulder)
	_block(hull, "GunHouse", metal, deck, shoulder, top, roof)
	# Where a face is at a height, front or back, on the block it is on.
	var front_at := func(y: float) -> float:
		if y < deck:
			return lerpf(waist[2], shoulder[2], (y - mid) / (deck - mid))
		return lerpf(shoulder[2], roof[2], (y - deck) / (top - deck))
	var rake := atan2(shoulder[2] - waist[2], deck - mid)
	var house_rake := atan2(roof[2] - shoulder[2], top - deck)
	# A rim round the waist, armored sponsons over the hips and a chin
	# plate, in the army's colour.
	_block(hull, "Rim", dark, mid - 0.05, [-0.9, 0.9, -1.07, 1.0], mid + 0.02, [-0.9, 0.9, -1.07, 1.0])
	for side: float in [-1.0, 1.0]:
		_block(hull, "Sponson", paint, mid - 0.02, [side * 0.7 - 0.2, side * 0.7 + 0.2, -0.7, 0.75], mid + 0.24,
				[side * 0.66 - 0.16, side * 0.66 + 0.16, -0.5, 0.62])
	# Bolt-on armor tiles in rows down the glacis, and side plates down the
	# casemate's flanks, so its big faces read as armor.
	var tile := _solid(Color(0.31, 0.32, 0.34), 0.0)
	for row in 2:
		var tile_y := lerpf(mid, deck, 0.3 + row * 0.4)
		var count := 4 - row
		for i in count:
			var x := (i - (count - 1) * 0.5) * 0.38
			var block := _piece(hull, "Tile", BoxMesh.new(), tile,
					Vector3(x, tile_y, front_at.call(tile_y) - 0.035), Vector3(0.34, 0.2, 0.07))
			block.rotation.x = rake
	for side: float in [-1.0, 1.0]:
		var flank := _piece(hull, "FlankPlate", BoxMesh.new(), tile,
				Vector3(side * lerpf(waist[1], shoulder[1], 0.5) + side * 0.02, lerpf(mid, deck, 0.5), 0.15),
				Vector3(0.05, 0.36, 1.1))
		flank.rotation.z = side * atan2(waist[1] - shoulder[1], deck - mid)
		_piece(hull, "FlankStripe", BoxMesh.new(), paint,
				Vector3(side * (lerpf(waist[1], shoulder[1], 0.5) + 0.05), lerpf(mid, deck, 0.5), -0.55),
				Vector3(0.03, 0.36, 0.18)).rotation.z = side * atan2(waist[1] - shoulder[1], deck - mid)
	# A sensor slit across the gun house over the cannon, lit in the army's
	# colour, and a hatch and a stripe of paint on the roof.
	var slit_y := top - 0.07
	var slit := _piece(hull, "Slit", BoxMesh.new(), lit, Vector3(0, slit_y, front_at.call(slit_y) - 0.012),
			Vector3(0.66, 0.045, 0.03))
	slit.rotation.x = house_rake
	_piece(hull, "Hatch", BoxMesh.new(), dark, Vector3(0, top + 0.02, 0.22), Vector3(0.44, 0.05, 0.42))
	_piece(hull, "RoofStripe", BoxMesh.new(), paint, Vector3(0, top + 0.005, -0.12), Vector3(0.96, 0.02, 0.18))
	# The heat vent, set into the rear armor: an armored frame round a grille
	# of glowing slats in the Foundry's molten orange, louvers over it, and
	# two short stacks either side.
	var vent_y := lerpf(mid, deck, 0.5)
	var vent_z := lerpf(waist[3], shoulder[3], 0.5)
	var lean := atan2(shoulder[3] - waist[3], deck - mid)
	var vent := Node3D.new()
	vent.name = "Vent"
	vent.position = Vector3(0, vent_y, vent_z)
	vent.rotation.x = lean
	hull.add_child(vent)
	_piece(vent, "VentFrame", BoxMesh.new(), metal, Vector3(0, 0, 0.01), Vector3(0.96, 0.5, 0.07))
	_piece(vent, "Grille", BoxMesh.new(), dark, Vector3(0, 0, 0.03), Vector3(0.78, 0.38, 0.05))
	var glow := _solid(VENT_GLOW, 3.0)
	for i in 5:
		_piece(vent, "Slat", BoxMesh.new(), glow, Vector3(0, -0.15 + i * 0.075, 0.06),
				Vector3(0.7, 0.032, 0.02))
	_piece(vent, "Louver", BoxMesh.new(), paint, Vector3(0, 0.27, 0.08), Vector3(1.0, 0.06, 0.14))
	var light := OmniLight3D.new()
	light.light_color = VENT_GLOW
	light.light_energy = 1.6
	light.omni_range = 2.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0, 0.35)
	vent.add_child(light)
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 8
	for side: float in [-1.0, 1.0]:
		var stack := _piece(hull, "Stack", tube, dark, Vector3(side * 0.6, deck + 0.1, shoulder[3] - 0.08),
				Vector3(0.14, 0.34, 0.14))
		stack.rotation.x = 0.3
		_piece(hull, "StackCap", tube, glow, Vector3(side * 0.6, deck + 0.26, shoulder[3] - 0.03),
				Vector3(0.11, 0.02, 0.11)).rotation.x = 0.3
	# The cannon, through the glacis on the line of the walker's eyes: a
	# mantlet let into the armor, a sleeve, the long barrel and a muzzle
	# brake. It pitches with the aim (`_aim_cannon`).
	var gun := Node3D.new()
	gun.name = "Cannon"
	gun.position = Vector3(0, eye, front_at.call(eye))
	hull.add_child(gun)
	var mantlet := _piece(gun, "Mantlet", BoxMesh.new(), metal, Vector3(0, 0, 0.04), Vector3(0.5, 0.36, 0.34))
	mantlet.rotation.x = house_rake * 0.5
	_piece(gun, "MantletPaint", BoxMesh.new(), paint, Vector3(0, 0.0, -0.13), Vector3(0.36, 0.26, 0.04))
	var sleeve := _piece(gun, "Sleeve", tube, dark, Vector3(0, 0, -0.38), Vector3(0.24, 0.46, 0.24))
	sleeve.rotation.x = PI * 0.5
	var barrel := _piece(gun, "Barrel", tube, metal, Vector3(0, 0, -1.0), Vector3(0.17, 1.1, 0.17))
	barrel.rotation.x = PI * 0.5
	_piece(gun, "Brake", BoxMesh.new(), dark, Vector3(0, 0, -1.6), Vector3(0.3, 0.2, 0.24))
	var bore := _piece(gun, "Bore", tube, glow, Vector3(0, 0, -1.725), Vector3(0.09, 0.01, 0.09))
	bore.rotation.x = PI * 0.5
	_cannon = gun
	# Hip drums on the hull's flanks, where the legs hang.
	var drum := CylinderMesh.new()
	drum.top_radius = 0.5
	drum.bottom_radius = 0.5
	drum.height = 1.0
	drum.radial_segments = 10
	for side: float in [-1.0, 1.0]:
		var x := absf(hip.x) * side
		var hub := _piece(hull, "HipDrum", drum, dark, Vector3(x + side * 0.14, hip.y, hip.z), Vector3(0.5, 0.3, 0.5))
		hub.rotation.z = PI * 0.5
		var cap := _piece(hull, "HipCap", drum, metal, Vector3(x + side * 0.3, hip.y, hip.z), Vector3(0.36, 0.04, 0.36))
		cap.rotation.z = PI * 0.5
	_hang_at(hull, "WalkerHull", hull_bone, Vector3.ZERO)
	# The legs: an armored thigh, a knee drum, a shin with a ram down its
	# front, a hock drum, a shank and a broad foot with splayed toes.
	for side: String in ["L", "R"]:
		var out := Vector3(signf(_rest_at("UpperLeg." + side).x), 0.0, 0.0)
		_limb("UpperLeg." + side, "MidLeg." + side, Vector3.ZERO, Vector2(0.26, 0.36), metal, 0.0, 1.0)
		_limb("UpperLeg." + side, "MidLeg." + side, out * 0.15, Vector2(0.06, 0.4), paint, 0.12, 0.85)
		_limb("MidLeg." + side, "LowerLeg." + side, Vector3.ZERO, Vector2(0.22, 0.26), metal, 0.05, 0.95)
		_limb("MidLeg." + side, "LowerLeg." + side, Vector3.ZERO, Vector2(0.07, 0.07), piston, 0.1, 0.9, true,
				Vector3(0, 0, -0.17))
		_limb("LowerLeg." + side, "FootBack." + side, Vector3.ZERO, Vector2(0.18, 0.2), dark, 0.0, 0.9)
		_limb("LowerLeg." + side, "FootBack." + side, out * 0.12, Vector2(0.05, 0.05), piston, 0.1, 0.8, true)
		var knee := _rest_at("MidLeg." + side)
		var knee_hub := Node3D.new()
		_piece(knee_hub, "KneeDrum", drum, dark, Vector3.ZERO, Vector3(0.36, 0.34, 0.36)).rotation.z = PI * 0.5
		_piece(knee_hub, "KneePlate", BoxMesh.new(), paint, Vector3(0, 0.04, -0.17), Vector3(0.26, 0.24, 0.06))
		_hang_at(knee_hub, "Knee" + side, "MidLeg." + side, knee)
		var hock := Node3D.new()
		_piece(hock, "HockDrum", drum, dark, Vector3.ZERO, Vector3(0.26, 0.28, 0.26)).rotation.z = PI * 0.5
		_hang_at(hock, "Hock" + side, "LowerLeg." + side, _rest_at("LowerLeg." + side))
		var ankle := _rest_at("FootBack." + side)
		var foot := Node3D.new()
		_piece(foot, "Sole", BoxMesh.new(), dark, Vector3(0, 0.05, 0.0), Vector3(0.46, 0.1, 0.62))
		_piece(foot, "Ankle", BoxMesh.new(), metal, Vector3(0, 0.17, 0.04), Vector3(0.26, 0.18, 0.26))
		for toe: float in [-1.0, 0.0, 1.0]:
			var claw := _piece(foot, "Toe", BoxMesh.new(), metal, Vector3(toe * 0.16, 0.06, -0.38),
					Vector3(0.13, 0.11, 0.28))
			claw.rotation.y = -toe * 0.3
		_piece(foot, "Heel", BoxMesh.new(), metal, Vector3(0, 0.06, 0.36), Vector3(0.18, 0.1, 0.2))
		_hang_at(foot, "Foot" + side, "FootBack." + side, Vector3(ankle.x, 0.0, ankle.z))


## The lit parts of a marsh beast: the planet's fungal glow.
const CREATURE_GLOW := Color(0.5, 1.0, 0.65)
## A shellback's soft rear: pale, fleshy hide lit faintly from inside.
const SOFT_REAR := Color(0.95, 0.66, 0.55)


## The walker's cannon, raised and lowered with the aim (view only).
var _cannon: Node3D


## A marsh beast's own body (DESIGN.md "Spore Marsh"), built round the
## walking skeleton of the skin's scene, whose own mesh is hidden: "stalker",
## "shellback" or "bloater". Rounded shapes, unlike the machines' blocks,
## each hung on the bone it moves with so the walk clip drives it. Lit parts
## are the planet's own glow: eyes, gills, the shellback's soft rear and the
## bloater's pustules. View only.
func _build_creature(kind: String) -> void:
	if _skeleton == null:
		return
	var hide := _solid(actor.body_color, 0.0)
	hide.metallic = 0.0
	hide.roughness = 0.8
	var dark := _solid(actor.body_color.darkened(0.45), 0.0)
	dark.metallic = 0.0
	dark.roughness = 0.9
	var bone := _solid(Color(0.78, 0.74, 0.62), 0.0)
	bone.metallic = 0.0
	var glow := _solid(CREATURE_GLOW, 2.6)
	var body := _rest_at("Body")
	var chest := _rest_at("Chest")
	var ball := SphereMesh.new()
	ball.radial_segments = 16
	ball.rings = 8
	ball.radius = 0.5
	ball.height = 1.0
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 8
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.5
	horn.height = 1.0
	horn.radial_segments = 6
	var h := actor.stand_height
	match kind:
		"stalker":
			var low := body.y * 0.95
			var trunk := Node3D.new()
			_piece(trunk, "Torso", ball, hide, Vector3(0, low, 0.0), Vector3(0.46, 0.42, 1.15) * h / 1.6)
			_piece(trunk, "Belly", ball, dark, Vector3(0, low - 0.08 * h, -0.05), Vector3(0.38, 0.3, 0.9) * h / 1.6)
			for i in 6:
				var spine := _piece(trunk, "Spine", horn, bone, Vector3(0, low + 0.2 * h / 1.6, -0.35 + i * 0.14) * Vector3(1, 1, h / 1.6),
						Vector3(0.05, 0.16, 0.05) * h / 1.6)
				spine.rotation.x = 0.5
			# The tail, tapering out behind.
			for i in 4:
				_piece(trunk, "Tail", ball, hide, Vector3(0, low + 0.02 * i, (0.6 + i * 0.26) * h / 1.6),
						Vector3(0.22 - i * 0.04, 0.2 - i * 0.035, 0.42) * h / 1.6)
			_hang_at(trunk, "CreatureTrunk", "Torso", trunk.position)
			# The head and long jaw, carried forward and low.
			var skull := Node3D.new()
			var at := Vector3(0, low + 0.12 * h, -0.72 * h / 1.6)
			_piece(skull, "Skull", ball, hide, at, Vector3(0.28, 0.26, 0.42) * h / 1.6)
			_piece(skull, "Jaw", ball, dark, at + Vector3(0, -0.08, -0.22) * h / 1.6, Vector3(0.2, 0.12, 0.42) * h / 1.6)
			for side: float in [-1.0, 1.0]:
				_piece(skull, "Eye", ball, glow, at + Vector3(side * 0.1, 0.06, -0.12) * h / 1.6,
						Vector3(0.05, 0.04, 0.05) * h / 1.6)
				for t in 3:
					var tooth := _piece(skull, "Tooth", horn, bone, at + Vector3(side * 0.07, -0.13, -0.28 - t * 0.07) * h / 1.6,
							Vector3(0.025, 0.07, 0.025) * h / 1.6)
					tooth.rotation.x = PI
			_hang_at(skull, "CreatureHead", "Head", Vector3.ZERO)
			# Hooked foreclaws, held up in front of the chest.
			for side: float in [-1.0, 1.0]:
				var arm := Node3D.new()
				var shoulder := Vector3(side * 0.18 * h / 1.6, low - 0.02, -0.38 * h / 1.6)
				var reach := _piece(arm, "Foreleg", tube, hide, shoulder + Vector3(0, -0.12, -0.08) * h / 1.6,
						Vector3(0.07, 0.3, 0.07) * h / 1.6)
				reach.rotation.x = 0.6
				for c in 3:
					var claw := _piece(arm, "Claw", horn, bone,
							shoulder + Vector3((c - 1) * 0.03, -0.28, -0.24) * h / 1.6, Vector3(0.025, 0.16, 0.025) * h / 1.6)
					claw.rotation.x = -2.2
				_hang_at(arm, "Foreclaw" + ("L" if side < 0.0 else "R"), "Chest", Vector3.ZERO)
			_creature_legs(hide, Vector2(0.11, 0.13), bone)
		"shellback":
			var dome := Node3D.new()
			var mid := body.y * 0.82
			_piece(dome, "Shell", ball, hide, Vector3(0, mid + 0.1 * h, 0), Vector3(1.5, 0.95, 1.9) * h / 1.6)
			_piece(dome, "Skirt", ball, dark, Vector3(0, mid - 0.05 * h, 0), Vector3(1.6, 0.4, 2.0) * h / 1.6)
			# Plates in rows down the dome.
			for row in 3:
				for i in 3:
					# On the dome's curve: an ellipsoid's surface over the
					# plate's spot across and along it.
					var px := (i - 1) * 0.42
					var pz := -0.5 + row * 0.5
					var up := 0.475 * sqrt(maxf(0.0, 1.0 - pow(px / 0.75, 2.0) - pow(pz / 0.95, 2.0)))
					var plate := _piece(dome, "Plate", ball, dark,
							Vector3(px * h / 1.6, mid + 0.1 * h + up * h / 1.6, pz * h / 1.6), Vector3(0.38, 0.09, 0.42) * h / 1.6)
					plate.rotation = Vector3(-pz * 0.9, 0, -px * 1.2)
			# The soft rear: pale hide between the back plates, lit from inside.
			var soft := _solid(SOFT_REAR, 0.9)
			soft.metallic = 0.0
			_piece(dome, "SoftRear", ball, soft, Vector3(0, mid + 0.05 * h, 0.86 * h / 1.6), Vector3(0.7, 0.5, 0.3) * h / 1.6)
			_hang_at(dome, "CreatureShell", "Torso", Vector3.ZERO)
			var face := Node3D.new()
			var at := Vector3(0, mid - 0.02 * h, -1.0 * h / 1.6)
			_piece(face, "Head", ball, dark, at, Vector3(0.6, 0.42, 0.5) * h / 1.6)
			_piece(face, "Brow", ball, hide, at + Vector3(0, 0.13, -0.04) * h / 1.6, Vector3(0.64, 0.16, 0.42) * h / 1.6)
			for side: float in [-1.0, 1.0]:
				_piece(face, "Eye", ball, glow, at + Vector3(side * 0.18, 0.06, -0.22) * h / 1.6,
						Vector3(0.06, 0.05, 0.05) * h / 1.6)
				var tusk := _piece(face, "Tusk", horn, bone, at + Vector3(side * 0.2, -0.08, -0.3) * h / 1.6,
						Vector3(0.06, 0.26, 0.06) * h / 1.6)
				tusk.rotation.x = -1.9
			_hang_at(face, "CreatureHead", "Head", Vector3.ZERO)
			_creature_legs(dark, Vector2(0.24, 0.26), bone)
		"bloater":
			var sac := Node3D.new()
			var at := Vector3(0, (chest.y + body.y) * 0.5, 0)
			_piece(sac, "Sac", ball, hide, at, Vector3(1.3, 1.4, 1.3) * h / 2.1)
			_piece(sac, "Belly", ball, dark, at + Vector3(0, -0.42, 0) * h / 2.1, Vector3(1.0, 0.6, 1.0) * h / 2.1)
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			for i in 12:
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
				_piece(sac, "Pustule", ball, glow, at + dir * 0.66 * h / 2.1, Vector3.ONE * rng.randf_range(0.1, 0.18) * h / 2.1)
			for i in 5:
				var tendril := _piece(sac, "Tendril", tube, dark,
						at + Vector3(cos(i * 1.3) * 0.35, -0.75, sin(i * 1.3) * 0.35) * h / 2.1, Vector3(0.04, 0.5, 0.04) * h / 2.1)
				tendril.rotation.z = cos(i * 2.1) * 0.25
			_hang_at(sac, "CreatureSac", "Chest", Vector3.ZERO)
			var face := Node3D.new()
			var mouth := at + Vector3(0, -0.25, -0.62) * h / 2.1
			_piece(face, "Mouth", ball, dark, mouth, Vector3(0.36, 0.22, 0.2) * h / 2.1)
			for side: float in [-1.0, 1.0]:
				_piece(face, "Eye", ball, glow, mouth + Vector3(side * 0.12, 0.16, -0.06) * h / 2.1,
						Vector3(0.06, 0.06, 0.05) * h / 2.1)
			_hang_at(face, "CreatureHead", "Head", Vector3.ZERO)
			_creature_legs(dark, Vector2(0.14, 0.16), bone)


## A beast's two legs down the skeleton's own (thigh, shank and foot), with
## claws on the foot.
func _creature_legs(mat: Material, size: Vector2, claw: Material) -> void:
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.5
	horn.height = 1.0
	horn.radial_segments = 6
	for side: String in ["L", "R"]:
		_limb("UpperLeg." + side, "MidLeg." + side, Vector3.ZERO, size, mat, 0.0, 1.0, true)
		_limb("MidLeg." + side, "LowerLeg." + side, Vector3.ZERO, size * 0.8, mat, 0.0, 1.0, true)
		_limb("LowerLeg." + side, "FootBack." + side, Vector3.ZERO, size * 0.6, mat, 0.0, 1.0, true)
		var ankle := _rest_at("FootBack." + side)
		var foot := Node3D.new()
		var pad := SphereMesh.new()
		pad.radial_segments = 10
		pad.rings = 5
		_piece(foot, "Pad", pad, mat, Vector3(0, size.x * 0.3, -size.x * 0.4), Vector3(size.x * 1.6, size.x * 0.7, size.x * 2.4))
		for toe: float in [-1.0, 0.0, 1.0]:
			var nail := _piece(foot, "Claw", horn, claw, Vector3(toe * size.x * 0.6, size.x * 0.2, -size.x * 1.5),
					Vector3(size.x * 0.35, size.x * 1.3, size.x * 0.35))
			nail.rotation = Vector3(-1.5, -toe * 0.3, 0)
		_hang_at(foot, "Foot" + side, "FootBack." + side, Vector3(ankle.x, 0.0, ankle.z))


## Pitches the walker's cannon in its mantlet toward where it aims.
func _aim_cannon() -> void:
	if _cannon == null or actor.is_dead:
		return
	var dir := actor.get_aim_dir()
	_cannon.rotation.x = clampf(asin(clampf(dir.y, -1.0, 1.0)), -0.25, 0.35)


## A faceted block, flat shaded: a bottom face at `y0` and a top face at
## `y1`, each [left, right, front, back] (actor space, front toward -Z).
static func _block(root: Node3D, block_name: String, mat: Material, y0: float, lower: Array, y1: float,
		upper: Array) -> MeshInstance3D:
	var corners := func(y: float, r: Array) -> Array[Vector3]:
		return [Vector3(r[0], y, r[2]), Vector3(r[1], y, r[2]), Vector3(r[1], y, r[3]), Vector3(r[0], y, r[3])]
	var b: Array[Vector3] = corners.call(y0, lower)
	var t: Array[Vector3] = corners.call(y1, upper)
	var faces := [[b[0], b[1], b[2], b[3]], [t[3], t[2], t[1], t[0]]]
	for i in 4:
		var j := (i + 1) % 4
		faces.append([b[i], t[i], t[j], b[j]])
	var centre := Vector3.ZERO
	for p in b + t:
		centre += p / 8.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Array in faces:
		var a: Vector3 = face[0]
		var b1: Vector3 = face[1]
		var c: Vector3 = face[2]
		var d: Vector3 = face[3]
		var normal := (b1 - a).cross(c - a)
		if normal.length_squared() < 0.000001:
			normal = (c - a).cross(d - a)
		var outward := (a + b1 + c + d) * 0.25 - centre
		var order := [0, 1, 2, 0, 2, 3]
		# Godot draws clockwise faces as the front.
		if normal.dot(outward) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		normal = normal.normalized() * signf(normal.dot(outward))
		for k: int in order:
			st.set_normal(normal)
			st.add_vertex(face[k])
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var part := MeshInstance3D.new()
	part.name = block_name
	part.mesh = mesh
	root.add_child(part)
	return part


## A limb segment along a bone, from `from` of the way to its `child` up to
## `to`, set off by `aside` (actor space, at rest), `size` across (x) and
## deep (along the leg's swing). A `round` one is a piston, pushed `ahead`.
func _limb(bone: String, child: String, aside: Vector3, size: Vector2, mat: Material, from: float, to: float,
		round := false, ahead := Vector3.ZERO) -> void:
	if _skeleton.find_bone(bone) < 0 or _skeleton.find_bone(child) < 0:
		return
	var a := _rest_at(bone)
	var b := _rest_at(child)
	var along := b - a
	var length := along.length() * (to - from)
	if length < 0.01:
		return
	var y := along.normalized()
	var x := Vector3.RIGHT
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	var root := Node3D.new()
	var mesh: PrimitiveMesh = BoxMesh.new()
	if round:
		var tube := CylinderMesh.new()
		tube.top_radius = 0.5
		tube.bottom_radius = 0.5
		tube.height = 1.0
		tube.radial_segments = 8
		mesh = tube
	var bar := _piece(root, "Limb", mesh, mat, Vector3.ZERO, Vector3.ONE)
	bar.basis = Basis(x, y, z) * Basis.from_scale(Vector3(size.x, length, size.y))
	# `ahead` is in the limb's own frame: toward -z is the leg's front.
	_hang_at(root, "Limb", bone, a + along * ((from + to) * 0.5) + aside + Basis(x, y, z) * ahead)


## An exo trooper's suit, round a person of ordinary size: a gunmetal frame
## down the outside of each arm and leg with a joint at hip, knee, shoulder
## and elbow, actuators along the front of the thighs and forearms, boot
## braces, a spine and a shoulder yoke with a roll cage up over the head,
## and a power pack on the back. Everything hangs on the bone it moves with.
func _build_exo_suit() -> void:
	if _skeleton == null:
		return
	var frame := _solid(Color(0.28, 0.29, 0.31), 0.0)
	var joint := _solid(Color(0.12, 0.12, 0.13), 0.0)
	var piston := _solid(Color(0.62, 0.63, 0.64), 0.0)
	var paint := _solid(actor.body_color.darkened(0.3), 0.0)
	for side: String in ["L", "R"]:
		var hip := _rest_at("UpperLeg." + side)
		var out := Vector3(signf(hip.x), 0.0, 0.0)
		var knee := _rest_at("LowerLeg." + side)
		var foot := _rest_at("Foot." + side)
		# Legs: heavy thigh and shin bars on the outside, a hip drum, a knee
		# drum under an actuator housing, a ram down the front of the thigh
		# and shin, and an armored boot.
		_strut("UpperLeg." + side, "LowerLeg." + side, out * 0.14, 0.1, frame, 0.05, 0.95)
		_strut("LowerLeg." + side, "Foot." + side, out * 0.13, 0.09, frame, 0.05, 0.88)
		_strut("UpperLeg." + side, "LowerLeg." + side, Vector3(0, 0, -0.12), 0.05, piston, 0.2, 0.85, true)
		_strut("LowerLeg." + side, "Foot." + side, Vector3(0, 0, -0.1), 0.045, piston, 0.12, 0.7, true)
		_disc("UpperLeg." + side, hip + out * 0.16, 0.1, joint)
		_disc("LowerLeg." + side, knee + out * 0.15, 0.09, joint)
		var housing := Node3D.new()
		_piece(housing, "KneeHousing", BoxMesh.new(), frame, Vector3.ZERO, Vector3(0.16, 0.16, 0.12))
		_piece(housing, "KneeCap", BoxMesh.new(), paint, Vector3(0, 0.02, -0.065), Vector3(0.12, 0.1, 0.02))
		_hang_at(housing, "Knee" + side, "LowerLeg." + side, knee + Vector3(0, 0.02, -0.1))
		var boot := Node3D.new()
		_piece(boot, "Boot", BoxMesh.new(), frame, Vector3.ZERO, Vector3(0.19, 0.15, 0.34))
		_piece(boot, "Toe", BoxMesh.new(), joint, Vector3(0, -0.03, -0.18), Vector3(0.17, 0.09, 0.06))
		_piece(boot, "Brace", BoxMesh.new(), frame, Vector3(out.x * 0.11, 0.1, 0.02), Vector3(0.05, 0.22, 0.18))
		_hang_at(boot, "Boot" + side, "Foot." + side, foot + Vector3(0, 0.06, -0.04))
		# Arms: heavy bars on the upper arm and forearm, shoulder and elbow
		# drums, an elbow housing, a ram along the forearm, and a guard over
		# the shoulder in the army's colour.
		var shoulder := _rest_at("UpperArm." + side)
		var elbow := _rest_at("LowerArm." + side)
		var arm_out := Vector3(signf(shoulder.x), 0.0, 0.0)
		_strut("UpperArm." + side, "LowerArm." + side, arm_out * 0.11, 0.08, frame, 0.05, 0.95)
		_strut("LowerArm." + side, "Wrist." + side, arm_out * 0.1, 0.075, frame, 0.05, 0.92)
		_strut("LowerArm." + side, "Wrist." + side, Vector3(0, 0.0, -0.08), 0.04, piston, 0.15, 0.85, true)
		_disc("LowerArm." + side, elbow + arm_out * 0.12, 0.075, joint)
		_disc("UpperArm." + side, shoulder + arm_out * 0.13, 0.1, joint)
		var elbow_box := Node3D.new()
		_piece(elbow_box, "ElbowHousing", BoxMesh.new(), frame, Vector3.ZERO, Vector3(0.12, 0.12, 0.14))
		_hang_at(elbow_box, "Elbow" + side, "LowerArm." + side, elbow + Vector3(0, 0, 0.07))
		var guard := Node3D.new()
		_piece(guard, "Guard", BoxMesh.new(), paint, Vector3.ZERO, Vector3(0.22, 0.08, 0.26))
		_piece(guard, "Lip", BoxMesh.new(), frame, Vector3(arm_out.x * 0.1, -0.07, 0), Vector3(0.04, 0.14, 0.26))
		_hang_at(guard, "Guard" + side, "UpperArm." + side, shoulder + arm_out * 0.1 + Vector3(0, 0.12, 0))
	# The back: a spine from the hips to a yoke over the shoulders, a roll
	# cage standing over the head, and the power pack between.
	var hips := _rest_at("Hips")
	var chest := _rest_at("Chest")
	var head := _rest_at("Head")
	var back := Vector3(0, 0, 0.17)
	var spine := Node3D.new()
	_piece(spine, "Spine", BoxMesh.new(), frame, Vector3.ZERO, Vector3(0.11, chest.y - hips.y + 0.1, 0.08))
	_hang_at(spine, "Spine", "Abdomen", Vector3(0, (hips.y + chest.y) * 0.5, hips.z + back.z))
	var yoke := Node3D.new()
	var top := head.y + 0.32 - (chest.y + 0.12)
	_piece(yoke, "Yoke", BoxMesh.new(), frame, Vector3.ZERO, Vector3(0.62, 0.1, 0.12))
	for x: float in [-0.19, 0.19]:
		_piece(yoke, "CagePost", BoxMesh.new(), frame, Vector3(x, top * 0.5, 0.0), Vector3(0.07, top, 0.07))
	_piece(yoke, "CageBar", BoxMesh.new(), paint, Vector3(0, top, -0.06), Vector3(0.45, 0.07, 0.2))
	_piece(yoke, "Belt", BoxMesh.new(), frame, Vector3(0, -(chest.y - hips.y) - 0.06, -0.02), Vector3(0.48, 0.1, 0.3))
	_hang_at(yoke, "Yoke", "Chest", Vector3(0, chest.y + 0.12, chest.z + back.z))
	var pack := build_cooler(Color(0.3, 0.31, 0.33), actor.body_color)
	pack.scale = Vector3(1.5, 1.25, 1.5)
	_hang_at(pack, "PowerPack", "Chest", Vector3(0, chest.y - 0.1, chest.z + back.z + 0.14))


## A bar along a bone, from the bone at `from` of the way to its `child` up
## to `to`, set off by `aside` (actor space, at rest) and `thick` across. A
## `round` one is a piston.
func _strut(bone: String, child: String, aside: Vector3, thick: float, mat: Material, from: float, to: float,
		round := false) -> void:
	if _skeleton.find_bone(bone) < 0 or _skeleton.find_bone(child) < 0:
		return
	var a := _rest_at(bone)
	var b := _rest_at(child)
	var along := b - a
	var length := along.length() * (to - from)
	if length < 0.01:
		return
	var y := along.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.UP).normalized()
	var root := Node3D.new()
	var mesh: PrimitiveMesh = BoxMesh.new()
	if round:
		var tube := CylinderMesh.new()
		tube.top_radius = 0.5
		tube.bottom_radius = 0.5
		tube.height = 1.0
		tube.radial_segments = 8
		mesh = tube
	var bar := _piece(root, "Strut", mesh, mat, Vector3.ZERO, Vector3(thick, length, thick * 1.2))
	bar.basis = Basis(x, y, x.cross(y)).orthonormalized() * Basis.from_scale(Vector3(thick, length, thick * 1.2))
	_hang_at(root, "Strut", bone, a + along * ((from + to) * 0.5) + aside)


## A joint: a short drum turned across the body, at `at` on `bone`.
func _disc(bone: String, at: Vector3, radius: float, mat: Material) -> void:
	if _skeleton.find_bone(bone) < 0:
		return
	var drum := CylinderMesh.new()
	drum.top_radius = 0.5
	drum.bottom_radius = 0.5
	drum.height = 1.0
	drum.radial_segments = 10
	var root := Node3D.new()
	var piece := _piece(root, "Joint", drum, mat, Vector3.ZERO, Vector3(radius * 2.0, 0.045, radius * 2.0))
	piece.rotation.z = PI * 0.5
	_hang_at(root, "Joint", bone, at)


## The glow of a walker's heat vent, the weak spot on its back: the Foundry's
## molten orange.
const VENT_GLOW := Color(1.0, 0.36, 0.08)


## A walker's tracking beam, seen by everyone: while its aim is up (the
## command's held aim) a thin line runs from its cannon along the aim to
## whatever it meets, faint at first and hot and wide once it has held
## `lock_time` (the actor's meta, the same the brain waits for), when the
## cannon fires. Breaking the line of sight drops the aim and the beam.
func _update_beam(delta: float) -> void:
	var on := actor.cmd.secondary and not actor.is_dead
	_beam_held = _beam_held + delta if on else 0.0
	if _beam == null:
		_beam = MeshInstance3D.new()
		_beam.name = "TrackingBeam"
		var tube := CylinderMesh.new()
		tube.top_radius = 0.5
		tube.bottom_radius = 0.5
		tube.height = 1.0
		tube.radial_segments = 6
		tube.rings = 1
		_beam.mesh = tube
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam.material_override = _beam_mat
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.top_level = true
		add_child(_beam)
	_beam.visible = on
	if not on:
		return
	var lock: float = actor.get_meta("lock_time", 1.0)
	var held := clampf(_beam_held / maxf(lock, 0.01), 0.0, 1.0)
	var from := actor.get_eye_position()
	var dir := actor.cmd.aim_dir if actor.cmd.aim_dir.length() > 0.5 \
			else Basis.from_euler(Vector3(actor.cmd.pitch, actor.cmd.yaw, 0.0)) * Vector3.FORWARD
	var reach := beam_reach
	if is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach,
				Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
		query.exclude = [actor.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			reach = from.distance_to(hit.position)
	var width := lerpf(0.012, 0.035, held)
	var hot: Color = _def.get("beam_color", Color(1.0, 0.5, 0.12))
	var color := (hot * Color(0.9, 0.25, 0.3)).lerp(hot, held)
	color.a = lerpf(0.25, 0.85, held)
	if held >= 1.0:
		# Locked: it flickers as the cannon fires down it.
		color.a *= 0.75 + 0.25 * sin(_beam_held * 40.0)
	_beam_mat.albedo_color = color
	var mid := from + dir * reach * 0.5
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	# The tube stands along Y: lay it along the aim (-Z of `looking_at`).
	basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
	_beam.global_transform = Transform3D(basis.scaled_local(Vector3(width, reach, width)), mid)


## How far a tracking beam reaches when it meets nothing.
var beam_reach := 90.0


## How much a frame covers, from its weight (Caleb's tactical pass): light
## is a slim carrier, caps, bracers and knee pads; medium the full kit with
## a cummerbund, pouches, an upper arm plate and a tasset; heavy layered
## plate with abdominal lames, a gorget, faulds and greaves. "pads" is how
## many lames hang under each shoulder dome. The shapes are
## `armor_model.gd`'s; a frame's tag picks the row, so a frame moved to
## another weight tier changes bulk with it.
const FRAME_BULK := {
	"light": {"pads": 1, "tassets": 1, "collar": false, "greaves": false},
	"medium": {"pads": 2, "tassets": 1, "collar": false, "greaves": false},
	"heavy": {"pads": 3, "tassets": 2, "collar": true, "greaves": true},
}

## Each frame's own look on top of its weight: plate, second plate, carrier
## fabric, straps, the undersuit ("suit"), the lit accent and bare metal,
## with the details that say what it does. Scrap is rusted plate on a
## crooked carrier with patches bolted over it; the Runner slate plate with
## a cool lit back panel (it runs cool, dim on thermal); the Trooper an
## olive carrier with a radio, admin and hydration pouches; the Thermal a
## white shell over a quilted liner with heat coils and a heater pack
## (bright on thermal); the Bulwark dark gunmetal with glowing back vents
## (it runs hot) and hazard chevrons.
const FRAME_STYLES := {
	"scrap": {"plate": Color(0.45, 0.28, 0.17), "plate2": Color(0.3, 0.2, 0.14), "fabric": Color(0.3, 0.27, 0.22),
			"strap": Color(0.14, 0.12, 0.1), "suit": Color(0.11, 0.1, 0.09), "accent": Color(0.85, 0.55, 0.25),
			"metal": Color(0.45, 0.44, 0.42), "rough": 0.9, "glow": 0.8, "details": ["patches"]},
	"runner": {"plate": Color(0.48, 0.52, 0.58), "plate2": Color(0.26, 0.29, 0.33), "fabric": Color(0.3, 0.32, 0.35),
			"strap": Color(0.14, 0.15, 0.17), "suit": Color(0.13, 0.14, 0.16), "accent": Color(0.3, 0.85, 1.0),
			"metal": Color(0.5, 0.53, 0.56), "details": ["spine"]},
	"trooper": {"plate": Color(0.36, 0.37, 0.27), "plate2": Color(0.24, 0.25, 0.19), "fabric": Color(0.46, 0.42, 0.31),
			"strap": Color(0.2, 0.19, 0.15), "suit": Color(0.07, 0.07, 0.065), "accent": Color(1.0, 0.7, 0.28),
			"metal": Color(0.48, 0.48, 0.46), "details": ["radio", "admin", "hydration"]},
	"thermal": {"plate": Color(0.54, 0.55, 0.54), "plate2": Color(0.36, 0.38, 0.4), "fabric": Color(0.4, 0.42, 0.45),
			"strap": Color(0.24, 0.25, 0.27), "suit": Color(0.2, 0.21, 0.23), "accent": Color(1.0, 0.45, 0.12),
			"metal": Color(0.6, 0.62, 0.64), "rough": 0.78, "details": ["quilt", "coils", "heater"]},
	"bulwark": {"plate": Color(0.26, 0.27, 0.29), "plate2": Color(0.14, 0.145, 0.155), "fabric": Color(0.19, 0.19, 0.2),
			"strap": Color(0.08, 0.08, 0.085), "suit": Color(0.045, 0.045, 0.05), "accent": Color(1.0, 0.42, 0.12),
			"metal": Color(0.62, 0.6, 0.56), "metal_finish": 0.35, "details": ["vents", "chevrons"]},
}

## Which look each frame wears; a frame not listed wears its weight's.
const FRAME_LOOKS := {"plate_light": "scrap", "frame_runner": "runner", "frame_trooper": "trooper",
		"frame_thermal": "thermal", "frame_bulwark": "bulwark"}
const WEIGHT_LOOKS := {"light": "runner", "medium": "trooper", "heavy": "bulwark"}

## The outfit whose fitted body, legs and boots a person wears under any
## frame, by build: its cloth becomes the undersuit (`_wear_undersuit`).
const SUIT_OUTFITS := {"m": "Swat", "f": "Soldier"}


## How heavy a frame looks: "light", "medium" or "heavy", from its tags. A
## weight itself ("heavy") or a skin's own plates ("skin:light") answer as is.
static func frame_weight(id: String) -> String:
	var bare := id.trim_prefix("skin:")
	if FRAME_BULK.has(bare):
		return bare
	if ItemDB.has_tag(id, "frame_heavy"):
		return "heavy"
	return "medium" if ItemDB.has_tag(id, "frame_medium") else "light"


## The look a frame wears (a `FRAME_STYLES` key).
static func frame_look(id: String) -> String:
	return FRAME_LOOKS.get(id, WEIGHT_LOOKS[frame_weight(id)])


## The colours and details a frame is built in: its look's `FRAME_STYLES`
## row, worn in the armor paint `paint` (`ArmorPaint.paint_style`; "" for
## the look's own colours).
static func frame_style(id: String, paint := "") -> Dictionary:
	return ArmorPaint.paint_style(FRAME_STYLES[frame_look(id)], paint)


## The armor paint this body wears on the frame `id`: the one its
## appearance picked for the frame's look ("" for none, and always none on
## a skin's own plates).
func frame_paint(id: String) -> String:
	if id == "" or id.begins_with("skin:"):
		return ""
	var paints: Variant = _appearance.get("paints", {})
	return str(paints.get(frame_look(id), "")) if typeof(paints) == TYPE_DICTIONARY else ""


## Puts the worn armor frame on the body, rebuilt when another goes on: the
## carrier on the chest, the belt on the hips and a piece on each upper arm,
## forearm, thigh and shin, every one hung on the bone it moves with, over
## the undersuit.
func _update_frame() -> void:
	var id := actor.frame_id
	# A skin that comes in its own armor (an exo trooper's) wears plates of
	# that weight when no frame is worn.
	var own: String = _def.get("frame", "") if id == "" else ""
	if own != "":
		id = "skin:" + own
	var paint := frame_paint(id)
	var key := id + ("|" + paint if paint != "" else "")
	if key == _frame_id and (id == "" or (not _frame_parts.is_empty() and is_instance_valid(_frame_parts[0]))):
		return
	_frame_id = key
	_wear_undersuit(frame_style(id, paint) if id != "" else {})
	for part in _frame_parts:
		if is_instance_valid(part):
			part.queue_free()
	_frame_parts.clear()
	if id == "" or _skeleton == null:
		return
	var height: float = _def.get("height", 1.8)
	_frame_parts.append(_hang(build_frame(id, paint), "Frame", _def.get("back_bone", ""), frame_offset,
			Vector3(0.0, height * 0.72, 0.0) + frame_offset, true))
	var hips: String = _def.get("hip_bone", "")
	if hips != "" and _skeleton.find_bone(hips) >= 0:
		_frame_parts.append(_hang(build_belt(id, paint), "Belt", hips, Vector3.ZERO, Vector3.ZERO, true))
	for side: String in ["L", "R"]:
		var out := -1.0 if side == "L" else 1.0
		for limb: Array in [["UpperArm", "LowerArm", build_pad(id, out, paint), Vector3(pad_offset.x * out, pad_offset.y, pad_offset.z)],
				["LowerArm", "Wrist", build_bracer(id, out, paint), Vector3.ZERO],
				["UpperLeg", "LowerLeg", build_tasset(id, out, paint), Vector3.ZERO],
				["LowerLeg", "Foot", build_shin(id, out, paint), Vector3.ZERO]]:
			var piece: Node3D = limb[2]
			var held := _hang_limb(piece, limb[0] + "." + side, limb[1] + "." + side, limb[3])
			if held == null:
				piece.free()
			else:
				_frame_parts.append(held)
	if _detail_every > 1:
		_gear_shadows(false)


## Hangs a limb piece, built standing up its limb (Y from the far joint
## toward this one, front -Z, +X out on the right) with its origin at the
## joint, on `bone`, turned along the limb as it stands at rest. Null where
## the skeleton lacks either bone.
func _hang_limb(part: Node3D, bone: String, child: String, offset: Vector3) -> Node3D:
	if _skeleton.find_bone(bone) < 0 or _skeleton.find_bone(child) < 0:
		return null
	var at := _rest_at(bone)
	var up := (at - _rest_at(child)).normalized()
	var front := Vector3.FORWARD - up * up.dot(Vector3.FORWARD)
	front = front.normalized() if front.length() > 0.1 else Vector3.FORWARD
	var held := _hang(part, part.name, bone, offset, at, true)
	part.basis = Basis(up.cross(-front).normalized(), up, -front)
	return held


## Under a frame a person wears the fitted undersuit: the body, legs and
## boots of their build's `SUIT_OUTFITS` (street clothes would bunch out
## through the plates), every surface below the head drawn as the suit in
## the look's colour, its cuffs lit in the accent. `style` empty takes it off
## and gives the clothes back. View only; the appearance is untouched.
func _wear_undersuit(style: Dictionary) -> void:
	var on := not style.is_empty()
	var outfit: String = SUIT_OUTFITS.get(_appearance.get("build", ""), "")
	if _skeleton != null and outfit != "":
		for node in _skeleton.get_children():
			var part := node as MeshInstance3D
			var slot: String = part.get_meta("slot", "") if part else ""
			if not slot in ["body", "legs", "feet"]:
				continue
			if on and not _street.has(slot) and _appearance.get(slot, "") != outfit:
				_suit_part(part, slot, outfit)
			elif not on and _street.has(slot):
				_give_back(part, slot)
	for mat in _materials:
		mat.set_shader_parameter("suit", 1.0 if on else 0.0)
		if on:
			mat.set_shader_parameter("suit_color", style["suit"])
			mat.set_shader_parameter("suit_trim", style["accent"])


## Puts `outfit`'s `slot` part on in place of `part`'s, keeping the clothes
## to give back, its cloth worn as undersuit.
func _suit_part(part: MeshInstance3D, slot: String, outfit: String) -> void:
	var donor: Node3D = look._instance(Human.outfit_path(_appearance["build"], outfit))
	if donor == null:
		return
	var source := donor.find_child(Human.SLOT_NODES[slot], true, false) as MeshInstance3D
	if source != null:
		var mats := []
		for i in part.mesh.get_surface_count():
			mats.append(part.get_surface_override_material(i))
		_street[slot] = {"mesh": part.mesh, "skin": part.skin, "mats": mats}
		_drop_materials(part)
		part.mesh = Human.shaped(source.mesh, source.skin) if Human.reshape else source.mesh
		part.skin = source.skin
		for i in part.mesh.get_surface_count():
			part.set_surface_override_material(i, null)
		for mat in look.dress_surfaces(part, _def, _appearance):
			if int(mat.get_shader_parameter("surface_kind")) == 0:
				mat.set_shader_parameter("surface_kind", 2)
			_materials.append(mat)
	donor.free()


## Lets go of `part`'s materials from the body's list.
func _drop_materials(part: MeshInstance3D) -> void:
	for i in part.get_surface_override_material_count():
		var mat := part.get_surface_override_material(i)
		if mat is ShaderMaterial:
			_materials.erase(mat)


## A frame's carrier and plates, front toward -Z, built round the chest
## bone (`armor_model.gd`): its weight sets the bulk and coverage, its look
## (`FRAME_STYLES`, in its armor paint, `frame_style`) the colours and the
## details. `id` is a frame's item id, a weight or "skin:<weight>". One mesh per material; the named plates are
## in its "parts" meta (`GearShapes.has_part`).
static func build_frame(id: String, paint := "") -> Node3D:
	return _armor("torso", id, 0.0, paint)


## The frame's battle belt, built round the hips bone.
static func build_belt(id: String, paint := "") -> Node3D:
	return _armor("belt", id, 0.0, paint)


## A shoulder pad for the side `out` (-1 left, 1 right): a dome over the
## shoulder and `FRAME_BULK` "pads" lames down the arm, built standing up
## the upper arm from the shoulder joint.
static func build_pad(id: String, out: float, paint := "") -> Node3D:
	return _armor("pauldron", id, out, paint)


## An elbow pad and bracer for the side `out`, built down the forearm.
static func build_bracer(id: String, out: float, paint := "") -> Node3D:
	return _armor("forearm", id, out, paint)


## A thigh plate (tassets) for the side `out`, built down the thigh from
## the hip; the right one carries a drop-leg pouch.
static func build_tasset(id: String, out: float, paint := "") -> Node3D:
	return _armor("thigh", id, out, paint)


## A knee pad and shin guard (a greave on heavy), built down the shin.
static func build_shin(id: String, out: float, paint := "") -> Node3D:
	return _armor("shin", id, out, paint)


## A frame's `piece` ("torso", "belt", "pauldron", "forearm", "thigh",
## "shin") for the side `out`, built once per weight, look and side and
## shared after (`GearShapes.cached`). `paint` is an armor paint
## (`ArmorPaint`) or "" for the look's own colours.
static func _armor(piece: String, id: String, out := 0.0, paint := "") -> Node3D:
	var weight := frame_weight(id)
	if not ArmorPaint.PAINTS.has(paint):
		paint = ""
	var style := frame_style(id, paint)
	return ArmorModel.G.cached("%s:%s:%s:%s:%s" % [piece, weight, frame_look(id), out, paint], func() -> Node3D:
		match piece:
			"torso":
				return ArmorModel.torso(weight, style)
			"belt":
				return ArmorModel.belt(weight, style)
			"pauldron":
				return ArmorModel.pauldron(weight, style, out)
			"forearm":
				return ArmorModel.forearm(weight, style, out)
			"thigh":
				return ArmorModel.thigh(weight, style, out)
		return ArmorModel.shin(weight, style, out))


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
	var worn := actor.visor.working() and not actor.is_dead
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
## In a cold world (`WorldDef.cold`) breath shows: a small puff of fog out
## of the mouth, quicker when shivering or short of stamina. Everyone sees
## it, first person included (it drifts out ahead of the eyes), but never
## from a cloaked or dead body.
func _update_breath(delta: float) -> void:
	_breath_in -= delta
	if _breath_in > 0.0:
		return
	var hard := actor.shivering or actor.stamina < actor.max_stamina * 0.5
	_breath_in = (breath_hard_every if hard else breath_every) * randf_range(0.85, 1.15)
	# Asked once a breath, not once: a body is dressed before it has a raid.
	if not Hud.feels_cold(actor) or actor.is_dead or actor.is_cloaked() or _skeleton == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(global_position) > breath_range:
		return
	var look := Basis.from_euler(Vector3(actor.cmd.pitch, actor.cmd.yaw, 0.0))
	var eyes: Variant = eye_point(look)
	if eyes == null:
		return
	if _breath == null:
		_breath = _breath_puffs()
		_breath.set_meta("uncloaked", true)
		add_child(_breath)
	var ahead := look * Vector3.FORWARD
	_breath.global_position = (eyes as Vector3) + Vector3.DOWN * 0.1 + ahead * 0.12
	_breath.direction = (ahead + Vector3.DOWN * 0.3).normalized()
	_breath.restart()


## The fog of one breath: a few soft puffs out of the mouth that spread and
## fade within a second and a half.
static func _breath_puffs() -> CPUParticles3D:
	var puffs := CPUParticles3D.new()
	puffs.name = "Breath"
	puffs.one_shot = true
	puffs.emitting = false
	puffs.amount = 6
	puffs.lifetime = 1.4
	puffs.explosiveness = 0.7
	puffs.local_coords = false
	puffs.spread = 18.0
	puffs.gravity = Vector3(0.0, 0.15, 0.0)
	puffs.initial_velocity_min = 0.35
	puffs.initial_velocity_max = 0.7
	puffs.damping_min = 0.3
	puffs.damping_max = 0.5
	puffs.scale_amount_min = 0.5
	puffs.scale_amount_max = 0.8
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	puffs.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(0.92, 0.95, 1.0, 0.4))
	puffs.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = ramp
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 32
	dot.height = 32
	mat.albedo_texture = dot
	quad.material = mat
	puffs.mesh = quad
	puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return puffs


func _update_cloak() -> void:
	var on := actor.is_cloaked() and not actor.is_dead
	if not on and not _cloaked:
		return
	_cloaked = on
	for node in actor.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		# An airborne sign-out's beacon stays solid: a cloak never hides it.
		if geometry.has_meta("uncloaked"):
			continue
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
## A charging rail's whine and a rotary gun's barrels spinning, heard by
## everyone near, from the gun's own state (simulated from the command, so a
## remote player's charge is heard too). One player each, made on first use.
var _hum: AudioStreamPlayer3D
var _hum_sound := ""


func _update_weapon_hum() -> void:
	var gun := actor.get_active_weapon() as Gun
	var want := ""
	var level := 0.0
	if gun != null and not actor.is_dead:
		if gun.charge_time > 0.0 and gun.charge_fraction() > 0.0:
			want = "rail_charge"
			level = 1.0
		elif gun.spin_fraction() > 0.0:
			want = "storm_spin"
			level = gun.spin_fraction()
	if want != _hum_sound:
		_hum_sound = want
		if _hum != null:
			_hum.stop()
		var stream := Sfx.get_stream(want) if want != "" else null
		if stream != null:
			if _hum == null:
				_hum = AudioStreamPlayer3D.new()
				_hum.name = "WeaponHum"
				_hum.position = Vector3(0.0, 1.3, 0.0)
				_hum.max_distance = 60.0
				add_child(_hum)
			_hum.stream = stream
			_hum.pitch_scale = 1.0
			_hum.play()
	if _hum != null and want == "storm_spin":
		# The whirr climbs with the barrels.
		_hum.pitch_scale = 0.5 + 0.6 * level
		_hum.volume_db = linear_to_db(0.2 + 0.8 * level) - 4.0
	elif _hum != null:
		_hum.volume_db = -2.0


func _update_materialize() -> void:
	var weapon := actor.get_active_weapon()
	# Stored back through the watch, it runs the other way: the solid model
	# breaks up into the same light and fades out of the hand.
	var storing := actor.storing_weapon()
	var fading := storing != null and storing == weapon
	var model: Node3D = weapon.visual if weapon != null and (actor.materialize_left > 0.0 or fading) \
			and weapon.visual != null and is_instance_valid(weapon.visual) else null
	if model != null and model != _materializing:
		# The watch's sound as it starts, heard by everyone near: up out of
		# the watch, or back down into it.
		Sfx.play("store" if fading else "summon", actor.global_position, -4.0)
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
	# Looked over (the inspect key), it turns with the wrist.
	var facing := actor.global_basis.orthonormalized()
	if pose.inspecting() == "hand":
		facing = facing * pose.inspect_basis()
	var turn := actor.hand.global_basis.orthonormalized().inverse() * facing
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
			# Flaring for a landing, the wings tip up to brake.
			var trim := lerpf(actor.glide_trim(), -1.0, smoothstep(0.0, 1.0, _flare))
			RigModel.set_wing_spread(_rig_back, _spread, clampf(-_bank / max_bank, -1.0, 1.0), trim)


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
	var flare := 0.0
	if alive and actor.flight.is_gliding and actor.velocity.y < 0.0:
		flare = 1.0 - smoothstep(flare_full, flare_height, actor.height_above_ground(flare_height + 0.5))
	elif not actor.flight.is_gliding and _glide > 0.0 and actor.is_on_floor():
		# Touched down: stay flared while the glide pose lets go.
		flare = _flare
	_flare = move_toward(_flare, flare, flare_rate * delta)

	var local := actor.global_basis.inverse() * actor.velocity
	var level := Vector3(local.x, 0.0, local.z)
	var speed := level.length()
	var dir := level / speed if speed > 0.5 else Vector3.FORWARD
	var tilt := Vector3.ZERO
	var face := 0.0
	var bank := 0.0
	if flat:
		var path := atan2(actor.velocity.y, maxf(speed, 0.5)) if actor.velocity.length() > 1.0 else 0.0
		var lie := lerpf(glide_pitch, flare_pitch, smoothstep(0.0, 1.0, _flare))
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
	# A passenger's pose is fitted to the pillion seat, the rider's to the vehicle.
	locomotion.ride = vehicle.call("ride_anchor", actor) if vehicle != null else null
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
	var w := smoothstep(0.0, 1.0, _limb_glide())

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


## How far the arms and legs are in the flat flying pose: a flare for the
## landing gives them back to the air pose, legs down under the body.
func _limb_glide() -> float:
	return _glide * (1.0 - 0.85 * smoothstep(0.0, 1.0, _flare))


## Bends the legs into the air pose. The flat flying pose, applied after,
## takes over as the body lies out.
func _pose_air() -> void:
	var w := smoothstep(0.0, 1.0, _air) * (1.0 - smoothstep(0.0, 1.0, _limb_glide()))
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
	_mark_storm()


## Hangs a rig part on a bone so it moves with the body (see `_hang`).
func _wear_part(part: Node3D, bone_name: String, offset: Vector3, fallback: Vector3) -> void:
	look._weather_model(part, 0.5, 0.6)
	_rig_holders.append(_hang(part, "Rig" + part.name, bone_name, offset, fallback))


## Hangs a part on a bone so it moves with the body, and returns the node to
## free to take it off. Parts are built in meters for a wearer facing the
## actor's way; this undoes the model's scale and turn so they come out that
## way. `offset` is from the bone, in the actor's frame. Skins without the
## bone get the part at `fallback` (actor frame), fixed to the body.
func _hang(part: Node3D, holder_name: String, bone_name: String, offset: Vector3, fallback: Vector3,
		merge := false) -> Node3D:
	if merge:
		# Plates, a helmet and armor parts are built from many still pieces:
		# drawn as one mesh per material they cost a few draws, not dozens.
		look.merge_pieces(part)
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


## A soldier who brings a gun up after a quiet spell calls it out: the tell
## that comes before its first shot (`BotBrain` raises the aim halfway
## through its reaction). Read from the command, so every view hears it;
## only bots (they carry a "zone") bark. View only.
func _update_bark(delta: float) -> void:
	if not actor.has_meta("zone") or actor.is_dead:
		return
	if not actor.cmd.secondary:
		_calm_for += delta
		return
	if _calm_for >= bark_calm and actor.get_active_weapon() is Gun:
		Sfx.play("alert", actor.get_eye_position(), -2.0, 45.0)
	_calm_for = 0.0
