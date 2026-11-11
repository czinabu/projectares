extends CharacterBody3D
## A rideable ground vehicle. The motorbike is the first one; later cars and
## mechs reuse this class with different item stats and a different model.
##
## Like the Actor, a vehicle is driven only by its rider's ActorCommand, so it
## runs the same on a headless server. It reads the rider's command before the
## rider ticks (see `process_physics_priority`), moves, and carries the rider
## along on its seat.
##
## The vehicle is the item. Its `item_id` is what goes into a stash when
## someone extracts riding it, and anyone can climb onto a vehicle nobody is
## riding, so a parked bike can be stolen.
##
## There is deliberately no `class_name` here: other scripts preload this file,
## so it works without the editor rescanning the global class list.

signal mounted(actor: Actor)
signal dismounted(actor: Actor)

## Physics layer 4, "vehicles". Bullets and the camera ignore it, so the rider
## stays exposed and the camera never snaps in against the bike.
const LAYER_VEHICLES := 8

var item_id := ""
var display_name := "Vehicle"

# Driving tuning. Item stats in ItemDB override these.
var max_speed := 24.0
## Top speed while the rider holds sprint.
var boost_speed := 32.0
var reverse_speed := 6.0
var accel := 14.0
var brake_decel := 32.0
var coast_decel := 5.0
## Turn rate in radians per second at full steer, once moving.
var turn_rate := 2.3
## Below this speed steering fades out, so the bike cannot spin in place.
var full_turn_speed := 6.0
var gravity := 20.0
var max_fall_speed := 50.0
## Where the rider sits, relative to the vehicle.
var seat_offset := Vector3(0.0, 0.35, 0.15)
## Where the rider lands when getting off, relative to the vehicle.
var exit_offset := Vector3(1.4, 0.1, 0.0)
var body_color := Color(0.85, 0.45, 0.15)

var rider: Actor
## The direction the vehicle points, in radians around up.
var heading := 0.0
## Signed speed along the heading. Negative while reversing.
var speed := 0.0
var airborne_time := 0.0

var _model: Node3D
var _lean := 0.0
var _seat: Seat


func setup(p_item_id: String) -> void:
	item_id = p_item_id
	display_name = ItemDB.item_name(p_item_id)
	var stats := ItemDB.item_stats(p_item_id)
	for key: String in stats:
		if key in self:
			set(key, stats[key])
		else:
			push_warning("Vehicle: no property '%s' for %s" % [key, p_item_id])


func _ready() -> void:
	add_to_group("vehicles")
	# After the player controller (-10) writes the command, before Actors (0) tick.
	process_physics_priority = -5
	collision_layer = LAYER_VEHICLES
	collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ACTORS
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(40.0)
	heading = rotation.y
	_build_body()


func _build_body() -> void:
	# A capsule lying along the bike rolls over kerbs and ramp lips.
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 2.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.rotation.x = PI / 2.0
	col.position.y = 0.36
	add_child(col)

	_seat = Seat.new()
	_seat.name = "Seat"
	_seat.vehicle = self
	var seat_shape := BoxShape3D.new()
	seat_shape.size = Vector3(0.9, 1.1, 2.1)
	var seat_col := CollisionShape3D.new()
	seat_col.shape = seat_shape
	seat_col.position.y = 0.55
	_seat.add_child(seat_col)
	add_child(_seat)

	_model = build_visual()
	add_child(_model)


## Greybox motorbike. Override for other vehicle types.
func build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var frame_mat := _mat(body_color)
	var dark := _mat(Color(0.08, 0.08, 0.09))
	var steel := _mat(Color(0.55, 0.55, 0.58))
	for z in [-0.75, 0.75]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.36
		wheel.bottom_radius = 0.36
		wheel.height = 0.18
		wheel.material = dark
		var node := MeshInstance3D.new()
		node.mesh = wheel
		node.rotation.z = PI / 2.0
		node.position = Vector3(0, 0.36, z)
		root.add_child(node)
	root.add_child(_part(Vector3(0.3, 0.32, 1.25), Vector3(0, 0.72, 0.05), frame_mat))  # tank and body
	root.add_child(_part(Vector3(0.34, 0.12, 0.6), Vector3(0, 0.92, 0.3), dark))        # seat
	root.add_child(_part(Vector3(0.08, 0.6, 0.08), Vector3(0, 0.8, -0.72), steel))       # fork
	root.add_child(_part(Vector3(0.8, 0.06, 0.06), Vector3(0, 1.12, -0.6), steel))       # handlebar
	var lamp_mat := _mat(Color(1.0, 0.9, 0.6))
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.5)
	root.add_child(_part(Vector3(0.2, 0.14, 0.08), Vector3(0, 0.98, -0.82), lamp_mat))  # headlight
	return root


