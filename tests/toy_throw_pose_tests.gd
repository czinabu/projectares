extends RefCounted
## The `toy_throw_pose` checks. The test runner finds this file by itself and calls
## `run(t)`.
##
## The toy in the hand and the throw are one shared pose (`ActionPose`), so
## first and third person and everyone around see the same arm.


static func run(t: Node) -> void:
	print("Vehicles: holding and throwing a toy")
	var arena: Node3D = t._vehicle_arena()
	var p := Actor.new()
	arena.add_child(p)
	await t.frames(2)
	var pose := ActionPose.of(p)
	t.check(pose.toy == 0.0 and pose.toy_shown() == "" and not pose.toy_busy(), "an empty hand shows no toy")
	p.toy_in_hand = "bike_scrapper"
	pose.toy_hand_free = false
	pose.advance_toy(0.5)
	t.check(pose.toy == 0.0 and pose.toy_busy(), "the toy waits for the weapon to be put away, keeping it away meanwhile")
	pose.toy_hand_free = true
	pose.advance_toy(0.1)
	t.check(pose.toy > 0.0 and pose.toy < 1.0, "then the hand comes up for it, eased")
	pose.advance_toy(1.0)
	var held := pose.toy_hand_point()
	t.check(pose.toy == 1.0 and pose.toy_shown() == "bike_scrapper" and held.z < -0.3 and held.y > 1.2,
			"held up in front, in view of the eyes")
	p.toy_throws += 1
	var path: Array[Vector3] = []
	var shown_at_release := ""
	var turned := 0.0
	var clock := 0.0
	pose.advance_toy(0.0)
	while pose.toy_throw_t >= 0.0 and clock < 2.0:
		path.append(pose.toy_hand_point())
		turned = minf(turned, pose.toy_turn().x)
		if pose.toy_throw_t < pose.toy_release - 0.02:
			shown_at_release = pose.toy_shown()
		if pose.toy_throw_t >= pose.toy_release:
			p.toy_in_hand = ""
		pose.advance_toy(1.0 / 60.0)
		clock += 1.0 / 60.0
	var back: Vector3 = path.reduce(func(a: Vector3, b: Vector3) -> Vector3: return b if b.z > a.z else a, path[0])
	var low: Vector3 = path.reduce(func(a: Vector3, b: Vector3) -> Vector3: return b if b.y < a.y else a, path[0])
	t.check(back.z > 0.0 and back.y > pose.shoulder.y, "the throw draws the toy back over the shoulder (%.2f, %.2f)" % [back.y, back.z])
	t.check(turned < -0.3, "the shoulders turn back into it")
	t.check(low.y < held.y - 0.2 and low.z < 0.0, "and follows through down across the body")
	t.check(shown_at_release == "bike_scrapper", "the toy is in the hand until the release")
	t.check(absf(clock - pose.toy_throw_time) < 0.05 and pose.toy == 0.0 and not pose.toy_busy(),
			"the hand is given back once the throw is through")
	# A toy that stays on record a moment after it flew (online, until the
	# server says so) is not held up again.
	p.toy_in_hand = "bike_scrapper"
	p.toy_throws += 1
	pose.advance_toy(0.0)
	for i in 60:
		pose.advance_toy(1.0 / 60.0)
	t.check(pose.toy_shown() == "" and pose.toy == 0.0, "a thrown toy does not come back to the hand while the world catches up")
	arena.queue_free()
	await t.frames(2)


## Has an online client throw the bike on its watch, turning until it finds
## room, and waits for the bike to stand unpacked close by.
