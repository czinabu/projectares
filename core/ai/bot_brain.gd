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
## Scales the pause between swings. A world sets `melee_tempo` on the bot
## (a heavy that should land more than one swing in the time a gun takes to
## answer). 1 is the default cadence.
var melee_tempo := 1.0
var guard_reaction := 0.22
## Melee bots fight like people (DESIGN.md "Melee bots"): a share of their
## attacks are held heavies (more against a raised guard, which a heavy
## breaks), some charges are feints that switch side and release as a quick
## light, a sprinting bot opens with a dash-strike from out of reach, and a
## bot strikes at once into a foe's recovery, stagger or its own riposte.
## Heavies, feints and dash-strikes come with the ring (`RING_HEAVY`,
## `RING_FEINT`, `RING_DASH`): the outer ring never dash-strikes.
const RING_FEINT := [0.0, 0.15, 0.3]
const RING_DASH := [0.0, 0.4, 0.7]
const RING_HEAVY := [0.05, 0.2, 0.3]
## A blade in reach beats a rifle (Caleb's call): an army bot cut by a
## blade flinches, its gun knocked `melee_knock_deg` off and its trigger
## held for `melee_flinch` seconds, so once a blade reaches a soldier the
## gun loses. Bots only: a player's aim is never moved.
var melee_flinch := 0.4
## An army gunner gives ground from a blade closer than this, from the hip.
var blade_backoff := 9.0
var melee_knock_deg := 14.0
var heavy_share := 0.25
var heavy_vs_guard := 0.6
var feint_chance := 0.15
var dash_chance := 0.6
## The least time between dash-strike tries, seconds.
var dash_every := 3.0
## How long a feint shows its first side before it switches, seconds
## (under `MeleeWeapon.hold_time`, so the release is a light).
var feint_show := 0.15

## Gun aim. Bots aim like people, not like an aimbot: they turn onto a target
## at a limited speed, trail it while it moves, and their aim wanders by an
## angle that starts wide on first sight and settles while they hold it in
## view. Moving, airborne and distant targets are harder to hit.
## 0 is a rookie, 1 a veteran. Below 0, each bot rolls its own from its seed.
var skill := -1.0
## The range a bot rolls its skill from when `skill` is below 0. The `Raid`
## sets it from `WorldDef.bot_skill_range` (risk zones, warlords).
var skill_range := Vector2(0.25, 0.75)
## Turn speed onto the target, degrees a second (at skill 0.5).
var turn_speed_deg := 200.0
## Seconds the aim trails a moving target (at skill 0.5).
var track_lag := 0.22
## Settled aim wander, degrees (at skill 0.5). Wide enough that a rookie
## misses a runner, tight enough that a settled shot at rifle range can hit.
var aim_error_deg := 1.55
## The wander on first sight is this many times the settled one...
var settle_mult := 3.0
## ...and settles over this long in view.
var settle_time := 2.5
## Extra wander when the target is in the air, and per metre past
## `preferred_range`, degrees.
var air_error_deg := 3.0
var far_error_deg := 0.08
## Extra wander while the bot itself is moving, degrees.
var self_move_error_deg := 0.65
## Fires only when its aim is within this of where it means to aim, degrees.
var fire_cone_deg := 6.0

