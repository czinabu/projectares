extends CharacterBody3D
## A rideable vehicle: the motorbike, the hoverbike, the squad rover, the mech
## and the jet are all this one class, picked by item data. The `model` stat
## picks the body (`VehicleModel`), and the rest is tuning: `pivot_turn` lets a walker
## turn on the spot, `jump_speed` gives it jump-jets, the "hover" tag floats
## it on a cushion of thrust (see "Hover" below), `passenger_seat` gives it
## seats for passengers (a pillion behind the rider, or a rover's three,
## `seats`), the "aircraft" tag flies it (`_fly`), and the "airship" tag
## makes it a world's airship (`_float`): nobody rides it, its `course`
## steers it, and its seats hold its weak spots.
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

const VehicleModel := preload("res://core/vehicle/vehicle_model.gd")

signal mounted(actor: Actor)
signal dismounted(actor: Actor)

## Physics layer 4, "vehicles". Bullets and the camera ignore it, so the rider
## stays exposed and the camera never snaps in against the bike.
const LAYER_VEHICLES := Actor.LAYER_VEHICLES

var item_id := ""
var display_name := "Vehicle"
## Which greybox body to build: "bike", "hoverbike", "rover", "mech", "jet"
## or "airship".
var model := "bike"
## Which of its model's bodies a bike or a hoverbike wears
## (`VehicleModel.BODIES`, "" for the first): the Scrapper is a "scrambler",
## the Raider a "ducted". A new bike can be another body and other tuning,
## all as item data.
var body := ""
## True for an item tagged "aircraft": it takes off past `takeoff_speed`.
var flies := false
## True for an item tagged "airship" (DESIGN.md "Basalt Rift", the Sky
## Leviathan): a world event's ship, never ridden or packed (it has no
## seat to interact with). Afloat it steers for `course` (`_float`) and
## passes through everything; with no course it falls, and then the world
## stops it. Each of its `seats` with a "part" is a weak spot: the `Raid`
## puts a bot there, and the model's piece for it ("Part<n>") shows broken
## once that seat has been manned and is empty.
var floats := false
## Where an airship steers for: it turns towards it at `turn_rate` and
## climbs or sinks to its height at up to `climb_rate`. INF: it falls.
var course := Vector3.INF
## Which of an airship's seats have been manned, so an empty one is broken.
var _manned: Array[bool] = []
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
## Wheels (and a hover's cushion) keep to the ground over a crest (a dune's
## top, a rise in the road) while they leave it climbing slower than this, in
## m/s: only a real ramp, taken fast, throws them in the air. Walkers stride
## their own way.
var crest_hold := 6.0
## How far down a crest's far side the wheels look for the ground, in metres.
var crest_snap := 1.2
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
## Tonnes, for what thin ice bears (`WorldDef.ice_holds`).
var weight := 0.3
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

# The handbrake (`handbrake`: wheels and the hoverbike). Held
# on the jump key (`ActorCommand.jump`) at speed, it locks the back end: the
# throttle stops pushing, the speed bleeds off at `handbrake_decel`, the nose
# swings round `drift_turn` times faster and the course trails it like a
# hover's (`slip`), held only by `drift_grip`, so the machine slides round a
# corner nose first. A drift held at `drift_min_slip` or wider builds a
# charge over `drift_build` seconds; let go of it on the throttle, without
# hitting anything, and the charge is a burst of up to `drift_boost` m/s,
# delivered over `drift_boost_time` (a clean exit). All of it is simulated
# from the command, so it predicts and replicates like the rest of the ride.
## True for a machine with a handbrake. Every wheeled machine and the
## hoverbike have one; the walker (whose jump key is its jump-jets) and the
## jet (whose jump key climbs) set it off in their stats.
var handbrake := true
var handbrake_decel := 5.0
var drift_turn := 1.6
var drift_grip := 2.5
var drift_max_slip := 0.85
## Below this speed (forward, m/s) the handbrake only brakes.
var drift_min_speed := 8.0
var drift_min_slip := 0.2
var drift_build := 0.8
var drift_boost := 4.0
var drift_boost_time := 0.3
## Share of speed a slide scrubs off a second, times the sine of its slip.
var slide_scrub := 0.25
## How fast a wheeled machine's course grips back onto its heading, per
## second, once its wheels break loose (let go of the handbrake, or on a
## slick surface, see `_surface_grip`).
var tyre_grip := 7.0
## True while the handbrake holds a drift this tick.
var drifting := false
## Seconds of clean drift banked toward the exit boost (0 to `drift_build`).
var drift_charge := 0.0
## m/s of exit boost still to be delivered.
var _boost_left := 0.0
## The world this vehicle is in, for its surface (`WorldDef.surface_grip`).
var _world: WorldDef
## Seconds to the next puff of tyre smoke or spray (view only).
var _puff_wait := 0.0

