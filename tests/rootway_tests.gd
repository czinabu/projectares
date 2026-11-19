extends RefCounted
## Checks for the Spore Marsh's Rootways (DESIGN.md "The Spore Marsh (the
## Rootways)"): the cut opens the ground and the water over it, the way down
## is floored, walled and roofed under the ground with room for a squad, a
## bot can walk from the shore to the keeper, inside is out of the weather
## and in close air, a garrison stands in the gallery, and the keeper fights
## in two phases (broodlings from the wall, then spore vents that warn
## before they hurt), opens a share of its vault for each who fought it and
## comes back on its own timer.

const MapScript := preload("res://worlds/marsh/map.gd")
const Rootway := preload("res://worlds/marsh/rootway.gd")


static func run(t: Node) -> void:
	_shape(t)
	await _built(t)
	await _keeper(t)


## The layout's numbers (Caleb's ask: no way narrower than 9 m) and the
## open cut, from the layout alone.
static func _shape(t: Node) -> void:
	print("Rootways: the layout")
	t.check(Rootway.ROOTWAYS.size() >= 1, "the marsh has a Rootway (%d)" % Rootway.ROOTWAYS.size())
	var g: Array = Rootway.GALLERY
	var p: Array = Rootway.PILLAR
	var narrowest := minf(Rootway.HALF * 2.0, minf(float(p[0]) - float(g[0]), float(g[1]) - float(p[1])))
	narrowest = minf(narrowest, minf(float(p[2]) - float(g[2]), float(g[3]) - float(p[3])))
	t.check(narrowest >= 9.0, "no way is narrower than 9 m (the narrowest is %.0f m)" % narrowest)
	t.check(Rootway.CHAMBER_RADIUS * 2.0 >= 30.0 and Rootway.ROOF - Rootway.CHAMBER_FLOOR >= 7.0
			and Rootway.ROOF - Rootway.FLOOR >= 5.0, "the keeper's chamber is a round room 32 m across with room over a big beast")
	t.check(Rootway.ARENA >= Rootway.CHAMBER_RADIUS, "the keeper's arena takes in its whole chamber")
	t.check(Rootway.BEND - Rootway.HALF >= float(Rootway.PILLAR[1]) and Rootway.HALF <= float(Rootway.PILLAR[1]) + 1.0,
			"the way bends round the pillar: the passage leaves the gallery beside it, out of line with the throat")
	var on_grid := true
	for hole in Rootway.holes():
		for n: float in [hole.position.x, hole.position.y, hole.size.x, hole.size.y]:
			if not is_zero_approx(fposmod(n, MapScript.CELL)):
				on_grid = false
	t.check(on_grid, "each cut lies on the ground's samples")
	var area := Rect2(-200, -200, 400, 400)
	var pieces := MapScript.water_pieces(area, Rootway.holes())
	var covered := 0.0
	var over_hole := false
	for piece in pieces:
		covered += piece.get_area()
		for hole in Rootway.holes():
			if piece.intersection(hole).get_area() > 0.01:
				over_hole = true
	var open := 0.0
	for hole in Rootway.holes():
		open += hole.get_area()
	t.check(not over_hole and is_equal_approx(covered + open, area.get_area()),
			"the black water covers the basin but the cuts (%d pieces)" % pieces.size())
	t.check(Rootway.inside(Rootway.frame(Rootway.ROOTWAYS[0]) * Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR + 1.0, Rootway.CHAMBER_Z))
			and Rootway.inside(Rootway.frame(Rootway.ROOTWAYS[0]) * Vector3(12.0, Rootway.FLOOR + 1.0, 50.0))
			and not Rootway.inside(Rootway.frame(Rootway.ROOTWAYS[0]) * Vector3(0, 1.0, 10.0))
			and not Rootway.inside(Rootway.frame(Rootway.ROOTWAYS[0]) * Vector3(0, 2.0, Rootway.CHAMBER_Z)),
			"inside is under the roof: the chamber and the gallery, not the open cut nor the ground over it")


