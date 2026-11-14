extends CharacterBody3D
## A rideable vehicle: the motorbike, the hoverbike, the squad rover, the mech
## and the jet are all this one class, picked by item data. The `model` stat
## picks the greybox body, and the rest is tuning: `pivot_turn` lets a walker
## turn on the spot, `jump_speed` gives it jump-jets, the "hover" tag floats
## it on a cushion of thrust (see "Hover" below), `passenger_seat` gives it a
## pillion seat behind the rider, and the "aircraft" tag flies it (`_fly`).
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
## Which greybox body to build: "bike", "hoverbike", "rover", "mech" or "jet".
var model := "bike"
## True for an item tagged "aircraft": it takes off past `takeoff_speed`.
var flies := false
## True for an item tagged "hover": it rides a cushion of thrust instead of
## wheels (see "Hover" below).
var hovers := false

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
## The steepest ground it can drive up, in degrees. Steeper is a wall.
var max_slope := 40.0
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
## How far the body leans into a turn at full speed, in radians. A bike leans
## in; a heavy body rolls a little the other way (negative).
var lean_amount := 0.35
## The collision box of anything but the bike (the bike has its capsule),
## width, height and length, standing on the ground.
var body_size := Vector3(0.7, 0.72, 2.0)
## Turn rate in radians per second at a standstill. A walker turns on the
## spot; wheels cannot (0).
var pivot_turn := 0.0
## Upward speed of a hop on jump-jets (`ActorCommand.jump_pressed`), 0 for none.
var jump_speed := 0.0
var jump_cooldown := 2.5
var _jump_wait := 0.0

# Hover, for a "hover" item only. It handles like a wheeled bike that slides:
# its course (where it is going) trails its heading (where it points) by
# `slip`, which steering opens and `grip` closes, so it drifts through turns.
# The cushion holds it level for `hang_time` after it runs off an edge at
# speed, so it crosses a gap of about speed times `hang_time`, and holds it
# down off a crest or ramp (it keeps `launch_keep` of its climb and falls at
# `downforce` times gravity while it rises), so it hugs the ground and never
# really flies.
## How fast the course swings round onto the heading, per second.
var grip := 3.5
## The widest the course may trail the heading, in radians.
var max_slip := 0.55
## Seconds of level glide off an edge, at `hang_min_speed` or faster.
var hang_time := 0.45
var hang_min_speed := 10.0
## Share of its upward speed it keeps leaving a crest or ramp lip.
var launch_keep := 0.6
## Gravity scale while it rises off a crest or ramp.
var downforce := 1.6
## True when it left the ground level (off an edge, not up a ramp): only
## then does the cushion hold it level.
var _left_level := false
## Height of the hull's underside over the ground: the cushion.
var hover_height := 0.45
## Radians the course trails the heading (positive: the course is to the left).
var slip := 0.0

# A pillion seat behind the rider (`passenger_seat`). Its anchors work like
# the rider's (`seat_offset`, `seat_point`, `grip_points`, `peg_points`,
# `rider_lean`, `exit_offset`); the passenger only sits, and may shoot.
var passenger_seat := false
var pillion_offset := Vector3(0.0, 0.17, 0.76)
var pillion_point := Vector3(0.0, 1.1, 0.76)
var pillion_grips: Array[Vector3] = [Vector3(-0.24, 1.1, 0.56), Vector3(0.24, 1.1, 0.56)]
var pillion_pegs: Array[Vector3] = [Vector3(-0.36, 0.8, 0.5), Vector3(0.36, 0.8, 0.5)]
var pillion_lean := 0.25
var pillion_exit := Vector3(-1.4, 0.1, 0.6)
## Two up it is heavier: these share of top speed, acceleration, turn rate
## and gap glide are what is left with a passenger aboard.
var laden_speed := 0.92
var laden_accel := 0.85
var laden_turn := 0.85
var laden_hang := 0.6

# Flight, for an "aircraft" only. It rolls along the ground like any vehicle
# until it is past `takeoff_speed`, then jump climbs and descend sinks. It
# cannot hover: in the air it never slows below `stall_speed` while the
# throttle is held off, and below it (off a ledge too slowly) it drops.
var takeoff_speed := 22.0
var stall_speed := 20.0
var climb_rate := 9.0
var climb_accel := 14.0
## Meters over the world's ground it can climb to.
var ceiling := 120.0
## How far the nose pitches with the climb, in radians at full climb.
var flight_pitch := 0.35
## Height over the ground below which a flier levels its wings and nose,
## fully level at the ground (`_clearance_share`). A bank or a pitch tips
## the wingtips and tail about this far.
var level_height := 3.0

## Clear ground it needs to unpack from a toy, width, height and length
## (`Raid.has_room_to_unpack`).
var footprint := Vector3(1.3, 1.2, 2.6)
## Seconds the watch takes to recharge after this one is thrown. Heavier
## vehicles take longer (DESIGN.md section 8).
var watch_recharge := 8.0
## How small it parks in the home base's garage bay, which is bike-sized.
var bay_scale := 1.0

## The walker's stride, in radians, read by the legs (`_animate_legs`).
var stride_phase := 0.0
var _legs: Array[Node3D] = []
## Height of a walker's hip joints over the ground.
const LEG_HIP := 1.75
## The steer this tick, for a walker's shuffle on the spot.
var _turning := 0.0

var rider: Actor
## Whoever sits on the pillion seat, or null.
var passenger: Actor
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
## True for a vehicle with no server over it (one unpacked in the home
## base): getting off is decided here even on a client.
var local_only := false

var _model: Node3D
## How far the bike leans into a turn, in radians (positive leans right).
var lean := 0.0
var _seat: Seat
## The pillion seat's anchors, riding on the model (`ride_anchor`).
var _pillion: Pillion
## Seconds of hover bob, for the look only.
var _bob_time := 0.0