# Seats for passengers (`passenger_seat`). Each seat's anchors work like the
# rider's (`seat_offset`, `seat_point`, `grip_points`, `peg_points`,
# `rider_lean`, `exit_offset`); a passenger only sits, and may shoot. By
# default it is one pillion seat behind the rider, from the `pillion_*`
# vars; an item lists more in `seats`, each a dictionary with the keys
# "offset", "point", "grips", "pegs", "lean" and "exit". A seat with a
# "gun" (an item id, tagged "mounted") is a gunner's: whoever sits there
# has that gun drawn (`_arm_seat`), on every machine, and loses it when
# they get off.
var passenger_seat := false
var seats: Array = []
var pillion_offset := Vector3(0.0, 0.17, 0.76)
var pillion_point := Vector3(0.0, 1.1, 0.76)
var pillion_grips: Array[Vector3] = [Vector3(-0.24, 1.1, 0.56), Vector3(0.24, 1.1, 0.56)]
var pillion_pegs: Array[Vector3] = [Vector3(-0.36, 0.8, 0.5), Vector3(0.36, 0.8, 0.5)]
var pillion_lean := 0.25
var pillion_exit := Vector3(-1.4, 0.1, 0.6)
## Two up it is heavier: these share of top speed, acceleration, turn rate
## and gap glide are what is left with a passenger aboard, and again for
## each more.
## Cargo (DESIGN.md "The Dune Sea"): where salvage crates ride, in the
## vehicle's own space, one crate a point (`SalvageCrate`, the `Raid`'s
## `set_down_crate`). `cargo` holds the crate at each point, or null.
var cargo_points: Array[Vector3] = []
var cargo: Array = []
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
## Who sits on each of `seats` (null where it is empty), in seat order.
var passengers: Array = []
## Whoever sits on the first passenger seat taken, or null.
var passenger: Actor:
	get:
		for actor in passengers:
			if actor != null:
				return actor
		return null
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
## Held for a race's lights (`Race`): the rider's throttle, steering and
## boost do nothing until it is let go. Set on every machine that simulates
## the ride, from the run, so it predicts online.
var held := false
## The race profile: tuning that replaces the stats above in a race world
## (`apply_race_profile`), so combat tuning never moves a lap time.
var race := {}
var _seat: Seat
## Each passenger seat's anchors, riding on the model (`ride_anchor`).
var _pillions: Array[Pillion] = []
## Seconds of hover bob, for the look only.
var _bob_time := 0.0

# The body's pose on the ground (view only, `_pose_model`, run on every
# machine from where the vehicle is and which way it points, so a ride looks
# the same from the saddle and across the street). The body tips to the
# ground under its wheels, read by a ray under each end (and each side for
# a wide one), and rides a spring that dips the nose under braking, squats
# under the throttle and thumps down on landing. The simulation never reads
# any of it.
## Half the track and half the wheelbase (m): where the rays look for the
## ground, across (x) and along (y). Zero across: it never rolls to the
## ground (a bike leans instead). Zero along: it never pitches to it (a
## walker strides its own way). Unset (-1), it comes from the model.
var contact_span := Vector2(-1.0, -1.0)
## How hard the spring pulls the body back (per second squared) and how much
## it damps the swing (per second).
var spring_rate := 140.0
var spring_damp := 14.0
## Radians the nose dips (or the tail squats) per m/s² of slowing (or
## speeding up), and the most it will.
var pitch_per_accel := 0.006
var max_body_pitch := 0.12
## How hard a landing kicks the nose down, per m/s it came down at.
var land_kick := 0.08
## How fast the body turns onto the ground's slope (per second).
var ground_follow := 12.0
## Further than this from the camera (m) the rays are left alone and the
## body keeps the slope it last read: nobody sees it tip from there.
var ground_view_range := 90.0
## Reads the ground headless too (tests only: a server never poses bodies).
var pose_headless := false
## Pitch and roll of the ground under the body (radians), and the spring's
## pitch with its rate.
var _ground_tilt := Vector2.ZERO
var _sway := 0.0
var _sway_rate := 0.0
## Where the ground was last read from, so a parked one reads it once.
var _ground_at := Vector3.INF
var _ground_heading := INF
## The last frame's place, heading, speed and fall, for the rates the pose
## follows (it works from what every machine has, not the rider's input).
var _pose_heading := INF
var _pose_speed := 0.0
var _pose_fall := 0.0
var _pose_y := INF
var _yaw_rate := 0.0
var _accel_seen := 0.0
var _was_grounded := true
## The hover's bob, added to the body's heave.
var _bob := 0.0

# Moving parts (view only, `_turn_parts`): wheels spin with the speed,
# steering wheels, forks, bars and a hover's rudders turn with the steering.
# The model marks them: a "Wheel..." node with its "radius" (and "steers"),
# whose "Spin" child turns with the speed,
# a pivot with its "axis" and "share" of the steering (and "grips" when the
# rider's hands are on it, `posed_grips`), a fan's "Rotor..." that spins
# while it runs, faster with the speed.
## Stopped with a rider aboard, a bike tips this far (radians) onto the
## rider's left foot.
var stand_lean := 0.09
## The steering's look, in radians at full lock at a standstill; at top
## speed a little of it (`steer_view_fast`), as a rider barely turns the bars.
var steer_view_angle := 0.38
var steer_view_fast := 0.35
## The steering shown now, in radians (positive turns left).
var steer_view := 0.0
var _wheels: Array[Node3D] = []
var _pivots: Array[Node3D] = []
var _rotors: Array[Node3D] = []
var _wheel_turn := 0.0
var _rotor_turn := 0.0
## A fan rotor's turns a second: idling, and added at top speed.
var rotor_idle_rate := 1.5
var rotor_speed_rate := 4.0


func setup(p_item_id: String) -> void:
	item_id = p_item_id
	display_name = ItemDB.item_name(p_item_id)
	flies = ItemDB.has_tag(p_item_id, "aircraft")
	floats = ItemDB.has_tag(p_item_id, "airship")
	hovers = ItemDB.has_tag(p_item_id, "hover")
	var stats := ItemDB.item_stats(p_item_id)
	for key: String in stats:
		if key in self:
			set(key, stats[key])
		else:
			push_warning("Vehicle: no property '%s' for %s" % [key, p_item_id])
	_fill_seats()
	cargo.resize(cargo_points.size())
	if contact_span.x < 0.0 or contact_span.y < 0.0:
		contact_span = _default_span()


