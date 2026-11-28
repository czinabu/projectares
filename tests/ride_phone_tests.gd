extends RefCounted
## The phone while riding (Caleb's bug: "the phone is unusable while in
## vehicles"). The phone came up only on foot, so on a vehicle nothing was in
## the hand: no screen to read, no hologram in third person and every click
## missed. Now the rider takes the right hand off the bar for it and the left
## keeps its grip (`Locomotion.phone_pose`). The pose itself is checked by eye
## (a dressed body exists only with a display); these check the shared state
## every view reads. `-- --groups ride_phone` runs just these.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Phone: out while riding")
	var arena: Node3D = t._vehicle_arena()
	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	arena.add_child(bike)
	bike.position = Vector3(0, 0.3, 0)
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(3, 0.1, 0)
	await t.frames(20)
	t.check(bike.mount(rider), "the rider gets on")
	var controller := PlayerController.new()
	controller.setup(rider)
	arena.add_child(controller)
	# Rolling along, then the phone comes out.
	controller.set_physics_process(false)
	rider.cmd.move = Vector2(0, 1)
	await t.frames(60)
	t.check(bike.speed > 5.0, "the bike is moving (%.1f m/s)" % bike.speed)
	controller.set_physics_process(true)
	controller.phone_out = true
	controller.input_blocked = true
	await t.frames(30)
	var pose := ActionPose.of(rider)
	t.check(rider.cmd.phone and pose.phone > 0.99,
			"the phone comes up in the hand on a vehicle too (%.2f), so its screen can be read and clicked" % pose.phone)
	t.check(rider.vehicle == bike, "and the rider stays seated")
	t.check(rider.cmd.move == Vector2.ZERO and not rider.cmd.jump,
			"hands on the phone: no throttle, steering or handbrake reach the vehicle")
	var before: float = bike.speed
	await t.frames(30)
	t.check(bike.speed < before, "so the vehicle coasts down (%.1f to %.1f m/s)" % [before, bike.speed])
	controller.phone_out = false
	controller.input_blocked = false
	await t.frames(40)
	t.check(not rider.cmd.phone and pose.phone < 0.01, "putting it away gives both hands back to the bars")
	bike.dismount()
	controller.queue_free()
	arena.queue_free()
	await t.frames(2)
