extends Node3D
## The model an actor wears. Added by `Look` as a child of the Actor; the
## Actor itself never knows about it. It reads the actor's state each frame
## and plays the matching animation, swaps greybox weapon parts for models,
## and plays the effects for shots and hits.

const GameSettings := preload("res://core/settings/game_settings.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const Vfx := preload("res://core/visual/vfx.gd")
const WeaponArm := preload("res://core/visual/weapon_arm.gd")
const RigModel := preload("res://core/visual/rig_model.gd")
const HelmetModel := preload("res://core/visual/helmet_model.gd")
const ArmorModel := preload("res://core/visual/armor_model.gd")
const WornFit := preload("res://core/visual/worn_fit.gd")
const BodyFit := preload("res://core/visual/body_fit.gd")
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
## Stands whose own legs are swapped for the relaxed stand's
## (`Locomotion.stand_legs`): the old gun and sword clips stand wide and
## bow-legged on the new bodies (Caleb: hunched and splay-legged). The
## blade's ready stance is then the fighting pose's own stagger. A gun
## raised to shoot keeps its clip's stance, which the sights are tuned on.
const LEGS_FROM_STAND: Array[String] = ["idle_gun", "idle_melee"]

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
## A knockdown (`_show_knocked_down`): the most the fall to the ground and
## the rise back up at the end take, in seconds (a short knockdown splits its
## time between them), and how far into the death clip a body with no fall
## and rise of its own goes down. `knock_rise_from` and `knock_rise_to` are
## the part of the rise clip played: where the lying starts to move and where
## the stand is reached.
var knock_fall_time := 0.6
var knock_rise_time := 0.7
var knock_depth := 1.0
var knock_rise_from := 0.15
var knock_rise_to := 1.35

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
## thrusting): legs nearly straight under the body, toes pointed, the
## second leg trailing a little behind the first.
var air_grace := 0.12
var air_blend := 6.0
var air_toes := 0.9
var leap_legs := [Vector3(0.05, -1.0, -0.75), Vector3(0.0, -1.0, 0.7), Vector3(0.05, -1.0, 0.3), Vector3(0.0, -1.0, 0.55)]
var fall_legs := [Vector3(0.22, -1.0, -0.45), Vector3(0.0, -1.0, 0.5), Vector3(0.2, -1.0, -0.15), Vector3(0.0, -1.0, 0.6)]
var hang_legs := [Vector3(0.05, -1.0, -0.04), Vector3(0.0, -1.0, 0.16), Vector3(0.05, -1.0, 0.14), Vector3(0.0, -1.0, 0.34)]
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
## Touching down out of a glide (or a boost) at speed is a run-out, not a
## crash: the body leans back against the skid by up to `run_out_lean`
## radians while it is still going faster than `run_out_speed` m/s, and the
## squat is kept to `run_out_squat` so it never folds up flat on the ground.
## The skid lasts at most `run_out_time` seconds, and ends at once when the
## player runs on (moving with the stick at running speed or slower), so
## the legs never freeze in it while the body runs.
var run_out_lean := 0.3
var run_out_speed := 7.0
var run_out_time := 0.9
var run_out_squat := 0.4
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
## How fast the body goes in and out of a boost's prone pose (a share a
## second, eased at both ends): out of a boost into a hover it rises from
## flat to the hover's lean over about half a second, never in a snap.
var boost_ease := 2.2
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
## Skating (the boots' cruise, `FlightRig.is_skating`): a skater's stance,
## not the flying pose. The body leans `skate_lean` radians into the way it
## goes and into a turn as a skater carves (up to `skate_bank` radians, read
## from how fast the heading swings, so remote players match), the lead leg
## reaches ahead with its knee bent and the other trails (`skate_legs`:
## thigh and shin of each, body frame as `leap_legs`), and the arms stay on
## the gun. The heel flames fire down under the feet.
var skate_lean := 0.42
var skate_bank := 0.55
var skate_legs: Array[Vector3] = [Vector3(0.1, -0.88, -0.42), Vector3(0.04, -0.9, 0.3),
		Vector3(0.12, -0.86, 0.48), Vector3(0.06, -0.72, 0.68)]
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
## The style pass (Caleb's call: each rig flies its own way). All view only,
## read from the simulated actor, so remote players match and both views
## show the same body.
## Jetpack, a heavy gunship: the flames stretch with the throttle (from
## `jet_flame_min` to `jet_flame_max` of their length, flickering by
## `jet_flicker`) and the nozzles swivel up to `jet_gimbal` radians to push
## the way the pack is working. Hovering, the body tips into that push like
## a helicopter, by up to `hover_lean`: into a drift as it sets off, back as
## it stops (a steady drift pushes `jet_drag` per m/s against the air). A
## boost lighting kicks the flames to `jet_kick` times for `jet_kick_time`.
var jet_flame_min := 0.55
var jet_flame_max := 1.7
var jet_flicker := 0.08
var jet_gimbal := 0.35
var jet_drag := 0.45
var jet_kick := 1.6
var jet_kick_time := 0.3
## Wings, a bird of prey: past the glide's speed the arms tuck in
## (`dive_arm`, full at the dive's top speed) and the wings sweep back;
## loaded in a hard turn or a pull the tips bend up; stalled, the wings
## shudder by `stall_shudder` radians and the arms reach out for balance
## (`stall_arm`). Same frame as `glide_arm`.
var dive_arm := Vector3(0.14, -1.0, 0.08)
var stall_arm := Vector3(0.9, -0.55, 0.05)
var stall_shudder := 0.07
## Wingtip vapor: a thin streak off each tip that fades over `vapor_life`
## seconds and is never longer than `vapor_length` m, drawn while the glide
## is faster than `vapor_speed` m/s or pulling more than `vapor_g`; never on
## the Low and Lowest graphics. It tapers to nothing at its tail, and fades
## out within `vapor_clear` m of the camera so a chase view behind the
## flyer sees wisps, not bars running past the lens.
var vapor_speed := 26.0
var vapor_g := 1.5
var vapor_life := 0.6
var vapor_length := 6.0
var vapor_width := 0.03
var vapor_alpha := 0.35
var vapor_clear := 4.0
## Boots, a skater and free-runner: the skate pumps in strides
## (`skate_stride` strides a second at the skate's speed, each leg pushing
## out and back by `skate_push`), a kick while skating spins the body once
## round over `kick_spin_time` seconds (not while aiming), and an air dash
## pulls the knees up into a tuck (`dash_tuck` radians).
var skate_stride := 1.3
var skate_push := 0.35
var kick_spin_time := 0.5
var dash_tuck := 0.7
## Secondary motion in flight (Caleb's ask: the body moves with every turn
## and change of speed, never holding one stiff pose). The limbs carry on a
## little as the body speeds up, slows, climbs or turns: the pull is the
## acceleration turned round, in g, on a spring a little bouncy so the limbs
## settle with some life (`sway_stiffness`, `sway_damping`). The arms swing
## `sway_arms` of it and the legs `sway_legs` (the shins half as much
## again); while the arms are free of a weapon the chest leads a turn by up
## to `sway_twist` radians (full at `sway_turn_full` radians a second) and
## sits back or forward against a change of speed by `sway_pitch` a g. View
## only, read from velocity, so remote players match.
var sway_stiffness := 60.0
var sway_damping := 11.0
var sway_arms := 0.5
var sway_legs := 0.4
var sway_twist := 0.3
var sway_turn_full := 2.0
var sway_pitch := 0.12
## The flyer leads the rig (Caleb's ask: the pilot steers, the rig answers,
## not the other way round). What the player asks for (the stick, a climb or
## a descent, the view swinging round, and in a glide the view against the
## way it flies and the trim) is read from `Actor.cmd`, which remote players
## have too, and eased in quickly (`lead_rate`, faster than the body's own
## attitude follows the velocity), so the body moves first and the flight
## answers. The body leans into the stick (`lead_lean`) and banks into a
## turn in a glide (`lead_bank`, radians); the head looks into the turn
## (`lead_head`) and the climb (`lead_head_pitch`); the chest turns
## (`lead_twist`), bends (`lead_roll`) and leans with the stick or the trim
## (`lead_crunch`); the arms drop on the inside of a turn and lift outside
## (`lead_arm_roll`), reach where the stick points and press down to climb
## (`lead_reach`), and sweep back for a dive or forward to pull up
## (`lead_sweep`); the hands tip like ailerons into the turn (`lead_hand`)
## and flex with the climb (`lead_hand_flex`); the legs swing the other way
## to balance (`lead_legs`). A glide turns `lead_turn_angle` radians of
## view off the flight path into a full turn, anything else
## `lead_turn_rate` radians a second of view turning. Arms and chest only
## while they are free of a weapon being aimed, and only `lead_armed` of
## the arms' lead with one in hand. View only.
var lead_rate := 14.0
var lead_armed := 0.4
var lead_lean := 0.16
var lead_bank := 0.3
var lead_head := 0.45
var lead_head_pitch := 0.25
var lead_twist := 0.3
var lead_roll := 0.14
var lead_crunch := 0.2
var lead_arm_roll := 0.45
var lead_reach := 0.5
var lead_sweep := 0.4
var lead_hand := 0.5
var lead_hand_flex := 0.35
var lead_legs := 0.2
var lead_turn_angle := 0.6
var lead_turn_rate := 2.5

## Riding, the head turns at most this far (radians) toward the aim; the
## body stays facing along the vehicle.
var ride_head_turn := 1.1
## Where the wrist sits behind the resting hand spot when a rider holds a gun
## out, in the actor's frame along the aim.
var ride_gun_wrist := Vector3(0.0, -0.02, 0.1)
## Stopped on a bike (slower than this, m/s) the rider puts the left foot
## down, eased in and out at this rate a second.
var foot_down_speed := 0.6
var foot_down_rate := 3.0
## Riding, a weapon slung on the back rides this much higher up the back, so
## its lower end clears the seat and the bike's tail.
var ride_sling_lift := 0.28

## Holstered weapons are worn on the body instead of vanishing: a gun is
## slung across the back, muzzle up over the right shoulder, and over the
## outside of a back rig (a jetpack or wings) when one is worn. A two-handed
## melee weapon crosses the back the other way; a one-handed blade hangs from
## the left hip, and then the gun leans over the left shoulder instead, its
## stock down by the right hip, clear of the blade and behind the holster. Distances in meters, in the actor's frame (x right, y up, z back).
var sling_tilt := deg_to_rad(35.0)
var sling_height := -0.2
## Where the back is behind the back bone with nothing worn, and how far the
## middle of a slung weapon sits out from the back or the rig's outer face:
## where it starts from, before `_fit_worn` moves it snug over whatever is
## really worn there (as it does every holster, the rig and a backpack).
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
var helmet_size := Vector3(0.215, 0.258, 0.258)
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
## The lamp on a worn helmet (`Actor.lamp_lit`, its own key): a small barrel
## on the right of the brow, `lamp_at` from the helmet's middle (its frame,
## front toward -Z), on the one model, so it rides to the hip with it. Lit,
## its lens glows and a beam shines from it along the aim: `lamp_range`
## metres, `lamp_angle` degrees out from its middle, fading out for viewers
## past `lamp_fade` metres. One model in every view; first person leaves the
## barrel out with the head, never the beam.
var lamp_at := Vector3(0.138, 0.05, -0.06)
var lamp_color := Color(1.0, 0.95, 0.84)
var lamp_energy := 4.0
var lamp_range := 30.0
var lamp_angle := 22.0
var lamp_fade := 60.0
## A worn armor frame is plates over the chest (on the "Chest" bone, front
## toward -Z), and from medium up a belly plate and shoulder pads (on the
## upper arm bones); heavy adds a collar. One model in every view.
var frame_offset := Vector3(0.0, 0.0, 0.0)
## How much `Look` sized the body from its own model (`Look.stand_model`):
## armor is fitted in the model's metres (`body_fit.gd`) and scaled by it.
var _body_scale := 1.0
var pad_offset := Vector3(0.0, 0.0, 0.0)
## Where a worn backpack sits from the hips: up onto the lower back and
## against it (+Z is behind). Under a back rig it rides lower and further
## out by `pack_rig_shift`, so the two never sink into each other.
var pack_offset := Vector3(0.0, 0.14, 0.06)
var pack_rig_shift := Vector3(0.0, -0.08, 0.08)
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
## The backpack worn on the lower back (`_update_pack`), and the key it was
## built for ("" for none).
var _pack_part: Node3D
var _pack_key := ""
## The frame `_frame_parts` were built for; "" for none.
var _frame_id := ""
## The person this body is dressed as (empty for a skin that is not a person).
var _appearance := {}
## The helmet `_helmet` was built for; "" while bare-headed.
var _helmet_id := ""
## The helmet lamp's lens (on the model, its own material to light) and its
## beam, kept apart from the skeleton so first person never leaves it out.
var _lamp_lens: MeshInstance3D
var _lamp_beam: SpotLight3D
var _lamp_shown := false
## A walker's tracking beam (`_update_beam`) and how long it has held its aim.
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _beam_held := 0.0
var _flames: Array[Node3D] = []
var _burst_left := 0.0
## Jetpack: the push the jets make (actor space, m/s²) and the throttle, in
## g; how long a boost's kick has left, and whether it boosted last frame.
var _jet_push := Vector3(0, 9.8, 0)
var _jet_throttle := 1.0
var _jet_kick_left := 0.0
var _was_boosting := false
## Wings: how far past the glide's speed (0..1), how stalled (0..1) and how
## loaded (0..1) the glide is, and the wingtip vapor (`_Vapor`).
var _wing_fast := 0.0
var _wing_stall := 0.0
var _wing_load := 0.0
var _vapor: _Vapor
## The worn rig's voice, heard by everyone near (`_update_rig_voice`), and
## whether an air dash was running last frame (a boots' dash pops).
var _rig_voice: AudioStreamPlayer3D
var _was_dashing := false
## Boots: the skate's stride (radians round), a kick's spin left (s) and its
## way round, and how far into a dash's tuck the legs are.
var _stride := 0.0
var _spin_left := 0.0
var _spin_dir := 1.0
var _tuck := 0.0
## Secondary motion (`sway_stiffness`): the limbs' pull, actor frame, in g,
## and how fast it is moving; how fast the way the body flies is swinging
## (radians a second, positive turning left); the spine's bones.
var _sway := Vector3.ZERO
var _sway_v := Vector3.ZERO
var _turn_rate := 0.0
## The pilot's intent (`lead_rate`): how hard a turn is asked for (-1..1,
## positive left), the reach (heading frame: the stick's way level, up for a
## climb or a pull), and how far the lead is on at all.
var _lead_turn := 0.0
var _lead_reach := Vector3.ZERO
var _lead_w := 0.0
var _sway_heading := NAN
var _spine_bones: Array[int] = []
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
## Skating: the heading last frame, and the carve's lean now.
var _skate_heading := NAN
var _run_out := false
var _run_out_left := 0.0
var _skate_carve := 0.0
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
## and what they were placed for: the rig, and `_stow_flags`.
var _stowed := {}
var _stowed_rig := ""
var _stowed_flags := 0
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
	var built: Dictionary = look.character(skin_name, actor.get_meta("appearance", {}), String(actor.name),
			actor.get_meta("uniform", {}))
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
				if key not in ["death", "attack", "roll", "kick", "fist", "knock_fall", "knock_rise"]:
					_player.get_animation(found).loop_mode = Animation.LOOP_LINEAR
		# Sized in the relaxed stand: an idle that bends the knees or
		# spreads the feet (a person's) would otherwise size the body up.
		var sized_in := "stand_legs" if _anims.has("stand_legs") else "idle"
		if _anims.has(sized_in):
			_player.play(_anims[sized_in])
			_player.advance(0.0)
		_play("idle")
	look.stand_model(self, model, def["height"])
	_body_scale = model.scale.y
	if _player:
		_player.advance(0.0)
	_def = def
	_lurk_model = model
	_lurk_base = model.position.y
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton = skeleton
	if def.get("chassis", "") == "walker":
		_build_walker()
	if def.get("creature", "") != "":
		_build_creature(str(def["creature"]))
	if def.get("suit", false):
		_build_exo_suit()
	if def.get("chassis", "") == "android":
		_build_android(def.get("heavy_chassis", false))
	if def.get("regalia", "") != "":
		_build_regalia(str(def["regalia"]))
	if def.get("gear", "") != "":
		_build_gear(str(def["gear"]))
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
		var fist: String = _anims.get("fist", _anims.get("idle_melee", ""))
		arm.setup(def, _player.get_animation(fist) if _player and fist != "" else null)
		_teach_arm.call_deferred()
		if _player:
			arm.calibrate(_player.get_animation(_anims["aim_gun"]) if _anims.has("aim_gun") else null,
					_player.get_animation(_anims["idle_melee"]) if _anims.has("idle_melee") else null)
		# After the arm has put the hand on the model's hand.
		skeleton.skeleton_updated.connect(_carry_moving)
	if skeleton:
		# Last, so the phone has the right hand whatever the arm was doing.
		locomotion.add_phone_hook()
		# The emote's arms after it, so a wave takes the hand it needs.
		locomotion.add_emote_hook()
	if skeleton and def.get("chassis", "") == "android":
		# The gun arm comes up along the aim, after the clip and the legs.
		var aim := WeaponArm.Hook.new()
		aim.name = "ArmAim"
		aim.run = _aim_arm
		skeleton.add_child(aim)
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


## Knocked off the feet (`Actor.knock_down`). A body with its own clips
## (`knock_fall`, `knock_rise`: a person's) is thrown back onto the ground,
## lies there and pushes itself up, the fall and the rise sped to fit the
## knockdown. Any other body plays the death clip's fall, holds it and plays
## it back up. Timed by what is left of the knockdown, so every view shows
## the same moment.
func _show_knocked_down() -> void:
	var total := maxf(actor.knocked_time, 0.01)
	var since := total - actor.knocked_left
	if _anims.has("knock_fall") and _anims.has("knock_rise"):
		var rise := minf(knock_rise_time, total * 0.5)
		var fall := minf(knock_fall_time, total - rise)
		if actor.knocked_left > rise:
			# Played at the speed it runs, not held still: a still player
			# never finishes the blend in from the stand.
			var length := _player.get_animation(_anims["knock_fall"]).length
			_play("knock_fall", length / maxf(fall, 0.01))
			_player.seek(length * clampf(since / maxf(fall, 0.01), 0.0, 1.0), true)
		else:
			var length := _player.get_animation(_anims["knock_rise"]).length
			var to := minf(knock_rise_to, length)
			var from := minf(knock_rise_from, to)
			var t := 1.0 - clampf(actor.knocked_left / maxf(rise, 0.01), 0.0, 1.0)
			_play("knock_rise", (to - from) / maxf(rise, 0.01))
			_player.seek(from + (to - from) * t, true)
		return
	_play("death", 0.0)
	var length := _player.current_animation_length
	var t := minf(clampf(since / maxf(knock_fall_time, 0.01), 0.0, 1.0),
			clampf(actor.knocked_left / maxf(knock_rise_time, 0.01), 0.0, 1.0))
	_player.seek(length * knock_depth * (1.0 - (1.0 - t) * (1.0 - t)), true)


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
	# A body whose gun holds a lock before it fires shows the beam it holds.
	if _def.get("beam", false) or float(actor.get_meta("lock_time", 0.0)) > 0.0:
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
	if _pack_part != null and is_instance_valid(_pack_part):
		holders.append(_pack_part)
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
	_update_sway(delta)
	_update_rig(delta)
	_update_glide(delta)
	_update_stowed()
	_update_switch(delta)
	_update_helmet()
	_update_lamp()
	_update_shadow_body()
	_update_frame()
	_update_pack()
	_fit_worn()
	_update_vitals()
	_update_phone()
	_update_watch_glow(delta)
	_update_cloak()
	_update_breath(delta)
	_update_materialize()
	_update_weapon_hum()
	_update_toy(delta)
	_update_bark(delta)
	_update_lurk(delta)
	_aim_left = maxf(_aim_left - delta, 0.0)
	var weapon := actor.get_active_weapon()
	if phone_up() or toy_up():
		# Hands on the phone or a toy: stand as if empty-handed.
		weapon = null
	var melee := weapon as MeleeWeapon
	if weapon is Gun:
		_hold_up(actor.cmd.primary, actor.cmd.secondary)
	if not _android_parts.is_empty():
		_update_arm_weapon()
		var raised := weapon is Gun and not actor.is_dead and (_aim_left > 0.0 or actor.cmd.secondary)
		_arm_raise = move_toward(_arm_raise, 1.0 if raised else 0.0, arm_raise_rate * delta)
	if locomotion == null:
		return
	_update_ride()
	locomotion.update(delta)
	locomotion.twist_target = 0.0
	locomotion.stride_target = 1.0
	locomotion.overlay = false
	locomotion.stand_legs = false
	locomotion.stand_legs_hips = true
	locomotion.air_legs = false
	ActionPose.of(actor).carry_wanted = false
	if actor.is_dead:
		_play("death")
		return
	if actor.knocked_left > 0.0 and _anims.has("death"):
		_show_knocked_down()
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
		# The swing's clip is the old body's, its legs set wide: a blade
		# swings over the relaxed stand's legs, and its footwork and stance
		# (`Locomotion._fight_pose`) step them. The kick keeps its own legs.
		if _current == "attack":
			locomotion.stand_legs = true
			locomotion.stand_legs_hips = false
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
		# Under the glide pose, the square stand: the pack's idle leans and
		# turns the chest, which would tip the wings hung on it.
		_play("stand_legs" if _anims.has("stand_legs") else "idle")
	elif airborne:
		# No ground under the feet: never a run cycle. A stand plays under
		# the air pose, so the arms keep their hold on the weapon.
		_play("idle_melee" if melee and _anims.has("idle_melee") else stand_key(weapon))
		locomotion.stand_legs = _current in LEGS_FROM_STAND
		locomotion.air_legs = true
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
		locomotion.stand_legs = true
		locomotion.stand_legs_hips = false
	else:
		_play(stand_key(weapon))
		locomotion.stand_legs = _current in LEGS_FROM_STAND
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
	pace *= actor.carry_speed
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
	var face := Vector3.UP * eye_up + look * Vector3(0.0, 0.0, -eye_ahead)
	# Down on a long gun's stock in the sights (`WeaponArm.cheek_eye`).
	if arm != null and arm.cheek_eye != Vector3.ZERO:
		face += actor.global_basis.orthonormalized() * arm.cheek_eye
	return head + face


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
## worn meanwhile and drawn again when the phone goes away. Riding too: the
## right hand leaves its grip for it and the left keeps the bar.
func phone_up() -> bool:
	return actor.cmd.phone and not actor.is_dead


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
	var flat := Vector2(actor.velocity.x, actor.velocity.z).length()
	_run_out = (_glide > 0.05 or _boost > 0.05) and flat > run_out_speed
	_run_out_left = run_out_time
	if _run_out:
		_land_depth = minf(_land_depth, run_out_squat)


## Eases the air pose in and out and between its shapes, and plays out the
## takeoff push and the landing squat.
func _update_air(delta: float, airborne: bool) -> void:
	_air = move_toward(_air, 1.0 if airborne else 0.0, air_blend * delta)
	if airborne and not _was_airborne:
		# Going up is a takeoff; walking off a ledge is not. It shows at
		# full on this pose and fades from the next, so a long frame (or a
		# body posed only every few frames) never swallows it.
		_air_push = 1.0 if actor.velocity.y > 1.0 else 0.0
		_land_left = 0.0
	else:
		_air_push = move_toward(_air_push, 0.0, delta / takeoff_time)
	_was_airborne = airborne
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
		# A machine's is built into its forearm (`Look.arm_weapon_model`).
		if _def.get("arm_weapons", false):
			for child in weapon.visual.get_children():
				if child is MeshInstance3D:
					child.visible = false
			weapon.visual.add_child(look.arm_weapon_model(weapon, float(_def.get("height", 2.2)) / 2.2))
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
	var flags := _stow_flags()
	if _stowed_rig != _rig_id or _stowed_flags != flags:
		_stowed_rig = _rig_id
		_stowed_flags = flags
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
			holder.transform = Transform3D(rest.basis, rest.origin + _fit_offset(holder) + (holder.get_meta("up") as Vector3) * lift)


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
	# A gun leans over the right shoulder, or the left when a blade hangs
	# on the left hip, where its stock would come down.
	var lean := sling_tilt if _hip_blade() else -sling_tilt
	return {"bone": back_bone, "at": out, "basis": Basis(Vector3.BACK, lean) * upright, "centre": true}


## Besides the rig, what the weapons put away were placed for: whether a
## backpack is worn (1) and whether a blade hangs on the hip (2). They are
## placed again when it changes.
func _stow_flags() -> int:
	return (1 if _wears_pack() else 0) | (2 if _hip_blade() else 0)


func _wears_pack() -> bool:
	return actor.pack_id != "" and ItemDB.has_item(actor.pack_id)


## Whether a one-handed blade is carried, so hangs on the left hip when
## put away.
func _hip_blade() -> bool:
	for w: Variant in actor.weapons:
		if is_instance_valid(w) and w is MeleeWeapon and not look.is_two_handed(w):
			return true
	return false


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
	# The frame (and its paint) is part of the key: a helmet wears its colours.
	if id != "" and actor.frame_id != "":
		id += "|" + actor.frame_id + "|" + frame_paint(actor.frame_id)
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
	_lamp_lens = null
	_lamp_shown = false
	_helmet_at = ""
	_show_head(id == "")
	if id == "":
		return
	var bone: String = "Head" if _skeleton and _skeleton.find_bone("Head") >= 0 else _def.get("neck", "")
	# A skin's own "scrap" helmet is the Junker's bucket (mode "").
	var mode := actor.visor.mode if own == "" else ("" if own == "scrap" else own)
	var glass := actor.visor.glass_color if own == "" else actor.body_color.lightened(0.2)
	var tier := actor.visor.tier if own == "" else 1
	var own_frame: String = _def.get("frame", "")
	var colors := helmet_colors(mode, actor.frame_id if own == "" else ("skin:" + own_frame if own_frame != "" else ""))
	_helmet = _hang(build_helmet(mode, glass, helmet_size, helmet_shell_color, tier, colors),
			"Helmet", bone, helmet_offset, Vector3(0.0, _def.get("height", 1.8) * 0.93, 0.0) + helmet_offset, true)
	_helmet_model = _helmet.find_child("HelmetModel", true, false) as Node3D
	if _helmet_model == null:
		_helmet_model = _helmet.get_child(0).get_child(0) as Node3D if _helmet is BoneAttachment3D \
				else _helmet.get_child(0) as Node3D
	_helmet_at = "head"
	if own == "":
		_lamp_lens = _build_lamp(_helmet_model)
		_lamp_shown = false
		# Somewhere to clip it and something to carry it in, made with it.
		var clip := Node3D.new()
		clip.name = "Clip"
		_helmet_clip = _hang(clip, "HelmetClip", _def.get("hip_bone", ""), helmet_clip,
				Vector3(0.0, _def.get("height", 1.8) * 0.5, 0.0) + helmet_clip)
		var holder := _held_part(_helmet_clip)
		holder.transform = holder.transform * Transform3D(Basis(Vector3.UP, helmet_clip_turn.x)
				* Basis(Vector3.BACK, -helmet_clip_turn.y), Vector3.ZERO)
		holder.set_meta("rest", holder.transform)
		_helmet_carry = Node3D.new()
		_helmet_carry.name = "HelmetCarry"
		add_child(_helmet_carry)
		_helmet_carry.top_level = true
		_place_helmet(true)
	if _detail_every > 1:
		_gear_shadows(false)


## Puts the lamp on a helmet `model` (`lamp_at`): a dark barrel, its front
## a lens that `_update_lamp` lights. Returns the lens. Added after the
## model's pieces are merged, as two pieces of its own.
func _build_lamp(model: Node3D) -> MeshInstance3D:
	var lamp := Node3D.new()
	lamp.name = "Lamp"
	lamp.position = lamp_at
	model.add_child(lamp)
	var barrel := CylinderMesh.new()
	barrel.radial_segments = 10
	barrel.rings = 1
	var housing := _piece(lamp, "Barrel", barrel, _solid(Color(0.13, 0.13, 0.14), 0.0), Vector3.ZERO,
			Vector3(0.03, 0.052, 0.03))
	housing.rotation.x = PI * 0.5
	# The beam starts at the lens: the lamp must not shade its own light.
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lens_mat := _solid(lamp_color, 0.0)
	lens_mat.emission_enabled = true
	lens_mat.emission = lamp_color
	lens_mat.emission_energy_multiplier = 0.0
	var lens := _piece(lamp, "Lens", barrel, lens_mat, Vector3(0.0, 0.0, -0.027), Vector3(0.024, 0.006, 0.024))
	lens.rotation.x = PI * 0.5
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lens


## Lights the helmet lamp while `Actor.lamp_lit` says so: the lens glows
## and the beam shines from it along the aim, so everyone sees where the
## wearer looks. Dark with the helmet off the head. View only.
func _update_lamp() -> void:
	var lit := actor.lamp_lit() and _lamp_lens != null and is_instance_valid(_lamp_lens)
	if lit != _lamp_shown:
		_lamp_shown = lit
		if _lamp_lens != null and is_instance_valid(_lamp_lens):
			((_lamp_lens.mesh as PrimitiveMesh).material as StandardMaterial3D).emission_energy_multiplier = 6.0 if lit else 0.0
	if not lit:
		if _lamp_beam != null:
			_lamp_beam.visible = false
		return
	if _lamp_beam == null:
		_lamp_beam = SpotLight3D.new()
		_lamp_beam.name = "LampBeam"
		_lamp_beam.top_level = true
		_lamp_beam.light_color = lamp_color
		_lamp_beam.light_energy = lamp_energy
		_lamp_beam.spot_range = lamp_range
		_lamp_beam.spot_angle = lamp_angle
		_lamp_beam.spot_attenuation = 0.8
		_lamp_beam.spot_angle_attenuation = 1.6
		_lamp_beam.shadow_enabled = true
		_lamp_beam.distance_fade_enabled = true
		_lamp_beam.distance_fade_begin = lamp_fade
		_lamp_beam.distance_fade_shadow = lamp_fade * 0.5
		_lamp_beam.distance_fade_length = 10.0
		add_child(_lamp_beam)
	_lamp_beam.visible = true
	var aim := actor.get_aim_dir()
	# Just ahead of the lens, clear of the helmet's own shell.
	var from := _lamp_lens.global_position + aim * 0.05
	var up := Vector3.UP if absf(aim.y) < 0.98 else Vector3.BACK
	_lamp_beam.global_transform = Transform3D(Basis.looking_at(aim, up), from)


## Shows the head's own meshes (the face, the hair), or hides them under a
## helmet.
func _show_head(on: bool) -> void:
	if _skeleton == null:
		return
	for node in _skeleton.get_children():
		if node is MeshInstance3D and node.get_meta("slot", "") == "head":
			(node as MeshInstance3D).visible = on


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
static func build_helmet(mode: String, glass: Color, size: Vector3, shell_color: Color, tier := 1,
		colors := {}) -> Node3D:
	var tint := ""
	for key: String in ["plate", "plate2", "fabric"]:
		if colors.has(key):
			tint += (colors[key] as Color).to_html()
	return HelmetModel.G.cached("helmet:%s:%s:%s:%s:%d:%s" % [mode, glass.to_html(), size, shell_color.to_html(), tier, tint],
			func() -> Node3D: return HelmetModel.build(mode, glass, size, shell_color, tier, colors))


## The colours a helmet of `mode` takes from the armor frame `frame_id`
## (in its paint), so helmet and plates read as one kit: its "plate",
## "plate2" and "fabric". {} with no frame, and always for the scrap visor
## (a patched pot of its own) and an exo's closed helm.
func helmet_colors(mode: String, frame_id: String) -> Dictionary:
	if frame_id == "" or mode == "" or mode == "slit" or not (frame_id.begins_with("skin:") or ItemDB.has_item(frame_id)):
		return {}
	var style := frame_style(frame_id, frame_paint(frame_id))
	var out := {}
	for key: String in ["plate", "plate2", "fabric"]:
		if style.get(key) is Color:
			out[key] = style[key]
	return out


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


## A backpack of `size` (1 a rucksack, 2 a hauler, 3 a mule frame; the
## item's "pack_size"), front toward -Z (against the back): a canvas bag
## with a lid, side pouches and compression straps, bigger each size, and
## the biggest lashed to a metal carrying frame. The same model is worn and
## hung up at home (`HomeBase`). Built from still boxes, so it merges to a
## few draws (`Look.merge_pieces`).
static func build_backpack(size: int, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "BackpackModel"
	size = clampi(size, 1, 3)
	var bag_size: Vector3 = [Vector3(0.3, 0.3, 0.15), Vector3(0.36, 0.42, 0.2), Vector3(0.4, 0.54, 0.24)][size - 1]
	var canvas := _solid(color, 0.0)
	canvas.metallic = 0.0
	canvas.roughness = 0.9
	var dark := _solid(color.darkened(0.45), 0.0)
	dark.metallic = 0.0
	dark.roughness = 0.9
	var metal := _solid(Color(0.32, 0.33, 0.35), 0.0)
	var box := BoxMesh.new()
	var mid := Vector3(0, 0, bag_size.z * 0.5)
	_piece(root, "Bag", box, canvas, mid, bag_size)
	_piece(root, "Lid", box, dark, mid + Vector3(0, bag_size.y * 0.5, 0.01),
			Vector3(bag_size.x * 0.96, 0.05, bag_size.z * 1.05))
	_piece(root, "Pocket", box, dark, Vector3(0, -bag_size.y * 0.15, bag_size.z + 0.03),
			Vector3(bag_size.x * 0.7, bag_size.y * 0.45, 0.06))
	for side: float in [-1.0, 1.0]:
		_piece(root, "Pouch", box, canvas,
				Vector3(side * (bag_size.x * 0.5 + 0.03), -bag_size.y * 0.1, bag_size.z * 0.5),
				Vector3(0.06, bag_size.y * 0.55, bag_size.z * 0.7))
		_piece(root, "Strap", box, dark, Vector3(side * bag_size.x * 0.28, 0, bag_size.z + 0.005),
				Vector3(0.035, bag_size.y * 1.02, 0.012))
	if size >= 2:
		# A bedroll strapped under the hauler and the mule.
		var roll := CylinderMesh.new()
		roll.top_radius = 0.5
		roll.bottom_radius = 0.5
		roll.height = 1.0
		var bedroll := _piece(root, "Bedroll", roll, dark, mid + Vector3(0, -bag_size.y * 0.5 - 0.05, 0.02),
				Vector3(0.1, bag_size.x * 1.05, 0.1))
		bedroll.rotation.z = PI / 2.0
	if size >= 3:
		# The mule's carrying frame: two rails up the back, a bar over the
		# top and a shelf under it.
		for side: float in [-1.0, 1.0]:
			_piece(root, "Rail", box, metal, Vector3(side * (bag_size.x * 0.5 + 0.07), 0.03, 0.03),
					Vector3(0.03, bag_size.y * 1.25, 0.03))
		_piece(root, "TopBar", box, metal, Vector3(0, bag_size.y * 0.66, 0.03),
				Vector3(bag_size.x + 0.17, 0.03, 0.03))
		_piece(root, "Shelf", box, metal, Vector3(0, -bag_size.y * 0.6, bag_size.z * 0.5),
				Vector3(bag_size.x + 0.17, 0.025, bag_size.z + 0.06))
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
## The lit parts of a beast of the ice: the cold's blue.
const FROST_GLOW := Color(0.45, 0.85, 1.0)
## The lit parts of the rift's lava beasts: the lava's own orange.
const LAVA_GLOW := Color(1.0, 0.42, 0.1)
## The lit eyes of a beast of the sand: a dim amber.
const DUNE_GLOW := Color(1.0, 0.72, 0.3)
## A shellback's soft rear: pale, fleshy hide lit faintly from inside.
const SOFT_REAR := Color(0.95, 0.66, 0.55)


## The walker's cannon, raised and lowered with the aim (view only).
var _cannon: Node3D
## A skin that "lurks" (metres, the marsh's lurkers) sinks that far while
## its body lies low (`Actor.crouch`, held by an ambusher's brain at its
## post), so it waits under the black water with only its lit eyes at the
## surface, and rises as it comes up to strike. View only.
var _lurk_model: Node3D
var _lurk_base := 0.0
var _lurk_sink := 0.0
const LURK_RATE := 2.5


func _update_lurk(delta: float) -> void:
	var depth := float(_def.get("lurks", 0.0))
	if depth <= 0.0 or _lurk_model == null:
		return
	var want := depth * actor.crouch if not actor.is_dead else 0.0
	_lurk_sink = move_toward(_lurk_sink, want, LURK_RATE * delta)
	_lurk_model.position.y = _lurk_base - _lurk_sink


## A marsh beast's own body (DESIGN.md "Spore Marsh"), built round the
## walking skeleton of the skin's scene, whose own mesh is hidden: "stalker",
## "shellback" or "bloater". Rounded shapes, unlike the machines' blocks,
## each hung on the bone it moves with so the walk clip drives it. Lit parts
## are the planet's own glow: eyes, gills, the shellback's soft rear and the
## bloater's pustules. View only.
func _build_creature(kind: String) -> void:
	if _skeleton == null:
		return
	var lit: float = CREATURE_FRECKLES.get(kind, 0.05)
	# A beast of the ice is dry fur, lit in the cold's blue.
	var frost := kind == "feral"
	# The rift's lava beasts are dry basalt lit in the lava's orange; a
	# beast of the sand is dry hide with amber eyes.
	var lava := kind in ["hound", "crawler"]
	var sand := kind == "burrower"
	var dry := frost or lava or sand
	var lit_color := FROST_GLOW if frost else (LAVA_GLOW if lava else (DUNE_GLOW if sand else CREATURE_GLOW))
	var hide := _creature_hide(actor.body_color, lit, 0.15 if dry else 0.6)
	var dark := _creature_hide(actor.body_color.darkened(0.45), lit * 0.5, 0.1 if dry else 0.4)
	for mat: ShaderMaterial in [hide, dark]:
		mat.set_shader_parameter("glow", lit_color)
	var bone := _solid(Color(0.78, 0.74, 0.62), 0.0)
	bone.metallic = 0.0
	var glow := _solid(lit_color, 2.6)
	# Egg sacs, gill fans and spore vents glow softly from inside, never as
	# bright as the eyes.
	var soft_glow := _solid(CREATURE_GLOW.lerp(Color(0.85, 0.95, 0.7), 0.4), 0.8)
	soft_glow.roughness = 0.35
	var fan := _creature_hide(actor.body_color.lerp(Color(0.55, 0.4, 0.5), 0.5), 0.5, 0.8)
	fan.set_shader_parameter("rim", 0.3)
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
		"stalker", "broodling", "feral", "hound":
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
			# Gill fans flared behind the skull, lit along their ribs, and a
			# row of short spines down the tail.
			var frill := Node3D.new()
			for side: float in ([] if frost or lava else [-1.0, 1.0]):
				for f in 3:
					var vane := _piece(frill, "Gill", ball, fan, at + Vector3(side * (0.15 + f * 0.02), 0.04 + f * 0.05, 0.12 + f * 0.05) * h / 1.6,
							Vector3(0.02, 0.2 - f * 0.03, 0.14) * h / 1.6)
					vane.rotation = Vector3(-0.3 - f * 0.25, 0.0, side * (0.5 + f * 0.15))
			_hang_at(frill, "CreatureGills", "Head", Vector3.ZERO)
			for i in 4:
				var barb := _piece(trunk, "TailSpine", horn, bone, Vector3(0, low + 0.12 * h / 1.6 - 0.025 * i * h / 1.6, (0.62 + i * 0.26) * h / 1.6),
						Vector3(0.035, 0.11 - i * 0.015, 0.035) * h / 1.6)
				barb.rotation.x = 0.9
			if frost:
				_feral(trunk, at, low, h / 1.6, ball, horn, hide, dark)
			if kind == "hound":
				_cinder_hound(at, low, h / 1.6, ball, horn)
			if kind == "broodling":
				# Fresh from the egg: shards of shell still stuck to its back
				# and eyes too big for its head.
				var shell := _solid(Color(0.82, 0.86, 0.72), 0.25)
				shell.metallic = 0.0
				var shards := Node3D.new()
				var rng := RandomNumberGenerator.new()
				rng.seed = 31
				for i in 5:
					var shard := _piece(shards, "Shard", ball, shell, Vector3(rng.randf_range(-0.14, 0.14), low + 0.2 * h / 1.6,
							rng.randf_range(-0.3, 0.4)) * Vector3(h / 1.6, 1.0, h / 1.6), Vector3(0.16, 0.03, 0.12) * h / 1.6)
					shard.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
				_hang_at(shards, "CreatureShards", "Torso", Vector3.ZERO)
				var big := Node3D.new()
				for side: float in [-1.0, 1.0]:
					_piece(big, "Eye", ball, glow, at + Vector3(side * 0.12, 0.08, -0.1) * h / 1.6, Vector3(0.09, 0.08, 0.09) * h / 1.6)
				_hang_at(big, "CreatureEyes", "Head", Vector3.ZERO)
			_creature_legs(hide, Vector2(0.11, 0.13), bone)
		"shellback", "elder", "crawler":
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
			var soft := _solid(Color(1.0, 0.78, 0.45), 2.4) if lava else _solid(SOFT_REAR, 0.9)
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
			# A hooked beak under the brow.
			var beak := _piece(face, "Beak", horn, bone, at + Vector3(0, -0.06, -0.3) * h / 1.6, Vector3(0.16, 0.24, 0.14) * h / 1.6)
			beak.rotation.x = -2.0
			_hang_at(face, "CreatureHead", "Head", Vector3.ZERO)
			if kind == "crawler":
				_magma_crawler(mid, h / 1.6, ball, horn, tube)
				_creature_legs(dark, Vector2(0.24, 0.26), bone)
				return
			# What grows on an old shell: tufts of moss in the seams and a few
			# small fungal caps, lit underneath.
			var growth := Node3D.new()
			var moss := _creature_hide(Color(0.2, 0.24, 0.12), 0.0, 0.2)
			var cap_mat := _creature_hide(Color(0.42, 0.3, 0.36), 0.25, 0.5)
			var grow_rng := RandomNumberGenerator.new()
			grow_rng.seed = 17
			for i in 10:
				var px := grow_rng.randf_range(-0.6, 0.6)
				var pz := grow_rng.randf_range(-0.75, 0.7)
				var up := 0.475 * sqrt(maxf(0.0, 1.0 - pow(px / 0.75, 2.0) - pow(pz / 0.95, 2.0)))
				var spot := Vector3(px * h / 1.6, mid + 0.1 * h + up * h / 1.6, pz * h / 1.6)
				if i < 6:
					_piece(growth, "Moss", ball, moss, spot, Vector3(0.22, 0.07, 0.2) * h / 1.6)
					continue
				var tall := grow_rng.randf_range(0.12, 0.22) * h / 1.6
				_strand(growth, "CapStem", tube, bone, spot, spot + Vector3(0, tall, 0), 0.025 * h / 1.6)
				_piece(growth, "Cap", ball, cap_mat, spot + Vector3(0, tall, 0), Vector3(0.16, 0.05, 0.16) * h / 1.6)
				_piece(growth, "CapGills", ball, soft_glow, spot + Vector3(0, tall - 0.012 * h, 0), Vector3(0.13, 0.02, 0.13) * h / 1.6)
			_hang_at(growth, "CreatureGrowth", "Torso", Vector3.ZERO)
			if kind == "elder":
				_shellback_elder(at, mid, h / 1.6, ball, tube, horn, hide, dark, bone, soft_glow)
			_creature_legs(dark, Vector2(0.24, 0.26), bone)
		"lurker", "drowned", "burrower":
			# Long and flat, made to lie in the water: a broad, low trunk, a
			# wide flat skull with a jaw half its length, a lit lure hung
			# over the snout on a stalk and a heavy tail.
			var k := h / 1.4
			var low := body.y * 0.7
			var trunk := Node3D.new()
			_piece(trunk, "Torso", ball, hide, Vector3(0, low, 0.1 * k), Vector3(0.8, 0.34, 1.7) * k)
			_piece(trunk, "Belly", ball, dark, Vector3(0, low - 0.1 * k, 0.1 * k), Vector3(0.7, 0.2, 1.5) * k)
			for i in 7:
				var scute := _piece(trunk, "Scute", ball, dark, Vector3(0, low + 0.15 * k, (-0.55 + i * 0.2) * k),
						Vector3(0.22, 0.08, 0.16) * k)
				scute.rotation.x = 0.2
			for i in 4:
				_piece(trunk, "Tail", ball, hide, Vector3(0, low - 0.02 * i, (1.0 + i * 0.32) * k),
						Vector3(0.36 - i * 0.07, 0.22 - i * 0.04, 0.5) * k)
			# Fins along its flanks, which ripple the water as it lies there.
			for side: float in ([] if sand else [-1.0, 1.0]):
				for i in 4:
					var fin := _piece(trunk, "Fin", ball, fan, Vector3(side * 0.4, low, (-0.4 + i * 0.34)) * k,
							Vector3(0.3, 0.02, 0.2) * k)
					fin.rotation = Vector3(0, side * 0.3, -side * 0.25)
			_hang_at(trunk, "CreatureTrunk", "Torso", Vector3.ZERO)
			var skull := Node3D.new()
			var at := Vector3(0, low + 0.06 * k, -0.95 * k)
			_piece(skull, "Skull", ball, hide, at, Vector3(0.62, 0.22, 0.62) * k)
			_piece(skull, "Jaw", ball, dark, at + Vector3(0, -0.09, -0.12) * k, Vector3(0.58, 0.12, 0.7) * k)
			for side: float in [-1.0, 1.0]:
				_piece(skull, "Eye", ball, glow, at + Vector3(side * 0.2, 0.11, 0.05) * k, Vector3(0.07, 0.05, 0.07) * k)
				for t in 4:
					var fang := _piece(skull, "Tooth", horn, bone, at + Vector3(side * (0.24 - t * 0.03), -0.06, -0.12 - t * 0.09) * k,
							Vector3(0.03, 0.09, 0.03) * k)
					fang.rotation.x = PI
			if sand:
				# No lure and no barbels: a burrower feels for its prey.
				_hang_at(skull, "CreatureHead", "Head", Vector3.ZERO)
				_dune_burrower(at, low, k, ball, horn, dark, bone)
				_creature_legs(dark, Vector2(0.15, 0.17), bone)
				return
			var stalk := _piece(skull, "LureStalk", tube, dark, at + Vector3(0, 0.3, -0.2) * k, Vector3(0.03, 0.42, 0.03) * k)
			stalk.rotation.x = -0.7
			_piece(skull, "Lure", ball, glow, at + Vector3(0, 0.44, -0.4) * k, Vector3(0.09, 0.09, 0.09) * k)
			# Barbels hanging off the jaw, feeling the water.
			for b in 4:
				var root_at := at + Vector3((b - 1.5) * 0.12, -0.12, -0.3 + absf(b - 1.5) * 0.08) * k
				_strand(skull, "Barbel", tube, dark, root_at, root_at + Vector3((b - 1.5) * 0.05, -0.13, -0.08) * k, 0.016 * k)
			_hang_at(skull, "CreatureHead", "Head", Vector3.ZERO)
			if kind == "drowned":
				_drowned_lurker(at, low, k, ball, tube, horn, hide, dark, bone, glow, soft_glow)
			_creature_legs(dark, Vector2(0.15, 0.17), bone)
		"keeper", "brood_mother":
			# The brood's keeper: a hunched giant of the stalkers' kind,
			# its back heaped with lit egg sacs, long arms ending in hooks.
			var k := h / 2.4
			var trunk := Node3D.new()
			var mid := body.y * 0.95
			_piece(trunk, "Torso", ball, hide, Vector3(0, mid, 0), Vector3(0.95, 0.85, 1.25) * k)
			_piece(trunk, "Belly", ball, dark, Vector3(0, mid - 0.18 * k, -0.08 * k), Vector3(0.8, 0.6, 1.0) * k)
			var rng := RandomNumberGenerator.new()
			rng.seed = 23
			for i in 9:
				var spot := Vector3(rng.randf_range(-0.32, 0.32), 0.36 + rng.randf() * 0.12, rng.randf_range(-0.2, 0.5)) * k
				_piece(trunk, "EggSac", ball, soft_glow, Vector3(0, mid, 0) + spot, Vector3.ONE * rng.randf_range(0.18, 0.28) * k)
			# A skin of hide drawn over the heap, the eggs showing through.
			_piece(trunk, "Membrane", ball, fan, Vector3(0, mid + 0.36 * k, 0.15 * k), Vector3(0.8, 0.22, 0.85) * k)
			# Feeding tendrils trailing from under the belly.
			for i in 6:
				var from := Vector3(cos(i * 1.05) * 0.3, mid - 0.4, -0.1 + sin(i * 1.05) * 0.3) * Vector3(k, 1.0, k)
				_strand(trunk, "Tendril", tube, dark, from, from + Vector3(cos(i * 2.3) * 0.08, -0.5, 0.1) * k, 0.03 * k)
			for i in 5:
				var spine := _piece(trunk, "Spine", horn, bone, Vector3((i - 2) * 0.16 * k, mid + 0.4 * k, -0.35 * k),
						Vector3(0.06, 0.26, 0.06) * k)
				spine.rotation.x = -0.4
			_hang_at(trunk, "CreatureTrunk", "Torso", Vector3.ZERO)
			var skull := Node3D.new()
			var at := Vector3(0, mid + 0.06 * k, -0.78 * k)
			_piece(skull, "Skull", ball, hide, at, Vector3(0.42, 0.36, 0.48) * k)
			_piece(skull, "Jaw", ball, dark, at + Vector3(0, -0.13, -0.16) * k, Vector3(0.34, 0.16, 0.44) * k)
			for side: float in [-1.0, 1.0]:
				for e in 2:
					_piece(skull, "Eye", ball, glow, at + Vector3(side * (0.11 + e * 0.07), 0.08 + e * 0.05, -0.17) * k,
							Vector3(0.045, 0.04, 0.045) * k)
			_hang_at(skull, "CreatureHead", "Head", Vector3.ZERO)
			for side: float in [-1.0, 1.0]:
				var arm := Node3D.new()
				var shoulder := Vector3(side * 0.42 * k, mid + 0.1 * k, -0.45 * k)
				var upper := _piece(arm, "Arm", tube, hide, shoulder + Vector3(side * 0.06, -0.3, -0.1) * k,
						Vector3(0.12, 0.7, 0.12) * k)
				upper.rotation.x = 0.35
				for c in 3:
					var hook := _piece(arm, "Claw", horn, bone,
							shoulder + Vector3(side * 0.08 + (c - 1) * 0.05, -0.72, -0.3) * k, Vector3(0.04, 0.26, 0.04) * k)
					hook.rotation.x = -2.0
				_hang_at(arm, "Foreclaw" + ("L" if side < 0.0 else "R"), "Chest", Vector3.ZERO)
			if kind == "brood_mother":
				_brood_mother(trunk, skull, mid, k, ball, tube, horn, hide, fan, soft_glow, bone)
			_creature_legs(hide, Vector2(0.2, 0.22), bone)
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
			# Spore vents round its crown, lit inside, and veins of glow
			# running down the sac.
			for i in 4:
				var a := i * TAU / 4.0 + 0.4
				var foot := at + Vector3(cos(a) * 0.3, 0.6, sin(a) * 0.3) * h / 2.1
				var tip := foot + Vector3(cos(a) * 0.08, 0.2, sin(a) * 0.08) * h / 2.1
				_strand(sac, "Vent", tube, dark, foot, tip, 0.06 * h / 2.1)
				_piece(sac, "VentGlow", ball, soft_glow, tip, Vector3(0.09, 0.04, 0.09) * h / 2.1)
			for i in 7:
				var a := i * TAU / 7.0
				for seg in 3:
					var t0 := 0.3 + seg * 0.4
					var p0 := at + Vector3(cos(a + seg * 0.2) * sin(t0), cos(t0), sin(a + seg * 0.2) * sin(t0)) * 0.66 * h / 2.1
					var p1 := at + Vector3(cos(a + seg * 0.2 + 0.2) * sin(t0 + 0.4), cos(t0 + 0.4), sin(a + seg * 0.2 + 0.2) * sin(t0 + 0.4)) * 0.66 * h / 2.1
					_strand(sac, "Vein", tube, soft_glow, p0, p1, 0.014 * h / 2.1)
			_hang_at(sac, "CreatureSac", "Chest", Vector3.ZERO)
			var face := Node3D.new()
			var mouth := at + Vector3(0, -0.25, -0.62) * h / 2.1
			_piece(face, "Mouth", ball, dark, mouth, Vector3(0.36, 0.22, 0.2) * h / 2.1)
			for side: float in [-1.0, 1.0]:
				_piece(face, "Eye", ball, glow, mouth + Vector3(side * 0.12, 0.16, -0.06) * h / 2.1,
						Vector3(0.06, 0.06, 0.05) * h / 2.1)
			_hang_at(face, "CreatureHead", "Head", Vector3.ZERO)
			_creature_legs(dark, Vector2(0.14, 0.16), bone)


## A Feral Stalker (the look "feral"): the stalker's body furred against the
## cold. A shaggy ruff round the neck and shoulders, tufts down the flanks, a
## mane of ice spines lit from inside down the back, frost on the brow, and
## long hooked blades of ice-blue horn over the foreclaws (its weapon). Built
## on the stalker's own pieces (`k` its scale, `at` its skull, `low` the line
## of its back).
func _feral(trunk: Node3D, at: Vector3, low: float, k: float, ball: SphereMesh, horn: CylinderMesh,
		hide: Material, dark: Material) -> void:
	var ice := _solid(FROST_GLOW, 1.4)
	ice.roughness = 0.15
	var pale := _creature_hide(actor.body_color.lerp(Color(0.82, 0.86, 0.9), 0.55), 0.0, 0.05)
	pale.set_shader_parameter("glow", FROST_GLOW)
	# The ruff: overlapping tufts of pale fur round the neck and shoulders.
	for i in 7:
		var a := (i - 3) * 0.42
		var tuft := _piece(trunk, "Ruff", ball, pale, Vector3(sin(a) * 0.24, low + 0.1 + cos(a) * 0.05, -0.42) * Vector3(k, 1.0, k),
				Vector3(0.2, 0.26, 0.24) * k)
		tuft.rotation = Vector3(0.4, 0.0, -a * 0.6)
	# Tufts down the flanks, the fur hanging long under the belly.
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var tuft := _piece(trunk, "Fur", horn, dark, Vector3(side * 0.2, low - 0.12, -0.25 + i * 0.2) * Vector3(k, 1.0, k),
					Vector3(0.07, 0.2, 0.07) * k)
			tuft.rotation = Vector3(PI, 0.0, side * 0.35)
	# The mane: a double row of ice spines down the back, tallest at the
	# shoulders.
	for i in 7:
		var tall := (0.26 - i * 0.025) * k
		for side: float in [-1.0, 1.0]:
			var spike := _piece(trunk, "IceSpine", horn, ice, Vector3(side * 0.06 * k, low + 0.2 * k + tall * 0.4, (-0.4 + i * 0.13) * k),
					Vector3(0.05 * k, tall, 0.05 * k))
			spike.rotation = Vector3(0.55, 0.0, side * 0.3)
	# Frost on the brow and a pair of swept horns.
	var crown := Node3D.new()
	_piece(crown, "Brow", ball, pale, at + Vector3(0, 0.1, -0.04) * k, Vector3(0.3, 0.1, 0.3) * k)
	for side: float in [-1.0, 1.0]:
		var horn_piece := _piece(crown, "Horn", horn, ice, at + Vector3(side * 0.1, 0.16, 0.12) * k, Vector3(0.04, 0.24, 0.04) * k)
		horn_piece.rotation = Vector3(1.1, 0.0, side * 0.35)
	_hang_at(crown, "FeralBrow", "Head", Vector3.ZERO)
	# Its blades: a long hooked spur of ice horn along each foreleg.
	for side: float in [-1.0, 1.0]:
		var spur := Node3D.new()
		var shoulder := Vector3(side * 0.18 * k, low - 0.02, -0.38 * k)
		var blade := _piece(spur, "Spur", horn, ice, shoulder + Vector3(side * 0.05, -0.2, -0.26) * k, Vector3(0.04, 0.42, 0.06) * k)
		blade.rotation = Vector3(-2.3, 0.0, 0.0)
		_hang_at(spur, "FeralSpur" + ("L" if side < 0.0 else "R"), "Chest", Vector3.ZERO)


## A Cinder Hound (the look "cinder_hound"): the stalker's lean body under
## basalt, lava glowing in the cracks between the plates down its back, a
## burning maw, a ruff of basalt shards round the neck and a tail that ends
## in an ember. Built on the stalker's own pieces (`k` its scale, `at` its
## skull, `low` the line of its back).
func _cinder_hound(at: Vector3, low: float, k: float, ball: SphereMesh, horn: CylinderMesh) -> void:
	var basalt := _creature_hide(Color(0.09, 0.08, 0.08), 0.0, 0.05)
	basalt.set_shader_parameter("glow", LAVA_GLOW)
	var molten := _solid(LAVA_GLOW, 2.4)
	var back := Node3D.new()
	# The lava under the back, showing between the plates laid over it.
	_piece(back, "Seam", ball, molten, Vector3(0, low + 0.16 * k, 0.0), Vector3(0.24, 0.06, 0.95) * k)
	for i in 6:
		for side: float in [-1.0, 1.0]:
			var plate := _piece(back, "Plate", ball, basalt, Vector3(side * 0.07, low + 0.2, -0.38 + i * 0.15) * Vector3(k, 1.0, k),
					Vector3(0.18, 0.07, 0.14) * k)
			plate.rotation = Vector3(0.15, 0.0, -side * 0.35)
	# A ruff of basalt shards round the neck.
	for i in 7:
		var a := (i - 3) * 0.42
		var shard := _piece(back, "Shard", horn, basalt, Vector3(sin(a) * 0.2, low + 0.12 + cos(a) * 0.05, -0.44) * Vector3(k, 1.0, k),
				Vector3(0.06, 0.24, 0.06) * k)
		shard.rotation = Vector3(0.9, 0.0, -a * 0.8)
	# The ember at the tail's end.
	_piece(back, "Ember", ball, molten, Vector3(0, low - 0.04, 1.6 * k), Vector3(0.1, 0.1, 0.14) * k)
	_hang_at(back, "HoundBack", "Torso", Vector3.ZERO)
	# The maw burns inside, and the brow is a basalt ridge.
	var face := Node3D.new()
	_piece(face, "Maw", ball, molten, at + Vector3(0, -0.04, -0.2) * k, Vector3(0.14, 0.05, 0.34) * k)
	_piece(face, "Brow", ball, basalt, at + Vector3(0, 0.1, -0.06) * k, Vector3(0.3, 0.08, 0.3) * k)
	for side: float in [-1.0, 1.0]:
		var spike := _piece(face, "BrowSpike", horn, basalt, at + Vector3(side * 0.1, 0.14, 0.12) * k, Vector3(0.04, 0.2, 0.04) * k)
		spike.rotation = Vector3(1.2, 0.0, side * 0.3)
	_hang_at(face, "HoundFace", "Head", Vector3.ZERO)


## A Magma Crawler (the look "magma_crawler"): a shellback's body whose dome
## is cooling basalt, lava running in the seams between its plates and out
## of three chimneys on its back, dripping from under its skirt where it
## burns the ground it walks on. Built on the shellback's own pieces
## (`mid` the line of its middle, `k` its scale).
func _magma_crawler(mid: float, k: float, ball: SphereMesh, horn: CylinderMesh, tube: CylinderMesh) -> void:
	var molten := _solid(LAVA_GLOW, 2.4)
	var basalt := _creature_hide(Color(0.1, 0.09, 0.085), 0.0, 0.05)
	basalt.set_shader_parameter("glow", LAVA_GLOW)
	var shell := Node3D.new()
	var top := mid + 0.16 * k
	# The dome's surface over a spot across (`px`) and along (`pz`) it.
	var surface := func(px: float, pz: float) -> Vector3:
		var up := 0.475 * sqrt(maxf(0.0, 1.0 - pow(px / 0.75, 2.0) - pow(pz / 0.95, 2.0)))
		return Vector3(px * k, top + up * 1.03 * k, pz * k)
	# Seams across the dome between the rows of plates, and down it between
	# the columns, each a chain of short glowing tubes on its curve.
	for pz: float in [-0.25, 0.25]:
		for i in 8:
			var a: Vector3 = surface.call(-0.7 + i * 0.175, pz)
			var b: Vector3 = surface.call(-0.7 + (i + 1) * 0.175, pz)
			_strand(shell, "Seam", tube, molten, a, b, 0.035 * k)
	for px: float in [-0.21, 0.21]:
		for i in 8:
			var a: Vector3 = surface.call(px, -0.88 + i * 0.22)
			var b: Vector3 = surface.call(px, -0.88 + (i + 1) * 0.22)
			_strand(shell, "Seam", tube, molten, a, b, 0.035 * k)
	# Chimneys of basalt, lava welling at their mouths.
	for i in 3:
		var foot: Vector3 = surface.call((i - 1) * 0.32, -0.05 + absf(i - 1) * 0.3)
		_strand(shell, "Chimney", tube, basalt, foot, foot + Vector3(0, 0.22, 0.04) * k, 0.07 * k)
		_piece(shell, "Vent", ball, molten, foot + Vector3(0, 0.23, 0.04) * k, Vector3(0.1, 0.05, 0.1) * k)
	# Drips under the skirt.
	for i in 6:
		var a := i * TAU / 6.0 + 0.3
		var drip := _piece(shell, "Drip", horn, molten, Vector3(cos(a) * 0.62, 0.0, sin(a) * 0.78) * k + Vector3(0, mid - 0.32 * k, 0),
				Vector3(0.05, 0.14, 0.05) * k)
		drip.rotation.x = PI
	_hang_at(shell, "CrawlerMagma", "Torso", Vector3.ZERO)


## A Dune Burrower (the look "dune_burrower"): a lurker's long, flat body in
## a sand hide, with a shovel of horn for a snout, a ridge of digging spades
## down its back and broad spade claws to dig with. Built on the lurker's
## own pieces (`k` its scale, `at` its skull, `low` the line of its back).
func _dune_burrower(at: Vector3, low: float, k: float, ball: SphereMesh, horn: CylinderMesh, dark: Material,
		bone: Material) -> void:
	var head := Node3D.new()
	var shovel := _piece(head, "Shovel", ball, bone, at + Vector3(0, 0.02, -0.42) * k, Vector3(0.52, 0.06, 0.36) * k)
	shovel.rotation.x = 0.15
	_piece(head, "Crest", ball, dark, at + Vector3(0, 0.12, 0.05) * k, Vector3(0.3, 0.1, 0.4) * k)
	for side: float in [-1.0, 1.0]:
		var horn_piece := _piece(head, "Horn", horn, bone, at + Vector3(side * 0.22, 0.1, 0.18) * k, Vector3(0.05, 0.26, 0.05) * k)
		horn_piece.rotation = Vector3(1.3, 0.0, side * 0.5)
	_hang_at(head, "BurrowerHead", "Head", Vector3.ZERO)
	var back := Node3D.new()
	for i in 6:
		var spade := _piece(back, "Spade", ball, bone, Vector3(0, low + 0.2 * k, (-0.5 + i * 0.24) * k),
				Vector3(0.03, 0.2 - absf(i - 2.5) * 0.02, 0.18) * k)
		spade.rotation.x = 0.4
	_hang_at(back, "BurrowerBack", "Torso", Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		var claw := _piece(arm, "Spade", ball, bone, Vector3(side * 0.44, low - 0.12, -0.55) * Vector3(k, 1.0, k), Vector3(0.2, 0.04, 0.24) * k)
		claw.rotation = Vector3(0.2, side * 0.4, -side * 0.3)
		_hang_at(arm, "BurrowerClaw" + ("L" if side < 0.0 else "R"), "Chest", Vector3.ZERO)


## A brood mother (a keeper's body grown old and huge, `Look.SKINS`
## A lurker grown old in the deep (the look "drowned_lurker", creature
## "drowned"): a crown of three more lures on stalks over its skull, a
## ridge of jagged bony plates down its back, weed hanging in beards from
## its jaw and flanks, glowcaps grown on it like barnacles, and old roots it
## dragged down with it still stuck through its back. Built on the lurker's
## own pieces (`k` its scale).
func _drowned_lurker(at: Vector3, low: float, k: float, ball: SphereMesh, tube: CylinderMesh,
		horn: CylinderMesh, _hide: Material, dark: Material, bone: Material, glow: Material, soft_glow: Material) -> void:
	var head := Node3D.new()
	var back := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 67
	var weed := _creature_hide(Color(0.1, 0.16, 0.1), 0.0, 0.2)
	var wood := _creature_hide(Color(0.24, 0.18, 0.15), 0.02, 0.25)
	# A crown of lures: three stalks fanned over the skull.
	for i in 3:
		var side := float(i - 1)
		var root_at := at + Vector3(side * 0.18, 0.1, 0.12) * k
		var tip := root_at + Vector3(side * 0.28, 0.42 - absf(side) * 0.1, -0.3) * k
		_strand(head, "Crown", tube, dark, root_at, tip, 0.03 * k)
		_piece(head, "CrownLure", ball, glow, tip, Vector3.ONE * 0.08 * k)
	# Weed in beards from the jaw.
	for i in 6:
		var from := at + Vector3(rng.randf_range(-0.28, 0.28), -0.14, rng.randf_range(-0.35, 0.1)) * k
		_strand(head, "Weed", tube, weed, from, from + Vector3(rng.randf_range(-0.05, 0.05), -rng.randf_range(0.2, 0.4), 0.05) * k, 0.025 * k)
	# Bony plates down the back, glowcap barnacles and weed on the flanks.
	for i in 8:
		var z := (-0.6 + i * 0.22) * k
		var plate := _piece(back, "BackPlate", horn, bone, Vector3(0, low + 0.2 * k, z), Vector3(0.1, 0.22 - absf(i - 3.5) * 0.02, 0.1) * k)
		plate.rotation.x = 0.4
	for i in 10:
		var spot := Vector3(rng.randf_range(-0.32, 0.32), low + 0.14 * k, rng.randf_range(-0.6, 0.9) * k)
		spot.x *= k
		_piece(back, "Barnacle", ball, soft_glow, spot, Vector3(0.09, 0.05, 0.09) * k)
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var from := Vector3(side * 0.4 * k, low - 0.02 * k, (-0.5 + i * 0.4) * k)
			_strand(back, "FlankWeed", tube, weed, from, from + Vector3(side * 0.05, -0.25, 0.08) * k, 0.03 * k)
	# Old roots dragged down with it, stuck through its back.
	for i in 3:
		var from := Vector3(rng.randf_range(-0.2, 0.2) * k, low, rng.randf_range(-0.3, 0.7) * k)
		var to := from + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.5, 0.8), rng.randf_range(0.1, 0.4)) * k
		_strand(back, "StuckRoot", tube, wood, from, to, 0.06 * k)
		_piece(back, "RootEnd", ball, wood, to, Vector3.ONE * 0.08 * k)
	_hang_at(head, "DrownedCrown", "Head", Vector3.ZERO)
	_hang_at(back, "DrownedBack", "Torso", Vector3.ZERO)


## What an old shellback grows into (the look "shellback_elder", creature
## "elder"): a ram of horn over its brow, two great horns swept forward, a
## ridge of jagged plates down the dome, a garden of fungus and hanging moss
## on its back and pale scars on its front. Built on the shellback's own
## pieces (`k` its scale), so its soft rear still shows.
func _shellback_elder(at: Vector3, mid: float, k: float, ball: SphereMesh,
		tube: CylinderMesh, horn: CylinderMesh, hide: Material, dark: Material, bone: Material, soft_glow: Material) -> void:
	var face := Node3D.new()
	var dome := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var old_bone := _solid(Color(0.66, 0.6, 0.48), 0.0)
	old_bone.metallic = 0.0
	old_bone.roughness = 0.9
	# The ram: a thick shield of horn over the brow, scarred pale.
	_piece(face, "Ram", ball, old_bone, at + Vector3(0, 0.2, -0.12) * k, Vector3(0.82, 0.34, 0.5) * k)
	for i in 5:
		var scar := _piece(face, "Scar", ball, bone, at + Vector3(rng.randf_range(-0.3, 0.3), 0.3, -0.34) * k,
				Vector3(0.05, 0.03, 0.18) * k)
		scar.rotation = Vector3(0.3, rng.randf_range(-0.6, 0.6), rng.randf_range(-0.4, 0.4))
	# Two great horns, out from the ram and swept forward, in segments.
	for side: float in [-1.0, 1.0]:
		var points: Array[Vector3] = []
		for seg in 6:
			var t := seg / 5.0
			points.append(at + Vector3(side * (0.32 + 0.38 * t), 0.24 + 0.32 * sin(t * 2.4), -0.1 - 0.62 * t) * k)
		for seg in 5:
			_strand(face, "Horn", horn if seg == 4 else tube, old_bone, points[seg], points[seg + 1],
					(0.11 - seg * 0.018) * k)
	# A ridge of jagged plates down the dome's spine.
	for i in 6:
		var pz := -0.65 + i * 0.26
		var up := 0.475 * sqrt(maxf(0.0, 1.0 - pow(pz / 0.95, 2.0)))
		var spike := _piece(dome, "Ridge", horn, dark, Vector3(0, mid + 0.1 * 1.6 * k + (up + 0.08) * k, pz * k),
				Vector3(0.16, 0.3 - absf(pz) * 0.12, 0.12) * k)
		spike.rotation.x = 0.35
	# A garden on its back: fungus stalks with lit gills, and moss hanging
	# in beards from the skirt.
	var moss := _creature_hide(Color(0.22, 0.27, 0.13), 0.0, 0.2)
	var cap_mat := _creature_hide(Color(0.5, 0.36, 0.3), 0.25, 0.5)
	for i in 7:
		var px := rng.randf_range(-0.55, 0.55)
		var pz := rng.randf_range(-0.3, 0.6)
		var up := 0.475 * sqrt(maxf(0.0, 1.0 - pow(px / 0.75, 2.0) - pow(pz / 0.95, 2.0)))
		var spot := Vector3(px, 0.1 * 1.6 + up, pz) * k + Vector3(0, mid, 0)
		var tall := rng.randf_range(0.25, 0.5) * k
		_strand(dome, "GardenStem", tube, bone, spot, spot + Vector3(rng.randf_range(-0.05, 0.05) * k, tall, 0), 0.04 * k)
		var wide := rng.randf_range(0.2, 0.34) * k
		_piece(dome, "GardenCap", ball, cap_mat, spot + Vector3(0, tall, 0), Vector3(wide, wide * 0.3, wide))
		_piece(dome, "GardenGills", ball, soft_glow, spot + Vector3(0, tall - 0.02 * k, 0), Vector3(wide, wide * 0.12, wide) * 0.85)
	for i in 14:
		var a := rng.randf() * TAU
		if absf(sin(a)) < 0.25 and cos(a) > 0.0:
			continue
		var rim := Vector3(sin(a) * 0.78, -0.02, cos(a) * 0.98) * k + Vector3(0, mid - 0.05 * 1.6 * k, 0)
		var hang := rng.randf_range(0.15, 0.35) * k
		_strand(dome, "Beard", tube, moss, rim, rim + Vector3(0, -hang, 0), 0.05 * k)
	_piece(dome, "Hide", ball, hide, Vector3(0, mid - 0.1 * k, 0), Vector3(1.3, 0.3, 1.7) * k)
	_hang_at(face, "ElderRam", "Head", Vector3.ZERO)
	_hang_at(dome, "ElderBack", "Torso", Vector3.ZERO)


## "brood_mother"): a swollen abdomen dragging behind, studded with lit eggs
## and veined with glow, woody roots grown out of her back and arching down
## to the ground behind her, and a crown of root horns swept back from the
## skull. Pieces hang on the keeper's own trunk and skull.
func _brood_mother(trunk: Node3D, skull: Node3D, mid: float, k: float, ball: SphereMesh, tube: CylinderMesh,
		horn: CylinderMesh, hide: Material, membrane: Material, soft_glow: Material, bone: Material) -> void:
	var wood := _creature_hide(Color(0.24, 0.18, 0.15), 0.02, 0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var belly := Vector3(0, mid - 0.05 * k, 1.05 * k)
	var size := Vector3(1.05, 0.95, 1.6) * k
	_piece(trunk, "Abdomen", ball, membrane, belly, size)
	_piece(trunk, "AbdomenUnder", ball, hide, belly + Vector3(0, -0.12, 0.05) * k, size * Vector3(0.9, 0.7, 0.95))
	# Eggs bulging through the abdomen's skin, and veins of glow over it.
	for i in 16:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-0.6, 1)).normalized()
		_piece(trunk, "Egg", ball, soft_glow, belly + dir * size * 0.47, Vector3.ONE * rng.randf_range(0.14, 0.24) * k)
	for i in 6:
		var a := -0.9 + i * 0.36
		var points: Array[Vector3] = []
		for seg in 5:
			var t := -0.9 + seg * 0.45
			points.append(belly + Vector3(sin(a) * cos(t), sin(t) * 0.8 + 0.25, cos(a) * cos(t) * 0.9).normalized() * size * 0.5)
		for seg in 4:
			_strand(trunk, "Vein", tube, soft_glow, points[seg], points[seg + 1], 0.02 * k)
	# Roots grown out of her back, arching up and down to the ground.
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var spread := 0.25 + float(i >> 1) * 0.3
		var from := Vector3(side * 0.18 * k, mid + 0.4 * k, (0.1 + float(i >> 1) * 0.35) * k)
		var peak := from + Vector3(side * spread * 0.6, 0.55 + rng.randf() * 0.25, 0.3) * k
		var foot := Vector3(side * (0.7 + spread) * k, 0.05, (0.6 + float(i >> 1) * 0.55) * k)
		var points: Array[Vector3] = []
		for seg in 7:
			var t := seg / 6.0
			points.append(from.lerp(peak, t).lerp(peak.lerp(foot, t), t))
		for seg in 6:
			_strand(trunk, "Root", tube, wood, points[seg], points[seg + 1], lerpf(0.09, 0.04, seg / 6.0) * k)
	# A crown of root horns swept back from the skull.
	var at := Vector3(0, mid + 0.06 * k, -0.78 * k)
	for i in 5:
		var x := (i - 2) * 0.09
		var base := at + Vector3(x, 0.2, 0.05) * k
		var tip := base + Vector3(x * 1.5, 0.3 - absf(x) * 0.6, 0.45) * k
		_strand(skull, "Crown", tube, wood, base, base.lerp(tip, 0.6), 0.045 * k)
		var point := _piece(skull, "CrownTip", horn, bone, base.lerp(tip, 0.8), Vector3(0.05, 0.22, 0.05) * k)
		point.rotation.x = 1.2


