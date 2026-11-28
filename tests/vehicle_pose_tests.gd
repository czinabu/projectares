extends RefCounted
## How a vehicle's body sits (view only, `Vehicle._pose_model`): tipped to
## the slope under its wheels, dipping its nose under braking and squatting
## under the throttle without a wheel sinking into the ground, and leaning
## into a turn from how its heading swings, so one moved from the server
## leans the same as the one you drive. `-- --groups vehicle_pose` runs just
## these.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: the body's pose")
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = Vector3(0, 0, -2600)
	var slope := deg_to_rad(14.0)
	var hill := StaticBody3D.new()
	hill.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(30, 1, 30)
	hill.add_child(shape)
	arena.add_child(hill)
	hill.position = Vector3(0, -0.5, 0)
	hill.rotation.x = slope
	var flat := StaticBody3D.new()
	flat.collision_layer = Actor.LAYER_WORLD
	var flat_shape := CollisionShape3D.new()
	flat_shape.shape = BoxShape3D.new()
	flat_shape.shape.size = Vector3(300, 1, 300)
	flat.add_child(flat_shape)
	arena.add_child(flat)
	flat.position = Vector3(200, -0.5, 0)

	# Parked on the hill, facing up it (-Z rises with a positive tilt about X).
	for id: String in ["bike_scrapper", "rover_warden"]:
		var v = VehicleScript.new()
		v.setup(id)
		v.pose_headless = true
		arena.add_child(v)
		v.position = Vector3(0, 3.0, 0)
		await t.frames(90)
		var model: Node3D = v.get_node("Model")
		var pitch := model.rotation.x
		t.check(absf(pitch - slope) < 0.04, "%s parked up a %.0f degree slope tips its nose up with it (%.1f degrees)"
				% [id, rad_to_deg(slope), rad_to_deg(pitch)])
		# Turned side-on, a wide body rolls to it and a bike does not.
		v.heading = PI / 2.0
		v.rotation.y = v.heading
		await t.frames(60)
		var roll := absf(model.rotation.z)
		if id == "rover_warden":
			# Each side's wheels sit on the hill, the uphill side up.
			var off := 0.0
			for side: float in [-1.0, 1.0]:
				var at: Vector3 = model.global_transform * Vector3(side * v.contact_span.x, 0, 0)
				var ground_y: float = hill.global_position.y + 0.5 / cos(slope) - (at.z - hill.global_position.z) * tan(slope)
				off = maxf(off, absf(at.y - ground_y))
			t.check(absf(roll - slope) < 0.05 and absf(model.rotation.x) < 0.04 and off < 0.08,
					"side-on, the rover rolls to the slope instead, both sides on it (%.1f degrees, %.2f m off)"
					% [rad_to_deg(roll), off])
		else:
			t.check(roll < 0.03, "side-on, a bike stays upright: it leans only into turns (%.1f degrees)" % rad_to_deg(roll))
		v.queue_free()
	await t.frames(2)

	# On the flat: the spring.
	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	bike.pose_headless = true
	arena.add_child(bike)
	bike.position = Vector3(200, 0.4, 100)
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(203, 0.1, 100)
	await t.frames(30)
	bike.mount(rider)
	var model: Node3D = bike.get_node("Model")
	var dip := {"low": INF, "pitch_max": -INF, "pitch_min": INF}
	var watch := func() -> void:
		var low := INF
		for wheel_z: float in [-bike.contact_span.y, bike.contact_span.y]:
			low = minf(low, (model.transform * Vector3(0, 0, wheel_z)).y)
		dip.low = minf(dip.low, low)
	t.get_tree().process_frame.connect(watch)
	rider.cmd.move = Vector2(0, 1)
	for i in 30:
		await t.frames(1)
		dip.pitch_max = maxf(dip.pitch_max, bike._sway)
	t.check(dip.pitch_max > 0.03, "the throttle squats the tail and lifts the nose (%.3f rad)" % dip.pitch_max)
	await t.frames(60)
	rider.cmd.move = Vector2(0, -1)
	for i in 30:
		await t.frames(1)
		dip.pitch_min = minf(dip.pitch_min, bike._sway)
	t.check(dip.pitch_min < -0.03, "braking dips the nose (%.3f rad)" % dip.pitch_min)
	t.check(dip.low > -0.01, "and the wheel it tips over stays on the ground (lowest %.3f m)" % dip.low)
	t.get_tree().process_frame.disconnect(watch)
	rider.cmd.move = Vector2.ZERO
	bike.dismount()
	await t.frames(60)

	# Moved from outside (as a client moves one the server drives): it leans
	# into the turn from how its heading swings.
	bike.set_physics_process(false)
	for i in 40:
		bike.speed = 18.0
		bike.heading += 0.03
		bike.rotation.y = bike.heading
		await t.frames(1)
	t.check(bike.lean < -0.1 and model.rotation.z > 0.1,
			"a vehicle moved from outside leans into its turn too (%.2f)" % bike.lean)
	arena.queue_free()
	await t.frames(2)