## Rival raiders (see `Raid._tick_raiders`). The `Raid` sends one on errands
## with `go_to` (a cache to loot) and has it `holding` still while it signs
## out; fights come first either way. `flies` lets it use its flight rig:
## jets or a kick over whatever it is stuck on, and a jetpack wearer takes
## to the air in a gunfight, hovering on held aim like a player.
var flies := false
## Seconds between a flier's hops in a gunfight, and how long one lasts, the
## first `combat_climb` of it climbing.
var combat_hop_every := Vector2(5.0, 10.0)
var combat_hop_time := 2.4
var combat_climb := 0.8
## A flier stuck this long, pushing against something, lifts off for
## `unstick_lift` seconds.
var stuck_time := 0.8
var unstick_lift := 1.2
## Below this heat (of the rig's 100) a flier starts a hop.
var hop_heat := 40.0
## A bot that wears a player's kit (a raider) looks after it the way a
## player does: back to the primary and a fresh mag between fights, the
## blade once every gun is dry, and a heal from its pack when hurt.
var uses_kit := false
## Below this share of its health it heals between fights...
var heal_below := 0.7
## ...and in a fight too, once this low and with nobody close.
var heal_desperate := 0.3
var heal_clear_range := 12.0
var holding := false
var errand := Vector3.ZERO
var has_errand := false

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
## A charge in progress: hold the attack button this much longer, then
## let go (a heavy turns by itself past `hold_time`). A feint switches to
## `_feint_to` when `_hold_left` falls to `_feint_at`.
var _hold_left := 0.0
var _hold_stance := 0
var _feint_at := -1.0
var _feint_to := 0
var _dash_wait := 0.0
var _flinch_left := 0.0
## Recoil reaches a bot's aim too (`Gun.recoil_for`): it pulls against
## `recoil_control` of each kick, from `RECOIL_CONTROL` by skill, so a
## rookie's long burst climbs off target and a veteran's holds.
const RECOIL_CONTROL := Vector2(0.55, 0.9)
const RECOIL_SETTLE_DELAY := 0.1
const RECOIL_SETTLE := 9.0
var _recoil_gun: Gun
var _recoil_seen := 0
## The climb (up, right; degrees) the bot's aim is off by from recoil.
var _recoil := Vector2.ZERO
var _recoil_rest := 0.0
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
## A gun that must hold a lock before it fires (a walker's cannon): seconds
## the aim has to stay on a target it can see, from the actor's meta
## "lock_time" (0 for none). Breaking the line of sight starts it over.
var lock_time := 0.0
## Group fights (DESIGN.md "Group fights", Caleb's call): a person (a
## player, or a bot that plays like one) is shot at by only `attack_slots`
## army bots at a time. The rest hold off, take cover or work round the
## flank until a slot comes free; slots are held a few seconds
## (`token_hold`) and pass along with a beat between (`token_beat`). A bot
## always shoots back at whoever hit it in the last `return_fire_time`
## seconds, and at anyone inside `point_blank`. Set from the bot's ring
## ("zone" meta): `RING_SLOTS`.
const RING_SLOTS := [1, 2, 3]
var attack_slots := 2
var token_hold := Vector2(2.5, 4.0)
var token_beat := 0.5
var return_fire_time := 2.0
var point_blank := 7.0
## Bots on the outer ring hold their cover; further in they also flank.
var flanks := true
## A target further off is spotted more slowly: the reaction time grows
## to this many times its near value at the edge of sight, and a crouched
## target takes `crouch_notice_mult` longer still.
var far_notice_mult := 1.6
var crouch_notice_mult := 1.3

## Who holds a slot on each person, by the person's instance id:
## {"holders": {brain id: physics frame it lets go}, "free_at": frame}.
static var _slots := {}
## Off lets every bot shoot at once (the group bench's `--slots off`, to
## compare); always on in play.
static var ration_attacks := true
var _rest_until := 0
var _hit_by: Actor
var _hit_at := -1000000
var _cover := Vector3.INF
var _cover_left := 0.0
var _lock := 0.0
var _stuck_for := 0.0
var _lift_left := 0.0
var _hop_in := 3.0
var _hop_left := 0.0


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
		skill = _rng.randf_range(skill_range.x, skill_range.y)
	if actor.has_meta("melee_tempo"):
		melee_tempo = float(actor.get_meta("melee_tempo"))
	# A world may give a body its own aim: a heavy machine that comes round
	# slowly ("aim_turn", degrees a second) but leads a moving or flying
	# target well ("track_lag", "air_error", see the aim tuning above).
	if actor.has_meta("aim_turn"):
		turn_speed_deg = float(actor.get_meta("aim_turn"))
	if actor.has_meta("track_lag"):
		track_lag = float(actor.get_meta("track_lag"))
	if actor.has_meta("air_error"):
		air_error_deg = float(actor.get_meta("air_error"))
	lock_time = float(actor.get_meta("lock_time", 0.0))
	var ring := int(actor.get_meta("zone", 1))
	attack_slots = RING_SLOTS[clampi(ring, 0, RING_SLOTS.size() - 1)]
	feint_chance = RING_FEINT[clampi(ring, 0, RING_FEINT.size() - 1)]
	dash_chance = RING_DASH[clampi(ring, 0, RING_DASH.size() - 1)]
	heavy_share = RING_HEAVY[clampi(ring, 0, RING_HEAVY.size() - 1)]
	flanks = ring > 0
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


