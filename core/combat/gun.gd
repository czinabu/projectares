class_name Gun
extends Weapon
## Firearm. The shot always starts at the actor's eyes, never at the camera,
## so a third-person camera cannot shoot around corners.
##
## One class covers every gun; item stats pick the behavior. Most guns are
## hitscan. Power weapons (items tagged "power") turn on the rest:
## `charge_time` (hold to charge, fires when full), `pierce` and `wall_pierce`
## (a shot that keeps going), `projectile` ("rocket" or "grenade": a moving
## round that bursts with `splash_radius`), `heat_seek` (rockets lock onto a
## thrusting jetpack) and `spin_up` (barrels spin before firing and slow you).

signal fired(from: Vector3, to: Vector3)

var damage := 20.0
## Fires once per trigger pull instead of while the trigger is held.
var semi_auto := false
## Damage multiplier for a shot that lands on an actor's head.
var headshot_mult := 1.0
## Projectiles per shot. Each one deals `damage` and gets its own spread.
var pellets := 1
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
## Effects. Power weapons use these to look and sound like what they are.
var tracer_color := Color(1.0, 0.85, 0.4)
var shot_sound := "shot"
## "bullet" for ordinary rounds. Power weapons name their own ("rail",
## "plasma", "arc") so feeds and guards can tell them apart.
var damage_kind := "bullet"
## Seconds the trigger must be held before the shot goes. 0 fires at once.
var charge_time := 0.0
## How many bodies one shot passes through, and how many walls.
var pierce := 0
var wall_pierce := 0
## A charged shot leaves a beam that hangs in the air this long, so everyone
## can see where it came from.
var beam_time := 0.0
## "" for hitscan, or "rocket" / "grenade" for a round that flies.
var projectile := ""
var projectile_speed := 40.0
## 0 flies straight, 1 drops like a thrown stone.
var projectile_gravity := 0.0
## Grenades: how many times a round bounces, and seconds before it bursts.
var bounces := 0
var fuse_time := 4.0
## Burst on impact: full `splash_damage` at the centre, falling to a third
## at the edge. Walls shelter whoever is behind them.
var splash_radius := 0.0
var splash_damage := 0.0
## Rockets steer onto a hostile actor whose flight rig is thrusting or hot,
## within this cone (degrees) of the aim when fired. 0 never locks.
var heat_seek_cone := 0.0
var heat_seek_range := 140.0
var heat_seek_turn := 2.2
## Barrels take this long to spin up. Holding aim keeps them spinning.
var spin_up := 0.0
## Walk speed multiplier with the barrels fully spun.
var spin_move_mult := 1.0

var _cooldown := 0.0
var _reload_left := 0.0
var _aiming := false
var _bloom := 0.0
var _rng := RandomNumberGenerator.new()
var _charge := 0.0
var _spin := 0.0


func build_visual() -> Node3D:
	var root := Node3D.new()
	if is_sidearm:
		root.add_child(Weapon.make_part(Vector3(0.05, 0.08, 0.24), Vector3(0, 0, -0.06), Color(0.16, 0.16, 0.18)))
		root.add_child(Weapon.make_part(Vector3(0.045, 0.13, 0.06), Vector3(0, -0.09, 0.03), Color(0.1, 0.1, 0.1)))
		return root
	root.add_child(Weapon.make_part(Vector3(0.07, 0.1, 0.62), Vector3(0, 0, -0.2), Color(0.16, 0.16, 0.18)))
	root.add_child(Weapon.make_part(Vector3(0.06, 0.16, 0.08), Vector3(0, -0.12, 0.0), Color(0.3, 0.22, 0.16)))
	root.add_child(Weapon.make_part(Vector3(0.05, 0.14, 0.1), Vector3(0, -0.1, -0.22), Color(0.1, 0.1, 0.1)))
	return root


func controls_hint() -> String:
	if charge_time > 0.0:
		return "Hold left mouse to charge, it fires when full"
	if spin_up > 0.0:
		return "Hold left mouse to spin up and fire   Right mouse keeps it spinning"
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


func handle_input(cmd: ActorCommand, delta: float) -> void:
	_aiming = cmd.secondary and _reload_left <= 0.0 and spin_up <= 0.0
	if cmd.reload_pressed:
		start_reload()
	if spin_up > 0.0:
		var spinning := (cmd.primary or cmd.secondary) and _reload_left <= 0.0
		_spin = clampf(_spin + (delta if spinning else -delta * 1.5) / spin_up, 0.0, 1.0)
		if _spin < 1.0:
			return
	if charge_time > 0.0:
		if not cmd.primary or _cooldown > 0.0 or _reload_left > 0.0 or ammo_in_mag <= 0:
			_charge = 0.0
			if cmd.primary and ammo_in_mag <= 0 and _cooldown <= 0.0:
				start_reload()
			return
		_charge += delta
		if _charge < charge_time:
			return
		_charge = 0.0
	var trigger := cmd.primary_pressed if semi_auto else cmd.primary
	if trigger and _cooldown <= 0.0 and _reload_left <= 0.0:
		if ammo_in_mag > 0:
			_fire()
		else:
			start_reload()


