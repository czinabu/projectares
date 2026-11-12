class_name Actor
extends CharacterBody3D
## A character in a raid: the player, a bot, or (later) a remote player.
##
## An Actor owns movement, health, inventory, weapons and the flight rig, and is
## driven only by its `cmd` (see ActorCommand). Controllers and AI live outside.

signal died(actor: Actor, info: DamageInfo)
signal landed(impact_speed: float)
## Short messages for whoever is watching this actor (the HUD for the player).
signal notice(text: String)
## This actor's attack landed on `target`. Drives hit markers and sounds.
signal hit_confirmed(target: Actor, info: DamageInfo, lethal: bool)
## The power weapon slot changed mid-raid (`Loadout.set_power`); "" is empty.
signal power_changed(item_id: String, mag: int, reserve: int)

const LAYER_WORLD := 1
const LAYER_ACTORS := 2
const LAYER_INTERACT := 4
## The body's capsule. `Combat.trace` tests rewound bodies against the same shape.
const BODY_RADIUS := 0.4
const BODY_HEIGHT := 1.8
## How far down from the top of the body a hit counts as a headshot.
const HEAD_SIZE := 0.3
## Where the hand sits on the body when a controller is not posing it.
const HAND_REST := Vector3(0.38, 1.25, -0.35)

var faction := "raider"
var display_name := "Raider"
## The clan this actor fights for (its id), or "". Clanmates cannot hurt each
## other (`Combat.deal`). Set by the authority; never trusted from a client.
var clan := ""
## The clan's short tag, for views to show beside the name.
var clan_tag := ""
var is_player := false
var body_color := Color(0.25, 0.6, 1.0)

# Movement tuning.
var walk_speed := 6.0
var sprint_speed := 9.5
var jump_velocity := 7.0
var gravity := 20.0
var ground_accel := 60.0
var air_accel := 14.0
var max_fall_speed := 50.0
var dash_speed := 18.0
## Shooting from the air: guns spread this many degrees wider and bloom by
## this much more per shot, except in a rig's steady state (see `air_aim`).
var air_spread_deg := 1.5
var air_bloom_mult := 1.5
var dash_time := 0.18
var dash_cooldown := 2.0

var eye_height := 1.6
var interact_range := 3.5
var heal_duration := 3.0
var heal_amount := 50.0

# Stamina pays for melee, blocking and dashing.
var max_stamina := 100.0
var stamina := 100.0
var stamina_regen := 28.0
var stamina_regen_delay := 0.9
var dash_stamina := 20.0
var stagger_speed_mult := 0.35
## Sliding: pressing slide while running fast drops you low and skids you
## along the ground, from `slide_speed` (or your speed, if faster) down to
## `slide_end_speed` over `slide_time`. Jumping ends it and keeps the speed.
var slide_speed := 11.0
var slide_end_speed := 4.0
var slide_time := 0.8
## The least ground speed a slide can start from.
var slide_min_speed := 7.0
var slide_cooldown := 0.6
var slide_stamina := 10.0
## How far the eyes drop while sliding, and how fast they get there (per second).
var slide_eye_drop := 0.75
var crouch_rate := 8.0

## How often the actor is simulated: every tick (1), or every nth tick with
## the time made up in one longer step. The authority thins out bots that no
## player is near (`Raid._tick_detail`); a player's own actor is never thinned.
var tick_every := 1

var cmd := ActorCommand.new()
var health := HealthComponent.new()
var inventory := Inventory.new()
var flight := FlightRig.new()
var ability := Ability.new()
## The helmet. Always there; `Visor.enabled` says whether one is worn.
var visor := Visor.new()
var weapons: Array[Weapon] = []
var active_weapon_index := 0
## Item ids of equipped gear (weapons, rig, armor). Dropped on death.
var gear_items: Array[String] = []
var frame_name := "No armor"
## How warm this actor looks through a thermal visor next to a bare body (1).
## Armor frames change it (see `Visor.heat_of`).
var heat_signature := 1.0
## The vehicle this actor is riding, or null. While riding, the vehicle moves
## the actor; weapons, healing and abilities still work.
var vehicle: Node3D = null