## Where a model's wheels (or a hover's pontoons) meet the ground, for
## `contact_span`: the bikes along only, the rover's four corners, a jet's
## gear; a walker and an airship never follow the ground.
func _default_span() -> Vector2:
	match model:
		"bike":
			return Vector2(0.0, 0.75)
		"hoverbike":
			return Vector2(0.0, 0.95)
		"rover":
			return Vector2(1.0, 1.35)
		"jet":
			return Vector2(0.0, body_size.z * 0.3)
	return Vector2.ZERO


## The pillion seat from the `pillion_*` vars, unless the item lists its own.
func _fill_seats() -> void:
	if passenger_seat and seats.is_empty():
		seats = [{"offset": pillion_offset, "point": pillion_point, "grips": pillion_grips,
				"pegs": pillion_pegs, "lean": pillion_lean, "exit": pillion_exit}]
	if not passenger_seat:
		seats = []
	passengers.resize(seats.size())


## Puts the race profile's tuning in place of the item's own. Called by a
## `Race` on every machine it spawns, on every machine that runs the race.
func apply_race_profile() -> void:
	for key: String in race:
		if key in self and key != "race":
			set(key, race[key])
	floor_max_angle = deg_to_rad(max_slope)


func _ready() -> void:
	add_to_group("vehicles")
	# After the player controller (-10) writes the command, before Actors (0) tick.
	process_physics_priority = -5
	collision_layer = LAYER_VEHICLES
	collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ACTORS
	if floats:
		# Afloat it passes through everything (its route is clear); going
		# down, it comes to rest on the world (`_float`).
		collision_mask = 0
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

	if not floats:
		_seat = Seat.new()
		_seat.name = "Seat"
		_seat.vehicle = self
		seat_col.shape = seat_shape
		_seat.add_child(seat_col)
		add_child(_seat)
	else:
		seat_col.free()

	_model = build_visual()
	add_child(_model)
	if passengers.size() != seats.size():
		_fill_seats()
	_pillions.clear()
	for i in seats.size():
		# On the model, so a passenger tips with the lean like the rider.
		var pillion := Pillion.new()
		pillion.name = "Pillion" if i == 0 else "Pillion%d" % (i + 1)
		pillion.vehicle = self
		pillion.index = i
		_model.add_child(pillion)
		_pillions.append(pillion)


## The body for `model`, built by `VehicleModel` round this vehicle's seat,
## grips and pegs (`grip_points`, `peg_points`). A walker's legs are its
## "LegL" and "LegR".
func build_visual() -> Node3D:
	var root: Node3D = VehicleModel.build(self)
	_wheels.clear()
	_pivots.clear()
	_rotors.clear()
	for node in root.find_children("*", "Node3D", true, false):
		if str(node.name).begins_with("Rotor"):
			_rotors.append(node)
		elif node.has_meta("radius"):
			_wheels.append(node)
		elif node.has_meta("axis"):
			_pivots.append(node)
	_legs.clear()
	for leg_name: String in ["LegL", "LegR"]:
		var leg := root.get_node_or_null(leg_name) as Node3D
		if leg != null:
			_legs.append(leg)
	return root


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
	if floats and _model != null:
		_show_parts()
	_puff_slide(delta)
	_pose_model(delta)


## An airship's weak spots: a seat's piece ("Part<n>") shows broken
## ("Broken<n>") once its seat has been manned and is empty again. View
## only, from who sits where, which every machine keeps.
func _show_parts() -> void:
	if _manned.size() != seats.size():
		_manned.resize(seats.size())
	for i in seats.size():
		if passengers[i] != null:
			_manned[i] = true
		var whole := passengers[i] != null or not _manned[i]
		var piece := _model.get_node_or_null("Part%d" % i) as Node3D
		if piece == null or piece.visible == whole:
			continue
		piece.visible = whole
		var wreck := _model.get_node_or_null("Broken%d" % i) as Node3D
		if wreck != null:
			wreck.visible = not whole
		if not whole and is_inside_tree():
			var at := piece.global_position
			Fx.burst(get_parent(), at, 3.5, Color(1.0, 0.55, 0.2))
			Fx.puff(get_parent(), at, 3.0, Color(0.2, 0.18, 0.17, 0.8))
			Sfx.play("shell_blast", at, 2.0, 250.0, 30.0)


## Tyre smoke off the back wheels while they slide, or spray off a hover's
## thrusters (view only, from `slip`, which every machine keeps, so a drift
## looks the same from the saddle and from across the street).
func _puff_slide(delta: float) -> void:
	_puff_wait -= delta
	if _puff_wait > 0.0 or absf(slip) < 0.15 or absf(speed) < 4.0 or not is_on_floor() or not is_inside_tree():
		return
	_puff_wait = 0.07
	var back := body_size.z * 0.4 if model != "bike" and model != "hoverbike" else 0.75
	var color := Color(0.75, 0.9, 1.0, 0.45) if hovers else Color(0.82, 0.8, 0.76, 0.55)
	for side: float in [-1.0, 1.0]:
		var at := global_position + Basis(Vector3.UP, heading) * Vector3(side * body_size.x * 0.4, 0.15, back)
		Fx.puff(get_parent(), at, 0.35 + absf(slip) * 0.5, color)