func setup(p_item_id: String) -> void:
	item_id = p_item_id
	display_name = ItemDB.item_name(p_item_id)
	flies = ItemDB.has_tag(p_item_id, "aircraft")
	hovers = ItemDB.has_tag(p_item_id, "hover")
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
	floor_max_angle = deg_to_rad(max_slope)
	heading = rotation.y
	_build_body()


func _build_body() -> void:
	var col := CollisionShape3D.new()
	var seat_shape := BoxShape3D.new()
	var seat_col := CollisionShape3D.new()
	if model == "hoverbike":
		# The cushion: a fat capsule under the hull, its underside on the
		# ground, so the hull floats `hover_height` up and rough ground and
		# kerbs pass under it.
		var cushion := CapsuleShape3D.new()
		cushion.radius = hover_height
		cushion.height = 2.3
		col.shape = cushion
		col.rotation.x = PI / 2.0
		col.position.y = hover_height
		seat_shape.size = Vector3(0.9, 1.2, 2.4)
		seat_col.position.y = 0.7
	elif model == "bike":
		# A capsule lying along the bike rolls over kerbs and ramp lips.
		var shape := CapsuleShape3D.new()
		shape.radius = 0.35
		shape.height = 2.0
		col.shape = shape
		col.rotation.x = PI / 2.0
		col.position.y = 0.36
		seat_shape.size = Vector3(0.9, 1.1, 2.1)
		seat_col.position.y = 0.55
	else:
		# A box over a capsule lying along the body: the capsule's round ends
		# roll it over kerbs and ramp lips, and its underside is the ground
		# line the model stands on (wheels and feet reach down to y = 0).
		var lift := minf(0.3, body_size.y * 0.25)
		var shape := BoxShape3D.new()
		shape.size = Vector3(body_size.x, body_size.y - lift, body_size.z)
		col.shape = shape
		col.position.y = lift + (body_size.y - lift) * 0.5
		var keel_shape := CapsuleShape3D.new()
		keel_shape.radius = lift
		keel_shape.height = maxf(body_size.z, lift * 2.0)
		var keel := CollisionShape3D.new()
		keel.name = "Keel"
		keel.shape = keel_shape
		keel.rotation.x = PI / 2.0
		keel.position.y = lift
		add_child(keel)
		seat_shape.size = body_size + Vector3(0.2, 0.2, 0.2)
		seat_col.position.y = body_size.y * 0.5
	add_child(col)

	_seat = Seat.new()
	_seat.name = "Seat"
	_seat.vehicle = self
	seat_col.shape = seat_shape
	_seat.add_child(seat_col)
	add_child(_seat)

	_model = build_visual()
	add_child(_model)
	if passenger_seat:
		# On the model, so the pillion rider tips with the lean like the rider.
		_pillion = Pillion.new()
		_pillion.name = "Pillion"
		_pillion.vehicle = self
		_model.add_child(_pillion)


## The greybox body for `model`. Each puts grips and pegs where the rider's
## pose puts hands and feet (`grip_points`, `peg_points`).
func build_visual() -> Node3D:
	match model:
		"rover":
			return _build_rover()
		"mech":
			return _build_mech()
		"jet":
			return _build_jet()
		"hoverbike":
			return _build_hoverbike()
	return _build_bike()


## Greybox sci-fi motorbike: a low spine frame, a raked fairing over the tank,
## glowing hub rings and side strips, foot pegs and grips.
func _build_bike() -> Node3D:
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


## Greybox hoverbike: a long, low hull on four downward thruster pods with
## glowing discs, so it floats on its cushion (`hover_height`) with daylight
## under it. A raked nose with a low screen, bars over it, a stepped two-up
## seat with grab rails for a pillion rider, side skirts with glow strips and
## a glowing rear thruster. No wheels anywhere.
func _build_hoverbike() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := _palette()
	var thrust := _mat(Color(0.5, 0.9, 1.0))
	thrust.emission_enabled = true
	thrust.emission = Color(0.35, 0.85, 1.0)
	thrust.emission_energy_multiplier = 2.5
	var base := hover_height
	for z: float in [-0.72, 0.68]:
		for x: float in [-0.27, 0.27]:
			var pod := _wheel(0.2, 0.1, c.dark)
			pod.rotation = Vector3.ZERO  # standing up: a pod pointing down
			pod.position = Vector3(x, base + 0.08, z)
			root.add_child(pod)
			var disc_mesh := CylinderMesh.new()
			disc_mesh.top_radius = 0.17
			disc_mesh.bottom_radius = 0.17
			disc_mesh.height = 0.03
			disc_mesh.radial_segments = 20
			var disc := MeshInstance3D.new()
			disc.name = "Thruster%d" % root.get_child_count()
			disc.mesh = disc_mesh
			disc.material_override = thrust
			disc.position = Vector3(x, base + 0.015, z)
			root.add_child(disc)
		root.add_child(_part(Vector3(0.66, 0.08, 0.3), Vector3(0, base + 0.17, z), c.steel))         # pod beam
	root.add_child(_part(Vector3(0.5, 0.3, 1.6), Vector3(0, base + 0.42, 0.0), c.paint))              # hull
	root.add_child(_part(Vector3(0.44, 0.24, 0.5), Vector3(0, base + 0.44, -0.95), c.paint, 0.3))     # nose cowl
	root.add_child(_part(Vector3(0.3, 0.12, 0.36), Vector3(0, base + 0.32, -1.22), c.dark, 0.15))     # nose tip
	root.add_child(_part(Vector3(0.36, 0.16, 0.42), Vector3(0, base + 0.62, -0.36), c.paint, 0.12))   # tank
	var screen := _part(Vector3(0.34, 0.04, 0.28), Vector3(0, base + 0.8, -0.66), null, 0.95, _clear_glass())
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(screen)
	root.add_child(_part(Vector3(0.3, 0.1, 0.5), Vector3(0, base + 0.53, 0.2), c.dark))               # rider's seat
	root.add_child(_part(Vector3(0.32, 0.12, 0.4), Vector3(0, base + 0.59, 0.74), c.dark))            # pillion seat
	root.add_child(_part(Vector3(0.36, 0.26, 0.42), Vector3(0, base + 0.4, 0.98), c.paint, -0.2))     # tail
	root.add_child(_part(Vector3(0.3, 0.14, 0.05), Vector3(0, base + 0.42, 1.2), null, 0.0, thrust))  # rear thruster
	root.add_child(_part(Vector3(0.6, 0.04, 0.04), Vector3(0, 1.3, -0.42), c.steel))                  # handlebar
	root.add_child(_part(Vector3(0.06, 0.06, 0.34), Vector3(0, 1.17, -0.52), c.steel, -0.9))          # bar riser
	for side: float in [-1.0, 1.0]:
		root.add_child(_part(Vector3(0.04, 0.16, 1.7), Vector3(side * 0.28, base + 0.24, 0.0), c.paint))  # skirt
		root.add_child(_part(Vector3(0.02, 0.04, 1.3), Vector3(side * 0.3, base + 0.34, -0.05), null, 0.0, c.glow))  # strip
		root.add_child(_part(Vector3(0.12, 0.05, 0.05), Vector3(side * 0.3, 1.3, -0.42), c.dark))    # grip
		root.add_child(_part(Vector3(0.14, 0.04, 0.1), Vector3(side * 0.36, 0.72, -0.04), c.steel))  # rider's peg
		root.add_child(_part(Vector3(0.12, 0.04, 0.1), Vector3(side * 0.36, 0.78, 0.5), c.steel))    # pillion peg
		root.add_child(_part(Vector3(0.04, 0.04, 0.32), Vector3(side * 0.24, 1.08, 0.64), c.steel))  # grab rail
		root.add_child(_part(Vector3(0.04, 0.12, 0.04), Vector3(side * 0.24, 1.02, 0.8), c.steel))   # its post
		root.add_child(_part(Vector3(0.1, 0.06, 0.04), Vector3(side * 0.16, base + 0.36, -1.38), c.lamp))  # headlight
	return root


