class_name MeleeWeapon
extends Weapon
## Blade-style melee.
##
## Attacks: a three-hit light combo, a heavy lunge, and a dive slam from the air.
## All on one button: a tap is a light attack, and holding past `hold_time`
## charges into the heavy (or the dive slam in the air). The tap strikes on
## release; the heavy shows its full windup once the charge turns into it.
## Every attack has a windup you can see, which is what makes parrying possible.
## A press made while the blade is still busy (mid-swing or recovering) is kept
## for `press_buffer` and plays as soon as it is free, so combos chain without
## pixel-perfect timing. The time a tap was held counts toward its windup.
## A heavy lunges at the foe in front of you and stops at striking distance; in
## the air, with an airborne foe in the aim cone, it becomes the magnetic
## air-lunge instead of a dive slam.
## Defense: hold block to stop hits from the front at a stamina cost. Raising the
## guard just before a hit lands is a parry: no damage, the attacker is
## staggered, and your next hit is a stronger riposte.
##
## Everything is directional. The actor's command carries a stance (overhead,
## left or right). An attack swings toward its stance: a left swing starts on
## your right and ends on your left (Caleb's call), so it comes from the
## mirrored side (`swing_from`). A guard covers the side of its stance, and
## only stops a melee hit that arrives at that side, so you read the enemy's
## windup and they read yours. Two fighters who both pick left meet: the left
## swing arrives on the defender's left.

signal swung(kind: String)
signal blocked_hit(info: DamageInfo)
signal parried_hit(info: DamageInfo)
## A strike reached `target`: emitted on every machine the swing is simulated
## on, before the server decides the damage, so the attacker's own view can
## answer at once. `outcome` is the local guess: "hit", "block" or "parry".
signal contact(target: Actor, outcome: String, at: Vector3)

enum Dir { OVERHEAD, LEFT, RIGHT }

const DIR_NAMES := ["overhead", "left", "right"]
const REST_POSE := -0.45
const GUARD_POSE := 0.25
const SWING_TIME := 0.16
const WINDUP_ROLL := 1.1
## Where the blade ends its swing; recovery eases back from here to rest.
const FOLLOW_THROUGH := -2.1
## A strike counts this much of a body's width beyond `reach` and the arc,
## so one that visibly reaches someone's shoulder is not a miss.
const HIT_ALLOWANCE := 0.2
## How far to the side a side swing starts and ends, beside the hand.
const SIDE_REACH := 0.28
## A side swing sweeps across, more flat than a chop: its pitch at the start
## and the end.
const SIDE_SWING_FROM := 0.5
const SIDE_SWING_TO := -1.0
## How long a landed strike holds the swing still (view only).
const HITSTOP := 0.06
## Where the blade is held, relative to the hand, for each guard.
const GUARD_OFFSET_OVERHEAD := Vector3(-0.25, 0.3, 0.0)
const GUARD_OFFSET_LEFT := Vector3(-0.5, 0.05, 0.0)
const GUARD_OFFSET_RIGHT := Vector3(0.12, 0.05, 0.0)

## Hold the attack button this long and it becomes a heavy instead of a light.
var hold_time := 0.25
## A press made while the blade is busy is kept this long and plays once it is
## free. Held, it keeps charging toward a heavy meanwhile.
var press_buffer := 0.35
## The time a tap was held counts toward its light windup, down to this share
## of `light_windup`, so a tap answers quickly but still shows a windup.
var light_windup_floor := 0.5

