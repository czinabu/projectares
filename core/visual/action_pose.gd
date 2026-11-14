class_name ActionPose
extends Node
## One actor's animation state for the weapon hand, which the body is posed
## from. First and third person differ only in where the camera is (Caleb's
## rule): both look at the same body, so `WeaponArm` and `ActorSkin` reaching
## the model's arm from this state is all there is to it. Nothing here feeds
## back into the simulation: it is read from the actor and its command, and
## only views read it. It is a child of the actor named `NODE_NAME`, made by
## the first view that asks (`ActionPose.of`), so a headless server never has
## one.
##
## Offsets are in the aim frame: the actor's facing turned by its pitch, with
## x to the actor's right, y up and z back, applied from the model's hand (or
## `Actor.HAND_REST` for melee).

const NODE_NAME := "ActionPose"

## Where the weapon hand goes for each melee side, as an offset from the
## resting hand.
var arm_windup := {
	MeleeWeapon.Dir.RIGHT: Vector3(0.0, 0.3, 0.25),
	MeleeWeapon.Dir.LEFT: Vector3(-0.5, 0.3, 0.1),
	MeleeWeapon.Dir.OVERHEAD: Vector3(-0.15, 0.5, 0.2),
}
var arm_follow := {
	MeleeWeapon.Dir.RIGHT: Vector3(-0.5, -0.2, -0.2),
	MeleeWeapon.Dir.LEFT: Vector3(0.15, -0.2, -0.2),
	MeleeWeapon.Dir.OVERHEAD: Vector3(-0.15, -0.35, -0.25),
}
var arm_guard := Vector3(0.0, 0.08, -0.08)
## Holding a one-handed weapon ready (standing, moving, between attacks) the
## hand is out in front, low on the right of the view, with the weapon
## standing in the fist (Caleb's references). Each model picks its hold
## (`Look.ready_hold`, the last field of `Look.MELEE_MODELS`): where the hand
## goes (an offset from `Actor.HAND_REST`, aim frame), which way the blade
## points (aim frame: x right, y up, z back), what the off hand does
## (`ready_off`) and whether the blade comes out of the little-finger side
## of the fist (a reverse grip, `ready_reversed`). A swing starts from the
## hold and eases back to it; a reverse grip turns over in the hand as it
## goes. Two-handed weapons are carried across the body instead
## (`WeaponArm.carry_point`).
var ready_holds := {
	# A straight sword: upright, the point barely forward.
	"upright": [Vector3(0.02, 0.14, -0.2), Vector3(0.0, 1.0, -0.1), "", false],
	# A katana in both hands, the off hand under the weapon hand: the point
	# forward and leaning in toward the middle of the view.
	"katana": [Vector3(0.04, 0.08, -0.2), Vector3(-0.38, 1.0, -0.35), "hilt", false],
	# A knife in a reverse grip: lying flat, the point out to the right and
	# ahead, the pommel over the thumb, the empty hand up low as a guard.
	"knife": [Vector3(-0.06, 0.12, -0.2), Vector3(0.85, -0.1, -0.5), "guard", true],
}
## Where the empty hand is held as a guard behind a knife (`ready_holds`):
## low in front of the chest, left of the middle, in the actor's frame.
var off_guard := Vector3(-0.16, 1.3, -0.5)
## How far the weapon is in its ready hold (0..1), eased.
var held_ready := 0.0
## A swing turns the arm about the shoulder (`shoulder`, in the actor's
## frame, like `Actor.HAND_REST`): the hand sweeps round from the windup to
## the follow-through on an arc, and the arm straightens by `swing_extend`
## (m, at most `arm_length` from the shoulder) through the middle of it.
var shoulder := Vector3(0.2, 1.45, -0.05)
var swing_extend := 0.18
var arm_length := 0.62
## Where the weapon elbow points (a pole, actor frame) with the arm cocked
## for a windup and with it thrown through at the end of a swing. Both views
## blend between them by `elbow_raise`.
var elbow_cocked := Vector3(0.9, 1.6, 0.35)
var elbow_thrown := Vector3(0.6, 0.5, 0.2)
## How long the follow-through is held after the swing lands, in seconds.
var follow_hold := 0.2
## Shoulder turn (x, radians, positive toward the actor's left) and lean
## (y, radians, positive backward) for each side.
var turn_windup := {
	MeleeWeapon.Dir.RIGHT: Vector2(-0.5, 0.0),
	MeleeWeapon.Dir.LEFT: Vector2(0.45, 0.0),
	MeleeWeapon.Dir.OVERHEAD: Vector2(0.0, 0.2),
}
var turn_follow := {
	MeleeWeapon.Dir.RIGHT: Vector2(0.45, -0.1),
	MeleeWeapon.Dir.LEFT: Vector2(-0.45, -0.1),
	MeleeWeapon.Dir.OVERHEAD: Vector2(0.0, -0.35),
}
var turn_guard := 0.12
## A windup keeps drawing back as it goes on, by up to this share of its
## reach and turn (`MeleeWeapon.windup_coil`), so it never freezes.
var windup_coil := 0.18
## A two-handed weapon turns the shoulders this much further: its weight
## comes from the body, not the wrist.
var two_hand_turn := 1.3
## The back strike: the hand drops back past the hip and thrusts behind,
## the shoulders turning to look back.
var arm_back := Vector3(0.12, -0.3, 0.38)
var turn_back := Vector2(-0.7, 0.1)
## A dash-strike leans the body forward (radians) as it closes in.
var dash_lean := 0.35
## Each weapon swings its own way (`MeleeWeapon.style_now`). "slash" is the
## sword's arcs above. A "thrust" (the spear, a knife's stab) draws the hand
## straight back at the side and drives it straight out along the aim, the
## shoulders turning into it. A "chop" (the axe, the hammer) raises the hand
## high over the shoulder and brings it down through a diagonal, ending low.
var thrust_windup := Vector3(0.08, 0.02, 0.3)
var thrust_follow := Vector3(-0.08, 0.04, -0.42)
var thrust_turn_windup := Vector2(-0.35, 0.05)
var thrust_turn_follow := Vector2(0.3, -0.15)
var chop_raise := Vector3(0.0, 0.28, 0.15)
var chop_drop := Vector3(0.0, -0.2, 0.0)
var chop_lean := 0.15
## A "cut" (the katana) is swung in both hands the whole way, the off hand
## kept on the handle under the weapon hand (kenjutsu and kendo: the left
## hand drives, the right steers). Each cut has three keys, in the aim
## frame: the windup, the moment of contact and the end of the
## follow-through. Hands are offsets from `Actor.HAND_REST`, blades the way
## the point goes. The hands pass through the contact key on a curve and
## the blade turns through it, so the cut sweeps out in front of the body
## and never through it.
##   RIGHT     kesa-giri: from hasso by the right shoulder, diagonally down
##             through the line to the left hip.
##   LEFT      gyaku-kesa: the mirror, from by the left shoulder.
##   OVERHEAD  shomen: from jodan over the head straight down the middle,
##             stopped at the chest with the point still forward.
##   "tsuki"   the heavy from the middle stance: a two-handed thrust,
##             drawn back to the hip and driven out along the aim.
## Each key is [hand, blade]; `cut_turns` are the shoulder turn and lean
## (as `turn_windup`) at the windup and at the end, the hips driving it.
var cuts := {
	MeleeWeapon.Dir.RIGHT: [
		[Vector3(-0.16, 0.37, 0.2), Vector3(0.25, 0.8, 0.55)],
		[Vector3(-0.28, 0.07, -0.33), Vector3(-0.55, 0.3, -0.8)],
		[Vector3(-0.48, -0.23, -0.1), Vector3(-0.8, -0.35, 0.3)],
	],
	MeleeWeapon.Dir.LEFT: [
		[Vector3(-0.4, 0.27, 0.06), Vector3(-0.35, 0.8, 0.45)],
		[Vector3(-0.26, 0.05, -0.33), Vector3(0.55, 0.3, -0.8)],
		[Vector3(0.04, -0.23, -0.03), Vector3(0.8, -0.35, 0.3)],
	],
	MeleeWeapon.Dir.OVERHEAD: [
		[Vector3(-0.26, 0.6, 0.2), Vector3(0.0, 0.55, 0.85)],
		[Vector3(-0.26, 0.25, -0.35), Vector3(0.0, 0.3, -0.95)],
		[Vector3(-0.26, -0.1, -0.23), Vector3(0.0, -0.35, -0.95)],
	],
	"tsuki": [
		[Vector3(-0.2, -0.1, 0.13), Vector3(-0.05, 0.15, -1.0)],
		[Vector3(-0.26, 0.05, -0.33), Vector3(0.0, 0.05, -1.0)],
		[Vector3(-0.26, 0.05, -0.37), Vector3(0.0, 0.0, -1.0)],
	],
}
var cut_turns := {
	MeleeWeapon.Dir.RIGHT: [Vector2(-0.35, 0.05), Vector2(0.4, -0.15)],
	MeleeWeapon.Dir.LEFT: [Vector2(0.35, 0.05), Vector2(-0.4, -0.15)],
	MeleeWeapon.Dir.OVERHEAD: [Vector2(0.0, 0.18), Vector2(0.0, -0.3)],
	"tsuki": [Vector2(-0.2, 0.05), Vector2(0.05, -0.35)],
}
## A heavy cut is raised higher and further back, and the hips coil more.
var cut_heavy_raise := Vector3(0.0, 0.06, 0.06)
var cut_heavy_coil := 1.25
## The guards of a cut, both hands on the handle: [hand, blade] for each
## side, the blade up across that side, or over the head edge up.
var cut_guards := {
	MeleeWeapon.Dir.RIGHT: [Vector3(0.02, 0.15, -0.12), Vector3(0.25, 1.0, -0.15)],
	MeleeWeapon.Dir.LEFT: [Vector3(-0.32, 0.15, -0.1), Vector3(-0.3, 1.0, -0.15)],
	MeleeWeapon.Dir.OVERHEAD: [Vector3(-0.38, 0.5, -0.05), Vector3(1.0, 0.15, -0.2)],
}
## Where the weapon elbow points through a cut (actor frame), cocked and
## thrown: down and out, never winged up, since both hands share the handle.
var cut_elbow_cocked := Vector3(0.75, 1.25, 0.2)
var cut_elbow_thrown := Vector3(0.55, 0.7, 0.0)
## Which way the blade's edge faces in the weapon's own frame (the blade
## runs along +Y): a cut leads with it.
var cut_edge := Vector3(0.0, 0.0, -1.0)
## How far the current weapon is held in both hands for its cuts (0..1).
var cut_grip := 0.0
## A reload: at its deepest the gun is brought down and in toward the off
## hand (`reload_reach`), and tipped (`reload_tilt`: pitch, yaw, roll in
## radians, roll positive to the left) to bring the magazine well round.
## `reload_ease` is the share of the reload spent going in and coming out.
var reload_reach := Vector3(-0.1, -0.12, 0.08)
var reload_tilt := Vector3(0.3, 0.15, 0.75)
var reload_ease := 0.22
## Standing still out of a fight a gun is held low (the `idle_gun` clip):
## how fast it is raised and lowered, per second.
var raise_rate := 9.0
var lower_rate := 2.5
## How fast the phone comes up and goes away (per second).
var phone_rate := 5.0
## A toy vehicle off the watch (`Actor.toy_in_hand`) is held up in the right
## hand, and thrown overarm: the hand draws back over the shoulder, whips
## forward and lets go at `toy_release` (the `Raid` lets it fly after the
## same wait, `Raid.toy_windup`), and follows through down across the body.
## Points are in the actor's frame (x right, y up, z back) and turn with the
## aim's pitch by `toy_pitch_share` about the shoulder.
var toy_hold := Vector3(0.24, 1.3, -0.46)
var toy_cocked := Vector3(0.3, 1.62, 0.12)
var toy_let_go := Vector3(0.18, 1.56, -0.5)
var toy_follow := Vector3(0.04, 1.05, -0.36)
var toy_pitch_share := 0.5
## The throw's timing, in seconds from its start: drawn back by
## `toy_cocked_at`, let go at `toy_release`, followed through by
## `toy_follow_at`, and handed back to the usual hold by `toy_throw_time`.
var toy_cocked_at := 0.2
var toy_release := 0.3
var toy_follow_at := 0.42
var toy_throw_time := 0.62
## How fast the hand comes up to hold a toy and goes back (per second).
var toy_rate := 6.0
## The shoulders' turn and lean (as `turn`) drawn back and thrown through.
var toy_turn_cocked := Vector2(-0.45, 0.06)
var toy_turn_thrown := Vector2(0.3, -0.12)
## Where the throwing elbow points, cocked (actor frame).
var toy_elbow := Vector3(0.9, 1.75, 0.3)
## Aiming down sights: the gun is brought up until its sight line runs
## through the eyes, the stock in the shoulder and the off hand on the fore
## end, the same body in both views. `ads_rate` is how fast it comes up and
## goes down (per second; `PlayerController` moves an optic's eye to the
## camera at the same pace). A sidearm is held out with its sight
## `sidearm_relief` in front of the eyes. A long gun is shouldered: the eye
## sits `stock_ahead` forward of the butt (a cheek on the stock), so its
## plain sights come `relief_for` in front of it, at least `min_relief`.
## An optic's eye point is its own relief.
var ads_rate := 7.0
var sidearm_relief := 0.5
var stock_ahead := 0.17
var min_relief := 0.06
## Guns with any of these tags are braced at the hip, never shouldered
## (a spinning cannon is too heavy to bring to the eye).
var ads_hip_tags: Array[String] = ["minigun"]
## Where the off hand's fist closes round a sidearm's grip, wrapped over
## the gun hand's fingers from the off side: from the grip spot
## (`hold_local`), in the gun's space.
var ads_cup := Vector3(-0.03, -0.035, -0.01)
## The stance that goes with aiming down sights, as a shoulder turn and lean
## (like `turn`: x toward the actor's left, y backward): a long gun blades
## the body so the off shoulder comes forward to the fore end, a sidearm
## squares up and leans in so the arms reach out.
var ads_stance_long := Vector2(-0.35, -0.06)
var ads_stance_sidearm := Vector2(0.3, -0.06)
## Inspecting what is in the hand (`ActorCommand.inspect`, the inspect key):
## the hand brings it in closer, a little up and toward the middle of the
## body, and turns it through `INSPECT_TURNS` so each side shows, then it
## goes back to the ready hold. The same body in both views, and everyone
## sees it, since the flag travels with the held keys. Offsets are in the
## aim frame like the rest, so it comes up wherever you look.
## `inspect_from_eyes` is where the wrist comes to (metres right, up and
## ahead of the eyes along the aim, the pitch clamped to `inspect_pitch`),
## whatever is in hand; `inspect_rate` is how fast it comes up and goes
## back (per second).
var inspect_from_eyes := Vector3(0.05, -0.18, -0.45)
var inspect_pitch := Vector2(-0.7, 0.5)
var inspect_rate := 3.5
## How long a look over takes, in seconds. The controller holds the flag
## this long (`PlayerController.inspect_left`); every view times the turns
## from when it saw the flag go on.
const INSPECT_SECONDS := 3.4
## The turns the item goes through, as [seconds in, Vector3(pitch, yaw,
## roll)] in radians, eased from one to the next (yaw positive to the left,
## roll about the item's own length): a gun's muzzle swung left across the
## body to show its right side, then out to the right and rolled to show
## its left side and top, then tipped up, and back.
const INSPECT_TURNS := [
	[0.0, Vector3.ZERO],
	[0.55, Vector3(0.15, 1.15, 0.35)],
	[1.25, Vector3(0.15, 1.25, 0.45)],
	[1.95, Vector3(-0.1, -0.35, -1.1)],
	[2.5, Vector3(-0.1, -0.45, -1.2)],
	[3.0, Vector3(0.55, 0.3, 0.0)],
	[3.4, Vector3.ZERO],
]

