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
	advance_toy(delta)

	var gun := weapon as Gun
	reload = reload_depth(gun) if gun != null and not actor.is_dead else 0.0
	var lowered := low_wanted and gun != null and not gun.is_aiming() and reload <= 0.0
	low = move_toward(low, 1.0 if lowered else 0.0, delta * (lower_rate if lowered else raise_rate))
	_ads_raise = move_toward(_ads_raise, 1.0 if ads_wanted(gun) else 0.0, delta * ads_rate)
	ads = ease(_ads_raise, -2.0)


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


## The gun's offset from its usual hold, in the aim frame: the reload motion.
func gun_offset() -> Transform3D:
	return Transform3D(Basis.from_euler(reload_tilt * reload), reload_reach * reload)