## Sends the bot to a place (a raider to a cache). It runs there whenever
## it is not fighting, and stays once it arrives (`at_errand`).
func go_to(point: Vector3) -> void:
	errand = point
	has_errand = true
	holding = false


## Done with its errand: it patrols where it stands until given another.
func clear_errand() -> void:
	has_errand = false
	_home = actor.global_position
	_has_dest = false


func at_errand() -> bool:
	return has_errand and _flat_dist(errand) < 2.2 and absf(errand.y - actor.global_position.y) < 2.5


func _physics_process(delta: float) -> void:
	if actor.is_dead:
		_release()
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
	cmd.jump = false
	cmd.crouch = false
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
		_release()
		_hold_left = 0.0
		_seen_time = 0.0
		_aim_target = null
		_lock = 0.0
		_lost_time += delta
		state = State.CHASE
		if _lost_time > give_up_time or _flat_dist(_last_seen) < 2.0:
			state = State.PATROL
			_has_dest = false
		else:
			cmd.sprint = true
			_move_toward(cmd, _last_seen, delta, true)
	elif holding:
		_stuck_for = 0.0
	elif has_errand:
		if not at_errand():
			cmd.sprint = true
			_move_toward(cmd, errand, delta, true)
	else:
		_patrol(cmd, delta)
	if uses_kit:
		_tend_kit(cmd)


## Looks after a player's kit (`uses_kit`): heal when hurt and safe enough,
## put the primary back in hand and reload it between fights, and in a fight
## swap off a gun with nothing left for one with rounds, or the blade.
## Only presses, the same keys a player would use.
func _tend_kit(cmd: ActorCommand) -> void:
	var share := actor.health.health / maxf(actor.health.max_health, 1.0)
	var near := target != null and is_instance_valid(target) \
			and actor.global_position.distance_to(target.global_position) < heal_clear_range
	if actor.heal_time_left <= 0.0 and actor.inventory.first_with_tag("heal") != "" \
			and ((state == State.PATROL and share < heal_below) or (share < heal_desperate and not near)):
		cmd.heal_pressed = true
		return
	if actor.heal_time_left > 0.0:
		return
	var held := actor.get_active_weapon()
	var gun := held as Gun
	if state == State.ATTACK:
		# Dry with nothing to reload from: the other gun if it has rounds,
		# else the blade.
		if held == null or (gun != null and gun.is_spent()):
			var next := _loaded_gun()
			cmd.switch_weapon = next if next >= 0 else _blade_index()
		return
	if state != State.PATROL:
		return
	var primary := _primary_index()
	if primary >= 0 and actor.active_weapon_index != primary and not (actor.weapons[primary] as Gun).is_spent():
		cmd.switch_weapon = primary
	elif gun != null and not gun.is_reloading() and gun.ammo_in_mag < gun.mag_size and gun.reserve_ammo > 0:
		cmd.reload_pressed = true
	elif held == null:
		var any := _loaded_gun()
		cmd.switch_weapon = any if any >= 0 else _blade_index()