var is_dead := false
## Set in a safe zone: weapons can be drawn and shown but not used, and
## abilities and healing do nothing.
var weapons_locked := false
var heal_time_left := 0.0
var airborne_time := 0.0
## While staggered the actor cannot attack, block, dash or jump.
var stagger_left := 0.0
## Seconds left of the current slide; above zero while sliding.
var slide_left := 0.0
## How low the actor is crouched, 0 standing to 1 down in a slide.
var crouch := 0.0
## After a parry, the next melee hit inside this window hits harder.
var riposte_left := 0.0
## Seconds left of drop-in protection: nothing can hurt this actor. It ends
## early the moment they attack someone (see `Combat.deal`).
var protected_left := 0.0
## Public reputation. Written by the `Raid` that decides it (online, copied
## from the server); read by nameplates and the HUD. See `RenownLedger`.
var renown := 0
## Scrip carried: pay that is lost with the body until it is banked. Written
## by the `Raid`, like renown.
var scrip := 0
var rank := 0
var streak := 0
var bounty := 0
## Everyone can see where this actor is.
var exposed := false
var marked := false
var body_mesh: MeshInstance3D
## Holds the active weapon's model. A first-person camera may pose it itself.
var hand := Node3D.new()
var hand_override := false
## The weapon last put away with the holster key, drawn again by it.
var last_drawn := 0

var _ticks_waited := 0
var _dash_left := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _dash_speed_now := 0.0
var _slide_cd := 0.0
## Wings: the barrel roll's sidestep (velocity added this tick, taken off
## again before the glide steers next tick), its time left and cooldown.
var _roll_vel := Vector3.ZERO
var _roll_left := 0.0
var _roll_cd := 0.0
var _last_roll := 0
var _roll_side := 0.0
## Wings: seconds until a main gun can fire again after the wings fold.
var _wing_stow := 0.0
var _slide_dir := Vector3.ZERO
var _slide_from := 0.0
var _was_on_floor := true
var _stamina_wait := 0.0
var _flash_left := 0.0
var _healing_with := ""
var _base_material: Material


func _init() -> void:
	health.name = "Health"
	inventory.name = "Inventory"
	flight.name = "FlightRig"
	add_child(health)
	add_child(inventory)
	add_child(flight)
	ability.name = "Ability"
	ability.actor = self
	add_child(ability)
	visor.name = "Visor"
	visor.actor = self
	add_child(visor)
	hand.name = "Hand"
	hand.position = HAND_REST
	add_child(hand)


func _ready() -> void:
	add_to_group("actors")
	collision_layer = LAYER_ACTORS
	collision_mask = LAYER_WORLD | LAYER_ACTORS
	floor_snap_length = 0.3
	_build_body()
	health.died.connect(_on_health_died)
	health.damaged.connect(_on_health_damaged)


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = BODY_HEIGHT * 0.5
	add_child(col)

	var mesh := CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mesh.material = mat
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = mesh
	body_mesh.position.y = 0.9
	add_child(body_mesh)

	# A visor so you can tell which way a greybox character is facing.
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.5, 0.15, 0.2)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.05, 0.05, 0.05)
	visor_mesh.material = visor_mat
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 0.65, -0.32)
	body_mesh.add_child(visor)


## Thins the actor out to one step every `every` ticks. `phase` spreads
## thinned actors over different ticks.
func thin(every: int, phase := 0) -> void:
	every = maxi(every, 1)
	if every == tick_every:
		return
	tick_every = every
	_ticks_waited = phase % every


## Whether the actor is simulated this tick. Whatever drives it (a bot's
## brain) asks before the actor's own step, and skips the same ticks.
func ticks_now() -> bool:
	return _ticks_waited + 1 >= tick_every