func _part(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var node := MeshInstance3D.new()
	node.mesh = box
	node.position = at
	return node


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func get_prompt() -> String:
	if rider:
		return "%s (ridden)" % display_name
	return "[E] Ride %s" % display_name


## Puts an actor on the seat. Returns false if it is taken or they cannot ride.
func mount(actor: Actor) -> bool:
	if rider != null or actor == null or actor.is_dead or actor.vehicle != null:
		return false
	rider = actor
	actor.vehicle = self
	add_collision_exception_with(actor)
	actor.add_collision_exception_with(self)
	if not actor.died.is_connected(_on_rider_died):
		actor.died.connect(_on_rider_died)
	_place_rider()
	actor.notice.emit("Riding %s. E to get off" % display_name)
	mounted.emit(actor)
	return true


## Drops the rider beside the vehicle. They keep its momentum, so getting off
## in mid-air off a ramp is a bail-out: the flight rig takes over from there.
func dismount() -> void:
	if rider == null:
		return
	var actor := rider
	rider = null
	if not is_instance_valid(actor):
		return
	actor.vehicle = null
	if actor.died.is_connected(_on_rider_died):
		actor.died.disconnect(_on_rider_died)
	if not actor.is_dead:
		# The exit spot is clear of the bike's body, so they collide again at once.
		actor.global_position = global_position + Basis(Vector3.UP, heading) * exit_offset
		actor.velocity = velocity
	remove_collision_exception_with(actor)
	actor.remove_collision_exception_with(self)
	dismounted.emit(actor)


func _on_rider_died(_actor: Actor, _info: DamageInfo) -> void:
	dismount()


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var boosting := false
	if rider != null and (not is_instance_valid(rider) or rider.is_dead):
		dismount()
	if rider != null:
		var cmd := rider.cmd
		if cmd.interact_pressed:
			# The press is spent on getting off, not on looting.
			cmd.interact_pressed = false
			dismount()
		else:
			throttle = clampf(cmd.move.y, -1.0, 1.0)
			steer = clampf(cmd.move.x, -1.0, 1.0)
			boosting = cmd.sprint

	var on_floor := is_on_floor()
	if on_floor:
		_drive(throttle, steer, boosting, delta)
	velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	move_and_slide()

	var forward := Basis(Vector3.UP, heading) * Vector3.FORWARD
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if is_on_wall():
		# Hitting something scrubs off the speed that went into it.
		var kept := horizontal.dot(forward)
		speed = minf(speed, kept) if speed >= 0.0 else maxf(speed, kept)
	if is_on_floor():
		airborne_time = 0.0
		if not on_floor:
			# Landing: keep whatever speed still points along the bike.
			speed = horizontal.dot(forward)
	else:
		airborne_time += delta
	rotation = Vector3(0.0, heading, 0.0)
	_place_rider()
	_update_visual(steer, delta)


func _drive(throttle: float, steer: float, boosting: bool, delta: float) -> void:
	var top := boost_speed if boosting else max_speed
	if throttle > 0.05:
		var rate := brake_decel if speed < 0.0 else accel
		speed = move_toward(speed, top * throttle, rate * delta)
	elif throttle < -0.05:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, brake_decel * delta)
		else:
			speed = move_toward(speed, -reverse_speed, accel * delta)
	else:
		speed = move_toward(speed, 0.0, coast_decel * delta)

	var turn_factor := clampf(absf(speed) / full_turn_speed, 0.0, 1.0)
	heading -= steer * turn_rate * turn_factor * signf(speed) * delta
	var forward := Basis(Vector3.UP, heading) * Vector3.FORWARD
	# Follow the ground: up a ramp the bike gains upward speed, which is what
	# launches it off the top.
	var along := forward.slide(get_floor_normal()).normalized()
	velocity = along * speed


func _place_rider() -> void:
	if rider == null or not is_instance_valid(rider):
		return
	rider.global_position = global_position + Basis(Vector3.UP, heading) * seat_offset
	rider.velocity = velocity


func _update_visual(steer: float, delta: float) -> void:
	if _model == null:
		return
	var target_lean := steer * clampf(absf(speed) / max_speed, 0.0, 1.0) * 0.35
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-8.0 * delta))
	var pitch := 0.0
	if not is_on_floor():
		pitch = clampf(velocity.y * 0.03, -0.4, 0.4)
	_model.rotation = Vector3(pitch, 0.0, _lean)


## The interact target for a vehicle. It rides along on the vehicle and only
## exists on the interactables layer, so it never blocks anything.
class Seat extends Interactable:
	## The vehicle this seat belongs to (untyped: this script has no class_name).
	var vehicle

	func get_prompt() -> String:
		return vehicle.get_prompt()

	func interact(actor: Actor) -> void:
		if not vehicle.mount(actor):
			actor.notice.emit("Someone is riding it")
