extends RefCounted
## Vehicles hitting things (`Vehicle._collide`; Caleb: "vehicles currently
## stop anytime they collide with anything no matter how small it is ... if
## you bump into someone they just slow down instead of react normally"). A
## low lip is driven over, a wall glanced off keeps most of the speed and
## turns the nose away, a wall hit head on bounces back, and two vehicles
## that meet trade speed by weight and are shoved and spun.
## `-- --groups vehicle_bump` runs just these.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func _box(arena: Node3D, size: Vector3, at: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = size
	body.add_child(col)
	arena.add_child(body)
	body.position = at
	body.rotation.y = yaw
	return body


## A bike with a rider holding the throttle, pointing `yaw`, at `at`.
static func _ride(t: Node, arena: Node3D, id: String, at: Vector3, yaw: float) -> Array:
	var bike = VehicleScript.new()
	bike.setup(id)
	arena.add_child(bike)
	bike.position = at
	bike.heading = yaw
	bike.rotation.y = yaw
	var rider := Actor.new()
	arena.add_child(rider)
	rider.position = at + Vector3(2, 0, 0)
	await t.frames(5)
	bike.mount(rider)
	return [bike, rider]


static func _clear(arena: Node3D, ride: Array) -> void:
	ride[0].dismount()
	ride[0].queue_free()
	ride[1].queue_free()


static func run(t: Node) -> void:
	print("Vehicles: hitting things")
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = Vector3(4200, 0, 4200)
	_box(arena, Vector3(400, 1, 400), Vector3(0, -0.5, 0))

	# A plank across the way, lower than a wheel: driven over at speed.
	_box(arena, Vector3(8, 0.2, 0.4), Vector3(0, 0.1, -30))
	var ride: Array = await _ride(t, arena, "bike_scrapper", Vector3(0, 0.3, 0), 0.0)
	var bike = ride[0]
	ride[1].cmd.move = Vector2(0, 1)
	var slowest := INF
	for i in 200:
		await t.frames(1)
		if bike.position.z < -20.0 and bike.position.z > -40.0:
			slowest = minf(slowest, bike.speed)
	t.check(bike.position.z < -40.0 and slowest > 12.0,
			"a plank lower than a wheel is ridden over (slowest %.1f m/s, at z %.1f)" % [slowest, bike.position.z])
	_clear(arena, ride)
	await t.frames(2)

	# A wall met at a shallow angle: it scrapes past, keeping most of its
	# speed, and the nose swings away from the wall.
	_box(arena, Vector3(1, 4, 120), Vector3(-60, 2, -40))
	ride = await _ride(t, arena, "bike_scrapper", Vector3(-55, 0.3, 20), 0.0)
	bike = ride[0]
	ride[1].cmd.move = Vector2(0, 1)
	await t.frames(60)
	var before: float = bike.speed
	bike.heading += deg_to_rad(20.0)
	bike.rotation.y = bike.heading
	var hit_speed := 0.0
	var hit := false
	for i in 90:
		await t.frames(1)
		if not hit and bike.position.x < -58.6:
			hit = true
		if hit and hit_speed == 0.0 and absf(bike.spin) > 0.0:
			hit_speed = bike.speed
	t.check(hit and hit_speed > before * 0.6,
			"a wall glanced at 20 degrees keeps most of the speed (%.1f of %.1f m/s)" % [hit_speed, before])
	t.check(wrapf(bike.heading, -PI, PI) < deg_to_rad(10.0),
			"and the nose turns away from the wall (%.0f degrees)" % rad_to_deg(wrapf(bike.heading, -PI, PI)))
	_clear(arena, ride)
	await t.frames(2)

	# Head on into a wall: it bounces back, it does not just stop.
	_box(arena, Vector3(20, 4, 1), Vector3(60, 2, -40))
	ride = await _ride(t, arena, "bike_scrapper", Vector3(60, 0.3, 0), 0.0)
	bike = ride[0]
	ride[1].cmd.move = Vector2(0, 1)
	var back := 0.0
	for i in 220:
		await t.frames(1)
		if bike.position.z > -36.0 and bike.speed < 0.0:
			ride[1].cmd.move = Vector2.ZERO
		back = minf(back, bike.speed)
	t.check(back < -2.0, "head on into a wall it bounces back (%.1f m/s)" % back)
	_clear(arena, ride)
	await t.frames(2)

	# Side by side at speed, one steering into the other (a race bump): both
	# are shoved apart, neither is slowed much, and the one hit is pushed
	# off its line.
	var a: Array = await _ride(t, arena, "bike_scrapper", Vector3(-120, 0.3, 100), 0.0)
	var b: Array = await _ride(t, arena, "bike_scrapper", Vector3(-117.6, 0.3, 100), 0.0)
	a[1].cmd.move = Vector2(0, 1)
	b[1].cmd.move = Vector2(0, 1)
	await t.frames(70)
	var a_fast: float = a[0].speed
	a[1].cmd.move = Vector2(1, 1)
	var shoved := 0.0
	var b_slowest := INF
	for i in 50:
		await t.frames(1)
		shoved = maxf(shoved, b[0].knock.x)
		b_slowest = minf(b_slowest, b[0].speed)
	t.check(shoved > 1.0, "a racer bumped from the side is shoved aside (%.1f m/s)" % shoved)
	t.check(b_slowest > a_fast * 0.7, "and keeps most of its pace (slowest %.1f of %.1f m/s)" % [b_slowest, a_fast])
	t.check(a[0].global_position.distance_to(b[0].global_position) > 0.9, "the two never ride through each other")
	_clear(arena, a)
	_clear(arena, b)
	await t.frames(2)

	# Rammed from the side while parked: a light bike is thrown and spun; a
	# heavy rover hardly moves, and the bike that hit it bounces off.
	var parked = VehicleScript.new()
	parked.setup("bike_scrapper")
	arena.add_child(parked)
	parked.position = Vector3(120, 0.3, 60)
	parked.rotation.y = PI / 2.0
	parked.heading = PI / 2.0
	var ram: Array = await _ride(t, arena, "rover_warden", Vector3(120.6, 0.3, 100), 0.0)
	await t.frames(20)
	ram[1].cmd.move = Vector2(0, 1)
	var moved := 0.0
	var spun := 0.0
	for i in 300:
		await t.frames(1)
		moved = maxf(moved, Vector2(parked.position.x - 120.0, parked.position.z - 60.0).length())
		spun = maxf(spun, absf(parked.spin))
	t.check(moved > 2.0 and spun > 0.2, "a parked bike rammed by a rover is thrown (%.1f m) and spun (%.1f rad/s)" % [moved, spun])
	_clear(arena, ram)
	parked.queue_free()
	await t.frames(2)
	arena.queue_free()
	await t.frames(2)