## Whether the actor took a step in the tick just gone.
func stepped() -> bool:
	return _ticks_waited == 0


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if tick_every > 1:
		if not ticks_now():
			_ticks_waited += 1
			return
		_ticks_waited = 0
		delta *= tick_every
	rotation.y = cmd.yaw
	if not hand_override:
		hand.position = HAND_REST
		hand.rotation = Vector3(cmd.pitch, 0.0, 0.0)
	_simulate_timers(delta)
	if vehicle == null:
		_simulate_movement(delta)
	_simulate_weapons(delta)
	ability.tick(delta)
	if cmd.ability_pressed and stagger_left <= 0.0 and not weapons_locked:
		ability.activate()
	visor.tick(cmd, delta)
	if not weapons_locked:
		_simulate_heal(delta)
	# On a client of an online raid, using things is the server's decision.
	if cmd.interact_pressed and Combat.authoritative:
		var target := find_interactable()
		if target:
			target.interact(self)
	if global_position.y < -30.0:
		kill("void")


func _simulate_timers(delta: float) -> void:
	stagger_left = maxf(0.0, stagger_left - delta)
	riposte_left = maxf(0.0, riposte_left - delta)
	protected_left = maxf(0.0, protected_left - delta)
	_stamina_wait = maxf(0.0, _stamina_wait - delta)
	if _stamina_wait <= 0.0:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and body_mesh:
			body_mesh.material_override = _base_material


## Takes stamina if there is enough. Returns false and takes nothing otherwise.
func spend_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_wait = stamina_regen_delay
	return true


func pause_stamina_regen() -> void:
	_stamina_wait = maxf(_stamina_wait, 0.2)


func stagger(duration: float) -> void:
	stagger_left = maxf(stagger_left, duration)
	notice.emit("Staggered")


## Gives the weapon in hand a chance to block or parry a hit.
func modify_incoming(info: DamageInfo) -> void:
	var weapon := get_active_weapon()
	if weapon and not is_dead and stagger_left <= 0.0:
		weapon.modify_incoming(info)
	ability.modify_incoming(info)


