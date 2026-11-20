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
	for i in Rootway.ROOTWAYS.size():
		await _keeper(t, i)
	await _charge(t)
	await _dive(t)


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
	for i in Rootway.ROOTWAYS.size():
		await _built_way(t, raid, marsh, i)
	raid.queue_free()
	await t.frames(2)


## One Rootway as built, `i` in `Rootway.ROOTWAYS`.
static func _built_way(t: Node, raid: Raid, marsh: WorldDef, i: int) -> void:
	var map := raid.map
	var way: Dictionary = Rootway.ROOTWAYS[i]
	var name: String = way["name"]
	print("  %s" % name)
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
	var hole: Rect2 = Rootway.holes()[i]
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
	for step in 600:
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
		return Rootway.way_at((entry.marker as Node3D).global_position + Vector3(0, 1.0, 0)) == i)
	var standing := guards.filter(func(entry: Dictionary) -> bool: return entry.bot != null and raid._is_extra(entry.bot as Actor))
	t.check(guards.size() >= 3 and standing.size() == guards.size(), "a garrison of the marsh's beasts stands guard (%d)" % guards.size())
	var caches: Array = raid._caches.filter(func(c: Dictionary) -> bool:
		return c.source == "rootway" and Rootway.way_at((c.container as Node3D).global_position + Vector3(0, 1.0, 0)) == i)
	t.check(caches.size() >= 2, "its gallery holds caches of its own (%d)" % caches.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var goods := 0
	for roll in 40:
		goods += marsh.roll_loot("rootway", rng).filter(func(id: String) -> bool: return id in ["glowcap", "spore_sac", "chitin_plate"]).size()
	t.check(goods > 40, "they pay the marsh's goods (%d in 40)" % goods)


## A keeper's fight, as the Engine's Heart Warden's runs: the keeper of
## `Rootway.ROOTWAYS[i]`.
static func _keeper(t: Node, i: int) -> void:
	var way: Dictionary = Rootway.ROOTWAYS[i]
	var who: String = way["boss_name"]
	print("Rootways: %s" % who)
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 33)
	await t.frames(2)
	var f := Rootway.frame(way)
	var kind: String = way["keeper"]
	var found := raid._bosses.filter(func(entry: Dictionary) -> bool:
		return (entry.marker as Node3D).get_meta("boss", "") == kind)
	t.check(found.size() == 1, "%s has its keeper" % way["name"])
	if found.is_empty():
		raid.queue_free()
		return
	var boss: Dictionary = found[0]
	var keeper := boss.bot as Actor
	t.check(keeper != null and keeper.display_name == who and (keeper.rear_damage_mult > 1.5 or bool(way["pools"]))
			and keeper.body_height() > 2.5 and keeper.health.max_health >= 1000.0 and keeper.health.armor > 0.0
			and Rootway.way_at(keeper.global_position + Vector3(0, 1.0, 0)) == i,
			"%s waits in the chamber: huge and armored" % who)
	t.check(keeper.inventory.items.is_empty(), "it carries nothing: its vault pays")
	var hooks := keeper.get_active_weapon() as MeleeWeapon
	t.check(hooks != null and hooks.light_windup >= 0.5 and (not hooks.dash_through or hooks.heavy_windup >= 0.8),
			"its strikes keep a long windup, so they can be parried or stepped out of")
	t.check(int(raid.keepers.get(kind, -1)) == 1, "it starts standing")
	var me := raid.add_player([], {}, "Delver", "delver")
	var mate := raid.add_player([], {}, "Second", "second")
	await t.frames(2)
	for actor: Actor in [me, mate]:
		actor.protected_left = 0.0
	var floor_y := Rootway.CHAMBER_FLOOR + 0.2
	me.global_position = f * Vector3(Rootway.BEND, floor_y, Rootway.CHAMBER_Z - 10.0)
	mate.global_position = f * Vector3(0, Rootway.FLOOR + 0.2, 40.0)
	# Phase one: what it calls out of the wall, if anything.
	raid._tick_keeper(boss, marsh.keeper_socket_first + 0.1)
	var adds: Array = boss.adds
	if str(way["adds"]) == "":
		t.check(adds.is_empty(), "%s calls nothing out of the walls: its fight is its own" % who)
	else:
		t.check(adds.size() == 1, "with someone in its chamber, a %s comes out of a root socket" % way["adds"])
	if adds.size() == 1:
		var add := adds[0] as Actor
		t.check(add.faction == str(way["adds"]) and raid._is_extra(add) and not marsh.can_damage(add, keeper, DamageInfo.new()),
				"one of the adds, outside the armies, its own kind")
	# Phase two: the vents.
	var lanes := []
	raid.purge_changed.connect(func(index: int, state: int) -> void: lanes.append([index, state]))
	keeper.health.health = keeper.health.max_health * 0.4
	raid._tick_keeper(boss, 0.05)
	t.check(int(raid.keepers[kind]) == 2, "below half it turns to its spore vents")
	var brain := keeper.get_node("Brain") as BotBrain
	if hooks.dash_through:
		t.check(brain.dash_every < float(keeper.get_meta("dash_every")), "and charges more often (every %.1f s)" % brain.dash_every)
	raid._tick_keeper(boss, marsh.keeper_purge_first + 0.05)
	var warned := lanes.filter(func(e: Array) -> bool: return e[1] == 1)
	t.check(warned.size() == marsh.keeper_purges_at_once, "the vents warn first (%d)" % warned.size())
	if not warned.is_empty():
		var lane := raid.purges[int(warned[0][0])]
		t.check(Rootway.way_at(lane.global_position + Vector3(0, 1.0, 0)) == i, "on its chamber's floor")
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
	t.check(int(raid.keepers.get(kind, -1)) == 0, "it falls")
	var shares: Array = boss.shares
	var labels := shares.map(func(share: LootContainer) -> String: return share.label)
	t.check(shares.size() == 1 and labels.has("Delver's share"),
			"its vault opens a share for the one in its chamber, none for the one up the throat (%s)" % str(labels))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var relics := 0
	var data := true
	for draw in 1000:
		var roll := marsh.roll_vault(kind, rng)
		data = data and roll.has("upgrade_data")
		relics += roll.filter(func(id: String) -> bool: return ItemDB.has_tag(id, "artifact")).size()
	t.check(data and relics > 50 and relics < 300, "a share holds upgrade data and now and then an artifact (%d in 1000)" % relics)
	t.check(float(boss.back_in) == Rootway.RESPAWN, "it comes back on its own timer")
	raid._tick_bosses(Rootway.RESPAWN + 0.1)
	var back: Variant = boss.bot
	t.check(back != null and is_instance_valid(back) and not (back as Actor).is_dead and int(raid.keepers[kind]) == 1
			and (boss.shares as Array).is_empty(), "and wakes again, its vault closed")
	raid.queue_free()
	await t.frames(2)


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD)
	return space.intersect_ray(query)


