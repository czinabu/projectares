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
## Sustained fire widens the spread; it settles when you let go.
var bloom_per_shot := 0.35
var max_bloom := 2.6
var bloom_recovery := 5.0
## How far each shot kicks the shooter's view, in degrees.
var recoil_kick_deg := 0.55
var recoil_side_deg := 0.22

var _cooldown := 0.0
var _reload_left := 0.0
var _aiming := false
var _bloom := 0.0
var _rng := RandomNumberGenerator.new()


func build_visual() -> Node3D:
	var root := Node3D.new()
	root.add_child(Weapon.make_part(Vector3(0.07, 0.1, 0.62), Vector3(0, 0, -0.2), Color(0.16, 0.16, 0.18)))
	root.add_child(Weapon.make_part(Vector3(0.06, 0.16, 0.08), Vector3(0, -0.12, 0.0), Color(0.3, 0.22, 0.16)))
	root.add_child(Weapon.make_part(Vector3(0.05, 0.14, 0.1), Vector3(0, -0.1, -0.22), Color(0.1, 0.1, 0.1)))
	return root


func controls_hint() -> String:
	return "Left mouse fire   Right mouse aim   R reload"


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_bloom = maxf(0.0, _bloom - bloom_recovery * delta)
	if visual:
		# Recoil kick settles back to rest.
		visual.position.z = move_toward(visual.position.z, 0.0, delta * 0.6)
		visual.rotation.x = move_toward(visual.rotation.x, 0.0, delta * 1.5)
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


func current_spread_deg() -> float:
	return (spread_deg + _bloom) * (ads_spread_mult if _aiming else 1.0)


func status_text() -> String:
	if is_reloading():
		return "%s  reloading" % display_name
	return "%s  %d / %d" % [display_name, ammo_in_mag, reserve_ammo]


func _fire() -> void:
	ammo_in_mag -= 1
	_cooldown = fire_interval
	if visual:
		visual.position.z = 0.05
		visual.rotation.x = 0.06
	var from := actor.get_eye_position()
	var dir := actor.get_aim_dir()
	var spread := deg_to_rad(spread_deg + _bloom) * (ads_spread_mult if _aiming else 1.0)
	_bloom = minf(max_bloom, _bloom + bloom_per_shot)
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
	Sfx.play("shot", null if actor.is_player else from)
	Fx.tracer(actor.get_parent(), from + dir * 0.8 - Vector3(0, 0.15, 0), to)
