extends RefCounted
## The Dune Sea's sandstorms (DESIGN.md "The Dune Sea (part two)", Caleb's
## call: shifting fields): each storm is aimed through a wreck field, buries
## every field its heart crosses (the crates lying there are gone, its hulks
## sink, its spots stand empty) and for each uncovers a buried field away
## from it, every spot filled at once. A client sinks and raises the same
## fields.

const NetSessionScript := preload("res://core/net/net_session.gd")


static func run(t: Node) -> void:
	print("Dune Sea: sandstorms")
	var world := Worlds.get_world("dunes")
	_settings(t, world)
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 23)
	await t.frames(3)
	for bot in raid.bots:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	_start(t, raid)
	await _storm(t, raid)
	_client(t, raid)
	await t._end_raid(raid)


static func _settings(t: Node, world: WorldDef) -> void:
	t.check(world.weather_kind == "sand" and world.weather_name == "Sandstorm" and world.weather_buries,
			"the Dune Sea has sandstorms, and they bury wreck fields")
	t.check(Look.weather_kit("sand") != Look.weather_kit("ash"), "a sandstorm looks like sand, not ash")
	var wrecks: Array = load("res://worlds/dunes/map.gd").get("WRECKS")
	var rng := RandomNumberGenerator.new()
	var through := true
	for i in 30:
		rng.seed = i
		var path := world.weather_path(rng)
		var from := Vector2(path[0].x, path[0].z)
		var to := Vector2(path[1].x, path[1].z)
		var near := INF
		for wreck: Dictionary in wrecks:
			var on := Geometry2D.get_closest_point_to_segment(wreck["at"], from, to)
			near = minf(near, on.distance_to(wreck["at"]))
		through = through and near < 1.0
	t.check(through, "every sandstorm is aimed through a wreck field")


static func _buried(raid: Raid) -> Array[int]:
	var out: Array[int] = []
	for i in raid.fields.size():
		if raid.is_field_buried(i):
			out.append(i)
	return out


static func _crates_in(raid: Raid, index: int) -> Array:
	var field: Node3D = raid.fields[index]
	return raid.crates.filter(func(crate: Variant) -> bool:
		return is_instance_valid(crate) and not (crate as SalvageCrate).is_queued_for_deletion() \
				and (crate as SalvageCrate).holder == null \
				and Vector2(crate.global_position.x - field.global_position.x,
						crate.global_position.z - field.global_position.z).length() <= float(field.get_meta("radius")))


static func _spots_in(raid: Raid, index: int) -> int:
	var count := 0
	for spot: Dictionary in raid.get("_crate_spots"):
		if int(spot.field) == index:
			count += 1
	return count


## The world starts with some fields buried: their hulks under the sand and
## no crates on their spots.
static func _start(t: Node, raid: Raid) -> void:
	var buried := _buried(raid)
	t.check(raid.fields.size() == 8 and buried.size() == raid.world.fields_buried_at_start,
			"of the eight wreck fields, %d start buried (%d)" % [raid.world.fields_buried_at_start, buried.size()])
	var sunk := true
	var empty := true
	for i in buried:
		var field: Node3D = raid.fields[i]
		for hulk: Node in field.get_children():
			var top := (hulk as Node3D).global_position.y + 1.7 + 0.9
			var ground := float(raid.map.call("ground_height", field.global_position.x, field.global_position.z))
			sunk = sunk and top < ground
		empty = empty and _crates_in(raid, i).is_empty()
	t.check(sunk, "a buried field's hulks are under the sand")
	t.check(empty, "and none of its spots has a crate")
	var open := true
	for i in raid.fields.size():
		if not buried.has(i):
			open = open and _crates_in(raid, i).size() == _spots_in(raid, i) and _spots_in(raid, i) > 0
	t.check(open, "every open field has a crate on each spot")