var light_damage := 28.0
var heavy_damage := 65.0
var reach := 2.8
var arc_deg := 110.0
var light_windup := 0.1
var light_recover := 0.28
var combo_finisher_mult := 1.5
var combo_window := 0.9
var heavy_windup := 0.4
var heavy_recover := 0.5
## Speed of the heavy lunge, m/s, held through the windup. It carries you at
## most `heavy_lunge * heavy_windup` metres, and stops at striking distance
## from the foe it aims at.
var heavy_lunge := 9.0
## With nobody to lunge at, a heavy still steps this far forward.
var heavy_step := 1.0
## Lunges stop with the foe this far inside `reach`.
var lunge_stop := 0.6
## Foes within this cone of the aim are lunged at.
var lunge_cone_deg := 60.0
## A light attack steps in up to this far when the foe is just out of reach.
var light_step := 0.3
## The magnetic air-lunge: a heavy in the air at an airborne foe within this
## range and cone pulls you to them (design doc, "Melee air-lunge").
var air_lunge_range := 6.0
var air_lunge_cone_deg := 40.0
## What is left of the lunge's speed once it has carried you there.
var air_lunge_keep := 0.35
var slam_damage := 55.0
var slam_radius := 4.5
var slam_fall_speed := 32.0

var light_stamina := 10.0
var heavy_stamina := 28.0
var slam_stamina := 20.0

## Hits from within this arc in front of you can be blocked.
var block_arc_deg := 130.0
## A guard raised this recently counts as a parry.
var parry_window := 0.22
var block_stamina_per_damage := 0.6
## A blade only turns aside part of a bullet.
var bullet_block_fraction := 0.5
var parry_stagger := 1.1
var guard_break_stagger := 0.9
var riposte_window := 1.6
var riposte_mult := 1.5

## What sets one melee type apart. The defaults change nothing, so a weapon
## only gets the traits its item stats ask for.
## Hits on someone facing away, from outside their front `backstab_arc_deg`,
## are multiplied by this. A guard never covers the back anyway.
var backstab_mult := 1.0
var backstab_arc_deg := 180.0
## A guard that stops this weapon's hit pays this many times the usual stamina,
## so heavy chopping breaks guards.
var guard_crush := 1.0
## How far above or below you a swing still connects. Long reach pokes fliers.
var vertical_reach := 2.5
## Targets closer than this are inside the point and take `close_mult` damage.
var close_range := 0.0
var close_mult := 1.0
## A heavy hit that lands unblocked staggers the target for this long.
var heavy_stagger := 0.0

## The stance the actor is asking for right now.
var stance := Dir.OVERHEAD
## The side the current or last attack comes from, as the attacker sees it:
## `swing_from(stance)` when it started, so a left swing comes from the right.
var attack_dir := Dir.OVERHEAD
## The side the guard covers, as the defender sees it. Set when it is raised.
var guard_dir := Dir.OVERHEAD

var combo_step := 0
var _cooldown := 0.0
var _combo_timer := 0.0
var _windup_left := 0.0
var _windup_kind := ""
var _windup_damage := 0.0
var _slamming := false
var _blocking := false
var _block_time := 0.0
var _swing_left := 0.0
## Seconds the attack button has been held, or below zero when not charging.
var _charge := -1.0
## A press made while busy, waiting to play (`press_buffer`).
var _queued := false
var _queued_age := 0.0
## How long the queued press has been held, or below zero once let go.
var _queued_held := 0.0
## The lunge in progress: velocity held each tick for `_lunge_left` seconds.
var _lunge_vel := Vector3.ZERO
var _lunge_left := 0.0
var _air_lunge := false
## The airborne foe an air-lunge homes on.
var _lunge_foe: Actor = null
## The recovery after the last strike, for the pose (view only).
var _recover_total := 0.0
var _hitstop_left := 0.0


func build_visual() -> Node3D:
	var root := Node3D.new()
	root.add_child(Weapon.make_part(Vector3(0.05, 0.22, 0.05), Vector3(0, 0.0, 0), Color(0.15, 0.15, 0.15)))
	root.add_child(Weapon.make_part(Vector3(0.2, 0.04, 0.06), Vector3(0, 0.12, 0), Color(0.3, 0.3, 0.3)))
	root.add_child(Weapon.make_part(Vector3(0.06, 0.95, 0.015), Vector3(0, 0.62, 0), Color(0.45, 0.9, 1.0), true))
	root.rotation.x = REST_POSE
	return root


## The side a swing toward `p_stance` starts from: a swing to the left is
## cocked on the right and sweeps across to the left, and back the other way.
static func swing_from(p_stance: int) -> int:
	return mirror(p_stance)