## A beast's two legs down the skeleton's own (thigh, shank and foot), with
## claws on the foot.
func _creature_legs(mat: Material, size: Vector2, claw: Material) -> void:
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.5
	horn.height = 1.0
	horn.radial_segments = 6
	for side: String in ["L", "R"]:
		# A heavy haunch at the hip and a thigh tapering into the shank, so
		# the legs carry the body rather than stilts.
		var hip := Node3D.new()
		var haunch := SphereMesh.new()
		haunch.radial_segments = 12
		haunch.rings = 6
		_piece(hip, "Haunch", haunch, mat, Vector3.ZERO, Vector3(size.x * 2.6, size.y * 3.0, size.x * 3.0))
		_hang_at(hip, "Haunch" + side, "UpperLeg." + side, _rest_at("UpperLeg." + side).lerp(_rest_at("MidLeg." + side), 0.2))
		_limb("UpperLeg." + side, "MidLeg." + side, Vector3.ZERO, size * 2.0, mat, 0.0, 1.0, true)
		_limb("MidLeg." + side, "LowerLeg." + side, Vector3.ZERO, size * 1.5, mat, 0.0, 1.0, true)
		_limb("LowerLeg." + side, "FootBack." + side, Vector3.ZERO, size * 0.75, mat, 0.0, 1.0, true)
		# A calf bulging at the top of the shank.
		var calf := Node3D.new()
		_piece(calf, "Calf", haunch, mat, Vector3.ZERO, Vector3(size.x * 1.9, size.y * 3.2, size.x * 2.0))
		_hang_at(calf, "Calf" + side, "MidLeg." + side, _rest_at("MidLeg." + side).lerp(_rest_at("LowerLeg." + side), 0.3))
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