## The Rootway as built in a running marsh: open, floored, closed, under
## the ground, walkable, out of the weather, garrisoned.
static func _built(t: Node) -> void:
	print("Rootways: as built")
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 31)
	await t.frames(2)
	var map := raid.map
	var way: Dictionary = Rootway.ROOTWAYS[0]
	var f := Rootway.frame(way)
	var space := raid.get_world_3d().direct_space_state
	var top := float(map.call("ground_height", f.origin.x, f.origin.z))
	# The cut is open: straight down onto the ramp, not the ground.
	var bad := []
	for z: float in [2.0, 10.0, 20.0, 30.0, 35.0]:
		for x: float in [-5.0, 0.0, 5.0]:
			var from := f * Vector3(x, 20.0, z)
			var hit := _ray(space, from, from + Vector3(0, -40.0, 0))
			var want := Rootway.floor_at(z, top)
			if hit.is_empty() or absf(hit.position.y - want) > 0.35:
				bad.append(Vector2(x, z))
	t.check(bad.is_empty(), "the cut is open to the sky down onto its ramp %s" % str(bad))
	# Floors to stand on all the way.
	var floors := []
	for spot: Vector3 in [Vector3(0, Rootway.FLOOR, 40.0), Vector3(-11.0, Rootway.FLOOR, 58.0), Vector3(11.0, Rootway.FLOOR, 58.0),
			Vector3(0, Rootway.FLOOR, 48.0), Vector3(0, Rootway.FLOOR, 68.0), Vector3(Rootway.BEND, Rootway.floor_at(76.0, top), 76.0),
			Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR, 81.0), Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR, Rootway.CHAMBER_Z),
			Vector3(Rootway.BEND - 12.0, Rootway.CHAMBER_FLOOR, Rootway.CHAMBER_Z + 6.0)]:
		var from := f * (spot + Vector3(0, 3.0, 0))
		var hit := _ray(space, from, from + Vector3(0, -6.0, 0))
		if hit.is_empty() or absf(hit.position.y - spot.y) > 0.35:
			floors.append(Vector2(spot.x, spot.z))
	t.check(floors.is_empty(), "the throat, the gallery, the passage and the chamber have floors %s" % str(floors))
	# Closed round: walls each side and a roof overhead, all the way.
	var open := []
	for spot: Vector3 in [Vector3(0, Rootway.FLOOR + 2.0, 40.0), Vector3(-11.0, Rootway.FLOOR + 2.0, 50.0),
			Vector3(11.0, Rootway.FLOOR + 2.0, 66.0), Vector3(Rootway.BEND, Rootway.FLOOR + 1.0, 76.0),
			Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR + 2.0, Rootway.CHAMBER_Z)]:
		var at := f * spot
		for dir: Vector3 in [f.basis.x, -f.basis.x, f.basis.z, Vector3.UP]:
			var hit := _ray(space, at, at + dir * 60.0)
			if hit.is_empty():
				open.append([Vector2(spot.x, spot.z), dir])
	t.check(open.is_empty(), "walls and a roof close round it all %s" % str(open))
	# Through the portal, the whole width and height.
	var blocked := []
	for x: float in [-Rootway.HALF + 0.6, 0.0, Rootway.HALF - 0.6]:
		for y: float in [0.6, Rootway.ROOF - Rootway.FLOOR - 0.6]:
			var hit := _ray(space, f * Vector3(x, Rootway.FLOOR + y, Rootway.CUT - 4.0), f * Vector3(x, Rootway.FLOOR + y, Rootway.THROAT_END - 0.5))
			if not hit.is_empty():
				blocked.append(Vector2(x, y))
	t.check(blocked.is_empty(), "the cut opens into the throat, clear its whole width %s" % str(blocked))
	# Under the ground: its roof stays under the ground and the pools' beds.
	var shallow := []
	var z := Rootway.CUT
	while z <= Rootway.END:
		for x: float in [-Rootway.GALLERY[1] - Rootway.WALL, -6.0, 0.0, 6.0, Rootway.GALLERY[1] + Rootway.WALL,
				Rootway.BEND + Rootway.CHAMBER_RADIUS + Rootway.WALL]:
			var at := f * Vector3(x, 0.0, z)
			if float(map.call("ground_height", at.x, at.z)) < Rootway.ROOF + Rootway.ROOF_THICK + 0.3:
				shallow.append(Vector2(x, z))
		z += 2.0
	t.check(shallow.is_empty(), "the ground and the pools' beds lie over its roof all the way %s" % str(shallow))
	# Nothing of the marsh stands in the cut.
	var hole: Rect2 = Rootway.holes()[0]
	var stalks: Array = map.get("_stalks")
	var in_cut := stalks.filter(func(stalk: Dictionary) -> bool:
		return hole.grow(float(stalk.radius) + 1.5).has_point(Vector2(stalk.at.x, stalk.at.z)))
	var marks := []
	for group in ["spawn_cache", "spawn_bot", "spawn_guard", "spawn_player", "depot"]:
		for node: Node3D in raid.get_tree().get_nodes_in_group(group):
			if hole.grow(3.0).has_point(Vector2(node.global_position.x, node.global_position.z)) and node.global_position.y > 0.0:
				marks.append(group)
	t.check(in_cut.is_empty() and marks.is_empty(), "no stalk, spawn or cache stands in the cut %s" % str(marks))
	# A bot can walk from the shore down to the keeper.
	var nav := raid.get_world_3d().navigation_map
	var outside := f * Vector3(0, top, -12.0)
	var goal := f * Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR, Rootway.CHAMBER_Z - 6.0)
	for i in 600:
		if NavigationServer3D.map_get_iteration_id(nav) > 0 \
				and NavigationServer3D.map_get_closest_point(nav, goal).distance_to(goal) < 1.0 \
				and NavigationServer3D.map_get_closest_point(nav, outside).distance_to(outside) < 1.0:
			break
		await t.frames(1)
	var shore := NavigationServer3D.map_get_closest_point(nav, outside)
	goal = NavigationServer3D.map_get_closest_point(nav, goal)
	var path := NavigationServer3D.map_get_path(nav, shore, goal, true)
	t.check(path.size() > 1 and path[path.size() - 1].distance_to(goal) < 1.0 and shore.distance_to(outside) < 1.0,
			"a path runs from the shore, down the cut, round the pillar and into the chamber (%d points)" % path.size())
	var back := NavigationServer3D.map_get_path(nav, goal, shore, true)
	t.check(back.size() > 1 and back[back.size() - 1].distance_to(shore) < 1.5, "and back up")
	# Out of the weather, in close air.
	var deep := f * Vector3(Rootway.BEND, Rootway.CHAMBER_FLOOR + 1.0, Rootway.CHAMBER_Z)
	var gallery := f * Vector3(11.0, Rootway.FLOOR + 1.0, 58.0)
	var cut := f * Vector3(0, Rootway.floor_at(10.0, top) + 1.0, 10.0)
	t.check(marsh.sheltered_at(deep) and marsh.sheltered_at(gallery) and not marsh.sheltered_at(cut),
			"down the Rootway is sheltered, the open cut is not")
	# The marsh has no storms of its own yet: lay one over it by hand.
	raid.weather.kind = "storm"
	raid.weather.radius = 120.0
	raid.weather.centre = Vector3(deep.x, 0.0, deep.z)
	raid.weather.strength = 1.0
	var under := raid.weather.strength_at(deep)
	raid.weather.centre = Vector3(cut.x, 0.0, cut.z)
	t.check(under == 0.0 and raid.weather.strength_at(cut) > 0.5, "no storm reaches down into it, though it rains into the cut")
	var forest_sight := float(marsh.get_script().get_script_constant_map()["FOREST_SIGHT"])
	t.check(marsh.sight_at(deep) <= forest_sight and marsh.sight_at(gallery) <= forest_sight,
			"a bot sees no further down there than in a forest's close air")
	# The garrison and the caches.
	var guards: Array = raid._guards.filter(func(entry: Dictionary) -> bool:
		return Rootway.inside((entry.marker as Node3D).global_position + Vector3(0, 1.0, 0)))
	var standing := guards.filter(func(entry: Dictionary) -> bool: return entry.bot != null and raid._is_extra(entry.bot as Actor))
	t.check(guards.size() >= 3 and standing.size() == guards.size(), "a garrison of the marsh's beasts stands guard (%d)" % guards.size())
	var caches: Array = raid._caches.filter(func(c: Dictionary) -> bool: return c.source == "rootway")
	t.check(caches.size() >= 2, "its gallery holds caches of its own (%d)" % caches.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var goods := 0
	for i in 40:
		goods += marsh.roll_loot("rootway", rng).filter(func(id: String) -> bool: return id in ["glowcap", "spore_sac", "chitin_plate"]).size()
	t.check(goods > 40, "they pay the marsh's goods (%d in 40)" % goods)
	raid.queue_free()
	await t.frames(2)


## The keeper's fight, as the Engine's Heart Warden's runs.
static func _keeper(t: Node) -> void:
	print("Rootways: the keeper")
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 33)
	await t.frames(2)
	var way: Dictionary = Rootway.ROOTWAYS[0]
	var f := Rootway.frame(way)
	var kind: String = way["keeper"]
	var found := raid._bosses.filter(func(entry: Dictionary) -> bool:
		return (entry.marker as Node3D).get_meta("boss", "") == kind)
	t.check(found.size() == 1, "the Rootway has its keeper")
	if found.is_empty():
		raid.queue_free()
		return
	var boss: Dictionary = found[0]
	var keeper := boss.bot as Actor
	t.check(keeper != null and keeper.display_name == "The Rootmother" and keeper.rear_damage_mult > 1.5
			and keeper.body_height() > 3.0 and keeper.health.max_health >= 1000.0 and keeper.health.armor > 0.0,
			"the Rootmother waits in the chamber: huge, armored, her back her weak spot")
	t.check(keeper.inventory.items.is_empty(), "she carries nothing: her vault pays")
	var hooks := keeper.get_active_weapon() as MeleeWeapon
	t.check(hooks != null and hooks.light_windup >= 0.5, "her hooks keep a long windup, so they can be parried")
	t.check(int(raid.keepers.get(kind, -1)) == 1, "she starts standing")
	var me := raid.add_player([], {}, "Delver", "delver")
	var mate := raid.add_player([], {}, "Second", "second")
	await t.frames(2)
	for actor: Actor in [me, mate]:
		actor.protected_left = 0.0
	var floor_y := Rootway.CHAMBER_FLOOR + 0.2
	me.global_position = f * Vector3(Rootway.BEND, floor_y, Rootway.CHAMBER_Z - 10.0)
	mate.global_position = f * Vector3(0, Rootway.FLOOR + 0.2, 40.0)
	# Phase one: broodlings out of the wall.
	raid._tick_keeper(boss, marsh.keeper_socket_first + 0.1)
	var adds: Array = boss.adds
	t.check(adds.size() == 1, "with someone in her chamber, a broodling comes out of a root socket")
	if adds.size() == 1:
		var add := adds[0] as Actor
		t.check(add.faction == "broodling" and raid._is_extra(add) and not marsh.can_damage(add, keeper, DamageInfo.new()),
				"a broodling, outside the armies, her own kind")
	# Phase two: the vents.
	var lanes := []
	raid.purge_changed.connect(func(index: int, state: int) -> void: lanes.append([index, state]))
	keeper.health.health = keeper.health.max_health * 0.4
	raid._tick_keeper(boss, 0.05)
	t.check(int(raid.keepers[kind]) == 2, "below half she turns to her spore vents")
	raid._tick_keeper(boss, marsh.keeper_purge_first + 0.05)
	var warned := lanes.filter(func(e: Array) -> bool: return e[1] == 1)
	t.check(warned.size() == marsh.keeper_purges_at_once, "the vents warn first (%d)" % warned.size())
	if not warned.is_empty():
		var lane := raid.purges[int(warned[0][0])]
		t.check(Rootway.inside(lane.global_position + Vector3(0, 1.0, 0)), "on her chamber's floor")
		var to: Vector3 = lane.get_meta("toward")
		me.global_position = lane.global_position.lerp(to, 0.3) + Vector3(0, 0.1, 0)
		var mine := me.health.health
		raid._tick_keeper(boss, marsh.keeper_purge_warn * 0.5)
		t.check(me.health.health == mine, "nothing hurts while a vent only warns")
		raid._tick_keeper(boss, marsh.keeper_purge_warn * 0.6)
		t.check(me.health.health < mine, "then it vents and hurts whoever stands in it")
		raid._tick_keeper(boss, Raid.PURGE_VENT + 0.1)
	# The fall.
	me.global_position = f * Vector3(Rootway.BEND, floor_y, Rootway.CHAMBER_Z - 10.0)
	keeper.kill("test", me)
	raid._tick_bosses(0.1)
	t.check(int(raid.keepers.get(kind, -1)) == 0, "she falls")
	var shares: Array = boss.shares
	var labels := shares.map(func(share: LootContainer) -> String: return share.label)
	t.check(shares.size() == 1 and labels.has("Delver's share"),
			"her vault opens a share for the one in her chamber, none for the one up the throat (%s)" % str(labels))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var relics := 0
	var data := true
	for i in 1000:
		var roll := marsh.roll_vault(kind, rng)
		data = data and roll.has("upgrade_data")
		relics += roll.filter(func(id: String) -> bool: return ItemDB.has_tag(id, "artifact")).size()
	t.check(data and relics > 50 and relics < 300, "a share holds upgrade data and now and then an artifact (%d in 1000)" % relics)
	t.check(float(boss.back_in) == Rootway.RESPAWN, "she comes back on her own timer")
	raid._tick_bosses(Rootway.RESPAWN + 0.1)
	var back: Variant = boss.bot
	t.check(back != null and is_instance_valid(back) and not (back as Actor).is_dead and int(raid.keepers[kind]) == 1
			and (boss.shares as Array).is_empty(), "and wakes again, her vault closed")
	raid.queue_free()
	await t.frames(2)


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD)
	return space.intersect_ray(query)