func _primary_index() -> int:
	for i in actor.weapons.size():
		var gun := actor.weapons[i] as Gun
		if gun != null and not gun.is_sidearm and not gun.is_power():
			return i
	return -1


## A gun that can still shoot, the primary first, or -1.
func _loaded_gun() -> int:
	for i in actor.slot_order():
		var gun := actor.weapons[i] as Gun
		if gun != null and not gun.is_spent():
			return i
	return -1


func _blade_index() -> int:
	for i in actor.weapons.size():
		if actor.weapons[i] is MeleeWeapon:
			return i
	return -1


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
		if not _may_attack(dist):
			_wait_turn_melee(cmd, blade, delta)
			return
		_attack_melee(cmd, blade, delta)
		return
	_aim_gun(cmd, eye, chest, dist, delta)
	_combat_hop(cmd, delta)
	var my_turn := _may_attack(dist)
	if not my_turn:
		# Keep the gun on them, ready, but hold fire and get somewhere better.
		_wait_turn(cmd, delta, dist)
		return
	# Aim down sights on the ground, the way a person fights a duel. In the
	# air the hop owns the aim button (a jetpack hovers while it is held).
	# A gun that locks on raises its aim (and its tracking beam, which every
	# view draws from the held aim) only once it has reacted, as the lock starts.
	# The gun comes up halfway through the reaction: the tell before the
	# first shot (every view sees it, and hears the bark, `ActorSkin`).
	var raise_at := _reaction if lock_time > 0.0 else _reaction * 0.5
	if actor.is_on_floor() and _hop_left <= 0.0 and _seen_time >= raise_at:
		cmd.secondary = true

	# A blade coming in: give ground from the hip at a full walk, angling
	# off, rather than stand aiming down sights to be cut.
	if not uses_kit and target.get_active_weapon() is MeleeWeapon and dist < blade_backoff:
		cmd.secondary = false
		cmd.move = Vector2(_strafe_sign * 0.6, -1.0).normalized()
	# Keep a comfortable distance: close in, back off, or strafe.
	elif dist > preferred_range * 1.4:
		_move_toward(cmd, target.global_position, delta, false)
	elif dist < preferred_range * 0.5:
		cmd.move = Vector2(0, -1)
	else:
		_strafe_left -= delta
		if _strafe_left <= 0.0:
			_strafe_left = _rng.randf_range(0.8, 2.0)
			_strafe_sign = -_strafe_sign
		cmd.move = Vector2(_strafe_sign, 0)

	if _flinch_left > 0.0:
		_flinch_left -= delta
		return
	if _seen_time < _reaction or dist > attack_range or not _on_target:
		_lock = 0.0 if not _on_target else _lock
		return
	if lock_time > 0.0:
		# The tracking beam: a lock builds while the target stays in sight,
		# and a wall (or a flier ducking behind one) breaks it.
		var query := PhysicsRayQueryParameters3D.create(eye, chest, Actor.LAYER_WORLD)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			_lock = 0.0
			return
		_lock += delta
		if _lock < lock_time:
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
	_take_recoil(delta)
	if target != _aim_target:
		_aim_target = target
		_seen_time = 0.0
		_lock = 0.0
		_reaction = reaction_time * _rng.randf_range(0.8, 1.3) * (1.4 - 0.8 * sharp) \
				* notice_mult(dist, sight_range, target.crouched, far_notice_mult, crouch_notice_mult)
		if _hit_by == target and _since_hit() < return_fire_time:
			_reaction *= 0.5
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
	var want := (to + side * tan(_wander.x * off + deg_to_rad(_recoil.y))
			+ up * tan(_wander.y * off + deg_to_rad(_recoil.x))).normalized()
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
	_dash_wait = maxf(0.0, _dash_wait - delta)
	if _hold_left > 0.0:
		_carry_charge(cmd, blade, delta, dist)
		return
	if dist > blade.reach * 0.7:
		cmd.sprint = true
		_move_toward(cmd, target.global_position, delta, false)
	if _try_dash_strike(cmd, blade, dist):
		return
	# Closing on a gunner with a blade, a bot that plays like a person keeps
	# its guard up (the fresh guard turns rounds aside, then it halves them).
	if uses_kit and target.get_active_weapon() is Gun and dist > blade.reach * 1.1:
		cmd.secondary = true
		return

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

	# An opening: the foe is recovering from a swing, staggered, or this bot
	# just parried. Strike now rather than wait out the tempo.
	var opening := actor.riposte_left > 0.0 or target.stagger_left > 0.0 \
			or (foe_blade != null and foe_blade.recover_progress() >= 0.0 and foe_blade.recover_progress() < 0.6)
	var may_swing := _melee_wait <= 0.0 or opening
	if dist <= blade.reach * 0.9 and may_swing and _seen_time >= reaction_time and not threatened \
			and not blade.is_busy():
		_start_attack(cmd, blade, opening)
		return
	if dist <= blade.reach * 1.6 and _guard_delay <= 0.0 and _seen_time >= reaction_time \
			and not blade.is_winding_up():
		cmd.stance = _guard_dir
		cmd.secondary = true