## A swing from the attacker's left arrives on the defender's right.
static func mirror(dir: int) -> int:
	if dir == Dir.LEFT:
		return Dir.RIGHT
	if dir == Dir.RIGHT:
		return Dir.LEFT
	return dir


## True when a guard facing `p_guard_dir` covers a hit thrown from `p_attack_dir`.
## Hits with no direction (below zero) can be stopped by any guard.
static func guard_covers(p_guard_dir: int, p_attack_dir: int) -> bool:
	return p_attack_dir < 0 or p_guard_dir == mirror(p_attack_dir)


func controls_hint() -> String:
	return "Tap left mouse to swing toward your side, hold it for a heavy (a dive slam in the air)   Right mouse guards that side, tap just before a hit to parry"


func is_blocking() -> bool:
	return _blocking


func is_winding_up() -> bool:
	return _windup_left > 0.0


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo_step = 0
	if actor.stagger_left > 0.0:
		# Being staggered cancels an attack in progress and drops the guard.
		_windup_left = 0.0
		_windup_kind = ""
		_blocking = false
		_lunge_left = 0.0
		_queued = false
	elif _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_strike(_windup_damage, _windup_kind)
			_windup_kind = ""
	_carry_lunge(delta)
	_animate(delta)


func handle_input(cmd: ActorCommand, delta: float) -> void:
	stance = clampi(cmd.stance, 0, Dir.size() - 1) as Dir
	var wants_block := cmd.secondary and not _slamming and _windup_left <= 0.0 and actor.stamina > 0.0
	if wants_block and not _blocking:
		_block_time = 0.0
		guard_dir = stance
	_blocking = wants_block
	if _blocking:
		_charge = -1.0
		_queued = false
		_block_time += delta
		actor.pause_stamina_regen()
		return
	if is_busy():
		_charge = -1.0
		_queue_press(cmd, delta)
		return
	if cmd.tertiary_pressed:
		# A heavy asked for outright (bots, or a bound key).
		_charge = -1.0
		_queued = false
		_heavy_or_slam()
		return
	if _queued:
		# A press made while busy plays now: a tap that was let go is a light,
		# one still held carries on charging from where it got to.
		_queued = false
		if _queued_held < 0.0:
			_light_attack(0.0)
			return
		_charge = _queued_held
	elif cmd.primary_pressed:
		_charge = 0.0
	if _charge < 0.0:
		return
	if not cmd.primary:
		# Let go before the charge turned: a tap, so a light attack.
		var held := _charge
		_charge = -1.0
		_light_attack(held)
		return
	_charge += delta
	if _charge >= hold_time:
		_charge = -1.0
		_heavy_or_slam()


## True while a swing, its recovery or a slam keeps the blade from attacking.
func is_busy() -> bool:
	return _cooldown > 0.0 or _slamming or _windup_left > 0.0


## Remembers a press made while busy, and how long it is held.
func _queue_press(cmd: ActorCommand, delta: float) -> void:
	if cmd.primary_pressed:
		_queued = true
		_queued_age = 0.0
		_queued_held = 0.0 if cmd.primary else -1.0
		return
	if not _queued:
		return
	_queued_age += delta
	if _queued_held >= 0.0:
		_queued_held = _queued_held + delta if cmd.primary else -1.0
	# A tap is forgotten once it is old; a press still held is a charge.
	if _queued_held < 0.0 and _queued_age > press_buffer:
		_queued = false


## True while the attack button is held but has not yet become a heavy.
func is_charging() -> bool:
	return _charge >= 0.0


func _heavy_or_slam() -> void:
	if actor.is_on_floor():
		_heavy_attack()
		return
	var foe := _air_lunge_target()
	if foe:
		_air_lunge_at(foe)
	else:
		_start_slam()


func on_holster() -> void:
	_charge = -1.0
	_queued = false
	_blocking = false
	_windup_left = 0.0
	_windup_kind = ""
	_lunge_left = 0.0
	_air_lunge = false
	_lunge_foe = null
	combo_step = 0
	# A slam put away mid-fall does not land.
	if _slamming:
		_slamming = false
		if actor.landed.is_connected(_on_slam_landed):
			actor.landed.disconnect(_on_slam_landed)