## A hover bobs gently on its cushion and its thrusters burn brighter with
## speed (view only, from `speed`, which a client keeps for every vehicle).
func _animate_hover(delta: float) -> void:
	_bob_time = fmod(_bob_time + delta, TAU * 10.0)
	var pace := clampf(absf(speed) / maxf(max_speed, 0.1), 0.0, 1.0)
	_bob = sin(_bob_time * 2.4) * 0.035 * (1.0 - 0.6 * pace)
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


func get_prompt() -> String:
	if rider == null:
		return "[F] Ride %s" % display_name
	if free_seat() >= 0:
		return ("[F] Ride behind on %s" if seats.size() == 1 else "[F] Ride in %s") % display_name
	return "%s (ridden)" % display_name


## True with anyone aboard, rider or passenger.
func is_occupied() -> bool:
	return rider != null or passenger != null


## How many passengers are aboard.
func passenger_count() -> int:
	var count := 0
	for actor in passengers:
		if actor != null:
			count += 1
	return count


## The empty passenger seat nearest `near` (any empty one without it), or -1.
func free_seat(near := Vector3.INF) -> int:
	var best := -1
	var best_d := INF
	for i in seats.size():
		if passengers[i] != null:
			continue
		if near == Vector3.INF:
			return i
		var d := near.distance_to(global_position + Basis(Vector3.UP, heading) * Vector3(seats[i].offset))
		if d < best_d:
			best = i
			best_d = d
	return best


## Which passenger seat `actor` is on, or -1.
func seat_of(actor: Actor) -> int:
	return passengers.find(actor) if actor != null else -1


## Puts an actor on the seat, or with `behind` on a passenger seat: seat
## `seat` if given, else the empty one nearest them. Returns false if that
## seat is taken or they cannot ride.
func mount(actor: Actor, behind := false, seat := -1) -> bool:
	if actor == null or actor.is_dead or actor.vehicle != null or unpack_left > 0.0:
		return false
	if not behind and rider == null:
		rider = actor
	elif behind:
		if seat < 0:
			seat = free_seat(actor.global_position)
		if seat < 0 or seat >= seats.size() or passengers[seat] != null:
			return false
		passengers[seat] = actor
	else:
		return false
	actor.vehicle = self
	add_collision_exception_with(actor)
	actor.add_collision_exception_with(self)
	if not actor.died.is_connected(_on_rider_died):
		actor.died.connect(_on_rider_died)
	_place_rider()
	if seat_of(actor) >= 0 and _arm_seat(actor, seat_of(actor)):
		actor.notice.emit("On the %s's gun. F to get off" % display_name)
	elif seat_of(actor) >= 0:
		actor.notice.emit(("Riding behind on %s. F to get off" if seats.size() == 1
				else "Riding in %s. F to get off") % display_name)
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


## Drops every passenger off their seats.
func dismount_passenger() -> void:
	for actor in passengers.duplicate():
		if actor != null:
			_let_off(actor)


## Everyone off.
func dismount_all() -> void:
	dismount()
	dismount_passenger()


## Lets `actor` off, whichever seat they are on.
func get_off(actor: Actor) -> void:
	if actor != null and (actor == rider or seat_of(actor) >= 0):
		_let_off(actor)


func _let_off(actor: Actor) -> void:
	var seat := seat_of(actor)
	var behind := seat >= 0
	if behind:
		passengers[seat] = null
	else:
		rider = null
	if not is_instance_valid(actor):
		return
	_disarm_seat(actor)
	actor.vehicle = null
	if actor.died.is_connected(_on_rider_died):
		actor.died.disconnect(_on_rider_died)
	if not actor.is_dead:
		# The exit spot is clear of the bike's body, so they collide again at once.
		var out: Vector3 = seats[seat].exit if behind else exit_offset
		actor.global_position = global_position + Basis(Vector3.UP, heading) * out
		actor.velocity = velocity
	remove_collision_exception_with(actor)
	actor.remove_collision_exception_with(self)
	dismounted.emit(actor)


## The gunner's seat: `actor` draws its mounted gun (a weapon of their own
## for as long as they sit there, marked "mounted"). Returns whether the
## seat has one.
func _arm_seat(actor: Actor, seat: int) -> bool:
	var id := str((seats[seat] as Dictionary).get("gun", ""))
	if id == "" or not ItemDB.has_item(id):
		return false
	var gun := Gun.new()
	gun.item_id = id
	gun.display_name = ItemDB.item_name(id)
	for key: String in ItemDB.item_stats(id):
		if key in gun:
			gun.set(key, ItemDB.item_stats(id)[key])
	gun.set_meta("mounted", true)
	actor.set_meta("unmounted_draw", actor.active_weapon_index)
	actor.equip_weapon(gun)
	actor.draw_weapon(actor.weapons.size() - 1)
	actor.call("_refresh_weapon_visuals")
	return true


## Off the gunner's seat: the mounted gun stays with the vehicle, and what
## they held before is back in hand.
func _disarm_seat(actor: Actor) -> void:
	for i in range(actor.weapons.size() - 1, -1, -1):
		if actor.weapons[i].has_meta("mounted"):
			actor.remove_weapon(i)
	if actor.has_meta("unmounted_draw"):
		var back := int(actor.get_meta("unmounted_draw"))
		actor.remove_meta("unmounted_draw")
		if back >= 0 and back < actor.weapons.size():
			actor.draw_weapon(back)
		elif back < 0:
			# They had nothing in hand: nothing in hand again.
			actor.active_weapon_index = -1
			actor.call("_refresh_weapon_visuals")