## Picks the next swing: a light tap, a held heavy (likelier into a raised
## guard or a stagger), or a feint.
func _start_attack(cmd: ActorCommand, blade: MeleeWeapon, opening: bool) -> void:
	var stance := _rng.randi_range(0, MeleeWeapon.Dir.size() - 1)
	cmd.stance = stance
	_melee_wait = _rng.randf_range(1.0, 1.7) * melee_tempo
	if uses_kit:
		# A person chains the three-hit combo, then breathes.
		_melee_wait = _rng.randf_range(0.3, 0.45) if blade.combo_step < 2 else _rng.randf_range(0.8, 1.2)
	_guard_delay = 0.75
	_guard_dir = _rng.randi_range(0, MeleeWeapon.Dir.size() - 1)
	var guarded := false
	var foe_blade := target.get_active_weapon() as MeleeWeapon
	if foe_blade != null:
		guarded = foe_blade.is_blocking()
	var heavy_odds := heavy_vs_guard if guarded or target.stagger_left > 0.0 else heavy_share
	if opening and actor.riposte_left > 0.0:
		heavy_odds = maxf(heavy_odds, 0.5)
	if actor.stamina >= blade.heavy_stamina and _rng.randf() < heavy_odds:
		# Hold through the turn into a heavy: its charge and windup show.
		_hold_left = blade.hold_time + 0.05
		_hold_stance = stance
		_feint_at = -1.0
		cmd.primary_pressed = true
		cmd.primary = true
		return
	if not opening and _rng.randf() < feint_chance:
		# Show one side, then switch and let go as a quick light.
		_hold_left = feint_show + 0.02
		_hold_stance = stance
		_feint_at = 0.02
		_feint_to = (stance + _rng.randi_range(1, MeleeWeapon.Dir.size() - 1)) % MeleeWeapon.Dir.size()
		cmd.primary_pressed = true
		cmd.primary = true
		return
	cmd.primary_pressed = true


## Keeps a charge held (and switches a feint's side) until it is let go.
func _carry_charge(cmd: ActorCommand, blade: MeleeWeapon, delta: float, dist: float) -> void:
	_hold_left -= delta
	if _feint_at >= 0.0 and _hold_left <= _feint_at:
		_hold_stance = _feint_to
		_feint_at = -1.0
	cmd.stance = _hold_stance
	if dist > blade.reach * 0.6:
		_move_toward(cmd, target.global_position, delta, false)
	if _hold_left > 0.0:
		cmd.primary = true
	else:
		_hold_left = 0.0


