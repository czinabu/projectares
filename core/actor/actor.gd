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

const LAYER_WORLD := 1
const LAYER_ACTORS := 2
const LAYER_INTERACT := 4
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

var cmd := ActorCommand.new()
var health := HealthComponent.new()
var inventory := Inventory.new()
var flight := FlightRig.new()
var weapons: Array[Weapon] = []
var active_weapon_index := 0
## Item ids of equipped gear (weapons, rig, armor). Dropped on death.
var gear_items: Array[String] = []

var is_dead := false
var heal_time_left := 0.0
var airborne_time := 0.0
var body_mesh: MeshInstance3D
## Holds the active weapon's model. A first-person camera may pose it itself.
var hand := Node3D.new()
var hand_override := false

var _dash_left := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _was_on_floor := true


func _init() -> void:
	health.name = "Health"
	inventory.name = "Inventory"
	flight.name = "FlightRig"
	add_child(health)
	add_child(inventory)
	add_child(flight)
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
	shape.radius = 0.4
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
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
	_simulate_movement(delta)
	_simulate_weapons(delta)
	_simulate_heal(delta)
	if cmd.interact_pressed:
		var target := find_interactable()
		if target:
			target.interact(self)
	if global_position.y < -30.0:
		kill("void")


func _simulate_movement(delta: float) -> void:
	var on_floor := is_on_floor()
	var yaw_basis := Basis(Vector3.UP, cmd.yaw)
	var wish := yaw_basis * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	var speed := sprint_speed if (cmd.sprint and cmd.move.y > 0.0) else walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		horizontal = horizontal.move_toward(wish * speed, ground_accel * delta)
	elif wish.length() > 0.01:
		# In the air you can steer but you keep your momentum if you let go.
		horizontal = horizontal.move_toward(wish * speed, air_accel * delta)

	_dash_cd = maxf(0.0, _dash_cd - delta)
	if cmd.dash and _dash_cd <= 0.0:
		_dash_dir = wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
		_dash_left = dash_time
		_dash_cd = dash_cooldown
	if _dash_left > 0.0:
		_dash_left -= delta
		horizontal = _dash_dir * dash_speed

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if on_floor and cmd.jump_pressed:
		velocity.y = jump_velocity
	var thrust := flight.tick(cmd.jump and not on_floor, delta)
	velocity.y += (thrust - gravity) * delta
	if thrust > 0.0:
		velocity.y = minf(velocity.y, flight.max_rise_speed)
	velocity.y = maxf(velocity.y, -max_fall_speed)

	var fall_speed := -velocity.y
	move_and_slide()

	var now_on_floor := is_on_floor()
	airborne_time = 0.0 if now_on_floor else airborne_time + delta
	if now_on_floor and not _was_on_floor:
		landed.emit(maxf(fall_speed, 0.0))
	_was_on_floor = now_on_floor


func _simulate_weapons(delta: float) -> void:
	for w in weapons:
		w.tick(delta)
	if cmd.switch_weapon >= 0 and cmd.switch_weapon < weapons.size() \
			and cmd.switch_weapon != active_weapon_index:
		var old := get_active_weapon()
		if old:
			old.on_holster()
		active_weapon_index = cmd.switch_weapon
		_refresh_weapon_visuals()
	var weapon := get_active_weapon()
	if weapon and heal_time_left <= 0.0:
		weapon.handle_input(cmd, delta)


func _simulate_heal(delta: float) -> void:
	if cmd.heal_pressed and heal_time_left <= 0.0 and inventory.has_item("medkit") \
			and health.health < health.max_health:
		heal_time_left = heal_duration
		notice.emit("Using medkit...")
	if heal_time_left > 0.0:
		heal_time_left -= delta
		if heal_time_left <= 0.0:
			inventory.remove_item("medkit")
			health.heal(heal_amount)
			notice.emit("Healed")


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, eye_height, 0.0)


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
	var info := DamageInfo.new()
	info.amount = 999999.0
	info.kind = kind
	info.source = source
	health.apply_damage(info)


func _on_health_damaged(_info: DamageInfo) -> void:
	if heal_time_left > 0.0:
		heal_time_left = 0.0
		notice.emit("Heal interrupted")


func _on_health_died(info: DamageInfo) -> void:
	is_dead = true
	collision_layer = 0
	velocity = Vector3.ZERO
	hand.visible = false
	if body_mesh:
		body_mesh.rotation.x = -PI / 2.0
		body_mesh.position.y = 0.4
	died.emit(self, info)
