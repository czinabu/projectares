extends RefCounted
## Checks for shelter from Frostline's cold (DESIGN.md "Frostline", "Shelter"):
## the map's rooms ("indoors" markers) keep the cold from hurting, an
## unheated ruin still chills slowly, a heated hut warms you over a few
## seconds anywhere inside, a whiteout leaks in through doorways and broken
## walls, and the visor and the watch say where you stand.

const MapScript := preload("res://worlds/frostline/map.gd")


static func run(t: Node) -> void:
	Raid.zone_rules = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("frostline"), 4242)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	await t.frames(3)
	_rooms_on_the_map(t, raid)
	await _ruin(t, raid)
	await _hut(t, raid)
	await _storm(t, raid)
	raid.queue_free()
	await t.frames(2)
	Raid.zone_rules = false


static func _ruins(raid: Raid) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for room in raid.rooms:
		if float(room.get_meta("heat", 0.0)) <= 0.0:
			out.append(room)
	return out


static func _huts(raid: Raid) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for room in raid.rooms:
		if float(room.get_meta("heat", 0.0)) > 0.0:
			out.append(room)
	return out


## A spot inside a room, `local` from its marker in the room's own space.
static func _in(room: Node3D, local: Vector3) -> Vector3:
	return room.global_transform * local


static func _put(actor: Actor, at: Vector3) -> void:
	actor.global_position = at
	actor.velocity = Vector3.ZERO


static func _rooms_on_the_map(t: Node, raid: Raid) -> void:
	print("Shelter: rooms on the map")
	t.check(_huts(raid).size() == MapScript.HUTS.size() + MapScript.POSTS.size(),
			"every heater hut and strongpoint hut is a heated room (%d)" % _huts(raid).size())
	t.check(_ruins(raid).size() == MapScript.RUINS.size(), "the shelves have their unheated ruins")
	var ruin: Node3D = _ruins(raid)[0]
	t.check(raid.indoors_at(_in(ruin, Vector3(0, 0.1, 0))) == ruin, "standing in a ruin is indoors")
	t.check(raid.indoors_at(_in(ruin, Vector3(0, 3.6, -1.0))) == null, "standing on its roof is not")
	t.check(raid.indoors_at(_in(ruin, Vector3(0, 0.1, 5.0))) == null, "nor is standing outside its doorway")
	var others := raid.rooms.all(func(room: Node3D) -> bool:
		return room == ruin or room.global_position.distance_to(ruin.global_position) > 30.0)
	t.check(others, "the rooms stand apart from each other")
	var clear := true
	for room in _ruins(raid):
		for w in raid.warmth:
			clear = clear and raid.indoors_at(w.global_position) != room
	t.check(clear, "no heater, vent or fire stands in a ruin")


static func _ruin(t: Node, raid: Raid) -> void:
	print("Shelter: an unheated ruin")
	var me := raid.player
	var ruin: Node3D = _ruins(raid)[0]
	var inside := _in(ruin, Vector3(0.8, 0.05, 0))
	# Along the shelf, out in the open, for comparing.
	var open := _in(ruin, Vector3(10.0, 0.05, 0))
	var rate: float = raid.world.cold_at(inside)
	_put(me, open)
	me.body_heat = 50.0
	await t.frames(60)
	var outside_lost := 50.0 - me.body_heat
	_put(me, inside)
	me.body_heat = 50.0
	await t.frames(60)
	var lost := 50.0 - me.body_heat
	t.check(not me.warming and lost > 0.0 and lost < outside_lost * 0.5,
			"a ruin still chills you, slowly (%.2f a second against %.2f outside)" % [lost, outside_lost])
	t.check(absf(lost - rate * raid.world.indoor_chill) < rate * 0.1,
			"by the world's indoor share of the cold (%.2f, %.2f expected)" % [lost, rate * raid.world.indoor_chill])
	t.check(raid.zone_label(me).ends_with("· shelter"), "the watch says you are in shelter")
	var glass := VisorHud.new()
	glass.raid = raid
	me.body_heat = 10.0
	me.shivering = true
	var cell: Dictionary = glass.vital_cells(me, Color.WHITE).filter(
			func(c: Dictionary) -> bool: return c.kind == "body_heat")[0]
	t.check(cell.label == "SHELTER" and not cell.warn, "the visor's body heat cell says shelter, and does not warn")
	glass.free()
	# Empty in a ruin: the cold never hurts indoors.
	me.protected_left = 0.0
	me.health.health = me.health.max_health
	me.body_heat = 0.0
	await t.frames(130)
	t.check(me.health.health == me.health.max_health and me.body_heat == 0.0,
			"with no body heat left, the cold still does not hurt indoors")
	_put(me, open)
	await t.frames(130)
	t.check(me.health.health < me.health.max_health, "step out of the doorway empty and it hurts at once")
	me.health.health = me.health.max_health
	me.body_heat = me.max_body_heat


static func _hut(t: Node, raid: Raid) -> void:
	print("Shelter: a heated hut")
	var me := raid.player
	var hut: Node3D = _huts(raid)[0]
	# By the open front, out of the heater's own reach.
	var spot := _in(hut, Vector3(-2.4, 0.05, 2.0))
	_put(me, spot)
	me.body_heat = 0.0
	await t.frames(60)
	var gained := me.body_heat
	t.check(me.warming and gained > 2.0, "a heated hut warms you anywhere inside (%.1f after a second)" % gained)
	t.check(gained < me.max_body_heat * 0.25, "gradually: the frost wears off over a few seconds, not at once")
	t.check(raid.zone_label(me).ends_with("· warm"), "the watch says you are somewhere warm")
	me.body_heat = me.max_body_heat


static func _storm(t: Node, raid: Raid) -> void:
	print("Shelter: a whiteout leaks in")
	var me := raid.player
	var ruin: Node3D = _ruins(raid)[0]
	var hut: Node3D = _huts(raid)[0]
	var inside := _in(ruin, Vector3(0.8, 0.05, 0))
	_put(me, inside)
	me.body_heat = 50.0
	await t.frames(60)
	var calm := 50.0 - me.body_heat
	var weather := raid.weather
	weather.start()
	weather.velocity = Vector3.ZERO
	weather.life = 1.0e9
	weather.age = 1.0e4
	weather.strength = 1.0
	weather.centre = Vector3(inside.x, 0.0, inside.z)
	me.body_heat = 50.0
	await t.frames(60)
	var stormy := 50.0 - me.body_heat
	t.check(stormy > calm * 1.5, "a whiteout leaks into a ruin (%.2f a second against %.2f)" % [stormy, calm])
	var spot := _in(hut, Vector3(-2.4, 0.05, 2.0))
	weather.centre = Vector3(spot.x, 0.0, spot.z)
	_put(me, spot)
	me.body_heat = 0.0
	await t.frames(60)
	var warmed := me.body_heat
	t.check(warmed > 0.0 and warmed < float(hut.get_meta("heat")),
			"and slows the warming in a heated hut, without stopping it (%.1f)" % warmed)
	weather.stop()
	me.body_heat = me.max_body_heat
