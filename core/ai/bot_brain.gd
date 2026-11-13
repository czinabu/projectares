class_name BotBrain
extends Node3D
## Drives a bot Actor by writing its ActorCommand, exactly like a player does.
## Patrols, chases what it sees or what shot it, and fights with its weapon.

enum State { PATROL, CHASE, ATTACK }

var seed_value := 0
var sight_range := 38.0
var close_sense_range := 9.0
var fov_deg := 140.0
var attack_range := 28.0
var preferred_range := 14.0
var reaction_time := 0.7
## Melee only: how far off the chest a swing is aimed, per metre.
var aim_error := 0.05
var burst_time := 0.6
var burst_pause := 0.7
var patrol_radius := 22.0
var give_up_time := 7.0
## Further than this beyond its patrol, a bot runs back to its post.
var march_distance := 12.0
## How far the place a bot is heading for must move before it plans a new path.
var repath_distance := 1.5
## Chance that a melee bot reads the side of an incoming swing in time.
var guard_skill := 0.4
var guard_reaction := 0.22

## Gun aim. Bots aim like people, not like an aimbot: they turn onto a target
## at a limited speed, trail it while it moves, and their aim wanders by an
## angle that starts wide on first sight and settles while they hold it in
## view. Moving, airborne and distant targets are harder to hit.
## 0 is a rookie, 1 a veteran. Below 0, each bot rolls its own from its seed.
var skill := -1.0
## Turn speed onto the target, degrees a second (at skill 0.5).
var turn_speed_deg := 200.0
## Seconds the aim trails a moving target (at skill 0.5).
var track_lag := 0.22
## Settled aim wander, degrees (at skill 0.5).
var aim_error_deg := 2.2
## The wander on first sight is this many times the settled one...
var settle_mult := 3.0
## ...and settles over this long in view.
var settle_time := 2.5
## Extra wander when the target is in the air, and per metre past
## `preferred_range`, degrees.
var air_error_deg := 3.0
var far_error_deg := 0.08
## Extra wander while the bot itself is moving, degrees.
var self_move_error_deg := 1.0
## Fires only when its aim is within this of where it means to aim, degrees.
var fire_cone_deg := 6.0

var state := State.PATROL
var actor: Actor
var target: Actor

var _nav: NavigationAgent3D
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
var _dest := Vector3.ZERO
var _has_dest := false
var _last_seen := Vector3.ZERO
var _lost_time := 0.0
var _think_left := 0.0
var _repath_left := 0.0
var _path_to := Vector3.ZERO
var _has_path := false
var _wait_left := 0.0
var _seen_time := 0.0
var _burst_left := 0.0
var _pause_left := 0.0
var _error := Vector3.ZERO
var _error_left := 0.0
var _strafe_sign := 1.0
var _strafe_left := 0.0
var _melee_wait := 0.0
var _guard_delay := 0.0
var _guard_dir := 0
var _read_left := 0.0
var _read_dir := 0
var _threat_seen := false
var _aim := Vector3.ZERO
var _aim_target: Actor
var _reaction := 0.0
var _wander := Vector2.ZERO
var _wander_goal := Vector2.ZERO
var _wander_left := 0.0
var _lag := 0.0
var _on_target := false


func _ready() -> void:
	actor = get_parent() as Actor
	process_physics_priority = -5
	_rng.seed = seed_value
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 1.0
	_nav.target_desired_distance = 1.5
	add_child(_nav)
	_home = actor.global_position
	actor.cmd.yaw = _rng.randf_range(-PI, PI)
	# Not every bot thinks on the same tick.
	_think_left = _rng.randf() * 0.2
	if skill < 0.0:
		skill = _rng.randf_range(0.25, 0.75)
	actor.health.damaged.connect(_on_damaged)
	actor.heard.connect(_on_heard)