## Carrying a gun on the move (Caleb's "running with a weapon" pass). Out of
## a fight a gun is carried, not pointed: jogging it sits at a low ready
## (stock in under the shoulder, muzzle down ahead of the feet, both hands
## on it), sprinting a long gun goes across the chest at port (muzzle up and
## to the off side, the off hand on the fore end) and a sidearm is tucked in
## to the chest muzzle down in one hand while the other arm pumps. Shooting,
## aiming or reloading takes it straight back up (`carry_out_rate` is quick,
## the way a sprint-to-fire is). Each pose is where the gun hand's wrist goes
## from the chest, in the actor's frame (x right, y up, z back), and how the
## gun turns from straight ahead (pitch up, yaw toward the off side, roll
## toward the off side, radians). The chest carries it, so the run's own lean
## and bounce move the gun with the body.
var carry_low_long := Vector3(0.16, 1.27, -0.3)
var carry_low_long_turn := Vector3(-0.3, 0.15, 0.08)
var carry_port_long := Vector3(0.15, 1.2, -0.28)
var carry_port_long_turn := Vector3(0.75, 1.0, 0.6)
var carry_low_sidearm := Vector3(0.05, 1.24, -0.3)
var carry_low_sidearm_turn := Vector3(-0.5, 0.1, 0.0)
var carry_port_sidearm := Vector3(0.17, 1.16, -0.2)
var carry_port_sidearm_turn := Vector3(-1.0, 0.15, 0.15)
## How much the off hand holds the gun in each carry: both hands at a low
## ready, a long gun at port; a sprinting sidearm leaves the off arm free.
var carry_support_low := 1.0
var carry_support_port_long := 1.0
var carry_support_port_sidearm := 0.0
## How fast the gun goes into its carry and comes back up out of it, and
## how fast it moves between the low ready and the sprint carry (per second).
var carry_in_rate := 3.5
var carry_out_rate := 9.0
var sprint_rate := 4.0
## The share of the chest's lean (a sprint's, a slide's) the carried gun
## follows: most, so it rides the body, but it stays steadier than the chest.
var carry_body_follow := 0.8
## The bob of a carried gun with each stride: the run's footfalls drop it
## twice a cycle and it swings side to side once, metres at a jog and at a
## sprint, and a little tip of the muzzle with the drop (radians).
var bob_drop := Vector2(0.008, 0.016)
var bob_swing := Vector2(0.01, 0.025)
var bob_tip := 0.04
## Inertia: a carried gun lags behind the body as it speeds up, stops or
## turns, on a damped spring. `sway_gain` is metres per m/s² of the body's
## change of speed, `sway_turn` metres per radian a second of turning,
## `sway_limit` the most it lags, and the spring's stiffness and damping.
var sway_gain := 0.004
var sway_turn := 0.012
var sway_limit := 0.05
var sway_stiffness := 120.0
var sway_damping := 18.0

