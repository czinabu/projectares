extends RefCounted
## Checks for each rig's fair limit and the wings' height (Caleb's calls):
## the boots' skate runs on heat, so it is no longer endless, and a wing
## boost's speed can be swooped into height above where it was bought.
## Run from the main test runner. Nothing here starts a server.

const RigStyle := preload("res://tests/rig_style_tests.gd")


static func run(t: Node) -> void:
	print("Rig limits")
	_test_skate_heat(t)
	await _test_boost_swoop(t)


## A Mk1 skate lasts about 20 s from cold, then drops off overheated until
## it cools; every rig flies on a limit.
static func _test_skate_heat(t: Node) -> void:
	var rig := _rig("boots_thruster")
	t.check(rig.skate_heat > 0.0, "the boots' skate builds heat (%.1f a second)" % rig.skate_heat)
	var lasted := 0.0
	while lasted < 60.0:
		rig.is_skating = true
		rig.aloft = true
		rig.tick(false, 0.1)
		if not rig.is_skating:
			break
		lasted += 0.1
	t.check(lasted > 15.0 and lasted < 25.0 and rig.overheated,
			"a Mk1 skate lasts about 20 s, then the boots overheat (%.1f s)" % lasted)
	var cooled := 0.0
	rig.aloft = false
	while rig.overheated and cooled < 20.0:
		rig.tick(false, 0.1)
		cooled += 0.1
	t.check(not rig.overheated and cooled < 6.0, "on the ground they cool and skate again within a few seconds (%.1f s)" % cooled)
	var mk3 := _rig("boots_thruster_mk3")
	t.check(mk3.skate_heat < rig.skate_heat, "a higher tier skates longer")
	for id: String in ["jetpack_mk1", "boots_thruster", "wings_glide"]:
		var each := _rig(id)
		var limited := each.heat_per_sec > 0.0 or each.skate_heat > 0.0 or each.glide_heat > 0.0
		t.check(limited, "%s flies on a limit" % id)


## Wings: a boost's speed, swooped, climbs above where the boost began, but
## no further than what it bought.
static func _test_boost_swoop(t: Node) -> void:
	var arena := RigStyle._arena(t, Vector3(-1700, 0, 14000))
	var p := RigStyle._actor(arena, ["wings_glide"])
	await t.frames(5)
	p.global_position.y = 36.0
	p.velocity = Vector3(0, -1, -22)
	p.cmd.jump = true
	await t.frames(40)
	var start := p.global_position.y
	p.cmd.sprint_pressed = true
	p.cmd.move = Vector2(0, 0.2)
	await t.frames(1)
	p.cmd.sprint_pressed = false
	p.cmd.move = Vector2.ZERO
	await t.frames(20)
	p.cmd.move = Vector2(0, -1)
	var peak := p.global_position.y
	for i in 300:
		await t.get_tree().physics_frame
		peak = maxf(peak, p.global_position.y)
	t.check(peak > start + 3.0 and peak < start + 20.0,
			"a boost then a pull-up climbs above where the boost began (%.1f m up)" % (peak - start))
	p.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


static func _rig(id: String) -> FlightRig:
	var rig := FlightRig.new()
	rig.enabled = true
	Loadout._apply_stats(rig, ItemDB.item_stats(id))
	return rig