## Sends the bot to hold a place: it walks there and patrols around it from
## then on. Fights along the way still come first.
func post_to(point: Vector3, radius: float) -> void:
	_home = point
	patrol_radius = minf(patrol_radius, maxf(radius * 0.8, 4.0))
	_has_dest = false
	_wait_left = 0.0


## Where the bot is posted.
func home() -> Vector3:
	return _home


func _physics_process(delta: float) -> void:
	if actor.is_dead:
		return
	# A bot nobody is near thinks only on the ticks its body moves.
	if not actor.ticks_now():
		return
	delta *= actor.tick_every
	var cmd := actor.cmd
	cmd.clear_one_shots()
	cmd.primary = false
	cmd.secondary = false
	cmd.sprint = false
	cmd.move = Vector2.ZERO
	cmd.aim_dir = Vector3.ZERO

	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = 0.2
		target = _find_target()

	if target and is_instance_valid(target) and not target.is_dead:
		_last_seen = target.global_position
		_lost_time = 0.0
		_seen_time += delta
		state = State.ATTACK
		_attack(cmd, delta)
	elif state != State.PATROL:
		_seen_time = 0.0
		_aim_target = null
		_lost_time += delta
		state = State.CHASE
		if _lost_time > give_up_time or _flat_dist(_last_seen) < 2.0:
			state = State.PATROL
			_has_dest = false
		else:
			cmd.sprint = true
			_move_toward(cmd, _last_seen, delta, true)
	else:
		_patrol(cmd, delta)


func _attack(cmd: ActorCommand, delta: float) -> void:
	_error_left -= delta
	if _error_left <= 0.0:
		_error_left = 0.35
		_error = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	var eye := actor.get_eye_position()
	var chest := target.global_position + Vector3(0, 1.1, 0)
	var dist := eye.distance_to(chest)

	var blade := actor.get_active_weapon() as MeleeWeapon
	if blade:
		var aim_point := chest + _error * dist * aim_error
		_look_along(cmd, aim_point - eye)
		cmd.aim_dir = (aim_point - eye).normalized()
		_aim = cmd.aim_dir
		_attack_melee(cmd, blade, delta)
		return
	_aim_gun(cmd, eye, chest, dist, delta)

	# Keep a comfortable distance: close in, back off, or strafe.
	if dist > preferred_range * 1.4:
		_move_toward(cmd, target.global_position, delta, false)
	elif dist < preferred_range * 0.5:
		cmd.move = Vector2(0, -1)
	else:
		_strafe_left -= delta
		if _strafe_left <= 0.0:
			_strafe_left = _rng.randf_range(0.8, 2.0)
			_strafe_sign = -_strafe_sign
		cmd.move = Vector2(_strafe_sign, 0)

	if _seen_time < _reaction or dist > attack_range or not _on_target:
		return
	if _burst_left > 0.0:
		_burst_left -= delta
		cmd.primary = true
		cmd.primary_pressed = true
		if _burst_left <= 0.0:
			_pause_left = burst_pause * _rng.randf_range(0.7, 1.4)
	else:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_burst_left = burst_time