func on_holster() -> void:
	_aiming = false
	_charge = 0.0
	_spin = 0.0


## How far a charge has built, 0 to 1.
func charge_fraction() -> float:
	return clampf(_charge / charge_time, 0.0, 1.0) if charge_time > 0.0 else 0.0


## How far the barrels have spun up, 0 to 1.
func spin_fraction() -> float:
	return _spin


func move_speed_mult() -> float:
	return lerpf(1.0, spin_move_mult, _spin) if spin_up > 0.0 else 1.0


## True for a raid-only power weapon (see `PowerArmory`).
func is_power() -> bool:
	return item_id != "" and ItemDB.has_tag(item_id, "power")


## True when a power weapon has nothing left to fire. It is never reloaded.
func is_spent() -> bool:
	return ammo_in_mag <= 0 and reserve_ammo <= 0 and _reload_left <= 0.0


func is_aiming() -> bool:
	return _aiming


func is_empty() -> bool:
	return ammo_in_mag <= 0 and _reload_left <= 0.0


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
	if is_power():
		if is_spent():
			return "%s  spent, swap it at a rack" % display_name
		var shots := "%s  %d shots" % [display_name, ammo_in_mag + reserve_ammo]
		if _charge > 0.0:
			shots += "  charging %d%%" % roundi(charge_fraction() * 100.0)
		elif _spin > 0.0 and _spin < 1.0:
			shots += "  spinning up"
		return shots
	return "%s  %d / %d" % [display_name, ammo_in_mag, reserve_ammo]


func _fire() -> void:
	ammo_in_mag -= 1
	_cooldown = fire_interval
	if visual:
		visual.position.z = 0.05
		visual.rotation.x = 0.06
	var from := actor.get_eye_position()
	var aim := actor.get_aim_dir()
	var spread := deg_to_rad(spread_deg + _bloom) * (ads_spread_mult if _aiming else 1.0)
	_bloom = minf(max_bloom, _bloom + bloom_per_shot)
	var to := from + aim * max_range
	for i in pellets:
		var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		var dir := (aim + jitter * tan(spread)).normalized()
		var muzzle := from + dir * 0.8 - Vector3(0, 0.15, 0)
		if projectile != "":
			_launch(muzzle, dir)
			continue
		to = _trace_shot(from, dir)
		if beam_time > 0.0:
			Fx.beam(actor.get_parent(), muzzle, to, tracer_color, beam_time)
		else:
			Fx.tracer(actor.get_parent(), muzzle, to, tracer_color)
	fired.emit(from, to)
	Sfx.play(shot_sound, null if actor.is_player else from)


## One hitscan round along `dir`. Deals its damage and returns where it
## stopped. With `pierce` or `wall_pierce` it keeps going through bodies and
## walls, losing a quarter of its damage at each.
func _trace_shot(from: Vector3, dir: Vector3) -> Vector3:
	var start := from
	var end := from + dir * max_range
	var amount := damage
	var bodies_left := pierce
	var walls_left := wall_pierce
	var struck: Array[Actor] = []
	for step in 1 + pierce + wall_pierce:
		var hit := Combat.trace(actor, start, end)
		if hit.is_empty():
			return end
		var at: Vector3 = hit.position
		var body := hit.collider as Actor
		if body != null:
			if not body in struck:
				struck.append(body)
				var info := DamageInfo.make(amount, actor, damage_kind, at)
				if Combat.is_headshot(hit):
					info.headshot = true
					info.amount *= headshot_mult
				Combat.deal(body, info)
			if bodies_left <= 0:
				return at
			bodies_left -= 1
			# Step past the body's far side before tracing again.
			start = at + dir * (Actor.BODY_RADIUS * 2.0 + 0.05)
		else:
			if walls_left <= 0:
				return at
			walls_left -= 1
			start = at + dir * 0.6
		amount *= 0.75
	return end


func _launch(at: Vector3, dir: Vector3) -> void:
	var shot := Round.new()
	shot.gun_shooter = actor
	shot.kind = projectile
	shot.damage_kind = damage_kind
	shot.velocity = dir * projectile_speed
	shot.gravity = projectile_gravity * 20.0
	shot.bounces_left = bounces
	shot.fuse = fuse_time
	shot.direct_damage = damage
	shot.splash_radius = splash_radius
	shot.splash_damage = splash_damage
	shot.color = tracer_color
	shot.turn_rate = heat_seek_turn
	if heat_seek_cone > 0.0:
		shot.target = heat_target(actor, dir, heat_seek_cone, heat_seek_range)
	actor.get_parent().add_child(shot)
	shot.global_position = at