## A bot running in from out of reach opens with a dash-strike (a heavy
## started at a sprint closes up to `MeleeWeapon.dash_range`).
func _try_dash_strike(cmd: ActorCommand, blade: MeleeWeapon, dist: float) -> bool:
	if blade.dash_range <= 0.0 or _dash_wait > 0.0 or blade.is_busy() or not cmd.sprint:
		return false
	if dist < blade.reach * 1.4 or dist > blade.reach + blade.dash_range * 0.8:
		return false
	if _seen_time < reaction_time or not actor.is_on_floor():
		return false
	if actor.stamina < blade.heavy_stamina + blade.dash_stamina:
		return false
	_dash_wait = dash_every
	if _rng.randf() >= dash_chance:
		return false
	cmd.stance = _rng.randi_range(0, MeleeWeapon.Dir.size() - 1)
	cmd.tertiary_pressed = true
	_melee_wait = _rng.randf_range(1.0, 1.7) * melee_tempo
	_guard_delay = 0.75
	return true


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
	if flies:
		_unstick(cmd, delta)


## A flier pushing against something it cannot walk over lifts off: a jump
## held into the rig's own lift (a jetpack's jets on held aim, the boots'
## skim, the wings' glide), the same keys a player would hold.
func _unstick(cmd: ActorCommand, delta: float) -> void:
	if not actor.flight.enabled:
		return
	if actor.is_on_floor() and actor.get_real_velocity().length() < 0.6:
		_stuck_for += delta
	else:
		_stuck_for = 0.0
	if _stuck_for > stuck_time and not actor.flight.overheated:
		_stuck_for = 0.0
		_lift_left = unstick_lift
	if _lift_left <= 0.0:
		return
	_lift_left -= delta
	if actor.is_on_floor():
		cmd.jump_pressed = true
	cmd.jump = true
	if actor.flight.can_hover():
		cmd.secondary = true


## A jetpack wearer in a gunfight takes to the air now and then: up off the
## ground, a climb, then a hover on held aim while it shoots, and down again
## when it lets go. It costs heat like anyone's, so it waits for a cool rig.
func _combat_hop(cmd: ActorCommand, delta: float) -> void:
	if not flies or not actor.flight.enabled or not actor.flight.can_hover():
		return
	if _hop_left > 0.0:
		_hop_left -= delta
		cmd.secondary = true
		cmd.jump = _hop_left > combat_hop_time - combat_climb
		return
	_hop_in -= delta
	if _hop_in <= 0.0 and actor.is_on_floor() and actor.flight.heat < hop_heat and not actor.flight.overheated:
		_hop_in = _rng.randf_range(combat_hop_every.x, combat_hop_every.y)
		_hop_left = combat_hop_time
		cmd.jump_pressed = true
		cmd.jump = true


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
	# A storm cuts how far a bot sees (DESIGN.md "Weather: ash storms"), by
	# the worse of where it stands and where its target does.
	var raid := Raid.of(actor)
	var weather: Weather = raid.weather if raid != null and raid.weather.kind != "" else null
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == actor or other.is_dead or other.faction == actor.faction:
			continue
		# Distance first: it is the cheapest way to rule most of a big field out.
		var chest := other.global_position + Vector3(0, other.body_height() * 0.6, 0)
		var dist := eye.distance_to(chest)
		if dist >= best_dist:
			continue
		if weather != null and dist >= sight_range * weather.sight_between(eye, chest):
			continue
		# A Phase Cloak hides all but someone right beside the bot.
		if other.is_cloaked() and dist > other.artifact.cloak_sense_range:
			continue
		if not Raid.together(actor, other):
			continue
		if world and not world.can_damage(actor, other, null):
			continue
		var in_view := forward.angle_to((chest - eye).normalized()) < deg_to_rad(fov_deg) * 0.5
		# Someone crouched creeps up quieter: sensed only closer in.
		var sense := close_sense_range * (other.crouch_sense_mult if other.crouched else 1.0)
		if not in_view and dist > sense and other != target:
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
	if source and source != actor:
		_hit_by = source
		_hit_at = Engine.get_physics_frames()
	if info.kind == "melee" and info.amount > 0.0 and not uses_kit and actor.get_active_weapon() is Gun:
		_flinch(melee_flinch, melee_knock_deg)
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


