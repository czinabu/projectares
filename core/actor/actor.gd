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

var _dash_left := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _slide_cd := 0.0
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


func _physics_process(delta: float) -> void:
	if is_dead:
		return
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
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	# Gliding: holding jump while falling with wings carries you forward.
	flight.is_gliding = flight.can_glide() and cmd.jump and not on_floor and velocity.y < 0.0 \
			and not staggered
	if on_floor:
		horizontal = horizontal.move_toward(wish * speed, ground_accel * delta)
	elif flight.is_gliding:
		var heading := wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
		horizontal = horizontal.move_toward(heading * flight.glide_speed, flight.glide_accel * delta)
	elif wish.length() > 0.01:
		# In the air you can steer but you keep your momentum if you let go.
		horizontal = horizontal.move_toward(wish * speed, air_accel * delta)

	_dash_cd = maxf(0.0, _dash_cd - delta)
	if cmd.dash and _dash_cd <= 0.0 and not staggered and spend_stamina(dash_stamina):
		_dash_dir = wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
		_dash_left = dash_time
		_dash_cd = dash_cooldown
	if _dash_left > 0.0:
		_dash_left -= delta
		horizontal = _dash_dir * dash_speed
		slide_left = 0.0
	horizontal = _simulate_slide(horizontal, on_floor, staggered, delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if on_floor and cmd.jump_pressed and not staggered:
		velocity.y = jump_velocity
	elif cmd.jump_pressed and not staggered:
		var burst := flight.try_burst()
		if burst > 0.0:
			velocity.y = maxf(velocity.y, burst)
	var thrust := flight.tick(cmd.jump and not on_floor and not staggered, delta)
	velocity.y += (thrust - gravity) * delta
	if thrust > 0.0:
		velocity.y = minf(velocity.y, flight.max_rise_speed)
	if flight.is_gliding:
		velocity.y = maxf(velocity.y, -flight.glide_fall_speed)
	velocity.y = maxf(velocity.y, -max_fall_speed)

	var fall_speed := -velocity.y
	move_and_slide()

	var now_on_floor := is_on_floor()
	airborne_time = 0.0 if now_on_floor else airborne_time + delta
	if now_on_floor and not _was_on_floor:
		landed.emit(maxf(fall_speed, 0.0))
	_was_on_floor = now_on_floor


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
