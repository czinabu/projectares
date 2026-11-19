extends RefCounted
## The `rover_crew` checks. The test runner finds this file by itself and calls
## `run(t)`.
##
## The lowest point of every mesh under `node`, in world height.
## The Warden Rover seats four (Caleb's call): a driver, a front passenger
## and two behind, each climbing in at the seat nearest them.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: the rover's crew of four")
	var arena: Node3D = t._vehicle_arena()
	var rover = VehicleScript.new()
	rover.setup("rover_warden")
	arena.add_child(rover)
	rover.position = Vector3(0, 0.5, 0)
	await t.frames(20)
	t.check(rover.seats.size() == 3 and rover.get_node_or_null("Model/Pillion") != null
			and rover.get_node_or_null("Model/Pillion3") != null, "the rover has three passenger seats")
	var crew: Array[Actor] = []
	for i in 4:
		var actor := Actor.new()
		arena.add_child(actor)
		crew.append(actor)
	var seat: Interactable = rover.get_node("Seat")
	# Each walks up to a different door: front left, rear right, rear left, front right.
	var doors := [Vector3(-2.2, 0.1, 0.2), Vector3(2.2, 0.1, 1.5), Vector3(-2.2, 0.1, 1.5), Vector3(2.2, 0.1, 0.2)]
	for i in 4:
		crew[i].global_position = rover.global_position + Vector3(doors[i])
		await t.frames(2)
		seat.interact(crew[i])
	t.check(rover.rider == crew[0] and rover.passenger_count() == 3, "four climb in: a driver and three passengers")
	t.check(rover.seat_of(crew[3]) == 0 and rover.seat_of(crew[1]) == 2 and rover.seat_of(crew[2]) == 1,
			"each passenger takes the seat by the door they came to")
	var late := Actor.new()
	arena.add_child(late)
	late.global_position = rover.global_position + Vector3(2.2, 0.1, 1.5)
	await t.frames(2)
	t.check(not rover.mount(late, true) and late.vehicle == null and "ridden" in rover.get_prompt(),
			"a fifth finds no room")
	await t.frames(2)
	var anchors := {}
	for i in range(1, 4):
		var anchor: Node3D = rover.ride_anchor(crew[i])
		anchors[anchor] = true
		var local: Vector3 = Basis(Vector3.UP, rover.heading).inverse() * (crew[i].global_position - rover.global_position)
		var spot: Vector3 = rover.seats[rover.seat_of(crew[i])].offset
		t.check(local.distance_to(spot) < 0.05, "passenger %d sits on their seat" % i)
		var grips: Array[Vector3] = anchor.get("grip_points")
		t.check(grips.size() == 2 and grips[0].z < anchor.get("seat_point").z and grips[0].y > anchor.get("seat_point").y,
				"passenger %d has handholds ahead of and above their seat" % i)
	t.check(anchors.size() == 3 and not anchors.has(rover), "every passenger's pose is fitted to their own seat")
	var front: Vector3 = Basis(Vector3.UP, rover.heading).inverse() * (crew[0].global_position - rover.global_position)
	var back: Vector3 = Basis(Vector3.UP, rover.heading).inverse() * (crew[1].global_position - rover.global_position)
	t.check(back.z > front.z + 0.8 and back.y > front.y, "the back seats are behind the front ones, and raised")
	crew[0].cmd.move = Vector2(0, 1)
	await t.frames(240)
	t.check(rover.speed > FlightRig.CRUISE_SPEED and rover.speed <= rover.max_speed * pow(rover.laden_speed, 3) + 0.05,
			"full, it still outruns flight cruise, a little slower (%.1f m/s)" % rover.speed)
	for actor in crew:
		t.check(actor.global_position.distance_to(rover.global_position) < 2.5, "the crew rides along")
	crew[0].cmd.move = Vector2.ZERO
	await t.frames(120)
	crew[2].cmd.interact_pressed = true
	await t.frames(1)
	crew[2].cmd.interact_pressed = false
	t.check(crew[2].vehicle == null and rover.passenger_count() == 2 and rover.rider == crew[0],
			"F lets one passenger off and the rest stay")
	var out: Vector3 = Basis(Vector3.UP, rover.heading).inverse() * (crew[2].global_position - rover.global_position)
	t.check(out.x < -1.2 and out.z > 0.8, "they step out of their own side, at the back")
	crew[3].kill("test")
	await t.frames(2)
	t.check(rover.seat_of(crew[3]) < 0 and rover.passenger_count() == 1, "a passenger's death empties their seat")
	rover.dismount_all()
	t.check(not rover.is_occupied(), "everyone gets out")
	arena.queue_free()
	await t.frames(2)