## The materials every greybox body shares: paint, dark, steel, a glow that
## `Look` leaves alone (an override), and a lamp it hangs a beam on.
func _palette() -> Dictionary:
	var glow := _mat(body_color.lightened(0.35))
	glow.emission_enabled = true
	glow.emission = body_color.lightened(0.2)
	glow.emission_energy_multiplier = 1.5
	var lamp := _mat(Color(1.0, 0.9, 0.6))
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.5)
	return {"paint": _mat(body_color), "dark": _mat(Color(0.08, 0.08, 0.09)),
			"steel": _mat(Color(0.55, 0.55, 0.58)), "glow": glow, "lamp": lamp,
			"glass": _mat(Color(0.2, 0.25, 0.3))}


## Greybox armored squad rover: an open-topped scout buggy on four big
## wheels with glowing hubs. A sloped hood runs down to a bumper and twin
## lamps; the cab is open over low door sills, so the crew shows from
## outside, behind a see-through windscreen (`_clear_glass`) that starts at
## the dash, under the driver's eye line. Low bucket seats (driver on the
## left, at the wheel), a roll bar over them, and a low cargo tray at the
## back with tail lamps and a whip antenna.
func _build_rover() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := _palette()
	var tail := _mat(Color(0.9, 0.15, 0.1))
	tail.emission_enabled = true
	tail.emission = Color(1.0, 0.1, 0.05)
	tail.emission_energy_multiplier = 2.0
	var screen := _mat(Color(0.35, 0.9, 1.0))
	screen.emission_enabled = true
	screen.emission = Color(0.3, 0.85, 1.0)
	screen.emission_energy_multiplier = 1.2
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.3
	ring_mesh.outer_radius = 0.34
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.35, 1.35]:
			var tyre := _wheel(0.52, 0.4, c.dark)
			tyre.position = Vector3(x * 1.0, 0.52, z)
			root.add_child(tyre)
			var hub := _wheel(0.22, 0.44, c.steel)
			hub.position = tyre.position
			root.add_child(hub)
			var ring := MeshInstance3D.new()
			ring.mesh = ring_mesh
			ring.material_override = c.glow
			ring.rotation.z = PI / 2.0
			ring.position = tyre.position + Vector3(x * 0.21, 0, 0)
			root.add_child(ring)
			# A wheel arch: a flat top with its ends angled down fore and aft.
			root.add_child(_part(Vector3(0.58, 0.07, 0.8), Vector3(x * 1.0, 1.12, z), c.paint))
			root.add_child(_part(Vector3(0.58, 0.07, 0.42), Vector3(x * 1.0, 1.02, z - 0.55), c.paint, -0.55))
			root.add_child(_part(Vector3(0.58, 0.07, 0.42), Vector3(x * 1.0, 1.02, z + 0.55), c.paint, 0.55))
		root.add_child(_part(Vector3(0.12, 0.42, 1.55), Vector3(x * 0.86, 0.97, 0.0), c.paint))       # door sill
		root.add_child(_part(Vector3(0.03, 0.06, 1.3), Vector3(x * 0.93, 1.02, 0.0), null, 0.0, c.glow))  # strip
		root.add_child(_part(Vector3(0.22, 0.05, 1.0), Vector3(x * 0.98, 0.64, 0.0), c.steel))        # side step
		root.add_child(_part(Vector3(0.22, 0.08, 0.04), Vector3(x * 0.6, 1.0, -2.13), c.lamp))        # headlight
		root.add_child(_part(Vector3(0.2, 0.08, 0.03), Vector3(x * 0.68, 1.0, 2.13), null, 0.0, tail))  # tail lamp
		# The windscreen's frame and the roll bar behind the seats, joined by a rail.
		root.add_child(_part(Vector3(0.06, 0.66, 0.06), Vector3(x * 0.8, 1.63, -0.64), c.steel, 0.25))  # pillar
		root.add_child(_part(Vector3(0.07, 0.95, 0.07), Vector3(x * 0.8, 1.6, 0.78), c.steel))         # roll bar
		root.add_child(_part(Vector3(0.06, 0.06, 1.36), Vector3(x * 0.8, 2.0, 0.1), c.steel, -0.11))    # roof rail
		root.add_child(_part(Vector3(0.06, 0.22, 1.2), Vector3(x * 0.82, 1.22, 1.55), c.paint))         # tray side
	root.add_child(_part(Vector3(1.5, 0.3, 3.8), Vector3(0, 0.62, 0), c.dark))                  # chassis
	root.add_child(_part(Vector3(1.6, 0.06, 1.9), Vector3(0, 0.82, 0.05), c.dark))              # cab floor
	# The hood, sloping down to the nose, over the engine bay.
	root.add_child(_part(Vector3(1.6, 0.38, 1.3), Vector3(0, 0.9, -1.45), c.paint))
	root.add_child(_part(Vector3(1.62, 0.08, 1.42), Vector3(0, 1.12, -1.42), c.paint, -0.12))
	root.add_child(_part(Vector3(0.5, 0.05, 0.7), Vector3(0, 1.18, -1.3), c.dark, -0.12))      # hood vent
	root.add_child(_part(Vector3(1.4, 0.24, 0.06), Vector3(0, 0.82, -2.12), c.dark))            # grille
	root.add_child(_part(Vector3(1.9, 0.12, 0.14), Vector3(0, 0.62, -2.2), c.steel))            # bumper
	# The dash: a low cowl under the windscreen, with the driver's screens lit.
	root.add_child(_part(Vector3(1.62, 0.2, 0.34), Vector3(0, 1.21, -0.62), c.dark))
	root.add_child(_part(Vector3(0.3, 0.13, 0.02), Vector3(-0.4, 1.36, -0.55), null, -0.5, screen))
	root.add_child(_part(Vector3(0.22, 0.1, 0.02), Vector3(0.35, 1.35, -0.55), null, -0.5, screen))
	root.add_child(_part(Vector3(1.66, 0.06, 0.06), Vector3(0, 1.32, -0.73), c.steel))          # screen foot
	root.add_child(_part(Vector3(1.66, 0.06, 0.06), Vector3(0, 1.94, -0.56), c.steel))          # screen top
	var glass := _part(Vector3(1.54, 0.62, 0.02), Vector3(0, 1.63, -0.64), null, 0.25, _clear_glass())
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	root.add_child(_part(Vector3(1.66, 0.07, 0.07), Vector3(0, 2.08, 0.78), c.steel))           # roll bar top
	# Low bucket seats, so the crew's shoulders and heads show over them.
	for x: float in [-0.4, 0.4]:
		root.add_child(_part(Vector3(0.48, 0.1, 0.48), Vector3(x, 0.9, 0.25), c.dark))        # seat
		root.add_child(_part(Vector3(0.46, 0.42, 0.08), Vector3(x, 1.14, 0.52), c.dark, 0.15))  # seat back
		for side: float in [-1.0, 1.0]:
			root.add_child(_part(Vector3(0.05, 0.12, 0.4), Vector3(x + side * 0.24, 0.98, 0.28), c.dark))  # bolster
	# The wheel faces the driver, its rim through the grips (`grip_points`).
	var wheel := MeshInstance3D.new()
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.16
	wheel_mesh.outer_radius = 0.2
	wheel_mesh.material = c.dark
	wheel.mesh = wheel_mesh
	wheel.position = Vector3(-0.4, 1.27, -0.25)
	wheel.rotation.x = PI / 2.0 - 0.45
	root.add_child(wheel)
	root.add_child(_part(Vector3(0.05, 0.05, 0.4), Vector3(-0.4, 1.2, -0.45), c.steel, 0.45))  # column
	for x: float in [-0.52, -0.28]:
		root.add_child(_part(Vector3(0.1, 0.04, 0.16), Vector3(x, 0.86, -0.5), c.steel))       # pedal
	# The back: a body under a low cargo tray, a bumper and a whip antenna.
	root.add_child(_part(Vector3(1.6, 0.34, 0.9), Vector3(0, 0.9, 1.68), c.paint))
	root.add_child(_part(Vector3(1.7, 0.1, 1.3), Vector3(0, 1.1, 1.55), c.paint))               # tray floor
	root.add_child(_part(Vector3(1.7, 0.22, 0.06), Vector3(0, 1.22, 2.17), c.paint))            # tailgate
	root.add_child(_part(Vector3(0.55, 0.3, 0.42), Vector3(0.38, 1.3, 1.45), c.steel))          # crate
	root.add_child(_part(Vector3(0.4, 0.22, 0.36), Vector3(-0.3, 1.26, 1.7), c.dark))           # crate
	root.add_child(_part(Vector3(1.8, 0.18, 0.16), Vector3(0, 0.72, 2.15), c.dark))             # rear bumper
	root.add_child(_part(Vector3(0.02, 1.1, 0.02), Vector3(0.78, 1.75, 2.05), c.steel, 0.12))  # antenna
	return root


