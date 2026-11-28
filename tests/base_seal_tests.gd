extends RefCounted
## The `base_seal` checks: the corridor to the range, the starter bunker's
## test lane and the range hall are closed all round in every hub shape,
## whole or in the starter bunker's small form, so no void shows past a
## wall and nobody can walk or jump out (Caleb: "the endless void is on the
## walls of the hallway and you can jump out into it"). The test runner finds
## this file by itself and calls `run(t)`.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BasePlan := preload("res://core/base/base_plan.gd")


static func run(t: Node) -> void:
	print("Home base walls")
	var base := HomeBase.new()
	var gear := ["rifle_carbine"]
	base.show_gear(gear, {"primary": "rifle_carbine"}, [])
	t.add_child(base)
	await t.frames(5)
	var starter: Array[String] = []
	for owned: Array in [starter, BaseUpgrades.full()]:
		var form := "the starter bunker" if owned.is_empty() else "the finished base"
		for shape: String in BasePlan.SHAPES:
			var plan := BasePlan.clean(null)
			plan["shape"] = shape
			base.show_gear(gear, {"primary": "rifle_carbine"}, owned, plan)
			await t.frames(3)
			var where := "%s, %s" % [form, shape]
			var open := _corridor_leaks(base)
			t.check(open.is_empty(), "%s: the corridor to the range has solid walls all along (open at %s)" % [where, open.slice(0, 3)])
			open = _near_wall_leaks(base)
			t.check(open.is_empty(), "%s: the range hall's near wall is solid beside the corridor (open at %s)" % [where, open.slice(0, 3)])
			if owned.is_empty():
				open = _lane_leaks(base)
				t.check(open.is_empty(), "%s: the test lane has solid walls all along (open at %s)" % [where, open.slice(0, 3)])
	base.queue_free()
	await t.frames(2)


## Points along the corridor (local to the base) where a ray sideways, at a
## step's height or a jump's, meets no wall within the corridor's width.
static func _corridor_leaks(base: HomeBase) -> Array:
	var out := []
	var from := base.room_size.z * 0.5 + 0.3
	var to := base.range_from() - 0.3
	var reach := base.corridor.x * 0.5 + 0.7
	var z := from
	while z < to:
		for y: float in [0.6, 2.0, base.corridor.y - 0.2]:
			for side: float in [-1.0, 1.0]:
				# The seventh socket's doorway off the spine's and the ring's corridor.
				if side < 0.0 and HomeBase.corridor_socket(base.hub_shape()) \
						and absf(-z - base.socket_transform("F1").origin.z) < base.room_door.x * 0.5 + 0.1:
					continue
				var at := Vector3(0, y, -z)
				if not _hits(base, at, at + Vector3(side * reach, 0, 0)):
					out.append(Vector3(side, y, -z))
		z += 0.5
	return out


## Points along the range hall's near wall, either side of the corridor,
## where a ray toward the hub from just inside the hall gets out.
static func _near_wall_leaks(base: HomeBase) -> Array:
	var out := []
	var z := -base.range_from() - 0.4
	var half := base.range_size.x * 0.5 - 0.2
	var x := base.corridor.x * 0.5 + 0.3
	while x < half:
		for y: float in [0.6, 3.0, base.socket_size.y - 0.3, base.range_size.y - 0.5]:
			for side: float in [-1.0, 1.0]:
				var at := Vector3(side * x, y, z)
				if not _hits(base, at, at + Vector3(0, 0, 1.2)):
					out.append(at)
		x += 0.5
	return out


## Points along the test lane where a ray sideways gets out.
static func _lane_leaks(base: HomeBase) -> Array:
	var out := []
	var start := base.range_from() + 0.3
	var end := base.range_from() + base.lane_size.z - 0.3
	var reach := base.lane_size.x * 0.5 + 0.7
	var z := start
	while z < end:
		for y: float in [0.6, 2.0, base.lane_size.y - 0.2]:
			for side: float in [-1.0, 1.0]:
				var at := Vector3(0, y, -z)
				if not _hits(base, at, at + Vector3(side * reach, 0, 0)):
					out.append(Vector3(side, y, -z))
		z += 0.5
	return out


## True if a ray from `a` to `b` (local to the base) meets the world.
static func _hits(base: HomeBase, a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(base.to_global(a), base.to_global(b), Actor.LAYER_WORLD)
	query.hit_back_faces = true
	return not base.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