func _on_rider_died(actor: Actor, _info: DamageInfo) -> void:
	if seat_of(actor) >= 0:
		_let_off(actor)
	else:
		dismount()


## What a seated actor's pose is fitted to: the vehicle itself for the rider,
## their seat's anchors (on the model) for a passenger.
func ride_anchor(actor: Actor) -> Node3D:
	var seat := seat_of(actor)
	if seat >= 0 and seat < _pillions.size():
		return _pillions[seat]
	return self


## Share of a stat left with the passengers aboard (1 when ridden alone).
func _laden(share: float) -> float:
	return pow(share, passenger_count())


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var boosting := false
	var lift := 0.0
	var hop := false
	var hand := false
	_jump_wait = maxf(0.0, _jump_wait - delta)
	if rider != null and (not is_instance_valid(rider) or rider.is_dead):
		dismount()
	for i in passengers.size():
		var aboard = passengers[i]
		if aboard == null:
			continue
		if not is_instance_valid(aboard):
			passengers[i] = null
		elif aboard.is_dead:
			_let_off(aboard)
		elif aboard.cmd.interact_pressed and (Combat.authoritative or local_only):
			aboard.cmd.interact_pressed = false
			_let_off(aboard)
	if rider != null:
		var cmd := rider.cmd
		if cmd.interact_pressed and (Combat.authoritative or local_only):
			# The press is spent on getting off, not on looting.
			cmd.interact_pressed = false
			dismount()
		else:
			# Online, a client predicting its own ride leaves getting off to
			# the server, and the press still has to reach it.
			throttle = clampf(cmd.move.y, -1.0, 1.0) if not held else 0.0
			steer = clampf(cmd.move.x, -1.0, 1.0) if not held else 0.0
			boosting = cmd.sprint and not held
			lift = (1.0 if cmd.jump else 0.0) - (1.0 if cmd.descend else 0.0)
			hop = cmd.jump_pressed
			hand = handbrake and cmd.jump and not held

	# A parked bike nobody rides, standing where its last move left it, has
	# no move to make. A map has a dozen standing about, and the move is the
	# dearest part of a tick. Anything that moves, turns or pushes it wakes it.
	if rider == null and is_on_floor() and speed == 0.0 and velocity.is_zero_approx() and slip == 0.0 \
			and _boost_left == 0.0 and global_position == _rest_at and heading == _rest_heading:
		return
	var on_floor := is_on_floor()
	_turning = steer
	# A flier is flying once it is off the ground with someone at the stick,
	# or rolling fast enough to lift off and asked to climb. Nobody aboard, it
	# drops like anything else.
	var flying := flies and rider != null and (not on_floor or (lift > 0.0 and speed >= takeoff_speed))
	if floats:
		_float(delta)
	elif flying:
		_fly(throttle, steer, boosting, lift, delta)
	else:
		if on_floor:
			_drive(throttle, steer, boosting, hand, delta)
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
	var aboard_layers := {}
	for aboard in passengers:
		if aboard != null and is_instance_valid(aboard):
			aboard_layers[aboard] = aboard.collision_layer
			aboard.collision_layer = 0
	move_and_slide()
	if on_floor and not is_on_floor() and not flying and not floats:
		_hold_crest()
	if carried:
		rider.collision_layer = rider_layer
	for aboard: Actor in aboard_layers:
		aboard.collision_layer = aboard_layers[aboard]

	# Where it is going: along the heading, or for a hover trailing it by `slip`.
	var forward := Basis(Vector3.UP, heading + slip) * Vector3.FORWARD
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if is_on_wall():
		# Hitting something scrubs off the speed that went into it, and a
		# drift that hits something is no clean exit.
		var kept := horizontal.dot(forward)
		speed = minf(speed, kept) if speed >= 0.0 else maxf(speed, kept)
		drift_charge = 0.0
		_boost_left = 0.0
	if not is_on_floor():
		# Off the ground the wheels hold nothing: no drift to carry on.
		drifting = false
		drift_charge = 0.0
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
		drifting = false
		drift_charge = 0.0
		_boost_left = 0.0
		velocity = Vector3.ZERO
	_rest_at = global_position
	_rest_heading = heading
	_place_rider()


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


## Wheels (and a hover) just run over a crest: pulled back onto the ground below
## (`crest_snap`) unless they left it climbing at `crest_hold` or faster, and
## then follow the far side. Without it every dune top throws a rover in the
## air, where it can neither steer nor brake.
func _hold_crest() -> void:
	# A walker strides (and hops) its own way; a hover's cushion still holds
	# it level off a real edge, past `crest_snap`.
	if (pivot_turn > 0.0 and not hovers) or velocity.y >= crest_hold:
		return
	var keep := floor_snap_length
	floor_snap_length = crest_snap
	apply_floor_snap()
	floor_snap_length = keep
	if is_on_floor():
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		velocity = horizontal.slide(get_floor_normal()).normalized() * horizontal.length()


