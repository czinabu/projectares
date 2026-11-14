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
var inspect_from_eyes := Vector3(0.08, -0.3, -0.4)
var inspect_pitch := Vector2(-0.7, 0.5)
var inspect_rate := 3.5
## How long a look over takes, in seconds. The controller holds the flag
## this long (`PlayerController.inspect_left`); every view times the turns
## from when it saw the flag go on.
const INSPECT_SECONDS := 3.4
## The turns the item goes through, as [seconds in, Vector3(pitch, yaw,
## roll)] in radians, eased from one to the next: the near side, the far
## side, then tipped up to show its top, and back.
const INSPECT_TURNS := [
	[0.0, Vector3.ZERO],
	[0.55, Vector3(0.1, -0.85, -0.35)],
	[1.25, Vector3(0.15, -0.95, -0.45)],
	[1.95, Vector3(-0.05, 0.75, 0.55)],
	[2.5, Vector3(-0.1, 0.85, 0.6)],
	[3.0, Vector3(0.6, 0.1, 0.0)],
	[3.4, Vector3.ZERO],
]

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
## How far the item in hand is brought in to be looked over (0..1, eased),
## and how long this look has been going (seconds), from
## `ActorCommand.inspect`.
var inspect := 0.0
var inspect_clock := 0.0
## Set by your own controller while a toy vehicle is in your hand (only you
## see it there), so the hand turns the toy rather than the weapon.
var toy_in_hand := false
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
	elbow_raise = lerpf(elbow_raise, elbow_wanted(melee) if holding else 0.0, follow)

	var watch_wanted := actor.cmd != null and actor.cmd.watch_up and not actor.is_dead
	_watch_raise = move_toward(_watch_raise, 1.0 if watch_wanted else 0.0, delta / maxf(watch_time, 0.001))
	watch = ease(_watch_raise, -2.0)
	var phone_wanted := actor.cmd != null and actor.cmd.phone and not actor.is_dead and actor.vehicle == null
	phone = move_toward(phone, 1.0 if phone_wanted else 0.0, phone_rate * delta)

	var gun := weapon as Gun
	reload = reload_depth(gun) if gun != null and not actor.is_dead else 0.0
	var lowered := low_wanted and gun != null and not gun.is_aiming() and reload <= 0.0 \
			and inspecting() != "gun"
	low = move_toward(low, 1.0 if lowered else 0.0, delta * (lower_rate if lowered else raise_rate))
	_ads_raise = move_toward(_ads_raise, 1.0 if ads_wanted(gun) else 0.0, delta * ads_rate)
	ads = ease(_ads_raise, -2.0)


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
		if melee.style_now() == "thrust":
			# Straight out along the aim, not round the shoulder.
			return windup_reach(melee, melee.attack_dir).lerp(follow_reach(melee, melee.attack_dir), arc)
		return swing_reach(windup_reach(melee, melee.attack_dir), follow_reach(melee, melee.attack_dir), arc)
	if melee.is_winding_up():
		return windup_reach(melee, melee.attack_dir) * (1.0 + windup_coil * melee.windup_coil())
	if _follow_left > 0.0:
		return follow_reach(melee, _follow_dir)
	if melee.is_blocking():
		return arm_guard
	var charge := charge_amount(melee)
	if charge > 0.0:
		return windup_reach(melee, MeleeWeapon.swing_from(melee.stance)) * charge
	var back := recover_left(melee)
	if back > 0.0:
		return follow_reach(melee, melee.attack_dir) * back
	if inspect_for("melee") > 0.0:
		# The resting hand's offset (from `Actor.HAND_REST`, in the aim
		# frame) that puts it on the inspect point.
		var aim := actor.global_basis.orthonormalized() * Basis(Vector3.RIGHT, actor.cmd.pitch)
		var rest := actor.global_transform * Actor.HAND_REST
		return (aim.inverse() * (inspect_point() - rest)) * inspect
	return null


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
	return turn_windup[dir]


## The shoulder turn and lean at the end of a swing from `dir`.
func follow_turn(melee: MeleeWeapon, dir: int) -> Vector2:
	match melee.style_now():
		"thrust":
			return thrust_turn_follow
		"chop":
			return (turn_follow[dir] as Vector2) - Vector2(0.0, chop_lean * 1.5)
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


## What is being looked over: "gun", "melee", "hand" (a toy vehicle, or an
## empty hand as everyone else sees one), or "" when nothing is.
func inspecting() -> String:
	if inspect <= 0.0 or actor == null or actor.is_dead:
		return ""
	if toy_in_hand:
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