## The Shellback Elder's charge: it runs its whole length past a player who
## steps aside, rams a snag behind them and is stuck there, its rear open;
## a player who stands is caught and hurt.
static func _charge(t: Node) -> void:
	print("Rootways: the Elder's charge")
	var ways := Rootway.ROOTWAYS.filter(func(way: Dictionary) -> bool: return bool(way["snags"]))
	t.check(not ways.is_empty(), "a Rootway's chamber stands snags for its keeper to ram")
	if ways.is_empty():
		return
	var way: Dictionary = ways[0]
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 35)
	await t.frames(2)
	var f := Rootway.frame(way)
	var boss: Dictionary = raid._bosses.filter(func(entry: Dictionary) -> bool:
		return (entry.marker as Node3D).get_meta("boss", "") == way["keeper"])[0]
	var elder := boss.bot as Actor
	var horns := elder.get_active_weapon() as MeleeWeapon
	t.check(horns.dash_through and horns.dash_range >= 12.0, "the Elder charges: its dash runs its whole length (%.0f m)" % horns.dash_range)
	elder.get_node("Brain").set_physics_process(false)
	var snags := raid._snags.filter(func(snag: Node3D) -> bool: return snag.get_meta("keeper", "") == way["keeper"])
	t.check(snags.size() == Rootway.SNAGS.size() and snags.all(func(snag: Node3D) -> bool:
		return Rootway.way_at(snag.global_position + Vector3(0, 1.0, 0)) == Rootway.ROOTWAYS.find(way)),
			"its chamber stands %d snags" % snags.size())
	var me := raid.add_player([], {}, "Delver", "delver")
	await t.frames(2)
	me.protected_left = 0.0
	me.set_physics_process(false)
	var heard := []
	me.notice.connect(func(text: String) -> void: heard.append(text))
	# Stand before a snag, the Elder 11 m off on the far side, and step aside
	# as it comes.
	var floor_y := Rootway.CHAMBER_FLOOR + 0.1
	var snag_at: Vector2 = Rootway.SNAGS[0]
	var snag := f * Vector3(Rootway.BEND + snag_at.x, floor_y, snag_at.y)
	var toward := (f * Vector3(Rootway.BEND, floor_y, snag_at.y) - snag).normalized()
	me.global_position = snag + toward * 2.2
	elder.global_position = snag + toward * 13.0
	await t.frames(3)
	var run := await _charge_at(t, elder, me)
	me.global_position += f.basis.z * 3.0
	var stuck := false
	for step in 90:
		await t.frames(1)
		if elder.stagger_left > 0.0:
			stuck = true
			break
	var past := elder.global_position.distance_to(snag + toward * 13.0)
	t.check(run and stuck and past > 8.0, "stepped aside, the Elder runs on into the snag behind and is stuck (%.1f m run)" % past)
	t.check(elder.stagger_left > 2.0 and heard.any(func(text: String) -> bool: return "stuck" in text),
			"for seconds, and everyone in its chamber is told to get behind it")
	var front := elder.health.health
	var info := DamageInfo.new()
	info.amount = 40.0
	info.source = me
	info.kind = "melee"
	me.global_position = elder.global_position + (elder.global_position - snag).normalized() * 2.0
	var behind := elder.hit_from_behind(info)
	Combat.deal(elder, info)
	t.check(behind and elder.health.health < front, "stuck facing the roots, its soft rear is turned to the room")
	# In the open, a player who stands is caught.
	await t.frames(1)
	elder.stagger_left = 0.0
	elder.global_position = f * Vector3(Rootway.BEND, floor_y, Rootway.CHAMBER_Z - 6.0)
	me.global_position = f * Vector3(Rootway.BEND, floor_y, Rootway.CHAMBER_Z + 4.0)
	for step in 180:
		if not horns.is_busy():
			break
		await t.frames(1)
	var mine := me.health.health
	await _charge_at(t, elder, me)
	for step in 90:
		await t.frames(1)
		if me.health.health < mine:
			break
	t.check(me.health.health < mine, "a player who stands in its way is caught (%.0f damage)" % (mine - me.health.health))
	# Left to itself, it charges a player across its chamber.
	me.health.health = me.health.max_health
	elder.global_position = f * Vector3(Rootway.BEND, floor_y, Rootway.CHAMBER_Z + 6.0)
	me.global_position = f * Vector3(Rootway.BEND, floor_y, Rootway.CHAMBER_Z - 7.0)
	elder.get_node("Brain").set_physics_process(true)
	elder.heard.emit(me.global_position, me)
	var charged := false
	for step in 900:
		await t.frames(1)
		if horns.is_dashing():
			charged = true
			break
	t.check(charged, "left to itself, it charges a player across its chamber")
	raid.queue_free()
	await t.frames(2)