func _simulate_movement(delta: float) -> void:
	var on_floor := is_on_floor()
	var yaw_basis := Basis(Vector3.UP, cmd.yaw)
	var wish := yaw_basis * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	var speed := sprint_speed if (cmd.sprint and cmd.move.y > 0.0) else walk_speed
	# Looking through binoculars: no running, and a slow walk.
	if visor.is_zoomed():
		speed = walk_speed * visor.move_mult()
	var held := get_active_weapon()
	if held:
		speed *= held.move_speed_mult()
	var staggered := stagger_left > 0.0
	if staggered:
		speed *= stagger_speed_mult
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) - _roll_vel
	_roll_vel = Vector3.ZERO
	if on_floor:
		flight.launched = false
	# Gliding: holding jump while falling with wings carries you forward.
	# Once gliding you stay gliding while you climb on your speed.
	flight.is_gliding = flight.can_glide() and cmd.jump and not on_floor and not staggered \
			and (velocity.y < 0.0 or flight.is_gliding)
	flight.is_skimming = flight.can_skim() and cmd.jump and not on_floor and not staggered \
			and not flight.overheated
	if on_floor:
		horizontal = horizontal.move_toward(wish * speed, ground_accel * delta)
	elif flight.is_skimming:
		horizontal = horizontal.move_toward(wish * flight.skim_speed, flight.skim_accel * delta)
	elif flight.is_gliding:
		horizontal = _glide_velocity(horizontal, wish, yaw_basis, delta)
	elif flight.is_hovering and flight.boost_speed > 0.0 and cmd.sprint and cmd.move.y > 0.0:
		pass  # Boosting: `_simulate_hover` flies the whole velocity.
	elif flight.is_hovering:
		horizontal = _cruise_velocity(horizontal, wish, delta)
	elif wish.length() > 0.01:
		# In the air you can steer but you keep your momentum if you let go.
		horizontal = horizontal.move_toward(wish * speed, air_accel * delta)

	_dash_cd = maxf(0.0, _dash_cd - delta)
	if cmd.dash and not on_floor and not staggered and _dash_left <= 0.0 and flight.air_dash_speed > 0.0:
		# Boots dash in the air on heat, not stamina.
		if flight.try_air_dash():
			_dash_dir = wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
			_dash_left = flight.air_dash_time
			_dash_speed_now = flight.air_dash_speed
	elif cmd.dash and _dash_cd <= 0.0 and not staggered and spend_stamina(dash_stamina):
		_dash_dir = wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
		_dash_left = dash_time
		_dash_cd = dash_cooldown
		_dash_speed_now = dash_speed
	if _dash_left > 0.0:
		_dash_left -= delta
		horizontal = _dash_dir * _dash_speed_now
		slide_left = 0.0
	horizontal = _simulate_slide(horizontal, on_floor, staggered, delta)

	horizontal += _roll_dodge(yaw_basis, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if on_floor and cmd.jump_pressed and not staggered:
		velocity.y = jump_velocity
	elif cmd.jump_pressed and not staggered and flight.is_gliding and flight.pulse_velocity > 0.0:
		# A wing pulse: up, keeping the airspeed.
		var pulse := flight.try_pulse()
		if pulse > 0.0:
			velocity.y = maxf(velocity.y, pulse)
	elif cmd.jump_pressed and not staggered:
		var burst := flight.try_burst()
		if burst > 0.0:
			velocity.y = maxf(velocity.y, burst)
			if flight.burst_push > 0.0 and wish.length() > 0.1:
				# Boots kick you the way you steer, not only up.
				var push := wish.normalized() * flight.burst_push
				var along := Vector3(velocity.x, 0.0, velocity.z).dot(wish.normalized())
				push *= clampf(1.0 - along / (flight.burst_push * 2.0), 0.0, 1.0)
				velocity.x += push.x
				velocity.z += push.z
		# A tap in the air lights a jetpack's jets and keeps them lit.
		if flight.can_hover() and not flight.overheated:
			flight.is_hovering = true
	if on_floor or staggered or not flight.can_hover() or flight.overheated:
		flight.is_hovering = false
	flight.is_boosting = flight.is_hovering and flight.boost_speed > 0.0 and cmd.sprint and cmd.move.y > 0.0
	flight.is_coasting = false
	if flight.is_hovering:
		_simulate_hover(delta)
	elif flight.is_skimming:
		_simulate_skim(delta)
	else:
		var thrust := flight.tick(cmd.jump and not on_floor and not staggered, delta)
		velocity.y += (thrust - gravity) * delta
		if thrust > 0.0:
			velocity.y = minf(velocity.y, flight.max_rise_speed)
		if flight.is_gliding:
			velocity.y = maxf(velocity.y, -_glide_sink())
			# Pulling up with speed in hand climbs on it.
			var pull := -glide_trim()
			var air_speed := Vector2(velocity.x, velocity.z).length()
			var spare := air_speed - flight.glide_speed * flight.glide_stall
			if pull > 0.0 and spare > 0.1:
				# The lift fades out as the speed comes down to the stall.
				var lift := air_speed * sin(pull * 0.7) * clampf(spare / (flight.glide_speed * 0.15), 0.0, 1.0)
				velocity.y = maxf(velocity.y, minf(lift, velocity.y + flight.glide_lift_accel * delta))
	velocity.y = maxf(velocity.y, -max_fall_speed)

	var fall_speed := -velocity.y
	if tick_every > 1:
		# One longer step: the engine moves a body by one tick of velocity.
		velocity *= tick_every
		move_and_slide()
		velocity /= tick_every
	else:
		move_and_slide()

	var now_on_floor := is_on_floor()
	airborne_time = 0.0 if now_on_floor else airborne_time + delta
	if now_on_floor and not _was_on_floor:
		_slide_landing()
		landed.emit(maxf(fall_speed, 0.0))
	_was_on_floor = now_on_floor


## Jets lit: the rig carries your weight. Jump climbs, descend sinks, and a
## boost flies you head first along the way you look.
func _simulate_hover(delta: float) -> void:
	var climb := (1.0 if cmd.jump else 0.0) - (1.0 if cmd.descend else 0.0)
	flight.is_coasting = climb < 0.0 and not flight.is_boosting
	if flight.is_boosting:
		var want := Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0)) * Vector3.FORWARD * flight.boost_speed
		want += Basis(Vector3.UP, cmd.yaw) * Vector3(cmd.move.x * flight.fly_speed * 0.5, 0.0, 0.0)
		want.y += climb * flight.descend_speed
		velocity = velocity.move_toward(want, flight.boost_accel * delta)
		flight.tick(true, delta, flight.boost_heat_mult)
		return
	var rise := flight.max_rise_speed if climb > 0.0 else climb * flight.descend_speed
	velocity.y = move_toward(velocity.y, rise, flight.hover_accel * delta)
	if flight.is_coasting:
		# Jets idle: sink, keep the speed, and cool off.
		flight.coast(delta)
		return
	var cruising := Vector2(velocity.x, velocity.z).length() > flight.fly_speed * 0.5
	flight.tick(true, delta, 1.0 if climb > 0.0 else (flight.cruise_heat_mult if cruising else flight.hover_heat_mult))


