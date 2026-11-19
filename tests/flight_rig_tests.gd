extends RefCounted
## The `flight_rig` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Flight rig")
	var rig := FlightRig.new()
	t.check(rig.tick(true, 0.1) == 0.0, "no thrust without a rig equipped")
	rig.enabled = true
	t.check(rig.tick(true, 0.1) > 0.0 and rig.heat > 0.0, "thrust builds heat")
	for i in 100:
		rig.tick(true, 0.1)
	t.check(rig.overheated and rig.tick(true, 0.1) == 0.0, "overheating cuts thrust")
	for i in 100:
		rig.tick(false, 0.1)
	t.check(not rig.overheated and rig.heat == 0.0, "the rig cools down and recovers")
	var bursts := [0]
	rig.burst_fired.connect(func() -> void: bursts[0] += 1)
	rig.try_burst()
	t.check(bursts[0] == 0, "a rig without a burst signals nothing")
	rig.burst_velocity = 10.0
	rig.burst_heat = 60.0
	rig.try_burst()
	rig.try_burst()
	rig.try_burst()
	t.check(bursts[0] == 1 and not rig.overheated, "a burst that would go far past the heat limit is refused, not fired")
	rig.heat = 0.0
	rig.burst_heat = 34.0
	var kicks := 0
	for i in 5:
		if rig.try_burst() > 0.0:
			kicks += 1
	t.check(kicks == 3 and rig.overheated, "the last burst of a set may tip the rig over and overheat it (%d)" % kicks)
	rig.heat = 0.0
	rig.overheated = false
	rig.launch_once = true
	rig.launched = false
	t.check(rig.try_burst() > 0.0 and rig.try_burst() == 0.0, "a launch-once rig launches once per takeoff")
	rig.heat = 90.0
	rig.is_hovering = true
	rig.coast(1.0)
	t.check(is_equal_approx(rig.heat, 90.0 - rig.coast_cool) and not rig.is_thrusting, "coasting idles the jets and cools fast")
	rig.heat = 50.0
	rig.is_gliding = true
	rig.glide_cool = 12.0
	rig.tick(false, 0.1)
	t.check(is_equal_approx(rig.heat, 50.0 - 1.2), "gliding cools at the glide rate with no delay")
	rig.is_gliding = false
	rig.pulse_velocity = 11.0
	rig.pulse_heat = 30.0
	rig.heat = 0.0
	var pulses := 0
	for i in 5:
		if rig.try_pulse() > 0.0:
			pulses += 1
	t.check(pulses == 3, "pulses are limited by heat (%d in a row)" % pulses)
	rig.free()
