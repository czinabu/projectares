extends RefCounted
## Checks for the handbrake drift: held on the jump key at speed, a wheeled
## machine or the hoverbike slides round a corner nose first, and letting go
## on the throttle after a clean drift gives a short burst of speed. Wheels
## also break loose on a slick surface (`WorldDef.surface_grip`): Frostline's
## snow and ice. Run from the main test runner. Nothing here starts a server.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


## A world whose ground is as slick as `grip`.
class SlickWorld extends WorldDef:
	var grip := 1.0

	func surface_grip(_pos: Vector3) -> float:
		return grip


static func run(t: Node) -> void:
	print("Vehicles: handbrake drifting")
	_test_items(t)
	_test_surfaces(t)
	await _test_wheels_drift(t)
	await _test_clean_exit(t)
	await _test_slow_and_plain(t)
	await _test_hover_and_rover(t)
	await _test_slick_ground(t)


static func _test_items(t: Node) -> void:
	var with: Array[String] = []
	var without: Array[String] = []
	for id: String in ["bike_scrapper", "bike_raider", "rover_warden", "mech_bulwark", "jet_kestrel"]:
		var v = VehicleScript.new()
		v.setup(id)
		(with if v.handbrake else without).append(id)
		v.free()
	t.check(with == ["bike_scrapper", "bike_raider", "rover_warden"] and without == ["mech_bulwark", "jet_kestrel"],
			"wheels and the hoverbike have a handbrake; the walker's and the jet's jump key stays theirs (%s)" % [with])
	var found := false
	for section: Array in preload("res://core/phone/phone.gd").CONTROLS:
		for row: Array in section[1]:
			if String(row[0]).contains("Handbrake"):
				found = true
	t.check(found, "the Controls app lists the handbrake")


static func _test_surfaces(t: Node) -> void:
	var frost := Worlds.get_world("frostline")
	var ash := Worlds.get_world("ashfront")
	var map := preload("res://worlds/frostline/map.gd")
	var lake := Vector3(map.centre(map.LAKE_Z), map.floor_at(map.LAKE_Z), map.LAKE_Z)
	var snow := Vector3(map.centre(100.0) + 40.0, map.floor_at(100.0), 100.0)
	var ice := float(frost.surface_grip(lake))
	var packed := float(frost.surface_grip(snow))
	t.check(ice < packed and packed < 1.0 and ice <= 0.5,
			"Frostline's lake is slicker than its snow, and both are slicker than dry ground (%.2f, %.2f)" % [ice, packed])
	t.check(is_equal_approx(float(ash.surface_grip(Vector3.ZERO)), 1.0), "Ashfront's ground grips as before")


static func _spawn(t: Node, arena: Node3D, id: String, rider: Actor) -> Node3D:
	var bike = VehicleScript.new()
	bike.setup(id)
	arena.add_child(bike)
	bike.global_position = arena.global_position + Vector3(-120, 0.6, 150)
	await t.frames(20)
	rider.global_position = bike.global_position + Vector3(2.5, 0.1, 0)
	await t.frames(2)
	bike.mount(rider)
	return bike


static func _clear(rider: Actor) -> void:
	rider.cmd.move = Vector2.ZERO
	rider.cmd.sprint = false
	rider.cmd.jump = false


## Brings `bike` up to speed straight ahead.
static func _run_up(t: Node, bike: Node3D, rider: Actor, frames := 150) -> void:
	_clear(rider)
	rider.cmd.move = Vector2(0, 1)
	await t.frames(frames)


static func _test_wheels_drift(t: Node) -> void:
	var arena: Node3D = t._vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	var bike: Node3D = await _spawn(t, arena, "bike_scrapper", rider)
	# A plain hard turn first, for comparison: the wheels grip, no slide.
	await _run_up(t, bike, rider)
	var plain_from: float = bike.heading
	rider.cmd.move = Vector2(-1, 1)
	var plain_slip := 0.0
	for i in 30:
		await t.frames(1)
		plain_slip = maxf(plain_slip, absf(bike.slip))
	var plain_turn: float = bike.heading - plain_from
	t.check(plain_slip == 0.0, "on dry ground a wheeled bike grips through a turn")
	# Again with the handbrake.
	await _run_up(t, bike, rider)
	var start_speed: float = bike.speed
	var from: float = bike.heading
	rider.cmd.move = Vector2(-1, 0)
	rider.cmd.jump = true
	var slipped := 0.0
	var smoke := false
	for i in 30:
		await t.frames(1)
		slipped = maxf(slipped, absf(bike.slip))
		smoke = smoke or bike.drifting
	var turned: float = bike.heading - from
	t.check(smoke and slipped > 0.3, "with the handbrake held it drifts, its course trailing the nose (%.2f rad)" % slipped)
	t.check(turned > plain_turn * 1.2, "the nose swings round faster than a plain turn (%.2f against %.2f rad)" % [turned, plain_turn])
	var course: Vector3 = Vector3(bike.velocity.x, 0, bike.velocity.z).normalized()
	var nose: Vector3 = Basis(Vector3.UP, bike.heading) * Vector3.FORWARD
	t.check(course.signed_angle_to(nose, Vector3.UP) > 0.2, "it slides sideways, nose into the corner")
	var lost: float = start_speed - bike.speed
	t.check(lost > 1.0 and lost < float(bike.brake_decel) * 0.5 * 0.6,
			"it bleeds speed, much less than braking would (%.1f m/s in 0.5 s)" % lost)
	_clear(rider)
	bike.dismount()
	arena.queue_free()
	await t.frames(2)