## Boots skimming: a kick rises as usual, then the boots hold your height
## (descend sinks), and the heat follows the height over what is below.
func _simulate_skim(delta: float) -> void:
	if velocity.y > 0.0 and not cmd.descend:
		velocity.y -= gravity * delta
	else:
		velocity.y = move_toward(velocity.y, -flight.descend_speed if cmd.descend else 0.0,
				flight.skim_hold_accel * delta)
	flight.skim(delta, height_above_ground(flight.skim_probe))


## How high the feet are over the world below, up to `reach` meters.
func height_above_ground(reach: float) -> float:
	if not is_inside_tree():
		return reach
	var from := global_position + Vector3(0.0, 0.1, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -reach - 0.1, 0.0), LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return reach if hit.is_empty() else maxf(0.0, global_position.y - (hit["position"] as Vector3).y)


## Jets lit: the move keys cruise you about. Slow, you go where you steer;
## at speed the heading only turns at `FlightRig.cruise_turn_rate`, and
## letting go of the keys (or pulling the other way) brakes to a stop.
func _cruise_velocity(horizontal: Vector3, wish: Vector3, delta: float) -> Vector3:
	var speed := horizontal.length()
	if wish.length() < 0.1 or speed < flight.fly_speed * 0.6:
		return horizontal.move_toward(wish * flight.fly_speed, flight.fly_accel * delta)
	var heading := horizontal / speed
	var angle := heading.signed_angle_to(wish.normalized(), Vector3.UP)
	if absf(angle) > 2.0:
		return horizontal.move_toward(Vector3.ZERO, flight.fly_accel * delta)
	var step := flight.cruise_turn_rate * delta
	heading = heading.rotated(Vector3.UP, clampf(angle, -step, step))
	return heading * move_toward(speed, wish.length() * flight.fly_speed, flight.fly_accel * delta)


## Wings: a roll key pressed while gliding snaps a sidestep that way. Returns
## the sideways velocity to add this tick.
func _roll_dodge(yaw_basis: Basis, delta: float) -> Vector3:
	_roll_cd = maxf(0.0, _roll_cd - delta)
	var pressed := cmd.roll != 0 and _last_roll != cmd.roll
	_last_roll = cmd.roll
	if pressed and flight.is_gliding and flight.roll_dodge_speed > 0.0 and _roll_cd <= 0.0:
		_roll_left = flight.roll_dodge_time
		_roll_cd = flight.roll_cooldown
		_roll_side = float(cmd.roll)
	if _roll_left <= 0.0 or not flight.is_gliding:
		_roll_left = 0.0
		return Vector3.ZERO
	_roll_left -= delta
	_roll_vel = yaw_basis * Vector3(_roll_side * flight.roll_dodge_speed, 0.0, 0.0)
	return _roll_vel


## Wings: touching down fast turns into a slide that keeps the speed.
func _slide_landing() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if flight.slide_landing_speed <= 0.0 or speed < flight.slide_landing_speed or slide_left > 0.0:
		return
	_slide_dir = Vector3(velocity.x, 0.0, velocity.z) / speed
	_slide_from = speed
	slide_left = slide_time
	_slide_cd = slide_time + slide_cooldown


## How much the air spoils aim, 0 to 1: none on the ground, riding, with
## jets lit and holding still or cruising (not boosting), skimming low on
## boots, and full otherwise.
func air_aim() -> float:
	if vehicle != null or airborne_time < 0.15:
		return 0.0
	if flight.is_hovering and not flight.is_boosting:
		return 0.0
	if flight.is_skimming and flight.skim_band() == 0:
		return 0.0
	return 1.0


