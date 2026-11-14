extends RefCounted
## Checks for the Raider hoverbike (DESIGN.md section 8): it floats on a
## cushion instead of wheels, drifts through turns, glides over short gaps a
## wheeled bike falls into, hugs the ground off a ramp, climbs less than
## wheels, and carries a passenger behind the rider, which makes it heavier.
## Run from the main test runner. Nothing here starts a server.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")
## The gap the cushion must carry it over at top speed, in meters.
const GAP := 9.0


static func run(t: Node) -> void:
	print("Vehicles: the Raider hoverbike")
	_test_item(t)
	await _test_float_and_handling(t)
	await _test_gap(t)
	await _test_ramp_and_slope(t)
	await _test_passenger(t)


static func _test_item(t: Node) -> void:
	t.check(ItemDB.has_tag("bike_raider", "vehicle") and ItemDB.has_tag("bike_raider", "hover")
			and not ItemDB.has_tag("bike_scrapper", "hover"), "the Raider is a hover vehicle, the Scrapper keeps its wheels")
	t.check(ItemDB.item_stats("bike_raider").get("model") == "hoverbike"
			and ItemDB.item_stats("bike_scrapper").get("model", "bike") == "bike", "the two bikes have their own models")
	t.check(ItemDB.item_rarity("bike_raider") > ItemDB.item_rarity("bike_scrapper")
			and ItemDB.item_value("bike_raider") > ItemDB.item_value("bike_scrapper")
			and not ItemDB.has_tag("bike_raider", "vendor"), "the hoverbike is rarer and dearer, and never sold")
	var raider := ItemDB.item_stats("bike_raider")
	var scrapper := ItemDB.item_stats("bike_scrapper")
	t.check(float(raider.max_speed) > float(scrapper.max_speed) and float(raider.boost_speed) > float(scrapper.boost_speed)
			and float(raider.max_speed) >= FlightRig.CRUISE_SPEED * 1.5,
			"the hoverbike is a little faster than the Scrapper, and well over flight cruise")
	var toy: Node3D = VehicleScript.toy_model("bike_raider")
	var wheels := toy.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
			return m.mesh is CylinderMesh and absf(m.rotation.z) > 1.0)
	var thrusters := toy.find_children("Thruster*", "MeshInstance3D", true, false)
	t.check(wheels.is_empty() and thrusters.size() == 4, "its toy is the hoverbike: four thrusters, no wheels")
	toy.free()


## A hoverbike on flat ground with a rider on it.
static func _spawn(t: Node, arena: Node3D, id: String, at: Vector3, rider: Actor) -> Node3D:
	var bike = VehicleScript.new()
	bike.setup(id)
	arena.add_child(bike)
	bike.global_position = arena.global_position + at
	await t.frames(20)
	if rider != null:
		rider.global_position = bike.global_position + Vector3(2.5, 0.1, 0)
		await t.frames(2)
		bike.mount(rider)
	return bike


static func _clear(rider: Actor) -> void:
	rider.cmd.move = Vector2.ZERO
	rider.cmd.sprint = false