## The side an attack is coming from right now, as the attacker sees it: the
## windup's side, or the stance while the button is held for a heavy. -1 when
## nothing is coming. What a defender (or the HUD) can read off the blade.
func threat_dir() -> int:
	if _windup_left > 0.0:
		return attack_dir
	if _charge >= 0.0:
		return swing_from(stance)
	return -1


## 0 at the start of the recovery after a strike, 1 once ready again, or -1
## when not recovering. For poses.
func recover_progress() -> float:
	if _recover_total <= 0.0 or _cooldown <= 0.0 or _windup_left > 0.0:
		return -1.0
	return clampf(1.0 - _cooldown / _recover_total, 0.0, 1.0)


func is_lunging() -> bool:
	return _lunge_left > 0.0


func status_text() -> String:
	if _blocking:
		return "%s  guarding %s" % [display_name, DIR_NAMES[guard_dir]]
	if _slamming:
		return "%s  dive slam" % display_name
	if _air_lunge and _windup_left > 0.0:
		return "%s  air lunge" % display_name
	if actor.riposte_left > 0.0:
		return "%s  riposte ready" % display_name
	if combo_step > 0:
		return "%s  %s  combo %d" % [display_name, DIR_NAMES[stance], combo_step]
	return "%s  %s" % [display_name, DIR_NAMES[stance]]


func modify_incoming(info: DamageInfo) -> void:
	if not _blocking or info.kind not in ["bullet", "melee"]:
		return
	var source := info.source as Node3D
	if source == null:
		return
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	var to := source.global_position - actor.global_position
	to.y = 0.0
	if to.length() > 0.01 and forward.normalized().angle_to(to.normalized()) > deg_to_rad(block_arc_deg) * 0.5:
		return
	if info.kind == "melee" and not guard_covers(guard_dir, info.direction):
		actor.notice.emit("Wrong side")
		return

	if _block_time <= parry_window:
		info.amount = 0.0
		info.parried = true
		actor.riposte_left = riposte_window
		actor.notice.emit("Parry!")
		var attacker := source as Actor
		if info.kind == "melee" and attacker:
			attacker.stagger(parry_stagger)
		parried_hit.emit(info)
		Sfx.play("parry", null if actor.is_player else actor.global_position)
		return

	var stopped := info.amount if info.kind == "melee" else info.amount * bullet_block_fraction
	if actor.spend_stamina(stopped * block_stamina_per_damage * info.guard_mult):
		info.amount -= stopped
		info.blocked = true
		blocked_hit.emit(info)
		Sfx.play("block", null if actor.is_player else actor.global_position)
	else:
		actor.stamina = 0.0
		_blocking = false
		actor.stagger(guard_break_stagger)
		actor.notice.emit("Guard broken")


func _light_attack(held: float) -> void:
	if not actor.spend_stamina(light_stamina):
		return
	combo_step = combo_step % 3 + 1
	var finisher := combo_step == 3
	# The hold before the release was already part of the windup.
	var windup := maxf(light_windup - held, light_windup * light_windup_floor)
	_combo_timer = combo_window + windup
	_cooldown = windup + light_recover * (1.6 if finisher else 1.0)
	_begin_windup("light", light_damage * (combo_finisher_mult if finisher else 1.0), windup)
	# Just out of reach: step in so the cut lands.
	var foe := _lunge_target(reach + light_step)
	if foe.size() > 0:
		var gap: float = foe[1] - reach * 0.85
		if gap > 0.0:
			_start_lunge(foe[2] * (gap / maxf(windup, 0.12)), maxf(windup, 0.12))


func _heavy_attack() -> void:
	if not actor.spend_stamina(heavy_stamina):
		return
	combo_step = 0
	_cooldown = heavy_windup + heavy_recover
	_begin_windup("heavy", heavy_damage, heavy_windup)
	var time := maxf(heavy_windup, 0.05)
	var most := heavy_lunge * time
	var foe := _lunge_target(reach + most)
	if foe.size() > 0:
		# Close to striking distance, never past the foe.
		var travel := clampf(foe[1] - reach * lunge_stop, 0.0, most)
		_start_lunge(foe[2] * (travel / time), time)
	else:
		var forward := actor.get_aim_dir()
		forward.y = 0.0
		_start_lunge(forward.normalized() * (minf(heavy_step, most) / time), time)


