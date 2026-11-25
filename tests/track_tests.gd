extends RefCounted
## Checks for Frostline's tracks and louder gunshots (DESIGN.md "Frostline"):
## people on foot leave footprints and ground vehicles wheel tracks in the
## open ground, the authority keeps them for a few minutes and a client is
## sent only those near it; a shot carries twice as far. Kept in its own file
## and called from the test runner.

const MapScript := preload("res://worlds/frostline/map.gd")
const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]
## How far round a player the server sends marks (the session's TRACK_RANGE).
const SEND_RANGE := 60.0


static func run(t: Node) -> void:
	_store(t)
	await _laid_down(t)
	await _gunshots(t)


static func _store(t: Node) -> void:
	print("Tracks: the store")
	var tracks := Tracks.new()
	tracks.lifetime = 10.0
	var first := tracks.add(Vector3(1, 0, 1), 0.0, Tracks.Kind.LEFT, 0.0)
	var second := tracks.add(Vector3(2, 0, 1), 0.0, Tracks.Kind.RIGHT, 1.0)
	tracks.add(Vector3(200, 0, 200), 0.0, Tracks.Kind.TREAD, 2.0)
	t.check(second > first and tracks.count() == 3, "marks are kept, each with a new id")
	t.check(tracks.near(Vector3.ZERO, 10.0).size() == 2, "a nearby lookup finds only the marks near")
	var cell := Tracks.cell_of(Vector3(1, 0, 1))
	t.check(tracks.since(cell, first).size() == 1 and tracks.since(cell, second).is_empty(),
			"a cell's new marks are found by the last id sent")
	var copy := Tracks.new()
	copy.unpack(Tracks.pack(tracks.near(Vector3.ZERO, 10.0), 5.0), 105.0)
	var marks := copy.near(Vector3.ZERO, 10.0)
	t.check(marks.size() == 2 and int(marks[1][3]) == Tracks.Kind.RIGHT and is_equal_approx(float(marks[0][4]), 100.0),
			"marks packed for the wire come out the same, aged by the receiver's clock")
	tracks.expire(10.5)
	t.check(tracks.count() == 2, "old marks fade away")
	for k in Tracks.CELL_CAP + 50:
		tracks.add(Vector3(3, 0, 3), 0.0, Tracks.Kind.LEFT, 11.0)
	t.check(tracks.count() <= Tracks.CELL_CAP + 1, "a trampled spot never grows past its cap")
	tracks.clear()
	t.check(tracks.count() == 0, "and the snow can be wiped clean")


static func _walk(t: Node, raid: Raid, actor: Actor, from: Vector3, to: Vector3, steps: int) -> void:
	for k in steps + 1:
		var at := from.lerp(to, float(k) / steps)
		actor.global_position = raid._stand(Vector3(at.x, raid.map.call("ground_height", at.x, at.z), at.z))
		actor.velocity = Vector3.ZERO
		await t.frames(7)


static func _laid_down(t: Node) -> void:
	print("Tracks: laid in the snow")
	var frost := Worlds.get_world("frostline")
	t.check(frost.tracks and not Worlds.get_world("ashfront").tracks and not Worlds.get_world("plaza").tracks,
			"Frostline keeps tracks; Ashfront and the plaza do not")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(frost, 4242)
	var me := raid.add_player(KIT, {}, "Walker", "walker")
	var x := MapScript.centre(106.0) + 25.0
	# The pockets near the walk wake as the walker arrives: park them, so
	# only the walker's feet mark the snow.
	me.global_position = Vector3(x, MapScript.floor_at(106.0) + 1.0, 106.0)
	raid._tick_pockets()
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	await t.frames(3)
	await _walk(t, raid, me, Vector3(x, 0, 110.0), Vector3(x, 0, 102.0), 12)
	var marks := raid.tracks.near(Vector3(x, 0, 106.0), 5.0)
	t.check(marks.size() >= 6, "walking leaves footprints (%d over 8 m)" % marks.size())
	var turns := true
	for k in range(1, marks.size()):
		turns = turns and int(marks[k][3]) != int(marks[k - 1][3])
	t.check(turns, "left and right in turn")
	var on_ground := marks.all(func(m: Array) -> bool:
		var at: Vector3 = m[1]
		return absf(at.y - float(raid.map.call("ground_height", at.x, at.z))) < 0.05)
	t.check(on_ground, "pressed into the ground where they fell")
	var yaw := float(marks[0][2]) if not marks.is_empty() else 1.0
	t.check(absf(wrapf(yaw, -PI, PI)) < 0.3, "pointing the way they walked (yaw %.2f)" % yaw)
	# Up on a hut's roof or floor nothing is printed.
	var before := raid.tracks.count()
	var high := me.global_position + Vector3(0, 3, 0)
	for k in 6:
		raid._track_mark(me, high + Vector3(0, 0, -k * 1.0), Tracks.Kind.LEFT, Raid.FOOT_STEP)
	t.check(raid.tracks.count() == before, "off the open ground (a roof, a floor) nothing is printed")
	# A ground vehicle leaves wheel tracks.
	var bike := raid.spawn_vehicle("bike_scrapper", Vector3(x, float(raid.map.call("ground_height", x, 80.0)), 80.0), 0.0)
	for k in 4:
		raid._track_mark(bike, bike.global_position + Vector3(0, 0, -k * 1.6), Tracks.Kind.TREAD, Raid.TREAD_STEP)
	var wheels := raid.tracks.near(bike.global_position, 8.0).filter(func(m: Array) -> bool:
		return int(m[3]) == Tracks.Kind.TREAD)
	t.check(wheels.size() >= 3, "a ground vehicle leaves wheel tracks (%d)" % wheels.size())
	# A client is sent only the marks near it.
	var near := raid.tracks.near(me.global_position, SEND_RANGE)
	t.check(not near.is_empty() and raid.tracks.near(Vector3(x, 0, -200.0), SEND_RANGE).is_empty(),
			"the marks near a player are few and far ones stay on the server")
	# They fade after their lifetime.
	raid.tracks.expire(raid.clock + frost.track_lifetime + 1.0)
	t.check(raid.tracks.count() == 0, "after a few minutes the snow is clean again")
	raid.queue_free()
	await t.frames(2)
	var war := Raid.new()
	t.add_child(war)
	war.start_server(Worlds.get_world("ashfront"), 7)
	var other := war.add_player(KIT, {}, "Other", "other")
	await t.frames(3)
	other.global_position += Vector3(6, 0, 0)
	await t.frames(20)
	t.check(war.tracks.count() == 0, "a world without tracks keeps none")
	war.queue_free()
	await t.frames(2)


static func _gunshots(t: Node) -> void:
	print("Tracks: gunshots carry further")
	var raids := {}
	for id in ["frostline", "ashfront"]:
		var raid := Raid.new()
		t.add_child(raid)
		raid.start_server(Worlds.get_world(id), 3)
		var shooter := raid.add_player(KIT, {}, "Shooter", "shooter")
		raids[id] = [raid, shooter]
	await t.frames(3)
	var cold_gun := (raids["frostline"][1] as Actor).weapons[0] as Gun
	var warm_gun := (raids["ashfront"][1] as Actor).weapons[0] as Gun
	t.check(is_equal_approx(cold_gun.noise_reach(), warm_gun.noise_reach() * 2.0) and is_equal_approx(cold_gun.shot_carry(), 2.0),
			"in Frostline a shot is heard twice as far (%.0f m against %.0f m)" % [cold_gun.noise_reach(), warm_gun.noise_reach()])
	for pair: Array in raids.values():
		(pair[0] as Raid).queue_free()
	await t.frames(2)
