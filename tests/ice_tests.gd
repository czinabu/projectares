extends RefCounted
## Checks for Frostline's thin ice (DESIGN.md "Frostline"): the middle of
## the lake bears a person or a bike but a heavy vehicle that stays on it
## cracks it and goes through, its riders into the water; the hole stays
## open a while, sinks anything driven into it, and freezes over. Kept in
## its own file and called from the test runner.

const MapScript := preload("res://worlds/frostline/map.gd")
const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]


static func run(t: Node) -> void:
	_where(t)
	await _breaking(t)


static func _where(t: Node) -> void:
	print("Ice: where it is thin")
	var frost := Worlds.get_world("frostline")
	t.check(frost.thin_ice and not Worlds.get_world("ashfront").thin_ice and not Worlds.get_world("plaza").thin_ice,
			"Frostline's lake has thin ice; Ashfront and the plaza have none")
	var mid := Vector3(MapScript.centre(MapScript.LAKE_Z), MapScript.floor_at(MapScript.LAKE_Z), MapScript.LAKE_Z)
	var shore := mid + Vector3(MapScript.LAKE_RADIUS.x * 0.85, 0.0, 0.0)
	t.check(frost.thin_ice_at(mid) and not frost.thin_ice_at(shore) and not frost.thin_ice_at(Vector3(0, 4, 200)),
			"thin in the lake's middle, sound at its shore and everywhere else")
	t.check(not frost.thin_ice_at(mid + Vector3(0, 20, 0)), "and nothing high over it counts")
	t.check(ItemDB.item_stats("rover_warden").get("weight", 0.0) > frost.ice_holds
			and ItemDB.item_stats("mech_bulwark").get("weight", 0.0) > frost.ice_holds
			and not ItemDB.item_stats("bike_scrapper").has("weight"),
			"a rover and a mech are too heavy for it; a bike is not")


static func _lake(raid: Raid, across := 0.0) -> Vector3:
	var x := MapScript.centre(MapScript.LAKE_Z) + across
	return Vector3(x, float(raid.map.call("ground_height", x, MapScript.LAKE_Z)) + 0.3, MapScript.LAKE_Z)


static func _wait(t: Node, condition: Callable, most: int) -> void:
	for k in most:
		if condition.call():
			return
		await t.frames(1)


static func _breaking(t: Node) -> void:
	print("Ice: breaking through")
	var frost := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 77)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	var me := raid.add_player(KIT, {}, "Driver", "driver")
	await t.frames(3)
	var cracks: Array[int] = []
	raid.ice_cracked.connect(func(_at: Vector3, stage: int) -> void: cracks.append(stage))
	# A bike crosses: the ice bears it.
	var bike := raid.spawn_vehicle("bike_scrapper", _lake(raid, 6.0), 0.0)
	await t.frames(240)
	t.check(is_instance_valid(bike) and bike in raid.vehicles and raid.ice_holes.is_empty() and cracks.is_empty(),
			"a bike stands on the thin ice and it holds")
	# A rover on the sound shore ice is fine too.
	var shore := raid.spawn_vehicle("rover_warden", _lake(raid, MapScript.LAKE_RADIUS.x * 0.85), 0.0)
	await t.frames(240)
	t.check(shore in raid.vehicles and raid.ice_holes.is_empty() and cracks.is_empty(),
			"a rover on the shore ice is borne")
	# A rover in the middle, with someone aboard, goes through.
	var rover := raid.spawn_vehicle("rover_warden", _lake(raid, -6.0), 0.0)
	await t.frames(2)
	me.global_position = rover.global_position + Vector3(2, 0, 0)
	rover.call("mount", me)
	t.check(me.vehicle == rover, "the driver gets on the rover")
	var broke := func() -> bool: return not raid.ice_holes.is_empty()
	await _wait(t, broke, 600)
	t.check(cracks.size() >= 3 and cracks[0] == 1 and cracks[1] == 2 and cracks[2] == 3,
			"the ice cracks twice out loud before it gives way (%s)" % [cracks])
	t.check(raid.ice_holes.size() == 1 and (not is_instance_valid(rover) or rover not in raid.vehicles),
			"a heavy vehicle that stays on it breaks through and sinks")
	t.check(me.vehicle == null and raid.ice_hole_at(me.global_position) >= 0,
			"its driver is left in the water")
	await t.frames(3)
	t.check(me.body_heat == 0.0 and me.shivering, "and the water takes all their body heat")
	# Out of the hole, the cold goes on as usual.
	me.global_position = raid._stand(_lake(raid, -6.0 + Raid.ICE_HOLE_RADIUS + 4.0))
	me.body_heat = 50.0
	await t.frames(3)
	t.check(me.body_heat > 0.0, "climbed out, the water no longer takes it")
	# The bike driven into the open hole sinks, light as it is.
	var hole: Vector3 = raid.ice_holes[0][0]
	bike.global_position = hole + Vector3(0, 0.3, 0)
	var sank := func() -> bool: return raid.vehicles.size() == 1
	await _wait(t, sank, 120)
	t.check(sank.call() and raid.ice_holes.size() == 1, "anything driven into the open hole sinks")
	# The holes go over the wire and come back the same.
	var copy := Raid.new()
	copy.clock = raid.clock
	copy.unpack_ice_holes(raid.pack_ice_holes())
	t.check(copy.ice_holes.size() == 1 and (copy.ice_holes[0][0] as Vector3).is_equal_approx(hole)
			and is_equal_approx(float(copy.ice_holes[0][1]), float(raid.ice_holes[0][1])),
			"open holes packed for the wire come out the same")
	copy.free()
	# It freezes over.
	raid.clock += frost.ice_refreeze + 1.0
	await t.frames(2)
	t.check(raid.ice_holes.is_empty(), "after a few minutes the hole freezes over")
	raid.queue_free()
	await t.frames(2)