## Wings spread (or just folded) stop a main gun from firing.
func wings_block(weapon: Weapon) -> bool:
	return _wing_stow > 0.0 and weapon is Gun and not (weapon as Gun).is_sidearm


## How far the glide is tipped by where you look: 1 a full dive, -1 a full flare.
func glide_trim() -> float:
	return clampf(-cmd.pitch / 0.9, -1.0, 1.0)


## Wings fly where they point: the heading turns toward where you steer (the
## move keys, or the way you face) rather than sliding there, and a dive is
## faster than a flare.
func _glide_velocity(horizontal: Vector3, wish: Vector3, yaw_basis: Basis, delta: float) -> Vector3:
	var want := wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
	var heading := horizontal.normalized() if horizontal.length() > 1.0 else want
	var angle := heading.signed_angle_to(want, Vector3.UP)
	var step := flight.glide_turn_rate * delta
	heading = heading.rotated(Vector3.UP, clampf(angle, -step, step))
	var trim := glide_trim()
	var air_speed := horizontal.length()
	var cruise := flight.glide_speed
	if air_speed < cruise * flight.glide_stall:
		# The launch: the wings bite and carry you off.
		air_speed = move_toward(air_speed, cruise * flight.glide_stall, flight.glide_accel * delta)
	elif trim > 0.0:
		var top := cruise * (1.0 + flight.glide_dive_gain * trim)
		air_speed = move_toward(air_speed, top, (flight.glide_dive_accel * trim if air_speed < top else flight.glide_drag) * delta)
		if air_speed < cruise:
			air_speed = move_toward(air_speed, cruise, flight.glide_recover * delta)
	else:
		if velocity.y > 0.0:
			# Height is paid for in speed.
			air_speed -= flight.glide_climb_cost * velocity.y / maxf(air_speed, 1.0) * delta
		var hold := cruise * lerpf(1.0, flight.glide_stall, -trim)
		air_speed = move_toward(air_speed, hold, (flight.glide_recover if air_speed < hold else flight.glide_drag) * delta)
		air_speed = maxf(air_speed, cruise * flight.glide_stall)
	return heading * air_speed


## The fastest a glide sinks right now.
func _glide_sink() -> float:
	if flight.stall_sink > 0.0 and Vector2(velocity.x, velocity.z).length() < flight.glide_speed * flight.glide_stall - 0.5:
		return flight.stall_sink
	var trim := glide_trim()
	if trim > 0.0:
		return lerpf(flight.glide_fall_speed, flight.glide_dive_fall, trim)
	return flight.glide_fall_speed


## Starts, carries on, or ends a slide, and returns the ground velocity.
func _simulate_slide(horizontal: Vector3, on_floor: bool, staggered: bool, delta: float) -> Vector3:
	_slide_cd = maxf(0.0, _slide_cd - delta)
	if cmd.slide and on_floor and slide_left <= 0.0 and _slide_cd <= 0.0 and _dash_left <= 0.0 \
			and not staggered and horizontal.length() >= slide_min_speed and spend_stamina(slide_stamina):
		_slide_dir = horizontal.normalized()
		_slide_from = maxf(horizontal.length(), slide_speed)
		slide_left = slide_time
		_slide_cd = slide_time + slide_cooldown
	if slide_left > 0.0:
		# Jumping, falling off an edge or being staggered ends it; the
		# speed carries on into whatever comes next.
		if cmd.jump_pressed or not on_floor or staggered:
			slide_left = 0.0
		else:
			slide_left = maxf(0.0, slide_left - delta)
			var done := 1.0 - slide_left / slide_time
			horizontal = _slide_dir * lerpf(_slide_from, slide_end_speed, done)
	crouch = move_toward(crouch, 1.0 if slide_left > 0.0 else 0.0, crouch_rate * delta)
	return horizontal


func is_sliding() -> bool:
	return slide_left > 0.0