## Tinted glass you can see through. It is a material override, so `Look`
## leaves it as it is instead of weathering it opaque.
func _clear_glass() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.78, 0.9, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = 0.4
	mat.roughness = 0.05
	return mat


## Greybox compact mech: a cockpit pod with twin cannons on its flanks and a
## glowing power unit on its back (its weak spot, by design), on two
## jointed legs that stride with its speed (`_animate_legs`).
func _build_mech() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := _palette()
	_legs.clear()
	for x: float in [-0.62, 0.62]:
		var leg := Node3D.new()
		leg.name = "LegL" if x < 0.0 else "LegR"
		leg.position = Vector3(x, LEG_HIP, 0.1)
		leg.add_child(_part(Vector3(0.36, 0.95, 0.42), Vector3(0, -0.42, -0.12), c.paint, 0.25))  # thigh
		leg.add_child(_part(Vector3(0.3, 0.3, 0.3), Vector3(0, -0.86, -0.22), c.steel))            # knee
		leg.add_child(_part(Vector3(0.28, 0.9, 0.32), Vector3(0, -1.2, -0.08), c.dark, -0.3))      # shin
		leg.add_child(_part(Vector3(0.5, 0.14, 0.8), Vector3(0, -1.68, -0.05), c.dark))            # foot
		leg.add_child(_part(Vector3(0.04, 0.5, 0.04), Vector3(x * 0.3, -0.42, 0.05), null, 0.25, c.glow))
		root.add_child(leg)
		_legs.append(leg)
	root.add_child(_part(Vector3(1.1, 0.4, 0.9), Vector3(0, 1.8, 0.1), c.steel))               # hip block
	root.add_child(_part(Vector3(1.4, 0.3, 1.5), Vector3(0, 2.12, 0.05), c.paint))              # pod floor
	# An open cockpit: low armor round the pilot, who sits exposed from the chest up.
	root.add_child(_part(Vector3(1.4, 0.6, 0.12), Vector3(0, 2.45, -0.75), c.paint, -0.3))      # front armor
	root.add_child(_part(Vector3(0.12, 0.36, 1.4), Vector3(-0.72, 2.4, 0.05), c.paint))         # pod side L
	root.add_child(_part(Vector3(0.12, 0.36, 1.4), Vector3(0.72, 2.4, 0.05), c.paint))          # pod side R
	root.add_child(_part(Vector3(1.0, 0.2, 0.04), Vector3(0, 2.82, -0.86), c.glass, 0.5))       # screen
	root.add_child(_part(Vector3(0.45, 0.12, 0.45), Vector3(0, 2.24, 0.15), c.dark))            # seat
	root.add_child(_part(Vector3(0.45, 0.6, 0.1), Vector3(0, 2.55, 0.42), c.dark, -0.15))       # seat back
	root.add_child(_part(Vector3(1.0, 0.9, 0.5), Vector3(0, 2.55, 0.75), c.dark))               # power unit
	root.add_child(_part(Vector3(0.7, 0.5, 0.06), Vector3(0, 2.6, 1.02), null, 0.0, c.glow))    # its glow
	for x: float in [-1.0, 1.0]:
		root.add_child(_part(Vector3(0.3, 0.3, 0.6), Vector3(x * 0.95, 2.45, 0.0), c.dark))     # cannon mount
		root.add_child(_part(Vector3(0.14, 0.14, 1.3), Vector3(x * 0.95, 2.45, -0.85), c.steel))  # barrel
		root.add_child(_part(Vector3(0.06, 0.4, 0.06), Vector3(x * 0.25, 2.3, -0.38), c.steel, 0.2))  # stick
		root.add_child(_part(Vector3(0.18, 0.05, 0.25), Vector3(x * 0.16, 2.05, -0.5), c.steel))  # pedal
		root.add_child(_part(Vector3(0.25, 0.2, 0.25), Vector3(x * 0.5, 2.1, 0.7), null, 0.0, c.glow))  # jump-jet
	root.add_child(_part(Vector3(0.3, 0.1, 0.06), Vector3(0, 2.2, -0.82), c.lamp))              # lamp
	return root