## An airship: afloat, it turns towards its `course` at `turn_rate` (slowing
## into a sharp turn) and climbs or sinks to the course's height; with no
## course it falls, drifting on, and comes down on the world.
func _float(delta: float) -> void:
	var forward := Basis(Vector3.UP, heading) * Vector3.FORWARD
	if course == Vector3.INF:
		collision_mask = Actor.LAYER_WORLD
		speed = move_toward(speed, max_speed * 0.5, coast_decel * delta)
		velocity = forward * speed + Vector3(0.0, maxf(velocity.y - gravity * delta, -max_fall_speed), 0.0)
		return
	collision_mask = 0
	var to := course - global_position
	var off := wrapf(atan2(-to.x, -to.z) - heading, -PI, PI)
	if Vector2(to.x, to.z).length() > 0.5:
		heading += clampf(off, -turn_rate * delta, turn_rate * delta)
	_turning = clampf(-off, -1.0, 1.0)
	speed = move_toward(speed, max_speed * clampf(1.2 - absf(off), 0.4, 1.0), accel * delta)
	var vy := move_toward(velocity.y, clampf(to.y * 0.4, -climb_rate, climb_rate), climb_accel * delta)
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


func _drive(throttle: float, steer: float, boosting: bool, hand: bool, delta: float) -> void:
	var top := (boost_speed if boosting else max_speed) * _laden(laden_speed)
	var surface := _surface_grip()
	# A slick surface gives the wheels less to push and brake against.
	var push := accel * _laden(laden_accel) * surface
	var was_drifting := drifting
	drifting = hand and speed >= drift_min_speed
	if drifting:
		# The back end is locked: the throttle does nothing and it bleeds off.
		speed = move_toward(speed, 0.0, handbrake_decel * delta)
	elif hand:
		# Too slow to drift: the handbrake just brakes.
		speed = move_toward(speed, 0.0, brake_decel * surface * delta)
	elif throttle > 0.05:
		var rate := brake_decel * surface if speed < 0.0 else push
		speed = move_toward(speed, top * throttle, rate * delta)
	elif throttle < -0.05:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, brake_decel * surface * delta)
		else:
			speed = move_toward(speed, -reverse_speed, push * delta)
	else:
		speed = move_toward(speed, 0.0, coast_decel * surface * delta)
	_drift_exit(was_drifting, throttle, top, delta)

	var turn_factor := clampf(absf(speed) / full_turn_speed, 0.0, 1.0)
	var rate := turn_rate * _laden(laden_turn) * turn_factor
	var way := -1.0 if speed < -0.5 else 1.0
	if drifting:
		rate *= drift_turn
	if pivot_turn > rate:
		# A walker turns on the spot (a hover too, slowly).
		rate = pivot_turn
	var turn := -steer * rate * way * delta
	heading += turn
	# The course keeps going the old way and swings round after the nose: a
	# hover always does (a drift through every turn), wheels only where they
	# break loose, under the handbrake or on a slick surface.
	var loose := 1.0 if hovers else 1.0 - surface
	var hold := grip if hovers else tyre_grip * surface
	var limit := max_slip
	if drifting:
		loose = 1.0
		hold = drift_grip
		limit = drift_max_slip
	if loose > 0.0 or slip != 0.0:
		# The limit only stops a slide opening further, never snaps one shut.
		limit = maxf(limit, absf(slip))
		slip = clampf(slip - turn * loose, -limit, limit) * exp(-hold * delta)
		if absf(slip) < 0.0005:
			slip = 0.0
		speed -= speed * absf(sin(slip)) * slide_scrub * delta
	var forward := Basis(Vector3.UP, heading + slip) * Vector3.FORWARD
	# Follow the ground: up a ramp the bike gains upward speed, which is what
	# launches it off the top.
	var along := forward.slide(get_floor_normal()).normalized()
	velocity = along * speed


## The drift's charge and its exit boost. A drift held wide banks charge;
## letting go on the throttle turns it into a burst, eased in over
## `drift_boost_time` and never past `boost_speed`. Braking cancels it.
func _drift_exit(was_drifting: bool, throttle: float, top: float, delta: float) -> void:
	if drifting:
		_boost_left = 0.0
		if absf(slip) >= drift_min_slip:
			drift_charge = minf(drift_charge + delta, drift_build)
	elif was_drifting:
		if throttle > 0.05 and drift_charge >= drift_build * 0.25:
			_boost_left = drift_boost * drift_charge / maxf(drift_build, 0.01)
			Sfx.play("dash", global_position, -4.0)
		drift_charge = 0.0
	if _boost_left <= 0.0:
		return
	if throttle < -0.05:
		_boost_left = 0.0
		return
	var step := minf(_boost_left, drift_boost / maxf(drift_boost_time, 0.01) * delta)
	_boost_left -= step
	var cap := maxf(boost_speed * _laden(laden_speed), top)
	if speed < cap:
		speed = minf(speed + step, cap)
	if _boost_left < 0.0005:
		_boost_left = 0.0


## How much grip the ground under the wheels gives, 1 on dry ground, less on
## snow and ice (`WorldDef.surface_grip`). A hover rides a cushion, so it is
## the same everywhere.
func _surface_grip() -> float:
	if hovers:
		return 1.0
	if _world == null:
		var raid := Raid.of(self)
		if raid == null or raid.world == null:
			return 1.0
		_world = raid.world
	return clampf(_world.surface_grip(global_position), 0.2, 1.0)


func _place_rider() -> void:
	if rider != null and is_instance_valid(rider):
		rider.global_position = global_position + Basis(Vector3.UP, heading) * seat_offset
		rider.velocity = velocity
	for i in passengers.size():
		var aboard = passengers[i]
		if aboard != null and is_instance_valid(aboard):
			aboard.global_position = global_position + Basis(Vector3.UP, heading) * Vector3(seats[i].offset)
			aboard.velocity = velocity