func _simulate_weapons(delta: float) -> void:
	for w in weapons:
		w.tick(delta)
	if flight.glide_sidearm_only and flight.is_gliding:
		_wing_stow = flight.glide_stow_time
	else:
		_wing_stow = maxf(0.0, _wing_stow - delta)
	var switch_to := cmd.switch_weapon
	if switch_to == ActorCommand.HOLSTER:
		switch_to = -1 if active_weapon_index >= 0 else -2
	if cmd.switch_weapon != -1 and switch_to >= -1 and switch_to < weapons.size() \
			and switch_to != active_weapon_index:
		_draw_weapon(switch_to)
	var weapon := get_active_weapon()
	if weapon and heal_time_left <= 0.0 and stagger_left <= 0.0 and not weapons_locked \
			and not visor.is_zoomed():
		# Run dry with the trigger held: draw the sidearm instead of reloading.
		# That pull only draws it; the next shot comes from the sidearm.
		var gun := weapon as Gun
		if gun and not gun.is_sidearm and not gun.is_power() and cmd.primary and gun.is_empty():
			var sidearm := loaded_sidearm_index()
			if sidearm >= 0:
				_draw_weapon(sidearm)
				notice.emit("Sidearm")
				return
		if not wings_block(weapon):
			weapon.handle_input(cmd, delta)
		# A power weapon with nothing left is thrown away. The authority
		# decides; a client hears it through `power_changed`.
		if gun and gun.is_power() and gun.is_spent() and Combat.authoritative:
			notice.emit("%s spent" % gun.display_name)
			Loadout.set_power(self, "")


## Index of a sidearm with rounds in its magazine, or -1.
func loaded_sidearm_index() -> int:
	for i in weapons.size():
		var gun := weapons[i] as Gun
		if gun and gun.is_sidearm and gun.ammo_in_mag > 0:
			return i
	return -1


## Takes out the weapon at `index`, or puts the one in hand away with -1.
func _draw_weapon(index: int) -> void:
	var old := get_active_weapon()
	if old:
		old.on_holster()
		last_drawn = active_weapon_index
	active_weapon_index = index
	_refresh_weapon_visuals()


func _simulate_heal(delta: float) -> void:
	if cmd.heal_pressed and heal_time_left <= 0.0 and health.health < health.max_health:
		var item := inventory.first_with_tag("heal")
		if item != "":
			_healing_with = item
			heal_time_left = heal_duration
			notice.emit("Using %s..." % ItemDB.item_name(item))
	if heal_time_left > 0.0:
		heal_time_left -= delta
		if heal_time_left <= 0.0 and inventory.remove_item(_healing_with):
			health.heal(ItemDB.item_stats(_healing_with).get("heal", heal_amount))
			notice.emit("Healed")


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, eye_height - slide_eye_drop * crouch, 0.0)


func get_aim_dir() -> Vector3:
	if cmd.aim_dir.length_squared() > 0.0001:
		return cmd.aim_dir.normalized()
	return Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0)) * Vector3.FORWARD


## Weapon indices in key order: primary (1), sidearm (2), melee (3), then any
## power or special weapon (4). The number keys and the mouse wheel both use
## this, so the order never depends on how the loadout was equipped.
func slot_order() -> Array[int]:
	var order: Array[int] = []
	for rank in 4:
		for i in weapons.size():
			if _slot_rank(weapons[i]) == rank:
				order.append(i)
	return order


## The weapon index on number key `key` (1 to 4), or -1 if that slot is empty.
func weapon_for_key(key: int) -> int:
	var order := slot_order()
	return order[key - 1] if key >= 1 and key <= order.size() else -1


## The next (step 1) or previous (step -1) weapon index in key order, wrapping.
func cycle_weapon_index(step: int) -> int:
	var order := slot_order()
	if order.size() < 2:
		return active_weapon_index
	# Holstered: step from the weapon last drawn.
	var at := order.find(active_weapon_index if get_active_weapon() else last_drawn)
	return order[posmod(maxi(at, 0) + step, order.size())]


static func _slot_rank(w: Weapon) -> int:
	# Power weapons are guns too, but they have their own key (4).
	if w.item_id != "" and ItemDB.has_tag(w.item_id, "power"):
		return 3
	if w is Gun:
		return 1 if w.is_sidearm else 0
	if w is MeleeWeapon:
		return 2
	return 3