var actor: Actor

## Set by the skin: true while it holds the gun low (the `idle_gun` stand).
var low_wanted := false
## How far the watch is raised to read (0 lowered, 1 up), eased, from the
## actor's command (`ActorCommand.watch_up`), so remote players raise it too.
var watch := 0.0
## Seconds the watch takes to come up or go down (as `Hud.Wrist.raise_time`).
var watch_time := 0.18
var _watch_raise := 0.0
## How far the phone is up in the right hand (0..1), from the actor's
## command (`ActorCommand.phone`), so everyone who sees them agrees.
var phone := 0.0
## How far the hand is up holding a toy or throwing it (0..1), eased.
var toy := 0.0
## Seconds into the toy throw being shown, or below zero when none is.
var toy_throw_t := -1.0
## Set by the skin: false while the hand is still putting a weapon away, so
## the toy comes up only into an empty hand. True with no skin (checks).
var toy_hand_free := true
var _toy_throws_seen := -1
var _toy_thrown := ""
## How far the item in hand is brought in to be looked over (0..1, eased),
## and how long this look has been going (seconds), from
## `ActorCommand.inspect`.
var inspect := 0.0
var inspect_clock := 0.0
var _inspect_raise := 0.0
var _inspect_was := false

## The melee hand offset, smoothed, and how much it has the arm (0..1).
var reach := Vector3.ZERO
var reach_weight := 0.0
## The shoulder turn and lean that go with `reach`, smoothed.
var turn := Vector2.ZERO
## How cocked the weapon elbow is (1 wound up, 0 thrown through), smoothed.
var elbow_raise := 0.0
## How deep into its reload motion the gun is (0..1), and how low it is held.
var reload := 0.0
var low := 0.0
## How far the gun is up at the eye (0 at the hold, 1 sighted), eased.
var ads := 0.0
## How far in front of the eyes the sight sits now (`relief_for`, drawn in
## to what the model's arm reaches). Set by the skin's arm; a view puts its
## eye this far behind the sight.
var relief_now := -1.0
var _ads_raise := 0.0

