class_name MeleeWeapon
extends Weapon
## Blade-style melee: a three-hit light combo, a heavy lunge, and a dive slam
## when you attack from the air. Parry and block come in Phase 1.

signal swung(kind: String)

var light_damage := 28.0
var heavy_damage := 65.0
var reach := 2.8
var arc_deg := 110.0
var light_interval := 0.38
var combo_finisher_mult := 1.5
var combo_window := 0.9
var heavy_windup := 0.4
var heavy_recover := 0.5
var heavy_lunge := 9.0
var slam_damage := 55.0
var slam_radius := 4.5
var slam_fall_speed := 32.0

var combo_step := 0
var _cooldown := 0.0
var _combo_timer := 0.0
var _heavy_left := 0.0
var _slamming := false


func prefers_third_person() -> bool:
	return true


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo_step = 0
	if _heavy_left > 0.0:
		_heavy_left -= delta
		if _heavy_left <= 0.0:
			_strike(heavy_damage, "heavy")


func handle_input(cmd: ActorCommand, _delta: float) -> void:
	if _cooldown > 0.0 or _slamming:
		return
	if cmd.primary_pressed:
		_light_attack()
	elif cmd.secondary_pressed:
		if actor.is_on_floor():
			_heavy_attack()
		else:
			_start_slam()


func status_text() -> String:
	if _slamming:
		return "%s  dive slam" % display_name
	if combo_step > 0:
		return "%s  combo %d" % [display_name, combo_step]
	return display_name


func _light_attack() -> void:
	combo_step = combo_step % 3 + 1
	_combo_timer = combo_window
	var finisher := combo_step == 3
	_cooldown = light_interval * (1.6 if finisher else 1.0)
	_strike(light_damage * (combo_finisher_mult if finisher else 1.0), "light")


func _heavy_attack() -> void:
	combo_step = 0
	_heavy_left = heavy_windup
	_cooldown = heavy_windup + heavy_recover
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	actor.add_impulse(forward.normalized() * heavy_lunge)


func _start_slam() -> void:
	_slamming = true
	_cooldown = 1.0
	actor.velocity.y = -slam_fall_speed
	if not actor.landed.is_connected(_on_slam_landed):
		actor.landed.connect(_on_slam_landed, CONNECT_ONE_SHOT)


func _on_slam_landed(_impact_speed: float) -> void:
	_slamming = false
	swung.emit("slam")
	for other in _other_actors():
		if other.global_position.distance_to(actor.global_position) <= slam_radius:
			Combat.deal(other, DamageInfo.make(slam_damage, actor, "slam", other.global_position))


func _strike(amount: float, kind: String) -> void:
	swung.emit(kind)
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	forward = forward.normalized()
	var half_arc := deg_to_rad(arc_deg) * 0.5
	for other in _other_actors():
		var to := other.global_position - actor.global_position
		var vertical := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		if dist > reach or vertical > 2.5:
			continue
		if dist > 0.8 and forward.angle_to(to.normalized()) > half_arc:
			continue
		Combat.deal(other, DamageInfo.make(amount, actor, "melee", other.global_position))


func _other_actors() -> Array[Actor]:
	var out: Array[Actor] = []
	if not actor.is_inside_tree():
		return out
	for node in actor.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other and other != actor and not other.is_dead:
			out.append(other)
	return out