## Turns the bot's aim toward the target the way a person would (see the
## aim tuning at the top) and sets `_on_target` when it is close enough to
## shoot. A new target means a fresh reaction time and a wide first aim.
func _aim_gun(cmd: ActorCommand, eye: Vector3, chest: Vector3, dist: float, delta: float) -> void:
	var sharp := clampf(skill, 0.0, 1.0)
	if target != _aim_target:
		_aim_target = target
		_seen_time = 0.0
		_reaction = reaction_time * _rng.randf_range(0.8, 1.3) * (1.4 - 0.8 * sharp)
		_wander_left = 0.0
		# The first look lands off to one side.
		_wander = Vector2.from_angle(_rng.randf() * TAU)
		if _aim.length_squared() < 0.5:
			_aim = Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0)) * Vector3.FORWARD
	# Where it means to aim: where the target was a moment ago, plus a
	# wander that drifts rather than jumps.
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = _rng.randf_range(0.3, 0.6)
		_wander_goal = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).limit_length(1.0)
		_lag = track_lag * _rng.randf_range(0.4, 1.3) * (1.5 - sharp)
	_wander = _wander.lerp(_wander_goal, clampf(delta * 5.0, 0.0, 1.0))
	var settle := lerpf(settle_mult, 1.0, clampf(_seen_time / settle_time, 0.0, 1.0))
	var error := aim_error_deg * (1.5 - sharp) * settle
	if target.airborne_time > 0.15:
		error += air_error_deg
	error += far_error_deg * maxf(dist - preferred_range, 0.0)
	if Vector2(actor.velocity.x, actor.velocity.z).length() > 1.0:
		error += self_move_error_deg
	var to := (chest - target.velocity * _lag - eye).normalized()
	var side := to.cross(Vector3.UP).normalized()
	var up := side.cross(to).normalized()
	var off := deg_to_rad(error)
	var want := (to + side * tan(_wander.x * off) + up * tan(_wander.y * off)).normalized()
	# Turn at a limited speed: no snap.
	var gap := _aim.angle_to(want)
	var step := deg_to_rad(turn_speed_deg * (0.6 + 0.8 * sharp)) * delta
	if gap > 0.0001:
		_aim = _aim.slerp(want, minf(1.0, step / gap)).normalized()
	_on_target = _aim.angle_to(want) < deg_to_rad(fire_cone_deg)
	_look_along(cmd, _aim)
	cmd.aim_dir = _aim


## Rush the target and swing from a random side when in reach. Between swings
## the bot guards one side on a guess, and sometimes reads an incoming swing
## and moves its guard to meet it. Swings have a visible windup, so a
## well-timed parry on the right side turns the fight.
func _attack_melee(cmd: ActorCommand, blade: MeleeWeapon, delta: float) -> void:
	var dist := _flat_dist(target.global_position)
	_melee_wait = maxf(0.0, _melee_wait - delta)
	_guard_delay = maxf(0.0, _guard_delay - delta)
	if dist > blade.reach * 0.7:
		cmd.sprint = true
		_move_toward(cmd, target.global_position, delta, false)

	var foe_blade := target.get_active_weapon() as MeleeWeapon
	var threatened := foe_blade != null and foe_blade.threat_dir() >= 0 and dist <= foe_blade.reach * 1.5
	if threatened and not _threat_seen and _rng.randf() < guard_skill:
		_read_left = guard_reaction
		_read_dir = MeleeWeapon.mirror(foe_blade.threat_dir())
	_threat_seen = threatened
	if _read_left > 0.0:
		_read_left -= delta
		if _read_left <= 0.0 and _guard_dir != _read_dir:
			# Drop the guard for a tick so it comes back up on the right side.
			_guard_dir = _read_dir
			return

	if dist <= blade.reach * 0.9 and _melee_wait <= 0.0 and _seen_time >= reaction_time and not threatened:
		cmd.stance = _rng.randi_range(0, MeleeWeapon.Dir.size() - 1)
		cmd.primary_pressed = true
		_melee_wait = _rng.randf_range(1.0, 1.7)
		_guard_delay = 0.75
		_guard_dir = _rng.randi_range(0, MeleeWeapon.Dir.size() - 1)
		return
	if dist <= blade.reach * 1.6 and _guard_delay <= 0.0 and _seen_time >= reaction_time \
			and not blade.is_winding_up():
		cmd.stance = _guard_dir
		cmd.secondary = true