## Set by the skin each frame: whether the gun in hand should be carried
## (moving out of a fight), how much of a sprint it is (0..1), and where the
## stride is (`stride_phase`, 0..1 through the gait clip) and how hard the
## body is moving (`stride_amount`, 0 standing to 1 at a sprint).
var carry_wanted := false
var sprint_wanted := 0.0
var stride_phase := 0.0
var stride_amount := 0.0
## How far into its carry the gun is (0 raised, 1 carried), and how far the
## carry is from the low ready toward the sprint carry, eased.
var carry := 0.0
var sprint := 0.0
## How far the carried gun lags behind the body, in the actor's frame, and
## the spring's speed.
var sway := Vector3.ZERO
var _sway_speed := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _last_yaw := 0.0
var _sway_primed := false

var _follow_left := 0.0
var _follow_dir := MeleeWeapon.Dir.OVERHEAD
var _frame := -1


## The pose node of `actor`, made on first use.
static func of(p_actor: Actor) -> ActionPose:
	var pose := p_actor.get_node_or_null(NODE_NAME) as ActionPose
	if pose == null:
		pose = ActionPose.new()
		pose.name = NODE_NAME
		pose.actor = p_actor
		p_actor.add_child(pose)
	return pose


func _ready() -> void:
	set_process(false)