## Greybox starfighter: a long fuselage with a bubble canopy over the pilot,
## swept wings, twin tail fins, glowing engines and short landing gear.
func _build_jet() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := _palette()
	root.add_child(_part(Vector3(1.1, 0.8, 5.2), Vector3(0, 1.0, 0.3), c.paint))               # fuselage
	root.add_child(_part(Vector3(0.7, 0.55, 1.4), Vector3(0, 0.95, -2.8), c.paint, 0.12))      # nose
	root.add_child(_part(Vector3(0.75, 0.04, 1.5), Vector3(0, 1.62, -0.9), c.glass, 0.12))     # canopy glass
	root.add_child(_part(Vector3(0.05, 0.4, 1.4), Vector3(-0.38, 1.45, -0.9), c.glass))
	root.add_child(_part(Vector3(0.05, 0.4, 1.4), Vector3(0.38, 1.45, -0.9), c.glass))
	root.add_child(_part(Vector3(0.5, 0.12, 0.5), Vector3(0, 1.24, -0.55), c.dark))            # seat
	root.add_child(_part(Vector3(0.5, 0.7, 0.1), Vector3(0, 1.6, -0.25), c.dark, -0.25))       # seat back
	for x: float in [-1.0, 1.0]:
		var wing := _part(Vector3(2.0, 0.1, 1.6), Vector3(x * 1.5, 0.95, 0.8), c.paint)
		wing.rotation.y = x * 0.35
		root.add_child(wing)
		root.add_child(_part(Vector3(0.08, 0.04, 1.2), Vector3(x * 2.45, 0.98, 1.3), null, 0.0, c.glow))  # wingtip
		var fin := _part(Vector3(0.08, 0.9, 0.9), Vector3(x * 0.4, 1.7, 2.4), c.paint, -0.4)
		fin.rotation.z = x * 0.25
		root.add_child(fin)
		root.add_child(_part(Vector3(0.42, 0.42, 0.3), Vector3(x * 0.3, 1.0, 3.0), null, 0.0, c.glow))  # engine
		root.add_child(_part(Vector3(0.06, 0.06, 0.3), Vector3(x * 0.22, 1.32, -1.15), c.steel, 0.4))  # stick
		root.add_child(_part(Vector3(0.18, 0.05, 0.25), Vector3(x * 0.15, 0.84, -1.6), c.steel))  # pedal
		root.add_child(_part(Vector3(0.08, 0.5, 0.08), Vector3(x * 0.9, 0.35, 1.0), c.steel))   # main gear
		var tyre := _wheel(0.18, 0.14, c.dark)
		tyre.position = Vector3(x * 0.9, 0.18, 1.0)
		root.add_child(tyre)
	root.add_child(_part(Vector3(0.08, 0.5, 0.08), Vector3(0, 0.35, -2.4), c.steel))            # nose gear
	var nose_tyre := _wheel(0.15, 0.12, c.dark)
	nose_tyre.position = Vector3(0, 0.15, -2.4)
	root.add_child(nose_tyre)
	root.add_child(_part(Vector3(0.2, 0.08, 0.06), Vector3(0, 0.85, -3.5), c.lamp))             # lamp
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