func _patrol(cmd: ActorCommand, delta: float) -> void:
	if _wait_left > 0.0:
		_wait_left -= delta
		return
	if not _has_dest:
		var angle := _rng.randf_range(0, TAU)
		_dest = _home + Vector3(cos(angle), 0, sin(angle)) * _rng.randf_range(5.0, patrol_radius)
		_has_dest = true
		_repath_left = 0.0
	if _flat_dist(_dest) < 2.0:
		_has_dest = false
		_wait_left = _rng.randf_range(1.0, 3.5)
		return
	# A long way from the post: this is a march, not a patrol.
	cmd.sprint = _flat_dist(_home) > patrol_radius + march_distance
	_move_toward(cmd, _dest, delta, true)
	# Give up on a point we cannot reach.
	if actor.get_real_velocity().length() < 0.3:
		_wait_left = 0.0
		if _rng.randf() < delta * 0.7:
			_has_dest = false


## Walks toward a point using the navmesh when one is ready, else in a straight line.
func _move_toward(cmd: ActorCommand, dest: Vector3, delta: float, face_travel: bool) -> void:
	# A new path is the dearest thing a bot does, so it asks for one only when
	# the place it is going has really moved (further for a far-off place), or
	# when the path it has ran out short of it: a search only reaches so far,
	# and a long march arrives in legs.
	_repath_left -= delta
	var dir := dest - actor.global_position
	if _repath_left <= 0.0:
		var moved := dest.distance_to(_path_to)
		var short := _nav.is_navigation_finished() and _flat_dist(dest) > 3.0
		if not _has_path or short or moved > maxf(repath_distance, dir.length() * 0.15):
			_has_path = true
			_path_to = dest
			_nav.target_position = dest
			_repath_left = 0.4
	var map_rid := _nav.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map_rid) > 0:
		var next := _nav.get_next_path_position()
		var step := next - actor.global_position
		step.y = 0.0
		if step.length() > 0.2:
			dir = step
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	if face_travel:
		_look_along(cmd, dir)
	var local := Basis(Vector3.UP, cmd.yaw).inverse() * dir
	cmd.move = Vector2(local.x, -local.z)


func _look_along(cmd: ActorCommand, dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	cmd.yaw = atan2(-dir.x, -dir.z)
	cmd.pitch = asin(clampf(dir.y, -1.0, 1.0))


func _find_target() -> Actor:
	var best: Actor = null
	var best_dist := sight_range
	var eye := actor.get_eye_position()
	var forward := Basis(Vector3.UP, actor.cmd.yaw) * Vector3.FORWARD
	var world := Worlds.of(actor)
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == actor or other.is_dead or other.faction == actor.faction:
			continue
		# Distance first: it is the cheapest way to rule most of a big field out.
		var chest := other.global_position + Vector3(0, 1.1, 0)
		var dist := eye.distance_to(chest)
		if dist >= best_dist:
			continue
		# A Phase Cloak hides all but someone right beside the bot.
		if other.is_cloaked() and dist > other.artifact.cloak_sense_range:
			continue
		if not Raid.together(actor, other):
			continue
		if world and not world.can_damage(actor, other, null):
			continue
		var in_view := forward.angle_to((chest - eye).normalized()) < deg_to_rad(fov_deg) * 0.5
		if not in_view and dist > close_sense_range and other != target:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, chest, Actor.LAYER_WORLD)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = other
		best_dist = dist
	return best


func _flat_dist(point: Vector3) -> float:
	var d := point - actor.global_position
	d.y = 0.0
	return d.length()


## Getting shot tells the bot where to look, even if it never saw the shooter.
func _on_damaged(info: DamageInfo) -> void:
	var source := info.source as Actor
	if source and source != actor and state == State.PATROL:
		_last_seen = source.global_position
		_lost_time = 0.0
		state = State.CHASE


## Gunfire nearby (`Combat.noise`): a bot on patrol goes to look where it came
## from. A blade makes no noise, so a melee kill leaves the rest on patrol.
func _on_heard(at: Vector3, source: Actor) -> void:
	if state != State.PATROL or source == null or source.faction == actor.faction:
		return
	var world := Worlds.of(actor)
	if world and not world.can_damage(actor, source, null):
		return
	_last_seen = at
	_lost_time = 0.0
	state = State.CHASE
