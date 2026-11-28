extends RefCounted
## A vehicle's moving parts (view only, `Vehicle._turn_parts`): the wheels
## spin with the speed, the fork, bars, steering wheel and a hover's rudders
## turn with the steering, and the rider's hands go with the bars
## (`posed_grips`). `-- --groups vehicle_parts` runs just these.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: moving parts")
	var arena: Node3D = t._vehicle_arena()
	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	arena.add_child(bike)
	bike.position = Vector3(60, 0.3, 60)
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(63, 0.1, 60)
	await t.frames(20)
	var model: Node3D = bike.get_node("Model")
	var steer: Node3D = model.get_node_or_null("Steer")
	var wheels := model.find_children("Wheel*", "Node3D", true, false)
	t.check(steer != null and wheels.size() == 2 and steer.get_node_or_null("WheelFront") != null,
			"a bike has two wheels, the front one on the fork that steers")
	var spin: Node3D = (wheels[0] as Node3D).get_node("Spin")
	bike.mount(rider)
	var before := spin.basis
	rider.cmd.move = Vector2(0, 1)
	await t.frames(40)
	t.check(not spin.basis.is_equal_approx(before), "the wheels spin as it rolls")
	var straight: Array[Vector3] = bike.posed_grips()
	rider.cmd.move = Vector2(1, 1)
	await t.frames(20)
	t.check(bike.steer_view < -0.05 and steer.basis.get_euler().y < -0.02,
			"steering right turns the fork and bars right (%.2f)" % bike.steer_view)
	var turned: Array[Vector3] = bike.posed_grips()
	t.check(turned[1].z > straight[1].z + 0.01 and turned[0].z < straight[0].z - 0.01,
			"the hands go with the bars: the right grip comes back, the left goes forward")
	rider.cmd.move = Vector2(0, 0)
	await t.frames(90)
	t.check(absf(bike.steer_view) < 0.03, "going straight, the bars come back to centre (%.2f)" % bike.steer_view)
	bike.dismount()

	for id: String in ["rover_warden", "bike_raider"]:
		var v = VehicleScript.new()
		v.setup(id)
		arena.add_child(v)
		v.position = Vector3(-60, 0.4, -60 if id == "rover_warden" else 60)
		await t.frames(5)
		var m: Node3D = v.get_node("Model")
		if id == "rover_warden":
			var steering := m.find_children("Wheel*", "Node3D", true, false).filter(
					func(w: Node) -> bool: return w.get_meta("steers", false))
			t.check(steering.size() == 2 and m.get_node_or_null("SteerWheel") != null,
					"the rover steers its two front wheels and has a steering wheel that turns")
		else:
			t.check(m.find_children("Wheel*", "Node3D", true, false).is_empty()
					and m.get_node_or_null("Fin0") != null and m.get_node_or_null("Steer") != null,
					"the hoverbike has no wheels, but bars and rudder fins that turn")
		v.set_physics_process(false)
		for i in 30:
			v.speed = 10.0
			v.heading -= 0.03
			v.rotation.y = v.heading
			await t.frames(1)
		var turner: Node3D = m.get_node("SteerWheel") if id == "rover_warden" else m.get_node("Fin0")
		t.check(v.steer_view < -0.05 and not turner.basis.is_equal_approx(Basis.IDENTITY),
				"%s: turning right turns its parts too (%.2f)" % [id, v.steer_view])
		v.queue_free()
	arena.queue_free()
	await t.frames(2)
