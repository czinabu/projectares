extends RefCounted
## The `arena_floor` checks. The test runner finds this file by itself and calls
## `run(t)`.
##
## The Pit's floor: cover, tunnels and doors, the rising barriers, the
## ceiling, and bots finding their way round it all.


static func run(t: Node) -> void:
	print("Arena: the floor, tunnels and rising barriers")
	var V := Arena.ArenaVenue
	t.check(V.doors_open("fight", 0.0) and V.doors_open("fight", V.DOOR_OPEN_TIME - 0.1)
			and not V.doors_open("fight", V.DOOR_OPEN_TIME + 0.1) and not V.doors_open("countdown", -1.0),
			"the tunnel doors open as the fight starts and close behind the fighters")
	t.check(V.barrier_raise(0, -1.0) == 1.0 and V.barrier_raise(1, -1.0) == 0.0
			and V.barrier_raise(0, V.BARRIER_PERIOD + V.BARRIER_MOVE) == 0.0
			and V.barrier_raise(1, V.BARRIER_PERIOD + V.BARRIER_MOVE) == 1.0
			and V.barrier_raise(0, V.BARRIER_PERIOD * 2.0 + V.BARRIER_MOVE) == 1.0,
			"the rising barriers take turns, one pair up at a time")
	var mid := V.barrier_raise(1, V.BARRIER_PERIOD + V.BARRIER_MOVE * 0.5)
	t.check(mid > 0.1 and mid < 0.9, "a barrier rises over a moment, not all at once")
	t.check(V.in_tunnel(Vector3(-V.GATE_DISTANCE, 0.1, 0)) and not V.in_pit(Vector3(-V.GATE_DISTANCE, 0.1, 0))
			and not V.in_tunnel(Vector3(0, 0.1, V.GATE_DISTANCE)) and V.in_pit(V.entry_point(1))
			and not V.in_tunnel(Vector3(-V.GATE_DISTANCE, V.WALL_HEIGHT, 0)),
			"each tunnel runs under the stands, apart from the floor and the seats over it")

	var arena: Arena = await t._quick_arena(["ana", "bo"])
	var map := arena.map
	var gates := arena._map_nodes("arena_gate")
	t.check(gates.size() == 2 and gates.all(func(g: Node3D) -> bool: return V.in_tunnel(g.global_position)),
			"both fighters wait in a tunnel")
	var space := map.get_world_3d().direct_space_state
	var gate_line := PhysicsRayQueryParameters3D.create(V.entry_point(0) + Vector3(0, 1.7, 0),
			V.entry_point(1) + Vector3(0, 1.7, 0), Actor.LAYER_WORLD)
	t.check(not space.intersect_ray(gate_line).is_empty(), "cover blocks the line from one gate to the other")
	var up := PhysicsRayQueryParameters3D.create(Vector3(3, 2, 3), Vector3(3, 40, 3), Actor.LAYER_WORLD)
	var lid := space.intersect_ray(up)
	t.check(not lid.is_empty() and absf(lid.position.y - V.CEILING) < 0.2, "a ceiling keeps flight over the floor")
	var meshes := map.find_children("*", "MeshInstance3D", true, false)
	t.check(meshes.size() < 30, "the venue is a handful of meshes, not hundreds of boxes (%d)" % meshes.size())
	var nav: NavigationRegion3D = map.get("nav_region")
	t.check(nav != null and nav.navigation_mesh != null and nav.navigation_mesh.get_polygon_count() > 10,
			"bots get a navigation mesh round the cover")

	# A practice bout: doors shut while the fighters wait, open for the fight,
	# shut again behind them; the barriers follow the clock.
	var ana: Actor = arena.players[0].actor
	arena.request(ana, "practice", {})
	await t._arena_phase(arena, Arena.Phase.COUNTDOWN)
	var door: Node3D = map.get_node("Door0")
	var shut_y := door.position.y
	t.check(V.in_tunnel(ana.global_position), "a fighter is brought in to their tunnel")
	await t._arena_phase(arena, Arena.Phase.FIGHT)
	await t.frames(2)
	t.check(door.position.y < shut_y - 2.0, "the door sinks open when the fight starts")
	arena.phase_left = arena.fight_time - V.DOOR_OPEN_TIME - 0.5
	await t.frames(2)
	t.check(is_equal_approx(door.position.y, shut_y) and V.in_pit(ana.global_position),
			"once the doors close, a fighter still in the tunnel is put on the floor")
	var barriers := t.get_tree().get_nodes_in_group("arena_barrier").filter(func(b: Node) -> bool:
		return map.is_ancestor_of(b))
	var heights := barriers.map(func(b: Node3D) -> float: return b.position.y)
	arena.phase_left = arena.fight_time - V.BARRIER_PERIOD - V.BARRIER_MOVE - 0.2
	await t.frames(2)
	var moved := 0
	for i in barriers.size():
		if absf(barriers[i].position.y - heights[i]) > 1.0:
			moved += 1
	t.check(barriers.size() == 4 and moved == 4, "every rising barrier changes over when the pairs swap")
	arena.queue_free()
	await t.frames(2)