## A drift held through a corner and let go on the throttle gives a burst;
## let go on the brake or straight into a wall, it gives nothing.
static func _test_clean_exit(t: Node) -> void:
	var arena: Node3D = t._vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	var bike: Node3D = await _spawn(t, arena, "bike_scrapper", rider)
	await _run_up(t, bike, rider)
	rider.cmd.move = Vector2(-1, 1)
	rider.cmd.jump = true
	await t.frames(54)
	t.check(bike.drift_charge >= float(bike.drift_build) * 0.9, "a drift held wide banks charge (%.2f s)" % bike.drift_charge)
	var released: float = bike.speed
	rider.cmd.jump = false
	rider.cmd.move = Vector2(0, 1)
	await t.frames(1)
	t.check(bike._boost_left > 1.0, "let go on the throttle, the charge becomes a burst (%.1f m/s to come)" % bike._boost_left)
	await t.frames(24)
	var gained: float = bike.speed - released
	var throttle_only: float = float(bike.accel) * 25.0 / 60.0
	t.check(gained > throttle_only + 1.0, "and it pulls out quicker than the throttle alone (+%.1f m/s against +%.1f)"
			% [gained, throttle_only])
	t.check(bike.speed <= float(bike.boost_speed) + 0.01, "never past boost speed")
	# Let go on the brake instead: no burst.
	await _run_up(t, bike, rider)
	rider.cmd.move = Vector2(-1, 1)
	rider.cmd.jump = true
	await t.frames(54)
	rider.cmd.jump = false
	rider.cmd.move = Vector2(0, -1)
	await t.frames(1)
	t.check(bike._boost_left == 0.0 and bike.drift_charge == 0.0, "let go on the brake, the charge is lost")
	_clear(rider)
	bike.dismount()
	arena.queue_free()
	await t.frames(2)


static func _test_slow_and_plain(t: Node) -> void:
	var arena: Node3D = t._vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	var bike: Node3D = await _spawn(t, arena, "bike_scrapper", rider)
	await _run_up(t, bike, rider, 20)
	t.check(bike.speed < float(bike.drift_min_speed), "a slow start (%.1f m/s)" % bike.speed)
	rider.cmd.move = Vector2(-1, 0)
	rider.cmd.jump = true
	await t.frames(20)
	t.check(not bike.drifting and bike.slip == 0.0 and bike.speed < 1.0,
			"too slow to drift, the handbrake only brakes (%.1f m/s)" % bike.speed)
	_clear(rider)
	await t.frames(30)
	t.check(bike.speed == 0.0 and bike.slip == 0.0 and bike._boost_left == 0.0, "and it comes to rest")
	bike.dismount()
	arena.queue_free()
	await t.frames(2)


static func _test_hover_and_rover(t: Node) -> void:
	for id: String in ["bike_raider", "rover_warden"]:
		var arena: Node3D = t._vehicle_arena()
		var rider := Actor.new()
		arena.add_child(rider)
		var bike: Node3D = await _spawn(t, arena, id, rider)
		await _run_up(t, bike, rider, 200)
		rider.cmd.move = Vector2(-1, 1)
		var plain := 0.0
		for i in 30:
			await t.frames(1)
			plain = maxf(plain, absf(bike.slip))
		await _run_up(t, bike, rider, 120)
		rider.cmd.move = Vector2(-1, 1)
		rider.cmd.jump = true
		var held := 0.0
		for i in 30:
			await t.frames(1)
			held = maxf(held, absf(bike.slip))
		t.check(held > plain + 0.1 and held > 0.3, "the %s's handbrake throws it wider than a plain turn (%.2f against %.2f rad)"
				% [bike.display_name, held, plain])
		_clear(rider)
		bike.dismount()
		arena.queue_free()
		await t.frames(2)


## On a slick surface wheels break loose in a plain turn and pull away slower;
## the hover's cushion does not care.
static func _test_slick_ground(t: Node) -> void:
	var arena: Node3D = t._vehicle_arena()
	var rider := Actor.new()
	arena.add_child(rider)
	var bike: Node3D = await _spawn(t, arena, "bike_scrapper", rider)
	var ice := SlickWorld.new()
	ice.grip = 0.35
	bike._world = ice
	_clear(rider)
	rider.cmd.move = Vector2(0, 1)
	await t.frames(60)
	var on_ice: float = bike.speed
	t.check(on_ice < float(bike.accel) * 0.6, "on ice the wheels spin: slow to pull away (%.1f m/s in 1 s)" % on_ice)
	await t.frames(120)
	rider.cmd.move = Vector2(-1, 1)
	var slid := 0.0
	for i in 30:
		await t.frames(1)
		slid = maxf(slid, absf(bike.slip))
	t.check(slid > 0.15, "and they slide wide through a plain turn (%.2f rad)" % slid)
	rider.cmd.move = Vector2(0, 1)
	await t.frames(120)
	t.check(absf(bike.slip) < 0.02, "straightened out, they grip again (%.3f)" % bike.slip)
	_clear(rider)
	bike.dismount()
	arena.queue_free()
	await t.frames(2)