## Poses the body (view only, every frame, on every machine): the lean
## into a turn, a flier's bank and climb, and on the ground the slope under
## it and the spring (`contact_span`, `spring_rate`). The turn is read from
## how fast the heading swings, not from the rider's keys, so a vehicle
## someone else drives leans the same.
func _pose_model(delta: float) -> void:
	if _model == null or delta <= 0.0:
		return
	var turned := 0.0 if _pose_heading == INF else wrapf(heading - _pose_heading, -PI, PI)
	_pose_heading = heading
	_yaw_rate = lerpf(_yaw_rate, turned / delta, 1.0 - exp(-12.0 * delta))
	var steer := clampf(-_yaw_rate / maxf(turn_rate, 0.1), -1.0, 1.0)
	if floats:
		steer = _turning
	var grounded := _grounded()
	var target_lean := steer * clampf(absf(speed) / max_speed, 0.0, 1.0) * lean_amount
	if rider != null and grounded and absf(speed) < 0.6 and (model == "bike" or model == "hoverbike"):
		# Stopped, the bike rests on the rider's left foot.
		target_lean = -stand_lean
	if flies and not grounded:
		# A flier banks hard into its turns.
		target_lean = steer * 0.6
	lean = lerpf(lean, target_lean, 1.0 - exp(-8.0 * delta))
	var fall := 0.0 if _pose_y == INF else (global_position.y - _pose_y) / delta
	_pose_y = global_position.y
	var pitch := 0.0
	if flies and not grounded:
		pitch = clampf(fall / maxf(climb_rate, 0.1), -1.0, 1.0) * flight_pitch
	elif not grounded and jump_speed <= 0.0:
		pitch = clampf(fall * 0.03, -0.4, 0.4)
	if floats:
		# An airship rolls a little into its turns and noses down falling.
		lean = lerpf(lean, steer * lean_amount, 1.0 - exp(-2.0 * delta))
		pitch = clampf(fall * 0.03, -0.35, 0.1) if course == Vector3.INF else 0.0
	_settle_body(grounded, fall, delta)
	var tilt := Vector3(pitch, 0.0, -lean)
	if flies and not grounded:
		# Near the ground a flier levels out, so a banked wingtip or a
		# pitched nose or tail never dips into the ground it is landing on.
		tilt *= _clearance_share()
	# A positive lean rolls the right side down; the ground's pitch lifts the
	# nose up a rise, its roll lifts the uphill side.
	tilt += Vector3(_ground_tilt.x, 0.0, _ground_tilt.y)
	# The spring tips the body about the wheel that stays down: the front
	# one as the nose dips, the back one as the tail squats, so no wheel
	# ever sinks into the ground.
	var pivot := Vector3(0.0, 0.0, contact_span.y * (1.0 if _sway > 0.0 else -1.0))
	var sprung := Basis(Vector3.RIGHT, _sway)
	_model.transform = Transform3D(Basis.from_euler(tilt), Vector3(0.0, _bob, 0.0)) \
			* Transform3D(sprung, pivot - sprung * pivot)
	var pace := clampf(absf(speed) / maxf(max_speed, 0.1), 0.0, 1.0)
	var lock := -steer * steer_view_angle * lerpf(1.0, steer_view_fast, pace)
	if pivot_turn > 0.0 and absf(speed) < 0.5:
		lock = 0.0
	steer_view = lerpf(steer_view, lock, 1.0 - exp(-10.0 * delta))
	_turn_parts(delta)


## Spins the wheels with the speed and turns the steering parts (view only).
func _turn_parts(delta: float) -> void:
	if _wheels.is_empty() and _pivots.is_empty() and _rotors.is_empty():
		return
	_wheel_turn = wrapf(_wheel_turn - speed * delta, 0.0, TAU * 1000.0)
	for wheel in _wheels:
		if wheel.get_meta("steers", false):
			wheel.basis = Basis(Vector3.UP, steer_view)
		var spin := wheel.get_node_or_null("Spin") as Node3D
		if spin != null:
			spin.basis = Basis(Vector3.RIGHT, _wheel_turn / float(wheel.get_meta("radius", 0.4)))
	for pivot in _pivots:
		pivot.basis = Basis(pivot.get_meta("axis") as Vector3, steer_view * float(pivot.get_meta("share", 1.0)))
	if not _rotors.is_empty():
		var pace := clampf(absf(speed) / maxf(max_speed, 0.1), 0.0, 1.0)
		_rotor_turn = wrapf(_rotor_turn + TAU * (rotor_idle_rate + rotor_speed_rate * pace) * delta, 0.0, TAU)
		for i in _rotors.size():
			_rotors[i].basis = Basis(Vector3.UP, _rotor_turn * (1.0 if i % 2 == 0 else -1.0))


## Where the rider's hands go: `grip_points`, turned with the bars or the
## wheel they hold (`steer_view`), so the hands stay on them. In the
## vehicle's frame, read by the riding pose.
func posed_grips() -> Array[Vector3]:
	for pivot in _pivots:
		if not pivot.get_meta("grips", false):
			continue
		var turn := Basis(pivot.get_meta("axis") as Vector3, steer_view * float(pivot.get_meta("share", 1.0)))
		var out: Array[Vector3] = []
		for grip in grip_points:
			out.append(pivot.position + turn * (grip - pivot.position))
		return out
	return grip_points


