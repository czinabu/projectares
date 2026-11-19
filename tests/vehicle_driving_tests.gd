extends RefCounted
## The `vehicle_driving` checks. The test runner finds this file by itself and calls
## `run(t)`.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: driving")
	var arena: Node3D = t._vehicle_arena()
	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	arena.add_child(bike)
	bike.position = Vector3(0, 0.3, 0)
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(3, 0.1, 0)
	await t.frames(20)
	t.check(bike.is_on_floor() and is_equal_approx(bike.max_speed, 24.0), "a bike settles and takes its item stats")
	var seat: Interactable = bike.get_node("Seat")
	t.check(seat.get_prompt().contains("Ride"), "a parked bike offers a ride")
	# The rider stands 3 m to the bike's +X side; yaw PI/2 faces -X.
	rider.cmd.yaw = PI / 2.0
	rider.cmd.pitch = -0.4
	t.check(rider.find_interactable() == seat, "looking at a bike targets its seat")
	rider.cmd.yaw = 0.0
	rider.cmd.pitch = 0.0
	seat.interact(rider)
	t.check(rider.vehicle == bike and bike.rider == rider, "interacting gets you on")
	# Seated, not standing on the bike: the eyes (and the head a shot finds)
	# are about where a seated rider's are, and the pose's anchors line up.
	await t.frames(2)
	var eye_up: float = rider.get_eye_position().y - bike.global_position.y
	t.check(eye_up > 1.3 and eye_up < 1.8, "a rider sits low on the bike (eyes %.2f m up)" % eye_up)
	var seat_at: Vector3 = bike.seat_point
	t.check(bike.grip_points.size() == 2 and bike.peg_points.size() == 2, "a bike has two grips and two pegs")
	t.check(bike.grip_points[0].x < 0.0 and bike.grip_points[1].x > 0.0 and bike.peg_points[0].x < 0.0 \
			and bike.peg_points[1].x > 0.0, "grips and pegs are listed left then right")
	t.check(bike.grip_points[0].z < seat_at.z and bike.grip_points[0].y > seat_at.y and bike.peg_points[0].y < seat_at.y,
			"grips are ahead of and above the seat, pegs below it")

	var start: Vector3 = bike.global_position
	rider.cmd.move = Vector2(0, 1)
	await t.frames(120)
	var dist: float = bike.global_position.distance_to(start)
	t.check(dist > rider.sprint_speed * 2.0, "the bike outruns sprinting (%.1f m in 2 s)" % dist)
	t.check(bike.global_position.z < start.z - 10.0, "throttle drives the way the bike points")
	t.check(rider.global_position.distance_to(bike.global_position) < 1.0, "the rider stays on the seat")
	rider.cmd.sprint = true
	await t.frames(90)
	t.check(bike.speed > bike.max_speed + 1.0, "sprint boosts past normal top speed (%.1f)" % bike.speed)
	rider.cmd.sprint = false
	rider.cmd.move = Vector2(-1, 1)
	var heading_before: float = bike.heading
	await t.frames(30)
	t.check(bike.heading > heading_before + 0.3, "A steers left")
	var model: Node3D = bike.get_node("Model")
	t.check(bike.lean < -0.05 and model.rotation.z > 0.05, "the bike leans into a left turn (%.2f)" % bike.lean)
	rider.cmd.move = Vector2(0, -1)
	await t.frames(60)
	t.check(bike.speed < 1.0, "S brakes the bike to a stop")
	rider.cmd.move = Vector2.ZERO
	await t.frames(30)

	rider.cmd.interact_pressed = true
	await t.frames(1)
	rider.cmd.interact_pressed = false
	t.check(rider.vehicle == null and bike.rider == null, "F gets you off")
	var off: float = rider.global_position.distance_to(bike.global_position)
	t.check(off > 0.8 and off < 2.5, "you step off beside the bike")
	var walk_from := rider.global_position
	rider.cmd.move = Vector2(0, 1)
	await t.frames(30)
	rider.cmd.move = Vector2.ZERO
	t.check(rider.global_position.distance_to(walk_from) > 1.0, "back on foot, you walk again")

	# Anyone can take a parked bike, but not one that is being ridden.
	var thief := Actor.new()
	arena.add_child(thief)
	thief.position = bike.position + Vector3(-2, 0, 0)
	await t.frames(5)
	seat.interact(thief)
	t.check(thief.vehicle == bike, "someone else can take a parked bike")
	seat.interact(rider)
	t.check(rider.vehicle == null and bike.rider == thief, "a ridden bike cannot be taken")
	thief.kill("test")
	await t.frames(2)
	t.check(bike.rider == null and thief.vehicle == null, "the rider's death leaves the bike behind")

	# Ramp jump, and bailing out mid-air keeps the momentum.
	bike.position = Vector3(60, 0.3, 0)
	bike.heading = 0.0
	bike.speed = 0.0
	bike.velocity = Vector3.ZERO
	await t.frames(5)
	seat.interact(rider)
	rider.cmd.move = Vector2(0, 1)
	rider.cmd.sprint = true
	var top := 0.0
	var air := 0.0
	var bailed := false
	var bail_speed := 0.0
	for i in 240:
		await t.frames(1)
		top = maxf(top, bike.position.y)
		air = maxf(air, bike.airborne_time)
		if not bailed and bike.airborne_time > 0.2:
			rider.cmd.interact_pressed = true
			bailed = true
		elif bailed and bail_speed == 0.0:
			rider.cmd.interact_pressed = false
			bail_speed = rider.velocity.length()
			t.check(rider.vehicle == null and not rider.is_on_floor(), "you can bail out mid-air")
	t.check(air > 0.4 and top > 2.5, "a ramp launches the bike (%.2f s in the air, %.1f m up)" % [air, top])
	t.check(bail_speed > 10.0, "bailing out keeps the bike's momentum (%.1f m/s)" % bail_speed)
	arena.queue_free()
	await t.frames(2)