## How many of a beast's hide cells carry a lit freckle, by kind.
const CREATURE_FRECKLES := {
	"feral": 0.03, "stalker": 0.08, "broodling": 0.04, "shellback": 0.03, "elder": 0.03, "drowned": 0.16, "lurker": 0.14, "keeper": 0.1, "bloater": 0.35,
	"brood_mother": 0.12, "hound": 0.1, "crawler": 0.12, "burrower": 0.0,
}


## A beast's hide (`creature.gdshader`): its colour mottled darker, a paler
## belly, lit freckles in the planet's glow and a wet sheen.
static func _creature_hide(color: Color, freckles: float, wet: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/creature.gdshader") as Shader
	mat.set_shader_parameter("hide", color)
	mat.set_shader_parameter("mottle", Color.from_hsv(fposmod(color.h - 0.04, 1.0), minf(color.s * 1.2 + 0.05, 1.0), color.v * 0.6))
	mat.set_shader_parameter("under", color.lerp(Color(0.78, 0.72, 0.62), 0.4))
	mat.set_shader_parameter("glow", CREATURE_GLOW)
	mat.set_shader_parameter("freckles", freckles)
	mat.set_shader_parameter("wet", wet)
	return mat


## A tube from one point to another, `width` across: a tendril, a stem, a vein.
static func _strand(root: Node3D, piece_name: String, tube: PrimitiveMesh, mat: Material, from: Vector3, to: Vector3,
		width: float) -> MeshInstance3D:
	var along := to - from
	var part := _piece(root, piece_name, tube, mat, (from + to) * 0.5, Vector3.ONE)
	var y := along.normalized() if along.length() > 0.0001 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	part.basis = Basis(x * width, y * along.length(), z * width)
	return part


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


## The station automata's own body (Caleb's call: sleeker, more advanced
## machines, with the weapon built into the arm), round the scene's walking
## skeleton, whose own mesh is hidden: pale ceramic shells over a graphite
## frame, a tapered carapace with a lit core in the chest, a segmented
## waist, a narrow helm with a lit visor and a crest, shoulder shells with
## a lit edge, armored thighs, knee guards and shin plates, and lit seams in
## the body's colour. The right forearm is the weapon (`_update_arm_weapon`);
## the left ends in a three-clawed hand. A colossus (`heavy`) is broader,
## with layered shoulders, a reactor on its back and a missile pod over the
## left shoulder. Everything hangs on the bone it moves with.
func _build_android(heavy: bool) -> void:
	if _skeleton == null:
		return
	var k := float(_def.get("height", 2.2)) / 2.2
	var bulk := 1.25 if heavy else 1.0
	var shell := _solid(Color(0.8, 0.82, 0.85), 0.0)
	shell.metallic = 0.2
	shell.roughness = 0.32
	var frame := _solid(Color(0.1, 0.105, 0.12), 0.0)
	frame.metallic = 0.6
	frame.roughness = 0.45
	var joint := _solid(Color(0.32, 0.33, 0.36), 0.0)
	joint.metallic = 0.75
	var paint := _solid(actor.body_color.darkened(0.35), 0.0)
	var lit := _solid(actor.body_color.lightened(0.35), 3.0)
	_android_parts = {"shell": shell, "frame": frame, "joint": joint, "lit": lit, "k": k, "bulk": bulk, "heavy": heavy}
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 10
	var hips := _rest_at("Body")
	var chest := _rest_at("Chest")
	var neck := _rest_at("Neck")
	var head := _rest_at("Head")
	var w := k * bulk
	# The pelvis: a graphite block with ceramic plates over the hips and a
	# lit seam across the front.
	var pelvis := Node3D.new()
	_block(pelvis, "Pelvis", frame, hips.y - 0.13 * k, [-0.17 * w, 0.17 * w, -0.12 * w, 0.12 * w],
			hips.y + 0.07 * k, [-0.19 * w, 0.19 * w, -0.13 * w, 0.13 * w])
	_block(pelvis, "Fauld", shell, hips.y - 0.08 * k, [-0.1 * w, 0.1 * w, -0.16 * w, -0.12 * w],
			hips.y + 0.06 * k, [-0.13 * w, 0.13 * w, -0.15 * w, -0.12 * w])
	for side: float in [-1.0, 1.0]:
		var plate := _piece(pelvis, "HipPlate", BoxMesh.new(), shell, Vector3(side * 0.2 * w, hips.y - 0.04 * k, 0),
				Vector3(0.05, 0.2, 0.22) * w)
		plate.rotation.z = side * 0.18
	_piece(pelvis, "Seam", BoxMesh.new(), lit, Vector3(0, hips.y + 0.04 * k, -0.135 * w), Vector3(0.22, 0.015, 0.01) * w)
	_hang_at(pelvis, "AndroidPelvis", "Body", Vector3.ZERO)
	# The waist: graphite rings stacked up to the chest, a spine behind.
	var waist := Node3D.new()
	var waist_lo := hips.y + 0.07 * k
	var waist_hi := chest.y - 0.12 * k
	for i in 3:
		var y := lerpf(waist_lo, waist_hi, (i + 0.5) / 3.0)
		_piece(waist, "Ring", tube, frame if i != 1 else joint, Vector3(0, y, 0),
				Vector3(0.27 - i * 0.015, (waist_hi - waist_lo) / 3.4, 0.2) * w)
	_piece(waist, "Spine", BoxMesh.new(), joint, Vector3(0, (waist_lo + waist_hi) * 0.5, 0.11 * w),
			Vector3(0.06 * w, waist_hi - waist_lo, 0.05 * w))
	_hang_at(waist, "AndroidWaist", "Torso", Vector3.ZERO)
	# The carapace: a ceramic shell tapering from broad shoulders to the
	# waist, a graphite inset down its front with the lit core in it, lit
	# seams down its sides, a collar, and a pack on its back.
	var torso := Node3D.new()
	var lo := chest.y - 0.16 * k
	var hi := neck.y + 0.02 * k
	# Broad enough at the top to meet the shoulder joints.
	var span := maxf(0.27 * w, absf(_rest_at("UpperArm.L").x) - 0.05 * w)
	_block(torso, "Carapace", shell, lo, [-0.18 * w, 0.18 * w, -0.15 * w, 0.13 * w],
			hi, [-span, span, -0.16 * w, 0.15 * w])
	_block(torso, "Inset", frame, lo + 0.04 * k, [-0.08 * w, 0.08 * w, -0.153 * w, -0.1 * w],
			hi - 0.06 * k, [-0.12 * w, 0.12 * w, -0.163 * w, -0.1 * w])
	var core_y := lerpf(lo, hi, 0.6)
	var core := _piece(torso, "Core", tube, lit, Vector3(0, core_y, -0.17 * w), Vector3(0.09, 0.02, 0.09) * w)
	core.rotation.x = PI * 0.5
	var rim := _piece(torso, "CoreRim", tube, joint, Vector3(0, core_y, -0.163 * w), Vector3(0.13, 0.02, 0.13) * w)
	rim.rotation.x = PI * 0.5
	for side: float in [-1.0, 1.0]:
		var seam := _piece(torso, "Seam", BoxMesh.new(), lit, Vector3(side * 0.2 * w, lerpf(lo, hi, 0.5), -0.135 * w),
				Vector3(0.012 * w, (hi - lo) * 0.8, 0.012 * w))
		seam.rotation.z = -side * 0.22
		_piece(torso, "ChestPlate", BoxMesh.new(), paint, Vector3(side * 0.17 * w, hi - 0.06 * k, -0.15 * w),
				Vector3(0.1, 0.05, 0.02) * w)
	_piece(torso, "Collar", tube, frame, Vector3(0, hi + 0.015 * k, 0), Vector3(0.24, 0.05, 0.2) * w)
	_block(torso, "BackPack", frame, lo + 0.05 * k, [-0.13 * w, 0.13 * w, 0.12 * w, 0.2 * w],
			hi - 0.03 * k, [-0.15 * w, 0.15 * w, 0.13 * w, 0.22 * w])
	for side: float in [-1.0, 1.0]:
		_piece(torso, "Vent", BoxMesh.new(), lit, Vector3(side * 0.07 * w, lerpf(lo, hi, 0.45), 0.215 * w),
				Vector3(0.04, (hi - lo) * 0.45, 0.01) * w)
	if heavy:
		# A reactor drum on the back, lit through its grille, and a pod of
		# missiles over the left shoulder.
		var drum := _piece(torso, "Reactor", tube, joint, Vector3(0, lerpf(lo, hi, 0.55), 0.3 * w), Vector3(0.26, 0.3, 0.26) * w)
		drum.rotation.x = PI * 0.5
		_piece(torso, "ReactorGlow", tube, lit, Vector3(0, lerpf(lo, hi, 0.55), 0.45 * w), Vector3(0.18, 0.01, 0.18) * w).rotation.x = PI * 0.5
		var pod_side := signf(_rest_at("UpperArm.L").x)
		var pod_at := Vector3(pod_side * 0.2 * w, hi + 0.12 * k, 0.06 * w)
		_piece(torso, "Pod", BoxMesh.new(), shell, pod_at, Vector3(0.2, 0.15, 0.24) * w)
		_piece(torso, "PodFace", BoxMesh.new(), frame, pod_at + Vector3(0, 0, -0.121 * w), Vector3(0.17, 0.12, 0.01) * w)
		for i in 4:
			_piece(torso, "PodTube", tube, lit, pod_at + Vector3((i % 2 - 0.5) * 0.07 * w, (floorf(i / 2.0) - 0.5) * 0.055 * w, -0.125 * w),
					Vector3(0.035, 0.008, 0.035) * w).rotation.x = PI * 0.5
	_hang_at(torso, "AndroidTorso", "Chest", Vector3.ZERO)
	# The helm: narrow and long, tapered to the brow, a lit visor across the
	# front, a dark faceplate under it, a crest and lit sensors either side.
	var helm := Node3D.new()
	var h0 := head.y - 0.04 * k
	var h1 := head.y + 0.24 * k
	_piece(helm, "Neck", tube, joint, Vector3(0, (hi + h0) * 0.5, 0.01 * k), Vector3(0.1, maxf(h0 - hi, 0.04 * k) + 0.04 * k, 0.1) * k)
	_block(helm, "Helm", shell, h0, [-0.125 * k, 0.125 * k, -0.15 * k, 0.15 * k], h1, [-0.09 * k, 0.09 * k, -0.1 * k, 0.14 * k])
	_block(helm, "Face", frame, h0 + 0.005 * k, [-0.1 * k, 0.1 * k, -0.165 * k, -0.07 * k],
			h0 + 0.12 * k, [-0.095 * k, 0.095 * k, -0.15 * k, -0.07 * k])
	_piece(helm, "Visor", BoxMesh.new(), lit, Vector3(0, h0 + 0.16 * k, -0.135 * k), Vector3(0.19, 0.035, 0.03) * k)
	_piece(helm, "Crest", BoxMesh.new(), paint, Vector3(0, h1 + 0.02 * k, 0.03 * k), Vector3(0.03, 0.06, 0.24) * k)
	for side: float in [-1.0, 1.0]:
		var ear := _piece(helm, "Ear", tube, joint, Vector3(side * 0.12 * k, h0 + 0.12 * k, 0.02 * k), Vector3(0.08, 0.035, 0.08) * k)
		ear.rotation.z = PI * 0.5
		var eye := _piece(helm, "Sensor", tube, lit, Vector3(side * 0.14 * k, h0 + 0.12 * k, 0.02 * k), Vector3(0.04, 0.01, 0.04) * k)
		eye.rotation.z = PI * 0.5
	_hang_at(helm, "AndroidHelm", "Head", Vector3.ZERO)
	# Arms and legs.
	for side: String in ["L", "R"]:
		var shoulder := _rest_at("UpperArm." + side)
		var elbow := _rest_at("LowerArm." + side)
		var out := Vector3(signf(shoulder.x), 0.0, 0.0)
		_disc("UpperArm." + side, shoulder, 0.1 * w, joint)
		var guard := Node3D.new()
		var size := Vector3(0.22, 0.1, 0.26) * w * (1.25 if heavy else 1.0)
		var cap := _piece(guard, "Shoulder", BoxMesh.new(), shell, Vector3.ZERO, size)
		cap.rotation.z = out.x * -0.3
		var edge := _piece(guard, "ShoulderEdge", BoxMesh.new(), lit, Vector3(out.x * size.x * 0.45, -size.y * 0.55, 0),
				Vector3(0.012 * w, 0.012 * w, size.z * 0.9))
		edge.rotation.z = out.x * -0.3
		_piece(guard, "ShoulderStripe", BoxMesh.new(), paint, Vector3(0, size.y * 0.52, 0), Vector3(size.x * 0.6, 0.01 * w, size.z * 0.3))
		if heavy:
			var under := _piece(guard, "ShoulderLower", BoxMesh.new(), shell, Vector3(out.x * 0.05 * w, -0.1 * w, 0),
					Vector3(0.2, 0.08, 0.24) * w)
			under.rotation.z = out.x * -0.55
		_hang_at(guard, "AndroidShoulder" + side, "UpperArm." + side, shoulder + out * 0.04 * w + Vector3(0, 0.08 * w, 0))
		_limb("UpperArm." + side, "LowerArm." + side, Vector3.ZERO, Vector2(0.08, 0.08) * w, frame, 0.0, 1.0, true)
		_limb("UpperArm." + side, "LowerArm." + side, Vector3.ZERO, Vector2(0.15, 0.15) * w, shell, 0.15, 0.8)
		_disc("LowerArm." + side, elbow, 0.075 * w, joint)
		var hand_bone := "PalmI." + side
		_limb("LowerArm." + side, hand_bone, Vector3.ZERO, Vector2(0.075, 0.075) * w, frame, 0.0, 1.0, true)
		if side == "L":
			_limb("LowerArm." + side, hand_bone, Vector3.ZERO, Vector2(0.16, 0.16) * w, shell, 0.12, 0.88)
			# Three claws and a thumb at the wrist.
			var wrist := _rest_at(hand_bone)
			var along := (wrist - elbow).normalized()
			var hand := Node3D.new()
			_piece(hand, "Palm", BoxMesh.new(), frame, wrist + along * 0.03 * w, Vector3(0.09, 0.09, 0.09) * w)
			for c in 3:
				var tip := wrist + along * 0.12 * w + Vector3(0, 0, (c - 1) * 0.03 * w)
				_strand(hand, "Claw", tube, joint, wrist + along * 0.06 * w + Vector3(0, 0, (c - 1) * 0.03 * w), tip, 0.022 * w)
			_hang_at(hand, "AndroidHand" + side, hand_bone, Vector3.ZERO)
		var hip := _rest_at("UpperLeg." + side)
		var knee := _rest_at("LowerLeg." + side)
		var foot := _rest_at("Foot." + side)
		var leg_out := Vector3(signf(hip.x), 0.0, 0.0)
		_disc("UpperLeg." + side, hip + leg_out * 0.06 * w, 0.1 * w, joint)
		_limb("UpperLeg." + side, "LowerLeg." + side, Vector3.ZERO, Vector2(0.13, 0.13) * w, frame, 0.0, 1.0, true)
		_limb("UpperLeg." + side, "LowerLeg." + side, Vector3.ZERO, Vector2(0.19, 0.17) * w, shell, 0.08, 0.82)
		_limb("UpperLeg." + side, "LowerLeg." + side, leg_out * 0.097 * w, Vector2(0.012, 0.012) * w, lit, 0.2, 0.72)
		var knee_guard := Node3D.new()
		_piece(knee_guard, "KneeGuard", BoxMesh.new(), shell, Vector3.ZERO, Vector3(0.14, 0.14, 0.06) * w)
		_piece(knee_guard, "KneeLight", BoxMesh.new(), lit, Vector3(0, 0.02 * w, -0.032 * w), Vector3(0.05, 0.015, 0.01) * w)
		_hang_at(knee_guard, "AndroidKnee" + side, "LowerLeg." + side, knee + Vector3(0, 0, -0.08 * w))
		_limb("LowerLeg." + side, "Foot." + side, Vector3.ZERO, Vector2(0.11, 0.11) * w, frame, 0.0, 0.92, true)
		_limb("LowerLeg." + side, "Foot." + side, Vector3.ZERO, Vector2(0.16, 0.14) * w, shell, 0.1, 0.72, false,
				Vector3(0, 0, -0.015 * w))
		var boot := Node3D.new()
		_block(boot, "Boot", frame, foot.y, [-0.075 * w, 0.075 * w, -0.2 * w, 0.08 * w],
				foot.y + 0.09 * k, [-0.065 * w, 0.065 * w, -0.08 * w, 0.07 * w])
		_piece(boot, "Toe", BoxMesh.new(), shell, Vector3(0, foot.y + 0.035 * k, -0.16 * w), Vector3(0.13, 0.06, 0.1) * w)
		var heel_side := Vector3(foot.x, 0.0, foot.z)
		for piece in boot.get_children():
			(piece as Node3D).position += heel_side
		_hang_at(boot, "AndroidBoot" + side, "Foot." + side, Vector3.ZERO)


## The parts the android was built of, for its arm weapon.
var _android_parts := {}
## The weapon its arm is built as, and the node that holds it.
var _arm_weapon_of: Weapon
var _arm_weapon_node: Node3D
## The end of the barrel of an arm gun (`_on_fired` flashes there).
var _arm_muzzle: Node3D
## How far the gun arm is raised along the aim (0 to 1), and how fast.
var _arm_raise := 0.0
var arm_raise_rate := 5.0


## Builds the android's right forearm as the weapon in its hand: a gun is
## an armored housing over the forearm with a barrel out past the wrist,
## lit coils round it and a lit muzzle (a colossus's lance is longer, with
## more coils and prongs at its end); a blade is a guard over the wrist and
## a long blade out of it, lit along the edge. Rebuilt when the weapon
## changes. View only: what the weapon does is its own stats.
func _update_arm_weapon() -> void:
	var weapon := actor.get_active_weapon()
	if weapon == null and not actor.weapons.is_empty():
		weapon = actor.weapons[0]
	if weapon == _arm_weapon_of and (weapon == null or is_instance_valid(_arm_weapon_node)):
		return
	_arm_weapon_of = weapon
	if is_instance_valid(_arm_weapon_node):
		_arm_weapon_node.queue_free()
	_arm_weapon_node = null
	_arm_muzzle = null
	if weapon == null or _android_parts.is_empty():
		return
	var k: float = _android_parts["k"]
	var w: float = k * float(_android_parts["bulk"])
	var heavy: bool = _android_parts["heavy"]
	var shell: Material = _android_parts["shell"]
	var frame: Material = _android_parts["frame"]
	var joint: Material = _android_parts["joint"]
	var lit: Material = _android_parts["lit"]
	var elbow := _rest_at("LowerArm.R")
	var wrist := _rest_at("PalmI.R")
	var y := (wrist - elbow).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.UP).normalized()
	var z := x.cross(y).normalized()
	# The weapon's own frame: +y out along the forearm, origin at the wrist.
	var at := Transform3D(Basis(x, y, z), wrist)
	var root := Node3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 10
	var put := func(piece_name: String, mesh: PrimitiveMesh, mat: Material, local: Vector3, size: Vector3) -> void:
		var part := _piece(root, piece_name, mesh, mat, Vector3.ZERO, Vector3.ONE)
		part.transform = at * Transform3D(Basis.from_scale(size), local)
	var forearm := (wrist - elbow).length()
	if weapon is Gun:
		var reach := (0.75 if heavy else 0.36) * w
		put.call("Housing", BoxMesh.new(), shell, Vector3(0, -forearm * 0.4, 0), Vector3(0.17 * w, forearm * 0.9, 0.17 * w))
		put.call("Breech", BoxMesh.new(), frame, Vector3(0, 0.03 * w, 0), Vector3(0.14 * w, 0.12 * w, 0.14 * w))
		put.call("Rail", BoxMesh.new(), frame, Vector3(0, -forearm * 0.35, -0.095 * w), Vector3(0.05 * w, forearm * 0.7, 0.03 * w))
		put.call("Seam", BoxMesh.new(), lit, Vector3(0.087 * w, -forearm * 0.4, 0), Vector3(0.01 * w, forearm * 0.7, 0.01 * w))
		put.call("Barrel", tube, joint, Vector3(0, 0.09 * w + reach * 0.5, 0), Vector3(0.06 * w, reach, 0.06 * w))
		var coils := 4 if heavy else 2
		for i in coils:
			put.call("Coil", tube, lit, Vector3(0, 0.12 * w + reach * (i + 0.5) / float(coils + 1), 0), Vector3(0.09 * w, 0.02 * w, 0.09 * w))
		put.call("Muzzle", tube, frame, Vector3(0, 0.09 * w + reach, 0), Vector3(0.1 * w, 0.05 * w, 0.1 * w))
		put.call("Bore", tube, lit, Vector3(0, 0.09 * w + reach + 0.026 * w, 0), Vector3(0.05 * w, 0.005 * w, 0.05 * w))
		if heavy:
			for side: float in [-1.0, 1.0]:
				put.call("Prong", BoxMesh.new(), shell, Vector3(side * 0.07 * w, 0.09 * w + reach * 0.85, 0),
						Vector3(0.025 * w, reach * 0.35, 0.05 * w))
		_arm_muzzle = Node3D.new()
		_arm_muzzle.name = "ArmMuzzle"
		_arm_muzzle.transform = at * Transform3D(Basis.IDENTITY, Vector3(0, 0.12 * w + reach, 0))
		root.add_child(_arm_muzzle)
		# Tracers, beams and the flash leave the arm (`Gun.muzzle_point`).
		if weapon.visual:
			weapon.visual.set_meta("drawn_muzzle", _arm_muzzle)
	else:
		var blade := (1.2 if heavy else 0.8) * w
		put.call("Guard", BoxMesh.new(), shell, Vector3(0, -forearm * 0.3, 0), Vector3(0.16 * w, forearm * 0.75, 0.16 * w))
		put.call("Hilt", BoxMesh.new(), frame, Vector3(0, 0.04 * w, 0), Vector3(0.12 * w, 0.1 * w, 0.18 * w))
		put.call("Blade", BoxMesh.new(), joint, Vector3(0, 0.08 * w + blade * 0.5, 0.02 * w), Vector3(0.03 * w, blade, 0.13 * w))
		put.call("Edge", BoxMesh.new(), lit, Vector3(0, 0.08 * w + blade * 0.5, -0.05 * w), Vector3(0.034 * w, blade * 0.95, 0.015 * w))
	_arm_weapon_node = _hang_at(root, "ArmWeapon", "LowerArm.R", Vector3.ZERO)
	if _detail_every > 1:
		_gear_shadows(false)