## True while it stands or rolls on the ground. Where this machine moves it
## that is the move's own answer; where the server's state does, the ground
## close under it.
func _grounded() -> bool:
	if floats:
		return false
	if is_physics_processing():
		return is_on_floor() or airborne_time < 0.05
	if not is_inside_tree() or (DisplayServer.get_name() == "headless" and not pose_headless) \
			or global_position.distance_squared_to(_under_at) < 0.0004:
		return _under_ground
	_under_at = global_position
	var below := _ground_height(Vector3.ZERO)
	_under_ground = not is_nan(below) and global_position.y - below < 0.5
	return _under_ground


## Where the ground under a vehicle moved from elsewhere was last looked
## for, and whether it was found close under it.
var _under_at := Vector3.INF
var _under_ground := true


## The slope under the wheels and the spring on top of it.
func _settle_body(grounded: bool, fall: float, delta: float) -> void:
	# The body's spring: slowing dips the nose, speeding up squats the tail,
	# and a landing sinks it by how hard it came down.
	var gained := (speed - _pose_speed) / delta
	_pose_speed = speed
	_accel_seen = lerpf(_accel_seen, gained, 1.0 - exp(-10.0 * delta))
	var want_pitch := 0.0
	if grounded and pivot_turn <= 0.0:
		# A positive pitch lifts the nose: speeding up lifts it, slowing drops it.
		want_pitch = clampf(_accel_seen * pitch_per_accel, -max_body_pitch, max_body_pitch)
	if grounded and not _was_grounded and _pose_fall < -2.0 and contact_span.y > 0.0:
		# A landing thumps the nose down onto the front wheel and back.
		_sway_rate -= minf(-_pose_fall * land_kick, max_body_pitch * 12.0)
	_was_grounded = grounded
	_pose_fall = fall
	# Stepped in short slices, so a long frame cannot throw it off.
	var left := minf(delta, 0.1)
	while left > 0.0:
		var step := minf(left, 1.0 / 120.0)
		left -= step
		_sway_rate += ((want_pitch - _sway) * spring_rate - _sway_rate * spring_damp) * step
		_sway += _sway_rate * step
	_sway = clampf(_sway, -max_body_pitch * 1.5, max_body_pitch * 1.5)
	var want := _ground_tilt
	if grounded and contact_span != Vector2.ZERO:
		want = _read_ground()
	elif not grounded:
		want = Vector2.ZERO
	_ground_tilt = _ground_tilt.lerp(want, 1.0 - exp(-ground_follow * delta))


## The ground's pitch (x, nose up positive) and roll (y, positive lifts the
## right side, as the model's turn about its long axis does) under the wheels, from a ray under each end and each side.
## Read again only once the vehicle has moved or turned, and only within
## `ground_view_range` of the camera; otherwise the last answer stands.
func _read_ground() -> Vector2:
	if not is_inside_tree() or (DisplayServer.get_name() == "headless" and not pose_headless):
		return _ground_target
	if global_position.distance_squared_to(_ground_at) < 0.0004 and absf(heading - _ground_heading) < 0.002:
		return _ground_target
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(global_position) > ground_view_range:
		return _ground_target
	_ground_at = global_position
	_ground_heading = heading
	var turn := Basis(Vector3.UP, heading)
	var front := _ground_height(turn * Vector3(0.0, 0.0, -contact_span.y))
	var back := _ground_height(turn * Vector3(0.0, 0.0, contact_span.y))
	var target := Vector2.ZERO
	if not is_nan(front) and not is_nan(back) and contact_span.y > 0.0:
		target.x = atan2(front - back, contact_span.y * 2.0)
	if contact_span.x > 0.0:
		var left := _ground_height(turn * Vector3(-contact_span.x, 0.0, 0.0))
		var right := _ground_height(turn * Vector3(contact_span.x, 0.0, 0.0))
		if not is_nan(left) and not is_nan(right):
			target.y = atan2(right - left, contact_span.x * 2.0)
	var most := deg_to_rad(max_slope)
	_ground_target = target.clamp(Vector2(-most, -most), Vector2(most, most))
	return _ground_target


var _ground_target := Vector2.ZERO


## The world's height at `offset` from the vehicle (in the world's frame),
## from a ray down past the wheels, or NAN where it finds nothing near.
func _ground_height(offset: Vector3) -> float:
	var from := global_position + offset + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.6, Actor.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return NAN if hit.is_empty() else (hit.position as Vector3).y


## The interact target for a vehicle. It rides along on the vehicle and only
## exists on the interactables layer, so it never blocks anything.
## A passenger seat's anchors, for a passenger's pose (`ride_anchor`). It
## rides on the model, so it tips with the lean; it has the same anchor
## names as a vehicle, so the riding pose reads either.
class Pillion extends Node3D:
	var vehicle
	## Which of the vehicle's `seats` this is.
	var index := 0
	var seat_offset: Vector3:
		get: return vehicle.seats[index].offset
	var seat_point: Vector3:
		get: return vehicle.seats[index].point
	var grip_points: Array[Vector3]:
		get:
			var out: Array[Vector3] = []
			out.assign(vehicle.seats[index].grips)
			return out
	var peg_points: Array[Vector3]:
		get:
			var out: Array[Vector3] = []
			out.assign(vehicle.seats[index].pegs)
			return out
	var rider_lean: float:
		get: return vehicle.seats[index].lean


class Seat extends Interactable:
	## The vehicle this seat belongs to (untyped: this script has no class_name).
	var vehicle

	func get_prompt() -> String:
		return vehicle.get_prompt()

	func interact(actor: Actor) -> void:
		# The front seat first; with someone on it, behind them.
		if not vehicle.mount(actor, vehicle.rider != null):
			actor.notice.emit("Someone is riding it" if not vehicle.passenger_seat else "No room on it")
