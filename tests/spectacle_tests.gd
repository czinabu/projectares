extends RefCounted
## Meridian's spectacle is solid on every machine (docs/systems/arena-and-race.md):
## the server, which draws nothing, builds the same stands, works and fences
## as a client that draws them, shape for shape.


static func run(t: Node) -> void:
	print("Meridian's spectacle")
	var was_on: bool = Look.enabled
	Look.enabled = false
	var bare := await _shapes(t)
	Look.enabled = true
	var drawn := await _shapes(t)
	Look.enabled = was_on
	t.check(bare["count"] > 1000, "the server builds the spectacle's collision (%d shapes)" % bare["count"])
	t.check(bare["count"] == drawn["count"] and bare["sum"].is_equal_approx(drawn["sum"]),
			"and the very same shapes as a client that draws it (%d against %d)" % [bare["count"], drawn["count"]])


## Every spectacle shape the map builds: how many, and where they are summed.
static func _shapes(t: Node) -> Dictionary:
	var map: Node3D = Worlds.get_world("meridian").create_map()
	t.add_child(map)
	await t.frames(1)
	var count := 0
	var sum := Vector3.ZERO
	for body: Node in map.find_children("Spectacle_*", "StaticBody3D", false, false):
		var solid := body as StaticBody3D
		for owner_id: int in solid.get_shape_owners():
			count += 1
			sum += solid.shape_owner_get_transform(owner_id).origin
	map.queue_free()
	await t.frames(1)
	return {"count": count, "sum": sum}