## A storm at full strength over an open field buries it, keeps the crate
## someone holds, and uncovers a buried field away from the storm.
static func _storm(t: Node, raid: Raid) -> void:
	var before := _buried(raid)
	var target := -1
	for i in raid.fields.size():
		if not before.has(i):
			target = i
	var field: Node3D = raid.fields[target]
	var me := raid.player
	var lying := _crates_in(raid, target)
	var held: SalvageCrate = lying[0]
	me.global_position = held.global_position + Vector3(0, 0.2, 1.0)
	t.check(raid.lift_crate(me, held) == "", "someone lifts a crate in the field before the storm comes")
	var news: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: news.append(text))
	var w := raid.weather
	w.kind = "sand"
	w.radius = raid.world.weather_radius
	w.centre = Vector3(field.global_position.x, 0.0, field.global_position.z)
	w.velocity = Vector3(raid.world.weather_speed, 0, 0)
	w.strength = 0.5
	w.life = 100.0
	raid.call("_tick_fields")
	t.check(not raid.is_field_buried(target), "a storm still building buries nothing")
	w.strength = 1.0
	var ground_y := field.position.y
	raid.call("_tick_fields")
	t.check(raid.is_field_buried(target) and is_equal_approx(field.position.y, ground_y - 4.0),
			"a storm in full cry buries the field under its heart, hulks and all")
	await t.frames(1)
	t.check(_crates_in(raid, target).is_empty(), "the crates lying there are gone")
	t.check(is_instance_valid(held) and me.crate == held, "but not the one someone holds")
	var now := _buried(raid)
	var uncovered: Array[int] = []
	for i in before:
		if not now.has(i):
			uncovered.append(i)
	t.check(uncovered.size() == 1 and now.size() == before.size(),
			"and a buried field elsewhere is uncovered, so as many lie buried as before (%s)" % str(now))
	if uncovered.size() == 1:
		var other: Node3D = raid.fields[uncovered[0]]
		t.check(Vector2(other.global_position.x - w.centre.x, other.global_position.z - w.centre.z).length() > w.radius,
				"out of the storm's reach")
		t.check(_crates_in(raid, uncovered[0]).size() == _spots_in(raid, uncovered[0]),
				"with a crate on every spot at once")
	t.check(news.any(func(s: String) -> bool: return s.begins_with("The sandstorm buried a wreck field"))
			and news.any(func(s: String) -> bool: return s.begins_with("The sandstorm uncovered a wreck field")),
			"the war feed tells everyone what the storm buried and uncovered (%s)" % str(news))
	raid.call("_tick_fields")
	t.check(_buried(raid) == now, "a field already buried is not buried again")
	raid.call("_tick_crates", raid.world.crate_respawn_time + 1.0)
	t.check(_crates_in(raid, target).is_empty(), "a buried field's spots stay empty however long it lies")
	raid.set_field_buried(target, false)
	t.check(is_equal_approx(field.position.y, ground_y) and _crates_in(raid, target).size() == _spots_in(raid, target),
			"uncovered again, its hulks rise and its crates are back")
	w.kind = ""
	w.strength = 0.0


## A client sinks and raises the fields the server tells it of.
static func _client(t: Node, raid: Raid) -> void:
	var session := NetSessionScript.new()
	var client := Raid.new()
	t.add_child(client)
	client.start_client(raid.world)
	session.raid = client
	t.check(client.fields.size() == raid.fields.size() and _buried(client).is_empty(),
			"a client's map has the same fields, none buried until told")
	session.call("_fields", raid.pack_fields())
	var same := true
	for i in raid.fields.size():
		same = same and client.is_field_buried(i) == raid.is_field_buried(i) \
				and is_equal_approx(client.fields[i].position.y, raid.fields[i].position.y)
	t.check(same, "told, it buries the same fields to the same depth")
	session.call("_fields", ["junk", 3])
	t.check(true, "a malformed message is ignored")
	session.free()
	client.queue_free()