static func _test_float_and_handling(t: Node) -> void:
	var arena: Node3D = t._vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	var bike: Node3D = await _spawn(t, arena, "bike_raider", Vector3(0, 0.6, 0), null)
	var model: Node3D = bike.get_node("Model")
	t.check(bike.is_on_floor() and bike.hovers, "a parked hoverbike settles on its cushion")
	var gap: float = t._lowest_point(model) - arena.global_position.y
	t.check(gap > 0.3 and gap < 0.6, "it floats with daylight under it (%.2f m)" % gap)
	var bob := {"lo": INF, "hi": -INF}
	for i in 90:
		await t.frames(1)
		bob.lo = minf(bob.lo, model.position.y)
		bob.hi = maxf(bob.hi, model.position.y)
	t.check(bob.hi - bob.lo > 0.02 and bob.hi - bob.lo < 0.1, "and bobs gently on it (%.3f m)" % (bob.hi - bob.lo))
	t.check(bike.get_node_or_null("Model/Pillion") != null and bike.get_prompt().contains("Ride"),
			"it has a pillion seat and offers a ride")

	rider.global_position = bike.global_position + Vector3(2.5, 0.1, 0)
	await t.frames(2)
	t.check(bike.mount(rider), "the rider gets on")
	await t.frames(2)
	var eye_up: float = rider.get_eye_position().y - bike.global_position.y
	t.check(eye_up > 1.3 and eye_up < 1.9, "the rider sits on it (eyes %.2f m up)" % eye_up)
	# A slow turn on the spot, which wheels cannot do.
	rider.cmd.move = Vector2(1, 0)
	var start: Vector3 = bike.global_position
	var heading: float = bike.heading
	await t.frames(30)
	t.check(bike.heading < heading - 0.25 and bike.global_position.distance_to(start) < 0.5,
			"it turns slowly on the spot (%.2f rad)" % (heading - bike.heading))
	rider.cmd.move = Vector2(0, 1)
	await t.frames(240)
	t.check(bike.speed > float(ItemDB.item_stats("bike_scrapper").max_speed), "it tops the Scrapper's speed (%.1f m/s)" % bike.speed)
	# A hard turn at speed: the nose comes round first and the course follows.
	rider.cmd.move = Vector2(-1, 1)
	var slipped := 0.0
	for i in 20:
		await t.frames(1)
		slipped = maxf(slipped, absf(bike.slip))
	var course: Vector3 = Vector3(bike.velocity.x, 0, bike.velocity.z).normalized()
	var nose: Vector3 = Basis(Vector3.UP, bike.heading) * Vector3.FORWARD
	t.check(slipped > 0.1 and course.signed_angle_to(nose, Vector3.UP) > 0.05,
			"it drifts through a turn, its course trailing the nose (%.2f rad)" % slipped)
	t.check(bike.lean < -0.15, "and leans hard into it (%.2f)" % bike.lean)
	rider.cmd.move = Vector2(0, 1)
	await t.frames(60)
	t.check(absf(bike.slip) < 0.02, "straightened out, the drift closes (%.3f)" % bike.slip)
	# Floaty: it coasts much further than a wheeled bike before it stops.
	rider.cmd.move = Vector2.ZERO
	var coast_from: float = bike.speed
	await t.frames(60)
	t.check(bike.speed > coast_from - 4.0, "off the throttle it glides on (%.1f to %.1f m/s)" % [coast_from, bike.speed])
	_clear(rider)
	bike.dismount()
	arena.queue_free()
	await t.frames(2)


## Two ledges `GAP` apart over a deep pit. The hoverbike glides across at
## top speed; the Scrapper drops into it.
static func _test_gap(t: Node) -> void:
	var results := {}
	for id: String in ["bike_raider", "bike_scrapper"]:
		var arena := Node3D.new()
		arena.name = "GapArena"
		t.add_child(arena)
		arena.position = Vector3(0, 0, 3000)
		for spot: Array in [[Vector3(0, -0.5, 40), Vector3(10, 1, 80)], [Vector3(0, -0.5, -GAP - 40), Vector3(10, 1, 80)],
				[Vector3(0, -40.5, 0), Vector3(200, 1, 400)]]:
			var ground := StaticBody3D.new()
			ground.collision_layer = Actor.LAYER_WORLD
			var shape := BoxShape3D.new()
			shape.size = spot[1]
			var col := CollisionShape3D.new()
			col.shape = shape
			ground.add_child(col)
			ground.position = spot[0]
			arena.add_child(ground)
		var rider := Actor.new()
		arena.add_child(rider)
		var bike: Node3D = await _spawn(t, arena, id, Vector3(0, 0.6, 70), rider)
		rider.cmd.move = Vector2(0, 1)
		rider.cmd.sprint = true
		var across := false
		for i in 360:
			await t.frames(1)
			if bike.global_position.z < arena.global_position.z - GAP - 6.0:
				across = bike.global_position.y > arena.global_position.y - 1.0
				break
			if bike.global_position.y < arena.global_position.y - 6.0:
				break
		results[id] = across
		_clear(rider)
		bike.dismount()
		arena.queue_free()
		await t.frames(2)
	t.check(results.bike_raider, "the hoverbike glides over a %d m gap at speed" % GAP)
	t.check(not results.bike_scrapper, "where the wheeled Scrapper drops into it")


