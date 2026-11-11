class_name MeleeWeapon
extends Weapon
## Blade-style melee.
##
## Attacks: a three-hit light combo, a heavy lunge, and a dive slam from the air.
## Every attack has a windup you can see, which is what makes parrying possible.
## Defense: hold block to stop hits from the front at a stamina cost. Raising the
## guard just before a hit lands is a parry: no damage, the attacker is
## staggered, and your next hit is a stronger riposte.
##
## Everything is directional. The actor's command carries a stance (overhead,
## left or right). An attack takes the stance it was started in, and a guard
## takes the stance it was raised in. A guard only stops a melee hit that comes
## at the side it covers, so you read the enemy's windup and they read yours.

signal swung(kind: String)
signal blocked_hit(info: DamageInfo)
signal parried_hit(info: DamageInfo)

enum Dir { OVERHEAD, LEFT, RIGHT }

const DIR_NAMES := ["overhead", "left", "right"]
const REST_POSE := -0.45
const GUARD_POSE := 0.25
const SWING_TIME := 0.16
const WINDUP_ROLL := 1.1
## Where the blade is held, relative to the hand, for each guard.
const GUARD_OFFSET_OVERHEAD := Vector3(-0.25, 0.3, 0.0)
const GUARD_OFFSET_LEFT := Vector3(-0.5, 0.05, 0.0)
const GUARD_OFFSET_RIGHT := Vector3(0.12, 0.05, 0.0)

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
var heavy_lunge := 9.0
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

## The stance the actor is asking for right now.
var stance := Dir.OVERHEAD
## The side the current or last attack comes from, as the attacker sees it.
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


func build_visual() -> Node3D:
	var root := Node3D.new()
	root.add_child(Weapon.make_part(Vector3(0.05, 0.22, 0.05), Vector3(0, 0.0, 0), Color(0.15, 0.15, 0.15)))
	root.add_child(Weapon.make_part(Vector3(0.2, 0.04, 0.06), Vector3(0, 0.12, 0), Color(0.3, 0.3, 0.3)))
	root.add_child(Weapon.make_part(Vector3(0.06, 0.95, 0.015), Vector3(0, 0.62, 0), Color(0.45, 0.9, 1.0), true))
	root.rotation.x = REST_POSE
	return root


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
	return "Left mouse attacks from your side   Right mouse guards that side, tap just before a hit to parry   F heavy lunge, or dive slam in the air"


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
	elif _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_strike(_windup_damage, _windup_kind)
			_windup_kind = ""
	_animate(delta)


func handle_input(cmd: ActorCommand, delta: float) -> void:
	stance = clampi(cmd.stance, 0, Dir.size() - 1) as Dir
	var wants_block := cmd.secondary and not _slamming and _windup_left <= 0.0 and actor.stamina > 0.0
	if wants_block and not _blocking:
		_block_time = 0.0
		guard_dir = stance
	_blocking = wants_block
	if _blocking:
		_block_time += delta
		actor.pause_stamina_regen()
		return
	if _cooldown > 0.0 or _slamming or _windup_left > 0.0:
		return
	if cmd.primary_pressed:
		_light_attack()
	elif cmd.tertiary_pressed:
		if actor.is_on_floor():
			_heavy_attack()
		else:
			_start_slam()


func on_holster() -> void:
	_blocking = false
	_windup_left = 0.0
	_windup_kind = ""


func status_text() -> String:
	if _blocking:
		return "%s  guarding %s" % [display_name, DIR_NAMES[guard_dir]]
	if _slamming:
		return "%s  dive slam" % display_name
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
	if actor.spend_stamina(stopped * block_stamina_per_damage):
		info.amount -= stopped
		info.blocked = true
		blocked_hit.emit(info)
		Sfx.play("block", null if actor.is_player else actor.global_position)
	else:
		actor.stamina = 0.0
		_blocking = false
		actor.stagger(guard_break_stagger)
		actor.notice.emit("Guard broken")


func _light_attack() -> void:
	if not actor.spend_stamina(light_stamina):
		return
	combo_step = combo_step % 3 + 1
	_combo_timer = combo_window + light_windup
	var finisher := combo_step == 3
	_cooldown = light_windup + light_recover * (1.6 if finisher else 1.0)
	_begin_windup("light", light_damage * (combo_finisher_mult if finisher else 1.0), light_windup)


func _heavy_attack() -> void:
	if not actor.spend_stamina(heavy_stamina):
		return
	combo_step = 0
	_cooldown = heavy_windup + heavy_recover
	_begin_windup("heavy", heavy_damage, heavy_windup)
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	actor.add_impulse(forward.normalized() * heavy_lunge)


func _begin_windup(kind: String, amount: float, time: float) -> void:
	if actor.riposte_left > 0.0:
		amount *= riposte_mult
		actor.riposte_left = 0.0
	_windup_kind = kind
	_windup_damage = amount
	_windup_left = maxf(time, 0.001)
	attack_dir = stance


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
		if dist > reach or vertical > 2.5:
			continue
		if dist > 0.8 and forward.angle_to(to.normalized()) > half_arc:
			continue
		var info := DamageInfo.make(amount, actor, "melee", at)
		info.direction = attack_dir
		Combat.deal(other, info)


## Greybox poses. The blade is cocked to the attack's side for a windup, swept
## through on a strike, and held on the guarded side while blocking, so both
## fighters can read the direction.
func _animate(delta: float) -> void:
	if visual == null:
		return
	var pose := REST_POSE
	var roll := 0.0
	var offset := Vector3.ZERO
	if _slamming:
		pose = 1.3
	elif _windup_left > 0.0:
		pose = 1.0 if _windup_kind == "heavy" else 0.7
		roll = _side(attack_dir) * WINDUP_ROLL
		if attack_dir == Dir.OVERHEAD:
			pose += 0.35
			offset.y = 0.12
	elif _swing_left > 0.0:
		_swing_left -= delta
		pose = lerpf(0.6, -2.1, 1.0 - maxf(_swing_left, 0.0) / SWING_TIME)
		roll = _side(attack_dir) * WINDUP_ROLL
	elif _blocking:
		pose = GUARD_POSE
		if guard_dir == Dir.OVERHEAD:
			roll = 1.4
			offset = GUARD_OFFSET_OVERHEAD
		else:
			roll = _side(guard_dir) * 0.2
			offset = GUARD_OFFSET_LEFT if guard_dir == Dir.LEFT else GUARD_OFFSET_RIGHT
	visual.rotation.z = lerp_angle(visual.rotation.z, roll, 1.0 - exp(-24.0 * delta))
	visual.rotation.x = lerp_angle(visual.rotation.x, pose, 1.0 - exp(-40.0 * delta))
	visual.position = visual.position.lerp(offset, 1.0 - exp(-24.0 * delta))


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