## The nearest foe on the ground within `range_m` and the lunge cone, as
## [actor, flat distance, flat direction], or [] for none. Foes are where this
## attacker sees them, so a lunge online goes where it looked like it would.
func _lunge_target(range_m: float) -> Array:
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	if forward.length() < 0.01:
		return []
	forward = forward.normalized()
	var half := deg_to_rad(lunge_cone_deg) * 0.5
	var seen := Combat.positions_seen_by(actor)
	var best: Array = []
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		if absf(to.y) > vertical_reach:
			continue
		to.y = 0.0
		var dist := to.length()
		if dist < 0.01 or dist > range_m or forward.angle_to(to / dist) > half:
			continue
		if best.is_empty() or dist < best[1]:
			best = [other, dist, to / dist]
	return best


## An airborne foe the magnetic air-lunge can reach, or null.
func _air_lunge_target() -> Actor:
	if air_lunge_range <= 0.0:
		return null
	var aim := actor.get_aim_dir().normalized()
	var half := deg_to_rad(air_lunge_cone_deg) * 0.5
	var seen := Combat.positions_seen_by(actor)
	var best: Actor = null
	var best_dist := INF
	for other in _other_actors():
		if other.is_on_floor():
			continue
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		var dist := to.length()
		if dist < 0.01 or dist > air_lunge_range or dist >= best_dist or aim.angle_to(to / dist) > half:
			continue
		best = other
		best_dist = dist
	return best


## A heavy in the air at an airborne foe: the full heavy windup, spent flying
## to them, and the strike lands as you arrive. A whiff leaves you drifting.
func _air_lunge_at(foe: Actor) -> void:
	if not actor.spend_stamina(heavy_stamina):
		return
	combo_step = 0
	_cooldown = heavy_windup + heavy_recover
	_begin_windup("heavy", heavy_damage, heavy_windup)
	_air_lunge = true
	_lunge_foe = foe
	_lunge_left = maxf(heavy_windup, 0.05)
	_lunge_vel = _air_lunge_velocity(_lunge_left)


## Toward the air-lunge's foe, fast enough to arrive at striking distance as
## `time_left` runs out. It follows them as they fly: that is the magnet.
func _air_lunge_velocity(time_left: float) -> Vector3:
	if _lunge_foe == null or not is_instance_valid(_lunge_foe) or _lunge_foe.is_dead:
		return _lunge_vel
	var seen := Combat.positions_seen_by(actor)
	var to: Vector3 = seen.get(_lunge_foe, _lunge_foe.global_position) - actor.global_position
	var travel := maxf(to.length() - reach * lunge_stop, 0.0)
	if to.length() < 0.01:
		return Vector3.ZERO
	return to.normalized() * (travel / maxf(time_left, 1.0 / 60.0))


func _start_lunge(vel: Vector3, time: float) -> void:
	_lunge_vel = vel
	_lunge_left = time if vel.length() > 0.01 else 0.0


## Holds the lunge's velocity. Runs after the actor has moved this tick, so
## the next move carries it; movement only eases it a little in between.
func _carry_lunge(delta: float) -> void:
	if _lunge_left <= 0.0:
		return
	if actor.get_active_weapon() != self:
		_lunge_left = 0.0
		return
	_lunge_left -= delta
	if _air_lunge:
		if _lunge_left > 0.0:
			_lunge_vel = _air_lunge_velocity(_lunge_left)
		actor.velocity = _lunge_vel if _lunge_left > 0.0 else _lunge_vel * air_lunge_keep
	elif _lunge_left > 0.0:
		actor.velocity.x = _lunge_vel.x
		actor.velocity.z = _lunge_vel.z
	if _lunge_left <= 0.0:
		_air_lunge = false
		_lunge_foe = null


