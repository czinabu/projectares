extends RefCounted
## The Dune Sea's ground (`worlds/dunes/map.gd`): sand a vehicle can drive
## and a far ring that meets it. Caleb saw sheets of sand jutting into the
## sky past the map's edge (the far ring built from another recipe, standing
## tens of metres over the sand) and rovers stopped dead or thrown in the
## air by the dunes. The runner finds this file by itself.

const MapScript := preload("res://worlds/dunes/map.gd")


static func run(t: Node) -> void:
	print("Dune Sea: the ground")
	var map: Node3D = MapScript.new()
	map.call("_seed_layout")
	var land: PlanetTerrain = map.call("far_land")
	# The far ring is the same ground as the playable sand: where the map's
	# own ground ends, the ring's ground is the map's height.
	var worst := 0.0
	var edge := (MapScript.SIDE - 1) * MapScript.CELL * 0.5
	for i in 64:
		var a := TAU * i / 64.0
		var x := clampf(cos(a) * edge * 1.5, -edge, edge)
		var z := clampf(sin(a) * edge * 1.5, -edge, edge)
		worst = maxf(worst, absf(land.height_at(x, z) - map.call("_height", x, z)))
	t.check(worst < 0.5, "dunes: the far ring meets the sand at the map's edge (off by %.1f m at most)" % worst)
	# Sand you can drive: almost none of the playable ground is steeper than
	# a wheel climbs (`Vehicle.max_slope`, 40 degrees).
	var steep := 0
	var total := 0
	var step := 4.0
	for x in range(-800, 800, 7):
		for z in range(-800, 800, 29):
			var h: float = map.call("_height", x, z)
			var gx: float = map.call("_height", x + step, z) - h
			var gz: float = map.call("_height", x, z + step) - h
			total += 1
			if rad_to_deg(atan(Vector2(gx, gz).length() / step)) > 40.0:
				steep += 1
	var share := float(steep) / total
	t.check(share < 0.01, "dunes: under 1%% of the sand is too steep to drive (%.2f%%)" % (share * 100.0))
	map.free()

	# A rover driven flat out across the dunes keeps going: no slope stops it
	# and the crests do not throw it in the air most of the way.
	var world := Worlds.get_world("dunes")
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 7)
	await t.frames(3)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position += Vector3(0, -400, 0)
	var me := raid.player
	var from := Vector2(-300.0, 200.0)
	var at := Vector3(from.x, float(raid.map.call("ground_height", from.x, from.y)) + 1.0, from.y)
	var rover = raid.spawn_vehicle("rover_warden", at, 2.2)
	me.global_position = at + Vector3(3, 0, 0)
	await t.frames(2)
	rover.mount(me)
	me.cmd.move = Vector2(0, 1)
	var walled := 0
	var air := 0
	var frames := 600
	for f in frames:
		await t.frames(1)
		walled += 1 if rover.is_on_wall() else 0
		air += 0 if rover.is_on_floor() else 1
	var went := Vector2(rover.global_position.x - at.x, rover.global_position.z - at.z).length()
	t.check(walled == 0 and went > rover.max_speed * frames / 60.0 * 0.65,
			"dunes: a rover crosses the dunes at speed (%.0f m in %d s, %d frames against a slope)" % [went, frames / 60, walled])
	t.check(air < frames * 0.2, "dunes: a rover keeps its wheels on the sand over the crests (%d of %d frames in the air)" % [air, frames])
	me.cmd.move = Vector2.ZERO
	raid.queue_free()
	await t.frames(2)