## Seconds a thrown toy takes to turn its one flip in the air. After it the
## toy flies level, facing the way it will unpack, so the vehicle grows out
## of it without a jump (`toy_flight_basis`).
const TOY_FLIP_TIME := 0.45


## How a thrown toy is turned `age` seconds into its flight, thrown facing
## `heading`: one forward flip that slows as it comes round, then level,
## facing `heading`, the way the vehicle unpacks.
static func toy_flight_basis(heading: float, age: float) -> Basis:
	var flip := TAU * ease(clampf(age / TOY_FLIP_TIME, 0.0, 1.0), 0.6)
	return Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, -flip)


## Starts the vehicle off toy-sized and lets it grow to full size, with a
## ring of light on the ground and a thump where it lands.
func unpack() -> void:
	unpack_left = unpack_time
	_show_unpack()
	if is_inside_tree():
		Fx.ring(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), body_size.z * 0.6, Color(0.35, 0.95, 1.0), 0.5)
		Sfx.play("slam", global_position, -8.0)


func _process(delta: float) -> void:
	if unpack_left > 0.0:
		unpack_left = maxf(0.0, unpack_left - delta)
		_show_unpack()
	if not _legs.is_empty():
		_animate_legs(delta)
	if hovers and _model != null:
		_animate_hover(delta)


## A hover bobs gently on its cushion and its thrusters burn brighter with
## speed (view only, from `speed`, which a client keeps for every vehicle).
func _animate_hover(delta: float) -> void:
	_bob_time = fmod(_bob_time + delta, TAU * 10.0)
	var pace := clampf(absf(speed) / maxf(max_speed, 0.1), 0.0, 1.0)
	_model.position.y = sin(_bob_time * 2.4) * 0.035 * (1.0 - 0.6 * pace)
	for node in _model.get_children():
		if node.name.begins_with("Thruster"):
			var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 2.0 + 2.5 * pace + 0.3 * sin(_bob_time * 17.0)
			break


## Swings a walker's legs with its speed (view only, and from `speed`, which
## a client keeps for vehicles it does not simulate). A turn on the spot
## shuffles them too; in the air they hang.
func _animate_legs(delta: float) -> void:
	var pace := absf(speed)
	if pace < 0.3 and absf(_turning) > 0.05:
		pace = 2.0
	stride_phase = wrapf(stride_phase + pace * delta * 1.6, 0.0, TAU)
	var swing := 0.45 * clampf(pace / 4.0, 0.0, 1.0)
	for i in _legs.size():
		var leg := _legs[i]
		var want := sin(stride_phase + PI * i) * swing
		if airborne_time > 0.1:
			want = -0.25
		leg.rotation.x = lerpf(leg.rotation.x, want, 1.0 - exp(-10.0 * delta))
		# A swung leg is lifted at the hip, so its foot steps over the ground
		# instead of sweeping through it.
		leg.position.y = LEG_HIP + absf(sin(leg.rotation.x)) * 0.45


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
	if rider == null:
		return "[F] Ride %s" % display_name
	if passenger_seat and passenger == null:
		return "[F] Ride behind on %s" % display_name
	return "%s (ridden)" % display_name


## True with anyone aboard, rider or passenger.
func is_occupied() -> bool:
	return rider != null or passenger != null


## Puts an actor on the seat, or with `behind` on the pillion seat. Returns
## false if that seat is taken or they cannot ride.
func mount(actor: Actor, behind := false) -> bool:
	if actor == null or actor.is_dead or actor.vehicle != null or unpack_left > 0.0:
		return false
	if not behind and rider == null:
		rider = actor
	elif behind and passenger_seat and passenger == null:
		passenger = actor
	else:
		return false
	actor.vehicle = self
	add_collision_exception_with(actor)
	actor.add_collision_exception_with(self)
	if not actor.died.is_connected(_on_rider_died):
		actor.died.connect(_on_rider_died)
	_place_rider()
	if actor == passenger:
		actor.notice.emit("Riding behind on %s. F to get off" % display_name)
	else:
		actor.notice.emit("Riding %s. F to get off" % display_name)
	mounted.emit(actor)
	return true


## Drops the rider beside the vehicle. They keep its momentum, so getting off
## in mid-air off a ramp is a bail-out: the flight rig takes over from there.
## A passenger stays aboard.
func dismount() -> void:
	if rider != null:
		_let_off(rider)


## Drops the passenger off the pillion seat.
func dismount_passenger() -> void:
	if passenger != null:
		_let_off(passenger)


## Everyone off.
func dismount_all() -> void:
	dismount()
	dismount_passenger()


## Lets `actor` off, whichever seat they are on.
func get_off(actor: Actor) -> void:
	if actor != null and (actor == rider or actor == passenger):
		_let_off(actor)


func _let_off(actor: Actor) -> void:
	var behind := actor == passenger
	if behind:
		passenger = null
	else:
		rider = null
	if not is_instance_valid(actor):
		return
	actor.vehicle = null
	if actor.died.is_connected(_on_rider_died):
		actor.died.disconnect(_on_rider_died)
	if not actor.is_dead:
		# The exit spot is clear of the bike's body, so they collide again at once.
		actor.global_position = global_position + Basis(Vector3.UP, heading) * (pillion_exit if behind else exit_offset)
		actor.velocity = velocity
	remove_collision_exception_with(actor)
	actor.remove_collision_exception_with(self)
	dismounted.emit(actor)


