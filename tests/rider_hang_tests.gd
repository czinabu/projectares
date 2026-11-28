extends RefCounted
## The rider hangs into a turn on a bike (Caleb: "leaning left or right into
## the bike and hoverbike ... like for the player model"). The bikes carry a
## `rider_hang` stat and the vehicle shows how hard it is turning in
## `steer_seen`, from how its heading swings, so the skin's pose
## (`Locomotion._ride_pose`) is the same in first and third person and on
## every machine. `-- --groups rider_hang` runs just these.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: the rider hangs into a turn")
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = Vector3(0, 0, -3400)
	var flat := StaticBody3D.new()
	flat.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(300, 1, 300)
	flat.add_child(shape)
	arena.add_child(flat)
	flat.position = Vector3(0, -0.5, 0)

	for id: String in ["bike_scrapper", "bike_raider"]:
		var v = VehicleScript.new()
		v.setup(id)
		t.check(v.rider_hang > 0.2, "%s's rider hangs into turns (%.2f rad at full lock)" % [id, v.rider_hang])
		v.queue_free()
	var rover = VehicleScript.new()
	rover.setup("rover_warden")
	t.check(is_equal_approx(rover.rider_hang, 0.0), "a wide body's rider sits upright")
	rover.queue_free()

	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	bike.pose_headless = true
	arena.add_child(bike)
	bike.position = Vector3(0, 1.0, 0)
	await t.frames(30)
	bike.set_physics_process(false)
	for turn: float in [0.03, -0.03]:
		for i in 40:
			bike.speed = 18.0
			bike.heading += turn
			bike.rotation.y = bike.heading
			await t.frames(1)
		var want := -signf(turn)
		t.check(bike.steer_seen * want > 0.5,
				"turning %s, the pose sees the steer (%.2f)" % ["left" if turn > 0.0 else "right", bike.steer_seen])
	for i in 40:
		bike.speed = 18.0
		await t.frames(1)
	t.check(absf(bike.steer_seen) < 0.1, "going straight, the rider sits square (%.2f)" % bike.steer_seen)
	arena.queue_free()
	await t.frames(2)