## Moves the pose on to this frame. Every reader calls it before reading;
## only the first call in a frame does anything.
func advance(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return
	_frame = frame
	if actor == null or not is_instance_valid(actor):
		return
	var inspect_wanted := actor.cmd != null and actor.cmd.inspect and not actor.is_dead \
			and actor.vehicle == null and not actor.cmd.phone
	if inspect_wanted and not _inspect_was:
		inspect_clock = 0.0
	_inspect_was = inspect_wanted
	if inspect_wanted or _inspect_raise > 0.0:
		inspect_clock += delta
	else:
		inspect_clock = 0.0
	_inspect_raise = move_toward(_inspect_raise, 1.0 if inspect_wanted else 0.0, inspect_rate * delta)
	inspect = smoothstep(0.0, 1.0, _inspect_raise)

	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
	var holding := melee != null and melee.visual != null and not actor.is_dead
	if holding and melee._swing_left > 0.0 and not melee.is_winding_up():
		_follow_left = follow_hold
		_follow_dir = melee.attack_dir
	elif _follow_left > 0.0:
		_follow_left -= delta
		if not holding or melee.is_winding_up() or melee.is_blocking():
			_follow_left = 0.0

	var wanted: Variant = arm_reach(melee) if holding else null
	reach_weight = move_toward(reach_weight, 0.0 if wanted == null else 1.0, delta * 9.0)
	# A swing is over in a few frames, so it is followed much more tightly.
	var follow := 1.0 - exp(-(70.0 if holding and melee.swing_arc() >= 0.0 else 26.0) * delta)
	if wanted != null:
		reach = wanted if reach_weight < 0.15 else reach.lerp(wanted, follow)
	turn = turn.lerp(body_turn(melee) if holding else Vector2.ZERO, follow)
	held_ready = lerpf(held_ready, ready_amount(melee) if holding else 0.0, follow)
	elbow_raise = lerpf(elbow_raise, elbow_wanted(melee) if holding else 0.0, follow)
	var both := holding and melee.style_now() == "cut" and not melee.showing_back_strike()
	cut_grip = move_toward(cut_grip, 1.0 if both else 0.0, delta * 8.0)

	var watch_wanted := actor.cmd != null and actor.cmd.watch_up and not actor.is_dead
	_watch_raise = move_toward(_watch_raise, 1.0 if watch_wanted else 0.0, delta / maxf(watch_time, 0.001))
	watch = ease(_watch_raise, -2.0)
	var phone_wanted := actor.cmd != null and actor.cmd.phone and not actor.is_dead and actor.vehicle == null
	phone = move_toward(phone, 1.0 if phone_wanted else 0.0, phone_rate * delta)
	advance_toy(delta)

	var gun := weapon as Gun
	reload = reload_depth(gun) if gun != null and not actor.is_dead else 0.0
	var lowered := low_wanted and gun != null and not gun.is_aiming() and reload <= 0.0 \
			and inspecting() != "gun"
	low = move_toward(low, 1.0 if lowered else 0.0, delta * (lower_rate if lowered else raise_rate))
	_ads_raise = move_toward(_ads_raise, 1.0 if ads_wanted(gun) else 0.0, delta * ads_rate)
	ads = ease(_ads_raise, -2.0)
	var carried := carry_wanted and gun != null and not actor.is_dead and reload <= 0.0 and not gun.is_aiming() \
			and inspecting() != "gun"
	carry = move_toward(carry, 1.0 if carried else 0.0, delta * (carry_in_rate if carried else carry_out_rate))
	sprint = move_toward(sprint, clampf(sprint_wanted, 0.0, 1.0), delta * sprint_rate)
	_update_sway(delta)


## The carried gun's lag behind the body: a damped spring pulled by how the
## body's speed and heading change, so it trails a start, swings on through
## a stop and lags round a turn. View only, read from the actor's velocity
## and facing, so a remote player's gun sways the same.
func _update_sway(delta: float) -> void:
	var basis := actor.global_basis.orthonormalized()
	var local := basis.inverse() * actor.velocity
	local.y = 0.0
	var yaw := actor.global_rotation.y
	if not _sway_primed or delta <= 0.0:
		_sway_primed = true
		_last_velocity = local
		_last_yaw = yaw
		return
	var accel := (local - _last_velocity) / delta
	var turning := wrapf(yaw - _last_yaw, -PI, PI) / delta
	_last_velocity = local
	_last_yaw = yaw
	# A start pulls the gun back, a stop throws it on, a turn left leaves it
	# out to the right.
	var pull := (-accel * sway_gain + Vector3(turning * sway_turn, 0.0, 0.0)).limit_length(sway_limit * 2.0)
	var step := minf(delta, 1.0 / 30.0)
	var steps := ceili(delta / step)
	for i in steps:
		var force := (pull - sway) * sway_stiffness - _sway_speed * sway_damping
		_sway_speed += force * step
		sway += _sway_speed * step
	sway = sway.limit_length(sway_limit)


## Where the gun hand's wrist goes in the carry now, from the chest, and how
## the gun turns from straight ahead (pitch, yaw, roll), for `gun`: the low
## ready blended toward the sprint carry, plus the stride's bob and the sway.
func carry_point(gun: Gun) -> Vector3:
	var side := gun != null and gun.is_sidearm
	var low_at := carry_low_sidearm if side else carry_low_long
	var port_at := carry_port_sidearm if side else carry_port_long
	return low_at.lerp(port_at, sprint) + carry_bob() + sway


func carry_turn(gun: Gun) -> Vector3:
	var side := gun != null and gun.is_sidearm
	var low_turn := carry_low_sidearm_turn if side else carry_low_long_turn
	var port_turn := carry_port_sidearm_turn if side else carry_port_long_turn
	var drop := cos(TAU * 2.0 * stride_phase) * stride_amount
	return low_turn.lerp(port_turn, sprint) + Vector3(-bob_tip * drop, 0.0, 0.0)


## A turn given as pitch (up), yaw (toward the off side) and roll (top
## toward the off side), in radians, from straight ahead.
static func turn_basis(turn: Vector3) -> Basis:
	return Basis(Vector3.UP, turn.y) * Basis(Vector3.RIGHT, turn.x) * Basis(Vector3.BACK, turn.z)


## How much the off hand holds the carried gun (0..1).
func carry_support(gun: Gun) -> float:
	var side := gun != null and gun.is_sidearm
	return lerpf(carry_support_low, carry_support_port_sidearm if side else carry_support_port_long, sprint)


## The stride's bob of a carried gun, in the actor's frame: down at each
## footfall, side to side once a cycle, bigger the harder the body moves.
func carry_bob() -> Vector3:
	if stride_amount <= 0.0:
		return Vector3.ZERO
	var drop := lerpf(bob_drop.x, bob_drop.y, sprint) * stride_amount
	var swing := lerpf(bob_swing.x, bob_swing.y, sprint) * stride_amount
	return Vector3(swing * sin(TAU * stride_phase), -drop * cos(TAU * 2.0 * stride_phase), 0.0)


## Moves the toy hold and throw on by `delta` seconds. A throw starts when
## `Actor.toy_throws` goes up (not for the count first seen: a body that
## comes into view mid-game does not replay an old throw).
func advance_toy(delta: float) -> void:
	if _toy_throws_seen < 0:
		_toy_throws_seen = actor.toy_throws
	if actor.toy_throws != _toy_throws_seen:
		_toy_throws_seen = actor.toy_throws
		toy_throw_t = 0.0 if not actor.is_dead else -1.0
		_toy_thrown = actor.toy_in_hand
	elif toy_throw_t >= 0.0:
		toy_throw_t += delta
		if toy_throw_t >= toy_throw_time or actor.is_dead:
			toy_throw_t = -1.0
	# The toy thrown may stay in the hand's record a moment after it has
	# flown (online, until the server says so): it is gone all the same.
	if actor.toy_in_hand != _toy_thrown:
		_toy_thrown = ""
	var holding := held_toy() != "" and toy_hand_free
	if toy_throw_t >= 0.0:
		# A throw takes the hand at once and hands it back as it ends.
		var going := smoothstep(toy_follow_at, toy_throw_time, toy_throw_t) if not holding else 0.0
		toy = minf(maxf(toy, smoothstep(0.0, 0.08, toy_throw_t)), 1.0 - going)
	else:
		toy = move_toward(toy, 1.0 if holding else 0.0, toy_rate * delta)


## The toy held up in the hand (not one already thrown), or "".
func held_toy() -> String:
	if actor.is_dead or actor.vehicle != null or actor.toy_in_hand == _toy_thrown:
		return ""
	return actor.toy_in_hand


## The toy the hand shows: held, or thrown and not yet let go. "" for none.
func toy_shown() -> String:
	if actor.is_dead or actor.vehicle != null:
		return ""
	if toy_throw_t >= 0.0:
		return _toy_thrown if toy_throw_t < toy_release else ""
	return held_toy()


## True while the hand is busy with a toy (held up or mid-throw): the weapon
## stays put away.
func toy_busy() -> bool:
	return toy > 0.0 or toy_throw_t >= 0.0 or held_toy() != ""


## Where the throwing hand goes now, in the actor's frame: up holding the toy,
## or along the throw (back over the shoulder, through the release, down
## across the body).
func toy_hand_point() -> Vector3:
	var at := toy_hold
	var t := toy_throw_t
	if t >= 0.0:
		if t < toy_cocked_at:
			at = toy_hold.lerp(toy_cocked, smoothstep(0.0, toy_cocked_at, t))
		elif t < toy_release:
			# The whip: slow out of the cock, fastest at the release.
			var u := (t - toy_cocked_at) / maxf(toy_release - toy_cocked_at, 0.001)
			at = _toy_arc(toy_cocked, toy_let_go, u * u)
		else:
			var u := clampf((t - toy_release) / maxf(toy_follow_at - toy_release, 0.001), 0.0, 1.0)
			at = toy_let_go.lerp(toy_follow, 1.0 - (1.0 - u) * (1.0 - u))
	var pitch := clampf(actor.cmd.pitch if actor.cmd != null else 0.0, -1.2, 1.2) * toy_pitch_share
	return shoulder + Basis(Vector3.RIGHT, pitch) * (at - shoulder)


## From `from` to `to` over the top of the shoulder, not straight through it.
func _toy_arc(from: Vector3, to: Vector3, u: float) -> Vector3:
	return from.lerp(to, u) + Vector3(0.0, 0.12, 0.0) * sin(u * PI)


## The shoulder turn and lean of the throw (as `turn`), 0 outside one.
func toy_turn() -> Vector2:
	var t := toy_throw_t
	if t < 0.0:
		return Vector2.ZERO
	if t < toy_cocked_at:
		return toy_turn_cocked * smoothstep(0.0, toy_cocked_at, t)
	if t < toy_release:
		return toy_turn_cocked.lerp(toy_turn_thrown, smoothstep(toy_cocked_at, toy_release, t))
	return toy_turn_thrown * (1.0 - smoothstep(toy_release, toy_throw_time, t))


## How cocked the throwing elbow is (0 to 1): up and back through the draw,
## dropping as the arm comes through.
func toy_elbow_raise() -> float:
	var t := toy_throw_t
	if t < 0.0:
		return 0.0
	return smoothstep(0.0, toy_cocked_at, t) * (1.0 - smoothstep(toy_cocked_at, toy_follow_at, t))


## True while `gun` should be up at the eye: aimed, in hand, shown, not
## mid-reload, on foot or riding, and not one that is braced at the hip.
func ads_wanted(gun: Gun) -> bool:
	if gun == null or actor.is_dead or not gun.is_aiming() or reload > 0.0:
		return false
	if gun.visual == null or not gun.visual.visible:
		return false
	return not shoulders_never(gun)


## The aiming stance for `gun` (see `ads_stance_long`).
func ads_stance(gun: Gun) -> Vector2:
	if gun == null:
		return Vector2.ZERO
	return ads_stance_sidearm if gun.is_sidearm else ads_stance_long


## True for a gun that is aimed from the hip (`ads_hip_tags`).
func shoulders_never(gun: Gun) -> bool:
	for tag in ads_hip_tags:
		if ItemDB.has_tag(gun.item_id, tag):
			return true
	return false


## How far in front of the eyes the sight of `gun` sits when sighted.
## An optic's "Sight" marker is already its eye point, so it needs none.
func relief_for(gun: Gun) -> float:
	if optic_sight(gun) != null:
		return 0.0
	if gun.is_sidearm or ItemDB.has_tag(gun.item_id, "sidearm"):
		return sidearm_relief
	var box := model_box(gun)
	if box.size == Vector3.ZERO:
		return min_relief
	return maxf(box.end.z - stock_ahead - sight_local(gun).z, min_relief)


## The bounds of the gun as drawn, in the space of its visual (worked out
## once it has a model, and kept). Empty with nothing drawn.
static func model_box(gun: Gun) -> AABB:
	if gun.visual.has_meta("model_box"):
		return gun.visual.get_meta("model_box")
	var box := AABB()
	var first := true
	var to_visual := gun.visual.global_transform.affine_inverse()
	for node in gun.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.visible:
			continue
		var part: AABB = (to_visual * mesh.global_transform) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	if not first and gun.visual.has_node("Model"):
		gun.visual.set_meta("model_box", box)
	return box


## The fitted optic's eye point, or null for plain sights.
static func optic_sight(gun: Gun) -> Node3D:
	if gun == null or gun.visual == null:
		return null
	return gun.visual.get_node_or_null("Attachments/optic/Sight") as Node3D


## Where you look along `gun` from, in the space of its visual: an optic's
## eye point, else the rear of the plain sights, the top of the model a
## little way in from its back end (worked out once and kept).
static func sight_local(gun: Gun) -> Vector3:
	var optic := optic_sight(gun)
	if optic != null:
		return gun.visual.global_transform.affine_inverse() * optic.global_position
	var iron := gun.visual.get_node_or_null("IronSight") as Node3D
	if iron != null:
		return iron.position
	var box := model_box(gun)
	if box.size == Vector3.ZERO:
		return Vector3(0.0, 0.08, 0.0)
	return Vector3(box.get_center().x, box.end.y, box.end.z - box.size.z * 0.25)


## Where the gun hand holds `gun`, in the space of its visual: the origin
## where the fist closes on the pistol grip, level with the trigger, and
## the basis's y up along the grip (the "Grip" marker that `Look` finds on
## the model, see `Look._measure_hold`). Null on a model without one.
static func hold_local(gun: Gun) -> Variant:
	if gun == null or gun.visual == null:
		return null
	var mark := gun.visual.get_node_or_null("Grip") as Node3D
	if mark == null:
		mark = gun.visual.get_node_or_null("Model/Grip") as Node3D
	if mark == null:
		return null
	# Read through how the model sits in the hand, not where a draw or
	# holster is carrying it this frame (`ActorSkin._carry_moving`).
	var at := mark.transform
	var up_node := mark.get_parent_node_3d()
	while up_node != null and up_node != gun.visual:
		at = (up_node.get_meta("held_at", up_node.transform) as Transform3D) * at
		up_node = up_node.get_parent_node_3d()
	var up := (at.basis * (mark.get_meta("up", Vector3.UP) as Vector3)).normalized()
	var side := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var back := side.cross(up).normalized()
	return Transform3D(Basis(up.cross(back).normalized(), up, back), at.origin)


## Where the sight of `gun` is drawn, wherever the physics tick left the
## hand node: the hand as the skin last showed it, kept from the actor
## ("shown_local", set by `WeaponArm.hold_weapon`) and carried along to
## where the actor is now, the way the eyes are. A view that follows the
## sight then never sees the tick's resting hand or a frame's lag behind the
## body (both showed as a stutter while aiming).
static func sight_shown(gun: Gun) -> Vector3:
	var hand := gun.visual.get_parent() as Node3D
	var at := gun.visual.global_transform * sight_local(gun)
	if hand == null or not hand.has_meta("shown_local"):
		return at
	var holder := hand.get_parent() as Node3D
	var shown: Transform3D = holder.global_transform * (hand.get_meta("shown_local") as Transform3D)
	return shown * (hand.global_transform.affine_inverse() * at)


## The hand offset the current melee state asks for, or null when the
## animation should have the hand.
func arm_reach(melee: MeleeWeapon) -> Variant:
	if melee == null or actor.is_dead:
		return null
	if melee._slamming:
		return windup_reach(melee, MeleeWeapon.Dir.OVERHEAD)
	if melee.showing_back_strike():
		return arm_back * (0.4 + 0.6 * maxf(melee.swing_arc(), 0.0))
	var arc := melee.swing_arc()
	if arc >= 0.0:
		if melee.style_now() == "cut":
			return cut_reach(melee, melee.attack_dir, arc)
		if melee.style_now() == "thrust":
			# Straight out along the aim, not round the shoulder.
			return windup_reach(melee, melee.attack_dir).lerp(follow_reach(melee, melee.attack_dir), arc)
		return swing_reach(windup_reach(melee, melee.attack_dir), follow_reach(melee, melee.attack_dir), arc)
	if melee.is_winding_up():
		return windup_reach(melee, melee.attack_dir) * (1.0 + windup_coil * melee.windup_coil())
	if _follow_left > 0.0:
		return follow_reach(melee, _follow_dir)
	if melee.is_blocking():
		if melee.style_now() == "cut":
			return cut_guards[melee.guard_dir][0]
		return arm_guard
	var hold: Variant = ready_reach(melee)
	var rest: Vector3 = hold if hold != null else Vector3.ZERO
	var charge := charge_amount(melee)
	if charge > 0.0:
		return rest.lerp(windup_reach(melee, MeleeWeapon.swing_from(melee.stance)), charge)
	var back := recover_left(melee)
	if back > 0.0:
		return rest.lerp(follow_reach(melee, melee.attack_dir), back)
	if inspect_for("melee") > 0.0:
		# The resting hand's offset (from `Actor.HAND_REST`, in the aim
		# frame) that puts it on the inspect point, eased from the hold.
		var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
		var at := actor.global_transform * Actor.HAND_REST
		return rest.lerp(aim.inverse() * (inspect_point() - at), inspect)
	return hold


## The ready hold `melee` is held in at rest (an entry of `ready_holds`), or
## an empty array for a two-handed weapon, which is carried instead.
func ready_hold(melee: MeleeWeapon) -> Array:
	if melee == null or melee.is_two_handed():
		return []
	return ready_holds.get(Look.ready_hold(melee), [])


## Where the hand is held ready (`ready_holds`), or null.
func ready_reach(melee: MeleeWeapon) -> Variant:
	var hold := ready_hold(melee)
	return hold[0] if not hold.is_empty() else null


## How the weapon stands in the hand held ready, in the aim frame, as the
## turn of the hand node (the weapon's own rest pitch taken back out), or
## null when it has no ready hold.
func ready_turn(melee: MeleeWeapon) -> Variant:
	var hold := ready_hold(melee)
	if hold.is_empty():
		return null
	var points := (hold[1] as Vector3).normalized()
	return Basis(Quaternion(Vector3.UP, points)) * Basis(Vector3.RIGHT, -MeleeWeapon.REST_POSE)


## True while the blade is held reversed in the fist (`ready_holds`): from
## halfway into the ready hold, so it turns over as an attack starts.
func ready_reversed(melee: MeleeWeapon) -> bool:
	var hold := ready_hold(melee)
	return not hold.is_empty() and hold[3] and held_ready > 0.5


## What the off hand does in the ready hold: "guard" (up empty, low in
## front), "hilt" (on the handle under the weapon hand) or "" (nothing).
func ready_off(melee: MeleeWeapon) -> String:
	var hold := ready_hold(melee)
	return hold[2] if not hold.is_empty() else ""


## How much the ready hold has the weapon (0..1): all of it at rest, none
## through an attack or guard, and part of it while drawing back for a heavy
## or easing back after a strike.
func ready_amount(melee: MeleeWeapon) -> float:
	if melee == null or actor.is_dead or ready_hold(melee).is_empty():
		return 0.0
	if melee._slamming or melee.showing_back_strike() or melee.swing_arc() >= 0.0:
		return 0.0
	if melee.is_winding_up() or _follow_left > 0.0 or melee.is_blocking():
		return 0.0
	var charge := charge_amount(melee)
	if charge > 0.0:
		return 1.0 - charge
	# Looked over, the weapon turns in the hand as the inspect says.
	return (1.0 - recover_left(melee)) * (1.0 - inspect_for("melee"))


## The shoulder turn and lean that go with `arm_reach`: heavier for a
## two-hander, leaning in through a dash-strike.
func body_turn(melee: MeleeWeapon) -> Vector2:
	if melee == null or actor.is_dead:
		return Vector2.ZERO
	var turned := _body_turn(melee)
	if melee.is_two_handed():
		turned *= two_hand_turn
	if melee._dashing and melee.is_lunging():
		turned.y -= dash_lean
	return turned


func _body_turn(melee: MeleeWeapon) -> Vector2:
	if melee._slamming:
		return windup_turn(melee, MeleeWeapon.Dir.OVERHEAD)
	if melee.showing_back_strike():
		return turn_back
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return windup_turn(melee, melee.attack_dir).lerp(follow_turn(melee, melee.attack_dir), arc)
	if melee.is_winding_up():
		return windup_turn(melee, melee.attack_dir) * (1.0 + windup_coil * melee.windup_coil())
	if _follow_left > 0.0:
		return follow_turn(melee, _follow_dir)
	if melee.is_blocking():
		return Vector2(MeleeWeapon._side(melee.guard_dir) * turn_guard, 0.0)
	var charge := charge_amount(melee)
	if charge > 0.0:
		return windup_turn(melee, MeleeWeapon.swing_from(melee.stance)) * charge
	var back := recover_left(melee)
	if back > 0.0:
		return follow_turn(melee, melee.attack_dir) * back
	return Vector2.ZERO


## Where the hand is cocked for a swing from `dir`, by the weapon's style
## and scaled by its `swing_scale` (a knife's swings are small).
func windup_reach(melee: MeleeWeapon, dir: int) -> Vector3:
	var at: Vector3
	match melee.style_now():
		"thrust":
			at = thrust_windup + Vector3(-MeleeWeapon._side(dir) * 0.1, 0.0, 0.0)
		"chop":
			at = (arm_windup[dir] as Vector3) + chop_raise
		"cut":
			var key: Variant = cut_key(melee, dir)
			at = cuts[key][0][0]
			if key is int and is_heavy(melee):
				at += cut_heavy_raise
		_:
			at = arm_windup[dir]
	return at * melee.swing_scale


## Where the hand ends a swing from `dir`.
func follow_reach(melee: MeleeWeapon, dir: int) -> Vector3:
	var at: Vector3
	match melee.style_now():
		"thrust":
			at = thrust_follow
		"chop":
			at = (arm_follow[dir] as Vector3) + chop_drop
		"cut":
			at = cuts[cut_key(melee, dir)][2][0]
		_:
			at = arm_follow[dir]
	return at * melee.swing_scale


## The shoulder turn and lean for a windup from `dir`.
func windup_turn(melee: MeleeWeapon, dir: int) -> Vector2:
	match melee.style_now():
		"thrust":
			return thrust_turn_windup
		"chop":
			return (turn_windup[dir] as Vector2) + Vector2(0.0, chop_lean)
		"cut":
			var turned: Vector2 = cut_turns[cut_key(melee, dir)][0]
			return turned * (cut_heavy_coil if is_heavy(melee) else 1.0)
	return turn_windup[dir]


## The shoulder turn and lean at the end of a swing from `dir`.
func follow_turn(melee: MeleeWeapon, dir: int) -> Vector2:
	match melee.style_now():
		"thrust":
			return thrust_turn_follow
		"chop":
			return (turn_follow[dir] as Vector2) - Vector2(0.0, chop_lean * 1.5)
		"cut":
			return cut_turns[cut_key(melee, dir)][1]
	return turn_follow[dir]


## The hand offset `done` (0..1) of the way through a swing from `from` to
## `to`: turned about the shoulder rather than cut straight across, with the
## arm reaching out through the middle.
func swing_reach(from: Vector3, to: Vector3, done: float) -> Vector3:
	var a := Actor.HAND_REST + from - shoulder
	var b := Actor.HAND_REST + to - shoulder
	var way := a.normalized().slerp(b.normalized(), done)
	var length := minf(lerpf(a.length(), b.length(), done) + swing_extend * sin(PI * done), arm_length)
	return shoulder + way * length - Actor.HAND_REST


## How cocked the elbow should be for the current melee state (0..1).
func elbow_wanted(melee: MeleeWeapon) -> float:
	if melee == null or actor.is_dead:
		return 0.0
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return 1.0 - arc
	if melee._slamming or melee.is_winding_up():
		return 1.0
	if melee.is_blocking():
		return 0.6
	return maxf(charge_amount(melee), 0.0)


## The weapon elbow's pole in the actor's frame, between cocked and thrown
## (lower through a two-handed cut).
func elbow_pole() -> Vector3:
	var pole := elbow_thrown.lerp(elbow_cocked, elbow_raise)
	return pole.lerp(cut_elbow_thrown.lerp(cut_elbow_cocked, elbow_raise), cut_grip)


## Which cut `melee` shows from `dir` (a key of `cuts`): the side's own, or
## the tsuki for a heavy from the middle stance (the dive slam is still
## jodan to shomen).
func cut_key(melee: MeleeWeapon, dir: int) -> Variant:
	if dir == MeleeWeapon.Dir.OVERHEAD and not melee._slamming and is_heavy(melee):
		return "tsuki"
	return dir


## True while `melee` is showing, winding up or drawing back toward a heavy.
static func is_heavy(melee: MeleeWeapon) -> bool:
	if melee.is_winding_up():
		return melee._windup_kind == "heavy"
	if charge_amount(melee) > 0.0:
		return true
	return melee._shown_kind == "heavy"


## The hand offset `done` (0..1) of the way through the cut from `dir`: on a
## curve from the windup through the contact key (at the hit, half way) to
## the end of the follow-through.
func cut_reach(melee: MeleeWeapon, dir: int, done: float) -> Vector3:
	var from := windup_reach(melee, dir)
	var to := follow_reach(melee, dir)
	var hit: Vector3 = cuts[cut_key(melee, dir)][1][0] * melee.swing_scale
	var bend := hit * 2.0 - (from + to) * 0.5
	var t := clampf(done, 0.0, 1.0)
	return from * (1.0 - t) * (1.0 - t) + bend * 2.0 * t * (1.0 - t) + to * t * t


## How a cut has the blade this frame, in the aim frame (the weapon's own
## frame turned so its blade runs the way the cut says and its edge leads),
## or null when no cut has it (at rest the ready hold does). Both views
## turn the weapon hand by it (`WeaponArm._blade_turn`).
func cut_blade(melee: MeleeWeapon) -> Variant:
	if melee == null or actor.is_dead or melee.style_now() != "cut" or melee.showing_back_strike():
		return null
	if melee._slamming:
		return _cut_blade_at(cut_key(melee, MeleeWeapon.Dir.OVERHEAD), 0.0)
	var arc := melee.swing_arc()
	if arc >= 0.0:
		return _cut_blade_at(cut_key(melee, melee.attack_dir), arc)
	if melee.is_winding_up():
		return _cut_blade_at(cut_key(melee, melee.attack_dir), 0.0)
	if _follow_left > 0.0:
		return _cut_blade_at(cut_key(melee, _follow_dir), 1.0)
	if melee.is_blocking():
		var guard: Array = cut_guards[melee.guard_dir]
		var edge := Vector3.UP if melee.guard_dir == MeleeWeapon.Dir.OVERHEAD else Vector3.FORWARD
		return blade_basis(guard[1], edge)
	var hold := ready_hold(melee)
	var rest := Basis(Quaternion(Vector3.UP, (hold[1] as Vector3).normalized())) if not hold.is_empty() else Basis.IDENTITY
	var charge := charge_amount(melee)
	if charge > 0.0:
		return _blend(rest, _cut_blade_at(cut_key(melee, MeleeWeapon.swing_from(melee.stance)), 0.0), charge)
	var back := recover_left(melee)
	if back > 0.0:
		return _blend(rest, _cut_blade_at(cut_key(melee, melee.attack_dir), 1.0), back)
	return null


## The blade `done` of the way through the cut `key`: turned from the
## windup through the contact key to the follow-through, the edge leading
## the way it turns (down, for the tsuki).
func _cut_blade_at(key: Variant, done: float) -> Basis:
	var keys: Array = cuts[key]
	var a := (keys[0][1] as Vector3).normalized()
	var b := (keys[1][1] as Vector3).normalized()
	var c := (keys[2][1] as Vector3).normalized()
	var t := clampf(done, 0.0, 1.0)
	var dir := a.slerp(b, t * 2.0) if t < 0.5 else b.slerp(c, t * 2.0 - 1.0)
	var lead := b - a if t < 0.5 else c - b
	if key is String:
		lead = Vector3.DOWN
	return blade_basis(dir, lead)


## The weapon's frame with its blade along `dir` and its edge (`cut_edge`)
## turned as near `edge` as it can face, both in the aim frame.
func blade_basis(dir: Vector3, edge: Vector3) -> Basis:
	var up := dir.normalized()
	var face := edge - up * edge.dot(up)
	if face.length() < 0.05:
		face = Vector3.DOWN - up * up.y
		if face.length() < 0.05:
			face = Vector3.FORWARD
	face = face.normalized()
	var own_face := (cut_edge - Vector3.UP * cut_edge.y).normalized()
	var wanted := Basis(up, face, up.cross(face))
	var own := Basis(Vector3.UP, own_face, Vector3.UP.cross(own_face))
	return (wanted * own.inverse()).orthonormalized()


static func _blend(from: Basis, to: Basis, weight: float) -> Basis:
	return Basis(from.get_rotation_quaternion().slerp(to.get_rotation_quaternion(), clampf(weight, 0.0, 1.0)))


## How far the arm is drawn back while the button is held toward a heavy
## (0..1), toward the side the swing will come from, or -1 when not.
static func charge_amount(melee: MeleeWeapon) -> float:
	var held := -1.0
	if melee._charge >= 0.0:
		held = melee._charge
	elif melee._queued and melee._queued_held >= 0.0:
		held = melee._queued_held
	if held < 0.0:
		return -1.0
	return clampf(held / maxf(melee.hold_time, 0.01), 0.0, 1.0)


## How much of the follow-through the arm still holds while the blade
## recovers after a strike (1 just after, easing to 0 once ready), so the
## wait before the next attack shows in both views.
static func recover_left(melee: MeleeWeapon) -> float:
	var done := melee.recover_progress()
	if done < 0.0:
		return 0.0
	return 1.0 - smoothstep(0.0, 1.0, done)


## How far through the shown swing (0 to 1), or 0 when none is showing.
static func swing_progress(melee: MeleeWeapon) -> float:
	return maxf(melee.swing_arc(), 0.0)


## How deep into the reload motion `gun` is: 0 outside a reload, easing to 1
## over the first `reload_ease` of it, held, and back to 0 as it ends.
func reload_depth(gun: Gun) -> float:
	if gun == null or not gun.is_reloading() or gun.reload_time <= 0.0:
		return 0.0
	var done := 1.0 - clampf(gun.reload_left() / gun.reload_time, 0.0, 1.0)
	var ease_in := smoothstep(0.0, reload_ease, done)
	var ease_out := 1.0 - smoothstep(1.0 - reload_ease, 1.0, done)
	return minf(ease_in, ease_out)


## The gun's offset from its usual hold, in the aim frame: the reload
## motion, and the gun brought in and turned while it is looked over.
func gun_offset() -> Transform3D:
	var reloading := Transform3D(Basis.from_euler(reload_tilt * reload), reload_reach * reload)
	if inspecting() != "gun":
		return reloading
	return Transform3D(inspect_basis(), Vector3.ZERO) * reloading


## Where the wrist goes to look the item in hand over, in the world: in
## front of the chest, under the eyes along the aim (`inspect_from_eyes`).
func inspect_point() -> Vector3:
	var pitch := clampf(actor.cmd.pitch, inspect_pitch.x, inspect_pitch.y)
	var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, pitch)
	return actor.get_eye_position() + aim * inspect_from_eyes