## The hostile actor in front of `shooter` that a heat-seeker would lock
## onto: one whose flight rig is thrusting or still hot, inside `cone_deg` of
## `dir` and in sight. The nearest to the aim line wins. Null for none.
static func heat_target(shooter: Actor, dir: Vector3, cone_deg: float, reach: float) -> Actor:
	var world := Worlds.of(shooter)
	var eye := shooter.get_eye_position()
	var best: Actor = null
	var best_angle := deg_to_rad(cone_deg)
	for node in shooter.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == shooter or other.is_dead or not Raid.together(shooter, other):
			continue
		if not (other.flight.is_thrusting or other.flight.heat >= other.flight.max_heat * 0.3):
			continue
		if world and not world.can_damage(shooter, other, DamageInfo.make(0.0, shooter, "plasma")):
			continue
		var chest := other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.6, 0.0)
		var to := chest - eye
		if to.length() > reach:
			continue
		var angle := dir.angle_to(to)
		if angle > best_angle:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, chest, Actor.LAYER_WORLD)
		if not shooter.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = other
		best_angle = angle
	return best


## Bursts at `at`: damage to every actor in `radius`, full at the centre and
## a third at the edge, for anyone not sheltered by a wall. Goes through
## `Combat.deal` like every hit, so world rules and guards still apply.
static func splash(source: Actor, at: Vector3, radius: float, amount: float, kind: String,
		space_owner: Node3D) -> int:
	var hurt := 0
	if radius <= 0.0 or amount <= 0.0 or space_owner == null or not space_owner.is_inside_tree():
		return 0
	var space := space_owner.get_world_3d().direct_space_state
	for node in space_owner.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other.is_dead:
			continue
		if source != null and is_instance_valid(source) and not Raid.together(source, other):
			continue
		var chest := other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
		var dist := at.distance_to(chest)
		if dist > radius:
			continue
		var query := PhysicsRayQueryParameters3D.create(at, chest, Actor.LAYER_WORLD)
		if not space.intersect_ray(query).is_empty():
			continue
		var share := lerpf(1.0, 1.0 / 3.0, dist / radius)
		var info := DamageInfo.make(amount * share, source if is_instance_valid(source) else null, kind, chest)
		if Combat.deal(other, info):
			hurt += 1
			# The blast throws people about a little.
			var push := (chest - at).normalized() if dist > 0.01 else Vector3.UP
			other.add_impulse((push + Vector3.UP * 0.6) * 6.0 * share)
	return hurt


## A round in flight: a plasma rocket or a bouncing arc grenade. Moves itself
## each physics tick, so it runs the same on a headless server. On a client
## it flies for show: `Combat.deal` refuses there, the server decides.
class Round extends Node3D:
	var gun_shooter: Actor
	var kind := "rocket"
	var damage_kind := "plasma"
	var velocity := Vector3.ZERO
	var gravity := 0.0
	var bounces_left := 0
	var fuse := 4.0
	var direct_damage := 0.0
	var splash_radius := 0.0
	var splash_damage := 0.0
	var color := Color.WHITE
	var target: Actor
	var turn_rate := 2.0
	var _age := 0.0
	var _done := false

	func _ready() -> void:
		var mesh := SphereMesh.new()
		mesh.radius = 0.14 if kind == "grenade" else 0.18
		mesh.height = mesh.radius * 2.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mesh.material = mat
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(body)

	func _physics_process(delta: float) -> void:
		if _done:
			return
		_age += delta
		if target != null and is_instance_valid(target) and not target.is_dead:
			var chest := target.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.6, 0.0)
			var want := (chest - global_position).normalized() * velocity.length()
			velocity = velocity.slerp(want, clampf(turn_rate * delta, 0.0, 1.0)) if velocity.length() > 0.01 else want
		velocity.y -= gravity * delta
		var from := global_position
		var to := from + velocity * delta
		var mask := Actor.LAYER_WORLD | Actor.LAYER_ACTORS
		var query := PhysicsRayQueryParameters3D.create(from, to, mask)
		# A round never hits its own shooter on the way out of the barrel.
		if gun_shooter != null and is_instance_valid(gun_shooter):
			query.exclude = [gun_shooter.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var body := hit.collider as Actor
			if body != null:
				_burst(hit.position, body)
				return
			if kind == "grenade" and bounces_left > 0:
				bounces_left -= 1
				velocity = velocity.bounce(hit.normal) * 0.55
				global_position = hit.position + hit.normal * 0.05
				return
			_burst(hit.position, null)
			return
		global_position = to
		Fx.trail(get_parent(), from, to, color)
		if _age >= fuse:
			_burst(global_position, null)

	func _burst(at: Vector3, struck: Actor) -> void:
		_done = true
		var source := gun_shooter if is_instance_valid(gun_shooter) else null
		if struck != null and direct_damage > 0.0:
			Combat.deal(struck, DamageInfo.make(direct_damage, source, damage_kind, at))
		Gun.splash(source, at, splash_radius, splash_damage, damage_kind, self)
		Fx.burst(get_parent(), at, splash_radius, color)
		Sfx.play("plasma_burst", at)
		queue_free()