func _begin_windup(kind: String, amount: float, time: float) -> void:
	if actor.riposte_left > 0.0:
		amount *= riposte_mult
		actor.riposte_left = 0.0
	_windup_kind = kind
	_windup_damage = amount
	_windup_left = maxf(time, 0.001)
	attack_dir = swing_from(stance) as Dir


func _start_slam() -> void:
	if not actor.spend_stamina(slam_stamina):
		return
	_slamming = true
	_cooldown = 1.0
	actor.velocity.y = -slam_fall_speed
	if not actor.landed.is_connected(_on_slam_landed):
		actor.landed.connect(_on_slam_landed, CONNECT_ONE_SHOT)


func _on_slam_landed(_impact_speed: float) -> void:
	_slamming = false
	swung.emit("slam")
	Sfx.play("slam", null if actor.is_player else actor.global_position)
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		if at.distance_to(actor.global_position) <= slam_radius:
			Combat.deal(other, DamageInfo.make(slam_damage, actor, "slam", at))


func _strike(amount: float, kind: String) -> void:
	swung.emit(kind)
	_swing_left = SWING_TIME
	_recover_total = _cooldown
	Sfx.play("swing", null if actor.is_player else actor.global_position)
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	forward = forward.normalized()
	var half_arc := deg_to_rad(arc_deg) * 0.5
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		var vertical := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		# A blade reaches a body, not the middle of it: count its width.
		if dist - HIT_ALLOWANCE > reach or vertical > vertical_reach:
			continue
		if dist > 0.8 and forward.angle_to(to.normalized()) > half_arc + atan(HIT_ALLOWANCE / dist):
			continue
		var hit := amount
		if dist < close_range:
			hit *= close_mult
		if backstab_mult != 1.0 and is_behind(other, actor.global_position, backstab_arc_deg):
			hit *= backstab_mult
		_contact(other, at)
		var info := DamageInfo.make(hit, actor, "melee", at)
		info.direction = attack_dir
		info.guard_mult = guard_crush
		if Combat.deal(other, info) and kind == "heavy" and heavy_stagger > 0.0 \
				and not info.blocked and not info.parried and not other.is_dead:
			other.stagger(heavy_stagger)


## The strike reached `other`: guess what their guard does with it, and let
## the views answer now rather than after the server's word.
func _contact(other: Actor, at: Vector3) -> void:
	var outcome := guess_outcome(other)
	_hitstop_left = HITSTOP
	if _air_lunge and _lunge_left > 0.0:
		# Arrived: the lunge has done its job.
		_lunge_left = minf(_lunge_left, 0.0001)
	var chest := at + Vector3(0.0, Actor.BODY_HEIGHT * 0.6, 0.0)
	contact.emit(other, outcome, chest)
	if actor.is_inside_tree():
		var color := Color(1.0, 0.85, 0.4) if outcome == "parry" \
				else (Color(0.55, 0.75, 1.0) if outcome == "block" else Color(1.0, 0.45, 0.35))
		Fx.burst(actor.get_parent(), chest, 0.35, color)


## What `other`'s guard would do with a strike from this blade right now:
## "parry", "block" or "hit". The server's `modify_incoming` decides for real;
## this only lets the attacker's view answer straight away.
func guess_outcome(other: Actor) -> String:
	var blade := other.get_active_weapon() as MeleeWeapon
	if blade == null or not blade.is_blocking() or other.stagger_left > 0.0:
		return "hit"
	var facing := other.get_aim_dir()
	facing.y = 0.0
	var to := actor.global_position - other.global_position
	to.y = 0.0
	if facing.length() > 0.01 and to.length() > 0.01 \
			and facing.normalized().angle_to(to.normalized()) > deg_to_rad(blade.block_arc_deg) * 0.5:
		return "hit"
	if not guard_covers(blade.guard_dir, attack_dir):
		return "hit"
	return "parry" if blade._block_time <= blade.parry_window else "block"