func _on_rider_died(actor: Actor, _info: DamageInfo) -> void:
	if actor == passenger:
		dismount_passenger()
	else:
		dismount()


## What a seated actor's pose is fitted to: the vehicle itself for the rider,
## the pillion seat's anchors (on the model) for a passenger.
func ride_anchor(actor: Actor) -> Node3D:
	if actor != null and actor == passenger and _pillion != null:
		return _pillion
	return self


## Share of a stat left with a passenger aboard (1 when ridden alone).
func _laden(share: float) -> float:
	return share if passenger != null else 1.0


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var boosting := false
	var lift := 0.0
	var hop := false
	_jump_wait = maxf(0.0, _jump_wait - delta)
	if rider != null and (not is_instance_valid(rider) or rider.is_dead):
		dismount()
	if passenger != null and (not is_instance_valid(passenger) or passenger.is_dead):
		dismount_passenger()
	if passenger != null and passenger.cmd.interact_pressed and (Combat.authoritative or local_only):
		passenger.cmd.interact_pressed = false
		dismount_passenger()
	if rider != null:
		var cmd := rider.cmd
		if cmd.interact_pressed and (Combat.authoritative or local_only):
			# The press is spent on getting off, not on looting.
			cmd.interact_pressed = false
			dismount()
		else:
			# Online, a client predicting its own ride leaves getting off to
			# the server, and the press still has to reach it.
			throttle = clampf(cmd.move.y, -1.0, 1.0)
			steer = clampf(cmd.move.x, -1.0, 1.0)
			boosting = cmd.sprint
			lift = (1.0 if cmd.jump else 0.0) - (1.0 if cmd.descend else 0.0)
			hop = cmd.jump_pressed

	# A parked bike nobody rides, standing where its last move left it, has
	# no move to make. A map has a dozen standing about, and the move is the
	# dearest part of a tick. Anything that moves, turns or pushes it wakes it.
	if rider == null and is_on_floor() and speed == 0.0 and velocity.is_zero_approx() and slip == 0.0 \
			and global_position == _rest_at and heading == _rest_heading:
		_update_visual(0.0, delta)
		return
	var on_floor := is_on_floor()
	_turning = steer
	# A flier is flying once it is off the ground with someone at the stick,
	# or rolling fast enough to lift off and asked to climb. Nobody aboard, it
	# drops like anything else.
	var flying := flies and rider != null and (not on_floor or (lift > 0.0 and speed >= takeoff_speed))
	if flying:
		_fly(throttle, steer, boosting, lift, delta)
	else:
		if on_floor:
			_drive(throttle, steer, boosting, delta)
			if hop and jump_speed > 0.0 and _jump_wait <= 0.0:
				# Jump-jets: a hop that keeps the stride's speed.
				velocity.y = jump_speed
				_jump_wait = jump_cooldown
		velocity.y = maxf(velocity.y - gravity * _gravity_share(on_floor) * delta, -max_fall_speed)
		if _hanging(on_floor):
			# The cushion still holds it level off the edge.
			velocity.y = maxf(velocity.y, 0.0)
	# The seated rider's body overlaps the bike. The collision exception keeps
	# it out of the slide, but not out of every query the move makes (the
	# floor snap found it under Jolt), so the rider leaves the actors layer
	# for the move alone. Shots and everything else still see the rider.
	var carried := rider != null and is_instance_valid(rider)
	var rider_layer := rider.collision_layer if carried else 0
	if carried:
		rider.collision_layer = 0
	var pillion := passenger != null and is_instance_valid(passenger)
	var pillion_layer := passenger.collision_layer if pillion else 0
	if pillion:
		passenger.collision_layer = 0
	move_and_slide()
	if carried:
		rider.collision_layer = rider_layer
	if pillion:
		passenger.collision_layer = pillion_layer

	# Where it is going: along the heading, or for a hover trailing it by `slip`.
	var forward := Basis(Vector3.UP, heading + slip) * Vector3.FORWARD
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
		if airborne_time == 0.0 and hovers:
			# Just left the ground: off a lip the cushion damps the climb, and
			# off a level edge it will hold it up for a moment.
			if velocity.y > 0.5:
				velocity.y *= launch_keep
			_left_level = velocity.y <= 0.5
		airborne_time += delta
	rotation = Vector3(0.0, heading, 0.0)
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() < 0.01 and absf(speed) < 0.01:
		# At rest: settle exactly, so the next tick can tell nothing changed.
		speed = 0.0
		slip = 0.0
		velocity = Vector3.ZERO
	_rest_at = global_position
	_rest_heading = heading
	_place_rider()
	_update_visual(steer, delta)


## Flying: the throttle sets the speed (never under `stall_speed` while it is
## held off), steering turns at the full rate, jump climbs and descend sinks
## up to `climb_rate`, eased by `climb_accel`, and the climb stops at the
## `ceiling` over the world's ground. Below stall speed it drops.
func _fly(throttle: float, steer: float, boosting: bool, lift: float, delta: float) -> void:
	var top := boost_speed if boosting else max_speed
	if throttle > 0.05:
		speed = move_toward(speed, top * throttle, accel * delta)
	elif throttle < -0.05:
		speed = move_toward(speed, stall_speed, brake_decel * 0.5 * delta)
	elif speed > max_speed:
		speed = move_toward(speed, max_speed, coast_decel * delta)
	heading -= steer * turn_rate * delta
	var forward := Basis(Vector3.UP, heading) * Vector3.FORWARD
	var climb := lift * climb_rate
	var ground := _ground_level()
	if not is_nan(ground) and global_position.y >= ground + ceiling:
		climb = minf(climb, 0.0)
	var vy := move_toward(velocity.y, climb, climb_accel * delta)
	if speed < stall_speed:
		# Too slow to fly: it sinks, harder the slower it goes.
		var short := 1.0 - clampf(speed / maxf(stall_speed, 0.1), 0.0, 1.0)
		vy = maxf(minf(vy, velocity.y) - gravity * short * delta, -max_fall_speed)
	velocity = forward * speed + Vector3(0.0, vy, 0.0)