## What is being looked over: "gun", "melee", "hand" (a toy vehicle held
## up, `Actor.toy_in_hand`), or "" when nothing is.
func inspecting() -> String:
	if inspect <= 0.0 or actor == null or actor.is_dead:
		return ""
	if toy_busy():
		return "hand"
	var weapon := actor.get_active_weapon()
	if weapon == null or weapon.visual == null or not weapon.visual.visible:
		return "hand"
	if weapon is Gun:
		return "gun"
	if weapon is MeleeWeapon:
		return "melee"
	return "hand"


## How much of the hand's (or gun's) own reach and turn the look over has,
## for what `inspecting` says is in hand: 0 when something else is.
func inspect_for(what: String) -> float:
	return inspect if inspecting() == what else 0.0


## How the item in hand is turned now while looked over, in the aim frame
## (identity when it is not).
func inspect_basis() -> Basis:
	if inspect <= 0.0:
		return Basis.IDENTITY
	return Basis.from_euler(inspect_turn(inspect_clock) * inspect)


## The turn `seconds` into a look over (`INSPECT_TURNS`), eased between
## the steps, back to none once it is done.
static func inspect_turn(seconds: float) -> Vector3:
	var last: Array = INSPECT_TURNS[INSPECT_TURNS.size() - 1]
	if seconds <= 0.0 or seconds >= float(last[0]):
		return Vector3.ZERO
	for i in range(1, INSPECT_TURNS.size()):
		var to: Array = INSPECT_TURNS[i]
		if seconds <= float(to[0]):
			var from: Array = INSPECT_TURNS[i - 1]
			var done := (seconds - float(from[0])) / maxf(float(to[0]) - float(from[0]), 0.001)
			return (from[1] as Vector3).lerp(to[1], smoothstep(0.0, 1.0, done))
	return Vector3.ZERO