## True when `from` is outside the front `front_arc_deg` of `target`, the way
## it faces.
static func is_behind(target: Actor, from: Vector3, front_arc_deg: float) -> bool:
	var facing := target.get_aim_dir()
	facing.y = 0.0
	var to := from - target.global_position
	to.y = 0.0
	if facing.length() < 0.01 or to.length() < 0.01:
		return false
	return facing.normalized().angle_to(to.normalized()) > deg_to_rad(front_arc_deg) * 0.5


## Greybox poses. The blade is cocked to the attack's side for a windup, swept
## through on a strike, and held on the guarded side while blocking, so both
## fighters can read the direction.
func _animate(delta: float) -> void:
	if visual == null:
		return
	var pose := REST_POSE
	var roll := 0.0
	var offset := Vector3.ZERO
	var follow := 24.0
	if _hitstop_left > 0.0:
		# A landed strike holds the swing still for a moment.
		_hitstop_left -= delta
		return
	if _slamming:
		pose = 1.3
	elif _windup_left > 0.0:
		# Cocked on the side the swing comes from.
		pose = 1.0 if _windup_kind == "heavy" else 0.7
		roll = _side(attack_dir) * WINDUP_ROLL
		offset.x = -_side(attack_dir) * SIDE_REACH
		if attack_dir == Dir.OVERHEAD:
			pose += 0.35
			offset.y = 0.12
	elif _swing_left > 0.0:
		# Swept across to the other side (a side swing), or chopped down.
		_swing_left -= delta
		var u := 1.0 - maxf(_swing_left, 0.0) / SWING_TIME
		follow = 60.0
		if attack_dir == Dir.OVERHEAD:
			pose = lerpf(0.6, FOLLOW_THROUGH, u)
		else:
			var side := _side(attack_dir)
			pose = lerpf(SIDE_SWING_FROM, SIDE_SWING_TO, u)
			roll = lerpf(side, -side, u) * WINDUP_ROLL
			offset.x = lerpf(-side, side, u) * SIDE_REACH
	elif _blocking:
		pose = GUARD_POSE
		if guard_dir == Dir.OVERHEAD:
			roll = 1.4
			offset = GUARD_OFFSET_OVERHEAD
		else:
			roll = _side(guard_dir) * 0.2
			offset = GUARD_OFFSET_LEFT if guard_dir == Dir.LEFT else GUARD_OFFSET_RIGHT
	elif _charge >= 0.0 or (_queued and _queued_held >= 0.0):
		# Drawing back while the button is held, toward the heavy's windup.
		var held := _charge if _charge >= 0.0 else _queued_held
		var t := clampf(held / maxf(hold_time, 0.01), 0.0, 1.0)
		pose = lerpf(REST_POSE, 0.6, t)
		roll = _side(swing_from(stance)) * WINDUP_ROLL * t
	elif recover_progress() >= 0.0:
		# Recovering: ease back from where the swing ended, so the wait
		# before the next attack can be seen.
		var t := smoothstep(0.0, 1.0, recover_progress())
		if attack_dir == Dir.OVERHEAD:
			pose = lerpf(FOLLOW_THROUGH * 0.75, REST_POSE, t)
		else:
			var side := _side(attack_dir)
			pose = lerpf(SIDE_SWING_TO, REST_POSE, t)
			roll = -side * WINDUP_ROLL * (1.0 - t)
			offset.x = side * SIDE_REACH * (1.0 - t)
	visual.rotation.z = lerp_angle(visual.rotation.z, roll, 1.0 - exp(-follow * delta))
	visual.rotation.x = lerp_angle(visual.rotation.x, pose, 1.0 - exp(-maxf(follow, 40.0) * delta))
	visual.position = visual.position.lerp(offset, 1.0 - exp(-follow * delta))


## +1 for the actor's left, -1 for the right, 0 for overhead.
static func _side(dir: int) -> float:
	if dir == Dir.LEFT:
		return 1.0
	if dir == Dir.RIGHT:
		return -1.0
	return 0.0


func _other_actors() -> Array[Actor]:
	var out: Array[Actor] = []
	if not actor.is_inside_tree():
		return out
	for node in actor.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other and other != actor and not other.is_dead and Raid.together(actor, other):
			out.append(other)
	return out