## Raises an android's gun arm along the aim while it fights: the elbow
## straightened and the arm swung from the shoulder so the barrel in the
## forearm points where it shoots. Blended in and out (`_arm_raise`). A
## hook in the skeleton's modifier order, after the clip; view only.
func _aim_arm() -> void:
	if _arm_raise <= 0.0 or _skeleton == null or actor == null:
		return
	var upper := _skeleton.find_bone("UpperArm.R")
	var lower := _skeleton.find_bone("LowerArm.R")
	var hand := _skeleton.find_bone("PalmI.R")
	if upper < 0 or lower < 0 or hand < 0:
		return
	var wgt := smoothstep(0.0, 1.0, _arm_raise)
	var dir := actor.cmd.aim_dir if actor.cmd.aim_dir.length() > 0.5 \
			else Basis.from_euler(Vector3(actor.cmd.pitch, actor.cmd.yaw, 0.0)) * Vector3.FORWARD
	var want := (_skeleton.global_transform.affine_inverse().basis * dir).normalized()
	# Each bone in turn swung so the next joint lies along the aim, from
	# the bones' own offsets (the poses below are not refreshed mid-hook).
	var upper_pose := _skeleton.get_bone_global_pose(upper)
	upper_pose.basis = _swung(upper_pose.basis, upper_pose.basis * _skeleton.get_bone_pose_position(lower), want, wgt)
	_skeleton.set_bone_global_pose(upper, upper_pose)
	var local := Transform3D(Basis(_skeleton.get_bone_pose_rotation(lower)).scaled(_skeleton.get_bone_pose_scale(lower)),
			_skeleton.get_bone_pose_position(lower))
	var lower_pose := upper_pose * local
	lower_pose.basis = _swung(lower_pose.basis, lower_pose.basis * _skeleton.get_bone_pose_position(hand), want, wgt)
	_skeleton.set_bone_global_pose(lower, lower_pose)