## How much longer than its near reaction a bot takes to spot someone `dist`
## away (up to `far` times at `sight`), longer still for a crouched body.
static func notice_mult(dist: float, sight: float, crouched: bool, far: float, crouch: float) -> float:
	var mult := lerpf(1.0, far, clampf(dist / maxf(sight, 1.0), 0.0, 1.0))
	return mult * (crouch if crouched else 1.0)


func _since_hit() -> float:
	return float(Engine.get_physics_frames() - _hit_at) / Engine.physics_ticks_per_second


## Someone who takes slots: a player, or a bot that plays like one.
static func is_person(other: Actor) -> bool:
	var brain := other.get_node_or_null("Brain") as BotBrain
	return brain == null or brain.uses_kit


## Whether this bot may shoot or swing at its target now (see `attack_slots`).
func _may_attack(dist: float) -> bool:
	if uses_kit or not ration_attacks or not is_person(target):
		return true
	if dist < point_blank or (_hit_by == target and _since_hit() < return_fire_time):
		return true
	return take_slot(target.get_instance_id(), get_instance_id(), attack_slots,
			Engine.get_physics_frames(), self)


## Asks for one of `slots` slots on the person `key` for the brain `me` at
## physics frame `now`; true while it holds one. Static so it can be checked
## on its own. `brain` (may be null) times its hold and rest.
static func take_slot(key: int, me: int, slots: int, now: int, brain: BotBrain) -> bool:
	var slot: Dictionary = _slots.get(key, {})
	if slot.is_empty():
		slot = {"holders": {}, "free_at": 0}
		_slots[key] = slot
		if _slots.size() > 512:
			_prune(now)
	var holders: Dictionary = slot.holders
	var tps := Engine.physics_ticks_per_second
	var beat := int((brain.token_beat if brain else 0.5) * tps)
	for id: int in holders.keys():
		if holders[id] <= now:
			slot.free_at = maxi(slot.free_at, holders[id] + beat)
			holders.erase(id)
	if holders.has(me):
		return true
	if brain and now < brain._rest_until:
		return false
	if holders.size() >= slots or now < slot.free_at:
		return false
	var hold := 3.0
	if brain:
		hold = brain._rng.randf_range(brain.token_hold.x, brain.token_hold.y)
	var until := now + int(hold * tps)
	holders[me] = until
	slot.free_at = now + beat
	if brain:
		# Give the others a turn before taking another.
		brain._rest_until = until + int(hold * 0.6 * tps)
	return true


## How many hold a slot on the person `key` at frame `now`.
static func slot_holders(key: int, now: int) -> int:
	var slot: Dictionary = _slots.get(key, {})
	if slot.is_empty():
		return 0
	var count := 0
	for id: int in slot.holders:
		if slot.holders[id] > now:
			count += 1
	return count


static func _prune(now: int) -> void:
	for key: int in _slots.keys():
		var holders: Dictionary = _slots[key].holders
		if holders.values().all(func(until: int) -> bool: return until <= now):
			_slots.erase(key)


## Lets go of any slot this bot holds.
func _release() -> void:
	if target == null or not is_instance_valid(target):
		return
	var slot: Dictionary = _slots.get(target.get_instance_id(), {})
	if not slot.is_empty() and slot.holders.has(get_instance_id()):
		slot.holders.erase(get_instance_id())
		slot.free_at = maxi(slot.free_at, Engine.get_physics_frames() + int(token_beat * Engine.physics_ticks_per_second))


