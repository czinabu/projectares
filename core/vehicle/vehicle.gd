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
## someone signs out riding it, and anyone can climb onto a vehicle nobody is
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
## Where the rider's feet are carried, relative to the vehicle. Low and over
## the seat, so a seated rider's head (and eyes, and headshot zone) is about
## where it shows.
var seat_offset := Vector3(0.0, 0.05, 0.28)
## Where a seated rider meets the bike, in the vehicle's frame (x right, y up,
## z back), for the skin's riding pose only: the top of the seat under the
## hips, the handlebar grips and the foot pegs, left then right.
var seat_point := Vector3(0.0, 0.98, 0.28)
var grip_points: Array[Vector3] = [Vector3(-0.22, 1.2, -0.3), Vector3(0.22, 1.2, -0.3)]
var peg_points: Array[Vector3] = [Vector3(-0.21, 0.44, 0.04), Vector3(0.21, 0.44, 0.04)]
## How far the rider leans forward from the hips, in radians.
var rider_lean := 0.8
## Where the rider lands when getting off, relative to the vehicle.
var exit_offset := Vector3(1.4, 0.1, 0.0)
var body_color := Color(0.85, 0.45, 0.15)

var rider: Actor
## The direction the vehicle points, in radians around up.
var heading := 0.0
## Signed speed along the heading. Negative while reversing.
var speed := 0.0
## Where and which way the bike stood after its last move (see `_physics_process`).
var _rest_at := Vector3.INF
var _rest_heading := 0.0
var airborne_time := 0.0

## A vehicle carried on the watch is a toy this many times smaller.
const TOY_SCALE := 0.12
## Seconds a thrown toy takes to grow into the vehicle (the look only: the
## full-size body is there from the moment it lands).
var unpack_time := 0.6
## Seconds left of growing from a toy; above zero while it unpacks.
var unpack_left := 0.0

var _model: Node3D
## How far the bike leans into a turn, in radians (positive leans right).
var lean := 0.0
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


## Greybox sci-fi motorbike: a low spine frame, a raked fairing over the tank,
## glowing hub rings and side strips, foot pegs and grips where the rider's
## pose puts hands and feet (`grip_points`, `peg_points`). Override for other
## vehicle types.
func build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var paint := _mat(body_color)
	var dark := _mat(Color(0.08, 0.08, 0.09))
	var steel := _mat(Color(0.55, 0.55, 0.58))
	# The glow is a material override, so `Look` leaves it as it is and does
	# not hang a headlight beam on every strip.
	var glow := _mat(body_color.lightened(0.35))
	glow.emission_enabled = true
	glow.emission = body_color.lightened(0.2)
	glow.emission_energy_multiplier = 1.5
	for z: float in [-0.75, 0.75]:
		var tyre := _wheel(0.36, 0.2, dark)
		tyre.position = Vector3(0, 0.36, z)
		root.add_child(tyre)
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.2
		ring_mesh.outer_radius = 0.235
		for face: float in [-1.0, 1.0]:
			var ring := MeshInstance3D.new()
			ring.mesh = ring_mesh
			ring.material_override = glow
			ring.rotation.z = PI / 2.0
			ring.position = tyre.position + Vector3(face * 0.1, 0, 0)
			root.add_child(ring)
		var hub := _wheel(0.1, 0.26, steel)
		hub.position = tyre.position
		root.add_child(hub)
	root.add_child(_part(Vector3(0.16, 0.12, 1.3), Vector3(0, 0.5, 0.0), dark, -0.12))           # spine frame
	root.add_child(_part(Vector3(0.3, 0.3, 0.42), Vector3(0, 0.5, -0.06), dark))                 # power cell
	root.add_child(_part(Vector3(0.36, 0.26, 0.56), Vector3(0, 0.82, -0.12), paint, 0.08))       # tank
	root.add_child(_part(Vector3(0.42, 0.42, 0.26), Vector3(0, 0.86, -0.5), paint, 0.5))         # fairing
	root.add_child(_part(Vector3(0.28, 0.06, 0.2), Vector3(0, 1.1, -0.52), _mat(Color(0.2, 0.25, 0.3)), 0.9))  # screen
	root.add_child(_part(Vector3(0.3, 0.1, 0.5), Vector3(0, 0.93, 0.3), dark))                   # seat
	root.add_child(_part(Vector3(0.24, 0.12, 0.42), Vector3(0, 0.98, 0.68), paint, -0.25))       # tail
	root.add_child(_part(Vector3(0.12, 0.08, 0.7), Vector3(0, 0.55, 0.45), steel, 0.35))         # swing arm
	for side: float in [-1.0, 1.0]:
		root.add_child(_part(Vector3(0.05, 0.75, 0.05), Vector3(side * 0.1, 0.71, -0.62), steel, 0.35))  # fork leg
		root.add_child(_part(Vector3(0.02, 0.05, 0.5), Vector3(side * 0.185, 0.84, -0.14), null, 0.08, glow))  # side strip
		root.add_child(_part(Vector3(0.16, 0.04, 0.06), Vector3(side * 0.2, 0.42, 0.04), steel))  # foot peg
		root.add_child(_part(Vector3(0.12, 0.05, 0.05), Vector3(side * 0.24, 1.2, -0.3), dark))   # grip
	root.add_child(_part(Vector3(0.4, 0.04, 0.04), Vector3(0, 1.2, -0.3), steel))                # handlebar
	root.add_child(_part(Vector3(0.06, 0.06, 0.26), Vector3(0, 1.13, -0.39), steel, -0.66))      # bar riser
	var lamp_mat := _mat(Color(1.0, 0.9, 0.6))
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.5)
	root.add_child(_part(Vector3(0.18, 0.08, 0.06), Vector3(0, 0.88, -0.7), lamp_mat))  # headlight
	return root