## `basis` turned by `weight` of the arc that takes `along` onto `want`.
static func _swung(basis: Basis, along: Vector3, want: Vector3, weight: float) -> Basis:
	if along.length() < 0.0001:
		return basis
	var turn := Quaternion(along.normalized(), want)
	return Basis(Quaternion.IDENTITY.slerp(turn, weight)) * basis


## A boss's regalia (a skin's "regalia"), over its own plate, so a boss
## reads as the one person on the field who leads: a cloak from the
## shoulders and what it carries on its back or brow. "warlord" (Ashfront):
## a long black cloak hemmed in gold and a banner on a pole over its
## shoulders in its army's colour. "baron" (the Dune Sea): a sand-torn cloak
## in strips and a salvaged engine block on its back, two exhaust stacks
## glowing over its shoulders. "crown" (the Basalt Rift): a crown of basalt
## spikes lit with lava, and a black cloak with a burning hem. The cloak is
## in two panels, the upper on the chest and the lower on the hips, so it
## follows the body as it moves. View only.
func _build_regalia(kind: String) -> void:
	if _skeleton == null or _skeleton.find_bone("Chest") < 0:
		return
	var s := float(_def.get("height", 1.8)) / 1.8
	var chest := _rest_at("Chest")
	var hips := _rest_at("Hips")
	var head := _rest_at("Head")
	var knee := _rest_at("LowerLeg.L")
	var cloth_color := Color(0.09, 0.085, 0.08)
	var trim_color := Color(0.75, 0.58, 0.25)
	var trim_glow := 0.0
	match kind:
		"baron":
			cloth_color = Color(0.46, 0.38, 0.27)
			trim_color = Color(0.3, 0.24, 0.17)
		"crown":
			cloth_color = Color(0.07, 0.06, 0.06)
			trim_color = Color(1.0, 0.42, 0.1)
			trim_glow = 2.2
	var cloth := _solid(cloth_color, 0.0)
	cloth.metallic = 0.0
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trim := _solid(trim_color, trim_glow)
	if trim_glow <= 0.0:
		trim.metallic = 0.7
		trim.roughness = 0.35
	var back := 0.17 * s
	var top := chest.y + 0.16 * s
	var mid := hips.y + 0.02 * s
	var hem := knee.y - (0.05 if kind == "baron" else 0.12) * s
	# The upper cloak, from the shoulders to the waist, flaring a little.
	var upper := Node3D.new()
	var panel := _piece(upper, "Cloak", BoxMesh.new(), cloth, Vector3(0, (top + mid) * 0.5, chest.z + back),
			Vector3(0.5 * s, top - mid, 0.02 * s))
	panel.rotation.x = 0.08
	for side: float in [-1.0, 1.0]:
		_piece(upper, "Clasp", BoxMesh.new(), trim, Vector3(side * 0.17 * s, top - 0.02 * s, chest.z - 0.05 * s),
				Vector3(0.07, 0.07, 0.03) * s)
		var drape := _piece(upper, "Drape", BoxMesh.new(), cloth, Vector3(side * 0.2 * s, top - 0.03 * s, chest.z + 0.04 * s),
				Vector3(0.16 * s, 0.05 * s, 0.26 * s))
		drape.rotation.z = side * -0.35
	_hang_at(upper, "CloakUpper", "Chest", Vector3.ZERO)
	# The lower cloak, from the waist to below the knee, wider at its hem.
	var lower := Node3D.new()
	if kind == "baron":
		# Torn into strips of different lengths.
		for i in 6:
			var x := (i - 2.5) * 0.095 * s
			var drop := (mid - hem) * (0.75 + 0.25 * sin(i * 2.7))
			var strip := _piece(lower, "CloakStrip", BoxMesh.new(), cloth, Vector3(x, mid - drop * 0.5, chest.z + back + 0.03 * s),
					Vector3(0.09 * s, drop, 0.02 * s))
			strip.rotation = Vector3(0.12, 0.0, x * 0.25)
	else:
		var skirt := _piece(lower, "Cloak", BoxMesh.new(), cloth, Vector3(0, (mid + hem) * 0.5, chest.z + back + 0.04 * s),
				Vector3(0.6 * s, mid - hem, 0.02 * s))
		skirt.rotation.x = 0.14
		var band := _piece(lower, "Hem", BoxMesh.new(), trim, Vector3(0, hem + 0.025 * s, chest.z + back + 0.04 * s + (mid - hem) * 0.5 * sin(0.14)),
				Vector3(0.61 * s, 0.045 * s, 0.025 * s))
		band.rotation.x = 0.14
	_hang_at(lower, "CloakLower", "Hips", Vector3.ZERO)
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
	match kind:
		"warlord":
			# A banner pole over the right shoulder, a crossbar and the
			# army's colour hanging from it, a gold finial on top.
			var flag := Node3D.new()
			var pole_x := 0.14 * s
			var pole_z := chest.z + back + 0.06 * s
			var foot := chest.y - 0.2 * s
			var tip := head.y + 0.75 * s
			_strand(flag, "Pole", tube, _solid(Color(0.16, 0.14, 0.12), 0.0), Vector3(pole_x, foot, pole_z), Vector3(pole_x, tip, pole_z), 0.025 * s)
			_piece(flag, "Finial", horn, trim, Vector3(pole_x, tip + 0.06 * s, pole_z), Vector3(0.05, 0.12, 0.05) * s)
			_piece(flag, "Crossbar", BoxMesh.new(), trim, Vector3(pole_x - 0.12 * s, tip - 0.04 * s, pole_z), Vector3(0.28, 0.025, 0.025) * s)
			var banner := _solid(actor.body_color.darkened(0.15), 0.0)
			banner.metallic = 0.0
			banner.roughness = 0.9
			banner.cull_mode = BaseMaterial3D.CULL_DISABLED
			_piece(flag, "Banner", BoxMesh.new(), banner, Vector3(pole_x - 0.12 * s, tip - 0.28 * s, pole_z), Vector3(0.26, 0.44, 0.012) * s)
			_piece(flag, "BannerMark", BoxMesh.new(), trim, Vector3(pole_x - 0.12 * s, tip - 0.24 * s, pole_z - 0.008 * s), Vector3(0.1, 0.1, 0.01) * s)
			_hang_at(flag, "Banner", "Chest", Vector3.ZERO)
		"baron":
			# An engine block strapped to the back, two exhaust stacks up
			# over the shoulders, their mouths glowing.
			var engine := Node3D.new()
			var block_z := chest.z + back + 0.1 * s
			_piece(engine, "Block", BoxMesh.new(), _solid(Color(0.3, 0.27, 0.24), 0.0), Vector3(0, chest.y - 0.02 * s, block_z),
					Vector3(0.34, 0.3, 0.18) * s)
			_piece(engine, "Stripe", BoxMesh.new(), _solid(Color(0.75, 0.6, 0.15), 0.0), Vector3(0, chest.y + 0.08 * s, block_z + 0.092 * s),
					Vector3(0.3, 0.05, 0.01) * s)
			var heat := _solid(Color(1.0, 0.5, 0.15), 2.4)
			for side: float in [-1.0, 1.0]:
				var from := Vector3(side * 0.12 * s, chest.y + 0.1 * s, block_z)
				var to := from + Vector3(side * 0.05, 0.5, 0.05) * s
				_strand(engine, "Stack", tube, _solid(Color(0.22, 0.2, 0.19), 0.0), from, to, 0.055 * s)
				_piece(engine, "StackGlow", tube, heat, to + Vector3(0, 0.005 * s, 0), Vector3(0.045, 0.01, 0.045) * s)
			_hang_at(engine, "Engine", "Chest", Vector3.ZERO)
		"crown":
			# A ring of basalt spikes over the brow, lit at their tips.
			var crown := Node3D.new()
			var basalt := _solid(Color(0.12, 0.11, 0.11), 0.0)
			var lava := _solid(Color(1.0, 0.42, 0.1), 2.8)
			var ring_y := head.y + 0.07 * s
			for i in 7:
				var a := (i - 3) * 0.42
				var at := Vector3(sin(a) * 0.12 * s, ring_y, head.z - cos(a) * 0.1 * s + 0.02 * s)
				var tall := (0.26 - absf(i - 3) * 0.04) * s
				var spike := _piece(crown, "CrownSpike", horn, basalt, at + Vector3(0, tall * 0.5, 0), Vector3(0.04 * s, tall, 0.04 * s))
				spike.rotation = Vector3(-0.2, 0.0, -sin(a) * 0.35)
				_piece(crown, "CrownGlow", BoxMesh.new(), lava, at + Vector3(0, tall * 0.25, -0.02 * s), Vector3(0.012, tall * 0.4 / s, 0.01) * s)
			_piece(crown, "CrownBand", tube, basalt, Vector3(0, ring_y, head.z + 0.02 * s), Vector3(0.26, 0.04, 0.24) * s)
			_hang_at(crown, "Crown", "Head", Vector3.ZERO)


## A plain fighter's own touches (a skin's "gear"), so a marksman or a
## runner reads apart from the rifleman whose clothes it shares. "hood": a
## marksman's hood framing the face and a short cape over the shoulders,
## in its army's colour, darkened. "scarf": a runner's scarf wound round
## the neck, its tails flying behind. "nomad": a desert raider's wrap round
## the head, a gaiter pulled up over the mouth and nose, goggles on a strap
## and a sash across the chest. "duster": the nomad's gaiter and goggles
## under a hood, a cape and a long coat open at the front, for the
## marksman. Rounded pieces fitted round the head (the "Head" bone's rest,
## its middle about 0.1 above it) and hung on the head, chest and hips.
## View only.
func _build_gear(kind: String) -> void:
	if _skeleton == null or _skeleton.find_bone("Chest") < 0 or _skeleton.find_bone("Head") < 0:
		return
	var s := float(_def.get("height", 1.8)) / 1.8
	var chest := _rest_at("Chest")
	var hips := _rest_at("Hips")
	var head := _rest_at("Head")
	var knee := _rest_at("LowerLeg.L") if _skeleton.find_bone("LowerLeg.L") >= 0 else hips - Vector3(0, 0.45 * s, 0)
	var army := actor.body_color if actor != null else Color(0.5, 0.5, 0.5)
	var cloth_color := army.darkened(0.45)
	var accent_color := army.darkened(0.2)
	if kind == "nomad" or kind == "duster":
		cloth_color = Color(0.7, 0.6, 0.44)
		accent_color = Color(0.45, 0.22, 0.17)
	var cloth := _cloth(cloth_color)
	var accent := _cloth(accent_color)
	var drum := CylinderMesh.new()
	drum.top_radius = 0.5
	drum.bottom_radius = 0.5
	drum.height = 1.0
	drum.radial_segments = 16
	drum.rings = 1
	var flare := drum.duplicate() as CylinderMesh
	flare.top_radius = 0.28
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 16
	ball.rings = 8
	var hooded := kind == "hood" or kind == "duster"
	var wrapped := kind == "nomad" or kind == "duster"
	var h := head.y
	var mid := Vector3(0, h + 0.1 * s, head.z)
	var face := Node3D.new()
	if hooded:
		# Set back from the face so the face shows inside its rim, and a
		# cowl under the chin.
		var hood := cloth if kind == "hood" else _cloth(cloth_color.darkened(0.42))
		_piece(face, "Hood", ball, hood, mid + Vector3(0, 0.02, 0.055) * s, Vector3(0.225, 0.26, 0.27) * s)
		_piece(face, "Cowl", flare, hood, Vector3(0, h - 0.035 * s, head.z + 0.03 * s), Vector3(0.24, 0.07, 0.22) * s)
	elif wrapped:
		# A wrap wound drum the crown, its tail hanging behind.
		var band := TorusMesh.new()
		band.inner_radius = 0.085
		band.outer_radius = 0.118
		band.rings = 16
		band.ring_segments = 8
		_piece(face, "Wrap", band, cloth, mid + Vector3(0, 0.07, 0.005) * s, Vector3(1.0, 1.4, 1.08) * s)
		var cap := _piece(face, "Wrap", ball, cloth, mid + Vector3(0, 0.085, 0.01) * s, Vector3(0.19, 0.1, 0.215) * s)
		cap.rotation.x = 0.1
		var tail := _piece(face, "WrapTail", BoxMesh.new(), cloth, mid + Vector3(0.03, -0.03, 0.12) * s, Vector3(0.05, 0.16, 0.012) * s)
		tail.rotation = Vector3(0.25, 0.0, 0.12)
	if wrapped:
		# A gaiter pulled up over the mouth and nose.
		_piece(face, "Mask", drum, accent, mid + Vector3(0, -0.06, -0.003) * s, Vector3(0.185, 0.075, 0.215) * s)
		_piece(face, "Mask", flare, accent, Vector3(0, h - 0.025 * s, head.z + 0.01 * s), Vector3(0.21, 0.06, 0.21) * s)
		# Goggles on a strap drum the head, their lenses at the eyes.
		var rim := _solid(Color(0.16, 0.14, 0.12), 0.0)
		rim.roughness = 0.6
		var glass := _solid(Color(0.3, 0.5, 0.5), 0.0)
		glass.metallic = 0.7
		glass.roughness = 0.1
		var strap := TorusMesh.new()
		strap.inner_radius = 0.098
		strap.outer_radius = 0.106
		strap.rings = 16
		strap.ring_segments = 4
		_piece(face, "GoggleStrap", strap, rim, mid + Vector3(0, 0.025, 0.005) * s, Vector3(1.0, 1.0, 1.08) * s)
		for side: float in [-1.0, 1.0]:
			var lens := _piece(face, "Goggle", drum, rim, mid + Vector3(side * 0.036, 0.025, -0.097) * s, Vector3(0.05, 0.025, 0.045) * s)
			lens.rotation.x = PI * 0.5
			var pane := _piece(face, "GoggleGlass", drum, glass, mid + Vector3(side * 0.036, 0.025, -0.11) * s, Vector3(0.04, 0.004, 0.036) * s)
			pane.rotation.x = PI * 0.5
	if face.get_child_count() > 0:
		_hang_at(face, "GearHead", "Head", Vector3.ZERO)
	else:
		face.free()
	var upper := Node3D.new()
	var lower := Node3D.new()
	var neck := h - 0.03 * s
	match kind:
		"hood", "duster":
			# A short cape over the shoulders, a cone open at the neck.
			var cape_color := cloth_color.darkened(0.42) if kind == "duster" else cloth_color
			_piece(upper, "Cape", flare, _cloth(cape_color), Vector3(0, neck - 0.1 * s, chest.z + 0.04 * s), Vector3(0.46, 0.16, 0.27) * s)
		"scarf":
			# Wound drum the neck, knotted at the side, its tails flying.
			var wind := TorusMesh.new()
			wind.inner_radius = 0.045
			wind.outer_radius = 0.1
			wind.rings = 16
			wind.ring_segments = 8
			for i in 2:
				var loop := _piece(upper, "Scarf", wind, accent, Vector3(0, neck - (0.005 + i * 0.04) * s, chest.z + 0.005 * s),
						Vector3(1.0 - i * 0.04, 1.15, 1.0) * s)
				loop.rotation = Vector3(0.12 + i * 0.12, 0.0, 0.1 - i * 0.2)
			_piece(upper, "ScarfKnot", ball, accent, Vector3(0.06, neck - 0.05 * s, chest.z - 0.07 * s), Vector3(0.05, 0.045, 0.045) * s)
			for i in 2:
				var tail := _piece(upper, "ScarfTail", BoxMesh.new(), accent,
						Vector3((0.02 - i * 0.05) * s, neck - 0.08 * s, chest.z + (0.15 + i * 0.03) * s), Vector3(0.045, 0.2 - i * 0.04, 0.01) * s)
				tail.rotation = Vector3(0.7 + i * 0.2, 0.0, 0.08 - i * 0.2)
	if wrapped:
		# A sash from the right shoulder to the left hip, front and back.
		for z: float in [-0.115, 0.125]:
			var sash := _piece(upper, "Sash", BoxMesh.new(), accent, Vector3(0, chest.y - 0.05 * s, chest.z + z * s), Vector3(0.055, 0.52, 0.012) * s)
			sash.rotation.z = 0.62 if z < 0.0 else -0.62
	if kind == "duster":
		# A long coat open at the front: a back panel and two side panels
		# from the shoulders, flaring from the waist to the knees.
		var coat := _cloth(cloth_color.darkened(0.42))
		_piece(upper, "Coat", BoxMesh.new(), coat, Vector3(0, chest.y - 0.06 * s, chest.z + 0.115 * s), Vector3(0.34, 0.42, 0.012) * s)
		var waist := hips.y + 0.06 * s
		var hem := knee.y - 0.1 * s
		var back := _piece(lower, "Coat", BoxMesh.new(), coat, Vector3(0, (waist + hem) * 0.5, hips.z + 0.13 * s),
				Vector3(0.36 * s, waist - hem, 0.012 * s))
		back.rotation.x = 0.1
		for side: float in [-1.0, 1.0]:
			var panel := _piece(lower, "Coat", BoxMesh.new(), coat, Vector3(side * 0.16 * s, (waist + hem) * 0.5, hips.z + 0.04 * s),
					Vector3(0.012 * s, waist - hem, 0.17 * s))
			panel.rotation = Vector3(0.0, 0.0, side * 0.08)
	if upper.get_child_count() > 0:
		_hang_at(upper, "GearUpper", "Chest", Vector3.ZERO)
	else:
		upper.free()
	if lower.get_child_count() > 0 and _skeleton.find_bone("Hips") >= 0:
		_hang_at(lower, "GearLower", "Hips", Vector3.ZERO)
	else:
		lower.free()


