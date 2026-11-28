extends RefCounted
## `--kit-only`, a mode `visual_check.gd` finds by itself. Ashfront's field
## landmarks clad in kit pieces (`worlds/ashfront/kit_dress.gd`), each from
## the field, near and far: name, from, toward, eye height over the ground,
## aim height over the ground there.

const VIEWS := [
	["forge_far", Vector2(90, 70), Vector2(2, -2), 2.0, 30.0],
	["forge_near", Vector2(28, -4), Vector2(2, -2), 1.7, 12.0],
	["forge_mouth", Vector2(2, 18), Vector2(2, -2), 1.7, 3.0],
	["forge_air", Vector2(-40, -36), Vector2(2, -2), 30.0, 20.0],
	["walls_breach", Vector2(-130, 100), Vector2(-142, 114), 1.7, 2.0],
	["walls_hill", Vector2(-128, -104), Vector2(-150, -118), 3.0, 10.0],
	["carrier_far", Vector2(90, 100), Vector2(134, 132), 2.0, 6.0],
	["carrier_near", Vector2(112, 150), Vector2(134, 128), 1.7, 6.0],
	["carrier_air", Vector2(100, 180), Vector2(134, 132), 28.0, 4.0],
	["wrecks_far", Vector2(118, -80), Vector2(158, -106), 3.0, 2.0],
	["wrecks_near", Vector2(146, -96), Vector2(160, -108), 1.7, 1.5],
	["wrecks_air", Vector2(130, -140), Vector2(158, -106), 25.0, 0.0],
]


static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	# `--kit-only forge` (or any name's start) shoots only those views.
	var only := ""
	for a in args:
		if not a.begins_with("-") and not a.contains("/"):
			only = a
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.visible = false
	raid.player.visible = false
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.far = 3000.0
	raid.add_child(camera)
	camera.make_current()
	var ground := func(x: float, z: float) -> float: return float(raid.map.call("scenery_height", x, z))
	for view: Array in VIEWS:
		if only != "" and not str(view[0]).begins_with(only):
			continue
		var from: Vector2 = view[1]
		var to: Vector2 = view[2]
		var eye := Vector3(from.x, ground.call(from.x, from.y) + float(view[3]), from.y)
		var aim := Vector3(to.x, ground.call(to.x, to.y) + float(view[4]), to.y)
		camera.look_at_from_position(eye, aim)
		await v._settle(40)
		await v._shot(out_dir.path_join("kit_%s.png" % view[0]))
	# A few supply piles, spread through the list, from a few metres off.
	var clutter: Array = raid.map.get("_clutter")
	if only == "" or "clutter".begins_with(only) or only.begins_with("clutter"):
		for n in mini(3, clutter.size()):
			var at: Vector3 = (clutter[n * clutter.size() / 3][1] as Transform3D).origin
			var eye := at + Vector3(6.0, 0.0, 5.0)
			eye.y = ground.call(eye.x, eye.z) + 2.0
			camera.look_at_from_position(eye, at + Vector3(0, 0.8, 0))
			await v._settle(40)
			await v._shot(out_dir.path_join("kit_clutter_%d.png" % n))
	# Up close to one wreck of each kind, from the side.
	var seen := {}
	for wreck: Dictionary in raid.map.get("_wrecks"):
		var kind := int(wreck.get("kind", -1))
		if kind < 0 or seen.has(kind) or (only != "" and not "wreck_kind".begins_with(only) and not only.begins_with("wreck_kind")):
			continue
		seen[kind] = true
		var at: Vector3 = wreck["at"]
		var size: Vector3 = wreck["size"]
		var away := Vector2.from_angle(float(wreck["yaw"]) + 0.7) * (size.length() * 1.1 + 4.0)
		var eye := Vector3(at.x + away.x, ground.call(at.x + away.x, at.z + away.y) + 2.5, at.z + away.y)
		camera.look_at_from_position(eye, at + Vector3(0, size.y * 0.4, 0))
		await v._settle(40)
		await v._shot(out_dir.path_join("kit_wreck_kind%d.png" % kind))
	raid.queue_free()