## Waiting for a slot with a gun: get into cover from the target, or round
## its flank, and keep the gun on them.
func _wait_turn(cmd: ActorCommand, delta: float, dist: float) -> void:
	_cover_left -= delta
	if _cover_left <= 0.0 or not _cover.is_finite():
		_cover_left = 1.5
		_cover = _find_cover()
		if not _cover.is_finite() and flanks:
			_cover = _flank_point(dist)
	if _cover.is_finite() and _flat_dist(_cover) > 1.0:
		_move_toward(cmd, _cover, delta, false)
		return
	if _cover.is_finite():
		# In cover: get down behind it.
		cmd.crouch = true
		return
	# Nowhere better: keep a respectful distance.
	if dist < preferred_range:
		cmd.move = Vector2(0, -1)


## Waiting for a slot with a blade: circle just out of reach, guard up.
func _wait_turn_melee(cmd: ActorCommand, blade: MeleeWeapon, delta: float) -> void:
	var dist := _flat_dist(target.global_position)
	if dist > blade.reach * 2.5:
		_move_toward(cmd, target.global_position, delta, false)
	elif dist < blade.reach * 1.8:
		cmd.move = Vector2(0, -1)
	else:
		cmd.move = Vector2(_strafe_sign, 0)
	cmd.stance = _guard_dir
	cmd.secondary = true


## A spot within a few metres where the target's eyes cannot see the bot's
## chest, still within shooting range; INF when none of the tries finds one.
func _find_cover() -> Vector3:
	var space := get_world_3d().direct_space_state
	var their_eye := target.get_eye_position()
	var from := actor.global_position
	var start := _rng.randf() * TAU
	for i in 6:
		var angle := start + TAU * i / 6.0
		var spot := from + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(3.0, 8.0)
		var reach := spot.distance_to(target.global_position)
		if reach > attack_range or reach < preferred_range * 0.5:
			continue
		var query := PhysicsRayQueryParameters3D.create(their_eye, spot + Vector3(0, 1.0, 0), Actor.LAYER_WORLD)
		if not space.intersect_ray(query).is_empty():
			return spot
	return Vector3.INF


## A point off the target's side, at the bot's preferred range.
func _flank_point(dist: float) -> Vector3:
	var off := actor.global_position - target.global_position
	off.y = 0.0
	if off.length() < 0.1:
		off = Vector3.FORWARD
	var turn := deg_to_rad(50.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var reach := clampf(dist, preferred_range * 0.8, attack_range * 0.8)
	return target.global_position + off.normalized().rotated(Vector3.UP, turn) * reach


## Knocks the gun off its aim and holds the trigger for `time` seconds.
func _flinch(time: float, knock_deg: float) -> void:
	_flinch_left = maxf(_flinch_left, time)
	_burst_left = 0.0
	if _aim.length_squared() > 0.0:
		var side := Vector3.UP.cross(_aim).normalized()
		_aim = _aim.rotated(Vector3.UP, deg_to_rad(knock_deg) * (1.0 if _rng.randf() < 0.5 else -1.0))
		if side.length_squared() > 0.0:
			_aim = _aim.rotated(side, deg_to_rad(knock_deg * 0.5) * _rng.randf_range(-1.0, 1.0))
		_on_target = false


## Adds the kick of any shot the held gun fired since the last tick to the
## climb the bot is fighting, less what it pulls against, and lets the climb
## settle once it stops firing (as a player's view settles).
func _take_recoil(delta: float) -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun != _recoil_gun:
		_recoil_gun = gun
		_recoil_seen = gun.shots_fired if gun else 0
	if gun != null and gun.shots_fired != _recoil_seen:
		var shots := gun.shots_fired - _recoil_seen
		_recoil_seen = gun.shots_fired
		var left := 1.0 - lerpf(RECOIL_CONTROL.x, RECOIL_CONTROL.y, skill)
		_recoil += gun.last_recoil * shots * left * (0.6 if gun.is_aiming() else 1.0)
		_recoil_rest = 0.0
		return
	_recoil_rest += delta
	if _recoil_rest >= RECOIL_SETTLE_DELAY:
		_recoil *= exp(-RECOIL_SETTLE * delta)