func get_active_weapon() -> Weapon:
	if active_weapon_index >= 0 and active_weapon_index < weapons.size():
		return weapons[active_weapon_index]
	return null


func equip_weapon(weapon: Weapon) -> void:
	weapon.actor = self
	weapons.append(weapon)
	add_child(weapon)
	weapon.visual = weapon.build_visual()
	if weapon.visual:
		hand.add_child(weapon.visual)
	_refresh_weapon_visuals()


## Puts `weapon` where the weapon at `index` was, freeing the old one. Used
## when a power weapon is swapped in or out mid-raid. Weapon indices keep
## their meaning, so switching weapons still picks the same slots.
func replace_weapon(index: int, weapon: Weapon) -> void:
	if index < 0 or index >= weapons.size():
		equip_weapon(weapon)
		return
	var old := weapons[index]
	if index == active_weapon_index:
		old.on_holster()
	if old.visual and is_instance_valid(old.visual):
		old.visual.queue_free()
	old.queue_free()
	weapon.actor = self
	weapons[index] = weapon
	add_child(weapon)
	weapon.visual = weapon.build_visual()
	if weapon.visual:
		hand.add_child(weapon.visual)
	_refresh_weapon_visuals()


## Takes out the weapon at `index` (the power slot uses this when a power
## weapon is picked up).
func draw_weapon(index: int) -> void:
	if index != active_weapon_index:
		_draw_weapon(index)


## Takes the weapon at `index` away for good (a spent power weapon). The
## active and last-drawn indices are kept pointing at the same weapons; if
## the weapon was in hand, the first weapon is drawn instead.
func remove_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return
	var old := weapons[index]
	if index == active_weapon_index:
		old.on_holster()
		active_weapon_index = 0 if weapons.size() > 1 else -1
	elif active_weapon_index > index:
		active_weapon_index -= 1
	if last_drawn == index:
		last_drawn = 0
	elif last_drawn > index:
		last_drawn -= 1
	weapons.remove_at(index)
	if old.visual and is_instance_valid(old.visual):
		old.visual.queue_free()
	old.queue_free()
	_refresh_weapon_visuals()


func _refresh_weapon_visuals() -> void:
	for i in weapons.size():
		if weapons[i].visual:
			weapons[i].visual.visible = i == active_weapon_index


func add_impulse(impulse: Vector3) -> void:
	velocity += impulse


## Returns the interactable the actor is looking at, or null.
func find_interactable() -> Interactable:
	if not is_inside_tree():
		return null
	var from := get_eye_position()
	var to := from + get_aim_dir() * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_INTERACT)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.collider as Interactable


## Everything this actor would drop on death.
func get_drop_items() -> Array[String]:
	var out: Array[String] = []
	out.append_array(gear_items)
	out.append_array(inventory.items)
	return out


func kill(kind: String, source: Node = null) -> void:
	# Nothing keeps an actor alive through this, not even an arena's yield rule.
	health.min_health = 0.0
	var info := DamageInfo.new()
	info.amount = 999999.0
	info.kind = kind
	info.source = source
	health.apply_damage(info)


func _on_health_damaged(_info: DamageInfo) -> void:
	_flash()
	if heal_time_left > 0.0:
		heal_time_left = 0.0
		notice.emit("Heal interrupted")


## A brief white flash so every hit is visible.
func _flash() -> void:
	if body_mesh == null or DisplayServer.get_name() == "headless":
		return
	if _flash_left <= 0.0:
		_base_material = body_mesh.material_override
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1)
	body_mesh.material_override = mat
	_flash_left = 0.07


func _on_health_died(info: DamageInfo) -> void:
	is_dead = true
	if _flash_left > 0.0 and body_mesh:
		body_mesh.material_override = _base_material
	collision_layer = 0
	velocity = Vector3.ZERO
	hand.visible = false
	if body_mesh:
		body_mesh.rotation.x = -PI / 2.0
		body_mesh.position.y = 0.4
	died.emit(self, info)