## Off the same ramp the wheeled bike flies higher; and the hoverbike gives
## up on a slope the wheels still climb.
static func _test_ramp_and_slope(t: Node) -> void:
	var tops := {}
	for id: String in ["bike_raider", "bike_scrapper"]:
		var arena: Node3D = t._vehicle_arena()
		var rider := Actor.new()
		arena.add_child(rider)
		var bike: Node3D = await _spawn(t, arena, id, Vector3(60, 0.6, 0), rider)
		rider.cmd.move = Vector2(0, 1)
		rider.cmd.sprint = true
		var top := 0.0
		for i in 240:
			await t.frames(1)
			top = maxf(top, bike.global_position.y - arena.global_position.y)
		tops[id] = top
		_clear(rider)
		bike.dismount()
		arena.queue_free()
		await t.frames(2)
	t.check(tops.bike_raider > 1.0 and tops.bike_raider < tops.bike_scrapper - 0.4,
			"off a ramp the hoverbike hugs the ground: %.1f m up against the wheels' %.1f m" % [tops.bike_raider, tops.bike_scrapper])

	var climbs := {}
	for id: String in ["bike_raider", "bike_scrapper"]:
		var arena: Node3D = t._vehicle_arena()
		# A 35 degree bank rising toward -Z, long enough to tell.
		var angle := deg_to_rad(35.0)
		var hill := StaticBody3D.new()
		hill.collision_layer = Actor.LAYER_WORLD
		var shape := BoxShape3D.new()
		shape.size = Vector3(12, 0.4, 20)
		var col := CollisionShape3D.new()
		col.shape = shape
		hill.add_child(col)
		hill.position = Vector3(-60, 10.0 * sin(angle) - 0.2 * cos(angle), -40)
		hill.basis = Basis(Vector3.RIGHT, angle)
		arena.add_child(hill)
		var rider := Actor.new()
		arena.add_child(rider)
		var bike: Node3D = await _spawn(t, arena, id, Vector3(-60, 0.6, -24), rider)
		rider.cmd.move = Vector2(0, 0.6)
		var top := 0.0
		for i in 150:
			await t.frames(1)
			top = maxf(top, bike.global_position.y - arena.global_position.y)
		climbs[id] = top
		_clear(rider)
		bike.dismount()
		arena.queue_free()
		await t.frames(2)
	t.check(climbs.bike_scrapper > 3.0 and climbs.bike_raider < climbs.bike_scrapper - 1.5,
			"a steep bank the wheels climb (%.1f m) stops the hoverbike (%.1f m)" % [climbs.bike_scrapper, climbs.bike_raider])


## Accelerates from a stop for `ticks` with full throttle and returns
## [speed, heading turned in a hard turn after it].
static func _run_up(t: Node, bike: Node3D, rider: Actor, ticks: int) -> Array:
	bike.speed = 0.0
	bike.slip = 0.0
	bike.velocity = Vector3.ZERO
	rider.cmd.move = Vector2(0, 1)
	await t.frames(ticks)
	var speed: float = bike.speed
	var heading: float = bike.heading
	rider.cmd.move = Vector2(-1, 1)
	await t.frames(30)
	var turned: float = bike.heading - heading
	rider.cmd.move = Vector2(0, -1)
	await t.frames(90)
	rider.cmd.move = Vector2.ZERO
	return [speed, turned]


