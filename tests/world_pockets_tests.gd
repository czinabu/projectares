extends RefCounted
## Every world but Ashfront places its enemies in encounter pockets
## (Caleb's call, DESIGN.md "Enemy layout"): no army roams, each pocket is
## one readable group of 1 to 5 at a named place, far enough from the next
## that a fight does not pull two, and each world keeps its own enemy
## budget. Ashfront keeps its war under a bigger budget of its own.

## The least distance between two groups' middles, per world (metres). The
## Marsh's basin is small and its forests close; its lone beasts (a
## hummock's, a lurker's pool) are ambushers and are not counted, nor is a
## pocket under the ground.
const GAP := {"dunes": 80.0, "rift": 80.0, "marsh": 70.0}
## The fewest pockets each world holds: the Rift is one mesa a pocket.
const FEWEST := {"dunes": 12, "rift": 3, "marsh": 12}


static func run(t: Node) -> void:
	print("World pockets")
	for id: String in ["marsh", "dunes", "rift"]:
		_layout(t, Worlds.get_world(id))
	await _budgets(t)


static func _layout(t: Node, world: WorldDef) -> void:
	t.check(world.bot_count == 0 and world.pocket_wake > 0.0 and world.enemy_cap == 12,
			"%s: no army, pockets that wake at %.0f m, a budget of 12" % [world.id, world.pocket_wake])
	var map: Node3D = world.create_map()
	t.add_child(map)
	var pockets := {}
	for marker: Node in map.get_tree().get_nodes_in_group("spawn_guard"):
		if not map.is_ancestor_of(marker):
			continue
		var key := str(marker.get_meta("pocket", "lone%d" % marker.get_instance_id()))
		if not pockets.has(key):
			pockets[key] = []
		(pockets[key] as Array).append((marker as Node3D).global_position)
	var sizes := pockets.values().map(func(spots: Array) -> int: return spots.size())
	t.check(pockets.size() >= int(FEWEST[world.id]) and sizes.all(func(n: int) -> bool: return n >= 1 and n <= 5),
			"%s: %d pockets of 1 to 5 (%s)" % [world.id, pockets.size(), str(sizes)])
	var groups: Array[Vector3] = []
	for key: String in pockets:
		var spots: Array = pockets[key]
		if spots.size() < 2:
			continue
		var mid := Vector3.ZERO
		for at: Vector3 in spots:
			mid += at
		mid /= spots.size()
		# A pocket under the ground (a Rootway's gallery) is walled off from
		# the one over it.
		if mid.y < float(map.call("ground_height", mid.x, mid.z)) - 5.0:
			continue
		groups.append(mid)
	var least := INF
	for i in groups.size():
		for j in range(i + 1, groups.size()):
			var d := Vector2(groups[i].x, groups[i].z).distance_to(Vector2(groups[j].x, groups[j].z))
			least = minf(least, d)
	t.check(least >= float(GAP[world.id]), "%s: the groups stand %.0f m apart at the least (%d groups)" % [world.id, least, groups.size()])
	map.free()


## Under the project's cap each world holds its own budget: 12 in a world of
## pockets, 24 for Ashfront's war.
static func _budgets(t: Node) -> void:
	var kept := Raid.enemy_cap
	Raid.enemy_cap = 8
	for plan: Array in [["ashfront", 24], ["dunes", 12]]:
		var raid := Raid.new()
		t.add_child(raid)
		raid.start(Worlds.get_world(plan[0]), 9)
		await t.frames(2)
		t.check(raid.enemy_budget() == plan[1] and raid.bots.size() <= plan[1],
				"%s holds at most %d enemies (%d now)" % [plan[0], plan[1], raid.bots.size()])
		raid.queue_free()
		await t.frames(2)
	Raid.enemy_cap = kept
	t.check(Worlds.get_world("frostline").enemy_cap == 0, "Frostline keeps the project's cap (its trial)")