## Matte cloth in `color`, seen from both sides.
func _cloth(color: Color) -> StandardMaterial3D:
	var mat := _solid(color, 0.0)
	mat.metallic = 0.0
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


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
	var drawn_from := from
	if is_instance_valid(_arm_muzzle) and _arm_muzzle.is_inside_tree():
		# An android's beam leaves its gun arm; what it meets is still
		# judged along the aim from the eyes.
		drawn_from = _arm_muzzle.global_position
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
	var end := from + dir * reach
	var line := end - drawn_from
	if line.length() < 0.01:
		return
	var mid := drawn_from + line * 0.5
	var along := line.normalized()
	var basis := Basis.looking_at(along, Vector3.UP if absf(along.y) < 0.99 else Vector3.RIGHT)
	# The tube stands along Y: lay it along the aim (-Z of `looking_at`).
	basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
	_beam.global_transform = Transform3D(basis.scaled_local(Vector3(width, line.length(), width)), mid)


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
## How far out armor of each weight holds the arms (`Locomotion.arm_clear`,
## metres at the elbow).
const ARM_CLEAR := {"light": 0.025, "medium": 0.035, "heavy": 0.05}
## How much thicker arm armor makes an upper arm and a forearm, for keeping
## it out of the trunk (`_teach_arm`).
const ARM_THICK := {"light": Vector2(0.02, 0.012), "medium": Vector2(0.03, 0.02), "heavy": Vector2(0.045, 0.03)}
const WEIGHT_LOOKS := {"light": "runner", "medium": "trooper", "heavy": "bulwark"}



## How heavy a frame looks: "light", "medium" or "heavy", from its tags. A
## weight itself ("heavy") or a skin's own plates ("skin:light") answer as is.
static func frame_weight(id: String) -> String:
	var bare := id.trim_prefix("skin:").get_slice(":", 0)
	if FRAME_BULK.has(bare):
		return bare
	if ItemDB.has_tag(id, "frame_heavy"):
		return "heavy"
	return "medium" if ItemDB.has_tag(id, "frame_medium") else "light"


## The look a frame wears (a `FRAME_STYLES` key).
static func frame_look(id: String) -> String:
	# A skin's own plates may name their look: "skin:<weight>:<look>".
	if id.begins_with("skin:") and FRAME_STYLES.has(id.get_slice(":", 2)):
		return id.get_slice(":", 2)
	return FRAME_LOOKS.get(id, WEIGHT_LOOKS[frame_weight(id)])


## The colours and details a frame is built in: its look's `FRAME_STYLES`
## row, worn in the armor paint `paint` (`ArmorPaint.paint_style`; "" for
## the look's own colours).
static func frame_style(id: String, paint := "") -> Dictionary:
	return ArmorPaint.paint_style(FRAME_STYLES[frame_look(id)], paint)


## The armor paint this body wears on the frame `id`: the one its
## appearance picked for the frame's look ("" for none). A skin's own
## plates wear the skin's "paint".
func frame_paint(id: String) -> String:
	if id.begins_with("skin:"):
		return str(_def.get("paint", ""))
	if id == "":
		return ""
	var paints: Variant = _appearance.get("paints", {})
	return str(paints.get(frame_look(id), "")) if typeof(paints) == TYPE_DICTIONARY else ""


## The build of this body (`Human.BUILDS`) its armor is fitted to: a
## person's own, "m" for any other skin.
func body_build() -> String:
	return str(_appearance.get("build", "m"))


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
	# Armor holds the arms out from the body, so a hanging hand clears the
	# belt and thigh plates (`tools/armor_fit/clip_check.tscn -- --arms`).
	if locomotion and "arm_clear" in locomotion:
		locomotion.set("arm_clear", ARM_CLEAR.get(frame_weight(id), 0.0) if id != "" else 0.0)
	for part in _frame_parts:
		if is_instance_valid(part):
			part.queue_free()
	_frame_parts.clear()
	_teach_arm.call_deferred()
	if id == "" or _skeleton == null:
		return
	var height: float = _def.get("height", 1.8)
	var build := body_build()
	var frame := build_frame(id, paint, build)
	frame.scale = Vector3.ONE * _body_scale
	_frame_parts.append(_hang(frame, "Frame", _def.get("back_bone", ""), frame_offset,
			Vector3(0.0, height * 0.72, 0.0) + frame_offset, true))
	var hips: String = _def.get("hip_bone", "")
	if hips != "" and _skeleton.find_bone(hips) >= 0:
		var belt := build_belt(id, paint, build)
		belt.scale = Vector3.ONE * _body_scale
		_frame_parts.append(_hang(belt, "Belt", hips, Vector3.ZERO, Vector3.ZERO, true))
	for side: String in ["L", "R"]:
		var out := -1.0 if side == "L" else 1.0
		for limb: Array in [["UpperArm", "LowerArm", build_pad(id, out, paint, build), Vector3(pad_offset.x * out, pad_offset.y, pad_offset.z)],
				["LowerArm", "Wrist", build_bracer(id, out, paint, build), Vector3.ZERO],
				["UpperLeg", "LowerLeg", build_tasset(id, out, paint, build), Vector3.ZERO],
				["LowerLeg", "Foot", build_shin(id, out, paint, build), Vector3.ZERO]]:
			var piece: Node3D = limb[2]
			var held := _hang_limb(piece, limb[0] + "." + side, limb[1] + "." + side, limb[3])
			if held == null:
				piece.free()
			else:
				_frame_parts.append(held)
	if _detail_every > 1:
		_gear_shadows(false)


## Shows the weapon arm the trunk and what is hung on it, so it keeps
## the arms outside both through a swing (`WeaponArm.learn_trunk`). Arm
## armor makes the arm itself thicker.
func _teach_arm() -> void:
	if arm == null or not is_instance_valid(arm) or not arm.has_method("learn_trunk"):
		return
	var weight := frame_weight(_frame_id.get_slice("|", 0)) if _frame_id != "" else ""
	arm.learn_trunk(_frame_parts.filter(func(p: Variant) -> bool: return is_instance_valid(p)),
			ARM_THICK.get(weight, Vector2.ZERO))


## Puts the worn backpack (`Actor.pack_id`) on the lower back, hung on the
## hips so it moves with them, rebuilt when another goes on. Below a back
## rig, and pushed out behind one so the two never sink into each other.
## The same model in both views. None for the field pack.
func _update_pack() -> void:
	var id := actor.pack_id
	var rig := actor.flight.enabled and actor.flight.item_id != ""
	var key := id + ("|rig" if rig else "") if id != "" else ""
	if key == _pack_key and (id == "" or (_pack_part != null and is_instance_valid(_pack_part))):
		return
	_pack_key = key
	if _pack_part != null and is_instance_valid(_pack_part):
		_pack_part.queue_free()
	_pack_part = null
	if id == "" or _skeleton == null or not ItemDB.has_item(id):
		return
	var hips: String = _def.get("hip_bone", "")
	var height: float = _def.get("height", 1.8)
	var size := int(ItemDB.item_stats(id).get("pack_size", 1))
	var color := Color(0.33, 0.31, 0.24)
	var behind := pack_offset + (pack_rig_shift if rig else Vector3.ZERO)
	_pack_part = _hang(build_backpack(size, color), "Backpack", hips if hips != "" and _skeleton.find_bone(hips) >= 0 else "",
			behind, Vector3(0.0, height * 0.55, 0.0) + behind, true)
	if _detail_every > 1:
		_gear_shadows(false)


## Keeps everything worn clear of the body and of each other (`worn_fit.gd`):
## once anything worn changes, the rig is moved back until it sits snug over
## the back or the armor, its shoulder straps laid over them, then a
## backpack, the weapons slung on the back and those on the hips are each
## moved back or out to their side to sit snug over what is already there,
## in that order. Worked out from the body at rest, once per kit and build
## (`_fits`); the gear then moves with its bones as before. View only.
func _fit_worn() -> void:
	# Only a person's body is measured (`body_fit.gd`).
	if _skeleton == null or _appearance.is_empty():
		return
	var stowed := []
	for weapon in actor.weapons:
		var root: Node3D = _stowed.get(weapon)
		if root != null and is_instance_valid(root) and root.has_meta("fit"):
			stowed.append([weapon.item_id, root])
	var clip: Node3D = _helmet_clip if _helmet_clip != null and is_instance_valid(_helmet_clip) \
			and _helmet_model != null and is_instance_valid(_helmet_model) else null
	var key := "%s|%.3f|%s|%s|%s|%s" % [body_build(), _body_scale, _frame_id, _rig_id, _pack_key, _helmet_id if clip else ""]
	var nodes := str(_rig_back.get_instance_id() if _rig_back else 0) + str(_pack_part.get_instance_id() if _pack_part else 0) \
			+ str(clip.get_instance_id() if clip else 0)
	for item: Array in stowed:
		key += "|" + str(item[0])
		nodes += "|" + str((item[1] as Node).get_instance_id())
	if key + nodes == _fit_key:
		return
	_fit_key = key + nodes
	if _rig_holders.is_empty() and _pack_part == null and stowed.is_empty() and clip == null:
		return
	if not _fits.has(key):
		# A new kit is worked out once for every body that wears it, at
		# most one a frame, so a crowd arriving at once never stalls one.
		var frame := Engine.get_process_frames()
		if _fit_frame == frame:
			_fit_key = ""
			return
		_fit_frame = frame
		_fits[key] = _work_out_fit(stowed, clip)
	var fit: Dictionary = _fits[key]
	var rig_holder := _rig_holder()
	if rig_holder:
		_set_fit(rig_holder, fit["rig"])
		_lay_straps(rig_holder, fit["straps"])
	var k := 0
	for held in _rig_holders:
		if is_instance_valid(held) and held != rig_holder and k < (fit["widen"] as Array).size():
			var grow: Vector2 = fit["widen"][k]
			for part in _held_part(held).get_children():
				RigModel.fit_boot(part, -1.0 if str(part.name).ends_with("L") else 1.0, grow)
			k += 1
	if _pack_part != null and is_instance_valid(_pack_part):
		_set_fit(_pack_part, fit["pack"])
	for i in stowed.size():
		_set_fit(stowed[i][1], (fit["stowed"] as Array)[i])
	if clip:
		_set_fit(clip, fit["clip"])


## Worked-out fits, by kit and build: {"rig", "pack", "clip" (actor frame
## moves), "stowed" (one move per weapon in order), "straps" (each strap's
## points and which way is out, actor frame), "widen" (how much wider each
## boot thruster's cuff is opened across and front to back, metres)}.
static var _fits := {}
static var _fit_frame := -1
var _fit_key := ""


func _work_out_fit(stowed: Array, clip: Node3D) -> Dictionary:
	var shape := WornFit.new(body_build(), _frame_id.get_slice("|", 0), _body_scale, _fit_shift(), _armor_points)
	var out := {"rig": Vector3.ZERO, "pack": Vector3.ZERO, "clip": Vector3.ZERO, "stowed": [], "straps": [], "widen": []}
	var rig_holder := _rig_holder()
	var rig_move := Vector3.ZERO
	if rig_holder:
		var straps := _strap_paths(shape)
		out["straps"] = straps
		for strap: Array in straps:
			shape.add_points(strap[0])
		var points := _hung_points(rig_holder, ["Straps", "FitStraps"])
		rig_move = Vector3(0.0, 0.0, shape.back_gap(points, worn_clear))
		out["rig"] = rig_move
		shape.add_points(_moved(points, rig_move))
	# Boot thrusters' cuffs are widened round the leg and anything on it.
	var widen := []
	for held in _rig_holders:
		if is_instance_valid(held) and held != rig_holder:
			var holder := _held_part(held)
			var at: Vector3 = ((holder.get_meta("bone_at") as Transform3D) * (holder.get_meta("rest") as Transform3D)).origin
			var rx := RigModel.CUFF_INNER
			var rz := RigModel.CUFF_INNER * RigModel.CUFF_DEPTH
			var s := shape.widen(at + Vector3(0.0, 0.0, RigModel.CUFF_Z), at.y, at.y + RigModel.CUFF_TOP + 0.01, rx, rz, worn_clear)
			widen.append(Vector2(rx * (s.x - 1.0), rz * (s.y - 1.0)))
	out["widen"] = widen
	# What is clamped to the rig's rails goes with it.
	var moves := {}
	for i in stowed.size():
		if (stowed[i][1] as Node).get_meta("fit") == "rail":
			moves[i] = rig_move
			shape.add_points(_moved(_hung_points(stowed[i][1]), rig_move))
	if _pack_part != null and is_instance_valid(_pack_part):
		var points := _hung_points(_pack_part)
		out["pack"] = Vector3(0.0, 0.0, shape.back_gap(points, worn_clear))
		shape.add_points(_moved(points, out["pack"]))
	for kind: String in ["back", "right", "left"]:
		for i in stowed.size():
			if (stowed[i][1] as Node).get_meta("fit") != kind:
				continue
			var points := _hung_points(stowed[i][1], [], true)
			var move := Vector3(0.0, 0.0, shape.back_gap(points, worn_clear, 1)) if kind == "back" \
					else Vector3((1.0 if kind == "right" else -1.0) * shape.side_gap(points, 1.0 if kind == "right" else -1.0, hip_clear, 1), 0.0, 0.0)
			moves[i] = move
			shape.add_points(_moved(points, move))
	for i in stowed.size():
		(out["stowed"] as Array).append(moves.get(i, Vector3.ZERO))
	if clip:
		# The helmet as it hangs on its clip, off the left hip.
		var holder := _held_part(clip)
		var at: Transform3D = (holder.get_meta("bone_at") as Transform3D) * (holder.get_meta("rest") as Transform3D)
		# Over its faces: round, the box round it would hold it well off.
		var points := PackedVector3Array()
		for p in WornFit.cloud(_helmet_model):
			points.append(at * p)
		out["clip"] = Vector3(-shape.side_gap(points, -1.0, hip_clear, 1), 0.0, 0.0)
	return out


## Where this body stands against its measurements (`body_fit.gd`,
## scaled by `_body_scale`), actor frame.
func _fit_shift() -> Vector3:
	var hips: String = _def.get("hip_bone", "")
	if hips == "" or _skeleton.find_bone(hips) < 0:
		return Vector3.ZERO
	return _rest_at(hips) - BodyFit.bone(body_build(), "Hips") * _body_scale


## The worn frame's points over its faces, actor frame.
func _armor_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for part in _frame_parts:
		if is_instance_valid(part):
			points.append_array(_hung_points(part, [], true))
	return points


## The rig's part on the back, or null.
func _rig_holder() -> Node3D:
	if _rig_back == null or not is_instance_valid(_rig_back):
		return null
	for held in _rig_holders:
		if is_instance_valid(held) and _held_part(held).is_ancestor_of(_rig_back):
			return held
	return null


## Points over what `hung` holds (see `_hang`) as it hangs at rest with no
## fit, actor frame: over its faces when `faces` (`WornFit.cloud`), else over the boxes round
## its meshes (`WornFit.boxes`).
func _hung_points(hung: Node3D, skip: Array = [], faces := false) -> PackedVector3Array:
	var holder := _held_part(hung)
	var at: Transform3D = (holder.get_meta("bone_at") as Transform3D) * (holder.get_meta("rest") as Transform3D)
	var out := PackedVector3Array()
	for child in holder.get_children():
		if child is Node3D:
			var xf := at * (child as Node3D).transform
			if faces:
				for p in WornFit.cloud(child, skip):
					out.append(xf * p)
			else:
				out.append_array(WornFit.boxes(child, xf, skip, true))
	return out


static func _moved(points: PackedVector3Array, by: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] + by
	return out


## Moves what `hung` holds by `move` (actor frame) from where it hangs.
func _set_fit(hung: Node3D, move: Vector3) -> void:
	var holder := _held_part(hung)
	if not holder.has_meta("rest"):
		return
	var local := (holder.get_meta("bone_at") as Transform3D).basis.inverse() * move
	holder.set_meta("fit", local)
	var rest: Transform3D = holder.get_meta("rest")
	holder.transform = Transform3D(rest.basis, rest.origin + local)


## The fit move of a holder, in its parent's frame.
func _fit_offset(holder: Node3D) -> Vector3:
	return holder.get_meta("fit", Vector3.ZERO)


## How far worn gear stands off what is under it.
var worn_clear := 0.006
## The same for what hangs on a hip, more since the thigh under it swings
## out a little as the body moves from its rest pose.
var hip_clear := 0.012
## How far a rig's shoulder strap stands off the skin or armor, and how
## thick and wide it is.
var strap_clear := 0.005
var strap_thick := 0.007


## A back rig's two shoulder straps over the body as worn: from under the
## harness plate up the back, over the top of the shoulder and down the
## chest, laid on whatever is there by casting in from outside. Each is
## [points, out] in the actor's frame.
func _strap_paths(shape: WornFit) -> Array:
	var build := body_build()
	var holder := _held_part(_rig_holder())
	var origin: Vector3 = ((holder.get_meta("bone_at") as Transform3D) * (holder.get_meta("rest") as Transform3D)).origin
	var axis := BodyFit.axis_z() * _body_scale + _fit_shift().z
	var top := BodyFit.bone(build, "Neck").y * _body_scale + _fit_shift().y - 0.06
	var back_low := origin.y + RigModel.HARNESS_TOP - 0.06
	var front_low := top - 0.24
	var paths := []
	for side: float in [-1.0, 1.0]:
		var x := side * RigModel.STRAP_X
		var points := PackedVector3Array()
		var outs := PackedVector3Array()
		# Up the back, under the harness plate.
		var half := RigModel.STRAP_WIDTH * 0.5
		var y := back_low
		while y < top:
			points.append(Vector3(x, y, shape.surface_z(x - half, x + half, y, 1.0, strap_clear, axis)))
			outs.append(Vector3.BACK)
			y += 0.02
		# Over the shoulder, back to front.
		var reach := PackedFloat32Array()
		var dirs := PackedVector3Array()
		for i in 29:
			var phi := lerpf(0.0, PI, i / 28.0)
			dirs.append(Vector3(0.0, sin(phi), cos(phi)))
			reach.append(_strap_cast(shape, Vector3(x, top, axis), dirs[i]))
		for i in reach.size():
			# A ray that slips through a gap in a thin collar would pull the
			# strap in through it: none dips below both its neighbours.
			var r := reach[i]
			if i > 0 and i < reach.size() - 1:
				r = maxf(r, minf(reach[i - 1], reach[i + 1]))
			points.append(Vector3(x, top, axis) + dirs[i] * r)
			outs.append(dirs[i])
		# Down the chest.
		y = top - 0.02
		while y > front_low:
			points.append(Vector3(x, y, shape.surface_z(x - half, x + half, y, -1.0, strap_clear, axis)))
			outs.append(Vector3.FORWARD)
			y -= 0.02
		paths.append([points, outs])
	return paths


