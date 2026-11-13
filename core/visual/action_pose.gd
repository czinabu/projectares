class_name ActionPose
extends Node
## One actor's animation state for the weapon hand, shared by every view of
## that actor so the same action reads the same way in first and third person.
##
## Third person, `WeaponArm` reaches the model's arm to it and `ActorSkin`
## plays weapon switches from it. First person, where the body is not drawn,
## `PlayerController` moves the held weapon in front of the camera by the very
## same offsets, on the same clock. Nothing here feeds back into the
## simulation: it is read from the actor and its command, and only views read
## it. It is a child of the actor named `NODE_NAME`, made by the first view
## that asks (`ActionPose.of`), so a headless server never has one.
##
## Offsets are in the aim frame: the actor's facing turned by its pitch, with
## x to the actor's right, y up and z back. Third person they apply from the
## model's hand (or `Actor.HAND_REST` for melee); first person from
## `PlayerController.FIRST_PERSON_HAND`.

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
## A reload: at its deepest the gun is brought down and in toward the off
## hand (`reload_reach`), and tipped (`reload_tilt`: pitch, yaw, roll in
## radians, roll positive to the left) to bring the magazine well round.
## `reload_ease` is the share of the reload spent going in and coming out.
var reload_reach := Vector3(-0.1, -0.12, 0.08)
var reload_tilt := Vector3(0.3, 0.15, 0.75)
var reload_ease := 0.22
## Standing still out of a fight, third person holds a gun low (the
## `idle_gun` clip); first person lowers it by this much. Raised quickly,
## lowered slowly, per second.
var low_reach := Vector3(-0.05, -0.08, 0.05)
var low_tilt := Vector3(-0.38, 0.28, 0.1)
var raise_rate := 9.0
var lower_rate := 2.5
## How fast the phone comes up and goes away (per second).
var phone_rate := 5.0

var actor: Actor

## Set by the skin each frame (see `ActorSkin._update_switch`): how far the
## hand is toward a holster while switching (0 in hand, 1 at the holster),
## and where that holster is, in the actor's frame.
var switch_weight := 0.0
var switch_point := Actor.HAND_REST
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
	var weapon := actor.get_active_weapon()
	var melee := weapon as MeleeWeapon
	var holding := melee != null and melee.visual != null and not actor.is_dead
	if holding and melee._swing_left > 0.0:
		_follow_left = follow_hold
		_follow_dir = melee.attack_dir
	elif _follow_left > 0.0:
		_follow_left -= delta
		if not holding or melee.is_winding_up() or melee.is_blocking():
			_follow_left = 0.0

	var wanted: Variant = arm_reach(melee) if holding else null
	reach_weight = move_toward(reach_weight, 0.0 if wanted == null else 1.0, delta * 9.0)
	# A swing is over in a few frames, so it is followed much more tightly.
	var follow := 1.0 - exp(-(70.0 if holding and melee._swing_left > 0.0 else 26.0) * delta)
	if wanted != null:
		reach = wanted if reach_weight < 0.15 else reach.lerp(wanted, follow)
	turn = turn.lerp(body_turn(melee) if holding else Vector2.ZERO, follow)
	elbow_raise = lerpf(elbow_raise, elbow_wanted(melee) if holding else 0.0, follow)

	var watch_wanted := actor.cmd != null and actor.cmd.watch_up and not actor.is_dead
	_watch_raise = move_toward(_watch_raise, 1.0 if watch_wanted else 0.0, delta / maxf(watch_time, 0.001))
	watch = ease(_watch_raise, -2.0)
	var phone_wanted := actor.cmd != null and actor.cmd.phone and not actor.is_dead and actor.vehicle == null
	phone = move_toward(phone, 1.0 if phone_wanted else 0.0, phone_rate * delta)

	var gun := weapon as Gun
	reload = reload_depth(gun) if gun != null and not actor.is_dead else 0.0
	var lowered := low_wanted and gun != null and not gun.is_aiming() and reload <= 0.0
	low = move_toward(low, 1.0 if lowered else 0.0, delta * (lower_rate if lowered else raise_rate))


## The hand offset the current melee state asks for, or null when the
## animation (or, first person, the resting hold) should have the hand.
func arm_reach(melee: MeleeWeapon) -> Variant:
	if melee == null or actor.is_dead:
		return null
	if melee._slamming:
		return arm_windup[MeleeWeapon.Dir.OVERHEAD]
	if melee.is_winding_up():
		return arm_windup[melee.attack_dir]
	if melee._swing_left > 0.0:
		return swing_reach(arm_windup[melee.attack_dir], arm_follow[melee.attack_dir], swing_progress(melee))
	if _follow_left > 0.0:
		return arm_follow[_follow_dir]
	if melee.is_blocking():
		return arm_guard
	var charge := charge_amount(melee)
	if charge > 0.0:
		return (arm_windup[MeleeWeapon.swing_from(melee.stance)] as Vector3) * charge
	var back := recover_left(melee)
	if back > 0.0:
		return (arm_follow[melee.attack_dir] as Vector3) * back
	return null


## The shoulder turn and lean that go with `arm_reach`.
func body_turn(melee: MeleeWeapon) -> Vector2:
	if melee == null or actor.is_dead:
		return Vector2.ZERO
	if melee._slamming:
		return turn_windup[MeleeWeapon.Dir.OVERHEAD]
	if melee.is_winding_up():
		return turn_windup[melee.attack_dir]
	if melee._swing_left > 0.0:
		return (turn_windup[melee.attack_dir] as Vector2).lerp(turn_follow[melee.attack_dir], swing_progress(melee))
	if _follow_left > 0.0:
		return turn_follow[_follow_dir]
	if melee.is_blocking():
		return Vector2(MeleeWeapon._side(melee.guard_dir) * turn_guard, 0.0)
	var charge := charge_amount(melee)
	if charge > 0.0:
		return (turn_windup[MeleeWeapon.swing_from(melee.stance)] as Vector2) * charge
	var back := recover_left(melee)
	if back > 0.0:
		return (turn_follow[melee.attack_dir] as Vector2) * back
	return Vector2.ZERO


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
	if melee._slamming or melee.is_winding_up():
		return 1.0
	if melee._swing_left > 0.0:
		return 1.0 - swing_progress(melee)
	if melee.is_blocking():
		return 0.6
	return maxf(charge_amount(melee), 0.0)


## The weapon elbow's pole in the actor's frame, between cocked and thrown.
func elbow_pole() -> Vector3:
	return elbow_thrown.lerp(elbow_cocked, elbow_raise)


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


static func swing_progress(melee: MeleeWeapon) -> float:
	return 1.0 - clampf(melee._swing_left / MeleeWeapon.SWING_TIME, 0.0, 1.0)


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
## motion, plus (first person only, where no clip lowers it) the low ready.
func gun_offset(with_low: bool) -> Transform3D:
	var at := reload_reach * reload
	var tilt := reload_tilt * reload
	if with_low:
		at += low_reach * low
		tilt += low_tilt * low
	return Transform3D(Basis.from_euler(tilt), at)
