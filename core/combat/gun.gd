class_name Gun
extends Weapon
## Hitscan firearm. The shot always starts at the actor's eyes, never at the
## camera, so a third-person camera cannot shoot around corners.

signal fired(from: Vector3, to: Vector3)

var damage := 20.0
var fire_interval := 0.11
var mag_size := 30
var ammo_in_mag := 30
var reserve_ammo := 120
var reload_time := 1.7
var max_range := 150.0
var spread_deg := 1.2
var ads_spread_mult := 0.3

var _cooldown := 0.0
var _reload_left := 0.0
var _aiming := false
var _rng := RandomNumberGenerator.new()


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			var need := mini(mag_size - ammo_in_mag, reserve_ammo)
			ammo_in_mag += need
			reserve_ammo -= need


func handle_input(cmd: ActorCommand, _delta: float) -> void:
	_aiming = cmd.secondary and _reload_left <= 0.0
	if cmd.reload_pressed:
		start_reload()
	if cmd.primary and _cooldown <= 0.0 and _reload_left <= 0.0:
		if ammo_in_mag > 0:
			_fire()
		else:
			start_reload()


func on_holster() -> void:
	_aiming = false


func is_aiming() -> bool:
	return _aiming


func is_reloading() -> bool:
	return _reload_left > 0.0


func start_reload() -> void:
	if _reload_left <= 0.0 and ammo_in_mag < mag_size and reserve_ammo > 0:
		_reload_left = reload_time


func status_text() -> String:
	if is_reloading():
		return "%s  reloading" % display_name
	return "%s  %d / %d" % [display_name, ammo_in_mag, reserve_ammo]


func _fire() -> void:
	ammo_in_mag -= 1
	_cooldown = fire_interval
	var from := actor.get_eye_position()
	var dir := actor.get_aim_dir()
	var spread := deg_to_rad(spread_deg) * (ads_spread_mult if _aiming else 1.0)
	var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	dir = (dir + jitter * tan(spread)).normalized()
	var to := from + dir * max_range

	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = hit.position
		Combat.deal(hit.collider, DamageInfo.make(damage, actor, "bullet", to))
	fired.emit(from, to)
	Fx.tracer(actor.get_parent(), from + dir * 0.8 - Vector3(0, 0.15, 0), to)