## How far along the ray from `from` along `dir` a strap crosses it: as far
## out as its widest reach across, so neither edge sinks in where the
## surface under it curves.
func _strap_cast(shape: WornFit, from: Vector3, dir: Vector3) -> float:
	var best := -INF
	for k in 3:
		var off := Vector3.RIGHT * RigModel.STRAP_WIDTH * (k / 2.0 - 0.5)
		best = maxf(best, (shape.cast_in(from + off, dir, 0.4, strap_clear) - from - off).dot(dir))
	return best


## Lays the fitted straps on the rig, in place of its own.
func _lay_straps(rig: Node3D, paths: Array) -> void:
	var holder := _held_part(rig)
	var own := _rig_back.get_node_or_null("Straps") as Node3D
	var old := holder.get_node_or_null("FitStraps")
	if old:
		old.free()
	if paths.is_empty() or own == null:
		return
	own.visible = false
	var to_rig := ((holder.get_meta("bone_at") as Transform3D) * holder.transform).affine_inverse()
	var node := Node3D.new()
	node.name = "FitStraps"
	holder.add_child(node)
	var strap_mat := StandardMaterial3D.new()
	strap_mat.albedo_color = RigModel.STRAP
	strap_mat.roughness = 0.9
	strap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var steel := StandardMaterial3D.new()
	steel.albedo_color = RigModel.STEEL
	steel.metallic = 0.6
	steel.roughness = 0.4
	for path: Array in paths:
		var points: PackedVector3Array = path[0]
		var outs: PackedVector3Array = path[1]
		var local := PackedVector3Array()
		var dirs := PackedVector3Array()
		for i in points.size():
			local.append(to_rig * points[i])
			dirs.append(to_rig.basis * outs[i])
		var strap := MeshInstance3D.new()
		strap.mesh = _ribbon(local, dirs, RigModel.STRAP_WIDTH, strap_thick)
		strap.material_override = strap_mat
		node.add_child(strap)
		# A buckle where it ends on the chest.
		var end := local[local.size() - 1]
		var buckle := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(RigModel.STRAP_WIDTH * 0.8, 0.03, 0.008)
		buckle.mesh = box
		buckle.material_override = steel
		buckle.position = end + dirs[dirs.size() - 1].normalized() * (strap_thick + 0.003) + Vector3(0, 0.02, 0)
		node.add_child(buckle)
	look._weather_model(node, 0.5, 0.6)