func _wheel(radius: float, width: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 24
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.rotation.z = PI / 2.0
	return node


## The vehicle `p_item_id` as a toy: its greybox model, toy-sized, under a
## node that `Look` dresses like a vehicle on show. No collision, no script.
static func toy_model(p_item_id: String) -> Node3D:
	var source = new()
	source.setup(p_item_id)
	var model: Node3D = source.build_visual()
	source.free()
	var toy := Node3D.new()
	toy.name = "Toy"
	toy.set_meta("display_item", p_item_id)
	toy.add_child(model)
	toy.scale = Vector3.ONE * TOY_SCALE
	return toy


## Starts the vehicle off toy-sized and lets it grow to full size.
func unpack() -> void:
	unpack_left = unpack_time
	_show_unpack()


func _process(delta: float) -> void:
	if unpack_left > 0.0:
		unpack_left = maxf(0.0, unpack_left - delta)
		_show_unpack()


func _show_unpack() -> void:
	if _model == null:
		return
	var grown := 1.0 - unpack_left / maxf(unpack_time, 0.01)
	# Overshoots a little near the end, so it lands with a pop.
	var size := lerpf(TOY_SCALE, 1.0, ease(grown, 0.4)) + sin(grown * PI) * 0.08
	_model.scale = Vector3.ONE * (size if unpack_left > 0.0 else 1.0)


## A box part, tipped `pitch` radians nose up about its middle. `override`
## is drawn instead of the mesh's own material (see the glow in `build_visual`).
func _part(size: Vector3, at: Vector3, mat: Material, pitch := 0.0, override: Material = null) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var node := MeshInstance3D.new()
	node.mesh = box
	node.position = at
	node.rotation.x = pitch
	node.material_override = override
	return node


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func get_prompt() -> String:
	if rider:
		return "%s (ridden)" % display_name
	return "[F] Ride %s" % display_name


## Puts an actor on the seat. Returns false if it is taken or they cannot ride.
func mount(actor: Actor) -> bool:
	if rider != null or actor == null or actor.is_dead or actor.vehicle != null or unpack_left > 0.0:
		return false
	rider = actor
	actor.vehicle = self
	add_collision_exception_with(actor)
	actor.add_collision_exception_with(self)
	if not actor.died.is_connected(_on_rider_died):
		actor.died.connect(_on_rider_died)
	_place_rider()
	actor.notice.emit("Riding %s. F to get off" % display_name)
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
		if cmd.interact_pressed and Combat.authoritative:
			# The press is spent on getting off, not on looting.
			cmd.interact_pressed = false
			dismount()
		else:
			# Online, a client predicting its own ride leaves getting off to
			# the server, and the press still has to reach it.
			throttle = clampf(cmd.move.y, -1.0, 1.0)
			steer = clampf(cmd.move.x, -1.0, 1.0)
			boosting = cmd.sprint

	# A parked bike nobody rides, standing where its last move left it, has
	# no move to make. A map has a dozen standing about, and the move is the
	# dearest part of a tick. Anything that moves, turns or pushes it wakes it.
	if rider == null and is_on_floor() and speed == 0.0 and velocity.is_zero_approx() \
			and global_position == _rest_at and heading == _rest_heading:
		_update_visual(0.0, delta)
		return
	var on_floor := is_on_floor()
	if on_floor:
		_drive(throttle, steer, boosting, delta)
	velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	# The seated rider's body overlaps the bike. The collision exception keeps
	# it out of the slide, but not out of every query the move makes (the
	# floor snap found it under Jolt), so the rider leaves the actors layer
	# for the move alone. Shots and everything else still see the rider.
	var carried := rider != null and is_instance_valid(rider)
	var rider_layer := rider.collision_layer if carried else 0
	if carried:
		rider.collision_layer = 0
	move_and_slide()
	if carried:
		rider.collision_layer = rider_layer

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
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() < 0.01 and absf(speed) < 0.01:
		# At rest: settle exactly, so the next tick can tell nothing changed.
		speed = 0.0
		velocity = Vector3.ZERO
	_rest_at = global_position
	_rest_heading = heading
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
	lean = lerpf(lean, target_lean, 1.0 - exp(-8.0 * delta))
	var pitch := 0.0
	if not is_on_floor():
		pitch = clampf(velocity.y * 0.03, -0.4, 0.4)
	# A positive lean rolls the right side down.
	_model.rotation = Vector3(pitch, 0.0, -lean)


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