## How free a flier is to bank and pitch, 0 at the ground to 1 from
## `level_height` up, from a ray straight down onto the world.
func _clearance_share() -> float:
	if not is_inside_tree():
		return 1.0
	var from := global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (level_height + 0.5), Actor.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return clampf((global_position.y - hit.position.y) / level_height, 0.0, 1.0)


## The world's ground height under the vehicle (the map's `ground_height`,
## else its origin), or NAN outside a raid. The same rule as
## `Actor.ground_level`.
func _ground_level() -> float:
	var raid := Raid.of(self)
	var map: Node3D = raid.map if raid != null else null
	if map == null or not is_instance_valid(map) or not map.is_inside_tree():
		return NAN
	if map.has_method("ground_height"):
		return map.call("ground_height", global_position.x, global_position.z)
	return map.global_position.y


## Share of gravity this tick. A hover falls slowly for a moment off an edge
## at speed (the cushion carries it over a gap; less of a moment two up) and
## is pulled down harder while it rises off a crest, so it hugs the ground.
func _gravity_share(on_floor: bool) -> float:
	if not hovers or on_floor:
		return 1.0
	if velocity.y > 0.5:
		return downforce
	if _hanging(on_floor):
		return 0.0
	return 1.0


## True while the cushion holds a hover level off an edge it ran off at speed.
func _hanging(on_floor: bool) -> bool:
	return hovers and not on_floor and _left_level and airborne_time < hang_time * _laden(laden_hang) \
			and absf(speed) >= hang_min_speed


func _drive(throttle: float, steer: float, boosting: bool, delta: float) -> void:
	var top := (boost_speed if boosting else max_speed) * _laden(laden_speed)
	var push := accel * _laden(laden_accel)
	if throttle > 0.05:
		var rate := brake_decel if speed < 0.0 else push
		speed = move_toward(speed, top * throttle, rate * delta)
	elif throttle < -0.05:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, brake_decel * delta)
		else:
			speed = move_toward(speed, -reverse_speed, push * delta)
	else:
		speed = move_toward(speed, 0.0, coast_decel * delta)

	var turn_factor := clampf(absf(speed) / full_turn_speed, 0.0, 1.0)
	var rate := turn_rate * _laden(laden_turn) * turn_factor
	var way := -1.0 if speed < -0.5 else 1.0
	if pivot_turn > rate:
		# A walker turns on the spot (a hover too, slowly).
		rate = pivot_turn
	var turn := -steer * rate * way * delta
	heading += turn
	if hovers:
		# The course keeps going the old way and swings round after the nose:
		# a drift, which grip closes and which scrubs a little speed.
		slip = clampf(slip - turn, -max_slip, max_slip) * exp(-grip * delta)
		if absf(slip) < 0.0005:
			slip = 0.0
		speed -= speed * absf(sin(slip)) * 0.25 * delta
	var forward := Basis(Vector3.UP, heading + slip) * Vector3.FORWARD
	# Follow the ground: up a ramp the bike gains upward speed, which is what
	# launches it off the top.
	var along := forward.slide(get_floor_normal()).normalized()
	velocity = along * speed


func _place_rider() -> void:
	if rider != null and is_instance_valid(rider):
		rider.global_position = global_position + Basis(Vector3.UP, heading) * seat_offset
		rider.velocity = velocity
	if passenger != null and is_instance_valid(passenger):
		passenger.global_position = global_position + Basis(Vector3.UP, heading) * pillion_offset
		passenger.velocity = velocity


func _update_visual(steer: float, delta: float) -> void:
	if _model == null:
		return
	var target_lean := steer * clampf(absf(speed) / max_speed, 0.0, 1.0) * lean_amount
	if flies and not is_on_floor():
		# A flier banks hard into its turns.
		target_lean = steer * 0.6
	lean = lerpf(lean, target_lean, 1.0 - exp(-8.0 * delta))
	var pitch := 0.0
	if flies and not is_on_floor():
		pitch = clampf(velocity.y / maxf(climb_rate, 0.1), -1.0, 1.0) * flight_pitch
	elif not is_on_floor() and jump_speed <= 0.0:
		pitch = clampf(velocity.y * 0.03, -0.4, 0.4)
	var tilt := Vector3(pitch, 0.0, -lean)
	if flies and not is_on_floor():
		# Near the ground a flier levels out, so a banked wingtip or a
		# pitched nose or tail never dips into the ground it is landing on.
		tilt *= _clearance_share()
	# A positive lean rolls the right side down.
	_model.rotation = tilt


## The interact target for a vehicle. It rides along on the vehicle and only
## exists on the interactables layer, so it never blocks anything.
## The pillion seat's anchors, for a passenger's pose (`ride_anchor`). It
## rides on the model, so it tips with the lean; it has the same anchor
## names as a vehicle, so the riding pose reads either.
class Pillion extends Node3D:
	var vehicle
	var seat_offset: Vector3:
		get: return vehicle.pillion_offset
	var seat_point: Vector3:
		get: return vehicle.pillion_point
	var grip_points: Array[Vector3]:
		get: return vehicle.pillion_grips
	var peg_points: Array[Vector3]:
		get: return vehicle.pillion_pegs
	var rider_lean: float:
		get: return vehicle.pillion_lean


class Seat extends Interactable:
	## The vehicle this seat belongs to (untyped: this script has no class_name).
	var vehicle

	func get_prompt() -> String:
		return vehicle.get_prompt()

	func interact(actor: Actor) -> void:
		# The front seat first; with someone on it, behind them.
		if not vehicle.mount(actor, vehicle.rider != null):
			actor.notice.emit("Someone is riding it" if not vehicle.passenger_seat else "No room on it")