## A flat strap along `points`, its back on them and its face toward `outs`.
static func _ribbon(points: PackedVector3Array, outs: PackedVector3Array, width: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for i in points.size():
		var along := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var up := outs[i].normalized()
		var across := along.cross(up).normalized() * width * 0.5
		var face := up * thick
		rings.append([points[i] - across, points[i] + across, points[i] + across + face, points[i] - across + face])
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in 4:
			var k1 := (k + 1) % 4
			st.add_vertex(a[k])
			st.add_vertex(b[k])
			st.add_vertex(b[k1])
			st.add_vertex(a[k])
			st.add_vertex(b[k1])
			st.add_vertex(a[k1])
	for end: Array in [rings[0], rings[rings.size() - 1]]:
		st.add_vertex(end[0])
		st.add_vertex(end[1])
		st.add_vertex(end[2])
		st.add_vertex(end[0])
		st.add_vertex(end[2])
		st.add_vertex(end[3])
	st.generate_normals()
	return st.commit()


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
	part.basis = Basis(up.cross(-front).normalized(), up, -front).scaled(Vector3.ONE * _body_scale)
	return held


## Everyone wears the tactical suit (`Human.suit_for`); under a frame it
## takes the frame look's colours, the cuffs lit in its accent. `style`
## empty gives each part its own suit back. View only; the appearance is
## untouched.
func _wear_undersuit(style: Dictionary) -> void:
	for mat in _materials:
		if not mat.has_meta("own_suit"):
			continue
		var own: Dictionary = mat.get_meta("own_suit")
		var feet: bool = mat.get_meta("suit_slot", "") == "feet"
		var cloth: Color = style["suit"] if not style.is_empty() else own["color"]
		if not style.is_empty() and feet:
			cloth = cloth.darkened(0.4)
		mat.set_shader_parameter("suit_color", cloth)
		mat.set_shader_parameter("suit_trim", style["accent"] if not style.is_empty() else own["trim"])


## A frame's carrier and plates, front toward -Z, built round the chest
## bone (`armor_model.gd`): its weight sets the bulk and coverage, its look
## (`FRAME_STYLES`, in its armor paint, `frame_style`) the colours and the
## details. `id` is a frame's item id, a weight or "skin:<weight>". One mesh per material; the named plates are
## in its "parts" meta (`GearShapes.has_part`).
static func build_frame(id: String, paint := "", build := "m") -> Node3D:
	return _armor("torso", id, 0.0, paint, build)


## The frame's battle belt, built round the hips bone.
static func build_belt(id: String, paint := "", build := "m") -> Node3D:
	return _armor("belt", id, 0.0, paint, build)


## A shoulder pad for the side `out` (-1 left, 1 right): a dome over the
## shoulder and `FRAME_BULK` "pads" lames down the arm, built standing up
## the upper arm from the shoulder joint.
static func build_pad(id: String, out: float, paint := "", build := "m") -> Node3D:
	return _armor("pauldron", id, out, paint, build)


## An elbow pad and bracer for the side `out`, built down the forearm.
static func build_bracer(id: String, out: float, paint := "", build := "m") -> Node3D:
	return _armor("forearm", id, out, paint, build)


## A thigh plate (tassets) for the side `out`, built down the thigh from
## the hip; the right one carries a drop-leg pouch.
static func build_tasset(id: String, out: float, paint := "", build := "m") -> Node3D:
	return _armor("thigh", id, out, paint, build)


## A knee pad and shin guard (a greave on heavy), built down the shin.
static func build_shin(id: String, out: float, paint := "", build := "m") -> Node3D:
	return _armor("shin", id, out, paint, build)


## A frame's `piece` ("torso", "belt", "pauldron", "forearm", "thigh",
## "shin") for the side `out`, fitted to the body `build` (`Human.BUILDS`,
## `body_fit.gd`), built once per weight, look, side and build and shared
## after (`GearShapes.cached`). `paint` is an armor paint (`ArmorPaint`) or
## "" for the look's own colours. Built in the body's own metres: hung on a
## body, it is scaled by the body's size (`_body_scale`).
static func _armor(piece: String, id: String, out := 0.0, paint := "", build := "m") -> Node3D:
	var weight := frame_weight(id)
	if not ArmorPaint.PAINTS.has(paint):
		paint = ""
	build = ArmorModel.BodyFit.build_of(build)
	var style := frame_style(id, paint)
	return ArmorModel.G.cached("%s:%s:%s:%s:%s:%s" % [piece, weight, frame_look(id), out, paint, build], func() -> Node3D:
		match piece:
			"torso":
				return ArmorModel.torso(weight, style, build)
			"belt":
				return ArmorModel.belt(weight, style, build)
			"pauldron":
				return ArmorModel.pauldron(weight, style, out, build)
			"forearm":
				return ArmorModel.forearm(weight, style, out, build)
			"thigh":
				return ArmorModel.thigh(weight, style, out, build)
		return ArmorModel.shin(weight, style, out, build))


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
			# Measured as it came together, its bounds go with its parts
			# still flying in: measured again as it now stands.
			_materializing.remove_meta("model_box")
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
	# A beast's or a machine's weapons are its body: nothing is worn.
	if _def.get("bare", false) or _def.get("arm_weapons", false):
		return null
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
	var bone: String = place["bone"]
	var hips: String = _def.get("hip_bone", "")
	if place["centre"] and not place.has("out") and _wears_pack() and bone != "" and hips != "" \
			and _skeleton.find_bone(bone) >= 0 and _skeleton.find_bone(hips) >= 0:
		# Slung over a backpack, strapped to it: on the hips with it, so the
		# two keep apart however the back bends.
		at += _rest_at(bone) - _rest_at(hips)
		bone = hips
	var root := _hang(pivot, "Stowed" + str(actor.weapons.find(weapon)), bone, at, fallback)
	# Riding lifts what is slung on the back clear of the seat; a weapon
	# clamped to a rail stays in its clamps (it rides beside the seat).
	root.set_meta("slung", place["centre"] and not place.has("out"))
	# How `_fit_worn` keeps it clear of what is under it: clamped to a rail
	# it moves with the rig; slung, it is pushed back off the back; on a
	# hip, out to that side.
	root.set_meta("fit", "rail" if place.has("out") else ("back" if place["centre"] else
			("right" if (place["at"] as Vector3).x > 0.0 else "left")))
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
	ActionPose.of(actor).kick(gun)
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
	if is_instance_valid(_arm_muzzle) and _arm_muzzle.is_inside_tree():
		# An android's gun is its forearm (`_update_arm_weapon`).
		muzzle = _arm_muzzle.global_position
		along = (to - muzzle).normalized()
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
	var burning := not actor.is_dead and (actor.flight.is_thrusting or actor.flight.is_skimming
			or actor.flight.is_skating or _burst_left > 0.0)
	var jets := actor.flight.can_hover()
	for i in _flames.size():
		var flame := _flames[i]
		flame.visible = burning
		if burning and actor.flight.can_skim():
			_aim_flame(flame)
		elif burning and jets:
			_aim_jet_flame(flame, i)
	_update_rig_voice(burning)
	if actor.flight.is_skating:
		var going := Vector2(actor.velocity.x, actor.velocity.z).length() / maxf(actor.flight.skate_speed, 1.0)
		_stride = wrapf(_stride + TAU * skate_stride * clampf(going, 0.3, 1.2) * delta, 0.0, TAU)
	if _rig_back and _rig_back.has_node("WingL"):
		var gliding := actor.flight.is_gliding and not actor.is_dead
		var want := 1.0 if gliding else 0.0
		var was := _spread
		_spread = move_toward(_spread, want, wing_speed * delta)
		_update_wing_air(gliding, delta)
		if _spread != was or _spread > 0.0:
			# Flaring for a landing, the wings tip up to brake.
			var trim := lerpf(actor.glide_trim(), -1.0, smoothstep(0.0, 1.0, _flare))
			var flutter := _wing_stall * stall_shudder * sin(Time.get_ticks_msec() * 0.06)
			RigModel.set_wing_spread(_rig_back, _spread, clampf(-_bank / max_bank, -1.0, 1.0), trim,
					smoothstep(0.0, 1.0, _wing_fast), _wing_load, flutter)


## The rig's voice, heard by everyone near as far as it carries (its
## `noise_range`): a jetpack roars with its throttle and higher in a boost,
## the wings' rush builds with the airspeed, boots hum on a skate and pop on
## a kick or a dash. View only: a server has no voice.
func _update_rig_voice(burning: bool) -> void:
	var f := actor.flight
	var dashing := f.can_skim() and actor.air_dash_left > 0.0
	if dashing and not _was_dashing and not actor.is_dead:
		Sfx.play("boot_pop", global_position + Vector3(0, 0.3, 0), -4.0, maxf(f.noise_range, 8.0), maxf(f.noise_range, 8.0) / 6.0)
	_was_dashing = dashing
	if _rig_voice == null:
		return
	var air := actor.velocity.length()
	var on := false
	var volume := -80.0
	var pitch := 1.0
	if f.can_hover():
		on = burning and f.is_thrusting
		volume = lerpf(-14.0, -1.0, clampf(_jet_throttle / 1.6, 0.0, 1.0))
		pitch = 0.75 + 0.2 * clampf(_jet_throttle, 0.0, 2.0) + (0.12 if f.is_boosting else 0.0)
	elif f.can_glide() or f.glide_fall_speed > 0.0:
		on = f.is_gliding and not actor.is_dead
		var share := clampf((air - 8.0) / 24.0, 0.0, 1.0)
		volume = lerpf(-22.0, -3.0, share)
		pitch = 0.8 + 0.5 * share
	else:
		on = f.is_skating and not actor.is_dead
		volume = -12.0
		pitch = 0.9 + 0.2 * clampf(air / maxf(f.skate_speed, 1.0), 0.0, 1.0)
	if on and not _rig_voice.playing:
		_rig_voice.play()
	elif not on and _rig_voice.playing:
		_rig_voice.stop()
	_rig_voice.volume_db = volume
	_rig_voice.pitch_scale = pitch


## How the air is treating the wings, for their pose and the arms': how far
## past the glide's speed, how stalled and how loaded the glide is, and the
## wingtip vapor that shows the fast and hard parts.
func _update_wing_air(gliding: bool, delta: float) -> void:
	var f := actor.flight
	var air := Vector2(actor.velocity.x, actor.velocity.z).length()
	var top := f.glide_speed * (1.0 + f.glide_dive_gain)
	var fast := clampf((air - f.glide_speed) / maxf(top - f.glide_speed, 0.1), 0.0, 1.0) if gliding else 0.0
	var stalled := 1.0 if gliding and actor.glide_stalled() else 0.0
	# Load in g: a banked turn's, and a pull-up with speed to spare.
	var pull := maxf(0.0, -actor.glide_trim()) if gliding else 0.0
	var spare := clampf((air - f.glide_speed * f.glide_stall) / maxf(f.glide_speed * 0.5, 0.1), 0.0, 1.0)
	var g := 1.0 / cos(minf(absf(_bank), 1.2)) + pull * spare if gliding else 1.0
	var follow := 1.0 - exp(-bank_follow * delta)
	_wing_fast = lerpf(_wing_fast, fast, follow)
	_wing_stall = lerpf(_wing_stall, stalled, follow)
	_wing_load = lerpf(_wing_load, clampf(g - 1.0, 0.0, 1.0), follow)
	var streaming := gliding and (air > vapor_speed or g > vapor_g)
	if _vapor == null and streaming and _vapor_allowed():
		_vapor = _Vapor.new()
		_vapor.top_level = true
		add_child(_vapor)
	if _vapor != null:
		var tips: Array[Vector3] = []
		for wing_name: String in ["WingL", "WingR"]:
			var tip := _rig_back.get_node_or_null(wing_name + "/Panel/TipLight") as Node3D
			if tip != null:
				tips.append(tip.global_position)
		if not streaming:
			tips.clear()
		_vapor.step(tips, delta, vapor_life, vapor_length, vapor_width, vapor_alpha, vapor_clear)


## For the first-person camera's flight motion (`PlayerController`): the
## wings' bank (radians, positive in a left turn, while the glide pose is
## on), the skate's carve (the same way round), the skate's stride (radians
## round, NAN when not skating) and how hard a jetpack boost is pushing
## (0..1, more as it lights).
func flight_bank() -> float:
	return _bank * smoothstep(0.0, 1.0, _glide) * (1.0 - smoothstep(0.0, 1.0, _boost))


func skate_carve() -> float:
	return _skate_carve if actor.flight.is_skating else 0.0


func stride_phase() -> float:
	return _stride if actor.flight.is_skating else NAN


func boost_push() -> float:
	if not actor.flight.is_boosting:
		return 0.0
	return clampf(0.5 + 0.5 * _jet_kick_left / maxf(jet_kick_time, 0.01), 0.0, 1.0)


## Wingtip vapor is a nicety: off on the Low and Lowest graphics.
static func _vapor_allowed() -> bool:
	var pick: Variant = GameSettings.value_of("graphics")
	return pick == null or (int(pick) != GameSettings.GRAPHICS_LOW and int(pick) != GameSettings.GRAPHICS_LOWEST)


## A fading streak behind each wingtip: the tips' last places, drawn as
## one ribbon mesh a frame facing the camera (one draw for both). View only.
class _Vapor extends MeshInstance3D:
	var _trails: Array = []
	var _mesh := ImmediateMesh.new()

	func _init() -> void:
		name = "WingVapor"
		mesh = _mesh
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		material_override = mat

	## Adds this frame's tip places (none while not streaming), ages the
	## rest out over `life` seconds, cuts each trail to `length` m and
	## redraws: `width` at the tip tapering to nothing, `alpha` at most,
	## fading by age, along the trail and within `clear` m of the camera.
	func step(tips: Array[Vector3], delta: float, life: float, length: float, width: float, alpha: float, clear: float) -> void:
		while _trails.size() < tips.size():
			_trails.append([])
		for trail: Array in _trails:
			for point: Array in trail:
				point[1] += delta
			while not trail.is_empty() and float(trail[0][1]) > life:
				trail.pop_front()
		for i in tips.size():
			(_trails[i] as Array).append([tips[i], 0.0])
		for trail: Array in _trails:
			var run := 0.0
			var j := trail.size() - 1
			while j > 0:
				run += (trail[j][0] as Vector3).distance_to(trail[j - 1][0])
				if run > length:
					break
				j -= 1
			for _cut in j:
				trail.pop_front()
		_mesh.clear_surfaces()
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		var eye := camera.global_position if camera != null else Vector3.ZERO
		var drawn := false
		var last := Vector3.ZERO
		for trail: Array in _trails:
			if trail.size() < 2:
				continue
			if not drawn:
				_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
				drawn = true
			else:
				# A break between the two ribbons: degenerate corners from
				# the last one's end to this one's start, drawn clear.
				_mesh.surface_set_color(Color(1, 1, 1, 0))
				_mesh.surface_add_vertex(last)
				_mesh.surface_set_color(Color(1, 1, 1, 0))
				_mesh.surface_add_vertex(trail[0][0])
			var count := trail.size()
			for j in count:
				var at: Vector3 = trail[j][0]
				var next: Vector3 = trail[mini(j + 1, count - 1)][0]
				var prev: Vector3 = trail[maxi(j - 1, 0)][0]
				var along := (next - prev).normalized()
				# 0 at the tail, 1 at the tip.
				var share := float(j) / float(count - 1)
				var side := along.cross(eye - at).normalized() * width * share
				var age := 1.0 - float(trail[j][1]) / life
				var near := smoothstep(clear * 0.5, clear, at.distance_to(eye)) if camera != null else 1.0
				var shade := Color(1, 1, 1, alpha * age * age * share * near)
				_mesh.surface_set_color(shade)
				_mesh.surface_add_vertex(at - side)
				_mesh.surface_set_color(shade)
				_mesh.surface_add_vertex(at + side)
				last = at + side
		if drawn:
			_mesh.surface_end()


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
	_boost = move_toward(_boost, 1.0 if alive and actor.flight.is_boosting else 0.0, boost_ease * delta)
	# Out of a boost the body keeps flying the prone attitude, eased back to
	# upright by `_boost`, so the hover's lean takes over without a snap.
	var prone := alive and not actor.flight.is_gliding and _boost > 0.0
	var prone_w := smoothstep(0.0, 1.0, _boost)
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
	if flat or prone:
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
		if not actor.flight.is_gliding:
			# A boost: between the hover's lean (or none) and flat out.
			var upright := Vector3.ZERO
			if actor.flight.is_hovering and not actor.flight.is_boosting:
				upright = _jet_lean()
			tilt = upright.lerp(tilt, prone_w)
			face *= prone_w
			bank *= prone_w
	else:
		_has_heading = false
		if alive and actor.flight.is_hovering:
			tilt = _jet_lean()
		elif alive and actor.flight.is_skating:
			tilt = _skate_tilt(speed, delta)
		elif _run_out:
			# Down out of a glide at speed: lean back against the skid.
			tilt = -dir * run_out_lean * clampf((speed - run_out_speed) / run_out_speed, 0.0, 1.0)
		elif alive and _boot_w > 0.0 and is_airborne():
			tilt = _boot_tilt() * smoothstep(0.0, 1.0, _boot_w)
		elif alive and _air > 0.0 and is_airborne():
			# A running jump leans into it, and rights itself for the landing.
			tilt = dir * leap_lean * clampf(speed / leap_lean_speed, 0.0, 1.0) * (1.0 - _air_fall)
	_run_out_left = maxf(0.0, _run_out_left - delta)
	var running_on := actor.cmd.move.length() > 0.1 and speed <= actor.sprint_speed + 0.5
	_run_out = _run_out and alive and speed > run_out_speed * 0.5 and actor.is_on_floor() \
			and _run_out_left > 0.0 and not running_on
	if locomotion != null:
		locomotion.skid = _run_out
	# The actor turns with the view, and this model is its child. While the
	# body is laid out in flight, a look round must not drag it round with
	# the camera and then let it swing back: undo the view's turn first, so
	# the attitude eases only toward the way the body really flies.
	var yaw := actor.global_rotation.y
	_update_lead(flat, face, wrapf(yaw - _last_yaw, -PI, PI), delta)
	if _glide > 0.0 or _boost > 0.0:
		var turned := wrapf(yaw - _last_yaw, -PI, PI)
		_face -= turned
		_tilt = _tilt.rotated(Vector3.UP, -turned)
	_last_yaw = yaw
	var follow := 1.0 - exp(-attitude_follow * delta)
	_tilt = _tilt.lerp(tilt, follow)
	_face = lerp_angle(wrapf(_face, -PI, PI), face, follow)
	_bank = lerpf(_bank, bank, 1.0 - exp(-bank_follow * delta))
	var lead_tilt := Vector3.ZERO
	var lead_banked := 0.0
	if _lead_w > 0.0:
		var level_reach := Vector3(_lead_reach.x, 0.0, _lead_reach.z)
		var flat_w := smoothstep(0.0, 1.0, maxf(_glide, _boost))
		lead_tilt = (level_reach * lead_lean * (1.0 - flat_w)
				+ Vector3.LEFT * _lead_turn * lead_lean * (1.0 if actor.flight.is_skating else 0.0)) * _lead_w
		lead_banked = lead_bank * _lead_turn * _lead_w * flat_w
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

	# A kick off a skate spins the body once round, eased at both ends.
	var spin := 0.0
	if _spin_left > 0.0:
		_spin_left = maxf(0.0, _spin_left - delta)
		spin = _spin_dir * TAU * smoothstep(0.0, 1.0, 1.0 - _spin_left / maxf(kick_spin_time, 0.01))
	var shown := _tilt + lead_tilt
	var angle := shown.length()
	var tip := Basis(Vector3.UP.cross(shown / angle).normalized(), angle) if angle > 0.001 else Basis.IDENTITY
	# A positive bank or twist rolls to the right: right side down.
	var turn := tip * Basis(Vector3.UP, _face - _bank - lead_banked + _twist + _look_roll + spin)
	_body_turn = turn
	var pivot := Vector3(0, glide_pivot, 0)
	transform = Transform3D(turn * Basis(Vector3.UP, PI), pivot - turn * pivot)
	var seated: Variant = ride_frame()
	if seated != null and locomotion != null and locomotion.ride_weight > 0.0:
		transform = transform.interpolate_with(seated, smoothstep(0.0, 1.0, locomotion.ride_weight))
	_update_boarding(delta)


## Getting on and off (view only). The actor is put on its seat, or off
## beside the vehicle, at once; the body follows over `board_time` (on) or
## `unboard_time` (off): it starts where the actor just was and moves across
## with a hop over the seat (`board_hop`), while the riding pose eases in or
## out at the same pace, so a leg swings over. The same body every view
## sees: first person rides on the posed head. Only at a walk
## (`board_max_speed`) and over a short step: a bail-out off a fast bike, or
## a seat taken far off (a teleport, a reclaimed body), is left instant.
## `boarding` is the share of it left (1 to 0, 0 when not), for sound.
var board_time := 0.42
var unboard_time := 0.32
var board_hop := 0.28
var board_max_speed := 4.0
var board_max_step := 4.0
var boarding := 0.0
var _board_on: Node3D
var _board_from := Vector3.ZERO
var _board_mounting := false
var _board_left := 0.0
var _board_total := 0.0
var _board_was: Node3D
var _board_last := Vector3.INF
var _board_rate := 0.0


func _update_boarding(delta: float) -> void:
	var on: Node3D = actor.vehicle if not actor.is_dead else null
	if on != null and not is_instance_valid(on):
		on = null
	var was: Node3D = _board_was if _board_was != null and is_instance_valid(_board_was) else null
	if on != was:
		_board_left = 0.0
		var by: Node3D = on if on != null else was
		var slow := by != null and absf(float(by.get("speed"))) < board_max_speed
		var near := _board_last != Vector3.INF and _board_last.distance_to(actor.global_position) < board_max_step
		if slow and near and (on == null) != (was == null) and not actor.is_dead:
			_board_on = by
			_board_mounting = on != null
			# Getting on, the start is kept on the vehicle (it may roll);
			# getting off, in the world.
			_board_from = by.global_transform.affine_inverse() * _board_last if _board_mounting else _board_last
			_board_total = board_time if _board_mounting else unboard_time
			_board_left = _board_total
			if locomotion != null:
				if _board_rate == 0.0:
					_board_rate = locomotion.ride_rate
				locomotion.ride_rate = 1.0 / _board_total
	_board_was = on
	_board_last = actor.global_position
	if _board_left <= 0.0 or _board_on == null or not is_instance_valid(_board_on):
		_board_left = 0.0
		boarding = 0.0
		if _board_rate > 0.0 and locomotion != null:
			locomotion.ride_rate = _board_rate
		return
	_board_left = maxf(0.0, _board_left - delta)
	var left := _board_left / maxf(_board_total, 0.01)
	boarding = left
	var from: Vector3 = _board_on.global_transform * _board_from if _board_mounting else _board_from
	var offset := (from - actor.global_position) * smoothstep(0.0, 1.0, left) + Vector3.UP * board_hop * sin(PI * left)
	var parent := get_parent() as Node3D
	if parent != null:
		transform.origin += parent.global_basis.inverse() * offset


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
	# Stopped on a bike, the rider puts a foot down (not a passenger).
	var stopped: bool = absf(float(vehicle.get("speed"))) < foot_down_speed and str(vehicle.get("model")) in ["bike", "hoverbike"] \
			and locomotion.ride == vehicle and float(vehicle.get("airborne_time")) <= 0.0
	locomotion.ride_foot_down = move_toward(locomotion.ride_foot_down, 1.0 if stopped else 0.0,
			foot_down_rate * get_process_delta_time())
	var free := _in_hand == null and _plan.is_empty() and not phone_up()
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
	for bone_name: String in def.get("spine", []):
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			_spine_bones.append(bone)
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
	_pose_spine()
	_pose_air()
	_pose_flat()
	_pose_lead_arms()


## The flat flying pose of `_pose_glide`, while the glide or a boost has it.
func _pose_flat() -> void:
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
		var arm_dir := glide_arm.lerp(dive_arm, smoothstep(0.0, 1.0, _wing_fast)).lerp(stall_arm, _wing_stall) \
				.lerp(boost_arm, smoothstep(0.0, 1.0, _boost)).lerp(backstroke_arm, back)
		var wanted := to_skeleton * (Vector3(arm_dir.x * limb[3], arm_dir.y, arm_dir.z) + _limb_sway(sway_arms))
		# Shooting or aiming, the arms keep their hold on the weapon.
		var arm_w := w * (1.0 - smoothstep(0.0, 1.0, _flight_hold))
		_aim_bone(limb[0], limb[1], wanted, arm_w)
		_aim_bone(limb[1], limb[2], wanted, arm_w)
	for limb: Array in _glide_legs:
		if not limb.is_empty():
			var leg := glide_leg.lerp(backstroke_leg, back)
			_pose_leg(limb, to_skeleton * (Vector3(leg.x * limb[3], leg.y, leg.z) + _limb_sway(sway_legs) + _leg_lead()), right, w)
	if _glide_neck >= 0:
		var pose := _skeleton.get_bone_global_pose(_glide_neck)
		pose.basis = Basis((to_skeleton * Vector3.RIGHT).normalized(), lerpf(glide_look, backstroke_look, back) * w) * pose.basis
		_skeleton.set_bone_global_pose(_glide_neck, pose)


## What the pilot is asking for (`lead_rate`), read from the command so a
## remote player's body leads the same way. `face` is where the flight path
## points from the view (radians, positive left), `turned` how far the view
## swung this frame.
func _update_lead(flat: bool, face: float, turned: float, delta: float) -> void:
	var f := actor.flight
	var alive := not actor.is_dead and actor.vehicle == null
	var flying := alive and f.enabled and is_airborne() \
			and (flat or f.is_hovering or f.is_skating or _boot_w > 0.0)
	var turn := 0.0
	var reach := Vector3.ZERO
	if flying:
		var cmd := actor.cmd
		if f.is_gliding:
			# A glide steers by the view: the body leads toward where it looks.
			if not cmd.free_look:
				turn = clampf(-wrapf(face, -PI, PI) / maxf(lead_turn_angle, 0.01), -1.0, 1.0)
			reach.y = clampf(-actor.glide_trim(), -1.0, 1.0)
		else:
			var rate := turned / delta if delta > 0.0 else 0.0
			var carve := cmd.move.x * 0.7 if f.is_skating else 0.0
			turn = clampf(rate / maxf(lead_turn_rate, 0.01) - carve, -1.0, 1.0)
			var climb := (1.0 if cmd.jump else 0.0) - (1.0 if cmd.descend else 0.0)
			reach = Vector3(cmd.move.x, climb, -cmd.move.y).limit_length(1.0)
	var follow := 1.0 - exp(-lead_rate * delta)
	_lead_turn = lerpf(_lead_turn, turn, follow)
	_lead_reach = _lead_reach.lerp(reach, follow)
	_lead_w = move_toward(_lead_w, 1.0 if flying else 0.0, air_blend * delta)


## A vector in the flight's heading frame (level, facing the way the body
## flies: x right, y up, z back), turned into the body's own frame before
## the tip, as limb directions are given.
func _heading_to_body(v: Vector3) -> Vector3:
	return _body_turn.inverse() * (Basis(Vector3.UP, _face) * v)


## The arms and hands lead (`lead_arm_roll`): laid over whatever pose the
## arms have, the inside arm drops and the outside one lifts into a turn,
## the arms reach where the stick points (pressing down to climb), a glide's
## sweep back to dive and forward to pull up, and the hands tip like
## ailerons and flex with the climb.
func _pose_lead_arms() -> void:
	var w := smoothstep(0.0, 1.0, _lead_w) * (1.0 - smoothstep(0.0, 1.0, _flight_hold))
	# A weapon in hand keeps the arms closer to its hold.
	if _in_hand != null:
		w *= lead_armed
	if w <= 0.001:
		return
	var to_skeleton := _skeleton.basis.orthonormalized().inverse() * _model_basis_inverse() * Basis(Vector3.UP, PI)
	var g := smoothstep(0.0, 1.0, _limb_glide())
	var level := Vector3(_lead_reach.x, 0.0, _lead_reach.z)
	for limb: Array in _glide_arms:
		if limb.is_empty():
			continue
		var side: float = limb[3]
		var off := Vector3(0.0, lead_arm_roll * _lead_turn * side, 0.0)
		off += (level - Vector3(0.0, _lead_reach.y, 0.0)) * lead_reach * (1.0 - g)
		off += Vector3(0.0, 0.0, -_lead_reach.y * lead_sweep * g)
		var push := to_skeleton * _heading_to_body(off)
		var upper := _skeleton.get_bone_global_pose(limb[0]).origin
		var elbow := _skeleton.get_bone_global_pose(limb[1]).origin
		_aim_bone(limb[0], limb[1], (elbow - upper).normalized() + push, w)
		elbow = _skeleton.get_bone_global_pose(limb[1]).origin
		var hand := _skeleton.get_bone_global_pose(limb[2])
		_aim_bone(limb[1], limb[2], (hand.origin - elbow).normalized() + push, w)
		hand = _skeleton.get_bone_global_pose(limb[2])
		var fore := (hand.origin - _skeleton.get_bone_global_pose(limb[1]).origin)
		if fore.length_squared() < 0.000001:
			continue
		var bend_axis := (to_skeleton * _heading_to_body(Vector3.RIGHT)).normalized()
		hand.basis = Basis(fore.normalized(), lead_hand * _lead_turn * side * w) \
				* Basis(bend_axis, lead_hand_flex * _lead_reach.y * w) * hand.basis
		_skeleton.set_bone_global_pose(limb[2], hand)


## The legs swing against the arms' reach to balance (`lead_legs`), body
## frame as `_limb_sway`.
func _leg_lead() -> Vector3:
	if _lead_w <= 0.0:
		return Vector3.ZERO
	return _heading_to_body(-Vector3(_lead_reach.x, 0.0, _lead_reach.z) * lead_legs * _lead_w)


## The limbs' secondary motion (`sway_stiffness`): the pull of the body's
## changes of speed and heading on a spring, stepped in short slices so a
## long frame cannot throw it off.
func _update_sway(delta: float) -> void:
	var flying := is_airborne() and not actor.is_dead and actor.vehicle == null
	var want := Vector3.ZERO
	var rate := 0.0
	if flying and delta > 0.0:
		var accel := actor.global_basis.inverse() * ((actor.velocity - _vel_lag) * boot_accel_rate)
		want = (-accel / 9.8).limit_length(1.2)
		var flat := Vector2(actor.velocity.x, actor.velocity.z)
		var heading := atan2(-actor.velocity.x, -actor.velocity.z)
		if flat.length() > 2.0 and not is_nan(_sway_heading):
			rate = wrapf(heading - _sway_heading, -PI, PI) / delta
		_sway_heading = heading if flat.length() > 2.0 else NAN
	else:
		_sway_heading = NAN
	_turn_rate = lerpf(_turn_rate, rate, 1.0 - exp(-bank_follow * delta))
	var left := minf(delta, 0.25)
	while left > 0.0:
		var step := minf(left, 1.0 / 120.0)
		_sway_v += ((want - _sway) * sway_stiffness - _sway_v * sway_damping) * step
		_sway += _sway_v * step
		left -= step


## The limbs' swing this frame, in the body's own frame before the tip
## (as limb directions are given), `share` of the pull.
func _limb_sway(share: float) -> Vector3:
	return (_body_turn.inverse() * _sway) * share


## While the arms are free of a weapon in flat flight, the chest leads the
## turn being flown and sits back or forward against a change of speed.
## Runs first, so the limbs are aimed from where the chest has gone.
func _pose_spine() -> void:
	if _spine_bones.is_empty():
		return
	var free := 1.0 - smoothstep(0.0, 1.0, _flight_hold)
	var lead := smoothstep(0.0, 1.0, _lead_w)
	var w := maxf(maxf(smoothstep(0.0, 1.0, _limb_glide()), smoothstep(0.0, 1.0, _boot_w) * _boot_hero), lead) * free
	if w <= 0.001:
		return
	var to_skeleton := _skeleton.basis.orthonormalized().inverse() * _model_basis_inverse() * Basis(Vector3.UP, PI)
	var up := (to_skeleton * Vector3.UP).normalized()
	var right := (to_skeleton * Vector3.RIGHT).normalized()
	var forward := (to_skeleton * Vector3.FORWARD).normalized()
	var g := smoothstep(0.0, 1.0, _limb_glide())
	# The chest leads: it turns into the turn asked for before the flight
	# swings round, bends into it, and leans with the stick or the trim.
	var twist := sway_twist * clampf(_turn_rate / maxf(sway_turn_full, 0.1), -1.0, 1.0) + lead_twist * _lead_turn * lead
	var pitch := sway_pitch * clampf((_body_turn.inverse() * _sway).z, -1.0, 1.0) \
			+ lead_crunch * (_lead_reach.z * (1.0 - g) + _lead_reach.y * g) * lead
	var roll := -lead_roll * _lead_turn * lead
	var share := w / _spine_bones.size()
	for bone in _spine_bones:
		var pose := _skeleton.get_bone_global_pose(bone)
		pose.basis = Basis(up, twist * share) * Basis(right, pitch * share) * Basis(forward, roll * share) * pose.basis
		_skeleton.set_bone_global_pose(bone, pose)
	if _glide_neck >= 0 and lead > 0.001:
		# The head leads most: it looks into the turn and the climb first.
		var pose := _skeleton.get_bone_global_pose(_glide_neck)
		pose.basis = Basis(up, lead_head * _lead_turn * lead * free) \
				* Basis(right, lead_head_pitch * _lead_reach.y * lead * free) * pose.basis
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
			var legs := _skate_leg(i) if actor.flight.is_skating else _boot_legs(i, float(limb[3]))
			thigh = thigh.lerp(legs[0], bw)
			shin = shin.lerp(legs[1], bw)
			toes = lerpf(toes, boot_toes, bw)
		var swing := _limb_sway(sway_legs) + _leg_lead()
		_pose_leg(limb, to_skeleton * (Vector3(thigh.x * limb[3], thigh.y, thigh.z) + swing), right, w,
				to_skeleton * (Vector3(shin.x * limb[3], shin.y, shin.z) + swing * 1.5), toes)
	var arm_w := w * smoothstep(0.0, 1.0, _boot_w) * _boot_hero * (1.0 - smoothstep(0.0, 1.0, _flight_hold))
	if arm_w > 0.001:
		# Lying out, the arms ride by the sides until there is aiming to do.
		for limb: Array in _glide_arms:
			if limb.is_empty():
				continue
			var wanted := to_skeleton * (Vector3(boot_arm.x * limb[3], boot_arm.y, boot_arm.z) + _limb_sway(sway_arms))
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
	if actor.flight.enabled and actor.flight.can_hover():
		_update_jet_thrust(delta)
	_tuck = move_toward(_tuck, 1.0 if boots and actor.air_dash_left > 0.0 else 0.0, air_blend * 1.5 * delta)
	var burning := boots and not actor.is_dead and actor.vehicle == null and is_airborne() \
			and (actor.flight.is_skimming or actor.flight.is_skating or actor.air_dash_left > 0.0 or _burst_left > 0.0)
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
	# Skating keeps the skater's stance (`skate_legs`), never the flying one.
	var hero := smoothstep(0.45, 0.9, ahead / cruise) * lined * lined if burning and not actor.flight.is_skating else 0.0
	_boot_hero = lerpf(_boot_hero, hero, follow)


## Reads what a jetpack's jets are doing from the actor's velocity: the push
## they make (holding you up, speeding you up or slowing you, and a steady
## drift against the air, `jet_drag`), the throttle, and a boost lighting.
func _update_jet_thrust(delta: float) -> void:
	var to_local := actor.global_basis.inverse()
	var local := to_local * actor.velocity
	var accel := to_local * ((actor.velocity - _vel_lag) * boot_accel_rate)
	var push := accel + Vector3(local.x, 0.0, local.z) * jet_drag + Vector3(0.0, 9.8, 0.0)
	push.y = maxf(push.y, 1.0)
	var follow := 1.0 - exp(-attitude_follow * delta)
	_jet_push = _jet_push.lerp(push, follow)
	_jet_throttle = lerpf(_jet_throttle, _jet_push.length() / 9.8, follow)
	_jet_kick_left = maxf(0.0, _jet_kick_left - delta)
	var boosting := actor.flight.is_boosting and not actor.is_dead
	if boosting and not _was_boosting:
		_jet_kick_left = jet_kick_time
	_was_boosting = boosting


## Hovering on a jetpack, the body tips into the jets' push, up to
## `hover_lean`: a helicopter's lean, not the drift's.
func _jet_lean() -> Vector3:
	var level := Vector3(_jet_push.x, 0.0, _jet_push.z)
	if level.length() < 0.001:
		return Vector3.ZERO
	return level.normalized() * minf(atan2(level.length(), maxf(_jet_push.y, 0.1)), hover_lean)


## Swivels a jetpack flame toward the jets' exhaust, as far as its nozzle
## turns (`jet_gimbal`), and stretches it with the throttle, a boost's kick
## and a flicker.
func _aim_jet_flame(flame: Node3D, i: int) -> void:
	var nozzle := flame.get_parent() as Node3D
	if nozzle == null:
		return
	var exhaust := -_jet_push.normalized() if _jet_push.length() > 0.01 else Vector3.DOWN
	var want := (nozzle.global_basis.orthonormalized().inverse() * (actor.global_basis.orthonormalized() * exhaust)).normalized()
	var angle := Vector3.DOWN.angle_to(want)
	var dir := Vector3.DOWN.slerp(want, minf(1.0, jet_gimbal / angle)) if angle > 0.001 else Vector3.DOWN
	var kick := lerpf(1.0, jet_kick, _jet_kick_left / maxf(jet_kick_time, 0.01))
	var flicker := 1.0 + jet_flicker * sin(Time.get_ticks_msec() * 0.045 + i * 1.7)
	var stretch := clampf(_jet_throttle, jet_flame_min, jet_flame_max) * kick * flicker
	var swivel := Basis(Quaternion(Vector3.DOWN, dir.normalized())) if angle > 0.001 else Basis.IDENTITY
	flame.basis = swivel * Basis.from_scale(Vector3(lerpf(1.0, sqrt(stretch), 0.5), stretch, lerpf(1.0, sqrt(stretch), 0.5)))


## The body's lean while skating, as `_update_glide` takes it: forward
## with the speed, and over into the turn being carved.
func _skate_tilt(speed: float, delta: float) -> Vector3:
	var heading := atan2(-actor.velocity.x, -actor.velocity.z)
	var carve := 0.0
	if not is_nan(_skate_heading) and speed > 2.0 and delta > 0.0:
		var rate := wrapf(heading - _skate_heading, -PI, PI) / delta
		carve = clampf(atan(speed * rate / 9.8), -skate_bank, skate_bank)
	_skate_heading = heading if speed > 2.0 else NAN
	_skate_carve = lerpf(_skate_carve, carve, 1.0 - exp(-bank_follow * delta))
	var going := clampf(speed / maxf(actor.flight.skate_speed, 1.0), 0.0, 1.0)
	# Turning left (heading growing) leans left: toward -X in the body frame.
	return Vector3.FORWARD * skate_lean * going + Vector3.LEFT * _skate_carve


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


## Thigh and shin of leg `i` in the skater's stance (`skate_legs`), mirrored
## for its side as `_pose_air` does.
func _skate_leg(i: int) -> Array:
	var at := mini(i, 1) * 2
	# Pumping: each leg in turn pushes out to its side and back.
	var push := maxf(0.0, sin(_stride + PI * i)) * skate_push
	var thigh: Vector3 = skate_legs[at] + Vector3(push, 0.0, push * 0.5)
	var shin: Vector3 = skate_legs[at + 1] + Vector3(push * 1.2, 0.0, push * 0.4)
	return [thigh.normalized(), shin.normalized()]


## Thigh and shin directions for leg `i` while boots fire, in the body's own
## frame before the tip and mirrored for `side` (as `_pose_air` reads them):
## both legs follow the exhaust, a little apart; the second leg's knee bends,
## more in forward flight.
func _boot_legs(i: int, side: float) -> Array:
	var along := _body_turn.inverse() * _exhaust
	along = Vector3(along.x * side, along.y, along.z)
	var thigh := (along + Vector3(0.06, 0.0, 0.0)).normalized()
	# A dash pulls both knees up into a tuck.
	var tuck := dash_tuck * smoothstep(0.0, 1.0, _tuck)
	if i == 0:
		return [Basis(Vector3.RIGHT, tuck * 0.8) * thigh, Basis(Vector3.RIGHT, -tuck * 0.6) * thigh]
	var bend := 0.2 + boot_knee * _boot_hero + tuck
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
	if actor.flight.can_skim() and not actor.is_dead:
		var reach := maxf(actor.flight.noise_range, 8.0)
		Sfx.play("boot_pop", global_position + Vector3(0, 0.3, 0), -2.0, reach, reach / 6.0)
	if actor.flight.is_skating and _flight_hold < 0.5 and not actor.is_dead:
		# A kick off a skate: a spin, the way the strafe key or the carve leans.
		var side := actor.cmd.move.x if absf(actor.cmd.move.x) > 0.1 else -_skate_carve
		_spin_dir = -1.0 if side < 0.0 else 1.0
		_spin_left = kick_spin_time


## Swaps the rig model for the one `id` needs ("" takes it off).
func _wear_rig(id: String) -> void:
	_rig_id = id
	for holder in _rig_holders:
		holder.queue_free()
	_rig_holders.clear()
	_flames.clear()
	if _rig_voice != null:
		_rig_voice.queue_free()
		_rig_voice = null
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
		# Hung on the shin it wraps, at the ankle, so it keeps its fit
		# round the leg (`_fit_worn`) however the foot turns.
		var foot := _skeleton.find_bone(bone) if _skeleton and bone != "" else -1
		var shin := _skeleton.get_bone_parent(foot) if foot >= 0 else -1
		var offset := boot_offset
		if shin >= 0:
			offset += _rest_at(bone) - _rest_at(_skeleton.get_bone_name(shin))
			bone = _skeleton.get_bone_name(shin)
		_wear_part(boot, bone, offset, Vector3(side * 0.12, 0.1, 0.0))
	var lit := false
	var trail := rig_trail()
	for holder in _rig_holders:
		for nozzle in RigModel.nozzles(holder):
			var size: Vector2 = nozzle.get_meta("flame", Vector2(0.05, 0.5))
			var flame := Vfx.nozzle_flame(size.x, size.y, not lit, trail)
			lit = true
			flame.visible = false
			nozzle.add_child(flame)
			_flames.append(flame)
	var voice: String = {"jetpack": "jet_roar", "wings": "wing_rush", "boots": "skate_hum"}.get(RigModel.kind_for(id), "")
	var stream := Sfx.get_stream(voice) if voice != "" else null
	if stream != null:
		_rig_voice = AudioStreamPlayer3D.new()
		_rig_voice.name = "RigVoice"
		_rig_voice.stream = stream
		var reach := maxf(float(ItemDB.item_stats(id).get("noise_range", 20.0)), 8.0)
		_rig_voice.max_distance = reach
		_rig_voice.unit_size = reach / 6.0
		_rig_voice.position = Vector3(0, 1.1, 0)
		add_child(_rig_voice)
	_mark_storm()


## The thruster trail this body's rig burns in (`RigTrail`): the one its
## appearance names, "" for the factory flame.
func rig_trail() -> String:
	return RigTrail.clean(_appearance.get("trail"))


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
		holder.set_meta("rest", holder.transform)
		holder.set_meta("bone_at", to_actor * global_transform)
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
	holder.set_meta("bone_at", bone_at)
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