static func _test_passenger(t: Node) -> void:
	var arena: Node3D = t._vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	var bike: Node3D = await _spawn(t, arena, "bike_raider", Vector3(0, 0.6, 120), rider)
	var seat: Interactable = bike.get_node("Seat")
	t.check(bike.rider == rider and seat.get_prompt().contains("behind"), "with a rider aboard it offers the seat behind")
	var solo: Array = await _run_up(t, bike, rider, 60)

	var friend := Actor.new()
	arena.add_child(friend)
	friend.global_position = bike.global_position + Vector3(-2.5, 0.1, 0.5)
	await t.frames(2)
	seat.interact(friend)
	t.check(bike.passenger == friend and friend.vehicle == bike and bike.rider == rider,
			"a second player sits behind the rider")
	await t.frames(2)
	var local: Vector3 = Basis(Vector3.UP, bike.heading).inverse() * (friend.global_position - bike.global_position)
	var front: Vector3 = Basis(Vector3.UP, bike.heading).inverse() * (rider.global_position - bike.global_position)
	t.check(local.z > front.z + 0.3 and absf(local.x) < 0.1, "the passenger sits right behind the rider")
	var eye_up: float = friend.get_eye_position().y - bike.global_position.y
	t.check(eye_up > 1.3 and eye_up < 2.0, "seated, not standing (eyes %.2f m up)" % eye_up)
	t.check(bike.ride_anchor(friend) != bike and bike.ride_anchor(rider) == bike
			and bike.ride_anchor(friend).get("seat_point").z > bike.seat_point.z,
			"the passenger's pose is fitted to the pillion seat")
	var third := Actor.new()
	arena.add_child(third)
	third.global_position = bike.global_position + Vector3(2.5, 0.1, -0.5)
	await t.frames(2)
	t.check(not bike.mount(third) and not bike.mount(third, true) and third.vehicle == null, "a third cannot get on")
	third.queue_free()
	friend.cmd.move = Vector2(1, 0)
	var two: Array = await _run_up(t, bike, rider, 60)
	t.check(friend.global_position.distance_to(bike.global_position) < 1.5, "the passenger rides along")
	t.check(two[0] < solo[0] - 0.5, "two up it picks up speed slower (%.1f against %.1f m/s)" % [two[0], solo[0]])
	t.check(two[1] < solo[1] - 0.05, "and turns wider (%.2f against %.2f rad)" % [two[1], solo[1]])
	t.check(bike.speed <= bike.max_speed * bike.laden_speed + 0.01, "with a lower top speed")
	friend.cmd.move = Vector2.ZERO

	# The passenger hops off with F; the rider rides on, back to full speed.
	friend.cmd.interact_pressed = true
	await t.frames(1)
	friend.cmd.interact_pressed = false
	t.check(bike.passenger == null and friend.vehicle == null and bike.rider == rider,
			"F lets the passenger off and the rider stays on")
	var off: float = friend.global_position.distance_to(bike.global_position)
	t.check(off > 0.8 and off < 2.5, "they step off beside it")
	var again: Array = await _run_up(t, bike, rider, 60)
	t.check(absf(again[0] - solo[0]) < 0.3, "alone again it is as quick as before")

	# The rider gets off and the passenger stays aboard: still occupied.
	friend.global_position = bike.global_position + Vector3(-2.5, 0.1, 0.5)
	await t.frames(2)
	seat.interact(friend)
	bike.dismount()
	t.check(bike.rider == null and bike.passenger == friend and bike.is_occupied(),
			"the rider getting off leaves the passenger sitting")
	friend.kill("test")
	await t.frames(2)
	t.check(bike.passenger == null and not bike.is_occupied(), "a passenger's death leaves the seat empty")
	arena.queue_free()
	await t.frames(2)
