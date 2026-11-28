extends RefCounted
## Getting on and off, and stopping (view only). The body's move onto and
## off the seat lives in the dressed skin (`ActorSkin._update_boarding`),
## which exists only with a display, so it is checked by eye; this checks
## what every machine shares: a stopped bike with a rider rests tipped onto
## the rider's left foot, and rights itself once it rolls.
## `-- --groups vehicle_mount` runs just these.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: getting on, off and stopping")
	var arena: Node3D = t._vehicle_arena()
	var bike = VehicleScript.new()
	bike.setup("bike_scrapper")
	arena.add_child(bike)
	bike.position = Vector3(-80, 0.3, -80)
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = Vector3(-77, 0.1, -80)
	await t.frames(30)
	t.check(absf(bike.lean) < 0.01, "parked with nobody on it, it stands upright (%.3f)" % bike.lean)
	bike.mount(rider)
	await t.frames(40)
	t.check(bike.lean < -0.05, "stopped with a rider, it rests on the rider's left foot (%.3f)" % bike.lean)
	rider.cmd.move = Vector2(0, 1)
	await t.frames(60)
	t.check(absf(bike.lean) < 0.03, "rolling straight, it rights itself (%.3f)" % bike.lean)
	rider.cmd.move = Vector2.ZERO
	bike.dismount()
	var rover = VehicleScript.new()
	rover.setup("rover_warden")
	arena.add_child(rover)
	rover.position = Vector3(-60, 0.4, -80)
	await t.frames(20)
	rover.mount(rider)
	await t.frames(40)
	t.check(absf(rover.lean) < 0.01, "a rover does not tip when stopped (%.3f)" % rover.lean)
	rover.dismount()
	arena.queue_free()
	await t.frames(2)