## Turns the Elder at `foe` and starts a charge from a sprint. True once its
## dash has started.
static func _charge_at(t: Node, elder: Actor, foe: Actor) -> bool:
	var to := foe.global_position - elder.global_position
	to.y = 0.0
	elder.thin(1)
	elder.cmd.yaw = atan2(-to.x, -to.z)
	elder.cmd.aim_dir = to.normalized()
	elder.cmd.sprint = true
	elder.cmd.move = Vector2.ZERO
	await t.frames(1)
	elder.cmd.tertiary_pressed = true
	await t.frames(1)
	var blade := elder.get_active_weapon() as MeleeWeapon
	elder.cmd.tertiary_pressed = false
	elder.cmd.sprint = false
	return (elder.get_active_weapon() as MeleeWeapon).is_dashing()


## The Drowned Lurker's dive: up a while, then under the black water where
## nothing hurts it, then up out of the pool nearest a player, still
## unhurtable while it rises, then open to blades again; hurt, it stays up
## for less; with nobody in its chamber it stays up.
static func _dive(t: Node) -> void:
	print("Rootways: the Drowned Lurker's dive")
	var ways := Rootway.ROOTWAYS.filter(func(way: Dictionary) -> bool: return bool(way["pools"]))
	t.check(not ways.is_empty(), "a Rootway's chamber is flooded, with pools for its keeper to dive into")
	if ways.is_empty():
		return
	var way: Dictionary = ways[0]
	var index := Rootway.ROOTWAYS.find(way)
	var marsh := Worlds.get_world("marsh")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(marsh, 37)
	await t.frames(2)
	var f := Rootway.frame(way)
	var boss: Dictionary = raid._bosses.filter(func(entry: Dictionary) -> bool:
		return (entry.marker as Node3D).get_meta("boss", "") == way["keeper"])[0]
	var lurker := boss.bot as Actor
	var brain := lurker.get_node("Brain") as BotBrain
	var pools := raid._pools.filter(func(pool: Node3D) -> bool: return pool.get_meta("keeper", "") == way["keeper"])
	t.check(pools.size() == Rootway.POOLS.size() and pools.all(func(pool: Node3D) -> bool:
		return Rootway.way_at(pool.global_position + Vector3(0, 1.0, 0)) == index),
			"its chamber has %d pools" % pools.size())
	t.check(not brain.lies_low and brain.leash >= Rootway.ARENA, "it is no ambusher at a post: it follows anyone in its chamber")
	# With nobody in its chamber it stays up.
	raid._tick_keeper(boss, marsh.keeper_dive_up + 0.1)
	t.check(not lurker.submerged, "with nobody in its chamber, it stays up")
	var me := raid.add_player([], {}, "Delver", "delver")
	await t.frames(2)
	me.protected_left = 0.0
	me.set_physics_process(false)
	var floor_y := Rootway.CHAMBER_FLOOR + 0.1
	var far: Vector2 = Rootway.POOLS[4]
	me.global_position = f * Vector3(Rootway.BEND + far.x, floor_y, far.y - 1.0)
	raid._tick_keeper(boss, 0.05)
	raid._tick_keeper(boss, marsh.keeper_dive_up + 0.1)
	t.check(lurker.submerged and brain.held_under, "after a while up, it dives")
	lurker.thin(1)
	for step in 40:
		await t.frames(1)
	t.check(lurker.crouch > 0.5, "down under the water, as every machine sees it (crouch %.2f)" % lurker.crouch)
	var info := DamageInfo.new()
	info.amount = 60.0
	info.source = me
	info.kind = "melee"
	var before := lurker.health.health
	Combat.deal(lurker, info)
	t.check(lurker.health.health == before, "nothing hurts it while it is under")
	var went_down := lurker.global_position
	raid._tick_keeper(boss, marsh.keeper_dive_under + 0.1)
	var nearest: Node3D = pools[0]
	for pool: Node3D in pools:
		if pool.global_position.distance_to(me.global_position) < nearest.global_position.distance_to(me.global_position):
			nearest = pool
	t.check(lurker.global_position.distance_to(nearest.global_position) < 0.5 and lurker.global_position.distance_to(went_down) > 2.0,
			"it rises out of the pool nearest a player, not where it went down")
	t.check(lurker.submerged and brain.held_still and not brain.held_under, "still unhurtable as it rises, and still")
	raid._tick_keeper(boss, marsh.keeper_dive_rise + 0.1)
	before = lurker.health.health
	Combat.deal(lurker, info)
	t.check(not lurker.submerged and not brain.held_still and lurker.health.health < before, "up, it is open to blades again")
	t.check(float((boss.dive as Dictionary).left) == marsh.keeper_dive_up, "and stays up %.0f s" % marsh.keeper_dive_up)
	# Up, it goes for whoever it rose for.
	var mine := me.health.health
	for step in 300:
		await t.frames(1)
		if me.health.health < mine:
			break
	t.check(me.health.health < mine, "and goes straight for the one it rose by (%.0f damage)" % (mine - me.health.health))
	# Hurt below half, it stays up for less.
	lurker.health.health = lurker.health.max_health * 0.4
	raid._tick_keeper(boss, 0.05)
	raid._tick_keeper(boss, marsh.keeper_dive_up + 0.1)
	raid._tick_keeper(boss, marsh.keeper_dive_under + 0.1)
	raid._tick_keeper(boss, marsh.keeper_dive_rise + 0.1)
	t.check(float((boss.dive as Dictionary).left) == marsh.keeper_dive_up_hurt and not lurker.submerged,
			"hurt below half, it stays up only %.0f s" % marsh.keeper_dive_up_hurt)
	raid.queue_free()
	await t.frames(2)
